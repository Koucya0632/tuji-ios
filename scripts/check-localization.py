#!/usr/bin/env python3
"""Fail when a string a screen can show is missing from the catalogue.

A user-visible string and its `Localizable.xcstrings` entry are two unrelated
edits, and nothing has ever connected them. The code compiles, the tests pass,
CI is green, and the app renders correctly in 繁體中文 — the base language *is*
the key, so a missing entry is invisible until someone opens the app in
Japanese or English. That has shipped three times in the last week.

This is the seam. It reads the Swift sources rather than the built product,
because the failure is a *missing* entry: there is nothing in the binary to
inspect.

Deliberately conservative. It only reports a literal it is confident is a
`LocalizedStringKey` — a `Text("…")`, a `tujiLocalized("…")`, or an argument to
a parameter this project declares as one. Anything ambiguous is skipped: a false
positive here blocks a merge, and a check people learn to override is worse than
no check.

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
PATTERNS = [
    re.compile(r'\bText\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\btujiLocalized\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\b(?:title|label|subtitle|message|detail|placeholder|footer|badge)'
               r'\s*:\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bLocalizedStringKey\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\baccessibilityLabel\(\s*Text\(\s*"((?:[^"\\]|\\.)*)"'),
]

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
                for pattern in PATTERNS:
                    for literal in pattern.findall(line):
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
                        if literal in catalog:
                            continue
                        if interpolations_to_specifiers(literal) in blind:
                            continue
                        if literal in seen:
                            continue
                        seen.add(literal)
                        missing.append((str(path.relative_to(ROOT)), number, literal))

    if "--list" in sys.argv:
        print(f"scanned {len(catalog)} catalogue keys")

    if not missing:
        print("✓ every user-visible string has a catalogue entry")
        return 0

    print(f"✗ {len(missing)} string(s) a screen can show are not in the catalogue.")
    print("  They will render as Traditional Chinese in ja / en / zh-Hans.\n")
    for path, number, literal in missing:
        shown = literal if len(literal) <= 60 else literal[:57] + "…"
        print(f"  {path}:{number}\n      {shown}")
    print("\n  Add them to Tuji/Resources/i18n/Localizable.xcstrings, or use the")
    print("  verbatim initialiser (Text(verbatim:) / BBtn(localized:) / …) if the")
    print("  value is already resolved.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
