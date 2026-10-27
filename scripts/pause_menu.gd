extends CanvasLayer
## The quick menu every gameplay scene opens with Escape: resume, write the
## journey to disk, switch the window between fullscreen and a window, leave the
## session and quit the client. It owns no simulation, so the world (and a
## hosted session) keeps running behind it; it only frees the pointer.

signal resumed
signal exit_requested
signal quit_requested

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")

var resume_button: Button
var save_button: Button
var display_button: Button
var exit_button: Button
var quit_button: Button
var _notice: Label
var _status: Label
var _open := false
var _built := false
var _exit_label := "EXIT TO TITLE"

func _ready() -> void:
	layer = 10
	visible = false
	_build()

## The scene names what leaving this session means: the town, the surface or the
## title menu.
func configure(exit_label: String) -> void:
	_exit_label = exit_label
	_build()
	exit_button.text = _exit_label

func is_open() -> bool:
	return _open

func open(message: String = "") -> void:
	_build()
	_open = true
	visible = true
	_notice.text = message
	_notice.visible = not message.is_empty()
	_status.text = ""
	_refresh_display()
	# The menu is the reason the pointer is free; clicking it must never move
	# the camera or swing a weapon.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	resumed.emit()

func set_status(message: String) -> void:
	if _status != null:
		_status.text = message

func is_fullscreen() -> bool:
	var mode := get_window().mode
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN

func save_journey() -> bool:
	var state := get_node_or_null("/root/PlayerState")
	if state == null or not state.has_method("save_state"):
		set_status("Nothing to save in this scene.")
		return false
	state.save_state()
	set_status("Journey saved  /  %d c  /  %d items" % [int(state.credits),state.inventory.size()])
	return true

func _build() -> void:
	if _built:
		return
	_built = true
	var root := Control.new()
	root.name = "Menu"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = _theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008,0.024,0.03,0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER,true)
	panel.position = Vector2(-230,-270)
	panel.size = Vector2(460,540)
	panel.add_theme_stylebox_override("panel",_style(Color(0.038,0.078,0.096,0.99),Color("3f5b60"),10))
	root.add_child(panel)
	_label(panel,"IRONWOOD",Vector2(26,20),12,GOLD)
	_label(panel,"MENU",Vector2(24,36),32,CREAM)
	_notice = _label(panel,"",Vector2(26,86),13,TEAL)
	_notice.size = Vector2(408,44)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	resume_button = _button(panel,"RESUME",Vector2(26,142),Vector2(408,46))
	resume_button.pressed.connect(close)
	save_button = _button(panel,"SAVE GAME",Vector2(26,198),Vector2(408,46))
	save_button.pressed.connect(save_journey)
	display_button = _button(panel,"DISPLAY",Vector2(26,254),Vector2(408,46))
	display_button.pressed.connect(_toggle_display)
	exit_button = _button(panel,_exit_label,Vector2(26,310),Vector2(408,46))
	exit_button.pressed.connect(func(): exit_requested.emit())
	quit_button = _button(panel,"EXIT GAME",Vector2(26,366),Vector2(408,46))
	quit_button.pressed.connect(_quit)
	var hint := _label(panel,"Esc closes this menu. The world keeps running behind it.",Vector2(26,424),11,MUTED)
	hint.size = Vector2(408,30)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = _label(panel,"",Vector2(26,466),12,TEAL)
	_status.size = Vector2(408,44)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_display()

func _refresh_display() -> void:
	if display_button == null:
		return
	display_button.text = "DISPLAY: FULLSCREEN" if is_fullscreen() else "DISPLAY: WINDOWED"

func _toggle_display() -> void:
	var window := get_window()
	if is_fullscreen():
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN
	_refresh_display()
	# The window is the authority: a platform that refuses the switch (a
	# headless run, a compositor that ignores it) keeps the label honest.
	if is_fullscreen():
		set_status("Fullscreen. Esc still opens this menu.")
	else:
		set_status("Windowed mode. Drag the border to resize.")

func _quit() -> void:
	# The journey is written first: quitting is the one exit with no scene
	# hand-off to save on the way out.
	save_journey()
	quit_requested.emit()
	get_tree().quit()

func _theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI"])
	result.default_font = font
	result.default_font_size = 15
	result.set_color("font_color","Label",CREAM)
	result.set_color("font_color","Button",CREAM)
	result.set_color("font_hover_color","Button",Color.WHITE)
	result.set_color("font_pressed_color","Button",Color("13282f"))
	result.set_stylebox("normal","Button",_style(Color("243a40"),Color("456068"),7))
	result.set_stylebox("hover","Button",_style(Color("34545b"),GOLD,7))
	result.set_stylebox("pressed","Button",_style(GOLD,GOLD,7))
	return result

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	return result

func _label(parent: Node, text: String, at: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	parent.add_child(result)
	return result

func _button(parent: Node, text: String, at: Vector2, size_at: Vector2) -> Button:
	var result := Button.new()
	result.text = text
	result.position = at
	result.size = size_at
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result
