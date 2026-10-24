extends SceneTree
## End-to-end entry paths: the Hollow's DESCEND button and the Wayfarer Inn
## hatch both hand off through Session and land in a hosted delve scene.

const Progress = preload("res://scripts/delve_progress.gd")
const TEST_STATE := "user://delve_entry_state.json"
const TEST_RUN := "user://delve_entry_run.json"

var failures := 0
var checks := 0
var state
var session

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DELVE_ENTRY_FAIL  ", message)

func _wait_scene(path: String, timeout: float = 8.0) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var scene := current_scene
		if scene != null and scene.scene_file_path == path:
			return scene
		await process_frame
	var fallback := current_scene
	return fallback if fallback != null and fallback.scene_file_path == path else null

func _drop_scene() -> void:
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame

func _test_menu_path() -> void:
	var menu = load("res://menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	check(menu.hud.delve_button != null, "The Hollow builds the delve button")
	menu._enter_delve_solo()
	var delve = await _wait_scene("res://delve.tscn")
	check(delve != null, "The Hollow loads the delve scene")
	if delve == null:
		return
	var hosted := false
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if delve.network_role == "host":
			hosted = true
			break
		await process_frame
	check(hosted, "The Hollow's solo deploy hosts the room")
	check(delve.phase == "ASSEMBLY", "The deploy lands on the surface staging")
	check(delve.world != null and delve.world.player_spawns.size() == 4, "The loaded room has its party spawns")
	delve.leave_game()
	await _drop_scene()

func _test_town_path() -> void:
	session.clear()
	var frontier = load("res://main.tscn").instantiate()
	root.add_child(frontier)
	current_scene = frontier
	await create_timer(0.6).timeout
	var entry: Dictionary = {}
	for record in frontier.world.interactables:
		if str(record.get("id", "")) == "delve":
			entry = record
			break
	check(not entry.is_empty(), "Hearthstead contains the delve hatch")
	if entry.is_empty():
		await _drop_scene()
		return
	var inn = frontier.world.find_child("WayfarerInn",true,false)
	var hatch = frontier.world.find_child("SunkenDelveHatch",true,false)
	check(inn != null and hatch != null, "The Wayfarer Inn contains the Sunken Delve hatch")
	if inn != null and hatch != null:
		var local: Vector3 = inn.to_local(hatch.global_position)
		check(absf(local.x) < 3.4 and absf(local.z) < 2.8, "The hatch is inside the house")
	frontier.player.global_position = (entry.get("position", Vector3.ZERO) as Vector3) + Vector3(0, 0.25, 1.0)
	frontier._update_interaction()
	check(frontier._interaction_allowed, "The hatch can be used from inside the inn")
	frontier._enter_delve()
	var delve = await _wait_scene("res://delve.tscn")
	check(delve != null, "The hatch loads the delve scene")
	if delve != null:
		var hosted := false
		var deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < deadline:
			if delve.network_role == "host":
				hosted = true
				break
			await process_frame
		check(hosted, "The inn hatch hosts a local room")
		delve.leave_game()
	await _drop_scene()

func _test_host_hatch_path() -> void:
	session.clear()
	var frontier = load("res://main.tscn").instantiate()
	root.add_child(frontier)
	current_scene = frontier
	await create_timer(0.6).timeout
	frontier._delve_host = true
	frontier._delve_port = 7816
	frontier._delve_name = "Hatch Host"
	var entry: Dictionary = {}
	for record in frontier.world.interactables:
		if str(record.get("id", "")) == "delve":
			entry = record
			break
	check(not entry.is_empty(), "The host path can find the inn hatch")
	if entry.is_empty():
		await _drop_scene()
		return
	frontier.player.global_position = (entry.get("position", Vector3.ZERO) as Vector3) + Vector3(0, 0.25, 1.0)
	frontier._update_interaction()
	frontier._enter_delve()
	var delve = await _wait_scene("res://delve.tscn")
	check(delve != null, "The host hatch loads the delve scene")
	if delve != null:
		var hosted := false
		var deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < deadline:
			if delve.network_role == "host":
				hosted = true
				break
			await process_frame
		check(hosted, "Host Tailscale's hatch descent hosts the delve")
		check(str(delve._endpoint).contains("7816"), "The host hatch uses the requested UDP port")
		delve.leave_game()
	await _drop_scene()

func _test_ascent_path() -> void:
	session.clear()
	Progress.clear_run(TEST_RUN)
	session.arm_delve("delve-solo", "127.0.0.1", 7777, "Ascent")
	var delve = load("res://delve.tscn").instantiate()
	delve.save_path = TEST_RUN
	root.add_child(delve)
	current_scene = delve
	var hosted := false
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if delve.network_role == "host":
			hosted = true
			break
		await process_frame
	check(hosted, "The ascent fixture hosts")
	if not hosted:
		await _drop_scene()
		return
	delve.begin_descent()
	var spawned := false
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if delve.devils.size() >= 2:
			spawned = true
			break
		await process_frame
	check(spawned, "The ascent fixture receives its wave")
	for devil in delve.devils.duplicate():
		if is_instance_valid(devil) and devil.alive:
			devil.take_damage(9999.0, -1)
	var cleared := false
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if delve.phase == "CLEARED" and delve.chest_ready:
			cleared = true
			break
		await process_frame
	check(cleared, "The ascent fixture clears its wave")
	delve.ascend_to_surface()
	var frontier = await _wait_scene("res://main.tscn")
	check(frontier != null, "Ascending returns the party to the open frontier")
	check(not Progress.load_run(TEST_RUN).is_empty(), "Ascending keeps the cleared checkpoint")
	Progress.clear_run(TEST_RUN)
	await _drop_scene()

func run() -> void:
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_STATE
	state.reset()
	session.clear()
	await _test_menu_path()
	await _test_town_path()
	await _test_host_hatch_path()
	await _test_ascent_path()
	state.reset()
	session.clear()
	if FileAccess.file_exists(TEST_STATE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_STATE))
	Progress.clear_run(TEST_RUN)
	print("DELVE_ENTRY_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
