extends CanvasLayer
## In-world kit UI. `I` and `P` both open the combined equipment screen: the
## worn pieces on the left, a live ranger in the middle, trinkets and the kit's
## derived stats on the right, and the 60-slot backpack underneath. A vendor
## stall replaces the stage with its stock, and the town stash chest replaces it
## with the strongbox; the backpack grid stays put in every view.
##
## The overlay owns every PlayerState mutation and never touches the cursor; the
## scene decides when the pointer is free and when movement is blocked.

signal opened
signal closed
signal loadout_changed

const StateScript = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const SlotScript = preload("res://scripts/inventory_slot.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const ItemTooltip = preload("res://scripts/item_tooltip.gd")
const CharacterPreview = preload("res://scripts/character_preview.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")

const COLUMNS := 15
const SLOT_SIZE := Vector2(78,40)
const SLOT_GAP := Vector2(4,4)
const GRID_ORIGIN := Vector2(11,62)

var state
var session
var rig
var in_town := true
var view := ""
var paperdoll_panel: Control
var inventory_panel: Panel
var side_panel: Panel
var close_button: Button
var paperdoll_buttons: Array[InventorySlot] = []
var backpack_buttons: Array[InventorySlot] = []
var stash_buttons: Array[InventorySlot] = []
var stock_buttons: Array[InventorySlot] = []
var floor_buttons: Array[InventorySlot] = []
var preview
var _dim: ColorRect
var _title: Label
var _subtitle: Label
var _purse: Label
var _status: Label
var _selected_label: Label
var _side_title: Label
var _side_sub: Label
var _backpack_count: Label
var _stash_count: Label
var _floor_label: Label
var _floor_list: HBoxContainer
var _floor_scroll: ScrollContainer
var _stock_scroll: ScrollContainer
var _stock_list: VBoxContainer
var _quick_label: Label
var _stat_values: Dictionary = {}
var _bonus_list: VBoxContainer
var _trinket_labels: Array[Label] = []
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
var _preview_signature := ""
var _character_panel: Panel

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
	if preview != null:
		preview.set_active(false)
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
	_refresh_stats()
	_refresh_preview()

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
	if next in ["inventory","equipment"]:
		_ensure_preview()
	_refresh_visibility()
	refresh()
	_title.text = _view_title()
	_subtitle.text = "THE TOWN STRONGBOX" if next == "stash" else \
		(StateScript.VENDORS[_vendor].tag if next == "vendor" else "THE RANGER'S KIT")
	match next:
		"inventory","equipment":
			_mode_hint("EQUIPMENT  •  click a slot to select, right-click to equip or return it.  Hover any piece for its card.")
		"stash":
			_mode_hint("STASH  •  select a pack piece, then TO STASH; select a stashed piece, then TO INVENTORY.")
		"vendor":
			_mode_hint("%s  •  select stock to buy, or a pack piece to sell." % StateScript.VENDORS[_vendor].name)
	if not was_open:
		opened.emit()
	visible = true

func _mode_hint(message: String) -> void:
	set_status(message)

func _view_title() -> String:
	match view:
		"inventory","equipment":
			return "EQUIPMENT"
		"stash":
			return "STASH"
		"vendor":
			return str(StateScript.VENDORS[_vendor].tag)
	return ""

func _refresh_visibility() -> void:
	var kit_visible := _open and view in ["inventory","equipment"]
	_dim.visible = _open
	paperdoll_panel.visible = kit_visible
	inventory_panel.visible = _open and view in ["inventory","equipment","stash","vendor"]
	side_panel.visible = _open and view in ["stash","vendor"]
	_title.visible = _open
	_subtitle.visible = _open
	_purse.visible = _open
	_status.visible = _open
	close_button.visible = _open
	_side_title.text = "STASH" if view == "stash" else str(StateScript.VENDORS[_vendor].tag)
	_side_sub.text = "The town strongbox." if view == "stash" else str(StateScript.VENDORS[_vendor].line)
	_stock_scroll.visible = view == "vendor"
	_buy.visible = view == "vendor"
	_stash_count.visible = view == "stash"
	for button in stash_buttons:
		button.visible = view == "stash"
	if preview != null:
		preview.set_active(kit_visible)

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
	_dim.color = Color(0.006,0.016,0.020,1.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)
	# One compact window instead of a full-screen sheet. 1120 x 640 in a
	# 1440 x 900 viewport leaves the world dimmed around it, like a panel.
	var shell := Control.new()
	shell.position = Vector2(80,150)
	shell.size = Vector2(1280,600)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shell)
	var window := Panel.new()
	window.position = Vector2.ZERO
	window.size = Vector2(1280,600)
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_theme_stylebox_override("panel",_style(Color(0.024,0.052,0.060,0.995),Color("6e5a3a"),9))
	shell.add_child(window)
	_title = _label(shell,"EQUIPMENT",Vector2(24,8),24,CREAM)
	_subtitle = _label(shell,"THE RANGER'S KIT",Vector2(26,36),10,GOLD)
	_quick_label = _label(shell,"",Vector2(330,36),9,GOLD)
	_quick_label.size = Vector2(600,14)
	_quick_label.clip_text = true
	_quick_label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.95))
	_quick_label.add_theme_constant_override("shadow_offset_x",1)
	_quick_label.add_theme_constant_override("shadow_offset_y",1)
	_purse = _label(shell,"0 c",Vector2(1000,14),16,GOLD)
	_purse.size = Vector2(130,24)
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_button = _button(shell,"CLOSE / ESC",Vector2(1138,10),Vector2(108,34))
	close_button.add_theme_font_size_override("font_size",10)
	close_button.pressed.connect(close)
	build_equipment(shell)
	build_backpack(shell)
	build_side(shell)
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
	result.toggle_mode = true
	result.add_theme_font_size_override("font_size",font_size)
	result.drag_enabled = false
	result.tooltip_builder = Callable(self,"_item_card")
	result.configure(area,index,slot_name,"")
	result.right_clicked.connect(_on_right_clicked)
	result.pressed.connect(_on_slot_pressed.bind(area,index,slot_name))
	parent.add_child(result)
	return result

