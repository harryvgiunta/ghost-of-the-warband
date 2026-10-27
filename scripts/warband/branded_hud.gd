class_name BrandedHud
extends CanvasLayer
## The branded sigil tile: what the main hand in the soul's grip can do, and how
## long until it can do it again.
##
## It owns no gameplay state. `BrandedRunner` already knows which sigil is live
## (its payload is the one the altar wrote) and how much cooldown is left, so the
## tile re-reads `brand()`, `cooldown_left()` and the body's stamina every frame
## and paints what it finds. A copy of any of those numbers here would be a
## second opinion about something the runner has to decide anyway, and the two
## would drift; the whole tile is therefore one pure function of the runner.
##
## ## Where it sits
##
## `WarbandHud` owns the top left (body panel, squad list under it), the top
## right (purse and essence) and the centre lines (`Status` at centre-top, the
## hint and the prompt at centre-bottom, both ±310 px around the middle). This
## layer is the bottom right corner: a fixed 330 x 132 tile 20 px in from the
## screen edges, one `CanvasLayer` above the battle readout so the two can never
## draw over one another at any of the sizes the game runs at (1440 x 900 design,
## 1280 x 800 window). On the 1440 canvas the hint reaches x = 1030 and the tile
## starts at x = 1090.
##
## It is hidden outright when the held piece carries no brand: plain steel has no
## sigil, and an empty frame in the corner would advertise a verb the body does
## not have.

const Branded = preload("res://scripts/warband/branded_skills.gd")

## One above `WarbandHud` (6): the sigil tile is a corner widget, never something
## the body panel or the squad rows have to fight for space with.
const LAYER := 7
const TILE_SIZE := Vector2(330.0, 132.0)
const MARGIN := 20.0
## The file's own path, so `attach()` can build one without the script naming
## its own `class_name` (a headless run against a stale global class cache would
## not resolve it).
const SELF_PATH := "res://scripts/warband/branded_hud.gd"

const READY_COLOUR := Color(0.70, 0.92, 0.62)
const COOLDOWN_COLOUR := Color(0.95, 0.78, 0.36)
const TIRED_COLOUR := Color(0.90, 0.48, 0.42)
const FAINT := Color(0.72, 0.68, 0.58)
const GOLD := Color(0.86, 0.72, 0.36)
const BACKDROP := Color(0.06, 0.05, 0.05, 0.78)
const BAR_BACK := Color(0.14, 0.12, 0.11, 0.9)

var _runner = null

var _panel: PanelContainer
var _title: Label
var _cost: Label
var _status: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat
## The identity the static labels were last built for, so a per-frame refresh
## only re-runs `tier_line` when the sigil or its tier actually changed.
var _signature := ""
var _status_text := ""

## Build a tile under `parent` (the scene root) and hand it back. The scene adds
## one line for this and never has to remember the node: it is named
## "BrandedHud", so `$BrandedHud` finds it later.
static func attach(parent: Node) -> Node:
	var script: Script = load(SELF_PATH)
	if script == null:
		push_error("BrandedHud: cannot load %s" % SELF_PATH)
		return null
	var tile: Node = script.new()
	tile.name = "BrandedHud"
	parent.add_child(tile)
	return tile

func _ready() -> void:
	layer = LAYER
	_build()
	set_process(true)

## The warband handle is accepted so a scene wires this tile the way it wires
## every other warband widget, and is deliberately not stored: every fact on the
## tile comes from the runner, whose payload the altar already wrote, and a
## second copy of the warband here would only invite a second opinion about it.
func configure(_warband, runner = null) -> void:
	set_runner(runner)

## The scene re-points the tile at its runner. The node is the same object for
## the whole scene, but a possession change re-binds the payload inside it, so
## this also paints the new sigil on the frame the soul moves.
func set_runner(runner) -> void:
	_runner = runner
	refresh()

## Whether the tile is on screen at all: false for plain steel, for a body
## without a soul in it, and for a dead body.
func is_showing() -> bool:
	return _panel != null and _panel.visible

## The identity line, exactly `BrandedSkills.tier_line()` for the live sigil.
func title_text() -> String:
	return _title.text if _title != null else ""

## "Cost 204 stamina".
func cost_text() -> String:
	return _cost.text if _cost != null else ""

## "READY", the countdown ("3.2 s"), "LOW STAMINA" or "DOWNED".
func status_text() -> String:
	return _status_text

## The cooldown bar's fill: 0 on the press, full again when the sigil is ready.
func cooldown_progress() -> float:
	if _bar == null or _bar.max_value <= 0.0:
		return 0.0
	return _bar.value / _bar.max_value

func _process(_delta: float) -> void:
	refresh()

