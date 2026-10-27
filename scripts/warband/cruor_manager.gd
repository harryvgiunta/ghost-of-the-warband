class_name WarbandCruor
extends RefCounted
## Sacramental Cruor: the ritual essence wallet, the unbinding, the distilling and
## the brands themselves.
##
## Three verbs, one ledger:
##   * unbind  - destroy a spare magic item on the altar -> Tier 1..3 essence;
##   * distil  - 5 of tier N -> 1 of tier N+1 (625 T1 renders one Tier 5);
##   * brand   - spend essence to burn a sigil onto a weapon, bow, skull or tome,
##               granting its active ability or rerolling the one already there.
##
## Brands are item properties keyed by catalog id, so they survive the piece
## moving between mercenaries and the stash. The essence counts and the brand map
## are the only saved state.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")

## Essence burned per brand by the tier used. The higher tiers buy the same
## sigil more cheaply, which is what makes distilling worth doing.
const BRAND_COSTS := {
	Contracts.CruorTier.T1_RITUAL_TALLOW: 5,
	Contracts.CruorTier.T2_BLACK_BILE: 3,
	Contracts.CruorTier.T3_COAGULATED_CRUOR: 2,
	Contracts.CruorTier.T4_STIGMATIC_RESIN: 1,
	Contracts.CruorTier.T5_CRYSTALLIZED_SIN: 1,
}

## Anything cheaper than this is plain junk and cannot be rendered down: the
## altar only eats gear that was worth carrying.
const MAGIC_PRICE := 40

var counts: Dictionary = {}
var brands: Dictionary = {}   # item_id -> {tier, ability, rerolls}

func _init() -> void:
	clear()

func clear() -> void:
	counts = {}
	for tier in Catalog.TIER_ORDER:
		counts[tier] = 0
	brands = {}

# --- wallet ----------------------------------------------------------------

func tier_count(tier: int) -> int:
	return int(counts.get(tier, 0))

func add(tier: int, amount: int) -> int:
	if not Catalog.is_tier(tier) or amount <= 0:
		return tier_count(tier)
	counts[tier] = tier_count(tier) + amount
	return int(counts[tier])

func spend(tier: int, amount: int) -> bool:
	var have := tier_count(tier)
	if amount <= 0 or have < amount:
		return false
	counts[tier] = have - amount
	return true

func total() -> int:
	var sum := 0
	for tier in counts:
		sum += int(counts[tier])
	return sum

## `[{"tier","name","short","count","value"}]` in tier order, for the altar rail.
func wallet_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tier in Catalog.TIER_ORDER:
		rows.append({"tier": tier, "name": Catalog.tier_name(tier),
			"short": Catalog.tier_short(tier), "count": tier_count(tier),
			"value": Catalog.tier_value(tier), "color": Catalog.tier_color(tier)})
	return rows

# --- unbinding -------------------------------------------------------------

## Whether the altar can render this item down: a real piece of gear, worth
## keeping in the first place, held in the shared pool rather than worn.
func can_unbind(stash: WarbandStash, item_id: String) -> bool:
	if stash == null or stash.pooled_count(item_id) <= 0:
		return false
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty() or not str(item.get("category", "")) in State_equippable_categories():
		return false
	return int(item.get("price", 0)) >= MAGIC_PRICE

## Static helper so the rule reads the same everywhere.
static func State_equippable_categories() -> Array:
	return ["1h", "2h", "bow", "staff", "shield", "focus", "armor", "jewelry"]

## Destroy one pooled copy into Tier 1..3 essence.
## Returns `{ok, message, item_id, yield, spent}`.
func unbind(stash: WarbandStash, item_id: String) -> Dictionary:
	if stash == null or item_id.is_empty():
		return {"ok": false, "message": "Choose a spare item.", "item_id": item_id, "yield": {}, "spent": false}
	if not can_unbind(stash, item_id):
		return {"ok": false, "message": "The altar will not take that.", "item_id": item_id, "yield": {}, "spent": false}
	if not stash.remove(item_id, 1):
		return {"ok": false, "message": "That item is not in the stash.", "item_id": item_id, "yield": {}, "spent": false}
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var rendered := Catalog.unbind_yield(int(item.get("price", 0)))
	for tier in rendered:
		add(int(tier), int(rendered[tier]))
	brands.erase(item_id)
	return {"ok": true, "yield": rendered, "item_id": item_id, "spent": true,
		"message": "Unbound %s into %s." % [str(item.get("name", item_id)), Catalog.yield_text(rendered)]}

# --- distilling ------------------------------------------------------------

## One batch: 5 x tier -> 1 x tier+1. There is no partial distilling.
func distill(tier: int) -> Dictionary:
	if not Catalog.is_tier(tier):
		return {"ok": false, "spent": 0, "output_tier": -1, "output_count": 0,
			"message": "That is not ritual essence."}
	if tier >= Contracts.CruorTier.T5_CRYSTALLIZED_SIN:
		return {"ok": false, "spent": 0, "output_tier": -1, "output_count": 0,
			"message": "%s is the last tier. It does not distil." % Catalog.tier_name(tier)}
	var ratio := Contracts.CRUOR_DISTILL_RATIO
	if tier_count(tier) < ratio:
		return {"ok": false, "spent": 0, "output_tier": tier + 1, "output_count": 0,
			"message": "Distilling %s needs %d." % [Catalog.tier_name(tier), ratio]}
	spend(tier, ratio)
	add(tier + 1, 1)
	return {"ok": true, "spent": ratio, "output_tier": tier + 1, "output_count": 1,
		"message": "Distilled %d x %s into 1 x %s." % [
			ratio, Catalog.tier_name(tier), Catalog.tier_name(tier + 1)]}

