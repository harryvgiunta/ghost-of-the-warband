"""Fit the three Unholy Forest watchers onto the warband's own humanoid rig.

The camp's watchers are the wood's creatures - the Hollow warden, the Ossuary
stalker and the Gallowsroot - but they fight the warband the way the warband
fights: on the ranger's 65-bone skeleton, with the ranger's authored walk, run,
swing, guard, flinch and fall. This script turns each shipped creature mesh into
a whole-body skin for that skeleton:

    Watcher_HollowWarden    the hooded grave-cloth, void, ember eyes, antler rack
    Watcher_OssuaryStalker  the fitted tunic, bone mask, bracers, lashed antlers
    Watcher_Gallowsroot     the long coat, bark plates, wooden mask, branch crown

Nothing is remodelled. The creature's own vertices, UVs and material slots are
carried across; only where they sit and which bones they follow changes:

1.  Both GLBs are imported. The creature is turned to the ranger's facing and
    scaled by ``1 / fit_scale``, where ``fit_scale`` is the creature's neck
    height over the ranger's: the runtime scales the rig back up by the same
    number, so a watcher stands exactly as tall as the creature it was.
2.  The ranger's arms are posed onto the creature's hanging arms (clavicle,
    upper arm, forearm, hand). That pose is the **bind**: the skin is weighted
    in it and exported with a skeleton whose rest *is* it, so the inverse bind
    matrices describe a body standing the way the creature was authored and the
    ranger's own clips swing it from there - no T-pose round trip through the
    sleeves and the hood.
3.  Every creature bone gets one affine fit onto its ranger counterpart: the
    segment from its head to the next joint is translated onto the ranger
    segment, turned onto its direction and stretched along it, so torso, arms
    and legs meet the ranger's joints exactly. The neck, head, jaw and crown
    are carried rigidly on the neck's own anchor (the hood keeps its height and
    the antlers their size), the claws ride the hand rigidly, and the robe and
    shroud fans follow the thigh fits so a hem stays a hem. A vertex moves by
    the blend of its own bones' fits; normals by the inverse transpose of the
    same blend.
4.  Weights are the creature's own, renamed onto ranger bones (the fans onto
    the thighs, the claws onto the proximal finger bones, the crown onto the
    head), limited to four influences and renormalised.

The skin is exported without images: its surfaces keep the creature's material
names, and ``scripts/archer.gd`` dresses them with the shipped creature GLB's
own materials at runtime, so the PBR atlases exist once on disk.

Usage (Blender 5.1+):
    blender --background --python-exit-code 1 --python tools/prepare_watcher_skins.py -- \
        [hollow_warden|ossuary_stalker|gallowsroot ...] [--no-captures]

or ``python tools/build_watcher_skins.py all``. Captures (bind pose beside the
source creature, then the ranger's own idle, walk, run, swings, guard and
crouch) land in ignored ``.runtime/watcher-skins/<species>/captures/``.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent.parent
RANGER = ROOT / "assets" / "characters" / "ironwood_ranger.glb"
FOREST = ROOT / "assets" / "characters" / "forest"
OUTPUT = ROOT / "assets" / "characters" / "watchers"
WORKSPACE = ROOT / ".runtime" / "watcher-skins"

SPECIES = {
    "hollow_warden": {
        "node": "Watcher_HollowWarden",
        "display": "Hollow warden",
        "skirt": "robe",
    },
    "ossuary_stalker": {
        "node": "Watcher_OssuaryStalker",
        "display": "Ossuary stalker",
        "skirt": "shroud",
    },
    "gallowsroot": {
        "node": "Watcher_Gallowsroot",
        "display": "Gallowsroot",
        "skirt": "",
    },
}
ORDER = ("hollow_warden", "ossuary_stalker", "gallowsroot")

## The joint whose height sets the fit scale: the base of the neck, so a skin
## stands to the creature's own height with its head and crown unscaled.
SCALE_JOINT = ("neck_01", "neck_01")
## Stretch bounds: a segment is never fitted past these, whatever the rigs say.
STRETCH_MIN = 0.40
STRETCH_MAX = 2.50
## Influences kept per vertex (Godot skins and the glTF exporter both read four).
MAX_INFLUENCES = 4
WEIGHT_FLOOR = 0.002
## Robe and shroud fans: how much of a side fan follows its own thigh, and how
## much of the front and back panels follows the two thighs together. The rest
## stays on the pelvis.
SKIRT_SIDE_THIGH = 0.62
SKIRT_PANEL_THIGHS = 0.50

## Creature bone -> (ranger bone, creature segment end, ranger segment end).
## `{s}` is the creature's side suffix, `{S}` the ranger side it lands on after
## the turn (resolved from the joint's position, not from the name). An end of
## "palm" is the mean of the finger roots; "tail" is the bone's own tail.
SEGMENTS = {
    "pelvis": ("pelvis", "spine_01", "spine_01"),
    "spine_01": ("spine_01", "spine_02", "spine_02"),
    "spine_02": ("spine_02", "chest", "spine_03"),
    "chest": ("spine_03", "neck_01", "neck_01"),
    "clavicle_{s}": ("clavicle_{S}", "upper_arm_{s}", "upperarm_{S}"),
    "upper_arm_{s}": ("upperarm_{S}", "lower_arm_{s}", "lowerarm_{S}"),
    "lower_arm_{s}": ("lowerarm_{S}", "hand_{s}", "hand_{S}"),
    "hand_{s}": ("hand_{S}", "palm", "palm"),
    "thigh_{s}": ("thigh_{S}", "shin_{s}", "calf_{S}"),
    "shin_{s}": ("calf_{S}", "foot_{s}", "foot_{S}"),
    "foot_{s}": ("foot_{S}", "toe_{s}", "ball_{S}"),
    "toe_{s}": ("ball_{S}", "tail", "ball_leaf_{S}"),
}
## Ranger bones the bind pose turns onto the creature, parent first. The legs
## and the spine keep the ranger's own rest: the costume is fitted onto them.
BIND_CHAIN = ("clavicle_{S}", "upperarm_{S}", "lowerarm_{S}", "hand_{S}")
## Carried rigidly on the neck's anchor: the hood keeps its height above the
## shoulders and the crown its size.
HEAD_CHAIN = ("neck_01", "neck_02", "head", "jaw")
CROWN_PREFIXES = ("antler_", "crown_")
FINGERS = {"1": "index_01_{S}", "2": "middle_01_{S}", "3": "ring_01_{S}"}
PALM_FINGERS = ("index_01_{S}", "middle_01_{S}", "ring_01_{S}", "pinky_01_{S}")

## Where each creature bone's weight goes on the ranger. Values are shares.
WEIGHT_MAP = {
    "root": {"pelvis": 1.0},
    "pelvis": {"pelvis": 1.0},
    "spine_01": {"spine_01": 1.0},
    "spine_02": {"spine_02": 1.0},
    "chest": {"spine_03": 1.0},
    "neck_01": {"neck_01": 1.0},
    "neck_02": {"neck_01": 0.5, "Head": 0.5},
    "head": {"Head": 1.0},
    "jaw": {"Head": 1.0},
    "clavicle_{s}": {"clavicle_{S}": 1.0},
    "upper_arm_{s}": {"upperarm_{S}": 1.0},
    "lower_arm_{s}": {"lowerarm_{S}": 1.0},
    "hand_{s}": {"hand_{S}": 1.0},
    "thigh_{s}": {"thigh_{S}": 1.0},
    "shin_{s}": {"calf_{S}": 1.0},
    "foot_{s}": {"foot_{S}": 1.0},
    "toe_{s}": {"ball_{S}": 1.0},
}

CAPTURE_POSES = (
    ("idle", "Idle_Loop", 0.30),
    ("walk_a", "Walk_Loop", 0.25),
    ("walk_b", "Walk_Loop", 0.75),
    ("run", "Jog_Fwd_Loop", 0.30),
    ("overhead_load", "Sword_Overhead_OneHand", 0.30),
    ("overhead_strike", "Sword_Overhead_OneHand", 0.48),
    ("guard", "Sword_Block_Loop_OneHand", 0.40),
    ("stab", "Dagger_Stab", 0.45),
    ("crouch", "Crouch_Idle_Loop", 0.30),
)


def log(*parts) -> None:
    print("WS_" + str(parts[0]), *parts[1:], flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 60
    scene.render.fps_base = 1.0


def import_glb(path: Path) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    added = [obj for obj in bpy.data.objects if obj not in before]
    # The importer's custom bone shape is scene clutter, never content.
    for obj in list(added):
        if obj.type == "MESH" and obj.parent is None and obj.name.startswith("Icosphere"):
            added.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
    rig = next(obj for obj in added if obj.type == "ARMATURE")
    meshes = [obj for obj in added if obj.type == "MESH"]
    if rig.animation_data:
        rig.animation_data.action = None
    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return rig, meshes


def hierarchy(rig: bpy.types.Object) -> list[str]:
    ordered: list[str] = []
    pending = [bone for bone in rig.data.bones if bone.parent is None]
    while pending:
        bone = pending.pop(0)
        ordered.append(bone.name)
        pending.extend(bone.children)
    return ordered


def side_of(point: Vector) -> str:
    """Ranger side for a point in ranger space: +X is the character's left."""
    return "l" if point.x > 0.0 else "r"


