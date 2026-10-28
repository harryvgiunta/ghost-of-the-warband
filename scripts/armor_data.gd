extends RefCounted
## Shared armor vocabulary: five independently equipped slots across five sets.
## Item ids, visual set indexes and damage reduction all live here so the hub,
## both match controllers, the rig and the network cannot drift apart.
##
## Reduction runs on two channels. A head hit resolves the helmet alone against
## the 2x head zone, so a 50% helmet turns a headshot back into a normal hit and
## a 75% one leaves half of it. Every other hit resolves the four body pieces
## summed. `TrinketStats.damage_reduction` adds the worn guard to whichever
## channel a hit used.
##
## A slot may also be empty: `NONE` wears nothing and guards nothing, and its
## code is the highest one in the slot's three bits so it survives the packed
## loadout and the snapshot.

const SLOTS := ["head", "chest", "hands", "legs", "feet"]
const BODY_SLOTS := ["chest", "hands", "legs", "feet"]
const SLOT_LABELS := {"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Feet"}
## `naked` is what a prisoner in the wood actually wears - an old shirt and a
## pair of shorts - and it guards nothing. The four forged sets and the salvage
## kit sit on top of it. Order is the wire and HUD index, not a quality ranking.
## Three bits per slot carry eight codes, so the six named sets and the two
## spare codes are all that field can hold.
const SET_IDS := ["leather", "mail", "plate", "cloth", "makeshift", "naked"]
const SET_ABBREVIATIONS := ["LEA", "MAI", "PLA", "CLO", "MSH", "NAK"]
## Three bits per slot fits the six sets with two codes left over for NONE. The
## packed armour integer shares its field width with the shield bit, so a seventh
## set would need that bit to move.
const BITS_PER_SLOT := 3
const SLOT_MASK := (1 << BITS_PER_SLOT) - 1
const PIECE_MASK := (1 << (5 * BITS_PER_SLOT)) - 1
const SHIELD_BIT := 1 << (5 * BITS_PER_SLOT)
## Empty slot. Three bits carry six set indexes, so every code above the sets
## is empty and a negative value packs itself into those spare codes.
const NONE := -1

## Per set, in `SET_IDS` order: the helmet's figure against a head hit, and the
## body figure a complete four-piece body kit adds.
const HEAD_REDUCTION := [0.20, 0.30, 0.50, 0.05, 0.20, 0.00]
const BODY_REDUCTION := [0.10, 0.25, 0.30, 0.05, 0.10, 0.00]
## Body pieces split that body figure 1 : 1 : 0.3 : 0.3 over chest, legs, hands
## and feet — a plate chest is 11.5%, its gauntlets 3.5% — so a mixed kit adds
## exactly the pieces worn and a full kit adds the row's body figure.
const BODY_WEIGHTS := {"chest":1.0, "legs":1.0, "hands":0.3, "feet":0.3}
const BODY_WEIGHT_TOTAL := 2.6

static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, slot.capitalize()))

static func set_abbreviation(index: int) -> String:
	if index < 0 or index >= SET_ABBREVIATIONS.size():
		return "--"
	return SET_ABBREVIATIONS[index]

static func item_id(set_index: int, slot: String) -> String:
	return "armor_%s_%s" % [SET_IDS[clampi(set_index, 0, SET_IDS.size() - 1)], slot]

## The set a worn piece belongs to, `NONE` for an empty slot or a piece that is
## not armour at all. The catalogue's ids are `armor_<set>_<slot>`, which is what
## `item_id()` writes, so this reads the id back instead of taking a dependency on
## the item table - and it is the one conversion a caller that holds *ids* needs
## before it can pack or dress a rig.
static func set_of_item(item_id: String) -> int:
	if item_id.is_empty() or not item_id.begins_with("armor_"):
		return NONE
	var parts := item_id.split("_")
	if parts.size() < 3:
		return NONE
	return SET_IDS.find(str(parts[1]).to_lower())

## One piece's contribution: the helmet's full figure, or a body piece's slice
## of its set's body figure. An empty slot contributes nothing.
static func reduction_for(set_index: int, slot: String) -> float:
	if set_index < 0:
		return 0.0
	var index := clampi(set_index, 0, SET_IDS.size() - 1)
	if slot == "head":
		return float(HEAD_REDUCTION[index])
	return float(BODY_REDUCTION[index]) * float(BODY_WEIGHTS.get(slot, 0.0)) / BODY_WEIGHT_TOTAL

## The head channel: the helmet alone, measured against the 2x head zone.
static func head_reduction(pieces: Dictionary) -> float:
	return reduction_for(int(pieces.get("head", NONE)), "head")

## The body channel: chest, hands, legs and feet summed.
static func body_reduction(pieces: Dictionary) -> float:
	var total := 0.0
	for slot in BODY_SLOTS:
		total += reduction_for(int(pieces.get(slot, NONE)), slot)
	return total

## `NONE` packs as the all-ones slot code; `unpack` reads that back as `NONE`.
static func pack(pieces: Dictionary) -> int:
	var bits := 0
	for index in SLOTS.size():
		bits |= (int(pieces.get(SLOTS[index], NONE)) & SLOT_MASK) << (index * BITS_PER_SLOT)
	return bits

static func unpack(bits: int) -> Dictionary:
	var pieces := {}
	for index in SLOTS.size():
		var value := (bits >> (index * BITS_PER_SLOT)) & SLOT_MASK
		pieces[SLOTS[index]] = value if value < SET_IDS.size() else NONE
	return pieces

