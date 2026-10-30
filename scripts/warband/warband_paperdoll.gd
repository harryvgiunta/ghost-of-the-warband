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
##
## The same renderer also shows a dead enemy. `show_corpse()` puts the screen in
## corpse mode: the left column becomes the kit the body still carries, the right
## column lists what can be taken, and every take goes through
## `WarbandLoot.take_from_corpse()` - the same booking path a hand pickup uses, so
## the stash stays the warband's only inventory. A piece taken elsewhere (a squad
## sweeping the same body) disappears from here on the next repaint.

signal changed

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const CharacterPreview = preload("res://scripts/character_preview.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Looks = preload("res://scripts/warband/warband_looks.gd")

const CREAM := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const GOLD := LedgerThemeScript.BLOOD
const TEAL := LedgerThemeScript.TEAL
const BONE := Color("e9e0c9")
const BONE_DIM := Color("b7ab93")
const BRASS_INK := Color("f2d6a2")
const SIZE := Vector2(1240, 780)
const SLOT_ICON := {
	"head": "helm", "chest": "cuirass", "hands": "gauntlet", "legs": "greaves",
	"feet": "boot", "neck": "amulet", "ring1": "ring", "ring2": "ring",
	"main": "blade", "off": "shield",
}

## The header line: the screen's name, or the body it is stripping in corpse mode.
var title_label: Label
## The vacuum a corpse's pieces are booked through. `CorpseLootPanel` binds it;
## null means the corpse screen can list the kit but take nothing.
var corpse_loot = null
## The body being shown; 0 while the screen dresses mercenaries.
var corpse_id := 0
## The carried pieces exactly as listed, in carry order: `{item_id, name, value,
## button}`. Empty means the body is stripped.
var corpse_rows: Array[Dictionary] = []

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
var _head_hint: Label
var _worn_title: Label
var _stash_title: Label
var _stash_hint: Label
var _merc_label: Label
var _stash_box: VBoxContainer
var _corpse_box: VBoxContainer
var _corpse_rows_box: VBoxContainer
var _corpse_empty: Label
var _take_all_button: Button
var _status: Label
var _stash_controls: Dictionary = {}   # item_id -> {root, button, tag}
var preview = null
var _stage: NinePatchRect
var _set_label: Label
var _set_button: Button
var _corpse_active := false
## The pieces the body carries, re-read from the vacuum on every repaint.
var _corpse_ids: Array[String] = []

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
## mercenary when nothing valid is selected yet. Opening the warband's own gear
## leaves the corpse screen behind: one screen, one job at a time.
func open(merc_id: int = -1) -> void:
	_ensure_built()
	if _corpse_active:
		clear_corpse()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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

## Put the screen on the body `new_corpse_id` names. `ids` is what the body still
## carries; every repaint re-reads the same list from the vacuum, so a piece the
## squad took on its own never lingers here.
func show_corpse(new_corpse_id: int, ids: Array[String]) -> void:
	_ensure_built()
	_corpse_active = true
	corpse_id = new_corpse_id
	_corpse_ids = ids.duplicate()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# A corpse has no chosen slot: every worn row is just a piece to take.
	selected_slot = -1
	set_title(_corpse_title())
	refresh_corpse()

## Leave the corpse screen and go back to dressing mercenaries.
func clear_corpse() -> void:
	if not _corpse_active:
		return
	_corpse_active = false
	corpse_id = 0
	_corpse_ids.clear()
	corpse_rows.clear()
	set_title("PAPERDOLL")
	_paint_mode()
	refresh()

## Whether the screen is showing a body instead of the warband.
func showing_corpse() -> bool:
	return _corpse_active

## The header line. `open()` and `clear_corpse()` restore the mercenary title; the
## corpse screen names the body it is stripping.
func set_title(text: String) -> void:
	if title_label != null:
		title_label.text = text

## Take one carried piece off the body. This is the corpse screen's only action,
## and the list row and the worn slot both land here; the vacuum refuses a piece
## that is already gone, so a stale row can never pay twice.
func take_piece(item_id: String) -> Dictionary:
	if not _corpse_active:
		return {"ok": false, "item_id": item_id, "message": ""}
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("take_from_corpse"):
		set_status("There is no way to take that piece.")
		return {"ok": false, "item_id": item_id, "message": ""}
	var result: Dictionary = corpse_loot.take_from_corpse(corpse_id, item_id)
	set_status(str(result.get("message", "")))
	refresh_corpse()
	# Gear moved, exactly as it does when the stash halves of this screen equip a
	# piece: whoever is watching the panel (a scene refreshing the body it drives)
	# hears the same signal for a corpse take.
	if bool(result.get("ok", false)):
		changed.emit()
	return result

## Strip the body in one go - the TAKE ALL row.
func take_all() -> Dictionary:
	if not _corpse_active:
		return {"ok": false, "ids": [], "count": 0, "value": 0}
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("take_all_from_corpse"):
		set_status("There is no way to take that gear.")
		return {"ok": false, "ids": [], "count": 0, "value": 0}
	var result: Dictionary = corpse_loot.take_all_from_corpse(corpse_id, 1)
	var count := int(result.get("count", 0))
	if count <= 0:
		set_status("There is nothing left on that body.")
	else:
		set_status("%d piece(s) go into the shared stash." % count)
	refresh_corpse()
	if count > 0:
		changed.emit()
	return result

## Choose whose ten slots are shown. The slot selection resets to the main hand,
## because an off-hand pick on one mercenary rarely means anything on the next.
## The one instruction the screen needs: how to move a piece, in either direction.
const USAGE_HINT := "Click a worn slot to take it off  /  click a stash row to wear it (another body's piece is a hand-off). TAB swaps the weapon set."

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
	if not _built:
		return
	if _corpse_active:
		refresh_corpse()
		return
	if _warband == null:
		return
	if selected_merc <= 0 or not _warband.roster.has(selected_merc):
		selected_merc = _first_merc_id()
	_sync_picker()
	_refresh_slots()
	_refresh_preview()
	_sync_stash(_warband.stash.rows(_warband.roster, _warband.cruor.brands))

## Repaint the corpse half: the carried slots, the takeable list and the two lines
## that say what the body is still worth.
func refresh_corpse() -> void:
	if not _built or not _corpse_active:
		return
	if corpse_loot != null and is_instance_valid(corpse_loot) \
			and corpse_loot.has_method("corpse_items"):
		_corpse_ids = corpse_loot.corpse_items(corpse_id)
	set_title(_corpse_title())
	_paint_mode()
	_sync_corpse_slots()
	_sync_corpse_rows()

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
	shell.theme = LedgerThemeScript.get_theme()
	add_child(shell)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("Gear", "cuirass")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -SIZE.x * 0.5
	frame.offset_right = SIZE.x * 0.5
	frame.offset_top = -SIZE.y * 0.5
	frame.offset_bottom = SIZE.y * 0.5
	shell.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.body.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	title_label = _label(head, "PAPERDOLL", 12, GOLD)
	_head_hint = _label(head, "the collective stash is shared", 12, MUTED)
	var spacer_head := Control.new()
	spacer_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer_head)
	_merc_label = _label(head, "", 12, TEAL)

	_picker_box = HBoxContainer.new()
	_picker_box.add_theme_constant_override("separation", 6)
	column.add_child(_picker_box)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 3)
	left.custom_minimum_size = Vector2(320, 0)
	body.add_child(left)
	_worn_title = _label(left, "WORN GEAR", 10, MUTED)
	for slot in Contracts.SLOT_ORDER:
		slot_rows[Contracts.slot_id(slot)] = _make_slot_row(left, slot)

	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", 6)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(centre)
	_stage = NinePatchRect.new()
	_stage.name = "Stage"
	_stage.texture = load(LedgerThemeScript.DIR + "plate_iron_idle.png")
	_stage.patch_margin_left = 20
	_stage.patch_margin_right = 20
	_stage.patch_margin_top = 12
	_stage.patch_margin_bottom = 12
	_stage.custom_minimum_size = Vector2(420, 0)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_stage)
	preview = CharacterPreview.new()
	preview.name = "Preview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 6
	preview.offset_top = 6
	preview.offset_right = -6
	preview.offset_bottom = -6
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.built.connect(_refresh_preview)
	_stage.add_child(preview)
	_set_label = _label(centre, "", 10, MUTED)
	_set_button = Button.new()
	_set_button.text = "SWAP SET  \u00b7  TAB"
	_set_button.focus_mode = Control.FOCUS_NONE
	_set_button.custom_minimum_size = Vector2(0, 30)
	_set_button.pressed.connect(_swap_set)
	centre.add_child(_set_button)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	right.custom_minimum_size = Vector2(340, 0)
	body.add_child(right)
	_stash_title = _label(right, "COLLECTIVE STASH  \u00b7  VALUE ORDER", 10, MUTED)
	_stash_hint = _label(right,
		"A worn slot takes the piece back; a free copy goes into the chosen slot.",
		11, MUTED)
	_stash_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_stash_box = VBoxContainer.new()
	_stash_box.add_theme_constant_override("separation", 4)
	_stash_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stash_box)
	_corpse_box = VBoxContainer.new()
	_corpse_box.add_theme_constant_override("separation", 4)
	_corpse_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_corpse_box.visible = false
	scroll.add_child(_corpse_box)
	_corpse_rows_box = VBoxContainer.new()
	_corpse_rows_box.add_theme_constant_override("separation", 4)
	_corpse_box.add_child(_corpse_rows_box)
	_corpse_empty = _label(_corpse_box, "Nothing left on the body.", 13, MUTED)
	_take_all_button = Button.new()
	_take_all_button.text = "TAKE ALL"
	_take_all_button.focus_mode = Control.FOCUS_NONE
	_take_all_button.custom_minimum_size = Vector2(0, 32)
	_take_all_button.pressed.connect(take_all)
	_corpse_box.add_child(_take_all_button)
	_status = _label(column, "", 12, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_slot_row(parent: Node, slot: int) -> Dictionary:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(318, 32)
	button.add_theme_font_size_override("font_size", 13)
	button.icon = LedgerThemeScript.icon_small(str(SLOT_ICON.get(Contracts.slot_id(slot), "blade")))
	button.add_theme_constant_override("icon_max_width", 26)
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
		button.theme_type_variation = "PrimaryButton" if merc_id == selected_merc else ""

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
	var color := BONE if not worn.is_empty() else BONE_DIM
	if slot == selected_slot:
		color = BRASS_INK
	var text := "%s%s  /  %s" % [marker, Contracts.slot_label(slot), _item_name(worn)]
	# Anointings and brands are properties of the piece, so the lines under the
	# item name are the only place the player learns what it looses before
	# entering a body - and a plain weapon says what the altar would wake in it.
	if not worn.is_empty() and _warband != null:
		var anointed: String = _warband.cruor.anoint_line(worn)
		if not anointed.is_empty():
			text += "\n" + anointed
		else:
			var sleeping: Dictionary = WarbandCruor.anoint_skill(worn)
			if not sleeping.is_empty():
				text += "\nPlain - the altar wakes %s" % str(sleeping.get("name", ""))
		if not _warband.cruor.brand_of(worn).is_empty():
			text += "\n" + _warband.cruor.brand_line(worn)
	if button.text != text:
		button.text = text
	if row.get("text_color", Color.TRANSPARENT) != color:
		row["text_color"] = color
		button.add_theme_color_override("font_color", color)

## The panel's own QR: the same swap the world's `TAB` runs, on the body this
## screen is showing. The roster owns both pairs, so a piece put in a slot after
## swapping belongs to the set that is now up.
func _swap_set() -> void:
	if _corpse_active or _warband == null or selected_merc <= 0:
		return
	var result: Dictionary = _warband.swap_weapon_set(selected_merc)
	set_status(str(result.get("message", "")))
	refresh()

func _on_slot_pressed(slot: int) -> void:
	# On a corpse the worn rows are the body's kit, so a press is a take rather
	# than an unequip: there is no mercenary whose slot it could be.
	if _corpse_active:
		var row: Dictionary = slot_rows.get(Contracts.slot_id(slot), {})
		var carried := str(row.get("item_id", ""))
		if carried.is_empty():
			set_status("That slot is empty.")
			return
		take_piece(carried)
		return
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
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 1)
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(func() -> void: _on_stash_pressed(item_id))
	root.add_child(button)
	var tag := _label(root, "", 10, MUTED)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(0, 14)
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
	(control["tag"] as Label).text = _tag_summary(data.get("tags", []))

