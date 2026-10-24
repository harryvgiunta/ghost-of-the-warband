extends SceneTree
## Main menu: new game, load saved game, join game with cached network defaults.

const TEST_SAVE := "user://title_menu_state.json"

var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TITLE_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://title.tscn","The title screen is the game's entry scene")
	state = root.get_node("PlayerState")
	state.save_path = TEST_SAVE
	state.reset(false)
	var starting_inventory: Array = state.inventory.duplicate()
	var starting_credits := int(state.credits)

	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(title.start_button.visible and title._load_button.visible and title.join_button.visible,"All three menu actions are visible")
	check(title._load_button.disabled,"Load is disabled when no save exists")
	title._load_saved_game()
	title.queue_free()
	await process_frame

	# A saved purse and stash load back into the world.
	state.add_credits(700)
	state.move_to_stash(0)
	var credits := int(state.credits)
	var stash_size: int = state.stash.size()
	title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(not title._load_button.disabled,"Load is enabled when a save exists")
	title._load_saved_game()
	await create_timer(0.6).timeout
	check(int(state.credits) == credits and state.stash.size() == stash_size,"Loading restores the saved purse and stash")
	check(current_scene != null and current_scene.scene_file_path == "res://main.tscn","Loading enters the town")
	if current_scene != null and current_scene.get("world") != null:
		check(current_scene.world.player_spawn.distance_to(Vector3(0,3,47)) < 0.05,"Loaded games start at the town gate")
	title.queue_free()
	await process_frame

	# New game resets the character and starts at the town gate.
	title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	title._start_new_game()
	await create_timer(0.6).timeout
	check(int(state.credits) == starting_credits and state.inventory == starting_inventory and state.stash.is_empty(),"New game discards the loaded purse and stash and restores the starting inventory")
	check(current_scene != null and current_scene.scene_file_path == "res://main.tscn","New game enters the town")
	if current_scene != null and current_scene.get("world") != null:
		check(current_scene.world.player_spawn.distance_to(Vector3(0,3,47)) < 0.05,"New games start at the town gate")
	title.queue_free()
	await process_frame

	# Join game reuses the cached name, address, port and mode.
	var cache = root.get_node("NetCache")
	cache.remember("CachedRanger","100.64.0.12",7999,"delve")
	title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	title._open_join()
	check(title._join_layer.visible,"Join opens the form")
	check(title._name_input.text == "CachedRanger" and title._address_input.text == "100.64.0.12" and int(title._port_input.value) == 7999,"Join restores cached details")
	check(title._join_mode.selected == 1,"Join restores the cached delve mode")
	title._close_join()
	check(not title._join_layer.visible,"Join can be cancelled")
	title.queue_free()
	await process_frame
	cache.reset()

	state.reset(false)
	_remove_test_save()
	print("TITLE_MENU_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
