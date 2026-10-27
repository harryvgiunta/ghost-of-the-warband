class_name WarbandRoster
extends RefCounted
## The warband: every mercenary the player owns, their identical base stats,
## their health/downed state and the gear each one wears.
##
## A mercenary is a plain dictionary so it survives save/load and the wire
## without a serializer: `id`, `name`, `health`, `max_health`, `state`,
## `equipped`, `deployed`, `downed_seconds`. Every record is created
## at `WarbandContracts.BASE_MAX_HEALTH` with empty hands: the ONLY thing that
## differentiates two mercenaries is the gear in `equipped`.
##
## Brands are item properties, not body properties, so they live in
## `scripts/warband/cruor_manager.gd` keyed by item id.
## This is pure data. It never touches a node, so the possession controller, the
## warband screen, the recruiter and the altar all share one truth.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/player_state.gd")

## Record keys.
const KEY_ID := "id"
const KEY_NAME := "name"
const KEY_HEALTH := "health"
const KEY_MAX_HEALTH := "max_health"
const KEY_STATE := "state"
const KEY_EQUIPPED := "equipped"
const KEY_DEPLOYED := "deployed"
const KEY_DOWNED_SECONDS := "downed_seconds"

var _mercs: Array[Dictionary] = []
var _next_id := 1

static func empty_equipment() -> Dictionary:
	var gear := {}
	for slot in EquipmentRules.SLOTS:
		gear[slot] = ""
	return gear

static func make_record(merc_id: int, merc_name: String,
		max_health: float = Contracts.BASE_MAX_HEALTH) -> Dictionary:
	return {
		KEY_ID: merc_id,
		KEY_NAME: merc_name,
		KEY_HEALTH: max_health,
		KEY_MAX_HEALTH: max_health,
		KEY_STATE: Contracts.HealthState.ALIVE,
		KEY_EQUIPPED: empty_equipment(),
		KEY_DEPLOYED: false,
		KEY_DOWNED_SECONDS: 0.0,
	}

# --- reading ---------------------------------------------------------------

func count() -> int:
	return _mercs.size()

func is_empty() -> bool:
	return _mercs.is_empty()

func ids() -> Array[int]:
	var out: Array[int] = []
	for merc in _mercs:
		out.append(int(merc[KEY_ID]))
	return out

## Live references, in recruitment order. Callers may mutate; they own the data.
func records() -> Array[Dictionary]:
	return _mercs.duplicate()

func has(merc_id: int) -> bool:
	return not find(merc_id).is_empty()

## The stored record itself (empty dictionary when unknown), so callers can
## write one field without a second lookup.
func find(merc_id: int) -> Dictionary:
	for merc in _mercs:
		if int(merc[KEY_ID]) == merc_id:
			return merc
	return {}

func name_of(merc_id: int) -> String:
	return str(find(merc_id).get(KEY_NAME, "Mercenary"))

func state_of(merc_id: int) -> int:
	var record := find(merc_id)
	if record.is_empty():
		return Contracts.HealthState.DEAD
	return int(record.get(KEY_STATE, Contracts.HealthState.ALIVE))

func health_of(merc_id: int) -> float:
	var record := find(merc_id)
	return float(record.get(KEY_HEALTH, 0.0))

func max_health_of(merc_id: int) -> float:
	var record := find(merc_id)
	return float(record.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))

func is_alive(merc_id: int) -> bool:
	return state_of(merc_id) == Contracts.HealthState.ALIVE

func is_downed(merc_id: int) -> bool:
	return state_of(merc_id) == Contracts.HealthState.DOWNED

func is_dead(merc_id: int) -> bool:
	return state_of(merc_id) == Contracts.HealthState.DEAD

## A body can be entered only while ALIVE. Downed bodies are revived first.
func can_possess(merc_id: int) -> bool:
	return is_alive(merc_id)

func alive_ids() -> Array[int]:
	var out: Array[int] = []
	for merc in _mercs:
		if int(merc.get(KEY_STATE, Contracts.HealthState.DEAD)) == Contracts.HealthState.ALIVE:
			out.append(int(merc[KEY_ID]))
	return out

func downed_ids() -> Array[int]:
	var out: Array[int] = []
	for merc in _mercs:
		if int(merc.get(KEY_STATE, Contracts.HealthState.DEAD)) == Contracts.HealthState.DOWNED:
			out.append(int(merc[KEY_ID]))
	return out

