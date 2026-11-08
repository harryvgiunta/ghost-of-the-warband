extends RefCounted
## Weapon passives: the bonus a weapon grants while a hand is actually swinging
## it. One table, one aggregation, the same shape as `TrinketStats`, so a new
## passive only needs a row here and its row in `effect_rows` renders itself.
##
## Rows are keyed by weapon class (`dagger`, `sword`, `greatsword`, `blunt`,
## `axe`, `staff`, `bow`) because that is the level the game and the wire already
## share: every dagger fights on the one `Archer.DAGGER_DATA` profile and only its
## mesh skin changes, and a replica learns `weapon`/`sword_index`/`off_weapon_kind`
## from the snapshot, so `sword_class` here resolves the same class on every peer.
## Keying by catalog id would need a new replicated field and would leave a remote
## fighter's club swinging at the wrong speed.
##
## Rate keys are additive fractions on one melee variant's attack rate, the same
## convention `TrinketStats.attack_speed` uses: `2.0` is +200%, so the dagger's
## 0.5 s forward stab resolves to `0.5 / (1 + 2.0) = 0.1667 s`. A row speeds the
## variant it names and nothing else, so a dagger's wheel-down swing keeps its own
## timing and a club's diagonal cut is not the overhead.
##
## The same key names are the annointment vocabulary (`overhead_speed`,
## `overhead_damage`): a weld that names one adds its own factor beside the
## class's, exactly as trinket haste multiplies beside both.
##
## This script is a leaf on purpose: the rig (`Archer`), the combat rules, `Sfx`,
## the annointment catalog and the item card all read it, and it preloads nothing
## back - no catalog, no rig, no scene.

## Blade span index in `Archer.SWORD_DATA` of the makeshift blunt tier: the club
## at 3 and the whole tree limb at 4. Named, never a floor: the axe is a later
## profile and is edged, so `index >= 3` would class it as wood.
const BLUNT_INDEXES := [3, 4]
## The profile index of the two-handed sword, which fights as its own class: its
## second click is a cut off the first one's momentum.
const TWO_HAND_INDEX := 2
## The profile index of the makeshift axe.
const AXE_INDEX := 5

## Melee variant → the row key that speeds it. A variant absent from this map
## has no passive vocabulary yet; add its key here and in `PASSIVES` together.
## `stab` is the wheel-up forward lunge, `diagonal_*` the left-mouse cuts and
## `overhead` the wheel-down chop.
const VARIANT_KEYS := {"stab": "stab_speed", "overhead": "overhead_speed"}
## Melee variant → the weapon-side key that scales its damage. Only the heavy
## blow has a damage channel today; a cut is the base the tables author.
const VARIANT_DAMAGE_KEYS := {"overhead": "overhead_damage"}
## Card labels, in the order `effect_rows` prints them.
const VARIANT_ORDER := ["stab", "overhead"]
const VARIANT_LABELS := {"stab": "FORWARD STAB", "overhead": "OVERHEAD"}

## Swings compound: trinket haste multiplies with a row. The ceiling keeps a
## shortened stab long enough to present its strike window, which is what the
## rig samples at `Archer.MELEE_SAMPLE_SECONDS`.
const MAX_RATE := 8.0

