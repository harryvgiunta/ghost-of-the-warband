extends SceneTree
## The F12 performance overlay, in the real campaign world: the key opens it and
## closes it again - over the campaign menu too - and while it is up it measures
## real frames and times the world's major functions by name, with every scope
## balanced. Closed, the profiler is off. The profiler's own arithmetic (own time
## against total time, one row per parent, a lost `end` reported) is checked
## first, because every number on the overlay is read off it.

const Perf = preload("res://scripts/perf_probe.gd")

const WORLD := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://perf_overlay_player.json"
const WARBAND_SAVE := "user://perf_overlay_warband.json"
## The world's own frame, named: the physics tick, the soul's step over the
## bodies, a body's step, the rigs every body wears, and the HUD. A readout
## without these is not measuring the game.
const WORLD_SCOPES := ["world.physics", "soul.step", "body.step", "rig.anim", "hud"]
## Long enough for several of the overlay's quarter-second windows.
const MEASURE_SECONDS := 1.5

var state
var warband
var game
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("PERF_OVERLAY_FAIL  ", message)


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

	var watch := Timer.new()
	watch.wait_time = 60.0
	watch.one_shot = true
	watch.timeout.connect(func() -> void:
		check(false, "the overlay test did not finish inside its watchdog")
		_finish())
	root.add_child(watch)
	watch.start()

	_check_profiler()
	await _check_overlay()
	_finish()


# --- the profiler ----------------------------------------------------------

func _check_profiler() -> void:
	check(not Perf.enabled, "the profiler is off until the overlay opens it")
	Perf.enabled = true
	Perf.reset()
	Perf.tick()
	Perf.begin("test.outer")
	Perf.begin("test.inner")
	OS.delay_usec(3000)
	Perf.end()
	Perf.end()
	Perf.begin("test.inner")
	Perf.end()
	Perf.tick()
	var outer := _row(Perf.rows(), "test.outer", 0)
	var nested := _row(Perf.rows(), "test.inner", 1)
	var root_inner := _row(Perf.rows(), "test.inner", 0)
	check(not outer.is_empty() and not nested.is_empty() and not root_inner.is_empty(),
		"the same name under two parents is two rows (%s)" % str(Perf.rows()))
	if not outer.is_empty() and not nested.is_empty() and not root_inner.is_empty():
		check(int(nested["total_us"]) >= 3000, "a scope's total covers its body (%d us)" % nested["total_us"])
		check(int(outer["total_us"]) >= int(nested["total_us"]), "a parent's total covers its child")
		check(int(outer["own_us"]) == int(outer["total_us"]) - int(nested["total_us"]),
			"own time is the total less the child scopes")
		check(int(nested["calls"]) == 1 and int(root_inner["calls"]) == 1,
			"each row counts only its own calls")
		check(Perf.scoped_us() == int(outer["total_us"]) + int(root_inner["total_us"]),
			"scoped time counts nested time once")
		var order := Perf.rows()
		var at := order.find(outer)
		check(at >= 0 and at + 1 < order.size() and order[at + 1] == nested,
			"a child is listed right under its parent")
	check(Perf.imbalanced == 0, "balanced pairs report no lost end")
	Perf.begin("test.lost")
	Perf.tick()
	check(Perf.imbalanced == 1, "a frame that closes with a scope open is reported")
	Perf.begin("test.after")
	Perf.end()
	check(not _row(Perf.rows(), "test.after", 0).is_empty(),
		"after a lost end the next scope is a root again, not a child of the lost one")
	Perf.enabled = false
	Perf.reset()


func _row(rows: Array[Dictionary], name: String, depth: int) -> Dictionary:
	for row in rows:
		if str(row["name"]) == name and int(row["depth"]) == depth:
			return row
	return {}


# --- the overlay in the world -----------------------------------------------

