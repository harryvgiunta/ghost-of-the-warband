"""Slate-stone gargoyle sentinel: winged devil brute with molten seams.

Silhouette: 2.35 m, hunched between slab shoulders, folded stone wings mantling
the back, heavy knuckled fists, thick digitigrade legs and a spade tail. The
surface is chipped slate with lichen on upward plates and ember light bleeding
out of the deeper cracks. Slow and heavy: long idle, pounding gait, a two-fist
overhead slam, and a death that folds onto its side.
"""

from __future__ import annotations

import math

import numpy as np
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree

from devil_pipeline import (
    TAU,
    add_ellipsoid,
    add_segment,
    apply_displacement,
    build_metaball,
    fbm,
    keyed,
    make_box,
    make_cone,
    make_membrane,
    make_tube,
    make_uv_sphere,
    part,
)

SCENE = "Gargoyle"
HEIGHT = 2.35

BONES = {
    "root": {"head": (0.0, 0.0, 0.0), "tail": (0.0, 0.0, 0.15), "deform": False},
    "pelvis": {"head": (0.0, 0.0, 1.02), "tail": (0.0, 0.02, 1.16), "parent": "root"},
    "spine_01": {"head": (0.0, 0.02, 1.16), "tail": (0.0, 0.04, 1.32),
                 "parent": "pelvis", "connect": True},
    "spine_02": {"head": (0.0, 0.04, 1.32), "tail": (0.0, 0.05, 1.48),
                 "parent": "spine_01", "connect": True},
    "chest": {"head": (0.0, 0.05, 1.48), "tail": (0.0, 0.06, 1.62),
              "parent": "spine_02", "connect": True},
    "neck_01": {"head": (0.0, 0.06, 1.62), "tail": (0.0, 0.09, 1.72),
                "parent": "chest", "connect": True},
    "neck_02": {"head": (0.0, 0.09, 1.72), "tail": (0.0, 0.11, 1.80),
                "parent": "neck_01", "connect": True},
    "head": {"head": (0.0, 0.11, 1.80), "tail": (0.0, 0.18, 1.94),
             "parent": "neck_02", "connect": True},
    "jaw": {"head": (0.0, 0.16, 1.86), "tail": (0.0, 0.30, 1.80), "parent": "head"},
    "tail_01": {"head": (0.0, -0.06, 1.02), "tail": (0.0, -0.24, 0.94), "parent": "pelvis"},
    "tail_02": {"head": (0.0, -0.24, 0.94), "tail": (0.0, -0.40, 0.88),
                "parent": "tail_01", "connect": True},
    "tail_03": {"head": (0.0, -0.40, 0.88), "tail": (0.0, -0.54, 0.90),
                "parent": "tail_02", "connect": True},
}

for side, sx in (("l", 1.0), ("r", -1.0)):
    BONES.update({
        f"clavicle_{side}": {"head": (sx * 0.04, 0.05, 1.58),
                             "tail": (sx * 0.22, 0.05, 1.60), "parent": "chest"},
        f"upper_arm_{side}": {"head": (sx * 0.22, 0.05, 1.60),
                              "tail": (sx * 0.38, 0.04, 1.34),
                              "parent": f"clavicle_{side}", "connect": True},
        f"forearm_{side}": {"head": (sx * 0.38, 0.04, 1.34),
                            "tail": (sx * 0.46, 0.06, 1.06),
                            "parent": f"upper_arm_{side}", "connect": True},
        f"hand_{side}": {"head": (sx * 0.46, 0.06, 1.06),
                         "tail": (sx * 0.48, 0.13, 0.94),
                         "parent": f"forearm_{side}", "connect": True},
        f"fingers_{side}": {"head": (sx * 0.48, 0.13, 0.94),
                            "tail": (sx * 0.48, 0.22, 0.88),
                            "parent": f"hand_{side}", "connect": True},
        f"thigh_{side}": {"head": (sx * 0.15, -0.01, 1.00),
                          "tail": (sx * 0.19, 0.08, 0.64), "parent": "pelvis"},
        f"shin_{side}": {"head": (sx * 0.19, 0.08, 0.64),
                         "tail": (sx * 0.20, -0.06, 0.34),
                         "parent": f"thigh_{side}", "connect": True},
        f"tarsus_{side}": {"head": (sx * 0.20, -0.06, 0.34),
                           "tail": (sx * 0.20, 0.04, 0.15),
                           "parent": f"shin_{side}", "connect": True},
        f"foot_{side}": {"head": (sx * 0.20, 0.04, 0.15),
                         "tail": (sx * 0.20, 0.16, 0.06),
                         "parent": f"tarsus_{side}", "connect": True},
        f"toes_{side}": {"head": (sx * 0.20, 0.16, 0.06),
                         "tail": (sx * 0.20, 0.28, 0.045),
                         "parent": f"foot_{side}", "connect": True},
        f"wing_root_{side}": {"head": (sx * 0.06, 0.06, 1.46),
                              "tail": (sx * 0.26, 0.14, 1.66), "parent": "chest"},
        f"wing_mid_{side}": {"head": (sx * 0.26, 0.14, 1.66),
                             "tail": (sx * 0.44, 0.06, 1.58),
                             "parent": f"wing_root_{side}", "connect": True},
        f"wing_tip_{side}": {"head": (sx * 0.44, 0.06, 1.58),
                             "tail": (sx * 0.36, -0.10, 1.18),
                             "parent": f"wing_mid_{side}", "connect": True},
    })

CHAINS = {
    "leg_l": {"bones": ["thigh_l", "shin_l", "tarsus_l", "foot_l", "toes_l"], "pole": -1.0},
    "leg_r": {"bones": ["thigh_r", "shin_r", "tarsus_r", "foot_r", "toes_r"], "pole": -1.0},
}

