extends Node
## Manual bow and sword combat shared by the frontier and authoritative arena actors.

signal shot(origin: Vector3, direction: Vector3, speed: float, charge: float)
signal clash(position: Vector3)
signal defense_resolved(defender_slot: int, position: Vector3, parried: bool)

const Archer = preload("res://scripts/archer.gd")
const Geo = preload("res://scripts/geo.gd")
const BASE_DAMAGE := [30.0, 38.0, 50.0]
const PARRY_WINDOW := 0.25
const PARRY_STAGGER := 0.8
const BLOCK_STAMINA := 22.0
const BLOCK_PUSH_SPEED := 5.5
const BLOCK_FACING_DOT := 0.35
const CLASH_FACING_DOT := 0.35
const CLASH_BOUNCE_SPEED := 4.5
const CLASH_BOT_DELAY := 0.4
const DEFENSE_NONE := 0
const DEFENSE_PARRY := 1
const DEFENSE_BLOCK := 2
var rig
var aim_point := Vector3.ZERO
var attack_progress := 1.0
var melee_progress := 1.0
var movement_mode := "STANDING"
var grounded := false
var actor: CharacterBody3D
var cover
var cover_side: int = 1
var cover_aim_ready := true
var _cover_attack := false
var _auto_exposure := false
var _release_pending := false
var target_mask := 2
var source_id := -1
var damage_enabled := true
var blocking := false
var block_time := 0.0
var stagger_time := 0.0
var clash_cooldown := 0.0
const MAX_SWEEP_STEPS := 32
const MAX_SWEEP_CONTACTS := 32
var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := CapsuleShape3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()
var _shaft_query := PhysicsShapeQueryParameters3D.new()
var _shaft_shape := SphereShape3D.new()
var _melee_exclude: Array[RID] = []
var _source_exclude: Array[RID] = []
var _melee_victims: Dictionary = {}
var _melee_active := false
var _melee_blocked := false
var _swing_sword_index := -1

func setup(archer: Node3D, initial_aim: Vector3) -> void:
	rig = archer
	aim_point = initial_aim
	rig.arrow_released.connect(_on_rig_shot)
	rig.melee_started.connect(_on_melee_started)
	rig.melee_sweep.connect(_on_melee_sweep)
	rig.loadout_changed.connect(_on_loadout_changed)
	_melee_query.shape = _melee_shape
	_melee_query.margin = 0.001
	_sight_query.collision_mask = 1
	_shaft_shape.radius = 0.01
	_shaft_query.shape = _shaft_shape
	_shaft_query.collision_mask = 1
	_shaft_query.margin = 0.001

func set_aim(point: Vector3) -> void:
	if point.is_finite():
		aim_point = point
		update_aim()

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

func start_block(forward: Vector3) -> bool:
	if blocking:
		return true
	if not grounded or stagger_time > 0.0 or rig.weapon != "sword" \
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
	if not blocking or not is_instance_valid(rig) or rig.phase == "MELEE" \
			or rig._roll_progress >= 0.0:
		return DEFENSE_NONE
	if is_instance_valid(actor) and actor.get("alive") == false:
		return DEFENSE_NONE
	var origin: Vector3 = actor.global_position if is_instance_valid(actor) else rig.global_position
	var to_attacker := attacker_position - origin
	to_attacker.y = 0.0
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0.0
	if to_attacker.length_squared() > 0.000001 and forward.length_squared() > 0.000001 \
			and forward.normalized().dot(to_attacker.normalized()) < BLOCK_FACING_DOT:
		return DEFENSE_NONE
	return DEFENSE_PARRY if block_time <= PARRY_WINDOW else DEFENSE_BLOCK

func stagger(seconds: float) -> void:
	stagger_time = maxf(stagger_time,seconds)
	stop_block()
	_melee_active = false
	_melee_blocked = false
	_melee_victims.clear()
	_melee_exclude.clear()
	_source_exclude.clear()
	attack_progress = 1.0
	melee_progress = 1.0
	if is_instance_valid(rig) and rig.phase == "MELEE":
		rig.cancel_draw()

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
		rig.charge_frozen = true
		_try_cover_release()
		return
	update_aim()
	rig.release_string()