func dead_ids() -> Array[int]:
	var out: Array[int] = []
	for merc in _mercs:
		if int(merc.get(KEY_STATE, Contracts.HealthState.DEAD)) == Contracts.HealthState.DEAD:
			out.append(int(merc[KEY_ID]))
	return out

func alive_count() -> int:
	return alive_ids().size()

func deployed_ids() -> Array[int]:
	var out: Array[int] = []
	for merc in _mercs:
		if bool(merc.get(KEY_DEPLOYED, false)):
			out.append(int(merc[KEY_ID]))
	return out

func deployed_count() -> int:
	return deployed_ids().size()

# --- mutation --------------------------------------------------------------

func clear() -> void:
	_mercs.clear()
	_next_id = 1

func create(merc_name: String = "", equipped: Dictionary = {}) -> int:
	var merc_id := _next_id
	_next_id += 1
	if merc_name.strip_edges().is_empty():
		merc_name = "Mercenary %d" % merc_id
	var record := make_record(merc_id, merc_name)
	if not equipped.is_empty():
		for slot in equipped:
			if not str(equipped[slot]).is_empty() and str(slot) in EquipmentRules.SLOTS:
				record[KEY_EQUIPPED][slot] = str(equipped[slot])
	_mercs.append(record)
	return merc_id

## Re-add a saved record, keeping its id and advancing the id counter past it.
func add_record(record: Dictionary) -> int:
	var copy := record.duplicate(true)
	var merc_id := int(copy.get(KEY_ID, 0))
	if merc_id <= 0:
		merc_id = _next_id
		copy[KEY_ID] = merc_id
	if has(merc_id):
		return -1
	copy[KEY_NAME] = str(copy.get(KEY_NAME, "Mercenary"))
	copy[KEY_MAX_HEALTH] = float(copy.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))
	copy[KEY_HEALTH] = clampf(float(copy.get(KEY_HEALTH, copy[KEY_MAX_HEALTH])), 0.0, copy[KEY_MAX_HEALTH])
	copy[KEY_STATE] = int(copy.get(KEY_STATE, Contracts.HealthState.ALIVE))
	copy[KEY_DEPLOYED] = bool(copy.get(KEY_DEPLOYED, false))
	copy[KEY_DOWNED_SECONDS] = float(copy.get(KEY_DOWNED_SECONDS, 0.0))
	var gear := empty_equipment()
	var saved_gear: Variant = copy.get(KEY_EQUIPPED, {})
	if saved_gear is Dictionary:
		for slot in saved_gear:
			if str(slot) in gear:
				gear[slot] = str(saved_gear[slot])
	copy[KEY_EQUIPPED] = gear
	_mercs.append(copy)
	_next_id = maxi(_next_id, merc_id + 1)
	return merc_id

## Remove one mercenary. Returns false when the id is unknown.
func remove(merc_id: int) -> bool:
	for index in _mercs.size():
		if int(_mercs[index][KEY_ID]) == merc_id:
			_mercs.remove_at(index)
			return true
	return false

func rename(merc_id: int, merc_name: String) -> bool:
	var record := find(merc_id)
	if record.is_empty():
		return false
	record[KEY_NAME] = merc_name.strip_edges()
	return true

func set_health(merc_id: int, hp: float) -> void:
	var record := find(merc_id)
	if record.is_empty():
		return
	record[KEY_MAX_HEALTH] = float(record.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))
	record[KEY_HEALTH] = clampf(hp, 0.0, float(record[KEY_MAX_HEALTH]))

func set_state(merc_id: int, state: int) -> void:
	var record := find(merc_id)
	if record.is_empty():
		return
	record[KEY_STATE] = state
	if state != Contracts.HealthState.DOWNED:
		record[KEY_DOWNED_SECONDS] = 0.0
	if state == Contracts.HealthState.DEAD:
		record[KEY_HEALTH] = 0.0
		record[KEY_DEPLOYED] = false

