#!/usr/bin/env node
import { execFileSync, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const webEnvFile = (() => {
  for (let dir = repoRoot; dir !== path.dirname(dir); dir = path.dirname(dir)) {
    const candidate = path.join(dir, "tuji-web/.env.local");
    if (fs.existsSync(candidate)) return candidate;
  }
  return "tuji-web/.env.local (not found above the repo)";
})();

const RATES = { normal: 1.0, fast: 1.25 };
const LEAD_SEC = 0.4;
const AMBIENCE_DB_BELOW_VOICE = 18;
// Bump when the mix recipe changes so every ambience file regenerates.
const MIX_VERSION = "mix-v1";
const MIN_SEC = 0.4;
const MAX_SEC = 8;

const { values: args } = parseArgs({
  options: {
    scenes: { type: "string", default: path.join(repoRoot, "Tuji/Resources/Scenes") },
    out: { type: "string" },
    ambience: { type: "string", default: path.join(scriptDir, "ambience-placeholder.mp3") },
    "dry-run": { type: "boolean", default: false },
    limit: { type: "string" },
  },
});
const scenesDir = path.resolve(args.scenes);
const outDir = path.resolve(args.out ?? path.join(scenesDir, "audio"));
const ambienceFile = path.resolve(args.ambience);
const manifestFile = path.join(outDir, "manifest.json");
const limit = args.limit === undefined ? Infinity : Number(args.limit);
if (!(limit > 0 && Number.isInteger(limit) || limit === Infinity)) {
  fail(["--limit must be a positive integer"]);
}

function fail(lines) {
  for (const line of lines) console.error(line);
  process.exit(1);
}

const sha256 = (data) => crypto.createHash("sha256").update(data).digest("hex");

function loadJobs() {
  const files = fs.existsSync(scenesDir)
    ? fs.readdirSync(scenesDir).filter((f) => f.endsWith(".json") && f !== "index.json").sort()
    : [];
  if (!files.length) fail([`no scene JSON files in ${scenesDir}`]);

  const ambienceHash = fs.existsSync(ambienceFile)
    ? sha256(fs.readFileSync(ambienceFile))
    : null;
  const jobs = new Map();
  const errors = [];

  const add = (source, { audio, text, voice, speed, ambience }) => {
    if (typeof audio !== "string" || !audio.endsWith(".mp3") || audio.includes("/")) {
      return errors.push(`${source}: audio must be a bare .mp3 filename, got ${JSON.stringify(audio)}`);
    }
    if (typeof text !== "string" || !text.trim()) return errors.push(`${source}: text is empty`);
    if (typeof voice !== "string" || !voice) return errors.push(`${source}: voice is missing`);
    if (!(speed in RATES)) return errors.push(`${source}: unknown speed ${JSON.stringify(speed)}`);
    if (ambience && !ambienceHash) return errors.push(`${source}: ambience requested but ${ambienceFile} is missing`);
    const job = {
      audio,
      text,
      voice: `ja-JP-Chirp3-HD-${voice}`,
      rate: RATES[speed],
      ambience: Boolean(ambience),
    };
    job.digest = sha256(
      JSON.stringify([job.text, job.voice, job.rate, job.ambience ? `${MIX_VERSION}:${ambienceHash}` : null]),
    );
    const existing = jobs.get(audio);
    if (!existing) return jobs.set(audio, { ...job, sources: [source] });
    existing.sources.push(source);
    if (existing.digest !== job.digest) {
      errors.push(`${audio} is referenced with different inputs by ${existing.sources.join(", ")}`);
    }
  };

  for (const file of files) {
    let scene;
    try {
      scene = JSON.parse(fs.readFileSync(path.join(scenesDir, file), "utf8"));
    } catch (error) {
      errors.push(`${file}: ${error.message}`);
      continue;
    }
    for (const question of scene.questions ?? []) {
      for (const p of question.phrasings ?? []) {
        if (p.text == null && p.audio == null) continue;
        add(`${file}:${p.id}`, p);
      }
      const r = question.response;
      if (r?.audio != null) {
        add(`${file}:${question.id}.response`, {
          audio: r.audio,
          text: r.ja,
          voice: r.voice,
          speed: "normal",
          ambience: false,
        });
      }
    }
  }
  if (errors.length) fail(["scene input errors:", ...errors.map((e) => `  ${e}`)]);
  return [...jobs.values()];
}

function readManifest() {
  if (!fs.existsSync(manifestFile)) return { schemaVersion: 1, files: {} };
  return JSON.parse(fs.readFileSync(manifestFile, "utf8"));
}

function writeManifest(manifest) {
  const sorted = Object.fromEntries(Object.entries(manifest.files).sort(([a], [b]) => a.localeCompare(b)));
  const temp = `${manifestFile}.${process.pid}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify({ ...manifest, files: sorted }, null, 2)}\n`);
  fs.renameSync(temp, manifestFile);
}

