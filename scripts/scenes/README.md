# 場面練習 audio

`generate-scene-audio.mjs` reads every `Tuji/Resources/Scenes/*.json` and writes one MP3 per 問法 with text and one per 回應 with audio into `Tuji/Resources/Scenes/audio/`. The file name is the `audio` field. All audio is Google Chirp3-HD TTS.

```sh
node scripts/scenes/generate-scene-audio.mjs --dry-run   # list jobs as new / changed / unchanged
node scripts/scenes/generate-scene-audio.mjs             # generate, then validate every file
```

Options: `--scenes <dir>`, `--out <dir>`, `--ambience <file>`, `--limit N`, `--dry-run`.

Needs Node 20 or later, plus `ffmpeg` and `ffprobe` on `PATH`. The key comes from `GOOGLE_TTS_API_KEY`. When that is empty, the script reads the same variable from `tuji-web/.env.local` in a parent directory. Dry runs need no key.

`audio/manifest.json` records a digest of text, voice, speaking rate and ambience source for each file. A rerun regenerates only files whose inputs changed or whose bytes no longer match. After generating, every file must decode and last 0.4 to 8 seconds, or the script exits non-zero with the list. Two scene entries that share an `audio` name with different inputs are an error before any API call.

`speed: "fast"` is speaking rate 1.25. `ambience: true` mixes a store bed about 18 dB under the voice, with 0.4 s of bed before and after, as mono 80 kbps MP3.

**`ambience-placeholder.mp3` is a synthetic placeholder, not a store recording.** `make-ambience-placeholder.sh` builds it from filtered noise and two faint beeps. Before release, replace it with a licensed recording via `--ambience <file>` (or by overwriting the file). The digest includes the ambience file's hash, so every ambience MP3 regenerates on the next run.

`fixtures/fixture-konbini.json` is a two-question scene for testing the script. Point `--out` at a scratch directory when you run it so its MP3s stay out of git.
