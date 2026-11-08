class_name RogueliteModCatalog
extends RefCounted
## The mod pool the pedestals draft, the chests offer and the Greed Totems push.
##
## Every row is data. The proc engine reads `stats` and `flags`, so a new mod is
## one dictionary here and nothing else - no branch in the engine, no scene code,
## no per-mod class. Values are *per stack* unless the field names a cap; the
## engine decides whether a key stacks linearly or hyperbolically
## (`roguelite_proc_engine.gd`), and that rule is what keeps ten copies of a mod
## from being an instant win.

const RARITY_COMMON := "common"
const RARITY_EPIC := "epic"
const RARITY_LEGENDARY := "legendary"
const RARITY_GREED := "greed"
const RARITIES := [RARITY_COMMON, RARITY_EPIC, RARITY_LEGENDARY, RARITY_GREED]

const RARITY_COLOUR := {
	RARITY_COMMON: Color("cfd8c4"),
	RARITY_EPIC: Color("9fd0ff"),
	RARITY_LEGENDARY: Color("f2c862"),
	RARITY_GREED: Color("e0624f"),
}

## The whole pool. `weight` decides how often the draft sees it inside its tier.
const MODS := [
	# --- weapon mods --------------------------------------------------------
	{
		"id": "split_shot", "name": "Arc Split", "rarity": RARITY_COMMON,
		"category": "weapon", "weight": 10, "max_stacks": 6,
		"description": "Every shot looses +1 arrow in a tight fan. Arrows deal " +
"85% damage, the first one full.",
		"stats": {"split_shots": 1.0}, "flags": {"split": true},
	},
	{
		"id": "scatter_shot", "name": "Scatter Burst", "rarity": RARITY_EPIC,
		"category": "weapon", "weight": 6, "max_stacks": 5,
		"description": "20% chance (+hyperbolic) on fire to unleash a burst of " +
"three bolts at 60% damage.",
		"stats": {"scatter_chance": 0.2}, "flags": {"scatter": true},
	},
	{
		"id": "homing_bolts", "name": "Homing Bolts", "rarity": RARITY_EPIC,
		"category": "weapon", "weight": 6, "max_stacks": 4,
		"description": "Projectiles curve toward the nearest valid enemy inside " +
"the aim cone. Each stack turns harder.",
		"stats": {"homing": 1.0}, "flags": {},
	},
	{
		"id": "ricochet", "name": "Ricochet", "rarity": RARITY_EPIC,
		"category": "weapon", "weight": 6, "max_stacks": 5,
		"description": "A projectile that lands bounces to +1 more enemy within " +
"12 m at 90% damage.",
		"stats": {"ricochet": 1.0}, "flags": {},
	},
	{
		"id": "piercing_wave", "name": "Piercing Wave", "rarity": RARITY_EPIC,
		"category": "weapon", "weight": 6, "max_stacks": 5,
		"description": "Projectiles and melee shockwaves pass through +1 body, " +
"and each body pierced adds 15% damage.",
		"stats": {"pierce": 1.0}, "flags": {},
	},
	{
		"id": "rapid_fire", "name": "Berserk Rate", "rarity": RARITY_COMMON,
		"category": "weapon", "weight": 10, "max_stacks": 10,
		"description": "+18% ranged fire rate and melee attack speed per stack.",
		"stats": {"attack_mult": 0.18}, "flags": {},
	},
	{
		"id": "heavy_caliber", "name": "Heavy Caliber", "rarity": RARITY_EPIC,
		"category": "weapon", "weight": 6, "max_stacks": 6,
		"description": "+35% weapon damage and +40% knockback/gore force, but " +
"-10% fire rate per stack.",
		"stats": {"damage_mult": 0.35, "knockback_mult": 0.4, "attack_mult": -0.1},
		"flags": {},
	},
	# --- on-hit and on-fire triggers ---------------------------------------
	{
		"id": "dagger_arc", "name": "Hatchet Arc", "rarity": RARITY_COMMON,
		"category": "trigger", "weight": 10, "max_stacks": 6,
		"description": "Chance on any ranged or melee hit to spin a throwing " +
"blade at a nearby enemy for 140% weapon damage.",
		"stats": {"arc_chance": 0.15}, "flags": {"dagger_arc": true},
	},
	{
		"id": "arrow_nova", "name": "Thorn Nova", "rarity": RARITY_EPIC,
		"category": "trigger", "weight": 6, "max_stacks": 5,
		"description": "Chance on hit to burst a ring of 8 splinters outward, " +
"and every kill does it outright. 55% weapon damage each.",
		"stats": {"nova_chance": 0.12}, "flags": {"nova": true},
	},
	{
		"id": "chain_lightning", "name": "Blood Arc", "rarity": RARITY_EPIC,
		"category": "trigger", "weight": 6, "max_stacks": 6,
		"description": "Chance on hit to arc to 3 + stack enemies for 40% " +
"weapon damage each.",
		"stats": {"chain_chance": 0.15, "chain_base": 3.0}, "flags": {"chain": true},
	},
	{
		"id": "sticky_charge", "name": "Blood Charge", "rarity": RARITY_EPIC,
		"category": "trigger", "weight": 6, "max_stacks": 5,
		"description": "Hits plant a blood charge that detonates after 1.2 s for " +
"120% weapon damage in a 3 m gore burst.",
		"stats": {"bomb_chance": 0.12}, "flags": {"bomb": true},
	},
	{
		"id": "melee_shockwave", "name": "Crescent Wave", "rarity": RARITY_LEGENDARY,
		"category": "trigger", "weight": 3, "max_stacks": 4,
		"description": "Every melee swing throws a short piercing crescent of " +
"wind and blood, so a hatchet answers a dense wave.",
		"stats": {"wave_damage": 0.45}, "flags": {"shockwave": true},
	},
	# --- crit, economy, survival ------------------------------------------
	{
		"id": "crit_sharpshooter", "name": "Critical Sharpshooter",
		"rarity": RARITY_COMMON, "category": "survival", "weight": 10, "max_stacks": 6,
		"description": "+12% crit chance. A crit deals 2.0x damage and rolls its " +
"procs twice.",
		"stats": {"crit_chance": 0.12}, "flags": {"crit": true},
	},
	{
		"id": "grim_harvest", "name": "Grim Harvest", "rarity": RARITY_COMMON,
		"category": "survival", "weight": 10, "max_stacks": 8,
		"description": "Killing or gibbing an enemy restores 1 + stack HP.",
		"stats": {"heal_on_kill": 1.0}, "flags": {"harvest": true},
	},
	{
		"id": "collectors_bounty", "name": "Collector's Bounty", "rarity": RARITY_COMMON,
		"category": "economy", "weight": 10, "max_stacks": 8,
		"description": "+25% crystals from every kill, chest and totem.",
		"stats": {"currency_mult": 0.25}, "flags": {},
	},
	{
		"id": "fortified_plate", "name": "Fortified Plate", "rarity": RARITY_COMMON,
		"category": "survival", "weight": 10, "max_stacks": 8,
		"description": "+25 max HP, and 10% of the pool comes back when the " +
"island is cleared.",
		"stats": {"max_hp_flat": 25.0, "heal_on_clear": 0.1}, "flags": {"plate": true},
	},
	{
		"id": "featherstep", "name": "Featherstep", "rarity": RARITY_COMMON,
		"category": "survival", "weight": 8, "max_stacks": 8,
		"description": "A step that is never quite where the blow lands: " +
"+10% dodge, stacking hyperbolically toward 60%.",
		"stats": {"dodge_chance": 0.10}, "flags": {"dodge": true},
	},
	{
		"id": "bonus_chest", "name": "Buried Cache", "rarity": RARITY_EPIC,
		"category": "economy", "weight": 6, "max_stacks": 6,
		"description": "15% chance per stack that clearing an island spawns an " +
"extra mini-chest.",
		"stats": {"chest_chance": 0.15}, "flags": {"bonus_chest": true},
	},
	# --- greed -------------------------------------------------------------
	{
		"id": "glass_cannon", "name": "Glass Cannon", "rarity": RARITY_GREED,
		"category": "greed", "weight": 5, "max_stacks": 5,
		"description": "Deal +100% all damage and lose 40% of your max HP.",
		"stats": {"damage_mult": 1.0, "max_hp_mult": -0.4}, "flags": {"glass": true},
	},
	{
		"id": "brutal_pact", "name": "Brutal Pact", "rarity": RARITY_GREED,
		"category": "greed", "weight": 5, "max_stacks": 3,
		"description": "Gain +3 Split Shot and +30% fire rate at once. Enemies " +
"move 25% faster and deal 30% more to you.",
		"stats": {"split_shots": 3.0, "attack_mult": 0.3,
			"enemy_speed_mult": 0.25, "enemy_damage_mult": 0.3},
		"flags": {"brutal": true},
	},
	{
		"id": "slippery_slope", "name": "Slippery Slope", "rarity": RARITY_GREED,
		"category": "greed", "weight": 5, "max_stacks": 3,
		"description": "+100% currency earned, but you bleed 2% of your max HP " +
"per second while standing still in a live wave.",
		"stats": {"currency_mult": 1.0, "standing_drain": 0.02},
		"flags": {"slippery": true},
	},
	{
		"id": "cursed_arsenal", "name": "Cursed Arsenal", "rarity": RARITY_GREED,
		"category": "greed", "weight": 4, "max_stacks": 2,
		"description": "Your hands lock for the rest of the run: +150% weapon " +
"damage and +50% proc coefficient on what you are already holding.",
		"stats": {"damage_mult": 1.5, "proc_coeff_mult": 0.5},
		"flags": {"cursed": true},
	},
	{
		"id": "bloodthirst", "name": "Bloodthirst", "rarity": RARITY_GREED,
		"category": "greed", "weight": 4, "max_stacks": 2,
		"description": "No more breathing between islands. All healing comes " +
"from your own cuts: +300% melee lifesteal.",
		"stats": {"melee_lifesteal": 3.0},
		"flags": {"bloodthirst": true},
	},
]