func _check_overlay() -> void:
	var overlay = root.get_node_or_null("PerfOverlay")
	check(overlay != null, "the PerfOverlay autoload exists")
	if overlay == null:
		return
	check(not overlay.is_open(), "the overlay starts closed")
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(2.0).timeout
	check(game.controller != null and game.controller.active_body(1) != null,
		"the world is up with the soul in a body")

	_press(KEY_F12)
	await process_frame
	check(overlay.is_open(), "F12 opens the overlay")
	check(Perf.enabled, "an open overlay switches the profiler on")
	# Every window is read: a lost `end` anywhere in the world's frame shows in
	# the window it happened in, and the next window starts clean.
	var lost := 0
	var until := Time.get_ticks_msec() + int(MEASURE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		lost = maxi(lost, Perf.imbalanced)
	check(lost == 0, "no scope in the world's frame loses its end (%d frames)" % lost)

	var text: String = overlay.text()
	var headline := text.get_slice("\n", 0)
	check(headline.contains("fps") and float(headline.strip_edges().get_slice(" ", 0)) > 0.0,
		"the headline is a measured frame rate (%s)" % headline)
	check(text.contains("worst") and text.contains("1% low"), "the frame line carries the worst frame and the 1% low")
	check(_line_starting(text, "render ").contains("draws"), "the renderer's time and counters are listed")
	check(_line_starting(text, "physics ").contains("pairs"), "the physics step and its counters are listed")
	check(_line_starting(text, "world ").contains("bodies"),
		"the world contributes its own line (%s)" % _line_starting(text, "world "))
	# The engine's own monitors are an average over the window, and physics is
	# printed per step: one slow step must not pass itself off as every frame's
	# cost, and the frame only decides how many steps it pays for.
	var physics_line := _line_starting(text, "physics ")
	check(physics_line.contains("other") and physics_line.contains("x"),
		"the frame's unscripted share is printed beside the steps it ran (%s)" % physics_line)
	# The frame that hurt, named: what an average cannot show, and the only
	# reading that explains a 1%% low.
	var slowest := _line_starting(text, "slowest ")
	var slow_fields := slowest.strip_edges().split(" ", false)
	var frame_fields := _line_starting(text, "frame ").strip_edges().split(" ", false)
	check(slow_fields.size() > 2 and float(slow_fields[1]) > 0.0 and slowest.contains("·"),
		"the readout names the scopes of the slowest frame (%s)" % slowest)
	check(float(slow_fields[1]) <= float(frame_fields[1]) + 0.01,
		"the slowest frame is the one the frame line calls worst (%s vs %s)"
		% [slow_fields[1], frame_fields[1]])
	for scope: String in WORLD_SCOPES:
		var line := _scope_line(text, scope)
		check(not line.is_empty(), "the readout times %s" % scope)
		if line.is_empty():
			continue
		# name, ms/frame, self, calls/frame, share
		var fields := line.strip_edges().split(" ", false)
		check(fields.size() == 5 and fields[4].ends_with("%")
				and float(fields[1]) >= float(fields[2]) and float(fields[2]) >= 0.0
				and float(fields[3]) > 0.0,
			"%s reads total >= self >= 0, a call count and a share (%s)" % [scope, line])

	# Over the campaign menu: the menu owns Escape and the pointer, not F12.
	_press(KEY_ESCAPE)
	await process_frame
	await process_frame
	check(game.menu != null and game.menu.is_open(), "Escape opens the campaign menu")
	_press(KEY_F12)
	await process_frame
	check(not overlay.is_open(), "F12 closes the overlay with the menu up")
	check(not Perf.enabled, "a closed overlay switches the profiler off")
	check(game.menu != null and game.menu.is_open(), "and the menu stays where it was")
	_press(KEY_F12)
	await process_frame
	check(overlay.is_open(), "F12 opens it again over the menu")
	overlay.set_open(false)
	if game.menu != null and game.menu.is_open():
		game.menu.close()


## The scope row for `name`, at any depth: rows are the name indented by its
## depth and then the numbers.
func _scope_line(text: String, name: String) -> String:
	for line in text.split("\n"):
		if line.strip_edges().begins_with(name + " "):
			return line
	return ""


func _line_starting(text: String, prefix: String) -> String:
	for line in text.split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


## One real key press and release through the input pipeline, so the binding is
## proved and not just the method behind it.
func _press(keycode: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = down
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("PERF_OVERLAY_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
