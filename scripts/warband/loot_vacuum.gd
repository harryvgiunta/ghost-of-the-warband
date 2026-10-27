class_name WarbandLoot
extends Node
## Battlefield looting for the warband: the real world drop, the instant
## single-piece pick a human makes, and the end-of-battle vacuum that moves every
## remaining drop straight into the infinite shared stash.
##
## There is no mode-local pile of loot here. A collected piece is a
## `WarbandStash` row the instant it is taken, so the stash stays the single
## container and the warband's worth is always the stash's worth.
##
## `sweep()` only moves what a living body could walk over: reach is measured from
## the survivors, and a battle that leaves nobody standing gathers nothing - the
## dead do not loot themselves.

const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## How far one survivor reaches on the battlefield. Generous on purpose: a drop
## is only left behind when it is nowhere near any living body.
const BATTLE_REACH := 60.0

## The warband this vacuum feeds. Kept untyped because `Warband` is an autoload
## script with no class name of its own.
var _warband = null
## Answers "which mercenary is this peer inside right now?" (-1 for none). When
## it answers, a hand pickup snaps into that body's hands instead of only landing
## in the stash: looting a blade is how a soul gets armed.
var equip_target := Callable()
## Where drops are parented. Null means the vacuum's own parent or the scene.
var _pickups_root: Node3D = null
## Drops this node made, including any whose parent is not under the root, so a
## sweep cannot miss a piece it is responsible for.
var _spawned: Array[WarbandPickup] = []
## Every id that has passed through this vacuum, in the order it was taken.
var _gathered: Array[String] = []

## Point the vacuum at a warband and, optionally, at the node that hosts the
## drops. Without a pickups root the parent (or the current scene) hosts them.
func setup(warband, pickups_root: Node3D = null) -> void:
	_warband = warband
	if pickups_root != null:
		_pickups_root = pickups_root

## Drop one real piece into the world at `at`. `armed` false makes it a locked
## drop for `dropper_peer` until `WarbandPickup.ARM_DELAY` has passed.
func spawn(item_id: String, at: Vector3, armed: bool = true, dropper_peer: int = 0) -> WarbandPickup:
	if not State.ITEMS.has(item_id):
		push_warning("WarbandLoot: %s is not a catalog item" % item_id)
		return null
	var host := _pickup_host()
	if host == null:
		push_warning("WarbandLoot: no node can host a drop")
		return null
	var pickup := WarbandPickup.new()
	pickup.setup(item_id)
	if armed:
		pickup.dropper_peer = dropper_peer
	else:
		pickup.disarm(dropper_peer)
	host.add_child(pickup)
	pickup.global_position = at
	_spawned.append(pickup)
	return pickup

## A human takes one drop instantly. There is no distance check here: the caller
## already decided the body under the crosshair reaches it.
func quick_loot(pickup: WarbandPickup, collector_peer: int = 1) -> Dictionary:
	if not is_instance_valid(pickup):
		return _refused("There is no drop to take.", "")
	if pickup.collected:
		return _refused("That drop has already been taken.", pickup.item_id)
	if pickup.item_id.is_empty():
		return _refused("That drop holds nothing.", "")
	if pickup.blocked_for(collector_peer):
		return _refused("You cannot take back the piece you just dropped.", pickup.item_id)
	var stash := _stash()
	if stash == null:
		return _refused("The shared stash is missing.", pickup.item_id)
	var item_id := pickup.item_id
	stash.add(item_id, 1)
	_gathered.append(item_id)
	pickup.collect()
	_notify_warband()
	var message := "%s goes into the shared stash." % WarbandPickup.item_name(item_id)
	var merc_id := _equip_owner(collector_peer)
	if merc_id > 0 and _warband != null:
		var auto: Dictionary = _warband.auto_equip(merc_id, item_id)
		if bool(auto.get("ok", false)):
			message = "%s goes to %s (%s)." % [WarbandPickup.item_name(item_id),
				_warband.roster.name_of(merc_id),
				Contracts.slot_id_label(str(auto.get("slot", "")))]
	return {"ok": true, "item_id": item_id, "message": message}

## The mercenary the pickup should be worn by, or -1. A callable that throws or
## answers nonsense simply means "keep it in the stash".
func _equip_owner(peer_id: int) -> int:
	if not equip_target.is_valid():
		return -1
	var answer: Variant = equip_target.call(peer_id)
	if typeof(answer) != TYPE_INT:
		return -1
	return int(answer)

