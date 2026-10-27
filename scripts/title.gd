extends Control
## The main menu. Four doors only: begin a new journey, continue the saved one,
## host your own open world, or join one. Everything else happens inside the world.

signal start_requested
signal load_requested
signal host_requested
signal join_requested

const StateScript = preload("res://scripts/player_state.gd")
const SessionScript = preload("res://scripts/session.gd")

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
var _join_layer: Control
var _name_input: LineEdit
var _join_mode: OptionButton
var _address_input: LineEdit
var _port_input: SpinBox
var _form_error: Label
var _default_name := "Ranger"
var _default_address := "127.0.0.1"
var _default_port := 7777
var crash_notice: Panel
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
	_refresh_load_button()
	print("IRONWOOD_MENU_READY")

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("08141a")
	add_child(backdrop)
	var gradient := Gradient.new()
	gradient.set_color(0,Color("122b31"))
	gradient.set_color(1,Color("050b0f"))
	gradient.add_point(0.55,Color("0a1c22"))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0,0.0)
	texture.fill_to = Vector2(1.0,1.0)
	texture.width = 512
	texture.height = 512
	var wash := TextureRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.texture = texture
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	var frame := Panel.new()
	frame.position = Vector2(72,92)
	frame.size = Vector2(520,716)
	frame.add_theme_stylebox_override("panel",_style(Color(0.03,0.07,0.085,0.92),Color("3f5b60"),10))
	add_child(frame)
	var rule := ColorRect.new()
	rule.position = Vector2(28,196)
	rule.size = Vector2(84,3)
	rule.color = GOLD
	frame.add_child(rule)
	var title := _label(frame,"IRONWOOD",Vector2(26,96),62,CREAM)
	title.size = Vector2(470,74)
	var subtitle := _label(frame,"THE FRONTIER AWAITS",Vector2(28,162),15,GOLD)
	subtitle.size = Vector2(470,20)
	var blurb := _label(frame,"One town. One wilderness. One delve that never ends.\nEverything happens in the world.",Vector2(28,232),14,MUTED)
	blurb.size = Vector2(462,48)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override("font_shadow_color",Color("081418"))
	start_button = _button(frame,"START NEW GAME",Vector2(28,316),Vector2(462,58))
	start_button.add_theme_font_size_override("font_size",19)
	start_button.pressed.connect(_start_new_game)
	_load_button = _button(frame,"LOAD SAVED GAME",Vector2(28,388),Vector2(462,58))
	_load_button.add_theme_font_size_override("font_size",19)
	_load_button.pressed.connect(_load_saved_game)
	host_world_button = _button(frame,"HOST OPEN WORLD",Vector2(28,460),Vector2(462,58))
	host_world_button.add_theme_font_size_override("font_size",19)
	host_world_button.pressed.connect(_host_open_world)
	join_button = _button(frame,"JOIN GAME",Vector2(28,532),Vector2(462,58))
	join_button.add_theme_font_size_override("font_size",19)
	join_button.pressed.connect(_open_join)
	# Ghost of the Warband: the possession campaign, a separate persistent warband
	# with its own save, entered from the cages or resumed in the town.
	var warband_button := _button(frame,"GHOST OF THE WARBAND",Vector2(28,604),Vector2(462,54))
	warband_button.add_theme_font_size_override("font_size",18)
	warband_button.pressed.connect(_enter_warband)
	_status = _label(frame,"",Vector2(28,662),13,TEAL)
	_status.size = Vector2(462,44)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var footer := _label(frame,"WASD  Move    LMB  Attack / Draw    G  Interact\nI  Inventory    P  Equipment    Esc  Menu / Save / Quit",Vector2(28,684),10,MUTED)
	footer.size = Vector2(462,28)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var ranger := Label.new()
	ranger.text = "II"
	ranger.position = Vector2(874,236)
	ranger.add_theme_font_size_override("font_size",164)
	ranger.add_theme_color_override("font_color",Color(0.35,0.55,0.53,0.16))
	add_child(ranger)
	_build_join_layer()

func _enter_warband() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.enter_warband()

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
	panel.add_theme_stylebox_override("panel",_style(Color(0.038,0.078,0.096,0.98),Color("3f5b60"),10))
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
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI"])
	theme.default_font = font
	theme.set_color("font_color","Button",CREAM)
	theme.set_color("font_hover_color","Button",Color.WHITE)
	theme.set_color("font_pressed_color","Button",Color("13282f"))
	theme.set_stylebox("normal","Button",_style(Color("243a40"),Color("456068"),7))
	theme.set_stylebox("hover","Button",_style(Color("34545b"),GOLD,7))
	theme.set_stylebox("pressed","Button",_style(GOLD,GOLD,7))
	result.theme = theme
	parent.add_child(result)
	return result

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
	crash_notice.add_theme_stylebox_override("panel",_style(Color(0.075,0.035,0.03,0.96),Color("8a4b39"),10))
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _join_layer != null and _join_layer.visible:
			_close_join()
			get_viewport().set_input_as_handled()
