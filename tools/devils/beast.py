"""Hell beast: hulking shaggy quadruped bruiser with bone spikes and tusks.

Reference palette: near-black brown fur with warm ember eyes; exposed flesh on
the muzzle and lower legs; pale keratin on the back ridge, tusks and claws.
Silhouette: bear-like forequarters and shoulder hump over short hindquarters,
broad head, heavy tail, ~1.65 m at the shoulder.
"""

from __future__ import annotations

import math

import numpy as np

from devil_pipeline import (
    TAU,
    add_ellipsoid,
    add_segment,
    build_metaball,
    keyed,
    make_box,
    make_clump_field,
    make_cone,
    make_tube,
    make_uv_sphere,
    part,
)

SCENE = "Beast"
HEIGHT = 1.65

BONES = {
    "root": {"head": (0.0, 0.0, 0.0), "tail": (0.0, 0.0, 0.15), "deform": False},
    "pelvis": {"head": (0.0, -0.62, 1.02), "tail": (0.0, -0.36, 1.08), "parent": "root"},
    "spine_01": {"head": (0.0, -0.36, 1.08), "tail": (0.0, -0.10, 1.14), "parent": "pelvis", "connect": True},
    "spine_02": {"head": (0.0, -0.10, 1.14), "tail": (0.0, 0.18, 1.19), "parent": "spine_01", "connect": True},
    "chest": {"head": (0.0, 0.18, 1.19), "tail": (0.0, 0.36, 1.22), "parent": "spine_02", "connect": True},
    "neck_01": {"head": (0.0, 0.36, 1.22), "tail": (0.0, 0.56, 1.30), "parent": "chest", "connect": True},
    "neck_02": {"head": (0.0, 0.56, 1.30), "tail": (0.0, 0.76, 1.30), "parent": "neck_01", "connect": True},
    "head": {"head": (0.0, 0.76, 1.30), "tail": (0.0, 0.98, 1.18), "parent": "neck_02", "connect": True},
    "jaw": {"head": (0.0, 0.92, 1.14), "tail": (0.0, 1.18, 1.06), "parent": "head"},
    "tail_01": {"head": (0.0, -0.78, 1.02), "tail": (0.0, -0.98, 0.92), "parent": "pelvis"},
    "tail_02": {"head": (0.0, -0.98, 0.92), "tail": (0.0, -1.14, 0.82), "parent": "tail_01", "connect": True},
    "tail_03": {"head": (0.0, -1.14, 0.82), "tail": (0.0, -1.26, 0.74), "parent": "tail_02", "connect": True},
}

for side, sx in (("l", 1.0), ("r", -1.0)):
    BONES.update({
        # Fore chain: every bone shares x = +-0.32 so the sagittal solver is exact.
        f"scapula_{side}": {"head": (sx * 0.20, 0.34, 1.26), "tail": (sx * 0.32, 0.42, 1.04),
                            "parent": "chest"},
        f"upper_fore_{side}": {"head": (sx * 0.32, 0.42, 1.04), "tail": (sx * 0.32, 0.36, 0.72),
                               "parent": "chest"},
        f"lower_fore_{side}": {"head": (sx * 0.32, 0.36, 0.72), "tail": (sx * 0.32, 0.48, 0.40),
                               "parent": f"upper_fore_{side}", "connect": True},
        f"carpus_{side}": {"head": (sx * 0.32, 0.48, 0.40), "tail": (sx * 0.32, 0.54, 0.18),
                           "parent": f"lower_fore_{side}", "connect": True},
        f"front_paw_{side}": {"head": (sx * 0.32, 0.54, 0.18), "tail": (sx * 0.32, 0.64, 0.08),
                              "parent": f"carpus_{side}", "connect": True},
        f"front_toes_{side}": {"head": (sx * 0.32, 0.64, 0.08), "tail": (sx * 0.32, 0.78, 0.06),
                               "parent": f"front_paw_{side}", "connect": True},
        # Hind chain: x = +-0.27.
        f"thigh_{side}": {"head": (sx * 0.27, -0.58, 1.02), "tail": (sx * 0.27, -0.40, 0.66),
                          "parent": "pelvis"},
        f"shin_{side}": {"head": (sx * 0.27, -0.40, 0.66), "tail": (sx * 0.27, -0.50, 0.34),
                         "parent": f"thigh_{side}", "connect": True},
        f"hock_{side}": {"head": (sx * 0.27, -0.50, 0.34), "tail": (sx * 0.27, -0.38, 0.16),
                         "parent": f"shin_{side}", "connect": True},
        f"hind_paw_{side}": {"head": (sx * 0.27, -0.38, 0.16), "tail": (sx * 0.27, -0.24, 0.07),
                             "parent": f"hock_{side}", "connect": True},
        f"hind_toes_{side}": {"head": (sx * 0.27, -0.24, 0.07), "tail": (sx * 0.27, -0.10, 0.05),
                              "parent": f"hind_paw_{side}", "connect": True},
        f"ear_{side}": {"head": (sx * 0.19, 0.80, 1.44), "tail": (sx * 0.30, 0.68, 1.58),
                        "parent": "head"},
    })

CHAINS = {
    "fore_l": {"bones": ["upper_fore_l", "lower_fore_l", "carpus_l", "front_paw_l", "front_toes_l"],
               "pole": 1.0, "fore": True},
    "fore_r": {"bones": ["upper_fore_r", "lower_fore_r", "carpus_r", "front_paw_r", "front_toes_r"],
               "pole": 1.0, "fore": True},
    "hind_l": {"bones": ["thigh_l", "shin_l", "hock_l", "hind_paw_l", "hind_toes_l"], "pole": -1.0},
    "hind_r": {"bones": ["thigh_r", "shin_r", "hock_r", "hind_paw_r", "hind_toes_r"], "pole": -1.0},
}

