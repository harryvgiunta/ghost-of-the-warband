class_name WorldMap
extends CanvasLayer
## The wood's own page: one map of the whole campaign, laid over the running world
## and never pausing it.
##
## The campaign had no map at all - no compass, no minimap, no way of telling how
## much road was left except by walking it - and the road is 1,375 m long now. So
## the map is drawn as a road-map sheet: the lane as one continuous line from the
## camp's ring at the bottom of the page to the town's walled square at the top,
## north up, at one honest scale.
##
## Three rules hold it together.
##
## 1. **The geometry is the world's.** The road is sampled from the same polyline
##    the torches, the trunks and the colliders are laid out from
##    (`host.trail.forest["path"]`), and the town stands where `host.town` stands.
##    Nothing here keeps a second idea of where the trail runs, so a moved lane
##    moves the map with it.
## 2. **The page is a projection and nothing else.** `map_bounds()`, `project()`,
##    `road()`, `markers()`, `scale_metres_per_pixel()` and `legend()` are the whole
##    of the data; the `Control._draw()` paints them and decides nothing. That is
##    what lets a headless regression assert the map instead of looking at it - and
##    what keeps the sheet and the test from drifting apart.
## 3. **It never stops the wood.** The map is an overlay on a running tree: the
##    pointer comes back for the page and is captured again when it closes, exactly
##    as the town's panels do, and the squad, the cult and the clock keep going
##    underneath. Reading the map is a risk, not a pause.

const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const TITLE := "THE WOOD"
const SUBTITLE := "THE CAMP'S RING TO THE TOWN'S WALL  \u00b7  NORTH IS UP"
## The map's own half-width around the lane, in metres: the wood a body can read
## from the road, so the sheet is a road-map of the strip and not of the county.
const MAP_VERGE := 60.0
## The camp pocket's own half-width, in metres. `cage_escape.gd` pads the ground
## flat over its yard; this is that same twenty metres, named here because a stub
## host has no camp to ask and the ring has to have a size.
const CAMP_RADIUS := 20.0
## Where the sheet's furniture sits: a header for the title, a footer for the scale
## and the legend, and the margin each side of the road band that the camp's, the
## town's and the clearings' names are written in.
const HEADER := 76.0
const FOOTER := 132.0
const SIDE_MARGIN := 120.0
const MIN_PAGE := Vector2(320.0, 360.0)
## Symbol sizes, in pixels. A map's marks are signs rather than scale drawings:
## only the road's own line and the distances are drawn to scale.
const SOUL_RADIUS := 3.4
const BODY_RADIUS := 2.4
const HOSTILE_RADIUS := 2.0
const QUEST_RADIUS := 4.6
const CLEARING_RADIUS := 2.6
const LABEL_SIZE := 11
const LEGEND_SIZE := 11
## How often the sheet is repainted while it is open. The world moves under it, so
## the marks move; ten frames a second is enough for that and none at all for a
## page nobody is reading.
const REPAINT_SECONDS := 0.1
## The vellum and the field it is ruled on. The inks, fonts and symbols are the
## ledger's own, so the map reads as one more page of the same campaign.
const DIM := Color(0.02, 0.015, 0.01, 0.62)
const PAGE_FILL := LedgerThemeScript.BONE
const FIELD_FILL := Color(0.82, 0.78, 0.68)

var _host = null
var _open := false
var _built := false
var _board = null
## The world-space lane, sampled once per configure: the ground does not move while
## a body is reading the map.
var _road_points := PackedVector3Array()
var _clearings: Array[Vector3] = []
var _lane_width := 11.0
var _bounds := Rect2()
var _frame_cache: Dictionary = {}
var _frame_size := Vector2.ZERO
var _elapsed := 0.0


## The one Control the sheet is painted on. It exists as a class because a map
## needs a `_draw()` and a `CanvasLayer` has none; it asks the map what to paint
## and holds no state of its own.
class Board extends Control:
	var map = null

	func _draw() -> void:
		if map != null:
			map.paint(self)


func _ready() -> void:
	layer = 10
	visible = false
	set_process(false)


## Point the page at the world it describes. Called once by the scene that owns
## both; the lane and the town are read here and cached, because a map is drawn
## from the ground, not from the frame.
func configure(host) -> void:
	_host = host
	_refresh()
	if _built:
		_board.queue_redraw()


func open() -> void:
	if not _built:
		_build()
	if _road_points.size() < 2:
		_refresh()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	_elapsed = 0.0
	_board.queue_redraw()


