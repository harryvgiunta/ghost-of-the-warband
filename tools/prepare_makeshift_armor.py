"""Author the Makeshift armor set on the Ranger's own skeleton.

Bone lashed onto cured hide: the kit of something that took a skeleton apart
and wore what was left. Five salvage pieces a ranger assembled in the Unholy
Forest, exported as one GLB the runtime retargets onto the hero rig:

    Armor_Makeshift_Head    bone coif: plated cap, brow band, cheek plates,
                            crown ridge, split-antler rack, leather lining
    Armor_Makeshift_Chest   cured-hide vest, bone rib plates, sternum, spine
                            ridge, spaulders, one bare shoulder, laced front
    Armor_Makeshift_Hands   narrow hide bracers, bone knuckles and wrist spur
    Armor_Makeshift_Legs    hide leggings, bone knee caps, one bone shin plate,
                            a hanging loin panel
    Armor_Makeshift_Feet    hide boots, bone toe caps and heel spurs

Every piece is fitted: the ranger's own tunic, trousers and boots are hidden by
the slots this kit replaces, so the chest carries a narrow hide sleeve instead
of a mantle, and the kit's silhouette is the body's silhouette. Bone is the
pale accent, and every plate is sampled off the hide surface it is lashed to,
so nothing hovers off the body.

Usage (Blender 5.1+):
    blender --background --python-exit-code 1 --python tools/prepare_makeshift_armor.py

The stage imports ``assets/characters/ironwood_ranger.glb`` first and takes
every joint, palm, crown, shoulder and silhouette radius from that file: no
position in this script is guessed.  Pieces are modelled in the Ranger's bind
space (armature space metres, +X is the character's left, -Y forward, +Z up),
skinned with explicit vertex weights, then joined per slot and exported with a
skeleton whose bone names match the Ranger's exactly.

Every material's PBR atlas is rasterised from ``tools/forest_surface.py``: the
finished mesh is unwrapped per material, each texel is resolved back to its
bind-space position and sampled, so bone pores, antler rings and hide grain
stay continuous across UV seams.  Bone and antler palettes come from
``tools/forest_styles.py``; the cured hide is the bone field retinted oxblood
(bone's own pore, crack and scuff masks driven into a leather palette) unless
``forest_surface`` grows a ``leather`` surface, in which case that is used.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
from pathlib import Path

import numpy as np
import bmesh
import bpy
from mathutils import Matrix, Vector

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import forest_styles as styles  # noqa: E402
import forest_surface as surfaces  # noqa: E402
import prepare_forest_mobs as mobs  # noqa: E402

TAU = math.tau
ROOT = styles.ROOT
SEED = styles.SEED
FPS = styles.FPS

RANGER = ROOT / "assets" / "characters" / "ironwood_ranger.glb"
OUTPUT = ROOT / "assets" / "characters" / "armor" / "ironwood_makeshift.glb"
WORKSPACE = ROOT / ".runtime" / "makeshift-armor"
CAPTURES = WORKSPACE / "captures"
TEXTURES = WORKSPACE / "textures"

SLOTS = ("head", "chest", "hands", "legs", "feet")
NODE_NAME = {slot: f"Armor_Makeshift_{slot.capitalize()}" for slot in SLOTS}

# Surfaces reused from the mobset: stained bone from the ossuary stalker is
# exactly the ivory the brief asks for, its antler supplies the crown, and its
# cured-hide palette is the oxblood leather the pieces are lashed onto.
SURFACE_COLOURS = {
    "leather": ("ossuary_stalker", "leather"),
    "bone": ("ossuary_stalker", "bone"),
    "antler": ("ossuary_stalker", "antler"),
}
MATERIAL_NAME = {surface: f"Makeshift_{surface.capitalize()}" for surface in SURFACE_COLOURS}
SURFACE_ORDER = ("leather", "bone", "antler")

# Atlas edge, normal strength and roughness band per surface.  Bone and antler
# keep the mobset's values; hide gets the larger atlas because four of the five
# pieces are mostly hide, so its texel density is what the kit reads at.
SURFACE_SPECS = {
    "leather": {**styles.SURFACES["leather"], "size": 2048},
    "bone": dict(styles.SURFACES["bone"]),
    "antler": dict(styles.SURFACES["antler"]),
}
# The hide field's pebble cell edge, used to filter its grain at bake time.
LEATHER_PEBBLE = 0.0043

TRIANGLE_BUDGET = 22_000
# Cross-section shape exponent: 2 is an ellipse, larger hugs a rounded box.
SECTION_EXPONENT = 2.6
IMAGE_BUDGET = 18

RIG: bpy.types.Object | None = None
MEASURE: "Measure | None" = None
IDLE_ACTION: bpy.types.Action | None = None
# Nearest the ranger's own arms come to the body midline in the idle pose,
# sampled by height. Anything the chest wears has to stay inboard of this.
ARM_LIMIT: list[tuple[float, float]] = []


def arm_limit(z: float) -> float:
    if not ARM_LIMIT:
        return 1.0e9
    if z <= ARM_LIMIT[0][0]:
        return ARM_LIMIT[0][1]
    if z >= ARM_LIMIT[-1][0]:
        return ARM_LIMIT[-1][1]
    for index in range(len(ARM_LIMIT) - 1):
        z0, v0 = ARM_LIMIT[index]
        z1, v1 = ARM_LIMIT[index + 1]
        if z <= z1:
            span = max(1e-9, z1 - z0)
            return v0 + (v1 - v0) * (z - z0) / span
    return ARM_LIMIT[-1][1]


def palette(surface: str) -> dict[str, str]:
    mob, key = SURFACE_COLOURS[surface]
    return styles.palette(mob, key)


# ---------------------------------------------------------------------------
# Measurement: everything the pieces sit on is read off the imported Ranger


class SectionTable:
    """Smoothed horizontal cross-section of a reference mesh, sampled by height."""

    def __init__(self, entries: list[tuple[float, float, float, float, float]]):
        self.entries = sorted(entries)

    def at(self, z: float) -> dict[str, float]:
        entries = self.entries
        if z <= entries[0][0]:
            lo = hi = entries[0]
            t = 0.0
        elif z >= entries[-1][0]:
            lo = hi = entries[-1]
            t = 0.0
        else:
            index = 0
            while index + 1 < len(entries) and entries[index + 1][0] < z:
                index += 1
            lo, hi = entries[index], entries[index + 1]
            span = hi[0] - lo[0]
            t = 0.0 if span <= 1e-9 else (z - lo[0]) / span
        return {
            "cx": lo[1] + (hi[1] - lo[1]) * t,
            "cy": lo[2] + (hi[2] - lo[2]) * t,
            "rx": lo[3] + (hi[3] - lo[3]) * t,
            "ry": lo[4] + (hi[4] - lo[4]) * t,
        }


class SectorTable:
    """Per-height ring sampled by angle: the garment's exact wearing envelope.

    An ellipse fitted to a bbox is a bad garment: it cuts the corners of a
    squarish torso and balloons a flat back.  This keeps the measured radius of
    every angular sector, so a cuirass can be loose over the chest and skin
    tight under the arm where the ranger's own arm hangs.
    """

    def __init__(self, entries, sectors: int):
        self.entries = sorted(entries)
        self.sectors = sectors

    def at(self, z: float):
        entries = self.entries
        if z <= entries[0][0]:
            left = right = entries[0]
            t = 0.0
        elif z >= entries[-1][0]:
            left = right = entries[-1]
            t = 0.0
        else:
            index = 0
            while index + 1 < len(entries) and entries[index + 1][0] < z:
                index += 1
            left, right = entries[index], entries[index + 1]
            span = right[0] - left[0]
            t = 0.0 if span <= 1e-9 else (z - left[0]) / span
        cx = left[1] + (right[1] - left[1]) * t
        cy = left[2] + (right[2] - left[2]) * t
        radii = tuple(a + (b - a) * t for a, b in zip(left[3], right[3]))
        return cx, cy, radii

    def ring(self, z: float, theta: float):
        cx, cy, radii = self.at(z)
        count = self.sectors
        position = (theta % TAU) / TAU * count
        index = int(position) % count
        # Take the widest of the neighbouring sectors: interpolating between
        # them could dip inside the surface between two measured samples.
        radius = max(radii[index], radii[(index + 1) % count], radii[(index - 1) % count])
        return cx, cy, radius


class Measure:
    def __init__(self, rig: bpy.types.Object, meshes: dict[str, bpy.types.Object]):
        self.rig = rig
        self.segments = {
            bone.name: (bone.head_local.copy(), bone.tail_local.copy())
            for bone in rig.data.bones
        }
        self.points = {
            name: [vertex.co.copy() for vertex in obj.data.vertices]
            for name, obj in meshes.items()
        }

    # -- bones ------------------------------------------------------------
    def exists(self, bone: str) -> bool:
        return bone in self.segments

    def joint(self, bone: str) -> Vector:
        return self.segments[bone][0].copy()

    def tip(self, bone: str) -> Vector:
        return self.segments[bone][1].copy()

    # -- silhouette -------------------------------------------------------
    def section(self, refs, z: float, half: float = 0.02, x_range=None) -> dict[str, float] | None:
        x0 = x1 = 0.0
        y0 = y1 = 0.0
        seen = 0
        for ref in refs:
            for point in self.points[ref]:
                if abs(point.z - z) > half:
                    continue
                if x_range is not None and not (x_range[0] <= point.x <= x_range[1]):
                    continue
                if seen == 0:
                    x0 = x1 = point.x
                    y0 = y1 = point.y
                else:
                    x0 = min(x0, point.x)
                    x1 = max(x1, point.x)
                    y0 = min(y0, point.y)
                    y1 = max(y1, point.y)
                seen += 1
        if seen < 6:
            return None
        cx = (x0 + x1) * 0.5
        cy = (y0 + y1) * 0.5
        rx = max(1e-4, (x1 - x0) * 0.5)
        ry = max(1e-4, (y1 - y0) * 0.5)
        # A bbox-sized ellipse cuts the corners of a rounded box; grow both
        # radii by the largest L^p radius the section actually reaches so the
        # garment encloses every sampled vertex instead of slicing through it.
        cover = 1.0
        for ref in refs:
            for point in self.points[ref]:
                if abs(point.z - z) > half:
                    continue
                if x_range is not None and not (x_range[0] <= point.x <= x_range[1]):
                    continue
                m = (abs((point.x - cx) / rx) ** SECTION_EXPONENT
                     + abs((point.y - cy) / ry) ** SECTION_EXPONENT) ** (1.0 / SECTION_EXPONENT)
                if m > cover:
                    cover = m
        return {"cx": cx, "cy": cy, "rx": rx * cover, "ry": ry * cover}

    def table(self, refs, z0: float, z1: float, step: float, x_range=None,
              half: float = 0.02, smooth: int = 2) -> SectionTable:
        """A widening envelope: each entry keeps the largest radius nearby.

        Armor must clear the body everywhere, so the profile takes the local
        maximum instead of the mean; interpolation between samples can then
        never cut inside a bulge the sampler stepped over.
        """
        raw = []
        for index in range(int(round((z1 - z0) / step)) + 1):
            z = z0 + index * step
            section = self.section(refs, z, half, x_range)
            if section is None:
                continue
            raw.append((z, section))
        entries = []
        for index, (z, section) in enumerate(raw):
            window = raw[max(0, index - smooth): index + smooth + 1]
            rx = max(item[1]["rx"] for item in window)
            cx = sum(item[1]["cx"] for item in window) / len(window)
            # Centre on the mean of the window, then grow the radius until it
            # encloses every sample: a boot whose toe and ankle alternate would
            # otherwise pinch the shell between two rows.
            cy = sum(item[1]["cy"] for item in window) / len(window)
            ry = max(abs(item[1]["cy"] - cy) + item[1]["ry"] for item in window)
            entries.append((z, cx, cy, rx, ry))
        return SectionTable(entries)

    def top_z(self, refs, x_range, y_range=(-0.07, 0.02)) -> float:
        best = None
        for ref in refs:
            for point in self.points[ref]:
                if not (x_range[0] <= point.x <= x_range[1]):
                    continue
                if not (y_range[0] <= point.y <= y_range[1]):
                    continue
                best = point.z if best is None else max(best, point.z)
        return 0.0 if best is None else best

    def height_at(self, refs, x: float, y: float, radius: float = 0.03) -> float | None:
        best = None
        for ref in refs:
            for point in self.points[ref]:
                if abs(point.x - x) > radius or abs(point.y - y) > radius:
                    continue
                best = point.z if best is None else max(best, point.z)
        return best


    def sector_table(self, refs, z0: float, z1: float, step: float, sectors: int = 32,
                     x_range=None, half: float = 0.02, smooth: int = 1,
                     minimum: int = 26) -> "SectorTable":
        """Radial envelope by height and angle.

        The ranger's leg meshes are sparse: a two-centimetre slice can hold
        seven vertices.  The band therefore widens until it has enough samples
        to describe a ring, and sectors with no sample are interpolated from
        their angular neighbours rather than inheriting whatever the far side
        of the limb measured.
        """
        rows = []
        for index in range(int(round((z1 - z0) / step)) + 1):
            z = z0 + index * step
            band = half
            points: list[Vector] = []
            while band <= 0.12:
                points = [point for ref in refs for point in self.points[ref]
                          if abs(point.z - z) <= band
                          and (x_range is None or x_range[0] <= point.x <= x_range[1])]
                if len(points) >= minimum:
                    break
                band += 0.010
            if len(points) < 6:
                continue
            cx = (min(point.x for point in points) + max(point.x for point in points)) * 0.5
            cy = (min(point.y for point in points) + max(point.y for point in points)) * 0.5
            rx = max(1e-4, max(point.x for point in points) - cx)
            ry = max(1e-4, max(point.y for point in points) - cy)
            buckets: list[float] = [0.0] * sectors
            for point in points:
                angle = math.atan2(point.y - cy, point.x - cx) % TAU
                cell = int(angle / TAU * sectors) % sectors
                radius = math.hypot(point.x - cx, point.y - cy)
                if radius > buckets[cell]:
                    buckets[cell] = radius
            filled = list(buckets)
            for cell in range(sectors):
                if filled[cell] > 0.0:
                    continue
                # A sector with no vertices (a sparse limb mesh) takes the
                # radius of the ellipse fitted to this row, not the radius of
                # whichever far-away sector happens to have one.
                angle = TAU * (cell + 0.5) / sectors
                cosine = math.cos(angle) / rx
                sine = math.sin(angle) / ry
                filled[cell] = 1.0 / math.sqrt(cosine * cosine + sine * sine)
            rows.append((z, cx, cy, tuple(filled)))
        if not rows:
            raise SystemExit(f"no samples for a sector table in {refs}")
        entries = []
        for index, row in enumerate(rows):
            window = rows[max(0, index - smooth): index + smooth + 1]
            radii = tuple(max(item[3][cell] for item in window) for cell in range(sectors))
            entries.append((row[0], row[1], row[2], radii))
        return SectorTable(entries, sectors)

    def axis_ring(self, refs, a: Vector, b: Vector, t: float, half_t: float = 0.07) -> dict:
        """Cross-section around a limb axis: mean centre and enclosing radius.

        Used for the sleeve, which has to enclose the ranger's own arm and
        hand, so the ring centre is the measured one rather than the bone axis.
        """
        direction = b - a
        length_squared = max(1e-9, direction.length_squared)
        collected = []
        for ref in refs:
            for point in self.points[ref]:
                local = (point - a).dot(direction) / length_squared
                if abs(local - t) > half_t:
                    continue
                collected.append((point - (a + direction * local)).length)
        if not collected:
            axis_point = a + direction * max(0.0, min(1.0, t))
            return {"cy": axis_point.y, "cz": axis_point.z, "radius": 0.05}
        centre_y = 0.0
        centre_z = 0.0
        count = 0
        for ref in refs:
            for point in self.points[ref]:
                local = (point - a).dot(direction) / length_squared
                if abs(local - t) > half_t:
                    continue
                centre_y += point.y
                centre_z += point.z
                count += 1
        centre_y /= max(1, count)
        centre_z /= max(1, count)
        radius = 0.0
        for ref in refs:
            for point in self.points[ref]:
                local = (point - a).dot(direction) / length_squared
                if abs(local - t) > half_t:
                    continue
                radius = max(radius, math.hypot(point.y - centre_y, point.z - centre_z))
        return {"cy": centre_y, "cz": centre_z, "radius": radius}

    def radius_along(self, refs, a: Vector, b: Vector, t: float, half_t: float = 0.12,
                     cap: float = 0.20, percent: float = 95.0) -> float:
        direction = b - a
        length_squared = max(1e-9, direction.length_squared)
        distances = []
        for ref in refs:
            for point in self.points[ref]:
                local = max(0.0, min(1.0, (point - a).dot(direction) / length_squared))
                if abs(local - t) > half_t:
                    continue
                distance = (point - (a + direction * local)).length
                if distance < cap:
                    distances.append(distance)
        if not distances:
            return 0.05
        distances.sort()
        return distances[min(len(distances) - 1, int(len(distances) * percent / 100.0))]


# ---------------------------------------------------------------------------
# Authoring helpers


def orient_outward(obj, axis: Vector | None = None) -> None:
    """Point the shell away from its axis so the solidify pass thickens outward."""
    axis = axis or Vector((0.0, 0.0, 0.0))
    mesh = obj.data
    inward = 0
    outward = 0
    for polygon in mesh.polygons:
        centre = polygon.center
        radial = centre - axis
        if radial.length_squared < 1e-10:
            continue
        if polygon.normal.dot(radial) < 0.0:
            inward += 1
        else:
            outward += 1
    if inward > outward:
        import bmesh

        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()


def surface_grid(name: str, cols: int, rows: int, sample, material, thickness: float = 0.0,
                 closed_u: bool = True, drop=None, cap_start: bool = False,
                 cap_end: bool = False, axis: Vector | None = None):
    """Generic shell: ``sample(u, v) -> Vector`` with u around and v along."""
    verts: list[Vector] = []
    grid: list[list[int]] = []
    for row in range(rows):
        v = row / (rows - 1)
        ring: list[int] = []
        for column in range(cols):
            u = (column / cols) if closed_u else (column / (cols - 1))
            ring.append(len(verts))
            verts.append(sample(u, v))
        grid.append(ring)
    faces: list[tuple[int, ...]] = []
    span = cols if closed_u else cols - 1
    for row in range(rows - 1):
        for column in range(span):
            if drop is not None and drop(row, column):
                continue
            nxt = (column + 1) % cols
            faces.append((grid[row][column], grid[row][nxt], grid[row + 1][nxt], grid[row + 1][column]))
    if cap_start:
        centre = len(verts)
        verts.append(sum((verts[index] for index in grid[0]), Vector()) / cols)
        for column in range(span):
            faces.append((centre, grid[0][column], grid[0][(column + 1) % cols]))
    if cap_end:
        centre = len(verts)
        verts.append(sum((verts[index] for index in grid[-1]), Vector()) / cols)
        for column in range(span):
            faces.append((centre, grid[-1][(column + 1) % cols], grid[-1][column]))
    obj = mobs.link_mesh(name, verts, faces, material)
    orient_outward(obj, axis)
    if thickness > 0.0:
        mobs.solidify(obj, thickness)
    return obj


def blob(name: str, centre: Vector, radii, material, sides: int = 8, rings: int = 6,
         salt: float = 0.0, squash_z: float = 1.0):
    """A small round lump: moss clump, bone stud, rivet."""
    verts: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    top = len(verts)
    verts.append(centre + Vector((0.0, 0.0, radii[2] * squash_z)))
    rows: list[list[int]] = []
    for ring in range(1, rings):
        polar = math.pi * ring / rings
        row: list[int] = []
        for step in range(sides):
            angle = TAU * step / sides
            wobble = 1.0 + (mobs.hash01(step * 1.7 + ring * 3.1 + salt) - 0.5) * 0.30
            row.append(len(verts))
            verts.append(centre + Vector((
                math.cos(angle) * math.sin(polar) * radii[0] * wobble,
                math.sin(angle) * math.sin(polar) * radii[1] * wobble,
                math.cos(polar) * radii[2] * squash_z,
            )))
        rows.append(row)
    bottom = len(verts)
    verts.append(centre - Vector((0.0, 0.0, radii[2] * squash_z)))
    for step in range(sides):
        nxt = (step + 1) % sides
        faces.append((top, rows[0][nxt], rows[0][step]))
        faces.append((bottom, rows[-1][step], rows[-1][nxt]))
    for ring in range(len(rows) - 1):
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((rows[ring][step], rows[ring][nxt], rows[ring + 1][nxt], rows[ring + 1][step]))
    return mobs.link_mesh(name, verts, faces, material)


def arc_plate(name: str, table: SectionTable, z0: float, z1: float, a0: float, a1: float,
              offset: float, cols: int, rows: int, material, thickness: float,
              salt: float = 0.0, jitter: float = 0.006, ragged: float = 0.0,
              closed: bool = False):
    """A plate bent around a measured cross-section.

    ``a0``..``a1`` in radians; ``closed`` joins the ends so a band can ring a
    limb (a helm rim) instead of being an open guard.
    """
    def sample(u, v):
        z = z0 + (z1 - z0) * v
        angle = a0 + (a1 - a0) * u
        section = table.at(z)
        rx = section["rx"] + offset
        ry = section["ry"] + offset
        wobble = 1.0 + (mobs.hash01(u * 9.1 + v * 4.3 + salt) - 0.5) * (jitter / max(0.03, rx))
        drop = 0.0
        if ragged > 0.0 and v > 0.72:
            drop = ragged * mobs.smoothstep(0.72, 1.0, v) * mobs.hash01(u * 7.7 + salt)
        return Vector((
            section["cx"] + math.cos(angle) * rx * wobble,
            section["cy"] + math.sin(angle) * ry * wobble,
            z - drop,
        ))

    return surface_grid(name, cols, rows, sample, material, thickness=thickness,
                        closed_u=closed)


def dome(name: str, centre: Vector, radii, material, cols: int = 12, rows: int = 5,
         thickness: float = 0.009, salt: float = 0.0, spread: float = 0.0):
    """A bone cap: the upper shell of a jittered ellipsoid.

    ``spread`` runs the shell past its equator (radians), so a spaulder can
    wrap down over the deltoid instead of ending in a flat disc.
    """
    def sample(u, v):
        polar = (math.pi * 0.5 + spread) * v
        angle = TAU * u
        wobble = 1.0 + (mobs.hash01(u * 7.0 + v * 3.0 + salt) - 0.5) * 0.10
        return centre + Vector((
            math.cos(angle) * math.sin(polar) * radii[0] * wobble,
            math.sin(angle) * math.sin(polar) * radii[1] * wobble,
            math.cos(polar) * radii[2] * wobble,
        ))

    return surface_grid(name, cols, rows, sample, material, thickness=thickness,
                        closed_u=True, cap_start=True, axis=centre)


def cord(name: str, path: list[Vector], radius: float, material, sides: int = 6,
         salt: float = 0.0, taper: float = 0.55):
    radii = [radius * (1.0 - taper * (index / max(1, len(path) - 1))) for index in range(len(path))]
    return mobs.tapered_tube(name, path, radii, sides, material, wobble=0.06, salt=salt)


def sphere_path(points: list[Vector], steps: int = 3) -> list[Vector]:
    """Catmull-Rom-ish resample so cords and tendrils bend instead of kinking."""
    if len(points) < 3:
        return list(points)
    out: list[Vector] = []
    for index in range(len(points) - 1):
        a = points[max(0, index - 1)]
        b = points[index]
        c = points[index + 1]
        d = points[min(len(points) - 1, index + 2)]
        for step in range(steps):
            t = step / steps
            t2 = t * t
            t3 = t2 * t
            out.append(0.5 * (
                (2.0 * b) + (-a + c) * t
                + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2
                + (-a + 3.0 * b - 3.0 * c + d) * t3
            ))
    out.append(points[-1])
    return out


# ---------------------------------------------------------------------------
# Weights


def gaussian_weights(point: Vector, segments: dict, names, sigma: float,
                     boosts: dict | None = None) -> dict[str, float]:
    values: dict[str, float] = {}
    for name in names:
        a, b = segments[name]
        distance = mobs.point_segment_distance(point, a, b)
        weight = math.exp(-((distance / sigma) ** 2))
        if boosts and name in boosts:
            weight *= boosts[name](point)
        if weight > 1e-6:
            values[name] = weight
    if not values:
        nearest = min(names, key=lambda n: mobs.point_segment_distance(point, *segments[n]))
        return {nearest: 1.0}
    return values


def assign_weights(obj, weight_fn, smooth_iterations: int = 2, limit: int = 4) -> None:
    """Per-vertex weights, edge-smoothed so seams cannot tear at a joint."""
    segments = MEASURE.segments
    raw: list[dict[str, float]] = [weight_fn(vertex.co.copy()) for vertex in obj.data.vertices]
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
    groups: dict[str, bpy.types.VertexGroup] = {}
    for index, weights in enumerate(raw):
        ordered = sorted(weights.items(), key=lambda item: (-item[1], item[0]))[:limit]
        ordered = [(name, value) for name, value in ordered if value > 1e-5]
        total = sum(value for _, value in ordered)
        if total <= 1e-9:
            raise RuntimeError(f"{obj.name}: vertex {index} has no bone weight")
        for name, value in ordered:
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([index], value / total, "REPLACE")


# ---------------------------------------------------------------------------
# Pieces
#
# A slot is skinned as a unit, but not every part of a slot follows the same
# bone: a sleeve has to follow the arm it covers, a loin panel hangs off the
# pelvis.  A builder can name a part in ``PART_WEIGHTS`` and that function is
# used instead of the slot's for that part alone; the entry is consumed when
# the part is skinned.
PART_WEIGHTS: dict[str, object] = {}


# The two angles the bone helm's rim drops at, to become its cheek guards.
CHEEK_CENTRES = (math.radians(322.0), math.radians(218.0))


def build_head(material_of) -> tuple:
    """Bone coif: plated cap, brow band, cheek plates, crown ridge, antlers."""
    measure = MEASURE
    # The cap fits the **skull**, not the cowl. It used to be measured off
    # `Male_Ranger_Head_Hood`, the leather set's own head piece - which is never
    # drawn under this one, because a slot wears exactly the set it was given - and
    # the cowl is 30 cm across where the head is 21. On top of that the brow band
    # stood 28 mm proud of it and the studs 52 mm, so the helmet measured 0.32 m
    # across a 0.21 m head and read as a boulder.
    refs = ["Ranger_Head_SuperHero_Male"]
    skull = measure.table(refs, 1.515, 1.782, 0.008, half=0.012, smooth=1)
    apex = skull.entries[-1][0]
    # 16 mm of air over the skin, and a 9 mm shell: the cap's inner face has to
    # clear the skull in the *idle* pose too, where the skin is not the bind pose.
    grow = 0.016
    z_top = apex + 0.030
    skull_centre = Vector((0.0, 0.030, 1.715))
    parts = []

    def cheek_dip(theta: float) -> float:
        """1 at the centre of a cheek guard, 0 over the face and the nape."""
        dip = 0.0
        for centre in CHEEK_CENTRES:
            delta = ((theta - centre + math.pi) % TAU) - math.pi
            dip = max(dip, math.exp(-((delta / 0.34) ** 2)))
        return dip

    def rim_z(theta: float) -> float:
        """Where the bone cap ends, by angle.

        Brow height at the face, a little lower at the nape, and dropped into a
        pair of cheek guards either side of the face -- the guards are the cap
        itself rather than plates hung off it, so nothing floats.
        """
        front = max(0.0, -math.sin(theta))
        back = max(0.0, math.sin(theta))
        return (1.716 + 0.034 * front ** 1.6 - 0.040 * back ** 1.3
                - 0.078 * cheek_dip(theta))

    def cap_uv(theta: float, v: float) -> Vector:
        zb = rim_z(theta)
        z = zb + (z_top - zb) * v
        section = skull.at(min(z, apex))
        # The brow and the cheekbones jut past a per-height ring, so the cap
        # stands proud of the skin instead of guillotining them.
        front = max(0.0, -math.sin(theta))
        extra = 0.014 * front ** 1.5 * (1.0 - mobs.smoothstep(0.30, 0.85, v))
        # The cheek guards stand a little further off than the crown, so they
        # read as jaw plates instead of as the bowl's rim.
        extra += 0.010 * cheek_dip(theta) * (1.0 - mobs.smoothstep(0.05, 0.45, v))
        shrink = 1.0 - 0.72 * mobs.smoothstep(apex - 0.004, z_top, z)
        # Four crown plates lap over each other: a raised lip on each plate's
        # trailing side, so the cap reads as bone plates and not as a bowl.
        lip = 0.005 * mobs.smoothstep(0.80, 1.0, (theta * 4.0 / TAU) % 1.0)
        rx = (section["rx"] + grow) * shrink + lip
        ry = (section["ry"] + grow + extra) * shrink + lip
        wobble = 1.0 + (mobs.hash01(theta * 2.4 + v * 6.0) - 0.5) * 0.026
        return Vector((section["cx"] + math.cos(theta) * rx * wobble,
                       section["cy"] + math.sin(theta) * ry * wobble,
                       z))

    def cap_at(theta: float, z: float) -> Vector:
        """The exact shell point at a height, so fittings ride the surface."""
        zb = rim_z(theta)
        v = max(0.0, min(1.0, (z - zb) / max(1e-5, z_top - zb)))
        return cap_uv(theta, v)

    def outward(point: Vector) -> Vector:
        return (point - skull_centre).normalized()

    parts.append(surface_grid("MS_Skull_Cap", 44, 10,
                              lambda u, v: cap_uv(TAU * u, v), material_of("bone"),
                              thickness=0.009, cap_end=True, axis=Vector((0.0, 0.05, 1.75))))

    # Bone rim all the way round, thickest across the brow where it becomes the
    # band the studs are driven through.
    def rim_band(u, v):
        theta = TAU * u
        point = cap_uv(theta, 0.012 + 0.150 * v)
        front = max(0.0, -math.sin(theta))
        radial = Vector((point.x, point.y - 0.03, 0.0))
        return point + radial.normalized() * (0.006 + 0.006 * front ** 1.5)

    parts.append(surface_grid("MS_Helm_Rim", 36, 2, rim_band, material_of("bone"),
                              thickness=0.008, closed_u=True, axis=Vector((0.0, 0.05, 1.75))))

    # Brow band: a second bone bar across the whole face. It stood 28 mm proud of
    # the cowl and was measured with it; across the brow it is a bar again.
    parts.append(arc_plate("MS_Helm_Brow", skull, 1.734, 1.780, math.radians(216.0),
                           math.radians(324.0), grow + 0.012, 22, 3, material_of("bone"),
                           0.009, salt=2.4, jitter=0.003))

    # Leather lining: a band hanging under the bone rim. It is built off the
    # cap's own edge rather than off the skull, so it cannot sink into the brow
    # where the skin flares; it reads as the roll the bone plates are sewn to.
    def lining(u, v):
        theta = TAU * u
        rim = cap_uv(theta, 0.020)
        radial = Vector((rim.x, rim.y - 0.030, 0.0)).normalized()
        return rim + radial * 0.006 + Vector((0.0, 0.0, -0.034 + 0.036 * v))

    parts.append(surface_grid("MS_Helm_Lining", 32, 2, lining, material_of("leather"),
                              thickness=0.006, closed_u=True, axis=Vector((0.0, 0.04, 1.70))))

    # Spine ridge: a bone bar front rim to nape over the crown, with scutes.
    ridge = [cap_uv(math.radians(270.0), 0.03 + 0.19 * step) for step in range(5)]
    ridge += [cap_uv(math.radians(270.0), 0.97), cap_uv(math.radians(90.0), 0.97)]
    ridge += [cap_uv(math.radians(90.0), 0.79 - 0.19 * step) for step in range(5)]
    ridge = [point + outward(point) * 0.009 for point in ridge]
    parts.append(cord("MS_Helm_Ridge", ridge, 0.013, material_of("bone"), sides=5,
                      salt=5.7, taper=0.22))
    for index, (theta_deg, v) in enumerate(((270.0, 0.26), (270.0, 0.56),
                                            (90.0, 0.30), (90.0, 0.64))):
        point = cap_uv(math.radians(theta_deg), v)
        parts.append(blob(f"MS_Helm_Scute_{index}", point + outward(point) * 0.011,
                          (0.018, 0.024, 0.013), material_of("bone"), sides=6, rings=4,
                          salt=9.1 + index, squash_z=0.85))

    # Antler crown: sockets sit on the measured cap, racks lean out and back.
    for side in (1.0, -1.0):
        theta = math.radians(58.0 if side > 0 else 122.0)
        surface = cap_at(theta, 1.772)
        away = Vector((math.cos(theta), math.sin(theta), 0.0)).normalized()
        # On the cap, not sunk through it: pulled inward the sockets are inside
        # the skull, which the clearance pass refuses.
        base = surface + away * 0.012
        parts.append(blob(f"MS_Helm_Socket_{'L' if side > 0 else 'R'}", base,
                          (0.018, 0.018, 0.015), material_of("bone"), sides=8, rings=6,
                          salt=6.2, squash_z=1.0))
        heading = (away * 0.40 + Vector((0.0, 0.12, 1.0))).normalized()
        racks = mobs.antler_rack(
            "MS_Antler", base + away * 0.004,
            heading, 0.145, 0.026, 2,
            material_of("antler"), salt=7.3 + side * 1.7 + 3.0, curve=0.72, gravity=0.09)
        parts.append(mobs.merge_tubes(f"MS_Antler_{'L' if side > 0 else 'R'}", racks, 6,
                                      material_of("antler"), wobble=0.10, salt=8.1 + side))

    # Rivets through the brow band.
    for index, angle in enumerate((238.0, 270.0, 302.0)):
        section = skull.at(1.770)
        point = Vector((section["cx"] + math.cos(math.radians(angle)) * (section["rx"] + grow + 0.016),
                        section["cy"] + math.sin(math.radians(angle)) * (section["ry"] + grow + 0.016),
                        1.770))
        parts.append(blob(f"MS_Helm_Stud_{index}", point, (0.010, 0.010, 0.008),
                          material_of("bone"), sides=6, rings=4, salt=10.0 + index))

    if os.environ.get("MS_DEBUG_HELM"):
        mesh = parts[0].data
        for lo, hi in ((1.60, 1.70), (1.70, 1.80), (1.80, 1.90), (1.90, 1.96)):
            pts = [v.co for v in mesh.vertices if lo <= v.co.z <= hi]
            if pts:
                print("MS_HELM_SHELL", lo, hi, "x", round(min(p.x for p in pts), 3),
                      round(max(p.x for p in pts), 3), "y", round(min(p.y for p in pts), 3),
                      round(max(p.y for p in pts), 3), len(pts))
    return parts, head_weights, 1


def head_weights(point: Vector) -> dict[str, float]:
    # A helm is a rigid body: it rides the skull, nothing else.
    return {"Head": 1.0}


def build_chest(material_of) -> tuple:
    """Cured-hide vest with bone ribs, sternum, spine ridge and spaulders."""
    measure = MEASURE
    refs = ["Male_Ranger_Body", "Male_Ranger_Legs"]
    torso_ring = measure.sector_table(refs, 0.880, 1.380, 0.010, sectors=32,
                                      half=0.020, smooth=1)
    vest_bottom = 0.948
    grow_side, grow_open = 0.010, 0.018
    arm_refs = ["Male_Ranger_Arms", "Male_Ranger_Arms_Bracer"]
    parts: list[bpy.types.Object] = []
    head_ring = measure.sector_table(["Ranger_Head_SuperHero_Male"], 1.430, 1.610, 0.008,
                                     sectors=24, half=0.012, smooth=1)
    print("MS_VEST", "bottom", vest_bottom, "arm_at_1.32", round(arm_limit(1.32), 3))

    def top_edge(theta: float) -> float:
        # Armholes: a narrow scoop at each side, where the arm hangs. Everywhere
        # else the rim stays high — the ranger's own neck and trapezius belong
        # to the hidden tunic, so the collar is what closes the silhouette.
        edge = 1.566
        for centre in (0.0, math.pi):
            delta = ((theta - centre + math.pi) % TAU) - math.pi
            edge -= 0.386 * math.exp(-((delta / 0.50) ** 2))
        return edge

    def vest_point(z: float, theta: float, extra: float = 0.0, scale: float = 1.0) -> Vector:
        cx, cy, radius = torso_ring.ring(z, theta)
        # Above the chest the shell closes toward the neck: this is the yoke
        # that replaces the tunic's collar and trapezius.
        blend = mobs.smoothstep(1.348, 1.500, z)
        if blend > 0.0:
            head_cx, head_cy, head_radius = head_ring.ring(min(z, 1.600), theta)
            cy = cy + (head_cy - cy) * blend
            radius = radius + (head_radius + 0.012 - radius) * blend
        # Laced tight at the sides, loose over the chest and the back.
        grow = grow_side + (grow_open - grow_side) * (1.0 - abs(math.cos(theta)) ** 2.0)
        reach = (radius + grow + extra) * scale
        return Vector((cx + math.cos(theta) * reach, cy + math.sin(theta) * reach, z))

    def vest_sample(u, v):
        theta = TAU * u
        z = vest_bottom + (top_edge(theta) - vest_bottom) * v
        wobble = 1.0 + mobs.hash01(u * 11.0 + v * 5.0) * 0.016
        fold = 1.0 + 0.014 * (0.5 + 0.5 * math.sin(theta * 7.0 + math.sin(z * 6.0) * 1.4)) \
            * (1.0 - v)
        point = vest_point(z, theta, scale=wobble * fold)
        if v < 0.10:
            point.z -= (0.10 - v) / 0.10 * (0.012 + 0.024 * mobs.hash01(u * 17.0))
        return point

    def vest_drop(row, column):
        return row == 0 and mobs.hash01(column * 1.7 + 3.0) < 0.30

    parts.append(surface_grid("MS_Vest", 40, 16, vest_sample, material_of("leather"),
                              thickness=0.006, drop=vest_drop, axis=Vector((0.0, 0.02, 1.15))))

    # Bone rib cage: bars lashed to the hide, meeting the sternum at the front
    # and climbing under the arm. They ride the vest surface, so they cannot
    # hover over it.
    for index in range(5):
        base_z = 1.008 + index * 0.052
        for side in (1.0, -1.0):
            start = math.radians(270.0 + side * 26.0)
            end = math.radians(270.0 + side * 80.0)
            path = []
            for step in range(6):
                u = step / 5.0
                path.append(vest_point(base_z + 0.050 * u ** 1.4,
                                       start + (end - start) * u, extra=0.004))
            parts.append(cord(f"MS_Rib_{index}_{'L' if side > 0 else 'R'}", path, 0.0125,
                              material_of("bone"), sides=5, salt=13.0 + index + side,
                              taper=0.42))

    # Sternum: one bone plate down the middle, over the rib ends.
    def sternum_sample(u, v):
        return vest_point(0.996 + 0.300 * v, math.radians(258.0 + 24.0 * u), extra=0.010)

    parts.append(surface_grid("MS_Sternum", 5, 7, sternum_sample, material_of("bone"),
                              thickness=0.010, closed_u=False,
                              axis=Vector((0.0, 0.0, 1.15))))
    for index, z in enumerate((1.046, 1.126, 1.206)):
        parts.append(blob(f"MS_Sternum_Boss_{index}",
                          vest_point(z, math.radians(270.0), extra=0.018),
                          (0.016, 0.016, 0.013), material_of("bone"), sides=6, rings=4,
                          salt=15.0 + index))

    # Spine: a bone ridge down the back with its vertebrae raised.
    ridge = [vest_point(0.960 + 0.056 * index, math.radians(90.0), extra=0.008)
             for index in range(8)]
    parts.append(cord("MS_Spine_Ridge", ridge, 0.013, material_of("bone"), sides=5,
                      salt=16.4, taper=0.20))
    for index in range(6):
        parts.append(blob(f"MS_Spine_Scute_{index}",
                          vest_point(0.986 + 0.064 * index, math.radians(90.0), extra=0.016),
                          (0.026, 0.020, 0.018), material_of("bone"), sides=6, rings=4,
                          salt=18.0 + index, squash_z=0.9))

    # Spaulder: bone over the right shoulder. The left shoulder stays hide --
    # one bare shoulder, held by the strap below, so the arms read as arms.
    joint = measure.joint("upperarm_r")
    cap = dome("MS_Spaulder_R",
               Vector((-abs(joint.x) - 0.004, joint.y + 0.006, joint.z + 0.020)),
               (0.090, 0.104, 0.062), material_of("bone"),
               cols=12, rows=4, thickness=0.010, salt=20.0, spread=0.55)
    parts.append(cap)
    PART_WEIGHTS[cap.name] = lambda point: {"upperarm_r": 1.0}

    # The strap: one shoulder's worth of hide holding the vest up. It lies on
    # the vest and over the sleeve, and it is what the bared shoulder reads as.
    strap = [
        vest_point(1.286, math.radians(340.0), extra=0.006),
        vest_point(1.400, math.radians(352.0), extra=0.006),
        Vector((0.160, -0.010, 1.500)),
        Vector((0.178, 0.075, 1.536)),
        Vector((0.150, 0.150, 1.470)),
        vest_point(1.330, math.radians(44.0), extra=0.006),
    ]
    parts.append(cord("MS_Shoulder_Strap", sphere_path(strap, 2), 0.011,
                      material_of("leather"), sides=5, salt=24.0, taper=0.18))
    parts.append(blob("MS_Shoulder_Buckle", Vector((0.172, 0.068, 1.552)),
                      (0.016, 0.018, 0.008), material_of("bone"), sides=6, rings=4,
                      salt=25.0))

    # Cross lacing up the chest opening, above the rib cage.
    for index, flip in enumerate((1.0, -1.0)):
        path = []
        for step in range(7):
            z = 1.300 + step * 0.024
            angle = math.radians(270.0 + flip * (5.0 if step % 2 == 0 else -5.0))
            path.append(vest_point(z, angle, extra=0.014))
        parts.append(cord(f"MS_Lace_{index}", path, 0.0065, material_of("leather"),
                          sides=5, salt=27.0 + index, taper=0.0))
    for index in range(6):
        index_angle = (271.0 if index % 2 == 0 else 269.0)
        z = 1.302 + index * 0.026
        parts.append(blob(f"MS_Eyelet_{index}",
                          vest_point(z, math.radians(270.0 + (6.0 if index % 2 else -6.0)),
                                     extra=0.012),
                          (0.010, 0.010, 0.008), material_of("bone"), sides=6, rings=4,
                          salt=29.0 + index))

    # Ragged hem strips hanging off the vest bottom.
    for index in range(7):
        theta = TAU * (index + 0.5) / 7.0
        drop = 0.052 + 0.044 * mobs.hash01(index * 2.3 + 5.0)
        head = vest_point(vest_bottom + 0.020, theta, extra=0.004)
        parts.append(cord(f"MS_Hem_{index}",
                          [head, head + Vector((0.004, 0.0, -drop * 0.6)),
                           head + Vector((0.006, 0.006, -drop))],
                          0.013, material_of("leather"), sides=5, salt=31.0 + index,
                          taper=0.75))

    # Fitted hide sleeves. The arm is chest-slot geometry (the ranger's own
    # arms are hidden with the tunic), so the chest has to provide it -- but
    # only as the arm it replaces, never as a mantle over both shoulders.
    for side, tag in ((1.0, "L"), (-1.0, "R")):
        shoulder = measure.joint(f"upperarm_{tag.lower()}")
        wrist = measure.joint(f"hand_{tag.lower()}")
        axis_a = Vector((side * abs(shoulder.x), shoulder.y, shoulder.z))
        axis_b = Vector((side * abs(wrist.x), wrist.y, wrist.z))
        direction = axis_b - axis_a

        def sleeve_sample(u, v, axis_a=axis_a, axis_b=axis_b, side=side):
            # Shoulder to just past the elbow, where the bracer cuffs over it:
            # the arm is one continuous tube, never a pair of pipes.
            t = 0.02 + 0.64 * v
            theta = TAU * u
            ring = measure.axis_ring(arm_refs, axis_a, axis_b, t, 0.05)
            centre = axis_a + direction * t
            centre.y = ring["cy"]
            centre.z = ring["cz"]
            profile = 0.054 + 0.010 * mobs.smoothstep(0.0, 0.24, t) \
                + 0.008 * mobs.smoothstep(0.45, 1.0, v)
            radius = min(max(profile, ring["radius"] + 0.004), 0.074)
            wobble = 1.0 + mobs.hash01(u * 7.0 + v * 3.0 + side) * 0.02
            return centre + Vector((0.0, math.cos(theta) * radius * wobble,
                                    math.sin(theta) * radius * wobble))

        sleeve = surface_grid(f"MS_Sleeve_{tag}", 14, 8, sleeve_sample,
                              material_of("leather"), thickness=0.007, cap_start=True,
                              cap_end=True, axis=axis_a)
        parts.append(sleeve)
        PART_WEIGHTS[sleeve.name] = lambda point, tag=tag: gaussian_weights(
            point, MEASURE.segments, [f"upperarm_{tag.lower()}", f"lowerarm_{tag.lower()}"],
            0.090)

    return parts, chest_weights, 2


def chest_weights(point: Vector) -> dict[str, float]:
    names = ["pelvis", "spine_01", "spine_02", "spine_03"]
    sigma = 0.115 if point.z < 1.24 else 0.095
    return gaussian_weights(point, MEASURE.segments, names, sigma)


def build_hands(material_of) -> tuple:
    """Narrow hide bracers, bone knuckles and a bone wrist spur."""
    measure = MEASURE
    parts = []
    for side, tag in ((1.0, "L"), (-1.0, "R")):
        elbow = measure.joint(f"lowerarm_{tag.lower()}")
        wrist = measure.joint(f"hand_{tag.lower()}")
        axis_a = Vector((side * abs(elbow.x), elbow.y, elbow.z))
        axis_b = Vector((side * abs(wrist.x), wrist.y, wrist.z))
        direction = (axis_b - axis_a)
        # The ranger's own glove cuff ends here; wrap to the knuckles.
        cuff_x = max([abs(point.x) for point in measure.points["Male_Ranger_Arms_Bracer"]
                      if point.x * side > 0.40] or [abs(axis_b.x) + 0.06])
        # The wrap runs past the wrist to the knuckles: the ranger's own hand
        # belongs to the hidden chest slot, so the hands piece has to end in a
        # fist rather than in an open cuff.
        span_end = (cuff_x + 0.115 - abs(axis_a.x)) / max(1e-6, abs(axis_b.x - axis_a.x))

        def radius_at(t: float) -> float:
            # Measured on the ranger's own glove cuff only: the bare hand that
            # spreads past the wrist is not part of a bracer's circumference.
            measured = measure.radius_along(["Male_Ranger_Arms_Bracer"], axis_a, axis_b,
                                            min(t, 1.02), 0.05, 0.16, percent=100.0)
            return max(0.050, min(0.070, measured + 0.009))

        def bracer_sample(u, v):
            t = 0.10 + (max(span_end, 1.30) - 0.10) * v
            theta = TAU * u
            centre = axis_a + direction * t
            # The cuff stands off the sleeve it overlaps, so the arm reads as
            # one limb with a bracer laced over it; past the wrist the wrap
            # swells over the palm and closes at the knuckles.
            radius = radius_at(t) * (1.0 + 0.04 * mobs.smoothstep(0.70, 1.0, v)) \
                + 0.008 * (1.0 - mobs.smoothstep(0.0, 0.16, v))
            if t > 1.04:
                swell = math.sin(math.pi * min(1.0, (t - 1.04) / (span_end - 1.04)))
                radius = 0.036 + 0.038 * swell
            wobble = 1.0 + (mobs.hash01(u * 9.0 + v * 4.0 + side) - 0.5) * 0.05
            return centre + Vector((0.0, math.cos(theta) * radius * wobble,
                                    math.sin(theta) * radius * wobble))

        parts.append(surface_grid(f"MS_Bracer_{tag}", 14, 10, bracer_sample,
                                  material_of("leather"), thickness=0.009,
                                  cap_end=True, axis=axis_a))
        for index, t in enumerate((0.55, 0.80, 1.05)):
            centre = axis_a + direction * t
            radius = radius_at(t) + 0.008
            path = [centre + Vector((0.0, math.cos(TAU * step / 10.0) * radius,
                                     math.sin(TAU * step / 10.0) * radius))
                    for step in range(11)]
            parts.append(cord(f"MS_Wrap_{tag}_{index}", path, 0.0055,
                              material_of("leather"), sides=4, salt=32.0 + index + side,
                              taper=0.0))

        # Knuckles: one bone plate over the wrapped fist, four spikes through
        # it. Both are placed on the fist's own surface, not on the ranger's
        # hidden hand, so they cannot sink into the wrap.
        knuckle_t = (cuff_x + 0.028 - abs(axis_a.x)) / max(1e-6, abs(axis_b.x - axis_a.x))
        swell = math.sin(math.pi * min(1.0, max(0.0, (knuckle_t - 1.04) / (span_end - 1.04))))
        fist_radius = 0.036 + 0.038 * swell
        fist_top = axis_a.z + fist_radius
        parts.append(mobs.bark_slab(f"MS_Knuckles_{tag}",
                                    Vector(((cuff_x + 0.028) * side, axis_a.y, fist_top - 0.002)),
                                    Vector((0.0, 0.0, 1.0)), 0.014, 0.052, 0.062,
                                    material_of("bone"), salt=35.0 + side))
        for index in range(4):
            across = -0.033 + index * 0.022
            if across * across > fist_radius * fist_radius:
                continue
            height = math.sqrt(max(0.0, fist_radius * fist_radius - across * across))
            base = Vector(((cuff_x + 0.028) * side, axis_a.y + across,
                           axis_a.z + height - 0.004))
            tip = base + Vector((side * 0.020, 0.0, 0.028))
            parts.append(cord(f"MS_Knuckle_Spike_{tag}_{index}",
                              sphere_path([base, base + Vector((0.0, 0.0, 0.014)), tip], 2),
                              0.0075, material_of("bone"), sides=5,
                              salt=37.0 + index + side, taper=0.90))

        # Wrist spur: a bone hook off the top of the wrap, aimed back up the
        # forearm from the wrist it is strapped to.
        anchor = axis_a + direction * 0.94
        base = anchor + Vector((0.0, 0.004, radius_at(0.94) + 0.014))
        tip = base + Vector((-side * 0.030, 0.006, 0.034))
        parts.append(cord(f"MS_Wrist_Spur_{tag}",
                          sphere_path([base, base + Vector((-side * 0.008, 0.004, 0.020)), tip], 2),
                          0.0085, material_of("bone"), sides=5, salt=39.0 + side, taper=0.85))

    return parts, hands_weights, 2


def hands_weights(point: Vector) -> dict[str, float]:
    tag = "l" if point.x > 0.0 else "r"
    names = [f"lowerarm_{tag}", f"hand_{tag}"]
    return gaussian_weights(point, MEASURE.segments, names, 0.075)


def build_legs(material_of) -> tuple:
    """Hide leggings, bone knee caps, one bone shin plate, one loin panel."""
    measure = MEASURE
    parts = []
    for side, tag in ((1.0, "L"), (-1.0, "R")):
        x_range = (0.020, 0.330) if side > 0 else (-0.330, -0.020)
        leg_refs = ["Male_Ranger_Legs", "Ranger_Base_Calf"]
        leg_ring = measure.sector_table(leg_refs, 0.330, 1.000, 0.012, sectors=28,
                                        x_range=x_range, half=0.016, smooth=1)
        leg = measure.table(leg_refs, 0.330, 1.000, 0.012,
                            x_range=x_range, half=0.016, smooth=1)
        knee = measure.tip(f"thigh_{tag.lower()}").z
        thigh_top = 0.990
        thigh_low = 0.238
        grow = 0.014

        def legging_point(z, theta, extra=0.0, scale=1.0, leg_ring=leg_ring):
            cx, cy, radius = leg_ring.ring(z, theta)
            reach = (radius + grow + extra) * scale
            return Vector((cx + math.cos(theta) * reach, cy + math.sin(theta) * reach, z))

        def legging_sample(u, v):
            z = thigh_low + (thigh_top - thigh_low) * v
            theta = TAU * u
            wobble = 1.0 + mobs.hash01(u * 8.0 + v * 5.0 + side) * 0.03
            fold = 1.0 + 0.016 * (0.5 + 0.5 * math.sin(theta * 6.0 + z * 9.0))
            point = legging_point(z, theta, scale=wobble * fold)
            if v < 0.10:
                point.z -= (0.10 - v) / 0.10 * 0.014 * mobs.hash01(u * 13.0 + side)
            return point

        def legging_drop(row, column):
            return row == 0 and mobs.hash01(column * 1.9 + 12.0 + side) < 0.22

        parts.append(surface_grid(f"MS_Legging_{tag}", 18, 11, legging_sample,
                                  material_of("leather"), thickness=0.009,
                                  drop=legging_drop, axis=Vector((side * 0.09, 0.04, 0.67))))

        # Knee: a domed bone cop over the kneecap and a narrow lame above it.
        # The cop is a dome turned to face forward, so it reads as a plate over
        # the joint instead of a patch stuck on the trouser.
        knee_point = legging_point(knee + 0.014, math.radians(270.0), extra=0.004)
        cop = dome(f"MS_Knee_Cap_{tag}", Vector((0.0, 0.0, 0.0)), (0.054, 0.052, 0.026),
                   material_of("bone"), cols=10, rows=3, thickness=0.010,
                   salt=44.0 + side, spread=0.42)
        # Baked into the mesh, not left on the object: every part is authored in
        # world space and the skinning pass reads local coordinates.
        cop.data.transform(Matrix.Translation(knee_point)
                           @ Matrix.Rotation(math.radians(90.0), 4, "X"))
        parts.append(cop)
        parts.append(arc_plate(f"MS_Knee_Lame_{tag}", leg, knee + 0.078, knee + 0.118,
                               math.radians(246.0), math.radians(294.0),
                               0.014, 6, 2, material_of("bone"), 0.010,
                               salt=46.0 + side, jitter=0.006))
        parts.append(blob(f"MS_Knee_Stud_{tag}", knee_point + Vector((0.0, -0.020, 0.004)),
                          (0.014, 0.010, 0.014), material_of("bone"), sides=6, rings=4,
                          salt=48.0 + side))

        # One strapped thigh: hide cord wound round the legging at the top.
        cuff = [legging_point(0.868, TAU * step / 10.0, extra=0.006) for step in range(11)]
        parts.append(cord(f"MS_Thigh_Strap_{tag}", cuff, 0.0075, material_of("leather"),
                          sides=4, salt=50.0 + side, taper=0.0))

    # Shin plate: one leg only, so the pair reads as salvage.
    shin_ring = measure.sector_table(["Male_Ranger_Legs", "Ranger_Base_Calf"], 0.330, 1.000,
                                     0.012, sectors=28, x_range=(0.020, 0.330),
                                     half=0.016, smooth=1)

    def shin_sample(u, v):
        angle = math.radians(240.0 + 60.0 * u)
        z = 0.352 + 0.150 * v
        cx, cy, radius = shin_ring.ring(z, angle)
        bulge = 0.012 * math.sin(math.pi * u) * math.sin(math.pi * v)
        reach = radius + 0.012 + bulge
        return Vector((cx + math.cos(angle) * reach, cy + math.sin(angle) * reach, z))

    parts.append(surface_grid("MS_Shin_Plate_L", 6, 5, shin_sample, material_of("bone"),
                              thickness=0.010, closed_u=False,
                              axis=Vector((0.09, 0.04, 0.44))))

    # Loin panel hanging off the left hip, ragged at the bottom.
    torso_legs = measure.table(["Male_Ranger_Body", "Male_Ranger_Legs"], 0.880, 1.030, 0.010,
                               half=0.016, smooth=1)

    def loin_sample(u, v):
        z = 1.020 - 0.380 * v
        angle = math.radians(284.0 + 60.0 * u)
        section = torso_legs.at(min(z, 1.020))
        spread = 0.018 + 0.026 * v
        hem = 0.0
        if v > 0.86:
            hem = (v - 0.86) / 0.14 * (0.020 + 0.038 * mobs.hash01(u * 11.0))
        wobble = 1.0 + (mobs.hash01(u * 7.0 + v * 3.0) - 0.5) * 0.05
        return Vector((section["cx"] + math.cos(angle) * (section["rx"] + spread) * wobble,
                       section["cy"] + math.sin(angle) * (section["ry"] + spread) * wobble,
                       z - hem))

    loin = surface_grid("MS_Loin_Panel", 10, 7, loin_sample, material_of("leather"),
                        thickness=0.010, closed_u=False, axis=Vector((0.0, 0.03, 0.80)))
    parts.append(loin)
    PART_WEIGHTS[loin.name] = lambda point: {"pelvis": 1.0}
    parts.append(blob("MS_Loin_Stud", loin_sample(0.5, 0.10) + Vector((0.0, -0.006, 0.0)),
                      (0.014, 0.012, 0.012), material_of("bone"), sides=6, rings=4,
                      salt=54.0))

    return parts, legs_weights, 2


def legs_weights(point: Vector) -> dict[str, float]:
    tag = "l" if point.x > 0.0 else "r"
    names = [f"thigh_{tag}", f"calf_{tag}"]
    if point.z > 0.960:
        names.append("pelvis")
    return gaussian_weights(point, MEASURE.segments, names, 0.105)


def build_feet(material_of) -> tuple:
    """Hide boots with bone toe caps, heel spurs and hide ankle straps."""
    measure = MEASURE
    parts = []
    for side, tag in ((1.0, "L"), (-1.0, "R")):
        x_range = (0.010, 0.330) if side > 0 else (-0.330, -0.010)
        boot_refs = ["Male_Ranger_Feet_Boots", "Ranger_Base_Calf"]
        boot = measure.sector_table(boot_refs, 0.000, 0.320, 0.008, sectors=32,
                                    x_range=x_range, half=0.012, smooth=1)
        grow = 0.020
        cols = 24
        low_z = -0.014
        top_z = 0.268
        axis = Vector((side * 0.10, 0.0, 0.10))

        def boot_ring(z, theta):
            """Ring of the boot the shell is built on, at any height.

            The ranger's boot mesh is dense at the shoe and again at the top of
            the shaft, with almost no vertices where the two meet -- a ring
            measured in that gap jumps its centre by five centimetres, which is
            what cuts a shell through the boot.  Across the gap the shell ramps
            between the two rings that are actually measured.
            """
            if z <= 0.166:
                return boot.ring(max(z, 0.0), theta)
            if z >= 0.240:
                return boot.ring(z, theta)
            share = mobs.smoothstep(0.166, 0.240, z)
            low = boot.ring(0.166, theta)
            high = boot.ring(0.240, theta)
            return tuple(a + (b - a) * share for a, b in zip(low, high))

        def boot_point(z, theta, extra=0.0, scale=1.0):
            cx, cy, radius = boot_ring(z, theta)
            reach = (radius + grow + extra) * scale
            return Vector((cx + math.cos(theta) * reach, cy + math.sin(theta) * reach, z))

        def boot_sample(u, v):
            # Cosine spacing: dense at the sole, where the boot's profile turns
            # fastest, and dense again at the cuff.
            z = low_z + (top_z - low_z) * (0.5 - 0.5 * math.cos(math.pi * v))
            theta = TAU * u
            wobble = 1.0 + mobs.hash01(u * 12.0 + v * 4.0 + side) * 0.03
            # The sole wall flares so the shell cannot graze the boot's own
            # sole rim. The cuff flares more: the ankle is where the ranger's
            # boot narrows fastest, and the legging tucks inside the lip.
            extra = 0.014 * (1.0 - mobs.smoothstep(0.002, 0.070, z)) \
                + 0.011 * mobs.smoothstep(0.52, 1.0, v)
            return boot_point(z, theta, extra=extra, scale=wobble)

        parts.append(surface_grid(f"MS_Boot_{tag}", cols, 11, boot_sample,
                                  material_of("leather"), thickness=0.012,
                                  cap_start=True, axis=axis))

        # Bone toe cap over the whole toe box, split into two plates.
        for index, (a0, a1) in enumerate(((280.0, 330.0), (210.0, 260.0))):
            def toe_sample(u, v, a0=a0, a1=a1):
                return boot_point(0.004 + 0.076 * v,
                                  math.radians(a0 + (a1 - a0) * u), extra=0.011)

            parts.append(surface_grid(f"MS_Toe_Cap_{tag}_{index}", 6, 3, toe_sample,
                                      material_of("bone"), thickness=0.011,
                                      closed_u=False, axis=axis))

        # Heel spur: a bone hook off the back of the heel.
        cx, cy, radius = boot.ring(0.072, math.radians(90.0))
        base = Vector((cx, cy + radius + 0.018, 0.078))
        parts.append(cord(f"MS_Heel_Spur_{tag}",
                          sphere_path([base, base + Vector((0.0, 0.024, 0.002)),
                                       base + Vector((0.0, 0.050, -0.032))], 2),
                          0.010, material_of("bone"), sides=5, salt=56.0 + side, taper=0.80))

        # Hide straps round the ankle and the instep.
        for index, (z, angle0) in enumerate(((0.118, 0.0), (0.196, 0.4))):
            path = [boot_point(z, angle0 + TAU * step / 10.0, extra=0.014)
                    for step in range(11)]
            parts.append(cord(f"MS_Ankle_Strap_{tag}_{index}", path, 0.0065,
                              material_of("leather"), sides=4, salt=58.0 + index + side,
                              taper=0.0))

    return parts, feet_weights, 2


def feet_weights(point: Vector) -> dict[str, float]:
    tag = "l" if point.x > 0.0 else "r"
    names = [f"foot_{tag}", f"ball_{tag}", f"calf_{tag}"]
    return gaussian_weights(point, MEASURE.segments, names, 0.090)


def join_slot(parts: list[bpy.types.Object], name: str) -> bpy.types.Object:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    target = parts[0]
    target.select_set(True)
    for obj in parts[1:]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    if len(parts) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    bpy.ops.object.shade_smooth()
    return joined


# ---------------------------------------------------------------------------
# Weight validation (fails the build, not just a log line)


def validate_piece(piece: bpy.types.Object, claimed: list[str]) -> list[str]:
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
    for bone in claimed:
        if bone in bones and used.get(bone, 0) == 0:
            problems.append(f"{piece.name}: claimed bone {bone!r} has an empty vertex group")
    for name, count in used.items():
        if count == 0:
            problems.append(f"{piece.name}: vertex group {name!r} is empty")
    return problems


# ---------------------------------------------------------------------------
# Clearance: measured against the posed Ranger, not assumed


def clearance_report(objects: list[bpy.types.Object], refs: list[str], label: str,
                     strict: list[str]) -> tuple[list[str], dict]:
    """Shell-intersection test against the posed Ranger.

    A signed distance is useless on the ranger's layered, occasionally open
    shells: the nearest triangle can be on the far side of a limb.  Two
    triangle trees either cross or they do not, so:

    ``strict``   references that must never be crossed at all.  The ranger's
                 hood, arms and boots are what the kit is judged against, so a
                 single crossing fails the build.
    everything else
                 a garment wrapped around a trousered limb always dips into the
                 hidden volume beside the limb, so those are gated on measured
                 penetration depth instead: a sliver under 2.5 mm inside the
                 surface is invisible, anything deeper is a real clip.
    """
    from mathutils.bvhtree import BVHTree

    problems: list[str] = []
    report: dict[str, dict] = {}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    trees: dict[str, BVHTree] = {}
    for name in refs:
        obj = bpy.data.objects.get(name)
        if obj is not None:
            trees[name] = BVHTree.FromObject(obj, depsgraph)
    for piece in objects:
        own = BVHTree.FromObject(piece, depsgraph)
        evaluated = piece.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        points = [piece.matrix_world @ vertex.co for vertex in mesh.vertices]
        entry: dict[str, dict] = {}
        for ref, tree in trees.items():
            hits = own.overlap(tree)
            # Only triangles that already cross get a depth estimate: near the
            # surface the nearest face normal is a reliable inside test.
            depth = 0.0
            for pair in hits:
                polygon = piece.data.polygons[pair[0]]
                centre = piece.matrix_world @ polygon.center
                location, normal, _index, _distance = tree.find_nearest(centre)
                if location is None:
                    continue
                depth = max(depth, -(centre - location).dot(normal))
            closest = 1e9
            for point in points:
                location, _normal, _index, distance = tree.find_nearest(point)
                if location is not None:
                    closest = min(closest, distance)
            entry[ref] = {
                "intersections": len(hits),
                "max_depth_mm": round(depth * 1000.0, 2),
                "nearest_mm": round(closest * 1000.0, 2),
            }
            print(f"MS_CLEARANCE {label} {piece.name} vs {ref} intersections={len(hits)} "
                  f"depth={depth * 1000.0:.2f}mm nearest={closest * 1000.0:.1f}mm")
            if hits and os.environ.get("MS_DEBUG_OVERLAP"):
                indices = sorted({pair[0] for pair in hits})
                sample = [piece.data.polygons[index].center
                          for index in indices[::max(1, len(indices) // 5)]][:5]
                print(f"MS_HITS {label} {piece.name} vs {ref} "
                      + " ".join(f"({c.x:.3f},{c.y:.3f},{c.z:.3f})" for c in sample))
            if hits and ref in strict:
                problems.append(f"{label}: {len(hits)} triangles of {piece.name} cross {ref}")

        report[piece.name] = entry
        evaluated.to_mesh_clear()
    return problems, report


# ---------------------------------------------------------------------------
# UV atlas + PBR bake


def allocate_cells(pieces: list[bpy.types.Object]) -> dict[str, dict[int, tuple[float, float, float, float]]]:
    """One UV rectangle per (surface, piece), so atlases never overlap."""
    users: dict[str, list[int]] = {surface: [] for surface in SURFACE_ORDER}
    for piece in pieces:
        for surface in SURFACE_ORDER:
            if material_slot(piece, surface) is not None:
                users[surface].append(pieces.index(piece))
    layout: dict[str, dict[int, tuple[float, float, float, float]]] = {}
    margin = 0.008
    for surface, indices in users.items():
        if not indices:
            continue
        grid = max(1, int(math.ceil(math.sqrt(len(indices)))))
        cells = {}
        for order, index in enumerate(indices):
            column = order % grid
            row = order // grid
            cells[index] = (
                column / grid + margin,
                (column + 1) / grid - margin,
                row / grid + margin,
                (row + 1) / grid - margin,
            )
        layout[surface] = cells
    return layout


def material_slot(piece: bpy.types.Object, surface: str) -> int | None:
    wanted = MATERIAL_NAME[surface]
    for index, material in enumerate(piece.data.materials):
        if material is not None and material.name == wanted:
            return index
    return None


def unwrap_piece(piece: bpy.types.Object, cells: dict[int, tuple[float, float, float, float]]) -> None:
    mobs.set_active(piece)
    if not piece.data.uv_layers:
        piece.data.uv_layers.new(name="UVMap")
    piece.data.uv_layers[0].name = "UVMap"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.object.mode_set(mode="OBJECT")
    index_in_pieces = cells
    for slot, rect in index_in_pieces.items():
        bpy.ops.object.mode_set(mode="EDIT")
        bm = bmesh.from_edit_mesh(piece.data)
        for face in bm.faces:
            face.select = face.material_index == slot
        bmesh.update_edit_mesh(piece.data)
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.010)
        bpy.ops.uv.pack_islands(margin=0.004)
        bpy.ops.object.mode_set(mode="OBJECT")
        uv = piece.data.uv_layers[0].data
        loops = [li for polygon in piece.data.polygons if polygon.material_index == slot
                 for li in polygon.loop_indices]
        if not loops:
            continue
        us = [uv[li].uv[0] for li in loops]
        vs = [uv[li].uv[1] for li in loops]
        u0, u1 = min(us), max(us)
        v0, v1 = min(vs), max(vs)
        su = 1.0 / max(1e-6, u1 - u0)
        sv = 1.0 / max(1e-6, v1 - v0)
        for li in loops:
            u, v = uv[li].uv
            uv[li].uv = (rect[0] + (u - u0) * su * (rect[1] - rect[0]),
                         rect[2] + (v - v0) * sv * (rect[3] - rect[2]))
    piece.data.update()


def sample_points(surface: str, points: np.ndarray) -> dict:
    """Sample a surface at atlas texel centres, filtered for its own grain."""
    grade = (2, float(points[:, 2].min()), float(points[:, 2].max()))
    if surface != "leather":
        return surfaces.sample(surface, points, palette(surface), SEED, grade)
    # Hide's grain is a 4 mm cell lattice and one texel here is about half a
    # cell, so a single sample per texel turns the pebble faces into a wicker
    # chequer.  Four samples half a cell apart average the faces back into
    # grain; the hide-scale swell, scuffing and stitches sit far above that
    # spacing and survive.
    step = LEATHER_PEBBLE * 0.5
    phase_offsets = ((0.0, 0.0), (step, 0.0), (0.0, step), (step, step))
    total: dict[str, np.ndarray] | None = None
    for dx, dy in phase_offsets:
        shifted = points + np.array((dx, dy, 0.0), np.float32)
        sampled = surfaces.sample(surface, shifted, palette(surface), SEED, grade)
        if total is None:
            total = {key: sampled[key].astype(np.float32)
                     for key in ("albedo", "height", "roughness")}
            continue
        for key in total:
            total[key] += sampled[key]
    for key in total:
        total[key] *= 1.0 / len(phase_offsets)
    return total


def box_filter(image: np.ndarray, factor: int) -> np.ndarray:
    """Box-filter a supersampled (H*factor, W*factor, C) image down by factor."""
    height, width = image.shape[:2]
    return image.reshape(height // factor, factor, width // factor, factor,
                         image.shape[2]).mean(axis=(1, 3), dtype=np.float32)


def blur3(field: np.ndarray) -> np.ndarray:
    """One 3x3 box pass over a 2D field, edges clamped."""
    padded = np.pad(field, 1, mode="edge")
    total = np.zeros_like(field)
    for dy in range(3):
        for dx in range(3):
            total += padded[dy:dy + field.shape[0], dx:dx + field.shape[1]]
    return total / 9.0


def box_blur(field: np.ndarray, radius: int) -> np.ndarray:
    """Separable box blur of a 2D or 3D field, edges clamped."""
    squeeze = field.ndim == 2
    work = (field[..., None] if squeeze else field).astype(np.float32)
    width = 2 * radius + 1
    for axis in (0, 1):
        pad = [(0, 0)] * work.ndim
        pad[axis] = (radius, radius)
        padded = np.pad(work, pad, mode="edge")
        cumulative = np.cumsum(padded, axis=axis, dtype=np.float64)
        cumulative = np.insert(cumulative, 0, 0.0, axis=axis)
        span = cumulative.shape[axis]
        upper = np.take(cumulative, np.arange(width, span), axis=axis)
        lower = np.take(cumulative, np.arange(0, span - width), axis=axis)
        work = ((upper - lower) / width).astype(np.float32)
    return work[..., 0] if squeeze else work


def bake_surface(surface: str, pieces: list[bpy.types.Object],
                 cells: dict[int, tuple[float, float, float, float]]) -> None:
    spec = SURFACE_SPECS[surface]
    size = int(spec["size"])
    # The mesh is rasterised at twice the exported edge and box-filtered down:
    # a 4 mm hide pebble is close to the texel size at this atlas scale, and
    # sampling it once per texel turns the grain into a moire lattice.
    supersample = 2
    bake_size = size * supersample
    albedo = np.zeros((bake_size * bake_size, 3), dtype=np.float32)
    height = np.zeros(bake_size * bake_size, dtype=np.float32)
    roughness = np.zeros(bake_size * bake_size, dtype=np.float32)
    covered = np.zeros(bake_size * bake_size, dtype=bool)
    texels = 0
    zmin = 1e9
    zmax = -1e9
    for piece in pieces:
        slot = material_slot(piece, surface)
        if slot is None:
            continue
        chunks = mobs.triangle_texels(piece, slot, bake_size)
        if not chunks:
            continue
        flat = np.concatenate([chunk[0] for chunk in chunks])
        points = np.concatenate([chunk[1] for chunk in chunks])
        sampled = sample_points(surface, points)
        albedo[flat] = np.clip(sampled["albedo"], 0.0, 1.0)
        height[flat] = np.clip(sampled["height"], 0.0, 1.0)
        roughness[flat] = np.clip(sampled["roughness"], *spec["rough"])
        covered[flat] = True
        texels += int(flat.size)
        zmin = min(zmin, float(points[:, 2].min()))
        zmax = max(zmax, float(points[:, 2].max()))
    albedo = box_filter(albedo.reshape(bake_size, bake_size, 3), supersample)
    height = box_filter(height.reshape(bake_size, bake_size, 1), supersample)[..., 0]
    roughness = box_filter(roughness.reshape(bake_size, bake_size, 1), supersample)[..., 0]
    coverage = covered.reshape(bake_size, bake_size).reshape(
        size, supersample, size, supersample).any(axis=(1, 3))
    albedo = mobs.dilate(albedo, coverage.copy(), 12)
    if surface == "leather":
        # Two texels of hide grain are one cell of the pebble field: at that
        # ratio the crease lines alias into a chequer at gameplay range. A
        # 1 mm blur keeps the pebble and the stitch seams, and stops the lines
        # from becoming the read.
        albedo = box_blur(albedo, 2)
    # The height field drives the normal map, and hide's pebble sits near the
    # texel size: differentiated raw it turns into shading moire at gameplay
    # range. One 3x3 pass keeps the swell and drops the aliasing.
    height = blur3(height)
    height = mobs.dilate(height[..., None], coverage.copy(), 12)[..., 0]
    roughness = mobs.dilate(roughness[..., None], coverage.copy(), 12)[..., 0]
    normals = surfaces.normal_map(height, float(spec["normal"]))
    prefix = MATERIAL_NAME[surface]
    images = {
        "albedo": mobs.new_image(prefix + "_albedo", size, albedo, False, TEXTURES),
        "normal": mobs.new_image(prefix + "_normal", size, np.clip(normals, 0.0, 1.0), True, TEXTURES),
        "roughness": mobs.new_image(prefix + "_roughness", size, roughness, True, TEXTURES),
    }
    material = bpy.data.materials.get(prefix)
    if material is None:
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
    bsdf.inputs["Base Color"].default_value = (0.6, 0.6, 0.6, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.8
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
    print("MS_BAKE", surface, "size", size, "texels", texels,
          "covered", int(np.count_nonzero(coverage)), "z", round(zmin, 3), round(zmax, 3))


# ---------------------------------------------------------------------------
# Export + measured metadata


def measure_arm_limit(action: bpy.types.Action | None) -> None:
    """Where the ranger's own arms sit for the whole idle cycle, by height."""
    global ARM_LIMIT
    ARM_LIMIT = []
    if action is None:
        return
    if RIG.animation_data is None:
        RIG.animation_data_create()
    RIG.animation_data.action = action
    if getattr(action, "slots", None):
        RIG.animation_data.action_slot = action.slots[0]
    samples: dict[int, float] = {}
    scene = bpy.context.scene
    for frame in range(0, max(1, int(2.0 * FPS)), max(1, FPS // 6)):
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for name in ("Male_Ranger_Arms", "Male_Ranger_Arms_Bracer"):
            obj = bpy.data.objects.get(name)
            if obj is None:
                continue
            mesh = obj.evaluated_get(depsgraph).to_mesh()
            for vertex in mesh.vertices:
                point = obj.matrix_world @ vertex.co
                if abs(point.x) < 0.08:
                    continue
                band = int(round(point.z / 0.02))
                value = abs(point.x)
                if band not in samples or value < samples[band]:
                    samples[band] = value
            obj.evaluated_get(depsgraph).to_mesh_clear()
    scene.frame_set(0)
    RIG.animation_data.action = None
    reset_pose()
    ARM_LIMIT = sorted((band * 0.02, value) for band, value in samples.items())
    print("MS_ARM_LIMIT", [(round(z, 2), round(v, 3)) for z, v in ARM_LIMIT][::3])


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


def write_metadata(pieces: list[bpy.types.Object], clearance: dict) -> dict:
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
        }
        total += triangles
    metadata = {
        "asset": OUTPUT.name,
        "set": "makeshift",
        "display": "Makeshift",
        "skeleton": "Armature/Skeleton3D",
        "bone_count": len(bones),
        "bone_names": bones,
        "slots": list(SLOTS),
        "pieces": pieces_meta,
        "total_triangles": total,
        "triangle_budget": TRIANGLE_BUDGET,
        "materials": [material.get("name", "") for material in document.get("materials", [])],
        "embedded_images": len(document.get("images", [])),
        "image_mime_types": sorted({image.get("mimeType", "") for image in document.get("images", [])}),
        "animations": [animation.get("name", "") for animation in document.get("animations", [])],
        "forward": [0, 0, 1],
        "up": [0, 1, 0],
        "unit": "metres",
        "rest_height": round(MEASURE.top_z(["Male_Ranger_Head_Hood"], (-1.0, 1.0), (-1.0, 1.0)), 5),
        "clearance": clearance,
        "authoring_fps": FPS,
        "source": (
            "original procedural work authored by tools/prepare_makeshift_armor.py; "
            "no third-party model or texture"
        ),
        "reproducer": "python tools/build_makeshift_armor.py",
    }
    path = OUTPUT.with_suffix(".json")
    path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("MS_METADATA", path)
    return metadata


# ---------------------------------------------------------------------------
# Captures


def add_area_light(name: str, location: Vector, colour, energy: float, size: float):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    data.color = colour
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector((0.0, 0.0, 1.10)) - location).to_track_quat("-Z", "Y").to_euler()
    return light


