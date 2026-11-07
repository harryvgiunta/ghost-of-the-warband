"""Rebuild the fitted devil skins and the fur tile.

Usage:
    python tools/build_devil_skins.py all
    python tools/build_devil_skins.py hell_goat

The fur tile is authored first (it is what the goat's body wears), then Blender
5.1 runs one process per species and reports the measured result. Override the
executable with ``IRONWOOD_BLENDER`` when the installed path differs.

After a rebuild, reimport in Godot and run the regressions:

    $Godot = '.\\\\.runtime\\\\godot\\\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
    & $Godot --headless --path . --script res://tests/corpse_regression.gd
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BLENDER = Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
SPECIES = ("hell_goat", "succubus", "spawn", "gargoyle")


def blender_path() -> Path:
    override = os.environ.get("IRONWOOD_BLENDER")
    candidate = Path(override) if override else DEFAULT_BLENDER
    if not candidate.exists():
        raise SystemExit(f"Blender not found at {candidate}; set IRONWOOD_BLENDER")
    return candidate


def build(species: str) -> dict:
    output = ROOT / "assets" / "characters" / "devils" / "fitted" / f"ironwood_devil_{species}.glb"
    command = [
        str(blender_path()),
        "--background",
        "--python-exit-code", "1",
        "--python", str(ROOT / "tools" / "prepare_devil_skins.py"),
        "--",
        species,
    ]
    print("BUILD_DEVIL_SKIN", species, flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"Blender failed for {species} ({result.returncode})")
    metadata_path = output.with_suffix(".json")
    if not metadata_path.exists():
        raise SystemExit(f"Missing metadata for {species}: {metadata_path}")
    return json.loads(metadata_path.read_text(encoding="utf-8"))


def main() -> None:
    argument = sys.argv[1] if len(sys.argv) > 1 else "all"
    wanted = list(SPECIES) if argument == "all" else [argument]
    for species in wanted:
        if species not in SPECIES:
            raise SystemExit(f"unknown fitted devil {species}")
    subprocess.run([sys.executable or "python", str(ROOT / "tools" / "devil_fur.py")],
                   cwd=ROOT, check=True)
    results = {species: build(species) for species in wanted}
    for species, metadata in results.items():
        print(
            f"DEVIL_SKIN_OK {species} tris={metadata['mesh_triangles']} "
            f"bones={metadata['bone_count']} fit={metadata['fit_scale']} "
            f"height={metadata['runtime_height']} images={metadata['embedded_images']} "
            f"stripped={metadata['removed_triangles']}"
        )


if __name__ == "__main__":
    main()