SKIN_BONES = {
    "pelvis": (0.30, 0.9),
    "spine_01": (0.30, 0.9),
    "spine_02": (0.31, 0.9),
    "chest": (0.38, 1.0),
    "neck_01": (0.16, 1.0),
    "neck_02": (0.15, 1.0),
    "head": (0.22, 1.1),
    "jaw": (0.15, 1.1),
    "tail_01": (0.09, 1.0),
    "tail_02": (0.075, 1.0),
    "tail_03": (0.065, 1.0),
}
for side in ("l", "r"):
    SKIN_BONES.update({
        f"clavicle_{side}": (0.16, 1.1),
        f"upper_arm_{side}": (0.16, 1.6),
        f"forearm_{side}": (0.145, 1.7),
        f"hand_{side}": (0.13, 1.7),
        f"fingers_{side}": (0.10, 1.7),
        f"thigh_{side}": (0.19, 1.4),
        f"shin_{side}": (0.145, 1.5),
        f"tarsus_{side}": (0.11, 1.5),
        f"foot_{side}": (0.12, 1.5),
        f"toes_{side}": (0.115, 1.5),
        f"wing_root_{side}": (0.12, 0.9),
        f"wing_mid_{side}": (0.11, 1.1),
        f"wing_tip_{side}": (0.09, 1.1),
    })

ROTATION_ORDER = [
    "spine_01", "spine_02", "chest", "neck_01", "neck_02", "head",
    "clavicle_l", "upper_arm_l", "forearm_l", "hand_l", "fingers_l",
    "clavicle_r", "upper_arm_r", "forearm_r", "hand_r", "fingers_r",
    "wing_root_l", "wing_mid_l", "wing_tip_l",
    "wing_root_r", "wing_mid_r", "wing_tip_r",
    "tail_01", "tail_02", "tail_03",
]
SWAY_BONES = ["spine_01", "spine_02", "chest", "neck_01", "neck_02", "head"]

PALETTE = {
    "body": {"kind": "stone", "base": "#3f454e", "second": "#16202d", "accent": "#747a8a",
             "roughness": 0.86, "grain_scale": 46.0, "speckle_scale": 380.0,
             "lichen_scale": 7.5, "crack_scale": 15.0, "ember_cracks": 0.55,
             "ember": "#ff6a22", "seed": 101},
    "stone": {"kind": "stone", "base": "#3f454e", "second": "#16202d", "accent": "#747a8a",
              "roughness": 0.86, "grain_scale": 52.0, "speckle_scale": 420.0,
              "lichen_scale": 8.5, "crack_scale": 17.0, "ember_cracks": 0.55,
              "ember": "#ff6a22", "seed": 103},
    "stone_dark": {"kind": "stone", "base": "#161c24", "second": "#0a0e13", "accent": "#3a424c",
                   "roughness": 0.90, "grain_scale": 60.0, "speckle_scale": 440.0,
                   "lichen_scale": 10.0, "crack_scale": 22.0, "ember_cracks": 0.42,
                   "ember": "#ff6a22", "seed": 107},
    "lichen": {"kind": "stone", "base": "#5a6a4a", "second": "#2c3426", "accent": "#6f7f5a",
               "roughness": 0.93, "grain_scale": 88.0, "speckle_scale": 520.0,
               "lichen_scale": 13.0, "crack_scale": 26.0, "seed": 109},
    "membrane": {"kind": "membrane", "base": "#2b323b", "second": "#10151c",
                 "accent": "#ff6a22", "roughness": 0.80, "vein_scale": 30.0,
                 "glow": 0.22, "seed": 113},
    "horn": {"kind": "horn", "base": "#4a5058", "second": "#20262e", "accent": "#8a929e",
             "roughness": 0.42, "ring_frequency": 150.0, "ring_height": 0.00045,
             "crack_scale": 30.0, "crack_mix": 0.35, "axis": (0.0, 0.3, 1.0), "seed": 127},
    "claw": {"kind": "claw", "base": "#4a5058", "second": "#20262e", "accent": "#8a929e",
             "roughness": 0.40, "ring_frequency": 190.0, "crack_scale": 48.0,
             "crack_mix": 0.45, "seed": 131},
    "eye": {"kind": "eye", "base": "#1a0c06", "roughness": 0.06, "seed": 137},
    "teeth": {"kind": "teeth", "base": "#c8b898", "second": "#8a7a5e", "accent": "#4a3c28",
              "roughness": 0.38, "seed": 139},
    "mouth": {"kind": "mouth", "base": "#1a0808", "second": "#080202", "accent": "#4a1414",
              "roughness": 0.30, "seed": 149},
}

EYES = [{
    "center": (0.076, 0.205, 1.876),
    "forward": (0.10, 0.99, -0.07),
    "radius": 0.038,
    "iris": "#ff8a2a",
    "pupil_colour": "#050202",
    "sclera": "#1a0c06",
    "pupil": 0.28,
    "iris_edge": 0.72,
    "emission": 1.8,
}, {
    "center": (-0.076, 0.205, 1.876),
    "forward": (-0.10, 0.99, -0.07),
    "radius": 0.038,
    "iris": "#ff8a2a",
    "pupil_colour": "#050202",
    "sclera": "#1a0c06",
    "pupil": 0.28,
    "iris_edge": 0.72,
    "emission": 1.8,
}]


def classify(P: np.ndarray, N: np.ndarray) -> np.ndarray:
    """Rest-space surface tags: dark joints, lichen on upward plates, slate."""
    x = np.abs(P[:, 0])
    z = P[:, 2]
    y = P[:, 1]
    armpit = (z > 1.38) & (z < 1.60) & (x > 0.20) & (y < 0.02)
    crotch = (z > 0.86) & (z < 1.08) & (x < 0.24) & (y < 0.08)
    throat = (z > 1.63) & (z < 1.80) & (y < 0.13) & (x < 0.16)
    knee = (z > 0.28) & (z < 0.48) & (x > 0.13) & (y < -0.05)
    neck_back = (z > 1.60) & (z < 1.79) & (y < -0.02)
    joint = armpit | crotch | throat | knee | neck_back
    lichen = (N[:, 2] > 0.40) & (z > 0.45) & (fbm(P, 6.0, 733) > 0.50)
    return np.where(joint, "stone_dark", np.where(lichen, "lichen", "stone"))


