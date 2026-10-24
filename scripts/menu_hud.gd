extends Control
## Hub interface: equipment paperdoll, backpack, floor, stash, vendors and every
## way to leave the Hollow. This panel is read-only over PlayerState; every
## mutation is a signal handled by menu.gd.

signal mode_selected(mode: String)
signal host_confirmed(port: int, player_name: String)
signal join_confirmed(address: String, port: int, player_name: String)
signal delve_host_confirmed(port: int, player_name: String)
signal delve_join_confirmed(address: String, port: int, player_name: String)
signal buy_requested(item_id: String)
signal equip_requested(index: int, target_slot: String)
signal unequip_requested(slot: String)
signal move_equipped_requested(from_slot: String, to_slot: String)
signal drop_requested(area: String, key)
signal floor_pickup_requested(index: int)
signal stash_requested(index: int)
signal unstash_requested(index: int)
signal sell_requested(location: String, index: int)
signal close_requested

const StateScript = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const SlotScript = preload("res://scripts/inventory_slot.gd")
const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")
const SLOT_FONT := 11

## Catches a drop anywhere the panels do not already own it, so releasing gear
## over the 3D view drops it at the ranger's feet. It only listens while a drag
## is in flight; otherwise the camera keeps every mouse event.
class DropCatcher:
	extends Control

	signal dropped(payload: Dictionary)

	var active := false

	func begin() -> void:
		active = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	func finish() -> void:
		active = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return active and data is Dictionary and data.has("area")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		finish()
		if data is Dictionary:
			dropped.emit(data)

var state
var session
var header_panel: Panel
var purse_panel: Panel
var paperdoll_panel: Panel
var backpack_panel: Panel
var stash_panel: Panel
var vendor_panel: Panel
var action_panel: Panel
var skirmish_button: Button
var host_button: Button
var join_button: Button
var frontier_button: Button
var delve_button: Button
var delve_host_button: Button
var delve_join_button: Button
var paperdoll_buttons: Array[InventorySlot] = []
var backpack_buttons: Array[InventorySlot] = []
var floor_buttons: Array[InventorySlot] = []
var stash_buttons: Array[InventorySlot] = []
var stock_buttons: Array[InventorySlot] = []
var vendor_buttons: Array[Button] = []
var stock_scroll: ScrollContainer
var stock_list: VBoxContainer
var floor_scroll: ScrollContainer
var floor_list: HBoxContainer
var _backpack_count: Label
var _floor_label: Label
var _stash_count: Label
var _credits: Label
var _status: Label
var _detail_header: Label
var _detail_meta: Label
var _detail_text: Label
var _detail_hint: Label
var equip_button: Button
var move_button: Button
var sell_button: Button
var drop_button: Button
var _vendor_name: Label
var _vendor_tag: Label
var _stock_header: Label
var _stock_meta: Label
var _stock_text: Label
var buy_button: Button
var _modal_layer: Control
var _modal_panel: Panel
var _modal_title: Label
var _modal_hint: Label
var _name_label: Label
var _name_input: LineEdit
var _address_label: Label
var _address_input: LineEdit
var _port_label: Label
var _port_input: SpinBox
var _form_error: Label
var _confirm_button: Button
var _cancel_button: Button
var _drop_catcher: DropCatcher
var _drag_seen := false
var _drag_idle_frames := 0
var _modal_kind := ""
var _location := ""
var _index := -1
var _slot := ""
var _stock_item := ""
var _vendor := 0
var _default_name := "Ranger"
var _default_address := "127.0.0.1"
var _default_port := 7777
var field_mode := false
var close_button: Button
var _dim: ColorRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _build_theme()
	_build_drop_catcher()
	_build_dim()
	_build_header()
	_build_paperdoll()
	_build_backpack()
	_build_stash()
	_build_vendors()
	_build_actions()
	_build_status()
	_build_modal()
	_apply_field_mode()

func _process(_delta: float) -> void:
	# A cancelled drag never reaches a drop handler; clear the catcher once the
	# viewport stops dragging so the camera gets the mouse back.
	if _drop_catcher == null or not _drop_catcher.active:
		return
	if get_viewport().gui_is_dragging():
		_drag_seen = true
		_drag_idle_frames = 0
	elif _drag_seen or _drag_idle_frames >= 2:
		_reset_drag()
	else:
		_drag_idle_frames += 1

func configure(player_state, session_state, field := false) -> void:
	state = player_state
	session = session_state
	field_mode = field
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		_default_name = str(cache.player_name)
		_default_address = str(cache.address)
		_default_port = int(cache.port)
	elif session != null:
		_default_name = str(session.player_name)
	_apply_field_mode()
	refresh()

## Field mode shows only the paperdoll, backpack, inspector and status over a
## dim backdrop; the helper that owns this layer drives open/close.
func _apply_field_mode() -> void:
	if _dim == null:
		return
	_dim.visible = field_mode
	var hub_panels: Array = [header_panel,purse_panel,stash_panel,vendor_panel,action_panel]
	for panel in hub_panels:
		if panel != null:
			panel.visible = not field_mode
	if _floor_label != null:
		_floor_label.visible = not field_mode
	if floor_scroll != null:
		floor_scroll.visible = not field_mode
	if close_button != null:
		close_button.visible = field_mode
	if field_mode and _modal_layer != null:
		_modal_layer.visible = false
		_modal_kind = ""