SKIN_BONES = {
    "pelvis": (0.36, 0.90),
    "spine_01": (0.36, 0.90),
    "spine_02": (0.38, 0.95),
    "chest": (0.46, 0.95),
    "neck_01": (0.34, 1.00),
    "neck_02": (0.32, 1.00),
    "head": (0.42, 1.15),
    "jaw": (0.26, 1.10),
    "tail_01": (0.16, 1.00),
    "tail_02": (0.13, 1.00),
    "tail_03": (0.11, 1.00),
}
for side in ("l", "r"):
    SKIN_BONES.update({
        f"scapula_{side}": (0.26, 1.10),
        f"upper_fore_{side}": (0.20, 1.40),
        f"lower_fore_{side}": (0.16, 1.60),
        f"carpus_{side}": (0.13, 1.70),
        f"front_paw_{side}": (0.14, 1.70),
        f"front_toes_{side}": (0.13, 1.70),
        f"thigh_{side}": (0.24, 1.35),
        f"shin_{side}": (0.16, 1.60),
        f"hock_{side}": (0.13, 1.70),
        f"hind_paw_{side}": (0.13, 1.70),
        f"hind_toes_{side}": (0.12, 1.70),
        f"ear_{side}": (0.10, 1.50),
    })

ROTATION_ORDER = [
    "spine_01", "spine_02", "chest", "neck_01", "neck_02", "head",
    "tail_01", "tail_02", "tail_03", "ear_l", "ear_r",
]
SWAY_BONES = ["spine_01", "spine_02", "chest", "neck_01", "neck_02", "head"]

PALETTE = {
    "body": {"kind": "fur", "base": "#221412", "second": "#0a0605", "accent": "#583228",
             "roughness": 0.94, "flow": (0.0, -0.6, -1.0), "frequency": 190.0,
             "clump_scale": 16.0, "height": 0.0018, "tip_mix": 0.35, "seed": 37},
    "fur": {"kind": "fur", "base": "#221412", "second": "#0a0605", "accent": "#583228",
            "roughness": 0.94, "flow": (0.0, -0.6, -1.0), "frequency": 190.0,
            "clump_scale": 16.0, "height": 0.0018, "tip_mix": 0.35, "seed": 37},
    "hair": {"kind": "hair", "base": "#221412", "second": "#0a0605", "accent": "#4a2a20",
             "roughness": 0.94, "flow": (0.0, -0.5, -1.0), "frequency": 300.0,
             "clump_scale": 26.0, "height": 0.0020, "tip_mix": 0.40, "seed": 43},
    "flesh": {"kind": "skin", "base": "#8d5f50", "second": "#4a2c28", "accent": "#cc9f8a",
              "roughness": 0.46, "mottle_scale": 10.0, "pore_scale": 280.0,
              "wrinkle_scale": 48.0, "vein_scale": 30.0, "vein_mix": 0.30,
              "pore_height": 0.00022, "wrinkle_height": 0.00040, "seed": 47},
    "skin": {"kind": "skin", "base": "#4a332c", "second": "#1e1210", "accent": "#7a5748",
             "roughness": 0.62, "mottle_scale": 14.0, "pore_scale": 250.0,
             "wrinkle_scale": 60.0, "vein_scale": 26.0, "vein_mix": 0.18,
             "pore_height": 0.00024, "wrinkle_height": 0.00048, "seed": 51},
    "bone": {"kind": "bone", "base": "#b8a98e", "second": "#6a5a42", "accent": "#2a241c",
             "roughness": 0.34, "ring_frequency": 150.0, "ring_height": 0.0005,
             "crack_scale": 28.0, "crack_mix": 0.55, "seed": 59},
    "claw": {"kind": "claw", "base": "#1a1410", "second": "#0a0806", "accent": "#5a4a3a",
             "roughness": 0.30, "ring_frequency": 260.0, "crack_scale": 40.0,
             "crack_mix": 0.40, "seed": 61},
    "mouth": {"kind": "mouth", "base": "#2a0a0a", "second": "#0c0202", "accent": "#5a1a1a",
              "roughness": 0.26, "seed": 67},
    "teeth": {"kind": "teeth", "base": "#d8c9a8", "second": "#b09b74", "accent": "#6a5638",
              "roughness": 0.36, "seed": 71},
    "eye": {"kind": "eye", "base": "#1a0a04", "roughness": 0.06, "seed": 73},
}

EYES = [{
    "center": (0.10, 0.90, 1.32),
    "forward": (0.0, 1.0, -0.02),
    "radius": 0.045,
    "iris": "#ffb24a",
    "pupil_colour": "#050202",
    "sclera": "#1a0a04",
    "pupil": 0.30,
    "iris_edge": 0.76,
    "emission": 1.5,
}, {
    "center": (-0.10, 0.90, 1.32),
    "forward": (0.0, 1.0, -0.02),
    "radius": 0.045,
    "iris": "#ffb24a",
    "pupil_colour": "#050202",
    "sclera": "#1a0a04",
    "pupil": 0.30,
    "iris_edge": 0.76,
    "emission": 1.5,
}]


def classify(P: np.ndarray, N: np.ndarray) -> np.ndarray:
    x = np.abs(P[:, 0])
    y = P[:, 1]
    z = P[:, 2]
    flesh = (y > 0.93) & (z > 1.00) & (z < 1.34) & (x < 0.26)
    skin = (((y > 0.86) & (z > 1.24) & (z < 1.41) & (x > 0.045) & (x < 0.22))
            | (z < 0.30))
    return np.where(flesh, "flesh", np.where(skin, "skin", "fur"))


