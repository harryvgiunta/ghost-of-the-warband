extends CharacterBody3D

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float)

const Geo = preload("res://scripts/geo.gd")
const WolfVisual = preload("res://scripts/wolf_visual.gd")
var kind := 0
var player: CharacterBody3D
var safe_center := Vector3.ZERO
var health := 38.0
var max_health := 38.0
var alive := true
var home := Vector3.ZERO
var state := "IDLE"
var _state_time := 0.0
var _stagger_duration := 0.0
var _walk_time := 0.0
var _body: Node3D
var _wolf: WolfVisual
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _warning: MeshInstance3D
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	name = "BriarWolf" if kind == 0 else "RuinSentinel"
	home = global_position
	max_health = 38.0 if kind == 0 else 82.0
	health = max_health
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.40 if kind == 0 else 0.48
	shape.height = 0.95 if kind == 0 else 1.9
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_body = Node3D.new()
	add_child(_body)
	if kind == 0:
		_build_wolf_visual()
	else:
		_build_guardian()
	var warning_material := Geo.material(Color(0.95, 0.22, 0.08, 0.38))
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning = Geo.cylinder(self, 1.5, 1.5, 0.018, Vector3(0, 0.035, 0), warning_material, 32)
	_warning.visible = false
	_query.collision_mask = 1

func _build_wolf_visual() -> void:
	_wolf = WolfVisual.new()
	_wolf.name = "WolfVisual"
	_body.add_child(_wolf)

func _build_guardian() -> void:
	var stone := Geo.material(Color("65747a"), 0.1)
	var edge := Geo.material(Color("3e4c54"))
	var core := Geo.material(Color("d77847"), 0.2)
	core.emission_enabled = true
	core.emission = Color("c25629")
	core.emission_energy_multiplier = 1.1
	Geo.sphere(_body, 0.55, Vector3(0, 1.20, 0), stone, Vector3(1, 1.1, 0.7))
	Geo.box(_body, Vector3(0.62, 0.31, 0.42), Vector3(0, 0.78, 0), edge)
	Geo.sphere(_body, 0.28, Vector3(0, 1.92, -0.02), stone, Vector3(0.85, 1.05, 0.9))
	Geo.box(_body, Vector3(0.23, 0.06, 0.04), Vector3(0, 1.96, -0.26), core)
	Geo.sphere(_body, 0.13, Vector3(0, 1.32, -0.35), core, Vector3(1, 1.25, 0.4))
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.24, 0.81, 0)
		_body.add_child(leg)
		_legs.append(leg)
		Geo.cylinder(leg, 0.15, 0.18, 0.55, Vector3(0, -0.30, 0), stone, 6)
		Geo.box(leg, Vector3(0.33, 0.20, 0.43), Vector3(0, -0.68, -0.10), edge)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.48, 1.49, 0)
		_body.add_child(arm)
		_arms.append(arm)
		Geo.sphere(arm, 0.23, Vector3.ZERO, stone)
		Geo.cylinder(arm, 0.14, 0.17, 0.44, Vector3(0, -0.28, 0), stone, 7)
		Geo.sphere(arm, 0.22, Vector3(0, -0.60, -0.04), edge, Vector3(1, 1.2, 1))

func get_aim_position() -> Vector3:
	return global_position + Vector3(0, 0.68 if kind == 0 else 1.28, 0)

func get_display_name() -> String:
	return "Briar wolf" if kind == 0 else "Ruin sentinel"


