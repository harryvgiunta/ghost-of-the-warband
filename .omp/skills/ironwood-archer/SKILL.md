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
| Briar wolf presentation | `scripts/wolf_visual.gd`: imported `assets/characters/ironwood_wolf.glb`, idle/trot speed sampling, attack seek from gameplay timers, and held death; `tools/prepare_wolf.py` reproduces the mesh/rig/coat/clips |
| Authored assets | `assets/characters/ironwood_ranger.glb` and `assets/characters/ironwood_wolf.glb` with adjacent JSON/provenance/import settings; `tools/prepare_character.py` / `tools/character_clearance.py` for Ranger retargeting, `tools/prepare_wolf.py` for the wolf |
| Shared combat | `scripts/combat.gd`: attack eligibility, independent sword recovery, linear bow damage, and continuous blade-contact collision |
| Roll | `scripts/dodge_roll.gd`: explicit modifier request, direction, takeoff, finite roll progress, and airborne reuse restriction |
| Running slide | `scripts/running_slide.gd`: achieved-sprint eligibility, finite deceleration, limited steering and collision/ground-loss termination |
| Cover and shoulder camera | `scripts/cover_movement.gd`: shared physics/crouch/peek state; `scripts/shoulder_camera.gd`: smooth shoulder swap and swept camera collision |
| Weapon/projectile geometry | `scripts/bow.gd`, `scripts/sword.gd`, `scripts/arrow.gd`, `scripts/geo.gd` |
| UI | `scripts/hud.gd` for frontier; `scripts/arena_hud.gd` for arena |
| World and supporting systems | `scripts/range_world.gd`, `scripts/arena_world.gd`, `scripts/enemy.gd` (wolf/sentinel AI and damage authority), `scripts/range_audio.gd` |

## Gameplay contracts to preserve

### Input and rolls

- Space jumps; **Shift + Space rolls immediately** from the ground or during a jump. Repeated unmodified Space presses never roll. There is no double-tap window.
- Movement determines roll direction, then facing is the fallback. Keep the single-roll-per-airborne-cycle restriction, normal world collisions, and attack cancellation; a roll is not invulnerability.
- Both controllers pass `event.shift_pressed`. The arena's `jump` action carries an explicitly validated boolean, not a trusted client animation state.
- `1` equips the selected bow; `2` equips the selected sword. Sizes are selected independently with mouse buttons, not number-key cycling.
- Mouse and Q are held attack inputs for bows. Release launches at most one arrow. Escape/equipment cancellation must not fire an arrow or leave a held-input latch active.

### Running slides

- C's new crouch intent during an achieved grounded sprint starts `RunningSlide` in both controllers. Require at least 6 m/s actual planar velocity, sprint input/stamina eligibility, and no existing crouch, cover or roll. Stationary Shift+C, walking and repeated true crouch intent must not manufacture or restart momentum.
- `try_start(body,stance,sprinting,rolling)` sets crouch intent; `step(delta,body,stance,direction,rolling)` precedes velocity selection, and `after_move(body,actual_velocity)` sees achieved post-collision movement. Keep `CoverMovement` as the sole capsule/camera stance owner. Slide velocity overrides ordinary acceleration only while active; roll remains the final override.
- The 0.75 s slide decelerates from 10.5 to 2.2 m/s, allows at most 36 degrees steering from entry, and persists without held movement/Shift. Continue normal sprint stamina drain; finish crouched. C cancels, successful jump/roll or cover attachment cancels, and floor loss/blocked forward movement ends it. Blocked headroom must not expand the capsule or cancel a rejected jump. Death/revive/camp and stale arena input clear sliding.
- Grounded combat remains available. `Archer.set_slide(progress,direction)` runs after `set_cover` and before the controller's pose updates; inactive progress is -1. The rig layers a fixed-length, asymmetric planted slide over authored crouch, suppresses stepping, and preserves upper-body weapon actions. Preserve heading through the exit blend rather than resetting it to world-forward.
- Animation snapshot `slide` is a compact `Vector4(progress,direction.x,direction.z,blend_weight)` so individual actor RPCs stay below ENet's MTU, including maximum-length UTF-8 names. Roll facing uses the existing replicated yaw, not a redundant direction field. Replicas apply physical cover before the animation snapshot. Clients still submit boolean crouch intent, never slide speed/position/pose claims.