## `WarbandStash.rows()` tags read "<merc> <slot>"; the panel prefixes them so a
## glance at the right-hand column says why a row cannot be equipped.
func _tag_summary(tags: Array) -> String:
	var names: Array[String] = []
	for tag in tags:
		var name := str(tag).split(" ")[0]
		if not name.is_empty() and not names.has(name):
			names.append(name)
	if names.is_empty():
		return ""
	var shown := ", ".join(PackedStringArray(names.slice(0, 2)))
	if names.size() > 2:
		shown += " +%d" % (names.size() - 2)
	return "WORN BY " + shown.to_upper()


func _tag_lines(tags: Array) -> Array[String]:
	var out: Array[String] = []
	for tag in tags:
		out.append("Equipped: %s" % str(tag))
	return out

func _on_stash_pressed(item_id: String) -> void:
	# The stash rows are hidden on the corpse screen; a press can only be a
	# leftover signal, and a corpse has no slot to dress.
	if _corpse_active:
		return
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

# --- the corpse screen -----------------------------------------------------

## The same screen, pointed at a body. Switching the two column headers and
## hiding the mercenary picker is all it takes: the worn rows and the list are
## already the two views a corpse needs.
func _paint_mode() -> void:
	_picker_box.visible = not _corpse_active
	_stage.visible = not _corpse_active
	_set_label.visible = not _corpse_active
	_set_button.visible = not _corpse_active
	_stash_hint.visible = not _corpse_active
	_stash_box.visible = not _corpse_active
	_corpse_box.visible = _corpse_active
	_worn_title.text = "WHAT THE BODY CARRIES" if _corpse_active else "WORN GEAR"
	_stash_title.text = "THE BODY'S GEAR / TAKE IT" if _corpse_active \
		else "COLLECTIVE STASH / VALUE ORDER"
	_head_hint.text = "their kit is the warband's" if _corpse_active \
		else "the collective stash is shared"

