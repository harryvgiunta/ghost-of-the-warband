class_name WarbandContracts
extends RefCounted
## GHOST OF THE WARBAND — the shared contract every parallel worktree reads.
##
## This file is Phase 0 of the overhaul and is deliberately pure vocabulary plus
## arithmetic: no scene, no node, no autoload. Six isolated branches cannot
## invent two spellings of the same slot, state, essence tier, bubble radius or
## overkill rule because they all land here.
##
## Existing vocabulary this maps onto, and must never replace:
##   * `EquipmentRules.SLOTS`  -> head/chest/hands/legs/feet/neck/ring1/ring2/main/off
##   * `PlayerState.ITEMS`     -> category 1h/2h/bow/staff/shield/focus/armor/jewelry
##   * `ArenaActor.MAX_HEALTH` -> 100.0 (every mercenary has identical base stats)
##   * `Stamina.MAX`           -> 1000.0 (identical for every mercenary)

# --- equipment -------------------------------------------------------------

## The ten worn slots, in paperdoll order. `BOOTS` is the existing `feet` id and
## `MAIN_HAND`/`OFF_HAND` are the existing `main`/`off` ids: the enum names are
## the design vocabulary, `SLOT_IDS` is the wire and save vocabulary.
enum SlotType { HEAD, CHEST, HANDS, LEGS, BOOTS, NECK, RING1, RING2, MAIN_HAND, OFF_HAND }

const SLOT_ORDER: Array[int] = [
	SlotType.HEAD, SlotType.CHEST, SlotType.HANDS, SlotType.LEGS, SlotType.BOOTS,
	SlotType.NECK, SlotType.RING1, SlotType.RING2, SlotType.MAIN_HAND, SlotType.OFF_HAND,
]

const SLOT_IDS := {
	SlotType.HEAD: "head",
	SlotType.CHEST: "chest",
	SlotType.HANDS: "hands",
	SlotType.LEGS: "legs",
	SlotType.BOOTS: "feet",
	SlotType.NECK: "neck",
	SlotType.RING1: "ring1",
	SlotType.RING2: "ring2",
	SlotType.MAIN_HAND: "main",
	SlotType.OFF_HAND: "off",
}

const SLOT_LABELS := {
	SlotType.HEAD: "Head",
	SlotType.CHEST: "Chest",
	SlotType.HANDS: "Hands",
	SlotType.LEGS: "Legs",
	SlotType.BOOTS: "Boots",
	SlotType.NECK: "Neck",
	SlotType.RING1: "Ring 1",
	SlotType.RING2: "Ring 2",
	SlotType.MAIN_HAND: "Main Hand",
	SlotType.OFF_HAND: "Off-Hand",
}

## What a held item is, as the paperdoll and the brand system care about it.
## `PlayerState.ITEMS` says `category`/`focus`; this says what the item *does*.
enum WeaponSubType { NONE, ONE_HAND, TWO_HAND, BOW, STAFF, SHIELD, SKULL, TOME }

const WEAPON_LABELS := {
	WeaponSubType.NONE: "Armor",
	WeaponSubType.ONE_HAND: "One-Handed",
	WeaponSubType.TWO_HAND: "Two-Handed",
	WeaponSubType.BOW: "Bow",
	WeaponSubType.STAFF: "Staff",
	WeaponSubType.SHIELD: "Shield",
	WeaponSubType.SKULL: "Skull",
	WeaponSubType.TOME: "Tome",
}

const SKULL_FOCUS := ["skull", "skull_life", "skull_death"]

# --- ritual essence --------------------------------------------------------

## Sacramental Cruor, Tier 1 (common) through Tier 5 (relic).
enum CruorTier {
	T1_RITUAL_TALLOW,
	T2_BLACK_BILE,
	T3_COAGULATED_CRUOR,
	T4_STIGMATIC_RESIN,
	T5_CRYSTALLIZED_SIN,
}

# --- combat lifecycle ------------------------------------------------------

enum HealthState { ALIVE, DOWNED, DEAD }

## `ACTIVE` = inside a human presence bubble, full speed and damage.
## `PASSIVE_SIM` = away from every human, convincing choreography at 10% damage.
enum CombatSimState { ACTIVE, PASSIVE_SIM }

# --- tuning ----------------------------------------------------------------

