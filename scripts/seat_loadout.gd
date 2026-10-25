extends RefCounted
## Seat loadouts arrive over the wire, so only real catalog ids that are legal
## for the requested hand may be applied. Both the arena and the open world use
## this one validator; a malformed kit leaves the existing presentation alone.

const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")

static func hand(value: Variant, slot: String) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var id := str(value)
	var item: Dictionary = State.ITEMS.get(id,{})
	if item.is_empty() or not Rules.allowed(item,slot):
		return ""
	return id

static func apply(rig, loadout: Dictionary) -> void:
	if rig == null or loadout.is_empty():
		return
	var bow: Variant = loadout.get("bow")
	var sword: Variant = loadout.get("sword")
	var armor: Variant = loadout.get("armor")
	var bow_ok := typeof(bow) == TYPE_INT and int(bow) >= 0 and int(bow) <= 2
	var sword_ok := typeof(sword) == TYPE_INT and int(sword) >= 0 and int(sword) <= 2
	var armor_ok := typeof(armor) == TYPE_INT and int(armor) >= 0 and int(armor) <= 1023
	var main_raw: Variant = loadout.get("main")
	var off_raw: Variant = loadout.get("off")
	var main := hand(main_raw,"main")
	var off := hand(off_raw,"off")
	var hands_present := loadout.has("main") or loadout.has("off")
	var main_ok := not loadout.has("main") or (typeof(main_raw) == TYPE_STRING and (str(main_raw).is_empty() or not main.is_empty()))
	var off_ok := not loadout.has("off") or (typeof(off_raw) == TYPE_STRING and (str(off_raw).is_empty() or not off.is_empty()))
	if hands_present and main_ok and off_ok:
		# Hub kits carry the whole paperdoll; the state script derives the
		# weapon mode, staff, focus, shield and off-hand from the validated ids.
		# Explicitly empty hands are deliberate (unarmed); a malformed non-empty
		# hand falls through instead of wiping a valid seat.
		var pieces: Dictionary = ArmorData.unpack(int(armor) & 1023) if armor_ok else rig.armor_pieces.duplicate()
		rig.apply_loadout(State.build_loadout(main,off,pieces))
		return
	if bow_ok:
		rig.set_bow(int(bow))
	if sword_ok:
		rig.set_sword(int(sword))
	if armor_ok:
		rig.set_armor_bits(int(armor))
