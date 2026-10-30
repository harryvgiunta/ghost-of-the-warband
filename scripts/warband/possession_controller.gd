class_name PossessionController
extends Node
## The local player's soul, spread over a squad of real `ArenaActor` bodies.
##
## Ghost of the Warband has no main character: the player is a floating
## consciousness and every mercenary in the warband is a possible body. This node
## is the bridge between that idea and the existing arena actor layer:
##
##   * one `ArenaActor` per living roster mercenary, wearing that mercenary's
##     gear through the same `State.build_loadout` + `SeatLoadout.apply` path the
##     hub paperdoll uses, so a body looks exactly like the roster record;
##   * `Warband.souls` (the router) stays the authority for who is inside what -
##     this controller never moves a soul itself, it asks the router and then
##     wires the scene to the answer;
##   * exactly the body this peer is inside gets player input; every other body
##     keeps its AI/remote flags, so a soul change is a control change, not a
##     teleport of the camera or of the squad;
##   * a body that stops being alive ejects its soul immediately, because a
##     player watching a corpse take input is the one bug this game cannot have.
##
## The camera (`possession_camera.gd`) owns the aim ray; the sim loop mirrors
## `arena.gd` (host steps every body, guest predicts its own).

signal possession_changed(peer_id: int, merc_id: int)
signal possession_released(peer_id: int, reason: String)
signal transfer_refused(peer_id: int, merc_id: int, reason: String)

const Actor = preload("res://scripts/arena_actor.gd")
const CameraRig = preload("res://scripts/warband/possession_camera.gd")
const SyncScript = preload("res://scripts/warband/possession_sync.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")

## The peer whose soul this process owns. 1 is the host, matching ENet.
var local_peer_id := 1
## The eye of the soul. Rebuilt in `setup`.
var camera_rig: CameraRig
## Netcode half, built here so the controller is usable from any mode.
var sync
## The body the local peer is inside, or null while the soul is between bodies.
var active_actor: Actor
## True when this process runs the authoritative simulation of the bodies.
var _authoritative := false
## A mode that calls `physics_step` itself (the admin arena does) sets this
## false so the bodies are never integrated twice per tick.
var auto_simulate := true
## Scene-owned gate: a pause menu or an inventory screen sets this false so the
## possessed body stops walking. Pointer capture stays the scene's business too,
## which is why the controller itself never touches `Input.mouse_mode` policy.
var input_enabled := true
## How the local soul asks for a body while this process is not the authority.
## The session sets it: a guest's `[`/`]`, F1..F8 and warband-screen click become a
## request the host answers with its ownership map, never a move made here - two
## guests deciding for themselves is how two souls ended up in one body.
var transfer_requester: Callable = Callable()
## The scene's half of the verbs the controller does not own (`swap_set`,
## `revive`): called as `world_action.call(actor, action, value)` on the
## authority, so a guest's TAB or revive reaches the host's warband through the
## same intent channel as its swing.
var world_action: Callable = Callable()
## The body the local soul's eye rides while it has none of its own: another
## soul's body. When every living body is taken, the soul that was inside the
## last one first keeps it, and everybody else watches it through this.
var watched: Actor = null

var _warband: WarbandState
var _bodies_root: Node3D
var _spawned: Array[Actor] = []
var _merc_bodies: Dictionary = {}   # merc_id -> ArenaActor
var _body_mercs: Dictionary = {}    # ArenaActor -> merc_id
var _loadouts: Dictionary = {}      # merc_id -> the seat loadout applied
var _peer_actors: Dictionary = {}   # peer_id -> ArenaActor
## The mercenary each peer was last wired into, so the swap sound fires on a
## real change of body and not on every re-wire `possession_changed` reports.
var _last_merc: Dictionary = {}     # peer_id -> merc_id
var _tick := 0
var _query := PhysicsRayQueryParameters3D.new()
var _last_step_frame := -1
## Per-mercenary AI flag the scene asked for; a body with no soul falls back to
## this, so leaving a body hands it to the AI the mode configured.
var _bot_flags: Dictionary = {}
var _drawing := false
var _throw_held := false
## Which side the next one-handed cut starts from; the locals alternate.
var _next_swing_side := 1

func _ready() -> void:
	set_physics_process(true)

## Wire the soul into a scene: the warband that owns it, the camera to own, and
## the node the bodies hang under.
func setup(warband: WarbandState, camera_node: Camera3D, bodies_root: Node3D) -> void:
	_warband = warband
	if bodies_root == null:
		var holder := Node3D.new()
		holder.name = "Bodies"
		add_child(holder)
		bodies_root = holder
	_bodies_root = bodies_root
	if camera_rig == null:
		camera_rig = CameraRig.new()
		camera_rig.name = "PossessionCamera"
		add_child(camera_rig)
	if camera_node != null:
		camera_rig.adopt(camera_node)
	if _warband != null:
		if not _warband.souls.body_state_changed.is_connected(_on_body_state_changed):
			_warband.souls.body_state_changed.connect(_on_body_state_changed)
		if not _warband.souls.body_unregistered.is_connected(_on_body_unregistered):
			_warband.souls.body_unregistered.connect(_on_body_unregistered)
	if sync == null:
		sync = SyncScript.new()
		sync.name = "PossessionSync"
		add_child(sync)
		sync.setup(warband, self)

