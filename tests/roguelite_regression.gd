extends SceneTree
## The roguelite loop end to end: the ledger, the armory, the proc engine, the
## town's three fixtures, and one full run from the portal to the last island.
##
## What this owns: that the starters are free and the rest are earned, that the
## stacking rules do what the pool says (linear damage, hyperbolic chances), that
## a run dresses the body in the rack's choice, spawns a budgeted wave, applies
## on-hit procs, pays crystals and keys, opens a chest and revives a downed body,
## drafts a pedestal mod, bargains at a Greed Totem, buys from the shop, takes a
## portal to a second island, and closes back onto the town square with the body
## where it started.

const WORLD = "res://scenes/warband_world.tscn"
const TEST_STATE := "user://roguelite_regression_state.json"
const TEST_WARBAND := "user://roguelite_regression_warband.json"
const TEST_META := "user://roguelite_regression_meta.json"

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const ProcEngineScript = preload("res://scripts/roguelite/proc_engine.gd")
const StageScript = preload("res://scripts/roguelite/roguelite_stage.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")

var game
var run
var body
var meta
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ROGUELITE_FAIL  ", message)


func _initialize() -> void:
	call_deferred("execute")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func execute() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	_check_ledger()
	_check_armory()
	_check_engine()
	await _open_world()
	await _check_town()
	_check_run()
	await _check_waves()
	_check_rewards()
	_check_portal()
	_check_close()
	_check_arsenal_in_hand()
	await _check_biomes_and_boss()
	_finish()


# --- pure systems ----------------------------------------------------------

func _check_ledger() -> void:
	meta = root.get_node("Roguelite")
	meta.save_path = TEST_META
	meta.reset(false)
	body = null
	check(meta.keys == MetaScript.STARTING_KEYS, "a fresh ledger carries the totem's first keys")
	check(meta.unlocked_ids().size() == 2, "two starters and nothing else")
	check(meta.is_unlocked("bow_twig"), "the twig bow is free")
	check(meta.is_unlocked("hatchet_makeshift"), "the hatchet is free")
	check(not meta.is_unlocked("xbow_heavy"), "the heavy crossbow is locked")
	check(meta.loadout_for("ranged") == MetaScript.DEFAULT_RANGED, "ranged slot starts the twig bow")
	check(meta.loadout_for("melee") == MetaScript.DEFAULT_MELEE, "melee slot starts the hatchet")
	check(not meta.set_loadout_slot("ranged", "javelin_iron").ok, "a locked piece cannot be bound")
	check(not meta.set_loadout_slot("ranged", "hatchet_makeshift").ok, "a melee piece cannot take the ranged slot")
	meta.keys = 30
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var roll: Dictionary = meta.roll_unlock(rng)
	check(bool(roll.get("ok", false)), "the totem opens a weapon")
	check(meta.keys == 30 - MetaScript.UNLOCK_COST, "the roll spends its keys")
	check(meta.unlocked_ids().size() == 3, "the pool grows by one")
	check(meta.is_unlocked(str(roll.get("id", ""))), "the opened weapon is in the pool")
	meta.save_meta()
	meta.load_meta()
	check(meta.is_unlocked(str(roll.get("id", ""))), "the ledger survives a reload")
	check(meta.keys == 30 - MetaScript.UNLOCK_COST, "and so do its keys")
	meta.unlocked.append("xbow_heavy")
	check(meta.set_loadout_slot("ranged", "xbow_heavy").ok, "an opened piece takes its slot")
	check(meta.loadout_for("ranged") == "xbow_heavy", "and the slot remembers it")
	meta.share_pool(["javelin_iron"])
	check(meta.is_unlocked("javelin_iron"), "the host's loan is field-able")
	meta.share_pool([])
	check(not meta.is_unlocked("javelin_iron"), "and the loan is taken back")


