class_name WarbandLoot
extends Node
## Battlefield looting for the warband: the real world drop, the instant
## single-piece pick a human makes, and the end-of-battle vacuum that moves every
## remaining drop straight into the infinite shared stash.
##
## There is no mode-local pile of loot here. A collected piece is a
## `WarbandStash` row the instant it is taken, so the stash stays the single
## container and the warband's worth is always the stash's worth. Below, in the
## delve, that row is in the delve inventory instead (`Warband.field_stash`): what
## the party takes in the cave is the party's until it climbs out.
##
## A fallen enemy is a container too, not a heap on the floor: `register_corpse()`
## reads the kit once and holds it on a record keyed by corpse id, so the corpse
## screen and the squad's own sweep search the body rather than a scattering of
## world drops. Every take - a pickup under the crosshair, a piece clicked off a
## body, an AI claim - walks `_book_piece()`, so there is exactly one way into
## the stash and a corpse can yield each piece once. That one path also says so
## (`booked`), which is what the looted list on the HUD is drawn from.
##
## `sweep()` only moves what a living body could walk over: reach is measured from
## the survivors, and a battle that leaves nobody standing gathers nothing - the
## dead do not loot themselves.

## One piece just entered the warband's pool. `collector_peer` is the soul whose
## hands took it, or 0 for the warband itself (a squadmate, a sweep).
signal booked(item_id: String, collector_peer: int)
## A body became a container. The host's session copies this record to every
## guest the moment it exists, wherever the kill was booked (a camp, the trail,
## the delve or the open wood).
signal corpse_registered(corpse_id: int)
## A body's list of pieces changed, so a co-op guest's copy can be told without
## shipping the whole corpse every time. Fires after the piece has left the body.
signal corpse_changed(corpse_id: int, items: Array)
## A drop left the ground, with where it lay: the one announcement that lets a
## guest's own copy of the drop go away at the same instant the host's does.
signal drop_taken(item_id: String, at: Vector3)

const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")

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
## Registered bodies, keyed by corpse id: `{id, enemy, items}`. The record is not
## an inventory of its own - `items` is what the enemy answered to `gear_items()`
## when it fell, and a piece leaves it only through `_book_piece()`. An empty
## `items` list means the body is stripped; a freed enemy takes the record with
## it, so a stale position is never reported.
var _corpses: Dictionary = {}
## Corpse ids are never reused: a screen or a running job may still name a body
## that has since been searched empty.
var _next_corpse_id := 1

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
## already decided the body under the crosshair reaches it. `dress` false books
## the piece into the pool without putting it on the taker's body.
func quick_loot(pickup: WarbandPickup, collector_peer: int = 1, dress: bool = true) -> Dictionary:
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
	# Heard where the piece lay, before `collect()` takes the node out of the
	# tree: one pickup is one sound, and the drop's position is about to go.
	var at := pickup.global_position
	var awoke := _book_piece(stash, item_id, collector_peer, pickup.anointed)
	pickup.collect()
	drop_taken.emit(item_id, at)
	SfxScript.pickup(at)
	_notify_warband()
	var message := _dress_message(item_id, collector_peer if dress else 0)
	if awoke:
		message += " %s." % str(_warband.cruor.anoint_line(item_id))
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
##
## Corpses are not swept here: a body is searched by `claim_corpse()` (the squad)
## or by the corpse screen, so the end-of-battle vacuum cannot book a piece twice
## when a scene also left it lying on the ground.
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
		# One chime per piece, at the drop itself. The node is about to leave the
		# tree, so the position is read first.
		var at: Vector3 = pickup.global_position
		_book_piece(stash, pickup.item_id, 0, pickup.anointed)
		ids.append(pickup.item_id)
		pickup.collect()
		SfxScript.pickup(at)
	ids.sort()
	_notify_warband()
	var message := "The warband sweeps %d piece(s) into %s." % [ids.size(), _pool_name()]
	if skipped > 0:
		message += " %d drop(s) lay beyond the battlefield." % skipped
	return _sweep_result(true, ids, skipped, message)