# --- spawning --------------------------------------------------------------

## One real body per living mercenary, wearing that mercenary's gear. Deployed
## ids win when the warband has marked a battle line; otherwise the whole living
## roster fields, which is what the cage and the arena both want.
func spawn_mercenaries(spawn_points: Array[Vector3], authoritative: bool = true,
		merc_ids: Array = []) -> Array[Actor]:
	var out: Array[Actor] = []
	if _warband == null:
		return out
	_authoritative = authoritative
	for merc_id in _spawn_ids(merc_ids):
		var spawn := Vector3.ZERO
		if not spawn_points.is_empty():
			spawn = spawn_points[out.size() % spawn_points.size()]
		var actor := _spawn_body(merc_id, spawn, authoritative)
		if actor != null:
			out.append(actor)
	return out

## The mercenaries to field. `wanted` is a list the authority already fielded (a
## co-op guest fields exactly the host's bodies, a downed one included); without
## it, deployed ids win and otherwise the living roster takes the field.
func _spawn_ids(wanted: Array = []) -> Array[int]:
	var out: Array[int] = []
	if not wanted.is_empty():
		for raw_id in wanted:
			var merc_id := int(raw_id)
			if _warband.roster.has(merc_id) and not _merc_bodies.has(merc_id) \
					and _warband.roster.state_of(merc_id) != Contracts.HealthState.DEAD:
				out.append(merc_id)
		return out
	var deployed := _warband.deployed_merc_ids()
	var source: Array[int] = deployed if not deployed.is_empty() else _warband.alive_merc_ids()
	for merc_id in source:
		if _warband.roster.is_alive(merc_id) and not _merc_bodies.has(merc_id):
			out.append(merc_id)
	return out

func _spawn_body(merc_id: int, spawn: Vector3, authoritative: bool) -> Actor:
	if _bodies_root == null:
		return null
	var actor := Actor.new()
	# The slot is assigned before the tree sees it: `_ready` reads it for the
	# label colour and `combat.source_id`, and two bodies sharing a slot would
	# refuse each other's damage.
	actor.slot = _spawned.size()
	actor.name = "Body%02d" % merc_id
	# Who this mercenary is to look at, decided before the body is in the tree:
	# the rig bakes the height in before it measures its own legs, so a 2.1 m
	# mercenary's feet still plant on the ground and a 1.6 m one's do too.
	actor.appearance = WarbandLooks.profile_for(merc_id)
	# And who he sounds like. A profile is a pure function of the id, like the
	# look: every peer and every reload gives the same man the same mouth, and
	# nothing about it travels the wire or needs a save field.
	actor.voice_id = VoiceLibrary.profile_for(merc_id)
	_bodies_root.add_child(actor)
	var label: String = _warband.roster.name_of(merc_id)
	actor.authoritative = authoritative
	actor.combat.damage_enabled = authoritative
	# The warband has no rounds: a mercenary that bleeds out stays dead, and the
	# roster is the only thing that can bring one back.
	actor.persistent_death = true
	# And no single blow takes a body off the field: a lethal hit puts it on its
	# chest for the whole bleed clock, a blow that lands on it there ends it, and
	# a body that does die keeps its corpse where it fell.
	actor.warband_death = true
	actor.configure(0, true, label, spawn)
	_apply_gear(actor, merc_id)
	actor.killed.connect(_on_actor_killed.bind(actor))
	# The router is what decides who may be entered, so it has to hear about the
	# lie as well as the death: a body on its chest is still the soul's (it crawls
	# and is picked up) but is nobody else's to step into.
	actor.downed_started.connect(_on_body_downed_state.bind(actor))
	actor.downed_ended.connect(_on_body_revived_state.bind(actor))
	actor.tree_exiting.connect(_on_body_exiting.bind(actor))
	_merc_bodies[merc_id] = actor
	_body_mercs[actor] = merc_id
	_spawned.append(actor)
	_warband.souls.register_body(merc_id, actor, label)
	# A body the roster already lost must not be enterable just because it was
	# spawned: the router's default is ALIVE.
	var state: int = _warband.roster.state_of(merc_id)
	if state != Contracts.HealthState.ALIVE:
		_warband.souls.set_body_state(merc_id, state)
	return actor

