extends RefCounted
## Ability definitions shared by every mode.
##
## An ability is data: the stock item whose skill it is, hand slot, cost,
## cooldown, duration, travel, animation, sound, icon and the effect the owning
## scene applies. `AbilityRunner` owns the lifecycle; controllers only supply
## authority and the current base movement speed. Add a new entry here, an icon
## beside it, and the same HUD/input/network path works for the next ability.
##
## Slot 0 is the main hand, slot 1 the off hand, slot 2 the trinket slot
## (necklace first, then ring 1, then ring 2). The granted ability follows the
## weapon the rig is actually holding, so a session weapon key changes it.
## A trinket grant is worn rather than held, so it survives every weapon swap.
##
## A weapon is plain until it is anointed. A hand definition's `item` names the
## stock row whose skill a piece wakes into (`skill_for`), not a grant: `granted`
## hands a held weapon its skill only when the rig's `anointed` names that skill
## for that hand, and the one source of that is the warband altar's ledger,
## carried onto the rig by `PlayerState.build_loadout`. An empty main hand keeps
## the unarmed Charge and a worn trinket keeps its own grant.
##
## `move` decides what the feet do for the duration. A planted skill (ranged
## casts, the unarmed charge, the backstab blink) stops the walk dead; a melee
## skill with `move` keeps the normal walking input and only overrides it while
## `travel_seconds` commits the owner to a step.
##
## `aim` decides where a committed step goes: the dash turns the body onto the
## live crosshair and travels down that line instead of the heading the key was
## pressed from. Every skill that travels (the lunge, the boss shove, the shield
## charge) declares it; a planted skill needs no direction.

const SLOT_COUNT := 3
const TrinketStats = preload("res://scripts/trinket_stats.gd")
## Temporary testing cost: every weapon skill spends a trivial stamina sliver
## so the effect can be exercised back to back. The legacy unarmed charge keeps
## its original price.
const TEST_STAMINA_COST := 1.0
## Base damage per catalog item. A definition's `damage_scale` multiplies it.
const ITEM_DAMAGE := {
	"bow_short": 30.0,
	"bow_recurve": 38.0,
	"bow_long": 50.0,
	"sword_short": 30.0,
	"sword_arming": 38.0,
	"sword_great": 50.0,
	"dagger_iron": 14.0,
	"staff_fire": 50.0,
	"staff_bone": 50.0,
	"shield_buckler": 18.0,
	"shield_kite": 18.0,
	"shield_tower": 18.0,
}
const BOW_ITEMS := ["bow_short", "bow_recurve", "bow_long"]
const SWORD_ITEMS := ["sword_short", "sword_arming", "sword_great"]
const STAFF_ITEMS := ["staff_fire", "staff_bone"]
const SHIELD_ITEMS := ["shield_buckler", "shield_kite", "shield_tower"]
## Effect kinds that swing the body's own weapon. They play their authored
## blade clip over the whole skeleton, so the stance has to be upright before
## they start; a cast can layer over a crouch, a cut cannot.
const MELEE_EFFECTS := ["melee_arc", "melee_ring", "backstab"]

