extends CharacterBody3D
## Host-authoritative ranger clone: a crimson-black mirror of the player that
## fights with a random paperdoll kit. The body keeps the player rig and combat
## clocks, so it draws, cuts, guards and parries exactly like a ranger; the AI is
## the arena bot's range discipline plus a guard reaction and a sidestep.
##
## The frontier and the delve both own it:
## - frontier: `attack_mode = "scene"` routes melee through `attacked`, so the
##   controller resolves the live ranger's guard and damage;
## - delve: `attack_mode = "direct"` strikes the delve actor and reports the
##   outcome through `struck`, matching `delve_devil.gd`.

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float, victim: Node3D)
signal arrow_fired(origin: Vector3, direction: Vector3, speed: float, damage: float)
signal died(clone)
signal struck(target, amount: float, position: Vector3, outcome)

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const CoverMovement = preload("res://scripts/cover_movement.gd")
const Stamina = preload("res://scripts/stamina.gd")
const State = preload("res://scripts/player_state.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const MobSteering = preload("res://scripts/mob_steering.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const MobLod = preload("res://scripts/mob_lod.gd")

const MAX_HEALTH := 100.0
const GOLD := 14
const KIND := 8
const BODY_RADIUS := 0.30
const BODY_HEIGHT := 1.80
const STRIKE_PROGRESS := 0.38
## Inside this distance the clone puts the bow away and closes to blade reach,
## so a party is never kept at arm's length by a circling archer.
const BLADE_RANGE := 11.0
## The bow only fires backwards of this: closer than that the clone advances
## through its own shot lane instead of backing off.
const BOW_MIN_RANGE := 6.0

const MAIN_POOL := [
	"bow_short","bow_recurve","bow_long",
	"sword_short","sword_arming","sword_great",
	"dagger_iron","staff_fire","staff_bone",
]
const OFF_POOL := ["shield_buckler","shield_kite","shield_tower"]
const FOCUS_POOL := ["focus_tome","focus_skull"]

var kind := KIND
var clone_id := 0
var depth := 1
var authoritative := true
var replica := false
var auto_ai := true
var attack_mode := "scene"
var bounds := 143.0
var alive := true
var _impact_force := Vector3.ZERO
var health := MAX_HEALTH
var max_health := MAX_HEALTH
## Slot of the ranger whose damage landed last (see `enemy.gd.last_hitter`).
var last_hitter := -1
var stamina := Stamina.MAX
var state := "IDLE"
var targets: Array = []
var fallback_target
var home := Vector3.ZERO
var aggro_range := 30.0
var leash := 42.0
var rig
var combat
var dodge

var _main_item := "sword_short"
var _target
var _retarget := 0.0
var _guard_hold := 0.0
var _guard_cooldown := 0.0
var _step_cooldown := 0.0
var _attack_cooldown := 0.0
var _state_time := 0.0
var _swing_pending := false
var _swing_count := 0
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
var _net_position := Vector3.ZERO
var _received_pose := false
## Buffered server states for the replica's delayed render (see `enemy.gd`).
var _timeline = NetReplication.mob_timeline()
var _death_handled := false
var _body: Node3D
var _collider: CollisionShape3D
var _shape: CapsuleShape3D
var _query := PhysicsRayQueryParameters3D.new()
var _floor_query := PhysicsRayQueryParameters3D.new()
var _steering := MobSteering.new()
## The cry the pack raised or the blow that named its striker. The clone hunts
## those bodies past its aggro range and leash until the clocks run out.
var _senses := MobSenses.new()
## The stretch of trail this clone patrols when nothing is in sight.
var _wander := MobWander.new()
## Tick budget: the further from the nearest ranger, the rarer the tick.
var _lod := MobLod.new()
## Presentation band last applied (0 shadowed, 1 animate-only, 2 resting).
var _present_band := -1
## Parked by `MobCuller`: no tick, no draw, no state change while it is true.
var dormant := false
## Whether this clone has already called the pack to the fight.
var _woke := false


func _ready() -> void:
	name = "RangerClone"
	collision_layer = 2
	collision_mask = 1
	# One slide per move: the clone steers its own lane.
	max_slides = 2
	# A body on a slope must keep its horizontal motion: the default stop
	# cancels it the moment the ground tilts, which read as crawling.
	floor_stop_on_slope = false
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	_shape = CapsuleShape3D.new()
	_shape.radius = BODY_RADIUS
	_shape.height = BODY_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	_collider.position.y = BODY_HEIGHT * 0.5
	add_child(_collider)
	_body = Node3D.new()
	_body.name = "CloneBody"
	add_child(_body)
	rig = Archer.new()
	rig.name = "RangerRig"
	_body.add_child(rig)
	rig.set_ground_sampler(_floor_height)
	combat = Combat.new()
	add_child(combat)
	combat.setup(rig, global_position + Vector3(0,1.2,0))
	combat.actor = self
	# The clone's damage is resolved by its owner scene, never by the shared
	# sweep: the frontier player body is not a Combat actor.
	combat.damage_enabled = false
	combat.target_mask = 0
	combat.shot.connect(_on_bow_released)
	var cover := CoverMovement.new()
	add_child(cover)
	cover.setup(self,_collider)
	combat.cover = cover
	dodge = DodgeStep.new()
	add_child(dodge)
	_query.collision_mask = 1
	_floor_query.collision_mask = 1
	# Clones answer and raise the same pack alarm as every other wilderness
	# body, so a woken wave fights together.
	add_to_group(MobSenses.GROUP)


## `mode` is `"scene"` for the frontier and `"direct"` for the delve.
func configure(id: int, next_depth: int, is_authoritative: bool, mode: String = "scene") -> void:
	clone_id = maxi(0,id)
	depth = maxi(1,next_depth)
	authoritative = is_authoritative
	replica = not is_authoritative
	attack_mode = mode
	auto_ai = mode == "scene"
	_steering.bias = 1.0 if clone_id % 2 == 0 else -1.0
	_lod = MobLod.new(clone_id * 3)
	aggro_range = 40.0 if mode == "direct" else 30.0
	leash = 60.0 if mode == "direct" else 42.0
	_roll_loadout()
	max_health = MAX_HEALTH * (1.0 + 0.15 * float(depth - 1))
	health = max_health
	stamina = Stamina.MAX
	alive = true
	state = "IDLE"
	_state_time = 0.0
	_death_handled = false
	_impact_force = Vector3.ZERO
	_swing_pending = false
	_swing_count = 0
	_target = null
	_retarget = 0.0
	combat.source_id = 400 + clone_id
	combat.damage_enabled = false
	combat.target_mask = 0
	combat.stop()
	combat.attack_progress = 1.0
	rig.set_hit_react(0.0)
	rig.set_roll(-1.0,Vector3.FORWARD)
	rig.set_step(-1.0,Vector3.FORWARD)
	rig.set_slide(-1.0,Vector3.FORWARD)
	rig.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	_net_position = global_position
	_received_pose = false
	_steering.reset()
	_senses.clear()
	_wander.reset()
	_woke = false
	_body.rotation = Vector3.ZERO
	_body.position = Vector3.ZERO
	_body.visible = true


func spawn_at(point: Vector3, facing: Vector3 = Vector3.ZERO) -> void:
	global_position = point
	home = point
	_net_position = point
	_received_pose = true
	velocity = Vector3.ZERO
	alive = true
	health = max_health
	stamina = Stamina.MAX
	_death_handled = false
	_impact_force = Vector3.ZERO
	_swing_pending = false
	state = "IDLE"
	_state_time = 0.0
	collision_layer = 2
	collision_mask = 1
	_target = null
	_steering.reset()
	_senses.clear()
	_wander.reset()
	_woke = false
	var flat := Vector3(facing.x,0.0,facing.z)
	if flat.length_squared() > 0.0001:
		rotation.y = atan2(-flat.x,-flat.z)


func get_display_name() -> String:
	return "Ranger clone"


func role() -> String:
	return "ranger"


func get_aim_position() -> Vector3:
	return global_position + Vector3(0,1.2,0)


func head_hitbox_center() -> Vector3:
	return rig.head_hitbox_center() if is_instance_valid(rig) else get_aim_position()


func head_hit_profile() -> Vector2:
	return rig.head_hit_profile() if is_instance_valid(rig) else Vector2(0.16,0.12)


func blood_rig() -> Node3D:
	return _body if is_instance_valid(_body) else self


func blood_scale() -> float:
	return 1.0


func blood_strike_point() -> Vector3:
	if is_instance_valid(rig):
		return rig.global_position + Vector3(0,1.25,0) - rig.global_basis.z * 0.45
	return get_aim_position()


func blood_weapon_anchor(_hand: String = "") -> Node3D:
	if is_instance_valid(rig) and rig.has_method("active_weapon_node"):
		return rig.active_weapon_node()
	return null


## The catalog id the clone would leave behind: its main-hand piece.
func held_weapon_id() -> String:
	return _main_item


## A patrol is one ranger, not a band: two clones never share a patch.
func wanders_packed() -> bool:
	return false


## How far the patrol strays from the spot it was posted to.
func wander_radius() -> float:
	return 15.0


func pack_family() -> String:
	return "ranger"


## Distance to the closest ranger, for the tick budget.
func _nearest_ranger() -> float:
	var best := INF
	if is_instance_valid(fallback_target):
		best = global_position.distance_squared_to(fallback_target.global_position)
	for candidate in targets:
		if is_instance_valid(candidate):
			best = minf(best, global_position.distance_squared_to(candidate.global_position))
	if best == INF:
		return INF
	return sqrt(best)


## Far clones stop sampling the player rig; it keeps its last pose.
func _cull_presentation(nearest: float) -> void:
	var band := MobLod.band(nearest)
	if band == _present_band:
		return
	_present_band = band
	if not is_instance_valid(rig):
		return
	# The rig is the heaviest body in the world: stop sampling it and stop its
	# shadow pass at range instead of hiding it, which would pop.
	rig.set_physics_process(band < 2)
	rig.set_process(band < 2)
	if rig.has_method("set_shadow_casting"):
		rig.set_shadow_casting(band == 0)


## The culler's only call into a parked body: one distance check per sweep.
## The pursuit, the bow ladder, the rig sampling and the swept move are all
## behind the physics process `mob_sleep` turns off.
func mob_lod_sweep() -> void:
	if not alive:
		return
	var nearest := _nearest_ranger()
	if not MobLod.dormant(nearest, dormant):
		if dormant:
			mob_wake()
		return
	if dormant:
		return
	if replica or _may_sleep():
		mob_sleep()


## Only a calm body with its feet down may park. A clone that is hunting has to
## keep running, and one parked mid-air would hang there. A replica runs no AI
## at all, so it parks on distance alone.
func _may_sleep() -> bool:
	return not _senses.aggressive() and is_on_floor()


## Parked: the clone keeps its loadout, health, patrol and corpse, and loses its
## physics process and its draw call. Nothing outside `MobSenses` can see it
## from here, and the frontier's fog is opaque well before it.
func mob_sleep() -> void:
	if dormant:
		return
	dormant = true
	if not replica:
		# Nothing banked from before the sleep; the first frame back is granted.
		_lod.resume()
		set_physics_process(false)
	visible = false


func mob_wake() -> void:
	if not dormant:
		return
	dormant = false
	_lod.resume()
	set_physics_process(true)
	visible = true
	# Re-apply the presentation band for the distance it woke at.
	_present_band = -1


func assign_territory(shared, ring_slot: int, pack_group: String) -> void:
	_wander.assign(shared, ring_slot, pack_group)


func _roll_loadout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + clone_id * 7919 + depth * 131
	_main_item = str(MAIN_POOL[rng.randi_range(0,MAIN_POOL.size() - 1)])
	var off := ""
	if _main_item in ["sword_short","sword_arming","dagger_iron"]:
		var roll := rng.randf()
		if roll < 0.35:
			off = str(OFF_POOL[rng.randi_range(0,OFF_POOL.size() - 1)])
		elif roll < 0.45:
			off = str(FOCUS_POOL[rng.randi_range(0,FOCUS_POOL.size() - 1)])
	var pieces := {}
	for slot in ["head","chest","hands","legs","feet"]:
		pieces[slot] = rng.randi_range(0,3)
	rig.apply_loadout(State.build_loadout(_main_item,off,pieces))
	_tint_rig()


## Heavy crimson-black: every mesh under the rig gets its own duplicated
## material, so one clone never recolours another ranger or another clone.
func _tint_rig() -> void:
	var red := 0.30 + 0.05 * float(clone_id % 3)
	var black := 0.015 + 0.008 * float(clone_id % 2)
	for node in rig.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var tuned := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				tuned.albedo_color = Color(red,black,black,1.0)
				tuned.emission_enabled = true
				tuned.emission = Color(0.55,0.02,0.02)
				tuned.emission_energy_multiplier = 0.35
				mesh.set_surface_override_material(surface,tuned)


func _physics_process(delta: float) -> void:
	if dormant:
		return
	if not alive:
		if authoritative and not replica:
			CorpsePhysics.settle_root(self, delta)
		return
	if replica or not authoritative or not auto_ai:
		return
	var nearest := _nearest_ranger()
	_cull_presentation(nearest)
	var budget := _lod.slice(nearest, delta, not _senses.aggressive())
	if budget <= 0.0:
		return
	delta = budget
	dodge.advance(delta,is_on_floor())
	_step_ai(delta,targets)


## The delve drives wave members through this entry point.
func step(delta: float, actors: Array = [], _peers: Array = []) -> void:
	if not authoritative or replica or not alive:
		return
	dodge.advance(delta,is_on_floor())
	_step_ai(delta,actors)


func _step_ai(delta: float, candidates: Array) -> void:
	_state_time += delta
	_attack_cooldown = maxf(0.0,_attack_cooldown - delta)
	_guard_cooldown = maxf(0.0,_guard_cooldown - delta)
	_step_cooldown = maxf(0.0,_step_cooldown - delta)
	_retarget -= delta
	_senses.age(delta)
	stamina = minf(Stamina.MAX,stamina + Stamina.REGEN_PER_SECOND * delta)
	combat.advance(delta)
	if _swing_pending and combat.attack_progress >= STRIKE_PROGRESS:
		_swing_pending = false
		_resolve_melee()
	var roster: Array = candidates
	if roster.is_empty() and is_instance_valid(fallback_target):
		roster = [fallback_target]
	if _retarget <= 0.0 or not _engaged(_target):
		_target = _nearest(roster)
		_retarget = 0.35
	if _engaged(_target):
		if not _woke:
			_woke = true
			MobSenses.alert_pack(self,_target,_target.global_position)
			MobSenses.alert_packmates(self,_target,_target.global_position,_wander.group)
	else:
		_woke = false
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	if not _engaged(_target):
		_target = null
		if combat.blocking:
			combat.stop_block()
		# A calm clone walks its patrol: the trail it was posted to, not a
		# statue on one spot.
		var outside: bool = _wander.outside(self)
		var patrol: Vector3 = _wander.step(self)
		state = "RETURN" if outside else "IDLE"
		if patrol.length_squared() > 0.0001:
			_move_intent = _steer(patrol)
			_move_speed = 4.2 if outside else 2.6
			_apply_motion(delta,_move_intent)
		else:
			_apply_motion(delta,Vector3.ZERO)
		return
	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector3.FORWARD
	combat.set_aim(_aim_point(_target,distance))
	combat.face_block(direction)
	var threat: bool = _target_attacking(_target) and distance <= float(rig.melee_reach("right")) + 0.9
	if combat.blocking:
		_guard_hold -= delta
		if _guard_hold <= 0.0 and not threat:
			combat.stop_block()
	elif threat and _guard_cooldown <= 0.0 and combat.attack_progress >= 0.999:
		if combat.start_block(direction):
			_guard_hold = 0.30
			_guard_cooldown = 0.9
	if threat and not combat.blocking and _step_cooldown <= 0.0 and dodge.can_step(is_on_floor(),false):
		var tangent := Vector3(-direction.z,0.0,direction.x)
		if clone_id % 2 != 0:
			tangent = -tangent
		if dodge.try_step(tangent,is_on_floor(),false):
			_step_cooldown = 1.6
	var want_bow := distance > BLADE_RANGE
	if combat.attack_progress >= 0.999 and not combat.blocking:
		if want_bow and rig.weapon != "bow":
			rig.set_weapon("bow")
		elif not want_bow and rig.weapon == "bow":
			rig.set_weapon("sword")
	if rig.weapon == "bow":
		state = "SHOOT" if rig.draw_amount > 0.0 else "CIRCLE"
		_bow_step(distance,direction)
	else:
		state = "STRIKE" if _swing_pending else "CIRCLE"
		_blade_step(distance,direction)
	_apply_motion(delta,direction)


func _apply_motion(delta: float, facing_direction: Vector3) -> void:
	var desired := _move_intent * _move_speed
	if dodge.active:
		var step_velocity: Vector3 = dodge.velocity()
		velocity.x = step_velocity.x
		velocity.z = step_velocity.z
	else:
		var control := 26.0 if is_on_floor() else 8.0
		velocity.x = move_toward(velocity.x,desired.x,control * delta)
		velocity.z = move_toward(velocity.z,desired.z,control * delta)
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= 18.0 * delta
	if facing_direction.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-facing_direction.x,-facing_direction.z),minf(delta * 10.0,1.0))
	var before := global_position
	MobLod.move(self, delta)
	position.x = clampf(position.x,-bounds,bounds)
	position.z = clampf(position.z,-bounds,bounds)
	var actual := (global_position - before) / maxf(delta,0.0001)
	_present(actual)


