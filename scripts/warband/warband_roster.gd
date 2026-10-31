class_name WarbandRoster
extends RefCounted
## The warband: every mercenary the player owns, their identical base stats,
## their health/downed state and the gear each one wears.
##
## A mercenary is a plain dictionary so it survives save/load and the wire
## without a serializer: `id`, `name`, `health`, `max_health`, `state`,
## `equipped`, `downed_seconds`. Every record is created
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

## A record that has just become DEAD, whoever put it down: a lethal blow, a
## finisher on a downed body, the bleed clock, or a scene mirroring a corpse.
## `Warband` listens so the dead leave the books on the same frame they die.
signal died(merc_id: int)

## Record keys.
const KEY_ID := "id"
const KEY_NAME := "name"
const KEY_HEALTH := "health"
const KEY_MAX_HEALTH := "max_health"
const KEY_STATE := "state"
const KEY_EQUIPPED := "equipped"
const KEY_DOWNED_SECONDS := "downed_seconds"
## The two weapon sets, and which one the hands carry. A mercenary's armour and
## trinkets live on `equipped`; only the two hand slots travel through these.
const KEY_WEAPON_SETS := "weapon_sets"
const KEY_ACTIVE_SET := "active_set"
## The same two-slot swap the frontier's `TAB` runs: set 1 and set 2, each a
## `{main, off}` pair, one of them in the hands.
const WEAPON_SET_COUNT := 2
const HAND_SLOTS := ["main", "off"]

var _mercs: Array[Dictionary] = []
var _next_id := 1

static func empty_equipment() -> Dictionary:
	var gear := {}
	for slot in EquipmentRules.SLOTS:
		gear[slot] = ""
	return gear

static func empty_pair() -> Dictionary:
	return {"main": "", "off": ""}

