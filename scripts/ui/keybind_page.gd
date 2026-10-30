class_name KeybindPage
extends Control
## The CONTROLS sheet: the keyboard itself, drawn from the ledger's bone keycaps.
##
## There is no InputMap - the warband's keys live in the scenes - so this is a
## reference plate and not a rebinding UI. Every key that does something is
## washed in blood, every key that does not is left as dead bone, and a blood
## arrowhead at the end of each leader thread says which action a key serves.
##
## Nothing here is laid out by a container. The board is built once in board
## units (46 px tiles, 6 px seams) and the whole plate is scaled to fit the page
## it is given, so the drawing never depends on a frame delta or on the mouse,
## and a narrow page shrinks the board instead of piling labels on top of keys.
##
## The leaders are drawn under the tiles: a thread that has to pass a key is
## hidden by it and shows again in the seam, so no line is ever scratched across
## a keycap's face.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")
const Keycap = preload("res://scripts/ui/ledger_keycap.gd")

# --- board metrics, board units (page pixels at scale 1) ---------------------
const KEY_W := 46.0
const KEY_H := 46.0
const GAP := 6.0
const PAD := 14.0
const SECTION_GAP := 12.0
const COL_GAP := 18.0
const ROWS := 6

## Row 1 is the widest: twelve one-unit keys and a two-unit backspace.
const PLATE_W := 750.0
const PLATE_H := 334.0
const MOUSE_X := PLATE_W + COL_GAP
const CLUSTER_W := 2.0 * KEY_W + GAP
const GROUP_W := MOUSE_X + CLUSTER_W
const CAPTION_H := 20.0

## The empty bands between the rows: a horizontal thread can run there without
## touching a keycap. The plate's own margins are bands too (TOP_BAND, FOOT_BAND).
const TOP_BAND := 7.0
const BAND_1 := 63.0
const BAND_2 := 115.0
const BAND_3 := 167.0
const BAND_4 := 219.0
const BAND_5 := 271.0
const FOOT_BAND := 327.0
## Below the mouse cluster and still clear of the second row.
const CLUSTER_BAND := 130.0

# --- page metrics ------------------------------------------------------------
const CORRIDOR := 12.0
const LEFT_GUTTER := 132.0
const RIGHT_GUTTER := 96.0
const LABEL_SIZE := 14
const LABEL_H := 18.0
const BOTTOM_GAP := 24.0
const FOOT_GAP := 14.0
const FOOT_H := 16.0
const SLOT_GAP := 12.0
const MIN_SCALE := 0.2

# --- ink --------------------------------------------------------------------
const BOARD_FILL := Color(0.24, 0.18, 0.12, 0.28)
const BOARD_EDGE := Color(0.38, 0.29, 0.19, 0.60)
const LIT_TINT := Color(0.36, 0.09, 0.10, 0.22)
const DEAD := Color(1, 1, 1, 0.55)
const LINE_W := 1.6
const HEAD_LEN := 7.0
const HEAD_W := 6.0
## Two actions on one key (`WHEEL` up and down, `Q`/`E` sidestep) enter the label
## on two threads a few pixels apart instead of one doubled line.
const TWIN_OFFSET := 2.5
const FOOTNOTE := "Esc closes this page.  Keys are fixed."

# --- the action table --------------------------------------------------------
## Warband keys as the scenes implement them. `[label, key, band]`; every key is
## listed on the left or the right of the board, or in the row beneath it.
const LEFT_ACTIONS := [
	["MOVE", "W", BAND_3],
	["SPRINT", "SHIFT", BAND_4],
	["JUMP", "SPACE", FOOT_BAND],
	["CROUCH", "C", BAND_5],
	["WEAPON SET", "TAB", BAND_2],
	["BODIES · F1-F5 · [ ]", "F1", TOP_BAND],
]
## `[label, [keys], band, exit edge of the key]`. The mouse reads as combat on
## the right, next to the tiles it belongs to.
const RIGHT_ACTIONS := [
	["SWING", ["LMB"], TOP_BAND, "top"],
	["GUARD", ["RMB"], 37.0, "right"],
	["STAB", ["WHEEL"], 89.0, "right"],
	["OVERHEAD", ["WHEEL"], CLUSTER_BAND, "bottom"],
	["THROW", ["T"], BAND_4, "right"],
	["SIDESTEP", ["Q", "E"], BAND_3, "right"],
	["SIGIL", ["R"], BAND_5, "right"],
]
## The world row under the board, one label per key.
const BOTTOM_ACTIONS := [
	["USE · LATCH", "G"],
	["TAKE", "K"],
	["GEAR", "P"],
	["WARBAND", "O"],
	["MAP", "M"],
	["MENU", "ESC"],
]

