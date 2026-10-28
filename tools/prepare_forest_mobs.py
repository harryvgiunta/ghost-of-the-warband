"""Author the Unholy Forest mobset and export skinned, animated GLBs.

Three original creatures, in the same deterministic Blender route as
``tools/prepare_wolf.py``:

``hollow_warden``   hooded antlered grave-cloth, ember stare, clawed hands.
``ossuary_stalker`` gaunt hide-wrapped humanoid, skull under a low antler crown,
                    bone ribs plated over leather, hook fingers, hide loincloth.
``gallowsroot``     a tall wooden man: bark body with hard bark plates, a knotty
                    head split into a burning face fissure, branch-antler crown.

Every material's atlas is rasterised from ``tools/forest_surface.py``: the
finished mesh is unwrapped per material, then each texel is resolved back to
its rest-space position and sampled, so bark fissures, cloth weave, bone pores
and antler rings are continuous across UV seams and carry texel-scale detail.
"""

from __future__ import annotations

import json
import math
import random
import struct
import sys
from pathlib import Path

import numpy as np
import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import forest_styles as styles  # noqa: E402
import forest_surface as surfaces  # noqa: E402

ROOT = styles.ROOT
FPS = styles.FPS
SEED = styles.SEED

RIG: bpy.types.Object | None = None
MESH: bpy.types.Object | None = None
JOINTS: dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]] = {}
PARENTS: dict[str, tuple[str | None, bool]] = {}
DEFORM: list[str] = []


# ---------------------------------------------------------------------------
# Small deterministic helpers


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


def rng_for(mob: str, salt: str) -> random.Random:
    return random.Random((SEED + len(mob) * 7919 + sum(ord(c) * 31 for c in salt)) & 0x7FFFFFFF)


def hash01(value: float, salt: float = 0.0) -> float:
    x = math.sin(value * 127.1 + salt * 311.7) * 43758.5453
    return x - math.floor(x)


def lerp_vector(a: Vector, b: Vector, t: float) -> Vector:
    return a + (b - a) * t


# ---------------------------------------------------------------------------
# Scene and object plumbing


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start = 0
    scene.frame_end = 1


