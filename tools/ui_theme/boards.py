"""The concept boards for the Blood Ledger menu language.

Each function paints one 1440 x 900 board: the same seven components on a real
still of the camp, so contrast and legibility are judged against the game rather
than a neutral grey. Copy is the shipped copy from the matching screen, so the
boards are a skin proposal and not a rewrite.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from . import kit
from . import materials as mat
from .kit import (
    BLOOD, BLOOD_DARK, BONE, EMBER, INK, INK_MUTED, INK_SOFT,
    button, chip, divider, draw_text, font, keycap, text_width,
)

ROOT = Path(__file__).resolve().parent.parent.parent
STILL = ROOT / "media" / "concept" / "backdrop_camp.png"

W, H = 1440, 900
TEAL_INK = (42, 92, 82, 255)
DEAD_INK = (98, 92, 82, 255)


# --- shared plate ----------------------------------------------------------

def backdrop(dim: float = 0.50, blur: float = 1.3, warm: float = 1.0) -> Image.Image:
    bg = Image.open(STILL).convert("RGB").resize((W, H), Image.LANCZOS)
    arr = np.asarray(bg, np.float32) / 255.0
    arr *= dim
    arr[..., 0] *= 0.94 * warm
    arr[..., 2] *= 1.07
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx = xx / (W - 1) * 2 - 1
    ny = yy / (H - 1) * 2 - 1
    vignette = np.clip(1.0 - 0.38 * (nx * nx + ny * ny), 0.30, 1.0)
    arr *= vignette[..., None]
    bg = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")
    return bg.filter(ImageFilter.GaussianBlur(blur)).convert("RGBA")


def finish(canvas: Image.Image) -> Image.Image:
    """The photographic pass: film grain, a vignette, and a touch of halation."""
    arr = np.asarray(canvas.convert("RGB"), np.float32) / 255.0
    bloom = arr.copy()
    for _ in range(3):
        bloom = (bloom + np.roll(bloom, 1, 0) + np.roll(bloom, -1, 0)
                 + np.roll(bloom, 1, 1) + np.roll(bloom, -1, 1)) / 5.0
    arr = np.clip(arr + (bloom - arr) * 0.10, 0.0, 1.0)
    rng = np.random.default_rng(4242)
    arr += rng.normal(0.0, 0.006, arr.shape[:2])[..., None]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    vx = xx / (W - 1) * 2 - 1
    vy = yy / (H - 1) * 2 - 1
    arr *= np.clip(1.0 - 0.16 * (vx * vx + vy * vy), 0.55, 1.0)[..., None]
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")


def caption(canvas: Image.Image, index: str, title: str) -> None:
    """The board's own nameplate, small and out of the way."""
    draw_text(canvas, (30, H - 40), "GHOST OF THE WARBAND", font(12, "body"),
              (150, 132, 106, 200), 3.0)
    draw_text(canvas, (30, H - 24), "THE BLOOD LEDGER  /  MENU LANGUAGE", font(11, "body"),
              (104, 92, 76, 190), 2.4)
    right = f"{index}    {title}"
    draw_text(canvas, (W - 30, H - 30), right, font(12, "body"),
              (150, 132, 106, 200), 2.6, "right")
    draw = ImageDraw.Draw(canvas)
    draw.line((W - 30 - text_width(right, font(12, "body"), 2.6), H - 12,
               W - 30, H - 12), fill=(120, 100, 74, 200), width=1)


def blend(canvas: Image.Image, rect, painter) -> None:
    """Draw translucent furniture on its own layer so the alpha actually blends."""
    x0, y0, x1, y1 = [int(round(v)) for v in rect]
    layer = Image.new("RGBA", (max(1, x1 - x0), max(1, y1 - y0)), (0, 0, 0, 0))
    painter(ImageDraw.Draw(layer), layer.size)
    canvas.alpha_composite(layer, (x0, y0))


def section(canvas: Image.Image, x0: float, x1: float, y: float, label: str) -> None:
    """A rubricated section head: blood ink, small caps, hairline to the margin."""
    f = font(11, "body")
    draw_text(canvas, (x0, y), label, f, BLOOD, 3.0)
    w = text_width(label, f, 3.0)
    draw = ImageDraw.Draw(canvas)
    draw.line((x0 + w + 23, y + 7, x1, y + 7), fill=(120, 96, 64, 150), width=1)
    kit.thorn(canvas, x0 + w + 15, y + 7, 4.2, 0, BLOOD)


def health_bar(canvas: Image.Image, rect, frac: float, tint=(150, 44, 34, 255)) -> None:
    x0, y0, x1, y1 = rect
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), fill=(24, 20, 15, 255))
    draw.rectangle((x0, y0, x1, y1), fill=(58, 46, 33, 255))
    fill_w = max(0.0, (x1 - x0) * np.clip(frac, 0, 1))
    if fill_w > 1:
        draw.rectangle((x0, y0, x0 + fill_w, y1), fill=tint)
        blend(canvas, (x0, y0, x0 + fill_w, y0 + 2),
              lambda d, s: d.rectangle((0, 0, s[0], s[1]), fill=(255, 206, 180, 70)))
        draw.rectangle((x0, y1 - 1, x0 + fill_w, y1), fill=(40, 8, 8, 255))


