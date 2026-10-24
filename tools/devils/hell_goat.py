"""Hellish goat man: shaggy digitigrade devil with ram horns and a bone collar.

Reference palette: near-monochrome charcoal fur and pale horn; warm ember eyes
provide the only saturated accent. Silhouette: 2.2 m, heavy shoulders, long
shaggy forearms and shins, cloven hooves, forward-hooked ram horns.
"""

from __future__ import annotations

import math

import numpy as np

from devil_pipeline import (
    TAU,
    add_ellipsoid,
    add_segment,
    build_metaball,
    fbm,
    keyed,
    make_box,
    make_clump_field,
    make_cone,
    make_tube,
    make_uv_sphere,
    part,
    srgb_array,
)

SCENE = "HellGoat"
HEIGHT = 2.20

BONES = {
    "root": {"head": (0.0, 0.0, 0.0), "tail": (0.0, 0.0, 0.15), "deform": False},
    "pelvis": {"head": (0.0, -0.02, 1.08), "tail": (0.0, 0.02, 1.20), "parent": "root"},
    "spine_01": {"head": (0.0, 0.02, 1.20), "tail": (0.0, 0.03, 1.34), "parent": "pelvis", "connect": True},
    "spine_02": {"head": (0.0, 0.03, 1.34), "tail": (0.0, 0.04, 1.48), "parent": "spine_01", "connect": True},
    "chest": {"head": (0.0, 0.04, 1.48), "tail": (0.0, 0.03, 1.64), "parent": "spine_02", "connect": True},
    "neck_01": {"head": (0.0, 0.03, 1.64), "tail": (0.0, 0.07, 1.76), "parent": "chest", "connect": True},
    "neck_02": {"head": (0.0, 0.07, 1.76), "tail": (0.0, 0.10, 1.85), "parent": "neck_01", "connect": True},
    "head": {"head": (0.0, 0.10, 1.85), "tail": (0.0, 0.18, 1.97), "parent": "neck_02", "connect": True},
    "jaw": {"head": (0.0, 0.15, 1.90), "tail": (0.0, 0.33, 1.84), "parent": "head"},
    "tail_01": {"head": (0.0, -0.05, 1.06), "tail": (0.0, -0.20, 1.00), "parent": "pelvis"},
    "tail_02": {"head": (0.0, -0.20, 1.00), "tail": (0.0, -0.32, 0.94), "parent": "tail_01", "connect": True},
    "tail_03": {"head": (0.0, -0.32, 0.94), "tail": (0.0, -0.40, 0.90), "parent": "tail_02", "connect": True},
}

for side, sx in (("l", 1.0), ("r", -1.0)):
    BONES.update({
        f"clavicle_{side}": {"head": (sx * 0.04, 0.03, 1.60), "tail": (sx * 0.21, 0.04, 1.60), "parent": "chest"},
        f"upper_arm_{side}": {"head": (sx * 0.21, 0.04, 1.60), "tail": (sx * 0.29, 0.07, 1.36), "parent": f"clavicle_{side}", "connect": True},
        f"forearm_{side}": {"head": (sx * 0.29, 0.07, 1.36), "tail": (sx * 0.34, 0.11, 1.12), "parent": f"upper_arm_{side}", "connect": True},
        f"hand_{side}": {"head": (sx * 0.34, 0.11, 1.12), "tail": (sx * 0.35, 0.17, 1.02), "parent": f"forearm_{side}", "connect": True},
        f"fingers_{side}": {"head": (sx * 0.35, 0.17, 1.02), "tail": (sx * 0.35, 0.25, 0.97), "parent": f"hand_{side}", "connect": True},
        f"thigh_{side}": {"head": (sx * 0.145, -0.01, 1.06), "tail": (sx * 0.17, 0.09, 0.76), "parent": "pelvis"},
        f"shin_{side}": {"head": (sx * 0.17, 0.09, 0.76), "tail": (sx * 0.18, -0.08, 0.45), "parent": f"thigh_{side}", "connect": True},
        f"tarsus_{side}": {"head": (sx * 0.18, -0.08, 0.45), "tail": (sx * 0.19, 0.04, 0.17), "parent": f"shin_{side}", "connect": True},
        f"foot_{side}": {"head": (sx * 0.19, 0.04, 0.17), "tail": (sx * 0.19, 0.16, 0.08), "parent": f"tarsus_{side}", "connect": True},
        f"toes_{side}": {"head": (sx * 0.19, 0.16, 0.08), "tail": (sx * 0.19, 0.28, 0.055), "parent": f"foot_{side}", "connect": True},
        f"ear_{side}": {"head": (sx * 0.11, 0.12, 1.98), "tail": (sx * 0.22, 0.06, 1.99), "parent": "head"},
    })

CHAINS = {
    "leg_l": {"bones": ["thigh_l", "shin_l", "tarsus_l", "foot_l", "toes_l"], "pole": -1.0},
    "leg_r": {"bones": ["thigh_r", "shin_r", "tarsus_r", "foot_r", "toes_r"], "pole": -1.0},
}

