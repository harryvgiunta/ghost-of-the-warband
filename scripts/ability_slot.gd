extends Panel
## One HUD ability slot: icon, keybind, stamina cost, active state and cooldown.
##
## The granted skill follows the held item, so the slot starts empty and takes
## its icon, name and key from the first state update. Every mode places the
## same control, so a new item skill only needs a definition and an icon.
##
## Two measures, one design. `configure(slot, extent)` lays the tile out from
## that one number: at 96 it is the full card (icon, key, name, cost), and below
## `COMPACT` it is a hotbar key - a half-size icon, the slot number under it and
## a glyph when the skill has no art yet.

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
var _compact := false

## The square the tile is built at when the caller asks for none: one arena tile.
const TILE := 96.0
## At or below this the tile drops the name and cost lines and becomes a hotbar
## key. The warband asks for 40: ten of them, with a 26 px icon, fit under the
## soul's plate without taking the screen the fight needs.
const COMPACT := 52.0
## The icon is half the full tile's 52 px in the compact measure.
const COMPACT_ICON := 26.0


## Lay the tile out at `extent` pixels square. Every child is placed and sized off
## that one number, so a smaller tile is the same design at another measure rather
## than a second layout: at 96 the icon is 52, the key 84 x 13 under it and the
## name 88 x 14 beneath that; at 40 it is the hotbar key described above.
func configure(slot: int, extent: float = TILE) -> void:
	_slot = slot
	var box := maxf(24.0, extent)
	_compact = box <= COMPACT
	custom_minimum_size = Vector2(box, box)
	size = Vector2(box, box)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.045,0.095,0.12,0.92)
	_style.border_color = Color("58716b")
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(3 if _compact else 8)
	add_theme_stylebox_override("panel",_style)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	if _compact:
		_icon.position = Vector2(floorf((box - COMPACT_ICON) * 0.5), 2.0)
		_icon.size = Vector2(COMPACT_ICON, COMPACT_ICON)
		# The number is the slot, not the authored key: the hotbar is 1..10.
		_key = _label(Vector2(0, box - 11.0), Vector2(box, 11.0), 9, MUTED)
		_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cooldown = _label(Vector2(0, 2.0), Vector2(box, COMPACT_ICON),
			maxi(10, roundi(box * 0.30)), CREAM)
		_cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cooldown.visible = false
		# A welded skill can exist before its art does. The name's initials are
		# the glyph that keeps such a tile from reading as an empty slot.
		_name = _label(Vector2(1, 1), Vector2(box - 2, COMPACT_ICON),
			maxi(9, roundi(box * 0.28)), GOLD)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name.clip_text = true
		_name.visible = false
		_cost = _label(Vector2(0, 0), Vector2.ZERO, 8, GOLD)
		_cost.visible = false
	else:
		var k := box / TILE
		_icon.position = Vector2(22,8) * k
		_icon.size = Vector2(52,52) * k
		_cooldown = _label(Vector2(20,10) * k,Vector2(56,48) * k,maxi(11,roundi(20.0 * k)),CREAM)
		_cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cooldown.visible = false
		_key = _label(Vector2(6,64) * k,Vector2(84,13) * k,maxi(8,roundi(10.0 * k)),MUTED)
		# The name owns the bottom row so a long skill name is not clipped; the
		# cost rides the icon's top-right corner instead.
		_name = _label(Vector2(6,78) * k,Vector2(88,14) * k,maxi(8,roundi(10.0 * k)),GOLD)
		_cost = _label(Vector2(66,8) * k,Vector2(26,12) * k,maxi(8,roundi(9.0 * k)),GOLD)
		_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	visible = false


func update_state(state: Dictionary) -> void:
	if _icon == null:
		return
	if state.is_empty():
		# A compact tile is a hotbar key: an empty slot keeps its frame and its
		# number, so the row reads as ten slots and a new grant fills one. The
		# full card has no empty state - it hides instead of advertising nothing.
		_definition = {}
		_icon.texture = null
		_cooldown.visible = false
		_cost.visible = false
		_name.visible = false
		_icon.modulate = Color.WHITE
		if _style != null:
			_style.border_color = Color("3a4a47")
		if _compact:
			_key.text = str(_slot + 1)
			visible = true
		else:
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
		var texture := AbilityRules.icon_texture(id)
		_icon.texture = texture
		_name.text = _acronym(str(_definition.get("name", ""))) if _compact \
			else str(_definition.get("name", ""))
		if _compact:
			_key.text = str(_slot + 1)
			_name.visible = texture == null
		else:
			_key.text = str(_definition.get("key", ""))
			_name.visible = true
	visible = true
	var cooldown := float(state.get("cooldown",0.0))
	var active := bool(state.get("active",false))
	var affordable := bool(state.get("affordable",true))
	var cost := int(float(state.get("stamina_cost",_definition.get("stamina_cost",0.0))))
	if not _compact:
		_cost.text = "-%d" % cost
	if _style != null:
		_style.border_color = GOLD if active else Color("58716b")
	if active:
		_cooldown.visible = false
		_icon.modulate = Color.WHITE
	elif cooldown > 0.05:
		_cooldown.visible = true
		_cooldown.text = "%.1f" % cooldown if not _compact else "%d" % ceili(cooldown)
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


## "TFV" for Triple Fan Volley, "BAR" for a one-word name: the stand-in glyph a
## tile with no icon texture draws.
func _acronym(text: String) -> String:
	var words := text.replace("'", "").split(" ", false)
	if words.size() == 1:
		return words[0].substr(0, 3).to_upper()
	var out := ""
	for word in words:
		out += word.substr(0, 1)
		if out.length() >= 3:
			break
	return out.to_upper()


func _label(at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
