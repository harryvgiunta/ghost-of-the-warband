# Quadruped animation and gameplay integration

Read this before baking creature motion, replacing wolf visuals, changing animation clocks, or fixing foot sliding/pose drift. [Wolf authoring](wolf-authoring.md) defines bind/skin prerequisites. [Variants and evidence](variants-and-evidence.md) defines rendered acceptance and future variant scaling. All clip/controller names below are proposed; inspect actual exported names before wiring them.

## 1. Own each clock and transform once

**Current code contract:** `scripts/enemy.gd` extends `CharacterBody3D`; the root owns collision, facing, `_steer()`, gravity and `move_and_slide()`. `_physics_process()` owns the `IDLE`, `CHASE`, `WINDUP`, `RECOVER` transitions. `take_damage()` owns `DEAD`, rewards and collision shutdown. Keep those authorities intact when replacing presentation.

- Gameplay faces local -Z; root world translation/facing come from gameplay, not an animation track. One visual child contains the measured model-axis conversion and asset scale. Never animate the physics root's position/rotation/scale from the GLB.
- Keep rotation-only rig/facing nodes unit-scale at the source. Repeated Euler property setters can preserve scale extracted from a previously rounded basis and accumulate drift during sustained updates; for a node whose complete intended transform is pure yaw, construct `Basis(Vector3.UP, yaw)` directly. Keep intentional asset/variant scale on a separate child and never erase it with that assignment. Bone interpolation likewise uses correct rest-relative rotation frames. If `Basis.slerp` reports a non-normalized rotation, repair the transform producer/ownership rather than repeatedly orthonormalizing at the error site or suppressing the warning.
- Use **in-place** locomotion for this integration. Bake out accumulating planar root travel/yaw, retain authored pelvis bob/roll and spine motion, and record the removed travel as stride metadata. Do not both apply `move_and_slide()` and consume root motion. Root-motion gameplay would be a separately requested redesign.
- Animation state is a view of gameplay, not permission to attack. Use the gameplay timer to sample combat clips; clip events never emit damage, create attacks, change collision masks, award rewards, or change AI state.
- Use one animation evaluator per visual instance. If manually sampling `AnimationPlayer`, set its processing to manual using the installed Godot API (`AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL` on applicable Godot versions) and advance/seek from the chosen clock. If using an `AnimationTree`, do not also independently advance the player's tracks. Inspect the installed API rather than copying an obsolete enum.

**Gate:** document which object owns physics, state clock, animation sampling and post-animation corrections. No property has two writers in the same tick.

## 2. Produce real clips, not animated placeholders

Either retarget verified quadruped source motion with rest-frame conversion and contact correction, or author keyed skeletal motion in Blender. Preserve source provenance for retargeted clips. Hand-authored keys and IK controllers are valid; bake evaluated deformation bones at 60 Hz into actions. Sine-driven runtime limb nodes, a static rig with bobbing whole-body motion, and random bone jitter are not authored clips.

Implemented default clip set for the shipped wolf. The names, durations and loop modes below are the current asset contract; re-measure the GLB before changing them.

| Clip | Proposed duration and loop | Required motion and measurements |
| --- | --- | --- |
| `Wolf_Idle_Loop` | 2.4 s, loop | Four planted paws, subtle chest breath, head/ear/tail overlap; no locomotion drift |
| `Wolf_Walk_Loop` | not shipped | The current default uses the trot for all travel. A walk is an optional later clip, not a hidden fallback. |
| `Wolf_Trot_Loop` | 0.6 s, loop | Shipped at 1.15 m full-cycle stride and 0.45 stance duty. Runtime playback rate is `speed / (1.15 / 0.6)`, not a forced 1.86 m stretch. |
| `Wolf_Attack` | 1.50 s, non-loop | Shipped load and forward bite; impact at 0.65 s; follow-through/recoil and neutral pose by 1.50 s. |
| `Wolf_Death` | 0.45 s, non-loop for baseline lifecycle | Shipped loss of support, leg folding and side collapse; the runtime holds the final grounded pose. |

The shipped attack/death durations are aligned to the existing gameplay lifecycle. If a replacement source is longer, retime its meaningful collapse into the 0.45 s presentation window or explicitly change the lifecycle and its test. Never silently stretch the despawn time. A separate gallop is only necessary if requested speeds/readability require it; the shipped trot covers the current chase and return speeds. Do not rename a walk as a run to satisfy the table.

### Contact-driven key recipe

Use phase `p` in `[0,1)`; LF/RF are left/right forepaws, LH/RH left/right hindpaws. Set each paw's touchdown offset and stance fraction, then key its sole position/orientation at touchdown, load, midstance, toe-off, swing apex and next touchdown. Cyclic interpolation must preserve touchdown velocity, not merely duplicate endpoints.

