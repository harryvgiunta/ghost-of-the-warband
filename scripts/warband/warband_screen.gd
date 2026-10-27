class_name WarbandScreen
extends CanvasLayer
## The tactical warband screen: the purse and worth in the header, one line per
## mercenary (live health, ALIVE/DOWNED/DEAD chip, gear, deployment switch and a
## click-to-control button) and the Gold recruiter's board underneath.
##
## It owns no state and no input. Every number is read out of `Warband` at paint
## time and every action goes back through it, so a heal on the battlefield, a
## hire or a deployment toggle repaints the panel without a scene reload.
## Entering a body is deliberately NOT done here: `possess_requested` is the seam
## the possession controller listens on, which keeps the router the one authority
## over who is inside what.
##
## The scene decides when the panel owns the pointer and what `W` means, so this
## class never touches `Input.mouse_mode`.

signal possess_requested(merc_id: int)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Vendor = preload("res://scripts/warband/mercenary_vendor.gd")
const State = preload("res://scripts/player_state.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")
const AMBER := Color("d9a441")
const DANGER := Color("c9604f")

const ARMOR_SLOTS := ["head", "chest", "hands", "legs", "feet"]

## Row controls keyed by mercenary id, so a scene (or a test) reads one line
## without walking the tree: `{root, name, bar, health, state, gear, deploy,
## control}`. Rebuilt only when the roster's shape changes; `_apply_row` keeps
## the existing buttons alive so hover/focus survive a refresh.
var rows: Dictionary = {}
## Header fields, in the order the screen reads them.
var gold_label: Label
var deployed_label: Label
var value_label: Label
## Recruiter board: the three fresh names currently offered, and the button that
## swears each one in.
var hire_names: Array[String] = []
var hire_buttons: Array[Button] = []
## The peer this screen belongs to. A body held by any other peer is not
## controlable, so its button is disabled rather than lying about it.
var local_peer := 1

var _warband = null
var _souls = null
var _built := false
var _open := false
var _rows_box: VBoxContainer
var _empty_label: Label
var _recruiter_box: VBoxContainer
var _cost_label: Label
var _status: Label
var _hire_rows: Array[Dictionary] = []
var _souls_watch := Callable()
var _souls_signals: Array = []

func _ready() -> void:
	layer = 20
	visible = _open
	_ensure_built()

func _exit_tree() -> void:
	_detach_sources()

## Bind the panel to a warband (`null` falls back to the `/root/Warband`
## autoload) and to the router the warband mirrors (`null` takes `warband.souls`).
func configure(warband, souls = null) -> void:
	_detach_sources()
	_warband = warband if warband != null else get_node_or_null("/root/Warband")
	var router = souls
	if router == null and _warband != null:
		router = _warband.souls
	_souls = router
	_attach_sources()
	_ensure_built()
	refresh()

func is_open() -> bool:
	return _open

func open() -> void:
	_ensure_built()
	_open = true
	visible = true
	refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false

## Repaint from the live state. Called by `Warband.changed`, by the router on a
## body hand-off and by `open()`, so nothing here needs a per-frame tick.
func refresh() -> void:
	if not _built:
		return
	_sync_rows()
	_refresh_header()
	_refresh_recruiter()

func set_status(message: String) -> void:
	if _status != null:
		_status.text = message

func status_text() -> String:
	return _status.text if _status != null else ""

# --- signal plumbing -------------------------------------------------------

func _attach_sources() -> void:
	if _warband != null and _warband.has_signal("changed") \
			and not _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.connect(_on_warband_changed)
	if _souls == null:
		return
	# A body can be taken or freed by another peer without `Warband.changed`
	# (the router is the authority over who is inside what), so the screen
	# listens to the router as well instead of only to the mirrored state.
	# One two-defaulted lambda answers every arity the router emits.
	_souls_watch = func(_first := 0, _second := 0) -> void: refresh()
	_souls_signals = [
		_souls.body_registered, _souls.body_unregistered, _souls.body_possessed,
		_souls.body_released, _souls.body_state_changed,
	]
	for watch in _souls_signals:
		if not (watch as Signal).is_connected(_souls_watch):
			(watch as Signal).connect(_souls_watch)

