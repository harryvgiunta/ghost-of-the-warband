#!/usr/bin/env python3
"""Ironwood world texture generator.

Deterministic, fully offline (numpy + Pillow only) authoring of every texture
named by the world-art contract.  Running

    python tools/world_textures.py

rewrites ``assets/world/textures/*.png`` and ``assets/world/world_textures.json``
byte-identically (fixed seeds, no timestamps), then validates the results and
writes ``.runtime/world-art/texture_report.txt`` plus contact sheets.

Authoring model
---------------
* All noise is a *tileable* value-noise/fBm built on a periodic lattice, so
  wrap-around continuity is structural rather than post-processed.  ``wrap``
  selects periodic x (panorama u), both axes (tiling albedo) or neither.
* Shapes are drawn with 4x supersampled Pillow buffers and Lanczos-downsampled;
  per-atlas-cell buffers guarantee fully transparent gutters.
* Detail textures are authored in "paint" (sRGB display) space; nothing is
  linearised.  Normal maps are derived from authored height fields with a
  central-difference gradient and the OpenGL (+Y up) convention.
* The sky is a 4096x2048 equirectangular panorama: an elevation ramp with a
  warm haze band, a broad Gaussian sun bloom (no disc), two cumulus banks with
  sun-side rim lighting and aerial-perspective fade, high cirrus, three hazy
  ridgelines just above the horizon and 1 LSB dither against 8-bit banding.
  Clouds are composed at half resolution and smoothly upsampled (they are soft
  by nature) which keeps the whole build well under two minutes.

CLI
---
    python tools/world_textures.py [--only id1,id2] [--no-sheets] [--stats]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = ROOT / "assets" / "world" / "textures"
SCRATCH = ROOT / ".runtime" / "world-art"

SEED = 20261023
GUTTER = 16

# ---------------------------------------------------------------------------
# small math helpers
# ---------------------------------------------------------------------------


def smoothstep(a: float, b: float, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def smooth(t):
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def stretch(a, lo=1.0, hi=99.0):
    """Percentile stretch to 0..1 (robust, deterministic)."""
    l, h = np.percentile(a, [lo, hi])
    if h <= l:
        return np.zeros_like(a)
    return np.clip((a - l) / (h - l), 0.0, 1.0).astype(np.float32)


def rgb(r, g, b):
    return np.array((r, g, b), np.float32) / 255.0


def mix(a, b, t):
    """Linear blend of RGB triples / arrays with a scalar or broadcastable t."""
    t = np.asarray(t, np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return a + (b - a) * t


# ---------------------------------------------------------------------------
# tileable value noise / fBm
# ---------------------------------------------------------------------------


def value_noise(w, h, fx, fy, seed, wrap="both"):
    """Bilinear value noise with a periodic lattice.

    wrap: "both" | "x" | "none".  Values are 0..1, mean ~0.5.
    """
    fx = max(1, min(int(round(fx)), w))
    fy = max(1, min(int(round(fy)), h))
    rng = np.random.default_rng(seed)
    lat = rng.random((fy, fx), dtype=np.float32)

    xs = (np.arange(w, dtype=np.float32) + 0.5) * (fx / w)
    ys = (np.arange(h, dtype=np.float32) + 0.5) * (fy / h)
    x0 = np.floor(xs)
    y0 = np.floor(ys)
    tx = smooth((xs - x0).astype(np.float32))
    ty = smooth((ys - y0).astype(np.float32))[:, None]
    x0 = x0.astype(np.int32)
    y0 = y0.astype(np.int32)

    if wrap in ("both", "x"):
        ix0 = x0 % fx
        ix1 = (x0 + 1) % fx
    else:
        ix0 = np.clip(x0, 0, fx - 1)
        ix1 = np.clip(x0 + 1, 0, fx - 1)
    if wrap == "both":
        iy0 = y0 % fy
        iy1 = (y0 + 1) % fy
    else:
        iy0 = np.clip(y0, 0, fy - 1)
        iy1 = np.clip(y0 + 1, 0, fy - 1)

    r0 = lat[iy0]
    r1 = lat[iy1]
    c00 = r0[:, ix0]
    c10 = r0[:, ix1]
    c01 = r1[:, ix0]
    c11 = r1[:, ix1]
    top = c00 + (c10 - c00) * tx
    bot = c01 + (c11 - c01) * tx
    return (top + (bot - top) * ty).astype(np.float32)


def fbm(w, h, fx, fy, seed, octaves=5, persistence=0.5, wrap="both", ridge=False):
    """Fractal sum of value noise.  ridge=True folds octaves for filigree."""
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        n = value_noise(w, h, fx * (1 << o), fy * (1 << o), seed + 7919 * o, wrap)
        if ridge:
            n = 1.0 - np.abs(n * 2.0 - 1.0)
        out += amp * n
        norm += amp
        amp *= persistence
    return out / norm


def sample_field(field, uu, vv, wrap_x=True, wrap_y=False):
    """Bilinear sample of a float field at normalised coords (broadcasts)."""
    h, w = field.shape
    x = np.asarray(uu, np.float32) * w - 0.5
    y = np.asarray(vv, np.float32) * h - 0.5
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    tx = (x - x0).astype(np.float32)
    ty = (y - y0).astype(np.float32)
    x0 %= w
    x1 = (x0 + 1) % w
    if wrap_x:
        x0 %= w
        x1 = (x0 + 1) % w
    else:
        x0 = np.clip(x0, 0, w - 1)
        x1 = np.clip(x0 + 1, 0, w - 1)
    if wrap_y:
        y0 %= h
        y1 = (y0 + 1) % h
    else:
        y0 = np.clip(y0, 0, h - 1)
        y1 = np.clip(y0 + 1, 0, h - 1)

    c00 = field[y0, x0]
    c10 = field[y0, x1]
    c01 = field[y1, x0]
    c11 = field[y1, x1]
    top = c00 + (c10 - c00) * tx
    bot = c01 + (c11 - c01) * tx
    out = top + (bot - top) * ty
    return out.astype(np.float32)


def normal_from_height(height, strength=1.0):
    """OpenGL-convention tangent normal map (green = +Y up / image up).

    Image rows grow downward, so dh/dy_up = -dh/dy_image and the green channel
    is +dh/dy_image.  Heights are expected in 0..1.
    """
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(height)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.empty(height.shape + (3,), np.float32)
    out[..., 0] = nx * inv * 0.5 + 0.5
    out[..., 1] = ny * inv * 0.5 + 0.5
    out[..., 2] = nz * inv * 0.5 + 0.5
    return out


def to_image(arr, mode="RGB"):
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(a, mode)


def dither(arr, scale=0.5, seed=SEED):
    """Add ±scale LSB uniform noise so smooth ramps survive 8-bit quantisation."""
    rng = np.random.default_rng(seed)
    n = rng.random(arr.shape[:2], dtype=np.float32) - 0.5
    if arr.ndim == 3:
        n = n[..., None]
    return arr + (n * scale) / 255.0


# ---------------------------------------------------------------------------
# sky (4096x2048 equirectangular, seamless in u)
# ---------------------------------------------------------------------------

SKY_STOPS = [
    (0.000, (38, 84, 158)),
    (0.100, (56, 104, 178)),
    (0.240, (90, 138, 198)),
    (0.340, (118, 158, 204)),
    (0.420, (146, 176, 208)),
    (0.462, (160, 182, 204)),
    (0.486, (184, 194, 200)),
    (0.494, (214, 206, 192)),
    (0.504, (238, 226, 204)),
    (0.518, (212, 208, 188)),
    (0.560, (184, 188, 162)),
    (0.700, (148, 156, 134)),
    (1.000, (104, 114, 100)),
]


def _sky_ramp(v, stops=SKY_STOPS):
    v = np.asarray(v, np.float32).ravel()
    pos = np.array([s[0] for s in stops], np.float32)
    cols = np.array([s[1] for s in stops], np.float32) / 255.0
    out = np.empty((v.size, 3), np.float32)
    for c in range(3):
        out[:, c] = np.interp(v, pos, cols[:, c])
    return out


def make_sky(w=4096, h=2048, debug=None):
    """Painterly midday panorama.  Returned as float RGB 0..1, (h, w, 3)."""
    sun_az = 0.615 * 2.0 * math.pi
    sun_el = math.radians(26.0)
    sun_dir = np.array(
        [math.cos(sun_el) * math.cos(sun_az), math.sin(sun_el),
         math.cos(sun_el) * math.sin(sun_az)], np.float32)

    uv = (np.arange(w, dtype=np.float32) + 0.5) / w
    vv = (np.arange(h, dtype=np.float32) + 0.5) / h
    v = vv[:, None]
    az = uv * (2.0 * math.pi)
    el = (0.5 - vv) * math.pi

    # --- base elevation ramp + gentle value mottling for a painted feel -----
    ramp = _sky_ramp(vv)
    sky = np.broadcast_to(ramp[:, None, :], (h, w, 3)).astype(np.float32)
    mottle = fbm(w, h, 5, 3, SEED + 3, octaves=4, wrap="x")
    mottle = 0.955 + 0.075 * mottle
    sky *= mottle[..., None]

    # --- direction grid + broad sun bloom ----------------------------------
    ce = np.cos(el)[:, None]
    dx = ce * np.cos(az)[None, :]
    dy = np.broadcast_to(np.sin(el)[:, None], (h, w)).astype(np.float32)
    dz = ce * np.sin(az)[None, :]
    dot = dx * sun_dir[0] + dy * sun_dir[1] + dz * sun_dir[2]
    ang = np.arccos(np.clip(dot, -1.0, 1.0))
    del dot, dx, dy, dz

    # Soft bloom: blend toward warm white instead of adding, so the glow
    # never clips a channel and cannot read as a hard sun disc.
    glow_core = np.exp(-((ang / 0.055) ** 2))
    glow_wide = np.exp(-((ang / 0.36) ** 2))
    glow_halo = np.exp(-((ang / 0.85) ** 2))
    glow = np.clip(0.34 * glow_wide + 0.11 * glow_halo + 0.47 * glow_core,
                   0.0, 1.0) * 0.94
    sky = mix(sky, rgb(255, 250, 236), glow[..., None])
    del glow_core, glow_wide, glow_halo, glow, ang

    # --- clouds, composed at half resolution -------------------------------
    # Three noise scales: banking masses, cumulus billows, small boil detail.
    cw, ch = w // 2, h // 2
    u2 = (np.arange(cw, dtype=np.float32) + 0.5) / cw
    v2 = (np.arange(ch, dtype=np.float32) + 0.5) / ch
    vv2 = v2[:, None]

    # isotropic-ish lumps (cells are roughly square in angle: fx ~= 2*fy)
    cov = (0.50 * fbm(cw, ch, 8, 4, SEED + 11, octaves=5, wrap="x")
           + 0.32 * fbm(cw, ch, 18, 9, SEED + 12, octaves=4, wrap="x")
           + 0.18 * fbm(cw, ch, 40, 20, SEED + 18, octaves=3, wrap="x"))
    cov = stretch(cov, 2, 98)
    wx = (fbm(cw, ch, 4, 3, SEED + 13, octaves=3, wrap="x") - 0.5) * 0.040
    wy = (fbm(cw, ch, 5, 4, SEED + 14, octaves=3, wrap="x") - 0.5) * 0.020
    cov = sample_field(cov, u2[None, :] + wx, v2[:, None] + wy, wrap_x=True,
                       wrap_y=False)

    base_shift = (value_noise(cw, 1, 7, 1, SEED + 15, wrap="x")[0] - 0.5) * 0.014
    vbase = 0.4692 + base_shift[None, :]
    vtop = 0.2500

    H = (vbase - v2[:, None]) / (vbase - vtop)
    Hc = np.clip(H, 0.0, 1.0)
    base_mask = smoothstep(0.0, 0.011, vbase - v2[:, None])
    topfade = 1.0 - smoothstep(0.62, 1.02, H)
    dens = smoothstep(0.595, 0.672, cov) * base_mask * topfade

    # sun-side rims: density compared with a sample shifted toward the sun
    az2 = u2 * (2.0 * math.pi)
    el2 = (0.5 - v2) * math.pi
    du = np.sign(np.sin(sun_az - az2))[None, :] * 0.0060
    dv = np.where(el2[:, None] < sun_el, -0.0022, 0.0022)
    d_shift = sample_field(dens, u2[None, :] + du, v2[:, None] + dv,
                           wrap_x=True, wrap_y=False)
    rim = np.clip((dens - d_shift) * 2.4, 0.0, 1.0)
    del d_shift

    # light structure inside the cloud: tops lit, bases in cool shade
    puff = fbm(cw, ch, 34, 30, SEED + 16, octaves=3, wrap="x")
    bright = 0.30 + 0.60 * Hc ** 0.80 + 0.50 * rim + 0.06 * (puff - 0.5)
    bright = np.clip(bright, 0.0, 1.0)

    lit = rgb(255, 250, 238)
    midc = rgb(186, 195, 214)
    shade = rgb(104, 120, 152)
    cloud = mix(shade, midc, smoothstep(0.06, 0.60, bright))
    cloud = mix(cloud, lit, smoothstep(0.56, 1.0, bright))

    sunprox = np.exp(-((np.arccos(np.clip(
        np.cos(el2)[:, None] * np.cos(az2)[None, :] * sun_dir[0]
        + np.sin(el2)[:, None] * sun_dir[1]
        + np.cos(el2)[:, None] * np.sin(az2)[None, :] * sun_dir[2],
        -1.0, 1.0)) / 0.55) ** 2))
    cloud = mix(cloud, rgb(255, 245, 220),
                np.clip(sunprox * 0.42 + rim * 0.30, 0.0, 0.72))
    del sunprox

    # faint interior billow creases (painted, not a noise field)
    crease = smoothstep(0.62, 0.90, fbm(cw, ch, 26, 20, SEED + 17, octaves=3,
                                        wrap="x", ridge=True))
    cloud *= (1.0 - 0.14 * crease * (1.0 - rim))[..., None]

    band = smoothstep(0.010, 0.030, el2[:, None]) * (1.0 - smoothstep(1.15, 1.45, el2[:, None]))
    alpha = dens * band * 0.97

    # aerial perspective: clouds near the horizon sink into the haze
    haze_mix = smoothstep(0.415, 0.500, v2[:, None])
    haze_col = _sky_ramp(v2)[:, None, :]
    cloud = mix(cloud, haze_col, haze_mix * 0.46)
    alpha *= 1.0 - 0.30 * haze_mix

    # --- thin high cirrus (two crossed anisotropic layers) -----------------
    cir = (0.55 * fbm(cw, ch, 2, 20, SEED + 21, octaves=5, wrap="x")
           + 0.45 * fbm(cw, ch, 3, 34, SEED + 22, octaves=4, wrap="x"))
    cir_wx = (fbm(cw, ch, 3, 6, SEED + 23, octaves=2, wrap="x") - 0.5) * 0.09
    cir = sample_field(cir, u2[None, :] + cir_wx, v2[:, None], wrap_x=True)
    cir = stretch(cir, 40, 99.5)
    cir_a = smoothstep(0.20, 0.80, cir) * 0.30
    cir_a *= smoothstep(0.14, 0.28, el2[:, None])       # above 8-16 deg
    cir_a *= 1.0 - smoothstep(1.00, 1.30, el2[:, None])
    cir_col = mix(rgb(245, 245, 242), rgb(255, 249, 236), 0.5)

    cloud = mix(cloud, cir_col, (cir_a / np.maximum(alpha + cir_a, 1e-5))[..., None])
    alpha = 1.0 - (1.0 - alpha) * (1.0 - cir_a)

    # --- composite clouds onto the full-resolution sky ---------------------
    uu = uv
    for c in range(3):
        up = sample_field(cloud[..., c], uu, vv[:, None], wrap_x=True)
        al = sample_field(alpha, uu, vv[:, None], wrap_x=True)
        sky[..., c] = sky[..., c] * (1.0 - al) + up * al
    if debug is not None:
        debug["alpha"] = al
        debug["dens"] = dens
        debug["rim"] = rim
        debug["sun"] = (sun_az, sun_el)
        debug["cov"] = cov
    del cov, dens, cloud, alpha, cir, cir_a

    # --- fine painterly grain (coherent, not white noise) ------------------
    grain = fbm(w, h, 900, 420, SEED + 61, octaves=2, wrap="x")
    stroke = fbm(w, h, 260, 40, SEED + 62, octaves=2, wrap="x")
    sky *= (1.0 + (grain - 0.5) * 0.135 + (stroke - 0.5) * 0.075)[..., None]
    del grain, stroke

    # --- three hazy ridgelines just above the horizon ----------------------
    ridge_specs = [
        # (base_deg, amp_deg, freq, colour, edge softness in v)
        (0.55, 0.55, 3.0, (150, 168, 188), 0.0016),
        (0.85, 0.90, 4.5, (128, 150, 176), 0.0012),
        (0.35, 1.35, 6.5, (108, 134, 163), 0.0009),
    ]
    horizon_v = 0.5
    for i, (base_deg, amp_deg, freq, col, soft) in enumerate(ridge_specs):
        n = value_noise(w, 1, freq, 1, SEED + 31 + i, wrap="x")[0]
        n2 = value_noise(w, 1, freq * 3, 1, SEED + 41 + i, wrap="x")[0]
        line = base_deg + amp_deg * (0.72 * n + 0.28 * n2)
        el_line = np.radians(line)[None, :]
        mask = 1.0 - smoothstep(-soft, soft, el[:, None] - el_line)
        # only the thin band around the horizon is a silhouette, so the haze
        # ramp below it survives
        mask *= 1.0 - smoothstep(0.500, 0.522, vv[:, None])
        # fade each ridge down into the haze so it reads as distance
        ccol = np.array(col, np.float32) / 255.0
        depth = 0.45 + 0.25 * i
        val = mix(ccol, _sky_ramp(np.array([0.5]))[0], depth)
        sky = sky * (1.0 - mask[..., None] * 0.92) + val * (mask[..., None] * 0.92)

    # --- dither to defeat 8-bit banding, quantise --------------------------
    img = np.clip(dither(sky, 1.0, SEED + 51), 0.0, 1.0)
    return to_image(img, "RGB")


# ---------------------------------------------------------------------------
# shared procedural helpers
# ---------------------------------------------------------------------------


def cellular(w, h, nx, ny, seed, wrap="both"):
    """Jittered-grid Voronoi.  Returns (f1, f2, cell_id) in pixels.

    Distances include the wrapping neighbours, so the field tiles.
    """
    rng = np.random.default_rng(seed)
    jx = (rng.random((ny, nx), dtype=np.float32) - 0.5) * 0.72
    jy = (rng.random((ny, nx), dtype=np.float32) - 0.5) * 0.72
    cw, ch = w / nx, h / ny
    gx = np.arange(w, dtype=np.float32) * (nx / w)
    gy = np.arange(h, dtype=np.float32) * (ny / h)
    cx = np.floor(gx).astype(np.int32)
    cy = np.floor(gy).astype(np.int32)
    X = (gx * cw)[None, :]
    Y = (gy * ch)[:, None]
    f1 = np.full((h, w), 1e9, np.float32)
    f2 = np.full((h, w), 1e9, np.float32)
    ids = np.zeros((h, w), np.int32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            ix = cx + ox
            iy = cy + oy
            if wrap == "both":
                wx_ = ix % nx
                wy_ = iy % ny
            else:
                wx_ = np.clip(ix, 0, nx - 1)
                wy_ = np.clip(iy, 0, ny - 1)
            jxv = jx[np.ix_(wy_, wx_)]
            jyv = jy[np.ix_(wy_, wx_)]
            px = (ix[None, :] + jxv + 0.5) * cw
            py = (iy[:, None] + jyv + 0.5) * ch
            ddx = px - X
            ddy = py - Y
            if wrap == "both":
                ddx -= w * np.round(ddx / w)
            ddy -= h * np.round(ddy / h)
            d2 = ddx * ddx + ddy * ddy
            closer = d2 < f1
            f2 = np.where(closer, f1, np.minimum(f2, d2))
            f1 = np.where(closer, d2, f1)
            ids = np.where(closer, wy_[:, None] * nx + wx_[None, :], ids)
    return np.sqrt(f1), np.sqrt(f2), ids


def value_hash(ids, seed):
    """Deterministic per-cell hash in 0..1."""
    rng = np.random.default_rng(seed)
    table = rng.random(int(ids.max()) + 2, dtype=np.float32)
    return table[np.clip(ids, 0, table.size - 1)]


def _vary(color, rng, amount=10.0):
    c = np.array(color, np.float32)
    return tuple(np.clip(c + rng.uniform(-amount, amount, 3), 0, 255).astype(int))


def _rot(pts, ang, ox=0.0, oy=0.0):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(ox + x * ca - y * sa, oy + x * sa + y * ca) for x, y in pts]


def _leaf_outline(length, width, lobes=0, lobe_amp=0.0, n=26):
    """Half-symmetric leaf outline, base (0,0), tip (0,-length)."""
    side = []
    for t in np.linspace(0.02, 0.995, n):
        prof = math.sin(math.pi * t ** 0.82) ** 0.55
        w = width * prof * (1.0 + lobe_amp * math.sin(t * lobes * math.pi * 2.0))
        side.append((max(w, 0.6), -length * t))
    return [(0.0, 0.0)] + side[::-1] + [(0.0, -length)] + \
           [(-x, y) for x, y in side]


def _ellipse_pts(cx, cy, rx, ry, ang=0.0, n=22):
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        pts.append(_rot([(rx * math.cos(a), ry * math.sin(a))], ang, cx, cy)[0])
    return pts


def _new_cell(size, ss=4):
    return Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))


def _finish_cell(img, size, edge=0.16, width=0.62):
    """Lanczos down to ``size`` (int or (w,h)) with a crisp alpha cutout."""
    wh = (size, size) if isinstance(size, int) else tuple(size)
    img = img.resize(wh, Image.LANCZOS)
    a = np.asarray(img, np.float32)
    al = np.clip((a[..., 3] / 255.0 - edge) / width, 0.0, 1.0)
    a[..., 3] = al * 255.0
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def compose_atlas(cells, cols, rows, size=512, gutter=GUTTER):
    """Paste equal cells with a fully transparent gutter on all sides."""
    cw = (size - gutter * (cols + 1)) // cols
    chh = (size - gutter * (rows + 1)) // rows
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        cx = gutter + (i % cols) * (cw + gutter)
        cy = gutter + (i // cols) * (chh + gutter)
        out.paste(cell, (cx, cy))
    return out, (cw, chh)


def atlas_alpha_coverage(img, cols, rows, gutter=GUTTER):
    arr = np.asarray(img)[..., 3]
    size = img.width
    cw = (size - gutter * (cols + 1)) // cols
    chh = (size - gutter * (rows + 1)) // rows
    cov = []
    for i in range(cols * rows):
        cx = gutter + (i % cols) * (cw + gutter)
        cy = gutter + (i // cols) * (chh + gutter)
        cell = arr[cy:cy + chh, cx:cx + cw]
        cov.append(round(float((cell > 12).mean()), 3))
    return cov


# ---------------------------------------------------------------------------
# bark (256x512 seamless, + height-derived normal)
# ---------------------------------------------------------------------------


def _bark_oak(w=256, h=512):
    yy = (np.arange(h, dtype=np.float32) + 0.5)[:, None]
    warp = (fbm(w, h, 3, 2, SEED + 101, octaves=3) - 0.5) * 46.0
    xx = (np.arange(w, dtype=np.float32) + 0.5)[None, :] + warp
    uu, vv = xx / w, np.broadcast_to(yy / h, (h, w))

    fib = sample_field(fbm(w, h, 8, 2, SEED + 102, octaves=5), uu, vv,
                       wrap_x=True, wrap_y=True)
    fine = fbm(w, h, 26, 9, SEED + 103, octaves=4)
    micro = fbm(w, h, 90, 70, SEED + 104, octaves=3)
    fiss = smoothstep(0.47, 0.35, fib) * 0.9 + smoothstep(0.56, 0.44, fine) * 0.45
    fiss = np.clip(fiss, 0, 1)
    plate = stretch(0.5 * fib + 0.35 * fine + 0.15 * micro, 3, 97)

    base = mix(rgb(104, 89, 72), rgb(126, 110, 88), plate)
    dark = rgb(46, 38, 30)
    alb = mix(base, dark, smoothstep(0.05, 0.95, fiss))
    alb *= (0.90 + 0.19 * micro)[..., None]

    # pale lichen flecks in the plate grain
    lichen = smoothstep(0.62, 0.78, fbm(w, h, 45, 45, SEED + 105, octaves=3))
    alb = mix(alb, rgb(150, 156, 132), lichen * 0.22)

    height = 0.55 - 0.62 * fiss + 0.16 * fine + 0.05 * micro

    # knots: periodic radial rings, kept seamless by wrapped distance
    ky = np.arange(h, dtype=np.float32)[:, None]
    kx = np.arange(w, dtype=np.float32)[None, :]
    for cx, cy, r in ((36, 96, 15), (198, 268, 19), (120, 430, 11)):
        dx = np.abs(kx - cx)
        dx = np.minimum(dx, w - dx)
        dy = np.abs(ky - cy)
        dy = np.minimum(dy, h - dy)
        dr = np.sqrt((dx / 1.0) ** 2 + (dy / 1.6) ** 2) / r
        ring = np.cos(dr * math.pi * 5.0) * np.exp(-dr * 2.2)
        core = np.exp(-(dr * 2.6) ** 2)
        alb = mix(alb, rgb(40, 31, 24), np.clip(core * 0.85 - ring * 0.15, 0, 1))
        height += np.clip(ring * 0.22 - core * 0.30, -0.5, 0.5)

    return alb, height


def _bark_pine(w=256, h=512):
    f1, f2, ids = cellular(w, h, 6, 15, SEED + 111)
    edge = f2 - f1
    groove = smoothstep(0.0, 4.5, edge)
    height = smoothstep(2.0, 26.0, f1) * groove
    cellv = value_hash(ids, SEED + 112)

    crack = smoothstep(0.58, 0.40, fbm(w, h, 30, 5, SEED + 113, octaves=4))
    fine = fbm(w, h, 70, 60, SEED + 114, octaves=3)

    plate = mix(rgb(108, 70, 46), rgb(146, 94, 57), cellv)
    plate = mix(plate, rgb(126, 84, 58), 0.4)
    alb = mix(rgb(38, 25, 17), plate, 0.25 + 0.75 * groove)
    alb = mix(alb, rgb(62, 42, 29), crack * 0.55)
    alb *= (0.88 + 0.24 * fine)[..., None]
    alb = mix(alb, rgb(122, 130, 104),
              smoothstep(0.66, 0.84, fbm(w, h, 24, 40, SEED + 115, octaves=2)) * 0.25)

    height = height * 0.8 + crack * 0.25 + fine * 0.10 - 0.02
    return alb, height


def _bark_birch(w=256, h=512):
    grain = fbm(w, h, 18, 3, SEED + 121, octaves=4)
    patch = fbm(w, h, 5, 6, SEED + 122, octaves=4)
    fine = fbm(w, h, 110, 80, SEED + 123, octaves=3)

    base = mix(rgb(222, 219, 205), rgb(238, 234, 220), stretch(patch, 5, 95))
    alb = mix(base, rgb(196, 190, 172), smoothstep(0.55, 0.8, grain) * 0.35)
    height = 0.5 + 0.06 * (grain - 0.5) + 0.03 * (fine - 0.5)

    rng = np.random.default_rng(SEED + 124)
    kx = np.arange(w, dtype=np.float32)[None, :]
    ky = np.arange(h, dtype=np.float32)[:, None]
    # dark horizontal scars with a soft lens shape
    for _ in range(16):
        cx = rng.integers(0, w)
        cy = rng.integers(0, h)
        sw = rng.uniform(0.05, 0.16) * w
        sh = rng.uniform(0.006, 0.014) * h
        dx = np.abs(kx - cx)
        dx = np.minimum(dx, w - dx)
        dy = np.abs(ky - cy)
        dy = np.minimum(dy, h - dy)
        d = np.sqrt((dx / sw) ** 2 + (dy / sh) ** 2)
        scar = np.clip(1.0 - d, 0.0, 1.0) ** 0.6
        alb = mix(alb, rgb(52, 48, 44), scar * 0.92)
        height -= scar * 0.16
        # a lit lip beneath the scar
        d2 = np.sqrt((dx / (sw * 1.05)) ** 2 + ((dy - sh * 1.8) / sh) ** 2)
        lip = np.clip(1.0 - d2, 0.0, 1.0) ** 1.2
        alb = mix(alb, rgb(250, 247, 236), np.clip(lip - scar, 0, 1) * 0.55)
        height += np.clip(lip - scar, 0, 1) * 0.05

    # small lenticel dashes
    for _ in range(90):
        cx = rng.integers(0, w)
        cy = rng.integers(0, h)
        sw = rng.uniform(1.0, 3.2)
        sh = rng.uniform(0.6, 1.4)
        dx = np.abs(kx - cx)
        dx = np.minimum(dx, w - dx)
        dy = np.abs(ky - cy)
        dy = np.minimum(dy, h - dy)
        d = np.sqrt((dx / sw) ** 2 + (dy / sh) ** 2)
        dash = np.clip(1.0 - d, 0, 1) ** 0.8
        alb = mix(alb, rgb(74, 66, 58), dash * 0.8)
        height -= dash * 0.03

    alb *= (0.985 + 0.03 * (fine - 0.5))[..., None]
    return alb, height


def _bark_dead(w=256, h=512):
    crack = smoothstep(0.56, 0.40, fbm(w, h, 16, 3, SEED + 131, octaves=5))
    split = smoothstep(0.62, 0.45, fbm(w, h, 6, 2, SEED + 132, octaves=4, ridge=True))
    f1, f2, ids = cellular(w, h, 7, 12, SEED + 133)
    crack2 = smoothstep(0.0, 2.5, f2 - f1)
    grain = fbm(w, h, 60, 30, SEED + 134, octaves=4)
    stain = fbm(w, h, 9, 5, SEED + 135, octaves=3)

    base = mix(rgb(158, 158, 150), rgb(184, 183, 172), stretch(stain, 5, 95))
    alb = mix(base, rgb(84, 83, 78), crack * 0.75 + (1.0 - crack2) * 0.35)
    alb = mix(alb, rgb(122, 126, 112),
              smoothstep(0.6, 0.85, fbm(w, h, 22, 22, SEED + 136, octaves=3)) * 0.30)
    alb *= (0.92 + 0.16 * grain)[..., None]
    height = 0.5 - 0.38 * crack - 0.20 * split + 0.08 * grain - 0.12 * (1.0 - crack2)
    return alb, height


BARK_STRENGTH = {"bark_oak": 6.0, "bark_pine": 5.0, "bark_birch": 15.0, "bark_dead": 5.0}


def make_bark(species):
    fn = {"bark_oak": _bark_oak, "bark_pine": _bark_pine,
          "bark_birch": _bark_birch, "bark_dead": _bark_dead}[species]
    alb, height = fn()
    norm = normal_from_height(height, BARK_STRENGTH[species])
    return to_image(alb, "RGB"), to_image(norm, "RGB")


# ---------------------------------------------------------------------------
# foliage / groundcover atlases (RGBA, 4x supersampled shapes)
# ---------------------------------------------------------------------------


def _draw_leaf(d, cx, cy, length, width, ang, fill, vein, lobes=0, lobe_amp=0.0, ss=4):
    pts = _leaf_outline(length, width, lobes, lobe_amp)
    poly = _rot(pts, ang, cx, cy)
    d.polygon(poly, fill=fill)
    # veins: midrib + side veins, clipped by construction inside the blade
    mid = _rot([(0.0, 0.0), (0.0, -length * 0.94)], ang, cx, cy)
    d.line([(x, y) for x, y in mid], fill=vein, width=max(1, int(0.9 * ss)))
    for t in (0.26, 0.44, 0.62, 0.78):
        prof = math.sin(math.pi * t ** 0.82) ** 0.55
        wdt = width * prof * 0.78
        seg = _rot([(0.0, -length * t), (wdt, -length * (t + 0.12))], ang, cx, cy)
        d.line([(x, y) for x, y in seg], fill=vein,
               width=max(1, int(0.65 * ss)))
        seg = _rot([(0.0, -length * t), (-wdt, -length * (t + 0.12))], ang, cx, cy)
        d.line([(x, y) for x, y in seg], fill=vein,
               width=max(1, int(0.65 * ss)))


def _leaf_cluster_cell(size, palette, veins, seed, leaves=11, lobes=0, lobe_amp=0.0,
                       twig_col=(88, 66, 46), leaf_scale=1.0, spread=0.55,
                       second_branch=True):
    ss = 4
    img = _new_cell(size, ss)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    S0 = size * ss
    # draw at 92% and inset, leaving headroom so no cell can clip its border
    S = S0 * 0.92
    off = S0 * 0.04
    cx, cy = off + S * 0.52, off + S * 0.93
    # main twig with a slight arc
    twig = [(cx + math.sin(t * 2.6) * S * 0.05, cy - S * 0.78 * t) for t in np.linspace(0, 1, 8)]
    d.line([(x, y) for x, y in twig], fill=(*twig_col, 255), width=max(3, int(S * 0.007)),
           joint="curve")
    for i in range(leaves):
        t = 0.20 + 0.78 * (i / max(1, leaves - 1))
        side = -1 if i % 2 else 1
        bx = cx + math.sin(t * 2.6) * S * 0.05
        by = cy - S * 0.78 * t
        # leaves fan out and up from the twig; upper ones lean more horizontal
        ang = side * (0.55 + 0.60 * t) + rng.uniform(-0.10, 0.10)
        col = _vary(palette[rng.integers(0, len(palette))], rng, 10)
        vn = _vary(veins[rng.integers(0, len(veins))], rng, 8)
        ln = S * rng.uniform(0.20, 0.30) * leaf_scale * (1.15 - 0.35 * t)
        wd = ln * rng.uniform(0.36, 0.50)
        px = bx + side * S * rng.uniform(0.01, 0.05 + spread * 0.06)
        py = by + S * rng.uniform(-0.01, 0.02)
        _draw_leaf(d, px, py, ln, wd, ang, (*col, 255), (*vn, 235), lobes, lobe_amp, ss)

    if second_branch:
        # a shorter side branch fills the upper-outer corner of the card
        sbx, sby = cx + S * 0.02, cy - S * 0.40
        sex, sey = off + S * 0.78, off + S * 0.22
        d.line([(sbx, sby), (sex, sey)], fill=(*twig_col, 255),
               width=max(2, int(S * 0.006)), joint="curve")
        for i in range(6):
            t = 0.15 + 0.78 * i / 5
            px = sbx + (sex - sbx) * t
            py = sby + (sey - sby) * t
            ang = (0.9 if i % 2 else -0.9) + rng.uniform(-0.20, 0.20)
            ln = S * rng.uniform(0.14, 0.20)
            col = _vary(palette[rng.integers(0, len(palette))], rng, 10)
            vn = _vary(veins[rng.integers(0, len(veins))], rng, 8)
            _draw_leaf(d, px, py, ln, ln * rng.uniform(0.36, 0.48), ang,
                       (*col, 255), (*vn, 235), lobes, lobe_amp, ss)
    return _finish_cell(img, size)


def make_leaves_broadleaf(size=232):
    palette = [(83, 124, 52), (95, 138, 58), (74, 112, 47), (108, 148, 66)]
    veins = [(52, 82, 36), (137, 170, 92)]
    return [_leaf_cluster_cell(size, palette, veins, SEED + 201 + k, leaves=17,
                               lobes=5, lobe_amp=0.30) for k in range(4)]


def make_leaves_amber(size=232):
    palette = [(204, 141, 43), (222, 166, 61), (186, 116, 35), (232, 187, 84),
               (166, 92, 30)]
    veins = [(124, 74, 24), (244, 208, 122)]
    return [_leaf_cluster_cell(size, palette, veins, SEED + 211 + k, leaves=16,
                              lobes=5, lobe_amp=0.28) for k in range(4)]


def _birch_cell(size, seed):
    ss = 4
    img = _new_cell(size, ss)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    S0 = size * ss
    S = S0 * 0.92
    off = S0 * 0.04
    palette = [(127, 168, 76), (142, 182, 86), (112, 152, 66), (154, 192, 100)]
    veins = [(81, 112, 48), (196, 216, 148)]
    for b in range(2):
        bx = off + S * (0.32 + 0.34 * b)
        pts = [(bx + math.sin(t * 3.1 + b) * S * 0.06, off + S * 0.95 - S * 0.78 * t)
               for t in np.linspace(0, 1, 7)]
        d.line([(x, y) for x, y in pts], fill=(104, 82, 61, 255),
               width=max(2, int(S * 0.004)), joint="curve")
        for i in range(11):
            t = 0.30 + 0.66 * i / 10
            px = bx + math.sin(t * 3.1 + b) * S * 0.06 + (S * 0.05 if i % 2 else -S * 0.05)
            py = off + S * 0.95 - S * 0.78 * t
            ang = (0.9 if i % 2 else -0.9) + rng.uniform(-0.2, 0.2)
            ln = S * rng.uniform(0.135, 0.185)
            col = _vary(palette[rng.integers(0, len(palette))], rng, 10)
            vn = _vary(veins[rng.integers(0, len(veins))], rng, 6)
            _draw_leaf(d, px, py, ln, ln * 0.62, ang, (*col, 255), (*vn, 220), 0, 0.0, ss)
    return _finish_cell(img, size)


def make_leaves_birch(size=232):
    return [_birch_cell(size, SEED + 221 + k) for k in range(4)]


def _pine_cell(size, seed):
    ss = 4
    img = _new_cell(size, ss)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    S = size * ss
    palette = [(56, 96, 56), (68, 112, 62), (48, 84, 48), (82, 122, 68)]
    for b in range(3):
        bx = S * (0.30 + 0.20 * b)
        by = S * (0.90 - 0.09 * b)
        tipx = bx + S * rng.uniform(0.06, 0.14)
        tipy = by - S * rng.uniform(0.26, 0.38)
        d.line([(bx, by), (tipx, tipy)], fill=(92, 70, 48, 255),
               width=max(2, int(S * 0.006)))
        for k in range(4):
            fx = bx + (tipx - bx) * (0.15 + 0.22 * k)
            fy = by + (tipy - by) * (0.15 + 0.22 * k)
            base_ang = -math.pi / 2 + rng.uniform(-0.7, 0.7)
            for i in range(22):
                ang = base_ang + (i - 7) * 0.125 + rng.uniform(-0.05, 0.05)
                ln = S * rng.uniform(0.13, 0.185)
                col = _vary(palette[rng.integers(0, len(palette))], rng, 8)
                wdt = max(1.1, S * 0.0018)
                x2 = fx + math.cos(ang) * ln
                y2 = fy + math.sin(ang) * ln
                # tapered needle
                nx, ny = -math.sin(ang), math.cos(ang)
                poly = [(fx * 1.0, fy * 1.0),
                        (x2 + nx * wdt, y2 + ny * wdt),
                        (x2, y2),
                        (x2 - nx * wdt, y2 - ny * wdt)]
                d.polygon([(x, y) for x, y in poly], fill=(*col, 255))
    return _finish_cell(img, size)


def make_needles_pine(size=232):
    return [_pine_cell(size, SEED + 231 + k) for k in range(4)]


def _grass_cell(size, seed):
    ss = 4
    img = _new_cell(size, ss)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    S = size * ss
    palette = [(150, 178, 98), (168, 194, 114), (132, 162, 86), (183, 204, 132)]
    for i in range(40):
        bx = S * rng.uniform(0.22, 0.78)
        by = S * 0.97
        hgt = S * rng.uniform(0.42, 0.82)
        lean = rng.uniform(-0.22, 0.22)
        col = _vary(palette[rng.integers(0, len(palette))], rng, 8)
        pts = []
        w = S * rng.uniform(0.010, 0.018)
        steps = 7
        for k in range(steps):
            t = k / (steps - 1)
            x = bx + lean * hgt * (t ** 1.6)
            y = by - hgt * t
            pts.append((x, y, w * (1.0 - 0.92 * t)))
        left = [(x - wd, y) for x, y, wd in pts]
        right = [(x + wd, y) for x, y, wd in reversed(pts)]
        d.polygon([(x, y) for x, y in left + right], fill=(*col, 255))
    return _finish_cell(img, size)


def make_grass_meadow(size=232):
    return [_grass_cell(size, SEED + 241 + k) for k in range(4)]


FLOWERS = [
    # stem colour, petal colour(s), centre, petals, radius
    ("daisy", (44, 96, 44), (246, 244, 232), (232, 190, 54), 12, 0.16),
    ("buttercup", (48, 100, 46), (242, 200, 54), (188, 128, 30), 5, 0.15),
    ("poppy", (54, 104, 48), (198, 54, 44), (44, 38, 34), 4, 0.17),
    ("cornflower", (58, 108, 52), (92, 122, 200), (70, 84, 150), 8, 0.15),
    ("campion", (50, 98, 46), (216, 130, 152), (236, 210, 214), 5, 0.16),
    ("yarrow", (56, 106, 50), (238, 238, 222), (222, 214, 176), 16, 0.13),
    ("marigold", (52, 102, 46), (232, 138, 42), (176, 92, 26), 14, 0.15),
    ("violet", (58, 110, 52), (146, 108, 184), (224, 200, 86), 5, 0.14),
]


def _flower_cell(size_w, size_h, spec, seed):
    ss = 4
    img = Image.new("RGBA", (size_w * ss, size_h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    W, H = size_w * ss, size_h * ss
    name, stem_c, petal_c, centre_c, npet, rad = spec
    bx = W * 0.5 + rng.uniform(-0.06, 0.06) * W
    top = H * rng.uniform(0.13, 0.20)
    lean = rng.uniform(-0.12, 0.12) * W
    stem = [(bx + lean * t * t, H * 0.99 - (H * 0.99 - top) * t)
            for t in np.linspace(0, 1, 8)]
    d.line([(x, y) for x, y in stem], fill=(*stem_c, 255), width=max(3, int(W * 0.035)),
           joint="curve")
    # two leaves
    for k, side in ((0.30, -1), (0.52, 1)):
        idx = int(k * (len(stem) - 1))
        x, y = stem[idx]
        lp = [(x, y), (x + side * W * 0.30, y - H * 0.06), (x + side * W * 0.16, y + H * 0.02)]
        d.polygon([(p[0], p[1]) for p in lp], fill=(*stem_c, 255))
    # petals
    R = min(W, H) * rad
    hx, hy = stem[-1]
    for i in range(npet):
        ang = 2.0 * math.pi * i / npet + rng.uniform(-0.06, 0.06)
        pc = _vary(petal_c, rng, 8)
        if name == "yarrow":
            ox = math.cos(ang) * R * 0.9
            oy = math.sin(ang) * R * 0.9
            d.ellipse([hx + ox - R * 0.16, hy + oy - R * 0.16,
                       hx + ox + R * 0.16, hy + oy + R * 0.16], fill=(*pc, 255))
        else:
            d.polygon(_ellipse_pts(hx + math.cos(ang) * R * 0.52,
                                   hy + math.sin(ang) * R * 0.52,
                                   R * 0.62, R * 0.28, ang, 14), fill=(*pc, 255))
    if name != "yarrow":
        d.ellipse([hx - R * 0.34, hy - R * 0.34, hx + R * 0.34, hy + R * 0.34],
                  fill=(*centre_c, 255))
    else:
        d.ellipse([hx - R * 0.22, hy - R * 0.22, hx + R * 0.22, hy + R * 0.22],
                  fill=(*centre_c, 255))
    return _finish_cell(img, (size_w, size_h))


def make_flowers(size=512):
    gutter = GUTTER
    cw = (size - gutter * 5) // 4
    chh = (size - gutter * 3) // 2
    cells = [_flower_cell(cw, chh, spec, SEED + 251 + i) for i, spec in enumerate(FLOWERS)]
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        cx = gutter + (i % 4) * (cw + gutter)
        cy = gutter + (i // 4) * (chh + gutter)
        out.paste(cell, (cx, cy))
    return out


def _fern_cell(size, seed, curve=0.0):
    ss = 4
    img = _new_cell(size, ss)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    S = size * ss
    green_dark = (66, 108, 58)
    green = (86, 132, 70)
    green_light = (112, 158, 88)
    base = (S * 0.5, S * 0.98)
    tip = (S * (0.5 + curve * 0.30), S * 0.06)
    steps = 18
    spine = []
    for k in range(steps + 1):
        t = k / steps
        x = base[0] + (tip[0] - base[0]) * t + math.sin(t * math.pi) * curve * S * 0.10
        y = base[1] + (tip[1] - base[1]) * t
        spine.append((x, y))
    d.line([(x, y) for x, y in spine], fill=(*green_dark, 255),
           width=max(2, int(S * 0.006)), joint="curve")
    for side in (-1, 1):
        for k in range(3, steps):
            t = k / steps
            x, y = spine[k]
            plen = S * 0.24 * (1.0 - 0.72 * t) * (0.75 + 0.35 * abs(math.sin(k * 1.7)))
            ang = (-0.62 if side > 0 else math.pi + 0.62) + t * 0.5 - 0.2
            col = (green if k % 2 else green_light) if side > 0 else green_dark
            col = _vary(col, rng, 8)
            poly = [(x, y),
                    (x + math.cos(ang) * plen * 0.55 - math.sin(ang) * plen * 0.14,
                     y + math.sin(ang) * plen * 0.55 + math.cos(ang) * plen * 0.14),
                    (x + math.cos(ang) * plen, y + math.sin(ang) * plen),
                    (x + math.cos(ang) * plen * 0.55 + math.sin(ang) * plen * 0.14,
                     y + math.sin(ang) * plen * 0.55 - math.cos(ang) * plen * 0.14)]
            d.polygon([(p[0], p[1]) for p in poly], fill=(*col, 255))
            # pinna midrib
            d.line([(x, y), (x + math.cos(ang) * plen * 0.94,
                             y + math.sin(ang) * plen * 0.94)],
                   fill=(*green_dark, 200), width=max(1, int(S * 0.002)))
    # second, shorter frond leaning the other way
    b2 = (S * (0.34 - curve * 0.1), S * 0.97)
    t2 = (S * (0.24 + curve * 0.22), S * 0.24)
    sp2 = [(b2[0] + (t2[0] - b2[0]) * q, b2[1] + (t2[1] - b2[1]) * q)
           for q in np.linspace(0, 1, steps + 1)]
    d.line([(x, y) for x, y in sp2], fill=(*green_dark, 255),
           width=max(2, int(S * 0.005)), joint="curve")
    for side in (-1, 1):
        for k in range(2, steps - 4):
            t = k / steps
            x, y = sp2[k]
            plen = S * 0.20 * (1.0 - 0.66 * t)
            ang = (-0.75 if side > 0 else math.pi + 0.75) + t * 0.4
            col = _vary(green if k % 2 else green_light, rng, 8)
            poly = [(x, y),
                    (x + math.cos(ang) * plen * 0.55 - math.sin(ang) * plen * 0.12,
                     y + math.sin(ang) * plen * 0.55 + math.cos(ang) * plen * 0.12),
                    (x + math.cos(ang) * plen, y + math.sin(ang) * plen),
                    (x + math.cos(ang) * plen * 0.55 + math.sin(ang) * plen * 0.12,
                     y + math.sin(ang) * plen * 0.55 - math.cos(ang) * plen * 0.12)]
            d.polygon(poly, fill=(*col, 255))
    return _finish_cell(img, size)


def make_fern(size=232):
    return [_fern_cell(size, SEED + 261 + k, curve=(-0.35, 0.25, -0.15, 0.4)[k])
            for k in range(4)]


# ---------------------------------------------------------------------------
# seamless terrain / rock / building materials
# ---------------------------------------------------------------------------


def _draw_shapes(size, ss, shape_fns):
    """Draw wrapped shapes on a transparent supersampled canvas."""
    canvas = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    step = size * ss
    for fn in shape_fns:
        for ox in (-step, 0, step):
            for oy in (-step, 0, step):
                fn(d, ox, oy)
    return canvas.resize((size, size), Image.LANCZOS)


def _overlay(rgb_arr, shapes, ss=2):
    """Composite wrapped RGBA shapes over an RGB float array."""
    size = rgb_arr.shape[0]
    base = to_image(rgb_arr, "RGB").convert("RGBA")
    return Image.alpha_composite(base, _draw_shapes(size, ss, shapes)).convert("RGB")


def make_terrain_grass(w=512, h=512):
    yy = (np.arange(h) + 0.5)[:, None] / h
    xx = (np.arange(w) + 0.5)[None, :] / w
    m1 = fbm(w, h, 7, 7, SEED + 301, octaves=5)
    m2 = fbm(w, h, 26, 26, SEED + 302, octaves=4)
    fine = fbm(w, h, 110, 110, SEED + 303, octaves=3)
    dry = smoothstep(0.58, 0.78, fbm(w, h, 4, 4, SEED + 304, octaves=3))

    base = mix(rgb(84, 118, 58), rgb(112, 148, 72), stretch(m1, 3, 97))
    base = mix(base, rgb(126, 158, 82), m2 * 0.35)
    base = mix(base, rgb(146, 152, 88), dry * 0.30)
    base *= (0.90 + 0.20 * fine)[..., None]

    # clover + tiny broad leaves for close-up interest
    rng = np.random.default_rng(SEED + 305)
    shapes = []
    for i in range(160):
        bx, by = rng.uniform(0, w), rng.uniform(0, h)
        hgt = rng.uniform(5, 18)
        lean = rng.uniform(-4, 4)
        col = _vary((70, 110, 48) if i % 3 else (126, 158, 86), rng, 12)
        wid = rng.uniform(0.7, 1.4)
        def blade(d, ox, oy, bx=bx, by=by, hgt=hgt, lean=lean, col=col, wid=wid):
            pts = [(bx + ox + lean * (t ** 1.5), by + oy - hgt * t)
                   for t in np.linspace(0, 1, 5)]
            d.line(pts, fill=(*col, 210), width=max(1, int(wid * 2)))
        shapes.append(blade)
    for i in range(45):
        bx, by = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1.6, 3.4)
        col = _vary((104, 142, 66), rng, 10)
        def clover(d, ox, oy, bx=bx, by=by, r=r, col=col):
            for k in range(3):
                a = k * 2.094
                d.ellipse([bx + ox + math.cos(a) * r - r * 0.7,
                           by + oy + math.sin(a) * r - r * 0.7,
                           bx + ox + math.cos(a) * r + r * 0.7,
                           by + oy + math.sin(a) * r + r * 0.7], fill=(*col, 190))
        shapes.append(clover)
    return _overlay(base, shapes)


def make_terrain_dirt(w=512, h=512):
    m1 = fbm(w, h, 6, 6, SEED + 311, octaves=5)
    m2 = fbm(w, h, 24, 24, SEED + 312, octaves=4)
    fine = fbm(w, h, 120, 120, SEED + 313, octaves=3)
    packed = smoothstep(0.55, 0.8, fbm(w, h, 3, 3, SEED + 314, octaves=3))

    base = mix(rgb(128, 103, 76), rgb(154, 128, 96), stretch(m1, 3, 97))
    base = mix(base, rgb(104, 84, 62), packed * 0.45)
    base = mix(base, rgb(160, 140, 108), m2 * 0.22)
    base *= (0.90 + 0.18 * fine)[..., None]

    rng = np.random.default_rng(SEED + 315)
    shapes = []
    for i in range(190):
        bx, by = rng.uniform(0, w), rng.uniform(0, h)
        rx, ry = rng.uniform(1.2, 6.0), rng.uniform(1.0, 4.5)
        ang = rng.uniform(0, math.pi)
        g = int(rng.uniform(120, 172))
        col = _vary((g, g - int(rng.uniform(2, 12)), g - int(rng.uniform(8, 22))), rng, 8)
        pts = _ellipse_pts(bx, by, rx, ry, ang, 9)
        def stone(d, ox, oy, pts=pts, col=col):
            d.polygon([(x + ox, y + oy) for x, y in pts], fill=(*col, 235))
            d.line([(x + ox, y + oy) for x, y in pts] + [(pts[0][0] + ox, pts[0][1] + oy)],
                   fill=(*[int(c * 0.55) for c in col], 200), width=1)
        shapes.append(stone)
    for i in range(26):
        bx, by = rng.uniform(0, w), rng.uniform(0, h)
        pts = [(bx, by)]
        a = rng.uniform(0, 6.28)
        for k in range(rng.integers(3, 7)):
            a += rng.uniform(-0.6, 0.6)
            bx += math.cos(a) * rng.uniform(4, 13)
            by += math.sin(a) * rng.uniform(4, 13)
            pts.append((bx, by))
        def crack(d, ox, oy, pts=pts):
            d.line([(x + ox, y + oy) for x, y in pts], fill=(84, 68, 50, 150), width=1)
        shapes.append(crack)
    return _overlay(base, shapes)


def make_terrain_rock(w=512, h=512):
    f1, f2, ids = cellular(w, h, 16, 16, SEED + 321)
    cellv = value_hash(ids, SEED + 322)
    crack = smoothstep(0.0, 3.0, f2 - f1)
    fine = fbm(w, h, 80, 80, SEED + 323, octaves=4)
    moss = smoothstep(0.60, 0.80, fbm(w, h, 5, 5, SEED + 324, octaves=3)
                      + 0.35 * (1.0 - crack))

    base = mix(rgb(104, 106, 100), rgb(140, 140, 130), cellv)
    base = mix(base, rgb(78, 80, 76), (1.0 - crack) * 0.55)
    base *= (0.88 + 0.24 * fine)[..., None]
    base = mix(base, rgb(88, 112, 68), moss * 0.55)
    base = mix(base, rgb(150, 150, 132),
               smoothstep(0.72, 0.85, fbm(w, h, 40, 40, SEED + 325, octaves=2)) * 0.25)
    return base


def make_terrain_macro(w=256, h=256):
    a = fbm(w, h, 3, 3, SEED + 331, octaves=5)
    b = fbm(w, h, 9, 9, SEED + 332, octaves=4)
    v = stretch(0.65 * a + 0.35 * b, 2, 98)
    v = 0.60 + 0.40 * v
    tint = mix(np.array((1.0, 1.0, 0.99), np.float32),
               np.array((0.98, 1.0, 0.96), np.float32), a)
    return np.clip(v[..., None] * tint, 0, 1)


def make_rock(w=512, h=512):
    f1, f2, ids = cellular(w, h, 11, 11, SEED + 341)
    cellv = value_hash(ids, SEED + 342)
    seam = f2 - f1
    crack = smoothstep(0.0, 3.5, seam)
    grain = fbm(w, h, 120, 120, SEED + 343, octaves=4)
    blotch = fbm(w, h, 8, 8, SEED + 344, octaves=4)
    cavity = smoothstep(0.15, 0.55, seam)

    base = mix(rgb(112, 114, 108), rgb(150, 149, 138), cellv)
    base = mix(base, rgb(88, 90, 86), (1.0 - crack) * 0.65)
    base *= (0.86 + 0.26 * grain)[..., None]
    base = mix(base, rgb(96, 100, 88), smoothstep(0.55, 0.8, blotch) * 0.35)

    moss = smoothstep(0.52, 0.78, fbm(w, h, 6, 6, SEED + 345, octaves=4)
                      + 0.45 * (1.0 - cavity))
    base = mix(base, rgb(84, 108, 62), moss * 0.72)
    lichen = smoothstep(0.66, 0.80, fbm(w, h, 34, 34, SEED + 346, octaves=3))
    base = mix(base, rgb(168, 170, 146), lichen * 0.35)

    height = 0.55 + 0.20 * grain - 0.45 * (1.0 - crack) + 0.10 * cellv - 0.05
    norm = normal_from_height(height, 5.0)
    return to_image(np.clip(base, 0, 1), "RGB"), to_image(norm, "RGB")


def make_water_normal(w=512, h=512):
    X = (np.arange(w, dtype=np.float32) + 0.5)[None, :]
    Y = (np.arange(h, dtype=np.float32) + 0.5)[:, None]
    rng = np.random.default_rng(SEED + 351)
    height = np.zeros((h, w), np.float32)
    gx = np.zeros((h, w), np.float32)
    gy = np.zeros((h, w), np.float32)
    waves = [(3, 1, 1.00), (1, 2, 0.70), (5, 3, 0.45), (-4, 2, 0.52),
             (2, -5, 0.33), (7, 4, 0.22), (-3, 7, 0.18)]
    for kx, ky, amp in waves:
        ph = rng.uniform(0, 2 * math.pi)
        arg = 2 * math.pi * (kx * X / w + ky * Y / h) + ph
        height += amp * np.sin(arg)
        gx += amp * np.cos(arg) * (2 * math.pi * kx / w)
        gy += amp * np.cos(arg) * (2 * math.pi * ky / h)
    rip = fbm(w, h, 18, 18, SEED + 352, octaves=4) - 0.5
    height += 0.35 * rip
    strength = 26.0
    nx = -gx * strength
    ny = gy * strength
    nz = np.ones_like(height)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.empty((h, w, 3), np.float32)
    out[..., 0] = nx * inv * 0.5 + 0.5
    out[..., 1] = ny * inv * 0.5 + 0.5
    out[..., 2] = nz * inv * 0.5 + 0.5
    return to_image(out, "RGB")


def _hash_table(seed, n=64):
    return np.random.default_rng(seed).random(n, dtype=np.float32)


def make_wood_planks(w=256, h=256):
    X = np.arange(w, dtype=np.float32)[None, :]
    Y = (np.arange(h, dtype=np.float32) + 0.5)[:, None]
    plank_h = 64.0
    rows = 4
    row = (Y // plank_h).astype(np.int32) % rows
    ly = np.mod(Y, plank_h)
    tone = _hash_table(SEED + 361, rows)
    rng = np.random.default_rng(SEED + 362)
    joint = (rng.random(rows) * w).astype(np.float32)

    grain = fbm(w, h, 5, 120, SEED + 363, octaves=4)
    grain2 = fbm(w, h, 2, 26, SEED + 364, octaves=3)
    fine = fbm(w, h, 90, 90, SEED + 365, octaves=2)

    jx = (X - joint[row]) % w
    jx2 = (X - (joint[row] + w * 0.5)) % w
    joints = np.minimum(jx, w - jx)
    joints = np.minimum(joints, np.minimum(jx2, w - jx2))
    joint_mask = 1.0 - smoothstep(0.6, 2.2, joints)
    # symmetric about each plank boundary, so the wrap joins like any other
    ed = np.minimum(ly, plank_h - ly)
    gap = 1.0 - smoothstep(0.0, 2.2, ed)

    # blend the previous plank's tone in across the joint so the row boundary
    # (including the texture wrap) is continuous under the dark gap
    tone_prev = tone[(row - 1) % rows]
    tb = smoothstep(0.0, 7.0, ly)
    tone_mix = tone_prev + (tone[row] - tone_prev) * tb
    base = mix(rgb(138, 103, 68), rgb(170, 132, 88), tone_mix)
    base = mix(base, rgb(112, 82, 54), 0.30 + 0.25 * grain2)
    base *= (0.84 + 0.30 * grain + 0.06 * (fine - 0.5))[..., None]
    # gentle barrel bevel, periodic in the plank height
    base *= (0.94 + 0.08 * np.sin(math.pi * ly / plank_h))[..., None]
    base = mix(base, rgb(52, 38, 26), np.clip(joint_mask * 0.85 + gap * 0.95, 0, 1))
    base *= (0.97 + 0.05 * (fine - 0.5))[..., None]
    return base


def make_timber(w=256, h=256):
    X = np.arange(w, dtype=np.float32)[None, :]
    Y = np.arange(h, dtype=np.float32)[:, None]
    grain = fbm(w, h, 120, 6, SEED + 371, octaves=5)
    crack = smoothstep(0.60, 0.42, fbm(w, h, 40, 5, SEED + 372, octaves=4))
    fine = fbm(w, h, 90, 60, SEED + 373, octaves=3)
    knot = fbm(w, h, 8, 8, SEED + 374, octaves=3)

    base = mix(rgb(72, 54, 38), rgb(104, 80, 56), stretch(grain, 3, 97))
    base = mix(base, rgb(44, 32, 22), crack * 0.55)
    base *= (0.90 + 0.18 * fine)[..., None]
    base = mix(base, rgb(88, 66, 46), smoothstep(0.62, 0.8, knot) * 0.25)

    # iron studs / pegs
    for cx, cy in ((40, 40), (168, 120), (86, 210), (222, 236)):
        dx = np.abs(X - cx)
        dx = np.minimum(dx, w - dx)
        dy = np.abs(Y - cy)
        dy = np.minimum(dy, h - dy)
        d = np.sqrt(dx * dx + dy * dy)
        stud = 1.0 - smoothstep(2.6, 4.0, d)
        rim = smoothstep(1.2, 1.8, d) * (1.0 - smoothstep(2.2, 3.4, d))
        base = mix(base, rgb(58, 56, 52), stud * 0.9)
        base = mix(base, rgb(96, 92, 84), rim * 0.6)
    return base


def make_plaster(w=256, h=256):
    patch = fbm(w, h, 4, 4, SEED + 381, octaves=4)
    fine = fbm(w, h, 130, 130, SEED + 382, octaves=3)
    crack = smoothstep(0.60, 0.45, fbm(w, h, 18, 18, SEED + 383, octaves=4, ridge=True))

    base = mix(rgb(210, 200, 180), rgb(234, 226, 208), stretch(patch, 3, 97))
    base = mix(base, rgb(188, 176, 154), smoothstep(0.62, 0.85, patch) * 0.35)
    base *= (0.94 + 0.10 * fine)[..., None]
    base = mix(base, rgb(150, 138, 120), crack * 0.30)
    # aggregate speckles
    speck = smoothstep(0.80, 0.86, fbm(w, h, 200, 200, SEED + 384, octaves=2))
    base = mix(base, rgb(166, 156, 138), speck * 0.35)
    return base


def make_roof_shingles(w=256, h=256):
    X = (np.arange(w, dtype=np.float32) + 0.5)[None, :]
    Y = (np.arange(h, dtype=np.float32) + 0.5)[:, None]
    row_h = 32.0
    rows = 8
    row = (Y // row_h).astype(np.int32) % rows
    ly = np.mod(Y, row_h)
    offs = (row % 2) * 25.6
    sh_w = 51.2
    lx = np.mod(X + offs, sh_w)
    sidx = (np.floor((X + offs) / sh_w).astype(np.int32) % 5)
    tone = np.random.default_rng(SEED + 391).random((rows, 5), dtype=np.float32)

    grain = fbm(w, h, 12, 90, SEED + 392, octaves=4)
    fine = fbm(w, h, 100, 90, SEED + 393, octaves=3)
    moss = smoothstep(0.62, 0.82, fbm(w, h, 6, 12, SEED + 394, octaves=3))

    tone_cur = tone[row, sidx]
    tone_prev = tone[(row - 1) % rows, sidx]
    tb = smoothstep(0.0, 7.0, ly)
    tone_mix = tone_prev + (tone_cur - tone_prev) * tb
    base = mix(rgb(124, 104, 82), rgb(156, 134, 106), tone_mix)
    base *= (0.84 + 0.28 * grain)[..., None]
    seams = 1.0 - smoothstep(0.8, 2.2, lx) * smoothstep(0.8, 2.2, sh_w - lx)
    # shadow under the overlapping row, symmetric about every row boundary
    underlap = np.exp(-((np.minimum(ly, row_h - ly) / 4.0) ** 2))
    base = mix(base, rgb(54, 44, 34), np.clip(seams * 0.72 + underlap * 0.38, 0, 1))
    base = mix(base, rgb(100, 108, 80), moss * 0.32)
    base *= (0.94 + 0.10 * (fine - 0.5))[..., None]
    return base


def make_stone_blocks(w=256, h=256):
    X = (np.arange(w, dtype=np.float32) + 0.5)[None, :]
    Y = (np.arange(h, dtype=np.float32) + 0.5)[:, None]
    rows = 6.0
    row_h = h / rows
    row = np.clip((Y // row_h).astype(np.int32), 0, 5)
    ly = np.mod(Y, row_h)
    offs = (row % 2) * 32.0
    bw = 64.0
    lx = np.mod(X + offs, bw)
    bidx = (np.floor((X + offs) / bw).astype(np.int32) % 4)
    tone = np.random.default_rng(SEED + 401).random((6, 4), dtype=np.float32)

    grain = fbm(w, h, 40, 40, SEED + 402, octaves=4)
    fine = fbm(w, h, 140, 140, SEED + 403, octaves=3)
    pits = smoothstep(0.72, 0.82, fbm(w, h, 90, 90, SEED + 404, octaves=2))

    mortar = np.clip((1.0 - smoothstep(0.8, 2.6, np.minimum(lx, bw - lx)))
                     + (1.0 - smoothstep(0.8, 2.6, np.minimum(ly, row_h - ly))), 0, 1)
    base = mix(rgb(132, 128, 116), rgb(168, 163, 148), tone[row, bidx])
    base *= (0.88 + 0.22 * grain)[..., None]
    base = mix(base, rgb(92, 90, 84), mortar * 0.9)
    base = mix(base, rgb(112, 112, 100), pits * 0.30)
    base *= (0.94 + 0.10 * (fine - 0.5))[..., None]
    return base


# ---------------------------------------------------------------------------
# inspection helpers
# ---------------------------------------------------------------------------

_ASCII = " .:-=+*#%@"


def ascii_preview(img, width=110, aspect=0.48, title="", gamma=1.0):
    """Print a luminance ASCII preview (no image viewer in this session)."""
    g = img.convert("L")
    h = max(1, int(width * (g.height / g.width) * aspect))
    a = np.asarray(g.resize((width, h), Image.LANCZOS), np.float32) / 255.0
    if gamma != 1.0:
        a = a ** gamma
    idx = np.clip((a * (len(_ASCII) - 1) + 0.5).astype(int), 0, len(_ASCII) - 1)
    print(f"--- {title} ({width}x{h}) ---")
    for row in idx:
        print("".join(_ASCII[i] for i in row))
    print()


# ---------------------------------------------------------------------------
# asset catalogue
# ---------------------------------------------------------------------------

BARK_IDS = ("bark_oak", "bark_pine", "bark_birch", "bark_dead")
ATLAS_LAYOUT = {
    "leaves_broadleaf": (2, 2), "leaves_amber": (2, 2),
    "leaves_birch": (2, 2), "needles_pine": (2, 2),
    "grass_meadow": (2, 2), "fern": (2, 2), "flowers": (4, 2),
}

ASSETS = [
    dict(id="sky_frontier", file="sky_frontier.png", size=(4096, 2048),
         channels=3, tiling="u", n_version=None, kind="sky",
         description="Painterly midday equirectangular sky: deep blue zenith, layered "
                     "cumulus with sun-side rims, high cirrus, thin warm haze, hazy "
                     "ridges, dither; seamless at u."),
    dict(id="bark_oak", file="bark_oak.png", size=(256, 512), channels=3,
         tiling="both", n_version="bark_oak_n.png", kind="bark",
         description="Warm grey-brown oak bark with deep vertical fissures and knots."),
    dict(id="bark_pine", file="bark_pine.png", size=(256, 512), channels=3,
         tiling="both", n_version="bark_pine_n.png", kind="bark",
         description="Reddish-brown pine bark in flaking plates with dark grooves."),
    dict(id="bark_birch", file="bark_birch.png", size=(256, 512), channels=3,
         tiling="both", n_version="bark_birch_n.png", kind="bark",
         description="Off-white birch bark, horizontal dark scars, sparse lenticels."),
    dict(id="bark_dead", file="bark_dead.png", size=(256, 512), channels=3,
         tiling="both", n_version="bark_dead_n.png", kind="bark",
         description="Pale weathered dead-wood bark, cracked grey splits."),
    dict(id="leaves_broadleaf", file="leaves_broadleaf.png", size=(512, 512),
         channels=4, tiling="atlas", n_version=None, kind="foliage",
         description="2x2 oak/broadleaf cluster cards (green), flat mid-tone, vein detail."),
    dict(id="leaves_amber", file="leaves_amber.png", size=(512, 512), channels=4,
         tiling="atlas", n_version=None, kind="foliage",
         description="2x2 autumn rowan cluster cards in gold and orange."),
    dict(id="leaves_birch", file="leaves_birch.png", size=(512, 512), channels=4,
         tiling="atlas", n_version=None, kind="foliage",
         description="2x2 silver-birch twig cards with small light-green leaves."),
    dict(id="needles_pine", file="needles_pine.png", size=(512, 512), channels=4,
         tiling="atlas", n_version=None, kind="foliage",
         description="2x2 pine needle fan sprigs on short branches."),
    dict(id="grass_meadow", file="grass_meadow.png", size=(512, 512), channels=4,
         tiling="atlas", n_version=None, kind="groundcover",
         description="2x2 pale-green upright grass tufts (tint friendly)."),
    dict(id="flowers", file="flowers.png", size=(512, 512), channels=4,
         tiling="atlas", n_version=None, kind="groundcover",
         description="4x2 wildflower cards: daisy, buttercup, poppy, cornflower, "
                     "campion, yarrow, marigold, violet."),
    dict(id="fern", file="fern.png", size=(512, 512), channels=4,
         tiling="atlas", n_version=None, kind="groundcover",
         description="2x2 fern fronds with serrated pinnae."),
    dict(id="terrain_grass", file="terrain_grass.png", size=(512, 512),
         channels=3, tiling="both", n_version=None, kind="terrain",
         description="Fine meadow grass and clover detail for the terrain shader."),
    dict(id="terrain_dirt", file="terrain_dirt.png", size=(512, 512), channels=3,
         tiling="both", n_version=None, kind="terrain",
         description="Packed trail dirt with small stones and cracks."),
    dict(id="terrain_rock", file="terrain_rock.png", size=(512, 512), channels=3,
         tiling="both", n_version=None, kind="terrain",
         description="Scree and fractured rock face with moss patches."),
    dict(id="terrain_macro", file="terrain_macro.png", size=(256, 256),
         channels=3, tiling="both", n_version=None, kind="terrain",
         description="Low-frequency grey-green mottling for macro terrain variation."),
    dict(id="rock", file="rock.png", size=(512, 512), channels=3, tiling="both",
         n_version="rock_n.png", kind="prop",
         description="Seamless granite boulder surface with moss and lichen."),
    dict(id="wood_planks", file="wood_planks.png", size=(256, 256), channels=3,
         tiling="both", n_version=None, kind="building",
         description="Warm horizontal timber planks with staggered butt joints."),
    dict(id="timber", file="timber.png", size=(256, 256), channels=3,
         tiling="both", n_version=None, kind="building",
         description="Dark aged structural timber with cracks and iron pegs."),
    dict(id="plaster", file="plaster.png", size=(256, 256), channels=3,
         tiling="both", n_version=None, kind="building",
         description="Warm lime plaster with patchy tone, hairline cracks and grit."),
    dict(id="roof_shingles", file="roof_shingles.png", size=(256, 256), channels=3,
         tiling="both", n_version=None, kind="building",
         description="Weathered wooden roof shingles in staggered rows with moss."),
    dict(id="stone_blocks", file="stone_blocks.png", size=(256, 256), channels=3,
         tiling="both", n_version=None, kind="building",
         description="Ashlar stone block coursing with mortar joints and pits."),
    dict(id="water_normal", file="water_normal.png", size=(512, 512), channels=3,
         tiling="both", n_version=None, kind="effect",
         description="Tileable animated ripple normal map (OpenGL +Y up)."),
]

NORMALS = {
    "bark_oak_n.png": ("bark_oak", 6.0), "bark_pine_n.png": ("bark_pine", 5.0),
    "bark_birch_n.png": ("bark_birch", 3.0), "bark_dead_n.png": ("bark_dead", 5.0),
    "rock_n.png": ("rock", 5.0),
}

LICENSE_TEXT = """IRONWOOD WORLD TEXTURES - LICENSE AND PROVENANCE