class Creature:
    """The source creature's rest skeleton, turned and scaled into ranger space."""

    def __init__(self, rig: bpy.types.Object, mesh: bpy.types.Object, fit_scale: float):
        self.rig = rig
        self.mesh = mesh
        self.fit_scale = fit_scale
        # The creature faces +Y in Blender and the ranger -Y: a half turn about Z,
        # then the uniform scale that the runtime will give back.
        self.turn = Matrix.Scale(1.0 / fit_scale, 4) @ Matrix.Rotation(math.pi, 4, "Z")
        self.heads: dict[str, Vector] = {}
        self.tails: dict[str, Vector] = {}
        for bone in rig.data.bones:
            self.heads[bone.name] = self.turn @ (rig.matrix_world @ bone.head_local)
            self.tails[bone.name] = self.turn @ (rig.matrix_world @ bone.tail_local)
        self.names = [bone.name for bone in rig.data.bones]


def resolve(template: str, creature_side: str, ranger_side: str) -> str:
    return template.replace("{s}", creature_side).replace("{S}", ranger_side)


def match_template(name: str, templates) -> tuple[str, str] | None:
    """The template a sided or plain creature bone name instantiates."""
    for template in templates:
        if "{s}" not in template:
            if template == name:
                return template, ""
            continue
        for side in "lr":
            if template.replace("{s}", side) == name:
                return template, side
    return None