func _present(actual: Vector3) -> void:
	rig.set_step(dodge.progress if dodge.active else -1.0,dodge.direction)
	rig.set_roll(-1.0,Vector3.FORWARD)
	rig.set_slide(-1.0,Vector3.FORWARD)
	rig.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	rig.set_locomotion(actual,is_on_floor())
	combat.set_motion(actual,actual.length() > 0.4,is_on_floor())


## The bow is a walking weapon here: the clone closes the gap between shots
## instead of orbiting at range, and only plants its feet while the string is
## drawn. A ranger who holds a corridor cannot be circled forever.
func _bow_step(distance: float, direction: Vector3) -> void:
	if distance < BOW_MIN_RANGE:
		_move_intent = -direction
		_move_speed = 5.4
	elif rig.draw_amount > 0.0 or rig.phase in ["DRAWING","HOLDING"]:
		var tangent := Vector3(-direction.z,0.0,direction.x) * 0.35
		if clone_id % 2 != 0:
			tangent = -tangent
		_move_intent = _steer(tangent)
		_move_speed = 1.4
	else:
		_move_intent = _steer(direction)
		_move_speed = 4.6
	if combat.can_draw() and _has_sight(_target):
		combat.begin_draw()
	elif rig.draw_amount >= 0.92 and rig.phase in ["DRAWING","HOLDING"]:
		combat.release_draw()


