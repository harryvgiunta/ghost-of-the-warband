"""The theme sheet: the one board that states what every other board obeys.

Materials, the clamp anatomy, the plate rack, the small marks, the marks' rack
and the type. If a screen in this game looks like it belongs to the same game,
it is because it uses these seven parts and no others.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from . import kit
from . import materials as mat
from .kit import (
    BLOOD, BONE, INK, INK_MUTED, INK_SOFT, button, chip, divider, draw_text, font,
    keycap, text_width,
)

W, H = 1600, 1620
BONE_DIM = (206, 194, 172, 255)
BONE_FAINT = (152, 140, 122, 255)
BRASS_LABEL = (186, 148, 88, 255)
MARGIN = 60


def sheet() -> Image.Image:
    canvas = _board()
    draw = ImageDraw.Draw(canvas)

    draw_text(canvas, (MARGIN, 54), "THE BLOOD LEDGER", font(58, "display"),
              (238, 226, 204, 255), 3.4)
    draw_text(canvas, (MARGIN + 2, 124),
              "ONE SHARED MENU LANGUAGE  \u00b7  CONCEPT BOARD v1", font(13, "body"),
              BRASS_LABEL, 3.2)
    draw_text(canvas, (W - MARGIN - 70, 56), "GHOST OF THE WARBAND", font(13, "body"),
              BONE_FAINT, 3.0, "right")
    draw_text(canvas, (W - MARGIN - 70, 78),
              "one clamp  \u00b7  one page  \u00b7  one rack  \u00b7  one seal",
              font(12, "italic"), BONE_FAINT, 0.0, "right")
    kit.seal_rotated(canvas, W - MARGIN - 26, 108, 26, seed=4, glyph="skull", angle=-8)
    draw.line((MARGIN, 176, W - MARGIN, 176), fill=(120, 96, 62, 210), width=1)
    draw.line((MARGIN, 177, W - MARGIN, 177), fill=(240, 216, 176, 34), width=1)

    _materials(canvas, 208)
    _clamp(canvas, 430)
    _plates(canvas, 830)
    _marks(canvas, 1130)
    _type_and_icons(canvas, 1260)

    draw.line((MARGIN, H - 74, W - MARGIN, H - 74), fill=(120, 96, 62, 150), width=1)
    draw_text(canvas, (MARGIN, H - 56),
              "Every screen is the same object: a forged clamp gripping a torn page, sealed in wax.",
              font(14, "italic"), BONE_DIM)
    draw_text(canvas, (W - MARGIN, H - 56), "01  /  THEME SHEET", font(12, "body"),
              BONE_FAINT, 2.6, "right")
    return canvas.convert("RGB")


def _board() -> Image.Image:
    """A dark leather workbench, not a screenshot: the swatches are the subject."""
    field = mat.leather(W, H, 91) * 0.55
    grain = mat.fbm(W, H, 92, octaves=5, scale=9)
    field *= (0.86 + 0.28 * grain)[..., None]
    ny, nx = np.mgrid[0:H, 0:W].astype(np.float32)
    vx = nx / (W - 1) * 2 - 1
    vy = ny / (H - 1) * 2 - 1
    field *= np.clip(1.0 - 0.45 * (vx * vx + vy * vy), 0.25, 1.0)[..., None]
    canvas = mat.rgba(field).convert("RGB").convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((26, 26, W - 27, H - 27), outline=(92, 74, 46, 100), width=1)
    draw.rectangle((30, 30, W - 31, H - 31), outline=(210, 180, 130, 28), width=1)
    return canvas


def _label(canvas: Image.Image, y: float, number: str, name: str) -> None:
    draw_text(canvas, (MARGIN, y), number, font(16, "display"), (170, 54, 34, 255), 1.0)
    draw_text(canvas, (MARGIN + 34, y + 2), name, font(13, "body"), BONE, 4.0)
    draw = ImageDraw.Draw(canvas)
    draw.line((MARGIN + 34 + text_width(name, font(13, "body"), 4.0) + 18, y + 10,
               W - MARGIN, y + 10), fill=(110, 90, 60, 150), width=1)


def _materials(canvas: Image.Image, y: float) -> None:
    _label(canvas, y, "01", "MATERIALS")
    tiles = [
        ("FORGED IRON", "clamp, frames", lambda W_, H_, s: mat.iron(W_, H_, s)),
        ("VELLUM", "every page", lambda W_, H_, s: mat.parchment(W_, H_, s)),
        ("OXBLOOD LEATHER", "title, HUD plates", lambda W_, H_, s: mat.leather(W_, H_, s)),
        ("BRASS", "primary action", lambda W_, H_, s: mat.brass(W_, H_, s)),
        ("SEALING WAX", "seal, danger", lambda W_, H_, s: mat.wax(W_, H_, s)),
        ("CARVED BONE", "keycaps, labels", lambda W_, H_, s: mat.bone(W_, H_, s)),
        ("SOUL LIGHT", "possession only", lambda W_, H_, s: mat.soul(W_, H_, s)),
    ]
    tw, th, gap = 196, 116, 14
    x = MARGIN
    for index, (name, use, fn) in enumerate(tiles):
        mask = mat.rounded_mask(tw, th, 6)
        field = fn(tw, th, 300 + index)
        shade = mat.bevel(mask, 2.2, 1.0)
        field = field * (1.0 + 0.35 * mat.lit(shade, 1.0)) * (1.0 - 0.30 * mat.shade_dark(shade, 1.0))
        canvas.alpha_composite(mat.rgba(field, mask), (int(x), int(y + 24)))
        draw = ImageDraw.Draw(canvas)
        draw.rounded_rectangle((x, y + 24, x + tw - 1, y + 24 + th - 1), radius=6,
                               outline=(0, 0, 0, 190), width=1)
        draw_text(canvas, (x, y + 152), name, font(11, "body"), BONE, 2.6)
        draw_text(canvas, (x, y + 170), use, font(11, "italic"), BONE_FAINT)
        x += tw + gap


def _clamp(canvas: Image.Image, y: float) -> None:
    _label(canvas, y, "02", "THE CLAMP")
    rect = (MARGIN, y + 34, MARGIN + 720, y + 34 + 330)
    content = kit.window(canvas, rect, "The Clamp", "scroll", seed=6, header_height=56)
    cx0, cy0, cx1, cy1 = content
    draw_text(canvas, (cx0, cy0), "STEP I  \u00b7  THE LESSON", font(12, "body"), BLOOD, 3.0)
    draw_text(canvas, (cx0, cy0 + 24), "A forged clamp holds a torn page",
              font(31, "display"), INK)
    draw_text(canvas, (cx0, cy0 + 70),
              "Every menu in the game is this one object at a different size.",
              font(16, "body"), INK)
    draw_text(canvas, (cx0, cy0 + 94),
              "The page carries the words; the iron carries title and seal.",
              font(16, "body"), INK)
    divider(canvas, cx0, cx1 - 250, cy0 + 136)
    plate = (cx1 - 220, cy0 + 112, cx1, cy0 + 158)
    button(canvas, plate, "CONTINUE", "brass", "idle", seed=44, label_size=14,
           tracking=3.0)

    x0, y0 = rect[0], rect[1]
    pins = [
        ("1", x0 + 6, y0 + 6),
        ("2", x0 + 10, y0 + 150),
        ("3", x0 + 34, y0 + 3),
        ("4", x0 + 700, y0 + 8),
        ("5", x0 + 52, y0 + 34),
        ("6", x0 + 684, y0 + 34),
        ("7", cx0 + 40, cy0 - 14),
        ("8", (plate[0] + plate[2]) * 0.5, plate[1] - 14),
    ]
    for number, px, py in pins:
        _pin(canvas, number, px, py)

    lx = MARGIN + 770
    legend = [
        ("1", "Outer keyline", "One black hairline, then a lit bevel. The clamp must read against black game footage."),
        ("2", "Planished iron", "Overlapping hammer facets; soot in the low spots, bright steel on the scratches."),
        ("3", "Brass hairline", "The only warm line in the ironwork. It ties the clamp to the plate rack."),
        ("4", "Forged rivets", "Four corner rivets, two side rivets, inset 23 px so a 9-slice cut never divides one."),
        ("5", "Header medallion", "A hammered disc with one brass-etched pictogram: the screen's subject in one mark."),
        ("6", "Wax seal", "One per window, pressed into the header. It carries the step numeral or the skull."),
        ("7", "Torn vellum", "Hand-cut edge, scorched deckle, fibres, freckles, folds. Never a clean rectangle."),
        ("8", "Brass plate", "The primary action: engraved label, bone keycap, rivets at 10 and 90 percent."),
    ]
    ly = y + 42
    for number, name, text in legend:
        _pin(canvas, number, lx, ly + 11)
        draw_text(canvas, (lx + 28, ly), name, font(14, "body"), BONE, 1.6)
        wrapped(canvas, (lx + 28, ly + 22), text, font(12, "italic"), BONE_FAINT, 520)
        ly += 40


def wrapped(canvas: Image.Image, xy, text: str, fnt, color, width: float) -> None:
    y = xy[1]
    for line in kit.wrap(text, fnt, width):
        draw_text(canvas, (xy[0], y), line, fnt, color)
        y += fnt.size + 4


def _pin(canvas: Image.Image, number: str, x: float, y: float) -> None:
    r = 10
    layer = Image.new("RGBA", (int(r * 2) + 4, int(r * 2) + 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((2, 2, 2 + r * 2, 2 + r * 2), fill=(150, 40, 26, 250),
              outline=(238, 218, 188, 200), width=1)
    d.text((2 + r, 2 + r), number, font=font(13, "body"), fill=(250, 238, 216, 255),
           anchor="mm")
    canvas.alpha_composite(layer, (int(x - r - 2), int(y - r - 2)))


def _plates(canvas: Image.Image, y: float) -> None:
    _label(canvas, y, "03", "THE PLATE RACK")
    states = ["idle", "hover", "pressed", "disabled"]
    for index, state in enumerate(states):
        x = MARGIN + 132 + index * 262
        draw_text(canvas, (x + 119, y + 26), state.upper(), font(10, "body"),
                  BONE_FAINT, 2.2, "center")
    rows = [("IRON", "secondary", "iron"), ("BRASS", "primary", "brass"),
            ("LACQUER", "danger", "lacquer")]
    for index, (name, use, variant) in enumerate(rows):
        ry = y + 44 + index * 62
        draw_text(canvas, (MARGIN, ry + 8), name, font(12, "body"), BONE, 2.6)
        draw_text(canvas, (MARGIN, ry + 26), use, font(10, "italic"), BONE_FAINT)
        for s_index, state in enumerate(states):
            x = MARGIN + 132 + s_index * 262
            button(canvas, (x, ry, x + 238, ry + 46), "LABEL", variant, state,
                   seed=500 + index * 10 + s_index, label_size=12, tracking=3.0)
    draw_text(canvas, (MARGIN, y + 246),
              "States change light and depth only: hover warms the plate, pressed sinks it, "
              "disabled drains it. Geometry and label never move.",
              font(12, "italic"), BONE_FAINT)
    draw_text(canvas, (MARGIN, y + 266),
              "MEASUREMENTS  \u00b7  CLAMP 21  \u00b7  HEADER 60  \u00b7  PAGE PADDING 40  "
              "\u00b7  PLATE 54  \u00b7  RADIUS 14", font(11, "body"), BONE_FAINT, 2.2)


def _marks(canvas: Image.Image, y: float) -> None:
    _label(canvas, y, "04", "THE SMALL MARKS")
    items = ["KEYCAP", "STATE CHIP", "THORN BULLET", "DIVIDER", "CHAPTER STAMPS", "WAX SEAL"]
    for index, name in enumerate(items):
        draw_text(canvas, (MARGIN + index * 250, y + 30), name, font(10, "body"),
                  BONE, 2.4)
    keycap(canvas, (MARGIN, y + 54), "G", 36)
    keycap(canvas, (MARGIN + 44, y + 54), "P", 36)
    chip(canvas, MARGIN + 250, y + 58, "ALIVE", (42, 92, 82, 255), 12)
    chip(canvas, MARGIN + 250, y + 88, "DOWNED", (150, 84, 34, 255), 12)
    kit.bullet(canvas, MARGIN + 508, y + 70, BLOOD, 5)
    draw_text(canvas, (MARGIN + 522, y + 62), "a soul is bound", font(14, "body"),
              BONE_DIM)
    divider(canvas, MARGIN + 750, MARGIN + 964, y + 70)
    kit.progress(canvas, MARGIN + 1070, y + 66, 5, 1, 8.0, 30.0)
    kit.seal_rotated(canvas, MARGIN + 1290, y + 78, 26, seed=31, glyph="skull", angle=-8)


def _type_and_icons(canvas: Image.Image, y: float) -> None:
    _label(canvas, y, "05", "TYPE  &  MEDALLIONS")
    draw_text(canvas, (MARGIN, y + 26), "PIRATA ONE  \u00b7  TITLES, NUMERALS",
              font(10, "body"), BONE_FAINT, 2.4)
    draw_text(canvas, (MARGIN, y + 42), "The Cages", font(44, "display"), BONE)
    draw_text(canvas, (MARGIN, y + 104), "IM FELL ENGLISH  \u00b7  BODY 23 / 36",
              font(10, "body"), BONE_FAINT, 2.4)
    draw_text(canvas, (MARGIN, y + 120),
              "Four prisoners hang in this camp, and your soul can",
              font(21, "body"), BONE_DIM)
    draw_text(canvas, (MARGIN, y + 146), "enter any living body.",
              font(21, "body"), BONE_DIM)
    draw_text(canvas, (MARGIN, y + 182), "TRACKED CAPS  \u00b7  LABELS 12 / 3.5",
              font(10, "body"), BONE_FAINT, 2.4)
    draw_text(canvas, (MARGIN, y + 198), "STEP I  \u00b7  THE LESSON  \u00b7  PURSE",
              font(13, "body"), BONE, 3.6)

    icons = ["scroll", "helm", "banner", "gear", "flame", "eye", "coin", "blade",
             "shield", "cage"]
    ix = 800
    for index, key in enumerate(icons):
        col = index % 5
        row = index // 5
        cx = ix + col * 148 + 24
        cy = y + 54 + row * 92
        kit.medallion(canvas, cx, cy, 21, key, seed=700 + index)
        draw_text(canvas, (cx, cy + 30), key.upper(), font(9, "body"), BONE_FAINT,
                  1.8, "center")


def render() -> Image.Image:
    return sheet()
