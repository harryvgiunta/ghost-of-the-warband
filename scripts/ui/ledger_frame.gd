class_name LedgerFrame
extends Control
## The one window: a forged iron clamp, a torn vellum page, a title rail with a
## brass medallion and a wax seal, and a body area for the screen's own content.
##
## Screens do not draw frames. They create a LedgerFrame, put their column in
## `body`, and the frame owns every edge, nail, seal and title. The clamp and the
## page are nine-slices, so one texture serves the tutorial card and the altar.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")

const INK := Color("2b1c10")
const BONE := Color("e9e0c9")

const CLAMP_MARGIN := 24
const PAGE_MARGIN := 56
const HEADER := 60
const PAGE_INSET := 24
const BODY_PAD_X := 40
const BODY_PAD_TOP := 30
const BODY_PAD_BOTTOM := 32

var body: MarginContainer
var title_label: Label

var _clamp: NinePatchRect
var _page: NinePatchRect
var _rail: NinePatchRect
var _shade: NinePatchRect
var _medallion: TextureRect
var _seal: TextureRect
var _seal_text: Label
var _built := false
var _title := ""
var _icon := "scroll"
var _stamp := ""


func _init() -> void:
	# Built at construction, not on `_ready`: a menu may be configured and laid
	# out before it enters the tree (tests do exactly that).
	_build()


func _ready() -> void:
	_build()
	_apply()
	set_process(true)


func _process(_delta: float) -> void:
	# A window on screen is a window that owns the pointer: the OS cursor must be
	# back the moment a menu is up, whatever the scene's input mode was. Hidden
	# frames cost nothing; a closed menu releases the pointer to the scene again.
	if not is_visible_in_tree():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Set the window's identity. Safe before or after the node enters the tree.
func configure(title_text: String, icon_key: String = "scroll",
		stamp_text: String = "") -> void:
	_title = title_text
	_icon = icon_key
	_stamp = stamp_text
	if _built:
		_apply()


func set_title(title_text: String) -> void:
	_title = title_text
	if _built:
		_apply()


func set_icon(icon_key: String) -> void:
	_icon = icon_key
	if _built:
		_apply()


func set_stamp(stamp_text: String) -> void:
	_stamp = stamp_text
	if _built:
		_apply()


func _build() -> void:
	if _built:
		return
	_built = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cast := Panel.new()
	cast.name = "CastShadow"
	cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cast_box := StyleBoxFlat.new()
	cast_box.bg_color = Color(0, 0, 0, 0)
	cast_box.shadow_color = Color(0, 0, 0, 0.55)
	cast_box.shadow_size = 22
	cast_box.corner_radius_top_left = 14
	cast_box.corner_radius_top_right = 14
	cast_box.corner_radius_bottom_left = 14
	cast_box.corner_radius_bottom_right = 14
	cast.add_theme_stylebox_override("panel", cast_box)
	add_child(cast)

	_clamp = NinePatchRect.new()
	_clamp.name = "Clamp"
	_clamp.texture = load(Ledger.DIR + "clamp.png")
	_clamp.patch_margin_left = CLAMP_MARGIN
	_clamp.patch_margin_right = CLAMP_MARGIN
	_clamp.patch_margin_top = CLAMP_MARGIN
	_clamp.patch_margin_bottom = CLAMP_MARGIN
	_clamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_clamp)

	_rail = NinePatchRect.new()
	_rail.name = "HeaderRail"
	_rail.texture = load(Ledger.DIR + "rail.png")
	_rail.patch_margin_left = 12
	_rail.patch_margin_right = 12
	_rail.patch_margin_top = 0
	_rail.patch_margin_bottom = 0
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rail.offset_left = PAGE_INSET
	_rail.offset_right = -PAGE_INSET
	_rail.offset_top = PAGE_INSET
	_rail.offset_bottom = PAGE_INSET + HEADER
	add_child(_rail)

	_page = NinePatchRect.new()
	_page.name = "Page"
	_page.texture = load(Ledger.DIR + "page.png")
	_page.patch_margin_left = PAGE_MARGIN
	_page.patch_margin_right = PAGE_MARGIN
	_page.patch_margin_top = PAGE_MARGIN
	_page.patch_margin_bottom = PAGE_MARGIN
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.offset_left = PAGE_INSET
	_page.offset_top = PAGE_INSET + HEADER
	_page.offset_right = -PAGE_INSET
	_page.offset_bottom = -PAGE_INSET
	add_child(_page)

	_shade = NinePatchRect.new()
	_shade.name = "PageShade"
	_shade.texture = load(Ledger.DIR + "page_shadow.png")
	_shade.patch_margin_left = 32
	_shade.patch_margin_right = 32
	_shade.patch_margin_top = 32
	_shade.patch_margin_bottom = 32
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.offset_left = PAGE_INSET
	_shade.offset_top = PAGE_INSET + HEADER
	_shade.offset_right = -PAGE_INSET
	_shade.offset_bottom = -PAGE_INSET
	add_child(_shade)

	_medallion = TextureRect.new()
	_medallion.name = "Medallion"
	_medallion.position = Vector2(16, 10)
	_medallion.size = Vector2(46, 46)
	_medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_medallion)

	title_label = Label.new()
	title_label.name = "WindowTitle"
	title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 14
	title_label.offset_bottom = 54
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", Ledger.FONT_DISPLAY)
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", BONE)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)

	_seal = TextureRect.new()
	_seal.name = "Seal"
	_seal.texture = load(Ledger.DIR + "seal.png")
	_seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_seal.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_seal.offset_left = -64
	_seal.offset_top = 8
	_seal.offset_right = -18
	_seal.offset_bottom = 54
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seal)

	_seal_text = Label.new()
	_seal_text.name = "SealMark"
	_seal_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_seal_text.offset_left = -64
	_seal_text.offset_top = 18
	_seal_text.offset_right = -18
	_seal_text.offset_bottom = 44
	_seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seal_text.add_theme_font_override("font", Ledger.FONT_DISPLAY)
	_seal_text.add_theme_font_size_override("font_size", 15)
	_seal_text.add_theme_color_override("font_color", Color(0.95, 0.86, 0.76, 0.92))
	_seal_text.add_theme_color_override("font_shadow_color", Color(0.10, 0.01, 0.02, 0.85))
	_seal_text.add_theme_constant_override("shadow_offset_x", 1)
	_seal_text.add_theme_constant_override("shadow_offset_y", 1)
	_seal_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seal_text)

	body = MarginContainer.new()
	body.name = "Body"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = PAGE_INSET + BODY_PAD_X
	body.offset_top = PAGE_INSET + HEADER + BODY_PAD_TOP
	body.offset_right = -(PAGE_INSET + BODY_PAD_X)
	body.offset_bottom = -(PAGE_INSET + BODY_PAD_BOTTOM)
	add_child(body)


func _apply() -> void:
	if not _built:
		return
	title_label.text = _title.to_upper()
	title_label.visible = not _title.is_empty()
	_medallion.texture = Ledger.icon_large(_icon)
	_medallion.visible = not _icon.is_empty()
	_seal_text.text = _stamp
	_seal.visible = true
	_seal_text.visible = not _stamp.is_empty()
