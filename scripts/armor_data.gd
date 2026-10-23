extends RefCounted
## Shared armor vocabulary: five independently equipped slots across four sets.
## Item ids, visual set indexes and damage reduction all live here so the hub,
## both match controllers, the rig and the network cannot drift apart.

const SLOTS := ["head", "chest", "hands", "legs", "feet"]
const SLOT_LABELS := {"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Feet"}
const SET_IDS := ["leather", "mail", "plate", "cloth"]
const SET_ABBREVIATIONS := ["LEA", "MAI", "PLA", "CLO"]
const SHIELD_BIT := 1024
const MAX_REDUCTION := 0.45

## Per-slot protection.  A complete mail kit reaches 15% and a complete plate
## kit 30%; mixed kits add exactly the pieces the player is wearing.
const REDUCTION := [
	{"head":0.00, "chest":0.00, "hands":0.00, "legs":0.00, "feet":0.00},
	{"head":0.03, "chest":0.05, "hands":0.02, "legs":0.03, "feet":0.02},
	{"head":0.07, "chest":0.09, "hands":0.04, "legs":0.06, "feet":0.04},
	{"head":0.00, "chest":0.00, "hands":0.00, "legs":0.00, "feet":0.00},
]

static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, slot.capitalize()))

static func set_abbreviation(index: int) -> String:
	return SET_ABBREVIATIONS[clampi(index, 0, SET_ABBREVIATIONS.size() - 1)]

static func item_id(set_index: int, slot: String) -> String:
	return "armor_%s_%s" % [SET_IDS[clampi(set_index, 0, SET_IDS.size() - 1)], slot]

static func reduction_for(set_index: int, slot: String) -> float:
	return float(REDUCTION[clampi(set_index, 0, REDUCTION.size() - 1)].get(slot, 0.0))

static func reduction(pieces: Dictionary) -> float:
	var total := 0.0
	for slot in SLOTS:
		total += reduction_for(int(pieces.get(slot, 0)), slot)
	return minf(MAX_REDUCTION, total)

static func pack(pieces: Dictionary) -> int:
	var bits := 0
	for index in SLOTS.size():
		bits |= (int(pieces.get(SLOTS[index], 0)) & 3) << (index * 2)
	return bits

static func unpack(bits: int) -> Dictionary:
	var pieces := {}
	for index in SLOTS.size():
		pieces[SLOTS[index]] = (bits >> (index * 2)) & 3
	return pieces