| Gait | Touchdown offsets | Initial stance fraction | Body timing |
| --- | --- | --- | --- |
| Walk | LH=0, LF=0.25, RH=0.50, RF=0.75 | 0.65 | Small continuous pelvis/chest transfer over support polygon; head counter-motion; tail follows pelvis with delay |
| Trot | LH=RF=0, RH=LF=0.50 | 0.55 | Diagonal support alternation; modest compression after pair contact and rise into transfer; chest/pelvis counter-rotation, head stabilised |

1. For each foot set local phase `q = (p - touchdown_offset + 1) % 1`. During stance (`q < stance_fraction`), the in-place paw moves backwards relative to the torso at the nominal travel speed. Its world-space sole should remain nearly still when the root moves forward. Record stride as distance per **full cycle**, not per half-step.
2. Start stance with paw ahead of its shoulder/hip, settle pad into load, pass under the joint, then roll through toes before lift-off. Use ankle/toe articulation, not a foot teleported from front to back. With stride `S` and duty `d`, stance travel is approximately `S*d`; verify reach against actual bone lengths and shorten the stride if needed.
3. Swing returns the paw to front over `1-d` of the cycle with a curved path and initial suggested clearance 4–8 cm. Peak clearance occurs near mid-swing. Tuck carpus/hock and toes; lower and orient the sole before touchdown. Use smooth horizontal acceleration/deceleration and near-zero vertical contact velocity. Key contact frames explicitly and inspect the evaluated in-between frames for spline overshoot.
4. Key scapula slide/rotation with fore reach, hip/spine response with hind propulsion, and compression during support. Head moves to stabilise gaze, not perfectly copy the chest. Tail follows pelvis turns/vertical acceleration by a small authored delay, not an unrelated metronome. Keep left/right motion plausibly asymmetric in idle, periodic and seam-continuous in locomotion.
5. Author keys for the complete deformation hierarchy, including head, jaw, ears, paws and tail. Solve IK in Blender and bake evaluated `pose_bone.matrix`/visual transforms into the export rig's correct local parent/rest space. In a script, use `scene.frame_set()` and update the dependency graph before reading evaluated poses; `PoseBone.keyframe_insert` on location/quaternion/scale or `bpy.ops.nla.bake` with visual keying can bake the result. Read operator options for installed Blender. Do not key a world matrix directly into local rotation channels.
6. Export only deform bones and required nondeforming root/socket nodes. Bake or remove constraints that would otherwise depend on unexported controls. Check action slots/NLA naming against the existing exporter pattern. For a loop bake both matching endpoint samples (0 through duration at 60 Hz); avoid introducing a duplicated held frame into the loop period.

**Gate/output:** Blender renders at eight evenly spaced phases plus contact/toe-off close-ups, contact table, actual duration/stride, and maximum stance slip. If the mesh clips or flips, return to the rig/weights stage; more blend smoothing cannot repair an invalid rig.

## 3. Attack: hit exactly when gameplay says so

Current `enemy.gd` timings and conditions to preserve:

- Enter `WINDUP` from eligible pursuit at horizontal distance `< 1.65`; reset `_state_time=0`, show `_warning`, request zero target velocity (the root still decelerates through its existing movement code).
- At `_state_time >= 0.65`, check horizontal distance `< 2.1`, `not player_safe`, and vertical separation `< 1.7`, then emit `damaged_player` once (13 for the wolf). Enter `RECOVER`, reset `_state_time=0`, hide warning.
- Exit recovery only when `_state_time > 0.85`. Preserve these exact comparisons and the existing frame-boundary behavior. Do not change damage to mesh contact, distance bands, animation callbacks, or a new hitbox as part of a visual overhaul.

Author the single attack clip with these starting landmarks:

1. 0.00–0.30 s: brace paws, lower shoulders/head, transfer weight rearward; jaw begins to open. Preserve the existing warning cue.
2. 0.30–0.55 s: extend through shoulders/neck and push with hindquarters; head trajectory is directed forward, not a full-body root teleport.
3. 0.55–0.65 s: quick bite closure/strike, strongest forward silhouette exactly at 0.65 s. The torso/paws show supported weight; an airborne root lunge is not added gameplay. Inspect real typical combat distances and acknowledge that existing damage is a proximity check, not physically measured teeth contact.
4. 0.65–0.85 s: follow-through and recoil; head/jaw recover without snapping.
5. 0.85–1.50 s: settle body and paws into a pose compatible with idle/trot. Blend back without restarting locomotion phase arbitrarily.

