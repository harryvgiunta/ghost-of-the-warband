"""Generate the production texture atlas for the Blood Ledger menu language.

    python tools/render_ui_theme.py

Writes 9-slice surfaces, plates in every state, keycaps, chips, the seal and the
medallion set into assets/ui/theme/, plus a manifest the Godot theme reads. All
art comes from the same seeded fields as the concept boards; the only change is
that edge strips are averaged along the axis the nine-slice stretches them, so a
stretched frame never smears its hammer marks.

Every file is deterministic: same seed, same pixels.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from ui_theme import kit  # noqa: E402
from ui_theme import materials as mat  # noqa: E402

OUT = ROOT / "assets" / "ui" / "theme"
ICON_KEYS = ["scroll", "helm", "banner", "gear", "flame", "eye", "coin", "blade",
             "shield", "cuirass", "gauntlet", "greaves", "boot", "amulet", "ring",
             "bow", "staff", "spear", "cage", "chalice", "key", "altar"]

CLAMP = 96
CLAMP_MARGIN = 24
PAGE = 256
PAGE_MARGIN = 56
PLATE = (96, 48)
PLATE_MARGIN = (20, 12)


def uniform_edges(image: Image.Image, margin_x: int, margin_y: int) -> Image.Image:
    """Average each edge strip along the axis a nine-slice will stretch."""
    arr = np.asarray(image).astype(np.float32)
    h, w = arr.shape[:2]
    if margin_x and margin_x * 2 < w:
        top = arr[:margin_y, margin_x:w - margin_x]
        arr[:margin_y, margin_x:w - margin_x] = top.mean(axis=1, keepdims=True)
        bottom = arr[h - margin_y:, margin_x:w - margin_x]
        arr[h - margin_y:, margin_x:w - margin_x] = bottom.mean(axis=1, keepdims=True)
    if margin_y and margin_y * 2 < h:
        left = arr[margin_y:h - margin_y, :margin_x]
        arr[margin_y:h - margin_y, :margin_x] = left.mean(axis=0, keepdims=True)
        right = arr[margin_y:h - margin_y, w - margin_x:]
        arr[margin_y:h - margin_y, w - margin_x:] = right.mean(axis=0, keepdims=True)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), image.mode)


def _save(image: Image.Image, name: str) -> None:
    image.save(OUT / name, optimize=True)
    print(f"  {name}  {image.size[0]}x{image.size[1]}")


def clamp() -> None:
    size = CLAMP
    outer = mat.rounded_mask(size, size, 12)
    inner = mat.rounded_mask(size, size, 6, inset=CLAMP_MARGIN)
    ring = np.clip(outer - inner, 0.0, 1.0)
    field = mat.iron(size, size, 71)
    field = field * (1.0 + 0.45 * mat.lit(mat.bevel(ring, 2.0), 1.0)) \
        * (1.0 - 0.40 * mat.shade_dark(mat.bevel(ring, 2.0), 1.0))
    image = mat.rgba(field, ring)
    lines = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(lines)
    draw.rounded_rectangle((1, 1, size - 2, size - 2), radius=11,
                           outline=(0, 0, 0, 235), width=1)
    draw.rounded_rectangle((5, 5, size - 6, size - 6), radius=9,
                           outline=(0, 0, 0, 170), width=1)
    draw.rounded_rectangle((6, 6, size - 7, size - 7), radius=9,
                           outline=(146, 114, 62, 200), width=1)
    draw.rounded_rectangle((CLAMP_MARGIN, CLAMP_MARGIN, size - CLAMP_MARGIN - 1,
                            size - CLAMP_MARGIN - 1), radius=6,
                           outline=(0, 0, 0, 210), width=1)
    image = Image.alpha_composite(image, lines)
    for rx, ry in ((12, 12), (size - 12, 12), (12, size - 12), (size - 12, size - 12)):
        kit.rivet(image, rx, ry, 3.4)
    _save(uniform_edges(image, CLAMP_MARGIN, CLAMP_MARGIN), "clamp.png")


def rail() -> None:
    """The header rail: the iron band the title is engraved on."""
    w, h = 96, 60
    field = mat.iron(w, h, 73)
    image = mat.rgba(field)
    lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(lines)
    draw.line((0, h - 3, w, h - 3), fill=(0, 0, 0, 220), width=2)
    draw.line((0, h - 4, w, h - 4), fill=(146, 114, 62, 150), width=1)
    draw.line((0, 0, w, 0), fill=(0, 0, 0, 170), width=1)
    draw.line((0, 0, 0, h), fill=(0, 0, 0, 150), width=1)
    draw.line((w - 1, 0, w - 1, h), fill=(0, 0, 0, 150), width=1)
    image = Image.alpha_composite(image, lines)
    _save(uniform_edges(image, 12, 0), "rail.png")


def page() -> None:
    size = PAGE
    field = mat.parchment(size, size, 91)
    # The centre is stretched across the window: soften the directional fibres
    # so a large page reads as one sheet instead of banded grain.
    smooth = mat.gaussian_filter(field, (2.2, 2.2, 0))
    field = field * 0.62 + smooth * 0.38
    field *= np.clip(kit._page_light(size, size), 0.6, 1.15)[..., None]
    mask = kit.deckled_mask(size, size, 4, 92, cut=1.6, wobble=7.0)
    image = mat.rgba(field, mask)
    _save(uniform_edges(image, PAGE_MARGIN, PAGE_MARGIN), "page.png")


def plates() -> None:
    states = ["idle", "hover", "pressed", "disabled"]
    variants = ["iron", "brass", "lacquer"]
    w, h = PLATE
    mx, my = PLATE_MARGIN
    for variant in variants:
        for index, state in enumerate(states):
            rivets = [] if state == "disabled" or variant == "lacquer" else [
                (15, h / 2), (w - 15, h / 2)]
            image = kit.plate_image(variant, state, w, h, 500 + index, 5.0, rivets)
            _save(uniform_edges(image, mx, my), f"plate_{variant}_{state}.png")


def keycap() -> None:
    size = 64
    mask = mat.rounded_mask(size, size, 6)
    field = mat.bone(size, size, 77)
    shade = mat.bevel(mask, 2.0, 1.2)
    field = field * (1.0 + 0.45 * mat.lit(shade, 1.0)) * (1.0 - 0.30 * mat.shade_dark(shade, 1.0))
    image = mat.rgba(field, mask)
    lines = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(lines)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=6,
                           outline=(38, 26, 16, 220), width=1)
    draw.rounded_rectangle((4, 4, size - 5, size - 5), radius=4,
                           outline=(0, 0, 0, 60), width=1)
    draw.line((6, 6, size - 7, 6), fill=(255, 246, 222, 90), width=1)
    image = Image.alpha_composite(image, lines)
    _save(uniform_edges(image, 16, 16), "keycap.png")


def chips() -> None:
    colors = {"alive": (42, 92, 82, 255), "downed": (124, 62, 18, 255),
              "dead": (98, 92, 82, 255), "blood": (118, 24, 25, 255)}
    size = (72, 32)
    for name, color in colors.items():
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        draw.rectangle((0, 0, size[0] - 1, size[1] - 1), fill=(*color[:3], 26))
        draw.rectangle((0, 0, size[0] - 1, size[1] - 1), outline=(*color[:3], 150), width=1)
        _save(uniform_edges(layer, 12, 8), f"chip_{name}.png")


def seal() -> None:
    size = 96
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    kit.seal_rotated(layer, size / 2, size / 2, 29, seed=12, glyph="skull", angle=-6)
    _save(layer, "seal.png")


def icons() -> None:
    for key in ICON_KEYS:
        large = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        kit.medallion(large, 48, 48, 46, key, seed=140, lit_icon=True)
        _save(large, f"icon_lg_{key}.png")
        small = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        kit.medallion(small, 32, 32, 30, key, seed=140, lit_icon=True)
        _save(small, f"icon_sm_{key}.png")


def stamps() -> None:
    for name, color in (("lit", (170, 52, 30, 255)), ("dim", (122, 100, 72, 255))):
        size = 24
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        draw.ellipse((3, 3, size - 4, size - 4), outline=color, width=2)
        if name == "lit":
            draw.ellipse((9, 9, size - 10, size - 10), fill=color)
        _save(layer, f"stamp_{name}.png")


def page_shadow() -> None:
    """The clamp's lip falling on the page: a nine-slice shadow overlay."""
    size = 96
    margin = 32
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    edge = np.minimum(np.minimum(xx, size - 1 - xx), np.minimum(yy, size - 1 - yy))
    falloff = np.exp(-np.maximum(edge, 0.0) / 7.0) * 0.55
    falloff += np.exp(-np.maximum(edge, 0.0) / 26.0) * 0.18
    rgba = np.zeros((size, size, 4), np.float32)
    rgba[..., :3] = 0.0
    rgba[..., 3] = np.clip(falloff, 0.0, 1.0) * 255.0
    image = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    _save(uniform_edges(image, margin, margin), "page_shadow.png")


def manifest() -> None:
    data = {
        "clamp": {"file": "clamp.png", "margin": CLAMP_MARGIN},
        "page": {"file": "page.png", "margin": PAGE_MARGIN},
        "plate": {"margin_x": PLATE_MARGIN[0], "margin_y": PLATE_MARGIN[1],
                  "variants": ["iron", "brass", "lacquer"],
                  "states": ["idle", "hover", "pressed", "disabled"]},
        "keycap": {"file": "keycap.png", "margin": 16},
        "chip_margin": [12, 8],
        "chips": ["alive", "downed", "dead", "blood"],
        "icons": ICON_KEYS,
    }
    (OUT / "manifest.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    print("  manifest.json")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    print("theme atlas ->", OUT.relative_to(ROOT))
    clamp()
    rail()
    page()
    plates()
    keycap()
    chips()
    seal()
    stamps()
    page_shadow()
    icons()
    manifest()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