static func make_record(merc_id: int, merc_name: String,
		max_health: float = Contracts.BASE_MAX_HEALTH) -> Dictionary:
	return {
		KEY_ID: merc_id,
		KEY_NAME: merc_name,
		KEY_HEALTH: max_health,
		KEY_MAX_HEALTH: max_health,
		KEY_STATE: Contracts.HealthState.ALIVE,
		KEY_EQUIPPED: empty_equipment(),
		KEY_WEAPON_SETS: [empty_pair(), empty_pair()],
		KEY_ACTIVE_SET: 0,
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
	# A body raised with a weapon in its hands carries it in Set 1; Set 2 waits
	# empty until the player puts something in it.
	_store_hands(record)
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
	copy[KEY_DOWNED_SECONDS] = float(copy.get(KEY_DOWNED_SECONDS, 0.0))
	var gear := empty_equipment()
	var saved_gear: Variant = copy.get(KEY_EQUIPPED, {})
	if saved_gear is Dictionary:
		for slot in saved_gear:
			if str(slot) in gear:
				gear[slot] = State.migrate_item_id(str(saved_gear[slot]))
	copy[KEY_EQUIPPED] = gear
	# A save written before the two sets existed has one pair of hands and no
	# second set: that pair becomes Set 1 and Set 2 starts empty, exactly as a
	# freshly raised mercenary's does. Ids migrate inside each pair.
	var sets: Array = []
	var saved_sets: Variant = copy.get(KEY_WEAPON_SETS, [])
	if saved_sets is Array:
		for entry in saved_sets:
			if entry is Dictionary and sets.size() < WEAPON_SET_COUNT:
				sets.append(legal_pair({"main": State.migrate_item_id(str(entry.get("main", ""))),
					"off": State.migrate_item_id(str(entry.get("off", "")))}))
	var complete := sets.size() >= WEAPON_SET_COUNT
	while sets.size() < WEAPON_SET_COUNT:
		sets.append(empty_pair())
	if not complete:
		# No saved sets: the hands in `equipped` are what Set 1 holds.
		sets[0] = {"main": str(gear.get("main", "")), "off": str(gear.get("off", ""))}
		copy[KEY_ACTIVE_SET] = 0
	copy[KEY_WEAPON_SETS] = sets
	copy[KEY_ACTIVE_SET] = clampi(int(copy.get(KEY_ACTIVE_SET, 0)), 0, WEAPON_SET_COUNT - 1)
	_sync_hands(copy)
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
	var was_dead := int(record.get(KEY_STATE, Contracts.HealthState.ALIVE)) \
		== Contracts.HealthState.DEAD
	record[KEY_STATE] = state
	if state != Contracts.HealthState.DOWNED:
		record[KEY_DOWNED_SECONDS] = 0.0
	if state == Contracts.HealthState.DEAD:
		record[KEY_HEALTH] = 0.0
	if state == Contracts.HealthState.DEAD and not was_dead:
		died.emit(merc_id)

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
		var answer := {"ok": true, "state": int(record[KEY_STATE]),
			"health": float(record[KEY_HEALTH]),
			"damage": maxf(0.0, amount), "overkill": maxf(0.0, amount), "downed": not finished,
			"died": finished, "merc_id": merc_id, "state_from": state_from}
		if finished:
			died.emit(merc_id)
		return answer
	var result := Contracts.resolve_damage(float(record[KEY_HEALTH]), max_hp, amount)
	if not bool(result["ok"]):
		result["merc_id"] = merc_id
		result["state_from"] = state_from
		return result
	record[KEY_HEALTH] = float(result["health"])
	record[KEY_STATE] = int(result["state"])
	result["merc_id"] = merc_id
	result["state_from"] = state_from
	if bool(result["died"]):
		died.emit(merc_id)
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
	died.emit(merc_id)
	return true

## Every dead record leaves the books, and the caller is told what each one was
## still wearing so the gear can go back to the shared stash instead of dying
## with the body. Returns `[{id, name, health, max_health, items}]`; empty when
## nobody had died. The roster stays pure data - it removes, it does not book.
func take_dead() -> Array[Dictionary]:
	var fallen: Array[Dictionary] = []
	for merc_id in dead_ids():
		var record := find(merc_id)
		var items: Array[String] = []
		for entry in worn_entries(merc_id):
			items.append(str(entry.get("item", "")))
		fallen.append({
			"id": merc_id,
			"name": str(record.get(KEY_NAME, "Mercenary")),
			"health": float(record.get(KEY_HEALTH, 0.0)),
			"max_health": float(record.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH)),
			"items": items,
		})
		remove(merc_id)
	return fallen

## Bring every mercenary back at full health for the next battle.
func restore_all() -> void:
	for merc in _mercs:
		if int(merc.get(KEY_STATE, Contracts.HealthState.DEAD)) == Contracts.HealthState.DEAD:
			continue
		merc[KEY_STATE] = Contracts.HealthState.ALIVE
		merc[KEY_HEALTH] = float(merc.get(KEY_MAX_HEALTH, Contracts.BASE_MAX_HEALTH))
		merc[KEY_DOWNED_SECONDS] = 0.0

# --- gear ------------------------------------------------------------------

## The ten slots of a mercenary's kit. The two hand slots are the pair the body
## is actually holding - the active weapon set - so every reader of `main`/`off`
## (the rig, the drop, the paperdoll, the squad's own hands) sees the set the
## player is wearing without knowing sets exist.
func equipped_of(merc_id: int) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return empty_equipment()
	var gear: Dictionary = _sync_hands(record)
	return gear.duplicate()

## The pair stored in one of the two weapon slots. Out-of-range asks answer with
## an empty pair instead of failing, so a panel can draw both.
func weapon_set_pair(merc_id: int, index: int) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return empty_pair()
	return hand_pair(record, index)

## The set the hands are carrying. `TAB` always leaves this slot and reaches the
## other one, so the key alternates instead of guessing from the hands.
func active_weapon_set(merc_id: int) -> int:
	var record := find(merc_id)
	if record.is_empty():
		return 0
	return int(record.get(KEY_ACTIVE_SET, 0))

func weapon_set_label(merc_id: int, index: int) -> String:
	var pair := weapon_set_pair(merc_id, index)
	return hand_pair_label(str(pair.get("main", "")), str(pair.get("off", "")))

