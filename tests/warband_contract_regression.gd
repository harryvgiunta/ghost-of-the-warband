extends SceneTree
## Phase 0 contract regression for Ghost of the Warband: the shared enums line up
## with the vocabulary this game already ships, the 10% overkill and downed rules
## answer at every boundary, the passive bubble scaler is one multiplier, and the
## warband roster, infinite stash, Cruor ledger and recruiter keep their promises.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const CruorScript = preload("res://scripts/warband/cruor_manager.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const StateScript = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://warband_contract_state.json"

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()

	check_slots()
	check_overkill()
	check_scaler()
	check_roster()
	check_gear_transfer(state, warband)
	check_weapon_sets(warband)
	check_souls()
	check_stash(state, warband)
	check_cruor(state, warband)
	check_vendor(state, warband)
	check_persistence(warband)

	_remove_test_save()
	print("WARBAND_CONTRACT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- slots -----------------------------------------------------------------

func check_slots() -> void:
	var ids: Array[String] = []
	for slot in Contracts.SLOT_ORDER:
		ids.append(Contracts.slot_id(slot))
	check(ids == Rules.SLOTS, "SlotType ids must be exactly EquipmentRules.SLOTS, got %s" % str(ids))
	check(Contracts.slot_id(Contracts.SlotType.BOOTS) == "feet", "BOOTS is the existing feet id")
	check(Contracts.slot_id(Contracts.SlotType.OFF_HAND) == "off", "OFF_HAND is the existing off id")
	check(Contracts.slot_from_id("ring2") == Contracts.SlotType.RING2, "ring2 round-trips")
	check(Contracts.slot_from_id("nope") == -1, "unknown ids are refused")
	check(Contracts.slot_label(Contracts.SlotType.RING1) == "Ring 1", "labels read as the design does")

	# Every catalog item must map onto exactly one weapon subtype.
	check(Contracts.weapon_subtype(StateScript.ITEMS["bow_short"]) == Contracts.WeaponSubType.BOW, "shortbow is a bow")
	check(Contracts.weapon_subtype(StateScript.ITEMS["sword_great"]) == Contracts.WeaponSubType.TWO_HAND, "greatsword is two-handed")
	check(Contracts.weapon_subtype(StateScript.ITEMS["dagger_iron"]) == Contracts.WeaponSubType.ONE_HAND, "dagger is one-handed")
	check(Contracts.weapon_subtype(StateScript.ITEMS["shield_buckler"]) == Contracts.WeaponSubType.SHIELD, "buckler is a shield")
	check(Contracts.weapon_subtype(StateScript.ITEMS["staff_fire"]) == Contracts.WeaponSubType.STAFF, "ember staff is a staff")
	check(Contracts.weapon_subtype(StateScript.ITEMS["focus_tome"]) == Contracts.WeaponSubType.TOME, "ash tome is a tome")
	check(Contracts.weapon_subtype(StateScript.ITEMS["focus_skull"]) == Contracts.WeaponSubType.SKULL, "bone skull is a skull")
	check(Contracts.weapon_subtype(StateScript.ITEMS["ring_copper"]) == Contracts.WeaponSubType.NONE, "a ring is not a weapon")
	for item_id in StateScript.ITEMS:
		var item: Dictionary = StateScript.ITEMS[item_id]
		var subtype := Contracts.weapon_subtype(item)
		if str(item.get("category", "")) == "focus":
			check(subtype in [Contracts.WeaponSubType.SKULL, Contracts.WeaponSubType.TOME],
				"%s must be a skull or a tome" % item_id)
	check(Contracts.two_handed_item(StateScript.ITEMS["sword_great"]), "2H leaves no off hand")
	check(not Contracts.two_handed_item(StateScript.ITEMS["shield_buckler"]), "a shield is not two-handed")

# --- 10% overkill ----------------------------------------------------------

func check_overkill() -> void:
	var clean := Contracts.resolve_damage(100.0, 100.0, 100.0)
	check(int(clean["state"]) == Contracts.HealthState.DOWNED, "an exactly-lethal hit downs, never kills")
	check(bool(clean["downed"]) and not bool(clean["died"]), "exactly lethal sets downed")
	check(is_equal_approx(float(clean["overkill"]), 0.0), "exactly lethal is zero overkill")

	var light := Contracts.resolve_damage(100.0, 100.0, 105.0)
	check(int(light["state"]) == Contracts.HealthState.DOWNED, "-5% overkill downs")
	var edge := Contracts.resolve_damage(100.0, 100.0, 110.0)
	check(int(edge["state"]) == Contracts.HealthState.DOWNED, "exactly -10% still downs")
	check(is_equal_approx(float(edge["overkill"]), 10.0), "the edge overkill is 10")
	var heavy := Contracts.resolve_damage(100.0, 100.0, 110.01)
	check(int(heavy["state"]) == Contracts.HealthState.DEAD, "more than -10% kills outright")
	check(bool(heavy["died"]) and not bool(heavy["downed"]), "heavy overkill is a death")

	var survived := Contracts.resolve_damage(100.0, 100.0, 40.0)
	check(int(survived["state"]) == Contracts.HealthState.ALIVE, "a non-lethal hit stays alive")
	check(is_equal_approx(float(survived["health"]), 60.0), "non-lethal health is subtracted once")
	check(not bool(Contracts.resolve_damage(100.0, 100.0, 0.0)["ok"]), "a zero hit is not a hit")

	# The same rule measured against a bigger pool: 10% of 100 is 10, not 10% of
	# the damage. A 120-damage hit on 50 max health overkills by 70 and kills.
	var big := Contracts.resolve_damage(50.0, 50.0, 120.0)
	check(int(big["state"]) == Contracts.HealthState.DEAD, "threshold scales with max health")
	check(Contracts.finishes_downed(100.0, 10.0) == false, "a light blow cannot finish a downed body")
	check(Contracts.finishes_downed(100.0, 10.5) == true, "a heavy blow finishes a downed body")
	check(Contracts.REVIVE_CHANNEL_SECONDS == 5.0, "the revive channel is five seconds")
	check(is_equal_approx(Contracts.PASSIVE_DAMAGE_MULTIPLIER, 0.1), "the far fight runs at 10%")
	check(is_equal_approx(Contracts.damage_multiplier(Contracts.CombatSimState.ACTIVE), 1.0), "active is 100%")
	check(is_equal_approx(Contracts.damage_multiplier(Contracts.CombatSimState.PASSIVE_SIM), 0.1), "passive is 10%")

# --- bubble scaler ---------------------------------------------------------

func check_scaler() -> void:
	Damage.reset()
	var body := Node3D.new()
	root.add_child(body)
	check(is_equal_approx(Damage.scale(100.0, body), 100.0), "an untracked body is not nerfed")
	Damage.set_sim_state(body, Contracts.CombatSimState.PASSIVE_SIM)
	check(is_equal_approx(Damage.scale(100.0, body), 10.0), "a passive body takes 10%")
	check(Damage.is_passive(body), "passive reads back")
	Damage.set_sim_state(body, Contracts.CombatSimState.ACTIVE)
	check(is_equal_approx(Damage.scale(100.0, body), 100.0), "re-entering the bubble restores 100%")
	check(Damage.registered_count() == 0, "ACTIVE bodies leave no registry entry")
	Damage.set_sim_state(body, Contracts.CombatSimState.PASSIVE_SIM)
	body.free()
	Damage.prune()
	check(Damage.registered_count() == 0, "prune drops a freed body")
	Damage.reset()

# --- gear hand-offs --------------------------------------------------------

## The stash is one pool: a piece another mercenary wears must be transferable,
## a piece can move between slots on the same body, and a pickup can snap into a
## hand when it is the better blade. Nothing in these moves may lose an item.
func check_gear_transfer(_state, warband) -> void:
	warband.reset_state()
	var roster = warband.roster
	var stash = warband.stash
	var ash: int = warband.add_mercenary("Ash")
	var corvin: int = warband.add_mercenary("Corvin")
	# Only the rescuer's shiv exists: the exact shape of the tutorial.
	roster.equip(corvin, "main", "dagger_ironwood")
	var before_total: int = warband.total_value()

	var hand: Dictionary = warband.equip_merc(ash, "main", "dagger_ironwood")
	check(bool(hand.get("ok", false)), "a worn dagger can be handed to another body: %s"
		% str(hand.get("message", "")))
	check(str(roster.equipped_of(ash).get("main", "")) == "dagger_ironwood",
		"the receiving body now holds it")
	check(str(roster.equipped_of(corvin).get("main", "")) == "",
		"the giver no longer wears it")
	check(warband.total_value() == before_total, "a hand-off loses no value")

	# Moving the same piece between slots on one body is legal too.
	var moved: Dictionary = warband.equip_merc(ash, "off", "dagger_ironwood")
	check(bool(moved.get("ok", false)), "the same dagger moves to the off hand")
	check(str(roster.equipped_of(ash).get("main", "")) == "",
		"the main hand is empty after the move")
	check(str(roster.equipped_of(ash).get("off", "")) == "dagger_ironwood",
		"the off hand holds it")

	# An unowned piece is still refused.
	var unowned: Dictionary = warband.equip_merc(ash, "main", "sword_great")
	check(unowned.get("ok") == false, "a piece nobody owns is refused")
	check(str(roster.equipped_of(ash).get("off", "")) == "dagger_ironwood",
		"a refused equip leaves the body alone")

	# A pickup snaps into a hand only when it beats what is already there.
	stash.add("sword_short", 1)
	var empty_hand: Dictionary = warband.auto_equip(ash, "sword_short")
	check(bool(empty_hand.get("ok", false)), "a looted blade fills an empty main hand")
	check(str(roster.equipped_of(ash).get("main", "")) == "sword_short",
		"the shortsword is worn")
	stash.add("dagger_iron", 1)
	var worse: Dictionary = warband.auto_equip(ash, "dagger_iron")
	check(worse.get("ok") == false, "a piece no better than the worn one stays in the stash")
	check(warband.stash.pooled_count("dagger_iron") == 1, "and it is still owned")
	stash.add("sword_arming", 1)
	var better: Dictionary = warband.auto_equip(ash, "sword_arming")
	check(bool(better.get("ok", false)), "a better blade goes straight into the hand")
	check(str(roster.equipped_of(ash).get("main", "")) == "sword_arming",
		"the arming sword replaced the shortsword")
	check(warband.stash.pooled_count("sword_short") == 1,
		"the displaced shortsword returns to the pool")
	check(str(roster.equipped_of(ash).get("off", "")) == "dagger_ironwood",
		"the off hand is untouched by a main-hand upgrade")

	# Unarmed bodies get the first thing they pick up.
	var bram: int = warband.add_mercenary("Bram")
	stash.add("bow_short", 1)
	var first: Dictionary = warband.auto_equip(bram, "bow_short")
	check(bool(first.get("ok", false)), "an unarmed body takes the first weapon it loots")
	check(str(roster.equipped_of(bram).get("main", "")) == "bow_short", "the bow is in hand")

# --- souls -----------------------------------------------------------------

## `TAB`'s two weapon sets: a body carries two complete pairs and exactly one is
## in its hands. The swap alternates, the set being left remembers what it held,
## both sets count as worn, and both survive a save.
func check_weapon_sets(warband) -> void:
	warband.reset_state()
	var roster = warband.roster
	var stash = warband.stash
	var merc: int = warband.add_mercenary("Tabbard")
	stash.add("bow_twig", 1)
	stash.add("dagger_ironwood", 1)
	stash.add("shield_wood", 1)

	check(roster.active_weapon_set(merc) == 0, "a fresh body carries Set 1")
	check(RosterScript.WEAPON_SET_COUNT == 2, "there are two weapon sets")
	var refusal: Dictionary = warband.swap_weapon_set(merc)
	check(not bool(refusal.get("ok", false)), "both sets empty: the swap is refused")
	check(String(refusal.get("message", "")).begins_with("Both weapon sets are empty"),
		"and it says why")

	check(bool(warband.equip_merc(merc, "main", "bow_twig").get("ok", false)),
		"the twig bow goes into the active set")
	check(str(roster.equipped_of(merc).get("main", "")) == "bow_twig",
		"Set 1 is what the hands carry")
	var swap: Dictionary = warband.swap_weapon_set(merc)
	check(bool(swap.get("ok", false)), "one press takes the body to Set 2")
	check(roster.active_weapon_set(merc) == 1, "Set 2 is the active set")
	check(str(roster.equipped_of(merc).get("main", "")) == "",
		"Set 2 starts empty, so the hands are empty")
	check(roster.weapon_set_pair(merc, 0).get("main", "") == "bow_twig",
		"Set 1 kept the bow the swap put away")

	check(bool(warband.equip_merc(merc, "main", "dagger_ironwood").get("ok", false)),
		"a blade equipped now lands in Set 2")
	check(bool(warband.equip_merc(merc, "off", "shield_wood").get("ok", false)),
		"and the off hand of Set 2 takes the shield")
	var back: Dictionary = warband.swap_weapon_set(merc)
	check(bool(back.get("ok", false)) and roster.active_weapon_set(merc) == 0,
		"the next press comes back to Set 1")
	check(str(roster.equipped_of(merc).get("main", "")) == "bow_twig"
			and str(roster.equipped_of(merc).get("off", "")) == "",
		"Set 1's pair is in the hands again")
	check(roster.weapon_set_label(merc, 1) == "Ironwood Shiv + Wooden Shield",
		"Set 2 is named by what it holds")

	# Both pairs are the body's gear: the stash sees them, the value counts them,
	# and a hand-off can take a piece out of the set the hands are not carrying.
	var worn_ids: Array[String] = []
	for entry in roster.worn_entries(merc):
		worn_ids.append(str(entry.get("item", "")))
	check(worn_ids.has("bow_twig") and worn_ids.has("dagger_ironwood")
			and worn_ids.has("shield_wood"),
		"worn entries list both weapon sets")
	check(warband.gear_value(merc) > 0, "the value of a body counts both sets")
	var rows: Array[Dictionary] = stash.rows(roster, {})
	var dagger_row := {}
	for row in rows:
		if str(row.get("item_id", "")) == "dagger_ironwood":
			dagger_row = row
	check(int(dagger_row.get("worn", []).size()) == 1,
		"the stash row knows a piece waits in the inactive set")
	var other: int = warband.add_mercenary("Borrower")
	var hand_off: Dictionary = warband.equip_merc(other, "main", "dagger_ironwood")
	check(bool(hand_off.get("ok", false)),
		"a piece in the inactive set can still be handed over")
	check(roster.weapon_set_pair(merc, 1).get("main", "") == "",
		"and it leaves the set it was waiting in")

	# A save carries both pairs and the set that is up.
	var saved: Dictionary = warband.to_dict()
	var fresh = RosterScript.new()
	fresh.from_dict(saved.get("roster", {}))
	check(fresh.active_weapon_set(merc) == 0, "the active set survives a save")
	check(fresh.weapon_set_pair(merc, 0).get("main", "") == "bow_twig",
		"Set 1 survives a save")
	check(fresh.weapon_set_pair(merc, 1).get("off", "") == "shield_wood",
		"Set 2 survives a save")
	# A record written before the sets existed loads with its pair in Set 1.
	var legacy = RosterScript.new()
	var old_id: int = legacy.add_record({"id": 41, "name": "Old", "health": 100.0,
		"max_health": 100.0, "state": 0, "deployed": false, "downed_seconds": 0.0,
		"equipped": {"main": "sword_short", "off": "shield_buckler"}})
	check(legacy.weapon_set_pair(old_id, 0).get("main", "") == "sword_short",
		"a pre-set record puts the pair in its hands into Set 1")
	check(legacy.weapon_set_pair(old_id, 1).get("main", "") == "",
		"and Set 2 starts empty")
	check(str(legacy.equipped_of(old_id).get("off", "")) == "shield_buckler",
		"the legacy pair is what the body holds")

func check_souls() -> void:
	var RouterScript = preload("res://scripts/warband/soul_router.gd")
	var router = RouterScript.new()
	var nodes: Array[Node3D] = []
	for index in 3:
		var node := Node3D.new()
		root.add_child(node)
		nodes.append(node)
		router.register_body(10 + index, node, "Body %d" % index)
	check(router.body_ids() == [10, 11, 12], "bodies are registered in id order")

	var entered := router.request_transfer(1, 10)
	check(entered["ok"], "peer one enters body ten")
	check(router.occupied_by(10) == 1, "the lock names the peer")
	check(router.body_of(1) == 10, "the peer knows its body")
	var stolen := router.request_transfer(2, 10)
	check(stolen["ok"] == false and str(stolen["reason"]) == RouterScript.REASON_OCCUPIED,
		"a second peer cannot enter an occupied body")
	check(router.body_of(2) == -1, "a refused transfer leaves the second peer bodiless")
	check(router.request_transfer(2, 11)["ok"], "peer two takes a free body")

	var move := router.request_transfer(1, 12)
	check(move["ok"] and int(move["previous_body_id"]) == 10, "a move releases the old body")
	check(router.occupied_by(10) == 0, "the old body is free")
	var back := router.cycle(1, -1)
	check(back["ok"] and router.body_of(1) == 10, "cycling backwards takes the lower free body")
	var forward := router.cycle(2, 1)
	check(forward["ok"] and router.body_of(2) == 12, "cycling forwards takes the higher free body")

	# A downed body keeps its soul - the player crawls it and an ally picks them up
	# - but nobody may hop *into* one.
	router.set_body_state(12, Contracts.HealthState.DOWNED)
	check(router.body_of(2) == 12, "a downed body keeps its soul")
	check(router.request_transfer(1, 12)["ok"] == false, "a downed body cannot be entered")
	# A death is what frees the peer.
	router.set_body_state(12, Contracts.HealthState.DEAD)
	check(router.body_of(2) == -1, "a dead body ejects its soul")
	check(router.body_ids().has(12), "a dead body is still registered for the HUD")
	check(router.possessable_ids() == [11], "only living free bodies are possessable")

	# The last survivor keeps its body rather than being cycled away.
	router.release_peer(2)
	router.release_peer(1)
	check(router.request_transfer(3, 11)["ok"], "peer three takes the last free body")
	router.set_body_state(10, Contracts.HealthState.DEAD)
	var only := router.cycle(3, 1)
	check(only["ok"] and router.body_of(3) == 11, "the only standing body is not cycled away")

	router.clear()
	for node in nodes:
		node.free()
	check(router.body_ids().is_empty(), "clear empties the registry")

# --- roster ----------------------------------------------------------------

func check_roster() -> void:
	var roster = RosterScript.new()
	var a := roster.create("Aldous")
	var b := roster.create("Brine")
	check(roster.count() == 2, "two bodies")
	check(roster.health_of(a) == Contracts.BASE_MAX_HEALTH, "identical base stats")
	check(roster.max_health_of(a) == roster.max_health_of(b), "no mercenary is born better")
	check(roster.alive_count() == 2, "both alive")

	var down := roster.apply_damage(a, 100.0)
	check(int(down["state"]) == Contracts.HealthState.DOWNED, "lethal hit downs a mercenary")
	check(roster.is_downed(a), "the roster knows it is downed")
	check(roster.can_possess(a) == false, "a downed body cannot be entered")
	check(roster.alive_ids().has(a) == false, "downed is not in the living list")
	check(roster.apply_damage(a, 5.0)["died"] == false, "chip damage does not finish a downed body")
	var finish := roster.apply_damage(a, 25.0)
	check(bool(finish["died"]), "a 25% blow finishes a downed body")
	check(roster.is_dead(a), "and it is dead")
	check(roster.revive(a) == false, "the dead do not revive")

	var c := roster.create("Cael")
	var hurt := roster.apply_damage(c, 100.0)
	check(int(hurt["state"]) == Contracts.HealthState.DOWNED, "c downed")
	check(roster.revive(c), "downed revives")
	check(is_equal_approx(roster.health_of(c),
		Contracts.BASE_MAX_HEALTH * Contracts.REVIVE_HEALTH_FRACTION),
		"revive restores a twentieth of the pool")
	check(roster.apply_damage(c, 200.0)["died"], "a body at half health can be overkilled")

	# Deployment cap X.
	var cap_roster = RosterScript.new()
	var ids: Array[int] = []
	for index in 10:
		ids.append(cap_roster.create("M%d" % index))
	var fielded := cap_roster.deploy(ids, Contracts.MAX_DEPLOYMENT_CAP)
	check(fielded.size() == Contracts.MAX_DEPLOYMENT_CAP, "deployment is capped at X")
	check(cap_roster.deployed_count() == Contracts.MAX_DEPLOYMENT_CAP, "deployed count agrees")
	var ninth := cap_roster.create("Ninth")
	var refusal := cap_roster.set_deployed(ninth, true, Contracts.MAX_DEPLOYMENT_CAP)
	check(refusal["ok"] == false, "a ninth body is refused at the cap")
	var stand_down := cap_roster.set_deployed(ninth, false, Contracts.MAX_DEPLOYMENT_CAP)
	check(stand_down["ok"] == true, "standing down always works")

	# Gear is the only differentiator, and hand rules hold.
	var gear_roster = RosterScript.new()
	var d := gear_roster.create("Dorn")
	var two_hand := gear_roster.equip(d, "main", "sword_great")
	check(two_hand["ok"], "greatsword equips")
	gear_roster.equip(d, "off", "shield_buckler")
	check(gear_roster.equipped_of(d)["main"] == "", "a shield returns the two-handed main to the stash")
	check(gear_roster.equipped_of(d)["off"] == "shield_buckler", "the shield takes the off hand")
	var swap := gear_roster.equip(d, "main", "sword_great")
	check(swap["ok"], "re-equipping the same 2H is a no-op")
	gear_roster.unequip(d, "main")
	gear_roster.equip(d, "main", "sword_short")
	var pair := gear_roster.equip(d, "off", "dagger_iron")
	check(pair["ok"], "dual wield equips")
	check(gear_roster.equipped_of(d)["off"] == "dagger_iron", "off hand holds the dagger")
	var great := gear_roster.equip(d, "main", "sword_great")
	check(great["ok"] and str(great["displaced"].get("off", "")) == "dagger_iron",
		"a two-hander displaces the off hand into the stash")
	check(gear_roster.equip(d, "ring1", "ring_copper")["ok"], "a ring fills ring 1")
	check(gear_roster.equip(d, "ring1", "ring_silver")["ok"], "a ring swaps")
	check(gear_roster.equip(d, "head", "bow_short")["ok"] == false, "a bow cannot be worn on the head")

	# Persistence round-trip keeps ids, gear and states.
	gear_roster.set_deployed(d, true, 8)
	var saved := gear_roster.to_dict()
	var loaded = RosterScript.new()
	loaded.from_dict(saved)
	check(loaded.count() == gear_roster.count(), "records survive a round-trip")
	check(loaded.equipped_of(d)["main"] == "sword_great", "gear survives a round-trip")
	check(loaded.deployed_ids().has(d), "deployment survives a round-trip")
	check(loaded.create("Next") > d, "the id counter advances past saved ids")

# --- stash -----------------------------------------------------------------

func check_stash(state, warband) -> void:
	warband.reset_state()
	var roster = warband.roster
	var stash = warband.stash
	check(stash.pooled_total() == 0, "a fresh stash is empty")
	stash.add("ring_copper", 2)
	stash.add("sword_great", 1)
	stash.add("bow_short", 1)
	check(stash.pooled_total() == 4, "the pool counts every copy")
	check(stash.remove("ring_copper", 1), "removing one copy works")
	check(stash.pooled_count("ring_copper") == 1, "one copy left")
	check(stash.remove("ring_copper", 5) == false, "cannot remove more than the pool holds")

	var merc_id : int = warband.add_mercenary("Edda")
	var equip : Dictionary = warband.equip_merc(merc_id, "main", "sword_great")
	check(equip["ok"], "equipping from the collective stash works")
	check(stash.pooled_count("sword_great") == 0, "the worn piece leaves the pool")
	var rows: Array[Dictionary] = warband.stash.rows(roster, warband.cruor.brands)
	var great_row: Dictionary = {}
	for row in rows:
		if str(row["item_id"]) == "sword_great":
			great_row = row
	check(not great_row.is_empty(), "a worn item is still a stash row")
	check(int(great_row["total"]) == 1 and int(great_row["pooled"]) == 0, "worn only")
	check((great_row["worn"] as Array).size() == 1, "the row names one wearer")
	check(str(((great_row["worn"] as Array)[0])["merc_name"]) == "Edda", "the tag names the mercenary")
	check(rows[0]["item_id"] == "sword_great", "rows sort highest value first (%s)" % rows[0]["item_id"])
	check(WarbandStash.value_of("sword_great") > WarbandStash.value_of("ring_copper"), "greatsword is worth more")

	# Swapping a worn piece returns the old one to the pool instead of losing it.
	stash.add("bow_short", 1)
	warband.equip_merc(merc_id, "main", "bow_short")
	check(stash.pooled_count("sword_great") == 1, "the displaced greatsword returns to the pool")
	check(stash.pooled_count("bow_short") == 1, "the bow left the pool")

	# Unequip round-trips.
	warband.unequip_merc(merc_id, "main")
	check(stash.pooled_count("bow_short") == 2, "unequipping returns the piece")

	# The same id can be both worn and spare: the row must count both.
	warband.equip_merc(merc_id, "main", "bow_short")
	var mixed: Dictionary = {}
	for row in warband.stash.rows(roster, warband.cruor.brands):
		if str(row["item_id"]) == "bow_short":
			mixed = row
	check(int(mixed["pooled"]) == 1, "a worn-and-spared id keeps its pooled count")
	check((mixed["worn"] as Array).size() == 1, "and keeps its wearer tag")
	check(int(mixed["total"]) == 2, "the row total is pooled plus worn")

	# The stash is infinite: 600 copies in, all readable and sorted.
	for index in 600:
		stash.add("ring_copper", 1)
	check(stash.pooled_count("ring_copper") == 601, "the stash is unbounded (%d)" % stash.pooled_count("ring_copper"))
	var big: Array[Dictionary] = warband.stash.rows(roster, warband.cruor.brands)
	check(big.size() == 3, "rows are per item id, not per copy")
	check(int(big[0]["value"]) >= int(big[big.size() - 1]["value"]), "the value sort is monotone")

# --- cruor -----------------------------------------------------------------

func check_cruor(state, warband) -> void:
	var cruor = warband.cruor
	check(cruor.total() == 0, "no essence at the start")
	cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 10)
	check(cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == 10, "essence banks")
	var one : Dictionary = cruor.distill(Contracts.CruorTier.T1_RITUAL_TALLOW)
	check(one["ok"], "5 T1 distils")
	check(cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == 5, "five spent, five left")
	check(cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE) == 1, "one Black Bile produced")
	var top : Dictionary = cruor.distill(Contracts.CruorTier.T5_CRYSTALLIZED_SIN)
	check(top["ok"] == false, "Tier 5 cannot distil further")

	# 125 trash Tier 1s are 1 Tier 4 (the design's own arithmetic through 5:1).
	var ladder = CruorScript.new()
	ladder.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 125)
	ladder.distill_all(Contracts.CruorTier.T1_RITUAL_TALLOW)   # 25 T2
	check(ladder.tier_count(Contracts.CruorTier.T2_BLACK_BILE) == 25, "125 T1 -> 25 T2")
	ladder.distill_all(Contracts.CruorTier.T2_BLACK_BILE)     # 5 T3
	check(ladder.tier_count(Contracts.CruorTier.T3_COAGULATED_CRUOR) == 5, "25 T2 -> 5 T3")
	ladder.distill_all(Contracts.CruorTier.T3_COAGULATED_CRUOR)  # 1 T4
	check(ladder.tier_count(Contracts.CruorTier.T4_STIGMATIC_RESIN) == 1, "5 T3 -> 1 T4")

	# Unbinding a spare magic item renders it into T1-T3 and destroys it.
	var stash = warband.stash
	warband.reset_state()
	stash = warband.stash
	cruor = warband.cruor
	stash.add("ring_silver", 1)
	check(cruor.can_unbind(stash, "ring_silver"), "silver ring is worth rendering")
	var rendered : Dictionary = cruor.unbind(stash, "ring_silver")
	check(rendered["ok"], "unbind succeeds")
	check(stash.pooled_count("ring_silver") == 0, "unbinding destroys the item")
	check(cruor.tier_count(Contracts.CruorTier.T1_RITUAL_TALLOW) == 5, "a 95-price ring yields 5 Tallow")
	check(cruor.unbind(stash, "ring_silver")["ok"] == false, "the altar cannot eat what you do not own")
	stash.add("dagger_ironwood", 1)
	check(cruor.can_unbind(stash, "dagger_ironwood") == false, "junk below the magic floor is refused")

	# A worn item is not spare: the altar only eats what sits in the pool.
	var merc_id : int = warband.add_mercenary("Fenwick")
	stash.add("ring_blood", 1)
	warband.equip_merc(merc_id, "ring1", "ring_blood")
	check(cruor.can_unbind(stash, "ring_blood") == false, "a worn piece is not spare")

	# Branding.
	cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 3)
	var brand : Dictionary = cruor.brand("bow_short", Contracts.CruorTier.T2_BLACK_BILE)
	check(brand["ok"], "a bow takes a brand: %s" % str(brand.get("message", "")))
	check(cruor.brand_of("bow_short")["ability"] == "arrow_barrage", "a bow brands to Arrow Barrage")
	check(cruor.tier_count(Contracts.CruorTier.T2_BLACK_BILE) == 0, "the brand burned three Black Bile")
	check(cruor.brand_line("bow_short") != "", "a branded piece has a tooltip line")
	var broke : Dictionary = cruor.brand("sword_short", Contracts.CruorTier.T3_COAGULATED_CRUOR)
	check(broke["ok"] == false, "branding without essence is refused")
	cruor.add(Contracts.CruorTier.T3_COAGULATED_CRUOR, 2)
	var reroll : Dictionary = cruor.brand("bow_short", Contracts.CruorTier.T3_COAGULATED_CRUOR)
	check(reroll["ok"] and bool(reroll["reroll"]), "rebranding rerolls the same piece")
	check(int(cruor.brand_of("bow_short")["rerolls"]) == 1, "the reroll is counted")
	check(cruor.brand("shield_buckler", Contracts.CruorTier.T3_COAGULATED_CRUOR)["ok"] == false,
		"a shield is not a vessel")
	check(Branded.for_subtype(Contracts.WeaponSubType.SKULL) == "hellfire_cone", "skulls brand to Hellfire Cone")
	check(Branded.power(0) < Branded.power(4), "tier raises the power of a brand")

	# The brand raises the row's value, so it sorts above plain steel.
	check(WarbandStash.value_of("bow_short", cruor.brand_of("bow_short")) > WarbandStash.value_of("bow_short"),
		"a brand adds value")