def _wing_grid(sx: float) -> list[list[tuple[float, float, float]]]:
    """Folded stone sail: wing leading edge stitched to the rear flank."""
    edge = [
        (0.06, 0.06, 1.46),
        (0.26, 0.14, 1.66),
        (0.35, 0.10, 1.62),
        (0.44, 0.06, 1.58),
        (0.36, -0.10, 1.18),
    ]
    inner = [
        (0.14, -0.11, 1.34),
        (0.18, -0.13, 1.28),
        (0.23, -0.13, 1.24),
        (0.27, -0.12, 1.22),
        (0.30, -0.09, 1.28),
    ]
    columns = 4
    grid = []
    for outer, anchor in zip(edge, inner):
        row = []
        for column in range(columns):
            t = column / (columns - 1)
            drape = math.sin(math.pi * t)
            point = [outer[i] * (1.0 - t) + anchor[i] * t for i in range(3)]
            point[0] += 0.020 * drape
            point[1] -= 0.045 * drape
            point[2] -= 0.014 * drape
            row.append((sx * point[0], point[1], point[2]))
        grid.append(row)
    return grid


def build_parts():
    parts = []

    def body_builder(mb):
        # Hips, waist, rib cage and the slab chest that carries the shoulders.
        add_ellipsoid(mb, (0.0, -0.005, 1.05), (0.22, 0.18, 0.145))
        add_ellipsoid(mb, (0.0, 0.015, 1.21), (0.195, 0.165, 0.15))
        add_ellipsoid(mb, (0.0, 0.03, 1.37), (0.255, 0.185, 0.17))
        add_ellipsoid(mb, (0.0, 0.05, 1.52), (0.32, 0.20, 0.165))
        add_ellipsoid(mb, (0.0, 0.10, 1.56), (0.19, 0.15, 0.13))
        add_ellipsoid(mb, (0.0, 0.0, 1.64), (0.26, 0.14, 0.10))
        for sx in (-1.0, 1.0):
            # Shoulder slabs, front deltoid and the trapezius ramp.
            add_ellipsoid(mb, (sx * 0.27, 0.03, 1.585), (0.135, 0.15, 0.15))
            add_ellipsoid(mb, (sx * 0.235, 0.11, 1.55), (0.10, 0.10, 0.11))
            add_ellipsoid(mb, (sx * 0.12, 0.02, 1.66), (0.10, 0.11, 0.08))
        # Short thick neck.
        add_segment(mb, (0.0, 0.05, 1.63), (0.0, 0.09, 1.78), 0.10)
        add_ellipsoid(mb, (0.0, 0.08, 1.745), (0.105, 0.105, 0.075))
        # Skull, brow shelf, flat face plate, muzzle and heavy underjaw.
        add_ellipsoid(mb, (0.0, 0.09, 1.89), (0.155, 0.135, 0.115))
        add_ellipsoid(mb, (0.0, 0.13, 1.865), (0.115, 0.095, 0.075))
        add_ellipsoid(mb, (0.0, 0.17, 1.928), (0.15, 0.07, 0.048))
        add_ellipsoid(mb, (0.0, 0.20, 1.845), (0.10, 0.095, 0.062))
        add_ellipsoid(mb, (0.0, 0.25, 1.830), (0.078, 0.06, 0.045))
        add_ellipsoid(mb, (0.0, 0.205, 1.805), (0.095, 0.10, 0.048))
        add_ellipsoid(mb, (0.0, 0.265, 1.800), (0.055, 0.05, 0.032))
        for sx in (-1.0, 1.0):
            add_ellipsoid(mb, (sx * 0.125, 0.155, 1.845), (0.065, 0.075, 0.062))
            add_ellipsoid(mb, (sx * 0.105, 0.11, 1.83), (0.05, 0.06, 0.05))
            # Negative element: a real ember socket over each eye.
            socket = add_ellipsoid(mb, (sx * 0.076, 0.245, 1.878), (0.054, 0.062, 0.048),
                                   stiffness=3.0)
            socket.use_negative = True
            # Arms: chunky upper arm, swollen forearm, fist.
            add_segment(mb, (sx * 0.255, 0.04, 1.56), (sx * 0.38, 0.04, 1.34), 0.095)
            add_ellipsoid(mb, (sx * 0.38, 0.04, 1.34), (0.088, 0.092, 0.088))
            add_segment(mb, (sx * 0.38, 0.04, 1.34), (sx * 0.46, 0.06, 1.07), 0.105)
            add_ellipsoid(mb, (sx * 0.46, 0.06, 1.07), (0.078, 0.082, 0.075))
            add_ellipsoid(mb, (sx * 0.48, 0.12, 0.955), (0.085, 0.105, 0.095))
            add_ellipsoid(mb, (sx * 0.48, 0.19, 0.91), (0.07, 0.075, 0.07))
            # Legs: haunch, thigh, knee, shin, hock, cannon, foot.
            add_ellipsoid(mb, (sx * 0.15, -0.01, 1.00), (0.13, 0.15, 0.155))
            add_segment(mb, (sx * 0.15, -0.01, 1.00), (sx * 0.19, 0.08, 0.64), 0.108)
            add_ellipsoid(mb, (sx * 0.19, 0.08, 0.64), (0.095, 0.098, 0.09))
            add_segment(mb, (sx * 0.19, 0.08, 0.64), (sx * 0.20, -0.06, 0.34), 0.077)
            add_ellipsoid(mb, (sx * 0.20, -0.06, 0.34), (0.072, 0.078, 0.07))
            add_segment(mb, (sx * 0.20, -0.06, 0.34), (sx * 0.20, 0.04, 0.15), 0.056)
            add_ellipsoid(mb, (sx * 0.20, 0.10, 0.075), (0.075, 0.10, 0.058))
            add_ellipsoid(mb, (sx * 0.20, 0.23, 0.05), (0.07, 0.075, 0.038))
        # Tail root and taper.
        add_segment(mb, (0.0, -0.06, 1.02), (0.0, -0.24, 0.94), 0.052)
        add_segment(mb, (0.0, -0.24, 0.94), (0.0, -0.40, 0.88), 0.040)
        add_segment(mb, (0.0, -0.40, 0.88), (0.0, -0.54, 0.90), 0.028)

    body = build_metaball("GargoyleBody", 0.0102, 0.6, body_builder,
                          decimate_ratio=0.32, smoothing=1)
    # Low-frequency chipped planes: broken slate rather than smooth flesh.
    apply_displacement(body, lambda points: (fbm(points, 9.0, 991) - 0.5) * 2.0, 0.010)
    parts.append(part(body, "body"))
    body_tree = BVHTree.FromPolygons([vertex.co.copy() for vertex in body.data.vertices],
                                     [tuple(polygon.vertices) for polygon in body.data.polygons])

    def surface_plate(hint, size, twist):
        """Sit a chipped plate flat on the slate, one third of it buried."""
        location, normal, _, _ = body_tree.find_nearest(Vector(hint))
        normal = Vector(normal).normalized()
        frame = normal.to_track_quat("Z", "Y").to_euler()
        quat = frame.to_quaternion() @ Quaternion((0.0, 0.0, 1.0), twist)
        centre = location + normal * (size[2] * 0.08)
        return (tuple(centre), tuple(size), tuple(quat.to_euler()))

    for side, sx in (("l", 1.0), ("r", -1.0)):
        # Heavy curved horns from the skull top, swept back over the mantle.
        horn_points = [
            (sx * 0.085, 0.090, 1.980),
            (sx * 0.125, 0.055, 2.090),
            (sx * 0.155, -0.010, 2.190),
            (sx * 0.170, -0.075, 2.285),
            (sx * 0.165, -0.115, 2.340),
        ]
        parts.append(part(make_tube(f"Horn_{side}", horn_points, [0.058, 0.052, 0.042, 0.026, 0.007],
                                    sides=10), "horn", rigid="head"))
        # Brow ridge over the ember eye.
        parts.append(part(make_tube(
            f"Brow_{side}",
            [(sx * 0.020, 0.252, 1.948), (sx * 0.080, 0.244, 1.940), (sx * 0.140, 0.216, 1.922)],
            [0.032, 0.027, 0.015], sides=7), "stone", rigid="head"))
        # Eye.
        parts.append(part(make_uv_sphere(f"Eye_{side}", (sx * 0.076, 0.205, 1.876),
                                         0.038, (1.0, 1.0, 1.0), 20, 14),
                          "eye", rigid="head"))
        # Shoulder and shoulder-blade spikes.
        parts.append(part(make_cone(f"ShoulderSpike_{side}",
                                    (sx * 0.25, 0.05, 1.655), (sx * 0.305, -0.02, 1.905),
                                    0.048, 7), "horn", rigid="chest"))
        parts.append(part(make_cone(f"BladeSpike_{side}",
                                    (sx * 0.165, -0.055, 1.625), (sx * 0.205, -0.125, 1.805),
                                    0.030, 6), "horn", rigid="chest"))
        # Folded stone wing: chunky leading edge plus the draped membrane.
        wing_points = [
            (sx * 0.06, 0.06, 1.46),
            (sx * 0.26, 0.14, 1.66),
            (sx * 0.35, 0.10, 1.62),
            (sx * 0.44, 0.06, 1.58),
            (sx * 0.36, -0.10, 1.18),
        ]
        parts.append(part(make_tube(f"WingArm_{side}", wing_points,
                                    [0.072, 0.062, 0.055, 0.042, 0.016], sides=8),
                          "stone"))
        parts.append(part(make_membrane(f"WingMembrane_{side}", _wing_grid(sx), 0.030),
                          "membrane"))
        # Fist claws.
        for index, offset in enumerate((-0.036, 0.0, 0.036)):
            parts.append(part(make_cone(
                f"HandClaw_{side}_{index}",
                (sx * 0.48 + offset, 0.215, 0.905),
                (sx * 0.48 + offset * 1.25, 0.300, 0.835), 0.014, 6),
                "claw", rigid=f"fingers_{side}"))
        # Toe blocks, heel plate and toe claws.
        for index, offset in enumerate((-0.048, 0.0, 0.048)):
            parts.append(part(make_box(
                f"Toe_{side}_{index}", (sx * 0.20 + offset, 0.270, 0.045),
                (0.055, 0.170, 0.090), bevel=0.012),
                "claw", rigid=f"toes_{side}"))
            parts.append(part(make_cone(
                f"ToeClaw_{side}_{index}",
                (sx * 0.20 + offset, 0.345, 0.045),
                (sx * 0.20 + offset, 0.405, 0.018), 0.012, 6),
                "claw", rigid=f"toes_{side}"))
        parts.append(part(make_box(f"Heel_{side}", (sx * 0.20, 0.100, 0.050),
                                   (0.115, 0.115, 0.100), bevel=0.014),
                          "claw", rigid=f"foot_{side}"))
        # Teeth.
        parts.append(part(make_cone(f"FangUpper_{side}", (sx * 0.070, 0.268, 1.845),
                                    (sx * 0.075, 0.283, 1.792), 0.013, 6),
                          "teeth", rigid="head"))
        parts.append(part(make_cone(f"FangLower_{side}", (sx * 0.065, 0.276, 1.790),
                                    (sx * 0.070, 0.288, 1.836), 0.011, 6),
                          "teeth", rigid="jaw"))

    # Spine ridge spikes down the back.
    for index, (base, tip, bone) in enumerate((
            ((0.0, -0.10, 1.600), (0.0, -0.165, 1.830), "chest"),
            ((0.0, -0.115, 1.470), (0.0, -0.190, 1.680), "spine_02"),
            ((0.0, -0.115, 1.340), (0.0, -0.190, 1.520), "spine_01"))):
        parts.append(part(make_cone(f"SpineSpike_{index}", base, tip, 0.038, 7),
                          "horn", rigid=bone))

    # Chipped slate plates: broken facets lifted off the chest, back and flanks.
    flakes = (
        ((0.215, 0.170, 1.500), (0.130, 0.105, 0.060), 0.35, "chest"),
        ((-0.215, 0.170, 1.500), (0.130, 0.105, 0.060), -0.35, "chest"),
        ((0.300, 0.090, 1.690), (0.095, 0.080, 0.055), 0.80, "chest"),
        ((-0.300, 0.090, 1.690), (0.095, 0.080, 0.055), -0.80, "chest"),
        ((0.060, -0.150, 1.520), (0.125, 0.095, 0.055), 0.20, "chest"),
        ((-0.060, -0.150, 1.520), (0.125, 0.095, 0.055), -0.20, "chest"),
        ((0.120, -0.155, 1.360), (0.110, 0.085, 0.055), 1.10, "spine_02"),
        ((-0.120, -0.155, 1.360), (0.110, 0.085, 0.055), -1.10, "spine_02"),
        ((0.0, -0.160, 1.230), (0.130, 0.090, 0.055), 0.0, "spine_01"),
        ((0.250, 0.020, 1.310), (0.090, 0.080, 0.050), 0.55, "spine_01"),
        ((-0.250, 0.020, 1.310), (0.090, 0.080, 0.050), -0.55, "spine_01"),
        ((0.310, 0.010, 1.450), (0.090, 0.075, 0.050), 0.90, "chest"),
        ((-0.310, 0.010, 1.450), (0.090, 0.075, 0.050), -0.90, "chest"),
        ((0.355, 0.075, 1.260), (0.080, 0.070, 0.045), 0.40, "upper_arm_l"),
        ((-0.355, 0.075, 1.260), (0.080, 0.070, 0.045), -0.40, "upper_arm_r"),
        ((0.0, 0.215, 1.600), (0.120, 0.070, 0.060), 0.0, "chest"),
    )
    for index, (hint, size, twist, bone) in enumerate(flakes):
        centre, dims, rotation = surface_plate(hint, size, twist)
        parts.append(part(make_box(f"Flake_{index}", centre, dims, rotation=rotation,
                                   bevel=0.012), "stone", rigid=bone))

    # Jaw: dark mouth box, incisor rows, and the tail spade with ridge spikes.
    parts.append(part(make_box("Mouth", (0.0, 0.255, 1.812), (0.130, 0.070, 0.026)),
                      "mouth", rigid="jaw"))
    parts.append(part(make_box("IncisorsUpper", (0.0, 0.286, 1.814), (0.100, 0.018, 0.022),
                               bevel=0.004), "teeth", rigid="head"))
    parts.append(part(make_box("IncisorsLower", (0.0, 0.290, 1.790), (0.085, 0.018, 0.018),
                               bevel=0.004), "teeth", rigid="jaw"))
    parts.append(part(make_box("TailSpade", (0.0, -0.585, 0.893), (0.075, 0.140, 0.030),
                               rotation=(0.25, 0.0, 0.0), bevel=0.008),
                      "horn", rigid="tail_03"))
    for index, (base, tip, bone) in enumerate((
            ((0.0, -0.215, 1.000), (0.0, -0.255, 1.062), "tail_01"),
            ((0.0, -0.355, 0.940), (0.0, -0.395, 1.000), "tail_02"),
            ((0.0, -0.495, 0.925), (0.0, -0.530, 0.982), "tail_03"))):
        parts.append(part(make_cone(f"TailSpike_{index}", base, tip, 0.020, 6),
                          "horn", rigid=bone))

    return parts


