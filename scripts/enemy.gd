extends CharacterBody3D

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float, victim: CharacterBody3D)
signal arrow_fired(origin: Vector3, direction: Vector3, speed: float, damage: float)

const Geo = preload("res://scripts/geo.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const SeveredHead = preload("res://scripts/severed_head.gd")
const SeveredBody = preload("res://scripts/severed_body.gd")
const WolfVisual = preload("res://scripts/wolf_visual.gd")
const DevilVisual = preload("res://scripts/cinder_devil_visual.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const HeldWeapon = preload("res://scripts/held_weapon.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const VoiceScript = preload("res://scripts/audio/voice.gd")
const VoiceEmitterScript = preload("res://scripts/audio/voice_emitter.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const MobSteering = preload("res://scripts/mob_steering.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const MobLod = preload("res://scripts/mob_lod.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const DEVIL_HEALTH := 24.0
## How far each kind can see. Distance alone never starts a fight: the mob has
## to have the ranger in its forward cone with a clear line of sight, and it
## keeps hunting for `MobSenses.MEMORY_SECONDS` after losing that view.
const WILD_SIGHT := 23.0
const DEVIL_SIGHT := 30.0
const DEVIL_WINDUP := 0.30
const DEVIL_STRIKE := 0.16
const DEVIL_RECOVER := 0.30
const DEVIL_SLIDE_SECONDS := 0.46
const DEVIL_DAMAGE := 8.0
const DEVIL_LEAP_DAMAGE := 10.0
const DEVIL_MAX_ATTACKERS := 3
## The physical capsules these bodies ride, declared once so the head zone can
## never be narrower than the surface an arrow actually stops on.
const WOLF_BODY_RADIUS := 0.40
const DEVIL_BODY_RADIUS := 0.34
## What a briar wolf is worth once it falls: a pelt every time, and one or two of
## the other three parts off the body's own salvage - the whole of what a kill in
## the wood pays now that the wolves carry no blade. The table is the frontier's,
## not the loot vacuum's: the corpse record is filled from here, so a wolf answers
## the same way whether it is the host's body or a replay of the same hunt.
const WOLF_PELT := "wolf_pelt"
const WOLF_PARTS := ["wolf_pelt", "wolf_bone", "wolf_tooth", "wolf_paw"]
## The share of wolves that also give up a second spare part. A body that leaves
## only a pelt is a thin kill, not a miss.
const WOLF_SPARE_SHARE := 0.5
var kind := 0
var pack_index := -1
var devil_weapon := "claw"
var player: CharacterBody3D
var targets: Array[CharacterBody3D] = []
var replica := false
## Buffered server states: a replica renders a short delay behind the host so
## uneven packets read as motion, and dead-reckons when the buffer runs dry.
var _timeline = NetReplication.mob_timeline()
var _received_pose := false
## The last state this copy was handed, and whether it has gone quiet. A replica
## the host stopped naming - a kill outside the batch, a body past the 70 m band -
## otherwise stands where it was, on a screen the host no longer shows it on.
var _state_at := -1.0
var stale := false
## How long a replica may go without a state before it leaves the screen. The
## host repeats an unchanged body once a second (`MOB_REFRESH_TICKS`) and names
## the ones it stops streaming at once (`receive_mob_leaves`), so this is only
## the last resort - a knot of missed datagrams. Shorter than one refresh, it hid
## a living mob for a quarter of a second, every second.
const STALE_SECONDS := 2.0
## The stream tick at which the host stopped naming this copy to this peer. A
## state from before that is a datagram still in flight, not news.
var _stream_left := -1
## Distance to the eye this machine draws through (`MobCuller.view_distance`), or
## -1 while nothing has measured it: what a body is drawn at is that camera's
## business, what it is simulated at is every soul's.
var _view_distance := -1.0
var safe_center := Vector3.ZERO
## A body is placed on its ground by whoever spawned it, and the wilderness
## streams its terrain tile by tile: a body whose feet find nothing under them
## must not sink out of the world, one coarse LOD step at a time. The fall is
## taken only where there is something to fall to, asked of the world at most
## four times a second - which is also what catches terrain that streams in
## under a body spawned ahead of it.
var _ground_below := true
var _ground_probe_at := -1.0
const GROUND_PROBE_SECONDS := 0.25
const GROUND_PROBE_DEPTH := 12.0
var health := 38.0
var max_health := 38.0
## Slot of the ranger whose damage landed last; the frontier reads it on death
## so off-hand skull trinkets only pay out to the killer.
var last_hitter := -1
var alive := true
var _impact_force := Vector3.ZERO
## The flight of a killing headshot, named by the arrow that landed it or by the
## death snapshot a replica was handed. Spent by the next blow.
var _head_shot := Vector3.ZERO
## A two-handed overhead's shove, named before the blow (`note_cleave`).
var _cleave := Vector3.ZERO
var _cleave_kind := "horizontal"
var _sever := Vector3.ZERO
var _split := Vector3.ZERO
var home := Vector3.ZERO
var state := "IDLE"
var _state_time := 0.0
var _stagger_duration := 0.0
var _body: Node3D
var _wolf: WolfVisual
## The salvage this body rolled when its corpse was first read, kept so a body
## that slid a step in its ragdoll still answers the parts it was killed with.
var _wolf_parts: Array[String] = []
var _devil: DevilVisual
## The noise this body makes: a growl going into the bite, a cry going down.
var _voice: VoiceEmitter
var _dodge
var _warning: MeshInstance3D
var _query := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()
var _senses := MobSenses.new()
var _steering := MobSteering.new()
## The patch this body keeps to when it is calm.
var _wander := MobWander.new()
## Tick budget: the further from the nearest ranger, the rarer the tick.
var _lod := MobLod.new()
## Presentation band last applied (0 shadowed, 1 animate-only, 2 resting).
var _present_band := -1
## Parked by `MobCuller`: no tick, no draw, no state change while it is true.
var dormant := false
var _attacker: Node3D
## Ghost of the Warband: the far-fight stance `PassiveDuelBrain` drives - the
## body holds its ring and guards between blows.
var warband_passive := false
var _warband_guard := 0.0
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
var _attack_reach := 1.8
var _leap_damage := DEVIL_LEAP_DAMAGE
var _struck := false
var _shot_fired := false
var shots_fired := 0
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
var _face_intent := Vector3.FORWARD
var _target: CharacterBody3D

func _ready() -> void:
	name = "BriarWolf" if kind == 0 else "CinderDevil"
	home = global_position
	# Watch the road: spawn facing the arriving ranger, like the newer mob
	# families do. Without a facing the sight cone would stare down -Z forever
	# and a whole pack could miss a ranger standing beside it.
	if is_instance_valid(player):
		var facing := player.global_position - global_position
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			rotation.y = atan2(-facing.x, -facing.z)
	max_health = 38.0 if kind == 0 else DEVIL_HEALTH
	health = max_health
	collision_layer = 2
	# World and ranger bodies only: mobs do not collide with each other (see
	# `devil_mob._ready`).
	collision_mask = 1 | 4
	# One slide per move (see `devil_mob._ready`).
	max_slides = 2
	# A body on a slope must keep its horizontal motion: the default stop
	# cancels it the moment the ground tilts, which read as crawling.
	floor_stop_on_slope = false
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	var shape := CapsuleShape3D.new()
	if kind == 0:
		shape.radius = WOLF_BODY_RADIUS
		shape.height = 0.95
	else:
		# The authored cinder devil stands 2.11 m to the crown: a gaunt frame
		# on a 2.15 m capsule, not the 0.9 m primitive imp it replaced.
		shape.radius = DEVIL_BODY_RADIUS
		shape.height = 2.15
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	add_child(collision)
	_body = Node3D.new()
	add_child(_body)
	if kind == 0:
		_build_wolf_visual()
	else:
		_build_devil_visual()
	var warning_radius := 0.85 if kind == 2 else 1.5
	var warning_material := Geo.material(Color(0.95, 0.22, 0.08, 0.38))
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning = Geo.cylinder(self, warning_radius, warning_radius, 0.018, Vector3(0, 0.035, 0), warning_material, 32)
	_warning.visible = false
	_query.collision_mask = 1
	# Any wilderness mob answers a neighbour's alarm, so one shot at a wolf
	# brings the rest of the pack and the devils standing nearby.
	add_to_group(MobSenses.GROUP)
	if kind == 2:
		add_to_group("cinder_devils")
		_dodge = DodgeStep.new()
		_dodge.travel = DodgeStep.TRAVEL * 0.5
		_dodge.duration = 0.22
		add_child(_dodge)
		var seeded := maxi(pack_index,0)
		_rng.seed = 7319 + seeded * 131
		_orbit_dir = 1.0 if seeded % 2 == 0 else -1.0
		_orbit_radius = 3.4 + float(seeded % 3) * 1.0
		_orbit_phase = _rng.randf() * TAU
		_attack_cooldown = 0.25 + float(seeded % 5) * 0.18
		_decision_timer = _rng.randf_range(0.15,0.45)
		devil_weapon = str(devil_weapon).to_lower()
		if devil_weapon not in ["claw","dagger","sword","bow"]:
			devil_weapon = "claw"
		match devil_weapon:
			"dagger":
				_attack_damage = 6.0
				_attack_reach = 1.6
				_leap_damage = 8.0
			"sword":
				_attack_damage = 11.0
				_attack_reach = 2.0
				_leap_damage = 13.0
			"bow":
				_attack_damage = 7.0
				_attack_reach = 0.0
				_leap_damage = 7.0
				_orbit_radius = 8.2 + float(seeded % 3) * 0.8
			_:
				_attack_damage = DEVIL_DAMAGE
				_attack_reach = 1.8
				_leap_damage = DEVIL_LEAP_DAMAGE
		_devil.set_weapon(devil_weapon)
		if is_instance_valid(player):
			var start := global_position - player.global_position
			start.y = 0.0
			if start.length_squared() > 0.0001:
				_orbit_angle = atan2(start.z,start.x)+float(seeded)*0.62
		state = "CIRCLE"
	# A pack that meets the same barrier splits around both of its sides.
	_steering.bias = _orbit_dir
	_lod = MobLod.new(int(absf(global_position.x) * 11.0 + absf(global_position.z) * 5.0))
	# The noise this body makes. The voice is named by the species, so a wolf and
	# a cinder devil keep their own takes without this file knowing either one;
	# `VoiceLibrary` decides whether that voice has been recorded at all.
	_voice = VoiceEmitterScript.create(voice_id(), self, false, 1103 + maxi(pack_index, 0))


## The voice this body speaks with. A species without recorded lines answers an
## empty name, which `VoiceEmitter` treats as silence rather than as an error.
func voice_id() -> String:
	return "wolf" if kind == 0 else "cinder_devil"

func _build_wolf_visual() -> void:
	_wolf = WolfVisual.new()
	_wolf.name = "WolfVisual"
	_body.add_child(_wolf)

func _build_devil_visual() -> void:
	_devil = DevilVisual.new()
	_devil.name = "DevilVisual"
	_body.add_child(_devil)

func get_aim_position() -> Vector3:
	return global_position + Vector3(0, 0.68 if kind == 0 else 1.25, 0)

## Squad-drive hooks. A squadmate naming a wolf as its quarry is the same
## enraged pursuit a landed blow starts, so `squad_drive.retarget` can point a
## wolf at the body that came for it without knowing which mob family it is.
func hunt(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	_senses.notice(target, target.global_position)
	if target is CharacterBody3D:
		player = target

## True while the wolf already wants somebody: a fresh sighting, a blow or a
## squadmate's challenge.
func hunting() -> bool:
	return _senses.aggressive()

func blood_rig() -> Node3D:
	if kind == 2 and is_instance_valid(_devil):
		var anchor := _devil.blood_anchor()
		if is_instance_valid(anchor):
			return anchor
	return _body

func blood_scale() -> float:
	return 1.35 if kind == 0 else 1.20

## What is on this body when it falls, for `WarbandLoot.register_corpse`. A wolf
## has no blade to take and nothing to strip off its back, so this is the salvage
## alone; every other kind answers empty, which is what leaves the cinder devils'
## dropped steel to the scene that spawns it.
func gear_items() -> Array[String]:
	if kind != 0:
		return []
	if _wolf_parts.is_empty():
		_wolf_parts = parts_for(name, global_position)
	return _wolf_parts.duplicate()

## The salvage one wolf leaves, off its identity: the number a scene gave it
## (`BriarWolf3`) and the metre it fell on. Two bodies that answer both, on any
## machine and in any replay, yield the same pieces.
static func parts_for(wolf_name: String, at: Vector3) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _salvage_seed(wolf_name, at)
	var out: Array[String] = [WOLF_PELT]
	var spare: Array = WOLF_PARTS.duplicate()
	spare.erase(WOLF_PELT)
	var wanted := 3 if rng.randf() < WOLF_SPARE_SHARE else 2
	while out.size() < wanted and not spare.is_empty():
		var index := rng.randi_range(0, spare.size() - 1)
		out.append(str(spare[index]))
		spare.remove_at(index)
	return out

## The seed, rounded to the metre: a corpse is registered on the frame it dies,
## but a body that is nudged before anything reads it must not change what it
## carried.
static func _salvage_seed(wolf_name: String, at: Vector3) -> int:
	var seed_value := absi(wolf_name.hash()) * 31
	seed_value += int(round(at.x)) * 7 + int(round(at.z)) * 13
	return seed_value

func blood_weapon_anchor(_hand: String = "") -> Node3D:
	if kind == 2 and is_instance_valid(_devil):
		return _devil.weapon_anchor()
	return null

## The limb or muzzle that landed the blow, for the blood it carried away: a
## wolf's jaws or the cinder devil's raking hand.
func blood_strike_point() -> Vector3:
	if kind == 0 and is_instance_valid(_wolf):
		return _wolf.head_hitbox_center()
	if kind == 2 and is_instance_valid(_devil):
		return _devil.strike_hand_position()
	return get_aim_position()

func get_display_name() -> String:
	return "Briar wolf" if kind == 0 else "Cinder devil"

## The catalog id of the weapon this mob carries; empty for wolves and claw
## devils that hold nothing.
func held_weapon_id() -> String:
	return HeldWeapon.item_id(devil_weapon) if kind == 2 else ""

func head_hitbox_center() -> Vector3:
	if kind == 0 and is_instance_valid(_wolf):
		return _wolf.head_hitbox_center()
	if is_instance_valid(_devil):
		return _devil.head_hitbox_center()
	return get_aim_position()
func head_hit_profile() -> Vector2:
	if kind == 0:
		return Vector2(Hitbox.head_zone_radius(Hitbox.WOLF_HEAD_RADIUS, WOLF_BODY_RADIUS),
			Hitbox.WOLF_HEAD_HALF_HEIGHT)
	return Vector2(Hitbox.head_zone_radius(Hitbox.DEVIL_HEAD_RADIUS, DEVIL_BODY_RADIUS),
		Hitbox.DEVIL_HEAD_HALF_HEIGHT)


func _physics_process(delta: float) -> void:
	Perf.begin("wolf.ai")
	_think(delta)
	Perf.end()


func _think(delta: float) -> void:
	if dormant or replica:
		return
	if not alive:
		CorpsePhysics.settle_root(self, delta)
		return
	var nearest := _nearest_ranger()
	_cull_presentation(_present_distance(nearest))
	var budget := _lod.slice(nearest, delta, not _senses.aggressive())
	if budget <= 0.0:
		# The brain sits the frame out; the body does not. This body used to move on
		# one frame in twelve, so a wolf at seventy metres crossed the ground in
		# metre-long steps five times a second - the pop a player reads as a mob
		# stuttering forward, and the staircase a replica could only interpolate.
		_glide(delta)
		return
	delta = budget
	# Sight and the pursuit memory decide aggression for the wolf and the
	# cinder devil exactly as they do for the newer mob families. Below the
	# sight range there is nobody to look for, so that tick skips its rays.
	var pursuit := false
	if nearest <= _sight_range():
		Perf.begin("wolf.senses")
		pursuit = _senses.step(self, _candidates(), delta, _sight_range(),
			_eye_height(), Callable(self, "_is_hostile"))
		Perf.end()
	else:
		_senses.age(delta)
		pursuit = _senses.aggressive()
	if _senses.woke:
		MobSenses.alert_packmates(self, _senses.target, _senses.last_seen, _wander.group)
	_target = _senses.target if is_instance_valid(_senses.target) else _resolve_target()
	if not is_instance_valid(_target) and not pursuit:
		_calm_tick(delta)
		return
	if kind == 2:
		_step_devil(delta, pursuit)
		return
	_state_time += delta
	# Ghost of the Warband: the wolf's guard window, ticked on the same clock.
	_warband_guard = maxf(0.0, _warband_guard - delta)
	var focus := _senses.focus() if pursuit else _target.global_position
	var displacement := focus - global_position
	displacement.y = 0.0
	var distance := displacement.length()
	var target_safe := MobSenses.in_safe_ring(safe_center, focus)
	var target_direction := Vector3.ZERO
	var speed := 3.1
	if state == "STAGGER":
		if _state_time >= _stagger_duration:
			state = "IDLE"
			_state_time = 0.0
	elif state == "WINDUP":
		if _state_time >= 0.65:
			if distance < 2.1 and not target_safe and absf(_target.position.y - position.y) < 1.7:
				attacked.emit(self,13.0,_target)
			# A parry can synchronously replace the attack with STAGGER.
			if state == "WINDUP":
				state = "RECOVER"
				_state_time = 0.0
				_warning.visible = false
	elif state == "RECOVER":
		if _state_time > 0.85:
			state = "IDLE"
	else:
		if pursuit and not target_safe:
			state = "CHASE"
			target_direction = displacement.normalized()
			if _senses.hunt > 0.0 and not _senses.seen:
				# Enraged by a landed blow: keep closing until it is seen.
				target_direction = displacement.normalized()
			elif not _senses.seen and distance < MobSenses.ARRIVE_DISTANCE:
				# Standing over the last sighting: sweep the ground.
				rotation.y += sin(_state_time * 1.5) * delta * 1.7
				target_direction = Vector3.ZERO
			elif _senses.seen and distance < 1.65 and _warband_guard <= 0.0:
				state = "WINDUP"
				_state_time = 0.0
				_warning.visible = true
				# The growl is the telegraph heard: a player looking the wrong
				# way still gets told the jaws are coming. Not every bite - the
				# row's chance is what keeps a pack from sounding like one animal.
				_voice.say("attack")
				target_direction = Vector3.ZERO
			elif warband_passive and distance < 2.6:
				# Ghost of the Warband: a passive wolf holds its ring instead of
				# leaning into the quarry.
				state = "CHASE"
				target_direction = Vector3.ZERO
		else:
			# Calm: keep to the pack's patch, walking the shared goal and
			# resting when it arrives.
			var wander := _wander.step(self)
			var outside := _wander.outside(self)
			state = "RETURN" if outside else "IDLE"
			if wander.length_squared() > 0.0001:
				target_direction = wander
				speed = 2.6 if outside else 1.7
	_drive_wolf(delta, target_direction, speed)

## The wolf's shared motion tail: steer around obstacles, drive, present.
func _drive_wolf(delta: float, direction: Vector3, speed: float) -> void:
	if direction.length_squared() > 0.1:
		direction = _steer(direction)
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 8.0, 1.0))
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 12.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 12.0)
	_hold_altitude(delta)
	# One physics frame of motion, never the banked budget: the frames this body's
	# brain sat out already stepped it (`_glide`), and a scaled sweep here would
	# cover that ground twice.
	MobLod.move(self)
	_present_body(delta)


## The body's own step on a frame its brain was not granted: gravity, one sweep,
## the presentation. Nothing is decided here - the motion the last granted tick
## set carries the body - so a body on a twelve-frame budget still walks, runs and
## turns smoothly, and the brain still costs what it did.
func _glide(delta: float) -> void:
	_hold_altitude(delta)
	MobLod.move(self)
	_present_body(delta)


## The rig's own read of this frame, and nothing past the resting band: a body
## whose clips stopped being evaluated (`MobLod.band` 2, past `ANIMATE_DISTANCE`)
## was still being asked for its motion every frame.
func _present_body(delta: float) -> void:
	if _present_band < 2:
		_update_cosmetics(delta)


## Gravity and the feet, in one place for both the decided tick and the glide.
func _hold_altitude(delta: float) -> void:
	if is_on_floor() or not _ground_below_feet():
		velocity.y = 0.0
	else:
		velocity.y = velocity.y - 18.0 * delta


## How far this body is from the eye that draws it: the camera on this machine
## when the culler has measured one, and the nearest ranger as the fallback for a
## scene with no camera behind it.
func _present_distance(nearest: float) -> float:
	return _view_distance if _view_distance >= 0.0 else nearest


## Whether there is anything to land on under this body. One standing on the
## floor never asks its world; an airborne one asks a quarter of a second at a
## time. Nothing below is not "falling" - it is a body the wilderness has no
## ground for, and it keeps the altitude it was placed at.
func _ground_below_feet() -> bool:
	if is_on_floor():
		return true
	var now := Time.get_ticks_msec() / 1000.0
	if _ground_probe_at >= 0.0 and now - _ground_probe_at < GROUND_PROBE_SECONDS:
		return _ground_below
	_ground_probe_at = now
	_query.from = global_position + Vector3.UP * 0.1
	_query.to = _query.from - Vector3.UP * GROUND_PROBE_DEPTH
	_ground_below = not get_world_3d().direct_space_state.intersect_ray(_query).is_empty()
	return _ground_below


## Nothing in sight and nothing remembered: keep the patch alive. Without this
## tick a calm body never moved at all, because the state machine below only
## runs once a target exists.
func _calm_tick(delta: float) -> void:
	if kind == 2:
		# The cinder devil's own machine has a calm RETURN branch already.
		_step_devil(delta, false)
		return
	_state_time += delta
	var wander := _wander.step(self)
	var outside := _wander.outside(self)
	state = "RETURN" if outside else "IDLE"
	var direction := Vector3.ZERO
	var speed := 0.0
	if wander.length_squared() > 0.0001:
		direction = wander
		speed = 2.6 if outside else 1.7
	_drive_wolf(delta, direction, speed)


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


## Everyone this mob could hunt: the local ranger plus every host seat.
func _candidates() -> Array:
	var list: Array = []
	for candidate in targets:
		if is_instance_valid(candidate) and not list.has(candidate):
			list.append(candidate)
	if is_instance_valid(player) and not list.has(player):
		list.append(player)
	return list


func _sight_range() -> float:
	return DEVIL_SIGHT if kind == 2 else WILD_SIGHT


## Eye height follows the authored body: the wolf looks out low, the cinder
## devil looks out of its horned skull about two metres up.
func _eye_height() -> float:
	var height := 0.95 if kind == 0 else 2.15
	return maxf(0.6, height * MobSenses.EYE_HEIGHT_FRACTION)


## Huntable rangers: alive and outside the town's safe ring.
func _is_hostile(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or candidate.get("alive") == false:
		return false
	return not MobSenses.in_safe_ring(safe_center, candidate.global_position)


## Wolves hunt in bands and cinder devils keep their packs; both keep a shared
## patch. Nothing in this family is a lone post-holder.
func wanders_packed() -> bool:
	return true


func wander_radius() -> float:
	return 10.0 if kind == 0 else 12.0


func pack_family() -> String:
	return "wolf" if kind == 0 else "cinder_devil"


## Distance to the closest ranger, for the tick budget.
func _nearest_ranger() -> float:
	var best := INF
	if is_instance_valid(player):
		best = global_position.distance_squared_to(player.global_position)
	for candidate in targets:
		if is_instance_valid(candidate):
			best = minf(best, global_position.distance_squared_to(candidate.global_position))
	if best == INF:
		return INF
	return sqrt(best)


## Far bodies stop evaluating animation tracks; the skeleton keeps its last
## pose, which at that distance is a few pixels.
func _cull_presentation(nearest: float) -> void:
	var band := MobLod.band(nearest)
	if band == _present_band:
		return
	_present_band = band
	if kind == 0 and is_instance_valid(_wolf) and _wolf.has_method("set_distance"):
		_wolf.set_distance(nearest)
	elif is_instance_valid(_devil) and _devil.has_method("set_distance"):
		_devil.set_distance(nearest)


## The culler's only call into a parked body: one distance check per sweep.
## Sight rays, steering, the state machine, the swept move and the skinning are
## all behind the physics process `mob_sleep` turns off.
##
## `eye_distance` is measured from every body a soul could be inside - the tick
## budget follows the fight, whoever is in it. `view_distance` is measured from
## this machine's own camera, and is the only one the presentation bands read.
func mob_lod_sweep(eye_distance: float = -1.0, view_distance: float = -1.0) -> void:
	if not alive:
		return
	if view_distance >= 0.0:
		_view_distance = view_distance
	var nearest := eye_distance if eye_distance >= 0.0 else _nearest_ranger()
	_cull_presentation(_present_distance(nearest))
	if not MobLod.dormant(nearest, dormant):
		if dormant:
			mob_wake()
		return
	if dormant:
		return
	if replica or _may_sleep():
		mob_sleep()


## Only a calm body with its feet down may park. A body that is hunting has to
## keep running (that is the whole point of the pursuit memory), and one frozen
## mid-leap would hang in the air until a ranger walked back. A replica runs no
## AI at all, so it parks on distance alone.
func _may_sleep() -> bool:
	return not _senses.aggressive() and is_on_floor()


## Parked: the body keeps its position, health, pack, gold and corpse, and
## loses its physics process and its draw call. Nothing outside `MobSenses` can
## see it from here, and the frontier's fog is opaque well before it.
func mob_sleep() -> void:
	if dormant:
		return
	dormant = true
	if not replica:
		# Nothing banked from before the sleep; the first frame back is granted.
		_lod.resume()
		set_physics_process(false)
	_apply_shown()


func mob_wake() -> void:
	if not dormant:
		return
	dormant = false
	_lod.resume()
	set_physics_process(true)
	_apply_shown()
	# Re-apply the presentation band for the distance it woke at.
	_present_band = -1


func assign_territory(shared, ring_slot: int, pack_group: String) -> void:
	_wander.assign(shared, ring_slot, pack_group)

func _update_cosmetics(_delta: float) -> void:
	var actual_velocity := get_real_velocity()
	_wolf.set_motion(Vector2(actual_velocity.x, actual_velocity.z).length())
	_wolf.set_combat(state, _state_time)

func _step_devil(delta: float, pursuit: bool) -> void:
	_state_time += delta
	_dodge.advance(delta,is_on_floor())
	_attack_cooldown = maxf(0.0,_attack_cooldown-delta)
	# Ghost of the Warband: the brain's guard window shares the cooldown clock.
	_warband_guard = maxf(0.0,_warband_guard-delta)
	_decision_timer -= delta
	_leap_cooldown = maxf(0.0,_leap_cooldown-delta)
	_slide_cooldown = maxf(0.0,_slide_cooldown-delta)
	var focus := _senses.focus()
	var to_target := focus-global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var aggro := pursuit and not MobSenses.in_safe_ring(safe_center, focus)
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
			# Calm: keep to the pack's patch. Outside it, hurry home.
			var wander := _wander.step(self)
			if wander.length_squared() > 0.0001:
				_move_intent = _steer_devil(wander)
				_move_speed = 4.6 if _wander.outside(self) else 1.8
				_face_intent = _move_intent
		"STAGGER":
			if _state_time >= _stagger_duration:
				_enter_devil_state("CIRCLE")
		"STEP":
			if distance > 0.001:
				_face_intent = to_target.normalized()
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
				if devil_weapon != "bow" and distance < 2.8 and _attack_cooldown <= 0.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS:
					_devil_begin_windup(_leap_damage)
				else:
					_decision_timer = 0.15
					_enter_devil_state("CIRCLE")
		"DIVE":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			var predicted := _target.global_position+_target.velocity*0.16
			var dive_offset := predicted-global_position
			dive_offset.y = 0.0
			if dive_offset.length_squared() > 0.0001:
				_move_intent = _steer_devil(_devil_with_separation(dive_offset.normalized()))
			_move_speed = 9.2
			if distance < 1.65 or _state_time >= 0.48:
				_devil_begin_windup(_attack_damage)
		"WINDUP":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if _state_time >= DEVIL_WINDUP:
				_enter_devil_state("STRIKE")
		"STRIKE":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if not _struck and _state_time >= 0.080:
				_struck = true
				_devil_strike(distance,to_target)
			if _state_time >= DEVIL_STRIKE:
				_attack_cooldown = 0.75+_rng.randf()*0.70
				_enter_devil_state("RECOVER")
		"SHOOT":
			if distance > 0.001:
				_face_intent = to_target.normalized()
			if not _shot_fired and _state_time >= 0.30:
				_shot_fired = true
				_shoot_arrow()
			if _state_time >= 0.52:
				_attack_cooldown = 0.70+_rng.randf()*0.60
				_enter_devil_state("RECOVER")
		"RECOVER":
			if distance > 0.001:
				var retreat := -to_target.normalized()
				var tangent := Vector3(-to_target.z,0.0,to_target.x).normalized()*_orbit_dir
				_move_intent = _steer_devil((retreat+tangent*0.7).normalized())
				_move_speed = 4.8
				_face_intent = _move_intent
			if _state_time >= DEVIL_RECOVER:
				_enter_devil_state("CIRCLE")
		_:
			if _senses.seen:
				_devil_circle(delta,distance,to_target)
			else:
				_devil_hunt(delta)
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
		velocity.y = 0.0
	elif not was_grounded and not _ground_below_feet():
		# Nothing under the body to land on: it holds the altitude it was placed
		# at instead of sinking out of the world a physics frame per LOD slice.
		velocity.y = 0.0
	elif not was_grounded:
		velocity.y -= 18.0*delta
	var facing := _face_intent
	if facing.length_squared() < 0.0001 or _dodge.active:
		facing = -global_basis.z
	if facing.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-facing.x,-facing.z),minf(delta*12.0,1.0))
	var before := global_position
	# The body steps every frame whatever its brain's budget, so this tick's own
	# step is one physics frame - the frames it sat out already moved it.
	MobLod.move(self)
	var actual := (global_position-before)/maxf(get_physics_process_delta_time(),0.0001)
	if state == "LEAP" and not was_grounded and is_on_floor() and _leap_air_time > 0.18:
		if devil_weapon != "bow" and distance < 2.8 and _attack_cooldown <= 0.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS:
			_devil_begin_windup(_leap_damage)
		else:
			_decision_timer = 0.15
			_enter_devil_state("CIRCLE")
	_devil.set_motion(actual,is_on_floor())
	_devil.set_action(state,_state_time)
	_devil.set_step(_dodge.progress if _dodge.active else -1.0,_dodge.direction)
	_devil.set_slide(_slide_time/DEVIL_SLIDE_SECONDS if state == "SLIDE" else -1.0)

