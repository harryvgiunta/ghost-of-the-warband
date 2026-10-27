class_name InventorySlot
extends Button
## One equipment, backpack, stash, vendor or floor cell.
## A press selects it, dragging carries {area,index,slot,item} and a right-click
## asks the hub for the context action. The hub never mutates PlayerState here.

signal drag_started()
signal right_clicked(area: String, index: int, slot: String, item: String)
signal slot_dropped(payload: Dictionary)

var area := ""
var index := -1
var slot := ""
var item := ""
var display_name := ""
var drag_enabled := true
## Optional (item_id, area) -> Control builder supplied by the hub.
var tooltip_builder: Callable

func configure(area_name: String, slot_index: int, slot_name: String, item_id: String) -> void:
	area = area_name
	index = slot_index
	slot = slot_name
	item = item_id

func payload() -> Dictionary:
	return {"area":area, "index":index, "slot":slot, "item":item}

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled or item.is_empty():
		return null
	drag_started.emit()
	var preview := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	if icon != null:
		var art := TextureRect.new()
		art.texture = icon
		art.custom_minimum_size = Vector2(44,44)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(art)
	var label := Label.new()
	label.text = display_name if not display_name.is_empty() else (tooltip_text if not tooltip_text.is_empty() else text)
	label.add_theme_font_size_override("font_size",11)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	preview.add_child(row)
	set_drag_preview(preview)
	return payload()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("area") and not str(data.get("item","")).is_empty()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		slot_dropped.emit(data)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(area,index,slot,item)
		accept_event()

func _make_custom_tooltip(for_text: String) -> Object:
	if tooltip_builder.is_valid() and not item.is_empty():
		var custom: Variant = tooltip_builder.call(item,area)
		if custom is Control:
			return custom
	var label := Label.new()
	label.text = for_text
	label.add_theme_font_size_override("font_size",12)
	return label
