class_name WarbandScreen
extends CanvasLayer
## The tactical warband screen: the purse and worth in the header, one line per
## mercenary (live health, ALIVE/DOWNED/DEAD chip, gear and a click-to-control
## button) and the Gold recruiter's board underneath.
##
## It owns no state and no input. Every number is read out of `Warband` at paint
## time and every action goes back through it, so a heal on the battlefield, a
## hire repaints the panel without a scene reload.
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

const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const CREAM := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const GOLD := LedgerThemeScript.BLOOD
const TEAL := LedgerThemeScript.TEAL
const AMBER := Color("7c3e12")
const DANGER := LedgerThemeScript.BLOOD

const SIZE := Vector2(1090, 660)

const ARMOR_SLOTS := ["head", "chest", "hands", "legs", "feet"]

## Row controls keyed by mercenary id, so a scene (or a test) reads one line
## without walking the tree: `{root, name, bar, health, state, gear, control}`.
## Rebuilt only when the roster's shape changes; `_apply_row` keeps the existing
## buttons alive so hover/focus survive a refresh.
var rows: Dictionary = {}
## Header fields, in the order the screen reads them.
var gold_label: Label
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	shell.theme = LedgerThemeScript.get_theme()
	add_child(shell)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.84)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("Warband", "banner")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -SIZE.x * 0.5
	frame.offset_right = SIZE.x * 0.5
	frame.offset_top = -SIZE.y * 0.5
	frame.offset_bottom = SIZE.y * 0.5
	shell.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.body.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	column.add_child(head)
	var purse := _label(head, "PURSE", 10, MUTED)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_label = _label(head, "", 22, CREAM)
	gold_label.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	value_label = _label(head, "", 12, MUTED)
	_section(column, "MERCENARY")
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	column.add_child(_rows_box)
	_empty_label = _label(_rows_box, "The warband is empty. Swear a body in below.", 13, MUTED)

	var recruiter_head := HBoxContainer.new()
	recruiter_head.add_theme_constant_override("separation", 14)
	column.add_child(recruiter_head)
	var recruiter_title := _label(recruiter_head, "GOLD RECRUITER", 17, GOLD)
	recruiter_title.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	recruiter_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cost_label = _label(recruiter_head, "", 11, MUTED)
	_recruiter_box = VBoxContainer.new()
	_recruiter_box.add_theme_constant_override("separation", 6)
	column.add_child(_recruiter_box)
	for index in 3:
		_hire_rows.append(_make_hire_row(index))
	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tail)
	_status = _label(column, "", 12, TEAL)
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
	root.add_theme_constant_override("separation", 12)
	root.custom_minimum_size = Vector2(0, 40)
	_rows_box.add_child(root)
	var name_label := _label(root, "", 20, CREAM)
	name_label.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	name_label.custom_minimum_size = Vector2(148, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("background", _bar_style(Color("3a2e21"), Color("221a12")))
	root.add_child(bar)
	var health_label := _label(root, "", 12, MUTED)
	health_label.custom_minimum_size = Vector2(74, 0)
	var chip := _label(root, "", 11, TEAL)
	chip.custom_minimum_size = Vector2(86, 24)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_stylebox_override("normal", _chip_style(0))
	var gear_label := _label(root, "", 12, MUTED)
	gear_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gear_label.clip_text = true
	var control := Button.new()
	control.text = "CONTROL"
	control.theme_type_variation = "PrimaryButton"
	control.focus_mode = Control.FOCUS_NONE
	control.custom_minimum_size = Vector2(112, 30)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.add_theme_font_size_override("font_size", 10)
	control.pressed.connect(func() -> void: _on_control(merc_id))
	root.add_child(control)
	return {"root": root, "name": name_label, "bar": bar, "health": health_label,
		"state": chip, "gear": gear_label, "control": control}

func _apply_row(merc_id: int) -> void:
	var row: Dictionary = rows[merc_id]
	if _warband == null:
		return
	var roster = _warband.roster
	var state := int(roster.state_of(merc_id))
	(row["name"] as Label).text = str(roster.name_of(merc_id))
	var chip: Label = row["state"]
	chip.text = Contracts.state_name(state).to_upper()
	var bar: ProgressBar = row["bar"]
	# The chip colour and the bar fill only change when the health state does;
	# repainting every row on every warband event must not allocate styles.
	if int(row.get("state_value", -1)) != state:
		row["state_value"] = state
		chip.add_theme_color_override("font_color", _state_color(state))
		chip.add_theme_stylebox_override("normal", _chip_style(state))
		var fill := _bar_fill(state)
		bar.add_theme_stylebox_override("fill", _bar_style(fill.darkened(0.25), fill))
	var max_health := maxf(1.0, float(roster.max_health_of(merc_id)))
	var health := clampf(float(roster.health_of(merc_id)), 0.0, max_health)
	bar.max_value = max_health
	bar.value = health
	(row["health"] as Label).text = "%d / %d" % [roundi(health), roundi(max_health)]
	(row["gear"] as Label).text = _gear_summary(merc_id)
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
			return Color("5f5a52")
	return TEAL

func _bar_fill(state: int) -> Color:
	match state:
		Contracts.HealthState.DOWNED:
			return Color("a35a22")
		Contracts.HealthState.DEAD:
			return Color("5c544a")
	return Color("962c22")

func _chip_style(state: int) -> StyleBoxTexture:
	var key := "alive"
	match state:
		Contracts.HealthState.DOWNED:
			key = "downed"
		Contracts.HealthState.DEAD:
			key = "dead"
	var box := StyleBoxTexture.new()
	box.texture = load(LedgerThemeScript.DIR + "chip_%s.png" % key)
	box.texture_margin_left = 12
	box.texture_margin_right = 12
	box.texture_margin_top = 8
	box.texture_margin_bottom = 8
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box

func _bar_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	return box

# --- header ----------------------------------------------------------------

func _refresh_header() -> void:
	if _warband == null:
		return
	gold_label.text = "%d G" % int(_warband.gold())
	value_label.text = "WORTH %d G" % int(_warband.total_value())

# --- recruiter -------------------------------------------------------------

func _make_hire_row(index: int) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var name_label := _label(root, "", 15, CREAM)
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.text = "HIRE"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 30)
	button.add_theme_font_size_override("font_size", 11)
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
	# The first eight oaths cost nothing, and a board that says "0 gold" makes the
	# player look for a catch. It says FREE.
	if cost <= 0:
		_cost_label.text = "Next oath: free  /  %d of %d sworn" % [
			int(_warband.roster.count()), int(_warband.deployment_cap)]
	else:
		_cost_label.text = "Next oath: %d gold  /  %d of %d sworn" % [cost,
			int(_warband.roster.count()), int(_warband.deployment_cap)]
	hire_names.clear()
	for index in _hire_rows.size():
		var row: Dictionary = _hire_rows[index]
		var candidate := offered[index] if index < offered.size() else ""
		(row["name"] as Label).text = candidate
		var button: Button = row["button"]
		button.text = "HIRE  FREE" if cost <= 0 else "HIRE  %d" % cost
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

func _on_control(merc_id: int) -> void:
	# A disabled button still delivers this signal if something emits it
	# directly, so the guard repeats the rule the disabled state advertises.
	var row: Dictionary = rows.get(merc_id, {})
	if row.is_empty() or (row["control"] as Button).disabled:
		return
	possess_requested.emit(merc_id)

# --- presentation helpers --------------------------------------------------

func _section(parent: Node, text: String) -> void:
	if text.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		parent.add_child(gap)
		return
	var label := _label(parent, text, 10, MUTED)
	label.add_theme_constant_override("line_spacing", 0)

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result
