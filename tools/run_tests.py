"""Run the Ironwood regression suite in parallel.

Each test gets an isolated APPDATA (so user:// saves and NetCache do not race),
and the two long deterministic tests run with a fixed simulated clock so the
suite finishes in about a minute instead of several. Failed tests are retried
once, sequentially, to absorb timing flakes from running 22 Godot processes at
once. Fixed UDP ports are unique across the list: 7811, 7895-7899.

Usage:
    python tools/run_tests.py
    GODOT_PATH=/path/to/godot python tools/run_tests.py
"""
import concurrent.futures
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = [
    "rig_regression",
    "draw_combat_regression",
    "projectile_regression",
    "gameplay_regression",
    "melee_roll_regression",
    "action_pose_regression",
    "weapon_input_regression",
    "arm_clearance_regression",
    "network_input_regression",
    "cover_movement_regression",
    "running_slide_regression",
    "wolf_regression",
    "devil_regression",
    "devil_mobs_regression",
    "forest_mobs_regression",
    "makeshift_gear_regression",
    "swing_reach_regression",
    "block_clash_regression",
    "hitbox_regression",
    "dagger_regression",
    "throw_regression",
    "shield_regression",
    "title_menu_regression",
    "town_services_regression",
    "paperdoll_regression",
    "world_ui_regression",
    "dual_wield_regression",
    "combat_expansion_regression",
    "world_art_regression",
    "delve_regression",
    "delve_entry_regression",
    "delve_network_regression",
    "world_network_regression",
    "ranger_clone_regression",
    "consumable_regression",
    "blood_regression",
    "corpse_regression",
    "ability_regression",
    "weapon_abilities_regression",
    "backstab_regression",
    "trinkets_regression"
]
FIXED_FPS = {"cover_movement_regression", "weapon_input_regression"}
TIMEOUT = 120.0
## Wall-clock ceilings where the flat budget no longer fits. The frontier
## simulates 75 mobs (36 legacy, 16 devils, 19 Unholy Forest, 4 clones); the two
## fixed-fps tests drive real movement through every one of them at a fixed
## 240 Hz clock, so their wall time scales with frontier cost, not with test
## content. Measured standalone after the forest mobset landed: 217 s.
TIMEOUTS = {"weapon_input_regression": 480.0, "cover_movement_regression": 300.0}


def engine_path() -> str:
    value = os.environ.get("GODOT_PATH")
    if value:
        return value
    managed = ROOT / ".runtime" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
    if not managed.exists():
        managed = ROOT.parent / "ironwood-archer" / ".runtime" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
    return str(managed)


def run_one(test: str, engine: str, retry: bool = False) -> tuple:
    suffix = "-retry" if retry else ""
    appdata = Path(tempfile.gettempdir()) / f"ironwood-test-appdata-{test}{suffix}"
    appdata.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(appdata)
    args = [engine, "--headless"]
    if test in FIXED_FPS:
        args += ["--fixed-fps", "240"]
    args += ["--path", str(ROOT), "--script", f"res://tests/{test}.gd"]
    started = time.time()
    try:
        process = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True,
                                 timeout=TIMEOUTS.get(test, TIMEOUT))
        output = process.stdout + process.stderr
        code = process.returncode
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or "") + (error.stderr or "")
        code = 124
    duration = time.time() - started
    lines = [line for line in output.splitlines() if "REGRESSION" in line or "SCRIPT ERROR" in line or "Parse Error" in line]
    return test, code, duration, lines, output


def main() -> int:
    engine = engine_path()
    if not Path(engine).exists():
        print(f"Engine not found: {engine}")
        return 2
    started = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(TESTS)) as pool:
        futures = {pool.submit(run_one, test, engine): test for test in TESTS}
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())
    failed = [result for result in results if result[1] != 0]
    for test, code, duration, lines, output in sorted(results):
        print(f"{test:32s} exit={code} {duration:6.1f}s  {' | '.join(lines[-2:])}")
        if code != 0:
            print("\n".join(output.splitlines()[-15:]))
    remaining = []
    for test, _, _, _, _ in failed:
        print(f"RETRY {test}")
        result = run_one(test, engine, retry=True)
        print(f"{test:32s} retry_exit={result[1]} {result[2]:6.1f}s  {' | '.join(result[3][-2:])}")
        if result[1] != 0:
            remaining.append(result)
            print("\n".join(result[4].splitlines()[-15:]))
    elapsed = time.time() - started
    print(f"TOTAL {elapsed:.1f}s tests={len(TESTS)} failures={len(remaining)}")
    return 0 if not remaining else 1


if __name__ == "__main__":
    sys.exit(main())