func _devil_circle(delta: float, distance: float, to_player: Vector3) -> void:
	_orbit_angle += _orbit_dir*delta*(1.65+0.40*sin(_orbit_phase+_state_time*0.8))
	var predicted := _target.global_position+_target.velocity*0.10
	var radius := _orbit_radius+sin(_orbit_phase+_state_time*0.7)*0.55
	var ring := predicted+Vector3(cos(_orbit_angle),0.0,sin(_orbit_angle))*radius
	var offset := ring-global_position
	offset.y = 0.0
	var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
	var retreat_at := 7.5 if devil_weapon == "bow" else 2.4
	# Ghost of the Warband: a passive body guards from a wider ring.
	if warband_passive:
		retreat_at = maxf(retreat_at, 3.4)
	var close_at := 13.0 if devil_weapon == "bow" else 9.0
	if distance < retreat_at:
		direction -= to_player.normalized()*1.0
	elif distance > close_at:
		direction += to_player.normalized()*0.8
	_move_intent = _steer_devil(_devil_with_separation(direction))
	_move_speed = 6.8
	# A circling predator keeps its eyes on the quarry; facing the orbit
	# direction would swing the ranger out of the sight cone every lap.
	_face_intent = to_player
	if _decision_timer <= 0.0:
		_decision_timer = 0.38+_rng.randf()*0.35
		_devil_choose(distance,to_player)

