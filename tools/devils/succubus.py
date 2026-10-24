"""Winged crimson temptress: plantigrade devil with bat wings, horns and a spade tail.

Silhouette: 1.88 m slender humanoid, swept-back horns and long black hair,
half-open bat wings spanning 1.9 m, leather harness and gold rings. The skin is
crimson with ember veins; the wings are veined membrane; the eyes burn amber.
"""

from __future__ import annotations

import math

import numpy as np

from devil_pipeline import (
    TAU,
    _mesh_object,
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
    smoothstep,
)

SCENE = "Succubus"
HEIGHT = 1.88

BONES = {
    "root": {"head": (0.0, 0.0, 0.0), "tail": (0.0, 0.0, 0.15), "deform": False},
    "pelvis": {"head": (0.0, 0.0, 0.98), "tail": (0.0, 0.02, 1.08), "parent": "root"},
    "spine_01": {"head": (0.0, 0.02, 1.08), "tail": (0.0, 0.03, 1.22), "parent": "pelvis", "connect": True},
    "spine_02": {"head": (0.0, 0.03, 1.22), "tail": (0.0, 0.04, 1.36), "parent": "spine_01", "connect": True},
    "chest": {"head": (0.0, 0.04, 1.36), "tail": (0.0, 0.03, 1.48), "parent": "spine_02", "connect": True},
    "neck_01": {"head": (0.0, 0.03, 1.48), "tail": (0.0, 0.05, 1.58), "parent": "chest", "connect": True},
    "neck_02": {"head": (0.0, 0.05, 1.58), "tail": (0.0, 0.07, 1.66), "parent": "neck_01", "connect": True},
    "head": {"head": (0.0, 0.07, 1.66), "tail": (0.0, 0.10, 1.82), "parent": "neck_02", "connect": True},
    "jaw": {"head": (0.0, 0.09, 1.72), "tail": (0.0, 0.19, 1.66), "parent": "head"},
    "tail_01": {"head": (0.0, -0.06, 0.98), "tail": (0.0, -0.22, 0.90), "parent": "pelvis"},
    "tail_02": {"head": (0.0, -0.22, 0.90), "tail": (0.0, -0.36, 0.82), "parent": "tail_01", "connect": True},
    "tail_03": {"head": (0.0, -0.36, 0.82), "tail": (0.0, -0.48, 0.88), "parent": "tail_02", "connect": True},
}

for side, sx in (("l", 1.0), ("r", -1.0)):
    BONES.update({
        "clavicle_" + side: {"head": (sx * 0.03, 0.03, 1.44), "tail": (sx * 0.17, 0.03, 1.45),
                             "parent": "chest"},
        "upper_arm_" + side: {"head": (sx * 0.17, 0.03, 1.45), "tail": (sx * 0.28, 0.05, 1.20),
                              "parent": "clavicle_" + side, "connect": True},
        "forearm_" + side: {"head": (sx * 0.28, 0.05, 1.20), "tail": (sx * 0.34, 0.08, 0.98),
                            "parent": "upper_arm_" + side, "connect": True},
        "hand_" + side: {"head": (sx * 0.34, 0.08, 0.98), "tail": (sx * 0.36, 0.12, 0.88),
                         "parent": "forearm_" + side, "connect": True},
        "fingers_" + side: {"head": (sx * 0.36, 0.12, 0.88), "tail": (sx * 0.36, 0.19, 0.84),
                            "parent": "hand_" + side, "connect": True},
        # Plantigrade leg: all five bones share one X so the sagittal solver
        # keeps the sole flat and the foot under the hip.
        "thigh_" + side: {"head": (sx * 0.115, 0.0, 0.99), "tail": (sx * 0.115, 0.04, 0.58),
                          "parent": "pelvis"},
        "shin_" + side: {"head": (sx * 0.115, 0.04, 0.58), "tail": (sx * 0.115, -0.02, 0.18),
                         "parent": "thigh_" + side, "connect": True},
        "tarsus_" + side: {"head": (sx * 0.115, -0.02, 0.18), "tail": (sx * 0.115, 0.04, 0.10),
                           "parent": "shin_" + side, "connect": True},
        "foot_" + side: {"head": (sx * 0.115, 0.04, 0.10), "tail": (sx * 0.115, 0.14, 0.055),
                         "parent": "tarsus_" + side, "connect": True},
        "toes_" + side: {"head": (sx * 0.115, 0.14, 0.055), "tail": (sx * 0.115, 0.24, 0.04),
                         "parent": "foot_" + side, "connect": True},
        # Wing arm: shoulder, wrist, finger tip. Half-open at rest.
        "wing_root_" + side: {"head": (sx * 0.05, 0.09, 1.42), "tail": (sx * 0.30, 0.20, 1.62),
                              "parent": "chest"},
        "wing_mid_" + side: {"head": (sx * 0.30, 0.20, 1.62), "tail": (sx * 0.62, 0.24, 1.70),
                             "parent": "wing_root_" + side, "connect": True},
        "wing_tip_" + side: {"head": (sx * 0.62, 0.24, 1.70), "tail": (sx * 0.95, 0.18, 1.52),
                             "parent": "wing_mid_" + side, "connect": True},
    })

CHAINS = {
    "leg_l": {"bones": ["thigh_l", "shin_l", "tarsus_l", "foot_l", "toes_l"], "pole": -1.0},
    "leg_r": {"bones": ["thigh_r", "shin_r", "tarsus_r", "foot_r", "toes_r"], "pole": -1.0},
}

SKIN_BONES = {
    "pelvis": (0.200, 0.90),
    "spine_01": (0.170, 0.90),
    "spine_02": (0.190, 0.90),
    "chest": (0.215, 0.95),
    "neck_01": (0.105, 1.00),
    "neck_02": (0.100, 1.00),
    "head": (0.155, 1.10),
    "jaw": (0.110, 1.10),
    "tail_01": (0.055, 1.00),
    "tail_02": (0.048, 1.00),
    "tail_03": (0.042, 1.00),
}
for side in ("l", "r"):
    SKIN_BONES.update({
        "clavicle_" + side: (0.100, 1.10),
        "upper_arm_" + side: (0.090, 1.50),
        "forearm_" + side: (0.072, 1.60),
        "hand_" + side: (0.065, 1.60),
        "fingers_" + side: (0.055, 1.60),
        "thigh_" + side: (0.125, 1.40),
        "shin_" + side: (0.090, 1.50),
        "tarsus_" + side: (0.070, 1.50),
        "foot_" + side: (0.085, 1.50),
        "toes_" + side: (0.080, 1.50),
        "wing_root_" + side: (0.240, 1.25),
        "wing_mid_" + side: (0.190, 1.30),
        "wing_tip_" + side: (0.150, 1.20),
    })

ROTATION_ORDER = [
    "spine_01", "spine_02", "chest", "neck_01", "neck_02", "head",
    "clavicle_l", "upper_arm_l", "forearm_l", "hand_l", "fingers_l",
    "clavicle_r", "upper_arm_r", "forearm_r", "hand_r", "fingers_r",
    "tail_01", "tail_02", "tail_03",
    "wing_root_l", "wing_mid_l", "wing_tip_l",
    "wing_root_r", "wing_mid_r", "wing_tip_r",
]
SWAY_BONES = ["spine_01", "spine_02", "chest", "neck_01", "neck_02", "head"]

