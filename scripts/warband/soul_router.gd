class_name SoulRouter
extends RefCounted
## The soul: one player, many bodies. The authoritative registry of every
## mercenary body that can be entered, who is inside it, and the transfer rules.
##
## Contract (Phase 0):
##   * exactly one peer per body (`occupied_by_peer_id`);
##   * a body can only be entered while it is ALIVE (a DOWNED body is revived,
##     never jumped into);
##   * a transfer is refused when the target is occupied by another peer, dead,
##     downed or unknown, and the refusal names the reason;
##   * a peer whose body is destroyed, downed or leaves is released rather than
##     left pointing at a corpse.
##
## This class never touches the scene graph beyond `Node3D` lookups, so the cage
## tutorial, the town hub, the admin arena and the expedition all share it.

signal body_registered(body_id: int)
signal body_unregistered(body_id: int)
signal body_state_changed(body_id: int, state: int)
signal body_possessed(peer_id: int, body_id: int)
signal body_released(peer_id: int, body_id: int)
signal transfer_refused(peer_id: int, body_id: int, reason: String)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## Refusal reasons, so the HUD can say something true.
const REASON_UNKNOWN := "That body is not in the warband."
const REASON_DEAD := "The dead do not answer."
const REASON_DOWNED := "That one is down. Revive them first."
const REASON_OCCUPIED := "Another soul is already inside that body."
const REASON_NONE := ""

var _bodies: Dictionary = {}   # body_id -> {node, name, state, occupied_by_peer_id, last_owner_peer_id}
var _peer_body: Dictionary = {}  # peer_id -> body_id

# --- registration ----------------------------------------------------------

func register_body(body_id: int, node: Node3D, display_name: String = "") -> void:
	if body_id <= 0:
		return
	var record := {
		"body_id": body_id,
		"node": node,
		"name": display_name,
		"state": Contracts.HealthState.ALIVE,
		"occupied_by_peer_id": 0,
		"last_owner_peer_id": 0,
	}
	var previous: Variant = _bodies.get(body_id)
	if previous is Dictionary:
		var owner_id := int(previous.get("occupied_by_peer_id", 0))
		if owner_id != 0:
			_peer_body.erase(owner_id)
	record["occupied_by_peer_id"] = int((previous as Dictionary).get("occupied_by_peer_id", 0)) if previous is Dictionary else 0
	_bodies[body_id] = record
	body_registered.emit(body_id)

func unregister_body(body_id: int) -> void:
	if not _bodies.has(body_id):
		return
	var record: Dictionary = _bodies[body_id]
	var owner_id := int(record.get("occupied_by_peer_id", 0))
	if owner_id != 0:
		_peer_body.erase(owner_id)
		body_released.emit(owner_id, body_id)
	_bodies.erase(body_id)
	body_unregistered.emit(body_id)

func has_body(body_id: int) -> bool:
	return _bodies.has(body_id)

func body_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _bodies:
		out.append(int(id))
	out.sort()
	return out

func body_node(body_id: int) -> Node3D:
	var record: Variant = _bodies.get(body_id)
	if record is Dictionary:
		var node: Variant = record.get("node")
		if node is Node3D and is_instance_valid(node):
			return node
	return null

func body_name(body_id: int) -> String:
	var record: Variant = _bodies.get(body_id)
	return str((record as Dictionary).get("name", "")) if record is Dictionary else ""

func body_state(body_id: int) -> int:
	var record: Variant = _bodies.get(body_id)
	if not record is Dictionary:
		return Contracts.HealthState.DEAD
	return int(record.get("state", Contracts.HealthState.DEAD))

## 0 when nobody is inside. This is the lock the whole system hangs on.
func occupied_by(body_id: int) -> int:
	var record: Variant = _bodies.get(body_id)
	if not record is Dictionary:
		return 0
	return int(record.get("occupied_by_peer_id", 0))

func body_of(peer_id: int) -> int:
	return int(_peer_body.get(peer_id, -1))

func is_possessed(peer_id: int) -> bool:
	return _peer_body.has(peer_id)

# --- state ------------------------------------------------------------------

## Health/downed updates arrive from the body or the roster. A body that stops
## being alive releases whoever was inside it.
func set_body_state(body_id: int, state: int) -> void:
	var record: Variant = _bodies.get(body_id)
	if not record is Dictionary:
		return
	var previous := int(record.get("state", Contracts.HealthState.ALIVE))
	record["state"] = state
	if previous != state:
		body_state_changed.emit(body_id, state)
	if state != Contracts.HealthState.ALIVE:
		var owner_id := int(record.get("occupied_by_peer_id", 0))
		if owner_id != 0:
			release_peer(owner_id, Contracts.state_name(state))

# --- transfer ---------------------------------------------------------------

