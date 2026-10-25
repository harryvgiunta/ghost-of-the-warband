"""Procedural surface fields for the Unholy Forest mobset.

``sample`` maps rest-space surface points to the four channels the Blender
stage bakes into a material: albedo (display/sRGB), height, roughness and
emission.  It is pure numpy and a pure function of *each point plus the fixed
arguments* -- no global state, no array statistics -- so the caller may chunk
a mesh into any number of UV islands and still get identical texels.  Detail
frequencies are expressed in cycles per metre of the rest-space point, so
rasterising an atlas at ~1 mm per texel resolves the same features the
preview renders show.

The noise machinery is a hashed 3D value-noise lattice (smooth fBm, ridged
fBm, cell domes) driven by a 16-bit random table seeded from
``forest_styles.SEED``.  Everything is vectorised and evaluated in float32
chunks of ``_CHUNK`` points; a 4.2 M point array takes a few seconds and a
single point costs the same code path.

Run ``python tools/forest_surface.py`` from the repository root to validate
the contract and render the preview slabs into
``.runtime/forest-source/previews``.
"""

from __future__ import annotations

import math
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

import forest_styles as _styles  # noqa: E402

#: The seven materials, in the order ``forest_styles`` declares them.
SURFACES: tuple[str, ...] = tuple(_styles.SURFACES)

PREVIEW_ROOT = _styles.SOURCE_ROOT / "previews"

# ---------------------------------------------------------------------------
# noise primitives
#
# A hash lattice gives value noise without storing a 3D field: cell corners
# hash to a 16-bit index into a random table.  All arithmetic is integer
# (int64 masked to 32 bits) so the result is bit-identical on every platform.

_GOLDEN = 0.6180339887498949
_TAB_BITS = 16
_TAB_MASK = (1 << _TAB_BITS) - 1
_MUL = (0x27D4EB2D, 0x165667B1, 0x1B873593)
_MUL2 = 0x2545F491
_CHUNK = 1 << 18

_LIGHT_KEY = np.array((-0.44, -0.58, 0.69), np.float32)
_LIGHT_KEY /= np.linalg.norm(_LIGHT_KEY)
_LIGHT_FILL = np.array((0.62, 0.46, 0.18), np.float32)
_LIGHT_FILL /= np.linalg.norm(_LIGHT_FILL)


def _table(seed: int) -> np.ndarray:
    """Deterministic white-noise LUT shared by every field of one call."""
    rng = np.random.default_rng(int(seed) & 0xFFFFFFFF)
    return rng.random(1 << _TAB_BITS, dtype=np.float32)


def _phase(salt: int) -> tuple[float, float, float]:
    """Three incommensurate lattice offsets so fields never share a lattice."""
    s = int(salt) & 0xFFFFFFFF
    return (
        ((s % 4093) * _GOLDEN) % 1.0,
        (((s >> 7) % 4093) * _GOLDEN) % 1.0,
        (((s >> 3) % 4093) * _GOLDEN) % 1.0,
    )


def _axis_hash(v: np.ndarray, k: int, salt: int) -> np.ndarray:
    """32-bit integer hash of one lattice axis coordinate."""
    h = (v * _MUL[k]) & 0xFFFFFFFF
    h = h ^ (h >> 15)
    h = (h * _MUL2) & 0xFFFFFFFF
    h = h ^ (h >> 13)
    return h ^ (int(salt) & 0xFFFFFFFF)


def _smooth(t: np.ndarray) -> np.ndarray:
    return t * t * (3.0 - 2.0 * t)


