extends CanvasLayer
## The tiny loot window: a right click on a body - or a pile of drops - in the
## body's reach lists what is on it, beside the crosshair.
##
## One row per piece (copies collapse into one row with a count). A click takes
## that row, a shift-click takes everything in the window, and a body that walks
## off, goes down or opens another panel closes it; so does a click anywhere off
## the window, a right click, or Escape. A body's dropped weapon lies beside it,
## so the window lists the corpse and the drops piled within reach of it as one
## container - the thing a player right-clicked is "what this body had".
##
## Nothing here books a piece: every take goes through the loot vacuum's one path
## (`take_from_corpse`, `quick_loot`), so a row can never pay twice, the looted
## list hears every piece, and a take by the soul's own hands still snaps a better
## piece into the body's slots.

## The pieces one take moved, in the order they were booked.
signal looted(ids: Array)

const SummaryScript = preload("res://scripts/warband/loot_summary.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const State = preload("res://scripts/player_state.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")

const WIDTH := 320.0
## Where the window sits relative to the crosshair: beside it, not over it.
const OFFSET := Vector2(48.0, -96.0)
## How far past the loot reach a body may step before the window lets go.
const LEAVE_SLACK := 1.0
## A drop this close to the clicked body or drop is part of the same container.
const PILE_RADIUS := 2.0
const LOCAL_PEER := 1
const DEFAULT_REACH := 2.6
const SUMMARY_SECONDS := 3.5

## The world this window loots in (its vacuum, controller and HUD).
var world = null

var _loot = null
var _controller = null
var _hud = null
var _reach := DEFAULT_REACH
var _open := false
var _actor = null
var _corpse_id := 0
var _pickup = null
var _anchor := Vector3.ZERO
var _signature := ""
var _rows: Array[Dictionary] = []
var _root: Control
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _footer: Label


func _ready() -> void:
	layer = 8
	visible = false
	_build()


func setup(world_ref) -> void:
	world = world_ref
	if world == null or not is_instance_valid(world):
		return
	_loot = world.get("loot")
	_hud = world.get("hud")
	_controller = world.get("controller")
	var script: Script = world.get_script()
	if script != null:
		var published: Variant = script.get_script_constant_map().get("LOOT_REACH")
		if typeof(published) == TYPE_INT or typeof(published) == TYPE_FLOAT:
			_reach = float(published)


func is_open() -> bool:
	return _open


## Open on the container `target` names (`WarbandLootHand.target_at`): a corpse,
## or a drop and the pile around it. False - and nothing opens - when there is
## nothing on it.
func open_on(actor, target: Dictionary) -> bool:
	if _loot == null or actor == null or not is_instance_valid(actor) or target.is_empty():
		return false
	_actor = actor
	_corpse_id = int(target.get("corpse_id", 0))
	_pickup = target.get("pickup")
	if _corpse_id != 0:
		_anchor = _loot.corpse_position(_corpse_id)
		_title_from(_loot.corpse_label(_corpse_id))
	elif _pickup != null and is_instance_valid(_pickup):
		_anchor = (_pickup as Node3D).global_position
		_title_from("On the ground")
	else:
		return false
	if _contents().is_empty():
		_actor = null
		return false
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if (actor as Object).has_method("set_crouch"):
		actor.set_crouch(true)
	_signature = ""
	_repaint()
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if _actor != null and is_instance_valid(_actor) and (_actor as Object).has_method("set_crouch") \
			and _actor.get("alive") != false and not bool(_actor.get("downed")):
		_actor.set_crouch(false)
	_actor = null
	_corpse_id = 0
	_pickup = null
	_rows.clear()


## What the window lists: `[{item_id, name, count, value}]`, dearest first.
func rows() -> Array[Dictionary]:
	return _rows.duplicate(true)


## The world's clock: let go of a body that walked away or fell, and keep the rows
## honest when a squadmate strips the same body.
func tick() -> void:
	if not _open:
		return
	if _actor == null or not is_instance_valid(_actor) or _actor.get("alive") == false \
			or bool(_actor.get("downed")):
		close()
		return
	if (_actor as Node3D).global_position.distance_to(_anchor) > _reach + LEAVE_SLACK:
		close()
		return
	if _contents().is_empty():
		close()
		return
	_repaint()


## Take every copy of one row's piece: off the body first, then out of the pile.
func take(item_id: String) -> Array[String]:
	var ids: Array[String] = []
	if not _open or _loot == null:
		return ids
	if _corpse_id != 0:
		while _loot.corpse_items(_corpse_id).has(item_id):
			var taken: Dictionary = _loot.take_from_corpse(_corpse_id, item_id, LOCAL_PEER)
			if not bool(taken.get("ok", false)):
				break
			ids.append(item_id)
	for pickup in _pile():
		if str(pickup.item_id) != item_id:
			continue
		var picked: Dictionary = _loot.quick_loot(pickup, LOCAL_PEER)
		if bool(picked.get("ok", false)):
			ids.append(item_id)
	_after(ids)
	return ids


## Take the lot: the whole body, then the whole pile.
func take_all() -> Array[String]:
	var ids: Array[String] = []
	if not _open or _loot == null:
		return ids
	if _corpse_id != 0:
		var taken: Dictionary = _loot.take_all_from_corpse(_corpse_id, LOCAL_PEER)
		for entry in taken.get("ids", []):
			ids.append(str(entry))
	for pickup in _pile():
		var picked: Dictionary = _loot.quick_loot(pickup, LOCAL_PEER)
		if bool(picked.get("ok", false)):
			ids.append(str(picked.get("item_id", "")))
	_after(ids)
	return ids


# --- internals -------------------------------------------------------------

## The drops that belong to this container: the clicked drop, and every open drop
## within `PILE_RADIUS` of the body or drop the window was opened on.
func _pile() -> Array:
	var out: Array = []
	if _loot == null or not _loot.has_method("pickups"):
		return out
	for pickup in _loot.pickups():
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		if pickup.blocked_for(LOCAL_PEER):
			continue
		if pickup.global_position.distance_to(_anchor) <= PILE_RADIUS:
			out.append(pickup)
	return out


## item_id -> copies, across the body and the pile.
func _contents() -> Dictionary:
	var counts: Dictionary = {}
	if _loot == null:
		return counts
	if _corpse_id != 0:
		for item_id in _loot.corpse_items(_corpse_id):
			counts[str(item_id)] = int(counts.get(str(item_id), 0)) + 1
	for pickup in _pile():
		var id := str(pickup.item_id)
		counts[id] = int(counts.get(id, 0)) + 1
	return counts


func _after(ids: Array[String]) -> void:
	if ids.is_empty():
		return
	if _controller != null and is_instance_valid(_controller) and _controller.has_method("refresh_gear"):
		var merc_id := int(_controller.merc_for_peer(LOCAL_PEER))
		if merc_id > 0:
			_controller.refresh_gear(merc_id)
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("set_status"):
		_hud.set_status(SummaryScript.describe(ids), SUMMARY_SECONDS)
	looted.emit(ids)
	if _contents().is_empty():
		close()
	else:
		_repaint()


func _title_from(text: String) -> void:
	if _title != null:
		_title.text = text.to_upper() if not text.is_empty() else "THE DEAD"


func _repaint() -> void:
	var counts := _contents()
	var keys: Array = counts.keys()
	keys.sort()
	var signature := ""
	for key in keys:
		signature += "%s=%d;" % [str(key), int(counts[key])]
	if signature == _signature:
		return
	_signature = signature
	_rows.clear()
	for key in keys:
		var id := str(key)
		_rows.append({"item_id": id, "name": str(State.ITEMS.get(id, {}).get("name", id)),
			"count": int(counts[key]), "value": StashScript.value_of(id)})
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		return str(a["name"]) < str(b["name"]))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for row in _rows:
		var item_id := str(row["item_id"])
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, 28)
		button.add_theme_font_size_override("font_size", 13)
		var count := int(row["count"])
		button.text = "%s%s  ·  %d G" % [str(row["name"]), "  ×%d" % count if count > 1 else "",
			int(row["value"]) * count]
		button.pressed.connect(_on_row_pressed.bind(item_id))
		_list.add_child(button)


