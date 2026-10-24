"""Author the source-based devil PBR maps with Pillow + numpy.

Run with the *system* Python (Pillow is not bundled with Blender):

    python tools/devil_source_textures.py -- all
    python tools/devil_source_textures.py -- succubus

The script reads the licensed CC0 Quaternius source maps under
``.runtime/character-source`` and writes tinted/detailed PNGs to
``.runtime/devil-source/<mob>/textures``.  All detail is deterministic; the
source skin/leather/hair normal and roughness maps are retained so pores,
weaves and leather grain survive the recolour.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

from devil_styles import (  # noqa: E402
    EYE_SOURCE, HAIR_SOURCE, LEATHER, SKIN, STYLES,
)
import world_textures as wt  # noqa: E402

OUT_ROOT = ROOT / ".runtime" / "devil-source"
SEED = 191_907  # deterministic


# ---------------------------------------------------------------------------
# IO helpers


def read_rgb(path: Path, size: int | None = None) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    if size and img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def read_rgba(path: Path, size: int | None = None) -> np.ndarray:
    img = Image.open(path).convert("RGBA")
    if size and img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def write_rgb(arr: np.ndarray, path: Path, mode: str = "RGB") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    if mode == "RGBA" and a.shape[-1] == 3:
        a = np.concatenate([a, np.full(a.shape[:2] + (1,), 255, np.uint8)], axis=-1)
    Image.fromarray(a, mode).save(path, optimize=True)


def luminance(rgb: np.ndarray) -> np.ndarray:
    return (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]).astype(np.float32)


def normalize(a: np.ndarray) -> np.ndarray:
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / max(1e-6, hi - lo)


def detail_stats(arr: np.ndarray) -> str:
    lap = np.abs(arr[1:-1, 1:-1] - 0.25 * (arr[:-2, 1:-1] + arr[2:, 1:-1] + arr[1:-1, :-2] + arr[1:-1, 2:]))
    return f"mean={arr.mean():.3f} std={arr.std():.3f} detail={lap.mean():.4f}"


# ---------------------------------------------------------------------------
# Painterly overlays (skin veins, scars, membrane veins)


def _vein_layer(size: int, color: tuple[int, int, int], seed: int,
                roots: int, alpha: float, direction: str = "radial") -> np.ndarray:
    """Branching vessel layer as an RGBA float array (alpha in A)."""
    ss = 2
    w = size * ss
    canvas = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    rng = np.random.default_rng(seed)

    def branch(x: float, y: float, ang: float, length: float, width: float, depth: int) -> None:
        steps = max(5, int(length / max(1.0, width * 1.6)))
        pts = []
        for i in range(steps + 1):
            t = i / steps
            nx = x + math.cos(ang) * length * t
            ny = y + math.sin(ang) * length * t
            # gentle meander, tapered width
            ang += (rng.random() - 0.5) * 0.16
            pts.append((nx, ny))
        a = int(255 * alpha * (0.45 + 0.55 * (1.0 - depth / 5.0)))
        for i in range(len(pts) - 1):
            taper = max(1, int(round(width * (1.0 - i / len(pts)))))
            draw.line([pts[i], pts[i + 1]], fill=(*color, a), width=taper, joint="curve")
        if depth > 0 and length > size * 0.05:
            for _ in range(2):
                side = -1 if rng.random() < 0.5 else 1
                bx, by = pts[int(len(pts) * (0.45 + 0.35 * rng.random()))]
                branch(bx, by, ang + side * (0.45 + 0.5 * rng.random()),
                       length * (0.42 + 0.26 * rng.random()), width * 0.55, depth - 1)

    for _ in range(roots):
        if direction == "radial":
            a = rng.random() * math.tau
            r = size * (0.10 + 0.12 * rng.random())
            x = w / 2 + math.cos(a) * r
            y = w / 2 + math.sin(a) * r
            ang = a + (rng.random() - 0.5) * 0.5
        else:  # from the left/top edge (wing membrane)
            x = rng.random() * w * 0.18
            y = rng.random() * w
            ang = 0.10 + (rng.random() - 0.5) * 0.45
        branch(x, y, ang, size * (0.28 + 0.32 * rng.random()),
               size * (0.0025 + 0.0035 * rng.random()), 4)
    canvas = canvas.resize((size, size), Image.LANCZOS)
    return np.asarray(canvas, dtype=np.float32) / 255.0


def overlay_rgba(base: np.ndarray, layer: np.ndarray) -> np.ndarray:
    a = layer[..., 3:4]
    out = base * (1.0 - a) + layer[..., :3] * a
    return np.clip(out, 0, 1)


def draw_scars(img: np.ndarray, count: int, seed: int) -> np.ndarray:
    if count <= 0:
        return img
    size = img.shape[0]
    ss = 2
    canvas = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        x = rng.random() * size * ss * 0.9 + size * ss * 0.05
        y = rng.random() * size * ss * 0.9 + size * ss * 0.05
        ang = rng.random() * math.tau
        length = size * ss * (0.035 + 0.10 * rng.random())
        pts = []
        for i in range(14):
            t = i / 13
            nx = x + math.cos(ang) * length * t
            ny = y + math.sin(ang) * length * t
            ang += (rng.random() - 0.5) * 0.10
            pts.append((nx, ny))
        draw.line(pts, fill=(70, 20, 24, 135), width=max(1, size // 700), joint="curve")
        draw.line([(px + 1, py + 1) for px, py in pts], fill=(210, 168, 156, 75),
                  width=max(1, size // 1100), joint="curve")
    canvas = canvas.resize((size, size), Image.LANCZOS)
    return overlay_rgba(img, np.asarray(canvas, dtype=np.float32) / 255.0)


# ---------------------------------------------------------------------------
# Skin


def skin_maps(mob: str, out_dir: Path) -> None:
    style = STYLES[mob]
    src = SKIN[style["skin_source"]]
    size = 2048
    base = read_rgb(src["albedo"], size)
    normal = read_rgb(src["normal"], size)
    rough = read_rgb(src["roughness"], size)[..., 0]

    gray = luminance(base)[..., None]
    target = np.array(style["skin_target"], np.float32)[None, None, :]
    # Keep source pore/shading detail in luminance; move only chroma + value.
    colorized = target * (0.38 + 1.18 * gray)
    albedo = base * (1.0 - 0.72 * style["skin_desaturate"]) + colorized * (0.72 * style["skin_desaturate"])

    # Mottled circulation and subtle blue/red capillary variation.
    low = wt.fbm(size, size, 7, 7, SEED + 11, octaves=5, wrap="both")
    mid = wt.fbm(size, size, 19, 19, SEED + 12, octaves=4, wrap="both")
    albedo *= 1.0 + style["skin_mottle"] * (low[..., None] - 0.5) * 2.0
    red = np.array((0.26, 0.02, 0.025), np.float32)[None, None, :]
    blue = np.array((0.02, 0.035, 0.065), np.float32)[None, None, :]
    albedo = albedo * (1.0 - 0.16 * mid[..., None]) + (red * 0.55 + blue * 0.45) * (0.16 * mid[..., None])
    # Grime settles in the lower-frequency cavities.
    albedo *= 1.0 - style["skin_grime"] * (wt.fbm(size, size, 4, 4, SEED + 13, octaves=4)[..., None])

    if style.get("skin_veins", 0) > 0:
        veins = _vein_layer(size, (52, 12, 18), SEED + 21, roots=9,
                            alpha=style["skin_veins"], direction="radial")
        albedo = overlay_rgba(albedo, veins)
    albedo = draw_scars(albedo, int(style.get("skin_scars", 0)), SEED + 31)
    albedo = np.clip(albedo, 0, 1)

    # Slight roughness break-up; the source already has realistic skin roughness.
    rn = wt.fbm(size, size, 9, 9, SEED + 14, octaves=4)
    rough_out = np.clip(rough * (0.92 + 0.16 * rn), 0.05, 1.0)

    write_rgb(albedo, out_path(out_dir, "skin_albedo.png"))
    write_rgb(normal, out_path(out_dir, "skin_normal.png"))
    write_rgb(np.repeat(rough_out[..., None], 3, axis=-1), out_path(out_dir, "skin_roughness.png"))
    print("SKIN", mob, detail_stats(albedo))


# ---------------------------------------------------------------------------
# Outfit leather, hair, eyes


def leather_maps(mob: str, out_dir: Path) -> None:
    style = STYLES[mob]
    size = 2048
    base = read_rgb(LEATHER["albedo"], size)
    normal = read_rgb(LEATHER["normal"], size)
    orm = read_rgb(LEATHER["orm"], size)
    tint = np.array(style.get("leather_tint", (0.22, 0.14, 0.09)), np.float32)
    # Multiply in display space, then restore a little of the source highlight.
    gain = float(style.get("leather_gain", 4.0))
    albedo = np.clip(base * tint * gain + base * base * 0.12, 0, 1)
    grime = wt.fbm(size, size, 8, 8, SEED + 41, octaves=5)
    albedo *= 1.0 - style.get("leather_grime", 0.2) * (grime[..., None] - 0.45)
    scratches = wt.fbm(size, size, 90, 7, SEED + 42, octaves=3, ridge=True)
    albedo = np.clip(albedo * (0.94 + 0.12 * scratches[..., None]), 0, 1)
    rough = np.clip(orm[..., 1] * (0.92 + 0.20 * wt.fbm(size, size, 12, 12, SEED + 43)), 0.08, 1.0)
    metal = orm[..., 2] * 0.0
    write_rgb(albedo, out_path(out_dir, "leather_albedo.png"))
    write_rgb(normal, out_path(out_dir, "leather_normal.png"))
    write_rgb(np.repeat(rough[..., None], 3, axis=-1), out_path(out_dir, "leather_roughness.png"))
    write_rgb(np.repeat(metal[..., None], 3, axis=-1), out_path(out_dir, "leather_metallic.png"))
    print("LEATHER", mob, detail_stats(albedo))


def hair_maps(mob: str, out_dir: Path, source: str = "female_long") -> None:
    style = STYLES[mob]
    src = HAIR_SOURCE[source]
    size = 1024
    base = read_rgb(src["albedo"], size)
    normal = read_rgb(src["normal"], size)
    tint = np.array(style.get("hair_tint", (0.04, 0.02, 0.02)), np.float32)
    albedo = np.clip(base * tint * 5.0 + base * base * 0.04, 0, 1)
    # Keep the card's highlight structure rather than flattening it.
    albedo = np.clip(albedo + base * 0.045, 0, 1)
    write_rgb(albedo, out_path(out_dir, "hair_albedo.png"))
    write_rgb(normal, out_path(out_dir, "hair_normal.png"))
    print("HAIR", mob, detail_stats(albedo))


def eye_maps(mob: str, out_dir: Path) -> None:
    style = STYLES[mob]
    size = 256
    base = read_rgb(EYE_SOURCE["albedo"], size)
    normal = read_rgb(EYE_SOURCE["normal"], size)
    mx = base.max(axis=2)
    mn = base.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    val = mx
    # Iris: coloured, mid-bright pixels.  Pupil and sclera are excluded.
    iris = ((sat > 0.14) & (val > 0.12) & (val < 0.96)).astype(np.float32)
    iris = np.asarray(Image.fromarray((iris * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)),
                      dtype=np.float32) / 255.0
    color = np.array(style["eye_iris"], np.float32)[None, None, :]
    lum = np.clip(luminance(base) * 1.8 + 0.10, 0, 1)[..., None]
    albedo = base * (1.0 - iris[..., None] * 0.94) + color * lum * iris[..., None] * 0.94
    albedo = np.clip(albedo, 0, 1)
    emission = np.clip(color * (iris[..., None] ** 0.8) * min(1.0, style["eye_emission"] / 3.0), 0, 1)
    write_rgb(albedo, out_path(out_dir, "eye_albedo.png"))
    write_rgb(emission, out_path(out_dir, "eye_emission.png"))
    write_rgb(normal, out_path(out_dir, "eye_normal.png"))
    print("EYE", mob, "iris_coverage", float(iris.mean()))


# ---------------------------------------------------------------------------
# Procedural extras


def horn_maps(mob: str, out_dir: Path) -> None:
    style = STYLES[mob]
    kind, dark, pale = style.get("horn", ("ram", (0.08, 0.05, 0.03), (0.66, 0.56, 0.40)))
    size = 1024
    if kind == "stone":
        stone_maps(mob, out_dir, size=size, prefix="horn", palette=(dark, pale))
        return
    u = np.linspace(0, 1, size, endpoint=False, dtype=np.float32)[None, :]
    v = np.linspace(0, 1, size, endpoint=False, dtype=np.float32)[:, None]
    rings = 24 if kind == "ram" else 15
    ring_phase = v * rings + 0.22 * np.sin(u * math.tau * 2.0) + 0.08 * wt.fbm(size, size, 5, 5, SEED + 51)
    ring = 0.5 + 0.5 * np.sin(ring_phase * math.tau)
    stri = wt.fbm(size, size, 96, 6, SEED + 52, octaves=5, wrap="x")
    pores = wt.fbm(size, size, 180, 180, SEED + 53, octaves=3)
    grad = wt.smoothstep(0.0, 0.90, v)
    base = np.array(dark, np.float32)[None, None, :]
    tip = np.array(pale, np.float32)[None, None, :]
    albedo = wt.mix(base, tip, np.clip(grad * 0.92 + 0.04, 0, 1))
    albedo = albedo * (0.72 + 0.30 * ring[..., None] + 0.16 * stri[..., None])
    albedo *= 0.92 + 0.12 * pores[..., None]
    # Dark growth grooves and a stained base.
    groove = (1.0 - wt.smoothstep(0.55, 0.98, stri)) * 0.22
    albedo *= (1.0 - groove[..., None]) * (1.0 - 0.20 * (1.0 - wt.smoothstep(0.0, 0.18, v)))
    height = 0.50 * ring + 0.24 * stri + 0.14 * pores
    normal = wt.normal_from_height(height.astype(np.float32), strength=2.4)
    rough = 0.36 + 0.20 * (1.0 - grad) + 0.10 * pores
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, "horn_albedo.png"))
    write_rgb(normal, out_path(out_dir, "horn_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, "horn_roughness.png"))
    print("HORN", mob, kind, detail_stats(np.clip(albedo, 0, 1)))


def bone_maps(mob: str, out_dir: Path) -> None:
    palette = STYLES[mob].get("bone", (0.70, 0.64, 0.50))
    size = 1024
    base = np.array(palette, np.float32)[None, None, :]
    f1, f2, _ = wt.cellular(size, size, 9, 9, SEED + 61)
    cracks = 1.0 - wt.smoothstep(0.0, 2.2, np.abs(f2 - f1) / max(1.0, size / 9.0))
    pores = wt.fbm(size, size, 120, 120, SEED + 62, octaves=4)
    stains = wt.fbm(size, size, 6, 6, SEED + 63, octaves=5)
    grain = wt.fbm(size, size, 45, 18, SEED + 64, octaves=4)
    albedo = base * (0.98 + 0.22 * grain[..., None]) * (0.93 + 0.14 * pores[..., None])
    albedo *= 1.0 - 0.24 * stains[..., None]
    albedo *= 1.0 - 0.38 * cracks[..., None]
    albedo *= 1.08
    height = 0.42 * grain + 0.20 * pores - 0.60 * cracks
    normal = wt.normal_from_height(height.astype(np.float32), strength=2.0)
    rough = 0.48 + 0.16 * (1.0 - grain) + 0.10 * cracks
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, "bone_albedo.png"))
    write_rgb(normal, out_path(out_dir, "bone_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, "bone_roughness.png"))
    print("BONE", mob, detail_stats(np.clip(albedo, 0, 1)))


def membrane_maps(mob: str, out_dir: Path) -> None:
    style = STYLES[mob]
    base_col = np.array(style.get("membrane", (0.2, 0.03, 0.04)), np.float32)
    size = 1024
    wrinkle = wt.fbm(size, size, 9, 22, SEED + 71, octaves=5, ridge=True)
    fine = wt.fbm(size, size, 55, 55, SEED + 72, octaves=4)
    albedo = base_col[None, None, :] * (0.55 + 0.55 * wrinkle[..., None])
    albedo *= 0.86 + 0.22 * fine[..., None]
    veins = _vein_layer(size, (18, 0, 3), SEED + 73, roots=16,
                        alpha=0.72, direction="edge")
    albedo = overlay_rgba(albedo, veins)
    # Raised vessels + wrinkle relief.
    height = 0.30 * wrinkle + 0.34 * veins[..., 0] + 0.10 * fine
    normal = wt.normal_from_height(height.astype(np.float32), strength=1.8)
    rough = 0.48 + 0.18 * (1.0 - veins[..., 0]) + 0.10 * fine
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, "membrane_albedo.png"))
    write_rgb(normal, out_path(out_dir, "membrane_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, "membrane_roughness.png"))
    print("MEMBRANE", mob, detail_stats(np.clip(albedo, 0, 1)))


def cloth_maps(mob: str, out_dir: Path) -> None:
    style = STYLES[mob]
    col = np.array(style.get("cloth", (0.12, 0.09, 0.06)), np.float32)
    size = 1024
    u = np.arange(size, dtype=np.float32)[None, :] / size
    v = np.arange(size, dtype=np.float32)[:, None] / size
    weave = 0.5 + 0.5 * np.sin(u * math.tau * 92.0) * np.sin(v * math.tau * 92.0)
    slub = wt.fbm(size, size, 11, 70, SEED + 81, octaves=4)
    fuzz = wt.fbm(size, size, 140, 140, SEED + 82, octaves=3)
    albedo = col[None, None, :] * (0.70 + 0.38 * weave[..., None] + 0.18 * slub[..., None])
    albedo *= 0.92 + 0.12 * fuzz[..., None]
    height = 0.35 * weave + 0.22 * slub + 0.10 * fuzz
    normal = wt.normal_from_height(height.astype(np.float32), strength=1.3)
    rough = 0.88 + 0.08 * fuzz
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, "cloth_albedo.png"))
    write_rgb(normal, out_path(out_dir, "cloth_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, "cloth_roughness.png"))
    print("CLOTH", mob, detail_stats(np.clip(albedo, 0, 1)))


def stone_maps(mob: str, out_dir: Path, size: int = 2048, prefix: str = "stone",
               palette=None) -> None:
    style = STYLES[mob]
    dark, light = palette if palette else (style.get("stone", (0.20, 0.21, 0.20)),
                                           tuple(min(1.0, c * 2.4) for c in style.get("stone", (0.20, 0.21, 0.20))))
    a = np.array(dark, np.float32)[None, None, :]
    b = np.array(light, np.float32)[None, None, :]
    macro = wt.fbm(size, size, 4, 4, SEED + 91, octaves=6)
    meso = wt.fbm(size, size, 13, 13, SEED + 92, octaves=5, ridge=True)
    micro = wt.fbm(size, size, 90, 90, SEED + 93, octaves=4)
    f1, f2, _ = wt.cellular(size, size, 7, 7, SEED + 94)
    crack = 1.0 - wt.smoothstep(0.0, 2.6, np.abs(f2 - f1) / max(1.0, size / 7.0))
    f1b, f2b, _ = wt.cellular(size, size, 19, 19, SEED + 95)
    crack2 = 1.0 - wt.smoothstep(0.0, 2.0, np.abs(f2b - f1b) / max(1.0, size / 19.0))
    crack = np.clip(crack + crack2 * 0.7, 0, 1)
    albedo = wt.mix(a, b, wt.smoothstep(0.22, 0.82, 0.55 * macro + 0.35 * meso + 0.10 * micro))
    albedo *= 0.86 + 0.30 * micro[..., None]
    albedo *= 1.0 - 0.42 * crack[..., None]
    # Moss/lichen settles in cavities, with a little dry ochre.
    moss_mask = wt.smoothstep(0.42, 0.78, wt.fbm(size, size, 6, 6, SEED + 96, octaves=4)) * np.clip(0.8 * crack + 0.3 * (1.0 - micro), 0, 1)
    moss = np.array(style.get("moss", (0.19, 0.24, 0.10)), np.float32)[None, None, :]
    albedo = albedo * (1.0 - 0.56 * moss_mask[..., None]) + moss * (0.56 * moss_mask[..., None]) * (0.8 + 0.5 * micro[..., None])
    # Chipped pits and pale dust on high points.
    pits = wt.smoothstep(0.62, 0.88, wt.fbm(size, size, 45, 45, SEED + 97, octaves=4))
    albedo *= 1.0 - 0.20 * pits[..., None]
    height = 0.45 * macro + 0.22 * meso + 0.12 * micro - 0.65 * crack
    normal = wt.normal_from_height(height.astype(np.float32), strength=2.6)
    rough = 0.70 + 0.16 * (1.0 - meso) + 0.08 * moss_mask
    # Ember fissures: a sparse subset of deep cracks, orange, low intensity.
    ember_sel = wt.smoothstep(0.74, 0.92, wt.fbm(size, size, 5, 5, SEED + 98, octaves=4)) * crack
    ember_col = np.array(style.get("ember", (1.0, 0.20, 0.025)), np.float32)[None, None, :]
    emission = ember_col * np.clip(ember_sel, 0, 1)[..., None] * 0.9
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, f"{prefix}_albedo.png"))
    write_rgb(normal, out_path(out_dir, f"{prefix}_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, f"{prefix}_roughness.png"))
    write_rgb(np.clip(emission, 0, 1), out_path(out_dir, f"{prefix}_emission.png"))
    print("STONE", mob, prefix, detail_stats(np.clip(albedo, 0, 1)))


def fur_maps(mob: str, out_dir: Path, prefix: str = "fur") -> None:
    style = STYLES[mob]
    col = np.array(style.get("fur", (0.07, 0.05, 0.035)), np.float32)
    size = 1024
    strand = wt.fbm(size, size, 5, 95, SEED + 101, octaves=5, wrap="x")
    fine = wt.fbm(size, size, 140, 18, SEED + 102, octaves=4, wrap="x")
    clump = wt.fbm(size, size, 6, 30, SEED + 103, octaves=4, wrap="x")
    v = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None, None]
    tip = col * 2.5 + 0.035
    albedo = (col[None, None, :] * (1.0 - v) + tip * v)
    albedo = albedo * (0.70 + 0.55 * strand[..., None] + 0.18 * fine[..., None])
    albedo = albedo * (0.90 + 0.25 * clump[..., None])
    height = 0.55 * strand + 0.20 * fine
    normal = wt.normal_from_height(height.astype(np.float32), strength=2.2)
    rough = 0.78 + 0.15 * fine
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, f"{prefix}_albedo.png"))
    write_rgb(normal, out_path(out_dir, f"{prefix}_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, f"{prefix}_roughness.png"))
    print("FUR", mob, prefix, detail_stats(np.clip(albedo, 0, 1)))


def beast_coat(out_dir: Path) -> None:
    """Extract the wolf coat, char it, and add a high-frequency fur detail pass."""
    base = extract_glb_image(ROOT / "assets" / "characters" / "ironwood_wolf.glb", 0, 1024)
    style = STYLES["beast"]
    size = base.shape[0]
    lum = luminance(base)[..., None]
    col = np.array(style["fur"], np.float32)[None, None, :]
    # Keep the coat's markings and value structure, but burn it toward charcoal.
    albedo = base * 0.22 + col * (0.50 + 1.25 * lum)
    albedo *= 0.82 + 0.30 * wt.fbm(size, size, 10, 10, SEED + 111, octaves=4)[..., None]
    strand = wt.fbm(size, size, 4, 110, SEED + 112, octaves=5, wrap="x")
    fine = wt.fbm(size, size, 150, 20, SEED + 113, octaves=3, wrap="x")
    albedo *= 0.82 + 0.32 * strand[..., None] + 0.10 * fine[..., None]
    # Charred patches and ember fissures.
    char = wt.smoothstep(0.58, 0.82, wt.fbm(size, size, 5, 5, SEED + 114, octaves=4))
    albedo *= 1.0 - 0.55 * char[..., None]
    f1, f2, _ = wt.cellular(size, size, 8, 8, SEED + 115)
    crack = 1.0 - wt.smoothstep(0.0, 2.0, np.abs(f2 - f1) / max(1.0, size / 8.0))
    sel = wt.smoothstep(0.54, 0.80, wt.fbm(size, size, 4, 4, SEED + 116, octaves=4))
    ember = np.array(style["ember"], np.float32)[None, None, :]
    emission = ember * (crack * sel)[..., None]
    albedo = np.clip(albedo + emission * 0.35, 0, 1)
    height = 0.42 * strand + 0.26 * crack + 0.18 * fine
    normal = wt.normal_from_height(height.astype(np.float32), strength=2.4)
    rough = 0.80 + 0.12 * fine
    write_rgb(np.clip(albedo, 0, 1), out_path(out_dir, "beast_coat_albedo.png"))
    write_rgb(normal, out_path(out_dir, "beast_coat_normal.png"))
    write_rgb(np.repeat(np.clip(rough, 0, 1)[..., None], 3, axis=-1), out_path(out_dir, "beast_coat_roughness.png"))
    write_rgb(np.clip(emission, 0, 1), out_path(out_dir, "beast_coat_emission.png"))
    print("BEAST_COAT", detail_stats(np.clip(albedo, 0, 1)))


# ---------------------------------------------------------------------------
# GLB helper


def extract_glb_image(path: Path, index: int, size: int | None = None) -> np.ndarray:
    raw = path.read_bytes()
    json_len = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_len])
    offset = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<II", raw, offset)
    offset += 8
    bin_data = raw[offset:offset + bin_len]
    img = doc["images"][index]
    view = doc["bufferViews"][img["bufferView"]]
    data = bin_data[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
    from io import BytesIO
    im = Image.open(BytesIO(data)).convert("RGB")
    if size and im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def out_path(root: Path, name: str) -> Path:
    return root / "textures" / name


# ---------------------------------------------------------------------------
# Build


def build_mob(mob: str) -> None:
    out_dir = OUT_ROOT / mob
    out_dir.mkdir(parents=True, exist_ok=True)
    print("TEXTURE_BUILD", mob, out_dir)
    if mob in ("succubus", "spawn"):
        skin_maps(mob, out_dir)
        leather_maps(mob, out_dir)
        hair_maps(mob, out_dir)
        eye_maps(mob, out_dir)
        horn_maps(mob, out_dir)
        cloth_maps(mob, out_dir)
        if mob == "succubus":
            membrane_maps(mob, out_dir)
    elif mob == "hell_goat":
        skin_maps(mob, out_dir)
        leather_maps(mob, out_dir)
        eye_maps(mob, out_dir)
        horn_maps(mob, out_dir)
        bone_maps(mob, out_dir)
        fur_maps(mob, out_dir)
        cloth_maps(mob, out_dir)
    elif mob == "gargoyle":
        stone_maps(mob, out_dir)
        horn_maps(mob, out_dir)  # kind == stone -> horn_* stone maps
        eye_maps(mob, out_dir)
        cloth_maps(mob, out_dir)
    elif mob == "beast":
        beast_coat(out_dir)
        horn_maps(mob, out_dir)
        fur_maps(mob, out_dir)
    else:
        raise SystemExit(f"Unknown mob: {mob}")
    print("TEXTURE_DONE", mob)


def main(argv=None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mobs", nargs="*", default=["all"])
    args = parser.parse_args(argv)
    mobs = args.mobs
    if not mobs or mobs == ["--"]:
        mobs = ["all"]
    if "--" in mobs:
        mobs = mobs[mobs.index("--") + 1:]
    if mobs == ["all"] or not mobs:
        mobs = ["succubus", "hell_goat", "gargoyle", "spawn", "beast"]
    for mob in mobs:
        build_mob(mob)


if __name__ == "__main__":
    main(sys.argv[1:])