def toggle(canvas: Image.Image, rect, on: bool, label: str = "DEPLOYED") -> None:
    x0, y0, x1, y1 = [int(v) for v in rect]
    if not on:
        button(canvas, rect, "DEPLOY", "iron", "idle", seed=x0, label_size=11,
               tracking=1.8)
        return
    blend(canvas, rect, lambda d, s: (
        d.rectangle((0, 0, s[0] - 1, s[1] - 1), fill=(42, 92, 82, 30), outline=(42, 92, 82, 190), width=1)))
    draw = ImageDraw.Draw(canvas)
    bx, by = x0 + 8, y0 + (y1 - y0) * 0.5
    draw.rectangle((bx - 5, by - 5, bx + 5, by + 5), outline=(42, 92, 82, 230),
                   fill=(240, 230, 208, 190), width=1)
    draw.line((bx - 2, by, bx + 1, by + 3), fill=TEAL_INK, width=2)
    draw.line((bx + 1, by + 3, bx + 5, by - 3), fill=TEAL_INK, width=2)
    draw_text(canvas, (x0 + 22, y0 + (y1 - y0) * 0.5 - 8), label, font(10, "body"),
              TEAL_INK, 1.2)


# --- 02: tutorial ----------------------------------------------------------

STEPS = {
    "cages": {
        "numeral": "I",
        "kicker": "STEP I  \u00b7  THE LESSON",
        "title": "You are a soul, not a body",
        "body": ("Four prisoners hang in this camp, and your soul can enter any "
                 "living body. Shift between them: that is the whole game."),
        "keys": [("cap", "F1"), ("cap", "F2"), ("cap", "F3"), ("cap", "F4"),
                 ("text", "or", "italic"), ("cap", "["), ("cap", "]"),
                 ("text", "enter another prisoner", "body")],
        "footnote": "Enter or click CONTINUE to play. TAB opens the warband, P your gear.",
        "caption": "02    TUTORIAL CARD  /  STEP I",
    },
    "latches": {
        "numeral": "III",
        "kicker": "STEP III  \u00b7  THE LATCHES",
        "title": "Four cages, four latches, one shiv",
        "body": ("No cage opens by itself: somebody has to stand at each one and cut "
                 "its latch. Only Corvin kept a blade. Take his body, then walk the "
                 "cage line and cut them one at a time."),
        "keys": [("cap", "F5"), ("text", "or", "italic"), ("cap", "["), ("cap", "]"),
                 ("text", "take Corvin", "body"), ("dot", ""), ("cap", "G"),
                 ("text", "at a cage \u2014 cut its latch", "body")],
        "footnote": "One latch per cage, four in all, and bare hands on a padlock cut nothing.",
        "caption": "02b    TUTORIAL CARD  /  STEP III",
    },
}


def key_line(canvas: Image.Image, x: float, y: float, items, cap: int = 35,
             limit: float = 0.0) -> None:
    for item in items:
        kind = item[0]
        if kind == "cap":
            keycap(canvas, (x, y), item[1], cap)
            x += cap + 6
        elif kind == "text":
            fnt = font(22 if item[2] == "italic" else 21,
                       "italic" if item[2] == "italic" else "body")
            draw_text(canvas, (x + 12, y + 7), item[1], fnt,
                      INK_MUTED if item[2] == "italic" else INK_SOFT)
            x += 12 + text_width(item[1], fnt) + 16
        elif kind == "dot":
            kit.thorn(canvas, x + 12, y + cap * 0.5, 6.5, 0, (110, 84, 54, 255))
            x += 30
        if limit and x > limit:
            break


def tutorial(step: str = "cages") -> Image.Image:
    spec = STEPS[step]
    canvas = backdrop()
    rect = (280, 162, 1160, 742)
    content = kit.window(canvas, rect, "The Cages", "scroll", seed=4,
                         header_height=60, stamp=spec["numeral"])
    cx0, cy0, cx1, cy1 = content
    draw_text(canvas, (cx0, cy0), spec["kicker"], font(15, "body"), BLOOD, 3.8)
    draw_text(canvas, (cx0, cy0 + 30), spec["title"], font(45, "display"), INK)
    y = kit.drop_cap_paragraph(canvas, (cx0, cy0 + 104), spec["body"],
                               font(96, "display"), BLOOD_DARK, font(23, "body"), INK,
                               680, line_gap=13, cap_lines=2, cap_margin=2)

    ky = y + 34
    key_line(canvas, cx0, ky, spec["keys"])
    draw_text(canvas, (cx0, ky + 66), spec["footnote"], font(17, "italic"), INK_MUTED)

    footer = cy1 - 58
    divider(canvas, cx0, cx1, footer - 26)
    kit.progress(canvas, cx0 + 76, footer + 22, 5, 0 if step == "cages" else 2,
                 8.0, 30.0)
    button(canvas, (cx1 - 316, footer, cx1, footer + 58), "CONTINUE", "brass",
           "idle", 21, keycap_label="G", label_size=20)
    caption(canvas, "02" if step == "cages" else "02b",
            "TUTORIAL CARD  /  " + ("STEP I" if step == "cages" else "STEP III"))
    return finish(canvas)


def tutorial_latches() -> Image.Image:
    return tutorial("latches")


# --- 03: warband -----------------------------------------------------------

MERC_ROWS = [
    ("Ash", 84, "ALIVE", "LEATHER \u00b7 SHIV", True, True),
    ("Bram", 97, "ALIVE", "MAIL \u00b7 SWORD", True, True),
    ("Het", 41, "ALIVE", "RAGS \u00b7 CLUB", True, True),
    ("Wren", 0, "DEAD", "CLOTH \u00b7 BOW", False, False),
    ("Corvin", 62, "DOWNED", "LEATHER \u00b7 SHIV", True, False),
]

