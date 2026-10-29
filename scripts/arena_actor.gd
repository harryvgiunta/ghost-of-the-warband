extends CharacterBody3D

signal fired(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float)
signal thrown_weapon(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float, weapon: String, weapon_index: int)
signal killed(slot: int, source: int)
# Ghost of the Warband: a lethal blow that overkills by at most the contract's
# 10% knocks the body DOWNED instead of killing it. These bracket that state so
# the HUD, the crawl and the revive channel never have to poll for it.
signal downed_started(slot: int)
signal downed_ended(slot: int)

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const BloodyFeet = preload("res://scripts/bloody_feet.gd")
const FootstepsScript = preload("res://scripts/audio/footsteps.gd")
const VoiceEmitterScript = preload("res://scripts/audio/voice_emitter.gd")
const BleedDrip = preload("res://scripts/warband/bleed_drip.gd")
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
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const MAX_HEALTH := 100.0
const WALK_SPEED := 5.5
## Packed focus silhouettes in the `gear` snapshot field: three bits, so the
## two skull trinkets get their own glow on every peer.
const FOCUS_CODES := {"tome":1, "skull":2, "skull_life":3, "skull_death":4}
const FOCUS_KINDS := {1:"tome", 2:"skull", 3:"skull_life", 4:"skull_death"}
var slot := 0
var peer_id := 0
var is_bot := true
var display_name := "Bot"
## The look this body wears (`WarbandLooks.profile_for`), set *before* the body
## enters the tree so the rig can bake the height in before it measures itself.
## Empty is the shipped ranger, which is what every arena fighter and bot is.
var appearance: Dictionary = {}
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
var max_health := MAX_HEALTH
var weapon_blood := 0.0
var alive := true
var kills := 0
var deaths := 0
var respawn := 0.0
## A body that stays down. The arena's round clock revives a dead fighter after
## three seconds; a warband mercenary that bled out is gone, and its roster record
## already says DEAD. Scenes that field bodies for good set this on creation.
var persistent_death := false
## Ghost of the Warband: a campaign body dies by the ground, never by the blow.
## A lethal hit always leaves it DOWNED, so every body gets the full bleed clock;
## once it is on the floor any blow that lands ends it; and a body that does die
## keeps its model where it fell instead of vanishing. The possession controller
## sets this on every roster body it spawns; the arena's own seats leave it off,
## where a round can still be lost to one heavy strike.
var warband_death := false
# Ghost of the Warband: the lifecycle a blow can put this body in. `alive` stays
# true while DOWNED - the body keeps its collision, its model and its claim on
# the slot, and only a finisher or the bleed clock kills it - so every existing
# `alive` check keeps its meaning.
var health_state := WarbandContracts.HealthState.ALIVE
var downed := false
## Seconds spent on the ground; the bleed clock reads this and nothing else.
var downed_seconds := 0.0
## The slot that put this body down, credited if it bleeds out.
var downed_by := -1
## Where that blow came from: the crawl aims the opposite way.
var downed_threat := Vector3.ZERO
var downed_threat_known := false
## A safe anchor the crawl biases toward (a friendly body, a patch of cover).
var safe_anchor := Vector3.ZERO
var safe_anchor_known := false
var authoritative := false
var is_local := false
## The voice this body speaks with (`VoiceLibrary.VOICES`), and the emitter that
## decides whether it says anything: a grunt on a real blow, the line on a heavy
## one, a word over a kill, and the moans of a body bleeding on the ground.
var voice_id := "player"
var _voice: VoiceEmitter
## True on the one peer that owns this body over the wire: it integrates its
## own movement immediately and reconciles against the host's acknowledgements.
var predicting := false
var spawn_point := Vector3.ZERO
var move_direction := Vector2.ZERO
var run_requested := false
var jump_requested := false
var stamina := Stamina.MAX
var max_stamina := Stamina.MAX
## Worn trinket kit and its summed modifiers (see `TrinketStats`).
var trinkets: Dictionary = {"neck":"", "ring1":"", "ring2":"", "off":""}
var trinket_stats: Dictionary = {}
## Energy Shield ward: while it runs, `absorb` of every hit is paid from
## stamina at `stamina_scale` times that share instead of from health.
var ward_seconds := 0.0
var ward_absorb := 0.5
var ward_stamina_scale := 2.0
var _exhausted := false
var consume_kind := ""
var _consume_elapsed := 0.0
var _heal_remaining := 0.0
var _heal_rate := 0.0
var input_age := 0.0
## The collision a scene configured for this body, kept across death so the
## revive can restore it instead of guessing one kit for every mode.
var _body_layer := -1
var _body_mask := -1
var _label: Label3D
var _ground_ring: MeshInstance3D
var _received_pose := false
var _gear_bits := -1
## The owning peer's unacknowledged movement frames and the local body it
## integrates them into. Empty for every host-side or remote fighter.
var _prediction = NetReplication.InputRing.new()
## The remote fighter's server states, played back a short delay behind the
## host so uneven packet arrivals render as motion instead of jumps.
var _timeline = NetReplication.SnapshotTimeline.new()
var _predicted_last := false
var _timeline_ready := false
## The last movement frame this body consumed as authority, and the state it
## held before using it. A correction replays this peer's later frames from it.
var _pending_seq := -1
## The newest acknowledgement, kept for the next physics frame. A correction
## sweeps collision per replayed frame, so it must not run inside an RPC
## callback (the idle frame) where the body's motion state is mid-frame.
var _pending_state: Dictionary = {}
## Client movement frames the authority has received but not simulated yet.
var _input_queue: Array = []
## True when this tick consumed one of them; false leaves the pose untouched.
var _frame_consumed := false
## True once a peer's numbered frames drive this body. Only then does a tick
## with no frame hold the pose: a body this scene drives itself (the host's own
## fighter, a bot, a fixture) has no frame stream and simulates every tick.
var frame_driven := false
var ack_seq := -1
var ack_position := Vector3.ZERO
var ack_velocity := Vector3.ZERO
## The server tick this peer drew the world at when it last acted.
var view_tick := -1
## Measured reconciliation: how far the prediction had drifted at the last
## authoritative packet, and how many corrections/replayed frames it took.
var prediction_drift := 0.0
## How far the rig is drawn from its body after a correction. The simulation
## takes the authoritative pose at once (the acknowledgement compares absolute
## poses, so a partially corrected body re-reports its own glide as drift), and
## this offset is what the eye sees: the model starts where it stood and travels
## to the corrected pose over a few frames.
var _rig_offset := Vector3.ZERO
## Where the model is actually drawn in world space, rate-limited toward
## `global_position + _rig_offset` so no correction can hop it.
var _rig_drawn := Vector3.ZERO
var _rig_drawn_ready := false
## The last sixty-four reconciliations: the frame acknowledged, the pose this
## peer had predicted for the following frame, the authoritative pose and the
## distance between them. The network regression prints the ones that moved.
var history: Array = []
var prediction_corrections := 0
var _last_motion := Vector3.ZERO
var _last_running := false
## A predicted body's own translation only matches the host within this
## tolerance; anything above it is replayed from the authoritative state. A
## standing body still lands within half a walking frame, so the floor absorbs
## the tick of phase rather than half a step.
const RECONCILE_DISTANCE := 0.05
## Every frame of disagreement worth this many frames of the body's own travel
## is phase, not error: the authority names a tick, and a tick either side of
## the client's frame is a legitimate few centimetres. Correcting that would
## yank the body backwards on every packet.
const RECONCILE_SLACK_FRAMES := 2.0
## Ceiling on the smoothed tolerance, so a fast body still corrects a real shove.
const RECONCILE_MAX_DISTANCE := 0.25
## How fast the model closes a correction, in metres per second, and the widest
## offset it will hold. A drag of up to a metre reads as the character stepping
## into place instead of a pop.
const RIG_GLIDE_SPEED := 4.0
const RIG_GLIDE_LIMIT := 2.0
## The most the drawn model may move in one frame. It also has to keep up with a
## walking body, so this is well above a stride and well below a pop.
const RIG_DRAW_STEP := 0.35
## The most the model may trail its body, in metres. Beyond this the offset is
## stale (a death, a revive, a scene hand-off) and is dropped instead of glided.
const RIG_DRAW_LIMIT := 2.5
## Movement frames each packet repeats behind its own. A frame the transport
## drops would otherwise cost its travel forever: the authority keeps walking
## short of the peer that sent it.
const INPUT_REDUNDANCY := 3
## Unconsumed client input frames the authority buffers. Two frames can arrive
## in one poll burst (a host under load runs two physics ticks per idle frame);
## holding them makes the authority apply each frame exactly once, in order, so
## the acknowledgement keeps naming the frame the client numbered. The cap is
## the longest stall worth replaying — 0.2 s of frames — because a frame dropped
## here loses its travel for good and shows up later as a correction.
const INPUT_QUEUE_LIMIT := 12
var _floor_query := PhysicsRayQueryParameters3D.new()
var _sight_query := PhysicsRayQueryParameters3D.new()
## Prints a bloody trail when this body walks out of a death pool.
var _bloody_feet := BloodyFeet.new()
## The boots: one emitter per body, driven by the same foot plant the trail reads.
var _footsteps := FootstepsScript.new()
## The blood this body leaves on the ground while it is down. Built with the body
## and parked until it falls, so a fight never allocates one.
var _bleed_drip: BleedDrip

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
	rig.appearance = appearance
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
	# A wire kit (or a mid-match paperdoll change) lands on the rig; the body
	# follows it into its maxima and its stagger resistance.
	rig.loadout_changed.connect(_sync_trinket_limits)
	roll = DodgeRoll.new()
	add_child(roll)
	dodge = DodgeStep.new()
	add_child(dodge)
	slide = RunningSlide.new()
	add_child(slide)
	_label = Label3D.new()
	_label.position.y = 2.3 * body_scale()
	_label.font_size = 36
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)
	var colors := [Color("70c4cb"),Color("e4a75f"),Color("bfa1dc"),Color("86c48a")]
	_label.modulate = colors[slot % colors.size()]
	var circle := TorusMesh.new()
	circle.inner_radius = 0.38
	circle.outer_radius = 0.43
	circle.rings = 24
	circle.ring_segments = 6
	_ground_ring = Geo.mesh_node(self,circle,Geo.material(colors[slot % colors.size()]),Vector3(0,0.025,0))
	# Built and parked with the body: the drop carries its own drip, and no scene
	# has to know that it does.
	_bleed_drip = BleedDrip.new()
	_bleed_drip.name = "BleedDrip"
	add_child(_bleed_drip)
	# The voice is built here and pointed at `voice_id`, which a scene may change
	# before the body makes its first noise. `is_local` is read every frame, not
	# here: the scene seats the body's flags after it is in the tree.
	_voice = VoiceEmitterScript.create(voice_id, self, false, 3907 + slot)

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
	_timeline.reset_to(position)
	_timeline_ready = false
	_predicted_last = false
	_prediction.clear()
	_pending_seq = -1
	_pending_state = {}
	ack_seq = -1
	_input_queue.clear()
	_frame_consumed = false
	frame_driven = false
	_rig_offset = Vector3.ZERO
	_rig_drawn = position
	_rig_drawn_ready = false
	_received_pose = false
	velocity = Vector3.ZERO
	move_direction = Vector2.ZERO
	run_requested = false
	jump_requested = false
	input_age = 0.0
	reset_stance()
	health = max_health
	weapon_blood = 0.0
	stamina = max_stamina
	ward_seconds = 0.0
	rig.set_ward(false)
	_exhausted = false
	ability.reset()
	consume_kind = ""
	_consume_elapsed = 0.0
	_heal_remaining = 0.0
	_heal_rate = 0.0
	alive = true
	# Ghost of the Warband: a respawn also clears the downed state - a body that
	# really died takes the arena's three-second path, never both.
	health_state = WarbandContracts.HealthState.ALIVE
	downed = false
	downed_seconds = 0.0
	downed_by = -1
	downed_threat_known = false
	safe_anchor_known = false
	# A respawn is the arena's way out of DEAD and out of DOWNED alike: the rig
	# stands up and stops bleeding here exactly as it does on a revive.
	_clear_downed_state()
	respawn = 0.0
	combat.stop()
	combat.clear_camera_ray()
	# The blow that killed this body also staggered it, and a dead body never
	# drains that clock: a revived ranger would stand there for the rest of the
	# killing blow's stagger, refusing every left click.
	combat.stagger_time = 0.0
	roll.reset()
	dodge.reset()
	rig.set_hit_react(0.0)
	rig.set_step(-1.0,Vector3.FORWARD)
	rig.set_roll(-1.0,Vector3.FORWARD)
	combat.attack_progress = 1.0
	combat.left_melee_progress = 1.0
	combat.right_melee_progress = 1.0
	combat.melee_progress = 1.0
	rig.reset_attack_state()
	rig._sync_primary_hand()
	rig.global_rotation.y = atan2(spawn_point.x,spawn_point.z)
	combat.aim_point = Vector3(0,1.2,0)
	_restore_body_collision()
	rig.visible = true