## Dress the rig from the roster record. `SeatLoadout` speaks the wire shape -
## main/off ids, the bow and sword indexes, packed armour and the trinket ids -
## and rebuilds the session kit through `State.build_loadout`, which is the same
## hand-off the hub paperdoll uses. Building that shape here (instead of passing
## `build_loadout`'s own output) is what makes the worn armour reach the rig.
func _apply_gear(actor: Actor, merc_id: int) -> void:
	var gear: Dictionary = _warband.roster.equipped_of(merc_id)
	var main_id := str(gear.get("main", ""))
	var off_id := str(gear.get("off", ""))
	var pieces := {}
	for slot in ArmorData.SLOTS:
		var worn := str(gear.get(slot, ""))
		pieces[slot] = int(State.ITEMS.get(worn, {}).get("set", ArmorData.NONE)) \
			if not worn.is_empty() else ArmorData.NONE
	var main_item: Dictionary = State.ITEMS.get(main_id, {})
	var category := str(main_item.get("category", ""))
	var bow_index := 0
	var sword_index := 0
	if category == "bow":
		bow_index = int(main_item.get("index", 0))
	elif category == "staff":
		sword_index = 2
	elif str(main_item.get("kind", "")) == "sword" and category in ["1h", "2h"]:
		sword_index = int(main_item.get("index", 0))
	var loadout := {
		"main": main_id,
		"off": off_id,
		"bow": bow_index,
		"sword": sword_index,
		"armor": ArmorData.pack(pieces),
		"trinkets": {
			"neck": str(gear.get("neck", "")),
			"ring1": str(gear.get("ring1", "")),
			"ring2": str(gear.get("ring2", "")),
			"off": off_id,
		},
	}
	SeatLoadout.apply(actor.rig, loadout)
	_loadouts[merc_id] = loadout

# --- reading ---------------------------------------------------------------

func body_of(merc_id: int) -> Actor:
	var actor: Variant = _merc_bodies.get(merc_id)
	return actor if actor is Actor else null

func merc_of(actor: Actor) -> int:
	if actor == null:
		return -1
	return int(_body_mercs.get(actor, -1))

func bodies() -> Array[Actor]:
	return _spawned.duplicate()

## The body a peer is inside. `0` means this process's own peer.
func active_body(peer_id: int = 0) -> Actor:
	if peer_id == 0 or peer_id == local_peer_id:
		return active_actor
	return body_for_peer(peer_id)

## The body the local soul is looking at: its own, or - while it has none - the
## one it is watching. The scene follows this for everything that should go on
## with the party rather than stop with one soul (the squad's escort, the music,
## the checkpoints).
func focus_body() -> Actor:
	if active_actor != null and is_instance_valid(active_actor):
		return active_actor
	return watching()

## The other soul's body this one is watching, or null.
func watching() -> Actor:
	if active_actor != null and is_instance_valid(active_actor):
		return null
	return watched if watched != null and is_instance_valid(watched) else null

## The peer inside the body being watched, or 0.
func watched_peer() -> int:
	var body := watching()
	if body == null:
		return 0
	for peer_id in _peer_actors:
		if _peer_actors[peer_id] == body:
			return int(peer_id)
	return 0

## Every peer this process has wired into a body, in id order.
func possessing_peers() -> Array[int]:
	var out: Array[int] = []
	for peer_id in _peer_actors:
		if body_for_peer(int(peer_id)) != null:
			out.append(int(peer_id))
	out.sort()
	return out

## Tell the controller whether an unpossessed body should fight on its own. The
## arena marks its two squads this way; a body with a soul inside ignores it
## until the soul leaves.
func set_bot(merc_id: int, bot: bool) -> void:
	var actor := body_of(merc_id)
	if actor == null:
		return
	_bot_flags[merc_id] = bot
	for peer_id in _peer_actors:
		if _peer_actors[peer_id] == actor:
			return
	actor.is_bot = bot
	actor.is_local = false
	actor.predicting = false
	if bot:
		actor.peer_id = 0

func body_for_peer(peer_id: int) -> Actor:
	var actor: Variant = _peer_actors.get(peer_id)
	return actor if actor is Actor else null

func merc_for_peer(peer_id: int) -> int:
	return merc_of(body_for_peer(peer_id))

## The exact seat loadout applied to a mercenary's rig.
## The seat loadout *as it was applied at spawn*. It is the wire shape a scene
## registers, not the current kit: once a piece is looted or the paperdoll moves
## gear, `refresh_gear()` is what puts the new kit on the body.
func seat_loadout(merc_id: int) -> Dictionary:
	var loadout: Dictionary = _loadouts.get(merc_id, {})
	return loadout.duplicate()

## Re-read a mercenary's roster kit and put it on the live body. Pickups, the
## paperdoll and the recruiter all change the roster while a scene is running;
## without this the body keeps whatever it was born with, which reads as "the
## weapon did not go into my hands" (and as an AI that will not swing).
func refresh_gear(merc_id: int) -> bool:
	var actor := body_of(merc_id)
	if actor == null or not is_instance_valid(actor):
		return false
	_apply_gear(actor, merc_id)
	return true

## Living bodies in roster order: what `F1`..`F8` count.
func living_merc_ids() -> Array[int]:
	var out: Array[int] = []
	if _warband == null:
		return out
	for merc_id in _warband.roster.ids():
		if _warband.roster.is_alive(merc_id) and _merc_bodies.has(merc_id):
			out.append(merc_id)
	return out