# --- the bind pose ----------------------------------------------------------

def solve_bind(ranger: bpy.types.Object, creature: Creature) -> tuple[dict, dict]:
    """Ranger armature-space matrices with the arms turned onto the creature's.

    Returns (posed matrices, matrix_basis per bone). Only `BIND_CHAIN` turns;
    every other bone inherits its parent's motion and keeps its rest otherwise.
    """
    rest = {bone.name: bone.matrix_local.copy() for bone in ranger.data.bones}
    parent = {bone.name: (bone.parent.name if bone.parent else "") for bone in ranger.data.bones}
    targets: dict[str, tuple[Vector, Vector]] = {}
    for side_c in "lr":
        hand = f"hand_{side_c}"
        if hand not in creature.heads:
            continue
        side_r = side_of(creature.heads[hand])
        chain = {
            "clavicle_{S}": (f"clavicle_{side_c}", f"upper_arm_{side_c}", "upperarm_{S}"),
            "upperarm_{S}": (f"upper_arm_{side_c}", f"lower_arm_{side_c}", "lowerarm_{S}"),
            "lowerarm_{S}": (f"lower_arm_{side_c}", f"hand_{side_c}", "hand_{S}"),
            "hand_{S}": (f"hand_{side_c}", "palm", "palm"),
        }
        for template in BIND_CHAIN:
            start_c, end_c, end_r = chain[template]
            head_c = creature.heads[start_c]
            tail_c = creature_palm(creature, side_c) if end_c == "palm" else creature.heads[end_c]
            name_r = resolve(template, side_c, side_r)
            if end_r == "palm":
                joint_rest = sum((rest[resolve(f, side_c, side_r)].translation
                                  for f in PALM_FINGERS), Vector()) / len(PALM_FINGERS)
            else:
                joint_rest = rest[resolve(end_r, side_c, side_r)].translation.copy()
            targets[name_r] = (joint_rest, (tail_c - head_c).normalized())
    posed: dict[str, Matrix] = {}
    basis: dict[str, Matrix] = {}
    for name in hierarchy(ranger):
        if parent[name]:
            inherited = posed[parent[name]] @ rest[parent[name]].inverted() @ rest[name]
        else:
            inherited = rest[name].copy()
        matrix = inherited
        if name in targets:
            joint_rest, wanted = targets[name]
            local_joint = rest[name].inverted() @ joint_rest
            current = (inherited @ local_joint) - inherited.translation
            turn = current.normalized().rotation_difference(wanted).to_matrix()
            rotation = turn @ inherited.to_3x3()
            matrix = Matrix.Translation(inherited.translation) @ rotation.to_4x4()
        posed[name] = matrix
        basis[name] = inherited.inverted() @ matrix
    return posed, basis


