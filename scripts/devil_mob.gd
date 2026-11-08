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
const SeveredHead = preload("res://scripts/severed_head.gd")
const SeveredBody = preload("res://scripts/severed_body.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const MobSteering = preload("res://scripts/mob_steering.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const DuelBrainScript = preload("res://scripts/warband/duel_brain.gd")
const CombatScript = preload("res://scripts/combat.gd")
const DemonFireScript = preload("res://scripts/warband/demon_fire.gd")
const MobLod = preload("res://scripts/mob_lod.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const VoiceScript = preload("res://scripts/audio/voice.gd")
const VoiceEmitterScript = preload("res://scripts/audio/voice_emitter.gd")
const Perf = preload("res://scripts/perf_probe.gd")

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
## The flight of a killing headshot, named by the arrow that landed it
## (`note_arrow_headshot`) or by the death snapshot a replica was handed. It is
## spent by the next blow, so a headshot that leaves the body standing cannot
## take a later kill's head.
var _head_shot := Vector3.ZERO
## The shove of a two-handed overhead that named this body before its blow: a
## killing chop splits it where the blade lands (`SeveredBody`).
var _cleave := Vector3.ZERO
var _cleave_kind := "horizontal"
## The class of the piece behind the blow in flight, named by the striker before
## its contact (`note_strike`) and spent by the blow that lands. A devil has no
## `Combat` and no stagger roll of its own: a blunt blow is the one that breaks
## its line (`Combat.blunt_stagger`), and the stagger state is its own.
var _strike_class := ""
var _sever := Vector3.ZERO
var _split := Vector3.ZERO
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
## The body's one physics capsule: what every arrow, thrown blade and swing stops
## on. Built from the profile in `_ready`; the shape is this body's own resource,
## so a subclass that draws its body at another size resizes it here.
var _collision: CollisionShape3D
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
## Physics frames between two brain ticks, and the offset this body takes into
## them so a den never lands its brains on the same frame. A brain is a decision
## rate: where to stand, who to chase, whether to swing. None of that needs the
## drawn frame's rate, and a hall of a hundred of them doing it was a fifth of
## the cave's frame. The blow itself is not a decision and does not run on this
## clock (`_advance_strike`).
##
## **Physics frames, never drawn ones**: the gate below used to count rendered
## frames, which made the brain run `fps / THINK_FRAMES` times a second - 12 at
## 60 fps, 29 at 144, 4 at 21 - so a mob's reaction time was a property of the
## host's GPU, and in co-op of the whole party's fight. One figure now: 12 Hz on
## every machine, with the LOD budget still deciding how many of those a distant
## body gets.
const THINK_FRAMES := 5
var _phase := 0
## The physics frame perception last ran in, and the tick time banked for it.
var _sense_frame := -1
var _sense_bank := 0.0
## Seconds left before a committed blow lands: armed by the brain, spent on the
## physics tick. -1 is no blow in the air.
var _strike_left := -1.0
## Parked by `MobCuller`: no tick, no draw, no state change while it is true.
var dormant := false
## Rested by its owner (`rest`): no brain at all, nothing hidden.
var resting := false
## Culled by its owner's eye: the body is past the fog wall and behind rock, so
## it is hidden and its rig is parked - but it is not dormant, so an owner that
## only asked for less drawing never silenced a fight.
var culled := false
## A replica's own last word on its feet: the physics body never moves here, so
## `is_on_floor()` is whatever the spawn left behind and the rig must read the
## snapshot's answer instead.
var _replica_grounded := true
## The clock of the last state a replica was handed. A copy the host has stopped
## naming - it died outside a peer's batch, or walked past the 70 m band - holds
## its last pose forever otherwise, a mob standing where the host has none.
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
## The drawn frame this body's brain last ran in, and the tick time it has banked
## from further ticks inside the same frame (`_physics_process`).
var _brain_frame := -1
var _brain_bank := 0.0
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
## Opt-in, and only a body that raises its own guard opts in - the warband's
## cultists, and the Hollow's duelists (`duelist`). The frontier's mobs keep the
## fight they were tuned for.
var guard_between_swings := false
## Seconds left on a rolled guard window (`brace`). A braced body refuses to
## trade: it holds its guard instead of swinging, and drops out of it into the
## swing when the window closes. The cultists brace on their own clock; the
## camp's watchers roll for it once an exchange.
var _braced := 0.0
## A duelist fights rather than grinds: it runs the ladder in `duel_brain.gd`
## instead of the walk-into-reach loop, guards on its temper's share and commits
## to a blow only into an opening. Set by whatever spawns the body before it
## enters the tree, or carried in the profile row as `"duelist": true`. Every
## other demon and every watcher keeps the grind.
var duelist := false
## What a duelist's temper is: how often it holds its guard, the beat before a
## blow, the seconds it circles, how far it leads a moving body, and that it
## waits for an opening. Its reach is the profile's, and how often it may swing
## stays the profile's own cooldown and clip timing.
const DUEL_TEMPER := {"guard": 0.55, "beat": 0.2, "step": 0.6, "lead": 0.3, "window": true}
## How far past its own reach a duelist stops closing: the band its swing already
## covers, so it starts the windup outside contact and carries itself in on the
## blow (the same gate the mob's own circle uses).
const DUEL_CLOSE_PAD := 1.15
## The guard a duelist writes on every brain tick while the ladder holds it up.
## Longer than one tick at 12 Hz, so a guard never blinks between two.
const DUEL_GUARD_HOLD := 0.2
## The ladder itself, built for a duelist and null for every other body.
var _duel = null
var _duel_temper: Dictionary = {}
## The fire kit (`demon_fire.gd`): the spells this body was born with, in the
## order it tries them, and the seconds left on each one's own clock. It is empty
## on every body whose owner names no spells, which is the whole frontier
## unchanged - a demon with a kit gets a third action beside its swing and guard.
var _fire_spells: Array[String] = []
var _fire_cooldowns: Dictionary = {}
## The spell winding up now ("" when none) and the seconds left on its tell. The
## windup is the tell the player answers; a stagger cancels it before it resolves.
var _cast_spell := ""
var _cast_left := -1.0
## The point and the line the windup was aimed down. A cast lands where the
## target stood when it was loosed, and never follows it: that is the dodge.
var _cast_aim := Vector3.ZERO
var _cast_facing := Vector3.FORWARD
## What the cast leaves in the world: the coal a windup gathers, the fireball in
## the air and the burning ground this body has. The body frees all three.
var _cast_tell: Node3D
var _cast_missile: Node3D
var _hazard: Node3D
## The beat before a body's second and third spell are ready, so a meeting is
## answered with fire and not with the whole kit on one tick.
const CAST_STAGGER := 1.5
## Two bodies of one family closer than this push apart (`_separate`).
const SEPARATION_RADIUS := 1.35
## The family's bodies by `SEPARATION_RADIUS` cell, gathered once per physics
## frame (`_crowd`): group name -> {cell: [body]}, and the frame it was taken.
## A delve fields 210 watchers in one family, so walking the whole group for
## every body that moved was 210 lookups per mover per tick.
static var _crowd_cells := {}
static var _crowd_frames := {}


func _ready() -> void:
	# With which of the `THINK_FRAMES` this body thinks, so a den of thirty never
	# lands its brains on the same frame.
	_phase = absi(get_instance_id()) % THINK_FRAMES
	var table := _profiles()
	if not table.has(mob_id):
		push_error("Unknown mob id: " + mob_id)
		return
	profile = (table[mob_id] as Dictionary).duplicate(true)
	# A body whose profile names it a duelist fights the ladder below; the scene
	# that spawns it may also say so on the body itself, before it enters the tree.
	duelist = duelist or bool(profile.get("duelist", false))
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
	_collision = CollisionShape3D.new()
	_collision.shape = shape
	_collision.position.y = shape.height * 0.5
	add_child(_collision)
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
	# A duelist fights the shared ladder: its own clock in the fight, its temper
	# built from the profile's reach, and a guard raised on its own window rather
	# than on the cultists' cooldown clock.
	if duelist:
		guard_between_swings = true
		_duel_temper = DUEL_TEMPER.duplicate()
		_duel_temper["range"] = float(profile.reach)
		_duel_temper["pad"] = DUEL_CLOSE_PAD
		_duel = DuelBrainScript.new(_strafe_dir)
	# What this body throws, and when each spell is first ready. A body with no
	# kit is the frontier's own demon: nothing below is ever reached for it.
	_fire_spells.assign(_fire_kit())
	for index in _fire_spells.size():
		_fire_cooldowns[_fire_spells[index]] = float(index) * CAST_STAGGER
	_lod = MobLod.new(int(absf(global_position.x) * 7.0 + absf(global_position.z) * 13.0))
	_attack_cooldown = _rng.randf_range(0.25, 0.85)
	state = "IDLE"
	_state_time = 0.0
	# The voice is named by the profile, so a hollow warden and a gallowsroot look
	# their takes up in their own folders without this file knowing either one.
	_voice = VoiceEmitterScript.create(voice_id(), self, false, 2711 + int(absf(global_position.x)))
	# `node_added` marks a replica before this body has a capsule to hide; the
	# first state is a packet away, so the hidden copy must be settled here.
	_apply_shown()


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
	if resting:
		return
	# Three clocks, and only the last one is a decision:
	#   * every physics tick - a blow already in the air, a corpse settling and
	#     what the eye reads (`_advance_presentation`);
	#   * once a drawn frame - everything the body can see, which is the rate a
	#     brain used to keep, so nothing that could be seen before is missed;
	#   * every `THINK_FRAMES` frames - where it stands, who it hunts, whether it
	#     swings. That is the quarter that cost a fifth of the cave's frame, and
	#     none of it needs the drawn frame's rate.
	# The clock that comes round is handed the whole elapsed time, so the
	# simulated time is unchanged - only work no eye could see is skipped.
	if not alive:
		# A ragdoll that falls five frames at a time drops a body through the
		# floor, so settling is not on the decision clock either.
		CorpsePhysics.settle_root(self, delta)
		return
	# A replica is the host's mob drawn here: `apply_snapshot` is the only writer
	# of its pose, health and state. Its brain never runs, and its body must not
	# integrate either - stepping it along the snapshot's velocity between packets
	# walks the copy ahead of the authority and then snaps it back, which reads as
	# stutter and, once the packets stop, as a mob that runs off on its own. What
	# is left is presentation: the rig still poses and advances its clips.
	if replica:
		_advance_presentation()
		return
	_advance_strike(delta)
	_advance_cast(delta)
	_advance_motion(delta)
	_advance_presentation()
	# The physics frame, never the drawn one: `get_process_frames()` counts
	# rendered frames, so a brain gated on it thinks `fps / THINK_FRAMES` times a
	# second - 12 at 60 fps, 29 at 144, 4 at 21. Mobs reacted four times faster on
	# a better GPU, and in co-op the host's frame rate set every mob's reaction
	# time for the whole party. The tick budget decides *how often* a body thinks;
	# this gate only spreads those decisions over the frames inside one tick.
	var frame := Engine.get_physics_frames()
	# Sight every physics frame (the rate a 60 Hz brain used to keep, so nothing
	# that could be seen before is missed now), and a decision every
	# `THINK_FRAMES` of them - one figure on every machine, whatever the frame
	# rate is.
	if frame == _sense_frame:
		_sense_bank += delta
	else:
		_sense_frame = frame
		_advance_senses(delta + _sense_bank)
		_sense_bank = 0.0
	if frame == _brain_frame:
		_brain_bank += delta
		return
	if (frame + _phase) % THINK_FRAMES != 0:
		_brain_bank += delta
		return
	_brain_frame = frame
	var step := delta + _brain_bank
	_brain_bank = 0.0
	Perf.begin("mob.ai")
	_think(step)
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
		return
	delta = budget
	# Sight, not proximity, decides whether this mob is in a fight - and sight is
	# already spent every tick by `_advance_senses`, so a brain this coarsely
	# budgeted never misses a sighting a per-frame brain would have made.
	var pursuit := _senses.aggressive()
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
	_advance_cast_clock(delta)
	# Between its own swings a cultist is not wide open: it keeps its guard up
	# while it re-arms. That is what makes a swing an opening instead of a rhythm.
	# It is braced for most of its cycle and opens for the half second before it
	# can swing again: a cultist is something you catch off its guard, not something
	# you out-trade, and that is what makes the fight last. A duelist's guard is
	# its ladder's own window (`_duel_step`) and is left to it.
	if guard_between_swings and not duelist and _attack_cooldown > 0.30:
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
			elif not _duel_step(delta):
				_circle(delta, distance, direction)
			# The third action: fire is what a body does between blows, and it is
			# only asked once the swing the ladder decided on has had its say.
			_cast_step(distance, direction)
		"CAST":
			# The windup holds the line it was loosed on: the body plants and
			# looks where the fire is going, and the cast resolves on its own
			# clock (`_advance_cast`), not on this one.
			_face_intent = _cast_facing
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
				_strike_left = 0.0
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
	_turn(delta)
	_separate()


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
	if replica:
		# A replica's band is its presentation and nothing else: no brain runs to
		# re-apply it, and a copy fifty metres up a hall was being skinned for the
		# shadow pass it does not need.
		_cull_presentation(_present_distance(nearest))
	if not MobLod.dormant(nearest, dormant):
		if dormant:
			mob_wake()
		return
	if dormant:
		return
	if replica or _may_sleep():
		mob_sleep()


## How far this body is from the eye that draws it: the camera on this machine
## when the culler has measured one, and the nearest ranger as the fallback for a
## scene with no camera behind it.
func _present_distance(nearest: float) -> float:
	return _view_distance if _view_distance >= 0.0 else nearest


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


## The owner's word that nothing can reach this body: a delve den asleep with the
## whole party out of its sight. While it holds the brain is skipped outright -
## unlike `mob_sleep` nothing is hidden, and the rig keeps its own clock on the
## band `nearest` puts it in. Lifting it hands the next tick back to the budget
## with nothing banked from the rest.
func rest(value: bool, nearest: float = INF) -> void:
	if value:
		_cull_presentation(_present_distance(nearest))
		# A body put to sleep mid-windup does not leave a tell standing over a
		# fire it will never throw.
		_cancel_cast()
	elif resting:
		_lod.resume()
	resting = value


func mob_wake() -> void:
	# A blow reaches a rested body as surely as a parked one (`take_damage`,
	# `stagger`): it thinks again this tick instead of at its owner's next look.
	rest(false)
	if not dormant:
		return
	dormant = false
	_lod.resume()
	set_physics_process(true)
	_apply_shown()
	# Re-apply the presentation band for the distance it woke at.
	_present_band = -1


## The owner's eye cannot reach this body: hide it and park its rig. It keeps
## its brain, its collision and its clock - a body behind the party is still a
## fight, and the party rounds a corner into it at full speed.
func set_culled(value: bool) -> void:
	if value == culled:
		return
	culled = value
	_apply_shown()


## One place decides whether the body and its rig are drawn: parked by the
## culler and culled by its owner are two reasons for the same treatment, and a
## rig that keeps sampling tracks while hidden costs what a visible one does.
##
## A replica that has never been sent a state is a third: the guest built this
## copy of the wood's mob, but the host may not have one there at all - killed
## before the join, or a body only the host fields. Until the wire proves it
## exists, it is neither drawn nor solid, so the guest cannot see a ghost or walk
## into one.
func _apply_shown() -> void:
	var unseen := replica and not _received_pose
	var hidden := dormant or culled or unseen or stale
	visible = not hidden
	if (unseen or stale) and _collision != null:
		_collision.disabled = true
	elif _collision != null and _collision.disabled:
		_collision.disabled = false
	if replica:
		# A replica's only LOD is whether the local eye can see its state: a
		# hidden copy skips the clip pass; a shown one is posed on the band this
		# machine's own camera puts it in, not always at full detail.
		_present_band = 2 if hidden else MobLod.band(maxf(_view_distance, 0.0))
	if is_instance_valid(_visual) and _visual.has_method("set_parked"):
		_visual.set_parked(hidden)


## Take the replica switch from the session. A mob the host owns is marked before
## its first snapshot arrives, and until that snapshot it is a copy of a body
## that may not exist here: hide it and take its capsule out of the world.
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
	_timeline.clear()
	_apply_shown()


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
	# when there is nothing left to fight. A duelist that loses its quarry must
	# not stand guard at a body that is no longer there.
	_braced = maxf(0.0, _braced - delta)
	_warband_guard = maxf(0.0, _warband_guard - delta)
	# A body out of the fight re-arms its spells as it re-arms its arm.
	_advance_cast_clock(delta)
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	_face_intent = Vector3.ZERO
	_return_home(delta)
	_turn(delta)
	if _present_band > 1:
		# Nothing at this distance can see the pose: skip the cluster pass and
		# the locomotion presentation entirely.
		_move_intent = _move_intent.normalized() if _move_speed > 0.0 else Vector3.ZERO
		return
	_separate()


func _enter(next_state: String, reset_time := true) -> void:
	state = next_state
	if reset_time:
		_state_time = 0.0
	if next_state == "WINDUP":
		_strike_left = -1.0
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


# --- the owner's difficulty --------------------------------------------------

## This body's share of its owner's difficulty (`delve_mode.gd`): how often it
## swings. 1.0 is the body as authored, and the frontier's own mobs never leave it.
## The swing's telegraph and strike are the animation's and stay as authored - a
## body that swings twice as often still lands its blow on the clip's own impact
## frame - so this divides the wait *between* blows only.
var difficulty_rate := 1.0
## The pool, walk and run this body was born with, taken the first time a floor
## scales it: `apply_difficulty` sets from these rather than compounding, so a body
## re-scaled twice is still its authored self.
var _authored := {}


## Set this body's numbers for a floor of a given difficulty: `life` multiplies its
## pool and `rate` multiplies how fast it walks and runs and how often it swings
## (`difficulty_rate`, which `_cooldown_seconds` divides by). A body refilled to
## its new pool, since a floor scales a body at spawn and never under a fight.
##
## The authored numbers are taken on the first call and every later one sets from
## them, so the verb is idempotent: the same difficulty applied twice is the floor
## that difficulty asks for, not four times it.
func apply_difficulty(life: float, rate: float) -> void:
	if not alive:
		return
	if _authored.is_empty():
		_authored = {
			"max_health": max_health,
			"walk_speed": float(profile.get("walk_speed", 0.0)),
			"run_speed": float(profile.get("run_speed", 0.0)),
		}
	max_health = maxf(1.0, float(_authored["max_health"]) * life)
	health = max_health
	profile["walk_speed"] = float(_authored["walk_speed"]) * rate
	profile["run_speed"] = float(_authored["run_speed"]) * rate
	difficulty_rate = maxf(0.01, rate)


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


## The duel ladder, for a body that fights a body rather than grinding it: it
## guards on its temper's share, steps off the line between blows and commits to
## a swing only when the target is in a window (`DuelBrainScript.observe`).
## Returns false for anything that is not a duelist with a target it can see, so
## the mob's own circle keeps every other body exactly as it was - and a duelist
## that loses its quarry falls back to the same hunt and wander it always had.
##
## It decides only what the mob's states already take: where to stand, where to
## look, whether the guard is up, and whether a windup starts. The windup, the
## strike's impact frame and the cooldowns stay the states' own (`_enter`,
## `_advance_strike`, `_cooldown_seconds`), so the tell a player answers and the
## pace of the fight do not change.
func _duel_step(delta: float) -> bool:
	if not duelist or _duel == null or not _senses.seen or not is_instance_valid(_target):
		return false
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var answer: Dictionary = _duel.tick(delta, _duel_temper, {
		"position": global_position,
		"target": _target.global_position,
		"target_velocity": _target.velocity,
		"weapon": "blade",
		"ready": _attack_cooldown <= 0.0 and _braced <= 0.0,
		"target_open": _duel.observe(_target.get("combat")),
	})
	# The guard is the body's own window: the reduction `take_damage` applies and
	# the pose the sampler reads both come off this one answer.
	warband_guard(DUEL_GUARD_HOLD if bool(answer["guard"]) else 0.0)
	var move: Vector3 = answer["move"]
	_move_intent = _steer(move) if move.length_squared() > 0.0001 else Vector3.ZERO
	if _move_intent.length_squared() > 0.0001:
		_move_speed = float(profile.run_speed) if bool(answer["run"]) else float(profile.walk_speed)
	else:
		_move_speed = 0.0
	if to_target.length_squared() > 0.0001:
		_face_intent = to_target.normalized()
	if not str(answer["swing"]).is_empty():
		_choose_attack()
		_enter("WINDUP")
	return true


# --- the fire kit -----------------------------------------------------------

## What this body may throw, in the order it tries them. The base demon fights
## with its hands alone, so an empty kit is every frontier mob and every watcher
## unchanged; the Hollow's goatmen name their fire in `delve_demon.gd`.
func _fire_kit() -> Array[String]:
	return []


## The kit this body was born with.
func fire_spells() -> Array[String]:
	return _fire_spells.duplicate()


## Seconds left on one spell's clock, 0 when it may be thrown.
func fire_cooldown(spell_id: String) -> float:
	return float(_fire_cooldowns.get(spell_id, 0.0))


## Whether a windup is standing: the tell a player answers, and never a second
## cast on top of a first.
func casting() -> bool:
	return not _cast_spell.is_empty()


## Everyone this body's fire can burn: the same bodies its melee picks from, so
## the blast, the cone and the patch all read the live party.
func fire_targets() -> Array:
	return _candidates()


## The chest the fire comes out of: the rig's own drawn height, so a fitted
## goatman throws from the body it is actually wearing.
func _throw_point() -> Vector3:
	var chest := 1.12
	if is_instance_valid(_visual) and _visual.has_method("drawn_height"):
		chest *= maxf(0.4, float(_visual.drawn_height()))
	return global_position + Vector3.UP * chest


## The kit's clocks, on the brain's own budget like the swing's cooldown.
func _advance_cast_clock(delta: float) -> void:
	for spell_id in _fire_cooldowns.keys():
		_fire_cooldowns[spell_id] = maxf(0.0, float(_fire_cooldowns[spell_id]) - delta)


## The third action, beside a swing and a guard: the first spell of the kit that
## is off cooldown, in range and not already burning the ground. It never begins
## while the body is swinging, holding a rolled guard, or already winding one up -
## the state is the gate - so a demon with fire is still a duelist and not a
## turret. A spell is spent as its windup starts: interrupting the tell costs the
## body the cast.
func _cast_step(distance: float, direction: Vector3) -> void:
	if _fire_spells.is_empty() or replica or not _senses.seen:
		return
	if state != "CIRCLE" or casting() or _braced > 0.0:
		return
	if not is_instance_valid(_target) or not _aggro_allowed(_target.global_position):
		return
	for spell_id in _fire_spells:
		if fire_cooldown(spell_id) > 0.0:
			continue
		var row: Dictionary = DemonFireScript.spell(spell_id)
		if not DemonFireScript.in_range(row, distance):
			continue
		# One patch at a time per body: the ground is a place, not a rhythm.
		if str(row.get("shape", "")) == "hazard" and is_instance_valid(_hazard):
			continue
		_begin_cast(spell_id, row, direction)
		return


func _begin_cast(spell_id: String, row: Dictionary, direction: Vector3) -> void:
	_cast_spell = spell_id
	_cast_aim = _target.global_position
	_cast_facing = direction
	_cast_left = maxf(0.05, float(row.get("windup", 0.5)))
	_fire_cooldowns[spell_id] = float(row.get("cooldown", 0.0))
	# The guard comes down for the windup: the tell is the opening, and a body
	# that reads it gets a free exchange.
	warband_guard(0.0)
	_enter("CAST")
	# The noise belongs to the tell rather than to the fire, as a swing's does.
	_voice.say("attack")
	_cast_tell = DemonFireScript.telegraph(get_parent() as Node3D, _throw_point(), row)


## Spends a windup on the physics tick, exactly as a blow's countdown is spent: the
## tell runs on the clock the eye reads and the fire lands on the frame its windup
## ends, not on the next decision.
func _advance_cast(delta: float) -> void:
	if _cast_left < 0.0:
		return
	_cast_left -= delta
	if _cast_left > 0.0:
		return
	var spell_id := _cast_spell
	_cast_left = -1.0
	_cast_spell = ""
	_free_tell()
	if state != "CAST":
		# A stagger, a corpse or a hunt took the body off the windup: nothing is
		# spawned and nothing is burned.
		return
	_resolve_cast(spell_id)
	_enter("CIRCLE")
	# The body spent a beat on the fire: its arm re-arms from here.
	_attack_cooldown = _cooldown_seconds()


## The spell lands where the windup remembered it and down the line it reared back
## on. The target is not read again: fire is where the body was, so walking out of
## it is the answer, and a target that died mid-windup leaves the cast aimed at an
## empty patch of ground rather than at nothing.
func _resolve_cast(spell_id: String) -> void:
	var row: Dictionary = DemonFireScript.spell(spell_id)
	var parent := get_parent() as Node3D
	if row.is_empty() or not is_instance_valid(parent):
		return
	match str(row.get("shape", "")):
		"projectile":
			_cast_missile = DemonFireScript.launch(parent, _throw_point(), _cast_aim, row,
				Callable(self, "_fire_blast"))
		"cone":
			DemonFireScript.breath(parent, global_position, _cast_facing, row, self)
		"hazard":
			_hazard = DemonFireScript.ember_rain(parent, _cast_aim, row,
				Callable(self, "_fire_burn"))


## A fireball arriving: the blast at the point it landed, out of this body's own
## hand. The shot only carries the point; the fire is the demon's.
func _fire_blast(at: Vector3, row: Dictionary) -> void:
	DemonFireScript.blast(get_parent() as Node3D, at, row, self)


## One tick of this body's burning ground.
func _fire_burn(at: Vector3, row: Dictionary) -> void:
	DemonFireScript.burn(at, row, self)


## Takes the windup's coal off the screen.
func _free_tell() -> void:
	if is_instance_valid(_cast_tell):
		_cast_tell.queue_free()
	_cast_tell = null


## A windup that never lands: nothing is spawned, nothing is burned, and the tell
## comes off the screen. The spell stays spent.
func _cancel_cast() -> void:
	_cast_left = -1.0
	_cast_spell = ""
	_free_tell()


## The body's own fire goes out with it: a windup is dropped, a patch is put out
## and a fireball still in the air is taken with the hand that threw it.
func _release_fire() -> void:
	_cancel_cast()
	if is_instance_valid(_cast_missile):
		_cast_missile.queue_free()
	_cast_missile = null
	if is_instance_valid(_hazard):
		_hazard.queue_free()
	_hazard = null


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


## The body moves, every tick, along the intent the brain last set. Motion is not
## a decision: handing `move_and_slide` the brain's five frames of delta swept a
## charging body a body-length in one step, with no capsule and no pose in
## between - which reads as teleporting, and puts every swing behind it.
func _advance_motion(delta: float) -> void:
	Perf.begin("mob.move")
	_drive(delta)
	Perf.end()


## What the eye reads, on every physics tick. The state it shows is the brain's,
## but the clip advances when the body is drawn: a death held on the ground must
## not step five frames at a time.
func _advance_presentation() -> void:
	if _present_band > 1 or not is_instance_valid(_visual):
		return
	# A replica's physics body is never stepped, so its measured velocity is
	# meaningless: the run/walk clip has to read the motion the snapshot carried.
	var motion: Vector3 = velocity if replica else get_real_velocity()
	var grounded: bool = _replica_grounded if replica else is_on_floor()
	_visual.set_motion(motion, grounded)
	_visual.set_combat(state, _state_time)
	_visual.set_poise(_present_blocking(), _present_crouch())


## Everything the body can see, on every physics tick. Perception is a raycast
## and a memory clock, not a decision: a brain that thinks every fifth frame must
## not also see every fifth frame, or a ranger crosses a doorway unseen.
func _advance_senses(delta: float) -> void:
	if dormant or replica:
		return
	var nearest := _nearest_ranger()
	if nearest <= _sight_range():
		Perf.begin("mob.senses")
		_senses.step(self, _candidates(), delta, _sight_range(),
			_eye_height(), Callable(self, "_is_hostile"))
		Perf.end()
	else:
		_senses.age(delta)


## Spends a committed blow's countdown. Called on the physics tick before the
## brain's budget is consulted, so a blow armed by a coarse brain still lands on
## the frame the swing's contact is authored for - within one tick, not within
## one brain.
func _advance_strike(delta: float) -> void:
	if _strike_left < 0.0:
		return
	_strike_left -= delta
	if _strike_left > 0.0:
		return
	_strike_left = -1.0
	_resolve_strike()


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
	var cells := _crowd()
	var cell := _crowd_cell(global_position)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var near: Array = cells.get(Vector2i(cell.x + dx, cell.y + dz), [])
			for other in near:
				if other == self or not is_instance_valid(other) or not bool(other.get("alive")):
					continue
				var offset: Vector3 = global_position - other.global_position
				offset.y = 0.0
				var gap := offset.length()
				if gap > 0.001 and gap < SEPARATION_RADIUS:
					push += offset / gap * (SEPARATION_RADIUS - gap)
	if push.length_squared() > 0.0001:
		if _move_intent.length_squared() > 0.0001:
			_move_intent = (_move_intent + push * 0.85).normalized()
		else:
			_move_intent = push.normalized()
			_move_speed = maxf(_move_speed, float(profile.walk_speed) * 0.35)


## This family's bodies by cell, taken on the first separation of the physics
## frame. A body can only push off the nine cells round its own, because a cell
## is as wide as the push. Within a frame the cells are where the bodies stood
## when it began; the push itself reads where each neighbour is now.
func _crowd() -> Dictionary:
	var group := _group_name()
	var frame := Engine.get_physics_frames()
	if int(_crowd_frames.get(group, -1)) == frame:
		return _crowd_cells[group]
	var cells := {}
	for other in get_tree().get_nodes_in_group(group):
		var key := _crowd_cell((other as Node3D).global_position)
		if cells.has(key):
			(cells[key] as Array).append(other)
		else:
			cells[key] = [other]
	_crowd_cells[group] = cells
	_crowd_frames[group] = frame
	return cells


static func _crowd_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / SEPARATION_RADIUS), floori(point.z / SEPARATION_RADIUS))


