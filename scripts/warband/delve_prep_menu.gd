extends CanvasLayer
## The Hollow's mouth: who goes down, and what the party carries with it.
##
## Three columns on one ledger page. **Party Members** is every body standing on
## the field, each row with a switch: green goes down, red stays in the town.
## **Town Stash** is the warband's free pieces, searchable. **Delve Inventory** is
## what goes down. One click on a row sends a single copy one way; a shift-click
## asks how many.
##
## Arrows and bandages are never packed by hand: every free quiver and dressing is
## already in the inventory the moment the page opens (`auto_pack_supplies`).
##
## The inventory is real warband state (`Warband.pack_for_delve`), so a pack made
## up and left at the mouth is still packed next time. GO DOWN asks the scene to
## take the chosen bodies below; the scene answers and the panel closes.
##
## Under the columns is the floor's difficulty: a three-way toggle - EASY, MEDIUM,
## HARD (`delve_mode.gd`) - that says how many bodies stand in every den, what pool
## they carry and how fast they move and swing. It is warband state
## (`Warband.set_delve_mode`), saved with the books and lent with them, and it opens
## on EASY for a band that has never been down the Hollow.

signal descend_requested(party: Array)

const State = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const ItemHover = preload("res://scripts/warband/item_hover.gd")
const DelveMode = preload("res://scripts/warband/delve_mode.gd")

const INK := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const TEAL := LedgerThemeScript.TEAL
const BONE := LedgerThemeScript.BONE
const BONE_DIM := LedgerThemeScript.BONE_DIM
const GOLD := Color("d8b273")

const PANEL_SIZE := Vector2(1180, 700)
const PARTY_WIDTH := 296.0
## The supplies no party forgets: every free copy is packed on open. Matched on
## the catalog's `kind`, so a second dressing on the shelf needs no change here.
const SUPPLY_KINDS := ["arrow", "bandage"]

const ROW_HEIGHT := 34
const PARTY_ROW_HEIGHT := 40
const SWITCH_WIDTH := 46.0
## The gear value in a party row, kept clear of the switch by `SWITCH_GAP`.
const SWITCH_GAP := 18.0
const GEAR_VALUE_WIDTH := 66.0
## The right-hand columns of an item row: the count, then the value.
const COUNT_WIDTH := 54.0
const VALUE_WIDTH := 66.0

var _warband = null
var _open := false
var _built := false
## Bodies that may go down, by merc id, in the order the scene offered them.
var _candidates: Array[int] = []
## Bodies chosen to go.
var _chosen: Array[int] = []
## What the stash search line holds, lowercased.
var _search := ""
var _party_box: VBoxContainer
var _stash_box: VBoxContainer
var _pack_box: VBoxContainer
var _party_meta: Label
var _stash_meta: Label
var _pack_meta: Label
var _status: Label
var _search_box: LineEdit
var _descend_button: Button
## The difficulty row: the three toggle plates by mode id, and the line that says
## what the lit one does to the floor.
var _mode_buttons: Dictionary = {}
var _mode_line: Label
var _prompt: Control
var _prompt_name: Label
var _prompt_note: Label
var _prompt_input: LineEdit
var _prompt_action: Button
var _prompt_item := ""
var _prompt_packing := true


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
	_search = ""
	if _search_box != null:
		_search_box.text = ""
	set_status("")
	_hide_prompt()
	auto_pack_supplies()
	refresh()


func close() -> void:
	_open = false
	visible = false
	_hide_prompt()


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


# --- the difficulty --------------------------------------------------------

## The three toggle plates, by mode id (`DelveMode.ORDER`), so a test or a hint
## reads them instead of walking the tree.
func mode_buttons() -> Dictionary:
	if not _built:
		_build()
	return _mode_buttons.duplicate()


