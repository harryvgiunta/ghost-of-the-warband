extends SceneTree
## Worn trinkets: the catalog rows, slot legality, additive aggregation, the
## derived maxima and rates, the amulet/dash grants in the third ability slot,
## the Energy Shield ward's stamina swap and the skull refills.
##
## The numbers here are the contract: +25 health is 125 on the bar, +10% melee
## is 33 on a 30-damage shortsword, and half a 40-point hit costs 40 stamina.

const State = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const Stats = preload("res://scripts/trinket_stats.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const Actor = preload("res://scripts/arena_actor.gd")
const Combat = preload("res://scripts/combat.gd")
const Stamina = preload("res://scripts/stamina.gd")
const Hud = preload("res://scripts/hud.gd")
const ArenaHud = preload("res://scripts/arena_hud.gd")
const DelveHud = preload("res://scripts/delve_hud.gd")

const TEST_SAVE := "user://trinkets_regression_state.json"
## Unarmored: an empty piece map wears nothing on either channel, so the ward
## and damage arithmetic below is measured against the raw hit.
const ZERO_ARMOR := {}

var checks := 0
var failures := 0
## Rigs and bodies need a real parent inside the tree for their `_ready`.
var scene: Node3D


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TRINKETS_FAIL  ", message)


func pause(seconds: float) -> void:
	await create_timer(seconds).timeout


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, false, "Trinket", at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor


func rig_for(main_id: String, off_id: String, trinkets: Dictionary) -> Node3D:
	var host := fighter(scene, 0, Vector3.ZERO)
	host.rig.apply_loadout(State.build_loadout(main_id, off_id, ZERO_ARMOR, trinkets))
	return host


func run() -> void:
	_remove(TEST_SAVE)
	scene = Node3D.new()
	root.add_child(scene)
	_test_catalog()
	_test_vendor_stock()
	_test_aggregation()
	_test_slot_routing()
	_test_persistence()
	await _test_derived_stats()
	_test_grants()
	await _test_ward()
	await _test_kill_refills()
	await _test_hud_tiles()
	_remove(TEST_SAVE)
	print("TRINKETS_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _test_catalog() -> void:
	var state = root.get_node("PlayerState")
	var ring_ids := [
		"ring_dash", "ring_health", "ring_ranged", "ring_melee", "ring_swift",
		"ring_haste", "ring_vigor", "ring_tide", "ring_ward", "ring_bounty",
		"ring_thrower", "ring_echo", "ring_ironhide", "ring_grit",
	]
	for item_id: String in ring_ids:
		check(State.ITEMS.has(item_id), "%s is in the catalog" % item_id)
		var item: Dictionary = State.ITEMS.get(item_id, {})
		check(str(item.get("category", "")) == "jewelry" and str(item.get("slot", "")) == "ring",
			"%s is ring jewelry" % item_id)
		check(Rules.allowed(item, "ring1") and Rules.allowed(item, "ring2"),
			"%s fits both ring slots" % item_id)
		check(not Stats.effect_rows(item_id).is_empty() or not Stats.grant_for(item_id).is_empty(),
			"%s advertises its effect" % item_id)
		check(not state.item_stat_rows(item_id).is_empty(), "%s has inspector rows" % item_id)
		check(not state.item_compact_stats(item_id).contains("NO EFFECT"),
			"%s is not labelled inert" % item_id)
	var amulet: Dictionary = State.ITEMS.get("neck_shield", {})
	check(str(amulet.get("category", "")) == "jewelry" and Rules.allowed(amulet, "neck"),
		"The amulet is neck jewelry")
	for skull_id: String in ["focus_skull_life", "focus_skull_death"]:
		var skull: Dictionary = State.ITEMS.get(skull_id, {})
		check(Rules.allowed(skull, "off"), "%s is an off-hand focus" % skull_id)
		check(str(skull.get("focus", "")) == skull_id.trim_prefix("focus_"),
			"%s carries its own focus silhouette" % skull_id)
	# The flavor jewelry keeps its no-effect label.
	check(Stats.effect_rows("ring_copper").is_empty(), "A plain copper ring stays inert")
	check(state.item_compact_stats("ring_copper") == "NO EFFECT", "The plain ring says so")
	# Every catalog item still resolves a legal slot where it claims one.
	for item_id: String in State.ITEMS:
		var item: Dictionary = State.ITEMS.get(item_id, {})
		var slot := str(item.get("slot", ""))
		if not slot in Rules.SLOTS:
			# Jewelry declares neck/ring; the paperdoll uses neck/ring1/ring2.
			continue
		check(Rules.allowed(item, slot), "%s is legal in its declared slot" % item_id)


func _test_vendor_stock() -> void:
	var stock: Array = State.VENDORS[2].stock
	for item_id: String in ["neck_shield", "focus_skull_life", "focus_skull_death", "ring_dash",
			"ring_health", "ring_ranged", "ring_melee", "ring_grit"]:
		check(stock.has(item_id), "Quartermaster Vey sells %s" % item_id)
	for item_id: String in stock:
		check(State.ITEMS.has(item_id), "Every stocked id is a real catalog item: %s" % item_id)
	var largest := 0
	for vendor: Dictionary in State.VENDORS:
		largest = maxi(largest, (vendor.stock as Array).size())
	check(largest == stock.size(), "The trinket list is the longest keeper stock")
	check(State.INVENTORY_CAPACITY >= 15, "The backpack size is unchanged")


func _test_aggregation() -> void:
	var kit := {"neck":"neck_shield", "ring1":"ring_health", "ring2":"ring_ironhide", "off":""}
	var total := Stats.sum(kit)
	check(is_equal_approx(float(total.health), 45.0), "+25 and +20 health are additive")
	check(is_equal_approx(float(total.guard), 0.02), "The iron ring adds 2% reduction")
	check(is_equal_approx(Stats.max_health(100.0, total), 145.0), "Max health follows the kit")
	check(is_equal_approx(Stats.damage_reduction(0.0, total), 0.02), "Guard stacks onto armor")
	check(is_equal_approx(Stats.damage_reduction(0.45, total), 0.47),
		"Guard adds on top of a capped armor figure")
	var glass := {"neck":"", "ring1":"ring_health", "ring2":"ring_ironhide", "off":""}
	check(is_equal_approx(float(Stats.sum(glass).health), 45.0), "The off hand contributes nothing here")
	var empty := Stats.sum({"neck":"", "ring1":"", "ring2":"", "off":""})
	for key: String in Stats.DEFAULT:
		check(is_equal_approx(float(empty[key]), float(Stats.DEFAULT[key])), "An empty kit zeroes %s" % key)
	var junk := Stats.sum({"neck":"not_an_item", "ring1":"bow_short", "ring2":"", "off":""})
	check(is_equal_approx(float(junk.health), 0.0) and is_equal_approx(float(junk.melee_damage), 0.0),
		"Unknown and non-trinket ids add nothing")
	check(is_equal_approx(Stats.damage_reduction(0.30, {"guard":0.6}), Stats.GUARD_CAP),
		"Trinket guard is capped")
	check(is_equal_approx(Stats.attack_rate({"attack_speed":0.12}), 1.12), "Attack speed is a rate")
	check(is_equal_approx(Stats.move_scale({"move_speed":0.08}), 1.08), "Move speed is a multiplier")
	check(is_equal_approx(Stats.stamina_regen({"stamina_regen":0.30}), 1.30), "Regen is a multiplier")
	check(is_equal_approx(Stats.gold_scale({"gold_find":0.25}), 1.25), "Gold find is a multiplier")
	check(is_equal_approx(Stats.cooldown_scale({"cooldown":0.15}), 0.85), "Cooldown is a discount")
	check(is_equal_approx(Stats.stagger_scale({"stagger":0.25}), 0.75), "Grit cuts stagger")


func _test_slot_routing() -> void:
	var state = root.get_node("PlayerState")
	state.save_path = TEST_SAVE
	state.reset()
	state.inventory.clear()
	state.inventory.append("ring_health")
	state.inventory.append("ring_swift")
	state.inventory.append("ring_haste")
	state.inventory.append("neck_shield")
	state.inventory.append("focus_skull_life")
	var first: Dictionary = state.equip_from_inventory(0)
	check(bool(first.get("ok", false)) and state.equipped_id("ring1") == "ring_health",
		"The first ring fills ring 1")
	var second: Dictionary = state.equip_from_inventory(0)
	check(bool(second.get("ok", false)) and state.equipped_id("ring2") == "ring_swift",
		"The second ring fills ring 2")
	var third: Dictionary = state.equip_from_inventory(0)
	check(bool(third.get("ok", false)) and state.equipped_id("ring1") == "ring_haste",
		"The third ring replaces ring 1")
	check(state.equipped_id("ring2") == "ring_swift", "The third ring leaves ring 2 alone")
	check((third.get("message", "") is String), "The swap reports a message")
	state.equip_from_inventory(state.inventory.find("neck_shield"))
	check(state.equipped_id("neck") == "neck_shield", "The amulet claims the neck slot")
	state.equip_from_inventory(state.inventory.find("focus_skull_life"))
	check(state.equipped_id("off") == "focus_skull_life", "A skull can be held in the off hand")
	var kit: Dictionary = state.trinkets()
	check(str(kit.neck) == "neck_shield" and str(kit.ring1) == "ring_haste"
		and str(kit.ring2) == "ring_swift" and str(kit.off) == "focus_skull_life",
		"PlayerState reports the worn kit")
	var loadout: Dictionary = state.loadout()
	check((loadout.get("trinkets", {}) as Dictionary).get("neck", "") == "neck_shield",
		"The loadout carries the worn kit")
	check(str((loadout.get("focus", {}) as Dictionary).get("kind", "")) == "skull_life",
		"The life skull keeps its own focus silhouette in the loadout")
	check(is_equal_approx(float(state.trinket_stats().heal_on_kill), 15.0),
		"Holding the life skull arms the kill refill")
	state.reset()


func _test_persistence() -> void:
	var state = root.get_node("PlayerState")
	state.save_path = TEST_SAVE
	state.reset()
	state.inventory.clear()
	state.inventory.append("neck_shield")
	state.inventory.append("ring_ranged")
	state.inventory.append("focus_skull_death")
	state.equip_from_inventory(0)
	state.equip_from_inventory(0)
	state.equip_from_inventory(0)
	state.save_state()
	state.equipped = State.DEFAULTS.duplicate()
	state.load_state()
	check(state.equipped_id("neck") == "neck_shield", "The amulet survives a reload")
	check(state.equipped_id("ring1") == "ring_ranged", "The ring survives a reload")
	check(state.equipped_id("off") == "focus_skull_death", "The death skull survives a reload")
	check(is_equal_approx(float(state.trinket_stats().stamina_on_kill), 15.0),
		"The reloaded kit still pays stamina on a kill")
	_remove(TEST_SAVE)
	state.reset()


func _test_derived_stats() -> void:
	var melee_host := rig_for("sword_short", "", {"ring1":"ring_melee", "ring2":"", "neck":"", "off":""})
	check(is_equal_approx(float(melee_host.rig.melee_damage("right")), 33.0),
		"+10% melee turns 30 into 33")
	check(is_equal_approx(float(melee_host.rig.melee_scale()), 1.1), "The rig reports the melee scale")
	melee_host.queue_free()

	var haste_host := rig_for("bow_short", "", {"ring1":"ring_haste", "ring2":"", "neck":"", "off":""})
	check(is_equal_approx(float(haste_host.rig.charge_seconds()), 1.0 / 1.12),
		"+12% attack speed shortens the shortbow draw")
	haste_host.queue_free()

	var speed_host := rig_for("bow_short", "", {"ring1":"ring_swift", "ring2":"", "neck":"", "off":""})
	check(is_equal_approx(float(speed_host.rig.move_scale()), 1.08), "The swift ring multiplies walk speed")
	speed_host.queue_free()

	var health_host := rig_for("sword_short", "", {"ring1":"ring_health", "ring2":"ring_vigor", "neck":"", "off":""})
	check(is_equal_approx(float(health_host.max_health), 125.0), "The health ring raises the seat's maximum")
	check(is_equal_approx(float(health_host.max_stamina), Stamina.MAX + 150.0),
		"The vigor ring raises the stamina pool")
	health_host.health = 125.0
	health_host.apply_trinkets({"ring1":"", "ring2":"", "neck":"", "off":""})
	check(is_equal_approx(float(health_host.max_health), 100.0), "Removing the ring lowers the maximum")
	check(health_host.health <= health_host.max_health, "The live pool is clamped, never over-full")
	health_host.queue_free()

	var ranged_host := rig_for("bow_short", "", {"ring1":"ring_ranged", "ring2":"", "neck":"", "off":""})
	check(is_equal_approx(Combat.damage_for(0, 1.0, float(ranged_host.rig.ranged_scale())), 33.0),
		"+10% ranged turns a full shortbow draw into 33")
	check(is_equal_approx(Combat.damage_for(0, 1.0), 30.0), "The unscaled formula is unchanged")
	check(is_equal_approx(AbilityRules.damage_for(AbilityRules.by_id("barrage"), ranged_host.rig), 16.5),
		"The Barrage skill is scaled by the ranged ring")
	check(is_equal_approx(float(Combat.throw_damage("sword", 0, 1.0, 1.25)), 37.5),
		"The throw scale multiplies the thrown blade")
	ranged_host.queue_free()

	var grit_host := rig_for("sword_short", "", {"ring1":"ring_grit", "ring2":"", "neck":"", "off":""})
	check(is_equal_approx(float(grit_host.combat.stagger_scale), 0.75), "Grit reaches the combat clock")
	var full := grit_host.combat.stagger_from_damage(60.0, 100.0) as float
	check(full > 0.0 and full <= Combat.HIT_STAGGER_MAX * 0.75 + 0.0001,
		"A guaranteed stagger is scaled down")
	grit_host.queue_free()

	var bonus_host := rig_for("sword_short", "focus_skull_life", {"ring1":"", "ring2":"", "neck":"", "off":"focus_skull_life"})
	check(str(bonus_host.rig.focus_kind) == "skull_life", "The rig holds the life skull silhouette")
	check(bonus_host.rig._focus_items.has("skull_death"), "The rig can build the death skull too")
	bonus_host.queue_free()
	await pause(0.05)


func _test_grants() -> void:
	check(AbilityRules.SLOT_COUNT == 3, "There are three ability slots")
	var dash_host := rig_for("bow_short", "", {"ring1":"ring_dash", "ring2":"", "neck":"", "off":""})
	var dash: Dictionary = dash_host.ability.definition(2)
	check(str(dash.get("id", "")) == "dash", "The dash ring grants Dash in the trinket slot")
	check(str(dash.get("key", "")) == "SHIFT + 3", "Dash is bound to SHIFT + 3")
	check(bool(dash.get("aim", false)) and float(dash.get("speed_scale", 0.0)) == 2.0,
		"Dash travels down the crosshair at double speed")
	dash_host.queue_free()

	var amulet_host := rig_for("bow_short", "", {"neck":"neck_shield", "ring1":"", "ring2":"", "off":""})
	var ward: Dictionary = amulet_host.ability.definition(2)
	check(str(ward.get("id", "")) == "energy_shield", "The amulet grants Energy Shield")
	check(is_equal_approx(float(AbilityRules.ward(ward).get("seconds", 0.0)), 60.0),
		"The ward lasts one minute")
	check(is_equal_approx(float(AbilityRules.ward(ward).get("absorb", 0.0)), 0.5),
		"The ward absorbs half of a hit")
	check(is_equal_approx(float(AbilityRules.ward(ward).get("stamina_scale", 0.0)), 2.0),
		"The ward charges twice the absorbed share from stamina")
	check(not amulet_host.ability.hud_state(2).is_empty(), "The amulet fills its HUD tile")
	check(str(amulet_host.ability.hud_state(2).get("name", "")) == "ENERGY SHIELD",
		"The tile names the ward")
	amulet_host.queue_free()

	var both_host := rig_for("bow_short", "", {"neck":"neck_shield", "ring1":"ring_dash", "ring2":"", "off":""})
	check(str(both_host.ability.definition(2).get("id", "")) == "energy_shield",
		"The necklace wins the trinket slot over a ring")
	both_host.queue_free()

	var echo_host := rig_for("bow_short", "", {"neck":"", "ring1":"ring_echo", "ring2":"", "off":""})
	echo_host.stamina = Stamina.MAX
	var echoed: Dictionary = echo_host.ability.activate(0)
	check(bool(echoed.get("ok", false)), "The bow skill activates")
	check(is_equal_approx(float(echo_host.ability.cooldowns[0]), 1.2 * 0.85),
		"The echo ring shortens the granted skill's cooldown")
	echo_host.queue_free()

	var none_host := rig_for("bow_short", "", {"neck":"", "ring1":"ring_health", "ring2":"", "off":""})
	check(none_host.ability.definition(2).is_empty(), "A stat-only ring grants no skill")
	check(none_host.ability.blocker(2) != "", "An empty trinket slot refuses activation")
	none_host.queue_free()
	await pause(0.05)


func _test_ward() -> void:
	var host := rig_for("bow_short", "", {"neck":"neck_shield", "ring1":"ring_health", "ring2":"", "off":""})
	check(is_equal_approx(float(host.max_health), 125.0), "The ward host carries the health ring")
	var start_stamina := float(host.stamina)
	var outcome: Dictionary = host.ability.activate(2)
	check(bool(outcome.get("ok", false)), "The amulet's ward activates")
	check(is_equal_approx(float(host.stamina), start_stamina - 8.0), "The ward spends its activation cost")
	check(is_equal_approx(float(host.ward_seconds), 60.0), "The ward starts its minute")
	check(is_instance_valid(host.rig._ward) and host.rig._ward.visible, "The bubble is shown")
	check(host.rig._ward.get_child_count() == 1, "The bubble is one shell mesh")
	check(host.snapshot().has("ward") and host.snapshot().has("maxh"),
		"The ward and the maximum travel in the snapshot")

	# Half of a 40-point hit moves to stamina at twice the share: 40 stamina.
	var before_health := float(host.health)
	var before_stamina := float(host.stamina)
	host.take_damage(40.0, 1, false, false)
	check(is_equal_approx(before_health - float(host.health), 20.0),
		"Half of the hit reaches health")
	check(is_equal_approx(before_stamina - float(host.stamina), 40.0),
		"The other half costs twice its value in stamina")

	# An empty pool can only pay for the stamina it has.
	host.stamina = 10.0
	var health_before := float(host.health)
	host.take_damage(40.0, 1, false, false)
	check(is_equal_approx(health_before - float(host.health), 35.0),
		"A dry pool pays five points of shield and lets the rest through")
	check(is_equal_approx(float(host.stamina), 0.0), "The pool is empty")

	# Expiry drops the shield and the bubble together.
	host.stamina = 400.0
	host.ward_seconds = 0.01
	host._tick_ward(0.02)
	check(is_equal_approx(float(host.ward_seconds), 0.0), "The ward expires on its clock")
	check(not host.rig._ward.visible, "The bubble hides with it")
	var bare := float(host.health)
	host.take_damage(40.0, 1, false, false)
	check(is_equal_approx(bare - float(host.health), 40.0), "An expired ward takes nothing from stamina")
	check(is_equal_approx(float(host.stamina), 400.0), "An expired ward spends no stamina")

	# A replica applies the bubble from the snapshot alone.
	var host2 := rig_for("bow_short", "", {"neck":"neck_shield", "ring1":"", "ring2":"", "off":""})
	host2.ability.activate(2)
	var replica := fighter(scene, 1, Vector3.ZERO)
	replica.authoritative = false
	replica.apply_snapshot(host2.snapshot())
	check(is_instance_valid(replica.rig._ward) and replica.rig._ward.visible,
		"A replica shows the replicated bubble")
	check(is_equal_approx(float(replica.max_health), 100.0), "The replica reads the replicated maximum")
	var packed: Dictionary = host2.snapshot()
	check(JSON.stringify(packed).to_utf8_buffer().size() < 1100,
		"The ward snapshot stays inside the MTU budget")
	replica.queue_free()
	host.queue_free()
	host2.queue_free()
	await pause(0.1)


func _test_kill_refills() -> void:
	var host := rig_for("sword_short", "focus_skull_life", {"neck":"", "ring1":"", "ring2":"", "off":"focus_skull_life"})
	host.health = 40.0
	host.apply_kill_refill()
	check(is_equal_approx(float(host.health), 55.0), "The life skull pays 15 health")
	host.health = float(host.max_health) - 5.0
	host.apply_kill_refill()
	check(is_equal_approx(float(host.health), float(host.max_health)),
		"The refill never exceeds the maximum")
	check(is_equal_approx(float(host.stamina), Stamina.MAX), "The life skull leaves stamina alone")
	host.queue_free()

	var death_host := rig_for("sword_short", "focus_skull_death", {"neck":"", "ring1":"", "ring2":"", "off":"focus_skull_death"})
	death_host.health = 40.0
	death_host.stamina = 500.0
	death_host.apply_kill_refill()
	check(is_equal_approx(float(death_host.health), 40.0), "The death skull leaves health alone")
	check(is_equal_approx(float(death_host.stamina), 515.0), "The death skull pays 15 stamina")
	death_host.queue_free()

	# The frontier routes a kill through the mob's last hitter.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await pause(0.5)
	game.set_physics_process(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game._player_state.equipped["off"] = "focus_skull_life"
	game.archer.apply_loadout(game._player_state.loadout())
	game._sync_trinket_limits()
	check(is_equal_approx(float(game.trinket_stats.get("heal_on_kill", 0.0)), 15.0),
		"The frontier mirrors the held skull")
	game.health = 50.0
	var enemy = game.enemies[0]
	enemy.take_damage(1000.0, 0)
	check(int(enemy.get("last_hitter")) == 0, "The dying mob remembers its killer")
	check(is_equal_approx(float(game.health), 65.0), "A frontier kill refills the killer")
	var other = game.enemies[0]
	game.health = 50.0
	other.take_damage(1000.0, 2)
	check(is_equal_approx(float(game.health), 50.0), "Someone else's kill pays nothing")
	check(int(other.get("last_hitter")) == 2, "The second mob remembers its own killer")
	game.queue_free()
	await pause(0.1)


func _test_hud_tiles() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	await pause(0.05)
	check(is_instance_valid(hud._trinket_ability_slot), "The frontier HUD builds a third tile")
	hud.set_limits(125.0, 1400.0)
	var state := {"id":"energy_shield", "name":"ENERGY SHIELD", "key":"SHIFT + 3",
		"cooldown":0.0, "active":false, "affordable":true, "stamina_cost":8.0}
	hud.update_status(120.0, 900.0, 0, 0, "READY", 0.0, "The frontier", 1.0, 1.0, "OPEN",
		false, false, 1.0, 1.0, "", 0.0, {}, {}, state)
	check(hud._trinket_ability_slot.visible, "The trinket tile shows a granted skill")
	check(hud._health_label.text == "HEALTH  120 / 125", "The health label reads the raised maximum")
	check(hud._stamina_label.text == "STAMINA  900 / 1400", "The stamina label reads its pool")
	check(is_equal_approx(hud._health_bar.max_value, 125.0), "The health bar is scaled")
	check(is_equal_approx(hud._stamina_bar.max_value, 1400.0), "The stamina bar is scaled")
	hud.queue_free()

	var arena_hud := ArenaHud.new()
	root.add_child(arena_hud)
	await pause(0.05)
	check(is_instance_valid(arena_hud._trinket_ability_slot), "The arena HUD builds a third tile")
	arena_hud.update_match({"players":[], "local_slot":0, "health":120.0, "max_health":125.0,
		"movement":"OPEN", "phase":"READY", "weapon":"bow", "draw":0.0,
		"attack_interval":1.0, "attack_progress":1.0, "blocking":false, "shield":false,
		"respawn":0.0, "left_melee":1.0, "right_melee":1.0, "parry":false,
		"armor":0, "bow":0, "sword":0, "ability":{}, "ability_off":{},
		"ability_trinket":state})
	check(arena_hud._trinket_ability_slot.visible, "The arena trinket tile shows the ward")
	check(arena_hud.health_label.text.begins_with("HEALTH  120 / 125"),
		"The arena health text reads the maximum")
	arena_hud.queue_free()

	var delve_hud := DelveHud.new()
	root.add_child(delve_hud)
	await pause(0.05)
	check(is_instance_valid(delve_hud._trinket_ability_slot), "The delve HUD builds a third tile")
	delve_hud.update_local({"health":120.0, "max_health":125.0, "stamina":900.0,
		"max_stamina":1400.0, "ability":{}, "ability_off":{}, "ability_trinket":state,
		"party":[], "phase":"READY"})
	check(delve_hud._trinket_ability_slot.visible, "The delve trinket tile shows the ward")
	check(is_equal_approx(delve_hud._health_bar.max_value, 125.0), "The delve health bar is scaled")
	delve_hud.queue_free()
	await pause(0.1)
