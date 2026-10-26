"""Author the Cinder devil and export a skinned, animated GLB.

The cinder devil is the frontier's pack enemy: it circles in threes and fives,
dives, leaps, slides, kites with a bow and dies in numbers. It used to be a
half-metre figure of runtime ``Geo`` spheres; this script replaces that with an
authored creature in the same deterministic Blender route as the Unholy Forest
mobset.

The silhouette is deliberately wrong-shaped for a person: a two-metre gaunt
frame with a long thrust-forward skull, arms that hang past the knees, a
ribcage split down the sternum with the fire still inside it, ash crusted on
every surface the heat blows across, and a barbed tail. Nothing is smooth where
a body should show bone.

Geometry, rig, skin weights, seven baked clips and every texture atlas are
produced here from ``tools/cinder_devil_surface.py`` and
``tools/cinder_devil_styles.py``. No third-party model, texture or motion is
used, and no download is required to rebuild it.

Build:

    python tools/build_cinder_devil.py

The shared authoring machinery lives in ``tools/prepare_forest_mobs.py``. This
module swaps in the cinder style and surface modules by rebinding that module's
globals, which is what lets one bake/rig/export implementation serve both
mobsets without a fork.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import cinder_devil_styles as styles  # noqa: E402
import cinder_devil_surface as surfaces  # noqa: E402
import prepare_forest_mobs as authoring  # noqa: E402

MOB = "cinder_devil"
ROOT = styles.ROOT
FPS = styles.FPS
SEED = styles.SEED


# Scene transform for the whole head. A demon head on a slim neck reads as a
# bird; the skull is carried at 1.14x and pushed forward of the shoulders, which
# is also the start of the hunch the rest pose leans into. One knob, applied to
# joints and geometry alike, so bone and mesh can never drift apart.
HEAD_CENTRE = Vector((0.0, 0.100, 1.980))
HEAD_SCALE = 1.16
HEAD_SHIFT = Vector((0.0, 0.062, -0.026))


def _h(point) -> Vector:
    """Head-local coordinate (as authored around HEAD_CENTRE) to world."""
    return HEAD_CENTRE + (Vector(point) - HEAD_CENTRE) * HEAD_SCALE + HEAD_SHIFT


def _hs(half) -> tuple[float, float, float]:
    size = Vector(half) * HEAD_SCALE
    return (size.x, size.y, size.z)


# ---------------------------------------------------------------------------
# Rig
#
# Metres, Y forward, Z up. The frame is 2.11 m to the crown and over 2.5 m
# across the swept horns. Shoulders sit forward of the pelvis and the skull is
# thrust again further forward, so the rest pose already reads as a predator
# leaning into its own stride.

CINDER_JOINTS = {
    "pelvis": ((0.0, 0.0, 1.030), (0.0, 0.0, 1.150)),
    "spine_01": ((0.0, 0.0, 1.150), (0.0, 0.012, 1.340)),
    "spine_02": ((0.0, 0.012, 1.340), (0.0, 0.004, 1.540)),
    "chest": ((0.0, 0.004, 1.540), (0.0, 0.020, 1.760)),
    "neck_01": ((0.0, 0.020, 1.760), (0.0, 0.070, 1.850)),
    "neck_02": ((0.0, 0.070, 1.850), tuple(_h((0.0, 0.096, 1.925)))),
    "head": (tuple(_h((0.0, 0.096, 1.925))), tuple(_h((0.0, 0.128, 2.110)))),
    "jaw": (tuple(_h((0.0, 0.120, 1.980))), tuple(_h((0.0, 0.205, 1.892)))),
    "thigh_l": ((0.128, 0.0, 1.000), (0.140, 0.020, 0.560)),
    "shin_l": ((0.140, 0.020, 0.560), (0.148, -0.030, 0.130)),
    "foot_l": ((0.148, -0.030, 0.130), (0.154, 0.095, 0.038)),
    "toe_l": ((0.154, 0.095, 0.038), (0.154, 0.235, 0.022)),
    "thigh_r": ((-0.128, 0.0, 1.000), (-0.140, 0.020, 0.560)),
    "shin_r": ((-0.140, 0.020, 0.560), (-0.148, -0.030, 0.130)),
    "foot_r": ((-0.148, -0.030, 0.130), (-0.154, 0.095, 0.038)),
    "toe_r": ((-0.154, 0.095, 0.038), (-0.154, 0.235, 0.022)),
    "clavicle_l": ((0.042, 0.008, 1.720), (0.200, 0.012, 1.694)),
    "upper_arm_l": ((0.200, 0.012, 1.694), (0.264, 0.032, 1.330)),
    "lower_arm_l": ((0.264, 0.032, 1.330), (0.314, 0.056, 0.978)),
    "hand_l": ((0.314, 0.056, 0.978), (0.326, 0.082, 0.858)),
    "finger_l_1": ((0.308, 0.096, 0.866), (0.313, 0.152, 0.730)),
    "finger_l_2": ((0.332, 0.090, 0.866), (0.348, 0.144, 0.742)),
    "finger_l_3": ((0.352, 0.070, 0.866), (0.374, 0.114, 0.760)),
    "clavicle_r": ((-0.042, 0.008, 1.720), (-0.200, 0.012, 1.694)),
    "upper_arm_r": ((-0.200, 0.012, 1.694), (-0.264, 0.032, 1.330)),
    "lower_arm_r": ((-0.264, 0.032, 1.330), (-0.314, 0.056, 0.978)),
    "hand_r": ((-0.314, 0.056, 0.978), (-0.326, 0.082, 0.858)),
    "finger_r_1": ((-0.308, 0.096, 0.866), (-0.313, 0.152, 0.730)),
    "finger_r_2": ((-0.332, 0.090, 0.866), (-0.348, 0.144, 0.742)),
    "finger_r_3": ((-0.352, 0.070, 0.866), (-0.374, 0.114, 0.760)),
    "crown_l": (tuple(_h((0.082, 0.006, 2.026))), tuple(_h((0.210, -0.072, 2.190)))),
    "crown_l2": (tuple(_h((0.210, -0.072, 2.190))), tuple(_h((0.320, -0.208, 2.286)))),
    "crown_r": (tuple(_h((-0.082, 0.006, 2.026))), tuple(_h((-0.210, -0.072, 2.190)))),
    "crown_r2": (tuple(_h((-0.210, -0.072, 2.190))), tuple(_h((-0.320, -0.208, 2.286)))),
    "tail_01": ((0.0, -0.086, 1.070), (0.0, -0.232, 1.004)),
    "tail_02": ((0.0, -0.232, 1.004), (0.0, -0.352, 0.898)),
    "tail_03": ((0.0, -0.352, 0.898), (0.0, -0.442, 0.766)),
}

CINDER_PARENTS = {
    "pelvis": ("root", False),
    "spine_01": ("pelvis", True),
    "spine_02": ("spine_01", True),
    "chest": ("spine_02", True),
    "neck_01": ("chest", False),
    "neck_02": ("neck_01", True),
    "head": ("neck_02", True),
    "jaw": ("head", False),
    "thigh_l": ("pelvis", False),
    "shin_l": ("thigh_l", True),
    "foot_l": ("shin_l", True),
    "toe_l": ("foot_l", True),
    "thigh_r": ("pelvis", False),
    "shin_r": ("thigh_r", True),
    "foot_r": ("shin_r", True),
    "toe_r": ("foot_r", True),
    "clavicle_l": ("chest", False),
    "upper_arm_l": ("clavicle_l", True),
    "lower_arm_l": ("upper_arm_l", True),
    "hand_l": ("lower_arm_l", True),
    "finger_l_1": ("hand_l", False),
    "finger_l_2": ("hand_l", False),
    "finger_l_3": ("hand_l", False),
    "clavicle_r": ("chest", False),
    "upper_arm_r": ("clavicle_r", True),
    "lower_arm_r": ("upper_arm_r", True),
    "hand_r": ("lower_arm_r", True),
    "finger_r_1": ("hand_r", False),
    "finger_r_2": ("hand_r", False),
    "finger_r_3": ("hand_r", False),
    "crown_l": ("head", False),
    "crown_l2": ("crown_l", True),
    "crown_r": ("head", False),
    "crown_r2": ("crown_r", True),
    "tail_01": ("pelvis", False),
    "tail_02": ("tail_01", True),
    "tail_03": ("tail_02", True),
}

# Sternum fissure: the ribs stop short of the centre line and the chest opens.
STERNUM_SPLIT = 0.042

# Finger and toe tips, copied from the joint table above so a claw can never
# float a centimetre away from the digit it belongs to.
FINGER_TIPS = {
    "l": [Vector((0.313, 0.152, 0.730)), Vector((0.348, 0.144, 0.742)), Vector((0.374, 0.114, 0.760))],
    "r": [Vector((-0.313, 0.152, 0.730)), Vector((-0.348, 0.144, 0.742)), Vector((-0.374, 0.114, 0.760))],
}
FINGER_DIRECTIONS = (
    Vector((0.05, 0.42, -0.90)),
    Vector((0.10, 0.36, -0.92)),
    Vector((0.14, 0.34, -0.92)),
)
TOE_TIPS = {
    "l": [Vector((0.130, 0.176, 0.030)), Vector((0.154, 0.190, 0.030)), Vector((0.178, 0.172, 0.030))],
    "r": [Vector((-0.130, 0.176, 0.030)), Vector((-0.154, 0.190, 0.030)), Vector((-0.178, 0.172, 0.030))],
}


def _front_at(obj, x_centre: float, z_centre: float,
              x_tolerance: float = 0.014, z_tolerance: float = 0.014) -> float:
    """Forward-most vertex Y inside a small window — measured, never guessed."""
    best = -1.0
    for vertex in obj.data.vertices:
        if abs(vertex.co.x - x_centre) <= x_tolerance and abs(vertex.co.z - z_centre) <= z_tolerance:
            best = max(best, vertex.co.y)
    # An empty window would place a void bowl inside the skull; fall back to a
    # plausible muzzle plane instead of a negative Y.
    return best if best > -0.5 else 0.140


def _horn(name: str, material, base: Vector, direction: Vector, length: float,
          radius: float, curve: float, salt: float, sides: int = 14):
    """A swept horn: one continuous keratin tine, never a branching rack.

    The heading rotates away from the face and back over the skull as it
    climbs, so the horn leaves the head going up and forward and arrives
    pointing behind the shoulders. Thick at the root, no tip radus below 6 mm.
    """
    steps = 12
    path = [base.copy()]
    heading = direction.normalized()
    bend = Vector((0.0, -1.0, 0.22))
    for _step in range(1, steps + 1):
        heading = (heading + bend * (curve * 0.145)).normalized()
        path.append(path[-1] + heading * (length / steps))
    radii = [radius * (1.14 - 1.04 * ((step / steps) ** 1.12)) for step in range(steps + 1)]
    radii[-1] = max(0.006, radii[-1])
    return authoring.tapered_tube(name, path, radii, sides, material, wobble=0.05, salt=salt)


def _s(value: float) -> float:
    """A head-local length in world metres."""
    return float(value) * HEAD_SCALE


def assemble_cinder_devil():
    char = authoring.material("char")
    ash = authoring.material("ash")
    horn = authoring.material("horn")
    bone = authoring.material("bone")
    leather = authoring.material("leather")
    cloth = authoring.material("cloth")
    void = authoring.material("void")
    ember = authoring.material("ember")

    # A gaunt frame under burnt hide. The torso is a wedge — broad chest over
    # a pinched waist — because a uniform tube reads as a mannequin no matter
    # what is painted on it.
    body = authoring.metaball_mesh(
        "CinderBody",
        lambda mb: (
            authoring.metaball_ellipsoid(mb, (0.0, 0.0, 1.062), (0.134, 0.096, 0.080)),
            authoring.metaball_capsule(mb, (0.0, 0.004, 1.100), (0.0, 0.010, 1.280), 0.096),
            authoring.metaball_ellipsoid(mb, (0.0, 0.010, 1.372), (0.132, 0.098, 0.096)),
            authoring.metaball_ellipsoid(mb, (0.0, 0.012, 1.520), (0.152, 0.106, 0.100)),
            authoring.metaball_ellipsoid(mb, (0.0, 0.012, 1.664), (0.168, 0.100, 0.088)),
            # Pectoral shelves and the trapezius ridge: the mass a ribcage hangs off.
            authoring.metaball_ellipsoid(mb, (0.074, 0.068, 1.638), (0.072, 0.046, 0.058)),
            authoring.metaball_ellipsoid(mb, (-0.074, 0.068, 1.638), (0.072, 0.046, 0.058)),
            authoring.metaball_ellipsoid(mb, (0.090, 0.006, 1.742), (0.092, 0.070, 0.046)),
            authoring.metaball_ellipsoid(mb, (-0.090, 0.006, 1.742), (0.092, 0.070, 0.046)),
            # Shoulder blades stand proud of the back.
            authoring.metaball_ellipsoid(mb, (0.126, -0.058, 1.688), (0.068, 0.042, 0.080)),
            authoring.metaball_ellipsoid(mb, (-0.126, -0.058, 1.688), (0.068, 0.042, 0.080)),
            authoring.metaball_capsule(mb, (0.0, 0.020, 1.744), _h((0.0, 0.096, 1.925)), 0.056),
            authoring.metaball_ellipsoid(mb, _h((0.0, 0.104, 1.980)), _hs((0.098, 0.100, 0.096))),
            # Deltoids, so the arm does not plug into a socket.
            authoring.metaball_ellipsoid(mb, (0.198, 0.004, 1.690), (0.070, 0.068, 0.066)),
            authoring.metaball_capsule(mb, (0.200, 0.012, 1.694), (0.264, 0.032, 1.330), 0.056),
            authoring.metaball_capsule(mb, (0.264, 0.032, 1.330), (0.314, 0.056, 0.978), 0.047),
            authoring.metaball_ellipsoid(mb, (0.322, 0.068, 0.900), (0.042, 0.048, 0.038)),
            authoring.metaball_capsule(mb, (0.306, 0.098, 0.884), (0.313, 0.152, 0.730), 0.018),
            authoring.metaball_capsule(mb, (0.331, 0.092, 0.884), (0.348, 0.144, 0.742), 0.017),
            authoring.metaball_capsule(mb, (0.352, 0.072, 0.884), (0.374, 0.114, 0.760), 0.016),
            authoring.metaball_ellipsoid(mb, (-0.198, 0.004, 1.690), (0.070, 0.068, 0.066)),
            authoring.metaball_capsule(mb, (-0.200, 0.012, 1.694), (-0.264, 0.032, 1.330), 0.056),
            authoring.metaball_capsule(mb, (-0.264, 0.032, 1.330), (-0.314, 0.056, 0.978), 0.047),
            authoring.metaball_ellipsoid(mb, (-0.322, 0.068, 0.900), (0.042, 0.048, 0.038)),
            authoring.metaball_capsule(mb, (-0.306, 0.098, 0.884), (-0.313, 0.152, 0.730), 0.018),
            authoring.metaball_capsule(mb, (-0.331, 0.092, 0.884), (-0.348, 0.144, 0.742), 0.017),
            authoring.metaball_capsule(mb, (-0.352, 0.072, 0.884), (-0.374, 0.114, 0.760), 0.016),
            authoring.metaball_capsule(mb, (0.128, 0.0, 1.000), (0.140, 0.020, 0.560), 0.072),
            # Calf mass, or the shin reads as a dowel.
            authoring.metaball_ellipsoid(mb, (0.145, 0.004, 0.430), (0.050, 0.054, 0.078)),
            authoring.metaball_capsule(mb, (0.140, 0.020, 0.560), (0.148, -0.030, 0.130), 0.045),
            authoring.metaball_capsule(mb, (0.150, -0.020, 0.096), (0.154, 0.070, 0.048), 0.048),
            authoring.metaball_ellipsoid(mb, (0.152, -0.070, 0.056), (0.044, 0.048, 0.044)),
            authoring.metaball_capsule(mb, (0.132, 0.078, 0.046), (0.130, 0.176, 0.030), 0.018),
            authoring.metaball_capsule(mb, (0.154, 0.080, 0.046), (0.154, 0.190, 0.030), 0.018),
            authoring.metaball_capsule(mb, (0.176, 0.076, 0.046), (0.178, 0.172, 0.030), 0.017),
            authoring.metaball_capsule(mb, (-0.128, 0.0, 1.000), (-0.140, 0.020, 0.560), 0.072),
            authoring.metaball_ellipsoid(mb, (-0.145, 0.004, 0.430), (0.050, 0.054, 0.078)),
            authoring.metaball_capsule(mb, (-0.140, 0.020, 0.560), (-0.148, -0.030, 0.130), 0.045),
            authoring.metaball_capsule(mb, (-0.150, -0.020, 0.096), (-0.154, 0.070, 0.048), 0.048),
            authoring.metaball_ellipsoid(mb, (-0.152, -0.070, 0.056), (0.044, 0.048, 0.044)),
            authoring.metaball_capsule(mb, (-0.132, 0.078, 0.046), (-0.130, 0.176, 0.030), 0.018),
            authoring.metaball_capsule(mb, (-0.154, 0.080, 0.046), (-0.154, 0.190, 0.030), 0.018),
            authoring.metaball_capsule(mb, (-0.176, 0.076, 0.046), (-0.178, 0.172, 0.030), 0.017),
        ),
        0.011,
        0.6,
        0.40,
        char,
    )
    authoring.displace_radial(body, 2, 0.008, 17.0, 0.55, 4.5)

    # --- the split ribcage -------------------------------------------------
    # Real ribs hang down and forward at the sternum and climb as they wrap to
    # the spine. A level ring reads as a barrel hoop, which is worse than no
    # ribs at all.
    ribs = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        for index in range(4):
            crown = 1.664 - index * 0.078
            reach = 1.0 - index * 0.045
            path = [
                Vector((sx * STERNUM_SPLIT, 0.082, crown - 0.062)),
                Vector((sx * 0.070 * reach, 0.100, crown - 0.050)),
                Vector((sx * 0.126 * reach, 0.074, crown - 0.014)),
                Vector((sx * 0.150 * reach, -0.004, crown + 0.026)),
                Vector((sx * 0.138 * reach, -0.076, crown + 0.056)),
            ]
            radii = [0.015, 0.019, 0.018, 0.014, 0.009]
            ribs.append(
                authoring.tapered_tube(f"CinderRib_{side}{index}", path, radii, 7, bone,
                                       wobble=0.10, salt=31.0 + index + sx)
            )

    # The cavity behind the split, and the embers still burning in it.
    chest_cavity = authoring.void_bowl("CinderChestVoid", void,
                                       Vector((0.0, 0.098, 1.520)), 0.072, 0.62)
    heart = authoring.ember_eye("CinderHeart", ember, Vector((0.0, 0.094, 1.500)), 0.052)
    flames = [
        authoring.tapered_tube(
            "CinderFlameCentre",
            [Vector((0.0, 0.106, 1.392)), Vector((0.0, 0.102, 1.500)), Vector((0.0, 0.098, 1.624))],
            [0.013, 0.010, 0.004], 6, ember, wobble=0.18, salt=41.0,
        ),
        authoring.tapered_tube(
            "CinderFlameLeft",
            [Vector((0.040, 0.096, 1.400)), Vector((0.033, 0.094, 1.470)), Vector((0.026, 0.092, 1.552))],
            [0.009, 0.007, 0.003], 5, ember, wobble=0.20, salt=43.0,
        ),
        authoring.tapered_tube(
            "CinderFlameRight",
            [Vector((-0.038, 0.098, 1.406)), Vector((-0.031, 0.094, 1.478)), Vector((-0.024, 0.092, 1.560))],
            [0.009, 0.007, 0.003], 5, ember, wobble=0.20, salt=45.0,
        ),
    ]

    # --- spine: a ridge of bone pushing through the burnt back --------------
    spine_spikes = []
    for index in range(8):
        t = index / 7.0
        z = 1.106 + t * 0.700
        y = -0.068 - 0.040 * math.sin(t * math.pi * 0.85)
        length = 0.034 + 0.058 * math.sin(t * math.pi * 0.9)
        spine_spikes.append(
            authoring.tapered_tube(
                f"CinderSpine{index}",
                [Vector((0.0, y + 0.020, z)),
                 Vector((0.0, y - length * 0.28, z + length * 0.66)),
                 Vector((0.0, y - length * 0.44, z + length * 0.98))],
                [0.019, 0.013, 0.004], 5, bone, wobble=0.12, salt=61.0 + index,
            )
        )

    # --- head, jaw, horns --------------------------------------------------
    # A long snout projects past the brow, so the profile is a muzzle and only
    # the silhouette behind it reads as a skull. Symmetric upright horns read
    # as ears; these sweep back over the shoulders.
    skull = authoring.metaball_mesh(
        "CinderSkull",
        lambda mb: (
            authoring.metaball_ellipsoid(mb, _h((0.0, 0.036, 2.012)), _hs((0.094, 0.088, 0.094))),
            authoring.metaball_ellipsoid(mb, _h((0.0, -0.038, 1.982)), _hs((0.064, 0.052, 0.062))),
            authoring.metaball_ellipsoid(mb, _h((0.0, 0.126, 2.010)), _hs((0.098, 0.040, 0.026))),
            authoring.metaball_capsule(mb, _h((0.0, 0.112, 1.992)), _h((0.0, 0.268, 1.974)),
                                       _s(0.047)),
            authoring.metaball_ellipsoid(mb, _h((0.0, 0.292, 1.966)), _hs((0.040, 0.038, 0.032))),
            authoring.metaball_ellipsoid(mb, _h((0.082, 0.150, 1.970)), _hs((0.032, 0.056, 0.042))),
            authoring.metaball_ellipsoid(mb, _h((-0.082, 0.150, 1.970)), _hs((0.032, 0.056, 0.042))),
            authoring.metaball_ellipsoid(mb, _h((0.086, 0.014, 2.018)), _hs((0.026, 0.050, 0.052))),
            authoring.metaball_ellipsoid(mb, _h((-0.086, 0.014, 2.018)), _hs((0.026, 0.050, 0.052))),
        ),
        0.007,
        0.6,
        0.40,
        char,
    )
    authoring.displace_radial(skull, 2, 0.005, 24.0, 0.5, 6.0)
    # The maw is a real gap, the sockets are pressed in, and the cranium is
    # split down the middle with heat showing through.
    authoring.carve_front(skull, _h((0.0, 0.0, 1.900)).z, _h((0.0, 0.0, 1.962)).z,
                          _s(0.078), _s(0.062), salt=7.1)
    authoring.carve_front(skull, _h((0.0, 0.0, 2.006)).z, _h((0.0, 0.0, 2.086)).z,
                          _s(0.016), _s(0.030), salt=8.3)
    for sx in (1.0, -1.0):
        authoring.carve_dimple(skull, _h((sx * 0.054, 0.164, 2.006)), _s(0.046), _s(0.050))
    maw_z = _h((0.0, 0.0, 1.930)).z
    maw_front = _front_at(skull, 0.0, maw_z, _s(0.030), _s(0.016))

    # The cavity sits behind the teeth, so the maw is a hole with a rim of
    # fangs rather than a plate of tusks.
    tongue_void = authoring.metaball_mesh(
        "CinderMouthVoid",
        lambda mb: (
            authoring.metaball_ellipsoid(mb, Vector((0.0, maw_front - _s(0.034), maw_z)),
                                        (_s(0.042), _s(0.048), _s(0.032))),
        ),
        0.008,
        0.6,
        0.5,
        void,
    )
    skull_split = authoring.tapered_tube(
        "CinderSkullSplit",
        [_h((0.0, 0.092, 2.030)), _h((0.0, 0.100, 2.062)), _h((0.0, 0.106, 2.090))],
        [_s(0.014), _s(0.010), _s(0.004)], 6, ember, wobble=0.12, salt=9.7,
    )

    sockets = []
    eyes = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        socket_centre = _h((sx * 0.054, 0.164, 2.006))
        socket_front = _front_at(skull, socket_centre.x, socket_centre.z, _s(0.016), _s(0.016))
        sockets.append(
            authoring.metaball_mesh(
                f"CinderSocket_{side}",
                lambda mb, cx=socket_centre, front=socket_front: (
                    authoring.metaball_ellipsoid(mb, Vector((cx.x, front - _s(0.024), cx.z)),
                                                (_s(0.028), _s(0.036), _s(0.030))),
                ),
                0.007,
                0.6,
                0.5,
                void,
            )
        )
        eyes.append(
            authoring.ember_eye(f"CinderEye_{side}", ember,
                                Vector((socket_centre.x, socket_front - _s(0.012), socket_centre.z)),
                                _s(0.024))
        )

    jaw = authoring.metaball_mesh(
        "CinderJaw",
        lambda mb: (
            authoring.metaball_capsule(mb, _h((-0.052, 0.128, 1.938)), _h((0.052, 0.128, 1.938)),
                                       _s(0.028)),
            authoring.metaball_capsule(mb, _h((0.052, 0.128, 1.938)), _h((0.028, 0.238, 1.912)),
                                       _s(0.024)),
            authoring.metaball_capsule(mb, _h((-0.052, 0.128, 1.938)), _h((-0.028, 0.238, 1.912)),
                                       _s(0.024)),
            authoring.metaball_ellipsoid(mb, _h((0.0, 0.252, 1.908)), _hs((0.042, 0.040, 0.022))),
        ),
        0.007,
        0.6,
        0.45,
        char,
    )

    # Six teeth, not a comb: long canines at the corners of the maw and short
    # incisors between them. Even, equal teeth read as a zipper.
    fangs = []
    upper_teeth = (
        (0.046, 0.066, 0.011), (-0.046, 0.066, 0.011),
        (0.016, 0.034, 0.008), (-0.016, 0.034, 0.008),
    )
    for index, (offset, length, radius) in enumerate(upper_teeth):
        base_y = maw_front + _s(0.014)
        fangs.append(
            authoring.tapered_tube(
                f"CinderFangUpper{index}",
                [Vector((_s(offset), base_y, _h((0.0, 0.0, 1.958)).z)),
                 Vector((_s(offset) * 0.96, base_y + _s(0.012),
                         _h((0.0, 0.0, 1.958 - length * 0.55)).z)),
                 Vector((_s(offset) * 0.90, base_y + _s(0.022),
                         _h((0.0, 0.0, 1.958 - length)).z))],
                [_s(radius), _s(radius) * 0.66, _s(0.002)], 6, bone, wobble=0.05,
                salt=71.0 + index,
            )
        )
    lower_teeth = ((0.042, 0.050, 0.010), (-0.042, 0.050, 0.010), (0.013, 0.026, 0.007))
    for index, (offset, length, radius) in enumerate(lower_teeth):
        base_y = maw_front + _s(0.014)
        fangs.append(
            authoring.tapered_tube(
                f"CinderFangLower{index}",
                [Vector((_s(offset), base_y, _h((0.0, 0.0, 1.916)).z)),
                 Vector((_s(offset) * 0.96, base_y + _s(0.010),
                         _h((0.0, 0.0, 1.916 + length * 0.55)).z)),
                 Vector((_s(offset) * 0.90, base_y + _s(0.018),
                         _h((0.0, 0.0, 1.916 + length)).z))],
                [_s(radius), _s(radius) * 0.64, _s(0.002)], 6, bone, wobble=0.05,
                salt=81.0 + index,
            )
        )

    # Horns leave the temporal plates going out and back over the shoulders,
    # plus a short brow pair framing the sockets. Nothing points straight up:
    # a vertical cone on the crown is an ear.
    horns = []
    horn_specs = (
        ("main_l", _h((0.086, 0.006, 2.024)), Vector((0.70, -0.22, 0.68)), _s(0.42), _s(0.056), 1.30),
        ("main_r", _h((-0.086, 0.006, 2.024)), Vector((-0.70, -0.22, 0.68)), _s(0.42), _s(0.056), 1.30),
    )
    for name, base, direction, length, radius, curve in horn_specs:
        horns.append(_horn(name, horn, base, direction, length, radius, curve, 93.0 + length))

    # --- ash crust ---------------------------------------------------------
    ash_crust = authoring.metaball_mesh(
        "CinderAsh",
        lambda mb: (
            # Ash settles on every high, exposed surface. It is a crust, not a
            # pad: flat shells that follow the body, broken up afterwards so
            # the silhouette never reads as a row of grey balls.
            authoring.metaball_ellipsoid(mb, (0.190, 0.004, 1.716), (0.086, 0.078, 0.028)),
            authoring.metaball_ellipsoid(mb, (-0.190, 0.004, 1.716), (0.086, 0.078, 0.028)),
            authoring.metaball_ellipsoid(mb, (0.0, -0.062, 1.664), (0.140, 0.050, 0.116)),
            authoring.metaball_ellipsoid(mb, (0.0, -0.028, 1.412), (0.104, 0.042, 0.078)),
            authoring.metaball_ellipsoid(mb, (0.0, 0.070, 2.074), (0.082, 0.074, 0.020)),
            authoring.metaball_ellipsoid(mb, (0.290, 0.044, 1.146), (0.044, 0.042, 0.086)),
            authoring.metaball_ellipsoid(mb, (-0.290, 0.044, 1.146), (0.044, 0.042, 0.086)),
            authoring.metaball_ellipsoid(mb, (0.146, 0.040, 0.436), (0.052, 0.044, 0.064)),
            authoring.metaball_ellipsoid(mb, (-0.146, 0.040, 0.436), (0.052, 0.044, 0.064)),
        ),
        0.010,
        0.62,
        0.5,
        ash,
    )
    authoring.displace_radial(ash_crust, 2, 0.004, 38.0, 0.4, 2.2)
    authoring.crumple(ash_crust, 0.005, 33.0, 3.3)

    # Heat still showing through the back and the throat, so the glow is not a
    # single red smear on the chest.
    seams = []
    for index, (z, length) in enumerate(((1.238, 0.058), (1.352, 0.070), (1.470, 0.082),
                                          (1.594, 0.074), (1.706, 0.058))):
        seams.append((
            authoring.tapered_tube(
                f"CinderBackSeam{index}",
                [Vector((0.0, -0.132, z)), Vector((0.0, -0.136, z + length * 0.5)),
                 Vector((0.0, -0.130, z + length))],
                [0.015, 0.011, 0.003], 6, ember, wobble=0.16, salt=131.0 + index,
            ),
            "spine_01" if z < 1.38 else "spine_02",
        ))
    seams.append((
        authoring.tapered_tube(
            "CinderThroatGlow",
            [Vector((0.0, 0.044, 1.776)), Vector((0.0, 0.070, 1.846)), Vector((0.0, 0.086, 1.906))],
            [0.015, 0.011, 0.004], 6, ember, wobble=0.14, salt=137.0,
        ),
        "neck_01",
    ))

    # --- claws -------------------------------------------------------------
    claws = []
    for side in ("l", "r"):
        for index, tip in enumerate(FINGER_TIPS[side]):
            direction = FINGER_DIRECTIONS[index].copy()
            if side == "r":
                direction.x = -direction.x
            claws.append((
                authoring.claw_set(
                    f"CinderClaw_{side}{index}", bone, tip, direction,
                    0.0, 1, 0.086, 0.0175, 0.52, 101.0 + index, down=0.10,
                ),
                f"finger_{side}_{index + 1}",
            ))
    toe_claws = []
    for side in ("l", "r"):
        for index, tip in enumerate(TOE_TIPS[side]):
            toe_claws.append((
                authoring.claw_set(
                    f"CinderToe_{side}{index}", bone, tip, Vector((0.0, 1.0, -0.06)),
                    0.0, 1, 0.062, 0.0140, 0.30, 107.0 + index, down=0.05,
                ),
                f"toe_{side}",
            ))

    # --- tail --------------------------------------------------------------
    tail_path = [Vector((0.0, -0.086, 1.070)), Vector((0.0, -0.232, 1.004)),
                 Vector((0.0, -0.352, 0.898)), Vector((0.0, -0.442, 0.766))]
    tail = authoring.tapered_tube("CinderTail", tail_path, [0.044, 0.032, 0.021, 0.009], 7,
                                  char, wobble=0.14, salt=111.0)
    tail_barb = authoring.tapered_tube(
        "CinderTailBarb",
        [Vector((0.0, -0.446, 0.762)), Vector((0.0, -0.484, 0.700)), Vector((0.0, -0.502, 0.626))],
        [0.024, 0.014, 0.003], 6, bone, wobble=0.06, salt=113.0,
    )

    # --- burnt tatters and hide straps -------------------------------------
    # Separate hanging strips, not a lathe skirt: a shell reads as a rigid box.
    tatters = []
    rng_salt = 141.0
    for index in range(6):
        angle = -1.10 + index * 0.44
        top = Vector((math.sin(angle) * 0.196, math.cos(angle) * 0.176 - 0.010, 1.116))
        bottom = top + Vector((math.sin(angle) * 0.070, math.cos(angle) * 0.060,
                               -0.22 - 0.20 * ((index * 7) % 5) / 4.0))
        tatters.append(
            authoring.open_tube(
                f"CinderTatter{index}",
                [top, (top + bottom) * 0.5, bottom],
                [0.034, 0.040, 0.026],
                8,
                cloth,
                wobble=0.20,
                salt=rng_salt + index,
                fringe=0.42,
                thickness=0.008,
            )
        )
        authoring.crumple(tatters[-1], 0.014, 26.0, rng_salt + index)
    straps = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        straps.append(
            authoring.tapered_tube(
                f"CinderStrap_{side}",
                [Vector((sx * 0.156, 0.048, 1.746)), Vector((sx * 0.086, 0.116, 1.616)),
                 Vector((-sx * 0.020, 0.130, 1.472)), Vector((-sx * 0.122, 0.098, 1.338))],
                [0.023, 0.021, 0.019, 0.016], 6, leather, wobble=0.16, salt=121.0 + sx,
            )
        )

    # --- weights -----------------------------------------------------------
    authoring.assign_envelope_weights(body, {
        "pelvis": (0.235, 1.0), "spine_01": (0.215, 1.0), "spine_02": (0.215, 1.0),
        "chest": (0.255, 1.0), "neck_01": (0.135, 1.0), "neck_02": (0.105, 1.0),
        "head": (0.155, 1.0),
        "clavicle_l": (0.155, 0.6), "clavicle_r": (0.155, 0.6),
        "upper_arm_l": (0.125, 1.0), "upper_arm_r": (0.125, 1.0),
        "lower_arm_l": (0.115, 1.0), "lower_arm_r": (0.115, 1.0),
        "hand_l": (0.075, 0.9), "hand_r": (0.075, 0.9),
        # Digits get their own envelopes: a claw bound to the palm slides off
        # the finger it belongs to the moment the hand curls.
        "finger_l_1": (0.030, 1.3), "finger_l_2": (0.030, 1.3), "finger_l_3": (0.030, 1.3),
        "finger_r_1": (0.030, 1.3), "finger_r_2": (0.030, 1.3), "finger_r_3": (0.030, 1.3),
        "thigh_l": (0.155, 1.0), "thigh_r": (0.155, 1.0),
        "shin_l": (0.115, 1.0), "shin_r": (0.115, 1.0),
        "foot_l": (0.090, 0.9), "foot_r": (0.090, 0.9),
        "toe_l": (0.040, 1.2), "toe_r": (0.040, 1.2),
    }, 3)
    # Each rib belongs to the torso segment it grows out of, never to an arm.
    for index, rib in enumerate(ribs):
        bone_name = ("chest", "chest", "spine_02", "spine_01")[index % 4]
        authoring.assign_envelope_weights(
            rib, {bone_name: (0.32, 1.0), "spine_02": (0.24, 0.5), "chest": (0.24, 0.5)}, 2
        )
    authoring.rigid_weight(chest_cavity, "spine_02")
    authoring.rigid_weight(heart, "spine_02")
    for flame in flames:
        authoring.rigid_weight(flame, "spine_02")
    for seam, bone_name in seams:
        authoring.rigid_weight(seam, bone_name)
    for index, spike in enumerate(spine_spikes):
        t = index / 7.0
        bone_name = "spine_01" if t < 0.34 else ("spine_02" if t < 0.72 else "chest")
        authoring.rigid_weight(spike, bone_name)
    authoring.assign_envelope_weights(skull, {"head": (0.185, 1.2), "neck_02": (0.110, 0.4)}, 2)
    authoring.rigid_weight(jaw, "jaw")
    authoring.rigid_weight(tongue_void, "head")
    authoring.rigid_weight(skull_split, "head")
    for part in [*sockets, *eyes]:
        authoring.rigid_weight(part, "head")
    for part in fangs[4:]:
        authoring.rigid_weight(part, "jaw")
    for part in fangs[:4]:
        authoring.rigid_weight(part, "head")
    for index, horn in enumerate(horns):
        authoring.rigid_weight(horn, "crown_l" if index % 2 == 0 else "crown_r")
    authoring.assign_envelope_weights(ash_crust, {
        "chest": (0.255, 1.0), "spine_02": (0.235, 1.0), "clavicle_l": (0.165, 0.7),
        "clavicle_r": (0.165, 0.7), "head": (0.135, 0.8),
        "lower_arm_l": (0.095, 0.7), "lower_arm_r": (0.095, 0.7),
        "shin_l": (0.090, 0.6), "shin_r": (0.090, 0.6),
    }, 2)
    for part, bone_name in [*claws, *toe_claws]:
        authoring.rigid_weight(part, bone_name)
    authoring.assign_envelope_weights(tail, {
        "tail_01": (0.115, 1.0), "tail_02": (0.095, 1.0), "pelvis": (0.120, 0.6),
    }, 2)
    authoring.rigid_weight(tail_barb, "tail_03")
    for strip in tatters:
        authoring.assign_envelope_weights(strip, {
            "pelvis": (0.190, 1.0), "thigh_l": (0.150, 1.0), "thigh_r": (0.150, 1.0),
            "spine_01": (0.130, 0.6),
        }, 2)
    for strap in straps:
        authoring.assign_envelope_weights(
            strap, {"chest": (0.240, 1.0), "spine_02": (0.215, 0.8), "spine_01": (0.180, 0.5)}, 2
        )

    parts = [*ribs, chest_cavity, heart, *flames, *[seam for seam, _bone in seams],
             *spine_spikes, skull, jaw, tongue_void, skull_split, *sockets, *eyes,
             *fangs, *horns, ash_crust,
             *[part for part, _bone in claws], *[part for part, _bone in toe_claws],
             tail, tail_barb, *tatters, *straps]
    mesh = authoring.join_parts(body, parts, "CinderMesh")
    return mesh


# ---------------------------------------------------------------------------
# Clips
#
# The pack state machine multiplies its own clock onto these. Attack carries
# its strike at 0.38 s (WINDUP 0.30 + the STRIKE frame at 0.08) and the shoot
# clip releases at 0.30 s, which is where `enemy.gd` spawns the arrow.


def cinder_base() -> dict:
    return {
        "pelvis_offset": Vector((0.0, 0.0, 0.0)),
        "pelvis_pitch": 0.0, "pelvis_roll": 0.0, "pelvis_yaw": 0.0,
        "spine1": (0.0, 0.0, 0.0), "spine2": (0.0, 0.0, 0.0), "chest_pose": (0.0, 0.0, 0.0),
        "neck1": (0.0, 0.0, 0.0), "neck2": (0.0, 0.0, 0.0), "head_pose": (0.0, 0.0, 0.0),
        "jaw_open": 0.0,
        "arm": {"l": (0.0, 0.0, 0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0, 0.0, 0.0)},
        "finger": {"l": 0.0, "r": 0.0},
        "crown": {"l": (0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0)},
        "tail": (0.0, 0.0, 0.0),
        "feet": {"l": (0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0)},
        "solve_feet": True,
    }


def cinder_idle(t: float) -> dict:
    """A starving animal breathing: rasping chest, twitching fingers, head roll."""
    duration = styles.MOBS[MOB]["clips"]["idle"]["duration"]
    phase = (t / duration) % 1.0
    breath = math.sin(phase * math.tau)
    slow = math.sin(phase * math.tau * 0.5)
    twitch = math.sin(phase * math.tau * 3.0) ** 5
    values = cinder_base()
    values.update({
        "pelvis_offset": Vector((0.004 * slow, 0.0, 0.012 * breath - 0.004)),
        "pelvis_pitch": 0.02 * breath,
        "pelvis_roll": 0.018 * slow,
        "pelvis_yaw": 0.016 * slow,
        "spine1": (0.030 * breath, 0.012 * slow, 0.0),
        "spine2": (0.034 * breath, 0.016 * slow, 0.0),
        "chest_pose": (0.038 * breath, 0.020 * slow, 0.0),
        "neck1": (-0.030 * breath, 0.024 * slow, 0.0),
        "neck2": (-0.020 * breath, 0.018 * slow, 0.0),
        "head_pose": (0.026 * math.sin(phase * math.tau + 0.7), 0.10 * slow, 0.05 * slow),
        # The jaw never fully closes: something is always showing teeth.
        "jaw_open": 0.12 + 0.06 * max(0.0, math.sin(phase * math.tau * 1.5)),
        "arm": {
            "l": (0.10 + 0.05 * breath, 0.04 * slow, 0.05, 0.16, 0.06),
            "r": (0.08 - 0.05 * breath, -0.04 * slow, 0.05, 0.15, 0.06),
        },
        "finger": {"l": 0.35 + 0.35 * twitch, "r": 0.32 - 0.30 * twitch},
        "crown": {"l": (0.03 * breath, 0.03 * slow, 0.0), "r": (0.03 * breath, -0.03 * slow, 0.0)},
        "tail": (-0.22 + 0.20 * slow, -0.16 + 0.12 * breath, -0.10),
    })
    return values


def cinder_locomotion(t: float, key: str) -> dict:
    spec = styles.MOBS[MOB]
    duration = spec["clips"][key]["duration"]
    stride = spec["stride"][key]
    duty = spec["duty"][key]
    clearance = spec["foot_lift"][key]
    phase = (t / duration) % 1.0
    step = math.sin(phase * math.tau)
    double = math.cos(phase * math.tau * 2.0)
    fast = 1.0 if key == "walk" else 1.5
    values = cinder_base()
    # It runs like something with too much arm: shoulders low, head leading.
    values.update({
        "pelvis_offset": Vector((0.010 * step, 0.0, (0.026 * double - 0.018) * fast)),
        "pelvis_pitch": 0.10 + 0.02 * fast,
        "pelvis_roll": 0.070 * step * fast,
        "pelvis_yaw": 0.060 * step * fast,
        "spine1": (-0.030, -0.040 * step, -0.020 * step),
        "spine2": (-0.040, -0.050 * step, -0.030 * step),
        "chest_pose": (-0.050, -0.060 * step * fast, 0.030 * step),
        "neck1": (0.045, 0.030 * step, 0.0),
        "neck2": (0.035, 0.020 * step, 0.0),
        "head_pose": (-0.030, 0.040 * step, 0.0),
        "jaw_open": 0.24 + 0.10 * max(0.0, step),
        "arm": {
            "l": (0.22 + 0.55 * step * fast, 0.06, 0.09, 0.42, 0.10),
            "r": (0.22 - 0.55 * step * fast, -0.06, 0.09, 0.40, 0.10),
        },
        "finger": {"l": 0.62, "r": 0.62},
        "crown": {"l": (0.05 * double, 0.04 * step, 0.0), "r": (0.05 * double, -0.04 * step, 0.0)},
        "tail": (-0.30 - 0.16 * double, -0.20 + 0.16 * step * fast, -0.16),
    })
    for side, offset in (("l", 0.0), ("r", 0.5)):
        y, lift, pitch = authoring.foot_target(phase, offset, duty, stride, clearance)
        values["feet"][side] = (y, lift, pitch)
    return values


def cinder_attack(t: float) -> dict:
    """Rear back, then rake down with both hands at 0.38 s. The jaw screams."""
    rear = authoring.keyed(t, [(0.0, 0.0), (0.14, 0.55), (0.28, 1.0), (0.34, 0.92),
                               (0.38, 0.10), (0.52, 0.0), (0.80, 0.0)])
    slam = authoring.keyed(t, [(0.0, 0.0), (0.30, 0.0), (0.345, 0.35), (0.38, 1.0),
                               (0.45, 0.86), (0.58, 0.34), (0.72, 0.08), (0.80, 0.0)])
    lunge = authoring.keyed(t, [(0.0, 0.0), (0.26, -0.07), (0.36, 0.10), (0.38, 0.20),
                                (0.52, 0.12), (0.70, 0.03), (0.80, 0.0)])
    values = cinder_base()
    values.update({
        "pelvis_offset": Vector((0.0, -0.06 * rear + 0.15 * slam, -0.05 * rear - 0.06 * slam)),
        "pelvis_pitch": -0.10 * rear + 0.18 * slam,
        "pelvis_yaw": 0.07 * rear - 0.08 * slam,
        "spine1": (lunge * 0.5, 0.04 * rear, 0.0),
        "spine2": (lunge * 0.6, 0.05 * rear, 0.0),
        "chest_pose": (lunge * 0.7 - 0.10 * rear, 0.06 * rear, 0.0),
        "neck1": (-0.20 * rear + 0.14 * slam, 0.0, 0.0),
        "neck2": (-0.14 * rear + 0.10 * slam, 0.0, 0.0),
        "head_pose": (-0.26 * rear + 0.24 * slam, 0.0, 0.07 * slam),
        "jaw_open": 0.24 + 0.72 * rear * (1.0 - 0.88 * slam),
        "arm": {
            "l": (-1.45 * rear + 1.95 * slam, 0.10, 0.16 - 0.14 * rear, 0.62 * rear - 0.44 * slam, 0.12),
            "r": (-1.50 * rear + 1.90 * slam, -0.10, 0.16 - 0.14 * rear, 0.58 * rear - 0.42 * slam, 0.12),
        },
        "finger": {"l": 1.15 - 0.55 * slam, "r": 1.10 - 0.52 * slam},
        "crown": {"l": (-0.18 * rear + 0.24 * slam, 0.0, 0.0), "r": (-0.18 * rear + 0.24 * slam, 0.0, 0.0)},
        "tail": (-0.34 + 0.30 * slam, -0.26 + 0.26 * rear, -0.18 + 0.14 * slam),
    })
    for side, offset in (("l", 0.52), ("r", 0.44)):
        values["feet"][side] = (0.06 * slam, 0.015 * rear, 0.0)
    return values


def cinder_shoot(t: float) -> dict:
    """Draw and loose at 0.30 s, then reach for the next arrow."""
    draw = authoring.keyed(t, [(0.0, 0.0), (0.10, 0.35), (0.22, 0.85), (0.30, 1.0),
                               (0.345, 0.25), (0.44, 0.0), (0.55, 0.0)])
    reach = authoring.keyed(t, [(0.0, 0.0), (0.16, 0.55), (0.30, 0.85), (0.40, 0.30),
                                (0.55, 0.0)])
    values = cinder_base()
    values.update({
        "pelvis_offset": Vector((-0.02 * draw, 0.0, -0.02 * draw)),
        "pelvis_pitch": 0.06 + 0.03 * draw,
        "pelvis_yaw": -0.24 * draw,
        "spine1": (-0.02, 0.10 * draw, 0.0),
        "spine2": (-0.03, 0.12 * draw, 0.0),
        "chest_pose": (-0.04, 0.14 * draw, 0.0),
        "neck1": (0.03, -0.10 * draw, 0.0),
        "neck2": (0.02, -0.06 * draw, 0.0),
        "head_pose": (0.02, -0.12 * draw, 0.04 * draw),
        "jaw_open": 0.14 + 0.10 * reach,
        "arm": {
            # Left arm holds the bow out; right hand draws to the jaw.
            "l": (-1.32 + 0.10 * draw, 0.20, 0.32, -0.20 + 0.12 * draw, 0.14),
            "r": (-0.55 - 0.40 * draw, -0.42, 0.40, 1.05 * draw, 0.10),
        },
        "finger": {"l": 0.75, "r": 0.55 + 0.45 * draw},
        "crown": {"l": (0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0)},
        "tail": (-0.30, -0.22 + 0.10 * draw, -0.14),
    })
    values["feet"]["l"] = (-0.10, 0.0, 0.0)
    values["feet"]["r"] = (0.10, 0.0, 0.0)
    return values


def cinder_hit(t: float) -> dict:
    flinch = authoring.keyed(t, [(0.0, 0.0), (0.10, 1.0), (0.22, 0.55), (0.36, 0.0)])
    values = cinder_base()
    values.update({
        "pelvis_offset": Vector((0.020 * flinch, -0.05 * flinch, -0.03 * flinch)),
        "pelvis_pitch": -0.10 * flinch,
        "pelvis_roll": 0.12 * flinch,
        "spine1": (-0.12 * flinch, 0.05 * flinch, 0.07 * flinch),
        "spine2": (-0.14 * flinch, 0.07 * flinch, 0.09 * flinch),
        "chest_pose": (-0.18 * flinch, 0.09 * flinch, 0.11 * flinch),
        "neck1": (-0.16 * flinch, 0.0, 0.07 * flinch),
        "neck2": (-0.10 * flinch, 0.0, 0.05 * flinch),
        "head_pose": (-0.28 * flinch, -0.10 * flinch, 0.16 * flinch),
        "jaw_open": 0.30 + 0.55 * flinch,
        "arm": {
            "l": (-0.45 * flinch, 0.12 * flinch, 0.34 * flinch, 0.50 * flinch, 0.10),
            "r": (-0.38 * flinch, -0.12 * flinch, 0.32 * flinch, 0.45 * flinch, 0.10),
        },
        "finger": {"l": 0.95, "r": 0.95},
        "crown": {"l": (-0.18 * flinch, 0.0, 0.10 * flinch),
                  "r": (-0.18 * flinch, 0.0, -0.10 * flinch)},
        "tail": (-0.34 - 0.24 * flinch, -0.20, -0.12),
    })
    return values


def cinder_death(t: float) -> dict:
    duration = styles.MOBS[MOB]["clips"]["death"]["duration"]
    p = max(0.0, min(1.0, t / duration))
    give = authoring.smoothstep(0.0, 0.30, p)
    topple = authoring.smoothstep(0.16, 0.78, p)
    settle = authoring.smoothstep(0.62, 1.0, p)
    values = cinder_base()
    values["solve_feet"] = False
    values.update({
        "pelvis_offset": Vector((0.07 * topple, 0.12 * topple, -0.34 * give - 0.52 * topple)),
        "pelvis_pitch": 0.18 * give + 1.00 * topple,
        "pelvis_roll": 0.12 * give + 0.38 * topple,
        "pelvis_yaw": 0.06 * topple,
        "spine1": (0.12 * give + 0.16 * topple, 0.0, 0.0),
        "spine2": (0.14 * give + 0.20 * topple, 0.0, 0.0),
        "chest_pose": (0.14 * give + 0.18 * topple, 0.0, 0.0),
        "neck1": (-0.24 * give - 0.12 * topple, 0.0, 0.0),
        "neck2": (-0.14 * give - 0.08 * topple, 0.0, 0.0),
        "head_pose": (-0.30 * give - 0.18 * topple, 0.14 * topple, 0.12 * topple),
        "jaw_open": 0.62 * (1.0 - topple) + 0.16,
        "arm": {
            "l": (0.34 * give + 0.40 * topple, 0.12 * topple, 0.50 * give, 0.34 * give, 0.10),
            "r": (0.28 * give + 0.34 * topple, -0.12 * topple, 0.46 * give, 0.30 * give, 0.10),
        },
        "finger": {"l": 0.55, "r": 0.65},
        "crown": {"l": (-0.22 * give - 0.12 * settle, 0.0, 0.0),
                  "r": (-0.22 * give - 0.12 * settle, 0.0, 0.0)},
        "tail": (-0.40 - 0.20 * topple, -0.24, -0.10),
    })
    values["leg_fold"] = {
        "l": (1.05 * give, -0.80 * give, 0.48 * give, 0.12 * topple),
        "r": (0.96 * give, -0.74 * give, 0.44 * give, -0.14 * topple),
    }
    return values


CLIP_FUNCTIONS = {
    "idle": cinder_idle,
    "walk": lambda t: cinder_locomotion(t, "walk"),
    "run": lambda t: cinder_locomotion(t, "run"),
    "attack": cinder_attack,
    "shoot": cinder_shoot,
    "hit": cinder_hit,
    "death": cinder_death,
}

CLIP_ORDER = ("idle", "walk", "run", "attack", "shoot", "hit", "death")


# ---------------------------------------------------------------------------
# Export


def build_actions() -> list[bpy.types.Action]:
    authoring.RIG.animation_data_create()
    authoring.RIG.animation_data.use_nla = False
    actions = []
    for key in CLIP_ORDER:
        actions.append(
            authoring.bake_clip(MOB, key, CLIP_FUNCTIONS[key], ground=(key == "death"))
        )
    return actions


def write_metadata(output: Path) -> dict:
    document, _raw = authoring.glb_document(output)
    animations = {animation["name"]: animation for animation in document.get("animations", [])}
    durations = {
        name: max(document["accessors"][sampler["input"]]["max"][0] for sampler in animation["samplers"])
        for name, animation in animations.items()
    }
    skin = document["skins"][0]
    bones = [document["nodes"][index].get("name", "") for index in skin["joints"]]
    position_accessors = [
        primitive["attributes"]["POSITION"]
        for mesh in document["meshes"]
        for primitive in mesh["primitives"]
    ]
    bounds_min = [min(document["accessors"][index]["min"][axis] for index in position_accessors) for axis in range(3)]
    bounds_max = [max(document["accessors"][index]["max"][axis] for index in position_accessors) for axis in range(3)]
    materials = [material.get("name", "") for material in document.get("materials", [])]
    images = [image.get("mimeType", "") for image in document.get("images", [])]
    triangles = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if "indices" in primitive:
                triangles += document["accessors"][primitive["indices"]]["count"] // 3
    root_index = next((index for index, node in enumerate(document["nodes"]) if node.get("name") == "root"), None)
    root_translation_channels = [
        channel
        for animation in document.get("animations", [])
        for channel in animation["channels"]
        if channel["target"].get("node") == root_index and channel["target"].get("path") == "translation"
    ]
    # A sampled export writes a translation track for every joint. What matters
    # is whether the values move: a constant track is harmless, a varying one
    # would double the CharacterBody's own motion.
    root_translation_drift = 0.0
    for animation in document.get("animations", []):
        for channel in animation["channels"]:
            if channel["target"].get("node") != root_index:
                continue
            if channel["target"].get("path") != "translation":
                continue
            accessor = document["accessors"][animation["samplers"][channel["sampler"]]["output"]]
            low = accessor.get("min")
            high = accessor.get("max")
            if low and high:
                root_translation_drift = max(
                    root_translation_drift, max(abs(high[axis] - low[axis]) for axis in range(3))
                )
    spec = styles.MOBS[MOB]
    clips = {}
    for key in CLIP_ORDER:
        name = styles.clip_name(MOB, key)
        entry = {
            "name": name,
            "duration": durations.get(name),
            "loop": bool(spec["clips"][key]["loop"]),
        }
        if key in ("walk", "run"):
            entry["stride"] = spec["stride"][key]
            entry["duty"] = spec["duty"][key]
        if not spec["clips"][key]["loop"] and "impact" in spec["clips"][key]:
            entry["impact"] = spec["clips"][key]["impact"]
        clips[key] = entry
    metadata = {
        "asset": output.name,
        "mob": MOB,
        "display": spec["display"],
        "summary": spec["summary"],
        "skeleton": "CinderArmature/Skeleton3D",
        "bone_count": len(bones),
        "bone_names": bones,
        "forward": [0, 0, -1],
        "up": [0, 1, 0],
        "unit": "metres",
        "rest_bounds_min": bounds_min,
        "rest_bounds_max": bounds_max,
        "mesh_triangles": triangles,
        "materials": materials,
        "embedded_images": len(images),
        "clips": clips,
        "animations": durations,
        "authoring_fps": FPS,
        "root_translation_channels": len(root_translation_channels),
        "root_translation_drift": round(root_translation_drift, 6),
        "source": (
            "Original procedural work authored by tools/prepare_cinder_devil.py from "
            "tools/cinder_devil_surface.py and tools/cinder_devil_styles.py on the shared "
            "tools/prepare_forest_mobs.py machinery; no third-party model, texture or motion."
        ),
        "reproducer": "python tools/build_cinder_devil.py",
    }
    path = output.with_suffix(".json")
    path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("CINDER_METADATA", path)
    return metadata


def main() -> None:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    output = Path(argv[0]).resolve() if argv else styles.asset_path(MOB)
    source = styles.mob_dir(MOB)
    source.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)

    # Rebind the shared stage onto the cinder recipe. Every helper in
    # prepare_forest_mobs resolves `styles`/`surfaces`/`SEED`/`FPS` from its own
    # module globals, so this is a complete cutover, not a partial override.
    authoring.styles = styles
    authoring.surfaces = surfaces
    authoring.SEED = SEED
    authoring.FPS = FPS
    authoring.JOINTS = dict(CINDER_JOINTS)
    authoring.PARENTS = dict(CINDER_PARENTS)
    authoring.DEFORM = list(CINDER_JOINTS.keys())
    authoring.ASSEMBLERS[MOB] = (CINDER_JOINTS, CINDER_PARENTS, assemble_cinder_devil)
    authoring.CLIP_FUNCTIONS[MOB] = dict(CLIP_FUNCTIONS)
    authoring.ARM_CHAINS[MOB] = (
        "clavicle_{side}", "upper_arm_{side}", "lower_arm_{side}", "hand_{side}"
    )

    authoring.reset_scene()
    print("CINDER_BEGIN", MOB, source, output)
    authoring.RIG = authoring.build_armature()
    authoring.RIG.name = "CinderArmature"
    authoring.RIG.data.name = "CinderArmature"
    mesh = assemble_cinder_devil()
    authoring.MESH = mesh
    authoring.skin_to_rig(mesh, authoring.RIG)
    triangles = sum(len(polygon.vertices) - 2 for polygon in mesh.data.polygons)
    print("CINDER_TRIS", triangles, "bones", len(authoring.DEFORM))
    authoring.unwrap_per_material(mesh)
    authoring.bake_materials(mesh, MOB, source / "textures")
    actions = build_actions()
    authoring.setup_nla_and_export(actions, output)
    metadata = write_metadata(output)
    authoring.render_captures(MOB, source, actions, metadata)
    bpy.ops.wm.save_as_mainfile(filepath=str(source / f"ironwood_{MOB}_source.blend"))
    print("CINDER_DONE", json.dumps({
        "mob": MOB,
        "triangles": metadata["mesh_triangles"],
        "bones": metadata["bone_count"],
        "images": metadata["embedded_images"],
        "clips": {key: value["duration"] for key, value in metadata["clips"].items()},
    }, indent=2))


if __name__ == "__main__":
    main()
