extends CanvasLayer
## In-world kit UI. `I` shows the backpack, `P` shows the equipped paperdoll,
## a vendor stall shows their stock, and the town stash chest shows the stash.
## The overlay owns every PlayerState mutation and never touches the cursor; the
## scene decides when the pointer is free and when movement is blocked.

signal opened
signal closed
signal loadout_changed

const StateScript = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const SlotScript = preload("res://scripts/inventory_slot.gd")
const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const WARN := Color("e2a06a")

var state
var session
var rig
var in_town := true
var view := ""
var paperdoll_panel: Panel
var inventory_panel: Panel
var side_panel: Panel
var details_panel: Panel
var close_button: Button
var paperdoll_buttons: Array[InventorySlot] = []
var backpack_buttons: Array[InventorySlot] = []
var stash_buttons: Array[InventorySlot] = []
var stock_buttons: Array[InventorySlot] = []
var floor_buttons: Array[InventorySlot] = []
var _dim: ColorRect
var _title: Label
var _purse: Label
var _status: Label
var _mode_title: Label
var _side_title: Label
var _side_sub: Label
var _backpack_count: Label
var _stash_count: Label
var _floor_label: Label
var _floor_list: HBoxContainer
var _floor_scroll: ScrollContainer
var _stock_scroll: ScrollContainer
var _stock_list: VBoxContainer
var _detail_header: Label
var _detail_meta: Label
var _detail_text: Label
var _detail_hint: Label
var _quick_label: Label
var _primary: Button
var _secondary: Button
var _tertiary: Button
var _buy: Button
var _drop_handler := Callable()
var _open := false
var _location := ""
var _index := -1
var _slot := ""
var _stock_item := ""
var _vendor := 0
var _built := false

func configure(player_state, session_state, rig_node, drop_handler: Callable = Callable(), town := true) -> void:
	state = player_state
	session = session_state
	rig = rig_node
	_drop_handler = drop_handler
	in_town = town
	if _built:
		refresh()
	else:
		_build()
		refresh()
	visible = _open

func rebind(rig_node) -> void:
	rig = rig_node

func is_open() -> bool:
	return _open

func active_view() -> String:
	return view

func open_inventory() -> void:
	_open_view("inventory")

func open_equipment() -> void:
	_open_view("equipment")

func open_stash() -> void:
	_open_view("stash")

func open_vendor(index: int) -> void:
	if index < 0 or index >= StateScript.VENDORS.size():
		return
	_vendor = index
	_open_view("vendor")

func toggle_inventory() -> void:
	if is_open() and view == "inventory":
		close()
	else:
		open_inventory()

func toggle_equipment() -> void:
	if is_open() and view == "equipment":
		close()
	else:
		open_equipment()

func close() -> void:
	if not _open:
		return
	_open = false
	_location = ""
	_index = -1
	_slot = ""
	_stock_item = ""
	visible = false
	closed.emit()

func refresh() -> void:
	if not _built or state == null:
		return
	_purse.text = "%d c" % int(state.credits)
	_backpack_count.text = "%d / %d" % [state.inventory.size(),state.INVENTORY_CAPACITY]
	_stash_count.text = "%d / %d" % [state.stash.size(),state.STASH_CAPACITY]
	_refresh_paperdoll()
	_refresh_backpack()
	_refresh_stash()
	_refresh_floor()
	_refresh_stock()
	_refresh_selection()

func set_status(message: String) -> void:
	if _status != null:
		_status.text = message

func _open_view(next: String) -> void:
	var was_open := _open
	view = next
	_open = true
	visible = true
	_location = ""
	_index = -1
	_slot = ""
	_stock_item = ""
	_refresh_visibility()
	refresh()
	if _mode_title != null:
		_mode_title.text = "EQUIPMENT"
	match next:
		"inventory":
			set_status("INVENTORY  /  right-click a piece to equip it.")
		"equipment":
			set_status("EQUIPMENT  /  right-click a slot to return it to the pack.")
		"stash":
			set_status("STASH  /  move pieces between the pack and the chest.")
		"vendor":
			set_status("%s  /  %s" % [StateScript.VENDORS[_vendor].name,StateScript.VENDORS[_vendor].line])
	if not was_open:
		opened.emit()
	visible = true

func _view_title() -> String:
	match view:
		"inventory":
			return "INVENTORY"
		"equipment":
			return "EQUIPMENT"
		"stash":
			return "STASH"
		"vendor":
			return str(StateScript.VENDORS[_vendor].tag)
	return ""

