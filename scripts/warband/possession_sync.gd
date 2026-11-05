class_name PossessionSync
extends Node
## The soul's own half of the wire: who is inside what, decided by the host and
## obeyed by everyone else.
##
## The *ownership* wire is `WarbandSession`'s: a guest asks (`request_transfer`),
## the host decides and broadcasts the `{peer: merc_id}` map, and a guest adopts
## it through `PossessionController.adopt` - which takes the host's word through
## `SoulRouter.assign` rather than re-validating it against a replica that may
## still believe the body is downed. This node carries the host's in-process form
## of that same decision (`server_apply`, for the host's own hotkeys and the
## single-process regression) and the per-frame intents the controller sends.

signal possession_applied(peer_id: int, merc_id: int)
signal possession_refused(peer_id: int, merc_id: int, reason: String)

const WarbandState = preload("res://scripts/warband/warband_state.gd")
const NetReplication = preload("res://scripts/net_replication.gd")

## Untyped so the controller and this script do not preload each other.
var controller
var warband: WarbandState
var _router: SoulRouter

## The high-frequency uplink: what this soul sends to the host, held for the
## simulated link when one was asked for (`NetReplication.requested_link`).
var _link = NetReplication.LagQueue.new()

func setup(warband_node: WarbandState, possession_controller = null) -> void:
	warband = warband_node
	_router = warband.souls if warband != null else null
	if possession_controller != null:
		controller = possession_controller
	# One direction of a simulated link: this peer's intents take `lag` seconds to
	# leave, and the host's answers take it to come back, which is a round trip.
	var asked := NetReplication.requested_link()
	_link.configure(asked.x, asked.y, asked.z)


## The simulated link's own clock. A deferred packet lands on the physics frame
## the link would have delivered it on, so the 60 Hz intents keep their cadence.
func _physics_process(_delta: float) -> void:
	if _link.active():
		_link.drain()

## 1 is the host in ENet, and an offline game is its own host.
func is_host() -> bool:
	return multiplayer == null or multiplayer.get_unique_id() == 1

# --- ownership -------------------------------------------------------------

## The host's decision, without a network round trip: the router validates, the
## controller wires the scene to the answer, and a refusal leaves both souls
## exactly where they were. The wire form of this is `WarbandSession`'s map.
func server_apply(peer_id: int, merc_id: int) -> Dictionary:
	if _router == null:
		return {"ok": false, "message": "No warband.", "body_id": merc_id,
			"previous_body_id": -1, "reason": SoulRouter.REASON_UNKNOWN}
	var result: Dictionary
	if controller != null:
		# The controller validates through the router and wires the scene in the
		# same step, so the host and the wire cannot disagree.
		result = controller.activate(peer_id, merc_id)
	else:
		result = _router.request_transfer(peer_id, merc_id)
		if bool(result.get("ok", false)) and warband != null:
			warband.note_possession(peer_id, merc_id)
	if bool(result.get("ok", false)):
		possession_applied.emit(peer_id, merc_id)
	else:
		possession_refused.emit(peer_id, merc_id, str(result.get("reason", "")))
	return result

# --- intents ---------------------------------------------------------------

## Client -> host movement frame for the body that peer is inside. The frame's
## number, the tick its owner was drawing and the three frames behind it ride
## along, so the host simulates exactly the intents that peer recorded.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func move_input(direction: Vector2, running: bool, point: Variant = null,
		origin: Variant = null, seq: Variant = -1, view: Variant = -1,
		history: Array = []) -> void:
	if not is_host():
		return
	var merc_id := _sender_body()
	if merc_id <= 0 or controller == null:
		return
	controller.apply_move(merc_id, direction, running, point, origin,
		int(seq) if typeof(seq) == TYPE_INT else -1,
		int(view) if typeof(view) == TYPE_INT else -1,
		history if typeof(history) == TYPE_ARRAY else [])

## Client -> host combat verb. Only the host resolves damage, parry or stamina,
## so a guest can never invent its own hit - and `view` is the tick that guest
## was drawing, which is the frame the host resolves the blow against.
@rpc("any_peer", "call_remote", "reliable")
func action_input(action: String, value: Variant = null, origin: Variant = null,
		view: Variant = -1) -> void:
	if not is_host():
		return
	var merc_id := _sender_body()
	if merc_id <= 0 or controller == null:
		return
	controller.apply_action(merc_id, action, value, origin,
		int(view) if typeof(view) == TYPE_INT else -1)

## This peer's own frame, on its way to the host.
func send_move(direction: Vector2, running: bool, point: Variant = null,
		origin: Variant = null, seq: int = -1, view: int = -1, history: Array = []) -> void:
	if is_host() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	# A move frame travels `unreliable_ordered`, so a real link may lose it and the
	# simulated one may too; a combat verb below is `reliable` and never is.
	var guarded := func():
		# Held past the handshake: the socket may be gone by the time it is due.
		if multiplayer == null or not multiplayer.has_multiplayer_peer() \
				or multiplayer.get_peers().is_empty():
			return
		move_input.rpc_id(1, direction, running, point, origin, seq, view, history)
	_link.defer(guarded, true)

func send_action(action: String, value: Variant = null, origin: Variant = null,
		view: int = -1) -> void:
	if is_host() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	var guarded := func():
		if multiplayer == null or not multiplayer.has_multiplayer_peer() \
				or multiplayer.get_peers().is_empty():
			return
		action_input.rpc_id(1, action, value, origin, view)
	_link.defer(guarded)

func _sender_body() -> int:
	if _router == null or multiplayer == null:
		return -1
	return _router.body_of(multiplayer.get_remote_sender_id())
