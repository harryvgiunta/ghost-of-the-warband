#!/usr/bin/env python3
"""Ironwood devil fur tile.

The Hellish goat man's coat used to be a proxy: a separate black shell of spike
geometry spiked out of the body, which read as fur made of thorns in a fight.
This script authors the coat as a surface instead - a seamless tile of hair
strands with the albedo and relief of jet-black goat fur, shipped beside the
devils' sources and worn by the fitted body skin's own material.

Deterministic and offline (numpy + Pillow, the same two the world textures use):
fixed seed, no timestamps, so

    python tools/devil_fur.py

rewrites ``assets/characters/devils/ironwood_devil_fur.png`` (albedo),
``ironwood_devil_fur_n.png`` (tangent normal, OpenGL +Y) and
``ironwood_devil_fur.json`` byte-identically.

Authoring model
---------------
* Everything is periodic in u and v by construction - every field is either a
  cosine of an integer number of turns or a value-noise lattice whose integer
  cells wrap - so the tile is seamless before mipmapping, not patched after.
* A strand is a rounded cross-section in u, leaning with a slow drift field and
  broken into three scales (a coarse guard-hair layer, a mid layer and a few
  long locks), with per-strand brightness keyed off the strand index so no two
  neighbours catch the light the same way.
* Hair is dark at the root and lifts at the crown: the albedo is a three-stop
  ramp (root -> body -> tip) with a cool sheen only on the crowns, authored in
  display space like the world textures (nothing is linearised).
* The normal map is the central-difference gradient of that same height field,
  so the relief in the render is the relief in the paint.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "characters" / "devils"
ALBEDO = OUT / "ironwood_devil_fur.png"
NORMAL = OUT / "ironwood_devil_fur_n.png"
MANIFEST = OUT / "ironwood_devil_fur.json"

SIZE = 512
SEED = 20261106
## Strand layers: (strands across the tile, weight, seed offset, lean). All
## three counts divide the lattice so the cosine closes exactly at the seam, and
## `lean` is a whole number of strands across the full height - the comb runs
## down the tile at a slight diagonal and still meets itself at the edge.
LAYERS = ((56, 1.00, 3, 2), (112, 0.42, 4, 3), (27, 0.62, 5, 1))
## Display-space stops of the coat, root to crown. Neutral to a hair cool, not
## warm: a black goat reads brown the moment the crown stops are biased red.
ROOT_COLOR = (0.024, 0.024, 0.026)
BODY_COLOR = (0.056, 0.057, 0.062)
TIP_COLOR = (0.132, 0.134, 0.145)
## A cool cast on the crowns only: black goat fur is not brown, and a dead-flat
## grey reads as plastic at gameplay distance.
SHEEN_COLOR = (0.020, 0.024, 0.032)
## How steep the strand relief is, in normal-map slope per texel.
NORMAL_SLOPE = 4.0


def _hash(ix, iy, seed):
    """One deterministic 16-bit value per integer lattice point."""
    h = (np.asarray(ix, dtype=np.int64) * 374761393
         + np.asarray(iy, dtype=np.int64) * 668265263
         + int(seed) * 2654435761) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float64) / 65535.0


def noise(u, v, cells_u, cells_v, seed):
    """Value noise on a lattice that wraps at `cells_u` x `cells_v`: periodic."""
    x = u * cells_u
    y = v * cells_v
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = x - ix
    fy = y - iy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    ix0 = ix % cells_u
    iy0 = iy % cells_v
    ix1 = (ix + 1) % cells_u
    iy1 = (iy + 1) % cells_v
    n00 = _hash(ix0, iy0, seed)
    n10 = _hash(ix1, iy0, seed)
    n01 = _hash(ix0, iy1, seed)
    n11 = _hash(ix1, iy1, seed)
    return (n00 * (1.0 - fx) + n10 * fx) * (1.0 - fy) \
        + (n01 * (1.0 - fx) + n11 * fx) * fy


def strand_height(u, v):
    """The coat's relief, 0 in the gap between strands to 1 on a crown."""
    # The flow is a *shear*: the whole comb leans with a field that changes
    # slowly across the tile and faster down it, so the strands wave like hair
    # rather than curling into loops where a fast field doubles back on itself.
    lean = (noise(u, v, 2, 3, SEED + 1) - 0.5) * 0.075 \
        + (noise(u, v, 3, 7, SEED + 2) - 0.5) * 0.022
    x = (u + lean) % 1.0
    total = np.zeros_like(u)
    weight = 0.0
    for cells, share, offset, lean_strands in LAYERS:
        drift = (noise(u, v, 2, 4, SEED + offset) - 0.5) * 0.30
        xc = (x + drift + v * float(lean_strands) / cells) % 1.0
        profile = (0.5 + 0.5 * np.cos(2.0 * np.pi * xc * cells)) ** 1.7
        index = np.floor(xc * cells).astype(np.int64) % cells
        shade = 0.55 + 0.90 * _hash(index, 0, SEED + offset)
        total += share * profile * shade
        weight += share
    strands = total / weight
    clump = noise(u, v, 6, 4, SEED + 6) * 0.55 \
        + noise(u, v, 17, 11, SEED + 7) * 0.30 \
        + noise(u, v, 41, 27, SEED + 8) * 0.15
    return np.clip(strands * 0.74 + clump * 0.26, 0.0, 1.0)