func _drive(delta: float) -> void:
	var desired := _move_intent * _move_speed
	if state == "STRIKE":
		var spent := clampf(_state_time / maxf(0.01, float(profile.strike)), 0.0, 1.0)
		desired = _strike_direction * float(profile.lunge) * (1.0 - 0.62 * spent)
	elif state == "WINDUP" or state == "STAGGER" or state == "CAST":
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
	# A body with nothing to do does not ask the world where it can go: a sweep
	# for a body with no horizontal motion resolves to standing still anyway, and
	# it is the most expensive thing a mob does per tick - a capsule cast at the
	# terrain. Half of a stand-off is spent standing or circling on the spot.
	if not is_on_floor() \
			or Vector2(velocity.x, velocity.z).length_squared() > 0.0004 \
			or desired.length_squared() > 0.0004:
		MobLod.move(self)


## Which way the body looks, on the clock it decides on. Facing is a decision like
## any other: turned from the motion tick instead, a body spends five frames
## swinging round to a point it chose five frames ago, and its sight cone sweeps
## the room on the way - a wanderer that turns would notice a ranger it never faced.
func _turn(delta: float) -> void:
	if _face_intent.length_squared() > 0.0001 and state != "STAGGER":
		rotation.y = lerp_angle(rotation.y, atan2(-_face_intent.x, -_face_intent.z),
			minf(delta * float(profile.turn), 1.0))


