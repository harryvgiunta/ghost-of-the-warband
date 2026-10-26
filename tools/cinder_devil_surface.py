"""Analytic surface fields for the Cinder devil.

Two materials are original to this creature:

``char``  carbonised hide. Broad heat-cracked plates with soot-black seams, a
          granular crust on the crests and hairline fissures that still carry
          heat — the emission is deliberately weak here, because the body reads
          as an ember-bed that has been burning a long time, not as a lamp.
``ash``   the pale desiccated crust that settles on the shoulders, forearms,
          skull crest and hooves where the fire blows over the body.

Everything else (bone teeth and claws, cured hide straps, burnt cloth, the
void inside the maw and the hot ember itself) is the shared Unholy Forest
surface library, sampled through the same entry point so one bake pass covers
the whole creature.

This module duck-types ``tools/forest_surface.py`` for the shared Blender
stage: same ``sample`` contract, same ``normal_map``.
"""

from __future__ import annotations

import math

import numpy as np

import cinder_devil_styles as _styles
import forest_surface as _forest

# The shared fields are sampled through the forest module; these two are ours.
_OWN_SURFACES = ("char", "ash")

SURFACES: tuple[str, ...] = tuple(_styles.SURFACES)

_CHUNK = _forest._CHUNK


def _rough_range(surface: str) -> tuple[float, float]:
    lo, hi = _styles.SURFACES[surface]["rough"]
    return float(lo), float(hi)


def _warp(p: np.ndarray, tab: np.ndarray, seed: int, amount: float) -> np.ndarray:
    """Isotropic domain warp, so scorch patterns never read as a lattice."""
    q = p.copy()
    for axis in range(3):
        drift = _forest._fbm3(p, (4.5, 4.5, 4.5), seed + 3 + axis, tab, 2) - 0.5
        q[:, axis] = p[:, axis] + drift * amount
    return q


def _char(p, pal, seed, g, along, axis, tab):
    """Carbonised hide: heat-cracked plates, soot seams, fissures still warm.

    The plates are a ridged field at body scale, cut again by a coarse crack
    network. Colour stays in the bottom of the value range on purpose — this is
    burnt skin, and its darkness is what makes the ember seams read.
    """
    soot = _forest._colour(pal, "soot", "seam")
    carbon = _forest._colour(pal, "carbon", "soot")
    plate_c = _forest._colour(pal, "plate", "carbon")
    seam_c = _forest._colour(pal, "seam", "soot")
    sheen_c = _forest._colour(pal, "sheen", "plate")
    heat_c = _forest._colour(pal, "ember_seam", "sheen")

    q = _warp(p, tab, seed, 0.030)

    # Two plate scales: the big scute pattern, then smaller scales on its crests.
    plate = _forest._smoothstep(
        0.26, 0.74, _forest._ridged(_forest._fbm3(q, (6.5, 6.5, 6.5), seed + 11, tab, 3))
    )
    fine_plate = _forest._smoothstep(
        0.40, 0.90, _forest._ridged(_forest._value3(q, (26.0, 26.0, 26.0), seed + 13, tab))
    )
    # The primary fissure network: long connected cracks with hot centres.
    crack = _forest._smoothstep(
        0.88, 0.998, _forest._ridged(_forest._fbm3(q, (2.2, 2.2, 2.2), seed + 17, tab, 4))
    )
    hairline = _forest._smoothstep(
        0.74, 0.98, _forest._ridged(_forest._value3(q, (48.0, 48.0, 48.0), seed + 19, tab))
    )
    grain = _forest._value3(q, (170.0, 170.0, 170.0), seed + 23, tab)
    soot_grain = _forest._fbm3(q, (34.0, 34.0, 34.0), seed + 29, tab, 2)
    crust = _forest._smoothstep(0.62, 0.94, _forest._fbm3(q, (9.0, 9.0, 9.0), seed + 31, tab, 2))

    # Heat gathers toward the core of the body and dies away at the extremities:
    # ``g`` is the material's base-to-tip coordinate, so the hands and hooves
    # cool off while the ribs burn.
    heat = crack * (0.30 + 0.70 * _forest._smoothstep(0.10, 0.90, g))
    heat = np.clip(heat * (0.55 + 0.65 * crust) + 0.10 * hairline * crack, 0.0, 1.0)

    relief = (0.62 * plate + 0.18 * fine_plate + 0.05 * (grain - 0.5)
              + 0.06 * crust - 0.30 * (1.0 - plate) - 0.34 * crack - 0.10 * hairline)
    height = np.clip(relief * 1.05 + 0.28, 0.0, 1.0)

    crest = _forest._smoothstep(0.58, 0.96, plate)
    col = _forest._mixc(soot, carbon, 0.75 * _forest._smoothstep(0.18, 0.66, plate))
    col = _forest._mixc(col, plate_c, 0.60 * crest)
    col = _forest._mixc(col, sheen_c, 0.34 * crest * fine_plate)
    col = _forest._mixc(col, seam_c, 0.85 * (1.0 - plate) + 0.60 * crack)
    col = _forest._mixc(col, heat_c, 0.55 * heat)
    shade = np.clip((0.78 + 0.30 * grain) * (1.0 - 0.42 * crack - 0.18 * hairline), 0.02, 1.15)
    albedo = np.clip(col * shade[..., None], 0.0, 1.0)

    lo, hi = _rough_range("char")
    rt = np.clip(0.30 + 0.40 * (1.0 - plate) + 0.22 * crust
                 + 0.20 * crack - 0.22 * crest * fine_plate, 0.0, 1.0)

    # Weak, mottled heat in the deepest fissures only. The dedicated ember
    # geometry carries the real glow; this is the skin still smouldering.
    emission = np.clip(heat_c[None, :] * (0.30 * heat)[..., None] * np.clip(1.0 - soot_grain, 0.2, 1.0)[..., None],
                       0.0, 1.0) * 0.55
    return albedo, height, lo + (hi - lo) * rt, emission


