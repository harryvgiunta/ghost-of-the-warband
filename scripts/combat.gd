extends Node
## Manual bow and sword combat shared by the frontier and authoritative arena actors.

signal shot(origin: Vector3, direction: Vector3, speed: float, charge: float)
signal thrown(origin: Vector3, direction: Vector3, speed: float, charge: float, weapon: String, weapon_index: int)
signal clash(position: Vector3)
signal defense_resolved(defender_slot: int, position: Vector3, parried: bool)

const Archer = preload("res://scripts/archer.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const Geo = preload("res://scripts/geo.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const ImpactRules = preload("res://scripts/impact_rules.gd")
const BASE_DAMAGE := [30.0, 38.0, 50.0]
const PARRY_WINDOW := 0.25
const SHAFT_SETTLE_GRACE := 0.15
const PARRY_STAGGER := 0.8
# Attack interruption is a roll against the share of max health a hit removed.
# A chip under the floor never breaks a swing; a hit at the certain fraction
# always does; the chance ramps linearly between, so a pack of small enemies
# can be traded through while a big hit still lands with weight.
const HIT_STAGGER_FLOOR_FRACTION := 0.05
const HIT_STAGGER_CERTAIN_FRACTION := 0.50
const HIT_STAGGER_MIN := 0.08
const HIT_STAGGER_MAX := 0.62
const HIT_STAGGER_PER_FRACTION := 1.2
# The rig's recoil is presentation only: it rides the same curve but stays
# short enough that a shrugged-off chip still reads as a hit, not a stagger.
const HIT_REACT_MAX := 0.42
const BLOCK_STAMINA := 22.0
const DAGGER_BLOCK_STAMINA := 30.0
const SHIELD_BLOCK_STAMINA := 18.0
const WEAK_BLOCK_DAMAGE_SCALE := 0.5
const BLOCK_PUSH_SPEED := 5.5
const BLOCK_FACING_DOT := 0.35
const CLASH_FACING_DOT := 0.35
const CLASH_BOUNCE_SPEED := 4.5
const CLASH_BOT_DELAY := 0.4
const DEFENSE_NONE := 0
const DEFENSE_PARRY := 1
const DEFENSE_BLOCK := 2
const DEFENSE_WEAK_BLOCK := 3
var rig
var aim_point := Vector3.ZERO
var attack_progress := 1.0
var melee_progress := 1.0:
	set(value):
		melee_progress = value
		# Existing callers and tests reset the single-weapon recovery through
		# this field. Keep that behavior; per-hand dual recovery is explicit.
		if is_instance_valid(rig) and rig.weapon != "dual":
			right_melee_progress = value
var movement_mode := "STANDING"
var grounded := false
var actor: CharacterBody3D
var cover
var cover_side: int = 1
var cover_aim_ready := true
var _cover_attack := false
var _auto_exposure := false
var _release_pending := false
var _shaft_grace := 0.0
var _pending_throw := false
var target_mask := 2
var source_id := -1
var damage_enabled := true
## Backward reconciliation: the host's hitbox history, the rewind its owner
## needs for this fighter and the tick the host is simulating right now.
## `lag_ticks` is 0 for every body the host drives itself.
var lag_rewind = null
var lag_ticks := 0
var lag_tick := 0
## Incoming stagger multiplier from worn trinkets (1.0 is unmodified).
var stagger_scale := 1.0
# The last validated camera-ray muzzle. Arrows leave along this line instead of
# converging from the animated bow tip to the crosshair point.
var launch_origin := Vector3.INF
var launch_direction := Vector3.ZERO
const CAMERA_MUZZLE_FORWARD := 0.08
var blocking := false
var block_time := 0.0
var stagger_time := 0.0
var clash_cooldown := 0.0
const MAX_SWEEP_STEPS := 32
const MAX_SWEEP_CONTACTS := 32
const CLEAVE_ANGLE_PADDING := deg_to_rad(12.0)
const CLEAVE_BOTTOM := -0.25
const CLEAVE_TOP := 1.85
const MAX_CLEAVE_CONTACTS := 128
var _cleave_query := PhysicsShapeQueryParameters3D.new()
var _cleave_shape := CylinderShape3D.new()
var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := CapsuleShape3D.new()
var _blast_query := PhysicsShapeQueryParameters3D.new()
var _blast_shape := SphereShape3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()
# Camera projectile lanes include fighters; melee occlusion is scenery-only.
var _melee_sight_query := PhysicsRayQueryParameters3D.new()
var _shaft_query := PhysicsShapeQueryParameters3D.new()
var _shaft_shape := SphereShape3D.new()
var _launch_query := PhysicsShapeQueryParameters3D.new()
var _launch_shape := SphereShape3D.new()
var left_melee_progress := 1.0
var right_melee_progress := 1.0
var _left_swing_seconds := float(Archer.DAGGER_DATA.seconds)
var _right_swing_seconds := 1.0
var _swings: Dictionary = {}

func _swing_state(hand: String) -> Dictionary:
	if not _swings.has(hand):
		var excluded: Array[RID] = []
		_swings[hand] = {"active":false, "weapon":"", "damage":0.0,
			"victims":{}, "exclude":excluded, "blocked":false,
			"diagonal":false, "reach":0.0, "half_angle":0.0, "side":1.0, "cut":0.0}
	return _swings[hand]

func melee_progress_for(hand: String) -> float:
	return left_melee_progress if hand == "left" else right_melee_progress

func _set_melee_progress(hand: String, value: float) -> void:
	if hand == "left":
		left_melee_progress = value
	else:
		right_melee_progress = value

func _sync_display_progress() -> void:
	if is_instance_valid(rig) and rig.weapon == "dual":
		if rig.has_melee("right"):
			melee_progress = right_melee_progress
		elif rig.has_melee("left"):
			melee_progress = left_melee_progress
		else:
			melee_progress = minf(left_melee_progress,right_melee_progress)
	else:
		melee_progress = right_melee_progress

func setup(archer: Node3D, initial_aim: Vector3) -> void:
	rig = archer
	aim_point = initial_aim
	rig.arrow_released.connect(_on_rig_shot)
	rig.weapon_thrown.connect(_on_rig_throw)
	rig.melee_started.connect(_on_melee_started)
	rig.melee_sweep.connect(_on_melee_sweep)
	rig.loadout_changed.connect(_on_loadout_changed)
	_melee_query.shape = _melee_shape
	_melee_query.margin = 0.001
	_cleave_query.shape = _cleave_shape
	_cleave_query.margin = 0.0
	_blast_query.shape = _blast_shape
	_blast_query.margin = 0.0
	_melee_sight_query.collision_mask = 1
	_melee_sight_query.hit_from_inside = true
	_shaft_shape.radius = 0.01
	_shaft_query.shape = _shaft_shape
	_shaft_query.collision_mask = 1
	_shaft_query.margin = 0.001
	_launch_shape.radius = 0.02
	_launch_query.shape = _launch_shape
	_launch_query.collision_mask = 1
	_launch_query.margin = 0.001

func set_aim(point: Vector3) -> void:
	if point.is_finite():
		aim_point = point
		update_aim()

func clear_camera_ray() -> void:
	launch_origin = Vector3.INF
	launch_direction = Vector3.ZERO

func set_camera_ray(ray_origin: Vector3, ray_direction: Vector3) -> void:
	# Physics arrows follow the exact center crosshair, not a converging line
	# from the animated bow. The muzzle is relocated onto that camera ray only
	# when the point and its link to the rendered tip are clear; cover shots
	# whose visible shaft is exposed but whose camera ray is buried keep the
	# rendered tip instead of shooting through geometry.
	clear_camera_ray()
	if not is_instance_valid(actor) or not is_instance_valid(rig):
		return
	if not ray_origin.is_finite() or not ray_direction.is_finite():
		return
	var direction := ray_direction.normalized()
	if direction.length_squared() < 0.5:
		return
	var anchor: Vector3 = actor.global_position
	anchor.y += cover.camera_height() if is_instance_valid(cover) else 1.2
	var anchor_offset := anchor - ray_origin
	var actor_depth := maxf(0.0,anchor_offset.dot(direction))
	# A legitimate shoulder-camera ray passes within a shoulder offset of the
	# actor. Reject a client-supplied ray that would spawn the projectile away
	# from its shooter.
	if (anchor_offset - direction * actor_depth).length() > 2.0:
		return
	var aim_depth := (aim_point-ray_origin).dot(direction)
	if not is_finite(aim_depth) or aim_depth <= actor_depth + CAMERA_MUZZLE_FORWARD + 0.02:
		return
	var min_depth := actor_depth + CAMERA_MUZZLE_FORWARD
	var max_depth := aim_depth - 0.02
	var tip: Vector3 = rig.get_arrow_origin()
	var tip_depth := (tip-ray_origin).dot(direction)
	var space := actor.get_world_3d().direct_space_state
	var excluded: Array[RID] = [actor.get_rid()]
	var path_end := ray_origin + direction * max_depth
	# Prefer the camera-ray point nearest the rendered arrow tip so the visual
	# relocation is short. The capsule-depth muzzle is the fallback.
	for depth in [clampf(tip_depth,min_depth,max_depth),clampf(actor_depth+0.12,min_depth,max_depth)]:
		var origin := ray_origin + direction * float(depth)
		if not _launch_point_clear(space,origin,excluded):
			continue
		if not _launch_line_clear(space,origin,path_end,excluded):
			continue
		if not _launch_line_clear(space,tip,origin,excluded):
			continue
		launch_origin = origin
		launch_direction = direction
		return

func _launch_point_clear(space: PhysicsDirectSpaceState3D, point: Vector3, excluded: Array[RID]) -> bool:
	_launch_query.transform = Transform3D(Basis.IDENTITY,point)
	_launch_query.motion = Vector3.ZERO
	_launch_query.collision_mask = 1 | target_mask
	_launch_query.exclude = excluded
	return space.intersect_shape(_launch_query,1).is_empty()

func _launch_line_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excluded: Array[RID]) -> bool:
	if from.distance_squared_to(to) < 0.000001:
		return true
	_sight_query.from = from
	_sight_query.to = to
	_sight_query.collision_mask = 1 | target_mask
	_sight_query.exclude = excluded
	return space.intersect_ray(_sight_query).is_empty()

