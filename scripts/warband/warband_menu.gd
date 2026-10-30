class_name WarbandMenu
extends Control
## The warband's own quick menu: resume, write the campaign to disk, resume a
## written one, settings and the two ways out.
##
## It is a plain Control, not a CanvasLayer, because the campaign world hangs it
## under its own overlay and the tests build it without a scene. Like every
## ledger window it pauses nothing: the warband keeps standing, a hosted session
## keeps running, and the menu only owns the pointer while it is up. The world
## does the pausing of input; this file never touches `get_tree().paused`.
##
## One LedgerFrame, one column of rows, and settings one page in: the sound page
## is the shared `SoundSettingsPage`, the same one the campaign's Escape window
## and the frontier's quick menu show, plus the windowed/fullscreen row that
## reads the window's real mode instead of remembering what it asked for.

signal resumed
signal load_requested
signal exit_requested
signal quit_requested
signal saved(path: String)

const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const SoundPageScript = preload("res://scripts/ui/sound_settings_page.gd")
const KeybindPageScript = preload("res://scripts/ui/keybind_page.gd")

## The index page and the two sub-pages it opens: the mix, and the controls sheet.
const PAGE_MENU := "menu"
const PAGE_SOUND := "sound"
const PAGE_KEYS := "keys"

const PANEL_SIZE := Vector2(460, 760)
## The controls sheet is a whole keyboard wide: the frame itself grows for it.
const KEYS_PANEL_SIZE := Vector2(1140, 760)
const DIM := Color(0.02, 0.015, 0.01, 0.82)

var resume_button: Button
var save_button: Button
var load_button: Button
var settings_button: Button
## The controls sheet's row, on the settings page beside the mix.
var keys_button: Button
var exit_button: Button
var quit_button: Button
## The windowed/fullscreen row on the settings page.
var display_button: Button
var back_button: Button
## The shared mixer page; it owns every level and mute, this menu owns none.
var sound_page
## The controls sheet, the same board the frontier's quick menu shows.
var keys_page

var _frame
var _menu_layer: VBoxContainer
var _sound_layer: VBoxContainer
var _keys_layer: VBoxContainer
var _notice: Label
var _status: Label
var _page := PAGE_MENU
var _open := false
var _built := false
var _exit_label := "LEAVE THE CAMPAIGN"
## What the pointer was doing before the menu took it, so closing can hand the
## scene back exactly what it had (usually a captured pointer).
var _prior_mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A menu must stay usable even if a host ever pauses the tree for it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 60
	_build()
	# The build may have happened before the node had a window (a test builds it
	# first); repaint the mode row now that there is one to ask.
	refresh()
	visible = _open


## The world names what leaving this campaign means: the trail, the town, the
## title. Safe before or after the node enters the tree.
func configure(exit_label: String) -> void:
	_exit_label = exit_label if not exit_label.is_empty() else "LEAVE THE CAMPAIGN"
	_build()
	exit_button.text = _exit_label


func is_open() -> bool:
	return _open


## Which page is showing: `"menu"`, `"sound"` or `"keys"`.
func page() -> String:
	return _page


## The six rows, by their contract key. A caller (a scene, a test, a hint) reads
## these instead of walking the tree, so renaming a node cannot break it.
func action_buttons() -> Dictionary:
	_build()
	return {
		"resume": resume_button,
		"save": save_button,
		"load": load_button,
		"settings": settings_button,
		"exit": exit_button,
		"quit": quit_button,
	}


## `context` may carry `page` (start on a page), `notice` (a line at the head,
## e.g. why the menu opened itself) and `status` (a line at the foot).
func open(context: Dictionary = {}) -> void:
	_build()
	if not _open:
		# Remembered only on the closed -> open edge: re-opening while already
		# up must not record the visible mode this menu just forced.
		_prior_mouse_mode = Input.mouse_mode
	_open = true
	visible = true
	var start_page := str(context.get("page", PAGE_MENU))
	show_page(start_page if not start_page.is_empty() else PAGE_MENU)
	_notice.text = str(context.get("notice", ""))
	_notice.visible = not _notice.text.is_empty()
	set_status(str(context.get("status", "")))
	refresh()
	_free_pointer()
	_note("open", {"page": _page, "exit_label": _exit_label})


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var closing_page := _page
	# The next open is the index again: a window that remembered a sub-page
	# would greet the player with sliders when they asked for the ledger.
	show_page(PAGE_MENU)
	_restore_pointer()
	resumed.emit()
	_note("close", {"page": closing_page})


## Escape walks back one page; a sub-page answers its own key instead of the
## menu closing twice. Returns true when it consumed the press.
func back() -> bool:
	if not _open:
		return false
	if _page != PAGE_MENU:
		show_page(PAGE_MENU)
		return true
	return false


