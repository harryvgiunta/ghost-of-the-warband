"""Rebuild the Unholy Forest mobset assets.

Usage:
    python tools/build_forest.py all
    python tools/build_forest.py hollow_warden

Runs one Blender process per mob (a fresh scene per asset keeps the rig
globals honest), then reports the measured result. Override the executable
with IRONWOOD_BLENDER when the installed path differs.

After a rebuild, reimport in Godot and run the regression:

    $Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
    & $Godot --headless --path . --script res://tests/forest_mobs_regression.gd
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BLENDER = Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forest_styles as styles  # noqa: E402


def blender_path() -> Path:
    override = os.environ.get("IRONWOOD_BLENDER")
    candidate = Path(override) if override else DEFAULT_BLENDER
    if not candidate.exists():
        raise SystemExit(f"Blender not found at {candidate}; set IRONWOOD_BLENDER")
    return candidate


def build(mob: str) -> dict:
    output = styles.asset_path(mob)
    command = [
        str(blender_path()),
        "--background",
        "--python-exit-code", "1",
        "--python", str(ROOT / "tools" / "prepare_forest_mobs.py"),
        "--",
        mob,
        str(output),
    ]
    print("BUILD_FOREST", mob, flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"Blender failed for {mob} ({result.returncode})")
    metadata_path = output.with_suffix(".json")
    if not metadata_path.exists():
        raise SystemExit(f"Missing metadata for {mob}: {metadata_path}")
    return json.loads(metadata_path.read_text(encoding="utf-8"))


def main() -> None:
    argument = sys.argv[1] if len(sys.argv) > 1 else "all"
    mobs = styles.MOB_ORDER if argument == "all" else [argument]
    results = {}
    for mob in mobs:
        if mob not in styles.MOBS:
            raise SystemExit(f"unknown mob {mob}")
        results[mob] = build(mob)
    for mob, metadata in results.items():
        clips = ", ".join(
            f"{key} {value['duration']:.3f}s" for key, value in metadata["clips"].items()
        )
        print(
            f"FOREST_OK {mob} tris={metadata['mesh_triangles']} "
            f"bones={metadata['bone_count']} images={metadata['embedded_images']} {clips}"
        )


if __name__ == "__main__":
    main()