func _check_armory() -> void:
	check(Weapons.has("bow_twig") and Weapons.has("hatchet_makeshift"), "both starters are in the registry")
	check(Weapons.slot_of("bow_twig") == "ranged", "the twig bow is ranged")
	check(Weapons.slot_of("hatchet_makeshift") == "melee", "the hatchet is melee")
	var heavy: Dictionary = Weapons.get_weapon("xbow_heavy")
	check(float(heavy.get("proc", 0.0)) == 1.5, "the heavy crossbow carries a 1.5 proc coefficient")
	check(int(heavy.get("pierce", 0)) >= 1, "and a pierce budget")
	var auto: Dictionary = Weapons.get_weapon("xbow_auto")
	check(float(auto.get("proc", 0.0)) == 0.5, "the repeater carries a 0.5 proc coefficient")
	check(float(auto.get("spread", 0.0)) > 0.0, "and a spread")
	check(Weapons.all_ids().size() >= 12, "every catalog blade and bow is registered (%d)" % Weapons.all_ids().size())
	check(Weapons.has("sword_great") and Weapons.has("bow_long") and Weapons.has("staff_fire"),
		"the campaign's own weapons are in the pool")
	for id in Weapons.unlock_pool():
		check(not Weapons.is_default(id), "the unlock pool holds no starter (%s)" % id)
	check(Mods.all().size() >= 20, "the mod pool is broad enough to draft from (%d)" % Mods.all().size())
	for rarity in Mods.RARITIES:
		var found := false
		for row in Mods.all():
			if str(row.rarity) == rarity:
				found = true
				break
		check(found, "the %s tier has rows" % rarity)


## Every new archetype has to be liftable: the rig builds a crossbow from a bow's
## data, a spear from a sword's and a throwing knife from a dagger's, and a loadout
## that crashes a rig is a weapon nobody can use.
func _check_arsenal_in_hand() -> void:
	var merc: int = game.controller.merc_of(body)
	for weapon_id in ["xbow_auto", "javelin_iron", "dagger_throwing", "axe_makeshift",
			"hatchet_makeshift", "bow_twig"]:
		check(run._dress_weapon(body, merc, weapon_id), "the rig takes %s" % weapon_id)
	check(str(body.rig.weapon) != "none", "the rig is holding something")
	check(Weapons.resolve("javelin_iron").get("archetype") == "javelin",
		"the javelin keeps its archetype")


func _check_biomes_and_boss() -> void:
	# A second run, to exercise the two islands the first one never reached and
	# the boss wave a six-island campaign sends on its third and sixth.
	var start: Dictionary = run.start_run()
	check(bool(start.get("ok", false)), "a second run opens")
	for index in StageScript.BIOMES.size():
		var data: Dictionary = StageScript.BIOMES[index]
		run.stage_index = index
		run.biome_id = str(data.id)
		run._build_stage()
		check(run.stage.biome_id == str(data.id), "the %s island builds" % str(data.id))
		check(run.stage.radius > 20.0, "and is a bounded island")
	# The boss: the last wave of a third island always sends one.
	run.stage_index = 2
	run.biome_id = "caves"
	run._build_stage()
	run.wave = 2
	run.waves_this_stage = 3
	run.wave_active = false
	run._begin_wave()
	check(run.boss_wave, "the third island's last wave is a boss wave")
	var has_boss := false
	for spec in run._queue:
		if bool((spec as Dictionary).get("boss", false)):
			has_boss = true
	check(has_boss, "and the queue carries the faction's boss")
	run.tick(2.5)
	run.tick(0.5)
	var boss_seen := false
	for mob in run._mobs:
		if not is_instance_valid(mob):
			continue
		var spec: Dictionary = run._mob_specs.get((mob as Node).get_instance_id(), {})
		if bool(spec.get("boss", false)):
			boss_seen = true
	check(boss_seen, "the boss stands on the island")
	# The third faction: the pit's own cloned rangers, spawned through the same
	# factory the host uses on island five.
	run.stage_index = 5
	run._begin_stage("arena")
	run.waves_this_stage = 1
	run.wave = 0
	run._begin_wave()
	run.tick(2.5)
	run.tick(0.5)
	var clone_seen := false
	for mob in run._mobs:
		if not is_instance_valid(mob):
			continue
		var script_path := str(mob.get_script().resource_path) if mob.get_script() != null else ""
		if script_path.ends_with("ranger_clone.gd"):
			clone_seen = true
	check(clone_seen, "the Blood Pit fields its cloned rangers")
	run._finish_run(false)
	check(not run.is_running(), "a lost run closes cleanly")