PALETTE = {
    "body": {"kind": "skin", "base": "#a8323c", "second": "#5e1c24", "accent": "#d75a5a",
             "roughness": 0.50, "mottle_scale": 13.0, "pore_scale": 360.0,
             "wrinkle_scale": 58.0, "vein_scale": 30.0, "vein_mix": 0.18,
             "pore_height": 0.00018, "wrinkle_height": 0.00035, "seed": 47},
    "skin": {"kind": "skin", "base": "#a8323c", "second": "#5e1c24", "accent": "#d75a5a",
             "roughness": 0.50, "mottle_scale": 13.0, "pore_scale": 360.0,
             "wrinkle_scale": 58.0, "vein_scale": 30.0, "vein_mix": 0.18,
             "pore_height": 0.00018, "wrinkle_height": 0.00035, "seed": 47},
    "membrane": {"kind": "membrane", "base": "#6e2028", "second": "#3a1015", "accent": "#b05050",
                 "roughness": 0.46, "vein_scale": 22.0, "seed": 53},
    "hair": {"kind": "hair", "base": "#161016", "second": "#070508", "accent": "#5a4a52",
             "roughness": 0.95, "flow": (0.0, -0.22, -1.0), "frequency": 300.0,
             "clump_scale": 30.0, "height": 0.0018, "tip_mix": 0.50, "seed": 59},
    "horn": {"kind": "horn", "base": "#211a1f", "second": "#0d090b", "accent": "#6a5560",
             "roughness": 0.30, "axis": (0.0, -1.0, 0.5), "ring_frequency": 220.0,
             "ring_height": 0.00055, "crack_scale": 30.0, "crack_mix": 0.50, "seed": 61},
    "leather": {"kind": "leather", "base": "#1b1014", "second": "#0a0608", "accent": "#4a3038",
                "roughness": 0.62, "grain_scale": 60.0, "crease_scale": 26.0, "seed": 67},
    "metal": {"kind": "metal", "base": "#8a6a3a", "second": "#4a3820", "accent": "#d8b060",
              "roughness": 0.30, "metallic": 0.92, "scratch_scale": 90.0, "seed": 71},
    "eye": {"kind": "eye", "base": "#2a0808", "roughness": 0.06, "seed": 73},
    "teeth": {"kind": "teeth", "base": "#e0d0b0", "second": "#b8a482", "accent": "#6a5638",
              "roughness": 0.36, "seed": 79},
    "mouth": {"kind": "mouth", "base": "#2a0f10", "second": "#120607", "accent": "#5a2020",
              "roughness": 0.28, "seed": 83},
    "claw": {"kind": "claw", "base": "#211a1f", "second": "#0d090b", "accent": "#6a5560",
             "roughness": 0.28, "ring_frequency": 240.0, "crack_mix": 0.40, "seed": 89},
}

EYES = [{
    "center": (0.044, 0.166, 1.735),
    "forward": (0.16, 0.98, -0.04),
    "radius": 0.028,
    "iris": "#ffcf4a",
    "pupil_colour": "#050202",
    "sclera": "#2a0808",
    "pupil": 0.30,
    "iris_edge": 0.74,
    "emission": 1.5,
}, {
    "center": (-0.044, 0.166, 1.735),
    "forward": (-0.16, 0.98, -0.04),
    "radius": 0.028,
    "iris": "#ffcf4a",
    "pupil_colour": "#050202",
    "sclera": "#2a0808",
    "pupil": 0.30,
    "iris_edge": 0.74,
    "emission": 1.5,
}]


def classify(P: np.ndarray, N: np.ndarray) -> np.ndarray:
    """The metaball body is skin everywhere; the face and limbs carry more veins."""
    del N
    tags = np.full(len(P), "skin", dtype=object)
    return tags


# ---------------------------------------------------------------------------
# Sample helpers (same shape as the goat so the clump field behaves identically)


def _sample_ellipsoid(rng, centre, radii, count, length_range, thickness, bend, region=None):
    centre = np.array(centre, dtype=np.float64)
    radii = np.array(radii, dtype=np.float64)
    samples = []
    attempts = 0
    while len(samples) < count and attempts < count * 16:
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


def _sample_hair_curtain(rng, count):
    """Long strands hanging from the back of the skull down the spine."""
    samples = []
    for _ in range(count):
        u = rng.uniform(-1.0, 1.0)
        z = rng.uniform(1.615, 1.800)
        lateral = 0.082 * u * (0.85 + 0.15 * rng.random())
        y = -0.020 + 0.016 * abs(u) ** 2 - (1.80 - z) * 0.055
        outward = 0.14 * u
        normal = np.array((outward, -0.26, -0.96), dtype=np.float64)
        normal /= np.linalg.norm(normal)
        bend = np.array((0.04 * u, -0.12, -0.18), dtype=np.float64)
        samples.append({
            "point": (float(lateral), float(y), float(z)),
            "normal": tuple(normal),
            "length": float(rng.uniform(0.34, 0.48)),
            "radius": float(rng.uniform(0.006, 0.012)),
            "bend": tuple(bend * rng.uniform(0.7, 1.15)),
        })
    return samples


def _sample_hair_lock(rng, sx, count):
    """Temple locks framing the face and falling past the jaw."""
    samples = []
    for _ in range(count):
        z = rng.uniform(1.700, 1.795)
        y = rng.uniform(-0.010, 0.075)
        direction = np.array((sx * 0.30, -0.14, -1.0), dtype=np.float64)
        direction /= np.linalg.norm(direction)
        samples.append({
            "point": (sx * rng.uniform(0.060, 0.092), float(y), float(z)),
            "normal": tuple(direction),
            "length": float(rng.uniform(0.24, 0.40)),
            "radius": float(rng.uniform(0.005, 0.010)),
            "bend": (float(sx * 0.10), -0.05, -0.22),
        })
    return samples


# ---------------------------------------------------------------------------
# Geometry helpers


def _curve(points, u):
    """Evaluate a list of (u, xyz) controls at u in [0, 1]."""
    u = min(max(u, 0.0), 1.0)
    for index in range(len(points) - 1):
        u0, p0 = points[index]
        u1, p1 = points[index + 1]
        if u <= u1 or index == len(points) - 2:
            t = (u - u0) / max(u1 - u0, 1e-9)
            t = min(max(t, 0.0), 1.0)
            a = np.array(p0, dtype=np.float64)
            b = np.array(p1, dtype=np.float64)
            return a + (b - a) * t
    return np.array(points[-1][1], dtype=np.float64)


LEADING_EDGE = [
    (0.00, (0.050, 0.090, 1.420)),
    (0.33, (0.300, 0.200, 1.620)),
    (0.67, (0.620, 0.240, 1.700)),
    (1.00, (0.950, 0.180, 1.520)),
]

TRAILING_EDGE = [
    (0.00, (0.100, -0.055, 1.185)),
    (0.20, (0.200, -0.018, 1.130)),
    (0.36, (0.300, 0.048, 1.105)),
    (0.50, (0.400, 0.140, 1.175)),
    (0.62, (0.500, 0.185, 1.220)),
    (0.72, (0.560, 0.200, 1.255)),
    (0.84, (0.660, 0.205, 1.330)),
    (1.00, (0.950, 0.180, 1.520)),
]


