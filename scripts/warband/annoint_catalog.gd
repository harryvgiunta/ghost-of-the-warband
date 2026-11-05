extends RefCounted
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ArmorData = preload("res://scripts/armor_data.gd")

## The annointment pool: every modifier the altar can weld to a piece of gear.
##
## One row, one class, one place. An `Entry` knows what it does, where it may be
## welded, how it reads on an item card, and how much an AI body wants it. The
## registry is built once from two shapes of data:
##
##   * `FAMILIES` - the blanket ladders (`attack speed 3/5/8/12/18%`). Every tier
##     becomes its own entry, so a ladder is one row of data and five modifiers.
##   * `NAMES` - the authored modifiers, each a small bundle of stats or a proc.
##
## Nothing here reads the world. `AnnointRoll` decides what a piece gets,
## `AnnointLedger` stores it, `AnnointRuntime` plays the procs. This file is the
## vocabulary those three share, and the only file an author edits to add one.
##
## `wired` is the honesty flag: an entry a system cannot yet play is listed with
## `wired=false`, it is excluded from the roll, and the card says so. Nothing in
## the pool is allowed to be a dead modifier in a player's hand.

## What an entry is. The roll only cares about ABILITY versus everything else.
enum Kind { STAT, PROC, ABILITY }

## When a PROC is rolled. STAT entries ignore this. `HIT` is the one
## damage-dealing edge: a blow the bearer's own hand or shaft landed, which the
## receiver never knows about, so `Combat` names the striker through the body's
## own `note_attack_landed`.
enum Trigger { DAMAGE_TAKEN, BLOCK, PARRY, LETHAL, KILL, HIT }

## The proc verbs `AnnointRuntime` can play. Keep this list short and literal:
## every verb here is one branch on the receiver, never a bespoke system.
enum Proc {
	HEAL,          # magnitude: health restored to the bearer
	STAMINA,       # magnitude: stamina restored to the bearer
	REFLECT,       # scale: share of the blow returned to the source
	ABSORB,        # scale: share of the blow never lands (once per `cooldown`)
	LETHAL_SAVE,   # leaves 1 health instead of dying (once per `cooldown`)
	STAGGER,       # seconds: stagger the source
	GUARD_BREAK,   # drops the source's guard where it is a bare guard
	BLEED,         # dps * duration: a real damage-over-time on the source
	QUICK_STRIKE,  # scale: strike again now, at `scale` times the swing rate
	POISON,        # magnitude * duration: a real damage-over-time on the target
	LIFESTEAL,     # scale: share of the damage the bearer deals, returned as health
}

const SLOT_MAIN := "main"
const SLOT_OFF := "off"
const ARMOUR_SLOTS := ["head", "chest", "hands", "legs", "feet"]

## Soft cap on one piece, and the hard ceiling the ledger enforces.
const MAX_PER_PIECE := 6

## --- what a class may be welded with ---------------------------------------
##
## The item rework: a weld has to fit the *material* it is laid on, not just the
## slot. These three tables are the whole of that rule - `keys` is the hard gate
## (a key absent here can never reach that class), `procs` the same gate for a
## proc's verb, and `weights` how much of the pool the family takes when the
## table does admit it. A weight below 1.0 is the "sometimes" in the design: the
## entry is legal, it is simply a rarer draw than the class's own bread.
##
## Every stat key belongs to exactly one family. `spell` is the robe channel -
## cloth armour and casting implements - and is deliberately separate from
## `bow`: a robe buys spells, leather buys arrows, and no piece buys both.
const FAMILY_OF_KEY := {
	"spell_damage": "spell",
	"cooldown": "spell",
	"ranged_damage": "bow",
	"flat_ranged": "flat",
	"flat_melee": "flat",
	"melee_damage": "melee",
	"throw_damage": "throw",
	"attack_speed": "tempo",
	"move_speed": "mobility",
	"guard": "defence",
	"health": "defence",
	"stamina": "defence",
	"stagger": "defence",
	"stamina_regen": "sustain",
	"heal_on_kill": "sustain",
	"stamina_on_kill": "sustain",
	"gold_find": "utility",
}

## A proc's verb read as a family, so a robe never arms a ward and a plate never
## arms a second strike.
const FAMILY_OF_PROC := {
	Proc.HEAL: "sustain",
	Proc.STAMINA: "sustain",
	Proc.LIFESTEAL: "sustain",
	Proc.REFLECT: "defence",
	Proc.ABSORB: "defence",
	Proc.LETHAL_SAVE: "defence",
	Proc.STAGGER: "defence",
	Proc.GUARD_BREAK: "control",
	Proc.BLEED: "melee",
	Proc.POISON: "melee",
	Proc.QUICK_STRIKE: "melee",
}

## The forged materials, in `ArmorData.SET_IDS` order, and their rules.
##
##   cloth   spell damage and spell modifiers, nothing else: never movement
##           speed, never attack speed, never damage reduction.
##   leather arrows and the body that draws them: ranged damage, attack speed,
##           movement speed, and guard only as a rarer draw.
##   plate   the wall: defence first, a few aggressive layers, never attack
##           speed and never movement speed.
##   mail    the soldier's compromise: mostly aggressive, some defence, and
##           attack and movement speed as the rarer draws.
const POLICY := {
	GROUP_CLOTH: {
		"keys": ["spell_damage", "cooldown", "stamina_regen"],
		"procs": [],
		"weights": {"spell": 1.0, "sustain": 0.35},
	},
	GROUP_LEATHER: {
		"keys": ["ranged_damage", "flat_ranged", "attack_speed", "move_speed", "guard",
			"stagger", "stamina_regen"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.ABSORB, Proc.REFLECT, Proc.STAGGER],
		"weights": {"bow": 1.0, "flat": 0.7, "tempo": 1.0, "mobility": 1.0,
			"defence": 0.25, "sustain": 0.6},
	},
	GROUP_MAIL: {
		"keys": ["melee_damage", "flat_melee", "ranged_damage", "guard", "health",
			"stamina", "stagger", "stamina_regen", "attack_speed", "move_speed"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.REFLECT, Proc.ABSORB, Proc.LETHAL_SAVE,
			Proc.STAGGER, Proc.GUARD_BREAK, Proc.BLEED, Proc.POISON, Proc.LIFESTEAL],
		"weights": {"melee": 1.0, "bow": 0.9, "flat": 0.6, "defence": 0.2,
			"sustain": 0.4, "tempo": 0.35, "mobility": 0.3},
	},
	GROUP_PLATE: {
		"keys": ["guard", "health", "stamina", "stagger", "stamina_regen",
			"melee_damage", "ranged_damage", "heal_on_kill", "stamina_on_kill"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.REFLECT, Proc.ABSORB, Proc.LETHAL_SAVE,
			Proc.STAGGER, Proc.GUARD_BREAK, Proc.BLEED],
		"weights": {"defence": 1.0, "melee": 0.3, "bow": 0.25, "sustain": 0.5},
	},
	GROUP_MAKESHIFT: {
		"keys": ["ranged_damage", "attack_speed", "move_speed", "guard",
			"health", "stamina", "stamina_regen"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.ABSORB, Proc.STAGGER],
		"weights": {"bow": 0.8, "tempo": 0.8, "mobility": 0.8, "defence": 0.5,
			"sustain": 0.5},
	},
	GROUP_NAKED: {"keys": [], "procs": [], "weights": {}},
	# --- weapons ---------------------------------------------------------
	GROUP_BOW: {
		"keys": ["ranged_damage", "flat_ranged", "attack_speed", "cooldown", "stamina_regen"],
		"procs": [Proc.HEAL, Proc.STAMINA],
		"weights": {"bow": 1.0, "flat": 1.0, "tempo": 0.6, "spell": 0.4, "sustain": 0.4},
	},
	GROUP_SWORD: {
		"keys": ["melee_damage", "flat_melee", "attack_speed", "guard", "cooldown",
			"stamina_regen", "health", "stamina"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.BLEED, Proc.LIFESTEAL, Proc.QUICK_STRIKE,
			Proc.GUARD_BREAK, Proc.ABSORB],
		"weights": {"melee": 1.0, "flat": 0.4, "tempo": 0.6, "defence": 0.4,
			"spell": 0.4, "sustain": 0.5},
	},
	GROUP_DAGGER: {
		"keys": ["melee_damage", "attack_speed", "move_speed", "cooldown", "stamina_regen"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.BLEED, Proc.POISON, Proc.QUICK_STRIKE,
			Proc.LIFESTEAL, Proc.GUARD_BREAK],
		"weights": {"melee": 1.0, "tempo": 0.8, "mobility": 0.5, "spell": 0.4,
			"sustain": 0.4},
	},
	GROUP_SHIELD: {
		# Anything but an arrow: a board may carry a spell, a thrown blade, a
		# weld of plate or a stride, and never the bow's own damage.
		"keys": ["health", "stamina", "melee_damage", "flat_melee", "throw_damage",
			"move_speed", "attack_speed", "guard", "stamina_regen", "stagger",
			"gold_find", "cooldown", "heal_on_kill", "stamina_on_kill", "spell_damage"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.REFLECT, Proc.ABSORB, Proc.LETHAL_SAVE,
			Proc.STAGGER, Proc.GUARD_BREAK, Proc.BLEED, Proc.POISON, Proc.QUICK_STRIKE,
			Proc.LIFESTEAL],
		"weights": {},
	},
	GROUP_STAFF: {
		"keys": ["spell_damage", "cooldown", "stamina_regen", "guard", "health",
			"stamina", "attack_speed"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.ABSORB, Proc.REFLECT, Proc.STAGGER,
			Proc.LETHAL_SAVE],
		"weights": {"spell": 1.0, "defence": 0.5, "sustain": 0.5},
	},
	GROUP_FOCUS: {
		"keys": ["spell_damage", "cooldown", "stamina_regen", "health", "stamina",
			"stagger", "stamina_on_kill"],
		"procs": [Proc.HEAL, Proc.STAMINA, Proc.ABSORB, Proc.LIFESTEAL],
		"weights": {"spell": 1.0, "defence": 0.7, "sustain": 0.6},
	},
}