def creature_palm(creature: Creature, side_c: str) -> Vector:
    """Mean of the claw roots: `finger_<side>_<n>`."""
    roots = [creature.heads[name] for name in creature.names
             if name.startswith("finger_") and name.split("_")[1] == side_c]
    if not roots:
        return creature.tails[f"hand_{side_c}"]
    return sum(roots, Vector()) / len(roots)


def ranger_palm(posed: dict, side_r: str) -> Vector:
    return sum((posed[f.replace("{S}", side_r)].translation for f in PALM_FINGERS), Vector()) \
        / len(PALM_FINGERS)


# --- the fit ------------------------------------------------------------------

class Fit:
    """One affine map from creature rest space onto the ranger's bind pose."""

    def __init__(self, origin_c: Vector, origin_r: Vector, linear: Matrix, stretch: float = 1.0,
                 label: str = ""):
        self.origin_c = np.array(origin_c, dtype=np.float64)
        self.origin_r = np.array(origin_r, dtype=np.float64)
        self.linear = np.array(linear, dtype=np.float64).reshape(3, 3)
        self.stretch = stretch
        self.label = label

    def apply(self, points: np.ndarray) -> np.ndarray:
        return self.origin_r + (points - self.origin_c) @ self.linear.T

    def at(self, point: Vector) -> Vector:
        return Vector(self.apply(np.array([point], dtype=np.float64))[0])

    @staticmethod
    def blend(fits: list[tuple["Fit", float]], label: str) -> "Fit":
        """A weighted mean of maps, expressed as one map about the first origin."""
        base = np.array(fits[0][0].origin_c)
        offset = np.zeros(3)
        linear = np.zeros((3, 3))
        for fit, share in fits:
            offset += share * fit.apply(base[None, :])[0]
            linear += share * fit.linear
        out = Fit(Vector(base), Vector(offset), Matrix(linear.tolist()), 1.0, label)
        return out


def segment_fit(head_c: Vector, tail_c: Vector, head_r: Vector, tail_r: Vector,
                label: str) -> Fit:
    span_c = tail_c - head_c
    span_r = tail_r - head_r
    length_c = max(span_c.length, 1.0e-5)
    length_r = max(span_r.length, 1.0e-5)
    stretch = min(max(length_r / length_c, STRETCH_MIN), STRETCH_MAX)
    axis = span_c / length_c
    turn = axis.rotation_difference(span_r / length_r).to_matrix()
    along = np.outer(np.array(axis), np.array(axis))
    linear = np.array(turn) @ (np.eye(3) + (stretch - 1.0) * along)
    return Fit(head_c, head_r, Matrix(linear.tolist()), stretch, label)


def build_fits(creature: Creature, posed: dict, skirt: str) -> dict[str, Fit]:
    fits: dict[str, Fit] = {}
    heads_r = {name: matrix.translation.copy() for name, matrix in posed.items()}
    # Segment bones: torso, arms, legs.
    for name in creature.names:
        found = match_template(name, SEGMENTS.keys())
        if found is None:
            continue
        template, side_c = found
        side_r = side_of(creature.heads[name]) if side_c else ""
        ranger_bone, end_c, end_r = SEGMENTS[template]
        ranger_bone = resolve(ranger_bone, side_c, side_r)
        head_c = creature.heads[name]
        if end_c == "palm":
            tail_c = creature_palm(creature, side_c)
            tail_r = ranger_palm(posed, side_r)
        elif end_c == "tail":
            tail_c = creature.tails[name]
            tail_r = heads_r[resolve(end_r, side_c, side_r)]
        else:
            tail_c = creature.heads[resolve(end_c, side_c, side_r)]
            tail_r = heads_r[resolve(end_r, side_c, side_r)]
        fits[name] = segment_fit(head_c, tail_c, heads_r[ranger_bone], tail_r, name)
    # The head chain rides the neck's anchor rigidly.
    anchor_c = creature.heads["neck_01"]
    anchor_r = heads_r["neck_01"]
    head_fit = Fit(anchor_c, anchor_r, Matrix.Identity(3), 1.0, "head_chain")
    for name in creature.names:
        if name in HEAD_CHAIN or name.startswith(CROWN_PREFIXES):
            fits[name] = head_fit
    # Claws ride the hand rigidly from their own root.
    for name in creature.names:
        if not name.startswith("finger_"):
            continue
        side_c = name.split("_")[1]
        hand = fits[f"hand_{side_c}"]
        root_c = creature.heads[name]
        root_r = hand.at(root_c)
        turn = Matrix(hand.linear.tolist())
        # Strip the hand's stretch: the claw keeps its own length.
        u, _, vt = np.linalg.svd(np.array(turn))
        rigid = Matrix((u @ vt).tolist())
        fits[name] = Fit(root_c, root_r, rigid, 1.0, name)
    # Robe and shroud fans follow the thighs: a side fan its own leg, the front
    # and back fans both legs evenly, so the hem stays where the legs put it.
    thighs = {}
    for name in creature.names:
        if name.startswith("thigh_"):
            thighs[side_of(creature.heads[name])] = fits[name]
    for name in creature.names:
        if skirt and name.startswith(skirt + "_"):
            key = name[len(skirt) + 1]
            if key in "lr":
                ranger_side = side_of(creature.heads[name] + creature.tails[name])
                fits[name] = thighs[ranger_side]
            else:
                fits[name] = Fit.blend([(thighs["l"], 0.5), (thighs["r"], 0.5)], name)
    fits["root"] = fits["pelvis"]
    missing = [name for name in creature.names if name not in fits]
    if missing:
        raise SystemExit(f"no fit for creature bones {missing}")
    return fits


