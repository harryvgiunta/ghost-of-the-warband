class_name WarbandSession
extends Node
## The socket of a warband battle: one ENet peer, the host as the authority, and
## the bodies of `PossessionController` as the replicated state.
##
## The controller stays the scene's clock and `SoulRouter` stays the rule book;
## this node owns only what crosses the wire:
##
##   * **transfers** - a guest asks to enter a body (`request_body`), the host
##     validates it through the router and answers either with a refusal that
##     names the reason or with the resulting `{peer: merc_id}` map, so no two
##     souls can end up inside one body and every peer agrees on the field;
##   * **snapshots** - the host writes every body at 20 Hz, keyed by *merc id*
##     (never the arena slot, which is a spawn-order artifact), packed through
##     `NetLimits` so a snapshot never needs ENet fragmentation;
##   * **intents** - movement, aim and combat verbs ride `PossessionSync`, which
##     the controller already drives from its own frame. The host resolves every
##     hit; a guest only ever predicts its own locomotion, and the host steps a
##     guest's body only on frames it actually received (never on frames it
##     invented to fill a gap);
##   * **the world** - when a `WarbandWorld` is attached, the host also owns its
##     mobs (15 Hz, 70 m around any body), the loot that hits its ground and the
##     missiles in flight. A guest's mobs are `replica`s and never run AI, its
##     arrows are visuals with an empty hit mask, and only the host's `defeated`
##     signal pays a reward. All of it rides this one peer.
##
## The scene spawns the bodies before `setup`; the session replicates them and
## never ticks `physics_step`, never reads `Input`, and never decides who is
## inside what - it asks `SoulRouter` and obeys. Both peers must mount it at the
## same node path, because that path is the RPC address.

const NetLimits = preload("res://scripts/net_limits.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")
const ArrowScript = preload("res://scripts/arrow.gd")

## How often the host writes every body to the wire.
const SNAPSHOT_HZ := 20.0
## The world's mobs. 15 Hz is enough for a replica that interpolates between two
## poses, and a fifth of the body rate keeps the datagrams from doubling.
const MOB_SNAPSHOT_HZ := 15.0
## A mob only matters to a soul that could reach it: beyond this, the mob is the
## wood's business and the wire stays quiet.
const MOB_REACH_METRES := 70.0
## Loot is a one-shot announcement, so it is polled slowly; a missile's visual
## start must look immediate, so it is polled with the physics frame.
const LOOT_POLL_SECONDS := 0.2
const MISSILE_POLL_SECONDS := 0.05
## The group every wilderness mob joins; a late spawn must be a replica too.
const WILD_MOB_GROUP := "wild_mobs"
## How many payload keys the client remembers. An announcement is rare, and the
## book is capped so a long campaign cannot grow it forever.
const DELIVERY_BOOK_CAP := 512
## ENet slots. The deployment cap is eight bodies, so eight souls is the field.
const MAX_CLIENTS := 8

