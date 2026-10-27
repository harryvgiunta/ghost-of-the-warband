class_name WarbandPaperdoll
extends CanvasLayer
## The mercenary paperdoll over the collective stash: the ten worn slots on the
## left, every owned piece on the right in the stash's own value order (pooled
## copies AND pieces someone is already wearing, tagged with their wearer), and a
## picker strip along the top so one panel dresses the whole warband.
##
## Both halves are views of `Warband`: clicking a free copy goes through
## `Warband.equip_merc` and clicking a worn slot through `Warband.unequip_merc`.
## That is what makes a two-hander displaced by a shield come back to the pool
## instead of vanishing, and why the warband's total value never drifts while
## gear moves around. The panel writes nothing itself.

signal changed

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/player_state.gd")

const CREAM := Color("eee9db")
const MUTED := Color("a5b6b7")
const GOLD := Color("e9bf76")
const TEAL := Color("72cbb6")

## The mercenary being dressed; `-1` when the warband is empty.
var selected_merc := -1
## The slot the next stash click lands in (`WarbandContracts.SlotType`).
var selected_slot := Contracts.SlotType.MAIN_HAND
## Slot rows keyed by slot id (`head`..`off`): `{slot, id, button, item_id}`.
var slot_rows: Dictionary = {}
## The stash exactly as rendered, in value order: the stash row dictionaries plus
## `button`, and `tags` rewritten as the "Equipped: <merc> <slot>" display lines.
var stash_rows: Array[Dictionary] = []
## Picker strip buttons keyed by mercenary id.
var picker_buttons: Dictionary = {}

var _warband = null
var _built := false
var _open := false
## True once the player has chosen a slot by hand; until then a stash click
## falls back to `EquipmentRules.auto_slot` so one click still dresses a body.
var _slot_chosen := false
var _picker_box: HBoxContainer
var _merc_label: Label
var _stash_box: VBoxContainer
var _status: Label
var _stash_controls: Dictionary = {}   # item_id -> {root, button, tag}

func _ready() -> void:
	layer = 25
	visible = _open
	_ensure_built()

func _exit_tree() -> void:
	_detach_source()

## Bind the panel to a warband (`null` falls back to the `/root/Warband` autoload).
func configure(warband) -> void:
	_detach_source()
	_warband = warband if warband != null else get_node_or_null("/root/Warband")
	if _warband != null and _warband.has_signal("changed") \
			and not _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.connect(_on_warband_changed)
	_ensure_built()
	refresh()

func is_open() -> bool:
	return _open

## Open on `merc_id`, or keep the current selection. `-1` picks the first
## mercenary when nothing valid is selected yet.
func open(merc_id: int = -1) -> void:
	_ensure_built()
	_open = true
	visible = true
	var target := merc_id
	if target <= 0 or _warband == null or not _warband.roster.has(target):
		target = selected_merc if _warband != null and _warband.roster.has(selected_merc) \
			else _first_merc_id()
	select_merc(target, false)
	set_status(USAGE_HINT)

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false

## Choose whose ten slots are shown. The slot selection resets to the main hand,
## because an off-hand pick on one mercenary rarely means anything on the next.
## The one instruction the screen needs: how to move a piece, in either direction.
const USAGE_HINT := "Click a worn slot to take it off  /  click a stash row to wear it (another body's piece is a hand-off)."

func select_merc(merc_id: int, announce: bool = true) -> void:
	selected_merc = merc_id if _warband != null and _warband.roster.has(merc_id) else -1
	_slot_chosen = false
	selected_slot = Contracts.SlotType.MAIN_HAND
	refresh()
	if announce:
		changed.emit()

## Repaint from the live state. `Warband.changed` calls this, so an equip made
## anywhere else (the altar, a scene script) shows up here without reopening.
func refresh() -> void:
	if not _built or _warband == null:
		return
	if selected_merc <= 0 or not _warband.roster.has(selected_merc):
		selected_merc = _first_merc_id()
	_sync_picker()
	_refresh_slots()
	_sync_stash(_warband.stash.rows(_warband.roster, _warband.cruor.brands))

func set_status(message: String) -> void:
	if _status != null:
		_status.text = message

func status_text() -> String:
	return _status.text if _status != null else ""

func _on_warband_changed() -> void:
	refresh()

func _detach_source() -> void:
	if _warband != null and is_instance_valid(_warband) and _warband.has_signal("changed") \
			and _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.disconnect(_on_warband_changed)

