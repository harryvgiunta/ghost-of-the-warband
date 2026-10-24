extends SceneTree
## In-game I-key paperdoll/backpack wiring in the frontier, delve and arena.

const StateScript = preload("res://scripts/player_state.gd")
const TEST_SAVE := "user://field_inventory_state.json"

var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("FIELD_INV_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	state.save_path = TEST_SAVE
	state.reset()
	await _test_frontier()
	await _test_delve()
	await _test_arena()
	state.reset()
	_remove_test_save()
	print("FIELD_INVENTORY_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _test_frontier() -> void:
	state.reset()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game.set_physics_process(false)
	check(game.field_inventory != null,"The frontier builds the field inventory")
	await _key(KEY_I)
	check(game._field_inventory_open(),"I opens the field paperdoll in the frontier")
	var hud = game.field_inventory.hud
	check(hud.field_mode,"The field overlay runs in field mode")
	check(hud.paperdoll_buttons.size() == 10 and hud.backpack_buttons.size() == 10,"The field overlay renders ten paperdoll and ten backpack slots")
	check(not hud.header_panel.visible and not hud.vendor_panel.visible and not hud.stash_panel.visible,"The field overlay hides Hollow-only panels")
	check(hud.close_button.visible,"The field overlay exposes a close button")
	check(game._cursor_free,"Opening the field overlay frees the cursor")

	var sword: int = state.inventory.find("sword_short")
	check(sword >= 0,"The starter sword is in the field backpack")
	hud._on_backpack_slot(sword)
	hud._on_equip()
	check(state.main_item() == "sword_short","Equipping from the field paperdoll updates PlayerState")
	check(game.archer.main_hand_kind == "sword" and game.archer.active_sword.visible,"The live ranger follows the field equip")
	check(state.inventory.has("bow_short"),"The displaced bow returns to the field backpack")
	hud.close_button.pressed.emit()
	await process_frame
	check(not game._field_inventory_open() and not game._cursor_free,"Closing the field overlay recaptures mouse-look")

	await _key(KEY_I)
	var bow: int = state.inventory.find("bow_short")
	check(bow >= 0,"The displaced bow is visible in the field backpack")
	hud = game.field_inventory.hud
	hud._on_backpack_slot(bow)
	hud._on_drop()
	check(not state.inventory.has("bow_short"),"Dropping in the field removes the item from the backpack")
	check(game.loot_pickups.size() == 1,"Dropping in the field creates a world pickup")
	var pickup = game.loot_pickups[0]
	check(not bool(pickup.get("armed")),"A field drop starts unarmed")
	game.player.global_position += Vector3(6,0,0)
	game._collect_loot(0.0)
	check(game.loot_pickups.size() == 1 and bool(pickup.get("armed")),"Stepping clear arms the field drop")
	game.player.global_position = pickup.global_position
	game._collect_loot(0.0)
	check(state.inventory.has("bow_short") and game.loot_pickups.is_empty(),"Walking back over the drop banks it again")
	await _key(KEY_ESCAPE)
	check(not game._field_inventory_open(),"Escape closes the field overlay")

	var inn = game.world.find_child("WayfarerInn",true,false)
	var hatch = game.world.find_child("SunkenDelveHatch",true,false)
	check(inn != null and hatch != null,"The Wayfarer Inn contains the delve hatch")
	if inn != null and hatch != null:
		var local: Vector3 = inn.to_local(hatch.global_position)
		check(absf(local.x) < 3.4 and absf(local.z) < 2.8,"The delve hatch sits inside the inn")
	var entry: Dictionary = {}
	for record in game.world.interactables:
		if str(record.get("id","")) == "delve":
			entry = record
			break
	check(not entry.is_empty(),"The hatch remains the frontier delve interaction")
	if not entry.is_empty():
		check(game.player.global_position.distance_to(entry.position) > 0.0,"The delve interaction has a world position")
		game.player.global_position = (entry.position as Vector3) + Vector3(0,0.25,1.0)
		game._update_interaction()
		check(game._interaction_id == "delve" and game._interaction_allowed,"The hatch is usable from inside the inn")
		check(game.hud._interaction.text.to_lower().contains("hatch"),"The hatch prompt names the hatch")
	game.queue_free()
	await process_frame

func _test_delve() -> void:
	state.reset()
	var session = root.get_node("Session")
	session.clear()
	session.arm_delve("delve-solo","127.0.0.1",7777,"Field Inventory")
	var delve = load("res://delve.tscn").instantiate()
	root.add_child(delve)
	current_scene = delve
	var deadline := Time.get_ticks_msec() + 5000
	while delve.network_role != "host" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(delve.network_role == "host" and delve.local_slot == 0,"The delve field test hosts a local room")
	check(delve._field_inventory != null,"The delve builds the field inventory")
	await _key(KEY_I)
	check(delve._field_inventory_open(),"I opens the field paperdoll in the delve")
	var hud = delve._field_inventory.hud
	var sword: int = state.inventory.find("sword_short")
	check(sword >= 0,"The delve shares the persistent backpack")
	hud._on_backpack_slot(sword)
	hud._on_equip()
	check(state.main_item() == "sword_short","Delve equipping updates PlayerState")
	check(delve.actors[0].rig.main_hand_kind == "sword" and delve.actors[0].rig.active_sword.visible,"Delve equipping updates the local rig")
	var bow: int = state.inventory.find("bow_short")
	check(bow >= 0,"The displaced bow is in the delve backpack")
	hud._on_backpack_slot(bow)
	hud._on_drop()
	check(not state.inventory.has("bow_short"),"Delve dropping removes the item")
	check(delve.loot_pickups.size() == 1,"Delve dropping spawns a local world pickup")
	var entry: Dictionary = delve.loot_pickups[0]
	var pickup = entry.get("node")
	check(not bool(entry.get("armed")),"A delve field drop starts unarmed")
	delve.actors[0].global_position += Vector3(4,0,0)
	delve._collect_loot(0.0)
	check(bool(entry.get("armed")),"Stepping clear arms the delve drop")
	delve.actors[0].global_position = pickup.global_position
	delve._collect_loot(0.0)
	check(state.inventory.has("bow_short") and delve.loot_pickups.is_empty(),"The delve drop can be picked back up")
	await _key(KEY_ESCAPE)
	check(not delve._field_inventory_open(),"Escape closes the delve field paperdoll")
	delve.leave_game()
	delve.queue_free()
	await process_frame

func _test_arena() -> void:
	state.reset()
	var session = root.get_node("Session")
	session.clear()
	session.arm_arena("host","127.0.0.1",7815,"Field Inventory")
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	var deadline := Time.get_ticks_msec() + 5000
	while arena.network_role != "host" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(arena.network_role == "host" and arena.local_slot == 0,"The arena field test hosts a local room")
	check(arena._field_inventory != null,"The arena builds the field inventory")
	await _key(KEY_I)
	check(arena._field_inventory_open(),"I opens the field paperdoll in the arena")
	var hud = arena._field_inventory.hud
	var sword: int = state.inventory.find("sword_short")
	check(sword >= 0,"The arena shares the persistent backpack")
	hud._on_backpack_slot(sword)
	hud._on_equip()
	check(state.main_item() == "sword_short","Arena equipping updates PlayerState")
	check(arena.actors[0].rig.main_hand_kind == "sword" and arena.actors[0].rig.active_sword.visible,"Arena equipping updates the local rig")
	var bow: int = state.inventory.find("bow_short")
	check(bow >= 0,"The displaced bow is in the arena backpack")
	hud._on_backpack_slot(bow)
	hud._on_drop()
	check(state.floor_items.has("bow_short"),"Arena drops fall back to the Hollow floor")
	await _key(KEY_ESCAPE)
	check(not arena._field_inventory_open(),"Escape closes the arena field paperdoll")
	arena.leave_game()
	arena.queue_free()
	await process_frame