## Lost sight but still remembers: run down the last known spot, then scan.
## An enraged devil follows the ranger that hit it instead of the old sighting.
func _devil_hunt(delta: float) -> void:
	var offset := _senses.focus()-global_position
	offset.y = 0.0
	if offset.length() > MobSenses.ARRIVE_DISTANCE:
		_move_intent = _steer_devil(_devil_with_separation(offset.normalized()))
		_move_speed = 5.2
		_face_intent = _move_intent
		return
	rotation.y += sin(_state_time*1.5)*delta*1.7
	_face_intent = -global_basis.z

func _devil_choose(distance: float, to_player: Vector3) -> void:
	if not is_on_floor():
		return
	# Ghost of the Warband: a guarded body commits to no attack - dive, leap or
	# shot - and keeps circling instead.
	if _warband_guard > 0.0:
		return
	var roll := _rng.randf()
	if devil_weapon == "bow":
		if distance < 6.0:
			if _leap_cooldown <= 0.0 and roll < 0.38:
				_devil_start_leap(distance,to_player,true)
			elif _slide_cooldown <= 0.0 and roll < 0.72:
				_devil_start_slide(to_player,true)
			elif _dodge.can_step(true,false):
				_devil_start_step(to_player)
			return
		if _attack_cooldown <= 0.0 and distance <= 16.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS and _devil_has_los():
			_enter_devil_state("SHOOT")
			return
		if roll < 0.22 and _dodge.can_step(true,false):
			_devil_start_step(to_player)
		return
	if _attack_cooldown <= 0.0 and distance < 8.0 and _pack_attackers() < DEVIL_MAX_ATTACKERS:
		_enter_devil_state("DIVE")
		return
	if _leap_cooldown <= 0.0 and roll < 0.32:
		_devil_start_leap(distance,to_player)
		return
	if roll < 0.64 and _dodge.can_step(true,false):
		_devil_start_step(to_player)
		return
	if _slide_cooldown <= 0.0 and distance > 2.3 and roll < 0.82:
		_devil_start_slide(to_player)