func _on_loadout_changed() -> void:
	if _cover_attack:
		stop()

func stop() -> void:
	_cover_attack = false
	_auto_exposure = false
	_release_pending = false
	_melee_active = false
	stop_block()
	rig.cancel_draw()

func wants_cover_exposure() -> bool:
	return _auto_exposure and _cover_attached() \
		and rig.phase in ["DRAWING","HOLDING","RELEASE"]

func _cover_attached() -> bool:
	return is_instance_valid(cover) and cover.active

func _accept_cover_draw() -> bool:
	if _cover_attached() and not cover.can_peek(cover_side):
		return false
	_cover_attack = _cover_attached()
	_auto_exposure = _cover_attack and not _can_release_from_cover()
	return true

func _try_cover_release() -> void:
	if not _release_pending or not _can_release_from_cover():
		return
	if rig.phase == "DRAWING" and rig._phase_time < Archer.RAISE_SECONDS:
		return
	# A remote camera must have observed this physical exposure before its
	# near-cover aim can authorize release. Charge stays frozen while it catches up.
	if not cover_aim_ready:
		return
	update_aim()
	if not _cover_shaft_clear():
		stop()
		return
	_release_pending = false
	rig.release_string()

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

func begin_melee() -> bool:
	if not grounded or melee_progress < 1.0 - 0.000001 or stagger_time > 0.0 \
			or rig.weapon != "sword" or rig.phase != "READY" or rig._roll_progress >= 0.0:
		return false
	stop()
	if _cover_attached():
		cover.exit()
		# Clear the visual constraint before the first swing pose, without moving or standing the body.
		rig.set_cover(false,Vector3.ZERO,cover.crouch_amount,false,Vector3.ZERO)
	update_aim()
	if rig.begin_melee():
		attack_progress = 0.0
		melee_progress = 0.0
		return true
	return false

func _on_melee_started() -> void:
	_melee_victims.clear()
	_melee_exclude.clear()
	_source_exclude.clear()
	_melee_active = true
	_melee_blocked = false
	_swing_sword_index = rig.sword_index
	if is_instance_valid(actor):
		_source_exclude.append(actor.get_rid())
		_melee_exclude.append(actor.get_rid())
	_sight_query.exclude = _source_exclude

func _can_damage_melee() -> bool:
	return damage_enabled and _melee_active and not _melee_blocked \
		and is_instance_valid(actor) and actor.get("alive") != false \
		and rig.weapon == "sword" and rig.phase == "MELEE" \
		and rig.sword_index == _swing_sword_index and rig._roll_progress < 0.0