const ABILITIES := [
	{
		"id": "charge",
		"name": "CHARGE",
		"item": "",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": 10.0,
		"cooldown": 2.5,
		"duration": 1.0,
		"travel_seconds": 1.0,
		"speed_scale": 2.0,
		"move": false,
		"sound": "charge",
		"animation": "Sprint_Loop",
		"lean": 0.18,
		"icon": "res://assets/ui/abilities/charge.png",
		"description": "Lunge forward at double speed for one second.",
	},
	{
		"id": "barrage",
		"name": "BARRAGE",
		"item": "bow_short",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.2,
		"duration": 1.15,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "barrage",
		"move": false,
		"animation": "Bow_Barrage",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/barrage.png",
		"description": "Rapid fire six half-damage arrows with a spread.",
		"effect": {"kind": "barrage", "damage_scale": 0.5, "shots": 6,
			"spread_degrees": 4.0, "vertical_spread_degrees": 1.4,
			"arrow_speed_scale": 1.05},
		"cues": [
			{"at": 0.22, "cue": "shot"},
			{"at": 0.34, "cue": "shot"},
			{"at": 0.46, "cue": "shot"},
			{"at": 0.58, "cue": "shot"},
			{"at": 0.70, "cue": "shot"},
			{"at": 0.82, "cue": "shot"},
		],
		# Normalised draw-strength keys. The rig solves both bow arms from this
		# curve, so every shot visibly reaches full draw and releases on its cue.
		"bow_draw": [
			[0.00, 0.10], [0.06, 0.88], [0.14, 1.00], [0.175, 1.00],
			[0.191, 0.00], [0.23, 0.88], [0.27, 1.00], [0.296, 0.00],
			[0.335, 0.90], [0.38, 1.00], [0.400, 0.00], [0.44, 0.90],
			[0.485, 1.00], [0.504, 0.00], [0.55, 0.90], [0.59, 1.00],
			[0.609, 0.00], [0.65, 0.92], [0.695, 1.00], [0.713, 0.00],
			[0.78, 0.30], [1.00, 0.00],
		],
	},
	{
		"id": "triple_volley",
		"name": "TRIPLE FAN VOLLEY",
		"item": "bow_recurve",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.3,
		"duration": 1.0,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "volley",
		"move": false,
		"animation": "Bow_Triple_Volley",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/triple_volley.png",
		"description": "Loose three arrows in one wide fan.",
		"effect": {"kind": "volley", "damage_scale": 0.7, "shots": 3,
			"spread_degrees": 5.0, "vertical_spread_degrees": 0.5,
			"arrow_speed_scale": 1.0},
		"cues": [{"at": 0.48, "cue": "volley"}],
		"bow_draw": [[0.00, 0.10], [0.16, 0.88], [0.40, 1.00], [0.46, 1.00],
			[0.48, 0.00], [0.62, 0.18], [1.00, 0.00]],
	},
	{
		"id": "piercing_shot",
		"name": "LONG PIERCING SHOT",
		"item": "bow_long",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.6,
		"duration": 1.25,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "pierce",
		"move": false,
		"animation": "Bow_Piercing_Shot",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/piercing_shot.png",
		"description": "A heavy arrow that punches through three bodies.",
		"effect": {"kind": "piercing_shot", "damage_scale": 2.0, "pierce": 3,
			"arrow_speed_scale": 1.5},
		"cues": [{"at": 0.72, "cue": "shot"}],
		"bow_draw": [[0.00, 0.10], [0.28, 0.92], [0.60, 1.00], [0.70, 1.00],
			[0.72, 0.00], [0.84, 0.14], [1.00, 0.00]],
	},
	{
		"id": "double_slash",
		"name": "DOUBLE SLASH",
		"item": "sword_short",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.1,
		"duration": 1.0,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "slash",
		"move": true,
		"animation": "Sword_Double_Slash",
		"lean": 0.05,
		"icon": "res://assets/ui/abilities/double_slash.png",
		"description": "Two fast cuts across the front arc.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.9, "arc_degrees": 150.0,
			"radius": 1.9, "stagger": 0.0},
		"cues": [
			{"at": 0.26, "cue": "arc"},
			{"at": 0.52, "cue": "arc"},
		],
	},
	{
		"id": "lunge_thrust",
		"name": "LUNGING THRUST",
		"item": "sword_arming",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.3,
		"duration": 0.95,
		"travel_seconds": 0.24,
		"speed_scale": 4.05,
		"sound": "lunge",
		"move": true,
		"aim": true,
		"animation": "Sword_Lunge_Thrust",
		"lean": 0.12,
		"icon": "res://assets/ui/abilities/lunge_thrust.png",
		"description": "A long dash that cuts through everything in its lane.",
		# The dash sweeps its lane every tick it travels, so a body it passes
		# through is hit once; the thrust at the end measures the old 2.45 m
		# reach with the same shared victim set.
		"effect": {"kind": "melee_arc", "damage_scale": 1.8, "arc_degrees": 55.0,
			"radius": 2.45, "stagger": 0.25, "path_damage": true,
			"path_radius": 1.35, "path_arc_degrees": 170.0,
			"dash_distance": 5.34},
		"cues": [
			{"at": 0.0, "cue": "dash"},
			{"at": 0.42, "cue": "arc"},
		],
	},
	{
		"id": "spin_slash",
		"name": "SPINNING AOE SPIN",
		"item": "sword_great",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.0,
		"duration": 0.3166667,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "spin",
		"move": true,
		"animation": "Sword_Spin_Slash",
		"lean": 0.04,
		"spin": 1.0,
		"icon": "res://assets/ui/abilities/spin_slash.png",
		"description": "One full turn that cuts everything around you.",
		"effect": {"kind": "melee_ring", "damage_scale": 1.4, "radius": 2.9,
			"stagger": 0.2},
		# The wind-up gathers the blade before the ring cue spends the hit. The
		# whole turn lasts a third of its old time, so the beats crowd the start.
		"cues": [
			{"at": 0.06, "cue": "wind"},
			{"at": 0.16, "cue": "ring"},
		],
	},
	{
		"id": "backstab",
		"name": "BACKSTAB",
		"item": "dagger_iron",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.4,
		"duration": 0.9,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "backstab",
		"move": false,
		"animation": "Dagger_Backstab",
		"lean": 0.16,
		"icon": "res://assets/ui/abilities/backstab.png",
		"description": "Blink behind a foe and drive the dagger through its back.",
		# The owning scene preflights the target before spending the cost; the
		# skill needs a live body under the crosshair to step behind.
		"effect": {"kind": "backstab", "damage_scale": 2.0, "radius": 1.2,
			"stagger": 0.35},
		"cues": [
			{"at": 0.20, "cue": "blink"},
			{"at": 0.50, "cue": "stab"},
		],
	},
	{
		"id": "fireball",
		"name": "FIREBALL",
		"item": "staff_fire",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.4,
		"duration": 1.2,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "fire",
		"move": false,
		"animation": "Staff_Fireball_Cast",
		"lean": -0.04,
		"icon": "res://assets/ui/abilities/fireball.png",
		"description": "Hurl a burning orb that bursts in a three-metre blast.",
		"effect": {"kind": "projectile", "projectile": "fireball",
			"damage_scale": 1.6, "radius": 3.0, "speed": 22.0, "pierce": 0},
		"cues": [{"at": 0.50, "cue": "cast"}],
	},
	{
		"id": "bone_spear",
		"name": "BONE SPEAR",
		"item": "staff_bone",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.4,
		"duration": 1.15,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "bone",
		"move": false,
		"animation": "Staff_Bone_Spear_Cast",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/bone_spear.png",
		"description": "A spectral bone lance that impales three bodies.",
		"effect": {"kind": "projectile", "projectile": "bone_spear",
			"damage_scale": 1.8, "radius": 0.0, "speed": 28.0, "pierce": 3},
		"cues": [{"at": 0.46, "cue": "cast"}],
	},
	{
		"id": "shield_bash",
		"name": "HEADBUTT",
		"item": "shield_buckler",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.0,
		"duration": 0.8,
		"travel_seconds": 0.16,
		"speed_scale": 0.55,
		"sound": "bash",
		"move": true,
		"aim": true,
		"animation": "Shield_Bash",
		"lean": 0.10,
		"icon": "res://assets/ui/abilities/shield_bash.png",
		"description": "A short head-first shove that staggers the front arc.",
		"effect": {"kind": "melee_arc", "damage_scale": 1.5, "arc_degrees": 100.0,
			"radius": 1.7, "stagger": 0.55},
		"cues": [{"at": 0.26, "cue": "arc"}],
	},
	{
		"id": "shield_charge",
		"name": "SHIELD CHARGE",
		"item": "shield_kite",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.2,
		"duration": 1.15,
		"travel_seconds": 0.48,
		"speed_scale": 1.65,
		"move": true,
		"aim": true,
		"sound": "charge",
		"animation": "Shield_Charge",
		"lean": 0.14,
		"icon": "res://assets/ui/abilities/shield_charge.png",
		"description": "Drive forward behind the shield face and bowl them over.",
		"effect": {"kind": "melee_arc", "damage_scale": 1.6, "arc_degrees": 130.0,
			"radius": 1.8, "stagger": 0.45},
		"cues": [
			{"at": 0.34, "cue": "arc"},
			{"at": 0.58, "cue": "arc"},
		],
	},
	{
		"id": "shield_slam",
		"name": "GROUND SHIELD SLAM",
		"item": "shield_tower",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.5,
		"duration": 1.1,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "slam",
		"move": true,
		"animation": "Shield_Ground_Slam",
		"lean": 0.16,
		"icon": "res://assets/ui/abilities/shield_slam.png",
		"description": "Slam the tower shield down and shake everyone nearby.",
		"effect": {"kind": "melee_ring", "damage_scale": 2.2, "radius": 2.9,
			"stagger": 0.65},
		"cues": [{"at": 0.50, "cue": "ring"}],
	},
	{
		# Worn trinkets own the third slot. The ring is not held, so this skill
		# is available with any weapon loadout.
		"id": "dash",
		"name": "DASH",
		"item": "ring_dash",
		"slot": 2,
		"key": "SHIFT + 3",
		"stamina_cost": 10.0,
		"cooldown": 2.5,
		"duration": 1.0,
		"travel_seconds": 1.0,
		"speed_scale": 2.0,
		"move": false,
		"aim": true,
		"sound": "charge",
		"animation": "Sprint_Loop",
		"lean": 0.18,
		"icon": "res://assets/ui/abilities/dash.png",
		"description": "Sprint down the crosshair at double speed for one second.",
	},
	{
		"id": "energy_shield",
		"name": "ENERGY SHIELD",
		"item": "neck_shield",
		"slot": 2,
		"key": "SHIFT + 3",
		"stamina_cost": 8.0,
		"cooldown": 30.0,
		"duration": 0.9,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "ward",
		"move": true,
		"animation": "Staff_Fireball_Cast",
		"lean": -0.03,
		"icon": "res://assets/ui/abilities/energy_shield.png",
		"description": "A humming ward for one minute: half of every hit is paid in stamina.",
		# The ward is a timed body state, not a beat of damage: `absorb` is the
		# share of a hit moved onto stamina at `stamina_scale` times the cost.
		"effect": {"kind": "ward", "absorb": 0.5, "stamina_scale": 2.0,
			"seconds": 60.0},
		"cues": [{"at": 0.42, "cue": "ward"}],
	},
]