func _devil_start_step(to_player: Vector3) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var forward_bias := -0.30 if devil_weapon == "bow" else 0.22
	var direction := (tangent*side*0.9+to_player.normalized()*forward_bias).normalized()
	if _dodge.try_step(direction,is_on_floor(),false):
		_enter_devil_state("STEP")
		_face_intent = to_player.normalized()

func _devil_start_leap(distance: float, to_player: Vector3, retreat: bool = false) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
	var forward := to_player.normalized()
	var direction := (forward*0.55+tangent*0.85).normalized()
	if retreat:
		direction = (-forward*0.65+tangent*0.85).normalized()
	elif distance > 4.5:
		direction = (forward*0.80+tangent*0.50).normalized()
	_leap_direction = _steer_devil(direction)
	_leap_air_time = 0.0
	_leap_cooldown = 1.05+_rng.randf()*0.40
	_enter_devil_state("LEAP")
	velocity.y = 6.5

func _devil_start_slide(to_player: Vector3, retreat: bool = false) -> void:
	if to_player.length_squared() < 0.0001:
		return
	var tangent := Vector3(-to_player.z,0.0,to_player.x).normalized()*_orbit_dir
	var forward := to_player.normalized()
	var direction := (tangent*0.9+forward*0.35).normalized()
	if retreat:
		direction = (-forward*0.70+tangent*0.85).normalized()
	_slide_direction = _steer_devil(direction)
	_slide_time = 0.0
	_slide_speed = 9.6
	_slide_cooldown = 1.2+_rng.randf()*0.5
	_enter_devil_state("SLIDE")