## The header line in corpse mode: who fell.
func _corpse_title() -> String:
	var label := ""
	if corpse_loot != null and is_instance_valid(corpse_loot) \
			and corpse_loot.has_method("corpse_label"):
		label = str(corpse_loot.corpse_label(corpse_id))
	if label.is_empty():
		return "THE DEAD"
	return "THE DEAD  /  " + label.to_upper()

func _sync_corpse_slots() -> void:
	var layout := _corpse_layout(_corpse_ids)
	for slot in Contracts.SLOT_ORDER:
		var row: Dictionary = slot_rows[Contracts.slot_id(slot)]
		var carried := str(layout.get(str(row["id"]), ""))
		row["item_id"] = carried
		_apply_slot_row(row, slot, carried)

## Where each carried piece would sit on the body: its natural slot first, then
## the free alternative, so a blade and a plank read as hands and a second
## one-hander reads as an off hand. A piece with nowhere left still shows in the
## list, which is what makes the two views agree about what the body holds.
func _corpse_layout(ids: Array[String]) -> Dictionary:
	var layout: Dictionary = {}
	for item_id in ids:
		var item: Dictionary = State.ITEMS.get(item_id, {})
		var slot := Rules.auto_slot(item, layout)
		if slot.is_empty():
			continue
		if layout.has(slot):
			slot = "off" if str(item.get("category", "")) == "1h" and not layout.has("off") else ""
		if slot.is_empty() or layout.has(slot):
			continue
		layout[slot] = item_id
	return layout

