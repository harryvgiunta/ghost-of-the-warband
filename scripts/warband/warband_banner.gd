extends CanvasLayer
## The strip `GameFlow` keeps on screen for a whole co-op session: the role, the
## endpoint, how many souls are on the field, and the last refusal verbatim.
##
## A guest's refusal never reaches the world HUD: the controller only publishes
## refusals it decided itself, and a guest's request is refused by the host over
## the wire, so without this strip the second player would be pressing a key that
## silently does nothing. It lives under the flow, which outlives every scene.

const LAYER := 40
const HOLD_SECONDS := 8.0
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")

## The role line as last painted ("WARBAND · HOSTING UDP 7790 · 2 souls").
var state_text := ""
## The last refusal in the router's own words. Kept after the line fades so a
## player who looked away can still read what happened.
var reason := ""

var _panel: Panel
var _state_label: Label
var _reason_label: Label
var _hold := 0.0

func _ready() -> void:
	layer = LAYER
	_build()
	set_process(true)

func show_state(text: String, warn: bool = false) -> void:
	state_text = text
	if _state_label != null:
		_state_label.text = text
		_state_label.add_theme_color_override("font_color", WARN if warn else TEAL)
	_refresh_visibility()

func note_refusal(text: String) -> void:
	reason = text
	_hold = HOLD_SECONDS
	if _reason_label != null:
		_reason_label.text = ("Refused: " + text) if not text.is_empty() else ""
	_refresh_visibility()

## The two lines a player can read right now.
func reason_line() -> String:
	if _reason_label == null or not _reason_label.visible:
		return ""
	return _reason_label.text

func _process(delta: float) -> void:
	if _hold <= 0.0:
		return
	_hold -= delta
	if _hold <= 0.0 and _reason_label != null:
		_reason_label.text = ""
		_refresh_visibility()

func _refresh_visibility() -> void:
	if _panel == null:
		return
	var has_reason := _reason_label != null and not _reason_label.text.is_empty()
	_panel.visible = not state_text.is_empty() or has_reason
	if _reason_label != null:
		_reason_label.visible = has_reason

func _build() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP, true)
	_panel.position = Vector2(-300, 10)
	_panel.size = Vector2(600, 62)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.07, 0.085, 0.86)
	style.border_color = Color("3f5b60")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])
	_state_label = Label.new()
	_state_label.position = Vector2(18, 8)
	_state_label.size = Vector2(564, 22)
	_state_label.add_theme_font_size_override("font_size", 16)
	_state_label.add_theme_color_override("font_color", TEAL)
	_state_label.add_theme_font_override("font", font)
	_panel.add_child(_state_label)
	_reason_label = Label.new()
	_reason_label.position = Vector2(18, 32)
	_reason_label.size = Vector2(564, 24)
	_reason_label.add_theme_font_size_override("font_size", 13)
	_reason_label.add_theme_color_override("font_color", WARN)
	_reason_label.add_theme_font_override("font", font)
	_reason_label.visible = false
	_panel.add_child(_reason_label)
