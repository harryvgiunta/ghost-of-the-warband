extends CanvasLayer
## The Hollow's own page: floor I as a surveyor's plan, laid over the running cave
## and never pausing it. `M` below opens it, as `M` above opens the wood's sheet.
##
## The same three rules as the wood's map (`world_map.gd`):
##
## 1. **The geometry is the floor's.** Every room is drawn from `delve_layout.gd`'s
##    own rectangles and every wall from `delve_rock.gd`'s wall runs - the raster
##    the colliders are built from - so the sheet cannot disagree with the rock.
## 2. **The page is a projection and nothing else.** `map_bounds()`, `project()`,
##    `rooms()`, `walls()`, `areas()`, `markers()`, `scale_metres_per_pixel()` and
##    `legend()` are the whole of the data; the board's `_draw()` paints them and
##    decides nothing, so a headless regression can assert the sheet.
## 3. **It never stops the delve.** The pointer comes back for the page and is
##    captured again when it closes, and the dens keep listening underneath.
##
## North is up as on the wood's sheet: the cave's -Z, deeper, is the top of the
## page. The plan shows the shafts (the ways up), Gorehorn's lair, the party and
## whatever hunts it - a sleeping den is not on it, because nobody has seen it yet.

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Rock = preload("res://scripts/warband/delve_rock.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const Perf = preload("res://scripts/perf_probe.gd")

const TITLE := "THE WEEPING HOLLOW  \u00b7  FLOOR I"
const SUBTITLE := "SIX ROPES ROUND GOREHORN'S LAIR  \u00b7  THE DEEP SIDE IS UP"
## The rock the plan keeps round the outermost rooms, in metres.
const MARGIN_METRES := 4.0
const HEADER := 76.0
const FOOTER := 112.0
const SIDE_MARGIN := 28.0
const MIN_PAGE := Vector2(360.0, 360.0)
const SOUL_RADIUS := 3.6
const BODY_RADIUS := 2.6
const HOSTILE_RADIUS := 2.2
const SHAFT_RADIUS := 4.2
const LABEL_SIZE := 11
const AREA_SIZE := 10
const LEGEND_SIZE := 11
const REPAINT_SECONDS := 0.1
const DIM := Color(0.02, 0.015, 0.01, 0.62)
const PAGE_FILL := LedgerThemeScript.BONE
## The rock is the page's darker field; a room is the cut, washed in its area's
## colour so the eleven areas read apart.
const ROCK_FILL := Color(0.66, 0.6, 0.5)
const CUT_FILL := Color(0.9, 0.86, 0.76)
const WASH := {
	"mouth": Color(0.86, 0.78, 0.6), "den": Color(0.82, 0.68, 0.54), "gallery": Color(0.6, 0.72, 0.78),
	"ossuary": Color(0.92, 0.88, 0.78), "garden": Color(0.68, 0.8, 0.62), "mere": Color(0.56, 0.64, 0.78),
	"chapel": Color(0.9, 0.78, 0.6), "rooted": Color(0.72, 0.64, 0.5), "workings": Color(0.8, 0.7, 0.56),
	"lair": Color(0.8, 0.52, 0.46),
}

var _area = null
var _open := false
var _built := false
var _board = null
var _elapsed := 0.0
var _frame_cache: Dictionary = {}
var _frame_size := Vector2.ZERO


## The one Control the sheet is painted on: it asks the map what to paint.
class Board extends Control:
	var map = null

	func _draw() -> void:
		if map != null:
			map.paint(self)


func _ready() -> void:
	layer = 10
	visible = false
	set_process(false)


## Point the page at the delve (`delve_area.gd`); the cave is read from it each
## paint, since it exists only while a party is below.
func configure(delve_area) -> void:
	_area = delve_area


func open() -> void:
	if not _built:
		_build()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	_elapsed = 0.0
	_board.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(false)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func is_open() -> bool:
	return _open


func title() -> String:
	return TITLE


func _process(delta: float) -> void:
	Perf.begin("hud.map")
	_tick_repaint(delta)
	Perf.end()


func _tick_repaint(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REPAINT_SECONDS:
		return
	_elapsed = 0.0
	if _board != null:
		_board.queue_redraw()


# --- what the sheet is drawn from -----------------------------------------------

## The floor plan's extent in the cave's frame (x/z): every room and a margin of
## rock. Fixed by the plan, so the scale never crawls.
func map_bounds() -> Rect2:
	var bounds := Rect2()
	for room in Layout.ROOMS:
		var rect: Rect2 = room["rect"]
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	return bounds.grow(MARGIN_METRES)


## A cave-frame point (x/z) on the page: x across, the cave's -Z (deeper) up.
## Linear and uniform, so `scale_metres_per_pixel()` is one number.
func project(cave_point: Vector2) -> Vector2:
	var bounds := map_bounds()
	var panel := panel_rect()
	var u := (cave_point.x - bounds.position.x) / maxf(bounds.size.x, 0.0001)
	var v := (cave_point.y - bounds.position.y) / maxf(bounds.size.y, 0.0001)
	return Vector2(panel.position.x + u * panel.size.x, panel.position.y + v * panel.size.y)


## Every room as the page draws it: `{id, area, tunnel, rect}` with `rect` in panel
## space, in `Layout.ROOMS` order.
func rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room in Layout.ROOMS:
		var rect: Rect2 = room["rect"]
		var a := project(rect.position)
		var b := project(rect.end)
		out.append({"id": str(room["id"]), "area": str(room["area"]), "tunnel": bool(room.get("tunnel", false)),
			"rect": Rect2(a, b - a)})
	return out


## Every wall, as panel-space segment pairs (`draw_multiline`): the wall runs the
## rock skin is raised on, so a way between rooms is a gap in the ink.
func walls() -> PackedVector2Array:
	var out := PackedVector2Array()
	for index in Layout.ROOMS.size():
		for run in Rock.wall_runs(index):
			var points: PackedVector2Array = run["points"]
			for k in points.size() - 1:
				out.append(project(points[k]))
				out.append(project(points[k + 1]))
	return out


## Each area's name and where the page writes it: the middle of its largest hall.
func areas() -> Array[Dictionary]:
	var best := {}
	for room in Layout.ROOMS:
		if bool(room.get("tunnel", false)):
			continue
		var area := str(room["area"])
		var rect: Rect2 = room["rect"]
		if not best.has(area) or rect.get_area() > (best[area] as Rect2).get_area():
			best[area] = rect
	var out: Array[Dictionary] = []
	for area in Layout.AREAS:
		if best.has(area):
			out.append({"area": str(area), "label": Layout.area_name(str(area)),
				"screen": project((best[area] as Rect2).get_center())})
	return out


## Everything the page marks, in paint order: the ropes (the one the shortest walk
## from the soul reaches flagged `nearest`), the lair, every awake hostile below,
## the party's bodies and the soul with its facing.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cave = _cave()
	var soul = _soul_body()
	var nearest := ""
	if cave != null and soul != null and cave.contains(soul.global_position):
		nearest = str(cave.nearest_rope(soul.global_position).get("id", ""))
	var came_down := str(_area.get("landing")) if _area != null else ""
	for entry in Layout.LANDINGS:
		var rope: Vector3 = entry["rope"]
		var mark := _mark("shaft", "ROPE", Vector2(rope.x, rope.z), 0.0)
		mark["area"] = Layout.area_name(str(entry["area"]))
		mark["id"] = str(entry["id"])
		mark["nearest"] = str(entry["id"]) == nearest
		mark["landed"] = str(entry["id"]) == came_down
		out.append(mark)
	var alive: bool = cave != null and cave.master_alive()
	out.append(_mark("master", "GOREHORN" if alive or cave == null else "GOREHORN, DEAD",
		Vector2(Layout.MASTER_POINT.x, Layout.MASTER_POINT.z), 0.0))
	if cave == null:
		return out
	for guard in _hostiles(cave):
		var local: Vector3 = cave.to_local((guard as Node3D).global_position)
		out.append(_mark("hostile", "", Vector2(local.x, local.z), 0.0))
	for body in _party(cave):
		var local: Vector3 = cave.to_local((body as Node3D).global_position)
		var is_soul: bool = body == soul
		out.append(_mark("soul" if is_soul else "body", "", Vector2(local.x, local.z),
			_yaw_of(body) if is_soul else 0.0))
	return out


## The page's key.
func legend() -> Array[String]:
	return [
		"THE SOUL  \u00b7  the big mark, and the way it faces;  THE PARTY  \u00b7  one mark to a body",
		"A ROPE  \u00b7  a way up, every shaft;  the ringed one is the shortest walk",
		"GOREHORN  \u00b7  the red diamond;  red marks are what has woken and hunts",
	]


## World metres per page pixel: one number, the projection's own.
func scale_metres_per_pixel() -> float:
	var panel := panel_rect()
	if panel.size.x < 1.0:
		return 1.0
	return map_bounds().size.x / panel.size.x


## The plan itself.
func panel_rect() -> Rect2:
	return _frame()["panel"]


## The whole vellum, title and legend included.
func page_rect() -> Rect2:
	return _frame()["page"]


func _mark(kind: String, label: String, cave_point: Vector2, yaw: float) -> Dictionary:
	var raw := project(cave_point)
	var panel := panel_rect()
	var screen := Vector2(clampf(raw.x, panel.position.x + 1.0, panel.end.x - 1.0),
		clampf(raw.y, panel.position.y + 1.0, panel.end.y - 1.0))
	return {"kind": kind, "label": label, "point": cave_point, "screen": screen, "yaw": yaw,
		"pinned": screen.distance_to(raw) > 0.01}


func _cave():
	if _area == null:
		return null
	var cave = _area.get("cave")
	return cave if cave != null and is_instance_valid(cave) else null


func _host():
	return _area.get("host") if _area != null else null


func _bodies() -> Array:
	var host = _host()
	var source = host.get("bodies") if host != null else null
	var out: Array = []
	if source is Array:
		for body in source:
			if body != null and is_instance_valid(body) and body is Node3D:
				out.append(body)
	return out


## The bodies standing in the cave: the party below.
func _party(cave) -> Array:
	var out: Array = []
	for body in _bodies():
		if bool(body.get("alive")) and cave.contains((body as Node3D).global_position):
			out.append(body)
	return out


## The awake hostiles below: only a woken den is on the world's hostile list.
func _hostiles(cave) -> Array:
	var out: Array = []
	var host = _host()
	var guards = host.get("guards") if host != null else null
	if not (guards is Array):
		return out
	for guard in guards:
		if guard == null or not is_instance_valid(guard) or not (guard is Node3D):
			continue
		var alive = guard.get("alive")
		if alive != null and not bool(alive):
			continue
		if cave.contains((guard as Node3D).global_position):
			out.append(guard)
	return out


func _soul_body():
	for body in _bodies():
		var local = body.get("is_local")
		if local != null and bool(local):
			return body
	return null


func _yaw_of(body) -> float:
	var rig = body.get("rig")
	if rig != null and is_instance_valid(rig) and rig is Node3D:
		return (rig as Node3D).global_rotation.y
	return (body as Node3D).global_rotation.y


# --- the sheet's geometry -------------------------------------------------------

func _frame() -> Dictionary:
	var win := _window_size()
	if _frame_cache.is_empty() or _frame_size != win:
		var page_h := clampf(win.y * 0.94, MIN_PAGE.y, maxf(MIN_PAGE.y, win.y - 20.0))
		var bounds := map_bounds()
		var aspect := bounds.size.x / maxf(bounds.size.y, 0.0001)
		var band_h := maxf(60.0, page_h - HEADER - FOOTER)
		var band_w := band_h * aspect
		var room := win.x - 60.0 - SIDE_MARGIN * 2.0
		if band_w > room:
			band_w = maxf(60.0, room)
			band_h = band_w / aspect
			page_h = band_h + HEADER + FOOTER
		var page_w := maxf(MIN_PAGE.x, band_w + SIDE_MARGIN * 2.0)
		var page := Rect2((win.x - page_w) * 0.5, (win.y - page_h) * 0.5, page_w, page_h)
		var panel := Rect2(page.position.x + (page_w - band_w) * 0.5, page.position.y + HEADER, band_w, band_h)
		_frame_size = win
		_frame_cache = {"page": page, "panel": panel}
	return _frame_cache


func _window_size() -> Vector2:
	var view := get_viewport()
	var size := view.get_visible_rect().size if view != null else Vector2.ZERO
	if size.x < 64.0 or size.y < 64.0:
		return Vector2(1280.0, 720.0)
	return size


# --- the paint ------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	_board = Board.new()
	_board.name = "Board"
	_board.map = self
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board)


## The whole sheet, painted from the queries above and nothing else.
func paint(canvas: CanvasItem) -> void:
	var page := page_rect()
	var panel := panel_rect()
	canvas.draw_rect(Rect2(Vector2.ZERO, _window_size()), DIM)
	canvas.draw_rect(page, PAGE_FILL, true)
	canvas.draw_rect(page, LedgerThemeScript.INK, false, 1.6)
	canvas.draw_rect(page.grow(-5.0), Color(0.42, 0.34, 0.22, 0.55), false, 1.0)
	canvas.draw_string(LedgerThemeScript.FONT_DISPLAY, page.position + Vector2(18.0, 42.0), title(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, LedgerThemeScript.INK)
	canvas.draw_string(LedgerThemeScript.FONT_ITALIC, page.position + Vector2(18.0, 62.0), SUBTITLE,
		HORIZONTAL_ALIGNMENT_LEFT, page.size.x - 36.0, 10, LedgerThemeScript.INK_MUTED)
	canvas.draw_rect(panel, ROCK_FILL, true)
	_paint_hatch(canvas, panel)
	for room in rooms():
		var wash: Color = WASH.get(str(room["area"]), CUT_FILL)
		canvas.draw_rect(room["rect"], CUT_FILL.lerp(wash, 0.45), true)
	canvas.draw_multiline(walls(), LedgerThemeScript.INK_SOFT, 1.4, true)
	canvas.draw_rect(panel, Color(0.42, 0.34, 0.22, 0.6), false, 1.0)
	for entry in areas():
		var at: Vector2 = entry["screen"]
		var label := str(entry["label"])
		var width := LedgerThemeScript.FONT_ITALIC.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, AREA_SIZE).x
		canvas.draw_string(LedgerThemeScript.FONT_ITALIC, at + Vector2(-width * 0.5, -10.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, AREA_SIZE, Color(LedgerThemeScript.INK_MUTED, 0.85))
	for marker in markers():
		_paint_marker(canvas, marker)
	_paint_scale(canvas)
	_paint_legend(canvas)


## Diagonal hatching over the rock, the surveyor's way of saying solid.
func _paint_hatch(canvas: CanvasItem, panel: Rect2) -> void:
	var lines := PackedVector2Array()
	var step := 9.0
	var span := panel.size.x + panel.size.y
	var offset := 0.0
	while offset < span:
		var a := Vector2(panel.position.x + offset, panel.position.y)
		var b := Vector2(panel.position.x + offset - panel.size.y, panel.end.y)
		var t0 := clampf((a.x - panel.end.x) / maxf(a.x - b.x, 0.001), 0.0, 1.0)
		var t1 := clampf((a.x - panel.position.x) / maxf(a.x - b.x, 0.001), 0.0, 1.0)
		lines.append(a.lerp(b, t0))
		lines.append(a.lerp(b, t1))
		offset += step
	canvas.draw_multiline(lines, Color(0.48, 0.4, 0.3, 0.35), 1.0)


func _paint_marker(canvas: CanvasItem, marker: Dictionary) -> void:
	var at: Vector2 = marker["screen"]
	match str(marker["kind"]):
		"shaft":
			canvas.draw_circle(at, SHAFT_RADIUS, Color(0.2, 0.3, 0.42))
			canvas.draw_arc(at, SHAFT_RADIUS + 1.6, 0.0, TAU, 18, LedgerThemeScript.INK, 1.2, true)
			if bool(marker.get("nearest", false)):
				canvas.draw_arc(at, SHAFT_RADIUS + 5.5, 0.0, TAU, 24, LedgerThemeScript.TEAL, 2.0, true)
			var label := str(marker["label"])
			if bool(marker.get("landed", false)):
				label += "  \u00b7  CAME DOWN HERE"
			# Written toward the middle of the plan, so it never runs off the page.
			var width := LedgerThemeScript.FONT_BODY.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				LABEL_SIZE).x
			var east := at.x > panel_rect().get_center().x
			var text_at := at + Vector2(-(SHAFT_RADIUS + 8.0) - width if east else SHAFT_RADIUS + 8.0, 4.0)
			canvas.draw_string(LedgerThemeScript.FONT_BODY, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				LABEL_SIZE, LedgerThemeScript.INK_SOFT)
		"master":
			var points := PackedVector2Array([at + Vector2(0.0, -6.0), at + Vector2(5.0, 0.0),
				at + Vector2(0.0, 6.0), at + Vector2(-5.0, 0.0)])
			canvas.draw_colored_polygon(points, LedgerThemeScript.BLOOD)
			canvas.draw_string(LedgerThemeScript.FONT_BODY, at + Vector2(9.0, 4.0), str(marker["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LedgerThemeScript.BLOOD)
		"hostile":
			canvas.draw_circle(at, HOSTILE_RADIUS, LedgerThemeScript.BLOOD)
		"body":
			canvas.draw_circle(at, BODY_RADIUS, LedgerThemeScript.INK_MUTED)
		"soul":
			var yaw := float(marker.get("yaw", 0.0))
			var forward := Vector2(-sin(yaw), -cos(yaw))
			var side := Vector2(-forward.y, forward.x)
			canvas.draw_colored_polygon(PackedVector2Array([at + forward * 10.0, at + side * 2.8, at - side * 2.8]),
				LedgerThemeScript.TEAL)
			canvas.draw_circle(at, SOUL_RADIUS, LedgerThemeScript.TEAL)


func _paint_scale(canvas: CanvasItem) -> void:
	var panel := panel_rect()
	var page := page_rect()
	var scale := scale_metres_per_pixel()
	var metres := 10.0
	for probe in [50.0, 40.0, 30.0, 25.0, 20.0, 10.0]:
		if probe / scale <= 160.0:
			metres = probe
			break
	var pixels := metres / maxf(scale, 0.0001)
	var origin := Vector2(page.position.x + 18.0, panel.end.y + 22.0)
	canvas.draw_line(origin, origin + Vector2(pixels, 0.0), LedgerThemeScript.INK, 2.0)
	for tick in [0.0, pixels]:
		canvas.draw_line(origin + Vector2(tick, -5.0), origin + Vector2(tick, 4.0), LedgerThemeScript.INK, 1.4)
	canvas.draw_string(LedgerThemeScript.FONT_ITALIC, origin + Vector2(pixels + 8.0, 4.0), "%d M" % int(metres),
		HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE, LedgerThemeScript.INK_SOFT)


func _paint_legend(canvas: CanvasItem) -> void:
	var panel := panel_rect()
	var page := page_rect()
	var at := Vector2(page.position.x + 18.0, panel.end.y + 46.0)
	for line in legend():
		canvas.draw_string(LedgerThemeScript.FONT_BODY, at, line, HORIZONTAL_ALIGNMENT_LEFT,
			page.size.x - 36.0, LEGEND_SIZE, LedgerThemeScript.INK_MUTED)
		at.y += 14.0