## Apply a hit through the shared overkill contract. Returns the resolver's
## dictionary plus `{"merc_id": id, "state_from": previous_state}`; a body that
## is already downed is finished only by a hit over the 10% threshold.
func apply_damage(merc_id: int, amount: float) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return {"ok": false, "state": Contracts.HealthState.DEAD, "health": 0.0,
			"damage": 0.0, "overkill": 0.0, "downed": false, "died": false,
			"merc_id": merc_id, "state_from": Contracts.HealthState.DEAD}
	var state_from := int(record.get(KEY_STATE, Contracts.HealthState.ALIVE))
	var max_hp := float(record.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))
	if state_from == Contracts.HealthState.DEAD:
		return {"ok": false, "state": state_from, "health": 0.0, "damage": 0.0,
			"overkill": 0.0, "downed": false, "died": false,
			"merc_id": merc_id, "state_from": state_from}
	if state_from == Contracts.HealthState.DOWNED:
		var finished := Contracts.finishes_downed(max_hp, amount)
		if finished:
			record[KEY_STATE] = Contracts.HealthState.DEAD
			record[KEY_HEALTH] = 0.0
			record[KEY_DEPLOYED] = false
		return {"ok": true, "state": int(record[KEY_STATE]), "health": float(record[KEY_HEALTH]),
			"damage": maxf(0.0, amount), "overkill": maxf(0.0, amount), "downed": not finished,
			"died": finished, "merc_id": merc_id, "state_from": state_from}
	var result := Contracts.resolve_damage(float(record[KEY_HEALTH]), max_hp, amount)
	if not bool(result["ok"]):
		result["merc_id"] = merc_id
		result["state_from"] = state_from
		return result
	record[KEY_HEALTH] = float(result["health"])
	record[KEY_STATE] = int(result["state"])
	if bool(result["died"]):
		record[KEY_DEPLOYED] = false
	result["merc_id"] = merc_id
	result["state_from"] = state_from
	return result

func heal(merc_id: int, amount: float) -> float:
	var record := find(merc_id)
	if record.is_empty() or int(record.get(KEY_STATE, Contracts.HealthState.DEAD)) != Contracts.HealthState.ALIVE:
		return 0.0
	var before := float(record[KEY_HEALTH])
	var after := minf(float(record[KEY_MAX_HEALTH]), before + maxf(0.0, amount))
	record[KEY_HEALTH] = after
	return after - before

## Stand a downed mercenary back up at `fraction` of max health. False when the
## body is dead (or already standing).
func revive(merc_id: int, fraction: float = Contracts.REVIVE_HEALTH_FRACTION) -> bool:
	var record := find(merc_id)
	if record.is_empty():
		return false
	var state := int(record.get(KEY_STATE, Contracts.HealthState.DEAD))
	if state == Contracts.HealthState.DEAD:
		return false
	if state == Contracts.HealthState.ALIVE:
		return false
	var max_hp := float(record.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))
	record[KEY_HEALTH] = clampf(max_hp * fraction, 1.0, max_hp)
	record[KEY_STATE] = Contracts.HealthState.ALIVE
	record[KEY_DOWNED_SECONDS] = 0.0
	return true

## Advance a downed body's bleed clock. Returns true when it died this call.
func tick_downed(merc_id: int, delta: float) -> bool:
	var record := find(merc_id)
	if record.is_empty() or int(record.get(KEY_STATE, Contracts.HealthState.DEAD)) != Contracts.HealthState.DOWNED:
		return false
	record[KEY_DOWNED_SECONDS] = float(record.get(KEY_DOWNED_SECONDS, 0.0)) + maxf(0.0, delta)
	if float(record[KEY_DOWNED_SECONDS]) < Contracts.DOWNED_BLEED_SECONDS:
		return false
	record[KEY_STATE] = Contracts.HealthState.DEAD
	record[KEY_HEALTH] = 0.0
	record[KEY_DEPLOYED] = false
	return true

## Bring every mercenary back at full health for the next battle.
func restore_all() -> void:
	for merc in _mercs:
		if int(merc.get(KEY_STATE, Contracts.HealthState.DEAD)) == Contracts.HealthState.DEAD:
			continue
		merc[KEY_STATE] = Contracts.HealthState.ALIVE
		merc[KEY_HEALTH] = float(merc.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))
		merc[KEY_DOWNED_SECONDS] = 0.0

# --- gear ------------------------------------------------------------------

func equipped_of(merc_id: int) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return empty_equipment()
	var gear: Variant = record.get(KEY_EQUIPPED, {})
	return gear.duplicate() if gear is Dictionary else empty_equipment()

