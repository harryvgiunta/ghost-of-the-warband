extends CanvasLayer
## In-match paperdoll/backpack overlay. The helper owns the field HUD and every
## PlayerState mutation; scenes only bind a rig and react to opened / closed /
## loadout_changed. It deliberately never touches the mouse cursor.

signal opened
signal closed
signal loadout_changed

const HubHud = preload("res://scripts/menu_hud.gd")

var hud
var state
var session
var rig
var _drop_handler := Callable()
var _open := false

func configure(player_state, session_state, rig_node, drop_handler: Callable = Callable()) -> void:
	state = player_state
	session = session_state
	rig = rig_node
	_drop_handler = drop_handler
	if hud == null:
		hud = HubHud.new()
		add_child(hud)
		hud.configure(state,session,true)
		hud.close_requested.connect(close)
		hud.equip_requested.connect(_on_equip_requested)
		hud.unequip_requested.connect(_on_unequip_requested)
		hud.move_equipped_requested.connect(_on_move_equipped_requested)
		hud.floor_pickup_requested.connect(_on_floor_pickup_requested)
		hud.drop_requested.connect(_on_drop_requested)
	else:
		hud.configure(state,session,true)
	if _open:
		hud.refresh()
	else:
		hud.visible = false
	visible = _open

func rebind(rig_node) -> void:
	# The scene owns the initial apply_loadout call; the helper only needs the
	# fresh node for later equip changes.
	rig = rig_node

func is_open() -> bool:
	return _open

func open() -> void:
	if hud == null:
		return
	var was_open := _open
	_open = true
	visible = true
	hud.visible = true
	hud.refresh()
	hud.set_status("FIELD KIT  /  Equip, unequip, or right-click a piece.")
	if not was_open:
		opened.emit()

func close() -> void:
	if hud != null:
		hud.visible = false
	var was_open := _open
	_open = false
	visible = false
	if was_open:
		closed.emit()

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func _on_equip_requested(index: int, target_slot: String) -> void:
	if state == null:
		return
	_resolve(state.equip_from_inventory(index,target_slot))

func _on_unequip_requested(slot: String) -> void:
	if state == null:
		return
	_resolve(state.unequip_to_backpack(slot))

func _on_move_equipped_requested(from_slot: String, to_slot: String) -> void:
	if state == null:
		return
	_resolve(state.move_equipped(from_slot,to_slot))

func _on_floor_pickup_requested(index: int) -> void:
	if state == null:
		return
	_resolve(state.pickup_floor(index))

func _on_drop_requested(area: String, key) -> void:
	if state == null:
		return
	var world_drop := _drop_handler.is_valid()
	var result: Dictionary
	if area == "paperdoll":
		var slot_name := str(key)
		result = state.take_equipped(slot_name) if world_drop else state.drop_equipped(slot_name)
	else:
		var index := int(key)
		result = state.take_from_inventory(index) if world_drop else state.drop_from_inventory(index)
	if bool(result.get("ok", false)) and world_drop:
		_drop_handler.call(str(result.get("item_id", "")))
	_resolve(result)

## Every handler ends here: repaint the HUD, push the equipped kit into the
## live rig, and tell the scene the loadout changed.
func _resolve(result: Dictionary) -> void:
	if hud != null:
		if bool(result.get("ok", false)):
			hud.clear_selection()
		hud.refresh()
	if bool(result.get("ok", false)):
		_apply_rig()
		loadout_changed.emit()
	if hud != null:
		hud.set_status(str(result.get("message", "")))

func _apply_rig() -> void:
	if state == null or rig == null:
		return
	if not is_instance_valid(rig) or not rig.has_method("apply_loadout"):
		return
	rig.apply_loadout(state.loadout())
