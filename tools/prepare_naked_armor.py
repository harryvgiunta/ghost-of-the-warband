"""Author the Naked armor set on the Ranger's own skeleton from a real body.

What a prisoner in the wood actually wears: an old shirt, a pair of cut-off
shorts, and bare skin everywhere else.  Four pieces, one per body region, in
one GLB the runtime binds to its copy of the hero skeleton:

    Armor_Naked_Chest   the torso as skin, with the shirt, sleeves and collar
    Armor_Naked_Hands   both arms as skin, from the deltoid to the fingertips
    Armor_Naked_Legs    both legs as skin, with the shorts over hips and thighs
    Armor_Naked_Feet    both feet as skin

The body is not modelled here.  It is ``Superhero_Male_FullBody`` from
Quaternius' Universal Base Characters (CC0, the same pack the Ranger's head
comes from), whose 65-bone rest skeleton is identical to the Ranger's.  The
source mesh is split by dominant bone into the four slot pieces and skinned to
the Ranger rig with the weights the source already carries, so the anatomy --
deltoids, pectorals, ribs, spine groove, knees, ankles, real fingers and toes --
is the sculpt's, not a surface of revolution.  Only the source's own head is
removed: the Ranger's head, eyes and brows live outside every armour slot and
are always on screen, so the naked body ends in a neck that is fitted *inside*
that head's opening.

The shirt and shorts are cut from the body's own surface: the same faces are
duplicated, relaxed, pushed out by a measured gap and reprojected outside the
body, so the cloth is fitted by construction and cannot stand through the
skin.  Shirt, sleeves, hems, collar and waistband are bands extruded off those
open boundaries, then solidified.  Their PBR maps are rasterised per texel
from analytic fields at bind-space positions: a linen plain weave for the
shirt, a heavier twill for the shorts, plus slubs, dye drift, seams, a button
placket, and grime that collects at the hems.  The skin keeps the source's own
2048 base-colour, normal and roughness maps through its own UVs, so pores,
knuckle creases and nails are the artist's, not noise.

Automatic material checks fail the build on: an unweighted vertex, a group the
Ranger skeleton does not have, a weight set that does not sum to one, a
triangle budget overrun, a cloth vertex inside the skin, or a naked shell that
crosses the face, eyes or brows.

Usage (Blender 5.1+):
    blender --background --python-exit-code 1 --python tools/prepare_naked_armor.py

The source pack is downloaded once into the ignored ``.runtime/character-source``
workspace (see assets/characters/LICENSE.txt for the URL and licence).
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import time
from collections import Counter
from pathlib import Path

import numpy as np
import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import forest_styles as styles  # noqa: E402
import forest_surface as surfaces  # noqa: E402
import prepare_forest_mobs as mobs  # noqa: E402
import prepare_makeshift_armor as salvage  # noqa: E402

TAU = math.tau
ROOT = styles.ROOT
FPS = styles.FPS

RANGER = ROOT / "assets" / "characters" / "ironwood_ranger.glb"
SOURCE_ROOT = ROOT / ".runtime" / "character-source"
BODY_SOURCE = (SOURCE_ROOT / "Universal Base Characters[Standard]" / "Base Characters" /
               "Godot - UE" / "Superhero_Male_FullBody.gltf")
OUTPUT = ROOT / "assets" / "characters" / "armor" / "ironwood_naked.glb"
WORKSPACE = ROOT / ".runtime" / "naked-armor"
TEXTURES = WORKSPACE / "textures"

SLOTS = ("chest", "hands", "legs", "feet")
NODE_NAME = {"chest": "Armor_Naked_Chest", "hands": "Armor_Naked_Hands",
             "legs": "Armor_Naked_Legs", "feet": "Armor_Naked_Feet"}
# One skin material (the source's painted body atlas) and one cloth material
# per garment, so the shirt's linen and the shorts' twill never share a texel.
SKIN_MATERIAL = "Naked_Skin"
CLOTH_MATERIAL = {"shirt": "Naked_Shirt", "shorts": "Naked_Shorts"}
ATLAS_SIZE = {"skin": 2048, "shirt": 1024, "shorts": 1024}
TRIANGLE_BUDGET = 52_000

# The neck has to disappear inside the Ranger head's opening.  The source body
# is full size while the head was fitted at 0.88, so the neck is fitted to the
# head's measured cross-section instead of being left at source scale.
NECK_CUT = 1.565
NECK_BLEND = 1.470
NECK_AXIS_Y = 0.005
NECK_SCALE = 0.87
NECK_MARGIN = 0.002

# Garment extents, in bind-space metres.  The hem sits on the hip above the
# shorts, the sleeve stops mid-bicep, and the shorts end mid-thigh.
SHIRT_HEM_Z = 0.930
SHIRT_TOP_Z = 1.545
SLEEVE_END = 0.158
NECK_LINE_Z = 1.470
NECK_COLUMN = 0.086
SHORTS_TOP_Z = 1.046
SHORTS_HEM_Z = 0.618


# Cloth: ``gap`` is the clear air between skin and the inside of the garment.
# The shirt is loose (a prisoner's shirt is not tailored); the shorts are
# closer but still have room to sit, and both widen toward the hem.
GAP = {
    "shirt": (0.013, 0.024),
    "sleeve": (0.010, 0.014),
    "shorts": (0.013, 0.020),
}
# Drape folds, as (amplitude metres, wavelength metres).  Only outward folds
# survive the reprojection, which is what real cloth does over a body.
FOLDS = {"shirt": ((0.0032, 0.115), (0.0014, 0.047)),
         "shorts": ((0.0022, 0.090), (0.0010, 0.038))}

CLOTH_LOOKS = {
    # Washed, undyed linen: warm grey-beige, low contrast, heavy matte.
    "shirt": {"kind": "shirt", "base": "#b7ac97", "pitch": 0.0042, "twill": 0.0,
              "rough": (0.80, 0.92), "stain": 0.55, "grime": 0.9,
              "contrast": 0.26, "slub": 0.06},
    # Coarse charcoal twill, a visibly different cloth from the shirt.
    "shorts": {"kind": "shorts", "base": "#4c4a45", "pitch": 0.0054, "twill": 0.75,
               "rough": (0.84, 0.95), "stain": 0.75, "grime": 1.0,
               "contrast": 0.34, "slub": 0.10},
}

SAMPLE_DIVISOR = 2  # cloth is baked at twice the exported edge and averaged

START = 0.0


def stamp(label: str) -> None:
    """Print the stage and the seconds since the run began."""
    print(f"NAKED_STAGE {label} {time.perf_counter() - START:.1f}s", flush=True)


RIG: bpy.types.Object | None = None
BODY: bpy.types.Object | None = None
BODY_BVH: BVHTree | None = None
BODY_NORMALS: list[Vector] = []
HEAD_OBJECTS: list[str] = []


# ---------------------------------------------------------------------------
# Small numeric helpers


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    span = edge1 - edge0
    if abs(span) < 1e-12:
        return 0.0
    t = min(1.0, max(0.0, (x - edge0) / span))
    return t * t * (3.0 - 2.0 * t)


def srgb_to_linear(values: np.ndarray) -> np.ndarray:
    values = np.clip(np.asarray(values, np.float64), 0.0, 1.0)
    return np.where(values <= 0.04045, values / 12.92,
                    ((values + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(values: np.ndarray) -> np.ndarray:
    values = np.clip(np.asarray(values, np.float64), 0.0, 1.0)
    return np.where(values <= 0.0031308, values * 12.92,
                    1.055 * np.power(np.maximum(values, 0.0), 1.0 / 2.4) - 0.055)


def _lattice(ix, iy, iz, salt: int) -> np.ndarray:
    h = ix * np.int64(73856093) ^ iy * np.int64(19349663) ^ iz * np.int64(83492791)
    h = (h + np.int64(salt) * np.int64(2654435761)) & np.int64(0x7FFFFFFF)
    h = ((h ^ (h >> 13)) * np.int64(1274126177)) & np.int64(0x7FFFFFFF)
    return ((h ^ (h >> 16)) & np.int64(0xFFFF)).astype(np.float64) / 65535.0


def value_noise(points: np.ndarray, frequency: float, salt: int) -> np.ndarray:
    """A trilinear value-noise field in 0..1 at bind-space points."""
    scaled = np.asarray(points, np.float64) * frequency
    base = np.floor(scaled).astype(np.int64)
    fraction = scaled - base
    smooth = fraction * fraction * (3.0 - 2.0 * fraction)
    total = np.zeros(len(points), np.float64)
    for dx in (0, 1):
        wx = smooth[:, 0] if dx else 1.0 - smooth[:, 0]
        for dy in (0, 1):
            wy = smooth[:, 1] if dy else 1.0 - smooth[:, 1]
            for dz in (0, 1):
                wz = smooth[:, 2] if dz else 1.0 - smooth[:, 2]
                total += wx * wy * wz * _lattice(base[:, 0] + dx, base[:, 1] + dy,
                                                 base[:, 2] + dz, salt)
    return total


def fbm(points: np.ndarray, frequency: float, salt: int, octaves: int = 3) -> np.ndarray:
    total = np.zeros(len(points), np.float64)
    weight = 0.0
    amplitude = 1.0
    for octave in range(octaves):
        total += value_noise(points, frequency * (2.0 ** octave), salt + octave * 7) * amplitude
        weight += amplitude
        amplitude *= 0.5
    return total / weight


def hex_rgb(value: str) -> np.ndarray:
    return np.array([int(value.lstrip("#")[index:index + 2], 16) / 255.0
                     for index in (0, 2, 4)], np.float64)


# ---------------------------------------------------------------------------
# Scene import


def import_scene() -> None:
    """Import the Ranger rig and the source body, and keep them aligned."""
    global RIG, BODY

    global START
    START = time.perf_counter()
    mobs.reset_scene()
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    TEXTURES.mkdir(parents=True, exist_ok=True)
    if not BODY_SOURCE.exists():
        raise SystemExit(
            "Missing source body:\n  %s\n"
            "Download 'Universal Base Characters[Standard].zip' from\n"
            "  https://quaternius.itch.io/universal-base-characters\n"
            "and unpack it into %s (see assets/characters/LICENSE.txt)."
            % (BODY_SOURCE, SOURCE_ROOT))
    print("NAKED_BEGIN", RANGER, flush=True)

    bpy.ops.import_scene.gltf(filepath=str(RANGER))
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not rigs:
        raise SystemExit("ranger GLB contains no armature")
    RIG = rigs[0]
    ranger_names = {obj.name for obj in bpy.data.objects}
    print("NAKED_RIG", RIG.name, "bones", len(RIG.data.bones))

    bpy.ops.import_scene.gltf(filepath=str(BODY_SOURCE))
    imported = [obj for obj in bpy.data.objects if obj.name not in ranger_names]
    bodies = [obj for obj in imported if obj.type == "MESH" and obj.name == "SuperHero_Male"]
    if not bodies:
        raise SystemExit("source body GLB has no SuperHero_Male mesh")
    BODY = bodies[0]
    source_rig = next((obj for obj in imported if obj.type == "ARMATURE"), None)

    # The two rigs are the same 65-bone skeleton at identity.  Repoint the body
    # at the Ranger armature and drop every other source object: only the body
    # surface is used, never the source's head, eyes, brows or hair.
    for modifier in list(BODY.modifiers):
        if modifier.type == "ARMATURE":
            modifier.object = RIG
    BODY.parent = RIG
    BODY.matrix_parent_inverse = Matrix.Identity(4)
    BODY.matrix_world = Matrix.Identity(4)
    for obj in imported:
        if obj not in (BODY, source_rig):
            bpy.data.objects.remove(obj, do_unlink=True)
    if source_rig is not None:
        bpy.data.objects.remove(source_rig, do_unlink=True)

    body_bones = {group.name for group in BODY.vertex_groups}
    rig_bones = {bone.name for bone in RIG.data.bones}
    missing = sorted(body_bones - rig_bones)
    if missing:
        raise SystemExit(f"source body carries bones the ranger lacks: {missing}")

    for material in BODY.data.materials:
        if material is not None:
            material.name = SKIN_MATERIAL
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    node.image.pack()

    print("NAKED_BODY", "verts", len(BODY.data.vertices),
          "faces", len(BODY.data.polygons), "groups", len(BODY.vertex_groups))


def head_meshes() -> list[bpy.types.Object]:
    return [bpy.data.objects[name] for name in HEAD_OBJECTS if name in bpy.data.objects]


# ---------------------------------------------------------------------------
# Neck: fit the source neck inside the Ranger head's opening, then cut the
# source head away


def head_envelope(z: float, band: float = 0.006) -> dict[str, float] | None:
    """The Ranger head's measured cross-section at one height.

    ``x`` is the half-width, ``y0``/``y1`` the front/back extent.  Sampled off
    the head, eyes and brows that actually stay on screen with every armour
    set, so the neck cannot be fitted to a guess.
    """
    xs: list[float] = []
    ys: list[float] = []
    for head in head_meshes():
        for point in head.data.vertices:
            co = point.co
            if abs(co.z - z) > band:
                continue
            xs.append(co.x)
            ys.append(co.y)
    if len(xs) < 12:
        return None
    return {"x": max(abs(value) for value in xs),
            "y0": min(ys), "y1": max(ys)}


def fit_torso() -> dict:
    """Take the barrel out of the source chest.

    The source is a superhero base: its chest is about 18 percent deeper and a
    little broader than a working man's, which is exactly the read the shipped
    shirt had.  A smooth, height-weighted slim over the ribcage leaves the
    anatomy (pecs, lats, waist crease) intact while bringing the silhouette
    back to human proportion; it fades to nothing at the neck, the waist and
    the arms so no joint or skinning region is distorted.
    """
    axis_y = 0.012
    moved = 0
    deepest = 0.0
    for vertex in BODY.data.vertices:
        co = vertex.co
        z = co.z
        if z < 0.95 or z > 1.56:
            continue
        bump = math.exp(-(((z - 1.30) / 0.135) ** 2))
        if bump < 1e-3:
            continue
        depth_scale = 1.0 - 0.12 * bump
        width_scale = 1.0 - 0.035 * bump
        co.x *= width_scale
        co.y = axis_y + (co.y - axis_y) * depth_scale
        moved += 1
        deepest = max(deepest, abs(1.0 - depth_scale))
    BODY.data.update()
    print("NAKED_TORSO", "vertices", moved, "depth_slim_percent", round(deepest * 100.0, 1),
          flush=True)
    return {"depth_slim_max": 0.12, "width_slim_max": 0.035,
            "centre_z": 1.30, "sigma_z": 0.135, "vertices": moved}


def fit_neck() -> dict:
    """Slim the source neck so it passes through the Ranger head's opening.

    The head was fitted to this rig at 0.88 scale while the source body is full
    size, so the neck is a centimetre wider and deeper than the opening.  A
    radial taper about the neck axis, blended in from the neck base and faded
    out beyond the neck column, turns the source's full-size neck into one that
    enters the head cleanly.  It is a proportional taper, so it cannot fold the
    surface or leave a pinch; the trapezius and shoulders keep their shape.
    """
    # Measured off the head's own lower shell: the cut ring has to be inside
    # both of these.
    widths: list[float] = []
    backs: list[float] = []
    for head in head_meshes():
        for point in head.data.vertices:
            if not (NECK_CUT - 0.012 <= point.co.z <= NECK_CUT + 0.010):
                continue
            widths.append(abs(point.co.x))
            backs.append(point.co.y)
    if not widths:
        raise SystemExit("neck fit: no head section above the cut")
    limit_x = max(widths)
    limit_back = max(backs)

    moved = 0
    shift = 0.0
    for vertex in BODY.data.vertices:
        co = vertex.co
        if co.z <= NECK_BLEND - 0.030:
            continue
        radius = math.hypot(co.x, co.y - NECK_AXIS_Y)
        if radius < 1e-6:
            continue
        mask = 1.0 - smoothstep(0.120, 0.170, radius)
        blend = smoothstep(NECK_BLEND, 1.560, co.z) * mask
        if blend <= 0.0:
            continue
        scale = 1.0 - (1.0 - NECK_SCALE) * blend
        co.x *= scale
        co.y = NECK_AXIS_Y + (co.y - NECK_AXIS_Y) * scale
        moved += 1
        shift = max(shift, radius * (1.0 - scale))
    BODY.data.update()

    ring = [vertex.co for vertex in BODY.data.vertices
            if abs(vertex.co.z - (NECK_CUT - 0.002)) < 0.006]
    if not ring:
        raise SystemExit("neck fit: no cut ring to measure")
    clearance = {
        "x_mm": round((limit_x - max(abs(point.x) for point in ring)) * 1000.0, 2),
        "back_mm": round((limit_back - max(point.y for point in ring)) * 1000.0, 2),
        "ring_vertices": len(ring),
    }
    print("NAKED_NECK", "cut", NECK_CUT, "scale", NECK_SCALE, "moved", moved,
          "largest_shift_mm", round(shift * 1000.0, 2), "clearance", clearance, flush=True)
    if min(clearance["x_mm"], clearance["back_mm"]) < 0.0:
        raise SystemExit(f"neck is outside the head's opening: {clearance}")
    return {"blend_z": NECK_BLEND, "cut_z": NECK_CUT, "radial_scale": NECK_SCALE,
            "vertices_moved": moved, "largest_shift_mm": round(shift * 1000.0, 3),
            "clearance": clearance}


def cut_source_head() -> None:
    """Remove the source body's head; the Ranger head is the only head."""
    mesh = BODY.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    dead = [face for face in bm.faces if face.calc_center_median().z > NECK_CUT]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print("NAKED_CUT", "verts", len(mesh.vertices), "faces", len(mesh.polygons))