# --- possession ------------------------------------------------------------

## Enter a body. Validated by the router, so a downed, dead or occupied body is
## refused with a reason and nothing in the scene moves.
func activate(peer_id: int, merc_id: int) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "No warband.", "body_id": merc_id, "previous_body_id": -1,
			"reason": SoulRouter.REASON_UNKNOWN}
	var result := _warband.souls.request_transfer(peer_id, merc_id)
	if not bool(result.get("ok", false)):
		transfer_refused.emit(peer_id, merc_id, str(result.get("reason", "")))
		return result
	_wire(peer_id, int(result.get("body_id", merc_id)))
	return result

## Next/previous living, unoccupied body. A refusal leaves the soul where it is.
func cycle(peer_id: int, direction: int = 1) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "No warband.", "body_id": -1, "previous_body_id": -1,
			"reason": SoulRouter.REASON_UNKNOWN}
	if _routes(peer_id):
		var target := _warband.souls.cycle_target(peer_id, direction)
		var body_id := int(target.get("body_id", -1))
		if not bool(target.get("ok", false)):
			transfer_refused.emit(peer_id, body_id, str(target.get("reason", "")))
			return target
		if body_id == _warband.souls.body_of(peer_id):
			return target
		return transfer_requester.call(body_id)
	var result := _warband.souls.cycle(peer_id, direction)
	if bool(result.get("ok", false)):
		_wire(peer_id, int(result.get("body_id", -1)))
	else:
		transfer_refused.emit(peer_id, int(result.get("body_id", -1)), str(result.get("reason", "")))
	return result

## Enter a named body. The warband screen's click and `F1`..`F8` both land here.
func direct(peer_id: int, merc_id: int) -> Dictionary:
	if _routes(peer_id):
		return transfer_requester.call(merc_id)
	return activate(peer_id, merc_id)

## Adopt the authority's decision as it stands: the router takes the host's word
## (`SoulRouter.assign`) and the scene is wired to it. Only a guest's session
## calls this, with the host's ownership map.
func adopt(peer_id: int, merc_id: int) -> void:
	if _warband == null or body_of(merc_id) == null:
		return
	if not _warband.souls.assign(peer_id, merc_id):
		return
	_wire(peer_id, merc_id)

## True when the local soul's move has to be asked for rather than made: this
## process is not the authority and a session is listening.
func _routes(peer_id: int) -> bool:
	return not _authoritative and peer_id == local_peer_id and transfer_requester.is_valid()

## Wire the scene to a router decision. Never validates: the router has already
## moved the soul by the time this runs, so a second check would only hide bugs.
func _wire(peer_id: int, merc_id: int) -> void:
	var actor := body_of(merc_id)
	var previous := body_for_peer(peer_id)
	if previous != null and previous != actor:
		_detach(previous)
	if actor == null:
		# Released (or a body this scene never spawned): the peer is a spectator.
		_release_peer(peer_id, "no body")
		return
	_dress(actor, peer_id)
	_peer_actors[peer_id] = actor
	if peer_id == local_peer_id:
		var was_watching := watching() != null
		active_actor = actor
		watched = null
		_drawing = false
		_throw_held = false
		if camera_rig != null:
			# The first body of a session snaps; every later body is an arc, and
			# so is the way back from a body this soul was only watching.
			camera_rig.follow(actor, previous == null and not was_watching)
	_warband.note_possession(peer_id, merc_id)
	var changed := int(_last_merc.get(peer_id, -1)) != merc_id
	_last_merc[peer_id] = merc_id
	possession_changed.emit(peer_id, merc_id)
	# One sound per body actually entered. `possession_changed` is also emitted
	# when the same body is re-wired (a re-dress, a spawn refresh), and a whoosh
	# on every one of those would read as the soul flickering.
	if changed:
		SfxScript.body_swap(actor.global_position)

## Hand a body to a peer: it becomes the input target for that peer only.
func _dress(actor: Actor, peer_id: int) -> void:
	var mine := peer_id == local_peer_id
	actor.peer_id = peer_id
	actor.is_bot = false
	actor.is_local = mine
	# A guest integrates its own body between snapshots; the host never does.
	actor.predicting = mine and not actor.authoritative
	actor.input_age = 0.0
	actor.combat.damage_enabled = actor.authoritative
	if actor.predicting:
		actor.interp_delay = 0.05

## Give a body back to the scene. Its intent latches are cleared so the AI does
## not inherit a held draw, a held guard or a half-finished swing from a soul
## that has already left.
func _detach(actor: Actor) -> void:
	if not is_instance_valid(actor):
		return
	actor.is_local = false
	actor.predicting = false
	actor.is_bot = bool(_bot_flags.get(merc_of(actor), true))
	actor.peer_id = 0
	actor.move_direction = Vector2.ZERO
	actor.run_requested = false
	actor.jump_requested = false
	actor.peek_requested = false
	actor.input_age = 0.0
	actor.combat.stop()
	actor.combat.stop_block()
	actor.combat.clear_camera_ray()