def _wing_grid(sx, columns=17, rows=9):
    grid = []
    for row in range(rows):
        v = row / (rows - 1)
        points = []
        for column in range(columns):
            u = column / (columns - 1)
            lead = _curve(LEADING_EDGE, u)
            trail = _curve(TRAILING_EDGE, u)
            point = lead * (1.0 - v) + trail * v
            # The inner panel bows backward so it passes behind the resting
            # arm instead of cutting through it; the outer panel keeps a
            # shallow billow only.
            inner = 1.0 - smoothstep(0.02, 0.60, u)
            amplitude = (0.045 + 0.085 * inner) * 1.0
            billow = -amplitude * math.sin(math.pi * v) ** 0.9 * math.sin(math.pi * min(u, 0.995)) ** 0.35
            points.append((sx * float(point[0]), float(point[1] + billow), float(point[2])))
        grid.append(points)
    return grid


def _ring(name, centre, axis, radius, thickness, sides=6, segments=16):
    axis = np.array(axis, dtype=np.float64)
    axis /= np.linalg.norm(axis) + 1e-9
    helper = np.array((0.0, 0.0, 1.0)) if abs(axis[2]) < 0.9 else np.array((0.0, 1.0, 0.0))
    side = np.cross(axis, helper)
    side /= np.linalg.norm(side) + 1e-9
    up = np.cross(side, axis)
    centre = np.array(centre, dtype=np.float64)
    points = []
    for index in range(segments + 1):
        angle = TAU * index / segments
        offset = side * math.cos(angle) + up * math.sin(angle)
        points.append(tuple(centre + offset * radius))
    return make_tube(name, points, [thickness] * len(points), sides=sides, cap=False)


def _solid_sheet(name, grid, thickness):
    """Watertight thin shell from a rectangular point grid.

    ``make_membrane`` relies on ``bpy.ops.object.modifier_apply``, which acts on
    the active object, so the solidify pass is lost when several parts are built
    in one session. Building both layers plus the rim explicitly keeps the wing
    membrane, bodice and spade closed solids.
    """
    rows = len(grid)
    cols = len(grid[0])
    points = np.array(grid, dtype=np.float64)
    normals = np.zeros_like(points)
    for row in range(rows):
        for column in range(cols):
            across = points[row][min(column + 1, cols - 1)] - points[row][max(column - 1, 0)]
            down = points[min(row + 1, rows - 1)][column] - points[max(row - 1, 0)][column]
            normal = np.cross(across, down)
            length = np.linalg.norm(normal)
            normals[row][column] = normal / length if length > 1e-9 else (0.0, -1.0, 0.0)
    half = thickness * 0.5
    vertices = []
    for row in range(rows):
        for column in range(cols):
            point = points[row][column]
            vertices.append(tuple(point + normals[row][column] * half))
    for row in range(rows):
        for column in range(cols):
            point = points[row][column]
            vertices.append(tuple(point - normals[row][column] * half))
    total = rows * cols
    faces = []
    for row in range(rows - 1):
        for column in range(cols - 1):
            a = row * cols + column
            b = a + 1
            c = a + cols + 1
            d = a + cols
            faces.append((a, b, c, d))
            faces.append((total + d, total + c, total + b, total + a))
    for column in range(cols - 1):
        a = column
        b = column + 1
        faces.append((a, total + a, total + b, b))
        a = (rows - 1) * cols + column
        b = a + 1
        faces.append((total + a, a, b, total + b))
    for row in range(rows - 1):
        a = row * cols
        b = a + cols
        faces.append((total + a, a, b, total + b))
        a = row * cols + cols - 1
        b = a + cols
        faces.append((a, total + a, total + b, b))
    return _mesh_object(name, vertices, faces)


def _corset_grid():
    """Leather bodice: a wrapped elliptical band standing off the torso."""
    rows = [
        (1.085, 0.138, 0.108, 0.000),
        (1.150, 0.118, 0.094, 0.002),
        (1.215, 0.130, 0.098, 0.008),
        (1.280, 0.150, 0.104, 0.014),
        (1.325, 0.152, 0.100, 0.016),
    ]
    columns = 19
    grid = []
    for z, rx, ry, yc in rows:
        row = []
        for index in range(columns):
            angle = -2.86 + 5.72 * index / (columns - 1)
            row.append((math.sin(angle) * rx, yc + math.cos(angle) * ry, z))
        grid.append(row)
    return grid


def _spade_grid():
    rows = [(0.000, -0.445, 0.925, 0.006), (0.333, -0.520, 0.900, 0.046),
            (0.666, -0.585, 0.855, 0.032), (1.000, -0.640, 0.810, 0.004)]
    grid = []
    for _, y, z, width in rows:
        grid.append([(-width, y, z), (0.0, y - 0.012, z), (width, y, z)])
    return grid


