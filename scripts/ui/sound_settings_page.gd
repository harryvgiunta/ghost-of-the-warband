class_name SoundSettingsPage
extends VBoxContainer
## The sound page: a level and a mute for the score and for everything else.
##
## One implementation, two windows - the campaign's Escape settings and the
## frontier's quick menu - and one source of truth, the `Audio` autoload. Every
## move here is a call on that manager and every number painted is read back
## from it, so a slider, a mute button and the mix on disk cannot disagree.
##
## It is built from `Label`, `Button` and one `HSlider` per row, with no texture
## of its own, so it constructs, opens and is driven inside a headless regression
## exactly as it does on screen.

signal changed

const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

var music_slider: HSlider
var sfx_slider: HSlider
var music_mute: Button
var sfx_mute: Button

var _values: Dictionary = {}
var _built := false


func _ready() -> void:
	_build()
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 10)
	# The mix hierarchy the game is built on: music is the bed, effects are
	# information. The page says so, because muting the wrong row is the
	# commonest mistake a sound page collects.
	var hint := _label("Music is the score. Effects are every blow, step and latch.",
		12, LedgerThemeScript.INK_MUTED)
	# One line, clipped. An autowrapping label in a hidden page reports the height
	# of its narrowest possible column, which is how a page the player cannot see
	# used to push the visible page's own buttons off the frame.
	hint.clip_text = true
	add_child(hint)

	music_slider = HSlider.new()
	music_slider.name = "MusicSlider"
	music_slider.min_value = 0.0
	music_slider.max_value = 100.0
	music_slider.step = 1.0
	music_slider.custom_minimum_size = Vector2(0, 28)
	music_slider.value_changed.connect(_on_level_changed.bind("music"))
	music_mute = _mute_button(_row("MUSIC", music_slider, "music"), "music")

	sfx_slider = HSlider.new()
	sfx_slider.name = "SfxSlider"
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 100.0
	sfx_slider.step = 1.0
	sfx_slider.custom_minimum_size = Vector2(0, 28)
	sfx_slider.value_changed.connect(_on_level_changed.bind("sfx"))
	sfx_mute = _mute_button(_row("SOUND EFFECTS", sfx_slider, "sfx"), "sfx")

	refresh()


## Repaint every control from the manager.
func refresh() -> void:
	_build()
	var audio := _audio()
	var music := float(audio.music_volume) if audio != null else 0.8
	var sfx := float(audio.sfx_volume) if audio != null else 0.8
	music_slider.set_value_no_signal(round(music * 100.0))
	sfx_slider.set_value_no_signal(round(sfx * 100.0))
	_paint("music", music, audio != null and bool(audio.music_muted), music_mute)
	_paint("sfx", sfx, audio != null and bool(audio.sfx_muted), sfx_mute)


## The numbers this page is showing, for a regression to compare with the mixer.
func values() -> Dictionary:
	return {
		"music": float(music_slider.value) / 100.0 if music_slider != null else 0.0,
		"sfx": float(sfx_slider.value) / 100.0 if sfx_slider != null else 0.0,
		"music_muted": _is_muted("music"),
		"sfx_muted": _is_muted("sfx"),
	}


# --- rows ------------------------------------------------------------------

## One row: the label, the slider, the percentage and the mute plate.
func _row(title: String, slider: HSlider, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % key
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var label := _label(title, 13, LedgerThemeScript.BLOOD)
	label.custom_minimum_size = Vector2(150, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_stain(slider)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var amount := _label("", 13, LedgerThemeScript.INK)
	amount.custom_minimum_size = Vector2(54, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(amount)
	_values[key] = amount
	return row


func _mute_button(row: HBoxContainer, key: String) -> Button:
	var button := Button.new()
	button.name = "Mute_%s" % key
	button.custom_minimum_size = Vector2(96, 32)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_mute_pressed.bind(key))
	row.add_child(button)
	return button


## The shared plate rack has no slider in it, so the trough and the fill wear the
## ledger's own inks: an ink channel and a blood bar.
func _stain(slider: HSlider) -> void:
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color("241a10")
	trough.set_corner_radius_all(3)
	trough.content_margin_top = 3
	trough.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", trough)
	var fill := StyleBoxFlat.new()
	fill.bg_color = LedgerThemeScript.BLOOD
	fill.set_corner_radius_all(3)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


# --- moves -----------------------------------------------------------------

func _on_level_changed(value: float, key: String) -> void:
	var audio := _audio()
	if audio != null:
		if key == "music":
			audio.set_music_volume(value / 100.0)
		else:
			audio.set_sfx_volume(value / 100.0)
	refresh()
	changed.emit()


func _on_mute_pressed(key: String) -> void:
	var audio := _audio()
	if audio != null:
		if key == "music":
			audio.toggle_music_muted()
		else:
			audio.toggle_sfx_muted()
	refresh()
	changed.emit()
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("settings", "mute", values())


func _is_muted(key: String) -> bool:
	var audio := _audio()
	if audio == null:
		return false
	return bool(audio.music_muted) if key == "music" else bool(audio.sfx_muted)


func _paint(key: String, level: float, muted: bool, button: Button) -> void:
	var label: Label = _values.get(key)
	if label != null:
		label.text = "%d%%" % int(round(level * 100.0))
		label.add_theme_color_override("font_color",
			LedgerThemeScript.INK_MUTED if muted else LedgerThemeScript.INK)
	if button != null:
		button.text = "MUTED" if muted else "MUTE"
		button.theme_type_variation = "DangerButton" if muted else ""


## A bare label. The caller parents it, because a row owns its own cells.
func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _audio() -> Node:
	return get_node_or_null("/root/Audio")
