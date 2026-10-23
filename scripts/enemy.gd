extends CharacterBody3D

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float)

const Geo = preload("res://scripts/geo.gd")
const WolfVisual = preload("res://scripts/wolf_visual.gd")
const DevilVisual = preload("res://scripts/devil_visual.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const DEVIL_HEALTH := 24.0
const DEVIL_AGGRO := 30.0
const DEVIL_LEASH := 48.0
const DEVIL_WINDUP := 0.34
const DEVIL_STRIKE := 0.16
const DEVIL_RECOVER := 0.38
const DEVIL_SLIDE_SECONDS := 0.46
const DEVIL_DAMAGE := 8.0
const DEVIL_LEAP_DAMAGE := 10.0
var kind := 0
var pack_index := -1
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
var _devil: DevilVisual
var _dodge
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _warning: MeshInstance3D
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()
var _orbit_angle := 0.0
var _orbit_dir := 1.0
var _orbit_radius := 4.0
var _orbit_phase := 0.0
var _decision_timer := 0.0
var _attack_cooldown := 0.0
var _leap_cooldown := 0.0
var _slide_cooldown := 0.0
var _slide_time := 0.0
var _slide_direction := Vector3.FORWARD
var _slide_speed := 0.0
var _leap_direction := Vector3.FORWARD
var _leap_air_time := 0.0
var _attack_damage := DEVIL_DAMAGE
var _struck := false
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
var _face_intent := Vector3.FORWARD

func _ready() -> void:
	name = "BriarWolf" if kind == 0 else ("CinderDevil" if kind == 2 else "RuinSentinel")
	home = global_position
	max_health = 38.0 if kind == 0 else (DEVIL_HEALTH if kind == 2 else 82.0)
	health = max_health
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	var shape := CapsuleShape3D.new()
	if kind == 0:
		shape.radius = 0.40
		shape.height = 0.95
	elif kind == 2:
		shape.radius = 0.22
		shape.height = 0.90
	else:
		shape.radius = 0.48
		shape.height = 1.9
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_body = Node3D.new()
	add_child(_body)
	if kind == 0:
		_build_wolf_visual()
	elif kind == 2:
		_build_devil_visual()
	else:
		_build_guardian()
	var warning_radius := 0.85 if kind == 2 else 1.5
	var warning_material := Geo.material(Color(0.95, 0.22, 0.08, 0.38))
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning = Geo.cylinder(self, warning_radius, warning_radius, 0.018, Vector3(0, 0.035, 0), warning_material, 32)
	_warning.visible = false
	_query.collision_mask = 1
	if kind == 2:
		add_to_group("cinder_devils")
		_dodge = DodgeStep.new()
		add_child(_dodge)
		var seeded := maxi(pack_index,0)
		_rng.seed = 7319 + seeded * 131
		_orbit_dir = 1.0 if seeded % 2 == 0 else -1.0
		_orbit_radius = 3.4 + float(seeded % 3) * 1.0
		_orbit_phase = _rng.randf() * TAU
		_attack_cooldown = 0.55 + float(seeded) * 0.32
		_decision_timer = _rng.randf_range(0.2,0.65)
		if is_instance_valid(player):
			var start := global_position - player.global_position
			start.y = 0.0
			if start.length_squared() > 0.0001:
				_orbit_angle = atan2(start.z,start.x)+float(seeded)*0.62
		state = "CIRCLE"

func _build_wolf_visual() -> void:
	_wolf = WolfVisual.new()
	_wolf.name = "WolfVisual"
	_body.add_child(_wolf)

func _build_devil_visual() -> void:
	_devil = DevilVisual.new()
	_devil.name = "DevilVisual"
	_body.add_child(_devil)

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
	return global_position + Vector3(0, 0.68 if kind == 0 else (0.55 if kind == 2 else 1.28), 0)

func get_display_name() -> String:
	return "Briar wolf" if kind == 0 else ("Cinder devil" if kind == 2 else "Ruin sentinel")

func head_hitbox_center() -> Vector3:
	if kind == 0 and is_instance_valid(_wolf):
		return _wolf.head_hitbox_center()
	if kind == 2 and is_instance_valid(_devil):
		return _devil.head_hitbox_center()
	if is_instance_valid(_body):
		return _body.to_global(Vector3(0,1.92,-0.02))
	return get_aim_position()

func head_hit_profile() -> Vector2:
	if kind == 0:
		return Vector2(Hitbox.WOLF_HEAD_RADIUS,Hitbox.WOLF_HEAD_HALF_HEIGHT)
	if kind == 2:
		return Vector2(Hitbox.DEVIL_HEAD_RADIUS,Hitbox.DEVIL_HEAD_HALF_HEIGHT)
	return Vector2(Hitbox.SENTINEL_HEAD_RADIUS,Hitbox.SENTINEL_HEAD_HALF_HEIGHT)


func _physics_process(delta: float) -> void:
	if not alive or not is_instance_valid(player):
		return
	if kind == 2:
		_step_devil(delta)
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

func _step_devil(delta: float) -> void:
	_state_time += delta
	_dodge.advance(delta,is_on_floor())
	_attack_cooldown = maxf(0.0,_attack_cooldown-delta)
	_decision_timer -= delta
	_leap_cooldown = maxf(0.0,_leap_cooldown-delta)
	_slide_cooldown = maxf(0.0,_slide_cooldown-delta)
	var to_player := player.global_position-global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var player_safe := Vector2(player.position.x-safe_center.x,player.position.z-safe_center.z).length() < 19.0
	var aggro := not player_safe and distance < DEVIL_AGGRO and global_position.distance_to(home) < DEVIL_LEASH
	if not aggro:
		if state != "RETURN":
			_enter_devil_state("RETURN")
	elif state in ["RETURN","IDLE"]:
		_enter_devil_state("CIRCLE")
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	_face_intent = Vector3.FORWARD
	match state:
		"RETURN":
			var home_offset := home-global_position
			home_offset.y = 0.0
			if home_offset.length() > 1.4:
				_move_intent = _steer_devil(home_offset.normalized())
				_move_speed = 6.0
				_face_intent = _move_intent
		"STAGGER":
			if _state_time >= _stagger_duration:
				_enter_devil_state("CIRCLE")
		"STEP":
			if distance > 0.001:
				_face_intent = to_player.normalized()
			if not _dodge.active:
				_enter_devil_state("CIRCLE")
		"SLIDE":
			_slide_time += delta
			_slide_speed = lerpf(9.4,4.0,clampf(_slide_time/DEVIL_SLIDE_SECONDS,0.0,1.0))
			_face_intent = _slide_direction
			if _slide_time >= DEVIL_SLIDE_SECONDS or not is_on_floor():
				_enter_devil_state("CIRCLE")
		"LEAP":
			_leap_air_time += delta
			_face_intent = _leap_direction
			if is_on_floor() and _leap_air_time > 0.18:
				if distance < 2.8 and _attack_cooldown <= 0.0 and _pack_attackers() < 2:
					_devil_begin_windup(DEVIL_LEAP_DAMAGE)
				else:
					_decision_timer = 0.20
					_enter_devil_state("CIRCLE")
		"DIVE":
			if distance > 0.001:
				_face_intent = to_player.normalized()
			var predicted := player.global_position+player.velocity*0.16
			var dive_offset := predicted-global_position
			dive_offset.y = 0.0
			if dive_offset.length_squared() > 0.0001:
				_move_intent = _steer_devil(_devil_with_separation(dive_offset.normalized()))
			_move_speed = 9.2
			if distance < 1.65 or _state_time >= 0.48:
				_devil_begin_windup(DEVIL_DAMAGE)
		"WINDUP":
			if distance > 0.001:
				_face_intent = to_player.normalized()
			if _state_time >= DEVIL_WINDUP:
				_enter_devil_state("STRIKE")
		"STRIKE":
			if distance > 0.001:
				_face_intent = to_player.normalized()
			if not _struck and _state_time >= 0.080:
				_struck = true
				_devil_strike(distance,to_player)
			if _state_time >= DEVIL_STRIKE:
				_attack_cooldown = 1.1+_rng.randf()*1.0
				_enter_devil_state("RECOVER")
		"RECOVER":
			if distance > 0.001:
				var retreat := -to_player.normalized()
				var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
				_move_intent = _steer_devil((retreat+tangent*0.7).normalized())
				_move_speed = 4.8
				_face_intent = _move_intent
			if _state_time >= DEVIL_RECOVER:
				_enter_devil_state("CIRCLE")
		_:
			_devil_circle(delta,distance,to_player)
	var was_grounded := is_on_floor()
	if _dodge.active:
		var step_velocity: Vector3 = _dodge.velocity()
		velocity.x = step_velocity.x
		velocity.z = step_velocity.z
	elif state == "SLIDE":
		velocity.x = _slide_direction.x*_slide_speed
		velocity.z = _slide_direction.z*_slide_speed
	elif state == "LEAP":
		velocity.x = _leap_direction.x*7.2
		velocity.z = _leap_direction.z*7.2
	else:
		var target := _move_intent*_move_speed
		var control := 32.0 if was_grounded else 9.0
		velocity.x = move_toward(velocity.x,target.x,control*delta)
		velocity.z = move_toward(velocity.z,target.z,control*delta)
	if was_grounded and velocity.y <= 0.0:
		velocity.y = -1.0
	elif not was_grounded:
		velocity.y -= 18.0*delta
	var facing := _face_intent
	if facing.length_squared() < 0.0001 or _dodge.active:
		facing = -global_basis.z
	if facing.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-facing.x,-facing.z),minf(delta*12.0,1.0))
	var before := global_position
	move_and_slide()
	var actual := (global_position-before)/maxf(delta,0.0001)
	if state == "LEAP" and not was_grounded and is_on_floor() and _leap_air_time > 0.18:
		if distance < 2.8 and _attack_cooldown <= 0.0 and _pack_attackers() < 2:
			_devil_begin_windup(DEVIL_LEAP_DAMAGE)
		else:
			_decision_timer = 0.20
			_enter_devil_state("CIRCLE")
	_devil.set_motion(actual,is_on_floor())
	_devil.set_action(state,_state_time)
	_devil.set_step(_dodge.progress if _dodge.active else -1.0,_dodge.direction)
	_devil.set_slide(_slide_time/DEVIL_SLIDE_SECONDS if state == "SLIDE" else -1.0)

