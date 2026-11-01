"""Author the Weeping Hollow's cave kit in Blender 5.1.

Usage (normally through ``python tools/build_cave_kit.py``)::

    blender --background --factory-startup --python-exit-code 1 \
        --python tools/prepare_cave_kit.py -- <source_dir> <out_dir> [<work_dir>]

``<source_dir>`` holds the pinned Poly Haven downloads (``.runtime/cave-source``,
one folder per asset, verified against ``tools/cave_kit_sources.py``);
``<out_dir>`` is ``assets/world/cave``; ``<work_dir>`` (default
``.runtime/cave-build``) receives intermediates and the preview render.

What it makes, all deterministic from ``SEED`` and the pinned scans:

* **Tileable rock sets** (``textures/cave_<set>_{albedo,normal,orh}.png``, 1024):
  each CC0 scan is read at 2k, averaged down in linear light, its broad blotches
  flattened so it tiles quietly over a cave wall, desaturated toward cave stone
  and normalised to one mean albedo, so the runtime's area tints decide the
  colour. ``albedo`` is sRGB RGB; ``normal`` is OpenGL (+Y green up); ``orh`` packs
  R = ambient occlusion, G = roughness, B = height (percentile-normalised), all
  linear data.
* **The formation kit** (``cave_formations.glb``): tall, squat and broken
  stalagmites, carrot and ribbed stalactites, a curtain, a floor-to-roof column,
  a flowstone mound, three breakdown boulders, a fallen slab and a talus pile.
  Every piece is sculpted twice from the same analytic fields - a dense
  high-detail surface (growth rings, drip flutes, fracture planes, pitting) and
  a low game mesh - and Cycles bakes base colour, tangent normals, roughness and
  occlusion from the high into one 2048 atlas. Lathe pieces get analytic
  cylindrical UVs; the rest are smart-projected into their atlas cells. Floor
  pieces stand on their origin (+Y up after export); hanging pieces hang from it.
* **Ambient fauna** (``cave_fauna.glb``): a bat (wings spread along +/-X for the
  runtime's flap shader), a rat, a cave spider and a moth, vertex-coloured, facing
  -Z in Godot.
* **A web** (``textures/cave_web.png``, 512 RGBA): radials, frame and a broken
  capture spiral built as curves and rendered orthographically in Cycles; white
  silk in alpha.

The manifest ``cave_kit.json`` records the sources (URL, SHA-256, authors), the
Blender version, every output's SHA-256 and the measured piece bounds.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
import time
import zlib
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cave_kit_sources as sources  # noqa: E402

SEED = 1100
TEX = 1024
ATLAS = 2048
ORM_SIZE = 1024
LUMA = np.array([0.2126, 0.7152, 0.0722])
INSET = 10.0 / ATLAS
SPACING = 9.0

# --- arguments and output ----------------------------------------------------------


def _args() -> tuple[Path, Path, Path]:
    argv = sys.argv
    if "--" not in argv:
        raise SystemExit("usage: blender --background --python tools/prepare_cave_kit.py -- <source_dir> <out_dir> [<work_dir>]")
    rest = argv[argv.index("--") + 1:]
    if len(rest) < 2:
        raise SystemExit("prepare_cave_kit: need <source_dir> <out_dir>")
    root = Path(__file__).resolve().parent.parent
    work = Path(rest[2]) if len(rest) > 2 else root / ".runtime" / "cave-build"
    return Path(rest[0]).resolve(), Path(rest[1]).resolve(), work.resolve()


def log(*parts) -> None:
    print("CAVE_KIT", *parts, flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path: Path, pixels: np.ndarray) -> None:
    """8-bit PNG, top row first, every row Paeth-filtered. Deterministic bytes."""
    if pixels.ndim == 2:
        pixels = pixels[..., None]
    height, width, channels = pixels.shape
    color_type = {1: 0, 3: 2, 4: 6}[channels]
    rows = np.ascontiguousarray(pixels.astype(np.uint8)).reshape(height, width * channels)
    data = rows.astype(np.int16)
    left = np.zeros_like(data)
    left[:, channels:] = data[:, :-channels]
    up = np.zeros_like(data)
    up[1:, :] = data[:-1, :]
    corner = np.zeros_like(data)
    corner[1:, channels:] = data[:-1, :-channels]
    guess = left + up - corner
    pa = np.abs(guess - left)
    pb = np.abs(guess - up)
    pc = np.abs(guess - corner)
    predicted = np.where((pa <= pb) & (pa <= pc), left, np.where(pb <= pc, up, corner))
    filtered = ((data - predicted) & 0xFF).astype(np.uint8)
    raw = np.concatenate([np.full((height, 1), 4, np.uint8), filtered], axis=1).tobytes()
    header = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(raw, 9)) + _chunk(b"IEND", b""))


def quantize(values: np.ndarray) -> np.ndarray:
    return np.clip(np.round(values * 255.0), 0, 255).astype(np.uint8)


def read_image(path: Path, channels: int) -> np.ndarray:
    """Raw stored values (no colour management), top row first, float64."""
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = "Non-Color"
    image.reload()
    width, height = image.size
    buffer = np.empty(width * height * 4, np.float32)
    image.pixels.foreach_get(buffer)
    bpy.data.images.remove(image)
    return buffer.reshape(height, width, 4)[::-1, :, :channels].astype(np.float64)


def image_pixels(image) -> np.ndarray:
    width, height = image.size
    buffer = np.empty(width * height * 4, np.float32)
    image.pixels.foreach_get(buffer)
    return buffer.reshape(height, width, 4)[::-1].astype(np.float64)


def to_linear(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def half(a: np.ndarray) -> np.ndarray:
    h, w = a.shape[:2]
    rest = a.shape[2:]
    return a.reshape(h // 2, 2, w // 2, 2, *rest).mean(axis=(1, 3))


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Periodic Gaussian blur: a tileable map stays tileable."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    kernel = np.exp(-2.0 * (math.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


# --- 1. tileable rock sets ------------------------------------------------------------

SETS = [
    # id, scan, saturation kept, mean linear albedo, how much broad blotching is
    # flattened away, normal strength, roughness bias, colour cast.
    {"id": "limestone", "source": "rock_face_03", "saturation": 0.62, "value": 0.23, "flatten": 0.7,
        "normal": 1.15, "rough_bias": 0.02, "cast": (1.0, 0.985, 0.95)},
    {"id": "strata", "source": "cliff_side", "saturation": 0.40, "value": 0.21, "flatten": 0.5,
        "normal": 1.0, "rough_bias": 0.0, "cast": (1.0, 0.97, 0.93)},
    {"id": "basalt", "source": "dark_rock_02", "saturation": 0.75, "value": 0.105, "flatten": 0.55,
        "normal": 1.05, "rough_bias": -0.04, "cast": (0.97, 0.99, 1.0)},
    {"id": "silt", "source": "rocks_ground_08", "saturation": 0.70, "value": 0.15, "flatten": 0.6,
        "normal": 1.0, "rough_bias": 0.0, "cast": (1.0, 0.98, 0.95)},
]


def build_sets(source_dir: Path, out_dir: Path, report: dict) -> None:
    tex_dir = out_dir / "textures"
    for spec in SETS:
        asset = spec["source"]
        folder = source_dir / asset

        def path(kind: str) -> Path:
            return folder / sources.local_name(asset, kind)

        diffuse = half(to_linear(read_image(path("diff"), 3)))
        normal = half(read_image(path("nor_gl"), 3) * 2.0 - 1.0)
        rough = half(read_image(path("rough"), 1)[..., 0])
        occlusion = half(read_image(path("ao"), 1)[..., 0])
        height = half(read_image(path("disp"), 1)[..., 0])
        # Albedo: flatten the scan's broad light/dark blotches (they are what makes
        # a tiled wall read as a repeating photograph), pull the colour toward cave
        # stone and normalise the mean so every set answers a tint the same way.
        luma = diffuse @ LUMA
        broad = blur(luma, TEX / 9.0)
        gain = (broad.mean() / np.maximum(broad, 1e-5)) ** spec["flatten"]
        flat = diffuse * gain[..., None]
        luma = flat @ LUMA
        colour = luma[..., None] + (flat - luma[..., None]) * spec["saturation"]
        colour = colour * np.array(spec["cast"])
        colour = colour * (spec["value"] / max(float((colour @ LUMA).mean()), 1e-5))
        albedo = quantize(to_srgb(colour))
        # Normal: renormalised after the average, scaled in xy for strength.
        normal[..., :2] *= spec["normal"]
        normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-6)
        normal_png = quantize(normal * 0.5 + 0.5)
        low, high = np.percentile(height, [1.0, 99.0])
        height = np.clip((height - low) / max(high - low, 1e-6), 0.0, 1.0)
        rough = np.clip(rough + spec["rough_bias"], 0.04, 1.0)
        orh = quantize(np.stack([occlusion, rough, height], axis=-1))
        files = {}
        for kind, pixels in (("albedo", albedo), ("normal", normal_png), ("orh", orh)):
            target = tex_dir / f"cave_{spec['id']}_{kind}.png"
            write_png(target, pixels)
            files[kind] = {"file": f"textures/{target.name}", "size": TEX, "sha256": sha256(target)}
        report["sets"][spec["id"]] = {
            "source": asset,
            "metres": sources.ASSETS[asset]["metres"],
            "mean_albedo_linear": round(float((to_linear(albedo / 255.0) @ LUMA).mean()), 4),
            "mean_roughness": round(float(rough.mean()), 3),
            "files": files,
        }
        log("set", spec["id"], asset, "mean", report["sets"][spec["id"]]["mean_albedo_linear"])


# --- noise ------------------------------------------------------------------------------


class Perlin:
    """Vectorised 3D gradient noise in about [-1, 1], seeded and platform-stable."""

    GRAD = np.array([[1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0], [1, 0, 1], [-1, 0, 1],
        [1, 0, -1], [-1, 0, -1], [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1]], np.float64)

    def __init__(self, seed: int) -> None:
        order = np.random.default_rng(seed).permutation(256)
        self.perm = np.concatenate([order, order]).astype(np.int64)

    def __call__(self, x, y, z) -> np.ndarray:
        x = np.asarray(x, np.float64)
        y = np.asarray(y, np.float64)
        z = np.asarray(z, np.float64)
        fx, fy, fz = np.floor(x), np.floor(y), np.floor(z)
        xf, yf, zf = x - fx, y - fy, z - fz
        X = fx.astype(np.int64) & 255
        Y = fy.astype(np.int64) & 255
        Z = fz.astype(np.int64) & 255
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
        p = self.perm
        A = p[X] + Y
        B = p[X + 1] + Y
        AA, AB = p[A] + Z, p[A + 1] + Z
        BA, BB = p[B] + Z, p[B + 1] + Z

        def g(h, dx, dy, dz):
            gr = self.GRAD[p[h] % 12]
            return gr[..., 0] * dx + gr[..., 1] * dy + gr[..., 2] * dz

        lerp = lambda a, b, t: a + (b - a) * t  # noqa: E731
        x1 = lerp(g(AA, xf, yf, zf), g(BA, xf - 1, yf, zf), u)
        x2 = lerp(g(AB, xf, yf - 1, zf), g(BB, xf - 1, yf - 1, zf), u)
        x3 = lerp(g(AA + 1, xf, yf, zf - 1), g(BA + 1, xf - 1, yf, zf - 1), u)
        x4 = lerp(g(AB + 1, xf, yf - 1, zf - 1), g(BB + 1, xf - 1, yf - 1, zf - 1), u)
        return lerp(lerp(x1, x2, v), lerp(x3, x4, v), w)


NOISE = Perlin(SEED)


def fbm(x, y, z, octaves: int = 4, gain: float = 0.5, salt: float = 0.0) -> np.ndarray:
    total = 0.0
    norm = 0.0
    amplitude = 1.0
    frequency = 1.0
    for octave in range(octaves):
        o = salt + octave * 19.31
        total = total + amplitude * NOISE(x * frequency + o, y * frequency - o * 0.7, z * frequency + o * 1.3)
        norm += amplitude
        amplitude *= gain
        frequency *= 2.03
    return total / norm


# --- 2. scene helpers --------------------------------------------------------------------


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    world = bpy.data.worlds.new("CaveWorld")
    scene.world = world
    world.color = (0.05, 0.05, 0.05)
    world.light_settings.distance = 0.45


def mesh_object(name: str, verts: np.ndarray, faces: list, uvs: np.ndarray | None = None,
        smooth: bool = True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts.tolist()], [], faces)
    if uvs is not None:
        layer = mesh.uv_layers.new(name="UVMap")
        loops = np.empty(len(mesh.loops), np.int64)
        mesh.loops.foreach_get("vertex_index", loops)
        layer.data.foreach_set("uv", uvs[loops].astype(np.float32).ravel())
    mesh.validate()
    mesh.update()
    if smooth:
        mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bm_object(name: str, bm, smooth: bool = True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if smooth:
        mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def select_only(objects, active) -> None:
    bpy.context.view_layer.update()
    for obj in bpy.context.scene.objects:
        if obj is not None:
            obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active


def socket(sockets, identifier: str):
    for item in sockets:
        if item.identifier == identifier:
            return item
    raise KeyError(identifier)


def triangles(obj) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


# --- 3. the formation kit -----------------------------------------------------------------


def lathe(n_seg: int, n_ring: int, field, tip: bool, cell, hanging: bool = False):
    """A surface of revolution. `field(T, TH, high)` returns radius and height
    arrays; θ-periodic detail keeps the seam closed. Returns verts, faces, uvs."""
    t = np.linspace(0.0, 1.0, n_ring + 1)
    th = np.linspace(0.0, 2.0 * math.pi, n_seg + 1)
    T, TH = np.meshgrid(t, th, indexing="ij")
    R, Z = field(T, TH)
    R = np.maximum(R, 0.0)
    X = R * np.cos(TH)
    Y = R * np.sin(TH)
    # The seam column repeats the first so UVs can run 0..1.
    X[:, -1], Y[:, -1], Z[:, -1] = X[:, 0], Y[:, 0], Z[:, 0]
    rings = n_ring if tip else n_ring + 1
    cols = n_seg + 1
    verts = np.stack([X[:rings], Y[:rings], Z[:rings]], axis=-1).reshape(-1, 3)
    u0, v0, u1, v1 = cell
    uv = np.stack([u0 + INSET + (u1 - u0 - 2 * INSET) * (TH[:rings] / (2 * math.pi)),
        v0 + INSET + (v1 - v0 - 2 * INSET) * T[:rings]], axis=-1).reshape(-1, 2)
    faces = []
    for j in range(rings - 1):
        for i in range(n_seg):
            a = j * cols + i
            faces.append((a, a + 1, a + cols + 1, a + cols))
    if tip:
        tip_index = len(verts)
        verts = np.vstack([verts, [[0.0, 0.0, float(Z[-1, 0])]]])
        uv = np.vstack([uv, [[u0 + (u1 - u0) * 0.5, v1 - INSET]]])
        j = rings - 1
        for i in range(n_seg):
            a = j * cols + i
            faces.append((a, a + 1, tip_index))
    if hanging:
        faces = [tuple(reversed(f)) for f in faces]
    return verts, faces, uv


def _cyl(TH, Z, radius):
    return np.cos(TH) * radius, np.sin(TH) * radius, Z


def _round_cap(T, start):
    return np.where(T > start, np.sqrt(np.clip(1.0 - ((T - start) / (1.0 - start)) ** 2, 0.0, 1.0)), 1.0)


def stalagmite_tall(high: bool):
    def field(T, TH):
        R0, H = 0.30, 2.4
        Z = -0.06 + T * (H + 0.06)
        r = R0 * (0.30 + 0.70 * (1 - T) ** 1.5) * (1 + 0.65 * (1 - T) ** 14) * _round_cap(T, 0.86)
        px, py, pz = _cyl(TH, Z, R0)
        detail = 0.10 * fbm(px * 2.2, py * 2.2, pz * 1.4, 3, salt=1.0)
        if high:
            rings = 0.014 * (0.5 + 0.5 * np.sin(2 * math.pi * (T * 17 + 1.4 * fbm(px * 3, py * 3, pz * 3, 2, salt=2.0)))) ** 2
            flutes = 0.075 * (np.abs(np.sin(5 * TH + 2.2 * fbm(px * 1.5, py * 1.5, pz * 0.8, 2, salt=3.0))) ** 0.6 - 0.62) * (1 - T) ** 0.6
            fine = 0.04 * fbm(px * 9, py * 9, pz * 9, 3, salt=4.0) + 0.014 * fbm(px * 30, py * 30, pz * 30, 2, salt=5.0)
            detail = detail + rings + flutes + fine
        return r * (1 + detail), Z
    return field


def stalagmite_squat(high: bool):
    def field(T, TH):
        R0, H = 0.46, 1.05
        Z = -0.06 + T * (H + 0.06)
        r = R0 * (1 - T ** 1.7) ** 0.75 * (1 + 0.5 * (1 - T) ** 10) * _round_cap(T, 0.8)
        r = r + 0.04 * R0 * _round_cap(T, 0.97)
        px, py, pz = _cyl(TH, Z, R0)
        detail = 0.12 * fbm(px * 2.0, py * 2.0, pz * 1.6, 3, salt=11.0)
        if high:
            rings = 0.016 * (0.5 + 0.5 * np.sin(2 * math.pi * (T * 11 + 1.5 * fbm(px * 2, py * 2, pz * 2, 2, salt=12.0)))) ** 2
            flutes = 0.09 * (np.abs(np.sin(4 * TH + 1.8 * fbm(px, py, pz, 2, salt=13.0))) ** 0.5 - 0.65) * (1 - T) ** 0.4
            fine = 0.045 * fbm(px * 8, py * 8, pz * 8, 3, salt=14.0) + 0.015 * fbm(px * 26, py * 26, pz * 26, 2, salt=15.0)
            detail = detail + rings + flutes + fine
        return r * (1 + detail), Z
    return field


def stalagmite_stump(high: bool):
    def field(T, TH):
        R0, H = 0.36, 0.85
        px, py, _ = _cyl(TH, T, R0)
        # A snapped top: the last tenth closes over a broken, uneven face.
        jag = 0.08 * fbm(px * 5, py * 5, np.zeros_like(px), 3, salt=21.0)
        Z = np.where(T > 0.9, H * (0.94 + (T - 0.9) * 0.4) + jag * (T - 0.9) * 10, -0.06 + T / 0.9 * (H * 0.94 + 0.06))
        r = R0 * (0.78 + 0.22 * (1 - T) ** 2) * (1 + 0.5 * (1 - T) ** 12)
        r = np.where(T > 0.9, r * np.clip((1.0 - T) / 0.1, 0.0, 1.0) ** 0.6, r)
        pz = Z
        detail = 0.10 * fbm(px * 2.4, py * 2.4, pz * 1.8, 3, salt=22.0)
        if high:
            rings = 0.015 * (0.5 + 0.5 * np.sin(2 * math.pi * (T * 9 + 1.5 * fbm(px * 2, py * 2, pz * 2, 2, salt=23.0)))) ** 2
            fine = 0.05 * fbm(px * 10, py * 10, pz * 10, 3, salt=24.0) + 0.02 * fbm(px * 32, py * 32, pz * 32, 2, salt=25.0)
            detail = detail + rings + fine
        return r * (1 + detail), Z
    return field


def stalactite_carrot(high: bool):
    def field(T, TH):
        R0, L = 0.24, 1.7
        Z = 0.08 - T * (L + 0.08)
        r = R0 * (1 - T) ** 1.35 * (1 + 0.7 * (1 - T) ** 16) + 0.016 * np.exp(-((T - 0.985) / 0.012) ** 2)
        px, py, pz = _cyl(TH, Z, R0)
        detail = 0.10 * fbm(px * 2.5, py * 2.5, pz * 1.2, 3, salt=31.0)
        if high:
            ridges = 0.08 * (np.abs(np.sin(4 * TH + 1.6 * fbm(px, py, pz * 0.6, 2, salt=32.0))) ** 0.7 - 0.6)
            ripples = 0.01 * np.sin(2 * math.pi * (T * 34 + 1.2 * fbm(px * 4, py * 4, pz * 4, 2, salt=33.0)))
            fine = 0.03 * fbm(px * 12, py * 12, pz * 12, 3, salt=34.0)
            detail = detail + ridges + ripples + fine
        return r * (1 + detail), Z
    return field


def stalactite_ribbed(high: bool):
    def field(T, TH):
        R0, L = 0.34, 0.95
        Z = 0.08 - T * (L + 0.08)
        r = R0 * (1 - T) ** 0.85 * (1 + 0.5 * (1 - T) ** 12) * _round_cap(T, 0.88)
        px, py, pz = _cyl(TH, Z, R0)
        ribs = 0.11 * (np.abs(np.sin(5 * TH + 1.2 * fbm(px, py, pz, 2, salt=41.0))) ** 1.5 - 0.4)
        detail = ribs * (0.55 if not high else 1.0) + 0.08 * fbm(px * 2.5, py * 2.5, pz * 2, 3, salt=42.0)
        if high:
            fine = 0.04 * fbm(px * 10, py * 10, pz * 10, 3, salt=43.0) + 0.008 * np.sin(2 * math.pi * T * 26)
            detail = detail + fine
        return r * (1 + detail), Z
    return field


def column_field(high: bool):
    def field(T, TH):
        H = 6.0
        Z = -0.1 + T * (H + 0.2)
        r = (0.40 + 0.62 * (1 - T) ** 5 + 0.52 * T ** 6
            + 0.09 * np.exp(-((T - 0.34) / 0.05) ** 2) + 0.07 * np.exp(-((T - 0.63) / 0.04) ** 2))
        px, py, pz = _cyl(TH, Z, 0.6)
        detail = 0.09 * fbm(px * 1.6, py * 1.6, pz * 0.7, 3, salt=51.0)
        if high:
            flutes = 0.07 * (np.abs(np.sin(5 * TH + 2.0 * fbm(px, py, pz * 0.4, 2, salt=52.0))) ** 0.6 - 0.62)
            rings = 0.012 * (0.5 + 0.5 * np.sin(2 * math.pi * (T * 40 + 1.5 * fbm(px * 2, py * 2, pz * 2, 2, salt=53.0)))) ** 2
            fine = 0.035 * fbm(px * 7, py * 7, pz * 7, 3, salt=54.0) + 0.012 * fbm(px * 24, py * 24, pz * 24, 2, salt=55.0)
            detail = detail + flutes + rings + fine
        return r * (1 + detail), Z
    return field


def flowstone_field(high: bool):
    def field(T, TH):
        R0, H = 1.0, 0.75
        s = 1.0 - T
        Z = -0.08 + (H + 0.08) * (1.0 - s ** 2) ** 0.8
        px, py, pz = _cyl(TH, Z, R0)
        lobes = 0.16 * np.sin(4 * TH + 1.3 * fbm(px, py, 0 * pz, 2, salt=61.0)) * s ** 0.5
        r = R0 * s ** 0.55 * (1 + lobes) * (1 + 0.1 * fbm(px * 1.8, py * 1.8, pz * 1.8, 3, salt=62.0))
        if high:
            ridges = 0.03 * np.sin(26 * TH + 4 * fbm(px * 1.5, py * 1.5, pz, 2, salt=63.0)) * s
            r = r * (1 + ridges + 0.03 * fbm(px * 9, py * 9, pz * 9, 3, salt=64.0))
            Z = Z + 0.03 * np.sin(T * 24 + 2 * fbm(px, py, pz, 2, salt=65.0)) * s
        return r, Z
    return field


def curtain_mesh(n_s: int, n_t: int, high: bool, cell):
    """A hanging drapery: a folded sheet, scalloped along its lower edge, thick at
    the roof and thinning toward the drip line."""
    W, H = 2.0, 1.4
    s = np.linspace(0.0, 1.0, n_s + 1)
    t = np.linspace(0.0, 1.0, n_t + 1)
    S, T = np.meshgrid(s, t, indexing="ij")
    fold = 0.16 * np.sin(2 * math.pi * (S * 3.2 + 0.15)) + 0.07 * np.sin(2 * math.pi * (S * 7.1 + 0.4))
    dfold = (0.16 * 2 * math.pi * 3.2 * np.cos(2 * math.pi * (S * 3.2 + 0.15))
        + 0.07 * 2 * math.pi * 7.1 * np.cos(2 * math.pi * (S * 7.1 + 0.4))) / W
    ends = np.clip(np.minimum(S, 1.0 - S) / 0.14, 0.0, 1.0) ** 0.7
    scallop = 0.5 + 0.5 * np.cos(2 * math.pi * S * 4.0 + 0.6 * np.sin(2 * math.pi * S * 1.7))
    length = H * (0.42 + 0.58 * scallop) * (0.35 + 0.65 * ends)
    X = (S - 0.5) * W
    Y = fold * (0.55 + 0.45 * T)
    Z = 0.06 - T * (length + 0.06)
    if high:
        Y = Y + 0.012 * np.sin(70 * S + 3 * fbm(X, Z, 0 * X, 2, salt=71.0)) + 0.02 * fbm(X * 6, Z * 6, 0 * X, 3, salt=72.0)
    thick = 0.075 * (1 - T) + 0.022
    nx = -dfold * (0.55 + 0.45 * T)
    ny = np.ones_like(nx)
    nl = np.sqrt(nx * nx + ny * ny)
    nx, ny = nx / nl, ny / nl
    front = np.stack([X + nx * thick * 0.5, Y + ny * thick * 0.5, Z], axis=-1)
    back = np.stack([X - nx * thick * 0.5, Y - ny * thick * 0.5, Z], axis=-1)
    rows = n_t + 1
    count = (n_s + 1) * rows
    verts = np.vstack([front.reshape(-1, 3), back.reshape(-1, 3)])
    u0, v0, u1, v1 = cell
    um = (u0 + u1) * 0.5
    uf = np.stack([u0 + INSET + (um - u0 - 2 * INSET) * S, v0 + INSET + (v1 - v0 - 2 * INSET) * T], axis=-1).reshape(-1, 2)
    ub = np.stack([um + INSET + (u1 - um - 2 * INSET) * S, v0 + INSET + (v1 - v0 - 2 * INSET) * T], axis=-1).reshape(-1, 2)
    uvs = np.vstack([uf, ub])
    faces = []
    for i in range(n_s):
        for j in range(n_t):
            a = i * rows + j
            faces.append((a, a + rows, a + rows + 1, a + 1))
            b = count + a
            faces.append((b, b + 1, b + rows + 1, b + rows))
    # The drip line and the two ends close the sheet.
    for i in range(n_s):
        a = i * rows + n_t
        faces.append((a, count + a, count + a + rows, a + rows))
    for j in range(n_t):
        a = j
        faces.append((a, a + 1, count + a + 1, count + a))
        a = n_s * rows + j
        faces.append((a, count + a, count + a + 1, a + 1))
    return verts, faces, uvs


def boulder_points(subdiv: int, seed: int, squash, fractures: int, high: bool):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    dirs = np.array([v.co[:] for v in bm.verts])
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    off = seed * 0.731
    broad = 0.30 * fbm(dirs[:, 0] * 1.3 + off, dirs[:, 1] * 1.3 - off, dirs[:, 2] * 1.3 + off * 0.5, 3, salt=seed)
    points = dirs * (1.0 + broad)[:, None] * np.array(squash)
    # The fracture planes come from a fixed dense sampling, so the low mesh and the
    # high mesh share every plane.
    probe = np.random.default_rng(seed).normal(size=(4000, 3))
    probe /= np.linalg.norm(probe, axis=1, keepdims=True)
    probe_broad = 0.30 * fbm(probe[:, 0] * 1.3 + off, probe[:, 1] * 1.3 - off, probe[:, 2] * 1.3 + off * 0.5, 3, salt=seed)
    probe_points = probe * (1.0 + probe_broad)[:, None] * np.array(squash)
    rng = np.random.default_rng(seed + 7)
    planes = []
    for _ in range(fractures):
        n = np.array([rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.45, 0.6)])
        n /= np.linalg.norm(n)
        reach = float((probe_points @ n).max())
        planes.append((n, reach * rng.uniform(0.7, 0.86)))
    if high:
        fine = (0.06 * fbm(dirs[:, 0] * 5 + off, dirs[:, 1] * 5, dirs[:, 2] * 5 - off, 3, salt=seed + 1)
            + 0.02 * fbm(dirs[:, 0] * 16, dirs[:, 1] * 16 + off, dirs[:, 2] * 16, 2, salt=seed + 2))
        points = points + dirs * fine[:, None]
    for n, plane in planes:
        depth = points @ n - plane
        cut = depth > 0
        points[cut] -= np.outer(depth[cut], n) * 0.97
        if high:
            # A broken face is not flat either: a shallow, irregular undulation.
            wave = points[cut] * 7.0
            ripple = 0.01 * fbm(wave[:, 0], wave[:, 1], wave[:, 2], 2, salt=seed + 3)
            points[cut] += np.outer(ripple, n)
    for index, vert in enumerate(bm.verts):
        vert.co = Vector(points[index])
    return bm


def boulder_object(name: str, subdiv: int, seed: int, squash, fractures: int, high: bool, scale: float):
    bm = boulder_points(subdiv, seed, squash, fractures, high)
    bmesh.ops.scale(bm, vec=Vector((scale, scale, scale)), verts=bm.verts)
    low_z = min(v.co.z for v in bm.verts)
    top_z = max(v.co.z for v in bm.verts)
    # Sit it in the floor: a sixth of its height is under the ground.
    lift = -low_z - (top_z - low_z) * 0.16
    bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, lift)), verts=bm.verts)
    return bm_object(name, bm)


def rubble_object(name: str, high: bool):
    bm = bmesh.new()
    rng = np.random.default_rng(SEED + 909)
    for index in range(11):
        piece = boulder_points(5 if high else 2, 900 + index * 13, (1.0, 0.9, 0.7), 2, high)
        size = rng.uniform(0.12, 0.3)
        angle = rng.uniform(0, 2 * math.pi)
        reach = rng.uniform(0.0, 0.75) * (1.0 if index > 2 else 0.4)
        at = Vector((math.cos(angle) * reach, math.sin(angle) * reach, size * 0.25 + 0.12 * (1 - reach / 0.75)))
        mat = Matrix.Translation(at) @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z") @ Matrix.Rotation(rng.uniform(-0.5, 0.5), 4, "X") \
            @ Matrix.Diagonal((size, size, size, 1.0))
        temp = bpy.data.meshes.new("rubble_temp")
        piece.to_mesh(temp)
        piece.free()
        temp.transform(mat)
        bm.from_mesh(temp)
        bpy.data.meshes.remove(temp)
    # The grit the stones lie in: a low mound.
    rings, segs = (24, 64) if high else (5, 14)
    centre = bm.verts.new((0.0, 0.0, 0.17))
    ring_verts = []
    for j in range(1, rings + 1):
        row = []
        rr = j / rings
        for i in range(segs):
            a = 2 * math.pi * i / segs
            x, y = math.cos(a) * rr * 1.0, math.sin(a) * rr * 0.85
            z = 0.17 * (1 - rr ** 2) - 0.04
            if high:
                z += 0.025 * float(fbm(np.array(x * 6), np.array(y * 6), np.array(0.0), 3, salt=990.0))
            row.append(bm.verts.new((x, y, z)))
        ring_verts.append(row)
    for i in range(segs):
        bm.faces.new((centre, ring_verts[0][i], ring_verts[0][(i + 1) % segs]))
    for j in range(rings - 1):
        for i in range(segs):
            bm.faces.new((ring_verts[j][i], ring_verts[j + 1][i], ring_verts[j + 1][(i + 1) % segs], ring_verts[j][(i + 1) % segs]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm_object(name, bm)


def smart_uv(obj, cell) -> None:
    select_only([obj], obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(62.0), island_margin=0.02, correct_aspect=True,
        scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.012)
    bpy.ops.object.mode_set(mode="OBJECT")
    u0, v0, u1, v1 = cell
    layer = obj.data.uv_layers.active
    uv = np.empty(len(layer.data) * 2, np.float32)
    layer.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    uv[:, 0] = u0 + INSET + (u1 - u0 - 2 * INSET) * uv[:, 0]
    uv[:, 1] = v0 + INSET + (v1 - v0 - 2 * INSET) * uv[:, 1]
    layer.data.foreach_set("uv", uv.ravel())


# Atlas cells, (u0, v0, u1, v1) with v up from the image's bottom edge.
PIECES = [
    {"name": "StalagmiteTall", "kind": "lathe", "field": stalagmite_tall, "low": (12, 18), "high": (160, 280),
        "tip": True, "cell": (0.0, 0.0, 0.25, 0.5), "anchor": "floor", "style": "flowstone"},
    {"name": "StalagmiteSquat", "kind": "lathe", "field": stalagmite_squat, "low": (12, 12), "high": (160, 180),
        "tip": True, "cell": (0.25, 0.0, 0.5, 0.25), "anchor": "floor", "style": "flowstone"},
    {"name": "StalagmiteStump", "kind": "lathe", "field": stalagmite_stump, "low": (12, 12), "high": (160, 180),
        "tip": True, "cell": (0.25, 0.25, 0.5, 0.5), "anchor": "floor", "style": "flowstone"},
    {"name": "StalactiteCarrot", "kind": "lathe", "field": stalactite_carrot, "low": (10, 16), "high": (128, 260),
        "tip": True, "cell": (0.5, 0.0, 0.625, 0.5), "anchor": "roof", "style": "flowstone", "hanging": True},
    {"name": "StalactiteRibbed", "kind": "lathe", "field": stalactite_ribbed, "low": (12, 10), "high": (160, 160),
        "tip": True, "cell": (0.625, 0.0, 0.75, 0.25), "anchor": "roof", "style": "flowstone", "hanging": True},
    {"name": "Curtain", "kind": "curtain", "low": (22, 7), "high": (320, 120),
        "cell": (0.75, 0.0, 1.0, 0.25), "anchor": "roof", "style": "flowstone"},
    {"name": "Flowstone", "kind": "lathe", "field": flowstone_field, "low": (16, 8), "high": (220, 120),
        "tip": True, "cell": (0.625, 0.25, 1.0, 0.5), "anchor": "floor", "style": "flowstone", "oval": (1.25, 0.8)},
    {"name": "Column", "kind": "lathe", "field": column_field, "low": (16, 28), "high": (180, 380),
        "tip": False, "cell": (0.0, 0.5, 0.25, 1.0), "anchor": "floor", "style": "flowstone"},
    {"name": "BoulderA", "kind": "boulder", "seed": 1201, "squash": (1.15, 0.95, 0.75), "fractures": 6, "scale": 0.8,
        "cell": (0.25, 0.5, 0.5, 0.75), "anchor": "floor", "style": "breakdown"},
    {"name": "BoulderB", "kind": "boulder", "seed": 1307, "squash": (1.0, 1.1, 0.85), "fractures": 6, "scale": 0.75,
        "cell": (0.5, 0.5, 0.75, 0.75), "anchor": "floor", "style": "breakdown"},
    {"name": "BoulderC", "kind": "boulder", "seed": 1409, "squash": (1.3, 0.8, 0.62), "fractures": 5, "scale": 0.8,
        "cell": (0.75, 0.5, 1.0, 0.75), "anchor": "floor", "style": "breakdown"},
    {"name": "Slab", "kind": "boulder", "seed": 1511, "squash": (1.45, 1.1, 0.34), "fractures": 6, "scale": 0.85,
        "cell": (0.625, 0.75, 1.0, 1.0), "anchor": "floor", "style": "breakdown"},
    {"name": "Talus", "kind": "rubble", "cell": (0.25, 0.75, 0.625, 1.0), "anchor": "floor", "style": "breakdown"},
]


def build_piece(spec: dict, high: bool):
    name = f"{'High' if high else 'Formation'}_{spec['name']}"
    kind = spec["kind"]
    if kind == "lathe":
        n_seg, n_ring = spec["high" if high else "low"]
        verts, faces, uvs = lathe(n_seg, n_ring, spec["field"](high), spec["tip"], spec["cell"],
            bool(spec.get("hanging", False)))
        if "oval" in spec:
            verts = verts * np.array([spec["oval"][0], spec["oval"][1], 1.0])
        return mesh_object(name, verts, faces, None if high else uvs)
    if kind == "curtain":
        n_s, n_t = spec["high" if high else "low"]
        verts, faces, uvs = curtain_mesh(n_s, n_t, high, spec["cell"])
        return mesh_object(name, verts, faces, None if high else uvs)
    if kind == "boulder":
        obj = boulder_object(name, 7 if high else 3, spec["seed"], spec["squash"], spec["fractures"], high, spec["scale"])
    else:
        obj = rubble_object(name, high)
    if not high:
        smart_uv(obj, spec["cell"])
    return obj


# --- 4. source materials and the bake ---------------------------------------------------------


def load_source_images(source_dir: Path) -> dict:
    out = {}
    for kind, colorspace in (("diff", "sRGB"), ("rough", "Non-Color"), ("disp", "Non-Color")):
        image = bpy.data.images.load(str(source_dir / "rock_08" / sources.local_name("rock_08", kind)))
        image.colorspace_settings.name = colorspace
        out[kind] = image
    return out


def _ramp(nodes, stops):
    node = nodes.new("ShaderNodeValToRGB")
    elements = node.color_ramp.elements
    elements[0].position, elements[0].color = stops[0][0], (*stops[0][1], 1.0)
    elements[1].position, elements[1].color = stops[-1][0], (*stops[-1][1], 1.0)
    for position, colour in stops[1:-1]:
        element = elements.new(position)
        element.color = (*colour, 1.0)
    return node


def _mix(nodes, links, blend: str, factor, a, b):
    node = nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend
    if isinstance(factor, float):
        socket(node.inputs, "Factor_Float").default_value = factor
    else:
        links.new(factor, socket(node.inputs, "Factor_Float"))
    for ident, value in (("A_Color", a), ("B_Color", b)):
        if isinstance(value, tuple):
            socket(node.inputs, ident).default_value = (*value, 1.0)
        else:
            links.new(value, socket(node.inputs, ident))
    return socket(node.outputs, "Result_Color")


def _range(nodes, links, value, low, high):
    node = nodes.new("ShaderNodeMapRange")
    links.new(value, node.inputs["Value"])
    node.inputs["From Min"].default_value = low
    node.inputs["From Max"].default_value = high
    node.clamp = True
    return node.outputs["Result"]


def source_material(name: str, style: str, images: dict):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / 0.8, 1 / 0.8, 1 / 0.8)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])

    def image(kind):
        node = nodes.new("ShaderNodeTexImage")
        node.image = images[kind]
        node.projection = "BOX"
        node.projection_blend = 0.4
        node.interpolation = "Cubic"
        links.new(mapping.outputs["Vector"], node.inputs["Vector"])
        return node

    diff, rough, disp = image("diff"), image("rough"), image("disp")
    geometry = nodes.new("ShaderNodeNewGeometry")
    pointy = _range(nodes, links, geometry.outputs["Pointiness"], 0.44, 0.56)
    variation = nodes.new("ShaderNodeTexNoise")
    variation.inputs["Scale"].default_value = 1.3
    variation.inputs["Detail"].default_value = 6.0
    variation.inputs["Roughness"].default_value = 0.55
    links.new(coord.outputs["Object"], variation.inputs["Vector"])
    if style == "flowstone":
        palette = _ramp(nodes, [(0.25, (0.27, 0.25, 0.21)), (0.45, (0.42, 0.39, 0.34)), (0.62, (0.55, 0.53, 0.48)),
            (0.8, (0.50, 0.40, 0.29))])
        links.new(variation.outputs["Fac"], palette.inputs["Fac"])
        bands = nodes.new("ShaderNodeTexWave")
        bands.wave_type = "BANDS"
        bands.bands_direction = "Z"
        bands.inputs["Scale"].default_value = 4.0
        bands.inputs["Distortion"].default_value = 11.0
        bands.inputs["Detail"].default_value = 4.0
        links.new(coord.outputs["Object"], bands.inputs["Vector"])
        band = _range(nodes, links, bands.outputs["Fac"], 0.25, 1.0)
        streak_map = nodes.new("ShaderNodeMapping")
        streak_map.inputs["Scale"].default_value = (7.0, 7.0, 0.9)
        links.new(coord.outputs["Object"], streak_map.inputs["Vector"])
        streak_noise = nodes.new("ShaderNodeTexNoise")
        streak_noise.inputs["Scale"].default_value = 1.0
        streak_noise.inputs["Detail"].default_value = 4.0
        links.new(streak_map.outputs["Vector"], streak_noise.inputs["Vector"])
        streak = _range(nodes, links, streak_noise.outputs["Fac"], 0.47, 0.64)
        banded = _mix(nodes, links, "MULTIPLY", band, palette.outputs["Color"], (0.93, 0.91, 0.88))
        grey = nodes.new("ShaderNodeHueSaturation")
        grey.inputs["Saturation"].default_value = 0.3
        links.new(diff.outputs["Color"], grey.inputs["Color"])
        textured = _mix(nodes, links, "OVERLAY", 0.7, banded, grey.outputs["Color"])
        wet = _mix(nodes, links, "MULTIPLY", streak, textured, (0.86, 0.80, 0.72))
        shaded = _mix(nodes, links, "MULTIPLY", 1.0, wet, (1.0, 1.0, 1.0))
        rough_value = nodes.new("ShaderNodeMath")
        rough_value.operation = "MULTIPLY_ADD"
        links.new(rough.outputs["Color"], rough_value.inputs[0])
        rough_value.inputs[1].default_value = 0.75
        rough_value.inputs[2].default_value = 0.12
        wet_rough = nodes.new("ShaderNodeMix")
        wet_rough.data_type = "FLOAT"
        links.new(streak, socket(wet_rough.inputs, "Factor_Float"))
        links.new(rough_value.outputs["Value"], socket(wet_rough.inputs, "A_Float"))
        socket(wet_rough.inputs, "B_Float").default_value = 0.32
        rough_out = socket(wet_rough.outputs, "Result_Float")
        bump_strength, bump_distance = 0.22, 0.018
    else:
        tint = _ramp(nodes, [(0.3, (0.74, 0.72, 0.68)), (0.7, (0.92, 0.88, 0.82))])
        links.new(variation.outputs["Fac"], tint.inputs["Fac"])
        shaded = _mix(nodes, links, "MULTIPLY", 1.0, diff.outputs["Color"], tint.outputs["Color"])
        rough_out = rough.outputs["Color"]
        bump_strength, bump_distance = 0.45, 0.03
    # Worn edges lighter, crevices dirtier: pigment, not lighting.
    wear = nodes.new("ShaderNodeMapRange")
    links.new(pointy, wear.inputs["Value"])
    wear.inputs["To Min"].default_value = 0.72
    wear.inputs["To Max"].default_value = 1.18
    base = _mix(nodes, links, "MULTIPLY", 1.0, shaded, (1.0, 1.0, 1.0))
    worn = nodes.new("ShaderNodeVectorMath")
    worn.operation = "SCALE"
    links.new(base, worn.inputs[0])
    links.new(wear.outputs["Result"], worn.inputs["Scale"])
    links.new(worn.outputs["Vector"], bsdf.inputs["Base Color"])
    links.new(rough_out, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = bump_distance
    links.new(disp.outputs["Color"], bump.inputs["Height"])
    pits = nodes.new("ShaderNodeTexNoise")
    pits.inputs["Scale"].default_value = 38.0
    pits.inputs["Detail"].default_value = 3.0
    links.new(coord.outputs["Object"], pits.inputs["Vector"])
    fine = nodes.new("ShaderNodeBump")
    fine.inputs["Strength"].default_value = 0.12
    fine.inputs["Distance"].default_value = 0.004
    links.new(pits.outputs["Fac"], fine.inputs["Height"])
    links.new(bump.outputs["Normal"], fine.inputs["Normal"])
    links.new(fine.outputs["Normal"], bsdf.inputs["Normal"])
    return material


def bake_kit(pieces: list, work: Path, prefix: str, size: int, emit: bool = False) -> dict:
    """Bake every piece's high mesh onto its low mesh's atlas cell: base colour,
    tangent normal, roughness, occlusion and (for glowing flora) emission. Writes
    `<prefix>_albedo/normal/orm[/emit].png` at half the bake size."""
    scene = bpy.context.scene
    kinds = [("color", (0.4, 0.38, 0.35, 1.0), "Linear Rec.709"), ("normal", (0.5, 0.5, 1.0, 1.0), "Non-Color"),
        ("rough", (0.8, 0.8, 0.8, 1.0), "Non-Color"), ("ao", (1.0, 1.0, 1.0, 1.0), "Non-Color")]
    if emit:
        kinds.append(("emit", (0.0, 0.0, 0.0, 1.0), "Linear Rec.709"))
    targets = {}
    for kind, colour, colorspace in kinds:
        image = bpy.data.images.new(f"{prefix}_{kind}", size, size, alpha=False, float_buffer=True)
        image.colorspace_settings.name = colorspace
        image.generated_color = colour
        targets[kind] = image
    bake_mat = bpy.data.materials.new(f"{prefix}_BakeTarget")
    bake_mat.use_nodes = True
    target_node = bake_mat.node_tree.nodes.new("ShaderNodeTexImage")
    bake_mat.node_tree.nodes.active = target_node
    for piece in pieces:
        mesh = piece["low"].data
        mesh.materials.clear()
        mesh.materials.append(bake_mat)
        indices = np.zeros(len(mesh.polygons), np.int32)
        mesh.polygons.foreach_set("material_index", indices)
    passes = [("color", "DIFFUSE", {"COLOR"}, 16), ("normal", "NORMAL", set(), 12),
        ("rough", "ROUGHNESS", set(), 8), ("ao", "AO", set(), 64)]
    if emit:
        passes.append(("emit", "EMIT", set(), 4))
    timing = {}
    for kind, bake_type, pass_filter, samples in passes:
        started = time.time()
        target_node.image = targets[kind]
        scene.cycles.samples = samples
        for piece in pieces:
            occluders = []
            if kind == "ao":
                for z in piece["occluders"]:
                    bpy.ops.mesh.primitive_plane_add(size=6.0, location=(piece["offset"], 0.0, z))
                    occluders.append(bpy.context.active_object)
            select_only([piece["high"], piece["low"]], piece["low"])
            kwargs = dict(type=bake_type, use_selected_to_active=True, cage_extrusion=piece["cage"],
                max_ray_distance=piece["cage"] * 2.2, margin=8, margin_type="EXTEND", use_clear=False,
                target="IMAGE_TEXTURES")
            if pass_filter:
                kwargs["pass_filter"] = pass_filter
            if bake_type == "NORMAL":
                kwargs["normal_space"] = "TANGENT"
            bpy.ops.object.bake(**kwargs)
            for occluder in occluders:
                bpy.data.objects.remove(occluder, do_unlink=True)
        timing[kind] = round(time.time() - started, 1)
        log("baked", prefix, kind, timing[kind], "s")
    colour = image_pixels(targets["color"])[..., :3]
    normal = image_pixels(targets["normal"])[..., :3]
    rough = image_pixels(targets["rough"])[..., 0]
    occlusion = image_pixels(targets["ao"])[..., 0]
    # AO at 64 samples still has grain: a light blur inside the islands.
    occlusion = np.clip(0.6 * occlusion + 0.4 * blur(occlusion, 1.2), 0.0, 1.0)
    occlusion = 1.0 - (1.0 - occlusion) * 0.85
    orm = np.stack([half(occlusion), half(rough), np.zeros((size // 2, size // 2))], axis=-1)
    files = {
        "albedo": work / f"{prefix}_albedo.png",
        "normal": work / f"{prefix}_normal.png",
        "orm": work / f"{prefix}_orm.png",
    }
    write_png(files["albedo"], quantize(to_srgb(colour)))
    write_png(files["normal"], quantize(normal))
    write_png(files["orm"], quantize(orm))
    if emit:
        files["emit"] = work / f"{prefix}_emit.png"
        glow = half(image_pixels(targets["emit"])[..., :3])
        write_png(files["emit"], quantize(to_srgb(np.clip(glow, 0.0, 1.0))))
    return {"files": files, "timing": timing}


def final_material(name: str, files: dict):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"

    def image(path: Path, colorspace: str):
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(path))
        node.image.colorspace_settings.name = colorspace
        links.new(uv.outputs["UV"], node.inputs["Vector"])
        return node

    albedo = image(files["albedo"], "sRGB")
    orm = image(files["orm"], "Non-Color")
    normal = image(files["normal"], "Non-Color")
    links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(orm.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.space = "TANGENT"
    normal_map.uv_map = "UVMap"
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    if "emit" in files:
        glow = image(files["emit"], "sRGB")
        links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    # The glTF exporter reads occlusion from this group's "Occlusion" socket.
    group = bpy.data.node_groups.get("glTF Material Output")
    if group is None:
        group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        group.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    settings = nodes.new("ShaderNodeGroup")
    settings.node_tree = group
    links.new(split.outputs["Red"], settings.inputs["Occlusion"])
    return material


def build_formations(source_dir: Path, out_dir: Path, work: Path, report: dict) -> list:
    images = load_source_images(source_dir)
    styles = {"flowstone": source_material("FlowstoneSource", "flowstone", images),
        "breakdown": source_material("BreakdownSource", "breakdown", images)}
    pieces = []
    for index, spec in enumerate(PIECES):
        started = time.time()
        low = build_piece(spec, False)
        high = build_piece(spec, True)
        high.data.materials.append(styles[spec["style"]])
        offset = index * SPACING
        low.location.x = offset
        high.location.x = offset
        dims = low.dimensions
        cage = 0.05 + 0.03 * max(dims.x, dims.y) * 0.5
        anchor = spec["anchor"]
        if spec["name"] == "Column":
            occluders = [0.0, 6.0]
        elif anchor == "roof":
            occluders = [0.0]
        else:
            occluders = [0.0]
        pieces.append({"spec": spec, "low": low, "high": high, "offset": offset, "cage": cage,
            "occluders": occluders})
        log("piece", spec["name"], "low", triangles(low), "high", triangles(high), round(time.time() - started, 1), "s")
    baked = bake_kit(pieces, work, "formations", ATLAS)
    material = final_material("CaveFormation", baked["files"])
    for piece in pieces:
        piece["low"].data.materials.clear()
        piece["low"].data.materials.append(material)
        piece["low"].location.x = 0.0
        bpy.data.objects.remove(piece["high"], do_unlink=True)
    path = out_dir / "cave_formations.glb"
    export_glb(path, [p["low"] for p in pieces], vertex_colours=False)
    entries = {}
    for piece in pieces:
        low = piece["low"]
        co = np.empty(len(low.data.vertices) * 3, np.float32)
        low.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        # Godot frame: x, z, -y.
        godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=-1)
        entries[piece["spec"]["name"]] = {
            "node": low.name,
            "anchor": piece["spec"]["anchor"],
            "triangles": triangles(low),
            "min": [round(float(v), 4) for v in godot.min(axis=0)],
            "max": [round(float(v), 4) for v in godot.max(axis=0)],
        }
    report["formations"] = {"file": path.name, "sha256": sha256(path), "atlas": ATLAS, "orm": ORM_SIZE,
        "bake_seconds": baked["timing"], "pieces": entries}
    return [p["low"] for p in pieces]


def export_glb(path: Path, objects: list, vertex_colours: bool) -> None:
    select_only(objects, objects[0])
    available = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    options = dict(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
        export_apply=False, export_materials="EXPORT", export_image_format="AUTO", export_tangents=True,
        export_animations=False, export_skins=False, export_morph=False, export_cameras=False,
        export_lights=False, export_vertex_color="ACTIVE" if vertex_colours else "NONE")
    options = {key: value for key, value in options.items() if key in available or key == "filepath"}
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(**options)
    log("exported", path.name, path.stat().st_size, "bytes")


# --- 4b. flora: the pale garden's fungus ------------------------------------------------------

FLORA_ATLAS = 1024


def surface(n_u: int, n_v: int, fn, cell, wrap: bool):
    """A parametric grid surface. `fn(U, V)` returns X, Y, Z arrays for U, V in
    [0, 1]; U runs round (closed when `wrap`), V along. UVs fill `cell`."""
    u = np.linspace(0.0, 1.0, n_u + 1)
    v = np.linspace(0.0, 1.0, n_v + 1)
    U, V = np.meshgrid(u, v, indexing="ij")
    X, Y, Z = fn(U, V)
    if wrap:
        X[-1], Y[-1], Z[-1] = X[0], Y[0], Z[0]
    verts = np.stack([X, Y, Z], axis=-1).reshape(-1, 3)
    u0, v0, u1, v1 = cell
    uvs = np.stack([u0 + INSET * 0.5 + (u1 - u0 - INSET) * U, v0 + INSET * 0.5 + (v1 - v0 - INSET) * V],
        axis=-1).reshape(-1, 2)
    rows = n_v + 1
    faces = []
    for i in range(n_u):
        for j in range(n_v):
            a = i * rows + j
            faces.append((a, a + rows, a + rows + 1, a + 1))
    return verts, faces, uvs


def _merge(parts):
    verts, faces, uvs, offset = [], [], [], 0
    for v, f, uv in parts:
        verts.append(v)
        uvs.append(uv)
        faces.extend(tuple(i + offset for i in face) for face in f)
        offset += len(v)
    return np.vstack(verts), faces, np.vstack(uvs)


def mushroom(high: bool, height: float, radius: float, lean: float, seed: float, stem_cell, cap_cell):
    """One mushroom: a stem that swells into its foot and bends a little, under a
    lobed cap with a curled lip and gill plates beneath. Returns the stem's and the
    cap's (verts, faces, uvs)."""
    stem_top = height * 0.86
    stem_r = radius * 0.13
    n_u = 96 if high else 12

    def stem(U, V):
        th = U * 2.0 * math.pi
        z = -0.04 * height + V * (stem_top + 0.06 * height)
        r = stem_r * (1.0 + 0.9 * (1.0 - V) ** 5 + 0.25 * V ** 6)
        if high:
            fibres = 0.04 * np.abs(np.sin(th * 23.0 + 3.0 * fbm(np.cos(th), np.sin(th), z * 0.6, 2, salt=seed)))
            r = r * (1.0 + fibres + 0.05 * fbm(np.cos(th) * 2, np.sin(th) * 2, z * 3, 3, salt=seed + 1))
        bend = lean * height * np.sin(V * math.pi) * 0.5
        return r * np.cos(th) + bend, r * np.sin(th), z

    def cap(U, V):
        th = U * 2.0 * math.pi
        lobes = 1.0 + 0.07 * np.sin(5.0 * th + seed) + 0.05 * fbm(np.cos(th) * 1.5, np.sin(th) * 1.5, 0 * th, 2,
            salt=seed + 2)
        rim_z = height * 0.9
        top_z = height * 1.04
        under = V < 0.42
        lip = (V >= 0.42) & (V < 0.54)
        s1 = np.clip(V / 0.42, 0.0, 1.0)
        s2 = np.clip((V - 0.42) / 0.12, 0.0, 1.0)
        s3 = np.clip((V - 0.54) / 0.46, 0.0, 1.0)
        r = np.where(under, stem_r * 1.25 + (radius - stem_r * 1.25) * s1,
            np.where(lip, radius + radius * 0.06 * np.sin(math.pi * s2), radius * np.cos(s3 * math.pi / 2) ** 0.85))
        z = np.where(under, stem_top + (rim_z - stem_top) * s1 ** 0.6,
            np.where(lip, rim_z + height * 0.04 * s2, rim_z + height * 0.04 + (top_z - rim_z - height * 0.04)
                * np.sin(s3 * math.pi / 2) ** 0.75))
        if high:
            gills = np.where(under, 0.045 * radius * np.abs(np.sin(th * 30.0)) ** 0.35 * np.sin(math.pi * s1) ** 0.5,
                0.0)
            z = z - gills
            scales = np.where(V > 0.6, 0.012 * radius * fbm(np.cos(th) * 6, np.sin(th) * 6, V * 6, 3, salt=seed + 3),
                0.0)
            r = r * (1.0 + scales)
            z = z + scales * 2.0
        r = r * lobes
        return r * np.cos(th), r * np.sin(th), z

    stem_mesh = surface(n_u, 24 if high else 6, stem, stem_cell, True)
    cap_mesh = surface(n_u * 2 if high else 28, 110 if high else 10, cap, cap_cell, True)
    return stem_mesh, cap_mesh


