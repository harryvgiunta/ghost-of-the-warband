class_name WarbandPaperdoll
extends CanvasLayer
## The mercenary paperdoll over the collective stash: the ten worn slots on the
## left, the stash's unequipped pieces on the right in its own value order (a
## piece somebody wears is shown on that body's slots, never in the list), and a
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
const ItemHover = preload("res://scripts/warband/item_hover.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilitySlotScript = preload("res://scripts/ability_slot.gd")

const CREAM := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const GOLD := LedgerThemeScript.BLOOD
const TEAL := LedgerThemeScript.TEAL
const BONE := Color("e9e0c9")
const BONE_DIM := Color("b7ab93")
const BRASS_INK := Color("f2d6a2")
const SIZE := Vector2(1240, 780)
## The hotbar row under the stage: the same compact key the HUD draws, at the
## same measure, so the screen the player arranges is the row the fight shows.
const HOTBAR_TILE := 40.0
## The same 3 px the HUD's own row uses, and the reason the block fits the
## centre column: ten 40 px keys and nine 3 px gaps are 427 px, inside the 432
## the frame leaves once the worn and stash columns have their widths.
const HOTBAR_GAP := 3
## The hotbar block's own measure: ten keys and the gaps between them. The
## header, the keys and the KIT ORDER press all take this width, so the block
## has one left edge and one right edge instead of three.
const HOTBAR_WIDTH := HOTBAR_TILE * AbilityRules.SLOT_COUNT \
	+ HOTBAR_GAP * (AbilityRules.SLOT_COUNT - 1)
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
## Set only on a co-op guest: `(corpse_id, item_id, all) -> void`. The body and
## the pool are the host's, so a take is a request and the record that comes back
## down the session is what repaints this screen. Unset means the vacuum books
## locally, which is what the host's own screen does.
var corpse_request: Callable = Callable()
## The body being shown; 0 while the screen dresses mercenaries.
var corpse_id := 0
## The carried pieces exactly as listed, in carry order: `{item_id, name, value,
## button}`. Empty means the body is stripped.
var corpse_rows: Array[Dictionary] = []

## The mercenary being dressed; `-1` when the warband is empty.
var selected_merc := -1
## The body the soul is inside right now (`-1` when no soul holds one here). The
## page opens on it, and the hotbar row names it: a row of keys the player did
## not arrange for the body under their hands must never read as their own.
var controlled_merc := -1
## The slot the next stash click lands in (`WarbandContracts.SlotType`).
var selected_slot := Contracts.SlotType.MAIN_HAND
## Slot rows keyed by slot id (`head`..`off`): `{slot, id, button, item_id}`.
var slot_rows: Dictionary = {}
## The stash exactly as rendered, in value order: the stash rows that still have
## a free copy, with `pooled` as that free count, plus `button`.
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
var _stash_controls: Dictionary = {}   # item_id -> row Button
var preview = null
var _stage: NinePatchRect
var _set_label: Label
var _set_button: Button
## The two re-kits under the stage: this body's, and the whole band's.
var _reequip_button: Button
var _reequip_all_button: Button
var _corpse_active := false
## The pieces the body carries, re-read from the vacuum on every repaint.
var _corpse_ids: Array[String] = []

## The hotbar row: one compact key per `AbilityRules.SLOT_COUNT`, in the order
## the body's key layout fires them. `hotbar_ids` is what that row is drawing
## (`""` for an empty key), kept for callers and tests.
var hotbar_tiles: Array = []
var hotbar_buttons: Array = []
var hotbar_ids: Array[String] = []
## The key picked up by the last click, `-1` when nothing is picked up.
var _hotbar_selected := -1
var _hotbar_box: VBoxContainer
var _hotbar_label: Label
var _reset_hotbar_button: Button

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

## Open on `merc_id`, or keep the current selection. `-1` picks the body the soul
## is inside when it is here, then the last name chosen, then the first
## mercenary. A real id is taken as the controlled body: every caller that opens
## this page is standing in the body it passes. Opening the warband's own gear
## leaves the corpse screen behind: one screen, one job at a time.
func open(merc_id: int = -1) -> void:
	_ensure_built()
	if _corpse_active:
		clear_corpse()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if merc_id > 0:
		controlled_merc = merc_id
	var target := merc_id
	if target <= 0 or not _can_dress(target):
		if _can_dress(controlled_merc):
			target = controlled_merc
		elif _can_dress(selected_merc):
			target = selected_merc
		else:
			target = _first_merc_id()
	select_merc(target, false)
	set_status(USAGE_HINT)

## The body the soul is inside, so the page can open on it and the hotbar row can
## name it. `-1` when the soul is watching from outside a body.
func set_controlled(merc_id: int) -> void:
	if merc_id == controlled_merc:
		return
	controlled_merc = merc_id
	refresh()

## A soul changed bodies while this page was up. A page that was showing the body
## it just left follows the player, so the gear and the hotbar under the cursor
## stay the body under their hands; a page the player pointed at another name
## stays there, and the hotbar header says it is not their body.
func follow_controlled(merc_id: int) -> void:
	var followed := selected_merc == controlled_merc
	controlled_merc = merc_id
	if followed and _open and _can_dress(merc_id):
		select_merc(merc_id, false)
		return
	refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	# A shut screen draws nothing: its stage stops rendering and posing.
	if preview != null:
		preview.set_active(false)

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
##
## One row is one take. When the body carries several copies of the same piece -
## the shafts off a trail archer - the row names the bunch and the click books all
## of them, so the count on the button is what actually moves.
func take_piece(item_id: String) -> Dictionary:
	if not _corpse_active:
		return {"ok": false, "item_id": item_id, "message": ""}
	if corpse_request.is_valid():
		# A guest's take: the row stays until the host's answer lands, and the
		# record that arrives is what moves it off the body.
		corpse_request.call(corpse_id, item_id, false)
		set_status("Taking %s..." % str((State.ITEMS.get(item_id, {}) as Dictionary).get("name", item_id)))
		return {"ok": true, "item_id": item_id, "message": ""}
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("take_from_corpse"):
		set_status("There is no way to take that piece.")
		return {"ok": false, "item_id": item_id, "message": ""}
	var result: Dictionary = corpse_loot.take_from_corpse(corpse_id, item_id)
	var taken := 1 if bool(result.get("ok", false)) else 0
	var last: Dictionary = result
	while bool(result.get("ok", false)) and _corpse_holds(item_id):
		result = corpse_loot.take_from_corpse(corpse_id, item_id)
		if bool(result.get("ok", false)):
			taken += 1
			last = result
	set_status(str(last.get("message", "")))
	refresh_corpse()
	# Gear moved, exactly as it does when the stash halves of this screen equip a
	# piece: whoever is watching the panel (a scene refreshing the body it drives)
	# hears the same signal for a corpse take.
	if taken > 0:
		changed.emit()
	return result


## Whether the body still carries this piece, for a caller that is emptying a row.
func _corpse_holds(item_id: String) -> bool:
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("corpse_items"):
		return false
	var ids: Array = corpse_loot.corpse_items(corpse_id)
	return ids.has(item_id)

## Strip the body in one go - the TAKE ALL row.
func take_all() -> Dictionary:
	if not _corpse_active:
		return {"ok": false, "ids": [], "count": 0, "value": 0}
	if corpse_request.is_valid():
		corpse_request.call(corpse_id, "", true)
		set_status("Taking everything on that body...")
		return {"ok": true, "ids": [], "count": 0, "value": 0}
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("take_all_from_corpse"):
		set_status("There is no way to take that gear.")
		return {"ok": false, "ids": [], "count": 0, "value": 0}
	var result: Dictionary = corpse_loot.take_all_from_corpse(corpse_id, 1)
	var count := int(result.get("count", 0))
	if count <= 0:
		set_status("There is nothing left on that body.")
	else:
		set_status("%d piece(s) go into %s." % [count, _pool_label()])
	refresh_corpse()
	if count > 0:
		changed.emit()
	return result

## Choose whose ten slots are shown. The slot selection resets to the main hand,
## because an off-hand pick on one mercenary rarely means anything on the next.
## The one instruction the screen needs: how to move a piece, in either direction.
const USAGE_HINT := "Click a worn slot to take it off  /  click a stash row to wear it  /  right-click a stash row to hold it back from auto-equip. RE-EQUIP hands a kit back and picks it again by priority. TAB swaps the weapon set. On the hotbar, click a skill then the key it should fire from."

func select_merc(merc_id: int, announce: bool = true) -> void:
	selected_merc = merc_id if _can_dress(merc_id) else -1
	_slot_chosen = false
	selected_slot = Contracts.SlotType.MAIN_HAND
	_hotbar_selected = -1
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
		_sync_hotbar()
		return
	if selected_merc <= 0 or not _can_dress(selected_merc):
		selected_merc = controlled_merc if _can_dress(controlled_merc) else _first_merc_id()
	_paint_mode()
	_sync_picker()
	_sync_reequip()
	_refresh_slots()
	_refresh_preview()
	_sync_hotbar()
	_sync_stash(_pool().rows(_warband.roster, _warband.cruor.brands))

## The pool the stash half shows and dresses from: the town stash, or the delve
## inventory while a party is below (`Warband.field_stash`).
func _pool() -> WarbandStash:
	return _warband.field_stash()

func _pool_label() -> String:
	return str(_warband.field_label()) if _warband != null else "the shared stash"

func _below() -> bool:
	return _warband != null and bool(_warband.delve.active)

## The mercenaries this panel may dress: the whole roster, or only the party
## while it is below - a body in the town is out of the cave's reach.
func _dressable_ids() -> Array[int]:
	var none: Array[int] = []
	if _warband == null:
		return none
	return _warband.dressable_ids()

func _can_dress(merc_id: int) -> bool:
	return merc_id > 0 and _dressable_ids().has(merc_id)

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

	# Two header lines, each on the frame's edges: the screen's name and the body
	# it is showing at the top, the roster chips and the band-wide press under
	# them. The body's name sits on the right, where it reads as the identity of
	# the page rather than the title of the stash under it.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	title_label = _label(head, "PAPERDOLL", 12, GOLD)
	_head_hint = _label(head, "the collective stash is shared, the body is not", 12, MUTED)
	var spacer_head := Control.new()
	spacer_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer_head)
	_merc_label = _label(head, "", 12, TEAL)
	_merc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var picker_line := HBoxContainer.new()
	picker_line.add_theme_constant_override("separation", 12)
	column.add_child(picker_line)
	_picker_box = HBoxContainer.new()
	_picker_box.add_theme_constant_override("separation", 6)
	picker_line.add_child(_picker_box)
	var spacer_pick := Control.new()
	spacer_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_line.add_child(spacer_pick)
	_reequip_all_button = Button.new()
	_reequip_all_button.text = "RE-EQUIP THE BAND"
	_reequip_all_button.focus_mode = Control.FOCUS_NONE
	_reequip_all_button.custom_minimum_size = Vector2(0, 28)
	_reequip_all_button.tooltip_text = "Every body hands its kit back, then the roster is dressed one body at a time: the first names get the pick of the pool."
	_reequip_all_button.pressed.connect(_reequip_band)
	picker_line.add_child(_reequip_all_button)

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
	# "This body" sits with the body's own controls; "the band" is a screen-level
	# action and lives in the header with the title. Both hand the kit back to the
	# pool first, so the band's own priorities are the only ones in play.
	_reequip_button = Button.new()
	_reequip_button.text = "RE-EQUIP"
	_reequip_button.focus_mode = Control.FOCUS_NONE
	_reequip_button.custom_minimum_size = Vector2(0, 30)
	_reequip_button.tooltip_text = "Hand this body's kit back to the stash and dress it again: the dearest spare for every slot, a shield for a tank, a bow for an archer."
	_reequip_button.pressed.connect(_reequip_selected)
	centre.add_child(_reequip_button)

	# The ten keys, in the order this body fires them. The HUD draws the same
	# row during a fight; this is the only place the order can be changed, and
	# the change is saved with the body and carried onto its rig at the next
	# dressing. Empty keys keep their frames and numbers, exactly as they do in
	# the fight, so the screen never promises a skill the kit cannot grant.
	_hotbar_box = VBoxContainer.new()
	_hotbar_box.name = "Hotbar"
	_hotbar_box.add_theme_constant_override("separation", 6)
	_hotbar_box.custom_minimum_size = Vector2(HOTBAR_WIDTH, 0)
	_hotbar_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	centre.add_child(_hotbar_box)
	var hotbar_head := HBoxContainer.new()
	hotbar_head.add_theme_constant_override("separation", 8)
	_hotbar_box.add_child(hotbar_head)
	_hotbar_label = _label(hotbar_head, "HOTBAR  /  THE TEN KEYS", 10, MUTED)
	var hotbar_spacer := Control.new()
	hotbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotbar_head.add_child(hotbar_spacer)
	_reset_hotbar_button = Button.new()
	_reset_hotbar_button.text = "KIT ORDER"
	_reset_hotbar_button.focus_mode = Control.FOCUS_NONE
	_reset_hotbar_button.custom_minimum_size = Vector2(0, 26)
	_reset_hotbar_button.tooltip_text = "Drop the arrangement and let the kit order the keys again: main hand, off hand, then the worn trinkets."
	_reset_hotbar_button.pressed.connect(_reset_hotbar)
	hotbar_head.add_child(_reset_hotbar_button)
	var hotbar_row := HBoxContainer.new()
	hotbar_row.name = "Keys"
	hotbar_row.add_theme_constant_override("separation", HOTBAR_GAP)
	_hotbar_box.add_child(hotbar_row)
	hotbar_tiles.clear()
	hotbar_buttons.clear()
	for index in AbilityRules.SLOT_COUNT:
		# A Button carries the click and the tooltip; the tile inside draws the
		# same key the HUD does at the same measure. An empty key is still a
		# drop target, so the frame is never hidden.
		var button := Button.new()
		button.name = "Key%d" % (index + 1)
		button.focus_mode = Control.FOCUS_NONE
		# The tile draws the frame; the button is only the click and the hover.
		button.flat = true
		button.custom_minimum_size = Vector2(HOTBAR_TILE, HOTBAR_TILE)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_hotbar_pressed.bind(index))
		hotbar_row.add_child(button)
		var tile = AbilitySlotScript.new()
		tile.name = "Skill"
		tile.configure(index, HOTBAR_TILE)
		button.add_child(tile)
		hotbar_buttons.append(button)
		hotbar_tiles.append(tile)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	right.custom_minimum_size = Vector2(340, 0)
	body.add_child(right)
	_stash_title = _label(right, "COLLECTIVE STASH  \u00b7  VALUE ORDER", 10, MUTED)
	_stash_hint = _label(right,
		"A worn slot takes the piece back; a free copy goes into the chosen slot.\n"
		+ "Right-click a free copy to hold it back from the band's auto-equip.",
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
	var button := ItemHover.Row.new()
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
	var ids: Array[int] = _dressable_ids()
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
			button.custom_minimum_size = Vector2(150, 30)
			button.pressed.connect(func() -> void: select_merc(merc_id))
			_picker_box.add_child(button)
			picker_buttons[merc_id] = button
		_picker_box.move_child(button, index)
		# The body under the player's hands carries its own mark: the chip is the
		# first thing on the page and it must answer "whose kit am I looking at"
		# before the gear and the hotbar are read.
		button.text = "%s  %s%s" % [str(_warband.roster.name_of(merc_id)),
			Contracts.state_name(int(_warband.roster.state_of(merc_id))),
			"  \u00b7  YOU" if merc_id == controlled_merc else ""]
		button.set_pressed_no_signal(merc_id == selected_merc)
		button.theme_type_variation = "PrimaryButton" if merc_id == selected_merc else ""

func _first_merc_id() -> int:
	var ids: Array[int] = _dressable_ids()
	return ids[0] if not ids.is_empty() else -1

## The per-body re-kit names the body it would hand back, and is dead when the
## screen has none to name: an empty warband, or a body the scene cannot dress.
func _sync_reequip() -> void:
	if _reequip_button == null or _warband == null:
		return
	var dressable := selected_merc > 0
	_reequip_button.disabled = not dressable
	if dressable:
		_reequip_button.text = "RE-EQUIP  \u00b7  %s" % \
			str(_warband.roster.name_of(selected_merc)).to_upper()
	else:
		_reequip_button.text = "RE-EQUIP"

# --- worn slots ------------------------------------------------------------

func _refresh_slots() -> void:
	if selected_merc <= 0:
		_merc_label.text = "NO BODY TO DRESS"
		_merc_label.add_theme_color_override("font_color", MUTED)
		_worn_title.text = "WORN GEAR"
		for slot in Contracts.SLOT_ORDER:
			var bare: Dictionary = slot_rows[Contracts.slot_id(slot)]
			bare["item_id"] = ""
			_apply_slot_row(bare, slot, "")
		return
	var body_name := str(_warband.roster.name_of(selected_merc))
	var mine := selected_merc == controlled_merc
	_merc_label.text = "%s  /  %s  /  %d G WORN%s" % [
		body_name.to_upper(),
		Contracts.state_name(int(_warband.roster.state_of(selected_merc))).to_upper(),
		int(_warband.gear_value(selected_merc)),
		"   \u00b7   YOU" if mine else ""]
	_merc_label.add_theme_color_override("font_color", TEAL if mine else BONE)
	# The column says whose rows these are, so the left half of the page can be
	# read on its own - the body's name is not only in the header.
	_worn_title.text = "WORN GEAR  \u00b7  %s" % body_name.to_upper()
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
	# Hovering the slot says what the piece is, not just what a click does; an
	# empty slot has nothing to describe.
	if worn.is_empty():
		button.show_item("")
	elif _corpse_active:
		button.show_item(worn, _warband, "Click to take it from the body.")
	else:
		button.show_item(worn, _warband, "Click to take it off.")

## The panel's own QR: the same swap the world's `TAB` runs, on the body this
## screen is showing. The roster owns both pairs, so a piece put in a slot after
## swapping belongs to the set that is now up.
func _swap_set() -> void:
	if _corpse_active or _warband == null or selected_merc <= 0:
		return
	var result: Dictionary = _warband.swap_weapon_set(selected_merc)
	set_status(str(result.get("message", "")))
	refresh()

## Re-kit the body on the stage: everything it wears goes back into the pool and
## the band's own choice fills the slots again (`Warband.reequip_merc`), so a tank
## comes back in a shield and a one-hander and an archer in a bow without the
## player sorting through the stash by hand.
func _reequip_selected() -> void:
	if _corpse_active or _warband == null or selected_merc <= 0:
		set_status("Choose a mercenary first.")
		return
	var result: Dictionary = _warband.reequip_merc(selected_merc)
	set_status(str(result.get("message", "")))
	refresh()
	changed.emit()

## Re-kit the whole band: every dressable body hands its kit back, then the roster
## is dressed one body at a time out of that one pool. The first names in the
## roster get the pick, which is what one shared stash costs.
func _reequip_band() -> void:
	if _corpse_active or _warband == null:
		return
	var result: Dictionary = _warband.reequip_warband()
	set_status(str(result.get("message", "")))
	refresh()
	changed.emit()

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
			set_status("%s returns to %s." % [_item_name(returned), _pool_label()])
		elif bool(_warband.get("lent")):
			set_status(str(_warband.LENT_MESSAGE))
	refresh()
	changed.emit()

# --- the hotbar -------------------------------------------------------------

## The ten keys this screen is drawing, one id per slot with "" for an empty
## key. The same row the HUD reads during a fight.
func hotbar_layout() -> Array[String]:
	return hotbar_ids.duplicate()

## Repaint the keys from the body's own layout. The HUD and this row read the
## same `Warband.hotbar_layout`, so what the player arranges here is exactly
## what the number row fires.
func _sync_hotbar() -> void:
	if hotbar_tiles.is_empty():
		return
	hotbar_ids.clear()
	var layout: Array = []
	if _warband != null and selected_merc > 0 and not _corpse_active:
		layout = _warband.hotbar_layout(selected_merc)
	# Whose row this is, in the row's own header: the body on the stage, and
	# whether that body is the one under the player's hands.
	var body_name := ""
	if _warband != null and selected_merc > 0:
		body_name = str(_warband.roster.name_of(selected_merc)).to_upper()
	var mine := selected_merc > 0 and selected_merc == controlled_merc
	if body_name.is_empty():
		_hotbar_label.text = "HOTBAR  /  THE TEN KEYS"
	else:
		_hotbar_label.text = "HOTBAR  /  %s  /  %s" % [body_name,
			"THE BODY YOU CONTROL" if mine else "NOT YOUR BODY"]
	_hotbar_label.add_theme_color_override("font_color",
		MUTED if mine or body_name.is_empty() else GOLD)
	var any := false
	for index in hotbar_tiles.size():
		var id := str(layout[index]) if index < layout.size() else ""
		hotbar_ids.append(id)
		if not id.is_empty():
			any = true
		hotbar_tiles[index].update_state({} if id.is_empty() else {"id": id})
		var button: Button = hotbar_buttons[index]
		var definition := AbilityRules.by_id(id)
		button.tooltip_text = "Key %d - no skill" % (index + 1) if definition.is_empty() \
			else "Key %d - %s\nClick a skill, then the key it should fire from." % [
				index + 1, str(definition.get("name", "")).capitalize()]
		button.modulate = Color(1.6, 1.4, 1.0) if index == _hotbar_selected \
			else Color.WHITE
	_reset_hotbar_button.disabled = _warband == null or selected_merc <= 0 \
		or _corpse_active or not any

## One click picks a key up; the next puts it where it belongs. A second click
## on the same key drops the pick, and an empty first key says so instead of
## leaving the player waiting for the second press.
func _on_hotbar_pressed(slot: int) -> void:
	if _corpse_active or hotbar_tiles.is_empty():
		return
	if _warband == null or selected_merc <= 0:
		set_status("Choose a mercenary first.")
		return
	if slot < 0 or slot >= hotbar_ids.size():
		return
	if _hotbar_selected < 0:
		if hotbar_ids[slot].is_empty():
			set_status("Key %d fires nothing. Pick a skill first." % (slot + 1))
			return
		_hotbar_selected = slot
		var definition := AbilityRules.by_id(hotbar_ids[slot])
		set_status("%s on key %d. Now click the key it should fire from." % [
			str(definition.get("name", "That skill")).capitalize(), slot + 1])
		_sync_hotbar()
		return
	if _hotbar_selected == slot:
		_hotbar_selected = -1
		set_status("")
		_sync_hotbar()
		return
	var from := _hotbar_selected
	_hotbar_selected = -1
	var result: Dictionary = _warband.move_hotbar_skill(selected_merc, from, slot)
	set_status(str(result.get("message", "")))
	refresh()

## Hand the keys back to the kit: main hand, off hand, necklace, ring 1, ring 2.
## The numbers stay where they are; only the skills move.
func _reset_hotbar() -> void:
	if _corpse_active or _warband == null or selected_merc <= 0:
		set_status("Choose a mercenary first.")
		return
	_hotbar_selected = -1
	var result: Dictionary = _warband.reset_hotbar(selected_merc)
	set_status(str(result.get("message", "")))
	refresh()

# --- stash -----------------------------------------------------------------

func _sync_stash(rows: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	stash_rows.clear()
	for data in rows:
		var item_id := str(data["item_id"])
		# The list is the unequipped pool only: a piece with no free copy is on a
		# body, and that body's worn slot is where it shows and comes off. The
		# free count is read from the pool itself, never from a worn tally.
		var free_count := int(_pool().pooled_count(item_id))
		if free_count <= 0:
			continue
		seen[item_id] = true
		var button: Button = _stash_controls.get(item_id)
		if button == null:
			button = _make_stash_row(item_id)
			_stash_controls[item_id] = button
		_stash_box.move_child(button, stash_rows.size())
		_apply_stash_row(button, data, free_count)
		var view: Dictionary = data.duplicate()
		view["pooled"] = free_count
		view["button"] = button
		stash_rows.append(view)
	for item_id in _stash_controls.keys():
		if seen.has(str(item_id)):
			continue
		var stale: Button = _stash_controls[item_id]
		_stash_box.remove_child(stale)
		stale.queue_free()
		_stash_controls.erase(item_id)

func _make_stash_row(item_id: String) -> Button:
	var button := ItemHover.Row.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(func() -> void: _on_stash_pressed(item_id))
	button.gui_input.connect(func(event: InputEvent) -> void:
		_on_stash_row_input(event, item_id))
	_stash_box.add_child(button)
	return button

func _apply_stash_row(button: Button, data: Dictionary, free_count: int) -> void:
	var item_id := str(data.get("item_id", ""))
	var held := _warband != null and bool(_warband.is_auto_equip_restricted(item_id))
	button.text = "%s  /  %d gold  /  x%d%s" % [
		str(data.get("name", item_id)), int(data.get("value", 0)), free_count,
		"  ·  HELD" if held else ""]
	var tooltip := "Click to wear it here. Right-click to restrict this item from auto-equip."
	if held:
		tooltip = "Restricted from auto-equip. Right-click to allow auto-equip again."
	button.show_item(item_id, _warband, tooltip, free_count)

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

## A right-click on a stash row is the player's override: hold that item id back
## from every automatic equip (band arming, recruit dressing, a loot pickup) or
## let it be equipped again. Left-click still wears it by hand, because the hold
## steers the AI and never takes the piece out of the player's hands.
func _on_stash_row_input(event: InputEvent, item_id: String) -> void:
	if _corpse_active or _warband == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_RIGHT:
		return
	var button: Variant = _stash_controls.get(item_id)
	if button is Button:
		(button as Button).accept_event()
	var hold := not bool(_warband.is_auto_equip_restricted(item_id))
	var result: Dictionary = _warband.restrict_auto_equip(item_id, hold)
	set_status(str(result.get("message", "")))
	refresh()

# --- the corpse screen -----------------------------------------------------

## The same screen, pointed at a body. Switching the two column headers and
## hiding the mercenary picker is all it takes: the worn rows and the list are
## already the two views a corpse needs.
func _paint_mode() -> void:
	_picker_box.visible = not _corpse_active
	_stage.visible = not _corpse_active
	_set_label.visible = not _corpse_active
	_set_button.visible = not _corpse_active
	_reequip_button.visible = not _corpse_active
	_reequip_all_button.visible = not _corpse_active
	_hotbar_box.visible = not _corpse_active
	_stash_hint.visible = not _corpse_active
	_stash_box.visible = not _corpse_active
	_corpse_box.visible = _corpse_active
	_worn_title.text = "WHAT THE BODY CARRIES" if _corpse_active else "WORN GEAR"
	_stash_title.text = "THE BODY'S GEAR / TAKE IT" if _corpse_active \
		else ("DELVE INVENTORY / VALUE ORDER" if _below() else "COLLECTIVE STASH / VALUE ORDER")
	_head_hint.text = "their kit is the warband's" if _corpse_active \
		else ("the party carries one inventory below, the body is not" if _below() \
		else "the collective stash is shared, the body is not")

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
	# One row per piece, not one per copy: a bunch of the same shaft is a single
	# line with its count, in the order the body was carrying them.
	var counts: Dictionary = {}
	var order: Array[String] = []
	var value := 0
	for item_id in _corpse_ids:
		if not counts.has(item_id):
			order.append(item_id)
			counts[item_id] = 0
		counts[item_id] = int(counts[item_id]) + 1
		value += StashScript.value_of(item_id)
	for item_id in order:
		corpse_rows.append(_make_corpse_row(item_id, int(counts[item_id])))
	_corpse_empty.visible = _corpse_ids.is_empty()
	_take_all_button.visible = not _corpse_ids.is_empty()
	_take_all_button.text = "TAKE ALL  /  %d gold" % value
	if _corpse_ids.is_empty():
		_merc_label.text = "Nothing left on the body."
	else:
		_merc_label.text = "%d piece(s)  /  %d gold on the body" % [_corpse_ids.size(), value]

func _make_corpse_row(item_id: String, count: int = 1) -> Dictionary:
	var button := ItemHover.Row.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var display := _item_name(item_id)
	# A row that stands for several copies says so, and its price is the bunch: one
	# click books exactly what the row says.
	var label := display if count <= 1 else "%s  ×%d" % [display, count]
	var worth := StashScript.value_of(item_id) * maxi(count, 1)
	button.text = "%s  /  %d gold" % [label, worth]
	button.show_item(item_id, _warband, "Click to take it from the body.", count)
	button.pressed.connect(take_piece.bind(item_id))
	_corpse_rows_box.add_child(button)
	return {"item_id": item_id, "name": display, "count": maxi(count, 1),
		"value": worth, "button": button}

# --- presentation helpers --------------------------------------------------

func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "empty"
	return str(State.ITEMS.get(item_id, {}).get("name", item_id))


## The altar's count on the two pieces this body is holding, for the stage ranger:
## a worked blade wears its marks on the paperdoll too, not only in the hand.
func _worn_annoint_marks() -> Dictionary:
	if _warband == null or not _warband.has_method("annointment_marks"):
		return {}
	return _warband.annointment_marks(selected_merc)

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
	preview.apply_kit(loadout, worn, _worn_annoint_marks())
	# Dressed on every repaint, open or shut (`Warband.changed` repaints a shut
	# screen too), but only an open screen renders and poses its stage.
	preview.set_active(_open)
	# The line under the ranger names the set TAB brings up: which pair is in
	# the hands is the one fact that decides what the next swap will take up.
	var active_set: int = _warband.roster.active_weapon_set(selected_merc)
	_set_label.text = "SET %d OF %d  \u00b7  MAIN: %s   \u00b7   OFF: %s" % [
		active_set + 1, RosterScript.WEAPON_SET_COUNT,
		_item_name(str(gear.get("main", ""))).to_upper(),
		_item_name(str(gear.get("off", ""))).to_upper()]
	_set_button.text = "SWAP TO SET %d  \u00b7  TAB" % (
		RosterScript.WEAPON_SET_COUNT - active_set)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result