Sample `Wolf_Attack` at `clamp(_state_time,0,0.65)` during WINDUP and at `0.65 + clamp(_state_time,0,0.85)` during RECOVER. On the state transition use the **new** state/timer after the authoritative update, so the first recovery sample displays impact rather than resetting to clip start. Do not start a fresh attack when entering RECOVER. A large physics delta must not skip the damage decision, duplicate it, or independently advance the clip beyond the gameplay state. Keep combat sampling tied to the existing timer; don't “fix” timer overshoot semantics during presentation work.

For source clip impact at `a` with duration `T`, map windup time `t` to `a*t/0.65`, recovery time `r` to `a + (T-a)*r/0.85`. This preserves source impact while aligning gameplay. If that would visibly slow the actual bite, author a piecewise map preserving the short fast strike interval and absorb duration in anticipation/recovery; record all source/output landmarks and verify them after export. Never claim an impact match from nominal clip duration alone.

Blend into attack without delaying its clock or blunting the impact; use a short transition that finishes before the strike interval. Death interrupts immediately. Clip method tracks must not emit `damaged_player` or call `take_damage`; presentation events such as non-authoritative sound are a separate, intentional decision, not a reason to add duplicate combat authority.

## 4. Runtime locomotion and fresh authored poses

1. After `move_and_slide()`, obtain actual horizontal travel velocity (Godot `get_real_velocity()` is appropriate for motion achieved across the tick; exclude vertical fall/bob). Do not drive cadence from the requested chase speed while blocked. Choose locomotion by measured motion, not only the state string: `IDLE` can be returning home at 2 m/s.
2. Integrate continuous phase: `phase = fposmod(phase + horizontal_speed * delta / stride_metres, 1.0)`; sample a clip at `phase * clip_duration`. This is equivalent to playback ratio `actual_speed / (stride / duration)`. Do not compute `elapsed_time * current_speed`, which jumps when speed changes. Keep phase continuous across walk/trot blends; choose corresponding contact phases or a short authored transition to avoid swapping supporting feet mid-blend.
3. At zero speed blend to planted idle. For sharp turns, avoid indefinitely pinning a stance paw outside the reachable support region: release/retarget through a short contact transition or use an authored turn if requested. Do not stretch a limb to follow a stale world-space plant.
4. Sample a **fresh authored pose** for the current clips each tick, blend the base poses, and capture the result for future authored transitions **before** applying crouch/stance lowering, terrain IK, gaze/aim or other procedural corrections. Then apply those corrections exactly once. Never take the visible, already-corrected skeleton as next frame's authored source.
5. `scripts/archer.gd` demonstrates the intended separation with `_blend_pose` and `_authored_pose` around `_update_pose()`, before `_apply_cover_crouch()` and ground/limb corrections. Read the live implementation rather than copying a stale line number. The movement failure this prevents is cumulative sinking: each new transition reuses an already lowered pelvis, then applies the lowering again. The same error can accumulate terrain tilt or paw offsets on a wolf.
6. Reset authored blend sources, contact caches and phase ownership deliberately on instantiate/reset/death or model replacement. Do not overwrite rest transforms with solved poses. Test many idle↔walk↔attack/turn transitions on a slope; no progressive height/rotation drift is allowed.

### Terrain correction, if needed for the requested result

Use actual world raycasts/shapecasts at paw sole targets, excluding the creature and querying world geometry. Ray origins should start above the expected ground within measured reach. Save contact anchors in world space during stance, release through toe-off, and keep swing targets authored with terrain clearance. Convert world targets through the visual/skeleton transform before solving; Skeleton3D global bone poses are **skeleton-relative**, not world transforms.

Constrain pelvis/chest vertical and tilt adjustments to plausible reach; distribute over spine, keep bone lengths fixed, and solve the appropriate fore/hind chains. Blend contact weights near touchdown/toe-off. Clamp or release an unreachable target, do not lengthen bones. On missing ground/ledge/airborne motion, fade correction rather than snapping to an invented floor. This is a corrective layer on authored motion, never a replacement for a gait. Verify actual terrain results before adding more solvers.

## 5. Wolf-only cutover in `enemy.gd`

The cutover is implemented. Preserve these invariants when changing the wolf; the historical primitive path must not return.

