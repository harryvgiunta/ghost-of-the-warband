class_name WeaponUnlockRegistry
extends RefCounted
## The roguelite armory: one definition per weapon the Unlock Totem can open and
## the Weapon Rack can hand out.
##
## The catalog of *pieces* is `PlayerState.ITEMS` (`bow_short`, `sword_great`,
## `axe_makeshift`, ...), and it stays the one source of names, prices and
## inventory behaviour. This file is the layer above it: what each piece does in
## the arena loop, expressed in numbers the proc engine and the firing controllers
## actually read - a damage multiplier over the rig's own base, a rate multiplier,
## a proc coefficient, a pierce budget, a spread, and whether the piece throws.
##
## Everything already in the repo is registered automatically (`_derive`), so a
## weapon added to the catalog tomorrow appears in the pool without a second list
## to maintain. The authored rows below override the derived defaults for the
## pieces whose roguelite identity is specific: the two starters, the two
## crossbows, the throwing steel, and the makeshift axe's charges.

const State = preload("res://scripts/player_state.gd")
const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")

const RANGED := "ranged"
const MELEE := "melee"
const STARTER_RANGED := "bow_twig"
const STARTER_MELEE := "hatchet_makeshift"

const RARITY_COMMON := "common"
const RARITY_EPIC := "epic"
const RARITY_LEGENDARY := "legendary"



## The authored rows. A row here replaces the derived defaults wholesale, because
## a piece whose whole purpose is a firing profile should be read in one place.
const AUTHORED := {
	STARTER_RANGED: {
		"slot": RANGED, "item_kind": "bow", "item_index": 3, "archetype": "starter_bow",
		"damage_mult": 1.0, "attack_mult": 1.0, "proc": 1.0, "pierce": 0,
		"spread": 0.0, "projectile": "arrow", "homing": 0.0, "ricochet": 0,
		"knockback": 1.0, "gore": 1.0, "throw_charges": 0, "throw_regen": 0.0,
		"rarity": RARITY_COMMON, "unlock_cost": 0,
		"description": "The bow a prisoner whittles on the walk out. One shaft, " +
"a clean line, and a 1.0x proc coefficient.",
	},
	STARTER_MELEE: {
		"slot": MELEE, "item_kind": "sword", "item_index": 5, "archetype": "hatchet",
		"damage_mult": 1.05, "attack_mult": 1.35, "proc": 1.0, "pierce": 0,
		"spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 1.1, "gore": 1.4, "throw_charges": 2, "throw_regen": 1.1,
		"rarity": RARITY_COMMON, "unlock_cost": 0,
		"description": "Fast close-quarters cuts and a quick secondary, and every " +
"landed cut rolls the melee proc chain.",
	},
	"xbow_heavy": {
		"slot": RANGED, "item_kind": "bow", "item_index": 4, "archetype": "heavy_crossbow",
		"damage_mult": 1.15, "attack_mult": 0.8, "proc": 1.5, "pierce": 1,
		"spread": 0.0, "projectile": "bolt", "homing": 0.0, "ricochet": 0,
		"knockback": 1.4, "gore": 1.6, "throw_charges": 0, "throw_regen": 0.0,
		"rarity": RARITY_EPIC, "unlock_cost": 4,
		"description": "A slow, crushing bolt that passes through the first body " +
"it meets. 1.5x proc coefficient.",
	},
	"xbow_auto": {
		"slot": RANGED, "item_kind": "bow", "item_index": 5, "archetype": "repeater",
		"damage_mult": 0.55, "attack_mult": 1.0, "proc": 0.5, "pierce": 0,
		"spread": 5.0, "projectile": "bolt", "homing": 0.0, "ricochet": 0,
		"knockback": 0.7, "gore": 0.8, "throw_charges": 0, "throw_regen": 0.0,
		"rarity": RARITY_EPIC, "unlock_cost": 4,
		"description": "A full-auto bolt repeater: light bolts, wide spread, and " +
"the fastest trigger in the armory. Built to feed On-Hit chains. 0.5x proc.",
	},
	"axe_makeshift": {
		"slot": MELEE, "item_kind": "sword", "item_index": 5, "archetype": "throwing_axe",
		"damage_mult": 1.1, "attack_mult": 1.0, "proc": 1.1, "pierce": 0,
		"spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 1.5, "gore": 2.0, "throw_charges": 3, "throw_regen": 1.1,
		"rarity": RARITY_COMMON, "unlock_cost": 2,
		"description": "A hafted head balanced to throw. Three charges, a heavy " +
"arc, and a gore multiplier that takes limbs off.",
	},
	"throwing_axe": {
		"slot": MELEE, "item_kind": "sword", "item_index": 5, "archetype": "throwing_axe",
		"damage_mult": 1.2, "attack_mult": 1.0, "proc": 1.15, "pierce": 0,
		"spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 1.6, "gore": 2.2, "throw_charges": 3, "throw_regen": 1.0,
		"rarity": RARITY_EPIC, "unlock_cost": 4,
		"description": "The arena's own throwing axe: three heavy arcs, a gore " +
"multiplier that opens a body, and enough stagger to stop a charge.",
	},
	"dagger_throwing": {
		"slot": MELEE, "item_kind": "dagger", "item_index": 2, "archetype": "throwing_knife",
		"damage_mult": 0.9, "attack_mult": 1.4, "proc": 1.3, "pierce": 0,
		"spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 0.8, "gore": 1.1, "throw_charges": 5, "throw_regen": 0.45,
		"rarity": RARITY_COMMON, "unlock_cost": 2,
		"description": "A balanced knife and a fast hand: five quick throws on a " +
"short recharge, and the best proc coefficient on the makeshift tier.",
	},
	"javelin_iron": {
		"slot": MELEE, "item_kind": "sword", "item_index": 6, "archetype": "javelin",
		"damage_mult": 1.5, "attack_mult": 0.75, "proc": 1.2, "pierce": 1,
		"spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 1.8, "gore": 2.4, "throw_charges": 2, "throw_regen": 2.2,
		"rarity": RARITY_LEGENDARY, "unlock_cost": 6,
		"description": "A whole iron-headed shaft, thrown for stagger and " +
"dismemberment. Two charges on a long recharge, and it punches through.",
	},
	"dagger_ironwood": {
		"slot": MELEE, "item_kind": "dagger", "item_index": 1, "archetype": "shiv",
		"damage_mult": 1.0, "attack_mult": 1.25, "proc": 1.0, "pierce": 0,
		"spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 0.8, "gore": 0.9, "throw_charges": 4, "throw_regen": 0.6,
		"rarity": RARITY_COMMON, "unlock_cost": 2,
		"description": "The wood's own shiv, quick in the hand and quicker out " +
"of it. Four throws on a short recharge.",
	},
}