func _sync_corpse_rows() -> void:
	for child in _corpse_rows_box.get_children():
		_corpse_rows_box.remove_child(child)
		child.queue_free()
	corpse_rows.clear()
	var value := 0
	for item_id in _corpse_ids:
		value += StashScript.value_of(item_id)
		corpse_rows.append(_make_corpse_row(item_id))
	_corpse_empty.visible = _corpse_ids.is_empty()
	_take_all_button.visible = not _corpse_ids.is_empty()
	_take_all_button.text = "TAKE ALL  /  %d gold" % value
	if _corpse_ids.is_empty():
		_merc_label.text = "Nothing left on the body."
	else:
		_merc_label.text = "%d piece(s)  /  %d gold on the body" % [_corpse_ids.size(), value]

func _make_corpse_row(item_id: String) -> Dictionary:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = "%s  /  %d gold" % [_item_name(item_id), StashScript.value_of(item_id)]
	button.tooltip_text = "Click to take it into the shared stash."
	button.pressed.connect(take_piece.bind(item_id))
	_corpse_rows_box.add_child(button)
	return {"item_id": item_id, "name": _item_name(item_id),
		"value": StashScript.value_of(item_id), "button": button}

# --- presentation helpers --------------------------------------------------

func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "empty"
	return str(State.ITEMS.get(item_id, {}).get("name", item_id))

