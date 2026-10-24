"""Bespoke plate armor for the gargoyle and the goat-man harness.

All pieces are authored parametric surfaces (no ranger outfit meshes), then
bevelled, solidified, riveted and skinned to the Quaternius skeleton.  The
gargoyle gets a full black-iron set; the goat man gets a lighter tribal
harness with a single bone/iron pauldron.
"""

from __future__ import annotations

import math

import bpy
import bmesh
from mathutils import Vector

from devil_source_pipeline import (mesh_object, make_spike, rigid_skin, tube,
                                   weight_by_segments)


def _apply_modifiers(obj) -> None:
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def plate(name: str, rows: int, cols: int, fn, material,
          thickness: float = 0.018, bevel: float = 0.005,
          uv_scale: float = 2.0) -> bpy.types.Object:
    verts, uvs, faces = [], [], []
    for i in range(rows + 1):
        v = i / rows
        for j in range(cols + 1):
            u = j / cols
            verts.append(Vector(fn(u, v)))
            uvs.append((u * uv_scale, v * uv_scale))
    for i in range(rows):
        for j in range(cols):
            a = i * (cols + 1) + j
            b = a + 1
            c = a + cols + 2
            d = a + cols + 1
            faces.append((a, b, c, d))
    obj = mesh_object(name, verts, faces, uvs, material)
    obj.data.polygons.foreach_set("use_smooth", [True] * len(obj.data.polygons))
    solid = obj.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solid.name)
    if bevel > 0:
        bev = obj.modifiers.new("Bevel", "BEVEL")
        bev.width = bevel
        bev.segments = 2
        bev.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=bev.name)
    return obj


def band(name: str, points, radii, material, sides: int = 20) -> bpy.types.Object:
    obj, _ = tube(name, points, radii, sides, material)
    return obj


def rivets(name: str, positions, material, bone: str, rig,
           radius: float = 0.007) -> bpy.types.Object:
    bm = bmesh.new()
    for pos in positions:
        ret = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=radius)
        for vert in ret["verts"]:
            vert.co += Vector(pos)
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


def positions_on_edge(fn, count: int, v: float):
    return [fn(i / (count - 1), v) for i in range(count)]


# ---------------------------------------------------------------------------
# Gargoyle full plate set


def chest_cuirass(rig, iron, bronze, rivet_mat):
    parts = []

    def fn(u, v):
        theta = (u - 0.5) * 2.15
        z = 1.57 - 0.46 * v
        r = 0.292 - 0.058 * v
        x = math.sin(theta) * r
        y = -math.cos(theta) * r - 0.012
        y -= 0.022 * max(0.0, 1.0 - abs(theta) / 1.1) ** 2
        z -= 0.040 * (1.0 - abs(u - 0.5) * 2.0) ** 2 * max(0.0, v - 0.62) / 0.38
        z += 0.012 * math.sin(theta * 1.4)
        return x, y, z

    cuirass = plate("Cuirass", 14, 18, fn, iron, 0.022, 0.006, 2.2)
    weight_by_segments(cuirass, rig, ["spine_02", "spine_03"], power=2.0)
    parts.append(cuirass)
    # Central ridge and edge trim.
    ridge_pts = [Vector(fn(0.5, v)) + Vector((0, -0.014, 0)) for v in
                 [i / 12 for i in range(13)]]
    ridge = band("CuirassRidge", ridge_pts, [0.011] * 13, bronze, 8)
    rigid_skin(ridge, rig, "spine_03")
    parts.append(ridge)
    for v in (0.015, 0.985):
        pts = [Vector(fn(i / 18, v)) for i in range(19)]
        rim = band("CuirassTrim", pts, [0.009] * 19, bronze, 6)
        weight_by_segments(rim, rig, ["spine_02", "spine_03"], power=2.0)
        parts.append(rim)
    # Rivets along both flanks.
    pos = []
    for u in (0.06, 0.94):
        for v in (0.12, 0.30, 0.48, 0.66, 0.84):
            p = Vector(fn(u, v))
            pos.append(p + Vector((0, -0.012, 0)))
    parts.append(rivets("CuirassRivets", pos, rivet_mat, "spine_03", rig))
    # Back spine plate.
    def back(u, v):
        theta = (u - 0.5) * 1.0
        z = 1.56 - 0.44 * v
        r = 0.245 - 0.035 * v
        return (math.sin(theta) * r, math.cos(theta) * r + 0.01, z)
    bp = plate("SpinePlate", 8, 6, back, iron, 0.018, 0.005, 1.6)
    rigid_skin(bp, rig, "spine_03")
    parts.append(bp)
    return parts