## The difficulty the next party goes down on: the warband's own, which a co-op
## guest reads off the host's books.
func mode() -> String:
	if _warband == null or _warband.get("delve") == null:
		return DelveMode.DEFAULT
	return DelveMode.id_of(str(_warband.get("delve").mode))


## Put the descent on `mode`. The warband owns the choice
## (`Warband.set_delve_mode`, saved and lent with the books), so the panel adds
## nothing but the press: a guest's press is the host's refusal on the status
## line, exactly as the party's mode is.
func set_mode(mode_id: String) -> bool:
	var ok := false
	var message := "No warband to take down in this scene."
	if _warband != null and _warband.has_method("set_delve_mode"):
		var result: Dictionary = _warband.set_delve_mode(mode_id)
		ok = bool(result.get("ok", false))
		message = str(result.get("message", ""))
	set_status(message)
	refresh()
	return ok


# --- moving pieces ---------------------------------------------------------

## One click: a single copy goes down into the delve inventory.
func pack(item_id: String, count: int = 1) -> Dictionary:
	return _move(item_id, count, true)


## One click on the inventory: a single copy comes back to the town stash.
func unpack(item_id: String, count: int = 1) -> Dictionary:
	return _move(item_id, count, false)


## A row was clicked. `shift` asks how many copies instead of sending one.
func click(item_id: String, packing: bool, shift: bool = false) -> Dictionary:
	if shift:
		open_count(item_id, packing)
		return {"ok": false, "item_id": item_id, "count": 0, "message": ""}
	return _move(item_id, 1, packing)


func _move(item_id: String, count: int, packing: bool) -> Dictionary:
	if _warband == null:
		return {"ok": false, "item_id": item_id, "count": 0, "message": ""}
	var result: Dictionary
	if packing:
		result = _warband.pack_for_delve(item_id, count)
	else:
		result = _warband.unpack_from_delve(item_id, count)
	set_status(str(result.get("message", "")))
	refresh()
	return result


## Which way a row moves its copies: true down into the delve inventory.
func _pool_of(packing: bool):
	if _warband == null:
		return null
	return _warband.stash if packing else _warband.delve.inventory


func _pool_count(item_id: String, packing: bool) -> int:
	var pool = _pool_of(packing)
	return int(pool.pooled_count(item_id)) if pool != null else 0


# --- the how-many prompt ---------------------------------------------------

## A shift-click: ask how many copies this row moves, `packing` naming the way.
## The line opens on the whole stack, so a quiver goes down in two presses.
func open_count(item_id: String, packing: bool) -> void:
	if _warband == null or item_id.is_empty():
		return
	var have := _pool_count(item_id, packing)
	if have <= 0:
		return
	_prompt_item = item_id
	_prompt_packing = packing
	_prompt_name.text = str(State.ITEMS.get(item_id, {}).get("name", item_id))
	_prompt_note.text = "%d %s" % [have, "in the stash" if packing else "packed"]
	_prompt_action.text = "PACK" if packing else "TAKE BACK"
	_prompt_input.text = str(have)
	_prompt.visible = true
	_prompt_input.grab_focus()
	_prompt_input.select_all()


func count_open() -> bool:
	return _prompt != null and _prompt.visible


## The piece the prompt is asking about, empty when it is shut.
func prompt_item() -> String:
	return _prompt_item


## Move the typed number. `-1` moves every copy the row holds.
func submit_count(count: int = -1) -> Dictionary:
	if not count_open() or _warband == null:
		return {"ok": false, "item_id": _prompt_item, "count": 0, "message": ""}
	var item_id := _prompt_item
	var packing := _prompt_packing
	var have := _pool_count(item_id, packing)
	var want := count
	if want >= 0:
		want = clampi(want, 1, maxi(have, 1))
	var result := _move(item_id, want, packing)
	_hide_prompt()
	return result


func cancel_count() -> void:
	_hide_prompt()


func _hide_prompt() -> void:
	_prompt_item = ""
	_prompt_packing = true
	if _prompt != null:
		_prompt.visible = false