func _devil_begin_windup(damage: float) -> void:
	_attack_damage = damage
	_struck = false
	_enter_devil_state("WINDUP")
	var to_target := _target.global_position-global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		_face_intent = to_target.normalized()

func _enter_devil_state(next: String) -> void:
	state = next
	_state_time = 0.0
	_shot_fired = false
	_warning.visible = next == "WINDUP"
	if next == "WINDUP":
		# Same reading as the wolf's: the noise goes with the telegraph, not with
		# the swing, so the windup can be answered with the eyes shut.
		_voice.say("attack")
	if next == "STRIKE":
		# The cinder devil's committed swing. `Sfx` reads what it carries, so a
		# short blade draws the short arc and a two-handed piece the long one.
		SfxScript.swing(self, global_position + Vector3.UP * 1.2)

func _devil_strike(distance: float, to_player: Vector3) -> void:
	if distance > _attack_reach or absf(_target.global_position.y-global_position.y) > 1.25:
		return
	if to_player.length_squared() > 0.0001 and (-global_basis.z).dot(to_player.normalized()) < 0.15:
		return
	_query.from = global_position+Vector3(0,0.5,0)
	_query.to = _target.global_position+Vector3(0,0.7,0)
	if not get_world_3d().direct_space_state.intersect_ray(_query).is_empty():
		return
	attacked.emit(self,_attack_damage,_target)