def albedo(height):
    """The three-stop coat: root, body, crown, plus a cool cast on the crowns."""
    root = np.array(ROOT_COLOR)
    body = np.array(BODY_COLOR)
    tip = np.array(TIP_COLOR)
    sheen = np.array(SHEEN_COLOR)
    lower = np.clip(height * 2.0, 0.0, 1.0)[..., None]
    upper = np.clip(height * 2.0 - 1.0, 0.0, 1.0)[..., None]
    color = root + (body - root) * lower + (tip - body) * upper
    color = color + sheen * np.clip(height - 0.55, 0.0, 1.0)[..., None]
    return np.clip(color, 0.0, 1.0)


def tangent_normals(height):
    """Central-difference gradient of the same relief, OpenGL +Y up."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx = -dx * NORMAL_SLOPE
    ny = -dy * NORMAL_SLOPE
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / length, ny / length, nz / length], axis=-1)


def write_png(path, pixels):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(np.rint(pixels * 255.0), 0.0, 255.0).astype(np.uint8)
    Image.fromarray(data, mode="RGB").save(path, optimize=True)
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build():
    v, u = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64) / float(SIZE)
    height = strand_height(u, v)
    write_png(ALBEDO, albedo(height))
    write_png(NORMAL, tangent_normals(height) * 0.5 + 0.5)
    manifest = {
        "asset": ALBEDO.name,
        "normal": NORMAL.name,
        "size": SIZE,
        "tileable": True,
        "channels": "RGB, display space (authored in paint/display space, nothing linearised)",
        "layers": [{"strands": cells, "weight": share, "lean": lean}
                   for cells, share, _, lean in LAYERS],
        "albedo_stops": {"root": ROOT_COLOR, "body": BODY_COLOR, "tip": TIP_COLOR,
                         "sheen": SHEEN_COLOR},
        "normal_slope": NORMAL_SLOPE,
        "normal_convention": "tangent space, OpenGL (+Y up)",
        "roughness": 0.88,
        "specular": 0.22,
        "used_by": "ironwood_hell_goat: the body surface of its fitted skin "
                   "(material Skin_HellGoat), the coat the removed Fur_HellGoat "
                   "spike proxy used to stand in for",
        "source": "Original procedural work authored by tools/devil_fur.py: "
                  "periodic cosine strand layers and wrap-around value noise. "
                  "No third-party image or scan.",
        "seed": SEED,
        "sha256": {ALBEDO.name: sha256(ALBEDO), NORMAL.name: sha256(NORMAL)},
        "reproducer": "python tools/devil_fur.py",
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("DEVIL_FUR_OK", SIZE, ALBEDO.name, NORMAL.name,
          manifest["sha256"][ALBEDO.name][:12], flush=True)
    return manifest


if __name__ == "__main__":
    build()
