extends Control
## Hub interface: inventory, stash, vendors and every way to leave the Hollow.
## The panel is read-only over PlayerState; every mutation is a signal to menu.gd.

signal mode_selected(mode: String)
signal host_confirmed(port: int, player_name: String)
signal join_confirmed(address: String, port: int, player_name: String)
signal delve_host_confirmed(port: int, player_name: String)
signal delve_join_confirmed(address: String, port: int, player_name: String)
signal buy_requested(item_id: String)
signal equip_requested(index: int)
signal stash_requested(index: int)
signal unstash_requested(index: int)
signal sell_requested(location: String, index: int)

const StateScript = preload("res://scripts/player_state.gd")
const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")
const SLOT_FONT := 11

var state
var session
var header_panel: Panel
var purse_panel: Panel
var inventory_panel: Panel
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
var inventory_buttons: Array[Button] = []
var stash_buttons: Array[Button] = []
var stock_buttons: Array[Button] = []
var vendor_buttons: Array[Button] = []
var stock_scroll: ScrollContainer
var stock_list: VBoxContainer
var _inventory_count: Label
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
var _modal_kind := ""
var _location := ""
var _index := -1
var _stock_item := ""
var _vendor := 0
var _default_name := "Ranger"
var _default_address := "127.0.0.1"
var _default_port := 7777

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _build_theme()
	_build_header()
	_build_inventory()
	_build_stash()
	_build_vendors()
	_build_actions()
	_build_status()
	_build_modal()

func configure(player_state, session_state) -> void:
	state = player_state
	session = session_state
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		_default_name = str(cache.player_name)
		_default_address = str(cache.address)
		_default_port = int(cache.port)
	elif session != null:
		_default_name = str(session.player_name)
	refresh()

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

