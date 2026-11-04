class_name WarbandStash
extends RefCounted
## The Infinite Shared Stash: one pool of every owned item, value-sorted with
## the most valuable first, and equipped pieces folded into the same list with an
## "Equipped" tag naming the mercenary wearing them.
##
## "Unified collective" is the whole point: a mercenary's sword is not a
## separate container, it is a row in this list that happens to be worn. The
## pooled counts only ever describe items nobody is wearing, so
## `pooled + worn == total owned` for every item id.
##
## Pure data; no node, no save. `Warband` persists it.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const State = preload("res://scripts/player_state.gd")
const CruorCatalog = preload("res://scripts/warband/cruor_catalog.gd")

## item_id -> the serials of the copies nobody is wearing, ascending.
##
## A copy is an *instance*: every piece the warband ever owned has its own serial,
## minted once and never reused, and that serial is what the altar's ledger keys
## an annointment on (`town_stash`'s ordinal). Two greatswords off a keeper's
## shelf are therefore two different weapons: one can be a relic and the other
## plain steel, and buying the second cannot hand the first's marks over to it.
var _pooled: Dictionary = {}
## The next serial to mint, per item id. Serials run from zero for each kind, so
## the first copy of an item keeps the `id#0` key older saves and every card
## already name, and two kinds can both be copy zero.
var _next_serial: Dictionary = {}

func clear() -> void:
	_pooled.clear()
	_next_serial.clear()

# --- pooled storage --------------------------------------------------------

## Put copies into the pool. `serial` carries an existing identity back in (a
## piece that came off a body), so a relic stays the same weapon when it is taken
## off and put down again; -1 mints new ones. Returns the serial added.
func add(item_id: String, count: int = 1, serial: int = -1) -> int:
	item_id = State.migrate_item_id(item_id)
	if item_id.is_empty() or count <= 0:
		return 0
	var list: Array = _pooled.get(item_id, [])
	var first := -1
	for index in count:
		var minted := serial if index == 0 and serial >= 0 else _mint_serial(item_id)
		if index == 0:
			first = minted
		list.append(minted)
	list.sort()
	_pooled[item_id] = list
	return first

## A serial for a copy that is not (and never was) in the pool: a piece that was
## put on a body before the warband had a shelf for it, or a slot claiming a copy
## another slot already holds. It still gets an identity of its own.
func mint_serial(item_id: String) -> int:
	return _mint_serial(State.migrate_item_id(item_id))

func _mint_serial(item_id: String) -> int:
	var serial := int(_next_serial.get(item_id, 0))
	_next_serial[item_id] = serial + 1
	return serial

## Take copies out of the pool. `serial` names the exact copy to take (that is how
## a body claims the weapon it means); -1 drops the lowest serials. False when the
## pool does not hold what was asked for.
func remove(item_id: String, count: int = 1, serial: int = -1) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	var list: Array = _pooled.get(item_id, [])
	if list.size() < count:
		return false
	if serial >= 0:
		if not list.has(serial):
			return false
		list.erase(serial)
	else:
		list = list.slice(count)
	if list.is_empty():
		_pooled.erase(item_id)
	else:
		_pooled[item_id] = list
	return true

## The serials of the copies nobody is wearing, lowest first.
func serials_of(item_id: String) -> Array[int]:
	var out: Array[int] = []
	for serial in _pooled.get(item_id, []):
		out.append(int(serial))
	return out

func has_serial(item_id: String, serial: int) -> bool:
	return (_pooled.get(item_id, []) as Array).has(serial)

func pooled_count(item_id: String) -> int:
	return (_pooled.get(item_id, []) as Array).size()

func pooled_total() -> int:
	var total := 0
	for item_id in _pooled:
		total += (_pooled[item_id] as Array).size()
	return total

func pooled_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in _pooled:
		out.append(str(item_id))
	out.sort()
	return out

## item_id -> copies, for persistence and tests.
func pooled_map() -> Dictionary:
	var out := {}
	for item_id in _pooled:
		out[str(item_id)] = (_pooled[item_id] as Array).size()
	return out

# --- value -----------------------------------------------------------------

## What one copy is worth for sorting: its keeper price plus the ritual value of
## any brand burned into it. A branded relic therefore floats to the top.
static func value_of(item_id: String, brand: Dictionary = {}) -> int:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var value := int(item.get("price", 0))
	if not brand.is_empty():
		var tier := int(brand.get("tier", -1))
		value += int(round(float(CruorCatalog.tier_value(tier)) * 0.5))
	return value

# --- the collective list ---------------------------------------------------

