#!/usr/bin/env python3
"""Rebuild Tuji's raster brand assets without redrawing their geometry."""

from __future__ import annotations

import colorsys
from pathlib import Path
from statistics import median

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ICON = ROOT.parent / "design/final/tuji-app-icon-mascot-book-1024.png"
ICON_DIR = ROOT / "Tuji/Assets.xcassets/AppIcon.appiconset"
LOCKUP_DIR = ROOT / "Tuji/Assets.xcassets/LaunchLockupPeekStart.imageset"

COCOA = "#59483D"
DARK_COCOA = "#3F342D"


def rgb01(hex_color: str) -> tuple[float, float, float]:
    value = hex_color.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4))


def is_replaceable_ground(
    hue: float,
    lightness: float,
    saturation: float,
    *,
    include_cocoa: bool,
    include_blue_fringe: bool,
) -> bool:
    """Select the old teal ground and, when requested, a generated cocoa ground."""
    old_teal = 0.47 <= hue <= 0.57 and saturation >= 0.22
    blue_fringe = 0.57 < hue <= 0.72 and saturation >= 0.18
    cocoa = 0.035 <= hue <= 0.115 and saturation >= 0.08 and lightness < 0.55
    return old_teal or (include_blue_fringe and blue_fringe) or (include_cocoa and cocoa)


def recolor_ground(
    source: Path,
    destination: Path,
    target_hex: str,
    *,
    include_cocoa: bool = False,
    include_blue_fringe: bool = False,
) -> None:
    image = Image.open(source).convert("RGBA")
    pixels = list(image.getdata())
    hls_pixels = []

    for red, green, blue, alpha in pixels:
        hue, lightness, saturation = colorsys.rgb_to_hls(red / 255, green / 255, blue / 255)
        hls_pixels.append((hue, lightness, saturation, alpha))

    selected = [
        (lightness, saturation)
        for hue, lightness, saturation, alpha in hls_pixels
        if alpha > 0
        and is_replaceable_ground(
            hue,
            lightness,
            saturation,
            include_cocoa=include_cocoa,
            include_blue_fringe=include_blue_fringe,
        )
    ]
    if not selected:
        raise RuntimeError(f"No replaceable brand ground found in {source}")

    source_lightness = median(item[0] for item in selected)
    source_saturation = median(item[1] for item in selected)
    target_hue, target_lightness, target_saturation = colorsys.rgb_to_hls(*rgb01(target_hex))

    result = []
    for original, (hue, lightness, saturation, alpha) in zip(pixels, hls_pixels):
        if alpha > 0 and is_replaceable_ground(
            hue,
            lightness,
            saturation,
            include_cocoa=include_cocoa,
            include_blue_fringe=include_blue_fringe,
        ):
            mapped_lightness = max(0, min(1, target_lightness + (lightness - source_lightness)))
            mapped_saturation = max(
                0,
                min(1, target_saturation + (saturation - source_saturation) * 0.12),
            )
            red, green, blue = colorsys.hls_to_rgb(
                target_hue,
                mapped_lightness,
                mapped_saturation,
            )
            result.append((round(red * 255), round(green * 255), round(blue * 255), alpha))
        else:
            result.append(original)

    image.putdata(result)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)


def assert_foreground_unchanged(source: Path, result: Path) -> None:
    original = Image.open(source).convert("RGBA")
    recolored = Image.open(result).convert("RGBA")
    if original.size != recolored.size:
        raise RuntimeError(f"Geometry changed while recoloring {result}")

    for index, (before, after) in enumerate(zip(original.getdata(), recolored.getdata())):
        red, green, blue, alpha = before
        hue, lightness, saturation = colorsys.rgb_to_hls(red / 255, green / 255, blue / 255)
        is_ground = alpha > 0 and is_replaceable_ground(
            hue,
            lightness,
            saturation,
            include_cocoa=False,
            include_blue_fringe=False,
        )
        if not is_ground and before != after:
            raise RuntimeError(f"Foreground pixel {index} changed while recoloring {result}")


def rebuild_icons() -> None:
    light = ICON_DIR / "tuji-icon-light.png"
    dark = ICON_DIR / "tuji-icon-dark.png"
    tinted = ICON_DIR / "tuji-icon-tinted.png"

    recolor_ground(SOURCE_ICON, light, COCOA)
    recolor_ground(SOURCE_ICON, dark, DARK_COCOA)
    assert_foreground_unchanged(SOURCE_ICON, light)
    assert_foreground_unchanged(SOURCE_ICON, dark)

    with Image.open(light) as image:
        grayscale = ImageOps.grayscale(image.convert("RGB"))
        grayscale.save(tinted, optimize=True)


def rebuild_lockup() -> None:
    for path in sorted(LOCKUP_DIR.glob("launch-lockup-peek-start*.png")):
        recolor_ground(
            path,
            path,
            COCOA,
            include_cocoa=True,
            include_blue_fringe=True,
        )


if __name__ == "__main__":
    rebuild_icons()
    rebuild_lockup()
    print("brand raster assets recolored without geometry changes")