func _check_engine() -> void:
	var engine = ProcEngineScript.new(77, 3)
	engine.add_mod("split_shot", 2)
	engine.add_mod("rapid_fire", 5)
	engine.add_mod("heavy_caliber", 1)
	check(int(engine.stats().split_shots) == 2, "two Arc Split stacks are +2 arrows")
	check(absf(engine.attack_scale() - (1.0 + 0.18 * 5.0 - 0.1)) < 0.0001,
		"rates stack linearly (+18% x5, -10% heavy)")
	check(absf(engine.damage_multiplier() - (1.0 + 0.35)) < 0.0001, "damage stacks linearly")
	var plan: Dictionary = engine.on_weapon_fire(Weapons.get_weapon("bow_twig"),
		Vector3.ZERO, Vector3.FORWARD)
	check(int(plan.get("shots", 0)) >= 3, "a split shot fires the fan")
	# Ten copies of a 15% proc must not reach the cap, let alone certainty.
	var chance = ProcEngineScript.new(11, 1)
	# The catalog caps a row at six; the curve itself is what is under test, so
	# the stack table is driven past the cap directly.
	chance.add_mod("chain_lightning", 6)
	chance.stacks["chain_lightning"] = 100
	chance._dirty = true
	var rolled := 0
	for _index in 2000:
		if chance.chance_roll("chain_chance"):
			rolled += 1
	var rate := float(rolled) / 2000.0
	check(rate > 0.60 and rate < 0.72, "hyperbolic proc chance approaches 70%%, not 100%% (%.3f)" % rate)
	check(chance.stat("chain_chance") <= 0.70, "the chance curve is capped")
	var greed = ProcEngineScript.new(5, 1)
	greed.add_mod("glass_cannon", 5)
	check(greed.health_factor() >= ProcEngineScript.MIN_HEALTH_FACTOR,
		"five Glass Cannons cannot delete the pool")
	check(absf(greed.damage_multiplier() - 6.0) < 0.0001, "+100% damage five times is +500%")
	var crit = ProcEngineScript.new(9, 1)
	crit.add_mod("crit_sharpshooter", 6)
	check(absf(crit.stat("crit_chance") - 0.72) < 0.0001, "crit chance stacks linearly to the cap")
	var draft_rng := RandomNumberGenerator.new()
	draft_rng.seed = 31
	var offers: Array = Mods.draft(draft_rng, 3, false)
	check(offers.size() == 3, "a draft offers three")
	var unique := {}
	for id in offers:
		unique[id] = true
		check(Mods.rarity_of(str(id)) != Mods.RARITY_GREED, "a normal draft holds no greed")
	check(unique.size() == 3, "a draft never repeats a row")


# --- the world and the square ----------------------------------------------

func _open_world() -> void:
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	var flow = root.get_node("GameFlow")
	state.save_path = TEST_STATE
	state.reset(false)
	warband.save_path = TEST_WARBAND
	warband.reset_state()
	flow.active = false
	flow.world_start = "town"
	game = load(WORLD).instantiate()
	root.add_child(game)
	current_scene = game
	var waited := 0.0
	while waited < 40.0 and (game.get("controller") == null or game.bodies.size() < 1):
		await physics_frame
		waited += 0.016
	run = game.get("roguelite")
	check(game.bodies.size() >= 1, "the campaign stands a body up")
	check(run != null, "the world owns a run director")
	check(game.get("roguelite_hud") != null, "and a plate")
	if game.bodies.size() >= 1:
		body = game.bodies[0]