## Swap the hands for the other weapon set, exactly as the frontier's `TAB` does:
## the set being left keeps what the hands were carrying and the other set's pair
## is taken up. Nothing is created or destroyed, because both sets are the
## mercenary's own gear.
func swap_weapon_set(merc_id: int) -> Dictionary:
	var record := find(merc_id)
	if record.is_empty():
		return {"ok": false, "message": "No such mercenary.", "set": 0}
	var sets := _hand_sets(record)
	var active := int(record.get(KEY_ACTIVE_SET, 0))
	var target := (active + 1) % WEAPON_SET_COUNT
	if not _pair_bound(sets[active]) and not _pair_bound(sets[target]):
		return {"ok": false, "message": "Both weapon sets are empty. Put a weapon in a hand first.",
			"set": active}
	_store_hands(record)
	record[KEY_ACTIVE_SET] = target
	_sync_hands(record)
	return {"ok": true, "set": target,
		"message": "Set %d ready: %s." % [target + 1, hand_pair_label(
			str((sets[target] as Dictionary).get("main", "")),
			str((sets[target] as Dictionary).get("off", "")))]}

## Every piece a mercenary is actually wearing, as `{slot, item, set}` records.
## Armour and trinkets answer `set` -1; both weapon sets are listed, because the
## collective stash is one pool and a hand-off has to find a piece waiting in the
## set the hands are not carrying.
func worn_entries(merc_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var record := find(merc_id)
	if record.is_empty():
		return out
	var sets := _hand_sets(record)
	var gear: Variant = record.get(KEY_EQUIPPED, {})
	if gear is Dictionary:
		for slot in EquipmentRules.SLOTS:
			if str(slot) in HAND_SLOTS:
				continue
			var item_id := str((gear as Dictionary).get(slot, ""))
			if not item_id.is_empty():
				out.append({"slot": str(slot), "item": item_id, "set": -1})
	for index in sets.size():
		var pair: Dictionary = sets[index] if sets[index] is Dictionary else empty_pair()
		for slot in HAND_SLOTS:
			var item_id := str(pair.get(slot, ""))
			if not item_id.is_empty():
				out.append({"slot": slot, "item": item_id, "set": index})
	return out

## Take one worn piece off. `set_index` -1 is a body slot, otherwise the weapon
## set the hand belongs to. Returns the item id that came off (empty when bare).
func take_worn(merc_id: int, slot_id: String, set_index: int = -1) -> String:
	var record := find(merc_id)
	if record.is_empty():
		return ""
	var sets := _hand_sets(record)
	var item_id := ""
	if set_index >= 0 and set_index < sets.size():
		if not slot_id in HAND_SLOTS:
			return ""
		var pair: Dictionary = sets[set_index] if sets[set_index] is Dictionary else empty_pair()
		item_id = str(pair.get(slot_id, ""))
		pair[slot_id] = ""
		sets[set_index] = pair
		_sync_hands(record)
		return item_id
	var gear: Dictionary = _sync_hands(record)
	item_id = str(gear.get(slot_id, ""))
	gear[slot_id] = ""
	if slot_id in HAND_SLOTS:
		_store_hands(record)
	return item_id

## A pair read off a save obeys the same rules a live equip does: a piece the
## catalog no longer knows, one the slot cannot take, is dropped, and a two-hander
## keeps no off hand.
static func legal_pair(source: Dictionary) -> Dictionary:
	var main_id := str(source.get("main", ""))
	var off_id := str(source.get("off", ""))
	if main_id.is_empty() or not EquipmentRules.allowed(State.ITEMS.get(main_id, {}), "main"):
		main_id = ""
	if off_id.is_empty() or not EquipmentRules.allowed(State.ITEMS.get(off_id, {}), "off"):
		off_id = ""
	if Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
		off_id = ""
	return {"main": main_id, "off": off_id}

## The pair stored in one slot of a record's sets. Reads never build anything, so
## a caller can ask a half-formed record a question safely.
static func hand_pair(record: Dictionary, index: int) -> Dictionary:
	var sets: Variant = record.get(KEY_WEAPON_SETS, [])
	var source: Dictionary = {}
	if sets is Array and index >= 0 and index < (sets as Array).size() \
			and (sets as Array)[index] is Dictionary:
		source = (sets as Array)[index]
	return {"main": str(source.get("main", "")), "off": str(source.get("off", ""))}

## "Shortbow + Buckler", or "Unarmed" for a bare pair.
static func hand_pair_label(main_id: String, off_id: String) -> String:
	var parts := PackedStringArray()
	if not main_id.is_empty():
		parts.append(str(State.ITEMS.get(main_id, {}).get("name", main_id)))
	if not off_id.is_empty():
		parts.append(str(State.ITEMS.get(off_id, {}).get("name", off_id)))
	return " + ".join(parts) if not parts.is_empty() else "Unarmed"

static func _pair_bound(pair: Dictionary) -> bool:
	return not str(pair.get("main", "")).is_empty() \
		or not str(pair.get("off", "")).is_empty()

## The record's two weapon sets, built in place for one that predates them: the
## pair the hands already carry becomes Set 1 and Set 2 starts empty.
func _hand_sets(record: Dictionary) -> Array:
	var existing: Variant = record.get(KEY_WEAPON_SETS, null)
	if existing is Array and (existing as Array).size() >= WEAPON_SET_COUNT \
			and (existing as Array)[0] is Dictionary and (existing as Array)[1] is Dictionary:
		return existing
	var gear: Variant = record.get(KEY_EQUIPPED, {})
	var hands := empty_pair()
	if gear is Dictionary:
		hands["main"] = str((gear as Dictionary).get("main", ""))
		hands["off"] = str((gear as Dictionary).get("off", ""))
	var built: Array = [hands, empty_pair()]
	record[KEY_WEAPON_SETS] = built
	record[KEY_ACTIVE_SET] = 0
	_sync_hands(record)
	return built

## The hands are the active set: `equipped`'s two hand slots mirror the pair the
## body is holding, so every existing reader of `main`/`off` keeps its meaning
## and only one place has to know which set is up. Returns the gear dictionary.
func _sync_hands(record: Dictionary) -> Dictionary:
	var gear: Variant = record.get(KEY_EQUIPPED, null)
	if not gear is Dictionary:
		gear = empty_equipment()
		record[KEY_EQUIPPED] = gear
	var pair := hand_pair(record, int(record.get(KEY_ACTIVE_SET, 0)))
	(gear as Dictionary)["main"] = str(pair.get("main", ""))
	(gear as Dictionary)["off"] = str(pair.get("off", ""))
	return gear

## The other direction: the hands on `equipped` are stored back into the active
## set. Every equip, unequip and drop writes through here, so a weapon moved by
## hand lands in the set the player is wearing and the other set keeps its own.
func _store_hands(record: Dictionary) -> void:
	var gear: Variant = record.get(KEY_EQUIPPED, {})
	if not gear is Dictionary:
		return
	var sets := _hand_sets(record)
	var active := clampi(int(record.get(KEY_ACTIVE_SET, 0)), 0, sets.size() - 1)
	sets[active] = {"main": str((gear as Dictionary).get("main", "")),
		"off": str((gear as Dictionary).get("off", ""))}

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
	# The hands are the active set: reading through `_sync_hands` means an equip
	# sees exactly the pair the body is holding, whatever moved it last.
	var gear: Dictionary = _sync_hands(record)
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
	if str(slot_id) in HAND_SLOTS:
		_store_hands(record)
	return {"ok": true, "message": "Equipped %s." % str(item.get("name", "Gear")),
		"displaced": displaced}

## Clear one slot. Returns the item id that came off (empty when already bare).
func unequip(merc_id: int, slot_id: String) -> String:
	var record := find(merc_id)
	if record.is_empty() or not slot_id in EquipmentRules.SLOTS:
		return ""
	var gear: Dictionary = _sync_hands(record)
	var item_id := str(gear.get(slot_id, ""))
	gear[slot_id] = ""
	if str(slot_id) in HAND_SLOTS:
		_store_hands(record)
	return item_id

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