def _body(mb):
    # Pelvis, hips, belly, waist.
    add_ellipsoid(mb, (0.0, -0.010, 0.995), (0.150, 0.104, 0.088))
    add_ellipsoid(mb, (0.072, -0.030, 0.985), (0.088, 0.092, 0.098))
    add_ellipsoid(mb, (-0.072, -0.030, 0.985), (0.088, 0.092, 0.098))
    add_ellipsoid(mb, (0.0, 0.000, 1.075), (0.126, 0.094, 0.078))
    add_ellipsoid(mb, (0.0, 0.004, 1.155), (0.103, 0.082, 0.075))
    # Ribcage, shoulders, bust.
    add_ellipsoid(mb, (0.0, 0.014, 1.245), (0.122, 0.090, 0.080))
    add_ellipsoid(mb, (0.0, 0.020, 1.330), (0.143, 0.096, 0.082))
    add_ellipsoid(mb, (0.0, 0.012, 1.415), (0.152, 0.086, 0.070))
    add_ellipsoid(mb, (0.060, 0.070, 1.372), (0.058, 0.058, 0.055))
    add_ellipsoid(mb, (-0.060, 0.070, 1.372), (0.058, 0.058, 0.055))
    add_ellipsoid(mb, (0.0, 0.020, 1.482), (0.108, 0.072, 0.048))
    # Neck.
    add_segment(mb, (0.0, 0.025, 1.475), (0.0, 0.062, 1.640), 0.043)
    # Skull, face, brow, cheekbones, pointed chin, nose.
    add_ellipsoid(mb, (0.0, 0.085, 1.745), (0.082, 0.090, 0.093))
    add_ellipsoid(mb, (0.0, 0.112, 1.700), (0.070, 0.075, 0.078))
    add_ellipsoid(mb, (0.0, 0.150, 1.760), (0.058, 0.030, 0.020))
    add_ellipsoid(mb, (0.058, 0.135, 1.700), (0.028, 0.032, 0.030))
    add_ellipsoid(mb, (-0.058, 0.135, 1.700), (0.028, 0.032, 0.030))
    add_ellipsoid(mb, (0.0, 0.148, 1.660), (0.036, 0.046, 0.032))
    add_ellipsoid(mb, (0.0, 0.176, 1.716), (0.017, 0.020, 0.030))
    for sx in (-1.0, 1.0):
        # Shoulder, arm, hand.
        add_ellipsoid(mb, (sx * 0.158, 0.018, 1.443), (0.064, 0.068, 0.064))
        add_segment(mb, (sx * 0.170, 0.030, 1.442), (sx * 0.278, 0.050, 1.205), 0.046)
        add_ellipsoid(mb, (sx * 0.278, 0.052, 1.200), (0.046, 0.048, 0.046))
        add_segment(mb, (sx * 0.278, 0.052, 1.198), (sx * 0.336, 0.080, 0.990), 0.038)
        add_ellipsoid(mb, (sx * 0.338, 0.082, 0.982), (0.031, 0.036, 0.030))
        add_segment(mb, (sx * 0.340, 0.086, 0.972), (sx * 0.354, 0.148, 0.890), 0.028, bulge=1.30)
        add_segment(mb, (sx * 0.354, 0.148, 0.888), (sx * 0.360, 0.192, 0.846), 0.019)
        # Thigh, knee, calf, ankle.
        add_segment(mb, (sx * 0.115, 0.000, 0.982), (sx * 0.115, 0.032, 0.790), 0.079)
        add_segment(mb, (sx * 0.115, 0.032, 0.792), (sx * 0.115, 0.042, 0.600), 0.060)
        add_ellipsoid(mb, (sx * 0.115, 0.038, 0.585), (0.054, 0.056, 0.055))
        add_segment(mb, (sx * 0.115, 0.034, 0.580), (sx * 0.115, -0.014, 0.290), 0.046)
        add_ellipsoid(mb, (sx * 0.115, 0.002, 0.468), (0.049, 0.056, 0.082))
        add_segment(mb, (sx * 0.115, -0.014, 0.292), (sx * 0.115, -0.018, 0.150), 0.030)
        add_ellipsoid(mb, (sx * 0.115, 0.006, 0.120), (0.032, 0.038, 0.048))
        # Plantigrade foot: heel, arch, toe mass; sole flat at z = 0.
        add_ellipsoid(mb, (sx * 0.115, 0.020, 0.048), (0.038, 0.052, 0.048))
        add_ellipsoid(mb, (sx * 0.115, 0.105, 0.044), (0.044, 0.100, 0.044))
        add_ellipsoid(mb, (sx * 0.115, 0.202, 0.030), (0.038, 0.055, 0.030))
    # Tail.
    add_segment(mb, (0.0, -0.080, 0.972), (0.0, -0.215, 0.905), 0.030)
    add_segment(mb, (0.0, -0.215, 0.905), (0.0, -0.355, 0.822), 0.021)
    add_segment(mb, (0.0, -0.355, 0.822), (0.0, -0.475, 0.872), 0.013)


def build_parts():
    rng = np.random.default_rng(20261025)
    parts = []

    body = build_metaball("SuccubusBody", 0.010, 0.6, _body,
                          decimate_ratio=0.40, smoothing=1)
    parts.append(part(body, "body"))

    for side, sx in (("l", 1.0), ("r", -1.0)):
        # Swept-back horn with raised growth rings.
        horn_points = [
            (sx * 0.052, 0.088, 1.806),
            (sx * 0.086, 0.040, 1.848),
            (sx * 0.106, -0.020, 1.856),
            (sx * 0.110, -0.082, 1.820),
            (sx * 0.098, -0.128, 1.772),
        ]
        horn_radii = [0.029, 0.023, 0.016, 0.009, 0.003]
        parts.append(part(make_tube("Horn_" + side, horn_points, horn_radii, sides=10),
                          "horn", rigid="head"))
        for index, u in enumerate((0.18, 0.40, 0.62)):
            point = _curve([(i / 4.0, p) for i, p in enumerate(horn_points)], u)
            near = _curve([(i / 4.0, p) for i, p in enumerate(horn_points)], u - 0.03)
            far = _curve([(i / 4.0, p) for i, p in enumerate(horn_points)], u + 0.03)
            axis = far - near
            axis /= np.linalg.norm(axis) + 1e-9
            base_radius = 0.029 * (1.0 - u) + 0.004 * u
            band = [tuple(point - axis * 0.008), tuple(point), tuple(point + axis * 0.008)]
            parts.append(part(make_tube(
                "HornRing_%s_%d" % (side, index), band,
                [base_radius * 1.10, base_radius * 1.18, base_radius * 1.10], sides=10),
                "horn", rigid="head"))
        # Pointed ear under the hair.
        parts.append(part(make_tube(
            "Ear_" + side,
            [(sx * 0.078, 0.070, 1.730), (sx * 0.096, 0.045, 1.762), (sx * 0.106, 0.020, 1.784)],
            [0.016, 0.011, 0.002], sides=7), "skin", rigid="head"))
        # Ember eye, matching the EYES entry exactly.
        eye = next(e for e in EYES if (e["center"][0] > 0.0) == (sx > 0.0))
        parts.append(part(make_uv_sphere(
            "Eye_" + side, eye["center"], eye["radius"], (1.0, 1.0, 0.94), 18, 13),
            "eye", rigid="head"))
        # Brow ridge above the socket.
        parts.append(part(make_tube(
            "Brow_" + side,
            [(sx * 0.016, 0.186, 1.776), (sx * 0.052, 0.188, 1.772), (sx * 0.080, 0.140, 1.762)],
            [0.009, 0.012, 0.007], sides=6), "skin", rigid="head"))
        # Fang.
        parts.append(part(make_cone(
            "Fang_" + side, (sx * 0.020, 0.186, 1.678), (sx * 0.021, 0.190, 1.655), 0.0075, 6),
            "teeth", rigid="head"))
        # Wing arm: three bone segments with tapered tubes.
        parts.append(part(make_tube(
            "WingArm_" + side,
            [(sx * 0.050, 0.090, 1.420), (sx * 0.175, 0.145, 1.520), (sx * 0.300, 0.200, 1.620)],
            [0.042, 0.030, 0.026], sides=8), "skin", rigid="wing_root_" + side))
        parts.append(part(make_tube(
            "WingFore_" + side,
            [(sx * 0.300, 0.200, 1.620), (sx * 0.460, 0.225, 1.665), (sx * 0.620, 0.240, 1.700)],
            [0.026, 0.021, 0.016], sides=8), "skin", rigid="wing_mid_" + side))
        parts.append(part(make_tube(
            "WingFinger_" + side,
            [(sx * 0.620, 0.240, 1.700), (sx * 0.790, 0.215, 1.615), (sx * 0.950, 0.180, 1.520)],
            [0.016, 0.010, 0.003], sides=8), "skin", rigid="wing_tip_" + side))
        parts.append(part(make_cone(
            "WingThumb_" + side, (sx * 0.600, 0.242, 1.692), (sx * 0.628, 0.232, 1.780),
            0.011, 6), "claw", rigid="wing_mid_" + side))
        # Wing membrane: leading edge down to the body anchor and trailing edge.
        parts.append(part(_solid_sheet("WingMembrane_" + side, _wing_grid(sx), 0.012),
                          "membrane"))
        # Hand claws.
        for index, offset in enumerate((-0.014, 0.0, 0.014)):
            parts.append(part(make_cone(
                "HandClaw_%s_%d" % (side, index),
                (sx * 0.360 + offset, 0.196, 0.852),
                (sx * 0.360 + offset * 1.4, 0.252, 0.800), 0.009, 6),
                "claw", rigid="fingers_" + side))
        # Toe claws.
        for index, offset in enumerate((-0.026, 0.0, 0.026)):
            parts.append(part(make_cone(
                "ToeClaw_%s_%d" % (side, index),
                (sx * 0.115 + offset, 0.250, 0.026),
                (sx * 0.115 + offset, 0.292, 0.006), 0.010, 6),
                "claw", rigid="toes_" + side))
        # Leather bracer and its gold band.
        parts.append(part(make_tube(
            "Bracer_" + side,
            [(sx * 0.300, 0.060, 1.130), (sx * 0.320, 0.072, 1.045), (sx * 0.338, 0.082, 0.992)],
            [0.050, 0.047, 0.044], sides=9), "leather", rigid="forearm_" + side))
        parts.append(part(_ring(
            "BracerBand_" + side, (sx * 0.316, 0.069, 1.070), (sx * 0.038, 0.022, -0.152),
            0.050, 0.006, sides=6), "metal", rigid="forearm_" + side))
        # Gold arm ring.
        parts.append(part(_ring(
            "ArmRing_" + side, (sx * 0.235, 0.042, 1.300), (sx * 0.110, 0.020, -0.250),
            0.056, 0.006, sides=6), "metal", rigid="upper_arm_" + side))
        # Ankle ring.
        parts.append(part(_ring(
            "AnkleRing_" + side, (sx * 0.115, 0.000, 0.150), (0.0, 0.0, 1.0),
            0.042, 0.006, sides=6), "metal", rigid="tarsus_" + side))
        # Shoulder harness strap.
        parts.append(part(make_tube(
            "Strap_" + side,
            [(sx * 0.070, 0.112, 1.330), (sx * 0.110, 0.085, 1.410),
             (sx * 0.148, 0.020, 1.462), (sx * 0.100, -0.040, 1.420),
             (sx * 0.058, -0.070, 1.360)],
            [0.020, 0.021, 0.021, 0.019, 0.017], sides=7), "leather", rigid="chest"))

    # Leather bodice.
    parts.append(part(_solid_sheet("Corset", _corset_grid(), 0.016), "leather"))
    parts.append(part(_ring("CorsetEdge", (0.0, 0.000, 1.085), (0.0, 0.0, 1.0), 0.138, 0.008,
                            sides=6, segments=20), "leather"))
    # Sternum ring and belt buckle in gold.
    parts.append(part(_ring("ChestRing", (0.0, 0.116, 1.300), (0.0, 1.0, 0.0), 0.028, 0.006,
                            sides=6), "metal", rigid="spine_02"))
    parts.append(part(make_box("Buckle", (0.0, 0.115, 1.090), (0.050, 0.014, 0.038), bevel=0.004),
                      "metal", rigid="pelvis"))
    # Choker.
    parts.append(part(_ring("Choker", (0.0, 0.050, 1.612), (0.0, 0.12, 1.0), 0.055, 0.011,
                            sides=7, segments=18), "leather", rigid="neck_02"))
    # Mouth and lower lip.
    parts.append(part(make_tube("MouthLine", [(-0.032, 0.190, 1.674), (0.0, 0.194, 1.676),
                                              (0.032, 0.190, 1.674)],
                                [0.004, 0.006, 0.004], sides=5), "mouth", rigid="head"))
    # Tail spade.
    parts.append(part(_solid_sheet("TailSpade", _spade_grid(), 0.016), "horn", rigid="tail_03"))

    # Hair: cap over the skull, long curtain down the back, temple locks.
    cap = _sample_ellipsoid(rng, (0.0, 0.050, 1.758), (0.100, 0.112, 0.098), 44,
                            (0.09, 0.17), (0.006, 0.011), (0.0, -0.16, -0.42),
                            region=lambda p: p[2] > 1.742 and not (p[1] > 0.135 and p[2] < 1.795))
    for sample in cap:
        normal = 0.55 * np.array(sample["normal"]) + np.array((0.0, -0.22, -0.88))
        sample["normal"] = tuple(normal / (np.linalg.norm(normal) + 1e-9))
    parts.append(part(make_clump_field("HairCap", cap, 5101), "hair", rigid="head"))
    curtain = _sample_hair_curtain(rng, 96)
    parts.append(part(make_clump_field("HairCurtain", curtain, 5107), "hair", rigid="head"))
    for side, sx in (("l", 1.0), ("r", -1.0)):
        locks = _sample_hair_lock(rng, sx, 9)
        parts.append(part(make_clump_field("HairLock_" + side, locks, 5113 + (0 if sx > 0 else 1)),
                          "hair", rigid="head"))

    return parts