Every texture under this directory (assets/world/textures/) is original,
procedurally generated work authored for this repository. No third-party
source imagery, scans, photo textures or paid packs were used or downloaded.

Authoring source: tools/world_textures.py (deterministic Python, numpy and
Pillow only). Running the tool regenerates every PNG in this directory
byte-identically. Colour maps are authored in display (sRGB) space; normal
maps are derived from authored height fields in the OpenGL convention
(+Y up, green = up) and carry no baked directional light.

Generated content: sky panorama, bark albedo + normals, foliage/ground-cover
alpha atlases, terrain detail and macro variation, rock and water normals,
and building materials (planks, timber, plaster, shingles, stone).

The textures are distributed under CC0 1.0 Universal (Public Domain
Dedication), the same dedication used by the character assets in this
repository:
https://creativecommons.org/publicdomain/zero/1.0/

No attribution is required by CC0; this file records provenance.
"""


# ---------------------------------------------------------------------------
# validation / reporting
# ---------------------------------------------------------------------------


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _as_uint8(img):
    if img.mode == "RGBA":
        return np.asarray(img)[..., :3].astype(np.int16)
    return np.asarray(img.convert("RGB")).astype(np.int16)


def seam_metrics(arr, axes="both"):
    """Wrap-edge deltas compared with the interior delta distribution.

    Cellular / plank textures contain legitimate sharp lines, so the interior
    *mean* is too strict a reference; the 95th percentile of adjacent
    row/column deltas describes the same kind of edge the wrap joins.
    """
    a = arr.astype(np.int16)
    out = {}
    if axes in ("both", "x"):
        dx = np.abs(a[:, 1:] - a[:, :-1]).mean(axis=2).ravel()
        out["x_edge"] = float(np.abs(a[:, 0] - a[:, -1]).mean())
        out["x_inner"] = float(dx.mean())
        out["x_p95"] = float(np.percentile(dx, 95))
    if axes in ("both", "y"):
        dy = np.abs(a[1:] - a[:-1]).mean(axis=2).ravel()
        out["y_edge"] = float(np.abs(a[0] - a[-1]).mean())
        out["y_inner"] = float(dy.mean())
        out["y_p95"] = float(np.percentile(dy, 95))
    return out


def gutter_alpha(img, cols, rows, gutter=GUTTER):
    a = np.asarray(img)[..., 3]
    size = img.width
    cw = (size - gutter * (cols + 1)) // cols
    ch = (size - gutter * (rows + 1)) // rows
    worst = 0
    for i in range(cols + 1):
        x = i * (cw + gutter)
        if x + gutter <= size:
            worst = max(worst, int(a[:, x:x + gutter].max()))
    for j in range(rows + 1):
        y = j * (ch + gutter)
        if y + gutter <= size:
            worst = max(worst, int(a[y:y + gutter, :].max()))
    return worst


def cell_edge_alpha(img, cols, rows, gutter=GUTTER, pad=2):
    """Max alpha within ``pad`` px of each cell border (0 = nothing clipped)."""
    a = np.asarray(img)[..., 3]
    size = img.width
    cw = (size - gutter * (cols + 1)) // cols
    ch = (size - gutter * (rows + 1)) // rows
    worst = 0
    for i in range(cols * rows):
        x = gutter + (i % cols) * (cw + gutter)
        y = gutter + (i // cols) * (ch + gutter)
        cell = a[y:y + ch, x:x + cw]
        worst = max(worst, int(cell[:pad].max()), int(cell[-pad:].max()),
                    int(cell[:, :pad].max()), int(cell[:, -pad:].max()))
    return worst


def normal_stats(img):
    a = np.asarray(img, np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    nz = b / 255.0 * 2.0 - 1.0
    return dict(mean_r=float(r.mean()), mean_g=float(g.mean()),
                mean_b=float(b.mean()), min_z=float(nz.min()),
                mean_abs_x=float(np.abs(r - 128.0).mean()),
                mean_abs_y=float(np.abs(g - 128.0).mean()))


def _self_test_normals():
    """Dome bump: left flank must point -X and the top flank +Y (green up)."""
    y, x = np.mgrid[0:64, 0:64].astype(np.float32)
    d = np.sqrt((x - 31.5) ** 2 + (y - 31.5) ** 2)
    height = np.clip(1.0 - d / 28.0, 0.0, 1.0) ** 2
    n = normal_from_height(height, 4.0)
    left = n[32, 8, 0] * 255.0
    top = n[8, 32, 1] * 255.0
    return float(left), float(top)


def sky_metrics(img):
    a = np.asarray(img, np.float32) / 255.0
    h, w, _ = a.shape
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    rows = []
    for v0, v1, name in ((0.0, 0.15, "zenith"), (0.15, 0.35, "upper sky"),
                         (0.35, 0.48, "play band"), (0.48, 0.52, "horizon haze"),
                         (0.52, 1.0, "below horizon")):
        sl = lum[int(v0 * h):int(v1 * h)]
        rows.append((name, v0, v1, float(sl.mean()), float(sl.std()),
                     float(np.percentile(sl, 95))))
    g = Image.fromarray(np.clip(lum * 255, 0, 255).astype(np.uint8))
    blur = np.asarray(g.filter(ImageFilter.GaussianBlur(2.0)), np.float32)
    hp = np.abs(lum * 255.0 - blur)
    top = hp[:int(0.55 * h)]
    sm = seam_metrics(np.asarray(img.convert("RGB")), "x")
    # sun: brightest broad region in the upper sky
    sun_az = 0.615 * 2.0 * math.pi
    sx = int(sun_az / (2.0 * math.pi) * w)
    sy = int((0.5 - math.radians(26.0) / math.pi) * h)
    return dict(bands=rows, hp50=float(np.percentile(top, 50)),
                hp90=float(np.percentile(top, 90)),
                hp99=float(np.percentile(top, 99)),
                bright_frac=float((lum > 0.90).mean()),
                seam=sm, sun_rgb=a[sy, sx], sun_lum=float(lum[sy, sx]))


# ---------------------------------------------------------------------------
# contact sheets
# ---------------------------------------------------------------------------


def _checkerboard(size, square=16):
    a = np.zeros((size, size, 3), np.uint8)
    yy, xx = np.mgrid[0:size, 0:size]
    a[...] = np.where(((xx // square) + (yy // square)) % 2, 196, 232)[..., None]
    return Image.fromarray(a, "RGB")


def _label(draw, xy, text):
    draw.text(xy, text, fill=(24, 24, 24))


def sheet_tiling(tex_dir, ids, path):
    from PIL import ImageFont
    font = ImageFont.load_default(size=15)
    tile = 128
    cell_w, cell_h = 256, 282
    cols = 5
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (235, 232, 224))
    d = ImageDraw.Draw(sheet)
    for i, tid in enumerate(ids):
        im = Image.open(tex_dir / f"{tid}.png").convert("RGB")
        small = im.resize((tile, tile), Image.LANCZOS)
        tileimg = Image.new("RGB", (tile * 2, tile * 2))
        for ox in range(2):
            for oy in range(2):
                tileimg.paste(small, (ox * tile, oy * tile))
        x = (i % cols) * cell_w + 12
        y = (i // cols) * cell_h + 10
        sheet.paste(tileimg, (x, y))
        d.text((x, y + 266), tid, fill=(24, 24, 24), font=font)
    sheet.save(path)


def sheet_foliage(tex_dir, ids, path):
    from PIL import ImageFont
    font = ImageFont.load_default(size=15)
    cell_w, cell_h = 276, 300
    cols = 4
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (238, 238, 234))
    d = ImageDraw.Draw(sheet)
    for i, tid in enumerate(ids):
        im = Image.open(tex_dir / f"{tid}.png").convert("RGBA")
        cells = ATLAS_LAYOUT[tid]
        bg = _checkerboard(256)
        bg.paste(im.resize((256, 256), Image.LANCZOS), (0, 0),
                 im.resize((256, 256), Image.LANCZOS))
        x = (i % cols) * cell_w + 10
        y = (i // cols) * cell_h + 10
        sheet.paste(bg, (x, y))
        # mark cell bounds (1 px) so the transparent gutters are visible
        g = GUTTER * 256 // im.width
        cw = (256 - g * (cells[0] + 1)) // cells[0]
        ch = (256 - g * (cells[1] + 1)) // cells[1]
        for cx in range(cells[0]):
            for cy in range(cells[1]):
                x0 = x + g + cx * (cw + g)
                y0 = y + g + cy * (ch + g)
                d.rectangle([x0, y0, x0 + cw, y0 + ch], outline=(120, 120, 140))
        d.text((x, y + 266), f"{tid}  {cells[0]}x{cells[1]}", fill=(24, 24, 24), font=font)
    sheet.save(path)


def sheet_sky_seam(sky, path):
    w, h = sky.size
    strip = Image.new("RGB", (512, 512))
    left = sky.crop((w - 256, int(h * 0.24), w, int(h * 0.24) + 512))
    right = sky.crop((0, int(h * 0.24), 256, int(h * 0.24) + 512))
    strip.paste(left, (0, 0))
    strip.paste(right, (256, 0))
    thumb = sky.resize((1024, 512), Image.LANCZOS)
    sheet = Image.new("RGB", (1024, 1024), (20, 22, 26))
    sheet.paste(strip, (256, 24))
    sheet.paste(thumb, (0, 512))
    d = ImageDraw.Draw(sheet)
    d.text((262, 4), "u seam at x=256 (full resolution, wrapped raw/paste)",
           fill=(240, 240, 230))
    d.text((8, 496), "equirectangular thumbnail 1024x512", fill=(240, 240, 230))
    sheet.save(path)


# ---------------------------------------------------------------------------
# build / CLI
# ---------------------------------------------------------------------------


def _want(only, tid):
    return not only or tid in only


def build_all(only=None):
    out = {}
    if _want(only, "sky_frontier"):
        out["sky_frontier.png"] = make_sky()

    for bid in BARK_IDS:
        if _want(only, bid):
            alb, nrm = make_bark(bid)
            out[f"{bid}.png"] = alb
            out[f"{bid}_n.png"] = nrm

    if _want(only, "leaves_broadleaf"):
        out["leaves_broadleaf.png"] = compose_atlas(make_leaves_broadleaf(), 2, 2)[0]
    if _want(only, "leaves_amber"):
        out["leaves_amber.png"] = compose_atlas(make_leaves_amber(), 2, 2)[0]
    if _want(only, "leaves_birch"):
        out["leaves_birch.png"] = compose_atlas(make_leaves_birch(), 2, 2)[0]
    if _want(only, "needles_pine"):
        out["needles_pine.png"] = compose_atlas(make_needles_pine(), 2, 2)[0]
    if _want(only, "grass_meadow"):
        out["grass_meadow.png"] = compose_atlas(make_grass_meadow(), 2, 2)[0]
    if _want(only, "fern"):
        out["fern.png"] = compose_atlas(make_fern(), 2, 2)[0]
    if _want(only, "flowers"):
        out["flowers.png"] = make_flowers()

    if _want(only, "terrain_grass"):
        out["terrain_grass.png"] = make_terrain_grass()
    if _want(only, "terrain_dirt"):
        out["terrain_dirt.png"] = make_terrain_dirt()
    if _want(only, "terrain_rock"):
        out["terrain_rock.png"] = to_image(make_terrain_rock(), "RGB")
    if _want(only, "terrain_macro"):
        out["terrain_macro.png"] = to_image(make_terrain_macro(), "RGB")
    if _want(only, "rock"):
        alb, nrm = make_rock()
        out["rock.png"] = alb
        out["rock_n.png"] = nrm
    if _want(only, "wood_planks"):
        out["wood_planks.png"] = to_image(make_wood_planks(), "RGB")
    if _want(only, "timber"):
        out["timber.png"] = to_image(make_timber(), "RGB")
    if _want(only, "plaster"):
        out["plaster.png"] = to_image(make_plaster(), "RGB")
    if _want(only, "roof_shingles"):
        out["roof_shingles.png"] = to_image(make_roof_shingles(), "RGB")
    if _want(only, "stone_blocks"):
        out["stone_blocks.png"] = to_image(make_stone_blocks(), "RGB")
    if _want(only, "water_normal"):
        out["water_normal.png"] = make_water_normal()
    return out


def write_outputs(outputs):
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    written = []
    for name, img in outputs.items():
        path = TEX_DIR / name
        img.save(path, "PNG", optimize=True)
        written.append(path)
    return written


def write_manifest():
    entries = []
    total = sum(p.stat().st_size for p in TEX_DIR.glob("*.png"))
    for spec in ASSETS:
        path = TEX_DIR / spec["file"]
        if not path.exists():
            continue
        entries.append(dict(
            id=spec["id"], file=spec["file"], size=list(spec["size"]),
            channels=spec["channels"], tiling=spec["tiling"],
            n_version=spec["n_version"], kind=spec["kind"],
            description=spec["description"]))
    manifest = dict(
        generator="tools/world_textures.py", seed=SEED,
        color_space="sRGB albedo; normal maps OpenGL +Y (green up)",
        file_count=len(list(TEX_DIR.glob("*.png"))),
        total_bytes=total, textures=entries)
    (TEX_DIR.parent / "world_textures.json").write_text(
        json.dumps(manifest, indent=1, sort_keys=False) + "\n", encoding="utf-8")


def validate_and_report(t_start):
    lines = []
    checks = []

    def add(text):
        lines.append(text)

    add("IRONWOOD WORLD TEXTURES - VALIDATION REPORT")
    add("tool: tools/world_textures.py   seed: %d" % SEED)
    add("")
    add("FILES")
    add("%-18s %-22s %-10s %8s  %s" % ("id", "file", "size", "bytes", "sha256[:16]"))
    total_bytes = 0
    loaded = {}
    for spec in ASSETS:
        for fn in [spec["file"]] + ([spec["n_version"]] if spec["n_version"] else []):
            path = TEX_DIR / fn
            if not path.exists():
                add("MISSING %s" % fn)
                checks.append(False)
                continue
            img = Image.open(path)
            img.load()
            loaded[fn] = img
            exp = spec["size"]
            ok = img.size == tuple(exp) and img.mode == (
                "RGBA" if spec["channels"] == 4 else "RGB")
            checks.append(ok)
            sz = path.stat().st_size
            if fn == spec["file"]:
                total_bytes += sz
            add("%-18s %-22s %-10s %8d  %s%s" % (
                spec["id"] if fn == spec["file"] else spec["id"] + "_n",
                fn, "%dx%d" % img.size, sz, sha256_file(path)[:16],
                "" if ok else "  <-- SIZE/MODE MISMATCH"))
    all_bytes = sum(p.stat().st_size for p in TEX_DIR.glob("*.png"))
    add("primary PNG bytes: %d (%.2f MB); all %d PNGs incl. normals: %d (%.2f MB)" % (
        total_bytes, total_bytes / 1e6, len(list(TEX_DIR.glob("*.png"))),
        all_bytes, all_bytes / 1e6))
    vram = 0.0
    for spec in ASSETS:
        for fn in [spec["file"]] + ([spec["n_version"]] if spec["n_version"] else []):
            path = TEX_DIR / fn
            if path.exists():
                im = Image.open(path)
                vram += im.size[0] * im.size[1] * len(im.getbands()) * (4.0 / 3.0)
    add("estimated GPU image memory incl. mipmaps: %.1f MB (budget 64 MB)"
        % (vram / 1e6))

    add("")
    add("TILING CONTINUITY  (mean abs 8-bit delta at wrap edge vs interior)")
    add("%-18s %-22s %-8s %-8s %-8s %-8s %s" % (
        "id", "axis", "edge", "inner", "inner95", "edge/95", "verdict"))
    for spec in ASSETS:
        if spec["tiling"] != "both":
            continue
        img = loaded[spec["file"]].convert("RGB")
        m = seam_metrics(np.asarray(img), "both")
        for ax in ("x", "y"):
            e, inn, p95 = m[ax + "_edge"], m[ax + "_inner"], m[ax + "_p95"]
            ok = e <= max(2.0, 1.25 * p95)
            checks.append(ok)
            add("%-18s %-22s %7.2f %8.2f %8.2f %8.2f %s" % (
                spec["id"], ax, e, inn, p95, e / max(p95, 1e-6),
                "PASS" if ok else "FAIL"))

    add("")
    add("ATLAS GUTTERS (16 px gutters between/around cells)")
    add("%-18s %-10s %-10s %-10s %s" % (
        "id", "layout", "gutter", "cell edge", "coverage per cell"))
    for tid, (cols, rows) in ATLAS_LAYOUT.items():
        fn = tid + ".png"
        if fn not in loaded:
            continue
        img = loaded[fn]
        ga = gutter_alpha(img, cols, rows)
        ea = cell_edge_alpha(img, cols, rows)
        cov = atlas_alpha_coverage(img, cols, rows)
        ok = ga == 0 and ea == 0 and all(0.02 <= c <= 0.75 for c in cov)
        checks.append(ok)
        add("%-18s %-10s %-10d %-10d %s %s" % (
            tid, "%dx%d" % (cols, rows), ga, ea, cov, "PASS" if ok else "FAIL"))

    add("")
    add("NORMAL MAPS (OpenGL +Y up; mean 128/128 neutral, positive z)")
    add("%-14s %-7s %-7s %-7s %-8s %-8s" % (
        "file", "meanR", "meanG", "meanB", "minZ", "mean|dx|"))
    for fn in NORMALS:
        path = TEX_DIR / fn
        if not path.exists():
            continue
        img = loaded.get(fn) or Image.open(path)
        st = normal_stats(img)
        ok = abs(st["mean_r"] - 128) < 4 and abs(st["mean_g"] - 128) < 4 and st["min_z"] > 0.2
        checks.append(ok)
        add("%-14s %-7.1f %-7.1f %-7.1f %-8.3f %-8.1f %s" % (
            fn, st["mean_r"], st["mean_g"], st["mean_b"], st["min_z"],
            st["mean_abs_x"], "PASS" if ok else "FAIL"))
    dome_left, dome_top = _self_test_normals()
    add("orientation self-test (dome): left R=%.1f (<128), top G=%.1f (>128) %s" % (
        dome_left, dome_top, "PASS" if dome_left < 128 and dome_top > 128 else "FAIL"))
    checks.append(dome_left < 128 and dome_top > 128)
    if "water_normal.png" in loaded:
        st = normal_stats(loaded["water_normal.png"])
        ok = abs(st["mean_r"] - 128) < 3 and abs(st["mean_g"] - 128) < 3 and st["mean_b"] > 180
        checks.append(ok)
        add("water_normal.png mean %.1f/%.1f/%.1f, z>0: %s" % (
            st["mean_r"], st["mean_g"], st["mean_b"], "PASS" if ok else "FAIL"))

    add("")
    if "sky_frontier.png" in loaded:
        sm = sky_metrics(loaded["sky_frontier.png"])
        add("SKY (4096x2048 equirectangular)")
        for name, v0, v1, mean, std, p95 in sm["bands"]:
            add("  v %.2f-%.2f %-14s luma %.3f  std %.3f  p95 %.3f"
                % (v0, v1, name, mean, std, p95))
        add("  u seam edge %.3f vs interior %.3f LSB" % (
            sm["seam"]["x_edge"], sm["seam"]["x_inner"]))
        add("  high-pass p50 %.2f  p90 %.2f  p99 %.2f (8-bit, top 55%%)"
            % (sm["hp50"], sm["hp90"], sm["hp99"]))
        add("  brightest pixels >0.90 luma: %.2f%% ; sun sample rgb %s" % (
            100.0 * sm["bright_frac"], np.round(sm["sun_rgb"] * 255).astype(int)))
        ok = (sm["seam"]["x_edge"] <= 2.0 and
              sm["bands"][2][3] < 0.78 and sm["bands"][2][4] > 0.045)
        checks.append(ok)
        add("  sky structure check: %s" % ("PASS" if ok else "REVIEW"))

    add("")
    add("NOTE: textures were inspected with numeric/ASCII diagnostics only in this")
    add("session (raster images could not be displayed to the authoring agent).")
    add("Contact sheets for human review: .runtime/world-art/texture_sheet.png,")
    add("foliage_sheet.png, sky_seam.png, sky_thumb.png")
    add("")
    result = "PASS" if all(checks) else "FAIL"
    add("RESULT: %s  (%d checks, %d failed)" % (result, len(checks), checks.count(False)))
    report = "\n".join(lines) + "\n"
    (SCRATCH / "texture_report.txt").write_text(report, encoding="utf-8")
    return report, result


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", default="", help="comma separated texture ids")
    ap.add_argument("--no-sheets", action="store_true")
    ap.add_argument("--stats", action="store_true", help="ASCII sky preview + metrics")
    args = ap.parse_args(argv)

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    only = [x.strip() for x in args.only.split(",") if x.strip()]

    t0 = time.time()
    outputs = build_all(only)
    write_outputs(outputs)
    print("wrote %d PNG files in %.1fs" % (len(outputs), time.time() - t0))

    if not only:
        (ROOT / "assets" / "world" / "LICENSE.txt").write_text(
            LICENSE_TEXT, encoding="utf-8")
        write_manifest()

    if args.stats and "sky_frontier.png" in outputs:
        ascii_preview(outputs["sky_frontier.png"], 118, 0.46, "sky equirect luminance")

    if not only:
        report, result = validate_and_report(t0)
        print(report)
        if not args.no_sheets:
            ids = [s["id"] for s in ASSETS if s["tiling"] == "both"]
            sheet_tiling(TEX_DIR, ids, SCRATCH / "texture_sheet.png")
            sheet_foliage(TEX_DIR, list(ATLAS_LAYOUT), SCRATCH / "foliage_sheet.png")
            sky = Image.open(TEX_DIR / "sky_frontier.png")
            sheet_sky_seam(sky, SCRATCH / "sky_seam.png")
            sky.resize((1024, 512), Image.LANCZOS).save(SCRATCH / "sky_thumb.png")
            print("contact sheets: .runtime/world-art/")
    print("total %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