func _build_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI"])
	result.default_font = font
	result.default_font_size = 15
	result.set_color("font_color", "Label", CREAM)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Color("13282f"))
	result.set_color("font_disabled_color", "Button", MUTED)
	result.set_stylebox("normal", "Button", _style(Color("243a40"),Color("456068"),6))
	result.set_stylebox("hover", "Button", _style(Color("34545b"),GOLD,6))
	result.set_stylebox("pressed", "Button", _style(GOLD,GOLD,6))
	result.set_stylebox("disabled", "Button", _style(Color("1b2b30"),Color("33484e"),6))
	return result

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	return result

func _panel(parent: Node, position_at: Vector2, size_at: Vector2) -> Panel:
	var result := Panel.new()
	result.position = position_at
	result.size = size_at
	result.add_theme_stylebox_override("panel", _style(Color(0.038,0.078,0.096,0.94),Color("3f5b60"),8))
	parent.add_child(result)
	return result

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

func _new_slot(parent: Node, area: String, index: int, slot_name: String, position_at: Vector2, size_at: Vector2, font_size: int) -> InventorySlot:
	var result := SlotScript.new()
	result.position = position_at
	result.size = size_at
	result.custom_minimum_size = size_at
	result.toggle_mode = true
	result.focus_mode = Control.FOCUS_NONE
	result.clip_text = true
	result.add_theme_font_size_override("font_size",font_size)
	result.drag_enabled = area != "stock"
	result.configure(area,index,slot_name,"")
	result.right_clicked.connect(_on_slot_right_clicked)
	result.slot_dropped.connect(_on_slot_dropped.bind(area,index,slot_name))
	result.drag_started.connect(_on_drag_started)
	result.tooltip_builder = _build_item_tooltip
	parent.add_child(result)
	return result

func _build_drop_catcher() -> void:
	_drop_catcher = DropCatcher.new()
	add_child(_drop_catcher)
	_drop_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_catcher.dropped.connect(_on_world_dropped)

func _build_dim() -> void:
	# Sits under every panel, so field mode dims the game behind the overlay and
	# keeps stray clicks away from the world. Hub mode leaves it hidden.
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.015,0.035,0.045,0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

func _build_header() -> void:
	header_panel = _panel(self,Vector2(24,22),Vector2(432,92))
	_label(header_panel,"IRONWOOD",Vector2(18,6),30,CREAM)
	_label(header_panel,"THE HOLLOW  /  STAGING DEPOT",Vector2(19,48),14,GOLD)
	_label(header_panel,"DRAG TO ORBIT  •  WHEEL TO ZOOM",Vector2(19,70),11,MUTED)
	purse_panel = _panel(self,Vector2(-320,22),Vector2(296,92))
	purse_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT,true)
	_label(purse_panel,"RANGER'S PURSE",Vector2(16,10),11,GOLD)
	_credits = _label(purse_panel,"0 c",Vector2(16,28),30,CREAM)
	_label(purse_panel,"Earned in the frontier, spent here.",Vector2(16,68),11,MUTED)

func _build_paperdoll() -> void:
	paperdoll_panel = _panel(self,Vector2(24,126),Vector2(404,412))
	var panel := paperdoll_panel
	_label(panel,"EQUIPPED KIT",Vector2(16,10),12,GOLD)
	close_button = _button(panel,"CLOSE / I",Vector2(300,4),Vector2(88,24))
	close_button.add_theme_font_size_override("font_size",11)
	close_button.tooltip_text = "Close the field kit."
	close_button.pressed.connect(func(): close_requested.emit())
	close_button.visible = false
	var hint := _label(panel,"Drag gear onto a slot to equip  •  right-click to unequip",Vector2(16,30),10,MUTED)
	hint.size = Vector2(372,12)
	hint.clip_text = true
	for index in Rules.SLOTS.size():
		var slot_name: String = Rules.SLOTS[index]
		var column := index / 5
		var row := index % 5
		var button := _new_slot(panel,"paperdoll",-1,slot_name,Vector2(16+column*188,44+row*36),Vector2(182,34),SLOT_FONT)
		button.pressed.connect(_on_paperdoll_slot.bind(slot_name))
		paperdoll_buttons.append(button)
	_label(panel,"SELECTED",Vector2(16,228),10,MUTED)
	_detail_header = _label(panel,"Nothing selected",Vector2(16,244),16,CREAM)
	_detail_header.size = Vector2(372,22)
	_detail_header.clip_text = true
	_detail_meta = _label(panel,"",Vector2(16,268),11,TEAL)
	_detail_meta.size = Vector2(372,18)
	_detail_meta.clip_text = true
	_detail_text = _label(panel,"",Vector2(16,288),11,MUTED)
	_detail_text.size = Vector2(372,48)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equip_button = _button(panel,"EQUIP",Vector2(16,338),Vector2(182,26))
	equip_button.add_theme_font_size_override("font_size",12)
	equip_button.pressed.connect(_on_equip)
	move_button = _button(panel,"TO STASH",Vector2(204,338),Vector2(182,26))
	move_button.add_theme_font_size_override("font_size",12)
	move_button.pressed.connect(_on_move)
	sell_button = _button(panel,"SELL",Vector2(16,368),Vector2(182,26))
	sell_button.add_theme_font_size_override("font_size",12)
	sell_button.pressed.connect(_on_sell)
	drop_button = _button(panel,"DROP",Vector2(204,368),Vector2(182,26))
	drop_button.add_theme_font_size_override("font_size",12)
	drop_button.pressed.connect(_on_drop)
	_detail_hint = _label(panel,"",Vector2(16,396),10,MUTED)
	_detail_hint.size = Vector2(372,14)
	_detail_hint.clip_text = true