func close() -> void:
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
	_elapsed += delta
	if _elapsed < REPAINT_SECONDS:
		return
	_elapsed = 0.0
	if _board != null:
		_board.queue_redraw()


# --- what the sheet is drawn from ------------------------------------------

## The world rectangle the page covers, in XZ. It is the lane's own extent plus
## `MAP_VERGE` either side, the camp's pocket and the town's walls - fixed by the
## ground rather than by whatever bodies happen to be walking, so the scale does
## not crawl while a body reads it.
func map_bounds() -> Rect2:
	if _bounds.size.x > 0.0 and _bounds.size.y > 0.0:
		return _bounds
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in _road_points:
		low = Vector2(minf(low.x, point.x - MAP_VERGE), minf(low.y, point.z - MAP_VERGE))
		high = Vector2(maxf(high.x, point.x + MAP_VERGE), maxf(high.y, point.z + MAP_VERGE))
	for point in [Vector3.ZERO, _town_point()]:
		if point == null:
			continue
		var flat := Vector2((point as Vector3).x, (point as Vector3).z)
		var pad := maxf(MAP_VERGE, CAMP_RADIUS + 8.0)
		low = Vector2(minf(low.x, flat.x - pad), minf(low.y, flat.y - pad))
		high = Vector2(maxf(high.x, flat.x + pad), maxf(high.y, flat.y + pad))
	if low.x > high.x or low.y > high.y or high.x - low.x < 2.0 or high.y - low.y < 2.0:
		return Rect2(-MAP_VERGE, -MAP_VERGE, MAP_VERGE * 2.0, MAP_VERGE * 2.0)
	_bounds = Rect2(low, high - low)
	return _bounds


## A world point on the page: x across, and the wood's own -Z (north, the town)
## up. Linear and uniform in both axes, so `scale_metres_per_pixel()` is one
## number and a straight road on the ground is a straight road here.
func project(world_point: Vector3) -> Vector2:
	var bounds := map_bounds()
	var panel := panel_rect()
	var u := (world_point.x - bounds.position.x) / maxf(bounds.size.x, 0.0001)
	var v := (world_point.z - bounds.position.y) / maxf(bounds.size.y, 0.0001)
	return Vector2(panel.position.x + u * panel.size.x, panel.position.y + v * panel.size.y)


## The lane as the page draws it: the sampled road, already in panel space.
func road() -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in _road_points:
		out.append(project(point))
	return out


## Everything the page marks, in the order it paints them, with the point each
## mark lands on. A mark whose world position is outside the page - a wolf pack
## holding the deep wood, a contract taken far off the lane - is pinned to the
## sheet's edge and flagged, so the sheet never claims a mark is somewhere it is
## not drawn.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _host == null:
		return out
	out.append(_mark("camp", "THE CAMP", Vector3.ZERO, 0.0, CAMP_RADIUS))
	var town = _town_point()
	if town != null:
		out.append(_mark("town", "THE TOWN", town, 0.0, _town_radius()))
	var index := 0
	for point in _clearings:
		index += 1
		out.append(_mark("clearing", "CLEARING %d" % index, point, 0.0))
	for entry in _host_markers():
		var position = entry.get("position")
		if not (position is Vector3):
			continue
		var mark := _mark("quest", str(entry.get("label", "A CONTRACT")), position, 0.0)
		mark["note"] = str(entry.get("kind", ""))
		out.append(mark)
	for guard in _hostiles():
		out.append(_mark("hostile", "", (guard as Node3D).global_position, 0.0))
	var soul = _soul_body()
	for body in _warband():
		var is_soul: bool = body == soul
		out.append(_mark("soul" if is_soul else "body", "", (body as Node3D).global_position,
			_yaw_of(body) if is_soul else 0.0))
	return out


## The page's own key: what each mark on the sheet means.
func legend() -> Array[String]:
	return [
		"THE SOUL  \u00b7  the big mark, and the way it faces",
		"THE WARBAND  \u00b7  one mark to a body",
		"THE CULT  \u00b7  red; the wolves hold the deep wood",
		"A CONTRACT  \u00b7  the ringed mark on the road",
		"THE CAMP  \u00b7  a ring;  THE TOWN  \u00b7  a walled square",
	]


## How many world metres one pixel of the road band covers. One number: the page
## is projected uniformly, so the road's distances and its line agree.
func scale_metres_per_pixel() -> float:
	var panel := panel_rect()
	if panel.size.x < 1.0:
		return 1.0
	return map_bounds().size.x / panel.size.x


