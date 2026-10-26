extends RefCounted
## Trinket modifiers: necklaces, rings and the off-hand skull foci.
##
## One table, one aggregation. Every controller derives the whole kit's
## bonuses from the equipped ids, so a new trinket only needs an entry here and
## a catalog row in `PlayerState.ITEMS`. Nothing in this file touches a scene.
##
## Fractions are additive multipliers on the base value (`0.10` is +10%);
## `health` and `stamina` are flat additions; `heal_on_kill` and
## `stamina_on_kill` are flat refills on a kill.

const SLOTS := ["neck", "ring1", "ring2", "off"]

const DEFAULT := {
	"health": 0.0,
	"stamina": 0.0,
	"melee_damage": 0.0,
	"ranged_damage": 0.0,
	"throw_damage": 0.0,
	"move_speed": 0.0,
	"attack_speed": 0.0,
	"guard": 0.0,
	"stamina_regen": 0.0,
	"stagger": 0.0,
	"gold_find": 0.0,
	"cooldown": 0.0,
	"heal_on_kill": 0.0,
	"stamina_on_kill": 0.0,
}

## The guard a trinket can add on top of the armor sets. Armor alone clamps at
## `ArmorData.MAX_REDUCTION`; the trinket ceiling leaves room for both.
const GUARD_CAP := 0.60

const STATS := {
	# Neck
	"neck_shield": {},
	# Off hand
	"focus_skull_life": {"heal_on_kill":15.0},
	"focus_skull_death": {"stamina_on_kill":15.0},
	# Rings
	"ring_dash": {},
	"ring_health": {"health":25.0},
	"ring_ranged": {"ranged_damage":0.10},
	"ring_melee": {"melee_damage":0.10},
	"ring_swift": {"move_speed":0.08},
	"ring_haste": {"attack_speed":0.12},
	"ring_vigor": {"stamina":150.0},
	"ring_tide": {"stamina_regen":0.30},
	"ring_ward": {"guard":0.06},
	"ring_grit": {"stagger":0.25},
	"ring_bounty": {"gold_find":0.25},
	"ring_thrower": {"throw_damage":0.25},
	"ring_echo": {"cooldown":0.15},
	"ring_ironhide": {"health":20.0, "guard":0.02},
}

## Trinkets that grant a skill in the amulet (third) ability slot. The neck
## wins over the rings, then ring 1 over ring 2, so a kit always resolves the
## same slot deterministically. `AbilityRules` owns the definitions.
const ABILITY_ORDER := ["neck", "ring1", "ring2"]
const ABILITY_GRANTS := {
	"neck_shield": "energy_shield",
	"ring_dash": "dash",
}


static func definition(id: String) -> Dictionary:
	return STATS.get(id, {})


static func has_stats(id: String) -> bool:
	return STATS.has(id)


## Aggregate every equipped trinket. Unknown ids and empty slots contribute
## nothing, so a stale save or a malformed wire kit cannot invent bonuses.
static func sum(trinkets: Dictionary) -> Dictionary:
	var total := DEFAULT.duplicate()
	for slot in SLOTS:
		var id := str(trinkets.get(slot, ""))
		var stats := definition(id)
		if stats.is_empty():
			continue
		for key in stats:
			if not total.has(key):
				total[key] = 0.0
			total[key] = float(total[key]) + float(stats[key])
	return total


## Convenience for callers that hold the whole ten-slot paperdoll.
static func for_equipped(equipped: Dictionary) -> Dictionary:
	var trinkets := {}
	for slot in SLOTS:
		trinkets[slot] = str(equipped.get(slot, ""))
	return sum(trinkets)


## The equipped ids that matter, in the same shape `sum` accepts.
static func kit(equipped: Dictionary) -> Dictionary:
	var trinkets := {}
	for slot in SLOTS:
		trinkets[slot] = str(equipped.get(slot, ""))
	return trinkets


## The trinket item that owns the amulet ability slot, or "" when the kit
## grants none. `AbilityRules` maps the id to its definition.
static func ability_item(trinkets: Dictionary) -> String:
	for slot in ABILITY_ORDER:
		var id := str(trinkets.get(slot, ""))
		if ABILITY_GRANTS.has(id):
			return id
	return ""


static func grant_for(id: String) -> String:
	return str(ABILITY_GRANTS.get(id, ""))


static func max_health(base: float, stats: Dictionary) -> float:
	return maxf(1.0, base + float(stats.get("health", 0.0)))


static func max_stamina(base: float, stats: Dictionary) -> float:
	return maxf(1.0, base + float(stats.get("stamina", 0.0)))


static func damage_scale(stats: Dictionary, key: String) -> float:
	return maxf(0.0, 1.0 + float(stats.get(key, 0.0)))