func _devil_circle(delta: float, distance: float, to_player: Vector3) -> void:
	_orbit_angle += _orbit_dir*delta*(1.45+0.35*sin(_orbit_phase+_state_time*0.8))
	var predicted := player.global_position+player.velocity*0.10
	var radius := _orbit_radius+sin(_orbit_phase+_state_time*0.7)*0.55
	var ring := predicted+Vector3(cos(_orbit_angle),0.0,sin(_orbit_angle))*radius
	var offset := ring-global_position
	offset.y = 0.0
	var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
	if distance < 2.4:
		direction -= to_player.normalized()*0.8
	elif distance > 9.0:
		direction += to_player.normalized()*0.8
	_move_intent = _steer_devil(_devil_with_separation(direction))
	_move_speed = 6.4
	_face_intent = _move_intent
	if _decision_timer <= 0.0:
		_decision_timer = 0.55+_rng.randf()*0.60
		_devil_choose(distance,to_player)

func _devil_choose(distance: float, to_player: Vector3) -> void:
	if _attack_cooldown <= 0.0 and distance < 7.0 and _pack_attackers() < 2:
		_attack_damage = DEVIL_DAMAGE
		_enter_devil_state("DIVE")
		return
	if is_on_floor():
		var roll := _rng.randf()
		if _leap_cooldown <= 0.0 and roll < 0.30:
			_devil_start_leap(distance,to_player)
			return
		if roll < 0.58 and _dodge.can_step(true,false):
			_devil_start_step(to_player)
			return
		if _slide_cooldown <= 0.0 and distance > 2.3 and roll < 0.74:
			_devil_start_slide(to_player)
			return