## Gear groups an entry can name. An item resolves to a group set in
## `groups_of`; the entry matches when the two sets intersect.
const GROUP_ANY_WEAPON := "weapon"
const GROUP_MELEE := "melee"
const GROUP_SWORD := "sword"
const GROUP_DAGGER := "dagger"
const GROUP_TWO_HAND := "two_hand"
const GROUP_BOW := "bow"
const GROUP_STAFF := "staff"
const GROUP_SHIELD := "shield"
const GROUP_FOCUS := "focus"
const GROUP_RANGED := "ranged"
const GROUP_ARMOUR := "armour"
## Necklaces and rings. One group, split by slot: a necklace entry names `neck`
## and only ever welds to the cord around the throat.
const GROUP_JEWELRY := "jewelry"
## The four forged armour materials, and the two salvage ones. A worn piece
## resolves to exactly one of these, and the material - not the slot - decides
## what may be welded to it.
const GROUP_CLOTH := "cloth"
const GROUP_LEATHER := "leather"
const GROUP_MAIL := "mail"
const GROUP_PLATE := "plate"
const GROUP_MAKESHIFT := "makeshift"
const GROUP_NAKED := "naked"
## The robe channel. Cloth armour and casting implements carry this group, so a
## `spell` entry can reach a robe's chest and a staff's shaft and nothing else.
const GROUP_SPELL := "spell"
## The worn trinket slots a jewellery copy can occupy - the same three the altar
## offers, in the order `AbilityRules` lays their skills on the hotbar.
const JEWELRY_SLOTS := ["neck", "ring1", "ring2"]

class Entry extends RefCounted:
	var id: String = ""
	var name: String = ""
	var kind: int = 0
	var wired: bool = true
	## Gear groups this entry may weld to. Empty = the armour slots only.
	var groups: Array = []
	## Worn slots this entry may occupy: main / off / head ... feet.
	var slots: Array = []
	## `TrinketStats`-shaped deltas. Always positive: a downside rides `drawback`.
	var stats: Dictionary = {}
	## A lesser, same-shaped delta the entry's flavour demands (see `line`).
	var drawback: Dictionary = {}
	## PROC fields.
	var trigger: int = 0
	var proc: int = 0
	var chance: float = 1.0
	var every: int = 0
	var magnitude: float = 0.0
	var scale: float = 0.0
	var duration: float = 0.0
	var cooldown: float = 0.0
	## ABILITY field: an `AbilityRules` id, or "" when the pool declares it and
	## the rules table has not learned it yet.
	var ability: String = ""
	## AI vocabulary: what a disposition is buying.
	var tags: Array[String] = []
	## 0..1, the power band this entry sits in (a tier ladder climbs it).
	var power: float = 0.5
	## The card's one-line value, e.g. "+15% attack speed".
	var line: String = ""
	var note: String = ""

	func tier_tag() -> String:
		return "T%d" % int(round(1.0 + power * 4.0))

	## Does this entry fit a piece with these groups and slots?
	func fits(item_groups: Array, item_slots: Array) -> bool:
		if slots.is_empty() or item_slots.is_empty():
			return false
		var slot_ok := false
		for slot in slots:
			if item_slots.has(slot):
				slot_ok = true
				break
		if not slot_ok:
			return false
		if groups.is_empty():
			return false
		for group in groups:
			if item_groups.has(group):
				return true
		return false

	## Label/value rows for `WarbandItemCard.compose`. Same shape as
	## `TrinketStats.effect_rows`.
	func effect_rows() -> Array:
		var rows: Array = []
		rows.append({"label": "ANNOINT", "value": name})
		if not line.is_empty():
			rows.append({"label": "EFFECT", "value": line})
		if not note.is_empty():
			rows.append({"label": "", "value": note})
		return rows

	func summary() -> String:
		return "%s  •  %s" % [name, line] if not line.is_empty() else name

	## How much a body of this disposition wants the entry, 0..1. The squad's
	## arming and casting priority both read this so a new entry needs no new
	## `match` anywhere.
	func want(disposition: String) -> float:
		var base := power
		if kind == Kind.ABILITY:
			base += 0.15
		match disposition:
			"tank":
				if tags.has("defence"):
					base += 0.25
				if tags.has("offence"):
					base -= 0.05
				if tags.has("control"):
					base += 0.10
			"bow":
				if tags.has("ranged"):
					base += 0.25
				if tags.has("melee"):
					base -= 0.20
				if tags.has("mobility"):
					base += 0.05
			_:
				if tags.has("melee") or tags.has("offence"):
					base += 0.20
				if tags.has("mobility"):
					base += 0.05
		return clampf(base, 0.0, 1.0)


# --- vocabulary ------------------------------------------------------------

const ROMAN := ["I", "II", "III", "IV", "V"]

