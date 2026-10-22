"""Author the default grey Ironwood wolf and export a skinned, animated GLB.

This is the wolf counterpart to tools/prepare_character.py. It builds an
original continuous wolf mesh, a UV-baked grey coat, a quadruped deformation
skeleton and the gameplay clips used by scripts/wolf_visual.gd.

Usage (Blender 5.1+):
    blender --background --python-exit-code 1 --python tools/prepare_wolf.py -- \
        .runtime/character-source/wolf assets/characters/ironwood_wolf.glb

Everything is authored in metres, Blender Z-up, wolf facing +Y. glTF export uses
Y-up, so +Y Blender becomes -Z in Godot, matching gameplay forward.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys

import numpy as np
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
FPS = 60
SEED = 1701

# Filled by build_geometry / build_armature.
FUR_OBJECT: bpy.types.Object | None = None
MESH_OBJECT: bpy.types.Object | None = None
RIG: bpy.types.Object | None = None
DETAIL_OBJECTS: list[bpy.types.Object] = []

# Rest joints, armature space. X is left(+)/right(-), Y forward, Z up.
# The foreleg has a real elbow bend so planted-paw IK has horizontal reach.
JOINTS = {
    "pelvis": ((0.0, -0.44, 0.77), (0.0, -0.22, 0.78)),
    "spine_01": ((0.0, -0.22, 0.78), (0.0, 0.02, 0.79)),
    "spine_02": ((0.0, 0.02, 0.79), (0.0, 0.24, 0.81)),
    "chest": ((0.0, 0.24, 0.81), (0.0, 0.38, 0.87)),
    "neck_01": ((0.0, 0.38, 0.87), (0.0, 0.52, 0.96)),
    "neck_02": ((0.0, 0.52, 0.96), (0.0, 0.64, 1.00)),
    "head": ((0.0, 0.64, 1.00), (0.0, 0.83, 0.95)),
    "jaw": ((0.0, 0.80, 0.905), (0.0, 1.01, 0.885)),
    "tail_01": ((0.0, -0.60, 0.80), (0.0, -0.74, 0.74)),
    "tail_02": ((0.0, -0.74, 0.74), (0.0, -0.88, 0.67)),
    "tail_03": ((0.0, -0.88, 0.67), (0.0, -1.02, 0.61)),
    "tail_04": ((0.0, -1.02, 0.61), (0.0, -1.10, 0.57)),
}

for side, sx in (("l", 1.0), ("r", -1.0)):
    JOINTS.update(
        {
            f"scapula_{side}": ((sx * 0.10, 0.26, 0.96), (sx * 0.18, 0.29, 0.83)),
            f"upper_fore_{side}": ((sx * 0.18, 0.29, 0.83), (sx * 0.18, 0.18, 0.45)),
            f"lower_fore_{side}": ((sx * 0.18, 0.18, 0.45), (sx * 0.18, 0.32, 0.15)),
            f"carpus_{side}": ((sx * 0.18, 0.32, 0.15), (sx * 0.18, 0.36, 0.09)),
            f"front_paw_{side}": ((sx * 0.18, 0.36, 0.09), (sx * 0.18, 0.43, 0.045)),
            f"front_toes_{side}": ((sx * 0.18, 0.43, 0.045), (sx * 0.18, 0.50, 0.040)),
            f"thigh_{side}": ((sx * 0.17, -0.42, 0.80), (sx * 0.18, -0.30, 0.50)),
            f"shin_{side}": ((sx * 0.18, -0.30, 0.50), (sx * 0.18, -0.44, 0.18)),
            f"hock_{side}": ((sx * 0.18, -0.44, 0.18), (sx * 0.18, -0.37, 0.09)),
            f"hind_paw_{side}": ((sx * 0.18, -0.37, 0.09), (sx * 0.18, -0.30, 0.045)),
            f"hind_toes_{side}": ((sx * 0.18, -0.30, 0.045), (sx * 0.18, -0.23, 0.040)),
            f"ear_{side}": ((sx * 0.062, 0.655, 1.03), (sx * 0.095, 0.635, 1.16)),
        }
    )

BONE_PARENTS = {
    "pelvis": ("root", False),
    "spine_01": ("pelvis", True),
    "spine_02": ("spine_01", True),
    "chest": ("spine_02", True),
    "neck_01": ("chest", False),
    "neck_02": ("neck_01", True),
    "head": ("neck_02", True),
    "jaw": ("head", False),
    "tail_01": ("pelvis", False),
    "tail_02": ("tail_01", True),
    "tail_03": ("tail_02", True),
    "tail_04": ("tail_03", True),
}
for side in ("l", "r"):
    BONE_PARENTS.update(
        {
            f"scapula_{side}": ("chest", False),
            f"upper_fore_{side}": (f"scapula_{side}", True),
            f"lower_fore_{side}": (f"upper_fore_{side}", True),
            f"carpus_{side}": (f"lower_fore_{side}", True),
            f"front_paw_{side}": (f"carpus_{side}", True),
            f"front_toes_{side}": (f"front_paw_{side}", True),
            f"thigh_{side}": ("pelvis", False),
            f"shin_{side}": (f"thigh_{side}", True),
            f"hock_{side}": (f"shin_{side}", True),
            f"hind_paw_{side}": (f"hock_{side}", True),
            f"hind_toes_{side}": (f"hind_paw_{side}", True),
            f"ear_{side}": ("head", False),
        }
    )

DEFORM_BONES = list(JOINTS.keys())
LEG_CHAINS = {
    "fore_l": ("upper_fore_l", "lower_fore_l", "carpus_l", "front_paw_l", "front_toes_l"),
    "fore_r": ("upper_fore_r", "lower_fore_r", "carpus_r", "front_paw_r", "front_toes_r"),
    "hind_l": ("thigh_l", "shin_l", "hock_l", "hind_paw_l", "hind_toes_l"),
    "hind_r": ("thigh_r", "shin_r", "hock_r", "hind_paw_r", "hind_toes_r"),
}
PAW_REST = {
    "fore_l": Vector((0.18, 0.36, 0.09)),
    "fore_r": Vector((-0.18, 0.36, 0.09)),
    "hind_l": Vector((0.18, -0.37, 0.09)),
    "hind_r": Vector((-0.18, -0.37, 0.09)),
}

# Per-bone skin envelope (radius, priority). Priority keeps limb vertices from
# being stolen by the broad torso envelopes; radii are metres.
SKIN_BONES = {
    "pelvis": (0.30, 0.85),
    "spine_01": (0.30, 0.90),
    "spine_02": (0.31, 0.90),
    "chest": (0.33, 0.90),
    "neck_01": (0.19, 1.05),
    "neck_02": (0.16, 1.05),
    "head": (0.20, 1.05),
    "tail_01": (0.115, 1.0),
    "tail_02": (0.105, 1.0),
    "tail_03": (0.095, 1.0),
    "tail_04": (0.085, 1.0),
}
for side in ("l", "r"):
    SKIN_BONES.update(
        {
            f"scapula_{side}": (0.17, 1.35),
            f"upper_fore_{side}": (0.135, 2.30),
            f"lower_fore_{side}": (0.115, 2.30),
            f"carpus_{side}": (0.100, 2.45),
            f"front_paw_{side}": (0.120, 2.45),
            f"front_toes_{side}": (0.100, 2.45),
            f"thigh_{side}": (0.175, 2.05),
            f"shin_{side}": (0.130, 2.30),
            f"hock_{side}": (0.105, 2.45),
            f"hind_paw_{side}": (0.115, 2.45),
            f"hind_toes_{side}": (0.100, 2.45),
        }
    )


def parse_args() -> tuple[Path, Path]:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []
    if len(argv) >= 2:
        source = Path(argv[0]).resolve()
        output = Path(argv[1]).resolve()
    else:
        source = (ROOT / ".runtime/character-source/wolf").resolve()
        output = (ROOT / "assets/characters/ironwood_wolf.glb").resolve()
    source.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    return source, output


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start = 0
    scene.frame_end = 1
    scene.render.engine = "BLENDER_WORKBENCH"


# ---------------------------------------------------------------------------
# Geometry


def metaball_ellipsoid(mb, centre, half, rotation=None, stiffness=2.0):
    # A single ELLIPSOID at radius 1/stiffness-surface produces a half-extent
    # close to half_*; this factor was measured on the installed Blender build.
    e = mb.elements.new(type="ELLIPSOID")
    e.co = Vector(centre)
    e.radius = 1.0 / 0.5735
    e.size_x, e.size_y, e.size_z = half
    e.stiffness = stiffness
    if rotation is not None:
        e.rotation = rotation
    return e


def metaball_segment(mb, a, b, radius, bulge=1.0):
    a, b = Vector(a), Vector(b)
    direction = b - a
    length = direction.length
    rotation = Vector((0.0, 1.0, 0.0)).rotation_difference(direction.normalized())
    return metaball_ellipsoid(
        mb,
        (a + b) * 0.5,
        (radius, length * 0.5 + radius * 0.35, radius * bulge),
        rotation,
    )


def build_body_mesh():
    mb = bpy.data.metaballs.new("WolfBody")
    mb.resolution = 0.018
    mb.render_resolution = 0.018
    mb.threshold = 0.6
    body = bpy.data.objects.new("WolfFur", mb)
    bpy.context.collection.objects.link(body)

    # Torso: deep ribcage, tucked waist, distinct pelvis.
    metaball_ellipsoid(mb, (0.0, -0.46, 0.78), (0.170, 0.185, 0.190))
    metaball_ellipsoid(mb, (0.0, -0.32, 0.785), (0.180, 0.180, 0.180))
    metaball_ellipsoid(mb, (0.0, -0.14, 0.775), (0.155, 0.175, 0.160))
    metaball_ellipsoid(mb, (0.0, 0.04, 0.775), (0.205, 0.235, 0.225))
    metaball_ellipsoid(mb, (0.0, 0.22, 0.800), (0.205, 0.200, 0.210))
    metaball_ellipsoid(mb, (0.0, 0.27, 0.670), (0.145, 0.165, 0.155))
    metaball_ellipsoid(mb, (0.0, 0.27, 0.905), (0.135, 0.135, 0.105))
    # Neck, throat, head, wedge muzzle, cheeks and brow.
    metaball_ellipsoid(mb, (0.0, 0.38, 0.885), (0.125, 0.145, 0.145))
    metaball_ellipsoid(mb, (0.0, 0.50, 0.955), (0.105, 0.125, 0.120))
    metaball_ellipsoid(mb, (0.0, 0.55, 0.865), (0.075, 0.115, 0.085))
    metaball_ellipsoid(mb, (0.0, 0.64, 1.000), (0.115, 0.130, 0.115))
    metaball_ellipsoid(mb, (0.0, 0.705, 0.995), (0.100, 0.105, 0.100))
    metaball_ellipsoid(mb, (0.0, 0.800, 0.945), (0.067, 0.130, 0.062))
    metaball_ellipsoid(mb, (0.0, 0.905, 0.930), (0.050, 0.095, 0.048))
    metaball_ellipsoid(mb, (0.0, 0.990, 0.922), (0.040, 0.052, 0.038))
    metaball_ellipsoid(mb, (0.0, 0.405, 0.790), (0.140, 0.105, 0.165))
    for sx in (-1.0, 1.0):
        metaball_ellipsoid(mb, (sx * 0.102, 0.655, 0.935), (0.076, 0.086, 0.082))
        metaball_ellipsoid(mb, (sx * 0.074, 0.715, 1.028), (0.036, 0.045, 0.030))
        # shoulder and haunch masses
        metaball_ellipsoid(mb, (sx * 0.155, 0.265, 0.825), (0.098, 0.130, 0.150))
        metaball_ellipsoid(mb, (sx * 0.162, -0.415, 0.790), (0.105, 0.145, 0.170))
        # foreleg chain: shoulder -> elbow (behind) -> wrist -> paw
        metaball_segment(mb, (sx * 0.18, 0.29, 0.83), (sx * 0.18, 0.18, 0.45), 0.055)
        metaball_ellipsoid(mb, (sx * 0.18, 0.18, 0.45), (0.056, 0.060, 0.056))
        metaball_segment(mb, (sx * 0.18, 0.18, 0.45), (sx * 0.18, 0.32, 0.15), 0.045)
        metaball_ellipsoid(mb, (sx * 0.18, 0.32, 0.15), (0.047, 0.052, 0.047))
        metaball_segment(mb, (sx * 0.18, 0.32, 0.15), (sx * 0.18, 0.36, 0.09), 0.040)
        metaball_ellipsoid(mb, (sx * 0.18, 0.385, 0.062), (0.063, 0.102, 0.050))
        for tx in (-0.037, 0.0, 0.037):
            metaball_ellipsoid(mb, (sx * 0.18 + tx, 0.455, 0.042), (0.026, 0.055, 0.032))
        # hind chain: hip -> stifle (forward) -> hock (back) -> paw
        metaball_segment(mb, (sx * 0.17, -0.42, 0.80), (sx * 0.18, -0.30, 0.50), 0.070)
        metaball_ellipsoid(mb, (sx * 0.18, -0.30, 0.50), (0.060, 0.065, 0.060))
        metaball_segment(mb, (sx * 0.18, -0.30, 0.50), (sx * 0.18, -0.44, 0.18), 0.047)
        metaball_ellipsoid(mb, (sx * 0.18, -0.44, 0.18), (0.046, 0.052, 0.050))
        metaball_segment(mb, (sx * 0.18, -0.44, 0.18), (sx * 0.18, -0.37, 0.09), 0.040)
        metaball_ellipsoid(mb, (sx * 0.18, -0.345, 0.062), (0.060, 0.100, 0.050))
        for tx in (-0.037, 0.0, 0.037):
            metaball_ellipsoid(mb, (sx * 0.18 + tx, -0.265, 0.042), (0.025, 0.052, 0.031))

    # Bushy tail.
    tail_points = [
        (0.0, -0.60, 0.80),
        (0.0, -0.74, 0.74),
        (0.0, -0.88, 0.67),
        (0.0, -1.02, 0.61),
        (0.0, -1.10, 0.57),
    ]
    tail_radii = [0.078, 0.078, 0.070, 0.060, 0.042]
    for i in range(len(tail_points) - 1):
        metaball_segment(mb, tail_points[i], tail_points[i + 1], tail_radii[i], 1.12)
    for point, radius in zip(tail_points, tail_radii):
        metaball_ellipsoid(mb, point, (radius, radius * 1.25, radius))

    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.convert(target="MESH")
    body = bpy.context.object
    body.name = "WolfFur"
    body.data.name = "WolfFur"
    bpy.ops.object.shade_smooth()
    decimate = body.modifiers.new("Decimate", "DECIMATE")
    decimate.ratio = 0.38
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    body.data.materials.append(make_fur_material())
    print("WOLF_BODY_TRIS", sum(len(p.vertices) - 2 for p in body.data.polygons))
    return body


def make_material(name: str, colour, roughness: float, metallic: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*colour, 1.0)
    return mat


def make_fur_material():
    # Placeholder until the UV coat painter replaces this material's nodes with
    # the packed albedo texture. Keeping the name stable gives the fur a known
    # material slot in the final joined mesh.
    return make_material("Wolf_Fur", (0.355, 0.340, 0.305), 0.88)


def make_ear(side: str, sx: float):
    width = 0.055
    depth = 0.032
    height = 0.145
    verts = [
        (-width, -depth, 0.0),
        (width, -depth, 0.0),
        (width, depth, 0.0),
        (-width, depth, 0.0),
        (0.0, -depth * 0.25, height),
        (0.0, depth * 0.25, height),
    ]
    faces = [
        (0, 1, 4),
        (3, 5, 2),
        (0, 4, 5, 3),
        (1, 2, 5, 4),
        (0, 3, 2, 1),
    ]
    mesh = bpy.data.meshes.new(f"Ear_{side}")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"Ear_{side}", mesh)
    obj.location = (sx * 0.064, 0.655, 1.035)
    obj.rotation_euler = (math.radians(-8.0), math.radians(sx * -13.0), 0.0)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(bpy.data.materials["Wolf_Fur"])
    return obj


def make_jaw_and_details():
    details = []
    # Lower jaw as a tapered continuous piece; weighted rigidly to the jaw bone.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.0, location=(0.0, 0.905, 0.876))
    jaw = bpy.context.object
    jaw.name = "WolfJaw"
    jaw.scale = (0.058, 0.130, 0.036)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    details.append(jaw)
    # Mouth cavity and tongue.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=1.0, location=(0.0, 0.905, 0.900))
    cavity = bpy.context.object
    cavity.name = "WolfMouth"
    cavity.scale = (0.047, 0.110, 0.028)
    bpy.ops.object.transform_apply(scale=True)
    cavity.data.materials.append(make_material("Wolf_Mouth", (0.22, 0.045, 0.050), 0.75))
    details.append(cavity)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=9, radius=1.0, location=(0.0, 0.900, 0.892))
    tongue = bpy.context.object
    tongue.name = "WolfTongue"
    tongue.scale = (0.034, 0.088, 0.014)
    bpy.ops.object.transform_apply(scale=True)
    tongue.data.materials.append(make_material("Wolf_Tongue", (0.46, 0.18, 0.17), 0.6))
    details.append(tongue)
    # Nose.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=1.0, location=(0.0, 1.035, 0.925))
    nose = bpy.context.object
    nose.name = "WolfNose"
    nose.scale = (0.036, 0.030, 0.026)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    nose.data.materials.append(make_material("Wolf_Nose", (0.045, 0.038, 0.036), 0.35))
    details.append(nose)
    # Eyes: dark socket, amber iris, black pupil.
    eye_mats = {
        "socket": make_material("Wolf_EyeSocket", (0.045, 0.035, 0.028), 0.55),
        "iris": make_material("Wolf_Iris", (0.72, 0.43, 0.075), 0.24),
        "pupil": make_material("Wolf_Pupil", (0.012, 0.010, 0.009), 0.18),
    }
    for sx in (-1.0, 1.0):
        for key, radius, offset, scale in (
            ("socket", 0.026, 0.0, (1.0, 1.0, 0.92)),
            ("iris", 0.020, 0.008, (1.0, 1.0, 0.90)),
            ("pupil", 0.0095, 0.017, (1.0, 1.0, 0.82)),
        ):
            bpy.ops.mesh.primitive_uv_sphere_add(
                segments=16,
                ring_count=8,
                radius=radius,
                location=(sx * (0.086 + offset), 0.745, 1.006),
            )
            obj = bpy.context.object
            obj.name = f"WolfEye_{key}_{'l' if sx > 0 else 'r'}"
            obj.scale = scale
            bpy.ops.object.transform_apply(scale=True)
            bpy.ops.object.shade_smooth()
            obj.data.materials.append(eye_mats[key])
            details.append(obj)
    # Canines and incisors. Upper -> head, lower -> jaw.
    tooth_mat = make_material("Wolf_Teeth", (0.83, 0.80, 0.69), 0.42)
    for sx in (-1.0, 1.0):
        for z, length, direction, y, jaw_bone in (
            (0.905, 0.050, -1, 0.982, False),
            (0.885, 0.040, 1, 0.972, True),
        ):
            bpy.ops.mesh.primitive_cone_add(
                vertices=10,
                radius1=0.010,
                radius2=0.0,
                depth=length,
                location=(sx * 0.037, y, z),
            )
            tooth = bpy.context.object
            tooth.name = f"WolfCanine_{'l' if sx > 0 else 'r'}_{'lower' if direction > 0 else 'upper'}"
            if direction < 0:
                tooth.rotation_euler.x = math.pi
            bpy.ops.object.transform_apply(rotation=True)
            bpy.ops.object.shade_smooth()
            tooth.data.materials.append(tooth_mat)
            details.append(tooth)
    for sx in (-0.022, 0.0, 0.022):
        bpy.ops.mesh.primitive_cone_add(
            vertices=8, radius1=0.006, radius2=0.0, depth=0.020, location=(sx, 1.000, 0.900)
        )
        tooth = bpy.context.object
        tooth.name = f"WolfIncisor_{sx:+.3f}"
        tooth.rotation_euler.x = math.pi
        bpy.ops.object.transform_apply(rotation=True)
        tooth.data.materials.append(tooth_mat)
        details.append(tooth)
    # Claws and paw pads.
    pad_mat = make_material("Wolf_Pads", (0.105, 0.088, 0.078), 0.62)
    for side, sx in (("l", 1.0), ("r", -1.0)):
        for front in (True, False):
            y0 = 0.455 if front else -0.265
            z0 = 0.030 if front else 0.030
            for index, tx in enumerate((-0.037, 0.0, 0.037)):
                bpy.ops.mesh.primitive_cone_add(
                    vertices=8,
                    radius1=0.0075,
                    radius2=0.0,
                    depth=0.030,
                    location=(sx * 0.18 + tx, y0 + (0.018 if front else -0.018), z0),
                )
                claw = bpy.context.object
                claw.name = f"WolfClaw_{side}_{'front' if front else 'hind'}_{index}"
                # Point forward (+Y) and slightly down.
                claw.rotation_euler.x = math.radians(96.0)
                bpy.ops.object.transform_apply(rotation=True)
                claw.data.materials.append(tooth_mat)
                details.append(claw)
            bpy.ops.mesh.primitive_uv_sphere_add(
                segments=12,
                ring_count=6,
                radius=1.0,
                location=(sx * 0.18, 0.39 if front else -0.34, 0.018),
            )
            pad = bpy.context.object
            pad.name = f"WolfPad_{side}_{'front' if front else 'hind'}"
            pad.scale = (0.045, 0.060, 0.018)
            bpy.ops.object.transform_apply(scale=True)
            pad.data.materials.append(pad_mat)
            details.append(pad)
    return details


# ---------------------------------------------------------------------------
# UV and coat bake


def unwrap_and_paint(mesh: bpy.types.Object, source: Path) -> None:
    """Unwrap the finished mesh and paint the grey coat into its UV atlas.

    A shader bake on a skinned mesh proved non-deterministic in this Blender
    build, so the coat is rasterised directly from rest-space vertex positions.
    The result is the same deliverable: a packed sRGB albedo texture whose
    colours are sampled by the fur material.
    """
    bpy.context.view_layer.objects.active = mesh
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    mesh.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.uv.pack_islands(margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    mesh.data.uv_layers[0].name = "UVMap"
    uv_data = mesh.data.uv_layers.active.data
    uv_area = 0.0
    for polygon in mesh.data.polygons:
        points = [uv_data[index].uv for index in polygon.loop_indices]
        for index in range(1, len(points) - 1):
            a, b, c = points[0], points[index], points[index + 1]
            uv_area += abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) * 0.5
    print("WOLF_UV_AREA", round(uv_area, 4))
    if not 0.05 < uv_area < 1.2:
        raise RuntimeError(f"Wolf UV atlas is not packed (area {uv_area:.3f})")

    fur_slot = next(
        (index for index, material in enumerate(mesh.data.materials) if material and material.name == "Wolf_Fur"),
        None,
    )
    if fur_slot is None:
        raise RuntimeError("Wolf fur material slot is missing")

    size = 1024
    color_sum = np.zeros((size * size, 3), dtype=np.float32)
    weight = np.zeros(size * size, dtype=np.float32)
    positions = [vertex.co.copy() for vertex in mesh.data.vertices]
    uv = [(entry.uv[0], entry.uv[1]) for entry in uv_data]

    def smooth(edge0, edge1, value):
        t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    def coat_colour(x, y, z):
        abx = np.abs(x)
        mid = np.array((0.455, 0.440, 0.405), dtype=np.float32)
        dark = np.array((0.235, 0.228, 0.218), dtype=np.float32)
        light = np.array((0.690, 0.650, 0.565), dtype=np.float32)
        buff = np.array((0.545, 0.510, 0.445), dtype=np.float32)
        muzzle_dark = np.array((0.250, 0.238, 0.225), dtype=np.float32)
        tail_dark = np.array((0.200, 0.192, 0.185), dtype=np.float32)
        ear_dark = np.array((0.245, 0.236, 0.225), dtype=np.float32)
        eye_dark = np.array((0.120, 0.110, 0.100), dtype=np.float32)
        dorsal = smooth(0.76, 0.98, z) * smooth(0.60, 0.72, z)
        belly = 1.0 - smooth(0.54, 0.72, z)
        legs = 1.0 - smooth(0.50, 0.68, z)
        muzzle = smooth(0.88, 0.98, y) * smooth(0.915, 0.945, z)
        cheek = smooth(0.64, 0.72, y) * smooth(0.90, 1.00, z) * smooth(0.035, 0.09, abx)
        chin = smooth(0.88, 0.96, y) * (1.0 - smooth(0.885, 0.925, z))
        tail = np.clip((-y - 0.98) / 0.10, 0.0, 1.0)
        ears = smooth(1.02, 1.07, z) * smooth(0.03, 0.06, abx)
        eye_distance = np.sqrt(
            np.minimum((x - 0.086) ** 2, (x + 0.086) ** 2)
            + (y - 0.745) ** 2
            + (z - 1.006) ** 2
        )
        eyes = 1.0 - smooth(0.035, 0.075, eye_distance)
        colour = mid
        colour = colour * (1.0 - belly[..., None] * 0.45) + light * (belly[..., None] * 0.45)
        colour = colour * (1.0 - legs[..., None] * 0.35) + buff * (legs[..., None] * 0.35)
        colour = colour * (1.0 - dorsal[..., None] * 0.62) + dark * (dorsal[..., None] * 0.62)
        colour = colour * (1.0 - cheek[..., None] * 0.34) + light * (cheek[..., None] * 0.34)
        colour = colour * (1.0 - muzzle[..., None] * 0.62) + muzzle_dark * (muzzle[..., None] * 0.62)
        colour = colour * (1.0 - chin[..., None] * 0.35) + light * (chin[..., None] * 0.35)
        colour = colour * (1.0 - tail[..., None] * 0.82) + tail_dark * (tail[..., None] * 0.82)
        colour = colour * (1.0 - ears[..., None] * 0.62) + ear_dark * (ears[..., None] * 0.62)
        colour = colour * (1.0 - eyes[..., None] * 0.58) + eye_dark * (eyes[..., None] * 0.58)
        # Short-fur variation: broad mottling plus fine directional strands.
        n1 = np.sin(x * 24.0 + y * 19.0 + z * 31.0) * 0.5 + 0.5
        n2 = np.sin(x * 67.0 - y * 53.0 + z * 41.0 + 1.7) * 0.5 + 0.5
        n3 = np.sin(y * 120.0 + n1 * 3.0) * 0.5 + 0.5
        variation = (n1 - 0.5) * 0.055 + (n2 - 0.5) * 0.030 + (n3 - 0.5) * 0.018
        return np.clip(colour * (1.0 + variation[..., None]), 0.0, 1.0)

    triangles = 0
    for polygon in mesh.data.polygons:
        if polygon.material_index != fur_slot:
            continue
        loop_indices = list(polygon.loop_indices)
        for corner in range(1, len(loop_indices) - 1):
            li0, li1, li2 = loop_indices[0], loop_indices[corner], loop_indices[corner + 1]
            vi0 = mesh.data.loops[li0].vertex_index
            vi1 = mesh.data.loops[li1].vertex_index
            vi2 = mesh.data.loops[li2].vertex_index
            u0, v0 = uv[li0]
            u1, v1 = uv[li1]
            u2, v2 = uv[li2]
            xmin = max(0, int(math.floor(min(u0, u1, u2) * size)) - 1)
            xmax = min(size - 1, int(math.ceil(max(u0, u1, u2) * size)) + 1)
            ymin = max(0, int(math.floor(min(v0, v1, v2) * size)) - 1)
            ymax = min(size - 1, int(math.ceil(max(v0, v1, v2) * size)) + 1)
            if xmax < xmin or ymax < ymin:
                continue
            xs = (np.arange(xmin, xmax + 1, dtype=np.float32) + 0.5) / size
            ys = (np.arange(ymin, ymax + 1, dtype=np.float32) + 0.5) / size
            px, py = np.meshgrid(xs, ys)
            denominator = (v1 - v2) * (u0 - u2) + (u2 - u1) * (v0 - v2)
            if abs(float(denominator)) < 1e-9:
                continue
            wa = ((v1 - v2) * (px - u2) + (u2 - u1) * (py - v2)) / denominator
            wb = ((v2 - v0) * (px - u2) + (u0 - u2) * (py - v2)) / denominator
            wc = 1.0 - wa - wb
            inside = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6)
            if not np.any(inside):
                continue
            iy, ix = np.nonzero(inside)
            wa = wa[iy, ix]
            wb = wb[iy, ix]
            wc = wc[iy, ix]
            p0, p1, p2 = positions[vi0], positions[vi1], positions[vi2]
            x = wa * p0.x + wb * p1.x + wc * p2.x
            y = wa * p0.y + wb * p1.y + wc * p2.y
            z = wa * p0.z + wb * p1.z + wc * p2.z
            colours = coat_colour(x, y, z)
            flat = (iy + ymin) * size + (ix + xmin)
            color_sum[flat] += colours
            weight[flat] += 1.0
            triangles += 1

    print("WOLF_TEXTURE_TRIANGLES", triangles)
    covered = weight > 0.0
    if not np.any(covered):
        raise RuntimeError("Wolf coat painter covered no UV pixels")
    image = color_sum / np.maximum(weight[:, None], 1.0)
    image = image.reshape(size, size, 3)
    coverage = covered.reshape(size, size)
    # Dilate the islands so nearest-mip sampling does not pull in empty pixels.
    for _ in range(10):
        neighbour_sum = np.zeros_like(image)
        neighbour_count = np.zeros_like(coverage, dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            shifted_image = np.zeros_like(image)
            shifted_coverage = np.zeros_like(coverage)
            ys0, ys1 = max(0, dy), size + min(0, dy)
            yd0, yd1 = max(0, -dy), size + min(0, -dy)
            xs0, xs1 = max(0, dx), size + min(0, dx)
            xd0, xd1 = max(0, -dx), size + min(0, -dx)
            shifted_image[yd0:yd1, xd0:xd1] = image[ys0:ys1, xs0:xs1]
            shifted_coverage[yd0:yd1, xd0:xd1] = coverage[ys0:ys1, xs0:xs1]
            neighbour_sum += shifted_image * shifted_coverage[..., None]
            neighbour_count += shifted_coverage
        fill = (~coverage) & (neighbour_count > 0.0)
        image[fill] = neighbour_sum[fill] / neighbour_count[fill][:, None]
        coverage[fill] = True
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[..., :3] = image
    texture = bpy.data.images.new("Wolf_Coat", size, size, alpha=False)
    texture.colorspace_settings.name = "sRGB"
    texture.file_format = "PNG"
    texture.pixels.foreach_set(rgba.ravel())
    texture.update()
    texture.pack()
    texture.filepath_raw = str(source / "wolf_coat.png")
    try:
        texture.save()
    except Exception as exc:  # noqa: BLE001 - saving evidence is best-effort
        print("WOLF_COAT_SAVE_SKIPPED", exc)

    procedural = mesh.data.materials[fur_slot]
    nodes = procedural.node_tree.nodes
    links = procedural.node_tree.links
    for node in list(nodes):
        if node.type != "OUTPUT_MATERIAL":
            nodes.remove(node)
    output = nodes.get("Material Output")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Metallic"].default_value = 0.0
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    tex = nodes.new("ShaderNodeTexImage")
    tex.name = "Wolf_Coat_Baked"
    tex.image = texture
    tex.interpolation = "Linear"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    print("WOLF_COAT_DONE", size, int(np.count_nonzero(covered)))


# ---------------------------------------------------------------------------
# Skeleton, weights and export


def build_armature() -> bpy.types.Object:
    armature = bpy.data.armatures.new("WolfArmature")
    rig = bpy.data.objects.new("WolfArmature", armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = armature.edit_bones
    for name in ["root", *DEFORM_BONES]:
        bone = edit_bones.new(name)
        if name == "root":
            bone.head = (0.0, 0.0, 0.0)
            bone.tail = (0.0, 0.0, 0.12)
            bone.use_deform = False
        else:
            head, tail = JOINTS[name]
            bone.head = head
            bone.tail = tail
            parent, connect = BONE_PARENTS[name]
            if parent:
                bone.parent = edit_bones[parent]
                bone.use_connect = connect
            bone.use_deform = True
        bone.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.display_type = "STICK"
    return rig


def bone_segments(rig: bpy.types.Object) -> dict[str, tuple[Vector, Vector]]:
    return {name: (rig.data.bones[name].head_local.copy(), rig.data.bones[name].tail_local.copy()) for name in DEFORM_BONES}


def point_segment_distance(point: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    denom = ab.length_squared
    if denom <= 1e-12:
        return (point - a).length
    t = max(0.0, min(1.0, (point - a).dot(ab) / denom))
    return (point - (a + ab * t)).length


def assign_envelope_weights(obj: bpy.types.Object, rig: bpy.types.Object, smooth_iterations: int = 2) -> None:
    segments = bone_segments(rig)
    groups = {name: obj.vertex_groups.new(name=name) for name in DEFORM_BONES}
    raw_weights: list[dict[str, float]] = []
    for vertex in obj.data.vertices:
        point = vertex.co
        candidate: dict[str, float] = {}
        for name, (radius, priority) in SKIN_BONES.items():
            a, b = segments[name]
            distance = point_segment_distance(point, a, b)
            if distance < radius:
                falloff = (1.0 - (distance / radius) ** 2) ** 2
                if falloff > 0.0005:
                    candidate[name] = falloff * priority
        if not candidate:
            nearest = min(SKIN_BONES, key=lambda n: point_segment_distance(point, *segments[n]))
            candidate[nearest] = 1.0
        raw_weights.append(candidate)
    # Smooth across the actual mesh edges to remove banding at the shoulders.
    adjacency: list[set[int]] = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    for _ in range(smooth_iterations):
        smoothed: list[dict[str, float]] = []
        for index, weights in enumerate(raw_weights):
            merged = {name: value * 0.5 for name, value in weights.items()}
            neighbours = adjacency[index]
            if neighbours:
                scale = 0.5 / len(neighbours)
                for neighbour in neighbours:
                    for name, value in raw_weights[neighbour].items():
                        merged[name] = merged.get(name, 0.0) + value * scale
            smoothed.append(merged)
        raw_weights = smoothed
    for index, weights in enumerate(raw_weights):
        ordered = sorted(weights.items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(value for _, value in ordered)
        if total <= 1e-9:
            ordered = [("pelvis", 1.0)]
            total = 1.0
        for name, value in ordered:
            groups[name].add([index], value / total, "REPLACE")
    print("WOLF_WEIGHTS_ASSIGNED", len(obj.data.vertices))


def rigid_weight(obj: bpy.types.Object, bone: str) -> None:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def ear_weights(obj: bpy.types.Object, side: str) -> None:
    ear_group = obj.vertex_groups.new(name=f"ear_{side}")
    head_group = obj.vertex_groups.new(name="head")
    for vertex in obj.data.vertices:
        t = max(0.0, min(1.0, vertex.co.z - 1.035) / 0.145)
        ear_weight = 0.45 + 0.55 * t
        ear_group.add([vertex.index], ear_weight, "REPLACE")
        head_group.add([vertex.index], 1.0 - ear_weight, "REPLACE")


def join_objects(target: bpy.types.Object, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return bpy.context.object


def finalize_mesh(fur: bpy.types.Object, details: list[bpy.types.Object], rig: bpy.types.Object) -> bpy.types.Object:
    mesh = join_objects(fur, details)
    mesh.name = "WolfMesh"
    mesh.data.name = "WolfMesh"
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.shade_smooth()
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    mesh.parent = rig
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    return mesh


def set_world_rotation(pb, quaternion: Quaternion) -> None:
    rest = pb.bone.matrix_local.to_quaternion()
    pb.rotation_quaternion = rest.inverted() @ quaternion @ rest


def set_axis_rotation(pb, angle: float, axis: Vector = Vector((1.0, 0.0, 0.0))) -> None:
    rest = pb.bone.matrix_local.to_quaternion()
    local_axis = rest.inverted() @ axis
    pb.rotation_quaternion = Quaternion(local_axis.normalized(), angle)


def reset_pose(rig: bpy.types.Object) -> None:
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def set_pelvis_offset(rig: bpy.types.Object, offset: Vector) -> None:
    pb = rig.pose.bones["pelvis"]
    rest = pb.bone.matrix_local.to_quaternion()
    pb.location = rest.inverted() @ offset


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def keyed(t: float, keys: list[tuple[float, float]]) -> float:
    if t <= keys[0][0]:
        return keys[0][1]
    for index in range(1, len(keys)):
        t0, v0 = keys[index - 1]
        t1, v1 = keys[index]
        if t <= t1:
            return v0 + (v1 - v0) * smoothstep(t0, t1, t)
    return keys[-1][1]


def rest_angle(name: str) -> float:
    head, tail = JOINTS[name]
    return math.atan2(tail[1] - head[1], head[2] - tail[2])


def foot_target(chain: str, phase: float, duty: float = 0.45, stride: float = 1.15, clearance: float = 0.075) -> tuple[float, float, float]:
    """Return paw-head offset (y, z lift) and toe flex for one leg."""
    offset = {"fore_l": 0.0, "fore_r": 0.5, "hind_l": 0.5, "hind_r": 0.0}[chain]
    q = (phase - offset) % 1.0
    half = stride * duty * 0.5
    if q < duty:
        # Stance: paw travels backwards relative to the body.
        y = half - 2.0 * half * (q / duty)
        lift = 0.0
        toe = 0.0
    else:
        t = (q - duty) / (1.0 - duty)
        y = -half + 2.0 * half * smoothstep(0.0, 1.0, t)
        lift = clearance * math.sin(math.pi * t) ** 1.15
        toe = -0.35 * math.sin(math.pi * t)
    return y, lift, toe


def solve_leg(rig: bpy.types.Object, chain: str, paw_target: Vector, toe_flex: float, parent_pitch: float) -> None:
    upper_name, lower_name, carpus_name, paw_name, toes_name = LEG_CHAINS[chain]
    upper_pb = rig.pose.bones[upper_name]
    lower_pb = rig.pose.bones[lower_name]
    carpus_pb = rig.pose.bones[carpus_name]
    paw_pb = rig.pose.bones[paw_name]
    toes_pb = rig.pose.bones[toes_name]
    A = upper_pb.matrix.translation.copy()
    # Keep the carpus/hock at its authored ground angle so the sole stays flat.
    carpus_rest = rest_angle(carpus_name)
    carpus_len = (Vector(JOINTS[carpus_name][1]) - Vector(JOINTS[carpus_name][0])).length
    cdir = Vector((0.0, math.sin(carpus_rest), -math.cos(carpus_rest)))
    W = paw_target - cdir * carpus_len
    d = Vector((0.0, W.y - A.y, W.z - A.z))
    L1 = (Vector(JOINTS[upper_name][1]) - Vector(JOINTS[upper_name][0])).length
    L2 = (Vector(JOINTS[lower_name][1]) - Vector(JOINTS[lower_name][0])).length
    distance = max(0.001, min(d.length, L1 + L2 - 0.001))
    u = d.normalized()
    a = (L1 * L1 - L2 * L2 + distance * distance) / (2.0 * distance)
    h = math.sqrt(max(0.0, L1 * L1 - a * a))
    # Fore elbows point backwards; hind stifles point forwards.
    pole = 1.0 if chain.startswith("fore") else -1.0
    normal = Vector((0.0, u.z, -u.y)) * pole
    elbow = A + u * a + normal * h
    phi1 = math.atan2(elbow.y - A.y, A.z - elbow.z)
    phi2 = math.atan2(W.y - elbow.y, elbow.z - W.z)
    rest1 = rest_angle(upper_name)
    rest2 = rest_angle(lower_name)
    rest3 = carpus_rest
    rest4 = rest_angle(paw_name)
    rest5 = rest_angle(toes_name)
    phi3 = math.atan2(paw_target.y - W.y, W.z - paw_target.z)
    phi4 = rest4
    phi5 = rest5 + toe_flex
    set_axis_rotation(upper_pb, (phi1 - rest1) - parent_pitch)
    set_axis_rotation(lower_pb, (phi2 - rest2) - (phi1 - rest1))
    set_axis_rotation(carpus_pb, (phi3 - rest3) - (phi2 - rest2))
    set_axis_rotation(paw_pb, (phi4 - rest4) - (phi3 - rest3))
    set_axis_rotation(toes_pb, (phi5 - rest5) - (phi4 - rest4))


def apply_torso(rig: bpy.types.Object, values: dict) -> float:
    """Apply pelvis/spine/neck/head/tail/jaw/ear pose; return fore parent pitch."""
    pelvis_pitch = values.get("pelvis_pitch", 0.0)
    pelvis_roll = values.get("pelvis_roll", 0.0)
    pelvis_yaw = values.get("pelvis_yaw", 0.0)
    offset = values.get("pelvis_offset", Vector((0.0, 0.0, 0.0)))
    set_pelvis_offset(rig, offset)
    pelvis_q = (
        Quaternion((0.0, 0.0, 1.0), pelvis_yaw)
        @ Quaternion((0.0, 1.0, 0.0), pelvis_roll)
        @ Quaternion((1.0, 0.0, 0.0), pelvis_pitch)
    )
    set_world_rotation(rig.pose.bones["pelvis"], pelvis_q)
    total_pitch = pelvis_pitch
    for name, key in (("spine_01", "spine1_pitch"), ("spine_02", "spine2_pitch"), ("chest", "chest_pitch")):
        pitch = values.get(key, 0.0)
        total_pitch += pitch
        set_axis_rotation(rig.pose.bones[name], pitch)
    for name, key in (("neck_01", "neck1_pitch"), ("neck_02", "neck2_pitch"), ("head", "head_pitch")):
        pitch = values.get(key, 0.0)
        yaw = values.get(key.replace("_pitch", "_yaw"), 0.0)
        roll = values.get(key.replace("_pitch", "_roll"), 0.0)
        quaternion = (
            Quaternion((0.0, 0.0, 1.0), yaw)
            @ Quaternion((0.0, 1.0, 0.0), roll)
            @ Quaternion((1.0, 0.0, 0.0), pitch)
        )
        set_world_rotation(rig.pose.bones[name], quaternion)
    jaw_open = values.get("jaw_open", 0.0)
    set_axis_rotation(rig.pose.bones["jaw"], -jaw_open)
    for side in ("l", "r"):
        ear_pitch = values.get(f"ear_{side}_pitch", 0.0)
        ear_roll = values.get(f"ear_{side}_roll", 0.0)
        quaternion = Quaternion((0.0, 1.0, 0.0), ear_roll) @ Quaternion((1.0, 0.0, 0.0), ear_pitch)
        set_world_rotation(rig.pose.bones[f"ear_{side}"], quaternion)
    for index in range(1, 5):
        name = f"tail_0{index}"
        pitch = values.get(f"tail{index}_pitch", 0.0)
        yaw = values.get(f"tail{index}_yaw", 0.0)
        quaternion = Quaternion((0.0, 0.0, 1.0), yaw) @ Quaternion((1.0, 0.0, 0.0), pitch)
        set_world_rotation(rig.pose.bones[name], quaternion)
    scapula_pitch = values.get("scapula_pitch", 0.0)
    for side in ("l", "r"):
        set_axis_rotation(rig.pose.bones[f"scapula_{side}"], scapula_pitch)
    return total_pitch + scapula_pitch


IDLE_VALUES = {
    "pelvis_pitch": 0.0,
    "spine1_pitch": 0.0,
    "spine2_pitch": 0.0,
    "chest_pitch": 0.0,
    "neck1_pitch": 0.0,
    "neck2_pitch": 0.0,
    "head_pitch": 0.0,
    "jaw_open": 0.0,
    "tail1_pitch": 0.0,
    "tail2_pitch": 0.0,
    "tail3_pitch": 0.0,
    "tail4_pitch": 0.0,
    "scapula_pitch": 0.0,
    "pelvis_offset": Vector((0.0, 0.0, 0.0)),
}


def make_action(rig: bpy.types.Object, name: str, duration: float, pose_function) -> bpy.types.Action:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    frames = int(round(duration * FPS))
    for frame in range(frames + 1):
        t = frame / FPS
        reset_pose(rig)
        values = pose_function(t)
        parent_pitch = apply_torso(rig, values)
        bpy.context.view_layer.update()
        for chain in ("fore_l", "fore_r", "hind_l", "hind_r"):
            chain_parent = parent_pitch if chain.startswith("fore") else values.get("pelvis_pitch", 0.0)
            paw_target = PAW_REST[chain].copy()
            paw_target.y += values.get(f"{chain}_y", 0.0)
            paw_target.z += values.get(f"{chain}_lift", 0.0)
            solve_leg(rig, chain, paw_target, values.get(f"{chain}_toe", 0.0), chain_parent)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "pelvis":
                pb.keyframe_insert("location", frame=frame)
    # Linear interpolation preserves the 60 Hz authored samples exactly.
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                for fcurve in channelbag.fcurves:
                    for point in fcurve.keyframe_points:
                        point.interpolation = "LINEAR"
    action.use_frame_range = True
    action.frame_end = frames
    print("WOLF_ACTION", name, "frames", frames, "seconds", duration)
    return action


def pose_idle(t: float) -> dict:
    phase = (t / 2.4) % 1.0
    breath = math.sin(phase * math.tau)
    values = dict(IDLE_VALUES)
    values.update(
        {
            "pelvis_offset": Vector((0.0, 0.0, 0.006 * breath)),
            "spine1_pitch": 0.012 * breath,
            "spine2_pitch": 0.016 * breath,
            "chest_pitch": 0.018 * breath,
            "neck1_pitch": -0.010 * breath,
            "neck2_pitch": -0.008 * breath,
            "head_pitch": 0.012 * math.sin(phase * math.tau + 0.5),
            "head_yaw": 0.035 * math.sin(phase * math.tau * 0.5),
            "ear_l_pitch": 0.05 * math.sin(phase * math.tau * 2.0 + 0.3),
            "ear_r_pitch": -0.04 * math.sin(phase * math.tau * 2.0 + 1.1),
            "tail1_yaw": 0.10 * math.sin(phase * math.tau),
            "tail2_yaw": 0.14 * math.sin(phase * math.tau - 0.35),
            "tail3_yaw": 0.18 * math.sin(phase * math.tau - 0.7),
            "tail4_yaw": 0.20 * math.sin(phase * math.tau - 1.05),
            "tail1_pitch": 0.03 * math.sin(phase * math.tau + 0.4),
        }
    )
    return values


def pose_trot(t: float) -> dict:
    phase = (t / 0.6) % 1.0
    bob = math.cos(phase * math.tau * 2.0 + 0.35)
    lateral = math.sin(phase * math.tau)
    values = dict(IDLE_VALUES)
    values.update(
        {
            "pelvis_offset": Vector((0.0, 0.0, 0.010 * bob)),
            "pelvis_pitch": 0.018 * math.sin(phase * math.tau * 2.0 + 0.8),
            "pelvis_roll": 0.012 * lateral,
            "pelvis_yaw": 0.008 * lateral,
            "spine1_pitch": -0.010 * bob,
            "spine2_pitch": -0.012 * bob,
            "chest_pitch": -0.016 * bob,
            "neck1_pitch": 0.010 * bob,
            "neck2_pitch": 0.012 * bob,
            "head_pitch": -0.020 * math.sin(phase * math.tau * 2.0 + 1.0),
            "head_yaw": -0.03 * lateral,
            "ear_l_pitch": 0.10 + 0.05 * math.sin(phase * math.tau * 2.0),
            "ear_r_pitch": 0.10 - 0.05 * math.sin(phase * math.tau * 2.0),
            "tail1_yaw": 0.12 * math.sin(phase * math.tau - 0.2),
            "tail2_yaw": 0.18 * math.sin(phase * math.tau - 0.55),
            "tail3_yaw": 0.22 * math.sin(phase * math.tau - 0.9),
            "tail4_yaw": 0.25 * math.sin(phase * math.tau - 1.25),
            "tail1_pitch": 0.08 + 0.04 * bob,
            "scapula_pitch": 0.20 * math.cos(phase * math.tau),
        }
    )
    for chain in ("fore_l", "fore_r", "hind_l", "hind_r"):
        y, lift, toe = foot_target(chain, phase)
        values[f"{chain}_y"] = y
        values[f"{chain}_lift"] = lift
        values[f"{chain}_toe"] = toe
    return values


def pose_attack(t: float) -> dict:
    # The gameplay clock is authoritative: impact is at 0.65 s, recovery ends
    # at 1.50 s. The pose below braces, lunges, snaps the jaw shut at impact,
    # then recoils into a neutral pose that blends back to locomotion.
    crouch = keyed(t, [(0.0, 0.0), (0.18, 1.0), (0.44, 0.85), (0.55, 0.25), (0.65, 0.0), (0.85, 0.55), (1.15, 0.15), (1.5, 0.0)])
    lunge = keyed(t, [(0.0, 0.0), (0.30, 0.0), (0.46, 0.20), (0.58, 0.85), (0.65, 1.0), (0.78, 0.55), (0.96, 0.10), (1.5, 0.0)])
    jaw = keyed(t, [(0.0, 0.0), (0.10, 0.0), (0.26, 0.75), (0.46, 1.0), (0.58, 1.0), (0.63, 0.18), (0.65, 0.0), (0.70, 0.03), (0.86, 0.0), (1.5, 0.0)])
    recoil = keyed(t, [(0.0, 0.0), (0.65, 0.0), (0.72, 1.0), (0.92, 0.45), (1.2, 0.10), (1.5, 0.0)])
    step = keyed(t, [(0.0, 0.0), (0.30, 0.0), (0.44, 0.0), (0.50, 0.05), (0.58, 0.12), (0.65, 0.14), (0.75, 0.14), (0.88, 0.06), (1.10, 0.0), (1.5, 0.0)])
    step_lift = keyed(t, [(0.0, 0.0), (0.44, 0.0), (0.50, 0.035), (0.57, 0.0), (0.65, 0.0), (1.5, 0.0)])
    values = dict(IDLE_VALUES)
    values.update(
        {
            "pelvis_offset": Vector((0.0, 0.13 * lunge, -0.050 * crouch + 0.008 * lunge)),
            "pelvis_pitch": -0.04 * crouch + 0.02 * lunge,
            "pelvis_roll": 0.01 * lunge,
            "spine1_pitch": -0.02 * crouch + 0.02 * lunge,
            "spine2_pitch": -0.03 * crouch + 0.03 * lunge,
            "chest_pitch": -0.04 * crouch + 0.04 * lunge,
            "neck1_pitch": -0.08 * crouch - 0.10 * lunge + 0.08 * recoil,
            "neck2_pitch": -0.10 * crouch - 0.12 * lunge + 0.10 * recoil,
            "head_pitch": -0.12 * crouch - 0.18 * lunge + 0.14 * recoil,
            "head_yaw": 0.04 * lunge - 0.02 * recoil,
            "jaw_open": 0.62 * jaw,
            "ear_l_pitch": -0.55 * crouch,
            "ear_r_pitch": -0.55 * crouch,
            "ear_l_roll": 0.12 * crouch,
            "ear_r_roll": -0.12 * crouch,
            "tail1_pitch": -0.35 * crouch + 0.10 * lunge,
            "tail2_pitch": -0.28 * crouch,
            "tail3_pitch": -0.20 * crouch,
            "tail4_pitch": -0.12 * crouch,
            "scapula_pitch": 0.12 * lunge - 0.03 * crouch,
        }
    )
    # Both forepaws take a short step forward with the body; hind paws stay
    # planted and extend. This keeps the bite supported instead of dragging
    # the forelegs past their reach.
    values["fore_l_y"] = step
    values["fore_r_y"] = step
    values["fore_l_lift"] = step_lift
    values["fore_r_lift"] = step_lift
    values["hind_l_y"] = 0.0
    values["hind_r_y"] = 0.0
    values["fore_l_toe"] = -0.25 * step_lift / 0.035 if step_lift > 0.0 else 0.0
    values["fore_r_toe"] = values["fore_l_toe"]
    return values


def pose_death(t: float) -> dict:
    p = max(0.0, min(1.0, t / 0.45))
    e = smoothstep(0.0, 1.0, p)
    fold = smoothstep(0.10, 0.75, p)
    values = dict(IDLE_VALUES)
    values.update(
        {
            "pelvis_offset": Vector((0.10 * e, 0.04 * e, -0.34 * e)),
            "pelvis_pitch": -0.25 * e,
            "pelvis_roll": 1.28 * e,
            "pelvis_yaw": 0.10 * e,
            "spine1_pitch": 0.10 * e,
            "spine2_pitch": 0.12 * e,
            "chest_pitch": 0.10 * e,
            "neck1_pitch": -0.25 * e,
            "neck2_pitch": -0.20 * e,
            "head_pitch": -0.20 * e,
            "head_yaw": 0.18 * e,
            "jaw_open": 0.20 * (1.0 - e),
            "ear_l_pitch": -0.45 * e,
            "ear_r_pitch": -0.45 * e,
            "tail1_pitch": -0.25 * e,
            "tail2_pitch": -0.20 * e,
            "tail3_pitch": -0.15 * e,
            "tail4_pitch": -0.10 * e,
        }
    )
    # Fold legs under the fallen body.
    for side in ("l", "r"):
        values[f"fore_{side}_pitch"] = 1.10 * fold
        values[f"hind_{side}_pitch"] = 1.00 * fold
        values[f"fore_{side}_lift"] = 0.0
        values[f"hind_{side}_lift"] = 0.0
    return values


def apply_death_legs(rig: bpy.types.Object, values: dict) -> None:
    for side in ("l", "r"):
        for chain, bone in (("fore", f"upper_fore_{side}"), ("hind", f"thigh_{side}")):
            set_axis_rotation(rig.pose.bones[bone], values.get(f"{chain}_{side}_pitch", 0.0))
        # Lower segments fold with the upper segment.
        for chain, lower in (("fore", "lower_fore"), ("hind", "shin")):
            set_axis_rotation(rig.pose.bones[f"{lower}_{side}"], -0.9 * smoothstep(0.0, 1.0, values.get("death_progress", 1.0)))
        for chain, carpus in (("fore", "carpus"), ("hind", "hock")):
            set_axis_rotation(rig.pose.bones[f"{carpus}_{side}"], 0.8 * smoothstep(0.0, 1.0, values.get("death_progress", 1.0)))
        set_axis_rotation(rig.pose.bones[f"front_toes_{side}"], 0.25)
        set_axis_rotation(rig.pose.bones[f"hind_toes_{side}"], 0.25)


def mesh_min_z(mesh: bpy.types.Object) -> float:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    evaluated_mesh = evaluated.to_mesh()
    minimum = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated_mesh.vertices)
    evaluated.to_mesh_clear()
    return minimum


def build_actions(rig: bpy.types.Object) -> list[bpy.types.Action]:
    rig.animation_data_create()
    rig.animation_data.use_nla = False
    actions = [
        make_action(rig, "Wolf_Idle_Loop", 2.4, pose_idle),
        make_action(rig, "Wolf_Trot_Loop", 0.6, pose_trot),
        make_action(rig, "Wolf_Attack", 1.5, pose_attack),
    ]
    # Death uses a direct fold rather than planted-paw IK; author it separately.
    death = bpy.data.actions.new("Wolf_Death")
    death.use_fake_user = True
    rig.animation_data.action = death
    frames = int(round(0.45 * FPS))
    for frame in range(frames + 1):
        t = frame / FPS
        reset_pose(rig)
        values = pose_death(t)
        values["death_progress"] = smoothstep(0.10, 0.75, max(0.0, min(1.0, t / 0.45)))
        apply_torso(rig, values)
        apply_death_legs(rig, values)
        bpy.context.view_layer.update()
        # Ground contact: never penetrate during the collapse, and settle the
        # final held corpse exactly on the floor.
        assert MESH_OBJECT is not None
        for _ in range(2):
            minimum = mesh_min_z(MESH_OBJECT)
            if minimum >= -0.001 and (t < 0.35 or abs(minimum) <= 0.002):
                break
            values["pelvis_offset"] = values["pelvis_offset"] + Vector((0.0, 0.0, -minimum))
            apply_torso(rig, values)
            apply_death_legs(rig, values)
            bpy.context.view_layer.update()
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "pelvis":
                pb.keyframe_insert("location", frame=frame)
    for layer in death.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                for fcurve in channelbag.fcurves:
                    for point in fcurve.keyframe_points:
                        point.interpolation = "LINEAR"
    death.use_frame_range = True
    death.frame_end = frames
    actions.append(death)
    print("WOLF_ACTION Wolf_Death frames", frames, "seconds", 0.45)
    return actions


def setup_nla_and_export(rig: bpy.types.Object, actions: list[bpy.types.Action], output: Path) -> None:
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    for action in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.action_frame_start = 0
        strip.action_frame_end = action.frame_end
        track.mute = True
    reset_pose(rig)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_skins=True,
    )


def glb_document(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20 : 20 + json_length])
    return document, raw


def write_metadata(output: Path, source: Path, actions: list[bpy.types.Action]) -> dict:
    document, raw = glb_document(output)
    animations = {animation["name"]: animation for animation in document.get("animations", [])}
    durations = {}
    for name, animation in animations.items():
        durations[name] = max(
            document["accessors"][sampler["input"]]["max"][0] for sampler in animation["samplers"]
        )
    skin = document["skins"][0]
    bone_names = [document["nodes"][index].get("name", "") for index in skin["joints"]]
    position_accessors = [
        primitive["attributes"]["POSITION"]
        for mesh in document["meshes"]
        for primitive in mesh["primitives"]
    ]
    bounds_min = [min(document["accessors"][index]["min"][axis] for index in position_accessors) for axis in range(3)]
    bounds_max = [max(document["accessors"][index]["max"][axis] for index in position_accessors) for axis in range(3)]
    materials = [material.get("name", "") for material in document.get("materials", [])]
    images = [image.get("mimeType", "") for image in document.get("images", [])]
    triangle_count = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if "indices" in primitive:
                triangle_count += document["accessors"][primitive["indices"]]["count"] // 3
    # A root translation track would double the CharacterBody movement.
    root_index = next((index for index, node in enumerate(document["nodes"]) if node.get("name") == "root"), None)
    root_translation_channels = [
        channel
        for animation in document.get("animations", [])
        for channel in animation["channels"]
        if channel["target"].get("node") == root_index and channel["target"].get("path") == "translation"
    ]
    metadata = {
        "asset": output.name,
        "skeleton": "WolfArmature/Skeleton3D",
        "bone_count": len(bone_names),
        "bone_names": bone_names,
        "forward": [0, 0, -1],
        "up": [0, 1, 0],
        "unit": "metres",
        "rest_bounds_min": bounds_min,
        "rest_bounds_max": bounds_max,
        "shoulder_height": 0.96,
        "muzzle_length": 0.36,
        "tail_length": 0.50,
        "mesh_triangles": triangle_count,
        "materials": materials,
        "embedded_images": images,
        "clips": {
            "idle": {"name": "Wolf_Idle_Loop", "duration": durations.get("Wolf_Idle_Loop"), "loop": True},
            "trot": {
                "name": "Wolf_Trot_Loop",
                "duration": durations.get("Wolf_Trot_Loop"),
                "loop": True,
                "stride": 1.15,
                "duty": 0.45,
                "contact_offsets": {"fore_l": 0.0, "hind_r": 0.0, "fore_r": 0.5, "hind_l": 0.5},
            },
            "attack": {
                "name": "Wolf_Attack",
                "duration": durations.get("Wolf_Attack"),
                "loop": False,
                "impact": 0.65,
                "recovery_end": 1.50,
            },
            "death": {"name": "Wolf_Death", "duration": durations.get("Wolf_Death"), "loop": False},
        },
        "animations": durations,
        "authoring_fps": FPS,
        "root_translation_channels": len(root_translation_channels),
        "source": "Original procedural wolf authored by tools/prepare_wolf.py; no third-party model, texture or motion.",
        "reproducer": "tools/prepare_wolf.py",
    }
    metadata_path = output.with_suffix(".json")
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("WOLF_METADATA", metadata_path)
    return metadata


def render_previews(rig: bpy.types.Object, source: Path, actions: list[bpy.types.Action]) -> None:
    """Render neutral textured/silhouette contact frames into ignored storage."""
    scene = bpy.context.scene
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    scene.render.film_transparent = True
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.show_specular_highlight = False
    world = bpy.data.worlds.new("WolfPreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.08, 0.10, 0.10, 1.0)
    scene.world = world
    cameras = {}
    for name, location, target, ortho in (
        ("side", (3.5, 0.0, 0.60), (0.0, 0.0, 0.60), 1.70),
        ("front", (0.0, 3.6, 0.62), (0.0, 0.0, 0.62), 1.45),
        ("threeq", (2.8, -2.8, 1.40), (0.0, 0.0, 0.62), 2.05),
    ):
        data = bpy.data.cameras.new(name)
        data.type = "ORTHO"
        data.ortho_scale = ortho
        camera = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(camera)
        camera.location = location
        camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        cameras[name] = camera
    # A ground plane makes paw contact legible.
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.data.materials.append(make_material("PreviewGround", (0.18, 0.20, 0.18), 0.9))
    capture_dir = source / "captures"
    capture_dir.mkdir(parents=True, exist_ok=True)
    preview_set = {
        "Wolf_Idle_Loop": [
            (0.0, "front"), (0.0, "side"), (0.0, "threeq"), (1.2, "threeq"), (2.4, "threeq"),
        ],
        "Wolf_Trot_Loop": [
            (0.0, "side"), (0.15, "side"), (0.30, "side"), (0.45, "side"), (0.60, "side"),
        ],
        "Wolf_Attack": [
            (0.0, "threeq"), (0.30, "threeq"), (0.55, "threeq"), (0.65, "threeq"),
            (0.65, "side"), (0.85, "threeq"), (1.25, "threeq"), (1.50, "threeq"),
        ],
        "Wolf_Death": [
            (0.0, "threeq"), (0.15, "threeq"), (0.30, "threeq"), (0.45, "threeq"), (0.45, "side"),
        ],
    }
    for action in actions:
        rig.animation_data.action = action
        if action.slots:
            rig.animation_data.action_slot = action.slots[0]
        for index, (time, view) in enumerate(preview_set.get(action.name, [(action.frame_end / FPS, "threeq")])):
            frame = int(round(time * FPS))
            scene.frame_set(frame)
            scene.camera = cameras[view]
            scene.render.filepath = str(capture_dir / f"{action.name}_{index:02d}_{time:.2f}s_{view}.png")
            bpy.ops.render.render(write_still=True)
    rig.animation_data.action = None
    print("WOLF_CAPTURES", capture_dir)


def main() -> None:
    source, output = parse_args()
    reset_scene()
    print("WOLF_BEGIN", source, output)
    fur = build_body_mesh()
    rig = build_armature()
    assign_envelope_weights(fur, rig)
    ears = [make_ear("l", 1.0), make_ear("r", -1.0)]
    details = make_jaw_and_details()
    jaw = next(obj for obj in details if obj.name == "WolfJaw")
    details.remove(jaw)
    # Jaw and ears join the fur coat before UV unwrap/bake so they share the
    # coat. Their weights are assigned before joining, so the body envelope
    # cannot bleed into the jaw or ears.
    for part in (jaw, *ears):
        part.data.materials.clear()
        part.data.materials.append(bpy.data.materials["Wolf_Fur"])
    rigid_weight(jaw, "jaw")
    ear_weights(ears[0], "l")
    ear_weights(ears[1], "r")
    fur = join_objects(fur, [jaw, *ears])
    fur.name = "WolfFur"
    # Rigid detail weights.
    for obj in details:
        if obj.name == "WolfJaw":
            continue
        if obj.name in ("WolfMouth", "WolfNose", "Wolf_Iris_l", "Wolf_Iris_r", "Wolf_Pupil_l", "Wolf_Pupil_r", "Wolf_EyeSocket_l", "Wolf_EyeSocket_r"):
            rigid_weight(obj, "head")
        elif obj.name == "WolfTongue" or "lower" in obj.name:
            rigid_weight(obj, "jaw")
        elif obj.name.startswith("WolfClaw_"):
            parts = obj.name.split("_")
            side = parts[1]
            front = parts[2] == "front"
            rigid_weight(obj, f"{'front' if front else 'hind'}_toes_{side}")
        elif obj.name.startswith("WolfPad_"):
            parts = obj.name.split("_")
            side = parts[1]
            front = parts[2] == "front"
            rigid_weight(obj, f"{'front' if front else 'hind'}_paw_{side}")
        else:
            rigid_weight(obj, "head")
    mesh = finalize_mesh(fur, [obj for obj in details if obj.name != "WolfJaw"], rig)
    global MESH_OBJECT
    MESH_OBJECT = mesh
    unwrap_and_paint(mesh, source)
    print("WOLF_FINAL_TRIS", sum(len(p.vertices) - 2 for p in mesh.data.polygons))
    actions = build_actions(rig)
    setup_nla_and_export(rig, actions, output)
    metadata = write_metadata(output, source, actions)
    render_previews(rig, source, actions)
    # Keep the editable source outside the tracked tree.
    bpy.ops.wm.save_as_mainfile(filepath=str(source / "ironwood_wolf_source.blend"))
    print("WOLF_DONE", json.dumps({k: metadata[k] for k in ("mesh_triangles", "bone_count", "clips")}, indent=2))


if __name__ == "__main__":
    main()