static var _icon_cache: Dictionary = {}
static var _by_id: Dictionary = {}
static var _by_item: Dictionary = {}


static func _static_init() -> void:
	for ability: Dictionary in ABILITIES:
		_by_id[str(ability.id)] = ability
		var item := str(ability.get("item", ""))
		var slot := int(ability.get("slot", 0))
		if not item.is_empty():
			_by_item["%s:%d" % [item, slot]] = ability


static func by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})


## A melee skill swings the equipped blade, so it can only be performed
## standing: the crouch overlay would replace the authored clip's arms.
static func is_melee(definition: Dictionary) -> bool:
	return MELEE_EFFECTS.has(str(definition.get("effect", {}).get("kind", "")))


## Skills that cannot be performed from a crouch. A blade swings over the whole
## skeleton, and a committed dash would slide a folded-over body along the
## floor; only the planted casts keep the crouch layer.
static func needs_standing(definition: Dictionary) -> bool:
	return is_melee(definition) or float(definition.get("speed_scale", 0.0)) > 0.0


## A committed step travels down the crosshair instead of the body's heading.
static func follows_aim(definition: Dictionary) -> bool:
	return bool(definition.get("aim", false))


static func by_item(item_id: String, slot: int = 0) -> Dictionary:
	return _by_item.get("%s:%d" % [item_id, slot], {})


