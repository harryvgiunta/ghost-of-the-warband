"""Build the five Ironwood devil mobs as textured, rigged, animated GLBs.

Usage (Blender 5.1):
    blender --background --python-exit-code 1 --python tools/prepare_devils.py -- all
    blender --background --python-exit-code 1 --python tools/prepare_devils.py -- hell_goat
    blender --background --python-exit-code 1 --python tools/prepare_devils.py -- succubus spawn beast gargoyle

Source .blend files, PBR atlases and capture sheets are written into the
ignored `.runtime/devil-source/<mob>/` workspace. Only the GLB, its metadata
JSON and the Godot import file belong in `assets/characters/devils/`.
"""

from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

from devil_pipeline import run_mob  # noqa: E402

MOBS = {
    "hell_goat": "devils.hell_goat",
    "succubus": "devils.succubus",
    "spawn": "devils.spawn",
    "beast": "devils.beast",
    "gargoyle": "devils.gargoyle",
}


def parse_args() -> list[str]:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    if not argv or argv[0] == "all":
        return list(MOBS)
    unknown = [name for name in argv if name not in MOBS]
    if unknown:
        raise SystemExit(f"Unknown mob(s): {', '.join(unknown)}. Choose from {', '.join(MOBS)}.")
    return argv


def build(mob_id: str) -> dict:
    module = importlib.import_module(MOBS[mob_id])
    spec = module.SPEC
    source = ROOT / ".runtime" / "devil-source" / mob_id
    output = ROOT / "assets" / "characters" / "devils" / f"ironwood_{mob_id}.glb"
    output.parent.mkdir(parents=True, exist_ok=True)
    print("DEVIL_BUILD_BEGIN", mob_id, source, output)
    metadata = run_mob(spec, source, output, previews=True)
    return {
        "mob": mob_id,
        "glb": str(output.relative_to(ROOT)),
        "metadata": str(output.with_suffix(".json").relative_to(ROOT)),
        "triangles": metadata["mesh_triangles"],
        "bones": metadata["bone_count"],
        "clips": {key: entry["duration"] for key, entry in metadata["clips"].items()},
    }


def main() -> None:
    results = []
    for mob_id in parse_args():
        results.append(build(mob_id))
    summary_path = ROOT / ".runtime" / "devil-source" / "build_summary.json"
    summary_path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print("DEVIL_BUILD_SUMMARY", json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
