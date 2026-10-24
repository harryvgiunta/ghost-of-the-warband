"""Rebuild the five devil mobs from the project's licensed CC0 Quaternius sources.

This is the source-based replacement for the procedural metaball pipeline.  It
imports the same base characters, outfits, hair and skeleton used by the
ranger, recolours them with authored PBR maps, adds devil anatomy (horns,
wings, tails, skulls, claws, fur, stone), and exports six baked 60 Hz clips.

Blender 5.1, Z-up, metres, source forward -Y (glTF +Z).  The finished rig is
rotated 180 degrees so the exported asset faces glTF -Z, matching Godot and
the existing DevilMob forward contract.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
FPS = 60
TAU = math.tau

if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))
from devil_styles import BASE_UE, HAIR, OUTFIT_DIR  # noqa: E402

CHAR = ROOT / "assets" / "characters"
DEVILS = CHAR / "devils"
RANGER_GLB = CHAR / "ironwood_ranger.glb"
WOLF_GLB = CHAR / "ironwood_wolf.glb"
SOURCE_RUNTIME = ROOT / ".runtime" / "devil-source"


# ---------------------------------------------------------------------------
# Scene and imports


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def import_gltf(path: Path) -> tuple[list[bpy.types.Object], bpy.types.Object | None]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    added = [o for o in bpy.data.objects if o not in before]
    rig = next((o for o in added if o.type == "ARMATURE"), None)
    return added, rig


def delete_objects(objs) -> None:
    for obj in list(objs):
        if obj and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def mesh_objects(objs) -> list[bpy.types.Object]:
    return [o for o in objs if o.type == "MESH"]


def replace_armature(obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    for mod in list(obj.modifiers):
        if mod.type == "ARMATURE":
            mod.object = rig
    if not any(mod.type == "ARMATURE" for mod in obj.modifiers):
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)


def import_piece(path: Path, rig: bpy.types.Object, keep_names: list[str] | None = None) -> list[bpy.types.Object]:
    added, old_rig = import_gltf(path)
    meshes = mesh_objects(added)
    if keep_names:
        kept = []
        for name in keep_names:
            match = [m for m in meshes if m.name == name or m.name.startswith(name + ".")]
            if not match:
                match = [m for m in meshes if name in m.name]
            kept.extend(match)
        meshes = kept
    for mesh in meshes:
        replace_armature(mesh, rig)
    delete_objects([o for o in added if o not in meshes])
    # The base import can leave a helper icosphere; strip it everywhere.
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.name.startswith("Icosphere") and obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    return meshes


def import_ranger_actions() -> dict[str, bpy.types.Action]:
    added, _rig = import_gltf(RANGER_GLB)
    actions = {a.name: a for a in bpy.data.actions}
    for action in actions.values():
        action.use_fake_user = True
    delete_objects(added)
    return actions


def find_bone(rig: bpy.types.Object, *names: str):
    for name in names:
        bone = rig.data.bones.get(name)
        if bone:
            return bone
    return None


# ---------------------------------------------------------------------------
# Materials


def load_image(path: Path, colorspace: str, non_color: bool = False):
    img = bpy.data.images.load(str(path), check_existing=True)
    img.colorspace_settings.name = "Non-Color" if non_color else colorspace
    return img


def pbr_material(name: str, texture_dir: Path, albedo: str | None, normal: str | None,
                 roughness: str | None = None, metallic: str | None = None,
                 emission: str | None = None, emission_strength: float = 1.0,
                 roughness_value: float = 0.6, metallic_value: float = 0.0,
                 dark: bool = False) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        out = nodes.get("Material Output") or nodes.new("ShaderNodeOutputMaterial")
        links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Metallic"].default_value = metallic_value
    bsdf.inputs["Roughness"].default_value = roughness_value

    def tex(path: str | None, non_color: bool):
        if not path:
            return None
        node = nodes.new("ShaderNodeTexImage")
        node.image = load_image(texture_dir / path, "Non-Color" if non_color else "sRGB", non_color)
        node.interpolation = "Linear"
        return node

    alb = tex(albedo, False)
    if alb:
        links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    elif dark:
        bsdf.inputs["Base Color"].default_value = (0.012, 0.010, 0.010, 1.0)
    nrm = tex(normal, True)
    if nrm:
        nmap = nodes.new("ShaderNodeNormalMap")
        links.new(nrm.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    rough = tex(roughness, True)
    if rough:
        links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    metal = tex(metallic, True)
    if metal:
        links.new(metal.outputs["Color"], bsdf.inputs["Metallic"])
    if emission:
        em = tex(emission, False)
        if em:
            links.new(em.outputs["Color"], bsdf.inputs.get("Emission Color", bsdf.inputs.get("Emission")))
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def simple_material(name: str, color, roughness: float = 0.5, metallic: float = 0.0,
                    emission=None, emission_strength: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.use_backface_culling = False
    return mat


def replace_materials(obj: bpy.types.Object, mapping: dict[str, bpy.types.Material], default=None) -> None:
    for slot in obj.material_slots:
        old = slot.material
        if old is None:
            continue
        base = old.name.split(".")[0]
        new = mapping.get(old.name) or mapping.get(base)
        if new is None and default is not None:
            new = default
        if new is not None:
            slot.material = new


# ---------------------------------------------------------------------------
# Vertex groups / skinning


def armature_modifier(obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    for mod in obj.modifiers:
        if mod.type == "ARMATURE":
            mod.object = rig
            return
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)


def rigid_skin(obj: bpy.types.Object, rig: bpy.types.Object, bone: str) -> None:
    armature_modifier(obj, rig)
    vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def segment_distance(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    denom = ab.length_squared
    if denom < 1e-9:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length


def weight_by_segments(obj: bpy.types.Object, rig: bpy.types.Object, bones: list[str],
                       power: float = 2.0, max_bones: int = 4) -> None:
    armature_modifier(obj, rig)
    segs = []
    for name in bones:
        b = rig.data.bones.get(name)
        if b:
            segs.append((name, b.head_local.copy(), b.tail_local.copy()))
    if not segs:
        return
    groups = {name: (obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)) for name, _, _ in segs}
    for vert in obj.data.vertices:
        p = vert.co
        scored = []
        for name, a, b in segs:
            d = segment_distance(p, a, b)
            scored.append((1.0 / max(1e-4, d) ** power, name))
        scored.sort(reverse=True)
        scored = scored[:max_bones]
        total = sum(w for w, _ in scored)
        for w, name in scored:
            if w / total > 1e-4:
                groups[name].add([vert.index], w / total, "REPLACE")


def add_group_weight(obj: bpy.types.Object, bone: str, indices: list[int], weight: float) -> None:
    vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    vg.add(indices, weight, "REPLACE")


# ---------------------------------------------------------------------------
# Rig extras


def edit_bones(rig: bpy.types.Object):
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    return rig.data.edit_bones


def add_bone(rig: bpy.types.Object, name: str, head, tail, parent: str, deform: bool = True) -> None:
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones.new(name)
    eb.head = Vector(head)
    eb.tail = Vector(tail)
    eb.parent = rig.data.edit_bones.get(parent)
    eb.use_connect = False
    eb.use_deform = deform
    bpy.ops.object.mode_set(mode="OBJECT")


def add_head_jaw_markers(rig: bpy.types.Object, face: Vector, jaw: Vector) -> None:
    add_bone(rig, "head", face, face + Vector((0.0, -0.055, 0.015)), "Head", True)
    add_bone(rig, "jaw", jaw, jaw + Vector((0.0, -0.045, -0.010)), "Head", True)


def wing_points(side: str, spread: bool = False) -> dict:
    """Wing skeleton. Folded is a narrow back-hanging wing; spread is a full
    half-open bat wing for the succubus."""
    s = 1.0 if side == "l" else -1.0
    if spread:
        shoulder = Vector((0.12 * s, 0.12, 1.42))
        elbow = Vector((0.55 * s, 0.20, 1.62))
        wrist = Vector((0.92 * s, 0.28, 1.50))
        top = Vector((1.15 * s, 0.36, 1.32))
        bottom = Vector((0.72 * s, 0.44, 0.82))
        body = Vector((0.15 * s, 0.20, 1.00))
    else:
        shoulder = Vector((0.10 * s, 0.13, 1.43))
        elbow = Vector((0.30 * s, 0.19, 1.63))
        wrist = Vector((0.25 * s, 0.30, 1.55))
        top = Vector((0.33 * s, 0.35, 1.30))
        bottom = Vector((0.18 * s, 0.36, 0.95))
        body = Vector((0.10 * s, 0.20, 1.00))
    return {"shoulder": shoulder, "elbow": elbow, "wrist": wrist,
            "top": top, "bottom": bottom, "body": body, "spread": spread}


def add_wing_bones(rig: bpy.types.Object, side: str, spread: bool = False,
                   points: dict | None = None) -> None:
    p = points if points is not None else wing_points(side, spread)
    add_bone(rig, f"wing_01_{side}", p["shoulder"], p["elbow"], "spine_03", True)
    add_bone(rig, f"wing_02_{side}", p["elbow"], p["wrist"], f"wing_01_{side}", True)
    add_bone(rig, f"wing_03_{side}", p["wrist"], p["top"], f"wing_02_{side}", True)

def add_tail_bones(rig: bpy.types.Object, points: list[Vector], prefix: str = "tail") -> None:
    for i in range(len(points) - 1):
        parent = "pelvis" if i == 0 else f"{prefix}_{i:02d}"
        add_bone(rig, f"{prefix}_{i + 1:02d}", points[i], points[i + 1], parent, True)


# ---------------------------------------------------------------------------
# Mesh building


def mesh_object(name: str, verts, faces, uvs=None, material=None) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    if material:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    if uvs:
        layer = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            for loop_i in poly.loop_indices:
                vi = mesh.loops[loop_i].vertex_index
                if vi < len(uvs):
                    layer.data[loop_i].uv = uvs[vi]
    return obj


def tube(name: str, points: list[Vector], radii: list[float], sides: int,
         material, sides_uv: bool = True) -> tuple[bpy.types.Object, list[Vector]]:
    points = [Vector(p) for p in points]
    radii = list(radii)
    verts, uvs, faces = [], [], []
    frames = []
    prev_n = None
    for i, p in enumerate(points):
        if i == 0:
            tangent = (points[1] - p).normalized()
        elif i == len(points) - 1:
            tangent = (p - points[-2]).normalized()
        else:
            tangent = (points[i + 1] - points[i - 1]).normalized()
        if prev_n is None:
            ref = Vector((0, 0, 1)) if abs(tangent.z) < 0.85 else Vector((0, 1, 0))
            n = tangent.cross(ref).normalized()
            if n.length < 1e-5:
                n = tangent.cross(Vector((1, 0, 0))).normalized()
        else:
            n = prev_n - tangent * prev_n.dot(tangent)
            if n.length < 1e-5:
                n = tangent.cross(Vector((0, 0, 1))).normalized()
            n.normalize()
        prev_n = n
        b = tangent.cross(n).normalized()
        frames.append((n, b))
        for j in range(sides):
            a = TAU * j / sides
            verts.append(p + n * math.cos(a) * radii[i] + b * math.sin(a) * radii[i])
            uvs.append((j / sides, i / max(1, len(points) - 1)))
    rings = len(points)
    for i in range(rings - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            c = (i + 1) * sides + (j + 1) % sides
            d = (i + 1) * sides + j
            faces.append((a, b, c, d))
    # caps
    faces.append(tuple(range(sides - 1, -1, -1)))
    base = (rings - 1) * sides
    faces.append(tuple(base + j for j in range(sides)))
    return mesh_object(name, verts, faces, uvs, material), verts


def curved_points(start, ctrl, end, count: int) -> list[Vector]:
    a, b, c = Vector(start), Vector(ctrl), Vector(end)
    out = []
    for i in range(count):
        t = i / max(1, count - 1)
        out.append((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c)
    return out


def make_horn(rig, side: str, points, radii, material, bone="Head", sides=48) -> bpy.types.Object:
    obj, _ = tube(f"Horn_{side}", points, radii, sides, material)
    rigid_skin(obj, rig, bone)
    return obj


def make_claw(rig, bone: str, base: Vector, direction: Vector, length: float,
              material, sides=8) -> bpy.types.Object:
    direction = direction.normalized()
    down = Vector((0, 0, -1))
    p0 = base
    p1 = base + direction * length * 0.35 + down * length * 0.06
    p2 = base + direction * length * 0.70 + down * length * 0.28
    p3 = base + direction * length * 0.92 + down * length * 0.60
    obj, _ = tube("Claw", [p0, p1, p2, p3], [0.010, 0.008, 0.0045, 0.0005], sides, material)
    rigid_skin(obj, rig, bone)
    return obj


def make_fang(rig, base: Vector, direction: Vector, length: float, material, bone="Head") -> bpy.types.Object:
    direction = direction.normalized()
    pts = [base, base + direction * length * 0.45, base + direction * length * 0.85,
           base + direction * length]
    obj, _ = tube("Fang", pts, [0.007, 0.0055, 0.0028, 0.0005], 8, material)
    rigid_skin(obj, rig, bone)
    return obj


def make_spike(rig, bone: str, base: Vector, direction: Vector, length: float,
               material, sides=8, radius=0.025) -> bpy.types.Object:
    d = direction.normalized()
    pts = [base, base + d * length * 0.45, base + d * length]
    obj, _ = tube("Spike", pts, [radius, radius * 0.55, 0.0005], sides, material)
    rigid_skin(obj, rig, bone)
    return obj


# ---------------------------------------------------------------------------
# Wings, tails, cloth, fur, skull


def make_wing(rig, side: str, membrane_mat, skin_mat, thickness: float = 0.004,
              spread: bool = False) -> list[bpy.types.Object]:
    """Clean bat-wing membrane sheet: leading arm, trailing scalloped edge and
    four visible finger struts.  No radial fan or chopped wedges."""
    p = wing_points(side, spread)
    s = 1.0 if side == "l" else -1.0
    shoulder, elbow, wrist = p["shoulder"], p["elbow"], p["wrist"]
    top, bottom, body = p["top"], p["bottom"], p["body"]

    def leading(u):
        if u < 0.42:
            return shoulder.lerp(elbow, u / 0.42)
        if u < 0.70:
            return elbow.lerp(wrist, (u - 0.42) / 0.28)
        return wrist.lerp(top, (u - 0.70) / 0.30)

    mid = body.lerp(bottom, 0.55) + Vector((0.0, 0.035, 0.015))

    def trailing(u):
        # Quadratic body->mid->bottom with a gentle scalloped bat edge.
        q = (1 - u) ** 2 * body + 2 * (1 - u) * u * mid + u * u * bottom
        q += Vector((0.012 * math.sin(u * math.pi * 4.0) * s,
                     0.010 * math.sin(u * math.pi * 3.0), 0.0))
        return q

    rows, cols = 14, 10
    verts, uvs, faces = [], [], []
    for i in range(rows + 1):
        u = i / rows
        L, T = leading(u), trailing(u)
        for j in range(cols + 1):
            v = j / cols
            q = L.lerp(T, v)
            billow = 0.030 * math.sin(math.pi * v) * math.sin(math.pi * u)
            q.y += billow
            q.x += 0.18 * billow * s
            q.z += 0.012 * math.sin(math.pi * v) * math.sin(math.pi * u * 2.0)
            verts.append(q)
            uvs.append((u * 1.6, v))
    for i in range(rows):
        for j in range(cols):
            a = i * (cols + 1) + j
            b = a + 1
            c = a + cols + 2
            d = a + cols + 1
            faces.append((a, b, c, d))
    obj = mesh_object(f"WingMembrane_{side}", verts, faces, uvs, membrane_mat)
    weight_by_segments(obj, rig, [f"wing_01_{side}", f"wing_02_{side}",
                                  f"wing_03_{side}", "spine_03"], power=2.0)
    solid = obj.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solid.name)
    parts = [obj]
    arm, _ = tube(f"WingArm_{side}", [shoulder, elbow, wrist], [0.038, 0.030, 0.020], 16, skin_mat)
    weight_by_segments(arm, rig, [f"wing_01_{side}", f"wing_02_{side}", f"wing_03_{side}"], power=2.5)
    parts.append(arm)
    for idx, u in enumerate((0.64, 0.80, 0.93, 1.0)):
        tip = trailing(u)
        midp = wrist.lerp(tip, 0.55) + Vector((0.0, 0.010, 0.0))
        strut, _ = tube(f"WingStrut_{side}_{idx}", [wrist, midp, tip],
                        [0.012, 0.007, 0.0025], 10, skin_mat)
        rigid_skin(strut, rig, f"wing_03_{side}")
        parts.append(strut)
    claw = make_claw(rig, f"wing_03_{side}", wrist + Vector((0.015 * s, -0.01, 0.01)),
                     Vector((0.35 * s, -0.15, 0.85)), 0.045, skin_mat, 6)
    parts.append(claw)
    return parts

def make_tail(rig, points, radii, material, tip_material, tail_bones, spade=True) -> list[bpy.types.Object]:
    obj, _ = tube("Tail", points, radii, 14, material)
    weight_by_segments(obj, rig, tail_bones, power=2.4)
    parts = [obj]
    tip = Vector(points[-1])
    if spade:
        # Flattened diamond spade.
        d = (Vector(points[-1]) - Vector(points[-2])).normalized()
        side = d.cross(Vector((0, 0, 1))).normalized()
        if side.length < 1e-5:
            side = Vector((1, 0, 0))
        up = d.cross(side).normalized()
        verts = [tip + d * 0.01, tip + side * 0.055 + d * 0.035, tip + d * 0.09,
                 tip - side * 0.055 + d * 0.035, tip + up * 0.012, tip - up * 0.012]
        faces = [(0, 1, 2), (0, 2, 3), (1, 4, 2), (2, 4, 3), (1, 5, 2), (2, 5, 3)]
        sp = mesh_object("TailSpade", verts, faces, None, tip_material)
        rigid_skin(sp, rig, tail_bones[-1])
        parts.append(sp)
    return parts


def make_skirt(rig, top_z: float, bottom_z: float, top_r: float, bottom_r: float,
               material, name="Loincloth", segments=48, jagged=0.05) -> bpy.types.Object:
    verts, uvs, faces = [], [], []
    for i in range(segments + 1):
        u = i / segments
        a = u * TAU
        # open at the front-side gaps: keep front and back panels
        for v, (z, r) in enumerate([(top_z, top_r), (bottom_z, bottom_r)]):
            wobble = 1.0 + 0.05 * math.sin(a * 7.0)
            verts.append(Vector((math.cos(a) * r * wobble, math.sin(a) * r * wobble, z)))
            uvs.append((u, 0.0 if v == 0 else 1.0))
    for i in range(segments):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))
    # Jagged hem: lower the hem vertices in a deterministic zig-zag.
    for i in range(0, len(verts), 2):
        u = uvs[i][0]
        verts[i + 1].z -= jagged * (0.5 + 0.5 * math.sin(u * TAU * 9.0))
    obj = mesh_object(name, verts, faces, uvs, material)
    weight_by_segments(obj, rig, ["pelvis", "thigh_l", "thigh_r"], power=1.4)
    return obj


def make_mantle(rig, material, rings=3, per_ring=56, seed=7) -> list[bpy.types.Object]:
    rng = np.random.default_rng(seed)
    parts = []
    for ring_i in range(rings):
        z = 1.42 - ring_i * 0.055
        rx = 0.18 + ring_i * 0.035
        ry = 0.15 + ring_i * 0.025
        for i in range(per_ring):
            a = TAU * i / per_ring + ring_i * 0.045
            base = Vector((math.cos(a) * rx, math.sin(a) * ry + 0.01, z))
            outward = Vector((math.cos(a), math.sin(a), 0))
            down = Vector((0, 0, -1))
            length = 0.10 + 0.11 * float(rng.random()) + 0.03 * ring_i
            p1 = base + outward * length * 0.35 + down * length * 0.15
            p2 = base + outward * length * 0.62 + down * length * 0.55
            p3 = base + outward * length * 0.70 + down * length
            obj, _ = tube("FurClump", [base, p1, p2, p3],
                          [0.013, 0.010, 0.005, 0.0007], 3, material)
            weight_by_segments(obj, rig, ["spine_03", "clavicle_l", "clavicle_r"], power=1.6, max_bones=2)
            parts.append(obj)
    # A solid collar hides the clump roots.
    collar = make_skirt(rig, 1.50, 1.36, 0.19, 0.24, material, "FurCollar", 40, 0.01)
    for vg in list(collar.vertex_groups):
        collar.vertex_groups.remove(vg)
    rigid_skin(collar, rig, "spine_03")
    parts.append(collar)
    return parts


def make_hoof(rig, side: str, center: Vector, foot_bone: str, material) -> list[bpy.types.Object]:
    parts = []
    for toe in (-1, 1):
        cx = center.x + toe * 0.021
        verts = [
            Vector((cx - 0.020, center.y + 0.045, center.z + 0.035)),
            Vector((cx + 0.020, center.y + 0.045, center.z + 0.035)),
            Vector((cx + 0.017, center.y - 0.045, center.z + 0.020)),
            Vector((cx - 0.017, center.y - 0.045, center.z + 0.020)),
            Vector((cx - 0.015, center.y - 0.035, center.z - 0.040)),
            Vector((cx + 0.015, center.y - 0.035, center.z - 0.040)),
        ]
        faces = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2), (0, 4, 5, 1)]
        obj = mesh_object(f"Hoof_{side}_{'in' if toe < 0 else 'out'}", verts, faces, None, material)
        for poly in obj.data.polygons:
            poly.use_smooth = False
        rigid_skin(obj, rig, foot_bone)
        parts.append(obj)
    return parts


# ---------------------------------------------------------------------------
# Skull (goat mask)


def make_goat_skull(rig, bone_mat, dark_mat, eye_mat, horn_mat) -> list[bpy.types.Object]:
    parts = []
    # Cranium
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=18, radius=1.0)
    for v in bm.verts:
        v.co.x *= 0.082
        v.co.y *= 0.090
        v.co.z *= 0.082
        v.co += Vector((0, -0.035, 1.665))
    me = bpy.data.meshes.new("SkullCranium")
    bm.to_mesh(me)
    bm.free()
    crane = bpy.data.objects.new("SkullCranium", me)
    bpy.context.collection.objects.link(crane)
    me.materials.append(bone_mat)
    for p in me.polygons:
        p.use_smooth = True
    parts.append(crane)
    # Snout
    snout, _ = tube("SkullSnout",
                    [Vector((0, -0.075, 1.640)), Vector((0, -0.145, 1.600)),
                     Vector((0, -0.215, 1.555)), Vector((0, -0.245, 1.535))],
                    [0.055, 0.048, 0.035, 0.024], 24, bone_mat)
    parts.append(snout)
    # Cheek and brow masses
    for side in (-1, 1):
        for name, pos, scale in [
            ("Cheek", (0.070 * side, -0.105, 1.610), (0.038, 0.045, 0.028)),
            ("Brow", (0.050 * side, -0.100, 1.690), (0.042, 0.030, 0.018)),
        ]:
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
            for v in bm.verts:
                v.co.x *= scale[0]
                v.co.y *= scale[1]
                v.co.z *= scale[2]
                v.co += Vector(pos)
            me = bpy.data.meshes.new(f"Skull{name}")
            bm.to_mesh(me)
            bm.free()
            obj = bpy.data.objects.new(f"Skull{name}", me)
            bpy.context.collection.objects.link(obj)
            me.materials.append(bone_mat)
            for p in me.polygons:
                p.use_smooth = True
            parts.append(obj)
    # Dark eye sockets (slightly proud black ellipsoids) and glowing pupils.
    for side in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
        for v in bm.verts:
            v.co.x *= 0.036
            v.co.y *= 0.024
            v.co.z *= 0.040
            v.co += Vector((0.058 * side, -0.145, 1.652))
        me = bpy.data.meshes.new("SkullSocket")
        bm.to_mesh(me)
        bm.free()
        sock = bpy.data.objects.new("SkullSocket", me)
        bpy.context.collection.objects.link(sock)
        me.materials.append(dark_mat)
        parts.append(sock)
        if eye_mat is not None:
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0)
            for v in bm.verts:
                v.co *= 0.012
                v.co += Vector((0.058 * side, -0.166, 1.652))
            me = bpy.data.meshes.new("SkullEye")
            bm.to_mesh(me)
            bm.free()
            eye = bpy.data.objects.new("SkullEye", me)
            bpy.context.collection.objects.link(eye)
            me.materials.append(eye_mat)
            parts.append(eye)
    # Nasal void
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.022, radius2=0.004,
                          depth=0.055)
    me = bpy.data.meshes.new("SkullNose")
    bm.to_mesh(me)
    bm.free()
    nose = bpy.data.objects.new("SkullNose", me)
    bpy.context.collection.objects.link(nose)
    me.materials.append(dark_mat)
    nose.location = Vector((0, -0.220, 1.545))
    nose.rotation_euler = (math.radians(82), 0, 0)
    parts.append(nose)
    # Upper teeth
    for i in range(7):
        x = -0.042 + 0.014 * i
        base = Vector((x, -0.205 + abs(x) * 0.9, 1.532))
        parts.append(make_fang(rig, base, Vector((0, -0.15, -1)), 0.030, bone_mat, "Head"))
    # Lower jaw and teeth
    jaw_pts = [Vector((-0.060, -0.095, 1.540)), Vector((-0.060, -0.185, 1.510)),
               Vector((0, -0.215, 1.500)), Vector((0.060, -0.185, 1.510)),
               Vector((0.060, -0.095, 1.540))]
    jaw, _ = tube("SkullJaw", jaw_pts, [0.017, 0.016, 0.015, 0.016, 0.017], 12, bone_mat)
    rigid_skin(jaw, rig, "jaw")
    parts.append(jaw)
    for i in range(5):
        x = -0.040 + 0.020 * i
        base = Vector((x, -0.200 + abs(x) * 0.85, 1.505))
        parts.append(make_fang(rig, base, Vector((0, -0.05, 1)), 0.024, bone_mat, "jaw"))
    # Horn cores
    for side in (-1, 1):
        base = Vector((0.070 * side, -0.010, 1.700))
        parts.append(make_spike(rig, "Head", base, Vector((0.35 * side, 0.15, 0.8)), 0.050,
                                horn_mat, sides=10, radius=0.035))
    # Skull and jaw weights
    for obj in parts:
        if obj.vertex_groups.get("jaw"):
            continue
        if obj.name.startswith(("SkullEye", "SkullSocket", "SkullNose")):
            rigid_skin(obj, rig, "Head")
        elif obj.name in ("SkullCranium", "SkullSnout", "SkullCheek", "SkullBrow", "Spike", "Fang"):
            # Already weighted by their makers; raw skull pieces need Head.
            if not obj.vertex_groups:
                rigid_skin(obj, rig, "Head")
    return parts


# ---------------------------------------------------------------------------
# Transform / join / actions


def apply_orientation_and_scale(rig, mesh_obj, scale: float) -> None:
    # Rotate the assembled character 180 degrees around world Z and scale it.
    # The mesh is parented to the rig; applying both while parented would bake
    # the parent scale twice.  Clear the parent, bake each once, then re-parent.
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_obj
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for obj in (rig, mesh_obj):
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = (0.0, 0.0, math.pi)
        obj.scale = (scale, scale, scale)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    mesh_obj.parent = rig
    mesh_obj.matrix_parent_inverse = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")


def scale_action_locations(action: bpy.types.Action, scale: float) -> None:
    for fc in action_fcurves(action):
        if not fc.data_path.endswith(".location"):
            continue
        for kp in fc.keyframe_points:
            kp.co[1] *= scale
            kp.handle_left[1] *= scale
            kp.handle_right[1] *= scale
        fc.update()


def action_fcurves(action: bpy.types.Action):
    try:
        if len(action.fcurves):
            return list(action.fcurves)
    except Exception:
        pass
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                cb = strip.channelbag(slot)
                if cb:
                    out.extend(cb.fcurves)
    return out


def assign_action(rig, action) -> None:
    rig.animation_data_create()
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]


def copy_action_rename(action: bpy.types.Action, name: str) -> bpy.types.Action:
    new = action.copy()
    new.name = name
    new.use_fake_user = True
    return new


def set_pelvis_offset(rig, offset: float) -> None:
    if abs(offset) < 1e-6:
        return
    pb = rig.pose.bones.get("pelvis")
    if pb:
        m = pb.matrix.copy()
        m.translation.z += offset
        pb.matrix = m
        bpy.context.view_layer.update()


def add_constant_pelvis_offset(action: bpy.types.Action, rig, offset: float) -> None:
    """Shift the pelvis translation in armature Z by evaluating the rest frame."""
    if abs(offset) < 1e-6:
        return
    assign_action(rig, action)
    rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    pb = rig.pose.bones["pelvis"]
    before = pb.location.copy()
    set_pelvis_offset(rig, offset)
    after = pb.location.copy()
    delta = after - before
    for fc in action_fcurves(action):
        if fc.data_path == 'pose.bones["pelvis"].location':
            for kp in fc.keyframe_points:
                kp.co[1] += delta[fc.array_index]
                kp.handle_left[1] += delta[fc.array_index]
                kp.handle_right[1] += delta[fc.array_index]
            fc.update()


def add_extra_curves(action: bpy.types.Action, rig, extra_bones: list[str], phase: float = 0.0,
                     amplitude: float = 1.0, kind: str = "wing") -> None:
    """Add looped rotation curves for authored wing/tail/jaw bones to a source action."""
    if not extra_bones:
        return
    assign_action(rig, action)
    start, end = action.frame_range
    start_i, end_i = int(round(start)), int(round(end))
    if end_i <= start_i:
        return
    # Find/create the channelbag.
    slot = action.slots[0] if action.slots else None
    cb = None
    for layer in action.layers:
        for strip in layer.strips:
            if slot:
                cb = strip.channelbag(slot, ensure=True)
                if cb:
                    break
        if cb:
            break
    if cb is None:
        return
    for name in extra_bones:
        pb = rig.pose.bones.get(name)
        if pb is None:
            continue
        path = f'pose.bones["{name}"].rotation_quaternion'
        curves = [cb.fcurves.find(path, index=i) or cb.fcurves.new(path, index=i) for i in range(4)]
        for i in range(4):
            for kp in list(curves[i].keyframe_points):
                curves[i].keyframe_points.remove(kp, fast=True)
        frames = [start_i, (start_i + end_i) // 2, end_i]
        for f in frames:
            t = (f - start_i) / max(1, end_i - start_i)
            if kind == "wing":
                # wing_01/02/03: slow flap; sign by side
                side = 1.0 if name.endswith("_l") else -1.0
                idx = int(name.split("_")[1])
                angle = amplitude * side * math.radians(4.0 + 2.0 * idx) * math.sin(t * TAU + phase + idx * 0.35)
                q = Quaternion((1.0, 0.0, 0.0), angle)
            elif kind == "tail":
                idx = int(name.split("_")[1])
                angle = amplitude * math.radians(5.0 + 2.5 * idx) * math.sin(t * TAU + phase + idx * 0.6)
                q = Quaternion((0.0, 0.0, 1.0), angle)
            else:  # jaw
                angle = amplitude * math.radians(3.0) * (0.5 + 0.5 * math.sin(t * TAU + phase))
                q = Quaternion((1.0, 0.0, 0.0), angle)
            for i in range(4):
                curves[i].keyframe_points.insert(f, q[i], options={"FAST"})
        for c in curves:
            for kp in c.keyframe_points:
                kp.interpolation = "BEZIER"
            c.update()


def bake_action(rig, source_action, name: str, duration: float, warp=None,
                overlay=None, extra=None, pelvis_offset: float = 0.0,
                source_frame0: bool = False) -> bpy.types.Action:
    """Bake a source pose plus overlays into a fresh full-skeleton action."""
    fps = FPS
    frame_count = max(1, int(round(duration * fps)))
    if source_action is not None:
        assign_action(rig, source_action)
        rig.animation_data.action_slot = source_action.slots[0]
    else:
        rig.animation_data_create()
        rig.animation_data.action = None
        bpy.context.scene.frame_set(0)
    base = []
    src_start, src_end = source_action.frame_range if source_action else (0, 0)
    for f in range(frame_count + 1):
        t = f / fps
        if source_action is not None:
            st = warp(t) if warp else t
            if source_frame0:
                st = 0.0
            sf = min(src_end, max(src_start, src_start + st * fps))
            bpy.context.scene.frame_set(int(round(sf)))
            bpy.context.view_layer.update()
        else:
            bpy.context.scene.frame_set(0)
            bpy.context.view_layer.update()
        base.append({pb.name: pb.matrix_basis.copy() for pb in rig.pose.bones})
    # New action.
    rig.animation_data.action = None
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    for f, mats in enumerate(base):
        t = f / fps
        # Evaluate the new action at the frame being keyed; leaving the scene
        # at 0 lets Blender re-evaluate earlier keys while the pose is being
        # written and corrupts later frames.
        bpy.context.scene.frame_set(f)
        for pb in rig.pose.bones:
            if pb.name in mats:
                pb.matrix_basis = mats[pb.name]
        if overlay:
            overlay(rig, t, duration)
        if extra:
            extra(rig, t, duration)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
        if f % 20 == 0:
            print("BAKE", name, f, "/", frame_count)
    for fc in action_fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
        fc.update()
    return action


# ---------------------------------------------------------------------------
# Export / metadata


def clear_pose(rig) -> None:
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def setup_nla(rig, actions: list[bpy.types.Action]) -> None:
    rig.animation_data_create()
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action = None
    for action in actions:
        start = int(round(action.frame_range[0]))
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, start, action)
        strip.name = action.name
        track.mute = True


def export_glb(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.file.pack_all()
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_apply=False,
        export_anim_single_armature=True,
        export_optimize_animation_size=False,
    )


def glb_document(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    json_len = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_len])
    return doc, raw


def mesh_bounds(doc: dict):
    lo = np.array([1e9, 1e9, 1e9])
    hi = np.array([-1e9, -1e9, -1e9])
    tris = 0
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            lo = np.minimum(lo, np.array(acc["min"]))
            hi = np.maximum(hi, np.array(acc["max"]))
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
            else:
                tris += acc["count"] // 3
    return lo, hi, tris


def write_metadata(output: Path, mob: str, display: str, clips: dict,
                   head_radius: float, head_half: float, notes: list[str],
                   source: str = "CC0 Quaternius base/outfit/hair + original modifications") -> dict:
    doc, _raw = glb_document(output)
    lo, hi, tris = mesh_bounds(doc)
    skeleton = next((n for n in doc["nodes"] if n.get("name") == "Armature" or n.get("name", "").startswith("Armature")), None)
    skin = doc["skins"][0]
    bone_names = [doc["nodes"][i].get("name") for i in skin["joints"]]
    mats = [m.get("name") for m in doc.get("materials", [])]
    images = doc.get("images", [])
    clip_meta = {}
    for key, info in clips.items():
        clip_meta[key] = {
            "name": info["name"],
            "duration": round(float(info["duration"]), 6),
            "impact": info.get("impact"),
            "loop": key in ("idle", "walk", "run"),
        }
    meta = {
        "asset": output.name,
        "mob": mob,
        "display_name": display,
        "skeleton": "Armature/Skeleton3D",
        "bone_count": len(bone_names),
        "bone_names": bone_names,
        "forward": [0, 0, -1],
        "up": [0, 1, 0],
        "unit": "metres",
        "rest_bounds_min": [round(float(v), 6) for v in lo],
        "rest_bounds_max": [round(float(v), 6) for v in hi],
        "height": round(float(hi[1] - lo[1]), 6),
        "mesh_triangles": int(tris),
        "materials": mats,
        "embedded_images": len(images),
        "texture_sets": "source PBR skin/leather/hair + authored horn/bone/membrane/stone/fur/cloth",
        "clips": clip_meta,
        "head_zone": {"bone": "head", "radius": round(head_radius, 4),
                      "half_height": round(head_half, 4)},
        "authoring_fps": FPS,
        "source": source,
        "surface_notes": notes,
    }
    output.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print("META", mob, "bones", len(bone_names), "tris", tris,
          "height", meta["height"], "materials", len(mats), "images", len(images))
    return meta