### Cover and shoulder controls

- F toggles grounded, geometry-derived cover within 1.35 m. Both controllers use `CoverMovement`; WASD projects onto the contact tangent. Supported full-capsule sweeps follow slopes, curved/faceted offsets and contiguous collider seams without shape/RID identity locking. Genuine edges and hard corners still stop movement. Attached movement is 2.2 m/s, or 4.2 m/s with Shift and normal stamina/exhaustion, including crouch.
- RMB holds a manual top/left/right lookout. Side destinations try 0.45/0.55/0.65 m in order, requiring supported ground, a swept clear capsule and a finite-width forward firing corridor. Low-cover classification also checks deeper inward geometry so an inset rock face cannot invent a top peek. Keep one endpoint latched, and normalize signed lean against its selected extent. A blocked opposite-side request may retuck and resume sliding; a stationary blocked same-side request cannot jump to a longer endpoint. Use the same 2 cm protected-return tolerance as arrival, not a submillimetre latch that terrain recovery can keep locked. Bow attacks OR automatic exposure with manual input; melee bypasses this gate by exiting cover.
- A draw begun already exposed by RMB keeps manual ownership: releasing RMB retucks without canceling the held draw, including sliding away from the edge. Releasing that bow while tucked requests exposure again; blocked release cancels safely. A direct tucked bow draw owns exposure through RELEASE, then retucks unless RMB remains held. Stop, equipment changes, jump/roll, death/respawn and lost cover clear pending bow intent.
- X explicitly selects left/right lookout and smoothly swaps the camera, not weapon handedness. Capture horizontal view-right on cover entry, a new READY draw, manual RMB press or X. Preserve it through release/return and free look; do not recapture on mouse-up/Q-up. Both controllers feed `cover.view_right` before eligibility/step. Camera smoothing advances once per render frame; aim queries call `resolve()` without advancing it. Preserve swept-volume obstruction and overlap recovery.
- C toggles manual crouch while grounded and not rolling, with captured-cursor movement guards; achieved sprint-to-crouch starts the running slide described above. Armor remains equipment-button-only. Outside cover, ordinary crouch moves at 2.2 m/s and disables sprint. F exit preserves manual crouch. Standing checks headroom; never expand a capsule into an obstacle.
- Cover owns capsule height and smooth `crouch_amount` (0–1), even outside cover. Run `cover.step(delta,direction,peek,side,fast)` every physics tick; use its returned velocity only if cover was active before the call. World-space `lean` is UP times physical rise for low cover, or the signed tangent times physical lateral exposure at tall edges, including retuck. `set_cover(active,normal,crouch_amount,peeking,lean)` runs before locomotion/roll pose updates in both modes and replicas. Keep cover data in the single physical cover snapshot, not duplicated in `get_animation_state()`; apply it before `apply_animation_state()`. Camera height follows crouch outside cover too.
- The rig layers authored `Cover_Lean_Top/Left/Right` pelvis/spine/head deltas in the cover frame so aiming cannot reverse a lean. Facing blends from the protected outward stance toward the aim point with exposure, including idle peeks and retuck. Apply the layer before foot and weapon corrections; preserve sword grips and actual blade sweeps. Retuck must keep its protected anchor until the capsule returns, even with movement held.
- Authored `Crouch_Idle_Loop` / `Crouch_Fwd_Loop` replace the crouched stance/steps, using the JSON stride estimate and actual speed for cadence. Layer only the lower body during bow/sword actions and two-handed carry; preserve overall 0.58 m pelvis lowering and fixed-length planted legs. Side peeks stay crouched; blocked top peeks cannot expand the collider or invent exposure.
- Space caches grounded state before `prepare_jump()`; blocked standing headroom prevents takeoff. Otherwise it exits cover, clears manual crouch and peek latches, restores the standing collider and performs the existing jump/roll. Apply queued jump velocity even if stance preparation changed the floor cache. Death, respawn and camp return use `cover.reset()` and clear held intent.
- Arena validates boolean crouch intent and lookout context (`pressed`, horizontal unit `right`, ±1 `side`). The host derives all geometry, anchors, exposure and collider height. Reliable peek-context messages precede draw/release without fabricating RMB presses. Aim-bearing movement/action RPCs include the observed own-actor snapshot tick, validated against snapshots actually sent. Keep accepted aim and tick atomic: stale samples cannot overwrite newer aim, but valid stale reliable release intent is not dropped.
- Remote `Combat.cover_aim_ready` requires an aim acknowledging the current physical exposure epoch. Reset that epoch on retuck, side transition, exit and lifecycle reset. Keep charge frozen until fresh exposed-camera aim arrives, then run the normal shaft check. Host/local/bots and noncover release are unchanged. Existing input_age >0.65 handling cancels automatic/frozen cover intent; do not add retry timers or allow a delayed shot after input resumes.