func _build_inventory() -> void:
	inventory_panel = _panel(self,Vector2(24,126),Vector2(404,372))
	var panel := inventory_panel
	_label(panel,"INVENTORY",Vector2(16,12),12,GOLD)
	_inventory_count = _label(panel,"",Vector2(248,12),12,CREAM)
	_inventory_count.size = Vector2(140,20)
	_inventory_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in 10:
		var column := index % 5
		var row := index / 5
		var button := _button(panel,"",Vector2(16+column*74,42+row*70),Vector2(68,62))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",SLOT_FONT)
		button.clip_text = true
		button.pressed.connect(_on_inventory_slot.bind(index))
		inventory_buttons.append(button)
	_label(panel,"SELECTED",Vector2(18,190),10,MUTED)
	_detail_header = _label(panel,"Nothing selected",Vector2(18,208),16,CREAM)
	_detail_meta = _label(panel,"",Vector2(18,232),11,TEAL)
	_detail_text = _label(panel,"",Vector2(18,252),12,MUTED)
	_detail_text.size = Vector2(366,44)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equip_button = _button(panel,"EQUIP",Vector2(18,304),Vector2(112,34))
	equip_button.pressed.connect(_on_equip)
	move_button = _button(panel,"TO STASH",Vector2(140,304),Vector2(112,34))
	move_button.pressed.connect(_on_move)
	sell_button = _button(panel,"SELL",Vector2(262,304),Vector2(100,34))
	sell_button.pressed.connect(_on_sell)
	_detail_hint = _label(panel,"* star marks the equipped item",Vector2(18,344),10,MUTED)

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
		var button := _button(panel,"",Vector2(16+column*60,42+row*44),Vector2(55,38))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",10)
		button.clip_text = true
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
	for index in 20:
		var button := _button(stock_list,"",Vector2.ZERO,Vector2(320,30))
		button.custom_minimum_size = Vector2(0,30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size",12)
		button.pressed.connect(_on_stock.bind(index))
		stock_buttons.append(button)
	_stock_header = _label(panel,"SELECT A STOCK ITEM",Vector2(16,288),10,MUTED)
	_stock_meta = _label(panel,"",Vector2(16,306),15,CREAM)
	_stock_text = _label(panel,"",Vector2(16,324),11,MUTED)
	_stock_text.size = Vector2(348,32)
	_stock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy_button = _button(panel,"BUY",Vector2(16,360),Vector2(348,34))
	buy_button.pressed.connect(_on_buy)
	_label(panel,"A purchase needs a free inventory slot.",Vector2(16,398),10,MUTED)

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
	if state == null:
		return
	_credits.text = "%d c" % int(state.credits)
	_inventory_count.text = "%d / %d" % [state.inventory.size(),state.INVENTORY_CAPACITY]
	_stash_count.text = "%d / %d" % [state.stash.size(),state.STASH_CAPACITY]
	for index in inventory_buttons.size():
		var button := inventory_buttons[index]
		if index < state.inventory.size():
			var item_id: String = state.inventory[index]
			button.disabled = false
			button.text = ("* " if state.is_equipped(item_id) else "") + state.item_short(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.disabled = true
			button.text = "—"
			button.tooltip_text = ""
		button.set_pressed_no_signal(_location == "inventory" and index == _index)
	for index in stash_buttons.size():
		var button := stash_buttons[index]
		if index < state.stash.size():
			var item_id: String = state.stash[index]
			button.disabled = false
			button.text = state.item_short(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.disabled = true
			button.text = ""
			button.tooltip_text = ""
		button.set_pressed_no_signal(_location == "stash" and index == _index)
	_refresh_vendor()
	_refresh_selection()

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
			button.text = "%s%s   %d c" % ["* " if state.is_equipped(item_id) else "",state.item_name(item_id),state.item_price(item_id)]
			button.set_pressed_no_signal(_location == "stock" and _stock_item == item_id)
		else:
			button.visible = false
			button.disabled = true
			button.text = ""
	if _location == "stock" and not _stock_item.is_empty():
		_stock_header.text = "STOCKED  /  " + state.item_kind(_stock_item).to_upper()
		_stock_meta.text = state.item_name(_stock_item)
		var owned: int = state.owned_in_inventory(_stock_item) + state.owned_in_stash(_stock_item)
		_stock_text.text = "%s\nYou own %d.  %d credits." % [state.item_detail(_stock_item),owned,state.item_price(_stock_item)]
	else:
		_stock_header.text = "SELECT A STOCK ITEM"
		_stock_meta.text = ""
		_stock_text.text = ""

func _refresh_selection() -> void:
	var item_id := _selected_item()
	equip_button.visible = _location == "inventory"
	move_button.visible = _location == "inventory" or _location == "stash"
	sell_button.visible = _location == "inventory" or _location == "stash"
	buy_button.visible = _location == "stock" and not _stock_item.is_empty()
	if buy_button.visible:
		buy_button.disabled = state.inventory_full() or int(state.credits) < state.item_price(_stock_item)
		buy_button.text = "BUY  /  %d c" % state.item_price(_stock_item)
		buy_button.tooltip_text = "Inventory is full." if state.inventory_full() else "Not enough credits." if int(state.credits) < state.item_price(_stock_item) else ""
	if item_id.is_empty():
		_detail_header.text = "Nothing selected"
		_detail_meta.text = ""
		_detail_text.text = ""
		equip_button.disabled = true
		move_button.disabled = true
		sell_button.disabled = true
		_detail_hint.text = "* star marks the equipped item"
		return
	_detail_header.text = state.item_name(item_id)
	var kind: String = state.item_kind(item_id).to_upper()
	var equipped: bool = state.is_equipped(item_id)
	_detail_meta.text = kind + ("  /  EQUIPPED" if equipped else "")
	_detail_meta.add_theme_color_override("font_color",TEAL if equipped else GOLD)
	_detail_text.text = "%s\n%s" % [state.item_summary(item_id),state.item_detail(item_id)]
	_detail_hint.text = "Sell value %d credits." % state.sell_value(item_id)
	if _location == "inventory":
		equip_button.disabled = equipped
		equip_button.text = "EQUIPPED" if equipped else "EQUIP"
		var move_blocked: bool = state.stash_full() or (equipped and state.owned_in_inventory(item_id) <= 1)
		move_button.disabled = move_blocked
		move_button.text = "TO STASH"
		move_button.tooltip_text = "Stash is full." if state.stash_full() else "Equip another item before storing the equipped one." if move_blocked else ""
		sell_button.disabled = equipped and state.owned_in_inventory(item_id) <= 1
		sell_button.tooltip_text = "Equipped — equip another item of this type first." if sell_button.disabled else ""
	elif _location == "stash":
		move_button.disabled = state.inventory_full()
		move_button.text = "TO INVENTORY"
		move_button.tooltip_text = "Inventory is full." if state.inventory_full() else ""
		sell_button.disabled = false
		sell_button.tooltip_text = ""

func clear_selection() -> void:
	_location = ""
	_index = -1
	_stock_item = ""

func _selected_item() -> String:
	if state == null:
		return ""
	if _location == "inventory" and _index >= 0 and _index < state.inventory.size():
		return state.inventory[_index]
	if _location == "stash" and _index >= 0 and _index < state.stash.size():
		return state.stash[_index]
	return ""

func _on_inventory_slot(index: int) -> void:
	if state == null or index >= state.inventory.size():
		return
	_location = "inventory"
	_index = index
	_stock_item = ""
	refresh()

func _on_stash_slot(index: int) -> void:
	if state == null or index >= state.stash.size():
		return
	_location = "stash"
	_index = index
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
	refresh()

func _on_equip() -> void:
	if _location == "inventory":
		equip_requested.emit(_index)

func _on_move() -> void:
	if _location == "inventory":
		stash_requested.emit(_index)
	elif _location == "stash":
		unstash_requested.emit(_index)

func _on_sell() -> void:
	if _location == "inventory" or _location == "stash":
		sell_requested.emit(_location,_index)

func _on_buy() -> void:
	if _location == "stock" and not _stock_item.is_empty():
		buy_requested.emit(_stock_item)