## A dying body keeps the collision its scene configured, because the revive
## has to put it back: the frontier ranger collides with mob layer 2 and the
## arena/delve fighters with the world only.
func _store_body_collision() -> void:
	_body_layer = collision_layer
	_body_mask = collision_mask
	collision_layer = 0
	collision_mask = 0

func _restore_body_collision() -> void:
	# A body downed by a blow keeps the collision its scene configured; one that
	# a lobby or round reset parked keeps the arena's fighter kit.
	collision_layer = _body_layer if _body_layer >= 0 else 4
	collision_mask = _body_mask if _body_mask >= 0 else 1

## Drops the rig into the prone drag pose and starts the drip. The state machine
## stays in this file; what runs here is only the body's own presentation of it,
## and every path into DOWNED calls it - the blow on the host, a replicated body
## reading the flag off the wire - so a body on the ground always looks like one.
func _begin_downed_state() -> void:
	if is_instance_valid(rig):
		# A downed body drags, it does not walk: the rig keeps whatever walk it
		# was in when the blow landed and keeps cycling its legs under the lie.
		# The crawl moves the body through its capsule itself, so this body's own
		# locomotion is what has to be zeroed here.
		rig.set_locomotion(Vector3.ZERO,true)
		rig.blood_loss = 0.0
		rig.set_downed(true)
	if _bleed_drip != null:
		_bleed_drip.attach(self)

## Puts the rig back on its feet and stops the drip. Shared by the revive, the
## arena respawn and the death, so no path can clear `downed` while leaving the
## prone pose - or a bleeding body - behind.
func _clear_downed_state() -> void:
	if is_instance_valid(rig):
		rig.set_downed(false)
		rig.blood_loss = 0.0
	if _bleed_drip != null:
		_bleed_drip.detach()