def set_active(obj: bpy.types.Object) -> None:
    for other in bpy.context.selected_objects:
        other.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def link_mesh(name: str, verts, faces, material: bpy.types.Material | None = None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.validate(verbose=False)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # Hand-built shells are closed or nearly closed: let Blender settle the
    # winding once so no hand-authored garment renders inside-out.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    if material is not None:
        mesh.materials.append(material)
    return obj


# ---------------------------------------------------------------------------
# Primitives


def metaball_ellipsoid(mb, centre, half, rotation=None, stiffness=2.0):
    # Measured on the installed build: a single ELLIPSOID at this radius puts
    # its stiffness surface close to the requested half extent.
    e = mb.elements.new(type="ELLIPSOID")
    e.co = Vector(centre)
    e.radius = 1.0 / 0.5735
    e.size_x, e.size_y, e.size_z = half
    e.stiffness = stiffness
    if rotation is not None:
        e.rotation = rotation
    return e


def metaball_capsule(mb, a, b, radius, bulge=1.0, stiffness=2.0):
    a, b = Vector(a), Vector(b)
    direction = b - a
    length = direction.length
    if length <= 1e-6:
        return metaball_ellipsoid(mb, a, (radius, radius, radius), stiffness=stiffness)
    rotation = Vector((0.0, 1.0, 0.0)).rotation_difference(direction.normalized())
    return metaball_ellipsoid(
        mb,
        (a + b) * 0.5,
        (radius, length * 0.5 + radius * 0.30, radius * bulge),
        rotation,
        stiffness,
    )


def metaball_mesh(name: str, elements, resolution: float, threshold: float,
                  decimate: float, material: bpy.types.Material):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = threshold
    obj = bpy.data.objects.new(name, mb)
    bpy.context.collection.objects.link(obj)
    elements(mb)
    set_active(obj)
    bpy.ops.object.convert(target="MESH")
    body = bpy.context.object
    body.name = name
    body.data.name = name
    bpy.ops.object.shade_smooth()
    if decimate < 0.999:
        modifier = body.modifiers.new("Decimate", "DECIMATE")
        modifier.ratio = decimate
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    body.data.materials.clear()
    body.data.materials.append(material)
    return body


def frame_vectors(tangent: Vector) -> tuple[Vector, Vector]:
    """Stable ring basis for a tube along ``tangent``."""
    axis = Vector((0.0, 0.0, 1.0))
    if abs(tangent.dot(axis)) > 0.92:
        axis = Vector((1.0, 0.0, 0.0))
    if abs(tangent.dot(axis)) > 0.92:
        axis = Vector((0.0, 1.0, 0.0))
    side = tangent.cross(axis).normalized()
    other = tangent.cross(side).normalized()
    return side, other


def tube_vertices(path: list[Vector], radii: list[float], sides: int,
                  wobble: float, salt: float) -> tuple[list[Vector], list[list[int]]]:
    """Rings along a polyline; returns world verts and ring index lists."""
    verts: list[Vector] = []
    rings: list[list[int]] = []
    for index, point in enumerate(path):
        if index == 0:
            tangent = (path[1] - point)
        elif index == len(path) - 1:
            tangent = (point - path[index - 1])
        else:
            tangent = (path[index + 1] - path[index - 1])
        tangent.normalize()
        side, other = frame_vectors(tangent)
        ring: list[int] = []
        for step in range(sides):
            angle = (step / sides) * math.tau
            # A little radial wobble breaks the machined cylinder feel.
            radial = 1.0 + wobble * (hash01(angle * 3.1 + index * 2.7 + salt) - 0.5) * 2.0
            offset = (side * math.cos(angle) + other * math.sin(angle)) * (radii[index] * radial)
            ring.append(len(verts))
            verts.append(point + offset)
        rings.append(ring)
    return verts, rings


def ring_triangles(rings: list[list[int]], start: int = 0) -> list[tuple[int, ...]]:
    faces: list[tuple[int, ...]] = []
    sides = len(rings[0])
    for index in range(start, len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((lower[step], lower[nxt], upper[nxt], upper[step]))
    return faces


def open_tube(name: str, path: list[Vector], radii: list[float], sides: int,
              material, wobble: float = 0.12, salt: float = 0.0, fringe: float = 0.0,
              thickness: float = 0.014):
    """An open-ended tube: a sleeve or a hanging cloth limb with a ragged cuff.

    ``fringe`` drops a fraction of the faces in the last band so the opening
    frays instead of ending in a machined ring.
    """
    verts, rings = tube_vertices(path, radii, sides, wobble, salt)
    faces: list[tuple[int, ...]] = []
    for index, face in enumerate(ring_triangles(rings)):
        if fringe > 0.0 and index >= (len(rings) - 2) * sides:
            step = index % sides
            if hash01(step * 2.3 + salt) < fringe:
                continue
        faces.append(face)
    tube = link_mesh(name, verts, faces, material)
    solidify(tube, thickness)
    return tube


def flat_shade(obj) -> None:
    """Hard edges: hand-cut plates and masks must not read as moulded plastic."""
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    obj.data.update()


def crumple(obj, amplitude: float, frequency: float, salt: float = 0.0) -> None:
    """Crush a garment along its normals with layered 3D noise.

    A smooth lathe reads as a vase. Three incommensurate waves at 20-40 cm
    scale give the creased, dragged look of cloth that has been worn, slept in
    and never washed.
    """
    mesh = obj.data
    normals = [vertex.normal.copy() for vertex in mesh.vertices]
    for vertex, normal in zip(mesh.vertices, normals):
        point = vertex.co
        qx, qy, qz = point.x * frequency, point.y * frequency, point.z * frequency
        wave = (math.sin(qx * 1.7 + qy * 2.3 + qz * 1.1 + salt)
                + 0.55 * math.sin(qx * 3.1 - qy * 1.9 + qz * 2.7 + salt * 1.3)
                + 0.28 * math.sin(qx * 5.3 + qy * 4.7 - qz * 3.9 + salt * 0.7))
        vertex.co = point + normal * (amplitude * wave / 1.83)
    mesh.update()


def bark_slab(name: str, centre: Vector, aim: Vector, length: float, width: float,
              thickness: float, material, salt: float = 0.0):
    """A chunky angular plate: broken bark, not a soft blob.

    Built as a jittered wedge in a local frame whose +Z is ``aim``, so plates
    can be hung off shoulders and shins without sculpting each one.
    """
    direction = aim.normalized()
    rotation = Vector((0.0, 0.0, 1.0)).rotation_difference(direction)
    half_w = width * 0.5
    half_t = thickness * 0.5
    local = [
        Vector((-half_w, -half_t, 0.0)), Vector((half_w, -half_t, 0.0)),
        Vector((half_w, half_t, 0.0)), Vector((-half_w, half_t, 0.0)),
        Vector((-half_w * 0.55, -half_t * 0.6, length)),
        Vector((half_w * 0.55, -half_t * 0.6, length)),
        Vector((half_w * 0.55, half_t * 0.6, length)),
        Vector((-half_w * 0.55, half_t * 0.6, length)),
    ]
    verts = []
    for index, point in enumerate(local):
        jitter = 1.0 + (hash01(index * 3.7 + salt) - 0.5) * 0.22
        verts.append(centre + rotation @ (point * jitter))
    faces = [
        (0, 1, 2, 3), (7, 6, 5, 4),
        (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0),
    ]
    return link_mesh(name, verts, faces, material)


def tapered_tube(name: str, path: list[Vector], radii: list[float], sides: int,
                 material: bpy.types.Material, wobble: float = 0.12, salt: float = 0.0):
    verts, rings = tube_vertices(path, radii, sides, wobble, salt)
    faces = ring_triangles(rings)
    # Close the ends with a fan around a centre vertex so claws look solid.
    # The start cap faces backwards along the path, the end cap forwards.
    for ring, point, start in ((rings[0], path[0], True), (rings[-1], path[-1], False)):
        centre = len(verts)
        verts.append(point)
        for step in range(sides):
            nxt = (step + 1) % sides
            if start:
                faces.append((centre, ring[step], ring[nxt]))
            else:
                faces.append((centre, ring[nxt], ring[step]))
    return link_mesh(name, verts, faces, material)


def merge_tubes(name: str, branches: list[tuple[list[Vector], list[float]]], sides: int,
                material: bpy.types.Material, wobble: float = 0.12, salt: float = 0.0):
    verts: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    for path, radii in branches:
        local_verts, rings = tube_vertices(path, radii, sides, wobble, salt)
        offset = len(verts)
        verts.extend(local_verts)
        local_faces = ring_triangles(rings)
        for ring, point, start in ((rings[0], path[0], True), (rings[-1], path[-1], False)):
            centre = len(verts)
            verts.append(point)
            for step in range(sides):
                nxt = (step + 1) % sides
                if start:
                    local_faces.append((centre, ring[step], ring[nxt]))
                else:
                    local_faces.append((centre, ring[nxt], ring[step]))
        faces.extend(tuple(index + offset for index in face) for face in local_faces)
    return link_mesh(name, verts, faces, material)


def lathe(name: str, rows: list[list[Vector]], material: bpy.types.Material,
          tears: dict[int, float] | None = None):
    """Close a ring grid into a tube-shell surface."""
    verts: list[Vector] = []
    rings: list[list[int]] = []
    for row in rows:
        ring = []
        for point in row:
            ring.append(len(verts))
            verts.append(point)
        rings.append(ring)
    faces: list[tuple[int, ...]] = []
    sides = len(rows[0])
    for index in range(len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        for step in range(sides):
            nxt = (step + 1) % sides
            if tears is not None and index + 1 >= len(rings) - 2:
                # Only single-quad notches: wide runs of removed quads read as
                # machined slots instead of a frayed edge.
                if hash01(float(step) * 1.7 + float(index) * 3.9) < tears.get(index + 1, 0.0):
                    continue
            faces.append((lower[step], lower[nxt], upper[nxt], upper[step]))
    # Cap the top row so the shell is watertight from above.
    top = rings[0]
    centre = len(verts)
    verts.append(sum((verts[index] for index in top), Vector()) / len(top))
    for step in range(sides):
        faces.append((centre, top[(step + 1) % sides], top[step]))
    return link_mesh(name, verts, faces, material)


def solidify(obj, thickness: float) -> None:
    set_active(obj)
    modifier = obj.modifiers.new("Solidify", "SOLIDIFY")
    modifier.thickness = thickness
    modifier.offset = 0.0
    modifier.use_rim = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def displace_radial(obj, axis_index: int, amplitude: float, frequency: float,
                    ridge: float = 0.5, phase: float = 0.0) -> None:
    """Push vertices along their normals with vertical furrows around Z.

    Used for bark and cloth folds: cheap, deterministic, and it survives into
    the silhouette instead of living only in a normal map.
    """
    mesh = obj.data
    normals = [vertex.normal.copy() for vertex in mesh.vertices]
    for vertex, normal in zip(mesh.vertices, normals):
        point = vertex.co
        if axis_index == 2:
            angle = math.atan2(point.y, point.x)
            along = point.z
        else:
            angle = math.atan2(point.z, point.x)
            along = point.y
        wave = math.sin(angle * frequency + math.sin(along * 1.9 + phase) * ridge)
        fine = math.sin(angle * frequency * 2.7 + along * 11.0 + phase) * 0.35
        vertex.co = point + normal * ((wave + fine) * amplitude)
    mesh.update()


# ---------------------------------------------------------------------------
# Rigs, weights, joins


def build_armature() -> bpy.types.Object:
    armature = bpy.data.armatures.new("ForestArmature")
    rig = bpy.data.objects.new("ForestArmature", armature)
    bpy.context.collection.objects.link(rig)
    set_active(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = armature.edit_bones
    for name in ["root", *DEFORM]:
        bone = edit_bones.new(name)
        if name == "root":
            bone.head = (0.0, 0.0, 0.0)
            bone.tail = (0.0, 0.0, 0.16)
            bone.use_deform = False
        else:
            head, tail = JOINTS[name]
            bone.head = head
            bone.tail = tail
            parent, connect = PARENTS[name]
            if parent:
                bone.parent = edit_bones[parent]
                bone.use_connect = connect
            bone.use_deform = True
        bone.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.display_type = "STICK"
    return rig


def bone_segments() -> dict[str, tuple[Vector, Vector]]:
    return {
        name: (Vector(JOINTS[name][0]), Vector(JOINTS[name][1]))
        for name in DEFORM
    }


def point_segment_distance(point: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    denom = ab.length_squared
    if denom <= 1e-12:
        return (point - a).length
    t = max(0.0, min(1.0, (point - a).dot(ab) / denom))
    return (point - (a + ab * t)).length


def assign_envelope_weights(obj, skin: dict[str, tuple[float, float]], smooth_iterations: int = 2) -> None:
    """Distance-weighted skinning restricted to the bones a part belongs to.

    Restricting the candidate set per part is what keeps a swinging sleeve from
    dragging the robe behind it; the wolf's global pass works for one coat, not
    for a layered robed figure.
    """
    segments = bone_segments()
    groups = {name: obj.vertex_groups.new(name=name) for name in skin}
    raw: list[dict[str, float]] = []
    for vertex in obj.data.vertices:
        point = vertex.co
        candidate: dict[str, float] = {}
        for name, (radius, priority) in skin.items():
            a, b = segments[name]
            distance = point_segment_distance(point, a, b)
            if distance < radius:
                falloff = (1.0 - (distance / radius) ** 2) ** 2
                if falloff > 0.0005:
                    candidate[name] = falloff * priority
        if not candidate:
            nearest = min(skin, key=lambda n: point_segment_distance(point, *segments[n]))
            candidate[nearest] = 1.0
        raw.append(candidate)
    adjacency: list[set[int]] = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    for _ in range(smooth_iterations):
        smoothed: list[dict[str, float]] = []
        for index, weights in enumerate(raw):
            merged = {name: value * 0.55 for name, value in weights.items()}
            neighbours = adjacency[index]
            if neighbours:
                scale = 0.45 / len(neighbours)
                for neighbour in neighbours:
                    for name, value in raw[neighbour].items():
                        merged[name] = merged.get(name, 0.0) + value * scale
            smoothed.append(merged)
        raw = smoothed
    for index, weights in enumerate(raw):
        ordered = sorted(weights.items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(value for _, value in ordered)
        if total <= 1e-9:
            fallback = next(iter(skin))
            ordered = [(fallback, 1.0)]
            total = 1.0
        for name, value in ordered:
            groups[name].add([index], value / total, "REPLACE")


def rigid_weight(obj, bone: str) -> None:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def blend_weight(obj, bone_a: str, bone_b: str, split) -> None:
    """Weight by ``split(point) -> 0..1`` toward ``bone_b``."""
    group_a = obj.vertex_groups.new(name=bone_a)
    group_b = obj.vertex_groups.new(name=bone_b)
    for vertex in obj.data.vertices:
        t = max(0.0, min(1.0, float(split(vertex.co))))
        group_a.add([vertex.index], 1.0 - t, "REPLACE")
        group_b.add([vertex.index], t, "REPLACE")


def join_parts(target, parts: list, name: str):
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = name
    mesh.data.name = name
    bpy.ops.object.shade_smooth()
    return mesh


def skin_to_rig(mesh_obj, rig) -> None:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    set_active(mesh_obj)
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    mesh_obj.parent = rig
    mesh_obj.matrix_parent_inverse = Matrix.Identity(4)


# ---------------------------------------------------------------------------
# PBR atlas bake


def unwrap_per_material(mesh_obj) -> None:
    """Pack each material's islands into its own 0..1 atlas.

    Materials own separate images, so overlapping islands across materials is
    correct and gives every surface full texel density.
    """
    set_active(mesh_obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.object.mode_set(mode="OBJECT")
    if not mesh_obj.data.uv_layers:
        mesh_obj.data.uv_layers.new(name="UVMap")
    mesh_obj.data.uv_layers[0].name = "UVMap"
    slots = len(mesh_obj.data.materials)
    for slot in range(slots):
        bpy.ops.object.mode_set(mode="EDIT")
        bm = bmesh.from_edit_mesh(mesh_obj.data)
        for face in bm.faces:
            face.select = face.material_index == slot
        bmesh.update_edit_mesh(mesh_obj.data)
        bpy.ops.uv.smart_project(angle_limit=math.radians(62.0), island_margin=0.012)
        bpy.ops.uv.pack_islands(margin=0.006)
        bpy.ops.object.mode_set(mode="OBJECT")


def triangle_texels(mesh_obj, slot: int, size: int):
    """Return per-triangle (flat pixel indices, rest-space points) for a slot."""
    mesh = mesh_obj.data
    uv_data = mesh.uv_layers[0].data
    positions = [vertex.co for vertex in mesh.vertices]
    uv = [(entry.uv[0], entry.uv[1]) for entry in uv_data]
    chunks: list[tuple[np.ndarray, np.ndarray]] = []
    for polygon in mesh.polygons:
        if polygon.material_index != slot:
            continue
        loops = list(polygon.loop_indices)
        for corner in range(1, len(loops) - 1):
            li0, li1, li2 = loops[0], loops[corner], loops[corner + 1]
            vi0 = mesh.loops[li0].vertex_index
            vi1 = mesh.loops[li1].vertex_index
            vi2 = mesh.loops[li2].vertex_index
            u0, v0 = uv[li0]
            u1, v1 = uv[li1]
            u2, v2 = uv[li2]
            xmin = max(0, int(math.floor(min(u0, u1, u2) * size)) - 1)
            xmax = min(size - 1, int(math.ceil(max(u0, u1, u2) * size)) + 1)
            ymin = max(0, int(math.floor(min(v0, v1, v2) * size)) - 1)
            ymax = min(size - 1, int(math.ceil(max(v0, v1, v2) * size)) + 1)
            if xmax < xmin or ymax < ymin:
                continue
            xs = (np.arange(xmin, xmax + 1, dtype=np.float64) + 0.5) / size
            ys = (np.arange(ymin, ymax + 1, dtype=np.float64) + 0.5) / size
            px, py = np.meshgrid(xs, ys)
            denominator = (v1 - v2) * (u0 - u2) + (u2 - u1) * (v0 - v2)
            if abs(denominator) < 1e-12:
                continue
            wa = ((v1 - v2) * (px - u2) + (u2 - u1) * (py - v2)) / denominator
            wb = ((v2 - v0) * (px - u2) + (u0 - u2) * (py - v2)) / denominator
            wc = 1.0 - wa - wb
            inside = (wa >= -1e-7) & (wb >= -1e-7) & (wc >= -1e-7)
            if not np.any(inside):
                continue
            iy, ix = np.nonzero(inside)
            wa = wa[iy, ix]
            wb = wb[iy, ix]
            wc = wc[iy, ix]
            p0, p1, p2 = positions[vi0], positions[vi1], positions[vi2]
            points = np.empty((iy.size, 3), dtype=np.float32)
            points[:, 0] = wa * p0.x + wb * p1.x + wc * p2.x
            points[:, 1] = wa * p0.y + wb * p1.y + wc * p2.y
            points[:, 2] = wa * p0.z + wb * p1.z + wc * p2.z
            flat = ((iy + ymin) * size + (ix + xmin)).astype(np.int64)
            chunks.append((flat, points))
    return chunks


def dilate(image: np.ndarray, coverage: np.ndarray, iterations: int = 12) -> np.ndarray:
    height, width = coverage.shape
    for _ in range(iterations):
        neighbour_sum = np.zeros_like(image)
        neighbour_count = np.zeros_like(coverage, dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            shifted_image = np.zeros_like(image)
            shifted_coverage = np.zeros_like(coverage)
            ys0, ys1 = max(0, dy), height + min(0, dy)
            yd0, yd1 = max(0, -dy), height + min(0, -dy)
            xs0, xs1 = max(0, dx), width + min(0, dx)
            xd0, xd1 = max(0, -dx), width + min(0, -dx)
            shifted_image[yd0:yd1, xd0:xd1] = image[ys0:ys1, xs0:xs1]
            shifted_coverage[yd0:yd1, xd0:xd1] = coverage[ys0:ys1, xs0:xs1]
            neighbour_sum += shifted_image * shifted_coverage[..., None]
            neighbour_count += shifted_coverage
        fill = (~coverage) & (neighbour_count > 0.0)
        image[fill] = neighbour_sum[fill] / neighbour_count[fill][:, None]
        coverage[fill] = True
    return image


def new_image(name: str, size: int, pixels: np.ndarray, non_color: bool, save_to: Path) -> bpy.types.Image:
    rgba = np.ones((size, size, 4), dtype=np.float32)
    if pixels.ndim == 2:
        rgba[..., 0] = pixels
        rgba[..., 1] = pixels
        rgba[..., 2] = pixels
    else:
        rgba[..., :3] = pixels
    image = bpy.data.images.new(name, size, size, alpha=False)
    image.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    image.file_format = "PNG"
    image.pixels.foreach_set(rgba.ravel())
    image.update()
    image.pack()
    image.filepath_raw = str(save_to / f"{name}.png")
    try:
        image.save()
    except Exception as exc:  # noqa: BLE001 - evidence only; the packed copy is what ships
        print("FOREST_TEXTURE_SAVE_SKIPPED", name, exc)
    return image


def bake_material(mesh_obj, slot: int, surface: str, mob: str, save_to: Path) -> bpy.types.Material:
    spec = styles.SURFACES[surface]
    size = int(spec["size"])
    chunks = triangle_texels(mesh_obj, slot, size)
    albedo = np.zeros((size * size, 3), dtype=np.float32)
    height = np.zeros(size * size, dtype=np.float32)
    roughness = np.zeros(size * size, dtype=np.float32)
    emission = np.zeros((size * size, 3), dtype=np.float32)
    covered = np.zeros(size * size, dtype=bool)
    if not chunks:
        print("FOREST_SLOT_EMPTY", surface)
    else:
        flat = np.concatenate([chunk[0] for chunk in chunks])
        points = np.concatenate([chunk[1] for chunk in chunks])
        zmin = float(points[:, 2].min())
        zmax = float(points[:, 2].max())
        palette = styles.palette(mob, surface)
        sampled = surfaces.sample(surface, points, palette, SEED, (2, zmin, zmax))
        albedo[flat] = np.clip(sampled["albedo"], 0.0, 1.0)
        height[flat] = np.clip(sampled["height"], 0.0, 1.0)
        roughness[flat] = np.clip(sampled["roughness"], *spec["rough"])
        if sampled.get("emission") is not None:
            emission[flat] = np.clip(sampled["emission"], 0.0, 1.0)
        covered[flat] = True
    albedo = albedo.reshape(size, size, 3)
    height = height.reshape(size, size)
    roughness = roughness.reshape(size, size)
    emission = emission.reshape(size, size, 3)
    coverage = covered.reshape(size, size)
    albedo = dilate(albedo, coverage.copy(), 12)
    height = dilate(height[..., None], coverage.copy(), 12)[..., 0]
    roughness = dilate(roughness[..., None], coverage.copy(), 12)[..., 0]
    emissive_any = float(np.max(emission)) > 0.004
    if emissive_any:
        emission = dilate(emission, coverage.copy(), 12)
    normals = surfaces.normal_map(height, float(spec["normal"]))
    prefix = f"{styles.material_name(surface)}_{mob}"
    albedo_image = new_image(prefix + "_albedo", size, albedo, False, save_to)
    normal_image = new_image(prefix + "_normal", size, np.clip(normals, 0.0, 1.0), True, save_to)
    rough_image = new_image(prefix + "_roughness", size, roughness, True, save_to)
    emissive_image = (
        new_image(prefix + "_emissive", size, emission, False, save_to) if emissive_any else None
    )
    material = bpy.data.materials.get(styles.material_name(surface))
    if material is None:
        material = bpy.data.materials.new(styles.material_name(surface))
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        if node.type != "OUTPUT_MATERIAL":
            nodes.remove(node)
    output = nodes.get("Material Output") or nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-260, 0)
    bsdf.inputs["Base Color"].default_value = (0.6, 0.6, 0.6, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Specular IOR Level"].default_value = 0.32
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    color_map = nodes.new("ShaderNodeTexImage")
    color_map.image = albedo_image
    color_map.location = (-900, 220)
    links.new(color_map.outputs["Color"], bsdf.inputs["Base Color"])
    normal_map = nodes.new("ShaderNodeTexImage")
    normal_map.image = normal_image
    normal_map.location = (-900, -220)
    normal_map.image.colorspace_settings.name = "Non-Color"
    normal_node = nodes.new("ShaderNodeNormalMap")
    normal_node.location = (-620, -220)
    normal_node.inputs["Strength"].default_value = 1.0
    links.new(normal_map.outputs["Color"], normal_node.inputs["Color"])
    links.new(normal_node.outputs["Normal"], bsdf.inputs["Normal"])
    rough_map = nodes.new("ShaderNodeTexImage")
    rough_map.image = rough_image
    rough_map.location = (-900, -520)
    rough_map.image.colorspace_settings.name = "Non-Color"
    links.new(rough_map.outputs["Color"], bsdf.inputs["Roughness"])
    if emissive_image is not None:
        emissive_map = nodes.new("ShaderNodeTexImage")
        emissive_map.image = emissive_image
        emissive_map.location = (-900, -20)
        links.new(emissive_map.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        material.blend_method = "OPAQUE"
    print(
        "FOREST_BAKE",
        mob,
        surface,
        "texels",
        int(flat.size) if chunks else 0,
        "covered",
        int(np.count_nonzero(coverage)),
        "size",
        size,
    )
    return material


def bake_materials(mesh_obj, mob: str, save_to: Path) -> None:
    save_to.mkdir(parents=True, exist_ok=True)
    for slot, material in enumerate(list(mesh_obj.data.materials)):
        surface = str(material.name).replace(styles.MATERIAL_PREFIX, "").lower()
        baked = bake_material(mesh_obj, slot, surface, mob, save_to)
        mesh_obj.data.materials[slot] = baked


def material(surface: str) -> bpy.types.Material:
    name = styles.material_name(surface)
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    created = bpy.data.materials.new(name)
    created.use_nodes = True
    return created


# ---------------------------------------------------------------------------
# Pose plumbing


def set_world_rotation(pb, quaternion: Quaternion) -> None:
    rest = pb.bone.matrix_local.to_quaternion()
    pb.rotation_quaternion = rest.inverted() @ quaternion @ rest


def set_axis_rotation(pb, angle: float, axis: Vector = Vector((1.0, 0.0, 0.0))) -> None:
    rest = pb.bone.matrix_local.to_quaternion()
    local_axis = rest.inverted() @ axis
    pb.rotation_quaternion = Quaternion(local_axis.normalized(), angle)


def world_quaternion(pitch: float, yaw: float, roll: float) -> Quaternion:
    return (
        Quaternion((0.0, 0.0, 1.0), yaw)
        @ Quaternion((0.0, 1.0, 0.0), roll)
        @ Quaternion((1.0, 0.0, 0.0), pitch)
    )


def chain_bone(rig, name: str, pitch: float, yaw: float, roll: float, accum: Quaternion) -> Quaternion:
    """Apply a world-space delta to a bone relative to the accumulated parent."""
    desired = world_quaternion(pitch, yaw, roll)
    set_world_rotation(rig.pose.bones[name], accum.inverted() @ desired)
    return desired


def reset_pose(rig) -> None:
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def set_pelvis_offset(rig, offset: Vector) -> None:
    pb = rig.pose.bones["pelvis"]
    rest = pb.bone.matrix_local.to_quaternion()
    pb.location = rest.inverted() @ offset


def rest_angle(name: str) -> float:
    head, tail = JOINTS[name]
    return math.atan2(tail[1] - head[1], head[2] - tail[2])


def segment_length(name: str) -> float:
    head, tail = JOINTS[name]
    return math.sqrt(sum((tail[axis] - head[axis]) ** 2 for axis in range(3)))


def solve_leg(rig, side: str, ankle: Vector, foot_pitch: float, toe_flex: float,
              parent_pitch: float) -> None:
    """Two-bone IK in the sagittal plane, knee forward, sole kept flat."""
    thigh_name = f"thigh_{side}"
    shin_name = f"shin_{side}"
    foot_name = f"foot_{side}"
    toe_name = f"toe_{side}"
    thigh_pb = rig.pose.bones[thigh_name]
    shin_pb = rig.pose.bones[shin_name]
    foot_pb = rig.pose.bones[foot_name]
    toe_pb = rig.pose.bones[toe_name]
    a = thigh_pb.matrix.translation.copy()
    d = Vector((0.0, ankle.y - a.y, ankle.z - a.z))
    l1 = segment_length(thigh_name)
    l2 = segment_length(shin_name)
    distance = max(0.001, min(d.length, l1 + l2 - 0.002))
    u = d.normalized() if d.length > 1e-6 else Vector((0.0, 0.0, -1.0))
    along = (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
    height = math.sqrt(max(0.0, l1 * l1 - along * along))
    # Knee pole: +Y (forward).
    normal = Vector((0.0, u.z, -u.y)) * -1.0
    knee = a + u * along + normal * height
    phi1 = math.atan2(knee.y - a.y, a.z - knee.z)
    phi2 = math.atan2(ankle.y - knee.y, knee.z - ankle.z)
    rest1 = rest_angle(thigh_name)
    rest2 = rest_angle(shin_name)
    rest3 = rest_angle(foot_name)
    rest4 = rest_angle(toe_name)
    phi3 = rest3 + foot_pitch
    phi4 = rest4 + toe_flex
    set_axis_rotation(thigh_pb, (phi1 - rest1) - parent_pitch)
    set_axis_rotation(shin_pb, (phi2 - rest2) - (phi1 - rest1))
    set_axis_rotation(foot_pb, (phi3 - rest3) - (phi2 - rest2))
    set_axis_rotation(toe_pb, (phi4 - rest4) - (phi3 - rest3))


def foot_target(phase: float, offset: float, duty: float, stride: float, clearance: float
                ) -> tuple[float, float, float]:
    """Return (y offset, lift, foot pitch) for one foot at a cycle phase."""
    q = (phase - offset) % 1.0
    half = stride * duty * 0.5
    if q < duty:
        t = q / duty
        return half - 2.0 * half * t, 0.0, 0.0
    t = (q - duty) / (1.0 - duty)
    ease = smoothstep(0.0, 1.0, t)
    lift = clearance * math.sin(math.pi * t) ** 1.15
    return -half + 2.0 * half * ease, lift, -0.25 * math.sin(math.pi * t)


# ---------------------------------------------------------------------------
# Cloth and bark construction helpers


def lathe(name: str, rows: list[list[Vector]], material: bpy.types.Material,
          tears: dict[int, float] | None = None):
    """Close a ring grid into a tube-shell surface, normals facing outward."""
    verts: list[Vector] = []
    rings: list[list[int]] = []
    for row in rows:
        ring = []
        for point in row:
            ring.append(len(verts))
            verts.append(point)
        rings.append(ring)
    faces: list[tuple[int, ...]] = []
    sides = len(rows[0])
    for index in range(len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        for step in range(sides):
            nxt = (step + 1) % sides
            if tears is not None and index + 1 >= len(rings) - 2:
                # Only single-quad notches: wide runs of removed quads read as
                # machined slots instead of a frayed edge.
                if hash01(float(step) * 1.7 + float(index) * 3.9) < tears.get(index + 1, 0.0):
                    continue
            faces.append((lower[step], upper[step], upper[nxt], lower[nxt]))
    # Cap the top row so the shell is watertight from above.
    top = rings[0]
    centre = len(verts)
    verts.append(sum((verts[index] for index in top), Vector()) / len(top))
    for step in range(sides):
        faces.append((centre, top[step], top[(step + 1) % sides]))
    return link_mesh(name, verts, faces, material)


def lathe_from_profile(name: str, profile: list[tuple[float, float]], sides: int,
                       material, fold_count: int, fold_amp: float, hem_jag: float,
                       salt: float, centre: Vector | None = None, tear: float = 0.0,
                       squash: float = 1.0, lean: float = 0.0):
    """A hanging garment or trunk shell.

    ``profile`` is a list of (height fraction, radius) from top to hem. Folds
    grow toward the hem, the hem itself is jagged, and narrow tears remove
    faces near the bottom so the silhouette frays instead of ending in a clean
    circle.
    """
    centre = centre or Vector((0.0, 0.0, 0.0))
    top_z, bottom_z = profile[0][0], profile[-1][0]
    rows: list[list[Vector]] = []
    for index, (z, radius) in enumerate(profile):
        t = index / (len(profile) - 1)
        row: list[Vector] = []
        for step in range(sides):
            angle = (step / sides) * math.tau
            wobble = hash01(step * 1.31 + index * 0.77 + salt)
            wave = math.sin(angle * fold_count + math.sin(angle * 3.0) * 0.6)
            # Sharpened wave: narrow valleys and crests read as pressed cloth,
            # a plain sine reads as a scalloped vase.
            fold = math.copysign(abs(wave) ** 0.62, wave) * fold_amp * t
            radius_here = radius * (1.0 + fold) + (wobble - 0.5) * 0.012 * t
            z_here = z
            if t > 0.82:
                drop = smoothstep(0.82, 1.0, t)
                z_here -= (wobble * hem_jag + hash01(step * 3.7 + salt) * hem_jag * 0.5) * drop
            x = math.cos(angle) * radius_here
            y = math.sin(angle) * radius_here * squash + lean * t
            row.append(centre + Vector((x, y, z_here)))
        rows.append(row)
    tears: dict[int, float] = {}
    if tear > 0.0:
        tears[len(rows) - 2] = tear
        tears[len(rows) - 1] = tear * 1.4
    shell = lathe(name, rows, material, tears)
    solidify(shell, 0.016)
    return shell


def hood_shell(name: str, material, top_z: float, drop: float, radius: float,
               opening_z: float, depth: float, fold_count: int, salt: float,
               cavity: float = 1.30, sharp: float = 0.14):
    """A cowl whose front is scooped into a face cavity.

    ``opening_z`` is the brow line: above it the cloth is intact, below it the
    front is pushed back by ``cavity`` radii over a ``sharp`` metre transition,
    which opens a hard-rimmed hole for the void bowl and ember eyes.
    """
    sides = 48
    rows = 26
    verts: list[Vector] = []
    grid: list[list[int]] = []
    for row in range(rows):
        v = row / (rows - 1)
        ring: list[int] = []
        for step in range(sides):
            angle = (step / sides) * math.tau
            wobble = hash01(step * 0.71 + row * 2.13 + salt)
            profile = 0.30 + 0.70 * math.sin(min(1.0, v * 1.10) * math.pi * 0.5)
            fold = math.sin(angle * fold_count + math.sin(angle * 2.0) * 0.5) * 0.035 * (0.3 + v)
            r = radius * profile * (1.0 + fold + (wobble - 0.5) * 0.03)
            z = top_z - drop * v
            x = math.cos(angle) * r
            y = math.sin(angle) * r * depth
            front = max(0.0, math.sin(angle))
            scoop = smoothstep(0.0, 1.0, (opening_z - z) / max(0.03, sharp)) * (front ** 1.5)
            y -= scoop * radius * cavity
            z -= scoop * 0.02
            ring.append(len(verts))
            verts.append(Vector((x, y, z)))
        grid.append(ring)
    faces: list[tuple[int, ...]] = []
    for row in range(rows - 1):
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((grid[row][step], grid[row][nxt], grid[row + 1][nxt], grid[row + 1][step]))
    shell = link_mesh(name, verts, faces, material)
    solidify(shell, 0.024)
    return shell


def void_bowl(name: str, material, centre: Vector, radius: float, squash: float):
    """The black inside of a hood or chest cavity.

    An open-fronted half bowl: the rim sits on the front plane so the dark
    interior is what a viewer sees through the opening.
    """
    sides = 32
    rows = 14
    verts: list[Vector] = []
    grid: list[list[int]] = []
    for row in range(rows):
        v = row / (rows - 1)
        # 0 at the rim (front plane), 1 at the back of the cup.
        polar = (1.0 - v) * math.pi * 0.5
        ring: list[int] = []
        for step in range(sides):
            angle = (step / sides) * math.tau
            r = math.cos(polar) * radius
            depth_back = math.sin(polar) * radius * squash
            ring.append(len(verts))
            verts.append(centre + Vector((math.cos(angle) * r, -depth_back, math.sin(angle) * r * 0.92)))
        grid.append(ring)
    faces: list[tuple[int, ...]] = []
    for row in range(rows - 1):
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((grid[row][step], grid[row][nxt], grid[row + 1][nxt], grid[row + 1][step]))
    bowl = link_mesh(name, verts, faces, material)
    solidify(bowl, 0.008)
    return bowl


def carve_front(obj, z_low: float, z_high: float, half_width: float, depth: float,
                salt: float = 0.0) -> None:
    """Recess the front of a body so a face fissure reads as a real hollow."""
    mesh = obj.data
    for vertex in mesh.vertices:
        point = vertex.co
        if point.y <= 0.0:
            continue
        vertical = smoothstep(z_low, z_low + 0.05, point.z) * (1.0 - smoothstep(z_high - 0.05, z_high, point.z))
        lateral = 1.0 - smoothstep(half_width * 0.55, half_width, abs(point.x))
        if vertical <= 0.0 or lateral <= 0.0:
            continue
        bite = vertical * lateral
        # A little raggedness keeps the recess from looking machined.
        bite *= 0.82 + 0.18 * hash01(point.z * 9.1 + point.x * 7.3 + salt)
        vertex.co.y -= depth * bite
    mesh.update()


def flare_base(obj, height: float, amount: float) -> None:
    """Widen the bottom radially so a trunk reads as a rooted tree, not a post."""
    mesh = obj.data
    for vertex in mesh.vertices:
        point = vertex.co
        if point.z >= height:
            continue
        t = 1.0 - smoothstep(0.0, height, point.z)
        radial = Vector((point.x, point.y, 0.0))
        if radial.length_squared < 1e-8:
            continue
        vertex.co = point + radial.normalized() * (amount * t * t)
    mesh.update()


def carve_dimple(obj, centre: Vector, radius: float, depth: float,
                 axis_scale: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> None:
    """Press a socket into the front of a body along -Y."""
    mesh = obj.data
    for vertex in mesh.vertices:
        point = vertex.co
        if point.y <= centre.y - radius * 0.4:
            continue
        delta = Vector((
            (point.x - centre.x) / max(1e-5, radius * axis_scale[0]),
            (point.z - centre.z) / max(1e-5, radius * axis_scale[1]),
            0.0,
        ))
        falloff = 1.0 - smoothstep(0.35, 1.0, delta.length)
        if falloff <= 0.0:
            continue
        vertex.co.y -= depth * falloff
    mesh.update()


def front_extent(obj, z_center: float, z_tolerance: float = 0.04, x_limit: float = 0.06) -> float:
    """Forward-most surface Y near a height, measured instead of guessed."""
    best = 0.0
    for vertex in obj.data.vertices:
        if abs(vertex.co.z - z_center) <= z_tolerance and abs(vertex.co.x) <= x_limit:
            best = max(best, vertex.co.y)
    return best


def ember_eye(name: str, material, centre: Vector, radius: float):
    sides = 12
    rows = 8
    verts: list[Vector] = []
    grid: list[list[int]] = []
    for row in range(rows):
        polar = (row / (rows - 1)) * math.pi
        ring: list[int] = []
        for step in range(sides):
            angle = (step / sides) * math.tau
            r = math.sin(polar) * radius
            z = math.cos(polar) * radius * 0.55
            ring.append(len(verts))
            verts.append(centre + Vector((math.cos(angle) * r, -abs(z) * 0.4, math.sin(angle) * r + z * 0.2)))
        grid.append(ring)
    faces: list[tuple[int, ...]] = []
    for row in range(rows - 1):
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((grid[row][step], grid[row][nxt], grid[row + 1][nxt], grid[row + 1][step]))
    return link_mesh(name, verts, faces, material)


def antler_rack(name: str, base: Vector, direction: Vector, length: float, radius: float,
                levels: int, material, salt: float, curve: float = 0.55,
                gravity: float = 0.0) -> list[tuple[list[Vector], list[float]]]:
    """Recursive branching rack: a gnarly beam with secondary tines."""
    rng = random.Random(int(salt * 1000) + 17)
    branches: list[tuple[list[Vector], list[float]]] = []

    def grow(origin: Vector, heading: Vector, size: float, thick: float, depth: int) -> None:
        steps = 6
        path = [origin.copy()]
        heading = heading.normalized()
        bend = Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.10, 0.06), gravity))
        for step in range(1, steps + 1):
            t = step / steps
            step_heading = (heading + bend * t * curve).normalized()
            point = path[-1] + step_heading * (size / steps)
            path.append(point)
        # Keep a real radius at the tip: an antler tine that tapers to a
        # needle renders as a floating line instead of part of the rack.
        radii = [max(0.009, thick * (1.0 - 0.62 * (i / steps) ** 0.85)) for i in range(steps + 1)]
        branches.append((path, radii))
        if depth <= 0:
            return
        for tine in range(2 if depth == 1 else 3):
            at = 0.44 + 0.22 * tine
            index = min(steps, max(1, int(round(at * steps))))
            origin_point = path[index]
            spread = 0.58 + rng.uniform(-0.12, 0.18)
            side = Vector((rng.uniform(-1.0, 1.0), rng.uniform(-0.7, 0.4), rng.uniform(0.2, 1.0)))
            child = (heading * math.cos(spread) + side.normalized() * math.sin(spread)).normalized()
            grow(origin_point, child, size * rng.uniform(0.50, 0.66), radii[index] * 0.74, depth - 1)

    grow(base, direction, length, radius, levels)
    return branches


def claw_set(name: str, material, origin: Vector, forward: Vector, spread: float,
             count: int, length: float, radius: float, curl: float, salt: float,
             down: float = 0.55):
    branches: list[tuple[list[Vector], list[float]]] = []
    for index in range(count):
        t = 0.0 if count == 1 else (index / (count - 1)) - 0.5
        heading = (forward + Vector((t * spread, 0.0, -down))).normalized()
        path = [origin.copy()]
        point = origin.copy()
        step_heading = heading
        for step in range(4):
            step_heading = (step_heading + Vector((0.0, 0.04 * curl, -0.22 * curl))).normalized()
            point = point + step_heading * (length / 4.0)
            path.append(point.copy())
        lengths = [radius * (1.0 - 0.86 * (i / 4.0)) for i in range(5)]
        branches.append((path, lengths))
    return merge_tubes(name, branches, 6, material, wobble=0.05, salt=salt)


# ---------------------------------------------------------------------------
# Mob 1: Hollow warden


WARDEN_JOINTS = {
    "pelvis": ((0.0, 0.0, 0.90), (0.0, 0.0, 1.06)),
    "spine_01": ((0.0, 0.0, 1.06), (0.0, 0.005, 1.24)),
    "spine_02": ((0.0, 0.005, 1.24), (0.0, 0.010, 1.46)),
    "chest": ((0.0, 0.010, 1.46), (0.0, 0.005, 1.72)),
    "neck_01": ((0.0, 0.005, 1.72), (0.0, 0.015, 1.86)),
    "neck_02": ((0.0, 0.015, 1.86), (0.0, 0.020, 1.96)),
    "head": ((0.0, 0.020, 1.96), (0.0, 0.020, 2.18)),
    "jaw": ((0.0, 0.055, 2.00), (0.0, 0.105, 1.90)),
    "thigh_l": ((0.115, 0.0, 0.88), (0.125, 0.020, 0.47)),
    "shin_l": ((0.125, 0.020, 0.47), (0.130, -0.025, 0.12)),
    "foot_l": ((0.130, -0.025, 0.12), (0.130, 0.100, 0.030)),
    "toe_l": ((0.130, 0.100, 0.030), (0.130, 0.205, 0.018)),
    "thigh_r": ((-0.115, 0.0, 0.88), (-0.125, 0.020, 0.47)),
    "shin_r": ((-0.125, 0.020, 0.47), (-0.130, -0.025, 0.12)),
    "foot_r": ((-0.130, -0.025, 0.12), (-0.130, 0.100, 0.030)),
    "toe_r": ((-0.130, 0.100, 0.030), (-0.130, 0.205, 0.018)),
    "clavicle_l": ((0.030, 0.005, 1.66), (0.150, 0.010, 1.63)),
    "upper_arm_l": ((0.150, 0.010, 1.63), (0.235, 0.030, 1.310)),
    "lower_arm_l": ((0.235, 0.030, 1.310), (0.285, 0.060, 0.990)),
    "hand_l": ((0.285, 0.060, 0.990), (0.300, 0.085, 0.875)),
    "finger_l_1": ((0.282, 0.100, 0.890), (0.288, 0.150, 0.775)),
    "finger_l_2": ((0.303, 0.095, 0.890), (0.318, 0.145, 0.790)),
    "finger_l_3": ((0.322, 0.080, 0.890), (0.344, 0.115, 0.808)),
    "clavicle_r": ((-0.030, 0.005, 1.66), (-0.150, 0.010, 1.63)),
    "upper_arm_r": ((-0.150, 0.010, 1.63), (-0.235, 0.030, 1.310)),
    "lower_arm_r": ((-0.235, 0.030, 1.310), (-0.285, 0.060, 0.990)),
    "hand_r": ((-0.285, 0.060, 0.990), (-0.300, 0.085, 0.875)),
    "finger_r_1": ((-0.282, 0.100, 0.890), (-0.288, 0.150, 0.775)),
    "finger_r_2": ((-0.303, 0.095, 0.890), (-0.318, 0.145, 0.790)),
    "finger_r_3": ((-0.322, 0.080, 0.890), (-0.344, 0.115, 0.808)),
    "antler_l": ((0.055, -0.005, 2.200), (0.190, -0.030, 2.460)),
    "antler_l2": ((0.190, -0.030, 2.460), (0.330, -0.060, 2.740)),
    "antler_r": ((-0.055, -0.005, 2.200), (-0.190, -0.030, 2.460)),
    "antler_r2": ((-0.190, -0.030, 2.460), (-0.330, -0.060, 2.740)),
    "robe_f1": ((0.0, 0.235, 1.00), (0.0, 0.300, 0.58)),
    "robe_f2": ((0.0, 0.300, 0.58), (0.0, 0.340, 0.10)),
    "robe_b1": ((0.0, -0.215, 1.00), (0.0, -0.270, 0.58)),
    "robe_b2": ((0.0, -0.270, 0.58), (0.0, -0.310, 0.10)),
    "robe_l1": ((0.215, 0.0, 1.00), (0.330, 0.0, 0.58)),
    "robe_l2": ((0.330, 0.0, 0.58), (0.430, 0.0, 0.10)),
    "robe_r1": ((-0.215, 0.0, 1.00), (-0.330, 0.0, 0.58)),
    "robe_r2": ((-0.330, 0.0, 0.58), (-0.430, 0.0, 0.10)),
}

WARDEN_PARENTS = {
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
    "antler_l": ("head", False),
    "antler_l2": ("antler_l", True),
    "antler_r": ("head", False),
    "antler_r2": ("antler_r", True),
    "robe_f1": ("pelvis", False),
    "robe_f2": ("robe_f1", True),
    "robe_b1": ("pelvis", False),
    "robe_b2": ("robe_b1", True),
    "robe_l1": ("pelvis", False),
    "robe_l2": ("robe_l1", True),
    "robe_r1": ("pelvis", False),
    "robe_r2": ("robe_r1", True),
}


def assemble_warden():
    cloth = material("cloth")
    void = material("void")
    ember = material("ember")
    antler = material("antler")
    bone = material("bone")
    moss = material("moss")

    body = metaball_mesh(
        "WardenBody",
        lambda mb: (
            metaball_capsule(mb, (0.0, 0.0, 0.98), (0.0, 0.0, 1.20), 0.145),
            metaball_capsule(mb, (0.0, 0.0, 1.20), (0.0, 0.005, 1.46), 0.155),
            metaball_capsule(mb, (0.0, 0.005, 1.46), (0.0, 0.0, 1.70), 0.150),
            metaball_ellipsoid(mb, (0.0, 0.0, 1.72), (0.135, 0.120, 0.075)),
            metaball_capsule(mb, (0.0, 0.005, 1.72), (0.0, 0.015, 1.94), 0.058),
        ),
        0.014,
        0.6,
        0.5,
        cloth,
    )

    mantle = lathe_from_profile(
        "WardenMantle",
        [(1.82, 0.115), (1.74, 0.170), (1.64, 0.235), (1.52, 0.282), (1.40, 0.302),
         (1.30, 0.300)],
        44,
        cloth,
        11,
        0.055,
        0.055,
        3.1,
        tear=0.07,
    )

    robe = lathe_from_profile(
        "WardenRobe",
        [
            (1.46, 0.185),
            (1.34, 0.196),
            (1.20, 0.212),
            (1.06, 0.232),
            (0.92, 0.266),
            (0.78, 0.308),
            (0.62, 0.356),
            (0.46, 0.404),
            (0.32, 0.446),
            (0.22, 0.484),
            (0.15, 0.500),
        ],
        56,
        cloth,
        11,
        0.085,
        0.105,
        5.7,
        tear=0.18,
    )
    displace_radial(robe, 2, 0.010, 10.0, 0.45, 1.3)

    hood = hood_shell("WardenHood", cloth, 2.30, 0.78, 0.335, 2.145, 1.05, 12, 2.3,
                      cavity=1.38, sharp=0.11)
    cowl_lining = void_bowl("WardenVoid", void, Vector((0.0, 0.010, 2.03)), 0.185, 0.95)

    eyes = [
        ember_eye("WardenEyeL", ember, Vector((0.058, 0.096, 2.058)), 0.028),
        ember_eye("WardenEyeR", ember, Vector((-0.058, 0.096, 2.058)), 0.028),
    ]

    sleeves = {}
    for side, sx in (("l", 1.0), ("r", -1.0)):
        sleeves[side] = open_tube(
            f"WardenSleeve_{side}",
            [
                Vector((sx * 0.120, 0.008, 1.700)),
                Vector((sx * 0.170, 0.018, 1.560)),
                Vector((sx * 0.235, 0.030, 1.310)),
                Vector((sx * 0.270, 0.048, 1.130)),
                Vector((sx * 0.288, 0.066, 0.960)),
                Vector((sx * 0.296, 0.078, 0.880)),
            ],
            [0.098, 0.094, 0.090, 0.094, 0.108, 0.122],
            18,
            cloth,
            wobble=0.16,
            salt=8.1 + sx,
            fringe=0.35,
            thickness=0.013,
        )

    hands = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        hand = claw_set(
            f"WardenHand_{side}",
            bone,
            Vector((sx * 0.298, 0.082, 0.885)),
            Vector((0.0, 0.62, -0.30)),
            0.62,
            4,
            0.190,
            0.017,
            1.30,
            6.5 + sx,
        )
        hands.append(hand)

    feet = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        foot = metaball_mesh(
            f"WardenFoot_{side}",
            lambda mb, sx=sx: (
                metaball_ellipsoid(mb, (sx * 0.130, 0.020, 0.055), (0.052, 0.090, 0.050)),
                metaball_capsule(mb, (sx * 0.130, -0.020, 0.095), (sx * 0.130, 0.030, 0.140), 0.042),
            ),
            0.010,
            0.6,
            0.6,
            bone,
        )
        claws = claw_set(
            f"WardenToes_{side}",
            bone,
            Vector((sx * 0.130, 0.090, 0.035)),
            Vector((0.0, 1.0, -0.15)),
            0.85,
            3,
            0.080,
            0.013,
            0.35,
            11.0 + sx,
            down=0.2,
        )
        feet.extend([foot, claws])

    rack = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        branches = antler_rack(
            f"WardenAntler_{side}",
            Vector((sx * 0.062, -0.010, 2.215)),
            Vector((sx * 0.52, -0.10, 0.85)),
            1.00,
            0.050,
            3,
            antler,
            40.0 + sx,
            curve=0.82,
            gravity=0.13,
        )
        # A low backward tine pair gives the rack the swept, heavy base of the
        # reference rather than a pair of upright twigs.
        branches.extend(antler_rack(
            f"WardenAntlerBack_{side}",
            Vector((sx * 0.050, -0.075, 2.185)),
            Vector((sx * 0.44, -0.62, 0.65)),
            0.54,
            0.034,
            1,
            antler,
            44.0 + sx,
            curve=0.6,
            gravity=0.10,
        ))
        rack.append(merge_tubes(f"WardenAntler_{side}", branches, 8, antler, 0.0, 12.0 + sx))

    moss_patches = metaball_mesh(
        "WardenMoss",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, -0.14, 2.24), (0.085, 0.070, 0.040)),
            metaball_ellipsoid(mb, (0.16, -0.10, 2.16), (0.060, 0.055, 0.032)),
            metaball_ellipsoid(mb, (-0.15, -0.06, 1.66), (0.070, 0.055, 0.035)),
            metaball_ellipsoid(mb, (0.26, 0.10, 1.30), (0.045, 0.040, 0.028)),
            metaball_ellipsoid(mb, (-0.30, -0.03, 0.86), (0.050, 0.045, 0.030)),
        ),
        0.010,
        0.62,
        0.6,
        moss,
    )

    # Weights: each layer is bound to the bones that own it. The robe needs
    # its own bone fan, otherwise a hip envelope drags the hem with the legs.
    warden_skin_torso = {
        "pelvis": (0.24, 0.8), "spine_01": (0.24, 1.0), "spine_02": (0.22, 1.0),
        "chest": (0.22, 1.0), "neck_01": (0.12, 1.0), "neck_02": (0.10, 1.0),
    }
    assign_envelope_weights(body, warden_skin_torso)
    assign_envelope_weights(mantle, {
        "chest": (0.30, 1.0), "neck_01": (0.24, 0.9), "spine_02": (0.28, 0.8),
        "clavicle_l": (0.20, 0.6), "clavicle_r": (0.20, 0.6),
    })
    assign_envelope_weights(robe, {
        "pelvis": (0.42, 0.55), "spine_01": (0.30, 0.35),
        "robe_f1": (0.30, 1.15), "robe_f2": (0.42, 1.25),
        "robe_b1": (0.30, 1.15), "robe_b2": (0.42, 1.25),
        "robe_l1": (0.32, 1.15), "robe_l2": (0.44, 1.25),
        "robe_r1": (0.32, 1.15), "robe_r2": (0.44, 1.25),
    }, 3)
    assign_envelope_weights(hood, {
        "head": (0.42, 1.2), "neck_02": (0.28, 0.7), "jaw": (0.20, 0.25),
    }, 2)
    rigid_weight(cowl_lining, "head")
    for eye in eyes:
        rigid_weight(eye, "head")
    for side in ("l", "r"):
        assign_envelope_weights(sleeves[side], {
            f"upper_arm_{side}": (0.20, 1.0), f"lower_arm_{side}": (0.20, 1.1),
            f"hand_{side}": (0.12, 0.7),
        }, 2)
    for side, hand in zip(("l", "r"), hands):
        rigid_weight(hand, f"hand_{side}")
    for index, obj in enumerate(feet):
        side = "l" if index < 2 else "r"
        if "Toes" in obj.name:
            rigid_weight(obj, f"toe_{side}")
        else:
            blend_weight(obj, f"foot_{side}", f"shin_{side}",
                         lambda co: smoothstep(0.055, 0.135, co.z))
    for side, part in zip(("l", "r"), rack):
        rigid_weight(part, f"antler_{side}")
    rigid_weight(moss_patches, "chest")

    parts = [mantle, robe, hood, cowl_lining, *eyes, sleeves["l"], sleeves["r"],
             *hands, *feet, *rack, moss_patches]
    mesh = join_parts(body, parts, "ForestMesh")
    return mesh


# ---------------------------------------------------------------------------
# Mob 2: Ossuary stalker


STALKER_JOINTS = {
    "pelvis": ((0.0, 0.0, 0.86), (0.0, 0.0, 1.00)),
    "spine_01": ((0.0, 0.0, 1.00), (0.0, 0.005, 1.16)),
    "spine_02": ((0.0, 0.005, 1.16), (0.0, 0.010, 1.34)),
    "chest": ((0.0, 0.010, 1.34), (0.0, 0.005, 1.56)),
    "neck_01": ((0.0, 0.005, 1.56), (0.0, 0.015, 1.68)),
    "neck_02": ((0.0, 0.015, 1.68), (0.0, 0.020, 1.76)),
    "head": ((0.0, 0.020, 1.76), (0.0, 0.030, 1.98)),
    "jaw": ((0.0, 0.050, 1.86), (0.0, 0.115, 1.755)),
    "thigh_l": ((0.110, 0.0, 0.84), (0.120, 0.020, 0.46)),
    "shin_l": ((0.120, 0.020, 0.46), (0.125, -0.030, 0.12)),
    "foot_l": ((0.125, -0.030, 0.12), (0.125, 0.100, 0.030)),
    "toe_l": ((0.125, 0.100, 0.030), (0.125, 0.210, 0.018)),
    "thigh_r": ((-0.110, 0.0, 0.84), (-0.120, 0.020, 0.46)),
    "shin_r": ((-0.120, 0.020, 0.46), (-0.125, -0.030, 0.12)),
    "foot_r": ((-0.125, -0.030, 0.12), (-0.125, 0.100, 0.030)),
    "toe_r": ((-0.125, 0.100, 0.030), (-0.125, 0.210, 0.018)),
    "clavicle_l": ((0.030, 0.0, 1.50), (0.140, 0.0, 1.47)),
    "upper_arm_l": ((0.140, 0.0, 1.47), (0.190, 0.015, 1.16)),
    "lower_arm_l": ((0.190, 0.015, 1.16), (0.225, 0.035, 0.88)),
    "hand_l": ((0.225, 0.035, 0.88), (0.235, 0.055, 0.775)),
    "finger_l_1": ((0.215, 0.070, 0.790), (0.220, 0.120, 0.680)),
    "finger_l_2": ((0.238, 0.065, 0.790), (0.252, 0.115, 0.690)),
    "finger_l_3": ((0.256, 0.050, 0.790), (0.276, 0.085, 0.700)),
    "clavicle_r": ((-0.030, 0.0, 1.50), (-0.140, 0.0, 1.47)),
    "upper_arm_r": ((-0.140, 0.0, 1.47), (-0.190, 0.015, 1.16)),
    "lower_arm_r": ((-0.190, 0.015, 1.16), (-0.225, 0.035, 0.88)),
    "hand_r": ((-0.225, 0.035, 0.88), (-0.235, 0.055, 0.775)),
    "finger_r_1": ((-0.215, 0.070, 0.790), (-0.220, 0.120, 0.680)),
    "finger_r_2": ((-0.238, 0.065, 0.790), (-0.252, 0.115, 0.690)),
    "finger_r_3": ((-0.256, 0.050, 0.790), (-0.276, 0.085, 0.700)),
    "antler_l": ((0.048, 0.030, 1.90), (0.150, 0.010, 2.06)),
    "antler_l2": ((0.150, 0.010, 2.06), (0.245, -0.010, 2.20)),
    "antler_r": ((-0.048, 0.030, 1.90), (-0.150, 0.010, 2.06)),
    "antler_r2": ((-0.150, 0.010, 2.06), (-0.245, -0.010, 2.20)),
    "shroud_f1": ((0.0, 0.145, 0.92), (0.0, 0.190, 0.58)),
    "shroud_f2": ((0.0, 0.190, 0.58), (0.0, 0.215, 0.22)),
    "shroud_b1": ((0.0, -0.135, 0.92), (0.0, -0.170, 0.58)),
    "shroud_b2": ((0.0, -0.170, 0.58), (0.0, -0.195, 0.24)),
    "shroud_l1": ((0.135, 0.0, 0.92), (0.190, 0.0, 0.58)),
    "shroud_l2": ((0.190, 0.0, 0.58), (0.225, 0.0, 0.26)),
    "shroud_r1": ((-0.135, 0.0, 0.92), (-0.190, 0.0, 0.58)),
    "shroud_r2": ((-0.190, 0.0, 0.58), (-0.225, 0.0, 0.26)),
}

STALKER_PARENTS = {
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
    "antler_l": ("head", False),
    "antler_l2": ("antler_l", True),
    "antler_r": ("head", False),
    "antler_r2": ("antler_r", True),
    "shroud_f1": ("pelvis", False),
    "shroud_f2": ("shroud_f1", True),
    "shroud_b1": ("pelvis", False),
    "shroud_b2": ("shroud_b1", True),
    "shroud_l1": ("pelvis", False),
    "shroud_l2": ("shroud_l1", True),
    "shroud_r1": ("pelvis", False),
    "shroud_r2": ("shroud_r1", True),
}


def assemble_stalker():
    bone = material("bone")
    leather = material("leather")
    cloth = material("cloth")
    antler = material("antler")
    moss = material("moss")
    void = material("void")
    ember = material("ember")

    # A person in a costume. The body underneath is human — shoulders, waist,
    # elbows, knees — and everything above it is salvage: hide, rag cloth,
    # bone stitched on, antlers lashed to a brow band. The costume, not the
    # skeleton, is what you see.
    body = metaball_mesh(
        "StalkerBody",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, 0.0, 0.945), (0.132, 0.092, 0.098)),
            metaball_capsule(mb, (0.0, 0.005, 0.985), (0.0, 0.010, 1.215), 0.100),
            metaball_capsule(mb, (0.0, 0.010, 1.215), (0.0, 0.004, 1.500), 0.122),
            metaball_ellipsoid(mb, (0.0, 0.010, 1.520), (0.148, 0.098, 0.072)),
            # neck: flares out of the shoulders and narrows under the jaw
            metaball_capsule(mb, (0.0, 0.014, 1.470), (0.0, 0.022, 1.620), 0.074),
            metaball_capsule(mb, (0.0, 0.022, 1.620), (0.0, 0.026, 1.742), 0.052),
            metaball_ellipsoid(mb, (0.082, 0.006, 1.545), (0.080, 0.062, 0.050)),
            metaball_ellipsoid(mb, (-0.082, 0.006, 1.545), (0.080, 0.062, 0.050)),
            metaball_ellipsoid(mb, (0.0, 0.020, 1.795), (0.086, 0.092, 0.092)),
            metaball_ellipsoid(mb, (0.0, 0.070, 1.762), (0.060, 0.052, 0.058)),
            metaball_capsule(mb, (0.162, 0.008, 1.505), (0.212, 0.020, 1.185), 0.047),
            metaball_capsule(mb, (0.212, 0.020, 1.185), (0.240, 0.042, 0.930), 0.036),
            metaball_ellipsoid(mb, (0.246, 0.048, 0.888), (0.036, 0.046, 0.038)),
            metaball_capsule(mb, (-0.162, 0.008, 1.505), (-0.212, 0.020, 1.185), 0.047),
            metaball_capsule(mb, (-0.212, 0.020, 1.185), (-0.240, 0.042, 0.930), 0.036),
            metaball_ellipsoid(mb, (-0.246, 0.048, 0.888), (0.036, 0.046, 0.038)),
            metaball_capsule(mb, (0.104, 0.0, 0.900), (0.112, 0.018, 0.500), 0.056),
            metaball_capsule(mb, (0.112, 0.018, 0.500), (0.116, -0.018, 0.095), 0.041),
            metaball_ellipsoid(mb, (0.118, 0.042, 0.052), (0.046, 0.100, 0.042)),
            metaball_capsule(mb, (-0.104, 0.0, 0.900), (-0.112, 0.018, 0.500), 0.056),
            metaball_capsule(mb, (-0.112, 0.018, 0.500), (-0.116, -0.018, 0.095), 0.041),
            metaball_ellipsoid(mb, (-0.118, 0.042, 0.052), (0.046, 0.100, 0.042)),
        ),
        0.009,
        0.6,
        0.4,
        leather,
    )

    # Costume layer one: a fitted cloth tunic. It follows the body — wide at
    # the shoulders, in at the waist, out at the hips — because a lathe here
    # reads as a soda can with a head on it.
    tunic = metaball_mesh(
        "StalkerTunic",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, 0.006, 1.445), (0.188, 0.108, 0.120)),
            metaball_ellipsoid(mb, (0.0, 0.002, 1.300), (0.152, 0.094, 0.105)),
            metaball_capsule(mb, (0.0, 0.0, 1.240), (0.0, 0.004, 1.120), 0.114),
            metaball_ellipsoid(mb, (0.0, 0.0, 1.010), (0.158, 0.106, 0.098)),
            metaball_ellipsoid(mb, (0.152, 0.008, 1.512), (0.062, 0.058, 0.052)),
            metaball_ellipsoid(mb, (-0.152, 0.008, 1.512), (0.062, 0.058, 0.052)),
        ),
        0.010,
        0.6,
        0.42,
        cloth,
    )
    crumple(tunic, 0.011, 24.0, 1.7)

    # The torn hem is a separate short skirt below the belt, where a flared
    # tube is the correct shape.
    skirt = lathe_from_profile(
        "StalkerSkirt",
        [(1.030, 0.176), (0.960, 0.196), (0.880, 0.214), (0.800, 0.230), (0.730, 0.240)],
        40,
        cloth,
        11,
        0.09,
        0.10,
        3.4,
        tear=0.20,
    )
    crumple(skirt, 0.015, 20.0, 3.9)

    collar = lathe_from_profile(
        "StalkerCollar",
        [(1.628, 0.086), (1.596, 0.104), (1.560, 0.122), (1.520, 0.132)],
        26,
        cloth,
        8,
        0.05,
        0.030,
        4.7,
        tear=0.08,
    )
    crumple(collar, 0.008, 30.0, 4.9)

    hood = hood_shell("StalkerHood", cloth, 1.995, 0.315, 0.170, 1.862, 1.0, 9, 3.3,
                      cavity=1.15, sharp=0.085)
    crumple(hood, 0.008, 26.0, 7.1)
    cowl_lining = void_bowl("StalkerCowlVoid", void, Vector((0.0, 0.028, 1.812)), 0.098, 0.75)

    # The skull is a mask worn under the hood, with embers behind its sockets.
    mask = metaball_mesh(
        "StalkerMask",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, 0.062, 1.802), (0.074, 0.070, 0.086)),
            metaball_ellipsoid(mb, (0.0, 0.126, 1.772), (0.044, 0.050, 0.052)),
            metaball_ellipsoid(mb, (0.0, 0.048, 1.742), (0.056, 0.046, 0.040)),
        ),
        0.007,
        0.6,
        0.35,
        bone,
    )
    carve_dimple(mask, Vector((0.032, 0.112, 1.808)), 0.038, 0.020, (1.0, 0.85, 1.0))
    carve_dimple(mask, Vector((-0.032, 0.112, 1.808)), 0.038, 0.020, (1.0, 0.85, 1.0))
    socket_front = front_extent(mask, 1.808, 0.02, 0.02)
    # Empty sockets: black pits, nothing burning in them.
    mask_eyes = [
        ember_eye("StalkerSocketL", void, Vector((0.032, socket_front - 0.012, 1.808)), 0.021),
        ember_eye("StalkerSocketR", void, Vector((-0.032, socket_front - 0.012, 1.808)), 0.021),
    ]
    mask_jaw = metaball_mesh(
        "StalkerMaskJaw",
        lambda mb: (
            metaball_capsule(mb, (-0.036, 0.070, 1.744), (0.036, 0.070, 1.744), 0.016),
            metaball_capsule(mb, (0.0, 0.085, 1.740), (0.0, 0.128, 1.728), 0.020),
        ),
        0.006,
        0.6,
        0.35,
        bone,
    )

    # Antlers are strapped on: a hide brow band carries them.
    brow_band = lathe_from_profile(
        "StalkerBrowBand",
        [(1.898, 0.098), (1.872, 0.112), (1.846, 0.106)],
        22,
        leather,
        7,
        0.05,
        0.010,
        9.3,
    )
    rack = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        branches = antler_rack(
            f"StalkerAntler_{side}",
            Vector((sx * 0.058, 0.062, 1.878)),
            Vector((sx * 0.60, -0.10, 0.79)),
            0.46,
            0.040,
            2,
            antler,
            55.0 + sx,
            curve=0.60,
            gravity=0.08,
        )
        rack.append(merge_tubes(f"StalkerAntler_{side}", branches, 7, antler, 0.0, 22.0 + sx))

    belt = lathe_from_profile(
        "StalkerBelt",
        [(1.055, 0.196), (1.020, 0.208), (0.980, 0.202), (0.950, 0.188)],
        26,
        leather,
        9,
        0.04,
        0.012,
        12.1,
    )
    straps = merge_tubes("StalkerStraps", [
        ([Vector((sx * 0.150, 0.108, 1.500)), Vector((-sx * 0.090, 0.140, 1.120))],
         [0.016, 0.013])
        for sx in (-1.0, 1.0)
    ], 6, leather, 0.08, 14.6)

    # Bone sewn onto the costume: three rib bars, uneven, plus one pauldron.
    ribs = merge_tubes("StalkerRibBones", [
        (
            [Vector((-0.135, 0.096, 1.455)), Vector((-0.060, 0.135, 1.430)),
             Vector((0.040, 0.128, 1.395))],
            [0.013, 0.016, 0.011],
        ),
        (
            [Vector((-0.140, 0.088, 1.360)), Vector((-0.058, 0.133, 1.340)),
             Vector((0.062, 0.122, 1.300))],
            [0.013, 0.016, 0.011],
        ),
        (
            [Vector((-0.120, 0.082, 1.268)), Vector((-0.040, 0.128, 1.252)),
             Vector((0.030, 0.118, 1.222))],
            [0.011, 0.014, 0.010],
        ),
    ], 6, bone, 0.10, 16.1)
    pauldron = bark_slab(
        "StalkerPauldron",
        Vector((-0.118, 0.006, 1.545)),
        Vector((-0.52, 0.10, -0.85)),
        0.215,
        0.165,
        0.030,
        bone,
        salt=17.3,
    )
    flat_shade(pauldron)

    sleeves = []
    forearm_wraps = []
    gloves = []
    claws = []
    trousers = []
    shin_wraps = []
    boots = []
    toe_caps = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        sleeve = open_tube(
            f"StalkerSleeve_{side}",
            [Vector((sx * 0.140, 0.010, 1.520)), Vector((sx * 0.180, 0.016, 1.350)),
             Vector((sx * 0.208, 0.024, 1.200))],
            [0.078, 0.066, 0.050],
            16,
            cloth,
            wobble=0.14,
            salt=31.0 + sx,
            fringe=0.30,
            thickness=0.012,
        )
        crumple(sleeve, 0.010, 30.0, 33.0 + sx)
        wraps = open_tube(
            f"StalkerForearmWrap_{side}",
            [Vector((sx * 0.208, 0.024, 1.196)), Vector((sx * 0.226, 0.034, 1.060)),
             Vector((sx * 0.240, 0.044, 0.940))],
            [0.052, 0.046, 0.042],
            14,
            leather,
            wobble=0.10,
            salt=35.0 + sx,
            thickness=0.009,
        )
        glove = metaball_mesh(
            f"StalkerGlove_{side}",
            lambda mb, sx=sx: (
                metaball_ellipsoid(mb, (sx * 0.248, 0.050, 0.892), (0.040, 0.050, 0.042)),
                metaball_capsule(mb, (sx * 0.248, 0.050, 0.892), (sx * 0.252, 0.070, 0.812), 0.030),
            ),
            0.007,
            0.6,
            0.5,
            leather,
        )
        claw = claw_set(
            f"StalkerClaws_{side}",
            bone,
            Vector((sx * 0.252, 0.086, 0.800)),
            Vector((0.0, 0.45, -0.55)),
            0.55,
            4,
            0.105,
            0.009,
            1.20,
            41.0 + sx,
        )
        trouser = open_tube(
            f"StalkerTrouser_{side}",
            [Vector((sx * 0.100, 0.0, 0.930)), Vector((sx * 0.108, 0.014, 0.700)),
             Vector((sx * 0.112, 0.014, 0.520))],
            [0.088, 0.078, 0.070],
            16,
            cloth,
            wobble=0.14,
            salt=45.0 + sx,
            fringe=0.26,
            thickness=0.012,
        )
        crumple(trouser, 0.009, 32.0, 47.0 + sx)
        wrap = open_tube(
            f"StalkerShinWrap_{side}",
            [Vector((sx * 0.112, 0.012, 0.520)), Vector((sx * 0.116, -0.010, 0.300)),
             Vector((sx * 0.116, -0.014, 0.150))],
            [0.052, 0.046, 0.044],
            14,
            leather,
            wobble=0.10,
            salt=51.0 + sx,
            thickness=0.009,
        )
        boot = metaball_mesh(
            f"StalkerBoot_{side}",
            lambda mb, sx=sx: (
                metaball_capsule(mb, (sx * 0.116, -0.010, 0.150), (sx * 0.118, 0.045, 0.062), 0.046),
                metaball_ellipsoid(mb, (sx * 0.118, 0.062, 0.050), (0.046, 0.096, 0.040)),
            ),
            0.008,
            0.6,
            0.5,
            leather,
        )
        toe = claw_set(
            f"StalkerToeCap_{side}",
            bone,
            Vector((sx * 0.118, 0.140, 0.038)),
            Vector((0.0, 1.0, -0.10)),
            0.75,
            3,
            0.070,
            0.011,
            0.25,
            55.0 + sx,
            down=0.12,
        )
        sleeves.append(sleeve)
        forearm_wraps.append(wraps)
        gloves.append(glove)
        claws.append(claw)
        trousers.append(trouser)
        shin_wraps.append(wrap)
        boots.append(boot)
        toe_caps.append(toe)

    moss_patches = metaball_mesh(
        "StalkerMoss",
        lambda mb: (
            metaball_ellipsoid(mb, (0.075, -0.150, 1.330), (0.055, 0.030, 0.045)),
            metaball_ellipsoid(mb, (-0.090, 0.030, 0.760), (0.045, 0.040, 0.050)),
        ),
        0.009,
        0.62,
        0.5,
        moss,
    )

    assign_envelope_weights(body, {
        "pelvis": (0.20, 1.0), "spine_01": (0.20, 1.0), "spine_02": (0.18, 1.0),
        "chest": (0.22, 1.0), "neck_01": (0.12, 1.0), "neck_02": (0.10, 1.0),
        "head": (0.14, 1.0),
        "clavicle_l": (0.13, 0.6), "clavicle_r": (0.13, 0.6),
        "upper_arm_l": (0.11, 1.0), "upper_arm_r": (0.11, 1.0),
        "lower_arm_l": (0.10, 1.0), "lower_arm_r": (0.10, 1.0),
        "hand_l": (0.09, 0.9), "hand_r": (0.09, 0.9),
        "thigh_l": (0.13, 1.0), "thigh_r": (0.13, 1.0),
        "shin_l": (0.10, 1.0), "shin_r": (0.10, 1.0),
        "foot_l": (0.09, 0.9), "foot_r": (0.09, 0.9),
    }, 3)
    assign_envelope_weights(tunic, {
        "pelvis": (0.26, 0.9), "spine_01": (0.26, 1.0), "spine_02": (0.24, 1.0),
        "chest": (0.28, 1.0), "neck_01": (0.14, 0.6),
        "clavicle_l": (0.16, 0.7), "clavicle_r": (0.16, 0.7),
    }, 3)
    assign_envelope_weights(collar, {
        "chest": (0.16, 1.0), "neck_01": (0.12, 1.0), "neck_02": (0.10, 0.8),
    }, 2)
    assign_envelope_weights(skirt, {
        "pelvis": (0.30, 0.9),
        "shroud_f1": (0.22, 1.1), "shroud_f2": (0.32, 1.2),
        "shroud_b1": (0.22, 1.1), "shroud_b2": (0.32, 1.2),
        "shroud_l1": (0.24, 1.1), "shroud_l2": (0.34, 1.2),
        "shroud_r1": (0.24, 1.1), "shroud_r2": (0.34, 1.2),
    }, 3)
    assign_envelope_weights(hood, {"head": (0.24, 1.2), "neck_02": (0.16, 0.6)}, 2)
    rigid_weight(cowl_lining, "head")
    assign_envelope_weights(mask, {"head": (0.16, 1.2)})
    rigid_weight(mask_jaw, "jaw")
    for eye in mask_eyes:
        rigid_weight(eye, "head")
    assign_envelope_weights(brow_band, {"head": (0.14, 1.2)})
    for side, part in zip(("l", "r"), rack):
        rigid_weight(part, f"antler_{side}")
    rigid_weight(belt, "pelvis")
    rigid_weight(straps, "chest")
    rigid_weight(ribs, "chest")
    rigid_weight(pauldron, "clavicle_r")
    for index, part in enumerate(sleeves):
        side = "l" if index == 0 else "r"
        assign_envelope_weights(part, {
            f"clavicle_{side}": (0.12, 0.5), f"upper_arm_{side}": (0.13, 1.0),
            f"lower_arm_{side}": (0.10, 0.8),
        }, 2)
    for index, part in enumerate(forearm_wraps):
        rigid_weight(part, f"lower_arm_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(gloves):
        rigid_weight(part, f"hand_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(claws):
        rigid_weight(part, f"hand_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(trousers):
        side = "l" if index == 0 else "r"
        assign_envelope_weights(part, {f"thigh_{side}": (0.14, 1.0), f"shin_{side}": (0.10, 0.6)}, 2)
    for index, part in enumerate(shin_wraps):
        rigid_weight(part, f"shin_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(boots):
        side = "l" if index == 0 else "r"
        assign_envelope_weights(part, {f"foot_{side}": (0.10, 1.0), f"shin_{side}": (0.08, 0.6)}, 2)
    for index, part in enumerate(toe_caps):
        rigid_weight(part, f"toe_{'l' if index == 0 else 'r'}")
    rigid_weight(moss_patches, "chest")

    parts = [tunic, skirt, collar, hood, cowl_lining, mask, mask_jaw, *mask_eyes,
             brow_band, *rack,
             belt, straps, ribs, pauldron, *sleeves, *forearm_wraps, *gloves, *claws,
             *trousers, *shin_wraps, *boots, *toe_caps, moss_patches]
    mesh = join_parts(body, parts, "ForestMesh")
    return mesh


# ---------------------------------------------------------------------------
# Mob 3: Gallowsroot


GALLOWSROOT_JOINTS = {
    "pelvis": ((0.0, 0.0, 1.020), (0.0, 0.0, 1.140)),
    "spine_01": ((0.0, 0.0, 1.140), (0.0, 0.010, 1.340)),
    "spine_02": ((0.0, 0.010, 1.340), (0.0, 0.005, 1.540)),
    "chest": ((0.0, 0.005, 1.540), (0.0, 0.010, 1.740)),
    "neck_01": ((0.0, 0.010, 1.740), (0.0, 0.018, 1.840)),
    "neck_02": ((0.0, 0.018, 1.840), (0.0, 0.022, 1.900)),
    "head": ((0.0, 0.022, 1.900), (0.0, 0.030, 2.100)),
    "jaw": ((0.0, 0.088, 1.948), (0.0, 0.132, 1.850)),
    "thigh_l": ((0.115, 0.0, 1.000), (0.125, 0.018, 0.560)),
    "shin_l": ((0.125, 0.018, 0.560), (0.130, -0.022, 0.115)),
    "foot_l": ((0.130, -0.022, 0.115), (0.135, 0.105, 0.030)),
    "toe_l": ((0.135, 0.105, 0.030), (0.135, 0.230, 0.018)),
    "thigh_r": ((-0.115, 0.0, 1.000), (-0.125, 0.018, 0.560)),
    "shin_r": ((-0.125, 0.018, 0.560), (-0.130, -0.022, 0.115)),
    "foot_r": ((-0.130, -0.022, 0.115), (-0.135, 0.105, 0.030)),
    "toe_r": ((-0.135, 0.105, 0.030), (-0.135, 0.230, 0.018)),
    "clavicle_l": ((0.035, 0.008, 1.700), (0.165, 0.008, 1.680)),
    "upper_arm_l": ((0.165, 0.008, 1.680), (0.225, 0.028, 1.340)),
    "lower_arm_l": ((0.225, 0.028, 1.340), (0.265, 0.048, 1.000)),
    "hand_l": ((0.265, 0.048, 1.000), (0.278, 0.066, 0.885)),
    "finger_l_1": ((0.262, 0.082, 0.892), (0.266, 0.126, 0.788)),
    "finger_l_2": ((0.282, 0.076, 0.892), (0.296, 0.118, 0.798)),
    "finger_l_3": ((0.300, 0.058, 0.892), (0.320, 0.094, 0.812)),
    "clavicle_r": ((-0.035, 0.008, 1.700), (-0.165, 0.008, 1.680)),
    "upper_arm_r": ((-0.165, 0.008, 1.680), (-0.225, 0.028, 1.340)),
    "lower_arm_r": ((-0.225, 0.028, 1.340), (-0.265, 0.048, 1.000)),
    "hand_r": ((-0.265, 0.048, 1.000), (-0.278, 0.066, 0.885)),
    "finger_r_1": ((-0.262, 0.082, 0.892), (-0.266, 0.126, 0.788)),
    "finger_r_2": ((-0.282, 0.076, 0.892), (-0.296, 0.118, 0.798)),
    "finger_r_3": ((-0.300, 0.058, 0.892), (-0.320, 0.094, 0.812)),
    "crown_l": ((0.060, 0.030, 2.055), (0.190, 0.000, 2.260)),
    "crown_l2": ((0.190, 0.000, 2.260), (0.320, -0.040, 2.470)),
    "crown_r": ((-0.060, 0.030, 2.055), (-0.190, 0.000, 2.260)),
    "crown_r2": ((-0.190, 0.000, 2.260), (-0.320, -0.040, 2.470)),
}

GALLOWSROOT_PARENTS = {
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
}


def assemble_gallowsroot():
    bark = material("bark")
    leather = material("leather")
    cloth = material("cloth")
    moss = material("moss")
    antler = material("antler")
    bone = material("bone")
    void = material("void")
    ember = material("ember")

    # A big man in a costume: coat, bark plates strapped over it, a carved mask
    # with branches lashed to the brow band. Human proportions underneath — the
    # costume is what you see, not a tree.
    body = metaball_mesh(
        "RootBody",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, 0.0, 1.035), (0.150, 0.105, 0.110)),
            metaball_capsule(mb, (0.0, 0.005, 1.080), (0.0, 0.010, 1.340), 0.115),
            metaball_capsule(mb, (0.0, 0.010, 1.340), (0.0, 0.005, 1.680), 0.145),
            metaball_ellipsoid(mb, (0.0, 0.010, 1.700), (0.180, 0.115, 0.085)),
            metaball_capsule(mb, (0.0, 0.014, 1.640), (0.0, 0.020, 1.820), 0.088),
            metaball_capsule(mb, (0.0, 0.020, 1.820), (0.0, 0.024, 1.920), 0.062),
            metaball_ellipsoid(mb, (0.095, 0.006, 1.700), (0.090, 0.070, 0.055)),
            metaball_ellipsoid(mb, (-0.095, 0.006, 1.700), (0.090, 0.070, 0.055)),
            metaball_ellipsoid(mb, (0.0, 0.020, 1.965), (0.100, 0.105, 0.105)),
            metaball_ellipsoid(mb, (0.0, 0.075, 1.930), (0.072, 0.060, 0.066)),
            metaball_capsule(mb, (0.180, 0.008, 1.685), (0.240, 0.026, 1.345), 0.058),
            metaball_capsule(mb, (0.240, 0.026, 1.345), (0.290, 0.050, 1.010), 0.046),
            metaball_ellipsoid(mb, (0.295, 0.058, 0.935), (0.055, 0.060, 0.055)),
            metaball_capsule(mb, (-0.180, 0.008, 1.685), (-0.240, 0.026, 1.345), 0.058),
            metaball_capsule(mb, (-0.240, 0.026, 1.345), (-0.290, 0.050, 1.010), 0.046),
            metaball_ellipsoid(mb, (-0.295, 0.058, 0.935), (0.055, 0.060, 0.055)),
            metaball_capsule(mb, (0.115, 0.0, 1.010), (0.125, 0.018, 0.570), 0.068),
            metaball_capsule(mb, (0.125, 0.018, 0.570), (0.130, -0.020, 0.130), 0.050),
            metaball_ellipsoid(mb, (0.133, 0.045, 0.062), (0.056, 0.115, 0.048)),
            metaball_capsule(mb, (-0.115, 0.0, 1.010), (-0.125, 0.018, 0.570), 0.068),
            metaball_capsule(mb, (-0.125, 0.018, 0.570), (-0.130, -0.020, 0.130), 0.050),
            metaball_ellipsoid(mb, (-0.133, 0.045, 0.062), (0.056, 0.115, 0.048)),
        ),
        0.011,
        0.6,
        0.4,
        leather,
    )

    # The coat: long, heavy, creased and torn. Two layers so the silhouette has
    # the stacked, off-centre bulk of real worn clothing.
    coat = lathe_from_profile(
        "RootCoat",
        [(1.760, 0.205), (1.660, 0.232), (1.500, 0.246), (1.320, 0.244), (1.140, 0.256),
         (0.960, 0.276), (0.780, 0.298), (0.620, 0.318), (0.480, 0.330)],
        48,
        cloth,
        11,
        0.10,
        0.11,
        2.3,
        tear=0.20,
    )
    crumple(coat, 0.020, 15.0, 6.2)
    cape = lathe_from_profile(
        "RootCape",
        [(1.760, 0.215), (1.680, 0.250), (1.590, 0.268), (1.500, 0.272)],
        40,
        leather,
        9,
        0.12,
        0.09,
        4.4,
        tear=0.26,
    )
    crumple(cape, 0.016, 20.0, 8.3)

    # Bark plates strapped over the coat: hard, flat, hand-cut.
    plates = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        plates.append(bark_slab(f"RootPlateShoulder_{side}", Vector((sx * 0.185, 0.020, 1.700)),
                                Vector((sx * 0.55, 0.10, -0.83)), 0.240, 0.185, 0.045, bark,
                                salt=51.0 + sx))
        plates.append(bark_slab(f"RootPlateChest_{side}", Vector((sx * 0.090, 0.215, 1.590)),
                                Vector((sx * 0.28, 0.34, -0.90)), 0.215, 0.150, 0.038, bark,
                                salt=53.0 + sx))
        plates.append(bark_slab(f"RootPlateRib_{side}", Vector((sx * 0.105, 0.205, 1.370)),
                                Vector((sx * 0.30, 0.36, -0.88)), 0.185, 0.130, 0.034, bark,
                                salt=55.0 + sx))
    for plate in plates:
        flat_shade(plate)
    belt = lathe_from_profile(
        "RootBelt",
        [(1.075, 0.268), (1.040, 0.282), (0.995, 0.274), (0.960, 0.258)],
        30,
        leather,
        9,
        0.04,
        0.012,
        61.0,
    )

    # A hooded head wearing a carved wooden mask; embers burn in its slit.
    hood = hood_shell("RootHood", cloth, 2.175, 0.330, 0.185, 2.010, 1.0, 9, 7.3,
                      cavity=1.10, sharp=0.09)
    crumple(hood, 0.010, 24.0, 9.1)
    cowl_lining = void_bowl("RootHoodVoid", void, Vector((0.0, 0.030, 1.960)), 0.110, 0.70)
    mask = metaball_mesh(
        "RootMask",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, 0.070, 1.960), (0.115, 0.105, 0.120)),
            metaball_ellipsoid(mb, (0.0, 0.150, 1.930), (0.070, 0.070, 0.070)),
            metaball_ellipsoid(mb, (0.0, 0.055, 1.885), (0.095, 0.075, 0.055)),
        ),
        0.009,
        0.6,
        0.4,
        bark,
    )
    displace_radial(mask, 2, 0.010, 18.0, 0.5, 5.5)
    carve_front(mask, 1.905, 2.045, 0.075, 0.070, salt=6.6)
    mask_front = front_extent(mask, 1.975, 0.05, 0.04)
    mask_void = void_bowl("RootMaskVoid", void, Vector((0.0, mask_front + 0.004, 1.975)), 0.072, 0.45)
    mask_glow = [
        ember_eye("RootEyeL", ember, Vector((0.038, mask_front - 0.008, 1.998)), 0.028),
        ember_eye("RootEyeR", ember, Vector((-0.038, mask_front - 0.008, 1.998)), 0.028),
    ]
    mask_jaw = metaball_mesh(
        "RootMaskJaw",
        lambda mb: (
            metaball_capsule(mb, (-0.062, mask_front - 0.020, 1.905),
                             (0.062, mask_front - 0.020, 1.905), 0.026),
            metaball_ellipsoid(mb, (0.0, mask_front + 0.006, 1.888), (0.050, 0.036, 0.030)),
        ),
        0.008,
        0.6,
        0.4,
        bark,
    )
    brow_band = lathe_from_profile(
        "RootBrowBand",
        [(2.070, 0.118), (2.040, 0.132), (2.010, 0.124)],
        24,
        leather,
        7,
        0.05,
        0.010,
        63.0,
    )
    crown = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        branches = antler_rack(f"RootCrown_{side}", Vector((sx * 0.070, 0.060, 2.055)),
                               Vector((sx * 0.55, -0.08, 0.83)), 0.62, 0.048, 2, antler,
                               81.0 + sx, curve=0.55, gravity=-0.05)
        crown.append(merge_tubes(f"RootCrown_{side}", branches, 7, antler, 0.0, 83.0 + sx))
    crown_mid = antler_rack("RootCrownMid", Vector((0.0, 0.050, 2.090)),
                            Vector((0.02, -0.26, 0.96)), 0.44, 0.038, 1, antler, 85.0,
                            curve=0.45, gravity=-0.04)
    crown.append(merge_tubes("RootCrownMid", crown_mid, 7, antler, 0.0, 87.0))

    # Costume extremities: sleeves, bark mitts and bark boots over the human
    # hands and feet. Without sleeves the arms read as bare limbs.
    sleeves = []
    sleeves_wraps = []
    mitts = []
    claws = []
    boots = []
    toe_caps = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        sleeve = open_tube(
            f"RootSleeve_{side}",
            [Vector((sx * 0.160, 0.010, 1.700)), Vector((sx * 0.205, 0.020, 1.500)),
             Vector((sx * 0.248, 0.034, 1.330))],
            [0.105, 0.092, 0.075],
            16,
            cloth,
            wobble=0.14,
            salt=91.0 + sx,
            fringe=0.28,
            thickness=0.014,
        )
        crumple(sleeve, 0.014, 26.0, 93.0 + sx)
        sleeve_wrap = open_tube(
            f"RootSleeveWrap_{side}",
            [Vector((sx * 0.248, 0.034, 1.330)), Vector((sx * 0.272, 0.044, 1.160)),
             Vector((sx * 0.292, 0.054, 1.000))],
            [0.064, 0.058, 0.052],
            14,
            leather,
            wobble=0.10,
            salt=95.0 + sx,
            thickness=0.010,
        )
        sleeves.append(sleeve)
        sleeves_wraps.append(sleeve_wrap)
        mitts.append(metaball_mesh(
            f"RootMitt_{side}",
            lambda mb, sx=sx: (
                metaball_ellipsoid(mb, (sx * 0.298, 0.060, 0.940), (0.062, 0.070, 0.062)),
                metaball_capsule(mb, (sx * 0.298, 0.060, 0.940), (sx * 0.305, 0.085, 0.845), 0.048),
            ),
            0.009,
            0.6,
            0.5,
            bark,
        ))
        claws.append(claw_set(f"RootClaws_{side}", antler, Vector((sx * 0.305, 0.098, 0.832)),
                              Vector((0.0, 0.55, -0.45)), 0.70, 4, 0.150, 0.022, 0.90, 73.0 + sx,
                              down=0.55))
        boots.append(metaball_mesh(
            f"RootBoot_{side}",
            lambda mb, sx=sx: (
                metaball_capsule(mb, (sx * 0.130, -0.014, 0.230), (sx * 0.133, 0.050, 0.070), 0.056),
                metaball_ellipsoid(mb, (sx * 0.133, 0.080, 0.055), (0.058, 0.108, 0.050)),
            ),
            0.009,
            0.6,
            0.5,
            bark,
        ))
        toe_caps.append(claw_set(f"RootToes_{side}", bone, Vector((sx * 0.133, 0.170, 0.038)),
                                 Vector((0.0, 1.0, -0.10)), 0.85, 3, 0.085, 0.013, 0.25,
                                 75.0 + sx, down=0.10))
    moss_patches = metaball_mesh(
        "RootMoss",
        lambda mb: (
            metaball_ellipsoid(mb, (0.0, -0.215, 1.560), (0.095, 0.050, 0.080)),
            metaball_ellipsoid(mb, (0.170, -0.120, 1.300), (0.070, 0.050, 0.065)),
            metaball_ellipsoid(mb, (-0.150, 0.150, 1.700), (0.065, 0.045, 0.055)),
        ),
        0.010,
        0.62,
        0.5,
        moss,
    )

    assign_envelope_weights(body, {
        "pelvis": (0.24, 1.0), "spine_01": (0.22, 1.0), "spine_02": (0.22, 1.0),
        "chest": (0.26, 1.0), "neck_01": (0.14, 1.0), "neck_02": (0.11, 1.0),
        "head": (0.16, 1.0),
        "clavicle_l": (0.16, 0.6), "clavicle_r": (0.16, 0.6),
        "upper_arm_l": (0.13, 1.0), "upper_arm_r": (0.13, 1.0),
        "lower_arm_l": (0.12, 1.0), "lower_arm_r": (0.12, 1.0),
        "hand_l": (0.11, 0.9), "hand_r": (0.11, 0.9),
        "thigh_l": (0.16, 1.0), "thigh_r": (0.16, 1.0),
        "shin_l": (0.12, 1.0), "shin_r": (0.12, 1.0),
        "foot_l": (0.11, 0.9), "foot_r": (0.11, 0.9),
    }, 3)
    # The coat hangs off the torso and swings with the legs at the hem.
    assign_envelope_weights(coat, {
        "pelvis": (0.34, 1.0), "spine_01": (0.30, 1.0), "spine_02": (0.26, 0.9),
        "chest": (0.24, 0.7), "thigh_l": (0.22, 1.0), "thigh_r": (0.22, 1.0),
    }, 3)
    assign_envelope_weights(cape, {
        "chest": (0.30, 1.0), "spine_02": (0.28, 1.0), "clavicle_l": (0.22, 0.7),
        "clavicle_r": (0.22, 0.7), "neck_01": (0.18, 0.5),
    }, 2)
    for plate in plates:
        rigid_weight(plate, "chest")
    rigid_weight(belt, "pelvis")
    assign_envelope_weights(hood, {"head": (0.26, 1.2), "neck_02": (0.16, 0.6)}, 2)
    rigid_weight(cowl_lining, "head")
    assign_envelope_weights(mask, {"head": (0.20, 1.2)})
    rigid_weight(mask_jaw, "jaw")
    rigid_weight(mask_void, "head")
    for glow in mask_glow:
        rigid_weight(glow, "head")
    assign_envelope_weights(brow_band, {"head": (0.16, 1.2)})
    rigid_weight(crown[0], "crown_l")
    rigid_weight(crown[1], "crown_r")
    rigid_weight(crown[2], "head")
    for index, part in enumerate(sleeves):
        side = "l" if index == 0 else "r"
        assign_envelope_weights(part, {
            f"clavicle_{side}": (0.14, 0.5), f"upper_arm_{side}": (0.15, 1.0),
            f"lower_arm_{side}": (0.12, 0.9),
        }, 2)
    for index, part in enumerate(sleeves_wraps):
        rigid_weight(part, f"lower_arm_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(mitts):
        rigid_weight(part, f"hand_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(claws):
        rigid_weight(part, f"hand_{'l' if index == 0 else 'r'}")
    for index, part in enumerate(boots):
        side = "l" if index == 0 else "r"
        assign_envelope_weights(part, {f"foot_{side}": (0.12, 1.0), f"shin_{side}": (0.10, 0.6)}, 2)
    for index, part in enumerate(toe_caps):
        rigid_weight(part, f"toe_{'l' if index == 0 else 'r'}")
    assign_envelope_weights(moss_patches, {
        "chest": (0.26, 1.0), "spine_02": (0.24, 1.0), "spine_01": (0.22, 0.8),
        "neck_01": (0.16, 0.7),
    }, 2)

    parts = [coat, cape, *plates, belt, hood, cowl_lining, mask, mask_jaw, mask_void,
             *mask_glow, brow_band, *crown, *sleeves, *sleeves_wraps,
             *mitts, *claws, *boots, *toe_caps, moss_patches]
    mesh = join_parts(body, parts, "ForestMesh")
    return mesh


ASSEMBLERS = {
    "hollow_warden": (WARDEN_JOINTS, WARDEN_PARENTS, assemble_warden),
    "ossuary_stalker": (STALKER_JOINTS, STALKER_PARENTS, assemble_stalker),
    "gallowsroot": (GALLOWSROOT_JOINTS, GALLOWSROOT_PARENTS, assemble_gallowsroot),
}


# ---------------------------------------------------------------------------
# Clips


def warden_base() -> dict:
    return {
        "pelvis_offset": Vector((0.0, 0.0, 0.0)),
        "pelvis_pitch": 0.0, "pelvis_roll": 0.0, "pelvis_yaw": 0.0,
        "spine1": (0.0, 0.0, 0.0), "spine2": (0.0, 0.0, 0.0), "chest_pose": (0.0, 0.0, 0.0),
        "neck1": (0.0, 0.0, 0.0), "neck2": (0.0, 0.0, 0.0), "head_pose": (0.0, 0.0, 0.0),
        "jaw_open": 0.0,
        "arm": {"l": (0.0, 0.0, 0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0, 0.0, 0.0)},
        "finger": {"l": 0.0, "r": 0.0},
        "antler": (0.0, 0.0, 0.0),
        "robe": {"f": (0.0, 0.0), "b": (0.0, 0.0), "l": (0.0, 0.0), "r": (0.0, 0.0)},
        "feet": {"l": (0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0)},
        "solve_feet": True,
    }


def warden_idle(t: float) -> dict:
    phase = (t / 2.8) % 1.0
    breath = math.sin(phase * math.tau)
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.0, 0.0, 0.007 * breath)),
        "spine1": (0.014 * breath, 0.0, 0.006 * math.sin(phase * math.tau + 0.6)),
        "spine2": (0.018 * breath, 0.0, 0.008 * math.sin(phase * math.tau + 0.9)),
        "chest_pose": (0.020 * breath, 0.02 * math.sin(phase * math.tau + 1.1), 0.010 * math.sin(phase * math.tau + 1.2)),
        "neck1": (-0.012 * breath, 0.03 * math.sin(phase * math.tau + 1.4), 0.0),
        "neck2": (-0.010 * breath, 0.02 * math.sin(phase * math.tau + 1.6), 0.0),
        "head_pose": (0.020 * math.sin(phase * math.tau + 0.4), 0.10 * math.sin(phase * math.tau * 0.5), 0.02 * math.sin(phase * math.tau * 0.5 + 0.7)),
        "jaw_open": 0.05 + 0.05 * math.sin(phase * math.tau * 2.0),
        "arm": {
            "l": (0.05 + 0.03 * math.sin(phase * math.tau + 0.3), 0.02, 0.10, 0.0, 0.0),
            "r": (0.05 + 0.03 * math.sin(phase * math.tau + 1.2), -0.02, 0.10, 0.0, 0.0),
        },
        "finger": {"l": 0.35, "r": 0.35},
        "antler": (0.02 * math.sin(phase * math.tau + 0.2), 0.03 * math.sin(phase * math.tau + 0.8), 0.0),
        "robe": {
            "f": (0.03 * math.sin(phase * math.tau + 0.9), 0.05 * math.sin(phase * math.tau + 0.4)),
            "b": (0.02 * math.sin(phase * math.tau + 0.2), 0.03 * math.sin(phase * math.tau - 0.3)),
            "l": (0.02 * math.sin(phase * math.tau + 0.6), 0.04 * math.sin(phase * math.tau + 0.1)),
            "r": (0.02 * math.sin(phase * math.tau + 1.5), 0.04 * math.sin(phase * math.tau + 1.0)),
        },
    })
    return values