static var _defs: Dictionary = {}
static var _built := false


# --- the table -------------------------------------------------------------

static func _ensure() -> void:
	if _built:
		return
	_built = true
	_defs.clear()
	# The catalog is the floor: every bow, blade and staff in `PlayerState.ITEMS`
	# is a piece the arena can field.
	for item_id in State.ITEMS:
		var id := str(item_id)
		var item: Dictionary = State.ITEMS[item_id]
		var slot := _slot_for_kind(str(item.get("kind", "")))
		if slot.is_empty():
			continue
		_defs[id] = _derive(id, item, slot)
	# The authored rows sit on top, including the pieces whose catalog ids are
	# also carried by an existing item (the makeshift axe).
	for id in AUTHORED:
		var base: Dictionary = _defs.get(id, _default_definition(str(id)))
		base.merge(AUTHORED[id], true)
		base["id"] = str(id)
		var item: Dictionary = State.ITEMS.get(id, {})
		base["name"] = str(item.get("name", base.get("name", id)))
		_defs[str(id)] = base


static func definitions() -> Dictionary:
	_ensure()
	return _defs


static func all_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id in _defs:
		out.append(str(id))
	out.sort()
	return out


static func has(weapon_id: String) -> bool:
	_ensure()
	return _defs.has(weapon_id)


static func get_weapon(weapon_id: String) -> Dictionary:
	_ensure()
	return _defs.get(weapon_id, {})


static func display_name(weapon_id: String) -> String:
	var def := get_weapon(weapon_id)
	if def.is_empty():
		return weapon_id
	return str(def.get("name", weapon_id))


static func slot_of(weapon_id: String) -> String:
	return str(get_weapon(weapon_id).get("slot", ""))


static func is_default(weapon_id: String) -> bool:
	return weapon_id == STARTER_RANGED or weapon_id == STARTER_MELEE


static func default_ids() -> Array[String]:
	return [STARTER_RANGED, STARTER_MELEE]