func _physics_process(delta: float) -> void:
	if not alive or not is_instance_valid(player):
		return
	_state_time += delta
	var displacement := player.global_position - global_position
	displacement.y = 0.0
	var distance := displacement.length()
	var player_safe := Vector2(player.position.x - safe_center.x, player.position.z - safe_center.z).length() < 19.0
	var target_direction := Vector3.ZERO
	var speed := 3.1 if kind == 0 else 2.2
	if state == "STAGGER":
		if _state_time >= _stagger_duration:
			state = "IDLE"
			_state_time = 0.0
	elif state == "WINDUP":
		if _state_time >= 0.65:
			if distance < 2.1 and not player_safe and absf(player.position.y - position.y) < 1.7:
				attacked.emit(self,13.0 if kind == 0 else 23.0)
			# A parry can synchronously replace the attack with STAGGER.
			if state == "WINDUP":
				state = "RECOVER"
				_state_time = 0.0
				_warning.visible = false
	elif state == "RECOVER":
		if _state_time > 0.85:
			state = "IDLE"
	else:
		if not player_safe and distance < 23.0 and global_position.distance_to(home) < 38.0:
			state = "CHASE"
			target_direction = displacement.normalized()
			if distance < 1.65:
				state = "WINDUP"
				_state_time = 0.0
				_warning.visible = true
				target_direction = Vector3.ZERO
		else:
			state = "IDLE"
			var to_home := home - global_position
			to_home.y = 0.0
			if to_home.length() > 1.0:
				target_direction = to_home.normalized()
				speed = 2.0
	if target_direction.length_squared() > 0.1:
		target_direction = _steer(target_direction)
		rotation.y = lerp_angle(rotation.y, atan2(-target_direction.x, -target_direction.z), minf(delta * 8.0, 1.0))
	velocity.x = move_toward(velocity.x, target_direction.x * speed, delta * 12.0)
	velocity.z = move_toward(velocity.z, target_direction.z * speed, delta * 12.0)
	velocity.y = -1.0 if is_on_floor() else velocity.y - 18.0 * delta
	move_and_slide()
	if kind == 0:
		var actual_velocity := get_real_velocity()
		_wolf.set_motion(Vector2(actual_velocity.x, actual_velocity.z).length())
		_wolf.set_combat(state, _state_time)
	else:
		var moving := Vector2(velocity.x, velocity.z).length()
		_walk_time += delta * moving * 2.4
		_body.position.y = absf(sin(_walk_time * 2.0)) * 0.035 * minf(moving, 1.0)
		for index in _legs.size():
			var offset := PI if index % 2 == 0 else 0.0
			_legs[index].rotation.x = sin(_walk_time + offset) * minf(moving * 0.2, 0.48)
		for arm in _arms:
			arm.rotation.x = -0.9 * sin(clampf(_state_time / 0.65, 0, 1) * PI * 0.5) if state == "WINDUP" else 0.0

func _steer(direction: Vector3) -> Vector3:
	_query.from = global_position + Vector3(0, 0.65, 0)
	_query.to = _query.from + direction * 1.7
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return direction
	var left := direction.rotated(Vector3.UP, 1.05)
	_query.to = _query.from + left * 1.8
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return left
	return direction.rotated(Vector3.UP, -1.05)

func stagger(seconds: float) -> void:
	if not alive:
		return
	state = "STAGGER"
	_state_time = 0.0
	_stagger_duration = maxf(0.0,seconds)
	_warning.visible = false
	velocity.x = 0.0
	velocity.z = 0.0

func take_damage(amount: float, _source_id: int) -> void:
	if not alive:
		return
	health = maxf(0.0, health - amount)
	var label := Label3D.new()
	label.text = str(int(amount))
	label.font_size = 54
	label.pixel_size = 0.007
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("f4d89b")
	get_parent().add_child(label)
	label.global_position = get_aim_position() + Vector3(0, 0.7, 0)
	var text_tween := label.create_tween()
	text_tween.tween_property(label, "position:y", label.position.y + 0.9, 0.8)
	text_tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	text_tween.tween_callback(label.queue_free)
	if health <= 0.0:
		alive = false
		state = "DEAD"
		_warning.visible = false
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 0)
		defeated.emit(self, 8 if kind == 0 else 18)
		var death_tween := create_tween()
		if kind == 0:
			_wolf.die()
			# 0.45 s authored collapse + 4.0 s held corpse, then shrink only the
			# visual container; the CharacterBody root stays identity-scaled.
			death_tween.tween_interval(4.45)
			death_tween.tween_property(_body, "scale", Vector3.ONE * 0.01, 0.4)
			death_tween.tween_callback(queue_free)
		else:
			death_tween.tween_property(_body, "rotation:z", PI * 0.48, 0.45)
			death_tween.tween_interval(4.0)
			death_tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
			death_tween.tween_callback(queue_free)