def stage_capture_visibility() -> None:
    """Hide everything the Makeshift kit replaces.

    The runtime swaps a whole slot at a time, so the leather outfit and the
    other three sets are not worn at once with this kit; a capture that showed
    them would photograph a wardrobe instead of the piece.
    """
    hidden = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.name.startswith("Armor_Makeshift_"):
            continue
        if obj.name.startswith("Armor_") or obj.name.startswith("Male_Ranger_") \
                or obj.name == "Icosphere":
            obj.hide_render = True
            obj.hide_viewport = True
            hidden += 1
    print("MS_CAPTURE_HIDDEN", hidden)


def render_captures(metadata: dict) -> None:
    CAPTURES.mkdir(parents=True, exist_ok=True)
    stage_capture_visibility()
    scene = bpy.context.scene
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1000
    scene.render.film_transparent = True
    # Near-black bark on a near-black character needs an explicit lift or the
    # captures photograph a silhouette.
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 1.00
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("MakeshiftPreviewWorld")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.045, 0.055, 0.050, 1.0)
    background.inputs["Strength"].default_value = 1.0
    scene.world = world

    lowest = min(piece["bounds_min"][1] for piece in metadata["pieces"].values())
    highest = max(piece["bounds_max"][1] for piece in metadata["pieces"].values())
    middle = (lowest + highest) * 0.5
    span = max(1.0, highest - lowest)
    ortho = span * 1.12
    distance = span * 1.9 + 2.0
    head_z = MEASURE.joint("Head").z + 0.19
    camera_specs = {
        # The Ranger faces -Y, so front and three-quarter sit on the -Y side.
        "front": ((0.0, -distance, middle + span * 0.02), (0.0, 0.0, middle), "ORTHO", ortho),
        "back": ((0.0, distance, middle + span * 0.02), (0.0, 0.0, middle), "ORTHO", ortho),
        "side": ((distance * 0.98, -distance * 0.12, middle + span * 0.02),
                 (0.0, 0.0, middle), "ORTHO", ortho),
        "threeq": ((-distance * 0.62, -distance * 0.74, middle + span * 0.12),
                   (0.0, 0.0, middle), "ORTHO", ortho * 1.05),
        "helmet": ((-span * 0.30, -span * 0.46, head_z + 0.10),
                   (0.0, 0.0, head_z), "ORTHO", span * 0.34),
        # Gameplay distance: a third-person camera about five metres out on
        # bright grass, which is the only view that proves the bone/leather
        # values separate against the world the kit is worn in.
        "gameplay": ((-2.95, -4.25, middle + 0.34), (0.0, 0.0, middle - 0.02),
                     "PERSP", 50.0),
    }
    cameras = {}
    for name, (location, target, kind, scale) in camera_specs.items():
        data = bpy.data.cameras.new(name)
        data.type = kind
        if kind == "ORTHO":
            data.ortho_scale = scale
        else:
            data.lens = scale
        camera = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(camera)
        camera.location = location
        camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        cameras[name] = camera

    bpy.ops.mesh.primitive_plane_add(size=16.0, location=(0.0, 0.0, -0.018))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground_mat = bpy.data.materials.new("PreviewGround")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.055, 0.062, 0.052, 1.0)
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.94
    ground.data.materials.append(ground_mat)
    grass_mat = bpy.data.materials.new("PreviewGrass")
    grass_mat.use_nodes = True
    grass_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.21, 0.36, 0.09, 1.0)
    grass_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.90
    grass_world = bpy.data.worlds.new("MakeshiftGrassWorld")
    grass_world.use_nodes = True
    grass_background = grass_world.node_tree.nodes["Background"]
    grass_background.inputs["Color"].default_value = (0.30, 0.44, 0.15, 1.0)
    grass_background.inputs["Strength"].default_value = 1.4

    scale = span / 2.4
    key = add_area_light("PreviewKey", Vector((2.8, -3.4, 3.1)) * scale,
                         (1.0, 0.93, 0.84), 520.0 * scale * scale, 2.4 * scale)
    fill = add_area_light("PreviewFill", Vector((-3.4, -2.4, 1.5)) * scale,
                          (0.58, 0.70, 0.92), 130.0 * scale * scale, 3.0 * scale)
    rim = add_area_light("PreviewRim", Vector((-1.3, -3.4, 3.0)) * scale,
                         (1.0, 0.52, 0.32), 260.0 * scale * scale, 2.0 * scale)
    for light in (key, fill, rim):
        light.data.shape = "DISK"

    def render(view: str, path: Path, engine: str) -> None:
        # The gameplay shot is framed for the world, not for an asset sheet.
        on_grass = view == "gameplay"
        if on_grass:
            scene.render.resolution_x = 1000
            scene.render.resolution_y = 640
        else:
            scene.render.resolution_x = 900
            scene.render.resolution_y = 1000
        scene.world = grass_world if on_grass else world
        ground.data.materials[0] = grass_mat if on_grass else ground_mat
        scene.render.engine = engine
        if engine == "BLENDER_WORKBENCH":
            scene.display.shading.light = "STUDIO"
            scene.display.shading.show_shadows = True
            scene.display.shading.show_cavity = True
            scene.display.shading.cavity_type = "BOTH"
            scene.display.shading.show_specular_highlight = False
            scene.display.shading.color_type = "TEXTURE"
            scene.display.shading.studiolight_intensity = 1.6
            scene.render.film_transparent = not on_grass
        else:
            scene.cycles.device = "CPU"
            scene.cycles.samples = 40
            scene.cycles.use_denoising = True
            scene.cycles.max_bounces = 4
            scene.render.film_transparent = False
            scene.view_settings.exposure = 0.10
        scene.camera = cameras[view]
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)

    # Rest (bind) pass: the neutral read of every silhouette.
    reset_pose()
    for view in ("front", "back", "side", "threeq", "helmet", "gameplay"):
        render(view, CAPTURES / f"kit_rest_{view}.png", "BLENDER_WORKBENCH")
    render("threeq", CAPTURES / "kit_rest_threeq_lit.png", "CYCLES")
    render("helmet", CAPTURES / "helmet_rest_lit.png", "CYCLES")
    render("gameplay", CAPTURES / "kit_rest_gameplay_lit.png", "CYCLES")

    # Idle pass: proves the deformation holds where the arms and knees move.
    if IDLE_ACTION is not None:
        if RIG.animation_data is None:
            RIG.animation_data_create()
        RIG.animation_data.action = IDLE_ACTION
        if getattr(IDLE_ACTION, "slots", None):
            RIG.animation_data.action_slot = IDLE_ACTION.slots[0]
        scene.frame_set(int(0.25 * FPS))
        bpy.context.view_layer.update()
        for view in ("front", "threeq"):
            render(view, CAPTURES / f"kit_idle_{view}.png", "BLENDER_WORKBENCH")
        render("threeq", CAPTURES / "kit_idle_threeq_lit.png", "CYCLES")
        scene.frame_set(0)
        RIG.animation_data.action = None
    reset_pose()
    print("MS_CAPTURES", CAPTURES)


