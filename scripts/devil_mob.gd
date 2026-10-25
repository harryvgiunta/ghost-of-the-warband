extends CharacterBody3D

## Authoritative frontier AI for the five imported devil mobs.
##
## The same shared state machine drives all profiles; behaviour, cadence and
## reach come from PROFILES. Presentation is entirely in DevilMobVisual, which
## samples the authored GLB clips. Damage and death stay here so the existing
## frontier combat, parry/block, damage numbers and loot paths are unchanged.

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float, victim: CharacterBody3D)

const Visual = preload("res://scripts/devil_mob_visual.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")

## Per-mob gameplay profiles. Health, damage, reach, speed and cadence are
## deliberately close to the existing Cinder devil pack so the new mobs remain
## additions, not a difficulty spike. `kind` keeps the deterministic frontier
## loot rotation distinct from kinds 0..2.
const PROFILES := {
	"hell_goat": {
		"display": "Hellish goat man", "kind": 3,
		"health": 72.0, "damage": 13.0, "reach": 2.05,
		"walk_speed": 1.50, "run_speed": 4.00, "orbit": 5.5,
		"aggro": 30.0, "leash": 50.0, "gold": 10,
		"radius": 0.45, "height": 2.00, "aim": 1.65,
		"windup": 0.45, "strike": 0.18, "recover": 0.55,
		"cooldown": 1.35, "lunge": 6.2, "turn": 9.0,
		"behaviour": "charger", "strafe": 0.9, "blood": 1.05,
	},
	"succubus": {
		"display": "Succubus", "kind": 4,
		"health": 46.0, "damage": 9.0, "reach": 1.85,
		"walk_speed": 1.40, "run_speed": 4.20, "orbit": 6.5,
		"aggro": 28.0, "leash": 44.0, "gold": 9,
		"radius": 0.32, "height": 2.05, "aim": 1.50,
		"windup": 0.36, "strike": 0.15, "recover": 0.45,
		"cooldown": 1.15, "lunge": 7.0, "turn": 10.0,
		"behaviour": "flyer", "strafe": 1.10, "blood": 0.95,
	},
	"spawn": {
		"display": "Devil spawn", "kind": 5,
		"health": 22.0, "damage": 6.0, "reach": 1.45,
		"walk_speed": 1.30, "run_speed": 4.60, "orbit": 4.0,
		"aggro": 26.0, "leash": 40.0, "gold": 5,
		"radius": 0.30, "height": 1.05, "aim": 0.75,
		"windup": 0.30, "strike": 0.14, "recover": 0.40,
		"cooldown": 0.90, "lunge": 8.0, "turn": 12.0,
		"behaviour": "crawler", "strafe": 1.50, "blood": 0.55,
	},
	"beast": {
		"display": "Hell beast", "kind": 6,
		"health": 130.0, "damage": 20.0, "reach": 2.50,
		"walk_speed": 1.40, "run_speed": 3.80, "orbit": 4.0,
		"aggro": 26.0, "leash": 40.0, "gold": 16,
		"radius": 0.55, "height": 1.65, "aim": 1.15,
		"windup": 0.65, "strike": 0.22, "recover": 0.70,
		"cooldown": 2.00, "lunge": 5.5, "turn": 5.5,
		"behaviour": "brute", "strafe": 0.2, "blood": 1.35,
	},
	"gargoyle": {
		"display": "Gargoyle", "kind": 7,
		"health": 110.0, "damage": 17.0, "reach": 3.30,
		"walk_speed": 1.00, "run_speed": 2.80, "orbit": 4.8,
		"aggro": 18.0, "leash": 28.0, "gold": 14,
		"radius": 0.70, "height": 3.05, "aim": 2.35,
		"windup": 0.75, "strike": 0.24, "recover": 0.85,
		"cooldown": 2.20, "lunge": 3.2, "turn": 4.5,
		"behaviour": "sentinel", "strafe": 0.0, "blood": 1.20,
	},
}