signal role_changed(role: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## The host's `{peer: merc_id}` map, as this peer last adopted it.
signal ownership_changed(assignments: Dictionary)
## A transfer this peer asked for was refused; `reason` is the router's words.
signal transfer_refused(merc_id: int, reason: String)

var controller: PossessionController
var warband: WarbandState

var _role := "offline"
var _player_name := ""
## peer_id -> player name, mirrored from the host with every ownership map.
var _names: Dictionary = {}
## The map this peer last received, so a soul that disappears from it is released.
var _adopted: Dictionary = {}
var _peer: ENetMultiplayerPeer
var _signals_wired := false
var _accumulator := 0.0
var _tick := 0

# --- the world beyond the bodies -------------------------------------------
#
# The campaign is one world: the mobs, the loot on the ground and the missiles
# in flight are the host's alone. The guest is told about them on the same peer,
# never allowed to run a mob's brain, and never trusted with a hit.
## The `WarbandWorld` this session replicates, or null between worlds.
var world: Node3D
## Pickup/projectile instance ids the host has already announced.
var _sent_loot: Dictionary = {}
var _sent_missiles: Dictionary = {}
## Mob names whose final (dead) state was already sent. A living guard is sent
## every tick; a corpse is sent exactly once, so a replica can fall.
var _dead_sent: Dictionary = {}
## Payload keys a client already spawned, so a repeated announcement is a no-op.
var _delivered_loot: Dictionary = {}
var _delivered_arrows: Dictionary = {}
var _mob_accumulator := 0.0
var _loot_accumulator := 0.0
var _missile_accumulator := 0.0
var _mob_tick := 0
var _world_watch := false

## Bind the session to the soul it carries. The controller's own `PossessionSync`
## is reused as-is: it is the only path that may turn a remote intent into a
## body.
func setup(possession_controller: PossessionController, warband_node: WarbandState) -> void:
	controller = possession_controller
	warband = warband_node
	if controller == null:
		push_error("WarbandSession needs a PossessionController")
		return
	if controller.sync == null:
		controller.sync = PossessionSync.new()
		controller.sync.name = "PossessionSync"
		controller.add_child(controller.sync)
	controller.sync.setup(warband, controller)

## "offline", "host" or "client".
func role() -> String:
	return _role

## Every soul on the field, this peer included, sorted by peer id.
func connected_peers() -> Array[int]:
	var out: Array[int] = []
	if _peer == null or multiplayer == null:
		return out
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return out
	var self_id := multiplayer.get_unique_id()
	if self_id <= 0:
		return out
	out.append(self_id)
	for peer_id in multiplayer.get_peers():
		out.append(int(peer_id))
	out.sort()
	return out

func peer_count() -> int:
	return connected_peers().size()

func player_name() -> String:
	return _player_name

func name_of(peer_id: int) -> String:
	return str(_names.get(peer_id, ""))

## The `{peer: merc_id}` map in force: derived from the controller on the host
## (which is why a transfer the host made itself is in it too) and the last map
## the host sent everywhere else. `0` means a soul with no body.
func ownership() -> Dictionary:
	var map := {}
	if controller == null:
		return map
	if _role == "client":
		return _adopted.duplicate()
	for peer_id in connected_peers():
		map[peer_id] = maxi(0, controller.merc_for_peer(peer_id))
	return map

# --- opening and closing ---------------------------------------------------

func host(port: int, host_name: String) -> bool:
	if controller == null:
		return false
	if _role != "offline":
		leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_CLIENTS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_player_name = host_name.strip_edges()
	_names = {1: _player_name}
	_adopted = {}
	_accumulator = 0.0
	_tick = 0
	# The host is ENet peer 1 and its soul is the controller's own by default.
	controller.local_peer_id = 1
	_role = "host"
	_wire_signals()
	role_changed.emit(_role)
	return true

func join(address: String, port: int, guest_name: String) -> bool:
	if controller == null:
		return false
	if _role != "offline":
		leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address.strip_edges(), port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_player_name = guest_name.strip_edges()
	_names = {}
	_adopted = {}
	_accumulator = 0.0
	_tick = 0
	_role = "client"
	# The world scene, when it fielded the bodies, already handed this session
	# its mobs; a guest never runs their AI, so they become replicas now.
	_mark_world_replicas()
	_wire_signals()
	role_changed.emit(_role)
	return true

## Give the body back and drop the socket. Safe to call in any role.
func leave() -> void:
	var was := _role
	_role = "offline"
	if controller != null:
		_release_body_of(controller.local_peer_id, "Left the battle.")
	_teardown()
	_adopted = {}
	if was != "offline":
		role_changed.emit(_role)

# --- ownership -------------------------------------------------------------

## Ask to enter a body: the host decides at once, a guest asks and waits for the
## answer. Returns the router-shaped payload; a guest's answer carries
## `pending = true` because the decision has not landed yet.
func request_body(merc_id: int) -> Dictionary:
	if controller == null:
		return {"ok": false, "message": "No warband body to enter.", "body_id": merc_id,
			"previous_body_id": -1, "reason": SoulRouter.REASON_UNKNOWN, "pending": false}
	if _role == "client":
		if not _has_peers():
			return {"ok": false, "message": "The host is not reachable yet.", "body_id": merc_id,
				"previous_body_id": -1, "reason": SoulRouter.REASON_NONE, "pending": false}
		if not _known_body(merc_id):
			return _refuse(controller.local_peer_id, merc_id, SoulRouter.REASON_UNKNOWN)
		request_transfer.rpc_id(1, merc_id)
		return {"ok": true, "message": "Asked the host.", "body_id": merc_id,
			"previous_body_id": controller.merc_for_peer(controller.local_peer_id),
			"reason": SoulRouter.REASON_NONE, "pending": true}
	return _host_transfer(controller.local_peer_id, merc_id)

## Guest -> host. The sender's id comes from ENet, never from the payload, so a
## guest can only ever move its own soul; the body is checked against the roster
## before the router is touched.
@rpc("any_peer", "call_remote", "reliable")
func request_transfer(merc_id: int) -> void:
	if _role != "host" or controller == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or sender == controller.local_peer_id:
		return
	_host_transfer(sender, merc_id)

## Guest -> host handshake, so a late joiner learns who is inside what and who
## the other souls are.
@rpc("any_peer", "call_remote", "reliable")
func announce(guest_name: String) -> void:
	if _role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_names[sender] = guest_name.strip_edges()
	_broadcast_ownership()

## Host -> everyone: the occupancy map plus the names that go with it.
@rpc("authority", "call_remote", "reliable")
func receive_ownership(assignments: Dictionary, names: Dictionary) -> void:
	_names = names.duplicate()
	_adopt_ownership(assignments)

## Host -> the one soul whose request lost.
@rpc("authority", "call_remote", "reliable")
func receive_refusal(merc_id: int, reason: String) -> void:
	transfer_refused.emit(merc_id, reason)

# --- snapshots -------------------------------------------------------------

## Host -> everyone. Unreliable: the next snapshot supersedes this one, and the
## entries were already split to fit a single datagram each.
@rpc("authority", "call_remote", "unreliable")
func receive_snapshot(tick: int, entries: Array) -> void:
	if controller == null:
		return
	_sync_local_peer()
	var actors: Array = controller.bodies()
	for entry in entries:
		if typeof(entry) != TYPE_ARRAY:
			continue
		var pair: Array = entry
		if pair.size() < 2:
			continue
		var merc_id := int(pair[0])
		# A merc id this peer does not have is dropped before it reaches a node:
		# the wire can never invent a body or touch a stale one.
		if not _known_body(merc_id):
			continue
		var state: Variant = pair[1]
		var actor := controller.body_of(merc_id)
		if actor == null or typeof(state) != TYPE_DICTIONARY:
			continue
		actor.apply_snapshot(state, tick, actors)

# --- the world beyond the bodies -------------------------------------------
#
# Everything below is additive to the body replication above: the host owns the
# world's mobs, the loot and the missiles, and a guest receives them. A guest
# never runs a mob's brain and never trusts its own hits, which is why the mob
# classes' existing `replica` flag is the whole switching mechanism.

## Bind a `WarbandWorld` to this session. Called by `GameFlow` the moment the
## scene that fields the bodies binds, so it is also the moment the guards exist.
## Idempotent: re-attaching the same world only re-wires it.
func attach_world(world_node: Node3D) -> void:
	if world_node == null:
		return
	var same := world == world_node
	world = world_node
	if not same:
		_reset_world_trackers()
	_watch_world_tree()
	_wire_world_guards()
	if _role == "client":
		_mark_world_replicas()

## Every living mob in `world.guards` within `limit_metres` of any body, as
## `[name, snapshot]`. Bodies without a snapshot are skipped instead of being
## sent as an entry a client could never read.
func collect_mob_entries(limit_metres: float) -> Array:
	var entries: Array = []
	if world == null:
		return entries
	var bodies: Variant = world.get("bodies")
	var body_list: Array = []
	if bodies is Array:
		body_list = bodies
	for guard in _world_guards():
		if not is_instance_valid(guard) or not _mob_living(guard):
			continue
		if not guard is Node3D or not guard.has_method("snapshot"):
			continue
		if not _near_any_body((guard as Node3D).global_position, body_list, limit_metres):
			continue
		entries.append([str((guard as Node).name), guard.call("snapshot")])
	return entries

## Apply a batch of mob states to the guards with those names. A name this peer
## does not own is dropped before it reaches a node: the wire can never invent a
## mob, exactly as it can never invent a body. Public so the unit regression can
## drive it without a socket.
func apply_mob_states(tick: int, states: Array) -> void:
	if world == null:
		return
	for entry in states:
		if typeof(entry) != TYPE_ARRAY:
			continue
		var pair: Array = entry
		if pair.size() < 2:
			continue
		var guard = _guard_named(str(pair[0]))
		if guard == null or not guard.has_method("apply_snapshot"):
			continue
		var state: Variant = pair[1]
		if typeof(state) != TYPE_DICTIONARY:
			continue
		# The switch the mob classes already honour: no AI, no local authority,
		# and `apply_snapshot` becomes the only writer of pose and health.
		guard.set("replica", true)
		guard.call("apply_snapshot", state, tick)

## Pickups the host has not announced yet, as `[item_id, position]`. The instance
## id is booked here so a pickup that stays on the ground is sent exactly once.
func collect_new_loot() -> Array:
	var out: Array = []
	if world == null:
		return out
	var pickups: Variant = world.get("pickups")
	if not pickups is Array:
		return out
	var pickup_list: Array = pickups
	for pickup in pickup_list:
		if not is_instance_valid(pickup) or not pickup is Node3D:
			continue
		if bool(pickup.get("collected")):
			continue
		var key: int = (pickup as Node).get_instance_id()
		if _sent_loot.has(key):
			continue
		var item_id := str(pickup.get("item_id"))
		if item_id.is_empty():
			continue
		_sent_loot[key] = true
		out.append([item_id, (pickup as Node3D).global_position])
	return out

## Missiles the host has not announced yet, as `[origin, direction, speed]`.
## A guest only draws them; the host is the only place a hit is resolved.
func collect_new_missiles() -> Array:
	var out: Array = []
	if world == null:
		return out
	var missiles: Variant = world.get("projectiles")
	if not missiles is Array:
		return out
	var missile_list: Array = missiles
	for missile in missile_list:
		if not is_instance_valid(missile) or not missile is Node3D:
			continue
		var key: int = (missile as Node).get_instance_id()
		if _sent_missiles.has(key):
			continue
		var velocity: Variant = missile.get("velocity")
		if typeof(velocity) != TYPE_VECTOR3:
			continue
		var speed := (velocity as Vector3).length()
		if speed <= 0.05:
			continue
		_sent_missiles[key] = true
		out.append([(missile as Node3D).global_position, (velocity as Vector3) / speed, speed])
	return out

## Host -> everyone: the mobs a soul could reach. Unreliable, like the body
## snapshots; the next batch supersedes this one and each batch already fits one
## datagram.
@rpc("authority", "call_remote", "unreliable")
func receive_mobs(tick: int, states: Array) -> void:
	apply_mob_states(tick, states)

## Host -> everyone: a piece of loot hit the ground. Reliable, because a drop
## that is missed is a piece the guest can never see or take.
@rpc("authority", "call_remote", "reliable")
func receive_loot(item_id: String, at: Vector3) -> void:
	if world == null or item_id.is_empty():
		return
	var key := "%s@%.2f,%.2f,%.2f" % [item_id, at.x, at.y, at.z]
	if _delivered_loot.has(key):
		return
	_remember(_delivered_loot, key)
	if world.has_method("spawn_pickup"):
		world.call("spawn_pickup", item_id, at)

## Host -> everyone: a shot or a thrown blade. Visual only - a guest's copy can
## draw the flight but its mask is empty, so it can never resolve a hit.
@rpc("authority", "call_remote", "unreliable")
func receive_arrow(origin: Vector3, direction: Vector3, speed: float) -> void:
	if world == null or speed <= 0.0:
		return
	var heading := direction.normalized()
	if heading.is_zero_approx():
		return
	var key := "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f" % [origin.x, origin.y, origin.z,
		heading.x, heading.y, heading.z, speed]
	if _delivered_arrows.has(key):
		return
	_remember(_delivered_arrows, key)
	var arrow := ArrowScript.new()
	arrow.authoritative_damage = false
	arrow.hit_mask = 0
	world.add_child(arrow)
	arrow.launch(origin, heading, speed, 0.0, [])

## Host -> everyone: a mob died and paid out. Only the host resolves a kill, so
## only the host decides the amount; the purse lives in `PlayerState`, which is
## the one wallet every mode writes through.
@rpc("authority", "call_remote", "reliable")
func receive_reward(amount: int) -> void:
	if amount <= 0:
		return
	var state := get_node_or_null("/root/PlayerState")
	if state != null and state.has_method("add_credits"):
		state.add_credits(amount)
	if world == null:
		return
	var hud: Variant = world.get("hud")
	if hud == null or not is_instance_valid(hud):
		return
	# The strip reads `warband.gold()` and only repaints on the warband's signal;
	# a purse paid through `PlayerState` has to refresh itself.
	if hud.has_method("refresh_purse"):
		hud.call("refresh_purse")
	elif hud.has_method("_refresh_purse"):
		hud.call("_refresh_purse")

# --- internals: the host ---------------------------------------------------

## One decision, shared by the host's own hotkeys and by the RPC above.
func _host_transfer(peer_id: int, merc_id: int) -> Dictionary:
	if controller == null:
		return _refuse(peer_id, merc_id, SoulRouter.REASON_UNKNOWN)
	if not _known_body(merc_id):
		return _refuse(peer_id, merc_id, SoulRouter.REASON_UNKNOWN)
	if peer_id != controller.local_peer_id and not multiplayer.get_peers().has(peer_id):
		return _refuse(peer_id, merc_id, "That soul is not in this battle.")
	var result: Dictionary = controller.activate(peer_id, merc_id)
	if not bool(result.get("ok", false)):
		return _refuse(peer_id, merc_id, str(result.get("reason", SoulRouter.REASON_UNKNOWN)))
	var actor := controller.body_of(int(result.get("body_id", merc_id)))
	if actor != null and peer_id != controller.local_peer_id:
		# The authority may only step a peer's body on frames that peer actually
		# sent; an invented frame is the one correction no one can reconcile.
		actor.frame_driven = true
	_broadcast_ownership()
	return result

## The router's rules already refused; this only makes sure the one soul that
## asked hears about it, and never the lucky soul that was asking for a body
## that turned out to be free.
func _refuse(peer_id: int, merc_id: int, reason: String) -> Dictionary:
	var previous := controller.merc_for_peer(peer_id) if controller != null else -1
	if controller != null and peer_id == controller.local_peer_id:
		transfer_refused.emit(merc_id, reason)
	elif multiplayer.get_peers().has(peer_id):
		receive_refusal.rpc_id(peer_id, merc_id, reason)
	return {"ok": false, "message": reason, "body_id": merc_id,
		"previous_body_id": previous, "reason": reason, "pending": false}

func _broadcast_ownership() -> void:
	if _role != "host" or not _has_peers():
		return
	receive_ownership.rpc(ownership(), _names.duplicate())

func _has_peers() -> bool:
	return _peer != null and multiplayer != null and not multiplayer.get_peers().is_empty()

## Bodies this peer may name: in the roster (so an invented id is impossible)
## and registered by the scene (so a body that was never spawned cannot be hit).
func _known_body(merc_id: int) -> bool:
	if merc_id <= 0 or warband == null:
		return false
	if not warband.roster.has(merc_id):
		return false
	return warband.souls.has_body(merc_id)

# --- internals: the guest --------------------------------------------------

func _adopt_ownership(assignments: Dictionary) -> void:
	if controller == null:
		return
	_sync_local_peer()
	var next := {}
	for key in assignments:
		next[int(key)] = int(assignments[key])
	for key in _adopted:
		var peer_id := int(key)
		if int(_adopted[key]) > 0 and int(next.get(peer_id, 0)) <= 0:
			_release_body_of(peer_id, "That soul let the body go.")
	for key in next:
		var merc_id := int(next[key])
		if merc_id <= 0 or not _known_body(merc_id):
			continue
		controller.activate(int(key), merc_id)
	_adopted = next
	ownership_changed.emit(_adopted.duplicate())

## Give a body back on this process. The router is told first because it is the
## rule book; the controller then hands the body to the scene, where it keeps
## whatever AI flag the scene gave it.
func _release_body_of(peer_id: int, reason: String) -> void:
	if controller == null:
		return
	var owned := warband != null and warband.souls.body_of(peer_id) != -1
	var in_scene := controller.body_for_peer(peer_id) != null \
		or (peer_id == controller.local_peer_id and controller.active_actor != null)
	if warband != null:
		warband.souls.release_peer(peer_id, reason)
	if not owned and not in_scene:
		return
	var actor := controller.body_for_peer(peer_id)
	if actor != null:
		actor.frame_driven = false
	# `PossessionController` publishes a release for its own soul only; the
	# remote half is the same detach routine (body flags, intents, camera), and a
	# second copy of it here would drift from the one the controller keeps.
	controller._release_peer(peer_id, reason)

## A guest cannot know its ENet id before the handshake lands, and the map it is
## about to adopt is keyed by that id, so the soul id is refreshed first.
func _sync_local_peer() -> void:
	if controller == null or _role != "client" or multiplayer == null:
		return
	var id := multiplayer.get_unique_id()
	if id > 0 and controller.local_peer_id != id:
		controller.local_peer_id = id

# --- internals: the wire ---------------------------------------------------

func _process(delta: float) -> void:
	if _role == "client":
		_sync_local_peer()
		return
	if _role != "host" or controller == null or warband == null or not _has_peers():
		return
	var interval := 1.0 / SNAPSHOT_HZ
	# A hitch must not turn into a burst of stale snapshots.
	_accumulator = minf(_accumulator + delta, interval * 4.0)
	while _accumulator >= interval:
		_accumulator -= interval
		_send_snapshots()
	_tick_world(delta)

func _send_snapshots() -> void:
	_tick += 1
	var entries: Array = []
	for merc_id in warband.roster.ids():
		var actor := controller.body_of(merc_id)
		if actor == null:
			continue
		entries.append([merc_id, actor.snapshot()])
	if entries.is_empty():
		return
	for batch in NetLimits.batches(entries, [_tick]):
		receive_snapshot.rpc(_tick, batch)

# --- internals: the world --------------------------------------------------

## The world's clocks. Mobs and missiles are polled, not event-driven: a mob's
## pose only means "now", and a missile that was announced on the frame it was
## fired would arrive before the host's own first physics step moved it.
func _tick_world(delta: float) -> void:
	if world == null:
		return
	var mob_interval := 1.0 / MOB_SNAPSHOT_HZ
	_mob_accumulator = minf(_mob_accumulator + delta, mob_interval * 4.0)
	while _mob_accumulator >= mob_interval:
		_mob_accumulator -= mob_interval
		_send_mobs()
	_loot_accumulator += delta
	if _loot_accumulator >= LOOT_POLL_SECONDS:
		_loot_accumulator = fmod(_loot_accumulator, LOOT_POLL_SECONDS)
		_send_loot()
	_missile_accumulator += delta
	if _missile_accumulator >= MISSILE_POLL_SECONDS:
		_missile_accumulator = fmod(_missile_accumulator, MISSILE_POLL_SECONDS)
		_send_missiles()

func _send_mobs() -> void:
	_mob_tick += 1
	var entries := collect_mob_entries(MOB_REACH_METRES)
	entries.append_array(_collect_death_states())
	if entries.is_empty():
		return
	for batch in NetLimits.batches(entries, [_mob_tick]):
		receive_mobs.rpc(_mob_tick, batch)

## A guard that has died is no longer "living", so the collector above stops
## naming it - but a replica still has to see it fall. Each corpse is sent once,
## with the snapshot whose `a` is false, and then the wire forgets it.
func _collect_death_states() -> Array:
	var out: Array = []
	if world == null:
		return out
	var bodies: Variant = world.get("bodies")
	var body_list: Array = []
	if bodies is Array:
		body_list = bodies
	for guard in _world_guards():
		if not is_instance_valid(guard) or not guard is Node3D:
			continue
		if not guard.has_method("snapshot") or _mob_living(guard):
			continue
		var guard_name := str((guard as Node).name)
		if _dead_sent.has(guard_name):
			continue
		if not _near_any_body((guard as Node3D).global_position, body_list, MOB_REACH_METRES):
			continue
		_dead_sent[guard_name] = true
		out.append([guard_name, guard.call("snapshot")])
	return out

func _send_loot() -> void:
	for entry in collect_new_loot():
		receive_loot.rpc(str(entry[0]), entry[1])

func _send_missiles() -> void:
	for entry in collect_new_missiles():
		receive_arrow.rpc(entry[0], entry[1], float(entry[2]))

func _world_guards() -> Array:
	if world == null:
		return []
	var guards: Variant = world.get("guards")
	if guards is Array:
		return guards
	return []

func _guard_named(guard_name: String):
	if guard_name.is_empty():
		return null
	for guard in _world_guards():
		if not is_instance_valid(guard) or not guard is Node:
			continue
		if str((guard as Node).name) == guard_name:
			return guard
	return null

## A guard with no `alive` property is still treated as living: the wire must not
## silently hide a class this build does not recognise, and the regression's
## snapshot-less guard is skipped for the right reason (no snapshot), not this one.
func _mob_living(guard) -> bool:
	if guard == null or not is_instance_valid(guard):
		return false
	var alive: Variant = guard.get("alive")
	return alive == null or bool(alive)

func _near_any_body(point: Vector3, bodies: Array, limit_metres: float) -> bool:
	if bodies.is_empty():
		return false
	var reach := maxf(limit_metres, 0.0)
	reach *= reach
	for body in bodies:
		if not is_instance_valid(body) or not body is Node3D:
			continue
		if (body as Node3D).global_position.distance_squared_to(point) <= reach:
			return true
	return false

## The host is the only peer that resolves a mob's death, so it is the only peer
## that pays for it. A guest hears the amount and books it against its own purse.
func _on_guard_defeated(_enemy: Node3D, reward: int) -> void:
	if _role != "host" or reward <= 0 or not _has_peers():
		return
	receive_reward.rpc(reward)

## Wire the guards that already exist. Both peers do this: the host needs the
## `defeated` signal, and a client needs the same node switched to replica.
func _wire_world_guards() -> void:
	for guard in _world_guards():
		_wire_guard_signal(guard)
		if _role == "client":
			_mark_replica(guard)

func _wire_guard_signal(guard) -> void:
	if guard == null or not is_instance_valid(guard) or not guard is Node:
		return
	if not (guard as Node).has_signal("defeated"):
		return
	var callable := Callable(self, "_on_guard_defeated")
	if not (guard as Node).is_connected("defeated", callable):
		(guard as Node).connect("defeated", callable)

## A mob the world adds after the hand-off - a ring that wakes, a wave that
## spawns - still has to be a replica on a guest and still has to pay on a host.
func _on_world_node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_signal("defeated"):
		_wire_guard_signal(node)
	if _role != "client":
		return
	# `node_added` fires before `_ready`, so the group may not be joined yet; the
	# snapshot surface is the same contract and is present from construction.
	if node.has_method("apply_snapshot") or node.is_in_group(WILD_MOB_GROUP):
		_mark_replica(node)

func _mark_world_replicas() -> void:
	for guard in _world_guards():
		_mark_replica(guard)

func _mark_replica(guard) -> void:
	if guard == null or not is_instance_valid(guard) or not guard is Node:
		return
	# The one switch every wilderness mob already honours: its physics frame
	# returns before any AI, and `apply_snapshot` is the sole writer of pose.
	(guard as Node).set("replica", true)

func _watch_world_tree() -> void:
	if _world_watch or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	if not tree.node_added.is_connected(_on_world_node_added):
		tree.node_added.connect(_on_world_node_added)
	_world_watch = true

func _unwatch_world_tree() -> void:
	if not _world_watch:
		return
	_world_watch = false
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_world_node_added):
		tree.node_added.disconnect(_on_world_node_added)