def _sample_tube(rng, a, b, radius, count, length_range, thickness, bend):
    a = np.array(a, dtype=np.float64)
    b = np.array(b, dtype=np.float64)
    axis = b - a
    samples = []
    for _ in range(count):
        t = rng.uniform(0.05, 0.95)
        centre = a + axis * t
        radial = rng.normal(0, 1, 3)
        radial[2] = 0.0
        radial /= np.linalg.norm(radial) + 1e-7
        point = centre + radial * radius * rng.uniform(0.55, 1.0)
        samples.append({
            "point": tuple(point),
            "normal": tuple(radial),
            "length": float(rng.uniform(*length_range)),
            "radius": float(rng.uniform(*thickness)),
            "bend": tuple(np.array(bend) * rng.uniform(0.4, 1.0)),
        })
    return samples


def _sample_ellipsoid(rng, centre, radii, count, length_range, thickness, bend, region=None):
    centre = np.array(centre, dtype=np.float64)
    radii = np.array(radii, dtype=np.float64)
    samples = []
    attempts = 0
    while len(samples) < count and attempts < count * 14:
        attempts += 1
        direction = rng.normal(0, 1, 3)
        direction /= np.linalg.norm(direction) + 1e-7
        point = centre + direction * radii
        if region is not None and not region(point):
            continue
        normal = direction * radii
        normal /= np.linalg.norm(normal) + 1e-7
        samples.append({
            "point": tuple(point),
            "normal": tuple(normal),
            "length": float(rng.uniform(*length_range)),
            "radius": float(rng.uniform(*thickness)),
            "bend": tuple(np.array(bend) * rng.uniform(0.4, 1.0)),
        })
    return samples