func _blade_step(distance: float, direction: Vector3) -> void:
	var reach: float = rig.melee_reach("right")
	if distance > reach * 0.80:
		_move_intent = _steer(direction)
		_move_speed = 5.8
	else:
		var tangent := Vector3(-direction.z,0.0,direction.x) * 0.55
		if clone_id % 2 != 0:
			tangent = -tangent
		_move_intent = tangent
		_move_speed = 2.6
		if _attack_cooldown <= 0.0 and combat.attack_progress >= 0.999 and not combat.blocking \
				and _has_sight(_target):
			var swing := "diagonal_right" if (clone_id + _swing_count) % 2 == 0 else "diagonal_left"
			if combat.begin_melee("right",swing):
				_swing_count += 1
				_swing_pending = true
				_attack_cooldown = 0.85


func _resolve_melee() -> void:
	if not _target_alive(_target):
		return
	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > rig.melee_reach("right") + 0.45:
		return
	if to_target.length_squared() > 0.0001 and (-global_basis.z).dot(to_target.normalized()) < 0.15:
		return
	var damage := _melee_damage()
	if damage <= 0.0:
		return
	if attack_mode == "scene":
		attacked.emit(self,damage,_target)
		return
	var outcome := Combat.DEFENSE_NONE
	if _target.has_method("receive_melee"):
		outcome = int(_target.receive_melee(damage,combat.source_id,global_position,false))
	elif _target.has_method("take_damage"):
		_target.take_damage(damage,combat.source_id)
	if outcome == Combat.DEFENSE_PARRY:
		stagger(Combat.PARRY_STAGGER)
	struck.emit(_target,damage,global_position,outcome)