# ---------------------------------------------------------------------------
# Clips


def _base():
    return {"rot": {}, "legs": {}}


def _leg(y: float = 0.0, lift: float = 0.0, toe: float = 0.0, foot: float = 0.0) -> dict:
    return {"y": y, "lift": lift, "toe": toe, "foot": foot}


def idle(t: float) -> dict:
    phase = (t / 3.0) % 1.0
    breath = math.sin(TAU * phase)
    scan = math.sin(TAU * phase * 0.5)
    wing = math.sin(TAU * phase * 0.75 + 0.8)
    wing_late = math.sin(TAU * phase * 0.75 + 1.6)
    values = _base()
    values["pelvis_offset"] = (0.004 * math.sin(TAU * phase + 0.3), 0.0,
                               -0.006 + 0.008 * breath)
    values["pelvis_pitch"] = -0.012 - 0.006 * breath
    values["pelvis_roll"] = 0.010 * breath
    values["pelvis_yaw"] = 0.008 * scan
    values["jaw_open"] = 0.030 + 0.012 * breath
    values["rot"] = {
        "spine_01": (-0.015 + 0.008 * breath, -0.006 * scan, 0.004 * breath),
        "spine_02": (-0.020 + 0.010 * breath, -0.008 * scan, 0.005 * breath),
        "chest": (-0.030 + 0.020 * breath, -0.010 * scan, 0.008 * breath),
        "neck_01": (0.020 + 0.012 * breath, 0.020 * scan, -0.004 * breath),
        "neck_02": (0.025 + 0.008 * breath, 0.028 * scan, -0.004 * breath),
        "head": (0.020 - 0.010 * breath, 0.055 * scan, 0.012 * math.sin(TAU * phase * 0.5 + 1.1)),
        "clavicle_l": (0.004 * breath, 0.0, -0.010),
        "clavicle_r": (0.004 * breath, 0.0, 0.010),
        "upper_arm_l": (0.040 + 0.012 * breath, 0.0, -0.120),
        "upper_arm_r": (0.040 + 0.012 * breath, 0.0, 0.120),
        "forearm_l": (0.250 + 0.015 * breath, 0.0, -0.020),
        "forearm_r": (0.250 + 0.015 * breath, 0.0, 0.020),
        "hand_l": (0.030, 0.0, 0.0),
        "hand_r": (0.030, 0.0, 0.0),
        "fingers_l": (0.120, 0.0, 0.0),
        "fingers_r": (0.120, 0.0, 0.0),
        "wing_root_l": (-0.010 * wing, 0.0, 0.020 * wing),
        "wing_mid_l": (-0.006 * wing, 0.0, -0.014 * wing),
        "wing_tip_l": (0.004 * wing_late, 0.0, 0.010 * wing_late),
        "wing_root_r": (-0.010 * wing_late, 0.0, -0.020 * wing_late),
        "wing_mid_r": (-0.006 * wing_late, 0.0, 0.014 * wing_late),
        "wing_tip_r": (0.004 * wing, 0.0, -0.010 * wing),
        "tail_01": (-0.030, 0.070 * scan, 0.0),
        "tail_02": (-0.020, 0.090 * math.sin(TAU * phase * 0.5 + 0.5), 0.0),
        "tail_03": (-0.012, 0.100 * math.sin(TAU * phase * 0.5 + 1.0), 0.0),
    }
    values["legs"] = {"leg_l": _leg(), "leg_r": _leg()}
    return values


