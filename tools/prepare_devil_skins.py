"""Fit the frontier devils onto the warband's own humanoid rig.

The devils fought like puppets on strings: six creature clips at a coarse clock,
which read as stop-motion the moment one of them closed on a ranger. This script
turns a devil's own mesh into a whole-body skin for the ranger's 65-bone
skeleton, exactly the way ``tools/prepare_watcher_skins.py`` does it for the
wood's wardens - the creature *is* the body, and the motion is a human's
authored idle, walk, run, swing, guard, flinch and fall:

    Devil_HellGoat    the goat man's hide, skull, horns and hooves
    Devil_Succubus    the winged hide, hair, horns and leather
    Devil_Spawn       the crouched little devil: hide, horns, rags
    Devil_Gargoyle    the carved stone body, wings and ember eyes

Nothing is remodelled. The creature's own vertices, UVs and material slots are
carried across; only where they sit and which bones they follow changes:

1.  Both GLBs are imported. The creature is turned to the ranger's facing and
    scaled by ``1 / fit_scale``, where ``fit_scale`` is the creature's neck
    height over the ranger's: the runtime scales the rig back up by the same
    number, so a devil stands exactly as tall as the creature it was.
2.  Proxy surfaces the fitted body does not want are struck first. The goat's
    ``Fur_HellGoat`` is a separate black shell of spike geometry standing in for
    a coat; on a fitted skin it reads as fur made of thorns, so its faces are
    deleted and the body wears the strand tile from ``tools/devil_fur.py``
    instead.
3.  The ranger's arms are posed onto the creature's rest arms (clavicle, upper
    arm, forearm, hand). That pose is the **bind**: the skin is weighted in it and
    exported with a skeleton whose rest *is* it, so the inverse bind matrices
    describe a body standing the way the creature was authored and the ranger's
    own clips swing it from there.
4.  Every creature bone gets one affine fit onto its ranger counterpart: the
    segment from its head to the next joint is translated onto the ranger
    segment, turned onto its direction and stretched along it. The devils use the
    ranger's own joint names, so most fits are that bone onto itself; the neck,
    skull and jaw are carried rigidly on the neck's anchor, the claws ride the
    hand rigidly, and anything else the rig carries (a wing root, a tail, a hair
    bone) rides its nearest fitted ancestor.
5.  Weights are the creature's own, renamed onto ranger bones - the same bone
    where the ranger has one, the nearest ancestor's target otherwise - limited
    to four influences and renormalised.

The skin is exported without images: its surfaces keep the creature's material
names, and ``scripts/devil_mob_visual.gd`` dresses them with the shipped
creature GLB's own materials at runtime (the goat's body also takes the fur
tile), so the PBR atlases exist once on disk.

Usage (Blender 5.1+):
    blender --background --python-exit-code 1 --python tools/prepare_devil_skins.py -- \
        [hell_goat|succubus|spawn|gargoyle ...] [--no-captures]

or ``python tools/build_devil_skins.py all``. Captures (bind pose beside the
source creature, then the ranger's own idle, walk, run, swings, guard and crouch)
land in ignored ``.runtime/devil-skins/<mob>/captures/``.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_watcher_skins as Watcher

ROOT = Path(__file__).resolve().parent.parent
RANGER = ROOT / "assets" / "characters" / "ironwood_ranger.glb"
DEVILS = ROOT / "assets" / "characters" / "devils"
OUTPUT = DEVILS / "fitted"
WORKSPACE = ROOT / ".runtime" / "devil-skins"
FUR = DEVILS / "ironwood_devil_fur.png"

SPECIES = {
    "hell_goat": {
        "node": "Devil_HellGoat",
        "display": "Hellish goat man",
        # The spike coat standing in for fur: removed, and worn as a tile instead.
        "strip": ("Fur_HellGoat",),
        "fur_material": "Skin_HellGoat",
    },
    "succubus": {
        "node": "Devil_Succubus",
        "display": "Succubus",
        "strip": (),
        "fur_material": "",
    },
    "spawn": {
        "node": "Devil_Spawn",
        "display": "Devil spawn",
        "strip": (),
        "fur_material": "",
    },
    "gargoyle": {
        "node": "Devil_Gargoyle",
        "display": "Gargoyle",
        "strip": (),
        "fur_material": "",
    },
}
## The Hell beast is a quadruped on a clawed 37-bone rig: it keeps its imported
## body and its imported clips rather than being forced onto a biped's skeleton.
ORDER = ("hell_goat", "succubus", "spawn", "gargoyle")

## The joint whose height sets the fit scale: the base of the neck, so a skin
## stands to the creature's own height with its head and crown unscaled.
SCALE_JOINT = "neck_01"
## Creature bone -> (ranger bone, creature segment end, ranger segment end).
## `{s}` is the creature's side, `{S}` the ranger side it lands on (resolved from
## the joint's position, not from the name). The devils already name their joints
## after the ranger's, so `{s}` and `{S}` agree - the fit is where each shared
## segment *sits*, not which bone it is. "palm" is the mean of the finger roots,
## "tail" the bone's own tail.
SEGMENTS = {
    "pelvis": ("pelvis", "spine_01", "spine_01"),
    "spine_01": ("spine_01", "spine_02", "spine_02"),
    "spine_02": ("spine_02", "spine_03", "spine_03"),
    "spine_03": ("spine_03", "neck_01", "neck_01"),
    "clavicle_{s}": ("clavicle_{S}", "upperarm_{s}", "upperarm_{S}"),
    "upperarm_{s}": ("upperarm_{S}", "lowerarm_{s}", "lowerarm_{S}"),
    "lowerarm_{s}": ("lowerarm_{S}", "hand_{s}", "hand_{S}"),
    "hand_{s}": ("hand_{S}", "palm", "palm"),
    "thigh_{s}": ("thigh_{S}", "calf_{s}", "calf_{S}"),
    "calf_{s}": ("calf_{S}", "foot_{s}", "foot_{S}"),
    "foot_{s}": ("foot_{S}", "ball_{s}", "ball_{S}"),
    "ball_{s}": ("ball_{S}", "tail", "ball_leaf_{S}"),
}
## Ranger bones the bind pose turns onto the creature, parent first.
BIND_CHAIN = ("clavicle_{S}", "upperarm_{S}", "lowerarm_{S}", "hand_{S}")
## Carried rigidly on the neck's anchor: the skull keeps its size and its seat.
HEAD_CHAIN = ("neck_01", "neck_02", "Head", "head", "jaw")
CROWN_PREFIXES = ("antler_", "crown_")
## Claws and fingers: carried rigidly from the hand, so a claw keeps its length.
FINGER_PREFIXES = ("index_", "middle_", "ring_", "pinky_", "thumb_")
PALM_FINGERS = ("index_01_{S}", "middle_01_{S}", "ring_01_{S}", "pinky_01_{S}")

CAPTURE_POSES = Watcher.CAPTURE_POSES


def log(*parts) -> None:
    print("DS_" + str(parts[0]), *parts[1:], flush=True)


def parents_of(rig: bpy.types.Object) -> dict:
    return {bone.name: (bone.parent.name if bone.parent else "") for bone in rig.data.bones}


# --- proxy surfaces -----------------------------------------------------------

def strip_materials(mesh_obj: bpy.types.Object, names) -> int:
    """Delete the faces of the named materials, and the vertices they leave loose."""
    import bmesh

    wanted = tuple(str(name) for name in names)
    slots = {index for index, slot in enumerate(mesh_obj.data.materials)
             if slot is not None and slot.name in wanted}
    if not slots:
        return 0
    bm = bmesh.new()
    bm.from_mesh(mesh_obj.data)
    bm.faces.ensure_lookup_table()
    doomed = [face for face in bm.faces if face.material_index in slots]
    removed = len(doomed)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.delete(bm, geom=[vertex for vertex in bm.verts if not vertex.link_faces],
                     context="VERTS")
    bm.to_mesh(mesh_obj.data)
    bm.free()
    mesh_obj.data.update()
    return removed


# --- the bind pose ----------------------------------------------------------

def solve_bind(ranger: bpy.types.Object, creature: Watcher.Creature) -> tuple[dict, dict]:
    """Ranger armature-space matrices with the arms turned onto the creature's.

    Returns (posed matrices, matrix_basis per bone). Only the arm chain turns;
    every other bone inherits its parent's motion and keeps its rest otherwise.
    """
    rest = {bone.name: bone.matrix_local.copy() for bone in ranger.data.bones}
    parent = parents_of(ranger)
    targets: dict[str, tuple[Vector, Vector]] = {}
    for side_c in "lr":
        if f"hand_{side_c}" not in creature.heads:
            continue
        side_r = Watcher.side_of(creature.heads[f"hand_{side_c}"])
        chain = {
            "clavicle_{S}": (f"clavicle_{side_c}", f"upperarm_{side_c}", "upperarm_{S}"),
            "upperarm_{S}": (f"upperarm_{side_c}", f"lowerarm_{side_c}", "lowerarm_{S}"),
            "lowerarm_{S}": (f"lowerarm_{side_c}", f"hand_{side_c}", "hand_{S}"),
            "hand_{S}": (f"hand_{side_c}", "palm", "palm"),
        }
        for template in BIND_CHAIN:
            start_c, end_c, end_r = chain[template]
            head_c = creature.heads[start_c]
            tail_c = devil_palm(creature, side_c) if end_c == "palm" else creature.heads[end_c]
            name_r = template.replace("{S}", side_r)
            if end_r == "palm":
                joint_rest = sum((rest[f.replace("{S}", side_r)].translation
                                  for f in PALM_FINGERS), Vector()) / len(PALM_FINGERS)
            else:
                joint_rest = rest[end_r.replace("{S}", side_r)].translation.copy()
            targets[name_r] = (joint_rest, (tail_c - head_c).normalized())
    posed: dict[str, Matrix] = {}
    basis: dict[str, Matrix] = {}
    for name in Watcher.hierarchy(ranger):
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


def devil_palm(creature: Watcher.Creature, side: str) -> Vector:
    """Mean of the finger roots on one hand, or the hand's own tail."""
    roots = [creature.heads[f"{prefix}01_{side}"] for prefix in FINGER_PREFIXES
             if f"{prefix}01_{side}" in creature.heads]
    if not roots:
        return creature.tails[f"hand_{side}"]
    return sum(roots, Vector()) / len(roots)


