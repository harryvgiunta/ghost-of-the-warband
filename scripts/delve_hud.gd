class_name DelveHud
extends Control

signal hub_requested
signal surface_requested

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const CROSSHAIR_AXES = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const PARTY_ROW_HEIGHT := 26
const MAX_PARTY_ROWS := 8

var reticle := Vector2.ZERO
var reticle_visible := false
var caption_label: Label
var wave_label: Label
var phase_label: Label
var prompt_label: Label
var party_container: VBoxContainer
var game_over_layer: Control
var surface_button: Button
var hub_button: Button
var endpoint_label: Label
var vitals_label: Label

var _endpoint := ""
var _role := "CLIENT"
var _built := false
var _party_panel: Panel
var _row_names: Array[Label] = []
var _row_bars: Array[ProgressBar] = []
var _row_states: Array[Label] = []
var _row_boxes: Array[HBoxContainer] = []
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _stamina_label: Label
var _equipment_label: Label
var _readiness_label: Label
var _prompt_panel: Panel
var _banner_label: Label
var _banner_time := 0.0
var _banner_fade := 0.5
var _toast_panel: Panel
var _toast_label: Label
var _toast_time := 0.0
var _toast_fade := 0.6
var _game_over_title: Label
var _game_over_reason: Label

func _init() -> void:
	_ensure_ui()

func _ready() -> void:
	_ensure_ui()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	_build()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", CREAM)
	ui_theme.set_color("font_color", "Button", CREAM)
	ui_theme.set_color("font_hover_color", "Button", Color.WHITE)
	ui_theme.set_color("font_pressed_color", "Button", Color("13282f"))
	ui_theme.set_stylebox("normal", "Button", _style(Color("243a40"), Color("456068"), 6))
	ui_theme.set_stylebox("hover", "Button", _style(Color("34545b"), GOLD, 6))
	ui_theme.set_stylebox("pressed", "Button", _style(GOLD, GOLD, 6))
	theme = ui_theme
	_build_run_panels()
	_build_party_panel()
	_build_vitals()
	_build_prompt()
	_build_banner()
	_build_toast()
	_build_game_over()
	var swap_hint := _label(self, "TAB  SWAP WEAPONS", Vector2(-190, -38), 11, MUTED)
	swap_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)

func _build_run_panels() -> void:
	var run := _panel(self, Vector2(-200, 14), Vector2(400, 92))
	run.set_anchors_preset(Control.PRESET_CENTER_TOP, true)
	caption_label = _label(run, "THE SUNKEN DELVE", Vector2.ZERO, 10, GOLD)
	caption_label.size = Vector2(400, 16)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label = _label(run, "DEPTH 1  WAVE 1", Vector2(0, 17), 24, CREAM)
	wave_label.size = Vector2(400, 32)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label = _label(run, "TOUCH THE ALTAR TO BEGIN", Vector2(0, 54), 13, TEAL)
	phase_label.size = Vector2(400, 26)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var link := _panel(self, Vector2(-300, 14), Vector2(276, 58))
	link.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	_label(link, "LINK", Vector2(14, 7), 10, GOLD)
	endpoint_label = _label(link, "CLIENT", Vector2(14, 24), 11, CREAM)
	endpoint_label.size = Vector2(248, 28)
	endpoint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_party_panel() -> void:
	_party_panel = _panel(self, Vector2(24, 14), Vector2(300, 46))
	_label(_party_panel, "PARTY", Vector2(12, 7), 10, GOLD)
	party_container = VBoxContainer.new()
	party_container.position = Vector2(12, 28)
	party_container.size = Vector2(276, 0)
	party_container.add_theme_constant_override("separation", 2)
	party_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_panel.add_child(party_container)

