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
##     invented to fill a gap).
##
## The scene spawns the bodies before `setup`; the session replicates them and
## never ticks `physics_step`, never reads `Input`, and never decides who is
## inside what - it asks `SoulRouter` and obeys. Both peers must mount it at the
## same node path, because that path is the RPC address.

const NetLimits = preload("res://scripts/net_limits.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")

## How often the host writes every body to the wire.
const SNAPSHOT_HZ := 20.0
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