func _shoot_arrow() -> void:
	if not is_instance_valid(_target) or get_parent() == null:
		return
	var origin: Vector3 = _devil.get_bow_origin()
	var target := _target.global_position+Vector3(0,1.0,0)+_target.velocity*0.12
	var flight := origin.distance_to(target)/30.0
	target.y += 0.5*4.0*flight*flight
	var direction := (target-origin).normalized()
	var arrow := Arrow.new()
	# Layer 8 is the shield: a raised or carried shield intercepts the shaft
	# before it reaches the body behind it.
	arrow.hit_mask = 1 | 4 | 8
	get_parent().add_child(arrow)
	arrow.launch(origin,direction,30.0,_attack_damage,[get_rid()],origin)
	arrow_fired.emit(origin,direction,30.0,_attack_damage)
	shots_fired += 1

func _devil_has_los() -> bool:
	if not is_instance_valid(_target):
		return false
	_query.from = global_position+Vector3(0,0.55,0)
	_query.to = _target.global_position+Vector3(0,0.85,0)
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()

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
		if str(other.get("state")) in ["WINDUP","STRIKE","DIVE","SHOOT"]:
			count += 1
	return count

func _steer_devil(direction: Vector3) -> Vector3:
	return _steering.steer(self, direction, 0.45)

