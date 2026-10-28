"""Render the Blood Ledger concept boards.

    python tools/render_ui_concept.py            # every board
    python tools/render_ui_concept.py 02 05      # only those whose name starts so

Boards land in media/concept/. They are art-direction boards, not assets: the
production atlas is generated from the same material fields by
tools/render_ui_theme.py once the direction is signed off.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from PIL import Image, ImageDraw, ImageFont  # noqa: E402

from ui_theme import boards, sheet  # noqa: E402

OUT = ROOT / "media" / "concept"


def main(argv: list[str]) -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = argv[1:]
    made = 0
    if not wanted or any(w.startswith("01") or "01".startswith(w) for w in wanted):
        image = sheet.sheet()
        path = OUT / "01_theme_sheet.png"
        image.save(path)
        print(f"{path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}")
        made += 1
    for name, maker in boards.BOARDS.items():
        if wanted and not any(name.startswith(w) for w in wanted):
            continue
        image = maker()
        path = OUT / f"{name}.png"
        _save(image, path)
        print(f"{path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}")
        made += 1
    if not wanted:
        _contact_sheet()
    if not made:
        print("no board matched", wanted)
        return 1
    return 0


def _save(image: Image.Image, path) -> None:
    """Write through a temp file: a viewer holding the PNG open must not kill the run."""
    temp = path.with_suffix(".tmp.png")
    image.save(temp)
    for attempt in range(6):
        try:
            temp.replace(path)
            return
        except OSError:
            if attempt == 5:
                raise
            time.sleep(0.4)


def _contact_sheet() -> None:
    """One page with every board, for review without opening eight files."""
    boards_list = [
        ("01_theme_sheet.png", "01  THEME SHEET"),
        ("02_tutorial.png", "02  TUTORIAL  /  STEP I"),
        ("02b_tutorial_latches.png", "02b  TUTORIAL  /  STEP III"),
        ("03_warband.png", "03  WARBAND  /  TAB"),
        ("04_gear.png", "04  GEAR  /  P"),
        ("05_menu.png", "05  QUICK MENU  /  ESC"),
        ("06_title.png", "06  TITLE"),
        ("07_quartermaster.png", "07  QUARTERMASTER"),
        ("08_altar.png", "08  SACRIFICIAL ALTAR"),
    ]
    col_w, gap, pad = 660, 24, 40
    display = ImageFont.truetype(str(ROOT / "assets/ui/fonts/PirataOne-Regular.ttf"), 40)
    body = ImageFont.truetype(str(ROOT / "assets/ui/fonts/IMFellEnglish-Regular.ttf"), 20)
    small = ImageFont.truetype(str(ROOT / "assets/ui/fonts/IMFellEnglish-Italic.ttf"), 18)
    col_heights = [0, 0]
    placed = []
    for name, label in boards_list:
        path = OUT / name
        if not path.exists():
            continue
        im = Image.open(path).convert("RGB")
        h = round(im.height * col_w / im.width)
        col = 0 if col_heights[0] <= col_heights[1] else 1
        x = pad + col * (col_w + gap)
        y = 150 + col_heights[col]
        placed.append((im.resize((col_w, h), Image.LANCZOS), label, x, y, h))
        col_heights[col] += h + 50
    if not placed:
        return
    width = pad * 2 + col_w * 2 + gap
    height = 150 + max(col_heights) + 60
    page = Image.new("RGB", (width, height), (12, 11, 10))
    draw = ImageDraw.Draw(page)
    draw.text((pad, 40), "THE BLOOD LEDGER", font=display, fill=(238, 226, 204))
    draw.text((pad, 96), "GHOST OF THE WARBAND  \u00b7  MENU LANGUAGE  \u00b7  CONCEPT BOARD v1",
              font=small, fill=(186, 148, 88))
    for im, label, x, y, h in placed:
        page.paste(im, (x, y))
        draw.rectangle((x, y, x + col_w - 1, y + h - 1), outline=(70, 60, 44))
        draw.text((x, y + h + 10), label, font=body, fill=(200, 190, 170))
    _save(page, OUT / "00_contact_sheet.png")
    print(f"media/concept/00_contact_sheet.png  {page.size[0]}x{page.size[1]}")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
