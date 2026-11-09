#!/usr/bin/env node
// Checks scene JSON the way the app does, without Xcode, so a content writer
// can check a draft in a second. The authority is Swift: the decoders in
// Tuji/Core/Scenes and TujiTests/SceneContentTests.swift. This file mirrors
// them; when a test changes, change the matching check here.
//
//   node scripts/scenes/validate-scenes.mjs [--dir <path>] [--words <tsv>]

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");

const { values: args } = parseArgs({
  options: {
    dir: { type: "string", default: path.join(repoRoot, "Tuji/Resources/Scenes") },
    words: { type: "string" },
  },
});
const dir = path.resolve(args.dir);

const SCHEMA_VERSION = 2;
const QUESTIONS_PER_SCENE = { min: 5, max: 7 };
const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const BLANK = /^[\t\p{Zs}]*$/u;

const problems = [];
const problem = (where, message) => problems.push(`${where}: ${message}`);

const isString = (v) => typeof v === "string";
const isAbsent = (v) => v === undefined || v === null;

function checkEnum(where, field, value, allowed) {
  if (!allowed.includes(value)) problem(where, `${field} must be one of ${allowed.join(" | ")}, got ${JSON.stringify(value)}`);
}

function checkLocalized(where, field, value) {
  if (typeof value !== "object" || value === null) return problem(where, `${field} must be { zh-Hant, zh-Hans, en }`);
  for (const key of ["zh-Hant", "zh-Hans", "en"]) {
    if (!isString(value[key])) problem(where, `${field}.${key} missing`);
    else if (BLANK.test(value[key])) problem(where, `${field}.${key} is empty`);
  }
}

function checkScreen(where, screen, question) {
  if (typeof screen !== "object" || Array.isArray(screen)) {
    return problem(where, `screen must be an object { heading, detail?, buttons }, got ${JSON.stringify(screen)}`);
  }
  if (!isString(screen.heading) || screen.heading === "") problem(where, "screen.heading missing or empty");
  if (!isAbsent(screen.detail) && (!isString(screen.detail) || screen.detail === "")) {
    problem(where, "screen.detail must be a non-empty string or left out");
  }
  if (!Array.isArray(screen.buttons)) return problem(where, "screen.buttons must be an array");
  for (const [i, b] of screen.buttons.entries()) {
    if (!isString(b?.choiceId)) problem(where, `screen.buttons[${i}].choiceId missing`);
    if (!isString(b?.ja) || b.ja === "") problem(where, `screen.buttons[${i}].ja missing or empty`);
  }
  if (!Array.isArray(question.choices)) return;
  const choiceIds = new Set(question.choices.map((c) => c?.id));
  const buttonIds = screen.buttons.map((b) => b?.choiceId);
  if (buttonIds.length !== choiceIds.size) {
    problem(where, `screen has ${buttonIds.length} buttons for ${choiceIds.size} choices; need one button per choice`);
  }
  const buttonSet = new Set(buttonIds);
  const missing = [...choiceIds].filter((id) => !buttonSet.has(id));
  const extra = [...buttonSet].filter((id) => !choiceIds.has(id));
  if (missing.length) problem(where, `screen has no button for choice ${missing.join(", ")}`);
  if (extra.length) problem(where, `screen button ${extra.join(", ")} is not a choice id`);
}

function checkPhrasing(question, p) {
  const where = p?.id ?? `${question.id}.phrasings[?]`;
  if (!isString(p?.id)) return problem(where, "phrasing id missing");
  checkEnum(where, "role", p.role, ["first", "review"]);
  checkEnum(where, "speaker", p.speaker, ["clerk", "staff", "register", "screen"]);
  checkEnum(where, "speed", p.speed, ["normal", "fast"]);
  if (typeof p.ambience !== "boolean") problem(where, "ambience must be true or false");
  const spoken = [p.text, p.voice, p.audio];
  const set = spoken.filter((v) => !isAbsent(v));
  if (set.some((v) => !isString(v))) problem(where, "text, voice and audio must be strings or null");
  if (set.length !== 0 && set.length !== 3) problem(where, "text, voice and audio must be all set or all null");
  const isSpoken = set.length === 3;
  if (!isAbsent(p.screen)) checkScreen(where, p.screen, question);
  if (question.kind === "listening") {
    if (!isSpoken) problem(where, "a listening phrasing needs text, voice and audio");
    if (!isAbsent(p.screen)) problem(where, "a listening phrasing has no screen");
  } else if (question.kind === "screen" && isAbsent(p.screen)) {
    problem(where, "a screen phrasing needs a screen");
  }
  if (isSpoken && p.audio !== `${p.id}.mp3`) problem(where, `audio must be ${p.id}.mp3, got ${p.audio}`);
}