## The one entry point for entering a body: hotkey cycling, a click in the
## warband screen and the tutorial's forced shift all come through here.
## Returns `{ok, message, body_id, previous_body_id, reason}`.
func request_transfer(peer_id: int, target_body_id: int) -> Dictionary:
	var result := _refuse(peer_id, target_body_id, "")
	if not bool(result["ok"]):
		return result
	var current_id := body_of(peer_id)
	if current_id == target_body_id:
		return {"ok": true, "message": "Already inside %s." % _label(target_body_id),
			"body_id": target_body_id, "previous_body_id": current_id, "reason": REASON_NONE}
	if current_id != -1:
		var current: Variant = _bodies.get(current_id)
		if current is Dictionary:
			current["last_owner_peer_id"] = peer_id
			current["occupied_by_peer_id"] = 0
		_peer_body.erase(peer_id)
	var target: Dictionary = _bodies[target_body_id]
	target["occupied_by_peer_id"] = peer_id
	target["last_owner_peer_id"] = peer_id
	_peer_body[peer_id] = target_body_id
	if current_id != -1:
		body_released.emit(peer_id, current_id)
	body_possessed.emit(peer_id, target_body_id)
	return {"ok": true, "message": "You are inside %s." % _label(target_body_id),
		"body_id": target_body_id, "previous_body_id": current_id, "reason": REASON_NONE}

## Check the rules without moving a soul.
func can_transfer(peer_id: int, target_body_id: int) -> Dictionary:
	return _refuse(peer_id, target_body_id, "")

func _refuse(peer_id: int, target_body_id: int, reason: String) -> Dictionary:
	if not _bodies.has(target_body_id):
		return _refused(peer_id, target_body_id, REASON_UNKNOWN)
	var record: Dictionary = _bodies[target_body_id]
	var state := int(record.get("state", Contracts.HealthState.ALIVE))
	if state == Contracts.HealthState.DEAD:
		return _refused(peer_id, target_body_id, REASON_DEAD)
	if state == Contracts.HealthState.DOWNED:
		return _refused(peer_id, target_body_id, REASON_DOWNED)
	var holder := int(record.get("occupied_by_peer_id", 0))
	if holder != 0 and holder != peer_id:
		return _refused(peer_id, target_body_id, REASON_OCCUPIED)
	return {"ok": true, "message": "", "body_id": target_body_id,
		"previous_body_id": body_of(peer_id), "reason": REASON_NONE}

func _refused(peer_id: int, target_body_id: int, reason: String) -> Dictionary:
	transfer_refused.emit(peer_id, target_body_id, reason)
	return {"ok": false, "message": reason, "body_id": target_body_id,
		"previous_body_id": body_of(peer_id), "reason": reason}

## Give up the body (death, disconnect, scene hand-off).
func release_peer(peer_id: int, reason: String = "") -> void:
	var body_id := body_of(peer_id)
	if body_id == -1:
		return
	var record: Variant = _bodies.get(body_id)
	if record is Dictionary:
		record["occupied_by_peer_id"] = 0
		record["last_owner_peer_id"] = peer_id
	_peer_body.erase(peer_id)
	body_released.emit(peer_id, body_id)

## Living bodies a peer could enter, in body-id order. The peer's own body is
## included so cycling wraps onto itself rather than skipping.
func possessable_ids() -> Array[int]:
	var out: Array[int] = []
	for body_id in body_ids():
		if body_state(body_id) != Contracts.HealthState.ALIVE:
			continue
		var holder := occupied_by(body_id)
		if holder != 0:
			continue
		out.append(body_id)
	return out

## Next/previous living body for the hotkey cycle. `direction` is +1 or -1.
## Returns the same `request_transfer` payload; a refusal leaves the soul put.
func cycle(peer_id: int, direction: int = 1, include_self: bool = false) -> Dictionary:
	var candidates := possessable_ids()
	var current := body_of(peer_id)
	if candidates.is_empty():
		return {"ok": false, "message": "No living body is free to enter.",
			"body_id": current, "previous_body_id": current, "reason": REASON_DEAD}
	if not include_self and candidates.size() <= 1 and candidates.has(current):
		return {"ok": true, "message": "You are the only body standing.", "body_id": current,
			"previous_body_id": current, "reason": REASON_NONE}
	var step := 1 if direction >= 0 else -1
	var index := candidates.find(current)
	var target := candidates[0]
	if index == -1:
		target = candidates[0] if step > 0 else candidates[candidates.size() - 1]
	else:
		var size := candidates.size()
		for offset in range(1, size + 1):
			var probe := candidates[posmod(index + step * offset, size)]
			if probe != current or size == 1:
				target = probe
				break
	return request_transfer(peer_id, target)

func clear() -> void:
	_bodies.clear()
	_peer_body.clear()

func description() -> String:
	var parts: PackedStringArray = []
	for body_id in body_ids():
		parts.append("%d:%s%s" % [body_id, body_name(body_id),
			"@" + str(occupied_by(body_id)) if occupied_by(body_id) != 0 else ""])
	return " | ".join(parts)

func _label(body_id: int) -> String:
	var label := body_name(body_id)
	return label if not label.is_empty() else "body %d" % body_id