## The corpse: the rig stays where it fell, prone and spent, with the drip off.
## Shared by the death and by a replica reading a death off the wire, so a body
## that died on the host lies in the same pose on every screen watching it.
func _hold_corpse() -> void:
	if is_instance_valid(rig):
		rig.visible = true
		# The lie, held still: a corpse that kept the downed body's arm-over-arm
		# pull would read as a body still trying to crawl.
		rig.set_corpse(true)
		rig.blood_loss = 1.0
	if _bleed_drip != null:
		_bleed_drip.detach()

## How long this body has lain on the ground, as a 0..1 share of the bleed clock.
## The rig carries it so the drip (and anything later) reads the same number the
## clock that kills the body runs on.
func _tick_downed_presentation(delta: float) -> void:
	if not downed:
		return
	# Only the authority runs the bleed clock, because only it can kill the body.
	# A replica reads how long it has been lying here locally, so a remote body's
	# drip quickens too; nothing in this function decides a death.
	if not authoritative:
		downed_seconds = minf(downed_seconds + maxf(delta, 0.0),
			WarbandContracts.DOWNED_BLEED_SECONDS)
	if is_instance_valid(rig):
		rig.blood_loss = DownedRules.bleed_fraction(downed_seconds)

## Ghost of the Warband: a blow overkilled by at most 10% knocks this body down
## instead of killing it.
##
## The body keeps its collision and its model on purpose: it is still an
## obstacle, still finishable and still the thing a human walks over to pick up.
## What stops is intent - no swing in flight, no ability, no guard, no walk - and
## the bleed clock starts. Nothing here touches `alive`, so the respawn timer,
## the snapshot and every existing "is this body there" check are unchanged.
func enter_downed(source_id: int = -1) -> void:
	if downed or not alive:
		return
	health = 0.0
	downed = true
	health_state = WarbandContracts.HealthState.DOWNED
	downed_seconds = 0.0
	downed_by = source_id
	velocity = Vector3.ZERO
	move_direction = Vector2.ZERO
	run_requested = false
	jump_requested = false
	ability.reset()
	roll.reset()
	dodge.reset()
	slide.reset()
	# A knocked-down fighter is not mid-swing and not staggered: the stance reset
	# clears the attack progress, the guard and the flinch in one place.
	combat.stagger_time = 0.0
	reset_stance()
	_restore_body_collision()
	_reset_rig_glide()
	rig.visible = true
	_begin_downed_state()
	# The blow that puts a body down is the body's own: the first moan, then the
	# bleed clock's ragged ones (`VoiceEmitter.tick`).
	if _voice != null:
		_voice.downed()
	downed_started.emit(slot)

## Ghost of the Warband: stand back up out of DOWNED with the contract's share of
## max health. The arena's `revive()` stays the respawn path for a body that
## actually died; these two never run for the same body at once.
func revive_from_downed(fraction: float = WarbandContracts.REVIVE_HEALTH_FRACTION) -> void:
	if not downed or not alive:
		return
	downed = false
	downed_seconds = 0.0
	downed_by = -1
	downed_threat_known = false
	safe_anchor_known = false
	health_state = WarbandContracts.HealthState.ALIVE
	health = DownedRules.revive_health(max_health, fraction)
	velocity = Vector3.ZERO
	combat.stagger_time = 0.0
	reset_stance()
	roll.reset()
	dodge.reset()
	# The blow that put this body down also set its flinch; a fighter standing up
	# into a full-length stagger would refuse every input for a second.
	rig.set_hit_react(0.0)
	_restore_body_collision()
	_reset_rig_glide()
	rig.visible = true
	_clear_downed_state()
	if _voice != null:
		_voice.stood_up()
	downed_ended.emit(slot)

## A hostile this body put down: a line about it, if it feels like one. Called by
## the mob's own death through `Voice.kill_quip`, which is the only record a kill
## leaves behind - the mob names its killer by instance id. The roll, the cooldown
## and the choice of take are the emitter's (`VoiceLibrary.VOICES.player.kill`).
func voice_kill_quip() -> void:
	if _voice == null or not (is_local or authoritative):
		return
	_voice.killed()


## Something hostile has just come into this body's reach and it has picked it:
## the party's one aggrieved line. Whether it is said at all is the row's
## business (`VoiceLibrary.SQUAD.aggro`: one roll in a hundred), so the caller
## asks on every engagement and a fight is usually silent. The line is placed at
## the body, so a squadmate shouting across the field is heard from where it
## stands - and not heard at all past the row's `max_distance`.
func voice_aggro() -> bool:
	if _voice == null or not (is_local or authoritative):
		return false
	return _voice.say("aggro")


## Where the blow that put this body down came from. `receive_melee` is the one
## funnel that knows the attacker's body, so the crawl's bearing comes from it.
func note_threat(point: Vector3) -> void:
	if point.is_finite():
		downed_threat = point
		downed_threat_known = true

## The safe anchor the crawl biases toward. A non-finite point clears it.
func set_safe_anchor(point: Vector3) -> void:
	safe_anchor = point
	safe_anchor_known = point.is_finite()

func clear_safe_anchor() -> void:
	safe_anchor_known = false

## The point this body drags itself toward while downed: away from the blow,
## biased toward the safe anchor. Its own position when it has nothing to crawl
## away from, or when it is not downed at all.
func downed_crawl_target() -> Vector3:
	if not downed:
		return global_position
	return DownedRules.crawl_target(global_position, downed_threat, downed_threat_known,
		safe_anchor, safe_anchor_known)

## Ghost of the Warband: one frame of the downed crawl, moved through the body's
## own capsule so a wall, tree or crate stops it instead of being ghosted
## through. Never moves a body that is not downed.
func crawl_step(point: Vector3, speed: float, delta: float) -> void:
	if not downed or not alive:
		return
	var travel := Vector3(point.x - position.x, 0.0, point.z - position.z)
	var distance := travel.length()
	var step_length := minf(distance, maxf(speed, 0.0) * maxf(delta, 0.0))
	if step_length <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	travel = travel / distance * step_length
	# `move_and_slide` advances by `velocity * delta`, so the velocity that
	# produces exactly this frame's step is the step over the frame's delta.
	velocity.x = travel.x / maxf(delta, 0.0001)
	velocity.z = travel.z / maxf(delta, 0.0001)
	velocity.y = 0.0
	move_and_slide()
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)

## The one death path: the respawn clock, the death stat, the hidden corpse and
## the kill credit. A finisher, the bleed clock and a lethal blow all land here,
## so a body that dies is a body that died the same way whatever put it down.
func _die(source_id: int) -> void:
	health = 0.0
	alive = false
	downed = false
	downed_seconds = 0.0
	downed_threat_known = false
	health_state = WarbandContracts.HealthState.DEAD
	respawn = 3.0
	deaths += 1
	combat.stop()
	reset_stance()
	roll.reset()
	_store_body_collision()
	_reset_rig_glide()
	# The drip stops on the frame the body dies. A campaign body then keeps the
	# ground: its model stays in the lie it fell in, so a corpse is a thing you
	# walk past rather than a body that winked out of the world.
	if warband_death:
		_hold_corpse()
	else:
		_clear_downed_state()
		rig.visible = false
	if _voice != null:
		_voice.stood_up()
	killed.emit(slot, source_id)