func _refresh_visibility() -> void:
	_dim.visible = _open
	paperdoll_panel.visible = _open and view == "equipment"
	inventory_panel.visible = _open and view in ["inventory","stash","vendor"]
	side_panel.visible = _open and view in ["stash","vendor"]
	details_panel.visible = _open and view != ""
	_title.visible = _open
	_purse.visible = _open
	_status.visible = _open
	close_button.visible = _open
	_side_title.text = "STASH" if view == "stash" else "STOCK"
	_side_sub.text = "The town strongbox." if view == "stash" else str(StateScript.VENDORS[_vendor].name)
	_stock_scroll.visible = view == "vendor"
	_buy.visible = view == "vendor"
	_stash_count.visible = view == "stash"
	if view == "stash":
		_side_title.text = "STASH"
	elif view == "vendor":
		_side_title.text = str(StateScript.VENDORS[_vendor].tag)
	else:
		_side_title.text = ""

func _build() -> void:
	if _built:
		return
	_built = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = _build_theme()
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.015,0.035,0.045,0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)
	_title = _label(root,"IRONWOOD",Vector2(40,28),30,CREAM)
	_purse = _label(root,"0 c",Vector2(1050,32),20,GOLD)
	_purse.size = Vector2(180,30)
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_button = _button(root,"CLOSE / ESC",Vector2(1240,28),Vector2(160,40))
	close_button.add_theme_font_size_override("font_size",12)
	close_button.pressed.connect(close)
	_status = _label(root,"",Vector2(-430,34),14,TEAL)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP,true)
	_status.size = Vector2(860,40)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_paperdoll(root)
	build_inventory(root)
	build_side(root)
	build_details(root)
	_refresh_visibility()

func _build_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI"])
	result.default_font = font
	result.default_font_size = 14
	result.set_color("font_color","Label",CREAM)
	result.set_color("font_color","Button",CREAM)
	result.set_color("font_hover_color","Button",Color.WHITE)
	result.set_color("font_pressed_color","Button",Color("13282f"))
	result.set_color("font_disabled_color","Button",MUTED)
	result.set_stylebox("normal","Button",_style(Color("243a40"),Color("456068"),6))
	result.set_stylebox("hover","Button",_style(Color("34545b"),GOLD,6))
	result.set_stylebox("pressed","Button",_style(GOLD,GOLD,6))
	result.set_stylebox("disabled","Button",_style(Color("1b2b30"),Color("33484e"),6))
	return result

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	return result

func _panel(parent: Node, at: Vector2, size_at: Vector2) -> Panel:
	var result := Panel.new()
	result.position = at
	result.size = size_at
	result.add_theme_stylebox_override("panel",_style(Color(0.038,0.078,0.096,0.96),Color("3f5b60"),8))
	parent.add_child(result)
	return result