## The end-of-battle sweep. Every drop under the root (plus every drop this node
## made itself) that a survivor can reach moves into the shared stash and leaves
## the world. `survivors` affects reach only; with no survivors nothing is
## gathered and the drops stay where they fell.
func sweep(survivors: Array) -> Dictionary:
	var pickups := _live_pickups()
	if survivors.is_empty():
		return _sweep_result(false, [], pickups.size(),
			"No survivors: the dead keep their steel.")
	var anchors := _survivor_positions(survivors)
	if anchors.is_empty():
		return _sweep_result(false, [], pickups.size(),
			"No living body is standing on the battlefield.")
	var stash := _stash()
	if stash == null:
		return _sweep_result(false, [], pickups.size(), "The shared stash is missing.")
	var ids: Array[String] = []
	var skipped := 0
	for pickup in pickups:
		if not _within_reach(pickup.global_position, anchors):
			skipped += 1
			continue
		ids.append(pickup.item_id)
		stash.add(pickup.item_id, 1)
		_gathered.append(pickup.item_id)
		pickup.collect()
	ids.sort()
	_notify_warband()
	var message := "The warband sweeps %d piece(s) into the shared stash." % ids.size()
	if skipped > 0:
		message += " %d drop(s) lay beyond the battlefield." % skipped
	return _sweep_result(true, ids, skipped, message)

## What this vacuum has pulled off the ground so far, valued by the same rule the
## stash sorts with, so a battle report and the stash rows always agree.
func battlefield_value() -> int:
	var total := 0
	for item_id in _gathered:
		total += StashScript.value_of(item_id)
	return total

## One line for the battle log and for tests.
func describe() -> String:
	return "drops=%d gathered=%d value=%d" % [
		_live_pickups().size(), _gathered.size(), battlefield_value()]

# --- internals -------------------------------------------------------------

## The drops a scene can offer to a player right now, in spawn order. Prompts and
## quick-loot both read this instead of walking the tree themselves.
func pickups() -> Array[WarbandPickup]:
	return _live_pickups()

## Every drop this vacuum still owns, one entry per node: the ones it spawned plus
## any pickup sitting under the root, so a scene that drops its own loot is swept
## too. Also prunes the spawned list so a freed drop is never walked again.
func _live_pickups() -> Array[WarbandPickup]:
	var seen: Dictionary = {}
	var out: Array[WarbandPickup] = []
	var live: Array[WarbandPickup] = []
	for pickup in _spawned:
		if not is_instance_valid(pickup) or pickup.collected:
			continue
		live.append(pickup)
		if not seen.has(pickup.get_instance_id()):
			seen[pickup.get_instance_id()] = true
			out.append(pickup)
	_spawned = live
	if is_instance_valid(_pickups_root):
		_collect_under(_pickups_root, seen, out)
	return out

func _collect_under(node: Node, seen: Dictionary, out: Array[WarbandPickup]) -> void:
	for child in node.get_children():
		if child is WarbandPickup:
			var pickup := child as WarbandPickup
			if not pickup.collected and not seen.has(pickup.get_instance_id()):
				seen[pickup.get_instance_id()] = true
				out.append(pickup)
		_collect_under(child, seen, out)

## A survivor is a living body still on the field. Only its position matters, so
## a roster record or a peer id contributes nothing and is simply skipped.
func _survivor_positions(survivors: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for body in survivors:
		if not is_instance_valid(body):
			continue
		if body is Node3D:
			out.append((body as Node3D).global_position)
	return out

func _within_reach(point: Vector3, anchors: Array[Vector3]) -> bool:
	var reach := BATTLE_REACH * BATTLE_REACH
	for anchor in anchors:
		if point.distance_squared_to(anchor) <= reach:
			return true
	return false

## The site drops are parented to: the configured root, else the parent when it is
## spatial, else the current scene so a drop is never orphaned.
func _pickup_host() -> Node:
	if is_instance_valid(_pickups_root):
		return _pickups_root
	var parent := get_parent()
	if parent != null:
		return parent
	if is_inside_tree():
		var scene := get_tree().current_scene
		if scene != null:
			return scene
	return null

## The infinite shared stash, resolved through the warband (or the autoload when
## this node was never handed one).
func _stash() -> WarbandStash:
	if _warband == null or not is_instance_valid(_warband):
		_warband = get_node_or_null("/root/Warband") if is_inside_tree() else null
	if _warband == null:
		return null
	var stash: Variant = _warband.get("stash")
	return stash if stash is WarbandStash else null

## The stash is the warband's, so its change signal is the one the HUD listens to.
func _notify_warband() -> void:
	if _warband != null and is_instance_valid(_warband) and _warband.has_signal("changed"):
		_warband.changed.emit()

func _refused(message: String, item_id: String) -> Dictionary:
	return {"ok": false, "message": message, "item_id": item_id}

func _sweep_result(ok: bool, ids: Array[String], skipped: int, message: String) -> Dictionary:
	return {"ok": ok, "message": message, "collected": ids.size(), "item_ids": ids,
		"skipped": skipped}