def weight_targets(creature: Creature, skirt: str) -> dict[str, dict[str, float]]:
    out: dict[str, dict[str, float]] = {}
    for name in creature.names:
        if name in WEIGHT_MAP:
            out[name] = dict(WEIGHT_MAP[name])
            continue
        if name.startswith(CROWN_PREFIXES):
            out[name] = {"Head": 1.0}
            continue
        if name.startswith("finger_"):
            _, side_c, index = name.split("_")
            side_r = side_of(creature.heads[name])
            out[name] = {FINGERS.get(index, "middle_01_{S}").replace("{S}", side_r): 1.0}
            continue
        if skirt and name.startswith(skirt + "_"):
            # A hem hangs from the hips: a side fan swings with its own leg
            # but stays partly on the pelvis, and the front and back panels
            # sit between both legs, so a stride parts the robe instead of
            # dragging the whole hem along with one thigh.
            key = name[len(skirt) + 1]
            if key in "lr":
                side_r = side_of(creature.heads[name] + creature.tails[name])
                out[name] = {f"thigh_{side_r}": SKIRT_SIDE_THIGH,
                             "pelvis": 1.0 - SKIRT_SIDE_THIGH}
            else:
                share = SKIRT_PANEL_THIGHS * 0.5
                out[name] = {"thigh_l": share, "thigh_r": share,
                             "pelvis": 1.0 - SKIRT_PANEL_THIGHS}
            continue
        found = match_template(name, WEIGHT_MAP.keys())
        if found is not None:
            template, side_c = found
            side_r = side_of(creature.heads[name])
            out[name] = {resolve(k, side_c, side_r): v for k, v in WEIGHT_MAP[template].items()}
            continue
        raise SystemExit(f"no weight target for creature bone {name}")
    return out


# --- the skin -----------------------------------------------------------------

def creature_weights(mesh_obj: bpy.types.Object, names: list[str]) -> np.ndarray:
    index_of = {group.index: names.index(group.name) for group in mesh_obj.vertex_groups
                if group.name in names}
    weights = np.zeros((len(mesh_obj.data.vertices), len(names)), dtype=np.float64)
    for vertex in mesh_obj.data.vertices:
        for element in vertex.groups:
            column = index_of.get(element.group)
            if column is not None:
                weights[vertex.index, column] += element.weight
    totals = weights.sum(axis=1)
    orphan = totals <= 1.0e-8
    if orphan.any():
        weights[orphan, names.index("pelvis")] = 1.0
        totals = weights.sum(axis=1)
    return weights / totals[:, None]