## The road band of the page: the map proper, with the vellum and the labels
## around it. Its aspect is the world's, which is why the page is a tall sheet.
func panel_rect() -> Rect2:
	return _frame()["panel"]


## The whole vellum, title and legend included.
func page_rect() -> Rect2:
	return _frame()["page"]


# --- the sheet's geometry -------------------------------------------------

func _frame() -> Dictionary:
	var win := _window_size()
	if _frame_cache.is_empty() or _frame_size != win:
		_make_frame(win)
	return _frame_cache


func _make_frame(win: Vector2) -> Dictionary:
	var page_h := clampf(win.y * 0.92, MIN_PAGE.y, maxf(MIN_PAGE.y, win.y - 24.0))
	var page_w := clampf(win.x * 0.34, MIN_PAGE.x, maxf(MIN_PAGE.x, win.x - 60.0))
	var bounds := map_bounds()
	var aspect := maxf(bounds.size.x / maxf(bounds.size.y, 0.0001), 0.02)
	var band_h := maxf(40.0, page_h - HEADER - FOOTER)
	var band_w := band_h * aspect
	var room := page_w - SIDE_MARGIN * 2.0
	if band_w > room:
		band_w = maxf(24.0, room)
		band_h = band_w / aspect
	var page := Rect2((win.x - page_w) * 0.5, (win.y - page_h) * 0.5, page_w, page_h)
	var panel := Rect2(page.position.x + (page_w - band_w) * 0.5, page.position.y + HEADER,
		band_w, band_h)
	_frame_size = win
	_frame_cache = {"page": page, "panel": panel}
	return _frame_cache


func _window_size() -> Vector2:
	var view := get_viewport()
	var size := view.get_visible_rect().size if view != null else Vector2.ZERO
	if size.x < 64.0 or size.y < 64.0:
		return Vector2(1280.0, 720.0)
	return size


## Read the world once: the lane, its clearings, its width and the town. Anything
## missing - a stub host in a regression, a preview with no lane - is simply not
## on the page.
func _refresh() -> void:
	_bounds = Rect2()
	_road_points = _sample_road()
	_lane_width = float(_forest().get("width", 11.0))
	_clearings = []
	for point in _forest().get("clearings", []) as Array:
		if point is Vector3:
			_clearings.append(point)
	_frame_cache = {}
	_frame()


func _sample_road() -> PackedVector3Array:
	var out := PackedVector3Array()
	var path = _trail_path()
	if path != null and float(path.total) > 0.0:
		var steps := 240
		for index in steps + 1:
			var frame: Dictionary = path.sample(float(path.total) * float(index) / float(steps))
			out.append(frame["position"])
		return out
	# No lane to read: a straight road between the camp and wherever the host says
	# the road ends, because a page with no road on it is not a map.
	out.append(Vector3.ZERO)
	var end: Vector3 = _lane_end()
	for index in 21:
		out.append(Vector3.ZERO.lerp(end, float(index) / 20.0))
	return out


func _trail_path():
	var trail = _host.get("trail") if _host != null else null
	if trail == null:
		return null
	var forest = trail.get("forest")
	if not (forest is Dictionary):
		return null
	var path = (forest as Dictionary).get("path")
	if path == null or not path.has_method("sample"):
		return null
	return path


func _forest() -> Dictionary:
	var trail = _host.get("trail") if _host != null else null
	if trail == null:
		return {}
	var forest = trail.get("forest")
	return forest if forest is Dictionary else {}


func _lane_end() -> Vector3:
	if _host != null and _host.has_method("lane_end"):
		return _host.lane_end()
	return Vector3.ZERO


func _town_point():
	var town = _host.get("town") if _host != null else null
	if town == null or not (town is Node3D):
		return null
	return (town as Node3D).global_position


func _town_radius() -> float:
	var town = _host.get("town") if _host != null else null
	if town == null:
		return 0.0
	return float(town.WALL_RADIUS)


func _warband() -> Array:
	var out: Array = []
	var source = _host.get("bodies") if _host != null else null
	if not (source is Array):
		return out
	for body in source as Array:
		if body != null and is_instance_valid(body) and body is Node3D:
			out.append(body)
	return out