# --- the fit ------------------------------------------------------------------

def build_fits(creature: Watcher.Creature, posed: dict) -> dict:
    fits: dict[str, Watcher.Fit] = {}
    parents = parents_of(creature.rig)
    heads_r = {name: matrix.translation.copy() for name, matrix in posed.items()}
    head_fit = Watcher.Fit(creature.heads["neck_01"], heads_r["neck_01"],
                           Matrix.Identity(3), 1.0, "head_chain")
    # Parent before child, so a bone the table does not name can borrow its
    # nearest fitted ancestor's map instead of being invented a new one.
    order = Watcher.hierarchy(creature.rig)
    for name in order:
        found = Watcher.match_template(name, SEGMENTS.keys())
        if found is not None:
            template, side_c = found
            side_r = Watcher.side_of(creature.heads[name]) if side_c else ""
            ranger_bone, end_c, end_r = SEGMENTS[template]
            ranger_bone = ranger_bone.replace("{s}", side_c).replace("{S}", side_r)
            if end_c == "palm":
                tail_c = devil_palm(creature, side_c)
                tail_r = sum((heads_r[f.replace("{S}", side_r)] for f in PALM_FINGERS),
                             Vector()) / len(PALM_FINGERS)
            elif end_c == "tail":
                tail_c = creature.tails[name]
                tail_r = heads_r[end_r.replace("{S}", side_r)]
            else:
                tail_c = creature.heads[end_c.replace("{s}", side_c)]
                tail_r = heads_r[end_r.replace("{S}", side_r)]
            fits[name] = Watcher.segment_fit(head_c=creature.heads[name], tail_c=tail_c,
                                             head_r=heads_r[ranger_bone], tail_r=tail_r,
                                             label=name)
            continue
        if name in HEAD_CHAIN or name.startswith(CROWN_PREFIXES):
            fits[name] = head_fit
            continue
        if name.split("_")[0] + "_" in FINGER_PREFIXES:
            hand = fits.get(f"hand_{name[-1]}")
            if hand is not None:
                # Rigid off the hand's map: the claw keeps its own length.
                u, _, vt = np.linalg.svd(np.array(hand.linear))
                fits[name] = Watcher.Fit(creature.heads[name], hand.at(creature.heads[name]),
                                         Matrix((u @ vt).tolist()), 1.0, name)
    # A bone the rig carries but the body does not name rides its nearest fitted
    # ancestor: a wing root follows the chest, a tail follows the hips.
    for name in order:
        if name in fits:
            continue
        parent = parents.get(name, "")
        while parent and parent not in fits:
            parent = parents.get(parent, "")
        fits[name] = fits[parent] if parent else fits["pelvis"]
    missing = [name for name in creature.names if name not in fits]
    if missing:
        raise SystemExit(f"no fit for creature bones {missing}")
    return fits


