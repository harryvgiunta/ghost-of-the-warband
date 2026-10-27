extends PanelContainer
## One hover card for every item slot in the kit UI.
##
## Typographic, like the ARPG cards this reads as: centered gold title, the
## type line beneath it, Speed and Damage only when the piece is a weapon, the
## extra modifiers as bullet rows, and the item's quote in italic at the foot.
## The card is sized by its content (a minimum reading width, no fixed height),
## so a short card stays short. The slot already carries the screenshot.

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const MIN_WIDTH := 240.0
## The panel margin is 12 px each side; wrapping must be measured at the
## inner width or a Label reports a one-character-wide, screen-tall minimum.
const CONTENT_WIDTH := MIN_WIDTH - 24.0

var state
var _italic: SystemFont


func configure(player_state,item_id: String) -> void:
	state = player_state
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A tooltip is shown inside Godot's tooltip container: without SHRINK the
	# panel is stretched to the container's full height and a two-line card
	# becomes a screen-tall black column. Keep both axes at the content size.
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(MIN_WIDTH,0)
	add_theme_stylebox_override("panel",_panel_style())
	var card_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift","Segoe UI"])
	card_theme.default_font = font
	theme = card_theme
	_italic = SystemFont.new()
	_italic.font_names = PackedStringArray(["Georgia","Palatino Linotype","Times New Roman"])
	_italic.font_italic = true
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",12)
	margin.add_theme_constant_override("margin_right",12)
	margin.add_theme_constant_override("margin_top",11)
	margin.add_theme_constant_override("margin_bottom",11)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.custom_minimum_size.x = CONTENT_WIDTH
	margin.add_child(column)
	_title(column,state.item_name(item_id))
	_type_line(column,state.item_type_text(item_id))
	var category: String = str(state.item_category(item_id))
	var weapon := category in ["1h","2h","bow","staff"]
	if weapon:
		_rule(column)
		_stat(column,"Speed",state.item_speed_text(item_id))
		_stat(column,"Damage",state.item_damage_text(item_id))
	var extras: Array = state.item_extra_rows(item_id)
	if not extras.is_empty():
		_rule(column)
		_heading(column,"EXTRA MODIFIERS")
		for entry: Dictionary in extras:
			_extra(column,str(entry.get("label","")),str(entry.get("value","")))
	var quote: String = str(state.item_quote(item_id))
	if not quote.is_empty():
		_rule(column)
		_quote(column,quote)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.030,0.058,0.066,0.985)
	style.border_color = Color("7c6a45")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0,0,0,0.6)
	style.shadow_size = 12
	return style


func _title(parent: Node,text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CONTENT_WIDTH
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_color",GOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _type_line(parent: Node,text: String) -> void:
	var label := Label.new()
	label.text = "Type:  " + text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CONTENT_WIDTH
	label.add_theme_font_size_override("font_size",9)
	label.add_theme_color_override("font_color",MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _heading(parent: Node,text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",9)
	label.add_theme_color_override("font_color",Color("8f7a56"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _stat(parent: Node,label_text: String,value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var key := Label.new()
	key.text = label_text + ":"
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.add_theme_font_size_override("font_size",12)
	key.add_theme_color_override("font_color",MUTED)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size",14)
	value.add_theme_color_override("font_color",CREAM)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)


func _extra(parent: Node,label_text: String,value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var bullet := Label.new()
	bullet.text = "◆"
	bullet.add_theme_font_size_override("font_size",8)
	bullet.add_theme_color_override("font_color",GOLD)
	bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bullet)
	var text := label_text + ("  " + value_text if not value_text.is_empty() else "")
	var line := Label.new()
	line.text = text
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = CONTENT_WIDTH - 16.0
	line.add_theme_font_size_override("font_size",11)
	line.add_theme_color_override("font_color",TEAL)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)


func _quote(parent: Node,text: String) -> void:
	var label := Label.new()
	label.text = "“%s”" % text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CONTENT_WIDTH
	label.add_theme_font_override("font",_italic)
	label.add_theme_font_size_override("font_size",12)
	label.add_theme_color_override("font_color",Color("c9b98f"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _rule(parent: Node) -> void:
	var rule := ColorRect.new()
	rule.color = Color("4a4232")
	rule.custom_minimum_size = Vector2(0,1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
