extends RefCounted
const AbilityRules = preload("res://scripts/ability_rules.gd")

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

## When a PROC is rolled. STAT entries ignore this.
enum Trigger { DAMAGE_TAKEN, BLOCK, PARRY, LETHAL, KILL }

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
}

const SLOT_MAIN := "main"
const SLOT_OFF := "off"
const ARMOUR_SLOTS := ["head", "chest", "hands", "legs", "feet"]

## Soft cap on one piece, and the hard ceiling the ledger enforces.
const MAX_PER_PIECE := 6

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
		"stats": {"ranged_damage": 0.08}, "line": "+8% spell damage",
		"tags": ["ranged", "offence"], "power": 0.5},
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


static func _build() -> void:
	if _built:
		return
	_built = true
	for family in FAMILIES:
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
		if group == GROUP_ARMOUR:
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
	return "%s %s" % [shown, key.replace("_", " ")]


# --- queries ---------------------------------------------------------------

static func all() -> Array[Entry]:
	_build()
	return _entries


static func by_id(id: String) -> Entry:
	_build()
	return _by_id.get(id, null) as Entry


## The gear groups an item resolves to. Armour answers exactly `["armour"]`.
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
			out.append(GROUP_RANGED)
		"shield":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_SHIELD)
		"focus":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_FOCUS)
		"1h", "2h":
			out.append(GROUP_ANY_WEAPON)
			out.append(GROUP_MELEE)
			if kind == "dagger":
				out.append(GROUP_DAGGER)
			elif category == "2h":
				out.append(GROUP_TWO_HAND)
			else:
				out.append(GROUP_SWORD)
		"armor":
			out.append(GROUP_ARMOUR)
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
	return out


## Every entry that may be welded to this item, wired ones only, stable order.
static func for_item(item: Dictionary) -> Array[Entry]:
	var out: Array[Entry] = []
	if item.is_empty():
		return out
	var groups := groups_of(item)
	var slots := slots_of(item)
	if groups.is_empty() or slots.is_empty():
		return out
	for entry in all():
		if entry.wired and entry.fits(groups, slots):
			out.append(entry)
	return out


## The armour pool for a worn slot ("head", "chest", ...).
static func for_armour_slot(slot: String) -> Array[Entry]:
	var out: Array[Entry] = []
	if not ARMOUR_SLOTS.has(slot):
		return out
	var item := {"category": "armor", "slot": slot}
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