static var _by_id: Dictionary = {}
static var _built := false


static func _ensure() -> void:
	if _built:
		return
	_built = true
	_by_id.clear()
	for row in MODS:
		_by_id[str(row.id)] = row


static func all() -> Array:
	_ensure()
	return MODS


static func get_mod(mod_id: String) -> Dictionary:
	_ensure()
	return _by_id.get(mod_id, {})


static func has(mod_id: String) -> bool:
	_ensure()
	return _by_id.has(mod_id)


static func rarity_of(mod_id: String) -> String:
	return str(get_mod(mod_id).get("rarity", RARITY_COMMON))


static func colour_of(mod_id: String) -> Color:
	return RARITY_COLOUR.get(rarity_of(mod_id), Color.WHITE)


static func name_of(mod_id: String) -> String:
	return str(get_mod(mod_id).get("name", mod_id))


static func max_stacks(mod_id: String) -> int:
	return maxi(1, int(get_mod(mod_id).get("max_stacks", 1)))


## One draft of `count` distinct offers, weighted inside the allowed tiers. The
## pedestal calls this with the run's own rng, so a draft is reproducible from
## the stage seed on every machine that asks the same question.
static func draft(rng: RandomNumberGenerator, count: int = 3,
		allow_greed: bool = false, exclude: Array = []) -> Array[String]:
	_ensure()
	var pool: Array[Dictionary] = []
	var total := 0.0
	for row in MODS:
		var id := str(row.id)
		if exclude.has(id):
			continue
		var rarity := str(row.rarity)
		if rarity == RARITY_GREED and not allow_greed:
			continue
		var weight := float(row.get("weight", 5))
		pool.append({"id": id, "weight": weight})
		total += weight
	var out: Array[String] = []
	for _pick in maxi(0, count):
		if pool.is_empty() or total <= 0.0:
			break
		var roll := rng.randf_range(0.0, total)
		var chosen := -1
		var walked := 0.0
		for index in pool.size():
			walked += float((pool[index] as Dictionary).weight)
			if roll <= walked:
				chosen = index
				break
		if chosen < 0:
			chosen = pool.size() - 1
		var row: Dictionary = pool[chosen]
		out.append(str(row.id))
		total -= float(row.weight)
		pool.remove_at(chosen)
	return out


## A greed totem's own offer: always a greed mod, never one already maxed out.
static func greed_offer(rng: RandomNumberGenerator, stacks: Dictionary) -> String:
	_ensure()
	var pool: Array[String] = []
	for row in MODS:
		if str(row.rarity) != RARITY_GREED:
			continue
		var id := str(row.id)
		if int(stacks.get(id, 0)) >= max_stacks(id):
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]
