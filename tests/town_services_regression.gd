extends SceneTree
## The three keepers, the stash, the arena portal and the jump-down hatch are
## real town objects, and I / P drive the in-world inventory and equipment.

const TEST_SAVE := "user://town_services_state.json"
const StateScript = preload("res://scripts/player_state.gd")

var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TOWN_FAIL  ",message)

func _wait_delve_gone(game, timeout: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if game._delve_inner == null:
			return true
		await create_timer(0.05).timeout
	return game._delve_inner == null

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _entry(world, kind: String) -> Dictionary:
	for item in world.interactables:
		if str(item.kind) == kind:
			return item
	return {}

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	state.save_path = TEST_SAVE
	state.reset(false)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout
	game.set_physics_process(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)

	check(state.inventory.size() == StateScript.STARTING_INVENTORY.size() and state.credits == StateScript.STARTING_CREDITS,"Starter kit loads")
	check(game.world.player_spawn.distance_to(Vector3(0,3,47)) < 0.05,"New game spawns at the town gate")
	check(game.world.interactables.size() == 10,"Town exposes camp, delve, three keepers, stash, portal and three waystones")
	check(game.world.landmarks.size() == 8,"The map gains the delve, the camp and the village landmarks")

	var vendors := []
	for item in game.world.interactables:
		if str(item.kind) == "vendor":
			vendors.append(item)
	check(vendors.size() == 3,"Three vendor keepers exist")
	var vendor_ids := {}
	for item in vendors:
		vendor_ids[int(item.vendor)] = item
	check(vendor_ids.size() == 3 and vendor_ids.has(0) and vendor_ids.has(1) and vendor_ids.has(2),"All three vendor seats are present")
	for index in [0,1,2]:
		var entry: Dictionary = vendor_ids[index]
		check(Vector2(entry.position.x,entry.position.z).distance_to(Vector2(0,32)) < 29.0,"Vendor %d sits in town" % index)
		game.player.global_position = entry.position + Vector3(0,0.1,0)
		game._update_interaction()
		check(game._interaction_kind == "vendor" and game._interaction_vendor == index,"Vendor %d is the nearest prompt" % index)
		game.interact()
		check(game.world_ui.is_open() and game.world_ui.active_view() == "vendor","Talking to vendor %d opens their stock" % index)
		check(game.world_ui.stock_buttons.size() >= (StateScript.VENDORS[index].stock as Array).size(),"Vendor stock renders every row")
		game.world_ui.close()
		check(not game.world_ui.is_open(),"Closing the shop works")

	var stash_entry := _entry(game.world,"stash")
	check(not stash_entry.is_empty(),"The town stash chest exists")
	game.player.global_position = stash_entry.position + Vector3(0,0.1,0)
	game._update_interaction()
	check(game._interaction_kind == "stash","The stash chest is interactive")
	game.interact()
	check(game.world_ui.is_open() and game.world_ui.active_view() == "stash","The stash opens beside the backpack")
	check(game.world_ui.stash_buttons.size() == 20,"The stash renders twenty slots")
	# Move the first backpack piece into the stash and back.
	var before: int = state.inventory.size()
	game.world_ui._location = "backpack"
	game.world_ui._index = 0
	game.world_ui._on_secondary()
	check(state.stash.size() == 1 and state.inventory.size() == before - 1,"Backpack moves into the stash")
	game.world_ui._location = "stash"
	game.world_ui._index = 0
	game.world_ui._on_primary()
	check(state.stash.is_empty() and state.inventory.size() == before,"Stash moves back to the backpack")
	game.world_ui.close()

	# I shows the pack; P shows the paperdoll. Equipping mutates the live kit.
	game.toggle_inventory()
	check(game.world_ui.is_open() and game.world_ui.active_view() == "inventory","I opens the backpack")
	check(game.world_ui.inventory_panel.visible and game.world_ui.paperdoll_panel.visible,"I opens the combined kit")
	var sword_index: int = state.inventory.find("sword_short")
	check(sword_index >= 0,"The starter sword is in the pack")
	game.world_ui._location = "backpack"
	game.world_ui._index = sword_index
	game.world_ui._on_primary()
	check(state.equipped_id("main") == "sword_short","Equipping from the pack updates the main hand")
	check(state.inventory.has("bow_short"),"The displaced bow returns to the pack")
	game.toggle_equipment()
	check(game.world_ui.is_open() and game.world_ui.active_view() == "equipment","P switches to the paperdoll")
	check(game.world_ui.paperdoll_panel.visible and game.world_ui.inventory_panel.visible,"P opens the combined kit")
	check(game.world_ui.paperdoll_buttons.size() == 10,"The paperdoll renders ten slots")
	game.world_ui._location = "paperdoll"
	game.world_ui._slot = "main"
	game.world_ui._on_primary()
	check(state.equipped_id("main").is_empty() and state.inventory.has("sword_short"),"Unequipping from the paperdoll returns the sword to the pack")

	# Buying at the Smith costs credits and fills the pack.
	var credits_before := int(state.credits)
	var smith: Dictionary = vendor_ids[1]
	game.player.global_position = smith.position + Vector3(0,0.1,0)
	game._update_interaction()
	game.interact()
	var stock_index: int = StateScriptStockIndex(1,"sword_arming")
	check(stock_index >= 0,"Smith stocks the arming sword")
	game.world_ui._location = "stock"
	game.world_ui._stock_item = "sword_arming"
	game.world_ui._on_buy()
	check(int(state.credits) == credits_before - 195,"Buying deducts the price")
	check(state.inventory.has("sword_arming"),"Buying appends the piece to the pack")
	game.world_ui.close()

	# World drops leave the pack as an unarmed pickup at the ranger's feet.
	game.world_ui.open_inventory()
	var drop_index: int = state.inventory.size() - 1
	var drop_id: String = state.inventory[drop_index]
	var drop_copies: int = state.inventory.count(drop_id)
	var pickups_before: int = game.loot_pickups.size()
	game.world_ui._location = "backpack"
	game.world_ui._index = drop_index
	game.world_ui._on_tertiary()
	check(game.loot_pickups.size() == pickups_before + 1,"Dropping spawns a world pickup")
	check(state.inventory.count(drop_id) == drop_copies - 1,"Dropping removes one piece from the pack")
	if game.loot_pickups.size() > 0:
		check(not bool(game.loot_pickups[-1].armed),"Fresh drops start unarmed")
	game.world_ui.close()

	# The hatch is a physical hole; entering arms a solo delve.
	check(game.world.is_over_delve_hatch(Vector3(16,2.0,42)),"The hatch footprint is open at floor level")
	check(not game.world.is_over_delve_hatch(Vector3(14,2.0,42)),"The hatch footprint is local")
	var hole_query := PhysicsRayQueryParameters3D.create(Vector3(16,3.5,42),Vector3(16,-10,42),1)
	var hole_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(hole_query)
	check(hole_hit.is_empty(),"The hatch cell has no terrain collision")
	var floor_query := PhysicsRayQueryParameters3D.create(Vector3(13,3.5,42),Vector3(13,-1,42),1)
	check(not game.get_world_3d().direct_space_state.intersect_ray(floor_query).is_empty(),"The inn floor around the hatch is solid")
	game._enter_delve()
	await create_timer(0.5).timeout
	check(is_instance_valid(game) and game.is_inside_tree(),"Entering the hatch keeps the session loaded")
	var delve = game._delve_inner
	check(delve != null and is_instance_valid(delve),"Entering the hatch opens the delve inside the session")
	if is_instance_valid(delve):
		check(String(delve.get_path()) == "/root/Ironwood/Delve","The run is an inner instance of the town session")
		check(str(delve.phase) == "ALTAR","The delve starts at the altar phase")
		check(not game._frontier.visible,"The town is frozen behind the run")
		delve._set_phase("CLEARED")
		delve.ascend_to_surface()
		check(await _wait_delve_gone(game),"The rope hands the town back")
		check(game._frontier.visible and game._ui_layer.visible,"The town is live again after the rope")

	state.reset(false)
	_remove_test_save()
	print("TOWN_SERVICES_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func StateScriptStockIndex(vendor: int, item_id: String) -> int:
	var vendors: Array = StateScript.VENDORS
	if vendor < 0 or vendor >= vendors.size():
		return -1
	return vendors[vendor].stock.find(item_id)