func _melee_damage() -> float:
	if rig.weapon == "dagger":
		return float(Archer.dagger_profile(0).damage)
	if rig.weapon == "bow":
		return 0.0
	return float(Archer.SWORD_DATA[clampi(rig.sword_index,0,2)].damage)


func _on_bow_released(origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	if not authoritative or not alive:
		return
	if not direction.is_finite() or direction.length_squared() < 0.01:
		return
	var damage := Combat.damage_for(rig.bow_index,charge)
	var arrow := Arrow.new()
	arrow.source_id = combat.source_id
	arrow.shooter = self
	# Layer 8 is the shield: a raised or carried shield takes the shaft first.
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = true
	get_parent().add_child(arrow)
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(rig.active_shield):
		excluded.append(rig.active_shield.get_rid())
	arrow.launch(origin,direction.normalized(),speed,damage,excluded)
	arrow_fired.emit(origin,direction,speed,damage)


func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false, _react: bool = true) -> void:
	if not alive or replica:
		return
	# Being hit is not something a parked body can miss: it wakes and turns.
	mob_wake()
	last_hitter = source_id
	var applied: float = amount * Hitbox.damage_multiplier(headshot) * (1.0 - rig.damage_reduction(headshot))
	health = maxf(0.0,health - applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	BloodFx.wound(self,blood_rig(),get_aim_position(),applied,headshot,health <= 0.0,blood_scale())
	if health <= 0.0:
		_die(true)


## Swords, daggers and staves meet the clone's guard here; arrows use take_damage.
func receive_melee(amount: float, source_id: int, attacker_position: Vector3, headshot: bool = false) -> int:
	if not alive or replica:
		return Combat.DEFENSE_NONE
	mob_wake()
	var outcome: int = combat.resolve_melee_defense(attacker_position)
	if outcome == Combat.DEFENSE_PARRY:
		return outcome
	if outcome == Combat.DEFENSE_BLOCK or outcome == Combat.DEFENSE_WEAK_BLOCK:
		stamina = maxf(0.0,stamina - combat.block_stamina_cost())
		var push := global_position - attacker_position
		push.y = 0.0
		if push.length_squared() > 0.000001:
			push = push.normalized() * Combat.BLOCK_PUSH_SPEED
			velocity.x = push.x
			velocity.z = push.z
		if outcome == Combat.DEFENSE_WEAK_BLOCK:
			take_damage(amount * Combat.WEAK_BLOCK_DAMAGE_SCALE,source_id,headshot,false)
		return outcome
	take_damage(amount,source_id,headshot)
	return Combat.DEFENSE_NONE


func stagger(seconds: float) -> void:
	if not alive:
		return
	mob_wake()
	combat.stagger(seconds)
	rig.set_hit_react(seconds)
	dodge.reset()
	velocity.x = 0.0
	velocity.z = 0.0


func snapshot() -> Dictionary:
	var rig_state: Array = rig.pack_animation_state(rig.get_animation_state()) if is_instance_valid(rig) else []
	if attack_mode == "direct":
		return {"kind":KIND,"id":clone_id,"role":"ranger","pos":global_position,"yaw":rotation.y,
			"state":state,"time":_state_time,"health":health,"alive":alive,
			"weapon":str(rig.weapon),"depth":depth,"max_health":max_health,"anim":rig_state}
	return {"kind":KIND,"id":clone_id,"max_health":max_health,"weapon":str(rig.weapon),
		"p":global_position,"y":rotation.y,"v":velocity,"g":is_on_floor(),
		"s":state,"t":_state_time,"h":health,"a":alive,"x":Vector4(-1,0,0,-1),
		"anim":rig_state}


func apply_snapshot(snapshot_state: Dictionary, tick: int = -1) -> void:
	authoritative = false
	replica = true
	auto_ai = false
	var had_pose := _received_pose
	var previous_health := health
	clone_id = int(snapshot_state.get("id",clone_id))
	var next_position: Vector3 = snapshot_state.get("pos",snapshot_state.get("p",_net_position))
	_net_position = next_position
	var next_velocity: Vector3 = snapshot_state.get("v",velocity)
	var yaw := float(snapshot_state.get("yaw",snapshot_state.get("y",rotation.y)))
	var at := tick if tick >= 0 else _timeline.newest_tick() + 1
	var now := Time.get_ticks_msec()/1000.0
	if not had_pose:
		_timeline.reset_to(next_position,next_velocity,yaw,at,now)
		position = next_position
		rotation.y = yaw
		_received_pose = true
	else:
		_timeline.push(at,next_position,next_velocity,yaw,now)
		rotation.y = _timeline.sample().yaw
	velocity = snapshot_state.get("v",velocity)
	max_health = float(snapshot_state.get("max_health",max_health))
	health = float(snapshot_state.get("health",snapshot_state.get("h",health)))
	alive = bool(snapshot_state.get("alive",snapshot_state.get("a",alive)))
	state = str(snapshot_state.get("state",snapshot_state.get("s",state)))
	_state_time = float(snapshot_state.get("time",snapshot_state.get("t",_state_time)))
	var weapon := str(snapshot_state.get("weapon",""))
	if weapon in ["bow","sword","dagger"] and str(rig.weapon) != weapon:
		rig.set_weapon(weapon)
	if snapshot_state.has("anim") and typeof(snapshot_state.anim) in [TYPE_DICTIONARY,TYPE_ARRAY]:
		rig.apply_animation_state(snapshot_state.anim)
	if had_pose and previous_health - health > 0.01:
		BloodFx.wound(self,blood_rig(),get_aim_position(),previous_health - health,
			false,health <= 0.0,blood_scale())
	if not alive and not _death_handled:
		_die(false)
	elif alive and _death_handled:
		alive = true


func _process(delta: float) -> void:
	if not replica or not alive or not _received_pose:
		return
	var before := position
	_timeline.advance(delta)
	var sample: Dictionary = _timeline.sample()
	position = sample.pos
	if is_instance_valid(rig):
		rig.set_locomotion((position - before)/maxf(delta,0.0001),true)


func _die(announce: bool) -> void:
	if _death_handled:
		return
	_death_handled = true
	alive = false
	state = "DEAD"
	var fall_dir := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 1
	combat.stop()
	dodge.reset()
	if is_instance_valid(rig):
		rig.set_step(-1.0,Vector3.FORWARD)
		rig.set_hit_react(0.0)
		# Stop the Archer's physics-clock animation and hide its loose props
		# before its skeleton is handed to the ragdoll; snapshots only mirror
		# state on dead replicas.
		rig.enter_corpse_pose()
	var limp = CorpsePhysics.start_limp(_body, fall_dir) if is_instance_valid(_body) else null
	var fall: Tween
	if limp != null:
		fall = create_tween()
		fall.tween_interval(0.5)
		CorpseHold.append(fall,self,_body)
	elif is_instance_valid(_body):
		fall = create_tween()
		fall.tween_property(_body,"rotation:z",PI * 0.47,0.5)
		CorpseHold.append(fall,self,_body)
	if announce:
		defeated.emit(self,GOLD)
		died.emit(self)


func _nearest(candidates: Array):
	var nearest = null
	var best := INF
	for candidate in candidates:
		if candidate == self or not _target_alive(candidate) or not _within_aggro(candidate):
			continue
		var offset: Vector3 = candidate.global_position - global_position
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


func _within_aggro(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	# A landed blow is a fight the clone cannot lose by distance: it walks the
	# whole way to whoever hit it, past the aggro range and past its leash.
	if _senses.aggressive() and candidate == _senses.target:
		return true
	if global_position.distance_to(candidate.global_position) > aggro_range:
		return false
	return global_position.distance_to(home) <= leash


func _engaged(candidate) -> bool:
	return _target_alive(candidate) and _within_aggro(candidate)


func _target_alive(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_downed"):
		return not candidate.is_downed()
	var flag = candidate.get("alive")
	if flag == null:
		return true
	return bool(flag)


func _target_attacking(candidate) -> bool:
	var unit = candidate
	if is_instance_valid(candidate) and candidate.has_meta("ironwood_damage_target"):
		unit = candidate.get_meta("ironwood_damage_target")
	if not is_instance_valid(unit):
		return false
	var other = unit.get("combat")
	if other == null:
		return false
	var progress = other.get("attack_progress")
	if progress == null:
		return false
	return float(progress) < 0.999


func _aim_point(candidate, distance: float) -> Vector3:
	var point: Vector3 = candidate.global_position + Vector3(0,1.0,0)
	var speed := float(Archer.BOW_DATA[rig.bow_index].speed)
	var travel := distance / maxf(speed,1.0)
	var target_velocity = candidate.get("velocity")
	if typeof(target_velocity) == TYPE_VECTOR3:
		point += target_velocity * travel * 0.55
	return point


func _has_sight(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	_query.from = global_position + Vector3(0,1.35,0)
	_query.to = candidate.global_position + Vector3(0,1.1,0)
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()


func _steer(direction: Vector3) -> Vector3:
	return _steering.steer(self,direction,0.9)


## A landed blow names its striker before it applies damage. The clone takes up
## the fight wherever the ranger runs to, exactly like every wilderness mob.
func note_attacker(attacker: Node3D) -> void:
	if not alive or replica or not is_instance_valid(attacker):
		return
	_senses.notice(attacker,attacker.global_position)
	_target = attacker
	_retarget = 0.0
	_woke = true
	MobSenses.alert_pack(self,attacker,attacker.global_position)


## A neighbour woke or was struck within earshot: take up the same hunt.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	if not alive or replica:
		return
	mob_wake()
	if is_instance_valid(attacker) and attacker is CharacterBody3D:
		_target = attacker
		_senses.hear(attacker, at)
		if _target_alive(_target):
			_woke = true


func _floor_height(point: Vector3) -> float:
	_floor_query.from = point + Vector3(0,1.2,0)
	_floor_query.to = point - Vector3(0,2.6,0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return float(hit.position.y) if not hit.is_empty() else global_position.y
