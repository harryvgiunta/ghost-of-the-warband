---
name: ironwood-archer
description: Use when modifying, debugging, launching, or verifying this Ironwood Godot repository, including authored skeletal character animation, Blender retargeting, frontier and arena gameplay, bow and sword combat, roll controls, HUD, and authoritative ENet multiplayer.
---

# Ironwood Archer

Work from the repository root containing `project.godot`. Paths below are repository-relative, not relative to this skill directory. Treat the current code and the user's requested behavior as authoritative; this skill records the existing contracts, not a prohibition on intentional changes.

## Orient before editing

1. Read the relevant portions of `README.md` and locate the affected symbols and callers. Preserve existing GDScript, signal, and scene conventions.
2. Separate shared gameplay from controller-specific input. A frontier-only fix is incomplete when the same feature is available in the arena.
3. Inspect the current launcher and setup files before changing the engine version or executable paths. Use the managed engine or the user's `GODOT_PATH`; do not introduce a new toolchain.
4. Check whether a GDScript language server is available before symbol navigation/refactors. If unavailable, use scoped symbol searches and Godot's parser/runtime; do not claim LSP verification.

## Ownership map

| Surface | Implementation and integration points |
| --- | --- |
| Frontier | `main.tscn`, `scripts/main.gd`: movement, input, camera, crosshair aim, equipment, and HUD updates |
| Arena/session | `arena.tscn`, `scripts/arena.gd`: host/client lifecycle, input actions, aim validation, authoritative projectile spawning, snapshots, and camera |
| Arena combatant | `scripts/arena_actor.gd`: authoritative movement, bots, stamina, health, respawn, `snapshot()` and `apply_snapshot()` |
| Character and animation | `scripts/archer.gd`: imported Skeleton3D/AnimationPlayer, action phases, physics-clock sampling, bow/terrain IK, equipment sockets, and animation-state replication |
| Authored assets | `assets/characters/ironwood_ranger.glb`, adjacent JSON/provenance/import settings, and `tools/prepare_character.py` / `tools/character_clearance.py` for reproducible Blender retargeting and cloth-clearance validation |
| Shared combat | `scripts/combat.gd`: attack eligibility, independent sword recovery, linear bow damage, and continuous blade-contact collision |
| Roll | `scripts/dodge_roll.gd`: explicit modifier request, direction, takeoff, finite roll progress, and airborne reuse restriction |
| Weapon/projectile geometry | `scripts/bow.gd`, `scripts/sword.gd`, `scripts/arrow.gd`, `scripts/geo.gd` |
| UI | `scripts/hud.gd` for frontier; `scripts/arena_hud.gd` for arena |
| World and supporting systems | `scripts/range_world.gd`, `scripts/arena_world.gd`, `scripts/enemy.gd`, `scripts/range_audio.gd` |

## Gameplay contracts to preserve

### Input and rolls

- Space jumps; **Shift + Space rolls immediately** from the ground or during a jump. Repeated unmodified Space presses never roll. There is no double-tap window.
- Movement determines roll direction, then facing is the fallback. Keep the single-roll-per-airborne-cycle restriction, normal world collisions, and attack cancellation; a roll is not invulnerability.
- Both controllers pass `event.shift_pressed`. The arena's `jump` action carries an explicitly validated boolean, not a trusted client animation state.
- `1` equips the selected bow; `2` equips the selected sword. Sizes are selected independently with mouse buttons, not number-key cycling.
- Mouse and Q are held attack inputs for bows. Release launches at most one arrow. Escape/equipment cancellation must not fire an arrow or leave a held-input latch active.

### Bow charge and recovery

- `Archer.BOW_DATA.draw_seconds` is the complete time to full charge: small/medium/large currently take 1/2/3 seconds. Raising is included, not an extra delay before charge begins.
- `draw_amount` drives the bar, string tension, and damage fraction. Half the draw duration means half damage; for the longbow, 1.5 seconds gives 50% of its base damage.
- Preserve the action sequence: `READY` → `DRAWING` → `HOLDING` if fully charged → `RELEASE` → `RECOVER` → `READY`. Release is also valid during `DRAWING`; holding at full charge never auto-fires.
- There is no separate bow cooldown or movement recovery penalty. Readiness follows the actual release/re-nock animation through `get_bow_recovery_progress()`. The current follow-through is 0.28 seconds and arrow retrieval/re-nocking is 0.95 seconds.
- Every shot, including zero/partial charge, spends the nocked arrow and completes recovery before another draw. Equipment swaps, cancellation, or rolling cannot skip/restart that recovery. Canceling an unreleased draw does not spend its arrow.
- Carry leftover frame time from release into recovery. Do not add a frame-dependent extra delay at phase boundaries.
- Aim is a world-space point from the current camera ray, not a tracked enemy or a gravity-compensated solution. Only real projectile collision applies bow damage.