def weight_targets(creature: Watcher.Creature, ranger_names: list[str]) -> dict:
    """Where each creature bone's weight goes on the ranger."""
    known = set(ranger_names)
    parents = parents_of(creature.rig)
    out: dict[str, dict[str, float]] = {}

    def target(name: str) -> dict:
        if name in out:
            return out[name]
        if name == "root":
            # The ranger's root deforms nothing: a body's own root rides the hips.
            mapping = {"pelvis": 1.0}
        elif name in known:
            mapping = {name: 1.0}
        elif name.startswith(CROWN_PREFIXES):
            mapping = {"Head": 1.0}
        else:
            parent = parents.get(name, "")
            mapping = target(parent) if parent else {"pelvis": 1.0}
        out[name] = mapping
        return mapping

    for name in Watcher.hierarchy(creature.rig):
        target(name)
    return out


def map_weights(weights: np.ndarray, creature: Watcher.Creature,
                ranger_names: list[str]) -> np.ndarray:
    targets = weight_targets(creature, ranger_names)
    table = np.zeros((len(creature.names), len(ranger_names)), dtype=np.float64)
    for row, name in enumerate(creature.names):
        for bone, share in targets[name].items():
            if bone not in ranger_names:
                raise SystemExit(f"weight target {bone} is not a ranger bone")
            table[row, ranger_names.index(bone)] += share
    mapped = weights @ table
    order = np.argsort(-mapped, axis=1)
    keep = np.zeros_like(mapped, dtype=bool)
    rows = np.arange(mapped.shape[0])[:, None]
    keep[rows, order[:, :Watcher.MAX_INFLUENCES]] = True
    mapped = np.where(keep & (mapped >= Watcher.WEIGHT_FLOOR), mapped, 0.0)
    totals = mapped.sum(axis=1)
    fallback = totals <= 1.0e-9
    if fallback.any():
        raise SystemExit(f"{int(fallback.sum())} vertices lost every influence")
    return mapped / totals[:, None]