def fit_mesh(mesh_obj: bpy.types.Object, creature: Creature, fits: dict[str, Fit]) -> tuple:
    mesh = mesh_obj.data
    count = len(mesh.vertices)
    source = np.zeros(count * 3, dtype=np.float64)
    mesh.vertices.foreach_get("co", source)
    source = source.reshape(count, 3)
    world = np.array(mesh_obj.matrix_world, dtype=np.float64)
    turn = np.array(creature.turn, dtype=np.float64)
    full = turn @ world
    points = source @ full[:3, :3].T + full[:3, 3]
    weights = creature_weights(mesh_obj, creature.names)
    fitted = np.zeros_like(points)
    jacobian = np.zeros((count, 3, 3), dtype=np.float64)
    for column, name in enumerate(creature.names):
        share = weights[:, column]
        used = share > 0.0
        if not used.any():
            continue
        fit = fits[name]
        fitted[used] += share[used, None] * fit.apply(points[used])
        jacobian[used] += share[used, None, None] * fit.linear[None, :, :]
    # Normals: the imported corner normals, carried by the inverse transpose of
    # the turn and of each vertex's blended fit (row vectors: n @ inverse).
    loops = len(mesh.loops)
    corner = np.zeros(loops * 3, dtype=np.float64)
    mesh.corner_normals.foreach_get("vector", corner)
    corner = corner.reshape(loops, 3) @ np.linalg.inv(full[:3, :3])
    vertex_of = np.zeros(loops, dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", vertex_of)
    inverse_t = np.transpose(np.linalg.inv(jacobian), (0, 2, 1))
    normals = np.einsum("lij,lj->li", inverse_t[vertex_of], corner)
    normals /= np.maximum(np.linalg.norm(normals, axis=1), 1.0e-9)[:, None]
    return fitted, normals, weights, points


def map_weights(weights: np.ndarray, creature: Creature, skirt: str,
                ranger_names: list[str]) -> np.ndarray:
    targets = weight_targets(creature, skirt)
    table = np.zeros((len(creature.names), len(ranger_names)), dtype=np.float64)
    for row, name in enumerate(creature.names):
        for bone, share in targets[name].items():
            if bone not in ranger_names:
                raise SystemExit(f"weight target {bone} is not a ranger bone")
            table[row, ranger_names.index(bone)] += share
    mapped = weights @ table
    # Four influences, renormalised; the smallest shares go first.
    order = np.argsort(-mapped, axis=1)
    keep = np.zeros_like(mapped, dtype=bool)
    rows = np.arange(mapped.shape[0])[:, None]
    keep[rows, order[:, :MAX_INFLUENCES]] = True
    mapped = np.where(keep & (mapped >= WEIGHT_FLOOR), mapped, 0.0)
    totals = mapped.sum(axis=1)
    fallback = totals <= 1.0e-9
    if fallback.any():
        raise SystemExit(f"{int(fallback.sum())} vertices lost every influence")
    return mapped / totals[:, None]


def build_export_rig(ranger: bpy.types.Object, basis: dict) -> bpy.types.Object:
    rig = ranger.copy()
    rig.data = ranger.data.copy()
    rig.animation_data_clear()
    rig.name = "Armature"
    rig.data.name = "Armature"
    bpy.context.scene.collection.objects.link(rig)
    for name, matrix in basis.items():
        rig.pose.bones[name].matrix_basis = matrix
    bpy.context.view_layer.update()
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return rig


def build_skin(creature: Creature, rig: bpy.types.Object, node: str, fitted: np.ndarray,
               normals: np.ndarray, mapped: np.ndarray, ranger_names: list[str]) -> bpy.types.Object:
    source = creature.mesh
    data = source.data.copy()
    data.name = node
    skin = bpy.data.objects.new(node, data)
    bpy.context.scene.collection.objects.link(skin)
    skin.matrix_world = Matrix.Identity(4)
    data.vertices.foreach_set("co", fitted.astype(np.float32).ravel())
    data.update()
    data.normals_split_custom_set([tuple(n) for n in normals.astype(np.float32)])
    skin.vertex_groups.clear()
    groups = {name: skin.vertex_groups.new(name=name) for name in ranger_names}
    columns = np.nonzero(mapped.sum(axis=0) > 0.0)[0]
    for column in columns:
        group = groups[ranger_names[column]]
        rows = np.nonzero(mapped[:, column] > 0.0)[0]
        values = mapped[rows, column]
        # Batch identical weights: one call per distinct value keeps this fast.
        rounded = np.round(values, 4)
        for value in np.unique(rounded):
            members = rows[rounded == value]
            group.add(members.tolist(), float(value), "REPLACE")
    skin.parent = rig
    skin.matrix_parent_inverse = Matrix.Identity(4)
    modifier = skin.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    modifier.use_vertex_groups = True
    return skin


def export(rig: bpy.types.Object, skin: bpy.types.Object, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    rig.select_set(True)
    skin.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
    )


def glb_document(path: Path) -> dict:
    raw = path.read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20: 20 + length])