### Swords and state isolation

- Swords use fixed-duration uncharged authored overhead swings. Damage comes from continuous blade-volume sweeps during the clip's downward striking interval, not an attacker-centered cone or a fixed 58% timestamp. Each victim can be damaged once per swing; world contact blocks further damage through cover.
- `Combat.melee_progress` is independent of bow readiness. Switching to a bow must neither block bow charging with sword recovery nor erase that recovery when switching back.
- `attack_progress` is presentation/replication state; do not treat it as a universal cooldown gate. `ArenaActor.revive()` resets both progress fields and rig/roll state.
- New attacks require solid ground and cannot start while rolling. Preserve cancellation before melee impact and the greatsword's two-hand grip.
- `melee_started()` resets per-swing victim state. `melee_sweep(previous_base, previous_tip, current_base, current_tip, radius)` supplies chronological world-space blade samples from the same pose used for the visible weapon. Preserve source exclusion, authoritative-only damage, cancellation, and coarse-frame contact coverage.

## Authored skeletal animation workflow

- The character is a textured, skinned Ranger with a 65-bone skeleton and authored clips. `assets/characters/LICENSE.txt` records the CC0 sources and modifications. Do not reintroduce the obsolete procedural body or a hand-position interpolation masquerading as a heavy sword animation.
- `tools/prepare_character.py` samples and retargets genuine source motion in Blender. The two-handed overhead is Gres's authored load/cut/recovery; the one-handed clip is a Quaternius overhead finisher with timing-only smoothing. Keep the original trajectory and anatomical elbow bend; bake proportion/cloth-clearance corrections offline instead of inventing runtime sword elbow poles.
- Keep the GLB, JSON, provenance and `.glb.import` settings together. `nodes/use_name_suffixes=false` preserves names such as `Idle_Loop`; otherwise Godot silently imports it as `Idle`. Animation sampling is 60 Hz; embedded image handling is 3 (lossless scene embedding), so extracted PNG duplicates are unnecessary.
- The model faces +Z; `archer.gd` rotates it by PI for gameplay's -Z convention. Use the exported `sword_grip`, `palms`, clip timings and `bow_anchor` metadata. Skeleton global poses are skeleton-relative, not world transforms. Never guess a weapon's axis from the hand bone's local Euler angles.
- `advance_animation(delta)` is the deterministic animation entry point, driven automatically by `_physics_process`. Tests that step it manually must call `set_physics_process(false)`, not `set_process(false)`. Active blade motion is sampled at steps no larger than 1/120 second; finish all crossed strike samples before changing MELEE to READY.
- Different sword durations retime windup and recovery while keeping a fast cutting stroke. Active source intervals come from the asset JSON, not a new arbitrary damage percentage.
- Pass post-collision **actual velocity** into `set_locomotion()` in both game modes. Integrate `_locomotion_phase` from speed; multiplying total elapsed time by current speed causes phase jumps during acceleration. Replicate the phase with the rest of the animation state.
- Keep fixed imported bone lengths and attached endpoints. `_solve_limb` rotates authored bone frames for bow aiming and terrain contact; it must not stretch limbs or invent twist bases. Equipment size does not rescale the humanoid.
- The imported Head joint is at the neck base, not the jaw. Bow contact uses the cheek-surface landmark exported by Blender. Draw with reachable push/pull targets; fetch the next arrow around the outside of the shoulder; hold the bow in front of the centreline for re-nocking. Straight hand interpolation across the waist/chest can hide the forearm inside the outfit even while joint-length tests pass.
- Both free arms move with authored locomotion. Bow aiming owns its hand targets; greatsword carry keeps the two-hand grip. Preserve terrain contact, authored roll articulation and landing transitions. Inspect the real mesh from multiple angles, not only bone coordinates.
- Keep the corrected two-hand guard animation playing on the upper body. Its support-elbow/clavicle tracks vary with breathing and recovery; replacing them with a frozen frame-zero arm pose against a separately animated torso reintroduces clipping. Keep the support palm on the actual handle while preserving the authored striking arm.