func _detach_sources() -> void:
	if _souls_watch.is_valid():
		for watch in _souls_signals:
			if (watch as Signal).is_connected(_souls_watch):
				(watch as Signal).disconnect(_souls_watch)
	_souls_signals.clear()
	_souls_watch = Callable()
	if _warband != null and is_instance_valid(_warband) and _warband.has_signal("changed") \
			and _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.disconnect(_on_warband_changed)

func _on_warband_changed() -> void:
	refresh()

# --- build -----------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var shell := Control.new()
	shell.name = "WarbandScreen"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.theme = _theme()
	add_child(shell)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.024, 0.03, 0.84)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	shell.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		_style(Color(0.038, 0.078, 0.096, 0.99), Color("3f5b60"), 10))
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	column.add_child(head)
	var title := _label(head, "WARBAND", 26, CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_label = _label(head, "", 14, GOLD)
	deployed_label = _label(head, "", 14, TEAL)
	value_label = _label(head, "", 14, MUTED)
	column.add_child(HSeparator.new())
	_label(column, "MERCENARY / HEALTH / STATE / GEAR / CONTROL", 11, MUTED)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	column.add_child(_rows_box)
	_empty_label = _label(_rows_box, "The warband is empty. Swear a body in below.", 13, MUTED)
	column.add_child(HSeparator.new())

	var recruiter_head := HBoxContainer.new()
	recruiter_head.add_theme_constant_override("separation", 16)
	column.add_child(recruiter_head)
	var recruiter_title := _label(recruiter_head, "GOLD RECRUITER", 16, GOLD)
	recruiter_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cost_label = _label(recruiter_head, "", 13, MUTED)
	_recruiter_box = VBoxContainer.new()
	_recruiter_box.add_theme_constant_override("separation", 6)
	column.add_child(_recruiter_box)
	for index in 3:
		_hire_rows.append(_make_hire_row(index))
	_status = _label(column, "", 13, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# --- rows ------------------------------------------------------------------

func _sync_rows() -> void:
	var ids: Array[int] = _warband.roster.ids() if _warband != null else []
	for merc_id in rows.keys():
		if ids.has(int(merc_id)):
			continue
		var stale: Dictionary = rows[merc_id]
		_rows_box.remove_child(stale["root"])
		(stale["root"] as Node).queue_free()
		rows.erase(merc_id)
	for index in ids.size():
		var merc_id := ids[index]
		if not rows.has(merc_id):
			rows[merc_id] = _make_row(merc_id)
		var row: Dictionary = rows[merc_id]
		_rows_box.move_child(row["root"], index)
		_apply_row(merc_id)
	_empty_label.visible = ids.is_empty()

func _make_row(merc_id: int) -> Dictionary:
	var root := HBoxContainer.new()
	root.name = "Mercenary%d" % merc_id
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size = Vector2(0, 32)
	_rows_box.add_child(root)
	var name_label := _label(root, "", 15, CREAM)
	name_label.custom_minimum_size = Vector2(150, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(170, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("background", _style(Color("132a30"), Color("2c4046"), 4))
	root.add_child(bar)
	var health_label := _label(root, "", 13, MUTED)
	health_label.custom_minimum_size = Vector2(84, 0)
	var chip := _label(root, "", 13, TEAL)
	chip.custom_minimum_size = Vector2(80, 0)
	var gear_label := _label(root, "", 13, MUTED)
	gear_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gear_label.clip_text = true
	var deploy := Button.new()
	deploy.toggle_mode = true
	deploy.focus_mode = Control.FOCUS_NONE
	deploy.custom_minimum_size = Vector2(106, 28)
	deploy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	deploy.pressed.connect(func() -> void: _on_deploy(merc_id, deploy.button_pressed))
	root.add_child(deploy)
	var control := Button.new()
	control.text = "CONTROL"
	control.focus_mode = Control.FOCUS_NONE
	control.custom_minimum_size = Vector2(112, 28)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.pressed.connect(func() -> void: _on_control(merc_id))
	root.add_child(control)
	return {"root": root, "name": name_label, "bar": bar, "health": health_label,
		"state": chip, "gear": gear_label, "deploy": deploy, "control": control}

func _apply_row(merc_id: int) -> void:
	var row: Dictionary = rows[merc_id]
	if _warband == null:
		return
	var roster = _warband.roster
	var state := int(roster.state_of(merc_id))
	(row["name"] as Label).text = str(roster.name_of(merc_id))
	var chip: Label = row["state"]
	chip.text = Contracts.state_name(state)
	var bar: ProgressBar = row["bar"]
	# The chip colour and the bar fill only change when the health state does;
	# repainting every row on every warband event must not allocate styles.
	if int(row.get("state_value", -1)) != state:
		row["state_value"] = state
		var color := _state_color(state)
		chip.add_theme_color_override("font_color", color)
		bar.add_theme_stylebox_override("fill", _style(color.darkened(0.25), color, 4))
	var max_health := maxf(1.0, float(roster.max_health_of(merc_id)))
	var health := clampf(float(roster.health_of(merc_id)), 0.0, max_health)
	bar.max_value = max_health
	bar.value = health
	(row["health"] as Label).text = "%d / %d" % [roundi(health), roundi(max_health)]
	(row["gear"] as Label).text = _gear_summary(merc_id)
	var deploy: Button = row["deploy"]
	deploy.set_pressed_no_signal(bool(roster.find(merc_id).get("deployed", false)))
	deploy.text = "DEPLOYED" if deploy.button_pressed else "DEPLOY"
	deploy.disabled = state == Contracts.HealthState.DEAD
	deploy.tooltip_text = "%s fielded of %d." % [
		str(roster.deployed_count()), int(_warband.deployment_cap)]
	var control: Button = row["control"]
	var holder := 0
	if _souls != null and _souls.has_body(merc_id):
		holder = int(_souls.occupied_by(merc_id))
	var taken := holder != 0 and holder != local_peer
	control.text = "IN USE" if taken else "CONTROL"
	control.disabled = state != Contracts.HealthState.ALIVE or taken
	control.tooltip_text = _control_hint(state, taken)

func _control_hint(state: int, taken: bool) -> String:
	if taken:
		return "Another soul is already inside that body."
	match state:
		Contracts.HealthState.DOWNED:
			return "Revive them before you can step in."
		Contracts.HealthState.DEAD:
			return "The dead do not answer."
	return "Take this body."

func _gear_summary(merc_id: int) -> String:
	var gear: Dictionary = _warband.roster.equipped_of(merc_id)
	var armor := 0
	for slot in ARMOR_SLOTS:
		if not str(gear.get(slot, "")).is_empty():
			armor += 1
	return "%s / %s / %d armour" % [
		_item_name(str(gear.get("main", ""))), _item_name(str(gear.get("off", ""))), armor]

func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "empty"
	return str(State.ITEMS.get(item_id, {}).get("name", item_id))

func _state_color(state: int) -> Color:
	match state:
		Contracts.HealthState.DOWNED:
			return AMBER
		Contracts.HealthState.DEAD:
			return DANGER
	return TEAL

# --- header ----------------------------------------------------------------

func _refresh_header() -> void:
	if _warband == null:
		return
	gold_label.text = "%d gold" % int(_warband.gold())
	deployed_label.text = "%d / %d deployed" % [
		int(_warband.roster.deployed_count()), int(_warband.deployment_cap)]
	value_label.text = "%d warband value" % int(_warband.total_value())

# --- recruiter -------------------------------------------------------------

func _make_hire_row(index: int) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var name_label := _label(root, "", 14, CREAM)
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.text = "HIRE"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 28)
	button.pressed.connect(func() -> void: _on_hire(index))
	root.add_child(button)
	hire_buttons.append(button)
	_recruiter_box.add_child(root)
	return {"root": root, "name": name_label, "button": button}

func _refresh_recruiter() -> void:
	if _warband == null or _hire_rows.is_empty():
		return
	var offered := _fresh_names(_hire_rows.size())
	var cost := int(_warband.hire_cost())
	var full: bool = int(_warband.roster.count()) >= int(_warband.deployment_cap)
	_cost_label.text = "Next oath: %d gold  /  %d of %d sworn" % [
		cost, int(_warband.roster.count()), int(_warband.deployment_cap)]
	hire_names.clear()
	for index in _hire_rows.size():
		var row: Dictionary = _hire_rows[index]
		var candidate := offered[index] if index < offered.size() else ""
		(row["name"] as Label).text = candidate
		var button: Button = row["button"]
		button.text = "HIRE  %d" % cost
		# The cap is not a disabled button: pressing it must report the refusal
		# the vendor returns, so the player learns why the board is empty.
		button.disabled = candidate.is_empty()
		button.tooltip_text = ("The warband already fields %d." % int(_warband.deployment_cap)) if full else ""
		hire_names.append(candidate)

## Three names nobody in the warband already carries. The candidate list itself
## is `WarbandVendor.NAMES`; only the "already sworn" filter lives here, because
## the vendor can only hand out one name at a time.
func _fresh_names(count: int) -> Array[String]:
	var used: Dictionary = {}
	if _warband != null:
		for merc in _warband.roster.records():
			used[str(merc.get("name", "")).to_lower()] = true
	var out: Array[String] = []
	for candidate in Vendor.NAMES:
		if out.size() >= count:
			break
		if used.has(candidate.to_lower()):
			continue
		out.append(candidate)
	return out

func _on_hire(index: int) -> void:
	if _warband == null:
		return
	var candidate := hire_names[index] if index < hire_names.size() else ""
	var result: Dictionary = _warband.hire(candidate)
	set_status(str(result.get("message", "")))
	refresh()

func _on_deploy(merc_id: int, on: bool) -> void:
	if _warband == null:
		return
	var result: Dictionary = _warband.set_deployed(merc_id, on)
	set_status(str(result.get("message", "")))
	if not bool(result.get("ok", false)) and rows.has(merc_id):
		# The toggle must not keep a mark the roster refused.
		var deploy: Button = rows[merc_id]["deploy"]
		deploy.set_pressed_no_signal(not on)
	refresh()

func _on_control(merc_id: int) -> void:
	# A disabled button still delivers this signal if something emits it
	# directly, so the guard repeats the rule the disabled state advertises.
	var row: Dictionary = rows.get(merc_id, {})
	if row.is_empty() or (row["control"] as Button).disabled:
		return
	possess_requested.emit(merc_id)

# --- presentation helpers --------------------------------------------------

func _theme() -> Theme:
	var result := Theme.new()
	result.default_font = ThemeDB.fallback_font
	result.default_font_size = 14
	result.set_color("font_color", "Label", CREAM)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Color("13282f"))
	result.set_color("font_disabled_color", "Button", Color("5b7175"))
	result.set_stylebox("normal", "Button", _style(Color("243a40"), Color("456068"), 6))
	result.set_stylebox("hover", "Button", _style(Color("34545b"), GOLD, 6))
	result.set_stylebox("pressed", "Button", _style(GOLD, GOLD, 6))
	result.set_stylebox("disabled", "Button", _style(Color("18282d"), Color("2c4046"), 6))
	return result

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	return result

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result
