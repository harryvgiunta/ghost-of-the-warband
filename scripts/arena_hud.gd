extends Control

const ArmorData = preload("res://scripts/armor_data.gd")

signal host_requested(port: int, player_name: String)
signal join_requested(address: String, port: int, player_name: String)
signal leave_requested
signal town_requested
signal bow_selected(index: int)
signal armor_selected(slot: String, set_index: int)
signal sword_selected(index: int)
signal weapon_selected(value: String)
signal shield_selected(active: bool)
signal consumable_selected(kind: String)

const UI = preload("res://scripts/hud.gd")
const AbilitySlot = preload("res://scripts/ability_slot.gd")
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
var toast_label: Label
var _toast_time := 0.0
var _cover_status: Label
var bar: ProgressBar
var _ability_slot
var _off_ability_slot
var _trinket_ability_slot
var bow_buttons: Array[Button] = []
var armor_buttons: Array[Button] = []
var _armor_pieces: Dictionary = {}
var sword_buttons: Array[Button] = []
var weapon_buttons: Array[Button] = []
var shield_button: Button
var dual_button: Button
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
	var hub := _ui._button(lobby,"RETURN TO TOWN",Vector2(25,505),Vector2(515,38))
	hub.pressed.connect(func(): town_requested.emit())
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		name_input.text = str(cache.player_name)
		address_input.text = str(cache.address)
		port_input.value = int(cache.port)
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
	_ability_slot = AbilitySlot.new()
	_ability_slot.position = Vector2(24,-143)
	_ability_slot.configure(0)
	_ability_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT,true)
	match_ui.add_child(_ability_slot)
	_off_ability_slot = AbilitySlot.new()
	_off_ability_slot.position = Vector2(128,-143)
	_off_ability_slot.configure(1)
	_off_ability_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT,true)
	match_ui.add_child(_off_ability_slot)
	_trinket_ability_slot = AbilitySlot.new()
	_trinket_ability_slot.position = Vector2(232,-143)
	_trinket_ability_slot.configure(2)
	_trinket_ability_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT,true)
	match_ui.add_child(_trinket_ability_slot)
	var cover_panel := _ui._panel(match_ui,Vector2(24,145),Vector2(620,116))
	cover_panel.set_anchors_preset(Control.PRESET_TOP_LEFT,true)
	_cover_status = _ui._label(cover_panel,"OPEN / RIGHT SHOULDER",Vector2(15,10),12,UI.MUTED)
	_ui._label(cover_panel,"F  Cover / exit   C  Crouch   SPACE  Jump   Q / E  Step left / right\nSHIFT  Sprint / fast cover   Sprint + C  Slide\nLMB  Diagonal cut / draw   WHEEL UP  Stab   WHEEL DOWN  Overhead\nRMB  Guard / peek (dual: right cut)   HOLD T  Throw   X  Lookout",Vector2(15,35),11,UI.CREAM)
	respawn_label = _ui._label(match_ui,"",Vector2(-300,-30),28,UI.GOLD)
	respawn_label.set_anchors_preset(Control.PRESET_CENTER,true)
	respawn_label.size.x = 600
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label = _ui._label(match_ui,"",Vector2(-300,-170),13,UI.TEAL)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM,true)
	toast_label.size = Vector2(600,22)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var equipment := _ui._panel(match_ui,Vector2(24,-360),Vector2(330,317))
	equipment.set_anchors_preset(Control.PRESET_BOTTOM_LEFT,true)
	for index in 3:
		var button := _ui._button(equipment,["1 BOW","2 SWD","3 DAG"][index],Vector2(12+index*78,12),Vector2(74,32))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",10)
		button.size = Vector2(74,32)
		button.pressed.connect(func(): weapon_selected.emit("bow" if index == 0 else "sword" if index == 1 else "dagger"))
		weapon_buttons.append(button)
	dual_button = _ui._button(equipment,"5 DUAL",Vector2(246,12),Vector2(74,32))
	dual_button.toggle_mode = true
	dual_button.add_theme_font_size_override("font_size",10)
	dual_button.size = Vector2(74,32)
	dual_button.pressed.connect(func(): weapon_selected.emit("dual"))
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
	_ui._label(equipment,"ARMOR / CLICK SLOT TO CYCLE",Vector2(14,204),11,UI.GOLD)
	for index in ArmorData.SLOTS.size():
		var slot: String = ArmorData.SLOTS[index]
		var button := _ui._button(equipment,"",Vector2(12+index*62,228),Vector2(58,34))
		button.add_theme_font_size_override("font_size",9)
		button.size = Vector2(58,34)
		button.pressed.connect(_cycle_armor.bind(slot))
		armor_buttons.append(button)
	shield_button = _ui._button(equipment,"4  SHIELD",Vector2(12,268),Vector2(100,28))
	shield_button.toggle_mode = true
	shield_button.add_theme_font_size_override("font_size",11)
	shield_button.toggled.connect(func(active: bool): shield_selected.emit(active))
	var bandage := _ui._button(equipment,"6 BANDAGE",Vector2(118,268),Vector2(100,28))
	bandage.add_theme_font_size_override("font_size",10)
	bandage.pressed.connect(func(): consumable_selected.emit("bandage"))
	var potion := _ui._button(equipment,"7 POTION",Vector2(224,268),Vector2(94,28))
	potion.add_theme_font_size_override("font_size",10)
	potion.pressed.connect(func(): consumable_selected.emit("potion"))
	_ui._label(equipment,"Gear 1-5. 6 bandage / 7 potion. LMB by shoulder. Wheel: stab / overhead.",Vector2(14,301),9,UI.MUTED)
	# The persistent paperdoll is the only visible equipment UI; P opens it.
	equipment.visible = false
	var leave := _ui._button(match_ui,"LEAVE MATCH",Vector2(-200,-83),Vector2(176,40))
	leave.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT,true)
	leave.pressed.connect(func(): leave_requested.emit())
	var hints := _ui._label(match_ui,"MOUSE  Aim   LMB  Draw / diagonal cut   WHEEL UP  Stab   WHEEL DOWN  Overhead   Q / E  Step   HOLD T  Throw   1-5  Gear   TAB  Swap   6 / 7  Consumables   SHIFT + SPACE  Roll   SHIFT + 1 / 2 / 3  Skills   I  Inventory   P  Equipment",Vector2(-610,-25),11,UI.CREAM)
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