func _on_row_pressed(item_id: String) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		take_all()
	else:
		take(item_id)


## A press anywhere off the window lets go of it - the window is a look at a body,
## not a screen the player has to leave by a button.
func _on_outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()
		_root.accept_event()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		close()
		_panel.accept_event()


func _build() -> void:
	_root = Control.new()
	_root.name = "LootCatcher"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = LedgerThemeScript.get_theme()
	_root.gui_input.connect(_on_outside_input)
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.name = "LootWindow"
	_panel.add_theme_stylebox_override("panel", LedgerThemeScript.iron_panel())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = OFFSET.x
	_panel.offset_top = OFFSET.y
	_panel.offset_right = OFFSET.x + WIDTH
	_panel.offset_bottom = OFFSET.y
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_root.add_child(_panel)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 14)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size = Vector2(WIDTH - 28.0, 0)
	pad.add_child(column)
	_title = Label.new()
	_title.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", LedgerThemeScript.BONE)
	column.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	column.add_child(_list)
	_footer = Label.new()
	_footer.text = "CLICK TAKES  ·  SHIFT-CLICK TAKES ALL  ·  RMB CLOSES"
	_footer.add_theme_font_size_override("font_size", 10)
	_footer.add_theme_color_override("font_color", LedgerThemeScript.BONE_DIM)
	column.add_child(_footer)
