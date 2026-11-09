# 場面練習 audio

`generate-scene-audio.mjs` reads every `Tuji/Resources/Scenes/*.json` and writes one MP3 per 問法 with text and one per 回應 with audio into `Tuji/Resources/Scenes/audio/`. The file name is the `audio` field. All audio is Google Chirp3-HD TTS.

```sh
node scripts/scenes/generate-scene-audio.mjs --dry-run   # list jobs as new / changed / unchanged
node scripts/scenes/generate-scene-audio.mjs             # generate, then validate every file
```

Options: `--scenes <dir>`, `--out <dir>`, `--ambience <file>`, `--limit N`, `--dry-run`.

Needs Node 20 or later, plus `ffmpeg` and `ffprobe` on `PATH`. The key comes from `GOOGLE_TTS_API_KEY`. When that is empty, the script reads the same variable from `tuji-web/.env.local` in a parent directory. Dry runs need no key.

`audio/manifest.json` records a digest of text, voice, speaking rate and ambience source for each file. A rerun regenerates only files whose inputs changed or whose bytes no longer match. After generating, every file must decode and last 0.3 to 8 seconds (a bare 「はい」 is about 0.35 s), or the script exits non-zero with the list. Two scene entries that share an `audio` name with different inputs are an error before any API call.

`speed: "fast"` is speaking rate 1.25. `ambience: true` mixes a store bed about 18 dB under the voice, with 0.4 s of bed before and after, as mono 80 kbps MP3.

**`ambience-placeholder.mp3` is a synthetic placeholder, not a store recording.** `make-ambience-placeholder.sh` builds it from filtered noise and two faint beeps. Before release, replace it with a licensed recording via `--ambience <file>` (or by overwriting the file). The digest includes the ambience file's hash, so every ambience MP3 regenerates on the next run.

`fixtures/fixture-konbini.json` is a two-question scene for testing the script. Point `--out` at a scratch directory when you run it so its MP3s stay out of git.

## Word ids

`node scripts/scenes/check-word-ids.mjs` checks every 問句's `wordIds` against the production 日文圖鑑 (`/api/words`, host from `Config/Release.xcconfig`). It prints each id with its topic and exits non-zero listing any id that does not exist. Run it after editing `wordIds`. Options: `--scenes <dir>`, `--base <url>`.

## Checking a scene

`node scripts/scenes/validate-scenes.mjs` checks every scene JSON against the same rules as `TujiTests/SceneContentTests.swift`, in about a second and without Xcode. It prints one line per problem and exits 1, or prints `ok N scenes, M questions`. Use `--dir <path>` for a folder of drafts and `--words <tsv>` (one word id per line in the first tab-separated column) to check `wordIds` against a word list. The Swift tests stay the authority. When one changes, change the matching check in the script.

A new scene is `<id>.json` in `Tuji/Resources/Scenes/` plus its id in `index.json`, which sets the order the app lists scenes in. A screen 問法 writes its screen out in full. Each button's `choiceId` is one of the question's choice ids, one button per choice:

```json
"screen": {
  "heading": "お支払い方法を選択してください",
  "detail": "合計 ¥1,280",
  "buttons": [
    { "choiceId": "cash", "ja": "現金" },
    { "choiceId": "credit", "ja": "クレジット" }
  ]
}
```

`detail` is optional.