func _steer(direction: Vector3) -> Vector3:
	return _steering.steer(self, direction, float(profile.height) * 0.45)


func stagger(seconds: float) -> void:
	if not alive:
		return
	mob_wake()
	# A blow that breaks the body breaks the spell with it: the windup is the only
	# thing standing between a telegraph and the fire, and a stagger takes it.
	_cancel_cast()
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
## swings too often is not the same fight as one that does not - and the floor's
## difficulty scales it through `difficulty_rate`.
func _cooldown_seconds() -> float:
	return float(profile.cooldown) / maxf(0.01, difficulty_rate)


## Whether a body at `focus` may be fought: the town's safe ring shuts every
## fight down, however the pursuit started.
func _aggro_allowed(focus: Vector3) -> bool:
	return not MobSenses.in_safe_ring(safe_center, focus)


## What the body is holding up, for the sampler. A duelist's guard is a stance
## the eye can read and answer; every body that grinds keeps the arms it was
## authored with.
func _present_blocking() -> bool:
	return duelist and guard_up()


func _present_crouch() -> bool:
	return false


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
	# The piece behind the blow is spent here too, whatever comes of it.
	var strike := _strike_class
	_strike_class = ""
	# Being hit is not something a parked body can miss: it wakes and turns.
	mob_wake()
	last_hitter = source_id
	var applied := amount * Hitbox.damage_multiplier(headshot)
	# A raised guard turns most of the blow: you have to catch the cultist with
	# its blade down (its strike, or the moment its guard breaks on a stagger).
	var turned := false
	if guard_between_swings and _warband_guard > 0.0:
		applied *= GUARD_REDUCTION
		turned = true
	health = maxf(0.0, health - applied)
	DamageNumbers.spawn(get_parent(), get_aim_position(), applied, "hit", headshot, health <= 0.0)
	BloodFx.wound(self, blood_rig(), get_aim_position(), applied, headshot,
		health <= 0.0, blood_scale())
	if health <= 0.0:
		_enter_dead(true, flight, applied, chop)
		return
	# A blunt head rocks the body where an edge would only open it: the same roll
	# the campaign's own bodies make, spent here as the mob's own stagger - which
	# stands it still, drops its guard window and cancels a windup or a cast.
	if not turned:
		var stunned := CombatScript.blunt_stagger(applied, max_health, strike)
		if stunned > 0.0:
			stagger(stunned)
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


