class_name CruorCatalog
extends RefCounted
## Sacramental Cruor: the five-tier ritual essence table and its pure arithmetic.
##
## Tier 1 (Ritual Tallow) is scavenged by unbinding spare magic items; five units
## of a tier distil into one of the next, so 625 Tier 1 renders a single relic
## Tier 5. Only the table and the maths live here, so the altar UI, the Crucible
## manager and the regression test cannot disagree about a name, a colour or a
## ratio. Nothing here mutates anything.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## `id` is the save/wire key, `name` the display name, `short` the chip caption,
## `value` a gold-equivalent used to sort the stash rows, `color` the rim tint.
const TIERS := {
	Contracts.CruorTier.T1_RITUAL_TALLOW: {
		"id": "cruor_t1", "name": "Ritual Tallow", "short": "Tallow",
		"value": 10, "color": Color(0.82, 0.76, 0.58, 1.0),
		"note": "Gutter-fat and prayer, rendered down.",
	},
	Contracts.CruorTier.T2_BLACK_BILE: {
		"id": "cruor_t2", "name": "Black Bile", "short": "Bile",
		"value": 55, "color": Color(0.35, 0.45, 0.30, 1.0),
		"note": "What a body keeps when the soul is spent.",
	},
	Contracts.CruorTier.T3_COAGULATED_CRUOR: {
		"id": "cruor_t3", "name": "Coagulated Cruor", "short": "Cruor",
		"value": 290, "color": Color(0.62, 0.14, 0.16, 1.0),
		"note": "Thick, warm, and it never quite stops moving.",
	},
	Contracts.CruorTier.T4_STIGMATIC_RESIN: {
		"id": "cruor_t4", "name": "Stigmatic Resin", "short": "Resin",
		"value": 1500, "color": Color(0.48, 0.22, 0.66, 1.0),
		"note": "It burns inward. The wound stays open and lights the room.",
	},
	Contracts.CruorTier.T5_CRYSTALLIZED_SIN: {
		"id": "cruor_t5", "name": "Crystallized Sin", "short": "Sin",
		"value": 8000, "color": Color(0.95, 0.85, 0.45, 1.0),
		"note": "A relic. You can hear it thinking.",
	},
}

const TIER_ORDER: Array[int] = [
	Contracts.CruorTier.T1_RITUAL_TALLOW,
	Contracts.CruorTier.T2_BLACK_BILE,
	Contracts.CruorTier.T3_COAGULATED_CRUOR,
	Contracts.CruorTier.T4_STIGMATIC_RESIN,
	Contracts.CruorTier.T5_CRYSTALLIZED_SIN,
]

static func tiers() -> Array[int]:
	return TIER_ORDER.duplicate()

static func is_tier(tier: int) -> bool:
	return TIERS.has(tier)

static func tier_name(tier: int) -> String:
	return str(TIERS.get(tier, {}).get("name", "Cruor"))

static func tier_short(tier: int) -> String:
	return str(TIERS.get(tier, {}).get("short", "Cruor"))

static func tier_id(tier: int) -> String:
	return str(TIERS.get(tier, {}).get("id", ""))

static func tier_from_id(id: String) -> int:
	for tier in TIERS:
		if str(TIERS[tier].get("id", "")) == id:
			return tier
	return -1

static func tier_value(tier: int) -> int:
	return int(TIERS.get(tier, {}).get("value", 0))

static func tier_color(tier: int) -> Color:
	var value: Variant = TIERS.get(tier, {}).get("color", Color.WHITE)
	return value if value is Color else Color.WHITE

static func tier_note(tier: int) -> String:
	return str(TIERS.get(tier, {}).get("note", ""))

## One distil step: `CRUOR_DISTILL_RATIO` units of `tier` become one of the
## next tier. Returns `{ok, spent, output_tier, output_count, message}`; the
## top tier cannot be distilled further.
static func distill(tier: int, count: int) -> Dictionary:
	var ratio := Contracts.CRUOR_DISTILL_RATIO
	if not is_tier(tier):
		return {"ok": false, "spent": 0, "output_tier": -1, "output_count": 0,
			"message": "That is not ritual essence."}
	if tier >= Contracts.CruorTier.T5_CRYSTALLIZED_SIN:
		return {"ok": false, "spent": 0, "output_tier": -1, "output_count": 0,
			"message": "%s is the last tier. It does not distil." % tier_name(tier)}
	var batches := int(count) / ratio
	if batches <= 0:
		return {"ok": false, "spent": 0, "output_tier": tier + 1, "output_count": 0,
			"message": "Distilling %d into %s needs %d." % [tier, tier_name(tier + 1), ratio]}
	return {"ok": true, "spent": batches * ratio, "output_tier": tier + 1,
		"output_count": batches,
		"message": "Distilled %d x %s into %d x %s." % [
			batches * ratio, tier_name(tier), batches, tier_name(tier + 1)]}

## How the given one-step batch count reads in the altar: 5 -> 1, 0 -> nothing.
static func distill_preview(tier: int, count: int) -> Dictionary:
	return distill(tier, count)

## Unbinding a spare magic item renders it into Tier 1-3 essence. The yield is a
## pure function of the item's gold price so the altar and the loot table agree:
##   * Tier 1 = max(1, round(price / 20))    - every magic item gives tallow
##   * Tier 2 = floor(price / 150)           - ordinary enchanted steel
##   * Tier 3 = floor(price / 400)           - the expensive pieces only
## Returns `{tier: count}` with empty tiers omitted.
static func unbind_yield(price: int) -> Dictionary:
	var cost := maxi(0, price)
	var rendered := {}
	var t1 := maxi(1, int(round(float(cost) / 20.0)))
	if t1 > 0:
		rendered[Contracts.CruorTier.T1_RITUAL_TALLOW] = t1
	var t2 := cost / 150
	if t2 > 0:
		rendered[Contracts.CruorTier.T2_BLACK_BILE] = t2
	var t3 := cost / 400
	if t3 > 0:
		rendered[Contracts.CruorTier.T3_COAGULATED_CRUOR] = t3
	return rendered

## The same yield as a readable line: "3 Ritual Tallow, 1 Black Bile".
static func yield_text(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for tier in TIER_ORDER:
		if amounts.has(tier) and int(amounts[tier]) > 0:
			parts.append("%d %s" % [int(amounts[tier]), tier_name(tier)])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "nothing"