var _group: Control
var _leaders: Control
var _caption: Label
var _foot: Label
var _tiles: Dictionary = {}       # token -> LedgerKeycap, in board order
var _slots: Dictionary = {}       # token -> the rect the board gives it
var _lit: Dictionary = {}         # token -> true
var _specs: Array = []            # one entry per action label, in table order
var _runs: Array = []             # one entry per drawn thread (heads included)
var _origin := Vector2.ZERO
var _scale := 1.0
var _built := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The smallest page the sheet is drawn on: below this the board shrinks to a
	# thumbnail and the key faces stop being legible, so the host gives it room.
	custom_minimum_size = Vector2(560.0, 380.0)
	_build()


func _ready() -> void:
	_build()
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


# --- what the sheet says -----------------------------------------------------

## Every action label on the page, in table order: left gutter, right gutter,
## then the world row beneath the board.
func action_labels() -> Array[String]:
	var out: Array[String] = []
	for spec in _specs:
		out.append(String(spec["label"]))
	return out


## The keys that are washed blood, in board order (rows top to bottom, then the
## mouse cluster).
func lit_keys() -> Array[String]:
	var out: Array[String] = []
	for token in _tiles.keys():
		if _lit.has(token):
			out.append(String(token))
	return out


## How many blood arrowheads the sheet actually draws: one per key of every
## action, so `SIDESTEP` (Q and E) and `STAB`/`OVERHEAD` (one wheel) count twice
## on their shared keys.
func arrow_count() -> int:
	return _runs.size()


## The keyboard plate's size as it stands on the page, after the fit.
func board_size() -> Vector2:
	return Vector2(PLATE_W, PLATE_H) * _scale


## The threads as drawn: one entry per arrowhead, `{label, tip, dir}`, with the
## tip in page coordinates. A head that does not end on its label's edge is a
## legend that points at nothing.
func leaders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run in _runs:
		out.append({
			"label": String(run["label"]),
			"tip": _origin + (run["tip"] as Vector2) * _scale,
			"dir": run["dir"],
		})
	return out


## The rect an action label occupies on the page.
func action_rect(text: String) -> Rect2:
	for spec in _specs:
		if String(spec["label"]) == text:
			var rect: Rect2 = spec["rect"]
			return rect
	return Rect2()


## The tile for a key token (`W`, `F1`, `SPACE`, `SHIFT`, `WHEEL`…), or null.
## Tiles live in board units, so their rects are the same at every page size.
func key_tile(token: String) -> Control:
	if not _tiles.has(token):
		return null
	return _tiles[token] as Control


# --- construction ------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	theme = Ledger.get_theme()

	_collect_lit()

	_group = Control.new()
	_group.name = "Board"
	_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.size = Vector2(GROUP_W, PLATE_H)
	add_child(_group)

	# Under the tiles: the plate first, then the threads, both in the canvas that
	# owns the drawing. A themed `Panel` would take its fill from whatever skin the
	# page is wearing, and this sheet has to read the same in every window.
	# `LeaderCanvas` overrides `_draw()` because a `draw` signal handler can be
	# emitted outside the drawing pass.
	_leaders = LeaderCanvas.new()
	_leaders.name = "Leaders"
	_leaders.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaders.size = Vector2(GROUP_W, PLATE_H)
	_leaders.painter = _draw_leaders
	_group.add_child(_leaders)

	var rows := _rows()
	for r in rows.size():
		var y := PAD + float(r) * (KEY_H + GAP)
		var x := PAD
		for entry in rows[r]:
			var units := float(entry["units"])
			_place(String(entry["token"]), Vector2(x, y), units)
			x += units * (KEY_W + GAP)
			if entry.has("gap_after"):
				x += float(entry["gap_after"])

	_place("LMB", Vector2(MOUSE_X, PAD), 1.0)
	_place("RMB", Vector2(MOUSE_X + KEY_W + GAP, PAD), 1.0)
	_place("WHEEL", Vector2(MOUSE_X, PAD + KEY_H + GAP), 2.0)

	_caption = _label("MOUSE", 10, Ledger.BLOOD)
	_caption.name = "MouseCaption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_caption)

	_build_actions()

	_foot = _label(FOOTNOTE, 12, Ledger.INK_MUTED)
	_foot.name = "Footnote"
	_foot.add_theme_font_override("font", Ledger.FONT_ITALIC)
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_foot)


