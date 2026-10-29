extends Control
## The main menu. Four doors only: begin a new journey, continue the saved one,
## host your own open world, or join one. Everything else happens inside the world.

signal start_requested
signal load_requested
signal host_requested
signal join_requested

const StateScript = preload("res://scripts/player_state.gd")
const SessionScript = preload("res://scripts/session.gd")
const LobbyScript = preload("res://scripts/warband/warband_lobby.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const SettingsScript = preload("res://scripts/ui/settings_menu.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")

var state
var session
var _status: Label
var start_button: Button
var _load_button: Button
var host_world_button: Button
var join_button: Button
## The possession campaign's door: a fresh warband, not a resume.
var warband_button: Button
## The checkpoint door: opens the world where the last autosave stands. Disabled
## until a warband save exists, because there is nothing to resume before one.
var warband_resume_button: Button
var _join_layer: Control
var _lobby_layer: Control
var _lobby_button: Button
## The warband's host/join panel, beside the four doors. It talks to `GameFlow`
## directly: the socket belongs to the flow (the one node that survives the
## hand-off), so the menu only has to remember what was typed.
var lobby
var _name_input: LineEdit
var _join_mode: OptionButton
var _address_input: LineEdit
var _port_input: SpinBox
var _form_error: Label
var _default_name := "Ranger"
var _default_address := "127.0.0.1"
var _default_port := 7777
var crash_notice: Panel
## Escape's own window: the menu has no pause to offer, but the mix still needs
## a door, and Escape is the one every screen in the game uses.
var settings
var _crash_report: Dictionary = {}

func _ready() -> void:
	state = get_node_or_null("/root/PlayerState")
	if state == null:
		state = StateScript.new()
		state.name = "PlayerStateFallback"
		add_child(state)
	session = get_node_or_null("/root/Session")
	if session == null:
		session = SessionScript.new()
		session.name = "SessionFallback"
		add_child(session)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_build_crash_notice()
	_build_settings()
	_refresh_load_button()
	_refresh_warband_resume()
	print("IRONWOOD_MENU_READY")

func _build() -> void:
	theme = LedgerThemeScript.get_theme()

	var backdrop := TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = load("res://assets/ui/title_backdrop.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.012, 0.010, 0.40)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var column := VBoxContainer.new()
	column.name = "Doors"
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -260
	column.offset_right = 260
	column.offset_top = -340
	column.offset_bottom = 340
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var seal := TextureRect.new()
	seal.name = "Seal"
	seal.texture = load(LedgerThemeScript.DIR + "seal.png")
	seal.custom_minimum_size = Vector2(72, 72)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(seal)
	_center_label(column, "G H O S T   O F", 22, Color(0.82, 0.75, 0.64))
	var wordmark := _center_label(column, "THE WARBAND", 74, Color(0.95, 0.90, 0.80))
	wordmark.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	var tagline := _center_label(column, "a soul may wear any living body", 19,
		Color(0.78, 0.70, 0.58))
	tagline.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	var breath := Control.new()
	breath.custom_minimum_size = Vector2(0, 4)
	column.add_child(breath)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(500, 1)
	rule.color = Color(0.58, 0.45, 0.25, 0.55)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)

	start_button = _plate(column, "NEW CAMPAIGN", "PrimaryButton", _start_new_game)
	_load_button = _plate(column, "CONTINUE", "", _load_saved_game)
	host_world_button = _plate(column, "HOST OPEN WORLD", "", _host_open_world)
	join_button = _plate(column, "JOIN GAME", "", _open_join)
	warband_button = _plate(column, "GHOST OF THE WARBAND", "", _enter_warband)
	warband_resume_button = _plate(column, "RESUME WARBAND", "", _resume_warband)
	_lobby_button = _plate(column, "WARBAND LOBBY", "", _toggle_lobby)
	# The lobby is the only door with two destinations, so the door says so
	# before it opens: an arena bout, or campaign co-op entered with a friend.
	_lobby_button.tooltip_text = "Arena battle or campaign co-op: host the warband, or join a friend."

	_status = _center_label(column, "", 12, LedgerThemeScript.TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _center_label(column,
		"WASD Move   ·   LMB Attack / Draw   ·   I Inventory   ·   P Equipment   ·   Esc Menu",
		10, Color(0.66, 0.60, 0.50))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# The warband's host/join panel is a door of its own: hidden until asked for,
	# then it sits over the world like every other ledger window.
	lobby = LobbyScript.new()
	lobby.name = "WarbandLobby"
	_lobby_layer = Control.new()
	_lobby_layer.name = "LobbyLayer"
	_lobby_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_lobby_layer.visible = false
	add_child(_lobby_layer)
	var lobby_dim := ColorRect.new()
	lobby_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_dim.color = Color(0.015, 0.012, 0.010, 0.88)
	lobby_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_lobby_layer.add_child(lobby_dim)
	lobby.position = Vector2(348, 258)
	_lobby_layer.add_child(lobby)
	var close := Button.new()
	close.text = "CLOSE"
	close.position = Vector2(870, 514)
	close.size = Vector2(194, 44)
	close.pressed.connect(_toggle_lobby)
	_lobby_layer.add_child(close)
	_build_join_layer()


func _center_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _plate(parent: Node, text: String, variation: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(500, 50)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 17)
	if not variation.is_empty():
		button.theme_type_variation = variation
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _toggle_lobby() -> void:
	if _lobby_layer == null:
		return
	_lobby_layer.visible = not _lobby_layer.visible
	if _lobby_layer.visible:
		# The panel's mode row is the point of this door, so opening it says
		# what the row chooses rather than leaving two silent options.
		_set_status("Warband lobby: arena battle or campaign co-op - host or join.")


func _enter_warband() -> void:
	# The warband door is a new campaign, not a resume: a fresh warband, the four
	# cages, however the last one ended. Resuming lives behind its own door.
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.start_campaign()


## The checkpoint door. `GameFlow.enter_warband()` is the resume path: it loads
## the save and opens the world on the bookmark the autosave left (the town for a
## file written before checkpoints existed).
func _resume_warband() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		return
	flow.enter_warband()


## Gate the checkpoint door on a real save. A warband may pin its own path (the
## regressions do), so the check reads the node, not the default constant.
func _refresh_warband_resume() -> void:
	if warband_resume_button == null:
		return
	var warband := get_node_or_null("/root/Warband")
	var has_save := warband != null and FileAccess.file_exists(str(warband.save_path))
	warband_resume_button.disabled = not has_save
	warband_resume_button.tooltip_text = "" if has_save else "No warband checkpoint yet."

func _build_join_layer() -> void:
	_join_layer = Control.new()
	_join_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_join_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_join_layer.visible = false
	add_child(_join_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.012,0.03,0.038,0.8)
	_join_layer.add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER,true)
	panel.position = Vector2(-240,-215)
	panel.size = Vector2(480,430)
	panel.add_theme_stylebox_override("panel", LedgerThemeScript.iron_panel())
	_join_layer.add_child(panel)
	_label(panel,"JOIN GAME",Vector2(24,18),26,GOLD)
	var hint := _label(panel,"Choose an arena match, a delve party or the open world. All values are remembered.",Vector2(24,54),11,MUTED)
	hint.size = Vector2(432,32)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(panel,"MODE",Vector2(24,96),10,GOLD)
	_join_mode = OptionButton.new()
	_join_mode.position = Vector2(24,116)
	_join_mode.size = Vector2(200,40)
	_join_mode.add_item("Arena match",0)
	_join_mode.add_item("Delve party",1)
	_join_mode.add_item("Open world",2)
	panel.add_child(_join_mode)
	_label(panel,"YOUR NAME",Vector2(250,96),10,GOLD)
	_name_input = LineEdit.new()
	_name_input.position = Vector2(250,116)
	_name_input.size = Vector2(206,40)
	_name_input.max_length = 16
	panel.add_child(_name_input)
	_label(panel,"HOST ADDRESS",Vector2(24,168),10,GOLD)
	_address_input = LineEdit.new()
	_address_input.position = Vector2(24,188)
	_address_input.size = Vector2(300,40)
	panel.add_child(_address_input)
	_label(panel,"UDP PORT",Vector2(340,168),10,GOLD)
	_port_input = SpinBox.new()
	_port_input.position = Vector2(340,188)
	_port_input.size = Vector2(116,40)
	_port_input.min_value = 1024
	_port_input.max_value = 65535
	panel.add_child(_port_input)
	var confirm := _button(panel,"JOIN",Vector2(24,258),Vector2(214,44))
	confirm.pressed.connect(_confirm_join)
	var cancel := _button(panel,"CANCEL",Vector2(250,258),Vector2(206,44))
	cancel.pressed.connect(_close_join)
	_form_error = _label(panel,"",Vector2(24,318),11,WARN)
	_form_error.size = Vector2(432,54)
	_form_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sync_join_form()


## Fills the form from the cache *now*. Reading it once in `_ready` froze the
## name, address, port and door at whatever the app started with, so a session
## that hosted or joined something else kept offering dead values.
func _sync_join_form() -> void:
	var cached_name := _default_name
	var cached_address := _default_address
	var cached_port := _default_port
	var cached_mode := "arena"
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cached_name = str(cache.player_name)
		cached_address = str(cache.address)
		cached_port = int(cache.port)
		cached_mode = str(cache.mode)
	if _name_input != null:
		_name_input.text = cached_name
	if _address_input != null:
		_address_input.text = cached_address
	if _port_input != null:
		_port_input.value = clampi(cached_port,1024,65535)
	if _join_mode != null:
		_join_mode.selected = 2 if cached_mode == "world" else 1 if cached_mode == "delve" else 0

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	return result

func _label(parent: Node, text: String, position_at: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = position_at
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	parent.add_child(result)
	return result

func _button(parent: Node, text: String, position_at: Vector2, size_at: Vector2) -> Button:
	var result := Button.new()
	result.text = text
	result.position = position_at
	result.size = size_at
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result

## The settings window is built last so it sits over the join form and the lobby
## panel; Escape is the only door to it, exactly as it is in the world.
func _build_settings() -> void:
	settings = SettingsScript.new()
	settings.name = "Settings"
	add_child(settings)


func _open_settings() -> void:
	if settings == null:
		return
	if _join_layer != null and _join_layer.visible:
		_close_join()
	if _lobby_layer != null and _lobby_layer.visible:
		_lobby_layer.visible = false
	settings.open()


## The logger writes a report for the last unclearly-ended session before the
## menu builds. Surface it here so a crashed player can find the file without
## knowing about user://logs; the report is local and never uploaded.
func _build_crash_notice() -> void:
	var log := get_node_or_null("/root/Log")
	if log == null:
		return
	var reports: Array = log.pending_crash_reports()
	if reports.is_empty():
		return
	_crash_report = reports[0]
	crash_notice = Panel.new()
	crash_notice.position = Vector2(872, 626)
	crash_notice.size = Vector2(496, 190)
	crash_notice.add_theme_stylebox_override("panel", LedgerThemeScript.lacquer_panel())
	add_child(crash_notice)
	_label(crash_notice,"PREVIOUS SESSION ENDED UNEXPECTEDLY",Vector2(20,16),14,WARN)
	var detail := _label(crash_notice,"Crash report and session log saved.\nAttach both when reporting the problem.",Vector2(20,44),12,MUTED)
	detail.size = Vector2(456,40)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var file_label := _label(crash_notice,str(_crash_report.get("text_path","")).get_file(),Vector2(20,94),11,TEAL)
	file_label.size = Vector2(456,18)
	file_label.clip_text = true
	var open_folder := _button(crash_notice,"OPEN CRASH REPORTS",Vector2(20,124),Vector2(218,44))
	open_folder.pressed.connect(log.open_crash_folder)
	var open_latest := _button(crash_notice,"OPEN LATEST REPORT",Vector2(250,124),Vector2(226,44))
	open_latest.pressed.connect(func(): log.open_report(0))
	_note("menu_crash_notice", {"session_id": str(_crash_report.get("session_id","")), "reports": reports.size()})


func _refresh_load_button() -> void:
	if _load_button == null or state == null:
		return
	var has_save := FileAccess.file_exists(str(state.save_path))
	_load_button.disabled = not has_save
	_load_button.tooltip_text = "" if has_save else "No saved journey yet."

func _start_new_game() -> void:
	if state == null:
		_set_status("Player state is unavailable.",WARN)
		return
	state.reset(true)
	if session != null:
		session.clear()
	_note("menu_start", {"credits": int(state.credits)})
	_set_status("A new journey begins at the town gate.")
	print("IRONWOOD_NEW_GAME credits=%d" % int(state.credits))
	start_requested.emit()
	get_tree().change_scene_to_file("res://main.tscn")

func _load_saved_game() -> void:
	if state == null:
		_set_status("Player state is unavailable.",WARN)
		return
	if not FileAccess.file_exists(str(state.save_path)):
		_set_status("No saved journey yet. Start a new game.",WARN)
		_refresh_load_button()
		return
	state.load_state()
	if session != null:
		session.clear()
	_note("menu_load", {"credits": int(state.credits), "inventory": state.inventory.size()})
	_set_status("Journey restored.")
	print("IRONWOOD_LOAD_GAME credits=%d inventory=%d" % [int(state.credits),state.inventory.size()])
	load_requested.emit()
	get_tree().change_scene_to_file("res://main.tscn")

func _host_open_world() -> void:
	var cache := get_node_or_null("/root/NetCache")
	var port := _default_port
	var player_name := _default_name
	if cache != null:
		# The host socket uses its own port. The guest-side `port` is what a
		# friend typed last, and letting it open the world is how a host ended up
		# serving a port nobody else knew about.
		port = int(cache.host_port)
		player_name = str(cache.player_name)
	if session != null:
		session.arm_world("world-host","127.0.0.1",port,player_name)
	if cache != null:
		cache.remember_host(player_name,port)
	_note("menu_host", {"port": port, "name": player_name})
	_set_status("Opening your world on UDP %d. Friends use this port." % port)
	print("IRONWOOD_HOST_WORLD port=%d" % port)
	host_requested.emit()
	get_tree().change_scene_to_file("res://main.tscn")

func _open_join() -> void:
	_sync_join_form()
	_join_layer.visible = true
	_form_error.text = ""
	_name_input.grab_focus()
	_name_input.select_all()

func _close_join() -> void:
	_join_layer.visible = false
	_form_error.text = ""

func _confirm_join() -> void:
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_form_error.text = "Enter the host's address."
		return
	var port := int(_port_input.value)
	if port < 1024 or port > 65535:
		_form_error.text = "Choose a UDP port between 1024 and 65535."
		return
	var player_name := _name_input.text.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	if player_name.is_empty():
		player_name = "Ranger"
	var cache := get_node_or_null("/root/NetCache")
	var join_mode := "arena"
	if _join_mode.selected == 1:
		join_mode = "delve"
	elif _join_mode.selected == 2:
		join_mode = "world"
	if cache != null:
		cache.remember(player_name,address,port,join_mode)
	if state != null:
		state.save_state()
	if session != null:
		if join_mode == "world":
			session.arm_world("world-join",address,port,player_name)
		elif join_mode == "delve":
			session.arm_delve("delve-join",address,port,player_name)
		else:
			session.arm_arena("client",address,port,player_name)
	_note("menu_join", {"mode": join_mode, "address": address, "port": port, "name": player_name})
	_set_status("Joining %s:%d..." % [address,port])
	print("IRONWOOD_JOIN mode=%s address=%s port=%d name=%s" % [join_mode,address,port,player_name])
	join_requested.emit()
	var scene_path := "res://main.tscn" if join_mode == "world" else "res://delve.tscn" if join_mode == "delve" else "res://arena.tscn"
	get_tree().change_scene_to_file(scene_path)

func _set_status(message: String, color: Color = TEAL) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override("font_color",color)

func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("menu", message, data)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if settings != null and settings.is_open():
		settings.close()
		get_viewport().set_input_as_handled()
	elif _lobby_layer != null and _lobby_layer.visible:
		_lobby_layer.visible = false
		get_viewport().set_input_as_handled()
	elif _join_layer != null and _join_layer.visible:
		_close_join()
		get_viewport().set_input_as_handled()
	else:
		_open_settings()
		get_viewport().set_input_as_handled()
