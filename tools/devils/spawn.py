"""Devil spawn: a small hunched grotesque with a bare ribcage and ember eyes.

Silhouette: 1.15 m, knuckle-dragging arms with oversized hands, spindly
digitigrade legs, elongated noseless skull with needle teeth, a crest of back
spikes and sparse bristles. Near-black blue-grey hide exposes a tan ribcage;
the only saturated accents are the ember eyes and hairline skin cracks.
"""

from __future__ import annotations

import math

import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from devil_pipeline import (
    TAU,
    add_ellipsoid,
    add_segment,
    build_metaball,
    fbm,
    keyed,
    make_clump_field,
    make_cone,
    make_tube,
    make_uv_sphere,
    part,
)

SCENE = "Spawn"
HEIGHT = 1.15

BONES = {
    "root": {"head": (0.0, 0.0, 0.0), "tail": (0.0, 0.0, 0.12), "deform": False},
    "pelvis": {"head": (0.0, 0.0, 0.58), "tail": (0.0, 0.08, 0.68), "parent": "root"},
    "spine_01": {"head": (0.0, 0.08, 0.68), "tail": (0.0, 0.16, 0.78),
                 "parent": "pelvis", "connect": True},
    "spine_02": {"head": (0.0, 0.16, 0.78), "tail": (0.0, 0.24, 0.88),
                 "parent": "spine_01", "connect": True},
    "chest": {"head": (0.0, 0.24, 0.88), "tail": (0.0, 0.30, 0.97),
              "parent": "spine_02", "connect": True},
    "neck_01": {"head": (0.0, 0.30, 0.97), "tail": (0.0, 0.36, 1.02),
                "parent": "chest", "connect": True},
    "neck_02": {"head": (0.0, 0.36, 1.02), "tail": (0.0, 0.40, 1.06),
                "parent": "neck_01", "connect": True},
    "head": {"head": (0.0, 0.40, 1.06), "tail": (0.0, 0.52, 1.02),
             "parent": "neck_02", "connect": True},
    "jaw": {"head": (0.0, 0.48, 1.00), "tail": (0.0, 0.62, 0.95), "parent": "head"},
    "tail_01": {"head": (0.0, -0.04, 0.58), "tail": (0.0, -0.18, 0.50), "parent": "pelvis"},
    "tail_02": {"head": (0.0, -0.18, 0.50), "tail": (0.0, -0.30, 0.44),
                "parent": "tail_01", "connect": True},
}

for side, sx in (("l", 1.0), ("r", -1.0)):
    BONES.update({
        f"clavicle_{side}": {"head": (sx * 0.03, 0.26, 0.94), "tail": (sx * 0.15, 0.27, 0.96),
                             "parent": "chest"},
        f"upper_arm_{side}": {"head": (sx * 0.15, 0.27, 0.96), "tail": (sx * 0.24, 0.34, 0.70),
                              "parent": f"clavicle_{side}", "connect": True},
        f"forearm_{side}": {"head": (sx * 0.24, 0.34, 0.70), "tail": (sx * 0.30, 0.40, 0.45),
                            "parent": f"upper_arm_{side}", "connect": True},
        f"hand_{side}": {"head": (sx * 0.30, 0.40, 0.45), "tail": (sx * 0.32, 0.46, 0.34),
                         "parent": f"forearm_{side}", "connect": True},
        f"fingers_{side}": {"head": (sx * 0.32, 0.46, 0.34), "tail": (sx * 0.32, 0.55, 0.29),
                            "parent": f"hand_{side}", "connect": True},
        f"thigh_{side}": {"head": (sx * 0.13, 0.02, 0.59), "tail": (sx * 0.13, 0.10, 0.40),
                          "parent": "pelvis"},
        f"shin_{side}": {"head": (sx * 0.13, 0.10, 0.40), "tail": (sx * 0.13, 0.00, 0.22),
                         "parent": f"thigh_{side}", "connect": True},
        f"tarsus_{side}": {"head": (sx * 0.13, 0.00, 0.22), "tail": (sx * 0.13, 0.06, 0.12),
                           "parent": f"shin_{side}", "connect": True},
        f"foot_{side}": {"head": (sx * 0.13, 0.06, 0.12), "tail": (sx * 0.13, 0.16, 0.055),
                         "parent": f"tarsus_{side}", "connect": True},
        f"toes_{side}": {"head": (sx * 0.13, 0.16, 0.055), "tail": (sx * 0.13, 0.26, 0.04),
                         "parent": f"foot_{side}", "connect": True},
        f"ear_{side}": {"head": (sx * 0.055, 0.405, 1.09), "tail": (sx * 0.14, 0.355, 1.105),
                        "parent": "head"},
    })

CHAINS = {
    "leg_l": {"bones": ["thigh_l", "shin_l", "tarsus_l", "foot_l", "toes_l"], "pole": -1.0},
    "leg_r": {"bones": ["thigh_r", "shin_r", "tarsus_r", "foot_r", "toes_r"], "pole": -1.0},
}

SKIN_BONES = {
    "pelvis": (0.145, 0.9),
    "spine_01": (0.135, 0.9),
    "spine_02": (0.13, 0.95),
    "chest": (0.16, 1.0),
    "neck_01": (0.075, 1.0),
    "neck_02": (0.065, 1.0),
    "head": (0.125, 1.15),
    "jaw": (0.07, 1.1),
    "tail_01": (0.045, 1.0),
    "tail_02": (0.035, 1.0),
}
for side in ("l", "r"):
    SKIN_BONES.update({
        f"clavicle_{side}": (0.085, 1.1),
        f"upper_arm_{side}": (0.075, 1.6),
        f"forearm_{side}": (0.058, 1.7),
        f"hand_{side}": (0.06, 1.7),
        f"fingers_{side}": (0.05, 1.7),
        f"thigh_{side}": (0.08, 1.4),
        f"shin_{side}": (0.052, 1.5),
        f"tarsus_{side}": (0.038, 1.5),
        f"foot_{side}": (0.05, 1.5),
        f"toes_{side}": (0.045, 1.5),
        f"ear_{side}": (0.03, 1.2),
    })

