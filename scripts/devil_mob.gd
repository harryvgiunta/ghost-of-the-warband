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
const NetReplication = preload("res://scripts/net_replication.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const MobSteering = preload("res://scripts/mob_steering.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const MobLod = preload("res://scripts/mob_lod.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const VoiceScript = preload("res://scripts/audio/voice.gd")
const VoiceEmitterScript = preload("res://scripts/audio/voice_emitter.gd")

## Per-mob gameplay profiles. Health, damage, reach, speed and cadence are
## deliberately close to the existing Cinder devil pack so the new mobs remain
## additions, not a difficulty spike. `kind` keeps the deterministic frontier
## loot rotation distinct from kinds 0..2.
const PROFILES := {
	"hell_goat": {
		"display": "Hellish goat man", "kind": 3,
		"health": 72.0, "damage": 13.0, "reach": 2.05,
		"walk_speed": 1.50, "run_speed": 4.00, "orbit": 5.5,
		"sight": 30.0, "gold": 10,
		"radius": 0.45, "height": 2.00, "aim": 1.65,
		"windup": 0.45, "strike": 0.18, "recover": 0.55,
		"cooldown": 1.35, "lunge": 6.2, "turn": 9.0,
		"behaviour": "charger", "strafe": 0.9, "blood": 1.05,
		"packed": true, "roam": 6.0,
	},
	"succubus": {
		"display": "Succubus", "kind": 4,
		"health": 46.0, "damage": 9.0, "reach": 1.85,
		"walk_speed": 1.40, "run_speed": 4.20, "orbit": 6.5,
		"sight": 28.0, "gold": 9,
		"radius": 0.32, "height": 2.05, "aim": 1.50,
		"windup": 0.36, "strike": 0.15, "recover": 0.45,
		"cooldown": 1.15, "lunge": 7.0, "turn": 10.0,
		"behaviour": "flyer", "strafe": 1.10, "blood": 0.95,
		"packed": true, "roam": 7.0,
	},
	"spawn": {
		"display": "Devil spawn", "kind": 5,
		"health": 22.0, "damage": 6.0, "reach": 1.45,
		"walk_speed": 1.30, "run_speed": 4.60, "orbit": 4.0,
		"sight": 26.0, "gold": 5,
		"radius": 0.30, "height": 1.05, "aim": 0.75,
		"windup": 0.30, "strike": 0.14, "recover": 0.40,
		"cooldown": 0.90, "lunge": 8.0, "turn": 12.0,
		"behaviour": "crawler", "strafe": 1.50, "blood": 0.55,
		"packed": true, "roam": 5.0,
	},
	"beast": {
		"display": "Hell beast", "kind": 6,
		"health": 130.0, "damage": 20.0, "reach": 2.50,
		"walk_speed": 1.40, "run_speed": 3.80, "orbit": 4.0,
		"sight": 26.0, "gold": 16,
		"radius": 0.55, "height": 1.65, "aim": 1.15,
		"windup": 0.65, "strike": 0.22, "recover": 0.70,
		"cooldown": 2.00, "lunge": 5.5, "turn": 5.5,
		"behaviour": "brute", "strafe": 0.2, "blood": 1.35,
		"packed": true, "roam": 8.0,
	},
	"gargoyle": {
		"display": "Gargoyle", "kind": 7,
		"health": 110.0, "damage": 17.0, "reach": 3.30,
		"walk_speed": 1.00, "run_speed": 2.80, "orbit": 4.8,
		"sight": 18.0, "gold": 14,
		"radius": 0.70, "height": 3.05, "aim": 2.35,
		"windup": 0.75, "strike": 0.24, "recover": 0.85,
		"cooldown": 2.20, "lunge": 3.2, "turn": 4.5,
		"behaviour": "sentinel", "strafe": 0.0, "blood": 1.20,
		"packed": false, "roam": 4.0,
	},
}

var mob_id := "hell_goat"
var profile: Dictionary = {}
var kind := 3
var player: CharacterBody3D
var targets: Array[CharacterBody3D] = []
var replica := false
## Buffered server states for the replica's delayed render (see `enemy.gd`).
var _timeline = NetReplication.mob_timeline()
var _received_pose := false
var safe_center := Vector3.ZERO
var home := Vector3.ZERO
var health := 50.0
var max_health := 50.0
## Slot of the ranger whose damage landed last (see `enemy.gd.last_hitter`).
var last_hitter := -1
var alive := true
var _impact_force := Vector3.ZERO
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
## The noise this body makes: a cry going into the swing, one going down.
var _voice: VoiceEmitter
var _rng := RandomNumberGenerator.new()
var _target: CharacterBody3D
var _senses := MobSenses.new()
var _steering := MobSteering.new()
## The patch this body keeps to when it is calm: its own, or the pack's.
var _wander := MobWander.new()
## Tick budget: the further from the nearest ranger, the rarer the tick.
var _lod := MobLod.new()
## Presentation band last applied (0 shadowed, 1 animate-only, 2 resting).
var _present_band := -1
## Parked by `MobCuller`: no tick, no draw, no state change while it is true.
var dormant := false
var _attacker: Node3D
## Ghost of the Warband: the far-fight stance - `PassiveDuelBrain` widens the
## ring and shuts the attack gate between the few blows a far body is allowed.
var warband_passive := false
var _warband_guard := 0.0
## A guarding body refuses to trade and takes a quarter off every blow it eats
## while the guard is up. The mob raises it itself between its own swings, so a
## fight is a conversation of openings rather than two blades passing through each
## other.
const GUARD_REDUCTION := 0.35
const GUARD_HOLD := 0.35
## Opt-in, and only the warband's cultists opt in: the frontier's mobs keep the
## fight they were tuned for.
var guard_between_swings := false
## Seconds left on a rolled guard window (`brace`). A braced body refuses to
## trade: it holds its guard instead of swinging, and drops out of it into the
## swing when the window closes. The cultists brace on their own clock; the
## camp's watchers roll for it once an exchange.
var _braced := 0.0


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
	# World and ranger bodies only. Mob-against-mob collision made every swept
	# move test seventy-four other capsules; the soft separation pass already
	# keeps a pack apart, so the physics query stays about the terrain.
	collision_mask = 1 | 4
	# One slide per move. A body on uneven ground reports three contacts and the
	# solver used to resolve each of them (~118 us a move instead of ~49 us);
	# the steering below already picks a lane around obstacles, so one resolve
	# is enough and the next tick continues along it.
	max_slides = 2
	# A body on a slope must keep its horizontal motion: the default stop
	# cancels it the moment the ground tilts, which read as crawling.
	floor_stop_on_slope = false
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
	# One shared group for every wilderness mob: a struck mob's cry reaches
	# whatever is close enough to hear it.
	add_to_group(MobSenses.GROUP)
	_rng.seed = 7919 + int(absf(global_position.x) * 13.0) + int(absf(global_position.z) * 7.0)
	_strafe_dir = 1.0 if (_rng.randi() & 1) == 0 else -1.0
	# A pack that meets the same barrier splits around both of its sides.
	_steering.bias = _strafe_dir
	_lod = MobLod.new(int(absf(global_position.x) * 7.0 + absf(global_position.z) * 13.0))
	_attack_cooldown = _rng.randf_range(0.25, 0.85)
	state = "IDLE"
	_state_time = 0.0
	# The voice is named by the profile, so a hollow warden and a gallowsroot look
	# their takes up in their own folders without this file knowing either one.
	_voice = VoiceEmitterScript.create(voice_id(), self, false, 2711 + int(absf(global_position.x)))


## The voice this body speaks with: the profile id, which is also the folder of
## its takes. A mobset with no recordings answers an empty voice - silence, not
## an error.
func voice_id() -> String:
	return mob_id


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
	if dormant or replica:
		return
	if not alive:
		CorpsePhysics.settle_root(self, delta)
		return
	var nearest := _nearest_ranger()
	_cull_presentation(nearest)
	var budget := _lod.slice(nearest, delta, not _senses.aggressive())
	if budget <= 0.0:
		return
	delta = budget
	# Sight, not proximity, decides whether this mob is in a fight. Losing the
	# view keeps the pursuit alive for `MEMORY_SECONDS`. Nothing further away
	# than its sight range can be seen, so that tick skips the sight rays.
	var pursuit := false
	if nearest <= _sight_range():
		pursuit = _senses.step(self, _candidates(), delta, _sight_range(),
			_eye_height(), Callable(self, "_is_hostile"))
	else:
		_senses.age(delta)
		pursuit = _senses.aggressive()
	if _senses.woke:
		# The first sighting of a pack's member is the pack's sighting.
		MobSenses.alert_packmates(self, _senses.target, _senses.last_seen, _wander.group)
	_target = _senses.target if is_instance_valid(_senses.target) else _resolve_target()
	if not is_instance_valid(_target) and not pursuit:
		_calm_tick(delta)
		return
	_state_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	# Ghost of the Warband: the brain's guard window rides the cooldown clock.
	_warband_guard = maxf(0.0, _warband_guard - delta)
	_braced = maxf(0.0, _braced - delta)
	# Between its own swings a cultist is not wide open: it keeps its guard up
	# while it re-arms. That is what makes a swing an opening instead of a rhythm.
	# It is braced for most of its cycle and opens for the half second before it
	# can swing again: a cultist is something you catch off its guard, not something
	# you out-trade, and that is what makes the fight last.
	if guard_between_swings and _attack_cooldown > 0.30:
		_warband_guard = maxf(_warband_guard, GUARD_HOLD)
	var focus := _senses.focus() if pursuit else _target.global_position
	var to_target := focus - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector3.FORWARD
	# Town peace: a ranger inside the safe ring is never hunted, alerted or not.
	var aggro := pursuit and _aggro_allowed(focus)
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	# Only an aware mob turns toward its quarry. A calm mob keeps the facing it
	# had, so walking up behind it stays possible.
	_face_intent = Vector3.ZERO
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
			if _state_time >= _windup_seconds():
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
				_attack_cooldown = _cooldown_seconds()
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
	_visual.set_poise(_present_blocking(), _present_crouch())


## Distance to the closest ranger, for the tick budget. Walks the two slots
## `_candidates()` would build, without building it.
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


## Far bodies stop evaluating animation tracks and locomotion presentation; the
## skeleton keeps its last pose, which at that distance is a few pixels.
func _cull_presentation(nearest: float) -> void:
	var band := MobLod.band(nearest)
	if band == _present_band:
		return
	_present_band = band
	if is_instance_valid(_visual) and _visual.has_method("set_distance"):
		_visual.set_distance(nearest)


## The culler's only call into a parked body: one distance check per sweep.
## Sight rays, steering, the state machine, the swept move and the skinning are
## all behind the physics process `mob_sleep` turns off.
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


## Nothing in sight and nothing remembered: keep the patch alive. This is the
## tick that used to freeze a calm mob - with no target the whole state machine
## was skipped, so a body that spawned at rest never moved again.
func _calm_tick(delta: float) -> void:
	if profile.is_empty():
		# `_ready` refuses an unknown mob id; never tick a body without a profile.
		return
	_state_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	# The guard window is a beat in an exchange, not a state: it runs out even
	# when there is nothing left to fight.
	_braced = maxf(0.0, _braced - delta)
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	_face_intent = Vector3.ZERO
	_return_home(delta)
	if _present_band > 1:
		# Nothing at this distance can see the pose: skip the cluster pass and
		# the locomotion presentation entirely.
		_move_intent = _move_intent.normalized() if _move_speed > 0.0 else Vector3.ZERO
		_drive(delta)
		return
	_separate()
	_drive(delta)
	if is_instance_valid(_visual):
		_visual.set_motion(get_real_velocity(), is_on_floor())
		_visual.set_combat(state, _state_time)
		_visual.set_poise(_present_blocking(), _present_crouch())


func _enter(next_state: String, reset_time := true) -> void:
	state = next_state
	if reset_time:
		_state_time = 0.0
	if next_state == "WINDUP":
		# The windup is the only warning a body gives, so the noise belongs to it
		# rather than to the blow: a player facing away is told anyway.
		_voice.say("attack")
	if next_state == "STRIKE":
		# The committed swing, heard from the body's own hand. `Sfx` reads the
		# piece the mob carries, so a watcher's club whooshes and a two-handed
		# piece draws the long arc.
		SfxScript.swing(self, blood_strike_point())


## Seconds from the swing being chosen to the blade coming down. The profile owns
## the number; a body that is a lesson rather than a fight stretches it (the cage
## watcher's `windup_scale`), because the telegraph is the only thing a new player
## can answer.
func _windup_seconds() -> float:
	return float(profile.get("windup", 0.45))


## Calm: the mob keeps its patch. It walks to the territory's current goal at
## its own walk speed, rests when it arrives, and hurries home if a chase left
## it outside.
func _return_home(_delta: float) -> void:
	var direction := _wander.step(self)
	var outside := _wander.outside(self)
	if direction.length_squared() > 0.0001:
		_move_intent = _steer(direction)
		_move_speed = float(profile.walk_speed) * (2.2 if outside else 1.0)
		_face_intent = _move_intent
		if state != ("RETURN" if outside else "IDLE"):
			_enter("RETURN" if outside else "IDLE", false)
		return
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	if state != "IDLE":
		_enter("IDLE", false)


func _circle(delta: float, distance: float, direction: Vector3) -> void:
	# Sight is gone but the pursuit memory is not: hunt the last known spot.
	if not _senses.seen:
		_hunt(delta)
		return
	var reach := float(profile.reach)
	# Ghost of the Warband: a guarded body refuses to trade (the brain's window,
	# or a rolled one the body itself braced into).
	if distance <= reach + 1.15 and _attack_cooldown <= 0.0 and not guard_up():
		_choose_attack()
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
	var closing := _attack_cooldown <= 0.0 and not (warband_passive and _warband_guard > 0.0)
	var radius := maxf(1.1, reach * 0.82) if closing else orbit
	# Ghost of the Warband: with the gate shut the body holds a ring just outside
	# its own swing gate, so a far duel reads as a measured circle-and-guard.
	if warband_passive and not closing:
		radius = reach + 1.4
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
	# Ghost of the Warband: a passive body circles at a walk, never a sprint.
	if warband_passive:
		_move_speed = float(profile.walk_speed)
	_face_intent = direction


## Lost sight but still remembers: run down the place the ranger was last
## seen, then sweep the ground while the pursuit timer runs out. A ranger that
## landed a blow is followed live instead - it knows where its attacker is.
func _hunt(delta: float) -> void:
	var focus := _senses.focus()
	var offset := focus - global_position
	offset.y = 0.0
	if offset.length() > MobSenses.ARRIVE_DISTANCE:
		_move_intent = _steer(offset.normalized())
		_move_speed = float(profile.run_speed)
		_face_intent = _move_intent
		return
	if _senses.hunt > 0.0 and is_instance_valid(_senses.target):
		# Enraged and standing on the quarry: keep pressing until it is seen.
		_move_intent = _steer((_senses.target.global_position - global_position).normalized())
		_move_speed = float(profile.run_speed)
		_face_intent = _move_intent
		return
	# Standing over the last sighting: scan the ground instead of freezing.
	rotation.y += sin(_state_time * 1.5) * delta * 1.7
	_face_intent = -global_basis.z


func _resolve_strike() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var spent := _state_time / maxf(0.01, float(profile.strike))
	var reach := float(profile.reach) * (1.0 + 0.18 * spent)
	if to_target.length() <= reach and absf(_target.global_position.y - global_position.y) < 2.4:
		attacked.emit(self, _strike_damage(), _target)

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


## How far this profile can see. Distance alone never starts a fight.
func _sight_range() -> float:
	return float(profile.get("sight", 0.0))


## Whether this species moves as a band. A sentinel on its post does not.
func wanders_packed() -> bool:
	return bool(profile.get("packed", true))


## How far a calm body strays from where it spawned.
func wander_radius() -> float:
	return float(profile.get("roam", 7.0))


## A band is one species: the court's five species stand together but never
## merge into a single pack.
func pack_family() -> String:
	return mob_id


## Called by the world once every mob is placed: pack members share one patch.
func assign_territory(shared, ring_slot: int, pack_group: String) -> void:
	_wander.assign(shared, ring_slot, pack_group)


func _eye_height() -> float:
	return maxf(0.7, float(profile.get("height", 1.8)) * MobSenses.EYE_HEIGHT_FRACTION)


## Huntable rangers: alive and outside the town's safe ring.
func _is_hostile(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or candidate.get("alive") == false:
		return false
	return not MobSenses.in_safe_ring(safe_center, candidate.global_position)


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
		# Zero, not a press: floor snapping keeps the body attached, and a
		# downward velocity spent a slide of the sweep (half the ground covered).
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= 18.0 * delta
	if _face_intent.length_squared() > 0.0001 and state != "STAGGER":
		rotation.y = lerp_angle(rotation.y, atan2(-_face_intent.x, -_face_intent.z),
			minf(delta * float(profile.turn), 1.0))
	MobLod.move(self, delta)


func _steer(direction: Vector3) -> Vector3:
	return _steering.steer(self, direction, float(profile.height) * 0.45)


func stagger(seconds: float) -> void:
	if not alive:
		return
	mob_wake()
	state = "STAGGER"
	_state_time = 0.0
	_stagger_duration = maxf(0.0, seconds)
	_struck = true
	velocity.x = 0.0
	velocity.z = 0.0


## Ghost of the Warband: the far-fight stance switch used by `PassiveDuelBrain`.
## Leaving the stance drops the guard, so a body entering a bubble fights at once.
func warband_stance(passive: bool) -> void:
	warband_passive = passive
	if not passive:
		_warband_guard = 0.0


## Open this body's own guard window for `seconds`: it holds the guard instead of
## swinging, and the next completed cooldown drops straight into the swing. The
## cultists' clock is `warband_guard`; this is the same gate a body can roll for
## itself, which is how the camp's watchers block sometimes and never always.
func brace(seconds: float) -> void:
	_braced = maxf(_braced, seconds)


## A raised guard: the body refuses to trade. Whoever owns the window - the
## brain's clock or the body's own roll - the swing gate reads this one answer.
func guard_up() -> bool:
	if _braced > 0.0:
		return true
	return guard_between_swings and _warband_guard > 0.0


## Ghost of the Warband: hold the attack gate shut for `seconds`; the newest
## order wins, so `warband_guard(0.0)` is how the brain opens a swing window.
func warband_guard(seconds: float) -> void:
	_warband_guard = maxf(0.0, seconds)


# --- identity hooks --------------------------------------------------------

## The swing the windup that is starting will play. A body with one attack says
## nothing; a body with several names one and the sampler plays it.
func _choose_attack() -> void:
	pass


## What one landed strike takes off. A body whose arm matters more than its
## profile says so here instead of after the blow has been emitted.
func _strike_damage() -> float:
	return float(profile.damage)


## The beat between two swings. A scene may own this as a dial - a body that
## swings too often is not the same fight as one that does not.
func _cooldown_seconds() -> float:
	return float(profile.cooldown)


## Whether a body at `focus` may be fought: the town's safe ring shuts every
## fight down, however the pursuit started.
func _aggro_allowed(focus: Vector3) -> bool:
	return not MobSenses.in_safe_ring(safe_center, focus)


## What the body is holding up, for the sampler. The devils neither brace nor
## crouch; a body that does answers here.
func _present_blocking() -> bool:
	return false


func _present_crouch() -> bool:
	return false


func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
	if not alive:
		return
	# Ghost of the Warband: the far fight runs at 10% (`WarbandDamage`).
	amount = WarbandDamage.scale(amount, self)
	# Being hit is not something a parked body can miss: it wakes and turns.
	mob_wake()
	last_hitter = source_id
	var applied := amount * Hitbox.damage_multiplier(headshot)
	# A raised guard turns most of the blow: you have to catch the cultist with
	# its blade down (its strike, or the moment its guard breaks on a stagger).
	if guard_between_swings and _warband_guard > 0.0:
		applied *= GUARD_REDUCTION
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(), get_aim_position(), applied, "hit", headshot, health <= 0.0)
	BloodFx.wound(self, blood_rig(), get_aim_position(), applied, headshot,
		health <= 0.0, blood_scale())
	if health <= 0.0:
		_enter_dead(true)
		return
	_respond_to_attack()


## The projectile, blade or spell that landed names itself here before it
## applies damage, so this mob knows who to turn on even when the blow came
## out of the dark.
func note_attacker(attacker: Node3D) -> void:
	_attacker = attacker


## Any landed blow gives the mob the fight, and the cry pulls the neighbours
## inside `MobSenses.SHOUT_RADIUS` into the same hunt.
func _respond_to_attack() -> void:
	var attacker: Node3D = _attacker if is_instance_valid(_attacker) else null
	_attacker = null
	if attacker != null and not _is_hostile(attacker):
		return
	if attacker == null:
		# Unattributed damage (no shooter named): the nearest ranger will do.
		var nearest := _resolve_target()
		if not is_instance_valid(nearest) or not _is_hostile(nearest):
			return
		attacker = nearest
	_senses.notice(attacker, attacker.global_position)
	MobSenses.alert_pack(self, attacker, _senses.last_seen)
	MobSenses.alert_packmates(self, attacker, _senses.last_seen, _wander.group)


## A neighbour was struck within earshot: take up the hunt where it last saw.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	if not alive or replica:
		return
	if is_instance_valid(attacker) and not _is_hostile(attacker):
		return
	# A pack answers its own cry: the hunt is the gameplay, so the body comes
	# back for it and parks again when the pursuit clock runs out.
	mob_wake()
	_senses.hear(attacker, at)


## The local death: stopped combat collision, falling root, the limp ragdoll
## and the shared hold. Replicas call it with `announce = false` so gold and the
## kill stay on the host.
func _enter_dead(announce: bool) -> void:
	alive = false
	state = "DEAD"
	_struck = true
	var fall := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	velocity = Vector3.ZERO
	if is_instance_valid(_visual):
		_visual.die(fall)
	# Presentation, so every machine that runs this body hears it: the authority
	# because it killed it, a replica because the snapshot just said so. `alive`
	# is already false, so this cannot fire twice.
	_voice.say("death")
	if announce:
		defeated.emit(self, int(profile.gold))
		# Only the authority resolves a killer's `last_hitter` id, so only it
		# asks the killer for a line.
		VoiceScript.kill_quip(last_hitter)
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
	if _voice != null:
		_voice.tick(delta)
	if not replica or not alive or not _received_pose:
		return
	_timeline.advance(delta)
	var sample: Dictionary = _timeline.sample()
	global_position = sample.pos
	rotation.y = sample.yaw


## Presentation-side mirror of the host's mob: the host owns AI, damage and
## gold, so a replica only replays the snapshot it was handed.
func apply_snapshot(state: Dictionary, tick: int = -1) -> void:
	var previous_health := health
	var was_alive := alive
	var previous_state := self.state
	_ingest_pose(state,tick)
	self.state = state.s
	_state_time = state.t
	health = state.h
	alive = state.a
	velocity = state.v
	if is_instance_valid(_visual):
		_visual.set_motion(velocity, state.g)
		_visual.set_combat(self.state, _state_time)
		_visual.set_poise(_present_blocking(), _present_crouch())
	# The host commits the swing; the guest hears the windup off the state change
	# the snapshot carries, which is the authority's own rule one packet late.
	if previous_state != "WINDUP" and self.state == "WINDUP":
		_voice.say("attack")
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
	var authored := Vector2(0.25, 0.12)
	if is_instance_valid(_visual):
		authored = _visual.head_hit_profile()
	# The zone is a band across the body, so it can never be narrower than the
	# capsule the arrow actually stops on.
	return Vector2(Hitbox.head_zone_radius(authored.x, float(profile.get("radius", 0.3))),
		authored.y)


func is_dead() -> bool:
	return not alive