def warden_locomotion(t: float, key: str) -> dict:
    spec = styles.MOBS["hollow_warden"]
    duration = spec["clips"][key]["duration"]
    stride = spec["stride"][key]
    duty = spec["duty"][key]
    clearance = spec["foot_lift"][key]
    phase = (t / duration) % 1.0
    step = math.sin(phase * math.tau)
    double = math.cos(phase * math.tau * 2.0)
    heavy = 1.0 if key == "walk" else 1.35
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.0, 0.0, (0.022 * double - 0.012) * heavy)),
        "pelvis_pitch": (0.03 if key == "walk" else 0.10),
        "pelvis_roll": 0.045 * step * heavy,
        "pelvis_yaw": 0.055 * step * heavy,
        "spine1": (-0.02, -0.03 * step, -0.02 * step),
        "spine2": (-0.02, -0.04 * step, -0.02 * step),
        "chest_pose": (-0.03, (-0.05 if key == "walk" else -0.09) * step, 0.02 * step),
        "neck1": (0.02, 0.02 * step, 0.0),
        "neck2": (0.02, 0.02 * step, 0.0),
        "head_pose": (0.06 if key == "walk" else 0.10, 0.06 * step, 0.0),
        "jaw_open": 0.06,
        "arm": {
            "l": (0.06 + 0.30 * step * heavy, 0.0, 0.12, 0.10, 0.0),
            "r": (0.06 - 0.30 * step * heavy, 0.0, 0.12, 0.10, 0.0),
        },
        "finger": {"l": 0.45, "r": 0.45},
        "antler": (0.03 * double, 0.05 * step, 0.0),
        "robe": {
            "f": (0.10 + 0.16 * step, 0.20 + 0.22 * step),
            "b": (-0.10 - 0.12 * step, -0.16 - 0.20 * step),
            "l": (0.0, 0.12 * step),
            "r": (0.0, -0.12 * step),
        },
    })
    for side, offset in (("l", 0.0), ("r", 0.5)):
        y, lift, pitch = foot_target(phase, offset, duty, stride, clearance)
        values["feet"][side] = (y, lift, pitch)
    return values