func _item_card(item_id: String, _area: String) -> Control:
	if state == null:
		return null
	var card := ItemTooltip.new()
	card.configure(state,item_id)
	return card

## ---------------------------------------------------------------------------
## Equipment stage

func build_equipment(parent: Node) -> void:
	paperdoll_panel = Control.new()
	paperdoll_panel.position = Vector2(16,50)
	paperdoll_panel.size = Vector2(1248,280)
	paperdoll_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(paperdoll_panel)
	_build_worn(paperdoll_panel)
	_build_trinkets(paperdoll_panel)
	_build_character(paperdoll_panel)
	_build_stats(paperdoll_panel)

func _build_worn(parent: Node) -> void:
	var panel := _panel(parent,Vector2(0,0),Vector2(190,280))
	_label(panel,"WORN",Vector2(10,6),10,GOLD)
	_label(panel,"Armour, hands and boots",Vector2(10,20),9,MUTED)
	for index in 5:
		var slot_name: String = Rules.SLOTS[index]
		var button := _make_slot(panel,"paperdoll",-1,slot_name,
			Vector2(10,28+index*50),Vector2(170,48),11)
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width",46 if slot_name in ["hands","feet"] else 42)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		paperdoll_buttons.append(button)

func _build_character(parent: Node) -> void:
	_character_panel = _panel(parent,Vector2(198,0),Vector2(680,280))
	var backdrop := TextureRect.new()
	backdrop.position = Vector2(6,6)
	backdrop.size = Vector2(668,268)
	backdrop.texture = _stage_texture()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_panel.add_child(backdrop)
	var main_button := _make_slot(_character_panel,"paperdoll",-1,"main",Vector2(12,216),Vector2(190,54),10)
	main_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	main_button.expand_icon = false
	main_button.z_index = 2
	main_button.add_theme_constant_override("icon_max_width",40)
	paperdoll_buttons.append(main_button)
	var off_button := _make_slot(_character_panel,"paperdoll",-1,"off",Vector2(478,216),Vector2(190,54),10)
	off_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	off_button.expand_icon = false
	off_button.z_index = 2
	off_button.add_theme_constant_override("icon_max_width",40)
	paperdoll_buttons.append(off_button)