## The keyboard, row by row. `units` is a multiple of KEY_W plus the seams a wide
## key swallows, so one nine-slice keycap serves `W` and `SPACE` alike.
func _rows() -> Array:
	var rows: Array = []

	var fn_row: Array = [{"token": "ESC", "units": 1.0, "gap_after": SECTION_GAP}]
	for i in 12:
		fn_row.append({"token": "F%d" % (i + 1), "units": 1.0})
	rows.append(fn_row)

	var digits: Array = []
	for text in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]:
		digits.append({"token": String(text), "units": 1.0})
	digits.append({"token": "BACKSPACE", "units": 2.0})
	rows.append(digits)

	var qwerty: Array = [{"token": "TAB", "units": 1.5}]
	for text in ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"]:
		qwerty.append({"token": String(text), "units": 1.0})
	rows.append(qwerty)

	var home: Array = [{"token": "CAPS", "units": 1.75}]
	for text in ["A", "S", "D", "F", "G", "H", "J", "K", "L"]:
		home.append({"token": String(text), "units": 1.0})
	home.append({"token": "ENTER", "units": 2.0})
	rows.append(home)

	var lower: Array = [{"token": "SHIFT", "units": 2.0}]
	for text in ["Z", "X", "C", "V", "B", "N", "M"]:
		lower.append({"token": String(text), "units": 1.0})
	lower.append({"token": "SHIFT_R", "units": 2.0})
	rows.append(lower)

	rows.append([
		{"token": "CTRL", "units": 1.5},
		{"token": "ALT", "units": 1.25},
		{"token": "SPACE", "units": 6.0},
		{"token": "ALT_R", "units": 1.25},
		{"token": "CTRL_R", "units": 1.5},
	])
	return rows


## One key: the carved cap, its blood wash when it is bound, the dead grey of a
## key that does nothing.
func _place(token: String, at: Vector2, units: float) -> void:
	var width := units * KEY_W + (units - 1.0) * GAP
	var cap: Control = Keycap.new(_text_of(token))
	cap.name = "Key_%s" % token
	cap.position = at
	# In the tree before the size is asked for: a keycap's minimum width is its
	# own carved size until its face is fitted, and a Control may not be sized
	# under its current minimum.
	_group.add_child(cap)
	_fit(cap, width)
	cap.custom_minimum_size = Vector2(width, KEY_H)
	cap.size = Vector2(width, KEY_H)
	if _lit.has(token):
		var wash := ColorRect.new()
		wash.name = "Lit"
		wash.color = LIT_TINT
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cap.add_child(wash)
	else:
		cap.modulate = DEAD
	_tiles[token] = cap
	_slots[token] = Vector2(width, KEY_H)


