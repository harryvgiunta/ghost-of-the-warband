"""Rebuild the Cinder devil asset.

Usage:
    python tools/build_cinder_devil.py

Runs Blender 5.1 in background mode, then reports the measured result. Unlike
the five source-based devils there is no texture pre-pass: every map is
rasterised inside Blender from the analytic fields in
``tools/cinder_devil_surface.py``, so no download and no Pillow/numpy pass
outside Blender is required.

Override the executable with ``IRONWOOD_BLENDER`` when the installed path
differs.

After a rebuild, reimport in Godot and run the regressions:

    $Godot = '.\\\\.runtime\\\\godot\\\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
    & $Godot --headless --path . --script res://tests/devil_regression.gd
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
import cinder_devil_styles as styles  # noqa: E402

MOB = "cinder_devil"


def blender_path() -> Path:
    override = os.environ.get("IRONWOOD_BLENDER")
    candidate = Path(override) if override else DEFAULT_BLENDER
    if not candidate.exists():
        raise SystemExit(f"Blender not found at {candidate}; set IRONWOOD_BLENDER")
    return candidate


def build() -> dict:
    output = styles.asset_path(MOB)
    command = [
        str(blender_path()),
        "--background",
        "--python-exit-code", "1",
        "--python", str(ROOT / "tools" / "prepare_cinder_devil.py"),
        "--",
        str(output),
    ]
    print("BUILD_CINDER", MOB, flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"Blender failed for {MOB} ({result.returncode})")
    metadata_path = output.with_suffix(".json")
    if not metadata_path.exists():
        raise SystemExit(f"Missing metadata for {MOB}: {metadata_path}")
    return json.loads(metadata_path.read_text(encoding="utf-8"))


def main() -> None:
    metadata = build()
    clips = ", ".join(
        f"{key} {value['duration']:.3f}s" for key, value in metadata["clips"].items()
    )
    print(
        f"CINDER_OK {MOB} tris={metadata['mesh_triangles']} "
        f"bones={metadata['bone_count']} images={metadata['embedded_images']} {clips}"
    )


if __name__ == "__main__":
    main()
