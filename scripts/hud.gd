extends Control

signal bow_selected(index: int)
signal armor_selected(index: int)
signal sword_selected(index: int)
signal weapon_selected(value: String)
signal view_toggled
signal camp_requested
signal map_toggled
signal hub_requested
signal cursor_requested(free: bool)

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const CROSSHAIR_AXES = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
var map_open := false
var reticle := Vector2.ZERO
var reticle_visible := false
var bow_buttons: Array[Button] = []
var armor_buttons: Array[Button] = []
var sword_buttons: Array[Button] = []
var weapon_buttons: Array[Button] = []
var _weapon := "bow"
var _equipment: Panel
var _region: Label
var _quest: Label
var _health_label: Label
var _gold_label: Label
var _phase: Label
var _loadout: Label
var _cover_status: Label
var _bow_details: Label
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _charge_bar: ProgressBar
var _interaction_panel: Panel
var _interaction: Label
var _feedback: Label
var _feedback_time := 0.0
var _damage_flash := 0.0
var _view_button: Button
var _map_button: Button
var _player_position := Vector3.ZERO
var _player_yaw := 0.0
var _activated: Dictionary = {}
var _landmarks: Array[Dictionary] = []
var _paths: Array[PackedVector3Array] = []
var _interactables: Array[Dictionary] = []
var _world_limit := 145.0
var _map_style: StyleBoxFlat

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_style = _style(Color(0.045, 0.095, 0.12, 0.96), Color("58716b"), 10)
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
	var title := _panel(self, Vector2(24, 22), Vector2(300, 88))
	_label(title, "IRONWOOD  " + str(ProjectSettings.get_setting("application/config/version")), Vector2(17, 11), 25, CREAM)
	_region = _label(title, "The frontier", Vector2(18, 49), 16, GOLD)
	var quest_panel := _panel(self, Vector2(-340, 22), Vector2(316, 154))
	quest_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	_label(quest_panel, "WORLD QUEST  /  THE LOST WAYSTONES", Vector2(16, 13), 11, GOLD)
	_quest = _label(quest_panel, "Restore the frontier   0 / 3", Vector2(16, 39), 20, CREAM)
	_label(quest_panel, "Follow the trails to the forest, ruins and ridge.\nDefeat the guards. Press E at each waystone.\nThe village campfire restores your health.", Vector2(16, 78), 12, MUTED)
	_feedback = _label(self, "", Vector2(-360, 111), 17, GOLD)
	_feedback.set_anchors_preset(Control.PRESET_CENTER_TOP, true)
	_feedback.size.x = 720
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_shadow_color", Color("10242b"))
	_feedback.add_theme_constant_override("shadow_outline_size", 4)
	_feedback.add_theme_constant_override("shadow_offset_y", 2)
	var vitals := _panel(self, Vector2(24, -154), Vector2(300, 122))
	vitals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_health_label = _label(vitals, "HEALTH  100 / 100", Vector2(16, 12), 13, CREAM)
	_health_bar = _bar(vitals, Vector2(16, 37), Vector2(268, 11), Color("72b58b"))
	_stamina_bar = _bar(vitals, Vector2(16, 58), Vector2(268, 5), GOLD)
	_label(vitals, "STAMINA", Vector2(16, 70), 10, MUTED)
	_gold_label = _label(vitals, "0 GOLD  /  0 FOES", Vector2(16, 91), 13, GOLD)
	var charge := _panel(self, Vector2(-260, -133), Vector2(520, 101))
	charge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	_phase = _label(charge, "", Vector2(17, 12), 13, CREAM)
	_charge_bar = _bar(charge, Vector2(17, 41), Vector2(486, 8), GOLD)
	_loadout = _label(charge, "", Vector2(17, 63), 13, MUTED)
	var cover_panel := _panel(self, Vector2(24, -255), Vector2(480, 98))
	cover_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	_cover_status = _label(cover_panel, "OPEN / RIGHT SHOULDER", Vector2(15, 10), 12, MUTED)
	_label(cover_panel, "F  Cover / exit   C  Crouch   SPACE  Jump\nSHIFT  Sprint / fast cover   Sprint + C  Slide\nLMB / Q  Attack (sword exits)   HOLD RMB  Guard / peek   X  Lookout side", Vector2(15, 35), 12, CREAM)
	_interaction_panel = _panel(self, Vector2(-310, -190), Vector2(620, 39))
	_interaction_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	_interaction = _label(_interaction_panel, "", Vector2(15, 9), 14, GOLD)
	_interaction_panel.visible = false
	var equipment_button := _button(self, "I   EQUIPMENT", Vector2(-216, -163), Vector2(192, 35))
	equipment_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	equipment_button.pressed.connect(toggle_equipment)
	_map_button = _button(self, "M   WORLD MAP", Vector2(-216, -119), Vector2(192, 35))
	_map_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	_map_button.pressed.connect(func(): map_toggled.emit())
	var camp_button := _button(self, "R   RETURN TO CAMP", Vector2(-216, -75), Vector2(192, 35))
	camp_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	camp_button.pressed.connect(func(): camp_requested.emit())
	var hub_button := _button(self, "RETURN TO THE HOLLOW", Vector2(-216, -207), Vector2(192, 35))
	hub_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	hub_button.add_theme_font_size_override("font_size", 13)
	hub_button.pressed.connect(func(): hub_requested.emit())
	var hints := _label(self, "MOUSE  Aim   HOLD LMB  Draw   RELEASE  Shoot   1  Bow   2  Sword   SHIFT + SPACE  Roll   ESC / I  Equipment cursor", Vector2(-540, -23), 12, CREAM)
	hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	hints.add_theme_color_override("font_shadow_color", Color("10242b"))
	hints.add_theme_constant_override("shadow_outline_size", 3)
	_build_equipment()