func _refresh_preview() -> void:
	if preview == null:
		return
	if _corpse_active or _warband == null or selected_merc <= 0 \
			or not _warband.roster.has(selected_merc):
		preview.set_active(false)
		return
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	# The live ranger is dressed from the *ids* the roster wears, not from a packed
	# int: the paperdoll held item ids and passed them straight to `pack()`, which
	# reads ints - so every slot packed as code 0 and the preview rendered the
	# leather set whatever the body was actually wearing, including nothing at all.
	var armor := {}
	for slot in ArmorData.SLOTS:
		armor[slot] = ArmorData.set_of_item(str(gear.get(slot, "")))
	var worn := {
		"neck": str(gear.get("neck", "")),
		"ring1": str(gear.get("ring1", "")),
		"ring2": str(gear.get("ring2", "")),
		"off": str(gear.get("off", "")),
	}
	var loadout := State.build_loadout(str(gear.get("main", "")), str(gear.get("off", "")),
		armor, worn)
	# The stage shows the mercenary being dressed, not a generic ranger: his own
	# height, face, hair and colours, then his kit on top of them.
	preview.set_appearance(Looks.profile_for(selected_merc))
	preview.apply_state(PreviewState.new(loadout, worn))
	preview.set_active(true)
	# The line under the ranger names the set TAB brings up, exactly as the
	# frontier's own paperdoll does: which pair is in the hands is the one fact
	# that decides what the next swap will take up.
	var active_set: int = _warband.roster.active_weapon_set(selected_merc)
	_set_label.text = "SET %d OF %d  \u00b7  MAIN: %s   \u00b7   OFF: %s" % [
		active_set + 1, RosterScript.WEAPON_SET_COUNT,
		_item_name(str(gear.get("main", ""))).to_upper(),
		_item_name(str(gear.get("off", ""))).to_upper()]
	_set_button.text = "SWAP TO SET %d  \u00b7  TAB" % (
		RosterScript.WEAPON_SET_COUNT - active_set)


class PreviewState:
	var _loadout: Dictionary
	var _trinkets: Dictionary

	func _init(loadout: Dictionary, trinkets: Dictionary) -> void:
		_loadout = loadout
		_trinkets = trinkets

	func loadout() -> Dictionary:
		return _loadout

	func trinkets() -> Dictionary:
		return _trinkets


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result