## Cross-mode change checklist

1. Change the shared rig/combat/roll behavior first, then migrate both controllers and their callsites.
2. For new animation state, update both rig serialization methods and review actor snapshots/replica application. The host owns combat and damage; clients submit input/aim, not charge or damage claims.
3. Update both HUDs, equipment hints, and the README when controls or timing change. Never leave labels describing a removed cooldown or input gesture.
4. Check weapon swaps, cancellation, airborne restrictions, respawn, and host/client behavior at the affected state boundaries.

## Run and verify

Windows launchers: `Play.cmd` opens the frontier; `Arena.cmd` opens the lobby; `Host Tailscale.cmd` hosts a match. They honor `GODOT_PATH`, run setup if needed, and import the bundled assets before starting. A fresh checkout must not rely on an existing `.godot` cache. Blender is only needed to re-author assets, not to play. Keep runtime binaries, logs, captures, and temporary scripts out of source control.

For the managed Windows console engine, run from the repository root:

```powershell
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
if ($LASTEXITCODE -ne 0) { throw 'Godot asset import failed' }
$Checks = @(
    'rig_regression',
    'draw_combat_regression',
    'projectile_regression',
    'gameplay_regression',
    'melee_roll_regression',
    'action_pose_regression',
    'weapon_input_regression',
    'arm_clearance_regression',
    'network_input_regression'
)
foreach ($Check in $Checks) {
    & $Godot --headless --path . --script "res://tests/$Check.gd"
    if ($LASTEXITCODE -ne 0) { throw "$Check failed ($LASTEXITCODE)" }
}
```

Use the selected engine path instead if `GODOT_PATH` is configured. Check exit codes and Godot parse/runtime errors, not just a final success line.

- `rig_regression` covers anatomy, bow geometry, grip/anchor, follow-through, and terrain contact.
- `draw_combat_regression` covers charge fractions, release uniqueness, re-nock boundaries, movement, cancellation, swaps, and long frames.
- `projectile_regression` covers real projectile collision behavior.
- `gameplay_regression` exercises the frontier controller's shot and movement behavior.
- `melee_roll_regression` covers actual blade contacts, off-blade misses, duplicate-hit prevention, thin cover, cancellation, coarse stepping, replicas and modifier-driven rolls.
- `action_pose_regression` checks imported limb lengths, continuous elbows, overhead loading/downward travel, body weight transfer, two-hand grip, running and rolls.
- `arm_clearance_regression` skins the actual torso mesh on the CPU and checks forearm intersection through draw, re-nock, sword windup and recovery. A named hand target or a guessed torso radius is not proof of visible clearance.
- `weapon_input_regression` injects real Godot input through frontier/arena equipment and attack controls.
- `network_input_regression` launches four actual ENet processes and checks authoritative input, damage, and replicated action states. Keep its isolated port/process lifecycle; do not replace it with mocked RPC echoes.

For shared combat, rig, or network changes, run the complete set after integration. Keep deterministic regression tests for meaningful behavior and boundaries, not HUD wording, copied fields, or source text.

Tests are not visual proof. Launch the actual changed scene and exercise its input. For animation changes, inspect rendered frames at opposing stride phases and during draw/release/recovery; check weapon contact, feet, terrain, and HUD. A temporary SceneTree script can instantiate `main.tscn` or `arena.tscn`, inject `InputEventKey`/mouse events, await `RenderingServer.frame_post_draw`, and save viewport images. Restore window focus and captured mouse-look before automated movement: a focus-out notification can intentionally suppress movement. Remove temporary scripts after verification.

## Restart and delivery

Godot keeps loaded scripts in memory. When asked to restart, identify processes by executable path and project arguments, preserve their scene/network arguments, close only this repo's game instances gracefully, and relaunch them. Do not kill unrelated Godot editors/games or silently force-kill a nonresponsive process. Restarting clears session-only frontier progress and disconnects a running match; reconnect clients to a restarted host.

Observe startup rather than assuming it: the frontier emits `IRONWOOD_WORLD_READY`, hosts emit `ARENA_HOST_READY`, and joined clients emit `ARENA_CLIENT_READY`. Leave a user-requested game running; close temporary verification instances.

Report the exact behavior changed, exercised verification, and any remaining blocker. Update this skill when an intentional change supersedes one of its repo contracts; do not preserve obsolete aliases or old input paths just to match these notes.
