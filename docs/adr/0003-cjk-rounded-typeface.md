# ADR-0003 — Bundling a rounded CJK typeface, and what it does not cover

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

The app ships no CJK font. `Info.plist`'s `UIAppFonts` registers five files — four
Plus Jakarta Sans weights and JetBrains Mono, 776 KB total, all Latin or monospace.
`TujiFont.swift` names "Noto Sans TC (CJK fallback)" in its header comment, but that file
was never bundled and the comment says so two lines later: `Font.custom` returns a system
fallback when the `.ttf` is absent.

So every Chinese and Japanese character in the product is rendered by PingFang or
Hiragino — Apple's system typefaces. This is a Chinese-language app for Chinese speakers:
the overwhelming majority of on-screen text is set in the platform default. A UI/UX review
concluded the app "reads as a standard iOS app with no face of its own", and diagnosed the
cause as stock chrome (native `List`, segmented controls, navigation bars, spinners). That
diagnosis missed the largest single contributor, which is the type itself.

The redesign therefore makes a rounded CJK typeface one of three "fingerprints" — the
properties by which the product should be recognisable with its logo and mascot removed.
This is the first time a CJK font would enter the bundle, so the cost is new, not marginal.

## Decision

Bundle **GenSenRounded 2** (SIL OFL 1.1, derived from Source Han Sans) in two faces,
registered through `UIAppFonts`:

| Interface language | Face |
|---|---|
| 繁體中文 | `GenSenRounded2TW` (月版, contemporary Taiwan stroke conventions) |
| 日本語 | `GenSenRounded2JP` |
| 简体中文 | **falls back to TW** |
| English | no CJK face applies |

**Two weights per face, not three.** No token asks for Medium — `TujiFont` sets
Regular for body copy and Bold for everything above it — so a Medium face would be
31 MB of glyphs nothing draws. `tujiDisplay` is ExtraBold in Latin and takes Bold in
CJK; GenSenRounded's Heavy would cost another 30 MB for one token.

Four files, **61 MB uncompressed**.

**The CJK face is a cascade entry, not the font.** Setting `Font.custom("GenSenRounded2TW-R", …)`
would hand *Latin* text to GenSenRounded's own Latin — a Source Sans derivative that is
neither rounded nor Plus Jakarta — silently replacing the Latin face across the app as a
side effect of fixing Chinese. Each token is instead a Plus Jakarta `UIFontDescriptor`
with the CJK face in its `cascadeList`, so only glyphs Plus Jakarta cannot draw fall
through.

That has one cost worth naming: `Font.custom(_:size:)` scales with Dynamic Type on its
own, and `Font(_: UIFont)` does not. The metric is therefore applied by hand
(`UIFontMetrics.default.scaledFont(for:)`) and the content size category is part of the
font cache key. Getting this wrong would have frozen every label in the app at the
default text size — silently, and only for users who had changed it.

Three limits are accepted rather than worked around:

**Simplified Chinese gets Taiwan glyph forms.** GenSenRounded has no SC face. Glyph
*coverage* is complete — a six-set probe (simplified common, simplified-only, traditional,
kana, TW/CN divergent characters, interface strings) found no missing glyphs, so there is
no tofu. What a zh-Hans reader sees is Taiwanese stroke conventions for characters whose
standard forms differ between regions.

**English interface does not get the rounded fingerprint.** GenSenRounded's rounding is
applied to CJK; its Latin descends from Source Sans and, rendered beside the incumbent
Plus Jakarta Sans, is not visibly rounder. In `en`, the interface keeps only two of the
three fingerprints — zero corner radius and ink-block inversion.

## Alternatives considered

**All three faces.** Rejected because the third face does not exist. This was the original
plan and it rested on an unverified assumption.

**TW only, Japanese falling back to TW.** Halves the size to 45.8 MB. Rejected: Japanese
is a first-class learning direction, and Han characters in a Taiwan face are the wrong
forms for a Japanese learner — worse than the zh-Hans compromise, because the reader is
studying those glyph shapes rather than merely reading through them.

**Subsetting all faces.** Rejected: the dictionary is server-driven and users author their
own content, so the required glyph set is unbounded. A missing glyph is a tofu block in
user-generated text.

**On-Demand Resources**, registering fonts at runtime via
`CTFontManagerRegisterFontsForURL` instead of `UIAppFonts`. Keeps the download at zero and
is technically viable. Rejected for now: every new user's first launch would render in the
system font, and first impression is exactly what this redesign is trying to win. Worth
revisiting if the store listing size proves to cost installs.

**Keeping the system font** and carrying the personality with weight contrast and
whitespace instead. Rejected: it leaves the single most common element on every screen as
the platform default, which is the problem being solved.

## Consequences

- Installed size grows by 61 MB. There is no measurement of how much a larger download
  costs in installs, and none is planned — the redesign is being treated as a brand
  decision, not an optimisation (see the redesign package's D2 §D).
- The repository grows by the same 61 MB, permanently: the files are committed directly,
  not through Git LFS, which this repo does not use. Removing them later means rewriting
  history.
- Simplified-Chinese users are knowingly served non-native glyph forms. If that becomes a
  complaint, the fix is a fourth face from a different family, which would break visual
  consistency across languages — so it is a real, not nominal, cost.
- `tujiMono` (JetBrains Mono) and Gabarito for Latin display text are unaffected.
- The licence permits commercial redistribution without fees; the OFL text must ship with
  the app's acknowledgements.
