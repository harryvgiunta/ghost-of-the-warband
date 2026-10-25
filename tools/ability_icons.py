"""Generate the deterministic ability icon set.

The icons are simple high-contrast glyphs: gold forward chevrons over teal
speed streaks, matching the HUD palette. Everything is drawn at 4x and reduced
with Lanczos so small HUD sizes stay clean.

Usage:
    python tools/ability_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "abilities"
SCALE = 4
SIZE = 128

GOLD = (233, 191, 118, 255)
TEAL = (114, 203, 182, 255)


def chevron(draw: ImageDraw.ImageDraw, x: int, y: int, height: int, depth: int,
            width: int) -> None:
    """A filled forward chevron with a flat back edge."""
    top = y - height // 2
    bottom = y + height // 2
    inner = top + width
    inner_bottom = bottom - width
    points = [
        (x, top),
        (x + depth, y),
        (x, bottom),
        (x + width, bottom),
        (x + depth + width, y),
        (x + width, top),
    ]
    draw.polygon(points, fill=GOLD)


def build_charge() -> Image.Image:
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    unit = SIZE * SCALE // 128

    # Speed streaks behind the glyph.
    for offset, length, width in ((26, 24, 5), (48, 20, 4), (70, 15, 3)):
        y = (40 + offset) * unit
        draw.rounded_rectangle(
            (14 * unit, y - width * unit, (14 + length) * unit, y + width * unit),
            radius=width * unit,
            fill=TEAL,
        )

    # Two forward chevrons with a clear seam between them.
    chevron(draw, 38 * unit, 64 * unit, 62 * unit, 22 * unit, 15 * unit)
    chevron(draw, 76 * unit, 64 * unit, 62 * unit, 22 * unit, 15 * unit)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    build_charge().save(OUT / "charge.png", optimize=True)
    print(f"wrote {OUT / 'charge.png'}")


if __name__ == "__main__":
    main()