HIRES = [("Sable", 210), ("Grist", 240), ("Ovrik", 265)]


def warband() -> Image.Image:
    canvas = backdrop(dim=0.46)
    rect = (175, 96, 1265, 804)
    content = kit.window(canvas, rect, "Warband", "banner", seed=9,
                         header_height=60)
    cx0, cy0, cx1, cy1 = content

    draw_text(canvas, (cx0, cy0 + 2), "PURSE", font(11, "body"), INK_MUTED, 2.6)
    draw_text(canvas, (cx0 + 58, cy0 - 8), "1,240 G", font(26, "display"), INK_SOFT)
    draw_text(canvas, (cx1, cy0 - 2), "4 FIELDED OF 8", font(14, "body"),
              INK_MUTED, 2.2, "right")
    draw_text(canvas, (cx1, cy0 + 20), "WARBAND WORTH   3,860 G", font(12, "body"),
              INK_MUTED, 1.8, "right")
    divider(canvas, cx0, cx1, cy0 + 40)

    hy = cy0 + 54
    for text, dx in (("MERCENARY", 0), ("HEALTH", 248), ("STATE", 476),
                     ("GEAR", 574), ("FIELD", 764), ("CONTROL", 864)):
        draw_text(canvas, (cx0 + dx, hy), text, font(10, "body"), INK_MUTED, 2.6)

    row_y = hy + 22
    row_h = 52
    for index, (name, hp, state, gear, deployed, controllable) in enumerate(MERC_ROWS):
        y = row_y + index * row_h
        if index:
            draw = ImageDraw.Draw(canvas)
            draw.line((cx0, y - 8, cx1, y - 8), fill=(92, 72, 48, 90), width=1)
        kit.medallion(canvas, cx0 + 16, y + 15, 14, "helm", seed=50 + index,
                      lit_icon=state != "DEAD")
        draw_text(canvas, (cx0 + 38, y + 0), name, font(26, "display"),
                  INK if state != "DEAD" else (126, 114, 98, 255))
        health_bar(canvas, (cx0 + 248, y + 10, cx0 + 396, y + 21), hp / 100.0,
                   tint=(150, 44, 34, 255) if state == "ALIVE"
                   else ((206, 120, 52, 255) if state == "DOWNED" else (92, 84, 72, 255)))
        draw_text(canvas, (cx0 + 404, y + 4), f"{hp} / 100", font(14, "body"), INK_SOFT)
        state_color = TEAL_INK if state == "ALIVE" else ((124, 62, 18, 255) if state == "DOWNED" else DEAD_INK)
        chip(canvas, cx0 + 476, y + 5, state, state_color, 12)
        draw_text(canvas, (cx0 + 574, y + 6), gear, font(13, "body"),
                  INK_SOFT if state != "DEAD" else (134, 122, 104, 255), 0.8)
        toggle(canvas, (cx0 + 764, y + 3, cx0 + 852, y + 31), deployed)
        button(canvas, (cx0 + 864, y + 2, cx0 + 952, y + 32), "CONTROL",
               "brass" if controllable else "iron",
               "idle" if controllable else "disabled", seed=80 + index,
               label_size=11, tracking=2.2)

    ry = row_y + row_h * len(MERC_ROWS) + 18
    divider(canvas, cx0, cx1, ry - 6)
    draw_text(canvas, (cx0, ry + 8), "GOLD RECRUITER", font(19, "body"), INK, 3.2)
    draw_text(canvas, (cx1, ry + 12), "THE PRICE OF A SOUL, PAID IN COIN",
              font(11, "body"), INK_MUTED, 1.8, "right")
    for index, (name, price) in enumerate(HIRES):
        hy2 = ry + 46 + index * 38
        draw_text(canvas, (cx0 + 4, hy2 - 3), name, font(21, "display"), INK_SOFT)
        draw_text(canvas, (cx0 + 128, hy2 + 2), "UNSWORN  \u00b7  ONE BLADE, NO ARMOUR",
                  font(11, "body"), INK_MUTED, 1.4)
        draw_text(canvas, (cx1 - 236, hy2 - 4), f"{price} G", font(20, "display"),
                  INK_SOFT, 0.0, "right")
        button(canvas, (cx1 - 196, hy2 - 8, cx1, hy2 + 22), "SWEAR IN", "iron",
               "idle", seed=90 + index, label_size=11, tracking=2.2)

    draw_text(canvas, (cx0, cy1 - 18), "TAB closes the ledger.  A body with a soul "
              "inside cannot be entered twice.", font(13, "italic"), INK_MUTED)
    caption(canvas, "03", "WARBAND SCREEN  /  TAB")
    return finish(canvas)


# --- 04: gear --------------------------------------------------------------

WORN = [
    ("head", "helm", "Ironwood Helm", ""),
    ("chest", "cuirass", "Leather Jerkin", ""),
    ("hands", "gauntlet", "Lashed Gloves", ""),
    ("legs", "greaves", "Linen Braies", ""),
    ("feet", "boot", "Boiled Boots", ""),
    ("neck", "amulet", "Bone Talisman", ""),
    ("ring1", "ring", "Ring of Small Mercy", "WARD"),
    ("ring2", "ring", "Copper Band", ""),
    ("main", "blade", "Prison Shank", "SHANK"),
    ("off", "shield", "Buckler", ""),
]