func _build_equipment() -> void:
	_equipment = _panel(self, Vector2(24, 130), Vector2(282, 615))
	_label(_equipment, "EQUIPMENT", Vector2(18, 15), 12, GOLD)
	_label(_equipment, "A ranger of Ironwood", Vector2(18, 40), 20, CREAM)
	for index in 2:
		var button := _button(_equipment,["1  BOW","2  SWORD"][index],Vector2(16+index*129,72),Vector2(121,30))
		button.toggle_mode = true
		button.pressed.connect(func(): weapon_selected.emit("bow" if index == 0 else "sword"))
		weapon_buttons.append(button)
	_label(_equipment,"BOW SIZE / CLICK TO SELECT",Vector2(18,112),11,MUTED)
	for index in 3:
		var button := _button(_equipment,["SMALL SHORTBOW / 1s","MEDIUM RECURVE / 2s","LARGE LONGBOW / 3s"][index],Vector2(16,134+index*34),Vector2(250,30))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",13)
		button.size = Vector2(250,30)
		button.pressed.connect(func(): bow_selected.emit(index))
		bow_buttons.append(button)
	_bow_details = _label(_equipment,"",Vector2(18,241),11,TEAL)
	_label(_equipment,"SWORD SIZE / CLICK TO SELECT",Vector2(18,275),11,MUTED)
	for index in 3:
		var button := _button(_equipment,["SMALL SWORD / 1s","MEDIUM SWORD / 2s","LARGE SWORD / 3s"][index],Vector2(16,297+index*34),Vector2(250,30))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",13)
		button.size = Vector2(250,30)
		button.pressed.connect(func(): sword_selected.emit(index))
		sword_buttons.append(button)
	_label(_equipment,"ARMOR / CLICK TO EQUIP",Vector2(18,410),11,MUTED)
	for index in 3:
		var button := _button(_equipment,["RANGER LEATHER / LIGHT","SENTINEL MAIL / 15% GUARD","WARDEN PLATE / 30% GUARD"][index],Vector2(16,432+index*33),Vector2(250,29))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",12)
		button.size = Vector2(250,29)
		button.pressed.connect(func(): armor_selected.emit(index))
		armor_buttons.append(button)
	_view_button = _button(_equipment,"V  INSPECT STANCE",Vector2(16,543),Vector2(250,30))
	_view_button.pressed.connect(func(): view_toggled.emit())
	_label(_equipment,"1 = bow. 2 = sword. Sizes are mouse-only.\nRMB guards with a sword. Escape frees the cursor; click world to aim.",Vector2(18,584),11,MUTED)
	_equipment.visible = false

