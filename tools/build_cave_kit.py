"""Rebuild the Weeping Hollow's cave kit.

Usage:
    python tools/build_cave_kit.py

1. Downloads every pinned CC0 Poly Haven scan in `tools/cave_kit_sources.py` into
   the ignored `.runtime/cave-source/<asset>/` (skipping files already present with
   the pinned SHA-256) and refuses to continue on any digest mismatch.
2. Runs Blender 5.1 in background mode on `tools/prepare_cave_kit.py`, which
   writes `assets/world/cave/` (the tileable rock sets, the formation and fauna
   GLBs, the web and `cave_kit.json`) and leaves intermediates plus
   `preview_formations.png` in `.runtime/cave-build/`.

Override the executable with ``IRONWOOD_BLENDER`` when the installed path
differs. After a rebuild, reimport in Godot:

    $Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BLENDER = Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
SOURCE_DIR = ROOT / ".runtime" / "cave-source"
WORK_DIR = ROOT / ".runtime" / "cave-build"
OUT_DIR = ROOT / "assets" / "world" / "cave"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cave_kit_sources as sources  # noqa: E402


def blender_path() -> Path:
    override = os.environ.get("IRONWOOD_BLENDER")
    candidate = Path(override) if override else DEFAULT_BLENDER
    if not candidate.exists():
        raise SystemExit(f"Blender not found at {candidate}; set IRONWOOD_BLENDER")
    return candidate


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch_sources() -> None:
    for (asset, kind), (url, pinned) in sorted(sources.FILES.items()):
        target = SOURCE_DIR / asset / sources.local_name(asset, kind)
        if target.exists() and sha256(target) == pinned:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        print("FETCH", url, flush=True)
        request = urllib.request.Request(url, headers={"User-Agent": "ironwood-cave-kit/1.0"})
        with urllib.request.urlopen(request, timeout=300) as response:
            target.write_bytes(response.read())
        actual = sha256(target)
        if actual != pinned:
            raise SystemExit(f"{target.name}: sha256 {actual} does not match the pinned {pinned}")


def build() -> dict:
    command = [
        str(blender_path()),
        "--background",
        "--factory-startup",
        "--python-exit-code", "1",
        "--python", str(ROOT / "tools" / "prepare_cave_kit.py"),
        "--",
        str(SOURCE_DIR),
        str(OUT_DIR),
        str(WORK_DIR),
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"Blender failed ({result.returncode})")
    return json.loads((OUT_DIR / "cave_kit.json").read_text(encoding="utf-8"))


def main() -> None:
    fetch_sources()
    manifest = build()
    pieces = manifest["formations"]["pieces"]
    print(f"CAVE_KIT_OK sets={len(manifest['sets'])} formations={len(pieces)} "
        f"formation_tris={sum(p['triangles'] for p in pieces.values())} "
        f"fauna={len(manifest['fauna']['pieces'])} seconds={manifest['build_seconds']}")


if __name__ == "__main__":
    main()
