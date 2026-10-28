"""Canonical recipes for the Unholy Forest mobset.

This module is the single source of truth shared by the two authoring stages:

* ``tools/forest_surface.py`` (pure numpy) turns a rest-space point into a
  bark/cloth/leather/bone/antler/moss/void/ember surface sample. ``tools/prepare_forest_mobs.py``
  (Blender) rasterises those samples into each material's UV atlas, then builds
  the rig, the clips and the GLB.

Nothing here touches Blender or the filesystem beyond the ignored build
workspace, so both stages can import it cheaply.

Three original mobs inhabit the frontier forest outside Hearthstead:

``hollow_warden``   a hooded, antlered thing of hanging grave-cloth. Its hood
                    is a hole in the world with two embers in it.
``ossuary_stalker`` a gaunt humanoid wrapped in cured hide, plated with the
                    skeleton it found: antlered skull, bone ribs and sternum,
                    bone hands and toe caps, a hide scarf and loincloth.
``gallowsroot``     a tall wooden man grown out of bark: humanoid body with hard
                    bark plates, a knotty head split into a glowing face
                    fissure, a branch-antler crown and root-claw toes.

Every model, texture and clip is original work authored by
``tools/prepare_forest_mobs.py``; the design sheet supplied with the request
was ink-and-wash inspiration and is not redistributed or used as a build input.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT / ".runtime" / "forest-source"
CHARACTER_ROOT = ROOT / "assets" / "characters" / "forest"

FPS = 60
SEED = 20_261_025

# ---------------------------------------------------------------------------
# Surfaces
#
# ``size`` is the atlas edge for that material. Texel density is what matters:
# bark and cloth cover the largest silhouette area, bone and antler carry the
# read at close range, void and ember are tiny emissive accents.
#
# ``normal`` is the world-space normal strength multiplier applied when the
# height field is differentiated; ``rough`` the roughness range the sampler
# must stay inside.

SURFACES: dict[str, dict] = {
    "bark": {"size": 2048, "normal": 2.35, "rough": (0.62, 0.94)},
    "cloth": {"size": 2048, "normal": 1.55, "rough": (0.78, 0.99)},
    "leather": {"size": 1024, "normal": 1.45, "rough": (0.55, 0.90)},
    "bone": {"size": 1024, "normal": 1.85, "rough": (0.34, 0.78)},
    "antler": {"size": 1024, "normal": 1.70, "rough": (0.28, 0.66)},
    "moss": {"size": 1024, "normal": 2.10, "rough": (0.84, 1.0)},
    "void": {"size": 512, "normal": 0.65, "rough": (0.90, 1.0)},
    "ember": {"size": 256, "normal": 0.90, "rough": (0.30, 0.55)},
}

# Material node names in Blender and in the exported glTF. ``Forest_Void`` and
# ``Forest_Ember`` carry emission; the runtime raises their energy.
MATERIAL_PREFIX = "Forest_"


def material_name(surface: str) -> str:
    return MATERIAL_PREFIX + surface.capitalize()


# ---------------------------------------------------------------------------
# Mobs
#
# ``clips`` is the animation contract. The Blender stage bakes exactly these
# names and durations at 60 Hz; ``tests/forest_mobs_regression.gd`` re-measures
# them from the imported GLB and every profile in ``scripts/forest_mob.gd``
# uses the same impact time so the authored strike lands on the damage frame.
#
# ``stride`` is the full-cycle ground travel of one foot in metres and ``duty``
# the fraction of the cycle a foot stays planted. ``foot_lift`` is the peak
# clearance of a swinging foot.

MOBS: dict[str, dict] = {
    "hollow_warden": {
        "display": "Hollow warden",
        "prefix": "Warden",
        "summary": "Hooded antlered grave-cloth with an ember stare.",
        "surfaces": ["cloth", "antler", "bone", "moss", "void", "ember"],
        "clips": {
            "idle": {"duration": 2.800, "loop": True},
            "walk": {"duration": 1.400, "loop": True},
            "run": {"duration": 0.800, "loop": True},
            "attack": {"duration": 1.600, "loop": False, "impact": 0.780},
            "hit": {"duration": 0.500, "loop": False, "impact": 0.120},
            "death": {"duration": 1.450, "loop": False},
            "attack_slash": {"duration": 1.350, "loop": False, "impact": 0.660},
            "attack_stab": {"duration": 1.100, "loop": False, "impact": 0.500},
            "block": {"duration": 1.200, "loop": True},
            "stagger": {"duration": 0.600, "loop": False},
            "crouch": {"duration": 2.400, "loop": True},
        },
        "stride": {"walk": 0.92, "run": 1.72},
        "duty": {"walk": 0.58, "run": 0.42},
        "foot_lift": {"walk": 0.075, "run": 0.145},
        "palette": {
            "cloth": {
                "deep": "#0B0908",
                "weft": "#191114",
                "warp": "#241419",
                "sheen": "#553039",
                "fray": "#63463C",
            },
            "antler": {
                "core": "#1E1311",
                "ridge": "#3C2921",
                "tip": "#6E5A40",
                "stain": "#4A3020",
            },
            "bone": {
                "pale": "#C3B49A",
                "mid": "#9A876C",
                "stain": "#5E4632",
                "crack": "#33251A",
            },
            "moss": {
                "deep": "#20241A",
                "body": "#3A3F26",
                "tip": "#5A5F3C",
            },
            "void": {
                "depth": "#030203",
                "floor": "#0C0709",
                "rim": "#2A1620",
            },
            "ember": {
                "core": "#FFD9A0",
                "iris": "#E8592A",
                "outer": "#8C2312",
            },
        },
    },
    "ossuary_stalker": {
        "display": "Ossuary stalker",
        "prefix": "Stalker",
        "summary": "Bark-grown skeleton in a rotted grave shroud.",
        "surfaces": ["cloth", "leather", "bone", "antler", "moss", "void", "ember"],
        "clips": {
            "idle": {"duration": 2.400, "loop": True},
            "walk": {"duration": 1.100, "loop": True},
            "run": {"duration": 0.700, "loop": True},
            "attack": {"duration": 1.250, "loop": False, "impact": 0.550},
            "hit": {"duration": 0.400, "loop": False, "impact": 0.100},
            "death": {"duration": 1.100, "loop": False},
        },
        "stride": {"walk": 0.86, "run": 1.68},
        "duty": {"walk": 0.55, "run": 0.40},
        "foot_lift": {"walk": 0.080, "run": 0.150},
        "palette": {
            "bone": {
                "pale": "#BCAC8E",
                "mid": "#8F7E66",
                "stain": "#57422C",
                "crack": "#33251C",
            },
            "bark": {
                "core": "#241713",
                "plate": "#3D2A24",
                "ridge": "#6E5A55",
                "growth": "#8A7268",
                "lichen": "#5A5C46",
            },
            "antler": {
                "core": "#2E201C",
                "ridge": "#584036",
                "tip": "#B8A184",
                "stain": "#7A5236",
            },
            "cloth": {
                "deep": "#1E1512",
                "weft": "#33241F",
                "warp": "#402C25",
                "sheen": "#65432F",
                "fray": "#8A674C",
            },
            "leather": {
                "hide": "#3A2721",
                "worn": "#6B4A38",
                "crease": "#1A1110",
                "sheen": "#7E5438",
                "stitch": "#93805C",
            },
            "moss": {
                "deep": "#232817",
                "body": "#3E4529",
                "tip": "#666B44",
            },
            "void": {
                "depth": "#020202",
                "floor": "#0A0708",
                "rim": "#251420",
            },
            "ember": {
                "core": "#FFCE8E",
                "iris": "#DC4A22",
                "outer": "#7A1B0E",
            },
        },
    },
    "gallowsroot": {
        "display": "Gallowsroot",
        "prefix": "Gallowsroot",
        "summary": "A dead tree that walks, split down the trunk and burning inside.",
        "surfaces": ["bark", "cloth", "leather", "moss", "antler", "bone", "void", "ember"],
        "clips": {
            "idle": {"duration": 3.200, "loop": True},
            "walk": {"duration": 1.800, "loop": True},
            "run": {"duration": 1.000, "loop": True},
            "attack": {"duration": 2.100, "loop": False, "impact": 1.050},
            "hit": {"duration": 0.600, "loop": False, "impact": 0.140},
            "death": {"duration": 1.800, "loop": False},
        },
        "stride": {"walk": 1.35, "run": 2.40},
        "duty": {"walk": 0.60, "run": 0.46},
        "foot_lift": {"walk": 0.125, "run": 0.240},
        "palette": {
            "bark": {
                "core": "#241713",
                "plate": "#432E26",
                "ridge": "#7E6763",
                "growth": "#A38A7C",
                "lichen": "#5E6348",
            },
            "cloth": {
                "deep": "#201A16",
                "weft": "#382C24",
                "warp": "#45352B",
                "sheen": "#6B4E38",
                "fray": "#8F7154",
            },
            "leather": {
                "hide": "#2E211C",
                "worn": "#5A4034",
                "crease": "#150E0C",
                "sheen": "#6E4A32",
                "stitch": "#857051",
            },
            "moss": {
                "deep": "#1E2314",
                "body": "#394024",
                "tip": "#5F653E",
            },
            "antler": {
                "core": "#251815",
                "ridge": "#4B322B",
                "tip": "#9C8670",
                "stain": "#6B4830",
            },
            "bone": {
                "pale": "#B6A78C",
                "mid": "#8E7C63",
                "stain": "#58422F",
                "crack": "#2E2118",
            },
            "void": {
                "depth": "#020101",
                "floor": "#140807",
                "rim": "#5A1E10",
            },
            "ember": {
                "core": "#FFE0AE",
                "iris": "#F0652C",
                "outer": "#9A2A10",
            },
        },
    },
}

MOB_ORDER = ["hollow_warden", "ossuary_stalker", "gallowsroot"]


def clip_name(mob: str, key: str) -> str:
    """``Warden_Idle``, ``Stalker_Attack``, ``Warden_Attack_Slash``.

    Every underscore-separated word is capitalised, so a compound key names the
    same clip here, in the GLB and in the metadata. No ``_Loop`` suffix: Godot's
    glTF importer strips a trailing ``_Loop`` from animation names, so a
    suffix-based name would silently import as a different name than the
    metadata records. Loop semantics live in the adjacent JSON and are applied
    by the runtime controller.
    """
    prefix = MOBS[mob]["prefix"]
    words = "_".join(word.capitalize() for word in key.split("_"))
    return f"{prefix}_{words}"


def mob_dir(mob: str) -> Path:
    return SOURCE_ROOT / mob


def asset_path(mob: str) -> Path:
    return CHARACTER_ROOT / f"ironwood_{mob}.glb"


def palette(mob: str, surface: str) -> dict[str, str]:
    return MOBS[mob]["palette"][surface]