def _ash(p, pal, seed, g, along, axis, tab):
    """Powdered crust: pale, granular, high friction, dry to the point of chalk."""
    pale_c = _forest._colour(pal, "pale", "sift")
    grey_c = _forest._colour(pal, "grey", "dark")
    dark_c = _forest._colour(pal, "dark", "grey")
    sift_c = _forest._colour(pal, "sift", "pale")

    q = _warp(p, tab, seed + 5, 0.020)

    drift = _forest._fbm3(q, (5.5, 5.5, 5.5), seed + 41, tab, 2)
    clump = _forest._smoothstep(
        0.28, 0.82, _forest._fbm3(q, (17.0, 17.0, 17.0), seed + 43, tab, 3)
    )
    grain = _forest._value3(q, (290.0, 290.0, 290.0), seed + 47, tab)
    flake = _forest._smoothstep(
        0.55, 0.95, _forest._ridged(_forest._value3(q, (60.0, 60.0, 60.0), seed + 53, tab))
    )
    # Ash sifts off the high, exposed crests and packs into the low hollows.
    sift = _forest._smoothstep(0.50, 0.92,
                               _forest._fbm3(q, (38.0, 38.0, 38.0), seed + 59, tab, 2))

    col = _forest._mixc(dark_c, grey_c, drift)
    col = _forest._mixc(col, pale_c, 0.75 * clump)
    col = _forest._mixc(col, sift_c, 0.55 * sift)
    shade = np.clip((0.86 + 0.26 * grain) * (1.0 - 0.22 * flake), 0.10, 1.15)
    albedo = np.clip(col * shade[..., None], 0.0, 1.0)

    height = np.clip(0.46 + 0.16 * clump + 0.07 * (grain - 0.5)
                     + 0.05 * flake - 0.10 * sift, 0.0, 1.0)
    lo, hi = _rough_range("ash")
    rt = np.clip(0.45 + 0.40 * clump + 0.20 * grain - 0.25 * sift, 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, None


def _ember(p, pal, seed, g, along, axis, tab):
    """Hot internal light, driven by its own turbulent field.

    The shared forest ember is a radial iris around one face. The cinder body
    needs heat in sockets at 2.0 m, in the sternum at 1.5 m and in back seams at
    1.3 m, so a material-wide height gradient would put the white-hot core in
    whatever geometry happened to sit mid-body and leave the eyes a flat dark
    disc. This field is location-independent: every emissive surface gets its
    own hot cores and cool crust.
    """
    core_c = _forest._colour(pal, "core", "iris")
    iris_c = _forest._colour(pal, "iris", "core")
    outer_c = _forest._colour(pal, "outer", "iris")

    q = _warp(p, tab, seed + 7, 0.012)
    heat = _forest._fbm3(q, (7.0, 7.0, 7.0), seed + 181, tab, 3)
    fine = _forest._value3(q, (64.0, 64.0, 64.0), seed + 183, tab)
    fibre = _forest._value3(q, (180.0, 180.0, 180.0), seed + 191, tab)
    heat = np.clip(heat * 1.30 + (fine - 0.5) * 0.26 - 0.16, 0.0, 1.0)

    col = _forest._mixc(outer_c, iris_c, _forest._smoothstep(0.16, 0.60, heat))
    col = _forest._mixc(col, core_c, _forest._smoothstep(0.62, 0.94, heat))
    glow = 0.42 + 1.05 * heat + 0.10 * (fibre - 0.5)
    emission = np.clip(col * glow[..., None], 0.0, 1.0)
    albedo = np.clip(col * (0.06 + 0.10 * heat)[..., None] + 0.004, 0.0, 1.0)
    height = np.clip(0.50 + 0.07 * (fibre - 0.5) + 0.09 * heat, 0.0, 1.0)
    lo, hi = _rough_range("ember")
    rt = np.clip(0.12 + 0.75 * (1.0 - heat) + 0.10 * fibre, 0.0, 1.0)
    return albedo, height, lo + (hi - lo) * rt, emission


def _void(p, pal, seed, g, along, axis, tab):
    """The inside of a socket or a maw: black, with a faint warm floor."""
    depth_c = _forest._colour(pal, "depth", "rim")
    floor_c = _forest._colour(pal, "floor", "depth")
    rim_c = _forest._colour(pal, "rim", "floor")

    q = _warp(p, tab, seed + 11, 0.010)
    drift = _forest._fbm3(q, (3.2, 3.2, 3.2), seed + 173, tab, 2)
    smoke = _forest._fbm3(q, (11.0, 11.0, 11.0), seed + 179, tab, 2)
    warm = _forest._smoothstep(0.70, 0.98, _forest._fbm3(q, (6.0, 6.0, 6.0), seed + 181, tab, 2))

    col = _forest._mixc(depth_c, floor_c, 0.25 + 0.70 * drift)
    col = _forest._mixc(col, rim_c, np.clip(0.60 * warm + 0.12 * smoke, 0.0, 1.0))
    height = np.clip(0.45 + 0.10 * (smoke - 0.5) + 0.06 * (drift - 0.5), 0.0, 1.0)
    lo, hi = _rough_range("void")
    rt = np.clip(0.55 + 0.35 * (1.0 - warm) + 0.10 * smoke, 0.0, 1.0)
    return col, height, lo + (hi - lo) * rt, None


def _horn(p, pal, seed, g, along, axis, tab):
    """Horn keratin: burnt at the root, dull horn at the tip, never ivory.

    Growth rings band the length, longitudinal striae run up it and a coarse
    crack network breaks the surface. The palette ramp is deliberately short —
    a bright tip is what makes a horn read as antler or tusk.
    """
    core_c = _forest._colour(pal, "core", "ridge")
    ridge_c = _forest._colour(pal, "ridge", "core")
    tip_c = _forest._colour(pal, "tip", "ridge")
    stain_c = _forest._colour(pal, "stain", "ridge")

    q = _warp(p, tab, seed + 5, 0.010)
    turb = _forest._fbm3(q, (5.0, 5.0, 5.0), seed + 201, tab, 2) - 0.5
    rings = 0.5 + 0.5 * np.sin((g * 34.0 + turb * 6.0) * math.pi)
    striae = _forest._value3(q, (26.0, 26.0, 5.0), seed + 203, tab)
    crack = _forest._smoothstep(
        0.84, 0.995, _forest._ridged(_forest._fbm3(q, (3.2, 3.2, 3.2), seed + 207, tab, 3))
    )

    col = _forest._mixc(core_c, ridge_c, _forest._smoothstep(0.0, 0.42, g))
    col = _forest._mixc(col, tip_c, 0.80 * _forest._smoothstep(0.58, 0.98, g))
    col = _forest._mixc(col, stain_c, 0.40 * (1.0 - _forest._smoothstep(0.0, 0.26, g)))
    shade = np.clip((0.70 + 0.52 * rings) * (0.86 + 0.26 * striae), 0.30, 1.28)
    col = np.clip(col * shade[..., None], 0.0, 1.0)
    col = _forest._mixc(col, core_c, 0.72 * crack)

    height = np.clip(0.46 + 0.13 * rings + 0.07 * striae - 0.22 * crack, 0.0, 1.0)
    lo, hi = _rough_range("horn")
    rt = np.clip(0.34 + 0.30 * (1.0 - rings) + 0.18 * striae + 0.14 * crack, 0.0, 1.0)
    return np.clip(col, 0.0, 0.42), height, lo + (hi - lo) * rt, None


_OWN_SAMPLERS = {
    "char": _char,
    "ash": _ash,
    "horn": _horn,
    "ember": _ember,
    "void": _void,
}

# Surfaces whose atlas carries an emission map.
_EMISSIVE = ("char", "ember")


def sample(
    surface: str,
    points: np.ndarray,
    palette: dict[str, str],
    seed: int,
    grade: tuple[int, float, float] = (2, 0.0, 1.0),
) -> dict[str, np.ndarray | None]:
    """Sample one cinder material at rest-space points.

    Same contract as :func:`forest_surface.sample`: ``points`` is ``(N, 3)``
    float32 metres in Blender axes, ``grade`` is ``(axis, low, high)``, and the
    result carries display-space ``albedo``, ``height``, ``roughness`` inside
    the surface's declared range and ``emission`` or ``None``.
    """
    if surface not in _OWN_SAMPLERS:
        return _forest.sample(surface, points, palette, seed, grade)

    pts = np.asarray(points, dtype=np.float32)
    if pts.ndim == 1 and pts.size == 3:
        pts = pts.reshape(1, 3)
    if pts.ndim != 2 or pts.shape[1] != 3:
        raise ValueError(f"points must be (N, 3), got {pts.shape}")

    n = int(pts.shape[0])
    sampler = _OWN_SAMPLERS[surface]
    tab = _forest._table(seed)

    albedo = np.empty((n, 3), np.float32)
    height = np.empty(n, np.float32)
    roughness = np.empty(n, np.float32)
    emission = np.zeros((n, 3), np.float32)

    for start in range(0, n, _CHUNK):
        stop = min(start + _CHUNK, n)
        chunk = np.nan_to_num(np.asarray(pts[start:stop], np.float32),
                              nan=0.0, posinf=1e4, neginf=-1e4)
        np.clip(chunk, -1e4, 1e4, out=chunk)
        g, along, axis = _forest._grade_values(chunk, grade)
        a, h, r, e = sampler(chunk, palette, int(seed), g, along, axis, tab)
        albedo[start:stop] = np.clip(a, 0.0, 1.0)
        height[start:stop] = np.clip(h, 0.0, 1.0)
        lo, hi = _rough_range(surface)
        roughness[start:stop] = np.clip(r, lo, hi)
        if e is not None:
            emission[start:stop] = np.clip(e, 0.0, 1.0)

    return {
        "albedo": albedo,
        "height": height,
        "roughness": roughness,
        "emission": emission if surface in _EMISSIVE else None,
    }


# The shared stage imports ``normal_map`` alongside ``sample``.
normal_map = _forest.normal_map


def _validate() -> list[str]:
    """Cheap assertions over both authored fields, runnable outside Blender."""
    problems: list[str] = []
    points = np.array(
        [[x, y, z] for x in (-0.4, 0.0, 0.4) for y in (-0.4, 0.0, 0.4)
         for z in (0.05, 1.0, 2.1)],
        np.float32,
    )
    for surface in _OWN_SURFACES:
        pal = _styles.palette("cinder_devil", surface)
        result = sample(surface, points, pal, _styles.SEED, (2, 0.0, 2.2))
        for key in ("albedo", "height", "roughness"):
            values = np.asarray(result[key])
            if values.shape[0] != points.shape[0]:
                problems.append(f"{surface}.{key} row count {values.shape[0]}")
            if not np.all(np.isfinite(values)):
                problems.append(f"{surface}.{key} not finite")
        lo, hi = _rough_range(surface)
        rough = np.asarray(result["roughness"])
        if rough.min() < lo - 1e-6 or rough.max() > hi + 1e-6:
            problems.append(f"{surface}.roughness outside {lo}..{hi}")
        albedo = np.asarray(result["albedo"])
        if albedo.min() < 0.0 or albedo.max() > 1.0:
            problems.append(f"{surface}.albedo outside 0..1")
        # Chunking must not change a texel: the same point sampled alone and
        # inside a batch has to agree exactly.
        whole = np.asarray(result["albedo"])
        for index in (0, points.shape[0] // 2, points.shape[0] - 1):
            alone = np.asarray(
                sample(surface, points[index:index + 1], pal, _styles.SEED, (2, 0.0, 2.2))["albedo"]
            )[0]
            if not np.allclose(alone, whole[index], atol=1e-6):
                problems.append(f"{surface}.albedo changes with batch size at {index}")
        if surface == "char":
            mean_value = float(np.mean(albedo))
            if mean_value > 0.26:
                problems.append(f"char too bright for burnt hide ({mean_value:.3f})")
            emission = np.asarray(result["emission"])
            if float(np.max(emission)) <= 0.01:
                problems.append("char carries no heat emission at all")
            if float(np.mean(emission)) > 0.12:
                problems.append("char emission is too even to read as fissures")
        if surface == "ash":
            if float(np.mean(albedo)) < 0.14:
                problems.append("ash is not pale enough to read as crust")
    return problems


def main() -> int:
    problems = _validate()
    for problem in problems:
        print("CINDER_SURFACE_PROBLEM", problem)
    samples = _forest._slab_points(4096)
    for surface in _OWN_SURFACES:
        pal = _styles.palette("cinder_devil", surface)
        result = sample(surface, samples, pal, _styles.SEED, (2, 0.0, 2.2))
        print(
            "CINDER_SURFACE",
            surface,
            "albedo_mean", round(float(np.mean(result["albedo"])), 4),
            "height_mean", round(float(np.mean(result["height"])), 4),
            "rough_mean", round(float(np.mean(result["roughness"])), 4),
        )
    print("CINDER_SURFACE_OK" if not problems else "CINDER_SURFACE_FAIL", len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