def _cells(cell, cols: int, rows: int):
    u0, v0, u1, v1 = cell
    w = (u1 - u0) / cols
    h = (v1 - v0) / rows
    return [(u0 + c * w, v0 + r * h, u0 + (c + 1) * w, v0 + (r + 1) * h) for r in range(rows) for c in range(cols)]


def flora_object(name: str, spec: dict, high: bool):
    """Builds one flora piece as one object; each part's faces carry the material
    slot of the source surface it is baked from (0 stem, 1 cap, 2 shelf)."""
    parts = []
    slots = []
    if spec["kind"] == "giant":
        stem_cell, cap_cell = _cells(spec["cell"], 2, 1)
        stem, cap = mushroom(high, 2.5, 0.85, 0.12, 7.0, stem_cell, cap_cell)
        parts += [stem, cap]
        slots += [0, 1]
    elif spec["kind"] == "cluster":
        rng = np.random.default_rng(SEED + 404)
        cells = _cells(spec["cell"], 2, 2)
        for k in range(4):
            stem_cell, cap_cell = _cells(cells[k], 2, 1)
            height = [0.42, 0.3, 0.24, 0.17][k]
            stem, cap = mushroom(high, height, height * rng.uniform(0.38, 0.5), rng.uniform(0.1, 0.3), 11.0 + k,
                stem_cell, cap_cell)
            angle = k * 2.1 + rng.uniform(-0.3, 0.3)
            reach = 0.0 if k == 0 else rng.uniform(0.12, 0.22)
            tilt = Matrix.Rotation(rng.uniform(0.08, 0.3) * (0 if k == 0 else 1), 4, Vector((math.sin(angle), -math.cos(angle), 0)))
            place = Matrix.Translation((math.cos(angle) * reach, math.sin(angle) * reach, 0.0)) @ tilt
            for verts, faces, uvs in (stem, cap):
                moved = np.array([(place @ Vector(v))[:] for v in verts])
                parts.append((moved, faces, uvs))
                slots.append(0 if len(parts) % 2 == 1 else 1)
    else:
        # Bracket fungus: three shelves stepped up a wall, each a half disc pinched
        # to the wall at its sides, a pale pored underside below a ringed top.
        cells = _cells(spec["cell"], 3, 1)
        for k, (lift, size) in enumerate(((0.0, 0.34), (0.22, 0.26), (0.38, 0.19))):
            def shelf(U, V, lift=lift, size=size, k=k):
                th = (U - 0.5) * math.pi * 0.92
                pinch = np.cos((U - 0.5) * math.pi) ** 0.55
                reach = size * pinch * (1.0 + 0.06 * np.sin(7 * th + k))
                top = V >= 0.5
                s = np.where(top, (1.0 - V) * 2.0, V * 2.0)
                rho = np.where(s > 0.86, 1.0 - (s - 0.86) * 0.3, s / 0.86) * reach
                thick = size * 0.22 * (1.0 - (rho / np.maximum(reach, 1e-4)) ** 2) ** 0.6
                z = np.where(top, thick * 0.65, -thick * 0.35) - 0.08 * size * (rho / np.maximum(reach, 1e-4)) ** 2
                if high:
                    rings = 0.012 * size * np.sin(rho / np.maximum(size, 1e-4) * 38.0) * top
                    z = z + rings
                x = rho * np.sin(th) + (k - 1) * 0.12
                y = -rho * np.cos(th)
                return x, y, z + lift
            parts.append(surface(48 if high else 9, 40 if high else 6, shelf, cells[k], False))
            slots.append(2)
    verts, faces, uvs = _merge(parts)
    face_slots = []
    for (v, f, uv), slot in zip(parts, slots):
        face_slots.extend([slot] * len(f))
    obj = mesh_object(name, verts, faces, None if high else uvs)
    if high:
        obj.data.polygons.foreach_set("material_index", np.array(face_slots, np.int32))
    return obj


