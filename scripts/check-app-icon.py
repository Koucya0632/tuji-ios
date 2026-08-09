#!/usr/bin/env python3
"""Validate the iOS app icon appearance variants without requiring Xcode."""

from __future__ import annotations

import hashlib
import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ICON_SET = ROOT / "Tuji" / "Assets.xcassets" / "AppIcon.appiconset"
EXPECTED_SIZE = (1024, 1024)
EXPECTED_APPEARANCES = {"light", "dark", "tinted"}


def fail(message: str) -> None:
    print(f"app icon check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def appearance(item: dict) -> str:
    appearances = item.get("appearances", [])
    if not appearances:
        return "light"
    if len(appearances) != 1 or appearances[0].get("appearance") != "luminosity":
        fail(f"unsupported appearance declaration: {appearances!r}")
    value = appearances[0].get("value")
    if value not in {"dark", "tinted"}:
        fail(f"unsupported luminosity value: {value!r}")
    return value


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if len(data) != 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        fail(f"{path.relative_to(ROOT)} is not a valid PNG")
    return struct.unpack(">II", data[16:24])


def main() -> None:
    contents = json.loads((ICON_SET / "Contents.json").read_text(encoding="utf-8"))
    images = contents.get("images", [])
    variants: dict[str, Path] = {}

    for item in images:
        if item.get("idiom") != "universal" or item.get("platform") != "ios":
            continue
        kind = appearance(item)
        filename = item.get("filename")
        if not filename:
            fail(f"{kind} appearance has no filename")
        if kind in variants:
            fail(f"duplicate {kind} appearance")
        variants[kind] = ICON_SET / filename

    if set(variants) != EXPECTED_APPEARANCES:
        fail(f"expected {sorted(EXPECTED_APPEARANCES)}, got {sorted(variants)}")

    digests: dict[str, str] = {}
    for kind, path in variants.items():
        if not path.is_file():
            fail(f"missing {path.relative_to(ROOT)}")
        if png_size(path) != EXPECTED_SIZE:
            fail(f"{path.relative_to(ROOT)} must be 1024x1024")
        digests[kind] = hashlib.sha256(path.read_bytes()).hexdigest()

    if len(set(digests.values())) != len(digests):
        fail("Light, Dark and Tinted must not contain identical PNG data")

    print("app icon variants OK")


if __name__ == "__main__":
    main()
