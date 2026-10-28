"""Procedural material fields for the Blood Ledger menu language.

Every menu surface in Ghost of the Warband is built from a handful of painterly
materials: blackened iron, hammered steel, ox-hide vellum, oxblood leather, dull
brass, wax and bone. Nothing here is a downloaded photograph and nothing bakes in
lighting: each field is generated from seeded value noise so the same call
produces the same pixels on every machine, and the bevel/emboss passes are
applied by the widget that owns the shape.

The module works in float32 RGB (0..1) and hands the result to PIL at the last
moment, which keeps the compositing maths readable and lets `bevel()` share one
light direction across every material.
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

# The one light in the room: cold moonlight from the upper left.
LIGHT = (-0.52, -0.85)


def make_rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(0xC0FFEE ^ (seed * 7919))


def value_noise(w: int, h: int, scale: int, seed: int) -> np.ndarray:
    """One smooth value-noise octave in 0..1, at `scale` pixels per lattice cell."""
    rng = make_rng(seed)
    gw = max(2, int(w / max(2, scale)) + 3)
    gh = max(2, int(h / max(2, scale)) + 3)
    grid = rng.random((gh, gw), dtype=np.float32)
    lattice = Image.fromarray((grid * 255.0).astype(np.uint8), "L")
    lattice = lattice.resize((w, h), Image.BICUBIC)
    return np.asarray(lattice, dtype=np.float32) / 255.0


def fbm(w: int, h: int, seed: int = 0, octaves: int = 5, scale: int = 96,
        persistence: float = 0.55, lacunarity: float = 2.0) -> np.ndarray:
    total = np.zeros((h, w), dtype=np.float32)
    amplitude = 1.0
    norm = 0.0
    for octave in range(octaves):
        total += amplitude * value_noise(w, h, max(2, int(scale)), seed + octave * 31)
        norm += amplitude
        amplitude *= persistence
        scale /= lacunarity
    return total / max(norm, 1e-6)


def stretched_noise(w: int, h: int, sx: float, sy: float, scale: int,
                    seed: int) -> np.ndarray:
    """Noise sampled on an anisotropically scaled grid: paper fibres and grain."""
    rng = make_rng(seed)
    gw = max(2, int(w / max(1.0, scale / sx)) + 3)
    gh = max(2, int(h / max(1.0, scale / sy)) + 3)
    grid = rng.random((gh, gw), dtype=np.float32)
    lattice = Image.fromarray((grid * 255.0).astype(np.uint8), "L")
    lattice = lattice.resize((w, h), Image.BICUBIC)
    return np.asarray(lattice, dtype=np.float32) / 255.0


def grain(w: int, h: int, seed: int, amount: float = 0.02) -> np.ndarray:
    """Per-pixel tooth; the one noise that must not be smoothed."""
    rng = make_rng(seed)
    return rng.normal(0.0, amount, (h, w)).astype(np.float32)


# --- shape helpers ---------------------------------------------------------

def rounded_mask(w: int, h: int, radius: float, inset: float = 0.0) -> np.ndarray:
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    r = max(0.0, radius - inset * 0.5)
    draw.rounded_rectangle((inset, inset, w - 1 - inset, h - 1 - inset), radius=r, fill=255)
    return np.asarray(mask, dtype=np.float32) / 255.0


def ellipse_mask(w: int, h: int, feather: float = 1.0) -> np.ndarray:
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, w - 1, h - 1), fill=255)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    if feather > 0.0:
        arr = gaussian_filter(arr, feather)
    return arr


def bevel(mask: np.ndarray, sigma: float = 2.4, strength: float = 1.0) -> np.ndarray:
    """Signed normal-lit shading for a mask: positive lit, negative shadow."""
    smooth = gaussian_filter(mask.astype(np.float32), sigma)
    gy, gx = np.gradient(smooth)
    shade = gx * LIGHT[0] + gy * LIGHT[1]
    peak = float(np.abs(shade).max())
    if peak < 1e-6:
        return np.zeros_like(mask)
    return np.clip(shade / peak, -1.0, 1.0) * strength


def lit(shade: np.ndarray, amount: float) -> np.ndarray:
    return np.clip(shade, 0.0, 1.0)[..., None] * amount


def shade_dark(shade: np.ndarray, amount: float) -> np.ndarray:
    return np.clip(-shade, 0.0, 1.0)[..., None] * amount


def rgba(rgb: np.ndarray, alpha: np.ndarray | None = None) -> Image.Image:
    rgb8 = (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    h, w = rgb8.shape[:2]
    if alpha is None:
        alpha8 = np.full((h, w), 255, dtype=np.uint8)
    else:
        alpha8 = (np.clip(alpha, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb8, alpha8]), "RGBA")


def paste(dst: np.ndarray, rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    a = np.clip(alpha, 0.0, 1.0)[..., None]
    return dst * (1.0 - a) + np.clip(rgb, 0.0, 1.0) * a


# --- materials -------------------------------------------------------------

def parchment(w: int, h: int, seed: int = 1) -> np.ndarray:
    """Ox-hide vellum: warm, cloudy, fibrous, creased, freckled and scorched."""
    rng = make_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = xx / max(1, w - 1)
    ny = yy / max(1, h - 1)

    # Base tone: warm ivory at the heart, tanned toward the deckle.
    cloud = fbm(w, h, seed, octaves=4, scale=190, persistence=0.65)
    blotch = fbm(w, h, seed + 1, octaves=4, scale=44, persistence=0.6)
    tone = 0.86 + 0.26 * (cloud - 0.5) + 0.10 * (blotch - 0.5)
    base = np.array([0.875, 0.760, 0.585], dtype=np.float32)
    col = base[None, None, :] * tone[..., None]

    # Cloudy age: broad sepia water stains, warmer than the sheet.
    stain = np.clip((fbm(w, h, seed + 2, octaves=4, scale=70) - 0.55) * 2.6, 0.0, 1.0)
    stain = gaussian_filter(stain, 2.0)
    col = paste(col, np.array([0.62, 0.470, 0.320], np.float32)[None, None, :], stain * 0.26)

    # Fibres: hair-fine striations in both directions, the thing that sells vellum.
    fine = gaussian_filter(rng.normal(0.0, 1.0, (h, w)).astype(np.float32), (0.6, 26.0))
    fine += gaussian_filter(rng.normal(0.0, 1.0, (h, w)).astype(np.float32), (26.0, 0.6)) * 0.7
    fine /= max(1e-6, float(np.abs(fine).max()))
    col *= (1.0 + 0.055 * fine)[..., None]
    col += (grain(w, h, seed + 3, 0.010) * 2.4)[..., None]

    light_pool = np.clip((cloud - 0.55) * 1.8, 0.0, 1.0)
    col += np.array([0.10, 0.085, 0.055], np.float32)[None, None, :] * light_pool[..., None]

    # Creases: a few folded hairlines that catch light on their upper lip.
    creases = np.zeros((h, w), dtype=np.float32)
    pen = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(pen)
    for _ in range(rng.integers(2, 5)):
        x0 = rng.uniform(-40, w * 0.8)
        y0 = rng.uniform(-40, h * 0.8)
        ang = rng.uniform(-0.5, 0.5) + (0.0 if rng.random() < 0.6 else np.pi / 2)
        length = rng.uniform(w * 0.4, w * 1.1)
        pts = []
        for step in range(7):
            t = step / 6.0
            pts.append((x0 + np.cos(ang) * length * t + np.sin(t * 9.0) * 3.0,
                        y0 + np.sin(ang) * length * t + np.cos(t * 7.0) * 3.0))
        draw.line(pts, fill=int(rng.uniform(90, 170)), width=1, joint="curve")
    creases = gaussian_filter(np.asarray(pen, np.float32) / 255.0, 0.55)
    col = paste(col, np.array([0.40, 0.285, 0.185], np.float32)[None, None, :], creases * 0.36)
    col += np.array([1.0, 0.93, 0.78], np.float32)[None, None, :] * (np.clip(bevel(creases, 1.8), 0, 1) * 0.10)[..., None]

    # Foxing: dense small rust freckles with soft haloes.
    speck = np.zeros((h, w), dtype=np.float32)
    hearts = np.zeros((h, w), dtype=np.float32)
    for _ in range(max(120, (w * h) // 2600)):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        radius = rng.uniform(0.6, 1.9)
        _disc(speck, cx, cy, radius * rng.uniform(2.6, 5.5))
        _disc(hearts, cx, cy, radius)
    speck = gaussian_filter(speck, 2.2)
    hearts = gaussian_filter(hearts, 0.55)
    fox = np.clip(speck * 0.13 + hearts * 0.42, 0.0, 1.0)
    col = paste(col, np.array([0.50, 0.315, 0.170], np.float32)[None, None, :], fox * 0.62)

    # Scorch: sharp soot at the deckle with ragged tongues reaching inward.
    edge = _edge_distance(w, h)
    burn_noise = fbm(w, h, seed + 33, octaves=5, scale=26)
    reach = 7.0 + 16.0 * burn_noise
    burn = np.clip((reach - edge) / np.maximum(reach, 1.0), 0.0, 1.0)
    burn = np.power(burn, 1.5)
    ring = np.exp(-np.maximum(edge - 4.0, 0.0) / 30.0) * np.clip(0.30 + burn_noise, 0.0, 1.1)
    col = paste(col, np.array([0.55, 0.375, 0.215], np.float32)[None, None, :], ring * 0.20)
    col = paste(col, np.array([0.115, 0.085, 0.065], np.float32)[None, None, :], burn * 0.90)
    return col


def _disc(field: np.ndarray, cx: float, cy: float, r: float) -> None:
    h, w = field.shape
    y0, y1 = max(0, int(cy - r - 1)), min(h, int(cy + r + 2))
    x0, x1 = max(0, int(cx - r - 1)), min(w, int(cx + r + 2))
    if y0 >= y1 or x0 >= x1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    field[y0:y1, x0:x1] += np.clip(r - np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2), 0.0, 1.0)


def _edge_distance(w: int, h: int) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    return np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))


def iron(w: int, h: int, seed: int = 2, rough: float = 1.0) -> np.ndarray:
    """Blackened iron, planished in overlapping hammer facets, scratched and pitted."""
    rng = make_rng(seed)
    hw, hh = w / 600.0, h / 400.0
    # Hammer facets: overlapping shallow domes. Their overlaps are the crescents
    # that make forged iron read at any size.
    height = np.zeros((h, w), dtype=np.float32)
    count = max(24, int(150 * hw * hh))
    for _ in range(count):
        cx, cy = rng.uniform(-40, w + 40), rng.uniform(-40, h + 40)
        r = rng.uniform(14, 46) * max(0.55, (hw + hh) * 0.5)
        weight = rng.uniform(0.35, 1.0)
        y0, y1 = max(0, int(cy - r)), min(h, int(cy + r) + 1)
        x0, x1 = max(0, int(cx - r)), min(w, int(cx + r) + 1)
        if y0 >= y1 or x0 >= x1:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        cap = np.clip(1.0 - ((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r), 0.0, 1.0)
        height[y0:y1, x0:x1] += weight * np.sqrt(cap)
    height = gaussian_filter(height, 1.1 * max(0.7, (hw + hh) * 0.5))

    gy, gx = np.gradient(height)
    shade = gx * LIGHT[0] + gy * LIGHT[1]
    peak = max(1e-6, float(np.abs(shade).max()))
    shade = shade / peak
    specular = np.clip(shade, 0.0, 1.0) ** 3
    shadow = np.clip(-shade, 0.0, 1.0) ** 1.6

    base = np.array([0.128, 0.142, 0.155], dtype=np.float32)
    facets = (height - float(height.mean())) / max(1e-6, rough * 0.6)
    tone = 0.94 + 0.16 * np.clip(facets, -1.5, 1.5)
    col = base[None, None, :] * tone[..., None]
    col *= (1.0 - 0.42 * shadow)[..., None]
    col += np.array([0.46, 0.52, 0.55], np.float32)[None, None, :] * (specular * 0.30)[..., None]

    # Cool moonlight edge and warm soot in the low spots.
    broad = fbm(w, h, seed + 1, octaves=3, scale=170)
    col *= (1.0 + 0.10 * (broad - 0.5))[..., None]
    soot = np.clip((fbm(w, h, seed + 2, octaves=4, scale=36) - 0.62) * 3.0, 0.0, 1.0)
    col = paste(col, np.array([0.035, 0.032, 0.032], np.float32)[None, None, :],
                soot * 0.45 * rough)

    # Scratches: bright steel where the black has been knocked off.
    pen = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(pen)
    for _ in range(max(20, int(70 * hw * hh))):
        x0, y0 = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.uniform(0, np.pi)
        length = rng.uniform(10, 90) * max(0.6, hw)
        draw.line((x0, y0, x0 + np.cos(ang) * length, y0 + np.sin(ang) * length),
                  fill=int(rng.uniform(60, 190)), width=1)
    scratches = gaussian_filter(np.asarray(pen, np.float32) / 255.0, 0.35)
    col += np.array([0.62, 0.66, 0.67], np.float32)[None, None, :] * (scratches * 0.30)[..., None]

    # Rust blooms, sparse and dark, mostly at the edge of the piece.
    edge = _edge_distance(w, h)
    bias = np.exp(-np.maximum(edge, 0.0) / 26.0)
    rust_field = np.clip((fbm(w, h, seed + 12, 4, 22) - 0.60) * 4.0, 0.0, 1.0) * bias
    col = paste(col, np.array([0.30, 0.145, 0.075], np.float32)[None, None, :],
                rust_field * 0.38 * rough)
    return col


def _ellipse(field: np.ndarray, cx: float, cy: float, rx: float, ry: float, weight: float) -> None:
    h, w = field.shape
    y0, y1 = max(0, int(cy - ry - 1)), min(h, int(cy + ry + 2))
    x0, x1 = max(0, int(cx - rx - 1)), min(w, int(cx + rx + 2))
    if y0 >= y1 or x0 >= x1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = ((xx - cx) / max(rx, 1e-3)) ** 2 + ((yy - cy) / max(ry, 1e-3)) ** 2
    field[y0:y1, x0:x1] += np.clip(1.0 - d, 0.0, 1.0) * weight


def brass(w: int, h: int, seed: int = 3) -> np.ndarray:
    """Dull, worn brass plate: soft patina, fine brush, faint scratches."""
    base = np.array([0.575, 0.435, 0.215], dtype=np.float32)
    mottle = fbm(w, h, seed, 4, 120)
    cloud = fbm(w, h, seed + 1, 5, 40)
    tooth = grain(w, h, seed + 2, 0.008)
    tone = 0.94 + 0.22 * (mottle - 0.5) + 0.12 * (cloud - 0.5) + tooth
    col = base[None, None, :] * tone[..., None]
    # Soft warm sheen bands: the plate is not flat metal, it is hand-polished.
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    col *= (1.0 + 0.10 * np.sin(yy * 6.0 + mottle.mean() * 8.0))[..., None]
    patina = np.clip((fbm(w, h, seed + 3, 5, 34) - 0.60) * 4.0, 0.0, 1.0)
    col = paste(col, np.array([0.30, 0.35, 0.28], np.float32)[None, None, :], patina * 0.26)
    worn = np.clip((fbm(w, h, seed + 5, 4, 22) - 0.58) * 3.4, 0.0, 1.0)
    col = paste(col, np.array([0.83, 0.71, 0.44], np.float32)[None, None, :], worn * 0.26)
    rng = make_rng(seed + 9)
    pen = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(pen)
    for _ in range(max(18, (w * h) // 5200)):
        x0, y0 = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.uniform(-0.35, 0.35)
        length = rng.uniform(10, 90)
        draw.line((x0, y0, x0 + np.cos(ang) * length, y0 + np.sin(ang) * length),
                  fill=int(rng.uniform(40, 110)), width=1)
    scratches = gaussian_filter(np.asarray(pen, np.float32) / 255.0, 0.45)
    col += np.array([0.95, 0.84, 0.60], np.float32)[None, None, :] * (scratches * 0.16)[..., None]
    return col


def bone(w: int, h: int, seed: int = 4) -> np.ndarray:
    """Carved bone: warm ivory, lengthwise grain, hairline cracks."""
    base = np.array([0.845, 0.790, 0.665], dtype=np.float32)
    grain_field = gaussian_filter(
        make_rng(seed).normal(0.0, 1.0, (h, w)).astype(np.float32), (0.6, 14.0))
    grain_field /= max(1e-6, float(np.abs(grain_field).max()))
    mottle = fbm(w, h, seed + 1, 5, 55)
    tone = 0.94 + 0.13 * (mottle - 0.5) + 0.035 * grain_field
    col = base[None, None, :] * tone[..., None]
    pore = np.clip((fbm(w, h, seed + 2, 4, 6) - 0.72) * 6.0, 0.0, 1.0)
    col = paste(col, np.array([0.46, 0.40, 0.30], np.float32)[None, None, :], pore * 0.45)
    cracks = np.clip((fbm(w, h, seed + 3, 4, 26) - 0.70) * 8.0, 0.0, 1.0)
    col = paste(col, np.array([0.42, 0.35, 0.25], np.float32)[None, None, :], cracks * 0.35)
    return col


def leather(w: int, h: int, seed: int = 5) -> np.ndarray:
    """Oxblood harness leather: pebbled grain, scuffed edges, dark creases."""
    base = np.array([0.190, 0.082, 0.068], dtype=np.float32)
    rough = fbm(w, h, seed, 5, 9)
    pebble = (rough - gaussian_filter(rough, 3.0)) * 6.0
    broad = fbm(w, h, seed + 1, 4, 90)
    tone = 1.0 + 0.45 * pebble + 0.30 * (broad - 0.5)
    col = base[None, None, :] * np.clip(tone, 0.35, 1.9)[..., None]
    edge = _edge_distance(w, h)
    scuff = np.exp(-np.maximum(edge, 0.0) / 16.0) * np.clip(0.4 + fbm(w, h, seed + 2, 3, 30), 0, 1.1)
    col = paste(col, np.array([0.46, 0.27, 0.18], np.float32)[None, None, :], scuff * 0.42)
    col = paste(col, np.array([0.06, 0.02, 0.02], np.float32)[None, None, :],
                np.clip(-pebble * 0.4, 0.0, 1.0) * 0.35)
    return col


def wax(w: int, h: int, seed: int = 6) -> np.ndarray:
    """Old sealing wax: oxblood red, cloudy, with candle soot in the hollows."""
    base = np.array([0.385, 0.070, 0.078], dtype=np.float32)
    mottle = fbm(w, h, seed, 5, 13)
    col = base[None, None, :] * (0.85 + 0.55 * (mottle - 0.5))[..., None]
    col = paste(col, np.array([0.16, 0.020, 0.030], np.float32)[None, None, :],
                np.clip(0.44 - mottle, 0.0, 1.0) * 0.7)
    col = paste(col, np.array([0.68, 0.20, 0.14], np.float32)[None, None, :],
                np.clip(mottle - 0.60, 0.0, 1.0) * 0.35)
    return col


def soul(w: int, h: int, seed: int = 7) -> np.ndarray:
    """The ghost accent: pale verdigris light, used only where a soul is present."""
    base = np.array([0.44, 0.72, 0.66], dtype=np.float32)
    n = fbm(w, h, seed, 4, 40)
    return base[None, None, :] * (0.9 + 0.3 * n)[..., None]
