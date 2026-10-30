extends Control
## The main menu. Four doors and nothing else: NEW CAMPAIGN (Ghost of the
## Warband from the cages), RESUME CAMPAIGN (the last autosave), JOIN GAME (play
## inside a friend's campaign) and HOST GAME (open yours to friends, fresh or from
## the checkpoint). Hosting shares one warband: every soul that joins plays from
## the host's roster, stash and purse.
##
## The menu never changes scene itself. Every door hands what was chosen to
## `GameFlow`, the one node that outlives the title, and the flow opens the world.

const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const SettingsScript = preload("res://scripts/ui/settings_menu.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const WarbandStateScript = preload("res://scripts/warband/warband_state.gd")
## Only for HOST GAME's two door names; the live flow is always the autoload.
const GameFlowScript = preload("res://scripts/warband/game_flow.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")

const DEFAULT_NAME := "Ranger"
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 7777
const MIN_PORT := 1024
const MAX_PORT := 65535
const NAME_LENGTH := 16

var _status: Label
## Ghost of the Warband from the beginning: a fresh warband in the cages.
var new_campaign_button: Button
## The last autosave. Disabled until a warband save exists, because there is
## nothing to resume before one.
var resume_button: Button
var join_button: Button
var host_button: Button

var _join_layer: Control
var _name_input: LineEdit
var _address_input: LineEdit
var _port_input: SpinBox
var _form_error: Label

var _host_layer: Control
var _host_name_input: LineEdit
var _host_port_input: SpinBox
var host_new_button: Button
var host_checkpoint_button: Button
## Says what FROM CHECKPOINT would open before the player commits to it.
var _host_checkpoint_label: Label
var _host_error: Label

var crash_notice: Panel
## Escape's own window: the menu has no pause to offer, but the mix still needs
## a door, and Escape is the one every screen in the game uses.
var settings
var _crash_report: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_build_crash_notice()
	_build_settings()
	_refresh_resume()
	# A session that ended under the player (the host left, a join never got an
	# answer) comes back to this screen; the reason is the first thing it says.
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		var notice := str(flow.take_notice())
		if not notice.is_empty():
			_set_status(notice, WARN)
		flow.notice_posted.connect(_on_notice_posted)
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
	column.offset_top = -280
	column.offset_bottom = 280
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
	gap.custom_minimum_size = Vector2(0, 26)
	column.add_child(gap)

	new_campaign_button = _plate(column, "NEW CAMPAIGN", "PrimaryButton", _start_new_campaign)
	new_campaign_button.tooltip_text = "Ghost of the Warband from the beginning: a fresh warband in the cages."
	resume_button = _plate(column, "RESUME CAMPAIGN", "", _resume_campaign)
	join_button = _plate(column, "JOIN GAME", "", _open_join)
	join_button.tooltip_text = "Join a friend's campaign and play from their warband."
	host_button = _plate(column, "HOST GAME", "", _open_host)
	host_button.tooltip_text = "Open a new game or your checkpoint to friends; everyone shares your warband."

	_status = _center_label(column, "", 12, LedgerThemeScript.TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_join_layer()
	_build_host_layer()


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


## Every door that opens a campaign on this machine hands the score over to the
## warband: the menu theme stops outright, the soundtrack starts at its own
## beginning, and the door answers with the weight of a door (a blunt take
## pitched into the floor and sent through the reverb bus). A refused door - no
## save to resume - never gets here, because a door that did not open must not
## restart the music.
func _enter_campaign_score() -> void:
	SfxScript.play("menu_thud")
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.start_campaign_music()


# --- NEW CAMPAIGN / RESUME CAMPAIGN ---------------------------------------------

## NEW CAMPAIGN is always the cages with a fresh warband and a fresh purse,
## however the last campaign ended; resuming lives behind its own door.
func _start_new_campaign() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		_set_status("The campaign is unavailable.", WARN)
		return
	_enter_campaign_score()
	_note("menu_new_campaign")
	print("IRONWOOD_MENU_NEW_CAMPAIGN")
	flow.start_campaign()


## RESUME CAMPAIGN opens the save on the bookmark its last autosave left (the
## town when the save predates checkpoints). The file is checked again on the
## press: it may have gone since the screen was built.
func _resume_campaign() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		_set_status("The campaign is unavailable.", WARN)
		return
	if not _has_warband_save():
		_refresh_resume()
		_set_status("No campaign saved yet. Start a new one.", WARN)
		return
	_enter_campaign_score()
	_note("menu_resume", {"save": _warband_save_path()})
	print("IRONWOOD_MENU_RESUME")
	flow.enter_warband()


## The warband save the resume and checkpoint doors read. A warband may pin its
## own path (the regressions do), so this reads the node, not the default.
func _warband_save_path() -> String:
	var warband := get_node_or_null("/root/Warband")
	return "" if warband == null else str(warband.save_path)


func _has_warband_save() -> bool:
	var path := _warband_save_path()
	return not path.is_empty() and FileAccess.file_exists(path)


## Re-reads the save gate for the resume door and the host panel's checkpoint
## door. Called when the screen opens and whenever a panel opens, so a save
## written or deleted while the title stood is never stale.
func _refresh_resume() -> void:
	if resume_button != null:
		var has_save := _has_warband_save()
		resume_button.disabled = not has_save
		if not has_save:
			resume_button.tooltip_text = "No campaign saved yet."
		else:
			var peek := WarbandStateScript.peek_save(_warband_save_path())
			var checkpoint: Dictionary = peek.get("checkpoint", {})
			if not checkpoint.is_empty():
				resume_button.tooltip_text = "Opens on your last checkpoint: %s." % _checkpoint_name(checkpoint)
			else:
				resume_button.tooltip_text = "Opens your last autosave."
	_refresh_host_checkpoint()


## A checkpoint's own label, or its ground when an older save wrote none.
func _checkpoint_name(checkpoint: Dictionary) -> String:
	var label := str(checkpoint.get("label", "")).strip_edges()
	if not label.is_empty():
		return label
	return "HEARTHSTEAD" if str(checkpoint.get("area", "")) == "town" else "THE TRAIL"


# --- JOIN GAME -----------------------------------------------------------------

func _build_join_layer() -> void:
	_join_layer = Control.new()
	_join_layer.name = "JoinLayer"
	_join_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_join_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_join_layer.visible = false
	add_child(_join_layer)
	var panel := _form_panel(_join_layer, Vector2(480, 384))
	_label(panel, "JOIN GAME", Vector2(24, 18), 26, GOLD)
	var hint := _label(panel,
		"You play from the host's warband, so you need no save of your own.",
		Vector2(24, 54), 11, MUTED)
	hint.size = Vector2(432, 32)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(panel, "YOUR NAME", Vector2(24, 96), 10, GOLD)
	_name_input = LineEdit.new()
	_name_input.position = Vector2(24, 116)
	_name_input.size = Vector2(432, 40)
	_name_input.max_length = NAME_LENGTH
	panel.add_child(_name_input)
	_label(panel, "HOST ADDRESS", Vector2(24, 168), 10, GOLD)
	_address_input = LineEdit.new()
	_address_input.position = Vector2(24, 188)
	_address_input.size = Vector2(300, 40)
	panel.add_child(_address_input)
	_label(panel, "UDP PORT", Vector2(340, 168), 10, GOLD)
	_port_input = _port_box(panel, Vector2(340, 188))
	var confirm := _button(panel, "JOIN", Vector2(24, 254), Vector2(214, 44))
	confirm.theme_type_variation = "PrimaryButton"
	confirm.pressed.connect(_confirm_join)
	var cancel := _button(panel, "CANCEL", Vector2(250, 254), Vector2(206, 44))
	cancel.pressed.connect(_close_join)
	_form_error = _label(panel, "", Vector2(24, 312), 11, WARN)
	_form_error.size = Vector2(432, 54)
	_form_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Fills the form from the cache *now*, every time it opens. Reading it once in
## `_ready` froze the name, address and port at whatever the app started with,
## so a session that joined somewhere else kept offering dead values.
func _open_join() -> void:
	if _host_layer != null and _host_layer.visible:
		_close_host()
	var cache := get_node_or_null("/root/NetCache")
	_name_input.text = DEFAULT_NAME if cache == null else str(cache.player_name)
	_address_input.text = DEFAULT_ADDRESS if cache == null else str(cache.address)
	_port_input.value = clampi(DEFAULT_PORT if cache == null else int(cache.port), MIN_PORT, MAX_PORT)
	_form_error.text = ""
	_join_layer.visible = true
	_name_input.grab_focus()
	_name_input.select_all()


func _close_join() -> void:
	_join_layer.visible = false
	_form_error.text = ""


## Connects and waits on this screen: the world opens only once the host answers
## with its warband, and a refusal comes back through `notice_posted`. The music
## is left alone for the same reason - the door has not opened yet.
func _confirm_join() -> void:
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_form_error.text = "Enter the host's address."
		return
	var port := int(_port_input.value)
	if port < MIN_PORT or port > MAX_PORT:
		_form_error.text = "Choose a UDP port between %d and %d." % [MIN_PORT, MAX_PORT]
		return
	var player_name := _clean_name(_name_input.text)
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cache.remember(player_name, address, port)
	_set_status("Joining %s:%d..." % [address, port])
	print("IRONWOOD_MENU_JOIN address=%s port=%d name=%s" % [address, port, player_name])
	_note("menu_join", {"address": address, "port": port, "name": player_name})
	SfxScript.play("menu_thud")
	_close_join()
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		_set_status("The campaign is unavailable.", WARN)
		return
	flow.join_campaign(address, port, player_name)


# --- HOST GAME -----------------------------------------------------------------

func _build_host_layer() -> void:
	_host_layer = Control.new()
	_host_layer.name = "HostLayer"
	_host_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_host_layer.visible = false
	add_child(_host_layer)
	var panel := _form_panel(_host_layer, Vector2(480, 430))
	_label(panel, "HOST GAME", Vector2(24, 18), 26, GOLD)
	var hint := _label(panel,
		"Friends join on this UDP port and play from your warband: one roster, one stash, one purse.",
		Vector2(24, 54), 11, MUTED)
	hint.size = Vector2(432, 32)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(panel, "YOUR NAME", Vector2(24, 96), 10, GOLD)
	_host_name_input = LineEdit.new()
	_host_name_input.position = Vector2(24, 116)
	_host_name_input.size = Vector2(300, 40)
	_host_name_input.max_length = NAME_LENGTH
	panel.add_child(_host_name_input)
	_label(panel, "UDP PORT", Vector2(340, 96), 10, GOLD)
	_host_port_input = _port_box(panel, Vector2(340, 116))
	host_new_button = _button(panel, "NEW GAME", Vector2(24, 180), Vector2(214, 44))
	host_new_button.theme_type_variation = "PrimaryButton"
	host_new_button.tooltip_text = "A fresh campaign in the cages."
	host_new_button.pressed.connect(_confirm_host.bind(GameFlowScript.HOST_NEW))
	host_checkpoint_button = _button(panel, "FROM CHECKPOINT", Vector2(250, 180), Vector2(206, 44))
	host_checkpoint_button.pressed.connect(_confirm_host.bind(GameFlowScript.HOST_CHECKPOINT))
	_host_checkpoint_label = _label(panel, "", Vector2(24, 236), 11, TEAL)
	_host_checkpoint_label.size = Vector2(432, 32)
	_host_checkpoint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cancel := _button(panel, "CANCEL", Vector2(24, 282), Vector2(432, 44))
	cancel.pressed.connect(_close_host)
	_host_error = _label(panel, "", Vector2(24, 342), 11, WARN)
	_host_error.size = Vector2(432, 54)
	_host_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Reads the cache and the save each time it opens. The host side has its own
## port: the guest-side `port` is what a friend typed last, and letting it open
## the socket is how a host ended up serving a port nobody else knew about.
func _open_host() -> void:
	if _join_layer != null and _join_layer.visible:
		_close_join()
	var cache := get_node_or_null("/root/NetCache")
	_host_name_input.text = DEFAULT_NAME if cache == null else str(cache.player_name)
	_host_port_input.value = clampi(DEFAULT_PORT if cache == null else int(cache.host_port), MIN_PORT, MAX_PORT)
	_host_error.text = ""
	_refresh_resume()
	_host_layer.visible = true
	_host_name_input.grab_focus()
	_host_name_input.select_all()


func _close_host() -> void:
	_host_layer.visible = false
	_host_error.text = ""


## FROM CHECKPOINT is only offered when there is a warband save, and the line
## under it says where that save would put the warband down.
func _refresh_host_checkpoint() -> void:
	if host_checkpoint_button == null:
		return
	var peek := WarbandStateScript.peek_save(_warband_save_path())
	var checkpoint: Dictionary = peek.get("checkpoint", {})
	host_checkpoint_button.disabled = not bool(peek.get("exists", false))
	if not bool(peek.get("exists", false)):
		_host_checkpoint_label.text = "No campaign saved yet."
	elif not checkpoint.is_empty():
		_host_checkpoint_label.text = "From checkpoint: %s" % _checkpoint_name(checkpoint)
	elif int(peek.get("roster", 0)) > 0:
		_host_checkpoint_label.text = "From checkpoint: saved warband - opens in Hearthstead"
	else:
		_host_checkpoint_label.text = "The save holds no warband yet - opens a fresh run in the cages."
	host_checkpoint_button.tooltip_text = _host_checkpoint_label.text


func _confirm_host(start: String) -> void:
	var port := int(_host_port_input.value)
	if port < MIN_PORT or port > MAX_PORT:
		_host_error.text = "Choose a UDP port between %d and %d." % [MIN_PORT, MAX_PORT]
		return
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		_host_error.text = "The campaign is unavailable."
		return
	var player_name := _clean_name(_host_name_input.text)
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cache.remember_host(player_name, port)
	_close_host()
	_enter_campaign_score()
	_set_status("Hosting on UDP %d. Friends join on this port." % port)
	print("IRONWOOD_MENU_HOST port=%d start=%s name=%s" % [port, start, player_name])
	_note("menu_host", {"port": port, "start": start, "name": player_name})
	flow.host_campaign(port, player_name, start)


# --- shared form pieces ----------------------------------------------------------

## A name as the session will seat it: one line, sixteen characters, never blank.
func _clean_name(text: String) -> String:
	var clean := text.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ").left(NAME_LENGTH)
	return DEFAULT_NAME if clean.is_empty() else clean


func _form_panel(layer: Control, panel_size: Vector2) -> Panel:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.012, 0.03, 0.038, 0.8)
	layer.add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER, true)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", LedgerThemeScript.iron_panel())
	layer.add_child(panel)
	return panel