func can_draw() -> bool:
	return rig.weapon == "bow" and grounded and rig.phase == "READY" \
		and rig._roll_progress < 0.0 and stagger_time <= 0.0

func begin_draw() -> bool:
	if not can_draw() or not _accept_cover_draw():
		return false
	stop_block()
	rig.begin_draw()
	update_aim()
	return true

func can_throw() -> bool:
	return rig.weapon in ["sword","dagger","dual"] and grounded and rig.phase == "READY" \
		and rig._roll_progress < 0.0 and stagger_time <= 0.0 \
		and melee_progress >= 1.0-0.000001

func begin_throw() -> bool:
	if not can_throw() or not _accept_cover_draw():
		return false
	stop_block()
	if not rig.begin_throw():
		return false
	update_aim()
	return true

func release_throw() -> void:
	if rig.phase not in ["T_DRAW","T_HOLD"] or rig.weapon not in ["sword","dagger","dual"] \
			or _release_pending:
		return
	if _cover_attack and not _cover_attached():
		stop()
		return
	if _cover_attached():
		if not grounded or rig._roll_progress >= 0.0 or not cover.can_peek(cover_side):
			stop()
			return
		_cover_attack = true
		if not _can_release_from_cover():
			_auto_exposure = true
		_release_pending = true
		_pending_throw = true
		_shaft_grace = 0.0
		rig.charge_frozen = true
		_try_cover_release(0.0)
		return
	update_aim()
	rig.release_throw()

func start_block(forward: Vector3) -> bool:
	if blocking:
		if rig.weapon == "dual":
			stop_block()
			return false
		return true
	if not grounded or stagger_time > 0.0 or rig.weapon not in ["sword","dagger"] \
			or rig.phase != "READY" or rig._roll_progress >= 0.0:
		return false
	if is_instance_valid(actor) and actor.get("alive") == false:
		return false
	blocking = true
	block_time = 0.0
	rig.set_blocking(true,forward)
	return true

func stop_block() -> void:
	if not blocking:
		return
	blocking = false
	block_time = 0.0
	if is_instance_valid(rig):
		rig.set_blocking(false)

func face_block(forward: Vector3) -> void:
	if blocking and is_instance_valid(rig):
		rig.face_block(forward)