func flash_status(message: String, seconds: float = 2.0) -> void:
	if toast_label == null:
		return
	toast_label.text = message
	_toast_time = seconds

func update_match(state: Dictionary) -> void:
	var lines := PackedStringArray()
	for row: Dictionary in state.players:
		var prefix := "> " if int(row.slot) == int(state.local_slot) else "   "
		lines.append("%s%s [%s]   %d / %d" % [prefix,str(row.name).left(12),"BOT" if row.bot else "P",int(row.kills),int(row.deaths)])
	roster.text = "\n".join(lines)
	health_label.text = "HEALTH  %d / %d   /   %s" % [int(state.health),int(round(float(state.get("max_health",100.0)))),str(state.movement)]
	var drawing: bool = state.phase in ["DRAWING","HOLDING"]
	var throwing: bool = state.phase in ["T_DRAW","T_HOLD"]
	var left_melee := float(state.get("left_melee",1.0))
	var right_melee := float(state.get("right_melee",1.0))
	var consume_time := float(state.get("phase_time",0.0))
	var ability_state: Dictionary = state.get("ability",{})
	var off_ability_state: Dictionary = state.get("ability_off",{})
	var trinket_ability_state: Dictionary = state.get("ability_trinket",{})
	_ability_slot.update_state(ability_state)
	if is_instance_valid(_off_ability_slot):
		_off_ability_slot.update_state(off_ability_state)
	if is_instance_valid(_trinket_ability_slot):
		_trinket_ability_slot.update_state(trinket_ability_state)
	if state.phase == "ABILITY":
		var charge_ratio := 0.0
		var active_state := ability_state
		if active_state.is_empty() or not bool(active_state.get("active", false)):
			active_state = off_ability_state
		if active_state.is_empty() or not bool(active_state.get("active", false)):
			active_state = trinket_ability_state
		if not active_state.is_empty():
			charge_ratio = clampf(float(active_state.get("elapsed",0.0))/maxf(float(active_state.get("duration",1.0)),0.001),0.0,1.0)
		attack_label.text = "%s  %d%%  /  %s" % [str(active_state.get("name", "SKILL")), int(charge_ratio * 100.0), str(active_state.get("key", ""))]
	elif state.phase == "BANDAGE":
		attack_label.text = "WRAPPING BANDAGE  %d%%  /  STAND STILL" % int(clampf(consume_time/3.0,0.0,1.0)*100.0)
	elif state.phase == "DRINK":
		attack_label.text = "DRINKING POTION  %d%%" % int(clampf(consume_time/0.5,0.0,1.0)*100.0)
	elif state.weapon == "dual" and (left_melee < 0.999999 or right_melee < 0.999999):
		attack_label.text = "DUAL  /  LEFT %s  /  RIGHT %s" % [_melee_pct(left_melee),_melee_pct(right_melee)]
		if state.get("attack_parry",false):
			attack_label.text += "  /  ATTACK PARRY"
	elif drawing:
		attack_label.text = "DRAW %.0f%% / DAMAGE x%.2f / RELEASE TO FIRE" % [float(state.draw)*100,float(state.draw)]
	elif throwing:
		attack_label.text = "THROW %.0f%% / DAMAGE x%.2f / RELEASE TO THROW" % [float(state.draw)*100,float(state.draw)]
	elif str(state.phase).begins_with("MELEE"):
		if state.weapon == "dual":
			attack_label.text = ("LEFT DIAGONAL CUT / %.2f s" if state.phase == "MELEE_L" else "RIGHT ATTACK / %.2f s") % float(state.attack_interval)
			if state.get("attack_parry",false):
				attack_label.text += "  /  ATTACK PARRY"
		elif state.phase == "MELEE_ST":
			attack_label.text = "FORWARD STAB / %.2f s SWING" % float(state.attack_interval)
		elif state.phase == "MELEE_DL":
			attack_label.text = "LEFT DIAGONAL CUT / %.2f s" % float(state.attack_interval)
		elif state.phase == "MELEE_DR":
			attack_label.text = "RIGHT DIAGONAL CUT / %.2f s" % float(state.attack_interval)
		else:
			attack_label.text = "OVERHEAD CHOP / %.1f s SWING" % float(state.attack_interval)
	elif state.get("blocking",false):
		if state.get("shield",false):
			attack_label.text = "SHIELD UP / FRONT ARROWS STOP"
		elif state.weapon == "dagger":
			attack_label.text = "WEAK GUARD / DAGGER ONLY SOFTENS THE HIT"
		else:
			attack_label.text = "PARRY WINDOW / COUNTER NOW" if state.get("parry",false) else "GUARDING / HOLD RMB"
	elif state.phase in ["RELEASE", "RECOVER"]:
		attack_label.text = "NOCKING NEXT ARROW / %.1f s" % [(1.0-float(state.attack_progress))*float(state.attack_interval)]
	elif state.phase in ["T_RELEASE", "T_RECOVER"]:
		attack_label.text = "THROW RECOVERY %.1f s" % [(1.0-float(state.attack_progress))*float(state.attack_interval)]
	elif float(state.attack_progress) < 0.999999:
		attack_label.text = "RECOVERY %.1f s" % [(1.0-float(state.attack_progress))*float(state.attack_interval)]
	else:
		if state.weapon == "dual":
			attack_label.text = "DUAL WIELD / LMB LEFT CUT / RMB RIGHT CUT / NO GUARD"
		elif state.weapon == "bow":
			attack_label.text = "READY / HOLD LMB, AIM, RELEASE"
		elif state.weapon == "none":
			attack_label.text = "UNARMED / PRESS P TO EQUIP"
		else:
			attack_label.text = "READY / LMB DIAGONAL BY SHOULDER / WHEEL UP STAB / WHEEL DOWN OVERHEAD"
	if state.phase == "ABILITY":
		var charge_ratio := 0.0
		if not ability_state.is_empty():
			charge_ratio = clampf(float(ability_state.get("elapsed",0.0))/maxf(float(ability_state.get("duration",1.0)),0.001),0.0,1.0)
		bar.value = charge_ratio * 100.0
	elif state.phase == "BANDAGE":
		bar.value = clampf(consume_time/3.0,0.0,1.0) * 100.0
	elif state.phase == "DRINK":
		bar.value = clampf(consume_time/0.5,0.0,1.0) * 100.0
	else:
		bar.value = float(state.draw if (drawing or throwing) else state.attack_progress) * 100.0
	respawn_label.text = "RESPAWNING IN %.1f" % float(state.respawn) if float(state.respawn) > 0 else ""
	_armor_pieces = ArmorData.unpack(int(state.armor) & ArmorData.PIECE_MASK)
	for index in ArmorData.SLOTS.size():
		var slot: String = ArmorData.SLOTS[index]
		armor_buttons[index].text = "%s\n%s" % [ArmorData.slot_label(slot).to_upper().left(5),ArmorData.set_abbreviation(int(_armor_pieces.get(slot,0)))]
	for index in 3:
		bow_buttons[index].set_pressed_no_signal(index == int(state.bow))
		sword_buttons[index].set_pressed_no_signal(index == int(state.sword))
	weapon_buttons[0].set_pressed_no_signal(state.weapon == "bow")
	weapon_buttons[1].set_pressed_no_signal(state.weapon == "sword")
	weapon_buttons[2].set_pressed_no_signal(state.weapon == "dagger")
	dual_button.set_pressed_no_signal(state.weapon == "dual")
	dual_button.disabled = int(state.sword) == 2
	var shield_allowed: bool = state.weapon == "dagger" or (state.weapon == "sword" and int(state.sword) <= 1)
	shield_button.set_pressed_no_signal(bool(state.get("shield",false)))
	shield_button.disabled = not shield_allowed