def walk(t: float) -> dict:
    phase = (t / 1.50) % 1.0
    swing = math.cos(TAU * phase)
    sway = math.sin(TAU * phase)
    bob = 0.028 * abs(math.sin(TAU * phase * 2.0))
    values = _base()
    values["pelvis_offset"] = (0.012 * sway, 0.0, -0.020 + bob)
    values["pelvis_pitch"] = -0.040
    values["pelvis_roll"] = 0.030 * swing
    values["pelvis_yaw"] = 0.050 * sway
    values["jaw_open"] = 0.040 + 0.010 * abs(swing)
    values["rot"] = {
        "spine_01": (-0.018, -0.028 * sway, 0.010 * swing),
        "spine_02": (-0.016, -0.036 * sway, 0.008 * swing),
        "chest": (-0.012, -0.048 * sway, 0.012 * swing),
        "neck_01": (0.020, 0.030 * sway, -0.008 * swing),
        "neck_02": (0.022, 0.034 * sway, -0.008 * swing),
        "head": (0.020, 0.028 * sway, 0.014 * swing),
        "clavicle_l": (0.0, 0.0, -0.010),
        "clavicle_r": (0.0, 0.0, 0.010),
        "upper_arm_l": (-0.220 * swing, 0.0, -0.100),
        "upper_arm_r": (0.220 * swing, 0.0, 0.100),
        "forearm_l": (0.260 + 0.070 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.260 + 0.070 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.030, 0.0, 0.0),
        "hand_r": (0.030, 0.0, 0.0),
        "fingers_l": (0.120, 0.0, 0.0),
        "fingers_r": (0.120, 0.0, 0.0),
        "wing_root_l": (0.010 * sway, 0.0, 0.024 + 0.012 * swing),
        "wing_mid_l": (-0.008 * sway, 0.0, -0.014 * swing),
        "wing_tip_l": (0.0, 0.0, 0.010 * sway),
        "wing_root_r": (0.010 * sway, 0.0, -0.024 - 0.012 * swing),
        "wing_mid_r": (-0.008 * sway, 0.0, 0.014 * swing),
        "wing_tip_r": (0.0, 0.0, -0.010 * sway),
        "tail_01": (-0.020, 0.100 * sway, 0.0),
        "tail_02": (-0.016, 0.130 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (-0.010, 0.150 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _gait(values, phase, 0.66, 1.70, 0.085, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def run(t: float) -> dict:
    phase = (t / 0.90) % 1.0
    swing = math.cos(TAU * phase)
    sway = math.sin(TAU * phase)
    bob = 0.052 * abs(math.sin(TAU * phase * 2.0))
    values = _base()
    values["pelvis_offset"] = (0.018 * sway, 0.0, -0.052 + bob)
    values["pelvis_pitch"] = -0.105
    values["pelvis_roll"] = 0.045 * swing
    values["pelvis_yaw"] = 0.075 * sway
    values["jaw_open"] = 0.070 + 0.020 * abs(swing)
    values["rot"] = {
        "spine_01": (-0.055, -0.045 * sway, 0.016 * swing),
        "spine_02": (-0.050, -0.060 * sway, 0.014 * swing),
        "chest": (-0.040, -0.075 * sway, 0.018 * swing),
        "neck_01": (0.075, 0.050 * sway, -0.012 * swing),
        "neck_02": (0.070, 0.055 * sway, -0.012 * swing),
        "head": (0.080, 0.045 * sway, 0.018 * swing),
        "clavicle_l": (-0.020, 0.0, -0.020),
        "clavicle_r": (-0.020, 0.0, 0.020),
        "upper_arm_l": (-0.460 * swing, 0.0, -0.120),
        "upper_arm_r": (0.460 * swing, 0.0, 0.120),
        "forearm_l": (0.420 + 0.150 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.420 + 0.150 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.040, 0.0, 0.0),
        "hand_r": (0.040, 0.0, 0.0),
        "fingers_l": (0.150, 0.0, 0.0),
        "fingers_r": (0.150, 0.0, 0.0),
        "wing_root_l": (-0.040 + 0.020 * sway, 0.0, 0.180),
        "wing_mid_l": (-0.030, 0.0, -0.100),
        "wing_tip_l": (0.020, 0.0, 0.030 * sway),
        "wing_root_r": (-0.040 - 0.020 * sway, 0.0, -0.180),
        "wing_mid_r": (-0.030, 0.0, 0.100),
        "wing_tip_r": (0.020, 0.0, -0.030 * sway),
        "tail_01": (-0.050, 0.090 * sway, 0.0),
        "tail_02": (-0.040, 0.120 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (-0.030, 0.150 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _gait(values, phase, 0.42, 2.90, 0.180, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def attack(t: float) -> dict:
    u = min(1.0, t / 1.80)
    impact = 0.95 / 1.80
    arm = keyed(u, [(0.0, 0.05), (0.16, -0.85), (0.32, -2.50), (0.44, -2.58),
                    (0.47, -1.70), (impact, 1.10), (0.60, 1.00), (0.72, 0.45), (1.0, 0.05)])
    forearm = keyed(u, [(0.0, 0.26), (0.20, 0.30), (0.34, 0.34), (0.44, 0.30),
                        (0.48, 0.55), (impact, 0.10), (0.62, 0.22), (0.78, 0.26), (1.0, 0.26)])
    torso = keyed(u, [(0.0, 0.0), (0.28, 0.060), (0.44, 0.085), (impact, -0.140),
                      (0.62, -0.120), (0.80, -0.035), (1.0, 0.0)])
    neck = keyed(u, [(0.0, 0.0), (0.30, -0.030), (0.44, -0.040), (impact, 0.065),
                     (0.62, 0.055), (0.80, 0.020), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (
        keyed(u, [(0.0, 0.0), (0.32, 0.0), (impact, 0.0), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.30, -0.05), (0.44, -0.06), (impact, 0.10),
                  (0.62, 0.08), (0.80, 0.02), (1.0, 0.0)]),
        keyed(u, [(0.0, -0.006), (0.30, 0.018), (0.44, 0.012), (impact, -0.155),
                  (0.62, -0.135), (0.80, -0.040), (1.0, -0.006)]),
    )
    values["pelvis_pitch"] = keyed(u, [(0.0, -0.010), (0.30, 0.050), (0.44, 0.070),
                                       (impact, -0.100), (0.62, -0.090), (0.80, -0.030),
                                       (1.0, -0.010)])
    values["pelvis_yaw"] = keyed(u, [(0.0, 0.0), (0.40, 0.055), (impact, -0.030),
                                     (0.72, 0.0), (1.0, 0.0)])
    values["pelvis_roll"] = keyed(u, [(0.0, 0.0), (0.40, 0.035), (impact, -0.035),
                                      (0.72, 0.0), (1.0, 0.0)])
    values["jaw_open"] = keyed(u, [(0.0, 0.030), (0.30, 0.110), (0.44, 0.230),
                                   (0.49, 0.400), (impact, 0.300), (0.70, 0.080),
                                   (1.0, 0.030)])
    head = keyed(u, [(0.0, -0.010), (0.30, 0.190), (0.44, 0.250), (0.50, 0.020),
                     (impact, -0.190), (0.62, -0.150), (0.80, 0.000), (1.0, -0.010)])
    wing = keyed(u, [(0.0, 0.0), (0.26, -0.220), (0.42, -0.340), (impact, 0.120),
                     (0.62, 0.060), (0.82, 0.0), (1.0, 0.0)])
    values["rot"] = {
        "spine_01": (torso, 0.0, 0.0),
        "spine_02": (torso * 1.15, 0.0, 0.0),
        "chest": (torso * 1.30, 0.0, 0.0),
        "neck_01": (neck, 0.0, 0.0),
        "neck_02": (neck * 1.15, 0.0, 0.0),
        "head": (head, 0.0, 0.0),
        "clavicle_l": (keyed(u, [(0.0, 0.0), (0.34, -0.16), (impact, 0.10), (1.0, 0.0)]),
                       0.0, -0.03),
        "clavicle_r": (keyed(u, [(0.0, 0.0), (0.34, -0.16), (impact, 0.10), (1.0, 0.0)]),
                       0.0, 0.03),
        "upper_arm_l": (arm, 0.0, -0.150),
        "upper_arm_r": (arm, 0.0, 0.150),
        "forearm_l": (forearm, 0.0, 0.0),
        "forearm_r": (forearm, 0.0, 0.0),
        "hand_l": (keyed(u, [(0.0, 0.03), (0.44, 0.18), (impact, -0.30), (1.0, 0.03)]), 0.0, 0.0),
        "hand_r": (keyed(u, [(0.0, 0.03), (0.44, 0.18), (impact, -0.30), (1.0, 0.03)]), 0.0, 0.0),
        "fingers_l": (keyed(u, [(0.0, 0.12), (0.44, 0.34), (impact, 0.05), (1.0, 0.12)]),
                      0.0, 0.0),
        "fingers_r": (keyed(u, [(0.0, 0.12), (0.44, 0.34), (impact, 0.05), (1.0, 0.12)]),
                      0.0, 0.0),
        "wing_root_l": (keyed(u, [(0.0, 0.0), (0.32, -0.12), (impact, 0.10), (1.0, 0.0)]),
                        0.0, wing),
        "wing_mid_l": (wing * 0.75, 0.0, wing * 0.55),
        "wing_tip_l": (wing * 0.45, 0.0, wing * 0.35),
        "wing_root_r": (keyed(u, [(0.0, 0.0), (0.32, -0.12), (impact, 0.10), (1.0, 0.0)]),
                        0.0, -wing),
        "wing_mid_r": (wing * 0.75, 0.0, -wing * 0.55),
        "wing_tip_r": (wing * 0.45, 0.0, -wing * 0.35),
        "tail_01": (keyed(u, [(0.0, -0.03), (0.32, 0.16), (impact, -0.14), (1.0, -0.03)]),
                    0.0, 0.0),
        "tail_02": (keyed(u, [(0.0, -0.02), (0.36, 0.12), (impact, -0.10), (1.0, -0.02)]),
                    0.0, 0.0),
        "tail_03": (keyed(u, [(0.0, -0.01), (0.40, 0.08), (impact, -0.06), (1.0, -0.01)]),
                    0.0, 0.0),
    }
    stance = keyed(u, [(0.0, 0.0), (0.30, -0.035), (0.44, -0.040), (impact, 0.045),
                       (0.62, 0.035), (0.80, 0.010), (1.0, 0.0)])
    values["legs"] = {
        "leg_l": _leg(y=stance, toe=0.0, foot=0.0),
        "leg_r": _leg(y=stance, toe=0.0, foot=0.0),
    }
    return values


def hit(t: float) -> dict:
    u = min(1.0, t / 0.50)
    recoil = keyed(u, [(0.0, 0.0), (0.20, 1.0), (0.52, 0.58), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (0.020 * recoil, -0.075 * recoil, -0.026 * recoil)
    values["pelvis_pitch"] = 0.100 * recoil
    values["pelvis_roll"] = 0.090 * recoil
    values["pelvis_yaw"] = -0.050 * recoil
    values["jaw_open"] = 0.20 * recoil + 0.030
    values["rot"] = {
        "spine_01": (0.140 * recoil, 0.0, 0.040 * recoil),
        "spine_02": (0.160 * recoil, 0.0, 0.050 * recoil),
        "chest": (0.190 * recoil, 0.0, 0.070 * recoil),
        "neck_01": (0.180 * recoil, 0.0, 0.070 * recoil),
        "neck_02": (0.180 * recoil, 0.0, 0.070 * recoil),
        "head": (0.320 * recoil, 0.140 * recoil, 0.150 * recoil),
        "upper_arm_l": (-0.280 * recoil, 0.0, -0.120 - 0.180 * recoil),
        "upper_arm_r": (-0.240 * recoil, 0.0, 0.120 + 0.140 * recoil),
        "forearm_l": (0.250 + 0.420 * recoil, 0.0, 0.0),
        "forearm_r": (0.250 + 0.380 * recoil, 0.0, 0.0),
        "hand_l": (0.030, 0.0, 0.0),
        "hand_r": (0.030, 0.0, 0.0),
        "fingers_l": (0.120 + 0.100 * recoil, 0.0, 0.0),
        "fingers_r": (0.120 + 0.100 * recoil, 0.0, 0.0),
        "wing_root_l": (0.060 * recoil, 0.0, -0.140 * recoil),
        "wing_mid_l": (0.040 * recoil, 0.0, 0.080 * recoil),
        "wing_tip_l": (0.020 * recoil, 0.0, 0.040 * recoil),
        "wing_root_r": (0.060 * recoil, 0.0, 0.140 * recoil),
        "wing_mid_r": (0.040 * recoil, 0.0, -0.080 * recoil),
        "wing_tip_r": (0.020 * recoil, 0.0, -0.040 * recoil),
        "tail_01": (-0.180 * recoil, 0.120 * recoil, 0.0),
        "tail_02": (-0.150 * recoil, 0.150 * recoil, 0.0),
        "tail_03": (-0.110 * recoil, 0.180 * recoil, 0.0),
    }
    values["legs"] = {
        "leg_l": _leg(y=0.055 * recoil, foot=0.05 * recoil),
        "leg_r": _leg(y=-0.055 * recoil, foot=0.05 * recoil),
    }
    return values


def death(t: float) -> dict:
    u = min(1.0, t / 1.40)
    collapse = keyed(u, [(0.0, 0.0), (0.10, 0.10), (0.34, 0.55), (0.58, 0.90),
                         (0.76, 1.0), (1.0, 1.0)])
    roll = keyed(u, [(0.0, 0.0), (0.22, 0.10), (0.48, 0.52), (0.70, 0.96),
                     (0.84, 1.04), (1.0, 1.04)])
    values = _base()
    values["pelvis_offset"] = (
        0.130 * roll,
        keyed(u, [(0.0, 0.0), (0.30, -0.040), (0.60, 0.060), (1.0, 0.080)]),
        -0.330 * collapse - 0.300 * roll - 0.006,
    )
    values["pelvis_pitch"] = -0.520 * collapse
    values["pelvis_roll"] = roll
    values["pelvis_yaw"] = 0.200 * collapse
    values["jaw_open"] = 0.100 + 0.140 * collapse
    values["rot"] = {
        "spine_01": (-0.160 * collapse, 0.080 * collapse, 0.100 * collapse),
        "spine_02": (-0.180 * collapse, 0.100 * collapse, 0.120 * collapse),
        "chest": (-0.140 * collapse, 0.080 * collapse, 0.100 * collapse),
        "neck_01": (0.200 * collapse, -0.120 * collapse, -0.160 * collapse),
        "neck_02": (0.220 * collapse, -0.150 * collapse, -0.180 * collapse),
        "head": (0.300 * collapse, -0.160 * collapse, -0.240 * collapse),
        "upper_arm_l": (1.500 * collapse, 0.0, -0.900 * collapse),
        "upper_arm_r": (1.900 * collapse, 0.0, 0.800 * collapse),
        "forearm_l": (0.250 + 0.600 * collapse, 0.0, 0.0),
        "forearm_r": (0.250 + 0.700 * collapse, 0.0, 0.0),
        "hand_l": (0.030, 0.0, 0.0),
        "hand_r": (0.030, 0.0, 0.0),
        "fingers_l": (0.120 + 0.120 * collapse, 0.0, 0.0),
        "fingers_r": (0.120 + 0.120 * collapse, 0.0, 0.0),
        "wing_root_l": (-0.080 * collapse, 0.0, -0.200 * collapse),
        "wing_mid_l": (0.050 * collapse, 0.0, 0.120 * collapse),
        "wing_tip_l": (0.040 * collapse, 0.0, 0.060 * collapse),
        "wing_root_r": (-0.080 * collapse, 0.0, 0.200 * collapse),
        "wing_mid_r": (0.050 * collapse, 0.0, -0.120 * collapse),
        "wing_tip_r": (0.040 * collapse, 0.0, -0.060 * collapse),
        "tail_01": (-0.120 * collapse, 0.180 * collapse, 0.0),
        "tail_02": (-0.100 * collapse, 0.200 * collapse, 0.0),
        "tail_03": (-0.080 * collapse, 0.220 * collapse, 0.0),
    }
    values["legs"] = {
        "leg_l": _leg(y=-0.060 * collapse, lift=0.020 * collapse),
        "leg_r": _leg(y=0.100 * collapse, lift=0.060 * collapse),
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
            toe = -0.22 * math.sin(math.pi * p)
            foot = 0.16 * math.sin(math.pi * p)
        values["legs"][chain_key] = {"y": y, "lift": lift, "toe": toe, "foot": foot}


CLIPS = {
    "idle": {"name": "Gargoyle_Idle_Loop", "duration": 3.0, "loop": True},
    "walk": {"name": "Gargoyle_Walk_Loop", "duration": 1.50, "loop": True,
             "stride": 1.70, "duty": 0.66, "fallback_speed": 1.133},
    "run": {"name": "Gargoyle_Run_Loop", "duration": 0.90, "loop": True,
            "stride": 2.90, "duty": 0.42, "fallback_speed": 3.222},
    "attack": {"name": "Gargoyle_Attack", "duration": 1.80, "loop": False,
               "impact": 0.95, "recovery_end": 1.80},
    "hit": {"name": "Gargoyle_Hit", "duration": 0.50, "loop": False},
    "death": {"name": "Gargoyle_Death", "duration": 1.40, "loop": False},
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
    "id": "gargoyle",
    "display_name": "Gargoyle",
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
    "paint_tags": ["body", "stone", "stone_dark", "lichen", "membrane",
                   "horn", "claw", "eye", "teeth", "mouth"],
    "eyes": EYES,
    "normal_strength": 1.25,
    "build_parts": build_parts,
    "clips": CLIPS,
    "poses": POSES,
    "head_zone": {"bone": "head", "radius": 0.30, "half_height": 0.14},
    "metadata_extra": {
        "role": "sentinel",
        "surface_notes": ["chipped slate plates", "lichen on upward faces",
                          "ember cracks", "keratin horns and claws",
                          "stone wing membrane", "ember eyes"],
    },
}