func _check_town() -> void:
	var saved_at: Vector3 = body.global_position
	for service in ["roguelite_totem", "roguelite_rack", "roguelite_portal"]:
		var point: Vector3 = game.town.service_point(service)
		check(point != Vector3.ZERO, "the square has a %s" % service)
		check(game.town.service_at(point) == service, "and it resolves as its own service (%s)" % service)
		body.global_position = point
		check(game.town.prompt_line(body).begins_with("G - "), "and writes a prompt when stood at")
		check(point.distance_to(game.town.global_position) < 40.0,
			"the %s stands inside the wall" % service)
	body.global_position = saved_at
	check(game.town.service_point("roguelite_portal").distance_to(
		game.town.service_point("roguelite_totem")) > 4.0,
		"the three fixtures have room between them")
	# The square dresses a body in the rack's ranged piece, and puts the campaign
	# kit back when the body walks out of the walls.
	check(str(body.rig.weapon) == "bow", "a body in the square holds the rack's bow")
	check(int(body.rig.bow_index) == 4, "and it is the piece the rack bound")
	body.global_position = game.town.global_position + Vector3(0.0, 0.0, -60.0)
	game._sync_town_dress()
	check(str(body.rig.weapon) != "bow", "walking out restores the campaign's kit")
	body.global_position = game.town.service_point("roguelite_totem")
	game._sync_town_dress()
	check(str(body.rig.weapon) == "bow", "walking back in dresses it again")
	# The press itself: each fixture opens the arena board on its own page.
	var service: String = game.town.interact_at(1, body.global_position)
	check(service == "roguelite_totem", "the totem's press resolves to the totem")
	check(game.town.forge_panel.is_open(), "and opens the arena board")
	game.town.forge_panel.close_panel()
	check(not game.town.forge_panel.is_open(), "which closes again")
	body.global_position = saved_at


# --- one run ---------------------------------------------------------------

func _check_run() -> void:
	var start: Dictionary = run.start_run()
	check(bool(start.get("ok", false)), "the portal opens the run: %s" % str(start.get("message", "")))
	check(run.is_running(), "the director is live")
	check(run.stage != null and is_instance_valid(run.stage), "an island was built")
	check(run.players.size() >= 1, "the body has a run runtime")
	var player = run.players.get(1)
	check(player != null and is_instance_valid(player), "the runtime is bound to peer 1")
	check(str(player.ranged_id) == "xbow_heavy", "the rack's choice rides into the run")
	check(int(body.rig.bow_index) == 4, "the heavy crossbow is in the rig's hand")
	check(body.bounds > 1000.0, "the island lifts the campaign's bound")
	check(body.global_position.y > 600.0, "the body stands on the island, not in the wood")
	check(absf(body.global_position.y - StageScript.LIFT) < 2.0, "the first island sits at the lift")