func _devil_start_step(to_player: Vector3) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var direction := (tangent*side*0.9+to_player.normalized()*0.22).normalized()
	if _dodge.try_step(direction,is_on_floor(),false):
		_enter_devil_state("STEP")
		_face_intent = to_player.normalized()

func _devil_start_leap(distance: float, to_player: Vector3) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
	var forward := to_player.normalized()
	var direction := (forward*0.55+tangent*0.85).normalized()
	if distance > 4.5:
		direction = (forward*0.80+tangent*0.50).normalized()
	_leap_direction = _steer_devil(direction)
	_leap_air_time = 0.0
	_leap_cooldown = 1.25+_rng.randf()*0.45
	_enter_devil_state("LEAP")
	velocity.y = 6.5

func _devil_start_slide(to_player: Vector3) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
	var direction := (tangent*0.9+to_player.normalized()*0.35).normalized()
	_slide_direction = _steer_devil(direction)
	_slide_time = 0.0
	_slide_speed = 9.4
	_slide_cooldown = 1.4+_rng.randf()*0.6
	_enter_devil_state("SLIDE")

func _devil_begin_windup(damage: float) -> void:
	_attack_damage = damage
	_struck = false
	_enter_devil_state("WINDUP")
	var to_player := player.global_position-global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.0001:
		_face_intent = to_player.normalized()

