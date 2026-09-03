#!/usr/bin/env python3
"""Every screen that shows an example sentence must host the 詞塊 card.

`InteractiveSentenceText` reads `\\.glossSelection` from the environment and
falls back to plain text when nothing hosts it. That fallback is correct — it is
what the feature looked like before it existed — but it is also *silent*: a
screen that forgot `.glossCard()` looks exactly like a screen the feature was
never meant to reach, so nobody reports it. It has been missed twice (複習's
reveal sheet, 物見's item detail), and the second one had live annotated data
sitting under dead text for weeks.

The compiler is happy and the unit tests are happy — `.glossCard()` is one
modifier on a screen root, and its absence is only visible to someone who taps a
word on that particular screen.

Two things have changed since, and this check still earns its place beside them.
`.tujiSheet(...)` now hosts the card itself, outside the shell, so a sheet
cannot forget; and `InteractiveSentenceText` paints a red rule under any
sentence it renders with usable 詞塊 and no host (DEBUG only). Neither replaces
this: the modifier covers sheets and not pushed screens, and the red rule needs
someone to open the screen. This one runs before anybody does.

Files whose host belongs to their *caller* are listed in HOSTED_BY_CALLER with
the reason. That list is the point: adding to it is a decision, and a new file
that renders sentences has to make it.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Tuji"

# Either hosts the card. `.tujiSheet(...)` applies `.glossCard()` itself, on the
# outside of the shell — which is the placement a caller has to get right by hand
# and the reason two screens used to hand-roll `TujiSheetShell` instead of using
# the convenience. A screen whose only sentences are inside such a sheet is
# covered by construction and must not be asked to say so twice.
HOSTS = (".glossCard()", ".tujiSheet(")

# Rendering any of these puts an example sentence (or a 譯義 line) on screen.
# `WordDetailSheet` and `ExpandableWordDetail` are here rather than only their
# leaves because the host must sit on the *screen root*: a sheet that shows word
# detail needs its own, and pointing the rule at the leaf would let that slip.
RENDERERS = (
    "InteractiveSentenceText",
    "WordDetailSections",
    "ExpandableWordDetail",
    "WordDetailSheet",
)

# Not screens. Their host is the caller's, and each says so in its own header.
HOSTED_BY_CALLER = {
    "Tuji/Features/Word/WordDetailSections.swift": "the sections block itself — every screen that renders it hosts the card",
    "Tuji/Features/Word/ExpandableWordDetail.swift": "loads into whatever sheet or page presents it; that root hosts the card",
    "Tuji/Features/Word/WordDetailSheet.swift": "its header says a caller must host the card, on the sheet root outside the shell",
}


def code_lines(text: str) -> list[str]:
    """Source with `//` comments removed.

    Three of the four files that talk about `.glossCard()` only *mention* it in
    prose — `WordDetailSheet` says a caller must add one — so a check that
    grepped the raw text would pass every screen that documented the rule while
    breaking it.
    """
    out = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        out.append(line.split("//", 1)[0])
    return out


def main() -> None:
    failures: list[str] = []
    checked = 0
    for path in sorted(SOURCES.rglob("*.swift")):
        rel = path.relative_to(ROOT).as_posix()
        lines = code_lines(path.read_text(encoding="utf-8"))
        body = "\n".join(lines)
        # `struct Foo: View {` is the definition, not a use of it.
        renders = any(
            re.search(rf"\b{name}\s*\(", body) and not re.search(rf"\bstruct\s+{name}\b", body)
            for name in RENDERERS
        )
        if not renders:
            continue
        checked += 1
        if rel in HOSTED_BY_CALLER or any(host in body for host in HOSTS):
            continue
        failures.append(rel)

    for rel in failures:
        print(
            f"gloss host check failed: {rel} renders example sentences but hosts no "
            f"詞塊 card ({' or '.join(HOSTS)}). Add one to the screen root, outside "
            f"whatever shell draws its title bar — or list the file in "
            f"HOSTED_BY_CALLER with the reason its caller hosts instead.",
            file=sys.stderr,
        )
    stale = [rel for rel in HOSTED_BY_CALLER if not (ROOT / rel).is_file()]
    for rel in stale:
        print(f"gloss host check failed: HOSTED_BY_CALLER names {rel}, which no longer exists", file=sys.stderr)
    if failures or stale:
        raise SystemExit(1)
    print(f"gloss host contract OK — {checked} sentence-rendering files, {len(HOSTED_BY_CALLER)} hosted by their caller")


if __name__ == "__main__":
    main()