ROTATION_ORDER = [
    "spine_01", "spine_02", "chest", "neck_01", "neck_02", "head",
    "clavicle_l", "upper_arm_l", "forearm_l", "hand_l", "fingers_l",
    "clavicle_r", "upper_arm_r", "forearm_r", "hand_r", "fingers_r",
    "tail_01", "tail_02", "ear_l", "ear_r",
]
SWAY_BONES = ["spine_01", "spine_02", "chest", "neck_01", "neck_02", "head"]

PALETTE = {
    "body": {"kind": "skin", "base": "#1a1c22", "second": "#090a0e", "accent": "#3a3f48",
             "roughness": 0.62, "mottle_scale": 11.0, "pore_scale": 360.0,
             "wrinkle_scale": 58.0, "vein_scale": 30.0, "vein_mix": 0.20,
             "pore_height": 0.00018, "wrinkle_height": 0.00040, "glow": 0.35, "seed": 91},
    "skin": {"kind": "skin", "base": "#1a1c22", "second": "#090a0e", "accent": "#3a3f48",
             "roughness": 0.62, "mottle_scale": 11.0, "pore_scale": 360.0,
             "wrinkle_scale": 58.0, "vein_scale": 30.0, "vein_mix": 0.20,
             "pore_height": 0.00018, "wrinkle_height": 0.00040, "glow": 0.35, "seed": 97},
    "bone": {"kind": "bone", "base": "#a2804c", "second": "#5b4c37", "accent": "#d8b98a",
             "roughness": 0.50, "ring_frequency": 210.0, "ring_height": 0.00045,
             "axis": (0.0, 0.2, 1.0), "crack_scale": 42.0, "crack_mix": 0.35,
             "striation_scale": 380.0, "seed": 101},
    "mouth": {"kind": "mouth", "base": "#240708", "second": "#0c0203", "accent": "#5a1818",
              "roughness": 0.30, "seed": 103},
    "teeth": {"kind": "teeth", "base": "#e0d0b0", "second": "#b09b74", "accent": "#6a5638",
              "roughness": 0.34, "seed": 107},
    "claw": {"kind": "claw", "base": "#201d1a", "second": "#0a0807", "accent": "#5a5048",
             "roughness": 0.30, "ring_frequency": 260.0, "crack_scale": 46.0,
             "crack_mix": 0.42, "striation_scale": 400.0, "seed": 109},
    "hair": {"kind": "hair", "base": "#14161a", "second": "#060708", "accent": "#4a5058",
             "roughness": 0.92, "flow": (0.0, -0.45, -0.85), "frequency": 300.0,
             "clump_scale": 32.0, "height": 0.0016, "tip_mix": 0.46, "seed": 113},
    "eye": {"kind": "eye", "base": "#1a0804", "roughness": 0.06, "seed": 127},
    "ember": {"kind": "ember", "base": "#1c0c08", "second": "#070302", "accent": "#ff5a1a",
              "roughness": 0.46, "seed": 131},
}

EYES = [{
    "center": (0.05, 0.478, 1.058),
    "forward": (0.28, 1.0, -0.10),
    "radius": 0.022,
    "iris": "#ff5a1a",
    "pupil_colour": "#050202",
    "sclera": "#1a0804",
    "pupil": 0.34,
    "iris_edge": 0.72,
    "emission": 1.7,
}, {
    "center": (-0.05, 0.478, 1.058),
    "forward": (-0.28, 1.0, -0.10),
    "radius": 0.022,
    "iris": "#ff5a1a",
    "pupil_colour": "#050202",
    "sclera": "#1a0804",
    "pupil": 0.34,
    "iris_edge": 0.72,
    "emission": 1.7,
}]