func _enter_devil_state(next: String) -> void:
	state = next
	_state_time = 0.0
	_warning.visible = next == "WINDUP"

func _devil_strike(distance: float, to_player: Vector3) -> void:
	if distance > 1.8 or absf(player.global_position.y-global_position.y) > 1.25:
		return
	if to_player.length_squared() > 0.0001 and (-global_basis.z).dot(to_player.normalized()) < 0.15:
		return
	_query.from = global_position+Vector3(0,0.5,0)
	_query.to = player.global_position+Vector3(0,0.7,0)
	if not get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return
	attacked.emit(self,_attack_damage)

func _devil_with_separation(direction: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("cinder_devils"):
		if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
			continue
		var offset: Vector3 = global_position-other.global_position
		offset.y = 0.0
		var spread := offset.length()
		if spread < 1.15 and spread > 0.001:
			push += offset/spread*(1.15-spread)*1.7
	return direction+push

func _pack_attackers() -> int:
	var count := 0
	for other in get_tree().get_nodes_in_group("cinder_devils"):
		if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
			continue
		if other.global_position.distance_squared_to(global_position) > 196.0:
			continue
		if str(other.get("state")) in ["WINDUP","STRIKE","DIVE"]:
			count += 1
	return count

func _steer_devil(direction: Vector3) -> Vector3:
	_query.from = global_position+Vector3(0,0.45,0)
	_query.to = _query.from+direction*1.25
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return direction
	var left := direction.rotated(Vector3.UP,1.0)
	_query.to = _query.from+left*1.35
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return left
	return direction.rotated(Vector3.UP,-1.0)

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
	if kind == 2:
		_dodge.reset()
		_slide_time = 0.0
		_attack_cooldown = maxf(_attack_cooldown,0.45)

func take_damage(amount: float, _source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	if health <= 0.0:
		alive = false
		state = "DEAD"
		_warning.visible = false
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 0)
		defeated.emit(self, 8 if kind == 0 else (6 if kind == 2 else 18))
		var death_tween := create_tween()
		if kind == 0:
			_wolf.die()
			# 0.45 s authored collapse + 4.0 s held corpse, then shrink only the
			# visual container; the CharacterBody root stays identity-scaled.
			death_tween.tween_interval(4.45)
			death_tween.tween_property(_body, "scale", Vector3.ONE * 0.01, 0.4)
			death_tween.tween_callback(queue_free)
		elif kind == 2:
			_devil.die()
			# The devil flops in its own 0.55 s pose; hold the corpse, then shrink
			# the visual container without scaling the CharacterBody root.
			death_tween.tween_interval(4.05)
			death_tween.tween_property(_body, "scale", Vector3.ONE * 0.01, 0.35)
			death_tween.tween_callback(queue_free)
		else:
			death_tween.tween_property(_body, "rotation:z", PI * 0.48, 0.45)
			death_tween.tween_interval(4.0)
			death_tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
			death_tween.tween_callback(queue_free)