var mob_id := "hell_goat"
var profile: Dictionary = {}
var kind := 3
var player: CharacterBody3D
var targets: Array[CharacterBody3D] = []
var replica := false
var safe_center := Vector3.ZERO
var home := Vector3.ZERO
var health := 50.0
var max_health := 50.0
var alive := true
var state := "IDLE"

var _state_time := 0.0
var _stagger_duration := 0.0
var _attack_cooldown := 0.0
var _struck := false
var _strike_direction := Vector3.FORWARD
var _face_intent := Vector3.FORWARD
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
var _strafe_dir := 1.0
var _visual
var _body: Node3D
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()
var _target: CharacterBody3D


func _ready() -> void:
	var table := _profiles()
	if not table.has(mob_id):
		push_error("Unknown mob id: " + mob_id)
		return
	profile = (table[mob_id] as Dictionary).duplicate(true)
	name = _node_prefix() + mob_id
	kind = int(profile.kind)
	max_health = float(profile.health)
	health = max_health
	home = global_position
	if is_instance_valid(player):
		var facing := player.global_position - global_position
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			rotation.y = atan2(-facing.x, -facing.z)
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	var shape := CapsuleShape3D.new()
	shape.radius = float(profile.radius)
	shape.height = maxf(float(profile.height), shape.radius * 2.0 + 0.02)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_body = Node3D.new()
	add_child(_body)
	_visual = _visual_script().new()
	_visual.mob_id = mob_id
	_visual.profile = profile
	_body.add_child(_visual)
	add_to_group(_group_name())
	_query.collision_mask = 1
	_rng.seed = 7919 + int(absf(global_position.x) * 13.0) + int(absf(global_position.z) * 7.0)
	_strafe_dir = 1.0 if (_rng.randi() & 1) == 0 else -1.0
	_attack_cooldown = _rng.randf_range(0.25, 0.85)
	state = "IDLE"
	_state_time = 0.0


## The profile table and the identity hooks are virtual so a second mobset can
## reuse this state machine instead of forking it. The five devils keep the
## defaults; scripts/forest_mob.gd overrides them.
func _profiles() -> Dictionary:
	return PROFILES


func _group_name() -> String:
	return "devil_mobs"


func _node_prefix() -> String:
	return "Devil_"


func _visual_script():
	return Visual


func _physics_process(delta: float) -> void:
	if replica:
		return
	if not alive:
		CorpsePhysics.settle_root(self, delta)
		return
	_target = _resolve_target()
	if not is_instance_valid(_target):
		return
	_state_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector3.FORWARD
	var target_safe := Vector2(_target.position.x - safe_center.x,
		_target.position.z - safe_center.z).length() < 19.0
	var aggro := (not target_safe) and distance < float(profile.aggro) \
		and global_position.distance_to(home) < float(profile.leash)
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	_face_intent = direction
	match state:
		"IDLE":
			if aggro:
				_enter("CIRCLE")
			else:
				_return_home(delta)
		"RETURN":
			if aggro:
				_enter("CIRCLE")
			else:
				_return_home(delta)
		"CIRCLE":
			if not aggro:
				_enter("RETURN")
			else:
				_circle(delta, distance, direction)
		"WINDUP":
			_face_intent = direction
			if _state_time >= float(profile.windup):
				_strike_direction = direction
				_face_intent = direction
				_struck = false
				_enter("STRIKE")
		"STRIKE":
			_face_intent = _strike_direction
			if not _struck and _state_time >= float(profile.strike) * 0.34:
				_struck = true
				_resolve_strike()
			if _state_time >= float(profile.strike):
				_enter("RECOVER")
				_attack_cooldown = float(profile.cooldown)
		"RECOVER":
			var retreat := -direction
			var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_dir
			_move_intent = _steer((retreat + tangent * 0.65).normalized())
			_move_speed = float(profile.walk_speed) * 0.75
			_face_intent = direction
			if _state_time >= float(profile.recover):
				_enter("CIRCLE")
		"STAGGER":
			if _state_time >= _stagger_duration:
				_enter("CIRCLE")
		"DEAD":
			return
	_separate()
	_drive(delta)
	_visual.set_motion(get_real_velocity(), is_on_floor())
	_visual.set_combat(state, _state_time)