func try_ability(slot: int = 0) -> Dictionary:
	if not authoritative or not alive or downed:
		return {"ok": false, "message": "You are down."}
	return ability.activate(slot)

func press_jump(roll_requested: bool) -> void:
	var grounded := is_on_floor()
	peek_requested = false
	if not alive or downed or ability.active or not cover.prepare_jump():
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
	if not authoritative or not alive or downed:
		return
	if pressed:
		combat.start_block(forward)
	else:
		combat.stop_block()

func receive_melee(amount: float, source_id: int, attacker_position: Vector3, headshot: bool = false) -> int:
	if not authoritative or not alive or source_id == slot:
		return Combat.DEFENSE_NONE
	if downed:
		# Ghost of the Warband: a body on the ground cannot guard, so the blow is
		# not a defence roll at all. `take_damage` owns the downed rule and turns
		# it into the contract's finisher check - a heavy strike ends the body, a
		# light one is shrugged off.
		take_damage(amount,source_id,headshot,false)
		return Combat.DEFENSE_NONE
	# The blow's own bearing, kept for the crawl if it puts this body down.
	note_threat(attacker_position)
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

## Host-authoritative blink used by the dagger backstab. The body appears at
## `point` facing `yaw` on the same simulation tick; the interpolation buffer
## is emptied so a remote peer snaps to the new pose instead of sliding there.
func teleport_to(point: Vector3, yaw: float) -> void:
	if not authoritative:
		return
	global_position = point
	velocity = Vector3.ZERO
	_timeline.reset_to(point,Vector3.ZERO,yaw)
	if is_instance_valid(rig):
		rig.global_basis = Basis(Vector3.UP, yaw)

func try_step(direction: Vector3) -> bool:
	if not authoritative and not predicting:
		return false
	if not alive or combat.stagger_time > 0.0 or ability.active:
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
	elif alive and not downed and is_on_floor() and not roll.active and not ability.active and cover.try_enter(preferred_direction):
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

## The point other bodies aim at, and the point this body's own wounds open. It
## rides the body's own height, so a mob reaches for the chest that is actually
## there instead of a height only the tallest man has.
func get_aim_position() -> Vector3:
	return global_position + Vector3(0,1.2 * body_scale(),0)

## This body's height as a fraction of the authored rig. Presentation only: the
## capsule, the health pool, reach and speeds are the same for every mercenary,
## which is the warband's whole contract.
func body_scale() -> float:
	return clampf(float(appearance.get("height", 1.0)), 0.80, 1.20)

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

## Apply a seat's worn trinket kit. Recomputes the maxima and clamps the live
## pools so a mid-match ring change cannot leave an over-full bar.
func apply_trinkets(kit: Dictionary) -> void:
	if is_instance_valid(rig):
		rig.apply_trinkets(kit)
	_sync_trinket_limits()

func _sync_trinket_limits() -> void:
	if not is_instance_valid(rig):
		return
	trinkets = rig.trinkets.duplicate()
	trinket_stats = rig.trinket_stats.duplicate()
	max_health = TrinketStats.max_health(MAX_HEALTH, trinket_stats)
	max_stamina = TrinketStats.max_stamina(Stamina.MAX, trinket_stats)
	health = minf(health, max_health)
	stamina = minf(stamina, max_stamina)
	combat.stagger_scale = TrinketStats.stagger_scale(trinket_stats)

func get_trinket_stats() -> Dictionary:
	return trinket_stats

## Off-hand skulls: the wearer refills on every kill this body makes.
func apply_kill_refill() -> void:
	var heal := float(trinket_stats.get("heal_on_kill", 0.0))
	var gain := float(trinket_stats.get("stamina_on_kill", 0.0))
	if heal > 0.0:
		health = minf(max_health, health + heal)
	if gain > 0.0:
		stamina = minf(max_stamina, stamina + gain)

## Start the Energy Shield ward from a successful activation.
func start_ward(definition: Dictionary) -> void:
	var effect := AbilityRules.ward(definition)
	if effect.is_empty():
		return
	ward_seconds = float(effect.get("seconds", 60.0))
	ward_absorb = clampf(float(effect.get("absorb", 0.5)), 0.0, 1.0)
	ward_stamina_scale = maxf(1.0, float(effect.get("stamina_scale", 2.0)))
	rig.set_ward(true)

## Returns the damage that still reaches health after the ward's swap.
func _absorb_with_ward(applied: float) -> float:
	if ward_seconds <= 0.0 or applied <= 0.0:
		return applied
	var price: float = applied * ward_absorb * ward_stamina_scale
	var paid: float = minf(price, stamina)
	if paid <= 0.0:
		return applied
	stamina -= paid
	return applied - paid / ward_stamina_scale

func _tick_ward(delta: float) -> void:
	if ward_seconds <= 0.0:
		return
	ward_seconds = maxf(0.0, ward_seconds - delta)
	if ward_seconds <= 0.0:
		rig.set_ward(false)

func take_damage(amount: float, source_id: int, headshot: bool = false, react: bool = true) -> void:
	if not authoritative or not alive or source_id == slot:
		return
	# Ghost of the Warband: one scale, at the funnel, from the victim's bubble.
	amount = WarbandDamage.scale(amount, self)
	if downed:
		# Ghost of the Warband: a blow on a downed body is a finisher, not damage.
		# A campaign body is finished by any blow that lands on it - that is the
		# price of lying in the dirt - while a body outside the campaign keeps the
		# contract's own threshold, where chip damage (including the 10% a
		# passive-simulated fight lands) is shrugged off.
		if warband_death or DownedRules.finishes(max_health, amount):
			_die(source_id)
		return
	_cancel_consumable()
	var applied: float = amount * Hitbox.damage_multiplier(headshot) \
		* (1.0 - rig.damage_reduction(headshot))
	applied = _absorb_with_ward(applied)
	# Ghost of the Warband: the contract's single 10% overkill authority decides
	# whether this hit leaves the body standing, drops it DOWNED or kills it.
	# Nothing here re-derives the threshold.
	var outcome: Dictionary = DownedRules.resolve(health, max_health, applied)
	health = maxf(0.0, float(outcome.health))
	DamageNumbers.spawn(get_parent(),global_position,applied,"self" if is_local else "hit",headshot,health <= 0.0)
	BloodFx.wound(self,rig,get_aim_position(),applied,headshot,health <= 0,1.0)
	if react:
		var seconds: float = combat.stagger_from_damage(applied,max_health)
		rig.set_hit_react(seconds)
		dodge.reset()
	if bool(outcome.died):
		# Nothing in the campaign is killed outright: the wood puts a body on its
		# chest and the bleed clock is the only thing here that carries a body off.
		if warband_death:
			enter_downed(source_id)
		else:
			_die(source_id)
		return
	if bool(outcome.downed):
		enter_downed(source_id)
		return
	# Still standing, so the blow is heard: the share of the pool it took decides
	# whether this is a grunt or the line a player remembers (`VoiceEmitter`).
	# A blow that puts a body down never gets here - going down has its own voice,
	# and two lines on one frame would be one cut off.
	if _voice != null:
		_voice.damage(applied / maxf(max_health, 1.0))

