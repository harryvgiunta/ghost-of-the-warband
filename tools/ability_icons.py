"""Generate the deterministic ability icon set.

Icons are high-contrast glyphs in the HUD palette: gold blades and shields,
teal motion and arcane accents, hot ember orange for fire. Everything is drawn
at 4x and reduced with Lanczos so small HUD sizes stay clean.

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
GOLD_DIM = (184, 146, 84, 255)
TEAL = (114, 203, 182, 255)
TEAL_DIM = (66, 134, 126, 255)
CREAM = (246, 240, 225, 255)
EMBER = (255, 144, 70, 255)
EMBER_HOT = (255, 216, 156, 255)
BONE = (198, 224, 200, 255)
INK = (14, 26, 30, 255)


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def u(value: float) -> int:
    return int(round(value * SCALE))


def chevron(draw: ImageDraw.ImageDraw, x: int, y: int, height: int, depth: int,
            width: int, color=GOLD) -> None:
    """A filled forward chevron with a flat back edge."""
    top = y - height // 2
    bottom = y + height // 2
    inner = top + width
    points = [
        (x, top),
        (x + depth, y),
        (x, bottom),
        (x + width, bottom),
        (x + depth + width, y),
        (x + width, top),
    ]
    draw.polygon(points, fill=color)


def arrow(draw: ImageDraw.ImageDraw, x: float, y: float, angle: float,
          length: float, color, width: float = 1.0) -> None:
    """A shaft with a solid head, drawn in the supersampled space."""
    import math
    dx, dy = math.cos(angle), math.sin(angle)
    x0, y0 = x - dx * length, y - dy * length
    x1, y1 = x, y
    draw.line([(u(x0), u(y0)), (u(x1), u(y1))], fill=color, width=u(width))
    head = u(7.0)
    left = angle + math.radians(150)
    right = angle - math.radians(150)
    draw.polygon([
        (u(x1), u(y1)),
        (u(x1 + math.cos(left) * head), u(y1 + math.sin(left) * head)),
        (u(x1 + math.cos(right) * head), u(y1 + math.sin(right) * head)),
    ], fill=color)


def blade(draw: ImageDraw.ImageDraw, x: float, y: float, angle: float,
          length: float, width: float, color=GOLD) -> None:
    import math
    dx, dy = math.cos(angle), math.sin(angle)
    px, py = -dy, dx
    tipx, tipy = x + dx * length, y + dy * length
    draw.polygon([
        (u(x + px * width), u(y + py * width)),
        (u(tipx), u(tipy)),
        (u(x - px * width), u(y - py * width)),
    ], fill=color)
    # crossguard
    draw.line([(u(x + px * width * 2.4), u(y + py * width * 2.4)),
               (u(x - px * width * 2.4), u(y - py * width * 2.4))],
              fill=GOLD_DIM, width=u(2.0))


def bow_body(draw: ImageDraw.ImageDraw) -> None:
    draw.arc([u(16), u(14), u(96), u(114)], start=-78, end=78, fill=GOLD, width=u(5))
    draw.line([(u(33), u(20)), (u(33), u(108))], fill=TEAL_DIM, width=u(2))


def glow_orb(draw: ImageDraw.ImageDraw, x: float, y: float, radius: float) -> None:
    draw.ellipse([u(x - radius * 1.9), u(y - radius * 1.9),
                  u(x + radius * 1.9), u(y + radius * 1.9)], fill=(255, 120, 44, 70))
    draw.ellipse([u(x - radius * 1.35), u(y - radius * 1.35),
                  u(x + radius * 1.35), u(y + radius * 1.35)], fill=(255, 144, 70, 150))
    draw.ellipse([u(x - radius), u(y - radius), u(x + radius), u(y + radius)], fill=EMBER)
    draw.ellipse([u(x - radius * 0.58), u(y - radius * 0.58),
                  u(x + radius * 0.58), u(y + radius * 0.58)], fill=EMBER_HOT)


def shield_shape(draw: ImageDraw.ImageDraw, x: float, y: float, radius: float,
                 color=GOLD) -> None:
    draw.polygon([
        (u(x), u(y - radius)),
        (u(x + radius * 0.86), u(y - radius * 0.52)),
        (u(x + radius * 0.78), u(y + radius * 0.25)),
        (u(x), u(y + radius)),
        (u(x - radius * 0.78), u(y + radius * 0.25)),
        (u(x - radius * 0.86), u(y - radius * 0.52)),
    ], fill=color)
    draw.ellipse([u(x - radius * 0.30), u(y - radius * 0.30),
                  u(x + radius * 0.30), u(y + radius * 0.30)], fill=INK)


def speed_lines(draw: ImageDraw.ImageDraw, x0: float, y0: float, x1: float,
                y1: float, count: int = 3, color=TEAL) -> None:
    for index in range(count):
        offset = (index - (count - 1) / 2.0) * 9.0
        draw.line([(u(x0), u(y0 + offset)), (u(x1 - index * 5), u(y1 + offset))],
                  fill=color, width=u(2.2))


def build_charge() -> Image.Image:
    image, draw = canvas()
    for offset, length, width in ((26, 24, 5), (48, 20, 4), (70, 15, 3)):
        y = (40 + offset) * SCALE
        draw.rounded_rectangle(
            (14 * SCALE, y - width * SCALE, (14 + length) * SCALE, y + width * SCALE),
            radius=width * SCALE,
            fill=TEAL,
        )
    chevron(draw, 38 * SCALE, 64 * SCALE, 62 * SCALE, 22 * SCALE, 15 * SCALE)
    chevron(draw, 76 * SCALE, 64 * SCALE, 62 * SCALE, 22 * SCALE, 15 * SCALE)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_barrage() -> Image.Image:
    image, draw = canvas()
    bow_body(draw)
    speed_lines(draw, 20, 44, 48, 44, 3)
    arrow(draw, 112, 34, -0.16, 52, CREAM, 2.4)
    arrow(draw, 112, 64, 0.0, 58, CREAM, 2.6)
    arrow(draw, 112, 94, 0.16, 52, CREAM, 2.4)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_triple_volley() -> Image.Image:
    image, draw = canvas()
    draw.arc([u(8), u(18), u(84), u(110)], start=-70, end=70, fill=GOLD_DIM, width=u(4))
    arrow(draw, 106, 30, -0.34, 66, GOLD, 2.2)
    arrow(draw, 114, 64, 0.0, 76, CREAM, 2.8)
    arrow(draw, 106, 98, 0.34, 66, GOLD, 2.2)
    draw.line([(u(30), u(18)), (u(30), u(110))], fill=TEAL_DIM, width=u(2))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_piercing_shot() -> Image.Image:
    image, draw = canvas()
    speed_lines(draw, 8, 38, 40, 38, 2, TEAL_DIM)
    speed_lines(draw, 8, 90, 40, 90, 2, TEAL_DIM)
    draw.line([(u(18), u(64)), (u(112), u(64))], fill=GOLD_DIM, width=u(3))
    arrow(draw, 120, 64, 0.0, 96, CREAM, 3.0)
    draw.polygon([(u(20), u(44)), (u(50), u(64)), (u(20), u(84))], fill=TEAL)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_double_slash() -> Image.Image:
    image, draw = canvas()
    draw.arc([u(18), u(22), u(118), u(122)], start=-52, end=52, fill=TEAL, width=u(5))
    draw.arc([u(10), u(6), u(110), u(106)], start=-42, end=42, fill=GOLD, width=u(5))
    blade(draw, 34, 92, -0.86, 52, 5)
    blade(draw, 30, 38, 0.70, 46, 4, GOLD_DIM)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_lunge_thrust() -> Image.Image:
    image, draw = canvas()
    speed_lines(draw, 6, 34, 46, 34, 3)
    speed_lines(draw, 6, 94, 46, 94, 3)
    blade(draw, 26, 64, 0.0, 88, 6)
    draw.ellipse([u(96), u(56), u(120), u(80)], fill=EMBER)
    draw.ellipse([u(102), u(62), u(114), u(74)], fill=CREAM)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_spin_slash() -> Image.Image:
    image, draw = canvas()
    for start, end, color, width in ((-150, -20, GOLD, 6), (-10, 120, TEAL, 5),
                                      (130, 250, GOLD_DIM, 4)):
        draw.arc([u(12), u(12), u(116), u(116)], start=start, end=end,
                 fill=color, width=u(width))
    import math
    for angle in (-20, 120, 250):
        tip = math.radians(angle)
        x, y = 64 + math.cos(tip) * 50, 64 + math.sin(tip) * 50
        draw.ellipse([u(x - 5), u(y - 5), u(x + 5), u(y + 5)], fill=CREAM)
    blade(draw, 42, 82, -0.7, 40, 4, CREAM)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_dash_stab() -> Image.Image:
    image, draw = canvas()
    for index in range(4):
        y = 30 + index * 20
        draw.line([(u(4 + index * 4), u(y)), (u(46 + index * 6), u(y))],
                  fill=TEAL_DIM, width=u(3))
    blade(draw, 46, 66, -0.18, 62, 5, CREAM)
    draw.polygon([(u(96), u(66)), (u(118), u(50)), (u(110), u(74))], fill=TEAL)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_fireball() -> Image.Image:
    image, draw = canvas()
    import math
    for index in range(5):
        angle = math.radians(150 + index * 18)
        length = 34 - index * 3
        draw.line([(u(56 - math.cos(angle) * length), u(64 + math.sin(angle) * length * 0.5)),
                   (u(58), u(64))], fill=EMBER, width=u(5 - index * 0.6))
    glow_orb(draw, 78, 62, 26)
    draw.polygon([(u(70), u(18)), (u(88), u(44)), (u(68), u(38))], fill=EMBER_HOT)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_bone_spear() -> Image.Image:
    image, draw = canvas()
    import math
    angle = -0.62
    dx, dy = math.cos(angle), math.sin(angle)
    px, py = -dy, dx
    for index in range(-1, 2):
        offset = index * 6
        draw.line([(u(26 + px * offset - dx * 40), u(86 + py * offset - dy * 40)),
                   (u(26 + px * offset), u(86 + py * offset))], fill=TEAL_DIM, width=u(2))
    draw.line([(u(26), u(86)), (u(96), u(36))], fill=BONE, width=u(6))
    draw.polygon([(u(100), u(30)), (u(112), u(22)), (u(106), u(42))], fill=CREAM)
    for index in range(3):
        x, y = 56 + index * 12, 74 - index * 12
        draw.line([(u(x), u(y)), (u(x + 8), u(y - 12))], fill=BONE, width=u(3))
    draw.ellipse([u(30), u(78), u(48), u(96)], fill=(114, 203, 182, 90))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_shield_bash() -> Image.Image:
    image, draw = canvas()
    shield_shape(draw, 56, 64, 36)
    import math
    for index in range(7):
        angle = math.radians(index * 360 / 7.0)
        x0, y0 = 100 + math.cos(angle) * 8, 58 + math.sin(angle) * 8
        x1, y1 = 100 + math.cos(angle) * 22, 58 + math.sin(angle) * 22
        draw.line([(u(x0), u(y0)), (u(x1), u(y1))], fill=EMBER, width=u(3))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_shield_charge() -> Image.Image:
    image, draw = canvas()
    speed_lines(draw, 8, 32, 40, 32, 2)
    speed_lines(draw, 8, 96, 40, 96, 2)
    shield_shape(draw, 62, 64, 38, GOLD)
    chevron(draw, 92, 64, 26, 10, 8, TEAL)
    chevron(draw, 108, 64, 26, 10, 8, TEAL)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def build_shield_slam() -> Image.Image:
    image, draw = canvas()
    shield_shape(draw, 64, 50, 34)
    for index in range(3):
        radius = 22 + index * 14
        draw.arc([u(64 - radius), u(92 - radius * 0.45), u(64 + radius), u(92 + radius * 0.45)],
                 start=180, end=360, fill=EMBER if index == 0 else GOLD_DIM, width=u(4))
    draw.line([(u(22), u(104)), (u(106), u(104))], fill=TEAL, width=u(3))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


BUILDERS = {
    "charge": build_charge,
    "barrage": build_barrage,
    "triple_volley": build_triple_volley,
    "piercing_shot": build_piercing_shot,
    "double_slash": build_double_slash,
    "lunge_thrust": build_lunge_thrust,
    "spin_slash": build_spin_slash,
    "dash_stab": build_dash_stab,
    "fireball": build_fireball,
    "bone_spear": build_bone_spear,
    "shield_bash": build_shield_bash,
    "shield_charge": build_shield_charge,
    "shield_slam": build_shield_slam,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, builder in BUILDERS.items():
        path = OUT / f"{name}.png"
        builder().save(path, optimize=True)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
