class_name WarbandHud
extends CanvasLayer
## The in-battle readout for a possession game: the body you are inside, the
## squad you can jump into, and the one prompt that matters right now.
##
## It owns no gameplay state: `set_body()` is called by the scene whenever the
## soul moves and every value is re-read each frame, so a revive, a loot or a
## downed body is never a stale label. The tactical screen (TAB) is
## `WarbandScreen`; this is the thin layer you read while fighting.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")

const LAYER := 6
const BAR_SIZE := Vector2(260, 10)

var _warband = null
var _body = null
var _merc_id := -1
var _merc_name := ""

var _name_label: Label
var _state_label: Label
var _health_label: Label
var _health_bar: ProgressBar
var _squad_box: VBoxContainer
var _squad_sig := ""
var _purse_label: Label
var _essence_label: Label
var _prompt_label: Label
var _status_label: Label
var _status_seconds := 0.0

func _ready() -> void:
	layer = LAYER
	_build()
	set_process(true)

func configure(warband) -> void:
	_warband = warband
	if _warband != null and not _warband.changed.is_connected(_refresh_purse):
		_warband.changed.connect(_refresh_purse)
	_refresh_purse()

## The body the local soul is inside. `merc_name` is the roster name; a null
## body means the soul is between bodies (spectating a wipe).
func set_body(body, merc_name: String = "", merc_id: int = -1) -> void:
	_body = body
	_merc_id = merc_id
	_merc_name = merc_name
	if body != null and merc_id < 0:
		_merc_id = _roster_id_for(body)
	if _merc_id >= 0 and merc_name.is_empty() and _warband != null:
		_merc_name = _warband.roster.name_of(_merc_id)

## One line under the crosshair: "Hold E to revive Dorn", "K - loot Shortsword".
func set_prompt(text: String) -> void:
	if _prompt_label != null:
		_prompt_label.text = text
		_prompt_label.visible = not text.is_empty()

## A temporary banner ("Reviving...", "Dorn is down").
func set_status(text: String, seconds: float = 2.5) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.visible = not text.is_empty()
	_status_seconds = maxf(0.0, seconds)

func _process(delta: float) -> void:
	if _status_seconds > 0.0:
		_status_seconds -= delta
		if _status_seconds <= 0.0:
			_status_label.visible = false
	_refresh_body()
	_refresh_squad()

func _build() -> void:
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	var frame := PanelContainer.new()
	frame.name = "BodyPanel"
	frame.position = Vector2(18, 16)
	frame.custom_minimum_size = Vector2(BAR_SIZE.x + 28, 0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	frame.add_child(column)

	_name_label = Label.new()
	_name_label.text = "No body"
	column.add_child(_name_label)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_state_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = BAR_SIZE
	_health_bar.show_percentage = false
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	column.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 11)
	column.add_child(_health_label)

	var squad_panel := PanelContainer.new()
	squad_panel.name = "SquadPanel"
	squad_panel.position = Vector2(18, 128)
	squad_panel.custom_minimum_size = Vector2(300, 0)
	squad_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(squad_panel)
	_squad_box = VBoxContainer.new()
	_squad_box.name = "Squad"
	_squad_box.add_theme_constant_override("separation", 1)
	_squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_panel.add_child(_squad_box)

	_purse_label = Label.new()
	_purse_label.name = "Purse"
	_purse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_purse_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_purse_label.position = Vector2(-20, 16)
	_purse_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root_control.add_child(_purse_label)

	_essence_label = Label.new()
	_essence_label.name = "Essence"
	_essence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_essence_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_essence_label.position = Vector2(-20, 38)
	_essence_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_essence_label.add_theme_font_size_override("font_size", 12)
	root_control.add_child(_essence_label)

	_prompt_label = Label.new()
	_prompt_label.name = "Prompt"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-180, -120)
	_prompt_label.custom_minimum_size = Vector2(360, 0)
	_prompt_label.visible = false
	root_control.add_child(_prompt_label)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-200, 90)
	_status_label.custom_minimum_size = Vector2(400, 0)
	_status_label.visible = false
	root_control.add_child(_status_label)