func try_consume(kind: String) -> bool:
	if not authoritative or not alive or downed or consume_kind != "":
		return false
	if not Archer.CONSUMABLE_DATA.has(kind) or health >= max_health-0.001:
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
					health = minf(max_health,health+float(data.heal))
	if _heal_remaining > 0.0:
		var amount := minf(_heal_rate*delta,_heal_remaining)
		health = minf(max_health,health+amount)
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
	if not authoritative and not predicting:
		return
	if not alive:
		# Only the authority owns the respawn clock; a replica learns its state
		# from the snapshots it is handed.
		if authoritative and not persistent_death:
			respawn = maxf(0,respawn-delta)
			if respawn <= 0:
				revive()
		return
	if downed:
		# Ghost of the Warband: a downed body keeps its ground and its collision
		# but has no intent - nothing here advances a swing, an ability or a
		# step. The bleed clock is the only thing that ticks, and the crawl node
		# (if the scene gave this body one) owns whatever motion it makes.
		if authoritative:
			downed_seconds += delta
			if DownedRules.bled_out(downed_seconds):
				_die(downed_by)
		return
	input_age += delta
	if authoritative:
		# Every authoritative body consumes its queued intent, including the
		# host's own fighter (which queues one local frame per tick with no
		# sequence number). `frame_driven` only decides whether a tick with an
		# empty queue may hold the pose.
		_frame_consumed = _consume_input_frame()
		_advance_consumable(delta)
		if consume_kind != "":
			move_direction = Vector2.ZERO
			run_requested = false
			jump_requested = false
			peek_requested = false
			combat.stop_block()
	roll.advance(delta,is_on_floor())
	dodge.advance(delta,is_on_floor())
	if authoritative:
		ability.advance(delta)
		_tick_ward(delta)
	if ability.active:
		# A melee skill keeps the walking intent, but sprint, jump, peek and
		# slide stay off for the duration. Any other skill plants the fighter.
		run_requested = false
		jump_requested = false
		peek_requested = false
		slide.reset()
		if not ability.allows_movement():
			move_direction = Vector2.ZERO
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
	var motion := {}
	if authoritative and frame_driven and not _frame_consumed:
		# A tick the peer that owns this body sent no frame for. Repeating the
		# last intent would walk the body ahead of the frames that own it, and
		# every invented frame comes back as a correction that yanks its owner
		# forward. A body this scene drives itself (the host's own fighter, a
		# bot, a fixture) has no frame stream and simulates every tick.
		_hold_position(delta)
	else:
		motion = _resolve_motion(delta,actors,simulation_tick)
		_integrate(delta,motion,actors,true)
		# The model trails a correction by a few frames while the body is exact.
		# Both the predicting peer and the authority pose their rig here.
		_glide_rig(delta)
		if authoritative:
			# Client frames that arrived behind this tick's one are the same kind
			# of intent: simulate each exactly once, oldest first, so a host that
			# runs slower than its peer never falls permanently behind the input
			# it was sent. The acknowledgement names the newest frame consumed.
			_drain_input_backlog(motion,actors)
		# The acknowledgement names the state the frame that consumed this
		# client frame produced, so its owner replays from exactly here.
		_commit_acknowledgement()
	if not authoritative:
		# The owning peer integrates its own translation; its rig stays on the
		# authoritative animation state so prediction never invents a pose.
		_prediction.push(motion)
		return
	rig.set_cover(cover.active,cover.normal,cover.crouch_amount,cover.peeking,cover.lean)
	rig.set_slide(slide.progress if slide.active else -1.0,slide.direction)
	rig.set_step(dodge.progress if dodge.active else -1.0,dodge.direction)
	rig.set_locomotion(_last_motion,is_on_floor() and not roll.active)
	rig.set_roll(roll.progress if roll.active else -1.0,roll.direction)
	combat.set_motion(_last_motion,_last_running or slide.active or roll.active or dodge.active,is_on_floor() and not roll.active)
	combat.advance(delta)
	_bloody_feet.update(delta,self,rig)
	_footsteps.update(delta,self,rig,is_local)

## One tick's movement intent: the walk target plus every velocity the state
## machines produced, in the single order the authority and a predicting peer
## share. The record is what `_integrate` consumes, so a rollback can replay a
## frame without advancing a state machine twice.
func _resolve_motion(delta: float, actors: Array, simulation_tick: int) -> Dictionary:
	var direction := Vector3(move_direction.x,0,move_direction.y)
	var slide_velocity: Vector3 = slide.step(delta,self,cover,direction,roll.active)
	var running: bool = run_requested and (cover.active or not cover.crouched and not cover.crouch_requested) and not _exhausted and stamina > 1 and direction.length_squared() > 0.01 and not ability.active
	var stamina_rate: float = 0.0 if combat.blocking or ability.active else (-Stamina.SPRINT_DRAIN_PER_SECOND if running or slide.active else Stamina.REGEN_PER_SECOND * TrinketStats.stamina_regen(trinket_stats))
	stamina = clampf(stamina + delta * stamina_rate,0,max_stamina)
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
	var walk_speed: float = (2.2 if cover.crouched or cover.crouch_requested else 8.5 if running else 5.5) * float(rig.move_scale())
	var committed: Variant = null
	if slide.active:
		committed = slide_velocity
	elif was_in_cover:
		committed = cover_velocity
	if dodge.active:
		var step_velocity: Vector3 = dodge.velocity()
		committed = step_velocity
	if roll.active:
		committed = Vector3(roll.direction.x * DodgeRoll.SPEED,0.0,roll.direction.z * DodgeRoll.SPEED)
	var record := {"dir": Vector2(direction.x,direction.z), "run": running, "speed": walk_speed,
		"replace": committed, "cap": 0.0,
		"separation": not was_in_cover and not roll.active,
		"jump": jump_requested, "takeoff": roll.takeoff_pending, "delta": delta,
		# The pose this frame started from: the authority reports the same pose
		# for the same frame, so the two are directly comparable.
		"pos": position}
	_last_running = running
	if ability.active:
		# Committed travel replaces the walk while it lasts; otherwise a moving
		# melee skill keeps the normal velocity and a planted one holds still.
		jump_requested = false
		var ability_velocity: Vector3 = ability.velocity()
		if not ability_velocity.is_zero_approx():
			record["replace"] = ability_velocity
		elif not ability.allows_movement():
			record["replace"] = Vector3.ZERO
		else:
			# Hand the dash back to the feet: the walk target caps the residual
			# travel instead of gliding a lane past the authored distance.
			record["cap"] = walk_speed
	record["jump"] = jump_requested
	return record