def warden_attack(t: float) -> dict:
    raise_ = keyed(t, [(0.0, 0.0), (0.14, 1.0), (0.40, 0.85), (0.48, 0.55), (0.56, 0.0), (0.80, 0.10), (1.10, 0.05), (1.60, 0.0)])
    swipe = keyed(t, [(0.0, 0.0), (0.42, 0.0), (0.52, 0.15), (0.66, 0.75), (0.78, 1.0), (0.86, 0.85), (1.00, 0.35), (1.30, 0.08), (1.60, 0.0)])
    twist = keyed(t, [(0.0, 0.0), (0.20, 0.35), (0.46, 0.45), (0.62, 0.10), (0.78, -0.45), (0.92, -0.55), (1.16, -0.20), (1.60, 0.0)])
    lunge = keyed(t, [(0.0, 0.0), (0.22, -0.04), (0.46, 0.0), (0.62, 0.10), (0.78, 0.18), (0.92, 0.12), (1.20, 0.02), (1.60, 0.0)])
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.0, lunge, -0.035 * raise_ + 0.015 * swipe)),
        "pelvis_pitch": -0.05 * raise_ + 0.10 * swipe,
        "pelvis_roll": -0.05 * twist,
        "pelvis_yaw": 0.30 * twist,
        "spine1": (0.02 * raise_ - 0.04 * swipe, 0.14 * twist, 0.03 * twist),
        "spine2": (0.03 * raise_ - 0.06 * swipe, 0.18 * twist, 0.04 * twist),
        "chest_pose": (0.05 * raise_ - 0.10 * swipe, 0.24 * twist, 0.05 * twist),
        "neck1": (-0.10 * raise_ + 0.06 * swipe, -0.05 * twist, 0.0),
        "neck2": (-0.12 * raise_ + 0.06 * swipe, -0.05 * twist, 0.0),
        "head_pose": (-0.18 * raise_ + 0.16 * swipe, -0.10 * twist, 0.04 * twist),
        "jaw_open": 0.10 + 0.55 * raise_ * (1.0 - swipe * 0.7),
        "arm": {
            "l": (-1.05 * raise_ + 0.55 * swipe, 0.30 * swipe, 0.55 * raise_ + 0.30, 0.35 * raise_ - 0.15 * swipe, 0.0),
            "r": (-1.20 * raise_ + 0.20 * swipe, -0.42 * swipe, 0.60 * raise_, 0.30 * raise_ - 0.10 * swipe, 0.0),
        },
        "finger": {"l": 1.15 - 0.55 * swipe, "r": 1.20 - 0.30 * swipe},
        "antler": (-0.10 * raise_, 0.08 * twist, 0.0),
        "robe": {
            "f": (-0.14 * raise_ + 0.30 * swipe, -0.22 * raise_ + 0.34 * swipe),
            "b": (0.16 * raise_ - 0.20 * swipe, 0.26 * raise_ - 0.24 * swipe),
            "l": (0.0, 0.18 * swipe),
            "r": (0.0, -0.18 * swipe),
        },
    })
    for side, offset in (("l", 0.62), ("r", 0.30)):
        values["feet"][side] = (0.10 * swipe, 0.0, 0.0)
    return values


