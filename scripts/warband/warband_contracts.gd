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
##
## Steel first, then the armour, then the trinkets - the order a body is armed in
## (`Warband.DRESS_SLOTS`), so the rows of the page and the kit order the hotbar
## keys are laid out in are the same order the body is first dressed.
enum SlotType { HEAD, CHEST, HANDS, LEGS, BOOTS, NECK, RING1, RING2, MAIN_HAND, OFF_HAND }

const SLOT_ORDER: Array[int] = [
	SlotType.MAIN_HAND, SlotType.OFF_HAND,
	SlotType.HEAD, SlotType.CHEST, SlotType.HANDS, SlotType.LEGS, SlotType.BOOTS,
	SlotType.NECK, SlotType.RING1, SlotType.RING2,
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

# --- the party's mode ------------------------------------------------------

## How the squad's AI picks its fights, set from the warband menu and saved with
## the warband. The id is the save and wire vocabulary; the menu prints it in caps.
##   * `offensive` - the squad goes looking: anything hostile inside its engage
##     radius is a fight (the only behaviour there was before the choice);
##   * `defensive` - the squad answers: it fights only what has struck one of the
##     band, and what the band has already wounded - the soul's own blade first;
##   * `passive` - the squad fights nothing and fetches nothing: it keeps to the
##     soul, for running away.
const PARTY_OFFENSIVE := "offensive"
const PARTY_DEFENSIVE := "defensive"
const PARTY_PASSIVE := "passive"
## Most willing first: the order the menu lays them out in.
const PARTY_MODES: Array[String] = [PARTY_OFFENSIVE, PARTY_DEFENSIVE, PARTY_PASSIVE]
## What a warband that was never told otherwise fights as - a fresh one, a v8 file.
const DEFAULT_PARTY_MODE := PARTY_OFFENSIVE

# --- the party member's disposition ----------------------------------------

## How one body fights on its own. The party's mode (`PARTY_MODES` above) says
## which fights the squad takes; a disposition says how each mercenary takes
## them. Every record carries one (`WarbandRoster.KEY_DISPOSITION`) and the squad
## AI reads it per body, so a band of eight fights as eight intentions instead of
## one - and the automatic arming reads it too, because a shield is a fighter's
## choice as much as a shield hand is.
##
##   * `tank`  - the front line. Guards between blows instead of behind a rolled
##     window, advances behind the guard, never gives ground to a blade and never
##     breaks off a fight to bind a wound; a shield's skills and a ward first.
##   * `melee` - the press. Attacks more than it guards, prefers the densest knot
##     of hostiles and the wide arc and ring skills, and below
##     `SquadDrive.WITHDRAW_SHARE` it falls back out of contact to bind a wound.
##   * `bow`   - the back line. Holds the far end of its own bow's reach and, when
##     struck or crowded, gives ground until the string can come up again (kites);
##     prefers the volley skills; the arming hands it a bow.
const DISPOSITION_TANK := "tank"
const DISPOSITION_MELEE := "melee"
const DISPOSITION_BOW := "bow"
## Every disposition, front line first - the order the roster screen steps them.
const DISPOSITIONS: Array[String] = [DISPOSITION_TANK, DISPOSITION_MELEE, DISPOSITION_BOW]
## What a warband that was never told otherwise fights as. A v10 file, a fresh
## warband and a rescued stranger all come up as this.
const DEFAULT_DISPOSITION := DISPOSITION_MELEE
const DISPOSITION_LABELS := {
	DISPOSITION_TANK: "TANK",
	DISPOSITION_MELEE: "MELEE",
	DISPOSITION_BOW: "BOW",
}
## The one line the roster screen prints under the chip.
const DISPOSITION_TEXT := {
	DISPOSITION_TANK: "Holds the line: guards between blows, never falls back.",
	DISPOSITION_MELEE: "Presses the densest knot and falls back under 30% to bind a wound.",
	DISPOSITION_BOW: "Back line: kites when struck or crowded, then looses again.",
}
## How far down a disposition's skill list an ability may sit. `ABILITY_NEVER`
## is a skill that disposition never reaches for, however idle it is.
const ABILITY_NEVER := 99
## Skill preferences, best first. A row names the skills its body reaches for
## and spells out the ones it will not (`ABILITY_NEVER`); a skill no row has met
## yet ranks `ABILITY_OTHER`, which loses to every named skill but is still used
## when nothing better fits - a new anointed blade is not dead weight on a body
## whose table has not caught up.
const ABILITY_OTHER := 8
const DISPOSITION_ABILITIES := {
	DISPOSITION_TANK: {
		"energy_shield": 0,
		"shield_slam": 1,
		"shield_bash": 2,
		"shield_charge": 3,
		"rebuke": 4,
		"double_slash": 5,
		"lunge_thrust": 6,
		"spin_slash": 7,
		"butchers_cut": 7,
		"ground_breaker": 7,
		"backstab": ABILITY_NEVER,
		"knife_work": ABILITY_NEVER,
		"dash": ABILITY_NEVER,
		"charge": ABILITY_NEVER,
		"rain_of_ash": ABILITY_NEVER,
		"skewer": ABILITY_NEVER,
	},
	DISPOSITION_MELEE: {
		"spin_slash": 0,
		"shield_slam": 1,
		"double_slash": 2,
		"lunge_thrust": 3,
		"shield_bash": 4,
		"shield_charge": 5,
		"fireball": 6,
		"bone_spear": 6,
		"energy_shield": 7,
		"ground_breaker": 4,
		"wide_sweep": 4,
		"executioner": 4,
		"butchers_cut": 5,
		"gut_hook": 5,
		"knife_work": 6,
		"rebuke": 7,
		"barrage": ABILITY_NEVER,
		"triple_volley": ABILITY_NEVER,
		"piercing_shot": ABILITY_NEVER,
		"backstab": ABILITY_NEVER,
		"dash": ABILITY_NEVER,
		"charge": ABILITY_NEVER,
	},
	DISPOSITION_BOW: {
		"barrage": 0,
		"triple_volley": 1,
		"piercing_shot": 2,
		"energy_shield": 4,
		"rain_of_ash": 1,
		"skewer": 3,
		"double_slash": 6,
		"lunge_thrust": 7,
		"knife_work": 7,
		"cinder_lance": ABILITY_NEVER,
		"grave_bloom": ABILITY_NEVER,
		"ember_ward": ABILITY_NEVER,
		"ground_breaker": ABILITY_NEVER,
		"wide_sweep": ABILITY_NEVER,
		"executioner": ABILITY_NEVER,
		"gut_hook": ABILITY_NEVER,
		"butchers_cut": ABILITY_NEVER,
		"rebuke": ABILITY_NEVER,
		"spin_slash": ABILITY_NEVER,
		"shield_bash": ABILITY_NEVER,
		"shield_charge": ABILITY_NEVER,
		"shield_slam": ABILITY_NEVER,
		"backstab": ABILITY_NEVER,
		"dash": ABILITY_NEVER,
		"charge": ABILITY_NEVER,
	},
}
## What the automatic arming adds to a piece's price when it is choosing for this
## disposition: the number that makes a shield worth carrying, a greatsword worth
## swinging and a bow worth drawing when the pool holds all three. A row may name
## a piece's `kind` as well as its `category`, and the kind wins when it does -
## `dagger` refines `1h`, so a body's opinion of a knife is not its opinion of a
## sword - while a kind the row does not name falls through to the category, which
## keeps `2h`, `bow`, `shield`, `focus` and plain armour on their single entry.
##
## A weight is a preference and price still carries the choice inside it: a tank's
## -70 does not keep a dear greatsword out of its hand, because 340 - 70 still beat
## a 110-shortsword's 230. A kind the stance must not carry at all belongs in
## `DISPOSITION_GEAR_REFUSED` below; the tank's two-hander is refused there and the
## weight is only the score it would get.
const DISPOSITION_GEAR := {
	DISPOSITION_TANK: {"shield": 170.0, "1h": 120.0, "focus": 40.0, "2h": -70.0,
		"bow": -220.0, "staff": -120.0, "dagger": -20.0},
	DISPOSITION_MELEE: {"2h": 150.0, "1h": 80.0, "dagger": 40.0, "focus": 20.0,
		"shield": -60.0, "bow": -220.0, "staff": -100.0},
	DISPOSITION_BOW: {"bow": 260.0, "1h": 30.0, "dagger": 20.0, "focus": 10.0,
		"2h": -90.0, "staff": -60.0, "shield": -170.0},
}
## The kinds a disposition's automatic arming **never reaches for**, however
## empty the hand and however dear the piece. `DISPOSITION_GEAR` can only make a
## piece expensive, so a pool with no blade in it still handed a melee body the
## band's one spare bow - and a body that fights with a blade cannot swing a bow,
## so it circled the field with a stick it never drew. A refusal is the arming's
## answer to that: a blade's trade keeps its hands empty for the blade the field
## will offer (or for the player's own hand on the paperdoll, which is not bound
## by this table), and the bow stays in the pool for a body that draws it.
##
## A tank's list carries `2h` for the same reason, on its own line: a two-hander
## locks the off hand, and the shield the tank's whole stance is built around can
## only follow it into the pool. A price weight can never say that - a dear
## greatsword outscores a cheap blade however negative the number - so the tank
## refuses the piece outright and dresses in the best shield and one-hander the
## pool holds, or waits for one with its hands empty.
const DISPOSITION_GEAR_REFUSED := {
	DISPOSITION_TANK: ["2h", "bow", "staff"],
	DISPOSITION_MELEE: ["bow", "staff"],
	DISPOSITION_BOW: [],
}
## What a disposition wants in its **off hand**, best kind first. The off hand is a
## stance of its own and not a second main hand: a tank's holds a shield (or a ward
## behind it), a melee body pairs a second blade with a one-hander, and a bowman
## keeps a ward there for when the string has to come up. The order outranks the
## price on that one slot, which is the point of it - a cheap board still beats a
## dear second dagger for the body that means to hold the line.
const DISPOSITION_OFF_HAND := {
	DISPOSITION_TANK: ["shield", "focus", "1h"],
	DISPOSITION_MELEE: ["1h", "shield", "focus"],
	DISPOSITION_BOW: ["focus", "1h", "shield"],
}

## The disposition id for `raw`: itself for a known id, the default for an empty
## string or a word this build has never heard of - a save, a screen and the wire
## all pass their own spelling through here.
static func disposition_id(raw: Variant) -> String:
	var wanted := str(raw).strip_edges().to_lower()
	return wanted if DISPOSITIONS.has(wanted) else DEFAULT_DISPOSITION

## The id for `raw` as written, or '' when it names no disposition this build
## knows. `disposition_id` is the forgiving reader; this is the refusing one, for
## a verb that must not silently accept a typo.
static func disposition_exact(raw: Variant) -> String:
	var wanted := str(raw).strip_edges().to_lower()
	return wanted if DISPOSITIONS.has(wanted) else ""

static func disposition_label(disposition: String) -> String:
	return str(DISPOSITION_LABELS.get(disposition, DISPOSITION_LABELS[DEFAULT_DISPOSITION]))

static func disposition_text(disposition: String) -> String:
	return str(DISPOSITION_TEXT.get(disposition, DISPOSITION_TEXT[DEFAULT_DISPOSITION]))

## The disposition one step on in `DISPOSITIONS` order, wrapping: what a press on
## the roster's chip does.
static func next_disposition(disposition: String) -> String:
	var index := DISPOSITIONS.find(disposition_id(disposition))
	return DISPOSITIONS[(index + 1) % DISPOSITIONS.size()]

## How much this body wants to reach for `ability` right now: 0 is its first
## choice, `ABILITY_NEVER` is a skill it never calls on. An unknown ability id is
## `ABILITY_OTHER`, so a skill added later is used when nothing preferred fits.
static func disposition_ability_rank(disposition: String, ability: String) -> int:
	var row: Dictionary = DISPOSITION_ABILITIES.get(disposition_id(disposition), {})
	return int(row.get(ability, ABILITY_OTHER))

## The word a disposition table knows a piece by: its `kind` when the catalogue
## names one (`dagger`, `bow`), its `category` when it does not (a plain `2h`).
## Both tables below read this one answer, so a knife can never be scored as the
## sword it is not and a refusal can never disagree with a weight.
static func gear_kind(item: Dictionary) -> String:
	var kind := str(item.get("kind", ""))
	return kind if not kind.is_empty() else str(item.get("category", ""))

## Whether this body's automatic arming must leave the piece in the pool. A
## refusal outranks both the price and the pool's emptiness: the hands stay empty
## for what the trade uses rather than closing on what it cannot swing. A body
## the player dresses by hand is not asked (`WarbandState.equip_merc`).
static func disposition_refuses_gear(disposition: String, item: Dictionary) -> bool:
	var row: Array = DISPOSITION_GEAR_REFUSED.get(disposition_id(disposition), [])
	var kind := gear_kind(item)
	return row.has(kind) or row.has(str(item.get("category", "")))

## The score the automatic arming gives a piece for this body: its price, plus
## what its kind is worth to the disposition. One decision, used by a recruit's
## dressing, the band-wide arming pass and a loot pickup's snap-in. Only pieces
## `disposition_refuses_gear` lets through are scored - a bow is not a cheap blade
## to a melee body, it is not a blade at all.
static func disposition_gear_score(disposition: String, item: Dictionary,
		value: int) -> float:
	var row: Dictionary = DISPOSITION_GEAR.get(disposition_id(disposition), {})
	var kind := gear_kind(item)
	if row.has(kind):
		return float(value) + float(row[kind])
	return float(value) + float(row.get(str(item.get("category", "")), 0.0))

## What this body wants in `slot_id`, higher being better and `-1` meaning the
## slot is not decided this way - every slot but the off hand is scored by
## `disposition_gear_score` alone, where price carries the choice. The off hand
## reads its row's best kind first, so a tank's shield outranks any second blade
## it could carry and a melee body's second blade outranks a board.
static func disposition_off_hand_rank(disposition: String, item: Dictionary,
		slot_id: String) -> int:
	if slot_id != "off":
		return -1
	var row: Array = DISPOSITION_OFF_HAND.get(disposition_id(disposition), [])
	var kind := str(item.get("kind", ""))
	var index := row.find(kind)
	if index < 0:
		index = row.find(str(item.get("category", "")))
	if index < 0:
		return 0
	return row.size() - index

# --- tuning ----------------------------------------------------------------

## A lethal hit whose overkill is <= 10% of max health downs instead of kills.
const OVERKILL_THRESHOLD := 0.10
## A human holds the revive channel for five seconds.
const REVIVE_CHANNEL_SECONDS := 5.0
## Mercenaries in a warband have identical base stats: gear is the only lever.
const BASE_MAX_HEALTH := 100.0
const BASE_MAX_STAMINA := 1000.0
## How many mercenaries a warband may swear in.
const MAX_DEPLOYMENT_CAP := 8
## How close a human must stand to hold a revive channel.
const REVIVE_REACH := 2.5
## Seconds a downed body survives before bleeding out, and its crawl pace.
const DOWNED_BLEED_SECONDS := 30.0
const DOWNED_CRAWL_SPEED := 0.9
## Every warband body knits its wounds on its own while it stands: one point of
## health every five seconds, whatever it is doing. Slow on purpose - a full pool
## is eight minutes of walking - so it buys a long retreat, never a fight.
const HEALTH_REGEN_AMOUNT := 1.0
const HEALTH_REGEN_SECONDS := 5.0
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