def _smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    span = edge1 - edge0
    if span == 0.0:
        span = 1e-6
    t = np.clip((x - edge0) / span, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _value3(p: np.ndarray, freq, salt: int, tab: np.ndarray) -> np.ndarray:
    """Trilinear value noise, ``freq`` in cycles per metre per world axis."""
    fx, fy, fz = freq
    ox, oy, oz = _phase(salt)
    qx = p[:, 0] * fx + ox
    qy = p[:, 1] * fy + oy
    qz = p[:, 2] * fz + oz

    ix0 = np.floor(qx)
    iy0 = np.floor(qy)
    iz0 = np.floor(qz)
    tx = _smooth(qx - ix0)
    ty = _smooth(qy - iy0)
    tz = _smooth(qz - iz0)

    ix = ix0.astype(np.int64)
    iy = iy0.astype(np.int64)
    iz = iz0.astype(np.int64)
    hx0 = _axis_hash(ix, 0, salt)
    hx1 = _axis_hash(ix + 1, 0, salt)
    hy0 = _axis_hash(iy, 1, salt)
    hy1 = _axis_hash(iy + 1, 1, salt)
    hz0 = _axis_hash(iz, 2, salt)
    hz1 = _axis_hash(iz + 1, 2, salt)

    m = _TAB_MASK
    a000 = tab[(hx0 ^ hy0 ^ hz0) & m]
    a100 = tab[(hx1 ^ hy0 ^ hz0) & m]
    a010 = tab[(hx0 ^ hy1 ^ hz0) & m]
    a110 = tab[(hx1 ^ hy1 ^ hz0) & m]
    a001 = tab[(hx0 ^ hy0 ^ hz1) & m]
    a101 = tab[(hx1 ^ hy0 ^ hz1) & m]
    a011 = tab[(hx0 ^ hy1 ^ hz1) & m]
    a111 = tab[(hx1 ^ hy1 ^ hz1) & m]

    x00 = a000 + (a100 - a000) * tx
    x01 = a001 + (a101 - a001) * tx
    x10 = a010 + (a110 - a010) * tx
    x11 = a011 + (a111 - a011) * tx
    y0 = x00 + (x10 - x00) * ty
    y1 = x01 + (x11 - x01) * ty
    return y0 + (y1 - y0) * tz


def _value2(p: np.ndarray, i: int, j: int, freq, salt: int,
            tab: np.ndarray) -> np.ndarray:
    """Bilinear value noise on the two world axes ``i`` and ``j``."""
    fi, fj = freq
    ox, oy, _ = _phase(salt)
    qi = p[:, i] * fi + ox
    qj = p[:, j] * fj + oy

    ii0 = np.floor(qi)
    ij0 = np.floor(qj)
    ti = _smooth(qi - ii0)
    tj = _smooth(qj - ij0)

    ii = ii0.astype(np.int64)
    ij = ij0.astype(np.int64)
    s = int(salt) & 0xFFFFFFFF
    hi0 = _axis_hash(ii, 0, salt)
    hi1 = _axis_hash(ii + 1, 0, salt)
    hj0 = _axis_hash(ij, 1, salt)
    hj1 = _axis_hash(ij + 1, 1, salt)

    m = _TAB_MASK
    a00 = tab[((hi0 ^ hj0) ^ s) & m]
    a10 = tab[((hi1 ^ hj0) ^ s) & m]
    a01 = tab[((hi0 ^ hj1) ^ s) & m]
    a11 = tab[((hi1 ^ hj1) ^ s) & m]
    b0 = a00 + (a10 - a00) * ti
    b1 = a01 + (a11 - a01) * ti
    return b0 + (b1 - b0) * tj


#: Non-harmonic lacunarity per octave.  A clean 2x series stacks every octave
#: on the same lattice lines, which shows up as a repeated motif; these ratios
#: (and the tiny per-axis jitter) keep the octaves unrelated.
_LACUNARITY = (1.87, 2.19, 1.71, 2.33, 1.93, 2.07)


def _fbm3(p: np.ndarray, freq, salt: int, tab: np.ndarray,
          octaves: int = 3, gain: float = 0.5) -> np.ndarray:
    """Smooth fBm of hashed value noise, mean ~0.5."""
    fx, fy, fz = float(freq[0]), float(freq[1]), float(freq[2])
    acc = None
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        n = _value3(p, (fx, fy, fz), salt + 0x51ED2701 * o, tab)
        acc = n * amp if acc is None else acc + n * amp
        norm += amp
        amp *= gain
        k = _LACUNARITY[o % len(_LACUNARITY)]
        fx *= k * 1.03
        fy *= k * 0.97
        fz *= k
    acc *= np.float32(1.0 / norm)
    return acc


def _fbm2(p: np.ndarray, i: int, j: int, freq, salt: int, tab: np.ndarray,
          octaves: int = 3, gain: float = 0.5) -> np.ndarray:
    fi, fj = float(freq[0]), float(freq[1])
    acc = None
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        n = _value2(p, i, j, (fi, fj), salt + 0x51ED2701 * o, tab)
        acc = n * amp if acc is None else acc + n * amp
        norm += amp
        amp *= gain
        k = _LACUNARITY[o % len(_LACUNARITY)]
        fi *= k * 1.03
        fj *= k * 0.97
    acc *= np.float32(1.0 / norm)
    return acc


def _blocks(p: np.ndarray, freq, salt: int,
            tab: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Axis-aligned cells with a per-cell random value.

    Returns ``(edge, cell)``: ``edge`` is 0 on a cell face and 1 in the middle
    of a cell, ``cell`` is the per-cell random in 0..1.  Domain warping of
    ``p`` is what keeps the cells from reading as a grid.
    """
    fx, fy, fz = freq
    ox, oy, oz = _phase(salt)
    qx = p[:, 0] * fx + ox
    qy = p[:, 1] * fy + oy
    qz = p[:, 2] * fz + oz

    ix0 = np.floor(qx)
    iy0 = np.floor(qy)
    iz0 = np.floor(qz)
    ux = qx - ix0
    uy = qy - iy0
    uz = qz - iz0

    ex = np.minimum(ux, 1.0 - ux)
    ey = np.minimum(uy, 1.0 - uy)
    ez = np.minimum(uz, 1.0 - uz)
    edge = np.minimum(np.minimum(ex, ey), ez) * 2.0

    h = (_axis_hash(ix0.astype(np.int64), 0, salt)
         ^ _axis_hash(iy0.astype(np.int64), 1, salt)
         ^ _axis_hash(iz0.astype(np.int64), 2, salt))
    return edge, tab[h & _TAB_MASK]


def _ridged(n: np.ndarray) -> np.ndarray:
    """Fold fBm into filigree ridges: 0 at mid-level crossings, 1 on peaks."""
    return 1.0 - np.abs(2.0 * n - 1.0)


def _dome(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """Threshold with a rounded shoulder: 0 below ``lo``, 1 at ``hi``."""
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * np.sqrt(t)


# ---------------------------------------------------------------------------
# colour helpers


def _hex_rgb(value: str) -> np.ndarray:
    v = value.lstrip("#")
    return np.array((int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)),
                    np.float32) / 255.0


def _colour(pal: dict[str, str], *keys: str) -> np.ndarray:
    """First palette entry that exists (palettes differ per mob)."""
    for key in keys:
        value = pal.get(key)
        if value:
            return _hex_rgb(value)
    return np.array((0.02, 0.02, 0.02), np.float32)


def _mixc(base, target: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Blend a constant or per-point colour toward ``target`` by ``t``."""
    t = np.clip(t, 0.0, 1.0)
    return base + (target - base) * t[..., None]


def _rough_range(surface: str) -> tuple[float, float]:
    lo, hi = _styles.SURFACES[surface]["rough"]
    return float(lo), float(hi)


# ---------------------------------------------------------------------------
# grade


def _grade_axis(grade) -> tuple[int, float, float]:
    axis, lo, hi = 2, 0.0, 1.0
    try:
        axis = int(grade[0]) % 3
        lo = float(grade[1])
        hi = float(grade[2])
    except (TypeError, IndexError, ValueError):
        pass
    if not math.isfinite(lo) or not math.isfinite(hi):
        lo, hi = 0.0, 1.0
    return axis, lo, hi


def _grade_values(p: np.ndarray, grade) -> tuple[np.ndarray, np.ndarray, int]:
    """Normalised base->tip coordinate and the raw coordinate along that axis.

    The result depends only on the point and the fixed ``grade`` bounds, never
    on the other points in the array, so chunking cannot change a texel.
    """
    axis, lo, hi = _grade_axis(grade)
    along = p[:, axis]
    span = hi - lo
    if abs(span) < 1e-9:
        g = np.full(p.shape[0], 0.5, np.float32)
    else:
        g = np.clip((along - lo) / span, 0.0, 1.0).astype(np.float32)
    return g, along, axis


# ---------------------------------------------------------------------------
# surfaces


def _bark(p, pal, seed, g, along, axis, tab):
    """Vertical furrows between overlapping plates, pale crests, lichen crust."""
    core = _colour(pal, "core", "depth")
    plate_c = _colour(pal, "plate", "core")
    ridge_c = _colour(pal, "ridge", "plate")
    growth_c = _colour(pal, "growth", "ridge")
    lichen_c = _colour(pal, "lichen", "growth")

    o1, o2 = (axis + 1) % 3, (axis + 2) % 3

    # domain warp: bend the grain around the trunk instead of extruding it
    bend = _fbm2(p, o1, o2, (2.6, 2.6), seed + 13, tab, 1) - 0.5
    bend2 = _fbm2(p, o1, o2, (9.5, 9.5), seed + 17, tab, 1) - 0.5
    a = p[:, o1]
    b = p[:, o2]
    r = np.sqrt(a * a + b * b)
    inv = 1.0 / np.maximum(r, 1e-3)
    shift = bend * 0.085 + bend2 * 0.020
    q = p.copy()
    q[:, o1] = a - b * inv * shift
    q[:, o2] = b + a * inv * shift

    # ridges run down the grain: ridged noise gives connected crests with
    # furrows between them, never a lattice of blobs
    ff = [12.0, 12.0, 12.0]
    ff[axis] = 2.4
    ridgef = _smoothstep(0.16, 0.78,
                         _ridged(_fbm3(q, tuple(ff), seed + 31, tab, 4)))
    # a finer ridge set stacks smaller ridges on the wide crests
    cf = [52.0, 52.0, 52.0]
    cf[axis] = 10.0
    furrow2 = _smoothstep(0.45, 0.92,
                          _ridged(_value3(q, tuple(cf), seed + 33, tab)))

    # plate seams are organic too: a coarse ridge field slices the crests into
    # scales and a slow field drops whole plates to their own height
    pf = [3.4, 3.4, 3.4]
    pf[axis] = 1.5
    seam = _smoothstep(0.86, 0.995,
                       _ridged(_fbm3(q, tuple(pf), seed + 23, tab, 2)))
    region = _fbm3(q, (2.2, 2.2, 2.2), seed + 29, tab, 1) - 0.5

    # growth striations and fine grain over the plate faces
    gf = [70.0, 70.0, 70.0]
    gf[axis] = 5.0
    grain = _value3(q, tuple(gf), seed + 37, tab)
    fine = _value3(q, (220.0, 220.0, 220.0), seed + 41, tab)

    # crusty lichen: granular flecks inside sparse colonies
    colony = _fbm2(p, o1, o2, (5.5, 5.5), seed + 43, tab, 2)
    fleck = _fbm3(q, (110.0, 110.0, 110.0), seed + 59, tab, 2)
    lich = _smoothstep(0.64, 0.86, fleck) * _smoothstep(0.58, 0.78, colony)

    relief = (0.56 * ridgef + 0.20 * region
              + 0.05 * (grain - 0.5) + 0.04 * (fine - 0.5)
              + 0.06 * lich
              - 0.26 * (1.0 - ridgef) - 0.14 * furrow2 - 0.16 * seam)
    height = np.clip(relief * 1.10 + 0.26, 0.0, 1.0)

    crest = _smoothstep(0.62, 0.96, ridgef)
    col = _mixc(core, plate_c, 0.85 * _smoothstep(0.30, 0.72, ridgef))
    col = _mixc(col, ridge_c, 0.80 * crest)
    col = _mixc(col, growth_c, 0.55 * crest * grain)
    col = _mixc(col, lichen_c, 0.45 * lich)
    shade = np.clip((0.82 + 0.24 * grain)
                    * (1.0 - 0.55 * (1.0 - ridgef) - 0.30 * furrow2
                       - 0.45 * seam), 0.04, 1.15)
    albedo = col * shade[..., None]

    lo, hi = _rough_range("bark")
    rt = np.clip(0.28 + 0.42 * (1.0 - ridgef) + 0.16 * lich
                 + 0.12 * furrow2 + 0.10 * (grain - 0.5), 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, None


def _cloth(p, pal, seed, g, along, axis, tab):
    """Grave cloth: plain weave at 1.2 mm, hanging folds, slubs, frayed hem."""
    deep = _colour(pal, "deep", "depth")
    weft_c = _colour(pal, "weft", "deep")
    warp_c = _colour(pal, "warp", "weft")
    sheen = _colour(pal, "sheen", "warp")
    fray_c = _colour(pal, "fray", "sheen")

    o1, o2 = (axis + 1) % 3, (axis + 2) % 3

    # plain weave: 1.2 mm between threads, warp running along the grade axis
    pitch = 0.0012
    across = p[:, o1] / pitch
    down = p[:, axis] / pitch
    iw = np.floor(across)
    it = np.floor(down)
    fu = across - iw
    ft = down - it
    hu = np.sin(np.pi * fu)
    hu = hu * (0.72 + 0.28 * hu)
    ht = np.sin(np.pi * ft)
    ht = ht * (0.72 + 0.28 * ht)

    parity = (iw.astype(np.int64) + it.astype(np.int64)) & 1
    warp_up = parity == 0
    over = np.where(warp_up, hu, ht)
    under = np.where(warp_up, ht, hu)
    weave = 0.66 * over + 0.16 * under

    # hanging folds and thread bundles carry the read at object scale
    fold = _fbm2(p, o1, o2, (2.0, 2.0), seed + 53, tab, 2)
    fold2 = _fbm2(p, o1, o2, (6.4, 6.4), seed + 59, tab, 2)
    bundle = _value2(p, o1, o2, (46.0, 46.0), seed + 61, tab)
    thick = _value3(p, (11.0, 11.0, 2.6), seed + 67, tab)
    streak = _value3(p, (150.0, 150.0, 4.5), seed + 71, tab)
    slub = _value3(p, (300.0, 300.0, 40.0), seed + 73, tab)

    # dropped stitches: rare patches where the weave gives out
    dedge, dcell = _blocks(p, (12.0, 12.0, 12.0), seed + 79, tab)
    drop = _smoothstep(0.070, 0.025, dcell) * _smoothstep(0.0, 0.30, dedge)

    # every thread is dyed a little differently: hash the thread indices
    warp_dye = tab[_axis_hash(iw.astype(np.int64), 0, seed + 89) & _TAB_MASK]
    weft_dye = tab[_axis_hash(it.astype(np.int64), 1, seed + 89) & _TAB_MASK]
    dye = np.where(warp_up, warp_dye, weft_dye)

    # frayed, brightened hem threads along the low grade edge
    hem_noise = _fbm2(p, o1, o2, (18.0, 18.0), seed + 83, tab, 2)
    hem = _smoothstep(0.12, 0.0, g + (hem_noise - 0.5) * 0.09)
    hem = hem * (0.45 + 0.55 * slub)

    drape = (fold - 0.5) * 1.05 + (fold2 - 0.5) * 0.32
    height = (0.30 * weave * (1.0 - 0.85 * drop) * (0.60 + 0.30 * thick
                                                     + 0.25 * dye)
              + 0.50 * drape + 0.12 * (bundle - 0.5) + 0.06 * (slub - 0.5)
              + 0.05 * (streak - 0.5)
              - 0.12 * drop - 0.16 * hem * (1.0 - over))
    height = np.clip(height + 0.48, 0.0, 1.0)

    thread_c = np.where(warp_up[:, None], warp_c[None, :], weft_c[None, :])
    col = _mixc(deep, thread_c, (0.26 + 0.74 * over) * (0.58 + 0.42 * thick))
    raise_ = np.clip((over - 0.40) * 1.7, 0.0, 1.0)
    col = _mixc(col, sheen, 0.60 * raise_)
    col = _mixc(col, warp_c, 0.34 * bundle)
    col = _mixc(col, fray_c, 0.50 * hem * (0.35 + 0.65 * (1.0 - over)))
    col = _mixc(col, deep, 0.55 * drop)
    fold_shade = np.clip(0.42 + 1.30 * (fold * 0.72 + fold2 * 0.28), 0.16, 1.35)
    albedo = col * ((0.78 + 0.34 * dye) * fold_shade
                    * (0.82 + 0.18 * slub))[..., None]

    lo, hi = _rough_range("cloth")
    rt = np.clip(0.34 + 0.40 * (1.0 - over) + 0.30 * hem + 0.12 * drop
                 - 0.10 * raise_, 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, None


def _bone(p, pal, seed, g, along, axis, tab):
    """Pale ivory, fine pitting, hairline cracks, stain settling into lows."""
    pale = _colour(pal, "pale", "mid")
    mid = _colour(pal, "mid", "pale")
    stain_c = _colour(pal, "stain", "mid")
    crack_c = _colour(pal, "crack", "stain")

    w = _value3(p, (5.5, 5.5, 5.5), seed + 89, tab) - 0.5
    q = p + (0.010 * w)[:, None]

    # two crack networks: thin dark lines with recessed interiors, and only
    # where a slow mask lets the bone craze at all -- not every square inch
    c1 = _fbm3(q, (7.0, 7.0, 7.0), seed + 97, tab, 3)
    crack = _smoothstep(0.992, 0.9996, _ridged(c1))
    c2 = _fbm3(q, (24.0, 24.0, 24.0), seed + 101, tab, 2)
    hair = _smoothstep(0.988, 0.9994, _ridged(c2))
    gate = _smoothstep(0.34, 0.62, _fbm3(p, (2.1, 2.1, 2.1), seed + 131,
                                        tab, 2))
    crack = crack * (0.15 + 0.85 * gate)
    hair = hair * (0.25 + 0.75 * gate)

    pore = _value3(q, (95.0, 95.0, 95.0), seed + 103, tab)
    pit = _smoothstep(0.74, 0.98, pore)
    micro = _value3(q, (280.0, 280.0, 280.0), seed + 107, tab)
    bumpn = _value3(q, (22.0, 22.0, 22.0), seed + 109, tab)

    gf = [64.0, 64.0, 64.0]
    gf[axis] = 7.0
    grain = _value3(q, tuple(gf), seed + 113, tab)
    blot = _fbm3(p, (2.4, 2.4, 2.4), seed + 127, tab, 2)

    local = (0.55 - 0.20 * crack - 0.08 * hair - 0.12 * pit
             + 0.12 * (bumpn - 0.5) + 0.05 * (grain - 0.5))
    stain = np.clip(0.72 * _smoothstep(0.42, 0.80, blot)
                    + 0.55 * _smoothstep(0.60, 0.24, local)
                    + 0.22 * _smoothstep(0.85, 0.20, g), 0.0, 1.0)

    height = np.clip(0.55 + 0.18 * (bumpn - 0.5) + 0.06 * (grain - 0.5)
                     + 0.04 * (micro - 0.5)
                     - 0.14 * crack - 0.06 * hair - 0.16 * pit
                     - 0.07 * stain, 0.0, 1.0)

    col = _mixc(pale, mid, 0.45 * _smoothstep(0.30, 0.75,
                                              bumpn * 0.5 + blot * 0.5))
    col = _mixc(col, stain_c, 0.80 * stain)
    col = _mixc(col, crack_c, np.clip(0.62 * crack + 0.35 * hair, 0.0, 1.0))
    col = col * ((1.0 - 0.45 * pit) * (0.94 + 0.12 * micro))[..., None]

    lo, hi = _rough_range("bone")
    rt = np.clip(0.12 + 0.55 * stain + 0.28 * (crack + hair) + 0.12 * pit
                 + 0.12 * (0.5 - bumpn), 0.0, 1.0)
    return col, height, lo + (hi - lo) * rt, None


def _antler(p, pal, seed, g, along, axis, tab):
    """Keratin: growth rings at the base, striations, stained base to pale tip."""
    core = _colour(pal, "core", "deep")
    ridge_c = _colour(pal, "ridge", "plate")
    tip_c = _colour(pal, "tip", "ridge")
    stain_c = _colour(pal, "stain", "core")

    wob = _value3(p, (12.0, 12.0, 12.0), seed + 131, tab) - 0.5
    ring = 0.5 + 0.5 * np.cos(along * (2.0 * math.pi * 62.0) + wob * 7.0)
    ring = ring ** 1.6
    ring_fine = 0.5 + 0.5 * np.cos(along * (2.0 * math.pi * 190.0) + wob * 11.0)
    base_w = np.clip(1.0 - g, 0.0, 1.0) ** 1.5

    sf = [34.0, 34.0, 34.0]
    sf[axis] = 3.2
    stri = _fbm3(p, tuple(sf), seed + 137, tab, 2)
    sf2 = [130.0, 130.0, 130.0]
    sf2[axis] = 10.0
    fine = _value3(p, tuple(sf2), seed + 139, tab)
    pit = _smoothstep(0.80, 0.98,
                      _value3(p, (170.0, 170.0, 170.0), seed + 149, tab))

    relief = (0.42 * ring * base_w + 0.07 * ring_fine * base_w
              + 0.26 * (stri - 0.5) + 0.09 * (fine - 0.5)
              - 0.08 * pit * base_w)
    height = np.clip(0.50 + relief, 0.0, 1.0)

    wob_g = 0.08 * (stri - 0.5) + 0.04 * (fine - 0.5)
    col = _mixc(core, ridge_c, _smoothstep(0.06, 0.48, g + wob_g))
    col = _mixc(col, tip_c, _smoothstep(0.42, 0.85, g + wob_g))
    col = _mixc(col, stain_c,
                0.80 * np.clip(1.0 - 3.0 * g, 0.0, 1.0) * (0.5 + 0.5 * stri))
    col = col * np.clip(1.02 + 0.42 * (stri - 0.5) + 0.16 * (fine - 0.5)
                        + 0.30 * ring * base_w - 0.25 * pit * base_w,
                        0.30, 1.45)[..., None]

    lo, hi = _rough_range("antler")
    rt = np.clip(0.18 + 0.60 * (1.0 - g) + 0.20 * (1.0 - stri)
                 + 0.15 * pit * base_w - 0.12 * ring * base_w, 0.0, 1.0)
    return col, height, lo + (hi - lo) * rt, None


def _moss(p, pal, seed, g, along, axis, tab):
    """Cushion growth with shadowed gaps, dry tips, thinning with height."""
    deep = _colour(pal, "deep", "depth")
    body_c = _colour(pal, "body", "deep")
    tip_c = _colour(pal, "tip", "body")

    density = np.clip(1.06 - 0.92 * g, 0.0, 1.0)
    # warp so nothing sits on the noise lattice, then build clumps out of
    # thresholded fBm: organic lumps with pockets, never a grid of beads
    w = _value3(p, (6.5, 6.5, 6.5), seed + 143, tab) - 0.5
    q = p + (0.018 * w)[:, None]

    clump = _fbm3(q, (24.0, 24.0, 24.0), seed + 149, tab, 2)  # ~4 cm cushions
    clutch = _fbm3(q, (62.0, 62.0, 62.0), seed + 157, tab, 2)  # ~1.6 cm
    hummock = _fbm3(q, (3.0, 3.0, 3.0), seed + 169, tab, 2)
    fuzz = _value3(q, (150.0, 150.0, 150.0), seed + 163, tab)

    # a mat, not a scatter: the body is continuous and only the narrow deep
    # pockets between cushions fall away
    gap = _smoothstep(0.48, 0.32, clump * 0.70 + hummock * 0.30)
    bump = (0.55 * _dome(clump, 0.44, 0.86)
            + 0.35 * _dome(clutch, 0.46, 0.86) + 0.10 * hummock)
    cushion = np.clip(0.52 + 0.48 * bump - 0.55 * gap, 0.0, 1.0)
    height = np.clip((0.52 + 0.55 * bump - 0.65 * gap)
                     * (0.55 + 0.45 * density) + 0.05 * density
                     + 0.10 * (fuzz - 0.5), 0.0, 1.0)

    dry = (_smoothstep(0.50, 0.84, fuzz + 0.22 * (bump - 0.5))
           * _smoothstep(0.30, 0.72, bump) * (0.30 + 0.70 * g))
    col = _mixc(body_c, deep, 0.85 * gap)
    col = _mixc(col, tip_c, 0.90 * dry)
    col = _mixc(col, deep, 0.45 * (1.0 - density))
    albedo = col * np.clip(0.80 + 0.25 * bump + 0.10 * (fuzz - 0.5)
                           - 0.30 * gap, 0.35, 1.25)[..., None]

    lo, hi = _rough_range("moss")
    rt = np.clip(0.30 + 0.45 * gap + 0.15 * dry
                 + 0.10 * (1.0 - fuzz), 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, None


def _leather(p, pal, seed, g, along, axis, tab):
    """Cured hide: pebbled grain, fat sheen on the crowns, scuffed dye.

    The salvage kit and the stalker's wrap both live here. The read at object
    scale is stitch seams and soft swell; at texel scale it is a 4 mm pebble
    with dark creases between the crowns.
    """
    hide = _colour(pal, "hide", "body")
    worn = _colour(pal, "worn", "edge")
    crease_c = _colour(pal, "crease", "deep")
    sheen_c = _colour(pal, "sheen", "worn")
    stitch_c = _colour(pal, "stitch", "sheen")

    o1, o2 = (axis + 1) % 3, (axis + 2) % 3

    # Pebbled grain: ~4 mm cells, domed crowns, creases on the cell faces.
    warp = _value3(p, (9.0, 9.0, 9.0), seed + 211, tab) - 0.5
    q = p + (0.0026 * warp)[:, None]
    grain_edge, grain_cell = _blocks(q, (230.0, 230.0, 230.0), seed + 213, tab)
    crown = _dome(grain_edge, 0.18, 0.96)
    crease = 1.0 - np.clip(grain_edge * 3.4, 0.0, 1.0)
    crown = np.clip(crown * (0.55 + 0.45 * grain_cell), 0.0, 1.0)

    # Hide-scale swell and folds: a soft body behind the grain.
    swell = _fbm3(p, (3.2, 3.2, 3.2), seed + 217, tab, 2)
    fold = _fbm3(p, (11.0, 11.0, 11.0), seed + 219, tab, 2)
    fold_line = _ridged(_fbm3(p, (7.5, 7.5, 7.5), seed + 223, tab, 2))

    # Abrasion: broad scuffed patches that lighten the dye and flatten the grain.
    abrade_edge, _abrade_cell = _blocks(p, (26.0, 26.0, 26.0), seed + 227, tab)
    abrade = _smoothstep(0.62, 0.20, abrade_edge)
    scuff = _value3(p, (210.0, 210.0, 210.0), seed + 229, tab)
    abrade = np.clip(abrade * (0.45 + 0.55 * scuff), 0.0, 1.0)

    # Stitched seam along the panel edge: punched holes with a raised thread.
    edge_g = np.abs(np.abs(g - 0.5) - 0.455)
    seam_band = _smoothstep(0.035, 0.008, edge_g)
    pitch = 0.011
    phase = (along / pitch) % 1.0
    hole = _smoothstep(0.34, 0.10, np.abs(phase - 0.5) * 2.0)
    stitch = seam_band * hole

    height = (0.46
              + 0.30 * crown * (1.0 - 0.55 * abrade)
              + 0.22 * (swell - 0.5)
              + 0.16 * (fold - 0.5)
              + 0.10 * (fold_line - 0.5)
              - 0.30 * crease
              - 0.26 * stitch)
    height = np.clip(height, 0.0, 1.0)

    col = _mixc(hide, crease_c, 0.85 * crease)
    col = _mixc(col, worn, 0.70 * np.clip(crown * 1.15 - 0.15, 0.0, 1.0))
    col = _mixc(col, sheen_c, 0.35 * np.clip(crown - 0.45, 0.0, 1.0))
    col = _mixc(col, worn, 0.85 * abrade)
    col = _mixc(col, crease_c, 0.55 * np.clip(fold_line - 0.55, 0.0, 0.45))
    col = _mixc(col, stitch_c, 0.80 * stitch)
    body_shade = np.clip(0.80 + 0.30 * (swell * 0.6 + fold * 0.4)
                         + 0.12 * (grain_cell - 0.5) - 0.20 * crease
                         + 0.18 * abrade, 0.35, 1.30)
    albedo = col * body_shade[..., None]

    lo, hi = _rough_range("leather")
    rt = np.clip(0.42 + 0.34 * crease + 0.22 * abrade + 0.18 * stitch
                 - 0.26 * np.clip(crown - 0.35, 0.0, 1.0), 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, None


def _void(p, pal, seed, g, along, axis, tab):
    """The inside of a hood: black, a faint rim, smoke that never reads."""
    depth = _colour(pal, "depth", "core")
    floor_c = _colour(pal, "floor", "depth")
    rim_c = _colour(pal, "rim", "floor")

    drift = _fbm3(p, (3.2, 3.2, 3.2), seed + 173, tab, 2)
    smoke = _fbm3(p, (9.0, 9.0, 9.0), seed + 179, tab, 2)
    rim = _smoothstep(0.35, 1.0, g)

    col = _mixc(depth, floor_c, 0.30 + 0.85 * drift)
    col = _mixc(col, rim_c, np.clip(0.80 * rim * rim + 0.35 * rim * smoke
                                   + 0.14 * (drift - 0.45), 0.0, 1.0))
    height = np.clip(0.45 + 0.12 * (smoke - 0.5) + 0.08 * (drift - 0.5),
                     0.0, 1.0)

    lo, hi = _rough_range("void")
    rt = np.clip(0.35 + 0.45 * (1.0 - rim) + 0.20 * smoke, 0.0, 1.0)
    return col, height, lo + (hi - lo) * rt, None


def _ember(p, pal, seed, g, along, axis, tab):
    """Hot internal light: cream core, orange iris with fibres, dark outer ring."""
    core_c = _colour(pal, "core", "iris")
    iris_c = _colour(pal, "iris", "core")
    outer_c = _colour(pal, "outer", "iris")

    o1, o2 = (axis + 1) % 3, (axis + 2) % 3
    phi = np.arctan2(p[:, o1], p[:, o2])
    a = np.abs(2.0 * g - 1.0)  # 0 at the hot core, 1 at the dark ring

    turb = _fbm3(p, (10.0, 10.0, 10.0), seed + 181, tab, 2) - 0.5
    mottle = _fbm3(p, (6.0, 6.0, 6.0), seed + 191, tab, 2) - 0.5
    fibre = 0.5 + 0.5 * np.sin(phi * 160.0 + turb * 10.0 - a * 4.0)
    fibre2 = 0.5 + 0.5 * np.sin(phi * 47.0 + turb * 4.0)

    # the hot/cool bands are mottled by the turbulence, never a clean gradient
    aa = np.clip(a + 1.20 * mottle + 0.14 * (fibre2 - 0.5), 0.0, 1.40)
    col = _mixc(outer_c, iris_c, _smoothstep(0.86, 0.30, aa))
    col = _mixc(col, core_c, _smoothstep(0.34, 0.04, aa))
    ring = _smoothstep(0.52, 1.0, aa)
    glow = (0.72 + 0.22 * fibre2 + 0.30 * (turb + 0.5)
            + 0.10 * (fibre - 0.5)) * (1.0 - 0.82 * ring)
    emission = np.clip(col * glow[..., None], 0.0, 1.0)
    albedo = np.clip(col * (0.14 - 0.09 * ring)[..., None] + 0.006, 0.0, 1.0)

    height = np.clip(0.50 + 0.08 * (fibre - 0.5) + 0.10 * turb, 0.0, 1.0)
    lo, hi = _rough_range("ember")
    rt = np.clip(0.10 + 0.85 * a + 0.10 * (1.0 - fibre), 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, emission


_SAMPLERS = {
    "bark": _bark,
    "cloth": _cloth,
    "leather": _leather,
    "bone": _bone,
    "antler": _antler,
    "moss": _moss,
    "void": _void,
    "ember": _ember,
}


# ---------------------------------------------------------------------------
# public sampling entry point


def sample(
    surface: str,
    points: np.ndarray,
    palette: dict[str, str],
    seed: int,
    grade: tuple[int, float, float] = (2, 0.0, 1.0),
) -> dict[str, np.ndarray | None]:
    """Sample one forest material at rest-space points.

    ``points`` is ``(N, 3)`` float32 metres in Blender axes (X left, Y
    forward, Z up) and ``grade`` is ``(axis, low, high)``: the base-to-tip
    bounds used for antler base->tip, the bone stain falloff and moss density.
    Returns display-space ``albedo`` (N,3), ``height`` (N,), ``roughness``
    (N,) inside the surface's declared range and ``emission`` (N,3) or
    ``None``.  Every value is finite and clamped to its documented range.
    """
    if surface not in _SAMPLERS:
        raise ValueError(f"unknown forest surface {surface!r}; "
                         f"expected one of {SURFACES}")
    pts = np.asarray(points, dtype=np.float32)
    if pts.ndim == 1 and pts.size == 3:
        pts = pts.reshape(1, 3)
    if pts.ndim != 2 or pts.shape[1] != 3:
        raise ValueError(f"points must be (N, 3), got {pts.shape}")

    n = int(pts.shape[0])
    sampler = _SAMPLERS[surface]
    tab = _table(seed)
    emissive = surface == "ember"

    albedo = np.empty((n, 3), np.float32)
    height = np.empty(n, np.float32)
    roughness = np.empty(n, np.float32)
    emission = np.empty((n, 3), np.float32) if emissive else None

    for start in range(0, n, _CHUNK):
        stop = min(start + _CHUNK, n)
        # sanitise a private copy so huge / non-finite inputs stay in range
        chunk = np.nan_to_num(np.asarray(pts[start:stop], np.float32),
                              nan=0.0, posinf=1e4, neginf=-1e4)
        np.clip(chunk, -1e4, 1e4, out=chunk)
        g, along, axis = _grade_values(chunk, grade)
        a, h, r, e = sampler(chunk, palette, int(seed), g, along, axis, tab)
        albedo[start:stop] = np.clip(a, 0.0, 1.0)
        height[start:stop] = np.clip(h, 0.0, 1.0)
        lo, hi = _rough_range(surface)
        roughness[start:stop] = np.clip(r, lo, hi)
        if emissive:
            emission[start:stop] = np.clip(e, 0.0, 1.0)

    return {
        "albedo": albedo,
        "height": height,
        "roughness": roughness,
        "emission": emission,
    }


def normal_map(height: np.ndarray, strength: float) -> np.ndarray:
    """Tangent-space normal map from a height field.

    ``(H, W) float32 height -> (H, W, 3) float32`` in 0..1, +U right and +V
    up (rows of the array run downward, the glTF/Blender OpenGL convention):
    the green channel encodes ``-dh/dv``, so a surface rising toward +V gets
    green below 0.5 -- the same sign as ``tools/world_textures.py``.
    """
    h = np.asarray(height, dtype=np.float32)
    if h.ndim != 2:
        raise ValueError(f"height must be (H, W), got {h.shape}")
    s = float(strength)
    rows, cols = h.shape

    out = np.empty((rows, cols, 3), np.float32)
    if rows < 2 or cols < 2:
        out[..., 0] = 0.5
        out[..., 1] = 0.5
        out[..., 2] = 1.0
        return out

    dx = np.empty_like(h)
    dx[:, 1:-1] = 0.5 * (h[:, 2:] - h[:, :-2])
    dx[:, 0] = h[:, 1] - h[:, 0]
    dx[:, -1] = h[:, -1] - h[:, -2]

    dy = np.empty_like(h)
    dy[1:-1, :] = 0.5 * (h[2:, :] - h[:-2, :])
    dy[0, :] = h[1, :] - h[0, :]
    dy[-1, :] = h[-1, :] - h[-2, :]

    nx = -dx * s
    ny = dy * s  # dy is dh/drow == -dh/dv, so this is the -dh/dv convention
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + 1.0)
    out[..., 0] = nx * inv * 0.5 + 0.5
    out[..., 1] = ny * inv * 0.5 + 0.5
    out[..., 2] = inv * 0.5 + 0.5
    return out


# ---------------------------------------------------------------------------
# self-test


_PREVIEW_SIZE = 1024
_PREVIEW_SS = 2
_PREVIEW_RADIUS = 0.30
_PREVIEW_Z = (0.0, 2.6)
_PREVIEW_EXPOSURE = 1.8
# the ember preview needs a small hot patch, or the slab shows one hot band
_PREVIEW_GRADE_OVERRIDE = {"ember": (2, 1.10, 1.50)}
#: Second-palette comparison tiles (only where the mob actually has the surface).
_GALLOWSROOT_TILES = ("bark", "moss", "void", "ember")


def _has_palette(mob: str, surface: str) -> bool:
    return surface in _styles.MOBS[mob]["palette"]


def _preview_palette(surface: str) -> tuple[str, dict[str, str]]:
    """Warden colours, else the mob that owns the surface, else gallowsroot.

    The warden has no bark, so the bark tile is drawn with the ossuary
    stalker's bark (the mob the material actually belongs to) and the
    gallowsroot bark is then still available as the comparison tile.
    """
    for mob in ("hollow_warden", "ossuary_stalker", "gallowsroot"):
        if _has_palette(mob, surface):
            return mob, _styles.palette(mob, surface)
    raise KeyError(f"no preview palette for {surface!r}")


def _check_points() -> np.ndarray:
    rng = np.random.default_rng(_styles.SEED ^ 0xF0E5)
    z = rng.uniform(0.0, 2.6, 20_000).astype(np.float32)
    theta = rng.uniform(0.0, 2.0 * math.pi, 20_000).astype(np.float32)
    r = rng.uniform(0.15, 0.45, 20_000).astype(np.float32)
    cloud = np.stack([r * np.cos(theta), r * np.sin(theta), z], axis=1)
    return np.concatenate([cloud.astype(np.float32),
                           np.zeros((1, 3), np.float32)], axis=0)


def _validate() -> list[str]:
    fails: list[str] = []
    pts = _check_points()
    grade = (2, 0.0, 2.6)
    pal_cache = {s: _preview_palette(s)[1] for s in SURFACES}

    for surface in SURFACES:
        pal = pal_cache[surface]
        lo, hi = _rough_range(surface)
        first = sample(surface, pts, pal, _styles.SEED, grade)
        second = sample(surface, pts, pal, _styles.SEED, grade)
        for key in ("albedo", "height", "roughness"):
            a, b = first[key], second[key]
            if not np.array_equal(a, b):
                fails.append(f"{surface}: {key} is not deterministic")
        albedo = first["albedo"]
        height = first["height"]
        rough = first["roughness"]
        if albedo.shape != (pts.shape[0], 3) or albedo.dtype != np.float32:
            fails.append(f"{surface}: albedo shape/dtype {albedo.shape} "
                         f"{albedo.dtype}")
        if height.shape != (pts.shape[0],) or height.dtype != np.float32:
            fails.append(f"{surface}: height shape/dtype {height.shape}")
        if rough.shape != (pts.shape[0],):
            fails.append(f"{surface}: roughness shape {rough.shape}")
        for key, arr in (("albedo", albedo), ("height", height),
                         ("roughness", rough)):
            if not np.isfinite(arr).all():
                fails.append(f"{surface}: {key} has non-finite values")
                continue
            if arr.min() < -1e-6 or arr.max() > 1.0 + 1e-6:
                fails.append(f"{surface}: {key} outside 0..1 "
                             f"({arr.min():.4f}..{arr.max():.4f})")
        if not np.isfinite(rough).all() or rough.min() < lo - 1e-6 \
                or rough.max() > hi + 1e-6:
            fails.append(f"{surface}: roughness outside {lo}..{hi} "
                         f"({rough.min():.4f}..{rough.max():.4f})")
        em = first["emission"]
        if surface == "ember":
            if em is None or em.shape != (pts.shape[0], 3):
                fails.append("ember: emission must be a (N, 3) array")
            elif not np.isfinite(em).all() or em.max() <= 0.0:
                fails.append("ember: emission is not a live colour")
        elif em is not None:
            if em.max() >= 0.05:
                fails.append(f"{surface}: emission {em.max():.3f} >= 0.05")

    # a single point must not change shape or blow up
    one = sample("bone", np.zeros((1, 3), np.float32), pal_cache["bone"],
                 _styles.SEED, grade)
    if one["albedo"].shape != (1, 3) or one["height"].shape != (1,):
        fails.append(f"single point shape {one['albedo'].shape}")
    if not np.isfinite(one["albedo"]).all():
        fails.append("single point is not finite")

    # chunking must not change a texel
    half = pts.shape[0] // 2
    whole = sample("bark", pts, pal_cache["bark"], _styles.SEED, grade)
    split = [sample("bark", pts[:half], pal_cache["bark"], _styles.SEED, grade),
             sample("bark", pts[half:], pal_cache["bark"], _styles.SEED,
                    grade)]
    for key in ("albedo", "height", "roughness"):
        joined = np.concatenate([split[0][key], split[1][key]], axis=0)
        if not np.array_equal(joined, whole[key]):
            fails.append(f"bark: {key} changes when the array is chunked")

    # normals
    flat = np.full((8, 8), 0.4, np.float32)
    nf = normal_map(flat, 2.0)
    if not np.allclose(nf, (0.5, 0.5, 1.0), atol=1e-6):
        fails.append(f"normal_map(flat) = {nf[0, 0]}")

    rows, cols = 32, 16
    v = np.linspace(0.0, 1.0, rows, dtype=np.float32)[::-1]  # rises toward +V
    ramp_up = np.repeat(v[:, None], cols, axis=1)  # row 0 is high = +V
    n_up = normal_map(ramp_up, 3.0)
    dec = n_up.astype(np.float64) * 2.0 - 1.0
    lengths = np.linalg.norm(dec, axis=-1)
    if not np.allclose(lengths, 1.0, atol=1e-5):
        fails.append(f"normal rows are not unit length "
                     f"({lengths.min():.6f}..{lengths.max():.6f})")
    if not (n_up[..., 1] < 0.5).all():
        fails.append("normal_map: a ramp rising toward +V must have green "
                     "< 0.5")
    if not np.allclose(n_up[..., 0], 0.5, atol=1e-6):
        fails.append("normal_map: a ramp along V must not tilt U")
    n_down = normal_map(ramp_up[::-1].copy(), 3.0)
    if not (n_down[..., 1] > 0.5).all():
        fails.append("normal_map: a ramp falling toward +V must have green "
                     "> 0.5")

    rng = np.random.default_rng(7)
    field = rng.random((64, 48), dtype=np.float32)
    nm = normal_map(field, 2.5)
    dec = nm.astype(np.float64) * 2.0 - 1.0
    if not np.isfinite(nm).all() or not np.allclose(
            np.linalg.norm(dec, axis=-1), 1.0, atol=1e-5):
        fails.append("normal_map(random) is not finite/unit length")
    if nm.min() < 0.0 or nm.max() > 1.0:
        fails.append("normal_map output outside 0..1")
    return fails


def _slab_points(n: int) -> np.ndarray:
    """The preview slab: a 0.30 m radius cylinder column, rows = z descending."""
    z0, z1 = _PREVIEW_Z
    theta = (np.arange(n, dtype=np.float32) + 0.5) * (2.0 * math.pi / n)
    z = z1 - (np.arange(n, dtype=np.float32) + 0.5) * ((z1 - z0) / n)
    cos_t = np.cos(theta)
    sin_t = np.sin(theta)
    xs = np.tile(_PREVIEW_RADIUS * cos_t, n)
    ys = np.tile(_PREVIEW_RADIUS * sin_t, n)
    zs = np.repeat(z, n)
    return np.stack((xs, ys, zs), axis=1)


def _prefilter(height: np.ndarray, taps: int = 1) -> np.ndarray:
    """Separable box prefilter used as a preview mip level.

    The slab is sampled at ~0.9 mm per pixel while the weave is a 1.2 mm
    pitch, so the raw height field is undersampled and differentiates into
    aliasing.  Averaging over the tap footprint is exactly what a mip chain
    would hand the renderer at this distance.
    """
    out = height
    for _ in range(taps):
        p = np.pad(out, 1, mode="edge")
        out = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
               + out) * 0.2
    return out.astype(np.float32)


def _render_preview(surface: str, pal: dict[str, str], grade) -> np.ndarray:
    """Sample the slab, light it with a fixed key light, box-filter down."""
    n = _PREVIEW_SIZE * _PREVIEW_SS
    pts = _slab_points(n)
    out = sample(surface, pts, pal, _styles.SEED, grade)

    height = out["height"].reshape(n, n)
    strength = float(_styles.SURFACES[surface]["normal"])
    nm = normal_map(_prefilter(height), strength)
    nx = nm[..., 0] * 2.0 - 1.0
    ny = nm[..., 1] * 2.0 - 1.0
    nz = nm[..., 2] * 2.0 - 1.0

    theta = (np.arange(n, dtype=np.float32) + 0.5) * (2.0 * math.pi / n)
    cos_t = np.cos(theta)[None, :]
    sin_t = np.sin(theta)[None, :]
    # world = T*nx + B*ny + N*nz with T = +theta, B = +Z, N = radial
    wx = -sin_t * nx + cos_t * nz
    wy = cos_t * nx + sin_t * nz
    wz = ny

    key = np.maximum(wx * _LIGHT_KEY[0] + wy * _LIGHT_KEY[1]
                     + wz * _LIGHT_KEY[2], 0.0)
    fill = np.maximum(wx * _LIGHT_FILL[0] + wy * _LIGHT_FILL[1]
                      + wz * _LIGHT_FILL[2], 0.0)
    lit = 0.14 + 0.92 * key + 0.20 * fill

    img = out["albedo"].reshape(n, n, 3) * lit[..., None]
    if out["emission"] is not None:
        img = img + out["emission"].reshape(n, n, 3)
    # preview-only display transform so near-black palettes stay readable
    img = 1.0 - np.exp(-_PREVIEW_EXPOSURE * np.maximum(img, 0.0))

    k = _PREVIEW_SS
    img = img.reshape(_PREVIEW_SIZE, k, _PREVIEW_SIZE, k, 3)
    return img.mean(axis=(1, 3)).astype(np.float32)


def _write_png(path: Path, rgb: np.ndarray) -> None:
    from PIL import Image

    a = np.clip(rgb * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(a, "RGB").save(path, optimize=True)


def main() -> int:
    print(f"forest_surface  seed={_styles.SEED}  surfaces={len(SURFACES)}")
    fails = _validate()
    if fails:
        for fail in fails:
            print("FAIL", fail)
        return 1
    print("checks ok: determinism, finiteness, ranges, roughness, emission, "
          "normals, single point, chunking")

    started = time.perf_counter()
    for surface in SURFACES:
        grade = _PREVIEW_GRADE_OVERRIDE.get(surface, (2, 0.0, 2.6))
        mob, pal = _preview_palette(surface)
        t0 = time.perf_counter()
        img = _render_preview(surface, pal, grade)
        dt = time.perf_counter() - t0
        _write_png(PREVIEW_ROOT / f"{surface}.png", img)

        extra = ""
        if surface in _GALLOWSROOT_TILES and mob != "gallowsroot":
            t1 = time.perf_counter()
            img2 = _render_preview(surface,
                                   _styles.palette("gallowsroot", surface),
                                   grade)
            dt2 = time.perf_counter() - t1
            _write_png(PREVIEW_ROOT / f"{surface}_gallowsroot.png", img2)
            extra = f"  gallowsroot {dt2:5.2f}s"

        print(f"{surface:<7} {_PREVIEW_SIZE}x{_PREVIEW_SIZE}  {mob:<14}"
              f"  {dt:5.2f}s  luma={float(img.mean()):.3f}{extra}")
    total = time.perf_counter() - started

    # the big-array path: every point goes through the same chunked sampler
    rng = np.random.default_rng(_styles.SEED ^ 0xB16)
    huge = rng.uniform(-0.5, 0.5, (4_500_000, 3)).astype(np.float32)
    t0 = time.perf_counter()
    big = sample("bark", huge, _preview_palette("bark")[1],
                 _styles.SEED, (2, 0.5, 0.5))
    dt = time.perf_counter() - t0
    ok = (big["albedo"].shape == (4_500_000, 3)
          and np.isfinite(big["albedo"]).all()
          and np.isfinite(big["height"]).all())
    print(f"bark    4,500,000 points  {dt:5.2f}s  "
          f"{'ok' if ok else 'FAIL'}")
    del huge, big

    print(f"previews: {PREVIEW_ROOT}  ({total:4.1f}s render)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