## A lethal hit whose overkill is <= 10% of max health downs instead of kills.
const OVERKILL_THRESHOLD := 0.10
## A human holds the revive channel for five seconds; AI never revives.
const REVIVE_CHANNEL_SECONDS := 5.0
## Damage multiplier inside a bubble and far away from every bubble.
const ACTIVE_DAMAGE_MULTIPLIER := 1.0
const PASSIVE_DAMAGE_MULTIPLIER := 0.10
## The bubble is measured from every human-possessed body, so it scales with
## the number of players rather than needing a separate node per group.
const DEFAULT_BUBBLE_RADIUS := 30.0
## A bubble shrinks/grows with hysteresis so a body pacing the edge cannot
## chatter between real combat and simulation every frame.
const BUBBLE_EXIT_RADIUS := 34.0
## Mercenaries in a warband have identical base stats: gear is the only lever.
const BASE_MAX_HEALTH := 100.0
const BASE_MAX_STAMINA := 1000.0
## The warband deployable into one battle (the plan's cap X).
const MAX_DEPLOYMENT_CAP := 8
## How close a human must stand to hold a revive channel.
const REVIVE_REACH := 2.5
## Seconds a downed body survives before bleeding out, and its crawl pace.
const DOWNED_BLEED_SECONDS := 30.0
const DOWNED_CRAWL_SPEED := 0.9
## 5 lower-tier units fuse into 1 of the next tier (5^4 = 625 Tier 1 -> 1 Tier 5).
const CRUOR_DISTILL_RATIO := 5

# --- slot helpers ----------------------------------------------------------

static func slot_id(slot: int) -> String:
	return str(SLOT_IDS.get(slot, ""))

## '' when the id is not a worn slot.
static func slot_from_id(id: String) -> int:
	for slot in SLOT_IDS:
		if SLOT_IDS[slot] == id:
			return slot
	return -1

static func slot_label(slot: int) -> String:
	return str(SLOT_LABELS.get(slot, "Slot"))

static func slot_id_label(id: String) -> String:
	return slot_label(slot_from_id(id))

## The item's combat identity, mapped from the catalog's category/focus pair.
static func weapon_subtype(item: Dictionary) -> int:
	if item.is_empty():
		return WeaponSubType.NONE
	match str(item.get("category", "")):
		"1h":
			return WeaponSubType.ONE_HAND
		"2h":
			return WeaponSubType.TWO_HAND
		"bow":
			return WeaponSubType.BOW
		"staff":
			return WeaponSubType.STAFF
		"shield":
			return WeaponSubType.SHIELD
		"focus":
			return WeaponSubType.SKULL if str(item.get("focus", "")) in SKULL_FOCUS else WeaponSubType.TOME
	return WeaponSubType.NONE

## True for items that leave no off hand: 2H, bows and staves.
static func two_handed_item(item: Dictionary) -> bool:
	return weapon_subtype(item) in [WeaponSubType.TWO_HAND, WeaponSubType.BOW, WeaponSubType.STAFF]

## Off-hand-only pieces: shields, skulls and tomes.
static func off_hand_only(item: Dictionary) -> bool:
	return weapon_subtype(item) in [WeaponSubType.SHIELD, WeaponSubType.SKULL, WeaponSubType.TOME]

# --- combat helpers --------------------------------------------------------

static func damage_multiplier(sim_state: int) -> float:
	return PASSIVE_DAMAGE_MULTIPLIER if sim_state == CombatSimState.PASSIVE_SIM else ACTIVE_DAMAGE_MULTIPLIER

static func state_name(state: int) -> String:
	match state:
		HealthState.DOWNED:
			return "Downed"
		HealthState.DEAD:
			return "Dead"
	return "Alive"

## Resolve one hit against a living body. The single authority for the 10%
## overkill rule: a lethal hit that does not overkill by more than 10% of max
## health leaves the body DOWNED at zero health, anything heavier kills it.
##
## Returns `{ok, state, health, damage, overkill, downed, died}`.
static func resolve_damage(health: float, max_health: float, amount: float) -> Dictionary:
	var max_hp := maxf(0.0, max_health)
	var hit := maxf(0.0, amount)
	if hit <= 0.0:
		return {"ok": false, "state": HealthState.ALIVE, "health": health,
			"damage": 0.0, "overkill": 0.0, "downed": false, "died": false}
	var remaining := health - hit
	if remaining > 0.0:
		return {"ok": true, "state": HealthState.ALIVE, "health": remaining,
			"damage": hit, "overkill": 0.0, "downed": false, "died": false}
	var overkill := -remaining
	if overkill <= max_hp * OVERKILL_THRESHOLD:
		return {"ok": true, "state": HealthState.DOWNED, "health": 0.0,
			"damage": hit, "overkill": overkill, "downed": true, "died": false}
	return {"ok": true, "state": HealthState.DEAD, "health": 0.0,
		"damage": hit, "overkill": overkill, "downed": false, "died": true}

## A blow on an already-downed body. The same 10% threshold is a finisher: a
## heavy strike ends it, a light one (including passive 10% chip) does not.
## Returns true when the body dies.
static func finishes_downed(max_health: float, amount: float) -> bool:
	return amount > maxf(0.0, max_health) * OVERKILL_THRESHOLD

## Health a revive restores, as a fraction of max health.
## What a body stands up with. A revived mercenary comes back with a twentieth of
## its own pool: enough to walk, not enough to trade blows, so a rescue buys a
## withdrawal rather than a second life.
const REVIVE_HEALTH_FRACTION := 0.05