def classify(P: np.ndarray, N: np.ndarray) -> np.ndarray:
    """Bared ribcage texels read as bone; everything else is near-black hide."""
    x = np.abs(P[:, 0])
    bare = ((P[:, 2] > 0.745) & (P[:, 2] < 0.898) & (P[:, 1] > 0.165) & (x < 0.16))
    ragged = fbm(P, 26.0, 17) > 0.44
    return np.where(bare & ragged, "bone", "skin")


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
        point = centre + radial * radius * rng.uniform(0.5, 1.0)
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
    rng = np.random.default_rng(20261031)
    parts = []

    def body_builder(mb):
        # Torso: narrow waist, exposed rib barrel, hunched shoulder girdle.
        add_ellipsoid(mb, (0.0, 0.02, 0.61), (0.115, 0.100, 0.100))
        add_ellipsoid(mb, (0.0, 0.07, 0.70), (0.100, 0.085, 0.095))
        add_ellipsoid(mb, (0.0, 0.135, 0.775), (0.095, 0.080, 0.090))
        add_ellipsoid(mb, (0.0, 0.215, 0.855), (0.125, 0.095, 0.095))
        add_ellipsoid(mb, (0.0, 0.260, 0.930), (0.160, 0.090, 0.070))
        add_ellipsoid(mb, (0.0, 0.320, 0.985), (0.070, 0.075, 0.060))
        add_ellipsoid(mb, (0.0, 0.365, 1.035), (0.055, 0.060, 0.050))
        # Elongated, nose-less skull.
        add_ellipsoid(mb, (0.0, 0.420, 1.065), (0.075, 0.082, 0.078))
        add_ellipsoid(mb, (0.0, 0.468, 1.092), (0.060, 0.035, 0.022))
        add_ellipsoid(mb, (0.0, 0.505, 1.035), (0.048, 0.060, 0.038))
        add_ellipsoid(mb, (0.0, 0.565, 1.018), (0.032, 0.042, 0.028))
        add_ellipsoid(mb, (0.0, 0.505, 0.985), (0.045, 0.065, 0.030))
        add_ellipsoid(mb, (0.0, 0.570, 0.972), (0.028, 0.035, 0.020))
        for sx in (-1.0, 1.0):
            add_ellipsoid(mb, (sx * 0.055, 0.460, 1.015), (0.025, 0.040, 0.035))
            # Neck/back spikes root, shoulder, long arm, oversized hand.
            add_ellipsoid(mb, (sx * 0.150, 0.270, 0.945), (0.055, 0.055, 0.060))
            add_segment(mb, (sx * 0.150, 0.270, 0.945), (sx * 0.240, 0.340, 0.700), 0.040)
            add_ellipsoid(mb, (sx * 0.240, 0.340, 0.700), (0.042, 0.042, 0.040))
            add_segment(mb, (sx * 0.240, 0.340, 0.700), (sx * 0.300, 0.400, 0.450), 0.032)
            add_ellipsoid(mb, (sx * 0.300, 0.400, 0.450), (0.032, 0.034, 0.032))
            add_ellipsoid(mb, (sx * 0.315, 0.440, 0.375), (0.038, 0.050, 0.045))
            add_ellipsoid(mb, (sx * 0.320, 0.520, 0.300), (0.030, 0.045, 0.025))
            # Spindly digitigrade leg: hip, knee, hock, ankle, splayed foot.
            add_ellipsoid(mb, (sx * 0.130, 0.020, 0.590), (0.055, 0.060, 0.065))
            add_segment(mb, (sx * 0.130, 0.020, 0.585), (sx * 0.130, 0.100, 0.400), 0.042)
            add_ellipsoid(mb, (sx * 0.130, 0.100, 0.400), (0.043, 0.043, 0.043))
            add_segment(mb, (sx * 0.130, 0.100, 0.400), (sx * 0.130, 0.000, 0.220), 0.030)
            add_ellipsoid(mb, (sx * 0.130, 0.000, 0.220), (0.030, 0.032, 0.030))
            add_segment(mb, (sx * 0.130, 0.000, 0.220), (sx * 0.130, 0.060, 0.120), 0.024)
            add_ellipsoid(mb, (sx * 0.130, 0.060, 0.120), (0.026, 0.028, 0.026))
            add_segment(mb, (sx * 0.130, 0.060, 0.120), (sx * 0.130, 0.160, 0.055), 0.029)
            add_ellipsoid(mb, (sx * 0.130, 0.205, 0.048), (0.038, 0.055, 0.026))
        # Short thrashing tail.
        add_segment(mb, (0.0, -0.040, 0.580), (0.0, -0.180, 0.500), 0.028)
        add_segment(mb, (0.0, -0.180, 0.500), (0.0, -0.300, 0.440), 0.018)
        add_ellipsoid(mb, (0.0, -0.305, 0.438), (0.014, 0.016, 0.014))

    body = build_metaball("SpawnBody", 0.0105, 0.6, body_builder,
                          decimate_ratio=0.46, smoothing=1)
    parts.append(part(body, "body"))

    # Details are seated on the actual metaball surface: authored rest points
    # are re-projected so ribs, teeth and cracks never disappear inside it.
    body_tree = BVHTree.FromPolygons(
        [vertex.co.copy() for vertex in body.data.vertices],
        [tuple(polygon.vertices) for polygon in body.data.polygons])

    def project(point, offset):
        hit, normal, _, _ = body_tree.find_nearest(Vector(point))
        if hit is None:
            return Vector(point)
        return hit + normal.normalized() * offset

    def cast(origin, point, offset):
        origin = Vector(origin)
        direction = Vector(point) - origin
        if direction.length < 1e-9:
            return origin
        hit, normal, _, _ = body_tree.ray_cast(origin, direction.normalized(), 2.0)
        if hit is None:
            return Vector(point)
        return hit + normal.normalized() * offset

    def seat(point, offset):
        hit, normal, _, _ = body_tree.find_nearest(Vector(point))
        if hit is None:
            return Vector(point), Vector((0.0, 0.0, 1.0))
        direction = normal.normalized()
        return hit + direction * offset, direction

    # Exposed ribcage: five pairs of curved bone tubes over the rib barrel.
    rows = (0.905, 0.874, 0.843, 0.812, 0.781)
    angles = (2.45, 2.00, 1.55, 1.10, 0.65, 0.25)
    for index, z_row in enumerate(rows):
        factor = 1.0 - 0.024 * index
        y_centre = 0.222 - 0.008 * index
        for sx in (-1.0, 1.0):
            points = []
            radii = []
            for step, angle in enumerate(angles):
                x = sx * 0.130 * factor * math.sin(angle)
                y = y_centre + 0.088 * factor * math.cos(angle)
                z = z_row - 0.0055 * step
                points.append(tuple(cast((0.0, 0.21, z), (x, y, z), 0.0045)))
                radii.append(0.0092 - 0.0009 * step)
            parts.append(part(make_tube(f"Rib_{index}_{int(sx)}", points, radii, sides=8),
                              "bone"))
    parts.append(part(make_tube(
        "Sternum",
        [tuple(project(point, 0.0055)) for point in
         [(0.0, 0.302, 0.905), (0.0, 0.312, 0.860), (0.0, 0.314, 0.810),
          (0.0, 0.303, 0.770)]],
        [0.009, 0.0105, 0.008, 0.004], sides=7), "bone"))

    # Back spikes: keratin blades along the spine, rigid to spine_02 and chest.
    spikes = (
        ((0.0, -0.068, 0.665), 0.070, 0.016, "spine_02"),
        ((0.0, -0.005, 0.735), 0.066, 0.015, "spine_02"),
        ((0.0, 0.060, 0.800), 0.074, 0.017, "spine_02"),
        ((0.0, 0.125, 0.865), 0.080, 0.018, "chest"),
        ((0.0, 0.185, 0.945), 0.072, 0.016, "chest"),
        ((0.0, 0.225, 0.995), 0.058, 0.013, "chest"),
        ((0.0, 0.270, 1.030), 0.046, 0.011, "chest"),
    )
    for index, (base, length, radius, bone) in enumerate(spikes):
        base_v = np.array(base, dtype=np.float64)
        tip = (base_v[0], base_v[1] - 0.045, base_v[2] + 0.92 * length)
        parts.append(part(make_cone(f"Spike_{index}", tuple(base_v), tuple(tip),
                                    radius, 7), "claw", rigid=bone))

    # Head furniture: ember eyes, orbital rims, brow, ears, snout ridge.
    for side, sx in (("l", 1.0), ("r", -1.0)):
        parts.append(part(make_uv_sphere(f"Eye_{side}", (sx * 0.05, 0.478, 1.058),
                                         0.022, (1.0, 1.0, 1.0), 16, 12),
                          "eye", rigid="head"))
        # Bony socket ring seals the eye against the skull.
        rim = []
        for step in range(9):
            angle = TAU * step / 8.0
            rim.append(tuple(project((sx * 0.05 + 0.030 * math.cos(angle), 0.470,
                                      1.058 + 0.028 * math.sin(angle)), 0.0015)))
        parts.append(part(make_tube(f"EyeRim_{side}", rim, [0.0048] * 9, sides=5,
                                    cap=False), "bone", rigid="head"))
        parts.append(part(make_tube(
            f"Brow_{side}",
            [tuple(project(point, 0.002)) for point in
             [(sx * 0.018, 0.474, 1.104), (sx * 0.070, 0.466, 1.096)]],
            [0.014, 0.008], sides=6), "bone", rigid="head"))
        # Ragged ear: main vane plus a torn barb.
        parts.append(part(make_tube(
            f"Ear_{side}",
            [(sx * 0.065, 0.404, 1.092), (sx * 0.115, 0.380, 1.110),
             (sx * 0.168, 0.345, 1.098)],
            [0.019, 0.014, 0.002], sides=7), "skin", rigid=f"ear_{side}"))
        parts.append(part(make_tube(
            f"EarBarb_{side}",
            [(sx * 0.105, 0.390, 1.104), (sx * 0.138, 0.395, 1.052)],
            [0.008, 0.001], sides=5), "skin", rigid=f"ear_{side}"))
    parts.append(part(make_tube(
        "SnoutRidge",
        [tuple(project(point, 0.002)) for point in
         [(0.0, 0.470, 1.104), (0.0, 0.520, 1.068), (0.0, 0.592, 1.030)]],
        [0.013, 0.010, 0.005], sides=6), "skin", rigid="head"))

    # Needle teeth: bases are seated on the snout surface so the grin shows.
    def lip_y(x):
        return 0.590 - 1.50 * abs(x)

    for side, sx in (("l", 1.0), ("r", -1.0)):
        for index in range(5):
            x = sx * (0.044 - 0.008 * index)
            base, normal = seat((x, lip_y(x), 1.000), 0.0020)
            tip = base + normal * 0.010 + Vector((0.0, 0.002, -0.030))
            parts.append(part(make_cone(f"ToothUp_{side}_{index}", tuple(base), tuple(tip),
                                        0.0052, 5), "teeth", rigid="head"))
        for index in range(4):
            x = sx * (0.040 - 0.009 * index)
            base, normal = seat((x, lip_y(x), 0.986), 0.0020)
            tip = base + normal * 0.016 + Vector((0.0, 0.002, 0.024))
            parts.append(part(make_cone(f"ToothDown_{side}_{index}", tuple(base), tuple(tip),
                                        0.0046, 5), "teeth", rigid="jaw"))
    lip_line = [tuple(project((x, lip_y(x), 0.993), 0.0008))
                for x in (-0.048, -0.036, -0.022, -0.008,
                          0.008, 0.022, 0.036, 0.048)]
    parts.append(part(make_tube("Mouth", lip_line, [0.0045] * 8, sides=5),
                      "mouth", rigid="head"))

    # Hands: three long claws plus an inner thumb claw.
    for side, sx in (("l", 1.0), ("r", -1.0)):
        for index, offset in enumerate((-0.026, 0.0, 0.026)):
            base = (sx * (0.320 + offset), 0.538, 0.306)
            mid = (sx * (0.320 + offset * 1.12), 0.576, 0.266)
            tip = (sx * (0.320 + offset * 1.25), 0.604, 0.222)
            parts.append(part(make_tube(f"Claw_{side}_{index}", [base, mid, tip],
                                        [0.0120, 0.0080, 0.0010], sides=6),
                              "claw", rigid=f"fingers_{side}"))
        parts.append(part(make_tube(
            f"Thumb_{side}",
            [(sx * 0.288, 0.462, 0.340), (sx * 0.272, 0.500, 0.296),
             (sx * 0.268, 0.528, 0.266)],
            [0.010, 0.007, 0.001], sides=6), "claw", rigid=f"hand_{side}"))
        # Toe claws dig into the ground.
        for index, offset in enumerate((-0.020, 0.0, 0.020)):
            base = (sx * 0.130 + offset, 0.232, 0.040)
            tip = (sx * 0.130 + offset * 1.18, 0.304, 0.0018)
            parts.append(part(make_tube(f"ToeClaw_{side}_{index}", [base, tip],
                                        [0.0095, 0.0008], sides=5),
                              "claw", rigid=f"toes_{side}"))

    # Ember cracks glowing through the hide.
    cracks = (
        ("chest", [(0.120, 0.285, 0.885), (0.142, 0.300, 0.850), (0.132, 0.312, 0.818)]),
        ("chest", [(-0.120, 0.285, 0.885), (-0.142, 0.300, 0.850), (-0.132, 0.312, 0.818)]),
        ("spine_01", [(0.040, -0.008, 0.706), (0.060, 0.000, 0.676), (0.052, 0.008, 0.650)]),
        ("spine_01", [(-0.040, -0.008, 0.706), (-0.060, 0.000, 0.676), (-0.052, 0.008, 0.650)]),
        ("upper_arm_l", [(0.202, 0.318, 0.838), (0.222, 0.330, 0.792), (0.214, 0.340, 0.750)]),
        ("upper_arm_r", [(-0.202, 0.318, 0.838), (-0.222, 0.330, 0.792), (-0.214, 0.340, 0.750)]),
        ("thigh_l", [(0.170, 0.070, 0.492), (0.168, 0.086, 0.454), (0.156, 0.096, 0.420)]),
        ("thigh_r", [(-0.170, 0.070, 0.492), (-0.168, 0.086, 0.454), (-0.156, 0.096, 0.420)]),
    )
    for index, (bone, points) in enumerate(cracks):
        placed = [tuple(project(point, 0.0016)) for point in points]
        parts.append(part(make_tube(f"Crack_{index}", placed,
                                    [0.0034, 0.0028, 0.0010], sides=5),
                          "ember", rigid=bone))

    # Sparse bristle crest on shoulders, spine, upper arms and forearms.
    regions = (
        ("ShoulderL", "clavicle_l", (0.150, 0.270, 0.940), (0.085, 0.085, 0.055), 22,
         (0.045, 0.105), (0.0032, 0.0065), (0.10, -0.55, -0.55),
         lambda p: p[2] > 0.905),
        ("ShoulderR", "clavicle_r", (-0.150, 0.270, 0.940), (0.085, 0.085, 0.055), 22,
         (0.045, 0.105), (0.0032, 0.0065), (-0.10, -0.55, -0.55),
         lambda p: p[2] > 0.905),
        ("Back", "spine_02", (0.0, 0.150, 0.800), (0.110, 0.100, 0.130), 34,
         (0.040, 0.100), (0.0030, 0.0060), (0.0, -0.70, -0.50),
         lambda p: p[1] < 0.155),
        ("Hackles", "neck_01", (0.0, 0.300, 0.975), (0.080, 0.085, 0.070), 16,
         (0.035, 0.090), (0.0028, 0.0055), (0.0, -0.60, -0.60),
         lambda p: (p[1] < 0.310) & (p[2] > 0.945)),
        ("UpperArmL", "upper_arm_l", (0.196, 0.302, 0.830), (0.055, 0.055, 0.110), 12,
         (0.035, 0.085), (0.0028, 0.0058), (0.0, -0.25, -1.0), None),
        ("UpperArmR", "upper_arm_r", (-0.196, 0.302, 0.830), (0.055, 0.055, 0.110), 12,
         (0.035, 0.085), (0.0028, 0.0058), (0.0, -0.25, -1.0), None),
        ("ForearmL", "forearm_l", (0.272, 0.372, 0.572), (0.050, 0.050, 0.115), 24,
         (0.040, 0.090), (0.0028, 0.0058), (0.0, -0.15, -1.0), None),
        ("ForearmR", "forearm_r", (-0.272, 0.372, 0.572), (0.050, 0.050, 0.115), 24,
         (0.040, 0.090), (0.0028, 0.0058), (0.0, -0.15, -1.0), None),
    )
    for index, (name, bone, centre, radii, count, length_range, thickness, bend, region) in enumerate(regions):
        samples = _sample_ellipsoid(rng, centre, radii, count, length_range, thickness,
                                    bend, region)
        parts.append(part(make_clump_field(name, samples, 6400 + index), "hair",
                          rigid=bone))

    tail_samples = _sample_tube(rng, (0.0, -0.055, 0.570), (0.0, -0.295, 0.442), 0.026, 14,
                                (0.028, 0.070), (0.0022, 0.0048), (0.0, -0.5, -0.6))
    parts.append(part(make_clump_field("TailBristles", tail_samples, 6500), "hair",
                      rigid="tail_02"))
    return parts