## Equip a catalog item into one of the ten slots. Legality is `EquipmentRules`',
## plus the two-handed rule (a 2H/bow/staff clears the off hand). Returns
## `{ok, message, displaced}` where `displaced` maps slot -> item id that came
## off the body into the shared stash.
func equip(merc_id: int, slot_id: String, item_id: String) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return {"ok": false, "message": "No such mercenary.", "displaced": {}}
	if not slot_id in EquipmentRules.SLOTS:
		return {"ok": false, "message": "That is not a worn slot.", "displaced": {}}
	if item_id.is_empty():
		return {"ok": false, "message": "Choose a piece of gear.", "displaced": {}}
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return {"ok": false, "message": "That gear does not exist.", "displaced": {}}
	if not EquipmentRules.allowed(item, slot_id):
		return {"ok": false, "message": "%s cannot go in the %s slot." % [
			str(item.get("name", "Gear")), EquipmentRules.slot_label(slot_id)], "displaced": {}}
	var gear: Dictionary = record[KEY_EQUIPPED]
	var displaced := {}
	var previous := str(gear.get(slot_id, ""))
	if previous == item_id:
		return {"ok": true, "message": "%s is already worn." % str(item.get("name", "Gear")),
			"displaced": {}}
	if not previous.is_empty():
		displaced[slot_id] = previous
	# Two-handed grips clear the off hand; an off-hand piece clears a 2H main.
	if slot_id == "main" and Contracts.two_handed_item(item):
		var off_id := str(gear.get("off", ""))
		if not off_id.is_empty():
			displaced["off"] = off_id
			gear["off"] = ""
	elif slot_id == "off":
		var main_item: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
		if not main_item.is_empty() and Contracts.two_handed_item(main_item):
			displaced["main"] = str(gear.get("main", ""))
			gear["main"] = ""
	gear[slot_id] = item_id
	return {"ok": true, "message": "Equipped %s." % str(item.get("name", "Gear")),
		"displaced": displaced}

## Clear one slot. Returns the item id that came off (empty when already bare).
func unequip(merc_id: int, slot_id: String) -> String:
	var record := find(merc_id)
	if record.is_empty() or not slot_id in EquipmentRules.SLOTS:
		return ""
	var gear: Dictionary = record[KEY_EQUIPPED]
	var item_id := str(gear.get(slot_id, ""))
	gear[slot_id] = ""
	return item_id

# --- deployment ------------------------------------------------------------

## Mark a body for the next battle. Refuses when the deployment cap is reached
## and the body is not already deployed. Returns `{ok, message}`.
func set_deployed(merc_id: int, on: bool, cap: int = Contracts.MAX_DEPLOYMENT_CAP) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return {"ok": false, "message": "No such mercenary."}
	if not on:
		record[KEY_DEPLOYED] = false
		return {"ok": true, "message": "%s stands down." % name_of(merc_id)}
	if int(record.get(KEY_STATE, Contracts.HealthState.DEAD)) == Contracts.HealthState.DEAD:
		return {"ok": false, "message": "%s is dead." % name_of(merc_id)}
	if bool(record.get(KEY_DEPLOYED, false)):
		return {"ok": true, "message": "%s is already deployed." % name_of(merc_id)}
	if deployed_count() >= maxi(0, cap):
		return {"ok": false, "message": "The warband can field at most %d." % cap}
	record[KEY_DEPLOYED] = true
	return {"ok": true, "message": "%s joins the battle." % name_of(merc_id)}

## Deploy exactly these ids, in order, up to the cap. Returns the ids fielded.
func deploy(merc_ids: Array, cap: int = Contracts.MAX_DEPLOYMENT_CAP) -> Array[int]:
	for merc in _mercs:
		merc[KEY_DEPLOYED] = false
	var out: Array[int] = []
	for id in merc_ids:
		var merc_id := int(id)
		if out.size() >= maxi(0, cap):
			break
		if is_dead(merc_id):
			continue
		var record := find(merc_id)
		if record.is_empty():
			continue
		record[KEY_DEPLOYED] = true
		out.append(merc_id)
	return out

func clear_deployment() -> void:
	for merc in _mercs:
		merc[KEY_DEPLOYED] = false

# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {"version": 1, "next_id": _next_id,
		"mercenaries": _mercs.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	_mercs.clear()
	_next_id = 1
	var saved: Variant = data.get("mercenaries", [])
	if saved is Array:
		for entry in saved:
			if entry is Dictionary:
				add_record(entry)
	_next_id = maxi(_next_id, int(data.get("next_id", _next_id)))