func resolve_melee_defense(attacker_position: Vector3) -> int:
	if not is_instance_valid(rig) or rig._roll_progress >= 0.0:
		return DEFENSE_NONE
	if is_instance_valid(actor) and actor.get("alive") == false:
		return DEFENSE_NONE
	var origin: Vector3 = actor.global_position if is_instance_valid(actor) else rig.global_position
	var to_attacker := attacker_position - origin
	to_attacker.y = 0.0
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0.0
	var facing := to_attacker.length_squared() <= 0.000001 or forward.length_squared() <= 0.000001 \
		or forward.normalized().dot(to_attacker.normalized()) >= BLOCK_FACING_DOT
	# Dual wielders cannot guard. Their active blade is the defense: a strike
	# already inside its authored contact window parries a front melee hit.
	if rig.weapon == "dual":
		return DEFENSE_PARRY if rig.in_strike_window() and facing else DEFENSE_NONE
	if not blocking or rig.is_melee() or not facing:
		return DEFENSE_NONE
	# A shield is a full front block and never parries.
	if rig.shield_equipped:
		return DEFENSE_BLOCK
	# A dagger cannot set a proper edge or lever: it never parries and only
	# softens a hit. Swords retain the timing-based parry/block split.
	if rig.weapon == "dagger":
		return DEFENSE_WEAK_BLOCK
	return DEFENSE_PARRY if block_time <= PARRY_WINDOW else DEFENSE_BLOCK

func block_stamina_cost() -> float:
	if rig.shield_equipped:
		return SHIELD_BLOCK_STAMINA
	return DAGGER_BLOCK_STAMINA if rig.weapon == "dagger" else BLOCK_STAMINA

static func stagger_chance(amount: float, max_health: float = 100.0) -> float:
	if max_health <= 0.0:
		return 1.0
	var fraction := maxf(amount,0.0)/max_health
	return clampf((fraction-HIT_STAGGER_FLOOR_FRACTION) \
		/(HIT_STAGGER_CERTAIN_FRACTION-HIT_STAGGER_FLOOR_FRACTION),0.0,1.0)

func stagger_from_damage(amount: float, max_health: float = 100.0) -> float:
	# Returns the rig's visible recoil in every case. Only a landed roll also
	# cancels the swing, guard and movement: the fraction of max health carries
	# the weight, so 5% chips are traded through and 50% hits always interrupt.
	var fraction := maxf(amount,0.0)/max_health if max_health > 0.0 else 1.0
	var seconds := clampf(HIT_STAGGER_MIN+fraction*HIT_STAGGER_PER_FRACTION,HIT_STAGGER_MIN,HIT_STAGGER_MAX) * clampf(stagger_scale,0.0,1.0)
	if randf() >= stagger_chance(amount,max_health):
		return minf(seconds,HIT_REACT_MAX)
	stagger(seconds)
	return seconds

func stagger(seconds: float) -> void:
	stagger_time = maxf(stagger_time,seconds)
	stop_block()
	for hand in ["left","right"]:
		var state := _swing_state(hand)
		state.active = false
		state.blocked = false
		state.victims.clear()
		state.exclude.clear()
	left_melee_progress = 1.0
	right_melee_progress = 1.0
	attack_progress = 1.0
	melee_progress = 1.0
	if is_instance_valid(rig) and rig.is_melee():
		rig.cancel_draw()
	if is_instance_valid(rig) and rig.is_ability():
		rig.cancel_ability()

func release_draw() -> void:
	if rig.phase not in ["DRAWING", "HOLDING"] or _release_pending:
		return
	if _cover_attack and not _cover_attached():
		stop()
		return
	if _cover_attached():
		if not grounded or rig._roll_progress >= 0.0 or not cover.can_peek(cover_side):
			stop()
			return
		_cover_attack = true
		if not _can_release_from_cover():
			_auto_exposure = true
		_release_pending = true
		_shaft_grace = 0.0
		_pending_throw = false
		rig.charge_frozen = true
		_try_cover_release(0.0)
		return
	update_aim()
	_release_archer()

func _release_archer() -> void:
	if launch_origin.is_finite() and launch_direction.length_squared() > 0.5:
		rig.release_string(launch_origin,launch_direction)
	else:
		rig.release_string()

func _on_loadout_changed() -> void:
	if _cover_attack:
		stop()

func stop() -> void:
	clear_camera_ray()
	_cover_attack = false
	_auto_exposure = false
	_release_pending = false
	_shaft_grace = 0.0
	_pending_throw = false
	for hand in ["left","right"]:
		var state := _swing_state(hand)
		state.active = false
		state.blocked = false
		state.victims.clear()
		state.exclude.clear()
	stop_block()
	rig.cancel_draw()
	if rig.is_ability():
		rig.cancel_ability()
	_sync_display_progress()

func wants_cover_exposure() -> bool:
	return _auto_exposure and _cover_attached() \
		and rig.phase in ["DRAWING","HOLDING","RELEASE","T_DRAW","T_HOLD","T_RELEASE"]

func _cover_attached() -> bool:
	return is_instance_valid(cover) and cover.active

func _accept_cover_draw() -> bool:
	if _cover_attached() and not cover.can_peek(cover_side):
		return false
	_cover_attack = _cover_attached()
	_auto_exposure = _cover_attack and not _can_release_from_cover()
	return true

func _try_cover_release(delta: float) -> void:
	if not _release_pending or not _can_release_from_cover():
		return
	if rig.phase in ["DRAWING","T_DRAW"] and rig._phase_time < Archer.RAISE_SECONDS:
		return
	# A remote camera must have observed this physical exposure before its
	# near-cover aim can authorize release. Charge stays frozen while it catches up.
	if not cover_aim_ready:
		return
	update_aim()
	if _pending_throw:
		if not _cover_throw_clear():
			stop()
			return
		_release_pending = false
		_pending_throw = false
		rig.release_throw()
		return
	if not _cover_shaft_clear():
		# A fresh exposure still has its lean/bow pose blending. Give the
		# settled pose a bounded chance to clear before calling it an obstruction.
		_shaft_grace += maxf(delta,0.0)
		if _shaft_grace < SHAFT_SETTLE_GRACE:
			return
		stop()
		return
	_shaft_grace = 0.0
	_release_pending = false
	_release_archer()

func _cover_shaft_clear() -> bool:
	if not is_instance_valid(actor):
		return false
	var nock: Vector3 = rig.active_bow.get_nock_position()
	var tip: Vector3 = rig.get_arrow_origin()
	var space := actor.get_world_3d().direct_space_state
	_shaft_query.transform = Transform3D(Basis.IDENTITY,nock)
	_shaft_query.motion = Vector3.ZERO
	# Sweeps ignore initial overlaps, including a nock buried inside cover.
	if not space.intersect_shape(_shaft_query,1).is_empty():
		return false
	_shaft_query.motion = tip-nock
	return space.cast_motion(_shaft_query)[0] >= 1.0