FLORA = [
    {"name": "CapGiant", "kind": "giant", "cell": (0.0, 0.0, 1.0, 0.5), "cage": 0.06},
    {"name": "CapCluster", "kind": "cluster", "cell": (0.0, 0.5, 0.6, 1.0), "cage": 0.025},
    {"name": "Shelf", "kind": "shelf", "cell": (0.6, 0.5, 1.0, 1.0), "cage": 0.03},
]


def flora_material(name: str, part: str):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    coord = nodes.new("ShaderNodeTexCoord")
    geometry = nodes.new("ShaderNodeNewGeometry")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Normal"], split.inputs["Vector"])
    below = _range(nodes, links, split.outputs["Z"], -0.05, -0.45)
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 6.0
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    if part == "stem":
        streak_map = nodes.new("ShaderNodeMapping")
        streak_map.inputs["Scale"].default_value = (30.0, 30.0, 1.5)
        links.new(coord.outputs["Object"], streak_map.inputs["Vector"])
        streaks = nodes.new("ShaderNodeTexNoise")
        streaks.inputs["Detail"].default_value = 4.0
        links.new(streak_map.outputs["Vector"], streaks.inputs["Vector"])
        tone = _ramp(nodes, [(0.3, (0.58, 0.6, 0.5)), (0.7, (0.82, 0.84, 0.74))])
        links.new(streaks.outputs["Fac"], tone.inputs["Fac"])
        split_pos = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coord.outputs["Object"], split_pos.inputs["Vector"])
        foot = _range(nodes, links, split_pos.outputs["Z"], 0.25, 0.0)
        colour = _mix(nodes, links, "MULTIPLY", foot, tone.outputs["Color"], (0.55, 0.5, 0.38))
        glow = (0.0, 0.0, 0.0)
        rough = 0.72
    elif part == "cap":
        spots = nodes.new("ShaderNodeTexVoronoi")
        spots.inputs["Scale"].default_value = 26.0
        links.new(coord.outputs["Object"], spots.inputs["Vector"])
        speck = _range(nodes, links, spots.outputs["Distance"], 0.12, 0.05)
        top = _ramp(nodes, [(0.25, (0.62, 0.66, 0.52)), (0.75, (0.78, 0.83, 0.68))])
        links.new(noise.outputs["Fac"], top.inputs["Fac"])
        spotted = _mix(nodes, links, "MULTIPLY", speck, top.outputs["Color"], (0.55, 0.62, 0.44))
        colour = _mix(nodes, links, "MIX", below, spotted, (0.7, 0.86, 0.72))
        glow = below
        rough = 0.5
    else:
        rings = nodes.new("ShaderNodeTexWave")
        rings.wave_type = "RINGS"
        rings.rings_direction = "SPHERICAL"
        rings.inputs["Scale"].default_value = 9.0
        rings.inputs["Distortion"].default_value = 3.0
        links.new(coord.outputs["Object"], rings.inputs["Vector"])
        band = _ramp(nodes, [(0.2, (0.36, 0.3, 0.2)), (0.55, (0.62, 0.55, 0.4)), (0.9, (0.74, 0.7, 0.56))])
        links.new(rings.outputs["Fac"], band.inputs["Fac"])
        pores = nodes.new("ShaderNodeTexVoronoi")
        pores.inputs["Scale"].default_value = 90.0
        links.new(coord.outputs["Object"], pores.inputs["Vector"])
        pored = _mix(nodes, links, "MULTIPLY", _range(nodes, links, pores.outputs["Distance"], 0.08, 0.02),
            (0.8, 0.84, 0.74), (0.5, 0.56, 0.5))
        colour = _mix(nodes, links, "MIX", below, band.outputs["Color"], pored)
        glow = below
        rough = 0.6
    links.new(colour, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    if isinstance(glow, tuple):
        bsdf.inputs["Emission Strength"].default_value = 0.0
    else:
        gill = _mix(nodes, links, "MULTIPLY", glow, (0.0, 0.0, 0.0), (0.42, 0.95, 0.66))
        links.new(gill, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    bump.inputs["Distance"].default_value = 0.01
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return material


def build_flora(out_dir: Path, work: Path, report: dict) -> list:
    materials = [flora_material("FloraStem", "stem"), flora_material("FloraCap", "cap"),
        flora_material("FloraShelf", "shelf")]
    pieces = []
    for index, spec in enumerate(FLORA):
        low = flora_object(f"Flora_{spec['name']}", spec, False)
        high = flora_object(f"FloraHigh_{spec['name']}", spec, True)
        for material in materials:
            high.data.materials.append(material)
        # Well clear of the formation kit, which still stands at the origin.
        offset = 300.0 + index * SPACING
        low.location.x = offset
        high.location.x = offset
        pieces.append({"spec": spec, "low": low, "high": high, "offset": offset, "cage": spec["cage"],
            "occluders": [0.0]})
        log("flora", spec["name"], "low", triangles(low), "high", triangles(high))
    baked = bake_kit(pieces, work, "flora", FLORA_ATLAS, emit=True)
    material = final_material("CaveFlora", baked["files"])
    for piece in pieces:
        piece["low"].data.materials.clear()
        piece["low"].data.materials.append(material)
        piece["low"].location.x = 0.0
        bpy.data.objects.remove(piece["high"], do_unlink=True)
    path = out_dir / "cave_flora.glb"
    export_glb(path, [p["low"] for p in pieces], vertex_colours=False)
    entries = {}
    for piece in pieces:
        low = piece["low"]
        co = np.empty(len(low.data.vertices) * 3, np.float32)
        low.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=-1)
        entries[piece["spec"]["name"]] = {"triangles": triangles(low),
            "min": [round(float(v), 4) for v in godot.min(axis=0)],
            "max": [round(float(v), 4) for v in godot.max(axis=0)]}
    report["flora"] = {"file": path.name, "sha256": sha256(path), "atlas": FLORA_ATLAS // 2,
        "bake_seconds": baked["timing"], "pieces": entries}
    return [p["low"] for p in pieces]


# --- 5. fauna ----------------------------------------------------------------------------------


def _part(bm, colours: dict, made: dict, colour):
    for vert in made["verts"]:
        colours[vert] = colour


def _sphere(bm, colours, radius, at, scale, colour, segs=10, rings=7):
    matrix = Matrix.Translation(at) @ Matrix.Diagonal((*scale, 1.0))
    made = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius, matrix=matrix)
    _part(bm, colours, made, colour)