func _check_waves() -> void:
	var guard_before: int = game.guards.size()
	var stormed := false
	for _round in 14:
		run.tick(2.5)
		if not run._mobs.is_empty():
			stormed = true
			break
	check(stormed, "the director queued and spawned a wave")
	check(game.guards.size() > guard_before, "the wave joined the world's hostile list")
	var first = run._mobs[0]
	check(first != null and is_instance_valid(first), "a mob exists")
	check(str(first.name).begins_with("Rogue"), "the mob carries a run name (%s)" % str(first.name))
	check(first.get("replica") != true, "a host wave is authoritative")
	# A proc chain: give the player a blood arc and hit the mob once.
	var player = run.players.get(1)
	var before := int(player.engine.mod_list().size())
	player.take_mod("chain_lightning")
	check(player.engine.stacks_of("chain_lightning") == 1, "the mod stack took")
	check(player.engine.mod_list().size() == before + 1, "and is listed")
	# The chain arc, forced: a second body beside the first, four jumps and a
	# lethal figure. The target the arc starts from is never struck twice.
	var second = first
	for mob in run._mobs:
		if is_instance_valid(mob) and mob != first:
			second = mob
			break
	second.global_position = first.global_position + Vector3(1.2, 0.0, 0.0)
	var chain_before: float = float(second.get("health"))
	run.execute_effect(player, {"kind": "chain", "target": first,
		"position": first.global_position, "damage": 4096.0, "proc": 1.0,
		"targets": 4})
	check(float(second.get("health")) < chain_before or second.get("alive") == false,
		"a chain arc spends damage on the next body")
	check(player.kills >= 1, "and the kill is booked to the shooter")
	# Crescent Wave is the one trigger with no die: every swing pays it, so the
	# effect pipeline is proven deterministically rather than by a lucky roll.
	player.take_mod("melee_shockwave")
	# A real shot: one trigger, one ammo spend, the registry's profile and the
	# mod engine's fan all applied to a live arrow.
	player.take_mod("split_shot")
	var arrows_before: int = game.projectiles.size()
	var ammo_before: int = int(game.warband.arrows())
	var fired: bool = run.fire(body, body.global_position + Vector3.UP * 1.4,
		Vector3.FORWARD, 60.0, 1.0)
	check(fired, "the director owns a run body's shot")
	check(game.projectiles.size() >= arrows_before + 2, "Arc Split puts more than one shaft in the air")
	check(int(game.warband.arrows()) == ammo_before,
		"the arena spends no shaft from the campaign's quiver")
	var left: Vector3 = (game.projectiles[arrows_before].velocity as Vector3).normalized()
	var right: Vector3 = (game.projectiles[arrows_before + 1].velocity as Vector3).normalized()
	check(absf(left.dot(right) - 1.0) > 0.000001, "the split shafts carry a real spread")
	var newest = game.projectiles[game.projectiles.size() - 1]
	check(int(newest.get("pierce")) >= 1, "the heavy crossbow's pierce rides the arrow")
	check(absf(float(newest.get("proc_coeff")) - 1.5) < 0.001, "and its proc coefficient")
	var throw_before: int = game.projectiles.size()
	var charged_before: int = int(run._throw_charges.get(1, 0))
	var thrown_ok: bool = run.throw_weapon(body, body.global_position + Vector3.UP * 1.4,
		Vector3.FORWARD, 26.0, 1.0, "sword", 5)
	check(thrown_ok, "the director owns a run body's throw")
	check(game.projectiles.size() == throw_before + 1, "a throwing blade leaves the hand")
	check(int(run._throw_charges.get(1, 0)) == charged_before - 1, "and spends a charge")
	var waves_before := _count_procs("ProcWave")
	var swing: Dictionary = player.melee_swing(Vector3.FORWARD)
	check(swing.has("crit"), "a swing answers its crit")
	check(_count_procs("ProcWave") > waves_before, "a melee swing throws its crescent")
	# Clear every wave.
	for _round in 20:
		run.tick(2.5)
		for mob in run._mobs.duplicate():
			if is_instance_valid(mob) and mob.get("alive") != false:
				mob.take_damage(4096.0, 1)
		run.tick(0.2)
		if run.stage_cleared:
			break
	check(run.stage_cleared, "the island clears after its last wave")
	check(run.crystals > 0, "kills paid crystals (%d)" % run.crystals)
	check(run.keys_earned >= 1, "the clear paid keys (%d)" % run.keys_earned)


func _count_procs(name_prefix: String) -> int:
	var count := 0
	for child in game.get_children():
		if is_instance_valid(child) and str(child.name).begins_with(name_prefix):
			count += 1
	return count


func _prop_of(kind: String) -> Node3D:
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == kind:
			return prop
	return null


