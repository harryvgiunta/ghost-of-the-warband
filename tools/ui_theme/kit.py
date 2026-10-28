"""The component kit for the Blood Ledger menu language.

One window shape, one rack of buttons, one medallion, one seal, one keycap: the
shared furniture every screen in Ghost of the Warband is built from. The kit is
deliberately small - a menu theme reads as a theme because the same seven parts
appear in the same places on every screen, not because each screen invents a new
ornament.

Everything is drawn into PIL RGBA canvases. Ornament is generated at the widget's
own size, never 9-sliced by hand, but every edge ornament sits inside the outer
24 px so the production texture can cut an atlas without seams.
"""
from __future__ import annotations

import math
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import materials as mat

ROOT = Path(__file__).resolve().parent.parent.parent
FONT_DIR = ROOT / "assets" / "ui" / "fonts"

# --- palette ---------------------------------------------------------------

INK = (43, 28, 16, 255)
INK_SOFT = (74, 50, 29, 255)
INK_MUTED = (104, 78, 52, 255)
BLOOD = (118, 24, 25, 255)
BLOOD_DARK = (74, 12, 16, 255)
BONE = (233, 224, 203, 255)
BONE_DIM = (203, 191, 167, 255)
IRON_INK = (10, 12, 13, 255)
BRASS_TEXT = (36, 24, 10, 255)
EMBER = (224, 138, 60, 255)
SOUL = (127, 215, 196, 255)
SHADOW = (0, 0, 0, 255)
ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

FONTS = {
    "display": "PirataOne-Regular.ttf",
    "body": "IMFellEnglish-Regular.ttf",
    "italic": "IMFellEnglish-Italic.ttf",
}


@lru_cache(maxsize=96)
def font(size: int, family: str = "body") -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_DIR / FONTS[family]), size)


# --- type ------------------------------------------------------------------

def text_width(s: str, fnt: ImageFont.FreeTypeFont, tracking: float = 0.0) -> float:
    if not s:
        return 0.0
    return float(fnt.getlength(s)) + tracking * max(0, len(s) - 1)


def draw_text(img: Image.Image, xy: tuple[float, float], s: str,
              fnt: ImageFont.FreeTypeFont, fill, tracking: float = 0.0,
              align: str = "left") -> float:
    """Draw with letterspacing; returns the advance. `align` is left/center/right."""
    draw = ImageDraw.Draw(img)
    width = text_width(s, fnt, tracking)
    x, y = float(xy[0]), float(xy[1])
    if align == "center":
        x -= width * 0.5
    elif align == "right":
        x -= width
    if tracking == 0.0:
        draw.text((x, y), s, font=fnt, fill=fill)
        return width
    for ch in s:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += fnt.getlength(ch) + tracking
    return width


def engraved(img: Image.Image, xy: tuple[float, float], s: str,
             fnt: ImageFont.FreeTypeFont, fill, tracking: float = 0.0,
             align: str = "left", depth: float = 1.3) -> float:
    """Metal relief: a dark chisel shadow under the letter, light on its lip."""
    x, y = xy
    draw_text(img, (x + depth * 0.4, y + depth), s, fnt, (0, 0, 0, 165), tracking, align)
    draw_text(img, (x, y), s, fnt, fill, tracking, align)
    return text_width(s, fnt, tracking)


def wrap(s: str, fnt: ImageFont.FreeTypeFont, max_width: float,
         tracking: float = 0.0) -> list[str]:
    words = s.split()
    lines: list[str] = []
    line = ""
    for word in words:
        candidate = word if not line else line + " " + word
        if text_width(candidate, fnt, tracking) <= max_width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def paragraph(img: Image.Image, xy: tuple[float, float], s: str,
              fnt: ImageFont.FreeTypeFont, fill, max_width: float,
              line_gap: float = 8.0, align: str = "left",
              tracking: float = 0.0) -> float:
    x, y = xy
    line_height = fnt.size + line_gap
    for line in wrap(s, fnt, max_width, tracking):
        draw_text(img, (x, y), line, fnt, fill, tracking, align)
        y += line_height
    return y - line_gap


# --- small ironwork --------------------------------------------------------