func _build_backpack() -> void:
	backpack_panel = _panel(self,Vector2(24,550),Vector2(404,172))
	var panel := backpack_panel
	_label(panel,"BACKPACK",Vector2(16,10),12,GOLD)
	_backpack_count = _label(panel,"",Vector2(200,10),12,CREAM)
	_backpack_count.size = Vector2(188,18)
	_backpack_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in 10:
		var column := index % 5
		var row := index / 5
		var button := _new_slot(panel,"backpack",index,"",Vector2(16+column*72,34+row*42),Vector2(68,36),10)
		button.pressed.connect(_on_backpack_slot.bind(index))
		backpack_buttons.append(button)
	_floor_label = _label(panel,"FLOOR  •  nothing dropped",Vector2(16,120),10,MUTED)
	_floor_label.size = Vector2(372,14)
	_floor_label.clip_text = true
	floor_scroll = ScrollContainer.new()
	floor_scroll.position = Vector2(16,138)
	floor_scroll.size = Vector2(372,30)
	floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	floor_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(floor_scroll)
	floor_list = HBoxContainer.new()
	floor_list.add_theme_constant_override("separation",4)
	floor_scroll.add_child(floor_list)

func _build_stash() -> void:
	stash_panel = _panel(self,Vector2(24,-170),Vector2(620,146))
	var panel := stash_panel
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT,true)
	_label(panel,"STASH",Vector2(16,12),12,GOLD)
	_stash_count = _label(panel,"",Vector2(444,12),12,CREAM)
	_stash_count.size = Vector2(160,20)
	_stash_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in 20:
		var column := index % 10
		var row := index / 10
		var button := _new_slot(panel,"stash",index,"",Vector2(16+column*60,42+row*44),Vector2(55,38),10)
		button.pressed.connect(_on_stash_slot.bind(index))
		stash_buttons.append(button)

func _build_vendors() -> void:
	vendor_panel = _panel(self,Vector2(-404,126),Vector2(380,420))
	var panel := vendor_panel
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT,true)
	_label(panel,"VENDORS",Vector2(16,12),12,GOLD)
	for index in 3:
		var button := _button(panel,str(StateScript.VENDORS[index].tag),Vector2(14+index*120,38),Vector2(112,30))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",10)
		button.pressed.connect(_on_vendor_tab.bind(index))
		vendor_buttons.append(button)
	_vendor_name = _label(panel,"",Vector2(16,78),15,CREAM)
	_vendor_tag = _label(panel,"",Vector2(16,98),11,MUTED)
	_vendor_tag.size = Vector2(348,26)
	_vendor_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock_scroll = ScrollContainer.new()
	stock_scroll.position = Vector2(16,132)
	stock_scroll.size = Vector2(348,150)
	stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(stock_scroll)
	stock_list = VBoxContainer.new()
	stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_list.add_theme_constant_override("separation",4)
	stock_scroll.add_child(stock_list)
	for index in 28:
		var button := _new_slot(stock_list,"stock",index,"",Vector2.ZERO,Vector2(320,30),12)
		button.custom_minimum_size = Vector2(0,30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.drag_enabled = false
		button.pressed.connect(_on_stock.bind(index))
		stock_buttons.append(button)
	_stock_header = _label(panel,"SELECT A STOCK ITEM",Vector2(16,288),10,MUTED)
	_stock_meta = _label(panel,"",Vector2(16,306),15,CREAM)
	_stock_text = _label(panel,"",Vector2(16,330),11,MUTED)
	_stock_text.size = Vector2(348,32)
	_stock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy_button = _button(panel,"BUY",Vector2(16,364),Vector2(348,34))
	buy_button.pressed.connect(_on_buy)
	_label(panel,"A purchase needs a free backpack slot.",Vector2(16,398),10,MUTED)

func _build_actions() -> void:
	# Two columns share one wide panel: arena and frontier on the left, the
	# Sunken Delve on the right. 600x306 keeps clear of the vendors above and
	# the stash to the left at the 1440x900 design resolution.
	action_panel = _panel(self,Vector2(-624,-324),Vector2(600,306))
	var panel := action_panel
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT,true)
	_label(panel,"DEPLOY",Vector2(18,12),12,GOLD)
	skirmish_button = _button(panel,"ARENA SKIRMISH",Vector2(18,38),Vector2(268,42))
	skirmish_button.pressed.connect(func(): mode_selected.emit("skirmish"))
	_label(panel,"Four seats; bots fill any empty seat.",Vector2(18,86),10,MUTED)
	host_button = _button(panel,"HOST A GAME",Vector2(18,108),Vector2(268,38))
	host_button.pressed.connect(open_host_form)
	join_button = _button(panel,"JOIN A GAME",Vector2(18,152),Vector2(268,38))
	join_button.pressed.connect(open_join_form)
	frontier_button = _button(panel,"ENTER THE FRONTIER  /  OPEN PvE",Vector2(18,202),Vector2(268,44))
	frontier_button.add_theme_font_size_override("font_size",12)
	frontier_button.pressed.connect(func(): mode_selected.emit("pve"))
	_label(panel,"Waystones, wolves and gold await.",Vector2(18,254),10,MUTED)
	_label(panel,"Your equipped kit carries into every mode.",Vector2(18,274),10,MUTED)
	_label(panel,"THE SUNKEN DELVE",Vector2(304,12),12,GOLD)
	delve_button = _button(panel,"DESCEND THE DELVE",Vector2(304,38),Vector2(278,54))
	delve_button.add_theme_font_size_override("font_size",13)
	delve_button.pressed.connect(func(): mode_selected.emit("delve"))
	delve_host_button = _button(panel,"HOST A DELVE",Vector2(304,102),Vector2(134,38))
	delve_host_button.add_theme_font_size_override("font_size",12)
	delve_host_button.pressed.connect(open_delve_host_form)
	delve_join_button = _button(panel,"JOIN A DELVE",Vector2(448,102),Vector2(134,38))
	delve_join_button.add_theme_font_size_override("font_size",12)
	delve_join_button.pressed.connect(open_delve_join_form)
	var delve_hint_one := _label(panel,"Three waves of cinder devils trickle in\nfrom four dark archways. Cleared waves\nleave a cache.",Vector2(304,158),10,MUTED)
	delve_hint_one.size = Vector2(278,48)
	var delve_hint_two := _label(panel,"The gate seals behind you;\ndowned rangers stay down.",Vector2(304,216),10,MUTED)
	delve_hint_two.size = Vector2(278,32)

