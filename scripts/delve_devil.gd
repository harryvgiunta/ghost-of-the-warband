extends CharacterBody3D
## Host-authoritative Cinder devil for the Sunken Delve.
##
## The run controller ticks `step` on the host with the current player list and
## peer devil list. Replicas receive `snapshot` dictionaries and glide toward the
## authoritative position, so combat state stays host-only. The visual rig is
## the shared `devil_visual.gd` presentation node.

signal died(devil)
signal struck(target, amount, position, outcome)

const Geo = preload("res://scripts/geo.gd")
const DevilVisual = preload("res://scripts/devil_visual.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const Combat = preload("res://scripts/combat.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const HeldWeapon = preload("res://scripts/held_weapon.gd")

const STATE_EMERGE := "EMERGE"
const STATE_CHASE := "CHASE"
const STATE_WINDUP := "WINDUP"
const STATE_STRIKE := "STRIKE"
const STATE_RECOVER := "RECOVER"
const STATE_STAGGER := "STAGGER"
const STATE_DEAD := "DEAD"

const MAX_HEALTH := 24.0
const EMERGE_SECONDS := 0.35
const WINDUP_SECONDS := 0.38
const STRIKE_SECONDS := 0.14
const STRIKE_HIT_TIME := 0.06
const RECOVER_SECONDS := 0.55
const STAGGER_SECONDS := 0.8
const ATTACK_RANGE := 1.9
const ATTACK_COOLDOWN_MIN := 0.9
const ATTACK_COOLDOWN_MAX := 1.3
const CHASE_SPEED := 3.4
const SEPARATION_RADIUS := 1.15
const LIMIT := 16.0
const WARNING_RADIUS := 1.6
const CORPSE_SECONDS := 2.2

var authoritative := false
var alive := true
var health := MAX_HEALTH
var max_health := MAX_HEALTH
var enemy_id := 0
var devil_weapon := "claw"
var depth := 1
var chase_speed := CHASE_SPEED
var target = null
var state := STATE_EMERGE

var _state_time := 0.0
var _attack_damage := 8.0
var _attack_reach := ATTACK_RANGE
var _attack_cooldown := 0.0
var _struck := false
var _side_bias := 1.0
var _death_handled := false
var _received_pose := false
var _net_position := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _visual: DevilVisual
var _warning: MeshInstance3D
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	name = "CinderDevil"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 0.90
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)
	_visual = DevilVisual.new()
	_visual.name = "DevilVisual"
	add_child(_visual)
	_visual.set_weapon(devil_weapon)
	# A flat emissive disc telegraphs the strike window on the floor.
	var warning_material := Geo.material(Color(0.95,0.22,0.08,0.34))
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning_material.emission_enabled = true
	warning_material.emission = Color("ff3b16")
	warning_material.emission_energy_multiplier = 2.2
	_warning = Geo.cylinder(self,WARNING_RADIUS,WARNING_RADIUS,0.02,Vector3(0,0.035,0),warning_material,40)
	_warning.visible = false
	_query.collision_mask = 1


func configure(next_id: int, weapon: String, next_depth: int) -> void:
	enemy_id = next_id
	depth = maxi(1, next_depth)
	devil_weapon = str(weapon).to_lower()
	if devil_weapon not in ["claw","dagger","sword"]:
		devil_weapon = "claw"
	match devil_weapon:
		"dagger":
			_attack_damage = 6.0
			_attack_reach = 1.9
		"sword":
			_attack_damage = 11.0
			_attack_reach = 2.1
		_:
			_attack_damage = 8.0
			_attack_reach = 1.9
	# Deeper chambers breed heavier, faster devils. Speed growth is capped so
	# they keep telegraphing instead of teleporting past the strike window.
	var step := float(depth - 1)
	max_health = MAX_HEALTH * (1.0 + 0.28 * step)
	_attack_damage *= 1.0 + 0.15 * step
	chase_speed = CHASE_SPEED * minf(1.35, 1.0 + 0.03 * step)
	if is_instance_valid(_visual):
		_visual.set_weapon(devil_weapon)
	# Per-enemy randomness: two devils in a wave never share a swing rhythm.
	_rng.seed = 4409 + maxi(enemy_id,0) * 277
	_attack_cooldown = 0.30 + _rng.randf() * 0.35
	_side_bias = 1.0 if maxi(enemy_id,0) % 2 == 0 else -1.0
	health = max_health
	alive = true
	_death_handled = false
	_struck = false
	state = STATE_EMERGE
	_state_time = 0.0
	if is_instance_valid(_warning):
		_warning.visible = false