# --- metadata -----------------------------------------------------------------

def glb_document(path: Path) -> dict:
    raw = path.read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20: 20 + length])


def write_metadata(species: str, path: Path, source: Path, creature: Watcher.Creature,
                   fits: dict, skin: bpy.types.Object, fitted: np.ndarray,
                   points: np.ndarray, mapped: np.ndarray, ranger_names: list[str],
                   stripped: int) -> dict:
    document = glb_document(path)
    skin_doc = document["skins"][0]
    nodes = document["nodes"]
    joints = [nodes[index].get("name", "") for index in skin_doc["joints"]]
    triangles = sum(len(polygon.vertices) - 2 for polygon in skin.data.polygons)
    # What the GLB actually carries, slot order preserved: the export drops the
    # slot of a stripped proxy surface, so Blender's slot list would promise a
    # fur material the skin no longer draws.
    exported = [material.get("name", "") for material in document.get("materials", [])]
    scale = creature.fit_scale
    lo = fitted.min(axis=0)
    hi = fitted.max(axis=0)
    spec = SPECIES[species]
    used = [ranger_names[column] for column in np.nonzero(mapped.sum(axis=0) > 0.0)[0]]
    metadata = {
        "asset": path.name,
        "species": species,
        "display": spec["display"],
        "node": spec["node"],
        "skeleton": "Armature/Skeleton3D",
        "bone_count": len(joints),
        "joints": joints,
        "deforming_bones": used,
        "unit": "metres",
        "fit_scale": round(scale, 4),
        "fit_scale_rule": f"creature {SCALE_JOINT} head height / ranger {SCALE_JOINT} head height",
        "bind": "ranger rest with clavicle, upper arm, forearm and hand turned onto "
                "the creature's rest arms",
        "segment_stretch": {name: round(fit.stretch, 4) for name, fit in sorted(fits.items())
                            if abs(fit.stretch - 1.0) > 1.0e-6},
        # Blender Z-up armature space -> glTF/Godot Y-up: (x, y, z) -> (x, z, -y).
        "bind_bounds_min": [round(float(lo[0]), 4), round(float(lo[2]), 4), round(float(-hi[1]), 4)],
        "bind_bounds_max": [round(float(hi[0]), 4), round(float(hi[2]), 4), round(float(-lo[1]), 4)],
        "runtime_height": round(float(hi[2]) * scale, 4),
        "source_height": round(float(points[:, 2].max()) * scale, 4),
        "mesh_triangles": triangles,
        "mesh_vertices": len(skin.data.vertices),
        "max_influences": Watcher.MAX_INFLUENCES,
        "materials": exported,
        "removed_materials": list(spec["strip"]),
        "removed_triangles": stripped,
        "materials_from": "res://assets/characters/devils/" + source.name,
        "embedded_images": len(document.get("images", [])),
        "source": "The shipped " + source.name + " mesh, UVs and material slots refitted "
                  "onto ironwood_ranger.glb's skeleton by tools/prepare_devil_skins.py. "
                  "No third-party model, texture or motion was added.",
        "source_sha256": {source.name: Watcher.sha256(source), RANGER.name: Watcher.sha256(RANGER)},
        "reproducer": f"python tools/build_devil_skins.py {species}",
    }
    if spec["fur_material"]:
        metadata["fur"] = {
            "material": spec["fur_material"],
            "albedo": "res://assets/characters/devils/" + FUR.name,
            "normal": "res://assets/characters/devils/" + FUR.with_name(
                FUR.stem + "_n.png").name,
            "rule": "the body surface wears the tiling strand tile at runtime; the "
                    "removed proxy geometry is what it replaces",
        }
    path.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return metadata