func set_delve_progress(wave: int, chest_ready: bool) -> void:
	if delve_button == null:
		return
	if wave <= 0:
		delve_button.text = "DESCEND THE DELVE"
	elif chest_ready and wave >= 3:
		delve_button.text = "RESUME THE DELVE  /  FINAL CACHE"
	elif chest_ready:
		delve_button.text = "RESUME THE DELVE  /  WAVE %d CACHE" % wave
	else:
		delve_button.text = "RESUME THE DELVE  /  WAVE %d" % wave

func _build_status() -> void:
	_status = _label(self,"Choose a vendor, move gear, then deploy.",Vector2(-212,30),14,TEAL)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP,true)
	_status.size = Vector2(560,48)
	_status.clip_text = true
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_shadow_color",Color("081418"))
	_status.add_theme_constant_override("shadow_outline_size",4)

func _build_modal() -> void:
	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.visible = false
	add_child(_modal_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015,0.035,0.045,0.78)
	_modal_layer.add_child(dim)
	_modal_panel = _panel(_modal_layer,Vector2(-240,-170),Vector2(480,340))
	_modal_panel.set_anchors_preset(Control.PRESET_CENTER,true)
	_modal_title = _label(_modal_panel,"",Vector2(24,18),22,GOLD)
	_modal_hint = _label(_modal_panel,"",Vector2(24,52),11,MUTED)
	_modal_hint.size = Vector2(432,38)
	_modal_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label = _label(_modal_panel,"YOUR NAME",Vector2(24,96),10,GOLD)
	_name_input = LineEdit.new()
	_name_input.position = Vector2(24,116)
	_name_input.size = Vector2(250,38)
	_name_input.max_length = 16
	_modal_panel.add_child(_name_input)
	_address_label = _label(_modal_panel,"HOST ADDRESS",Vector2(24,160),10,GOLD)
	_address_input = LineEdit.new()
	_address_input.position = Vector2(24,180)
	_address_input.size = Vector2(250,38)
	_modal_panel.add_child(_address_input)
	_port_label = _label(_modal_panel,"UDP PORT",Vector2(300,96),10,GOLD)
	_port_input = SpinBox.new()
	_port_input.position = Vector2(300,116)
	_port_input.size = Vector2(156,38)
	_port_input.min_value = 1024
	_port_input.max_value = 65535
	_port_input.value = 7777
	_modal_panel.add_child(_port_input)
	_confirm_button = _button(_modal_panel,"",Vector2(24,176),Vector2(200,42))
	_confirm_button.pressed.connect(_on_confirm)
	_cancel_button = _button(_modal_panel,"CANCEL",Vector2(236,176),Vector2(140,42))
	_cancel_button.pressed.connect(close_form)
	_form_error = _label(_modal_panel,"",Vector2(24,232),11,WARN)
	_form_error.size = Vector2(432,40)
	_form_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func set_status(message: String) -> void:
	_status.text = message

func is_form_open() -> bool:
	return _modal_layer != null and _modal_layer.visible

func close_form() -> void:
	_modal_kind = ""
	_modal_layer.visible = false

