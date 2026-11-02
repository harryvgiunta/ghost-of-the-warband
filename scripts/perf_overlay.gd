extends CanvasLayer
## Autoload `PerfOverlay`: F12 in any scene - the title, the campaign world, a
## standalone area - draws the frame over the game. The headline is fps and the
## average frame time. Under it: the worst frame and the 1% low of the last 240
## frames, the renderer's CPU and GPU time and its counters, the physics step,
## the scene tree and memory, a line from the scene about what it is running,
## and the timings of the game's major functions as the `Perf` scopes
## (`perf_probe.gd`) measured them, as a call tree.
##
## Closed, it costs nothing: its process is off and `Perf.enabled` is false, so
## every instrumented scope returns on its first line. Opening it turns both on
## and measures from that frame; closing turns both off again. It answers F12 in
## `_input`, before any menu or key the scenes own, and never takes the pointer.
##
## The readout is rebuilt four times a second from the frames in between: slow
## enough to read, quick enough to follow a turn of the camera. It lists as many
## scope rows as the window has room for and sums the time of what it left out.

const Perf = preload("res://scripts/perf_probe.gd")
const Ledger = preload("res://scripts/ui/ledger_theme.gd")

## The engine monitors the window averages, in the order `_sample_monitors`
## reads them. One array of floats holds seconds and counts alike.
const M_RENDER_CPU := 0
const M_RENDER_GPU := 1
const M_DRAWS := 2
const M_PRIMS := 3
const M_OBJECTS := 4
const M_PHYSICS := 5
const M_PAIRS := 6
const M_ACTIVE := 7
const M_ISLANDS := 8
const M_NODES := 9
const M_ORPHANS := 10
const M_RESOURCES := 11
const M_MEMORY := 12
const M_VRAM := 13
const MONITORS := 14

## A scene that knows something the engine does not (bodies, mobs, missiles)
## joins this group and answers `perf_context() -> PackedStringArray`.
const CONTEXT_GROUP := &"perf_context"
## Wall time between two rebuilds of the text.
const REFRESH_US := 250000
## Frames the fps, worst-frame and 1%-low figures are taken over.
const WINDOW := 240
## Scope rows listed however small the window: below this the table says too
## little to be worth the screen.
const MIN_ROWS := 8
## Above every layer the game draws (the paperdoll's 25 is the highest).
const LAYER := 100
const MARGIN := 16.0
const PADDING := 12.0
const GAP := 6
const HEADLINE_SIZE := 24
const BODY_SIZE := 14
## The 60 Hz frame with room for vsync jitter (a vsynced 60 fps averages a hair
## over 16.67 ms): an average frame slower than 57 fps turns the headline red.
const BUDGET_MS := 1000.0 / 57.0
## A frame slower than this is counted as a hitch in the headline block.
const SLOW_MS := 40.0
const OVER_BUDGET := Color(0.95, 0.42, 0.34)
## The scope column is two spaces a level of nesting, then the name.
const NAME_WIDTH := 28
const ROW_FORMAT := "%-28s %8s %7s %6s %6s"
const SCOPE_FORMAT := "%-28s %8.3f %7.3f %6.1f %5.1f%%"

var _panel: PanelContainer
var _headline: Label
var _body: Label
## The last `WINDOW` frame times in microseconds, written round-robin.
var _frame_us := PackedInt64Array()
var _next := 0
var _filled := 0
var _since_refresh := 0
## The engine's own monitors, summed over the window. They are read from
## `Performance` once a frame and printed as an average: a single frame's value
## is what the browser shows, and one slow step read as "physics 44 ms" says
## nothing about the frame the eye is complaining about.
var _sum := PackedFloat64Array()
var _samples := 0
## Physics steps seen since the last rebuild, counted on the same frames the
## milliseconds are summed on. Dividing one clock's sum by another clock's count
## is what let "physics 43.94" sit beside a 28 ms frame.
var _steps := 0
var _last_physics_frame := 0


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	# First in the idle phase, so a window's frames run from one idle start to
	# the next and every callback of a frame lands in the same window.
	process_priority = -1000
	_frame_us.resize(WINDOW)
	_build()
	visible = false


func _ready() -> void:
	# The engine switches `_process` on at ready for any script that has one.
	set_process(visible)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F12:
		return
	toggle()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func toggle() -> void:
	set_open(not visible)