def pauldron(rig, side: str, iron, bronze, rivet_mat, bone_scale: float = 1.0):
    s = 1.0 if side == "l" else -1.0
    shoulder = Vector((0.205 * s, 0.0, 1.47))
    elbow = Vector((0.46 * s, 0.03, 1.42))
    tangent = (elbow - shoulder).normalized()
    up = Vector((0, 0, 1))
    side_axis = tangent.cross(up).normalized()
    up2 = side_axis.cross(tangent).normalized()
    parts = []

    def shell(u, v, radius, zoff=0.0):
        b = shoulder.lerp(elbow, 0.08 + 0.34 * v)
        theta = (u - 0.5) * 2.5
        radial = up2 * math.cos(theta) + side_axis * math.sin(theta) * 0.4
        return b + radial * radius + tangent * (0.02 * v) + Vector((0, 0, zoff))

    outer = plate("PauldronOuter", 7, 12, lambda u, v: shell(u, v, 0.155 * bone_scale),
                  iron, 0.020, 0.006, 1.8)
    rigid_skin(outer, rig, f"upperarm_{side}")
    parts.append(outer)
    inner = plate("PauldronInner", 5, 10, lambda u, v: shell(u, v, 0.125 * bone_scale, -0.015),
                  iron, 0.016, 0.004, 1.5)
    rigid_skin(inner, rig, f"upperarm_{side}")
    parts.append(inner)
    # Rim and upward spike.
    rim_pts = [shell(i / 16, 0.98, 0.165 * bone_scale) for i in range(17)]
    rim = band("PauldronRim", rim_pts, [0.010] * 17, bronze, 6)
    rigid_skin(rim, rig, f"upperarm_{side}")
    parts.append(rim)
    spike_base = shell(0.5, 0.25, 0.16 * bone_scale)
    parts.append(make_spike(rig, f"upperarm_{side}", spike_base,
                            up2 * 0.85 + side_axis * 0.3 * s + tangent * 0.1,
                            0.12, iron, sides=8, radius=0.025))
    rpos = [shell(u, v, 0.170 * bone_scale) for u in (0.2, 0.8) for v in (0.25, 0.55, 0.82)]
    parts.append(rivets("PauldronRivets", rpos, rivet_mat, f"upperarm_{side}", rig))
    return parts


def bracer(rig, side: str, iron, bronze, rivet_mat):
    lo = rig.data.bones.get(f"lowerarm_{side}")
    if lo is None:
        return []
    a = lo.head_local.lerp(lo.tail_local, 0.12)
    b = lo.head_local.lerp(lo.tail_local, 0.88)
    axis = (b - a).normalized()
    obj = band("Bracer", [a, a.lerp(b, 0.5), b], [0.070, 0.075, 0.060], iron, 20)
    rigid_skin(obj, rig, f"lowerarm_{side}")
    parts = [obj]
    # Outer splint and spike.
    out = Vector((0, -0.072, 0.02))
    spl = plate("BracerSplint", 4, 4,
                lambda u, v: a.lerp(b, 0.08 + 0.84 * v) + Vector(
                    (math.sin((u - 0.5) * 1.1) * 0.07, -math.cos((u - 0.5) * 1.1) * 0.07, 0.0)),
                iron, 0.014, 0.004, 1.4)
    rigid_skin(spl, rig, f"lowerarm_{side}")
    parts.append(spl)
    parts.append(make_spike(rig, f"lowerarm_{side}", a.lerp(b, 0.55) + out,
                            Vector((0, -1, 0.15)), 0.075, iron, sides=6, radius=0.015))
    return parts


def greave(rig, side: str, iron, bronze, rivet_mat):
    ca = rig.data.bones.get(f"calf_{side}")
    if ca is None:
        return []
    a = ca.head_local.lerp(ca.tail_local, 0.18)
    b = ca.head_local.lerp(ca.tail_local, 0.92)
    obj = band("Greave", [a, a.lerp(b, 0.45), b], [0.085, 0.092, 0.075], iron, 20)
    rigid_skin(obj, rig, f"calf_{side}")
    parts = [obj]
    # Knee cop and front ridge.
    knee = a + (b - a).normalized() * -0.015
    cop = plate("KneeCop", 4, 7,
                lambda u, v: knee + Vector(((u - 0.5) * 0.16,
                                             -0.095 * math.cos((u - 0.5) * 2.0) - 0.01,
                                             -0.10 * v)),
                iron, 0.016, 0.005, 1.5)
    rigid_skin(cop, rig, f"calf_{side}")
    parts.append(cop)
    parts.append(make_spike(rig, f"calf_{side}", knee + Vector((0, -0.10, -0.015)),
                            Vector((0, -1, 0.2)), 0.06, iron, sides=6, radius=0.012))
    return parts


