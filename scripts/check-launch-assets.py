#!/usr/bin/env python3
"""Validate the static launch screen contract without requiring Xcode."""

from __future__ import annotations

import json
import plistlib
import re
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Tuji" / "Assets.xcassets"
EXPECTED_IMAGE = "LaunchLockupPeekStart"
EXPECTED_COLOR = "LaunchBg"
EXPECTED_SIZES = {
    "1x": (232, 230),
    "2x": (464, 460),
    "3x": (696, 690),
}


def fail(message: str) -> None:
    print(f"launch asset check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if len(data) != 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        fail(f"{path.relative_to(ROOT)} is not a valid PNG")
    return struct.unpack(">II", data[16:24])


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path.relative_to(ROOT)}: {error}")


def validate_info_plist() -> None:
    with (ROOT / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    launch = info.get("UILaunchScreen")
    if not isinstance(launch, dict):
        fail("Info.plist has no UILaunchScreen dictionary")
    expected = {
        "UIColorName": EXPECTED_COLOR,
        "UIImageName": EXPECTED_IMAGE,
        "UIImageRespectsSafeAreaInsets": True,
    }
    for key, value in expected.items():
        if launch.get(key) != value:
            fail(f"UILaunchScreen.{key} must be {value!r}, got {launch.get(key)!r}")


def validate_background_color() -> None:
    color_json = load_json(ASSETS / f"{EXPECTED_COLOR}.colorset" / "Contents.json")
    colors = color_json.get("colors", [])
    if len(colors) != 1 or colors[0].get("idiom") != "universal" or "appearances" in colors[0]:
        fail("LaunchBg must contain exactly one universal light-only color")

    theme = (ROOT / "Tuji" / "Core" / "Theme" / "TujiColor.swift").read_text(encoding="utf-8")
    match = re.search(r"tujiPaper\s*=\s*Color\(hex:\s*0x([0-9A-Fa-f]{6})\)", theme)
    if match is None:
        fail("cannot find tujiPaper hex value in TujiColor.swift")
    rgb = tuple(int(match.group(1)[index : index + 2], 16) / 255 for index in (0, 2, 4))

    components = colors[0].get("color", {}).get("components", {})
    try:
        launch_rgb = tuple(float(components[name]) for name in ("red", "green", "blue"))
        alpha = float(components["alpha"])
    except (KeyError, TypeError, ValueError) as error:
        fail(f"LaunchBg has invalid sRGB components: {error}")
    if alpha != 1 or any(abs(actual - expected) > 0.0005 for actual, expected in zip(launch_rgb, rgb)):
        fail(f"LaunchBg {launch_rgb} does not match tujiPaper {rgb}")


def validate_lockup_images() -> None:
    image_set = ASSETS / f"{EXPECTED_IMAGE}.imageset"
    contents = load_json(image_set / "Contents.json")
    images = contents.get("images", [])
    by_scale = {item.get("scale"): item for item in images if item.get("idiom") == "universal"}
    if set(by_scale) != set(EXPECTED_SIZES):
        fail(f"{EXPECTED_IMAGE} must define exactly 1x, 2x and 3x universal images")

    for scale, expected_size in EXPECTED_SIZES.items():
        filename = by_scale[scale].get("filename")
        if not filename:
            fail(f"{EXPECTED_IMAGE} {scale} slot has no filename")
        path = image_set / filename
        if not path.is_file():
            fail(f"missing {path.relative_to(ROOT)}")
        actual_size = png_size(path)
        if actual_size != expected_size:
            fail(f"{path.relative_to(ROOT)} is {actual_size}, expected {expected_size}")

    if (ASSETS / "LaunchMarkV2.imageset").exists():
        fail("obsolete LaunchMarkV2.imageset must be removed")


def main() -> None:
    validate_info_plist()
    validate_background_color()
    validate_lockup_images()
    print("launch asset contract OK")


if __name__ == "__main__":
    main()