function isCurrent(job, entry) {
  if (entry?.digest !== job.digest) return false;
  const file = path.join(outDir, job.audio);
  return fs.existsSync(file) && sha256(fs.readFileSync(file)) === entry.sha256;
}

function loadApiKey() {
  const fromEnv = process.env.GOOGLE_TTS_API_KEY?.trim();
  if (fromEnv) return fromEnv;
  if (!fs.existsSync(webEnvFile)) return null;
  const line = fs
    .readFileSync(webEnvFile, "utf8")
    .split("\n")
    .find((l) => /^\s*(export\s+)?GOOGLE_TTS_API_KEY\s*=/.test(l));
  return line?.split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "") || null;
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function synthesize(job, apiKey) {
  const body = {
    input: { text: job.text },
    voice: { languageCode: "ja-JP", name: job.voice },
    audioConfig: { audioEncoding: "MP3", speakingRate: job.rate },
  };
  for (let attempt = 1; ; attempt++) {
    const response = await fetch("https://texttospeech.googleapis.com/v1/text:synthesize", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Goog-Api-Key": apiKey },
      body: JSON.stringify(body),
    });
    if (response.ok) {
      const bytes = Buffer.from((await response.json()).audioContent ?? "", "base64");
      if (bytes.length < 256) throw new Error("TTS returned an empty audio payload");
      return bytes;
    }
    const detail = (await response.text().catch(() => "")).slice(0, 200);
    if (attempt === 3 || ![429, 500, 502, 503, 504].includes(response.status)) {
      throw new Error(`TTS HTTP ${response.status}: ${detail}`);
    }
    await wait(attempt * 5000);
  }
}

function probeDuration(file) {
  const out = execFileSync(
    "ffprobe",
    ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file],
    { encoding: "utf8" },
  );
  return Number(out.trim());
}

function volumedetect(file) {
  const { stderr } = spawnSync(
    "ffmpeg",
    ["-hide_banner", "-nostats", "-i", file, "-af", "volumedetect", "-f", "null", "-"],
    { encoding: "utf8" },
  );
  const match = stderr?.match(/mean_volume:\s*(-?[\d.]+) dB/);
  if (!match) throw new Error(`could not measure loudness of ${file}`);
  return Number(match[1]);
}

let ambienceMeanDb;
function mixAmbience(voiceFile, outFile) {
  ambienceMeanDb ??= volumedetect(ambienceFile);
  const voiceDb = volumedetect(voiceFile);
  const gainDb = voiceDb - AMBIENCE_DB_BELOW_VOICE - ambienceMeanDb;
  const total = (probeDuration(voiceFile) + 2 * LEAD_SEC).toFixed(3);
  const leadMs = Math.round(LEAD_SEC * 1000);
  const filter = [
    `[0:a]aformat=channel_layouts=mono,adelay=${leadMs}:all=1,apad=whole_dur=${total}[v]`,
    `[1:a]aformat=channel_layouts=mono,atrim=0:${total},volume=${gainDb.toFixed(2)}dB,` +
      `afade=t=in:d=0.25,afade=t=out:st=${(total - 0.3).toFixed(3)}:d=0.3[a]`,
    `[v][a]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[m]`,
  ].join(";");
  execFileSync("ffmpeg", [
    "-v", "error", "-y",
    "-i", voiceFile,
    "-stream_loop", "-1", "-i", ambienceFile,
    "-filter_complex", filter,
    "-map", "[m]", "-ac", "1", "-ar", "24000", "-c:a", "libmp3lame", "-b:a", "80k",
    outFile,
  ]);
}