# --- corpses ---------------------------------------------------------------

## Turn a fallen enemy into a container. The kit is read once and held on the
## record: a body that has already given its blade cannot answer for a second one,
## and the scene that spawned the body does not have to keep the ids anywhere.
## Answers 0 for a body that carries nothing, and the same id when the same enemy
## is registered twice.
func register_corpse(enemy) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	_prune_corpses()
	var known := _corpse_id_of_enemy(enemy)
	if known != 0:
		return known
	if not enemy.has_method("gear_items"):
		return 0
	var ids: Array[String] = []
	var gear: Array = enemy.gear_items()
	for entry in gear:
		var item_id := str(entry)
		if not item_id.is_empty():
			ids.append(item_id)
	if ids.is_empty():
		return 0
	var corpse_id := _next_corpse_id
	_next_corpse_id += 1
	_corpses[corpse_id] = {"id": corpse_id, "enemy": enemy, "items": ids}
	corpse_registered.emit(corpse_id)
	return corpse_id

## A member of the party below who dies keeps what he still wore on his own body:
## a container like an enemy's, labelled with his name, and marked as the party's
## remains so the squad's sweep (`corpse_ids(false)`) never strips a fallen
## comrade - a soul has to take it back. Answers 0 for an empty kit, and the same
## id when the same body is registered twice.
func register_remains(body: Node3D, items: Array[String], label: String) -> int:
	if body == null or not is_instance_valid(body) or items.is_empty():
		return 0
	_prune_corpses()
	var known := _corpse_id_of_enemy(body)
	if known != 0:
		return known
	var corpse_id := _next_corpse_id
	_next_corpse_id += 1
	_corpses[corpse_id] = {"id": corpse_id, "enemy": body, "items": items.duplicate(),
		"label": label, "remains": true}
	corpse_registered.emit(corpse_id)
	return corpse_id

## Forget a body: what is still on it is nobody's now. The Hollow calls this for
## the dead the party leaves below when its instance closes.
func forget_corpse(corpse_id: int) -> void:
	if not _corpses.has(corpse_id):
		return
	_corpses.erase(corpse_id)
	corpse_changed.emit(corpse_id, [])

## Whether the body a corpse id names is registered and still holds something.
## False for a stripped body and for one whose enemy has been freed, so a caller
## that offers loot never offers a finished corpse.
func has_corpse(corpse_id: int) -> bool:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return false
	return not (record["items"] as Array).is_empty()

## How many fallen bodies the registry has taken in this battle, whether or not
## somebody has already emptied them. `corpse_ids()` only names the ones still
## holding something, which is what a searcher wants; this is what a test or a
## battle report wants, because the squad strips corpses on its own and a body can
## be emptied before anything else looks at it.
func registered_corpses() -> int:
	_prune_corpses()
	return _corpses.size()


# --- co-op copies -----------------------------------------------------------
#
# A guest's vacuums never register a body of their own: the host owns every kill
# and every booking. These four calls are the host's record arriving over the
# session, so the guest's corpse screen can list a body and then watch pieces
# leave it when somebody else takes them. The id is the host's, which is the one
# every take is named by, so no local id has to be translated.

## Take the host's record for a fallen body: its id, who it was, what it still
## holds, and where it lies. A repeated announcement replaces the record, so a
## guest that joins late and one that saw the death both end up with one row.
func import_corpse(corpse_id: int, body_name: String, label: String,
		items: Array, at: Vector3, remains: bool = false) -> void:
	if corpse_id <= 0:
		return
	var held: Array[String] = []
	for entry in items:
		var item_id := str(entry)
		if not item_id.is_empty() and State.ITEMS.has(item_id):
			held.append(item_id)
	if held.is_empty():
		drop_corpse(corpse_id)
		return
	_corpses[corpse_id] = {"id": corpse_id, "items": held, "label": label,
		"at": at, "name": body_name, "remains": remains, "remote": true}
	_next_corpse_id = maxi(_next_corpse_id, corpse_id + 1)


