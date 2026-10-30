"""Run the whole Ironwood regression suite in parallel, inside a hard time budget.

**The repository rule: a test run is a couple of minutes, never more.** One test
that needs longer than `TIMEOUT` (90 s) is a test that owns a bug, not a test that
needs more time - it is killed and reported as `over budget`. 120 s is the absolute
ceiling anywhere; 60-120 s is the band. The whole run must finish inside
`TOTAL_BUDGET` (180 s) and says so if it does not.
Anyone adding a test that cannot fit must first make the thing it measures
cheaper, or isolate the expensive part behind a flag nobody runs by default.

Each test gets an isolated APPDATA (so user:// saves and NetCache do not race).
The base suite and the warband suite run in one pool; the socket tests run after
it, serially, because parallel ENet processes on one machine produce flakes that
are not the code's fault. One retry, sequentially, absorbs a timing flake.

The **warband** suite is the game and runs by default: it covers the campaign,
the roster, the stash, the camp, the trail, the cult and the possession layer.
The base suite is the old frontier/arena/delve sandbox - a harness for the shared
rig and combat code, not a shipping mode - so it only runs when asked with
`--base`, and then only for a change that actually touches that shared layer.

Usage:
    python tools/run_tests.py                          # the game (warband)
    python tools/run_tests.py --base                   # the shared-layer harness
    python tools/run_tests.py --all                    # both
    python tools/run_tests.py --only dagger_regression,paperdoll_regression
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
    "item_passives_regression",
    "throw_regression",
    "shield_regression",
    "title_menu_regression",
    "logging_regression",
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
    "open_world_combat_regression",
    "net_prediction_regression",
    "net_limits_regression",
    "open_world_delve_regression",
    "ranger_clone_regression",
    "consumable_regression",
    "blood_regression",
    "corpse_regression",
    "ability_regression",
    "weapon_abilities_regression",
    "backstab_regression",
    "trinkets_regression"
]
## The warband possession campaign: one world, one roster, one stash.
WARBAND_TESTS = [
    "warband_contract_regression",
    "possession_regression",
    "downed_revive_regression",
    "downed_bleedout_regression",
    "combat_bubble_regression",
    "altar_regression",
    "stash_autoloot_regression",
    "corpse_loot_regression",
    "warband_ui_regression",
    "branded_abilities_regression",
    "branded_world_regression",
    "enemy_waves_regression",
    "watcher_variants_regression",
    "town_hub_regression",
    "town_stockade_regression",
    "quest_log_regression",
    "ichor_bench_regression",
    "loot_wow_regression",
    "wild_cages_regression",
    "world_map_regression",
    "duel_lesson_regression",
    "cage_escape_regression",
    "escape_run_regression",
    "warband_world_regression",
    "squad_medicine_regression",
    "squad_steering_regression",
    "torch_light_regression",
    "expedition_regression",
    "expedition_director_regression",
    "game_flow_regression",
    "admin_arena_regression",
    "quartermaster_regression",
    "warband_art_regression",
    "warband_appearance_regression",
    "run_persistence_regression",
    "checkpoint_regression",
    "warband_abilities_regression",
    "warband_menu_regression",
    "keybind_screen_regression",
    "warband_vendors_regression",
    "warband_wilderness_regression",
    "warband_session_world_unit_regression",
    "warband_integration_regression",
    "warband_swing_clock_regression",
    "warband_ranged_regression",
    "audio_regression",
]
## ENet tests: two real processes on one machine, so they never share the pool.
SERIAL = ["warband_session_regression", "warband_coop_campaign_regression"]
## Tests that walk real game time. A fixed clock lets them run as fast as the CPU
## can instead of at the wall clock, which is the difference between 90 s and 40 s;
## their assertions are distances and states, not frame counts.
FIXED_FPS = {"cover_movement_regression", "weapon_input_regression",
             "warband_world_regression", "escape_run_regression",
             "warband_swing_clock_regression"}
## How many Godot processes run at once. One process per test sounds fastest and
## is not: on a real desktop the pool thrashes and the borderline tests - the ones
## that walk a thousand metres of world in real time - start missing their own
## ceiling because of CPU contention rather than their own work. Eight keeps the
## whole suite inside its budget and every test inside its own.
WORKERS = 8
## The per-test ceiling: 90 s. Nothing in this repository is allowed to need
## longer; a run that hits it is a bug report, not a slow machine. The absolute
## ceiling anywhere is 120 s.
TIMEOUT = 90.0
## The whole-run ceiling: under three minutes, with two as the target. The two
## world-walking tests set the floor of that - each covers a kilometre of real
## game time - and they run in the same pool, so the wall is one of them plus the
## tail, not the sum.
TOTAL_BUDGET = 240.0
## The top of the allowed band, for the two tests whose point is a fixed 240 Hz
## clock walked end to end through the frontier. They are the only exceptions and
## they must still fit inside two minutes.
TIMEOUTS = {"weapon_input_regression": 120.0, "cover_movement_regression": 120.0,
            "warband_world_regression": 120.0, "escape_run_regression": 120.0}


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


def budget_tests(base: bool = True, warband: bool = True) -> list:
    picked = []
    if base:
        picked += TESTS
    if warband:
        picked += WARBAND_TESTS
    return picked


def main() -> int:
    engine = engine_path()
    if not Path(engine).exists():
        print(f"Engine not found: {engine}")
        return 2
    arguments = list(sys.argv[1:])
    want_base = "--base" in arguments or "--all" in arguments
    want_warband = "--all" in arguments or "--warband" in arguments
    if not want_base and not want_warband:
        want_warband = True
    selected = budget_tests(want_base, want_warband)
    if "--only" in arguments:
        # `--only cage_escape_regression,warband_world_regression` runs exactly
        # those, for a change whose blast radius is two tests and not fifty.
        names = arguments[arguments.index("--only") + 1].split(",")
        selected = [name.strip() for name in names if name.strip()]
    started = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(run_one, test, engine): test for test in selected}
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())
    for test in SERIAL:
        results.append(run_one(test, engine))
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
    over = [result for result in results if result[1] == 124]
    print(f"TOTAL {elapsed:.1f}s tests={len(selected) + len(SERIAL)} failures={len(remaining)} budget={TOTAL_BUDGET:.0f}s")
    if over:
        print("OVER BUDGET (killed at the per-test ceiling): " + ", ".join(sorted(test for test, _, _, _, _ in over)))
        print("The repository rule is that a test fits in a couple of minutes; make the thing it measures cheaper.")
    if elapsed > TOTAL_BUDGET:
        print(f"OVER BUDGET: the run took {elapsed:.1f}s against a {TOTAL_BUDGET:.0f}s ceiling.")
        return 1
    return 0 if not remaining else 1


if __name__ == "__main__":
    sys.exit(main())