func _refresh_body() -> void:
	if _name_label == null:
		return
	if _body == null or not is_instance_valid(_body):
		_name_label.text = _merc_name if not _merc_name.is_empty() else "No body"
		if _warband != null and _merc_id >= 0:
			_state_label.text = "%s  (F1..F8 to take another)" % Contracts.state_name(
				_warband.roster.state_of(_merc_id))
		else:
			_state_label.text = "The warband is down"
		_health_bar.value = 0.0
		_health_label.text = ""
		return
	var health: float = float(_body.get("health"))
	var max_health: float = maxf(1.0, float(_body.get("max_health")))
	var downed: bool = bool(_body.get("downed"))
	var state := Contracts.HealthState.DOWNED if downed else (
		Contracts.HealthState.ALIVE if bool(_body.get("alive")) else Contracts.HealthState.DEAD)
	_name_label.text = _merc_name if not _merc_name.is_empty() else str(_body.get("display_name"))
	_state_label.text = Contracts.state_name(state)
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_label.text = "%d / %d" % [int(round(health)), int(round(max_health))]

func _refresh_squad() -> void:
	if _squad_box == null or _warband == null:
		return
	var ids: Array[int] = _warband.roster.ids()
	var signature := "%d|%d" % [ids.size(), _merc_id]
	for merc_id in ids:
		var record: Dictionary = _warband.roster.find(merc_id)
		signature += "|%d:%d:%d" % [merc_id,
			int(round(float(record.get("health", 0.0)))), int(record.get("state", 0))]
	if signature == _squad_sig:
		return
	_squad_sig = signature
	for child in _squad_box.get_children():
		child.queue_free()
	for index in ids.size():
		var merc_id := ids[index]
		var record: Dictionary = _warband.roster.find(merc_id)
		if record.is_empty():
			continue
		var state := int(record.get("state", Contracts.HealthState.DEAD))
		var max_hp := maxf(1.0, float(record.get("max_health", 1.0)))
		var percent := int(round(float(record.get("health", 0.0)) / max_hp * 100.0))
		var key := "F%d" % (index + 1) if index < 8 else "--"
		var marker := ">" if merc_id == _merc_id else " "
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 12)
		var suffix := ""
		match state:
			Contracts.HealthState.DOWNED:
				suffix = "  DOWNED"
				row.modulate = Color(0.92, 0.62, 0.30)
			Contracts.HealthState.DEAD:
				suffix = "  DEAD"
				row.modulate = Color(0.55, 0.55, 0.55)
			_:
				row.modulate = Color(0.95, 0.95, 0.95)
		row.text = "%s %s  %-10s %3d%%%s" % [marker, key, str(record.get("name", "?")), percent, suffix]
		_squad_box.add_child(row)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.72, 0.72, 0.72)
	hint.text = "[ / ] swap body   TAB warband   G altar/stash"
	_squad_box.add_child(hint)

func _refresh_purse() -> void:
	if _purse_label == null:
		return
	if _warband == null:
		_purse_label.text = ""
		_essence_label.text = ""
		return
	_purse_label.text = "%d gold" % _warband.gold()
	var total: int = _warband.cruor.total()
	var parts: PackedStringArray = []
	for tier in Catalog.TIER_ORDER:
		var count: int = _warband.cruor.tier_count(tier)
		if count > 0:
			parts.append("%d %s" % [count, Catalog.tier_short(tier)])
	_essence_label.text = ("Cruor: " + ", ".join(parts)) if not parts.is_empty() else (
		"Cruor: none" if total == 0 else "Cruor: %d" % total)

func _roster_id_for(body) -> int:
	if _warband == null or body == null:
		return -1
	for body_id in _warband.souls.body_ids():
		if _warband.souls.body_node(body_id) == body:
			return int(body_id)
	return -1