func _add_party_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	party_container.add_child(row)
	var name_label := _label(row, "", Vector2.ZERO, 13, CREAM)
	name_label.custom_minimum_size = Vector2(124, 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bar := _bar(row, Vector2.ZERO, Vector2(86, 8), TEAL)
	bar.custom_minimum_size = Vector2(86, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var state_label := _label(row, "", Vector2.ZERO, 11, MUTED)
	state_label.custom_minimum_size = Vector2(58, 0)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row_boxes.append(row)
	_row_names.append(name_label)
	_row_bars.append(bar)
	_row_states.append(state_label)

func _build_vitals() -> void:
	var vitals := _panel(self, Vector2(24, -196), Vector2(300, 160))
	vitals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	vitals_label = _label(vitals, "HEALTH  100 / 100", Vector2(14, 8), 13, CREAM)
	vitals_label.size = Vector2(272, 18)
	_health_bar = _bar(vitals, Vector2(14, 32), Vector2(272, 10), TEAL)
	_stamina_bar = _bar(vitals, Vector2(14, 52), Vector2(272, 6), GOLD)
	_stamina_label = _label(vitals, "STAMINA  100 / 100", Vector2(14, 62), 10, MUTED)
	_stamina_label.size = Vector2(272, 14)
	_equipment_label = _label(vitals, "", Vector2(14, 82), 11, GOLD)
	_equipment_label.size = Vector2(272, 16)
	_equipment_label.clip_text = true
	_readiness_label = _label(vitals, "READY", Vector2(14, 102), 12, CREAM)
	_readiness_label.size = Vector2(272, 48)
	_readiness_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_prompt() -> void:
	_prompt_panel = _panel(self, Vector2(-250, -164), Vector2(500, 40))
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	prompt_label = _label(_prompt_panel, "", Vector2(14, 10), 14, GOLD)
	prompt_label.size = Vector2(472, 20)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.clip_text = true
	prompt_label.visible = false
	_prompt_panel.visible = false

func _build_banner() -> void:
	_banner_label = _label(self, "", Vector2(-400, -140), 40, GOLD)
	_banner_label.size = Vector2(800, 100)
	_banner_label.set_anchors_preset(Control.PRESET_CENTER, true)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_color_override("font_shadow_color", Color("10242b"))
	_banner_label.add_theme_constant_override("shadow_outline_size", 6)
	_banner_label.add_theme_constant_override("shadow_offset_y", 3)
	_banner_label.visible = false

func _build_toast() -> void:
	_toast_panel = _panel(self, Vector2(24, -252), Vector2(360, 40))
	_toast_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_toast_label = _label(_toast_panel, "", Vector2(12, 10), 12, TEAL)
	_toast_label.size = Vector2(336, 20)
	_toast_panel.visible = false

func _build_game_over() -> void:
	game_over_layer = Control.new()
	game_over_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_layer.visible = false
	add_child(game_over_layer)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("050b0e")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_layer.add_child(shade)
	var box := _panel(game_over_layer, Vector2(-240, -135), Vector2(480, 270))
	box.set_anchors_preset(Control.PRESET_CENTER, true)
	_game_over_title = _label(box, "THE DELVE CLAIMS YOU", Vector2(24, 24), 26, GOLD)
	_game_over_title.size = Vector2(432, 36)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_reason = _label(box, "", Vector2(24, 74), 14, CREAM)
	_game_over_reason.size = Vector2(432, 98)
	_game_over_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_game_over_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	surface_button = _button(box, "RETURN TO TOWN", Vector2(24, 196), Vector2(208, 42))
	surface_button.add_theme_font_size_override("font_size", 12)
	surface_button.pressed.connect(func(): surface_requested.emit())
	hub_button = _button(box, "ABANDON DELVE", Vector2(248, 196), Vector2(208, 42))
	hub_button.add_theme_font_size_override("font_size", 12)
	hub_button.pressed.connect(func(): hub_requested.emit())

func configure(endpoint: String) -> void:
	_ensure_ui()
	_endpoint = endpoint
	_role = "HOST" if not endpoint.is_empty() else "CLIENT"
	_refresh_endpoint()

func _refresh_endpoint() -> void:
	if endpoint_label == null:
		return
	if _endpoint.is_empty():
		endpoint_label.text = _role
	else:
		endpoint_label.text = "%s  /  %s" % [_role, _endpoint]

func update_run(state: Dictionary) -> void:
	_ensure_ui()
	if state.has("endpoint"):
		var endpoint := str(state.get("endpoint", ""))
		if not endpoint.is_empty():
			_endpoint = endpoint
	# The host's slot zero is the only seat that owns the run; a client's
	# endpoint is the host address, so endpoint presence cannot decide the role.
	_role = "HOST" if int(state.get("local_slot", -1)) == 0 else "CLIENT"
	_refresh_endpoint()
	var depth := maxi(1, int(state.get("depth", 1)))
	var wave := maxi(1, int(state.get("wave_number", 1)))
	var phase := str(state.get("phase", "ALTAR"))
	caption_label.text = _room_caption(str(state.get("room", "sanctuary")))
	wave_label.text = "DEPTH %d  WAVE %d" % [depth, wave]
	phase_label.text = _phase_line(state, phase)
	var phase_color := CREAM
	if phase == "GAME_OVER" or phase == "RITUAL" or phase == "DROP":
		phase_color = GOLD
	elif phase == "CLEARED":
		phase_color = TEAL
	phase_label.add_theme_color_override("font_color", phase_color)
	_update_party(state)

func _room_caption(room: String) -> String:
	if room == "ossuary":
		return "THE OSSUARY PIT"
	return "THE SUNKEN DELVE"

func _phase_line(state: Dictionary, phase: String) -> String:
	match phase:
		"ALTAR":
			if str(state.get("room", "sanctuary")) == "ossuary":
				return "THE SUMMONING CONTINUES"
			return "TOUCH THE ALTAR TO BEGIN"
		"RITUAL":
			return "THE PENTAGRAM WAKES - %d INCOMING" % int(state.get("wave_total", 0))
		"DROP":
			return "FALLING INTO THE PIT"
		"WAVE":
			var remaining := int(state.get("remaining", 0))
			var sealed := bool(state.get("sealed", true))
			return ("SEALED — DEVILS REMAINING %d" if sealed else "DEVILS REMAINING %d") % remaining
		"CLEARED":
			var timer := float(state.get("timer", -1.0))
			if bool(state.get("chest_open", false)):
				return "CACHE CLAIMED — ROPE OR HOLE"
			if timer > 0.0:
				return "DEPTH CLEARED — CACHE SEALING %.1f" % timer
			if bool(state.get("chest_ready", false)):
				return "CACHE READY — ROPE OR HOLE"
			return "DEPTH CLEARED"
		"GAME_OVER":
			return "THE DELVE CLAIMS YOU"
	return phase

func _update_party(state: Dictionary) -> void:
	var party: Variant = state.get("party", [])
	if not (party is Array):
		party = []
	var local_slot := int(state.get("local_slot", -1))
	var used := 0
	for member in party:
		if used >= MAX_PARTY_ROWS:
			break
		if not (member is Dictionary):
			continue
		_ensure_party_rows(used + 1)
		var row: Dictionary = member
		var health := float(row.get("health", 100.0))
		var alive := bool(row.get("alive", true)) and health > 0.0
		var is_local := bool(row.get("is_local", false))
		if not is_local and local_slot >= 0:
			is_local = int(row.get("slot", -1)) == local_slot
		var display_name := str(row.get("name", "RANGER"))
		_row_names[used].text = ("> " if is_local else "  ") + display_name
		_row_names[used].add_theme_color_override("font_color", GOLD if (is_local and alive) else (MUTED if not alive else CREAM))
		_row_bars[used].value = clampf(health, 0.0, 100.0)
		_row_states[used].text = "FALLEN" if not alive else "%d" % int(health)
		_row_states[used].add_theme_color_override("font_color", MUTED if not alive else TEAL)
		_row_boxes[used].visible = true
		used += 1
	for index in _row_boxes.size():
		if index >= used:
			_row_boxes[index].visible = false
	var height := 46.0 if used == 0 else 38.0 + float(used) * PARTY_ROW_HEIGHT + 6.0
	_party_panel.size = Vector2(_party_panel.size.x, height)
	party_container.size = Vector2(party_container.size.x, float(used) * PARTY_ROW_HEIGHT)

func _ensure_party_rows(count: int) -> void:
	while _row_boxes.size() < count and _row_boxes.size() < MAX_PARTY_ROWS:
		_add_party_row()

func update_local(state: Dictionary) -> void:
	_ensure_ui()
	var health := float(state.get("health", 100.0))
	var stamina := float(state.get("stamina", 100.0))
	vitals_label.text = "HEALTH  %d / 100" % int(health)
	_health_bar.value = clampf(health, 0.0, 100.0)
	_stamina_bar.value = clampf(stamina, 0.0, 100.0)
	_stamina_label.text = "STAMINA  %d / 100" % int(stamina)
	var weapon := str(state.get("weapon", "")).to_upper()
	var movement := str(state.get("movement", "OPEN")).to_upper()
	if weapon.is_empty():
		weapon = "UNARMED"
	_equipment_label.text = "%s  /  %s" % [weapon, movement]
	var blocking := bool(state.get("blocking", false))
	var parry := bool(state.get("parry", false))
	var phase := str(state.get("phase", "READY"))
	var draw := float(state.get("draw", 0.0))
	var progress := float(state.get("attack_progress", 1.0))
	var interval := maxf(0.001, float(state.get("attack_interval", 0.0)))
	var readiness := _readiness_line(phase, draw, progress, interval, blocking, parry)
	var left := float(state.get("left", 1.0))
	var right := float(state.get("right", 1.0))
	if left < 0.999999 or right < 0.999999:
		readiness += "   L %s / R %s" % [_percent(left), _percent(right)]
	if phase == "READY" and progress >= 0.999999:
		if weapon == "DUAL":
			readiness += "  /  LMB LEFT CUT / RMB RIGHT CUT"
		elif weapon in ["SWORD", "DAGGER"]:
			readiness += "  /  LMB DIAGONAL / WHEEL STAB, OVERHEAD"
	_readiness_label.text = readiness

func _readiness_line(phase: String, draw: float, progress: float, interval: float, blocking: bool, parry: bool) -> String:
	var remaining := maxf(0.0, 1.0 - progress) * interval
	if phase == "DRAWING" or phase == "HOLDING":
		return "DRAW %d%%  /  RELEASE TO STRIKE" % int(round(draw * 100.0))
	if phase == "T_DRAW" or phase == "T_HOLD":
		return "THROW %d%%  /  RELEASE" % int(round(draw * 100.0))
	if phase in ["MELEE_DL", "MELEE_DR", "MELEE_L"]:
		return "DIAGONAL CUT  /  %.2f s" % interval
	if phase == "MELEE_ST":
		return "FORWARD STAB  /  %.2f s" % interval
	if phase.begins_with("MELEE"):
		return "OVERHEAD  /  %.2f s" % interval
	if blocking:
		return "PARRY WINDOW  /  COUNTER NOW" if parry else "GUARDING  /  HOLD RMB"
	if phase == "RELEASE" or phase == "RECOVER" or phase == "T_RELEASE" or phase == "T_RECOVER":
		return "RECOVERY  /  %.1f s" % remaining
	if progress < 0.999999:
		return "RECOVERY  /  %.1f s" % remaining
	return "READY"

func _percent(value: float) -> String:
	if value >= 0.999999:
		return "READY"
	return "%d%%" % int(value * 100.0)

func set_prompt(text: String) -> void:
	_ensure_ui()
	if prompt_label == null:
		return
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()
	_prompt_panel.visible = not text.is_empty()

func show_banner(text: String, seconds: float = 2.0) -> void:
	_ensure_ui()
	if _banner_label == null:
		return
	_banner_label.text = text
	_banner_time = maxf(0.05, seconds)
	_banner_fade = maxf(0.05, minf(0.6, _banner_time * 0.5))
	_banner_label.modulate.a = 1.0
	_banner_label.visible = true

func show_game_over(reason: String) -> void:
	_ensure_ui()
	if game_over_layer == null:
		return
	_game_over_title.text = "THE DELVE CLAIMS YOU"
	_game_over_reason.text = reason
	surface_button.visible = true
	surface_button.position = Vector2(24, 196)
	hub_button.visible = true
	hub_button.position = Vector2(248, 196)
	game_over_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_layer.visible = true

func show_connection_lost(message: String) -> void:
	_ensure_ui()
	if game_over_layer == null:
		return
	_game_over_title.text = "CONNECTION LOST"
	_game_over_reason.text = message
	surface_button.visible = false
	hub_button.visible = true
	hub_button.position = Vector2(136, 196)
	game_over_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_layer.visible = true

func set_status(message: String, seconds: float = 3.0) -> void:
	_ensure_ui()
	if _toast_panel == null:
		return
	if message.is_empty():
		_toast_time = 0.0
		_toast_panel.visible = false
		return
	_toast_label.text = message
	_toast_time = maxf(0.1, seconds)
	_toast_fade = maxf(0.05, minf(0.6, _toast_time * 0.5))
	_toast_panel.modulate.a = 1.0
	_toast_panel.visible = true

func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time = maxf(0.0, _banner_time - delta)
		if _banner_time <= 0.0:
			if _banner_label != null:
				_banner_label.visible = false
		else:
			_banner_label.modulate.a = minf(1.0, _banner_time / _banner_fade)
	if _toast_time > 0.0:
		_toast_time = maxf(0.0, _toast_time - delta)
		if _toast_time <= 0.0:
			if _toast_panel != null:
				_toast_panel.visible = false
		else:
			_toast_panel.modulate.a = minf(1.0, _toast_time / _toast_fade)
	queue_redraw()

func _draw() -> void:
	if reticle_visible and not (game_over_layer != null and game_over_layer.visible):
		for axis in CROSSHAIR_AXES:
			draw_line(reticle + axis * 5, reticle + axis * 13, Color(0.04, 0.09, 0.10, 0.85), 3.5, true)
			draw_line(reticle + axis * 5, reticle + axis * 13, Color.WHITE, 1.25, true)
		draw_circle(reticle, 1.5, Color.WHITE)

func _panel(parent: Node, position_at: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = position_at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.095, 0.12, 0.92), Color("3c5358"), 9))
	parent.add_child(panel)
	return panel

func _label(parent: Node, text: String, position_at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, position_at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position_at
	button.custom_minimum_size = dimensions
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _bar(parent: Node, position_at: Vector2, dimensions: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position_at
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_font_size_override("font_size", 1)
	bar.add_theme_stylebox_override("background", _style(Color("30464b"), Color.TRANSPARENT, 3))
	bar.add_theme_stylebox_override("fill", _style(color, Color.TRANSPARENT, 3))
	parent.add_child(bar)
	bar.size = dimensions
	return bar

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style
