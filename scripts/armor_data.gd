extends RefCounted
## Shared armor vocabulary: five independently equipped slots across five sets.
## Item ids, visual set indexes and damage reduction all live here so the hub,
## both match controllers, the rig and the network cannot drift apart.

const SLOTS := ["head", "chest", "hands", "legs", "feet"]
const SLOT_LABELS := {"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Feet"}
## Makeshift is the salvage set the ranger starts in; the four forged sets sit
## on top of it. Order is the wire and HUD index, not a quality ranking.
const SET_IDS := ["leather", "mail", "plate", "cloth", "makeshift"]
const SET_ABBREVIATIONS := ["LEA", "MAI", "PLA", "CLO", "MSH"]
## Three bits per slot fits five sets. The packed armour integer shares its
## field with the shield bit, so these two constants move together.
const BITS_PER_SLOT := 3
const SLOT_MASK := (1 << BITS_PER_SLOT) - 1
const PIECE_MASK := (1 << (5 * BITS_PER_SLOT)) - 1
const SHIELD_BIT := 1 << (5 * BITS_PER_SLOT)
const MAX_REDUCTION := 0.45

## Per-slot protection. A complete mail kit reaches 15% and a complete plate
## kit 30%; mixed kits add exactly the pieces the player is wearing. The two
## tier-0 starter skins (Ranger leather and Makeshift salvage) guard nothing by
## design: they change what the ranger looks like, not what a blow costs.
const REDUCTION := [
	{"head":0.00, "chest":0.00, "hands":0.00, "legs":0.00, "feet":0.00},
	{"head":0.03, "chest":0.05, "hands":0.02, "legs":0.03, "feet":0.02},
	{"head":0.07, "chest":0.09, "hands":0.04, "legs":0.06, "feet":0.04},
	{"head":0.00, "chest":0.00, "hands":0.00, "legs":0.00, "feet":0.00},
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
		bits |= (int(pieces.get(SLOTS[index], 0)) & SLOT_MASK) << (index * BITS_PER_SLOT)
	return bits

static func unpack(bits: int) -> Dictionary:
	var pieces := {}
	for index in SLOTS.size():
		pieces[SLOTS[index]] = clampi((bits >> (index * BITS_PER_SLOT)) & SLOT_MASK,
			0, SET_IDS.size() - 1)
	return pieces