SKIN_BONES = {
    "pelvis": (0.25, 0.9),
    "spine_01": (0.27, 0.9),
    "spine_02": (0.28, 0.9),
    "chest": (0.31, 0.95),
    "neck_01": (0.145, 1.0),
    "neck_02": (0.135, 1.0),
    "head": (0.19, 1.1),
    "jaw": (0.13, 1.1),
    "tail_01": (0.08, 1.0),
    "tail_02": (0.07, 1.0),
    "tail_03": (0.06, 1.0),
}
for side in ("l", "r"):
    SKIN_BONES.update({
        f"clavicle_{side}": (0.13, 1.1),
        f"upper_arm_{side}": (0.125, 1.6),
        f"forearm_{side}": (0.105, 1.7),
        f"hand_{side}": (0.105, 1.7),
        f"fingers_{side}": (0.085, 1.7),
        f"thigh_{side}": (0.155, 1.4),
        f"shin_{side}": (0.115, 1.5),
        f"tarsus_{side}": (0.09, 1.5),
        f"foot_{side}": (0.105, 1.5),
        f"toes_{side}": (0.105, 1.5),
        f"ear_{side}": (0.055, 1.4),
    })

ROTATION_ORDER = [
    "spine_01", "spine_02", "chest", "neck_01", "neck_02", "head",
    "clavicle_l", "upper_arm_l", "forearm_l", "hand_l", "fingers_l",
    "clavicle_r", "upper_arm_r", "forearm_r", "hand_r", "fingers_r",
    "tail_01", "tail_02", "tail_03", "ear_l", "ear_r",
]
SWAY_BONES = ["spine_01", "spine_02", "chest", "neck_01", "neck_02", "head"]

PALETTE = {
    "body": {"kind": "fur", "base": "#3a3a3d", "second": "#1d1d20", "accent": "#8d8d90",
             "roughness": 0.90, "flow": (0.0, -0.3, -1.0), "frequency": 155.0,
             "clump_scale": 18.0, "height": 0.0016, "tip_mix": 0.42},
    "fur": {"kind": "fur", "base": "#3a3a3d", "second": "#1d1d20", "accent": "#8d8d90",
            "roughness": 0.90, "flow": (0.0, -0.3, -1.0), "frequency": 155.0,
            "clump_scale": 18.0, "height": 0.0016, "tip_mix": 0.42, "seed": 41},
    "skin": {"kind": "skin", "base": "#4a4442", "second": "#26211f", "accent": "#6b5f58",
             "roughness": 0.52, "mottle_scale": 13.0, "pore_scale": 330.0,
             "wrinkle_scale": 62.0, "vein_scale": 34.0, "vein_mix": 0.16,
             "pore_height": 0.00020, "wrinkle_height": 0.00042, "seed": 47},
    "hair": {"kind": "hair", "base": "#2b2b2e", "second": "#131315", "accent": "#808085",
             "roughness": 0.94, "flow": (0.0, -0.45, -1.0), "frequency": 280.0,
             "clump_scale": 30.0, "height": 0.0018, "tip_mix": 0.50, "seed": 53},
    "horn": {"kind": "horn", "base": "#b9aa90", "second": "#6f6048", "accent": "#2a241c",
             "roughness": 0.34, "ring_frequency": 220.0, "ring_height": 0.00055,
             "crack_scale": 32.0, "crack_mix": 0.55, "seed": 59},
    "hoof": {"kind": "hoof", "base": "#1a1715", "second": "#2d2620", "accent": "#0b0908",
             "roughness": 0.44, "ring_frequency": 160.0, "crack_scale": 42.0,
             "crack_mix": 0.6, "seed": 61},
    "claw": {"kind": "claw", "base": "#2a2622", "second": "#100e0c", "accent": "#6e6152",
             "roughness": 0.30, "ring_frequency": 240.0, "crack_mix": 0.4, "seed": 67},
    "eye": {"kind": "eye", "base": "#1a0c08", "roughness": 0.06, "seed": 71},
    "teeth": {"kind": "teeth", "base": "#d8c9a8", "second": "#b09b74", "accent": "#6a5638",
              "roughness": 0.36, "seed": 73},
    "mouth": {"kind": "mouth", "base": "#2a0f10", "second": "#120607", "accent": "#5a2020",
              "roughness": 0.28, "seed": 79},
    "leather": {"kind": "leather", "base": "#2b201a", "second": "#120d0a", "accent": "#5a4433",
                "roughness": 0.72, "grain_scale": 60.0, "crease_scale": 26.0, "seed": 83},
    "metal": {"kind": "metal", "base": "#6a6155", "second": "#3a3329", "accent": "#c9a86a",
              "roughness": 0.42, "metallic": 0.88, "seed": 89},
}