function checkQuestion(scene, q, ids) {
  const where = q?.id ?? `${scene.id}.questions[?]`;
  if (!isString(q?.id)) return problem(where, "question id missing");
  if (!q.id.startsWith(`${scene.id}.`)) problem(where, `question id must start with ${scene.id}.`);
  if (ids.questions.has(q.id)) problem(where, "duplicate question id");
  ids.questions.add(q.id);
  checkEnum(where, "kind", q.kind, ["listening", "screen"]);
  checkLocalized(where, "goal", q.goal);
  checkLocalized(where, "explanation", q.explanation);

  const phrasings = Array.isArray(q.phrasings) ? q.phrasings : (problem(where, "phrasings must be an array"), []);
  for (const p of phrasings) {
    if (isString(p?.id)) {
      if (!p.id.startsWith(`${q.id}.`)) problem(p.id, `phrasing id must start with ${q.id}.`);
      if (ids.phrasings.has(p.id)) problem(p.id, "duplicate phrasing id");
      ids.phrasings.add(p.id);
    }
    checkPhrasing(q, p);
    if (p?.speaker === "register" && isString(p.voice)) ids.registerVoices.add(p.voice);
  }
  const firsts = phrasings.filter((p) => p?.role === "first");
  const reviews = phrasings.filter((p) => p?.role === "review");
  if (phrasings.length < 3) problem(where, `needs at least 3 phrasings, has ${phrasings.length}`);
  if (firsts.length !== 1) problem(where, `needs exactly 1 first phrasing, has ${firsts.length}`);
  if (reviews.length < 2) problem(where, `needs at least 2 review phrasings, has ${reviews.length}`);
  if (!reviews.some((p) => p.speed === "fast" && p.ambience === true)) {
    problem(where, "needs a review phrasing with speed fast and ambience true");
  }
  const firstVoice = firsts[0]?.voice;
  if (isString(firstVoice)) {
    for (const r of reviews) {
      if ((r.speaker === "clerk" || r.speaker === "staff") && r.voice === firstVoice) problem(r.id, `review clerk voice must differ from first phrasing's ${firstVoice}`);
    }
  }

  const choices = Array.isArray(q.choices) ? q.choices : (problem(where, "choices must be an array"), []);
  if (choices.length < 3 || choices.length > 4) problem(where, `needs 3 or 4 choices, has ${choices.length}`);
  const correct = choices.filter((c) => c?.correct === true).length;
  if (correct !== 1) problem(where, `needs exactly 1 correct choice, has ${correct}`);
  if (new Set(choices.map((c) => c?.id)).size !== choices.length) problem(where, "choice ids repeat");
  for (const [i, c] of choices.entries()) {
    if (!isString(c?.id)) problem(where, `choices[${i}].id missing`);
    if (typeof c?.correct !== "boolean") problem(where, `choices[${i}].correct must be true or false`);
    checkLocalized(where, `choices[${i}].text`, c?.text);
  }

  const r = q.response;
  if (!isString(r?.ja)) problem(where, "response.ja missing");
  else if (r.ja === "") problem(where, "response.ja is empty");
  if (isAbsent(r?.audio) !== isAbsent(r?.voice)) problem(where, "response audio and voice must be both set or both null");
  if (!isAbsent(r?.audio) && r.audio !== `${q.id}.response.mp3`) {
    problem(where, `response audio must be ${q.id}.response.mp3, got ${r.audio}`);
  }

  if (!Array.isArray(q.wordIds)) problem(where, "wordIds must be an array");
  else {
    if (new Set(q.wordIds).size !== q.wordIds.length) problem(where, "wordIds repeat");
    for (const id of q.wordIds) {
      if (!isString(id) || !KEBAB.test(id)) problem(where, `word id ${JSON.stringify(id)} is not kebab-case`);
    }
  }
}