## Blanket ladders. `key` is a `TrinketStats` key, `values` the five rungs, and
## `unit` the formatter for the card line. One row here is five modifiers.
const FAMILIES := [
	# --- weapons -----------------------------------------------------------
	{"key": "attack_speed", "name": "Haste", "group": "weapon", "values": [0.03, 0.05, 0.08, 0.12, 0.18],
		"unit": "pct", "tags": ["offence", "tempo"],
		"note": "As a rate: a 1.0 s swing becomes 1.0 / (1 + bonus)."},
	{"key": "melee_damage", "name": "Keen Edge", "group": "melee", "values": [0.03, 0.05, 0.08, 0.12, 0.18],
		"unit": "pct", "tags": ["offence", "melee"]},
	{"key": "ranged_damage", "name": "Steady Draw", "group": "ranged", "values": [0.03, 0.05, 0.08, 0.12, 0.18],
		"unit": "pct", "tags": ["offence", "ranged"]},
	{"key": "throw_damage", "name": "Thrower's Grip", "group": "weapon", "values": [0.05, 0.10, 0.15, 0.25, 0.40],
		"unit": "pct", "tags": ["offence"]},
	{"key": "cooldown", "name": "Ritual Threads", "group": "weapon", "values": [0.03, 0.05, 0.08, 0.12, 0.18],
		"unit": "pct", "tags": ["tempo", "ability"]},
	{"key": "heal_on_kill", "name": "Thirst", "group": "weapon", "values": [2.0, 3.0, 5.0, 8.0, 12.0],
		"unit": "flat", "tags": ["sustain"]},
	{"key": "stamina_on_kill", "name": "Second Wind", "group": "weapon", "values": [5.0, 10.0, 20.0, 35.0, 50.0],
		"unit": "flat", "tags": ["sustain", "tempo"]},
	{"key": "stamina_regen", "name": "Deep Lungs", "group": "weapon", "values": [0.05, 0.10, 0.15, 0.20, 0.30],
		"unit": "pct", "tags": ["sustain"]},
	# Flat damage, additive on the weapon that lands the blow. A bow's arrow and
	# a sword's cut carry their own: the two never cross, so a heavy broadhead
	# on the string adds nothing to the blade in the other hand.
	{"key": "flat_ranged", "name": "Broadhead", "group": "bow", "values": [2.0, 3.0, 5.0, 8.0, 12.0],
		"unit": "flat", "tags": ["ranged", "offence"],
		"note": "Added to every arrow after the draw multiplier."},
	{"key": "flat_melee", "name": "Ground Edge", "group": "sword", "values": [2.0, 3.0, 5.0, 8.0, 12.0],
		"unit": "flat", "tags": ["melee", "offence"],
		"note": "Added to every swing after the melee multiplier."},
	# The robe channel. Cloth armour and the casting implements share this ladder,
	# so a robe and a staff draw the same spells and nothing the bow wears.
	{"key": "spell_damage", "name": "Ember Thread", "group": "spell",
		"slots": ["main", "off", "head", "chest", "hands", "legs", "feet"],
		"values": [0.04, 0.07, 0.10, 0.15, 0.20], "unit": "pct",
		"tags": ["spell", "offence"],
		"note": "Scales the staff's spells, never an arrow."},
	# --- armour ------------------------------------------------------------
	{"key": "guard", "name": "Case-Hardened", "group": "armour", "values": [0.01, 0.02, 0.03, 0.05, 0.07],
		"unit": "pct", "tags": ["defence"],
		"note": "Added to the channel figure and clamped at 0.60 with the set."},
	{"key": "health", "name": "Sewn Doubling", "group": "armour", "values": [8.0, 12.0, 18.0, 25.0, 35.0],
		"unit": "flat", "tags": ["defence"]},
	{"key": "stamina", "name": "Iron Constitution", "group": "armour", "values": [40.0, 70.0, 100.0, 150.0, 200.0],
		"unit": "flat", "tags": ["defence", "sustain"]},
	{"key": "stamina_regen", "name": "Knitted Gait", "group": "armour", "values": [0.05, 0.10, 0.15, 0.20, 0.30],
		"unit": "pct", "tags": ["sustain"]},
	{"key": "move_speed", "name": "Long Stride", "group": "armour", "values": [0.02, 0.04, 0.06, 0.08, 0.12],
		"unit": "pct", "tags": ["mobility"]},
	{"key": "attack_speed", "name": "Quick Knuckles", "group": "armour", "values": [0.03, 0.05, 0.07, 0.10, 0.15],
		"unit": "pct", "tags": ["offence", "tempo"]},
	{"key": "stagger", "name": "Braced", "group": "armour", "values": [0.05, 0.10, 0.15, 0.20, 0.30],
		"unit": "pct", "tags": ["defence"],
		"note": "Shortens the recoil, not the save roll."},
	{"key": "cooldown", "name": "Warden's Pendulum", "group": "armour", "values": [0.03, 0.05, 0.08, 0.12, 0.18],
		"unit": "pct", "tags": ["tempo", "ability"]},
	{"key": "gold_find", "name": "Warden's Mark", "group": "armour", "values": [0.05, 0.10, 0.20, 0.30, 0.50],
		"unit": "pct", "tags": ["utility"]},
	{"key": "heal_on_kill", "name": "Blooded Padding", "group": "armour", "values": [2.0, 3.0, 5.0, 8.0, 12.0],
		"unit": "flat", "tags": ["sustain"]},
	{"key": "stamina_on_kill", "name": "Dead Weight", "group": "armour", "values": [5.0, 10.0, 20.0, 35.0, 50.0],
		"unit": "flat", "tags": ["sustain"]},
	# The two aggressive armour ladders. Leather's own is the ranged one; mail
	# and plate may carry either, and the class table decides how much of the
	# pool each of them takes.
	{"key": "ranged_damage", "name": "Far Eye", "group": "armour", "values": [0.03, 0.05, 0.08, 0.12, 0.15],
		"unit": "pct", "tags": ["ranged", "offence"]},
	{"key": "melee_damage", "name": "Honed Gauntlet", "group": "armour", "values": [0.03, 0.05, 0.08, 0.12, 0.15],
		"unit": "pct", "tags": ["melee", "offence"]},
]

## The amulet's own ladders. An amulet is the trinket that carries a body's
## numbers, so the cord is the one piece with a broad stat pool: ten keys, five
## rungs each, neck-only (`slots`), and every figure sits under the kit ceiling in
## `AnnointLedger.CEILINGS` so a top rung plus the piece's own stats never reaches
## a clamp that silently does nothing.
const JEWEL_FAMILIES := [
	{"key": "health", "name": "Heartstone", "group": "jewelry", "slots": ["neck"],
		"values": [6.0, 10.0, 14.0, 20.0, 30.0], "unit": "flat", "tags": ["defence"]},
	{"key": "stamina", "name": "Bellows Bead", "group": "jewelry", "slots": ["neck"],
		"values": [40.0, 70.0, 100.0, 150.0, 200.0], "unit": "flat",
		"tags": ["defence", "sustain"]},
	{"key": "stamina_regen", "name": "Steady Pulse", "group": "jewelry", "slots": ["neck"],
		"values": [0.05, 0.10, 0.15, 0.20, 0.30], "unit": "pct", "tags": ["sustain"]},
	{"key": "melee_damage", "name": "Wolf Fang", "group": "jewelry", "slots": ["neck"],
		"values": [0.03, 0.05, 0.08, 0.12, 0.18], "unit": "pct",
		"tags": ["offence", "melee"]},
	{"key": "ranged_damage", "name": "Far Eye", "group": "jewelry", "slots": ["neck"],
		"values": [0.03, 0.05, 0.08, 0.12, 0.18], "unit": "pct",
		"tags": ["offence", "ranged"]},
	{"key": "cooldown", "name": "Hastened Rite", "group": "jewelry", "slots": ["neck"],
		"values": [0.03, 0.05, 0.08, 0.12, 0.18], "unit": "pct",
		"tags": ["tempo", "ability"]},
	{"key": "gold_find", "name": "Miser's Knot", "group": "jewelry", "slots": ["neck"],
		"values": [0.05, 0.10, 0.20, 0.30, 0.50], "unit": "pct", "tags": ["utility"]},
	{"key": "stagger", "name": "Stout Cord", "group": "jewelry", "slots": ["neck"],
		"values": [0.05, 0.10, 0.15, 0.20, 0.30], "unit": "pct", "tags": ["defence"],
		"note": "Shortens the recoil, not the save roll."},
	{"key": "heal_on_kill", "name": "Red Bead", "group": "jewelry", "slots": ["neck"],
		"values": [2.0, 3.0, 5.0, 8.0, 12.0], "unit": "flat", "tags": ["sustain"]},
	{"key": "stamina_on_kill", "name": "Killer's Breath", "group": "jewelry", "slots": ["neck"],
		"values": [5.0, 10.0, 20.0, 35.0, 50.0], "unit": "flat",
		"tags": ["sustain", "tempo"]},
]