## Repaint from the runner. Safe to call before the scene has a runner.
func refresh() -> void:
	if _panel == null:
		return
	var live := _read()
	_panel.visible = bool(live["visible"])
	if not _panel.visible:
		_signature = ""
		_status_text = ""
		return
	var signature := "%s|%d|%d" % [str(live["ability"]), int(live["tier"]),
		int(round(float(live["cost"])))]
	if signature != _signature:
		_signature = signature
		_title.text = Branded.tier_line(str(live["ability"]), int(live["tier"]))
		_cost.text = "Cost %d stamina" % int(round(float(live["cost"])))
		_bar.max_value = maxf(0.1, float(live["cooldown"]))
	var left := float(live["left"])
	# The bar fills as the sigil recharges, so a full bar and READY are the same
	# fact rather than two readings of it.
	_bar.value = _bar.max_value if left <= 0.0 else maxf(0.0, float(live["cooldown"]) - left)
	var text := _status_for(live)
	if text != _status_text:
		_status_text = text
		_status.text = text
		var colour := TIRED_COLOUR
		if text == "READY":
			colour = READY_COLOUR
		elif text.ends_with(" s"):
			colour = COOLDOWN_COLOUR
		_status.modulate = colour
		_fill.bg_color = colour

## Everything the tile prints, read once per frame from the runner and its body.
func _read() -> Dictionary:
	var out := {"visible": false, "ability": "", "tier": 0, "cost": 0.0,
		"cooldown": 1.0, "left": 0.0, "stamina": -1.0, "downed": false}
	if _runner == null or not is_instance_valid(_runner):
		return out
	var payload: Dictionary = _runner.brand()
	var ability := str(payload.get("ability", ""))
	if ability.is_empty():
		return out
	var body = _runner.get("actor")
	if body == null or not is_instance_valid(body) or body.get("alive") != true:
		return out
	var tier := int(payload.get("tier", 0))
	out["ability"] = ability
	out["tier"] = tier
	out["cost"] = Branded.scaled(Branded.stamina_cost(ability), tier)
	out["cooldown"] = maxf(0.1, Branded.cooldown(ability))
	out["left"] = maxf(0.0, float(_runner.cooldown_left()))
	var stamina: Variant = body.get("stamina")
	if stamina != null:
		out["stamina"] = float(stamina)
	out["downed"] = bool(body.get("downed"))
	out["visible"] = true
	return out

## The one line that says whether the verb is available and when it will be.
func _status_for(live: Dictionary) -> String:
	if bool(live.get("downed", false)):
		return "DOWNED"
	var left := float(live.get("left", 0.0))
	if left > 0.0:
		return "%.1f s" % left
	var stamina := float(live.get("stamina", -1.0))
	if stamina >= 0.0 and stamina < float(live.get("cost", 0.0)):
		return "LOW STAMINA"
	return "READY"

func _build() -> void:
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	_panel = PanelContainer.new()
	_panel.name = "BrandTile"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the bottom right corner with explicit offsets, so the tile has
	# the same rectangle whatever it happens to be printing.
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -(MARGIN + TILE_SIZE.x)
	_panel.offset_top = -(MARGIN + TILE_SIZE.y)
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	_panel.visible = false
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = BACKDROP
	backdrop.border_color = Color(0.32, 0.24, 0.14)
	backdrop.set_border_width_all(1)
	backdrop.set_corner_radius_all(3)
	backdrop.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", backdrop)
	root_control.add_child(_panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "BRANDED SIGIL"
	heading.add_theme_font_size_override("font_size", 10)
	heading.add_theme_color_override("font_color", GOLD)
	column.add_child(heading)

	_title = Label.new()
	_title.name = "Ability"
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84))
	column.add_child(_title)

	_cost = Label.new()
	_cost.name = "Cost"
	_cost.add_theme_font_size_override("font_size", 11)
	_cost.add_theme_color_override("font_color", FAINT)
	column.add_child(_cost)

	var row := HBoxContainer.new()
	row.name = "StateRow"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_status = Label.new()
	_status.name = "State"
	_status.add_theme_font_size_override("font_size", 14)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	var key := Label.new()
	key.name = "Key"
	key.text = "R"
	key.add_theme_font_size_override("font_size", 12)
	key.add_theme_color_override("font_color", GOLD)
	row.add_child(key)

	_bar = ProgressBar.new()
	_bar.name = "Cooldown"
	_bar.custom_minimum_size = Vector2(TILE_SIZE.x - 20.0, 8.0)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.value = 0.0
	var back := StyleBoxFlat.new()
	back.bg_color = BAR_BACK
	back.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("background", back)
	_fill = StyleBoxFlat.new()
	_fill.bg_color = READY_COLOUR
	_fill.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("fill", _fill)
	column.add_child(_bar)
