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

	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(title.start_button.text == "START NEW GAME","Start New Game is the first door")
	check(title._load_button.text == "LOAD SAVED GAME","Load Saved Game is the second door")
	check(title.host_world_button.text == "HOST OPEN WORLD","Host Open World is the third door")
	check(title.join_button.text == "JOIN GAME","Join Game is the fourth door")
	check(title.start_button.visible and title._load_button.visible and title.host_world_button.visible and title.join_button.visible,"All four menu actions are visible")
	check(title._load_button.disabled,"Load is disabled when no save exists")
	title._load_saved_game()
	check(title._status.text.contains("No saved journey"),"Loading an absent save explains itself")
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
	check(int(state.credits) == 200 and state.inventory.size() == state.STARTING_INVENTORY.size() and state.stash.is_empty(),"New game restores the starter kit")
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
	check(title._join_mode.get_item_text(2) == "Open world","Join offers the open world mode")
	title._close_join()
	check(not title._join_layer.visible,"Join can be cancelled")
	title.queue_free()
	await process_frame
	cache.remember("CachedRanger","100.64.0.12",7999,"world")
	title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	title._open_join()
	check(title._join_mode.selected == 2,"Join restores the cached open world mode")
	title._close_join()
	title.queue_free()
	await process_frame
	cache.reset()

	# Hosting the open world arms a world host on the cached port and leaves the save alone.
	cache.remember("HostRanger","127.0.0.1",8123,"arena")
	var session = root.get_node("Session")
	var credits_before := int(state.credits)
	var inventory_before: int = state.inventory.size()
	var stash_before: int = state.stash.size()
	title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	session.clear()
	title.host_world_button.pressed.emit()
	check(session.mode == "world-host","Hosting the open world arms a world host")
	check(session.port == 8123 and session.address == "127.0.0.1" and session.player_name == "HostRanger","Hosting the open world uses the cached port, address and name")
	check(cache.mode == "world","Hosting the open world remembers the world mode")
	check(title._status.text.contains("UDP 8123"),"Hosting the open world reports the UDP port")
	check(int(state.credits) == credits_before and state.inventory.size() == inventory_before and state.stash.size() == stash_before,"Hosting the open world leaves the save alone")
	check(current_scene == null,"Hosting the open world enters no scene during the test")

	session.clear()
	state.reset(false)
	cache.reset()
	_remove_test_save()
	print("TITLE_MENU_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