## Authored modifiers. Every row is a small, literal bundle: stats, or one proc
## the runtime already owns. `wired=false` rows are the pool's backlog - they are
## listed so the sheet and the code agree, and they never reach a player.
const NAMES := [
	# --- weapons: stat bundles --------------------------------------------
	{"id": "w_quick_string", "name": "Quick String", "groups": ["bow"],
		"stats": {"attack_speed": 0.25}, "drawback": {"ranged_damage": -0.15},
		"line": "+25% draw speed, -15% damage", "tags": ["ranged", "tempo"], "power": 0.55},
	{"id": "w_heavy_head", "name": "Heavy Head", "groups": ["bow"],
		"stats": {"ranged_damage": 0.20}, "drawback": {"attack_speed": -0.10},
		"line": "+20% arrow damage, slower arrows", "tags": ["ranged", "offence"], "power": 0.6},
	{"id": "w_light_hand", "name": "Light Hand", "groups": ["melee"],
		"stats": {"attack_speed": 0.20}, "drawback": {"melee_damage": -0.10},
		"line": "+20% swing speed, -10% damage", "tags": ["melee", "tempo"], "power": 0.55},
	{"id": "w_cleaving_weight", "name": "Cleaving Weight", "groups": ["two_hand"],
		"stats": {"melee_damage": 0.30}, "drawback": {"attack_speed": -0.20},
		"line": "+30% damage, +25% swing time", "tags": ["melee", "offence"], "power": 0.75},
	{"id": "w_grip_ash", "name": "Grip of Ash", "groups": ["weapon"],
		"stats": {"attack_speed": 0.06}, "drawback": {"melee_damage": -0.04},
		"line": "+6% attack speed, -4% damage", "tags": ["offence", "tempo"], "power": 0.3},
	{"id": "w_trigger_finger", "name": "Trigger Finger", "groups": ["weapon"],
		"stats": {"attack_speed": 0.06, "ranged_damage": 0.04},
		"line": "+6% attack speed, +4% ranged damage", "tags": ["offence", "ranged"], "power": 0.4},
	{"id": "w_bone_knuckles", "name": "Bone Knuckles", "groups": ["melee"],
		"stats": {"melee_damage": 0.06}, "line": "+6% melee damage",
		"tags": ["melee", "offence"], "power": 0.3},
	{"id": "w_cheap_guard", "name": "Cheap Guard", "groups": ["melee"],
		"stats": {"guard": 0.02}, "line": "+2% guard while the blade is up",
		"tags": ["defence"], "power": 0.25},
	{"id": "w_iron_constitution", "name": "Iron Constitution", "groups": ["weapon"],
		"stats": {"health": 8.0, "stamina": 40.0},
		"line": "+8 health, +40 stamina", "tags": ["defence"], "power": 0.35},
	# The class bundles. A blade's flat cut, an arrow's heavy head, and the
	# dagger's own quiet trade - each names its own group, so a class that does
	# not want it never sees it in its pool.
	{"id": "w_honed_edge", "name": "Honed Edge", "groups": ["sword"],
		"stats": {"flat_melee": 4.0, "melee_damage": 0.05},
		"line": "+4 blade damage, +5% melee damage", "tags": ["melee", "offence"], "power": 0.55},
	{"id": "w_broadhead", "name": "Barbed Broadhead", "groups": ["bow"],
		"stats": {"flat_ranged": 4.0, "ranged_damage": 0.04},
		"line": "+4 arrow damage, +4% ranged damage", "tags": ["ranged", "offence"], "power": 0.55},
	{"id": "w_quiet_step", "name": "Quiet Step", "groups": ["dagger"],
		"stats": {"move_speed": 0.06, "attack_speed": 0.05},
		"line": "+6% move, +5% attack speed", "tags": ["mobility", "tempo"], "power": 0.5},
	{"id": "w_needle_point", "name": "Needle Point", "groups": ["dagger"],
		"stats": {"melee_damage": 0.10}, "drawback": {"stamina_regen": -0.06},
		"line": "+10% dagger damage, -6% stamina regen",
		"tags": ["melee", "offence"], "power": 0.5},

	# --- weapons: procs ----------------------------------------------------
	{"id": "w_thirst_hit", "name": "Leech", "groups": ["weapon"], "kind": "proc",
		"trigger": "damage_taken", "proc": "heal", "chance": 0.12, "magnitude": 4.0,
		"line": "12% on being hit: heal 4", "tags": ["sustain"], "power": 0.4,
		"note": "Bearer-side by design - the receiver is the only place a landed blow is known."},
	{"id": "w_ward_grip", "name": "Warded Grip", "groups": ["two_hand"], "kind": "proc",
		"trigger": "damage_taken", "proc": "absorb", "scale": 0.40, "cooldown": 8.0,
		"line": "First blow each 8 s is reduced 40%", "tags": ["defence"], "power": 0.6},
	{"id": "w_undercut", "name": "Undercut", "groups": ["dagger"], "kind": "proc",
		"trigger": "block", "proc": "guard_break", "chance": 0.20,
		"line": "20% when you block: drop the attacker's guard", "tags": ["control"], "power": 0.5},
	{"id": "w_bleed_edge", "name": "Whetstone Edge", "groups": ["melee"], "kind": "proc",
		"trigger": "damage_taken", "proc": "bleed", "chance": 0.15, "magnitude": 2.0, "duration": 3.0,
		"line": "15% on being hit: the attacker bleeds 2/s for 3 s", "tags": ["control"], "power": 0.45},

	# --- jewellery: the necklace's own three words --------------------------
	# Neck only, and each one is a different shape of the same idea: the cord
	# changes what a blow does. Quick Hit and Poison Hit are attack-side procs
	# (`Trigger.HIT`), Three Strike is a welded skill.
	{"id": "j_quick_hit", "name": "Quick Hit", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "proc", "trigger": "hit", "proc": "quick_strike",
		"chance": 0.20, "scale": 5.0,
		"line": "20% on a landed blade hit: strike again at 500% attack speed",
		"tags": ["melee", "offence", "tempo"], "power": 0.78,
		"note": "Blades only - there is no quick second draw for a bow."},
	{"id": "j_poison_hit", "name": "Poison Hit", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "proc", "trigger": "hit", "proc": "poison",
		"chance": 0.20, "magnitude": 5.0, "duration": 5.0,
		"line": "20% on hit: 5 damage a second poison for 5 s",
		"tags": ["offence", "control"], "power": 0.72},
	{"id": "k_three_strike", "name": "Dual Wield Three Strike", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "ability", "ability": "three_strike",
		"line": "three waves of steel, up to three bodies each",
		"tags": ["melee", "offence"], "power": 0.8},
	{"id": "k_stone_skin", "name": "Stone Skin", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "ability", "ability": "stone_skin",
		"line": "a short ward that pays a third of each blow in stamina",
		"tags": ["defence"], "power": 0.72,
		"note": "Any hand can perform it: the cord, not the steel, is the ward."},
	# The amulet's bundles. A cord buys a number and pays for it somewhere a
	# player can see on the card.
	{"id": "j_greedy_cord", "name": "Miser's Locket", "groups": ["jewelry"],
		"slots": ["neck"], "stats": {"gold_find": 0.30}, "drawback": {"ranged_damage": -0.08},
		"line": "+30% gold from kills, -8% ranged damage",
		"tags": ["utility"], "power": 0.5},
	{"id": "j_blood_cord", "name": "Blood Cord", "groups": ["jewelry"],
		"slots": ["neck"], "stats": {"melee_damage": 0.12}, "drawback": {"stamina": -40.0},
		"line": "+12% melee damage, -40 stamina",
		"tags": ["offence", "melee"], "power": 0.55},
	{"id": "j_long_breath", "name": "Long Breath", "groups": ["jewelry"],
		"slots": ["neck"], "stats": {"stamina_regen": 0.20}, "drawback": {"health": -6.0},
		"line": "+20% stamina regen, -6 health",
		"tags": ["sustain"], "power": 0.45},
	# --- the amulet's procs -------------------------------------------------
	# `LIFESTEAL` is the one verb here that reads the blow rather than the body:
	# a share of the damage the bearer deals comes back as health.
	{"id": "j_blood_thirst", "name": "Bloodthirst", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "proc", "trigger": "hit", "proc": "lifesteal",
		"chance": 0.25, "scale": 0.15,
		"line": "25% on a landed hit: 15% of that damage returns as health",
		"tags": ["sustain", "offence"], "power": 0.65},
	{"id": "j_ward_bead", "name": "Ward Bead", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "proc", "trigger": "damage_taken",
		"proc": "absorb", "scale": 0.18, "cooldown": 7.0,
		"line": "first blow each 7 s is reduced 18%",
		"tags": ["defence"], "power": 0.5},
	{"id": "j_cinder_surge", "name": "Cinder Surge", "groups": ["jewelry"],
		"slots": ["neck"], "kind": "proc", "trigger": "damage_taken",
		"proc": "reflect", "chance": 0.12, "scale": 0.22,
		"line": "12% on being hit: return 22% of the blow",
		"tags": ["defence", "offence"], "power": 0.55},

	# --- armour: stat bundles ---------------------------------------------
	{"id": "a_second_skin", "name": "Second Skin", "slots": ["chest", "legs"],
		"stats": {"health": 10.0}, "drawback": {"move_speed": -0.05},
		"line": "+10 health, -5% move", "tags": ["defence"], "power": 0.4},
	{"id": "a_iron_seams", "name": "Iron Seams", "stats": {"health": 8.0, "guard": 0.01},
		"line": "+8 health, +1% guard", "tags": ["defence"], "power": 0.35},
	{"id": "a_warded_stitch", "name": "Warded Stitch", "stats": {"guard": 0.02, "stamina_regen": 0.06},
		"line": "+2% guard, +6% stamina regen", "tags": ["defence", "sustain"], "power": 0.35},
	{"id": "a_bone_lattice", "name": "Bone Lattice Corset", "slots": ["chest"],
		"stats": {"guard": 0.05}, "drawback": {"move_speed": -0.03},
		"line": "+5% guard, -3% move", "tags": ["defence"], "power": 0.55},
	{"id": "a_padded_thighs", "name": "Padded Thighs", "slots": ["legs"],
		"stats": {"guard": 0.02, "move_speed": 0.03},
		"line": "+2% guard, +3% move", "tags": ["defence", "mobility"], "power": 0.35},
	{"id": "a_hobnails", "name": "Hobnails", "slots": ["feet"],
		"stats": {"move_speed": 0.06, "guard": 0.02},
		"line": "+6% move, +2% guard", "tags": ["mobility", "defence"], "power": 0.45},
	{"id": "a_bracer_plates", "name": "Bracer Plates", "slots": ["hands"],
		"stats": {"guard": 0.02, "stamina": 15.0},
		"line": "+2% guard, +15 stamina", "tags": ["defence"], "power": 0.3},
	{"id": "a_deep_chest", "name": "Deep Chest", "slots": ["chest"],
		"stats": {"stamina_regen": 0.20}, "line": "+20% stamina regen",
		"tags": ["sustain"], "power": 0.5},
	{"id": "a_keen_sight", "name": "Keen Sight", "slots": ["head"],
		"stats": {"ranged_damage": 0.10}, "line": "+10% ranged damage",
		"tags": ["ranged", "offence"], "power": 0.5},
	{"id": "a_helmed_focus", "name": "Helmed Focus", "slots": ["head"],
		"stats": {"melee_damage": 0.05, "ranged_damage": 0.05},
		"line": "+5% melee and ranged damage", "tags": ["offence"], "power": 0.4},
	{"id": "a_rosined_palm", "name": "Rosined Palm", "slots": ["hands"],
		"stats": {"melee_damage": 0.08}, "line": "+8% melee damage",
		"tags": ["melee", "offence"], "power": 0.45},
	{"id": "a_casting_glove", "name": "Casting Glove", "slots": ["hands"],
		"stats": {"cooldown": 0.08}, "line": "-8% skill cooldowns",
		"tags": ["tempo", "ability"], "power": 0.4},
	{"id": "a_binder_straps", "name": "Binder Straps", "slots": ["legs", "feet"],
		"stats": {"stamina_regen": 0.06}, "line": "+6% stamina regen",
		"tags": ["sustain"], "power": 0.3},
	{"id": "a_rag_wraps", "name": "Rag Wraps", "slots": ["feet"],
		"stats": {"stamina_regen": 0.10}, "line": "+10% stamina regen",
		"tags": ["sustain"], "power": 0.45},

	# --- armour: procs ----------------------------------------------------
	{"id": "a_bone_rivets", "name": "Bone Rivets", "kind": "proc",
		"trigger": "damage_taken", "proc": "stamina", "chance": 0.08, "magnitude": 15.0,
		"line": "8% on being hit: regain 15 stamina", "tags": ["sustain"], "power": 0.35},
	{"id": "a_return_fire", "name": "Return Fire", "slots": ["chest", "head"], "kind": "proc",
		"trigger": "damage_taken", "proc": "reflect", "chance": 0.10, "scale": 0.25,
		"line": "10% on being hit: return 25% of the blow", "tags": ["defence"], "power": 0.5},
	{"id": "a_iron_retort", "name": "Iron Retort", "slots": ["chest"], "kind": "proc",
		"trigger": "block", "proc": "stagger", "chance": 0.15, "magnitude": 0.6,
		"line": "15% on a block: stagger the attacker 0.6 s", "tags": ["defence", "control"], "power": 0.55},
	{"id": "a_sanguine_board", "name": "Sanguine Board", "slots": ["chest"], "kind": "proc",
		"trigger": "block", "proc": "heal", "every": 3, "magnitude": 6.0,
		"line": "Every 3rd block: heal 6", "tags": ["defence", "sustain"], "power": 0.55},
	{"id": "a_second_heart", "name": "Second Heart", "slots": ["chest"], "kind": "proc",
		"trigger": "lethal", "proc": "lethal_save", "cooldown": 60.0,
		"line": "Once per 60 s, a killing blow leaves you at 1 health",
		"tags": ["defence"], "power": 0.9},
	{"id": "a_snap_stitching", "name": "Snap Stitching", "kind": "proc",
		"trigger": "damage_taken", "proc": "absorb", "scale": 0.20, "cooldown": 10.0,
		"line": "First blow each 10 s is reduced 20%", "tags": ["defence"], "power": 0.45},
	{"id": "a_gristle", "name": "Gristle", "kind": "proc",
		"trigger": "damage_taken", "proc": "absorb", "scale": 0.06,
		"line": "-6% damage while under 30% health", "tags": ["defence"], "power": 0.35,
		"wired": false, "note": "Needs a conditional multiplier on the incoming path; not wired yet."},
	{"id": "a_cinder_lining", "name": "Cinder Lining", "kind": "proc",
		"trigger": "damage_taken", "proc": "absorb", "scale": 0.25,
		"line": "-25% damage from burns and bleeds", "tags": ["defence"], "power": 0.35,
		"wired": false, "note": "DoT-typed incoming only; the source tag does not exist yet."},

	# --- cloth: the robe's own words --------------------------------------
	# A robe buys spells and the casting that pays for them, and nothing else.
	# No movement, no attack speed, no damage reduction: the class table in
	# `POLICY` enforces that even against the armour ladders above.
	{"id": "c_ash_body", "name": "Ashen Body", "groups": ["cloth"],
		"stats": {"spell_damage": 0.08}, "drawback": {"stamina_regen": -0.06},
		"line": "+8% spell damage, -6% stamina regen", "tags": ["spell", "offence"], "power": 0.5},
	{"id": "c_quickened_rite", "name": "Quickened Rite", "groups": ["cloth"],
		"stats": {"cooldown": 0.10}, "drawback": {"stamina_regen": -0.05},
		"line": "-10% skill cooldowns, -5% stamina regen",
		"tags": ["spell", "tempo", "ability"], "power": 0.45},
	{"id": "c_bonfire_hem", "name": "Bonfire Hem", "groups": ["cloth"],
		"stats": {"spell_damage": 0.06, "stamina_regen": 0.08},
		"line": "+6% spell damage, +8% stamina regen",
		"tags": ["spell", "sustain"], "power": 0.45},
	{"id": "c_star_chart", "name": "Star Chart", "groups": ["cloth"],
		"stats": {"spell_damage": 0.04, "cooldown": 0.06},
		"line": "+4% spell damage, -6% skill cooldowns",
		"tags": ["spell", "tempo"], "power": 0.4},
	{"id": "c_live_stitch", "name": "Live Stitch", "groups": ["cloth"],
		"stats": {"spell_damage": 0.12}, "drawback": {"stamina_regen": -0.08},
		"line": "+12% spell damage, -8% stamina regen",
		"tags": ["spell", "offence"], "power": 0.65},

	# --- shields and focuses: the off hand's own words ---------------------
	{"id": "o_banded", "name": "Banded", "groups": ["shield"],
		"stats": {"guard": 0.04}, "line": "+4% guard", "tags": ["defence"], "power": 0.45},
	{"id": "o_wide_boss", "name": "Wide Boss", "groups": ["shield"],
		"stats": {"stamina": 60.0}, "line": "+60 stamina", "tags": ["defence", "sustain"], "power": 0.45},
	{"id": "o_bulwark", "name": "Bulwark", "stats": {"guard": 0.03, "health": 12.0},
		"line": "+3% guard, +12 health", "tags": ["defence"], "power": 0.4},
	{"id": "o_spiked_rim", "name": "Spiked Rim", "groups": ["shield"],
		"stats": {"melee_damage": 0.06}, "line": "+6% shield damage",
		"tags": ["offence", "melee"], "power": 0.4},
	{"id": "o_quiet_words", "name": "Quiet Words", "groups": ["focus"],
		"stats": {"spell_damage": 0.08}, "line": "+8% spell damage",
		"tags": ["spell", "offence"], "power": 0.5},
	{"id": "o_bone_lattice", "name": "Bone Lattice", "groups": ["focus"],
		"stats": {"stagger": 0.15}, "line": "-15% stagger time",
		"tags": ["defence"], "power": 0.4},
	{"id": "o_grim_page", "name": "Grim Page", "groups": ["focus"],
		"stats": {"stamina_on_kill": 15.0}, "line": "+15 stamina per kill",
		"tags": ["sustain"], "power": 0.35},
	{"id": "o_skullward", "name": "Skullward", "groups": ["focus"],
		"stats": {"health": 12.0}, "line": "+12 health", "tags": ["defence"], "power": 0.4},
	{"id": "o_copper_ward", "name": "Copper Ward", "groups": ["focus"], "kind": "proc",
		"trigger": "damage_taken", "proc": "absorb", "scale": 0.10, "cooldown": 6.0,
		"line": "First blow each 6 s is reduced 10%", "tags": ["defence"], "power": 0.4},

	# --- abilities: the skills the altar can weld ---------------------------
	# Every id here must exist in `AbilityRules`; the registry drops the entry
	# otherwise, so a skill can be declared before it is written.
	{"id": "k_barrage", "name": "Barrage", "kind": "ability", "groups": ["bow"],
		"ability": "barrage", "line": "six half-damage arrows in a spread",
		"tags": ["ranged", "offence"], "power": 0.7},
	{"id": "k_triple_volley", "name": "Triple Fan Volley", "kind": "ability", "groups": ["bow"],
		"ability": "triple_volley", "line": "three arrows fanned wide",
		"tags": ["ranged", "offence"], "power": 0.6},
	{"id": "k_piercing_shot", "name": "Piercing Shot", "kind": "ability", "groups": ["bow"],
		"ability": "piercing_shot", "line": "double damage through three bodies",
		"tags": ["ranged", "offence"], "power": 0.7},
	{"id": "k_rain_of_ash", "name": "Rain of Ash", "kind": "ability", "groups": ["bow"],
		"ability": "rain_of_ash", "line": "eight arrows into a patch of ground",
		"tags": ["ranged", "offence"], "power": 0.8},
	{"id": "k_skewer", "name": "Skewer", "kind": "ability", "groups": ["bow"],
		"ability": "skewer", "line": "one shaft through three bodies",
		"tags": ["ranged", "offence"], "power": 0.65},
	{"id": "k_double_slash", "name": "Double Slash", "kind": "ability", "groups": ["sword"],
		"ability": "double_slash", "line": "two fast cuts across the front arc",
		"tags": ["melee", "offence"], "power": 0.6},
	{"id": "k_lunge_thrust", "name": "Lunging Thrust", "kind": "ability", "groups": ["sword"],
		"ability": "lunge_thrust", "line": "a committed step and a point",
		"tags": ["melee", "offence", "mobility"], "power": 0.65},
	{"id": "k_butchers_cut", "name": "Butcher's Cut", "kind": "ability", "groups": ["sword"],
		"ability": "butchers_cut", "line": "a hooked cut through the front arc",
		"tags": ["melee", "control"], "power": 0.6},
	{"id": "k_gut_hook", "name": "Gut Hook", "kind": "ability", "groups": ["sword"],
		"ability": "gut_hook", "line": "one narrow, heavy cut",
		"tags": ["melee", "offence"], "power": 0.6},
	{"id": "k_backstab", "name": "Backstab", "kind": "ability", "groups": ["dagger"],
		"ability": "backstab", "line": "blink behind the target and stab for double",
		"tags": ["melee", "offence"], "power": 0.8},
	{"id": "k_knife_work", "name": "Knife Work", "kind": "ability", "groups": ["dagger"],
		"ability": "knife_work", "line": "three fast stabs",
		"tags": ["melee", "offence"], "power": 0.55},
	{"id": "k_spin_slash", "name": "Whirling Steel", "kind": "ability", "groups": ["two_hand"],
		"ability": "spin_slash", "line": "a full ring around the body",
		"tags": ["melee", "offence"], "power": 0.7},
	{"id": "k_ground_breaker", "name": "Ground Breaker", "kind": "ability", "groups": ["two_hand"],
		"ability": "ground_breaker", "line": "a 3 m slam that staggers everything",
		"tags": ["melee", "control"], "power": 0.8},
	{"id": "k_wide_sweep", "name": "Wide Sweep", "kind": "ability", "groups": ["two_hand"],
		"ability": "wide_sweep", "line": "a 220 degree arc",
		"tags": ["melee", "offence"], "power": 0.6},
	{"id": "k_executioner", "name": "Executioner", "kind": "ability", "groups": ["two_hand"],
		"ability": "executioner", "line": "a 2.2x overhead",
		"tags": ["melee", "offence"], "power": 0.75},
	{"id": "k_fireball", "name": "Fireball", "kind": "ability", "groups": ["staff"],
		"ability": "fireball", "line": "a blast at the aim point",
		"tags": ["ranged", "offence"], "power": 0.7},
	{"id": "k_bone_spear", "name": "Bone Spear", "kind": "ability", "groups": ["staff"],
		"ability": "bone_spear", "line": "a spear of bone through three bodies",
		"tags": ["ranged", "offence"], "power": 0.7},
	{"id": "k_cinder_lance", "name": "Cinder Lance", "kind": "ability", "groups": ["staff"],
		"ability": "cinder_lance", "line": "a fast lance that pierces four",
		"tags": ["ranged", "offence"], "power": 0.75},
	{"id": "k_grave_bloom", "name": "Grave Bloom", "kind": "ability", "groups": ["staff"],
		"ability": "grave_bloom", "line": "a 4 m bloom where it lands",
		"tags": ["ranged", "offence"], "power": 0.7},
	{"id": "k_ember_ward", "name": "Ember Ward", "kind": "ability", "groups": ["staff"],
		"ability": "ember_ward", "line": "a 6 s ward paid in stamina",
		"tags": ["defence"], "power": 0.6},
	{"id": "k_shield_bash", "name": "Shield Bash", "kind": "ability", "groups": ["shield"],
		"ability": "shield_bash", "line": "the boss into the front arc",
		"tags": ["defence", "control"], "power": 0.6},
	{"id": "k_shield_charge", "name": "Shield Charge", "kind": "ability", "groups": ["shield"],
		"ability": "shield_charge", "line": "a running shoulder into a stagger",
		"tags": ["defence", "control", "mobility"], "power": 0.65},
	{"id": "k_shield_slam", "name": "Shield Slam", "kind": "ability", "groups": ["shield"],
		"ability": "shield_slam", "line": "a ring of force off the board",
		"tags": ["defence", "offence"], "power": 0.7},
	{"id": "k_rebuke", "name": "Rebuke", "kind": "ability", "groups": ["shield"],
		"ability": "rebuke", "line": "the rim comes round",
		"tags": ["defence", "control"], "power": 0.55},
]