func _enter(next_state: String, reset_time := true) -> void:
	state = next_state
	if reset_time:
		_state_time = 0.0


func _return_home(delta: float) -> void:
	var offset := home - global_position
	offset.y = 0.0
	if offset.length() > 1.2:
		_move_intent = _steer(offset.normalized())
		_move_speed = float(profile.walk_speed)
		_face_intent = _move_intent
	elif state != "IDLE":
		_enter("IDLE")


func _circle(delta: float, distance: float, direction: Vector3) -> void:
	var reach := float(profile.reach)
	if distance <= reach + 1.15 and _attack_cooldown <= 0.0:
		_enter("WINDUP")
		return
	var behaviour := str(profile.behaviour)
	if behaviour == "brute" or behaviour == "sentinel":
		if distance > reach * 1.30:
			_move_intent = _steer(direction)
			_move_speed = float(profile.run_speed) if distance > reach * 2.2 else float(profile.walk_speed)
			_face_intent = _move_intent
		else:
			var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_dir
			_move_intent = _steer(tangent)
			_move_speed = float(profile.walk_speed) * 0.4
			_face_intent = direction
		return
	var orbit := float(profile.orbit)
	var closing := _attack_cooldown <= 0.0
	var radius := maxf(1.1, reach * 0.82) if closing else orbit
	var angle := atan2(global_position.z - _target.global_position.z,
		global_position.x - _target.global_position.x)
	angle += _strafe_dir * delta * float(profile.strafe) * (1.15 + 0.25 * sin(_state_time * 0.9))
	var ring := _target.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var offset := ring - global_position
	offset.y = 0.0
	var desired := offset.normalized() if offset.length_squared() > 0.0001 else direction
	if distance > orbit + 3.5:
		desired = direction
	_move_intent = _steer(desired)
	var desired_speed := float(profile.run_speed) if distance > orbit + 2.0 else float(profile.walk_speed)
	if closing:
		desired_speed = float(profile.run_speed) if distance > radius + 1.4 else float(profile.walk_speed)
	_move_speed = desired_speed
	_face_intent = direction


func _resolve_strike() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var spent := _state_time / maxf(0.01, float(profile.strike))
	var reach := float(profile.reach) * (1.0 + 0.18 * spent)
	if to_target.length() <= reach and absf(_target.global_position.y - global_position.y) < 2.4:
		attacked.emit(self, float(profile.damage), _target)

func _resolve_target() -> CharacterBody3D:
	var nearest := INF
	var best: CharacterBody3D = null
	for candidate in targets:
		if not is_instance_valid(candidate) or candidate.get("alive") == false:
			continue
		var offset := candidate.global_position - global_position
		var planar := offset.x * offset.x + offset.z * offset.z
		if planar < nearest:
			nearest = planar
			best = candidate
	return best if is_instance_valid(best) else player


func _separate() -> void:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(_group_name()):
		if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var gap := offset.length()
		if gap > 0.001 and gap < 1.35:
			push += offset / gap * (1.35 - gap)
	if push.length_squared() > 0.0001:
		if _move_intent.length_squared() > 0.0001:
			_move_intent = (_move_intent + push * 0.85).normalized()
		else:
			_move_intent = push.normalized()
			_move_speed = maxf(_move_speed, float(profile.walk_speed) * 0.35)


func _drive(delta: float) -> void:
	var desired := _move_intent * _move_speed
	if state == "STRIKE":
		var spent := clampf(_state_time / maxf(0.01, float(profile.strike)), 0.0, 1.0)
		desired = _strike_direction * float(profile.lunge) * (1.0 - 0.62 * spent)
	elif state == "WINDUP" or state == "STAGGER":
		desired = Vector3.ZERO
	var control := 26.0 if is_on_floor() else 7.0
	velocity.x = move_toward(velocity.x, desired.x, control * delta)
	velocity.z = move_toward(velocity.z, desired.z, control * delta)
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -1.0
	elif not is_on_floor():
		velocity.y -= 18.0 * delta
	if _face_intent.length_squared() > 0.0001 and state != "STAGGER":
		rotation.y = lerp_angle(rotation.y, atan2(-_face_intent.x, -_face_intent.z),
			minf(delta * float(profile.turn), 1.0))
	move_and_slide()