STASH_GLYPHS = ["blade", "shield", "cuirass", "helm", "boot", "greaves", "gauntlet",
                "ring", "amulet", "bow", "staff", "spear", "flame", "coin",
                "scroll", "key"]

PREVIEW = ROOT / "media" / "concept" / "preview_ranger.png"


def gear() -> Image.Image:
    canvas = backdrop(dim=0.44)
    rect = (70, 40, 1370, 860)
    content = kit.window(canvas, rect, "Gear", "cuirass", seed=21, header_height=60)
    cx0, cy0, cx1, cy1 = content

    # Tabs: the whole warband across the top, one body being dressed.
    tabs = [("Ash", "ALIVE"), ("Bram", "ALIVE"), ("Het", "ALIVE"),
            ("Wren", "DEAD"), ("Corvin", "DOWNED")]
    x = cx0
    for index, (name, state) in enumerate(tabs):
        tab_plate(canvas, (x, cy0, x + 150, cy0 + 50), name, index == 0, state,
                  seed=30 + index)
        x += 158
    draw_text(canvas, (cx1, cy0 + 6), "ASH  /  ALIVE  /  318 G WORN",
              font(12, "body"), INK_MUTED, 2.0, "right")
    draw_text(canvas, (cx1, cy0 + 26),
              "The collective stash is shared; the body is not.", font(13, "italic"),
              INK_MUTED, 0.0, "right")

    main_y = cy0 + 70
    # Left: the ten worn slots.
    draw_text(canvas, (cx0, main_y), "WORN GEAR", font(10, "body"), INK_MUTED, 2.8)
    for index, (slot, glyph, name, brand) in enumerate(WORN):
        y = main_y + 24 + index * 34
        selected = index == 8
        if selected:
            blend(canvas, (cx0 - 8, y - 3, cx0 + 286, y + 31), lambda d, s: (
                d.rectangle((0, 0, s[0] - 1, s[1] - 1), fill=(146, 44, 26, 30)),
                d.rectangle((0, 0, 4, s[1] - 1), fill=(146, 44, 26, 235)),
                d.rectangle((0, 0, s[0] - 1, s[1] - 1), outline=(146, 44, 26, 110), width=1)))
        kit.medallion(canvas, cx0 + 14, y + 15, 12, glyph, seed=100 + index,
                      lit_icon=selected)
        draw_text(canvas, (cx0 + 34, y + 1), slot.upper(), font(9, "body"),
                  INK_MUTED, 2.0)
        draw_text(canvas, (cx0 + 34, y + 12), name, font(18, "body"),
                  BLOOD if selected else INK_SOFT)
        if brand:
            draw_text(canvas, (cx0 + 214, y + 14), brand, font(9, "body"), BLOOD, 1.8)

    # Centre: the live ranger in an iron alcove.
    stage = (cx0 + 320, main_y - 8, cx0 + 320 + 372, main_y + 352)
    _alcove(canvas, stage, seed=77)
    _ranger(canvas, stage)
    draw_text(canvas, ((stage[0] + stage[2]) * 0.5, stage[3] + 14),
              "TAB  SWAP SET   \u00b7   MAIN: PRISON SHANK   \u00b7   OFF: BUCKLER",
              font(11, "body"), INK_MUTED, 1.8, "center")

    # Right: trinkets, derived kit, the set line.
    rx = stage[2] + 34
    draw_text(canvas, (rx, main_y), "TRINKETS", font(10, "body"), INK_MUTED, 2.8)
    trinkets = [("NECK", "amulet", "Bone"), ("RING", "ring", "Mercy"),
                ("RING", "ring", "Copper"), ("OFF", "flame", "Ward")]
    tx = rx
    for index, (slot, glyph, name) in enumerate(trinkets):
        kit.medallion(canvas, tx + 18, main_y + 46, 17, glyph, seed=200 + index)
        draw_text(canvas, (tx + 18, main_y + 68), slot, font(8, "body"), INK_MUTED,
                  1.6, "center")
        draw_text(canvas, (tx + 18, main_y + 80), name, font(11, "italic"), INK_SOFT,
                  0.0, "center")
        tx += 66

    draw_text(canvas, (rx, main_y + 116), "KIT", font(10, "body"), INK_MUTED, 2.8)
    draw = ImageDraw.Draw(canvas)
    draw.line((rx, main_y + 138, cx1, main_y + 138), fill=(96, 74, 50, 140), width=1)
    rows = [("HEALTH", "100"), ("STAMINA", "1,000"), ("MELEE", "+18%"),
            ("RANGED", "+9%"), ("GUARD", "22%"), ("MOVE", "+4%")]
    for index, (label, value) in enumerate(rows):
        y = main_y + 150 + index * 26
        draw_text(canvas, (rx, y), label, font(10, "body"), INK_MUTED, 2.4)
        draw_text(canvas, (cx1, y - 3), value, font(17, "display"), INK_SOFT, 0.0, "right")

    button(canvas, (rx, main_y + 318, cx1, main_y + 366), "SWAP SET", "iron",
           "idle", seed=260, keycap_label="TAB", label_size=13, tracking=2.6)

    # Bottom: the collective stash as the old menu's grid.
    gy = main_y + 396
    divider(canvas, cx0, cx1, gy - 12)
    draw_text(canvas, (cx0, gy), "COLLECTIVE STASH", font(10, "body"), INK_MUTED, 2.8)
    draw_text(canvas, (cx0 + 640, gy), "VALUE ORDER", font(10, "body"), INK_MUTED,
              2.2, "right")
    draw_text(canvas, (cx0 + 646, gy), "\u00b7  74 PIECES", font(10, "body"), INK_MUTED,
              2.2)

    cols, rows_n, tile, gap = 16, 2, 46, 6
    for i in range(cols * rows_n):
        col = i % cols
        row = i // cols
        tx2 = cx0 + col * (tile + gap)
        ty2 = gy + 24 + row * (tile + gap)
        _stash_tile(canvas, (tx2, ty2, tx2 + tile, ty2 + tile),
                    STASH_GLYPHS[i % len(STASH_GLYPHS)], seed=300 + i,
                    worn=(i in (0, 4, 9)))

    # Marginal note beside the grid.
    nx = cx0 + cols * (tile + gap) + 22
    blend(canvas, (nx, gy + 24, cx1, gy + 122), lambda d, s: (
        d.rectangle((0, 0, s[0] - 1, s[1] - 1), fill=(24, 20, 15, 18),
                    outline=(96, 74, 50, 130), width=1)))
    draw_text(canvas, (nx + 14, gy + 36), "A WORN PIECE", font(9, "body"), BLOOD, 2.4)
    draw_text(canvas, (nx + 14, gy + 52), "is part of the body.", font(13, "italic"),
              INK_SOFT)
    draw_text(canvas, (nx + 14, gy + 72), "The rest is the warband's.", font(13, "italic"),
              INK_SOFT)
    draw_text(canvas, (nx + 14, gy + 94), "74 pieces, sorted by worth.", font(11, "body"),
              INK_MUTED)

    draw_text(canvas, (cx0, cy1 - 16),
              "A press on a worn slot strips it; a press on the stash dresses the body.",
              font(13, "italic"), INK_MUTED)
    caption(canvas, "04", "GEAR  /  P")
    return finish(canvas)