# ---------------------------------------------------------------------------
# Clips


def _base():
    return {"rot": {}, "legs": {}}


def idle(t: float) -> dict:
    phase = (t / 2.0) % 1.0
    breath = math.sin(TAU * phase)
    scan = math.sin(TAU * phase + 0.9)
    twitch = math.sin(TAU * phase * 4.0 + 0.3) ** 3
    values = _base()
    values["pelvis_offset"] = (0.004 * math.sin(TAU * phase + 0.5),
                               0.004 * breath, 0.007 * breath - 0.003)
    values["pelvis_pitch"] = 0.02 + 0.010 * breath
    values["pelvis_roll"] = 0.012 * math.sin(TAU * phase)
    values["pelvis_yaw"] = 0.012 * scan
    values["jaw_open"] = 0.06 + 0.035 * breath
    values["rot"] = {
        "spine_01": (0.012 * breath, -0.010 * scan, 0.006 * breath),
        "spine_02": (0.016 * breath, -0.012 * scan, 0.006 * breath),
        "chest": (-0.032 * breath, -0.016 * scan, 0.008 * breath),
        "neck_01": (0.014 * breath, 0.020 * scan, -0.006 * breath),
        "neck_02": (0.012 * breath, 0.028 * scan, 0.0),
        "head": (-0.030 - 0.012 * breath, 0.150 * scan + 0.045 * twitch,
                 0.020 * math.sin(TAU * phase * 2.0)),
        "upper_arm_l": (0.020 + 0.020 * breath, 0.0, -0.040),
        "upper_arm_r": (0.020 + 0.020 * breath, 0.0, 0.040),
        "forearm_l": (0.130 + 0.022 * breath, 0.0, 0.0),
        "forearm_r": (0.130 + 0.022 * breath, 0.0, 0.0),
        "hand_l": (0.040, 0.0, 0.0),
        "hand_r": (0.040, 0.0, 0.0),
        "fingers_l": (0.060 + 0.050 * math.sin(TAU * phase * 2.0 + 1.1), 0.0, 0.0),
        "fingers_r": (0.060 + 0.050 * math.sin(TAU * phase * 2.0 + 1.4), 0.0, 0.0),
        "tail_01": (0.050 * breath, 0.140 * math.sin(TAU * phase * 2.0), 0.0),
        "tail_02": (0.040 * breath, 0.190 * math.sin(TAU * phase * 2.0 + 0.7), 0.0),
        "ear_l": (0.06 * math.sin(TAU * phase * 3.0), 0.0, 0.10 * scan),
        "ear_r": (0.05 * math.sin(TAU * phase * 3.0 + 1.4), 0.0, -0.09 * scan),
    }
    values["legs"] = {
        "leg_l": {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0},
        "leg_r": {"y": 0.0, "lift": 0.0, "toe": 0.0, "foot": 0.0},
    }
    return values


