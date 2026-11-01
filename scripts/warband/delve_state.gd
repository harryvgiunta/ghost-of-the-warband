class_name WarbandDelve
extends RefCounted
## The delve as warband state: which bodies went down, and the one inventory
## they carry between them.
##
## The town stash is the warband's safe pool. A descent takes a party and its
## delve inventory - the supplies packed at the Hollow's mouth - into the cave,
## and everything the party takes down there (a corpse's kit, a drop, a fallen
## squadmate's gear taken back off his body) lands in that inventory, never in the
## stash. Climbing out alive empties the inventory into the stash (the essence it
## carried into the altar's wallet); a party that falls loses the inventory and
## everything its members still wear.
##
## While no descent runs the inventory is simply the pack being made up in town:
## packed pieces are out of the stash and wait at the mouth for the next party.
##
## Pure data, like the stash and the ledger: no node, and `Warband` persists it.

const StashScript = preload("res://scripts/warband/town_stash_model.gd")

## The Hollow has one floor so far.
const FLOOR_ONE := 1

## True from the moment a party goes down until it climbs out or falls.
var active := false
var depth := FLOOR_ONE
## The bodies that went down, by mercenary id, in the order they were chosen.
var party: Array[int] = []
## The delve inventory: the packed supplies, then everything looted below.
var inventory: WarbandStash = StashScript.new()


## Whether this mercenary is one of the party below. False while no descent runs.
func is_member(merc_id: int) -> bool:
	return active and party.has(merc_id)


## Start a descent with these bodies. Ids are taken once each and in order; the
## inventory is whatever was packed, untouched.
func begin(party_ids: Array, floor_number: int = FLOOR_ONE) -> void:
	party.clear()
	for raw_id in party_ids:
		var merc_id := int(raw_id)
		if merc_id > 0 and not party.has(merc_id):
			party.append(merc_id)
	depth = maxi(FLOOR_ONE, floor_number)
	active = not party.is_empty()


## End the descent. The inventory is the caller's to empty (a climb out) or to
## lose (a fall); this only forgets who went down.
func finish() -> void:
	active = false
	party.clear()
	depth = FLOOR_ONE


## Forget the descent and the pack: a fresh campaign.
func clear() -> void:
	finish()
	inventory.clear()


func to_dict() -> Dictionary:
	return {
		"active": active,
		"depth": depth,
		"party": party.duplicate(),
		"inventory": inventory.to_dict(),
	}


## Read a saved record. Anything that is not a well-formed descent reads as no
## descent, and a descent with nobody in it is not one.
func from_dict(data: Variant) -> void:
	clear()
	if not (data is Dictionary):
		return
	var record: Dictionary = data
	var saved_inventory: Variant = record.get("inventory", {})
	if saved_inventory is Dictionary:
		inventory.from_dict(saved_inventory)
	var ids: Variant = record.get("party", [])
	if bool(record.get("active", false)) and ids is Array:
		begin(ids, int(record.get("depth", FLOOR_ONE)))
