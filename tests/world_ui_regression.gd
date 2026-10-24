extends SceneTree
## I and P work in the delve and arena, equip the live rig, and arena drops fall
## back to the persistent floor list.

const TEST_SAVE := "user://world_ui_state.json"
const DELVE_PORT := 7832
const ARENA_PORT := 7833

var state
var session
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WORLD_UI_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_SAVE
	state.reset(false)
	await _test_delve()
	await _test_arena()
	state.reset(false)
	_remove_test_save()
	print("WORLD_UI_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _test_delve() -> void:
	state.reset(false)
	session.arm_delve("delve-solo","127.0.0.1",DELVE_PORT,"UITester")
	var delve = load("res://delve.tscn").instantiate()
	root.add_child(delve)
	await create_timer(0.7).timeout
	for devil in delve.devils:
		devil.set_physics_process(false)
	check(delve._world_ui != null,"The delve builds the in-world kit")
	await _key(KEY_I)
	check(delve._ui_open() and delve._world_ui.active_view() == "inventory","I opens the delve backpack")
	check(delve._world_ui.inventory_panel.visible and not delve._world_ui.paperdoll_panel.visible,"Delve inventory hides the paperdoll")
	check(delve._cursor_free,"Opening the delve kit frees the cursor")
	var sword_index: int = state.inventory.find("sword_short")
	check(sword_index >= 0,"The starter sword is available")
	delve._world_ui._location = "backpack"
	delve._world_ui._index = sword_index
	delve._world_ui._on_primary()
	check(state.equipped_id("main") == "sword_short","Delve equip updates PlayerState")
	check(delve.actors[0].rig.weapon == "sword","Delve equip updates the live rig")
	await _key(KEY_P)
	check(delve._world_ui.active_view() == "equipment","P switches to the delve paperdoll")
	check(delve._world_ui.paperdoll_panel.visible and not delve._world_ui.inventory_panel.visible,"Delve equipment hides the backpack")
	await _key(KEY_ESCAPE)
	check(not delve._ui_open(),"Escape closes the delve kit")
	delve.queue_free()
	await process_frame

func _test_arena() -> void:
	state.reset(false)
	session.arm_arena("skirmish","127.0.0.1",ARENA_PORT,"UITester")
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	await create_timer(0.7).timeout
	for actor in arena.actors:
		actor.set_physics_process(false)
	check(arena._world_ui != null,"The arena builds the in-world kit")
	arena._world_ui.open_inventory()
	check(arena._ui_open() and arena._world_ui.active_view() == "inventory","I opens the arena backpack")
	check(arena._cursor_free,"Opening the arena kit frees the cursor")
	var before: int = state.floor_items.size()
	var drop_index: int = state.inventory.size() - 1
	var drop_id: String = state.inventory[drop_index]
	arena._world_ui._location = "backpack"
	arena._world_ui._index = drop_index
	arena._world_ui._on_tertiary()
	check(state.floor_items.size() == before + 1 and state.floor_items.has(drop_id),"Arena drops fall back to the floor list")
	check(not state.inventory.has(drop_id),"Arena drops leave the pack")
	arena._world_ui.open_equipment()
	check(arena._world_ui.active_view() == "equipment","The arena equipment view opens")
	arena._world_ui.close()
	check(not arena._ui_open() and not arena._cursor_free,"Closing the arena kit recaptures the mouse")
	arena.queue_free()
	await process_frame
