"""Build the source-based devil GLBs from the licensed CC0 Quaternius sources.

Usage (Blender 5.1, after tools/devil_source_textures.py):
    blender --background --python-exit-code 1 --python tools/prepare_devil_sources.py -- all
    blender --background --python-exit-code 1 --python tools/prepare_devil_sources.py -- succubus
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import numpy as np
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

from devil_source_pipeline import (  # noqa: E402
    BASE_UE, HAIR, OUTFIT_DIR, SOURCE_RUNTIME, DEVILS, FPS, WOLF_GLB,
    action_fcurves, add_bone, add_constant_pelvis_offset, add_extra_curves,
    add_group_weight, add_head_jaw_markers, add_tail_bones,
    apply_orientation_and_scale, armature_modifier, assign_action, bake_action,
    copy_action_rename, delete_objects, export_glb, import_gltf, import_piece,
    import_ranger_actions, make_claw, make_fang, make_horn, make_mantle,
    make_goat_skull, make_hoof, make_skirt, make_spike, make_tail, make_wing,
    mesh_object, pbr_material, replace_materials, reset_scene, rigid_skin,
    scale_action_locations, setup_nla, simple_material, tube,
    weight_by_segments, write_metadata, add_wing_bones,
)


def mesh_list(added):
    return [o for o in added if o.type == "MESH"]


def base_meshes(added):
    keep = []
    for obj in mesh_list(added):
        name = obj.name.lower()
        if "icosphere" in name:
            continue
        if any(k in name for k in ["superhero", "sphere", "face", "eyes", "eyebrows"]):
            keep.append(obj)
    return keep


def find_body(objs):
    for obj in objs:
        n = obj.name.lower()
        if "superhero" in n:
            return obj
    for obj in objs:
        if "sphere" in obj.name.lower():
            return obj
    return objs[0]


def assign_source_materials(meshes, mapping, default=None):
    for obj in meshes:
        replace_materials(obj, mapping, default)


def build_actions(rig, actions, source_names, scale, pelvis_offset, extra_bones,
                  attack, hit, death, overlay_attack, overlay_hit, overlay_death,
                  extra_kinds=None):
    """Copy locomotion actions and bake attack/hit/death."""
    clips = {}
    for key, src_name, new_name in source_names:
        src = actions.get(src_name)
        if src is None:
            raise RuntimeError("Missing source action " + src_name)
        act = copy_action_rename(src, new_name)
        scale_action_locations(act, scale)
        if pelvis_offset:
            add_constant_pelvis_offset(act, rig, pelvis_offset)
        if extra_bones:
            for kind, bones in extra_kinds.items():
                add_extra_curves(act, rig, bones, phase=0.0, amplitude=1.0, kind=kind)
        clips[key] = {"name": new_name, "duration": (act.frame_range[1] - act.frame_range[0]) / FPS}
    # Attack
    atk_src = actions.get(attack["source"])
    if atk_src is None:
        raise RuntimeError("Missing attack source " + attack["source"])
    src_impact = attack["source_impact"]
    src_duration = (atk_src.frame_range[1] - atk_src.frame_range[0]) / FPS

    def attack_warp(t, dur=attack["duration"], impact=attack["impact"]):
        if t <= impact:
            return src_impact * (t / max(1e-5, impact))
        return src_impact + (t - impact) / max(1e-5, dur - impact) * max(0.02, src_duration - src_impact)

    atk_act = bake_action(rig, atk_src, attack["name"], attack["duration"],
                          warp=attack_warp, overlay=overlay_attack,
                          pelvis_offset=0.0)
    scale_action_locations(atk_act, scale)
    if pelvis_offset:
        add_constant_pelvis_offset(atk_act, rig, pelvis_offset)
    clips["attack"] = {"name": attack["name"], "duration": attack["duration"],
                       "impact": attack["impact"]}
    # Hit
    hit_act = bake_action(rig, actions.get("Idle_Loop"), hit["name"], hit["duration"],
                          warp=None, overlay=overlay_hit, pelvis_offset=0.0,
                          source_frame0=True)
    scale_action_locations(hit_act, scale)
    if pelvis_offset:
        add_constant_pelvis_offset(hit_act, rig, pelvis_offset)
    clips["hit"] = {"name": hit["name"], "duration": hit["duration"]}
    # Death
    death_act = bake_action(rig, actions.get("Idle_Loop"), death["name"], death["duration"],
                            warp=None, overlay=overlay_death, pelvis_offset=0.0,
                            source_frame0=True)
    scale_action_locations(death_act, scale)
    if pelvis_offset:
        add_constant_pelvis_offset(death_act, rig, pelvis_offset)
    clips["death"] = {"name": death["name"], "duration": death["duration"]}
    return clips, [atk_act, hit_act, death_act]


def make_scene_export(rig, joined, actions, output, mob, display, clips,
                      head_radius, head_half, notes, source_note):
    for action in actions:
        if action and not action.use_fake_user:
            action.use_fake_user = True
    setup_nla(rig, actions)
    export_glb(output)
    return write_metadata(output, mob, display, clips, head_radius, head_half, notes,
                          source=source_note)


def base_material_maps(mob):
    td = SOURCE_RUNTIME / mob / "textures"
    return td


# ---------------------------------------------------------------------------
# Succubus


def build_succubus() -> dict:
    mob = "succubus"
    reset_scene()
    added, rig = import_gltf(BASE_UE / "Superhero_Female_FullBody.gltf")
    if rig is None:
        raise RuntimeError("female base has no armature")
    base = base_meshes(added)
    delete_objects([o for o in added if o.type == "MESH" and o not in base])
    body = find_body(base)
    print("BASE_FEMALE", len(base), [o.name for o in base], "bones", len(rig.data.bones))

    outfit = import_piece(OUTFIT_DIR / "Female_Ranger.gltf", rig,
                          ["Female_Ranger_Body", "Female_Ranger_Feet"])
    hair = import_piece(HAIR / "Hair_Long.gltf", rig, ["Hair_Long"])
    actions = import_ranger_actions()
    print("ACTIONS", sorted(actions)[:12], "idle_range", actions["Idle_Loop"].frame_range)

    # Extra bones before transforms.
    add_head_jaw_markers(rig, Vector((0.0, -0.095, 1.620)), Vector((0.0, -0.085, 1.565)))
    add_wing_bones(rig, "l", spread=True)
    add_wing_bones(rig, "r", spread=True)
    tail_pts = [Vector((0, 0.08, 0.95)), Vector((0, 0.20, 0.86)),
                Vector((0, 0.30, 0.70)), Vector((0, 0.36, 0.52))]
    add_tail_bones(rig, tail_pts, "tail")

    # Source-bound materials.
    td = base_material_maps(mob)
    skin = pbr_material("Skin_Succubus", td, "skin_albedo.png", "skin_normal.png",
                        "skin_roughness.png", roughness_value=0.52)
    leather = pbr_material("Leather_Succubus", td, "leather_albedo.png", "leather_normal.png",
                           "leather_roughness.png", roughness_value=0.55)
    hair_mat = pbr_material("Hair_Succubus", td, "hair_albedo.png", "hair_normal.png",
                            roughness_value=0.45)
    eye = pbr_material("Eye_Succubus", td, "eye_albedo.png", "eye_normal.png",
                       emission="eye_emission.png", emission_strength=2.4,
                       roughness_value=0.22)
    horn = pbr_material("Horn_Succubus", td, "horn_albedo.png", "horn_normal.png",
                        "horn_roughness.png", roughness_value=0.38)
    membrane = pbr_material("Membrane_Succubus", td, "membrane_albedo.png",
                            "membrane_normal.png", "membrane_roughness.png",
                            roughness_value=0.52)
    dark = simple_material("Dark_Succubus", (0.006, 0.004, 0.004), 0.6)

    replace_materials_bulk(base + outfit + hair,
                           {"MI_Superhero_Female": skin, "MI_Ranger": leather,
                            "MI_Hair_2": hair_mat, "MI_Eyes": eye,
                            "MI_Regular_Female": skin})
    # The long hair mesh is the only MI_Hair_2 in the hair import; the base
    # brows also become hair, which is correct.

    # Face/jaw marker weights (tiny; the markers inherit Head).
    add_marker_weights(body, rig)
    # Remove any source helper objects that slipped in.
    delete_objects([o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Icosphere")])

    extras = []
    # Horns.
    for side, s in (("l", 1), ("r", -1)):
        pts = [Vector((0.062 * s, -0.060, 1.730)), Vector((0.104 * s, 0.010, 1.865)),
               Vector((0.138 * s, 0.100, 1.980)), Vector((0.132 * s, 0.200, 2.055)),
               Vector((0.095 * s, 0.275, 2.090)), Vector((0.060 * s, 0.315, 2.075))]
        extras.append(make_horn(rig, side, pts,
                                [0.052, 0.045, 0.034, 0.022, 0.011, 0.0025], horn, "Head", 48))
    # Wings.
    for side in ("l", "r"):
        extras.extend(make_wing(rig, side, membrane, skin, spread=True))
    # Tail.
    extras.extend(make_tail(rig, tail_pts, [0.036, 0.028, 0.018, 0.009],
                            skin, horn, [f"tail_{i:02d}" for i in range(1, 4)]))
    # Finger claws.
    for side in ("l", "r"):
        for finger in ("index", "middle", "ring", "pinky", "thumb"):
            bone = rig.data.bones.get(f"{finger}_03_{side}")
            if bone:
                base_p = bone.tail_local.copy()
                d = (bone.tail_local - bone.head_local).normalized()
                extras.append(make_claw(rig, bone.name, base_p, d, 0.036, horn, 8))
    # Fangs.
    for s in (-1, 1):
        extras.append(make_fang(rig, Vector((0.024 * s, -0.108, 1.598)),
                                Vector((0.0, -0.15, -1.0)), 0.022, horn, "Head"))
    # Tattered loincloth; no metal waistband.
    # Ensure every extra has an armature modifier and is parented.
    for obj in extras:
        if not any(m.type == "ARMATURE" for m in obj.modifiers):
            armature_modifier(obj, rig)
    joined = join_all(base + outfit + hair + extras, body, rig)
    apply_orientation_and_scale(rig, joined, 1.0)
    # The female base needs a 17 mm lift to match the male-authored clips.
    pelvis_offset = 0.017
    # Scale the shared source actions before copying/baking.
    for act in actions.values():
        scale_action_locations(act, 1.0)

    extra_kinds = {
        "wing": [f"wing_{i:02d}_{s}" for s in ("l", "r") for i in range(1, 4)],
        "tail": ["tail_01", "tail_02", "tail_03"],
    }
    clips, baked = build_actions(
        rig, actions,
        [("idle", "Idle_Loop", "Succubus_Idle_Loop"),
         ("walk", "Walk_Loop", "Succubus_Walk_Loop"),
         ("run", "Sprint_Loop", "Succubus_Run_Loop")],
        1.0, pelvis_offset, extra_kinds,
        {"source": "Sword_Overhead_OneHand", "source_impact": 0.375,
         "duration": 1.35, "impact": 0.58, "name": "Succubus_Attack"},
        {"name": "Succubus_Hit", "duration": 0.45},
        {"name": "Succubus_Death", "duration": 1.20},
        succubus_attack,
        lambda rig, t, dur: humanoid_hit(rig, t, dur),
        lambda rig, t, dur: humanoid_death(rig, t, dur, wings=True, tail=True),
        extra_kinds,
    )
    add_pelvis_drop(next(a for a in bpy.data.actions if a.name == "Succubus_Death"), rig, 1.20, 0.30)
    # Keep only the six tracks in the export.
    all_actions = [a for a in bpy.data.actions if a.name.startswith("Succubus_")]
    for act in baked:
        if act.name not in {a.name for a in all_actions}:
            all_actions.append(act)
    order = [next(a for a in all_actions if a.name == f"Succubus_{k}") for k in
             ["Idle_Loop", "Walk_Loop", "Run_Loop", "Attack", "Hit", "Death"]]
    meta = make_scene_export(rig, joined, order, DEVILS / "ironwood_succubus.glb",
                             mob, "Succubus", clips, 0.135, 0.095,
                             ["source female base and ranger leather", "long hair",
                              "bat wings, tail, keratin horns and claws",
                              "crimson-grey skin with authored pores/veins"],
                             "CC0 Quaternius female base, female ranger outfit, hair, core animations; original devil modifications")
    render_preview(rig, joined, mob)
    return meta


def replace_materials_bulk(meshes, mapping, default=None):
    for obj in meshes:
        replace_materials(obj, mapping, default)


def add_marker_weights(body, rig):
    head = rig.data.bones.get("head")
    jaw = rig.data.bones.get("jaw")
    if head is None or jaw is None:
        return
    face = head.head_local
    jaw_p = jaw.head_local
    h_idx, j_idx = [], []
    for v in body.data.vertices:
        if (v.co - face).length < 0.055:
            h_idx.append(v.index)
        if (v.co - jaw_p).length < 0.040:
            j_idx.append(v.index)
    if h_idx:
        add_group_weight(body, "head", h_idx, 0.002)
    if j_idx:
        add_group_weight(body, "jaw", j_idx, 0.002)


def make_belt(rig, z: float, radius: float, leather, metal, name: str):
    # A thin leather band plus a small metal buckle.
    pts = [Vector((math.cos(a) * radius, math.sin(a) * radius, z)) for a in
           [i / 48 * math.tau for i in range(49)]]
    obj, _ = tube(name, pts, [0.012] * 49, 8, leather)
    weight_by_segments(obj, rig, ["pelvis"], power=2.0)
    # Buckle
    verts = [Vector((-0.035, -radius - 0.012, z - 0.035)), Vector((0.035, -radius - 0.012, z - 0.035)),
             Vector((0.035, -radius - 0.012, z + 0.035)), Vector((-0.035, -radius - 0.012, z + 0.035)),
             Vector((-0.035, -radius + 0.012, z - 0.035)), Vector((0.035, -radius + 0.012, z - 0.035)),
             Vector((0.035, -radius + 0.012, z + 0.035)), Vector((-0.035, -radius + 0.012, z + 0.035))]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    buckle = mesh_object("Buckle", verts, faces, None, metal)
    rigid_skin(buckle, rig, "pelvis")
    return [obj, buckle]


def join_all(meshes, active, rig):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = "DevilMesh"
    joined.parent = rig
    joined.matrix_parent_inverse = Matrix.Identity(4)
    # Ensure exactly one armature modifier references the final rig.
    for mod in list(joined.modifiers):
        if mod.type == "ARMATURE":
            mod.object = rig
    if not any(m.type == "ARMATURE" for m in joined.modifiers):
        armature_modifier(joined, rig)
    return joined


# ---------------------------------------------------------------------------
# Succubus overlays


def succubus_attack(rig, t: float, duration: float) -> None:
    u = min(1.0, t / max(1e-5, duration))
    impact = 0.58
    # Wings spread on the load and snap at impact.
    flare = math.sin(math.pi * min(1.0, u / max(0.01, impact / duration)))
    for side, s in (("l", 1), ("r", -1)):
        for i in range(1, 4):
            pb = rig.pose.bones.get(f"wing_{i:02d}_{side}")
            if pb:
                pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), s * math.radians(8.0 * flare))
    tail = rig.pose.bones.get("tail_01")
    if tail:
        tail.rotation_quaternion = tail.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(18.0 * math.sin(u * math.pi)))


# ---------------------------------------------------------------------------
# Render preview


def render_preview(rig, mesh, mob: str, idle_name: str | None = None) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1100
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.025, 0.030, 0.040, 1.0)
        bg.inputs[1].default_value = 0.35
    # Show the idle pose rather than the bind pose.
    idle = bpy.data.actions.get(idle_name) if idle_name else None
    if idle is None:
        idle = next((a for a in bpy.data.actions if a.name.endswith("_Idle_Loop")), None)
    if idle:
        assign_action(rig, idle)
        bpy.context.scene.frame_set(0)
        bpy.context.view_layer.update()
    # Camera in front of the rotated character (it faces +Y in Blender now).
    bpy.ops.object.camera_add(location=(3.2, 4.8, 1.9))
    cam = bpy.context.object
    cam.data.lens = 40
    scene.camera = cam
    look = Vector((0, 0, 1.45)) - cam.location
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    # Three-point area lighting.
    for name, pos, energy, size in [
        ("Key", (3.5, 3.0, 3.2), 500, 3.0),
        ("Fill", (-3.0, 2.0, 2.0), 200, 4.0),
        ("Rim", (-1.0, -3.0, 2.8), 400, 2.0),
    ]:
        bpy.ops.object.light_add(type="AREA", location=pos)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (Vector((0, 0, 1.1)) - light.location).to_track_quat("-Z", "Y").to_euler()
    out = SOURCE_RUNTIME / mob / "captures"
    out.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out / f"{mob}_preview.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)


def render_head_preview(rig, mob: str, idle_name: str | None = None) -> None:
    """Second still: three-quarter face close-up at sculpted feature scale."""
    scene = bpy.context.scene
    idle = bpy.data.actions.get(idle_name) if idle_name else None
    if idle:
        assign_action(rig, idle)
        scene.frame_set(0)
        bpy.context.view_layer.update()
    cam = scene.camera
    if cam is None:
        return
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    cam.data.lens = 70
    marker = rig.pose.bones.get("head")
    if marker is not None:
        m = rig.matrix_world @ marker.matrix
        face = m.translation
        basis = m.to_3x3()
        forward = (basis @ Vector((0.0, 1.0, 0.0))).normalized()
        right = (basis @ Vector((1.0, 0.0, 0.0))).normalized()
        target = face + Vector((0.0, 0.0, -0.01))
        cam.location = target + forward * 1.05 + right * 0.24
    else:
        target = Vector((0.0, 0.0, 2.70))
        cam.location = (0.62, 1.05, 2.86)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    out = SOURCE_RUNTIME / mob / "captures"
    scene.render.filepath = str(out / f"{mob}_face.png")
    bpy.ops.render.render(write_still=True)
    print("FACE_PREVIEW", scene.render.filepath)




# ---------------------------------------------------------------------------
# Goat-specific body helpers


def cut_head(body, z_cut: float = 1.52) -> None:
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    doomed = [v for v in bm.verts if v.co.z > z_cut]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def _fur_clump(rig, material, base: Vector, direction: Vector, length: float,
               bones: list[str], radius: float = 0.012):
    d = direction.normalized()
    down = Vector((0, 0, -1))
    p1 = base + d * length * 0.32 + down * length * 0.10
    p2 = base + d * length * 0.60 + down * length * 0.42
    p3 = base + d * length * 0.72 + down * length * 0.88
    obj, _ = tube("FurClump", [base, p1, p2, p3],
                  [radius, radius * 0.72, radius * 0.40, radius * 0.06], 3, material)
    weight_by_segments(obj, rig, bones, power=1.5, max_bones=2)
    return obj


def make_fur_patches(rig, material, seed: int = 31):
    rng = np.random.default_rng(seed)
    parts = []

    def region(bone_name: str, t0: float, t1: float, along: int, around: int,
               radius: float, length: float, bones: list[str]):
        bone = rig.data.bones.get(bone_name)
        if bone is None:
            return
        axis = (bone.tail_local - bone.head_local).normalized()
        up = Vector((0, 0, 1)) if abs(axis.z) < 0.85 else Vector((0, 1, 0))
        n = axis.cross(up).normalized()
        b2 = axis.cross(n).normalized()
        for i in range(along):
            t = t0 + (t1 - t0) * (i + 0.5) / along
            center = bone.head_local.lerp(bone.tail_local, t)
            for j in range(around):
                a = math.tau * (j + 0.5) / around + (i % 2) * 0.12
                radial = n * math.cos(a) + b2 * math.sin(a)
                base = center + radial * radius
                L = length * (0.78 + 0.42 * float(rng.random()))
                parts.append(_fur_clump(rig, material, base,
                                        radial * 0.75 + Vector((0, 0, -0.35)),
                                        L, bones))

    for side in ("l", "r"):
        region(f"lowerarm_{side}", 0.12, 0.92, 6, 5, 0.052, 0.10,
               [f"lowerarm_{side}"])
        region(f"upperarm_{side}", 0.18, 0.86, 4, 5, 0.062, 0.11,
               [f"upperarm_{side}"])
        region(f"calf_{side}", 0.10, 0.92, 7, 6, 0.068, 0.13,
               [f"calf_{side}"])
        region(f"thigh_{side}", 0.18, 0.82, 4, 5, 0.085, 0.11,
               [f"thigh_{side}"])
    # Chest, back and flanks.
    for z, count in ((1.22, 14), (1.34, 14), (1.44, 12)):
        for j in range(count):
            a = math.tau * j / count
            base = Vector((math.cos(a) * 0.23, math.sin(a) * 0.17 + 0.01, z))
            L = 0.095 * (0.8 + 0.5 * float(rng.random()))
            parts.append(_fur_clump(rig, material, base,
                                    Vector((math.cos(a), math.sin(a), -0.35)), L,
                                    ["spine_02", "spine_03"]))
    return parts


def make_hoof_boot(rig, side: str, horn, fur):
    foot = rig.data.bones.get(f"foot_{side}")
    calf = rig.data.bones.get(f"calf_{side}")
    if foot is None or calf is None:
        return []
    x = foot.head_local.x
    parts = []
    # Boot/shin sleeve covering the human foot and ankle.
    sleeve, _ = tube("HoofBoot",
                     [Vector((x, 0.045, 0.36)), Vector((x, 0.020, 0.21)),
                      Vector((x, -0.005, 0.09))],
                     [0.082, 0.078, 0.064], 18, fur)
    weight_by_segments(sleeve, rig, [f"calf_{side}", f"foot_{side}"], power=1.6)
    parts.append(sleeve)
    # Two cloven hoof toes at the bottom, extending forward.
    for toe in (-1, 1):
        cx = x + toe * 0.027
        verts = [
            Vector((cx - 0.024, 0.045, 0.105)),
            Vector((cx + 0.024, 0.045, 0.105)),
            Vector((cx + 0.021, -0.125, 0.065)),
            Vector((cx - 0.021, -0.125, 0.065)),
            Vector((cx - 0.018, -0.110, 0.0)),
            Vector((cx + 0.018, -0.110, 0.0)),
        ]
        faces = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2), (0, 4, 5, 1)]
        obj = mesh_object(f"Hoof_{side}_{toe}", verts, faces, None, horn)
        for poly in obj.data.polygons:
            poly.use_smooth = False
        rigid_skin(obj, rig, f"foot_{side}")
        parts.append(obj)
    # Fur cuff at the boot top.
    for j in range(10):
        a = math.tau * j / 10
        base = Vector((x + math.cos(a) * 0.085, math.sin(a) * 0.075 + 0.02, 0.34))
        parts.append(_fur_clump(rig, fur, base,
                                Vector((math.cos(a), math.sin(a), -0.5)),
                                0.10, [f"calf_{side}"]))
    return parts


def make_fur_collar(rig, material):
    collar = make_skirt(rig, 1.565, 1.415, 0.125, 0.205, material, "NeckRuff", 36, 0.012)
    for vg in list(collar.vertex_groups):
        collar.vertex_groups.remove(vg)
    weight_by_segments(collar, rig, ["neck_01", "spine_03"], power=1.8)
    parts = [collar]
    for j in range(18):
        a = math.tau * j / 18
        base = Vector((math.cos(a) * 0.155, math.sin(a) * 0.145 + 0.01, 1.495))
        parts.append(_fur_clump(rig, material, base,
                                Vector((math.cos(a), math.sin(a), -0.55)),
                                0.105, ["neck_01", "Head"]))
    return parts


def make_sphere(name: str, center, scale, material, rig, bone: str) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    c = Vector(center)
    sc = Vector(scale)
    for v in bm.verts:
        v.co = Vector((v.co.x * sc.x, v.co.y * sc.y, v.co.z * sc.z)) + c
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    me.materials.append(material)
    for poly in me.polygons:
        poly.use_smooth = True
    rigid_skin(obj, rig, bone)
    return obj


def make_neck_tube(rig, material) -> bpy.types.Object:
    obj, _ = tube("Neck", [Vector((0, 0.020, 1.430)), Vector((0, 0.010, 1.520)),
                           Vector((0, 0.005, 1.600))],
                  [0.115, 0.105, 0.095], 18, material)
    weight_by_segments(obj, rig, ["neck_01", "Head"], power=1.8)
    return obj


def drop_pelvis(rig, amount: float) -> None:
    """Drop the pelvis `amount` metres in armature Z without touching `matrix`.

    The hunch is an overlay: it runs once per baked frame on top of a freshly
    restored base pose, and the bake has only keyed frames <= f. Reading
    `pose_bone.matrix` there therefore returns the previous frame's evaluated
    pose and the offset compounds on every key -- the gargoyle sank a further
    3 cm per frame and dropped through the floor. The pelvis location channel
    is the basis the overlay owns, and a rest-space translation needs no
    depsgraph update, so it stays constant.
    """
    pb = rig.pose.bones.get("pelvis")
    bone = rig.data.bones.get("pelvis")
    if pb is None or bone is None or abs(amount) < 1e-9:
        return
    local = bone.matrix_local.to_3x3().inverted() @ Vector((0.0, 0.0, -1.0))
    pb.location += local.normalized() * amount


def gargoyle_hunch(rig, t: float, duration: float) -> None:
    # Predatory stoop on the upright source pose plus a slow stone-breath swell.
    breath = math.sin(t * math.tau / 2.5)
    for name, angle in [("spine_01", 10.0 + 0.8 * breath),
                        ("spine_02", 9.0 + 0.9 * breath),
                        ("spine_03", 7.0 + 0.6 * breath),
                        ("neck_01", -9.0), ("Head", -5.0 + 1.2 * breath)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(angle))
    for side, s in (("l", 1), ("r", -1)):
        pb = rig.pose.bones.get(f"upperarm_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(10.0 * s))
        pb = rig.pose.bones.get(f"lowerarm_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(-11.0 * s))
        for i in range(1, 4):
            pb = rig.pose.bones.get(f"wing_{i:02d}_{side}")
            if pb:
                pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(6.0 * math.sin(t * 1.6 + i)))
    pb = rig.pose.bones.get("tail_01")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(10.0 * math.sin(t * 1.2)))
    drop_pelvis(rig, 0.020)
    for side in ("l", "r"):
        pb = rig.pose.bones.get(f"thigh_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(-7.0))
        pb = rig.pose.bones.get(f"calf_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(14.0))
        pb = rig.pose.bones.get(f"foot_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(-7.0))


def goat_hunch(rig, t: float, duration: float) -> None:
    for name, angle in [("spine_01", 11.0), ("spine_02", 9.0), ("spine_03", 7.0),
                        ("neck_01", -7.0), ("Head", -6.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(angle))
    for side, s in (("l", 1), ("r", -1)):
        pb = rig.pose.bones.get(f"upperarm_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(6.0 * s))


# ---------------------------------------------------------------------------
# Shared humanoid helpers


def apply_scale_only(rig, mesh, scale: float) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for obj in (rig, mesh):
        obj.scale = (scale, scale, scale)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh.parent = rig
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")


def reweight_rigid(obj, rig, bone: str) -> None:
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    rigid_skin(obj, rig, bone)


def smart_uv(obj, uv_scale: float = 1.5) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name="UVMap")
    obj.data.uv_layers.active_index = 0
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    layer = obj.data.uv_layers.active
    for loop in layer.data:
        loop.uv *= uv_scale


def smooth(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / max(1e-6, edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def enlarge_head(meshes, pivot: Vector, factor: float) -> None:
    for obj in meshes:
        for v in obj.data.vertices:
            f = 1.0 + (factor - 1.0) * smooth(pivot.z - 0.035, pivot.z + 0.065, v.co.z)
            v.co = pivot + (v.co - pivot) * f
        obj.data.update()


def boot_toe_center(boot, side: int) -> Vector:
    verts = [v.co for v in boot.data.vertices if v.co.z < 0.18 and v.co.x * side > 0.035]
    if not verts:
        return Vector((0.11 * side, -0.16, 0.045))
    min_y = min(v.y for v in verts)
    near = [v for v in verts if v.y < min_y + 0.035]
    cx = sum(v.x for v in near) / len(near)
    return Vector((cx, min_y + 0.010, 0.045))


def add_hand_claws(rig, material, length: float, sides: int = 8):
    parts = []
    for side in ("l", "r"):
        for finger in ("index", "middle", "ring", "pinky", "thumb"):
            bone = rig.data.bones.get(f"{finger}_03_{side}")
            if bone:
                d = (bone.tail_local - bone.head_local).normalized()
                parts.append(make_claw(rig, bone.name, bone.tail_local.copy(), d,
                                       length, material, sides))
    return parts


def add_foot_claws(rig, material, length: float, count: int = 3, lift: float = 0.0):
    parts = []
    for side in ("l", "r"):
        bone = rig.data.bones.get(f"ball_{side}")
        if bone is None:
            continue
        base = bone.tail_local.copy() + Vector((0.0, 0.0, lift))
        for i in range(count):
            off = (i - (count - 1) * 0.5) * 0.026
            parts.append(make_claw(rig, bone.name, base + Vector((off, 0, 0)),
                                   Vector((0, -0.9, -0.22)), length, material, 8))
    return parts


def make_chest_wrap(rig, material):
    obj = make_skirt(rig, 1.32, 1.10, 0.165, 0.185, material, "ChestWrap", 36, 0.018)
    reweight_rigid(obj, rig, "spine_02")
    return obj


def humanoid_hit(rig, t: float, duration: float, jaw: bool = False) -> None:
    u = min(1.0, t / max(1e-5, duration))
    recoil = math.sin(math.pi * u)
    for name, angle in [("spine_01", -8.0), ("spine_02", -12.0),
                        ("spine_03", -10.0), ("neck_01", 8.0), ("Head", 10.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(angle * recoil))
    for name, angle in [("upperarm_l", 10.0), ("upperarm_r", 10.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(angle * recoil))
    if jaw:
        pb = rig.pose.bones.get("jaw")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(10.0 * recoil))


def humanoid_death(rig, t: float, duration: float, jaw: bool = False,
                   wings: bool = False, tail: bool = False) -> None:
    u = min(1.0, t / max(1e-5, duration))
    fall = smooth(0.0, 1.0, u)
    pelvis = rig.pose.bones.get("pelvis")
    if pelvis:
        pelvis.rotation_quaternion = pelvis.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(68.0 * fall))
    for name, angle in [("spine_01", 14.0), ("spine_02", 16.0), ("spine_03", 12.0),
                        ("neck_01", 16.0), ("Head", 14.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(angle * fall))
    for name, angle in [("thigh_l", -38.0), ("calf_l", 68.0), ("foot_l", -22.0),
                        ("thigh_r", -32.0), ("calf_r", 60.0), ("foot_r", -20.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(angle * fall))
    for name, angle in [("upperarm_l", -18.0), ("lowerarm_l", 12.0),
                        ("upperarm_r", -22.0), ("lowerarm_r", 15.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(angle * fall))
    if jaw:
        pb = rig.pose.bones.get("jaw")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(16.0 * fall))
    if wings:
        for side in ("l", "r"):
            for i in range(1, 4):
                pb = rig.pose.bones.get(f"wing_{i:02d}_{side}")
                if pb:
                    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(-30.0 * fall))
    if tail:
        pb = rig.pose.bones.get("tail_01")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(-20.0 * fall))


def add_pelvis_drop(action, rig, duration: float, max_drop: float) -> None:
    if abs(max_drop) < 1e-6:
        return
    assign_action(rig, action)
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    pb = rig.pose.bones["pelvis"]
    before = pb.location.copy()
    m = pb.matrix.copy()
    m.translation.z -= 1.0
    pb.matrix = m
    bpy.context.view_layer.update()
    delta = pb.location - before
    for fc in action_fcurves(action):
        if fc.data_path != 'pose.bones["pelvis"].location':
            continue
        for kp in fc.keyframe_points:
            t = kp.co[0] / FPS
            d = max_drop * smooth(0.0, duration, t)
            kp.co[1] += delta[fc.array_index] * d
            kp.handle_left[1] += delta[fc.array_index] * d
            kp.handle_right[1] += delta[fc.array_index] * d
        fc.update()


def goat_attack(rig, t: float, duration: float) -> None:
    u = min(1.0, t / max(1e-5, duration))
    snarl = smooth(0.45, 0.62, u) * (1.0 - smooth(0.70, 1.0, u))
    pb = rig.pose.bones.get("jaw")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(15.0 * snarl))
    pb = rig.pose.bones.get("Head")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(5.0 * snarl))


def gargoyle_attack(rig, t: float, duration: float) -> None:
    u = min(1.0, t / max(1e-5, duration))
    flare = math.sin(math.pi * min(1.0, u / 0.54))
    snarl = smooth(0.40, 0.58, u) * (1.0 - smooth(0.72, 1.0, u))
    for side in ("l", "r"):
        for i in range(1, 4):
            pb = rig.pose.bones.get(f"wing_{i:02d}_{side}")
            if pb:
                pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(16.0 * flare))
        pb = rig.pose.bones.get(f"upperarm_{side}")
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(10.0 * flare * (1 if side == "l" else -1)))
    pb = rig.pose.bones.get("jaw")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(26.0 * snarl))
    pb = rig.pose.bones.get("Head")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(-7.0 * snarl))
    pb = rig.pose.bones.get("tail_01")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(14.0 * math.sin(u * math.pi)))


def spawn_attack(rig, t: float, duration: float) -> None:
    u = min(1.0, t / max(1e-5, duration))
    pb = rig.pose.bones.get("tail_01")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(24.0 * math.sin(u * math.pi)))
    pb = rig.pose.bones.get("Head")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(8.0 * math.sin(u * math.pi)))


def beast_hit(rig, t: float, duration: float) -> None:
    u = min(1.0, t / max(1e-5, duration))
    recoil = math.sin(math.pi * u)
    for name, angle in [("spine_01", -7.0), ("spine_02", -9.0), ("chest", -7.0),
                        ("neck_01", 9.0), ("neck_02", 9.0), ("head", 12.0)]:
        pb = rig.pose.bones.get(name)
        if pb:
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(angle * recoil))
    pb = rig.pose.bones.get("jaw")
    if pb:
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), math.radians(18.0 * recoil))


# ---------------------------------------------------------------------------
# Hell goat man


def build_hell_goat() -> dict:
    mob = "hell_goat"
    reset_scene()
    added, rig = import_gltf(BASE_UE / "Superhero_Male_FullBody.gltf")
    base = base_meshes(added)
    base = [o for o in base if o.name not in ("Face", "Face.001", "Eyebrows", "Eyes")]
    delete_objects([o for o in added if o.type == "MESH" and o not in base])
    body = find_body(base)
    print("BASE_MALE", [o.name for o in base], "bones", len(rig.data.bones))
    actions = import_ranger_actions()
    cut_head(body, 1.515)
    add_head_jaw_markers(rig, Vector((0.0, -0.135, 1.640)), Vector((0.0, -0.100, 1.560)))
    td = base_material_maps(mob)
    skin = pbr_material("Skin_HellGoat", td, "skin_albedo.png", "skin_normal.png",
                        "skin_roughness.png", roughness_value=0.58)
    fur = pbr_material("Fur_HellGoat", td, "fur_albedo.png", "fur_normal.png",
                       "fur_roughness.png", roughness_value=0.86)
    horn = pbr_material("Horn_HellGoat", td, "horn_albedo.png", "horn_normal.png",
                        "horn_roughness.png", roughness_value=0.40)
    bone = pbr_material("Bone_HellGoat", td, "bone_albedo.png", "bone_normal.png",
                        "bone_roughness.png", roughness_value=0.55)
    dark = simple_material("Dark_HellGoat", (0.004, 0.004, 0.004), 0.70)
    replace_materials_bulk(base, {"MI_Superhero_Male": skin})
    add_marker_weights(body, rig)
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj, do_unlink=True)
    extras = []
    # Bare skull head with empty sockets; no glowing eyes.
    extras.extend(make_goat_skull(rig, bone, dark, None, horn))
    for side, s in (("l", 1), ("r", -1)):
        pts = [Vector((0.085 * s, -0.035, 1.720)), Vector((0.170 * s, 0.030, 1.770)),
               Vector((0.255 * s, 0.120, 1.735)), Vector((0.300 * s, 0.215, 1.635)),
               Vector((0.285 * s, 0.285, 1.530)), Vector((0.230 * s, 0.320, 1.455))]
        extras.append(make_horn(rig, side, pts,
                                [0.058, 0.052, 0.043, 0.031, 0.017, 0.003], horn, "Head", 48))
    # Compact black neck, no armor, no fur rings.
    extras.append(make_neck_tube(rig, skin))
    extras.extend(make_fur_patches(rig, fur))
    for side in ("l", "r"):
        extras.extend(make_hoof_boot(rig, side, horn, fur))
    extras.extend(add_hand_claws(rig, horn, 0.042))
    for obj in extras:
        if not any(m.type == "ARMATURE" for m in obj.modifiers):
            armature_modifier(obj, rig)
    joined = join_all(base + extras, body, rig)
    apply_orientation_and_scale(rig, joined, 1.08)

    def hunch(rig, t, dur):
        goat_hunch(rig, t, dur)

    clips = {}
    for key, src_name, new_name, duration in [
        ("idle", "Idle_Loop", "HellGoat_Idle_Loop", 2.50),
        ("walk", "Walk_Loop", "HellGoat_Walk_Loop", 1.333),
        ("run", "Sprint_Loop", "HellGoat_Run_Loop", 0.667),
    ]:
        act = bake_action(rig, actions[src_name], new_name, duration,
                          overlay=hunch, pelvis_offset=0.0)
        scale_action_locations(act, 1.08)
        clips[key] = {"name": new_name, "duration": duration}
    atk_src = actions["Sword_Overhead"]
    src_dur = (atk_src.frame_range[1] - atk_src.frame_range[0]) / FPS
    src_impact = 0.808
    def warp(t, dur=1.45, impact=0.62):
        if t <= impact:
            return src_impact * (t / max(1e-5, impact))
        return src_impact + (t - impact) / max(1e-5, dur - impact) * max(0.02, src_dur - src_impact)
    atk = bake_action(rig, atk_src, "HellGoat_Attack", 1.45, warp=warp,
                      overlay=lambda rig, t, dur: (goat_hunch(rig, t, dur),
                                                   goat_attack(rig, t, dur)),
                      pelvis_offset=0.0)
    scale_action_locations(atk, 1.08)
    clips["attack"] = {"name": "HellGoat_Attack", "duration": 1.45, "impact": 0.62}
    hit = bake_action(rig, actions["Idle_Loop"], "HellGoat_Hit", 0.50,
                      overlay=lambda rig, t, dur: (goat_hunch(rig, t, dur),
                                                   humanoid_hit(rig, t, dur, jaw=True)),
                      source_frame0=True, pelvis_offset=0.0)
    scale_action_locations(hit, 1.08)
    clips["hit"] = {"name": "HellGoat_Hit", "duration": 0.50}
    death = bake_action(rig, actions["Idle_Loop"], "HellGoat_Death", 1.25,
                        overlay=lambda rig, t, dur: (goat_hunch(rig, t, dur),
                                                     humanoid_death(rig, t, dur, jaw=True)),
                        source_frame0=True, pelvis_offset=0.0)
    scale_action_locations(death, 1.08)
    add_pelvis_drop(death, rig, 1.25, 0.30)
    clips["death"] = {"name": "HellGoat_Death", "duration": 1.25}
    order = [next(a for a in bpy.data.actions if a.name == f"HellGoat_{k}") for k in
             ["Idle_Loop", "Walk_Loop", "Run_Loop", "Attack", "Hit", "Death"]]
    meta = make_scene_export(rig, joined, order, DEVILS / "ironwood_hell_goat.glb",
                             mob, "Hellish goat man", clips, 0.20, 0.15,
                             ["jet-black furred body, black ram horns and hooves",
                              "bare goat skull head with empty sockets",
                              "no armor, harness, rings or glowing eyes",
                              "hunched feral locomotion and claw slam"],
                             "CC0 Quaternius male base and core animations; original black goat skull, fur, hooves and feral pose")
    render_preview(rig, joined, mob, "HellGoat_Idle_Loop")
    return meta


# ---------------------------------------------------------------------------
# Gargoyle


def gargoyle_wing_points(side: str) -> dict:
    """Half-raised stone bat wing whose finger tips clear the horns."""
    s = 1.0 if side == "l" else -1.0
    return {
        "shoulder": Vector((0.105 * s, 0.115, 1.455)),
        "elbow": Vector((0.350 * s, 0.170, 1.705)),
        "wrist": Vector((0.575 * s, 0.230, 1.850)),
        "top": Vector((0.800 * s, 0.310, 1.975)),
    }


def make_ellipsoid(rig, name, center, scale, material, bone="Head",
                   rotation=(0.0, 0.0, 0.0), us=28, vs=18):
    rot = Euler(rotation, "XYZ").to_matrix()
    c = Vector(center)
    sc = Vector(scale)
    verts, faces, uvs = [], [], []
    for i in range(vs + 1):
        theta = math.pi * i / vs
        st, ct = math.sin(theta), math.cos(theta)
        for j in range(us + 1):
            phi = math.tau * j / us
            local = Vector((sc.x * st * math.cos(phi),
                            sc.y * st * math.sin(phi),
                            sc.z * ct))
            verts.append(rot @ local + c)
            uvs.append((j / us, i / vs))
    for i in range(vs):
        for j in range(us):
            a = i * (us + 1) + j
            faces.append((a, a + 1, a + us + 2, a + us + 1))
    obj = mesh_object(name, verts, faces, uvs, material)
    rigid_skin(obj, rig, bone)
    return obj


def make_loft(rig, name, stations, material, bone="Head", sides=24):
    """Ring-lofted mass travelling along -Y (snout, jaw)."""
    verts, faces, uvs = [], [], []
    rings = len(stations)
    for i, (y, cz, rx, rz) in enumerate(stations):
        for j in range(sides):
            a = math.tau * j / sides
            verts.append(Vector((rx * math.cos(a), y, cz + rz * math.sin(a))))
            uvs.append((j / sides * 2.0, i / max(1, rings - 1)))
    for i in range(rings - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(range(sides - 1, -1, -1)))
    base = (rings - 1) * sides
    faces.append(tuple(base + j for j in range(sides)))
    obj = mesh_object(name, verts, faces, uvs, material)
    rigid_skin(obj, rig, bone)
    return obj


def make_blade(rig, name, spine, widths, thickness, material, bone="Head", sides=8):
    """Flattened pointed fin used for the ears."""
    pts = [Vector(p) for p in spine]
    obj, _ = tube(name, pts, widths, sides, material)
    for v in obj.data.vertices:
        v.co.y = pts[0].y + (v.co.y - pts[0].y) * thickness
    rigid_skin(obj, rig, bone)
    return obj


def make_tooth(rig, base, direction, length, radius, material, bone="Head", sides=8):
    d = Vector(direction).normalized()
    p0 = Vector(base)
    obj, _ = tube("Tooth", [p0, p0 + d * length * 0.5, p0 + d * length * 0.85,
                            p0 + d * length],
                  [radius, radius * 0.70, radius * 0.34, 0.0006], sides, material)
    rigid_skin(obj, rig, bone)
    return obj


# Bone-keyed radial inflation; chunkier than a uniform scale and still blends
# across joints because every vertex uses its own skin weights.
GARGOYLE_AXIS_BULK = {
    "clavicle": 1.38, "upperarm": 1.55, "lowerarm": 1.45, "hand": 1.20,
    "thigh": 1.40, "calf": 1.38, "spine_01": 1.26,
    "spine_02": 1.34, "spine_03": 1.42, "neck_01": 1.35, "pelvis": 1.20,
}

# (centre, radii, outward strength) in source rest space; mirrored later.
GARGOYLE_BULGES = [
    ((0.072, -0.060, 1.405), (0.075, 0.075, 0.070), 0.045),   # pectoral
    ((0.215, 0.060, 1.465), (0.075, 0.085, 0.080), 0.050),    # deltoid
    ((0.070, 0.055, 1.500), (0.085, 0.075, 0.055), 0.035),    # trapezius
    ((0.150, 0.070, 1.320), (0.070, 0.075, 0.110), 0.030),    # latissimus
    ((0.330, 0.060, 1.462), (0.095, 0.065, 0.060), 0.030),    # biceps
    ((0.560, 0.062, 1.458), (0.100, 0.060, 0.055), 0.022),    # forearm
    ((0.095, 0.110, 0.995), (0.075, 0.060, 0.085), 0.028),    # glute
    ((0.110, -0.020, 0.780), (0.075, 0.085, 0.150), 0.030),   # quadriceps
    ((0.118, 0.085, 0.360), (0.065, 0.070, 0.130), 0.026),    # calf
    ((0.000, -0.100, 1.230), (0.085, 0.055, 0.110), 0.014),   # abdominal wall
]


def bulk_gargoyle(body, rig) -> None:
    axis = {}
    for name, factor in GARGOYLE_AXIS_BULK.items():
        for side in ("l", "r") if name not in ("spine_01", "spine_02", "spine_03", "neck_01", "pelvis") else ("",):
            full = f"{name}_{side}" if side else name
            bone = rig.data.bones.get(full)
            if bone:
                axis[full] = (bone.head_local.copy(), bone.tail_local.copy(), factor)
    bulges = list(GARGOYLE_BULGES)
    bulges += [((-c[0], c[1], c[2]), r, w) for c, r, w in GARGOYLE_BULGES if abs(c[0]) > 1e-6]
    groups = {g.index: g.name for g in body.vertex_groups}
    verts = body.data.vertices
    normals = [v.normal.copy() for v in verts]
    for v, nrm in zip(verts, normals):
        p = v.co.copy()
        if p.z > 1.53:
            continue
        acc = Vector()
        total = 0.0
        for g in v.groups:
            bone_name = groups.get(g.group)
            entry = axis.get(bone_name)
            if entry is None or g.weight < 0.02:
                continue
            a, b, factor = entry
            if bone_name.startswith(("calf", "thigh")):
                factor = 1.0 + (factor - 1.0) * smooth(0.015, 0.16, p.z)
            ab = b - a
            if ab.length_squared < 1e-9:
                continue
            t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            acc += (p - (a + ab * t)) * (factor - 1.0) * g.weight
            total += g.weight
        if total > 1e-5:
            p += acc / total
        for center, radii, strength in bulges:
            dx = (p.x - center[0]) / radii[0]
            dy = (p.y - center[1]) / radii[1]
            dz = (p.z - center[2]) / radii[2]
            q = dx * dx + dy * dy + dz * dz
            if q < 3.4:
                p += nrm * (strength * math.exp(-q))
        v.co = p
    body.data.update()


GARGOYLE_HEAD_PIVOT = Vector((0.0, 0.010, 1.560))
GARGOYLE_HEAD_SCALE = 1.26


def make_gargoyle_head(rig, stone, horn_stone, dark, ember):
    parts = []
    # Cranium and jowl enclose the removed human face completely.
    parts.append(make_ellipsoid(rig, "GargoyleCranium", (0.0, -0.005, 1.725),
                                (0.115, 0.128, 0.112), stone))
    # Carved face plate: flattens the mask so the sockets read from the front.
    parts.append(make_ellipsoid(rig, "GargoyleFacePlate", (0.0, -0.110, 1.702),
                                (0.106, 0.032, 0.098), stone))
    parts.append(make_ellipsoid(rig, "GargoyleJowl", (0.0, -0.010, 1.618),
                                (0.108, 0.118, 0.070), stone))
    # Broad short snout below the eyes.
    parts.append(make_loft(rig, "GargoyleMuzzle", [
        (0.020, 1.690, 0.090, 0.058),
        (-0.040, 1.686, 0.094, 0.058),
        (-0.100, 1.680, 0.090, 0.055),
        (-0.150, 1.672, 0.084, 0.051),
        (-0.190, 1.664, 0.072, 0.046),
        (-0.218, 1.658, 0.056, 0.038),
        (-0.236, 1.654, 0.038, 0.030),
    ], stone))
    # Lower jaw hangs open in a snarl and follows the jaw bone.
    parts.append(make_loft(rig, "GargoyleJaw", [
        (0.000, 1.596, 0.098, 0.038),
        (-0.060, 1.590, 0.096, 0.036),
        (-0.120, 1.584, 0.086, 0.032),
        (-0.170, 1.578, 0.072, 0.028),
        (-0.210, 1.574, 0.052, 0.024),
        (-0.228, 1.572, 0.034, 0.020),
    ], stone, bone="jaw"))
    # Dark maw behind the bared teeth.
    parts.append(make_ellipsoid(rig, "GargoyleMaw", (0.0, -0.168, 1.612),
                                (0.070, 0.055, 0.020), dark))
    # Nose pad and bridge.
    parts.append(make_ellipsoid(rig, "GargoyleNosePad", (0.0, -0.236, 1.662),
                                (0.042, 0.011, 0.013), stone))
    nose_pts = [Vector((0.0, -0.145, 1.760)), Vector((0.0, -0.182, 1.714)),
                Vector((0.0, -0.218, 1.680))]
    nose, _ = tube("GargoyleNoseRidge", nose_pts, [0.016, 0.020, 0.012], 10, stone)
    rigid_skin(nose, rig, "Head")
    parts.append(nose)
    # Upper lip and upper fangs.
    lip_pts = [Vector((-0.070, -0.190, 1.636)), Vector((-0.036, -0.218, 1.632)),
               Vector((0.0, -0.230, 1.630)), Vector((0.036, -0.218, 1.632)),
               Vector((0.070, -0.190, 1.636))]
    lip, _ = tube("GargoyleLip", lip_pts, [0.014, 0.016, 0.017, 0.016, 0.014], 10, stone)
    rigid_skin(lip, rig, "Head")
    parts.append(lip)
    for i in range(9):
        x = -0.064 + 0.016 * i
        length = 0.018 + 0.013 * (1.0 - abs(x) / 0.072)
        parts.append(make_tooth(rig, Vector((x, -0.212 + abs(x) * 0.40, 1.633)),
                                Vector((0.0, -0.12, -1.0)), length, 0.0072,
                                horn_stone))
    for s in (-1, 1):
        # Socket: flat dark inset, thin orbital rim, ember lens deep inside.
        parts.append(make_ellipsoid(rig, "GargoyleSocket",
                                    (0.070 * s, -0.139, 1.716),
                                    (0.038, 0.006, 0.030), dark,
                                    rotation=(0.0, math.radians(14.0 * s), 0.0)))
        rim = []
        for i in range(16):
            a = math.tau * i / 16
            x = 0.070 * s + 0.047 * math.cos(a)
            z = 1.718 + 0.035 * math.sin(a) + 0.22 * (x - 0.070 * s)
            rim.append(Vector((x, -0.146, z)))
        orbit, _ = tube("GargoyleOrbit", rim, [0.010] * 16, 8, stone)
        rigid_skin(orbit, rig, "Head")
        parts.append(orbit)
        parts.append(make_ellipsoid(rig, "GargoyleEmber",
                                    (0.070 * s, -0.147, 1.714),
                                    (0.009, 0.005, 0.009), ember))
        # Heavy brow shelf over both sockets.
        brow_pts = [Vector((0.006 * s, -0.148, 1.738)),
                    Vector((0.040 * s, -0.152, 1.748)),
                    Vector((0.078 * s, -0.140, 1.744)),
                    Vector((0.104 * s, -0.094, 1.726))]
        brow, _ = tube("GargoyleBrow", brow_pts, [0.018, 0.027, 0.024, 0.014], 12, stone)
        for v in brow.data.vertices:
            v.co.z = 1.744 + (v.co.z - 1.744) * 0.68
        rigid_skin(brow, rig, "Head")
        parts.append(brow)
        # Angular cheek plate with a swept cheek horn.
        parts.append(make_ellipsoid(rig, "GargoyleCheek",
                                    (0.098 * s, -0.115, 1.672),
                                    (0.037, 0.050, 0.042), stone))
        parts.append(make_tooth(rig, Vector((0.100 * s, -0.135, 1.665)),
                                Vector((0.90 * s, -0.45, 0.05)), 0.060, 0.014,
                                horn_stone))
        # Brow horn.
        parts.append(make_tooth(rig, Vector((0.088 * s, -0.058, 1.780)),
                                Vector((0.55 * s, -0.30, 1.0)), 0.075, 0.016,
                                horn_stone))
        # Pointed ear.
        parts.append(make_blade(rig, "GargoyleEar",
                                [(0.100 * s, 0.006, 1.746),
                                 (0.150 * s, 0.046, 1.794),
                                 (0.204 * s, 0.092, 1.828),
                                 (0.240 * s, 0.122, 1.846)],
                                [0.038, 0.030, 0.017, 0.0015], 0.34, stone))
        # Swept-back crown horn.
        parts.append(make_horn(rig, "l" if s > 0 else "r",
                               [Vector((0.060 * s, 0.030, 1.806)),
                                Vector((0.130 * s, 0.078, 1.880)),
                                Vector((0.184 * s, 0.152, 1.932)),
                                Vector((0.208 * s, 0.240, 1.912)),
                                Vector((0.196 * s, 0.306, 1.842))],
                               [0.048, 0.038, 0.026, 0.014, 0.002],
                               horn_stone, "Head", 32))
        # Flared nostril.
        parts.append(make_ellipsoid(rig, "GargoyleNostril",
                                    (0.020 * s, -0.246, 1.660),
                                    (0.0085, 0.004, 0.0065), dark))
        # Lower fangs and a tusk outside the lip, both on the jaw.
        parts.append(make_tooth(rig, Vector((0.058 * s, -0.196, 1.598)),
                                Vector((0.05 * s, 0.04, 1.0)), 0.036, 0.010,
                                horn_stone, "jaw"))
        parts.append(make_tooth(rig, Vector((0.076 * s, -0.158, 1.592)),
                                Vector((0.16 * s, -0.22, 0.95)), 0.065, 0.014,
                                horn_stone, "jaw"))
        parts.append(make_tooth(rig, Vector((0.036 * s, -0.228, 1.560)),
                                Vector((0.18 * s, -0.55, -0.45)), 0.048, 0.011,
                                horn_stone, "jaw"))
    for i in range(7):
        x = -0.050 + 0.0167 * i
        parts.append(make_tooth(rig, Vector((x, -0.206 + abs(x) * 0.35, 1.598)),
                                Vector((0.0, 0.06, 1.0)), 0.017, 0.0062,
                                horn_stone, "jaw"))
    for obj in parts:
        for v in obj.data.vertices:
            v.co = GARGOYLE_HEAD_PIVOT + (v.co - GARGOYLE_HEAD_PIVOT) * GARGOYLE_HEAD_SCALE
        obj.data.update()
    return parts


def make_gargoyle_wing(rig, side, membrane_mat, rib_mat):
    """Boned bat wing: scalloped finger membrane, stone arm and rib struts."""
    s = 1.0 if side == "l" else -1.0
    shoulder = Vector((0.105 * s, 0.115, 1.455))
    elbow = Vector((0.350 * s, 0.170, 1.705))
    wrist = Vector((0.575 * s, 0.230, 1.850))
    tips = [Vector((0.800 * s, 0.310, 1.975)),
            Vector((0.760 * s, 0.385, 1.700)),
            Vector((0.660 * s, 0.435, 1.470)),
            Vector((0.540 * s, 0.458, 1.230)),
            Vector((0.425 * s, 0.452, 1.060))]
    body = Vector((0.130 * s, 0.190, 1.120))

    def scallop(a, b, count=4, depth=0.10):
        out = []
        for i in range(1, count):
            t = i / count
            out.append(a.lerp(b, t).lerp(wrist, depth * math.sin(math.pi * t)))
        return out

    boundary = [shoulder, elbow, wrist, tips[0]]
    for a, b in zip(tips, tips[1:]):
        boundary += scallop(a, b)
        boundary.append(b)
    boundary.append(body)
    center = sum(boundary, Vector()) / len(boundary)
    n = len(boundary)
    verts = [center + Vector((0.0, 0.020, 0.0))]
    uvs = [(0.5, 0.5)]
    for frac in (0.40, 0.72, 1.0):
        for i, p in enumerate(boundary):
            q = center.lerp(p, frac)
            q.y += 0.045 * math.sin(math.pi * 0.5 * frac) * math.sin(math.pi * (i + 0.5) / n)
            verts.append(q)
            uvs.append((0.5 + 0.5 * q.x / (0.86 * s if s > 0 else -0.86),
                        0.5 + (q.z - 1.48) / 0.62))
    faces = []
    for i in range(n):
        faces.append((0, 1 + i, 1 + (i + 1) % n))
    for r in range(2):
        a0 = 1 + r * n
        b0 = 1 + (r + 1) * n
        for i in range(n):
            i2 = (i + 1) % n
            faces.append((a0 + i, b0 + i, b0 + i2, a0 + i2))
    obj = mesh_object(f"GWingMembrane_{side}", verts, faces, uvs, membrane_mat)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    weight_by_segments(obj, rig, [f"wing_01_{side}", f"wing_02_{side}",
                                  f"wing_03_{side}", "spine_03"], power=2.0)
    solid = obj.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.030
    solid.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solid.name)
    parts = [obj]
    arm, _ = tube(f"GWingArm_{side}", [shoulder, elbow, wrist],
                  [0.045, 0.034, 0.022], 14, rib_mat)
    weight_by_segments(arm, rig, [f"wing_01_{side}", f"wing_02_{side}",
                                  f"wing_03_{side}"], power=2.5)
    parts.append(arm)
    for i, tip in enumerate(tips):
        midp = wrist.lerp(tip, 0.55) + Vector((0.0, 0.020, 0.0))
        strut, _ = tube(f"GWingRib_{side}_{i}", [wrist, midp, tip],
                        [0.018, 0.010, 0.003], 10, rib_mat)
        rigid_skin(strut, rig, f"wing_03_{side}" if i == 0 else f"wing_02_{side}")
        parts.append(strut)
    parts.append(make_tooth(rig, elbow + Vector((0.0, 0.030, 0.020)),
                            Vector((0.25 * s, 0.55, 0.60)), 0.080, 0.016, rib_mat,
                            f"wing_02_{side}"))
    parts.append(make_tooth(rig, tips[0] + Vector((0.0, 0.0, -0.012)),
                            Vector((0.25 * s, 0.05, 0.75)), 0.060, 0.012, rib_mat,
                            f"wing_03_{side}"))
    return parts


def build_gargoyle() -> dict:
    mob = "gargoyle"
    reset_scene()
    added, rig = import_gltf(BASE_UE / "Superhero_Male_FullBody.gltf")
    base = base_meshes(added)
    base = [o for o in base if o.name not in ("Face", "Eyebrows", "Eyes")]
    delete_objects([o for o in added if o.type == "MESH" and o not in base])
    body = find_body(base)
    print("BASE_GARGOYLE", [o.name for o in base], "bones", len(rig.data.bones))
    actions = import_ranger_actions()
    face = GARGOYLE_HEAD_PIVOT + (Vector((0.0, -0.128, 1.700)) - GARGOYLE_HEAD_PIVOT) * GARGOYLE_HEAD_SCALE
    jaw = GARGOYLE_HEAD_PIVOT + (Vector((0.0, -0.030, 1.620)) - GARGOYLE_HEAD_PIVOT) * GARGOYLE_HEAD_SCALE
    add_head_jaw_markers(rig, face, jaw)
    for side in ("l", "r"):
        add_wing_bones(rig, side, points=gargoyle_wing_points(side))
    tail_pts = [Vector((0, 0.10, 1.02)), Vector((0, 0.24, 0.92)),
                Vector((0, 0.36, 0.72)), Vector((0, 0.44, 0.50))]
    add_tail_bones(rig, tail_pts, "tail")
    td = base_material_maps(mob)
    stone = pbr_material("Stone_Gargoyle", td, "stone_albedo.png", "stone_normal.png",
                         "stone_roughness.png", emission="stone_emission.png",
                         emission_strength=0.65, roughness_value=0.80)
    horn_stone = pbr_material("HornStone_Gargoyle", td, "horn_albedo.png", "horn_normal.png",
                              "horn_roughness.png", emission="horn_emission.png",
                              emission_strength=0.25, roughness_value=0.74)
    dark = simple_material("Dark_Gargoyle", (0.004, 0.004, 0.004), 0.72)
    ember = simple_material("EmberEye_Gargoyle", (0.75, 0.06, 0.006), 0.25,
                            emission=(1.0, 0.10, 0.008), emission_strength=3.0)
    replace_materials_bulk(base, {"MI_Superhero_Male": stone})
    add_marker_weights(body, rig)
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj, do_unlink=True)
    # Bodybuilder mass, then UV project the sculpted surface.
    bulk_gargoyle(body, rig)
    smart_uv(body, 2.1)
    extras = make_gargoyle_head(rig, stone, horn_stone, dark, ember)
    # Stone collar spikes around the neck base.
    for i in range(11):
        a = math.tau * i / 11
        base_p = Vector((math.cos(a) * 0.125, math.sin(a) * 0.115 + 0.015, 1.558))
        extras.append(make_tooth(rig, base_p,
                                 Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, 0.55)),
                                 0.075, 0.019, horn_stone, "neck_01"))
    # Shoulder spikes; the outer pair rides the arm.
    for side, s in (("l", 1), ("r", -1)):
        extras.append(make_tooth(rig, Vector((0.150 * s, 0.010, 1.548)),
                                 Vector((0.45 * s, 0.10, 1.0)), 0.105, 0.022,
                                 horn_stone, "spine_03"))
        extras.append(make_tooth(rig, Vector((0.196 * s, 0.058, 1.522)),
                                 Vector((0.65 * s, 0.35, 0.9)), 0.115, 0.023,
                                 horn_stone, f"clavicle_{side}"))
        extras.append(make_tooth(rig, Vector((0.238 * s, -0.005, 1.470)),
                                 Vector((0.95 * s, -0.10, 0.55)), 0.090, 0.019,
                                 horn_stone, f"upperarm_{side}"))
    # Spinal ridge down the back.
    for bone, base_p, direction, length, radius in [
        ("spine_03", (0.0, 0.140, 1.520), (0.0, 0.55, 1.0), 0.115, 0.024),
        ("spine_03", (0.0, 0.152, 1.440), (0.0, 0.55, 1.0), 0.100, 0.022),
        ("spine_02", (0.0, 0.142, 1.360), (0.0, 0.60, 1.0), 0.090, 0.020),
        ("spine_02", (0.0, 0.132, 1.280), (0.0, 0.65, 1.0), 0.085, 0.019),
        ("spine_01", (0.0, 0.126, 1.200), (0.0, 0.65, 1.0), 0.080, 0.018),
        ("spine_01", (0.0, 0.126, 1.120), (0.0, 0.70, 1.0), 0.075, 0.017),
        ("pelvis", (0.0, 0.120, 1.040), (0.0, 0.70, 1.0), 0.065, 0.015),
    ]:
        extras.append(make_tooth(rig, Vector(base_p), Vector(direction), length,
                                 radius, horn_stone, bone))
    # Upper-arm and forearm ridges.
    for side, s in (("l", 1), ("r", -1)):
        extras.append(make_tooth(rig, Vector((0.300 * s, 0.120, 1.500)),
                                 Vector((0.25 * s, 0.75, 0.70)), 0.090, 0.018,
                                 horn_stone, f"upperarm_{side}"))
        for t, radius in ((0.45, 0.014), (0.72, 0.012)):
            px = (0.463 + (0.706 - 0.463) * t) * s
            extras.append(make_tooth(rig, Vector((px, 0.122, 1.455)),
                                     Vector((0.15 * s, 0.85, -0.25)),
                                     0.075 - t * 0.02, radius, horn_stone,
                                     f"lowerarm_{side}"))
    # Half-raised stone wings, heavy tail, oversized claws.
    for side in ("l", "r"):
        extras.extend(make_gargoyle_wing(rig, side, stone, horn_stone))
    extras.extend(make_tail(rig, tail_pts, [0.060, 0.048, 0.032, 0.016],
                            stone, horn_stone, [f"tail_{i:02d}" for i in range(1, 4)]))
    extras.extend(add_hand_claws(rig, horn_stone, 0.085))
    extras.extend(add_foot_claws(rig, horn_stone, 0.065, lift=0.045))
    for obj in extras:
        if not any(m.type == "ARMATURE" for m in obj.modifiers):
            armature_modifier(obj, rig)
    joined = join_all(base + extras, body, rig)
    scale = 1.62
    apply_orientation_and_scale(rig, joined, scale)

    def hunch(rig, t, dur):
        gargoyle_hunch(rig, t, dur)

    def loop_warp(source, duration):
        src_dur = (source.frame_range[1] - source.frame_range[0]) / FPS
        return lambda t, sd=src_dur, d=duration: t * sd / max(1e-5, d)

    clips = {}
    for key, src_name, new_name, duration in [
        ("idle", "Idle_Loop", "Gargoyle_Idle_Loop", 2.50),
        ("walk", "Walk_Loop", "Gargoyle_Walk_Loop", 1.333),
        ("run", "Jog_Fwd_Loop", "Gargoyle_Run_Loop", 0.933),
    ]:
        src = actions[src_name]
        act = bake_action(rig, src, new_name, duration,
                          warp=loop_warp(src, duration), overlay=hunch,
                          pelvis_offset=0.0)
        scale_action_locations(act, scale)
        clips[key] = {"name": new_name, "duration": duration}
    atk_src = actions["Sword_Overhead"]
    src_dur = (atk_src.frame_range[1] - atk_src.frame_range[0]) / FPS
    src_impact = 0.808
    def warp(t, dur=1.80, impact=0.95):
        if t <= impact:
            return src_impact * (t / max(1e-5, impact))
        return src_impact + (t - impact) / max(1e-5, dur - impact) * max(0.02, src_dur - src_impact)
    atk = bake_action(rig, atk_src, "Gargoyle_Attack", 1.80, warp=warp,
                      overlay=lambda rig, t, dur: (gargoyle_hunch(rig, t, dur),
                                                   gargoyle_attack(rig, t, dur)),
                      pelvis_offset=0.0)
    scale_action_locations(atk, scale)
    clips["attack"] = {"name": "Gargoyle_Attack", "duration": 1.80, "impact": 0.95}
    hit = bake_action(rig, actions["Crouch_Idle_Loop"], "Gargoyle_Hit", 0.50,
                      overlay=lambda rig, t, dur: (gargoyle_hunch(rig, t, dur),
                                                   humanoid_hit(rig, t, dur, jaw=True)),
                      source_frame0=True, pelvis_offset=0.0)
    scale_action_locations(hit, scale)
    clips["hit"] = {"name": "Gargoyle_Hit", "duration": 0.50}
    death = bake_action(rig, actions["Crouch_Idle_Loop"], "Gargoyle_Death", 1.40,
                        overlay=lambda rig, t, dur: (gargoyle_hunch(rig, t, dur),
                                                     humanoid_death(rig, t, dur, jaw=True,
                                                                    wings=True, tail=True)),
                        source_frame0=True, pelvis_offset=0.0)
    scale_action_locations(death, scale)
    add_pelvis_drop(death, rig, 1.40, 0.32)
    clips["death"] = {"name": "Gargoyle_Death", "duration": 1.40}
    order = [next(a for a in bpy.data.actions if a.name == f"Gargoyle_{k}") for k in
             ["Idle_Loop", "Walk_Loop", "Run_Loop", "Attack", "Hit", "Death"]]
    meta = make_scene_export(rig, joined, order, DEVILS / "ironwood_gargoyle.glb",
                             mob, "Gargoyle", clips, 0.30, 0.20,
                             ["heavily muscled basalt anatomy, hunched predator stance",
                              "carved demon face: heavy brow, deep sockets, ember eyes, bared fangs",
                              "swept crown horns, pointed ears, spinal and shoulder spikes",
                              "half-raised stone bat wings, heavy tail, oversized claws"],
                             "CC0 Quaternius male base plus core animations; original carved gargoyle head, muscle sculpt, stone wings, horns, claws and stance")
    render_preview(rig, joined, mob, "Gargoyle_Idle_Loop")
    render_head_preview(rig, mob, "Gargoyle_Idle_Loop")
    return meta


# ---------------------------------------------------------------------------
# Devil spawn


def build_spawn() -> dict:
    mob = "spawn"
    reset_scene()
    added, rig = import_gltf(BASE_UE / "Superhero_Female_FullBody.gltf")
    base = base_meshes(added)
    base = [o for o in base if o.name != "Eyebrows"]
    delete_objects([o for o in added if o.type == "MESH" and o not in base])
    body = find_body(base)
    pivot = Vector((0.0, 0.0, 1.520))
    enlarge_head(base, pivot, 1.30)
    print("BASE_SPAWN", [o.name for o in base], "bones", len(rig.data.bones))
    actions = import_ranger_actions()
    face = pivot + (Vector((0.0, -0.095, 1.620)) - pivot) * 1.30
    jaw = pivot + (Vector((0.0, -0.085, 1.565)) - pivot) * 1.30
    add_head_jaw_markers(rig, face, jaw)
    tail_pts = [Vector((0, 0.07, 0.95)), Vector((0, 0.20, 0.86)),
                Vector((0, 0.31, 0.72)), Vector((0, 0.37, 0.56))]
    add_tail_bones(rig, tail_pts, "tail")
    td = base_material_maps(mob)
    skin = pbr_material("Skin_Spawn", td, "skin_albedo.png", "skin_normal.png",
                        "skin_roughness.png", roughness_value=0.52)
    eye = pbr_material("Eye_Spawn", td, "eye_albedo.png", "eye_normal.png",
                       emission="eye_emission.png", emission_strength=3.0, roughness_value=0.22)
    horn = pbr_material("Horn_Spawn", td, "horn_albedo.png", "horn_normal.png",
                        "horn_roughness.png", roughness_value=0.38)
    cloth = pbr_material("Cloth_Spawn", td, "cloth_albedo.png", "cloth_normal.png",
                         "cloth_roughness.png", roughness_value=0.90)
    leather = pbr_material("Leather_Spawn", td, "leather_albedo.png", "leather_normal.png",
                           "leather_roughness.png", roughness_value=0.60)
    metal = simple_material("Metal_Spawn", (0.03, 0.026, 0.022), 0.4, 0.8)
    dark = simple_material("Dark_Spawn", (0.005, 0.004, 0.003), 0.65)
    replace_materials_bulk(base, {"MI_Superhero_Female": skin, "MI_Eyes": eye})
    add_marker_weights(body, rig)
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj, do_unlink=True)
    extras = []
    for side, s in (("l", 1), ("r", -1)):
        points = [Vector((0.060 * s, -0.055, 1.750)), Vector((0.095 * s, 0.010, 1.820)),
                  Vector((0.090 * s, 0.075, 1.860))]
        extras.append(make_horn(rig, side, points, [0.030, 0.021, 0.003], horn, "Head", 28))
    extras.extend(add_hand_claws(rig, horn, 0.030))
    extras.extend(add_foot_claws(rig, horn, 0.038))
    for s in (-1, 1):
        extras.append(make_fang(rig, Vector((0.028 * s, -0.140, 1.612)),
                                Vector((0.0, -0.25, -1.0)), 0.025, horn, "Head"))
    extras.extend(make_tail(rig, tail_pts, [0.028, 0.020, 0.012, 0.005],
                            skin, horn, [f"tail_{i:02d}" for i in range(1, 4)]))
    extras.append(make_skirt(rig, 1.060, 0.790, 0.265, 0.330, cloth, "Loincloth", 44, 0.05))
    extras.append(make_chest_wrap(rig, cloth))
    extras.extend(make_belt(rig, 1.050, 0.285, leather, metal, "Belt"))
    for obj in extras:
        if not any(m.type == "ARMATURE" for m in obj.modifiers):
            armature_modifier(obj, rig)
    joined = join_all(base + extras, body, rig)
    apply_orientation_and_scale(rig, joined, 0.58)
    pelvis_offset = 0.017 * 0.58
    extra_kinds = {"tail": ["tail_01", "tail_02", "tail_03"]}
    clips, baked = build_actions(
        rig, actions,
        [("idle", "Crouch_Idle_Loop", "Spawn_Idle_Loop"),
         ("walk", "Crouch_Fwd_Loop", "Spawn_Walk_Loop"),
         ("run", "Sprint_Loop", "Spawn_Run_Loop")],
        0.58, pelvis_offset, extra_kinds,
        {"source": "Dagger_Stab", "source_impact": 0.225,
         "duration": 1.10, "impact": 0.48, "name": "Spawn_Attack"},
        {"name": "Spawn_Hit", "duration": 0.40},
        {"name": "Spawn_Death", "duration": 1.00},
        spawn_attack,
        lambda rig, t, dur: humanoid_hit(rig, t, dur, jaw=True),
        lambda rig, t, dur: humanoid_death(rig, t, dur, jaw=True, tail=True),
        extra_kinds,
    )
    add_pelvis_drop(next(a for a in bpy.data.actions if a.name == "Spawn_Death"), rig, 1.00, 0.20)
    order = [next(a for a in bpy.data.actions if a.name == f"Spawn_{k}") for k in
             ["Idle_Loop", "Walk_Loop", "Run_Loop", "Attack", "Hit", "Death"]]
    meta = make_scene_export(rig, joined, order, DEVILS / "ironwood_spawn.glb",
                             mob, "Devil spawn", clips, 0.165, 0.13,
                             ["pale sickly source skin with veins", "enlarged head",
                              "small horns, fangs and needle claws", "ragged chest wrap and loincloth"],
                             "CC0 Quaternius female base and core animations; original spawn proportions, horns, claws, fangs and rags")
    render_preview(rig, joined, mob, "Spawn_Idle_Loop")
    return meta


# ---------------------------------------------------------------------------
# Hell beast


def build_beast() -> dict:
    mob = "beast"
    reset_scene()
    added, rig = import_gltf(WOLF_GLB)
    meshes = [o for o in added if o.type == "MESH" and o.name == "WolfMesh"]
    delete_objects([o for o in added if o.type == "MESH" and o not in meshes])
    body = meshes[0]
    actions = {a.name: a for a in bpy.data.actions}
    for a in actions.values():
        a.use_fake_user = True
    print("BASE_BEAST", body.name, "bones", len(rig.data.bones), "actions", sorted(actions))
    td = base_material_maps(mob)
    fur = pbr_material("Fur_Beast", td, "beast_coat_albedo.png", "beast_coat_normal.png",
                       "beast_coat_roughness.png", emission="beast_coat_emission.png",
                       emission_strength=1.8, roughness_value=0.82)
    horn = pbr_material("Horn_Beast", td, "horn_albedo.png", "horn_normal.png",
                        "horn_roughness.png", roughness_value=0.40)
    iris = simple_material("EyeIris_Beast", (0.9, 0.14, 0.015), 0.22,
                           emission=(1.0, 0.18, 0.012), emission_strength=4.0)
    teeth = simple_material("Teeth_Beast", (0.62, 0.58, 0.46), 0.34)
    mouth = simple_material("Mouth_Beast", (0.16, 0.018, 0.02), 0.55)
    tongue = simple_material("Tongue_Beast", (0.42, 0.035, 0.045), 0.48)
    nose = simple_material("Nose_Beast", (0.018, 0.014, 0.012), 0.42)
    pads = simple_material("Pads_Beast", (0.045, 0.032, 0.028), 0.66)
    dark = simple_material("Dark_Beast", (0.005, 0.004, 0.003), 0.65)
    replace_materials(body, {
        "Wolf_Fur": fur, "Wolf_Iris": iris, "Wolf_Teeth": teeth,
        "Wolf_Mouth": mouth, "Wolf_Tongue": tongue, "Wolf_Nose": nose,
        "Wolf_EyeSocket": dark, "Wolf_Pupil": dark, "Wolf_Pads": pads,
    })
    extras = []
    # Horns from the skull.
    for side, s in (("l", 1), ("r", -1)):
        pts = [Vector((0.105 * s, 0.630, 1.105)), Vector((0.160 * s, 0.500, 1.220)),
               Vector((0.195 * s, 0.345, 1.295)), Vector((0.180 * s, 0.210, 1.315))]
        extras.append(make_horn(rig, side, pts, [0.034, 0.027, 0.015, 0.003], horn, "head", 32))
    # Spine ridge.
    for i, (bone, base, direction, length) in enumerate([
        ("chest", (0.0, 0.280, 1.010), (0.0, -0.15, 1.0), 0.130),
        ("spine_02", (0.0, 0.080, 1.055), (0.0, -0.10, 1.0), 0.160),
        ("spine_01", (0.0, -0.120, 1.045), (0.0, -0.10, 1.0), 0.140),
        ("pelvis", (0.0, -0.300, 0.995), (0.0, -0.05, 1.0), 0.110),
    ]):
        extras.append(make_spike(rig, bone, Vector(base), Vector(direction), length,
                                 horn, sides=8, radius=0.026))
    # Toe claws.
    for side in ("l", "r"):
        for limb in ("front", "hind"):
            bone = rig.data.bones.get(f"{limb}_toes_{side}")
            if not bone:
                continue
            for i in range(3):
                off = (i - 1) * 0.022
                extras.append(make_claw(rig, bone.name,
                                        bone.tail_local + Vector((off, 0, 0)),
                                        Vector((0, 1, -0.18)), 0.055, horn, 8))
    for obj in extras:
        if not any(m.type == "ARMATURE" for m in obj.modifiers):
            armature_modifier(obj, rig)
    joined = join_all(meshes + extras, body, rig)
    apply_scale_only(rig, joined, 1.35)
    clips = {}
    for key, src, new in [
        ("idle", "Wolf_Idle_Loop", "Beast_Idle_Loop"),
        ("walk", "Wolf_Trot_Loop", "Beast_Walk_Loop"),
        ("run", "Wolf_Trot_Loop", "Beast_Run_Loop"),
    ]:
        act = copy_action_rename(actions[src], new)
        scale_action_locations(act, 1.35)
        clips[key] = {"name": new, "duration": (act.frame_range[1] - act.frame_range[0]) / FPS}
    src = actions["Wolf_Attack"]
    src_duration = (src.frame_range[1] - src.frame_range[0]) / FPS
    src_impact = 0.65
    def warp(t, dur=1.60, impact=0.82):
        if t <= impact:
            return src_impact * (t / max(1e-5, impact))
        return src_impact + (t - impact) / max(1e-5, dur - impact) * max(0.02, src_duration - src_impact)
    atk = bake_action(rig, src, "Beast_Attack", 1.60, warp=warp, pelvis_offset=0.0)
    scale_action_locations(atk, 1.35)
    clips["attack"] = {"name": "Beast_Attack", "duration": 1.60, "impact": 0.82}
    hit = bake_action(rig, actions["Wolf_Idle_Loop"], "Beast_Hit", 0.50,
                      overlay=beast_hit, source_frame0=True, pelvis_offset=0.0)
    scale_action_locations(hit, 1.35)
    clips["hit"] = {"name": "Beast_Hit", "duration": 0.50}
    death = copy_action_rename(actions["Wolf_Death"], "Beast_Death")
    scale_action_locations(death, 1.35)
    clips["death"] = {"name": "Beast_Death", "duration": (death.frame_range[1] - death.frame_range[0]) / FPS}
    order = [next(a for a in bpy.data.actions if a.name == f"Beast_{k}") for k in
             ["Idle_Loop", "Walk_Loop", "Run_Loop", "Attack", "Hit", "Death"]]
    meta = make_scene_export(rig, joined, order, DEVILS / "ironwood_beast.glb",
                             mob, "Hell beast", clips, 0.38, 0.20,
                             ["charred wolf fur with ember fissures", "bone horns and spinal ridge",
                              "enlarged claws", "glowing eyes"],
                             "CC0 wolf asset plus original char/ember treatment, horns, ridge and claws")
    render_preview(rig, joined, mob, "Beast_Idle_Loop")
    return meta


def parse_args() -> list[str]:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    if not argv or argv[0] == "all":
        return ["succubus", "hell_goat", "gargoyle", "spawn", "beast"]
    return argv


def main() -> None:
    builders = {
        "succubus": build_succubus,
        "hell_goat": build_hell_goat,
        "gargoyle": build_gargoyle,
        "spawn": build_spawn,
        "beast": build_beast,
    }
    for mob in parse_args():
        if mob not in builders:
            raise SystemExit(f"Unknown mob: {mob}")
        meta = builders[mob]()
        print("BUILT", mob, meta["mesh_triangles"], meta["bone_count"])


if __name__ == "__main__":
    main()