def _dome(size: int, height: float = 0.55) -> np.ndarray:
    """A radial dome normal map in 0..1, for rivets, seals and buttons."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) * 0.5
    nx = (xx - c) / max(c, 1.0)
    ny = (yy - c) / max(c, 1.0)
    r2 = nx * nx + ny * ny
    nz = np.sqrt(np.clip(1.0 - r2, 0.0, 1.0)) * height
    normal = np.dstack([nx, ny, nz])
    light = np.array([mat.LIGHT[0], mat.LIGHT[1], 0.72], dtype=np.float32)
    light /= np.linalg.norm(light)
    lambert = normal @ light
    return np.clip(lambert * 0.5 + 0.5, 0.0, 1.0)


def rivet(img: Image.Image, cx: float, cy: float, radius: float = 4.0,
          tint=(0.30, 0.33, 0.35)) -> None:
    size = max(6, int(radius * 2) + 2)
    dome = _dome(size)
    mask = mat.ellipse_mask(size, size, 0.6)
    base = np.array(tint, np.float32)[None, None, :] * (0.55 + 0.85 * dome)[..., None]
    base = base + (dome[..., None] ** 6) * 0.35
    layer = mat.rgba(base, mask)
    img.alpha_composite(layer, (int(cx - size / 2), int(cy - size / 2)))


def nail(img: Image.Image, cx: float, cy: float, radius: float = 5.0) -> None:
    """A hand-forged nail head pinning the sheet: dome, slot, cold highlight."""
    size = int(radius * 2) + 4
    dome = _dome(size, 0.7)
    mask = mat.ellipse_mask(size, size, 0.5)
    base = np.array([0.20, 0.21, 0.22], np.float32)[None, None, :] * (0.4 + 1.1 * dome)[..., None]
    base += (dome[..., None] ** 8) * 0.45
    img.alpha_composite(mat.rgba(base, mask), (int(cx - size / 2), int(cy - size / 2)))
    draw = ImageDraw.Draw(img)
    draw.line((cx - radius * 0.55, cy + radius * 0.15, cx + radius * 0.5, cy - radius * 0.2),
              fill=(0, 0, 0, 170), width=max(1, int(radius * 0.28)))


def thorn(img: Image.Image, cx: float, cy: float, size: float, angle: float = 0.0,
          color=(0.42, 0.45, 0.46, 255)) -> None:
    """A forged thorn: two hooks and a point, used on dividers and corner spurs."""
    pts = [(0.0, -1.0), (0.45, -0.15), (0.15, 0.05), (0.55, 0.55),
           (0.0, 0.35), (-0.55, 0.55), (-0.15, 0.05), (-0.45, -0.15)]
    ca, sa = math.cos(angle), math.sin(angle)
    rot = [(cx + (x * ca - y * sa) * size, cy + (x * sa + y * ca) * size) for x, y in pts]
    draw = ImageDraw.Draw(img)
    draw.polygon(rot, fill=color)


def divider(img: Image.Image, x0: float, x1: float, y: float,
            ink=(122, 96, 66, 210), accent=(150, 40, 24, 255)) -> None:
    """An inked rule with a thorn at its heart - the section break of the ledger."""
    draw = ImageDraw.Draw(img)
    mid = (x0 + x1) * 0.5
    gap = 20.0
    for a, b in ((x0, mid - gap), (mid + gap, x1)):
        draw.line((a, y, b, y), fill=ink, width=1)
        draw.line((a, y + 1, b, y + 1), fill=(255, 244, 220, 40), width=1)
        for end, step in ((a, 1), (b, -1)):
            draw.line((end, y, end + step * 12, y), fill=ink, width=2)
            draw.line((end, y - 3, end + step * 4, y), fill=ink, width=1)
            draw.line((end, y + 3, end + step * 4, y), fill=ink, width=1)
    # Heart: a thorned lozenge.
    draw.polygon([(mid, y - 7), (mid + 5, y), (mid, y + 7), (mid - 5, y)], fill=accent)
    draw.line((mid - 14, y, mid - 6, y), fill=ink, width=1)
    draw.line((mid + 6, y, mid + 14, y), fill=ink, width=1)


def seal(img: Image.Image, cx: float, cy: float, radius: float, seed: int = 1,
         numeral: str = "", glyph: str = "skull") -> None:
    """A wax seal: irregular pressing, dome-lit rim, embossed sigil."""
    size = int(radius * 2.4)
    ss = 3
    canvas = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    rng = mat.make_rng(seed)
    phase = rng.uniform(0, math.tau)
    pts = []
    steps = 96
    for i in range(steps):
        a = i / steps * math.tau
        wobble = 1.0 + 0.055 * math.sin(3 * a + phase) + 0.030 * math.sin(7 * a + phase * 2)
        pts.append((size * ss / 2 + math.cos(a) * size * ss * 0.42 * wobble,
                    size * ss / 2 + math.sin(a) * size * ss * 0.42 * wobble))
    draw.polygon(pts, fill=(255, 255, 255, 255))
    mask = np.asarray(canvas, np.float32)[..., 3] / 255.0

    yy, xx = np.mgrid[0:size * ss, 0:size * ss].astype(np.float32)
    c = size * ss * 0.5
    nx = np.clip((xx - c) / (size * ss * 0.5), -1, 1)
    ny = np.clip((yy - c) / (size * ss * 0.5), -1, 1)
    dome = np.clip(1.0 - (nx * nx + ny * ny) * 0.7, 0.0, 1.0)
    wax_field = mat.wax(size * ss, size * ss, seed)
    lit_wax = wax_field * (0.55 + 1.0 * dome)[..., None]
    lit_wax += np.array([0.85, 0.55, 0.42], np.float32)[None, None, :] * (
        np.clip(mat.bevel(mask, 2.0), 0, 1) * 0.55)[..., None]
    lit_wax = mat.paste(lit_wax, np.array([0.10, 0.01, 0.02], np.float32)[None, None, :],
                        np.clip(-mat.bevel(mask, 2.0), 0, 1) * 0.45)
    seal_img = mat.rgba(lit_wax, mask).resize((size, size), Image.LANCZOS)
    img.alpha_composite(seal_img, (int(cx - size / 2), int(cy - size / 2)))

    # Emboss the sigil: a stamped hollow with a lit lower lip and a dark core.
    def _skull_layer(color):
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        if numeral:
            f = font(int(size * (0.40 if len(numeral) < 3 else 0.30)), "display")
            bb = f.getbbox(numeral)
            w_ = bb[2] - bb[0]
            ld.text((size / 2 - w_ / 2 - bb[0], size / 2 - f.size * 0.35 - bb[1]),
                    numeral, font=f, fill=color)
        elif size < 56:
            # At header size the die presses only a hollow: no glyph pretends to read.
            c_ = size / 2
            d_ = size * 0.10
            ld.ellipse((c_ - d_, c_ - d_, c_ + d_, c_ + d_), fill=color)
        elif glyph == "skull":
            scale = size * 0.34
            sk = skull_shape(scale)
            ox, oy = size / 2 - scale * 0.5, size / 2 - scale * 0.54
            for poly in sk["fills"]:
                ld.polygon([(x + ox, y + oy) for x, y in poly], fill=color)
            for hole in sk["holes"]:
                ld.ellipse([hole[0] + ox, hole[1] + oy, hole[2] + ox, hole[3] + oy],
                           fill=(0, 0, 0, 0))
        return layer

    body = _skull_layer((26, 2, 4, 245))
    lip = _skull_layer((236, 148, 118, 210))
    img.alpha_composite(lip, (int(cx - size / 2) - 1, int(cy - size / 2) - 2))
    img.alpha_composite(body, (int(cx - size / 2), int(cy - size / 2)))

    # The candle's gloss on the wax.
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd_ = ImageDraw.Draw(gloss)
    gd_.ellipse((size * 0.24, size * 0.20, size * 0.52, size * 0.42),
                fill=(255, 190, 160, 26))
    gloss = gloss.filter(_blur(size * 0.05))
    img.alpha_composite(gloss, (int(cx - size / 2), int(cy - size / 2)))

    # The die's pressed ring.
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rr = size * 0.235
    rd.ellipse((size / 2 - rr, size / 2 - rr, size / 2 + rr, size / 2 + rr),
               outline=(34, 2, 4, 150), width=max(1, int(size * 0.018)))
    rd.arc((size / 2 - rr, size / 2 - rr, size / 2 + rr, size / 2 + rr), 20, 200,
           fill=(232, 138, 112, 120), width=1)
    img.alpha_composite(ring, (int(cx - size / 2), int(cy - size / 2)))

    # A wet rim of light along the lower right of the pressing.
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.arc((size * 0.10, size * 0.10, size * 0.90, size * 0.90), 25, 150,
           fill=(236, 132, 100, 40), width=max(1, int(size * 0.022)))
    img.alpha_composite(ring, (int(cx - size / 2), int(cy - size / 2)))


def skull_shape(scale: float) -> dict:
    """A small horned skull in a 100-unit box, scaled for seals and medals."""
    def s(points):
        return [(x * scale / 100.0, y * scale / 100.0) for x, y in points]

    cranium = [(50, 8), (63, 11), (71, 20), (74, 32), (72, 43), (66, 51),
               (60, 54), (61, 60), (55, 65), (50, 66), (45, 65), (39, 60),
               (40, 54), (34, 51), (28, 43), (26, 32), (29, 20), (37, 11)]
    horn_l = [(29, 23), (19, 15), (9, 4), (5, 13), (9, 27), (17, 33), (25, 31)]
    horn_r = [(71, 23), (81, 15), (91, 4), (95, 13), (91, 27), (83, 33), (75, 31)]
    fills = [s(cranium), s(horn_l), s(horn_r)]
    holes = [(x * scale / 100.0, y * scale / 100.0,
              (x + w) * scale / 100.0, (y + h) * scale / 100.0)
             for (x, y, w, h) in [(36, 30, 10, 11), (54, 30, 10, 11), (47, 45, 6, 8)]]
    return {"fills": fills, "holes": holes}


def bullet(img: Image.Image, x: float, y: float, color=INK_SOFT, size: float = 4.0) -> None:
    """The list mark: a small thorned diamond, not a round dot."""
    draw = ImageDraw.Draw(img)
    draw.polygon([(x, y - size), (x + size * 0.8, y), (x, y + size), (x - size * 0.8, y)],
                 fill=color)


# --- icons -----------------------------------------------------------------

def icon_mask(key: str, size: int) -> Image.Image:
    """Line-relief pictograms drawn at 4x and reduced; callers tint and emboss."""
    ss = 4
    box = size * ss
    img = Image.new("L", (box, box), 0)
    d = ImageDraw.Draw(img)
    w = max(2, int(box * 0.105))
    u = box / 100.0

    def line(points, width=w):
        d.line([(x * u, y * u) for x, y in points], fill=255, width=width, joint="curve")

    def ellipse(box_, width=w, fill=0):
        d.ellipse([box_[0] * u, box_[1] * u, box_[2] * u, box_[3] * u],
                  outline=255, width=width, fill=fill)

    def rect(box_, width=w):
        d.rounded_rectangle([box_[0] * u, box_[1] * u, box_[2] * u, box_[3] * u],
                            radius=box_[4] * u, outline=255, width=width)

    if key == "scroll":
        line([(26, 22), (74, 22)])
        d.rounded_rectangle([22 * u, 18 * u, 78 * u, 82 * u], radius=6 * u, outline=255, width=w)
        for y in (36, 48, 60):
            line([(33, y), (67, y)], width=max(2, int(u * 5)))
        ellipse([16, 20, 32, 34], w)
        ellipse([16, 66, 32, 80], w)
        ellipse([68, 20, 84, 34], w)
        ellipse([68, 66, 84, 80], w)
    elif key == "helm":
        line([(50, 12), (76, 20), (82, 44), (76, 66), (62, 76), (50, 78)])
        line([(50, 12), (24, 20), (18, 44), (24, 66), (38, 76), (50, 78)])
        line([(50, 16), (50, 78)], width=max(2, int(u * 6)))
        line([(26, 44), (44, 44)], width=max(2, int(u * 6)))
        line([(56, 44), (74, 44)], width=max(2, int(u * 6)))
        line([(50, 60), (50, 74)])
    elif key == "banner":
        d.polygon([(34 * u, 14 * u), (74 * u, 18 * u), (66 * u, 34 * u),
                   (76 * u, 52 * u), (34 * u, 46 * u)], fill=255)
        d.polygon([(46 * u, 24 * u), (62 * u, 26 * u), (58 * u, 34 * u),
                   (62 * u, 40 * u), (46 * u, 38 * u)], fill=0)
        line([(30, 8), (30, 92)], width=max(3, int(u * 7)))
        line([(24, 20), (34, 22)], width=max(2, int(u * 5)))
        line([(24, 38), (34, 40)], width=max(2, int(u * 5)))
    elif key == "gear":
        teeth = []
        for i in range(8):
            a = i * math.tau / 8
            teeth.append(((50 + math.cos(a) * 34) * u, (50 + math.sin(a) * 34) * u))
        ellipse([16, 16, 84, 84], width=w)
        for i in range(8):
            a = i * math.tau / 8
            line([((50 + math.cos(a) * 26) * u / u, (50 + math.sin(a) * 26)),
                  ((50 + math.cos(a) * 40), (50 + math.sin(a) * 40))])
        d.ellipse([40 * u, 40 * u, 60 * u, 60 * u], fill=255)
    elif key == "flame":
        line([(50, 10), (64, 34), (72, 52), (62, 74), (50, 84), (38, 74), (28, 54), (36, 34), (50, 44)])
        line([(50, 44), (56, 58), (52, 70), (50, 72)], width=max(2, int(u * 5)))
    elif key == "eye":
        d.arc([10 * u, 24 * u, 90 * u, 76 * u], 200, 340, fill=255, width=w)
        d.arc([10 * u, 24 * u, 90 * u, 76 * u], 20, 160, fill=255, width=w)
        d.ellipse([38 * u, 38 * u, 62 * u, 62 * u], outline=255, width=w)
        d.ellipse([46 * u, 46 * u, 54 * u, 54 * u], fill=255)
    elif key == "coin":
        d.ellipse([24 * u, 30 * u, 76 * u, 82 * u], outline=255, width=w)
        d.arc([18 * u, 18 * u, 70 * u, 40 * u], 180, 360, fill=255, width=w)
        line([(50, 40), (50, 68)], width=max(2, int(u * 5)))
        line([(42, 46), (58, 46)], width=max(2, int(u * 5)))
        line([(42, 62), (58, 62)], width=max(2, int(u * 5)))
    elif key == "chain":
        ellipse([16, 20, 56, 56], w)
        ellipse([44, 44, 84, 80], w)
        d.ellipse([30 * u, 34 * u, 42 * u, 46 * u], fill=255)
    elif key == "key":
        d.ellipse([18 * u, 22 * u, 50 * u, 54 * u], outline=255, width=w)
        line([(46, 44), (80, 78)], width=max(3, int(u * 7)))
        line([(64, 62), (72, 54)], width=max(3, int(u * 7)))
        line([(72, 70), (80, 62)], width=max(3, int(u * 7)))
    elif key == "blade":
        d.polygon([(50 * u, 4 * u), (58 * u, 14 * u), (58 * u, 54 * u),
                   (50 * u, 64 * u), (42 * u, 54 * u), (42 * u, 14 * u)], fill=255)
        d.rectangle([32 * u, 58 * u, 68 * u, 67 * u], fill=255)
        d.rectangle([46 * u, 66 * u, 54 * u, 86 * u], fill=255)
        d.ellipse([44 * u, 84 * u, 56 * u, 95 * u], fill=255)
    elif key == "greaves":
        d.polygon([(20 * u, 22 * u), (38 * u, 16 * u), (42 * u, 58 * u),
                   (36 * u, 88 * u), (22 * u, 86 * u), (18 * u, 56 * u)], outline=255,
                  width=max(2, int(u * 5)))
        d.polygon([(80 * u, 22 * u), (62 * u, 16 * u), (58 * u, 58 * u),
                   (64 * u, 88 * u), (78 * u, 86 * u), (82 * u, 56 * u)], outline=255,
                  width=max(2, int(u * 5)))
        line([(24, 60), (38, 60)], width=max(2, int(u * 5)))
        line([(62, 60), (76, 60)], width=max(2, int(u * 5)))
    elif key == "cage":
        line([(24, 30), (24, 84)])
        line([(38, 30), (38, 84)])
        line([(50, 30), (50, 84)])
        line([(62, 30), (62, 84)])
        line([(76, 30), (76, 84)])
        line([(22, 30), (78, 30)], width=max(3, int(u * 7)))
        line([(22, 84), (78, 84)], width=max(3, int(u * 7)))
        d.arc([38 * u, 12 * u, 62 * u, 32 * u], 180, 360, fill=255, width=max(2, int(u * 6)))
    elif key == "chalice":
        line([(30, 20), (34, 52), (44, 62), (44, 74), (56, 74), (56, 62), (66, 52), (70, 20)])
        line([(30, 20), (70, 20)], width=max(3, int(u * 6)))
        ellipse([28, 12, 72, 26], w)
        line([(34, 74), (66, 74)], width=max(3, int(u * 6)))
    elif key == "skull":
        for poly in skull_shape(100.0)["fills"]:
            d.polygon([(x * u, y * u) for x, y in poly], fill=255)
        for hole in skull_shape(100.0)["holes"]:
            d.ellipse([hole[0] * u, hole[1] * u, hole[2] * u, hole[3] * u], fill=0)
    elif key == "altar":
        line([(20, 70), (80, 70)], width=max(3, int(u * 7)))
        line([(30, 70), (30, 88)])
        line([(70, 70), (70, 88)])
        line([(50, 62), (62, 44), (56, 24), (50, 34), (44, 24), (38, 44), (50, 62)])
        d.ellipse([44 * u, 12 * u, 56 * u, 22 * u], fill=255)
    elif key == "cuirass":
        d.polygon([(50 * u, 10 * u), (70 * u, 18 * u), (78 * u, 28 * u),
                   (72 * u, 36 * u), (68 * u, 60 * u), (62 * u, 88 * u),
                   (38 * u, 88 * u), (32 * u, 60 * u), (28 * u, 36 * u),
                   (22 * u, 28 * u), (30 * u, 18 * u)], fill=255)
        d.polygon([(50 * u, 10 * u), (58 * u, 21 * u), (50 * u, 28 * u),
                   (42 * u, 21 * u)], fill=0)
    elif key == "gauntlet":
        d.polygon([(36 * u, 24 * u), (48 * u, 14 * u), (60 * u, 20 * u),
                   (64 * u, 40 * u), (62 * u, 62 * u), (68 * u, 84 * u),
                   (32 * u, 84 * u), (34 * u, 62 * u), (26 * u, 44 * u)], fill=255)
        d.ellipse([24 * u, 34 * u, 40 * u, 58 * u], fill=255)
        line([(32, 72), (66, 72)], width=max(3, int(u * 6)))
    elif key == "boot":
        line([(34, 12), (58, 12), (60, 58), (78, 70), (80, 88), (36, 88), (34, 12)])
        line([(36, 74), (76, 74)], width=max(2, int(u * 5)))
    elif key == "amulet":
        d.arc([24 * u, 8 * u, 76 * u, 66 * u], 200, 340, fill=255, width=max(2, int(u * 6)))
        d.polygon([(50 * u, 56 * u), (62 * u, 74 * u), (50 * u, 92 * u), (38 * u, 74 * u)],
                  outline=255, width=max(2, int(u * 5)))
    elif key == "ring":
        d.ellipse([28 * u, 36 * u, 72 * u, 84 * u], outline=255, width=max(3, int(u * 7)))
        d.polygon([(50 * u, 8 * u), (60 * u, 22 * u), (50 * u, 34 * u), (40 * u, 22 * u)],
                  outline=255, width=max(2, int(u * 5)))
    elif key == "shield":
        line([(50, 10), (78, 20), (74, 52), (50, 88), (26, 52), (22, 20), (50, 10)])
        line([(50, 24), (50, 72)], width=max(2, int(u * 5)))
        line([(36, 38), (64, 38)], width=max(2, int(u * 5)))
    elif key == "bow":
        d.arc([16 * u, 10 * u, 84 * u, 90 * u], 300, 60, fill=255, width=max(3, int(u * 6)))
        d.line([(64 * u, 16 * u), (64 * u, 84 * u)], fill=255, width=max(2, int(u * 4)))
        line([(64, 26), (30, 50), (64, 74)], width=max(2, int(u * 5)))
    elif key == "staff":
        line([(38, 92), (58, 12)], width=max(3, int(u * 7)))
        line([(40, 26), (62, 26)], width=max(3, int(u * 6)))
        d.ellipse([48 * u, 6 * u, 66 * u, 24 * u], outline=255, width=max(2, int(u * 5)))
        d.ellipse([53 * u, 11 * u, 61 * u, 19 * u], fill=255)
    elif key == "spear":
        line([(34, 92), (60, 34)], width=max(3, int(u * 6)))
        d.polygon([(60 * u, 34 * u), (66 * u, 10 * u), (74 * u, 30 * u), (64 * u, 40 * u)],
                  outline=255, width=max(2, int(u * 5)))
        line([(52, 48), (66, 56)], width=max(2, int(u * 5)))
    elif key == "eye_ring":
        d.ellipse([12 * u, 12 * u, 88 * u, 88 * u], outline=255, width=w)
        d.arc([24 * u, 32 * u, 76 * u, 68 * u], 200, 340, fill=255, width=max(2, int(u * 6)))
        d.arc([24 * u, 32 * u, 76 * u, 68 * u], 20, 160, fill=255, width=max(2, int(u * 6)))
        d.ellipse([42 * u, 42 * u, 58 * u, 58 * u], fill=255)
    else:  # a plain thorned ring, the fallback mark
        d.ellipse([16 * u, 16 * u, 84 * u, 84 * u], outline=255, width=w)
    img = img.resize((size, size), Image.LANCZOS)
    return img


def _small_medallion(img: Image.Image, cx: float, cy: float, radius: float,
                     key: str, seed: int, lit_icon: bool) -> None:
    """Slot-size mark: a brass button with a dark cut glyph, so it still reads."""
    size = int(radius * 2) + 2
    mask = mat.ellipse_mask(size, size, 0.6)
    dome = _dome(size, 0.8)
    field = mat.brass(size, size, seed) * (0.72 + 0.60 * dome)[..., None]
    disc = mat.rgba(field, mask)
    draw = ImageDraw.Draw(disc)
    draw.ellipse((1, 1, size - 2, size - 2), outline=(58, 38, 14, 235),
                 width=max(1, int(radius * 0.13)))
    draw.arc((2, 2, size - 3, size - 3), 200, 340, fill=(246, 216, 154, 120), width=1)
    img.alpha_composite(disc, (int(cx - size / 2), int(cy - size / 2)))

    icon = icon_mask(key, int(radius * 1.58))
    arr = np.asarray(icon, np.float32) / 255.0
    shade = mat.bevel(arr, 1.0)
    dark = np.broadcast_to(np.array([0.105, 0.072, 0.040], np.float32)[None, None, :],
                           (arr.shape[0], arr.shape[1], 3)).copy()
    dark = dark * (0.70 + 0.55 * np.clip(-shade, 0, 1))[..., None]
    img.alpha_composite(mat.rgba(dark, arr * (0.95 if lit_icon else 0.80)),
                        (int(cx - icon.width / 2), int(cy - icon.height / 2)))


def medallion(img: Image.Image, cx: float, cy: float, radius: float, key: str,
              seed: int = 1, lit_icon: bool = True) -> None:
    """Iron disc with a brass-etched pictogram: the left shoulder of every header."""
    if radius <= 16:
        _small_medallion(img, cx, cy, radius, key, seed, lit_icon)
        return
    size = int(radius * 2) + 2
    mask = mat.ellipse_mask(size, size, 0.6)
    field = mat.iron(size, size, seed, rough=0.7)
    dome = _dome(size, 0.8)
    field = field * (0.70 + 0.70 * dome)[..., None]
    disc = mat.rgba(field, mask)
    # Brass rim.
    draw = ImageDraw.Draw(disc)
    draw.ellipse((1, 1, size - 2, size - 2), outline=(92, 74, 40, 210), width=max(1, int(radius * 0.10)))
    draw.arc((3, 3, size - 4, size - 4), 200, 340, fill=(196, 166, 105, 90), width=1)
    img.alpha_composite(disc, (int(cx - size / 2), int(cy - size / 2)))

    icon = icon_mask(key, int(radius * 1.56))
    icon_arr = np.asarray(icon, np.float32) / 255.0
    icon_shade = mat.bevel(icon_arr, 1.2)
    brass_field = mat.brass(icon_arr.shape[1], icon_arr.shape[0], seed + 4)
    fill = brass_field * (0.95 + 0.65 * np.clip(icon_shade, 0, 1))[..., None]
    if not lit_icon:
        fill = brass_field * (0.60 + 0.30 * np.clip(icon_shade, 0, 1))[..., None]
    # A dark chisel bed under the motif so it reads on the iron.
    bed = mat.rgba(np.zeros_like(fill), icon_arr * 0.55)
    img.alpha_composite(bed, (int(cx - icon.width / 2) + 1, int(cy - icon.height / 2) + 1))
    img.alpha_composite(mat.rgba(fill, icon_arr), (int(cx - icon.width / 2), int(cy - icon.height / 2)))


# --- controls --------------------------------------------------------------

def _plate(material_fn, w: int, h: int, seed: int, radius: float = 4.0,
           bevel_strength: float = 1.0) -> np.ndarray:
    mask = mat.rounded_mask(w, h, radius)
    field = material_fn(w, h, seed)
    shade = mat.bevel(mask, 2.2, bevel_strength)
    field = field * (1.0 + 0.55 * mat.lit(shade, 1.0)) * (1.0 - 0.40 * mat.shade_dark(shade, 1.0))
    return field, mask


def plate_image(variant: str, state: str, w: int, h: int, seed: int,
                radius: float = 5.0,
                rivets: list[tuple[float, float]] | None = None) -> Image.Image:
    """A plate with its keylines and rivets baked in - the one renderer shared by
    the concept boards and the production texture atlas."""
    ss = 2
    W, H = w * ss, h * ss
    r = radius * ss
    fill = {
        "iron": lambda W_, H_, s: mat.iron(W_, H_, s, rough=0.75),
        "brass": lambda W_, H_, s: mat.brass(W_, H_, s),
        "lacquer": lambda W_, H_, s: mat.leather(W_, H_, s) * 0.75,
    }[variant]
    field, mask = _plate(fill, W, H, seed, r, 1.1)
    if variant == "brass":
        field = field * 0.95 + np.array([0.10, 0.07, 0.02], np.float32)[None, None, :]
    if variant == "lacquer":
        field = mat.paste(field, np.array([0.36, 0.055, 0.06], np.float32)[None, None, :],
                          np.full((H, W), 0.55, np.float32))
    yy_grad = np.linspace(1.08, 0.86, H, dtype=np.float32)[:, None, None]
    field = field * yy_grad
    if state == "hover":
        field = field * 1.20
        glow = mat.rounded_mask(W, H, r) - mat.rounded_mask(W, H, r, inset=3 * ss)
        field += np.array([0.16, 0.075, 0.02], np.float32)[None, None, :] * glow[..., None]
    elif state == "pressed":
        field = field * 0.56
        inner_m = mat.rounded_mask(W, H, r, inset=2 * ss)
        edge = np.clip(inner_m - mat.rounded_mask(W, H, r, inset=4 * ss), 0, 1)
        field *= (1.0 - 0.55 * edge)[..., None]
    elif state == "disabled":
        grey = field.mean(axis=2, keepdims=True)
        field = np.repeat(grey * 0.92, 3, axis=2)
    layer = mat.rgba(field, mask).resize((w, h), Image.LANCZOS)

    draw = ImageDraw.Draw(layer)
    draw.rectangle((1, 1, w - 2, h - 2), outline=(0, 0, 0, 160), width=1)
    inner = (4, 4, w - 5, h - 5)
    if variant == "lacquer":
        draw.rectangle(inner, outline=(126, 94, 50, 140), width=1)
    else:
        draw.rectangle(inner, outline=(0, 0, 0, 110), width=1)
        draw.line((inner[0], inner[1], inner[2], inner[1]),
                  fill=(255, 238, 198, 40), width=1)
        draw.line((inner[0], inner[3], inner[2], inner[3]),
                  fill=(0, 0, 0, 120), width=1)
    if variant in ("iron", "brass") and state != "disabled" and rivets:
        for rx, ry in rivets:
            rivet(layer, rx, ry, max(2.0, h * 0.06),
                  tint=(0.34, 0.36, 0.37) if variant == "iron" else (0.72, 0.58, 0.32))
    return layer


def button(img: Image.Image, rect: tuple[float, float, float, float], label: str,
           variant: str = "iron", state: str = "idle", seed: int = 1,
           keycap_label: str = "", label_size: int = 20,
           tracking: float = 5.0) -> None:
    """One rack of plates: iron (secondary), brass (primary), lacquer (danger).

    States are `idle`, `hover`, `pressed` and `disabled`, and they differ only in
    light and depth - the shape and the label never move.
    """
    x0, y0, x1, y1 = [int(round(v)) for v in rect]
    w, h = x1 - x0, y1 - y0
    rivets = [] if state == "disabled" or variant == "lacquer" else [
        (w * 0.10, h * 0.5), (w * 0.90, h * 0.5)]
    img.alpha_composite(plate_image(variant, state, w, h, seed, 5.0, rivets), (x0, y0))

    label_fill = BRASS_TEXT if variant == "brass" else (BONE if state != "disabled" else (150, 142, 126, 255))
    if variant == "brass" and state == "hover":
        label_fill = (26, 16, 6, 255)
    f = font(max(11, int(label_size)), "body")
    # Draw at supersampled scale for even spacing, then composite.
    if w > 48:
        tx = (x0 + x1) * 0.5
        if keycap_label:
            cap_w = int(h * 0.52)
            text_gap = 8
            lab_w = text_width(label, f, tracking)
            total = cap_w + text_gap + lab_w
            cx = (x0 + x1) * 0.5 - total * 0.5
            keycap(img, (cx, y0 + (h - cap_w) * 0.5), keycap_label, size=cap_w,
                   tone="bone", state=state)
            lab_x = cx + cap_w + text_gap
            lab_y = y0 + h * 0.5 - f.size * 0.5 + 2
            draw_text(img, (lab_x, lab_y), label, f, label_fill, tracking)
        else:
            draw_text(img, (tx, y0 + h * 0.5 - f.size * 0.55), label, f, label_fill,
                      tracking, "center")
def keycap(img: Image.Image, xy: tuple[float, float], label: str, size: int = 34,
           tone: str = "bone", state: str = "idle") -> int:
    """A carved key tile: the control hint that sits beside the words it belongs to."""
    x, y = int(xy[0]), int(xy[1])
    ss = 3
    W = size * ss
    mask = mat.rounded_mask(W, W, 5 * ss)
    fill = mat.bone(W, W, 11) if tone == "bone" else mat.iron(W, W, 12, rough=0.5)
    shade = mat.bevel(mask, 2.0, 1.2)
    fill = fill * (1.0 + 0.45 * mat.lit(shade, 1.0)) * (1.0 - 0.30 * mat.shade_dark(shade, 1.0))
    if state == "hover":
        fill = fill * 1.12
    tile = mat.rgba(fill, mask).resize((size, size), Image.LANCZOS)
    img.alpha_composite(tile, (x, y))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((x, y, x + size - 1, y + size - 1), radius=max(2, size // 7),
                           outline=(38, 26, 16, 200) if tone == "bone" else (0, 0, 0, 170),
                           width=max(1, size // 20))
    f = font(max(9, int(size * 0.54)), "body")
    fill_col = (44, 30, 18, 255) if tone == "bone" else (222, 214, 196, 255)
    draw.text((x + size * 0.5, y + size * 0.5 + size * 0.02), label, font=f,
              fill=fill_col, anchor="mm")
    return size


def chip(img: Image.Image, x: float, y: float, label: str, color=BLOOD,
         size: int = 13) -> float:
    """A stamped state chip (ALIVE / DOWNED / DEAD): inked box, letterspaced."""
    f = font(size, "body")
    w = text_width(label, f, 1.4) + 16
    h = size + 10
    layer = Image.new("RGBA", (int(w) + 2, int(h) + 2), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rectangle((0, 0, int(w), int(h)), fill=(*color[:3], 26))
    ld.rectangle((0, 0, int(w), int(h)), outline=(*color[:3], 150), width=1)
    draw_text(layer, (8, 4), label, f, color, 1.4)
    img.alpha_composite(layer, (int(x), int(y)))
    return w


# --- window ----------------------------------------------------------------

def deckled_mask(w: int, h: int, radius: float, seed: int,
                 cut: float = 2.0, wobble: float = 9.0) -> np.ndarray:
    """A hand-cut page edge: the clamp's page is torn, never a clean rectangle."""
    base = mat.rounded_mask(w, h, radius)
    edge = _edge_distance(w, h)
    n = mat.fbm(w, h, seed, octaves=4, scale=max(8, min(w, h) // 22))
    ragged = np.clip((edge + (n - 0.5) * wobble - cut) / 1.4, 0.0, 1.0)
    return np.clip(base * ragged, 0.0, 1.0)


def forged_mask(w: int, h: int, radius: float, seed: int) -> np.ndarray:
    """A clamp whose silhouette has been banged against things for years."""
    base = mat.rounded_mask(w, h, radius)
    edge = _edge_distance(w, h)
    chip = mat.fbm(w, h, seed, octaves=4, scale=7)
    keep = np.clip(edge + (chip - 0.5) * 3.2 - 0.4, 0.0, 1.0)
    return np.clip(base * np.clip(keep, 0.0, 1.0), 0.0, 1.0)


def _page_light(w: int, h: int) -> np.ndarray:
    """A warm pool of light at the heart of the page, falling away to the clamp."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / max(1, w - 1)) * 2.0 - 1.0
    ny = (yy / max(1, h - 1)) * 2.0 - 1.0
    r = np.sqrt(nx * nx * 0.92 + ny * ny)
    directional = 1.0 + 0.055 * (-nx - ny) * 0.5
    return np.clip(1.03 - 0.16 * r * r, 0.80, 1.04) * directional


def watermark(img: Image.Image, cx: float, cy: float, radius: float,
              key: str = "eye_ring", alpha: float = 0.07, color=INK) -> None:
    """An inked marginal sigil: the page was stamped before it was written on."""
    icon = icon_mask(key, int(radius * 2))
    arr = np.asarray(icon, np.float32) / 255.0
    tint = np.array(color[:3], np.float32)[None, None, :] / 255.0
    tint = np.broadcast_to(tint, (arr.shape[0], arr.shape[1], 3)).copy()
    img.alpha_composite(mat.rgba(tint, arr * alpha),
                        (int(cx - icon.width / 2), int(cy - icon.height / 2)))


def seal_rotated(img: Image.Image, cx: float, cy: float, radius: float, seed: int = 1,
                 numeral: str = "", glyph: str = "skull", angle: float = 0.0) -> None:
    size = int(radius * 3.0)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    seal(layer, size * 0.5, size * 0.5, radius, seed, numeral, glyph)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC)
    img.alpha_composite(layer, (int(cx - size * 0.5), int(cy - size * 0.5)))


def drop_cap_paragraph(img: Image.Image, xy: tuple[float, float], s: str,
                       cap_font: ImageFont.FreeTypeFont, cap_fill,
                       body_font: ImageFont.FreeTypeFont, body_fill,
                       max_width: float, line_gap: float = 8.0,
                       cap_lines: int = 2, cap_margin: float = 12.0) -> float:
    """A manuscript opening: illuminated initial, first lines indented round it."""
    x, y = float(xy[0]), float(xy[1])
    line_height = body_font.size + line_gap
    first = s[:1]
    words = s[1:].split()
    block = cap_lines * line_height - line_gap
    # Size the initial by measured cap height, then seat it on the last baseline.
    for _ in range(6):
        bbox = cap_font.getbbox("H")
        height = max(1, bbox[3] - bbox[1])
        if abs(height - block) <= 2:
            break
        cap_font = font(max(12, int(cap_font.size * (block * 1.04) / height)), "display")
    bbox = cap_font.getbbox("H")
    cap_w = float(cap_font.getbbox(first)[2] - cap_font.getbbox(first)[0]) + cap_margin
    baseline = y + block
    top = baseline - (bbox[1] + (bbox[3] - bbox[1]))
    draw_text(img, (x - cap_font.getbbox(first)[0], top), first, cap_font, cap_fill)

    short_width = max_width - cap_w
    head: list[str] = []
    row = ""
    used = 0
    for word in words:
        candidate = word if not row else row + " " + word
        if text_width(candidate, body_font) <= short_width or not row:
            row = candidate
            used += 1
            continue
        head.append(row)
        row = word
        used += 1
        if len(head) >= cap_lines:
            break
    if row and len(head) < cap_lines:
        head.append(row)
    remainder = words[used:]
    yy = y
    for line in head:
        draw_text(img, (x + cap_w, yy), line, body_font, body_fill)
        yy += line_height
    tail = " ".join(remainder)
    if tail:
        for line in wrap(tail, body_font, max_width):
            draw_text(img, (x, yy), line, body_font, body_fill)
            yy += line_height
    return yy - line_gap


def _edge_distance(w: int, h: int) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    return np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))


def window(canvas: Image.Image, rect: tuple[float, float, float, float],
           title: str = "", icon_key: str = "scroll", seed: int = 1,
           header: bool = True, header_height: int = 58,
           close: bool = False, footer_height: int = 0,
           engrave_title: bool = True, stamp: str = "",
           seal_glyph: str = "skull", seal: bool = True) -> tuple[int, int, int, int]:
    """The one frame: forged iron clamp, brass studs, torn vellum page.

    Returns the content rectangle (x0, y0, x1, y1) inside the page.
    """
    x0, y0, x1, y1 = [int(round(v)) for v in rect]
    w, h = x1 - x0, y1 - y0
    radius = 14

    # Cast shadow: the window sits over the world, not in it.
    shadow = Image.new("RGBA", (w + 96, h + 96), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((48, 56, 48 + w, 56 + h), radius=radius, fill=(0, 0, 0, 165))
    shadow = shadow.filter(_blur(20))
    canvas.alpha_composite(shadow, (x0 - 48, y0 - 48))

    # Forged iron clamp, with one fine hammer relief pass over the base field.
    iron_field = mat.iron(w, h, seed, rough=1.0)
    hammer = mat.fbm(w, h, seed + 5, octaves=5, scale=13)
    gy, gx = np.gradient(mat.gaussian_filter(hammer, 1.6))
    relief = np.clip(gx * mat.LIGHT[0] + gy * mat.LIGHT[1], -1, 1)
    peak = max(1e-6, float(np.abs(relief).max()))
    relief = relief / peak
    iron_field = iron_field * (1.0 + 0.52 * np.clip(relief, 0, 1)[..., None]) \
        * (1.0 - 0.40 * np.clip(-relief, 0, 1)[..., None])
    mask = forged_mask(w, h, radius, seed + 17)
    shade = mat.bevel(mask, 3.0, 1.0)
    iron_field = iron_field * (1.0 + 0.70 * mat.lit(shade, 1.0)) \
        * (1.0 - 0.52 * mat.shade_dark(shade, 1.0))
    canvas.alpha_composite(mat.rgba(iron_field, mask), (x0, y0))

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=radius,
                           outline=(0, 0, 0, 235), width=1)
    # The forged groove that runs round the clamp.
    draw.rounded_rectangle((x0 + 9, y0 + 9, x1 - 10, y1 - 10), radius=radius - 4,
                           outline=(0, 0, 0, 150), width=1)
    draw.rounded_rectangle((x0 + 10, y0 + 10, x1 - 11, y1 - 11), radius=radius - 4,
                           outline=(168, 176, 178, 30), width=1)

    # Vellum: torn edge, warm heart.
    inset = 21
    vx0, vy0 = x0 + inset, y0 + inset
    vx1, vy1 = x1 - inset, y1 - inset
    if header:
        vy0 += header_height - inset
    vw, vh = vx1 - vx0, vy1 - vy0
    page = mat.parchment(vw, vh, seed + 7)
    page = page * _page_light(vw, vh)[..., None]
    page_mask = deckled_mask(vw, vh, 5, seed + 13)
    canvas.alpha_composite(mat.rgba(page, page_mask), (vx0, vy0))

    # The cut edge of the sheet catches light along its top and left.
    edge_light = np.clip(page_mask - mat.rounded_mask(vw, vh, 5, inset=1.6), 0.0, 1.0)
    canvas.alpha_composite(mat.rgba(np.ones((vh, vw, 3), np.float32), edge_light * 0.28),
                           (vx0, vy0 - 1))

    # The clamp bites the page.
    lip = np.clip(page_mask - deckled_mask(vw, vh, 5, seed + 13, cut=4.0), 0.0, 1.0)
    canvas.alpha_composite(mat.rgba(np.zeros((vh, vw, 3), np.float32), lip * 0.42),
                           (vx0, vy0))
    fall = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fall)
    fd.rounded_rectangle((0, 0, vw - 1, vh - 1), radius=6, outline=(0, 0, 0, 88), width=11)
    fall = fall.filter(_blur(8))
    canvas.alpha_composite(fall, (vx0, vy0))

    # A brass hairline runs round the clamp: the one warm line in the ironwork.
    draw.rounded_rectangle((x0 + 6, y0 + 6, x1 - 7, y1 - 7), radius=radius - 3,
                           outline=(0, 0, 0, 170), width=1)
    draw.rounded_rectangle((x0 + 5, y0 + 5, x1 - 6, y1 - 6), radius=radius - 3,
                           outline=(140, 110, 60, 120), width=1)

    # The page throws its candlelight back onto the clamp's lower lip.
    bounce = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bounce)
    bd.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius,
                         outline=(64, 38, 18, 0), width=9)
    warm = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    wd = ImageDraw.Draw(warm)
    wd.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, outline=(255, 186, 104, 54),
                         width=3)
    warm = warm.filter(_blur(3))
    canvas.alpha_composite(warm, (x0, y0))

    # Header: medallion, engraved name, heraldic rules.
    if header:
        hy = y0 + inset + header_height * 0.5
        if icon_key:
            medallion(canvas, x0 + 16 + 23, hy, 23, icon_key, seed + 3)
        if title:
            f = font(29, "display")
            label = title.upper()
            title_y = hy - 23
            if engrave_title:
                engraved(canvas, ((x0 + x1) * 0.5, title_y), label, f,
                         (228, 220, 200, 255), 3.2, "center", 1.4)
            else:
                draw_text(canvas, ((x0 + x1) * 0.5, title_y), label, f,
                          (228, 220, 200, 255), 3.2, "center")
            tw = text_width(label, f, 3.2)
            left = (x0 + x1) * 0.5 - tw * 0.5 - 22
            right = (x0 + x1) * 0.5 + tw * 0.5 + 22
            head_left = x0 + 16 + 46 + 20
            head_right = x1 - 26
            for a, b, outer in ((head_left, left, -1), (right, head_right, 1)):
                if b - a < 30:
                    continue
                draw.line((a, hy, b, hy), fill=(0, 0, 0, 190), width=1)
                draw.line((a, hy + 1, b, hy + 1), fill=(150, 158, 158, 46), width=1)
                dx = b if outer > 0 else a
                draw.polygon([(dx, hy - 4), (dx + 4, hy), (dx, hy + 4), (dx - 4, hy)],
                             fill=(0, 0, 0, 190))
                draw.polygon([(dx, hy - 3), (dx + 3, hy), (dx, hy + 3), (dx - 3, hy)],
                             fill=(142, 148, 148, 150))
        rule_y = y0 + inset + header_height - 1
        draw.line((x0 + 44, rule_y, x1 - 44, rule_y), fill=(0, 0, 0, 200), width=1)
        draw.line((x0 + 44, rule_y + 1, x1 - 44, rule_y + 1), fill=(140, 148, 148, 40), width=1)
        if seal:
            seal_rotated(canvas, x1 - 36, hy, 18, seed + 9, numeral=stamp,
                         glyph=seal_glyph, angle=13)
            if close:
                draw_text(canvas, (x1 - 42.5, hy - 9), "X", font(13, "body"),
                          (240, 226, 210, 230), 0, "left")

    # Rivets on the clamp, inset so a 9-slice cannot cut them.
    for rx, ry in ((23, 23), (w - 23, 23), (23, h - 23), (w - 23, h - 23)):
        rivet(canvas, x0 + rx, y0 + ry, 3.4)
    for side_x in (x0 + 7, x1 - 7):
        rivet(canvas, side_x, (y0 + y1) * 0.5, 3.0)

    pad = 40
    return (vx0 + pad, vy0 + 30, vx1 - pad, vy1 - 34)


def _blur(sigma: float):
    from PIL import ImageFilter
    return ImageFilter.GaussianBlur(sigma)


def progress(img: Image.Image, cx: float, y: float, count: int, active: int,
             size: float = 8.0, gap: float = 30.0) -> None:
    """The tutorial's chapter marks: a stamped thorned ring per beat."""
    draw = ImageDraw.Draw(img)
    x = cx - (count - 1) * gap * 0.5
    f = font(11, "body")
    for i in range(count):
        live = i <= active
        color = (150, 44, 26, 255) if live else (122, 100, 72, 255)
        r = size
        draw.line((x - gap * 0.5 + r * 1.6, y, x - r * 1.7, y),
                  fill=(122, 100, 72, 120), width=1)
        draw.ellipse((x - r, y - r, x + r, y + r), outline=color,
                     width=2 if live else 1)
        if live:
            draw.ellipse((x - r * 0.42, y - r * 0.42, x + r * 0.42, y + r * 0.42),
                         fill=(170, 52, 30, 230))
        draw.text((x, y + r + 3), ROMAN[i] if i < len(ROMAN) else "", font=f,
                  fill=(120, 96, 68, 220), anchor="mt")
        x += gap