## Drop every reference this process holds to a peer's soul.
func _release_peer(peer_id: int, reason: String) -> void:
	var previous := body_for_peer(peer_id)
	if previous != null:
		_detach(previous)
	_peer_actors.erase(peer_id)
	_last_merc.erase(peer_id)
	if peer_id == local_peer_id:
		active_actor = null
		_drawing = false
		_throw_held = false
		if camera_rig != null:
			camera_rig.clear()
	if _warband != null:
		_warband.note_possession(peer_id, -1)
	possession_changed.emit(peer_id, -1)
	possession_released.emit(peer_id, reason)

## Wipe: the local soul leaves its body and becomes a spectator. The scene
## decides what a bodiless peer is (the arena shows a spectator camera).
func release_local() -> void:
	if _warband != null:
		_warband.souls.release_peer(local_peer_id, "released")
	_release_peer(local_peer_id, "released")

# --- death and auto-eject --------------------------------------------------

## The router noticed a body stop being *alive*. Only a death moves the soul out.
## A downed body keeps its soul on purpose: the player still has hands, the crawl
## is theirs to steer, and an ally standing over them is the way back up. Ejecting
## a soul the moment its body hit the floor is what left a player watching a body
## slide away on its own with no control at all.
func _on_body_state_changed(body_id: int, state: int) -> void:
	if state != Contracts.HealthState.DEAD:
		return
	var peer_id := _warband.souls.occupied_by(body_id) if _warband != null else 0
	if peer_id == 0:
		return
	_eject(peer_id, Contracts.state_name(state))

## A body knocked onto its chest. The router records DOWNED, which keeps the soul
## where it is and refuses everybody else: `[`/`]`, F1..F8 and a click on the
## warband screen cannot put a second soul into a body that is already on the floor.
func _on_body_downed_state(_slot: int, actor: Actor) -> void:
	var merc_id := merc_of(actor)
	if merc_id <= 0 or _warband == null:
		return
	_warband.souls.set_body_state(merc_id, Contracts.HealthState.DOWNED)

## A downed body standing back up: the router may offer it again.
func _on_body_revived_state(_slot: int, actor: Actor) -> void:
	var merc_id := merc_of(actor)
	if merc_id <= 0 or _warband == null:
		return
	if not bool(actor.get("alive")):
		return
	_warband.souls.set_body_state(merc_id, Contracts.HealthState.ALIVE)

## The body itself died (a real `take_damage` reaching zero health). The router
## owns entry rules, so record the death there and let the state handler eject.
func _on_actor_killed(_slot: int, _source: int, actor: Actor) -> void:
	var merc_id := merc_of(actor)
	if merc_id <= 0 or _warband == null:
		return
	_warband.souls.set_body_state(merc_id, Contracts.HealthState.DEAD)

func _eject(peer_id: int, reason: String) -> void:
	# A guest does not move souls: the host ejects every one of them and its
	# ownership map says where each landed - or that one is watching now.
	if not _authoritative:
		return
	var moved := cycle(peer_id, 1)
	var body := body_for_peer(peer_id)
	if bool(moved.get("ok", false)) and body != null and body.alive:
		return
	# Nothing living is free: the scene decides what a bodiless soul becomes.
	_warband.souls.release_peer(peer_id, reason)
	_release_peer(peer_id, reason)

func _on_body_exiting(actor: Actor) -> void:
	var merc_id := merc_of(actor)
	if merc_id > 0:
		_merc_bodies.erase(merc_id)
	_body_mercs.erase(actor)
	_spawned.erase(actor)
	for peer_id in _peer_actors.keys():
		if _peer_actors[peer_id] == actor:
			_peer_actors.erase(peer_id)
			_last_merc.erase(peer_id)
	if camera_rig != null:
		camera_rig.forget(actor)
	if active_actor == actor:
		active_actor = null

func _on_body_unregistered(body_id: int) -> void:
	if _merc_bodies.has(body_id):
		var actor: Actor = _merc_bodies[body_id]
		_merc_bodies.erase(body_id)
		_body_mercs.erase(actor)

# --- simulation and input --------------------------------------------------

func _physics_process(delta: float) -> void:
	if auto_simulate:
		physics_step(delta)