## Compact wire code for the animation/replication scalars. Index 0 is the
## first authored ability, so a packed zero never means a real ability.
static func index_of(id: String) -> int:
	for index in ABILITIES.size():
		if str(ABILITIES[index].id) == id:
			return index
	return -1


static func by_index(index: int) -> Dictionary:
	if index < 0 or index >= ABILITIES.size():
		return {}
	return ABILITIES[index]


## The item the rig is visibly holding in the main hand. Session weapon keys
## change the held mode, so the granted skill follows the hands, not the
## paperdoll's stowed kit.
static func main_item(rig) -> String:
	if not is_instance_valid(rig):
		return ""
	match str(rig.weapon):
		"bow":
			return BOW_ITEMS[clampi(int(rig.bow_index), 0, BOW_ITEMS.size() - 1)]
		"dagger":
			return "dagger_iron"
		"sword":
			if bool(rig.staff_active):
				return STAFF_ITEMS[clampi(int(rig.staff_index), 0, STAFF_ITEMS.size() - 1)]
			return SWORD_ITEMS[clampi(int(rig.sword_index), 0, SWORD_ITEMS.size() - 1)]
		"dual":
			return SWORD_ITEMS[clampi(int(rig.sword_index), 0, 1)]
	return ""


static func off_item(rig) -> String:
	if not is_instance_valid(rig) or not bool(rig.get("shield_equipped")):
		return ""
	return SHIELD_ITEMS[clampi(int(rig.shield_variant), 0, SHIELD_ITEMS.size() - 1)]


## Both hands' current grants plus the worn trinket's grant. A slot with no
## grant resolves to an empty dict. An empty main hand keeps the legacy unarmed
## charge; a held weapon grants its skill only once it is anointed. The trinket
## slot prefers the necklace, then ring 1, then ring 2.
static func granted(rig) -> Array:
	if not is_instance_valid(rig):
		return [{}, {}, {}]
	var main := main_item(rig)
	var off := off_item(rig)
	var trinket := trinket_item(rig)
	var main_definition := by_id("charge") if main.is_empty() \
		else _anointed(rig, "main", by_item(main, 0))
	var off_definition := {} if off.is_empty() else _anointed(rig, "off", by_item(off, 1))
	return [main_definition, off_definition,
		by_item(trinket, 2) if not trinket.is_empty() else {}]


