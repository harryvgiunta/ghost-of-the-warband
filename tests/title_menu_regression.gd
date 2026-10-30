extends SceneTree
## Main menu: new game, load saved game, join game with cached network defaults.

const TEST_SAVE := "user://title_menu_state.json"
const NetCacheScript = preload("res://scripts/net_cache.gd")

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
	check(title.start_button.text == "NEW CAMPAIGN","Start New Game is the first door")
	check(title._load_button.text == "CONTINUE","Load Saved Game is the second door")
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
	check(int(state.credits) == state.STARTING_CREDITS and state.inventory.is_empty() and state.stash.is_empty(),"New game starts with an empty pack and an empty stash")
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
	# The form reads the cache when it opens, not once at startup: a value written
	# after the title was built must show up on the next open.
	cache.remember("FreshRanger","100.64.0.44",8111,"world")
	title._close_join()
	title._open_join()
	check(title._name_input.text == "FreshRanger" and title._address_input.text == "100.64.0.44" and int(title._port_input.value) == 8111,"Join rereads the cache every time the form opens")
	check(title._join_mode.selected == 2,"Join rereads the cached open world mode")
	title._close_join()
	check(not title._join_layer.visible,"Join can be cancelled")
	title.queue_free()
	await process_frame
	cache.reset()

	# Hosting the open world opens its own port and leaves the guest-side endpoint
	# alone. A remembered join port must never move the host socket: that is how a
	# host served a port no friend had and still accepted a same-PC second instance.
	cache.remember("HostRanger","100.64.0.12",8123,"arena")
	check(cache.host_port == 7777,"The open-world port starts at 7777")
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
	check(session.port == 7777 and session.address == "127.0.0.1" and session.player_name == "HostRanger","Hosting opens the open-world port, never the last join port")
	check(cache.mode == "world","Hosting the open world remembers the world mode")
	check(cache.port == 8123 and cache.address == "100.64.0.12","Hosting leaves the remembered join endpoint untouched")
	check(cache.host_port == 7777,"Hosting remembers its own open-world port")
	check(title._status.text.contains("UDP 7777"),"Hosting the open world reports the UDP port")
	check(int(state.credits) == credits_before and state.inventory.size() == inventory_before and state.stash.size() == stash_before,"Hosting the open world leaves the save alone")
	check(current_scene == null,"Hosting the open world enters no scene during the test")

	# Both values survive a restart, and an older cache has no host port at all.
	var reloaded = NetCacheScript.new()
	reloaded.save_path = cache.save_path
	reloaded.load_cache()
	check(reloaded.host_port == 7777 and reloaded.port == 8123 and reloaded.address == "100.64.0.12","The open-world port survives a restart without moving the join port")
	reloaded.free()
	var legacy_file := FileAccess.open("user://net_cache_legacy.json",FileAccess.WRITE)
	legacy_file.store_string('{"version":1,"player_name":"Legacy","address":"100.64.0.7","port":52140,"mode":"world"}')
	legacy_file.close()
	var legacy = NetCacheScript.new()
	legacy.save_path = "user://net_cache_legacy.json"
	legacy.load_cache()
	check(legacy.port == 52140 and legacy.host_port == 7777,"A version-1 cache keeps its join port and defaults the open-world port to 7777")
	legacy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://net_cache_legacy.json"))

	# The warband door is a new campaign, never a resume: however the last one
	# ended, pressing it puts a fresh warband in the cages. It used to load the
	# save and drop the player in town, which is exactly what a player clicking
	# "Ghost of the Warband" for a new run does not want.
	var warband = root.get_node_or_null("Warband")
	var flow = root.get_node_or_null("GameFlow")
	if warband != null and flow != null:
		title.queue_free()
		await process_frame
		warband.save_path = "user://title_warband.json"
		warband.reset_state()
		warband.add_mercenary("Old Ash")
		warband.award_gold(500)
		warband.save_state()
		check(warband.roster.count() == 1, "a saved warband exists to resume")
		flow.active = false
		flow.world_start = "town"
		title = load("res://title.tscn").instantiate()
		root.add_child(title)
		await process_frame
		check(title.warband_button != null, "the warband door is on the title")
		# The door is heard and the score is handed over: the menu theme stops
		# outright and the soundtrack starts at its own beginning.
		var audio_node = root.get_node_or_null("Audio")
		if audio_node != null:
			audio_node.last_event = ""
		title.warband_button.pressed.emit()
		if audio_node != null:
			check(audio_node.last_event == "menu_thud",
				"the warband door must sound as a door (%s)" % audio_node.last_event)
			check(audio_node.music_track == "warband",
				"the warband door must hand the score to the campaign (%s)" % audio_node.music_track)
		check(flow.world_start == "camp", "the warband door starts at the cages (%s)" % flow.world_start)
		check(warband.roster.count() == 0, "the warband door begins a fresh warband (%d bodies)"
			% warband.roster.count())
		check(warband.gold() == int(state.STARTING_CREDITS),
			"a fresh warband starts on the starting purse, not the saved one (%d)" % warband.gold())

		# The skip door warns first, and only then opens the campaign in town.
		check(title.warband_skip_button != null, "the skip tutorial door is on the title")
		title.warband_skip_button.pressed.emit()
		check(title._skip_layer != null and title._skip_layer.visible,
			"the skip door asks before it throws the tutorial away")
		if audio_node != null:
			audio_node.last_event = ""
		title.skip_confirm_button.pressed.emit()
		check(not title._skip_layer.visible, "confirming closes the warning")
		check(flow.world_start == "town",
			"a skipped tutorial starts in Hearthstead (%s)" % flow.world_start)
		if audio_node != null:
			check(audio_node.last_event == "menu_thud", "the skip door sounds as a door")
		flow.active = false
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://title_warband.json"))

	session.clear()
	state.reset(false)
	cache.reset()
	_remove_test_save()
	print("TITLE_MENU_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