def warden_hit(t: float) -> dict:
    strike = keyed(t, [(0.0, 0.0), (0.10, 1.0), (0.30, 0.35), (0.50, 0.0)])
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.02 * strike, -0.05 * strike, -0.02 * strike)),
        "pelvis_pitch": -0.10 * strike,
        "pelvis_roll": 0.06 * strike,
        "pelvis_yaw": 0.08 * strike,
        "spine1": (-0.10 * strike, 0.05 * strike, 0.05 * strike),
        "spine2": (-0.12 * strike, 0.06 * strike, 0.06 * strike),
        "chest_pose": (-0.16 * strike, 0.08 * strike, 0.08 * strike),
        "neck1": (-0.18 * strike, 0.0, 0.10 * strike),
        "neck2": (-0.20 * strike, -0.04 * strike, 0.10 * strike),
        "head_pose": (-0.26 * strike, -0.08 * strike, 0.14 * strike),
        "jaw_open": 0.45 * strike,
        "arm": {
            "l": (-0.35 * strike, 0.0, 0.35 * strike, 0.25 * strike, 0.0),
            "r": (-0.28 * strike, 0.0, 0.28 * strike, 0.20 * strike, 0.0),
        },
        "finger": {"l": 0.9, "r": 0.9},
        "antler": (-0.16 * strike, 0.0, 0.0),
        "robe": {
            "f": (0.20 * strike, 0.28 * strike),
            "b": (-0.12 * strike, -0.18 * strike),
            "l": (0.0, 0.0), "r": (0.0, 0.0),
        },
    })
    return values


