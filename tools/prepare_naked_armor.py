"""Author the Naked armor set on the Ranger's own skeleton.

What a prisoner in the wood actually wears: an old shirt, a pair of tight
shorts, and bare skin everywhere else.  Two pieces, exported as one GLB the
runtime binds to its copy of the hero skeleton:

    Armor_Naked_Chest   torso, both arms and both hands as skin, with a
                        short-sleeved shirt worn over the torso
    Armor_Naked_Legs    both legs and both feet as skin, with tight shorts
                        over the hips and upper thighs

The garment is deliberately not fitted to the measured body.  The shirt, the
shorts and the skin under them are surfaces of revolution about their own
axes, with the radius taken from a keyed profile of height: consecutive rings
cannot cross and no column can cut into another, so no pose can open a hole.
Sleeves and shorts legs start *inside* the tube they belong to.  A loft that
followed the source's uneven tunic rows produced valleys, and the bare body
stood through them.

The rig hides a whole slot at a time, so the chest has to carry the arms and
the hands: the Ranger's ``Male_Ranger_Arms`` mesh is chest-slot geometry and
its skin primitive is the only hand geometry in the source asset.  The legs
carry the feet for the same reason -- ``Male_Ranger_Feet_Boots`` is the feet
slot, and with nothing in that slot the naked figure would end at the ankle.
The head, eyes, brows and hair are outside every slot and stay on screen, so
the new skin has to match them: every colour in this file is read out of the
Ranger's own skin materials, never invented.

Usage (Blender 5.1+):
    blender --background --python-exit-code 1 --python tools/prepare_naked_armor.py

The stage imports ``assets/characters/ironwood_ranger.glb`` and takes the
torso, hip, knee, wrist and ankle envelopes from it, along with the hands
themselves.  Pieces are modelled in the Ranger's bind space (armature space
metres, +X is the character's left, -Y forward, +Z up), skinned with explicit
vertex weights onto bones the Ranger has, joined per slot and exported with a
skeleton whose bone names match the Ranger's exactly.

Surface palettes are measured, not chosen:

``skin``   The albedo, roughness and normal statistics come from the textures
           bound to the Ranger's own skin materials -- ``MI_Superhero_Male``
           on the head and ``MI_Regular_Male`` on the hands -- sampled through
           the UVs those meshes actually use.  The body shell is shaded by
           blending the measured shadow/base/light percentiles with noise, so
           every texel is a real skin colour.  Fingers and thumb are modelled
           on the ends of the arm tubes; the source's own hand mesh is fingers
           without a palm, so it cannot be joined to a forearm.

``cloth``  ``tools/forest_surface.py``'s grave-cloth sampler, passed a linen
           palette for the shirt and a wool palette for the shorts, so the
           shirt wears like the rest of the world's cloth.

Geometry helpers are the fitted-garment toolkit written for the Makeshift set
(``tools/prepare_makeshift_armor.py``): identical measurement, lofting and UV
code, so the two kits are fitted the same way.  Only the pieces, the skin field
and the atlas provenance differ.

Each surface is one 512 atlas sampled at half its exported edge: the fields
behind skin and grave cloth have nothing finer in them than a couple of
millimetres, so a denser bake would only cost time.  The whole stage runs in
about eight seconds.

Cloth against skin is measured and reported rather than gated.  A set-in sleeve
starts inside the torso and a crotch is closed by the two shorts legs crossing
each other, so a crossing depth cannot be read as a defect on its own; what the
build does gate is weight validity, the triangle budget, and anything crossing
the face, the eyes or the brows above the jaw -- those stay on screen whatever
armour is worn.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import time
from pathlib import Path

import numpy as np
import bpy
from mathutils import Matrix, Vector

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import forest_styles as styles  # noqa: E402
import forest_surface as surfaces  # noqa: E402
import prepare_forest_mobs as mobs  # noqa: E402
import prepare_makeshift_armor as salvage  # noqa: E402

TAU = math.tau
ROOT = styles.ROOT
SEED = styles.SEED
FPS = styles.FPS

RANGER = ROOT / "assets" / "characters" / "ironwood_ranger.glb"
OUTPUT = ROOT / "assets" / "characters" / "armor" / "ironwood_naked.glb"
WORKSPACE = ROOT / ".runtime" / "naked-armor"
TEXTURES = WORKSPACE / "textures"

SLOTS = ("chest", "legs")
NODE_NAME = {"chest": "Armor_Naked_Chest", "legs": "Armor_Naked_Legs"}
SURFACE_ORDER = ("skin", "cloth")
MATERIAL_NAME = {"skin": "Naked_Skin", "cloth": "Naked_Cloth"}
# Two pieces and a pair of hands: 512 is a texel every two millimetres on the
# body, and the hands are a straight resample of the source's own skin, so a
# larger atlas would only re-enlarge texels that are already that size.
ATLAS_SIZE = {"skin": 512, "cloth": 512}
TRIANGLE_BUDGET = 16_000

# The measured envelopes the pieces are fitted to.  Everything below is metres
# in bind space; the Ranger stands with its soles at z = 0.
TORSO_Z0, TORSO_Z1 = 0.900, 1.596
TORSO_INSET = 0.012
# Where the shoulder gathers into the neck.  The neck itself is the head mesh's
# envelope, so both the skin and the shirt have to converge on it.
# The garment and the skin under it are surfaces of revolution about the
# torso axis: the radius is a keyed function of height only, so a ring can
# never cross the ring above it and no column can cut into another.  The
# measured body is only used for the sleeve and leg envelopes, which follow
# their bones.  Aspect is the front-to-back flattening of every ring.
BODY_ASPECT = 0.76
BODY_CENTRE_Y = 0.012
SHIRT_PROFILE = ((0.918, 0.206), (0.960, 0.199), (1.040, 0.191), (1.160, 0.201),
                 (1.300, 0.216), (1.400, 0.209), (1.470, 0.198), (1.515, 0.170),
                 (1.548, 0.120), (1.572, 0.092), (1.586, 0.086))
SKIN_PROFILE = ((0.900, 0.176), (0.960, 0.169), (1.040, 0.161), (1.160, 0.171),
                (1.300, 0.186), (1.400, 0.179), (1.470, 0.168), (1.515, 0.140),
                (1.548, 0.086), (1.572, 0.064), (1.596, 0.060))
SHIRT_HEM_Z, SHIRT_NECK_Z = 0.918, 1.586
SKIN_HEM_Z, SKIN_NECK_Z = 0.900, 1.596
COLLAR_Z = (1.560, 1.596)
# Shorts: a hip tube with two leg tubes starting inside it.
SHORTS_HIP_Z = (0.930, 1.062)
SHORTS_LEG_Z = (0.700, 0.995)
SHORTS_LEG_RADIUS = (0.108, 0.096)
ARM_INSET = 0.009
# The ankle is where the leg tube hands over to the foot's own shell: the tube
# ends inside the foot, at the narrowest radius the two can share.
ANKLE_Z, ANKLE_RADIUS = 0.112, 0.038
# The leg tube ends below the foot's ankle ring, inside the foot shell, so the
# tube's rim cannot show as a ledge above the foot.
LEG_BOTTOM = 0.075
LEG_Z1 = 1.020
LEG_INSET = 0.010
SOCK_INSET = 0.006
SHIRT_INSET = -0.018
SHIRT_HEM = 0.925
SLEEVE_FROM, SLEEVE_TO = -0.300, 0.420
SLEEVE_RADIUS = (0.076, 0.058)
# The palm the fingers grow out of: the arm tube's section at the knuckles.
HAND_RADIUS = (0.048, 0.026)
HAND_CENTRE = Vector((0.0, 0.062, 1.450))
CUFF_GROW = 0.006
# Feet are authored from the ankle down; the sole sits on the ground plane the
# Ranger's boots stand on (their lowest vertex is at -0.004, the sole at 0).
FOOT_SOLE = 0.004
FOOT_TOP = 0.145

# The measured skin roughness (0.66) with room for the field's own variation.
SKIN_ROUGH_RANGE = (0.52, 0.80)

# The Ranger's skin materials, and the glTF images Blender unpacks from them.
SKIN_HEAD_MATERIAL = "MI_Superhero_Male"
SKIN_HAND_MATERIAL = "MI_Regular_Male"
HAND_MATERIAL = "MI_Regular_Male"
ARM_MESH = "Male_Ranger_Arms"

# Shirt and shorts are a washed linen and a coarse wool: near-uniform, with
# slubs and the weave readable only close up.  ``contrast`` is the full albedo
# range the field is allowed to swing through, in sRGB value, so the cloth
# cannot turn into a print.  ``weave`` is the thread pitch in metres; it has to
# stay well above the atlas texel (about 2 mm) or the pattern aliases into
# blotches, which is exactly what a 1.2 mm shader weave did here.
CLOTH_LOOKS = {
    "shirt": {"base": "#ada18c", "contrast": 0.34, "weave": 0.0110,
              "rough": (0.86, 0.92), "slub": 0.030},
    # Collar, placket and buttons sit a shade darker than the body of the shirt.
    "trim": {"base": "#988974", "contrast": 0.30, "weave": 0.0110,
             "rough": (0.87, 0.93), "slub": 0.026},
    "shorts": {"base": "#635c50", "contrast": 0.48, "weave": 0.0130,
               "rough": (0.86, 0.93), "slub": 0.040},
}

START = 0.0


def stamp(label: str) -> None:
    """Print the stage and the seconds since the run began."""
    print(f"NAKED_STAGE {label} {time.perf_counter() - START:.1f}s", flush=True)


RIG: bpy.types.Object | None = None
MEASURE = None
SKIN = None
IDLE_ACTION: bpy.types.Action | None = None


# ---------------------------------------------------------------------------
# Colour: sRGB value space, matching what Blender hands back from a PNG


def srgb_to_linear(values: np.ndarray) -> np.ndarray:
    values = np.clip(np.asarray(values, np.float64), 0.0, 1.0)
    return np.where(values <= 0.04045, values / 12.92,
                    ((values + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(values: np.ndarray) -> np.ndarray:
    values = np.clip(np.asarray(values, np.float64), 0.0, 1.0)
    return np.where(values <= 0.0031308, values * 12.92,
                    1.055 * np.power(np.maximum(values, 0.0), 1.0 / 2.4) - 0.055)


def image_rgb(image: bpy.types.Image) -> np.ndarray:
    """The image as ``(height, width, 3)`` in its stored sRGB values."""
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(height, width, 4)[..., :3].astype(np.float64)


def sample_image(image: np.ndarray, uv: np.ndarray) -> np.ndarray:
    """Bilinear sample of an image array at glTF UVs (v measured upward)."""
    height, width = image.shape[:2]
    x = np.clip(uv[:, 0] * width - 0.5, 0.0, width - 1.0)
    y = np.clip(uv[:, 1] * height - 0.5, 0.0, height - 1.0)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    x1 = np.minimum(x0 + 1, width - 1)
    y1 = np.minimum(y0 + 1, height - 1)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    top = image[y0, x0] * (1.0 - fx) + image[y0, x1] * fx
    bottom = image[y1, x0] * (1.0 - fx) + image[y1, x1] * fx
    return top * (1.0 - fy) + bottom * fy


# ---------------------------------------------------------------------------
# Deterministic value noise for the skin field


def _lattice(ix, iy, iz, salt: int) -> np.ndarray:
    h = ix * np.int64(73856093) ^ iy * np.int64(19349663) ^ iz * np.int64(83492791)
    h = (h + np.int64(salt) * np.int64(2654435761)) & np.int64(0x7FFFFFFF)
    h = ((h ^ (h >> 13)) * np.int64(1274126177)) & np.int64(0x7FFFFFFF)
    return ((h ^ (h >> 16)) & np.int64(0xFFFF)).astype(np.float64) / 65535.0


def value_noise(points: np.ndarray, frequency: float, salt: int) -> np.ndarray:
    """A trilinear value-noise field in 0..1 at bind-space points."""
    scaled = np.asarray(points, np.float64) * frequency
    base = np.floor(scaled).astype(np.int64)
    fraction = scaled - base
    smooth = fraction * fraction * (3.0 - 2.0 * fraction)
    total = np.zeros(len(points), np.float64)
    for dx in (0, 1):
        wx = smooth[:, 0] if dx else 1.0 - smooth[:, 0]
        for dy in (0, 1):
            wy = smooth[:, 1] if dy else 1.0 - smooth[:, 1]
            for dz in (0, 1):
                wz = smooth[:, 2] if dz else 1.0 - smooth[:, 2]
                total += wx * wy * wz * _lattice(base[:, 0] + dx, base[:, 1] + dy,
                                                 base[:, 2] + dz, salt)
    return total


def fbm(points: np.ndarray, frequency: float, salt: int, octaves: int = 3) -> np.ndarray:
    total = np.zeros(len(points), np.float64)
    weight = 0.0
    amplitude = 1.0
    for octave in range(octaves):
        total += value_noise(points, frequency * (2.0 ** octave), salt + octave * 7) * amplitude
        weight += amplitude
        amplitude *= 0.5
    return total / weight


def cloth_surface(look: dict, points: np.ndarray) -> dict[str, np.ndarray]:
    """Linen or wool at bind-space points: a flat field with a faint weave."""
    base = np.array([int(look["base"].lstrip("#")[index:index + 2], 16) / 255.0
                     for index in (0, 2, 4)], np.float64)
    pitch = float(look["weave"])
    warp = 0.5 + 0.5 * np.sin(TAU * points[:, 2] / pitch)
    weft = 0.5 + 0.5 * np.sin(TAU * points[:, 0] / pitch + 1.7)
    weave = 0.6 * warp + 0.4 * weft
    # Nearly uniform: the broad term is only a whisper, so the cloth cannot
    # read as a print from across the camp.  What carries it is the weave at
    # thread pitch and a fibre grain just above the atlas texel.
    broad = fbm(points, 11.0, 61, 2)
    fine = value_noise(points, 52.0, 67) * 0.6 + value_noise(points, 88.0, 73) * 0.4
    slub = np.clip((value_noise(points, 110.0, 71) - 0.74) / 0.26, 0.0, 1.0)
    # The broad term is a whisper: at 9 cm it reads as staining rather than
    # cloth, and a washed shirt is near-uniform.  Fibre and slubs carry the
    # value spread instead.
    shade = (0.5 + (broad - 0.5) * 0.06 + (fine - 0.5) * 0.72
             + (weave - 0.5) * 0.16 + slub * float(look["slub"]))
    albedo = np.clip(base[None, :] * (1.0 + (shade - 0.5)[:, None] * float(look["contrast"])),
                     0.0, 1.0)
    low, high = look["rough"]
    roughness = low + (high - low) * np.clip(0.30 + 0.70 * (fine * 0.6 + weave * 0.4), 0.0, 1.0)
    # Flat: a differentiated height field is evaluated per texel, and every UV
    # island in the atlas is scaled differently, so relief that fine changes
    # from island to island and reads as a print rather than as cloth.  At four
    # millimetres a texel there is no cloth relief to resolve anyway; the albedo
    # carries the weave.
    height = np.full(len(points), 0.5)
    return {"albedo": albedo, "height": height, "roughness": roughness}


# ---------------------------------------------------------------------------
# The Ranger's own skin, measured


class SkinSource:
    """The skin already on the Ranger: palette, roughness, and the hand texels.

    The head mesh and the hands are the only skin the source asset carries, and
    they use two different body textures.  Both are sampled through the UVs the
    meshes actually use, so lips, brows and everything the artists painted stay
    out of the statistics: what is left is the colour of the skin itself.
    """

    def __init__(self) -> None:
        head = bpy.data.objects["Ranger_Head_SuperHero_Male"]
        arms = bpy.data.objects[ARM_MESH]
        head_images = self._images(SKIN_HEAD_MATERIAL)
        hand_images = self._images(SKIN_HAND_MATERIAL)
        self.head_albedo = image_rgb(head_images["albedo"])
        self.head_roughness = image_rgb(head_images["roughness"])
        self.head_normal = image_rgb(head_images["normal"])
        self.hand_albedo = image_rgb(hand_images["albedo"])
        self.hand_roughness = image_rgb(hand_images["roughness"])
        self.hand_normal = image_rgb(hand_images["normal"])

        head_texels = self._texels(head, 0, head_images["albedo"], self.head_albedo)
        hand_texels = self._texels(arms, self._hand_slot(arms), hand_images["albedo"],
                                   self.hand_albedo)
        texels = np.concatenate([head_texels, hand_texels])

        self.shadow = self._percentile(texels, 15)
        self.base = self._percentile(texels, 50)
        self.light = self._percentile(texels, 85)
        self.spread = float(np.percentile(texels.mean(axis=1), 85)
                            - np.percentile(texels.mean(axis=1), 15))

        head_uv = self._texel_uvs(head, 0, 256)
        hand_uv = self._texel_uvs(arms, self._hand_slot(arms), 256)
        head_rough = sample_image(self.head_roughness, head_uv)[:, 1]
        hand_rough = sample_image(self.hand_roughness, hand_uv)[:, 1]
        rough = np.concatenate([head_rough, hand_rough])
        self.roughness = float(np.median(rough))
        self.roughness_band = float(np.percentile(rough, 85) - np.percentile(rough, 15))

        print("NAKED_SKIN", "shadow", [round(float(v), 4) for v in self.shadow],
              "base", [round(float(v), 4) for v in self.base],
              "light", [round(float(v), 4) for v in self.light],
              "spread", round(self.spread, 4), "roughness", round(self.roughness, 4))

    @staticmethod
    def _images(material_name: str) -> dict[str, bpy.types.Image]:
        material = bpy.data.materials[material_name]
        found: dict[str, bpy.types.Image] = {}
        for node in material.node_tree.nodes:
            if node.type != "TEX_IMAGE" or node.image is None:
                continue
            name = node.image.name
            if "Roughness" in name or "ORM" in name:
                found.setdefault("roughness", node.image)
            elif "Normal" in name:
                found.setdefault("normal", node.image)
            else:
                found.setdefault("albedo", node.image)
        missing = {"albedo", "normal", "roughness"} - set(found)
        if missing:
            raise SystemExit(f"{material_name} is missing images: {sorted(missing)}")
        return found

    @staticmethod
    def _hand_slot(arms: bpy.types.Object) -> int:
        for index, material in enumerate(arms.data.materials):
            if material is not None and material.name == HAND_MATERIAL:
                return index
        raise SystemExit(f"{ARM_MESH} carries no {HAND_MATERIAL} primitive")

    @staticmethod
    def _texel_uvs(obj: bpy.types.Object, slot: int, size: int) -> np.ndarray:
        chunks = mobs.triangle_texels(obj, slot, size)
        if not chunks:
            raise SystemExit(f"{obj.name}: no texels for material slot {slot}")
        flat = np.concatenate([chunk[0] for chunk in chunks])
        return np.stack([(flat % size + 0.5) / size, (flat // size + 0.5) / size], axis=1)

    def _texels(self, obj: bpy.types.Object, slot: int, image: bpy.types.Image,
                pixels: np.ndarray) -> np.ndarray:
        uv = self._texel_uvs(obj, slot, 256)
        return sample_image(pixels, uv)

    @staticmethod
    def _percentile(texels: np.ndarray, percent: float) -> np.ndarray:
        luminance = texels.mean(axis=1)
        order = np.argsort(luminance)
        low = int(len(order) * 0.05)
        high = max(low + 1, int(len(order) * 0.95))
        window = order[low:high]
        target = np.percentile(luminance[window], percent)
        nearest = window[np.argmin(np.abs(luminance[window] - target))]
        return texels[nearest].copy()

    # -- fields -----------------------------------------------------------
    def body_field(self, points: np.ndarray) -> dict[str, np.ndarray]:
        """Shade the authored body shell from the measured palette."""
        coarse = fbm(points, 9.0, 3, 3) * 0.66 + fbm(points, 26.0, 11, 2) * 0.34
        fine = fbm(points, 46.0, 17, 2) * 0.68 + fbm(points, 92.0, 23, 1) * 0.32
        shade = np.clip(0.5 + (coarse - 0.5) * 1.25 + (fine - 0.5) * 0.45, 0.0, 1.0)

        shadow = srgb_to_linear(self.shadow)
        base = srgb_to_linear(self.base)
        light = srgb_to_linear(self.light)
        under = 1.0 - shade
        albedo = np.where((shade < 0.5)[:, None],
                          shadow[None, :] + (base - shadow)[None, :] * (shade * 2.0)[:, None],
                          base[None, :] + (light - base)[None, :] * ((shade - 0.5) * 2.0)[:, None])

        # Creases darken toward the measured shadow: elbows and knees are where
        # a body creases, and the whole shift stays inside the sampled spread.
        crease = np.zeros(len(points), np.float64)
        for centre, radius in SKIN_CREASES:
            distance = np.linalg.norm(points - np.array(centre, np.float64), axis=1)
            crease = np.maximum(crease, np.clip(1.0 - distance / radius, 0.0, 1.0) ** 2)
        crease *= 0.55 * (0.35 + 0.65 * under)
        albedo = albedo + (shadow[None, :] - albedo) * crease[:, None]

        height = np.clip(0.5 + (fine - 0.5) * 0.55 + (fbm(points, 34.0, 29, 2) - 0.5) * 0.35
                         + (fbm(points, 96.0, 31, 1) - 0.5) * 0.22, 0.0, 1.0)
        roughness = np.clip(self.roughness + (fine - 0.5) * self.roughness_band * 0.55,
                            *SKIN_ROUGH_RANGE)
        return {
            "albedo": linear_to_srgb(albedo),
            "height": height,
            "roughness": roughness,
        }

# The elbow and knee centres, in bind space.  Arms are modelled in a T-pose, so
# an elbow is a point along the arm axis, not a height.
SKIN_CREASES: list[tuple[tuple[float, float, float], float]] = []


def set_creases() -> None:
    """Read the elbow and knee joints once the rig is known."""
    global SKIN_CREASES
    knees = []
    elbows = []
    for tag in ("l", "r"):
        elbow = MEASURE.joint(f"lowerarm_{tag}")
        elbows.append((tuple(elbow), 0.050))
        knee = MEASURE.joint(f"calf_{tag}")
        knees.append((tuple(knee), 0.060))
    SKIN_CREASES = elbows + knees
    print("NAKED_CREASES", [(tuple(round(v, 3) for v in c), round(r, 3)) for c, r in SKIN_CREASES])


# ---------------------------------------------------------------------------
# Authoring helpers that the Makeshift toolkit does not provide


def assign_weights(obj: bpy.types.Object, weight_fn, smooth_iterations: int = 2,
                   limit: int = 4) -> None:
    """Per-vertex weights, edge-smoothed so a seam cannot tear at a joint."""
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


def gaussian_weights(point: Vector, names, sigma: float) -> dict[str, float]:
    segments = MEASURE.segments
    values: dict[str, float] = {}
    for name in names:
        a, b = segments[name]
        distance = mobs.point_segment_distance(point, a, b)
        weight = math.exp(-((distance / sigma) ** 2))
        if weight > 1e-6:
            values[name] = weight
    if not values:
        nearest = min(names, key=lambda n: mobs.point_segment_distance(point, *segments[n]))
        return {nearest: 1.0}
    return values


def clearance_report(objects: list[bpy.types.Object], refs: list[str], label: str,
                     strict: list[str], floor_z: float = -1.0e9) -> tuple[list[str], dict]:
    """Shell-intersection test against named surfaces in the scene.

    A signed distance is useless on layered, occasionally open shells: the
    nearest triangle can be on the far side of a limb.  Two triangle trees
    either cross or they do not, so:

    ``strict``   references that must never be crossed at all -- the face, the
                 eyes and the brows are on screen whatever the armour, so a
                 single crossing fails the build.
    everything else
                 reported only, because a cuff seated on an arm, a set-in
                 sleeve or a neck emerging from its shoulders is nested by
                 design and its depth cannot be read as a defect.

    ``floor_z`` limits the gate to the part of the reference that is on screen
    regardless of armour: skin may meet the jaw, but nothing may pass through
    the face above it.
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
            above = 0
            if floor_z > -1.0e8:
                above = sum(1 for pair in hits
                            if (piece.matrix_world @ piece.data.polygons[pair[0]].center).z > floor_z)
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
                "above_floor": above,
                "floor_z": round(floor_z, 3) if floor_z > -1.0e8 else None,
                "max_depth_mm": round(depth * 1000.0, 2),
                "nearest_mm": round(closest * 1000.0, 2),
            }
            print(f"NAKED_CLEARANCE {label} {piece.name} vs {ref} intersections={len(hits)} "
                  f"depth={depth * 1000.0:.2f}mm nearest={closest * 1000.0:.1f}mm")
            if hits and os.environ.get("NAKED_DEBUG_HITS"):
                indices = sorted({pair[0] for pair in hits})
                sample = [piece.data.polygons[index].center
                          for index in indices[::max(1, len(indices) // 6)]][:6]
                print(f"NAKED_HITS {label} {piece.name} vs {ref} "
                      + " ".join(f"({c.x:.3f},{c.y:.3f},{c.z:.3f})" for c in sample))
            if above > 0 and ref in strict:
                problems.append(f"{label}: {above} triangles of {piece.name} cross {ref} "
                                f"above z={floor_z:.3f}")
        report[piece.name] = entry
        evaluated.to_mesh_clear()
    return problems, report


def validate_piece(piece: bpy.types.Object, claimed: list[str]) -> list[str]:
    """Fail the build on an unweighted vertex, an empty group or a stray bone."""
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
# Pieces
#
# Every part carries the surface it is baked with and the weights it follows.
# Parts are grouped by (surface, palette, provenance) before the atlas is laid
# out, so a slot's skin shares one atlas cell and the hands get their own.


class Part:
    def __init__(self, obj: bpy.types.Object, surface: str, weights,
                 palette: str | None = None):
        self.obj = obj
        self.surface = surface
        self.weights = weights
        self.palette = palette

    def key(self, slot: str) -> tuple:
        return (slot, self.surface, self.palette or "")


def skin(material_of) -> bpy.types.Material:
    return material_of("skin")


def cloth(material_of) -> bpy.types.Material:
    return material_of("cloth")


def torso_weights(point: Vector) -> dict[str, float]:
    """Spine chain plus the clavicles.

    The arm bones are deliberately absent: a shoulder weighted to its own
    upper arm is dragged down with the arm and the shirt tears open at the
    armhole.  The sleeve is separate geometry and carries the arm weights, so
    the armhole edge stays on the shoulder where it was fitted.
    """
    names = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]
    if abs(point.x) > 0.06:
        names += ["clavicle_l", "clavicle_r"]
    return gaussian_weights(point, names, 0.115)


def sleeve_weights(point: Vector) -> dict[str, float]:
    return arm_weights(point)


def arm_weights(point: Vector) -> dict[str, float]:
    """Upper arm and forearm only: the tube ends inside the palm."""
    tag = "l" if point.x > 0.0 else "r"
    names = [f"clavicle_{tag}", f"upperarm_{tag}", f"lowerarm_{tag}"]
    return gaussian_weights(point, names, 0.095)


def leg_weights(point: Vector) -> dict[str, float]:
    tag = "l" if point.x > 0.0 else "r"
    names = [f"thigh_{tag}", f"calf_{tag}", f"foot_{tag}"]
    if point.z > 0.960:
        names.append("pelvis")
    return gaussian_weights(point, names, 0.100)


def foot_weights(point: Vector) -> dict[str, float]:
    tag = "l" if point.x > 0.0 else "r"
    return gaussian_weights(point, [f"calf_{tag}", f"foot_{tag}", f"ball_{tag}"], 0.075)


def shorts_weights(point: Vector) -> dict[str, float]:
    tag = "l" if point.x > 0.0 else "r"
    return gaussian_weights(point, ["pelvis", f"thigh_{tag}"], 0.085)


# -- the arm silhouette, shared by the skin sleeve and the shirt sleeve ------

ARM_TABLES: dict[float, dict] = {}
# Where each hand's wrist opening is, so the forearm can end inside the palm.


def measure_arms() -> None:
    """Sample each arm's ring centre and radius along the shoulder->wrist axis.

    The Ranger's sleeve and bracer are the outer surface of the arm, so the
    skin radius is the measured radius less the cloth that used to be there.
    The hand's own opening is measured too: the forearm tube has to disappear
    inside the palm rather than end in a cuff the hand does not fill.
    """
    refs = [ARM_MESH, "Male_Ranger_Arms_Bracer"]
    source = bpy.data.objects[ARM_MESH]
    for side in (1.0, -1.0):
        tag = "l" if side > 0 else "r"
        shoulder = MEASURE.joint(f"upperarm_{tag}")
        wrist = MEASURE.joint(f"hand_{tag}")
        a = Vector((side * abs(shoulder.x), shoulder.y, shoulder.z))
        b = Vector((side * abs(wrist.x), wrist.y, wrist.z))
        rows = []
        for step in range(25):
            t = -0.06 + step * 0.05
            ring = MEASURE.axis_ring(refs, a, b, max(t, 0.0), 0.05)
            radius = MEASURE.radius_along(refs, a, b, max(t, 0.0), 0.07, 0.30, 40.0)
            rows.append((t, ring["cy"], ring["cz"], radius))
        # The bracer's straps and plates sit on the sleeve, so a single ring
        # measures a ridge and the next measures a valley.  Smoothing across
        # five rings is what stops the arm coming out as a string of sausages.
        smoothed = []
        for index, row in enumerate(rows):
            window = rows[max(0, index - 2): index + 3]
            smoothed.append((row[0],
                             sum(item[1] for item in window) / len(window),
                             sum(item[2] for item in window) / len(window),
                             sorted(item[3] for item in window)[len(window) // 2]))
        rows = smoothed
        ARM_TABLES[side] = {"a": a, "b": b, "rows": rows}

        print("NAKED_ARM", tag, "r", [round(row[3], 4) for row in rows[::4]])


def arm_ring(side: float, t: float) -> tuple[float, float, float]:
    """Ring centre (y, z) and cloth radius of the arm at a point along it."""
    table = ARM_TABLES[side]
    rows = table["rows"]
    if t <= rows[0][0]:
        row = rows[0]
        return row[1], row[2], row[3]
    if t >= rows[-1][0]:
        row = rows[-1]
        return row[1], row[2], row[3]
    for index in range(len(rows) - 1):
        if t <= rows[index + 1][0]:
            lo, hi = rows[index], rows[index + 1]
            span = max(1e-9, hi[0] - lo[0])
            share = (t - lo[0]) / span
            return (lo[1] + (hi[1] - lo[1]) * share,
                    lo[2] + (hi[2] - lo[2]) * share,
                    lo[3] + (hi[3] - lo[3]) * share)
    row = rows[-1]
    return row[1], row[2], row[3]


def arm_axis(side: float, t: float) -> tuple[Vector, float, float]:
    """Bare arm ring: centre, and the Y/Z radii of the ellipse on that centre.

    The bracer this set replaces is thicker than the upper sleeve, so the
    forearm is inset further than the upper arm.  Past the wrist the ring
    flattens onto the palm's section, so the same tube carries the hand.
    """
    table = ARM_TABLES[side]
    a, b = table["a"], table["b"]
    cy, cz, radius = arm_ring(side, t)
    centre = Vector((a.x + (b.x - a.x) * t, cy, cz))
    inset = ARM_INSET + 0.003 * mobs.smoothstep(0.40, 0.90, t)
    skin_radius = max(0.028, min(0.068, radius - inset))
    ry = rz = skin_radius
    blend = mobs.smoothstep(0.86, 1.10, t)
    if blend > 0.0:
        centre.y += (HAND_CENTRE.y - centre.y) * blend
        centre.z += (HAND_CENTRE.z - centre.z) * blend
        ry += (HAND_RADIUS[0] - ry) * blend
        rz += (HAND_RADIUS[1] - rz) * blend
    return centre, ry, rz


def radial_shell(name, profile, z0: float, z1: float, cols: int, rows: int, material,
                 thickness: float = 0.0, aspect: float = BODY_ASPECT,
                 centre_y: float = BODY_CENTRE_Y):
    """A surface of revolution about the torso axis, radius from a keyed table.

    The radius is a function of height alone, so consecutive rings cannot cross
    and no column can cut into another: the shell is incapable of folding into
    itself, which is what a garment lofted around an uneven measured body did.
    """

    def sample(u, v):
        theta = TAU * u
        z = z0 + (z1 - z0) * v
        radius = mobs.keyed(z, profile)
        return Vector((math.cos(theta) * radius,
                       centre_y + math.sin(theta) * radius * aspect, z))

    return salvage.surface_grid(name, cols, rows, sample, material, thickness=thickness,
                                axis=Vector((0.0, centre_y, 0.5 * (z0 + z1))))


def sleeve_radius(t: float) -> float:
    share = (t - SLEEVE_FROM) / (SLEEVE_TO - SLEEVE_FROM)
    return SLEEVE_RADIUS[0] + (SLEEVE_RADIUS[1] - SLEEVE_RADIUS[0]) * min(1.0, max(0.0, share))


def build_chest(material_of) -> list[Part]:
    """Torso, arms and hands as skin, with a short-sleeved shirt over the torso."""
    parts: list[Part] = []
    mouth = ARM_TABLES[1.0]["a"]
    wrist = ARM_TABLES[1.0]["b"]

    parts.append(Part(radial_shell("NAKED_Torso", SKIN_PROFILE, SKIN_HEM_Z, SKIN_NECK_Z,
                                   32, 18, skin(material_of)),
                      "skin", torso_weights))

    for side in (1.0, -1.0):
        tag = "l" if side > 0 else "r"
        a = ARM_TABLES[side]["a"]
        # The tube runs from inside the shoulder to the knuckles, where it
        # flattens into the palm the fingers grow out of: one shell, no hand
        # floating at the end of an arm.
        end_t = 1.36

        def arm_sample(u, v, side=side, a=a, end_t=end_t):
            t = -0.02 + (end_t + 0.02) * v
            theta = TAU * u
            centre, ry, rz = arm_axis(side, t)
            # Under the sleeve the arm has to stay inside it.
            if SLEEVE_FROM <= t <= SLEEVE_TO:
                room = sleeve_radius(t) - 0.010
                shrink = min(1.0, room / max(ry, rz))
                ry *= shrink
                rz *= shrink
            return centre + Vector((0.0, math.cos(theta) * ry, math.sin(theta) * rz))

        parts.append(Part(salvage.surface_grid(f"NAKED_Arm_{tag.upper()}", 16, 18, arm_sample,
                                               skin(material_of), cap_start=True, cap_end=True,
                                               axis=a),
                          "skin", arm_weights))

        digits = []
        for index in range(4):
            across = -0.030 + index * 0.020
            digits.append((
                [Vector((0.815 * side, 0.062 + across, 1.450)),
                 Vector((0.858 * side, 0.062 + across, 1.449)),
                 Vector((0.892 * side, 0.062 + across, 1.446))],
                [0.0115, 0.0100, 0.0070]))
        digits.append((
            [Vector((0.808 * side, 0.022, 1.438)),
             Vector((0.848 * side, 0.004, 1.418)),
             Vector((0.876 * side, -0.010, 1.402))],
            [0.0130, 0.0110, 0.0075]))
        hand = mobs.merge_tubes(f"NAKED_Fingers_{tag.upper()}", digits, 6,
                                skin(material_of), wobble=0.04, salt=3.0 + side)
        parts.append(Part(hand, "skin", lambda point, tag=tag: {f"hand_{tag}": 1.0}))

    # Shirt: one closed tube, its own profile 30 mm outside the skin's.
    parts.append(Part(radial_shell("NAKED_Shirt", SHIRT_PROFILE, SHIRT_HEM_Z, SHIRT_NECK_Z,
                                   32, 18, cloth(material_of), thickness=0.006),
                      "cloth", torso_weights, palette="shirt"))

    # Sleeves: tapered tubes off the arm axis, starting inside the shirt tube.
    for side in (1.0, -1.0):
        tag = "l" if side > 0 else "r"
        a = ARM_TABLES[side]["a"]

        def sleeve_sample(u, v, side=side):
            t = SLEEVE_FROM + (SLEEVE_TO - SLEEVE_FROM) * v
            centre, _ry, _rz = arm_axis(side, t)
            theta = TAU * u
            radius = sleeve_radius(t)
            return centre + Vector((0.0, math.cos(theta) * radius, math.sin(theta) * radius))

        parts.append(Part(salvage.surface_grid(f"NAKED_Sleeve_{tag.upper()}", 14, 8, sleeve_sample,
                                               cloth(material_of), thickness=0.006, cap_start=True,
                                               axis=a),
                          "cloth", arm_weights, palette="shirt"))

    # Collar: a band round the shirt's neckline, just proud of it.
    def collar_sample(u, v):
        theta = TAU * u
        z = COLLAR_Z[0] + (COLLAR_Z[1] - COLLAR_Z[0]) * v
        radius = mobs.keyed(z, SHIRT_PROFILE) + 0.011
        return Vector((math.cos(theta) * radius,
                       BODY_CENTRE_Y + math.sin(theta) * radius * BODY_ASPECT, z))

    parts.append(Part(salvage.surface_grid("NAKED_Collar", 24, 3, collar_sample,
                                           cloth(material_of), thickness=0.004,
                                           axis=Vector((0.0, BODY_CENTRE_Y, 1.55))),
                      "cloth", torso_weights, palette="trim"))

    print("NAKED_CHEST", "shoulder", tuple(round(v, 3) for v in mouth),
          "wrist", tuple(round(v, 3) for v in wrist))
    return parts


def clamp_inside_shorts(point: Vector, side: float) -> Vector:
    """Pull a skin vertex inside the shorts' own section, in the shorts' frame.

    The thigh is measured, the shorts are analytic, and their centres differ by
    a centimetre or two: clamping by radius alone still leaves the bare leg
    standing through the cloth.  This maps the point into each garment section
    and scales it back inside.
    """
    z = point.z
    x, y = point.x, point.y
    if SHORTS_LEG_Z[0] - 0.020 <= z <= SHORTS_LEG_Z[1]:
        share = min(1.0, max(0.0, (z - SHORTS_LEG_Z[0]) / (SHORTS_LEG_Z[1] - SHORTS_LEG_Z[0])))
        radius = SHORTS_LEG_RADIUS[1] + (SHORTS_LEG_RADIUS[0] - SHORTS_LEG_RADIUS[1]) * share
        cx, cy, aspect = side * 0.095, 0.045, 0.95
        dx, dy = x - cx, (y - cy) / aspect
        distance = math.hypot(dx, dy)
        limit = radius - 0.017
        if distance > limit > 0.0:
            scale = limit / distance
            x, y = cx + dx * scale, cy + dy * scale * aspect
    if SHORTS_HIP_Z[0] <= z <= SHORTS_HIP_Z[1]:
        share = (z - SHORTS_HIP_Z[0]) / (SHORTS_HIP_Z[1] - SHORTS_HIP_Z[0])
        radius = 0.196 + 0.010 * share
        aspect = 0.78
        cy = 0.020
        dx, dy = x, (y - cy) / aspect
        distance = math.hypot(dx, dy)
        limit = radius - 0.015
        if distance > limit > 0.0:
            scale = limit / distance
            x, y = dx * scale, cy + dy * scale * aspect
    return Vector((x, y, z))


def build_legs(material_of) -> list[Part]:
    """Legs and feet as skin, with tight shorts over the hips and thighs."""
    measure = MEASURE
    parts: list[Part] = []
    leg_refs = ["Male_Ranger_Legs", "Ranger_Base_Calf"]

    for side in (1.0, -1.0):
        tag = "l" if side > 0 else "r"
        x_range = (0.018, 0.340) if side > 0 else (-0.340, -0.018)
        leg_ring = measure.sector_table(leg_refs, LEG_BOTTOM, LEG_Z1, 0.012, sectors=28,
                                        x_range=x_range, half=0.016, smooth=1)
        # Ranger_Base_Calf is not part of any armour slot, so it is on screen
        # under every set: the bare leg has to sit outside it, not inside it.
        sock_ring = measure.sector_table(["Ranger_Base_Calf"], 0.090, 0.490, 0.012, sectors=28,
                                         x_range=x_range, half=0.016, smooth=1)

        def leg_sample(u, v, side=side, leg_ring=leg_ring, sock_ring=sock_ring):
            z = LEG_BOTTOM + (LEG_Z1 - LEG_BOTTOM) * v
            theta = TAU * u
            cx, cy, radius = leg_ring.ring(z, theta)
            inset = SOCK_INSET if z < 0.470 else LEG_INSET
            reach = max(0.018, radius - inset)
            # The ankle is the narrowest part of the leg and the foot's own
            # shell takes over below it, so the last two centimetres pull in to
            # the radius the foot's ankle ring already covers.
            share = 1.0 - mobs.smoothstep(LEG_BOTTOM, 0.235, z)
            reach += (ANKLE_RADIUS - reach) * share
            # Ranger_Base_Calf is never hidden by any slot, so it is on screen
            # under this set too: the bare leg has to be wider than it, and the
            # floor is applied after the ankle taper so the taper cannot dive
            # back inside the sock.
            if z < 0.620:
                reach = max(reach, sock_ring.ring(min(max(z, 0.093), 0.481), theta)[2] + 0.006)
            wobble = 1.0 + math.sin(theta * 2.0 + z * 6.0 + side) * 0.006
            point = Vector((cx + math.cos(theta) * reach * wobble,
                            cy + math.sin(theta) * reach * wobble, z))
            return clamp_inside_shorts(point, side)

        parts.append(Part(salvage.surface_grid(f"NAKED_Leg_{tag.upper()}", 18, 20, leg_sample,
                                               skin(material_of),
                                               axis=Vector((side * 0.09, 0.05, 0.60))),
                          "skin", leg_weights))

        ankle = max(sock_ring.ring(ANKLE_Z, step * TAU / 8.0)[2] for step in range(8)) + 0.006
        parts.append(Part(build_foot(side, ankle, material_of), "skin", foot_weights))

    # Shorts: a hip tube plus two leg tubes that start inside it.  Both are
    # surfaces of revolution, so nothing here can cross itself, and the leg
    # tubes are buried in the hip tube so the join cannot open a hole.
    def hip_sample(u, v):
        theta = TAU * u
        z = SHORTS_HIP_Z[0] + (SHORTS_HIP_Z[1] - SHORTS_HIP_Z[0]) * v
        radius = 0.196 + 0.010 * v
        return Vector((math.cos(theta) * radius, 0.020 + math.sin(theta) * radius * 0.78, z))

    parts.append(Part(salvage.surface_grid("NAKED_Shorts_Hip", 28, 4, hip_sample,
                                           cloth(material_of), thickness=0.006,
                                           axis=Vector((0.0, 0.02, 0.99))),
                      "cloth", shorts_weights, palette="shorts"))

    for side in (1.0, -1.0):
        tag = "l" if side > 0 else "r"

        def leg_short_sample(u, v, side=side):
            theta = TAU * u
            z = SHORTS_LEG_Z[0] + (SHORTS_LEG_Z[1] - SHORTS_LEG_Z[0]) * v
            radius = SHORTS_LEG_RADIUS[1] + (SHORTS_LEG_RADIUS[0] - SHORTS_LEG_RADIUS[1]) * v
            return Vector((side * 0.095 + math.cos(theta) * radius,
                           0.045 + math.sin(theta) * radius * 0.95, z))

        parts.append(Part(salvage.surface_grid(f"NAKED_Shorts_{tag.upper()}", 16, 5,
                                               leg_short_sample, cloth(material_of),
                                               thickness=0.006,
                                               axis=Vector((side * 0.095, 0.045, 0.85))),
                          "cloth", shorts_weights, palette="shorts"))

    return parts


def build_foot(side: float, ankle: float, material_of) -> bpy.types.Object:
    """A bare foot: the boot's footprint, shrunk to skin and closed at the ankle.

    Rings stack from the sole to the ankle.  At the sole each ring is the whole
    foot outline; as it rises it draws back and narrows until it is the ankle,
    which is why the leg tube above can taper into the same surface.  The
    ankle stub rises past the leg tube's bottom edge but stays inside it, so
    the two shells are one skin instead of a cuff over a stump.
    """
    centre_x = 0.0985 * side
    # measured on the ranger's boot: the sole outline it stands in
    sole_width, sole_length, sole_y = 0.050, 0.116, -0.032
    # the leg tube's own ankle section, so the two shells meet instead of
    # stepping; the stub above it is hidden inside the leg
    ankle_width, ankle_length, ankle_y = ankle, ankle * 1.08, 0.046
    stub_width, stub_length = ankle * 0.55, ankle * 0.60

    def ring(z: float) -> tuple[float, float, float]:
        low = mobs.smoothstep(FOOT_SOLE, ANKLE_Z, z)
        if z <= ANKLE_Z:
            share = low ** 0.62
            return (sole_width + (ankle_width - sole_width) * share,
                    sole_length + (ankle_length - sole_length) * share,
                    sole_y + (ankle_y - sole_y) * share)
        share = mobs.smoothstep(ANKLE_Z, FOOT_TOP, z)
        return (ankle_width + (stub_width - ankle_width) * share,
                ankle_length + (stub_length - ankle_length) * share,
                ankle_y)

    def arch(y: float) -> float:
        """The instep lifts off the ground between the heel pad and the ball."""
        span = max(1e-6, sole_length)
        across = (y - sole_y) / span + 0.30
        return 0.011 * math.exp(-((across / 0.42) ** 2))

    def foot_sample(u, v):
        z = FOOT_SOLE + (FOOT_TOP - FOOT_SOLE) * (0.5 - 0.5 * math.cos(math.pi * v))
        half_w, half_l, cy = ring(z)
        theta = TAU * u
        cosine, sine = math.cos(theta), math.sin(theta)
        exponent = 2.05
        # A superellipse outline keeps the toe box square-ish and the heel round.
        radius = 1.0 / max(1e-6, (abs(cosine / half_w) ** exponent
                                  + abs(sine / half_l) ** exponent) ** (1.0 / exponent))
        y = cy + sine * radius
        lift = arch(y) * (1.0 - mobs.smoothstep(FOOT_SOLE, 0.045, z))
        return Vector((centre_x + cosine * radius, y, z + lift))

    return salvage.surface_grid(f"NAKED_Foot_{'L' if side > 0 else 'R'}", 20, 11, foot_sample,
                                skin(material_of), cap_start=True, cap_end=True,
                                axis=Vector((centre_x, -0.02, 0.06)))


# ---------------------------------------------------------------------------
# UV atlas, provenance and bake


# How far below the exported atlas edge each surface is sampled.  A cloth cell
# covers about a metre of fabric, so sampling it at half edge puts one sample
# every 8 mm and anything finer aliases into blotches -- which is exactly how a
# washed linen turned into a camouflage print.  Cloth is therefore sampled at
# the exported edge; the skin field is smooth enough to be sampled at half.
SAMPLE_DIVISOR = {"skin": 2, "cloth": 1}


def allocate_cells(keys: list[tuple]) -> dict[tuple, tuple[float, float, float, float]]:
    """One atlas rectangle per (surface, palette, provenance) group."""
    layout: dict[tuple, tuple[float, float, float, float]] = {}
    margin = 0.010
    for surface in SURFACE_ORDER:
        group_keys = [key for key in keys if key[1] == surface]
        if not group_keys:
            continue
        grid = max(1, int(math.ceil(math.sqrt(len(group_keys)))))
        for order, key in enumerate(group_keys):
            column = order % grid
            row = order // grid
            layout[key] = (
                column / grid + margin,
                (column + 1) / grid - margin,
                row / grid + margin,
                (row + 1) / grid - margin,
            )
    return layout


def upsample(image: np.ndarray, factor: int) -> np.ndarray:
    """Bilinear stretch of an atlas sampled at a coarser grid."""
    squeeze = image.ndim == 2
    if squeeze:
        image = image[..., None]
    height, width = image.shape[:2]
    ys = (np.arange(height * factor) + 0.5) / factor - 0.5
    xs = (np.arange(width * factor) + 0.5) / factor - 0.5
    y0 = np.clip(np.floor(ys).astype(np.int64), 0, height - 1)
    y1 = np.clip(y0 + 1, 0, height - 1)
    x0 = np.clip(np.floor(xs).astype(np.int64), 0, width - 1)
    x1 = np.clip(x0 + 1, 0, width - 1)
    fy = np.clip(ys - y0, 0.0, 1.0)[:, None, None]
    fx = np.clip(xs - x0, 0.0, 1.0)[None, :, None]
    top = image[y0][:, x0] * (1.0 - fx) + image[y0][:, x1] * fx
    bottom = image[y1][:, x0] * (1.0 - fx) + image[y1][:, x1] * fx
    stretched = (top * (1.0 - fy) + bottom * fy).astype(np.float32)
    return stretched[..., 0] if squeeze else stretched


def uv_report(piece: bpy.types.Object) -> tuple[float, float]:
    """Total and largest triangle area in UV space: a packing sanity check."""
    uv = piece.data.uv_layers[0].data
    areas = []
    for polygon in piece.data.polygons:
        corners = [uv[loop].uv for loop in polygon.loop_indices]
        area = 0.0
        for index in range(1, len(corners) - 1):
            ax, ay = corners[0]
            bx, by = corners[index]
            cx, cy = corners[index + 1]
            area += abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5
        areas.append(area)
    return sum(areas), max(areas)


def bake_surface(surface: str, size: int, groups: list[dict]) -> None:
    """Rasterise one surface's groups into its atlas and build the material.

    The fields behind skin and grave cloth have nothing finer in them than a
    couple of millimetres, so the atlas is sampled at half the exported edge and
    stretched up: the texels are the same size either way, and the bake is four
    times cheaper.
    """
    divisor = int(SAMPLE_DIVISOR[surface])
    normal_strength = 0.30 if surface == "cloth" else 0.55
    grid = size // divisor
    albedo = np.zeros((grid * grid, 3), dtype=np.float32)
    height = np.zeros(grid * grid, dtype=np.float32)
    roughness = np.zeros(grid * grid, dtype=np.float32)
    covered = np.zeros(grid * grid, dtype=bool)
    texels = 0
    for group in groups:
        started = time.perf_counter()
        group_texels = 0
        for piece in group["pieces"]:
            chunks = mobs.triangle_texels(piece, 0, grid)
            if not chunks:
                continue
            flat = np.concatenate([chunk[0] for chunk in chunks])
            points = np.concatenate([chunk[1] for chunk in chunks])
            sampled = group["sampler"](points)
            height[flat] = np.clip(sampled["height"], 0.0, 1.0)
            group_albedo = np.clip(sampled["albedo"], 0.0, 1.0)
            albedo[flat] = group_albedo
            roughness[flat] = np.clip(sampled["roughness"], 0.0, 1.0)
            covered[flat] = True
            group_texels += int(flat.size)
            texels += int(flat.size)
            if group["surface"] == "cloth":
                value = group_albedo.mean(axis=1)
                print(f"NAKED_CLOTH {group['palette']} base={np.round(group_albedo.mean(axis=0), 3)} "
                      f"p5={float(np.percentile(value, 5)):.3f} "
                      f"p95={float(np.percentile(value, 95)):.3f} "
                      f"spread={float(np.percentile(value, 95) - np.percentile(value, 5)):.3f} "
                      f"rough={np.round(roughness[flat].mean(), 3)}", flush=True)
        print(f"NAKED_GRID {surface} {group['key'][0]}/{group['palette'] or 'skin'} "
              f"texels={group_texels} seconds={time.perf_counter() - started:.1f}", flush=True)
    if texels == 0:
        raise SystemExit(f"{surface}: nothing was baked")

    albedo = albedo.reshape(grid, grid, 3)
    height = height.reshape(grid, grid)
    roughness = roughness.reshape(grid, grid)
    coverage = covered.reshape(grid, grid)
    albedo = mobs.dilate(albedo, coverage.copy(), 4)
    # Height and roughness are smooth fields: they need a couple of texels of
    # bleed at the island edges, not the albedo's full margin.
    fields = mobs.dilate(np.stack([height, roughness, np.zeros_like(height)], axis=-1),
                         coverage.copy(), 2)
    height = fields[..., 0]
    roughness = fields[..., 1]
    normals = surfaces.normal_map(height, float(normal_strength))
    albedo = upsample(albedo, divisor)
    normals = upsample(np.clip(normals, 0.0, 1.0), divisor)
    roughness = upsample(roughness, divisor)
    prefix = MATERIAL_NAME[surface]
    images = {
        "albedo": mobs.new_image(prefix + "_albedo", size, albedo, False, TEXTURES),
        "normal": mobs.new_image(prefix + "_normal", size, normals, True, TEXTURES),
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
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.8
    # Skin scatters: a softer specular lobe than cloth's flat one.
    bsdf.inputs["Specular IOR Level"].default_value = 0.45 if surface == "skin" else 0.28
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
    normal_node.inputs["Strength"].default_value = 0.85 if surface == "skin" else 1.0
    links.new(normal_tex.outputs["Color"], normal_node.inputs["Color"])
    links.new(normal_node.outputs["Normal"], bsdf.inputs["Normal"])
    rough_tex = nodes.new("ShaderNodeTexImage")
    rough_tex.image = images["roughness"]
    rough_tex.location = (-900, -520)
    rough_tex.image.colorspace_settings.name = "Non-Color"
    links.new(rough_tex.outputs["Color"], bsdf.inputs["Roughness"])
    print("NAKED_BAKE", surface, "size", size, "texels", texels,
          "covered", int(np.count_nonzero(coverage)))


# ---------------------------------------------------------------------------
# Export + measured metadata


def reset_pose() -> None:
    if RIG.animation_data:
        RIG.animation_data.action = None
    for pose_bone in RIG.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def apply_action(action: bpy.types.Action | None, frame: int) -> None:
    if action is None:
        return
    if RIG.animation_data is None:
        RIG.animation_data_create()
    RIG.animation_data.action = action
    if getattr(action, "slots", None):
        RIG.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)
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


def image_bytes(document: dict, index: int) -> int:
    view = document["bufferViews"][document["images"][index]["bufferView"]]
    return int(view["byteLength"])


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
        bind = [piece.matrix_world @ vertex.co for vertex in piece.data.vertices]
        pieces_meta[piece.name] = {
            "slot": piece.name.split("_")[-1].lower(),
            "bones": used,
            "triangles": triangles,
            "bounds_min": [round(value, 5) for value in bounds_min],
            "bounds_max": [round(value, 5) for value in bounds_max],
            "bounds_bind_min": [round(min(point[axis] for point in bind), 5) for axis in range(3)],
            "bounds_bind_max": [round(max(point[axis] for point in bind), 5) for axis in range(3)],
            "vertices": sum(document["accessors"][primitive["attributes"]["POSITION"]]["count"]
                            for primitive in mesh["primitives"]),
        }
        total += triangles
    images = document.get("images", [])
    metadata = {
        "asset": OUTPUT.name,
        "set": "naked",
        "display": "Naked",
        "skeleton": "Armature/Skeleton3D",
        "bone_count": len(bones),
        "bone_names": bones,
        "slots": list(SLOTS),
        "pieces": pieces_meta,
        "total_triangles": total,
        "triangle_budget": TRIANGLE_BUDGET,
        "materials": [material.get("name", "") for material in document.get("materials", [])],
        "embedded_images": len(images),
        "image_mime_types": sorted({image.get("mimeType", "") for image in images}),
        "image_names": [image.get("name", "") for image in images],
        "image_bytes": {image.get("name", ""): image_bytes(document, index)
                        for index, image in enumerate(images)},
        "atlas_size": ATLAS_SIZE,
        "animations": [animation.get("name", "") for animation in document.get("animations", [])],
        "forward": [0, 0, 1],
        "up": [0, 1, 0],
        "bind_axes": "+X is the character's left, -Y forward, +Z up, metres",
        "unit": "metres",
        "rest_height": round(MEASURE.top_z(["Male_Ranger_Head_Hood"], (-1.0, 1.0),
                                           (-1.0, 1.0)), 5),
        "skin": {
            "source_materials": [SKIN_HEAD_MATERIAL, SKIN_HAND_MATERIAL],
            "shadow_srgb": [round(float(value), 4) for value in SKIN.shadow],
            "base_srgb": [round(float(value), 4) for value in SKIN.base],
            "light_srgb": [round(float(value), 4) for value in SKIN.light],
            "luminance_spread": round(SKIN.spread, 4),
            "roughness": round(SKIN.roughness, 4),
        },
        "clearance": clearance,
        "authoring_fps": FPS,
        "source": (
            "original procedural work authored by tools/prepare_naked_armor.py; hands are "
            "the Ranger's own palm and finger geometry from assets/characters/"
            "ironwood_ranger.glb; no third-party model or texture added"
        ),
        "reproducer": "python tools/build_naked_armor.py",
    }
    path = OUTPUT.with_suffix(".json")
    path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("NAKED_METADATA", path)
    return metadata


# ---------------------------------------------------------------------------
# Main


def build_groups(parts: list[Part], slot: str, layout: dict) -> list[dict]:
    """Split a slot's parts by (surface, palette) and unwrap each into its cell."""
    groups: list[dict] = []
    seen: dict[tuple, dict] = {}
    for part in parts:
        key = part.key(slot)
        group = seen.get(key)
        if group is None:
            group = {"key": key, "surface": part.surface, "palette": part.palette,
                     "pieces": [], "parts": [], "rect": layout[key]}
            seen[key] = group
            groups.append(group)
        group["pieces"].append(part.obj)
        group["parts"].append(part)
    for index, group in enumerate(groups):
        joined = salvage.join_slot(group["pieces"], f"NAKED_{slot}_{index}")
        group["pieces"] = [joined]
        salvage.unwrap_piece(joined, {0: group["rect"]})
        total, largest = uv_report(joined)
        cell = (group["rect"][1] - group["rect"][0]) * (group["rect"][3] - group["rect"][2])
        print(f"NAKED_UV {joined.name} cell={cell:.4f} uv_total={total:.4f} "
              f"uv_largest={largest:.5f} tris={len(joined.data.polygons)}", flush=True)
        if total > cell * 1.25:
            raise SystemExit(f"{joined.name}: UV islands overlap ({total:.4f} > {cell:.4f})")
    return groups


def main() -> None:
    global RIG, MEASURE, SKIN, IDLE_ACTION

    global START
    START = time.perf_counter()
    mobs.reset_scene()
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    TEXTURES.mkdir(parents=True, exist_ok=True)
    print("NAKED_BEGIN", RANGER)

    bpy.ops.import_scene.gltf(filepath=str(RANGER))
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if not rigs:
        raise SystemExit("ranger GLB contains no armature")
    RIG = rigs[0]
    IDLE_ACTION = next((action for action in bpy.data.actions if action.name == "Idle_Loop"), None)
    meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    MEASURE = salvage.Measure(RIG, meshes)
    reset_pose()
    set_creases()
    measure_arms()
    rig_bones = [bone.name for bone in RIG.data.bones]
    print("NAKED_RIG", RIG.name, "bones", len(rig_bones))

    SKIN = SkinSource()
    stamp("rig")

    materials = {}
    for surface in SURFACE_ORDER:
        material = bpy.data.materials.new(MATERIAL_NAME[surface])
        material.use_nodes = True
        materials[surface] = material

    def material_of(surface: str) -> bpy.types.Material:
        return materials[surface]

    claimed = {
        # The chest owns the torso, the arms and the hands: the ranger's own
        # arm mesh is chest geometry, so nothing else can carry the hands.
        # The palm of the copied hand is weighted to the forearm (the source
        # rigs the mitten that way and its fingers to the finger chains), so
        # hand_l/hand_r carry no vertices of this piece.
        "chest": ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01",
                  "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r",
                  "lowerarm_l", "lowerarm_r"],
        # The feet have to ride the legs: the feet slot is empty by contract.
        "legs": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r",
                 "foot_l", "foot_r", "ball_l", "ball_r"],
    }
    builders = {"chest": build_chest, "legs": build_legs}
    # The face, eyes and brows are on screen whatever the armour, so a shell
    # that pokes through them is a visible defect and fails the build.  The
    # torso is allowed to meet the jaw from below -- a neck emerging from its
    # shoulders -- so the chest gate starts above it.
    strict_floor = {"chest": 1.600}
    strict_refs = {
        "chest": ["Ranger_Head_SuperHero_Male", "Ranger_Head_Eyes", "Ranger_Head_Eyebrows"],
        "legs": [],
    }
    clearance_refs = {
        "chest": ["Ranger_Head_SuperHero_Male", "Ranger_Head_Eyes", "Ranger_Head_Eyebrows",
                  "Male_Ranger_Body", "Male_Ranger_Arms"],
        "legs": ["Male_Ranger_Legs", "Ranger_Base_Calf", "Male_Ranger_Feet_Boots"],
    }
    problems: list[str] = []
    clearance: dict = {"rest": {}, "layers": {}, "idle": {}}
    measured: list[dict] = []
    clearance_problems: list[str] = []
    pieces: list[bpy.types.Object] = []
    slot_parts: dict[str, list[Part]] = {}

    for slot in SLOTS:
        parts = builders[slot](material_of)
        slot_parts[slot] = parts
        if os.environ.get("NAKED_DEBUG_PARTS"):
            for part in parts:
                lo = [min(vertex.co[i] for vertex in part.obj.data.vertices) for i in range(3)]
                hi = [max(vertex.co[i] for vertex in part.obj.data.vertices) for i in range(3)]
                print("NAKED_PART", slot, part.obj.name,
                      "lo", [round(value, 3) for value in lo],
                      "hi", [round(value, 3) for value in hi])
        skin_parts = [part.obj.name for part in parts if part.surface == "skin"]
        cloth_parts = [part.obj for part in parts if part.surface == "cloth"]
        slot_problems, report = clearance_report([part.obj for part in parts],
                                                         clearance_refs[slot], "rest",
                                                         strict_refs[slot],
                                                         strict_floor.get(slot, -1.0e9))
        clearance["rest"][NODE_NAME[slot]] = report
        measured.extend(entry for part in report.values() for entry in part.values())
        clearance_problems.extend(slot_problems)
        if cloth_parts:
            # Cloth against the skin under it, reported rather than gated: a
            # set-in sleeve and a crotch are nested into the body on purpose,
            # so a crossing depth cannot be read as a defect on its own.  The
            # numbers are the evidence that the gaps are the widths claimed.
            _, layer_report = clearance_report(cloth_parts, skin_parts, "layers", [])
            clearance["layers"][NODE_NAME[slot]] = layer_report
            for entries in layer_report.values():
                measured.extend(entries.values())
        for part in parts:
            if part.weights is not None:
                assign_weights(part.obj, part.weights, smooth_iterations=2)

    stamp("pieces")
    keys = []
    for slot in SLOTS:
        for part in slot_parts[slot]:
            key = part.key(slot)
            if key not in keys:
                keys.append(key)
    layout = allocate_cells(keys)
    print("NAKED_LAYOUT", {str(key): [round(v, 3) for v in rect] for key, rect in layout.items()})

    # Groups stay separate until the atlas is baked: joining them into the slot
    # node deletes the objects, and the bake reads their meshes.
    slot_groups: dict[str, list[dict]] = {}
    all_groups: list[dict] = []
    for slot in SLOTS:
        groups = build_groups(slot_parts[slot], slot, layout)
        for group in groups:
            if group["surface"] == "cloth":
                look = CLOTH_LOOKS[group["palette"]]
                group["sampler"] = lambda pts, look=look: cloth_surface(look, pts)
            else:
                group["sampler"] = SKIN.body_field
            all_groups.append(group)
        slot_groups[slot] = groups

    stamp("groups")
    for surface in SURFACE_ORDER:
        surface_groups = [group for group in all_groups if group["surface"] == surface]
        if surface_groups:
            bake_surface(surface, int(ATLAS_SIZE[surface]), surface_groups)
    stamp("bake")

    for slot in SLOTS:
        joined = salvage.join_slot([group["pieces"][0] for group in slot_groups[slot]],
                                   NODE_NAME[slot])
        problems.extend(validate_piece(joined, claimed[slot]))
        triangles = sum(len(polygon.vertices) - 2 for polygon in joined.data.polygons)
        print("NAKED_PIECE", joined.name, "tris", triangles, "verts", len(joined.data.vertices),
              "groups", sorted(group.name for group in joined.vertex_groups))
        joined.parent = RIG
        joined.matrix_parent_inverse = Matrix.Identity(4)
        modifier = joined.modifiers.new("Armature", "ARMATURE")
        modifier.object = RIG
        modifier.use_vertex_groups = True
        pieces.append(joined)

    if problems:
        for problem in problems:
            print("NAKED_ERROR", problem)
        raise SystemExit("weight validation failed")

    total = sum(sum(len(polygon.vertices) - 2 for polygon in piece.data.polygons) for piece in pieces)
    print("NAKED_TRIS", total)
    if total > TRIANGLE_BUDGET:
        raise SystemExit(f"triangle budget exceeded: {total} > {TRIANGLE_BUDGET}")

    # Sole check: the naked figure stands on the same ground the boots did.
    soles = []
    for piece in pieces:
        if piece.name != NODE_NAME["legs"]:
            continue
        soles = [vertex.co.z for vertex in piece.data.vertices if vertex.co.z < 0.030]
    if soles:
        print("NAKED_SOLE", round(min(soles), 4), "count", len(soles))

    if IDLE_ACTION is not None:
        apply_action(IDLE_ACTION, int(0.25 * FPS))
        for piece in pieces:
            slot = piece.name.split("_")[-1].lower()
            idle_problems, report = clearance_report([piece], clearance_refs[slot], "idle",
                                                             strict_refs[slot],
                                                             strict_floor.get(slot, -1.0e9))
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
        "idle frame %d. Crossings with 'gated_refs' (the face, eyes and brows, which stay on "
        "screen) fail the build. 'layers' measures the cloth against the skin under it and is "
        "reported only: a set-in sleeve and a crotch are nested into the body by design, so "
        "depth alone cannot distinguish them from a clip. max_depth_mm is only meaningful "
        "within a few millimetres of a surface."
        % int(0.25 * FPS)
    )
    if clearance_problems:
        for problem in clearance_problems:
            print("NAKED_ERROR", problem)
        raise SystemExit("clearance validation failed")

    stamp("clearance")

    export(pieces)
    metadata = write_metadata(pieces, clearance)
    stamp("export")
    print("NAKED_DONE", json.dumps({
        "triangles": metadata["total_triangles"],
        "bones": metadata["bone_count"],
        "images": metadata["embedded_images"],
        "image_bytes": metadata["image_bytes"],
        "pieces": {name: meta["triangles"] for name, meta in metadata["pieces"].items()},
    }, indent=2))


if __name__ == "__main__":
    main()
