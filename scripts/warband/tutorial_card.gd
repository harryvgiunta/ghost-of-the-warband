class_name TutorialCard
extends CanvasLayer
## The tutorial's step card: the biggest thing on the screen, and the only modal
## in the warband mode. It opens on a new beat, holds the game still underneath
## while it is up, and closes on one obvious button (or G / Enter / Escape), so a
## player can read the controls without a fight happening behind them.
##
## The card owns the pause: `open()` remembers whether the tree was paused and
## `close()` restores it. Its whole subtree runs with `PROCESS_MODE_ALWAYS`, or a
## paused tree would freeze the very button that resumes it.

signal closed

const PANEL_SIZE := Vector2(760, 440)
const TITLE_SIZE := 34
const BODY_SIZE := 20
const KEY_SIZE := 24
const KICKER_SIZE := 14
const DIM := Color(0.02, 0.03, 0.05, 0.72)
const GOLD := Color(0.98, 0.78, 0.44)
const CREAM := Color(0.94, 0.92, 0.86)
const MUTED := Color(0.72, 0.74, 0.75)

var _built := false
var _open := false
var _step := ""
var _shown: Dictionary = {}
var _kicker: Label
var _title: Label
var _body: Label
var _keys: Label
var _footnote: Label
var _button: Button
var _previous_pause := false
var _previous_mouse := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 8
	visible = false

## One card per step id. The scene calls this on every beat; `false` means this
## beat was already read (or the card is mid-read) and nothing was opened.
func show_step(step: String, kicker: String, title: String, body: String,
		keys: String, footnote: String = "") -> bool:
	if _shown.has(step):
		return false
	_shown[step] = true
	_ensure_built()
	_step = step
	_kicker.text = kicker
	_title.text = title
	_body.text = body
	_keys.text = keys
	_footnote.text = footnote if not footnote.is_empty() \
		else "The game is paused while this card is open."
	open()
	return true

func open() -> void:
	if not _built:
		_ensure_built()
	if _open:
		return
	_open = true
	visible = true
	_previous_pause = get_tree().paused
	_previous_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _button != null:
		_button.grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = _previous_pause
	Input.mouse_mode = _previous_mouse
	closed.emit(_step)

func is_open() -> bool:
	return _open

func step() -> String:
	return _step

func has_shown(step: String) -> bool:
	return _shown.has(step)

## Forget what was read (a fresh campaign starts the cards again).
func reset() -> void:
	_shown.clear()
	_step = ""
	close()

func _exit_tree() -> void:
	# A scene hand-off must never inherit a paused tree.
	if _open:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_G, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE]:
		close()
		get_viewport().set_input_as_handled()

# --- construction ----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root_control)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Card"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style())
	root_control.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	_kicker = _label(KICKER_SIZE, GOLD)
	column.add_child(_kicker)
	_title = _label(TITLE_SIZE, CREAM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	_body = _label(BODY_SIZE, CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(PANEL_SIZE.x - 64, 0)
	column.add_child(_body)
	_keys = _label(KEY_SIZE, GOLD)
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_keys)
	_footnote = _label(13, MUTED)
	column.add_child(_footnote)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	_button = Button.new()
	_button.name = "Continue"
	_button.text = "CONTINUE   (G)"
	_button.custom_minimum_size = Vector2(300, 60)
	_button.add_theme_font_size_override("font_size", 22)
	_button.add_theme_color_override("font_color", Color(0.08, 0.12, 0.14))
	_button.add_theme_stylebox_override("normal", _button_style(Color(0.96, 0.80, 0.48)))
	_button.add_theme_stylebox_override("hover", _button_style(Color(1.0, 0.88, 0.60)))
	_button.add_theme_stylebox_override("pressed", _button_style(Color(0.84, 0.68, 0.38)))
	_button.pressed.connect(close)
	row.add_child(_button)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.10, 0.97)
	style.border_color = Color(0.42, 0.58, 0.62)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	return style

func _button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	return style
