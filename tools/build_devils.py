#!/usr/bin/env python3
"""One-command rebuild for the source-based devil mobs.

    python tools/build_devils.py all
    python tools/build_devils.py succubus hell_goat

Runs the system-Python texture pass (Pillow + numpy), then Blender 5.1 to
assemble/skin/animate/export the GLBs.  Override the Blender executable with
IRONWOOD_BLENDER if it is not installed at the default path.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOBS = ["succubus", "hell_goat", "gargoyle", "spawn", "beast"]
DEFAULT_BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")


def blender_path() -> Path:
    candidates = [
        Path(os.environ["IRONWOOD_BLENDER"]) if os.environ.get("IRONWOOD_BLENDER") else None,
        DEFAULT_BLENDER,
        ROOT / ".runtime" / "blender" / "blender.exe",
        Path(shutil.which("blender") or ""),
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return candidate
    raise SystemExit("Blender 5.1 not found. Set IRONWOOD_BLENDER to blender.exe.")


def parse(argv: list[str]) -> list[str]:
    argv = [a for a in argv if a != "--"]
    if not argv or argv[0] == "all":
        return list(MOBS)
    unknown = [m for m in argv if m not in MOBS]
    if unknown:
        raise SystemExit(f"Unknown mob(s): {', '.join(unknown)}")
    return argv


def run(cmd: list[str]) -> None:
    print("RUN", " ".join(str(c) for c in cmd), flush=True)
    result = subprocess.run(cmd, cwd=ROOT)
    if result.returncode:
        raise SystemExit(result.returncode)


def main() -> None:
    mobs = parse(sys.argv[1:])
    run([sys.executable, "tools/devil_source_textures.py", "--", *mobs])
    run([str(blender_path()), "--background", "--python-exit-code", "1",
         "--python", "tools/prepare_devil_sources.py", "--", *mobs])


if __name__ == "__main__":
    main()