## Every whole batch this tier can make, in one click.
func distill_all(tier: int) -> Dictionary:
	var result := Catalog.distill(tier, tier_count(tier))
	if not bool(result["ok"]):
		return result
	spend(tier, int(result["spent"]))
	add(int(result["output_tier"]), int(result["output_count"]))
	return result

# --- branding --------------------------------------------------------------

func brand_cost(tier: int) -> int:
	return int(BRAND_COSTS.get(tier, 0))

static func brandable_item(item_id: String) -> bool:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return false
	return Branded.can_brand_subtype(Contracts.weapon_subtype(item))

## `{ok, message, ability, tier, reroll}` for the altar preview.
func can_brand(item_id: String, tier: int) -> Dictionary:
	if not brandable_item(item_id):
		return {"ok": false, "message": "Only steel, bows, staves, skulls and tomes take a brand."}
	if not Catalog.is_tier(tier):
		return {"ok": false, "message": "Choose an essence tier."}
	var cost := brand_cost(tier)
	if tier_count(tier) < cost:
		return {"ok": false, "message": "%s needs %d %s." % [
			Catalog.tier_name(tier), cost, Catalog.tier_name(tier)]}
	var ability := Branded.for_subtype(Contracts.weapon_subtype(State.ITEMS[item_id]))
	if ability.is_empty():
		return {"ok": false, "message": "That piece cannot hold a sigil."}
	return {"ok": true, "message": Branded.tier_line(ability, tier), "ability": ability}

## Burn essence into a piece. Branding plain steel grants its ability; branding
## an already-branded piece rerolls the sigil at the new tier.
func brand(item_id: String, tier: int) -> Dictionary:
	var check := can_brand(item_id, tier)
	if not bool(check["ok"]):
		return {"ok": false, "message": str(check["message"]), "ability": "", "tier": tier, "reroll": false}
	var cost := brand_cost(tier)
	if not spend(tier, cost):
		return {"ok": false, "message": "Not enough essence.", "ability": "", "tier": tier, "reroll": false}
	var previous: Dictionary = brand_of(item_id)
	var ability := str(check["ability"])
	var rerolls := int(previous.get("rerolls", 0)) + (1 if not previous.is_empty() else 0)
	brands[item_id] = {"tier": tier, "ability": ability, "rerolls": rerolls}
	var item_name := str(State.ITEMS.get(item_id, {}).get("name", item_id))
	var verb := "Rebranded" if not previous.is_empty() else "Branded"
	return {"ok": true, "ability": ability, "tier": tier, "reroll": not previous.is_empty(),
		"message": "%s %s with %s (%s)." % [verb, item_name,
			Catalog.tier_name(tier), Branded.ability_name(ability)]}

func brand_of(item_id: String) -> Dictionary:
	var payload: Variant = brands.get(item_id, {})
	return payload if payload is Dictionary else {}

func is_branded(item_id: String) -> bool:
	return brands.has(item_id)

## The tooltip line for a branded piece, or "" for plain steel.
func brand_line(item_id: String) -> String:
	var payload := brand_of(item_id)
	if payload.is_empty():
		return ""
	return Branded.tier_line(str(payload.get("ability", "")), int(payload.get("tier", 0)))

## Every branded item, value-first, for the altar's "already branded" list.
func branded_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item_id in brands:
		var payload := brand_of(item_id)
		var item: Dictionary = State.ITEMS.get(item_id, {})
		rows.append({"item_id": str(item_id), "name": str(item.get("name", item_id)),
			"tier": int(payload.get("tier", 0)),
			"ability": str(payload.get("ability", "")),
			"line": Branded.tier_line(str(payload.get("ability", "")), int(payload.get("tier", 0))),
			"rerolls": int(payload.get("rerolls", 0))})
	rows.sort_custom(func(a, b): return int(a["tier"]) > int(b["tier"]))
	return rows

# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	var saved_counts := {}
	for tier in counts:
		saved_counts[str(int(tier))] = int(counts[tier])
	var saved_brands := {}
	for item_id in brands:
		saved_brands[str(item_id)] = brand_of(str(item_id)).duplicate(true)
	return {"counts": saved_counts, "brands": saved_brands}

func from_dict(data: Dictionary) -> void:
	clear()
	var saved_counts: Variant = data.get("counts", {})
	if saved_counts is Dictionary:
		for key in saved_counts:
			var tier := int(str(key))
			if Catalog.is_tier(tier):
				counts[tier] = maxi(0, int(saved_counts[key]))
	var saved_brands: Variant = data.get("brands", {})
	if saved_brands is Dictionary:
		for item_id in saved_brands:
			var payload: Variant = saved_brands[item_id]
			if payload is Dictionary:
				brands[str(item_id)] = {"tier": int(payload.get("tier", 0)),
					"ability": str(payload.get("ability", "")),
					"rerolls": int(payload.get("rerolls", 0))}