# --- recruiter -------------------------------------------------------------

func check_vendor(state, warband) -> void:
	warband.reset_state()
	state.credits = 1000
	# The first eight oaths are free: the recruiter is garrisoning a warband, not
	# selling one, and eight bodies is the deployment cap itself.
	check(warband.hire_cost() == 0, "the first oath is free")
	var hired : Dictionary = warband.hire("Grist")
	check(hired["ok"], "hiring swears a body: %s" % str(hired.get("message", "")))
	check(warband.roster.count() == 1, "the body joins the warband")
	check(int(hired["cost"]) == 0, "and quotes nothing")
	check(int(state.credits) == 1000, "a free oath spends no gold")

	# Past the free eight the old curve is back, and every oath still costs more
	# than the one before it.
	while warband.roster.count() < VendorScript.FREE_HIRES:
		warband.add_mercenary("Free %d" % warband.roster.count())
	warband.deployment_cap = VendorScript.FREE_HIRES + 1
	var first_paid : int = warband.hire_cost()
	check(first_paid == VendorScript.HIRE_BASE_COST + VendorScript.HIRE_STEP_COST * VendorScript.FREE_HIRES,
		"the ninth oath is priced again (%d)" % first_paid)
	var paid : Dictionary = warband.hire("Hale")
	check(paid["ok"], "a priced oath goes through while there is room")
	check(int(state.credits) == 1000 - first_paid, "exactly the quoted price is spent")
	check(warband.hire_cost() > first_paid, "the next body costs more")

	# The cap is hard.
	warband.deployment_cap = VendorScript.FREE_HIRES
	var full : Dictionary = warband.hire("Ilsa")
	check(full["ok"] == false, "the cap refuses another body")
	check(warband.roster.count() == VendorScript.FREE_HIRES + 1, "the roster stays where it was")

	# A poor purse buys nothing, once the free eight are behind it.
	state.credits = 5
	warband.deployment_cap = VendorScript.FREE_HIRES + 4
	var sworn: int = warband.roster.count()
	var poor : Dictionary = warband.hire("Jory")
	check(poor["ok"] == false, "no gold, no blade")
	check(warband.roster.count() == sworn, "the roster is unchanged")
	state.credits = 99999
	warband.deployment_cap = Contracts.MAX_DEPLOYMENT_CAP

