extends CanvasLayer
## The Hollow's mouth: where a party is chosen and its delve inventory packed.
##
## Three columns on one ledger page. THE PARTY is every body standing on the
## field, each a toggle - lit goes down. THE TOWN STASH is the warband's free
## pieces: the amount dial above the page says how many copies a click moves
## (one by default, or as many as a quiver needs), a shift-click moves a whole
## stack whatever the dial says, and the inventory's rows go back the same way.
## The inventory is real warband state (`Warband.pack_for_delve`), so a pack made
## up and left at the mouth is still packed next time. GO DOWN asks the scene to
## take the chosen bodies below; the scene answers and the panel closes.
##
## The page says the rule once, in plain words: what the party wears and packs is
## lost if it falls, and comes home into the stash if it climbs out.

signal descend_requested(party: Array)

const State = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const INK := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const BLOOD := LedgerThemeScript.BLOOD
const TEAL := LedgerThemeScript.TEAL
const PANEL_SIZE := Vector2(1180, 700)
## The most copies one click will move. Shafts are counted in the hundreds, so
## this is the same order as a full quiver and not a limit a party can reach by
## accident.
const MAX_AMOUNT := 999
const RULE := "Whatever the party wears and packs goes down with it. Climb out alive and every piece comes home into the town stash; fall below and the Hollow keeps all of it."

var _warband = null
var _open := false
var _built := false
## Copies one click moves. One by default, so a click is still "one copy" for
## anything that never touches the dial.
var _amount := 1
## Bodies that may go down, by merc id, in the order the scene offered them.
var _candidates: Array[int] = []
## Bodies chosen to go.
var _chosen: Array[int] = []
var _party_box: VBoxContainer
var _stash_box: VBoxContainer
var _pack_box: VBoxContainer
var _party_title: Label
var _stash_title: Label
var _pack_title: Label
var _status: Label
var _amount_box: SpinBox
var _descend_button: Button


func _ready() -> void:
	layer = 9
	visible = false


func configure(warband) -> void:
	_warband = warband
	if not _built:
		_build()
	if _warband != null and _warband.has_signal("changed") \
			and not _warband.changed.is_connected(refresh):
		_warband.changed.connect(refresh)


func is_open() -> bool:
	return _open


## Open on the bodies that may go down. Every one of them starts chosen: the
## common descent is the whole band, and leaving a body home is the decision.
func open(candidates: Array[int]) -> void:
	if not _built:
		_build()
	_candidates = candidates.duplicate()
	_chosen = candidates.duplicate()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_status("")
	refresh()


func close() -> void:
	_open = false
	visible = false


func selected() -> Array[int]:
	return _chosen.duplicate()


func candidates() -> Array[int]:
	return _candidates.duplicate()


func set_member(merc_id: int, going: bool) -> void:
	if not _candidates.has(merc_id):
		return
	if going and not _chosen.has(merc_id):
		_chosen.append(merc_id)
	elif not going:
		_chosen.erase(merc_id)
	# Keep the party in the order the scene offered it.
	var ordered: Array[int] = []
	for merc_id_in in _candidates:
		if _chosen.has(merc_id_in):
			ordered.append(merc_id_in)
	_chosen = ordered
	refresh()


## Pack one click's worth of a free stash piece. `every` is the shift-click and
## wins over the dial: the whole stack goes.
func pack(item_id: String, every: bool = false) -> Dictionary:
	return _move(item_id, every, true)


## Put one click's worth (or every copy) back in the stash.
func unpack(item_id: String, every: bool = false) -> Dictionary:
	return _move(item_id, every, false)


## How many copies one click moves. The dial writes it; a test or a scene can say
## so directly, and the panel repaints what the next click will do.
func set_amount(count: int) -> void:
	_amount = clampi(count, 1, MAX_AMOUNT)
	if _amount_box != null:
		_amount_box.set_value_no_signal(float(_amount))
	refresh()


func amount() -> int:
	return _amount


func _move(item_id: String, every: bool, packing: bool) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": ""}
	var count: int = -1 if every else _amount
	var result: Dictionary
	if packing:
		result = _warband.pack_for_delve(item_id, count)
	else:
		result = _warband.unpack_from_delve(item_id, count)
	set_status(str(result.get("message", "")))
	refresh()
	return result


func _on_amount_changed(value: float) -> void:
	set_amount(int(value))


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func status_text() -> String:
	return str(_status.text) if _status != null else ""


## The pack's rows as the panel shows them: `[{item_id, name, count, value}]`.
func pack_rows() -> Array[Dictionary]:
	return _pool_rows(_warband.delve.inventory if _warband != null else null)


func stash_rows() -> Array[Dictionary]:
	return _pool_rows(_warband.stash if _warband != null else null)


func refresh() -> void:
	if not _built or _warband == null or not _open:
		return
	_clear(_party_box)
	for merc_id in _candidates:
		if not _warband.roster.has(merc_id):
			continue
		var going := _chosen.has(merc_id)
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 32)
		button.add_theme_font_size_override("font_size", 14)
		button.set_pressed_no_signal(going)
		button.theme_type_variation = "PrimaryButton" if going else ""
		button.text = "%s  %s  ·  %d G worn" % ["GOES" if going else "STAYS",
			str(_warband.roster.name_of(merc_id)), int(_warband.gear_value(merc_id))]
		button.toggled.connect(func(on: bool) -> void: set_member(merc_id, on))
		_party_box.add_child(button)
	_party_title.text = "THE PARTY  ·  %d GO DOWN" % _chosen.size()
	_stash_title.text = "THE TOWN STASH  ·  CLICK MOVES %d" % _amount
	_fill_pool(_stash_box, stash_rows(), true)
	var packed := pack_rows()
	_fill_pool(_pack_box, packed, false)
	var pieces := 0
	var value := 0
	for row in packed:
		pieces += int(row["count"])
		value += int(row["count"]) * int(row["value"])
	_pack_title.text = "THE DELVE INVENTORY  ·  %d PIECE%s  ·  %d G" % [pieces,
		"" if pieces == 1 else "S", value]
	_descend_button.disabled = _chosen.is_empty()