func _steer(direction: Vector3) -> Vector3:
	return _steering.steer(self, direction, 0.65)

func stagger(seconds: float) -> void:
	if not alive:
		return
	mob_wake()
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


## Ghost of the Warband: the far-fight stance switch used by `PassiveDuelBrain`.
## Dropping the stance drops the guard, so a body entering a bubble fights at once.
func warband_stance(passive: bool) -> void:
	warband_passive = passive
	if not passive:
		_warband_guard = 0.0


## Ghost of the Warband: hold the attack gate shut for `seconds`; the newest
## order wins, so `warband_guard(0.0)` is how the brain opens a swing window.
func warband_guard(seconds: float) -> void:
	_warband_guard = maxf(0.0, seconds)

## The killing blow's style/angle force, recorded by the damage source. It is
## only read at death; a miss does not matter.
func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	# A headshot is only worth a head, and a chop only worth a split, if this is
	# the blow that named it.
	var flight := _head_shot
	_head_shot = Vector3.ZERO
	var chop := _cleave
	_cleave = Vector3.ZERO
	# Being hit is not something a parked body can miss: it wakes and turns.
	mob_wake()
	last_hitter = source_id
	var applied := amount * Hitbox.damage_multiplier(headshot)
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	# Every mob bleeds: the wolf and the cinder devil both carry blood in this
	# world, so a landed hit always reads on the body and on the floor.
	BloodFx.wound(self,blood_rig(),get_aim_position(),applied,headshot,
		health <= 0.0,blood_scale())
	if health <= 0.0:
		_sever = flight
		_enter_dead(true, applied, chop)
		return
	_respond_to_attack()


## An arrow that lands on the head names its flight here before its blow, so a
## killing shot can throw the head off with the shaft still in it.
func note_arrow_headshot(velocity: Vector3, _amount: float) -> void:
	if alive:
		_head_shot = velocity


## A two-handed overhead names its shove here before its blow: the chop that
## kills this body takes it in two (`SeveredBody`).
func note_cleave(force: Vector3, kind: String = "horizontal") -> void:
	if alive:
		_cleave = force
		_cleave_kind = kind


## The projectile, blade or spell that landed names itself here before it
## applies damage, so the mob can turn on an archer it never saw.
func note_attacker(attacker: Node3D) -> void:
	_attacker = attacker


## A landed blow always starts the fight, and the cry pulls the neighbours in.
func _respond_to_attack() -> void:
	var attacker: Node3D = _attacker if is_instance_valid(_attacker) else null
	_attacker = null
	if attacker != null and not _is_hostile(attacker):
		return
	if attacker == null:
		var nearest := _resolve_target()
		if not is_instance_valid(nearest) or not _is_hostile(nearest):
			return
		attacker = nearest
	_senses.notice(attacker,attacker.global_position)
	MobSenses.alert_pack(self,attacker,_senses.last_seen)
	MobSenses.alert_packmates(self,attacker,_senses.last_seen,_wander.group)


## A neighbour was struck within earshot: take up the hunt where it last saw.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	if not alive or replica:
		return
	if is_instance_valid(attacker) and not _is_hostile(attacker):
		return
	# A pack answers its own cry: the hunt is the gameplay, so the body comes
	# back for it and parks again when the pursuit clock runs out.
	mob_wake()
	_senses.hear(attacker,at)

## Feeds one authoritative pose into the render buffer. The first packet and
## any teleport restart the buffer; everything else interpolates.
func _ingest_pose(state: Dictionary, tick: int) -> void:
	var point: Vector3 = state.p
	var yaw := float(state.y)
	var speed: Vector3 = state.v
	var at := tick if tick >= 0 else _timeline.newest_tick() + 1
	var now := Time.get_ticks_msec()/1000.0
	if not _received_pose:
		_timeline.reset_to(point,speed,yaw,at,now)
		global_position = point
		rotation.y = yaw
		_received_pose = true
		return
	_timeline.push(at,point,speed,yaw,now)
	rotation.y = _timeline.sample().yaw


func _process(delta: float) -> void:
	Perf.begin("wolf.process")
	_replay_tick(delta)
	Perf.end()


func _replay_tick(delta: float) -> void:
	# Every machine that draws this body runs its voice clock, because the cues a
	# replica makes off a snapshot are as local as the ones the authority makes.
	if _voice != null:
		_voice.tick(delta)
	if not replica or not alive or not _received_pose:
		return
	if not stale and _state_at > 0.0 \
			and Time.get_ticks_msec() / 1000.0 - _state_at > STALE_SECONDS:
		stale = true
		collision_layer = 0
		_apply_shown()
	_timeline.advance(delta)
	var sample: Dictionary = _timeline.sample()
	global_position = sample.pos
	rotation.y = sample.yaw


## One place decides whether the body is drawn, so no path can talk over another:
## parked by the culler (`dormant`), quiet for too long (`stale`), and a replica
## the host has never named or has stopped streaming to this peer (no pose), are
## three reasons for the same treatment.
func _apply_shown() -> void:
	var unseen := replica and not _received_pose
	visible = not (dormant or stale or unseen)


## Take the replica switch from the session, the way `devil_mob` does: a guest
## builds its own copy of the wood, and one the host may not have at all - killed
## before the join, or a body only the host fields - is neither drawn nor solid
## until the wire proves it exists here.
func mark_replica() -> void:
	replica = true
	_apply_shown()