func _on_count_submitted(_text: String) -> void:
	var typed := int(_prompt_input.text.strip_edges())
	submit_count(maxi(typed, 1))


func _input(event: InputEvent) -> void:
	if not count_open():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		cancel_count()
		get_viewport().set_input_as_handled()


# --- supplies --------------------------------------------------------------

## Every free arrow and bandage the warband owns, sorted. These are the pieces a
## party is never asked to pack by hand.
func supplies() -> Array[String]:
	var out: Array[String] = []
	if _warband == null:
		return out
	for raw_id in _warband.stash.pooled_ids():
		var item_id := str(raw_id)
		var kind := str(State.ITEMS.get(item_id, {}).get("kind", ""))
		if SUPPLY_KINDS.has(kind):
			out.append(item_id)
	return out


## Pack every free arrow and bandage into the delve inventory. Returns the copies
## moved; a warband already below refuses, exactly as a hand-packed piece would.
func auto_pack_supplies() -> int:
	var moved := 0
	if _warband == null:
		return moved
	for item_id in supplies():
		var result: Dictionary = _warband.pack_for_delve(item_id, -1)
		moved += int(result.get("count", 0))
	return moved


# --- painting --------------------------------------------------------------

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


## The control a row is drawn on: the piece's plate in the pack or in the stash.
## Null when that pool does not show the piece (the search can hide it).
func pack_row_control(item_id: String) -> Control:
	return _row_control(_pack_box, item_id)


func stash_row_control(item_id: String) -> Control:
	return _row_control(_stash_box, item_id)


func _row_control(box: Node, item_id: String) -> Control:
	if box == null:
		return null
	for child in box.get_children():
		if child is ItemHover.Row and str((child as ItemHover.Row).item_id) == item_id:
			return child as Control
	return null


func refresh() -> void:
	if not _built or _warband == null or not _open:
		return
	_paint_party()
	var stash := _filtered(stash_rows())
	_fill_pool(_stash_box, stash, true)
	var packed := pack_rows()
	_fill_pool(_pack_box, packed, false)
	var free := 0
	for row in stash:
		free += int(row["count"])
	_stash_meta.text = "%d piece%s" % [free, "" if free == 1 else "s"]
	var pieces := 0
	var value := 0
	for row in packed:
		pieces += int(row["count"])
		value += int(row["count"]) * int(row["value"])
	_pack_meta.text = "%d piece%s  ·  %d G" % [pieces, "" if pieces == 1 else "s", value]
	_descend_button.disabled = _chosen.is_empty()
	_paint_mode()


## Light the difficulty the warband holds - the host's, on a guest - and say what
## it does to the floor below.
func _paint_mode() -> void:
	if _mode_line == null:
		return
	var chosen := mode()
	for key in _mode_buttons:
		var button: Button = _mode_buttons[key]
		var lit: bool = key == chosen
		button.set_pressed_no_signal(lit)
		button.theme_type_variation = "PrimaryButton" if lit else ""
	_mode_line.text = DelveMode.line_of(chosen)


func _paint_party() -> void:
	_clear(_party_box)
	for merc_id in _candidates:
		if not _warband.roster.has(merc_id):
			continue
		_party_row(merc_id, _chosen.has(merc_id))
	var going := _chosen.size()
	var staying := maxi(_candidates.size() - going, 0)
	_party_meta.text = "%d going" % going if staying == 0 \
		else "%d going  ·  %d staying" % [going, staying]