def tassets(rig, iron, bronze, cloth, rivet_mat):
    parts = []
    # Four hanging plates over the cloth skirt.
    for k, (u0, u1) in enumerate([(-0.92, -0.52), (-0.38, -0.02),
                                   (0.02, 0.38), (0.52, 0.92)]):
        def fn(u, v, u0=u0, u1=u1):
            theta = u0 + (u1 - u0) * u
            z = 1.045 - 0.235 * v
            r = 0.275 + 0.035 * v
            return (math.sin(theta) * r, -math.cos(theta) * r - 0.012, z)
        p = plate("Tasset", 8, 5, fn, iron, 0.018, 0.005, 1.6)
        rigid_skin(p, rig, "pelvis")
        parts.append(p)
        pos = [Vector(fn(u, 0.88)) + Vector((0, -0.010, 0)) for u in (0.15, 0.5, 0.85)]
        parts.append(rivets("TassetRivets", pos, rivet_mat, "pelvis", rig))
    # Heavy belt band and buckle.
    ring_pts = [Vector((math.cos(a) * 0.30, math.sin(a) * 0.30, 1.065))
                for a in [i / 48 * math.tau for i in range(49)]]
    belt = band("BeltIron", ring_pts, [0.018] * 49, iron, 10)
    rigid_skin(belt, rig, "pelvis")
    parts.append(belt)
    buckle = plate("Buckle", 3, 5,
                   lambda u, v: Vector((((u - 0.5) * 0.15),
                                        -0.315,
                                        1.02 + v * 0.09 + 0.02 * math.cos((u - 0.5) * 3))),
                   bronze, 0.018, 0.005, 1.0)
    rigid_skin(buckle, rig, "pelvis")
    parts.append(buckle)
    return parts


def gorget(rig, iron, bronze):
    ring_pts = [Vector((math.cos(a) * 0.135, math.sin(a) * 0.135, 1.545))
                for a in [i / 36 * math.tau for i in range(37)]]
    obj = band("Gorget", ring_pts, [0.018] * 37, iron, 10)
    rigid_skin(obj, rig, "neck_01")
    parts = [obj]
    # Front pointed plate.
    plate_obj = plate("GorgetFront", 3, 5,
                      lambda u, v: Vector(((u - 0.5) * 0.18,
                                           -0.15 - 0.012 * math.cos((u - 0.5) * 3),
                                           1.60 - 0.12 * v - 0.03 * (1 - abs(u - 0.5) * 2))),
                      iron, 0.014, 0.004, 1.2)
    rigid_skin(plate_obj, rig, "neck_01")
    parts.append(plate_obj)
    return parts


# ---------------------------------------------------------------------------
# Goat-man tribal harness


def goat_harness(rig, leather, iron, bronze, bone, cloth):
    parts = []
    # Crossed chest straps.
    for s in (1, -1):
        pts = [Vector((0.20 * s, -0.02, 1.47)), Vector((0.10 * s, -0.17, 1.34)),
               Vector((-0.06 * s, -0.20, 1.20)), Vector((-0.16 * s, -0.14, 1.08))]
        strap = band("HarnessStrap", pts, [0.026, 0.030, 0.026, 0.022], leather, 8)
        weight_by_segments(strap, rig, ["spine_02", "spine_03"], power=2.0)
        parts.append(strap)
    # Central iron ring.
    ring_pts = [Vector((math.cos(a) * 0.055, -0.215, 1.27 + math.sin(a) * 0.055))
                for a in [i / 24 * math.tau for i in range(25)]]
    ring = band("HarnessRing", ring_pts, [0.011] * 25, bronze, 8)
    rigid_skin(ring, rig, "spine_03")
    parts.append(ring)
    # One bespoke bone/iron shoulder plate and spike.
    parts.extend(pauldron(rig, "l", bone, bronze, bronze, bone_scale=0.78))
    # Leather bracers with iron studs.
    for side in ("l", "r"):
        lo = rig.data.bones.get(f"lowerarm_{side}")
        if lo:
            a = lo.head_local.lerp(lo.tail_local, 0.18)
            b = lo.head_local.lerp(lo.tail_local, 0.82)
            obj = band("HarnessBracer", [a, a.lerp(b, 0.5), b],
                       [0.064, 0.068, 0.056], leather, 14)
            rigid_skin(obj, rig, f"lowerarm_{side}")
            parts.append(obj)
    # Waist belt + loincloth.
    ring_pts = [Vector((math.cos(a) * 0.275, math.sin(a) * 0.275, 1.045))
                for a in [i / 48 * math.tau for i in range(49)]]
    belt = band("HarnessBelt", ring_pts, [0.018] * 49, leather, 8)
    rigid_skin(belt, rig, "pelvis")
    parts.append(belt)
    parts.append(make_spike(rig, "pelvis", Vector((0, -0.29, 1.045)),
                            Vector((0, -1, 0.1)), 0.035, iron, sides=6, radius=0.012))
    parts.append(make_loincloth(rig, leather, cloth))
    return parts


def make_loincloth(rig, leather, cloth):
    from devil_source_pipeline import make_skirt
    skirt = make_skirt(rig, 1.035, 0.735, 0.285, 0.35, cloth, "Loincloth", 40, 0.06)
    for vg in list(skirt.vertex_groups):
        skirt.vertex_groups.remove(vg)
    weight_by_segments(skirt, rig, ["pelvis", "thigh_l", "thigh_r"], power=1.4)
    return skirt