func _hostiles() -> Array:
	var out: Array = []
	var source = _host.get("guards") if _host != null else null
	if not (source is Array):
		return out
	for guard in source as Array:
		if guard == null or not is_instance_valid(guard) or not (guard is Node3D):
			continue
		var alive = guard.get("alive")
		if alive != null and not bool(alive):
			continue
		out.append(guard)
	return out


func _host_markers() -> Array:
	if _host == null or not _host.has_method("map_markers"):
		return []
	var list = _host.map_markers()
	return list if list is Array else []


## The body the player is inside: the one that answers to this machine's input.
## The sheet draws it heavier than its squadmates and turns a cone the way it
## faces, because "which of these dots am I" is the first question a map answers.
func _soul_body():
	for body in _warband():
		var local = body.get("is_local")
		if local != null and bool(local):
			return body
	return null


func _yaw_of(body) -> float:
	var rig = body.get("rig")
	if rig != null and is_instance_valid(rig) and rig is Node3D:
		return (rig as Node3D).global_rotation.y
	return (body as Node3D).global_rotation.y


## One mark on the sheet: what it is, where it is, where it lands and what it
## covers. `radius` is how many world metres wide the thing the mark stands for is
## - the camp's own pocket, the town's walls - so those two are drawn at their real
## size while the bodies and the cult are drawn as signs.
func _mark(kind: String, label: String, position: Vector3, yaw: float,
		radius: float = 0.0) -> Dictionary:
	var raw := project(position)
	var panel := panel_rect()
	var screen := Vector2(
		clampf(raw.x, panel.position.x + 1.0, panel.end.x - 1.0),
		clampf(raw.y, panel.position.y + 1.0, panel.end.y - 1.0))
	return {
		"kind": kind,
		"label": label,
		"position": position,
		"screen": screen,
		"yaw": yaw,
		"radius": radius,
		"pinned": screen.distance_to(raw) > 0.01,
	}


# --- the paint ------------------------------------------------------------

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


## The whole sheet, painted from the queries above and nothing else. Called by the
## board's `_draw()`; every colour is the ledger's, every mark is a marker, every
## line is a projection.
func paint(canvas: CanvasItem) -> void:
	var page := page_rect()
	var panel := panel_rect()
	canvas.draw_rect(Rect2(Vector2.ZERO, _window_size()), DIM)
	canvas.draw_rect(page, PAGE_FILL, true)
	canvas.draw_rect(page, LedgerThemeScript.INK, false, 1.6)
	canvas.draw_rect(page.grow(-5.0), Color(0.42, 0.34, 0.22, 0.55), false, 1.0)
	canvas.draw_string(LedgerThemeScript.FONT_DISPLAY, page.position + Vector2(18.0, 42.0),
		title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, LedgerThemeScript.INK)
	canvas.draw_string(LedgerThemeScript.FONT_ITALIC, page.position + Vector2(18.0, 62.0),
		SUBTITLE, HORIZONTAL_ALIGNMENT_LEFT, page.size.x - 36.0, 10,
		LedgerThemeScript.INK_MUTED)
	if panel.size.y < 12.0 or panel.size.x < 4.0:
		return
	canvas.draw_rect(panel, FIELD_FILL, true)
	canvas.draw_rect(panel, Color(0.42, 0.34, 0.22, 0.6), false, 1.0)
	_paint_road(canvas)
	for marker in markers():
		_paint_marker(canvas, marker)
	_paint_scale(canvas)
	_paint_legend(canvas)


func _paint_road(canvas: CanvasItem) -> void:
	var line := road()
	if line.size() < 2:
		return
	var width := maxf(2.6, _lane_width / maxf(scale_metres_per_pixel(), 0.0001))
	canvas.draw_polyline(line, Color(0.30, 0.22, 0.13, 0.55), width + 1.6, true)
	canvas.draw_polyline(line, LedgerThemeScript.INK_SOFT, width, true)