func configure_map(landmarks: Array[Dictionary], paths: Array[PackedVector3Array], interactables: Array[Dictionary], limit: float) -> void:
	_landmarks = landmarks
	_paths = paths
	_interactables = interactables
	_world_limit = limit

func update_status(health: float, stamina: float, gold: int, kills: int, phase_name: String, draw_amount: float, region: String, interval: float, progress: float, movement: String, blocking: bool = false, parry_ready: bool = false) -> void:
	_region.text = region
	_health_label.text = "HEALTH  %d / 100" % int(health)
	_health_bar.value = health
	_stamina_bar.value = stamina
	_gold_label.text = "%d GOLD  /  %d FOES" % [gold, kills]
	_charge_bar.value = draw_amount * 100.0 if phase_name in ["DRAWING", "HOLDING"] else progress * 100.0
	if phase_name in ["DRAWING", "HOLDING"]:
		_phase.text = "DRAW %.0f%%  /  DAMAGE x%.2f  /  RELEASE TO SHOOT" % [draw_amount * 100, draw_amount]
	elif phase_name == "MELEE":
		_phase.text = "OVERHAND CHOP / %.1f s SWING" % interval
	elif blocking:
		_phase.text = "PARRY WINDOW / COUNTER NOW" if parry_ready else "GUARDING / EACH HIT COSTS STAMINA"
	elif phase_name in ["RELEASE", "RECOVER"]:
		_phase.text = "NOCKING NEXT ARROW / %.1f s" % [(1.0 - progress) * interval]
	elif progress < 0.999999:
		_phase.text = "RECOVERY %.1f s  /  %s" % [(1.0 - progress) * interval, movement]
	else:
		_phase.text = "READY / HOLD LMB TO DRAW / RELEASE TO SHOOT" if _weapon == "bow" else "READY / CLICK FOR AN OVERHAND CHOP"

func update_cover(active: bool, low: bool, peeking: bool, side: int, crouched: bool, sliding: bool) -> void:
	var stance := "SLIDING" if sliding else "CROUCHED" if crouched else "OPEN"
	if active:
		if peeking:
			stance = "TOP LOOKOUT" if low else "LEFT LOOKOUT" if side < 0 else "RIGHT LOOKOUT"
		else:
			stance = ("LOW COVER" if low else "TALL COVER") + (" / CROUCHED" if crouched else " / TUCKED")
	_cover_status.text = stance if active and peeking else stance + (" / LEFT SHOULDER" if side < 0 else " / RIGHT SHOULDER")
	_cover_status.add_theme_color_override("font_color", TEAL if active and peeking else GOLD if active else MUTED)

func update_loadout(bow: int, armor: int, data: Dictionary, armor_name: String, sword: int, weapon: String, sword_data: Dictionary) -> void:
	for index in 3:
		bow_buttons[index].set_pressed_no_signal(index == bow)
		armor_buttons[index].set_pressed_no_signal(index == armor)
		sword_buttons[index].set_pressed_no_signal(index == sword)
	_weapon = weapon
	weapon_buttons[0].set_pressed_no_signal(weapon == "bow")
	weapon_buttons[1].set_pressed_no_signal(weapon == "sword")
	_bow_details.text = "%.0f s FULL DRAW / RE-NOCK AFTER SHOT" % float(data.draw_seconds)
	_loadout.text = "%s / %s / %s" % [weapon.to_upper(),data.name if weapon == "bow" else sword_data.name,armor_name]


func update_world_position(position_at: Vector3, yaw: float, activated: Dictionary) -> void:
	_player_position = position_at
	_player_yaw = yaw
	_activated = activated
	_quest.text = "Frontier restored  3 / 3" if activated.size() == 3 else "Restore the frontier   %d / 3" % activated.size()

func set_interaction(text: String) -> void:
	_interaction_panel.visible = not text.is_empty()
	_interaction.text = text