func _pool_rows(pool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if pool == null:
		return out
	var pooled: Dictionary = pool.pooled_map()
	for item_id in pooled:
		var id := str(item_id)
		out.append({"item_id": id, "name": str(State.ITEMS.get(id, {}).get("name", id)),
			"count": int(pooled[item_id]), "value": StashScript.value_of(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		return str(a["name"]) < str(b["name"]))
	return out


func _fill_pool(box: VBoxContainer, rows: Array[Dictionary], packing: bool) -> void:
	_clear(box)
	if rows.is_empty():
		var empty := _label(box, "Nothing packed yet." if not packing else "The stash holds nothing spare.",
			13, MUTED)
		empty.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
		return
	for row in rows:
		var item_id := str(row["item_id"])
		var held: bool = _warband != null and bool(_warband.is_auto_equip_restricted(item_id))
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.text = "%s  %s  ×%d  ·  %d G%s" % ["+" if packing else "-", str(row["name"]),
			int(row["count"]), int(row["value"]), "  ·  HELD" if held else ""]
		button.tooltip_text = "Click: moves %d. Shift-click: the whole stack. Right-click: restrict this item from auto-equip." % _amount
		if held:
			button.tooltip_text = "Restricted from auto-equip. Click: moves %d. Shift-click: the whole stack. Right-click: allow auto-equip again." % _amount
		button.gui_input.connect(func(event: InputEvent) -> void:
			_on_pool_input(event, item_id))
		if packing:
			button.pressed.connect(func() -> void: pack(item_id, Input.is_key_pressed(KEY_SHIFT)))
		else:
			button.pressed.connect(func() -> void: unpack(item_id, Input.is_key_pressed(KEY_SHIFT)))
		box.add_child(button)


## A right-click on a stash row is the same override the paperdoll offers: hold
## the item id back from every automatic equip, or allow it again. Packing with
## the left button is untouched, so a held piece can still go down with the party.
func _on_pool_input(event: InputEvent, item_id: String) -> void:
	if _warband == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_RIGHT:
		return
	var hold := not bool(_warband.is_auto_equip_restricted(item_id))
	var result: Dictionary = _warband.restrict_auto_equip(item_id, hold)
	set_status(str(result.get("message", "")))
	refresh()


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- construction ----------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.theme = LedgerThemeScript.get_theme()
	add_child(root_control)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)
	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("The Weeping Hollow", "key", "I")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	root_control.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.body.add_child(column)
	_label(column, "THE DELVE  ·  FLOOR I  ·  WATCHERS IN THE DARK, AND SOMETHING AT THE BOTTOM",
		11, BLOOD)
	var rule := _label(column, RULE, 15, INK)
	rule.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# The dial that ends the click-per-arrow tax: a quiver goes down in one click
	# at the number typed here, and a shift-click still takes the whole stack.
	var move_row := HBoxContainer.new()
	move_row.add_theme_constant_override("separation", 10)
	column.add_child(move_row)
	_label(move_row, "COPIES A CLICK MOVES", 11, MUTED)
	_amount_box = SpinBox.new()
	_amount_box.name = "Amount"
	_amount_box.min_value = 1.0
	_amount_box.max_value = float(MAX_AMOUNT)
	_amount_box.step = 1.0
	_amount_box.allow_greater = false
	_amount_box.allow_lesser = false
	_amount_box.value = float(_amount)
	_amount_box.custom_minimum_size = Vector2(140, 30)
	_amount_box.tooltip_text = "How many copies one click moves, both ways. SHIFT-click moves the whole stack."
	_amount_box.value_changed.connect(_on_amount_changed)
	move_row.add_child(_amount_box)
	var stack_note := _label(move_row, "SHIFT-CLICK  -  THE WHOLE STACK", 11, MUTED)
	stack_note.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var party := _column(body, 300)
	_party_title = _label(party, "THE PARTY", 11, MUTED)
	_party_box = _scroll_list(party)
	var stash := _column(body, 0)
	stash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stash_title = _label(stash, "THE TOWN STASH", 11, MUTED)
	_stash_box = _scroll_list(stash)
	var pack := _column(body, 0)
	pack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pack_title = _label(pack, "THE DELVE INVENTORY", 11, MUTED)
	_pack_box = _scroll_list(pack)

	_status = _label(column, "", 13, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 22)
	var plates := HBoxContainer.new()
	plates.add_theme_constant_override("separation", 12)
	plates.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(plates)
	var close_button := Button.new()
	close_button.text = "LEAVE IT  ·  ESC"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(180, 40)
	close_button.pressed.connect(close)
	plates.add_child(close_button)
	_descend_button = Button.new()
	_descend_button.text = "GO DOWN"
	_descend_button.theme_type_variation = "PrimaryButton"
	_descend_button.focus_mode = Control.FOCUS_NONE
	_descend_button.custom_minimum_size = Vector2(220, 40)
	_descend_button.pressed.connect(func() -> void: descend_requested.emit(selected()))
	plates.add_child(_descend_button)


func _column(parent: Node, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if width > 0.0:
		box.custom_minimum_size = Vector2(width, 0)
	parent.add_child(box)
	return box


func _scroll_list(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result
