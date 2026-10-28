class_name LedgerTheme
extends RefCounted
## The one Theme every menu shares: the Blood Ledger's plates, fonts and inks.
##
## Built once, cached, and assigned to the root Control of a menu; every Button
## and Label underneath inherits it. `PrimaryButton` (brass) marks the one action
## a screen is really for, `DangerButton` (lacquer) the ways out, and the plain
## `Button` is the iron secondary. Geometry and copy live in the screens; this
## file owns only the skin.

const DIR := "res://assets/ui/theme/"
const FONT_BODY: FontFile = preload("res://assets/ui/fonts/IMFellEnglish-Regular.ttf")
const FONT_ITALIC: FontFile = preload("res://assets/ui/fonts/IMFellEnglish-Italic.ttf")
const FONT_DISPLAY: FontFile = preload("res://assets/ui/fonts/PirataOne-Regular.ttf")

const INK := Color("2b1c10")
const INK_SOFT := Color("4a321d")
const INK_MUTED := Color("684e34")
const BLOOD := Color("761819")
const BONE := Color("e9e0c9")
const BONE_DIM := Color("cbbfa7")
const TEAL := Color("2a5c52")
const EMBER := Color("7c3e12")
const BRASS_TEXT := Color("24180a")

const PLATE_MARGIN := Vector2i(20, 12)

static var _cached: Theme


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var theme := Theme.new()
	theme.default_font = FONT_BODY
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", INK)

	_button(theme, "Button", "iron")
	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", BONE)
	theme.set_color("font_pressed_color", "Button", BONE_DIM)
	theme.set_color("font_disabled_color", "Button", Color(0.56, 0.52, 0.46))
	theme.set_font("font", "Button", FONT_BODY)
	theme.set_font_size("font_size", "Button", 15)

	theme.set_type_variation("PrimaryButton", "Button")
	_button(theme, "PrimaryButton", "brass")
	theme.set_color("font_color", "PrimaryButton", BRASS_TEXT)
	theme.set_color("font_hover_color", "PrimaryButton", BRASS_TEXT)
	theme.set_color("font_pressed_color", "PrimaryButton", BRASS_TEXT)
	theme.set_color("font_disabled_color", "PrimaryButton", Color(0.35, 0.33, 0.30))
	theme.set_font("font", "PrimaryButton", FONT_BODY)
	theme.set_font_size("font_size", "PrimaryButton", 15)

	theme.set_type_variation("DangerButton", "Button")
	_button(theme, "DangerButton", "lacquer")
	theme.set_color("font_color", "DangerButton", BONE)
	theme.set_color("font_hover_color", "DangerButton", BONE)
	theme.set_color("font_pressed_color", "DangerButton", BONE_DIM)
	theme.set_color("font_disabled_color", "DangerButton", Color(0.45, 0.42, 0.38))
	theme.set_font("font", "DangerButton", FONT_BODY)
	theme.set_font_size("font_size", "DangerButton", 15)

	theme.set_type_variation("DisplayLabel", "Label")
	theme.set_font("font", "DisplayLabel", FONT_DISPLAY)
	theme.set_color("font_color", "DisplayLabel", INK)

	theme.set_type_variation("IronLabel", "Label")
	theme.set_color("font_color", "IronLabel", BONE)

	# Option buttons and text fields wear the same plates as the rest.
	theme.set_stylebox("normal", "OptionButton", _plate("iron", "idle"))
	theme.set_stylebox("hover", "OptionButton", _plate("iron", "hover"))
	theme.set_stylebox("pressed", "OptionButton", _plate("iron", "pressed"))
	theme.set_stylebox("disabled", "OptionButton", _plate("iron", "disabled"))
	theme.set_stylebox("focus", "OptionButton", _plate("iron", "hover"))
	theme.set_color("font_color", "OptionButton", BONE)
	theme.set_color("font_hover_color", "OptionButton", BONE)
	theme.set_color("font_pressed_color", "OptionButton", BONE_DIM)
	theme.set_color("font_disabled_color", "OptionButton", Color(0.56, 0.52, 0.46))
	theme.set_font("font", "OptionButton", FONT_BODY)
	theme.set_font_size("font_size", "OptionButton", 13)

	theme.set_stylebox("normal", "LineEdit", _plate("iron", "idle"))
	theme.set_stylebox("focus", "LineEdit", _plate("iron", "hover"))
	theme.set_stylebox("read_only", "LineEdit", _plate("iron", "disabled"))
	theme.set_color("font_color", "LineEdit", BONE)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.62, 0.58, 0.50))
	theme.set_font("font", "LineEdit", FONT_BODY)
	theme.set_font_size("font_size", "LineEdit", 14)

	var menu_box := StyleBoxFlat.new()
	menu_box.bg_color = Color(0.09, 0.075, 0.06, 0.98)
	menu_box.border_color = Color(0.58, 0.45, 0.25, 0.9)
	menu_box.set_border_width_all(1)
	menu_box.content_margin_left = 8
	menu_box.content_margin_right = 8
	menu_box.content_margin_top = 6
	menu_box.content_margin_bottom = 6
	theme.set_stylebox("panel", "PopupMenu", menu_box)
	theme.set_color("font_color", "PopupMenu", BONE_DIM)
	theme.set_color("font_hover_color", "PopupMenu", BONE)
	theme.set_stylebox("hover", "PopupMenu", _plate("brass", "hover"))

	# A vellum panel for inner blocks (a stash well, a note).
	var note := StyleBoxFlat.new()
	note.bg_color = Color(0.10, 0.08, 0.06, 0.06)
	note.border_color = Color(0.38, 0.29, 0.19, 0.45)
	note.set_border_width_all(1)
	note.content_margin_left = 12
	note.content_margin_right = 12
	note.content_margin_top = 10
	note.content_margin_bottom = 10
	theme.set_stylebox("panel", "PanelContainer", note)

	_cached = theme
	return theme


static func _button(theme: Theme, type: String, variant: String) -> void:
	for state in ["idle", "hover", "pressed", "disabled"]:
		theme.set_stylebox(_style_key(state), type, _plate(variant, state))
	theme.set_stylebox("focus", type, _plate(variant, "hover"))


static func _style_key(state: String) -> String:
	match state:
		"hover":
			return "hover"
		"pressed":
			return "pressed"
		"disabled":
			return "disabled"
	return "normal"


static func _plate(variant: String, state: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(DIR + "plate_%s_%s.png" % [variant, state])
	box.texture_margin_left = PLATE_MARGIN.x
	box.texture_margin_right = PLATE_MARGIN.x
	box.texture_margin_top = PLATE_MARGIN.y
	box.texture_margin_bottom = PLATE_MARGIN.y
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## A nine-slice iron slab for panels that are not the vellum page (title, lobby).
static func iron_panel() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(DIR + "plate_iron_idle.png")
	box.texture_margin_left = 20
	box.texture_margin_right = 20
	box.texture_margin_top = 12
	box.texture_margin_bottom = 12
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box


static func plate_texture(variant: String, state: String) -> Texture2D:
	return load(DIR + "plate_%s_%s.png" % [variant, state])


static func icon_large(key: String) -> Texture2D:
	return load(DIR + "icon_lg_%s.png" % key)


static func icon_small(key: String) -> Texture2D:
	return load(DIR + "icon_sm_%s.png" % key)