func set_open(value: bool) -> void:
	if value == visible:
		return
	visible = value
	set_process(value)
	Perf.enabled = value
	if is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), value)
	if not value:
		return
	Perf.reset()
	_next = 0
	_filled = 0
	_since_refresh = 0
	_sum.resize(MONITORS)
	_sum.fill(0.0)
	_samples = 0
	_steps = 0
	_last_physics_frame = Engine.get_physics_frames()
	_headline.add_theme_color_override("font_color", Ledger.BONE)
	_headline.text = "measuring..."
	_body.text = ""


## What each monitor cost or counted since the last rebuild, added up: the
## column is printed as a mean over the frames of the window, so one slow step
## cannot pass itself off as the cost of every frame.
func _sample_monitors() -> void:
	var rid := get_viewport().get_viewport_rid()
	_sum[M_RENDER_CPU] += RenderingServer.get_frame_setup_time_cpu() \
		+ RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_sum[M_RENDER_GPU] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_sum[M_DRAWS] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_sum[M_PRIMS] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_sum[M_OBJECTS] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	# The monitor reports the frame's whole physics time, so a frame that ran
	# three steps reports three steps' worth - and a frame that ran none repeats
	# the last reading, which must not be summed again.
	var physics_frame := Engine.get_physics_frames()
	var ran := physics_frame - _last_physics_frame
	_last_physics_frame = physics_frame
	if ran > 0:
		_steps += ran
		_sum[M_PHYSICS] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_sum[M_PAIRS] += Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
	_sum[M_ACTIVE] += Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	_sum[M_ISLANDS] += Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)
	_sum[M_NODES] += Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_sum[M_ORPHANS] += Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_sum[M_RESOURCES] += Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	_sum[M_MEMORY] += Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_sum[M_VRAM] += Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_samples += 1


func _mean(index: int) -> float:
	return _sum[index] / float(maxi(_samples, 1))


## The readout as drawn, headline first. What the regression reads.
func text() -> String:
	return "%s\n%s" % [_headline.text, _body.text]


func _process(_delta: float) -> void:
	var spent := Perf.tick()
	if spent <= 0:
		return
	_frame_us[_next] = spent
	_next = (_next + 1) % WINDOW
	_filled = mini(_filled + 1, WINDOW)
	_sample_monitors()
	_since_refresh += spent
	if _since_refresh < REFRESH_US:
		return
	_since_refresh = 0
	_compose()
	Perf.restart()


