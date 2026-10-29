"""Rebuild the Naked armor set (one Blender process, then a measured summary).

Usage:
    python tools/build_naked_armor.py

The set's body is the CC0 Quaternius ``Superhero_Male_FullBody`` sculpt, so the
Universal Base Characters archive must be unpacked into
``.runtime/character-source`` first (assets/characters/LICENSE.txt records the
URL and licence). The Blender stage imports the shipped Ranger GLB for the rig
and the head, splits the source body into the four slot pieces, fits and
authors the shirt and shorts, bakes their cloth maps and exports the GLB.

Override the Blender executable with IRONWOOD_BLENDER when the installed path
differs.  The Blender stage fails the process (``--python-exit-code 1``) when a
piece is unweighted, claims a bone the ranger skeleton does not have, leaves an
empty vertex group, breaks the triangle budget, or crosses the face above the
jaw (the neck passes through the head's opening by design); this wrapper then
re-raises with the same non-zero exit.

After a rebuild, reimport in Godot and check the kit on the rig:

    $Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BLENDER = Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
OUTPUT = ROOT / "assets" / "characters" / "armor" / "ironwood_naked.glb"


def blender_path() -> Path:
    override = os.environ.get("IRONWOOD_BLENDER")
    candidate = Path(override) if override else DEFAULT_BLENDER
    if not candidate.exists():
        raise SystemExit(f"Blender not found at {candidate}; set IRONWOOD_BLENDER")
    return candidate


def main() -> None:
    command = [
        str(blender_path()),
        "--background",
        "--python-exit-code", "1",
        "--python", str(ROOT / "tools" / "prepare_naked_armor.py"),
    ]
    print("BUILD_NAKED", flush=True)
    started = time.perf_counter()
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace")
    elapsed = time.perf_counter() - started
    if result.returncode != 0:
        raise SystemExit(f"Blender failed for the Naked set ({result.returncode})")
    metadata_path = OUTPUT.with_suffix(".json")
    if not metadata_path.exists():
        raise SystemExit(f"Missing metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    for name, piece in metadata["pieces"].items():
        print(
            f"NAKED_OK {name} slot={piece['slot']} tris={piece['triangles']} "
            f"bones={','.join(piece['bones'])}"
        )
    images = metadata.get("image_bytes", {})
    print(
        f"NAKED_TOTAL tris={metadata['total_triangles']} "
        f"budget={metadata['triangle_budget']} bones={metadata['bone_count']} "
        f"images={metadata['embedded_images']} materials={len(metadata['materials'])} "
        f"atlas={max(metadata['atlas_size'].values())} "
        f"bytes={OUTPUT.stat().st_size} "
        f"texture_bytes={sum(images.values())} seconds={elapsed:.1f}"
    )
    for name, size in sorted(images.items()):
        print(f"NAKED_ATLAS {name} bytes={size}")


if __name__ == "__main__":
    main()
