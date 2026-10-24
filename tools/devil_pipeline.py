"""Shared deterministic authoring pipeline for the Ironwood devil mobs.

Blender 5.1, Python 3.11. Every delivered surface is authored here: continuous
metaball anatomy, rigid detail meshes, a packed PBR atlas (albedo, tangent
normal, roughness, metallic, emission), a deform skeleton, procedural foot
contact and baked 60 Hz clips. No third-party model, texture or motion is used.

Coordinates: metres, Blender Z-up, creature facing +Y. glTF export is Y-up, so
+Y Blender becomes -Z in Godot, matching the gameplay forward axis.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path
from typing import Callable, Iterable

import numpy as np

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
FPS = 60
TAU = math.tau

# ---------------------------------------------------------------------------
# Colour and deterministic noise


def hex_lin(value: str) -> tuple[float, float, float]:
    """sRGB hex -> linear scene colour (Blender shader inputs)."""
    value = value.lstrip("#")
    srgb = tuple(int(value[index:index + 2], 16) / 255.0 for index in (0, 2, 4))
    return tuple(_srgb_to_linear(channel) for channel in srgb)


def _srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def linear_to_srgb(image: np.ndarray) -> np.ndarray:
    image = np.clip(image, 0.0, 1.0)
    return np.where(image <= 0.0031308, image * 12.92,
                    1.055 * np.power(image, 1.0 / 2.4) - 0.055)


def srgb_array(rgb) -> np.ndarray:
    if isinstance(rgb, str):
        value = rgb.lstrip("#")
        rgb = tuple(int(value[index:index + 2], 16) / 255.0 for index in (0, 2, 4))
    return np.array([_srgb_to_linear(float(c)) for c in rgb], dtype=np.float32)


def fract(value: np.ndarray) -> np.ndarray:
    return value - np.floor(value)


def hash01(x: np.ndarray, y: np.ndarray, z: np.ndarray, seed: int) -> np.ndarray:
    h = np.sin(x * 127.1 + y * 311.7 + z * 74.7 + seed * 19.19) * 43758.5453123
    return fract(h)


def value_noise(points: np.ndarray, scale: float, seed: int) -> np.ndarray:
    """Trilinear value noise in rest space; suitable for seamless UV islands."""
    q = points * scale
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    ix, iy, iz = i[:, 0], i[:, 1], i[:, 2]
    fx, fy, fz = f[:, 0], f[:, 1], f[:, 2]
    out = np.zeros(len(points), dtype=np.float32)
    for dx in (0, 1):
        wx = fx if dx else 1.0 - fx
        for dy in (0, 1):
            wy = fy if dy else 1.0 - fy
            for dz in (0, 1):
                wz = fz if dz else 1.0 - fz
                out += wx * wy * wz * hash01(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(points: np.ndarray, scale: float, seed: int, octaves: int = 4,
        gain: float = 0.5, lacunarity: float = 2.03) -> np.ndarray:
    total = np.zeros(len(points), dtype=np.float32)
    amplitude = 1.0
    norm = 0.0
    frequency = scale
    for octave in range(octaves):
        total += value_noise(points, frequency, seed + octave * 17) * amplitude
        norm += amplitude
        amplitude *= gain
        frequency *= lacunarity
    return total / max(norm, 1e-6)


def ridged(points: np.ndarray, scale: float, seed: int, octaves: int = 3) -> np.ndarray:
    value = fbm(points, scale, seed, octaves)
    return 1.0 - np.abs(value * 2.0 - 1.0)


def smoothstep(edge0: float, edge1: float, value):
    if edge1 == edge0:
        return 1.0 if np.asarray(value) >= edge0 else 0.0
    t = np.clip((np.asarray(value, dtype=np.float32) - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def keyed(t: float, keys: list[tuple[float, float]]) -> float:
    if t <= keys[0][0]:
        return keys[0][1]
    for index in range(1, len(keys)):
        t0, v0 = keys[index - 1]
        t1, v1 = keys[index]
        if t <= t1:
            return v0 + (v1 - v0) * float(smoothstep(t0, t1, t))
    return keys[-1][1]


# ---------------------------------------------------------------------------
# Scene and materials


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


def make_tag_material(name: str):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (0.5, 0.5, 0.5, 1.0)
    return material


# ---------------------------------------------------------------------------
# Geometry primitives


def add_ellipsoid(mb, centre: Iterable[float], half: Iterable[float],
                  rotation: Quaternion | None = None, stiffness: float = 2.0):
    element = mb.elements.new(type="ELLIPSOID")
    element.co = Vector(centre)
    element.radius = 1.0 / 0.5735
    element.size_x, element.size_y, element.size_z = half
    element.stiffness = stiffness
    if rotation is not None:
        element.rotation = rotation
    return element


def add_segment(mb, a: Iterable[float], b: Iterable[float], radius: float,
                bulge: float = 1.0, stiffness: float = 2.0):
    a, b = Vector(a), Vector(b)
    direction = b - a
    length = direction.length
    rotation = Vector((0.0, 1.0, 0.0)).rotation_difference(direction.normalized())
    return add_ellipsoid(mb, (a + b) * 0.5,
                         (radius, length * 0.5 + radius * 0.35, radius * bulge),
                         rotation, stiffness)


def build_metaball(name: str, resolution: float, threshold: float,
                   builder: Callable, decimate_ratio: float = 0.5,
                   smoothing: int = 1):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = threshold
    obj = bpy.data.objects.new(name, mb)
    bpy.context.collection.objects.link(obj)
    builder(mb)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name
    bpy.ops.object.shade_smooth()
    if smoothing:
        for _ in range(smoothing):
            modifier = obj.modifiers.new("Smooth", "SMOOTH")
            modifier.iterations = 2
            modifier.factor = 0.35
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    if decimate_ratio < 0.999:
        modifier = obj.modifiers.new("Decimate", "DECIMATE")
        modifier.ratio = decimate_ratio
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    triangle_count = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
    print("DEVIL_TRIS", name, triangle_count)
    return obj


def _mesh_object(name: str, vertices: list[Vector], faces: list[tuple[int, ...]]):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in vertices], [], faces)
    mesh.validate()
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _tube_frames(points: list[Vector]) -> list[tuple[Vector, Vector, Vector]]:
    frames = []
    for index, point in enumerate(points):
        if index == 0:
            tangent = (points[1] - point).normalized()
        elif index == len(points) - 1:
            tangent = (point - points[-2]).normalized()
        else:
            tangent = (points[index + 1] - points[index - 1]).normalized()
        reference = Vector((0.0, 0.0, 1.0))
        if abs(tangent.dot(reference)) > 0.94:
            reference = Vector((0.0, 1.0, 0.0))
        side = tangent.cross(reference).normalized()
        up = side.cross(tangent).normalized()
        frames.append((tangent, side, up))
    return frames


def make_tube(name: str, points: Iterable[Iterable[float]], radii: Iterable[float],
              sides: int = 8, cap: bool = True):
    pts = [Vector(p) for p in points]
    rds = [float(r) for r in radii]
    frames = _tube_frames(pts)
    vertices: list[Vector] = []
    for point, radius, (_, side, up) in zip(pts, rds, frames):
        for index in range(sides):
            angle = TAU * index / sides
            vertices.append(point + (side * math.cos(angle) + up * math.sin(angle)) * radius)
    faces = []
    for ring in range(len(pts) - 1):
        for index in range(sides):
            a = ring * sides + index
            b = ring * sides + (index + 1) % sides
            c = (ring + 1) * sides + (index + 1) % sides
            d = (ring + 1) * sides + index
            faces.append((a, b, c, d))
    if cap:
        faces.append(tuple(range(sides - 1, -1, -1)))
        base = (len(pts) - 1) * sides
        faces.append(tuple(base + index for index in range(sides)))
    return _mesh_object(name, vertices, faces)


def make_cone(name: str, base: Iterable[float], tip: Iterable[float], radius: float,
              sides: int = 8):
    return make_tube(name, [base, tip], [radius, max(radius * 0.06, 1e-4)], sides)


def make_uv_sphere(name: str, centre: Iterable[float], radius: float,
                   scale: Iterable[float] = (1.0, 1.0, 1.0),
                   segments: int = 24, rings: int = 16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=radius, location=Vector(centre))
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(scale)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    return obj


def make_box(name: str, centre: Iterable[float], size: Iterable[float],
             rotation: Iterable[float] | None = None, bevel: float = 0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=Vector(centre))
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation is not None:
        obj.rotation_euler = Vector(rotation)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.shade_smooth()
    return obj


def make_membrane(name: str, grid: list[list[Iterable[float]]], thickness: float = 0.012):
    """A curved two-sided membrane from a rectangular grid of points."""
    rows = len(grid)
    cols = len(grid[0])
    vertices = [Vector(point) for row in grid for point in row]
    faces = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            b = a + 1
            c = a + cols + 1
            d = a + cols
            faces.append((a, b, c, d))
    obj = _mesh_object(name, vertices, faces)
    modifier = obj.modifiers.new("Solidify", "SOLIDIFY")
    modifier.thickness = thickness
    modifier.offset = 0.0
    # Apply on this object explicitly; build_parts() usually leaves another
    # primitive active, and bpy.ops.object.modifier_apply targets the active
    # object, which previously left every membrane a single sheet.
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.shade_smooth()
    return obj


def make_clump_field(name: str, samples: list[dict], seed: int,
                     sides: int = 5, segments: int = 3):
    """Merge many tapered fur/hair clumps into one mesh object.

    Each sample: {"point": Vector, "normal": Vector, "length": float,
                  "radius": float, "bend": Vector}
    """
    rng = np.random.default_rng(seed)
    vertices: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    for sample in samples:
        point = Vector(sample["point"])
        normal = Vector(sample["normal"]).normalized()
        length = float(sample["length"])
        radius = float(sample["radius"])
        bend = Vector(sample.get("bend", (0.0, 0.0, 0.0)))
        sway = Vector((rng.normal(), rng.normal(), rng.normal())) * radius * 3.0
        pts = []
        for step in range(segments + 1):
            t = step / segments
            centre = (point + normal * (length * t)
                      + bend * (length * t * t) + sway * (t * t))
            pts.append(centre)
        radii = [radius * (1.0 - 0.94 * (step / segments) ** 1.35) for step in range(segments + 1)]
        frames = _tube_frames(pts)
        local_start = len(vertices)
        for ring, (centre, ring_radius, (_, side, up)) in enumerate(zip(pts, radii, frames)):
            for index in range(sides):
                angle = TAU * index / sides
                vertices.append(centre + (side * math.cos(angle) + up * math.sin(angle)) * ring_radius)
        for ring in range(segments):
            for index in range(sides):
                a = local_start + ring * sides + index
                b = local_start + ring * sides + (index + 1) % sides
                c = local_start + (ring + 1) * sides + (index + 1) % sides
                d = local_start + (ring + 1) * sides + index
                faces.append((a, b, c, d))
    return _mesh_object(name, vertices, faces)


# ---------------------------------------------------------------------------
# Skeleton, weights and mesh finalisation


def part(obj, tag: str, rigid: str | None = None):
    return {"object": obj, "tag": tag, "rigid": rigid, "weights": "rigid" if rigid else "envelope"}


def _bone_segments(spec: dict) -> dict[str, tuple[Vector, Vector]]:
    return {name: (Vector(data["head"]), Vector(data["tail"]))
            for name, data in spec["bones"].items()}


def point_segment_distance(point: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    denom = ab.length_squared
    if denom <= 1e-12:
        return (point - a).length
    t = max(0.0, min(1.0, (point - a).dot(ab) / denom))
    return (point - (a + ab * t)).length


def build_rig(spec: dict):
    armature = bpy.data.armatures.new(spec["scene"] + "Armature")
    rig = bpy.data.objects.new(spec["scene"] + "Armature", armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = armature.edit_bones
    for name, data in spec["bones"].items():
        bone = edit_bones.new(name)
        bone.head = Vector(data["head"])
        bone.tail = Vector(data["tail"])
        bone.use_deform = bool(data.get("deform", name != "root"))
        bone.roll = float(data.get("roll", 0.0))
    for name, data in spec["bones"].items():
        parent = data.get("parent")
        if parent:
            edit_bones[name].parent = edit_bones[parent]
            edit_bones[name].use_connect = bool(data.get("connect", False))
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.display_type = "STICK"
    return rig


def assign_envelope(obj, rig, skin_map: dict[str, tuple[float, float]],
                    smooth_iterations: int = 2) -> None:
    segments = {name: (rig.data.bones[name].head_local.copy(), rig.data.bones[name].tail_local.copy())
                for name in skin_map}
    groups = {name: obj.vertex_groups.new(name=name) for name in skin_map}
    raw_weights: list[dict[str, float]] = []
    for vertex in obj.data.vertices:
        point = vertex.co
        candidate: dict[str, float] = {}
        for name, (radius, priority) in skin_map.items():
            a, b = segments[name]
            distance = point_segment_distance(point, a, b)
            if distance < radius:
                falloff = (1.0 - (distance / radius) ** 2) ** 2
                if falloff > 0.0005:
                    candidate[name] = falloff * priority
        if not candidate:
            nearest = min(skin_map, key=lambda n: point_segment_distance(point, *segments[n]))
            candidate[nearest] = 1.0
        raw_weights.append(candidate)
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


def rigid_weight(obj, bone: str) -> None:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def join_parts(parts: list[dict], mesh_name: str):
    objects = []
    for entry in parts:
        obj = entry["object"]
        obj.data.materials.clear()
        obj.data.materials.append(bpy.data.materials[entry["tag"]])
        objects.append(obj)
    target = objects[0]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = mesh_name
    mesh.data.name = mesh_name
    return mesh


def apply_displacement(mesh, field: Callable[[np.ndarray], np.ndarray], amount: float) -> None:
    normals = np.zeros((len(mesh.data.vertices), 3), dtype=np.float32)
    mesh.data.vertices.foreach_get("normal", normals.ravel())
    positions = np.zeros((len(mesh.data.vertices), 3), dtype=np.float32)
    mesh.data.vertices.foreach_get("co", positions.ravel())
    offsets = field(positions)
    for index, offset in enumerate(offsets):
        mesh.data.vertices[index].co += Vector(normals[index]) * float(offset * amount)
    mesh.data.update()


def unwrap(mesh) -> float:
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    # Joining objects that already carried primitive UVs creates several UV
    # layers; smart project writes to the active one, so start from a clean
    # single layer or the measured/baked atlas reads the wrong coordinates.
    for layer in list(mesh.data.uv_layers):
        mesh.data.uv_layers.remove(layer)
    mesh.data.uv_layers.new(name="UVMap")
    mesh.data.uv_layers.active_index = 0
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(88.0), island_margin=0.0006,
                             scale_to_bounds=True)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=0.0006)
    bpy.ops.object.mode_set(mode="OBJECT")
    mesh.data.uv_layers[0].name = "UVMap"
    uv_data = mesh.data.uv_layers.active.data
    uv_area = 0.0
    for polygon in mesh.data.polygons:
        points = [uv_data[index].uv for index in polygon.loop_indices]
        for index in range(1, len(points) - 1):
            a, b, c = points[0], points[index], points[index + 1]
            uv_area += abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) * 0.5
    print("DEVIL_UV_AREA", round(uv_area, 4))
    if not 0.03 < uv_area < 1.5:
        raise RuntimeError(f"UV atlas is not packed (area {uv_area:.3f})")
    return uv_area


def vertex_cavity(mesh) -> np.ndarray:
    normals = np.zeros((len(mesh.data.vertices), 3), dtype=np.float32)
    mesh.data.vertices.foreach_get("normal", normals.ravel())
    points = np.zeros((len(mesh.data.vertices), 3), dtype=np.float32)
    mesh.data.vertices.foreach_get("co", points.ravel())
    adjacency = [[] for _ in range(len(mesh.data.vertices))]
    for edge in mesh.data.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    cavity = np.zeros(len(mesh.data.vertices), dtype=np.float32)
    for index, neighbours in enumerate(adjacency):
        if not neighbours:
            continue
        direction = points[neighbours] - points[index]
        lengths = np.linalg.norm(direction, axis=1, keepdims=True)
        direction = direction / np.maximum(lengths, 1e-7)
        cavity[index] = np.maximum(0.0, float(np.mean(np.sum(direction * normals[index], axis=1))))
    for _ in range(2):
        smoothed = cavity.copy()
        for index, neighbours in enumerate(adjacency):
            if neighbours:
                smoothed[index] = cavity[index] * 0.6 + float(np.mean(cavity[neighbours])) * 0.4
        cavity = smoothed
    return np.clip(cavity, 0.0, 1.0)


def finish_mesh(parts: list[dict], rig, spec: dict):
    mesh = join_parts(parts, spec["scene"] + "Mesh")
    # Blender's join merges material slots by material identity. Capture the
    # resulting slot names before compacting the list, then remap each polygon
    # by name so no face loses its surface tag.
    old_slots = [slot.name for slot in mesh.data.materials]
    polygon_tags = [old_slots[polygon.material_index] if old_slots else "body"
                    for polygon in mesh.data.polygons]
    mesh.data.materials.clear()
    unique_tags = list(dict.fromkeys(polygon_tags))
    for tag in unique_tags:
        mesh.data.materials.append(bpy.data.materials[tag])
    slot_of = {tag: index for index, tag in enumerate(unique_tags)}
    for polygon, tag in zip(mesh.data.polygons, polygon_tags):
        polygon.material_index = slot_of[tag]
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.ops.object.shade_smooth()
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    mesh.parent = rig
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    return mesh


# ---------------------------------------------------------------------------
# PBR atlas: albedo, tangent normal, roughness, metallic, emission
#
# The atlas is painted in rest space from the actual triangle positions, so a
# UV island never samples a neighbouring material. Normals come from the
# painted height field converted through each triangle's UV scale, which keeps
# detail consistent across automatically packed islands.


def _dilate(image: np.ndarray, coverage: np.ndarray, iterations: int = 8) -> np.ndarray:
    height, width = coverage.shape
    image = image.copy()
    coverage = coverage.copy()
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
        if not np.any(fill):
            break
        image[fill] = neighbour_sum[fill] / neighbour_count[fill][:, None]
        coverage[fill] = True
    return image


def _block_downsample(image: np.ndarray, factor: int) -> np.ndarray:
    if factor <= 1:
        return image
    height, width = image.shape[0], image.shape[1]
    channels = image.shape[2] if image.ndim == 3 else None
    out_h, out_w = height // factor, width // factor
    trimmed = image[:out_h * factor, :out_w * factor]
    if channels is None:
        return trimmed.reshape(out_h, factor, out_w, factor).mean(axis=(1, 3))
    return trimmed.reshape(out_h, factor, out_w, factor, channels).mean(axis=(1, 3))


def _make_image(name: str, size: int, pixels: np.ndarray, colorspace: str,
                path: Path) -> bpy.types.Image:
    rgba = np.ones((size, size, 4), dtype=np.float32)
    if pixels.ndim == 2:
        rgba[..., 0] = pixels
        rgba[..., 1] = pixels
        rgba[..., 2] = pixels
    else:
        rgba[..., :3] = pixels
    image = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    image.colorspace_settings.name = colorspace
    image.file_format = "PNG"
    image.pixels.foreach_set(rgba.ravel())
    image.update()
    image.pack()
    image.filepath_raw = str(path)
    try:
        image.save()
    except Exception as exc:  # noqa: BLE001 - evidence saving is best-effort
        print("DEVIL_IMAGE_SAVE_SKIPPED", path.name, exc)
    return image


def paint_textures(mesh, spec: dict, source_dir: Path):
    from math import sqrt

    size = int(spec.get("texture_size", 1024))
    palette = spec["palette"]
    classify: Callable = spec.get("classify")
    pixels = size * size
    colour = np.zeros((pixels, 3), dtype=np.float32)
    height = np.zeros(pixels, dtype=np.float32)
    roughness = np.zeros(pixels, dtype=np.float32)
    metallic = np.zeros(pixels, dtype=np.float32)
    emission = np.zeros((pixels, 3), dtype=np.float32)
    texel_scale = np.full(pixels, 0.0005, dtype=np.float32)
    cavity_map = np.zeros(pixels, dtype=np.float32)
    counts = np.zeros(pixels, dtype=np.uint16)
    tag_ids = np.full(pixels, -1, dtype=np.int16)
    tag_names: list[str] = []

    def tag_id(name: str) -> int:
        if name not in tag_names:
            tag_names.append(name)
        return tag_names.index(name)

    positions = np.zeros((len(mesh.data.vertices), 3), dtype=np.float32)
    mesh.data.vertices.foreach_get("co", positions.ravel())
    normals = np.zeros((len(mesh.data.vertices), 3), dtype=np.float32)
    mesh.data.vertices.foreach_get("normal", normals.ravel())
    cavity = vertex_cavity(mesh)
    uv_layer = mesh.data.uv_layers.active.data
    uvs = np.array([[entry.uv[0], entry.uv[1]] for entry in uv_layer], dtype=np.float32)
    tags_by_slot = [material.name for material in mesh.data.materials]

    covered_triangles = 0
    for polygon in mesh.data.polygons:
        loop_indices = list(polygon.loop_indices)
        slot_tag = tags_by_slot[polygon.material_index] if tags_by_slot else "body"
        for corner in range(1, len(loop_indices) - 1):
            li0, li1, li2 = loop_indices[0], loop_indices[corner], loop_indices[corner + 1]
            vi0 = mesh.data.loops[li0].vertex_index
            vi1 = mesh.data.loops[li1].vertex_index
            vi2 = mesh.data.loops[li2].vertex_index
            u0, v0 = uvs[li0]
            u1, v1 = uvs[li1]
            u2, v2 = uvs[li2]
            xmin = max(0, int(math.floor(min(u0, u1, u2) * size)) - 1)
            xmax = min(size - 1, int(math.ceil(max(u0, u1, u2) * size)) + 1)
            ymin = max(0, int(math.floor(min(v0, v1, v2) * size)) - 1)
            ymax = min(size - 1, int(math.ceil(max(v0, v1, v2) * size)) + 1)
            if xmax < xmin or ymax < ymin:
                continue
            denominator = (v1 - v2) * (u0 - u2) + (u2 - u1) * (v0 - v2)
            if abs(float(denominator)) < 1e-11:
                continue
            xs = (np.arange(xmin, xmax + 1, dtype=np.float32) + 0.5) / size
            ys = (np.arange(ymin, ymax + 1, dtype=np.float32) + 0.5) / size
            px, py = np.meshgrid(xs, ys)
            wa = ((v1 - v2) * (px - u2) + (u2 - u1) * (py - v2)) / denominator
            wb = ((v2 - v0) * (px - u2) + (u0 - u2) * (py - v2)) / denominator
            wc = 1.0 - wa - wb
            inside = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6)
            if not np.any(inside):
                continue
            iy, ix = np.nonzero(inside)
            wa = wa[iy, ix][:, None]
            wb = wb[iy, ix][:, None]
            wc = wc[iy, ix][:, None]
            p0, p1, p2 = positions[vi0], positions[vi1], positions[vi2]
            n0, n1, n2 = normals[vi0], normals[vi1], normals[vi2]
            P = p0 * wa + p1 * wb + p2 * wc
            N = n0 * wa + n1 * wb + n2 * wc
            N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-7)
            cav = (cavity[vi0] * wa[:, 0] + cavity[vi1] * wb[:, 0] + cavity[vi2] * wc[:, 0])
            area3d = np.linalg.norm(np.cross(p1 - p0, p2 - p0)) * 0.5
            area_uv = abs((u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)) * 0.5
            scale = sqrt(max(area3d, 1e-12) / max(area_uv, 1e-12))
            if slot_tag == "body" and classify is not None:
                tags = classify(P, N)
            else:
                tags = np.full(len(P), slot_tag, dtype=object)
            flats = (iy + ymin) * size + (ix + xmin)
            for group_tag in np.unique(tags):
                mask = tags == group_tag
                if not np.any(mask):
                    continue
                result = paint_surface(str(group_tag), P[mask], N[mask], spec, cav[mask])
                target = flats[mask]
                count = counts[target].astype(np.float32)
                blend = 1.0 / (count + 1.0)
                colour[target] = colour[target] * (1.0 - blend[:, None]) + result["colour"] * blend[:, None]
                emission[target] = emission[target] * (1.0 - blend[:, None]) + result["emission"] * blend[:, None]
                height[target] = height[target] * (1.0 - blend) + result["height"] * blend
                roughness[target] = roughness[target] * (1.0 - blend) + result["roughness"] * blend
                metallic[target] = metallic[target] * (1.0 - blend) + result["metallic"] * blend
                texel_scale[target] = texel_scale[target] * (1.0 - blend) + scale * blend
                cavity_map[target] = cavity_map[target] * (1.0 - blend) + cav[mask] * blend
                tag_ids[target] = tag_id(str(group_tag))
                counts[target] += 1
            covered_triangles += 1

    print("DEVIL_TEXTURE_TRIANGLES", covered_triangles, "size", size)
    coverage = counts > 0
    if not np.any(coverage):
        raise RuntimeError("texture painter covered no UV pixels")
    colour = colour.reshape(size, size, 3)
    emission = emission.reshape(size, size, 3)
    height = height.reshape(size, size)
    roughness = roughness.reshape(size, size)
    metallic = metallic.reshape(size, size)
    texel_scale = texel_scale.reshape(size, size)
    cavity_map = cavity_map.reshape(size, size)
    coverage2d = coverage.reshape(size, size)
    tag_2d = tag_ids.reshape(size, size)

    colour = _dilate(colour, coverage2d)
    emission = _dilate(emission, coverage2d)
    height = _dilate(height[..., None], coverage2d)[..., 0]
    roughness = _dilate(roughness[..., None], coverage2d)[..., 0]
    metallic = _dilate(metallic[..., None], coverage2d)[..., 0]
    texel_scale = _dilate(texel_scale[..., None], coverage2d)[..., 0]
    cavity_map = _dilate(cavity_map[..., None], coverage2d)[..., 0]
    tag_2d = _dilate(tag_2d[..., None].astype(np.float32), coverage2d)[..., 0].astype(np.int16)

    # Height field -> tangent-space normal. Blender and glTF use +Y up.
    dhdu = np.gradient(height, axis=1) * texel_scale
    dhdv = np.gradient(height, axis=0) * texel_scale
    normal_slope = float(spec.get("normal_strength", 1.0))
    nx = -dhdu * normal_slope
    ny = -dhdv * normal_slope
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal_rgb = np.stack((nx / length, ny / length, nz / length), axis=-1) * 0.5 + 0.5

    # Baked cavity darkens albedo and roughens recesses; no separate AO texture.
    occlusion = (1.0 - 0.42 * np.clip(cavity_map, 0.0, 1.0))[..., None]
    albedo_srgb = linear_to_srgb(colour * occlusion)
    emission_srgb = linear_to_srgb(emission)
    roughness = np.clip(roughness + 0.10 * cavity_map, 0.03, 1.0)
    metallic = np.clip(metallic, 0.0, 1.0)

    source_dir.mkdir(parents=True, exist_ok=True)
    half = max(256, size // 2)
    rough_small = _block_downsample(roughness, size // half)
    metal_small = _block_downsample(metallic, size // half)
    emission_small = _block_downsample(emission_srgb, size // half)

    prefix = spec["id"]
    # Blender writes 8-bit Image pixels verbatim; the sRGB tag tells Godot how
    # to decode them, so the PNG must already contain display-referred values.
    albedo_image = _make_image(f"{spec['scene']}_Albedo", size, albedo_srgb, "sRGB",
                               source_dir / f"{prefix}_albedo.png")
    normal_image = _make_image(f"{spec['scene']}_Normal", size, normal_rgb, "Non-Color",
                               source_dir / f"{prefix}_normal.png")
    rough_image = _make_image(f"{spec['scene']}_Roughness", half, rough_small, "Non-Color",
                              source_dir / f"{prefix}_roughness.png")
    metal_image = _make_image(f"{spec['scene']}_Metallic", half, metal_small, "Non-Color",
                              source_dir / f"{prefix}_metallic.png")
    emission_image = _make_image(f"{spec['scene']}_Emission", half, emission_small, "sRGB",
                                 source_dir / f"{prefix}_emission.png")

    material = bpy.data.materials.new(spec["scene"] + "_Surface")
    material.use_nodes = True
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        if node.type != "OUTPUT_MATERIAL":
            nodes.remove(node)
    output = nodes.get("Material Output")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.65
    bsdf.inputs["Metallic"].default_value = 0.0
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    albedo_node = nodes.new("ShaderNodeTexImage")
    albedo_node.name = "BaseColor"
    albedo_node.image = albedo_image
    albedo_node.interpolation = "Linear"
    links.new(albedo_node.outputs["Color"], bsdf.inputs["Base Color"])
    normal_node = nodes.new("ShaderNodeTexImage")
    normal_node.name = "Normal"
    normal_node.image = normal_image
    normal_node.interpolation = "Linear"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 1.0
    links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    rough_node = nodes.new("ShaderNodeTexImage")
    rough_node.name = "Roughness"
    rough_node.image = rough_image
    rough_node.interpolation = "Linear"
    links.new(rough_node.outputs["Color"], bsdf.inputs["Roughness"])
    metal_node = nodes.new("ShaderNodeTexImage")
    metal_node.name = "Metallic"
    metal_node.image = metal_image
    metal_node.interpolation = "Linear"
    links.new(metal_node.outputs["Color"], bsdf.inputs["Metallic"])
    emission_node = nodes.new("ShaderNodeTexImage")
    emission_node.name = "Emission"
    emission_node.image = emission_image
    emission_node.interpolation = "Linear"
    links.new(emission_node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    material.diffuse_color = (0.4, 0.35, 0.32, 1.0)

    mesh.data.materials.clear()
    mesh.data.materials.append(material)
    for polygon in mesh.data.polygons:
        polygon.material_index = 0
    print("DEVIL_TEXTURE_DONE", spec["id"], size, int(np.count_nonzero(coverage2d)))
    return {
        "albedo": str(source_dir / f"{prefix}_albedo.png"),
        "normal": str(source_dir / f"{prefix}_normal.png"),
        "roughness": str(source_dir / f"{prefix}_roughness.png"),
        "metallic": str(source_dir / f"{prefix}_metallic.png"),
        "emission": str(source_dir / f"{prefix}_emission.png"),
        "tags": tag_names,
    }


# ---------------------------------------------------------------------------
# Surface painters. All functions are vectorised over rest-space points and
# return sRGB colour/emission plus metric height and material scalars.


def _mix(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    if t.ndim == 1:
        t = t[:, None]
    return a * (1.0 - t) + b * t


def _palette(spec: dict, tag: str) -> dict:
    palette = spec["palette"]
    if tag in palette:
        return palette[tag]
    if "body" in palette:
        return palette["body"]
    return palette.get("skin", {})


def _surface_arrays(n: int):
    return {
        "colour": np.zeros((n, 3), dtype=np.float32),
        "height": np.zeros(n, dtype=np.float32),
        "roughness": np.zeros(n, dtype=np.float32),
        "metallic": np.zeros(n, dtype=np.float32),
        "emission": np.zeros((n, 3), dtype=np.float32),
    }


def paint_surface(tag: str, P: np.ndarray, N: np.ndarray, spec: dict,
                  cavity: np.ndarray) -> dict:
    entry = _palette(spec, tag)
    kind = entry.get("kind", tag)
    n = len(P)
    result = _surface_arrays(n)
    seed = int(entry.get("seed", 31)) + (sum(ord(c) for c in tag) % 997)
    base = srgb_array(entry.get("base", (0.45, 0.40, 0.36)))
    second = srgb_array(entry.get("second", entry.get("base", (0.45, 0.40, 0.36))))
    accent = srgb_array(entry.get("accent", entry.get("second", entry.get("base", (0.5, 0.4, 0.3)))))
    rough = float(entry.get("roughness", 0.62))
    metal = float(entry.get("metallic", 0.0))

    if kind == "fur" or kind == "hair":
        flow = np.array(entry.get("flow", (0.0, -0.25, -1.0)), dtype=np.float32)
        flow /= np.linalg.norm(flow) + 1e-7
        frequency = float(entry.get("frequency", 150.0 if kind == "fur" else 260.0))
        clump = fbm(P, float(entry.get("clump_scale", 22.0)), seed)
        strand = 0.5 + 0.5 * np.sin(P @ flow * frequency + clump * 7.0)
        strand = strand ** float(entry.get("sharpness", 1.6))
        tips = smoothstep(0.72, 1.0, strand)
        root = 1.0 - smoothstep(0.0, 0.35, strand)
        colour = _mix(base, second, np.clip(0.25 + strand * 0.55 + (clump - 0.5) * 0.35, 0.0, 1.0))
        colour = _mix(colour, accent, tips * float(entry.get("tip_mix", 0.32)))
        colour = _mix(colour, second * 0.55, root * 0.25)
        result["colour"] = colour
        result["height"] = ((strand - 0.5) * float(entry.get("height", 0.0012))
                            + (clump - 0.5) * 0.0006)
        result["roughness"] = np.full(n, rough) + (clump - 0.5) * 0.08
        result["metallic"] = np.full(n, metal)
        return result

    if kind == "skin" or kind == "hide":
        mottle = fbm(P, float(entry.get("mottle_scale", 9.0)), seed)
        pores = value_noise(P, float(entry.get("pore_scale", 260.0)), seed + 5) - 0.5
        wrinkle = ridged(P, float(entry.get("wrinkle_scale", 48.0)), seed + 7, 3)
        veins = ridged(P, float(entry.get("vein_scale", 22.0)), seed + 11, 3) ** 3.0
        t = np.clip(0.30 + (mottle - 0.5) * 1.10 + (veins - 0.5) * 0.55, 0.0, 1.0)
        colour = _mix(base, second, t)
        colour = _mix(colour, accent, np.clip(veins * float(entry.get("vein_mix", 0.22)), 0.0, 1.0))
        colour += pores[:, None] * float(entry.get("pore_contrast", 0.05))
        result["colour"] = np.clip(colour, 0.0, 1.0)
        result["height"] = (pores * float(entry.get("pore_height", 0.00022))
                            + (wrinkle - 0.5) * float(entry.get("wrinkle_height", 0.00035)))
        result["roughness"] = np.full(n, rough) + (mottle - 0.5) * 0.10
        result["metallic"] = np.full(n, metal)
        if entry.get("glow"):
            glow = np.clip((veins - 0.55) * 2.2, 0.0, 1.0)
            result["emission"] = accent[None, :] * glow[:, None] * float(entry.get("glow", 0.0))
        return result

    if kind in ("horn", "keratin", "claw", "hoof", "bone"):
        axis = np.array(entry.get("axis", (0.0, 0.0, 1.0)), dtype=np.float32)
        axis /= np.linalg.norm(axis) + 1e-7
        rings = 0.5 + 0.5 * np.sin(P @ axis * float(entry.get("ring_frequency", 190.0))
                                  + fbm(P, 18.0, seed + 3) * 5.0)
        striation = value_noise(P, float(entry.get("striation_scale", 420.0)), seed + 8)
        cracks = ridged(P, float(entry.get("crack_scale", 30.0)), seed + 13, 3)
        t = np.clip(0.25 + rings * 0.55 + (striation - 0.5) * 0.35, 0.0, 1.0)
        colour = _mix(base, second, t)
        crack_mask = smoothstep(0.86, 0.99, cracks)
        colour = _mix(colour, accent, crack_mask * float(entry.get("crack_mix", 0.5)))
        result["colour"] = colour
        result["height"] = ((rings - 0.5) * float(entry.get("ring_height", 0.0004))
                            + (striation - 0.5) * 0.00018 - crack_mask * 0.0003)
        result["roughness"] = np.full(n, rough) + (rings - 0.5) * 0.05
        result["metallic"] = np.full(n, metal)
        return result

    if kind == "leather":
        grain = fbm(P, float(entry.get("grain_scale", 55.0)), seed)
        creases = ridged(P, float(entry.get("crease_scale", 24.0)), seed + 5, 3)
        wear = fbm(P, 7.0, seed + 9)
        colour = _mix(base, second, np.clip(0.2 + grain * 0.55 + (wear - 0.5) * 0.7, 0.0, 1.0))
        colour = _mix(colour, accent, smoothstep(0.72, 0.96, creases) * 0.30)
        result["colour"] = colour
        result["height"] = ((grain - 0.5) * 0.00045 - smoothstep(0.75, 0.98, creases) * 0.0005)
        result["roughness"] = np.full(n, rough) + (grain - 0.5) * 0.08
        result["metallic"] = np.full(n, metal)
        return result

    if kind == "metal":
        scratches = ridged(P, float(entry.get("scratch_scale", 85.0)), seed + 2, 4)
        grain = fbm(P, 34.0, seed + 6)
        patina = fbm(P, 11.0, seed + 12)
        streak = 0.5 + 0.5 * np.sin(P[:, 2] * 240.0 + grain * 8.0)
        colour = _mix(base, second, np.clip(0.3 + patch_mix(patina) * 0.55, 0.0, 1.0))
        colour = _mix(colour, accent, np.clip((scratches - 0.82) * 4.0, 0.0, 1.0) * 0.5)
        result["colour"] = colour
        result["height"] = (streak - 0.5) * 0.00016 + (scratches - 0.5) * 0.00012
        result["roughness"] = np.full(n, rough) + (patina - 0.5) * 0.18
        result["metallic"] = np.clip(metal * (0.72 + patina * 0.28), 0.0, 1.0)
        return result

    if kind == "membrane":
        veins = ridged(P, float(entry.get("vein_scale", 26.0)), seed + 4, 4) ** 2.2
        thin = fbm(P, 60.0, seed + 10)
        t = np.clip(0.18 + thin * 0.45 + veins * 0.35, 0.0, 1.0)
        colour = _mix(base, second, t)
        colour = _mix(colour, accent, np.clip(veins * 1.35, 0.0, 1.0) * 0.55)
        result["colour"] = colour
        result["height"] = (veins - 0.5) * 0.00032 + (thin - 0.5) * 0.00014
        result["roughness"] = np.full(n, rough) + (thin - 0.5) * 0.10
        result["metallic"] = np.full(n, metal)
        if entry.get("glow"):
            result["emission"] = accent[None, :] * (veins ** 4.0)[:, None] * float(entry["glow"])
        return result

    if kind == "stone":
        granite = fbm(P, float(entry.get("grain_scale", 62.0)), seed, 5)
        speckle = value_noise(P, float(entry.get("speckle_scale", 430.0)), seed + 3)
        lichen = smoothstep(0.58, 0.78, fbm(P, float(entry.get("lichen_scale", 9.0)), seed + 6))
        cracks = ridged(P, float(entry.get("crack_scale", 17.0)), seed + 9, 4)
        chip = smoothstep(0.64, 0.92, fbm(P, 30.0, seed + 15))
        t = np.clip(0.15 + granite * 0.75 + (speckle - 0.5) * 0.45, 0.0, 1.0)
        colour = _mix(base, second, t)
        colour = _mix(colour, accent, lichen * 0.35)
        crack_mask = smoothstep(0.84, 0.98, cracks)
        colour = _mix(colour * (1.0 - chip[:, None] * 0.18), second * 1.15, chip * 0.25)
        result["colour"] = np.clip(colour, 0.0, 1.0)
        result["height"] = ((granite - 0.5) * 0.0016 + (speckle - 0.5) * 0.0005
                            - crack_mask * 0.0012 + chip * 0.0004)
        result["roughness"] = np.full(n, rough) + (granite - 0.5) * 0.10
        result["metallic"] = np.full(n, metal)
        ember = float(entry.get("ember_cracks", 0.0))
        if ember > 0.0:
            glow = crack_mask * np.clip(0.35 + (granite - 0.5) * 1.4, 0.0, 1.0)
            result["emission"] = srgb_array(entry.get("ember", "#ff6a22"))[None, :] * glow[:, None] * ember
        return result

    if kind == "eye":
        eyes = spec.get("eyes", [])
        colour = np.tile(base, (n, 1)).astype(np.float32)
        emission = np.zeros((n, 3), dtype=np.float32)
        height = np.zeros(n, dtype=np.float32)
        sizes = np.zeros(n, dtype=np.float32)
        for eye in eyes:
            centre = np.array(eye["center"], dtype=np.float32)
            forward = np.array(eye.get("forward", (0.0, 1.0, 0.0)), dtype=np.float32)
            forward /= np.linalg.norm(forward) + 1e-7
            radius = float(eye.get("radius", 0.035))
            delta = P - centre
            along = delta @ forward
            radial = np.linalg.norm(delta - along[:, None] * forward[None, :], axis=1)
            ratio = radial / radius
            mask = (along > 0.0) & (ratio < 1.0)
            if not np.any(mask):
                continue
            pupil = mask & (ratio < float(eye.get("pupil", 0.28)))
            iris = mask & ~pupil
            sclera = mask & (ratio >= float(eye.get("iris_edge", 0.74)))
            iris_colour = srgb_array(eye.get("iris", "#ff7a1a"))
            pupil_colour = srgb_array(eye.get("pupil_colour", "#050203"))
            sclera_colour = srgb_array(eye.get("sclera", entry.get("base", "#1a0d0a")))
            streak = 0.5 + 0.5 * np.sin(np.arctan2(delta[:, 2], delta[:, 0]) * 38.0 + ratio * 24.0)
            iris_tinted = _mix(iris_colour * 0.65, iris_colour * 1.35, streak)
            colour[iris] = iris_tinted[iris]
            colour[sclera] = sclera_colour
            colour[pupil] = pupil_colour
            if eye.get("emission", 0.0):
                emission[iris] = iris_colour * float(eye["emission"])
            height[iris] = 0.00018
            height[pupil] = -0.00022
            sizes[mask] = 1.0
        result["colour"] = colour
        result["emission"] = emission
        result["height"] = height
        result["roughness"] = np.where(sizes > 0.0, 0.06, rough)
        result["metallic"] = np.zeros(n)
        return result

    if kind == "teeth":
        root = smoothstep(0.0, 0.55, fbm(P, 12.0, seed))
        cracks = ridged(P, 70.0, seed + 2, 3)
        colour = _mix(base, second, root)
        colour = _mix(colour, accent, smoothstep(0.88, 0.99, cracks) * 0.45)
        result["colour"] = colour
        result["height"] = (cracks - 0.5) * 0.00022
        result["roughness"] = np.full(n, rough)
        result["metallic"] = np.full(n, metal)
        return result

    if kind == "mouth":
        wet = fbm(P, 45.0, seed)
        colour = _mix(base, second, wet)
        result["colour"] = colour
        result["height"] = (wet - 0.5) * 0.0003
        result["roughness"] = np.full(n, rough) + (wet - 0.5) * 0.06
        result["metallic"] = np.zeros(n)
        return result

    if kind == "ember":
        charred = fbm(P, 38.0, seed)
        cracks = ridged(P, 24.0, seed + 4, 4)
        glow = smoothstep(0.86, 0.99, cracks) * np.clip(0.4 + charred, 0.0, 1.0)
        colour = _mix(base, second, charred)
        result["colour"] = colour
        result["height"] = (charred - 0.5) * 0.0005 - glow * 0.0004
        result["roughness"] = np.full(n, rough)
        result["metallic"] = np.full(n, metal)
        result["emission"] = srgb_array(entry.get("accent", "#ff6a22"))[None, :] * glow[:, None]
        return result

    # Fallback: neutral hide.
    mottle = fbm(P, 10.0, seed)
    result["colour"] = _mix(base, second, mottle)
    result["height"] = (mottle - 0.5) * 0.0003
    result["roughness"] = np.full(n, rough)
    result["metallic"] = np.full(n, metal)
    return result


def patch_mix(value: np.ndarray) -> np.ndarray:
    return np.clip((value - 0.35) * 1.6, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Posing, foot contact and baked clips


def set_world_rotation(pb, quaternion: Quaternion) -> None:
    rest = pb.bone.matrix_local.to_quaternion()
    pb.rotation_quaternion = rest.inverted() @ quaternion @ rest


def set_axis_rotation(pb, angle: float, axis: Vector = Vector((1.0, 0.0, 0.0))) -> None:
    rest = pb.bone.matrix_local.to_quaternion()
    local_axis = rest.inverted() @ axis
    pb.rotation_quaternion = Quaternion(local_axis.normalized(), angle)


def reset_pose(rig) -> None:
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def set_pelvis_offset(rig, offset: Vector) -> None:
    pb = rig.pose.bones["pelvis"]
    rest = pb.bone.matrix_local.to_quaternion()
    pb.location = rest.inverted() @ Vector(offset)


def rest_direction(spec: dict, name: str) -> Vector:
    data = spec["bones"][name]
    return (Vector(data["tail"]) - Vector(data["head"])).normalized()


def rest_length(spec: dict, name: str) -> float:
    data = spec["bones"][name]
    return (Vector(data["tail"]) - Vector(data["head"])).length


def rest_angle(spec: dict, name: str) -> float:
    direction = rest_direction(spec, name)
    return math.atan2(direction.y, -direction.z)


def solve_leg(rig, spec: dict, chain_key: str, target: Vector,
              toe_flex: float, foot_pitch: float, parent_pitch: float) -> None:
    names = spec["chains"][chain_key]["bones"]
    upper_name, lower_name, third_name, paw_name, toes_name = names
    upper_pb = rig.pose.bones[upper_name]
    lower_pb = rig.pose.bones[lower_name]
    third_pb = rig.pose.bones[third_name]
    paw_pb = rig.pose.bones[paw_name]
    toes_pb = rig.pose.bones[toes_name]
    A = upper_pb.matrix.translation.copy()
    third_dir = rest_direction(spec, third_name)
    third_len = rest_length(spec, third_name)
    W = target - third_dir * third_len
    W.x = A.x
    delta = Vector((0.0, W.y - A.y, W.z - A.z))
    L1 = rest_length(spec, upper_name)
    L2 = rest_length(spec, lower_name)
    distance = max(0.001, min(delta.length, L1 + L2 - 0.001))
    if delta.length < 1e-6:
        return
    u = delta.normalized()
    a = (L1 * L1 - L2 * L2 + distance * distance) / (2.0 * distance)
    h = math.sqrt(max(0.0, L1 * L1 - a * a))
    pole = float(spec["chains"][chain_key].get("pole", 1.0))
    normal = Vector((0.0, u.z, -u.y)) * pole
    elbow = A + u * a + normal * h
    phi1 = math.atan2(elbow.y - A.y, A.z - elbow.z)
    phi2 = math.atan2(W.y - elbow.y, elbow.z - W.z)
    rest1 = rest_angle(spec, upper_name)
    rest2 = rest_angle(spec, lower_name)
    set_axis_rotation(upper_pb, (phi1 - rest1) - parent_pitch)
    set_axis_rotation(lower_pb, (phi2 - rest2) - (phi1 - rest1))
    # Keep the cannon/ankle and sole world-level; add an authored foot pitch.
    set_axis_rotation(third_pb, foot_pitch - (phi2 - rest2))
    set_axis_rotation(paw_pb, 0.0)
    set_axis_rotation(toes_pb, toe_flex)


def apply_pose(rig, spec: dict, values: dict) -> None:
    reset_pose(rig)
    pelvis_pitch = float(values.get("pelvis_pitch", 0.0))
    pelvis_roll = float(values.get("pelvis_roll", 0.0))
    pelvis_yaw = float(values.get("pelvis_yaw", 0.0))
    set_pelvis_offset(rig, Vector(values.get("pelvis_offset", (0.0, 0.0, 0.0))))
    pelvis_q = (Quaternion((0.0, 0.0, 1.0), pelvis_yaw)
                @ Quaternion((0.0, 1.0, 0.0), pelvis_roll)
                @ Quaternion((1.0, 0.0, 0.0), pelvis_pitch))
    set_world_rotation(rig.pose.bones["pelvis"], pelvis_q)
    rotations = values.get("rot", {})
    torso_pitch = pelvis_pitch
    for name in spec.get("rotation_order", []):
        pitch, yaw, roll = rotations.get(name, (0.0, 0.0, 0.0))
        torso_pitch += float(pitch)
        quaternion = (Quaternion((0.0, 0.0, 1.0), float(yaw))
                      @ Quaternion((0.0, 1.0, 0.0), float(roll))
                      @ Quaternion((1.0, 0.0, 0.0), float(pitch)))
        if name in rig.pose.bones:
            set_world_rotation(rig.pose.bones[name], quaternion)
    jaw = float(values.get("jaw_open", 0.0))
    if "jaw" in rig.pose.bones:
        set_axis_rotation(rig.pose.bones["jaw"], -jaw)
    bpy.context.view_layer.update()
    for chain_key, chain_values in values.get("legs", {}).items():
        if chain_key not in spec["chains"]:
            continue
        rest_target = Vector(spec["chains"][chain_key].get("target",
                           spec["bones"][spec["chains"][chain_key]["bones"][3]]["head"]))
        target = rest_target + Vector((0.0,
                                       float(chain_values.get("y", 0.0)),
                                       float(chain_values.get("lift", 0.0))))
        chain_parent = torso_pitch if spec["chains"][chain_key].get("fore", False) else pelvis_pitch
        chain_parent += float(chain_values.get("parent_pitch", 0.0))
        solve_leg(rig, spec, chain_key, target,
                  float(chain_values.get("toe", 0.0)),
                  float(chain_values.get("foot", 0.0)),
                  chain_parent)
    bpy.context.view_layer.update()


def make_action(rig, spec: dict, clip_key: str):
    clip = spec["clips"][clip_key]
    duration = float(clip["duration"])
    name = clip["name"]
    pose_function = spec["poses"][clip_key]
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    frames = int(round(duration * FPS))
    for frame in range(frames + 1):
        t = frame / FPS
        values = pose_function(t)
        apply_pose(rig, spec, values)
        for pb in rig.pose.bones:
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
    print("DEVIL_ACTION", name, "frames", frames, "seconds", duration)
    return action


def build_actions(rig, spec: dict):
    if rig.animation_data is None:
        rig.animation_data_create()
    actions = []
    for clip_key in spec["clips"]:
        actions.append(make_action(rig, spec, clip_key))
    return actions


# --- shared locomotion helpers -------------------------------------------------


def gait_chains(spec: dict, phase: float, duty: float, stride: float,
                clearance: float, offsets: dict[str, float], values: dict) -> None:
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
            foot = 0.18 * math.sin(math.pi * p)
        values["legs"][chain_key] = {"y": y, "lift": lift, "toe": toe, "foot": foot}


def apply_body_sway(values: dict, spec: dict, phase: float, yaw: float,
                    bob: float, roll: float) -> None:
    values["pelvis_offset"] = (0.0, 0.0, bob)
    values["pelvis_yaw"] = yaw
    values["pelvis_roll"] = roll
    rotations = values.setdefault("rot", {})
    for name in spec.get("sway_bones", []):
        pitch, ryaw, rroll = rotations.get(name, (0.0, 0.0, 0.0))
        rotations[name] = (pitch, ryaw - yaw * 0.55, rroll + roll * 0.35)


# ---------------------------------------------------------------------------
# Export, metadata and rendered evidence


def setup_nla_and_export(rig, actions, output: Path) -> None:
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
        export_tangents=True,
        export_skins=True,
    )


def glb_document(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + json_length])
    return document, raw


def write_metadata(output: Path, spec: dict) -> dict:
    document, _ = glb_document(output)
    animations = {animation["name"]: animation for animation in document.get("animations", [])}
    durations = {}
    for name, animation in animations.items():
        durations[name] = max(
            document["accessors"][sampler["input"]]["max"][0]
            for sampler in animation["samplers"]
        )
    skin = document["skins"][0]
    bone_names = [document["nodes"][index].get("name", "") for index in skin["joints"]]
    position_accessors = [
        primitive["attributes"]["POSITION"]
        for mesh in document["meshes"]
        for primitive in mesh["primitives"]
    ]
    bounds_min = [min(document["accessors"][index]["min"][axis] for index in position_accessors)
                  for axis in range(3)]
    bounds_max = [max(document["accessors"][index]["max"][axis] for index in position_accessors)
                  for axis in range(3)]
    materials = [material.get("name", "") for material in document.get("materials", [])]
    images = [image.get("mimeType", "") for image in document.get("images", [])]
    triangle_count = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if "indices" in primitive:
                triangle_count += document["accessors"][primitive["indices"]]["count"] // 3
    root_index = next((index for index, node in enumerate(document["nodes"])
                       if node.get("name") == "root"), None)
    root_translation_channels = [
        channel
        for animation in document.get("animations", [])
        for channel in animation["channels"]
        if channel["target"].get("node") == root_index
        and channel["target"].get("path") == "translation"
    ]
    clips = {}
    for key, clip in spec["clips"].items():
        entry = {
            "name": clip["name"],
            "duration": durations.get(clip["name"]),
            "loop": bool(clip.get("loop", False)),
        }
        for extra in ("stride", "duty", "impact", "recovery_end", "contact_offsets",
                      "fallback_speed", "run_threshold"):
            if extra in clip:
                entry[extra] = clip[extra]
        clips[key] = entry
    metadata = {
        "asset": output.name,
        "mob": spec["id"],
        "display_name": spec["display_name"],
        "skeleton": spec["scene"] + "Armature/Skeleton3D",
        "bone_count": len(bone_names),
        "bone_names": bone_names,
        "forward": [0, 0, -1],
        "up": [0, 1, 0],
        "unit": "metres",
        "rest_bounds_min": bounds_min,
        "rest_bounds_max": bounds_max,
        "height": spec.get("height"),
        "mesh_triangles": triangle_count,
        "materials": materials,
        "embedded_images": images,
        "texture_atlas": {
            "size": int(spec.get("texture_size", 1024)),
            "tags": spec.get("paint_tags", []),
            "channels": ["albedo", "normal", "roughness", "metallic", "emission"],
        },
        "clips": clips,
        "animations": durations,
        "authoring_fps": FPS,
        "root_translation_channels": len(root_translation_channels),
        "head_zone": spec.get("head_zone"),
        "source": ("Original procedural creature authored by tools/prepare_devils.py; "
                   "no third-party model, texture or motion."),
        "reproducer": f"tools/prepare_devils.py --mob {spec['id']}",
    }
    for key, value in spec.get("metadata_extra", {}).items():
        metadata[key] = value
    metadata_path = output.with_suffix(".json")
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("DEVIL_METADATA", metadata_path)
    return metadata


def _add_preview_lighting(scene) -> None:
    world = bpy.data.worlds.new("DevilPreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.020, 0.024, 0.030, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.65
    scene.world = world
    for name, location, energy, size, colour in (
        ("Key", (2.6, 2.2, 3.2), 900.0, 3.0, (1.0, 0.82, 0.68)),
        ("Fill", (-3.0, 1.2, 1.6), 260.0, 2.5, (0.55, 0.68, 1.0)),
        ("Rim", (0.6, -3.0, 2.4), 700.0, 2.0, (1.0, 0.40, 0.22)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = colour
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        light.rotation_euler = (Vector((0.0, 0.0, 1.1)) - Vector(location)).to_track_quat("-Z", "Y").to_euler()


def render_previews(rig, spec: dict, actions, source_dir: Path) -> None:
    scene = bpy.context.scene
    _add_preview_lighting(scene)
    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    preview_material = bpy.data.materials.new("PreviewGround")
    preview_material.use_nodes = True
    bsdf = preview_material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.035, 0.038, 0.035, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.82
    ground.data.materials.append(preview_material)
    cameras = {}
    for name, location, target, ortho in (
        ("front", (0.0, 4.4, 1.25), (0.0, 0.0, 1.15), 2.55),
        ("threeq", (3.3, -3.4, 2.0), (0.0, 0.0, 1.10), 2.85),
        ("side", (4.4, 0.0, 1.2), (0.0, 0.0, 1.10), 2.55),
    ):
        data = bpy.data.cameras.new(name)
        data.type = "ORTHO"
        data.ortho_scale = ortho
        camera = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(camera)
        camera.location = location
        camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        cameras[name] = camera
    capture_dir = source_dir / "captures"
    capture_dir.mkdir(parents=True, exist_ok=True)

    # Fast textured contact sheet: silhouette, pose and albedo.
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    preview_set = {}
    for key, clip in spec["clips"].items():
        name = clip["name"]
        if key == "idle":
            preview_set[name] = [(0.0, "front"), (0.0, "threeq"), (clip["duration"] * 0.5, "threeq")]
        elif key in ("walk", "run", "crawl", "hover"):
            preview_set[name] = [(clip["duration"] * 0.25, "side"),
                                 (clip["duration"] * 0.5, "side"),
                                 (clip["duration"] * 0.75, "threeq")]
        elif key == "attack":
            impact = float(clip.get("impact", clip["duration"] * 0.5))
            preview_set[name] = [(impact * 0.45, "threeq"), (impact, "threeq"),
                                 (impact, "side"), (min(clip["duration"], impact + 0.35), "threeq")]
        elif key == "death":
            preview_set[name] = [(clip["duration"] * 0.45, "threeq"),
                                 (clip["duration"], "threeq")]
        else:
            preview_set[name] = [(clip["duration"] * 0.5, "threeq")]
    for action in actions:
        rig.animation_data.action = action
        if action.slots:
            rig.animation_data.action_slot = action.slots[0]
        for index, (time, view) in enumerate(preview_set.get(action.name, [])):
            scene.frame_set(int(round(time * FPS)))
            scene.camera = cameras[view]
            scene.render.filepath = str(capture_dir / f"{action.name}_{index:02d}_{time:.2f}s_{view}.png")
            bpy.ops.render.render(write_still=True)

    # PBR hero frames prove the normal/roughness/metallic/emission atlas.
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.eevee.taa_render_samples = 24
    for key in ("idle", "attack"):
        action = next((entry for entry in actions if entry.name == spec["clips"][key]["name"]), None)
        if action is None:
            continue
        rig.animation_data.action = action
        if action.slots:
            rig.animation_data.action_slot = action.slots[0]
        clip = spec["clips"][key]
        time = 0.0 if key == "idle" else float(clip.get("impact", clip["duration"] * 0.5))
        scene.frame_set(int(round(time * FPS)))
        scene.camera = cameras["threeq"]
        scene.render.filepath = str(capture_dir / f"{spec['id']}_{key}_pbr.png")
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = None
    print("DEVIL_CAPTURES", capture_dir)


def triangulate(mesh) -> None:
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(mesh.data)
    bm.free()
    mesh.data.update()


def run_mob(spec: dict, source_dir: Path, output: Path, previews: bool = True) -> dict:
    reset_scene()
    for tag in spec["paint_tags"]:
        make_tag_material(tag)
    rig = build_rig(spec)
    parts = spec["build_parts"]()
    for entry in parts:
        obj = entry["object"]
        if entry["rigid"]:
            rigid_weight(obj, entry["rigid"])
        else:
            assign_envelope(obj, rig, spec["skin_bones"])
    mesh = finish_mesh(parts, rig, spec)
    unwrap(mesh)
    paint_textures(mesh, spec, source_dir)
    triangulate(mesh)
    print("DEVIL_FINAL_TRIS", spec["id"],
          sum(len(poly.vertices) - 2 for poly in mesh.data.polygons))
    actions = build_actions(rig, spec)
    setup_nla_and_export(rig, actions, output)
    metadata = write_metadata(output, spec)
    if previews:
        render_previews(rig, spec, actions, source_dir)
    source_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source_dir / f"ironwood_{spec['id']}_source.blend"))
    print("DEVIL_DONE", spec["id"], json.dumps({
        "triangles": metadata["mesh_triangles"],
        "bones": metadata["bone_count"],
        "clips": metadata["clips"],
    }))
    return metadata