# --- persistence -----------------------------------------------------------

func check_persistence(warband) -> void:
	warband.reset_state()
	warband.add_mercenary("Kestrel")
	warband.stash.add("ring_blood", 2)
	warband.cruor.add(Contracts.CruorTier.T4_STIGMATIC_RESIN, 3)
	warband.cruor.add(Contracts.CruorTier.T5_CRYSTALLIZED_SIN, 1)
	warband.cruor.add(Contracts.CruorTier.T3_COAGULATED_CRUOR, 2)
	warband.cruor.brand("sword_arming", Contracts.CruorTier.T3_COAGULATED_CRUOR)
	warband.save_state()
	var before : String = warband.describe()
	var merc_count : int = warband.roster.count()
	var essence : int = warband.cruor.total()
	warband.reset_state()
	check(warband.roster.count() == 0, "reset clears the roster")
	var loaded: bool = warband.load_state()
	check(loaded, "a saved warband loads")
	check(warband.roster.count() == merc_count, "mercenaries survive")
	check(warband.stash.pooled_count("ring_blood") == 2, "the stash survives")
	check(warband.cruor.total() == essence, "the essence survives")
	check(warband.cruor.brand_of("sword_arming")["ability"] == "rending_strike", "the brand survives")
	check(warband.describe() == before, "the saved card round-trips exactly")
	check(warband.total_value() > 0, "the warband has a worth")