def _tube(bm, colours, a, b, r_a, r_b, colour, sides=5):
    a, b = Vector(a), Vector(b)
    span = b - a
    length = span.length
    if length < 1e-5:
        return
    rotation = Vector((0, 0, 1)).rotation_difference(span.normalized()).to_matrix().to_4x4()
    matrix = Matrix.Translation((a + b) * 0.5) @ rotation
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r_a, radius2=r_b,
        depth=length, matrix=matrix)
    _part(bm, colours, made, colour)


def _finish_fauna(name: str, bm, colours: dict):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    order = list(bm.verts)
    values = [colours.get(v, (0.1, 0.1, 0.1)) for v in order]
    bm.to_mesh(mesh)
    bm.free()
    attribute = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="POINT")
    flat = []
    for colour in values:
        flat.extend((colour[0], colour[1], colour[2], 1.0))
    attribute.data.foreach_set("color", flat)
    mesh.color_attributes.active_color = attribute
    mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bat_object():
    bm, colours = bmesh.new(), {}
    fur, membrane, dark = (0.10, 0.075, 0.06), (0.085, 0.065, 0.06), (0.03, 0.025, 0.022)
    _sphere(bm, colours, 1.0, (0.0, 0.0, 0.0), (0.021, 0.042, 0.019), fur)
    _sphere(bm, colours, 1.0, (0.0, 0.048, 0.006), (0.015, 0.016, 0.014), fur)
    _sphere(bm, colours, 1.0, (0.0, 0.062, 0.003), (0.007, 0.009, 0.006), dark, 8, 5)
    for side in (-1.0, 1.0):
        _tube(bm, colours, (side * 0.007, 0.052, 0.016), (side * 0.013, 0.047, 0.036), 0.006, 0.0008, dark, 5)
        # The wing: a membrane stitched between the arm's leading edge and the
        # scalloped trailing edge, in columns along the span and rows across it, so
        # the runtime's flap (a bend that grows with |x|) folds it smoothly.
        lead = _resample([(0.016, 0.02), (0.06, 0.04), (0.095, 0.045), (0.165, 0.03)], 12)
        trail = _resample([(0.018, -0.04), (0.06, -0.062), (0.105, -0.072), (0.118, -0.05), (0.145, -0.052),
            (0.152, -0.026), (0.17, -0.012), (0.161, 0.01), (0.163, 0.026)], 12)
        rows = 4
        grid = []
        for k in range(rows + 1):
            f = k / rows
            row = []
            for (lx, ly), (tx, ty) in zip(lead, trail):
                row.append(bm.verts.new((side * (lx + (tx - lx) * f), ly + (ty - ly) * f, 0.0)))
            grid.append(row)
        for row in grid:
            for vert in row:
                colours[vert] = membrane
        for k in range(rows):
            for index in range(len(lead) - 1):
                quad = (grid[k][index], grid[k][index + 1], grid[k + 1][index + 1], grid[k + 1][index])
                bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
        wrist = Vector((side * 0.095, 0.045, 0.0012))
        for tip in ((0.165, 0.03), (0.17, -0.012), (0.145, -0.052), (0.105, -0.072)):
            _tube(bm, colours, wrist, Vector((side * tip[0], tip[1], 0.0012)), 0.0018, 0.0007, dark, 4)
        _tube(bm, colours, Vector((side * 0.016, 0.02, 0.0012)), wrist, 0.0028, 0.0022, dark, 4)
    return _finish_fauna("Fauna_Bat", bm, colours)