func set_inspecting(value: bool) -> void:
	_equipment.visible = value
	_view_button.text = "V   RETURN TO ADVENTURE" if value else "V   INSPECT STANCE"

func toggle_equipment() -> void:
	_equipment.visible = not _equipment.visible
	map_open = false
	_map_button.text = "M   WORLD MAP"
	cursor_requested.emit(_equipment.visible)

func toggle_map() -> void:
	map_open = not map_open
	_equipment.visible = false
	_map_button.text = "M   CLOSE MAP" if map_open else "M   WORLD MAP"
	cursor_requested.emit(map_open)

func close_panels() -> void:
	_equipment.visible = false
	map_open = false
	_map_button.text = "M   WORLD MAP"
	cursor_requested.emit(false)

func show_feedback(message: String, seconds: float = 3.0) -> void:
	_feedback.text = message
	_feedback_time = seconds
	_feedback.modulate.a = 1.0

func flash_damage() -> void:
	_damage_flash = 0.35

func _process(delta: float) -> void:
	_feedback_time = maxf(0.0, _feedback_time - delta)
	_feedback.modulate.a = minf(_feedback_time * 2.0, 1.0)
	_damage_flash = maxf(0.0, _damage_flash - delta)
	queue_redraw()

func _draw() -> void:
	if _damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.07, 0.03, _damage_flash * 0.4), false, 14.0)
	if map_open:
		var map_rect := Rect2(Vector2(size.x * 0.5 - 310, 135), Vector2(620, 620))
		_draw_map(map_rect, true)
	else:
		_draw_map(Rect2(Vector2(size.x - 216, 196), Vector2(192, 192)), false)
	if reticle_visible and not map_open:
		for axis in CROSSHAIR_AXES:
			draw_line(reticle+axis*5,reticle+axis*13,Color(0.04,0.09,0.10,0.85),3.5,true)
			draw_line(reticle+axis*5,reticle+axis*13,Color.WHITE,1.25,true)
		draw_circle(reticle,1.5,Color.WHITE)

func _map_point(point: Vector3, rect: Rect2) -> Vector2:
	var normalized := Vector2(point.x, point.z) / (_world_limit * 2.0) + Vector2.ONE * 0.5
	return rect.position + Vector2.ONE * 14 + normalized * (rect.size - Vector2.ONE * 28)

func _draw_map(rect: Rect2, expanded: bool) -> void:
	draw_style_box(_map_style, rect)
	var font := get_theme_default_font()
	for path in _paths:
		for index in range(path.size() - 1):
			draw_line(_map_point(path[index], rect), _map_point(path[index + 1], rect), Color("8f8970"), 3.0 if expanded else 1.4, true)
	for landmark: Dictionary in _landmarks:
		var point := _map_point(landmark.position, rect)
		draw_circle(point, 3.0, MUTED)
		if expanded:
			draw_string(font, point + Vector2(8, -7), landmark.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREAM)
	for item: Dictionary in _interactables:
		var point := _map_point(item.position, rect)
		var color := TEAL if _activated.has(item.id) else GOLD
		if item.kind == "camp":
			draw_rect(Rect2(point - Vector2.ONE * 4, Vector2.ONE * 8), Color("d69b74"))
		else:
			draw_circle(point, 5.0 if expanded else 3.5, color)
			draw_arc(point, 8.0 if expanded else 6.0, 0, TAU, 20, color, 1.0, true)
	var player_point := _map_point(_player_position, rect)
	var direction := Vector2(-sin(_player_yaw), -cos(_player_yaw))
	var right := Vector2(-direction.y, direction.x)
	var triangle := PackedVector2Array([player_point + direction * 8, player_point - direction * 5 + right * 5, player_point - direction * 5 - right * 5])
	draw_colored_polygon(triangle, CREAM)
	draw_string(font, rect.position + Vector2(12, 20), "IRONWOOD FRONTIER  /  M TO CLOSE" if expanded else "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
	if expanded:
		draw_string(font, rect.position + Vector2(18, rect.size.y - 14), "Gold: dark waystone   /   Teal: restored   /   Square: village campfire", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)

func _panel(parent: Node, position_at: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = position_at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