## Applies one motion record. `live` is the running simulation: replay passes
## false so a correction re-moves the body without advancing any clock.
func _integrate(delta: float, record: Dictionary, actors: Array, live: bool) -> void:
	var committed: Variant = record.get("replace")
	if committed != null:
		var fixed: Vector3 = committed
		velocity.x = fixed.x
		velocity.z = fixed.z
	else:
		var aim_direction: Vector2 = record.dir
		var walk_speed := float(record.get("speed",WALK_SPEED))
		velocity.x = move_toward(velocity.x,aim_direction.x*walk_speed,35*delta)
		velocity.z = move_toward(velocity.z,aim_direction.y*walk_speed,35*delta)
	if bool(record.get("separation",false)):
		var separation := _separation_velocity(actors)
		velocity.x += separation.x
		velocity.z += separation.z
	var cap := float(record.get("cap",0.0))
	if cap > 0.0:
		var walked := Vector2(velocity.x,velocity.z).limit_length(cap)
		velocity.x = walked.x
		velocity.z = walked.y
	if bool(record.get("jump",false)):
		velocity.y = 7.0
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 20*delta
	if bool(record.get("takeoff",false)):
		velocity.y = maxf(velocity.y,6.0)
	if live:
		jump_requested = false
		roll.takeoff_pending = false
	var before := position
	# A replay is arithmetic, never a physics move. `move_and_slide()` outside
	# the physics frame integrates against the *idle* frame's delta and asks the
	# physics server about a body state its last tick produced, so replaying a
	# handful of frames inside one correction multiplies the travel by however
	# long the render frame took and launches the body — the classic
	# re-simulation trap. Integrate the record's velocity directly instead.
	if live:
		move_and_slide()
		# The lunge cuts the lane it just crossed, measured after the move.
		if authoritative and ability.active:
			_sweep_ability_path()
	else:
		# A replay is a swept move, not a physics step: `move_and_collide` takes
		# the motion explicitly, so it collides exactly like the live move
		# without depending on which frame the callback ran in, and sliding the
		# remainder along the surface keeps a blocked body where its owner's
		# blocked body was.
		var motion := velocity*delta
		if motion.length_squared() > 0.0000001:
			var collision := move_and_collide(motion)
			if collision != null:
				var slid := motion.slide(collision.get_normal())
				if slid.length_squared() > 0.0000001:
					move_and_collide(slid)
	position.x = clampf(position.x,-bounds,bounds)
	position.z = clampf(position.z,-bounds,bounds)
	var actual := (position-before)/maxf(delta,0.0001)
	if live:
		slide.after_move(self,actual)
	_last_motion = actual

## Draws the model from its pre-correction pose to the corrected one. The body
## itself is already authoritative; only the presentation lags for a few frames.
## Anchors the drawn model to the body again and forgets any outstanding glide.
## Called whenever this peer stops predicting (death, cover) and whenever the
## anchor could not possibly be a glide: a stale anchor is what leaves the model
## standing at an old corpse while the body is somewhere else.
func _reset_rig_glide() -> void:
	_rig_offset = Vector3.ZERO
	_rig_drawn = global_position
	_rig_drawn_ready = false
	if is_instance_valid(rig) and not rig.position.is_zero_approx():
		rig.position = Vector3.ZERO


func _glide_rig(delta: float) -> void:
	var wanted := global_position + _rig_offset
	if not _rig_drawn_ready:
		# First correction of a run: begin where the model already stood, so the
		# correction cannot hop it.
		_rig_drawn = rig.global_position
		_rig_drawn_ready = true
	_rig_drawn = _rig_drawn.move_toward(wanted,RIG_DRAW_STEP)
	_rig_offset = _rig_offset.move_toward(Vector3.ZERO,RIG_GLIDE_SPEED*maxf(delta,0.0))
	if _rig_offset.is_zero_approx():
		_rig_offset = Vector3.ZERO
	if _rig_drawn.distance_squared_to(global_position) < 0.000001:
		_rig_drawn = global_position
		_rig_drawn_ready = false
		rig.position = Vector3.ZERO
		return
	# A model this far from its body is not gliding, it is stale: anchor it.
	if _rig_drawn.distance_to(global_position) > RIG_DRAW_LIMIT:
		_reset_rig_glide()
		return
	rig.position = to_local(_rig_drawn)

## -- prediction and reconciliation ---------------------------------------

## The authority's acknowledgement point: the pose produced by the frame that
## consumed the newest client input. A correcting peer replays its own later
## frames from exactly here and compares its own frame `ack + 1` against it.
func _commit_acknowledgement() -> void:
	if _pending_seq < 0:
		return
	ack_seq = _pending_seq
	ack_position = position
	ack_velocity = velocity
	_pending_seq = -1

## Host side of the movement stream: queue the client's simulated frame. The
## authority pops exactly one per tick in `_consume_input_frame()`, so the pose
## it acknowledges always belongs to the same numbered frame the client
## recorded, and the frames behind the newest fill any gap a lost datagram left.
func accept_network_input(direction: Vector2, running: bool, seq: int = -1, view: int = -1,
		history: Array = []) -> void:
	if not direction.is_finite():
		return
	if view >= 0:
		view_tick = view
	if seq >= 0:
		frame_driven = true
		# A frame the authority has already simulated can never be a fresh
		# intent: `unreliable_ordered` and a repeated send can both re-deliver.
		if seq <= ack_seq:
			return
		# Frames repeated behind this one fill the gaps a lost datagram left.
		for entry in history:
			if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 3:
				continue
			var past := int(entry[0])
			if past <= ack_seq or past >= seq:
				continue
			if not _input_queue.is_empty() and past <= int(_input_queue[-1].seq):
				continue
			_queue_input_frame(Vector2(entry[1]),bool(entry[2]),past)
		if not _input_queue.is_empty() and seq <= int(_input_queue[-1].seq):
			return
	_queue_input_frame(direction,running,seq)

func _queue_input_frame(direction: Vector2, running: bool, seq: int) -> void:
	_input_queue.append({"dir": direction.limit_length(), "run": running, "seq": seq})
	while _input_queue.size() > INPUT_QUEUE_LIMIT:
		# A stalled or saturated stream: keep the freshest frames so the body
		# follows the input the player is actually holding.
		_input_queue.pop_front()

## One frame of client intent becomes this tick's movement, and the frame it
## came from becomes the acknowledgement the next snapshot carries.
func _consume_input_frame() -> bool:
	if _input_queue.is_empty():
		return false
	var frame: Dictionary = _input_queue.pop_front()
	_apply_input_frame(frame)
	return true

## A tick with no client frame: keep the pose. Gravity and the floor still
## settle the body, and the walk velocity is preserved so the next frame
## continues from the momentum the peer's own body has.
func _hold_position(delta: float) -> void:
	velocity.y = -1.0 if is_on_floor() else velocity.y-20.0*delta
	var held_x := velocity.x
	var held_z := velocity.z
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	velocity.x = held_x
	velocity.z = held_z

## Frames still queued after this tick's own: motion only. Their clocks have
## already advanced this tick, so they are integrated the way a correction
## replays a frame — translation, no state machine, no second jump.
func _drain_input_backlog(motion: Dictionary, actors: Array) -> void:
	while not _input_queue.is_empty():
		var frame: Dictionary = _input_queue.pop_front()
		_apply_input_frame(frame)
		var record := motion.duplicate()
		record["dir"] = frame.dir
		record["jump"] = false
		record["takeoff"] = false
		_integrate(float(record.get("delta",1.0/60.0)),record,actors,false)

func _apply_input_frame(frame: Dictionary) -> void:
	move_direction = frame.dir
	run_requested = bool(frame.run)
	input_age = 0.0
	var seq := int(frame.seq)
	if seq > ack_seq:
		_pending_seq = seq

## This peer's own input for the frame it is about to simulate.
func update_input(direction: Vector2, running: bool, view: int = -1) -> void:
	move_direction = direction.limit_length()
	run_requested = running
	input_age = 0.0
	if view >= 0:
		view_tick = view

func latest_prediction_seq() -> int:
	return _prediction.latest_seq()

## The newest `count` unacknowledged frames, oldest first, as `[seq, dir, run]`
## blocks. Each movement packet repeats them so one lost datagram cannot leave
## the authority permanently short of this peer's travel.
func input_history(count: int = INPUT_REDUNDANCY) -> Array:
	var out: Array = []
	var records: Array = _prediction.records
	var start := maxi(0,records.size() - maxi(count,0) - 1)
	for index in range(start,records.size() - 1):
		var record: Dictionary = records[index]
		out.append([int(record.seq),Vector2(record.dir),bool(record.get("run",false))])
	return out