## One body: the name, the kit it carries down, and the switch that says whether
## it is going. A click anywhere on the row throws the switch.
func _party_row(merc_id: int, going: bool) -> void:
	var row := Button.new()
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.set_pressed_no_signal(going)
	row.custom_minimum_size = Vector2(0, PARTY_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := "Click to leave this one in the town." if going \
		else "Click to send this one down."
	row.tooltip_text = "%s: %s" % [str(_warband.roster.name_of(merc_id)), hint]
	row.add_child(_row_text(str(_warband.roster.name_of(merc_id)), 15, BONE, 16,
			-(SWITCH_WIDTH + SWITCH_GAP + GEAR_VALUE_WIDTH + 10.0)))
	row.add_child(_row_text("%d G" % int(_warband.gear_value(merc_id)), 13, BONE_DIM,
			-(SWITCH_WIDTH + SWITCH_GAP + GEAR_VALUE_WIDTH), -(SWITCH_WIDTH + SWITCH_GAP),
			HORIZONTAL_ALIGNMENT_RIGHT))
	var toggle := Switch.new()
	toggle.anchor_left = 1.0
	toggle.anchor_right = 1.0
	toggle.anchor_top = 0.5
	toggle.anchor_bottom = 0.5
	toggle.offset_left = -(SWITCH_WIDTH + 14.0)
	toggle.offset_right = -14.0
	toggle.offset_top = -12.0
	toggle.offset_bottom = 12.0
	toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle.set_state(going)
	row.add_child(toggle)
	row.toggled.connect(func(on: bool) -> void: set_member(merc_id, on))
	_party_box.add_child(row)


func _filtered(rows: Array[Dictionary]) -> Array[Dictionary]:
	if _search.is_empty():
		return rows
	var out: Array[Dictionary] = []
	for row in rows:
		if str(row["name"]).to_lower().contains(_search) \
				or str(row["item_id"]).contains(_search):
			out.append(row)
	return out


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
		var text := "Nothing packed yet."
		if packing:
			text = "Nothing matches that." if not _search.is_empty() else "The stash is empty."
		var empty := _label(box, text, 13, MUTED)
		empty.custom_minimum_size = Vector2(0, 32)
		return
	for row in rows:
		_item_row(box, row, packing)


## One piece: the name, the copies free, the worth, and the whole plate as the
## hover card's target. Left click sends one copy, shift-click asks how many, and
## a right click on a stash row holds the piece back from automatic equipping.
func _item_row(box: VBoxContainer, row: Dictionary, packing: bool) -> void:
	var item_id := str(row["item_id"])
	var held: bool = _warband != null and bool(_warband.is_auto_equip_restricted(item_id))
	var button := ItemHover.Row.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := "Click: one copy. Shift-click: how many." if packing \
			else "Click: one copy back to the stash. Shift-click: how many."
	if held:
		hint += " Right click: allow auto-equip again."
	elif packing:
		hint += " Right click: hold it back from auto-equip."
	button.show_item(item_id, _warband, hint, int(row["count"]))
	button.add_child(_row_text(str(row["name"]), 14, BONE, 14,
			-(COUNT_WIDTH + VALUE_WIDTH + 20.0)))
	button.add_child(_row_text("×%d" % int(row["count"]), 13, BONE_DIM,
			-(COUNT_WIDTH + VALUE_WIDTH + 14.0), -(VALUE_WIDTH + 14.0),
			HORIZONTAL_ALIGNMENT_RIGHT))
	button.add_child(_row_text("HELD" if held else "%d G" % int(row["value"]), 13,
			GOLD if not held else BONE_DIM, -(VALUE_WIDTH + 14.0), -14.0,
			HORIZONTAL_ALIGNMENT_RIGHT))
	button.gui_input.connect(func(event: InputEvent) -> void:
		_on_pool_input(event, item_id, packing))
	button.pressed.connect(func() -> void:
		click(item_id, packing, Input.is_key_pressed(KEY_SHIFT)))
	box.add_child(button)


## A right-click on a stash row is the same override the paperdoll offers: hold
## the item id back from every automatic equip, or allow it again. The click
## itself is untouched, so a held piece can still go down with the party.
func _on_pool_input(event: InputEvent, item_id: String, packing: bool) -> void:
	if _warband == null or not packing:
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
	column.add_theme_constant_override("separation", 10)
	frame.body.add_child(column)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var party := _column(body, PARTY_WIDTH)
	_party_meta = _header(party, "Party Members")
	_party_box = _scroll_list(party)

	body.add_child(_divider())

	var stash := _column(body, 0.0)
	_stash_meta = _header(stash, "Town Stash")
	_search_box = LineEdit.new()
	_search_box.name = "StashSearch"
	_search_box.placeholder_text = "Search the stash"
	_search_box.focus_mode = Control.FOCUS_CLICK
	_search_box.custom_minimum_size = Vector2(0, 30)
	_search_box.add_theme_font_size_override("font_size", 14)
	_search_box.add_theme_color_override("font_placeholder_color", BONE_DIM)
	_search_box.text_changed.connect(_on_search_changed)
	stash.add_child(_search_box)
	_stash_box = _scroll_list(stash)

	body.add_child(_divider())

	var pack := _column(body, 0.0)
	_pack_meta = _header(pack, "Delve Inventory")
	_pack_box = _scroll_list(pack)

	_status = _label(column, "", 13, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 20)

	_build_descent_row(column)

	var plates := HBoxContainer.new()
	plates.add_theme_constant_override("separation", 12)
	plates.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(plates)
	var close_button := Button.new()
	close_button.text = "LEAVE IT  ·  ESC"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(180, 42)
	close_button.pressed.connect(close)
	plates.add_child(close_button)
	_descend_button = Button.new()
	_descend_button.text = "GO DOWN"
	_descend_button.theme_type_variation = "PrimaryButton"
	_descend_button.focus_mode = Control.FOCUS_NONE
	_descend_button.custom_minimum_size = Vector2(220, 42)
	_descend_button.pressed.connect(func() -> void: descend_requested.emit(selected()))
	plates.add_child(_descend_button)

	_build_prompt(root_control)


func _on_search_changed(text: String) -> void:
	_search = text.strip_edges().to_lower()
	refresh()


## The floor's difficulty, under the columns: a rule, then THE DESCENT and the
## three plates - one lit - then the line that says what the lit one does. The
## press is the warband's (`set_mode`); the panel only draws the answer.
func _build_descent_row(parent: Node) -> void:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(INK.r, INK.g, INK.b, 0.30)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	var row := HBoxContainer.new()
	row.name = "Descent"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var caption := _label(row, "THE DESCENT", 13, LedgerThemeScript.INK_SOFT)
	caption.custom_minimum_size = Vector2(118, 0)
	for entry in DelveMode.ORDER:
		var button := Button.new()
		button.name = "Delve" + str(entry).capitalize()
		button.text = DelveMode.label_of(entry)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(132, 34)
		button.add_theme_font_size_override("font_size", 13)
		# A lit plate is brass, and the theme's ink on brass is the dark one: the
		# pressed states are pinned by hand because a toggled button falls back to
		# the default theme's light inks for them, which brass swallows.
		for state in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, LedgerThemeScript.BRASS_TEXT)
		button.tooltip_text = DelveMode.line_of(str(entry))
		button.pressed.connect(set_mode.bind(str(entry)))
		row.add_child(button)
		_mode_buttons[str(entry)] = button
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	# What the lit plate does to the floor, in the panel's ink: the line is a
	# sentence on parchment, and the parchment is what it has to read on. It is not
	# clipped: a clipped label asks a box container for no width at all, and the
	# spacer beside it takes the whole row.
	_mode_line = _label(row, "", 13, LedgerThemeScript.INK_MUTED)
	_mode_line.name = "DescentLine"


