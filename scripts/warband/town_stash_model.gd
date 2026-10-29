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

## item_id -> copies nobody is wearing.
var _pooled: Dictionary = {}

func clear() -> void:
	_pooled.clear()

# --- pooled storage --------------------------------------------------------

func add(item_id: String, count: int = 1) -> void:
	item_id = State.migrate_item_id(item_id)
	if item_id.is_empty() or count <= 0:
		return
	_pooled[item_id] = int(_pooled.get(item_id, 0)) + count

## Take copies out of the pool. False when the pool does not hold that many.
func remove(item_id: String, count: int = 1) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	var have := int(_pooled.get(item_id, 0))
	if have < count:
		return false
	var left := have - count
	if left <= 0:
		_pooled.erase(item_id)
	else:
		_pooled[item_id] = left
	return true

func pooled_count(item_id: String) -> int:
	return int(_pooled.get(item_id, 0))

func pooled_total() -> int:
	var total := 0
	for item_id in _pooled:
		total += int(_pooled[item_id])
	return total

func pooled_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in _pooled:
		out.append(str(item_id))
	out.sort()
	return out

## item_id -> copies, for persistence and tests.
func pooled_map() -> Dictionary:
	return _pooled.duplicate()

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
		by_item[str(item_id)] = {"pooled": int(_pooled[item_id]), "worn": []}
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
	return {"pooled": _pooled.duplicate()}

func from_dict(data: Dictionary) -> void:
	_pooled.clear()
	var saved: Variant = data.get("pooled", {})
	if saved is Dictionary:
		for item_id in saved:
			var count := int(saved[item_id])
			var restored := State.migrate_item_id(str(item_id))
			if count > 0 and not restored.is_empty():
				_pooled[restored] = count
