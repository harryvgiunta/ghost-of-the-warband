"""Author the warband's individual faces, hair and tintable colour surfaces.

The warband fields up to eight bodies on one skeleton, so until now the only thing
that told two mercenaries apart was the gear in their hands.  This tool makes the
band a band:

    assets/characters/warband/ironwood_faces.glb      8 faces (head, brows, eyes)
    assets/characters/warband/ironwood_hair.glb       8 cuts + 3 beards
    assets/characters/warband/warband_skin_basecolor.png
    assets/characters/warband/warband_shirt_basecolor.png
    assets/characters/warband/warband_shorts_basecolor.png
    assets/characters/warband/warband_hair_basecolor.png
    assets/characters/warband/warband_beard_<style>.png   (RGBA: the beard's own mask)
    assets/characters/warband/warband_beard_<style>.png
    assets/characters/warband/warband_eye_<n>_basecolor.png
    assets/characters/warband/ironwood_warband_looks.json

Nothing here downloads a source or launches Blender: every variant is derived
from geometry and textures the repository already ships, so the numbers are
reproducible and the licence is the one already recorded for the Ranger (CC0
Quaternius Universal Base Characters -- see ``assets/characters/LICENSE.txt``).

Faces
-----
The Ranger's head, brows and eyes are read straight out of
``ironwood_ranger.glb`` in bind space.  A face variant is an analytic warp of
that surface -- jaw width, chin length and width, cheekbones, nose projection and
width, brow ridge, eye spacing, mouth width and lip volume -- windowed to the
*front* of the face, so the braincase, and therefore every helmet and hood the
armour sets draw, stays exactly where the artist put it.  Brows follow the same
field so they keep hugging the brow, and each eyeball is translated rigidly
rather than squashed.  Variants keep the authored UVs, joint indices and skin
weights, so any of them binds to the live rig by repointing its skin.

Hair and beards
---------------
A short cut is a **thin shell of the skull's own triangles**, a few millimetres
thick: a buzz cut is the man's head with colour on it, and a smooth proxy bulges
where a forehead recedes, which made every cut look like the same cap. The
**afro** - one body, one cut - is the one lofted mass: rings from a crown disc
down to its own measured hairline, measured off the masked skull, swelling to a
cloud and settling flush onto the skin at the edge. Sealed matters: an open shell of the head's triangles leaves a rim that
gapes at the temples and, drawn double-sided, shades itself into a black band;
loose locks - tried first as tubes and then as cards - read as spikes stuck to a
skull. The afro is this same construction with the volume of a cloud.

A beard is a sheet laid over the jaw and cut out by its own **alpha design**, not
by a shell of the head's triangles: at 2,864 triangles a triangle edge is a saw
tooth, so the silhouette comes from a texture. The design draws what a beard is -
a cheek line that leaves the cheek clear, an arched moustache over the upper lip,
an open mouth, and a bottom edge on the jawline so the throat stays shaved. Both
bind rigidly to ``Head``, because hair rides a skull - it does not deform with a
jaw.

Surfaces
--------
Skin, shirt and shorts ship as *veiled* maps: the authored detail divided by the
base colour that carries it, so a body's tone is one ``albedo_color`` multiply
and eight bodies share one texture.  Palette entry 0 of each material is the
measured base, so an untinted mercenary still looks exactly as it shipped; the
rest of the palette is the variation.  Normals stay the artist's.

Usage:
    python tools/prepare_warband_looks.py
"""

from __future__ import annotations

import io
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from glb_animation_merge import read_glb, write_glb  # noqa: E402

ROOT = TOOLS.parent
RANGER = ROOT / "assets" / "characters" / "ironwood_ranger.glb"
ARMOUR = ROOT / "assets" / "characters" / "armor"
OUT = ROOT / "assets" / "characters" / "warband"
FACES_GLB = OUT / "ironwood_faces.glb"
HAIR_GLB = OUT / "ironwood_hair.glb"
META = OUT / "ironwood_warband_looks.json"

SKIN_ATLAS = ARMOUR / "ironwood_naked_T_Superhero_Male_Dark.png"
SHIRT_ATLAS = ARMOUR / "ironwood_naked_Naked_Shirt_albedo.png"
SHORTS_ATLAS = ARMOUR / "ironwood_naked_Naked_Shorts_albedo.png"

LUMA = np.array([0.2126, 0.7152, 0.0722])


# --- small maths ------------------------------------------------------------


def smoothstep(edge0: float, edge1: float, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def window(x, low: float, high: float, soft: float = 0.06):
    """One inside ``low..high`` and easing to zero over ``soft`` on both sides."""
    return smoothstep(low - soft, low + soft, x) * (1.0 - smoothstep(high - soft, high + soft, x))


def png_bytes(pixels: np.ndarray) -> bytes:
    buffer = io.BytesIO()
    Image.fromarray(np.clip(np.round(pixels * 255.0), 0, 255).astype(np.uint8),
                    "RGBA" if pixels.shape[2] == 4 else "RGB").save(buffer, format="PNG")
    return buffer.getvalue()


def srgb_to_linear(a: np.ndarray) -> np.ndarray:
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(a: np.ndarray) -> np.ndarray:
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1.0 / 2.4) - 0.055)


def hex_of(linear_rgb: np.ndarray) -> str:
    srgb = np.clip(linear_to_srgb(np.asarray(linear_rgb, dtype=np.float64)), 0.0, 1.0)
    return "#" + "".join("%02x" % int(round(value * 255.0)) for value in srgb)


