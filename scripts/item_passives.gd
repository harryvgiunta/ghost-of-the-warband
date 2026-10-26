extends RefCounted
## Weapon passives: the bonus a weapon grants while a hand is actually swinging
## it. One table, one aggregation, the same shape as `TrinketStats`, so a new
## passive only needs a row here and its tooltip text in `PlayerState.ITEMS`.
##
## Rows are keyed by weapon class (`dagger`, `sword`, `staff`, `bow`) because
## that is the level the game and the wire already share: every dagger fights on
## the one `Archer.DAGGER_DATA` profile and only its mesh skin changes, and a
## replica learns `weapon`/`off_weapon_kind` from the snapshot. Keying by
## catalog id would need a new replicated field and would leave a remote
## fighter's dagger swinging at the wrong speed.
##
## Rate keys are additive fractions on one melee variant's attack rate, the same
## convention `TrinketStats.attack_speed` uses: `2.0` is +200%, so the dagger's
## 0.5 s forward stab resolves to `0.5 / (1 + 2.0) = 0.1667 s`. A row speeds the
## variant it names and nothing else, so a dagger's wheel-down swing keeps its
## own timing.
##
## This script is a leaf on purpose: `PlayerState` preloads it to render the
## tooltip rows, and it never preloads the catalog back.

## Melee variant → the row key that speeds it. A variant absent from this map
## has no passive vocabulary yet; add its key here and in `PASSIVES` together.
## `stab` is the wheel-up forward lunge, `diagonal_*` the left-mouse cuts and
## `overhead` the wheel-down chop.
const VARIANT_KEYS := {"stab": "stab_speed"}

## Swings compound: trinket haste multiplies with a row. The ceiling keeps a
## shortened stab long enough to present its strike window, which is what the
## rig samples at `Archer.MELEE_SAMPLE_SECONDS`.
const MAX_RATE := 8.0

const PASSIVES := {
	# The dagger's wheel-up lunge becomes a shanking: three stabs fit in the
	# time one used to take, while the wheel-down chop keeps the base 0.5 s.
	"dagger": {"name": "Prison shank", "stab_speed": 2.0},
}


static func definition(weapon_class: String) -> Dictionary:
	return PASSIVES.get(weapon_class, {})


static func has_passives(weapon_class: String) -> bool:
	return PASSIVES.has(weapon_class)


## Additive attack-rate bonus this class grants the named melee variant, or 0.0
## when the weapon is inert for that variant.
static func variant_bonus(weapon_class: String, variant: String) -> float:
	var row := definition(weapon_class)
	var key := str(VARIANT_KEYS.get(variant, ""))
	if row.is_empty() or key.is_empty():
		return 0.0
	return maxf(0.0, float(row.get(key, 0.0)))


## Rate multiplier for one variant; `1.0` when the weapon grants nothing.
static func variant_rate(weapon_class: String, variant: String) -> float:
	return clampf(1.0 + variant_bonus(weapon_class, variant), 1.0, MAX_RATE)


## Label/value rows for the item tooltip. `base_seconds` is the catalog's own
## attack time for the variant, so the row can advertise the resolved time
## (`+300%  /  0.13 s`) without this table owning any weapon profile.
static func effect_rows(weapon_class: String, base_seconds: float = 0.0) -> Array:
	var row := definition(weapon_class)
	var rows: Array = []
	if row.is_empty():
		return rows
	var name := str(row.get("name", ""))
	if not name.is_empty():
		rows.append({"label": "PASSIVE", "value": name})
	var stab := float(row.get("stab_speed", 0.0))
	if stab > 0.0:
		var value := "+%d%%" % int(round(stab * 100.0))
		if base_seconds > 0.0:
			value += "  /  %.2f s" % (base_seconds / variant_rate(weapon_class, "stab"))
		rows.append({"label": "FORWARD STAB", "value": value})
	return rows


## Compact form for the inspector's meta line.
static func effect_summary(weapon_class: String) -> String:
	var row := definition(weapon_class)
	if row.is_empty():
		return ""
	var parts := PackedStringArray()
	var name := str(row.get("name", ""))
	if not name.is_empty():
		parts.append(name.to_upper())
	var stab := float(row.get("stab_speed", 0.0))
	if stab > 0.0:
		parts.append("STAB +%d%%" % int(round(stab * 100.0)))
	return "  •  ".join(parts)