def _resample(points, count: int) -> list:
    """`count` points evenly spaced along a 2D polyline by arc length."""
    pts = np.array(points, np.float64)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    along = np.concatenate([[0.0], np.cumsum(seg)])
    targets = np.linspace(0.0, along[-1], count)
    xs = np.interp(targets, along, pts[:, 0])
    ys = np.interp(targets, along, pts[:, 1])
    return list(zip(xs.tolist(), ys.tolist()))


def rat_object():
    bm, colours = bmesh.new(), {}
    fur, belly, pink, black = (0.20, 0.17, 0.14), (0.32, 0.28, 0.24), (0.55, 0.36, 0.34), (0.01, 0.01, 0.01)
    _sphere(bm, colours, 1.0, (0.0, 0.0, 0.042), (0.036, 0.075, 0.034), fur, 12, 8)
    _sphere(bm, colours, 1.0, (0.0, -0.005, 0.026), (0.03, 0.06, 0.02), belly, 10, 6)
    _sphere(bm, colours, 1.0, (0.0, 0.085, 0.046), (0.021, 0.036, 0.02), fur, 10, 7)
    _sphere(bm, colours, 1.0, (0.0, 0.118, 0.04), (0.008, 0.012, 0.008), pink, 8, 5)
    for side in (-1.0, 1.0):
        _sphere(bm, colours, 1.0, (side * 0.016, 0.075, 0.066), (0.011, 0.004, 0.012), pink, 8, 5)
        _sphere(bm, colours, 1.0, (side * 0.014, 0.1, 0.054), (0.0035, 0.0035, 0.0035), black, 6, 4)
        for end in (-1.0, 1.0):
            foot = Vector((side * 0.026, end * 0.04, 0.006))
            _tube(bm, colours, foot + Vector((0, 0, 0.026)), foot, 0.007, 0.004, fur, 5)
            _sphere(bm, colours, 1.0, foot + Vector((0, 0.006, -0.002)), (0.006, 0.01, 0.003), pink, 6, 4)
    points = [Vector((0.0, -0.07 - 0.03 * k, 0.034 - 0.006 * k + 0.004 * math.sin(k))) for k in range(7)]
    for k in range(6):
        _tube(bm, colours, points[k], points[k + 1], 0.0065 - k * 0.0009, 0.0056 - k * 0.0009, pink, 5)
    return _finish_fauna("Fauna_Rat", bm, colours)