func _port_box(parent: Node, position_at: Vector2) -> SpinBox:
	var box := SpinBox.new()
	box.position = position_at
	box.size = Vector2(116, 40)
	box.min_value = MIN_PORT
	box.max_value = MAX_PORT
	parent.add_child(box)
	return box


func _label(parent: Node, text: String, position_at: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = position_at
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
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


# --- settings, crash notice, status ------------------------------------------------

## The settings window is built last so it sits over both forms; Escape is the
## only door to it, exactly as it is in the world.
func _build_settings() -> void:
	settings = SettingsScript.new()
	settings.name = "Settings"
	add_child(settings)


func _open_settings() -> void:
	if settings == null:
		return
	if _join_layer != null and _join_layer.visible:
		_close_join()
	if _host_layer != null and _host_layer.visible:
		_close_host()
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
	_label(crash_notice, "PREVIOUS SESSION ENDED UNEXPECTEDLY", Vector2(20, 16), 14, WARN)
	var detail := _label(crash_notice, "Crash report and session log saved.\nAttach both when reporting the problem.", Vector2(20, 44), 12, MUTED)
	detail.size = Vector2(456, 40)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var file_label := _label(crash_notice, str(_crash_report.get("text_path", "")).get_file(), Vector2(20, 94), 11, TEAL)
	file_label.size = Vector2(456, 18)
	file_label.clip_text = true
	var open_folder := _button(crash_notice, "OPEN CRASH REPORTS", Vector2(20, 124), Vector2(218, 44))
	open_folder.pressed.connect(log.open_crash_folder)
	var open_latest := _button(crash_notice, "OPEN LATEST REPORT", Vector2(250, 124), Vector2(226, 44))
	open_latest.pressed.connect(func(): log.open_report(0))
	_note("menu_crash_notice", {"session_id": str(_crash_report.get("session_id", "")), "reports": reports.size()})


## A join that came to nothing while the title stood. The line is shown here and
## taken from the flow at once, so the next title does not repeat a stale reason.
func _on_notice_posted(text: String) -> void:
	_set_status(text, WARN)
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.take_notice()


func _set_status(message: String, color: Color = TEAL) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override("font_color", color)


func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("menu", message, data)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if settings != null and settings.is_open():
		settings.close()
	elif _host_layer != null and _host_layer.visible:
		_close_host()
	elif _join_layer != null and _join_layer.visible:
		_close_join()
	else:
		_open_settings()
	get_viewport().set_input_as_handled()
