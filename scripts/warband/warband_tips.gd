class_name WarbandTips
extends CanvasLayer
## GHOST OF THE WARBAND: the one hint channel, and the whole of the tutorial.
##
## A tip is a key and a command - `G · CUT THE LATCH`, `HOLD RMB · GUARD` - under
## the crosshair, up for a few seconds, then gone. It never pauses the tree, never
## takes the pointer and never opens twice: a beat that re-announces itself cannot
## nag. Nothing in the warband explains itself in a paragraph any more; the game
## is played and the keys are named as they are needed.
##
## The tokens are drawn as the ledger's carved-bone key tiles, so a hint in the
## middle of a fight looks like the same object as the pause menu's controls page.

const LedgerKeycapScript = preload("res://scripts/ui/ledger_keycap.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const LAYER := 7
## How long a tip stays up before it starts to fade, and how long the fade takes.
const HOLD := 6.0
const FADE := 0.7
## A whole line of keys is not a hint, it is a manual: at most four tiles.
const MAX_KEYS := 4
const TEXT_SIZE := 15
const KEY_SIZE := 13
const BOTTOM := 208.0

## The tokens that become a key tile. A token with an underscore is one key with a
## two-word name: `WHEEL_UP` prints WHEEL UP on one tile.
const KEYS := ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "G", "P", "K", "R",
	"T", "O", "M", "C", "Q", "E", "6", "TAB", "ESC", "ENTER", "SPACE", "SHIFT",
	"CTRL", "LMB", "RMB", "MOUSE", "WHEEL_UP", "WHEEL_DOWN", "W", "A", "S", "D",
	"[", "]"]

const BONE := Color("e9e0c9")
const BONE_DIM := Color("cbbfa7")
const PLATE_BG := Color(0.05, 0.04, 0.03, 0.86)
const PLATE_EDGE := Color(0.58, 0.45, 0.25, 0.55)

var _seen: Dictionary = {}
var _plate: PanelContainer
var _row: HBoxContainer
var _keys_box: HBoxContainer
var _label: Label
var _clock := 0.0
var _hold := HOLD
var _tip := ""


func _ready() -> void:
	layer = LAYER
	_build()
	visible = false
	set_process(true)


## Offer a tip once. `keys` is a space-separated token line (`"HOLD G"`,
## `"W A S D"`, `""` for words only) and `text` is one command in capitals.
## Returns false when this id was already offered, or the tip is empty.
func tip(id: String, keys: String, text: String, seconds: float = HOLD) -> bool:
	if id.is_empty() or _seen.has(id):
		return false
	if keys.strip_edges().is_empty() and text.strip_edges().is_empty():
		return false
	_seen[id] = true
	_tip = id
	_paint(keys, text)
	_hold = maxf(1.5, seconds)
	_clock = 0.0
	visible = true
	_plate.modulate.a = 1.0
	return true


func has_shown(id: String) -> bool:
	return _seen.has(id)


func current_tip() -> String:
	return _tip


func current_text() -> String:
	return _label.text if _label != null else ""


## The tiles currently drawn, in reading order, for a regression that must not
## read private nodes.
func current_keys() -> Array[String]:
	var out: Array[String] = []
	if _keys_box == null:
		return out
	for child in _keys_box.get_children():
		var label := child.get_node_or_null("Key") as Label
		if label != null:
			out.append(str(label.text))
	return out


func showing() -> bool:
	return visible and _plate != null and _plate.modulate.a > 0.01


func shown_count() -> int:
	return _seen.size()


## Forget every tip (a fresh campaign starts the opening again).
func reset() -> void:
	_seen.clear()
	_tip = ""
	visible = false
	_clock = 0.0
	if _plate != null:
		_plate.modulate.a = 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	if _clock <= _hold:
		return
	var over := _clock - _hold
	if over >= FADE:
		visible = false
		return
	_plate.modulate.a = 1.0 - over / FADE


func _paint(keys: String, text: String) -> void:
	for child in _keys_box.get_children():
		_keys_box.remove_child(child)
		child.queue_free()
	var shown := 0
	for token in keys.split(" ", false):
		if shown >= MAX_KEYS:
			break
		if _is_key(token):
			_keys_box.add_child(_keycap(token.replace("_", " ")))
			shown += 1
			continue
		var word := _text(token.to_upper(), KEY_SIZE, BONE_DIM)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_keys_box.add_child(word)
	_label.text = text
	_keys_box.visible = _keys_box.get_child_count() > 0


func _is_key(token: String) -> bool:
	return token == token.to_upper() and KEYS.has(token)


func _keycap(text: String) -> Control:
	var cap = LedgerKeycapScript.new(text)
	cap.name = "Key"
	return cap


func _text(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", LedgerThemeScript.FONT_BODY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_plate = PanelContainer.new()
	_plate.name = "Tip"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_plate.offset_bottom = -BOTTOM
	var plate := StyleBoxFlat.new()
	plate.bg_color = PLATE_BG
	plate.border_color = PLATE_EDGE
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(3)
	plate.content_margin_left = 14
	plate.content_margin_right = 14
	plate.content_margin_top = 8
	plate.content_margin_bottom = 8
	_plate.add_theme_stylebox_override("panel", plate)
	root.add_child(_plate)

	_row = HBoxContainer.new()
	_row.name = "Line"
	_row.add_theme_constant_override("separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_row)

	_keys_box = HBoxContainer.new()
	_keys_box.name = "Keys"
	_keys_box.add_theme_constant_override("separation", 5)
	_keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_keys_box)

	_label = _text("", TEXT_SIZE, BONE)
	_label.name = "Text"
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_label)