func open_host_form() -> void:
	_modal_kind = "host"
	_modal_title.text = "HOST AN ARENA"
	_modal_hint.text = "Four seats. Share this computer's address and UDP port; empty seats stay bots."
	_name_label.visible = true
	_name_input.visible = true
	_name_input.text = _default_name
	_address_label.visible = false
	_address_input.visible = false
	_port_label.position = Vector2(300,96)
	_port_input.position = Vector2(300,116)
	_confirm_button.position = Vector2(24,176)
	_cancel_button.position = Vector2(236,176)
	_confirm_button.text = "HOST ARENA"
	_form_error.text = ""
	_port_input.value = _default_port
	_modal_layer.visible = true
	_name_input.grab_focus()

func open_join_form() -> void:
	_modal_kind = "join"
	_modal_title.text = "JOIN AN ARENA"
	_modal_hint.text = "Ask the host for the address and UDP port. Tailscale or LAN keeps the route direct."
	_name_label.visible = true
	_name_input.visible = true
	_name_input.text = _default_name
	_address_label.visible = true
	_address_input.visible = true
	_address_input.text = _default_address
	_port_label.position = Vector2(300,160)
	_port_input.position = Vector2(300,180)
	_confirm_button.position = Vector2(24,236)
	_cancel_button.position = Vector2(236,236)
	_confirm_button.text = "JOIN ARENA"
	_form_error.text = ""
	_port_input.value = _default_port
	_modal_layer.visible = true
	_name_input.grab_focus()

func open_delve_host_form() -> void:
	_modal_kind = "delve_host"
	_modal_title.text = "HOST THE SUNKEN DELVE"
	_modal_hint.text = "One sealed chamber, three waves, two cinder devils apiece. Share this address and UDP port with your party."
	_name_label.visible = true
	_name_input.visible = true
	_name_input.text = _default_name
	_address_label.visible = false
	_address_input.visible = false
	_port_label.position = Vector2(300,96)
	_port_input.position = Vector2(300,116)
	_confirm_button.position = Vector2(24,176)
	_cancel_button.position = Vector2(236,176)
	_confirm_button.text = "HOST DELVE"
	_form_error.text = ""
	_port_input.value = _default_port
	_modal_layer.visible = true
	_name_input.grab_focus()

func open_delve_join_form() -> void:
	_modal_kind = "delve_join"
	_modal_title.text = "JOIN THE SUNKEN DELVE"
	_modal_hint.text = "Ask the host for the address and UDP port. The gate seals once the run begins."
	_name_label.visible = true
	_name_input.visible = true
	_name_input.text = _default_name
	_address_label.visible = true
	_address_input.visible = true
	_address_input.text = _default_address
	_port_label.position = Vector2(300,160)
	_port_input.position = Vector2(300,180)
	_confirm_button.position = Vector2(24,236)
	_cancel_button.position = Vector2(236,236)
	_confirm_button.text = "JOIN DELVE"
	_form_error.text = ""
	_port_input.value = _default_port
	_modal_layer.visible = true
	_name_input.grab_focus()

func _on_confirm() -> void:
	var clean_name := _name_input.text.strip_edges().left(16)
	if clean_name.is_empty():
		clean_name = "Ranger"
	if _modal_kind == "host":
		var host_port := int(_port_input.value)
		if host_port < 1024 or host_port > 65535:
			_form_error.text = "Choose a UDP port between 1024 and 65535."
			return
		close_form()
		host_confirmed.emit(host_port,clean_name)
	elif _modal_kind == "join":
		var address := _address_input.text.strip_edges()
		if address.is_empty():
			_form_error.text = "Enter the host's address."
			return
		close_form()
		join_confirmed.emit(address,int(_port_input.value),clean_name)
	elif _modal_kind == "delve_host":
		var delve_port := int(_port_input.value)
		if delve_port < 1024 or delve_port > 65535:
			_form_error.text = "Choose a UDP port between 1024 and 65535."
			return
		close_form()
		delve_host_confirmed.emit(delve_port,clean_name)
	elif _modal_kind == "delve_join":
		var delve_address := _address_input.text.strip_edges()
		if delve_address.is_empty():
			_form_error.text = "Enter the host's address."
			return
		close_form()
		delve_join_confirmed.emit(delve_address,int(_port_input.value),clean_name)

func refresh() -> void:
	if state == null or _credits == null:
		return
	_credits.text = "%d c" % int(state.credits)
	_backpack_count.text = "%d / %d" % [state.inventory.size(),state.INVENTORY_CAPACITY]
	_stash_count.text = "%d / %d" % [state.stash.size(),state.STASH_CAPACITY]
	_refresh_paperdoll()
	_refresh_backpack()
	_refresh_stash()
	_refresh_floor()
	_refresh_vendor()
	_refresh_selection()

func _refresh_paperdoll() -> void:
	for index in paperdoll_buttons.size():
		var button := paperdoll_buttons[index]
		var slot_name: String = Rules.SLOTS[index]
		var item_id: String = state.equipped_id(slot_name)
		button.item = item_id
		button.index = -1
		button.slot = slot_name
		var label := str(Rules.SLOT_LABELS.get(slot_name,slot_name))
		if item_id.is_empty():
			button.text = "%s  •  EMPTY" % label.to_upper()
			button.tooltip_text = "%s — nothing equipped" % label
		else:
			button.text = "%s  •  %s" % [label.to_upper(),state.item_short(item_id)]
			button.tooltip_text = state.item_name(item_id)
		button.set_pressed_no_signal(_location == "paperdoll" and _slot == slot_name)