# --- registry --------------------------------------------------------------

static var _entries: Array[Entry] = []
static var _by_id: Dictionary = {}
static var _built := false
## The applicability answer per (groups, slots), built once. `for_item` is asked
## on every repaint of the altar's rack, the item card and every hover, and the
## filter walks the whole registry each time: the class rules are pure, so the
## pool is cached and handed out as a copy (the entries themselves never change).
static var _pools: Dictionary = {}


static func _build() -> void:
	if _built:
		return
	_built = true
	for family in FAMILIES:
		_build_family(family)
	for family in JEWEL_FAMILIES:
		_build_family(family)
	for row in NAMES:
		_build_named(row)
	# An ability entry can only be wired when the rules table knows the skill.
	for entry in _entries:
		if entry.kind == Kind.ABILITY and not entry.ability.is_empty():
			var known := not AbilityRules.by_id(entry.ability).is_empty()
			entry.wired = entry.wired and known
	for entry in _entries:
		_by_id[entry.id] = entry


static func _build_family(family: Dictionary) -> void:
	var group := str(family.get("group", GROUP_ARMOUR))
	var values: Array = family.get("values", [])
	var rungs := mini(values.size(), ROMAN.size())
	for index in rungs:
		var value := float(values[index])
		var entry := Entry.new()
		entry.kind = Kind.STAT
		entry.id = "f_%s_%s_%d" % [group, str(family["key"]), index + 1]
		entry.name = "%s %s" % [str(family["name"]), ROMAN[index]]
		entry.stats = {str(family["key"]): value}
		entry.line = _format(str(family["unit"]), value, str(family["key"]))
		entry.note = str(family.get("note", ""))
		entry.tags = _tags(family.get("tags", []))
		entry.power = 0.18 + 0.18 * float(index)
		var declared: Array = family.get("slots", [])
		if not declared.is_empty():
			# A ladder that names its slot owns exactly that slot: the amulet's
			# numbers belong on a cord and nowhere else.
			entry.groups = [group]
			for slot in declared:
				entry.slots.append(str(slot))
		elif group == GROUP_ARMOUR:
			entry.groups = [GROUP_ARMOUR]
			entry.slots = ARMOUR_SLOTS.duplicate()
		elif group == "weapon":
			entry.groups = [GROUP_ANY_WEAPON]
			entry.slots = [SLOT_MAIN, SLOT_OFF]
		else:
			entry.groups = [group]
			entry.slots = [SLOT_MAIN, SLOT_OFF]
		_entries.append(entry)