def warden_death(t: float) -> dict:
    duration = styles.MOBS["hollow_warden"]["clips"]["death"]["duration"]
    p = max(0.0, min(1.0, t / duration))
    fold = smoothstep(0.05, 0.55, p)
    fall = smoothstep(0.30, 0.90, p)
    values = warden_base()
    values["solve_feet"] = False
    values.update({
        "pelvis_offset": Vector((0.10 * fall, -0.04 * fall, -0.44 * fold - 0.16 * fall)),
        "pelvis_pitch": -0.18 * fold + 0.30 * fall,
        "pelvis_roll": 0.30 * fold + 1.05 * fall,
        "pelvis_yaw": 0.10 * fall,
        "spine1": (0.10 * fold, 0.0, 0.10 * fall),
        "spine2": (0.14 * fold, 0.0, 0.14 * fall),
        "chest_pose": (0.16 * fold, 0.10 * fall, 0.16 * fall),
        "neck1": (-0.20 * fold, 0.0, 0.0),
        "neck2": (-0.16 * fold, 0.0, 0.0),
        "head_pose": (-0.30 * fold + 0.20 * fall, 0.20 * fall, 0.10 * fall),
        "jaw_open": 0.30 * (1.0 - fold) + 0.05,
        "arm": {
            "l": (0.35 * fold, 0.0, 0.55 * fold, 0.30 * fold, 0.0),
            "r": (-0.20 * fold, 0.0, 0.80 * fold, 0.20 * fold, 0.0),
        },
        "finger": {"l": 0.5, "r": 0.7},
        "antler": (-0.20 * fold, 0.10 * fall, 0.0),
        "robe": {
            "f": (0.30 * fold, 0.40 * fall),
            "b": (-0.20 * fold, -0.25 * fall),
            "l": (0.10 * fall, 0.20 * fall),
            "r": (-0.10 * fall, -0.10 * fall),
        },
    })
    for side, sign in (("l", 1.0), ("r", -1.0)):
        values.setdefault("leg_fold", {})[side] = (1.05 * fold, -0.85 * fold, 0.55 * fold, sign * 0.20 * fall)
    return values


def offset_pose(stance: dict, deltas: dict, amount: float) -> dict:
    """Layer a scaled delta table onto an authored stance.

    Tuples add element-wise, vectors add, and the ``arm``/``finger``/``robe``/
    ``feet`` tables recurse. Keys the deltas never mention pass through, and a
    zero ``amount`` reproduces the stance exactly, which is how a one-shot
    recoil returns to the idle frame it has to blend back into.
    """
    values = dict(stance)
    for key, delta in deltas.items():
        base = values.get(key)
        if isinstance(delta, dict):
            values[key] = offset_pose(base if isinstance(base, dict) else {}, delta, amount)
        elif isinstance(delta, Vector):
            values[key] = (base if isinstance(base, Vector) else Vector((0.0, 0.0, 0.0))) + delta * amount
        elif isinstance(base, tuple):
            values[key] = tuple(a + b * amount for a, b in zip(base, delta))
        else:
            values[key] = float(base or 0.0) + float(delta) * amount
    return values


def warden_attack_slash(t: float) -> dict:
    """A wide horizontal sweep: the antler crown and a bladed haft lead the arc.

    The coil loads the body onto its right heel, the crown and the blade carry
    the sweep across the front, and the follow-through unwinds into the stance.
    Impact sits on 0.66 s, where the crown and the hand are both at full travel.
    """
    coil = keyed(t, [(0.0, 0.0), (0.16, 0.72), (0.30, 1.0), (0.42, 0.45),
                     (0.56, 0.10), (0.66, 0.0), (1.35, 0.0)])
    sweep = keyed(t, [(0.0, 0.0), (0.30, 0.0), (0.42, 0.22), (0.54, 0.68), (0.66, 1.0),
                      (0.80, 0.86), (0.98, 0.38), (1.20, 0.10), (1.35, 0.0)])
    drop = keyed(t, [(0.0, 0.0), (0.30, 0.35), (0.54, 0.70), (0.66, 0.90),
                     (0.90, 0.30), (1.35, 0.0)])
    step = keyed(t, [(0.0, 0.0), (0.30, 0.08), (0.66, 0.16), (1.00, 0.06), (1.35, 0.0)])
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.04 * sweep - 0.03 * coil, 0.05 * sweep, -0.06 * drop)),
        "pelvis_pitch": -0.05 * coil + 0.06 * sweep,
        "pelvis_roll": -0.06 * coil + 0.08 * sweep,
        "pelvis_yaw": 0.30 * coil - 0.34 * sweep,
        "spine1": (0.02 * coil - 0.03 * sweep, 0.16 * coil - 0.18 * sweep, 0.03 * coil - 0.04 * sweep),
        "spine2": (0.02 * coil - 0.04 * sweep, 0.19 * coil - 0.21 * sweep, 0.03 * coil - 0.04 * sweep),
        "chest_pose": (0.03 * coil - 0.05 * sweep, 0.24 * coil - 0.28 * sweep, 0.04 * coil - 0.05 * sweep),
        "neck1": (-0.04 * coil + 0.03 * sweep, -0.12 * coil + 0.14 * sweep, 0.0),
        "neck2": (-0.05 * coil + 0.03 * sweep, -0.14 * coil + 0.16 * sweep, 0.0),
        "head_pose": (-0.07 * coil + 0.05 * sweep, -0.18 * coil + 0.20 * sweep, 0.03 * sweep),
        "jaw_open": 0.10 + 0.45 * max(coil, sweep),
        "arm": {
            "l": (0.05 - 0.35 * coil + 0.30 * sweep, 0.05 + 0.20 * coil - 0.30 * sweep,
                  -0.20 * coil + 0.15 * sweep, 0.40 * coil + 0.30 * sweep, 0.25 * sweep),
            "r": (0.10 - 0.75 * coil + 0.65 * sweep, 0.55 * coil - 0.85 * sweep,
                  0.35 * coil + 0.15 * sweep, 0.55 * coil + 0.55 * sweep,
                  1.15 + 0.25 * coil + 0.35 * sweep),
        },
        "finger": {"l": 0.55 + 0.45 * max(coil, sweep), "r": 1.30 + 0.15 * coil},
        "antler": (-0.10 * coil - 0.06 * sweep, 0.45 * coil - 0.60 * sweep, 0.0),
        "robe": {
            "f": (0.18 * coil + 0.30 * sweep, 0.18 * coil + 0.36 * sweep),
            "b": (-0.14 * coil - 0.24 * sweep, -0.14 * coil - 0.30 * sweep),
            "l": (0.0, 0.16 * sweep - 0.10 * coil),
            "r": (0.0, 0.16 * coil - 0.10 * sweep),
        },
    })
    values["feet"]["r"] = (step, 0.0, 0.0)
    values["feet"]["l"] = (-0.10 * step, 0.0, 0.0)
    return values


def warden_attack_stab(t: float) -> dict:
    """A committed lunge: the haft cocks under the shoulder, the body drops onto
    the front foot and the point drives forward. Impact 0.50 s."""
    cock = keyed(t, [(0.0, 0.0), (0.14, 0.55), (0.30, 1.0), (0.42, 0.30), (0.50, 0.0), (1.10, 0.0)])
    drive = keyed(t, [(0.0, 0.0), (0.24, 0.0), (0.38, 0.35), (0.50, 1.0),
                      (0.62, 0.92), (0.80, 0.45), (0.96, 0.16), (1.10, 0.0)])
    lunge = keyed(t, [(0.0, 0.0), (0.24, 0.10), (0.42, 0.55), (0.50, 1.0),
                      (0.66, 0.94), (0.86, 0.45), (1.10, 0.0)])
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.02 * drive, 0.16 * lunge - 0.05 * cock, -0.07 * lunge)),
        "pelvis_pitch": -0.04 * cock + 0.08 * drive,
        "pelvis_roll": -0.03 * drive,
        "pelvis_yaw": 0.22 * cock - 0.26 * drive,
        "spine1": (0.02 * cock - 0.03 * drive, 0.12 * cock - 0.14 * drive, 0.02 * cock),
        "spine2": (0.02 * cock - 0.05 * drive, 0.14 * cock - 0.17 * drive, 0.02 * cock),
        "chest_pose": (0.03 * cock - 0.07 * drive, 0.18 * cock - 0.22 * drive, 0.03 * cock),
        "neck1": (-0.06 * cock + 0.04 * drive, -0.08 * cock + 0.10 * drive, 0.0),
        "neck2": (-0.07 * cock + 0.05 * drive, -0.09 * cock + 0.11 * drive, 0.0),
        "head_pose": (-0.10 * cock + 0.08 * drive, -0.12 * cock + 0.14 * drive, 0.0),
        "jaw_open": 0.12 + 0.42 * drive,
        "arm": {
            "l": (0.05 - 0.20 * cock + 0.25 * drive, 0.05 + 0.15 * cock - 0.22 * drive,
                  -0.15 * cock + 0.10 * drive, 0.35 * cock + 0.25 * drive, 0.15 * drive),
            "r": (0.10 - 0.60 * cock + 1.05 * drive, 0.35 * cock - 0.30 * drive,
                  0.20 * cock + 0.10 * drive, 0.75 * cock + 0.25 * drive,
                  1.35 + 0.15 * cock + 0.30 * drive),
        },
        "finger": {"l": 0.60, "r": 1.35},
        "antler": (-0.12 * cock - 0.10 * drive, 0.20 * cock - 0.24 * drive, 0.0),
        "robe": {
            "f": (-0.10 * cock + 0.26 * drive, -0.12 * cock + 0.32 * drive),
            "b": (0.14 * cock - 0.22 * drive, 0.18 * cock - 0.28 * drive),
            "l": (0.0, 0.10 * cock),
            "r": (0.0, 0.10 * cock),
        },
    })
    values["feet"]["r"] = (0.30 * lunge, 0.0, 0.0)
    values["feet"]["l"] = (-0.04 * lunge - 0.08 * cock, 0.0, 0.0)
    return values


def warden_block(t: float) -> dict:
    """A holdable guard: weight back, the haft carried across the chest, the
    crown lowered over it, and a shallow breath the runtime can loop."""
    duration = styles.MOBS["hollow_warden"]["clips"]["block"]["duration"]
    phase = (t / duration) % 1.0
    breath = math.sin(phase * math.tau)
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.0, -0.05, -0.05 + 0.006 * breath)),
        "pelvis_pitch": 0.06 + 0.01 * breath,
        "pelvis_roll": 0.02 * breath,
        "pelvis_yaw": -0.06,
        "spine1": (0.03 + 0.010 * breath, -0.04, 0.0),
        "spine2": (0.04 + 0.012 * breath, -0.05, 0.0),
        "chest_pose": (0.05 + 0.014 * breath, -0.06, 0.01 * breath),
        "neck1": (-0.05 - 0.008 * breath, 0.03, 0.0),
        "neck2": (-0.06 - 0.006 * breath, 0.04, 0.0),
        "head_pose": (-0.08 - 0.006 * breath, 0.05, 0.0),
        "jaw_open": 0.06 + 0.03 * breath,
        "arm": {
            "l": (0.80 + 0.018 * breath, 0.40, -0.25, 1.30 + 0.020 * breath, 2.20),
            "r": (0.75 + 0.018 * breath, -0.35, 0.25, 1.35 + 0.020 * breath, 2.35),
        },
        "finger": {"l": 1.25, "r": 1.35},
        "antler": (-0.30 - 0.02 * breath, 0.05, 0.0),
        "robe": {
            "f": (0.10 + 0.02 * breath, 0.14),
            "b": (-0.10 - 0.02 * breath, -0.14),
            "l": (0.0, 0.04 * breath),
            "r": (0.0, 0.04 * breath),
        },
    })
    values["feet"]["r"] = (0.14, 0.0, 0.0)
    values["feet"]["l"] = (-0.10, 0.0, 0.0)
    return values


def warden_stagger(t: float) -> dict:
    """A one-shot recoil: shoulders driven back, head snapped, feet catching up.

    Authored as a delta over the first frame of the idle, so the last frame is
    that idle stance exactly and the runtime can cut the clip short anywhere.
    """
    recoil = keyed(t, [(0.0, 0.0), (0.09, 1.0), (0.20, 0.86), (0.32, 0.50),
                       (0.44, 0.20), (0.60, 0.0)])
    deltas = {
        "pelvis_offset": Vector((0.0, -0.11, -0.01)),
        "pelvis_pitch": 0.10,
        "pelvis_roll": 0.05,
        "pelvis_yaw": -0.07,
        "spine1": (0.16, 0.0, 0.04),
        "spine2": (0.20, 0.0, 0.05),
        "chest_pose": (0.28, -0.05, 0.06),
        "neck1": (0.14, 0.0, 0.0),
        "neck2": (0.16, 0.0, 0.0),
        "head_pose": (0.32, -0.09, 0.10),
        "jaw_open": 0.55,
        "arm": {"l": (0.28, 0.0, -0.45, 0.10, 0.30), "r": (0.32, 0.0, 0.45, 0.15, 0.35)},
        "finger": {"l": 0.40, "r": 0.35},
        "antler": (0.24, 0.0, 0.0),
        "robe": {"f": (0.20, 0.26), "b": (-0.22, -0.28), "l": (0.22, 0.28), "r": (0.22, 0.28)},
    }
    values = offset_pose(warden_idle(0.0), deltas, recoil)
    values["feet"]["l"] = (-0.18 * recoil, 0.035 * recoil, 0.0)
    values["feet"]["r"] = (0.04 * recoil, 0.0, 0.0)
    return values