func step(delta: float, actors: Array = [], peers: Array = []) -> void:
	if not authoritative or not alive:
		return
	_state_time += delta
	_attack_cooldown = maxf(0.0,_attack_cooldown-delta)
	# Pick the closest survivor while chasing so a swing is never redirected
	# mid-windup by a second player stepping closer.
	if state == STATE_CHASE or state == STATE_EMERGE or not _target_alive(target):
		target = _nearest_target(actors)
	var to_target := Vector3.ZERO
	var distance := INF
	if _target_alive(target):
		to_target = target.global_position-global_position
		to_target.y = 0.0
		distance = to_target.length()
	var move_intent := Vector3.ZERO
	var face_intent := Vector3.ZERO
	match state:
		STATE_EMERGE:
			if _state_time >= EMERGE_SECONDS:
				_enter(STATE_CHASE)
		STATE_CHASE:
			if distance <= ATTACK_RANGE and _attack_cooldown <= 0.0:
				_begin_windup()
			elif distance < INF:
				move_intent = _steer(_with_separation(to_target.normalized(),peers))
				face_intent = to_target.normalized()
		STATE_WINDUP:
			if distance < INF:
				face_intent = to_target.normalized()
			if _state_time >= WINDUP_SECONDS:
				_enter(STATE_STRIKE)
		STATE_STRIKE:
			if distance < INF:
				face_intent = to_target.normalized()
			if not _struck and _state_time >= STRIKE_HIT_TIME:
				_struck = true
				_strike()
			if _state_time >= STRIKE_SECONDS:
				_attack_cooldown = _rng.randf_range(ATTACK_COOLDOWN_MIN,ATTACK_COOLDOWN_MAX)
				_enter(STATE_RECOVER)
		STATE_RECOVER:
			if distance < INF:
				face_intent = to_target.normalized()
			if _state_time >= RECOVER_SECONDS:
				_enter(STATE_CHASE)
		STATE_STAGGER:
			if _state_time >= STAGGER_SECONDS:
				_enter(STATE_CHASE)
		_:
			pass
	if move_intent.length_squared() > 0.0001:
		var desired := move_intent.normalized()*chase_speed
		velocity.x = move_toward(velocity.x,desired.x,26.0*delta)
		velocity.z = move_toward(velocity.z,desired.z,26.0*delta)
	else:
		velocity.x = move_toward(velocity.x,0.0,26.0*delta)
		velocity.z = move_toward(velocity.z,0.0,26.0*delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 18.0*delta
	if face_intent.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-face_intent.x,-face_intent.z),minf(delta*10.0,1.0))
	var before := global_position
	move_and_slide()
	position.x = clampf(position.x,-LIMIT,LIMIT)
	position.z = clampf(position.z,-LIMIT,LIMIT)
	var actual := (global_position-before)/maxf(delta,0.0001)
	if is_instance_valid(_visual):
		_visual.set_motion(actual,is_on_floor())
		_visual.set_action(state,_state_time)