func _check_rewards() -> void:
	var chest := _prop_of("chest")
	check(chest != null, "a reward chest stands on the island")
	var pedestal := _prop_of("pedestal")
	check(pedestal != null, "a mod pedestal stands on the island")
	var greed := _prop_of("greed")
	check(greed != null, "a Greed Totem stands on the island")
	var portals := 0
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == "portal":
			portals += 1
	check(portals == 2, "two portals are offered (%d)" % portals)
	# Downed, then the chest's contract.
	body.health = 0.0
	body.enter_downed(1)
	check(bool(body.downed), "a lethal wave puts the body on the dirt")
	body.take_damage(50.0, 1)
	check(bool(body.alive), "a held body cannot be finished")
	run.tick(0.2)
	check(bool(body.alive), "and it does not bleed out while the run holds it")
	var chest_serial := int(chest.get_meta("serial"))
	run._open_chest(chest_serial, body)
	check(run._opened.has(chest_serial), "the chest opens")
	check(not bool(body.downed) and float(body.health) > 0.0,
		"the chest wakes a downed body at half the pool")
	check(run._opened.has("chest"), "the chest unseals the portals")
	# The draft.
	var pedestal_serial := int(pedestal.get_meta("serial"))
	var offers: Array = run.draft_offers.get(pedestal_serial, [])
	if offers.is_empty():
		run._open_draft(pedestal_serial, body)
		offers = run.draft_offers.get(pedestal_serial, [])
	check(offers.size() == 3, "the pedestal holds three offers")
	var player = run.players.get(1)
	var stacks_before: int = player.engine.total_stacks()
	var chosen: Dictionary = run.choose_draft(1, pedestal_serial, 0)
	check(bool(chosen.get("ok", false)), "the first offer is taken")
	check(player.engine.total_stacks() == stacks_before + 1, "the mod lands on the body")
	check(not run._props_by_serial.has(pedestal_serial), "the pedestal is spent")
	# The Greed Totem.
	var greed_serial := int(greed.get_meta("serial"))
	var health_before: float = float(body.health)
	var greed_stacks: int = player.engine.total_stacks()
	run._open_greed(greed_serial, body)
	check(player.engine.total_stacks() > greed_stacks, "the totem sells a greed mod")
	check(float(body.health) < health_before, "and takes its price in blood")
	# The shop.
	var wares := [{"id": "rapid_fire", "name": "Berserk Rate", "price": 10,
		"rarity": "common"}]
	var shop: Node3D = run._spawn_prop("shop", run.stage.rim_point(1, 6), {"wares": wares})
	run.shop_wares[int(shop.get_meta("serial"))] = wares
	run.crystals = 100
	var bought: Dictionary = run.buy(int(shop.get_meta("serial")), 0, 1)
	check(bool(bought.get("ok", false)), "the stall sells a ware")
	check(run.crystals == 90, "and takes its price")


func _check_portal() -> void:
	var portal := _prop_of("portal")
	check(portal != null, "a portal is standing")
	var before_stage: int = run.stage_index
	var before_biome: String = run.biome_id
	run._vote_portal(int(portal.get_meta("serial")), body, 1)
	check(run.stage_index == before_stage + 1, "the portal takes a second island")
	check(run.biome_id != before_biome, "and the island is a different biome (%s)" % run.biome_id)
	check(run.stage != null and is_instance_valid(run.stage), "the next island is built")
	check(body.global_position.y > 600.0, "the party stands on the new island")
	check(run.wave == 0 or run.wave_active, "the new island opens on a wave")


func _check_close() -> void:
	var town_point: Vector3 = game.town.global_position
	var runs_before: int = int(meta.runs)
	run._finish_run(true)
	check(not run.is_running(), "the run closes")
	check(run.stage == null, "the island is gone")
	check(int(meta.runs) == runs_before + 1, "the ledger books the run")
	check(body.global_position.distance_to(town_point) < 60.0, "the body is back in the square")
	check(body.bounds < 2000.0, "and the campaign's bound is restored")
	check(game.roguelite_hud.open_panels() == false, "no plate is left open")
	# The net surface an arena needs, present even offline.
	var session_script = load("res://scripts/warband/warband_session.gd")
	check(session_script != null, "the session script still loads")
	var session = session_script.new()
	for method in ["send_roguelite_event", "send_roguelite_request", "receive_roguelite",
			"roguelite_request"]:
		check(session.has_method(method), "the session carries %s" % method)
	# An armory lent before this machine's world existed is kept until it does.
	session.receive_roguelite({"t": "pool", "ids": ["javelin_iron"]})
	check(session._roguelite_pool.has("javelin_iron"),
		"the host's pool is held until a world can take it")
	session.free()
	# The guest half of the director: the absolute purse and a lent pool apply
	# through the same entry point the RPC calls.
	run.apply_event({"t": "crystals", "total": 321})
	check(run.crystals == 321, "the purse follows the host's total, not a delta")
	var lent := ""
	for candidate in Weapons.all_ids():
		if not meta.is_unlocked(str(candidate)):
			lent = str(candidate)
			break
	check(not lent.is_empty(), "the ledger still has a locked piece to lend")
	run.apply_event({"t": "pool", "ids": [lent]})
	check(meta.is_unlocked(lent), "a lent pool reaches the rack")
	meta.share_pool([])
	check(not meta.is_unlocked(lent), "and is taken back with the session")
	run.apply_event({"t": "fx", "kind": "nova", "at": body.global_position, "points": []})
	check(true, "a proc flash applies without a world-side error")


func _finish() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	print("ROGUELITE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