func _steer(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return direction
	_query.from = global_position + Vector3(0.0, float(profile.height) * 0.45, 0.0)
	_query.to = _query.from + direction.normalized() * 1.55
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return direction
	var left := direction.rotated(Vector3.UP, 1.0)
	_query.to = _query.from + left * 1.7
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return left
	return direction.rotated(Vector3.UP, -1.0)


func stagger(seconds: float) -> void:
	if not alive:
		return
	state = "STAGGER"
	_state_time = 0.0
	_stagger_duration = maxf(0.0, seconds)
	_struck = true
	velocity.x = 0.0
	velocity.z = 0.0


func take_damage(amount: float, _source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(), get_aim_position(), applied, "hit", headshot, health <= 0.0)
	BloodFx.wound(self, blood_rig(), get_aim_position(), applied, headshot,
		health <= 0.0, blood_scale())
	if health <= 0.0:
		_enter_dead(true)


## The local death: stopped combat collision, falling root, the limp ragdoll
## and the shared hold. Replicas call it with `announce = false` so gold and the
## kill stay on the host.
func _enter_dead(announce: bool) -> void:
	alive = false
	state = "DEAD"
	_struck = true
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	velocity = Vector3.ZERO
	if is_instance_valid(_visual):
		_visual.die()
	if announce:
		defeated.emit(self, int(profile.gold))
	# Hold the authored death pose for the shared five minutes, then dissolve.
	CorpseHold.hold(self, _body)


func snapshot() -> Dictionary:
	return {
		"p": global_position,
		"y": rotation.y,
		"v": velocity,
		"g": is_on_floor(),
		"s": state,
		"t": _state_time,
		"h": health,
		"a": alive,
		"x": Vector4.ZERO,
	}


## Presentation-side mirror of the host's mob: the host owns AI, damage and
## gold, so a replica only replays the snapshot it was handed.
func apply_snapshot(state: Dictionary) -> void:
	var previous_health := health
	var was_alive := alive
	global_position = state.p
	rotation.y = state.y
	self.state = state.s
	_state_time = state.t
	health = state.h
	alive = state.a
	velocity = state.v
	if is_instance_valid(_visual):
		_visual.set_motion(velocity, state.g)
		_visual.set_combat(self.state, _state_time)
	if health < previous_health:
		var applied: float = previous_health - health
		DamageNumbers.spawn(get_parent(), get_aim_position(), applied, "hit", false, health <= 0.0)
		BloodFx.wound(self, blood_rig(), get_aim_position(), applied, false,
			health <= 0.0, blood_scale())
	if was_alive and not alive:
		_enter_dead(false)


func get_aim_position() -> Vector3:
	return global_position + Vector3(0.0, float(profile.get("aim", 1.0)), 0.0)


## The imported body that the blood field measures for cloth stains.
func blood_rig() -> Node3D:
	if is_instance_valid(_visual):
		var anchor: Node3D = _visual.blood_anchor()
		if is_instance_valid(anchor):
			return anchor
	return _body


func blood_scale() -> float:
	return float(profile.get("blood", 1.0))


## These mobs fight with claws: nothing to stain, but the striking hand still
## comes away wet when the blow lands.
func blood_strike_point() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.strike_hand_position()
	return get_aim_position()


func get_display_name() -> String:
	return str(profile.get("display", mob_id))


func held_weapon_id() -> String:
	return ""


func head_hitbox_center() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.head_hitbox_center()
	return get_aim_position()


func head_hit_profile() -> Vector2:
	if is_instance_valid(_visual):
		return _visual.head_hit_profile()
	return Vector2(0.25, 0.12)


func is_dead() -> bool:
	return not alive
