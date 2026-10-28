class_name LedgerKeycap
extends PanelContainer
## A carved bone key tile. Used beside the words it belongs to (TAB, G, F1…);
## the tile is a nine-slice, so a one-letter key and a TAB are the same asset.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")

const INK := Color("2c1e12")


func _init(text: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxTexture.new()
	box.texture = load(Ledger.DIR + "keycap.png")
	box.texture_margin_left = 16
	box.texture_margin_right = 16
	box.texture_margin_top = 16
	box.texture_margin_bottom = 16
	box.content_margin_left = 11
	box.content_margin_right = 11
	box.content_margin_top = 4
	box.content_margin_bottom = 6
	add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Ledger.FONT_BODY)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	custom_minimum_size = Vector2(maxf(34.0, label.get_minimum_size().x + 24.0), 34.0)