def warden_crouch(t: float) -> dict:
    """A loopable low stalk: knees bent over a planted stance, the crown
    levelled forward, the haft carried ready across the body."""
    duration = styles.MOBS["hollow_warden"]["clips"]["crouch"]["duration"]
    phase = (t / duration) % 1.0
    sway = math.sin(phase * math.tau)
    breath = math.sin(phase * math.tau * 2.0)
    values = warden_base()
    values.update({
        "pelvis_offset": Vector((0.01 * sway, 0.02, -0.17 + 0.012 * breath)),
        "pelvis_pitch": -0.20,
        "pelvis_roll": 0.02 * sway,
        "pelvis_yaw": 0.04 * sway,
        "spine1": (-0.13 + 0.008 * breath, 0.02 * sway, 0.0),
        "spine2": (-0.16 + 0.010 * breath, 0.02 * sway, 0.0),
        "chest_pose": (-0.19 + 0.012 * breath, 0.03 * sway, 0.01 * sway),
        "neck1": (0.12, -0.02 * sway, 0.0),
        "neck2": (0.13, -0.02 * sway, 0.0),
        "head_pose": (0.14 + 0.008 * breath, -0.03 * sway, 0.0),
        "jaw_open": 0.05 + 0.03 * breath,
        "arm": {
            "l": (0.62 + 0.015 * breath, 0.30, -0.22, 0.80, 1.15),
            "r": (0.55 + 0.015 * breath, -0.30, 0.24, 0.90, 1.35),
        },
        "finger": {"l": 1.15, "r": 1.30},
        "antler": (-0.34 - 0.02 * breath, 0.04 * sway, 0.0),
        "robe": {
            "f": (1.00 + 0.02 * breath, 1.06),
            "b": (-0.98 - 0.02 * breath, -1.04),
            "l": (0.95, 1.05),
            "r": (0.95, 1.05),
        },
    })
    values["feet"]["r"] = (0.20, 0.0, 0.0)
    values["feet"]["l"] = (-0.16, 0.0, 0.0)
    return values


ARM_CHAINS = {
    "hollow_warden": ("clavicle_{side}", "upper_arm_{side}", "lower_arm_{side}", "hand_{side}"),
    "ossuary_stalker": ("clavicle_{side}", "upper_arm_{side}", "lower_arm_{side}", "hand_{side}"),
    "gallowsroot": ("clavicle_{side}", "upper_arm_{side}", "lower_arm_{side}", "hand_{side}"),
}

TORSO_CHAIN = (
    ("spine_01", "spine1"),
    ("spine_02", "spine2"),
    ("chest", "chest_pose"),
    ("neck_01", "neck1"),
    ("neck_02", "neck2"),
    ("head", "head_pose"),
)

CLOTH_CHAINS = {"robe": "robe_", "shroud": "shroud_"}


def apply_pose(mob: str, values: dict, fold_legs: dict | None = None) -> None:
    """Apply one authored frame onto the rig, per-mob chains and all."""
    rig = RIG
    pelvis_pitch = values.get("pelvis_pitch", 0.0)
    set_pelvis_offset(rig, values.get("pelvis_offset", Vector((0.0, 0.0, 0.0))))
    pelvis_q = world_quaternion(pelvis_pitch, values.get("pelvis_yaw", 0.0), values.get("pelvis_roll", 0.0))
    set_world_rotation(rig.pose.bones["pelvis"], pelvis_q)
    accum = pelvis_q
    chest_accum = pelvis_q
    for bone, key in TORSO_CHAIN:
        if bone not in rig.pose.bones:
            continue
        pitch, yaw, roll = values.get(key, (0.0, 0.0, 0.0))
        accum = chain_bone(rig, bone, pitch, yaw, roll, accum)
        if bone == "chest":
            chest_accum = accum
    set_axis_rotation(rig.pose.bones["jaw"], -values.get("jaw_open", 0.0))

    bones = rig.pose.bones
    for side in ("l", "r"):
        chain = [template.format(side=side) if template else "" for template in ARM_CHAINS[mob]]
        pitch, yaw, splay, elbow, hand = values.get("arm", {}).get(side, (0.0,) * 5)
        side_accum = chest_accum
        if chain[0]:
            side_accum = chain_bone(rig, chain[0], splay * 0.30, 0.0, splay, side_accum)
        side_accum = chain_bone(rig, chain[1], pitch, yaw, splay, side_accum)
        side_accum = chain_bone(rig, chain[2], elbow, 0.0, 0.0, side_accum)
        chain_bone(rig, chain[3], hand, 0.0, 0.0, side_accum)
        curl = values.get("finger", {}).get(side, 0.0)
        for index in (1, 2, 3):
            name = f"finger_{side}_{index}"
            if name in bones:
                set_axis_rotation(bones[name], 0.45 * curl)
    antler_pitch, antler_yaw, antler_roll = values.get("antler", (0.0, 0.0, 0.0))
    for side in ("l", "r"):
        if f"antler_{side}" not in bones:
            continue
        set_world_rotation(bones[f"antler_{side}"], world_quaternion(antler_pitch, antler_yaw, 0.0))
        if f"antler_{side}2" in bones:
            set_world_rotation(bones[f"antler_{side}2"],
                               world_quaternion(antler_pitch * 0.6, antler_yaw * 0.4, antler_roll))
    for key, prefix in (("f", "robe_f"), ("b", "robe_b"), ("l", "robe_l"), ("r", "robe_r")):
        if prefix + "1" not in bones:
            continue
        near, far = values.get("robe", {}).get(key, (0.0, 0.0))
        set_axis_rotation(bones[prefix + "1"], near)
        set_axis_rotation(bones[prefix + "2"], far - near)
    for key, prefix in (("f", "shroud_f"), ("b", "shroud_b"), ("l", "shroud_l"), ("r", "shroud_r")):
        if prefix + "1" not in bones:
            continue
        near, far = values.get("robe", {}).get(key, (0.0, 0.0))
        set_axis_rotation(bones[prefix + "1"], near)
        set_axis_rotation(bones[prefix + "2"], far - near)
    for side in ("l", "r"):
        if f"crown_{side}" not in bones:
            continue
        pitch, yaw, roll = values.get("crown", {}).get(side, (0.0, 0.0, 0.0))
        set_world_rotation(bones[f"crown_{side}"], world_quaternion(pitch, yaw, roll))
        if f"crown_{side}2" in bones:
            set_world_rotation(bones[f"crown_{side}2"],
                               world_quaternion(pitch * 0.7, yaw * 0.5, roll * 0.8))
    # A barbed tail, where the mob has one: an absolute pitch per segment, so a
    # mob without tail bones (all three forest mobs) skips this untouched.
    if "tail_01" in bones:
        for index, angle in enumerate(values.get("tail", (0.0, 0.0, 0.0))):
            name = f"tail_0{index + 1}"
            if name in bones:
                set_axis_rotation(bones[name], float(angle))
    bpy.context.view_layer.update()
    if values.get("solve_feet", True):
        for side in ("l", "r"):
            y, lift, pitch = values.get("feet", {}).get(side, (0.0, 0.0, 0.0))
            ankle = Vector((float(JOINTS[f"foot_{side}"][0][0]),
                            float(JOINTS[f"foot_{side}"][0][1]) + y,
                            float(JOINTS[f"foot_{side}"][0][2]) + lift))
            solve_leg(rig, side, ankle, pitch, -0.30 * lift, pelvis_pitch)
    elif fold_legs:
        for side, (thigh, shin, foot, splay) in fold_legs.items():
            set_axis_rotation(rig.pose.bones[f"thigh_{side}"], thigh)
            set_axis_rotation(rig.pose.bones[f"shin_{side}"], shin)
            set_axis_rotation(rig.pose.bones[f"foot_{side}"], foot,
                              Vector((0.0, 1.0, 0.0)) * (1.0 if side == "l" else -1.0))
    bpy.context.view_layer.update()


def mesh_min_z(mesh_obj) -> float:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh_obj.evaluated_get(depsgraph)
    evaluated_mesh = evaluated.to_mesh()
    minimum = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated_mesh.vertices)
    evaluated.to_mesh_clear()
    return minimum


def bake_clip(mob: str, key: str, pose_function, ground: bool = False) -> bpy.types.Action:
    spec = styles.MOBS[mob]["clips"][key]
    duration = float(spec["duration"])
    name = styles.clip_name(mob, key)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    RIG.animation_data.action = action
    frames = int(round(duration * FPS))
    for frame in range(frames + 1):
        t = frame / FPS
        reset_pose(RIG)
        values = pose_function(t)
        fold = values.pop("leg_fold", None) if not values.get("solve_feet", True) else None
        apply_pose(mob, values, fold)
        if ground:
            # Keep the collapsing body on the floor: the authored pelvis drop
            # is corrected against the deformed mesh, never guessed.
            for _ in range(3):
                minimum = mesh_min_z(MESH)
                if minimum >= -0.002:
                    break
                values["pelvis_offset"] = values.get("pelvis_offset", Vector((0.0, 0.0, 0.0))) + Vector((0.0, 0.0, -minimum))
                apply_pose(mob, values, fold)
        for pb in RIG.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "pelvis":
                pb.keyframe_insert("location", frame=frame)
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                for fcurve in channelbag.fcurves:
                    for point in fcurve.keyframe_points:
                        point.interpolation = "LINEAR"
    action.use_frame_range = True
    action.frame_end = frames
    print("FOREST_CLIP", name, "frames", frames, "seconds", duration)
    return action


# ---------------------------------------------------------------------------
# Stalker and gallowsroot poses


def stalker_base() -> dict:
    values = warden_base()
    values["crouch"] = 0.0
    return values


def stalker_idle(t: float) -> dict:
    phase = (t / 2.4) % 1.0
    breath = math.sin(phase * math.tau)
    twitch = max(0.0, math.sin(phase * math.tau * 3.0) - 0.86) * 7.0
    values = stalker_base()
    values.update({
        "pelvis_offset": Vector((0.0, 0.01, -0.055 + 0.010 * breath)),
        "pelvis_pitch": 0.10,
        "pelvis_roll": 0.02 * math.sin(phase * math.tau + 0.4),
        "pelvis_yaw": 0.03 * math.sin(phase * math.tau * 0.5),
        "spine1": (0.05 + 0.014 * breath, 0.0, 0.0),
        "spine2": (0.06 + 0.016 * breath, 0.02 * math.sin(phase * math.tau + 0.7), 0.0),
        "chest_pose": (0.05 + 0.018 * breath, 0.03 * math.sin(phase * math.tau + 0.9), 0.0),
        "neck1": (-0.10, 0.03 * math.sin(phase * math.tau + 1.1), 0.0),
        "neck2": (-0.10, 0.03 * math.sin(phase * math.tau + 1.3), 0.0),
        "head_pose": (-0.06 + 0.02 * breath, 0.16 * math.sin(phase * math.tau * 0.5), 0.05 * math.sin(phase * math.tau * 0.5 + 0.4)),
        "jaw_open": 0.06 + 0.10 * twitch,
        "arm": {
            "l": (0.12 + 0.03 * math.sin(phase * math.tau + 0.5), 0.06, 0.16, 0.28 + 0.05 * math.sin(phase * math.tau), 0.10),
            "r": (0.10 + 0.03 * math.sin(phase * math.tau + 1.4), -0.06, 0.16, 0.24 + 0.05 * math.sin(phase * math.tau + 0.7), 0.10),
        },
        "finger": {"l": 0.55 + 0.25 * twitch, "r": 0.50 + 0.25 * twitch},
        "antler": (0.02 * breath, 0.02 * math.sin(phase * math.tau + 0.6), 0.0),
        "robe": {
            "f": (0.05, 0.07 * math.sin(phase * math.tau + 0.3)),
            "b": (0.03, 0.05 * math.sin(phase * math.tau + 0.9)),
            "l": (0.02, 0.04 * math.sin(phase * math.tau + 0.6)),
            "r": (0.02, 0.04 * math.sin(phase * math.tau + 1.2)),
        },
    })
    return values


def stalker_locomotion(t: float, key: str) -> dict:
    spec = styles.MOBS["ossuary_stalker"]
    duration = spec["clips"][key]["duration"]
    stride = spec["stride"][key]
    duty = spec["duty"][key]
    clearance = spec["foot_lift"][key]
    phase = (t / duration) % 1.0
    step = math.sin(phase * math.tau)
    double = math.cos(phase * math.tau * 2.0)
    run = 1.0 if key == "walk" else 1.6
    values = stalker_base()
    values.update({
        "pelvis_offset": Vector((0.0, 0.02 * run, -0.075 + 0.020 * double * run)),
        "pelvis_pitch": 0.14 + 0.06 * run,
        "pelvis_roll": 0.05 * step * run,
        "pelvis_yaw": 0.07 * step * run,
        "spine1": (0.05, -0.04 * step, -0.02 * step),
        "spine2": (0.06, -0.06 * step, -0.03 * step),
        "chest_pose": (0.05, -0.08 * step * run, 0.03 * step),
        "neck1": (-0.14 - 0.05 * run, 0.03 * step, 0.0),
        "neck2": (-0.12 - 0.05 * run, 0.03 * step, 0.0),
        "head_pose": (-0.10 - 0.04 * run, 0.05 * step, 0.0),
        "jaw_open": 0.08 + 0.10 * run,
        "arm": {
            "l": (0.14 + 0.36 * step * run, 0.05, 0.18, 0.42 * run, 0.14),
            "r": (0.12 - 0.36 * step * run, -0.05, 0.18, 0.38 * run, 0.14),
        },
        "finger": {"l": 0.7, "r": 0.7},
        "antler": (0.03 * double, 0.04 * step, 0.0),
        "robe": {
            "f": (0.14 * run + 0.10 * step, 0.24 * run + 0.14 * step),
            "b": (-0.10 * run, -0.16 * run),
            "l": (0.0, 0.10 * step), "r": (0.0, -0.10 * step),
        },
    })
    for side, offset in (("l", 0.0), ("r", 0.5)):
        y, lift, pitch = foot_target(phase, offset, duty, stride, clearance)
        values["feet"][side] = (y, lift, pitch)
    return values


def stalker_attack(t: float) -> dict:
    # Impact 0.55 s: the right claw crosses the body, the left braces.
    cock = keyed(t, [(0.0, 0.0), (0.12, 0.9), (0.30, 1.0), (0.44, 0.55), (0.55, 0.0), (0.80, 0.08), (1.25, 0.0)])
    slash = keyed(t, [(0.0, 0.0), (0.20, 0.0), (0.34, 0.25), (0.46, 0.70), (0.55, 1.0), (0.64, 0.85), (0.82, 0.30), (1.05, 0.06), (1.25, 0.0)])
    twist = keyed(t, [(0.0, 0.0), (0.16, 0.55), (0.34, 0.70), (0.48, 0.10), (0.55, -0.45), (0.70, -0.55), (0.95, -0.18), (1.25, 0.0)])
    hop = keyed(t, [(0.0, 0.0), (0.30, -0.02), (0.44, 0.06), (0.55, 0.12), (0.70, 0.06), (1.00, 0.0), (1.25, 0.0)])
    values = stalker_base()
    values.update({
        "pelvis_offset": Vector((0.0, hop, -0.055 - 0.03 * cock + 0.02 * slash)),
        "pelvis_pitch": 0.12 - 0.06 * cock + 0.14 * slash,
        "pelvis_roll": 0.04 * twist,
        "pelvis_yaw": 0.34 * twist,
        "spine1": (0.04, 0.14 * twist, 0.03 * twist),
        "spine2": (0.05, 0.16 * twist, 0.04 * twist),
        "chest_pose": (0.04, 0.22 * twist, 0.05 * twist),
        "neck1": (-0.12, -0.10 * twist, 0.0),
        "neck2": (-0.10, -0.08 * twist, 0.0),
        "head_pose": (-0.06, -0.20 * twist, 0.03 * twist),
        "jaw_open": 0.12 + 0.55 * cock * (1.0 - slash * 0.6),
        "arm": {
            "l": (-0.55 * cock + 0.20 * slash, 0.30 * cock, 0.30 + 0.20 * cock, 0.55 * cock + 0.30 * slash, 0.15),
            "r": (-1.15 * cock + 0.45 * slash, -0.55 * twist, 0.35 + 0.30 * cock, 0.75 * cock - 0.20 * slash, 0.20),
        },
        "finger": {"l": 1.2 - 0.4 * slash, "r": 1.35 - 0.9 * slash},
        "antler": (-0.12 * cock, 0.10 * twist, 0.0),
        "robe": {
            "f": (-0.10 * cock + 0.34 * slash, -0.16 * cock + 0.40 * slash),
            "b": (0.12 * cock - 0.24 * slash, 0.20 * cock - 0.28 * slash),
            "l": (0.0, 0.16 * slash), "r": (0.0, -0.16 * slash),
        },
    })
    for side, offset in (("l", 0.58), ("r", 0.32)):
        values["feet"][side] = (0.14 * slash, 0.02 * cock, 0.0)
    return values


def stalker_hit(t: float) -> dict:
    strike = keyed(t, [(0.0, 0.0), (0.09, 1.0), (0.26, 0.32), (0.40, 0.0)])
    values = stalker_base()
    values.update({
        "pelvis_offset": Vector((0.03 * strike, -0.06 * strike, -0.055 - 0.03 * strike)),
        "pelvis_pitch": 0.06 - 0.05 * strike,
        "pelvis_roll": 0.10 * strike,
        "pelvis_yaw": 0.12 * strike,
        "spine1": (-0.10 * strike, 0.08 * strike, 0.08 * strike),
        "spine2": (-0.14 * strike, 0.10 * strike, 0.10 * strike),
        "chest_pose": (-0.18 * strike, 0.12 * strike, 0.12 * strike),
        "neck1": (-0.22 * strike, 0.0, 0.10 * strike),
        "neck2": (-0.24 * strike, -0.05 * strike, 0.10 * strike),
        "head_pose": (-0.30 * strike, -0.10 * strike, 0.16 * strike),
        "jaw_open": 0.55 * strike,
        "arm": {
            "l": (-0.40 * strike, 0.10, 0.45 * strike, 0.35 * strike, 0.10),
            "r": (-0.35 * strike, -0.10, 0.40 * strike, 0.30 * strike, 0.10),
        },
        "finger": {"l": 1.1, "r": 1.1},
        "antler": (-0.18 * strike, 0.0, 0.0),
        "robe": {"f": (0.24 * strike, 0.32 * strike), "b": (-0.14 * strike, -0.20 * strike),
                 "l": (0.0, 0.0), "r": (0.0, 0.0)},
    })
    return values


def stalker_death(t: float) -> dict:
    duration = styles.MOBS["ossuary_stalker"]["clips"]["death"]["duration"]
    p = max(0.0, min(1.0, t / duration))
    buckle = smoothstep(0.0, 0.42, p)
    fall = smoothstep(0.32, 0.85, p)
    values = stalker_base()
    values["solve_feet"] = False
    values.update({
        "pelvis_offset": Vector((0.03 * fall, 0.06 * buckle, -0.40 * buckle - 0.22 * fall)),
        "pelvis_pitch": 0.20 * buckle + 0.35 * fall,
        "pelvis_roll": 0.20 * buckle + 0.75 * fall,
        "pelvis_yaw": 0.10 * fall,
        "spine1": (0.16 * buckle, 0.0, 0.10 * fall),
        "spine2": (0.20 * buckle, 0.0, 0.12 * fall),
        "chest_pose": (0.22 * buckle, 0.12 * fall, 0.14 * fall),
        "neck1": (-0.30 * buckle, 0.0, 0.0),
        "neck2": (-0.26 * buckle, 0.0, 0.0),
        "head_pose": (-0.30 * buckle + 0.30 * fall, 0.24 * fall, 0.10 * fall),
        "jaw_open": 0.45 * (1.0 - buckle) + 0.10,
        "arm": {
            "l": (0.45 * buckle, 0.10, 0.55 * buckle, 0.40 * buckle, 0.10),
            "r": (0.30 * buckle, -0.10, 0.70 * buckle, 0.30 * buckle, 0.10),
        },
        "finger": {"l": 0.6, "r": 0.8},
        "antler": (-0.24 * buckle, 0.12 * fall, 0.0),
        "robe": {"f": (0.30 * buckle, 0.42 * fall), "b": (-0.20 * buckle, -0.28 * fall),
                 "l": (0.10 * fall, 0.20 * fall), "r": (-0.10 * fall, -0.10 * fall)},
    })
    values["leg_fold"] = {
        "l": (1.25 * buckle, -1.05 * buckle, 0.65 * buckle, 0.15 * fall),
        "r": (1.05 * buckle, -0.90 * buckle, 0.55 * buckle, -0.20 * fall),
    }
    return values


def gallowsroot_base() -> dict:
    return {
        "pelvis_offset": Vector((0.0, 0.0, 0.0)),
        "pelvis_pitch": 0.0, "pelvis_roll": 0.0, "pelvis_yaw": 0.0,
        "spine1": (0.0, 0.0, 0.0), "spine2": (0.0, 0.0, 0.0), "chest_pose": (0.0, 0.0, 0.0),
        "neck1": (0.0, 0.0, 0.0), "head_pose": (0.0, 0.0, 0.0),
        "jaw_open": 0.0,
        "arm": {"l": (0.0, 0.0, 0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0, 0.0, 0.0)},
        "finger": {"l": 0.0, "r": 0.0},
        "crown": {"l": (0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0)},
        "feet": {"l": (0.0, 0.0, 0.0), "r": (0.0, 0.0, 0.0)},
        "solve_feet": True,
    }