def spider_object():
    bm, colours = bmesh.new(), {}
    body, mark, leg = (0.05, 0.04, 0.034), (0.30, 0.24, 0.16), (0.07, 0.055, 0.045)
    _sphere(bm, colours, 1.0, (0.0, -0.02, 0.016), (0.016, 0.022, 0.014), body, 10, 7)
    _sphere(bm, colours, 1.0, (0.0, -0.014, 0.028), (0.006, 0.01, 0.004), mark, 8, 5)
    _sphere(bm, colours, 1.0, (0.0, 0.008, 0.012), (0.011, 0.012, 0.009), body, 8, 6)
    for side in (-1.0, 1.0):
        for index, along in enumerate((0.016, 0.009, 0.002, -0.006)):
            spread = (index - 1.5) * 0.45
            base = Vector((side * 0.008, 0.008 + along * 0.3, 0.012))
            knee = Vector((side * (0.03 + 0.004 * abs(spread)), 0.008 + along * 1.6 + spread * 0.012, 0.03))
            foot = Vector((side * (0.05 + 0.006 * abs(spread)), 0.008 + along * 2.6 + spread * 0.03, 0.0))
            _tube(bm, colours, base, knee, 0.0016, 0.0013, leg, 4)
            _tube(bm, colours, knee, foot, 0.0013, 0.0007, leg, 4)
    return _finish_fauna("Fauna_Spider", bm, colours)


