extends RefCounted
## Seat loadouts arrive over the wire, so only real catalog ids that are legal
## for the requested hand may be applied. Both the arena and the open world use
## this one validator; a malformed kit leaves the existing presentation alone.

const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

const TRINKET_SLOTS := ["neck", "ring1", "ring2"]

static func hand(value: Variant, slot: String) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var id := str(value)
	var item: Dictionary = State.ITEMS.get(id,{})
	if item.is_empty() or not Rules.allowed(item,slot):
		return ""
	return id

## Stats ride the rig's own trinket dictionary; skills replace the hand gates,
## so every welded skill on a held piece fires from the hand that holds it. A
## hand with no weld keeps the stock skill `apply_loadout` put there, and a hand
## with several welds keeps all of them.
static func _apply_annoints(rig, annoints: Dictionary) -> void:
	if rig == null or annoints.is_empty():
		return
	var stats: Variant = annoints.get("stats", {})
	var procs: Variant = annoints.get("procs", [])
	if rig.has_method("apply_annointments"):
		rig.apply_annointments(stats if stats is Dictionary else {},
			procs if procs is Array else [])
	var skills: Variant = annoints.get("skills", {})
	var marks: Variant = annoints.get("marks", {})
	if marks is Dictionary and rig.has_method("set_annoint_marks"):
		rig.set_annoint_marks(marks)
	if not skills is Dictionary:
		return
	var current: Variant = rig.get("anointed")
	var held: Dictionary = current if current is Dictionary else {}
	var hands := {
		"main": AbilityRules.skill_ids(held.get("main", "")),
		"off": AbilityRules.skill_ids(held.get("off", "")),
	}
	for hand in ["main", "off"]:
		var welded := AbilityRules.skill_ids((skills as Dictionary).get(hand, ""))
		if not welded.is_empty():
			hands[hand] = welded
	rig.anointed = hands

## The worn kit travels beside the hands. Each id must be a real catalog item
## legal in its slot; anything else becomes an empty slot.
static func trinkets(value: Variant) -> Dictionary:
	var kit := {"neck":"", "ring1":"", "ring2":"", "off":""}
	if typeof(value) != TYPE_DICTIONARY:
		return kit
	var source: Dictionary = value
	for slot in TRINKET_SLOTS:
		kit[slot] = hand(source.get(slot,""),slot)
	return kit

## `anointed` is the altar ledger's list of anointed catalog ids. It is a local,
## trusted argument and never read from `loadout`: a seat loadout can arrive over
## the wire, and a peer must not be able to claim a skill its steel was never given.
## `annoints` is the same kind of trusted-local argument as `anointed`: the
## warband's own ledger, never a loadout field. `{stats: Dictionary,
## skills: {main, off}, marks: {main, off}}`; a bare dictionary leaves the rig
## alone. `marks` is how many annointments each held copy carries, which the rig
## draws on the piece. `hotbar_order` is the player's own sequence for the ten
## keys, read off the mercenary's record: it changes the slot a skill fires from
## and never which skills the kit grants, so it rides beside the loadout too.
static func apply(rig, loadout: Dictionary, anointed: Array = [],
		annoints: Dictionary = {}, hotbar_order: Array = []) -> void:
	if rig == null or loadout.is_empty():
		return
	rig.set("hotbar_order", AbilityRules.skill_ids(hotbar_order))
	var bow: Variant = loadout.get("bow")
	var sword: Variant = loadout.get("sword")
	var armor: Variant = loadout.get("armor")
	var bow_ok := typeof(bow) == TYPE_INT and int(bow) >= 0 and int(bow) <= 2
	var sword_ok := typeof(sword) == TYPE_INT and int(sword) >= 0 and int(sword) <= 2
	var armor_ok := typeof(armor) == TYPE_INT and int(armor) >= 0 and int(armor) <= ArmorData.PIECE_MASK
	var main_raw: Variant = loadout.get("main")
	var off_raw: Variant = loadout.get("off")
	var main := hand(main_raw,"main")
	var off := hand(off_raw,"off")
	var worn := trinkets(loadout.get("trinkets"))
	worn["off"] = off
	var hands_present := loadout.has("main") or loadout.has("off")
	var main_ok := not loadout.has("main") or (typeof(main_raw) == TYPE_STRING and (str(main_raw).is_empty() or not main.is_empty()))
	var off_ok := not loadout.has("off") or (typeof(off_raw) == TYPE_STRING and (str(off_raw).is_empty() or not off.is_empty()))
	if hands_present and main_ok and off_ok:
		# Hub kits carry the whole paperdoll; the state script derives the
		# weapon mode, staff, focus, shield and off-hand from the validated ids.
		# Explicitly empty hands are deliberate (unarmed); a malformed non-empty
		# hand falls through instead of wiping a valid seat.
		var pieces: Dictionary = ArmorData.unpack(int(armor) & ArmorData.PIECE_MASK) if armor_ok else rig.armor_pieces.duplicate()
		rig.apply_loadout(State.build_loadout(main,off,pieces,worn,anointed))
		_apply_annoints(rig, annoints)
		return
	# A kit that omits the hands still carries its worn trinkets.
	rig.apply_trinkets(worn)
	if bow_ok:
		rig.set_bow(int(bow))
	if sword_ok:
		rig.set_sword(int(sword))
	if armor_ok:
		rig.set_armor_bits(int(armor))
	_apply_annoints(rig, annoints)