const PASSIVES := {
	# The dagger's wheel-up lunge becomes a shanking: three stabs fit in the
	# time one used to take, while the wheel-down chop keeps the base 0.5 s and
	# drives the blade down through a body for double.
	"dagger": {"name": "Prison shank", "stab_speed": 2.0, "overhead_damage": 1.0},
	# The club's weight: a bludgeon is no quicker than a blade - its overhand is
	# the profile's own clip (the club's 0.9 s), which is already the slower of the
	# two swings it has (the sweep is `DIAGONAL_SECONDS`, 0.55 s) - and a landed
	# blow breaks a body's line where a cut of the same weight does not.
	# `stagger` is added to the receiver's own chance roll; `stagger_hold` is
	# the share longer the reaction lasts. The overhand used to be sped to twice
	# the profile's rate (0.45 s on the club, 0.3 s under Heavy Swing): a heavy
	# chop that fast read as a flick, so the class grants no rate at all.
	"blunt": {"name": "Knockabout",
		"stagger": 0.35, "stagger_hold": 0.5},
	# A greatsword is a momentum weapon: the first click loads the cut, and the
	# second one comes round 30% quicker off the weight already moving.
	"greatsword": {"name": "Rolling cut", "combo_speed": 0.30},
	# A one-handed sword answered in each hand: the pair is quicker than either
	# blade alone, and the off blade turns a quarter of what reaches the body.
	"sword": {"name": "Twin edge", "dual_speed": 0.20, "dual_block": 0.25},
	# The axe is a throwing piece. Its edge is no faster than a sword's; the
	# whole weapon is balanced to be let go of, and it lands for double.
	"axe": {"name": "Hurl", "throw_damage": 1.0},
}


## The melee class a profile index fights as. A staff is its own class (it
## reuses the greatsword index), the two-hander is its own, the makeshift blunt
## tier is blunt steel, and the axe is edged.
static func sword_class(index: int, staff_shown: bool = false) -> String:
	if staff_shown:
		return "staff"
	if index == TWO_HAND_INDEX:
		return "greatsword"
	if index == AXE_INDEX:
		return "axe"
	return "blunt" if BLUNT_INDEXES.has(index) else "sword"


static func is_blunt_index(index: int) -> bool:
	return BLUNT_INDEXES.has(index)


## The class a catalog row fights as, read off the item the way the catalog
## spells it. Empty for anything a hand does not swing (ammunition, a shield,
## a piece of armour), so a caller can gate on it.
static func class_of(item: Dictionary) -> String:
	var category := str(item.get("category", ""))
	match category:
		"bow":
			return "bow"
		"staff":
			return "staff"
		"1h", "2h":
			if str(item.get("kind", "")) == "dagger":
				return "dagger"
			return sword_class(int(item.get("index", 0)))
	return ""


static func definition(weapon_class: String) -> Dictionary:
	return PASSIVES.get(weapon_class, {})


static func has_passives(weapon_class: String) -> bool:
	return PASSIVES.has(weapon_class)


## The stats key a variant speeds through, or "" when it has no rate channel.
static func variant_key(variant: String) -> String:
	return str(VARIANT_KEYS.get(variant, ""))


## The stats key a variant scales through, or "" when it has no damage channel.
static func variant_damage_key(variant: String) -> String:
	return str(VARIANT_DAMAGE_KEYS.get(variant, ""))


static func _row_value(weapon_class: String, key: String) -> float:
	return maxf(0.0, float(definition(weapon_class).get(key, 0.0)))


## Additive attack-rate bonus this class grants the named melee variant, or 0.0
## when the weapon is inert for that variant.
static func variant_bonus(weapon_class: String, variant: String) -> float:
	var key := variant_key(variant)
	if definition(weapon_class).is_empty() or key.is_empty():
		return 0.0
	return maxf(0.0, float(definition(weapon_class).get(key, 0.0)))


## Rate multiplier for one variant; `1.0` when the weapon grants nothing.
static func variant_rate(weapon_class: String, variant: String) -> float:
	return clampf(1.0 + variant_bonus(weapon_class, variant), 1.0, MAX_RATE)


## Additive damage fraction this class grants the named variant, converted the
## way every damage key is: `1.0` is double the blow.
static func variant_damage_scale(weapon_class: String, variant: String) -> float:
	var key := variant_damage_key(variant)
	if definition(weapon_class).is_empty() or key.is_empty():
		return 1.0
	return 1.0 + maxf(0.0, float(definition(weapon_class).get(key, 0.0)))