## One row per owned item id, sorted by value (highest first), then name.
## Row: `{item_id, name, category, value, pooled, worn, total, tags, branded}`.
## `worn` is `[{merc_id, merc_name, slot}]`; `tags` is the display list.
func rows(roster, brands: Dictionary = {}) -> Array[Dictionary]:
	var by_item: Dictionary = {}   # item_id -> {pooled:int, worn:Array}
	for item_id in _pooled:
		by_item[str(item_id)] = {"pooled": (_pooled[item_id] as Array).size(),
			"worn": []}
	if roster != null:
		# Both weapon sets count as worn: a piece waiting in the set the hands are
		# not carrying is still on that mercenary, and a stash row that forgot it
		# would offer the warband a copy it does not own.
		for merc in roster.records():
			var merc_id := int(merc.get("id", 0))
			for wear in roster.worn_entries(merc_id):
				var worn_id := str(wear.get("item", ""))
				if worn_id.is_empty():
					continue
				var entry: Variant = by_item.get(worn_id)
				if not entry is Dictionary:
					entry = {"pooled": 0, "worn": []}
					by_item[worn_id] = entry
				(entry["worn"] as Array).append({"merc_id": merc_id,
					"merc_name": str(merc.get("name", "Mercenary")),
					"slot": str(wear.get("slot", "")),
					"set": int(wear.get("set", -1))})
	var rows: Array[Dictionary] = []
	for item_id in by_item:
		var entry: Dictionary = by_item[item_id]
		var worn: Array = entry["worn"]
		var pooled := int(entry["pooled"])
		var item: Dictionary = State.ITEMS.get(item_id, {})
		var brand: Variant = brands.get(item_id, {})
		var brand_payload: Dictionary = brand if brand is Dictionary else {}
		var tags: Array[String] = []
		for wear in worn:
			tags.append("%s %s" % [str(wear.get("merc_name", "Mercenary")),
				Contracts.slot_id_label(str(wear.get("slot", "")))])
		rows.append({
			"item_id": item_id,
			"name": str(item.get("name", item_id)),
			"category": str(item.get("category", "")),
			"value": value_of(item_id, brand_payload),
			"pooled": pooled,
			"worn": worn,
			"total": pooled + worn.size(),
			"tags": tags,
			"branded": not brand_payload.is_empty(),
		})
	rows.sort_custom(_sort_rows)
	return rows

static func _sort_rows(a: Dictionary, b: Dictionary) -> bool:
	if int(a["value"]) != int(b["value"]):
		return int(a["value"]) > int(b["value"])
	var a_name := str(a["name"]).to_lower()
	var b_name := str(b["name"]).to_lower()
	if a_name != b_name:
		return a_name < b_name
	return str(a["item_id"]) < str(b["item_id"])

## Every id a mercenary could be equipped with, pooled or already worn: used by
## the paperdoll's gear picker.
func available_ids(roster) -> Array[String]:
	var seen: Dictionary = {}
	for item_id in _pooled:
		seen[str(item_id)] = true
	if roster != null:
		for merc in roster.records():
			for wear in roster.worn_entries(int(merc.get("id", 0))):
				var worn_id := str(wear.get("item", ""))
				if not worn_id.is_empty():
					seen[worn_id] = true
	var out: Array[String] = []
	for item_id in seen:
		out.append(str(item_id))
	out.sort()
	return out

# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	var pooled := {}
	for item_id in _pooled:
		pooled[str(item_id)] = (_pooled[item_id] as Array).duplicate()
	return {"pooled": pooled, "next_serial": _next_serial.duplicate()}

func from_dict(data: Dictionary) -> void:
	_pooled.clear()
	_next_serial.clear()
	var saved_next: Variant = data.get("next_serial", {})
	if saved_next is Dictionary:
		for item_id in saved_next:
			_next_serial[str(item_id)] = int(saved_next[item_id])
	var saved: Variant = data.get("pooled", {})
	if not saved is Dictionary:
		return
	for item_id in saved:
		var restored := State.migrate_item_id(str(item_id))
		if restored.is_empty():
			continue
		var entry: Variant = saved[item_id]
		var list: Array = []
		if entry is Array:
			# A save from v14 on: the copies' own serials.
			for serial in entry:
				list.append(int(serial))
		else:
			# A count from before copies had serials: mint them now, in order, so
			# the ledger's `id#N` keys and the pool's own serials cannot collide.
			var count := int(entry)
			for index in maxi(0, count):
				list.append(_mint_serial(restored))
		if list.is_empty():
			continue
		list.sort()
		for serial in list:
			_next_serial[restored] = maxi(int(_next_serial.get(restored, 0)),
				int(serial) + 1)
		_pooled[restored] = list