## Client-side mirror of the locomotion intents: the owning peer applies the
## same state change it just sent, so a jump, roll, dodge or cover attach starts
## on the frame the key went down instead of a round trip later. Combat, kits,
## consumables and skills stay authority-only, so no client ever guesses a hit.
func predict_action(action: String, value: Variant) -> void:
	if not predicting or not alive:
		return
	match action:
		"jump":
			if typeof(value) == TYPE_BOOL:
				press_jump(value)
		"step":
			if typeof(value) != TYPE_VECTOR3:
				return
			var direction: Vector3 = value
			if not direction.is_finite() or absf(direction.y) > 0.01:
				return
			var flat := Vector3(direction.x,0,direction.z)
			if absf(flat.length()-1.0) > 0.1:
				return
			try_step(flat)


## One frame of the owning peer's own movement: the same `step()` the authority
## runs for this body, minus damage, combat clocks, consumables and kits. The
## resolved motion frame is recorded for replay.
func predicted_step(delta: float, actors: Array) -> void:
	if not prediction_active():
		return
	input_age = 0.0
	if not _pending_state.is_empty():
		var state := _pending_state
		_pending_state = {}
		reconcile(state,actors)
	step(delta,actors)


## True while this peer owns and integrates the body itself. Cover is a
## host-driven stance: the attached slide, the crouch transition and the exposure
## timing all belong to the authority, so the body is rendered from its replicated
## state until it detaches.
func prediction_active() -> bool:
	return predicting and alive and not cover.active

## Rebuilds the present-day pose from the authority's acknowledgement plus the
## frames it has not seen yet. Skipping the replay when the prediction already
## matched keeps a steady stream from nudging the body at all.
func reconcile(state: Dictionary, actors: Array) -> void:
	var packed: Variant = state.get("ack",null)
	if typeof(packed) != TYPE_ARRAY or (packed as Array).size() < 3:
		return
	var block: Array = packed
	var ack := int(block[0])
	if ack < 0:
		return
	# One acknowledgement is reconciled once. Every snapshot the authority sends
	# while it has no fresh input repeats the last frame it consumed, and a
	# reordered datagram can re-deliver an older one: correcting for it again
	# would apply the same verdict twice.
	if ack <= int(_prediction.acked):
		return
	var pose: Vector3 = block[1]
	var sent_velocity: Vector3 = block[2]
	# The authority's pose is the one *after* frame `ack`; this peer recorded the
	# pose its own frame `ack + 1` started from, so the two name the same instant.
	var predicted: Dictionary = _prediction.record_at(ack + 1)
	if predicted.is_empty():
		_prediction.acknowledge(ack)
		prediction_drift = 0.0
		return
	prediction_drift = (predicted.get("pos",pose) as Vector3).distance_to(pose)
	if history.size() < 64:
		history.append({"ack":ack, "drift":prediction_drift, "predicted":predicted.get("pos",pose),
			"actual":pose, "latest":_prediction.latest_seq()})
	if prediction_drift <= reconcile_tolerance():
		_prediction.acknowledge(ack)
		return
	prediction_corrections += 1
	# The verdict is a displacement, not a pose: `pose` minus the pose this peer
	# recorded for the same instant is how far its own simulation is from the
	# authority's. Applying that to the present body corrects the error without
	# replaying the unacknowledged window, whose re-swept path can never match
	# the collisions and slopes the live frames actually met — every mismatch
	# there came back as a pop of the whole window. The window is dropped so the
	# next acknowledgement compares against the corrected path.
	var shift: Vector3 = pose - (predicted.get("pos",pose) as Vector3)
	if not _rig_drawn_ready:
		# Anchor the model to the pose it is actually drawn at *before* the body
		# takes the authority's: anchoring after the shift would hop it.
		_rig_drawn = position
		_rig_drawn_ready = true
	position += shift
	velocity = sent_velocity
	_prediction.acknowledge(_prediction.latest_seq())
	if shift.length() > RIG_DRAW_LIMIT:
		# A revive, a blink, a hatch rescue: the body changed place, so the model
		# does too. There is nothing to glide over.
		_reset_rig_glide()
		return
	# The model glides over what the body took in one frame.
	_rig_offset = (_rig_offset - shift).limit_length(RIG_GLIDE_LIMIT)

## The disagreement worth correcting: a couple of frames of the body's own
## travel, so a tick of phase between the peer's frame numbering and the
## authority's tick is absorbed instead of snapping the body backwards.
func reconcile_tolerance() -> float:
	var travel: float = _last_motion.length() * get_physics_process_delta_time()
	return clampf(maxf(RECONCILE_DISTANCE,travel*RECONCILE_SLACK_FRAMES),
		RECONCILE_DISTANCE,RECONCILE_MAX_DISTANCE)

## How far behind the host this peer was drawing the world when it acted, in
## ticks. The host rewinds its hitboxes by exactly this much.
func lag_ticks(server_tick: int, limit: int) -> int:
	if view_tick < 0 or server_tick < 0:
		return 0
	return clampi(server_tick - view_tick,0,limit)

## A travelling skill sweeps the lane it has just crossed: after the body moved
## for the tick, every body inside the path arc takes one hit. The activation's
## victim set is shared with the closing thrust beat, so no body is hit twice.
func _sweep_ability_path() -> void:
	var effect: Dictionary = ability.active_definition.get("effect", {})
	if not bool(effect.get("path_damage", false)):
		return
	if ability.elapsed > ability.travel_seconds + 0.02:
		return
	combat.ability_strike(float(effect.get("path_radius", 1.0)),
		float(effect.get("path_arc_degrees", 180.0)),
		AbilityRules.damage_for(ability.active_definition,rig),
		float(effect.get("stagger", 0.0)),false,false,ability.active_victims)

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
		# Ghost of the Warband: a Downed body is not a threat and not a target.
		# Without this an AI squad executes its own crawling allies with the next
		# swing, which makes the whole Downed state meaningless.
		if other == self or not other.alive or other.get("downed") == true:
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
		focus_code = FOCUS_CODES.get(str(rig.focus_kind),2)
	bits |= (focus_code & 7) << 5
	bits |= (int(rig.focus_index) & 1) << 8
	bits |= (int(rig.shield_variant) & 3) << 9
	return bits

func snapshot() -> Dictionary:
	var state := {"slot":slot,"peer":peer_id,"position":position,"velocity":velocity,
		"health":health,"maxh":max_health,"ward":ward_seconds,"alive":alive,"kills":kills,"deaths":deaths,"respawn":respawn,"bow":rig.bow_index,"armor":rig.armor_bits() | (ArmorData.SHIELD_BIT if rig.shield_equipped else 0),"sword":rig.sword_index,"weapon":rig.weapon,"gear":gear_bits(),
		"weapon_blood":weapon_blood,
		"stamina":stamina,"ability":ability.pack_snapshot(),
		"animation":rig.pack_animation_state(rig.get_animation_state()),"progress":combat.attack_progress,"movement":combat.movement_mode,
		"aim":combat.aim_point,"grounded":is_on_floor(),"cover":cover.pack_snapshot()}
	# Only a body driven by a remote peer carries an acknowledgement: the pose
	# its owner replays from plus the frame that pose precedes.
	if ack_seq >= 0:
		# One positional block, like every other wire value: the acknowledgement
		# rides inside the clamped datagram beside an already-full snapshot.
		state["ack"] = [ack_seq, ack_position, ack_velocity]
	return state