## The host's answer to a take: this is what the body holds now. An empty list
## is a stripped body, and the row goes.
func set_corpse_items(corpse_id: int, items: Array) -> void:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return
	var held: Array[String] = []
	for entry in items:
		var item_id := str(entry)
		if not item_id.is_empty():
			held.append(item_id)
	if held.is_empty():
		drop_corpse(corpse_id)
		return
	record["items"] = held
	_corpses[corpse_id] = record


## The body is nobody's now: the host has forgotten it, or the last piece left.
func drop_corpse(corpse_id: int) -> void:
	_corpses.erase(corpse_id)


## Whether this body is a fallen comrade rather than a hostile: the squad never
## strips the party's own dead, and a guest's copy has to know which one it has.
func corpse_is_remains(corpse_id: int) -> bool:
	var record := _corpse_record(corpse_id)
	return not record.is_empty() and bool(record.get("remains", false))


## Who this body was, for a take that has to name it back to the host.
func corpse_name(corpse_id: int) -> String:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return ""
	var named := str(record.get("name", ""))
	if not named.is_empty():
		return named
	var enemy = record.get("enemy")
	return str((enemy as Node).name) if is_instance_valid(enemy) else ""


## Every body still worth searching, oldest first. A stripped body stays out of
## this list, so a caller that walks it never re-offers a finished corpse; with
## `include_remains` false so do the party's own dead (`register_remains`), which
## is the list the squad's sweep walks.
func corpse_ids(include_remains: bool = true) -> Array[int]:
	_prune_corpses()
	var out: Array[int] = []
	for corpse_id in _corpses.keys():
		var record: Dictionary = _corpses[corpse_id]
		if (record["items"] as Array).is_empty():
			continue
		if not include_remains and bool(record.get("remains", false)):
			continue
		out.append(int(corpse_id))
	out.sort()
	return out

## What is still on the body, in the order it was carried. Empty answers for a
## stripped body and for one whose enemy has been freed.
func corpse_items(corpse_id: int) -> Array[String]:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return []
	var items: Array[String] = record["items"]
	return items.duplicate()

## What the body is still worth, by the rule the stash sorts with.
func corpse_value(corpse_id: int) -> int:
	return _value_of(corpse_items(corpse_id))

## The nearest body with something left on it inside `reach`, or 0 for none.
func corpse_at(point: Vector3, reach: float) -> int:
	var best := 0
	var best_distance := maxf(reach, 0.0)
	for corpse_id in corpse_ids():
		var distance := point.distance_to(corpse_position(corpse_id))
		if distance <= best_distance:
			best_distance = distance
			best = corpse_id
	return best

## Where the body lies, or `Vector3.ZERO` once it is gone: a freed enemy is not a
## position, and the record dies with it rather than remembering a stale point.
func corpse_position(corpse_id: int) -> Vector3:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return Vector3.ZERO
	# A guest's copy is imported from the host: the body here is the guest's own
	# replica and may be hidden, but where the host says it lies is the truth the
	# loot window opens on.
	if bool(record.get("remote", false)):
		return record.get("at", Vector3.ZERO)
	var enemy = record["enemy"]
	if not (enemy is Node3D):
		return Vector3.ZERO
	return (enemy as Node3D).global_position

## Who the body was, for the corpse screen's title line.
func corpse_label(corpse_id: int) -> String:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return ""
	var label := str(record.get("label", ""))
	if not label.is_empty():
		return label
	var enemy = record.get("enemy")
	if not is_instance_valid(enemy):
		return ""
	if enemy.has_method("get_display_name"):
		var named := str(enemy.get_display_name())
		if not named.is_empty():
			return named
	return str(enemy.name)