## The rate this class's second click of a chain swings at: a greatsword's cut
## off the momentum of the first is `1.3`. `1.0` for everything else.
static func combo_rate(weapon_class: String) -> float:
	return clampf(1.0 + _row_value(weapon_class, "combo_speed"), 1.0, MAX_RATE)


## The rate a pairing of this class in both hands swings at: a matched pair of
## one-handed swords is `1.2`. `1.0` when the off hand is not the same class.
static func dual_rate(weapon_class: String, off_class: String) -> float:
	if weapon_class != off_class or definition(weapon_class).is_empty():
		return 1.0
	return clampf(1.0 + _row_value(weapon_class, "dual_speed"), 1.0, MAX_RATE)


## The share of blows a pairing of this class turns without raising a guard.
static func dual_block_chance(weapon_class: String, off_class: String) -> float:
	if weapon_class != off_class or definition(weapon_class).is_empty():
		return 0.0
	return clampf(_row_value(weapon_class, "dual_block"), 0.0, 1.0)


## The damage multiplier this class carries into a throw: an axe is `2.0`.
static func throw_scale(weapon_class: String) -> float:
	return 1.0 + _row_value(weapon_class, "throw_damage")


## Chance this class's blow adds to the receiver's own stagger roll. A blade
## adds nothing: its weight is already the damage the roll reads.
static func stagger_bonus(weapon_class: String) -> float:
	return maxf(0.0, float(definition(weapon_class).get("stagger", 0.0)))


## The share longer a stagger from this class holds the receiver standing.
static func stagger_hold(weapon_class: String) -> float:
	return maxf(0.0, float(definition(weapon_class).get("stagger_hold", 0.0)))


## Label/value rows for the item card. Percent-only on purpose: the resolved
## seconds are the rig's (`Archer.melee_seconds`), and a card that guessed the
## trinkets and welds on the body would disagree with the hand holding it.
static func effect_rows(weapon_class: String) -> Array:
	var row := definition(weapon_class)
	var rows: Array = []
	if row.is_empty():
		return rows
	var name := str(row.get("name", ""))
	if not name.is_empty():
		rows.append({"label": "PASSIVE", "value": name})
	for variant in VARIANT_ORDER:
		var bonus := float(row.get(str(VARIANT_KEYS.get(variant, "")), 0.0))
		if bonus > 0.0:
			rows.append({"label": str(VARIANT_LABELS.get(variant, variant.to_upper())),
				"value": "+%d%%" % int(round(bonus * 100.0))})
	var damage := 0.0
	for key in VARIANT_DAMAGE_KEYS.values():
		damage = maxf(damage, float(row.get(str(key), 0.0)))
	if damage > 0.0:
		rows.append({"label": "OVERHEAD DAMAGE", "value": "x%d" % int(round(1.0 + damage))})
	var combo := float(row.get("combo_speed", 0.0))
	if combo > 0.0:
		rows.append({"label": "SECOND CUT", "value": "+%d%%" % int(round(combo * 100.0))})
	var dual := float(row.get("dual_speed", 0.0))
	if dual > 0.0:
		rows.append({"label": "TWIN BLADES", "value": "+%d%% speed" % int(round(dual * 100.0))})
	var block := float(row.get("dual_block", 0.0))
	if block > 0.0:
		rows.append({"label": "TWIN GUARD", "value": "%d%% block" % int(round(block * 100.0))})
	var thrown := float(row.get("throw_damage", 0.0))
	if thrown > 0.0:
		rows.append({"label": "THROWN", "value": "x%d damage" % int(round(1.0 + thrown))})
	var stagger := float(row.get("stagger", 0.0))
	if stagger > 0.0:
		var value := "+%d%% odds" % int(round(stagger * 100.0))
		var hold := float(row.get("stagger_hold", 0.0))
		if hold > 0.0:
			value += ",  %d%% longer" % int(round(hold * 100.0))
		rows.append({"label": "STAGGER", "value": value})
	return rows