# --- pages -----------------------------------------------------------------

## Unknown pages fall back to the index, so a typo can never hide the menu.
func show_page(name: String) -> void:
	_build()
	if name != PAGE_SOUND and name != PAGE_KEYS:
		name = PAGE_MENU
	_page = name
	_menu_layer.visible = name == PAGE_MENU
	_sound_layer.visible = name == PAGE_SOUND
	_keys_layer.visible = name == PAGE_KEYS
	match name:
		PAGE_SOUND:
			_frame.configure("Sound", "gear")
			_set_panel_size(PANEL_SIZE)
		PAGE_KEYS:
			_frame.configure("Keys", "cage")
			_set_panel_size(KEYS_PANEL_SIZE)
		_:
			_frame.configure("Warband", "banner")
			_set_panel_size(PANEL_SIZE)
	if name == PAGE_SOUND and sound_page != null and is_inside_tree():
		sound_page.refresh()


## The frame is centred, so its four offsets are all a page size needs.
func _set_panel_size(panel: Vector2) -> void:
	_frame.offset_left = -panel.x * 0.5
	_frame.offset_right = panel.x * 0.5
	_frame.offset_top = -panel.y * 0.5
	_frame.offset_bottom = panel.y * 0.5


## Repaint the rows that mirror real state: whether a save exists, and the mode
## the window is actually in.
func refresh() -> void:
	if not _built:
		return
	_refresh_load()
	_refresh_display()
	if _page == PAGE_SOUND and sound_page != null and is_inside_tree():
		sound_page.refresh()


func status_text() -> String:
	return _status.text if _status != null else ""


func set_status(message: String) -> void:
	if _status != null:
		_status.text = message


# --- moves -----------------------------------------------------------------

## Write the warband exactly as `Warband.save_state()` writes it. The menu adds
## no arithmetic: the status line and the `saved` signal report the real file.
func save_game() -> bool:
	var warband := _warband()
	if warband == null or not warband.has_method("save_state"):
		set_status("No warband to write in this scene.")
		_note("save_skipped")
		return false
	# A co-op guest is playing the host's warband: there is no file of its own to
	# write, and the host's ledger is the host's to keep.
	if bool(warband.get("lent")):
		set_status("This is the host's campaign: the host keeps its ledger.")
		_note("save_skipped", {"lent": true})
		return false
	var path := _save_path()
	if path.is_empty():
		set_status("No warband file is configured.")
		_note("save_skipped")
		return false
	warband.save_state()
	if not FileAccess.file_exists(path):
		set_status("The ledger could not be written.")
		_note("save_failed", {"path": path})
		return false
	var roster := _roster_count(warband)
	set_status("Warband written  /  %s  /  %d in the roster" % [path.get_file(), roster])
	_note("save", {"path": path, "roster": roster})
	saved.emit(path)
	_refresh_load()
	return true


func is_fullscreen() -> bool:
	if not is_inside_tree():
		return false
	var window := get_window()
	if window == null:
		return false
	return window.mode == Window.MODE_FULLSCREEN \
		or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN


# --- build -----------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	var root := Control.new()
	root.name = "MenuRoot"
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

	_frame = LedgerFrameScript.new()
	_frame.name = "Frame"
	_frame.configure("Warband", "banner")
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.offset_left = -PANEL_SIZE.x * 0.5
	_frame.offset_right = PANEL_SIZE.x * 0.5
	_frame.offset_top = -PANEL_SIZE.y * 0.5
	_frame.offset_bottom = PANEL_SIZE.y * 0.5
	root.add_child(_frame)

	_menu_layer = _column(_frame.body, "Menu")
	var column := _menu_layer

	var kicker := _label("GHOST OF THE WARBAND", 10, LedgerThemeScript.INK_MUTED)
	column.add_child(kicker)
	var title := _label("THE WARBAND", 30, LedgerThemeScript.INK)
	title.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	column.add_child(title)

	_notice = _label("", 12, LedgerThemeScript.BLOOD)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size = Vector2(0, 32)
	_notice.visible = false
	column.add_child(_notice)

	resume_button = _button("RESUME", "PrimaryButton", 52)
	resume_button.pressed.connect(close)
	column.add_child(resume_button)
	_section(column, "THE CAMPAIGN")

	save_button = _button("SAVE GAME", "", 46)
	save_button.pressed.connect(save_game)
	column.add_child(save_button)
	load_button = _button("LOAD GAME", "", 46)
	load_button.pressed.connect(_on_load_pressed)
	column.add_child(load_button)
	settings_button = _button("SETTINGS", "", 46)
	settings_button.pressed.connect(show_page.bind(PAGE_SOUND))
	column.add_child(settings_button)
	keys_button = _button("KEYS", "", 46)
	keys_button.pressed.connect(show_page.bind(PAGE_KEYS))
	column.add_child(keys_button)
	_section(column, "LEAVE")

	exit_button = _button(_exit_label, "DangerButton", 46)
	exit_button.pressed.connect(_on_exit_pressed)
	column.add_child(exit_button)
	quit_button = _button("QUIT GAME", "DangerButton", 46)
	quit_button.pressed.connect(_on_quit_pressed)
	column.add_child(quit_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var hint := _label("The warband keeps standing while this page is open.",
		12, LedgerThemeScript.INK_MUTED)
	hint.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_status = _label("", 12, LedgerThemeScript.TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 32)
	column.add_child(_status)

	_sound_layer = _column(_frame.body, "Settings")
	_sound_layer.visible = false
	_section(_sound_layer, "SETTINGS")
	sound_page = SoundPageScript.new()
	sound_page.name = "SoundPage"
	_sound_layer.add_child(sound_page)

	var sound_spacer := Control.new()
	sound_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sound_layer.add_child(sound_spacer)

	display_button = _button("", "", 46)
	display_button.pressed.connect(_toggle_display)
	_sound_layer.add_child(display_button)
	back_button = _button("BACK", "", 46)
	back_button.pressed.connect(show_page.bind(PAGE_MENU))
	_sound_layer.add_child(back_button)

	_keys_layer = _column(_frame.body, "Keys")
	_keys_layer.visible = false
	_section(_keys_layer, "CONTROLS")
	keys_page = KeybindPageScript.new()
	keys_page.name = "KeybindPage"
	keys_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_keys_layer.add_child(keys_page)
	var keys_back := _button("BACK", "", 46)
	keys_back.name = "KeysBack"
	keys_back.pressed.connect(show_page.bind(PAGE_MENU))
	_keys_layer.add_child(keys_back)

	_refresh_display()
	_refresh_load()


func _column(parent: Control, node_name: String) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.name = node_name
	result.add_theme_constant_override("separation", 6)
	parent.add_child(result)
	return result


func _refresh_load() -> void:
	if load_button == null:
		return
	var path := _save_path()
	var warband := _warband()
	var lent := warband != null and bool(warband.get("lent"))
	var has_save := not path.is_empty() and FileAccess.file_exists(path)
	load_button.disabled = lent or not has_save
	if lent:
		load_button.tooltip_text = "Only the host can load this campaign."
	else:
		load_button.tooltip_text = "" if has_save else "No written warband to load."


func _refresh_display() -> void:
	if display_button == null:
		return
	# The window is the authority: report the mode it is in, not the one the
	# button last asked for (a headless run or a compositor may refuse).
	display_button.text = "DISPLAY:  FULLSCREEN" if is_fullscreen() else "DISPLAY:  WINDOWED"


func _toggle_display() -> void:
	if not is_inside_tree():
		return
	var window := get_window()
	if window == null:
		return
	if is_fullscreen():
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN
	_refresh_display()
	_note("display", {"mode": window.mode, "fullscreen": is_fullscreen()})
	if is_fullscreen():
		set_status("Fullscreen. The ledger stays one page deep.")
	else:
		set_status("Windowed. Drag the border to resize.")


func _on_load_pressed() -> void:
	if load_button != null and load_button.disabled:
		return
	_note("load_requested", {"path": _save_path()})
	load_requested.emit()


func _on_exit_pressed() -> void:
	_note("exit_requested", {"label": _exit_label})
	exit_requested.emit()


func _on_quit_pressed() -> void:
	_note("quit")
	quit_requested.emit()
	# Deferred: the press finishes unwinding (and the signal reaches the scene)
	# before the tree is torn down, so a listener can still write state.
	call_deferred("_quit_now")


func _quit_now() -> void:
	if is_inside_tree():
		get_tree().quit()


# --- helpers ---------------------------------------------------------------

func _warband() -> Node:
	# A node built but not yet parented has no `/root` to ask; the autoload is
	# only reachable once this menu is inside the tree.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Warband")


func _save_path() -> String:
	var warband := _warband()
	if warband == null:
		return ""
	var value: Variant = warband.get("save_path")
	return "" if value == null else str(value)


func _roster_count(warband: Node) -> int:
	var roster: Variant = warband.get("roster")
	if roster != null and roster.has_method("count"):
		return int(roster.count())
	return 0


func _free_pointer() -> void:
	# Headless runs have no pointer; writing the mode there is noise.
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restore_pointer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = _prior_mouse_mode


func _note(message: String, data: Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("warband_menu", message, data)


func _section(parent: Control, text: String) -> void:
	parent.add_child(_label(text, 10, LedgerThemeScript.BLOOD))


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