### Bow charge and recovery

- `Archer.BOW_DATA.draw_seconds` is the complete time to full charge: small/medium/large currently take 1/2/3 seconds. Raising is included, not an extra delay before charge begins.
- `draw_amount` drives the bar, string tension, and damage fraction. Half the draw duration means half damage; for the longbow, 1.5 seconds gives 50% of its base damage.
- Preserve the action sequence: `READY` → `DRAWING` → `HOLDING` if fully charged → `RELEASE` → `RECOVER` → `READY`. Release is also valid during `DRAWING`; holding at full charge never auto-fires.
- In cover, an early bow release sets replicated `rig.charge_frozen`: charge stops at input release while the raise clock continues. `Combat` fires once only after physical exposure and the 0.30-second raise; waiting never increases damage. Non-cover release timing remains immediate.
- There is no separate bow cooldown or movement recovery penalty. Readiness follows the actual release/re-nock animation through `get_bow_recovery_progress()`. The current follow-through is 0.28 seconds and arrow retrieval/re-nocking is 0.95 seconds.
- Every shot, including zero/partial charge, spends the nocked arrow and completes recovery before another draw. Equipment swaps, cancellation, or rolling cannot skip/restart that recovery. Canceling an unreleased draw does not spend its arrow.
- Carry leftover frame time from release into recovery. Do not add a frame-dependent extra delay at phase boundaries.
- Aim remains a world-space point from the camera ray, not target tracking or gravity compensation. Start the query at the projected actor position plus `cover.camera_height()`, clipping only camera-side geometry. Never use the animated muzzle to choose this start: it feeds bow facing/raise back into targeting, skips close crosshair targets and makes shoulder convergence unstable. Aim the bow from its cheek anchor. Before a cover release, sweep the actual nock-to-tip shaft with finite radius and an initial-overlap check. Obstruction cancels pending release/frozen charge. Never relocate a clear shot's origin behind the obstacle; it launches from the rendered arrow tip. Ordinary projectile collision alone applies damage.

### Swords and state isolation

- Swords use fixed-duration uncharged authored overhead swings. Damage comes from continuous blade-volume sweeps during the clip's downward striking interval, not an attacker-centered cone or a fixed 58% timestamp. Each victim can be damaged once per swing; world contact blocks further damage through cover.
- `Combat.melee_progress` is independent of bow readiness. Switching to a bow must neither block bow charging with sword recovery nor erase that recovery when switching back.
- `attack_progress` is presentation/replication state; do not treat it as a universal cooldown gate. `ArenaActor.revive()` resets both progress fields and rig/roll state.
- New attacks require solid ground and cannot start while rolling. Preserve cancellation before melee impact and the greatsword's two-hand grip.
- A valid `Combat.begin_melee()` immediately exits sticky cover and calls `rig.set_cover(false,...)` before the first swing pose. No peek/edge/headroom prerequisite, deferred melee, automatic retuck, teleport or forced stand. Preserve manual crouch and collider height; ordinary stance updates may stand only when clear. Failed cooldown/ground/weapon/roll gates leave attachment unchanged. Movement is free during the swing, and F is required to reattach even if RMB stays held. World blade collision still blocks damage through cover.
- `melee_started()` resets per-swing victim state. `melee_sweep(previous_base, previous_tip, current_base, current_tip, radius)` supplies chronological world-space blade samples from the same pose used for the visible weapon. Preserve source exclusion, authoritative-only damage, cancellation, and coarse-frame contact coverage.

## Authored skeletal animation workflow