func _cover_throw_clear() -> bool:
	if not is_instance_valid(actor):
		return false
	var origin: Vector3 = rig.get_throw_origin()
	var direction: Vector3 = (aim_point-origin).normalized()
	if direction.length_squared() < 0.5:
		return false
	# The weapon leaves the exposed hand along the aim line. A wall between the
	# hand and the first metre of flight cancels the throw instead of passing
	# the weapon through cover.
	_sight_query.from = origin
	_sight_query.to = origin + direction*1.2
	_sight_query.collision_mask = 1
	var excluded: Array[RID] = []
	if is_instance_valid(actor):
		excluded.append(actor.get_rid())
	_sight_query.exclude = excluded
	return actor.get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty()

func begin_melee(hand: String = "right", variant: String = "overhead") -> bool:
	var key := "left" if hand == "left" else "right"
	if not grounded or stagger_time > 0.0 or rig._roll_progress >= 0.0:
		return false
	if key == "left":
		if rig.weapon != "dual":
			return false
	elif rig.weapon not in ["sword","dagger","dual"]:
		return false
	if variant not in ["overhead","diagonal_left","diagonal_right","stab"]:
		return false
	var requested := variant
	if melee_progress_for(key) < 1.0 - 0.000001 or not rig.can_begin_melee(key):
		return false
	var other_active: bool = rig.is_melee()
	if other_active and rig.weapon != "dual":
		return false
	if other_active:
		# Overlapping dual swing: the other hand keeps its clock and contacts.
		stop_block()
		if _cover_attached():
			cover.exit()
			rig.set_cover(false,Vector3.ZERO,cover.crouch_amount,false,Vector3.ZERO)
	else:
		stop()
		if _cover_attached():
			cover.exit()
			# Clear the visual constraint before the first swing pose, without moving or standing the body.
			rig.set_cover(false,Vector3.ZERO,cover.crouch_amount,false,Vector3.ZERO)
	update_aim()
	if not rig.begin_melee(key,requested):
		return false
	_set_melee_progress(key,0.0)
	attack_progress = 0.0
	_sync_display_progress()
	return true

func _on_melee_started(hand: String) -> void:
	var state := _swing_state(hand)
	state.active = true
	state.blocked = false
	state.weapon = rig.weapon
	state.damage = rig.melee_damage(hand)
	state.diagonal = rig.is_diagonal_swing(hand)
	state.reach = rig.melee_reach(hand)
	state.half_angle = rig.melee_half_angle(hand)
	state.variant = rig.melee_variant(hand)
	state.side = 1.0 if rig.melee_variant(hand) == "diagonal_right" else -1.0
	state.cut = 0.0
	state.victims.clear()
	state.exclude.clear()
	if is_instance_valid(actor):
		state.exclude.append(actor.get_rid())
	var seconds: float = rig.melee_seconds(hand)
	if hand == "left":
		_left_swing_seconds = seconds
	else:
		_right_swing_seconds = seconds

func _can_damage_melee(hand: String, state: Dictionary) -> bool:
	return damage_enabled and state.active and not state.blocked \
		and is_instance_valid(actor) and actor.get("alive") != false \
		and rig.weapon == state.weapon and rig.has_melee(hand) \
		and rig._roll_progress < 0.0