func _paint_marker(canvas: CanvasItem, marker: Dictionary) -> void:
	var at: Vector2 = marker["screen"]
	var kind := str(marker["kind"])
	var scale := scale_metres_per_pixel()
	match kind:
		"camp":
			var radius := maxf(6.0, float(marker.get("radius", CAMP_RADIUS))
				/ maxf(scale, 0.0001))
			canvas.draw_arc(at, radius, 0.0, TAU, 40, LedgerThemeScript.TEAL, 1.8, true)
			canvas.draw_circle(at, 1.6, LedgerThemeScript.TEAL)
		"town":
			var half := maxf(4.0, float(marker.get("radius", 0.0)) / maxf(scale, 0.0001))
			var square := Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
			canvas.draw_rect(square, Color(0.62, 0.58, 0.48, 0.85), true)
			canvas.draw_rect(square, LedgerThemeScript.INK, false, 1.6)
		"clearing":
			canvas.draw_arc(at, CLEARING_RADIUS, 0.0, TAU, 14,
				LedgerThemeScript.INK_MUTED, 1.0, true)
		"quest":
			canvas.draw_circle(at, QUEST_RADIUS, LedgerThemeScript.EMBER, false, 1.6, true)
			canvas.draw_circle(at, 1.6, LedgerThemeScript.EMBER)
		"hostile":
			canvas.draw_circle(at, HOSTILE_RADIUS, LedgerThemeScript.BLOOD)
		"body":
			canvas.draw_circle(at, BODY_RADIUS, LedgerThemeScript.INK_MUTED)
		"soul":
			_paint_cone(canvas, at, float(marker.get("yaw", 0.0)))
			canvas.draw_circle(at, SOUL_RADIUS, LedgerThemeScript.TEAL)
	var label := str(marker.get("label", ""))
	if not label.is_empty():
		_paint_label(canvas, at, label, kind)


## The way the soul faces: a small wedge off the dot, the length of a finger,
## turned by the body's own yaw. -Z is the way these rigs look, so the wedge is
## the facing rotated into the page's axes (x right, z down).
func _paint_cone(canvas: CanvasItem, at: Vector2, yaw: float) -> void:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	var tip := at + forward * 9.0
	var points := PackedVector2Array([tip, at + side * 2.6, at - side * 2.6])
	canvas.draw_colored_polygon(points, LedgerThemeScript.TEAL)


## A name in the sheet's own margin, with a tick from the band's edge to the mark,
## so the road stays a road and the words stay words.
func _paint_label(canvas: CanvasItem, at: Vector2, label: String, kind: String) -> void:
	var panel := panel_rect()
	# The camp names itself on the west margin, the town on the east, the clearings
	# and the contracts on the east as well but stepped in, so the road's own line
	# is never written over.
	var west := kind == "camp"
	var edge := panel.position.x if west else panel.end.x
	var tick := -1.0 if west else 1.0
	canvas.draw_line(Vector2(edge, at.y), Vector2(edge + tick * 7.0, at.y),
		Color(0.35, 0.28, 0.18, 0.7), 1.0)
	var text_at := Vector2(edge + tick * 11.0, at.y + 4.0)
	if west:
		var width := LedgerThemeScript.FONT_BODY.get_string_size(label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		text_at.x -= width
	canvas.draw_string(LedgerThemeScript.FONT_BODY, text_at, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LedgerThemeScript.INK_SOFT)


## The scale, in the footer: a bar the length of a round number of metres and the
## number written against it. It is the page's only claim about distance, and it is
## the projection's own claim - the bar is `metres / scale` pixels long.
func _paint_scale(canvas: CanvasItem) -> void:
	var panel := panel_rect()
	var page := page_rect()
	var scale := scale_metres_per_pixel()
	var metres := 50.0
	for probe in [1000.0, 500.0, 300.0, 250.0, 200.0, 100.0, 50.0]:
		if probe / scale <= 150.0:
			metres = probe
			break
	var pixels := metres / maxf(scale, 0.0001)
	var origin := Vector2(page.position.x + 18.0, panel.end.y + 20.0)
	canvas.draw_line(origin, origin + Vector2(pixels, 0.0), LedgerThemeScript.INK, 2.0)
	for tick in [0.0, pixels]:
		canvas.draw_line(origin + Vector2(tick, -5.0), origin + Vector2(tick, 4.0),
			LedgerThemeScript.INK, 1.4)
	canvas.draw_string(LedgerThemeScript.FONT_ITALIC, origin + Vector2(pixels + 8.0, 4.0),
		"%d M" % int(metres), HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE,
		LedgerThemeScript.INK_SOFT)


func _paint_legend(canvas: CanvasItem) -> void:
	var panel := panel_rect()
	var page := page_rect()
	var at := Vector2(page.position.x + 18.0, panel.end.y + 44.0)
	for line in legend():
		canvas.draw_string(LedgerThemeScript.FONT_BODY, at, line,
			HORIZONTAL_ALIGNMENT_LEFT, page.size.x - 36.0, LEGEND_SIZE,
			LedgerThemeScript.INK_MUTED)
		at.y += 14.0