func _on_melee_sweep(previous_base: Vector3, previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	if not _can_damage_melee() or radius <= 0.0:
		return
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
		_sweep_capsule(space, base_from, tip_from, base_to, tip_to, radius)
		if not _can_damage_melee():
			return

func _sweep_capsule(space: PhysicsDirectSpaceState3D, base_from: Vector3,
		tip_from: Vector3, base_to: Vector3, tip_to: Vector3, radius: float) -> void:
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
	_melee_query.collision_mask = 1
	_melee_query.exclude = _source_exclude
	# cast_motion ignores initial overlaps; test those explicitly first.
	if not space.get_rest_info(_melee_query).is_empty():
		_melee_blocked = true
		return
	_melee_query.motion = motion
	var world_fraction := 1.0
	if not motion.is_zero_approx():
		var world_cast := space.cast_motion(_melee_query)
		world_fraction = world_cast[0]
	_melee_query.collision_mask = target_mask
	for contact in MAX_SWEEP_CONTACTS:
		if not _can_damage_melee():
			return
		_melee_query.exclude = _melee_exclude
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
		_melee_exclude.append(hit.rid)
		var unit = instance_from_id(hit.collider_id)
		if not is_instance_valid(unit) or not unit.has_method("take_damage") \
				or unit.get("alive") != true or _melee_victims.has(unit.get_instance_id()):
			continue
		# The contact is on the actual blade query, never an actor-centered hit
		# fallback. This ray also prevents a windup starting through thin cover.
		_sight_query.from = actor.global_position + Vector3(0, 1.1, 0)
		_sight_query.to = hit.point
		if not space.intersect_ray(_sight_query).is_empty():
			continue
		var target_combat = unit.get("combat")
		if is_instance_valid(target_combat) and _can_clash_with(unit,target_combat):
			_resolve_clash(unit,target_combat,hit.point)
			return
		_melee_victims[unit.get_instance_id()] = true
		var damage := float(Archer.SWORD_DATA[_swing_sword_index].damage)
		var outcome := DEFENSE_NONE
		if unit.has_method("receive_melee"):
			outcome = int(unit.receive_melee(damage,source_id,actor.global_position))
		else:
			unit.take_damage(damage,source_id)
		if outcome == DEFENSE_PARRY:
			_block_feedback(unit,hit.point,true)
		elif outcome == DEFENSE_BLOCK:
			_block_feedback(unit,hit.point,false)
	if world_fraction < 1.0:
		# An authored animation may continue beyond a wall; it must not resume
		# damage on the far side in the next sample of this same swing.
		_melee_blocked = true

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
	_melee_active = false
	_melee_blocked = false
	_melee_victims.clear()
	_melee_exclude.clear()
	_source_exclude.clear()
	attack_progress = 1.0
	melee_progress = 1.0
	if is_instance_valid(rig) and rig.phase == "MELEE":
		rig.cancel_draw()

func _block_feedback(unit: Node, at: Vector3, parried: bool) -> void:
	var defender_slot := int(unit.get("slot")) if unit.get("slot") != null else -1
	defense_resolved.emit(defender_slot,at,parried)
	if not parried:
		# A held block is a neutral reset: the attacker's swing is knocked aside
		# instead of retaining a long recovery the defender could punish for free.
		abort_melee_to_neutral()
	elif is_instance_valid(actor) and actor.has_method("stagger"):
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

func get_attack_interval() -> float:
	if rig.weapon == "sword" and rig.phase not in ["RELEASE", "RECOVER"]:
		return float(Archer.SWORD_DATA[rig.sword_index].seconds)
	return Archer.RELEASE_SECONDS + Archer.RECOVER_SECONDS

func advance(delta: float) -> void:
	if stagger_time > 0.0:
		stagger_time = maxf(0.0,stagger_time-delta)
	if clash_cooldown > 0.0:
		clash_cooldown = maxf(0.0,clash_cooldown-delta)
	if blocking:
		if rig._roll_progress >= 0.0 \
				or (is_instance_valid(actor) and actor.get("alive") == false):
			stop_block()
		else:
			block_time += delta
	if _cover_attack:
		if not _cover_attached() or not grounded or rig._roll_progress >= 0.0 \
				or (is_instance_valid(actor) and actor.get("alive") == false):
			stop()
		elif rig.phase in ["RECOVER","READY"]:
			_cover_attack = false
			_auto_exposure = false
			_release_pending = false
		elif (_auto_exposure or _release_pending) and not cover.can_peek(cover_side):
			stop()
		elif _release_pending:
			if not _can_release_from_cover():
				_auto_exposure = true
			_try_cover_release()
	# Sword recovery continues across weapon swaps but never gates a bow draw.
	if melee_progress < 1.0:
		melee_progress = minf(1.0, melee_progress + delta / float(Archer.SWORD_DATA[rig.sword_index].seconds))
	# Bow readiness follows the actual release/re-nock animation, not a second timer.
	if rig.weapon == "bow" or rig.phase in ["RELEASE", "RECOVER"]:
		attack_progress = rig.get_bow_recovery_progress()
	else:
		attack_progress = melee_progress
	update_aim()

func update_aim() -> void:
	if rig.phase == "RELEASE" or rig.phase == "RECOVER":
		return
	# Aim is a world-space point from the camera ray, never a tracked unit or
	# a compensated ballistic solution. Gravity acts after the arrow is released.
	rig.aim_at(aim_point)

static func damage_for(bow_index: int, charge: float) -> float:
	return float(BASE_DAMAGE[bow_index]) * clampf(charge, 0.0, 1.0)


func _on_rig_shot(origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	attack_progress = 0.0
	# The checked visible shaft owns the muzzle; never relocate it to the chest.
	shot.emit(origin, direction, speed, clampf(charge, 0.0, 1.0))