# ---------------------------------------------------------------------------
# Clips


def _base():
    return {"rot": {}, "legs": {}}


def _wings(values, root_lift, root_sweep, mid_lift, mid_sweep, tip_lift, tip_sweep):
    values["rot"]["wing_root_l"] = (0.0, -root_sweep, -root_lift)
    values["rot"]["wing_root_r"] = (0.0, root_sweep, root_lift)
    values["rot"]["wing_mid_l"] = (0.0, -mid_sweep, -mid_lift)
    values["rot"]["wing_mid_r"] = (0.0, mid_sweep, mid_lift)
    values["rot"]["wing_tip_l"] = (0.0, -tip_sweep, -tip_lift)
    values["rot"]["wing_tip_r"] = (0.0, tip_sweep, tip_lift)


def idle(t: float) -> dict:
    phase = (t / 2.4) % 1.0
    breath = math.sin(TAU * phase)
    flap = math.sin(TAU * phase - 0.6)
    scan = math.sin(TAU * phase * 0.5)
    values = _base()
    values["pelvis_offset"] = (0.008 * math.sin(TAU * phase + 0.5), 0.0, 0.010 * breath)
    values["pelvis_roll"] = 0.018 * math.sin(TAU * phase)
    values["pelvis_yaw"] = 0.016 * scan
    values["pelvis_pitch"] = 0.012 * breath
    values["jaw_open"] = 0.025 + 0.010 * breath
    values["rot"] = {
        "spine_01": (0.020 * breath, -0.010 * scan, 0.008 * breath),
        "spine_02": (0.018 * breath, -0.014 * scan, 0.006 * breath),
        "chest": (-0.040 * breath, -0.020 * scan, 0.010 * breath),
        "neck_01": (0.016 * breath, 0.032 * scan, -0.008 * breath),
        "neck_02": (0.014 * breath, 0.040 * scan, 0.0),
        "head": (-0.010 * breath, 0.080 * scan, 0.020 * math.sin(TAU * phase * 0.7)),
        "clavicle_l": (0.0, 0.0, 0.0),
        "clavicle_r": (0.0, 0.0, 0.0),
        "upper_arm_l": (0.035 * breath, 0.0, 0.040),
        "upper_arm_r": (0.035 * breath, 0.0, -0.040),
        "forearm_l": (0.300 + 0.030 * breath, 0.0, 0.0),
        "forearm_r": (0.300 + 0.030 * breath, 0.0, 0.0),
        "hand_l": (0.060, 0.0, 0.0),
        "hand_r": (0.060, 0.0, 0.0),
        "fingers_l": (0.10 + 0.02 * breath, 0.0, 0.0),
        "fingers_r": (0.10 + 0.02 * breath, 0.0, 0.0),
        "tail_01": (0.070 * breath, 0.130 * math.sin(TAU * phase * 0.65), 0.0),
        "tail_02": (0.050 * breath, 0.170 * math.sin(TAU * phase * 0.65 + 0.5), 0.0),
        "tail_03": (0.030 * breath, 0.200 * math.sin(TAU * phase * 0.65 + 1.0), 0.0),
    }
    _wings(values,
           0.120 + 0.070 * flap, 0.180 + 0.050 * scan,
           0.050 + 0.050 * flap, 0.060 + 0.030 * scan,
           0.030 + 0.060 * flap, 0.040 + 0.020 * scan)
    values["legs"] = {
        "leg_l": {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0},
        "leg_r": {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0},
    }
    return values


