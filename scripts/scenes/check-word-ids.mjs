#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");

function fail(lines) {
  for (const line of lines) console.error(line);
  process.exit(1);
}

function releaseBaseURL() {
  const config = fs.readFileSync(path.join(repoRoot, "Config/Release.xcconfig"), "utf8");
  const match = config.match(/^TUJI_BASE_URL\s*=\s*(\S+)/m);
  if (!match) fail(["TUJI_BASE_URL not found in Config/Release.xcconfig"]);
  return match[1].replace("$()", "");
}

const { values: args } = parseArgs({
  options: {
    scenes: { type: "string", default: path.join(repoRoot, "Tuji/Resources/Scenes") },
    base: { type: "string" },
  },
});
const scenesDir = path.resolve(args.scenes);
const base = args.base ?? releaseBaseURL();

const files = fs.readdirSync(scenesDir).filter((f) => f.endsWith(".json")).sort();
if (!files.length) fail([`no scene JSON files in ${scenesDir}`]);

const url = `${base}/api/words?lang=zh-Hant&learning=zh-ja`;
const response = await fetch(url);
if (!response.ok) fail([`GET ${url} -> ${response.status}`]);
const { words } = await response.json();
const byId = new Map(words.map((w) => [w.id, w]));
console.log(`${url}: ${words.length} words`);

const missing = [];
for (const file of files) {
  const scene = JSON.parse(fs.readFileSync(path.join(scenesDir, file), "utf8"));
  for (const question of scene.questions) {
    for (const id of question.wordIds) {
      const word = byId.get(id);
      if (word) {
        console.log(`ok       ${question.id}  ${id}  [${word.category}]  ${word.word}`);
      } else {
        console.log(`MISSING  ${question.id}  ${id}`);
        missing.push(`${question.id}: ${id}`);
      }
    }
  }
}

if (missing.length) fail([`${missing.length} word id(s) not in production:`, ...missing]);