static func _build_named(row: Dictionary) -> void:
	var entry := Entry.new()
	entry.id = str(row.get("id", ""))
	entry.name = str(row.get("name", entry.id))
	entry.kind = _kind_of(str(row.get("kind", "stat")))
	entry.wired = bool(row.get("wired", true))
	entry.line = str(row.get("line", ""))
	entry.note = str(row.get("note", ""))
	entry.tags = _tags(row.get("tags", []))
	entry.power = float(row.get("power", 0.5))
	entry.stats = (row.get("stats", {}) as Dictionary).duplicate()
	entry.drawback = (row.get("drawback", {}) as Dictionary).duplicate()
	entry.ability = str(row.get("ability", ""))
	var groups: Array = row.get("groups", [])
	if groups.is_empty():
		entry.groups = [GROUP_ARMOUR]
	else:
		for group in groups:
			entry.groups.append(str(group))
	var slots: Array = row.get("slots", [])
	if slots.is_empty():
		# An armour row with no slot named fits every armour slot; a weapon row
		# with no group named would have fallen through to armour above.
		entry.slots = ARMOUR_SLOTS.duplicate() if groups.is_empty() else [SLOT_MAIN, SLOT_OFF]
	else:
		for slot in slots:
			entry.slots.append(str(slot))
	if entry.kind == Kind.PROC:
		entry.trigger = _trigger_of(str(row.get("trigger", "damage_taken")))
		entry.proc = _proc_of(str(row.get("proc", "heal")))
		entry.chance = float(row.get("chance", 1.0))
		entry.every = int(row.get("every", 0))
		entry.magnitude = float(row.get("magnitude", 0.0))
		entry.scale = float(row.get("scale", 0.0))
		entry.duration = float(row.get("duration", 0.0))
		entry.cooldown = float(row.get("cooldown", 0.0))
	_entries.append(entry)


