extends SceneTree
## The town end of the one world, on real bodies: the square builds at the far end
## of the trail, the five services resolve from a point, the recruiter hires and
## refuses at the cap, the paperdoll moves gear between one mercenary and the
## collective pool, and the square is the campaign's one settlement.
##
## The town is not a scene of its own in the campaign; it is loaded here by asking
## the world to put the warband down at its town end, which is exactly what a
## resumed save does.

const State = preload("res://scripts/player_state.gd")
const VoiceLibrary = preload("res://scripts/audio/voice_library.gd")

const TEST_SAVE := "user://town_hub_state.json"
const WARBAND_SAVE := "user://town_hub_warband.json"
const WORLD := "res://scenes/warband_world.tscn"

var game
var state
var warband
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TOWN_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "town"

	game = load(WORLD).instantiate()
	if game == null:
		check(false, "the world scene loads")
		print("TOWN_HUB_REGRESSION checks=", checks, " failures=", failures)
		quit(1)
		return
	root.add_child(game)
	await create_timer(0.6).timeout

	check_square()
	await check_stash()
	await check_altar()
	await check_recruiter()

	if game != null and is_instance_valid(game):
		game.queue_free()
	await process_frame
	root.get_node("GameFlow").world_start = "camp"
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("TOWN_HUB_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- the square ------------------------------------------------------------

func check_square() -> void:
	check(game.start_area == "town", "the world put the warband down at the town end (%s)" % game.start_area)
	check(game.camp != null and game.trail != null,
		"the camp and the trail are the same world, 300 m up the road")
	check(warband.roster.count() >= 5, "the hub seeds a warband (%d)" % warband.roster.count())
	check(game.bodies.size() >= 5, "at least five bodies stand in the square (%d)" % game.bodies.size())
	check(game.bodies.size() <= warband.deployment_cap,
		"the square fields no more than the cap (%d)" % game.bodies.size())
	var actor = game.controller.active_body(1)
	check(actor != null and is_instance_valid(actor), "the player is inside a body")
	if actor != null and is_instance_valid(actor):
		check(bool(actor.get("alive")) and not bool(actor.get("downed")),
			"the body the player is inside is living")
		check(actor.global_position.distance_to(game.town.global_position) < 8.0,
			"the body starts in the square (%.1f m from the fire)"
			% actor.global_position.distance_to(game.town.global_position))
	var merc_id: int = game.controller.merc_for_peer(1)
	check(merc_id > 0 and warband.souls.occupied_by(merc_id) == 1,
		"the router says peer one holds that body")
	check(game.hud != null and game.screen != null and game.paperdoll != null,
		"the HUD and both panels exist")

	# The services are the merged objects, not town-local copies.
	check(is_instance_valid(game.stash_chest), "the stash chest stands in the square")
	check(is_instance_valid(game.recruiter_desk), "the recruiter desk stands in the square")
	check(is_instance_valid(game.signpost), "the signpost stands in the square")
	check(game.altar != null and game.altar.has_method("in_reach") and game.altar.has_method("interact"),
		"the sacrificial altar is the shared object")
	check(game.fire_light is OmniLight3D and game.fire_light.light_energy > 0.0,
		"the campfire casts light")
	check(game.flame is MeshInstance3D and game.flame.mesh != null, "the campfire has a flame mesh")

	# Point resolution: the four rings name one service each, and the fire names
	# none of them.
	for service in ["stash", "altar", "recruiter", "quartermaster"]:
		var point: Vector3 = game.service_point(service)
		var named: String = game.service_at(point)
		check(named == service, "the %s ring resolves to itself (got '%s')" % [service, named])
	check(game.service_at(game.town.global_position) == "", "the fire is not a service")

	# The counters that can speak: every stall keeper and the quartermaster has a
	# voice the library knows, and each one stands inside its own ring - a counter
	# whose point fell outside its reach would greet nobody and never be heard.
	for service in game.town.KEEPER_VOICES.keys():
		var voice := str(game.town.KEEPER_VOICES[service])
		check(VoiceLibrary.VOICES.has(voice), "the %s counter speaks with an unknown voice" % service)
		check(game.service_at(game.service_point(service)) == service,
			"the %s counter is not reachable from its own point" % service)
	for service in game.town.VENDOR_SERVICES:
		check(game.town.KEEPER_VOICES.has(service), "the %s stall has no keeper voice" % service)

# --- stash and paperdoll ---------------------------------------------------

func check_stash() -> void:
	var actor = game.controller.active_body(1)
	var point: Vector3 = game.service_point("stash")
	actor.global_position = point + Vector3(0.0, 0.1, 1.4)
	await create_timer(0.25).timeout
	check(game.interact_at(1, point) == "stash", "G at the chest names the stash")
	check(game.paperdoll.is_open(), "the shared stash opens the paperdoll")
	check(game.paperdoll.selected_merc == game.controller.merc_for_peer(1),
		"the paperdoll opens on the body the soul is inside")
	if not game.paperdoll.is_open():
		return

	var merc_id: int = game.paperdoll.selected_merc
	var worn_main := str(warband.roster.equipped_of(merc_id).get("main", ""))
	# A free one-hander in the pool: pressing its row is the paperdoll's own path
	# into `Warband.equip_merc`, so this measures the panel and not the roster.
	var picked := -1
	for index in game.paperdoll.stash_rows.size():
		var row: Dictionary = game.paperdoll.stash_rows[index]
		if int(row.get("pooled", 0)) <= 0:
			continue
		var item_id := str(row["item_id"])
		if item_id == worn_main:
			continue
		if str(State.ITEMS.get(item_id, {}).get("category", "")) == "1h":
			picked = index
			break
	check(picked >= 0, "a free one-hander waits in the collective stash")
	if picked < 0:
		return
	var row: Dictionary = game.paperdoll.stash_rows[picked]
	var swap_id := str(row["item_id"])
	var swap_pool: int = warband.stash.pooled_count(swap_id)
	var worn_pool: int = warband.stash.pooled_count(worn_main)
	(row["button"] as Button).pressed.emit()
	var now_main := str(warband.roster.equipped_of(merc_id).get("main", ""))
	check(now_main == swap_id, "the paperdoll wears the stashed piece (%s)" % now_main)
	check(warband.stash.pooled_count(swap_id) == swap_pool - 1,
		"the equipped copy leaves the pool (%d -> %d)" % [swap_pool, warband.stash.pooled_count(swap_id)])
	check(warband.stash.pooled_count(worn_main) == worn_pool + 1,
		"the displaced main hand returns to the pool")

# --- altar -----------------------------------------------------------------

func check_altar() -> void:
	var point: Vector3 = game.service_point("altar")
	game.controller.active_body(1).global_position = point + Vector3(1.6, 0.1, 1.0)
	await create_timer(0.25).timeout
	check(game.interact_at(1, point) == "altar", "G at the block names the altar")
	check(game.altar.is_open(), "the altar answers G in town")
	var menu: Object = game.altar.menu()
	check(menu != null, "the altar owns its ritual menu")
	if menu != null:
		check(menu.distill_rows().size() == 5, "all five cruor tiers are listed")
	if game.altar.is_open():
		game.altar.close()

# --- recruiter -------------------------------------------------------------

func check_recruiter() -> void:
	var point: Vector3 = game.service_point("recruiter")
	game.controller.active_body(1).global_position = point + Vector3(1.4, 0.1, 1.2)
	await create_timer(0.25).timeout
	check(game.interact_at(1, point) == "recruiter", "G at the desk names the recruiter")
	check(game.screen.is_open(), "the recruiter desk opens the warband screen")
	check(game.screen.status_text().to_lower().contains("hire"),
		"the desk tells the player to hire there")
	if not game.screen.is_open():
		return

	var count_before: int = warband.roster.count()
	var gold_before: int = warband.gold()
	var cost: int = warband.hire_cost()
	var hire_button: Button = null
	for button in game.screen.hire_buttons:
		if not button.disabled:
			hire_button = button
			break
	check(hire_button != null, "the recruiter board offers an affordably-named hire")
	if hire_button == null:
		return
	hire_button.pressed.emit()
	check(warband.roster.count() == count_before + 1,
		"hiring at the desk adds a body (%d -> %d)" % [count_before, warband.roster.count()])
	check(warband.gold() == gold_before - cost,
		"hiring spends exactly the hire cost (%d -> %d, cost %d)"
			% [gold_before, warband.gold(), cost])
	check(warband.hire_cost() == 0, "the next oath is still free under the eight")

	# At the cap the board must refuse and leave the purse and roster alone.
	while warband.roster.count() < warband.deployment_cap:
		warband.add_mercenary("Oath %d" % warband.roster.count())
	game.screen.refresh()
	var cap_count: int = warband.roster.count()
	var cap_gold: int = warband.gold()
	var cap_button: Button = null
	for button in game.screen.hire_buttons:
		if not button.disabled:
			cap_button = button
			break
	check(cap_button != null, "the board keeps a pressable row at the cap")
	if cap_button != null:
		cap_button.pressed.emit()
	check(warband.roster.count() == cap_count, "the recruiter refuses at the cap")
	check(warband.gold() == cap_gold, "a refused hire costs nothing")
	game.screen.close()