- The character is a textured, skinned Ranger with a 65-bone skeleton and authored clips. `assets/characters/LICENSE.txt` records the CC0 sources and modifications. Do not reintroduce the obsolete procedural body or a hand-position interpolation masquerading as a heavy sword animation.
- `tools/prepare_character.py` samples and retargets genuine source motion in Blender. The two-handed overhead is Gres's authored load/cut/recovery; the one-handed clip is a Quaternius overhead finisher with timing-only smoothing. Keep the original trajectory and anatomical elbow bend; bake proportion/cloth-clearance corrections offline instead of inventing runtime sword elbow poles.
- The same preparation tool retargets Quaternius crouch idle/forward clips and keys the three 0.24-second cover leans from one idle reference. Their asset-space directions and measured crouch stride are recorded in JSON; keep arm-local poses neutral for additive combat layering.
- Keep the GLB, JSON, provenance and `.glb.import` settings together. `nodes/use_name_suffixes=false` preserves names such as `Idle_Loop` and `Wolf_Idle_Loop`; otherwise Godot silently strips the suffix. Animation sampling is 60 Hz. Check the actual importer behavior before changing texture handling: the wolf uses `gltf/embedded_image_handling=2` so its coat stays embedded in the imported scene without an extracted duplicate PNG, while the Ranger import currently records 3.
- The Ranger model faces +Z; `archer.gd` rotates it by PI for gameplay's -Z convention. The wolf imports facing -Z, so `wolf_visual.gd` applies no wrapper rotation. Use the exported `sword_grip`, `palms`, clip timings, `bow_anchor` and wolf JSON. Skeleton global poses are skeleton-relative, not world transforms. Never guess a weapon's axis from the hand bone's local Euler angles.
- `advance_animation(delta)` is the deterministic animation entry point, driven automatically by `_physics_process`. Tests that step it manually must call `set_physics_process(false)`, not `set_process(false)`. Active blade motion is sampled at steps no larger than 1/120 second; finish all crossed strike samples before changing MELEE to READY.
- Different sword durations retime windup and recovery while keeping a fast cutting stroke. Active source intervals come from the asset JSON, not a new arbitrary damage percentage.
- Pass post-collision **actual velocity** into `set_locomotion()` in both game modes. Integrate `_locomotion_phase` from speed; multiplying total elapsed time by current speed causes phase jumps during acceleration. Replicate the phase with the rest of the animation state.
- Keep fixed imported bone lengths and attached endpoints. `_solve_limb` rotates authored bone frames for bow aiming and terrain contact; it must not stretch limbs or invent twist bases. Equipment size does not rescale the humanoid.
- Cache and blend authored poses before applying crouch, foot placement, or weapon IK. Reusing an already-corrected pose as the next blend source accumulates crouch offsets during movement transitions and can sink the skeleton. Keep rotation-only rig/model nodes at unit scale by constructing their yaw basis directly; repeated Euler setters must not feed extracted floating-point scale back into aiming rotations.
- The imported Head joint is at the neck base, not the jaw. Bow contact uses the cheek-surface landmark exported by Blender. Draw with reachable push/pull targets; fetch the next arrow around the outside of the shoulder; hold the bow in front of the centreline for re-nocking. Straight hand interpolation across the waist/chest can hide the forearm inside the outfit even while joint-length tests pass.
- Both free arms move with authored locomotion. Bow aiming owns its hand targets; greatsword carry keeps the two-hand grip. Preserve terrain contact, authored roll articulation and landing transitions. Inspect the real mesh from multiple angles, not only bone coordinates.
- Keep the corrected two-hand guard animation playing on the upper body. Its support-elbow/clavicle tracks vary with breathing and recovery; replacing them with a frozen frame-zero arm pose against a separately animated torso reintroduces clipping. Keep the support palm on the actual handle while preserving the authored striking arm.

### Briar wolf (frontier enemy)