function validate(jobs) {
  const problems = [];
  for (const job of jobs) {
    const file = path.join(outDir, job.audio);
    if (!fs.existsSync(file)) {
      problems.push(`${job.audio}: missing`);
      continue;
    }
    try {
      execFileSync("ffmpeg", ["-v", "error", "-i", file, "-f", "null", "-"], { stdio: ["ignore", "ignore", "pipe"] });
      const sec = probeDuration(file);
      if (!(sec >= MIN_SEC && sec <= MAX_SEC)) problems.push(`${job.audio}: duration ${sec}s outside ${MIN_SEC}-${MAX_SEC}s`);
    } catch (error) {
      problems.push(`${job.audio}: does not decode (${String(error.stderr ?? error.message).trim().slice(0, 160)})`);
    }
  }
  return problems;
}

const jobs = loadJobs();
const manifest = readManifest();
const selected = jobs.slice(0, limit);
const pending = selected.filter((job) => !isCurrent(job, manifest.files[job.audio]));

if (args["dry-run"]) {
  for (const job of selected) {
    const state = pending.includes(job) ? (manifest.files[job.audio] ? "changed" : "new") : "unchanged";
    const flags = [job.rate === 1 ? "normal" : `rate ${job.rate}`, job.ambience ? "ambience" : null].filter(Boolean);
    console.log(`${state.padEnd(9)} ${job.audio}  ${job.voice}  ${flags.join(", ")}  ${job.text}`);
  }
  console.log(`\n${jobs.length} jobs, ${selected.length} selected, ${pending.length} to generate (dry run, nothing written)`);
  process.exit(0);
}

const apiKey = pending.length ? loadApiKey() : null;
if (pending.length && !apiKey) fail([`GOOGLE_TTS_API_KEY is not set and not found in ${webEnvFile}`]);
fs.mkdirSync(outDir, { recursive: true });
const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "scene-audio-"));
const failures = [];

try {
  for (const [index, job] of selected.entries()) {
    const tag = `[${index + 1}/${selected.length}]`;
    if (!pending.includes(job)) {
      console.log(`${tag} skip ${job.audio}`);
      continue;
    }
    try {
      const raw = path.join(workDir, `raw-${job.audio}`);
      fs.writeFileSync(raw, await synthesize(job, apiKey));
      const staged = path.join(workDir, job.audio);
      if (job.ambience) mixAmbience(raw, staged);
      else fs.copyFileSync(raw, staged);
      const target = path.join(outDir, job.audio);
      fs.copyFileSync(staged, `${target}.tmp`);
      fs.renameSync(`${target}.tmp`, target);
      const bytes = fs.readFileSync(target);
      manifest.files[job.audio] = {
        digest: job.digest,
        sha256: sha256(bytes),
        text: job.text,
        voice: job.voice,
        rate: job.rate,
        ambience: job.ambience ? path.basename(ambienceFile) : null,
        bytes: bytes.length,
        durationSec: Number(probeDuration(target).toFixed(3)),
      };
      writeManifest(manifest);
      console.log(`${tag} generated ${job.audio} (${manifest.files[job.audio].durationSec}s)`);
      await wait(150);
    } catch (error) {
      failures.push(`${job.audio}: ${error.message}`);
      console.error(`${tag} failed ${job.audio}: ${error.message}`);
    }
  }
} finally {
  fs.rmSync(workDir, { recursive: true, force: true });
}

const referenced = new Set(jobs.map((j) => j.audio));
for (const name of Object.keys(manifest.files)) if (!referenced.has(name)) delete manifest.files[name];
writeManifest(manifest);

const problems = [...failures, ...validate(selected)];
const generatedCount = pending.length - failures.length;
console.log(`\n${selected.length} jobs: ${generatedCount} generated, ${selected.length - pending.length} skipped, ${problems.length} problems`);
if (problems.length) fail(["validation failed:", ...[...new Set(problems)].map((p) => `  ${p}`)]);
