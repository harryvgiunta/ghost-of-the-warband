extends PanelContainer
## The arena's board, and nothing else: three plates for how hard the ring is,
## and one press to step into it.
##
## It is deliberately thinner than the delve's page - the ring takes no pack and
## no party selection, because the whole field goes in and comes back - so the
## only two decisions are the tier and the press. The scene opens it; the
## `fight_requested` signal is the world's.

signal fight_requested(tier: String)
signal closed()

const ArenaScript = preload("res://scripts/warband/arena_area.gd")

var _warband = null
var _arena = null
var _tier := ArenaScript.DEFAULT_DIFFICULTY
var _plates: Dictionary = {}
var _status: Label


func configure(warband_state, arena) -> void:
	_warband = warband_state
	_arena = arena
	if arena != null:
		_tier = str(arena.difficulty)
	_paint()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(420, 260)
	visible = false
	_build()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_paint()


func close() -> void:
	visible = false
	closed.emit()


func tier() -> String:
	return _tier


func select_tier(tier: String) -> bool:
	if not ArenaScript.DIFFICULTIES.has(tier):
		return false
	_tier = tier
	_paint()
	return true


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "THE ARENA"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var blurb := Label.new()
	blurb.text = "A mirrored warband, the same ten slots, the same skills. Nothing is kept but the purse."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(392, 0)
	blurb.add_theme_font_size_override("font_size", 12)
	box.add_child(blurb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for tier in ArenaScript.DIFFICULTIES:
		var plate := Button.new()
		plate.text = tier.to_upper()
		plate.custom_minimum_size = Vector2(124, 44)
		plate.pressed.connect(func() -> void: select_tier(tier))
		row.add_child(plate)
		_plates[tier] = plate

	var fight := Button.new()
	fight.text = "STEP INTO THE RING"
	fight.custom_minimum_size = Vector2(392, 46)
	fight.pressed.connect(func() -> void: fight_requested.emit(_tier))
	box.add_child(fight)

	var leave := Button.new()
	leave.text = "NOT TODAY"
	leave.pressed.connect(close)
	box.add_child(leave)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	box.add_child(_status)


func _paint() -> void:
	for tier in _plates.keys():
		var plate: Button = _plates[tier]
		plate.disabled = str(tier) == _tier
	if _status != null:
		_status.text = "THE RING  ·  %s" % _tier.to_upper()