## Advance the squad exactly once for this physics tick: read the possessed
## body's intent, then host-step every body (or predict the guest's own). A mode
## with its own simulation clock calls this and turns `auto_simulate` off; the
## physics-frame guard below keeps a double call from integrating twice.
func physics_step(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _last_step_frame:
		return
	_last_step_frame = frame
	if camera_rig != null:
		_update_watch()
		camera_rig.update(delta)
	if _spawned.is_empty():
		return
	_tick += 1
	var actor := active_actor
	if actor != null and is_instance_valid(actor):
		_drive(actor)
	if _authoritative:
		for body in _spawned:
			if not is_instance_valid(body):
				continue
			body.combat.lag_tick = _tick
			body.step(delta, _spawned, _tick)
	elif actor != null and is_instance_valid(actor) and actor.predicting:
		actor.predicted_step(delta, _spawned)

## A soul with no body watches one that has a soul in it: the lowest peer id
## other than this one with a living body. That is the other player's body when
## the last free one went to them, and nothing at all when every body is down -
## the eye then holds its last frame, as it always did.
func _update_watch() -> void:
	if active_actor != null and is_instance_valid(active_actor):
		watched = null
		return
	var target: Actor = null
	for peer_id in possessing_peers():
		if peer_id == local_peer_id:
			continue
		var body := body_for_peer(peer_id)
		if body != null and body.alive:
			target = body
			break
	if target == watched and (target == null or camera_rig.active_body() == target):
		return
	watched = target
	if target == null:
		camera_rig.clear()
	else:
		camera_rig.follow(target, false)

## The possessed body's intent for this frame, read from the same bindings the
## arena uses: WASD relative to the camera, Shift to sprint, the centre ray as
## the aim. A guest integrates its own body and tells the host; the host applies
## it directly.
func _drive(actor: Actor) -> void:
	if not actor.alive or not input_enabled:
		return
	var x := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var z := float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var motion := Vector2(x, z).limit_length()
	var yaw := camera_rig.yaw if camera_rig != null else 0.0
	var right := Vector2(cos(yaw), -sin(yaw))
	var back := Vector2(sin(yaw), cos(yaw))
	var direction := right * motion.x + back * motion.y
	# A peek leans out of the shoulder the eye is on, so the side is read from
	# the same camera that draws the crosshair. `cover.normal` only exists in
	# cover; the actor's own step already tolerates the call outside it.
	actor.peek_view_right = Vector3(right.x, 0.0, right.y)
	actor.update_combat_cover_side()
	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	var sample := aim_sample()
	if actor.authoritative:
		var point: Vector3 = sample["point"]
		var origin: Vector3 = sample["origin"]
		_aim(actor, point, origin)
		actor.accept_network_input(direction, running)
	else:
		actor.update_input(direction, running)
		if sync != null:
			sync.send_move(direction, running, sample["point"], sample["origin"])

## The centre ray of the view plus the first thing it hits, which is what the
## possessed body aims at. The possessed body itself and nothing else is
## excluded, matching the arena's crosshair query.
func aim_sample() -> Dictionary:
	var actor := active_actor
	if actor == null or not is_instance_valid(actor):
		return {"point": Vector3.ZERO, "origin": Vector3.ZERO}
	var ray := camera_rig.aim_ray() if camera_rig != null \
		else {"origin": actor.global_position, "direction": -actor.global_basis.z}
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	var point := origin + direction * 120.0
	if _bodies_root != null and _bodies_root.is_inside_tree():
		var anchor: Vector3 = actor.global_position + Vector3.UP * CameraRig.EYE_HEIGHT
		var depth := maxf(0.0, (anchor - origin).dot(direction))
		_query.from = origin + direction * depth
		_query.to = point
		# The world and the wood's own bodies. Layer 4 is other warband bodies: a
		# squadmate is not a crosshair target, and `combat.target_mask` agrees.
		# Masking the mobs out here is what used to put every aim point through a
		# watcher and into the dirt behind it.
		_query.collision_mask = 1 | 2
		var excluded: Array[RID] = [actor.get_rid()]
		_query.exclude = excluded
		var space := _bodies_root.get_world_3d().direct_space_state
		var hit: Dictionary = space.intersect_ray(_query) if space != null else {}
		if not hit.is_empty():
			point = hit.position
	return {"point": point, "origin": origin}

## Aim the body at a world point, optionally with the camera ray that produced
## it (the same pair the arena's `_set_aim` validates).
func _aim(actor: Actor, point: Vector3, origin: Variant = null) -> bool:
	if not point.is_finite() or point.length_squared() > 1000000.0:
		return false
	actor.update_cover_aim_readiness()
	actor.combat.set_aim(point)
	if typeof(origin) == TYPE_VECTOR3:
		var from: Vector3 = origin
		var ray: Vector3 = point - from
		if from.is_finite() and from.distance_squared_to(actor.global_position) <= 144.0 \
				and ray.is_finite() and ray.length_squared() > 0.01:
			actor.combat.set_camera_ray(from, ray)
		else:
			actor.combat.clear_camera_ray()
	else:
		actor.combat.clear_camera_ray()
	if actor.combat.blocking:
		var facing: Vector3 = point - actor.global_position
		facing.y = 0.0
		if facing.length_squared() > 0.000001:
			actor.combat.face_block(facing)
	return true

## A movement frame for a peer's body, arriving from the wire.
func apply_move(merc_id: int, direction: Vector2, running: bool, point: Variant = null,
		origin: Variant = null) -> bool:
	var actor := body_of(merc_id)
	if actor == null or not actor.authoritative:
		return false
	if typeof(point) == TYPE_VECTOR3:
		_aim(actor, point, origin)
	actor.accept_network_input(direction, running)
	return true

## One validated combat verb on one body. Shared by the local driver and by the
## sync's remote intents, so a guest can only do what the host could do.
func apply_action(merc_id: int, action: String, value: Variant = null,
		origin: Variant = null) -> bool:
	return _perform(body_of(merc_id), action, value, origin)

func _perform(actor: Actor, action: String, value: Variant, origin: Variant = null) -> bool:
	if actor == null or not is_instance_valid(actor) or not actor.alive:
		return false
	var combat = actor.combat
	match action:
		"draw":
			if typeof(value) != TYPE_VECTOR3:
				return false
			if not _aim(actor, value, origin):
				return false
			actor.update_combat_cover_side()
			return combat.begin_draw()
		"release":
			if typeof(value) != TYPE_VECTOR3:
				return false
			if not _aim(actor, value, origin):
				return false
			actor.update_combat_cover_side()
			combat.release_draw()
			return true
		"melee":
			if typeof(value) != TYPE_DICTIONARY:
				return false
			var aim: Variant = value.get("aim")
			var hand := str(value.get("hand", "right"))
			var variant := str(value.get("variant", "overhead"))
			if typeof(aim) != TYPE_VECTOR3 or hand not in ["left", "right"] \
					or variant not in ["overhead", "diagonal_left", "diagonal_right", "stab"]:
				return false
			if not _aim(actor, aim, origin):
				return false
			actor.update_combat_cover_side()
			return combat.begin_melee(hand, variant)
		"throw":
			if typeof(value) != TYPE_VECTOR3:
				return false
			if not _aim(actor, value, origin):
				return false
			actor.update_combat_cover_side()
			return combat.begin_throw()
		"throw_release":
			if typeof(value) != TYPE_VECTOR3:
				return false
			if not _aim(actor, value, origin):
				return false
			actor.update_combat_cover_side()
			combat.release_throw()
			return true
		"block":
			if typeof(value) != TYPE_DICTIONARY:
				return false
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("forward")) != TYPE_VECTOR3:
				return false
			var forward: Vector3 = value.forward
			if not forward.is_finite() or (value.pressed and forward.length_squared() < 0.25):
				return false
			actor.set_block(value.pressed, Vector3(forward.x, 0, forward.z))
			return true
		"jump":
			if typeof(value) != TYPE_BOOL:
				return false
			actor.press_jump(value)
			return true
		"crouch":
			if typeof(value) != TYPE_BOOL:
				return false
			actor.set_crouch(value)
			return true
		"cover":
			if typeof(value) != TYPE_VECTOR3:
				return false
			var facing: Vector3 = value
			if not facing.is_finite() or facing.length_squared() < 0.01 \
					or facing.length_squared() > 1000000.0:
				return false
			actor.toggle_cover(facing.normalized())
			return true
		"step":
			if typeof(value) != TYPE_VECTOR3:
				return false
			var side: Vector3 = value
			if not side.is_finite() or absf(side.y) > 0.01:
				return false
			var flat := Vector3(side.x, 0, side.z)
			if absf(flat.length() - 1.0) > 0.1:
				return false
			return actor.try_step(flat)
		"consume":
			if typeof(value) != TYPE_STRING or value not in ["bandage", "potion"]:
				return false
			return actor.try_consume(str(value))
		"ability":
			# The warband binds plain 1/2/3 to the actor's three skill slots. The
			# runner owns eligibility, stamina and cooldown; the controller only
			# keeps the wire honest about which slot was asked for.
			if typeof(value) != TYPE_INT:
				return false
			var index := int(value)
			if index < 0 or index >= AbilityRules.SLOT_COUNT:
				return false
			var outcome: Variant = actor.try_ability(index)
			return typeof(outcome) == TYPE_DICTIONARY and bool(outcome.get("ok", false))
		"stop":
			combat.stop()
			return true
		"swap_set", "revive":
			# The scene's verbs: the authority's world answers them for this body,
			# so a guest's TAB and revive land on the host's warband and field.
			if world_action.is_valid():
				return bool(world_action.call(actor, action, value))
	return false