## The column header: the name in the window's own face over a hairline, with the
## column's running count on the right. Returns that count's label.
func _header(parent: Node, title: String) -> Label:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	parent.add_child(head)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var meta := _label(head, "", 13, LedgerThemeScript.INK_SOFT)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(INK.r, INK.g, INK.b, 0.30)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return meta


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(1, 0)
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.color = Color(INK.r, INK.g, INK.b, 0.18)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _column(parent: Node, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if width > 0.0:
		box.custom_minimum_size = Vector2(width, 0)
	else:
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box


func _scroll_list(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


## A row's own text, hung off the plate it sits on: the name on the left, the
## numbers on the right, and the mouse left to the plate underneath.
func _row_text(text: String, font_size: int, color: Color, left: float, right: float,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = left
	label.offset_right = right
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


# --- the prompt ------------------------------------------------------------

func _build_prompt(root_control: Control) -> void:
	_prompt = Control.new()
	_prompt.name = "CountPrompt"
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt.visible = false
	root_control.add_child(_prompt)
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.015, 0.01, 0.55)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			cancel_count())
	_prompt.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(center)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", LedgerThemeScript.iron_panel())
	center.add_child(plate)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 26)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 18)
	plate.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(360, 0)
	pad.add_child(column)
	_prompt_name = Label.new()
	_prompt_name.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_prompt_name.add_theme_font_size_override("font_size", 24)
	_prompt_name.add_theme_color_override("font_color", BONE)
	column.add_child(_prompt_name)
	_prompt_note = _label(column, "", 14, BONE_DIM)
	_prompt_input = LineEdit.new()
	_prompt_input.name = "Count"
	_prompt_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_input.custom_minimum_size = Vector2(0, 44)
	_prompt_input.add_theme_font_size_override("font_size", 22)
	_prompt_input.add_theme_color_override("font_color", BONE)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.05, 0.04, 0.03, 0.92)
	field.border_color = Color(0.58, 0.45, 0.25, 0.75)
	field.set_border_width_all(1)
	field.set_corner_radius_all(2)
	field.content_margin_left = 10
	field.content_margin_right = 10
	field.content_margin_top = 6
	field.content_margin_bottom = 6
	_prompt_input.add_theme_stylebox_override("normal", field)
	_prompt_input.add_theme_stylebox_override("focus", field)
	_prompt_input.text_submitted.connect(_on_count_submitted)
	column.add_child(_prompt_input)
	var plates := HBoxContainer.new()
	plates.add_theme_constant_override("separation", 10)
	column.add_child(plates)
	var all_button := Button.new()
	all_button.text = "ALL"
	all_button.focus_mode = Control.FOCUS_NONE
	all_button.custom_minimum_size = Vector2(88, 38)
	all_button.pressed.connect(func() -> void: submit_count(-1))
	plates.add_child(all_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plates.add_child(gap)
	var cancel_button := Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.custom_minimum_size = Vector2(104, 38)
	cancel_button.pressed.connect(cancel_count)
	plates.add_child(cancel_button)
	_prompt_action = Button.new()
	_prompt_action.text = "PACK"
	_prompt_action.theme_type_variation = "PrimaryButton"
	_prompt_action.focus_mode = Control.FOCUS_NONE
	_prompt_action.custom_minimum_size = Vector2(132, 38)
	_prompt_action.pressed.connect(func() -> void: submit_count(_prompt_text()))
	plates.add_child(_prompt_action)


func _prompt_text() -> int:
	return maxi(int(_prompt_input.text.strip_edges()), 1)


## The party switch: a green track when the body goes down, red when it stays,
## with the knob at the end the state names. Draws only; the row takes the click.
class Switch extends Control:
	const ON := Color("35613a")
	const OFF := Color("6d1a1c")
	const KNOB := Color("e9e0c9")

	var on := false

	func set_state(value: bool) -> void:
		on = value
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var track := StyleBoxFlat.new()
		track.bg_color = ON if on else OFF
		track.border_color = Color(0.10, 0.07, 0.05, 0.85)
		track.set_border_width_all(1)
		track.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var radius := size.y * 0.34
		var x := size.x - radius - 5.0 if on else radius + 5.0
		draw_circle(Vector2(x, size.y * 0.5), radius, KNOB)
