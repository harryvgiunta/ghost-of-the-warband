class_name WarbandCruor
extends RefCounted
## Sacramental Cruor: the ritual essence wallet, the unbinding, the distilling,
## the brands, and the anointings the altar works with reagents.
##
## Four verbs, one ledger:
##   * anoint  - lay a reagent from the shared stash on a weapon or a shield so
##               it wakes into its own skill (the 1 / 2 keys); stock steel has none;
##   * unbind  - destroy a spare magic item on the altar -> Tier 1..3 essence;
##   * distil  - 5 of tier N -> 1 of tier N+1 (625 T1 renders one Tier 5);
##   * brand   - spend essence to burn a sigil onto a weapon, bow, skull or tome,
##               granting its `R` ability or rerolling the one already there.
##
## Brands and anointings are item properties keyed by catalog id, so they survive
## the piece moving between mercenaries and the stash, and every copy the warband
## owns carries them. The essence counts, the brand map and the anointed map are
## the only saved state.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

## The reagent every anointing takes for now: a warden's ichor out of the shared
## stash.
const BASIC_REAGENT := "ichor_vial"

## What waking each skill costs at the altar, `{reagent catalog id: count}`.
## Every skill takes the basic reagent for now - one warden's ichor - so this is
## the one table to balance them apart later. A skill missing here cannot be
## anointed.
const ANOINT_RECIPES := {
	"barrage": {BASIC_REAGENT: 1},
	"triple_volley": {BASIC_REAGENT: 1},
	"piercing_shot": {BASIC_REAGENT: 1},
	"double_slash": {BASIC_REAGENT: 1},
	"lunge_thrust": {BASIC_REAGENT: 1},
	"spin_slash": {BASIC_REAGENT: 1},
	"backstab": {BASIC_REAGENT: 1},
	"fireball": {BASIC_REAGENT: 1},
	"bone_spear": {BASIC_REAGENT: 1},
	"shield_bash": {BASIC_REAGENT: 1},
	"shield_charge": {BASIC_REAGENT: 1},
	"shield_slam": {BASIC_REAGENT: 1},
}

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
var anointed: Dictionary = {}   # item_id -> ability id the piece wakes into

func _init() -> void:
	clear()

func clear() -> void:
	counts = {}
	for tier in Catalog.TIER_ORDER:
		counts[tier] = 0
	brands = {}
	anointed = {}

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

# --- anointing -------------------------------------------------------------

## The skill a catalog piece wakes into at the altar, or {} for one that has none.
static func anoint_skill(item_id: String) -> Dictionary:
	return AbilityRules.skill_for(State.ITEMS.get(item_id, {}))

## The key that looses a piece's skill in the warband: 1 for the main hand, 2 for
## a shield.
static func anoint_key(item_id: String) -> String:
	return str(AbilityRules.hand_slot(State.ITEMS.get(item_id, {})) + 1)

## The reagents waking `ability_id` costs, `{catalog id: count}`; {} when the
## altar has no rite for it.
static func anoint_recipe(ability_id: String) -> Dictionary:
	var recipe: Variant = ANOINT_RECIPES.get(ability_id, {})
	return (recipe as Dictionary).duplicate() if recipe is Dictionary else {}

## "1 Warden's Ichor" - the altar row's price and the refusal's.
static func recipe_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for reagent in recipe:
		parts.append("%d %s" % [int(recipe[reagent]),
			str(State.ITEMS.get(str(reagent), {}).get("name", reagent))])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "nothing"

func is_anointed(item_id: String) -> bool:
	return anointed.has(item_id)

## The ability id an anointed piece carries, or "" for a plain one.
func anointed_skill(item_id: String) -> String:
	return str(anointed.get(item_id, ""))

## The ids in `item_ids` the altar has anointed: what a dressing hands
## `SeatLoadout.apply` so the rig carries their skills.
func anointed_among(item_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for item_id in item_ids:
		if anointed.has(str(item_id)):
			out.append(str(item_id))
	return out

## The card line for an anointed piece ("Anointed - BARRAGE [1]"), or "".
func anoint_line(item_id: String) -> String:
	var ability := anointed_skill(item_id)
	if ability.is_empty():
		return ""
	return "Anointed - %s [%s]" % [str(AbilityRules.by_id(ability).get("name", ability)),
		anoint_key(item_id)]

## `{ok, message, ability, recipe}`: whether the altar would wake this piece now.
## The piece has to be the warband's (pooled or worn - an anointing lives on the
## item, not on a body) and the shared stash has to hold the whole recipe.
func can_anoint(stash: WarbandStash, roster, item_id: String) -> Dictionary:
	var skill := anoint_skill(item_id)
	var item_name := str(State.ITEMS.get(item_id, {}).get("name", item_id))
	if skill.is_empty():
		return {"ok": false, "message": "Only a weapon or a shield wakes at the altar.",
			"ability": "", "recipe": {}}
	var ability := str(skill.get("id", ""))
	if is_anointed(item_id):
		return {"ok": false, "message": "%s already carries %s." % [item_name, str(skill.get("name", ""))],
			"ability": ability, "recipe": {}}
	if stash == null or not stash.available_ids(roster).has(item_id):
		return {"ok": false, "message": "The warband does not carry a %s." % item_name,
			"ability": ability, "recipe": {}}
	var recipe := anoint_recipe(ability)
	if recipe.is_empty():
		return {"ok": false, "message": "The altar knows no rite for %s." % str(skill.get("name", "")),
			"ability": ability, "recipe": {}}
	for reagent in recipe:
		if stash.pooled_count(str(reagent)) < int(recipe[reagent]):
			return {"ok": false, "message": "%s needs %s." % [str(skill.get("name", "")), recipe_text(recipe)],
				"ability": ability, "recipe": recipe}
	return {"ok": true, "message": "%s wakes into %s for %s." % [item_name, str(skill.get("name", "")),
		recipe_text(recipe)], "ability": ability, "recipe": recipe}

## Lay the recipe's reagents on a piece: they leave the shared stash and every
## copy of the piece the warband owns wakes into its skill. Returns `{ok, message,
## item_id, ability, spent}`, `spent` being the `{reagent: count}` that left.
func anoint(stash: WarbandStash, roster, item_id: String) -> Dictionary:
	var check := can_anoint(stash, roster, item_id)
	var ability := str(check.get("ability", ""))
	if not bool(check.get("ok", false)):
		return {"ok": false, "message": str(check.get("message", "")), "item_id": item_id,
			"ability": ability, "spent": {}}
	var recipe: Dictionary = check["recipe"]
	for reagent in recipe:
		stash.remove(str(reagent), int(recipe[reagent]))
	anointed[item_id] = ability
	var item_name := str(State.ITEMS.get(item_id, {}).get("name", item_id))
	return {"ok": true, "item_id": item_id, "ability": ability, "spent": recipe,
		"message": "%s wakes into %s. Key %s looses it." % [item_name,
			str(AbilityRules.by_id(ability).get("name", ability)), anoint_key(item_id)]}

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
	return {"counts": saved_counts, "brands": saved_brands, "anointed": anointed.duplicate()}

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
	# An anointing is re-derived from today's table rather than trusted: a piece
	# that no longer wakes into anything drops out, and one whose skill was
	# re-tabled carries the skill it has now.
	var saved_anointed: Variant = data.get("anointed", {})
	if saved_anointed is Dictionary:
		for item_id in saved_anointed:
			var restored := State.migrate_item_id(str(item_id))
			var skill := anoint_skill(restored)
			if not skill.is_empty():
				anointed[restored] = str(skill.get("id", ""))