# --- input -----------------------------------------------------------------

## `[` / `]` cycle, `F1`..`F8` enter a named body, and the possessed body gets
## the arena's own key bindings. Nothing here takes a key the actor layer owns.
func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _hotkey(event.keycode):
			get_viewport().set_input_as_handled()
			return
	if active_actor == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _command(event):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		_mouse_press(event)

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if active_actor == null:
		# A watching soul still owns its eye: it looks around the body it rides.
		if watching() != null and event is InputEventMouseMotion \
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera_rig != null:
			camera_rig.rotate_view(-event.relative.x * 0.004, event.relative.y * 0.004)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if camera_rig != null:
			camera_rig.rotate_view(-event.relative.x * 0.004, event.relative.y * 0.004)
	elif event is InputEventMouseButton and not event.pressed:
		_mouse_release(event)
	elif event is InputEventKey and event.keycode == KEY_T and not event.pressed and _throw_held:
		_throw_held = false
		var sample := aim_sample()
		_act("throw_release", sample["point"], sample["origin"])

## Soul-level hotkeys. These work even with no body, because that is how a
## spectator gets back into one.
func _hotkey(keycode: int) -> bool:
	if keycode == KEY_BRACKETLEFT:
		cycle(local_peer_id, -1)
		return true
	if keycode == KEY_BRACKETRIGHT:
		cycle(local_peer_id, 1)
		return true
	for index in 8:
		if keycode == KEY_F1 + index:
			var ids := living_merc_ids()
			if index < ids.size():
				direct(local_peer_id, ids[index])
			return true
	return false

