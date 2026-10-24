extends RefCounted
## Pure equipment vocabulary and planning for the ranger's ten equipment slots.
## Nothing here mutates state: every plan returns fresh copies of the equipped
## ids, the backpack and the floor so PlayerState can commit or discard it.

const SLOTS := ["head","chest","hands","legs","feet","neck","ring1","ring2","main","off"]
const SLOT_LABELS := {
	"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Boots",
	"neck":"Neck", "ring1":"Ring 1", "ring2":"Ring 2", "main":"Main Hand", "off":"Off-Hand",
}
const CATEGORIES := ["1h","2h","bow","staff","shield","focus","armor","jewelry","armor_bundle"]
const EQUIPPABLE := ["1h","2h","bow","staff","shield","focus","armor","jewelry"]
const TWO_HANDED := ["2h","bow","staff"]

static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, slot.capitalize()))

static func item_name(item: Dictionary) -> String:
	return str(item.get("name", "Gear"))

static func two_handed(item: Dictionary) -> bool:
	return str(item.get("category", "")) in TWO_HANDED

## Whether the item's category may occupy the slot at all.
static func allowed(item: Dictionary, slot: String) -> bool:
	if item.is_empty() or not slot in SLOTS:
		return false
	match str(item.get("category", "")):
		"1h":
			return slot == "main" or slot == "off"
		"2h", "bow", "staff":
			return slot == "main"
		"shield", "focus":
			return slot == "off"
		"armor":
			return slot == str(item.get("slot", ""))
		"jewelry":
			match str(item.get("slot", "")):
				"neck":
					return slot == "neck"
				"ring":
					return slot == "ring1" or slot == "ring2"
	return false

## The slot a fresh equip would choose: one-handers go to the main hand, off
## pieces to the off hand, armor and necklaces are fixed, and a ring fills the
## first empty ring slot before replacing ring 1.
static func auto_slot(item: Dictionary, equipped: Dictionary) -> String:
	var category := str(item.get("category", ""))
	match category:
		"1h", "2h", "bow", "staff":
			return "main"
		"shield", "focus":
			return "off"
		"armor":
			return str(item.get("slot", ""))
		"jewelry":
			match str(item.get("slot", "")):
				"neck":
					return "neck"
				"ring":
					if _slot_id(equipped, "ring1").is_empty():
						return "ring1"
					if _slot_id(equipped, "ring2").is_empty():
						return "ring2"
					return "ring1"
	return ""

static func plan_equip(equipped: Dictionary, inventory: Array, index: int, target_slot: String, items: Dictionary, capacity: int) -> Dictionary:
	var next_equipped := equipped.duplicate(true)
	var next_inventory: Array = inventory.duplicate()
	var floor: Array[String] = []
	if index < 0 or index >= inventory.size():
		return _result(false, "Choose a piece of gear in your backpack.", next_equipped, next_inventory, floor)
	var item_id := str(inventory[index])
	var item: Dictionary = items.get(item_id, {})
	if item.is_empty():
		return _result(false, "That item cannot be equipped.", next_equipped, next_inventory, floor)
	if not str(item.get("category", "")) in EQUIPPABLE:
		return _result(false, "%s cannot be equipped." % item_name(item), next_equipped, next_inventory, floor)
	var slot := target_slot
	if slot.is_empty():
		slot = auto_slot(item, equipped)
	if not allowed(item, slot):
		return _result(false, "%s cannot go in the %s slot." % [item_name(item), slot_label(slot)], next_equipped, next_inventory, floor)

	# The item leaves the backpack before anything is displaced, so a swap can
	# reuse its slot instead of spilling a displaced piece to the floor.
	next_inventory.remove_at(index)
	var notes: Array[String] = []
	if slot == "main":
		if two_handed(item):
			_displace(_slot_id(next_equipped, "main"), next_inventory, floor, capacity, items, notes)
			_displace(_slot_id(next_equipped, "off"), next_inventory, floor, capacity, items, notes)
			next_equipped["off"] = ""
		else:
			_displace(_slot_id(next_equipped, "main"), next_inventory, floor, capacity, items, notes)
		next_equipped["main"] = item_id
	elif slot == "off":
		var main_item: Dictionary = items.get(_slot_id(next_equipped, "main"), {})
		if two_handed(main_item):
			# A two-handed grip displaces the main hand and leaves it empty.
			_displace(_slot_id(next_equipped, "main"), next_inventory, floor, capacity, items, notes)
			next_equipped["main"] = ""
		_displace(_slot_id(next_equipped, "off"), next_inventory, floor, capacity, items, notes)
		next_equipped["off"] = item_id
	else:
		_displace(_slot_id(next_equipped, slot), next_inventory, floor, capacity, items, notes)
		next_equipped[slot] = item_id

	var message := "Equipped %s." % item_name(item)
	if not notes.is_empty():
		message += " " + ", ".join(PackedStringArray(notes)) + "."
	if not floor.is_empty():
		message += " No backpack room; check the ground."
	return _result(true, message, next_equipped, next_inventory, floor)