1. In `_ready()`, preserve root identity/position, wolf health 38, layer 2, mask `1 | 2 | 4`, floor snap 0.6, max floor angle 46 degrees, capsule radius 0.40/height 0.95 and centre y=height/2, warning geometry, and `_query.collision_mask=1`. Attach the new visual only for `kind == 0`; the cinder devil's own capsule (radius 0.34/height 2.15) belongs to its kind branch and must not leak into wolf tuning.
2. `_build_wolf_visual()` attaches `scripts/wolf_visual.gd`; the old `_build_wolf()` primitive construction is gone. Do not reintroduce a primitive fallback wolf or a second animation driver. `_body` remains the wolf visual container.
3. Wolf no longer participates in the `_walk_time`/sine limb/`_body.position.y` animation or arm windup; those fields went with the retired primitive path. `Geo` still builds the warning ring, so do not remove its preload indiscriminately.
4. Keep `_steer`, safe-area check, pursuit `<23`, home leash `<38`, return-home behavior, chase speed 3.1/return speed 2.0, acceleration 12, gravity 18, facing interpolation, warning/damage signals and `get_display_name()` unchanged. Keep `get_aim_position()` at y=0.68 for the baseline unless the user explicitly approves a gameplay geometry change. Review external callers before introducing an interface.
5. In `take_damage()`, preserve damage labels, one-time `alive` guard, state DEAD, warning hide, deferred collision disable, and `defeated.emit(self, 8)` for the wolf / 6 for the cinder devil. The wolf branch calls `_wolf.die()`, holds the authored collapse for 4.0 seconds, then shrinks `_body` for 0.4 seconds and `queue_free()`s on the original 0.45+4.0+0.4 s lifecycle. The CharacterBody root stays identity-scaled. The cinder devil branch calls `_devil.die()` and holds its 0.90 s authored collapse before the same corpse path.
6. `_physics_process()` returns immediately when `not alive`; therefore a wolf visual sampled only from that function would freeze at the first death frame. Give the visual controller an explicit dead-state update path/own clock, or update presentation before the early return while preserving the AI return. Do not re-enable dead AI, collision, reward emission, or locomotion to make the animation run.
7. Keep the wolf and cinder devil branches separate. Do not leave two animation systems fighting over one imported rig, and do not fold one mob's presentation into the other to “simplify” the branch split.

## 6. Export/import and runtime inspection gates

1. Bake at 60 Hz; use the export recipe in [wolf authoring](wolf-authoring.md). The shipped script paints the albedo directly into the packed UV atlas from rest-space positions instead of relying on a scene bake. Verify required clip names/durations in exported data, skin joint count, embedded texture presence, consistent bind transforms and non-accumulating root tracks. No control-rig objects or unrelated source actions should ship.
2. Follow the existing `.glb.import` conventions: `nodes/use_name_suffixes=false`, animation sampling 60 fps, `gltf/embedded_image_handling=3` where that is the actual current importer key. Inspect the Ranger import file for precise current keys before editing; don't assume a guessed setting name. Confirm loop mode on idle/walk/trot and non-loop mode on attack/death in Godot itself; `_Loop` in a name is not proof.
3. Import with the resolved Godot executable, for example `& $Godot --headless --editor --path . --import`, checking exit code and parser/import errors. `$Godot` must already have been resolved from `GODOT_PATH` or the project's managed executable. Do not assume a cached `.godot` directory proves a clean checkout works.
4. Instantiate the real imported scene. Discover its Skeleton3D and AnimationPlayer paths; enumerate `AnimationPlayer.get_animation_list()` and `get_animation(name).length/loop_mode`, and inspect skeleton names/rests and mesh skin assignments. Compare to measured metadata. Fail visibly on missing required nodes/clips; do not silently play any available action.
5. Manually evaluate/render each clip at landmarks and loop seams. Verify -Z gameplay facing, upright metre scale, paws at floor, intact textures, jaw/head attachment and no root translation leakage. Then integrate in the actual enemy scene and perform [in-world acceptance](variants-and-evidence.md#delivery-and-evidence).

## Troubleshooting without hiding the cause

| Observation | Inspect and correct |
| --- | --- |
| Mesh explodes only after export | Bind/rest inverse matrices, unapplied/negative transforms, missing deform bones, skin weights; do not fix by rescaling the physics root |
| Paw slides while body moves | Measured stride, actual velocity input, foot's local stance speed, model scale and double root motion; a stronger IK pin alone hides a cadence error |
| Backward knees or one side twists | Bone roll/rest basis, mirror handedness and pole plane; do not negate arbitrary local Euler angles |
| Wolf sinks after repeated transitions | Authored pose snapshot before corrections, stale solved pose reuse and duplicate pose processing; never add an upward offset every switch |
| Rotation interpolation errors after sustained movement | Rotation-only nodes accumulating extracted scale, mixed scale/rotation ownership and invalid rest frames; construct the intended unit rotation at its producer, not a blanket orthonormalize-at-error patch |
| Attack impact looks late | Exported impact landmark, transition blending and sampling from new gameplay state/timer; do not move damage into a clip event |
| Death is frozen or rolls twice | Dead early return, two animation clocks and a leftover rotation or scale tween fighting the imported collapse |
| Trot loops pop or paws hop at wrap | Endpoint derivatives, double-held last sample, mismatched contact phase and incorrectly inferred loop settings |
| Cinder devil regresses | Shared `_body`/warning/`Geo`/death edits escaped the kind branch; restore the affected branch rather than adding the missing motion to the other mob |