def build_parts():
    rng = np.random.default_rng(20261024)
    parts = []

    def body_builder(mb):
        # Hindquarters: narrow hips, heavy haunch, sloped back.
        add_ellipsoid(mb, (0.0, -0.58, 1.02), (0.24, 0.22, 0.20))
        add_ellipsoid(mb, (0.0, -0.44, 0.98), (0.28, 0.28, 0.24))
        add_ellipsoid(mb, (0.0, -0.22, 0.99), (0.31, 0.32, 0.25))
        # Barrel ribcage and the hulking shoulder hump.
        add_ellipsoid(mb, (0.0, 0.02, 1.09), (0.37, 0.32, 0.29))
        add_ellipsoid(mb, (0.0, 0.20, 1.18), (0.42, 0.30, 0.31))
        add_ellipsoid(mb, (0.0, 0.30, 1.34), (0.38, 0.25, 0.24))
        add_ellipsoid(mb, (0.0, 0.38, 1.27), (0.32, 0.20, 0.23))
        for sx in (-1.0, 1.0):
            add_ellipsoid(mb, (sx * 0.28, 0.32, 1.16), (0.18, 0.22, 0.22))
        # Massive neck merging into the shoulders and a short thick throat.
        add_segment(mb, (0.0, 0.34, 1.24), (0.0, 0.62, 1.31), 0.215)
        add_ellipsoid(mb, (0.0, 0.58, 1.30), (0.25, 0.22, 0.23))
        add_ellipsoid(mb, (0.0, 0.70, 1.16), (0.17, 0.16, 0.14))
        # Broad skull, heavy brow, cheeks, short flesh muzzle and underjaw.
        add_ellipsoid(mb, (0.0, 0.78, 1.30), (0.24, 0.15, 0.20))
        add_ellipsoid(mb, (0.0, 0.85, 1.35), (0.21, 0.10, 0.13))
        for sx in (-1.0, 1.0):
            add_ellipsoid(mb, (sx * 0.17, 0.84, 1.22), (0.11, 0.16, 0.15))
        add_ellipsoid(mb, (0.0, 0.99, 1.17), (0.14, 0.19, 0.12))
        add_ellipsoid(mb, (0.0, 0.97, 1.06), (0.13, 0.19, 0.085))
        # Heavy tail.
        add_segment(mb, (0.0, -0.78, 1.02), (0.0, -0.98, 0.92), 0.095)
        add_segment(mb, (0.0, -0.98, 0.92), (0.0, -1.14, 0.82), 0.072)
        add_segment(mb, (0.0, -1.14, 0.82), (0.0, -1.28, 0.73), 0.052)
        for sx in (-1.0, 1.0):
            # Forequarters: deep shoulder, heavy arm, straight columnar forearm.
            add_ellipsoid(mb, (sx * 0.30, 0.36, 1.10), (0.15, 0.16, 0.19))
            add_segment(mb, (sx * 0.32, 0.42, 1.04), (sx * 0.32, 0.36, 0.72), 0.105)
            add_ellipsoid(mb, (sx * 0.32, 0.36, 0.72), (0.09, 0.09, 0.09))
            add_segment(mb, (sx * 0.32, 0.36, 0.72), (sx * 0.32, 0.48, 0.40), 0.082)
            add_segment(mb, (sx * 0.32, 0.48, 0.40), (sx * 0.32, 0.54, 0.19), 0.055)
            # Hindquarters: thick thigh, tucked shin, short hock.
            add_ellipsoid(mb, (sx * 0.27, -0.50, 0.94), (0.16, 0.20, 0.22))
            add_segment(mb, (sx * 0.27, -0.58, 1.02), (sx * 0.27, -0.40, 0.66), 0.115)
            add_segment(mb, (sx * 0.27, -0.40, 0.66), (sx * 0.27, -0.50, 0.34), 0.072)
            add_segment(mb, (sx * 0.27, -0.50, 0.34), (sx * 0.27, -0.38, 0.17), 0.052)

    body = build_metaball("BeastBody", 0.014, 0.6, body_builder,
                          decimate_ratio=0.34, smoothing=1)
    parts.append(part(body, "body"))

    # ------------------------------------------------------------------
    # Rigid details
    for side, sx in (("l", 1.0), ("r", -1.0)):
        # Ears: short, swept back above the jaw.
        parts.append(part(make_tube(
            f"Ear_{side}",
            [(sx * 0.19, 0.80, 1.44), (sx * 0.26, 0.74, 1.54), (sx * 0.30, 0.68, 1.58)],
            [0.052, 0.038, 0.004], sides=7), "skin", rigid="head"))
        # Eyes and heavy brow ridge.
        parts.append(part(make_uv_sphere(f"Eye_{side}", (sx * 0.10, 0.90, 1.32),
                                         0.045, (1.0, 0.92, 1.0), 20, 14), "eye", rigid="head"))
        parts.append(part(make_tube(
            f"Brow_{side}",
            [(sx * 0.035, 0.905, 1.372), (sx * 0.105, 0.925, 1.382), (sx * 0.175, 0.895, 1.355)],
            [0.030, 0.034, 0.018], sides=6), "skin", rigid="head"))
        # Bone tusks out of the lower jaw, curling up and forward.
        parts.append(part(make_tube(
            f"Tusk_{side}",
            [(sx * 0.125, 1.005, 1.055), (sx * 0.145, 1.115, 1.070),
             (sx * 0.160, 1.215, 1.130), (sx * 0.170, 1.265, 1.205)],
            [0.045, 0.034, 0.021, 0.005], sides=8), "bone", rigid="jaw"))
        # Upper canine.
        parts.append(part(make_cone(f"Fang_{side}", (sx * 0.095, 1.055, 1.155),
                                    (sx * 0.098, 1.070, 1.075), 0.020, 6),
                          "teeth", rigid="head"))
        # Big splayed forepaw with four toe knuckles and claws.
        parts.append(part(make_uv_sphere(
            f"ForePaw_{side}", (sx * 0.32, 0.585, 0.115), 0.095, (1.50, 1.80, 1.05), 18, 12),
            "skin", rigid=f"front_paw_{side}"))
        for index, offset in enumerate((-0.090, -0.030, 0.030, 0.090)):
            px = sx * 0.32 + offset
            parts.append(part(make_uv_sphere(
                f"ForeToe_{side}_{index}", (px, 0.745, 0.062), 0.048, (1.0, 1.25, 0.92),
                14, 10), "skin", rigid=f"front_toes_{side}"))
            parts.append(part(make_cone(
                f"ForeClaw_{side}_{index}", (px, 0.795, 0.050),
                (px + offset * 0.25, 0.925, 0.030), 0.017, 6),
                "claw", rigid=f"front_toes_{side}"))
        # Smaller hind paw.
        parts.append(part(make_uv_sphere(
            f"HindPaw_{side}", (sx * 0.27, -0.155, 0.105), 0.085, (1.40, 1.70, 1.05), 18, 12),
            "skin", rigid=f"hind_paw_{side}"))
        for index, offset in enumerate((-0.075, -0.025, 0.025, 0.075)):
            px = sx * 0.27 + offset
            parts.append(part(make_uv_sphere(
                f"HindToe_{side}_{index}", (px, -0.070, 0.058), 0.042, (1.0, 1.25, 0.92),
                14, 10), "skin", rigid=f"hind_toes_{side}"))
            parts.append(part(make_cone(
                f"HindClaw_{side}_{index}", (px, -0.020, 0.048),
                (px + offset * 0.2, 0.045, 0.028), 0.014, 6),
                "claw", rigid=f"hind_toes_{side}"))

    # Muzzle flesh and mouth.
    parts.append(part(make_uv_sphere("Nose", (0.0, 1.165, 1.205), 0.042, (1.35, 0.85, 0.85), 16, 12),
                      "skin", rigid="head"))
    parts.append(part(make_uv_sphere("Mouth", (0.0, 1.045, 1.085), 0.100, (1.25, 1.55, 0.42), 16, 10),
                      "mouth", rigid="jaw"))
    parts.append(part(make_box("Incisors", (0.0, 1.085, 1.095), (0.115, 0.055, 0.025), bevel=0.005),
                      "teeth", rigid="jaw"))
    # Keratin ridge spikes along the spine: six, biggest over the shoulder hump.
    ridge = [
        ("Ridge_0", (0.0, 0.345, 1.545), (0.0, 0.300, 1.665), 0.055, "chest"),
        ("Ridge_1", (0.0, 0.165, 1.520), (0.0, 0.125, 1.630), 0.050, "spine_02"),
        ("Ridge_2", (0.0, -0.020, 1.470), (0.0, -0.060, 1.575), 0.046, "spine_02"),
        ("Ridge_3", (0.0, -0.205, 1.418), (0.0, -0.245, 1.515), 0.041, "spine_01"),
        ("Ridge_4", (0.0, -0.385, 1.350), (0.0, -0.425, 1.440), 0.035, "spine_01"),
        ("Ridge_5", (0.0, -0.560, 1.265), (0.0, -0.600, 1.345), 0.029, "pelvis"),
    ]
    for name, base, tip, radius, bone in ridge:
        parts.append(part(make_tube(
            name, [base, ((base[0] + tip[0]) * 0.5, (base[1] + tip[1]) * 0.5,
                          base[2] + (tip[2] - base[2]) * 0.55), tip],
            [radius, radius * 0.55, 0.003], sides=7), "bone", rigid=bone))

    # ------------------------------------------------------------------
    # Shaggy fur clumps: 415 total, rigid to the owning torso/limb bone.
    regions = [
        ("Mane", "chest", (0.0, 0.36, 1.30), (0.46, 0.42, 0.32), 110, (0.12, 0.28),
         (0.007, 0.015), (0.0, -0.25, -1.0), lambda p: p[2] > 1.18),
        ("Hump", "spine_02", (0.0, 0.22, 1.38), (0.38, 0.30, 0.20), 50, (0.10, 0.24),
         (0.007, 0.014), (0.0, -0.20, -1.0), lambda p: p[2] > 1.32),
        ("Back", "spine_01", (0.0, -0.22, 1.22), (0.32, 0.40, 0.24), 45, (0.09, 0.22),
         (0.006, 0.013), (0.0, -0.15, -1.0), lambda p: p[2] > 1.10),
        ("Rump", "pelvis", (0.0, -0.50, 1.12), (0.30, 0.26, 0.22), 25, (0.10, 0.24),
         (0.006, 0.013), (0.0, -0.30, -1.0), lambda p: p[2] > 1.00),
        ("Belly", "spine_01", (0.0, -0.12, 0.92), (0.32, 0.48, 0.18), 45, (0.10, 0.24),
         (0.006, 0.012), (0.0, -0.05, -1.0), lambda p: p[2] < 0.98),
        ("ShoulderL", "scapula_l", (0.34, 0.32, 1.16), (0.13, 0.22, 0.24), 28, (0.11, 0.26),
         (0.007, 0.014), (0.0, -0.10, -1.0), lambda p: p[0] > 0.25),
        ("ShoulderR", "scapula_r", (-0.34, 0.32, 1.16), (0.13, 0.22, 0.24), 28, (0.11, 0.26),
         (0.007, 0.014), (0.0, -0.10, -1.0), lambda p: p[0] < -0.25),
        ("ThighL", "thigh_l", (0.28, -0.50, 0.94), (0.16, 0.20, 0.24), 22, (0.10, 0.24),
         (0.006, 0.013), (0.0, -0.15, -1.0), lambda p: p[2] < 1.05),
        ("ThighR", "thigh_r", (-0.28, -0.50, 0.94), (0.16, 0.20, 0.24), 22, (0.10, 0.24),
         (0.006, 0.013), (0.0, -0.15, -1.0), lambda p: p[2] < 1.05),
        ("Cheek", "head", (0.0, 0.88, 1.22), (0.25, 0.13, 0.12), 14, (0.07, 0.16),
         (0.005, 0.010), (0.0, -0.20, -1.0), lambda p: p[2] < 1.28),
    ]
    for index, (name, bone, centre, radii, count, length_range, thickness, bend, region) in enumerate(regions):
        samples = _sample_ellipsoid(rng, centre, radii, count, length_range, thickness, bend, region)
        parts.append(part(make_clump_field(name, samples, 5200 + index), "hair", rigid=bone))

    tail_samples = _sample_tube(rng, (0.0, -0.98, 0.92), (0.0, -1.26, 0.74), 0.075, 26,
                                (0.09, 0.16), (0.006, 0.011), (0.0, -0.40, -0.35))
    parts.append(part(make_clump_field("TailTuft", tail_samples, 5290), "hair", rigid="tail_02"))

    return parts


