extends Node
## Manual bow and sword combat shared by the frontier and authoritative arena actors.

signal shot(origin: Vector3, direction: Vector3, speed: float, charge: float)

const Archer = preload("res://scripts/archer.gd")
const BASE_DAMAGE := [30.0, 38.0, 50.0]
var rig
var aim_point := Vector3.ZERO
var attack_progress := 1.0
var melee_progress := 1.0
var movement_mode := "STANDING"
var grounded := false
var actor: CharacterBody3D
var cover
var target_mask := 2
var source_id := -1
var damage_enabled := true
const MAX_SWEEP_STEPS := 32
const MAX_SWEEP_CONTACTS := 32
var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := CapsuleShape3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()
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
	_melee_query.shape = _melee_shape
	_melee_query.margin = 0.001
	_sight_query.collision_mask = 1

func set_aim(point: Vector3) -> void:
	if point.is_finite():
		aim_point = point
		update_aim()

func can_draw() -> bool:
	return rig.weapon == "bow" and grounded and rig.phase == "READY" and rig._roll_progress < 0.0 and _can_attack_from_cover()

func begin_draw() -> bool:
	if not can_draw():
		return false
	rig.begin_draw()
	update_aim()
	return true

func release_draw() -> void:
	if not _can_attack_from_cover():
		stop()
		return
	if rig.phase != "DRAWING" and rig.phase != "HOLDING":
		return
	update_aim()
	rig.release_string()

func stop() -> void:
	_melee_active = false
	rig.cancel_draw()

func begin_melee() -> bool:
	if not grounded or melee_progress < 1.0 - 0.000001 or not _can_attack_from_cover():
		return false
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
		_melee_victims[unit.get_instance_id()] = true
		unit.take_damage(float(Archer.SWORD_DATA[_swing_sword_index].damage), source_id)
	if world_fraction < 1.0:
		# An authored animation may continue beyond a wall; it must not resume
		# damage on the far side in the next sample of this same swing.
		_melee_blocked = true

func set_motion(actual_velocity: Vector3, running: bool, on_ground: bool) -> void:
	grounded = on_ground
	if Vector2(actual_velocity.x, actual_velocity.z).length_squared() <= 0.01:
		movement_mode = "STANDING"
	else:
		movement_mode = "RUNNING" if running else "WALKING"
	if is_instance_valid(cover) and cover.active:
		movement_mode = "PEEKING" if cover.peeking else "COVER"

func _can_attack_from_cover() -> bool:
	return not is_instance_valid(cover) or not cover.active or cover.peeking

func get_attack_interval() -> float:
	if rig.weapon == "sword" and rig.phase not in ["RELEASE", "RECOVER"]:
		return float(Archer.SWORD_DATA[rig.sword_index].seconds)
	return Archer.RELEASE_SECONDS + Archer.RECOVER_SECONDS

func advance(delta: float) -> void:
	if not _can_attack_from_cover() and rig.phase in ["DRAWING","HOLDING","MELEE"]:
		stop()
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
	if is_instance_valid(cover) and cover.active and is_instance_valid(actor):
		_sight_query.from = actor.global_position+Vector3.UP*1.4
		_sight_query.to = origin
		if not actor.get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty():
			# A weapon protruding through cover must still fire from this side of it.
			origin = _sight_query.from
	shot.emit(origin, direction, speed, clampf(charge, 0.0, 1.0))
