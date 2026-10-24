"""Shared palettes and source-map recipes for the source-based devil rebuild.

The five devils are original *assemblies and modifications* of the CC0
Quaternius character sources already licensed by this project (the same base
meshes, outfits, hair and animations used by the ranger).  This module only
describes how each mob recolours and details those sources; the Blender
pipeline does the geometry, rigging, animation and export.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / ".runtime" / "character-source"
BASE_UE = SOURCE / "Universal Base Characters[Standard]" / "Base Characters" / "Godot - UE"
BASE_TEX = SOURCE / "Universal Base Characters[Standard]" / "Base Characters" / "Textures"
OUTFIT = SOURCE / "Modular Character Outfits - Fantasy[Standard]" / "Exports" / "glTF (Godot-Unreal)"
OUTFIT_DIR = OUTFIT / "Outfits"
HAIR = SOURCE / "Universal Base Characters[Standard]" / "Hairstyles" / "Rigged to Head Bone" / "glTF (Godot -Unreal)"

# Source maps -----------------------------------------------------------------
SKIN = {
    "female_light": {
        "albedo": BASE_TEX / "T_Superhero_Female_Light_BaseColor.png",
        "normal": BASE_UE / "T_Superhero_Female_Normal.png",
        "roughness": BASE_UE / "T_Superhero_Female_Roughness.png",
    },
    "female_dark": {
        "albedo": BASE_UE / "T_Superhero_Female_Dark_BaseColor.png",
        "normal": BASE_UE / "T_Superhero_Female_Normal.png",
        "roughness": BASE_UE / "T_Superhero_Female_Roughness.png",
    },
    "male_dark": {
        "albedo": BASE_UE / "T_Superhero_Male_Dark.png",
        "normal": BASE_UE / "T_Superhero_Male_Normal.png",
        "roughness": BASE_UE / "T_Superhero_Male_Roughness.png",
    },
}

LEATHER = {
    "albedo": OUTFIT_DIR / "T_Ranger_BaseColor.png",
    "normal": OUTFIT_DIR / "T_Ranger_Normal.png",
    "orm": OUTFIT_DIR / "T_Ranger_ORM.png",
}

HAIR_SOURCE = {
    "female_long": {
        "albedo": BASE_UE / "T_Hair_2_BaseColor.png",
        "normal": BASE_UE / "T_Hair_2_Normal.png",
    },
    "male_beard": {
        "albedo": BASE_UE / "T_Hair_1_BaseColor.png",
        "normal": BASE_UE / "T_Hair_1_Normal.png",
    },
}

EYE_SOURCE = {
    "albedo": BASE_UE / "T_Eye_Brown.png",
    "normal": BASE_UE / "T_Eye_Normal.png",
}

# Per-mob look ---------------------------------------------------------------
# Colours are display/sRGB tints.  Texture generators retain source luminance
# and detail; these values only move hue/value into the devil palette.
STYLES = {
    "succubus": {
        "skin_source": "female_light",
        "skin_target": (0.78, 0.58, 0.58),
        "skin_desaturate": 0.55,
        "skin_mottle": 0.10,
        "skin_veins": 0.14,
        "skin_scars": 5,
        "skin_grime": 0.07,
        "leather_tint": (0.17, 0.050, 0.060), "leather_gain": 4.4,
        "leather_grime": 0.18,
        "hair_tint": (0.055, 0.018, 0.022),
        "eye_iris": (1.0, 0.48, 0.06),
        "eye_emission": 2.4,
        "horn": ("ram", (0.004, 0.003, 0.003), (0.085, 0.075, 0.070)),
        "membrane": (0.20, 0.035, 0.045),
        "cloth": (0.17, 0.055, 0.065),
        "surfaces": ["crimson-grey demon skin", "black oxblood leather harness", "bat-wing membrane", "keratin horns"],
    },
    "hell_goat": {
        "skin_source": "male_dark",
        "skin_target": (0.016, 0.014, 0.013),
        "skin_desaturate": 1.0, "skin_blackout": True,
        "skin_mottle": 0.02,
        "skin_veins": 0.0,
        "skin_scars": 2,
        "skin_grime": 0.03,
        "leather_tint": (0.30, 0.20, 0.12), "leather_gain": 5.0,
        "leather_grime": 0.30,
        "hair_tint": (0.045, 0.030, 0.022),
        "eye_iris": (1.0, 0.28, 0.035),
        "eye_emission": 2.8,
        "horn": ("ram", (0.004, 0.003, 0.003), (0.085, 0.075, 0.070)),
        "bone": (0.075, 0.070, 0.065),
        "fur": (0.012, 0.010, 0.009),
        "cloth": (0.18, 0.12, 0.08),
        "metal": ((0.030, 0.028, 0.025), (0.15, 0.14, 0.12)),
        "surfaces": ["goat skull mask and ram horns", "shaggy black fur mantle", "weathered ranger leather", "cloven hoof boots"],
    },
    "gargoyle": {
        "skin_source": "male_dark",
        "skin_target": (0.45, 0.46, 0.44),
        "skin_desaturate": 0.80,
        "skin_mottle": 0.06,
        "skin_veins": 0.0,
        "skin_scars": 0,
        "skin_grime": 0.10,
        "stone": (0.20, 0.21, 0.20),
        "moss": (0.19, 0.24, 0.10),
        "ember": (1.0, 0.20, 0.025),
        "eye_iris": (1.0, 0.12, 0.02),
        "eye_emission": 3.2,
        "horn": ("stone", (0.14, 0.15, 0.14), (0.48, 0.47, 0.43)),
        "cloth": (0.18, 0.19, 0.18),
        "metal": ((0.028, 0.032, 0.036), (0.16, 0.18, 0.20)),
        "surfaces": ["basalt stone anatomy", "cracked stone wings", "moss and ember fissures", "glowing eyes"],
    },
    "spawn": {
        "skin_source": "female_light",
        "skin_target": (0.60, 0.67, 0.53),
        "skin_desaturate": 0.62,
        "skin_mottle": 0.16,
        "skin_veins": 0.26,
        "skin_scars": 7,
        "skin_grime": 0.22,
        "leather_tint": (0.14, 0.09, 0.06), "leather_gain": 4.2,
        "leather_grime": 0.30,
        "hair_tint": (0.04, 0.03, 0.024),
        "eye_iris": (1.0, 0.36, 0.03),
        "eye_emission": 3.0,
        "horn": ("small", (0.08, 0.05, 0.035), (0.64, 0.56, 0.42)),
        "cloth": (0.18, 0.13, 0.09),
        "surfaces": ["pale sickly spawn skin", "ragged loincloth", "small horns and needle claws"],
    },
    "beast": {
        "fur": (0.075, 0.055, 0.042),
        "ember": (1.0, 0.16, 0.015),
        "eye_iris": (1.0, 0.22, 0.02),
        "eye_emission": 3.6,
        "horn": ("beast", (0.055, 0.040, 0.030), (0.46, 0.40, 0.30)),
        "surfaces": ["charred black fur", "bony spine ridge and horns", "ember cracks", "glowing eyes"],
    },
}

# Texture output names used by the Blender pipeline.
TEXTURE_NAMES = (
    "skin_albedo", "skin_normal", "skin_roughness",
    "leather_albedo", "leather_normal", "leather_roughness", "leather_metallic",
    "hair_albedo", "hair_normal",
    "eye_albedo", "eye_emission", "eye_normal",
    "horn_albedo", "horn_normal", "horn_roughness",
    "bone_albedo", "bone_normal", "bone_roughness",
    "membrane_albedo", "membrane_normal", "membrane_roughness",
    "cloth_albedo", "cloth_normal", "cloth_roughness",
    "stone_albedo", "stone_normal", "stone_roughness", "stone_emission",
    "metal_albedo", "metal_normal", "metal_roughness", "metal_metallic",
    "fur_albedo", "fur_normal", "fur_roughness",
    "beast_coat_albedo", "beast_coat_normal", "beast_coat_roughness", "beast_coat_emission",
)