## Resolves one blade sample against the present world, then against the world
## the client's owner was drawing: a body that stepped out of the cut since the
## shooter's frame still takes the blow it saw land.
func _on_melee_sweep(hand: String, previous_base: Vector3, previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	var state := _swing_state(hand)
	if not _can_damage_melee(hand,state) or radius <= 0.0:
		return
	_sweep_blade(hand,state,previous_base,previous_tip,current_base,current_tip,radius)
	_lag_melee_strike(hand,state,current_base,current_tip,radius)

func _sweep_blade(hand: String, state: Dictionary, previous_base: Vector3, previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	if state.diagonal:
		_sweep_cleave(hand,state)
		return
	# Precision attacks still follow the blade. Daggers retain their short
	# thrust envelope; broad diagonal cuts use the frontal sweep above.
	var reach := 0.0
	var thicken := 0.0
	if (hand == "right" and rig.weapon == "dagger") \
			or (hand == "left" and rig.weapon == "dual"):
		reach = 0.38
		thicken = 0.06
	if reach > 0.0:
		var previous_length := (previous_tip-previous_base).length()
		var current_length := (current_tip-current_base).length()
		if previous_length > 0.0001:
			previous_tip += (previous_tip-previous_base)/previous_length*reach
		if current_length > 0.0001:
			current_tip += (current_tip-current_base)/current_length*reach
		radius += thicken
	# Translation is continuous (cast_motion), not discrete overlap sampling.
	# Subdivide rotation only. A small conservative capsule expansion encloses
	# both endpoint orientations, including stationary and very fast samples.
	var blade_change := (current_tip - current_base) - (previous_tip - previous_base)
	var steps := clampi(ceili(blade_change.length() / (radius * 0.25)), 1, MAX_SWEEP_STEPS)
	var space := actor.get_world_3d().direct_space_state
	for step in steps:
		var start_fraction := float(step) / steps
		var end_fraction := float(step + 1) / steps
		var base_from := previous_base.lerp(current_base, start_fraction)
		var tip_from := previous_tip.lerp(current_tip, start_fraction)
		var base_to := previous_base.lerp(current_base, end_fraction)
		var tip_to := previous_tip.lerp(current_tip, end_fraction)
		_sweep_capsule(space,hand,state,base_from,tip_from,base_to,tip_to,radius)
		if not _can_damage_melee(hand,state):
			return

func _sweep_cleave(hand: String, state: Dictionary) -> void:
	# Sweep a body-height sector in the same direction and active interval as
	# the visible diagonal. It reaches point-blank and short foes without
	# demanding that a thin animated blade cross their exact height.
	var cut: float = rig.melee_cut_curve(hand)
	var angle_from: float = state.side * lerpf(state.half_angle,-state.half_angle,state.cut)
	var angle_to: float = state.side * lerpf(state.half_angle,-state.half_angle,cut)
	state.cut = cut
	var low := maxf(-PI*0.5,minf(angle_from,angle_to)-CLEAVE_ANGLE_PADDING)
	var high := minf(PI*0.5,maxf(angle_from,angle_to)+CLEAVE_ANGLE_PADDING)
	var forward: Vector3 = aim_point-rig.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	_cleave_shape.radius = state.reach
	_cleave_shape.height = CLEAVE_TOP-CLEAVE_BOTTOM
	_cleave_query.transform = Transform3D(Basis.IDENTITY,
		actor.global_position+Vector3.UP*(CLEAVE_TOP+CLEAVE_BOTTOM)*0.5)
	_cleave_query.collision_mask = target_mask
	_cleave_query.exclude = state.exclude
	var space := actor.get_world_3d().direct_space_state
	var hits := space.intersect_shape(_cleave_query,MAX_CLEAVE_CONTACTS)
	for hit in hits:
		if not _can_damage_melee(hand,state):
			return
		var unit = hit.collider
		if not is_instance_valid(unit) or not unit.has_method("take_damage") \
				or unit.get("alive") != true or state.victims.has(unit.get_instance_id()):
			continue
		var offset: Vector3 = unit.global_position-actor.global_position
		offset.y = 0.0
		var angle := atan2(offset.dot(right),offset.dot(forward))
		if angle < low or angle > high:
			continue
		var contact: Vector3 = unit.get_aim_position()
		contact.y = clampf(contact.y,actor.global_position.y+CLEAVE_BOTTOM+0.05,
			actor.global_position.y+CLEAVE_TOP-0.05)
		_melee_sight_query.from = actor.global_position+Vector3(0,1.0-0.45*rig._crouch_amount,0)
		_melee_sight_query.to = contact
		_melee_sight_query.exclude = state.exclude
		# Scenery occludes each target, not the entire crowd: hitting a wall on
		# one flank cannot swallow the clear part of the same cut.
		if not space.intersect_ray(_melee_sight_query).is_empty():
			continue
		state.exclude.append(hit.rid)
		_resolve_melee_contact(hand,state,unit,contact,false)

func _sweep_capsule(space: PhysicsDirectSpaceState3D, hand: String, state: Dictionary,
		base_from: Vector3, tip_from: Vector3, base_to: Vector3, tip_to: Vector3,
		radius: float) -> void:
	var blade_from := tip_from - base_from
	var blade_to := tip_to - base_to
	var blade := (blade_from + blade_to) * 0.5
	var center := (base_from + tip_from) * 0.5
	var motion := (base_to + tip_to) * 0.5 - center
	var padding := (blade_to - blade_from).length() * 0.25
	_melee_shape.radius = radius + padding
	_melee_shape.height = blade.length() + 2.0 * _melee_shape.radius
	var axis := blade.normalized() if blade.length_squared() > 0.000001 else Vector3.UP
	var tangent := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var pose := Transform3D(Basis(tangent, axis, tangent.cross(axis)), center)
	_melee_query.transform = pose
	_melee_query.motion = Vector3.ZERO
	var world_fraction := 1.0
	_melee_query.collision_mask = 1
	_melee_query.exclude = state.exclude
	# cast_motion ignores initial overlaps; test those explicitly first.
	if not space.get_rest_info(_melee_query).is_empty():
		state.blocked = true
		return
	_melee_query.motion = motion
	if not motion.is_zero_approx():
		var world_cast := space.cast_motion(_melee_query)
		world_fraction = world_cast[0]
	_melee_query.collision_mask = target_mask
	for contact in MAX_SWEEP_CONTACTS:
		if not _can_damage_melee(hand,state):
			return
		_melee_query.exclude = state.exclude
		_melee_query.transform = pose
		_melee_query.motion = Vector3.ZERO
		var hit := space.get_rest_info(_melee_query)
		if hit.is_empty():
			if motion.is_zero_approx():
				break
			_melee_query.motion = motion
			var target_cast := space.cast_motion(_melee_query)
			if target_cast[1] >= world_fraction or target_cast[1] >= 1.0:
				break
			_melee_query.transform.origin = center + motion * target_cast[1]
			_melee_query.motion = Vector3.ZERO
			hit = space.get_rest_info(_melee_query)
			if hit.is_empty():
				break
		# Exclude every visited collider so dead/non-damageable bodies cannot
		# monopolize the bounded query loop. Victims persist for the whole swing.
		state.exclude.append(hit.rid)
		var unit = instance_from_id(hit.collider_id)
		if not is_instance_valid(unit) or not unit.has_method("take_damage") \
				or unit.get("alive") != true or state.victims.has(unit.get_instance_id()):
			continue
		# A contact the shooter's own frame could not have produced is not a hit:
		# the body was never under their blade.
		if lag_ticks > 0 and is_instance_valid(lag_rewind) \
				and lag_rewind.refuses(unit.get_instance_id(),lag_tick - lag_ticks,
					base_to,tip_to,radius):
			continue
		# The contact is on the actual blade query, never an actor-centered hit
		# fallback. This ray also prevents a windup starting through thin cover.
		_melee_sight_query.from = actor.global_position + Vector3(0, 1.1, 0)
		_melee_sight_query.to = hit.point
		_melee_sight_query.exclude = state.exclude
		if not space.intersect_ray(_melee_sight_query).is_empty():
			continue
		var headshot := Hitbox.blade_headshot(unit,base_from,tip_from,radius) \
			or Hitbox.blade_headshot(unit,base_to,tip_to,radius)
		_resolve_melee_contact(hand,state,unit,hit.point,headshot)
	if world_fraction < 1.0:
		# An authored animation may continue beyond a wall; it must not resume
		# damage on the far side in the next sample of this same swing.
		state.blocked = true

## Adds the victims this blade sample had in the world the client was drawing.
## Everything downstream is the ordinary contact path, so blocks, parries, blood
## and damage numbers behave exactly as they do for a present-time hit.
func _lag_melee_strike(hand: String, state: Dictionary, base: Vector3, tip: Vector3,
		radius: float) -> void:
	if lag_ticks <= 0 or not is_instance_valid(lag_rewind) or not damage_enabled:
		return
	var tick := lag_tick - lag_ticks
	var space := actor.get_world_3d().direct_space_state
	var forward: Vector3 = aim_point-actor.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var low := -PI
	var high := PI
	if state.diagonal:
		var cut: float = rig.melee_cut_curve(hand)
		var angle_from: float = state.side * lerpf(state.half_angle,-state.half_angle,state.cut)
		var angle_to: float = state.side * lerpf(state.half_angle,-state.half_angle,cut)
		low = maxf(-PI*0.5,minf(angle_from,angle_to)-CLEAVE_ANGLE_PADDING)
		high = minf(PI*0.5,maxf(angle_from,angle_to)+CLEAVE_ANGLE_PADDING)
	for candidate in lag_rewind.candidates(tick):
		if not is_instance_valid(candidate) or not candidate.has_method("take_damage"):
			continue
		if candidate.get("alive") != true:
			continue
		if state.victims.has(candidate.get_instance_id()) or state.exclude.has(candidate.get_rid()):
			continue
		var historical: Vector3 = lag_rewind.position_at(candidate.get_instance_id(),tick)
		if not historical.is_finite():
			continue
		if state.diagonal:
			var offset: Vector3 = historical-actor.global_position
			offset.y = 0.0
			if offset.length() > state.reach+0.45:
				continue
			var angle := atan2(offset.dot(right),offset.dot(forward))
			if angle < low or angle > high:
				continue
		elif not lag_rewind.segment_hits(candidate.get_instance_id(),tick,base,tip,radius):
			continue
		var contact: Vector3 = historical+Vector3.UP*1.1
		_melee_sight_query.from = actor.global_position + Vector3(0, 1.1, 0)
		_melee_sight_query.to = contact
		_melee_sight_query.exclude = state.exclude
		if not space.intersect_ray(_melee_sight_query).is_empty():
			continue
		state.exclude.append(candidate.get_rid())
		_resolve_melee_contact(hand,state,candidate,contact,false)


func _impact_force(state: Dictionary, at: Vector3, unit: Node3D) -> Vector3:
	var style := str(state.get("variant", "overhead"))
	if style == "ability":
		var origin: Vector3 = state.get("force_origin", actor.global_position)
		return ImpactRules.radial_force(origin, unit.global_position)
	var forward: Vector3 = aim_point - actor.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return ImpactRules.melee_force(actor.global_position, forward, right, at, style,
		float(state.get("side", 1.0)))


func _resolve_melee_contact(hand: String, state: Dictionary, unit: Node3D,
		at: Vector3, headshot: bool) -> int:
	var target_combat = unit.get("combat")
	if is_instance_valid(target_combat) and _can_clash_with(unit,target_combat):
		_resolve_clash(unit,target_combat,at)
		return DEFENSE_NONE
	state.victims[unit.get_instance_id()] = true
	var damage: float = state.damage
	var outcome := DEFENSE_NONE
	# Name the striker before the blow lands so a mob can turn on the ranger
	# that hit it, even a backstab it never saw coming.
	if is_instance_valid(actor) and unit.has_method("note_attacker"):
		unit.note_attacker(actor)
	if unit.has_method("note_impact"):
		unit.note_impact(_impact_force(state, at, unit))
	if unit.has_method("receive_melee"):
		outcome = int(unit.receive_melee(damage,source_id,actor.global_position,headshot))
	else:
		unit.take_damage(damage,source_id,headshot)
	if outcome == DEFENSE_PARRY:
		_block_feedback(unit,at,true,hand)
	elif outcome == DEFENSE_BLOCK:
		_block_feedback(unit,at,false,hand)
	elif outcome == DEFENSE_WEAK_BLOCK:
		_block_feedback(unit,at,false,hand,false)
	else:
		# Unmitigated contact: directional spray at the wound and the blade
		# that opened it. The target's take_damage owns body and floor blood.
		BloodFx.impact(actor,at,at-actor.global_position,damage,headshot)
		BloodFx.stain_weapon(rig,damage,hand)
		if actor.has_method("note_weapon_blood"):
			actor.note_weapon_blood(damage)
		if _unit_is_dead(unit):
			# The kill throws blood back over the body that landed it.
			BloodFx.spatter_kill(actor,rig,at,damage)
	return outcome

## One radial beat of an item skill: an arc in front of the body or a full
## ring around it. Reuses the melee contact path so blocks, armor, blood and
## damage numbers behave exactly like an authored swing. Returns victims hit.
## `victims` is shared across every beat of one activation (a travelling lunge
## sweeps the same dictionary each tick), so no body is ever struck twice.
func ability_strike(radius: float, arc_degrees: float, damage: float,
		stagger_seconds: float = 0.0, ring: bool = false,
		require_sight: bool = true, victims: Dictionary = {}) -> int:
	if not is_instance_valid(actor):
		return 0
	var struck := _ability_area(actor.global_position+Vector3.UP*0.95,radius,damage,
		stagger_seconds,arc_degrees,ring,require_sight,victims)
	struck += _lag_area_strike(actor.global_position+Vector3.UP*0.95,radius,damage,
		stagger_seconds,arc_degrees,ring,require_sight,victims)
	return struck

## A blast centred away from the caster (a fireball burst). Sight is ignored:
## the explosion owns the space it fills.
func ability_blast(centre: Vector3, radius: float, damage: float,
		stagger_seconds: float = 0.0) -> int:
	var struck := _ability_area(centre,radius,damage,stagger_seconds,360.0,true,false)
	struck += _lag_area_strike(centre,radius,damage,stagger_seconds,360.0,true,false)
	return struck


## The same radial beat against the bodies as their owner last saw them.
func _lag_area_strike(centre: Vector3, radius: float, damage: float,
		stagger_seconds: float, arc_degrees: float, ring: bool,
		require_sight: bool, victims: Dictionary = {}) -> int:
	if lag_ticks <= 0 or not is_instance_valid(lag_rewind) or not damage_enabled:
		return 0
	if not is_instance_valid(actor) or actor.get("alive") == false or radius <= 0.0:
		return 0
	var tick := lag_tick - lag_ticks
	var space := actor.get_world_3d().direct_space_state
	var forward: Vector3 = aim_point-actor.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var half := deg_to_rad(clampf(arc_degrees,0.0,360.0))*0.5
	var struck := 0
	for candidate in lag_rewind.candidates(tick):
		if not is_instance_valid(candidate) or not candidate.has_method("take_damage"):
			continue
		if candidate == actor or candidate.get("alive") != true:
			continue
		if victims.has(candidate.get_instance_id()) or candidate.get_rid() == actor.get_rid():
			continue
		var historical: Vector3 = lag_rewind.position_at(candidate.get_instance_id(),tick)
		if not historical.is_finite():
			continue
		if not lag_rewind.sphere_hits(candidate.get_instance_id(),tick,centre,radius):
			continue
		if not ring and arc_degrees < 359.5:
			var offset: Vector3 = historical-actor.global_position
			offset.y = 0.0
			if absf(atan2(offset.dot(right),offset.dot(forward))) > half:
				continue
		var contact: Vector3 = historical+Vector3.UP*0.95
		if require_sight:
			_melee_sight_query.from = actor.global_position+Vector3(0,1.1-0.45*rig._crouch_amount,0)
			_melee_sight_query.to = contact
			_melee_sight_query.exclude = [actor.get_rid()]
			if not space.intersect_ray(_melee_sight_query).is_empty():
				continue
		victims[candidate.get_instance_id()] = true
		var state := {
			"active": true, "blocked": false, "weapon": rig.weapon,
			"damage": damage, "diagonal": false, "reach": radius,
			"victims": victims, "exclude": [actor.get_rid()],
			"variant": "ability", "force_origin": centre,
		}
		_resolve_melee_contact("right",state,candidate,contact,false)
		struck += 1
		if stagger_seconds > 0.0:
			var target_combat = candidate.get("combat")
			if is_instance_valid(target_combat) and target_combat.has_method("stagger"):
				target_combat.stagger(stagger_seconds)
			elif candidate.has_method("stagger"):
				candidate.stagger(stagger_seconds)
	return struck


func _ability_area(centre: Vector3, radius: float, damage: float,
		stagger_seconds: float, arc_degrees: float, ring: bool,
		require_sight: bool, victims: Dictionary = {}) -> int:
	if not damage_enabled or not is_instance_valid(actor) or not is_instance_valid(rig):
		return 0
	if actor.get("alive") == false or radius <= 0.0:
		return 0
	var state := {
		"active": true, "blocked": false, "weapon": rig.weapon,
		"damage": damage, "diagonal": false, "reach": radius,
		"victims": victims, "exclude": [actor.get_rid()],
		"variant": "ability", "force_origin": centre,
	}
	var forward: Vector3 = aim_point-actor.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -rig.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var half := deg_to_rad(clampf(arc_degrees,0.0,360.0))*0.5
	_blast_shape.radius = radius
	_blast_query.transform = Transform3D(Basis.IDENTITY,centre)
	_blast_query.collision_mask = target_mask
	_blast_query.exclude = state.exclude
	var space := actor.get_world_3d().direct_space_state
	var hits := space.intersect_shape(_blast_query,MAX_CLEAVE_CONTACTS)
	var hit_count := 0
	for hit in hits:
		var unit = hit.collider
		if not is_instance_valid(unit) or not unit.has_method("take_damage") \
				or unit.get("alive") != true or state.victims.has(unit.get_instance_id()):
			continue
		var offset: Vector3 = unit.global_position-actor.global_position
		offset.y = 0.0
		if not ring and float(arc_degrees) < 359.5:
			var angle := atan2(offset.dot(right),offset.dot(forward))
			if absf(angle) > half:
				continue
		var contact: Vector3 = unit.get_aim_position() if unit.has_method("get_aim_position") \
			else unit.global_position
		if require_sight:
			_melee_sight_query.from = actor.global_position+Vector3(0,1.1-0.45*rig._crouch_amount,0)
			_melee_sight_query.to = contact
			_melee_sight_query.exclude = state.exclude
			if not space.intersect_ray(_melee_sight_query).is_empty():
				continue
		state.exclude.append(hit.rid)
		var outcome := _resolve_melee_contact("right",state,unit,contact,false)
		hit_count += 1
		if outcome == DEFENSE_NONE and stagger_seconds > 0.0:
			var target_combat = unit.get("combat")
			if is_instance_valid(target_combat) and target_combat.has_method("stagger"):
				target_combat.stagger(stagger_seconds)
			elif unit.has_method("stagger"):
				unit.stagger(stagger_seconds)
	return hit_count

func _unit_is_dead(unit: Node) -> bool:
	var flag = unit.get("alive")
	if flag != null:
		return not bool(flag)
	return unit.has_method("is_dead") and bool(unit.is_dead())

func _can_clash_with(unit: Node, target_combat) -> bool:
	if target_combat == self or not is_instance_valid(target_combat) \
			or not is_instance_valid(actor) or not is_instance_valid(rig):
		return false
	var other_rig = target_combat.rig
	if not is_instance_valid(other_rig) or other_rig.weapon != "sword" \
			or not other_rig.in_strike_window():
		return false
	if rig.weapon != "sword" or not rig.in_strike_window():
		return false
	var delta: Vector3 = unit.global_position - actor.global_position
	delta.y = 0.0
	if delta.length_squared() < 0.000001:
		return false
	var direction := delta.normalized()
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0.0
	var other_forward: Vector3 = -other_rig.global_basis.z
	other_forward.y = 0.0
	return forward.length_squared() > 0.000001 and other_forward.length_squared() > 0.000001 \
		and forward.normalized().dot(direction) >= CLASH_FACING_DOT \
		and other_forward.normalized().dot(-direction) >= CLASH_FACING_DOT

func _resolve_clash(unit: Node, target_combat, at: Vector3) -> void:
	var delta: Vector3 = unit.global_position - actor.global_position
	delta.y = 0.0
	var direction: Vector3 = -rig.global_basis.z
	if delta.length_squared() > 0.000001:
		direction = delta.normalized()
	if actor.has_method("clash_bounce"):
		actor.clash_bounce(-direction)
	if unit.has_method("clash_bounce"):
		unit.clash_bounce(direction)
	abort_melee_to_neutral()
	target_combat.abort_melee_to_neutral()
	# Only the detecting bot waits; the other may swing first next frame.
	# Symmetric delays would make two bots re-clash forever in lockstep.
	clash_cooldown = CLASH_BOT_DELAY
	target_combat.clash_cooldown = 0.0
	clash.emit(at)

func abort_melee_to_neutral() -> void:
	for hand in ["left","right"]:
		var state := _swing_state(hand)
		state.active = false
		state.blocked = false
		state.victims.clear()
		state.exclude.clear()
	left_melee_progress = 1.0
	right_melee_progress = 1.0
	attack_progress = 1.0
	melee_progress = 1.0
	if is_instance_valid(rig) and rig.is_melee():
		rig.cancel_draw()

func abort_swing(hand: String) -> void:
	var state := _swing_state(hand)
	state.active = false
	state.blocked = false
	state.victims.clear()
	state.exclude.clear()
	_set_melee_progress(hand,1.0)
	if is_instance_valid(rig):
		rig.abort_melee(hand)
	_sync_display_progress()
	attack_progress = melee_progress

func _block_feedback(unit: Node, at: Vector3, parried: bool,
		hand: String, reset_attacker: bool = true) -> void:
	var defender_slot := int(unit.get("slot")) if unit.get("slot") != null else -1
	defense_resolved.emit(defender_slot,at,parried)
	if not parried and reset_attacker:
		# A held block knocks aside the swing that contacted it. A dual wielder's
		# other hand keeps its own clock and can continue into the opening.
		abort_swing(hand)
	elif parried and is_instance_valid(actor) and actor.has_method("stagger"):
		actor.stagger(PARRY_STAGGER)

static func spawn_impact(parent: Node3D, at: Vector3, kind: String) -> void:
	if not is_instance_valid(parent):
		return
	var color := Color("ffd37a")
	if kind == "parry":
		color = Color("bff4ff")
	elif kind == "block":
		color = Color("9fc9ff")
	var mat := Geo.material(color,0.3,0.25)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var root := Node3D.new()
	root.name = "DefenseImpact"
	parent.add_child(root)
	root.global_position = at
	var directions := [
		Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK,
		(Vector3.RIGHT+Vector3.UP).normalized(),(Vector3.LEFT+Vector3.UP).normalized(),
		(Vector3.FORWARD+Vector3.RIGHT).normalized(),(Vector3.BACK+Vector3.LEFT).normalized()]
	for direction in directions:
		var beam := Geo.beam(root,Vector3.ZERO,direction*0.42,0.016,mat,4)
		beam.scale = Vector3.ONE*0.2
		var tween := beam.create_tween()
		tween.set_parallel(true)
		tween.tween_property(beam,"scale",Vector3.ONE*1.25,0.15)
		tween.tween_property(beam,"transparency",1.0,0.18)
	var core := Geo.sphere(root,0.10,Vector3.ZERO,mat)
	core.scale = Vector3.ONE*0.3
	var core_tween := core.create_tween()
	core_tween.set_parallel(true)
	core_tween.tween_property(core,"scale",Vector3.ONE*2.4,0.12)
	core_tween.tween_property(core,"transparency",1.0,0.16)
	var life := root.create_tween()
	life.tween_interval(0.22)
	life.tween_callback(root.queue_free)

func set_motion(actual_velocity: Vector3, running: bool, on_ground: bool) -> void:
	grounded = on_ground
	if Vector2(actual_velocity.x, actual_velocity.z).length_squared() <= 0.01:
		movement_mode = "STANDING"
	else:
		movement_mode = "RUNNING" if running else "WALKING"
	if is_instance_valid(cover) and cover.active:
		movement_mode = "PEEKING" if cover.peeking else "COVER"

func _can_release_from_cover() -> bool:
	return not _cover_attached() or (cover.peeking and (cover.low \
		or cover.lean.dot(cover.normal.cross(Vector3.UP))*float(cover_side) > 0.0))

func get_attack_interval(hand: String = "") -> float:
	if rig.weapon in ["sword","dagger","dual"] and rig.phase not in ["RELEASE", "RECOVER", "T_RELEASE", "T_RECOVER"]:
		return rig.melee_seconds(hand)
	return Archer.RELEASE_SECONDS + Archer.RECOVER_SECONDS

func advance(delta: float) -> void:
	if stagger_time > 0.0:
		stagger_time = maxf(0.0,stagger_time-delta)
	if clash_cooldown > 0.0:
		clash_cooldown = maxf(0.0,clash_cooldown-delta)
	if blocking:
		if rig.weapon == "dual" or rig._roll_progress >= 0.0 \
				or (is_instance_valid(actor) and actor.get("alive") == false):
			stop_block()
		else:
			block_time += delta
	if _cover_attack:
		if not _cover_attached() or not grounded or rig._roll_progress >= 0.0 \
				or (is_instance_valid(actor) and actor.get("alive") == false):
			stop()
		elif rig.phase in ["RECOVER","READY","T_RECOVER"]:
			_cover_attack = false
			_auto_exposure = false
			_release_pending = false
			_pending_throw = false
		elif (_auto_exposure or _release_pending) and not cover.can_peek(cover_side):
			stop()
		elif _release_pending:
			if not _can_release_from_cover():
				_auto_exposure = true
			_try_cover_release(delta)
	# Each hand recovers independently. Sword recovery continues across weapon
	# swaps but never gates a bow draw.
	if left_melee_progress < 1.0:
		left_melee_progress = minf(1.0,left_melee_progress + delta / maxf(_left_swing_seconds,0.001))
	if right_melee_progress < 1.0:
		right_melee_progress = minf(1.0,right_melee_progress + delta / maxf(_right_swing_seconds,0.001))
	_sync_display_progress()
	# Bow readiness follows the actual release/re-nock animation, not a second timer.
	if rig.weapon == "bow" or rig.phase in ["RELEASE", "RECOVER", "T_RELEASE", "T_RECOVER"]:
		attack_progress = rig.get_recovery_progress()
	else:
		attack_progress = melee_progress
	update_aim()

func update_aim() -> void:
	if rig.phase in ["RELEASE","RECOVER","T_RELEASE","T_RECOVER"]:
		return
	# Aim is a world-space point from the camera ray, never a tracked unit or
	# a compensated ballistic solution. Gravity acts after the arrow is released.
	rig.aim_at(aim_point)

## `scale` is the shooter's trinket multiplier; enemies pass nothing.
static func damage_for(bow_index: int, charge: float, scale: float = 1.0) -> float:
	return float(BASE_DAMAGE[bow_index]) * clampf(charge, 0.0, 1.0) * maxf(scale, 0.0)

static func throw_damage(weapon_name: String, weapon_index: int, charge: float,
		scale: float = 1.0) -> float:
	var base := float(Archer.DAGGER_DATA.damage) if weapon_name == "dagger" \
		else float(Archer.SWORD_DATA[clampi(weapon_index,0,2)].damage)
	return base * clampf(charge, 0.0, 1.0) * maxf(scale, 0.0)


func _on_rig_shot(origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	attack_progress = 0.0
	# The checked visible shaft owns the muzzle; never relocate it to the chest.
	shot.emit(origin, direction, speed, clampf(charge, 0.0, 1.0))

func _on_rig_throw(origin: Vector3, direction: Vector3, speed: float, charge: float,
		weapon_name: String, weapon_index: int) -> void:
	attack_progress = 0.0
	thrown.emit(origin, direction, speed, clampf(charge, 0.0, 1.0), weapon_name, weapon_index)
