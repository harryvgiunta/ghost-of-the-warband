extends SceneTree
## The quick menu every gameplay scene opens with Escape: the pointer is freed,
## the world keeps simulating, gameplay keys are inert, SAVE GAME writes the
## journey, the display row switches the window, RESUME gives mouse-look back,
## and each scene's exit row performs its own hand-off.

const TEST_SAVE := "user://menu_regression_state.json"
const DELVE_PORT := 7834

var state
var session
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("MENU_FAIL  ",message)

func _key(code: Key, shift_pressed := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift_pressed
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift_pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _hold(code: Key, seconds: float) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await create_timer(seconds).timeout
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	Input.parse_input_event(release)
	await process_frame

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_screen_transform() * point
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	await _mouse(point,true)
	await _mouse(point,false)

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_SAVE
	state.reset(false)
	await _test_world()
	await _test_arena()
	await _test_delve()
	_remove_test_save()
	print("MENU_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _test_world() -> void:
	session.clear()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(0.5).timeout
	var menu = game.pause_menu
	check(menu != null,"The town builds the quick menu")
	check(not menu.is_open() and not game._cursor_free,"The town starts with mouse-look captured")
	await _key(KEY_ESCAPE)
	check(menu.is_open(),"Escape opens the quick menu in the town")
	check(game._cursor_free,"The quick menu frees the pointer")
	check(not paused,"The quick menu does not pause the world")
	check(game._frontier.process_mode == Node.PROCESS_MODE_INHERIT,"The frontier keeps simulating behind the menu")
	check(str(menu.exit_button.text) == "EXIT TO TITLE","The town menu exits to the title")
	# Movement is derived from held keys, not key events, so this is the real
	# proof that a menu-open player cannot walk out from behind it.
	var start: Vector3 = game.player.global_position
	await _hold(KEY_W,0.35)
	check(start.distance_to(game.player.global_position) < 0.05,"Held movement is inert behind the menu")
	await _key(KEY_I)
	check(not game._ui_open(),"The kit cannot open behind the menu")
	await _click(menu.save_button)
	check(FileAccess.file_exists(TEST_SAVE),"SAVE GAME writes the journey")
	check(str(menu._status.text).contains("saved"),"SAVE GAME reports the write")
	await _click(menu.display_button)
	if DisplayServer.get_name() == "headless":
		# A headless window reports MINIMIZED and refuses every mode change; the
		# row must then keep the mode it really has instead of claiming success.
		check(not menu.is_fullscreen() and str(menu.display_button.text).contains("WINDOWED"),"A refused display switch keeps the honest mode")
		check(str(menu._status.text).contains("Windowed"),"The display row reports the mode that stuck")
	else:
		check(menu.is_fullscreen() and str(menu.display_button.text).contains("FULLSCREEN"),"The display row switches to fullscreen")
		await _click(menu.display_button)
		check(not menu.is_fullscreen() and str(menu.display_button.text).contains("WINDOWED"),"The display row switches back to a window")
	await _click(menu.resume_button)
	check(not menu.is_open() and not game._cursor_free,"RESUME closes the menu and gives mouse-look back")
	await _key(KEY_ESCAPE)
	check(menu.is_open(),"Escape reopens the menu")
	await _key(KEY_ESCAPE)
	check(not menu.is_open(),"A second Escape closes it")
	await _key(KEY_ESCAPE)
	await _click(menu.exit_button)
	await create_timer(0.6).timeout
	check(current_scene != null and current_scene.scene_file_path == "res://title.tscn","The town's exit hands the scene back to the title menu")

func _test_arena() -> void:
	session.clear()
	var probe := PacketPeerUDP.new()
	probe.bind(0)
	var port := probe.get_local_port()
	probe.close()
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.host_game(port,"Menu tester")
	await create_timer(0.4).timeout
	check(arena.local_slot == 0,"The arena hosts a match for the menu check")
	var menu = arena.pause_menu
	check(str(menu.exit_button.text) == "LEAVE MATCH","The match menu leaves the match")
	await _key(KEY_ESCAPE)
	check(menu.is_open() and arena._cursor_free,"Escape opens the match menu")
	var weapon: String = arena.actors[0].rig.weapon
	await _key(KEY_3)
	check(arena.actors[0].rig.weapon == weapon,"Gameplay keys are inert behind the match menu")
	await _key(KEY_ESCAPE)
	check(not menu.is_open() and not arena._cursor_free,"Escape closes the match menu and recaptures mouse-look")
	await _key(KEY_ESCAPE)
	await _click(menu.exit_button)
	await create_timer(0.3).timeout
	check(arena.network_role == "offline" and arena.local_slot == -1,"LEAVE MATCH drops the session")
	check(not menu.is_open() and arena._cursor_free,"The arena lobby keeps the pointer")
	arena.queue_free()
	await process_frame

func _test_delve() -> void:
	session.clear()
	session.arm_delve("delve-solo","127.0.0.1",DELVE_PORT,"Menu tester")
	var delve = load("res://delve.tscn").instantiate()
	root.add_child(delve)
	current_scene = delve
	await create_timer(0.8).timeout
	for devil in delve.devils:
		devil.set_physics_process(false)
	var menu = delve.pause_menu
	check(str(menu.exit_button.text) == "RETURN TO SURFACE","The delve menu returns to the surface")
	await _key(KEY_ESCAPE)
	check(menu.is_open() and delve._cursor_free,"Escape opens the delve menu")
	await _key(KEY_ESCAPE)
	check(not menu.is_open() and not delve._cursor_free,"Escape closes the delve menu and recaptures mouse-look")
	await _key(KEY_ESCAPE)
	await _click(menu.exit_button)
	await create_timer(0.8).timeout
	check(current_scene != null and current_scene.scene_file_path == "res://main.tscn","RETURN TO SURFACE hands the town back")