## A held weapon's skill is the altar's to give: the definition comes back only
## when the rig's `anointed` names it for that hand, so a stock piece - or a
## piece the hands changed to without being dressed again - grants nothing.
static func _anointed(rig, hand: String, definition: Dictionary) -> Dictionary:
	if definition.is_empty():
		return {}
	var hands: Variant = rig.get("anointed")
	if hands is Dictionary and str((hands as Dictionary).get(hand, "")) == str(definition.get("id", "")):
		return definition
	return {}


## The stock row a catalog piece shares: the class-and-index clamp `main_item`
## and `off_item` read off a dressed rig, applied to the catalog entry instead,
## so the salvage tier wakes into the skill its hands resolve to. "" for a piece
## that is not a bow, sword, dagger, staff or shield.
static func stock_item(entry: Dictionary) -> String:
	var index := int(entry.get("index", 0))
	match str(entry.get("category", "")):
		"bow":
			return BOW_ITEMS[clampi(index, 0, BOW_ITEMS.size() - 1)]
		"staff":
			return STAFF_ITEMS[clampi(index, 0, STAFF_ITEMS.size() - 1)]
		"shield":
			return SHIELD_ITEMS[clampi(index, 0, SHIELD_ITEMS.size() - 1)]
		"1h", "2h":
			match str(entry.get("kind", "")):
				"dagger":
					return "dagger_iron"
				"sword":
					return SWORD_ITEMS[clampi(index, 0, SWORD_ITEMS.size() - 1)]
	return ""


## The hand a catalog piece looses its skill from: a shield's is the off hand's,
## every other weapon's the main hand's.
static func hand_slot(entry: Dictionary) -> int:
	return 1 if str(entry.get("category", "")) == "shield" else 0


## The skill a catalog piece wakes into once it is anointed, or {} for a piece
## that has none (a focus, a trinket, salvage).
static func skill_for(entry: Dictionary) -> Dictionary:
	var stock := stock_item(entry)
	if stock.is_empty():
		return {}
	return by_item(stock, hand_slot(entry))


static func trinket_item(rig) -> String:
	if not is_instance_valid(rig):
		return ""
	var kit: Variant = rig.get("trinkets")
	if kit is Dictionary:
		return TrinketStats.ability_item(kit)
	return ""


static func definition_for(rig, slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {}
	return granted(rig)[slot]


static func damage_for(definition: Dictionary, rig) -> float:
	var item := str(definition.get("item", ""))
	if item.is_empty():
		# Unarmed charge does no damage; fall back to the held weapon so a
		# malformed definition cannot become a free heavy hit.
		item = main_item(rig)
	var base := float(ITEM_DAMAGE.get(item, 0.0))
	var effect: Dictionary = definition.get("effect", {})
	var damage := base * float(effect.get("damage_scale", 1.0))
	if not is_instance_valid(rig):
		return damage
	# Ranged trinkets scale arrows and spells; melee trinkets scale blade
	# skills and the backstab. Every scene reads this one function, so the
	# frontier, the arena and the delve cannot drift apart.
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot", "projectile":
			return damage * ranged_scale(rig)
		"melee_arc", "melee_ring", "backstab":
			return damage * melee_scale(rig)
	return damage


## The echo trinkets shorten every skill's cooldown.
static func cooldown_scale(rig) -> float:
	if not is_instance_valid(rig):
		return 1.0
	var stats: Variant = rig.get("trinket_stats")
	if stats is Dictionary:
		return TrinketStats.cooldown_scale(stats)
	return 1.0


static func ranged_scale(rig) -> float:
	if not is_instance_valid(rig) or not rig.has_method("ranged_scale"):
		return 1.0
	return float(rig.ranged_scale())


static func melee_scale(rig) -> float:
	if not is_instance_valid(rig) or not rig.has_method("melee_scale"):
		return 1.0
	return float(rig.melee_scale())


## The ward block of a definition, or {} for every other skill.
static func ward(definition: Dictionary) -> Dictionary:
	var effect: Dictionary = definition.get("effect", {})
	if str(effect.get("kind", "")) != "ward":
		return {}
	return effect


static func icon_texture(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := str(by_id(id).get("icon", ""))
	var texture: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_icon_cache[id] = texture
	return texture