## Take one piece off a body. `collector_peer` follows the same rule a hand pickup
## does: 0 means the warband itself took it (an AI claim, a squad's silent sweep)
## and no body is dressed, while a peer standing in a living body gets the piece
## in hand. Either way the piece is a stash row first, and it leaves the body
## strictly after it is booked.
func take_from_corpse(corpse_id: int, item_id: String, collector_peer: int = 1) -> Dictionary:
	var record := _corpse_record(corpse_id)
	if record.is_empty():
		return _refused("There is no body left to search.", item_id)
	var items: Array[String] = record["items"]
	if items.is_empty():
		return _refused("There is nothing left on that body.", item_id)
	var index := items.find(item_id)
	if index < 0:
		return _refused("%s is not on that body." % WarbandPickup.item_name(item_id), item_id)
	var stash := _stash()
	if stash == null:
		return _refused("The shared stash is missing.", item_id)
	_book_piece(stash, item_id, collector_peer)
	items.remove_at(index)
	record["items"] = items
	corpse_changed.emit(corpse_id, items.duplicate())
	_notify_warband()
	return {"ok": true, "item_id": item_id, "remaining": items.size(),
		"message": _dress_message(item_id, collector_peer)}

## Strip a body in one go. Returns what was taken and what it was worth, so a
## panel and a battle report can both use the same answer. Each piece is booked
## before it leaves the body, so a failure part-way cannot lose one. `dress` false
## books every piece into the pool and puts none of them on the taker's body.
func take_all_from_corpse(corpse_id: int, collector_peer: int = 1, dress: bool = true) -> Dictionary:
	var ids: Array[String] = []
	var value := 0
	var stash := _stash()
	if stash == null:
		return {"ok": false, "ids": ids, "count": 0, "value": 0}
	var record := _corpse_record(corpse_id)
	var remaining: Array = []
	if not record.is_empty():
		var items: Array[String] = record["items"]
		for item_id in items.duplicate():
			_book_piece(stash, item_id, collector_peer)
			# The dressing still happens for a peer standing in a body, but a bulk
			# take reports counts rather than one line per piece.
			_dress_message(item_id, collector_peer if dress else 0)
			ids.append(item_id)
			value += StashScript.value_of(item_id)
			items.remove_at(items.find(item_id))
		record["items"] = items
		remaining = items
	if not ids.is_empty():
		corpse_changed.emit(corpse_id, remaining.duplicate())
		_notify_warband()
	return {"ok": not ids.is_empty(), "ids": ids, "count": ids.size(), "value": value}

## The AI's entry point: turn whatever a corpse still holds into stash rows and
## say nothing about it. The warband's contract forbids announcing loot steps, so
## this reports counts only. `collector_peer` 0 is the warband itself, not a body
## the piece could be worn by - the squad's soldiers have no soul in them.
func claim_corpse(corpse_id: int, collector_peer: int = 0) -> Dictionary:
	return take_all_from_corpse(corpse_id, collector_peer)

## What this vacuum has pulled off the ground so far, valued by the same rule the
## stash sorts with, so a battle report and the stash rows always agree.
func battlefield_value() -> int:
	return _value_of(_gathered)

## One line for the battle log and for tests.
func describe() -> String:
	return "drops=%d gathered=%d value=%d corpses=%d" % [
		_live_pickups().size(), _gathered.size(), battlefield_value(),
		corpse_ids().size()]

# --- internals -------------------------------------------------------------

# --- the one booking path --------------------------------------------------

## The one way a piece enters the warband: a real stash row plus a line in the
## ledger the battle report reads. Every caller resolves the stash first, because
## refusing before anything is booked is the only honest answer to a missing one.
## A piece that came out of the Hollow already anointed wakes into its skill as it
## is booked (`Warband.grant_anointing`); answers true when it did.
func _book_piece(stash: WarbandStash, item_id: String, collector_peer: int, anointed: bool = false) -> bool:
	stash.add(item_id, 1)
	var awoke: bool = anointed and _warband != null and is_instance_valid(_warband) \
		and _warband.has_method("grant_anointing") and bool(_warband.grant_anointing(item_id))
	_gathered.append(item_id)
	booked.emit(item_id, collector_peer)
	return awoke