def walk(t: float) -> dict:
    phase = (t / 1.15) % 1.0
    swing = math.cos(TAU * phase)
    values = _base()
    values["pelvis_offset"] = (0.016 * math.sin(TAU * phase), 0.0,
                               0.022 * abs(math.sin(TAU * phase * 2.0)) - 0.012)
    values["pelvis_yaw"] = 0.070 * math.sin(TAU * phase)
    values["pelvis_roll"] = 0.032 * swing
    values["pelvis_pitch"] = 0.020
    values["jaw_open"] = 0.020
    values["rot"] = {
        "spine_01": (0.030, -0.032 * math.sin(TAU * phase), 0.012 * swing),
        "spine_02": (0.025, -0.042 * math.sin(TAU * phase), 0.010 * swing),
        "chest": (0.010, -0.058 * math.sin(TAU * phase), 0.012 * swing),
        "neck_01": (-0.012, 0.042 * math.sin(TAU * phase), -0.010 * swing),
        "neck_02": (-0.010, 0.042 * math.sin(TAU * phase), -0.010 * swing),
        "head": (-0.020, 0.036 * math.sin(TAU * phase), 0.016 * swing),
        "upper_arm_l": (-0.30 * swing, 0.0, 0.045),
        "upper_arm_r": (0.30 * swing, 0.0, -0.045),
        "forearm_l": (0.34 + 0.10 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.34 + 0.10 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.05, 0.0, 0.0),
        "hand_r": (0.05, 0.0, 0.0),
        "fingers_l": (0.10, 0.0, 0.0),
        "fingers_r": (0.10, 0.0, 0.0),
        "tail_01": (0.05, 0.13 * math.sin(TAU * phase), 0.0),
        "tail_02": (0.04, 0.17 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (0.03, 0.21 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _wings(values,
           0.110 + 0.060 * math.sin(TAU * phase + 1.1), 0.180 + 0.060 * math.sin(TAU * phase),
           0.045 + 0.040 * math.sin(TAU * phase + 1.4), 0.055 + 0.030 * math.sin(TAU * phase),
           0.030 + 0.045 * math.sin(TAU * phase + 1.7), 0.035 + 0.020 * math.sin(TAU * phase))
    _gait(values, phase, 0.60, 1.30, 0.075, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def run(t: float) -> dict:
    phase = (t / 0.62) % 1.0
    swing = math.cos(TAU * phase)
    values = _base()
    values["pelvis_offset"] = (0.018 * math.sin(TAU * phase), 0.0,
                               0.045 * abs(math.sin(TAU * phase * 2.0)) - 0.022)
    values["pelvis_yaw"] = 0.090 * math.sin(TAU * phase)
    values["pelvis_roll"] = 0.045 * swing
    values["pelvis_pitch"] = 0.085
    values["jaw_open"] = 0.050
    values["rot"] = {
        "spine_01": (0.055, -0.050 * math.sin(TAU * phase), 0.018 * swing),
        "spine_02": (0.050, -0.070 * math.sin(TAU * phase), 0.015 * swing),
        "chest": (0.030, -0.090 * math.sin(TAU * phase), 0.020 * swing),
        "neck_01": (-0.045, 0.070 * math.sin(TAU * phase), -0.015 * swing),
        "neck_02": (-0.040, 0.060 * math.sin(TAU * phase), -0.015 * swing),
        "head": (-0.060, 0.050 * math.sin(TAU * phase), 0.020 * swing),
        "upper_arm_l": (-0.72 * swing, 0.0, 0.070),
        "upper_arm_r": (0.72 * swing, 0.0, -0.070),
        "forearm_l": (0.55 + 0.22 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.55 + 0.22 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.10, 0.0, 0.0),
        "hand_r": (0.10, 0.0, 0.0),
        "fingers_l": (0.16, 0.0, 0.0),
        "fingers_r": (0.16, 0.0, 0.0),
        "tail_01": (0.10, 0.12 * math.sin(TAU * phase), 0.0),
        "tail_02": (0.08, 0.16 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_03": (0.06, 0.20 * math.sin(TAU * phase + 0.8), 0.0),
    }
    _wings(values,
           0.180 + 0.220 * math.sin(TAU * phase + 0.9), 0.260 + 0.060 * math.sin(TAU * phase),
           0.090 + 0.140 * math.sin(TAU * phase + 1.2), 0.080 + 0.030 * math.sin(TAU * phase),
           0.060 + 0.120 * math.sin(TAU * phase + 1.5), 0.050 + 0.020 * math.sin(TAU * phase))
    _gait(values, phase, 0.36, 2.20, 0.150, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def attack(t: float) -> dict:
    u = min(1.0, t / 1.35)
    values = _base()
    values["pelvis_offset"] = (
        keyed(u, [(0.0, 0.0), (0.28, 0.055), (0.36, 0.050), (0.43, -0.070), (0.58, -0.095),
                  (0.78, -0.030), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.22, -0.090), (0.34, -0.130), (0.43, 0.185), (0.58, 0.250),
                  (0.78, 0.090), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.24, -0.060), (0.34, -0.095), (0.43, -0.030), (0.58, 0.010),
                  (1.0, 0.0)]),
    )
    values["pelvis_pitch"] = keyed(u, [(0.0, 0.0), (0.30, -0.100), (0.34, -0.120),
                                       (0.43, 0.120), (0.58, 0.180), (0.78, 0.060), (1.0, 0.0)])
    values["pelvis_yaw"] = keyed(u, [(0.0, 0.0), (0.30, 0.240), (0.34, 0.270),
                                     (0.43, -0.260), (0.58, -0.310), (0.80, -0.100), (1.0, 0.0)])
    values["pelvis_roll"] = keyed(u, [(0.0, 0.0), (0.30, 0.060), (0.43, -0.080),
                                      (0.58, -0.060), (1.0, 0.0)])
    values["jaw_open"] = keyed(u, [(0.0, 0.020), (0.30, 0.100), (0.43, 0.320),
                                   (0.58, 0.240), (0.80, 0.080), (1.0, 0.020)])
    values["rot"] = {
        "spine_01": (keyed(u, [(0.0, 0.0), (0.30, -0.060), (0.43, 0.120), (0.58, 0.160),
                               (1.0, 0.0)]),
                     keyed(u, [(0.0, 0.0), (0.30, 0.130), (0.43, -0.170), (0.58, -0.200),
                               (1.0, 0.0)]), 0.0),
        "spine_02": (keyed(u, [(0.0, 0.0), (0.30, -0.080), (0.43, 0.140), (0.58, 0.180),
                               (1.0, 0.0)]),
                     keyed(u, [(0.0, 0.0), (0.30, 0.160), (0.43, -0.200), (0.58, -0.240),
                               (1.0, 0.0)]), 0.0),
        "chest": (keyed(u, [(0.0, 0.0), (0.30, -0.100), (0.43, 0.160), (0.58, 0.210),
                            (0.80, 0.060), (1.0, 0.0)]),
                  keyed(u, [(0.0, 0.0), (0.30, 0.250), (0.43, -0.420), (0.58, -0.480),
                            (0.80, -0.150), (1.0, 0.0)]),
                  keyed(u, [(0.0, 0.0), (0.43, -0.060), (0.58, -0.080), (1.0, 0.0)])),
        "neck_01": (keyed(u, [(0.0, 0.0), (0.30, -0.060), (0.43, 0.080), (0.58, 0.100),
                              (1.0, 0.0)]),
                    keyed(u, [(0.0, 0.0), (0.30, 0.180), (0.43, -0.150), (0.58, -0.180),
                              (1.0, 0.0)]), 0.0),
        "neck_02": (keyed(u, [(0.0, 0.0), (0.30, -0.050), (0.43, 0.060), (0.58, 0.080),
                              (1.0, 0.0)]),
                    keyed(u, [(0.0, 0.0), (0.30, 0.150), (0.43, -0.130), (0.58, -0.150),
                              (1.0, 0.0)]), 0.0),
        "head": (keyed(u, [(0.0, 0.0), (0.30, -0.180), (0.36, -0.200), (0.43, 0.150),
                           (0.58, 0.180), (0.80, 0.050), (1.0, 0.0)]),
                 keyed(u, [(0.0, 0.0), (0.30, 0.260), (0.43, -0.240), (0.58, -0.280),
                           (0.80, -0.080), (1.0, 0.0)]),
                 keyed(u, [(0.0, 0.0), (0.43, 0.080), (0.58, 0.060), (1.0, 0.0)])),
        "upper_arm_r": (keyed(u, [(0.0, 0.0), (0.28, -0.350), (0.34, -0.420), (0.43, -0.200),
                                  (0.58, -0.050), (0.80, 0.050), (1.0, 0.0)]),
                        keyed(u, [(0.0, 0.0), (0.28, 0.550), (0.34, 0.650), (0.43, -0.700),
                                  (0.58, -0.950), (0.78, -0.400), (1.0, 0.0)]),
                        keyed(u, [(0.0, 0.0), (0.28, 0.900), (0.34, 1.000), (0.43, 0.600),
                                  (0.58, 0.350), (1.0, 0.0)])),
        "forearm_r": (keyed(u, [(0.0, 0.300), (0.28, 0.950), (0.34, 1.050), (0.43, 0.250),
                                (0.58, 0.350), (1.0, 0.300)]), 0.0, 0.0),
        "hand_r": (keyed(u, [(0.0, 0.050), (0.34, -0.350), (0.43, -0.550), (0.58, -0.200),
                             (1.0, 0.050)]), 0.0, 0.0),
        "fingers_r": (keyed(u, [(0.0, 0.100), (0.34, 0.550), (0.43, 0.850), (0.58, 0.500),
                                (1.0, 0.100)]), 0.0, 0.0),
        "upper_arm_l": (keyed(u, [(0.0, 0.0), (0.30, 0.300), (0.43, 0.350), (0.58, 0.250),
                                  (1.0, 0.0)]),
                        keyed(u, [(0.0, 0.0), (0.30, -0.350), (0.43, 0.250), (0.58, 0.350),
                                  (1.0, 0.0)]),
                        keyed(u, [(0.0, 0.0), (0.30, -0.200), (0.43, -0.350), (1.0, 0.0)])),
        "forearm_l": (keyed(u, [(0.0, 0.300), (0.30, 0.700), (0.43, 0.500), (0.58, 0.420),
                                (1.0, 0.300)]), 0.0, 0.0),
        "hand_l": (keyed(u, [(0.0, 0.050), (0.43, -0.200), (1.0, 0.050)]), 0.0, 0.0),
        "fingers_l": (keyed(u, [(0.0, 0.100), (0.43, 0.400), (1.0, 0.100)]), 0.0, 0.0),
        "tail_01": (0.050, keyed(u, [(0.0, 0.0), (0.28, -0.350), (0.43, 0.520), (0.58, 0.650),
                                     (0.78, 0.200), (1.0, 0.0)]), 0.0),
        "tail_02": (0.040, keyed(u, [(0.0, 0.0), (0.30, -0.300), (0.45, 0.480), (0.60, 0.600),
                                     (0.80, 0.180), (1.0, 0.0)]), 0.0),
        "tail_03": (0.030, keyed(u, [(0.0, 0.0), (0.32, -0.250), (0.47, 0.420), (0.62, 0.520),
                                     (0.82, 0.150), (1.0, 0.0)]), 0.0),
    }
    _wings(values,
           keyed(u, [(0.0, 0.120), (0.28, 0.340), (0.34, 0.400), (0.43, 0.620), (0.58, 0.560),
                     (0.80, 0.220), (1.0, 0.120)]),
           keyed(u, [(0.0, 0.180), (0.30, 0.460), (0.36, 0.420), (0.43, -0.060), (0.58, 0.040),
                     (1.0, 0.180)]),
           keyed(u, [(0.0, 0.050), (0.28, 0.220), (0.43, 0.380), (0.58, 0.330), (1.0, 0.050)]),
           keyed(u, [(0.0, 0.060), (0.30, 0.160), (0.43, 0.020), (0.58, 0.050), (1.0, 0.060)]),
           keyed(u, [(0.0, 0.030), (0.28, 0.180), (0.43, 0.300), (0.58, 0.260), (1.0, 0.030)]),
           keyed(u, [(0.0, 0.040), (0.30, 0.120), (0.43, 0.030), (0.58, 0.050), (1.0, 0.040)]))
    values["legs"] = {
        "leg_l": {"y": keyed(u, [(0.0, 0.0), (0.28, 0.090), (0.34, 0.105), (0.43, 0.155),
                                 (0.58, 0.140), (0.80, 0.060), (1.0, 0.0)]),
                  "lift": 0.0,
                  "toe": keyed(u, [(0.0, 0.0), (0.43, -0.050), (0.58, -0.020), (1.0, 0.0)]),
                  "foot": 0.0},
        "leg_r": {"y": keyed(u, [(0.0, 0.0), (0.28, -0.090), (0.34, -0.105), (0.43, -0.150),
                                 (0.58, -0.130), (0.80, -0.060), (1.0, 0.0)]),
                  "lift": 0.0,
                  "toe": 0.0,
                  "foot": 0.0},
    }
    return values


def hit(t: float) -> dict:
    u = min(1.0, t / 0.45)
    recoil = keyed(u, [(0.0, 0.0), (0.28, 1.0), (0.60, 0.50), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (0.020 * recoil, -0.075 * recoil, -0.022 * recoil)
    values["pelvis_pitch"] = -0.130 * recoil
    values["pelvis_roll"] = 0.090 * recoil
    values["pelvis_yaw"] = -0.060 * recoil
    values["jaw_open"] = 0.240 * recoil
    values["rot"] = {
        "spine_01": (-0.150 * recoil, 0.040 * recoil, 0.050 * recoil),
        "spine_02": (-0.170 * recoil, 0.050 * recoil, 0.060 * recoil),
        "chest": (-0.200 * recoil, 0.060 * recoil, 0.080 * recoil),
        "neck_01": (-0.190 * recoil, -0.060 * recoil, 0.060 * recoil),
        "neck_02": (-0.200 * recoil, -0.070 * recoil, 0.070 * recoil),
        "head": (-0.340 * recoil, -0.120 * recoil, 0.140 * recoil),
        "upper_arm_l": (-0.300 * recoil, 0.100 * recoil, 0.220 * recoil),
        "upper_arm_r": (-0.260 * recoil, -0.100 * recoil, -0.180 * recoil),
        "forearm_l": (0.300 + 0.520 * recoil, 0.0, 0.0),
        "forearm_r": (0.300 + 0.480 * recoil, 0.0, 0.0),
        "hand_l": (0.050, 0.0, 0.0),
        "hand_r": (0.050, 0.0, 0.0),
        "fingers_l": (0.100 + 0.250 * recoil, 0.0, 0.0),
        "fingers_r": (0.100 + 0.250 * recoil, 0.0, 0.0),
        "tail_01": (-0.180 * recoil, 0.150 * recoil, 0.0),
        "tail_02": (-0.150 * recoil, 0.180 * recoil, 0.0),
        "tail_03": (-0.120 * recoil, 0.210 * recoil, 0.0),
    }
    _wings(values,
           0.120 + 0.420 * recoil, 0.180 - 0.320 * recoil,
           0.050 + 0.220 * recoil, 0.060 - 0.040 * recoil,
           0.030 + 0.160 * recoil, 0.040 - 0.020 * recoil)
    values["legs"] = {
        "leg_l": {"y": 0.070 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.0},
        "leg_r": {"y": -0.055 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.0},
    }
    return values


def death(t: float) -> dict:
    u = min(1.0, t / 1.20)
    collapse = keyed(u, [(0.0, 0.0), (0.18, 0.10), (0.45, 0.48), (0.72, 0.88), (0.90, 1.0),
                         (1.0, 1.0)])
    fold = keyed(u, [(0.0, 0.0), (0.30, 0.30), (0.62, 0.75), (0.88, 1.0), (1.0, 1.0)])
    values = _base()
    values["pelvis_offset"] = (
        keyed(u, [(0.0, 0.0), (0.30, 0.020), (0.60, 0.090), (0.85, 0.140), (1.0, 0.145)]),
        keyed(u, [(0.0, 0.0), (0.18, -0.070), (0.45, -0.020), (0.75, 0.060), (1.0, 0.080)]),
        -0.575 * collapse,
    )
    values["pelvis_pitch"] = 0.360 * collapse
    values["pelvis_roll"] = 0.200 * collapse
    values["pelvis_yaw"] = 0.300 * collapse
    values["jaw_open"] = 0.160 + 0.120 * collapse
    values["rot"] = {
        "spine_01": (0.140 * collapse, -0.100 * collapse, 0.340 * collapse),
        "spine_02": (0.160 * collapse, -0.120 * collapse, 0.360 * collapse),
        "chest": (0.140 * collapse, -0.100 * collapse, 0.360 * collapse),
        "neck_01": (-0.120 * collapse, 0.100 * collapse, 0.140 * collapse),
        "neck_02": (-0.140 * collapse, 0.120 * collapse, 0.160 * collapse),
        "head": (-0.240 * collapse, 0.200 * collapse, 0.350 * collapse),
        "upper_arm_l": (-0.400 * collapse, 0.200 * collapse, 0.380 * collapse),
        "upper_arm_r": (-0.300 * collapse, -0.150 * collapse, -0.420 * collapse),
        "forearm_l": (0.300 + 0.420 * collapse, 0.0, 0.0),
        "forearm_r": (0.300 + 0.300 * collapse, 0.0, 0.0),
        "hand_l": (0.050, 0.0, 0.0),
        "hand_r": (0.050, 0.0, 0.0),
        "fingers_l": (0.100 + 0.300 * collapse, 0.0, 0.0),
        "fingers_r": (0.100 + 0.260 * collapse, 0.0, 0.0),
        "tail_01": (-0.800 * collapse, 0.350 * collapse, 0.0),
        "tail_02": (-0.550 * collapse, 0.300 * collapse, 0.0),
        "tail_03": (-0.400 * collapse, 0.250 * collapse, 0.0),
    }
    _wings(values,
           0.120 + 0.120 * fold, 0.180 + 1.100 * fold,
           0.050 + 0.180 * fold, 0.060 + 0.900 * fold,
           0.030 + 0.200 * fold, 0.040 + 0.700 * fold)
    values["legs"] = {
        "leg_l": {"y": keyed(u, [(0.0, 0.0), (0.40, 0.080), (0.80, 0.150), (1.0, 0.160)]),
                  "lift": 0.0,
                  "toe": 0.180 * collapse,
                  "foot": 0.0},
        "leg_r": {"y": keyed(u, [(0.0, 0.0), (0.40, -0.070), (0.80, -0.120), (1.0, -0.130)]),
                  "lift": 0.0,
                  "toe": -0.120 * collapse,
                  "foot": 0.0},
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
            toe = -0.30 * math.sin(math.pi * p)
            foot = 0.16 * math.sin(math.pi * p)
        values["legs"][chain_key] = {"y": y, "lift": lift, "toe": toe, "foot": foot}


CLIPS = {
    "idle": {"name": "Succubus_Idle_Loop", "duration": 2.4, "loop": True},
    "walk": {"name": "Succubus_Walk_Loop", "duration": 1.15, "loop": True,
             "stride": 1.30, "duty": 0.60, "fallback_speed": 1.13},
    "run": {"name": "Succubus_Run_Loop", "duration": 0.62, "loop": True,
            "stride": 2.20, "duty": 0.36, "fallback_speed": 3.55},
    "attack": {"name": "Succubus_Attack", "duration": 1.35, "loop": False,
               "impact": 0.58, "recovery_end": 1.35},
    "hit": {"name": "Succubus_Hit", "duration": 0.45, "loop": False},
    "death": {"name": "Succubus_Death", "duration": 1.20, "loop": False},
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
    "id": "succubus",
    "display_name": "Succubus",
    "scene": SCENE,
    "height": HEIGHT,
    "texture_size": 1024,
    "bones": BONES,
    "chains": CHAINS,
    "skin_bones": SKIN_BONES,
    "rotation_order": ROTATION_ORDER,
    "sway_bones": SWAY_BONES,
    "palette": PALETTE,
    "classify": classify,
    "paint_tags": ["body", "skin", "membrane", "hair", "horn", "leather", "metal",
                   "eye", "teeth", "mouth", "claw"],
    "eyes": EYES,
    "normal_strength": 1.10,
    "build_parts": build_parts,
    "clips": CLIPS,
    "poses": POSES,
    "head_zone": {"bone": "head", "radius": 0.26, "half_height": 0.13},
    "metadata_extra": {
        "role": "skirmisher",
        "surface_notes": ["crimson demon skin with ember veins", "bat wing membrane",
                          "black swept-back horns with ring ridges", "leather bodice and bracers",
                          "gold rings", "ember eyes", "spade tail"],
    },
}