EYES = [{
    "center": (0.066, 0.205, 1.930),
    "forward": (0.0, 1.0, -0.05),
    "radius": 0.034,
    "iris": "#ff7d22",
    "pupil_colour": "#080302",
    "sclera": "#1c0d09",
    "pupil": 0.30,
    "iris_edge": 0.74,
    "emission": 1.6,
}, {
    "center": (-0.066, 0.205, 1.930),
    "forward": (0.0, 1.0, -0.05),
    "radius": 0.034,
    "iris": "#ff7d22",
    "pupil_colour": "#080302",
    "sclera": "#1c0d09",
    "pupil": 0.30,
    "iris_edge": 0.74,
    "emission": 1.6,
}]


def classify(P: np.ndarray, N: np.ndarray) -> np.ndarray:
    x = np.abs(P[:, 0])
    face = (P[:, 2] > 1.77) & (P[:, 1] > 0.05) & (x < 0.26)
    hands = (P[:, 2] > 0.90) & (P[:, 2] < 1.20) & (x > 0.255)
    knees = (P[:, 2] < 0.55) & (x > 0.12) & (x < 0.26) & (P[:, 1] > 0.02)
    return np.where(face | hands | knees, "skin", "fur")


def _sample_tube(rng, a, b, radius, count, length_range, thickness, bend):
    a = np.array(a, dtype=np.float64)
    b = np.array(b, dtype=np.float64)
    axis = b - a
    samples = []
    for _ in range(count):
        t = rng.uniform(0.05, 0.95)
        centre = a + axis * t
        theta = rng.uniform(0, TAU)
        radial = rng.normal(0, 1, 3)
        radial[2] = 0.0
        radial /= np.linalg.norm(radial) + 1e-7
        point = centre + radial * radius * rng.uniform(0.55, 1.0)
        normal = radial.copy()
        samples.append({
            "point": tuple(point),
            "normal": tuple(normal),
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
    while len(samples) < count and attempts < count * 12:
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
        # Torso and shoulders.
        add_ellipsoid(mb, (0.0, -0.01, 1.08), (0.20, 0.16, 0.17))
        add_ellipsoid(mb, (0.0, 0.02, 1.22), (0.17, 0.15, 0.16))
        add_ellipsoid(mb, (0.0, 0.03, 1.44), (0.25, 0.19, 0.22))
        add_ellipsoid(mb, (0.0, 0.02, 1.58), (0.30, 0.18, 0.17))
        add_ellipsoid(mb, (0.0, 0.03, 1.62), (0.34, 0.16, 0.13))
        # Neck, skull, brow, muzzle and jaw mass.
        add_ellipsoid(mb, (0.0, 0.06, 1.72), (0.12, 0.13, 0.14))
        add_ellipsoid(mb, (0.0, 0.12, 1.90), (0.135, 0.16, 0.14))
        add_ellipsoid(mb, (0.0, 0.20, 1.92), (0.11, 0.09, 0.08))
        add_ellipsoid(mb, (0.0, 0.28, 1.86), (0.075, 0.14, 0.08))
        add_ellipsoid(mb, (0.0, 0.40, 1.84), (0.05, 0.06, 0.05))
        add_ellipsoid(mb, (0.0, 0.29, 1.80), (0.065, 0.12, 0.05))
        add_ellipsoid(mb, (0.0, 0.24, 1.74), (0.06, 0.08, 0.10))
        for sx in (-1.0, 1.0):
            # Shoulder, arm, hand.
            add_ellipsoid(mb, (sx * 0.25, 0.03, 1.58), (0.10, 0.11, 0.13))
            add_segment(mb, (sx * 0.24, 0.04, 1.55), (sx * 0.29, 0.07, 1.36), 0.072)
            add_ellipsoid(mb, (sx * 0.29, 0.07, 1.36), (0.068, 0.07, 0.07))
            add_segment(mb, (sx * 0.29, 0.07, 1.36), (sx * 0.34, 0.11, 1.12), 0.052)
            add_ellipsoid(mb, (sx * 0.34, 0.12, 1.10), (0.055, 0.08, 0.065))
            # Haunch, thigh, knee, calf, hock, cannon, fetlock.
            add_ellipsoid(mb, (sx * 0.15, -0.01, 1.02), (0.11, 0.13, 0.15))
            add_segment(mb, (sx * 0.15, -0.01, 1.02), (sx * 0.17, 0.09, 0.76), 0.078)
            add_ellipsoid(mb, (sx * 0.17, 0.09, 0.76), (0.072, 0.075, 0.075))
            add_segment(mb, (sx * 0.17, 0.09, 0.76), (sx * 0.18, -0.08, 0.45), 0.052)
            add_ellipsoid(mb, (sx * 0.18, -0.08, 0.45), (0.048, 0.055, 0.05))
            add_segment(mb, (sx * 0.18, -0.08, 0.45), (sx * 0.19, 0.04, 0.17), 0.038)
            add_ellipsoid(mb, (sx * 0.19, 0.05, 0.15), (0.048, 0.06, 0.045))
        # Short tail.
        add_segment(mb, (0.0, -0.06, 1.06), (0.0, -0.22, 0.99), 0.045)
        add_segment(mb, (0.0, -0.22, 0.99), (0.0, -0.38, 0.91), 0.032)

    body = build_metaball("HellGoatBody", 0.012, 0.6, body_builder,
                          decimate_ratio=0.40, smoothing=1)
    parts.append(part(body, "body"))

    # Ram horns: thick at the skull, sweeping out, back and down.
    for side, sx in (("l", 1.0), ("r", -1.0)):
        points = [
            (sx * 0.070, 0.105, 2.005),
            (sx * 0.115, 0.050, 2.145),
            (sx * 0.185, -0.025, 2.175),
            (sx * 0.260, -0.105, 2.095),
            (sx * 0.300, -0.165, 1.955),
        ]
        radii = [0.045, 0.040, 0.031, 0.020, 0.007]
        parts.append(part(make_tube(f"Horn_{side}", points, radii, sides=10), "horn", rigid="head"))
        # Ear under the horn base.
        parts.append(part(make_tube(
            f"Ear_{side}",
            [(sx * 0.115, 0.115, 1.965), (sx * 0.175, 0.090, 1.945), (sx * 0.235, 0.055, 1.915)],
            [0.030, 0.028, 0.004], sides=7), "skin", rigid="head"))
        # Eye and a small brow ridge.
        parts.append(part(make_uv_sphere(f"Eye_{side}", (sx * 0.066, 0.205, 1.930),
                                         0.034, (1.0, 0.92, 1.0), 20, 14), "eye", rigid="head"))
        parts.append(part(make_tube(
            f"Brow_{side}",
            [(sx * 0.028, 0.205, 1.995), (sx * 0.105, 0.195, 1.985)],
            [0.024, 0.014], sides=6), "skin", rigid="head"))
        # Cloven hoof: two blocks under the fetlock.
        for toe in (-1.0, 1.0):
            parts.append(part(make_box(
                f"Hoof_{side}_{int(toe)}",
                (sx * 0.19 + toe * 0.030, 0.195, 0.050),
                (0.052, 0.185, 0.085), rotation=(0.16, 0.0, 0.0), bevel=0.016),
                "hoof", rigid=f"toes_{side}"))
        # Three claws on each hand.
        for index, offset in enumerate((-0.030, 0.0, 0.030)):
            parts.append(part(make_cone(
                f"Claw_{side}_{index}",
                (sx * 0.35 + offset, 0.235, 0.985),
                (sx * 0.35 + offset * 1.3, 0.305, 0.925), 0.011, 6),
                "claw", rigid=f"fingers_{side}"))
        # Beard tufts under the jaw.
        beard = _sample_ellipsoid(rng, (0.0, 0.255, 1.755), (0.055, 0.075, 0.085), 26,
                                  (0.09, 0.20), (0.006, 0.012), (0.0, -0.02, -1.0),
                                  region=lambda p: p[2] < 1.79)
        parts.append(part(make_clump_field(f"Beard_{side}", beard, 3101 + (0 if sx > 0 else 1)),
                          "hair", rigid="jaw"))

    # Bone collar: a ring of short spikes around the neck.
    for index in range(9):
        angle = TAU * index / 9.0
        base = (math.sin(angle) * 0.115, 0.045 + math.cos(angle) * 0.075, 1.775)
        tip = (math.sin(angle) * 0.145, 0.045 + math.cos(angle) * 0.095, 1.865)
        parts.append(part(make_cone(f"Collar_{index}", base, tip, 0.016, 5),
                          "horn", rigid="neck_02"))

    # Shaggy fur regions, each rigid to the bone that owns it.
    regions = [
        ("Mane", "chest", (0.0, 0.02, 1.56), (0.31, 0.16, 0.19), 90, (0.10, 0.24), (0.007, 0.014),
         (0.0, -0.05, -1.0), lambda p: p[2] > 1.42),
        ("Back", "spine_02", (0.0, -0.01, 1.38), (0.22, 0.15, 0.19), 55, (0.08, 0.20),
         (0.006, 0.013), (0.0, -0.08, -1.0), lambda p: p[1] < 0.06),
        ("UpperArmL", "upper_arm_l", (0.26, 0.05, 1.47), (0.09, 0.08, 0.14), 30, (0.10, 0.22),
         (0.006, 0.012), (0.0, -0.03, -1.0), None),
        ("UpperArmR", "upper_arm_r", (-0.26, 0.05, 1.47), (0.09, 0.08, 0.14), 30, (0.10, 0.22),
         (0.006, 0.012), (0.0, -0.03, -1.0), None),
        ("ForearmL", "forearm_l", (0.315, 0.09, 1.25), (0.065, 0.06, 0.13), 34, (0.11, 0.24),
         (0.006, 0.012), (0.0, -0.03, -1.0), None),
        ("ForearmR", "forearm_r", (-0.315, 0.09, 1.25), (0.065, 0.06, 0.13), 34, (0.11, 0.24),
         (0.006, 0.012), (0.0, -0.03, -1.0), None),
        ("ShinL", "shin_l", (0.175, 0.01, 0.60), (0.075, 0.08, 0.16), 40, (0.09, 0.20),
         (0.006, 0.012), (0.0, -0.03, -1.0), None),
        ("ShinR", "shin_r", (-0.175, 0.01, 0.60), (0.075, 0.08, 0.16), 40, (0.09, 0.20),
         (0.006, 0.012), (0.0, -0.03, -1.0), None),
    ]
    for index, (name, bone, centre, radii, count, length_range, thickness, bend, region) in enumerate(regions):
        samples = _sample_ellipsoid(rng, centre, radii, count, length_range, thickness, bend, region)
        parts.append(part(make_clump_field(name, samples, 4200 + index), "hair", rigid=bone))

    tail_samples = _sample_tube(rng, (0.0, -0.20, 1.00), (0.0, -0.38, 0.91), 0.045, 28,
                                (0.08, 0.18), (0.005, 0.010), (0.0, -0.05, -0.8))
    parts.append(part(make_clump_field("TailTuft", tail_samples, 4310), "hair", rigid="tail_02"))

    # Leather harness: a belt, a chest strap and a hanging loin flap.
    parts.append(part(make_box("Belt", (0.0, 0.0, 1.15), (0.44, 0.34, 0.075), bevel=0.012),
                      "leather", rigid="pelvis"))
    parts.append(part(make_box("LoinFlap", (0.0, -0.16, 0.98), (0.20, 0.035, 0.30),
                               rotation=(-0.10, 0.0, 0.0), bevel=0.008), "leather", rigid="pelvis"))
    parts.append(part(make_tube("ChestStrap", [(-0.22, 0.13, 1.57), (0.0, 0.20, 1.50),
                                                (0.22, 0.13, 1.57)],
                                [0.030, 0.034, 0.030], sides=5), "leather", rigid="chest"))
    # A crude iron collar ring.
    collar_points = []
    for index in range(15):
        angle = TAU * index / 15.0
        collar_points.append((math.sin(angle) * 0.135, 0.05 + math.cos(angle) * 0.095, 1.735))
    collar_points.append(collar_points[0])
    parts.append(part(make_tube("IronCollar", collar_points, [0.013] * len(collar_points),
                                sides=5, cap=False), "metal", rigid="neck_01"))

    # Teeth: two lower canines and a row of upper incisors.
    for side, sx in (("l", 1.0), ("r", -1.0)):
        parts.append(part(make_cone(f"Fang_{side}", (sx * 0.045, 0.315, 1.815),
                                    (sx * 0.045, 0.335, 1.880), 0.012, 6),
                          "teeth", rigid="head"))
    parts.append(part(make_box("Incisors", (0.0, 0.345, 1.825), (0.075, 0.030, 0.020), bevel=0.004),
                      "teeth", rigid="jaw"))
    parts.append(part(make_box("Mouth", (0.0, 0.285, 1.805), (0.080, 0.100, 0.018)),
                      "mouth", rigid="jaw"))
    parts.append(part(make_uv_sphere("Nose", (0.0, 0.425, 1.845), 0.038, (1.2, 0.85, 0.75), 18, 12),
                      "skin", rigid="head"))
    return parts


# ---------------------------------------------------------------------------
# Clips


def _base():
    return {"rot": {}, "legs": {}}


def idle(t: float) -> dict:
    phase = (t / 2.4) % 1.0
    breath = math.sin(TAU * phase)
    scan = math.sin(TAU * phase * 0.5)
    values = _base()
    values["pelvis_offset"] = (0.006 * math.sin(TAU * phase + 0.4), 0.0, 0.012 * breath)
    values["pelvis_roll"] = 0.020 * math.sin(TAU * phase)
    values["pelvis_yaw"] = 0.014 * scan
    values["pelvis_pitch"] = 0.010 * breath
    values["jaw_open"] = 0.035 + 0.015 * breath
    values["rot"] = {
        "spine_01": (0.025 * breath, -0.010 * scan, 0.006 * breath),
        "spine_02": (0.020 * breath, -0.012 * scan, 0.006 * breath),
        "chest": (-0.045 * breath, -0.018 * scan, 0.010 * breath),
        "neck_01": (0.020 * breath, 0.030 * scan, -0.008 * breath),
        "neck_02": (0.018 * breath, 0.040 * scan, 0.0),
        "head": (-0.012 * breath, 0.075 * scan, 0.020 * math.sin(TAU * phase * 0.7)),
        "upper_arm_l": (0.030 * breath, 0.0, 0.030),
        "upper_arm_r": (0.030 * breath, 0.0, -0.030),
        "forearm_l": (0.300 + 0.030 * breath, 0.0, 0.0),
        "forearm_r": (0.300 + 0.030 * breath, 0.0, 0.0),
        "hand_l": (0.060, 0.0, 0.0),
        "hand_r": (0.060, 0.0, 0.0),
        "tail_01": (0.070 * breath, 0.120 * math.sin(TAU * phase * 0.65), 0.0),
        "tail_02": (0.050 * breath, 0.160 * math.sin(TAU * phase * 0.65 + 0.5), 0.0),
        "tail_03": (0.030 * breath, 0.180 * math.sin(TAU * phase * 0.65 + 1.0), 0.0),
        "ear_l": (0.05 * math.sin(TAU * phase * 1.3), 0.0, 0.08 * math.sin(TAU * phase * 0.9)),
        "ear_r": (0.05 * math.sin(TAU * phase * 1.1 + 1.2), 0.0, -0.08 * math.sin(TAU * phase * 0.8)),
    }
    values["legs"] = {
        "leg_l": {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0},
        "leg_r": {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0},
    }
    return values


def walk(t: float) -> dict:
    phase = (t / 1.1) % 1.0
    swing = math.cos(TAU * phase)
    values = _base()
    values["pelvis_offset"] = (0.014 * math.sin(TAU * phase), 0.0,
                               0.026 * abs(math.sin(TAU * phase * 2.0)) - 0.010)
    values["pelvis_yaw"] = 0.065 * math.sin(TAU * phase)
    values["pelvis_roll"] = 0.035 * swing
    values["pelvis_pitch"] = 0.020
    values["rot"] = {
        "spine_01": (0.030, -0.030 * math.sin(TAU * phase), 0.012 * swing),
        "spine_02": (0.025, -0.040 * math.sin(TAU * phase), 0.010 * swing),
        "chest": (0.010, -0.055 * math.sin(TAU * phase), 0.012 * swing),
        "neck_01": (-0.010, 0.040 * math.sin(TAU * phase), -0.010 * swing),
        "neck_02": (-0.010, 0.040 * math.sin(TAU * phase), -0.010 * swing),
        "head": (-0.020, 0.035 * math.sin(TAU * phase), 0.015 * swing),
        "upper_arm_l": (-0.34 * swing, 0.0, 0.035),
        "upper_arm_r": (0.34 * swing, 0.0, -0.035),
        "forearm_l": (0.36 + 0.10 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.36 + 0.10 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.05, 0.0, 0.0),
        "hand_r": (0.05, 0.0, 0.0),
        "tail_01": (0.05, 0.12 * math.sin(TAU * phase), 0.0),
        "tail_02": (0.04, 0.16 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (0.03, 0.20 * math.sin(TAU * phase + 0.8), 0.0),
    }
    gait_chains_offsets = {"leg_l": 0.0, "leg_r": 0.5}
    _gait(values, phase, 0.62, 1.45, 0.075, gait_chains_offsets)
    return values


def run(t: float) -> dict:
    phase = (t / 0.65) % 1.0
    swing = math.cos(TAU * phase)
    values = _base()
    values["pelvis_offset"] = (0.020 * math.sin(TAU * phase), 0.0,
                               0.050 * abs(math.sin(TAU * phase * 2.0)) - 0.018)
    values["pelvis_yaw"] = 0.090 * math.sin(TAU * phase)
    values["pelvis_roll"] = 0.050 * swing
    values["pelvis_pitch"] = 0.070
    values["rot"] = {
        "spine_01": (0.065, -0.050 * math.sin(TAU * phase), 0.018 * swing),
        "spine_02": (0.060, -0.070 * math.sin(TAU * phase), 0.015 * swing),
        "chest": (0.045, -0.085 * math.sin(TAU * phase), 0.020 * swing),
        "neck_01": (-0.050, 0.070 * math.sin(TAU * phase), -0.015 * swing),
        "neck_02": (-0.045, 0.060 * math.sin(TAU * phase), -0.015 * swing),
        "head": (-0.060, 0.050 * math.sin(TAU * phase), 0.020 * swing),
        "upper_arm_l": (-0.82 * swing, 0.0, 0.060),
        "upper_arm_r": (0.82 * swing, 0.0, -0.060),
        "forearm_l": (0.55 + 0.22 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.55 + 0.22 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.10, 0.0, 0.0),
        "hand_r": (0.10, 0.0, 0.0),
        "tail_01": (0.10, 0.10 * math.sin(TAU * phase), 0.0),
        "tail_02": (0.08, 0.14 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (0.06, 0.18 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _gait(values, phase, 0.38, 2.35, 0.165, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def attack(t: float) -> dict:
    u = min(1.0, t / 1.45)
    values = _base()
    values["pelvis_offset"] = (
        0.0,
        keyed(u, [(0.0, 0.0), (0.20, -0.09), (0.38, -0.15), (0.52, 0.20),
                  (0.62, 0.34), (0.82, 0.12), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.20, -0.08), (0.38, -0.10), (0.52, 0.02),
                  (0.62, -0.04), (0.82, 0.02), (1.0, 0.0)]),
    )
    values["pelvis_pitch"] = keyed(u, [(0.0, 0.0), (0.22, -0.14), (0.38, -0.22),
                                       (0.52, 0.18), (0.62, 0.36), (0.82, 0.12), (1.0, 0.0)])
    values["pelvis_yaw"] = keyed(u, [(0.0, 0.0), (0.38, 0.10), (0.62, -0.04), (1.0, 0.0)])
    values["pelvis_roll"] = keyed(u, [(0.0, 0.0), (0.38, 0.06), (0.62, -0.06), (1.0, 0.0)])
    values["jaw_open"] = keyed(u, [(0.0, 0.04), (0.38, 0.12), (0.60, 0.46), (0.72, 0.38), (1.0, 0.05)])
    values["rot"] = {
        "spine_01": (keyed(u, [(0.0, 0.0), (0.38, -0.10), (0.62, 0.26), (1.0, 0.0)]), 0.0, 0.0),
        "spine_02": (keyed(u, [(0.0, 0.0), (0.38, -0.14), (0.62, 0.30), (1.0, 0.0)]), 0.0, 0.0),
        "chest": (keyed(u, [(0.0, 0.0), (0.38, -0.18), (0.62, 0.34), (1.0, 0.0)]), 0.0, 0.0),
        "neck_01": (keyed(u, [(0.0, 0.0), (0.38, -0.22), (0.62, 0.30), (1.0, 0.0)]), 0.0, 0.0),
        "neck_02": (keyed(u, [(0.0, 0.0), (0.38, -0.20), (0.62, 0.24), (1.0, 0.0)]), 0.0, 0.0),
        "head": (keyed(u, [(0.0, 0.0), (0.38, -0.42), (0.52, -0.30), (0.62, 0.62),
                           (0.78, 0.30), (1.0, 0.0)]), 0.0, 0.0),
        "upper_arm_l": (keyed(u, [(0.0, 0.0), (0.38, -0.75), (0.62, 0.98), (0.82, 0.45), (1.0, 0.0)]),
                        0.0, 0.08),
        "upper_arm_r": (keyed(u, [(0.0, 0.0), (0.38, -0.70), (0.62, 0.92), (0.82, 0.40), (1.0, 0.0)]),
                        0.0, -0.08),
        "forearm_l": (keyed(u, [(0.0, 0.30), (0.38, 0.72), (0.62, 0.18), (1.0, 0.30)]), 0.0, 0.0),
        "forearm_r": (keyed(u, [(0.0, 0.30), (0.38, 0.68), (0.62, 0.20), (1.0, 0.30)]), 0.0, 0.0),
        "hand_l": (keyed(u, [(0.0, 0.05), (0.62, -0.35), (1.0, 0.05)]), 0.0, 0.0),
        "hand_r": (keyed(u, [(0.0, 0.05), (0.62, -0.35), (1.0, 0.05)]), 0.0, 0.0),
        "tail_01": (keyed(u, [(0.0, 0.05), (0.38, -0.20), (0.62, 0.30), (1.0, 0.05)]), 0.0, 0.0),
        "tail_02": (keyed(u, [(0.0, 0.03), (0.38, -0.16), (0.62, 0.26), (1.0, 0.03)]), 0.0, 0.0),
        "tail_03": (keyed(u, [(0.0, 0.0), (0.38, -0.12), (0.62, 0.20), (1.0, 0.0)]), 0.0, 0.0),
    }
    values["legs"] = {
        "leg_l": {"y": keyed(u, [(0.0, 0.0), (0.38, -0.10), (0.62, 0.28), (0.85, 0.10), (1.0, 0.0)]),
                  "lift": keyed(u, [(0.0, 0.0), (0.38, 0.0), (0.52, 0.12), (0.62, 0.0), (1.0, 0.0)]),
                  "toe": 0.0, "foot": keyed(u, [(0.0, 0.0), (0.62, -0.18), (1.0, 0.0)])},
        "leg_r": {"y": keyed(u, [(0.0, 0.0), (0.38, 0.10), (0.62, -0.22), (0.85, -0.08), (1.0, 0.0)]),
                  "lift": keyed(u, [(0.0, 0.0), (0.38, 0.0), (0.52, 0.10), (0.62, 0.0), (1.0, 0.0)]),
                  "toe": 0.0, "foot": keyed(u, [(0.0, 0.0), (0.62, 0.20), (1.0, 0.0)])},
    }
    return values


def hit(t: float) -> dict:
    u = min(1.0, t / 0.5)
    recoil = keyed(u, [(0.0, 0.0), (0.22, 1.0), (0.55, 0.55), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (0.0, -0.09 * recoil, -0.025 * recoil)
    values["pelvis_pitch"] = -0.12 * recoil
    values["pelvis_roll"] = 0.10 * recoil
    values["jaw_open"] = 0.20 * recoil
    values["rot"] = {
        "spine_01": (-0.16 * recoil, 0.0, 0.05 * recoil),
        "spine_02": (-0.18 * recoil, 0.0, 0.06 * recoil),
        "chest": (-0.20 * recoil, 0.0, 0.08 * recoil),
        "neck_01": (-0.20 * recoil, 0.0, 0.08 * recoil),
        "head": (-0.34 * recoil, 0.12 * recoil, 0.16 * recoil),
        "upper_arm_l": (-0.30 * recoil, 0.0, 0.18 * recoil),
        "upper_arm_r": (-0.26 * recoil, 0.0, -0.14 * recoil),
        "forearm_l": (0.55 * recoil + 0.30, 0.0, 0.0),
        "forearm_r": (0.52 * recoil + 0.30, 0.0, 0.0),
        "tail_01": (-0.20 * recoil, 0.15 * recoil, 0.0),
        "tail_02": (-0.16 * recoil, 0.18 * recoil, 0.0),
        "tail_03": (-0.12 * recoil, 0.20 * recoil, 0.0),
    }
    values["legs"] = {
        "leg_l": {"y": 0.06 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.06 * recoil},
        "leg_r": {"y": -0.06 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.06 * recoil},
    }
    return values


def death(t: float) -> dict:
    u = min(1.0, t / 1.25)
    collapse = keyed(u, [(0.0, 0.0), (0.20, 0.12), (0.55, 0.72), (0.82, 1.0), (1.0, 1.0)])
    roll = keyed(u, [(0.0, 0.0), (0.25, 0.20), (0.62, 0.85), (0.88, 1.12), (1.0, 1.12)])
    values = _base()
    values["pelvis_offset"] = (
        keyed(u, [(0.0, 0.0), (0.4, 0.06), (0.8, 0.14), (1.0, 0.16)]),
        keyed(u, [(0.0, 0.0), (0.3, -0.08), (0.7, 0.08), (1.0, 0.10)]),
        -0.60 * collapse,
    )
    values["pelvis_pitch"] = 0.55 * collapse
    values["pelvis_roll"] = roll
    values["pelvis_yaw"] = 0.22 * collapse
    values["jaw_open"] = 0.18 + 0.12 * collapse
    values["rot"] = {
        "spine_01": (0.20 * collapse, 0.10 * collapse, 0.12 * collapse),
        "spine_02": (0.22 * collapse, 0.12 * collapse, 0.14 * collapse),
        "chest": (0.18 * collapse, 0.10 * collapse, 0.12 * collapse),
        "neck_01": (-0.20 * collapse, -0.15 * collapse, -0.18 * collapse),
        "neck_02": (-0.22 * collapse, -0.18 * collapse, -0.20 * collapse),
        "head": (-0.35 * collapse, -0.20 * collapse, -0.28 * collapse),
        "upper_arm_l": (-0.45 * collapse, 0.0, 0.45 * collapse),
        "upper_arm_r": (-0.35 * collapse, 0.0, -0.50 * collapse),
        "forearm_l": (0.30 + 0.45 * collapse, 0.0, 0.0),
        "forearm_r": (0.30 + 0.30 * collapse, 0.0, 0.0),
        "hand_l": (0.05, 0.0, 0.0),
        "hand_r": (0.05, 0.0, 0.0),
        "tail_01": (0.20 * collapse, 0.22 * collapse, 0.0),
        "tail_02": (0.16 * collapse, 0.24 * collapse, 0.0),
        "tail_03": (0.12 * collapse, 0.26 * collapse, 0.0),
    }
    values["legs"] = {
        "leg_l": {"y": -0.10 * collapse, "lift": 0.0, "toe": 0.20 * collapse, "foot": 0.25 * collapse},
        "leg_r": {"y": 0.18 * collapse, "lift": 0.10 * collapse, "toe": -0.15 * collapse, "foot": -0.20 * collapse},
    }
    return values


def _gait(values: dict, phase: float, duty: float, stride: float,
          clearance: float, offsets: dict) -> None:
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
            toe = -0.32 * math.sin(math.pi * p)
            foot = 0.20 * math.sin(math.pi * p)
        values["legs"][chain_key] = {"y": y, "lift": lift, "toe": toe, "foot": foot}


CLIPS = {
    "idle": {"name": "HellGoat_Idle_Loop", "duration": 2.4, "loop": True},
    "walk": {"name": "HellGoat_Walk_Loop", "duration": 1.1, "loop": True,
             "stride": 1.45, "duty": 0.62, "fallback_speed": 1.32},
    "run": {"name": "HellGoat_Run_Loop", "duration": 0.65, "loop": True,
            "stride": 2.35, "duty": 0.38, "fallback_speed": 3.62},
    "attack": {"name": "HellGoat_Attack", "duration": 1.45, "loop": False,
               "impact": 0.62, "recovery_end": 1.45},
    "hit": {"name": "HellGoat_Hit", "duration": 0.5, "loop": False},
    "death": {"name": "HellGoat_Death", "duration": 1.25, "loop": False},
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
    "id": "hell_goat",
    "display_name": "Hellish goat man",
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
    "paint_tags": ["body", "skin", "fur", "hair", "horn", "hoof", "claw",
                   "eye", "teeth", "mouth", "leather", "metal"],
    "eyes": EYES,
    "normal_strength": 1.15,
    "build_parts": build_parts,
    "clips": CLIPS,
    "poses": POSES,
    "head_zone": {"bone": "head", "radius": 0.30, "half_height": 0.14},
    "metadata_extra": {
        "role": "charger",
        "surface_notes": ["procedural charcoal fur", "ram horn", "cloven hoof",
                          "ember eyes", "leather harness", "iron collar"],
    },
}