def measure_body() -> None:
    """Cache the body's triangle tree and its smoothed vertex normals."""
    global BODY_BVH, BODY_NORMALS

    mesh = BODY.data
    vertices = [vertex.co.copy() for vertex in mesh.vertices]
    polygons = [tuple(polygon.vertices) for polygon in mesh.polygons]
    BODY_BVH = BVHTree.FromPolygons(vertices, polygons)
    BODY_NORMALS = [vertex.normal.copy() for vertex in mesh.vertices]


# ---------------------------------------------------------------------------
# Splitting the body into slot pieces


def dominant_bones() -> list[str]:
    groups = {group.index: group.name for group in BODY.vertex_groups}
    result = []
    for vertex in BODY.data.vertices:
        if not vertex.groups:
            result.append("")
            continue
        best = max(vertex.groups, key=lambda entry: entry.weight)
        result.append(groups.get(best.group, ""))
    return result


ARM_PREFIXES = ("index_", "middle_", "ring_", "pinky_", "thumb_")
LEG_BONES = {"thigh_l", "thigh_r", "calf_l", "calf_r"}
FOOT_BONES = {"foot_l", "foot_r", "ball_l", "ball_r"}
ARM_BONES = {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"}


def is_arm_bone(bone: str) -> bool:
    return bone in ARM_BONES or bone.startswith(ARM_PREFIXES)


def slot_faces() -> dict[str, list[int]]:
    dominant = dominant_bones()
    result: dict[str, list[int]] = {slot: [] for slot in SLOTS}
    for face in BODY.data.polygons:
        counts = Counter(dominant[index] for index in face.vertices)
        bone = counts.most_common(1)[0][0]
        if bone in LEG_BONES:
            result["legs"].append(face.index)
        elif bone in FOOT_BONES:
            result["feet"].append(face.index)
        elif is_arm_bone(bone):
            result["hands"].append(face.index)
        else:
            result["chest"].append(face.index)
    return result


def copy_faces(name: str, faces: list[int]) -> bpy.types.Object:
    """Duplicate the body object and keep only ``faces``.

    Vertex groups, weights and the UV layout come along untouched, which is
    what keeps four pieces reading as one body: the seams are the same
    vertices, and the normals are assigned from the source afterwards.
    """
    obj = BODY.copy()
    obj.data = BODY.data.copy()
    obj.name = name
    obj.data.name = name
    bpy.context.collection.objects.link(obj)
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    keep = set(faces)
    bmesh.ops.delete(bm, geom=[face for face in bm.faces if face.index not in keep],
                     context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    prune_empty_groups(obj)
    return obj


def prune_empty_groups(obj: bpy.types.Object) -> None:
    """Drop vertex groups that carry no weight: a copied body keeps all 65."""
    used = set()
    for vertex in obj.data.vertices:
        for entry in vertex.groups:
            if entry.weight > 0.0:
                used.add(entry.group)
    for group in reversed(list(obj.vertex_groups)):
        if group.index not in used:
            obj.vertex_groups.remove(group)


def build_skin_pieces(faces: dict[str, list[int]]) -> dict[str, bpy.types.Object]:
    pieces = {}
    for slot in SLOTS:
        obj = copy_faces("NAKED_Skin_" + slot.capitalize(), faces[slot])
        obj.data.materials.clear()
        obj.data.materials.append(bpy.data.materials[SKIN_MATERIAL])
        pieces[slot] = obj
        triangles = sum(len(face.vertices) - 2 for face in obj.data.polygons)
        print("NAKED_SKIN", slot, "verts", len(obj.data.vertices), "tris", triangles, flush=True)
    return pieces


# ---------------------------------------------------------------------------
# Garments cut from the body's own surface


def arm_parameter(point: Vector, side: str) -> float:
    """Distance in metres from the shoulder joint down the upper-arm axis."""
    head = RIG.data.bones["upperarm_" + side].head_local
    tail = RIG.data.bones["lowerarm_" + side].head_local
    axis = tail - head
    length = axis.length
    if length < 1e-9:
        return 0.0
    return (point - head).dot(axis / length)


def shirt_faces() -> list[int]:
    """Torso and the upper half of each upper arm, in one connected shell."""
    dominant = dominant_bones()
    selected: list[int] = []
    for face in BODY.data.polygons:
        centre = face.center
        if centre.z < SHIRT_HEM_Z or centre.z > SHIRT_TOP_Z:
            continue
        bones = Counter(dominant[index] for index in face.vertices)
        bone = bones.most_common(1)[0][0]
        neck_column = (centre.z > NECK_LINE_Z
                       and math.hypot(centre.x, centre.y - NECK_AXIS_Y) < NECK_COLUMN)
        if bone == "neck_01" or neck_column:
            # The neck is skin above the neckline: a crew collar sits at the
            # base of the neck, so nothing of the shirt climbs the neck.
            continue
        if is_arm_bone(bone):
            side = "l" if centre.x > 0.0 else "r"
            if bone.startswith(("lowerarm", "hand")) or bone.startswith(ARM_PREFIXES):
                continue
            if arm_parameter(centre, side) > SLEEVE_END:
                continue
        selected.append(face.index)
    return selected


def shorts_faces() -> list[int]:
    selected = []
    for face in BODY.data.polygons:
        centre = face.center
        if centre.z < SHORTS_HEM_Z or centre.z > SHORTS_TOP_Z:
            continue
        selected.append(face.index)
    return selected


def weld(obj: bpy.types.Object, distance: float = 0.0002) -> None:
    """Merge the source's split seam vertices so a garment is one shell.

    Game meshes duplicate vertices along UV seams; a copied patch therefore has
    phantom boundary loops running down the middle of the cloth.  Welding them
    (UVs stay per-loop) is what lets the hem, cuffs and waistband be extruded
    off real openings instead of off a seam.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=distance)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def shell_from_faces(name: str, faces: list[int]) -> bpy.types.Object:
    obj = copy_faces(name, faces)
    weld(obj)
    return obj


def vertex_adjacency(mesh: bpy.types.Mesh) -> list[list[int]]:
    adjacency: list[set[int]] = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    return [sorted(neighbours) for neighbours in adjacency]


def signed_distance(point: Vector) -> tuple[float, Vector]:
    """Distance to the body surface, positive outside, and the surface normal."""
    location, normal, _index, _distance = BODY_BVH.find_nearest(point)
    if location is None:
        return 1.0e9, Vector((0.0, 0.0, 1.0))
    return (point - location).dot(normal), normal


def drape(obj: bpy.types.Object, gap: tuple[float, float], folds, hem_z: float,
          smooth_iterations: int = 9) -> dict:
    """Relax the copied skin, push it out, and keep it outside the body.

    Relaxation removes the anatomy that cloth bridges (the spine groove, the
    pectoral split); the reprojection puts the garment back outside the skin
    with the measured gap; the fold field is added outward only, so it cannot
    punch through the body it is supposed to hang off.
    """
    mesh = obj.data
    mesh.update()
    adjacency = vertex_adjacency(mesh)
    positions = [vertex.co.copy() for vertex in mesh.vertices]
    normals = [vertex.normal.copy() for vertex in mesh.vertices]
    hem_reach = max(1e-6, SHIRT_TOP_Z - hem_z) if hem_z < 1.0 else 1.0

    for _ in range(smooth_iterations):
        smoothed = []
        for index, point in enumerate(positions):
            neighbours = adjacency[index]
            if not neighbours:
                smoothed.append(point.copy())
                continue
            average = Vector((0.0, 0.0, 0.0))
            for neighbour in neighbours:
                average += positions[neighbour]
            average /= len(neighbours)
            smoothed.append(point.lerp(average, 0.55))
        positions = smoothed

    def gap_at(z: float) -> float:
        if hem_z >= 1.0:  # sleeve: constant clearance, not a hanging hem
            return gap[0]
        share = 1.0 - smoothstep(hem_z, SHIRT_TOP_Z, z)
        return gap[0] + (gap[1] - gap[0]) * share

    for index, point in enumerate(positions):
        normal = normals[index]
        target = point + normal * gap_at(point.z)
        # Keep the shell outside the body even after relaxation and, at the
        # armhole and crotch, where the copied normals converge.
        distance, surface_normal = signed_distance(target)
        if distance < gap_at(target.z):
            target += surface_normal * (gap_at(target.z) - distance)
        # Drape folds: outward only, strongest at the free hem.
        fold = 0.0
        for amplitude, wavelength in folds:
            phase = point.x * 0.76 + point.y * 0.51 + point.z * 0.40
            fold += amplitude * math.sin(TAU * phase / wavelength)
        fold *= 0.35 + 0.65 * (1.0 - min(1.0, abs(point.z - hem_z) / hem_reach))
        target += normal * max(0.0, fold)
        distance, surface_normal = signed_distance(target)
        if distance < gap_at(target.z):
            target += surface_normal * (gap_at(target.z) - distance)
        positions[index] = target

    for vertex, point in zip(mesh.vertices, positions):
        vertex.co = point
    mesh.update()

    inside = 0
    worst = 0.0
    for point in positions:
        distance, _normal = signed_distance(point)
        if distance < 0.0005:
            inside += 1
            worst = max(worst, -distance)
    return {"vertices_inside_skin": inside, "deepest_mm": round(worst * 1000.0, 3)}


def boundary_loops(mesh: bpy.types.Mesh) -> list[list[int]]:
    """Groups of boundary edge indices, one list per open rim."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.edges.ensure_lookup_table()
    boundary = [edge for edge in bm.edges if len(edge.link_faces) == 1]
    adjacency: dict[int, list[int]] = {}
    for edge in boundary:
        for vertex in edge.verts:
            adjacency.setdefault(vertex.index, []).append(edge.index)
    seen: set[int] = set()
    loops: list[list[int]] = []
    by_index = {edge.index: edge for edge in boundary}
    for edge in boundary:
        if edge.index in seen:
            continue
        stack = [edge]
        group = []
        while stack:
            current = stack.pop()
            if current.index in seen:
                continue
            seen.add(current.index)
            group.append(current.index)
            for vertex in current.verts:
                for neighbour in adjacency.get(vertex.index, []):
                    if neighbour not in seen:
                        stack.append(by_index[neighbour])
        loops.append(group)
    bm.free()
    return loops


def loop_vertices(mesh: bpy.types.Mesh, edges: list[int]) -> list[int]:
    vertices: set[int] = set()
    for index in edges:
        edge = mesh.edges[index]
        vertices.update(edge.vertices)
    return sorted(vertices)


def extrude_band(obj: bpy.types.Object, edges: list[int], offset: Vector,
                 flare: float = 0.0) -> tuple[int, int, int]:
    """Extrude an open rim into a band: hem, cuff, collar or waistband."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.edges.ensure_lookup_table()
    selection = [bm.edges[index] for index in edges]
    before = len(bm.verts)
    result = bmesh.ops.extrude_edge_only(bm, edges=selection)
    new_verts = [element for element in result["geom"] if isinstance(element, bmesh.types.BMVert)]
    centre = Vector((0.0, 0.0, sum(vertex.co.z for vertex in new_verts) / max(1, len(new_verts))))
    for vertex in new_verts:
        direction = vertex.co - centre
        direction.z = 0.0
        if direction.length > 1e-6:
            vertex.co += direction.normalized() * flare
        vertex.co += offset
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return before, len(obj.data.vertices), len(new_verts)


def copy_weights_from_nearest(obj: bpy.types.Object) -> int:
    """Give band vertices the weights of the garment vertex they grew from."""
    mesh = obj.data
    groups = {group.index: group.name for group in obj.vertex_groups}
    weighted = [vertex.index for vertex in mesh.vertices if vertex.groups]
    unweighted = [vertex.index for vertex in mesh.vertices if not vertex.groups]
    if not unweighted:
        return 0
    if not weighted:
        raise RuntimeError(f"{obj.name}: no weighted vertices to copy from")
    tree = KDTree(len(weighted))
    for slot, index in enumerate(weighted):
        tree.insert(mesh.vertices[index].co, slot)
    tree.balance()
    groups_by_name = {group.name: group for group in obj.vertex_groups}
    for index in unweighted:
        _co, slot, _distance = tree.find(mesh.vertices[index].co)
        source = mesh.vertices[weighted[slot]]
        for entry in source.groups:
            name = groups.get(entry.group)
            if name is None:
                continue
            groups_by_name[name].add([index], entry.weight, "REPLACE")
    return len(unweighted)


def garment_extent(obj: bpy.types.Object) -> dict:
    points = [vertex.co for vertex in obj.data.vertices]
    return {
        "z_range": [round(min(point.z for point in points), 4),
                    round(max(point.z for point in points), 4)],
        "x_range": [round(min(point.x for point in points), 4),
                    round(max(point.x for point in points), 4)],
        "vertices": len(points),
    }


def build_shirt() -> tuple[bpy.types.Object, dict]:
    faces = shirt_faces()
    obj = shell_from_faces("NAKED_Shirt", faces)
    report = drape(obj, GAP["shirt"], FOLDS["shirt"], SHIRT_HEM_Z)
    loops = boundary_loops(obj.data)
    classified = {"hem": [], "neck": [], "cuff": []}
    for loop in loops:
        vertices = loop_vertices(obj.data, loop)
        if not vertices:
            continue
        coords = [obj.data.vertices[index].co for index in vertices]
        low = min(point.z for point in coords)
        high = max(point.z for point in coords)
        side = sum(point.x for point in coords) / len(coords)
        reach = max(abs(point.x) for point in coords)
        if reach > 0.20:
            classified["cuff"].append(loop)
        elif high < 1.05:
            classified["hem"].append(loop)
        elif abs(side) < 0.06 and high > 1.40:
            classified["neck"].append(loop)
        else:
            classified["cuff"].append(loop)
    bands = 0
    for loop in classified["hem"]:
        extrude_band(obj, loop, Vector((0.0, 0.0, -0.020)), flare=0.004)
        bands += 1
    # The neckline is left as the shell's own edge (solidify gives it a rolled
    # rim) and its rib is painted in the cloth field: extruding a band off a
    # loop that crosses the trapezius ridge would raise a rim across the back.
    for loop in classified["cuff"]:
        extrude_band(obj, loop, Vector((0.0, 0.0, 0.0)), flare=0.003)
        bands += 1
    report["bands"] = bands
    report["weighted_from_neighbour"] = copy_weights_from_nearest(obj)
    report.update(garment_extent(obj))
    mobs.solidify(obj, 0.0035)
    mobs.set_active(obj)
    bpy.ops.object.shade_smooth()
    print("NAKED_SHIRT", "faces", len(obj.data.polygons), "bands", bands,
          "inside", report["vertices_inside_skin"], report, flush=True)
    return obj, report


def build_shorts() -> tuple[bpy.types.Object, dict]:
    faces = shorts_faces()
    obj = shell_from_faces("NAKED_Shorts", faces)
    report = drape(obj, GAP["shorts"], FOLDS["shorts"], SHORTS_HEM_Z)
    loops = boundary_loops(obj.data)
    spans = []
    for loop in loops:
        vertices = loop_vertices(obj.data, loop)
        if not vertices:
            continue
        coords = [obj.data.vertices[index].co for index in vertices]
        spans.append((max(point.z for point in coords),
                      min(point.z for point in coords), loop))
    spans.sort(key=lambda entry: -entry[0])
    # A pair of shorts is three openings: the waist (highest) and two leg
    # hems (lowest).  Nothing else survives welding.
    waists = [spans[0][2]] if spans else []
    hems = [entry[2] for entry in spans[1:] if entry[1] < SHORTS_HEM_Z + 0.06]
    bands = 0
    for loop in waists:
        extrude_band(obj, loop, Vector((0.0, 0.0, 0.024)), flare=0.004)
        bands += 1
    for loop in hems:
        extrude_band(obj, loop, Vector((0.0, 0.0, -0.014)), flare=0.003)
        bands += 1
    report["bands"] = bands
    report["weighted_from_neighbour"] = copy_weights_from_nearest(obj)
    report.update(garment_extent(obj))
    mobs.solidify(obj, 0.0040)
    mobs.set_active(obj)
    bpy.ops.object.shade_smooth()
    print("NAKED_SHORTS", "faces", len(obj.data.polygons), "bands", bands,
          "inside", report["vertices_inside_skin"], report, flush=True)
    return obj, report


# ---------------------------------------------------------------------------
# Cloth maps


def seam_line(distance: np.ndarray, half_width: float) -> np.ndarray:
    """A soft one-texel-wide line around zero distance."""
    return np.clip(1.0 - np.abs(distance) / half_width, 0.0, 1.0)


def cloth_field(look: dict, points: np.ndarray) -> dict[str, np.ndarray]:
    """Linen or twill at bind-space points: weave, slubs, stains, seams.

    Every seam is authored in bind space so it lands on the garment it belongs
    to: the shirt gets its hem stitch, a button placket and collar rib; the
    shorts get a waistband, leg hems, a side seam and a fly.
    """
    base = hex_rgb(look["base"])
    pitch = float(look["pitch"])
    kind = str(look["kind"])
    x, y, z = points[:, 0], points[:, 1], points[:, 2]
    radius = np.hypot(x, y - NECK_AXIS_Y)
    warp = 0.5 + 0.5 * np.sin(TAU * z / pitch)
    weft = 0.5 + 0.5 * np.sin(TAU * (0.71 * x + 0.71 * y) / pitch + 1.7)
    twill = float(look["twill"])
    diagonal = 0.5 + 0.5 * np.sin(TAU * (z + 0.55 * x + 0.35 * y) / (pitch * 1.6))
    weave = (1.0 - twill) * (0.55 * warp + 0.45 * weft) + twill * diagonal

    broad = fbm(points, 7.0, 61, 2)
    fine = value_noise(points, 240.0, 67) * 0.65 + value_noise(points, 420.0, 73) * 0.35
    slub = np.clip((value_noise(points, 90.0, 71) - 0.72) / 0.28, 0.0, 1.0)
    stain = fbm(points, 3.1, 83, 3)
    grime = np.clip((0.72 - z) / 0.55, 0.0, 1.0) ** 1.6 * float(look["grime"])

    shade = (0.5 + (broad - 0.5) * 0.10 + (fine - 0.5) * 0.75
             + (weave - 0.5) * 0.30 + slub * float(look["slub"]))
    shade -= np.clip(stain - 0.62, 0.0, 1.0) * 0.55 * float(look["stain"])
    albedo = np.clip(base[None, :] * (1.0 + (shade - 0.5)[:, None] * float(look["contrast"])),
                     0.0, 1.0)
    albedo *= (1.0 - grime[:, None] * 0.22)

    seam = np.zeros(len(points), np.float64)
    darken = np.zeros(len(points), np.float64)
    raise_height = np.zeros(len(points), np.float64)
    dash = (np.sin(TAU * (x * 46.0 + y * 46.0)) > 0.30).astype(np.float64)
    if kind == "shirt":
        seam = np.maximum(seam, seam_line(z - (SHIRT_HEM_Z + 0.012), 0.0016) * dash)
        placket = (np.abs(x) < 0.015) & (y < -0.02) & (z > 1.03) & (z < 1.50)
        for centre_z in (1.075, 1.175, 1.275, 1.375, 1.475):
            button = np.exp(-(((z - centre_z) / 0.011) ** 2) - ((x / 0.009) ** 2))
            raise_height = np.maximum(raise_height, button * 0.5)
            darken = np.maximum(darken, button * 0.25)
        raise_height += placket.astype(np.float64) * 0.12
        darken += placket.astype(np.float64) * 0.05
        # Ribbed crew collar around the neckline.
        collar = ((z > 1.435) & (radius > 0.070) & (radius < 0.100)).astype(np.float64)
        rib = 0.5 + 0.5 * np.sin(np.arctan2(y - NECK_AXIS_Y, x) * 64.0)
        raise_height += collar * rib * 0.35
        darken += collar * 0.10 * rib
    else:
        seam = np.maximum(seam, seam_line(z - (SHORTS_TOP_Z + 0.002), 0.0016) * dash)
        seam = np.maximum(seam, seam_line(z - (SHORTS_HEM_Z + 0.014), 0.0016) * dash)
        waist = (z > SHORTS_TOP_Z - 0.030).astype(np.float64)
        raise_height += waist * 0.18
        darken += waist * 0.10
        fly = (np.abs(x) < 0.010) & (y < -0.03) & (z > 0.93) & (z < 1.03)
        raise_height += fly.astype(np.float64) * 0.12
        darken += fly.astype(np.float64) * 0.06
        side = seam_line(np.abs(x) - 0.150, 0.0020) * ((y < -0.02) | (y > 0.03)).astype(np.float64)
        seam = np.maximum(seam, side * 0.8)

    albedo = albedo * (1.0 - seam[:, None] * 0.32) * (1.0 - darken[:, None])
    height = np.clip(0.5 + (weave - 0.5) * 0.55 + (fine - 0.5) * 0.35
                     + (broad - 0.5) * 0.10 + seam * 0.18 + raise_height
                     + slub * 0.12, 0.0, 1.0)
    low, high = look["rough"]
    roughness = np.clip(low + (high - low) * np.clip(
        0.25 + 0.55 * fine + 0.20 * weave + 0.25 * grime, 0.0, 1.0), low, high)
    # ``new_image`` writes these values into the image buffer and saves them
    # byte-for-byte, so the albedo is handed over in sRGB exactly as an author
    # would paint it.  (Feeding it linear values is what turns a charcoal
    # twill into black and a linen shirt into a pale grey.)
    return {"albedo": linear_to_srgb(srgb_to_linear(albedo)),
            "height": height, "roughness": roughness}


def bake_cloth(obj: bpy.types.Object, look: dict, key: str) -> bpy.types.Material:
    size = int(ATLAS_SIZE[key])
    bake = size * int(SAMPLE_DIVISOR)
    chunks = mobs.triangle_texels(obj, 0, bake)
    if not chunks:
        raise SystemExit(f"{obj.name}: no texels to bake")
    flat = np.concatenate([chunk[0] for chunk in chunks])
    points = np.concatenate([chunk[1] for chunk in chunks])
    albedo = np.zeros((bake * bake, 3), np.float32)
    height = np.zeros(bake * bake, np.float32)
    roughness = np.zeros(bake * bake, np.float32)
    covered = np.zeros(bake * bake, bool)
    sampled = cloth_field(look, points)
    albedo[flat] = np.clip(sampled["albedo"], 0.0, 1.0)
    height[flat] = np.clip(sampled["height"], 0.0, 1.0)
    roughness[flat] = np.clip(sampled["roughness"], 0.0, 1.0)
    covered[flat] = True

    def downsample(array: np.ndarray, factor: int) -> np.ndarray:
        if array.ndim == 1:
            return array.reshape(bake, bake).reshape(size, factor, size, factor).mean(axis=(1, 3))
        return array.reshape(bake, bake, -1).reshape(
            size, factor, size, factor, -1).mean(axis=(1, 3))

    albedo = downsample(albedo, SAMPLE_DIVISOR)
    height = downsample(height, SAMPLE_DIVISOR)
    roughness = downsample(roughness, SAMPLE_DIVISOR)
    coverage = covered.reshape(bake, bake).reshape(
        size, SAMPLE_DIVISOR, size, SAMPLE_DIVISOR).mean(axis=(1, 3)) > 0.5
    albedo = mobs.dilate(albedo, coverage.copy(), 4)
    height = mobs.dilate(height[..., None], coverage.copy(), 3)[..., 0]
    roughness = mobs.dilate(roughness[..., None], coverage.copy(), 3)[..., 0]

    normals = surfaces.normal_map(height, 0.55)
    prefix = CLOTH_MATERIAL[key]
    images = {
        "albedo": mobs.new_image(prefix + "_albedo", size, albedo, False, TEXTURES),
        "normal": mobs.new_image(prefix + "_normal", size, np.clip(normals, 0.0, 1.0), True,
                                 TEXTURES),
        "roughness": mobs.new_image(prefix + "_roughness", size, roughness, True, TEXTURES),
    }
    material = bpy.data.materials.new(prefix)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        if node.type != "OUTPUT_MATERIAL":
            nodes.remove(node)
    output = nodes.get("Material Output") or nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-260, 0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0.30
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    colour = nodes.new("ShaderNodeTexImage")
    colour.image = images["albedo"]
    colour.location = (-900, 220)
    links.new(colour.outputs["Color"], bsdf.inputs["Base Color"])
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.image = images["normal"]
    normal_tex.location = (-900, -220)
    normal_tex.image.colorspace_settings.name = "Non-Color"
    normal_node = nodes.new("ShaderNodeNormalMap")
    normal_node.location = (-620, -220)
    normal_node.inputs["Strength"].default_value = 1.0
    links.new(normal_tex.outputs["Color"], normal_node.inputs["Color"])
    links.new(normal_node.outputs["Normal"], bsdf.inputs["Normal"])
    rough_tex = nodes.new("ShaderNodeTexImage")
    rough_tex.image = images["roughness"]
    rough_tex.location = (-900, -520)
    rough_tex.image.colorspace_settings.name = "Non-Color"
    links.new(rough_tex.outputs["Color"], bsdf.inputs["Roughness"])
    values = albedo.reshape(-1, 3).mean(axis=0)
    print("NAKED_CLOTH", key, "texels", int(flat.size), "mean", np.round(values, 3),
          "rough", round(float(roughness.mean()), 3), flush=True)
    return material


def dress_garment(obj: bpy.types.Object, look: dict, key: str) -> bpy.types.Material:
    """Unwrap the garment, bake its cloth and give it the material."""
    salvage.unwrap_piece(obj, {0: (0.02, 0.98, 0.02, 0.98)})
    total, largest = uv_report(obj)
    print("NAKED_UV", obj.name, "uv_total", round(total, 4),
          "uv_largest", round(largest, 5), flush=True)
    if total > 0.95:
        raise SystemExit(f"{obj.name}: UV islands overlap ({total:.3f} > 0.95)")
    material = bake_cloth(obj, look, key)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return material


def uv_report(piece: bpy.types.Object) -> tuple[float, float]:
    uv = piece.data.uv_layers[0].data
    areas = []
    for polygon in piece.data.polygons:
        corners = [uv[loop].uv for loop in polygon.loop_indices]
        area = 0.0
        for index in range(1, len(corners) - 1):
            ax, ay = corners[0]
            bx, by = corners[index]
            cx, cy = corners[index + 1]
            area += abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5
        areas.append(area)
    return sum(areas), max(areas)


# ---------------------------------------------------------------------------
# Validation


def validate_piece(piece: bpy.types.Object, claimed: list[str]) -> list[str]:
    """Fail the build on an unweighted vertex, an empty group or a stray bone."""
    problems: list[str] = []
    bones = {bone.name for bone in RIG.data.bones}
    for bone in claimed:
        if bone not in bones:
            problems.append(f"{piece.name}: bone {bone!r} is not in the ranger skeleton")
    groups = {group.index: group.name for group in piece.vertex_groups}
    used: dict[str, int] = {name: 0 for name in groups.values()}
    unweighted = 0
    for vertex in piece.data.vertices:
        total = 0.0
        for entry in vertex.groups:
            name = groups.get(entry.group)
            if name is None:
                continue
            if name not in bones:
                problems.append(f"{piece.name}: vertex group {name!r} is not a ranger bone")
            total += entry.weight
            used[name] += 1
        if total <= 1e-5:
            unweighted += 1
        elif abs(total - 1.0) > 1e-3:
            problems.append(f"{piece.name}: weights on vertex {vertex.index} sum to {total:.4f}")
    if unweighted:
        problems.append(f"{piece.name}: {unweighted} vertices carry no weight")
    for name, count in used.items():
        if count == 0:
            problems.append(f"{piece.name}: vertex group {name!r} is empty")
    return problems


def tree_for(obj: bpy.types.Object) -> BVHTree:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(obj, depsgraph)


def clearance_report(piece: bpy.types.Object, refs: list[bpy.types.Object],
                     label: str, floor_z: float = -1.0e9) -> dict[str, dict]:
    """Triangle-tree crossings between one piece and named reference surfaces.

    ``floor_z`` keeps the gate on what is actually on screen: the naked neck
    passes up through the head's opening, which is a crossing of the head's rim
    by design, so only crossings above the jaw are defects.
    """
    report: dict[str, dict] = {}
    own = tree_for(piece)
    for ref in refs:
        other = tree_for(ref)
        hits = own.overlap(other)
        if floor_z > -1.0e8:
            hits = [pair for pair in hits
                    if piece.data.polygons[pair[0]].center.z > floor_z]
        report[ref.name] = {"intersections": len(hits)}
        if hits and os.environ.get("NAKED_DEBUG_HITS"):
            sample = [piece.data.polygons[pair[0]].center for pair in hits][:6]
            print("NAKED_HITS", label, piece.name, ref.name,
                  [(round(c.x, 3), round(c.y, 3), round(c.z, 3)) for c in sample], flush=True)
        print(f"NAKED_CLEARANCE {label} {piece.name} vs {ref.name} intersections={len(hits)}",
              flush=True)
    return report


def garment_skin_gap(garment: bpy.types.Object) -> dict:
    """Cloth-to-skin distance in bind space: reported, gated on cloth under skin."""
    inside = 0
    deepest = 0.0
    minimum = 1.0e9
    for vertex in garment.data.vertices:
        signed, _normal = signed_distance(vertex.co)
        minimum = min(minimum, signed)
        if signed < 0.0005:
            inside += 1
            deepest = max(deepest, -signed)
    return {"vertices_inside_skin": inside,
            "deepest_mm": round(deepest * 1000.0, 3),
            "minimum_gap_mm": round(minimum * 1000.0, 3)}


# ---------------------------------------------------------------------------
# Export + measured metadata


def reset_pose() -> None:
    if RIG.animation_data:
        RIG.animation_data.action = None
    for pose_bone in RIG.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def export(pieces: list[bpy.types.Object]) -> None:
    reset_pose()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    RIG.select_set(True)
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_force_sampling=True,
        export_frame_range=False,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_skins=True,
    )


def glb_document(path: Path) -> dict:
    raw = path.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20: 20 + json_length])


def image_bytes(document: dict, index: int) -> int:
    view = document["bufferViews"][document["images"][index]["bufferView"]]
    return int(view["byteLength"])


def write_metadata(pieces: list[bpy.types.Object], extras: dict) -> dict:
    document = glb_document(OUTPUT)
    nodes = document["nodes"]
    skin = document["skins"][0]
    bones = [nodes[index].get("name", "") for index in skin["joints"]]
    node_index = {node.get("name", ""): index for index, node in enumerate(nodes)}
    pieces_meta: dict[str, dict] = {}
    total = 0
    for piece in pieces:
        index = node_index.get(piece.name)
        if index is None:
            raise SystemExit(f"exported GLB is missing node {piece.name}")
        mesh = document["meshes"][nodes[index]["mesh"]]
        position_accessors = [primitive["attributes"]["POSITION"] for primitive in mesh["primitives"]]
        bounds_min = [min(document["accessors"][a]["min"][axis] for a in position_accessors)
                      for axis in range(3)]
        bounds_max = [max(document["accessors"][a]["max"][axis] for a in position_accessors)
                      for axis in range(3)]
        triangles = 0
        for primitive in mesh["primitives"]:
            if "indices" in primitive:
                triangles += document["accessors"][primitive["indices"]]["count"] // 3
        used = sorted(group.name for group in piece.vertex_groups)
        pieces_meta[piece.name] = {
            "slot": piece.name.split("_")[-1].lower(),
            "bones": used,
            "triangles": triangles,
            "bounds_min": [round(value, 5) for value in bounds_min],
            "bounds_max": [round(value, 5) for value in bounds_max],
            "vertices": sum(document["accessors"][primitive["attributes"]["POSITION"]]["count"]
                            for primitive in mesh["primitives"]),
            "materials": [document["materials"][primitive["material"]].get("name", "")
                          for primitive in mesh["primitives"] if "material" in primitive],
        }
        total += triangles
    images = document.get("images", [])
    metadata = {
        "asset": OUTPUT.name,
        "set": "naked",
        "display": "Naked",
        "skeleton": "Armature/Skeleton3D",
        "bone_count": len(bones),
        "bone_names": bones,
        "slots": list(SLOTS),
        "pieces": pieces_meta,
        "total_triangles": total,
        "triangle_budget": TRIANGLE_BUDGET,
        "materials": [material.get("name", "") for material in document.get("materials", [])],
        "embedded_images": len(images),
        "image_mime_types": sorted({image.get("mimeType", "") for image in images}),
        "image_names": [image.get("name", "") for image in images],
        "image_bytes": {image.get("name", ""): image_bytes(document, index)
                        for index, image in enumerate(images)},
        "atlas_size": ATLAS_SIZE,
        "animations": [animation.get("name", "") for animation in document.get("animations", [])],
        "forward": [0, 0, 1],
        "up": [0, 1, 0],
        "bind_axes": "+X is the character's left, -Y forward, +Z up, metres",
        "unit": "metres",
        "body": {
            "source": "Universal Base Characters[Standard] - Superhero_Male_FullBody.gltf",
            "creator": "Quaternius",
            "licence": "CC0 1.0 Universal",
            "skeleton": "same 65-bone rest skeleton as the ranger; weights from the source",
            "skinned_vertices": len(BODY.data.vertices) if BODY else 0,
            "head": "removed at the neck; the ranger head/eyes/brows stay on screen",
        },
        "garments": extras.get("garments", {}),
        "neck_fit": extras.get("neck_fit", {}),
        "torso_fit": extras.get("torso_fit", {}),
        "clearance": extras.get("clearance", {}),
        "authoring_fps": FPS,
        "authoring_tool": "Blender 5.1",
        "source": (
            "body, skin maps and weights: Quaternius Universal Base Characters (CC0); "
            "shirt, shorts, bands, cloth maps and the neck fit: original procedural work "
            "authored by tools/prepare_naked_armor.py"
        ),
        "reproducer": "python tools/build_naked_armor.py",
    }
    path = OUTPUT.with_suffix(".json")
    path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("NAKED_METADATA", path, flush=True)
    return metadata


# ---------------------------------------------------------------------------
# Main


def main() -> None:
    global BODY, BODY_BVH, BODY_NORMALS, HEAD_OBJECTS

    import_scene()
    HEAD_OBJECTS = [name for name in
                    ("Ranger_Head_SuperHero_Male", "Ranger_Head_Eyes", "Ranger_Head_Eyebrows")
                    if name in bpy.data.objects]
    torso = fit_torso()
    neck = fit_neck()
    cut_source_head()
    measure_body()

    faces = slot_faces()
    skin = build_skin_pieces(faces)
    stamp("body")

    shirt, shirt_report = build_shirt()
    shorts, shorts_report = build_shorts()
    stamp("garments")

    shirt_material = dress_garment(shirt, CLOTH_LOOKS["shirt"], "shirt")
    shorts_material = dress_garment(shorts, CLOTH_LOOKS["shorts"], "shorts")
    stamp("cloth")

    # Custom normals: the skin pieces keep the body's own smooth normals, which
    # is what makes the ankle and wrist seams of four separate meshes read as
    # one continuous body.  Garment normals stay their own.
    normals_source = list(BODY_NORMALS)
    skin_counts = {slot: len(skin[slot].data.vertices) for slot in SLOTS}
    # The four skin pieces are copies of one body, so a boundary vertex is
    # present in two meshes; both get the body's normal at that position,
    # which is what keeps the ankle and wrist seams from shading as creases.
    normal_index = KDTree(len(BODY.data.vertices))
    for index, vertex in enumerate(BODY.data.vertices):
        normal_index.insert(vertex.co, index)
    normal_index.balance()

    assemblies: dict[str, list[bpy.types.Object]] = {
        "chest": [skin["chest"], shirt],
        "hands": [skin["hands"]],
        "legs": [skin["legs"], shorts],
        "feet": [skin["feet"]],
    }
    claimed = {slot: sorted({group.name for obj in parts for group in obj.vertex_groups})
               for slot, parts in assemblies.items()}
    pieces: list[bpy.types.Object] = []
    problems: list[str] = []
    gaps: dict[str, dict] = {}

    for slot in SLOTS:
        parts = assemblies[slot]
        sleeve = tuple(part for part in parts if part.data.materials and
                       part.data.materials[0].name in CLOTH_MATERIAL.values())
        for part in sleeve:
            gaps[part.name] = garment_skin_gap(part)
        joined = salvage.join_slot(parts, NODE_NAME[slot])
        skin_count = skin_counts[slot]
        normals = []
        for index, vertex in enumerate(joined.data.vertices):
            if index < skin_count:
                _co, source, _distance = normal_index.find(vertex.co)
                normals.append(normals_source[source])
            else:
                normals.append(vertex.normal.copy())
        try:
            joined.data.normals_split_custom_set_from_vertices(normals)
            joined.data.update()
        except Exception as exc:  # noqa: BLE001 - reported, then the build stops
            problems.append(f"{joined.name}: custom normals failed: {exc}")
        joined.parent = RIG
        joined.matrix_parent_inverse = Matrix.Identity(4)
        modifier = joined.modifiers.new("Armature", "ARMATURE")
        modifier.object = RIG
        modifier.use_vertex_groups = True
        problems.extend(validate_piece(joined, claimed[slot]))
        pieces.append(joined)

    total = sum(sum(len(face.vertices) - 2 for face in piece.data.polygons) for piece in pieces)
    print("NAKED_TRIS", total, "budget", TRIANGLE_BUDGET, flush=True)
    if total > TRIANGLE_BUDGET:
        problems.append(f"triangle budget exceeded: {total} > {TRIANGLE_BUDGET}")

    # The neck must be inside the head's opening, never crossing the face.
    strict = head_meshes()
    clearance: dict = {}
    for piece in pieces:
        clearance[piece.name] = clearance_report(piece, strict, "strict", floor_z=1.600)
        for ref, entry in clearance[piece.name].items():
            if entry["intersections"]:
                problems.append(f"{piece.name}: {entry['intersections']} triangles cross {ref}")

    if problems:
        for problem in problems:
            print("NAKED_ERROR", problem, flush=True)
        raise SystemExit("validation failed")

    print("NAKED_GAPS", {name: value for name, value in gaps.items()}, flush=True)
    garments = {
        "shirt": {"material": shirt_material.name, "hem_z": SHIRT_HEM_Z,
                  "sleeve_end_m": SLEEVE_END, "gap_m": GAP["shirt"],
                  "atlas": ATLAS_SIZE["shirt"], "report": shirt_report},
        "shorts": {"material": shorts_material.name, "hem_z": SHORTS_HEM_Z,
                   "top_z": SHORTS_TOP_Z, "gap_m": GAP["shorts"],
                   "atlas": ATLAS_SIZE["shorts"], "report": shorts_report},
        "weave_m": {key: look["pitch"] for key, look in CLOTH_LOOKS.items()},
        "skin_material": SKIN_MATERIAL,
        "skin_atlas": ATLAS_SIZE["skin"],
    }
    export(pieces)
    metadata = write_metadata(pieces, {"garments": garments, "neck_fit": neck,
                                       "torso_fit": torso,
                                       "clearance": {"strict": clearance, "garment_gap": gaps}})
    stamp("export")
    print("NAKED_DONE", json.dumps({
        "triangles": metadata["total_triangles"],
        "bones": metadata["bone_count"],
        "images": metadata["embedded_images"],
        "image_bytes": metadata["image_bytes"],
        "pieces": {name: meta["triangles"] for name, meta in metadata["pieces"].items()},
    }, indent=2))


if __name__ == "__main__":
    main()
