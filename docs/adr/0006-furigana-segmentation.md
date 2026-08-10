# Furigana is split on the server, against a dictionary

Japanese headwords now carry their kana over the characters those kana read, rather than
on a line underneath. Which kana belong to which kanji is a fact no rule derives from the
data we had — はみがきこ does not say that 歯 is は — so it comes from **JmdictFurigana**
(a per-character furigana dataset derived from JMdict), consulted on the server and stored
as `reading_segments` beside `reading`. The app receives the split and draws it; it holds
no dictionary and runs no alignment.

## Why a dictionary and not the model we already pay for

The enrichment pipeline could be asked to divide a reading among a word's kanji, and would
usually answer plausibly. The difference is that a dictionary lookup can be *checked*: we
already hold the whole reading, so a proposed split is accepted only if its pieces
concatenate back to exactly that string and leave the headword's own kana untouched. A
model's answer satisfies the same arithmetic while being wrong — 時計 divides tidily into
時=と and 計=けい, and both halves are inventions. Over the catalogue the dictionary path
resolves 237 of 249 kanji-bearing words per character, 11 with at least one indivisible
block, and 1 not at all.

This is also the second time this project has learned that a model cannot be the authority
on Japanese readings; see `lib/ja-reading-overrides.ts` and the 2026-08 repair.

## Why the split is a range, not a character

熟字訓 have no per-character reading: 時計 is とけい as a unit. JmdictFurigana itself emits
such blocks, so a per-character format could not represent its own source. Ranges also make
run-level grouping — the coarser thing we would fall back to without a dictionary — the
same shape rather than a separate one.

## Why the 圖鑑 grid keeps its reading line

A correctly proportioned ruby is half the base size. The grid sets headwords in `tujiH3`
(18pt), so its ruby would be 9pt — inside the range `TujiFont.swift` removed on purpose,
because CJK strokes merge there. Ruby at a legible 13pt over an 18pt base is nearly the
size of the word it annotates. Neither is worth having, and the grid's job is recognising a
word rather than reading it, so ruby is confined to the display-size screens.

## Consequences

- **An attribution obligation.** JMdict and JmdictFurigana are Creative Commons
  Attribution-ShareAlike, and `reading_segments` is derived from them. Settings → 關於 now
  credits both, alongside the SIL OFL notice the bundled typeface had always needed and
  never had. Removing that screen is not a cosmetic change.
- **A dictionary table in Postgres.** 235,610 rows, loaded by
  `scripts/import-furigana-dict.ts`. It is in the database rather than the app or the
  serverless bundle because splitting a headword probes every substring of it, which is one
  indexed query and would otherwise be a 12 MB file parsed on every cold start.
- **`reading_segments` may be null, and that is normal.** It means "no trustworthy split",
  and the client falls back to the line this replaced. It is never an error state.