## A long word on a short key (`BACKSPACE`) shrinks its own face rather than
## widening the tile and breaking the row's alignment.
func _fit(cap: Control, width: float) -> void:
	var face: Label = null
	for child in cap.get_children():
		if child is Label:
			face = child
			break
	if face == null:
		return
	# The tile is the size the board says it is, never the size its word wants:
	# a keycap's label clips instead of pushing its neighbour off the row.
	face.clip_text = true
	face.custom_minimum_size = Vector2(0, 0)
	face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var size := LABEL_SIZE
	var room := width - 24.0
	while size > 11 and Ledger.FONT_BODY.get_string_size(
			face.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	face.add_theme_font_size_override("font_size", size)


func _text_of(token: String) -> String:
	if token.ends_with("_R"):
		return token.substr(0, token.length() - 2)
	return token


## Keys that are listed by one label but bound as a family (`WASD` movement,
## `F1`..`F5` bodies, `[` and `]` cycling) are washed with the key the label
## points at.
const LIT_FAMILY := ["A", "S", "D", "F2", "F3", "F4", "F5", "[", "]"]


func _collect_lit() -> void:
	for token in LIT_FAMILY:
		_lit[String(token)] = true
	for entry in LEFT_ACTIONS:
		_lit[String(entry[1])] = true
	for entry in RIGHT_ACTIONS:
		for key in entry[1]:
			_lit[String(key)] = true
	for entry in BOTTOM_ACTIONS:
		_lit[String(entry[1])] = true


func _build_actions() -> void:
	for entry in LEFT_ACTIONS:
		_specs.append(_spec(String(entry[0]), [String(entry[1])], "left",
			float(entry[2]), "left"))
	for entry in RIGHT_ACTIONS:
		var keys: Array = []
		for key in entry[1]:
			keys.append(String(key))
		_specs.append(_spec(String(entry[0]), keys, "right",
			float(entry[2]), String(entry[3])))
	for entry in BOTTOM_ACTIONS:
		_specs.append(_spec(String(entry[0]), [String(entry[1])], "bottom",
			0.0, "bottom"))


func _spec(text: String, keys: Array, place: String, band: float,
		exit_side: String) -> Dictionary:
	var node := _label(text, LABEL_SIZE, Ledger.INK_SOFT)
	node.name = "Action%d" % _specs.size()
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if place == "left":
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	elif place == "right":
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(node)
	return {
		"label": text,
		"keys": keys,
		"place": place,
		"band": band,
		"exit": exit_side,
		"node": node,
		"rect": Rect2(),
	}


func _label(text: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_override("font", Ledger.FONT_BODY)
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


# --- layout ------------------------------------------------------------------

## The whole sheet, from the page's size and constants: the board is scaled to
## fit between the gutters, the labels are hung off the board's bands, and the
## threads are rebuilt from the two. Called on every resize, never on a delta.
func _layout() -> void:
	if not _built:
		return
	var page := size
	if page.x < 64.0 or page.y < 64.0:
		return
	var band := BOTTOM_GAP + LABEL_H + FOOT_GAP + FOOT_H
	var avail_w := page.x - LEFT_GUTTER - RIGHT_GUTTER - CORRIDOR * 2.0
	var avail_h := page.y - band
	_scale = maxf(MIN_SCALE, minf(1.0, minf(avail_w / GROUP_W,
		avail_h / (PLATE_H + CAPTION_H))))
	var content_h := (PLATE_H + CAPTION_H) * _scale + band
	var top := maxf(0.0, (page.y - content_h) * 0.5)
	_origin = Vector2(LEFT_GUTTER + CORRIDOR, top + CAPTION_H * _scale)
	_group.position = _origin
	_group.scale = Vector2(_scale, _scale)

	for token in _slots.keys():
		var cap: Control = _tiles[token]
		cap.size = _slots[token]
	_place_caption()
	_place_sides()
	_place_bottom()
	_foot.position = Vector2(0.0, top + content_h - FOOT_H)
	_foot.size = Vector2(page.x, FOOT_H)
	_build_runs()
	_leaders.queue_redraw()


func _place_caption() -> void:
	_caption.size = Vector2(CLUSTER_W * _scale, FOOT_H)
	_caption.position = Vector2(
		_origin.x + (MOUSE_X + CLUSTER_W * 0.5) * _scale - CLUSTER_W * _scale * 0.5,
		_origin.y - FOOT_H)


## The two side gutters: labels hung on the band their thread runs along, so a
## label can never sit on top of another one's line.
func _place_sides() -> void:
	var left_edge := LEFT_GUTTER
	var right_edge := _origin.x + GROUP_W * _scale + CORRIDOR
	for spec in _specs:
		var place := String(spec["place"])
		if place == "bottom":
			continue
		var node: Label = spec["node"]
		var width := _width(String(spec["label"]))
		var y := _origin.y + float(spec["band"]) * _scale - LABEL_H * 0.5
		node.size = Vector2(width, LABEL_H)
		if place == "left":
			node.position = Vector2(left_edge - width, y)
		else:
			node.position = Vector2(right_edge, y)
		spec["rect"] = Rect2(node.position, node.size)


## The world row: one label per key, centred under the key where it fits and
## pushed along the row where it would not.
func _place_bottom() -> void:
	var items: Array = []
	for spec in _specs:
		if String(spec["place"]) != "bottom":
			continue
		var cap: Control = _tiles[String(spec["keys"][0])]
		items.append({
			"spec": spec,
			"want": _origin.x + (cap.position.x + cap.size.x * 0.5) * _scale,
			"w": _width(String(spec["label"])),
			"left": 0.0,
		})
	items.sort_custom(func(a, b): return float(a["want"]) < float(b["want"]))
	var cursor := _origin.x
	for item in items:
		var left := maxf(float(item["want"]) - float(item["w"]) * 0.5, cursor)
		item["left"] = left
		cursor = left + float(item["w"]) + SLOT_GAP
	var limit := _origin.x + PLATE_W * _scale
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		var left := minf(float(item["left"]), limit - float(item["w"]))
		item["left"] = left
		limit = left - SLOT_GAP
	var y := _origin.y + PLATE_H * _scale + BOTTOM_GAP
	for item in items:
		var spec: Dictionary = item["spec"]
		var node: Label = spec["node"]
		var width := float(item["w"])
		node.size = Vector2(width, LABEL_H)
		node.position = Vector2(float(item["left"]), y)
		spec["rect"] = Rect2(node.position, node.size)


func _width(text: String) -> float:
	return Ledger.FONT_BODY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, LABEL_SIZE).x + 2.0


# --- leaders -----------------------------------------------------------------

## One thread per action key: out of the key's edge, along a seam, then into the
## label's edge under a blood head. Two keys on one label (`Q`/`E`, the wheel's
## two directions) enter a few pixels apart so both heads stay visible.
func _build_runs() -> void:
	_runs.clear()
	for spec in _specs:
		var keys: Array = spec["keys"]
		var place := String(spec["place"])
		var band := float(spec["band"])
		var middle := (keys.size() - 1) * 0.5
		for i in keys.size():
			var token := String(keys[i])
			if place == "bottom":
				_runs.append(_bottom_run(spec, token))
			else:
				var tip_y := band + (float(i) - middle) * TWIN_OFFSET * 2.0
				_runs.append(_side_run(spec, token, tip_y))


func _side_run(spec: Dictionary, token: String, tip_y: float) -> Dictionary:
	var cap: Control = _tiles[token]
	var exit := String(spec["exit"])
	var half := cap.size * 0.5
	var start := Vector2(cap.position.x + half.x, cap.position.y + cap.size.y)
	match exit:
		"left":
			start = Vector2(cap.position.x, cap.position.y + half.y)
		"right":
			start = Vector2(cap.position.x + cap.size.x, cap.position.y + half.y)
		"top":
			start = Vector2(cap.position.x + half.x, cap.position.y)
	var left := String(spec["place"]) == "left"
	var edge := (-CORRIDOR / _scale) if left else (GROUP_W + CORRIDOR / _scale)
	var tip := Vector2(edge, tip_y)
	var points := PackedVector2Array([start])
	if absf(start.y - tip_y) > 0.5:
		points.append(Vector2(start.x, tip_y))
	points.append(tip)
	return {
		"points": points,
		"tip": tip,
		"dir": Vector2(-1.0, 0.0) if left else Vector2(1.0, 0.0),
		"label": spec["label"],
	}


## Down the key's own column - behind every cap it passes, visible in the seams -
## then along the shelf under the board and into the label's head.
func _bottom_run(spec: Dictionary, token: String) -> Dictionary:
	var cap: Control = _tiles[token]
	var start := Vector2(cap.position.x + cap.size.x * 0.5,
		cap.position.y + cap.size.y)
	var rect: Rect2 = spec["rect"]
	var centre := (rect.position.x + rect.size.x * 0.5 - _origin.x) / _scale
	var shelf := (rect.position.y - HEAD_LEN - 2.0 - _origin.y) / _scale
	var tip_y := (rect.position.y - _origin.y) / _scale
	var tip := Vector2(centre, tip_y)
	var points := PackedVector2Array([start])
	if absf(start.x - centre) > 0.5:
		points.append(Vector2(start.x, shelf))
	points.append(Vector2(centre, shelf))
	points.append(tip)
	return {
		"points": points,
		"tip": tip,
		"dir": Vector2(0.0, 1.0),
		"label": spec["label"],
	}


## The threads, drawn by the canvas that owns them.
func _draw_leaders(canvas: CanvasItem) -> void:
	# The plate: a washed parchment board with one hairline edge, inset by PAD so
	# the key grid sits inside it.
	var plate := Rect2(Vector2(2.0, 2.0), Vector2(PLATE_W - 4.0, PLATE_H - 4.0))
	canvas.draw_rect(plate, BOARD_FILL, true)
	canvas.draw_rect(plate, BOARD_EDGE, false, 1.0)
	for run in _runs:
		var points: PackedVector2Array = run["points"]
		if points.size() < 2:
			continue
		canvas.draw_polyline(points, Ledger.INK_MUTED, LINE_W, true)
		_head(canvas, run["tip"], run["dir"])


func _head(canvas: CanvasItem, tip: Vector2, dir: Vector2) -> void:
	var axis: Vector2 = dir.normalized()
	var side := Vector2(-axis.y, axis.x)
	var base := tip - axis * HEAD_LEN
	canvas.draw_colored_polygon(PackedVector2Array([
		tip,
		base + side * (HEAD_W * 0.5),
		base - side * (HEAD_W * 0.5),
	]), Ledger.BLOOD)


## The thread layer. `_draw()` is the one place a CanvasItem may draw, so the
## board's leaders are painted from here and never from a `draw` signal handler.
class LeaderCanvas extends Control:
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)