static func _kind_of(word: String) -> int:
	match word:
		"proc":
			return Kind.PROC
		"ability":
			return Kind.ABILITY
	return Kind.STAT


static func _trigger_of(word: String) -> int:
	match word:
		"block":
			return Trigger.BLOCK
		"parry":
			return Trigger.PARRY
		"lethal":
			return Trigger.LETHAL
		"kill":
			return Trigger.KILL
		"hit":
			return Trigger.HIT
	return Trigger.DAMAGE_TAKEN


static func _proc_of(word: String) -> int:
	match word:
		"stamina":
			return Proc.STAMINA
		"reflect":
			return Proc.REFLECT
		"absorb":
			return Proc.ABSORB
		"lethal_save":
			return Proc.LETHAL_SAVE
		"stagger":
			return Proc.STAGGER
		"guard_break":
			return Proc.GUARD_BREAK
		"bleed":
			return Proc.BLEED
		"quick_strike":
			return Proc.QUICK_STRIKE
		"poison":
			return Proc.POISON
		"lifesteal":
			return Proc.LIFESTEAL
	return Proc.HEAL


static func _tags(source: Variant) -> Array[String]:
	var out: Array[String] = []
	if source is Array:
		for tag in source:
			out.append(str(tag))
	return out


## Card text for one rung. Percentages carry a sign; flat pools do not.
static func _format(unit: String, value: float, key: String) -> String:
	var shown := ("+%d%%" % int(round(value * 100.0))) if unit == "pct" else ("+%d" % int(round(value)))
	match key:
		"guard":
			return "%s guard" % shown
		"cooldown":
			return "%s skill cooldown" % shown
		"stagger":
			return "%s stagger time" % shown
		"move_speed":
			return "%s move speed" % shown
		"stamina_regen":
			return "%s stamina regen" % shown
		"heal_on_kill":
			return "%s health per kill" % shown
		"stamina_on_kill":
			return "%s stamina per kill" % shown
		"attack_speed":
			return "%s attack speed" % shown
		"throw_damage":
			return "%s throw damage" % shown
		"spell_damage":
			return "%s spell damage" % shown
		"flat_melee":
			return "%s blade damage" % shown
		"flat_ranged":
			return "%s arrow damage" % shown
	return "%s %s" % [shown, key.replace("_", " ")]


# --- queries ---------------------------------------------------------------

static func all() -> Array[Entry]:
	_build()
	return _entries


static func by_id(id: String) -> Entry:
	_build()
	return _by_id.get(id, null) as Entry