function checkScene(file, scene, ids) {
  const where = file;
  if (scene.schemaVersion !== SCHEMA_VERSION) problem(where, `schemaVersion must be ${SCHEMA_VERSION}, got ${scene.schemaVersion}`);
  if (scene.id !== path.basename(file, ".json")) problem(where, `id ${JSON.stringify(scene.id)} must match the file name`);
  if (!Number.isInteger(scene.revision)) problem(where, "revision must be an integer");
  checkEnum(where, "access", scene.access, ["free", "lifetime"]);
  checkLocalized(where, "title", scene.title);
  checkLocalized(where, "summary", scene.summary);
  if (!Array.isArray(scene.questions)) return problem(where, "questions must be an array");
  if (scene.questions.length < QUESTIONS_PER_SCENE.min || scene.questions.length > QUESTIONS_PER_SCENE.max) {
    problem(where, `needs ${QUESTIONS_PER_SCENE.min}-${QUESTIONS_PER_SCENE.max} questions, has ${scene.questions.length}`);
  }
  for (const q of scene.questions) checkQuestion(scene, q, ids);
}

function readJSON(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    problem(path.basename(file), error.message);
    return null;
  }
}

if (!fs.existsSync(dir)) {
  console.error(`${dir}: no such directory`);
  process.exit(1);
}
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".json") && f !== "index.json").sort();
if (!files.length) problem(dir, "no scene JSON files");

const indexFile = path.join(dir, "index.json");
if (fs.existsSync(indexFile)) {
  const index = readJSON(indexFile);
  const groups = index?.groups;
  const groupsOk = Array.isArray(groups) && groups.every((g) => isString(g?.id) && Array.isArray(g?.scenes) && g.scenes.every(isString));
  if (!groupsOk) problem("index.json", "groups must be an array of { id, title, scenes: [scene id] }");
  for (const g of groupsOk ? groups : []) checkLocalized(`index.json ${g.id}`, "title", g.title);
  const listed = groupsOk ? groups.flatMap((g) => g.scenes) : null;
  const released = index?.released;
  if (!Array.isArray(released) || !released.every(isString)) problem("index.json", "released must be an array of scene ids");
  else for (const id of released) if (listed && !listed.includes(id)) problem("index.json", `released ${id} is not in any group`);
  if (listed) {
    if (new Set(listed).size !== listed.length) problem("index.json", "an id is listed twice");
    for (const id of listed) if (!files.includes(`${id}.json`)) problem("index.json", `${id} is listed but ${id}.json is missing`);
    for (const f of files) if (!listed.includes(path.basename(f, ".json"))) problem("index.json", `${f} is not listed`);
  }
} else if (path.resolve(dir) === path.join(repoRoot, "Tuji/Resources/Scenes")) {
  problem("index.json", "missing");
}

const ids = { questions: new Set(), phrasings: new Set(), registerVoices: new Set() };
const scenes = [];
for (const file of files) {
  const scene = readJSON(path.join(dir, file));
  if (scene === null) continue;
  scenes.push(scene);
  checkScene(file, scene, ids);
}
if (ids.registerVoices.size > 1) problem("register", `announcements must use one voice, found ${[...ids.registerVoices].join(", ")}`);

const questions = scenes.flatMap((s) => (Array.isArray(s.questions) ? s.questions : []));

const audioDir = path.join(dir, "audio");
const clips = fs.existsSync(audioDir) ? new Set(fs.readdirSync(audioDir).filter((f) => f.endsWith(".mp3"))) : new Set();
if (clips.size) {
  for (const q of questions) {
    const referenced = [...(q.phrasings ?? []).map((p) => p?.audio), q.response?.audio].filter(isString);
    for (const file of referenced) if (!clips.has(file)) problem(q.id, `missing clip ${file}`);
  }
}

if (args.words) {
  const known = new Set(
    fs.readFileSync(args.words, "utf8").split("\n").map((line) => line.split("\t")[0].trim()).filter(Boolean),
  );
  for (const q of questions) {
    for (const id of Array.isArray(q.wordIds) ? q.wordIds : []) {
      if (!known.has(id)) problem(q.id, `word id ${id} is not in ${path.basename(args.words)}`);
    }
  }
}

if (problems.length) {
  for (const line of problems) console.log(line);
  process.exit(1);
}
console.log(`ok ${scenes.length} scenes, ${questions.length} questions`);