## The line a taker reads, and the one hand-off the warband allows: a piece taken
## by a soul standing in a living body snaps into that body's hands instead of only
## landing in the stash. The piece is a stash row either way, so what the warband
## is worth never disagrees with what it wears.
func _dress_message(item_id: String, collector_peer: int) -> String:
	var message := "%s goes into %s." % [WarbandPickup.item_name(item_id), _pool_name()]
	# Peer 0 is the warband itself - a squad soldier or a sweep - and has no body
	# a piece could be worn by, so the booking stays a plain stash row.
	if collector_peer <= 0:
		return message
	var merc_id := _equip_owner(collector_peer)
	if merc_id <= 0 or _warband == null or not is_instance_valid(_warband):
		return message
	var auto: Dictionary = _warband.auto_equip(merc_id, item_id)
	if bool(auto.get("ok", false)):
		message = "%s goes to %s (%s)." % [WarbandPickup.item_name(item_id),
			_warband.roster.name_of(merc_id),
			Contracts.slot_id_label(str(auto.get("slot", "")))]
	return message

# --- corpse bookkeeping ----------------------------------------------------

## The record for a corpse id, or an empty dictionary once its enemy is gone. The
## record dies with the body, so a caller can never read a stale position.
func _corpse_record(corpse_id: int) -> Dictionary:
	var record: Dictionary = _corpses.get(corpse_id, {})
	if record.is_empty():
		return {}
	if bool(record.get("remote", false)):
		return record
	if not is_instance_valid(record.get("enemy")):
		_corpses.erase(corpse_id)
		return {}
	return record

## Forget every body whose enemy has left the tree. Cheap: a battlefield holds a
## handful of corpses, and this only runs when somebody asks about them. A copy
## imported from the host has no enemy here at all and lives until the host says
## the body is gone.
func _prune_corpses() -> void:
	for corpse_id in _corpses.keys():
		var record: Dictionary = _corpses[corpse_id]
		if bool(record.get("remote", false)) or is_instance_valid(record.get("enemy")):
			continue
		_corpses.erase(corpse_id)

## The id a registered enemy already holds, or 0. Registration is idempotent, so
## a scene that reports the same death twice cannot make a second record.
func _corpse_id_of_enemy(enemy) -> int:
	if not is_instance_valid(enemy):
		return 0
	for corpse_id in _corpses.keys():
		if (_corpses[corpse_id] as Dictionary).get("enemy") == enemy:
			return int(corpse_id)
	return 0

## The stash's own value rule, applied to a list of ids.
func _value_of(ids: Array[String]) -> int:
	var total := 0
	for item_id in ids:
		total += StashScript.value_of(item_id)
	return total

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

## The pool a take lands in: the warband's field stash - the town stash, or the
## delve inventory while a party is below - resolved through the warband (or the
## autoload when this node was never handed one).
func _stash() -> WarbandStash:
	if _warband == null or not is_instance_valid(_warband):
		_warband = get_node_or_null("/root/Warband") if is_inside_tree() else null
	if _warband == null:
		return null
	var stash: Variant = _warband.call("field_stash") if _warband.has_method("field_stash") \
		else _warband.get("stash")
	return stash if stash is WarbandStash else null

## How a message names that pool.
func _pool_name() -> String:
	if _warband != null and is_instance_valid(_warband) and _warband.has_method("field_label"):
		return str(_warband.call("field_label"))
	return "the shared stash"

## The stash is the warband's, so its change signal is the one the HUD listens to.
func _notify_warband() -> void:
	if _warband != null and is_instance_valid(_warband) and _warband.has_signal("changed"):
		_warband.changed.emit()

func _refused(message: String, item_id: String) -> Dictionary:
	return {"ok": false, "message": message, "item_id": item_id}

func _sweep_result(ok: bool, ids: Array[String], skipped: int, message: String) -> Dictionary:
	return {"ok": ok, "message": message, "collected": ids.size(), "item_ids": ids,
		"skipped": skipped}