## The material a worn armour piece is made of, `""` when it is not armour or
## the piece does not name a set. The catalogue carries the set index; a caller
## that only holds a slot asks for a material by name in `for_armour_slot`.
static func material_of(item: Dictionary) -> String:
	if str(item.get("category", "")) != "armor":
		return ""
	var index := int(item.get("set", -1))
	if index < 0 or index >= ArmorData.SET_IDS.size():
		return ""
	return str(ArmorData.SET_IDS[index])


## The gear groups an item resolves to. Armour answers `armour` plus its
## material, and the materials are what the class table keys on: a robe is
## `armour` + `cloth` + `spell`, a mail shirt `armour` + `mail`.
static func groups_of(item: Dictionary) -> Array:
	var out: Array = []
	if item.is_empty():
		return out
	var category := str(item.get("category", ""))
	var kind := str(item.get("kind", ""))
	match category:
		"bow":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_BOW)
			out.append(GROUP_RANGED)
		"staff":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_STAFF)
			out.append(GROUP_SPELL)
		"shield":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_SHIELD)
			# "Anything but an arrow": a board may carry a spell's own bonus.
			out.append(GROUP_SPELL)
		"focus":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_FOCUS)
			out.append(GROUP_SPELL)
		"1h", "2h":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_MELEE)
			if kind == "dagger":
				# A dagger is its own class: it shares the melee channel with a
				# sword and nothing else, and the class table does the rest.
				out.append(GROUP_DAGGER)
			else:
				# Every sword, including the greatsword: a two-hander is a
				# sword first and a two-handed weapon second.
				out.append(GROUP_SWORD)
				if category == "2h":
					out.append(GROUP_TWO_HAND)
		"armor":
			out.append(GROUP_ARMOUR)
			var material := material_of(item)
			if not material.is_empty():
				out.append(material)
				if material == GROUP_CLOTH:
					out.append(GROUP_SPELL)
		"jewelry":
			out.append(GROUP_JEWELRY)
	return out


## Which worn slots an item can occupy. A one-hander fits either hand.
static func slots_of(item: Dictionary) -> Array:
	var out: Array[String] = []
	var category := str(item.get("category", ""))
	match category:
		"bow", "staff", "2h":
			out.append(SLOT_MAIN)
		"shield", "focus":
			out.append(SLOT_OFF)
		"1h":
			out.append(SLOT_MAIN)
			out.append(SLOT_OFF)
		"armor":
			var slot := str(item.get("slot", ""))
			if ARMOUR_SLOTS.has(slot):
				out.append(slot)
		"jewelry":
			# The catalog says "ring" because one row fits either finger; the
			# worn slot is where it actually sits.
			match str(item.get("slot", "")):
				"neck":
					out.append("neck")
				"ring":
					out.append("ring1")
					out.append("ring2")
	return out


## Every entry that may be welded to this item, wired ones only, stable order.
## Pure in the item's class (`groups_of` + `slots_of`), so the answer is cached
## and copied out: the rack asks for the same pool once per copy on every press.
static func for_item(item: Dictionary) -> Array[Entry]:
	var out: Array[Entry] = []
	if item.is_empty():
		return out
	var groups := groups_of(item)
	var slots := slots_of(item)
	if groups.is_empty() or slots.is_empty():
		return out
	var key := "%s|%s" % [",".join(PackedStringArray(groups)),
		",".join(PackedStringArray(slots))]
	var cached: Variant = _pools.get(key)
	if cached is Array:
		for entry in cached:
			out.append(entry)
		return out
	for entry in all():
		if entry.wired and entry.fits(groups, slots) and admits(entry, groups):
			out.append(entry)
	_pools[key] = out.duplicate()
	return out


## Whether the item's class rules allow this entry at all. Every stat key the
## entry writes - and every key its drawback writes - must be one the class
## names, and a proc's verb must be one the class arms. Abilities are gated by
## their own `groups`, which already name the implement they belong to.
static func admits(entry: Entry, item_groups: Array) -> bool:
	if entry == null:
		return false
	for group in item_groups:
		if not POLICY.has(group):
			continue
		var policy: Dictionary = POLICY[group]
		var keys: Array = policy.get("keys", [])
		for key in entry.stats:
			if not keys.has(str(key)):
				return false
		for key in entry.drawback:
			if not keys.has(str(key)):
				return false
		if int(entry.kind) == Kind.PROC:
			var procs: Array = policy.get("procs", [])
			if not procs.has(int(entry.proc)):
				return false
	return true


## The families an entry writes, in the order it writes them. A proc is read by
## its verb, a stat bundle by its keys.
static func families_of(entry: Entry) -> Array[String]:
	var out: Array[String] = []
	if entry == null:
		return out
	for key in entry.stats:
		var family := str(FAMILY_OF_KEY.get(str(key), "utility"))
		if not out.has(family):
			out.append(family)
	for key in entry.drawback:
		var family := str(FAMILY_OF_KEY.get(str(key), "utility"))
		if not out.has(family):
			out.append(family)
	if int(entry.kind) == Kind.PROC:
		var family := str(FAMILY_OF_PROC.get(int(entry.proc), "defence"))
		if not out.has(family):
			out.append(family)
	return out


## How likely this entry is to be drawn for an item of these groups. 1.0 is a
## class's own bread; 0.4 is the "sometimes" a design sheet writes in words.
## The rarest family an entry writes decides: a bundle is only as common as its
## least typical ingredient.
static func weight_of(entry: Entry, item_groups: Array) -> float:
	if entry == null:
		return 1.0
	var weight := 1.0
	var families := families_of(entry)
	for group in item_groups:
		if not POLICY.has(group):
			continue
		var weights: Dictionary = POLICY[group].get("weights", {})
		for family in families:
			weight = minf(weight, float(weights.get(family, 1.0)))
	return weight


## The four forged materials. These are the pieces the altar works at any price:
## the price of a jerkin is the wood's, and the material is the whole of what it
## can carry. Salvage hide and a bare shirt are not gear worth a vial.
const FORGED_MATERIALS := [GROUP_LEATHER, GROUP_MAIL, GROUP_PLATE, GROUP_CLOTH]


## Whether the altar takes this piece at all, before its pool is asked.
static func workable(item: Dictionary) -> bool:
	return FORGED_MATERIALS.has(material_of(item))


## The armour pool for a worn slot ("head", "chest", ...). `material` names the
## set - `leather`, `mail`, `plate`, `cloth`, `makeshift`, `naked` - and an empty
## material answers the slot's generic pool, which is what a caller with no piece
## in hand should see.
static func for_armour_slot(slot: String, material: String = "") -> Array[Entry]:
	var out: Array[Entry] = []
	if not ARMOUR_SLOTS.has(slot):
		return out
	var item := {"category": "armor", "slot": slot}
	var index := ArmorData.SET_IDS.find(material)
	if index >= 0:
		item["set"] = index
	return for_item(item)


static func abilities_of(pool: Array[Entry]) -> Array[Entry]:
	var out: Array[Entry] = []
	for entry in pool:
		if entry.kind == Kind.ABILITY:
			out.append(entry)
	return out


static func passives_of(pool: Array[Entry]) -> Array[Entry]:
	var out: Array[Entry] = []
	for entry in pool:
		if entry.kind != Kind.ABILITY:
			out.append(entry)
	return out


# --- aggregation -----------------------------------------------------------

## Fold one entry's deltas into a `TrinketStats`-shaped dictionary in place.
## Stats are additive across pieces; the ladders are why a body can reach +18%
## attack speed from one rung and +33% across two pieces, which the kit ceilings
## in `AnnointLedger.CEILINGS` then clamp.
static func apply_entry(target: Dictionary, entry: Entry, sign: float = 1.0) -> void:
	if entry == null:
		return
	for key in entry.stats:
		target[str(key)] = float(target.get(str(key), 0.0)) + float(entry.stats[key]) * sign
	for key in entry.drawback:
		target[str(key)] = float(target.get(str(key), 0.0)) + float(entry.drawback[key]) * sign