def save_png(path: Path, pixels: np.ndarray) -> None:
    """Write an RGB or RGBA array, whichever the caller built."""
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(np.round(pixels * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(data, "RGBA" if pixels.shape[2] == 4 else "RGB").save(path)


# --- glTF io ----------------------------------------------------------------


COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16,
             5125: np.uint32, 5126: np.float32}
COMPONENT_GLTF = {np.dtype(np.int8): 5120, np.dtype(np.uint8): 5121, np.dtype(np.int16): 5122,
                  np.dtype(np.uint16): 5123, np.dtype(np.uint32): 5125,
                  np.dtype(np.float32): 5126}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(doc: dict, blob: bytearray, index: int) -> np.ndarray:
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    dtype = np.dtype(COMPONENT[accessor["componentType"]])
    count = accessor["count"]
    width = WIDTH[accessor["type"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride")
    span = width * dtype.itemsize
    if stride and stride != span:
        raw = np.frombuffer(bytes(blob), dtype=np.uint8, count=(count - 1) * stride + span,
                            offset=start)
        raw = raw.reshape(count, stride)[:, :span]
        data = np.ascontiguousarray(raw).view(dtype).reshape(count, width)
    else:
        data = np.frombuffer(bytes(blob), dtype=dtype, count=count * width,
                             offset=start).reshape(count, width)
    if accessor.get("normalized") and dtype != np.float32:
        data = data.astype(np.float64) / np.iinfo(dtype).max
    return np.ascontiguousarray(data)


def accessor_data(doc: dict, blob: bytearray, index: int) -> np.ndarray:
    data = read_accessor(doc, blob, index)
    return data.reshape(-1) if data.shape[1] == 1 else data


class Blob:
    """A fresh binary chunk that new accessors and images are appended to."""

    def __init__(self) -> None:
        self.data = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def _pad(self, align: int = 4) -> None:
        while len(self.data) % align:
            self.data.append(0)

    def add_view(self, payload: bytes, target: int | None = None) -> int:
        self._pad()
        view = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(payload)}
        if target is not None:
            view["target"] = target
        self.data.extend(payload)
        self.views.append(view)
        return len(self.views) - 1

    def add(self, array: np.ndarray, kind: str, component: int | None = None,
            target: int | None = 34962, bounds: bool = False) -> int:
        array = np.ascontiguousarray(array)
        dtype = np.dtype(COMPONENT[component]) if component is not None else np.dtype(array.dtype)
        if dtype == np.dtype(np.float64):
            dtype = np.dtype(np.float32)
        view = self.add_view(array.astype(dtype, copy=False).tobytes(), target)
        accessor = {"bufferView": view, "componentType": COMPONENT_GLTF[dtype],
                    "count": int(array.shape[0]), "type": kind}
        if bounds:
            accessor["min"] = np.min(array, axis=0).astype(np.float64).tolist()
            accessor["max"] = np.max(array, axis=0).astype(np.float64).tolist()
        self.accessors.append(accessor)
        return len(self.accessors) - 1


# --- the Ranger's head ------------------------------------------------------


class Head:
    """The authoring source: the shipped head, brows and eyes in bind space."""

    PARTS = (("head", "Ranger_Head_SuperHero_Male"),
             ("brows", "Ranger_Head_Eyebrows"),
             ("eyes", "Ranger_Head_Eyes"))

    def __init__(self) -> None:
        doc, blob = read_glb(RANGER)
        self.doc = doc
        self.blob = blob
        by_name = {node.get("name"): index for index, node in enumerate(doc["nodes"])}
        self.part = {}
        for key, node_name in self.PARTS:
            primitive = doc["meshes"][doc["nodes"][by_name[node_name]]["mesh"]]["primitives"][0]
            attributes = primitive["attributes"]
            self.part[key] = {
                "position": accessor_data(doc, blob, attributes["POSITION"]).astype(np.float64),
                "normal": accessor_data(doc, blob, attributes["NORMAL"]).astype(np.float64),
                "uv": accessor_data(doc, blob, attributes["TEXCOORD_0"]).astype(np.float64),
                "joints": accessor_data(doc, blob, attributes["JOINTS_0"]).astype(np.uint16),
                "weights": accessor_data(doc, blob, attributes["WEIGHTS_0"]).astype(np.float64),
                "indices": accessor_data(doc, blob, primitive["indices"]).astype(np.int64),
            }
        self.skin = doc["skins"][0]
        self.ibm = read_accessor(doc, blob, self.skin["inverseBindMatrices"]).reshape(-1, 16)
        head = self.part["head"]["position"]
        eyes = self.part["eyes"]["position"]
        self.top = float(head[:, 1].max())
        self.neck = float(head[:, 1].min())
        self.half_width = float(np.abs(head[:, 0]).max())
        self.nose = head[int(np.argmax(head[:, 2]))]
        front = head[head[:, 2] > 0.06]
        self.chin = front[int(np.argmin(front[:, 1]))]
        self.eye_centre = (eyes.min(axis=0) + eyes.max(axis=0)) * 0.5
        self.back = float(head[:, 2].min())
        self.chin_y = float(self.chin[1])
        self.face_height = self.top - self.chin_y
        self.mouth = np.array([0.0,
                               self.chin_y + 0.30 * (float(self.eye_centre[1]) - self.chin_y),
                               float(self.nose[2]) - 0.012])
        self.head_joint = self.joint_of("Head")

    def joint_of(self, bone: str) -> int:
        node = [index for index, item in enumerate(self.doc["nodes"])
                if item.get("name") == bone][0]
        return int(self.skin["joints"].index(node))

    def image_bytes(self, name: str) -> bytes:
        for image in self.doc["images"]:
            if image.get("name") == name:
                view = self.doc["bufferViews"][image["bufferView"]]
                start = view.get("byteOffset", 0)
                return bytes(self.blob[start:start + view["byteLength"]])
        raise KeyError(name)


# --- face variants ----------------------------------------------------------


FACE_VARIANTS = [
    # jaw, chin, chin_w, cheek, nose_proj, nose_w, brow, eye_gap, mouth, lip
    {"name": "Sharp", "jaw": -0.055, "chin": 0.011, "chin_w": -0.030, "cheek": 0.0035,
     "nose_proj": 0.006, "nose_w": -0.10, "brow": 0.0015, "eye_gap": 0.0000,
     "mouth": -0.05, "lip": 0.0000},
    {"name": "Broad", "jaw": 0.075, "chin": 0.000, "chin_w": 0.055, "cheek": 0.0055,
     "nose_proj": -0.002, "nose_w": 0.16, "brow": 0.0045, "eye_gap": 0.0010,
     "mouth": 0.06, "lip": 0.0012},
    {"name": "Long", "jaw": -0.020, "chin": 0.016, "chin_w": -0.010, "cheek": -0.0030,
     "nose_proj": 0.003, "nose_w": -0.02, "brow": 0.0005, "eye_gap": -0.0012,
     "mouth": -0.02, "lip": 0.0000},
    {"name": "Round", "jaw": 0.040, "chin": -0.008, "chin_w": 0.060, "cheek": 0.0080,
     "nose_proj": -0.004, "nose_w": 0.08, "brow": -0.0020, "eye_gap": 0.0008,
     "mouth": 0.000, "lip": 0.0018},
    {"name": "Heavy", "jaw": 0.025, "chin": 0.004, "chin_w": 0.015, "cheek": 0.0020,
     "nose_proj": 0.008, "nose_w": 0.02, "brow": 0.0070, "eye_gap": 0.0020,
     "mouth": 0.02, "lip": 0.0020},
    {"name": "Wide", "jaw": 0.020, "chin": -0.004, "chin_w": 0.010, "cheek": 0.0110,
     "nose_proj": -0.001, "nose_w": 0.04, "brow": 0.0010, "eye_gap": 0.0015,
     "mouth": 0.03, "lip": 0.0005},
    {"name": "Fine", "jaw": -0.030, "chin": 0.006, "chin_w": -0.020, "cheek": 0.0010,
     "nose_proj": -0.006, "nose_w": -0.12, "brow": -0.0030, "eye_gap": -0.0018,
     "mouth": -0.06, "lip": -0.0015},
    {"name": "Hooked", "jaw": -0.035, "chin": 0.008, "chin_w": -0.010, "cheek": 0.0040,
     "nose_proj": 0.011, "nose_w": -0.06, "brow": 0.0030, "eye_gap": 0.0005,
     "mouth": -0.01, "lip": 0.0025},
]


def face_warp(points: np.ndarray, head: Head, prm: dict) -> np.ndarray:
    """Displace face vertices by one variant, confined to the front of the face."""
    x = points[:, 0].copy()
    y = points[:, 1].copy()
    z = points[:, 2].copy()
    u = x / head.half_width
    t = (y - head.chin_y) / head.face_height
    front = smoothstep(-0.020, 0.020, z) * window(t, -0.05, 0.92, 0.08)

    jaw = window(t, 0.02, 0.32, 0.09) * front
    x = x * (1.0 + prm["jaw"] * jaw * (0.30 + 0.85 * np.abs(u)))

    chin = window(t, -0.02, 0.15, 0.055) * smoothstep(-0.030, 0.020, z)
    y = y - prm["chin"] * chin
    x = x * (1.0 + prm["chin_w"] * chin)

    cheek = window(t, 0.34, 0.52, 0.07) * window(np.abs(u), 0.22, 0.88, 0.10) * front
    x = x + np.sign(x) * prm["cheek"] * cheek

    nose = np.exp(-(u / 0.19) ** 2) * window(t, 0.26, 0.47, 0.05) * smoothstep(0.0, 0.03, z)
    z = z + prm["nose_proj"] * nose
    x = x * (1.0 + prm["nose_w"] * nose)

    brow = window(t, 0.54, 0.70, 0.055) * front \
        * (0.35 + 0.65 * window(np.abs(u), 0.0, 0.75, 0.10))
    y = y + prm["brow"] * brow
    z = z + 0.55 * prm["brow"] * brow

    eye = np.exp(-((t - 0.615) / 0.075) ** 2) * front * window(np.abs(u), 0.0, 0.80, 0.10)
    x = x + np.sign(x) * prm["eye_gap"] * eye

    mouth = window(t, 0.13, 0.24, 0.045) * np.exp(-(u / 0.35) ** 2) * smoothstep(0.0, 0.03, z)
    x = x * (1.0 + prm["mouth"] * mouth)
    z = z + prm["lip"] * mouth

    return np.stack([x, y, z], axis=1)


def rigid_eye_offset(points: np.ndarray, head: Head, prm: dict) -> np.ndarray:
    """Translate each eyeball by the warped position of its own centre."""
    out = points.copy()
    for side in (-1.0, 1.0):
        mask = np.sign(points[:, 0]) == side
        if not np.any(mask):
            continue
        centre = points[mask].mean(axis=0)
        out[mask] += face_warp(centre[None, :], head, prm)[0] - centre
    return out


# --- growing meshes ---------------------------------------------------------


class Builder:
    """Positions, normals, uvs and triangles; every face is fan-triangulated."""

    def __init__(self) -> None:
        self.pos: list[np.ndarray] = []
        self.nrm: list[np.ndarray] = []
        self.uv: list[np.ndarray] = []
        self.tri: list[np.ndarray] = []
        self.count = 0

    def add(self, pos: np.ndarray, nrm: np.ndarray, uv: np.ndarray) -> int:
        base = self.count
        self.pos.append(np.asarray(pos, dtype=np.float64))
        self.nrm.append(np.asarray(nrm, dtype=np.float64))
        self.uv.append(np.asarray(uv, dtype=np.float64))
        self.count += len(pos)
        return base

    def face(self, indices) -> None:
        indices = np.asarray(indices, dtype=np.int64)
        for corner in range(1, len(indices) - 1):
            self.tri.append(np.array([indices[0], indices[corner], indices[corner + 1]]))

    def arrays(self):
        return (np.concatenate(self.pos), np.concatenate(self.nrm),
                np.concatenate(self.uv), np.concatenate(self.tri))

    def triangles(self) -> int:
        return int(sum(len(tri) for tri in self.tri))


def boundary_edges(tris: np.ndarray) -> np.ndarray:
    """The directed edges of a triangle set that appear exactly once."""
    directed = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    unique, inverse, counts = np.unique(np.sort(directed, axis=1), axis=0,
                                        return_inverse=True, return_counts=True)
    del unique
    return directed[counts[inverse] == 1]


def tube(path: np.ndarray, radii: np.ndarray, sides: int = 6, uv_scale: float = 5.0,
         flatten: np.ndarray | None = None) -> Builder:
    """A capped tube swept along ``path`` with one radius per ring."""
    builder = Builder()
    rings = []
    for index in range(len(path)):
        if index == 0:
            tangent = path[1] - path[0]
        elif index == len(path) - 1:
            tangent = path[-1] - path[-2]
        else:
            tangent = path[index + 1] - path[index - 1]
        tangent = tangent / max(float(np.linalg.norm(tangent)), 1e-9)
        helper = np.array([1.0, 0.0, 0.0]) if abs(tangent[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
        side = np.cross(tangent, helper)
        side /= max(float(np.linalg.norm(side)), 1e-9)
        up = np.cross(side, tangent)
        up /= max(float(np.linalg.norm(up)), 1e-9)
        ring = []
        for step in range(sides):
            angle = math.tau * step / sides
            direction = np.cos(angle) * side + np.sin(angle) * up
            if flatten is not None:
                direction = direction * flatten
            ring.append(path[index] + direction * radii[index])
        ring = np.array(ring)
        normal = ring - path[index]
        normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-9)
        uv = np.array([[step / sides, index / max(len(path) - 1, 1) * uv_scale]
                       for step in range(sides)])
        rings.append(builder.add(ring, normal, uv))
    for index in range(len(path) - 1):
        for step in range(sides):
            nxt = (step + 1) % sides
            builder.face([rings[index] + step, rings[index] + nxt,
                          rings[index + 1] + nxt, rings[index + 1] + step])
    builder.face([rings[0] + step for step in range(sides)][::-1])
    builder.face([rings[-1] + step for step in range(sides)])
    return builder


def lump(centre: np.ndarray, radius: float, sides: int = 14, rings: int = 8,
         squash: float = 1.0) -> Builder:
    """A lumpy ellipsoid: buns, topknots and braid ends."""
    builder = Builder()
    rows = []
    for ring in range(rings + 1):
        phi = math.pi * ring / rings
        points = []
        for step in range(sides):
            theta = math.tau * step / sides
            direction = np.array([math.sin(phi) * math.cos(theta),
                                  math.cos(phi) * squash,
                                  math.sin(phi) * math.sin(theta)])
            wobble = 0.88 + 0.12 * math.sin(theta * 3.0 + ring * 1.7) * math.cos(phi * 2.0)
            points.append(centre + direction * radius * wobble)
        points = np.array(points)
        normal = points - centre
        normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-9)
        uv = np.array([[step / sides, ring / rings] for step in range(sides)])
        rows.append(builder.add(points, normal, uv))
    for ring in range(rings):
        for step in range(sides):
            nxt = (step + 1) % sides
            builder.face([rows[ring] + step, rows[ring] + nxt,
                          rows[ring + 1] + nxt, rows[ring + 1] + step])
    return builder


def merge(parts: list[Builder]) -> Builder:
    out = Builder()
    for part in parts:
        pos, nrm, uv, tri = part.arrays()
        base = out.add(pos, nrm, uv)
        out.tri.append(tri + base)
    return out


def shell(position: np.ndarray, normal: np.ndarray, tris: np.ndarray, mask,
          thickness, uv_scale=(1.0, 9.0), rim: bool = True,
          centroid: bool = False, uv_fn=None, fringe: float = 0.0) -> Builder:
    """A closed offset shell over the masked triangles, with a rim wall."""
    if centroid:
        keep = mask(position[tris].mean(axis=1))
    else:
        keep = mask(position)[tris].all(axis=1)
    chosen = tris[keep]
    if not len(chosen):
        raise RuntimeError("shell mask selected no triangles")
    used, inverse = np.unique(chosen, return_inverse=True)
    inner_tris = inverse.reshape(-1, 3)
    base_pos = position[used]
    base_nrm = normal[used]
    thick = thickness(base_pos) if callable(thickness) else np.full(len(base_pos), float(thickness))
    close = np.minimum(thick * 0.35, 0.0018)
    outer_pos = base_pos + base_nrm * thick[:, None]
    inner_pos = base_pos - base_nrm * close[:, None]

    if uv_fn is not None:
        keep_uv = uv_fn(base_pos)
    elif uv_scale is None:
        keep_uv = None
    else:
        # One wrap around the skull: the strand texture is periodic in u, so a
        # single wrap is seamless, while three wrapped copies put a hard seam at
        # every third of the head and read as chevrons of milled wood.
        angle = np.arctan2(base_pos[:, 0], base_pos[:, 2] - 0.02)
        keep_uv = np.stack([(angle / math.tau + 0.5) % 1.0,
                            (base_pos[:, 1] * uv_scale[1]) % 1.0], axis=1)

    builder = Builder()
    # The inner surface is never seen -- the head is inside it -- so only the
    # rim is built: the outer skin plus the wall that closes it onto the skull.
    inner_base = builder.add(inner_pos, -base_nrm, keep_uv)
    outer_base = builder.add(outer_pos, base_nrm, keep_uv)
    for tri in inner_tris:
        builder.face(outer_base + tri)
    if rim:
        for edge in boundary_edges(inner_tris):
            a, b = int(edge[0]), int(edge[1])
            builder.face([inner_base + b, inner_base + a, outer_base + a, outer_base + b])
    if fringe > 0.0:
        # A ragged edge: one tapered flap per boundary edge, hanging off it. This
        # is what a hairline looks like - tresses of unequal length over the skin -
        # and it is the difference between a head of hair and a cap.
        for edge in boundary_edges(inner_tris):
            a, b = int(edge[0]), int(edge[1])
            mid = 0.5 * (outer_pos[a] + outer_pos[b])
            grain = 0.5 + 0.5 * math.sin(mid[0] * 173.0 + mid[2] * 91.0 + mid[1] * 47.0)
            drop = fringe * (0.30 + 0.90 * grain)
            outward = (base_nrm[a] + base_nrm[b]) * 0.5
            tip = mid + np.array([0.0, -drop, 0.0]) + outward * (fringe * 0.30)
            tip_normal = outward / max(float(np.linalg.norm(outward)), 1e-9)
            tip_uv = (keep_uv[a] + keep_uv[b]) * 0.5 if keep_uv is not None else (0.0, 0.0)
            tip_index = builder.add(tip[None, :], tip_normal[None, :],
                                   np.array([tip_uv], dtype=np.float64))
            builder.face([outer_base + a, outer_base + b, tip_index])
    return builder


# --- styles -----------------------------------------------------------------


## Cuts are *skull-fitted*: a thin cap whose thickness grows over the crown, a
## ragged hairline, and, on the three long ones, a sheer that thickens as it
## falls toward the nape. Nothing is grown on a stalk, because a 2 cm tube bound
## rigidly to a head reads as a rod stuck to a skull, not as hair.
## Eight cuts, one man each, and only one of them is a mass of hair. The short ones
## are *thin* - a few millimetres of shell that hugs the skull, so the silhouette is
## the man's own head and the cut reads as a shaved or cropped head rather than as a
## puff. The order is fixed: index 5 is the afro, because that is the body it has
## always been worn by.
## Eight cuts, one man each, and only one of them is a mass of hair. The thin ones
## are wrapped on the skull itself - a buzz cut has to be the man's own head with
## colour on it - and the order is fixed: index 5 is the afro, the body that has
## always worn it.
HAIR_STYLES = [
    {"name": "Bare", "bare": True},
    {"name": "Buzz", "front": 0.048, "side": -0.026, "back": -0.078, "base": 0.0034,
     "crown": 0.0046, "bump": 0.5},
    {"name": "Crop", "front": 0.058, "side": -0.030, "back": -0.086, "base": 0.0064,
     "crown": 0.0090, "bump": 0.7},
    {"name": "Fringe", "front": 0.028, "side": -0.034, "back": -0.088, "base": 0.0080,
     "crown": 0.0108, "bump": 0.8, "seed": 23},
    {"name": "Widow", "front": 0.078, "side": -0.020, "back": -0.076, "base": 0.0056,
     "crown": 0.0078, "bump": 0.6, "seed": 31},
    # The one afro, on the body that wears it.
    {"name": "Afro", "front": 0.054, "side": -0.030, "back": -0.092, "base": 0.026,
     "crown": 0.040, "bump": 2.4, "mass": True, "seed": 53},
    # A mop: unkempt, thicker than a crop and low all the way round.
    {"name": "Mop", "front": 0.034, "side": -0.040, "back": -0.100, "base": 0.0125,
     "crown": 0.0165, "bump": 1.4, "seed": 47},
    # A bob: the hairline drops to the nape and the hair gathers there.
    {"name": "Bob", "front": 0.050, "side": -0.048, "back": -0.140, "base": 0.0135,
     "crown": 0.0185, "fall": 0.016, "bump": 1.2, "seed": 71},
]

## Beards are cut out of a sheet laid over the jaw, not grown as a shell of the
## head's own triangles: a triangle edge at this mesh's density is a saw tooth, so
## the silhouette has to come from a mask the texture can round off.
## Beards are *shaped*, the way a barber shapes one: a cheek line that keeps the
## cheek clear, a moustache over the upper lip, an open mouth, and a clean line
## under the jaw - never hair round the throat. `shape` names the design the mask
## draws; `stubble` cuts the same shape into a broken, thinning edge.
BEARD_STYLES = [
    {"name": "None"},
    {"name": "Moustache", "shape": "moustache", "thickness": 0.0045},
    {"name": "Stubble", "shape": "full", "thickness": 0.0028, "stubble": True},
    {"name": "Chinstrap", "shape": "chinstrap", "thickness": 0.0050},
    {"name": "Full", "shape": "full", "thickness": 0.0065},
]

## Eight entries per palette: the warband deploys at most eight bodies, and the
## rig walks each palette by id, so a full deployment fields eight different skins,
## eight shirts and eight pairs of shorts instead of eight men in one colour.
##
## Index 0 of the three cloth/skin palettes is the *measured base* of the shipped
## texture, written by the tool below, so an untinted mercenary looks exactly as he
## shipped; the other seven are the variation.
TONES = {
    "skin": ["#eec3a2", "#f2d8c6", "#e2bb9c", "#d9ab84", "#c6956c", "#a97446",
             "#8a5c38", "#69452b"],
    "shirt": ["#c7bfae", "#a4552f", "#3f4e6b", "#5c6440", "#b98a3c", "#4a4643",
              "#8c3a34", "#6d8494"],
    "shorts": ["#5e5a55", "#6b543c", "#4f5a3f", "#33394b", "#2c2a28", "#6a3b30",
               "#8a7350", "#423d38"],
    "hair": ["#1b1715", "#3a2617", "#55402a", "#6e3a22", "#a98a58", "#8c4423",
             "#8f8b86", "#cfc3ad"],
}
EYE_TONES = ["#6b4a2a", "#7a6a33", "#4d6b45", "#557084", "#2f2a26"]


def hair_line(head: Head, style: dict, position: np.ndarray) -> np.ndarray:
    """Where this cut's hairline crosses each vertex, as an absolute height."""
    eyes_y = float(head.eye_centre[1])
    front = eyes_y + style["front"]
    side = eyes_y + style["side"]
    back = eyes_y + style["back"]
    facing = np.cos(np.arctan2(position[:, 0], position[:, 2]))
    line = np.where(facing > 0.0,
                    side + (front - side) * smoothstep(0.15, 0.85, facing),
                    side + (back - side) * smoothstep(0.15, 0.9, -facing))
    line = line - 0.010 * (1.0 - np.abs(facing))
    # A real hairline is a ragged line, not a lathe cut: two harmonics around the
    # skull keep the edge from reading as the rim of a skullcap.
    angle = np.arctan2(position[:, 0], position[:, 2])
    return line + 0.0055 * np.sin(angle * 7.0 + 1.3) + 0.0028 * np.sin(angle * 13.0 + 0.7)


def hair_mask(head: Head, style: dict):
    burn = float(style.get("burn", 0.020))

    def mask(position: np.ndarray) -> np.ndarray:
        line = hair_line(head, style, position)
        above = (position[:, 1] > line) & (position[:, 1] < head.top + 0.02)
        # Sideburns: a short drop in front of the ear, which is what stops the cut
        # from reading as a clean circle drawn on the skull.
        burns = (np.abs(position[:, 0]) > 0.056) & (position[:, 2] > 0.0) \
            & (position[:, 1] > line - burn)
        return above | burns

    return mask


def scalp_rim(head: Head, mask) -> tuple[np.ndarray, np.ndarray]:
    tris = head.part["head"]["indices"].reshape(-1, 3)
    keep = mask(head.part["head"]["position"])[tris].all(axis=1)
    chosen = tris[keep]
    if not len(chosen):
        return np.zeros((0, 3)), np.zeros((0, 3))
    used = np.unique(boundary_edges(chosen))
    return head.part["head"]["position"][used], head.part["head"]["normal"][used]


def skull_frame(head: Head) -> tuple[np.ndarray, np.ndarray]:
    """The skull as an ellipsoid, used to loft a hair mass over the head.

    The head mesh is only 2,864 triangles, so a card laid on its own surface
    inherits every facet. The fitted ellipsoid is smooth, and it is what makes the
    cards read as hair rather than as more of the mesh.
    """
    verts = head.part["head"]["position"]
    upper = verts[verts[:, 1] > head.chin_y + 0.004]
    centre = (upper.min(axis=0) + upper.max(axis=0)) * 0.5
    radii = (upper.max(axis=0) - upper.min(axis=0)) * 0.5 * 0.96
    return centre, radii


def skull_point(centre: np.ndarray, radii: np.ndarray, theta: float, azimuth: float,
                offset: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """A point on the fitted skull, its outward direction, and its width tangent."""
    direction = np.array([np.sin(theta) * np.sin(azimuth),
                          np.cos(theta),
                          np.sin(theta) * np.cos(azimuth)])
    point = centre + direction * radii
    outward = direction * radii
    outward /= max(float(np.linalg.norm(outward)), 1e-9)
    tangent = np.array([np.cos(azimuth), 0.0, -np.sin(azimuth)])
    tangent /= max(float(np.linalg.norm(tangent)), 1e-9)
    return point + outward * offset, outward, tangent


def hair_extent(head: Head, style: dict, bins: int = 48) -> np.ndarray:
    """The lowest point of this cut, per azimuth round the head.

    The ellipsoid is a smooth proxy for laying hair on, but it is not the head:
    its forehead is not the head's. So how far a cut reaches is measured on the
    *masked triangles themselves*, then smoothed into a table the loft and the
    cards both read.
    """
    verts = head.part["head"]["position"]
    inside = hair_mask(head, style)(verts)
    azimuth = np.arctan2(verts[inside, 0], verts[inside, 2])
    height = verts[inside, 1]
    index = ((azimuth + math.pi) / math.tau * bins).astype(int) % bins
    table = np.full(bins, float(head.top))
    for slot in range(bins):
        column = height[index == slot]
        if column.size:
            table[slot] = float(column.min())
    for _ in range(2):
        table = 0.5 * table + 0.25 * (np.roll(table, 1) + np.roll(table, -1))
    return table


def extent_at(table: np.ndarray, azimuth: float) -> float:
    bins = len(table)
    position = ((azimuth + math.pi) / math.tau * bins) % bins
    low = int(math.floor(position))
    frac = position - low
    return float(table[low % bins] * (1.0 - frac) + table[(low + 1) % bins] * frac)


def theta_for_height(centre: np.ndarray, radii: np.ndarray, height: float) -> float:
    cosine = np.clip((height - centre[1]) / max(float(radii[1]), 1e-6), -1.0, 1.0)
    return float(np.arccos(cosine))


def build_cap(head: Head, style: dict) -> Builder:
    """A short cut: a thin shell of the skull itself.

    This has to follow the *head*, not the ellipsoid the afro is lofted on. A
    smooth proxy bulges forward where a forehead recedes and rounds off where a
    crown is flat, and at a few millimetres of hair that bulge is the whole
    silhouette - which is what made every short cut read as a helmet. Wrapped on
    the head's own triangles, the cut's outline is the man's own head.
    """
    mask = hair_mask(head, style)
    chin, top = head.chin_y, head.top
    base, crown = float(style["base"]), float(style["crown"])
    fall = float(style.get("fall", 0.0))
    bump = float(style.get("bump", 1.0))
    back_line = float(head.eye_centre[1]) + float(style["back"])

    def thickness(position: np.ndarray) -> np.ndarray:
        line = hair_line(head, style, position)
        edge = smoothstep(line + 0.0015, line + 0.016, position[:, 1])
        share = np.clip((position[:, 1] - chin) / max(top - chin, 1e-6), 0.0, 1.0)
        value = base * (0.35 + 0.65 * edge) + crown * smoothstep(0.35, 1.0, share)
        if fall > 0.0:
            facing = np.cos(np.arctan2(position[:, 0], position[:, 2]))
            backness = np.clip(-facing, 0.0, 1.0)
            drop = 1.0 - smoothstep(back_line, back_line + 0.085, position[:, 1])
            value = value + fall * backness * backness * backness * drop
        clump = bump * (0.0022 * np.sin(position[:, 0] * 26.0 + position[:, 1] * 12.0)
                        + 0.0016 * np.sin(position[:, 2] * 23.0 - position[:, 1] * 15.0))
        return value + edge * clump

    return shell(head.part["head"]["position"], head.part["head"]["normal"],
                 head.part["head"]["indices"].reshape(-1, 3), mask, thickness, rim=False)


def build_mass(head: Head, style: dict) -> Builder:
    """A whole head of hair: one closed cloud lofted above the skull.

    Rings from a crown disc down to the cut's own measured hairline, swelling to
    the cut's volume and settling flush onto the skin at the edge, so the volume is
    sealed and there is no rim to gape.
    """
    centre, radii = skull_frame(head)
    extent = hair_extent(head, style)
    columns = int(style.get("columns", 30))
    rows = int(style.get("rows", 12))
    mass = float(style["base"]) + float(style["crown"]) * 0.5
    bump = float(style.get("bump", 1.0))
    theta_top = 0.10
    rng = np.random.default_rng(int(style.get("seed", 53)))
    lumps = [(rng.random() * math.tau, 2.0 + rng.random() * 3.0, rng.random())
             for _ in range(6)]

    def offset(azimuth: float, theta: float, tuck: float) -> float:
        value = mass * (1.0 - tuck) + 0.0004 * tuck
        for phase, harmonic, weight in lumps:
            value += 0.0026 * bump * weight * math.sin(theta * harmonic
                                                        + azimuth * 2.0 + phase)
        return value

    builder = Builder()
    grid = []
    for row in range(rows + 1):
        v = row / rows
        tuck = smoothstep(0.78, 1.0, v)
        line = []
        for column in range(columns + 1):
            azimuth = -math.pi + math.tau * column / columns
            bottom = extent_at(extent, azimuth)
            theta_cut = max(theta_for_height(centre, radii, bottom), theta_top + 0.08)
            theta = theta_top + (theta_cut - theta_top) * min(v / 0.78, 1.0)
            point, outward, _tangent = skull_point(
                centre, radii, theta, azimuth, offset(azimuth, theta, tuck))
            line.append(builder.add(point[None, :], outward[None, :],
                                    np.array([[column / columns, v]], dtype=np.float64)))
        grid.append(line)
    for row in range(rows):
        for column in range(columns):
            builder.face([grid[row][column + 1], grid[row][column],
                          grid[row + 1][column], grid[row + 1][column + 1]])
    crown_point, crown_outward, _t = skull_point(centre, radii, theta_top, 0.0, mass)
    crown = builder.add(crown_point[None, :], crown_outward[None, :],
                        np.array([[0.5, 0.0]], dtype=np.float64))
    for column in range(columns):
        builder.face([crown, grid[0][column], grid[0][column + 1]])
    return builder


def build_hair(head: Head, style: dict) -> Builder:
    """One cut. Only the afro is a cloud; every other cut is a thin skull shell."""
    if style.get("bare") or "base" not in style:
        return Builder()
    if style.get("mass"):
        return build_mass(head, style)
    return build_cap(head, style)


# --- beards: a shaped sheet over the jaw -----------------------------------

## How far around the head the beard sheet reaches, and how far past the beard
## region it runs so the cut is always inside geometry.
BEARD_ARC = 1.30
BEARD_MARGIN = 0.030


def beard_shape(style: dict, head: Head, angle: np.ndarray,
                y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The beard's design, drawn in (angle round the face, height).

    This is the part that makes a beard look like a beard and not like a smear:
    a cheek line that leaves the cheek clear, a moustache over the upper lip, a
    mouth opening, and a bottom edge that follows the jaw so the throat stays
    shaved.
    """
    shape = str(style.get("shape", "full"))
    aa = np.abs(angle)
    mouth_y = float(head.mouth[1])
    # A cheek line that climbs toward the ears, and a jaw line that does too, so
    # the hair stops where a razor would stop.
    cheek = 1.6402 + 0.0340 * smoothstep(0.15, 1.05, aa)
    jaw = 1.5832 + 0.0300 * smoothstep(0.05, 0.95, aa)
    inside = (y < cheek) & (y > jaw) & (aa < 1.12)
    if shape == "moustache":
        # An arch under the nose with tips that fall at the corners - the shape a
        # moustache actually has, rather than a bar across the lip.
        share = np.clip(aa / 0.52, 0.0, 1.0)
        top = mouth_y + 0.0145 - 0.0022 * share * share
        bottom = mouth_y + 0.0044 + 0.0068 * share * share
        inside = (y < top) & (y > bottom) & (aa < 0.52)
    elif shape == "chinstrap":
        inside = (y < jaw + 0.0205) & (y > jaw - 0.0035) & (aa < 1.06)
    # The mouth is open in every design: a beard frames a mouth.
    hole = (((y - mouth_y) / 0.0102) ** 2 + (aa / 0.40) ** 2) < 1.0
    inside = inside & ~hole
    # Thinning out at the very edge, so the border is a fade and not a cut.
    border = np.minimum(np.minimum(cheek - y, y - jaw) / 0.006,
                        (1.12 - aa) / 0.09)
    return inside, np.clip(border, 0.0, 1.0)


def beard_patch_mask(head: Head, style: dict) -> callable:
    """The sheet's own extent: everything the design could possibly cover."""
    def mask(position: np.ndarray) -> np.ndarray:
        angle = np.arctan2(position[:, 0], position[:, 2])
        y = position[:, 1]
        return (y > 1.5690) & (y < 1.6930) & (np.abs(angle) < BEARD_ARC)

    return mask


def beard_patch_uv(head: Head, style: dict) -> callable:
    def uv(position: np.ndarray) -> np.ndarray:
        angle = np.arctan2(position[:, 0], position[:, 2])
        return np.stack([angle / (2.0 * BEARD_ARC) + 0.5,
                         np.clip((1.6930 - position[:, 1]) / (1.6930 - 1.5690), 0.0, 1.0)],
                        axis=1)

    return uv


def beard_texture(head: Head, style: dict, size: int = 256) -> np.ndarray:
    """The beard's design, as alpha over a strand map.

    The silhouette lives in the texture, so the cut is as smooth as a texel and
    never the stair-step of the head mesh's triangles. The strands run down the
    sheet; the colour comes from the tint, so one map serves every hair colour.
    """
    rng = np.random.default_rng(5)
    u = (np.arange(size) + 0.5) / size
    v = (np.arange(size) + 0.5) / size
    angle = (u - 0.5) * 2.0 * BEARD_ARC
    y = (1.6930 - v * (1.6930 - 1.5690))
    a = angle[None, :].repeat(size, axis=0)
    yy = y[:, None].repeat(size, axis=1)
    inside, border = beard_shape(style, head, a, yy)
    alpha = inside.astype(np.float64) * (0.35 + 0.65 * border)
    if style.get("stubble"):
        # Short hair is a thinning edge all over, not a solid slab.
        alpha = alpha * (0.45 + 0.75 * rng.random((size, size)))
    for _ in range(2):
        alpha = 0.25 * (np.roll(alpha, 1, axis=0) + np.roll(alpha, -1, axis=0)
                        + np.roll(alpha, 1, axis=1) + np.roll(alpha, -1, axis=1))
    alpha = np.clip((alpha - 0.34) / 0.30, 0.0, 1.0)
    # Strands: fine grain that runs down the sheet, kept low so it reads as hair
    # rather than as lines drawn on a face.
    strands = np.zeros((size, size))
    for frequency, amplitude in ((23, 0.42), (41, 0.28), (79, 0.16)):
        phase = rng.random(frequency) * math.tau
        strands += np.sin(math.tau * u[None, :] * frequency + phase[:, None]).sum(axis=0)             * amplitude / 2.0
    grain = 0.80 + 0.14 * strands + 0.06 * rng.random((size, size))
    rgb = np.repeat(np.clip(grain, 0.0, 1.0)[:, :, None], 3, axis=2)
    return np.concatenate([rgb, alpha[:, :, None]], axis=2)


def build_beard(head: Head, style: dict) -> Builder:
    """A sheet laid over the jaw, cut by its own design."""
    tris = head.part["head"]["indices"].reshape(-1, 3)
    position = head.part["head"]["position"]
    offset = float(style["thickness"])
    builder = shell(position, head.part["head"]["normal"], tris,
                    beard_patch_mask(head, style), offset, rim=False,
                    uv_fn=beard_patch_uv(head, style))
    # A little unevenness so the sheet is hair lying on a jaw, not glass.
    pos, nrm, uv, tri = builder.arrays()
    ripple = 0.0011 * np.sin(pos[:, 0] * 210.0 + pos[:, 1] * 120.0) \
        + 0.0008 * np.sin(pos[:, 2] * 180.0 - pos[:, 1] * 90.0)
    pos = pos + nrm * ripple[:, None]
    out = Builder()
    out.add(pos, nrm, uv)
    out.tri.append(tri)
    return out


def veiled(rgb_u8: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Divide authored detail by the colour that carries it.

    The result keeps the artist's structure - pores, folds, weave, grime, lips -
    and loses the hue, so one texture serves every tone through ``albedo_color``.
    The base colour is the mean of the brightest fifth: the flat lit surface.
    """
    linear = srgb_to_linear(rgb_u8.astype(np.float64) / 255.0)
    luma = linear @ LUMA
    bright = luma >= np.percentile(luma, 80.0)
    base = np.maximum(linear[bright].mean(axis=0), 1e-4)
    detail = np.clip(linear / base, 0.0, 1.0)
    # The paint's own blush and lip red are kept only partly: a deep-skinned
    # mercenary with the pale character's pink cheeks reads as sunburn, while the
    # structure that makes the face a face - lips, nose, knuckles, nails - is in
    # the luminance and survives untouched.
    return linear_to_srgb(detail * 0.45 + (detail @ LUMA)[:, :, None] * 0.55), base


def hair_albedo(size: int = 256) -> np.ndarray:
    """A painterly map for hair: broad, soft locks and nothing drawn on it.

    An earlier pass baked fine strands (and a normal map of them). At the distance
    this game is played from those read as scratches etched over the skull - a
    spiderweb of thin bright lines - so the map is now a handful of large, soft
    lobes, the way a hair mass is blocked in by hand, and the fine detail lives in
    the geometry's own clumps.
    """
    rng = np.random.default_rng(20240611)
    u = np.arange(size) / size
    texture = np.zeros((size, size))
    for _ in range(26):
        # Locks run down the sheet (v), so each lobe is a soft, elongated ellipse.
        cx, cy = rng.random(), rng.random()
        rx = 0.05 + rng.random() * 0.10
        ry = 0.10 + rng.random() * 0.22
        dx = np.minimum(np.abs(u - cx), 1.0 - np.abs(u - cx)) / rx
        dy = np.abs(u - cy) / ry
        texture += (0.5 + 0.5 * np.cos(np.clip(dx * dx + dy * dy, 0.0, 4.0) * math.pi * 0.5)) \
            * (0.4 + 0.6 * rng.random())
    texture -= texture.min()
    texture /= max(texture.max(), 1e-6)
    albedo = (0.84 + 0.16 * texture)[:, :, None].repeat(3, axis=2)
    return np.clip(albedo, 0.0, 1.0)


# --- writing GLBs -----------------------------------------------------------


def write_asset(path: Path, head: Head, pieces: list[dict], images: list[tuple[str, bytes]],
                materials: list[dict], bones: int = 66) -> dict:
    """One skinned GLB: the Ranger's own skeleton, fresh meshes and materials."""
    nodes = []
    for index in range(bones):
        node = json.loads(json.dumps(head.doc["nodes"][index]))
        node.pop("mesh", None)
        node.pop("skin", None)
        nodes.append(node)
    armature_index = len(nodes)
    nodes.append({"name": "Armature", "children": [65]})
    blob = Blob()
    skin = {"joints": list(head.skin["joints"]),
            "inverseBindMatrices": blob.add(head.ibm, "MAT4", target=None),
            "name": "Armature"}
    meshes, mesh_nodes = [], []
    joint_column = np.full((1, 4), head.head_joint, dtype=np.uint16)
    for piece in pieces:
        builder = piece["builder"]
        if builder.triangles() == 0:
            continue
        pos, nrm, uv, tri = builder.arrays()
        rigid = bool(piece.get("rigid"))
        joints = np.repeat(joint_column, len(pos), axis=0) if rigid else piece["joints"]
        weights = (np.tile(np.array([1.0, 0.0, 0.0, 0.0]), (len(pos), 1)) if rigid
                   else piece["weights"])
        attributes = {
            "POSITION": blob.add(pos, "VEC3", bounds=True),
            "NORMAL": blob.add(nrm, "VEC3"),
            "TEXCOORD_0": blob.add(uv, "VEC2"),
            "JOINTS_0": blob.add(joints.astype(np.uint16), "VEC4", component=5123),
            "WEIGHTS_0": blob.add(np.asarray(weights, dtype=np.float64), "VEC4"),
        }
        meshes.append({"name": piece["name"], "primitives": [{
            "attributes": attributes,
            "indices": blob.add(tri.reshape(-1).astype(np.uint32), "SCALAR",
                                component=5125, target=34963),
            "material": int(piece["material"]), "mode": 4}]})
        mesh_nodes.append({"name": piece["name"], "mesh": len(meshes) - 1, "skin": 0})
    nodes[armature_index]["children"] = [65] + [len(nodes) + index
                                                for index in range(len(mesh_nodes))]
    nodes.extend(mesh_nodes)

    image_docs, textures = [], []
    for name, payload in images:
        image_docs.append({"name": name, "mimeType": "image/png",
                           "bufferView": blob.add_view(payload)})
        textures.append({"sampler": 0, "source": len(image_docs) - 1})
    material_docs = []
    for spec in materials:
        item = {"name": spec["name"], "doubleSided": bool(spec.get("double_sided", False)),
                "pbrMetallicRoughness": {
                    "metallicFactor": 0.0,
                    "roughnessFactor": float(spec.get("roughness", 0.8)),
                    "baseColorTexture": {"index": int(spec["albedo"])}}}
        if "normal" in spec:
            item["normalTexture"] = {"index": int(spec["normal"])}
        if spec.get("alpha"):
            # A beard's silhouette is its texture, so the cut is a texel and not a
            # triangle edge.
            item["alphaMode"] = "MASK"
            item["alphaCutoff"] = 0.5
        material_docs.append(item)
    document = {
        "asset": {"version": "2.0",
                  "generator": "Ironwood warband looks (tools/prepare_warband_looks.py)"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [armature_index]}],
        "nodes": nodes,
        "skins": [skin],
        "materials": material_docs,
        "meshes": meshes,
        "textures": textures,
        "images": image_docs,
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "accessors": blob.accessors,
        "bufferViews": blob.views,
        "buffers": [{"byteLength": 0}],
    }
    write_glb(path, document, blob.data)
    return {"nodes": len(nodes), "meshes": len(meshes), "materials": len(material_docs),
            "images": len(image_docs), "bytes": path.stat().st_size,
            "triangles": int(sum(piece["builder"].triangles() for piece in pieces))}


def iris_variants(rgb_u8: np.ndarray) -> list[np.ndarray]:
    """Recolour the authored brown iris into a handful of eye colours."""
    linear = srgb_to_linear(rgb_u8.astype(np.float64) / 255.0)
    luma = linear @ LUMA
    saturation = linear.max(axis=2) - linear.min(axis=2)
    iris = saturation > 0.06
    shape = np.clip(luma / 0.20, 0.0, 1.6)
    out = []
    for tone in EYE_TONES:
        tint = srgb_to_linear(np.array([[int(tone[1:3], 16), int(tone[3:5], 16),
                                         int(tone[5:7], 16)]], dtype=np.float64) / 255.0)[0]
        coloured = tint[None, None, :] * shape[:, :, None]
        out.append(linear_to_srgb(np.where(iris[:, :, None], coloured, linear)))
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    head = Head()

    # -- surfaces -----------------------------------------------------------
    skin_body, skin_base = veiled(np.asarray(Image.open(SKIN_ATLAS).convert("RGB")))
    skin_head = np.asarray(Image.fromarray(
        np.clip(np.round(skin_body * 255.0), 0, 255).astype(np.uint8))
        .resize((1024, 1024), Image.LANCZOS)).astype(np.float64) / 255.0
    shirt, shirt_base = veiled(np.asarray(Image.open(SHIRT_ATLAS).convert("RGB")))
    shorts, shorts_base = veiled(np.asarray(Image.open(SHORTS_ATLAS).convert("RGB")))
    save_png(OUT / "warband_skin_head_basecolor.png", skin_head)
    save_png(OUT / "warband_skin_basecolor.png", skin_body)
    save_png(OUT / "warband_shirt_basecolor.png", shirt)
    save_png(OUT / "warband_shorts_basecolor.png", shorts)
    save_png(OUT / "warband_hair_basecolor.png", hair_albedo())
    beard_textures = {}
    for beard in BEARD_STYLES:
        if beard["name"] == "None":
            continue
        pixels = beard_texture(head, beard)
        beard_textures[beard["name"]] = pixels
        save_png(OUT / ("warband_beard_%s.png" % beard["name"].lower()), pixels)

    iris_source = np.asarray(Image.open(io.BytesIO(head.image_bytes("T_Eye_Brown")))
                             .convert("RGB"))
    for index, iris in enumerate(iris_variants(iris_source)):
        save_png(OUT / ("warband_eye_%d_basecolor.png" % index), iris)

    # -- faces --------------------------------------------------------------
    face_images = [
        ("Warband_Skin_Head", (OUT / "warband_skin_head_basecolor.png").read_bytes()),
        ("Warband_Skin_Normal", head.image_bytes("T_Superhero_Male_Normal")),
        ("Warband_Hair", (OUT / "warband_hair_basecolor.png").read_bytes()),
        ("Warband_Eye_Normal", head.image_bytes("T_Eye_Normal_png")),
    ] + [("Warband_Eye_%d" % index, (OUT / ("warband_eye_%d_basecolor.png" % index)).read_bytes())
         for index in range(len(EYE_TONES))]
    face_texture = {name: index for index, (name, _payload) in enumerate(face_images)}
    face_materials = [
        {"name": "Warband_Skin", "albedo": face_texture["Warband_Skin_Head"],
         "normal": face_texture["Warband_Skin_Normal"], "roughness": 0.75},
        {"name": "Warband_Hair", "albedo": face_texture["Warband_Hair"], "roughness": 0.90,
         "double_sided": True},
    ] + [{"name": "Warband_Eye_%d" % index, "albedo": face_texture["Warband_Eye_%d" % index],
          "normal": face_texture["Warband_Eye_Normal"], "roughness": 0.25,
          "double_sided": True} for index in range(len(EYE_TONES))]
    skin_material, hair_material, eye_material = 0, 1, 2

    face_pieces = []
    for index, prm in enumerate(FACE_VARIANTS):
        warped = {
            "head": face_warp(head.part["head"]["position"], head, prm),
            "brows": face_warp(head.part["brows"]["position"], head, prm),
            "eyes": rigid_eye_offset(head.part["eyes"]["position"], head, prm),
        }
        for key, suffix, material in (("head", "Skin", skin_material),
                                      ("brows", "Brows", hair_material),
                                      ("eyes", "Eyes", eye_material)):
            source = head.part[key]
            builder = Builder()
            builder.add(warped[key], source["normal"], source["uv"])
            builder.tri.append(source["indices"].reshape(-1, 3))
            face_pieces.append({"name": "Face%d_%s" % (index + 1, suffix), "builder": builder,
                                "material": material, "joints": source["joints"],
                                "weights": source["weights"]})
    face_stats = write_asset(FACES_GLB, head, face_pieces, face_images, face_materials)

    # -- hair ---------------------------------------------------------------
    hair_images = [("Warband_Hair", (OUT / "warband_hair_basecolor.png").read_bytes())]
    # One material for every cut: a sealed mass, so no back faces are needed and
    # the surface cannot shade itself into a black band.
    hair_materials = [{"name": "Warband_Hair_Mass", "albedo": 0, "roughness": 0.92,
                       "double_sided": False}]
    hair_pieces = [{"name": "Hair_%s" % style["name"], "builder": build_hair(head, style),
                    "material": 0, "rigid": True}
                   for style in HAIR_STYLES]
    for style in BEARD_STYLES:
        if style["name"] == "None":
            continue
        pixels = beard_textures[style["name"]]
        hair_images.append(("Warband_Beard_%s" % style["name"], png_bytes(pixels)))
        hair_materials.append({"name": "Warband_Beard",
                               "albedo": len(hair_images) - 1, "roughness": 0.92,
                               "double_sided": True, "alpha": True})
        hair_pieces.append({"name": "Beard_%s" % style["name"],
                            "builder": build_beard(head, style),
                            "material": len(hair_materials) - 1, "rigid": True})
    hair_stats = write_asset(HAIR_GLB, head, hair_pieces, hair_images, hair_materials)

    # -- metadata -----------------------------------------------------------
    TONES["skin"][0] = hex_of(skin_base)
    TONES["shirt"][0] = hex_of(shirt_base)
    TONES["shorts"][0] = hex_of(shorts_base)
    meta = {
        "asset": "warband looks",
        "tool": "tools/prepare_warband_looks.py",
        "command": "python tools/prepare_warband_looks.py",
        "source": "assets/characters/ironwood_ranger.glb (head, brows, eyes) and the "
                  "naked set's own atlases in assets/characters/armor/",
        "licence": "Derived from the CC0 Quaternius Universal Base Characters pack; see "
                   "assets/characters/LICENSE.txt",
        "head": {"chin_y": round(head.chin_y, 5), "top_y": round(head.top, 5),
                 "half_width": round(head.half_width, 5), "back_z": round(head.back, 5),
                 "nose_tip": [round(float(value), 5) for value in head.nose],
                 "eye_centre": [round(float(value), 5) for value in head.eye_centre],
                 "mouth": [round(float(value), 5) for value in head.mouth],
                 "head_joint": head.head_joint},
        "faces": [dict(variant) for variant in FACE_VARIANTS],
        "hair": [dict(style) for style in HAIR_STYLES],
        "beards": [dict(style) for style in BEARD_STYLES],
        "tones": TONES,
        "eye_tones": EYE_TONES,
        "veil": {"skin": [round(float(value), 4) for value in skin_base],
                 "shirt": [round(float(value), 4) for value in shirt_base],
                 "shorts": [round(float(value), 4) for value in shorts_base]},
        "files": {FACES_GLB.name: face_stats, HAIR_GLB.name: hair_stats},
    }
    META.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print("WARBAND_LOOKS faces=%d hair=%d beards=%d face_tris=%d hair_tris=%d"
          % (len(FACE_VARIANTS), len(HAIR_STYLES), len(BEARD_STYLES) - 1,
             face_stats["triangles"], hair_stats["triangles"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
