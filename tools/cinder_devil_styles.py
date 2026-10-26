"""Canonical recipe for the Cinder devil.

The cinder devil is the pack enemy that circles the frontier in threes and
fives. It used to be a half-metre primitive figure assembled from ``Geo``
spheres at runtime; it is now an original authored creature in the same
deterministic Blender route as the Unholy Forest mobset.

``tools/cinder_devil_surface.py`` turns a rest-space point into a charred,
ash-crusted or ember-lit surface sample. ``tools/prepare_cinder_devil.py``
rasterises those samples into each material's UV atlas, then builds the rig,
the seven clips and the GLB.

This module duck-types ``tools/forest_styles.py`` exactly: the Blender stage is
shared, and it only ever asks a style module for ``SURFACES``,
``MATERIAL_PREFIX``, ``material_name``, ``MOBS``, ``clip_name``, ``mob_dir``,
``asset_path`` and ``palette``.

Every mesh, texture and clip here is original work authored in this repository.
No third-party model, texture or motion is used.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT / ".runtime" / "cinder-source"
CHARACTER_ROOT = ROOT / "assets" / "characters" / "devils"

FPS = 60
SEED = 20_261_026

# ---------------------------------------------------------------------------
# Surfaces
#
# ``size`` is the atlas edge for that material. Char carries the whole body
# silhouette and must hold texel-scale fissures; ash, bone and leather are
# smaller accents; void and ember are tiny emissive reads that need density,
# not area. ``normal`` is the height-field strength the bake differentiates at
# and ``rough`` the range the sampler must stay inside.

SURFACES: dict[str, dict] = {
    "char": {"size": 2048, "normal": 2.55, "rough": (0.52, 0.96)},
    "ash": {"size": 1024, "normal": 1.90, "rough": (0.72, 0.99)},
    "bone": {"size": 1024, "normal": 1.85, "rough": (0.34, 0.80)},
    "horn": {"size": 1024, "normal": 1.70, "rough": (0.24, 0.62)},
    "leather": {"size": 1024, "normal": 1.45, "rough": (0.55, 0.92)},
    "cloth": {"size": 1024, "normal": 1.55, "rough": (0.80, 1.0)},
    "void": {"size": 512, "normal": 0.65, "rough": (0.90, 1.0)},
    "ember": {"size": 512, "normal": 0.90, "rough": (0.26, 0.58)},
}

# Material node names in Blender and in the exported glTF. Every character
# carries its own prefix so a reimported asset cannot collide with the forest
# set's ``Forest_*`` materials at runtime.
MATERIAL_PREFIX = "Cinder_"


def material_name(surface: str) -> str:
    return MATERIAL_PREFIX + surface.capitalize()


# ---------------------------------------------------------------------------
# The mob
#
# ``clips`` is the animation contract. The Blender stage bakes exactly these
# names and durations at 60 Hz. ``scripts/devil_visual.gd`` maps the pack state
# machine onto them, so the non-looping clips carry an ``impact`` that matches
# the frame the gameplay clock deals damage on:
#
#   attack  WINDUP 0.30 + STRIKE damage at 0.08  = 0.38 s
#   shoot   SHOOT damage at                      = 0.30 s
#
# ``stride`` is the full-cycle ground travel of one foot in metres, ``duty``
# the fraction of the cycle a foot stays planted, ``foot_lift`` the peak
# clearance of a swinging foot.

MOBS: dict[str, dict] = {
    "cinder_devil": {
        "display": "Cinder devil",
        "prefix": "Cinder",
        "summary": "A gaunt charred horror with embers burning in a split ribcage.",
        "surfaces": ["char", "ash", "horn", "bone", "leather", "cloth", "void", "ember"],
        "clips": {
            "idle": {"duration": 2.200, "loop": True},
            "walk": {"duration": 0.900, "loop": True},
            "run": {"duration": 0.620, "loop": True},
            "attack": {"duration": 0.800, "loop": False, "impact": 0.380},
            "shoot": {"duration": 0.550, "loop": False, "impact": 0.300},
            "hit": {"duration": 0.360, "loop": False, "impact": 0.100},
            "death": {"duration": 0.900, "loop": False},
        },
        "stride": {"walk": 0.78, "run": 1.62},
        "duty": {"walk": 0.56, "run": 0.40},
        "foot_lift": {"walk": 0.070, "run": 0.135},
        "palette": {
            "char": {
                "soot": "#0D0A09",
                "carbon": "#1E1614",
                "plate": "#35271F",
                "seam": "#0F0A08",
                "sheen": "#4E3A2E",
                "ember_seam": "#7E2409",
            },
            "ash": {
                "pale": "#74706A",
                "grey": "#6A655F",
                "dark": "#45413D",
                "sift": "#8A857C",
            },
            "bone": {
                "pale": "#B9A98D",
                "mid": "#8C7A61",
                "stain": "#4E3728",
                "crack": "#281B14",
            },
            "horn": {
                "core": "#0B0706",
                "ridge": "#20140F",
                "tip": "#5E4838",
                "stain": "#331C14",
            },
            "leather": {
                "hide": "#241814",
                "worn": "#463029",
                "crease": "#100A09",
                "sheen": "#5A3A2C",
                "stitch": "#6E5A42",
            },
            "cloth": {
                "deep": "#1B1310",
                "weft": "#30201A",
                "warp": "#3C2820",
                "sheen": "#573A2A",
                "fray": "#6E4832",
            },
            "void": {
                "depth": "#010101",
                "floor": "#070303",
                "rim": "#2E0C06",
            },
            "ember": {
                "core": "#FFD79B",
                "iris": "#F2551C",
                "outer": "#7E1A08",
            },
        },
    },
}

MOB_ORDER = ["cinder_devil"]


def clip_name(mob: str, key: str) -> str:
    """``Cinder_Idle``, ``Cinder_Attack``.

    No ``_Loop`` suffix: Godot's glTF importer strips a trailing ``_Loop`` from
    animation names, so the clips are named ``<Prefix>_<Clip>`` and the runtime
    controller owns loop modes.
    """
    return f"{MOBS[mob]['prefix']}_{key.capitalize()}"


def mob_dir(mob: str) -> Path:
    return SOURCE_ROOT / mob


def asset_path(mob: str) -> Path:
    return CHARACTER_ROOT / f"ironwood_{mob}.glb"


def palette(mob: str, surface: str) -> dict[str, str]:
    return MOBS[mob]["palette"][surface]
