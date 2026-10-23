"""Author the swappable armor pieces on the Ranger skeleton.

The exported Ranger GLB already contains the leather outfit as separate meshes.
This module builds the missing leather gloves and three complete sets (mail,
plate and cloth) as skinned meshes sharing the same 65-bone rest skeleton:

    Armor_<Set>_<Slot>   set in {Mail, Plate, Cloth}

Run it through tools/prepare_character.py; it is not a standalone asset stage.
The meshes are modelled in armature space: +X is the character's left, -Y is
forward and +Z is up.  Every piece is skinned with explicit vertex weights so
the export contains no runtime weighting or modifier work.
"""
import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

TAU = math.tau
SLOTS = ("head", "chest", "hands", "legs", "feet")
SETS = ("leather", "mail", "plate", "cloth")
TEXTURE_SIZE = 512


def clamp01(value):
    return 0.0 if value < 0.0 else 1.0 if value > 1.0 else value


def smoothstep(edge0, edge1, value):
    if edge1 <= edge0:
        return 0.0 if value < edge0 else 1.0
    t = clamp01((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def blend(first, second, t):
    return first * (1.0 - t) + second * t


def _obj_from_data(name, verts, faces, material, smooth=False):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.validate(verbose=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    return obj


def _select_only(objects, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[0]


def _apply_modifiers(obj):
    _select_only([obj], obj)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def add_bevel(obj, width=0.003, segments=2, angle=math.radians(40.0)):
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = angle
    _apply_modifiers(obj)


def add_solidify(obj, thickness=0.006, offset=0.0, rim=True):
    modifier = obj.modifiers.new("Solidify", "SOLIDIFY")
    modifier.thickness = thickness
    modifier.offset = offset
    modifier.use_rim = rim
    _apply_modifiers(obj)


def join_parts(name, parts):
    if len(parts) == 1:
        parts[0].name = name
        parts[0].data.name = name
        return parts[0]
    _select_only(parts, parts[0])
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def assign_weights(obj, weight_fn):
    """Assign a {bone: weight} dict per vertex, quantised for fast grouping."""
    buckets = {}
    for vertex in obj.data.vertices:
        weights = weight_fn(vertex.co.copy())
        total = sum(max(0.0, value) for value in weights.values())
        if total <= 1e-8:
            continue
        for bone, value in weights.items():
            if value <= 1e-5:
                continue
            quantised = max(1, min(64, round(value / total * 64.0)))
            buckets.setdefault((bone, quantised), []).append(vertex.index)
    for (bone, quantised), indices in buckets.items():
        group = obj.vertex_groups.get(bone)
        if group is None:
            group = obj.vertex_groups.new(name=bone)
        group.add(indices, quantised / 64.0, "REPLACE")


def assign_bone(obj, bone):
    assign_weights(obj, lambda _point: {bone: 1.0})


def cube_project(obj, tile_size):
    _select_only([obj], obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=tile_size, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def recalc_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def finish_piece(name, parts, rig, tile_size):
    obj = join_parts(name, parts)
    obj.data.validate(verbose=False)
    recalc_normals(obj)
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    modifier.use_vertex_groups = True
    cube_project(obj, tile_size)
    return obj


# ----------------------------------------------------------------------------
# Textures.  Generated in linear float buffers, packed into the GLB by the
# exporter.  Normal maps are marked Non-Color.  All patterns tile.
# ----------------------------------------------------------------------------

def _fbm(size, seed, octaves=6, base=2):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) / size
    value = np.zeros((size, size), dtype=np.float64)
    amplitude = 1.0
    total = 0.0
    for octave in range(octaves):
        frequency = base ** octave
        for _ in range(3):
            fx = int(rng.integers(1, max(2, frequency + 2)))
            fy = int(rng.integers(1, max(2, frequency + 2)))
            phase = float(rng.random()) * TAU
            value += amplitude * np.sin(TAU * (fx * xx + fy * yy) + phase)
            total += amplitude
        amplitude *= 0.55
    return value / max(total, 1e-9)


def _normal_from_height(height, strength=2.0):
    dx = np.gradient(height, axis=1)
    dy = np.gradient(height, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([(nx / length) * 0.5 + 0.5,
                     (ny / length) * 0.5 + 0.5,
                     (nz / length) * 0.5 + 0.5,
                     np.ones_like(height)], axis=-1)


def _rgba(rgb):
    result = np.ones((rgb.shape[0], rgb.shape[1], 4), dtype=np.float64)
    result[:, :, :3] = rgb
    return result


def _save_texture(name, pixels, color_space, folder):
    height, width = pixels.shape[:2]
    image = bpy.data.images.new(name, width=width, height=height, alpha=False, float_buffer=False)
    image.colorspace_settings.name = color_space
    image.pixels.foreach_set(pixels.astype(np.float32).ravel())
    image.file_format = "PNG"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (name + ".png")
    image.filepath_raw = str(path)
    image.save()
    image.pack()
    return image


def _steel_image(size, seed, dark):
    rng = np.random.default_rng(seed)
    grain = _fbm(size, seed, octaves=7, base=2)
    scratches = np.zeros((size, size))
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    for _ in range(26):
        angle = float(rng.random()) * math.pi
        offset = float(rng.random()) * size
        width = rng.uniform(0.4, 1.4)
        line = np.abs(np.cos(angle) * xx + np.sin(angle) * yy - offset)
        scratch = np.exp(-(line * line) / (width * width))
        scratches = np.maximum(scratches, scratch * rng.uniform(0.18, 0.55))
    mottling = 0.5 + 0.5 * grain
    base = (0.22 if dark else 0.34) + 0.12 * mottling
    rgb = np.stack([base * 0.96, base, base * 1.04], axis=-1)
    rgb += scratches[:, :, None] * np.array([0.18, 0.19, 0.20])
    return _rgba(np.clip(rgb, 0.0, 1.0)), _normal_from_height(grain * 0.5 + scratches, 1.4)


def _mail_image(size, seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) + 0.5
    height = np.zeros((size, size))
    spacing_x, spacing_y = size / 16.0, size / 32.0
    radius, band = spacing_x * 0.62, spacing_x * 0.20
    for row in range(32):
        for column in range(16):
            cx = (column + 0.5) * spacing_x + (spacing_x * 0.5 if row % 2 else 0.0)
            cy = (row + 0.5) * spacing_y
            dx = np.abs(xx - cx)
            dy = np.abs(yy - cy)
            dx = np.minimum(dx, size - dx)
            dy = np.minimum(dy, size - dy)
            distance = np.sqrt(dx * dx + dy * dy)
            ring = np.clip(1.0 - np.abs(distance - radius) / band, 0.0, 1.0)
            height = np.maximum(height, ring)
    height = np.maximum(height, -np.clip(1.0 - height, 0.0, 1.0) * 0.35)
    grain = _fbm(size, seed, octaves=5)
    height = np.clip(height + grain * 0.10, -0.4, 1.0)
    shadows = np.clip(1.0 - height, 0.0, 1.0)
    rgb = np.stack([0.22 + 0.38 * height, 0.24 + 0.40 * height, 0.26 + 0.42 * height], axis=-1)
    rgb -= shadows[:, :, None] * np.array([0.07, 0.07, 0.06])
    rgb += (0.5 + 0.5 * grain)[:, :, None] * np.array([0.03, 0.03, 0.03])
    return _rgba(np.clip(rgb, 0.0, 1.0)), _normal_from_height(height, 2.8)


def _leather_image(size, seed):
    grain = _fbm(size, seed, octaves=6)
    pores = _fbm(size, seed + 17, octaves=8)
    height = grain * 0.55 + np.clip(pores - 0.55, 0.0, 1.0) * 0.45
    mottling = 0.5 + 0.5 * grain
    rgb = np.stack([0.16 + 0.10 * mottling, 0.085 + 0.060 * mottling, 0.048 + 0.035 * mottling], axis=-1)
    rgb -= np.clip(pores - 0.6, 0.0, 1.0)[:, :, None] * np.array([0.05, 0.035, 0.02])
    return _rgba(np.clip(rgb, 0.0, 1.0)), _normal_from_height(height, 1.8)


def _cloth_image(size, seed):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    weave_x = 0.5 + 0.5 * np.sin(TAU * xx / 7.0)
    weave_y = 0.5 + 0.5 * np.sin(TAU * yy / 7.0)
    weave = weave_x * (1.0 - weave_y) + (1.0 - weave_x) * weave_y
    grain = 0.5 + 0.5 * _fbm(size, seed, octaves=7)
    height = weave * 0.55 + grain * 0.45
    mottling = 0.55 + 0.45 * grain
    rgb = np.stack([0.145 + 0.060 * mottling, 0.105 + 0.046 * mottling, 0.078 + 0.034 * mottling], axis=-1)
    rgb += (weave[:, :, None] - 0.5) * np.array([0.040, 0.034, 0.028])
    return _rgba(np.clip(rgb, 0.0, 1.0)), _normal_from_height(height, 1.6)


def _make_material(name, base_color, metallic, roughness, base_image=None, normal_image=None,
                   normal_strength=1.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*base_color, 1.0)
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    if base_image is not None:
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = base_image
        texture.interpolation = "Linear"
        links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    if normal_image is not None:
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = normal_image
        texture.interpolation = "Linear"
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = normal_strength
        links.new(texture.outputs["Color"], normal.inputs["Color"])
        links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    material.diffuse_color = (*base_color, 1.0)
    return material


def create_materials(texture_folder):
    plate, plate_normal = _steel_image(TEXTURE_SIZE, 11, dark=False)
    dark_plate, dark_plate_normal = _steel_image(TEXTURE_SIZE, 23, dark=True)
    mail, mail_normal = _mail_image(TEXTURE_SIZE, 31)
    leather, leather_normal = _leather_image(TEXTURE_SIZE, 41)
    cloth, cloth_normal = _cloth_image(TEXTURE_SIZE, 51)
    images = {
        "T_Armor_Plate": _save_texture("T_Armor_Plate", plate, "sRGB", texture_folder),
        "T_Armor_Plate_Normal": _save_texture("T_Armor_Plate_Normal", plate_normal, "Non-Color", texture_folder),
        "T_Armor_DarkPlate": _save_texture("T_Armor_DarkPlate", dark_plate, "sRGB", texture_folder),
        "T_Armor_DarkPlate_Normal": _save_texture("T_Armor_DarkPlate_Normal", dark_plate_normal, "Non-Color", texture_folder),
        "T_Armor_Mail": _save_texture("T_Armor_Mail", mail, "sRGB", texture_folder),
        "T_Armor_Mail_Normal": _save_texture("T_Armor_Mail_Normal", mail_normal, "Non-Color", texture_folder),
        "T_Armor_Leather": _save_texture("T_Armor_Leather", leather, "sRGB", texture_folder),
        "T_Armor_Leather_Normal": _save_texture("T_Armor_Leather_Normal", leather_normal, "Non-Color", texture_folder),
        "T_Armor_Cloth": _save_texture("T_Armor_Cloth", cloth, "sRGB", texture_folder),
        "T_Armor_Cloth_Normal": _save_texture("T_Armor_Cloth_Normal", cloth_normal, "Non-Color", texture_folder),
    }
    return {
        "plate": _make_material("M_Armor_Plate", (0.40, 0.42, 0.43), 0.75, 0.40,
                                images["T_Armor_Plate"], images["T_Armor_Plate_Normal"], 1.1),
        "plate_dark": _make_material("M_Armor_Plate_Dark", (0.28, 0.30, 0.31), 0.70, 0.48,
                                     images["T_Armor_DarkPlate"], images["T_Armor_DarkPlate_Normal"], 1.1),
        "mail": _make_material("M_Armor_Mail", (0.34, 0.36, 0.37), 0.80, 0.45,
                               images["T_Armor_Mail"], images["T_Armor_Mail_Normal"], 1.3),
        "leather": _make_material("M_Armor_Leather", (0.20, 0.11, 0.06), 0.0, 0.68,
                                  images["T_Armor_Leather"], images["T_Armor_Leather_Normal"], 1.0),
        "leather_dark": _make_material("M_Armor_Leather_Dark", (0.075, 0.045, 0.030), 0.0, 0.78),
        "cloth": _make_material("M_Armor_Cloth", (0.24, 0.15, 0.10), 0.0, 0.92,
                                images["T_Armor_Cloth"], images["T_Armor_Cloth_Normal"], 1.0),
        "cloth_dark": _make_material("M_Armor_Cloth_Dark", (0.10, 0.065, 0.050), 0.0, 0.95),
        "trim": _make_material("M_Armor_Trim", (0.62, 0.44, 0.17), 0.55, 0.35),
        "brass": _make_material("M_Armor_Brass", (0.64, 0.46, 0.18), 0.55, 0.32),
        "steel_edge": _make_material("M_Armor_Steel_Edge", (0.60, 0.62, 0.63), 0.60, 0.30),
        "eye_dark": _make_material("M_Armor_Interior", (0.025, 0.020, 0.018), 0.0, 1.0),
    }




# ----------------------------------------------------------------------------
# Geometry helpers
# ----------------------------------------------------------------------------

def _section(section):
    result = {"z": 0.0, "rx": 0.1, "ry": 0.1, "cx": 0.0, "cy": 0.0,
              "exp": 2.0, "fold": 0.0, "fold_freq": 6.0, "phase": 0.0}
    result.update(section)
    return result


def _profile_point(section, angle):
    cosine, sine = math.cos(angle), math.sin(angle)
    if abs(section["exp"] - 2.0) < 1e-6:
        x = section["rx"] * cosine
        y = section["ry"] * sine
    else:
        power = 2.0 / section["exp"]
        x = section["rx"] * math.copysign(abs(cosine) ** power, cosine)
        y = section["ry"] * math.copysign(abs(sine) ** power, sine)
    fold = section["fold"] * math.sin(section["fold_freq"] * angle + section["phase"])
    return Vector((section["cx"] + x + fold * cosine,
                   section["cy"] + y + fold * sine,
                   section["z"]))


def revolve(name, sections, material, weight_fn, segments=32, angle_start=0.0, angle_end=TAU,
            closed=True, cap_top=False, cap_bottom=False, smooth=True, skip=None,
            thickness=0.0, bevel=0.0, bevel_segments=2):
    sections = [_section(section) for section in sections]
    span = angle_end - angle_start
    count = segments if closed else segments + 1
    step = span / (segments if closed else segments)
    verts = []
    for section in sections:
        for index in range(count):
            angle = angle_start + step * index
            verts.append(_profile_point(section, angle))
    faces = []
    for ring in range(len(sections) - 1):
        lower = ring * count
        upper = (ring + 1) * count
        for index in range(count if closed else count - 1):
            nxt = (index + 1) % count
            angle = angle_start + step * (index + 0.5)
            z_mid = (sections[ring]["z"] + sections[ring + 1]["z"]) * 0.5
            if skip is not None and skip(angle, z_mid):
                continue
            faces.append((lower + index, lower + nxt, upper + nxt, upper + index))
    if cap_bottom and sections:
        # The bottom fan keeps the piece closed when it is a solid plate.
        centre = len(verts)
        section = sections[0]
        verts.append(Vector((section["cx"], section["cy"], section["z"])))
        for index in range(count if closed else count - 1):
            nxt = (index + 1) % count
            faces.append((centre, index, nxt))
    if cap_top and sections:
        centre = len(verts)
        section = sections[-1]
        base = (len(sections) - 1) * count
        verts.append(Vector((section["cx"], section["cy"], section["z"])))
        for index in range(count if closed else count - 1):
            nxt = (index + 1) % count
            faces.append((centre, base + nxt, base + index))
    obj = _obj_from_data(name, verts, faces, material, smooth=smooth)
    assign_weights(obj, weight_fn)
    if thickness > 0.0:
        add_solidify(obj, thickness)
    if bevel > 0.0:
        add_bevel(obj, bevel, bevel_segments)
    return obj


def tube(name, points, radii, material, weight_fn, segments=14, smooth=True,
         cap_start=True, cap_end=True, thickness=0.0, bevel=0.0):
    points = [Vector(point) for point in points]
    if isinstance(radii[0], (int, float)):
        radii = [(float(radius), float(radius)) for radius in radii]
    frames = []
    for index, point in enumerate(points):
        if index == 0:
            tangent = points[1] - point
        elif index == len(points) - 1:
            tangent = point - points[-2]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangent.normalize()
        reference = Vector((0, 1, 0)) if abs(tangent.z) > 0.9 else Vector((0, 0, 1))
        side = tangent.cross(reference)
        if side.length < 1e-6:
            side = tangent.cross(Vector((1, 0, 0)))
        side.normalize()
        normal = side.cross(tangent).normalized()
        frames.append((side, normal))
    verts, faces = [], []
    for index, point in enumerate(points):
        side, normal = frames[index]
        rx, ry = radii[index]
        for step in range(segments):
            angle = TAU * step / segments
            verts.append(point + side * (math.cos(angle) * rx) + normal * (math.sin(angle) * ry))
    for ring in range(len(points) - 1):
        lower = ring * segments
        upper = (ring + 1) * segments
        for step in range(segments):
            nxt = (step + 1) % segments
            faces.append((lower + step, lower + nxt, upper + nxt, upper + step))
    if cap_start:
        centre = len(verts)
        verts.append(points[0])
        for step in range(segments):
            faces.append((centre, (step + 1) % segments, step))
    if cap_end:
        centre = len(verts)
        base = (len(points) - 1) * segments
        verts.append(points[-1])
        for step in range(segments):
            faces.append((centre, base + step, base + (step + 1) % segments))
    obj = _obj_from_data(name, verts, faces, material, smooth=smooth)
    assign_weights(obj, weight_fn)
    if thickness > 0.0:
        add_solidify(obj, thickness)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    return obj


def rect_tube(name, points, width, thickness, material, weight_fn, up_hint=Vector((0, 0, 1))):
    points = [Vector(point) for point in points]
    verts, faces = [], []
    for index, point in enumerate(points):
        if index == 0:
            tangent = points[1] - point
        elif index == len(points) - 1:
            tangent = point - points[-2]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangent.normalize()
        side = tangent.cross(up_hint)
        if side.length < 1e-6:
            side = tangent.cross(Vector((1, 0, 0)))
        side.normalize()
        normal = side.cross(tangent).normalized()
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append(point + side * (sx * width * 0.5) + normal * (sy * thickness * 0.5))
    for ring in range(len(points) - 1):
        lower = ring * 4
        upper = (ring + 1) * 4
        for step in range(4):
            nxt = (step + 1) % 4
            faces.append((lower + step, lower + nxt, upper + nxt, upper + step))
    faces.append((0, 3, 2, 1))
    last = (len(points) - 1) * 4
    faces.append((last, last + 1, last + 2, last + 3))
    obj = _obj_from_data(name, verts, faces, material, smooth=False)
    assign_weights(obj, weight_fn)
    add_bevel(obj, min(width, thickness) * 0.35, 1)
    return obj


def torus_ring(name, center, major_x, major_y, minor, material, weight_fn, axis="Z",
               segments=28, sides=8):
    centre = Vector(center)
    verts = []
    for index in range(segments):
        angle = TAU * index / segments
        if axis == "Z":
            ring_centre = centre + Vector((major_x * math.cos(angle), major_y * math.sin(angle), 0.0))
            radial = Vector((math.cos(angle), math.sin(angle), 0.0))
            binormal = Vector((0, 0, 1))
        else:  # axis X, ring in YZ
            ring_centre = centre + Vector((0.0, major_x * math.cos(angle), major_y * math.sin(angle)))
            radial = Vector((0.0, math.cos(angle), math.sin(angle)))
            binormal = Vector((1, 0, 0))
        for side in range(sides):
            phi = TAU * side / sides
            verts.append(ring_centre + radial * (math.cos(phi) * minor) + binormal * (math.sin(phi) * minor))
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        for side in range(sides):
            side_next = (side + 1) % sides
            faces.append((index * sides + side, nxt * sides + side,
                          nxt * sides + side_next, index * sides + side_next))
    obj = _obj_from_data(name, verts, faces, material, smooth=True)
    assign_weights(obj, weight_fn)
    return obj


def dome(name, center, radius_x, radius_y, height, material, weight_fn, basis=None,
         segments=20, rings=6, thickness=0.006, smooth=True):
    basis = basis or Matrix.Identity(3)
    centre = Vector(center)
    verts = []
    for ring in range(rings + 1):
        phi = (math.pi * 0.5) * ring / rings
        radial = math.sin(phi)
        vertical = math.cos(phi)
        for index in range(segments):
            angle = TAU * index / segments
            local = Vector((radius_x * radial * math.cos(angle),
                            radius_y * radial * math.sin(angle),
                            height * vertical))
            verts.append(centre + basis @ local)
    faces = []
    for ring in range(rings):
        lower = ring * segments
        upper = (ring + 1) * segments
        for index in range(segments):
            nxt = (index + 1) % segments
            faces.append((lower + index, lower + nxt, upper + nxt, upper + index))
    obj = _obj_from_data(name, verts, faces, material, smooth=smooth)
    assign_weights(obj, weight_fn)
    if thickness > 0.0:
        add_solidify(obj, thickness)
    return obj


def box(name, center, size, material, weight_fn, rotation=None, bevel=0.004):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    scale = Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
    transform = (rotation.to_matrix().to_4x4() if isinstance(rotation, Euler) else
                 rotation if rotation is not None else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ transform @ scale, verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(material)
    assign_weights(obj, weight_fn)
    if bevel > 0.0:
        add_bevel(obj, bevel, 2)
    return obj


def rivet(name, center, normal, material, weight_fn, radius=0.006):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=radius)
    normal = Vector(normal).normalized()
    side = normal.cross(Vector((0, 0, 1)))
    if side.length < 1e-6:
        side = normal.cross(Vector((1, 0, 0)))
    side.normalize()
    up = side.cross(normal).normalized()
    basis = Matrix((side, up, normal)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ basis @ Matrix.Diagonal(Vector((1, 1, 0.45, 1))),
                        verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(material)
    assign_weights(obj, weight_fn)
    return obj


# ----------------------------------------------------------------------------
# Skinning recipes
# ----------------------------------------------------------------------------

def _bone_point(rig, name):
    bone = rig.data.bones[name]
    return bone.head_local.copy(), bone.tail_local.copy()


def _segment_distance(point, head, tail):
    along = tail - head
    length_squared = along.length_squared
    if length_squared < 1e-10:
        return (point - head).length
    t = max(0.0, min(1.0, (point - head).dot(along) / length_squared))
    return (point - (head + along * t)).length


def _chain_weights(point, rig, names, sigma=0.07):
    values = {}
    for name in names:
        head, tail = _bone_point(rig, name)
        distance = _segment_distance(point, head, tail)
        values[name] = math.exp(-((distance / sigma) ** 2))
    total = sum(values.values())
    if total <= 1e-9:
        return {names[0]: 1.0}
    return {name: value / total for name, value in values.items()}


def torso_weights(point):
    z = point.z
    if z >= 1.56:
        t = smoothstep(1.56, 1.62, z)
        return {"spine_03": 1.0 - 0.45 * t, "neck_01": 0.45 * t}
    if z >= 1.38:
        return {"spine_03": 1.0}
    if z >= 1.20:
        t = smoothstep(1.20, 1.38, z)
        return {"spine_02": 1.0 - t, "spine_03": t}
    if z >= 1.06:
        t = smoothstep(1.06, 1.20, z)
        return {"spine_01": 1.0 - t, "spine_02": t}
    if z >= 0.96:
        t = smoothstep(0.96, 1.06, z)
        return {"pelvis": 1.0 - t, "spine_01": t}
    return {"pelvis": 1.0}


def stiff_torso_weights(point):
    """Cuirass weights: broad rigid bands rather than a soft shirt."""
    z = point.z
    if z >= 1.42:
        return {"spine_03": 1.0}
    if z >= 1.24:
        return {"spine_02": 0.72, "spine_03": 0.28}
    if z >= 1.08:
        return {"spine_01": 0.78, "spine_02": 0.22}
    return {"pelvis": 0.65, "spine_01": 0.35}


def arm_weights(rig, side):
    names = [f"upperarm_{side}", f"lowerarm_{side}", f"hand_{side}"]
    return lambda point: _chain_weights(point, rig, names, 0.075)


def arm_stiff_weights(rig, side):
    wrist = _bone_point(rig, f"hand_{side}")[0]
    elbow = _bone_point(rig, f"lowerarm_{side}")[0]
    upper = f"upperarm_{side}"
    lower = f"lowerarm_{side}"
    hand = f"hand_{side}"
    def weights(point):
        if point.x * (1 if side == "l" else -1) >= abs(wrist.x) - 0.01:
            return {hand: 1.0}
        if point.x * (1 if side == "l" else -1) >= abs(elbow.x) - 0.035:
            return {lower: 1.0}
        return {upper: 1.0}
    return weights


def leg_weights(rig, side):
    names = [f"thigh_{side}", f"calf_{side}", f"foot_{side}"]
    return lambda point: _chain_weights(point, rig, names, 0.085)


def skirt_weights(side, top=1.02, bottom=0.18, thigh_floor=0.62):
    def weights(point):
        t = smoothstep(bottom, top, point.z)
        pelvis = t
        thigh = 1.0 - t
        # The hem keeps a meaningful thigh share so legs lift cloth rather than
        # leaving it pinned to the pelvis.
        thigh = max(thigh, thigh_floor * (1.0 - t))
        total = pelvis + thigh
        return {"pelvis": pelvis / total, f"thigh_{side}": thigh / total}
    return weights


def head_weights(point):
    if point.z >= 1.60:
        return {"Head": 1.0}
    if point.z >= 1.50:
        t = smoothstep(1.50, 1.60, point.z)
        return {"neck_01": 1.0 - t * 0.35, "spine_03": t * 0.35}
    return {"spine_03": 1.0}


def hood_weights(point):
    if point.z >= 1.63:
        return {"Head": 1.0}
    if point.z >= 1.54:
        t = smoothstep(1.54, 1.63, point.z)
        return {"Head": t, "neck_01": 1.0 - t}
    t = smoothstep(1.44, 1.54, point.z)
    return {"neck_01": t * 0.6, "spine_03": 1.0 - t * 0.6}


def hand_weights(rig, side):
    lower = _bone_point(rig, f"lowerarm_{side}")
    hand = _bone_point(rig, f"hand_{side}")
    wrist_x = hand[0].x
    sign = 1.0 if side == "l" else -1.0
    def weights(point):
        distance = (point.x * sign) - (wrist_x * sign)
        if distance < -0.015:
            return {f"lowerarm_{side}": 1.0}
        if distance < 0.025:
            t = smoothstep(-0.015, 0.025, distance)
            return {f"lowerarm_{side}": 1.0 - t, f"hand_{side}": t}
        return {f"hand_{side}": 1.0}
    return weights


# ----------------------------------------------------------------------------
# Plate
# ----------------------------------------------------------------------------

def _side_sign(side):
    return 1.0 if side == "l" else -1.0


def _plate_helm(rig, mats):
    parts = []
    weight = lambda point: {"Head": 1.0}

    # Sallet: a high dome whose lower edge dips at the back and lifts over the
    # brow, leaving the face open for the bow cheek anchor.
    segments, rings = 36, 7
    verts = []
    verts.append(Vector((0.0, 0.015, 1.918)))
    for ring in range(1, rings + 1):
        t = ring / rings
        for index in range(segments):
            angle = TAU * index / segments
            bottom = 1.655 - 0.050 * math.sin(angle)
            z = bottom + (1.918 - bottom) * t
            radial = (1.0 - t) ** 0.55
            rx = 0.012 + 0.142 * radial
            ry = 0.014 + 0.154 * radial
            verts.append(Vector((rx * math.cos(angle), 0.015 + ry * math.sin(angle), z)))
    faces = []
    for index in range(segments):
        faces.append((0, 1 + index, 1 + (index + 1) % segments))
    for ring in range(rings - 1):
        lower = 1 + ring * segments
        upper = 1 + (ring + 1) * segments
        for index in range(segments):
            nxt = (index + 1) % segments
            faces.append((lower + index, lower + nxt, upper + nxt, upper + index))
    parts.append(_obj_from_data("PlateHelmDome", verts, faces, mats["plate_dark"], smooth=True))
    assign_weights(parts[-1], weight)
    add_solidify(parts[-1], 0.008)
    add_bevel(parts[-1], 0.002, 2)

    parts.append(revolve("PlateHelmBrow",
                         [{"z": 1.700, "rx": 0.150, "ry": 0.162, "cy": 0.012},
                          {"z": 1.735, "rx": 0.154, "ry": 0.166, "cy": 0.012},
                          {"z": 1.765, "rx": 0.149, "ry": 0.160, "cy": 0.012}],
                         mats["plate"], weight, segments=30,
                         angle_start=-math.pi * 0.90, angle_end=-math.pi * 0.10,
                         closed=False, thickness=0.007, bevel=0.0015, smooth=True))
    for side, start, end in (("l", -math.pi * 0.90, -math.pi * 0.68),
                             ("r", -math.pi * 0.32, -math.pi * 0.10)):
        # The lower cheek stays open so the bowstring can reach the actual
        # cheek anchor without passing through a steel plate.
        parts.append(revolve("PlateCheek_" + side,
                             [{"z": 1.660, "rx": 0.135, "ry": 0.150, "cy": 0.008},
                              {"z": 1.700, "rx": 0.143, "ry": 0.157, "cy": 0.010},
                              {"z": 1.745, "rx": 0.148, "ry": 0.161, "cy": 0.011}],
                             mats["plate"], weight, segments=12,
                             angle_start=start, angle_end=end, closed=False,
                             thickness=0.007, bevel=0.0015, smooth=True))
    parts.append(revolve("PlateNeckGuardA",
                         [{"z": 1.545, "rx": 0.155, "ry": 0.150, "cy": 0.010},
                          {"z": 1.600, "rx": 0.162, "ry": 0.158, "cy": 0.012},
                          {"z": 1.650, "rx": 0.166, "ry": 0.163, "cy": 0.014}],
                         mats["plate_dark"], weight, segments=24,
                         angle_start=math.pi * 0.10, angle_end=math.pi * 0.90,
                         closed=False, thickness=0.007, bevel=0.0015, smooth=True))
    parts.append(revolve("PlateNeckGuardB",
                         [{"z": 1.500, "rx": 0.172, "ry": 0.166, "cy": 0.012},
                          {"z": 1.548, "rx": 0.166, "ry": 0.160, "cy": 0.010}],
                         mats["plate"], weight, segments=24,
                         angle_start=math.pi * 0.12, angle_end=math.pi * 0.88,
                         closed=False, thickness=0.007, bevel=0.0015, smooth=True))
    parts.append(rect_tube("PlateNasal",
                           [(0.0, -0.148, 1.805), (0.0, -0.160, 1.720),
                            (0.0, -0.166, 1.640)],
                           0.026, 0.014, mats["steel_edge"], weight,
                           up_hint=Vector((1, 0, 0))))
    parts.append(tube("PlateComb",
                      [(0.0, -0.120, 1.862), (0.0, -0.055, 1.908), (0.0, 0.020, 1.918),
                       (0.0, 0.090, 1.900), (0.0, 0.150, 1.850)],
                      [(0.011, 0.006)] * 5, mats["steel_edge"], weight,
                      segments=8, smooth=True))
    for index in range(7):
        angle = -math.pi * 0.90 + (math.pi * 0.80) * index / 6.0
        point = Vector((0.154 * math.cos(angle), 0.012 + 0.166 * math.sin(angle), 1.720))
        parts.append(rivet("PlateBrowRivet%d" % index, point,
                           (math.cos(angle), math.sin(angle), 0.15), mats["brass"], weight))
    for side, base_angle in (("r", -math.pi * 0.86), ("l", -math.pi * 0.14)):
        for index in range(2):
            angle = base_angle + (index * 0.06 if side == "l" else -index * 0.06)
            point = Vector((0.145 * math.cos(angle), 0.010 + 0.159 * math.sin(angle), 1.685 + index * 0.035))
            parts.append(rivet("PlateCheekRivet_%s_%d" % (side, index), point,
                               (math.cos(angle), math.sin(angle), 0.0), mats["brass"], weight, 0.005))
    return finish_piece("Armor_Plate_Head", parts, rig, 0.42)


def _plate_chest(rig, mats):
    parts = []
    sections = [
        {"z": 1.555, "rx": 0.135, "ry": 0.108, "cy": 0.020, "exp": 2.5},
        {"z": 1.525, "rx": 0.198, "ry": 0.150, "cy": 0.020, "exp": 2.5},
        {"z": 1.475, "rx": 0.236, "ry": 0.170, "cy": 0.018, "exp": 2.5},
        {"z": 1.400, "rx": 0.246, "ry": 0.178, "cy": 0.015, "exp": 2.5},
        {"z": 1.310, "rx": 0.226, "ry": 0.168, "cy": 0.015, "exp": 2.4},
        {"z": 1.220, "rx": 0.198, "ry": 0.148, "cy": 0.015, "exp": 2.4},
        {"z": 1.150, "rx": 0.185, "ry": 0.138, "cy": 0.018, "exp": 2.4},
        {"z": 1.080, "rx": 0.190, "ry": 0.142, "cy": 0.020, "exp": 2.4},
        {"z": 1.010, "rx": 0.205, "ry": 0.152, "cy": 0.022, "exp": 2.4},
    ]
    weight = stiff_torso_weights
    parts.append(revolve("PlateCuirass", sections, mats["plate"], weight, segments=40,
                         closed=True, smooth=True, thickness=0.010, bevel=0.0025))
    # Raised keel and paired flutes on the breastplate.
    keel = [(0.0, -0.158, 1.500), (0.0, -0.166, 1.390), (0.0, -0.153, 1.280),
            (0.0, -0.135, 1.170), (0.0, -0.126, 1.090)]
    parts.append(tube("PlateKeel", keel, [(0.013, 0.010)] * 5, mats["steel_edge"], weight,
                      segments=8, smooth=True))
    for side in (-1.0, 1.0):
        flute = [(side * 0.085, -0.156, 1.480), (side * 0.100, -0.162, 1.370),
                 (side * 0.088, -0.146, 1.260), (side * 0.070, -0.128, 1.160)]
        parts.append(tube("PlateFlute", flute, [(0.006, 0.004)] * 4, mats["steel_edge"], weight,
                          segments=6, smooth=True))
    parts.append(revolve("PlatePlackart",
                         [{"z": 1.000, "rx": 0.208, "ry": 0.154, "cy": 0.022, "exp": 2.4},
                          {"z": 1.045, "rx": 0.202, "ry": 0.150, "cy": 0.021, "exp": 2.4},
                          {"z": 1.090, "rx": 0.194, "ry": 0.145, "cy": 0.020, "exp": 2.4}],
                         mats["plate_dark"], stitch_weight, segments=36, closed=True,
                         smooth=True, thickness=0.009, bevel=0.002))
    for index in range(3):
        z = 0.885 + index * 0.052
        rx = 0.224 + (2 - index) * 0.006
        ry = 0.160 + (2 - index) * 0.004
        for start, end in ((-math.pi * 0.5 - 1.20, -math.pi * 0.5 + 1.20),
                           (math.pi * 0.5 - 1.10, math.pi * 0.5 + 1.10)):
            parts.append(revolve("PlateFaulds",
                                 [{"z": z, "rx": rx, "ry": ry, "cy": 0.020, "exp": 2.4},
                                  {"z": z + 0.045, "rx": rx - 0.006, "ry": ry - 0.004, "cy": 0.020, "exp": 2.4}],
                                 mats["plate"], pelvis_weight, segments=22,
                                 angle_start=start, angle_end=end, closed=False,
                                 smooth=True, thickness=0.008, bevel=0.0015))
    parts.append(torus_ring("PlateGorget", (0.0, 0.020, 1.552), 0.112, 0.100, 0.017,
                            mats["plate"], spine_top_weight, segments=28, sides=8))
    parts.append(revolve("PlateBevor",
                         [{"z": 1.480, "rx": 0.150, "ry": 0.132, "cy": 0.018},
                          {"z": 1.525, "rx": 0.142, "ry": 0.122, "cy": 0.018},
                          {"z": 1.560, "rx": 0.128, "ry": 0.108, "cy": 0.018}],
                         mats["plate"], spine_top_weight, segments=16,
                         angle_start=-math.pi * 0.82, angle_end=-math.pi * 0.18,
                         closed=False, smooth=True, thickness=0.009, bevel=0.0015))
    for side in (-1.0, 1.0):
        # Layered pauldron domes and a rolled rim.
        for index, (dx, dz, radius, height) in enumerate(((0.000, 0.000, 0.118, 0.105),
                                                          (0.024, -0.035, 0.122, 0.078),
                                                          (0.046, -0.067, 0.120, 0.060))):
            parts.append(dome("PlatePauldron", (side * (0.208 + dx), 0.055, 1.480 + dz),
                              radius, radius * 0.84, height, mats["plate"] if index == 0 else mats["plate_dark"],
                              pauldron_weight(side), segments=20, rings=5, thickness=0.008))
        parts.append(torus_ring("PlatePauldronRim", (side * 0.270, 0.055, 1.445),
                                0.078, 0.070, 0.008, mats["steel_edge"],
                                lambda point, s=side: {f"upperarm_{'l' if s > 0 else 'r'}": 1.0},
                                axis="X", segments=20, sides=6))
        # Rerebrace, couter and vambrace.
        sign = side
        arm_weight = arm_stiff_weights(rig, "l" if side > 0 else "r")
        parts.append(tube("PlateRerebrace",
                          [(sign * 0.245, 0.065, 1.455), (sign * 0.320, 0.067, 1.455),
                           (sign * 0.400, 0.069, 1.455)],
                          [(0.074, 0.070), (0.070, 0.066), (0.062, 0.060)],
                          mats["plate"], arm_weight, segments=14, smooth=True, thickness=0.006))
        elbow_basis = Matrix(((0, 0, sign), (1, 0, 0), (0, 1, 0))).transposed()
        parts.append(dome("PlateCouter", (sign * 0.447, 0.070, 1.455),
                          0.082, 0.070, 0.052, mats["plate"], couter_weight(rig, sign),
                          basis=elbow_basis, segments=18, rings=4, thickness=0.007))
        parts.append(tube("PlateVambrace",
                          [(sign * 0.472, 0.068, 1.455), (sign * 0.550, 0.066, 1.455),
                           (sign * 0.640, 0.064, 1.455)],
                          [(0.062, 0.058), (0.056, 0.052), (0.052, 0.048)],
                          mats["plate"], arm_weight, segments=14, smooth=True, thickness=0.006))
        parts.append(torus_ring("PlateArmStrap", (sign * 0.335, 0.067, 1.455), 0.070, 0.067, 0.007,
                                mats["leather_dark"],
                                lambda point, s=sign: {f"upperarm_{'l' if s > 0 else 'r'}": 1.0},
                                axis="X", segments=16, sides=6))
        parts.append(torus_ring("PlateVambraceStrap", (sign * 0.585, 0.065, 1.455), 0.056, 0.053, 0.006,
                                mats["leather_dark"],
                                lambda point, s=sign: {f"lowerarm_{'l' if s > 0 else 'r'}": 1.0},
                                axis="X", segments=16, sides=6))
        for index in range(4):
            angle = -0.5 + index * 0.33
            point = Vector((sign * 0.31, 0.067 + 0.071 * math.cos(angle), 1.455 + 0.071 * math.sin(angle)))
            parts.append(rivet("PlateArmRivet", point, (0.0, math.cos(angle), math.sin(angle)),
                               mats["brass"], arm_weight, 0.005))
    # Diagonal leather harness across the breastplate.
    harness = [(-0.150, -0.118, 1.500), (0.020, -0.170, 1.350),
               (0.135, -0.132, 1.175), (0.105, -0.130, 1.050)]
    parts.append(rect_tube("PlateHarness", harness, 0.036, 0.009, mats["leather_dark"],
                           torso_weights, up_hint=Vector((0, 0, 1))))
    parts.append(box("PlateBuckle", (0.010, -0.176, 1.330), (0.055, 0.016, 0.050),
                     mats["brass"], torso_weights, bevel=0.006))
    for index in range(6):
        angle = -math.pi * 0.5 + (index - 2.5) * 0.20
        point = Vector((0.200 * math.cos(angle), 0.020 + 0.153 * math.sin(angle), 1.045))
        parts.append(rivet("PlatePlackartRivet", point, (math.cos(angle), math.sin(angle), 0.0),
                           mats["brass"], torso_weights, 0.005))
    return finish_piece("Armor_Plate_Chest", parts, rig, 0.55)


def stitch_weight(point):
    return stiff_torso_weights(point)


def pelvis_weight(point):
    return {"pelvis": 1.0}


def spine_top_weight(point):
    return {"spine_03": 0.75, "neck_01": 0.25}


def pauldron_weight(side):
    bone = "upperarm_l" if side > 0 else "upperarm_r"
    clavicle = "clavicle_l" if side > 0 else "clavicle_r"
    return lambda point: {bone: 0.72, clavicle: 0.28}


def couter_weight(rig, sign):
    side = "l" if sign > 0 else "r"
    return lambda point: {f"upperarm_{side}": 0.5, f"lowerarm_{side}": 0.5}


def _plate_hands(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        hand = f"hand_{side}"
        lower = f"lowerarm_{side}"
        parts.append(tube("PlateCuff",
                          [(sign * 0.620, 0.065, 1.455), (sign * 0.665, 0.065, 1.455),
                           (sign * 0.690, 0.065, 1.455)],
                          [(0.064, 0.060), (0.060, 0.056), (0.058, 0.054)],
                          mats["plate"], lambda point, s=sign: {lower: 1.0},
                          segments=14, smooth=True, thickness=0.006))
        parts.append(torus_ring("PlateCuffStrap", (sign * 0.638, 0.065, 1.455),
                                0.062, 0.058, 0.006, mats["leather_dark"],
                                lambda point, s=sign: {lower: 1.0}, axis="X", segments=16, sides=6))
        parts.append(dome("PlateHandBack", (sign * 0.742, 0.065, 1.452),
                          0.058, 0.047, 0.022, mats["plate"],
                          lambda point, s=sign: {hand: 1.0}, segments=16, rings=4, thickness=0.006))
        parts.append(box("PlatePalm", (sign * 0.745, 0.065, 1.438), (0.108, 0.088, 0.012),
                         mats["leather_dark"], lambda point, s=sign: {hand: 1.0}, bevel=0.004))
        for index, (y, width) in enumerate(((0.029, 0.020), (0.058, 0.022),
                                            (0.086, 0.020), (0.112, 0.017))):
            parts.append(box("PlateKnuckle", (sign * 0.790, y, 1.470), (0.022, width, 0.014),
                             mats["steel_edge"], lambda point, s=sign: {hand: 1.0}, bevel=0.004))
        # Articulated finger lames.  Each phalanx gets a small capping plate
        # weighted to its own bone so the authored grip closes cleanly.
        for finger in ("index", "middle", "ring", "pinky"):
            for segment in ("01", "02", "03"):
                name = f"{finger}_{segment}_{side}"
                head = rig.data.bones[name].head_local.copy()
                tail = rig.data.bones[name].tail_local.copy()
                start = head.lerp(tail, 0.10)
                end = head.lerp(tail, 0.88)
                start.z += 0.009
                end.z += 0.009
                parts.append(tube("PlateFingerLame", [start, end],
                                  [(0.011, 0.009), (0.010, 0.008)], mats["plate"],
                                  lambda point, bone=name: {bone: 1.0}, segments=8,
                                  smooth=True, thickness=0.002))
        for segment in ("01", "02", "03"):
            name = f"thumb_{segment}_{side}"
            head = rig.data.bones[name].head_local.copy()
            tail = rig.data.bones[name].tail_local.copy()
            start = head.lerp(tail, 0.10)
            end = head.lerp(tail, 0.88)
            start.z += 0.008
            end.z += 0.008
            parts.append(tube("PlateThumbLame", [start, end],
                              [(0.012, 0.010), (0.010, 0.009)], mats["plate"],
                              lambda point, bone=name: {bone: 1.0}, segments=8,
                              smooth=True, thickness=0.002))
    return finish_piece("Armor_Plate_Hands", parts, rig, 0.33)


def _plate_legs(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        thigh = f"thigh_{side}"
        calf = f"calf_{side}"
        # Cuisse follows the thigh, with a raised front ridge.
        parts.append(tube("PlateCuisse",
                          [(sign * 0.091, 0.036, 0.975), (sign * 0.091, 0.040, 0.880),
                           (sign * 0.091, 0.042, 0.770), (sign * 0.091, 0.038, 0.660),
                           (sign * 0.091, 0.036, 0.585)],
                          [(0.100, 0.095), (0.098, 0.092), (0.091, 0.086),
                           (0.085, 0.080), (0.082, 0.077)],
                          mats["plate"], lambda point, bone=thigh: {bone: 1.0},
                          segments=16, smooth=True, thickness=0.007))
        parts.append(tube("PlateCuisseRidge",
                          [(sign * 0.091, -0.065, 0.955), (sign * 0.091, -0.058, 0.800),
                           (sign * 0.091, -0.052, 0.620)],
                          [(0.011, 0.007)] * 3, mats["steel_edge"],
                          lambda point, bone=thigh: {bone: 1.0}, segments=6, smooth=True))
        knee_basis = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
        parts.append(dome("PlatePoleyn", (sign * 0.091, 0.005, 0.552),
                          0.088, 0.078, 0.062, mats["plate"],
                          lambda point, s=side: {f"thigh_{s}": 0.5, f"calf_{s}": 0.5},
                          basis=knee_basis, segments=18, rings=4, thickness=0.007))
        parts.append(box("PlatePoleynFan", (sign * 0.165, 0.025, 0.550), (0.018, 0.085, 0.105),
                         mats["steel_edge"],
                         lambda point, s=side: {f"thigh_{s}": 0.45, f"calf_{s}": 0.55},
                         bevel=0.005))
        parts.append(tube("PlateGreave",
                          [(sign * 0.091, 0.050, 0.525), (sign * 0.091, 0.062, 0.430),
                           (sign * 0.091, 0.075, 0.310), (sign * 0.091, 0.085, 0.185),
                           (sign * 0.091, 0.089, 0.115)],
                          [(0.080, 0.075), (0.077, 0.072), (0.071, 0.067),
                           (0.063, 0.060), (0.059, 0.056)],
                          mats["plate"], lambda point, bone=calf: {bone: 1.0},
                          segments=16, smooth=True, thickness=0.007))
        parts.append(tube("PlateGreaveRidge",
                          [(sign * 0.091, -0.015, 0.500), (sign * 0.091, 0.000, 0.330),
                           (sign * 0.091, 0.020, 0.150)],
                          [(0.010, 0.006)] * 3, mats["steel_edge"],
                          lambda point, bone=calf: {bone: 1.0}, segments=6, smooth=True))
        # Two overlapping tassets on the front/outside of each thigh.
        for index in range(2):
            start = -math.pi * 0.5 + (0.15 if sign > 0 else -0.62)
            end = -math.pi * 0.5 + (0.62 if sign > 0 else -0.15)
            z = 0.955 - index * 0.070
            parts.append(revolve("PlateTasset",
                                 [{"z": z - 0.080, "rx": 0.206 + index * 0.006,
                                   "ry": 0.158 + index * 0.005, "cy": 0.020, "exp": 2.3},
                                  {"z": z, "rx": 0.196 + index * 0.006,
                                   "ry": 0.150 + index * 0.005, "cy": 0.020, "exp": 2.3}],
                                 mats["plate"], lambda point, s=side: {f"thigh_{s}": 0.82, "pelvis": 0.18},
                                 segments=12, angle_start=start, angle_end=end, closed=False,
                                 smooth=True, thickness=0.008, bevel=0.0015))
        parts.append(torus_ring("PlateThighStrap", (sign * 0.091, 0.040, 0.875),
                                0.095, 0.090, 0.007, mats["leather_dark"],
                                lambda point, bone=thigh: {bone: 1.0}, axis="Z", segments=18, sides=6))
        parts.append(torus_ring("PlateCalfStrap", (sign * 0.091, 0.070, 0.330),
                                0.074, 0.071, 0.006, mats["leather_dark"],
                                lambda point, bone=calf: {bone: 1.0}, axis="Z", segments=18, sides=6))
        for index in range(3):
            point = Vector((sign * 0.091, -0.060, 0.930 - index * 0.095))
            parts.append(rivet("PlateCuisseRivet", point, (0, -1, 0), mats["brass"],
                               lambda point, bone=thigh: {bone: 1.0}, 0.005))
    return finish_piece("Armor_Plate_Legs", parts, rig, 0.46)


def _plate_feet(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        foot = f"foot_{side}"
        ball = f"ball_{side}"
        parts.append(box("PlateSole", (sign * 0.091, -0.020, 0.012), (0.105, 0.300, 0.020),
                         mats["plate_dark"], lambda point, bone=foot: {bone: 1.0}, bevel=0.006))
        lames = ((0.075, 0.105, 0.100, foot), (0.010, 0.090, 0.085, foot),
                 (-0.055, 0.075, 0.070, ball), (-0.115, 0.062, 0.058, ball),
                 (-0.165, 0.050, 0.046, ball))
        for index, (y, z, height, bone) in enumerate(lames):
            parts.append(box("PlateSabatonLame", (sign * 0.091, y, z),
                             (0.110, 0.075, height), mats["plate"],
                             lambda point, b=bone: {b: 1.0},
                             rotation=Euler((0.18 if index < 3 else 0.05, 0, 0)), bevel=0.004))
        parts.append(box("PlateHeel", (sign * 0.091, 0.118, 0.055), (0.100, 0.070, 0.075),
                         mats["plate_dark"], lambda point, bone=foot: {bone: 1.0}, bevel=0.006))
        parts.append(box("PlateToeCap", (sign * 0.091, -0.195, 0.032), (0.085, 0.060, 0.030),
                         mats["steel_edge"], lambda point, bone=ball: {bone: 1.0}, bevel=0.005))
        parts.append(torus_ring("PlateAnkleCuff", (sign * 0.091, 0.080, 0.130),
                                0.067, 0.063, 0.008, mats["steel_edge"],
                                lambda point, s=side: {f"foot_{s}": 0.8, f"calf_{s}": 0.2},
                                axis="Z", segments=16, sides=6))
        for index in range(2):
            parts.append(rivet("PlateSabatonRivet", (sign * 0.091, 0.020 - index * 0.10, 0.105),
                               (0, 0, 1), mats["brass"],
                               lambda point, b=foot: {b: 1.0}, 0.004))
    return finish_piece("Armor_Plate_Feet", parts, rig, 0.30)


# ----------------------------------------------------------------------------
# Mail
# ----------------------------------------------------------------------------

def _mail_coif(rig, mats):
    parts = []
    def opening(angle, z):
        if z < 1.555 or z > 1.845:
            return False
        front = -math.pi * 0.5
        difference = abs((angle - front + math.pi) % TAU - math.pi)
        half = 0.36 + 0.16 * smoothstep(1.60, 1.76, z) - 0.12 * smoothstep(1.80, 1.85, z)
        return difference < half

    sections = [
        {"z": 1.435, "rx": 0.190, "ry": 0.175, "cy": 0.030},
        {"z": 1.485, "rx": 0.178, "ry": 0.172, "cy": 0.026},
        {"z": 1.530, "rx": 0.160, "ry": 0.163, "cy": 0.022},
        {"z": 1.580, "rx": 0.148, "ry": 0.158, "cy": 0.018},
        {"z": 1.640, "rx": 0.146, "ry": 0.160, "cy": 0.014},
        {"z": 1.710, "rx": 0.148, "ry": 0.163, "cy": 0.010},
        {"z": 1.780, "rx": 0.138, "ry": 0.155, "cy": 0.010},
        {"z": 1.835, "rx": 0.112, "ry": 0.132, "cy": 0.010},
        {"z": 1.875, "rx": 0.070, "ry": 0.085, "cy": 0.012},
        {"z": 1.895, "rx": 0.020, "ry": 0.028, "cy": 0.014},
    ]
    parts.append(revolve("MailCoif", sections, mats["mail"], hood_weights, segments=40,
                         closed=True, skip=opening, smooth=True, thickness=0.006))
    parts.append(torus_ring("MailCoifBand", (0.0, 0.010, 1.782), 0.142, 0.158, 0.012,
                            mats["plate"], lambda point: {"Head": 1.0}, segments=30, sides=7))
    parts.append(rect_tube("MailCoifNasal",
                           [(0.0, -0.146, 1.800), (0.0, -0.155, 1.720),
                            (0.0, -0.159, 1.625)],
                           0.022, 0.012, mats["plate"], lambda point: {"Head": 1.0},
                           up_hint=Vector((1, 0, 0))))
    parts.append(box("MailCoifClasp", (0.0, -0.172, 1.505), (0.042, 0.018, 0.030),
                     mats["brass"], hood_weights, bevel=0.006))
    for index in range(6):
        angle = -math.pi * 0.86 + math.pi * 0.72 * index / 5.0
        point = Vector((0.142 * math.cos(angle), 0.010 + 0.158 * math.sin(angle), 1.782))
        parts.append(rivet("MailCoifRivet", point, (math.cos(angle), math.sin(angle), 0.0),
                           mats["brass"], lambda point: {"Head": 1.0}, 0.005))
    return finish_piece("Armor_Mail_Head", parts, rig, 0.30)


def _mail_hauberk(rig, mats):
    parts = []
    sections = [
        {"z": 1.560, "rx": 0.132, "ry": 0.110, "cy": 0.020},
        {"z": 1.530, "rx": 0.195, "ry": 0.148, "cy": 0.020},
        {"z": 1.480, "rx": 0.236, "ry": 0.172, "cy": 0.018},
        {"z": 1.400, "rx": 0.242, "ry": 0.178, "cy": 0.015},
        {"z": 1.300, "rx": 0.224, "ry": 0.166, "cy": 0.015},
        {"z": 1.200, "rx": 0.205, "ry": 0.154, "cy": 0.015},
        {"z": 1.120, "rx": 0.194, "ry": 0.146, "cy": 0.018},
        {"z": 1.040, "rx": 0.201, "ry": 0.152, "cy": 0.020},
        {"z": 0.960, "rx": 0.216, "ry": 0.162, "cy": 0.022},
    ]
    parts.append(revolve("MailHauberk", sections, mats["mail"], torso_weights, segments=40,
                         closed=True, smooth=True, thickness=0.006))
    for side in ("l", "r"):
        sign = _side_sign(side)
        start = (-math.pi * 0.5 + 0.02) if sign > 0 else (-math.pi * 0.5 - 1.14)
        end = (-math.pi * 0.5 + 1.14) if sign > 0 else (-math.pi * 0.5 - 0.02)
        for face in ("front", "back"):
            if face == "back":
                start = (math.pi * 0.5 - 1.14) if sign > 0 else (math.pi * 0.5 + 0.02)
                end = (math.pi * 0.5 - 0.02) if sign > 0 else (math.pi * 0.5 + 1.14)
            parts.append(revolve("MailSkirt", 
                                 [{"z": 0.800, "rx": 0.242, "ry": 0.182, "cy": 0.022},
                                  {"z": 0.880, "rx": 0.232, "ry": 0.175, "cy": 0.022},
                                  {"z": 0.960, "rx": 0.218, "ry": 0.164, "cy": 0.022}],
                                 mats["mail"], skirt_weights(side, top=0.98, bottom=0.80, thigh_floor=0.55),
                                 segments=16, angle_start=start, angle_end=end, closed=False,
                                 smooth=True, thickness=0.006))
        parts.append(tube("MailSleeve",
                          [(sign * 0.198, 0.062, 1.470), (sign * 0.300, 0.066, 1.455),
                           (sign * 0.420, 0.070, 1.455), (sign * 0.540, 0.067, 1.455),
                           (sign * 0.655, 0.065, 1.455)],
                          [(0.082, 0.078), (0.074, 0.070), (0.066, 0.062),
                           (0.059, 0.055), (0.052, 0.049)],
                          mats["mail"], arm_weights(rig, side), segments=16,
                          smooth=True, thickness=0.005))
        parts.append(torus_ring("MailWristCuff", (sign * 0.630, 0.065, 1.455),
                                0.056, 0.052, 0.008, mats["leather_dark"],
                                lambda point, s=side: {f"lowerarm_{s}": 1.0},
                                axis="X", segments=16, sides=6))
    parts.append(torus_ring("MailCollar", (0.0, 0.020, 1.555), 0.112, 0.100, 0.024,
                            mats["leather_dark"], spine_top_weight, segments=26, sides=8))
    parts.append(torus_ring("MailBelt", (0.0, 0.020, 1.040), 0.206, 0.157, 0.014,
                            mats["leather_dark"], pelvis_weight, segments=30, sides=7))
    parts.append(box("MailBuckle", (0.0, -0.150, 1.040), (0.060, 0.020, 0.052),
                     mats["brass"], pelvis_weight, bevel=0.007))
    # Short chain mantle over the shoulders, split at the front.
    for start, end in ((-math.pi * 0.5 - 1.25, -math.pi * 0.5 + 1.25),
                       (math.pi * 0.5 - 1.20, math.pi * 0.5 + 1.20)):
        parts.append(revolve("MailMantle",
                             [{"z": 1.420, "rx": 0.255, "ry": 0.196, "cy": 0.018},
                              {"z": 1.480, "rx": 0.245, "ry": 0.185, "cy": 0.018},
                              {"z": 1.530, "rx": 0.212, "ry": 0.162, "cy": 0.018}],
                             mats["mail"], spine_top_weight, segments=24,
                             angle_start=start, angle_end=end, closed=False,
                             smooth=True, thickness=0.005))
    # Baldric across the chest.
    parts.append(rect_tube("MailBaldric",
                           [(-0.145, -0.150, 1.510), (0.000, -0.180, 1.390),
                            (0.120, -0.156, 1.220), (0.095, -0.150, 1.075)],
                           0.038, 0.008, mats["leather_dark"], torso_weights,
                           up_hint=Vector((0, 0, 1))))
    parts.append(box("MailBaldricBuckle", (0.000, -0.186, 1.390), (0.050, 0.018, 0.045),
                     mats["brass"], torso_weights, bevel=0.005))
    return finish_piece("Armor_Mail_Chest", parts, rig, 0.44)


def _mail_hands(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        hand = f"hand_{side}"
        lower = f"lowerarm_{side}"
        parts.append(tube("MailCuff",
                          [(sign * 0.620, 0.065, 1.455), (sign * 0.675, 0.065, 1.455)],
                          [(0.060, 0.056), (0.057, 0.053)], mats["mail"],
                          lambda point, s=side: {f"lowerarm_{s}": 1.0}, segments=14,
                          smooth=True, thickness=0.005))
        parts.append(tube("MailMitten",
                          [(sign * 0.680, 0.065, 1.452), (sign * 0.770, 0.065, 1.450),
                           (sign * 0.850, 0.062, 1.447), (sign * 0.895, 0.060, 1.446)],
                          [(0.058, 0.055), (0.055, 0.052), (0.042, 0.040), (0.022, 0.021)],
                          mats["mail"], lambda point, s=side: {f"hand_{s}": 1.0},
                          segments=14, smooth=True, thickness=0.005))
        parts.append(box("MailPalm", (sign * 0.770, 0.065, 1.431), (0.170, 0.086, 0.012),
                         mats["leather"], lambda point, s=side: {f"hand_{s}": 1.0}, bevel=0.005))
        # Mail thumb; follows the actual thumb chain.
        thumb_names = [f"thumb_{segment}_{side}" for segment in ("01", "02", "03")]
        points = [rig.data.bones[thumb_names[0]].head_local.copy()]
        for name in thumb_names:
            points.append(rig.data.bones[name].tail_local.copy())
        parts.append(tube("MailThumb", points, [(0.020, 0.018), (0.017, 0.016),
                                                 (0.014, 0.013), (0.010, 0.009)],
                          mats["mail"], lambda point, names=thumb_names: _chain_weights(point, rig, names, 0.035),
                          segments=10, smooth=True, thickness=0.004))
        parts.append(torus_ring("MailMittenStrap", (sign * 0.700, 0.065, 1.455),
                                0.058, 0.055, 0.007, mats["leather_dark"],
                                lambda point, s=side: {f"hand_{s}": 1.0}, axis="X",
                                segments=14, sides=6))
    return finish_piece("Armor_Mail_Hands", parts, rig, 0.26)


def _mail_legs(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        thigh = f"thigh_{side}"
        calf = f"calf_{side}"
        parts.append(tube("MailChausse",
                          [(sign * 0.091, 0.036, 0.995), (sign * 0.091, 0.039, 0.880),
                           (sign * 0.091, 0.040, 0.760), (sign * 0.091, 0.038, 0.640),
                           (sign * 0.091, 0.050, 0.520), (sign * 0.091, 0.064, 0.390),
                           (sign * 0.091, 0.078, 0.250), (sign * 0.091, 0.087, 0.130)],
                          [(0.103, 0.098), (0.099, 0.094), (0.092, 0.087), (0.086, 0.081),
                           (0.080, 0.075), (0.074, 0.070), (0.066, 0.063), (0.058, 0.055)],
                          mats["mail"], leg_weights(rig, side), segments=16,
                          smooth=True, thickness=0.005))
        parts.append(torus_ring("MailKneeStrap", (sign * 0.091, 0.043, 0.555),
                                0.086, 0.081, 0.009, mats["leather_dark"],
                                lambda point, s=side: {f"thigh_{s}": 0.5, f"calf_{s}": 0.5},
                                axis="Z", segments=18, sides=6))
        parts.append(torus_ring("MailAnkleStrap", (sign * 0.091, 0.082, 0.165),
                                0.064, 0.061, 0.008, mats["leather_dark"],
                                lambda point, s=side: {f"calf_{s}": 0.8, f"foot_{s}": 0.2},
                                axis="Z", segments=16, sides=6))
        for index in range(4):
            point = Vector((sign * 0.091 + (0.100 if index % 2 else -0.100), 0.036, 0.900 - index * 0.100))
            # Pull the rivet to the side surface of the chausse.
            point.x = sign * 0.091 + (0.100 if index % 2 else -0.100)
            parts.append(rivet("MailChausseStud", point, (1 if index % 2 else -1, 0, 0),
                               mats["brass"], lambda point, s=side: {f"thigh_{s}": 1.0}, 0.004))
    return finish_piece("Armor_Mail_Legs", parts, rig, 0.48)


def _mail_feet(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        foot = f"foot_{side}"
        ball = f"ball_{side}"
        def weight(point, s=side):
            return {f"foot_{s}": 1.0} if point.y > -0.02 else {f"ball_{s}": 1.0}
        parts.append(tube("MailShoe",
                          [(sign * 0.091, 0.100, 0.105), (sign * 0.091, 0.030, 0.075),
                           (sign * 0.091, -0.050, 0.060), (sign * 0.091, -0.130, 0.048),
                           (sign * 0.091, -0.185, 0.036)],
                          [(0.062, 0.060), (0.058, 0.055), (0.054, 0.050),
                           (0.047, 0.044), (0.030, 0.026)],
                          mats["mail"], weight, segments=14, smooth=True, thickness=0.005))
        parts.append(box("MailSole", (sign * 0.091, -0.010, 0.014), (0.105, 0.290, 0.018),
                         mats["leather_dark"], lambda point, s=side: {f"foot_{s}": 1.0}, bevel=0.005))
        parts.append(torus_ring("MailAnkleCuff", (sign * 0.091, 0.095, 0.140),
                                0.066, 0.062, 0.009, mats["leather_dark"],
                                lambda point, s=side: {f"foot_{s}": 1.0}, axis="Z",
                                segments=16, sides=6))
        parts.append(box("MailToeCap", (sign * 0.091, -0.190, 0.045), (0.080, 0.050, 0.035),
                         mats["mail"], lambda point, s=side: {f"ball_{s}": 1.0}, bevel=0.006))
    return finish_piece("Armor_Mail_Feet", parts, rig, 0.26)


# ----------------------------------------------------------------------------
# Cloth and leather
# ----------------------------------------------------------------------------

def _cloth_hood(rig, mats):
    parts = []
    def opening(angle, z):
        if z < 1.535 or z > 1.870:
            return False
        front = -math.pi * 0.5
        difference = abs((angle - front + math.pi) % TAU - math.pi)
        half = 0.46 + 0.10 * smoothstep(1.60, 1.74, z) - 0.16 * smoothstep(1.80, 1.87, z)
        return difference < half

    sections = [
        {"z": 1.365, "rx": 0.235, "ry": 0.205, "cy": 0.032, "fold": 0.010, "fold_freq": 8},
        {"z": 1.420, "rx": 0.212, "ry": 0.196, "cy": 0.030, "fold": 0.010, "fold_freq": 8},
        {"z": 1.480, "rx": 0.186, "ry": 0.188, "cy": 0.026, "fold": 0.009, "fold_freq": 8},
        {"z": 1.550, "rx": 0.166, "ry": 0.180, "cy": 0.020, "fold": 0.009, "fold_freq": 7},
        {"z": 1.630, "rx": 0.160, "ry": 0.180, "cy": 0.014, "fold": 0.008, "fold_freq": 7},
        {"z": 1.710, "rx": 0.160, "ry": 0.183, "cy": 0.010, "fold": 0.008, "fold_freq": 7},
        {"z": 1.790, "rx": 0.150, "ry": 0.176, "cy": 0.012, "fold": 0.007, "fold_freq": 6},
        {"z": 1.860, "rx": 0.125, "ry": 0.154, "cy": 0.020, "fold": 0.006, "fold_freq": 6},
        {"z": 1.920, "rx": 0.086, "ry": 0.116, "cy": 0.034, "fold": 0.004, "fold_freq": 5},
        {"z": 1.965, "rx": 0.030, "ry": 0.052, "cy": 0.048, "fold": 0.002, "fold_freq": 4},
    ]
    parts.append(revolve("ClothHood", sections, mats["cloth"], hood_weights, segments=44,
                         closed=True, skip=opening, smooth=True, thickness=0.010))
    for side, start, end in (("l", -math.pi * 0.5 + 0.03, -math.pi * 0.5 + 1.28),
                             ("r", -math.pi * 0.5 - 1.28, -math.pi * 0.5 - 0.03)):
        parts.append(revolve("ClothHoodMantle",
                             [{"z": 1.335, "rx": 0.250, "ry": 0.222, "cy": 0.032, "fold": 0.012, "fold_freq": 7},
                              {"z": 1.385, "rx": 0.230, "ry": 0.208, "cy": 0.032, "fold": 0.010, "fold_freq": 7},
                              {"z": 1.435, "rx": 0.212, "ry": 0.196, "cy": 0.030, "fold": 0.008, "fold_freq": 7}],
                             mats["cloth_dark"], hood_weights, segments=24,
                             angle_start=start, angle_end=end, closed=False,
                             smooth=True, thickness=0.008))
    parts.append(torus_ring("ClothHoodBand", (0.0, 0.012, 1.790), 0.154, 0.180, 0.010,
                            mats["leather_dark"], lambda point: {"Head": 1.0},
                            segments=30, sides=6))
    parts.append(box("ClothHoodClasp", (0.0, -0.168, 1.545), (0.044, 0.020, 0.032),
                     mats["brass"], hood_weights, bevel=0.006))
    parts.append(tube("ClothHoodTrim",
                      [(-0.145, -0.128, 1.620), (-0.165, -0.146, 1.720),
                       (-0.145, -0.150, 1.810)],
                      [(0.006, 0.004)] * 3, mats["trim"], hood_weights, segments=6,
                      smooth=True))
    for index in range(5):
        points = [(-0.12 + index * 0.06, 0.16, 1.930), (-0.14 + index * 0.07, 0.22, 1.870)]
        parts.append(rect_tube("ClothHoodTatter", points, 0.018, 0.004,
                               mats["cloth"], hood_weights, up_hint=Vector((0, 0, 1))))
    return finish_piece("Armor_Cloth_Head", parts, rig, 0.32)


def _cloth_chest(rig, mats):
    parts = []
    sections = [
        {"z": 1.565, "rx": 0.138, "ry": 0.112, "cy": 0.020, "fold": 0.004, "fold_freq": 7},
        {"z": 1.525, "rx": 0.202, "ry": 0.152, "cy": 0.020, "fold": 0.006, "fold_freq": 7},
        {"z": 1.470, "rx": 0.242, "ry": 0.178, "cy": 0.018, "fold": 0.008, "fold_freq": 8},
        {"z": 1.390, "rx": 0.248, "ry": 0.182, "cy": 0.015, "fold": 0.009, "fold_freq": 8},
        {"z": 1.290, "rx": 0.228, "ry": 0.170, "cy": 0.015, "fold": 0.010, "fold_freq": 8},
        {"z": 1.190, "rx": 0.208, "ry": 0.157, "cy": 0.015, "fold": 0.010, "fold_freq": 8},
        {"z": 1.100, "rx": 0.196, "ry": 0.149, "cy": 0.018, "fold": 0.009, "fold_freq": 9},
        {"z": 1.010, "rx": 0.206, "ry": 0.156, "cy": 0.020, "fold": 0.008, "fold_freq": 9},
    ]
    parts.append(revolve("ClothRobe", sections, mats["cloth"], torso_weights, segments=42,
                         closed=True, smooth=True, thickness=0.008))
    # Inner dark tunic visible through the open collar.
    parts.append(revolve("ClothInnerTunic",
                         [{"z": 1.535, "rx": 0.160, "ry": 0.132, "cy": 0.020},
                          {"z": 1.450, "rx": 0.212, "ry": 0.160, "cy": 0.018},
                          {"z": 1.350, "rx": 0.220, "ry": 0.166, "cy": 0.016},
                          {"z": 1.200, "rx": 0.198, "ry": 0.150, "cy": 0.015},
                          {"z": 1.050, "rx": 0.185, "ry": 0.142, "cy": 0.018}],
                         mats["cloth_dark"], torso_weights, segments=28, closed=True,
                         smooth=True, thickness=0.005))
    # Crossed lapels and a narrow trim.
    for side, start, end in (("l", -0.070, 0.185), ("r", -0.185, 0.070)):
        parts.append(rect_tube("ClothLapel",
                               [(start, -0.150, 1.545), (side == "l" and 0.010 or -0.010, -0.180, 1.420),
                                (0.0, -0.165, 1.310)],
                               0.055, 0.010, mats["cloth_dark"], torso_weights,
                               up_hint=Vector((0, 0, 1))))
    parts.append(tube("ClothCollarTrim",
                      [(-0.14, -0.128, 1.550), (-0.075, -0.166, 1.520),
                       (0.0, -0.176, 1.495), (0.075, -0.166, 1.520),
                       (0.14, -0.128, 1.550)],
                      [(0.007, 0.004)] * 5, mats["trim"], torso_weights, segments=6,
                      smooth=True))
    for side in ("l", "r"):
        sign = _side_sign(side)
        parts.append(tube("ClothSleeve",
                          [(sign * 0.195, 0.060, 1.475), (sign * 0.290, 0.064, 1.450),
                           (sign * 0.400, 0.068, 1.445), (sign * 0.510, 0.066, 1.445),
                           (sign * 0.590, 0.064, 1.445), (sign * 0.625, 0.063, 1.445)],
                          [(0.095, 0.090), (0.090, 0.084), (0.092, 0.085),
                           (0.100, 0.092), (0.112, 0.103), (0.110, 0.100)],
                          mats["cloth"], arm_weights(rig, side), segments=18,
                          smooth=True, thickness=0.007))
        parts.append(torus_ring("ClothCuffTrim", (sign * 0.620, 0.063, 1.445),
                                0.108, 0.099, 0.007, mats["trim"],
                                lambda point, s=side: {f"lowerarm_{s}": 1.0},
                                axis="X", segments=20, sides=6))
    # Shoulder mantle.
    for start, end in ((-math.pi * 0.5 - 1.25, -math.pi * 0.5 + 1.25),
                       (math.pi * 0.5 - 1.20, math.pi * 0.5 + 1.20)):
        parts.append(revolve("ClothMantle",
                             [{"z": 1.400, "rx": 0.262, "ry": 0.208, "cy": 0.018, "fold": 0.012, "fold_freq": 9},
                              {"z": 1.470, "rx": 0.255, "ry": 0.200, "cy": 0.018, "fold": 0.010, "fold_freq": 9},
                              {"z": 1.535, "rx": 0.220, "ry": 0.172, "cy": 0.018, "fold": 0.008, "fold_freq": 8}],
                             mats["cloth"], spine_top_weight, segments=26,
                             angle_start=start, angle_end=end, closed=False,
                             smooth=True, thickness=0.008))
        parts.append(tube("ClothMantleTrim",
                          [(0.0, -0.195, 1.400), (0.0, -0.198, 1.470), (0.0, -0.176, 1.535)],
                          [(0.006, 0.004)] * 3, mats["trim"], spine_top_weight,
                          segments=6, smooth=True))
    parts.append(box("ClothClasp", (0.0, -0.198, 1.470), (0.052, 0.022, 0.042),
                     mats["brass"], spine_top_weight, bevel=0.007))
    # Sash and hanging tails.
    parts.append(torus_ring("ClothSash", (0.0, 0.020, 1.035), 0.210, 0.160, 0.018,
                            mats["cloth_dark"], pelvis_weight, segments=30, sides=7))
    parts.append(box("ClothSashKnot", (0.105, -0.155, 1.015), (0.070, 0.045, 0.060),
                     mats["cloth_dark"], pelvis_weight, bevel=0.012))
    for index, x in enumerate((0.085, 0.130)):
        parts.append(rect_tube("ClothSashTail",
                               [(x, -0.155, 0.995), (x + 0.015, -0.165, 0.910),
                                (x - 0.010, -0.155, 0.825)],
                               0.036, 0.008, mats["cloth_dark"], pelvis_weight,
                               up_hint=Vector((0, 0, 1))))
    return finish_piece("Armor_Cloth_Chest", parts, rig, 0.34)


def _gloved_hand(parts, rig, mats, side, material, cuff_material, band_material, uv_prefix):
    sign = _side_sign(side)
    hand = f"hand_{side}"
    lower = f"lowerarm_{side}"
    parts.append(tube(uv_prefix + "Cuff",
                      [(sign * 0.615, 0.065, 1.455), (sign * 0.670, 0.065, 1.455),
                       (sign * 0.690, 0.065, 1.455)],
                      [(0.061, 0.057), (0.058, 0.054), (0.056, 0.052)],
                      cuff_material, lambda point, s=side: {f"lowerarm_{s}": 1.0},
                      segments=14, smooth=True, thickness=0.004))
    parts.append(tube(uv_prefix + "Palm",
                      [(sign * 0.682, 0.065, 1.454), (sign * 0.745, 0.065, 1.450),
                       (sign * 0.800, 0.064, 1.448)],
                      [(0.056, 0.050), (0.054, 0.046), (0.050, 0.040)],
                      material, lambda point, s=side: {f"hand_{s}": 1.0},
                      segments=14, smooth=True, thickness=0.003))
    for finger in ("index", "middle", "ring", "pinky"):
        for segment in ("01", "02", "03"):
            name = f"{finger}_{segment}_{side}"
            head = rig.data.bones[name].head_local.copy()
            tail = rig.data.bones[name].tail_local.copy()
            start = head.lerp(tail, 0.02)
            end = head.lerp(tail, 0.94)
            parts.append(tube(uv_prefix + "Finger",
                              [start, end], [(0.012, 0.011), (0.010, 0.009)],
                              material, lambda point, bone=name: {bone: 1.0},
                              segments=8, smooth=True, thickness=0.002))
    for segment in ("01", "02", "03"):
        name = f"thumb_{segment}_{side}"
        head = rig.data.bones[name].head_local.copy()
        tail = rig.data.bones[name].tail_local.copy()
        parts.append(tube(uv_prefix + "Thumb",
                          [head.lerp(tail, 0.02), head.lerp(tail, 0.94)],
                          [(0.013, 0.012), (0.011, 0.010)], material,
                          lambda point, bone=name: {bone: 1.0}, segments=8,
                          smooth=True, thickness=0.002))
    parts.append(box(uv_prefix + "KnucklePad", (sign * 0.792, 0.065, 1.466),
                     (0.030, 0.090, 0.014), cuff_material,
                     lambda point, s=side: {f"hand_{s}": 1.0}, bevel=0.005))
    parts.append(torus_ring(uv_prefix + "WristBand", (sign * 0.645, 0.065, 1.455),
                            0.060, 0.056, 0.007, band_material,
                            lambda point, s=side: {f"lowerarm_{s}": 1.0},
                            axis="X", segments=14, sides=6))


def _leather_hands(rig, mats):
    parts = []
    for side in ("l", "r"):
        _gloved_hand(parts, rig, mats, side, mats["leather"], mats["leather"],
                     mats["leather_dark"], "Leather")
    return finish_piece("Armor_Leather_Hands", parts, rig, 0.25)


def _cloth_hands(rig, mats):
    parts = []
    for side in ("l", "r"):
        _gloved_hand(parts, rig, mats, side, mats["cloth_dark"], mats["cloth"],
                     mats["leather_dark"], "Cloth")
    return finish_piece("Armor_Cloth_Hands", parts, rig, 0.24)


def _cloth_legs(rig, mats):
    parts = []
    # Short dark under-skirt closes the gaps between the four robe panels.
    parts.append(revolve("ClothUnderskirt",
                         [{"z": 0.560, "rx": 0.235, "ry": 0.185, "cy": 0.020, "fold": 0.006, "fold_freq": 9},
                          {"z": 0.720, "rx": 0.218, "ry": 0.172, "cy": 0.020, "fold": 0.006, "fold_freq": 9},
                          {"z": 0.900, "rx": 0.202, "ry": 0.160, "cy": 0.020, "fold": 0.005, "fold_freq": 9},
                          {"z": 1.020, "rx": 0.196, "ry": 0.154, "cy": 0.020, "fold": 0.004, "fold_freq": 9}],
                         mats["cloth_dark"], pelvis_weight, segments=32, closed=True,
                         smooth=True, thickness=0.006))
    sections = [
        {"z": 0.140, "rx": 0.315, "ry": 0.245, "cy": 0.025, "fold": 0.018, "fold_freq": 10},
        {"z": 0.300, "rx": 0.288, "ry": 0.223, "cy": 0.024, "fold": 0.016, "fold_freq": 10},
        {"z": 0.500, "rx": 0.262, "ry": 0.203, "cy": 0.023, "fold": 0.014, "fold_freq": 9},
        {"z": 0.700, "rx": 0.238, "ry": 0.185, "cy": 0.022, "fold": 0.012, "fold_freq": 9},
        {"z": 0.880, "rx": 0.218, "ry": 0.170, "cy": 0.021, "fold": 0.010, "fold_freq": 9},
        {"z": 1.020, "rx": 0.205, "ry": 0.160, "cy": 0.020, "fold": 0.008, "fold_freq": 9},
    ]
    for side in ("l", "r"):
        sign = _side_sign(side)
        for face in ("front", "back"):
            if face == "front":
                start = (-math.pi * 0.5 + 0.035) if sign > 0 else (-math.pi * 0.5 - 1.30)
                end = (-math.pi * 0.5 + 1.30) if sign > 0 else (-math.pi * 0.5 - 0.035)
            else:
                start = (math.pi * 0.5 - 1.28) if sign > 0 else (math.pi * 0.5 + 0.035)
                end = (math.pi * 0.5 - 0.035) if sign > 0 else (math.pi * 0.5 + 1.28)
            parts.append(revolve("ClothRobeSkirt", sections, mats["cloth"],
                                 skirt_weights(side, top=1.02, bottom=0.14, thigh_floor=0.58),
                                 segments=22, angle_start=start, angle_end=end,
                                 closed=False, smooth=True, thickness=0.008))
            # Jagged torn strips at the hem.
            for index in range(3):
                angle = start + (end - start) * (0.22 + index * 0.26)
                x = 0.312 * math.cos(angle)
                y = 0.024 + 0.242 * math.sin(angle)
                points = [(x, y, 0.155), (x * 0.97, y * 0.97, 0.095)]
                parts.append(rect_tube("ClothHemTatter", points, 0.024, 0.004,
                                       mats["cloth"], skirt_weights(side, top=1.02, bottom=0.14, thigh_floor=0.58),
                                       up_hint=Vector((0, 0, 1))))
    parts.append(torus_ring("ClothWaistCord", (0.0, 0.020, 1.030), 0.205, 0.160, 0.009,
                            mats["trim"], pelvis_weight, segments=28, sides=6))
    return finish_piece("Armor_Cloth_Legs", parts, rig, 0.36)


def _cloth_feet(rig, mats):
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        foot = f"foot_{side}"
        calf = f"calf_{side}"
        parts.append(tube("ClothBootShaft",
                          [(sign * 0.091, 0.078, 0.300), (sign * 0.091, 0.080, 0.220),
                           (sign * 0.091, 0.084, 0.140), (sign * 0.091, 0.088, 0.080)],
                          [(0.075, 0.071), (0.072, 0.068), (0.069, 0.065), (0.066, 0.062)],
                          mats["leather"], leg_weights(rig, side), segments=14,
                          smooth=True, thickness=0.004))
        parts.append(tube("ClothBootFoot",
                          [(sign * 0.091, 0.100, 0.085), (sign * 0.091, 0.030, 0.060),
                           (sign * 0.091, -0.050, 0.050), (sign * 0.091, -0.130, 0.042),
                           (sign * 0.091, -0.185, 0.032)],
                          [(0.064, 0.060), (0.060, 0.056), (0.056, 0.052),
                           (0.048, 0.045), (0.030, 0.026)],
                          mats["leather"],
                          lambda point, s=side: ({f"foot_{s}": 1.0} if point.y > -0.02 else {f"ball_{s}": 1.0}),
                          segments=14, smooth=True, thickness=0.004))
        parts.append(torus_ring("ClothBootCuff", (sign * 0.091, 0.078, 0.290),
                                0.079, 0.075, 0.010, mats["cloth"],
                                lambda point, s=side: {f"calf_{s}": 1.0}, axis="Z",
                                segments=18, sides=6))
        parts.append(torus_ring("ClothBootStrap", (sign * 0.091, 0.085, 0.150),
                                0.070, 0.066, 0.007, mats["leather_dark"],
                                lambda point, s=side: {f"foot_{s}": 1.0}, axis="Z",
                                segments=16, sides=6))
        parts.append(box("ClothSole", (sign * 0.091, -0.010, 0.012), (0.105, 0.285, 0.018),
                         mats["leather_dark"], lambda point, s=side: {f"foot_{s}": 1.0}, bevel=0.005))
    return finish_piece("Armor_Cloth_Feet", parts, rig, 0.24)



def _base_calves(rig, mats):
    """A dark hose underlayer so short sabatons never expose an empty shin."""
    parts = []
    for side in ("l", "r"):
        sign = _side_sign(side)
        parts.append(tube("Ranger_Base_Calf",
                          [(sign * 0.091, 0.036, 0.470), (sign * 0.091, 0.050, 0.370),
                           (sign * 0.091, 0.064, 0.260), (sign * 0.091, 0.078, 0.160),
                           (sign * 0.091, 0.086, 0.100)],
                          [(0.070, 0.066), (0.067, 0.063), (0.062, 0.059),
                           (0.056, 0.053), (0.052, 0.049)],
                          mats["cloth_dark"], leg_weights(rig, side), segments=12,
                          smooth=True, thickness=0.004))
    return finish_piece("Ranger_Base_Calf", parts, rig, 0.22)

# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------

def build_character_armor(rig, source_directory):
    """Build every new piece and return (objects, metadata)."""
    texture_folder = Path(source_directory) / "generated_armor_textures"
    mats = create_materials(texture_folder)
    builders = {
        ("plate", "head"): _plate_helm,
        ("plate", "chest"): _plate_chest,
        ("plate", "hands"): _plate_hands,
        ("plate", "legs"): _plate_legs,
        ("plate", "feet"): _plate_feet,
        ("mail", "head"): _mail_coif,
        ("mail", "chest"): _mail_hauberk,
        ("mail", "hands"): _mail_hands,
        ("mail", "legs"): _mail_legs,
        ("mail", "feet"): _mail_feet,
        ("cloth", "head"): _cloth_hood,
        ("cloth", "chest"): _cloth_chest,
        ("cloth", "hands"): _cloth_hands,
        ("cloth", "legs"): _cloth_legs,
        ("cloth", "feet"): _cloth_feet,
        ("leather", "hands"): _leather_hands,
    }
    objects = []
    generated = {}
    objects.append(_base_calves(rig, mats))
    for (set_name, slot), builder in builders.items():
        obj = builder(rig, mats)
        objects.append(obj)
        generated.setdefault(set_name, {})[slot] = [obj.name]
        print("ARMOR_PIECE", obj.name, len(obj.data.vertices), "verts", len(obj.data.polygons), "faces")
    metadata = {
        "source": "tools/character_armor.py",
        "slots": list(SLOTS),
        "sets": list(SETS),
        "extra": {"leather": {"hands": ["Armor_Leather_Hands"]}},
        "generated": generated,
    }
    return objects, metadata