def _alcove(canvas: Image.Image, rect, seed: int) -> None:
    """The stage the ranger stands in: a dark iron niche in the page."""
    x0, y0, x1, y1 = [int(v) for v in rect]
    w, h = x1 - x0, y1 - y0
    mask = mat.rounded_mask(w, h, 8)
    field = mat.leather(w, h, seed) * 0.42
    field = field * (0.85 + 0.3 * mat.fbm(w, h, seed + 1, 4, 60))[..., None]
    shade = mat.bevel(mask, 3.0, 1.0)
    field = field * (1.0 + 0.45 * mat.lit(shade, 1.0)) * (1.0 - 0.55 * mat.shade_dark(shade, 1.0))
    canvas.alpha_composite(mat.rgba(field, mask), (x0, y0))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=8, outline=(0, 0, 0, 210),
                           width=1)
    draw.rounded_rectangle((x0 + 3, y0 + 3, x1 - 4, y1 - 4), radius=6,
                           outline=(150, 118, 66, 90), width=1)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((w * 0.22, h * 0.62, w * 0.78, h * 0.98), fill=(127, 215, 196, 26))
    glow = glow.filter(kit._blur(18))
    canvas.alpha_composite(glow, (x0, y0))
    kit.nail(canvas, x0 + 14, y0 + 14, 3.4)
    kit.nail(canvas, x1 - 14, y0 + 14, 3.4)
    draw.line((x0 + 10, y1 - 10, x1 - 10, y1 - 10), fill=(0, 0, 0, 150), width=1)


def _ranger(canvas: Image.Image, rect) -> None:
    if not PREVIEW.exists():
        return
    x0, y0, x1, y1 = rect
    figure = Image.open(PREVIEW).convert("RGBA").crop((214, 6, 514, 426))
    target_h = int((y1 - y0) * 0.94)
    scale = target_h / figure.height
    figure = figure.resize((int(figure.width * scale), target_h), Image.LANCZOS)
    arr = np.asarray(figure, np.float32) / 255.0
    arr[..., :3] *= 0.92
    arr[..., 2] *= 1.04
    figure = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    cx = (x0 + x1) // 2 - figure.width // 2
    cy = y1 - 8 - figure.height
    canvas.alpha_composite(figure, (cx, cy))
    # The feet dissolve into the niche's shadow instead of ending on the page.
    w, h = x1 - x0, y1 - y0
    ramp = np.zeros((h, w, 4), np.float32)
    band = np.clip((np.arange(h, dtype=np.float32) - (h - 74.0)) / 74.0, 0.0, 1.0)
    ramp[..., 3] = (band[:, None] ** 1.5) * 176.0
    ramp[..., :3] = 0.03
    canvas.alpha_composite(Image.fromarray(ramp.astype(np.uint8), "RGBA"), (x0, y0))


