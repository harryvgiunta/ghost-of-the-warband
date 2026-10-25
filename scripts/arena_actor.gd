extends CharacterBody3D

signal fired(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float)
signal thrown_weapon(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float, weapon: String, weapon_index: int)
signal killed(slot: int, source: int)

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const Geo = preload("res://scripts/geo.gd")
const DodgeRoll = preload("res://scripts/dodge_roll.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const RunningSlide = preload("res://scripts/running_slide.gd")
const CoverMovement = preload("res://scripts/cover_movement.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityRunner = preload("res://scripts/ability_runner.gd")
const Stamina = preload("res://scripts/stamina.gd")
const MAX_HEALTH := 100.0
const WALK_SPEED := 5.5
var slot := 0
var peer_id := 0
var is_bot := true
var display_name := "Bot"
var rig
var combat
var ability
var roll
var dodge
var slide
var cover
var bounds := 31.5
var interp_delay := 0.12
var peek_requested := false
var peek_view_right := Vector3.RIGHT
var peek_shoulder := 1
var aim_snapshot_tick := -1
var _exposure_tick := -1
var health := MAX_HEALTH
var weapon_blood := 0.0
var alive := true
var kills := 0
var deaths := 0
var respawn := 0.0
var authoritative := false
var is_local := false
var spawn_point := Vector3.ZERO
var move_direction := Vector2.ZERO
var run_requested := false
var jump_requested := false
var stamina := Stamina.MAX
var _exhausted := false
var consume_kind := ""
var _consume_elapsed := 0.0
var _heal_remaining := 0.0
var _heal_rate := 0.0
var input_age := 0.0
var _label: Label3D
var _ground_ring: MeshInstance3D
var _target_position := Vector3.ZERO
var _received_pose := false
var _states: Array[Dictionary] = []
var _gear_bits := -1
const INTERP_BUFFER_LIMIT := 32
const INTERP_HISTORY := 0.9
const INTERP_EXTRAPOLATION := 0.15
var _floor_query := PhysicsRayQueryParameters3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	set_meta("ironwood_player", true)
	collision_layer = 4
	# Fighters do not hard-collide with each other. A gentle authoritative
	# separation keeps bodies from stacking while allowing a close measure.
	collision_mask = 1
	floor_snap_length = 0.5
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.position.y = 0.9
	collider.shape = capsule
	add_child(collider)
	cover = CoverMovement.new()
	add_child(cover)
	cover.setup(self,collider)
	rig = Archer.new()
	add_child(rig)
	_floor_query.collision_mask = 1
	_sight_query.collision_mask = 1
	rig.set_ground_sampler(_floor_height)
	combat = Combat.new()
	add_child(combat)
	combat.setup(rig,position + Vector3(0,1.2,-20))
	combat.shot.connect(func(origin: Vector3,direction: Vector3,speed: float,charge: float):
		if authoritative and alive:
			fired.emit(slot,origin,direction,speed,charge))
	combat.thrown.connect(func(origin: Vector3,direction: Vector3,speed: float,charge: float,weapon_name: String,weapon_index: int):
		if authoritative and alive:
			thrown_weapon.emit(slot,origin,direction,speed,charge,weapon_name,weapon_index))
	combat.actor = self
	combat.cover = cover
	combat.target_mask = 4
	combat.source_id = slot
	combat.damage_enabled = false
	ability = AbilityRunner.new()
	add_child(ability)
	ability.setup(self,rig,combat,WALK_SPEED)
	roll = DodgeRoll.new()
	add_child(roll)
	dodge = DodgeStep.new()
	add_child(dodge)
	slide = RunningSlide.new()
	add_child(slide)
	_label = Label3D.new()
	_label.position.y = 2.3
	_label.font_size = 36
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)
	var colors := [Color("70c4cb"),Color("e4a75f"),Color("bfa1dc"),Color("86c48a")]
	_label.modulate = colors[slot]
	var circle := TorusMesh.new()
	circle.inner_radius = 0.38
	circle.outer_radius = 0.43
	circle.rings = 24
	circle.ring_segments = 6
	_ground_ring = Geo.mesh_node(self,circle,Geo.material(colors[slot]),Vector3(0,0.025,0))

func configure(owner_id: int, bot: bool, player_name: String, spawn: Vector3) -> void:
	peer_id = owner_id
	is_bot = bot
	display_name = player_name
	spawn_point = spawn
	combat.damage_enabled = authoritative
	kills = 0
	deaths = 0
	revive()

func revive() -> void:
	position = spawn_point + Vector3(0,0.08,0)
	_target_position = position
	_received_pose = false
	_states.clear()
	velocity = Vector3.ZERO
	move_direction = Vector2.ZERO
	run_requested = false
	jump_requested = false
	input_age = 0.0
	reset_stance()
	health = MAX_HEALTH
	weapon_blood = 0.0
	stamina = Stamina.MAX
	_exhausted = false
	ability.reset()
	consume_kind = ""
	_consume_elapsed = 0.0
	_heal_remaining = 0.0
	_heal_rate = 0.0
	alive = true
	respawn = 0.0
	combat.stop()
	combat.clear_camera_ray()
	roll.reset()
	dodge.reset()
	rig.set_hit_react(0.0)
	rig.set_step(-1.0,Vector3.FORWARD)
	rig.set_roll(-1.0,Vector3.FORWARD)
	combat.attack_progress = 1.0
	combat.left_melee_progress = 1.0
	combat.right_melee_progress = 1.0
	combat.melee_progress = 1.0
	rig._clear_melee()
	rig._sync_primary_hand()
	rig.draw_amount = 0.0
	rig.global_rotation.y = atan2(spawn_point.x,spawn_point.z)
	combat.aim_point = Vector3(0,1.2,0)
	collision_layer = 4
	collision_mask = 1
	rig.visible = true

func try_ability(slot: int = 0) -> Dictionary:
	if not authoritative or not alive:
		return {"ok": false, "message": "You are down."}
	return ability.activate(slot)

func press_jump(roll_requested: bool) -> void:
	var grounded := is_on_floor()
	peek_requested = false
	if not alive or ability.active or not cover.prepare_jump():
		return
	_exposure_tick = -1
	combat.stop()
	dodge.reset()
	jump_requested = roll.press_jump(Vector3(move_direction.x,0,move_direction.y),-rig.global_basis.z,grounded,roll_requested) or jump_requested
	if jump_requested or roll.active:
		slide.reset()
		rig.set_slide(-1.0,Vector3.FORWARD)
	if roll.active:
		jump_requested = false
		combat.stop()

func set_block(pressed: bool, forward: Vector3) -> void:
	if not authoritative or not alive:
		return
	if pressed:
		combat.start_block(forward)
	else:
		combat.stop_block()

func receive_melee(amount: float, source_id: int, attacker_position: Vector3, headshot: bool = false) -> int:
	if not authoritative or not alive or source_id == slot:
		return Combat.DEFENSE_NONE
	var outcome: int = combat.resolve_melee_defense(attacker_position)
	if outcome == Combat.DEFENSE_PARRY:
		return outcome
	if outcome == Combat.DEFENSE_BLOCK or outcome == Combat.DEFENSE_WEAK_BLOCK:
		stamina = maxf(0.0,stamina-combat.block_stamina_cost())
		var push := global_position - attacker_position
		push.y = 0.0
		if push.length_squared() > 0.000001:
			push = push.normalized() * Combat.BLOCK_PUSH_SPEED
			velocity.x = push.x
			velocity.z = push.z
		if outcome == Combat.DEFENSE_WEAK_BLOCK:
			# The raised dagger absorbs the impact: half damage but the guard
			# stays up and the attacker's swing continues.
			take_damage(amount * Combat.WEAK_BLOCK_DAMAGE_SCALE,source_id,headshot,false)
		return outcome
	take_damage(amount,source_id,headshot)
	return Combat.DEFENSE_NONE

func clash_bounce(direction: Vector3) -> void:
	if not authoritative:
		return
	var planar := Vector3(direction.x,0.0,direction.z)
	if planar.length_squared() > 0.000001:
		planar = planar.normalized()
		velocity.x = planar.x * Combat.CLASH_BOUNCE_SPEED
		velocity.z = planar.z * Combat.CLASH_BOUNCE_SPEED

func stagger(seconds: float) -> void:
	if not authoritative:
		return
	combat.stagger(seconds)
	rig.set_hit_react(seconds)
	dodge.reset()
	velocity.x = 0.0
	velocity.z = 0.0

func try_step(direction: Vector3) -> bool:
	if not authoritative or not alive or combat.stagger_time > 0.0 or ability.active:
		return false
	var planar := Vector3(direction.x,0.0,direction.z)
	if planar.length_squared() < 0.0001:
		return false
	if not dodge.can_step(is_on_floor(),roll.active):
		return false
	if cover.active:
		leave_cover()
	if not dodge.try_step(planar,is_on_floor(),roll.active):
		return false
	combat.stop()
	slide.reset()
	rig.set_slide(-1.0,Vector3.FORWARD)
	stamina = maxf(0.0,stamina-DodgeStep.STAMINA_COST)
	return true

func set_crouch(requested: bool) -> void:
	if not requested:
		slide.reset()
		rig.set_slide(-1.0,Vector3.FORWARD)
	if not alive or not is_on_floor() or roll.active:
		return
	if requested and ability.active:
		return
	if requested and not cover.crouch_requested:
		var sprinting: bool = run_requested and not _exhausted and stamina > 1 and move_direction.length_squared() > 0.01
		if slide.try_start(self,cover,sprinting,roll.active):
			return
	cover.crouch_requested = requested

func toggle_cover(preferred_direction: Vector3) -> void:
	if cover.active:
		leave_cover()
	elif alive and is_on_floor() and not roll.active and not ability.active and cover.try_enter(preferred_direction):
		slide.reset()
		rig.set_slide(-1.0,Vector3.FORWARD)
		_exposure_tick = -1
		jump_requested = false
		combat.stop()

func leave_cover() -> void:
	combat.stop()
	cover.exit()
	_exposure_tick = -1
	peek_requested = false
	peek_view_right = Vector3.RIGHT
	peek_shoulder = 1
	rig.set_cover(false,cover.normal,cover.crouch_amount,false,Vector3.ZERO)

func reset_stance() -> void:
	consume_kind = ""
	_consume_elapsed = 0.0
	_heal_remaining = 0.0
	_heal_rate = 0.0
	combat.stop()
	combat.left_melee_progress = 1.0
	combat.right_melee_progress = 1.0
	combat.melee_progress = 1.0
	rig._clear_melee()
	rig._sync_primary_hand()
	cover.reset()
	slide.reset()
	dodge.reset()
	rig.set_hit_react(0.0)
	peek_requested = false
	peek_view_right = Vector3.RIGHT
	peek_shoulder = 1
	aim_snapshot_tick = -1
	_exposure_tick = -1
	jump_requested = false
	move_direction = Vector2.ZERO
	run_requested = false
	rig.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	rig.set_slide(-1.0,Vector3.FORWARD)

func get_aim_position() -> Vector3:
	return global_position + Vector3(0,1.2,0)

func head_hitbox_center() -> Vector3:
	return rig.head_hitbox_center() if is_instance_valid(rig) else global_position

func head_hit_profile() -> Vector2:
	return rig.head_hit_profile() if is_instance_valid(rig) else Vector2.ZERO

func get_display_name() -> String:
	return display_name

func note_weapon_blood(amount: float) -> void:
	# Host-side tally replicated in snapshots so clients can coat the weapon
	# they render for this fighter. Purely cosmetic.
	weapon_blood += maxf(amount, 0.0)

func take_damage(amount: float, source_id: int, headshot: bool = false, react: bool = true) -> void:
	if not authoritative or not alive or source_id == slot:
		return
	_cancel_consumable()
	var applied: float = amount * Hitbox.damage_multiplier(headshot) * (1.0 - rig.armor_reduction())
	health = maxf(0,health - applied)
	DamageNumbers.spawn(get_parent(),global_position,applied,"self" if is_local else "hit",headshot,health <= 0.0)
	BloodFx.wound(self,rig,get_aim_position(),applied,headshot,health <= 0,1.0)
	if react:
		var seconds: float = combat.stagger_from_damage(applied,MAX_HEALTH)
		rig.set_hit_react(seconds)
		dodge.reset()
	if health <= 0:
		alive = false
		respawn = 3.0
		deaths += 1
		combat.stop()
		reset_stance()
		roll.reset()
		collision_layer = 0
		collision_mask = 0
		rig.visible = false
		killed.emit(slot,source_id)

func try_consume(kind: String) -> bool:
	if not authoritative or not alive or consume_kind != "":
		return false
	if not Archer.CONSUMABLE_DATA.has(kind) or health >= 99.999:
		return false
	if combat.stagger_time > 0.0 or not is_on_floor() or roll.active or slide.active or ability.active:
		return false
	combat.stop()
	if not rig.begin_consumable(kind):
		return false
	consume_kind = kind
	_consume_elapsed = 0.0
	return true

func _advance_consumable(delta: float) -> void:
	if consume_kind != "":
		if not rig.is_consuming():
			consume_kind = ""
			_consume_elapsed = 0.0
		else:
			_consume_elapsed += delta
			var data: Dictionary = Archer.CONSUMABLE_DATA[consume_kind]
			if _consume_elapsed >= float(data.seconds):
				var kind := consume_kind
				consume_kind = ""
				_consume_elapsed = 0.0
				rig.end_consumable()
				if kind == "bandage":
					_heal_remaining = float(data.heal)
					_heal_rate = float(data.heal)/maxf(float(data.heal_seconds),0.001)
				else:
					health = minf(100.0,health+float(data.heal))
	if _heal_remaining > 0.0:
		var amount := minf(_heal_rate*delta,_heal_remaining)
		health = minf(100.0,health+amount)
		_heal_remaining = maxf(0.0,_heal_remaining-amount)

func _cancel_consumable() -> void:
	if consume_kind != "":
		consume_kind = ""
		_consume_elapsed = 0.0
		rig.cancel_consumable()

func update_combat_cover_side() -> void:
	cover.view_right = peek_view_right
	var tangent: Vector3 = cover.normal.cross(Vector3.UP)
	var side: int = peek_shoulder if peek_view_right.dot(tangent) >= 0.0 else -peek_shoulder
	if side != combat.cover_side:
		_exposure_tick = -1
	combat.cover_side = side
	update_cover_aim_readiness()

func update_cover_aim_readiness() -> void:
	if not cover.active:
		_exposure_tick = -1
	combat.cover_aim_ready = is_bot or peer_id <= 1 or not cover.active \
		or (_exposure_tick >= 0 and aim_snapshot_tick >= _exposure_tick)

func step(delta: float, actors: Array, simulation_tick: int = 0) -> void:
	if not authoritative:
		return
	if not alive:
		respawn = maxf(0,respawn-delta)
		if respawn <= 0:
			revive()
		return
	input_age += delta
	_advance_consumable(delta)
	if consume_kind != "":
		move_direction = Vector2.ZERO
		run_requested = false
		jump_requested = false
		peek_requested = false
		combat.stop_block()
	roll.advance(delta,is_on_floor())
	dodge.advance(delta,is_on_floor())
	ability.advance(delta)
	if ability.active:
		move_direction = Vector2.ZERO
		run_requested = false
		jump_requested = false
		peek_requested = false
		slide.reset()
	if is_bot:
		_bot_step(delta,actors)
	elif input_age > 0.65:
		move_direction = Vector2.ZERO
		run_requested = false
		peek_requested = false
		slide.reset()
		combat.stop_block()
		if combat.wants_cover_exposure() or rig.charge_frozen:
			combat.stop()
	if combat.stagger_time > 0.0:
		move_direction = Vector2.ZERO
		run_requested = false
		jump_requested = false
		peek_requested = false
		combat.stop_block()
	var direction := Vector3(move_direction.x,0,move_direction.y)
	var slide_velocity: Vector3 = slide.step(delta,self,cover,direction,roll.active)
	var running: bool = run_requested and (cover.active or not cover.crouched and not cover.crouch_requested) and not _exhausted and stamina > 1 and direction.length_squared() > 0.01 and not ability.active
	var stamina_rate: float = 0.0 if combat.blocking or ability.active else (-Stamina.SPRINT_DRAIN_PER_SECOND if running or slide.active else Stamina.REGEN_PER_SECOND)
	stamina = clampf(stamina + delta * stamina_rate,0,Stamina.MAX)
	if stamina <= Stamina.SPRINT_EXHAUSTED:
		_exhausted = true
	elif stamina >= Stamina.SPRINT_RESUME:
		_exhausted = false
	var was_in_cover: bool = cover.active
	update_combat_cover_side()
	var cover_velocity: Vector3 = cover.step(delta,direction,peek_requested or combat.wants_cover_exposure(),combat.cover_side,running)
	if not cover.peeking:
		_exposure_tick = -1
	elif _exposure_tick < 0:
		_exposure_tick = simulation_tick
	update_cover_aim_readiness()
	if slide.active:
		velocity.x = slide_velocity.x
		velocity.z = slide_velocity.z
	elif was_in_cover:
		velocity.x = cover_velocity.x
		velocity.z = cover_velocity.z
	else:
		var speed := 2.2 if cover.crouched or cover.crouch_requested else 8.5 if running else 5.5
		velocity.x = move_toward(velocity.x,direction.x*speed,35*delta)
		velocity.z = move_toward(velocity.z,direction.z*speed,35*delta)
	if dodge.active:
		var step_velocity: Vector3 = dodge.velocity()
		velocity.x = step_velocity.x
		velocity.z = step_velocity.z
	if roll.active:
		velocity.x = roll.direction.x * DodgeRoll.SPEED
		velocity.z = roll.direction.z * DodgeRoll.SPEED
	if not was_in_cover and not roll.active:
		var separation := _separation_velocity(actors)
		velocity.x += separation.x
		velocity.z += separation.z
	if ability.active:
		var charge_velocity: Vector3 = ability.velocity()
		velocity.x = charge_velocity.x
		velocity.z = charge_velocity.z
		jump_requested = false
	if jump_requested:
		velocity.y = 7.0
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 20*delta
	if roll.takeoff_pending:
		velocity.y = maxf(velocity.y,6.0)
		roll.takeoff_pending = false
	jump_requested = false
	var before := position
	move_and_slide()
	position.x = clampf(position.x,-bounds,bounds)
	position.z = clampf(position.z,-bounds,bounds)
	var actual := (position-before)/maxf(delta,0.0001)
	slide.after_move(self,actual)
	rig.set_cover(cover.active,cover.normal,cover.crouch_amount,cover.peeking,cover.lean)
	rig.set_slide(slide.progress if slide.active else -1.0,slide.direction)
	rig.set_step(dodge.progress if dodge.active else -1.0,dodge.direction)
	rig.set_locomotion(actual,is_on_floor() and not roll.active)
	rig.set_roll(roll.progress if roll.active else -1.0,roll.direction)
	combat.set_motion(actual,running or slide.active or roll.active or dodge.active,is_on_floor() and not roll.active)
	combat.advance(delta)

func _separation_velocity(actors: Array) -> Vector3:
	# Hard fighter capsules would stop centres 0.6 m apart and shove a close
	# attacker off their aim. Bodies are now soft: a bounded push only grows
	# once the centres are inside 0.46 m, still leaving room to measure a stab.
	var push := Vector3.ZERO
	for other in actors:
		if other == self or not is_instance_valid(other) or not other.alive:
			continue
		var offset: Vector3 = global_position-other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance >= 0.46:
			continue
		if distance < 0.001:
			var angle := TAU*float(slot)/4.0
			offset = Vector3(cos(angle),0.0,sin(angle))
		else:
			offset /= distance
		push += offset*(0.46-distance)/0.46
	return push.limit_length(1.0)*3.2

func _bot_step(_delta: float, actors: Array) -> void:
	if combat.stagger_time > 0.0:
		move_direction = Vector2.ZERO
		run_requested = false
		jump_requested = false
		combat.stop_block()
		return
	var nearest = null
	var distance := INF
	for other in actors:
		if other == self or not other.alive:
			continue
		var candidate: float = position.distance_squared_to(other.position)
		if candidate < distance:
			distance = candidate
			nearest = other
	if nearest == null:
		move_direction = Vector2.ZERO
		combat.stop()
		return
	var to_enemy: Vector3 = nearest.position-position
	to_enemy.y = 0
	var direction := to_enemy.normalized()
	_sight_query.from = get_aim_position()
	_sight_query.to = nearest.get_aim_position()
	var obstructed := not get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty()
	if distance > 100 or obstructed:
		_sight_query.to = _sight_query.from + direction * 2.0
		if not get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty():
			direction = direction.rotated(Vector3.UP,1.1 if slot % 2 == 0 else -1.1)
		move_direction = Vector2(direction.x,direction.z)
	elif distance < 16:
		move_direction = Vector2(-direction.x,-direction.z)
	else:
		move_direction = Vector2.ZERO
	run_requested = false
	combat.set_aim(nearest.get_aim_position())
	if distance < 9.0:
		rig.set_weapon("sword")
	elif distance > 20.25:
		rig.set_weapon("bow")
	if rig.weapon == "sword":
		move_direction = Vector2(direction.x,direction.z) if distance > 2.25 else Vector2.ZERO
		if combat.clash_cooldown <= 0.0 and not obstructed \
				and distance <= pow(float(Archer.SWORD_DATA[rig.sword_index].reach),2):
			combat.begin_melee()
		return
	if not obstructed and distance < 625.0:
		if combat.can_draw():
			combat.begin_draw()
		elif rig.draw_amount >= 0.85 and rig.phase in ["DRAWING", "HOLDING"]:
			combat.release_draw()

func _floor_height(point: Vector3) -> float:
	_floor_query.from = point + Vector3(0,1,0)
	_floor_query.to = point - Vector3(0,2,0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return float(hit.position.y) if not hit.is_empty() else global_position.y

func gear_bits() -> int:
	return gear_bits_for(rig)

static func gear_bits_for(rig) -> int:
	# Ten compact bits for the paperdoll presentation that the bow/sword/armor
	# fields cannot carry: off-hand weapon, staff, focus and shield silhouette.
	var bits := 0
	if rig.off_weapon_active:
		bits |= 1
	if rig.off_weapon_kind == "sword":
		bits |= 2
	bits |= (int(rig.off_weapon_index) & 1) << 2
	if rig.staff_active:
		bits |= 1 << 3
	bits |= (int(rig.staff_index) & 1) << 4
	var focus_code := 0
	if rig.focus_active:
		focus_code = 1 if rig.focus_kind == "tome" else 2
	bits |= (focus_code & 3) << 5
	bits |= (int(rig.focus_index) & 1) << 7
	bits |= (int(rig.shield_variant) & 3) << 8
	return bits

func snapshot() -> Dictionary:
	return {"slot":slot,"peer":peer_id,"bot":is_bot,"name":display_name,"position":position,"velocity":velocity,
		"health":health,"alive":alive,"kills":kills,"deaths":deaths,"respawn":respawn,"bow":rig.bow_index,"armor":rig.armor_bits() | (ArmorData.SHIELD_BIT if rig.shield_equipped else 0),"sword":rig.sword_index,"weapon":rig.weapon,"gear":gear_bits(),
		"weapon_blood":weapon_blood,
		"stamina":stamina,"ability":ability.snapshot(),
		"animation":rig.get_animation_state(),"progress":combat.attack_progress,"movement":combat.movement_mode,
		"interval":combat.get_attack_interval(),"aim":combat.aim_point,"grounded":is_on_floor(),"cover":cover.snapshot()}

func apply_snapshot(state: Dictionary) -> void:
	var replaced := peer_id != int(state.peer) or is_bot != bool(state.bot)
	peer_id = int(state.peer)
	is_bot = bool(state.bot)
	display_name = str(state.name)
	var previous_health := health
	var previous_weapon_blood := weapon_blood
	var had_pose := _received_pose
	var target: Vector3 = state.position
	_target_position = target
	var now := Time.get_ticks_msec()/1000.0
	_states.append({"time":now,"position":target,"velocity":state.velocity})
	while _states.size() > INTERP_BUFFER_LIMIT:
		_states.pop_front()
	while _states.size() > 2 and float(_states[0].time) < now-INTERP_HISTORY:
		_states.pop_front()
	if replaced or not _received_pose or position.distance_squared_to(target) > 36:
		position = target
	_states[-1] = {"time":now,"position":target,"velocity":state.velocity}
	_received_pose = true
	velocity = state.velocity
	health = state.health
	stamina = float(state.get("stamina",stamina))
	ability.apply_snapshot(state.get("ability",{}))
	weapon_blood = float(state.get("weapon_blood",weapon_blood))
	var fresh_weapon_blood := 0.0
	if not authoritative and had_pose and not replaced and weapon_blood-previous_weapon_blood > 0.01:
		fresh_weapon_blood = weapon_blood-previous_weapon_blood
	if not authoritative and had_pose and not replaced and previous_health-health > 0.01:
		DamageNumbers.spawn(get_parent(),global_position,previous_health-health,"self" if is_local else "hit",false,health <= 0.0)
		BloodFx.wound(self,rig,get_aim_position(),previous_health-health,false,health <= 0.0,1.0)
	alive = state.alive
	kills = state.kills
	deaths = state.deaths
	respawn = state.respawn
	rig.visible = alive
	collision_layer = 4 if alive else 0
	collision_mask = 1 if alive else 0
	if rig.bow_index != int(state.bow):
		rig.set_bow(int(state.bow))
	var armor_bits := int(state.armor) & ArmorData.PIECE_MASK
	var shield_state := (int(state.armor) & ArmorData.SHIELD_BIT) != 0
	if rig.armor_bits() != armor_bits:
		rig.set_armor_bits(armor_bits)
	if rig.sword_index != int(state.sword):
		rig.set_sword(int(state.sword))
	var gear := int(state.get("gear",_gear_bits))
	var gear_changed := gear != _gear_bits
	var staff_on := (gear & 8) != 0
	var staff_slot := (gear >> 4) & 1
	if gear_changed:
		_gear_bits = gear
		var off_active := (gear & 1) != 0
		var off_kind := "sword" if (gear & 2) != 0 else "dagger"
		var focus_code := (gear >> 5) & 3
		var focus_kind := "" if focus_code == 0 else ("tome" if focus_code == 1 else "skull")
		# Arm the off hand before the weapon mode so a replicated dual loadout
		# can actually enter dual; the staff is restored last because set_sword()
		# deliberately stows it.
		rig.set_off_focus(focus_kind,(gear >> 7) & 1,focus_code != 0)
		rig.set_shield_variant((gear >> 8) & 3)
		rig.set_off_weapon(off_kind,(gear >> 2) & 1,off_active)
	if rig.weapon != str(state.weapon):
		rig.set_weapon(str(state.weapon))
	if rig.shield_equipped != shield_state:
		rig.set_shield(shield_state)
	if gear_changed:
		rig.set_staff(staff_slot,staff_on)
	if fresh_weapon_blood > 0.0:
		BloodFx.stain_weapon(rig,fresh_weapon_blood)
	cover.apply_snapshot(state.cover)
	if not alive:
		reset_stance()
	rig.set_cover(cover.active,cover.normal,cover.crouch_amount,cover.peeking,cover.lean)
	rig.set_locomotion(velocity,bool(state.grounded) and float(state.animation.roll) < 0)
	rig.apply_animation_state(state.animation)
	combat.attack_progress = state.progress
	combat.movement_mode = state.movement
	combat.aim_point = state.aim
	combat.blocking = rig.is_blocking()
	# Guard timing stays host-authoritative; a replica HUD shows GUARDING rather
	# than inventing a parry window from snapshot arrival time.
	combat.block_time = 0.0

func _interpolate_position(render_time: float) -> Vector3:
	if _states.is_empty():
		return _target_position
	var newest: Dictionary = _states[-1]
	if render_time >= float(newest.time):
		# Snapshot starved: carry the last authoritative velocity briefly, then
		# hold. Never invent a long extrapolation that can rewind a hit.
		var extra := minf(render_time-float(newest.time),INTERP_EXTRAPOLATION)
		return Vector3(newest.position)+Vector3(newest.velocity)*extra
	var oldest: Dictionary = _states[0]
	if render_time <= float(oldest.time):
		var first_point: Vector3 = oldest.position
		return first_point
	for index in range(1,_states.size()):
		var after: Dictionary = _states[index]
		if render_time > float(after.time):
			continue
		var before: Dictionary = _states[index-1]
		var span := maxf(float(after.time)-float(before.time),0.001)
		var weight := clampf((render_time-float(before.time))/span,0.0,1.0)
		var from_point: Vector3 = before.position
		var to_point: Vector3 = after.position
		return from_point.lerp(to_point,weight)
	var last_point: Vector3 = newest.position
	return last_point

func _process(delta: float) -> void:
	if not authoritative and _received_pose:
		var render_time := Time.get_ticks_msec()/1000.0-interp_delay
		position = _interpolate_position(render_time)
	_label.text = "%s%s  %d" % [display_name," [BOT]" if is_bot else "",int(health)]
	_ground_ring.visible = alive
	_ground_ring.global_position = Vector3(global_position.x,_floor_height(global_position)+0.025,global_position.z)