def walk(t: float) -> dict:
    phase = (t / 0.90) % 1.0
    swing = math.cos(TAU * phase)
    values = _base()
    values["pelvis_offset"] = (0.008 * math.sin(TAU * phase), 0.0,
                               0.014 * abs(math.sin(TAU * phase * 2.0)) - 0.005)
    values["pelvis_yaw"] = 0.055 * math.sin(TAU * phase)
    values["pelvis_roll"] = 0.030 * swing
    values["pelvis_pitch"] = 0.075 + 0.018 * math.sin(TAU * phase * 2.0)
    values["jaw_open"] = 0.07 + 0.03 * abs(math.sin(TAU * phase * 2.0))
    values["rot"] = {
        "spine_01": (0.020, -0.028 * math.sin(TAU * phase), 0.012 * swing),
        "spine_02": (0.020, -0.032 * math.sin(TAU * phase), 0.012 * swing),
        "chest": (0.014, -0.040 * math.sin(TAU * phase), 0.012 * swing),
        "neck_01": (-0.045, 0.050 * math.sin(TAU * phase), -0.012 * swing),
        "neck_02": (-0.038, 0.050 * math.sin(TAU * phase), -0.010 * swing),
        "head": (-0.070 + 0.035 * math.cos(TAU * phase * 2.0),
                 0.045 * math.sin(TAU * phase), 0.018 * swing),
        "upper_arm_l": (-0.120 - 0.300 * swing, 0.0, -0.080),
        "upper_arm_r": (-0.120 + 0.300 * swing, 0.0, 0.080),
        "forearm_l": (0.160 + 0.200 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.160 + 0.200 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.060, 0.0, 0.0),
        "hand_r": (0.060, 0.0, 0.0),
        "fingers_l": (0.090 + 0.040 * swing, 0.0, 0.0),
        "fingers_r": (0.090 - 0.040 * swing, 0.0, 0.0),
        "tail_01": (0.040, 0.180 * math.sin(TAU * phase + 0.3), 0.0),
        "tail_02": (0.030, 0.240 * math.sin(TAU * phase + 0.9), 0.0),
        "ear_l": (0.05 * swing, 0.0, 0.07),
        "ear_r": (0.05 * swing, 0.0, -0.07),
    }
    _gait(values, phase, 0.55, 0.95, 0.055, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def run(t: float) -> dict:
    phase = (t / 0.50) % 1.0
    swing = math.cos(TAU * phase)
    values = _base()
    values["pelvis_offset"] = (0.012 * math.sin(TAU * phase), 0.0,
                               0.030 * abs(math.sin(TAU * phase * 2.0)) - 0.006)
    values["pelvis_yaw"] = 0.080 * math.sin(TAU * phase)
    values["pelvis_roll"] = 0.050 * swing
    values["pelvis_pitch"] = 0.130 + 0.030 * math.sin(TAU * phase * 2.0)
    values["jaw_open"] = 0.16 + 0.06 * abs(swing)
    values["rot"] = {
        "spine_01": (0.045, -0.045 * math.sin(TAU * phase), 0.018 * swing),
        "spine_02": (0.045, -0.055 * math.sin(TAU * phase), 0.016 * swing),
        "chest": (0.035, -0.065 * math.sin(TAU * phase), 0.018 * swing),
        "neck_01": (-0.080, 0.065 * math.sin(TAU * phase), -0.016 * swing),
        "neck_02": (-0.070, 0.060 * math.sin(TAU * phase), -0.014 * swing),
        "head": (-0.110 + 0.050 * math.cos(TAU * phase * 2.0),
                 0.055 * math.sin(TAU * phase), 0.025 * swing),
        "upper_arm_l": (-0.300 - 0.550 * swing, 0.0, -0.120),
        "upper_arm_r": (-0.300 + 0.550 * swing, 0.0, 0.120),
        "forearm_l": (0.300 + 0.260 * max(0.0, -swing), 0.0, 0.0),
        "forearm_r": (0.300 + 0.260 * max(0.0, swing), 0.0, 0.0),
        "hand_l": (0.090, 0.0, 0.0),
        "hand_r": (0.090, 0.0, 0.0),
        "fingers_l": (0.140 + 0.060 * swing, 0.0, 0.0),
        "fingers_r": (0.140 - 0.060 * swing, 0.0, 0.0),
        "tail_01": (0.070, 0.200 * math.sin(TAU * phase + 0.4), 0.0),
        "tail_02": (0.050, 0.280 * math.sin(TAU * phase + 1.0), 0.0),
        "ear_l": (0.09 * swing, 0.0, 0.10),
        "ear_r": (0.09 * swing, 0.0, -0.10),
    }
    _gait(values, phase, 0.34, 1.70, 0.095, {"leg_l": 0.0, "leg_r": 0.5})
    return values


def attack(t: float) -> dict:
    u = min(1.0, t / 1.10)
    strike = keyed(u, [(0.0, 0.0), (0.32, 0.0), (0.40, 0.58), (0.436, 1.0),
                       (0.58, 0.62), (0.80, 0.14), (1.0, 0.0)])
    coil = keyed(u, [(0.0, 0.0), (0.15, 0.62), (0.30, 1.0), (0.42, 0.30),
                     (0.436, 0.0), (0.65, 0.12), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (
        keyed(u, [(0.0, 0.0), (0.30, 0.020), (0.436, -0.010), (0.70, 0.0), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.30, -0.070), (0.436, 0.150), (0.62, 0.090),
                  (0.85, 0.020), (1.0, 0.0)]),
        keyed(u, [(0.0, 0.0), (0.30, -0.075), (0.436, -0.032), (0.62, -0.002), (1.0, 0.0)]),
    )
    values["pelvis_pitch"] = keyed(u, [(0.0, 0.0), (0.30, 0.120), (0.40, 0.020),
                                       (0.436, -0.200), (0.62, -0.100), (0.85, -0.020), (1.0, 0.0)])
    values["pelvis_yaw"] = keyed(u, [(0.0, 0.0), (0.30, 0.080), (0.436, -0.050),
                                     (0.70, 0.0), (1.0, 0.0)])
    values["pelvis_roll"] = keyed(u, [(0.0, 0.0), (0.30, 0.050), (0.436, -0.060),
                                      (0.70, 0.0), (1.0, 0.0)])
    values["jaw_open"] = keyed(u, [(0.0, 0.05), (0.30, 0.22), (0.40, 0.48), (0.436, 0.54),
                                   (0.62, 0.28), (0.85, 0.10), (1.0, 0.05)])
    values["rot"] = {
        "spine_01": (keyed(u, [(0.0, 0.0), (0.30, 0.040), (0.436, -0.070), (1.0, 0.0)]), 0.0, 0.0),
        "spine_02": (keyed(u, [(0.0, 0.0), (0.30, 0.050), (0.436, -0.090), (1.0, 0.0)]), 0.0, 0.0),
        "chest": (keyed(u, [(0.0, 0.0), (0.30, 0.060), (0.436, -0.120), (1.0, 0.0)]), 0.0, 0.0),
        "neck_01": (keyed(u, [(0.0, 0.0), (0.30, 0.060), (0.436, 0.120), (1.0, 0.0)]), 0.0, 0.0),
        "neck_02": (keyed(u, [(0.0, 0.0), (0.30, 0.050), (0.436, 0.100), (1.0, 0.0)]), 0.0, 0.0),
        "head": (keyed(u, [(0.0, 0.0), (0.30, 0.180), (0.40, 0.100), (0.436, -0.100),
                           (0.62, -0.050), (0.85, 0.0), (1.0, 0.0)]), 0.0, 0.0),
        "upper_arm_l": (keyed(u, [(0.0, 0.0), (0.30, -0.550), (0.40, -0.100), (0.436, 0.850),
                                  (0.58, 0.650), (0.80, 0.180), (1.0, 0.0)]), 0.0, -0.10),
        "upper_arm_r": (keyed(u, [(0.0, 0.0), (0.30, -0.550), (0.40, -0.100), (0.436, 0.850),
                                  (0.58, 0.650), (0.80, 0.180), (1.0, 0.0)]), 0.0, 0.10),
        "forearm_l": (keyed(u, [(0.0, 0.12), (0.30, 0.550), (0.40, 0.300), (0.436, 0.150),
                                (0.62, 0.320), (1.0, 0.12)]), 0.0, 0.0),
        "forearm_r": (keyed(u, [(0.0, 0.12), (0.30, 0.550), (0.40, 0.300), (0.436, 0.150),
                                (0.62, 0.320), (1.0, 0.12)]), 0.0, 0.0),
        "hand_l": (keyed(u, [(0.0, 0.05), (0.30, 0.120), (0.40, -0.250), (0.436, -0.360),
                             (0.62, 0.0), (1.0, 0.05)]), 0.0, 0.0),
        "hand_r": (keyed(u, [(0.0, 0.05), (0.30, 0.120), (0.40, -0.250), (0.436, -0.360),
                             (0.62, 0.0), (1.0, 0.05)]), 0.0, 0.0),
        "fingers_l": (keyed(u, [(0.0, 0.10), (0.30, 0.180), (0.40, -0.280), (0.436, -0.420),
                                (0.62, -0.050), (1.0, 0.10)]), 0.0, 0.0),
        "fingers_r": (keyed(u, [(0.0, 0.10), (0.30, 0.180), (0.40, -0.280), (0.436, -0.420),
                                (0.62, -0.050), (1.0, 0.10)]), 0.0, 0.0),
        "tail_01": (keyed(u, [(0.0, 0.04), (0.30, -0.25), (0.436, 0.35), (0.70, 0.10), (1.0, 0.04)]),
                    0.0, 0.0),
        "tail_02": (keyed(u, [(0.0, 0.03), (0.30, -0.20), (0.436, 0.30), (0.70, 0.08), (1.0, 0.03)]),
                    0.0, 0.0),
    }
    values["legs"] = {
        "leg_l": {"y": keyed(u, [(0.0, 0.0), (0.30, -0.030), (0.436, 0.100),
                                 (0.62, 0.080), (1.0, 0.0)]),
                  "lift": 0.0, "toe": 0.0, "foot": 0.0},
        "leg_r": {"y": keyed(u, [(0.0, 0.0), (0.30, 0.030), (0.436, -0.100),
                                 (0.62, -0.080), (1.0, 0.0)]),
                  "lift": 0.0, "toe": 0.0, "foot": 0.0},
    }
    return values


def hit(t: float) -> dict:
    u = min(1.0, t / 0.40)
    recoil = keyed(u, [(0.0, 0.0), (0.22, 1.0), (0.55, 0.55), (1.0, 0.0)])
    values = _base()
    values["pelvis_offset"] = (0.0, -0.050 * recoil, -0.008 * recoil)
    values["pelvis_pitch"] = -0.080 * recoil
    values["pelvis_roll"] = 0.070 * recoil
    values["pelvis_yaw"] = -0.030 * recoil
    values["jaw_open"] = 0.06 + 0.20 * recoil
    values["rot"] = {
        "spine_01": (-0.100 * recoil, 0.0, 0.040 * recoil),
        "spine_02": (-0.120 * recoil, 0.0, 0.045 * recoil),
        "chest": (-0.140 * recoil, 0.0, 0.050 * recoil),
        "neck_01": (-0.120 * recoil, 0.0, 0.050 * recoil),
        "neck_02": (-0.110 * recoil, 0.0, 0.045 * recoil),
        "head": (-0.280 * recoil, 0.140 * recoil, 0.120 * recoil),
        "upper_arm_l": (-0.200 * recoil, 0.0, -0.180 * recoil),
        "upper_arm_r": (-0.180 * recoil, 0.0, 0.160 * recoil),
        "forearm_l": (0.250 + 0.180 * recoil, 0.0, 0.0),
        "forearm_r": (0.250 + 0.150 * recoil, 0.0, 0.0),
        "hand_l": (0.05 + 0.15 * recoil, 0.0, 0.0),
        "hand_r": (0.05 + 0.12 * recoil, 0.0, 0.0),
        "tail_01": (-0.160 * recoil, 0.150 * recoil, 0.0),
        "tail_02": (-0.140 * recoil, 0.190 * recoil, 0.0),
    }
    values["legs"] = {
        "leg_l": {"y": 0.030 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.050 * recoil},
        "leg_r": {"y": -0.020 * recoil, "lift": 0.0, "toe": 0.0, "foot": 0.050 * recoil},
    }
    return values


def death(t: float) -> dict:
    u = min(1.0, t / 1.0)
    collapse = keyed(u, [(0.0, 0.0), (0.12, 0.10), (0.50, 0.72), (0.78, 1.0), (1.0, 1.0)])
    roll = keyed(u, [(0.0, 0.0), (0.22, 0.12), (0.55, 0.62), (0.82, 1.02), (1.0, 1.02)])
    values = _base()
    values["pelvis_offset"] = (
        keyed(u, [(0.0, 0.0), (0.50, 0.050), (0.80, 0.110), (1.0, 0.120)]),
        keyed(u, [(0.0, 0.0), (0.30, -0.080), (0.70, 0.050), (1.0, 0.080)]),
        -0.340 * collapse,
    )
    values["pelvis_pitch"] = 0.550 * collapse
    values["pelvis_roll"] = roll
    values["pelvis_yaw"] = 0.200 * collapse
    values["jaw_open"] = 0.20 + 0.16 * collapse
    values["rot"] = {
        "spine_01": (0.120 * collapse, 0.060 * collapse, 0.080 * collapse),
        "spine_02": (0.140 * collapse, 0.080 * collapse, 0.090 * collapse),
        "chest": (0.100 * collapse, 0.060 * collapse, 0.080 * collapse),
        "neck_01": (-0.180 * collapse, -0.120 * collapse, -0.140 * collapse),
        "neck_02": (-0.200 * collapse, -0.140 * collapse, -0.160 * collapse),
        "head": (-0.340 * collapse, -0.200 * collapse, -0.300 * collapse),
        "upper_arm_l": (0.300 * collapse, 0.0, -0.400 * collapse),
        "upper_arm_r": (-0.550 * collapse, 0.0, -0.150 * collapse),
        "forearm_l": (0.120 + 0.700 * collapse, 0.0, 0.0),
        "forearm_r": (0.120 + 0.550 * collapse, 0.0, 0.0),
        "hand_l": (0.05 + 0.250 * collapse, 0.0, 0.0),
        "hand_r": (0.05 + 0.220 * collapse, 0.0, 0.0),
        "fingers_l": (0.10 + 0.280 * collapse, 0.0, 0.0),
        "fingers_r": (0.10 + 0.240 * collapse, 0.0, 0.0),
        "tail_01": (-0.320 * collapse, 0.220 * collapse, 0.0),
        "tail_02": (-0.280 * collapse, 0.260 * collapse, 0.0),
        "ear_l": (-0.180 * collapse, 0.0, 0.220 * collapse),
        "ear_r": (-0.160 * collapse, 0.0, -0.200 * collapse),
    }
    values["legs"] = {
        "leg_l": {"y": -0.060 * collapse, "lift": 0.020 * collapse,
                  "toe": 0.150 * collapse, "foot": -0.150 * collapse},
        "leg_r": {"y": 0.100 * collapse, "lift": 0.0,
                  "toe": -0.100 * collapse, "foot": 0.150 * collapse},
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
            toe = -0.26 * math.sin(math.pi * p)
            foot = 0.18 * math.sin(math.pi * p)
        values["legs"][chain_key] = {"y": y, "lift": lift, "toe": toe, "foot": foot}


CLIPS = {
    "idle": {"name": "Spawn_Idle_Loop", "duration": 2.0, "loop": True},
    "walk": {"name": "Spawn_Walk_Loop", "duration": 0.90, "loop": True,
             "stride": 0.95, "duty": 0.55, "fallback_speed": 1.06},
    "run": {"name": "Spawn_Run_Loop", "duration": 0.50, "loop": True,
            "stride": 1.70, "duty": 0.34, "fallback_speed": 3.40},
    "attack": {"name": "Spawn_Attack", "duration": 1.10, "loop": False,
               "impact": 0.48, "recovery_end": 1.10},
    "hit": {"name": "Spawn_Hit", "duration": 0.40, "loop": False},
    "death": {"name": "Spawn_Death", "duration": 1.00, "loop": False},
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
    "id": "spawn",
    "display_name": "Devil spawn",
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
    "paint_tags": ["body", "skin", "bone", "mouth", "teeth", "claw", "hair",
                   "eye", "ember"],
    "eyes": EYES,
    "normal_strength": 1.10,
    "build_parts": build_parts,
    "clips": CLIPS,
    "poses": POSES,
    "head_zone": {"bone": "head", "radius": 0.22, "half_height": 0.10},
    "metadata_extra": {
        "role": "skirmisher",
        "surface_notes": ["near-black blue-grey hide", "exposed tan ribcage",
                          "needle teeth", "ember eyes", "keratin back spikes",
                          "sparse bristle crest"],
    },
}