def moth_object():
    bm, colours = bmesh.new(), {}
    body, wing = (0.38, 0.33, 0.25), (0.62, 0.56, 0.45)
    _sphere(bm, colours, 1.0, (0.0, 0.0, 0.0), (0.003, 0.011, 0.003), body, 6, 5)
    for side in (-1.0, 1.0):
        for points in (((0.002, 0.004), (0.026, 0.01), (0.024, -0.006), (0.002, -0.002)),
                ((0.002, -0.002), (0.018, -0.008), (0.012, -0.018), (0.001, -0.009))):
            verts = [bm.verts.new((side * x, y, 0.0)) for x, y in points]
            for vert in verts:
                colours[vert] = wing
            face = verts if side > 0 else list(reversed(verts))
            bm.faces.new(face)
    return _finish_fauna("Fauna_Moth", bm, colours)


def build_fauna(out_dir: Path, report: dict) -> None:
    material = bpy.data.materials.new("CaveFauna")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Col"
    links.new(attribute.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    objects = [bat_object(), rat_object(), spider_object(), moth_object()]
    for obj in objects:
        obj.data.materials.append(material)
    path = out_dir / "cave_fauna.glb"
    export_glb(path, objects, vertex_colours=True)
    entries = {}
    for obj in objects:
        co = np.empty(len(obj.data.vertices) * 3, np.float32)
        obj.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=-1)
        entries[obj.name] = {"triangles": triangles(obj),
            "min": [round(float(v), 4) for v in godot.min(axis=0)],
            "max": [round(float(v), 4) for v in godot.max(axis=0)]}
    report["fauna"] = {"file": path.name, "sha256": sha256(path), "pieces": entries}
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


