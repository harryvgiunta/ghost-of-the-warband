extends Node
## Manual bow and sword combat shared by the frontier and authoritative arena actors.

signal shot(origin: Vector3, direction: Vector3, speed: float, charge: float)

const Archer = preload("res://scripts/archer.gd")
const BASE_DAMAGE := [30.0, 38.0, 50.0]
var rig
var aim_point := Vector3.ZERO
var attack_progress := 1.0
var movement_mode := "STANDING"
var grounded := false
var actor: CharacterBody3D
var target_mask := 2
var source_id := -1
var damage_enabled := true
var _melee_query := PhysicsShapeQueryParameters3D.new()
var _melee_shape := SphereShape3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()

func setup(archer: Node3D, initial_aim: Vector3) -> void:
	rig = archer
	aim_point = initial_aim
	rig.arrow_released.connect(_on_rig_shot)
	rig.melee_strike.connect(_on_melee_strike)
	_melee_query.shape = _melee_shape

func set_aim(point: Vector3) -> void:
	if point.is_finite():
		aim_point = point
		update_aim()

func can_draw() -> bool:
	return rig.weapon == "bow" and grounded and attack_progress >= 1.0 - 0.000001 and rig.phase in ["READY", "RECOVER"]

func begin_draw() -> bool:
	if not can_draw():
		return false
	rig.begin_draw()
	update_aim()
	return true

func release_draw() -> void:
	if rig.phase != "DRAWING" and rig.phase != "HOLDING":
		return
	update_aim()
	rig.release_string()

func stop() -> void:
	rig.cancel_draw()

func begin_melee() -> bool:
	if not grounded or attack_progress < 1.0 - 0.000001:
		return false
	update_aim()
	if rig.begin_melee():
		attack_progress = 0.0
		return true
	return false

func _on_melee_strike() -> void:
	if not damage_enabled or not is_instance_valid(actor) or rig.weapon != "sword":
		return
	var data: Dictionary = Archer.SWORD_DATA[rig.sword_index]
	var origin := actor.global_position + Vector3(0,1.1,0)
	_melee_shape.radius = float(data.reach)
	_melee_query.transform = Transform3D(Basis.IDENTITY,origin)
	_melee_query.collision_mask = target_mask
	_melee_query.exclude = [actor.get_rid()]
	_sight_query.collision_mask = 1 | target_mask
	_sight_query.exclude = [actor.get_rid()]
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var damaged: Dictionary = {}
	for result: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(_melee_query,16):
		var unit = result.collider
		if not unit.has_method("take_damage") or not unit.has_method("get_aim_position") or not unit.alive or damaged.has(unit):
			continue
		var point: Vector3 = unit.get_aim_position()
		var offset := point-origin
		var horizontal := Vector3(offset.x,0,offset.z)
		if horizontal.length() > float(data.reach) or absf(offset.y) > 1.6:
			continue
		if horizontal.length_squared() > 0.01 and horizontal.normalized().dot(forward) < 0.70:
			continue
		_sight_query.from = origin
		_sight_query.to = point
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(_sight_query)
		if not hit.is_empty() and hit.collider == unit:
			damaged[unit] = true
			unit.take_damage(float(data.damage),source_id)

func set_motion(actual_velocity: Vector3, running: bool, on_ground: bool) -> void:
	grounded = on_ground
	if Vector2(actual_velocity.x, actual_velocity.z).length_squared() <= 0.01:
		movement_mode = "STANDING"
	else:
		movement_mode = "RUNNING" if running else "WALKING"

func get_attack_interval() -> float:
	if rig.weapon == "sword":
		return float(Archer.SWORD_DATA[rig.sword_index].seconds)
	var rate := 1.0
	if movement_mode == "RUNNING":
		rate = 0.25
	elif movement_mode == "WALKING":
		rate = 0.50
	return float(Archer.BOW_DATA[rig.bow_index].attack_interval) / rate

func advance(delta: float) -> void:
	# Changing movement or equipment keeps fractional cooldown progress. A held
	# mouse never schedules a shot: only release_draw can launch an arrow.
	attack_progress = minf(1.0, attack_progress + delta / get_attack_interval())
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
	shot.emit(origin, direction, speed, clampf(charge, 0.0, 1.0))