# ---------------------------------------------------------------------------
# Clips


def _base():
    return {"rot": {}, "legs": {}}


def _fore_parent_pitch(neck_01: float, neck_02: float, head: float) -> float:
    """The solver folds every rotation_order pitch into torso_pitch; cancel the
    neck/head part so the fore chain sees only the chest's world pitch."""
    return -(neck_01 + neck_02 + head)


def _planted(compensation: float = 0.0) -> dict:
    return {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0,
            "parent_pitch": compensation}


def idle(t: float) -> dict:
    phase = (t / 2.6) % 1.0
    breath = math.sin(TAU * phase)
    scan = math.sin(TAU * phase * 0.5)
    values = _base()
    values["pelvis_offset"] = (0.006 * math.sin(TAU * phase + 0.4), 0.0,
                               -0.004 + 0.006 * breath)
    values["pelvis_roll"] = 0.018 * math.sin(TAU * phase)
    values["pelvis_yaw"] = 0.014 * scan
    values["pelvis_pitch"] = 0.008 * breath
    values["jaw_open"] = 0.030 + 0.015 * breath
    n1 = 0.020 * breath
    n2 = 0.016 * breath
    hd = -0.010 * breath
    comp = _fore_parent_pitch(n1, n2, hd)
    values["rot"] = {
        "spine_01": (0.022 * breath, -0.010 * scan, 0.006 * breath),
        "spine_02": (0.018 * breath, -0.012 * scan, 0.006 * breath),
        "chest": (-0.038 * breath, -0.016 * scan, 0.010 * breath),
        "neck_01": (n1, 0.030 * scan, -0.008 * breath),
        "neck_02": (n2, 0.040 * scan, 0.0),
        "head": (hd, 0.070 * scan, 0.020 * math.sin(TAU * phase * 0.7)),
        "tail_01": (0.0, 0.120 * math.sin(TAU * phase * 0.65), 0.0),
        "tail_02": (0.0, 0.160 * math.sin(TAU * phase * 0.65 + 0.5), 0.0),
        "tail_03": (0.0, 0.180 * math.sin(TAU * phase * 0.65 + 1.0), 0.0),
        "ear_l": (0.0, 0.0, 0.06 * math.sin(TAU * phase * 0.9)),
        "ear_r": (0.0, 0.0, -0.06 * math.sin(TAU * phase * 0.8 + 1.1)),
    }
    values["legs"] = {"fore_l": _planted(comp), "fore_r": _planted(comp),
                      "hind_l": _planted(), "hind_r": _planted()}
    return values