## The host has stopped naming this body to this peer: it walked out of that
## player's reach. The copy is put down here and kept down until the host names it
## again; the state that brings it back is a reset, not an interpolation from
## wherever it stood when it left. Waiting for `STALE_SECONDS` instead left a mob
## frozen in place for a second first.
func set_streamed(value: bool, tick: int = -1) -> void:
	if value:
		return
	_stream_left = maxi(_stream_left, tick)
	_received_pose = false
	stale = false
	collision_layer = 0
	_timeline.clear()
	_apply_shown()


## The local death: combat collision off, gravity on, the limp collapse, then
## the shared hold. Replicas call it with `announce = false` so the kill stays
## on the host.
func _enter_dead(announce: bool, damage := 0.0, cleaved := Vector3.ZERO) -> void:
	alive = false
	state = "DEAD"
	_split = cleaved
	_warning.visible = false
	var fall := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	# Layer 0 stops the corpse blocking bodies and arrows; mask 1 lets the dead
	# root keep falling onto the world if the mob died mid-leap.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	velocity = Vector3.ZERO
	if kind == 2 and is_instance_valid(_devil):
		# The dropped pickup owns the weapon now; keep it out of the corpse.
		_devil.set_weapon("claw")
	# The death cry is presentation, so every machine that runs this body hears
	# it: the authority because it killed it, a replica because the snapshot has
	# just told it the body is gone. `alive` is already false, so it happens once.
	_voice.say("death")
	if announce:
		defeated.emit(self, 8 if kind == 0 else 6)
		# The body that landed the last blow says something about it, if it feels
		# like it. Only the authority knows a killer's `last_hitter` id, so only
		# it asks.
		VoiceScript.kill_quip(last_hitter)
	# Collapse first, then hold the corpse for the shared five minutes.
	var death_tween := create_tween()
	if kind == 0:
		# A head an arrow took off leaves before the ragdoll is built from the
		# lethal pose, so the stump the corpse keeps is the one its bones read.
		if _sever != Vector3.ZERO:
			SeveredHead.sever(_wolf, _sever, maxf(damage, 12.0))
		elif cleaved != Vector3.ZERO:
			SeveredBody.split(_wolf, cleaved, maxf(damage, 30.0), _cleave_kind)
		# The wolf's imported skeleton ragdolls limp from its current pose.
		_wolf.die(fall)
		death_tween.tween_interval(0.45)
		CorpseHold.append(death_tween, self, _body)
	else:
		if _sever != Vector3.ZERO:
			SeveredHead.sever(_devil, _sever, maxf(damage, 12.0))
		elif cleaved != Vector3.ZERO:
			SeveredBody.split(_devil, cleaved, maxf(damage, 30.0), _cleave_kind)
		# The imported cinder's skeleton ragdolls from its lethal pose.
		_devil.die(fall)
		death_tween.tween_interval(0.90)
		CorpseHold.append(death_tween, self, _body)

## The death cause the wire carries: w = 1 a head (xyz the arrow's flight),
## w = 2 a body opened across, w = 3 one sliced in half (xyz the chop's shove).
func _death_cause() -> Vector4:
	if _sever != Vector3.ZERO:
		return Vector4(_sever.x, _sever.y, _sever.z, 1.0)
	if _split != Vector3.ZERO:
		return Vector4(_split.x, _split.y, _split.z,
			3.0 if _cleave_kind == "vertical" else 2.0)
	return Vector4.ZERO


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
		# The death that took a piece: w = 1 is a head (xyz the arrow's flight),
		# w = 2 a body opened across, w = 3 one sliced in half (xyz the chop's shove).
		"k": _death_cause(),
		"x": _packed_pose(),
	}

func _packed_pose() -> Vector4:
	if kind != 2:
		return Vector4.ZERO
	if state == "STEP":
		return Vector4(_dodge.progress if _dodge.active else -1.0,
			_dodge.direction.x,_dodge.direction.z,-1.0)
	if state == "SLIDE":
		return Vector4(_dodge.progress if _dodge.active else -1.0,
			_slide_direction.x,_slide_direction.z,
			clampf(_slide_time/DEVIL_SLIDE_SECONDS,0.0,1.0))
	return Vector4(-1,0,0,-1)

## Presentation-side mirror of the host's mob: the host owns AI, damage and
## arrows, so a replica only replays the snapshot it was handed.
func apply_snapshot(state: Dictionary, tick: int = -1) -> void:
	if tick >= 0 and tick <= _stream_left:
		# A state from before the host stopped naming this copy: a datagram still
		# in flight, not news. It must not put a body back on the screen.
		return
	var previous_health := health
	var was_alive := alive
	var previous_state := self.state
	var had_pose := _received_pose
	_ingest_pose(state,tick)
	self.state = state.s
	_state_time = state.t
	health = state.h
	alive = state.a
	velocity = state.v
	_state_at = Time.get_ticks_msec() / 1000.0
	if stale or not had_pose:
		stale = false
		collision_layer = 2 if alive else 0
	_apply_shown()
	var grounded: bool = state.g
	var pose: Vector4 = state.x
	_warning.visible = self.state == "WINDUP"
	# A replica commits its bite on the host, so the growl is read off the state
	# change the wire carries: the same rule as the authority's, one snapshot
	# late. The death cry is the `_enter_dead` below.
	if previous_state != "WINDUP" and self.state == "WINDUP":
		_voice.say("attack")
	if kind == 0:
		_wolf.set_motion(Vector2(velocity.x,velocity.z).length())
		_wolf.set_combat(self.state,_state_time)
	else:
		_devil.set_motion(velocity,grounded)
		_devil.set_action(self.state,_state_time)
		_devil.set_step(pose.x,Vector3(pose.y,0.0,pose.z))
		_devil.set_slide(pose.w)
	if health < previous_health:
		var applied: float = previous_health - health
		DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",false,health <= 0.0)
		BloodFx.wound(self,blood_rig(),get_aim_position(),applied,false,
			health <= 0.0,blood_scale())
	if was_alive and not alive:
		var cause: Vector4 = state.get("k", Vector4.ZERO)
		_sever = Vector3(cause.x, cause.y, cause.z) \
			if cause.w > 0.5 and cause.w < 1.5 else Vector3.ZERO
		var chop := Vector3(cause.x, cause.y, cause.z) if cause.w > 1.5 \
			else Vector3.ZERO
		_cleave_kind = "vertical" if cause.w > 2.5 else "horizontal"
		_enter_dead(false, 0.0, chop)

