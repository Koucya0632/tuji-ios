#!/usr/bin/env python3
"""Fail when a string a screen can show renders as 繁體中文 in ja / en / zh-Hans.

A user-visible string and its `Localizable.xcstrings` entry are two unrelated
edits, and nothing has ever connected them. The code compiles, the tests pass,
CI is green, and the app renders correctly in 繁體中文 — the base language *is*
the key, so a missing entry is invisible until someone opens the app in
Japanese or English. That has shipped three times in the last week.

This is the seam. It reads the Swift sources rather than the built product,
because one of the two failures is a *missing* entry: there is nothing in the
binary to inspect.

**There are two ways to lose a translation, and this check used to ask about
only one of them.** A literal can be absent from the catalogue entirely, or it
can sit in the catalogue as a key with no `en` / `ja` / `zh-Hans` under it.
Both end the same way — iOS falls back to the key, and the key is the 繁體中文
source string — so a screen reads Chinese in an English UI either way. The
original version of this script only asked "is the key present?", which let the
second kind through: v1.1.1 was one signed build away from shipping 15 of them,
including the signup screen's body copy and the destructive-action footer in
設定. So the question is now "does this literal resolve in all three?", and
`Tuji v1.1.0 · 圖記` is the reason the answer has to include the version
signature too.

Deliberately conservative. It only reports a literal it is confident is a
`LocalizedStringKey`:

  * `Text("…")` / `tujiLocalized("…")` / `LocalizedStringKey("…")`
  * an argument to a parameter this project declares as one (`title:`, `detail:` …)
  * the first positional argument of a type that takes a key there —
    `Button("…")`, `TujiPromptAction("…")`, `TujiRow("…")` (see LEADING_KEY_CALLS)
  * both branches of a ternary on a line that already contains one of the above,
    which is how `Text(sent ? "已收到檢舉" : "檢舉這個合集")` is written

The last two were added after two strings shipped uncaught: the literals sat
next to nothing the earlier patterns looked for, which left `TujiPromptAction`
— the most common key-taking call in this codebase — entirely unchecked.

Anything ambiguous is skipped: a false positive here blocks a merge, and a check
people learn to override is worse than no check.

    python3 scripts/check-localization.py            # report and exit non-zero
    python3 scripts/check-localization.py --list     # just print what it found
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Tuji/Resources/i18n/Localizable.xcstrings"
SOURCES = [ROOT / "Tuji"]

# Call shapes whose string argument is resolved against the catalogue.
#
# `Text(verbatim:)` and the `init(localized:)` family are the *escape hatches* —
# they mean "already resolved, do not look this up" — so they are absent by
# design, not by omission.
# Opens a declaration whose *return type* is a key, so every bare literal inside
# it is one:
#
#     var label: LocalizedStringKey {
#         switch self { case .again: "重來" … }
#     }
#
# This is the dominant idiom in this codebase (SRSRating.label, CardsSource.title,
# MasteryLevel.name, AtlasReviewStatus.label …) and the call-site patterns below
# cannot see it — the literal never appears next to `Text(` or a labelled
# argument. Missing it let two strings ship uncaught the first time this script
# was trusted.
KEY_RETURNING = re.compile(r"(?:var|func)\s+\w+[^{}\n]*->?\s*:?\s*LocalizedStringKey\??\s*\{|"
                           r"(?:var|let)\s+\w+\s*:\s*LocalizedStringKey\??\s*\{")
BARE_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')

# Initialisers whose FIRST POSITIONAL argument is a `LocalizedStringKey`.
#
# This shape was the blind spot that let 檢舉這個合集 and 檢舉這位作者 ship
# unnoticed: the literal sits next to nothing the patterns below look for — no
# `Text(`, no `label:` — so a whole family of call sites was unchecked, including
# `TujiPromptAction` (the single most common one in this codebase) and every
# `Button("…")`.
#
# An explicit list rather than "any Capitalised(" on purpose: `Image("mascot")`
# and `Set("…")` take the same shape and neither wants a translator, and a false
# positive here blocks a merge. To extend it, check the type really declares
# `init(_ x: LocalizedStringKey …)` — a labelled `title:` is already covered by
# the argument-name pattern below.
LEADING_KEY_CALLS = (
    # SwiftUI
    "Button", "Label", "Link", "Toggle", "Picker", "Menu", "Section",
    "NavigationLink", "Stepper", "TextField", "SecureField", "TextEditor",
    "confirmationDialog", "alert",
    # This project
    "TujiRow", "TujiScreenTitle", "TujiPromptAction", "TujiNavTextAction",
)

PATTERNS = [
    re.compile(r'\bText\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\btujiLocalized\(\s*"((?:[^"\\]|\\.)*)"'),
    # `text:` joined this list the day a tour step's body copy was rewritten and
    # nothing noticed it had left the catalogue. `TourStep.text` is a
    # `LocalizedStringKey` sitting directly beneath `title:`, which *was*
    # checked — so the one line of the step that gets translated was guarded and
    # the paragraph under it was not. Keep this list and `KEY_CALL_ON_LINE`'s
    # copy of it in step; they are the same list read two ways.
    re.compile(r'\b(?:title|text|label|subtitle|message|detail|placeholder|footer|badge)'
               r'\s*:\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bLocalizedStringKey\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\baccessibilityLabel\(\s*Text\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r"\b(?:" + "|".join(LEADING_KEY_CALLS) + r')\(\s*"((?:[^"\\]|\\.)*)"'),
]

# `Text(sent ? "已收到檢舉" : "檢舉這個合集")` — the branches are keys, but
# neither sits where the patterns above look, so both were invisible. Only
# trusted on a line that already contains a key-taking call, so an ordinary
# `foo(a ? "x" : "y")` elsewhere is not dragged in.
TERNARY = re.compile(r'\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
KEY_CALL_ON_LINE = re.compile(
    r"\b(?:Text|tujiLocalized|LocalizedStringKey|accessibilityLabel|"
    + "|".join(LEADING_KEY_CALLS)
    + r")\(|"
    # `text:` joined this list the day a tour step's body copy was rewritten and
    # nothing noticed it had left the catalogue. `TourStep.text` is a
    # `LocalizedStringKey` sitting beside `title:`, which *was* checked — so the
    # one line of the step that gets translated was guarded and the paragraph
    # under it was not.
    + r"\b(?:title|text|label|subtitle|message|detail|placeholder|footer|badge)\s*:"
)

# A key that carries no meaning of its own. `Text("\(count)")` is a number, not
# a sentence; `Text("→")` is a glyph. Neither wants a translation. Applied
# *after* interpolations are removed, so `"\(pct)%"` collapses to punctuation.
SKIP = re.compile(r"^[\s\d%@·/:→←✓✕\-–—.,()\[\]]*$")

# Not prose. A reverse-DNS queue label, a bundle id, an SF Symbol name and an
# example address are all matched by the `label:` / `placeholder:` shapes above
# and none of them wants a translator.
NOT_PROSE = re.compile(
    r"^(?:[a-z0-9]+(?:[.\-][a-z0-9]+){2,}"      # app.tuji.ios.network-monitor
    r"|[^@\s]+@[^@\s]+\.[a-z]{2,}"              # name@example.com
    r"|https?://\S+)$",
    re.IGNORECASE,
)


# The three the app ships besides the zh-Hant base. A key that resolves in
# none of them is as Chinese on screen as a key that was never added.
TARGETS = ("en", "ja", "zh-Hans")


def untranslated(entry: dict) -> list[str]:
    """Which of TARGETS this catalogue entry cannot answer in.

    `state` matters as much as presence: Xcode writes `"new"` for an entry a
    translator has not confirmed, and those do not reach the compiled
    `.lproj` — the entry looks filled in the JSON and is still missing in the
    binary. Every shipping entry in this catalogue is `translated`, so
    requiring it costs nothing and closes that door.
    """
    localizations = entry.get("localizations", {})
    return [
        lang
        for lang in TARGETS
        if localizations.get(lang, {}).get("stringUnit", {}).get("state") != "translated"
    ]


def interpolations_to_specifiers(literal: str) -> str:
    """Swift writes `\\(n) 字`; the catalogue stores `%lld 字`.

    Which specifier a given interpolation produces depends on the expression's
    type, which is not knowable from the source text. So both are accepted and
    the caller treats a hit on either as present.
    """
    return re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "\x00", literal)


def main() -> int:
    if not CATALOG.exists():
        print(f"catalogue not found: {CATALOG}", file=sys.stderr)
        return 1

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    # Index the catalogue by its interpolation-blind shape so `%lld 字` and
    # `%@ 字` both match a source literal that interpolates in that position.
    blind: dict[str, str] = {}
    for key in catalog:
        blind.setdefault(re.sub(r"%(?:lld|@|\d+\$[a-z@]+|\.\d+f|d)", "\x00", key), key)

    missing: list[tuple[str, int, str]] = []
    partial: list[tuple[str, int, str, list[str]]] = []
    seen: set[str] = set()

    for root in SOURCES:
        for path in sorted(root.rglob("*.swift")):
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except UnicodeDecodeError:
                continue
            # `#Preview` bodies are developer scaffolding — never shipped, and
            # deliberately full of throwaway sample copy.
            preview_depth: int | None = None
            # Brace depth inside a key-returning declaration, or None.
            key_depth: int | None = None
            for number, line in enumerate(lines, start=1):
                if preview_depth is None and line.lstrip().startswith("#Preview"):
                    preview_depth = 0
                if preview_depth is not None:
                    preview_depth += line.count("{") - line.count("}")
                    if preview_depth <= 0 and "}" in line:
                        preview_depth = None
                    continue
                stripped = line.lstrip()
                if stripped.startswith("//") or stripped.startswith("///"):
                    continue

                if key_depth is None and KEY_RETURNING.search(line):
                    key_depth = 0
                found = list(PATTERNS)
                if key_depth is not None:
                    key_depth += line.count("{") - line.count("}")
                    # Not on an interpolated line: a nested literal inside
                    # `\(x, specifier: "%.1f")` cuts the scan in half and the
                    # tail reads as its own key. The call-site patterns do not
                    # cover interpolation here either — a miss beats a false
                    # positive, which is the whole posture of this check.
                    if "\\(" not in line:
                        found = found + [BARE_LITERAL]
                    if key_depth <= 0:
                        key_depth = None

                candidates: list[str] = []
                for pattern in found:
                    candidates.extend(pattern.findall(line))
                if KEY_CALL_ON_LINE.search(line):
                    for branch in TERNARY.findall(line):
                        candidates.extend(branch)

                for literal in candidates:
                    if not literal or NOT_PROSE.match(literal):
                        continue
                    collapsed = interpolations_to_specifiers(literal)
                    # An interpolation left open means the literal runs onto
                    # the next line and this scan only has a fragment of it.
                    # Judging a fragment would produce a false positive, and
                    # a check that cries wolf gets overridden.
                    if "\\(" in collapsed:
                        continue
                    if SKIP.match(collapsed.replace("\x00", "")):
                        continue
                    key = literal if literal in catalog else blind.get(collapsed)
                    if literal in seen:
                        continue
                    seen.add(literal)
                    where = (str(path.relative_to(ROOT)), number)
                    if key is None:
                        missing.append((*where, literal))
                        continue
                    gaps = untranslated(catalog[key])
                    if gaps:
                        partial.append((*where, key, gaps))

    if "--list" in sys.argv:
        print(f"scanned {len(catalog)} catalogue keys")

    if not missing and not partial:
        print("✓ every user-visible string resolves in en / ja / zh-Hans")
        return 0

    def show(literal: str) -> str:
        return literal if len(literal) <= 60 else literal[:57] + "…"

    if missing:
        print(f"✗ {len(missing)} string(s) a screen can show are not in the catalogue.")
        print("  They will render as Traditional Chinese in ja / en / zh-Hans.\n")
        for path, number, literal in missing:
            print(f"  {path}:{number}\n      {show(literal)}")
        print("\n  Add them to Tuji/Resources/i18n/Localizable.xcstrings, or use the")
        print("  verbatim initialiser (Text(verbatim:) / BBtn(localized:) / …) if the")
        print("  value is already resolved.")

    if partial:
        if missing:
            print()
        print(f"✗ {len(partial)} string(s) are in the catalogue with no translation.")
        print("  Same symptom: iOS falls back to the key, and the key is 繁體中文.\n")
        for path, number, key, gaps in partial:
            print(f"  {path}:{number}  [missing: {', '.join(gaps)}]\n      {show(key)}")
        print("\n  Fill them in Tuji/Resources/i18n/Localizable.xcstrings. A brand")
        print("  name or a language code still needs an entry per language — the")
        print("  translation is just the same string.")

    return 1


if __name__ == "__main__":
    sys.exit(main())