static func ids_for_slot(slot: String) -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id in _defs:
		if str((_defs[id] as Dictionary).get("slot", "")) == slot:
			out.append(str(id))
	out.sort_custom(func(a: String, b: String) -> bool:
		var def_a: Dictionary = _defs[a]
		var def_b: Dictionary = _defs[b]
		var default_a := is_default(a)
		var default_b := is_default(b)
		if default_a != default_b:
			return default_a
		var cost_a := int(def_a.get("unlock_cost", 3))
		var cost_b := int(def_b.get("unlock_cost", 3))
		if cost_a == cost_b:
			return a < b
		return cost_a < cost_b)
	return out


## The pool the Unlock Totem draws from: every piece that is not a starter.
static func unlock_pool() -> Array[String]:
	var out: Array[String] = []
	for id in all_ids():
		if not is_default(id):
			out.append(id)
	return out


## What a piece in a body's hand is, for the firing controllers. A weapon the
## registry has never seen (a modded catalog entry, a test fixture) is answered
## with a neutral definition instead of failing the shot.
static func resolve(weapon_id: String) -> Dictionary:
	if has(weapon_id):
		return get_weapon(weapon_id).duplicate(true)
	var item: Dictionary = State.ITEMS.get(weapon_id, {})
	var slot := _slot_for_kind(str(item.get("kind", "")))
	if slot.is_empty():
		return {}
	return _derive(weapon_id, item, slot)


# --- derivation ------------------------------------------------------------

static func _slot_for_kind(kind: String) -> String:
	match kind:
		"bow", "staff":
			return RANGED
		"sword", "dagger":
			return MELEE
	return ""


## Defaults read off the piece's own catalog row: a bow's draw time and a blade's
## swing time are already authored in `Archer`, so the registry does not restate
## them - it names the multiplier the arena loop layers over them.
static func _derive(id: String, item: Dictionary, slot: String) -> Dictionary:
	var def := _default_definition(id)
	def["slot"] = slot
	def["item_kind"] = str(item.get("kind", "sword"))
	def["item_index"] = int(item.get("index", 0))
	def["name"] = str(item.get("name", id))
	def["unlock_cost"] = int(item.get("price", 0))
	var index := int(def["item_index"])
	match str(def["item_kind"]):
		"bow":
			def["archetype"] = "bow"
			def["projectile"] = "arrow"
			# A war bow hits harder than a scout bow and draws slower; the rig
			# already owns both numbers, so the registry only names the edge.
			def["damage_mult"] = 1.0 + 0.18 * float(index)
			def["proc"] = 1.0 + 0.1 * float(index)
			def["rarity"] = RARITY_EPIC if index >= 2 else RARITY_COMMON
			def["unlock_cost"] = 4 if index >= 2 else 2
		"staff":
			def["archetype"] = "staff"
			def["projectile"] = "spell"
			def["damage_mult"] = 1.0
			def["proc"] = 1.15
			def["rarity"] = RARITY_EPIC
			def["unlock_cost"] = 4
		"sword":
			var data: Dictionary = Archer.SWORD_DATA[clampi(index, 0,
				Archer.SWORD_DATA.size() - 1)]
			def["archetype"] = "axe" if index == 5 else ("branch" if index == 4 else "blade")
			def["damage_mult"] = 1.0
			def["attack_mult"] = 1.0
			def["proc"] = 1.0
			def["gore"] = 1.6 if index == 5 else (1.35 if index == 4 else 1.0)
			def["knockback"] = 1.3 if bool(data.get("two_handed", false)) else 1.0
			def["throw_charges"] = 1
			def["throw_regen"] = 1.5
			def["rarity"] = RARITY_EPIC if float(data.get("damage", 0.0)) >= 38.0 else RARITY_COMMON
			def["unlock_cost"] = 4 if def["rarity"] == RARITY_EPIC else 2
		"dagger":
			def["archetype"] = "shiv" if index == 1 else "knife"
			def["damage_mult"] = 1.0
			def["attack_mult"] = 1.15
			def["proc"] = 1.1
			def["gore"] = 0.9
			def["throw_charges"] = 2
			def["throw_regen"] = 1.0
			def["rarity"] = RARITY_COMMON
			def["unlock_cost"] = 2
	return def


static func _default_definition(id: String) -> Dictionary:
	return {
		"id": id, "name": id, "slot": MELEE, "item_kind": "sword", "item_index": 0,
		"archetype": "blade", "damage_mult": 1.0, "attack_mult": 1.0, "proc": 1.0,
		"pierce": 0, "spread": 0.0, "projectile": "", "homing": 0.0, "ricochet": 0,
		"knockback": 1.0, "gore": 1.0, "throw_charges": 1, "throw_regen": 1.5,
		"rarity": RARITY_COMMON, "unlock_cost": 2,
		"description": "",
	}