func _compose() -> void:
	var samples := _frame_us.slice(0, _filled)
	samples.sort()
	var sum := 0
	for value in samples:
		sum += value
	var average := float(sum) / float(samples.size()) / 1000.0
	var worst := float(samples[samples.size() - 1]) / 1000.0
	var low := float(samples[mini(samples.size() - 1, int(float(samples.size()) * 0.99))]) / 1000.0
	_headline.text = "%5.1f fps   %6.2f ms" % [_fps(average), average]
	_headline.add_theme_color_override("font_color",
		OVER_BUDGET if average > BUDGET_MS else Ledger.BONE)

	var window_frames := maxi(Perf.frames, 1)
	var lines := PackedStringArray()
	lines.append("frame    %6.2f worst   %6.2f 1%% low (%5.1f fps)   %s" % [
		worst, low, _fps(low), _pacing()])
	lines.append("render   %5.2f cpu %5.2f gpu   %d draws   %.2f M prims   %d objects" % [
		_mean(M_RENDER_CPU), _mean(M_RENDER_GPU), int(_mean(M_DRAWS)),
		_mean(M_PRIMS) / 1000000.0, int(_mean(M_OBJECTS))])
	# Physics is printed per step, not per frame: the frame only decides how many
	# steps it has to pay for, and a step that is itself slow is a different bug.
	var steps := maxi(_steps, 1)
	lines.append("physics  %5.2f /step x%3.1f  %d active   %d pairs   %d islands" % [
		_sum[M_PHYSICS] / float(steps), float(_steps) / float(maxi(_samples, 1)),
		int(_mean(M_ACTIVE)), int(_mean(M_PAIRS)), int(_mean(M_ISLANDS))])
	lines.append("tree     %d nodes   %d orphans   %d resources   %d MB   vram %d MB" % [
		int(_mean(M_NODES)), int(_mean(M_ORPHANS)), int(_mean(M_RESOURCES)),
		int(_mean(M_MEMORY)), int(_mean(M_VRAM))])
	# The frame that hurt, and what was running inside it: the one reading an
	# average cannot give, and the only one that explains a 1% low.
	if Perf.worst_frame_us > 0:
		var inside := PackedStringArray()
		for row in Perf.worst_rows(4):
			inside.append("%s %.2f" % [str(row["name"]), float(row["us"]) / 1000.0])
		lines.append("slowest  %6.2f ms  %d frames ago  %s" % [
			float(Perf.worst_frame_us) / 1000.0, Perf.worst_frames_ago,
			"  ·  ".join(inside)])
	# How often the frame is over twice the 60 Hz budget: the shape of the drop,
	# which a mean and a 1% low between them cannot describe.
	var slow := 0
	for index in _filled:
		if float(_frame_us[index]) / 1000.0 > SLOW_MS:
			slow += 1
	lines.append("hitches  %d of %d frames over %d ms" % [slow, maxi(_filled, 1),
		int(SLOW_MS)])
	for node in get_tree().get_nodes_in_group(CONTEXT_GROUP):
		if node.has_method("perf_context"):
			lines.append_array(node.call("perf_context"))
	lines.append("")
	lines.append(ROW_FORMAT % ["scope", "ms/frame", "self", "calls", "share"])

	# Window sums in microseconds, to milliseconds per drawn frame.
	var per_frame := 1.0 / float(window_frames) / 1000.0
	var frame_us := float(maxi(Perf.frame_us, 1))
	var rows := Perf.rows()
	# What is left under the rows: the "more" line, the totals, a warning.
	var listed := mini(rows.size(), _rows_that_fit(lines.size() + 3))
	for index in listed:
		var row: Dictionary = rows[index]
		var label := "  ".repeat(int(row["depth"])) + str(row["name"])
		lines.append(SCOPE_FORMAT % [
			label.left(NAME_WIDTH),
			float(row["total_us"]) * per_frame,
			float(row["own_us"]) * per_frame,
			float(row["calls"]) / float(window_frames),
			100.0 * float(row["total_us"]) / frame_us])
	if rows.is_empty():
		lines.append("  (no scope ran in this window)")
	elif rows.size() > listed:
		# A hidden child is already inside its listed parent; a hidden root is not.
		var unlisted := 0
		for index in range(listed, rows.size()):
			if int(rows[index]["depth"]) == 0:
				unlisted += int(rows[index]["total_us"])
		lines.append("  ... %d more scopes, %.3f ms/frame at the top level" % [
			rows.size() - listed, float(unlisted) * per_frame])
	lines.append("scoped %.2f of %.2f ms/frame   %.0f pairs/frame" % [
		float(Perf.scoped_us()) * per_frame, frame_us * per_frame,
		float(Perf.pairs()) / float(window_frames)])
	if Perf.imbalanced > 0:
		lines.append("WARNING %d frames closed with a scope open: a begin lost its end" % Perf.imbalanced)
	_body.text = "\n".join(lines)


## Scope rows that fit in the visible window under `fixed` other lines of the
## readout, so a small window lists fewer rows instead of running off the screen.
func _rows_that_fit(fixed: int) -> int:
	var line := _body.get_theme_font("font").get_height(BODY_SIZE) \
		+ float(_body.get_theme_constant("line_spacing"))
	var room := get_viewport().get_visible_rect().size.y - MARGIN * 2.0 - PADDING * 2.0 \
		- _headline.get_minimum_size().y - float(GAP)
	return maxi(MIN_ROWS, int(room / line) - fixed)


## How the frame is paced, which is what an fps figure is read against: a
## vsynced 60 Hz display never shows more than 60.
func _pacing() -> String:
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	var pacing := "vsync on" if vsync else "vsync off"
	if Engine.max_fps > 0:
		pacing += "  cap %d" % Engine.max_fps
	return pacing


func _fps(milliseconds: float) -> float:
	return 1000.0 / maxf(milliseconds, 0.001)


func _build() -> void:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono",
		"Courier New", "monospace"])
	_panel = PanelContainer.new()
	_panel.name = "PerfPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.045, 0.035, 0.86)
	style.border_color = Color(0.58, 0.45, 0.25, 0.9)
	style.set_border_width_all(1)
	style.set_content_margin_all(PADDING)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", GAP)
	_panel.add_child(column)
	_headline = Label.new()
	_headline.name = "Headline"
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline.add_theme_font_override("font", mono)
	_headline.add_theme_font_size_override("font_size", HEADLINE_SIZE)
	_headline.add_theme_color_override("font_color", Ledger.BONE)
	column.add_child(_headline)
	_body = Label.new()
	_body.name = "Readout"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_override("font", mono)
	_body.add_theme_font_size_override("font_size", BODY_SIZE)
	_body.add_theme_color_override("font_color", Ledger.BONE_DIM)
	column.add_child(_body)
