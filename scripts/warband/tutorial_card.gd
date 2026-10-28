class_name TutorialCard
extends CanvasLayer
## The tutorial's step card: the biggest thing on the screen, and the only modal
## in the warband mode. It opens on a new beat, holds the game still underneath
## while it is up, and closes on one obvious button (or G / Enter / Escape), so a
## player can read the controls without a fight happening behind them.
##
## The card is one LedgerFrame: the chapter name on the clamp, the lesson on the
## vellum, the chapter stamps and the primary plate at the foot. The card owns
## the pause: `open()` remembers whether the tree was paused and `close()`
## restores it. Its whole subtree runs with `PROCESS_MODE_ALWAYS`, or a paused
## tree would freeze the very button that resumes it.

signal closed

const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const LedgerKeycapScript = preload("res://scripts/ui/ledger_keycap.gd")

const PANEL_SIZE := Vector2(880, 580)
const TITLE_SIZE := 44
const BODY_SIZE := 23
const KEY_SIZE := 21
const KICKER_SIZE := 14
const FOOTNOTE_SIZE := 16

const DIM := Color(0.02, 0.015, 0.01, 0.87)
const INK := LedgerThemeScript.INK
const INK_SOFT := LedgerThemeScript.INK_SOFT
const INK_MUTED := LedgerThemeScript.INK_MUTED
const BLOOD := LedgerThemeScript.BLOOD

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
## The stamps at the foot mark how far through the chapter a beat is. The warband
## opening is nine cards long now that the first fight teaches its own three, so
## the rail carries one stamp per card.
const STAMP_COUNT := 9

## The tokens the card draws as a carved key tile. A token with an underscore is
## one key with a two-word name: `WHEEL_UP` prints WHEEL UP on a single tile.
const KEYS := ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "G", "P", "K", "R",
	"TAB", "ESC", "ENTER", "SPACE", "SHIFT", "CTRL", "LMB", "RMB", "MOUSE",
	"WHEEL_UP", "WHEEL_DOWN", "W", "A", "S", "D", "[", "]"]

var _built := false
var _open := false
var _step := ""
var _shown: Dictionary = {}
var _frame
var _kicker: Label
var _title: Label
var _body: Label
var _keys_row: HFlowContainer
var _footnote: Label
var _button: Button
var _stamps: Array[TextureRect] = []
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
	_kicker.text = _kicker_text(kicker)
	_title.text = title
	_body.text = body
	_fill_keys(keys)
	_footnote.text = footnote if not footnote.is_empty() \
		else "The game is paused while this card is open."
	if _frame != null:
		_frame.set_title(_chapter_text(kicker))
		_frame.set_stamp(_step_numeral(step))
	_refresh_stamps()
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
	root_control.theme = LedgerThemeScript.get_theme()
	add_child(root_control)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Card"
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	root_control.add_child(frame)
	_frame = frame

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	frame.body.add_child(column)

	_kicker = _label(KICKER_SIZE, BLOOD)
	column.add_child(_kicker)
	_title = _label(TITLE_SIZE, INK)
	_title.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	_body = _label(BODY_SIZE, INK)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(PANEL_SIZE.x - 128, 0)
	_body.add_theme_constant_override("line_spacing", 10)
	column.add_child(_body)
	_keys_row = HFlowContainer.new()
	_keys_row.add_theme_constant_override("h_separation", 8)
	_keys_row.add_theme_constant_override("v_separation", 6)
	column.add_child(_keys_row)
	_footnote = _label(FOOTNOTE_SIZE, INK_MUTED)
	_footnote.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	column.add_child(_footnote)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	for index in STAMP_COUNT:
		var stamp := TextureRect.new()
		stamp.texture = _stamp_texture(false)
		stamp.custom_minimum_size = Vector2(16, 16)
		stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stamp)
		_stamps.append(stamp)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_button = Button.new()
	_button.name = "Continue"
	_button.text = "CONTINUE"
	_button.theme_type_variation = "PrimaryButton"
	_button.custom_minimum_size = Vector2(300, 56)
	_button.add_theme_font_size_override("font_size", 19)
	_button.pressed.connect(close)
	row.add_child(_button)

func _fill_keys(text: String) -> void:
	for child in _keys_row.get_children():
		_keys_row.remove_child(child)
		child.queue_free()
	for token in text.split(" ", false):
		# A key is written in capitals in the copy, so a lowercase word that happens
		# to spell one ("a", "w", "d") stays prose instead of turning into a tile.
		var clean := token.trim_suffix(",")
		if clean == clean.to_upper() and _is_key(clean):
			_keys_row.add_child(LedgerKeycapScript.new(clean.replace("_", " ")))
			continue
		var word := _label(KEY_SIZE, INK_MUTED if token in ["\u2014", "\u00b7"] else INK_SOFT)
		word.text = token
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if token.to_lower() == "or":
			word.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
		_keys_row.add_child(word)

func _is_key(token: String) -> bool:
	if token != token.to_upper():
		return false
	return KEYS.has(token)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

# --- copy ------------------------------------------------------------------

func _kicker_text(kicker: String) -> String:
	var parts := kicker.split("/", false, 1)
	var step_part := parts[0].strip_edges()
	if parts.size() < 2:
		return step_part.to_upper()
	return "%s  \u00b7  THE LESSON" % step_part.to_upper()

func _chapter_text(kicker: String) -> String:
	var parts := kicker.split("/", false, 1)
	if parts.size() < 2:
		return "The Lesson"
	return parts[1].strip_edges().capitalize()

func _step_numeral(step: String) -> String:
	var index := _step_index(step)
	if index < 0 or index >= ROMAN.size():
		return ""
	return ROMAN[index]

func _step_index(step: String) -> int:
	if not step.begins_with("step_"):
		return -1
	return int(step.trim_prefix("step_"))

func _stamp_texture(lit: bool) -> Texture2D:
	return load(LedgerThemeScript.DIR + ("stamp_lit.png" if lit else "stamp_dim.png"))

func _refresh_stamps() -> void:
	var active := _step_index(_step)
	for index in _stamps.size():
		_stamps[index].texture = _stamp_texture(index <= active)