func _cycle_armor(slot: String) -> void:
	var next := (int(_armor_pieces.get(slot,0)) + 1) % ArmorData.SET_IDS.size()
	armor_selected.emit(slot,next)

func _melee_pct(value: float) -> String:
	return "READY" if value >= 0.999999 else "%d%%" % int(value*100.0)

func update_cover(active: bool, low: bool, peeking: bool, side: int, crouched: bool, sliding: bool) -> void:
	var stance := "SLIDING" if sliding else "CROUCHED" if crouched else "OPEN"
	if active:
		if peeking:
			stance = "TOP LOOKOUT" if low else "LEFT LOOKOUT" if side < 0 else "RIGHT LOOKOUT"
		else:
			stance = ("LOW COVER" if low else "TALL COVER") + (" / CROUCHED" if crouched else " / TUCKED")
	_cover_status.text = stance if active and peeking else stance + (" / LEFT SHOULDER" if side < 0 else " / RIGHT SHOULDER")
	_cover_status.add_theme_color_override("font_color", UI.TEAL if active and peeking else UI.GOLD if active else UI.MUTED)

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time = maxf(_toast_time - delta, 0.0)
		if _toast_time == 0.0 and toast_label != null:
			toast_label.text = ""
	queue_redraw()

func _draw() -> void:
	if reticle_visible and not lobby.visible:
		for axis in UI.CROSSHAIR_AXES:
			draw_line(reticle+axis*5,reticle+axis*13,Color(0.04,0.09,0.10,0.85),3.5,true)
			draw_line(reticle+axis*5,reticle+axis*13,Color.WHITE,1.25,true)
		draw_circle(reticle,1.5,Color.WHITE)
