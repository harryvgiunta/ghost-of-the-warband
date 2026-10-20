extends SceneTree

var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	game.combat.set_aim(game.player.position + Vector3(0,1.7,-24))
	game.combat.begin_draw()
	var deadline := Time.get_ticks_msec() + 4000
	while game.archer.phase != "HOLDING" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.archer.phase == "HOLDING", "World controller must reach a complete draw")
	var direction: Vector3 = game.archer.active_bow.get_arrow_direction()
	var grip: Vector3 = game.archer.bow_hand.global_position
	var feet_origin: Vector3 = game.player.global_position
	game.combat.release_draw()
	deadline = Time.get_ticks_msec() + 2000
	while game.archer.draw_amount > 0.01 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.archer.phase == "RELEASE", "String returns during follow-through")
	check(game.archer.active_bow.get_arrow_direction().dot(direction) > 0.9995, "Dropping string tension must not retarget or pitch the archer backward")
	check(game.archer.bow_hand.global_position.distance_to(grip) < 0.015, "Bow arm remains steady in the real world controller")
	check(game.player.global_position.distance_to(feet_origin) < 0.01, "Stationary shot preserves its planted stance")
	key(KEY_W, true)
	await create_timer(0.3).timeout
	check(game.player.global_position.distance_to(feet_origin) > 0.5, "Manual shot recovery does not freeze movement")
	key(KEY_W, false)
	for voice in game.audio.voices:
		if voice.playing:
			await voice.finished
	game.queue_free()
	await process_frame
	print("GAMEPLAY_REGRESSION failures=", failures)
	quit(0 if failures == 0 else 1)