def gallowsroot_idle(t: float) -> dict:
    phase = (t / 3.2) % 1.0
    creak = math.sin(phase * math.tau)
    slow = math.sin(phase * math.tau * 0.5)
    values = gallowsroot_base()
    values.update({
        "pelvis_offset": Vector((0.006 * slow, 0.0, 0.010 * creak)),
        "pelvis_pitch": 0.02 * creak,
        "pelvis_roll": 0.020 * slow,
        "pelvis_yaw": 0.020 * slow,
        "spine1": (0.020 * creak, 0.010 * slow, 0.0),
        "spine2": (0.024 * creak, 0.014 * slow, 0.0),
        "chest_pose": (0.028 * creak, 0.018 * slow, 0.0),
        "neck1": (-0.020 * creak, 0.02 * slow, 0.0),
        "head_pose": (0.030 * math.sin(phase * math.tau + 0.6), 0.09 * slow, 0.03 * slow),
        "jaw_open": 0.06 + 0.07 * max(0.0, math.sin(phase * math.tau * 1.5)),
        "arm": {
            "l": (0.06 + 0.05 * creak, 0.03 * slow, 0.03, 0.10, 0.05),
            "r": (0.05 - 0.05 * creak, -0.03 * slow, 0.03, 0.09, 0.05),
        },
        "finger": {"l": 0.30, "r": 0.30},
        "crown": {"l": (0.03 * creak, 0.04 * slow, 0.0), "r": (0.03 * creak, -0.04 * slow, 0.0)},
    })
    return values


def gallowsroot_locomotion(t: float, key: str) -> dict:
    spec = styles.MOBS["gallowsroot"]
    duration = spec["clips"][key]["duration"]
    stride = spec["stride"][key]
    duty = spec["duty"][key]
    clearance = spec["foot_lift"][key]
    phase = (t / duration) % 1.0
    step = math.sin(phase * math.tau)
    double = math.cos(phase * math.tau * 2.0)
    heavy = 1.0 if key == "walk" else 1.4
    values = gallowsroot_base()
    values.update({
        "pelvis_offset": Vector((0.0, 0.0, (0.030 * double - 0.020) * heavy)),
        "pelvis_pitch": 0.05 + 0.02 * heavy,
        "pelvis_roll": 0.075 * step * heavy,
        "pelvis_yaw": 0.045 * step * heavy,
        "spine1": (-0.02, -0.03 * step, -0.02 * step),
        "spine2": (-0.03, -0.04 * step, -0.03 * step),
        "chest_pose": (-0.04, -0.05 * step * heavy, 0.03 * step),
        "neck1": (0.02, 0.02 * step, 0.0),
        "head_pose": (0.05, 0.05 * step, 0.0),
        "jaw_open": 0.06,
        "arm": {
            "l": (0.10 + 0.20 * step * heavy, 0.04, 0.05, 0.18, 0.06),
            "r": (0.10 - 0.20 * step * heavy, -0.04, 0.05, 0.16, 0.06),
        },
        "finger": {"l": 0.35, "r": 0.35},
        "crown": {"l": (0.04 * double, 0.05 * step, 0.0), "r": (0.04 * double, -0.05 * step, 0.0)},
    })
    for side, offset in (("l", 0.0), ("r", 0.5)):
        y, lift, pitch = foot_target(phase, offset, duty, stride, clearance)
        values["feet"][side] = (y, lift, pitch)
    return values


def gallowsroot_attack(t: float) -> dict:
    # Impact 1.05 s: both branch arms rear back, then hammer down.
    rear = keyed(t, [(0.0, 0.0), (0.22, 0.75), (0.46, 1.0), (0.72, 1.0), (0.88, 0.55), (1.05, 0.10), (1.30, 0.25), (1.75, 0.06), (2.10, 0.0)])
    slam = keyed(t, [(0.0, 0.0), (0.70, 0.0), (0.82, 0.30), (0.94, 0.72), (1.05, 1.0), (1.16, 0.92), (1.36, 0.45), (1.70, 0.12), (2.10, 0.0)])
    lean = keyed(t, [(0.0, 0.0), (0.40, -0.10), (0.72, -0.14), (0.92, 0.10), (1.05, 0.22), (1.24, 0.16), (1.60, 0.05), (2.10, 0.0)])
    values = gallowsroot_base()
    values.update({
        "pelvis_offset": Vector((0.0, -0.05 * rear + 0.16 * slam, -0.06 * rear - 0.05 * slam)),
        "pelvis_pitch": -0.05 * rear + 0.14 * slam,
        "pelvis_roll": 0.0,
        "pelvis_yaw": 0.05 * rear - 0.05 * slam,
        "spine1": (lean * 0.5, 0.0, 0.0),
        "spine2": (lean * 0.6, 0.0, 0.0),
        "chest_pose": (lean * 0.7, 0.0, 0.0),
        "neck1": (-0.16 * rear + 0.10 * slam, 0.0, 0.0),
        "head_pose": (-0.22 * rear + 0.20 * slam, 0.0, 0.06 * slam),
        "jaw_open": 0.20 + 0.60 * rear * (1.0 - slam * 0.82),
        "arm": {
            "l": (-1.35 * rear + 1.85 * slam, 0.06, 0.10 - 0.10 * rear, 0.55 * rear - 0.40 * slam, 0.10),
            "r": (-1.40 * rear + 1.80 * slam, -0.06, 0.10 - 0.10 * rear, 0.50 * rear - 0.38 * slam, 0.10),
        },
        "finger": {"l": 1.1 - 0.5 * slam, "r": 1.1 - 0.5 * slam},
        "crown": {"l": (-0.16 * rear + 0.22 * slam, 0.0, 0.0), "r": (-0.16 * rear + 0.22 * slam, 0.0, 0.0)},
    })
    for side, offset in (("l", 0.55), ("r", 0.40)):
        values["feet"][side] = (0.05 * slam, 0.02 * rear, 0.0)
    return values


def gallowsroot_hit(t: float) -> dict:
    strike = keyed(t, [(0.0, 0.0), (0.12, 1.0), (0.36, 0.35), (0.60, 0.0)])
    values = gallowsroot_base()
    values.update({
        "pelvis_offset": Vector((0.02 * strike, -0.04 * strike, -0.03 * strike)),
        "pelvis_pitch": -0.08 * strike,
        "pelvis_roll": 0.10 * strike,
        "spine1": (-0.10 * strike, 0.04 * strike, 0.06 * strike),
        "spine2": (-0.12 * strike, 0.06 * strike, 0.08 * strike),
        "chest_pose": (-0.16 * strike, 0.08 * strike, 0.10 * strike),
        "neck1": (-0.14 * strike, 0.0, 0.06 * strike),
        "head_pose": (-0.24 * strike, -0.08 * strike, 0.14 * strike),
        "jaw_open": 0.50 * strike + 0.08,
        "arm": {
            "l": (-0.40 * strike, 0.10 * strike, 0.30 * strike, 0.45 * strike, 0.10),
            "r": (-0.34 * strike, -0.10 * strike, 0.28 * strike, 0.40 * strike, 0.10),
        },
        "finger": {"l": 0.9, "r": 0.9},
        "crown": {"l": (-0.16 * strike, 0.0, 0.10 * strike), "r": (-0.16 * strike, 0.0, -0.10 * strike)},
    })
    return values


def gallowsroot_death(t: float) -> dict:
    duration = styles.MOBS["gallowsroot"]["clips"]["death"]["duration"]
    p = max(0.0, min(1.0, t / duration))
    give = smoothstep(0.0, 0.35, p)
    topple = smoothstep(0.18, 0.82, p)
    settle = smoothstep(0.68, 1.0, p)
    values = gallowsroot_base()
    values["solve_feet"] = False
    values.update({
        "pelvis_offset": Vector((0.06 * topple, 0.10 * topple, -0.30 * give - 0.55 * topple)),
        "pelvis_pitch": 0.15 * give + 0.95 * topple,
        "pelvis_roll": 0.10 * give + 0.35 * topple,
        "pelvis_yaw": 0.05 * topple,
        "spine1": (0.10 * give + 0.15 * topple, 0.0, 0.0),
        "spine2": (0.12 * give + 0.18 * topple, 0.0, 0.0),
        "chest_pose": (0.12 * give + 0.16 * topple, 0.0, 0.0),
        "neck1": (-0.20 * give - 0.10 * topple, 0.0, 0.0),
        "head_pose": (-0.26 * give - 0.16 * topple, 0.12 * topple, 0.10 * topple),
        "jaw_open": 0.45 * (1.0 - topple) + 0.10,
        "arm": {
            "l": (0.30 * give + 0.35 * topple, 0.10 * topple, 0.45 * give, 0.30 * give, 0.10),
            "r": (0.24 * give + 0.30 * topple, -0.10 * topple, 0.40 * give, 0.26 * give, 0.10),
        },
        "finger": {"l": 0.5, "r": 0.6},
        "crown": {"l": (-0.20 * give - 0.10 * settle, 0.0, 0.0), "r": (-0.20 * give - 0.10 * settle, 0.0, 0.0)},
    })
    values["leg_fold"] = {
        "l": (1.0 * give, -0.75 * give, 0.45 * give, 0.10 * topple),
        "r": (0.92 * give, -0.70 * give, 0.42 * give, -0.12 * topple),
    }
    return values


CLIP_FUNCTIONS = {
    "hollow_warden": {
        "idle": warden_idle,
        "walk": lambda t: warden_locomotion(t, "walk"),
        "run": lambda t: warden_locomotion(t, "run"),
        "attack": warden_attack,
        "hit": warden_hit,
        "death": warden_death,
        "attack_slash": warden_attack_slash,
        "attack_stab": warden_attack_stab,
        "block": warden_block,
        "stagger": warden_stagger,
        "crouch": warden_crouch,
    },
    "ossuary_stalker": {
        "idle": stalker_idle,
        "walk": lambda t: stalker_locomotion(t, "walk"),
        "run": lambda t: stalker_locomotion(t, "run"),
        "attack": stalker_attack,
        "hit": stalker_hit,
        "death": stalker_death,
    },
    "gallowsroot": {
        "idle": gallowsroot_idle,
        "walk": lambda t: gallowsroot_locomotion(t, "walk"),
        "run": lambda t: gallowsroot_locomotion(t, "run"),
        "attack": gallowsroot_attack,
        "hit": gallowsroot_hit,
        "death": gallowsroot_death,
    },
}


def build_actions(mob: str) -> list[bpy.types.Action]:
    RIG.animation_data_create()
    RIG.animation_data.use_nla = False
    actions = []
    for key in styles.MOBS[mob]["clips"]:
        actions.append(bake_clip(mob, key, CLIP_FUNCTIONS[mob][key], ground=(key == "death")))
    return actions


# ---------------------------------------------------------------------------
# Export, metadata and captures


def setup_nla_and_export(actions: list[bpy.types.Action], output: Path) -> None:
    RIG.animation_data.action = None
    for track in list(RIG.animation_data.nla_tracks):
        RIG.animation_data.nla_tracks.remove(track)
    for action in actions:
        track = RIG.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.action_frame_start = 0
        strip.action_frame_end = action.frame_end
        track.mute = True
    reset_pose(RIG)
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


def write_metadata(mob: str, output: Path) -> dict:
    document, _raw = glb_document(output)
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
    # A sampled export writes a translation track for every joint, so the count
    # alone says nothing. What matters is whether the values move: a constant
    # track is harmless, a varying one would double the CharacterBody motion.
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
    spec = styles.MOBS[mob]
    clips = {}
    for key in spec["clips"]:
        name = styles.clip_name(mob, key)
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
        "mob": mob,
        "display": spec["display"],
        "skeleton": "ForestArmature/Skeleton3D",
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
            "Original procedural work authored by tools/prepare_forest_mobs.py from "
            "tools/forest_surface.py and tools/forest_styles.py; no third-party model, "
            "texture or motion. The supplied design sheet was inspiration only."
        ),
        "reproducer": "python tools/build_forest.py " + mob,
    }
    path = output.with_suffix(".json")
    path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("FOREST_METADATA", path)
    return metadata


def render_captures(mob: str, source: Path, actions: list[bpy.types.Action], metadata: dict) -> None:
    """Three passes: textured form, flat clay form, and a lit beauty frame.

    The workbench passes make folds and silhouette legible; the Cycles pass is
    the only one that shows what the PBR maps actually look like, which is what
    art review needs. Everything lands in ignored storage.
    """
    scene = bpy.context.scene
    capture_dir = source / "captures"
    capture_dir.mkdir(parents=True, exist_ok=True)
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1000
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("ForestPreviewWorld")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.045, 0.055, 0.050, 1.0)
    background.inputs["Strength"].default_value = 1.0
    scene.world = world
    # Frame from the measured rest bounds so every mob fills its captures.
    lowest = float(metadata["rest_bounds_min"][1])
    highest = float(metadata["rest_bounds_max"][1])
    middle = (lowest + highest) * 0.5
    span = max(0.8, highest - lowest)
    ortho = span * 1.10
    distance = span * 1.9 + 2.2
    head_z = (JOINTS["head"][0][2] + JOINTS["head"][1][2]) * 0.5
    camera_specs = {
        "front": ((0.0, distance, middle), (0.0, 0.0, middle), ortho),
        "side": ((distance, 0.0, middle), (0.0, 0.0, middle), ortho),
        # The mobs face +Y, so a three-quarter and a close-up both have to sit
        # on the +Y side or they photograph the back of the wardrobe.
        "threeq": ((distance * 0.66, distance * 0.74, middle + span * 0.10),
                   (0.0, 0.0, middle), ortho * 1.06),
        "closeup": ((span * 0.34, span * 0.52, head_z + span * 0.05),
                    (0.0, 0.0, head_z), span * 0.34),
    }
    cameras = {}
    for name, (location, target, scale) in camera_specs.items():
        data = bpy.data.cameras.new(name)
        data.type = "ORTHO"
        data.ortho_scale = scale
        camera = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(camera)
        camera.location = location
        camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        cameras[name] = camera
    bpy.ops.mesh.primitive_plane_add(size=16.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground_mat = bpy.data.materials.new("PreviewGround")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.055, 0.062, 0.052, 1.0)
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.94
    ground.data.materials.append(ground_mat)

    # Three-point rig scaled to the subject; a 3.6 m tree needs more light than
    # a 1.2 m skeleton for the same exposure. Values are deliberately low so a
    # near-black wardrobe still shows its weave instead of blowing out.
    scale = span / 2.4
    key = _add_area_light("PreviewKey", Vector((2.8, -3.4, 3.1)) * scale,
                          (1.0, 0.93, 0.84), 520.0 * scale * scale, 2.4 * scale)
    fill = _add_area_light("PreviewFill", Vector((-3.4, -2.4, 1.5)) * scale,
                           (0.58, 0.70, 0.92), 130.0 * scale * scale, 3.0 * scale)
    rim = _add_area_light("PreviewRim", Vector((-1.3, -3.4, 3.0)) * scale,
                          (1.0, 0.52, 0.32), 260.0 * scale * scale, 2.0 * scale)
    for light in (key, fill, rim):
        light.data.shape = "DISK"

    preview_set = {
        "idle": [(0.0, "front"), (0.0, "side"), (0.0, "threeq"), (0.0, "closeup")],
        "walk": [(0.25, "side"), (0.55, "side"), (0.85, "side"), (0.25, "threeq")],
        "run": [(0.20, "side"), (0.45, "side"), (0.70, "threeq")],
        "attack": [(0.35, "threeq"), (0.62, "threeq"), (0.86, "threeq")],
        "attack_slash": [(0.28, "front"), (0.50, "threeq"), (0.66, "threeq")],
        "attack_stab": [(0.28, "side"), (0.50, "threeq"), (0.78, "side")],
        "block": [(0.30, "front"), (0.30, "threeq")],
        "stagger": [(0.12, "threeq"), (0.34, "side")],
        "crouch": [(0.60, "side"), (0.60, "threeq")],
        "hit": [(0.12, "threeq"), (0.30, "threeq")],
        "death": [(0.40, "threeq"), (0.80, "threeq"), (1.20, "side")],
    }
    form_set = {"idle": [(0.0, "front"), (0.0, "threeq")],
                "attack": [(0.62, "threeq")],
                "attack_slash": [(0.66, "threeq")],
                "block": [(0.30, "front")],
                "crouch": [(0.60, "side")],
                "death": [(1.20, "side")]}
    beauty_set = {"idle": [(0.0, "threeq"), (0.0, "closeup")]}

    def render_frames(keys: dict, suffix: str, engine: str) -> None:
        scene.render.engine = engine
        if engine == "BLENDER_WORKBENCH":
            scene.display.shading.light = "STUDIO"
            scene.display.shading.show_shadows = True
            scene.display.shading.show_cavity = True
            scene.display.shading.cavity_type = "BOTH"
            scene.display.shading.show_specular_highlight = False
        else:
            scene.cycles.device = "CPU"
            scene.cycles.samples = 32
            scene.cycles.use_denoising = True
            scene.cycles.max_bounces = 4
            scene.render.film_transparent = False
        for action in actions:
            key = next((k for k in CLIP_FUNCTIONS[mob] if styles.clip_name(mob, k) == action.name), None)
            if key is None or key not in keys:
                continue
            RIG.animation_data.action = action
            if action.slots:
                RIG.animation_data.action_slot = action.slots[0]
            for index, (time, view) in enumerate(keys[key]):
                duration = float(styles.MOBS[mob]["clips"][key]["duration"])
                frame = int(round(min(time, duration * 0.98) * FPS))
                scene.frame_set(frame)
                scene.camera = cameras[view]
                scene.render.filepath = str(
                    capture_dir / f"{key}_{index:02d}_{time:.2f}s_{view}{suffix}.png"
                )
                bpy.ops.render.render(write_still=True)

    scene.display.shading.color_type = "TEXTURE"
    render_frames(preview_set, "", "BLENDER_WORKBENCH")
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (0.62, 0.62, 0.62)
    render_frames(form_set, "_form", "BLENDER_WORKBENCH")
    scene.view_settings.view_transform = "Standard"
    render_frames(beauty_set, "_lit", "CYCLES")
    RIG.animation_data.action = None
    print("FOREST_CAPTURES", capture_dir)


def _add_area_light(name: str, location: Vector, colour, energy: float, size: float):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    data.color = colour
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector((0.0, 0.0, 1.4)) - location).to_track_quat("-Z", "Y").to_euler()
    return light


def main() -> None:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    flags = {item for item in argv if item.startswith("--")}
    arguments = [item for item in argv if not item.startswith("--")]
    mob = arguments[0] if arguments else "hollow_warden"
    if mob not in styles.MOBS:
        raise SystemExit(f"unknown mob {mob}")
    output = Path(arguments[1]).resolve() if len(arguments) > 1 else styles.asset_path(mob)
    source = styles.mob_dir(mob)
    source.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)

    global JOINTS, PARENTS, DEFORM, RIG, MESH
    JOINTS, PARENTS, assembler = ASSEMBLERS[mob]
    DEFORM = list(JOINTS.keys())

    reset_scene()
    print("FOREST_BEGIN", mob, source, output)
    RIG = build_armature()
    mesh = assembler()
    MESH = mesh
    skin_to_rig(mesh, RIG)
    triangles = sum(len(polygon.vertices) - 2 for polygon in mesh.data.polygons)
    print("FOREST_TRIS", triangles, "bones", len(DEFORM))
    unwrap_per_material(mesh)
    bake_materials(mesh, mob, source / "textures")
    actions = build_actions(mob)
    setup_nla_and_export(actions, output)
    metadata = write_metadata(mob, output)
    # Captures are a review pass, not part of the asset: a rebuild that only
    # needs the GLB and its JSON skips the render stage with --no-captures.
    if "--no-captures" not in flags:
        render_captures(mob, source, actions, metadata)
    bpy.ops.wm.save_as_mainfile(filepath=str(source / f"ironwood_{mob}_source.blend"))
    print("FOREST_DONE", json.dumps({
        "mob": mob,
        "triangles": metadata["mesh_triangles"],
        "bones": metadata["bone_count"],
        "images": metadata["embedded_images"],
        "clips": {k: v["duration"] for k, v in metadata["clips"].items()},
    }, indent=2))


if __name__ == "__main__":
    main()
