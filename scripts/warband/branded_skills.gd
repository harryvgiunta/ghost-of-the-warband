class_name BrandedSkills
extends RefCounted
## The brand table: what burning Sacramental Cruor onto a weapon actually grants.
##
## Phase 0 owns the identity of each ability (id, name, which item classes can
## carry it, its flavour line and how tier scales its numbers). The combat effect
## that plays when the ability fires lives in `scripts/warband/branded_runner.gd`
## and is wired into the ability pipeline; keeping the table separate means the
## altar, the item tooltip and the skill runner cannot disagree about what a
## given brand is called.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

const ABILITIES := {
	"rending_strike": {
		"name": "Rending Strike",
		"subtype": Contracts.WeaponSubType.ONE_HAND,
		"cost": 120.0,
		"cooldown": 6.0,
		"summary": "A single cut that keeps opening. Bleeds every foe it crosses.",
	},
	"shockwave_cleave": {
		"name": "Shockwave Cleave",
		"subtype": Contracts.WeaponSubType.TWO_HAND,
		"cost": 220.0,
		"cooldown": 9.0,
		"summary": "The blade lands and the ground answers. A widening ring of force.",
	},
	"arrow_barrage": {
		"name": "Rapid-Fire Arrow Barrage",
		"subtype": Contracts.WeaponSubType.BOW,
		"cost": 180.0,
		"cooldown": 8.0,
		"summary": "Six shafts loosed inside the space of one draw.",
	},
	"ember_storm": {
		"name": "Ember Storm",
		"subtype": Contracts.WeaponSubType.STAFF,
		"cost": 200.0,
		"cooldown": 8.5,
		"summary": "The staff coughs a star and the star comes apart.",
	},
	"hellfire_cone": {
		"name": "Hellfire Cone",
		"subtype": Contracts.WeaponSubType.SKULL,
		"cost": 210.0,
		"cooldown": 9.0,
		"summary": "The skull opens its jaw. Everything in front of it learns why.",
	},
	"blood_ward": {
		"name": "Blood Ritual Ward",
		"subtype": Contracts.WeaponSubType.TOME,
		"cost": 190.0,
		"cooldown": 10.0,
		"summary": "A ring of names, written in your own blood, that spends itself for you.",
	},
}

## Ability ids in altar order.
const ORDER := ["rending_strike", "shockwave_cleave", "arrow_barrage",
	"ember_storm", "hellfire_cone", "blood_ward"]

## Brandable item classes: plain steel, bows, staves, skulls and tomes. A shield
## is a board, not a vessel.
const BRANDABLE := [
	Contracts.WeaponSubType.ONE_HAND,
	Contracts.WeaponSubType.TWO_HAND,
	Contracts.WeaponSubType.BOW,
	Contracts.WeaponSubType.STAFF,
	Contracts.WeaponSubType.SKULL,
	Contracts.WeaponSubType.TOME,
]

static func can_brand_subtype(subtype: int) -> bool:
	return subtype in BRANDABLE

static func for_subtype(subtype: int) -> String:
	for ability_id in ORDER:
		if int(ABILITIES[ability_id]["subtype"]) == subtype:
			return ability_id
	return ""

static func definition(ability_id: String) -> Dictionary:
	return ABILITIES.get(ability_id, {})

static func ability_name(ability_id: String) -> String:
	return str(definition(ability_id).get("name", "Brand"))

static func summary(ability_id: String) -> String:
	return str(definition(ability_id).get("summary", ""))

static func stamina_cost(ability_id: String) -> float:
	return float(definition(ability_id).get("cost", 100.0))

static func cooldown(ability_id: String) -> float:
	return float(definition(ability_id).get("cooldown", 8.0))

## Tier 1 is a whisper; Tier 5 is a relic. One uniform curve so the skill runner,
## the tooltip and the altar show the same power number.
static func power(tier: int) -> float:
	return 1.0 + 0.35 * float(clampi(tier, 0, 4))

## Duration/radius figures scale with the same curve.
static func scaled(value: float, tier: int) -> float:
	return value * power(tier)

## The line the altar and the item card both print.
static func tier_line(ability_id: String, tier: int) -> String:
	if ability_id.is_empty():
		return "Unbranded"
	return "%s - %d%% power" % [ability_name(ability_id), int(round(power(tier) * 100.0))]