## The possessed body's bindings. What a body carries is its gear, so there is no
## key that puts a weapon or a shield in its hands: `refresh_gear()` dresses the
## body from its roster record and the paperdoll moves pieces in and out. 6/7 stay
## the consumables.
func _command(event: InputEventKey) -> bool:
	var actor := active_actor
	var yaw := camera_rig.yaw if camera_rig != null else 0.0
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	match event.keycode:
		# The three item skills sit on the number row, plain: a warband player
		# never needs Shift to reach a skill, and Shift+1 is the same press.
		KEY_1:
			_act("ability", 0)
		KEY_2:
			_act("ability", 1)
		KEY_3:
			_act("ability", 2)
		KEY_6:
			_act("consume", "bandage")
		KEY_7:
			_act("consume", "potion")
		KEY_SPACE:
			_act("jump", event.shift_pressed)
		KEY_C:
			_act("crouch", not actor.cover.crouch_requested)
		KEY_F:
			_act("cover", forward)
			# Peeking is a cover-only intent: standing up drops any lean the
			# mouse still holds, so the next cover press starts flat against it.
			if not actor.cover.active:
				actor.peek_requested = false
		KEY_X:
			# Shoulder swap, as the frontier binds it: the eye crosses to the other
			# side of the body and the crosshair keeps pointing where it pointed.
			if camera_rig != null:
				camera_rig.swap()
		KEY_T:
			_throw_held = true
			var sample := aim_sample()
			_act("throw", sample["point"], sample["origin"])
		KEY_Q:
			_act("step", right * -1.0)
		KEY_E:
			_act("step", right)
		_:
			return false
	return true

func _mouse_press(event: InputEventMouseButton) -> void:
	var actor := active_actor
	var sample := aim_sample()
	var yaw := camera_rig.yaw if camera_rig != null else 0.0
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var weapon: String = actor.rig.weapon
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if weapon == "bow":
				_drawing = _act("draw", sample["point"], sample["origin"])
			elif weapon == "dual":
				_melee("left", "diagonal_left", sample)
			else:
				# The locals alternate cut sides, exactly as the arena does.
				var variant := "diagonal_right" if _next_swing_side >= 0 else "diagonal_left"
				if _melee("right", variant, sample):
					_next_swing_side = -_next_swing_side
		MOUSE_BUTTON_RIGHT:
			if weapon == "dual":
				_melee("right", "diagonal_right", sample)
			else:
				_throw_held = false
				_act("block", {"pressed": true, "forward": forward})
				# Holding the guard against cover also leans out of it: the body
				# stays behind the wall, the eye and the weapon come round it.
				# Outside cover the same press is only a guard.
				actor.peek_requested = bool(actor.cover.active)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if weapon in ["sword", "dagger", "dual"]:
				var variant := "stab" if event.button_index == MOUSE_BUTTON_WHEEL_UP else "overhead"
				_melee("right", variant, sample)

func _mouse_release(event: InputEventMouseButton) -> void:
	var actor := active_actor
	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Releasing the button ends the lean whatever the hands hold: the body
		# settles back behind the wall instead of hanging out in the open.
		actor.peek_requested = false
	if event.button_index == MOUSE_BUTTON_LEFT and _drawing:
		_drawing = false
		var sample := aim_sample()
		_act("release", sample["point"], sample["origin"])
	elif event.button_index == MOUSE_BUTTON_RIGHT and actor.rig.weapon != "dual":
		_act("block", {"pressed": false, "forward": Vector3.ZERO})

func _melee(hand: String, variant: String, sample: Dictionary) -> bool:
	return _act("melee", {"aim": sample["point"], "hand": hand, "variant": variant},
		sample["origin"])

## One verb on the local soul's body, the way its key would send it: performed
## here on the authority, predicted and sent to the host on a guest. The scene's
## own keys (TAB, the revive hold) come through this.
func act(action: String, value: Variant = null) -> bool:
	return _act(action, value)

## Run one verb on the possessed body with the camera ray that produced it.
## A guest owns no combat: it predicts the locomotion intents the actor layer
## already mirrors and hands every other verb to the host.
func _act(action: String, value: Variant, origin: Variant = null) -> bool:
	var actor := active_actor
	if actor == null or not is_instance_valid(actor) or not actor.alive:
		return false
	if actor.authoritative:
		return _perform(actor, action, value, origin)
	actor.predict_action(action, value)
	if sync != null:
		sync.send_action(action, value, origin)
	return true