func _detach_world() -> void:
	_unwatch_world_tree()
	world = null
	_reset_world_trackers()

func _reset_world_trackers() -> void:
	_sent_loot.clear()
	_sent_missiles.clear()
	_dead_sent.clear()
	_delivered_loot.clear()
	_delivered_arrows.clear()
	_mob_accumulator = 0.0
	_loot_accumulator = 0.0
	_missile_accumulator = 0.0
	_mob_tick = 0

## Book a payload that has been spawned, clearing the book when it is full. A
## repeat announcement then costs one dictionary lookup.
func _remember(book: Dictionary, key: String) -> void:
	if book.size() >= DELIVERY_BOOK_CAP:
		book.clear()
	book[key] = true

func _wire_signals() -> void:
	if _signals_wired or multiplayer == null:
		return
	_signals_wired = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _unwire_signals() -> void:
	if not _signals_wired or multiplayer == null:
		return
	_signals_wired = false
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.disconnect(_on_connected)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _teardown() -> void:
	_unwire_signals()
	_detach_world()
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_names.clear()
	_accumulator = 0.0
	_tick = 0

func _on_connected() -> void:
	_sync_local_peer()
	announce.rpc_id(1, _player_name)

func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var merc_id := controller.merc_for_peer(peer_id) if controller != null else -1
	_release_body_of(peer_id, "That soul left the battle.")
	if merc_id > 0 and controller != null:
		# The body stays on the field under its own AI rather than freezing.
		controller.set_bot(merc_id, true)
	_names.erase(peer_id)
	if _role == "host":
		_broadcast_ownership()
	peer_left.emit(peer_id)

func _on_connection_failed() -> void:
	_end("Could not join.")

func _on_server_disconnected() -> void:
	_end("The host left.")

func _end(reason: String) -> void:
	var was := _role
	_role = "offline"
	if controller != null:
		_release_body_of(controller.local_peer_id, reason)
	_teardown()
	_adopted = {}
	if was != "offline":
		role_changed.emit(_role)