def _stash_tile(canvas: Image.Image, rect, glyph: str, seed: int, worn: bool = False) -> None:
    """One piece in the grid: an iron tile with a brass-etched silhouette."""
    x0, y0, x1, y1 = [int(v) for v in rect]
    w, h = x1 - x0, y1 - y0
    fill, mask = kit._plate(lambda W_, H_, s: mat.iron(W_, H_, s, rough=0.45),
                            w, h, seed, 4.0, 0.9)
    if worn:
        fill = fill * 1.15 + np.array([0.06, 0.02, 0.01], np.float32)[None, None, :]
    canvas.alpha_composite(mat.rgba(fill, mask), (x0, y0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((x0, y0, x1 - 1, y1 - 1),
                   outline=(150, 44, 26, 170) if worn else (0, 0, 0, 210), width=1)
    draw.rectangle((x0 + 2, y0 + 2, x1 - 3, y1 - 3),
                   outline=(150, 118, 66, 90) if worn else (86, 72, 50, 70), width=1)
    icon = kit.icon_mask(glyph, int(h * 0.60))
    arr = np.asarray(icon, np.float32) / 255.0
    shade = mat.bevel(arr, 1.1)
    brass = mat.brass(arr.shape[1], arr.shape[0], seed + 3)
    tint = brass * (0.85 + 0.55 * np.clip(shade, 0, 1))[..., None]
    bed = mat.rgba(np.zeros((arr.shape[0], arr.shape[1], 3), np.float32), arr * 0.5)
    cx, cy = int((x0 + x1) / 2 - icon.width / 2), int((y0 + y1) / 2 - icon.height / 2)
    canvas.alpha_composite(bed, (cx + 1, cy + 1))
    canvas.alpha_composite(mat.rgba(tint, arr), (cx, cy))


def tab_plate(canvas: Image.Image, rect, label: str, active: bool, sub: str,
              seed: int = 1) -> None:
    x0, y0, x1, y1 = [int(v) for v in rect]
    w, h = x1 - x0, y1 - y0
    fill, mask = kit._plate(
        (lambda W_, H_, s: mat.iron(W_, H_, s, rough=0.6)) if not active
        else (lambda W_, H_, s: mat.brass(W_, H_, s) * 0.78),
        w, h, seed, 4.0, 0.9)
    canvas.alpha_composite(mat.rgba(fill, mask), (x0, y0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((x0 + 1, y0 + 1, x1 - 2, y1 - 2), outline=(0, 0, 0, 200), width=1)
    if active:
        draw.line((x0 + 6, y1 - 3, x1 - 6, y1 - 3), fill=(176, 44, 28, 255), width=2)
    draw_text(canvas, ((x0 + x1) * 0.5, y0 + 8), label, font(16, "body"),
              (24, 16, 8, 255) if active else BONE, 2.2, "center")
    draw_text(canvas, ((x0 + x1) * 0.5, y0 + 27), sub, font(10, "body"),
              (72, 40, 26, 245) if active else (186, 174, 152, 240), 1.8, "center")


# --- 05: quick menu --------------------------------------------------------

def settings() -> Image.Image:
    canvas = backdrop(dim=0.42)
    rect = (500, 130, 940, 770)
    content = kit.window(canvas, rect, "Menu", "gear", seed=31, header_height=60)
    cx0, cy0, cx1, cy1 = content

    draw_text(canvas, (cx0, cy0), "IRONWOOD", font(12, "body"), INK_MUTED, 3.2)
    draw_text(canvas, (cx0, cy0 + 18), "QUICK MENU", font(36, "display"), INK)

    button(canvas, (cx0, cy0 + 68, cx1, cy0 + 118), "RESUME", "brass", "idle",
           seed=151, keycap_label="ESC", label_size=16, tracking=3.6)

    section(canvas, cx0, cx1, cy0 + 136, "JOURNEY")
    button(canvas, (cx0, cy0 + 156, cx1, cy0 + 206), "SAVE JOURNEY", "iron", "idle",
           seed=152, label_size=15, tracking=3.0)
    button(canvas, (cx0, cy0 + 212, cx1, cy0 + 262), "DISPLAY:  WINDOWED", "iron",
           "idle", seed=153, label_size=15, tracking=2.4)

    section(canvas, cx0, cx1, cy0 + 280, "LEAVE")
    button(canvas, (cx0, cy0 + 300, cx1, cy0 + 350), "EXIT TO TOWN", "lacquer",
           "idle", seed=154, label_size=15, tracking=3.0)
    button(canvas, (cx0, cy0 + 356, cx1, cy0 + 406), "EXIT GAME", "lacquer", "idle",
           seed=155, label_size=15, tracking=3.4)

    divider(canvas, cx0, cx1, cy0 + 428)
    draw_text(canvas, (cx0, cy0 + 440), "LAST WRITING", font(10, "body"), INK_MUTED, 2.6)
    draw_text(canvas, (cx0, cy0 + 456), "THE CAGES  \u00b7  12 MINUTES AGO",
              font(13, "italic"), INK_SOFT)
    draw_text(canvas, (cx0, cy0 + 478), "JOURNEY SAVED  \u00b7  1,240 G  \u00b7  44 ITEMS",
              font(11, "body"), TEAL_INK, 1.6)
    caption(canvas, "05", "QUICK MENU  /  ESC")
    return finish(canvas)


# --- 06: title -------------------------------------------------------------

def title() -> Image.Image:
    canvas = backdrop(dim=0.55, blur=2.6)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((W * 0.18, -140, W * 0.82, 520), fill=(255, 170, 90, 16))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    canvas.alpha_composite(glow)

    kit.seal_rotated(canvas, W * 0.5, 140, 44, seed=77, glyph="skull", angle=-6)
    draw_text(canvas, (W * 0.5, 208), "GHOST OF", font(28, "body"),
              (208, 190, 160, 235), 10.0, "center")
    draw_text(canvas, (W * 0.5, 234), "THE WARBAND", font(94, "display"),
              (238, 226, 202, 255), 4.0, "center")
    draw_text(canvas, (W * 0.5, 336), "a soul may wear any living body",
              font(24, "italic"), (200, 178, 146, 235), 0.0, "center")

    draw = ImageDraw.Draw(canvas)
    draw.line((W * 0.5 - 300, 380, W * 0.5 - 40, 380), fill=(150, 118, 66, 150), width=1)
    draw.line((W * 0.5 + 40, 380, W * 0.5 + 300, 380), fill=(150, 118, 66, 150), width=1)
    kit.thorn(canvas, W * 0.5, 380, 10, 0, (170, 48, 32, 230))

    labels = [("NEW CAMPAIGN", "brass", "N"), ("CONTINUE", "iron", ""),
              ("HOST OPEN WORLD", "iron", ""), ("JOIN GAME", "iron", ""),
              ("WARBAND LOBBY", "iron", ""), ("QUIT", "lacquer", "")]
    y = 442
    for label, variant, cap in labels:
        button(canvas, (W * 0.5 - 250, y, W * 0.5 + 250, y + 54), label, variant,
               "idle", seed=200 + y, keycap_label=cap, label_size=16, tracking=3.4)
        y += 63
    draw_text(canvas, (W * 0.5, y + 16), "ENTER  TO  CONFIRM   \u00b7   ESC  TO  RETURN",
              font(12, "body"), (176, 156, 128, 225), 3.0, "center")
    caption(canvas, "06", "TITLE")
    return finish(canvas)


# --- 07: quartermaster -----------------------------------------------------

STOCK = [
    ("Arming Sword", "SWORD \u00b7 ONE-HANDED", "blade", 240),
    ("Kite Shield", "SHIELD \u00b7 HEAVY", "shield", 185),
    ("Mail Hauberk", "MAIL \u00b7 CHEST", "cuirass", 320),
    ("Shortbow", "BOW \u00b7 MEDIUM", "bow", 140),
    ("Cinder Staff", "STAFF \u00b7 TWO-HANDED", "staff", 410),
    ("Bone Spear", "SPEAR \u00b7 TWO-HANDED", "spear", 260),
]


def quartermaster() -> Image.Image:
    canvas = backdrop(dim=0.44)
    rect = (400, 120, 1040, 780)
    content = kit.window(canvas, rect, "Quartermaster", "coin", seed=57,
                         header_height=60)
    cx0, cy0, cx1, cy1 = content

    draw_text(canvas, (cx0, cy0), "THE TOWN  \u00b7  SHARED STASH", font(11, "body"),
              INK_MUTED, 2.6)
    draw_text(canvas, (cx0, cy0 + 18), "THE QUARTERMASTER", font(33, "display"), INK)
    draw_text(canvas, (cx1, cy0 + 2), "PURSE  1,240 G", font(15, "body"), INK_SOFT, 1.6,
              "right")
    draw_text(canvas, (cx1, cy0 + 24), "74 PIECES HELD", font(11, "body"), INK_MUTED,
              1.8, "right")
    divider(canvas, cx0, cx1, cy0 + 62)

    hy = cy0 + 76
    draw_text(canvas, (cx0, hy), "STEEL", font(10, "body"), INK_MUTED, 2.6)
    draw_text(canvas, (cx1 - 164, hy), "PRICE", font(10, "body"), INK_MUTED, 2.6, "right")

    for index, (name, kind, glyph, price) in enumerate(STOCK):
        y = hy + 22 + index * 58
        if index:
            ImageDraw.Draw(canvas).line((cx0, y - 8, cx1, y - 8),
                                        fill=(92, 72, 48, 70), width=1)
        kit.medallion(canvas, cx0 + 16, y + 16, 13, glyph, seed=880 + index,
                      lit_icon=True)
        draw_text(canvas, (cx0 + 40, y + 1), name, font(21, "body"), INK)
        draw_text(canvas, (cx0 + 40, y + 24), kind, font(9, "body"), INK_MUTED, 2.0)
        draw_text(canvas, (cx1 - 186, y + 4), f"{price} G", font(20, "display"),
                  INK_SOFT, 0.0, "right")
        button(canvas, (cx1 - 150, y - 2, cx1, y + 30), "BUY", "iron", "idle",
               seed=900 + index, label_size=12, tracking=3.0)

    draw_text(canvas, (cx0, cy1 - 18),
              "Plain steel, bought into the shared stash.  Every keeper keeps three counters.",
              font(13, "italic"), INK_MUTED)
    caption(canvas, "07", "QUARTERMASTER")
    return finish(canvas)


# --- 08: altar -------------------------------------------------------------

TIERS = [("HIDE", "12", "2", (150, 128, 92, 255)),
         ("SHADE", "8", "1", (150, 96, 60, 255)),
         ("MALICE", "4", "0", (128, 40, 30, 255))]


def altar() -> Image.Image:
    canvas = backdrop(dim=0.38)
    rect = (90, 100, 1350, 800)
    content = kit.window(canvas, rect, "The Altar", "flame", seed=63,
                         header_height=60)
    cx0, cy0, cx1, cy1 = content

    draw_text(canvas, (cx0, cy0), "THE SACRIFICE  \u00b7  THE SOUL IS THE COLLATERAL",
              font(11, "body"), BLOOD, 2.8)
    draw_text(canvas, (cx0, cy0 + 18), "THE ALTAR", font(44, "display"), INK)
    draw_text(canvas, (cx1, cy0 + 8), "CRUOR  260", font(26, "display"), INK_SOFT,
              0.0, "right")
    draw_text(canvas, (cx1, cy0 + 40), "THE LEDGER OF BOUND SOULS", font(10, "body"),
              INK_MUTED, 2.2, "right")

    top = cy0 + 84
    col1, col2, col3 = cx0, cx0 + 400, cx0 + 720
    col_w1, col_w2, col_w3 = 370, 280, cx1 - col3

    # Column heads.
    for x, w, label in ((col1, col_w1, "UNBIND SPARE STEEL"),
                        (col2, col_w2, "DISTIL  5 : 1"),
                        (col3, col_w3, "BRAND A VESSEL")):
        draw_text(canvas, (x, top), label, font(11, "body"), BLOOD, 3.0)
        draw = ImageDraw.Draw(canvas)
        draw.line((x, top + 22, x + w - 20, top + 22), fill=(96, 74, 50, 150), width=1)

    draw_text(canvas, (col1, top + 30), "Spare pieces only; worn gear stays on the body.",
              font(12, "italic"), INK_MUTED)
    for index, (name, glyph, yield_) in enumerate(
            [("Ring of Small Mercy", "ring", "+80"), ("Cinder Staff", "staff", "+120"),
             ("Bone Spear", "spear", "+70")]):
        y = top + 60 + index * 50
        kit.medallion(canvas, col1 + 14, y + 14, 12, glyph, seed=950 + index,
                      lit_icon=True)
        draw_text(canvas, (col1 + 34, y), name, font(19, "body"), INK)
        draw_text(canvas, (col1 + 34, y + 22), "UNBINDS FOR " + yield_ + " CRUOR",
                  font(10, "body"), INK_MUTED, 1.8)
        button(canvas, (col1 + 250, y - 4, col1 + 350, y + 26), "UNBIND", "iron",
               "idle", seed=960 + index, label_size=10, tracking=2.0)

    for index, (tier, held, out, color) in enumerate(TIERS):
        y = top + 40 + index * 46
        draw_text(canvas, (col2, y), tier, font(11, "body"), color, 2.6)
        draw_text(canvas, (col2, y + 18), f"{held} HELD   \u00b7   {out} ESSENCE",
                  font(12, "body"), INK_SOFT)
        button(canvas, (col2 + 190, y - 2, col2 + 280, y + 30), "DISTIL", "iron",
               "idle" if out != "0" else "disabled", seed=970 + index,
               label_size=10, tracking=2.0)
    button(canvas, (col2, top + 190, col2 + 280, top + 240), "DISTIL ALL", "lacquer",
           "idle", seed=980, label_size=13, tracking=3.0)

    # Brand column: two iron fields and the one brass action of the screen.
    field_h = 40
    draw_text(canvas, (col3, top + 30), "VESSEL", font(9, "body"), INK_MUTED, 2.4)
    blend(canvas, (col3, top + 44, col3 + col_w3 - 20, top + 44 + field_h),
          lambda d, s: (d.rectangle((0, 0, s[0] - 1, s[1] - 1), fill=(24, 20, 15, 40),
                                    outline=(96, 74, 50, 170), width=1)))
    draw_text(canvas, (col3 + 10, top + 54), "Corvin's Prison Shank", font(17, "body"),
              INK_SOFT)

    draw_text(canvas, (col3, top + 98), "ESSENCE", font(9, "body"), INK_MUTED, 2.4)
    blend(canvas, (col3, top + 112, col3 + col_w3 - 20, top + 112 + field_h),
          lambda d, s: (d.rectangle((0, 0, s[0] - 1, s[1] - 1), fill=(24, 20, 15, 40),
                                    outline=(96, 74, 50, 170), width=1)))
    draw_text(canvas, (col3 + 10, top + 122), "MALICE  \u00b7  6 STAMINA", font(17, "body"),
              INK_SOFT)

    draw_text(canvas, (col3, top + 172), "THE BRAND IT BUYS", font(9, "body"),
              INK_MUTED, 2.4)
    draw_text(canvas, (col3, top + 188), "BONECALL", font(28, "display"), BLOOD)
    draw_text(canvas, (col3, top + 222), "Raises three spears of bone from the ground.",
              font(12, "italic"), INK_SOFT)
    button(canvas, (col3, top + 250, col3 + col_w3 - 20, top + 306), "BRAND", "brass",
           "idle", seed=990, label_size=15, tracking=4.0)

    # Column spines.
    for x in (col1 + 382, col2 + 300):
        draw = ImageDraw.Draw(canvas)
        draw.line((x, top, x, cy1 - 54), fill=(96, 74, 50, 120), width=1)
        kit.thorn(canvas, x, cy1 - 64, 7, 0, (120, 30, 22, 210))

    draw_text(canvas, (cx0, cy1 - 18),
              "Only spare steel is offered.  A worn piece is part of the body, not the stock.",
              font(13, "italic"), INK_MUTED)
    caption(canvas, "08", "SACRIFICIAL ALTAR")
    return finish(canvas)


BOARDS = {
    "02_tutorial": tutorial,
    "02b_tutorial_latches": tutorial_latches,
    "03_warband": warband,
    "04_gear": gear,
    "05_menu": settings,
    "06_title": title,
    "07_quartermaster": quartermaster,
    "08_altar": altar,
}