- `scripts/enemy.gd` owns the wolf's root transform, health 38, layer/mask, steering, leash, chase speed 3.1, return speed 2.0, `WINDUP`/`RECOVER` timers, damage check and reward. `scripts/wolf_visual.gd` is presentation only; never move damage into a clip event, add a mesh hitbox, or re-enable AI for a dead visual.
- The imported wolf faces -Z at identity scale with paws at y=0 and an aim target at y=0.68. The visual switches between `Wolf_Idle_Loop` and `Wolf_Trot_Loop` from post-collision actual horizontal speed; trot playback rate is `speed / (1.15 / 0.6)`.
- The 1.5 s `Wolf_Attack` is sampled from the existing timer: `clamp(_state_time,0,0.65)` during windup and `0.65 + clamp(_state_time,0,0.85)` during recovery, so the authored jaw snap lands at the damage frame. Do not restart the clip when entering RECOVER.
- Lethal damage calls `_wolf.die()`; the 0.45 s collapse runs on the visual's own clock and holds its final pose for 4.0 s before `_body` shrinks for 0.4 s and the root frees. Keep the CharacterBody root at identity scale. The sentinel keeps its primitive limbs and existing `_body.rotation:z` death tween.
- `tests/wolf_regression.gd` checks the imported 37-bone skeleton, clip names/durations/loops, facing/bounds, embedded 1024 coat, stationary root, bite closure/thrust, held death, wolf cutover and sentinel preservation. Existing humanoid regressions do not validate quadruped anatomy.

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
    'network_input_regression',
    'cover_movement_regression',
    'running_slide_regression',
    'wolf_regression'
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
- `weapon_input_regression` drives both controllers through near/mid/far crosshair targets from both shoulders and initial sideways facing, native-scale cylinder/box/compound lookouts, manual RMB and direct LMB/Q, held-draw X swaps, free-look sign crossings, exact tip origin and actual projectile clearance, buried/midshaft blockers, cancellation and immediate melee exits. Aim checks measure real target impacts, not only agreement with combat's own aim field. Flush injected held-key events before measuring charge.
- `network_input_regression` uses four real ENet processes to check remote tree lookouts/shots/retuck, observer pose/projectile direction, fresh exposure acknowledgement, malformed/future/stale tick handling, frozen charge, paused-input cancellation and melee exits. Wait for replicated transitions with bounded deadlines, not fixed sleeps tied to one peek extent.
- `cover_movement_regression` checks standing/crouched cylinders, rotated boxes, inward-rising and faceted convex rocks, compound/body seams, blocked lanes/ledges, supported slopes, recovery dips, resumed movement after retuck, queued bow releases and melee detachment. Pose/contact and wolf checks retain their separate coverage.
- `wolf_regression` checks the imported wolf’s 37-bone skeleton, clip names/durations/loops, -Z facing, ground contact, embedded 1024 coat, stationary root, bite closure/forward thrust, held death, `enemy.gd` cutover and sentinel preservation.
- `running_slide_regression` checks sprint-crouch eligibility, retained momentum, finite deceleration, bounded steering, no held-input retrigger, wall/headroom safety, jump/roll/death/revive transitions, grounded combat, replicated skeletons and fixed limb lengths. Contact checks allow the physics solver's `safe_margin`, not visible penetration.

For shared combat, rig, or network changes, run the complete set after integration. Keep deterministic regression tests for meaningful behavior and boundaries, not HUD wording, copied fields, or source text.

Tests are not visual proof. Launch the actual changed scene and exercise its input. For animation changes, inspect rendered frames at opposing stride phases and during draw/release/recovery; check weapon contact, feet, terrain, and HUD. A temporary SceneTree script can instantiate `main.tscn` or `arena.tscn`, inject `InputEventKey`/mouse events, await `RenderingServer.frame_post_draw`, and save viewport images. Restore window focus and captured mouse-look before automated movement: a focus-out notification can intentionally suppress movement. Remove temporary scripts after verification.

## Restart and delivery

Godot keeps loaded scripts in memory. When asked to restart, identify processes by executable path and project arguments, preserve their scene/network arguments, close only this repo's game instances gracefully, and relaunch them. Do not kill unrelated Godot editors/games or silently force-kill a nonresponsive process. Restarting clears session-only frontier progress and disconnects a running match; reconnect clients to a restarted host.

Observe startup rather than assuming it: the frontier emits `IRONWOOD_WORLD_READY`, hosts emit `ARENA_HOST_READY`, and joined clients emit `ARENA_CLIENT_READY`. Leave a user-requested game running; close temporary verification instances.

Report the exact behavior changed, exercised verification, and any remaining blocker. Update this skill when an intentional change supersedes one of its repo contracts; do not preserve obsolete aliases or old input paths just to match these notes.
