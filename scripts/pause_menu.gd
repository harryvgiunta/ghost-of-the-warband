extends CanvasLayer
## The quick menu every gameplay scene opens with Escape: resume, write the
## journey to disk, switch the window between fullscreen and a window, leave the
## session and quit the client. It owns no simulation, so the world (and a
## hosted session) keeps running behind it; it only frees the pointer.
##
## The menu is one LedgerFrame like every other screen: the plates are the shared
## rack, the sections are rubricated in blood ink, and the last written save is
## set at the foot of the page.

signal resumed
signal exit_requested
signal quit_requested

const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const PANEL_SIZE := Vector2(460, 600)
const INK := LedgerThemeScript.INK
const INK_MUTED := LedgerThemeScript.INK_MUTED
const BLOOD := LedgerThemeScript.BLOOD
const TEAL := LedgerThemeScript.TEAL
const DIM := Color(0.02, 0.015, 0.01, 0.82)

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
	_note("open", {"notice": message, "exit_label": _exit_label})
	# The menu is the reason the pointer is free; clicking it must never move
	# the camera or swing a weapon.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if resume_button != null:
		resume_button.grab_focus()

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
		_note("save_skipped")
		set_status("Nothing to save in this scene.")
		return false
	state.save_state()
	_note("save", {"credits": int(state.credits), "inventory": state.inventory.size()})
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
	root.theme = LedgerThemeScript.get_theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("Menu", "gear")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	root.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.body.add_child(column)

	var kicker := _label("IRONWOOD", 11, INK_MUTED)
	column.add_child(kicker)
	var title := _label("QUICK MENU", 32, INK)
	title.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	column.add_child(title)

	_notice = _label("", 12, BLOOD)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size = Vector2(0, 34)
	_notice.visible = false
	column.add_child(_notice)

	resume_button = _button("RESUME", "PrimaryButton", 54)
	resume_button.pressed.connect(close)
	column.add_child(resume_button)
	_section(column, "JOURNEY")

	save_button = _button("SAVE JOURNEY", "", 48)
	save_button.pressed.connect(save_journey)
	column.add_child(save_button)
	display_button = _button("DISPLAY", "", 48)
	display_button.pressed.connect(_toggle_display)
	column.add_child(display_button)
	_section(column, "LEAVE")

	exit_button = _button(_exit_label, "DangerButton", 48)
	exit_button.pressed.connect(func():
		_note("exit_requested", {"label": _exit_label})
		exit_requested.emit())
	column.add_child(exit_button)
	quit_button = _button("EXIT GAME", "DangerButton", 48)
	quit_button.pressed.connect(_quit)
	column.add_child(quit_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var hint := _label("Esc closes this menu. The world keeps running behind it.",
		12, INK_MUTED)
	hint.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_status = _label("", 12, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 30)
	column.add_child(_status)
	_refresh_display()

func _refresh_display() -> void:
	if display_button == null:
		return
	display_button.text = "DISPLAY:  FULLSCREEN" if is_fullscreen() else "DISPLAY:  WINDOWED"

func _toggle_display() -> void:
	var window := get_window()
	if is_fullscreen():
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN
	_refresh_display()
	_note("display", {"mode": window.mode, "fullscreen": is_fullscreen(), "headless": DisplayServer.get_name() == "headless"})
	# The window is the authority: a platform that refuses the switch (a
	# headless run, a compositor that ignores it) keeps the label honest.
	if is_fullscreen():
		set_status("Fullscreen. Esc still opens this menu.")
	else:
		set_status("Windowed mode. Drag the border to resize.")

func _quit() -> void:
	# The journey is written first: quitting is the one exit with no scene
	# hand-off to save on the way out.
	_note("quit")
	save_journey()
	quit_requested.emit()
	get_tree().quit()

func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("menu", message, data)

func _section(parent: Control, text: String) -> void:
	var label := _label(text, 10, BLOOD)
	parent.add_child(label)

func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func _button(text: String, variation: String, height: int) -> Button:
	var result := Button.new()
	result.text = text
	if not variation.is_empty():
		result.theme_type_variation = variation
	result.custom_minimum_size = Vector2(0, height)
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", 15)
	return result
