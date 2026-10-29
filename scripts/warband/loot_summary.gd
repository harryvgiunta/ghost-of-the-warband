class_name LootSummary
extends RefCounted
## One line saying what a loot batch was worth.
##
## A body that strips a corpse gets a single line, not a feed: the warband's
## contract forbids announcing loot steps, so the only thing ever said about a
## take is the total, once the hands are full. This is the one place that wording
## lives - the click's summary, a panel's strip and a test all read it - so a
## second phrasing cannot grow beside it.
##
## Counts collapse (`Wolf Pelt x2`, never the same name twice), the name list is
## capped so the line stays one line, and the value is the keeper price the stash
## sorts with. There is no second valuation here.

const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const State = preload("res://scripts/player_state.gd")
const PickupScript = preload("res://scripts/warband/warband_pickup.gd")

## How many distinct pieces the line names before it stops naming them.
const MAX_NAMES := 4
## The gap the line is written with, so a summary reads as three facts:
## what came up, what it was, and what it is worth.
const SEP := "  ·  "

## Catalog position per id, built once from `PlayerState.ITEMS`, whose own order
## is the order the catalogue and every panel read in.
static var _rank: Dictionary = {}


## The batch as numbers: how many pieces, what each id is worth, and the names in
## catalog order. An id the catalog has never heard of is still counted and named
## (by its raw id), because a total that quietly drops a piece is a lie.
static func of(ids: Array) -> Dictionary:
	var counts: Dictionary = {}
	var value := 0
	var count := 0
	for entry in ids:
		var item_id := str(entry)
		if item_id.is_empty():
			continue
		counts[item_id] = int(counts.get(item_id, 0)) + 1
		value += StashScript.value_of(item_id)
		count += 1
	var names: Array[String] = []
	for item_id in ordered_ids(counts):
		names.append(PickupScript.item_name(item_id))
	return {"count": count, "counts": counts, "value": value, "names": names}


## The one line. Empty batch answers "Nothing to loot." rather than a zero line,
## because a body that came back with nothing should be told so plainly.
static func describe(ids: Array) -> String:
	var summary := of(ids)
	var count := int(summary.get("count", 0))
	if count <= 0:
		return "Nothing to loot."
	var counts: Dictionary = summary.get("counts", {})
	var ordered := ordered_ids(counts)
	var parts := PackedStringArray()
	for index in mini(ordered.size(), MAX_NAMES):
		var item_id := ordered[index]
		parts.append("%s x%d" % [PickupScript.item_name(item_id), int(counts[item_id])])
	if ordered.size() > MAX_NAMES:
		parts.append("and %d more" % (ordered.size() - MAX_NAMES))
	return "Looted %d%s%s%s%d G" % [count, SEP, ", ".join(parts), SEP,
		int(summary.get("value", 0))]


## The distinct ids in catalog order. An id the catalog does not carry sorts last
## and by name, so an unknown piece lands at the tail of the line instead of
## floating around it.
static func ordered_ids(counts: Dictionary) -> Array[String]:
	_ensure_rank()
	var out: Array[String] = []
	for key in counts.keys():
		out.append(str(key))
	out.sort_custom(func(left: String, right: String) -> bool:
		var rank_left := int(_rank.get(left, _rank.size()))
		var rank_right := int(_rank.get(right, _rank.size()))
		if rank_left == rank_right:
			return left < right
		return rank_left < rank_right)
	return out


static func _ensure_rank() -> void:
	if not _rank.is_empty():
		return
	var index := 0
	for item_id in State.ITEMS.keys():
		_rank[str(item_id)] = index
		index += 1