func _label(parent: Node, text: String, at: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	parent.add_child(result)
	return result

func _button(parent: Node, text: String, at: Vector2, size_at: Vector2) -> Button:
	var result := Button.new()
	result.text = text
	result.position = at
	result.size = size_at
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result

func _make_slot(parent: Node, area: String, index: int, slot_name: String, at: Vector2, size_at: Vector2, font_size: int) -> InventorySlot:
	var result := SlotScript.new()
	result.position = at
	result.size = size_at
	result.custom_minimum_size = size_at
	result.focus_mode = Control.FOCUS_NONE
	result.clip_text = true
	result.add_theme_font_size_override("font_size",font_size)
	result.drag_enabled = false
	result.configure(area,index,slot_name,"")
	result.right_clicked.connect(_on_right_clicked)
	result.pressed.connect(_on_slot_pressed.bind(area,index,slot_name))
	parent.add_child(result)
	return result

func build_paperdoll(parent: Node) -> void:
	paperdoll_panel = _panel(parent,Vector2(40,110),Vector2(430,390))
	_mode_title = _label(paperdoll_panel,"EQUIPMENT",Vector2(16,10),12,GOLD)
	_label(paperdoll_panel,"Drag-free paperdoll  •  click a slot to inspect",Vector2(16,30),10,MUTED)
	for index in Rules.SLOTS.size():
		var slot_name: String = Rules.SLOTS[index]
		var column := index % 2
		var row := index / 2
		var button := _make_slot(paperdoll_panel,"paperdoll",-1,slot_name,Vector2(16+column*202,52+row*52),Vector2(196,44),11)
		paperdoll_buttons.append(button)
	_quick_label = _label(paperdoll_panel,"",Vector2(16,312),10,TEAL)
	_quick_label.size = Vector2(398,16)
	_quick_label.clip_text = true
	_label(paperdoll_panel,"TAB swaps this pair. Select a main/off slot, then BIND SWAP.",Vector2(16,330),10,MUTED)

func build_inventory(parent: Node) -> void:
	inventory_panel = _panel(parent,Vector2(40,110),Vector2(430,390))
	_label(inventory_panel,"BACKPACK",Vector2(16,10),12,GOLD)
	_backpack_count = _label(inventory_panel,"",Vector2(250,10),12,CREAM)
	_backpack_count.size = Vector2(164,18)
	_backpack_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in StateScript.INVENTORY_CAPACITY:
		var column := index % 5
		var row := index / 5
		var button := _make_slot(inventory_panel,"backpack",index,"",Vector2(16+column*80,48+row*56),Vector2(76,48),10)
		backpack_buttons.append(button)
	_floor_label = _label(inventory_panel,"GROUND  •  empty",Vector2(16,216),10,MUTED)
	_floor_label.size = Vector2(398,16)
	_floor_scroll = ScrollContainer.new()
	_floor_scroll.position = Vector2(16,234)
	_floor_scroll.size = Vector2(398,38)
	_floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_floor_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_panel.add_child(_floor_scroll)
	_floor_list = HBoxContainer.new()
	_floor_list.add_theme_constant_override("separation",4)
	_floor_scroll.add_child(_floor_list)
	_label(inventory_panel,"I  INVENTORY  /  P  EQUIPMENT  /  TAB  SWAP\nG  interact with a keeper or chest",Vector2(16,284),11,MUTED)

func build_side(parent: Node) -> void:
	side_panel = _panel(parent,Vector2(500,110),Vector2(900,390))
	_side_title = _label(side_panel,"",Vector2(16,10),12,GOLD)
	_side_sub = _label(side_panel,"",Vector2(16,30),11,MUTED)
	_side_sub.size = Vector2(860,20)
	_stash_count = _label(side_panel,"",Vector2(760,10),12,CREAM)
	_stash_count.size = Vector2(124,18)
	_stash_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in 20:
		var column := index % 5
		var row := index / 5
		var button := _make_slot(side_panel,"stash",index,"",Vector2(16+column*176,58+row*58),Vector2(168,52),11)
		stash_buttons.append(button)
	_stock_scroll = ScrollContainer.new()
	_stock_scroll.position = Vector2(16,58)
	_stock_scroll.size = Vector2(868,290)
	_stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(_stock_scroll)
	_stock_list = VBoxContainer.new()
	_stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_list.add_theme_constant_override("separation",4)
	_stock_scroll.add_child(_stock_list)
	for index in 28:
		var button := _make_slot(_stock_list,"stock",index,"",Vector2.ZERO,Vector2(820,32),12)
		button.custom_minimum_size = Vector2(0,32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		stock_buttons.append(button)
	_buy = _button(side_panel,"BUY",Vector2(16,358),Vector2(868,26))
	_buy.add_theme_font_size_override("font_size",12)
	_buy.pressed.connect(_on_buy)

func build_details(parent: Node) -> void:
	details_panel = _panel(parent,Vector2(40,512),Vector2(1360,236))
	_detail_header = _label(details_panel,"Nothing selected",Vector2(18,12),22,CREAM)
	_detail_header.size = Vector2(940,28)
	_detail_header.clip_text = true
	_detail_meta = _label(details_panel,"",Vector2(18,44),12,TEAL)
	_detail_meta.size = Vector2(940,20)
	_detail_meta.clip_text = true
	_detail_text = _label(details_panel,"",Vector2(18,68),12,MUTED)
	_detail_text.size = Vector2(940,58)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_hint = _label(details_panel,"",Vector2(18,132),11,MUTED)
	_detail_hint.size = Vector2(940,24)
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_primary = _button(details_panel,"",Vector2(990,20),Vector2(350,44))
	_primary.add_theme_font_size_override("font_size",14)
	_primary.pressed.connect(_on_primary)
	_secondary = _button(details_panel,"",Vector2(990,76),Vector2(350,44))
	_secondary.add_theme_font_size_override("font_size",14)
	_secondary.pressed.connect(_on_secondary)
	_tertiary = _button(details_panel,"",Vector2(990,132),Vector2(350,44))
	_tertiary.add_theme_font_size_override("font_size",14)
	_tertiary.pressed.connect(_on_tertiary)
	_label(details_panel,"DROP moves the piece onto the ground. Re-pickup it from the world.",Vector2(990,184),10,MUTED)

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
	if _quick_label != null:
		_quick_label.text = "QUICK SWAP (TAB)  •  %s" % state.quick_set_label()

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
		button.index = index
		if index < state.stash.size():
			var item_id: String = state.stash[index]
			button.item = item_id
			button.text = state.item_short(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.item = ""
			button.text = ""
			button.tooltip_text = ""
		button.set_pressed_no_signal(_location == "stash" and index == _index)

func _refresh_floor() -> void:
	for child in _floor_list.get_children():
		_floor_list.remove_child(child)
		child.queue_free()
	floor_buttons.clear()
	var items: Array = state.floor_items
	_floor_label.text = "GROUND  •  nothing dropped" if items.is_empty() else "GROUND  •  %d piece(s)" % items.size()
	for index in items.size():
		var item_id: String = items[index]
		var button := _make_slot(_floor_list,"floor",index,"",Vector2.ZERO,Vector2(112,32),10)
		button.custom_minimum_size = Vector2(112,32)
		button.item = item_id
		button.text = state.item_short(item_id)
		button.tooltip_text = state.item_name(item_id)
		button.set_pressed_no_signal(_location == "floor" and index == _index)
		floor_buttons.append(button)

func _refresh_stock() -> void:
	if view != "vendor":
		return
	var vendor: Dictionary = StateScript.VENDORS[_vendor]
	var stock: Array = vendor.stock
	for index in stock_buttons.size():
		var button := stock_buttons[index]
		if index < stock.size():
			var item_id: String = stock[index]
			button.visible = true
			button.disabled = false
			button.index = index
			button.item = item_id
			button.text = "%s   %d c" % [state.item_name(item_id),state.item_price(item_id)]
			button.tooltip_text = state.item_detail(item_id)
			button.set_pressed_no_signal(_location == "stock" and _stock_item == item_id)
		else:
			button.visible = false
			button.disabled = true
			button.item = ""
			button.text = ""

func _refresh_selection() -> void:
	var item_id := _selected_item()
	if item_id.is_empty():
		_detail_header.text = "Nothing selected"
		_detail_meta.text = ""
		_detail_text.text = ""
		_detail_hint.text = "Click a slot to inspect it."
		_primary.visible = false
		_secondary.visible = false
		_tertiary.visible = false
		_buy.disabled = true
		return
	_detail_header.text = state.item_name(item_id)
	var meta: String = state.item_type_line(item_id)
	var compact: String = state.item_compact_stats(item_id)
	if not compact.is_empty():
		meta += "  •  " + compact
	if _location != "stock" and state.is_equipped(item_id):
		meta += "  •  EQUIPPED"
	_detail_meta.text = meta
	_detail_text.text = "%s\n“%s”" % [state.item_summary(item_id),state.item_quote(item_id)]
	_primary.visible = false
	_secondary.visible = false
	_tertiary.visible = false
	match _location:
		"backpack":
			_primary.visible = true
			_primary.text = "EQUIP"
			_primary.tooltip_text = "Auto-route to the legal slot."
			if view == "stash":
				_secondary.visible = true
				_secondary.text = "TO STASH"
				_secondary.disabled = state.stash_full()
				_secondary.tooltip_text = "Stash is full." if state.stash_full() else ""
			if view == "vendor":
				_secondary.visible = true
				_secondary.text = "SELL  /  %d c" % state.sell_value(item_id)
				_secondary.disabled = false
			if _drop_handler.is_valid() or in_town:
				_tertiary.visible = true
				_tertiary.text = "DROP"
				_tertiary.tooltip_text = "Drop the piece on the ground."
			_detail_hint.text = "Right-click equips automatically."
		"paperdoll":
			_primary.visible = true
			_primary.text = "UNEQUIP"
			_primary.tooltip_text = "Return this piece to the backpack."
			if _slot == "main" or _slot == "off":
				_secondary.visible = true
				_secondary.text = "BIND SWAP"
				_secondary.tooltip_text = "Store the current main and off hand as the TAB swap set."
			if _drop_handler.is_valid() or in_town:
				_tertiary.visible = true
				_tertiary.text = "DROP"
			_detail_hint.text = "Right-click returns it to the backpack. TAB swaps the bound pair."
		"stash":
			_primary.visible = true
			_primary.text = "TO INVENTORY"
			_primary.disabled = state.inventory_full()
			_primary.tooltip_text = "Backpack is full." if state.inventory_full() else ""
			_detail_hint.text = "Move pieces between the stash and the backpack."
		"floor":
			_primary.visible = true
			_primary.text = "PICK UP"
			_primary.disabled = state.inventory_full()
			_primary.tooltip_text = "Backpack is full." if state.inventory_full() else ""
			_detail_hint.text = "Ground items wait at the ranger's feet."
		"stock":
			_detail_hint.text = "Buy a piece with a free backpack slot."
			_buy.disabled = state.inventory_full() or int(state.credits) < state.item_price(item_id)
			_buy.text = "BUY  /  %d c" % state.item_price(item_id)
	if _location != "stock":
		_buy.disabled = true

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
		"floor":
			if _index >= 0 and _index < state.floor_items.size():
				return state.floor_items[_index]
		"paperdoll":
			return state.equipped_id(_slot)
		"stock":
			return _stock_item
	return ""

func _on_slot_pressed(area: String, index: int, slot_name: String) -> void:
	if area == "stock":
		_location = "stock"
		_index = index
		_stock_item = str(StateScript.VENDORS[_vendor].stock[index]) if index < StateScript.VENDORS[_vendor].stock.size() else ""
	elif area == "paperdoll":
		_location = "paperdoll"
		_index = -1
		_slot = slot_name
	else:
		_location = area
		_index = index
		_slot = slot_name
	_refresh_selection()
	_refresh_paperdoll()
	_refresh_backpack()
	_refresh_stash()
	_refresh_floor()
	_refresh_stock()

func _on_right_clicked(area: String, index: int, slot_name: String, item_id: String) -> void:
	if item_id.is_empty():
		return
	match area:
		"backpack":
			_resolve(state.equip_from_inventory(index,""))
		"paperdoll":
			_resolve(state.unequip_to_backpack(slot_name))
		"stash":
			_resolve(state.move_to_inventory(index))
		"floor":
			_resolve(state.pickup_floor(index))
		"stock":
			_location = "stock"
			_stock_item = item_id
			_refresh_selection()

func _on_primary() -> void:
	if state == null:
		return
	match _location:
		"backpack":
			_resolve(state.equip_from_inventory(_index,""))
		"paperdoll":
			_resolve(state.unequip_to_backpack(_slot))
		"stash":
			_resolve(state.move_to_inventory(_index))
		"floor":
			_resolve(state.pickup_floor(_index))

func _on_secondary() -> void:
	if state == null:
		return
	if _location == "paperdoll":
		var result: Dictionary = state.bind_quick_from_equipped()
		refresh()
		set_status(str(result.get("message","")))
		return
	if _location == "backpack":
		if view == "stash":
			_resolve(state.move_to_stash(_index))
		elif view == "vendor":
			_resolve(state.sell("inventory",_index))

func _on_tertiary() -> void:
	if state == null:
		return
	if _location == "backpack":
		_drop_item("backpack",_index)
	elif _location == "paperdoll":
		_drop_item("paperdoll",_slot)

func _drop_item(area: String, key: Variant) -> void:
	var world_drop := _drop_handler.is_valid()
	var result: Dictionary
	if area == "paperdoll":
		var slot_name := str(key)
		result = state.take_equipped(slot_name) if world_drop else state.drop_equipped(slot_name)
	else:
		var index := int(key)
		result = state.take_from_inventory(index) if world_drop else state.drop_from_inventory(index)
	if bool(result.get("ok", false)) and world_drop:
		_drop_handler.call(str(result.get("item_id","")))
	_resolve(result)

func _on_buy() -> void:
	if state == null or _stock_item.is_empty():
		return
	_resolve(state.buy(_stock_item))

func _resolve(result: Dictionary) -> void:
	var ok := bool(result.get("ok",false))
	if ok:
		_location = ""
		_index = -1
		_slot = ""
		_stock_item = ""
	refresh()
	if ok:
		_apply_rig()
		loadout_changed.emit()
	set_status(str(result.get("message","")))

func _apply_rig() -> void:
	if state == null or rig == null:
		return
	if not is_instance_valid(rig) or not rig.has_method("apply_loadout"):
		return
	rig.apply_loadout(state.loadout())