func _refresh_backpack() -> void:
	for index in backpack_buttons.size():
		var button := backpack_buttons[index]
		button.index = index
		button.slot = ""
		if index < state.inventory.size():
			var item_id: String = state.inventory[index]
			button.item = item_id
			button.text = state.item_short(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.item = ""
			button.text = "—"
			button.tooltip_text = "Empty backpack slot"
		button.set_pressed_no_signal(_location == "backpack" and index == _index)

func _refresh_stash() -> void:
	for index in stash_buttons.size():
		var button := stash_buttons[index]
		if index < state.stash.size():
			var item_id: String = state.stash[index]
			button.item = item_id
			button.index = index
			button.text = state.item_short(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.item = ""
			button.text = ""
			button.tooltip_text = ""
		button.set_pressed_no_signal(_location == "stash" and index == _index)

func _refresh_floor() -> void:
	for child in floor_list.get_children():
		floor_list.remove_child(child)
		child.queue_free()
	floor_buttons.clear()
	var items: Array = state.floor_items
	if items.is_empty():
		_floor_label.text = "FLOOR  •  nothing dropped"
	else:
		_floor_label.text = "FLOOR  •  %d  •  drag gear onto the ranger to drop" % items.size()
	for index in items.size():
		var item_id: String = items[index]
		var button := _new_slot(floor_list,"floor",index,"",Vector2.ZERO,Vector2(64,28),10)
		button.custom_minimum_size = Vector2(64,28)
		button.item = item_id
		button.text = state.item_short(item_id)
		button.tooltip_text = state.item_name(item_id)
		button.pressed.connect(_on_floor_slot.bind(index))
		button.set_pressed_no_signal(_location == "floor" and index == _index)
		floor_buttons.append(button)

func _refresh_vendor() -> void:
	var vendors: Array = StateScript.VENDORS
	var vendor: Dictionary = vendors[_vendor]
	_vendor_name.text = str(vendor.name)
	_vendor_tag.text = str(vendor.line)
	for index in vendor_buttons.size():
		vendor_buttons[index].set_pressed_no_signal(index == _vendor)
	var stock: Array = vendor.stock
	for index in stock_buttons.size():
		var button := stock_buttons[index]
		if index < stock.size():
			var item_id: String = stock[index]
			button.visible = true
			button.disabled = false
			button.item = item_id
			button.text = "%s%s   %d c" % ["* " if state.is_equipped(item_id) else "",state.item_name(item_id),state.item_price(item_id)]
			button.set_pressed_no_signal(_location == "stock" and _stock_item == item_id)
		else:
			button.visible = false
			button.disabled = true
			button.item = ""
			button.text = ""
	if _location == "stock" and not _stock_item.is_empty():
		var category := str(state.item_category(_stock_item)).to_upper()
		if category.is_empty():
			category = state.item_kind(_stock_item).to_upper()
		_stock_header.text = "STOCKED  /  " + category
		_stock_meta.text = state.item_name(_stock_item)
		var owned: int = state.owned_in_inventory(_stock_item) + state.owned_in_stash(_stock_item) + (1 if state.is_equipped(_stock_item) else 0)
		_stock_text.text = "%s\nYou own %d.  %d credits." % [state.item_detail(_stock_item),owned,state.item_price(_stock_item)]
	else:
		_stock_header.text = "SELECT A STOCK ITEM"
		_stock_meta.text = ""
		_stock_text.text = ""

func _refresh_selection() -> void:
	var item_id := _selected_item()
	var on_backpack := _location == "backpack"
	var on_paperdoll := _location == "paperdoll"
	var on_stash := _location == "stash"
	var on_floor := _location == "floor"
	equip_button.visible = on_backpack or on_paperdoll or on_floor
	move_button.visible = on_backpack or on_stash
	sell_button.visible = on_backpack or on_stash
	drop_button.visible = on_backpack or on_paperdoll
	buy_button.visible = _location == "stock" and not _stock_item.is_empty()
	if field_mode:
		# The field kit only equips, unequips, drops and picks up; stashing and
		# selling stay in the Hollow.
		move_button.visible = false
		sell_button.visible = false
		buy_button.visible = false
	if buy_button.visible:
		buy_button.disabled = state.inventory_full() or int(state.credits) < state.item_price(_stock_item)
		buy_button.text = "BUY  /  %d c" % state.item_price(_stock_item)
		buy_button.tooltip_text = "Backpack is full." if state.inventory_full() else "Not enough credits." if int(state.credits) < state.item_price(_stock_item) else ""
	if item_id.is_empty():
		_detail_header.text = "Nothing selected"
		_detail_meta.text = ""
		_detail_text.text = ""
		equip_button.disabled = true
		move_button.disabled = true
		sell_button.disabled = true
		drop_button.disabled = true
		_detail_hint.text = "Click a slot to inspect it."
		return
	_detail_header.text = state.item_name(item_id)
	var equipped: bool = state.is_equipped(item_id)
	# Only the paperdoll and the vendor stock mark a piece as equipped; a spare
	# copy sitting in the backpack is just stock on the shelf.
	var equipped_here := equipped and (on_paperdoll or _location == "stock")
	var meta: String = state.item_type_line(item_id)
	var compact: String = state.item_compact_stats(item_id)
	if not compact.is_empty():
		meta += "  •  " + compact
	if equipped_here:
		meta += "  •  EQUIPPED"
	_detail_meta.text = meta
	_detail_meta.add_theme_color_override("font_color",TEAL if equipped_here else GOLD)
	var quote: String = state.item_quote(item_id)
	if quote.is_empty():
		_detail_text.text = state.item_summary(item_id)
	else:
		_detail_text.text = "%s\n“%s”" % [state.item_summary(item_id),quote]
	equip_button.disabled = false
	move_button.disabled = false
	sell_button.disabled = false
	drop_button.disabled = false
	if on_backpack:
		equip_button.text = "EQUIP"
		equip_button.tooltip_text = "Right-click equips automatically; Alt+right-click takes the off-hand."
		move_button.text = "TO STASH"
		move_button.disabled = state.stash_full()
		move_button.tooltip_text = "Stash is full." if state.stash_full() else ""
		sell_button.text = "SELL"
		sell_button.tooltip_text = "Sell value %d credits." % state.sell_value(item_id)
		drop_button.text = "DROP"
		drop_button.tooltip_text = "Drop at the ranger's feet."
		_detail_hint.text = "Right-click equips  •  Alt+right-click equips the off-hand."
	elif on_paperdoll:
		equip_button.text = "UNEQUIP"
		equip_button.tooltip_text = "Return this piece to the backpack."
		move_button.visible = false
		sell_button.visible = false
		drop_button.text = "DROP"
		drop_button.tooltip_text = "Drop at the ranger's feet."
		_detail_hint.text = "Right-click or UNEQUIP returns it to the backpack."
	elif on_stash:
		equip_button.visible = false
		move_button.text = "TO INVENTORY"
		move_button.disabled = state.inventory_full()
		move_button.tooltip_text = "Backpack is full." if state.inventory_full() else ""
		sell_button.text = "SELL"
		sell_button.tooltip_text = "Sell value %d credits." % state.sell_value(item_id)
		_detail_hint.text = "Sell value %d credits." % state.sell_value(item_id)
	elif on_floor:
		equip_button.text = "PICK UP"
		equip_button.disabled = state.inventory_full()
		equip_button.tooltip_text = "Backpack is full." if state.inventory_full() else "Return this item to the backpack."
		move_button.visible = false
		sell_button.visible = false
		drop_button.visible = false
		_detail_hint.text = "Dropped items wait at the ranger's feet."
	else:
		# Vendor stock selection.
		_detail_hint.text = "Sell value %d credits." % state.sell_value(item_id)

func clear_selection() -> void:
	_location = ""
	_index = -1
	_slot = ""
	_stock_item = ""

func _selected_item() -> String:
	if state == null:
		return ""
	match _location:
		"backpack":
			if _index >= 0 and _index < state.inventory.size():
				return state.inventory[_index]
		"stash":
			if _index >= 0 and _index < state.stash.size():
				return state.stash[_index]
		"paperdoll":
			if not _slot.is_empty():
				return state.equipped_id(_slot)
		"floor":
			if _index >= 0 and _index < state.floor_items.size():
				return state.floor_items[_index]
		"stock":
			return _stock_item
	return ""

func _on_paperdoll_slot(slot_name: String) -> void:
	if state == null:
		return
	var item_id: String = state.equipped_id(slot_name)
	if item_id.is_empty():
		clear_selection()
		refresh()
		return
	_location = "paperdoll"
	_slot = slot_name
	_index = -1
	_stock_item = ""
	refresh()

func _on_backpack_slot(index: int) -> void:
	if state == null or index >= state.inventory.size():
		return
	_location = "backpack"
	_index = index
	_slot = ""
	_stock_item = ""
	refresh()

func _on_floor_slot(index: int) -> void:
	if state == null or index >= state.floor_items.size():
		return
	_location = "floor"
	_index = index
	_slot = ""
	_stock_item = ""
	refresh()

func _on_stash_slot(index: int) -> void:
	if state == null or index >= state.stash.size():
		return
	_location = "stash"
	_index = index
	_slot = ""
	_stock_item = ""
	refresh()

func _on_vendor_tab(index: int) -> void:
	_vendor = index
	if _location == "stock":
		_location = ""
		_stock_item = ""
	if stock_scroll != null:
		stock_scroll.scroll_vertical = 0
	refresh()

func _on_stock(index: int) -> void:
	if state == null:
		return
	var stock: Array = StateScript.VENDORS[_vendor].stock
	if index >= stock.size():
		return
	_location = "stock"
	_stock_item = stock[index]
	_index = -1
	_slot = ""
	refresh()

func _on_slot_right_clicked(area: String, index: int, slot_name: String, item_id: String) -> void:
	if item_id.is_empty():
		return
	match area:
		"backpack":
			equip_requested.emit(index,"off" if Input.is_key_pressed(KEY_ALT) else "")
		"paperdoll":
			unequip_requested.emit(slot_name)
		"stash":
			unstash_requested.emit(index)
		"floor":
			floor_pickup_requested.emit(index)
		"stock":
			_on_stock(index)

func _on_slot_dropped(payload: Dictionary, to_area: String, _to_index: int, to_slot: String) -> void:
	_reset_drag()
	var from_area := str(payload.get("area",""))
	var from_index := int(payload.get("index",-1))
	var from_slot := str(payload.get("slot",""))
	var item_id := str(payload.get("item",""))
	if item_id.is_empty() or from_area.is_empty():
		return
	match from_area:
		"backpack":
			if to_area == "paperdoll":
				equip_requested.emit(from_index,to_slot)
			elif to_area == "stash":
				stash_requested.emit(from_index)
			elif to_area == "floor":
				drop_requested.emit("backpack",from_index)
		"paperdoll":
			if to_area == "paperdoll" and from_slot != to_slot:
				move_equipped_requested.emit(from_slot,to_slot)
			elif to_area == "floor":
				drop_requested.emit("paperdoll",from_slot)
		"stash":
			if to_area == "backpack":
				unstash_requested.emit(from_index)
		"floor":
			if to_area == "backpack":
				floor_pickup_requested.emit(from_index)

func _on_world_dropped(payload: Dictionary) -> void:
	_reset_drag()
	var from_area := str(payload.get("area",""))
	if str(payload.get("item","")).is_empty():
		return
	match from_area:
		"backpack":
			drop_requested.emit("backpack",int(payload.get("index",-1)))
		"paperdoll":
			drop_requested.emit("paperdoll",str(payload.get("slot","")))

func _on_drag_started() -> void:
	_drag_seen = false
	_drag_idle_frames = 0
	if _drop_catcher != null and not field_mode:
		_drop_catcher.begin()

func _reset_drag() -> void:
	_drag_seen = false
	_drag_idle_frames = 0
	if _drop_catcher != null:
		_drop_catcher.finish()

func _on_equip() -> void:
	match _location:
		"backpack":
			equip_requested.emit(_index,"")
		"paperdoll":
			unequip_requested.emit(_slot)
		"floor":
			floor_pickup_requested.emit(_index)

func _on_move() -> void:
	if _location == "backpack":
		stash_requested.emit(_index)
	elif _location == "stash":
		unstash_requested.emit(_index)

func _on_sell() -> void:
	if _location == "backpack" or _location == "stash":
		sell_requested.emit(_location,_index)

func _on_drop() -> void:
	match _location:
		"backpack":
			drop_requested.emit("backpack",_index)
		"paperdoll":
			drop_requested.emit("paperdoll",_slot)

func _on_buy() -> void:
	if _location == "stock" and not _stock_item.is_empty():
		buy_requested.emit(_stock_item)

## Hover card for any inventory slot. The card is built fresh for each request
## and freed by the tooltip popup; it never changes the selected item, so the
## action buttons always keep operating on the pinned selection.
func _build_item_tooltip(item_id: String, area: String = "") -> Control:
	if state == null:
		return null
	var equipped_here: bool = area == "paperdoll" and state.is_equipped(item_id)
	var panel := PanelContainer.new()
	panel.name = "ItemTooltip"
	panel.theme = theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(Color(0.03,0.062,0.078,0.98),TEAL if equipped_here else GOLD,8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation",3)
	panel.add_child(box)
	_tooltip_label(box,state.item_name(item_id),17,CREAM)
	var type_line: String = state.item_type_line(item_id)
	if equipped_here:
		type_line += "  •  EQUIPPED"
	_tooltip_label(box,type_line,10,TEAL if equipped_here else GOLD)
	var rows: Array = state.item_stat_rows(item_id)
	if not rows.is_empty():
		var divider := ColorRect.new()
		divider.color = Color("3f5b60")
		divider.custom_minimum_size = Vector2(0,1)
		divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(divider)
		for row in rows:
			_tooltip_row(box,str(row.get("label","")),str(row.get("value","")))
		if state.item_damage_range(item_id) != Vector2i.ZERO:
			var note := "Body hit to headshot at full draw." if state.item_category(item_id) == "bow" else "Body hit to headshot."
			_tooltip_label(box,note,9,MUTED)
	var detail: String = state.item_detail(item_id)
	if not detail.is_empty():
		_tooltip_label(box,detail,10,MUTED,282.0)
	var summary: String = state.item_summary(item_id)
	if not summary.is_empty():
		_tooltip_label(box,summary,11,CREAM,282.0)
	var quote: String = state.item_quote(item_id)
	if not quote.is_empty():
		_tooltip_label(box,"“%s”" % quote,11,Color("d8c8a2"),282.0)
	return panel

func _tooltip_label(parent: Node, text: String, font_size: int, color: Color, wrap_width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	if wrap_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(wrap_width,0)
	parent.add_child(label)
	return label

func _tooltip_row(parent: Node, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	var key_label := _tooltip_label(row,key,10,MUTED)
	key_label.custom_minimum_size = Vector2(104,0)
	_tooltip_label(row,value,12,CREAM)