def write_metadata(species: str, path: Path, source: Path, creature: Creature,
                   fits: dict[str, Fit], skin: bpy.types.Object, fitted: np.ndarray,
                   points: np.ndarray, mapped: np.ndarray, ranger_names: list[str]) -> dict:
    document = glb_document(path)
    skin_doc = document["skins"][0]
    nodes = document["nodes"]
    joints = [nodes[index].get("name", "") for index in skin_doc["joints"]]
    triangles = sum(len(polygon.vertices) - 2 for polygon in skin.data.polygons)
    scale = creature.fit_scale
    lo = fitted.min(axis=0)
    hi = fitted.max(axis=0)
    used = [ranger_names[column] for column in np.nonzero(mapped.sum(axis=0) > 0.0)[0]]
    stretch = {name: round(fit.stretch, 4) for name, fit in sorted(fits.items())
               if abs(fit.stretch - 1.0) > 1.0e-6}
    metadata = {
        "asset": path.name,
        "species": species,
        "display": SPECIES[species]["display"],
        "node": SPECIES[species]["node"],
        "skeleton": "Armature/Skeleton3D",
        "bone_count": len(joints),
        "joints": joints,
        "deforming_bones": used,
        "unit": "metres",
        "forward": [0, 0, 1],
        "up": [0, 1, 0],
        "fit_scale": round(scale, 4),
        "fit_scale_rule": "creature neck_01 head height / ranger neck_01 head height",
        "bind": "ranger rest with clavicle, upper arm, forearm and hand turned onto the creature's rest arms",
        "segment_stretch": stretch,
        # Blender Z-up armature space -> glTF/Godot Y-up: (x, y, z) -> (x, z, -y).
        "bind_bounds_min": [round(float(lo[0]), 4), round(float(lo[2]), 4), round(float(-hi[1]), 4)],
        "bind_bounds_max": [round(float(hi[0]), 4), round(float(hi[2]), 4), round(float(-lo[1]), 4)],
        "runtime_height": round(float(hi[2]) * scale, 4),
        "source_height": round(float(points[:, 2].max()) * scale, 4),
        "mesh_triangles": triangles,
        "mesh_vertices": len(skin.data.vertices),
        "max_influences": MAX_INFLUENCES,
        "materials": [material.name for material in skin.data.materials if material is not None],
        "materials_from": "res://assets/characters/forest/" + source.name,
        "embedded_images": len(document.get("images", [])),
        "source": "Original procedural work: the shipped " + source.name + " mesh, UVs and "
                  "material slots refitted onto ironwood_ranger.glb's skeleton by "
                  "tools/prepare_watcher_skins.py. No third-party model, texture or motion.",
        "source_sha256": {source.name: sha256(source), RANGER.name: sha256(RANGER)},
        "reproducer": f"python tools/build_watcher_skins.py {species}",
    }
    path.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return metadata


# --- captures -----------------------------------------------------------------

def copy_pose(source: bpy.types.Object, target: bpy.types.Object) -> None:
    """Pose `target` so every bone has `source`'s armature-space matrix.

    The two rigs share bone names but not rests (the target's rest is the bind),
    so matrix_basis is solved per bone from the parent's already-copied pose.
    """
    rest = {bone.name: bone.matrix_local.copy() for bone in target.data.bones}
    for name in hierarchy(target):
        bone = target.data.bones[name]
        wanted = source.pose.bones[name].matrix.copy()
        if bone.parent:
            parent_pose = source.pose.bones[bone.parent.name].matrix
            inherited = parent_pose @ rest[bone.parent.name].inverted() @ rest[name]
        else:
            inherited = rest[name]
        target.pose.bones[name].matrix_basis = inherited.inverted() @ wanted
    bpy.context.view_layer.update()