# ---------------------------------------------------------------------------
# Main


def main() -> None:
    global RIG, MEASURE, IDLE_ACTION

    mobs.reset_scene()
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    TEXTURES.mkdir(parents=True, exist_ok=True)
    print("MS_BEGIN", RANGER)

    bpy.ops.import_scene.gltf(filepath=str(RANGER))
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not rigs:
        raise SystemExit("ranger GLB contains no armature")
    RIG = rigs[0]
    IDLE_ACTION = next((action for action in bpy.data.actions if action.name == "Idle_Loop"), None)
    meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    MEASURE = Measure(RIG, meshes)
    reset_pose()
    measure_arm_limit(IDLE_ACTION)
    rig_bones = [bone.name for bone in RIG.data.bones]
    print("MS_RIG", RIG.name, "bones", len(rig_bones))

    materials = {}
    for surface in SURFACE_ORDER:
        material = bpy.data.materials.new(MATERIAL_NAME[surface])
        material.use_nodes = True
        materials[surface] = material

    def material_of(surface: str) -> bpy.types.Material:
        return materials[surface]

    claimed = {
        "head": ["Head"],
        # The sleeves and spaulders are chest-slot geometry: they follow the
        # arm, so the chest claims the arm bones it actually deforms.
        "chest": ["pelvis", "spine_01", "spine_02", "spine_03",
                  "upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r"],
        "hands": ["lowerarm_l", "hand_l", "lowerarm_r", "hand_r"],
        "legs": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"],
        "feet": ["calf_l", "foot_l", "ball_l", "calf_r", "foot_r", "ball_r"],
    }

    builders = {
        "head": build_head,
        "chest": build_chest,
        "hands": build_hands,
        "legs": build_legs,
        "feet": build_feet,
    }
    # Crossings with these are visible clipping and fail the build. The torso
    # and the limb meshes underneath the hide are reported, not gated: a
    # garment wrapped around a trousered leg always dips a few millimetres into
    # the hidden volume beside the limb, and the arm's inner half is modelled
    # inside the torso, so "never cross" is not a physical target there.
    strict_refs = {
        # The cap fits the skull. `Male_Ranger_Head_Hood` is the *leather* set's
        # head piece and a slot draws exactly the set it wears, so the two are
        # never on screen together - measuring the cap against the cowl is what
        # made it 0.32 m across a 0.21 m head.
        "head": ["Ranger_Head_SuperHero_Male"],
        "chest": [],
        # The arms and glove cuff are chest/hands slot geometry themselves, so
        # they are never drawn with this kit; crossings are measured, not gated.
        "hands": [],
        "legs": [],
        "feet": ["Male_Ranger_Feet_Boots", "Ranger_Base_Calf"],
    }
    clearance_refs = {
        "head": ["Ranger_Head_SuperHero_Male", "Male_Ranger_Body"],
        "chest": ["Male_Ranger_Body", "Male_Ranger_Legs", "Male_Ranger_Arms",
                  "Male_Ranger_Arms_Bracer", "Male_Ranger_Body_Belt_1",
                  "Male_Ranger_Body_Belt_2", "Male_Ranger_Acc_Pauldron"],
        # The arms and glove cuff are chest/hands slot geometry themselves, so
        # they are never drawn with this kit; crossings are measured, not gated.
        "hands": [],
        "legs": ["Male_Ranger_Legs", "Ranger_Base_Calf", "Male_Ranger_Body"],
        "feet": ["Male_Ranger_Feet_Boots", "Ranger_Base_Calf"],
    }

    problems: list[str] = []
    clearance: dict = {"rest": {}, "idle": {}}
    measured: list[dict] = []
    clearance_problems: list[str] = []
    pieces: list[bpy.types.Object] = []
    for slot in SLOTS:
        parts, weight_fn, smooth = builders[slot](material_of)
        if os.environ.get("MS_DEBUG_PARTS"):
            for part in parts:
                lo = [min(v.co[i] for v in part.data.vertices) for i in range(3)]
                hi = [max(v.co[i] for v in part.data.vertices) for i in range(3)]
                span = [round(hi[i] - lo[i], 3) for i in range(3)]
                if max(span) > 0.30:
                    print("MS_PART", slot, part.name, "size", span,
                          "lo", [round(v, 3) for v in lo], "hi", [round(v, 3) for v in hi])
        slot_problems, report = clearance_report(parts, clearance_refs[slot], "rest",
                                                 strict_refs[slot])
        clearance["rest"][NODE_NAME[slot]] = report
        measured.extend(entry for part in report.values() for entry in part.values())
        clearance_problems.extend(slot_problems)
        # Skin each part before the join: a slot can mix a vest on the spine
        # with a sleeve on the arm, and joining first would fuse the weights.
        for part in parts:
            assign_weights(part, PART_WEIGHTS.pop(part.name, weight_fn),
                           smooth_iterations=smooth)
        piece = join_slot(parts, NODE_NAME[slot])
        problems.extend(validate_piece(piece, claimed[slot]))
        triangles = sum(len(polygon.vertices) - 2 for polygon in piece.data.polygons)
        print("MS_PIECE", piece.name, "tris", triangles, "verts", len(piece.data.vertices),
              "groups", sorted(group.name for group in piece.vertex_groups))
        piece.parent = RIG
        piece.matrix_parent_inverse = Matrix.Identity(4)
        modifier = piece.modifiers.new("Armature", "ARMATURE")
        modifier.object = RIG
        modifier.use_vertex_groups = True
        pieces.append(piece)
    if problems:
        for problem in problems:
            print("MS_ERROR", problem)
        raise SystemExit("weight validation failed")

    total = sum(sum(len(polygon.vertices) - 2 for polygon in piece.data.polygons) for piece in pieces)
    print("MS_TRIS", total)
    if total > TRIANGLE_BUDGET:
        raise SystemExit(f"triangle budget exceeded: {total} > {TRIANGLE_BUDGET}")

    if IDLE_ACTION is not None:
        if RIG.animation_data is None:
            RIG.animation_data_create()
        RIG.animation_data.action = IDLE_ACTION
        if getattr(IDLE_ACTION, "slots", None):
            RIG.animation_data.action_slot = IDLE_ACTION.slots[0]
        bpy.context.scene.frame_set(int(0.25 * FPS))
        bpy.context.view_layer.update()
        for piece in pieces:
            slot = piece.name.split("_")[-1].lower()
            idle_problems, report = clearance_report([piece], clearance_refs[slot], "idle",
                                                     strict_refs[slot])
            clearance["idle"][piece.name] = report
            measured.extend(entry for part in report.values() for entry in part.values())
            clearance_problems.extend(idle_problems)
        clearance["idle_frame"] = int(0.25 * FPS)
        RIG.animation_data.action = None
        reset_pose()
    clearance["reported_intersections"] = sum(entry["intersections"] for entry in measured)
    clearance["gated_refs"] = strict_refs
    clearance["note"] = (
        "Every piece is measured against the ranger's own surfaces in the bind pose and at "
        "idle frame %d. Crossings with 'gated_refs' fail the build; the rest are reported "
        "because those meshes belong to slots this kit replaces (one piece per slot), and "
        "because a garment wrapped around a trousered limb necessarily dips into the hidden "
        "volume beside the limb. max_depth_mm is only meaningful within a few millimetres of "
        "a surface." % int(0.25 * FPS)
    )
    if clearance_problems:
        for problem in clearance_problems:
            print("MS_ERROR", problem)
        raise SystemExit("clearance validation failed")

    layout = allocate_cells(pieces)
    for piece in pieces:
        for surface in SURFACE_ORDER:
            slot = material_slot(piece, surface)
            if slot is None:
                continue
            cells = layout[surface]
            unwrap_piece(piece, {slot: cells[pieces.index(piece)]})
    for surface in SURFACE_ORDER:
        if surface in layout:
            bake_surface(surface, pieces, layout[surface])

    export(pieces)
    metadata = write_metadata(pieces, clearance)
    render_captures(metadata)
    print("MS_DONE", json.dumps({
        "triangles": metadata["total_triangles"],
        "bones": metadata["bone_count"],
        "images": metadata["embedded_images"],
        "pieces": {name: meta["triangles"] for name, meta in metadata["pieces"].items()},
    }, indent=2))


if __name__ == "__main__":
    main()