static func move_scale(stats: Dictionary) -> float:
	return clampf(1.0 + float(stats.get("move_speed", 0.0)), 0.5, 2.0)


## Attack speed is a rate: +12% turns a 1.0 s draw into 1.0 / 1.12.
static func attack_rate(stats: Dictionary) -> float:
	return clampf(1.0 + float(stats.get("attack_speed", 0.0)), 0.5, 3.0)


static func stamina_regen(stats: Dictionary) -> float:
	return maxf(0.0, 1.0 + float(stats.get("stamina_regen", 0.0)))


static func gold_scale(stats: Dictionary) -> float:
	return maxf(0.0, 1.0 + float(stats.get("gold_find", 0.0)))


static func cooldown_scale(stats: Dictionary) -> float:
	return clampf(1.0 - float(stats.get("cooldown", 0.0)), 0.0, 1.0)


## Incoming stagger is reduced by the grit trinkets.
static func stagger_scale(stats: Dictionary) -> float:
	return clampf(1.0 - float(stats.get("stagger", 0.0)), 0.0, 1.0)


## Armor and trinkets share one damage-reduction number. Armor alone keeps its
## own 45% ceiling; the combined figure may only reach `GUARD_CAP`.
static func damage_reduction(armor_reduction: float, stats: Dictionary) -> float:
	return clampf(maxf(armor_reduction, 0.0) + float(stats.get("guard", 0.0)), 0.0, GUARD_CAP)


## Label/value rows for the paperdoll inspector and the hover card.
static func effect_rows(id: String) -> Array:
	var stats := definition(id)
	var rows: Array = []
	if stats.is_empty():
		return rows
	var health := float(stats.get("health", 0.0))
	if health > 0.0:
		rows.append({"label":"MAX HEALTH", "value":"+%d" % int(round(health))})
	var stamina := float(stats.get("stamina", 0.0))
	if stamina > 0.0:
		rows.append({"label":"MAX STAMINA", "value":"+%d" % int(round(stamina))})
	var melee := float(stats.get("melee_damage", 0.0))
	if melee > 0.0:
		rows.append({"label":"MELEE DAMAGE", "value":"+%d%%" % int(round(melee * 100.0))})
	var ranged := float(stats.get("ranged_damage", 0.0))
	if ranged > 0.0:
		rows.append({"label":"RANGED DAMAGE", "value":"+%d%%" % int(round(ranged * 100.0))})
	var thrown := float(stats.get("throw_damage", 0.0))
	if thrown > 0.0:
		rows.append({"label":"THROWN DAMAGE", "value":"+%d%%" % int(round(thrown * 100.0))})
	var move := float(stats.get("move_speed", 0.0))
	if move > 0.0:
		rows.append({"label":"MOVE SPEED", "value":"+%d%%" % int(round(move * 100.0))})
	var attack := float(stats.get("attack_speed", 0.0))
	if attack > 0.0:
		rows.append({"label":"ATTACK SPEED", "value":"+%d%%" % int(round(attack * 100.0))})
	var guard := float(stats.get("guard", 0.0))
	if guard > 0.0:
		rows.append({"label":"DAMAGE REDUCTION", "value":"+%d%%" % int(round(guard * 100.0))})
	var regen := float(stats.get("stamina_regen", 0.0))
	if regen > 0.0:
		rows.append({"label":"STAMINA REGEN", "value":"+%d%%" % int(round(regen * 100.0))})
	var stagger := float(stats.get("stagger", 0.0))
	if stagger > 0.0:
		rows.append({"label":"STAGGER SUFFERED", "value":"-%d%%" % int(round(stagger * 100.0))})
	var gold := float(stats.get("gold_find", 0.0))
	if gold > 0.0:
		rows.append({"label":"KILL GOLD", "value":"+%d%%" % int(round(gold * 100.0))})
	var cooldown := float(stats.get("cooldown", 0.0))
	if cooldown > 0.0:
		rows.append({"label":"SKILL COOLDOWN", "value":"-%d%%" % int(round(cooldown * 100.0))})
	var heal := float(stats.get("heal_on_kill", 0.0))
	if heal > 0.0:
		rows.append({"label":"ON KILL", "value":"+%d life" % int(round(heal))})
	var gain := float(stats.get("stamina_on_kill", 0.0))
	if gain > 0.0:
		rows.append({"label":"ON KILL", "value":"+%d stamina" % int(round(gain))})
	return rows


## Compact one-line form for the slot row and the inspector header.
static func effect_summary(id: String) -> String:
	var rows := effect_rows(id)
	var parts := PackedStringArray()
	for row in rows:
		parts.append("%s %s" % [str(row.label), str(row.value)])
	var grant := grant_for(id)
	if not grant.is_empty():
		parts.append("SKILL %s" % grant.replace("_", " ").to_upper())
	return "  •  ".join(parts)