func _build_trinkets(parent: Node) -> void:
	var panel := _panel(parent,Vector2(886,0),Vector2(74,280))
	_label(panel,"TRINKETS",Vector2(4,6),8,GOLD)
	for offset in 3:
		var slot_name: String = Rules.SLOTS[5+offset]
		var button := _make_slot(panel,"paperdoll",-1,slot_name,
			Vector2(4,28+offset*74),Vector2(66,62),8)
		button.expand_icon = true
		button.text = ""
		paperdoll_buttons.append(button)
		var label := _label(panel,"",Vector2(4,92+offset*74),9,MUTED)
		label.size = Vector2(66,10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		_trinket_labels.append(label)
	_label(panel,"HOVER FOR",Vector2(4,258),7,MUTED)
	_label(panel,"ITS CARD",Vector2(4,268),7,MUTED)

func _build_stats(parent: Node) -> void:
	var panel := _panel(parent,Vector2(968,0),Vector2(280,280))
	_label(panel,"RANGER",Vector2(10,6),19,CREAM)
	_label(panel,"THE FRONTIER KIT",Vector2(11,28),9,MUTED)
	var rows := [
		{"key":"attack", "label":"Attack", "y":44},
		{"key":"defense", "label":"Defense", "y":78},
		{"key":"life", "label":"Life", "y":112},
		{"key":"stamina", "label":"Stamina", "y":146},
	]
	for row: Dictionary in rows:
		_label(panel,str(row["label"]),Vector2(10,float(row["y"])),10,MUTED)
		var value := _label(panel,"—",Vector2(130,float(row["y"])-4),18,GOLD)
		value.size = Vector2(140,26)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stat_values[str(row["key"])] = value
		var rule := ColorRect.new()
		rule.position = Vector2(10,float(row["y"])+30)
		rule.size = Vector2(260,1)
		rule.color = Color("2d474d")
		panel.add_child(rule)
	_label(panel,"BONUSES",Vector2(10,182),9,GOLD)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(10,198)
	scroll.size = Vector2(260,64)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_bonus_list = VBoxContainer.new()
	_bonus_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bonus_list.add_theme_constant_override("separation",1)
	scroll.add_child(_bonus_list)
	_label(panel,"HOVER A SLOT FOR ITS CARD",Vector2(10,268),8,MUTED)

func _stage_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.66,1.0])
	gradient.colors = PackedColorArray([Color("27464a"),Color("14272b"),Color("081113")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.40)
	texture.fill_to = Vector2(1.08,0.52)
	texture.width = 512
	texture.height = 512
	return texture

func _ensure_preview() -> void:
	if preview != null or _character_panel == null:
		return
	preview = CharacterPreview.new()
	preview.name = "Preview"
	preview.position = Vector2(6,6)
	preview.size = Vector2(668,268)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.built.connect(_on_preview_built)
	_character_panel.add_child(preview)

func _on_preview_built() -> void:
	if preview != null and state != null:
		preview.apply_state(state)
		preview.set_active(paperdoll_panel != null and paperdoll_panel.visible)
	_preview_signature = ""

func _refresh_preview() -> void:
	if preview == null or state == null:
		return
	var signature := JSON.stringify(state.equipped)
	if signature == _preview_signature:
		return
	_preview_signature = signature
	preview.apply_state(state)

## ---------------------------------------------------------------------------
## Backpack

func build_backpack(parent: Node) -> void:
	inventory_panel = _panel(parent,Vector2(16,338),Vector2(1248,250))
	_label(inventory_panel,"BACKPACK",Vector2(10,6),11,GOLD)
	_backpack_count = _label(inventory_panel,"",Vector2(86,7),11,CREAM)
	_backpack_count.size = Vector2(100,18)
	_selected_label = _label(inventory_panel,"No piece selected",Vector2(186,8),10,MUTED)
	_selected_label.size = Vector2(560,16)
	_selected_label.clip_text = true
	_primary = _button(inventory_panel,"",Vector2(826,5),Vector2(112,28))
	_primary.add_theme_font_size_override("font_size",11)
	_primary.pressed.connect(_on_primary)
	_secondary = _button(inventory_panel,"",Vector2(946,5),Vector2(112,28))
	_secondary.add_theme_font_size_override("font_size",11)
	_secondary.pressed.connect(_on_secondary)
	_tertiary = _button(inventory_panel,"",Vector2(1066,5),Vector2(112,28))
	_tertiary.add_theme_font_size_override("font_size",11)
	_tertiary.pressed.connect(_on_tertiary)
	_floor_label = _label(inventory_panel,"GROUND  •  nothing dropped",Vector2(10,38),9,MUTED)
	_floor_scroll = ScrollContainer.new()
	_floor_scroll.position = Vector2(64,34)
	_floor_scroll.size = Vector2(1160,24)
	_floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_floor_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_panel.add_child(_floor_scroll)
	_floor_list = HBoxContainer.new()
	_floor_list.add_theme_constant_override("separation",3)
	_floor_scroll.add_child(_floor_list)
	for index in StateScript.INVENTORY_CAPACITY:
		var column := index % COLUMNS
		var row := index / COLUMNS
		var at := GRID_ORIGIN + Vector2(column * (SLOT_SIZE.x + SLOT_GAP.x),row * (SLOT_SIZE.y + SLOT_GAP.y))
		var button := _make_slot(inventory_panel,"backpack",index,"",at,SLOT_SIZE,11)
		button.expand_icon = true
		button.text = ""
		backpack_buttons.append(button)
	_status = _label(inventory_panel,"",Vector2(10,236),10,TEAL)
	_status.size = Vector2(1228,14)
	_status.clip_text = true

## ---------------------------------------------------------------------------
## Stash / keeper stock

static func stock_row_count() -> int:
	var largest := 0
	for vendor in StateScript.VENDORS:
		largest = maxi(largest, (vendor.stock as Array).size())
	return largest

func build_side(parent: Node) -> void:
	side_panel = _panel(parent,Vector2(16,50),Vector2(1248,280))
	_side_title = _label(side_panel,"",Vector2(12,8),11,GOLD)
	_side_sub = _label(side_panel,"",Vector2(12,24),9,MUTED)
	_side_sub.size = Vector2(800,18)
	_side_sub.clip_text = true
	_stash_count = _label(side_panel,"",Vector2(1120,8),11,CREAM)
	_stash_count.size = Vector2(110,18)
	_stash_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index in 20:
		var column := index % 5
		var row := index / 5
		var button := _make_slot(side_panel,"stash",index,"",
			Vector2(33+column*238,36+row*60),Vector2(230,54),11)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width",40)
		stash_buttons.append(button)
	_stock_scroll = ScrollContainer.new()
	_stock_scroll.position = Vector2(12,32)
	_stock_scroll.size = Vector2(1224,166)
	_stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(_stock_scroll)
	_stock_list = VBoxContainer.new()
	_stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_list.add_theme_constant_override("separation",3)
	_stock_scroll.add_child(_stock_list)
	# One row per keeper stock entry: the pool is sized from the largest vendor
	# so a longer list can never silently lose its last pieces.
	for index in stock_row_count():
		var button := _make_slot(_stock_list,"stock",index,"",Vector2.ZERO,Vector2(1210,28),10)
		button.custom_minimum_size = Vector2(0,28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width",20)
		stock_buttons.append(button)
	_buy = _button(side_panel,"BUY",Vector2(12,204),Vector2(1224,28))
	_buy.add_theme_font_size_override("font_size",11)
	_buy.pressed.connect(_on_buy)

## ---------------------------------------------------------------------------
## Refresh

func _refresh_paperdoll() -> void:
	for index in paperdoll_buttons.size():
		var button := paperdoll_buttons[index]
		var slot_name: String = Rules.SLOTS[index]
		var item_id: String = state.equipped_id(slot_name)
		button.item = item_id
		button.index = -1
		button.slot = slot_name
		var icon := ItemArt.texture(item_id)
		button.icon = icon
		var label := str(Rules.SLOT_LABELS.get(slot_name,slot_name))
		if index >= 5 and index <= 7:
			button.text = ""
			var trinket_label := _trinket_labels[index - 5]
			trinket_label.text = state.item_short(item_id).to_upper() if not item_id.is_empty() else "EMPTY"
			trinket_label.add_theme_color_override("font_color",CREAM if not item_id.is_empty() else MUTED)
			button.tooltip_text = state.item_name(item_id) if not item_id.is_empty() else "%s — nothing equipped" % label
		elif item_id.is_empty():
			button.text = "%s  •  EMPTY" % label.to_upper()
			button.tooltip_text = "%s — nothing equipped" % label
		else:
			button.text = "%s  •  %s" % [label.to_upper(),state.item_short(item_id)]
			button.tooltip_text = state.item_name(item_id)
		button.set_pressed_no_signal(_location == "paperdoll" and _slot == slot_name)
	_quick_label.text = "TAB  " + state.quick_set_label()
	if state.has_quick_return():
		_quick_label.text += "  ↔  " + state.quick_return_label()

func _refresh_backpack() -> void:
	for index in backpack_buttons.size():
		var button := backpack_buttons[index]
		button.index = index
		button.slot = ""
		if index < state.inventory.size():
			var item_id: String = state.inventory[index]
			button.item = item_id
			var icon := ItemArt.texture(item_id)
			button.icon = icon
			button.text = "" if icon != null else state.item_short(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.item = ""
			button.icon = null
			button.text = ""
			button.tooltip_text = ""
		button.set_pressed_no_signal(_location == "backpack" and index == _index)

func _refresh_stash() -> void:
	for index in stash_buttons.size():
		var button := stash_buttons[index]
		button.index = index
		if index < state.stash.size():
			var item_id: String = state.stash[index]
			button.item = item_id
			var icon := ItemArt.texture(item_id)
			button.icon = icon
			button.text = "   " + state.item_name(item_id)
			button.tooltip_text = state.item_name(item_id)
		else:
			button.item = ""
			button.icon = null
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
		var button := _make_slot(_floor_list,"floor",index,"",Vector2.ZERO,Vector2(120,24),8)
		button.custom_minimum_size = Vector2(120,24)
		button.item = item_id
		button.icon = ItemArt.texture(item_id)
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width",18)
		button.text = "  " + state.item_short(item_id)
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
			button.icon = ItemArt.texture(item_id)
			button.text = "  %s   %d c" % [state.item_name(item_id),state.item_price(item_id)]
			button.tooltip_text = state.item_detail(item_id)
			button.set_pressed_no_signal(_location == "stock" and _stock_item == item_id)
		else:
			button.visible = false
			button.disabled = true
			button.item = ""
			button.icon = null
			button.text = ""

func _refresh_stats() -> void:
	if state == null or _stat_values.is_empty():
		return
	_stat_values["attack"].text = state.main_attack_text()
	_stat_values["defense"].text = "%d%%" % state.defense_percent()
	_stat_values["life"].text = str(state.life_value())
	_stat_values["stamina"].text = str(state.stamina_value())
	for child in _bonus_list.get_children():
		_bonus_list.remove_child(child)
		child.queue_free()
	var rows: Array = state.kit_bonus_rows()
	if rows.is_empty():
		var none := Label.new()
		none.text = "No worn modifiers."
		none.add_theme_font_size_override("font_size",10)
		none.add_theme_color_override("font_color",MUTED)
		_bonus_list.add_child(none)
		return
	for entry: Dictionary in rows:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(entry.get("label",""))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",9)
		label.add_theme_color_override("font_color",MUTED)
		row.add_child(label)
		var value := Label.new()
		value.text = str(entry.get("value",""))
		value.add_theme_font_size_override("font_size",10)
		value.add_theme_color_override("font_color",TEAL)
		row.add_child(value)
		_bonus_list.add_child(row)

func _refresh_selection() -> void:
	var item_id := _selected_item()
	_primary.visible = false
	_secondary.visible = false
	_tertiary.visible = false
	_buy.disabled = true
	if item_id.is_empty():
		_selected_label.text = "No piece selected"
		return
	_selected_label.text = "%s   •   %s" % [state.item_name(item_id),state.item_type_line(item_id)]
	_buy.disabled = state.inventory_full() or int(state.credits) < state.item_price(item_id)
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
		"stash":
			_primary.visible = true
			_primary.text = "TO INVENTORY"
			_primary.disabled = state.inventory_full()
			_primary.tooltip_text = "Backpack is full." if state.inventory_full() else ""
		"floor":
			_primary.visible = true
			_primary.text = "PICK UP"
			_primary.disabled = state.inventory_full()
			_primary.tooltip_text = "Backpack is full." if state.inventory_full() else ""
		"stock":
			_buy.text = "BUY  /  %d c" % state.item_price(item_id)
	if _location != "stock":
		_buy.disabled = true
	if _location == "backpack" and view != "stash":
		_secondary.visible = false

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

## ---------------------------------------------------------------------------
## Actions

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