def capture(species: str, ranger: bpy.types.Object, rig: bpy.types.Object,
            skin: bpy.types.Object, creature: Creature) -> Path:
    folder = WORKSPACE / species / "captures"
    folder.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scale = creature.fit_scale
    rig.scale = (scale, scale, scale)
    # The source creature, unscaled and turned to the same facing, a stride away.
    creature.rig.matrix_world = Matrix.Translation((1.5, 0.0, 0.0)) @ Matrix.Rotation(math.pi, 4, "Z")
    for pose_bone in creature.rig.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = False
    scene.render.resolution_x = 800
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    height = max(3.0, float(creature.heads["neck_01"].z) * scale * 2.35)
    cameras = {}
    for view, direction in {"front": Vector((0.0, -1.0, 0.0)), "side": Vector((-1.0, 0.0, 0.0))}.items():
        data = bpy.data.cameras.new("Capture_" + view)
        data.type = "ORTHO"
        data.ortho_scale = height
        camera = bpy.data.objects.new("Capture_" + view, data)
        scene.collection.objects.link(camera)
        focus = Vector((0.75 if view == "front" else 0.0, 0.0, height * 0.48))
        camera.location = focus + direction * 9.0
        camera.rotation_euler = (focus - camera.location).to_track_quat("-Z", "Y").to_euler()
        cameras[view] = camera
    written = []

    def shoot(label: str, show_source: bool) -> None:
        creature.mesh.hide_render = not show_source
        for shading, suffix in (("TEXTURE", ""), ("SINGLE", "_form")):
            scene.display.shading.color_type = shading
            if shading == "SINGLE":
                scene.display.shading.single_color = (0.66, 0.64, 0.60)
            for view, camera in cameras.items():
                if view == "side" and show_source:
                    continue
                scene.camera = camera
                target = folder / f"{label}_{view}{suffix}.png"
                scene.render.filepath = str(target)
                bpy.ops.render.render(write_still=True)
                written.append(target)

    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    shoot("bind", True)
    if ranger.animation_data is None:
        ranger.animation_data_create()
    for label, clip, share in CAPTURE_POSES:
        action = bpy.data.actions.get(clip)
        if action is None:
            log("CAPTURE_SKIP", clip)
            continue
        ranger.animation_data.action = action
        if getattr(action, "slots", None):
            ranger.animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        scene.frame_set(int(round(start + (end - start) * share)))
        bpy.context.view_layer.update()
        copy_pose(ranger, rig)
        shoot(label, False)
    ranger.animation_data.action = None
    log("CAPTURES", folder, len(written))
    return folder


# --- main ---------------------------------------------------------------------

def build(species: str, captures: bool) -> dict:
    spec = SPECIES[species]
    source = FOREST / f"ironwood_{species}.glb"
    output = OUTPUT / f"ironwood_watcher_{species}.glb"
    reset_scene()
    ranger, ranger_meshes = import_glb(RANGER)
    ranger.name = "RangerSource"
    for obj in ranger_meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
    ranger_names = [bone.name for bone in ranger.data.bones]
    creature_rig, creature_meshes = import_glb(source)
    creature_rig.name = "CreatureSource"
    if len(creature_meshes) != 1:
        raise SystemExit(f"{source.name}: expected one skinned mesh, found {len(creature_meshes)}")
    rest_r = {bone.name: bone.head_local.copy() for bone in ranger.data.bones}
    neck_c = creature_rig.data.bones[SCALE_JOINT[0]].head_local
    fit_scale = float(neck_c.z) / float(rest_r[SCALE_JOINT[1]].z)
    creature = Creature(creature_rig, creature_meshes[0], fit_scale)
    log("BEGIN", species, "fit_scale", round(fit_scale, 4))
    posed, basis = solve_bind(ranger, creature)
    fits = build_fits(creature, posed, spec["skirt"])
    for name, fit in sorted(fits.items()):
        if abs(fit.stretch - 1.0) > 1.0e-6:
            log("STRETCH", name, round(fit.stretch, 3))
    fitted, normals, weights, points = fit_mesh(creature.mesh, creature, fits)
    mapped = map_weights(weights, creature, spec["skirt"], ranger_names)
    rig = build_export_rig(ranger, basis)
    skin = build_skin(creature, rig, spec["node"], fitted, normals, mapped, ranger_names)
    export(rig, skin, output)
    metadata = write_metadata(species, output, source, creature, fits, skin, fitted, points,
                              mapped, ranger_names)
    log("EXPORTED", output, "tris", metadata["mesh_triangles"], "bones", metadata["bone_count"],
        "height", metadata["runtime_height"])
    if captures:
        capture(species, ranger, rig, skin, creature)
    return metadata


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    captures = "--no-captures" not in argv
    wanted = [arg for arg in argv if not arg.startswith("--")] or list(ORDER)
    for species in wanted:
        if species not in SPECIES:
            raise SystemExit(f"unknown watcher species {species}")
    results = {species: build(species, captures) for species in wanted}
    log("DONE", json.dumps({name: {"tris": meta["mesh_triangles"], "scale": meta["fit_scale"],
                                   "height": meta["runtime_height"]}
                            for name, meta in results.items()}))


if __name__ == "__main__":
    main()