func take_damage(amount: float, _source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0,health-applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	BloodFx.wound(self,blood_rig(),get_aim_position(),applied,headshot,
		health <= 0.0,blood_scale())
	if health <= 0.0:
		_die(true)


func snapshot() -> Dictionary:
	return {"id":enemy_id,"pos":position,"yaw":rotation.y,"state":state,"time":_state_time,
		"health":health,"alive":alive,"weapon":devil_weapon,"depth":depth}


func apply_snapshot(snapshot_state: Dictionary) -> void:
	authoritative = false
	var had_pose := _received_pose
	var previous_health := health
	enemy_id = int(snapshot_state.get("id",enemy_id))
	var next_weapon := str(snapshot_state.get("weapon",devil_weapon))
	if next_weapon != devil_weapon:
		devil_weapon = next_weapon
		if is_instance_valid(_visual):
			_visual.set_weapon(devil_weapon)
	health = float(snapshot_state.get("health",health))
	if had_pose and previous_health-health > 0.01:
		# Replicas never apply damage; the health delta is their only hit signal.
		BloodFx.wound(self,blood_rig(),get_aim_position(),previous_health-health,
			false,health <= 0.0,blood_scale())
	state = str(snapshot_state.get("state",state))
	_state_time = float(snapshot_state.get("time",_state_time))
	if is_instance_valid(_visual):
		_visual.set_action(state,_state_time)
	var next_position: Vector3 = snapshot_state.get("pos",_net_position)
	_net_position = next_position
	if not _received_pose or position.distance_squared_to(next_position) > 36.0:
		position = next_position
	_received_pose = true
	rotation.y = float(snapshot_state.get("yaw",rotation.y))
	var next_alive := bool(snapshot_state.get("alive",alive))
	if is_instance_valid(_warning):
		_warning.visible = next_alive and state == STATE_WINDUP
	if not next_alive:
		_die(false)
	elif not _death_handled:
		alive = true


func blood_rig() -> Node3D:
	if is_instance_valid(_visual):
		var anchor := _visual.blood_anchor()
		if is_instance_valid(anchor):
			return anchor
	return self

func blood_scale() -> float:
	return 0.75

func blood_weapon_anchor(_hand: String = "") -> Node3D:
	if is_instance_valid(_visual):
		return _visual.weapon_anchor()
	return null

func get_aim_position() -> Vector3:
	return global_position + Vector3(0,0.55,0)


func head_hitbox_center() -> Vector3:
	if is_instance_valid(_visual):
		return _visual.head_hitbox_center()
	return global_position + Vector3(0,0.78,0)


func head_hit_profile() -> Vector2:
	return Vector2(Hitbox.DEVIL_HEAD_RADIUS,Hitbox.DEVIL_HEAD_HALF_HEIGHT)


func get_display_name() -> String:
	return "Cinder devil"

func held_weapon_id() -> String:
	return HeldWeapon.item_id(devil_weapon)


func _process(delta: float) -> void:
	if authoritative or not _received_pose:
		return
	var before := position
	if state != STATE_DEAD:
		position = position.lerp(_net_position,clampf(delta*12.0,0.0,1.0))
	if is_instance_valid(_visual):
		var motion := (position-before)/maxf(delta,0.0001)
		_visual.set_motion(motion,true)
		_visual.set_action(state,_state_time)


func _begin_windup() -> void:
	_struck = false
	_enter(STATE_WINDUP)
	if _target_alive(target):
		var to_target: Vector3 = target.global_position-global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			rotation.y = atan2(-to_target.x,-to_target.z)


func _enter(next_state: String) -> void:
	state = next_state
	_state_time = 0.0
	if is_instance_valid(_warning):
		_warning.visible = next_state == STATE_WINDUP


func _strike() -> void:
	if not _target_alive(target):
		return
	var to_target: Vector3 = target.global_position-global_position
	to_target.y = 0.0
	if to_target.length() > _attack_reach:
		return
	if to_target.length_squared() > 0.0001:
		var facing := -global_basis.z
		if facing.dot(to_target.normalized()) < 0.0:
			return
	_query.from = global_position + Vector3(0,0.45,0)
	_query.to = target.global_position + Vector3(0,0.6,0)
	if not get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return
	var outcome: int = Combat.DEFENSE_NONE
	if target.has_method("receive_melee"):
		outcome = target.receive_melee(_attack_damage,20+enemy_id,global_position,false)
	elif target.has_method("take_damage"):
		target.take_damage(_attack_damage,20+enemy_id)
	struck.emit(target,_attack_damage,global_position,outcome)
	if outcome == Combat.DEFENSE_NONE and target is Node3D:
		BloodFx.impact(self,(target as Node3D).get_aim_position(),to_target,
			_attack_damage,false)
		BloodFx.stain_weapon_node(blood_weapon_anchor(),_attack_damage,blood_scale())
	if outcome == Combat.DEFENSE_PARRY:
		_enter(STATE_STAGGER)


func _die(announce: bool) -> void:
	if _death_handled:
		return
	_death_handled = true
	alive = false
	state = STATE_DEAD
	_state_time = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(_warning):
		_warning.visible = false
	if is_instance_valid(_visual):
		_visual.set_weapon("claw")
		_visual.set_action(STATE_DEAD,0.0)
		_visual.die()
	if announce:
		died.emit(self)
	if is_inside_tree():
		var tween := create_tween()
		tween.tween_interval(CORPSE_SECONDS)
		tween.tween_callback(queue_free)


func _nearest_target(actors: Array):
	var nearest = null
	var best := INF
	for candidate in actors:
		if candidate == self or not _target_alive(candidate):
			continue
		var offset: Vector3 = candidate.global_position-global_position
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


func _target_alive(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_downed"):
		return not candidate.is_downed()
	var flag = candidate.get("alive")
	if flag == null:
		return true
	return bool(flag)


func _with_separation(direction: Vector3, peers: Array) -> Vector3:
	var push := Vector3.ZERO
	for other in peers:
		if other == self or not is_instance_valid(other):
			continue
		var flag = other.get("alive")
		if flag != null and not bool(flag):
			continue
		var offset: Vector3 = global_position-other.global_position
		offset.y = 0.0
		var spread := offset.length()
		if spread > 0.001 and spread < SEPARATION_RADIUS:
			push += offset/spread*(SEPARATION_RADIUS-spread)
	return direction + push*0.9


func _steer(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	var planar := Vector3(direction.x,0.0,direction.z).normalized()
	_query.from = global_position + Vector3(0,0.45,0)
	_query.to = _query.from + planar*1.4
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return planar
	# Glide around the pillar: blend along its surface normal with the desired
	# heading, using a per-enemy side bias so both devils do not pick one edge.
	var normal: Vector3 = hit.normal
	var tangent := normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()*_side_bias
	var blended := (tangent + planar*0.35).normalized()
	_query.to = _query.from + blended*1.3
	if get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return blended
	return (planar*0.35-tangent).normalized()