# --- 6. the web ----------------------------------------------------------------------------------


def _thread(curve_data, points, radius: float) -> None:
    spline = curve_data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for index, point in enumerate(points):
        spline.points[index].co = (point[0], point[1], 0.0, 1.0)
        spline.points[index].radius = radius


def build_web(out_dir: Path, work: Path, report: dict) -> None:
    rng = np.random.default_rng(SEED + 77)
    curve = bpy.data.curves.new("Web", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.0016
    curve.bevel_resolution = 1
    centre = np.array([0.03, -0.02])
    spokes = 17
    angles = np.sort(np.linspace(0, 2 * math.pi, spokes, endpoint=False) + rng.uniform(-0.12, 0.12, spokes))
    anchors = []
    for angle in angles:
        reach = rng.uniform(0.40, 0.49)
        point = centre + np.array([math.cos(angle), math.sin(angle)]) * reach
        anchors.append(np.clip(point, -0.485, 0.485))
    for index in range(spokes):
        _thread(curve, [centre, anchors[index]], 1.15)
        _thread(curve, [anchors[index], anchors[(index + 1) % spokes]], 1.25)
    # The capture spiral, stepping spoke to spoke, sagging toward the hub between
    # them and broken where something blundered through.
    radius, step = 0.05, 0.0175
    spiral = []
    turn = 0
    while True:
        for index in range(spokes):
            span = np.linalg.norm(anchors[index] - centre)
            r = radius + step * (turn + index / spokes)
            if r > span * 0.93:
                break
            direction = (anchors[index] - centre) / span
            spiral.append(centre + direction * r)
        else:
            turn += 1
            continue
        break
    run = [spiral[0]]
    for a, b in zip(spiral, spiral[1:]):
        mid = (a + b) * 0.5
        sag = mid - centre
        mid = mid - sag / max(np.linalg.norm(sag), 1e-6) * 0.004
        if rng.uniform() < 0.07:
            if len(run) > 1:
                _thread(curve, run, 0.7)
            run = [b]
            continue
        run.extend([mid, b])
    if len(run) > 1:
        _thread(curve, run, 0.7)
    # The hub's tight little mesh.
    hub = [centre + np.array([math.cos(a), math.sin(a)]) * (0.012 + 0.0035 * a) for a in np.linspace(0, 6 * math.pi, 60)]
    _thread(curve, hub, 0.8)
    web = bpy.data.objects.new("Web", curve)
    bpy.context.scene.collection.objects.link(web)
    silk = bpy.data.materials.new("Silk")
    silk.use_nodes = True
    nodes, links = silk.node_tree.nodes, silk.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    links.new(emit.outputs["Emission"], out.inputs["Surface"])
    curve.materials.append(silk)
    camera_data = bpy.data.cameras.new("WebCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.0
    camera = bpy.data.objects.new("WebCamera", camera_data)
    camera.location = (0.0, 0.0, 2.0)
    bpy.context.scene.collection.objects.link(camera)
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.film_transparent = True
    scene.cycles.samples = 48
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    raw = work / "web_render.png"
    scene.render.filepath = str(raw)
    bpy.ops.render.render(write_still=True)
    pixels = read_image(raw, 4)
    alpha = half(pixels[..., 3])
    rgba = np.stack([np.full_like(alpha, 0.94), np.full_like(alpha, 0.93), np.full_like(alpha, 0.9), alpha], axis=-1)
    target = out_dir / "textures" / "cave_web.png"
    write_png(target, quantize(rgba))
    report["web"] = {"file": f"textures/{target.name}", "size": 512, "sha256": sha256(target)}
    for obj in (web, camera):
        bpy.data.objects.remove(obj, do_unlink=True)
    scene.render.film_transparent = False


# --- 7. preview -----------------------------------------------------------------------------------


def render_preview(lows: list, work: Path) -> None:
    scene = bpy.context.scene
    x = 0.0
    for obj in lows:
        width = obj.dimensions.x
        x += width * 0.5 + 0.35
        hanging = obj.name.startswith("Formation_Stalactite") or obj.name == "Formation_Curtain"
        obj.location = (x, 0.0, 3.4 if hanging else 0.0)
        x += width * 0.5
    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(x * 0.5, 0.0, 0.0))
    ground = bpy.context.active_object
    ground_mat = bpy.data.materials.new("PreviewGround")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.08, 0.075, 0.07, 1.0)
    ground.data.materials.append(ground_mat)
    key = bpy.data.lights.new("Key", "POINT")
    key.energy = 2600.0
    key.color = (1.0, 0.72, 0.45)
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (x * 0.35, -4.5, 3.2)
    rim = bpy.data.lights.new("Rim", "POINT")
    rim.energy = 1400.0
    rim.color = (0.55, 0.7, 1.0)
    rim_obj = bpy.data.objects.new("Rim", rim)
    rim_obj.location = (x * 0.75, 3.5, 4.0)
    for obj in (key_obj, rim_obj):
        scene.collection.objects.link(obj)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 24.0
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    camera.location = (x * 0.5, -x * 0.62, 3.0)
    camera.rotation_euler = (math.radians(86.0), 0.0, 0.0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 760
    scene.cycles.samples = 48
    scene.world.color = (0.012, 0.012, 0.014)
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = str(work / "preview_formations.png")
    bpy.ops.render.render(write_still=True)
    log("preview", scene.render.filepath)


# --- main -------------------------------------------------------------------------------------------


def main() -> None:
    started = time.time()
    source_dir, out_dir, work = _args()
    work.mkdir(parents=True, exist_ok=True)
    (out_dir / "textures").mkdir(parents=True, exist_ok=True)
    report = {
        "generator": "tools/prepare_cave_kit.py",
        "builder": "python tools/build_cave_kit.py",
        "blender": bpy.app.version_string,
        "seed": SEED,
        "license": "CC BY-NC-SA 4.0 (LICENSE.md section 3); upstream scans CC0 1.0 (Poly Haven)",
        "conventions": {
            "axes": "Godot +Y up; fauna face -Z; floor pieces stand on their origin, roof pieces hang from it",
            "albedo": "sRGB", "normal": "OpenGL tangent (+Y green up)",
            "orh": "R occlusion, G roughness, B height (linear)",
            "formation_orm": "R occlusion, G roughness, B metallic (glTF)",
        },
        "sets": {},
        "sources": [],
    }
    for (asset, kind), (url, digest) in sorted(sources.FILES.items()):
        path = source_dir / asset / sources.local_name(asset, kind)
        if not path.exists():
            raise SystemExit(f"prepare_cave_kit: missing source {path}")
        actual = sha256(path)
        if actual != digest:
            raise SystemExit(f"prepare_cave_kit: {path.name} sha256 {actual} != pinned {digest}")
        report["sources"].append({"asset": asset, "map": kind, "url": url, "sha256": digest,
            "title": sources.ASSETS[asset]["title"], "authors": sources.ASSETS[asset]["authors"],
            "license": sources.LICENSE_URL, "retrieved": sources.RETRIEVED})
    reset_scene()
    build_sets(source_dir, out_dir, report)
    build_web(out_dir, work, report)
    reset_scene()
    lows = build_formations(source_dir, out_dir, work, report)
    flora = build_flora(out_dir, work, report)
    render_preview(lows + flora, work)
    reset_scene()
    build_fauna(out_dir, report)
    report["build_seconds"] = round(time.time() - started, 1)
    manifest = out_dir / "cave_kit.json"
    manifest.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    log("done", round(time.time() - started, 1), "s")


if __name__ == "__main__":
    main()