## Swap two equipped items, or move one into an empty slot. A move only needs
## the piece to be legal in the destination; a swap needs both to be legal
## where they land. The result must never leave a two-handed main hand paired
## with an off-hand item.
static func plan_move(equipped: Dictionary, from_slot: String, to_slot: String, items: Dictionary) -> Dictionary:
	var next_equipped := equipped.duplicate(true)
	if not from_slot in SLOTS or not to_slot in SLOTS:
		return {"ok":false, "message":"Choose two equipment slots.", "equipped":next_equipped, "inventory":[], "floor":[]}
	if from_slot == to_slot:
		return {"ok":false, "message":"That piece is already in that slot.", "equipped":next_equipped, "inventory":[], "floor":[]}
	var from_id := _slot_id(next_equipped, from_slot)
	var to_id := _slot_id(next_equipped, to_slot)
	if from_id.is_empty():
		return {"ok":false, "message":"That slot is empty.", "equipped":next_equipped, "inventory":[], "floor":[]}
	var from_item: Dictionary = items.get(from_id, {})
	if from_item.is_empty():
		return {"ok":false, "message":"That gear is unknown.", "equipped":next_equipped, "inventory":[], "floor":[]}
	var to_item: Dictionary = {}
	if to_id.is_empty():
		# Moving into an empty slot only needs the piece to fit there.
		if not allowed(from_item, to_slot):
			return {"ok":false, "message":"%s cannot go in the %s slot." % [item_name(from_item), slot_label(to_slot)], "equipped":next_equipped, "inventory":[], "floor":[]}
		next_equipped[from_slot] = ""
		next_equipped[to_slot] = from_id
	else:
		to_item = items.get(to_id, {})
		if to_item.is_empty():
			return {"ok":false, "message":"That gear is unknown.", "equipped":next_equipped, "inventory":[], "floor":[]}
		if not allowed(from_item, to_slot) or not allowed(to_item, from_slot):
			return {"ok":false, "message":"%s cannot go in the %s slot." % [item_name(from_item), slot_label(to_slot)], "equipped":next_equipped, "inventory":[], "floor":[]}
		next_equipped[from_slot] = to_id
		next_equipped[to_slot] = from_id
	var main_item: Dictionary = items.get(_slot_id(next_equipped, "main"), {})
	if two_handed(main_item) and not _slot_id(next_equipped, "off").is_empty():
		return {"ok":false, "message":"A two-handed weapon leaves no off hand.", "equipped":next_equipped, "inventory":[], "floor":[]}
	var message := "Swapped %s and %s." % [item_name(from_item), item_name(to_item)] if not to_item.is_empty() else "Moved %s to the %s slot." % [item_name(from_item), slot_label(to_slot)]
	return {"ok":true, "message":message, "equipped":next_equipped, "inventory":[], "floor":[]}

static func _slot_id(equipped: Dictionary, slot: String) -> String:
	var value: Variant = equipped.get(slot, "")
	return "" if value == null else str(value)

static func _displace(item_id: String, inventory: Array, floor: Array, capacity: int, items: Dictionary, notes: Array) -> void:
	if item_id.is_empty():
		return
	var label := item_name(items.get(item_id, {}))
	if inventory.size() < capacity:
		inventory.append(item_id)
		notes.append("%s moved to the backpack" % label)
	else:
		floor.append(item_id)
		notes.append("%s dropped to the floor" % label)

static func _result(ok: bool, message: String, equipped: Dictionary, inventory: Array, floor: Array) -> Dictionary:
	return {"ok":ok, "message":message, "equipped":equipped, "inventory":inventory, "floor":floor}