func apply_snapshot(state: Dictionary, tick: int = -1, actors: Array = []) -> void:
	# A bot seat has no peer: peer 0 is the wire form of `is_bot`.
	var incoming_bot := int(state.peer) == 0
	var replaced := peer_id != int(state.peer) or is_bot != incoming_bot
	peer_id = int(state.peer)
	is_bot = incoming_bot
	# The name is static for the match and arrives with the roster, not the tick.
	if state.has("name"):
		display_name = str(state.name)
	var previous_health := health
	var previous_weapon_blood := weapon_blood
	var had_pose := _received_pose
	_ingest_pose(state,tick,actors,replaced)
	_received_pose = true
	health = state.health
	max_health = float(state.get("maxh",max_health))
	ward_seconds = float(state.get("ward",ward_seconds))
	if is_instance_valid(rig):
		rig.set_ward(ward_seconds > 0.0)
	stamina = float(state.get("stamina",stamina))
	ability.apply_snapshot(state.get("ability",{}))
	weapon_blood = float(state.get("weapon_blood",weapon_blood))
	var fresh_weapon_blood := 0.0
	if not authoritative and had_pose and not replaced and weapon_blood-previous_weapon_blood > 0.01:
		fresh_weapon_blood = weapon_blood-previous_weapon_blood
	if not authoritative and had_pose and not replaced and previous_health-health > 0.01:
		DamageNumbers.spawn(get_parent(),global_position,previous_health-health,"self" if is_local else "hit",false,health <= 0.0)
		BloodFx.wound(self,rig,get_aim_position(),previous_health-health,false,health <= 0.0,1.0)
		# The peer that does not simulate this body still has to hear its own
		# voice: the host applied the blow, the ears are here. A blow that leaves
		# the body at zero is the downed branch below, not a grunt.
		if is_local and _voice != null and health > 0.0:
			_voice.damage((previous_health-health) / maxf(max_health, 1.0))
	alive = state.alive
	# Ghost of the Warband: the wire carries no separate downed flag. A body at
	# zero health that is still alive is exactly what the host wrote when a blow
	# only overkilled by the contract's threshold, so a replica reads it back
	# instead of standing up a body the authority has on the ground.
	var incoming_downed: bool = alive and health <= 0.0
	if incoming_downed != downed:
		downed = incoming_downed
		downed_seconds = 0.0
		if not alive:
			health_state = WarbandContracts.HealthState.DEAD
		elif downed:
			health_state = WarbandContracts.HealthState.DOWNED
		else:
			health_state = WarbandContracts.HealthState.ALIVE
		# The pose and the drip follow the flag here too. A remote body has to
		# lie on the ground and bleed like the one the host put down, and the
		# wire - which carries no presentation flag - is enough to say so.
		if downed:
			_begin_downed_state()
			# The guest's own body: it went down on the host, it moans here.
			if is_local and _voice != null:
				_voice.downed()
			downed_started.emit(slot)
		else:
			_clear_downed_state()
			if _voice != null:
				_voice.stood_up()
			downed_ended.emit(slot)
	# A campaign death leaves a corpse on every screen, not a body that disappears
	# the instant the authority says it is over - and a body that joined the scene
	# already dead is lying on the ground like every other one. Idempotent.
	if not alive and warband_death:
		_hold_corpse()
	kills = state.kills
	deaths = state.deaths
	respawn = state.respawn
	rig.visible = alive or warband_death
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
		var focus_code := (gear >> 5) & 7
		var focus_kind := str(FOCUS_KINDS.get(focus_code,""))
		# Arm the off hand before the weapon mode so a replicated dual loadout
		# can actually enter dual; the staff is restored last because set_sword()
		# deliberately stows it.
		rig.set_off_focus(focus_kind,(gear >> 8) & 1,focus_code != 0)
		rig.set_shield_variant((gear >> 9) & 3)
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
		_reset_rig_glide()
		reset_stance()
	rig.set_cover(cover.active,cover.normal,cover.crouch_amount,cover.peeking,cover.lean)
	rig.set_locomotion(velocity,bool(state.grounded) and Archer.animation_roll(state.animation) < 0)
	rig.apply_animation_state(state.animation)
	combat.attack_progress = state.progress
	combat.movement_mode = state.movement
	combat.aim_point = state.aim
	combat.blocking = rig.is_blocking()
	# Guard timing stays host-authoritative; a replica HUD shows GUARDING rather
	# than inventing a parry window from snapshot arrival time.
	combat.block_time = 0.0
	if prediction_active():
		# The owning peer never advances the combat clock, so the only movement
		# gate it cannot derive locally — a stagger — is read off the pose it
		# was handed. STAGGER carries the remaining reaction in its time field,
		# and apply_animation_state() has already turned it into _hit_react.
		combat.stagger_time = rig._hit_react

## Routes one authoritative pose. A predicting body reconciles against the
## acknowledgement; every other body feeds the delay buffer its render reads.
func _ingest_pose(state: Dictionary, tick: int, actors: Array, replaced: bool) -> void:
	var active := prediction_active()
	if active != _predicted_last:
		# Handing the body between the local prediction and the buffered view:
		# restart the buffer where the body actually stands, so neither mode
		# starts by dragging it. The drawn model is anchored here too, or the
		# pose it was drawn at before a death would still be chasing it.
		_reset_rig_glide()
		_timeline.reset_to(position,velocity,0.0,_pose_tick(tick),_pose_now())
		_timeline_ready = false
		_predicted_last = active
	var target: Vector3 = state.position
	var sent_velocity: Vector3 = state.velocity
	if active:
		_pending_state = state
		return
	_pending_state = {}
	_timeline.floor_delay_ticks = clampf(interp_delay/_timeline.tick_seconds,
		NetReplication.SnapshotTimeline.MIN_DELAY_TICKS,
		NetReplication.SnapshotTimeline.MAX_DELAY_TICKS)
	# A fighter walks at most 0.14 m in a tick: anything past a stride is a
	# blink, a revive or a scene hand-off, and the view must cut to it.
	_timeline.discontinuity_metres = 0.75
	if replaced or not _timeline_ready:
		_timeline.reset_to(target,sent_velocity,0.0,_pose_tick(tick),_pose_now())
		_timeline_ready = true
		position = target
		velocity = sent_velocity
		return
	_timeline.push(_pose_tick(tick),target,sent_velocity,0.0,_pose_now())
	velocity = sent_velocity

func _pose_now() -> float:
	return Time.get_ticks_msec()/1000.0

func _pose_tick(tick: int) -> int:
	return tick if tick >= 0 else _timeline.newest_tick() + 1

func _process(delta: float) -> void:
	# The body's voice: the local body's own lines play flat - they are the ears
	# they come from - and every other body's are placed where it stands. The flag
	# is read here rather than at creation because the scene seats `is_local`
	# after the body is in the tree.
	if _voice != null:
		_voice.flat = is_local
		_voice.tick(delta)
	if not authoritative and _received_pose and not prediction_active():
		_timeline.advance(delta)
		var sample: Dictionary = _timeline.sample()
		position = sample.pos
		velocity = sample.vel
	_tick_downed_presentation(delta)
	_label.text = "%s%s  %d" % [display_name," [BOT]" if is_bot else "",int(health)]
	_ground_ring.visible = alive
	_ground_ring.global_position = Vector3(global_position.x,_floor_height(global_position)+0.025,global_position.z)