# --- captures -----------------------------------------------------------------

def capture(species: str, ranger: bpy.types.Object, rig: bpy.types.Object,
            skin: bpy.types.Object, creature: Watcher.Creature) -> Path:
    folder = WORKSPACE / species / "captures"
    folder.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scale = creature.fit_scale
    rig.scale = (scale, scale, scale)
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
    for view, direction in {"front": Vector((0.0, -1.0, 0.0)),
                            "side": Vector((-1.0, 0.0, 0.0))}.items():
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
        Watcher.copy_pose(ranger, rig)
        shoot(label, False)
    ranger.animation_data.action = None
    log("CAPTURES", folder, len(written))
    return folder


# --- main ---------------------------------------------------------------------

def build(species: str, captures: bool) -> dict:
    spec = SPECIES[species]
    source = DEVILS / f"ironwood_{species}.glb"
    output = OUTPUT / f"ironwood_devil_{species}.glb"
    Watcher.reset_scene()
    ranger, ranger_meshes = Watcher.import_glb(RANGER)
    ranger.name = "RangerSource"
    for obj in ranger_meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
    ranger_names = [bone.name for bone in ranger.data.bones]
    creature_rig, creature_meshes = Watcher.import_glb(source)
    creature_rig.name = "CreatureSource"
    if len(creature_meshes) != 1:
        raise SystemExit(f"{source.name}: expected one skinned mesh, found {len(creature_meshes)}")
    stripped = strip_materials(creature_meshes[0], spec["strip"])
    rest_r = {bone.name: bone.head_local.copy() for bone in ranger.data.bones}
    neck_c = creature_rig.data.bones[SCALE_JOINT].head_local
    fit_scale = float(neck_c.z) / float(rest_r[SCALE_JOINT].z)
    creature = Watcher.Creature(creature_rig, creature_meshes[0], fit_scale)
    log("BEGIN", species, "fit_scale", round(fit_scale, 4), "stripped_tris", stripped)
    posed, basis = solve_bind(ranger, creature)
    fits = build_fits(creature, posed)
    fitted, normals, weights, points = Watcher.fit_mesh(creature.mesh, creature, fits)
    mapped = map_weights(weights, creature, ranger_names)
    rig = Watcher.build_export_rig(ranger, basis)
    skin = Watcher.build_skin(creature, rig, spec["node"], fitted, normals, mapped, ranger_names)
    Watcher.export(rig, skin, output)
    metadata = write_metadata(species, output, source, creature, fits, skin, fitted, points,
                              mapped, ranger_names, stripped)
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
            raise SystemExit(f"unknown fitted devil {species}; known: {', '.join(ORDER)}")
    results = {species: build(species, captures) for species in wanted}
    log("DONE", json.dumps({name: {"tris": meta["mesh_triangles"], "scale": meta["fit_scale"],
                                   "height": meta["runtime_height"]}
                            for name, meta in results.items()}))


if __name__ == "__main__":
    main()