## The piece behind a blow, named by the striker before its contact: a blunt head
## is the one that breaks a devil's line (`Combat.blunt_stagger`). `at` is where
## the blow would land; a devil has no guard for it to matter to.
func note_strike(weapon_class: String, _at: Vector3 = Vector3.INF) -> void:
	if alive:
		_strike_class = weapon_class


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
func _enter_dead(announce: bool, severed := Vector3.ZERO, damage := 0.0,
		cleaved := Vector3.ZERO) -> void:
	Perf.begin("mob.dead")
	alive = false
	state = "DEAD"
	_struck = true
	# A demon's fire goes out with it: a windup is dropped, a patch is put out and
	# a fireball still in the air is taken with the hand that threw it. Nothing
	# this body made outlives it.
	_release_fire()
	_sever = severed
	_split = cleaved
	var fall := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	velocity = Vector3.ZERO
	# The head comes away before the ragdoll is built from the lethal pose, so
	# the stump the corpse keeps is the one the bones were read in.
	if is_instance_valid(_visual):
		if severed != Vector3.ZERO:
			SeveredHead.sever(_visual, severed, maxf(damage, 12.0))
		elif cleaved != Vector3.ZERO:
			SeveredBody.split(_visual, cleaved, maxf(damage, 30.0), _cleave_kind)
		_visual.die(fall)
	# Presentation, so every machine that runs this body hears it: the authority
	# because it killed it, a replica because the snapshot just said so. `alive`
	# is already false, so this cannot fire twice.
	_voice.say("death")
	if announce:
		Perf.begin("mob.defeated")
		defeated.emit(self, int(profile.gold))
		# Only the authority resolves a killer's `last_hitter` id, so only it
		# asks the killer for a line.
		VoiceScript.kill_quip(last_hitter)
		Perf.end()
	# Hold the authored death pose for the shared five minutes, then dissolve.
	Perf.begin("corpse.hold")
	CorpseHold.hold(self, _body)
	Perf.end()
	Perf.end()


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
	Perf.begin("mob.process")
	_replay_tick(delta)
	Perf.end()


