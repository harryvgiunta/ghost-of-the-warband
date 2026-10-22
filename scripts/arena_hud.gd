extends Control

signal host_requested(port: int, player_name: String)
signal join_requested(address: String, port: int, player_name: String)
signal leave_requested
signal hub_requested
signal bow_selected(index: int)
signal armor_selected(index: int)
signal sword_selected(index: int)
signal weapon_selected(value: String)

const UI = preload("res://scripts/hud.gd")
var reticle := Vector2.ZERO
var reticle_visible := false
var lobby: Panel
var match_ui: Control
var name_input: LineEdit
var address_input: LineEdit
var port_input: SpinBox
var status_label: Label
var roster: Label
var health_label: Label
var attack_label: Label
var connection_label: Label
var respawn_label: Label
var _cover_status: Label
var bar: ProgressBar
var bow_buttons: Array[Button] = []
var armor_buttons: Array[Button] = []
var sword_buttons: Array[Button] = []
var weapon_buttons: Array[Button] = []
var _ui := UI.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI"])
	style_theme.default_font = font
	style_theme.default_font_size = 16
	style_theme.set_color("font_color", "Label", UI.CREAM)
	style_theme.set_color("font_color", "Button", UI.CREAM)
	style_theme.set_color("font_pressed_color", "Button", Color("13282f"))
	style_theme.set_stylebox("normal", "Button", _ui._style(Color("243a40"),Color("456068"),6))
	style_theme.set_stylebox("hover", "Button", _ui._style(Color("34545b"),UI.GOLD,6))
	style_theme.set_stylebox("pressed", "Button", _ui._style(UI.GOLD,UI.GOLD,6))
	theme = style_theme
	lobby = _ui._panel(self, Vector2(-285,-285),Vector2(570,570))
	lobby.set_anchors_preset(Control.PRESET_CENTER,true)
	_ui._label(lobby,"IRONWOOD / ARENA  " + str(ProjectSettings.get_setting("application/config/version")),Vector2(25,22),28,UI.GOLD)
	_ui._label(lobby,"Four fighters. Every archer for himself.",Vector2(25,68),18,UI.CREAM)
	_ui._label(lobby,"Empty seats use bots. Joining players replace bots.\nLAN / direct IP  •  No account or matchmaking required.",Vector2(25,101),14,UI.MUTED)
	_ui._label(lobby,"YOUR NAME",Vector2(25,159),12,UI.GOLD)
	name_input = LineEdit.new()
	name_input.position = Vector2(25,184)
	name_input.size = Vector2(300,38)
	name_input.text = "Ranger"
	name_input.max_length = 16
	lobby.add_child(name_input)
	_ui._label(lobby,"UDP PORT",Vector2(350,159),12,UI.GOLD)
	port_input = SpinBox.new()
	port_input.position = Vector2(350,184)
	port_input.size = Vector2(190,38)
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = 7777
	lobby.add_child(port_input)
	var host_button := _ui._button(lobby,"HOST ARENA + BOTS",Vector2(25,239),Vector2(515,42))
	host_button.pressed.connect(func(): host_requested.emit(int(port_input.value),name_input.text))
	_ui._label(lobby,"HOST ADDRESS",Vector2(25,302),12,UI.GOLD)
	address_input = LineEdit.new()
	address_input.position = Vector2(25,326)
	address_input.size = Vector2(315,40)
	address_input.text = "127.0.0.1"
	lobby.add_child(address_input)
	var join_button := _ui._button(lobby,"JOIN GAME",Vector2(355,326),Vector2(185,40))
	join_button.pressed.connect(func(): join_requested.emit(address_input.text,int(port_input.value),name_input.text))
	status_label = _ui._label(lobby,"",Vector2(25,389),14,UI.TEAL)
	status_label.size = Vector2(515,96)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hub := _ui._button(lobby,"RETURN TO THE HOLLOW",Vector2(25,505),Vector2(515,38))
	hub.pressed.connect(func(): hub_requested.emit())
	match_ui = Control.new()
	match_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	match_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(match_ui)
	var top := _ui._panel(match_ui,Vector2(24,22),Vector2(475,102))
	_ui._label(top,"IRONWOOD / ARENA  " + str(ProjectSettings.get_setting("application/config/version")),Vector2(18,12),22,UI.GOLD)
	connection_label = _ui._label(top,"",Vector2(18,46),12,UI.MUTED)
	connection_label.size = Vector2(440,45)
	connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scores := _ui._panel(match_ui,Vector2(-342,22),Vector2(318,190))
	scores.set_anchors_preset(Control.PRESET_TOP_RIGHT,true)
	_ui._label(scores,"COMBATANTS                K / D",Vector2(16,12),14,UI.GOLD)
	roster = _ui._label(scores,"",Vector2(16,45),15,UI.CREAM)
	roster.add_theme_constant_override("line_spacing",9)
	var bottom := _ui._panel(match_ui,Vector2(-320,-143),Vector2(640,100))
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM,true)
	health_label = _ui._label(bottom,"",Vector2(18,10),16,UI.TEAL)
	attack_label = _ui._label(bottom,"",Vector2(18,35),14,UI.CREAM)
	bar = _ui._bar(bottom,Vector2(18,73),Vector2(604,8),UI.GOLD)
	var cover_panel := _ui._panel(match_ui,Vector2(24,145),Vector2(480,98))
	cover_panel.set_anchors_preset(Control.PRESET_TOP_LEFT,true)
	_cover_status = _ui._label(cover_panel,"OPEN / RIGHT SHOULDER",Vector2(15,10),12,UI.MUTED)
	_ui._label(cover_panel,"F  Cover / exit   C  Crouch   SPACE  Jump\nSHIFT  Sprint / fast cover   Sprint + C  Slide\nLMB / Q  Attack (sword exits)   HOLD RMB  Guard / peek   X  Lookout side",Vector2(15,35),12,UI.CREAM)
	respawn_label = _ui._label(match_ui,"",Vector2(-300,-30),28,UI.GOLD)
	respawn_label.set_anchors_preset(Control.PRESET_CENTER,true)
	respawn_label.size.x = 600
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var equipment := _ui._panel(match_ui,Vector2(24,-360),Vector2(330,317))
	equipment.set_anchors_preset(Control.PRESET_BOTTOM_LEFT,true)
	for index in 2:
		var button := _ui._button(equipment,["1  BOW","2  SWORD"][index],Vector2(12+index*158,12),Vector2(148,32))
		button.toggle_mode = true
		button.pressed.connect(func(): weapon_selected.emit("bow" if index == 0 else "sword"))
		weapon_buttons.append(button)
	_ui._label(equipment,"BOW SIZE / CLICK",Vector2(14,56),11,UI.GOLD)
	_ui._label(equipment,"SWORD SIZE / CLICK",Vector2(174,56),11,UI.GOLD)
	for index in 3:
		var title: String = ["SMALL / 1s","MEDIUM / 2s","LARGE / 3s"][index]
		var bow := _ui._button(equipment,title,Vector2(12,78+index*37),Vector2(148,32))
		bow.toggle_mode = true
		bow.add_theme_font_size_override("font_size",13)
		bow.size = Vector2(148,32)
		bow.pressed.connect(func(): bow_selected.emit(index))
		bow_buttons.append(bow)
		var sword := _ui._button(equipment,title,Vector2(170,78+index*37),Vector2(148,32))
		sword.toggle_mode = true
		sword.add_theme_font_size_override("font_size",13)
		sword.size = Vector2(148,32)
		sword.pressed.connect(func(): sword_selected.emit(index))
		sword_buttons.append(sword)
	_ui._label(equipment,"ARMOR / CLICK TO EQUIP",Vector2(14,204),11,UI.GOLD)
	for index in 3:
		var button := _ui._button(equipment,["Leather","Mail","Plate"][index],Vector2(12+index*105,228),Vector2(100,32))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",12)
		button.size = Vector2(100,32)
		button.pressed.connect(func(): armor_selected.emit(index))
		armor_buttons.append(button)
	_ui._label(equipment,"ESC / I: cursor. Sizes: mouse. RMB: guard.",Vector2(14,278),12,UI.MUTED)
	var leave := _ui._button(match_ui,"LEAVE MATCH",Vector2(-200,-83),Vector2(176,40))
	leave.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT,true)
	leave.pressed.connect(func(): leave_requested.emit())
	var hints := _ui._label(match_ui,"MOUSE  Aim   HOLD LMB  Draw   RELEASE  Shoot   1  Bow   2  Sword   SHIFT + SPACE  Roll   ESC / I  Equipment cursor",Vector2(-560,-25),12,UI.CREAM)
	hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM,true)
	show_lobby()