def walk(t: float) -> dict:
    phase = (t / 1.30) % 1.0
    swing = math.cos(TAU * phase)
    cross = math.sin(TAU * phase)
    bob = abs(math.sin(TAU * phase * 2.0))
    values = _base()
    values["pelvis_offset"] = (0.022 * cross, 0.0, -0.012 + 0.026 * bob)
    values["pelvis_yaw"] = 0.075 * cross
    values["pelvis_roll"] = 0.038 * swing
    values["pelvis_pitch"] = 0.020
    n1 = -0.008
    n2 = -0.008
    hd = -0.012 + 0.012 * math.cos(TAU * phase * 2.0)
    comp = _fore_parent_pitch(n1, n2, hd)
    values["rot"] = {
        "spine_01": (0.018, -0.028 * cross, 0.010 * swing),
        "spine_02": (0.016, -0.040 * cross, 0.010 * swing),
        "chest": (0.006, -0.055 * cross, 0.012 * swing),
        "neck_01": (n1, 0.035 * cross, -0.008 * swing),
        "neck_02": (n2, 0.030 * cross, -0.006 * swing),
        "head": (hd, 0.030 * cross, 0.012 * swing),
        "tail_01": (0.0, 0.11 * math.sin(TAU * phase), 0.0),
        "tail_02": (0.0, 0.15 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (0.0, 0.19 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _gait(values, phase, 0.55, 1.90, 0.10,
          {"fore_l": 0.0, "hind_r": 0.0, "fore_r": 0.5, "hind_l": 0.5}, comp)
    values["jaw_open"] = 0.025
    return values


def run(t: float) -> dict:
    phase = (t / 0.75) % 1.0
    swing = math.cos(TAU * phase)
    cross = math.sin(TAU * phase)
    bob = abs(math.sin(TAU * phase * 2.0))
    values = _base()
    values["pelvis_offset"] = (0.030 * cross, 0.0, -0.020 + 0.038 * bob)
    values["pelvis_yaw"] = 0.100 * cross
    values["pelvis_roll"] = 0.055 * swing
    values["pelvis_pitch"] = 0.045
    n1 = -0.030
    n2 = -0.026
    hd = -0.035 + 0.022 * math.cos(TAU * phase * 2.0)
    comp = _fore_parent_pitch(n1, n2, hd)
    values["rot"] = {
        "spine_01": (0.050, -0.045 * cross, 0.016 * swing),
        "spine_02": (0.046, -0.060 * cross, 0.014 * swing),
        "chest": (0.030, -0.080 * cross, 0.018 * swing),
        "neck_01": (n1, 0.060 * cross, -0.012 * swing),
        "neck_02": (n2, 0.050 * cross, -0.012 * swing),
        "head": (hd, 0.040 * cross, 0.018 * swing),
        "tail_01": (0.0, 0.10 * math.sin(TAU * phase), 0.0),
        "tail_02": (0.0, 0.14 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (0.0, 0.18 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _gait(values, phase, 0.36, 3.30, 0.22,
          {"fore_l": 0.0, "hind_r": 0.0, "fore_r": 0.5, "hind_l": 0.5}, comp)
    values["jaw_open"] = 0.05
    return values


def attack(t: float) -> dict:
    u = min(1.0, t / 1.60)
    values = _base()
    values["pelvis_offset"] = (
        0.0,
        keyed(u, [(0.0, 0.0), (0.20, -0.04), (0.34, -0.10), (0.44, -0.12),
                  (0.48, -0.12), (0.5125, 0.10), (0.60, 0.12), (0.80, 0.04), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.20, -0.02), (0.34, 0.02), (0.44, 0.03),
                  (0.48, 0.03), (0.5125, -0.06), (0.60, -0.07), (0.80, -0.01), (1.0, 0.0)]),
    )
    values["pelvis_pitch"] = keyed(u, [(0.0, 0.0), (0.16, 0.03), (0.30, 0.20),
                                       (0.44, 0.30), (0.48, 0.31), (0.5125, -0.12),
                                       (0.60, -0.16), (0.75, 0.02), (0.90, 0.01), (1.0, 0.0)])
    values["pelvis_yaw"] = keyed(u, [(0.0, 0.0), (0.44, 0.09), (0.5125, -0.03),
                                     (0.70, 0.02), (1.0, 0.0)])
    values["pelvis_roll"] = keyed(u, [(0.0, 0.0), (0.44, 0.03), (0.5125, -0.05),
                                      (0.70, 0.02), (1.0, 0.0)])
    values["jaw_open"] = keyed(u, [(0.0, 0.04), (0.30, 0.16), (0.44, 0.24),
                                   (0.5125, 0.52), (0.60, 0.40), (0.72, 0.14), (1.0, 0.04)])
    s1 = keyed(u, [(0.0, 0.0), (0.30, 0.04), (0.44, 0.06), (0.48, 0.06),
                   (0.5125, -0.07), (0.62, -0.06), (1.0, 0.0)])
    s2 = keyed(u, [(0.0, 0.0), (0.30, 0.05), (0.44, 0.08), (0.48, 0.08),
                   (0.5125, -0.09), (0.62, -0.08), (1.0, 0.0)])
    ch = keyed(u, [(0.0, 0.0), (0.30, 0.06), (0.44, 0.10), (0.48, 0.10),
                   (0.5125, -0.14), (0.62, -0.12), (1.0, 0.0)])
    n1 = keyed(u, [(0.0, 0.0), (0.30, 0.05), (0.44, 0.07), (0.48, 0.07),
                   (0.5125, -0.09), (0.62, -0.07), (1.0, 0.0)])
    n2 = keyed(u, [(0.0, 0.0), (0.30, 0.04), (0.44, 0.06), (0.48, 0.06),
                   (0.5125, -0.08), (0.62, -0.06), (1.0, 0.0)])
    hd = keyed(u, [(0.0, 0.0), (0.30, 0.05), (0.44, 0.08), (0.48, 0.08),
                   (0.5125, -0.22), (0.60, -0.16), (0.72, 0.06), (1.0, 0.0)])
    comp = _fore_parent_pitch(n1, n2, hd)
    values["rot"] = {
        "spine_01": (s1, 0.0, 0.0),
        "spine_02": (s2, 0.0, 0.0),
        "chest": (ch, 0.0, 0.0),
        "neck_01": (n1, 0.0, 0.0),
        "neck_02": (n2, 0.0, 0.0),
        "head": (hd, -0.04 * math.sin(TAU * u * 2.0), 0.0),
        "tail_01": (0.0, keyed(u, [(0.0, 0.0), (0.44, 0.18), (0.60, -0.10), (1.0, 0.0)]), 0.0),
        "tail_02": (0.0, keyed(u, [(0.0, 0.0), (0.44, 0.22), (0.60, -0.12), (1.0, 0.0)]), 0.0),
        "tail_03": (0.0, keyed(u, [(0.0, 0.0), (0.44, 0.26), (0.60, -0.14), (1.0, 0.0)]), 0.0),
    }

    def fore(side_phase: int) -> dict:
        lag = 0.0 if side_phase == 0 else 0.02
        return {
            "y": keyed(u, [(0.0, 0.0), (0.30 - lag, -0.10), (0.44 - lag, -0.16),
                           (0.48 - lag, -0.18), (0.5125, 0.12), (0.62, 0.12),
                           (0.80, 0.03), (1.0, 0.0)]),
            "lift": keyed(u, [(0.0, 0.0), (0.18, 0.05), (0.30 - lag, 0.28),
                              (0.44 - lag, 0.52), (0.48 - lag, 0.54), (0.5125, 0.0),
                              (0.70, 0.0), (1.0, 0.0)]),
            "toe": keyed(u, [(0.0, 0.0), (0.30 - lag, -0.14), (0.48 - lag, -0.18),
                             (0.5125, 0.0), (1.0, 0.0)]),
            "foot": keyed(u, [(0.0, 0.0), (0.30 - lag, -0.16), (0.44 - lag, -0.34),
                              (0.48 - lag, -0.38), (0.5125, 0.0), (1.0, 0.0)]),
            "parent_pitch": comp,
        }

    values["legs"] = {
        "fore_l": fore(0),
        "fore_r": fore(1),
        "hind_l": {"y": keyed(u, [(0.0, 0.0), (0.44, 0.03), (0.5125, -0.06), (1.0, 0.0)]),
                   "lift": 0.0, "toe": 0.0, "foot": 0.0},
        "hind_r": {"y": keyed(u, [(0.0, 0.0), (0.44, -0.03), (0.5125, 0.05), (1.0, 0.0)]),
                   "lift": 0.0, "toe": 0.0, "foot": 0.0},
    }
    return values


def hit(t: float) -> dict:
    u = min(1.0, t / 0.50)
    recoil = keyed(u, [(0.0, 0.0), (0.22, 1.0), (0.55, 0.55), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (0.05 * recoil, -0.06 * recoil, -0.03 * recoil)
    values["pelvis_pitch"] = -0.10 * recoil
    values["pelvis_roll"] = 0.08 * recoil
    values["pelvis_yaw"] = 0.06 * recoil
    values["jaw_open"] = 0.24 * recoil + 0.02
    n1 = -0.14 * recoil
    n2 = -0.10 * recoil
    hd = -0.26 * recoil
    comp = _fore_parent_pitch(n1, n2, hd)
    values["rot"] = {
        "spine_01": (0.13 * recoil, 0.0, 0.05 * recoil),
        "spine_02": (0.15 * recoil, 0.0, 0.06 * recoil),
        "chest": (0.18 * recoil, 0.0, 0.08 * recoil),
        "neck_01": (n1, 0.0, 0.06 * recoil),
        "neck_02": (n2, 0.0, 0.06 * recoil),
        "head": (hd, 0.10 * recoil, 0.14 * recoil),
        "tail_01": (0.0, 0.16 * recoil, 0.0),
        "tail_02": (0.0, 0.20 * recoil, 0.0),
        "tail_03": (0.0, 0.24 * recoil, 0.0),
    }
    values["legs"] = {
        "fore_l": {"y": 0.05 * recoil, "lift": 0.0, "toe": 0.0,
                   "foot": 0.04 * recoil, "parent_pitch": comp},
        "fore_r": {"y": -0.05 * recoil, "lift": 0.0, "toe": 0.0,
                   "foot": 0.04 * recoil, "parent_pitch": comp},
        "hind_l": {"y": -0.04 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.03 * recoil},
        "hind_r": {"y": 0.04 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.03 * recoil},
    }
    return values


def death(t: float) -> dict:
    u = min(1.0, t / 1.30)
    collapse = keyed(u, [(0.0, 0.0), (0.16, 0.10), (0.46, 0.68), (0.80, 1.0), (1.0, 1.0)])
    roll = keyed(u, [(0.0, 0.0), (0.20, 0.12), (0.55, 0.72), (0.85, 1.12), (1.0, 1.12)])
    settle = keyed(u, [(0.0, 0.0), (0.72, 0.0), (0.88, -0.12), (1.0, -0.12)])
    values = _base()
    values["pelvis_offset"] = (0.10 * collapse, 0.05 * collapse,
                               -0.38 * collapse + settle)
    values["pelvis_pitch"] = 0.14 * collapse
    values["pelvis_roll"] = roll
    values["pelvis_yaw"] = 0.16 * collapse
    values["jaw_open"] = 0.14 + 0.14 * collapse
    s1 = 0.05 * collapse
    s2 = 0.07 * collapse
    ch = 0.05 * collapse
    n1 = -0.10 * collapse
    n2 = -0.12 * collapse
    hd = -0.20 * collapse
    comp = _fore_parent_pitch(n1, n2, hd)
    values["rot"] = {
        "spine_01": (s1, 0.06 * collapse, 0.06 * collapse),
        "spine_02": (s2, 0.08 * collapse, 0.08 * collapse),
        "chest": (ch, 0.06 * collapse, 0.06 * collapse),
        "neck_01": (n1, -0.10 * collapse, -0.12 * collapse),
        "neck_02": (n2, -0.12 * collapse, -0.14 * collapse),
        "head": (hd, -0.14 * collapse, -0.18 * collapse),
        "tail_01": (0.0, 0.20 * collapse, 0.10 * collapse),
        "tail_02": (0.0, 0.22 * collapse, 0.12 * collapse),
        "tail_03": (0.0, 0.24 * collapse, 0.14 * collapse),
    }
    values["legs"] = {
        "fore_l": {"y": 0.08 * collapse, "lift": 0.08 * collapse,
                   "toe": 0.22 * collapse, "foot": 0.20 * collapse, "parent_pitch": comp},
        "fore_r": {"y": 0.18 * collapse, "lift": 0.20 * collapse,
                   "toe": -0.18 * collapse, "foot": -0.24 * collapse, "parent_pitch": comp},
        "hind_l": {"y": -0.08 * collapse, "lift": 0.06 * collapse,
                   "toe": 0.20 * collapse, "foot": 0.18 * collapse},
        "hind_r": {"y": 0.14 * collapse, "lift": 0.16 * collapse,
                   "toe": -0.16 * collapse, "foot": -0.20 * collapse},
    }
    return values


def _gait(values: dict, phase: float, duty: float, stride: float,
          clearance: float, offsets: dict, compensation: float = 0.0) -> None:
    values.setdefault("legs", {})
    for chain_key, offset in offsets.items():
        q = (phase - offset) % 1.0
        half = stride * duty * 0.5
        if q < duty:
            y = half - 2.0 * half * (q / duty)
            lift = 0.0
            toe = 0.0
            foot = 0.0
        else:
            p = (q - duty) / max(1e-6, 1.0 - duty)
            eased = p * p * (3.0 - 2.0 * p)
            y = -half + 2.0 * half * eased
            lift = clearance * math.sin(math.pi * p) ** 1.2
            toe = -0.30 * math.sin(math.pi * p)
            foot = 0.18 * math.sin(math.pi * p)
        entry = {"y": y, "lift": lift, "toe": toe, "foot": foot}
        if chain_key.startswith("fore"):
            entry["parent_pitch"] = compensation
        values["legs"][chain_key] = entry


CLIPS = {
    "idle": {"name": "Beast_Idle_Loop", "duration": 2.60, "loop": True},
    "walk": {"name": "Beast_Walk_Loop", "duration": 1.30, "loop": True,
             "stride": 1.90, "duty": 0.55, "fallback_speed": 1.46},
    "run": {"name": "Beast_Run_Loop", "duration": 0.75, "loop": True,
            "stride": 3.30, "duty": 0.36, "fallback_speed": 4.40},
    "attack": {"name": "Beast_Attack", "duration": 1.60, "loop": False,
               "impact": 0.82, "recovery_end": 1.60},
    "hit": {"name": "Beast_Hit", "duration": 0.50, "loop": False},
    "death": {"name": "Beast_Death", "duration": 1.30, "loop": False},
}

POSES = {
    "idle": idle,
    "walk": walk,
    "run": run,
    "attack": attack,
    "hit": hit,
    "death": death,
}

SPEC = {
    "id": "beast",
    "display_name": "Hell beast",
    "scene": SCENE,
    "height": HEIGHT,
    "texture_size": 2048,
    "bones": BONES,
    "chains": CHAINS,
    "skin_bones": SKIN_BONES,
    "rotation_order": ROTATION_ORDER,
    "sway_bones": SWAY_BONES,
    "palette": PALETTE,
    "classify": classify,
    "paint_tags": ["body", "fur", "hair", "flesh", "skin", "bone", "claw",
                   "eye", "teeth", "mouth"],
    "eyes": EYES,
    "normal_strength": 1.20,
    "build_parts": build_parts,
    "clips": CLIPS,
    "poses": POSES,
    "head_zone": {"bone": "head", "radius": 0.45, "half_height": 0.22},
    "metadata_extra": {
        "role": "bruiser",
        "body_length": 2.70,
        "locomotion": "heavy trot, four-beat fallback walk",
        "surface_notes": ["procedural dark shaggy fur", "exposed flesh muzzle",
                          "bone back ridge", "bone tusks", "keratin claws",
                          "ember eyes"],
    },
}