func _replay_tick(delta: float) -> void:
	if _voice != null:
		_voice.tick(delta)
	if not replica or not alive or not _received_pose:
		return
	if not stale and _state_at > 0.0 \
			and Time.get_ticks_msec() / 1000.0 - _state_at > STALE_SECONDS:
		stale = true
		_apply_shown()
	_timeline.advance(delta)
	var sample: Dictionary = _timeline.sample()
	global_position = sample.pos
	rotation.y = sample.yaw


## Presentation-side mirror of the host's mob: the host owns AI, damage and
## gold, so a replica only replays the snapshot it was handed.
func apply_snapshot(state: Dictionary, tick: int = -1) -> void:
	if tick >= 0 and tick <= _stream_left:
		# A state from before the host stopped naming this copy: a datagram still
		# in flight, not news. It must not put a body back on the screen.
		return
	var previous_health := health
	var was_alive := alive
	var previous_state := self.state
	_ingest_pose(state,tick)
	self.state = state.s
	_state_time = state.t
	health = state.h
	alive = state.a
	velocity = state.v
	_replica_grounded = bool(state.get("g", true))
	_state_at = Time.get_ticks_msec() / 1000.0
	stale = false
	if replica:
		# The host's clock is the only one a replica has: lift the rest its
		# owner's build put it under, and put the rig back on the animation band
		# a replica always reads at. Without this a delve copy stays `resting`
		# and its walk clip never advances, so the mob glides with its legs set.
		rest(false)
		if dormant:
			mob_wake()
		_apply_shown()
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
		# The host strips a body before it becomes a container, so its record and
		# its drop hold the blade once. The guest's copy empties the same hand.
		if replica and has_method("take_weapon_item"):
			call("take_weapon_item")
		var cause: Vector4 = state.get("k", Vector4.ZERO)
		_cleave_kind = "vertical" if cause.w > 2.5 else "horizontal"
		_enter_dead(false,
			Vector3(cause.x, cause.y, cause.z) if cause.w > 0.5 and cause.w < 1.5 \
				else Vector3.ZERO,
			0.0,
			Vector3(cause.x, cause.y, cause.z) if cause.w > 1.5 else Vector3.ZERO)


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


## Whether this body is in a pursuit right now: it saw, heard or was struck by
## something it hunts and the memory has not run out. A scene that keeps bodies
## asleep until they notice somebody (the delve's dens) asks this.
func alerted() -> bool:
	return alive and _senses.aggressive()