func _exit_tree() -> void:
	_ui.free()

func show_lobby(message: String = "Host a game or enter the host's IP address to join.") -> void:
	lobby.visible = true
	match_ui.visible = false
	reticle_visible = false
	set_status(message)

func show_match(local_name: String, address: String) -> void:
	lobby.visible = false
	match_ui.visible = true
	connection_label.text = local_name + "  /  " + address

func set_status(message: String) -> void:
	status_label.text = message

func update_match(state: Dictionary) -> void:
	var lines := PackedStringArray()
	for row: Dictionary in state.players:
		var prefix := "> " if int(row.slot) == int(state.local_slot) else "   "
		lines.append("%s%s [%s]   %d / %d" % [prefix,str(row.name).left(12),"BOT" if row.bot else "P",int(row.kills),int(row.deaths)])
	roster.text = "\n".join(lines)
	health_label.text = "HEALTH  %d / 100   /   %s" % [int(state.health),str(state.movement)]
	var drawing: bool = state.phase in ["DRAWING","HOLDING"]
	if drawing:
		attack_label.text = "DRAW %.0f%% / DAMAGE x%.2f / RELEASE TO FIRE" % [float(state.draw)*100,float(state.draw)]
	elif state.phase == "MELEE":
		attack_label.text = "OVERHAND CHOP / %.1f s SWING" % float(state.attack_interval)
	elif state.get("blocking",false):
		attack_label.text = "PARRY WINDOW / COUNTER NOW" if state.get("parry",false) else "GUARDING / HOLD RMB"
	elif state.phase in ["RELEASE", "RECOVER"]:
		attack_label.text = "NOCKING NEXT ARROW / %.1f s" % [(1.0-float(state.attack_progress))*float(state.attack_interval)]
	elif float(state.attack_progress) < 0.999999:
		attack_label.text = "RECOVERY %.1f s" % [(1.0-float(state.attack_progress))*float(state.attack_interval)]
	else:
		attack_label.text = "READY / HOLD LMB, AIM, RELEASE" if state.weapon == "bow" else "READY / CLICK FOR AN OVERHAND CHOP"
	bar.value = float(state.draw if drawing else state.attack_progress) * 100.0
	respawn_label.text = "RESPAWNING IN %.1f" % float(state.respawn) if float(state.respawn) > 0 else ""
	for index in 3:
		bow_buttons[index].set_pressed_no_signal(index == int(state.bow))
		armor_buttons[index].set_pressed_no_signal(index == int(state.armor))
		sword_buttons[index].set_pressed_no_signal(index == int(state.sword))
	weapon_buttons[0].set_pressed_no_signal(state.weapon == "bow")
	weapon_buttons[1].set_pressed_no_signal(state.weapon == "sword")

func update_cover(active: bool, low: bool, peeking: bool, side: int, crouched: bool, sliding: bool) -> void:
	var stance := "SLIDING" if sliding else "CROUCHED" if crouched else "OPEN"
	if active:
		if peeking:
			stance = "TOP LOOKOUT" if low else "LEFT LOOKOUT" if side < 0 else "RIGHT LOOKOUT"
		else:
			stance = ("LOW COVER" if low else "TALL COVER") + (" / CROUCHED" if crouched else " / TUCKED")
	_cover_status.text = stance if active and peeking else stance + (" / LEFT SHOULDER" if side < 0 else " / RIGHT SHOULDER")
	_cover_status.add_theme_color_override("font_color", UI.TEAL if active and peeking else UI.GOLD if active else UI.MUTED)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if reticle_visible and not lobby.visible:
		for axis in UI.CROSSHAIR_AXES:
			draw_line(reticle+axis*5,reticle+axis*13,Color(0.04,0.09,0.10,0.85),3.5,true)
			draw_line(reticle+axis*5,reticle+axis*13,Color.WHITE,1.25,true)
		draw_circle(reticle,1.5,Color.WHITE)
