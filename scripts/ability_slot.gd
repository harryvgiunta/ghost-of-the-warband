extends Panel
## One HUD ability slot: icon, keybind, stamina cost, active state and cooldown.
##
## The granted skill follows the held item, so the slot starts empty and takes
## its icon, name and key from the first state update. Every mode places the
## same control, so a new item skill only needs a definition and an icon.

const AbilityRules = preload("res://scripts/ability_rules.gd")
const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const ERROR := Color("d97a68")

var _definition: Dictionary = {}
var _style: StyleBoxFlat
var _icon: TextureRect
var _cooldown: Label
var _key: Label
var _name: Label
var _cost: Label
var _slot := 0


func configure(slot: int) -> void:
	_slot = slot
	custom_minimum_size = Vector2(96,96)
	size = Vector2(96,96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.045,0.095,0.12,0.92)
	_style.border_color = Color("58716b")
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel",_style)
	_icon = TextureRect.new()
	_icon.position = Vector2(22,8)
	_icon.size = Vector2(52,52)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_cooldown = _label(Vector2(20,10),Vector2(56,48),20,CREAM)
	_cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cooldown.visible = false
	_key = _label(Vector2(6,64),Vector2(84,13),10,MUTED)
	_name = _label(Vector2(6,78),Vector2(60,14),10,GOLD)
	_cost = _label(Vector2(52,78),Vector2(38,14),10,GOLD)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	visible = false


func update_state(state: Dictionary) -> void:
	if _icon == null:
		return
	if state.is_empty():
		visible = false
		return
	var id := str(state.get("id", ""))
	if id != str(_definition.get("id", "")):
		_definition = AbilityRules.by_id(id)
		if _definition.is_empty():
			# A replica without the definition table cannot draw a meaningful
			# tile; hide instead of showing a stale skill.
			visible = false
			return
		_icon.texture = AbilityRules.icon_texture(id)
		_key.text = str(_definition.get("key", ""))
		_name.text = str(_definition.get("name", ""))
	visible = true
	var cooldown := float(state.get("cooldown",0.0))
	var active := bool(state.get("active",false))
	var affordable := bool(state.get("affordable",true))
	var cost := int(float(state.get("stamina_cost",_definition.get("stamina_cost",0.0))))
	_cost.text = "-%d" % cost
	if _style != null:
		_style.border_color = GOLD if active else Color("58716b")
	if active:
		_cooldown.visible = false
		_icon.modulate = Color.WHITE
	elif cooldown > 0.05:
		_cooldown.visible = true
		_cooldown.text = "%.1f" % cooldown
		_cooldown.add_theme_color_override("font_color",CREAM)
		_icon.modulate = Color(0.45,0.52,0.54,0.9)
	elif not affordable:
		_cooldown.visible = true
		_cooldown.text = "LOW"
		_cooldown.add_theme_color_override("font_color",ERROR)
		_icon.modulate = Color(0.55,0.55,0.55,0.9)
	else:
		_cooldown.visible = false
		_icon.modulate = Color.WHITE


func _label(at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
