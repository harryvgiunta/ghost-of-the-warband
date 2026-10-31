class_name PossessionSync
extends Node
## The wire half of the soul: who is inside what, decided by the host and
## obeyed by everyone else.
##
## A client never moves its own soul. It asks (`request_transfer`), the host
## checks the `SoulRouter` and either broadcasts the new occupancy
## (`apply_possession`) or refuses with the router's reason. That asymmetry is
## the whole point: two peers pressing `]` at the same instant must not both end
## up inside the same body, and a refusal must leave both souls exactly where
## they were.
##
## `server_apply()` is the same decision without a network round trip, so the
## host's own hotkeys and a single-process regression drive the identical code.

signal possession_applied(peer_id: int, merc_id: int)
signal possession_refused(peer_id: int, merc_id: int, reason: String)

const WarbandState = preload("res://scripts/warband/warband_state.gd")

## Untyped so the controller and this script do not preload each other.
var controller
var warband: WarbandState
var _router: SoulRouter

func setup(warband_node: WarbandState, possession_controller = null) -> void:
	warband = warband_node
	_router = warband.souls if warband != null else null
	if possession_controller != null:
		controller = possession_controller

## 1 is the host in ENet, and an offline game is its own host.
func is_host() -> bool:
	return multiplayer == null or multiplayer.get_unique_id() == 1

# --- ownership -------------------------------------------------------------

## Client -> host. The sender's own soul is the only one it may move, so the
## request carries a body and no peer id at all.
@rpc("any_peer", "call_remote", "reliable")
func request_transfer(body_id: int) -> void:
	if not is_host() or multiplayer == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var result := server_apply(sender, body_id)
	if not bool(result.get("ok", false)):
		refuse.rpc_id(sender, body_id, str(result.get("reason", "")))

@rpc("authority", "call_remote", "reliable")
func refuse(body_id: int, reason: String) -> void:
	possession_refused.emit(multiplayer.get_unique_id() if multiplayer != null else 0,
		body_id, reason)

## Host -> everyone. The receiving scene adopts the occupancy the host decided.
@rpc("authority", "call_remote", "reliable")
func apply_possession(peer_id: int, merc_id: int) -> void:
	_adopt(peer_id, merc_id)

## The host's one decision point, shared by hotkeys, the warband screen and the
## RPC above. Returns the router payload (`ok`, `message`, `body_id`, ...).
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
		_broadcast(peer_id, merc_id)
		possession_applied.emit(peer_id, merc_id)
	else:
		possession_refused.emit(peer_id, merc_id, str(result.get("reason", "")))
	return result

func _adopt(peer_id: int, merc_id: int) -> void:
	if controller != null:
		controller.activate(peer_id, merc_id)
		return
	if _router == null:
		return
	var result := _router.request_transfer(peer_id, merc_id)
	if bool(result.get("ok", false)) and warband != null:
		warband.note_possession(peer_id, merc_id)
		possession_applied.emit(peer_id, merc_id)
	else:
		possession_refused.emit(peer_id, merc_id, str(result.get("reason", "")))

func _broadcast(peer_id: int, merc_id: int) -> void:
	# An offline or single-process game has nobody to tell, and `rpc()` without
	# a multiplayer peer would only log noise.
	if multiplayer == null or not multiplayer.has_multiplayer_peer() or not is_host():
		return
	apply_possession.rpc(peer_id, merc_id)

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
	move_input.rpc_id(1, direction, running, point, origin, seq, view, history)

func send_action(action: String, value: Variant = null, origin: Variant = null,
		view: int = -1) -> void:
	if is_host() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	action_input.rpc_id(1, action, value, origin, view)

func _sender_body() -> int:
	if _router == null or multiplayer == null:
		return -1
	return _router.body_of(multiplayer.get_remote_sender_id())