# --- build -----------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var shell := Control.new()
	shell.name = "WarbandPaperdoll"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.theme = _theme()
	add_child(shell)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.024, 0.03, 0.86)
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
	var title := _label(head, "PAPERDOLL", 24, CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(head, "the collective stash is shared", 12, MUTED)
	_picker_box = HBoxContainer.new()
	_picker_box.add_theme_constant_override("separation", 6)
	column.add_child(_picker_box)
	_merc_label = _label(column, "", 14, TEAL)
	column.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(360, 0)
	body.add_child(left)
	_label(left, "WORN GEAR", 12, MUTED)
	for slot in Contracts.SLOT_ORDER:
		slot_rows[Contracts.slot_id(slot)] = _make_slot_row(left, slot)
	body.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_label(right, "COLLECTIVE STASH / VALUE ORDER", 12, MUTED)
	_label(right, "A worn slot takes the piece back; a free copy goes into the chosen slot.",
		11, MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_stash_box = VBoxContainer.new()
	_stash_box.add_theme_constant_override("separation", 4)
	_stash_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stash_box)
	_status = _label(column, "", 13, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_slot_row(parent: Node, slot: int) -> Dictionary:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(340, 32)
	button.pressed.connect(func() -> void: _on_slot_pressed(slot))
	parent.add_child(button)
	return {"slot": slot, "id": Contracts.slot_id(slot), "button": button, "item_id": ""}

# --- picker ----------------------------------------------------------------

func _sync_picker() -> void:
	var ids: Array[int] = _warband.roster.ids()
	for merc_id in picker_buttons.keys():
		if ids.has(int(merc_id)):
			continue
		var stale: Button = picker_buttons[merc_id]
		_picker_box.remove_child(stale)
		stale.queue_free()
		picker_buttons.erase(merc_id)
	for index in ids.size():
		var merc_id := ids[index]
		var button: Button = picker_buttons.get(merc_id)
		if button == null:
			button = Button.new()
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(132, 30)
			button.pressed.connect(func() -> void: select_merc(merc_id))
			_picker_box.add_child(button)
			picker_buttons[merc_id] = button
		_picker_box.move_child(button, index)
		button.text = "%s  %s" % [str(_warband.roster.name_of(merc_id)),
			Contracts.state_name(int(_warband.roster.state_of(merc_id)))]
		button.set_pressed_no_signal(merc_id == selected_merc)

func _first_merc_id() -> int:
	if _warband == null or _warband.roster.count() == 0:
		return -1
	var ids: Array[int] = _warband.roster.ids()
	return ids[0]

# --- worn slots ------------------------------------------------------------

func _refresh_slots() -> void:
	if selected_merc <= 0:
		_merc_label.text = "No mercenary to dress."
		for slot in Contracts.SLOT_ORDER:
			var bare: Dictionary = slot_rows[Contracts.slot_id(slot)]
			bare["item_id"] = ""
			_apply_slot_row(bare, slot, "")
		return
	_merc_label.text = "%s  /  %s  /  %d gold worn" % [
		str(_warband.roster.name_of(selected_merc)),
		Contracts.state_name(int(_warband.roster.state_of(selected_merc))),
		int(_warband.gear_value(selected_merc))]
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	for slot in Contracts.SLOT_ORDER:
		var row: Dictionary = slot_rows[Contracts.slot_id(slot)]
		var worn := str(gear.get(str(row["id"]), ""))
		row["item_id"] = worn
		_apply_slot_row(row, slot, worn)

func _apply_slot_row(row: Dictionary, slot: int, worn: String) -> void:
	var button: Button = row["button"]
	var marker := "> " if slot == selected_slot else "   "
	var color := CREAM if not worn.is_empty() else MUTED
	if slot == selected_slot:
		color = GOLD
	var text := "%s%s  /  %s" % [marker, Contracts.slot_label(slot), _item_name(worn)]
	# A brand is a property of the piece, so the line under the item name is the
	# only place the player learns what the sigil does before entering a body.
	if not worn.is_empty() and not _warband.cruor.brand_of(worn).is_empty():
		text += "\n" + _warband.cruor.brand_line(worn)
	if button.text != text:
		button.text = text
	if row.get("text_color", Color.TRANSPARENT) != color:
		row["text_color"] = color
		button.add_theme_color_override("font_color", color)

func _on_slot_pressed(slot: int) -> void:
	if _warband == null or selected_merc <= 0:
		set_status("Choose a mercenary first.")
		return
	selected_slot = slot
	_slot_chosen = true
	var slot_id := Contracts.slot_id(slot)
	var worn := str(_warband.roster.equipped_of(selected_merc).get(slot_id, ""))
	if worn.is_empty():
		set_status("Choose a free piece for the %s." % Contracts.slot_label(slot))
	else:
		var returned := str(_warband.unequip_merc(selected_merc, slot_id))
		if not returned.is_empty():
			set_status("%s returns to the collective stash." % _item_name(returned))
	refresh()
	changed.emit()

# --- stash -----------------------------------------------------------------

func _sync_stash(rows: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	stash_rows.clear()
	for index in rows.size():
		var data: Dictionary = rows[index]
		var item_id := str(data["item_id"])
		seen[item_id] = true
		# `WarbandStash.rows()` folds a partly-worn item's pooled count into its
		# worn array, so the free count shown and clicked has to come from the
		# pool itself - otherwise a piece one mercenary wears could never be
		# handed to a second one.
		var free_count := int(_warband.stash.pooled_count(item_id))
		var control: Dictionary = _stash_controls.get(item_id, {})
		if control.is_empty():
			control = _make_stash_row(item_id)
			_stash_controls[item_id] = control
		_stash_box.move_child(control["root"], index)
		_apply_stash_row(control, data, free_count)
		var view: Dictionary = data.duplicate()
		view["pooled"] = free_count
		view["tags"] = _tag_lines(data.get("tags", []))
		view["button"] = control["button"]
		stash_rows.append(view)
	for item_id in _stash_controls.keys():
		if seen.has(str(item_id)):
			continue
		var stale: Dictionary = _stash_controls[item_id]
		_stash_box.remove_child(stale["root"])
		(stale["root"] as Node).queue_free()
		_stash_controls.erase(item_id)

func _make_stash_row(item_id: String) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: _on_stash_pressed(item_id))
	root.add_child(button)
	var tag := _label(root, "", 12, GOLD)
	tag.custom_minimum_size = Vector2(210, 0)
	_stash_box.add_child(root)
	return {"root": root, "button": button, "tag": tag}

func _apply_stash_row(control: Dictionary, data: Dictionary, free_count: int) -> void:
	var button: Button = control["button"]
	var worn_text := "free x%d" % free_count if free_count > 0 else "worn"
	button.text = "%s  /  %d gold  /  %s" % [
		str(data.get("name", data.get("item_id", ""))), int(data.get("value", 0)), worn_text]
	# The stash is one pool: a piece another mercenary is wearing can be taken
	# and handed over, so the row stays clickable and says where it is.
	button.disabled = false
	button.tooltip_text = "Click to wear it here." if free_count > 0 \
		else "Worn by someone else: click to take it and wear it here."
	(control["tag"] as Label).text = ", ".join(PackedStringArray(_tag_lines(data.get("tags", []))))

## `WarbandStash.rows()` tags read "<merc> <slot>"; the panel prefixes them so a
## glance at the right-hand column says why a row cannot be equipped.
func _tag_lines(tags: Array) -> Array[String]:
	var out: Array[String] = []
	for tag in tags:
		out.append("Equipped: %s" % str(tag))
	return out

func _on_stash_pressed(item_id: String) -> void:
	if _warband == null or selected_merc <= 0:
		set_status("Choose a mercenary first.")
		return
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	var slot_id := ""
	if _slot_chosen:
		slot_id = Contracts.slot_id(selected_slot)
	else:
		slot_id = Rules.auto_slot(item, gear)
	if slot_id.is_empty():
		set_status("%s fits no worn slot." % _item_name(item_id))
		return
	# Equipping the copy already in that slot would take one out of the pool and
	# change nothing on the body, so say so instead of silently burning it.
	if str(gear.get(slot_id, "")) == item_id:
		set_status("%s is already worn in the %s." % [
			_item_name(item_id), Contracts.slot_id_label(slot_id)])
		return
	var result: Dictionary = _warband.equip_merc(selected_merc, slot_id, item_id)
	set_status(str(result.get("message", "")))
	# One click dresses one piece: the next row routes by its own natural slot
	# instead of reusing the slot that happened to be selected before.
	_slot_chosen = false
	refresh()
	changed.emit()

# --- presentation helpers --------------------------------------------------

func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "empty"
	return str(State.ITEMS.get(item_id, {}).get("name", item_id))

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
