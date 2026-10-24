extends SceneTree
## Endless Sunken Delve: fall in, touch the altar, clear, loot the cache,
## climb the rope or drop through the floor into a harder recycled depth.

const TEST_SAVE := "user://delve_regression_state.json"
const PORT := 7831

var state
var session
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DELVE_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	for path in [TEST_SAVE,"user://net_cache_test.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _host_scene() -> Node:
	session.arm_delve("delve-solo","127.0.0.1",PORT,"Tester")
	var scene = load("res://delve.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.8).timeout
	return scene

func _kill_devils(delve) -> void:
	for tick in 26:
		for devil in delve.devils.duplicate():
			if is_instance_valid(devil) and devil.alive:
				devil.take_damage(99999.0,-1)
		await create_timer(0.1).timeout

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_SAVE
	state.reset(false)

	var delve = await _host_scene()
	check(delve.network_role == "host","The delve hosts solo")
	check(delve.phase == "ALTAR" and delve.depth == 1,"Entry lands at the depth-one altar")
	check(delve.local_slot == 0 and delve.actors[0].alive,"The host delver is alive")
	check(delve.actors[0].global_position.y < 8.2,"The party is dropped into the room")
	check(delve.world.altar_position == Vector3(0,0.05,-4.0),"The altar contract is stable")
	check(delve.world.rope_position == Vector3(5.2,0.05,3.0) and delve.world.hole_position == Vector3(-5.2,0.05,3.0),"Rope and hole contracts are stable")
	check(not delve.world.is_rope_lowered() and not delve.world.is_hole_open(),"Rope and hole start closed")
	check(delve.chest == null and not delve.chest_ready,"No cache before the first wave")

	delve.actors[0].global_position = delve.world.altar_position + Vector3(0,0.1,1.2)
	check(delve._prompt_text().contains("ALTAR"),"The altar prompt appears in reach")
	delve.begin_wave()
	check(delve.phase == "WAVE","Touching the altar starts the wave")
	check(delve.world.sealed,"The wave seals both gates")
	await create_timer(0.3).timeout
	check(delve.devils.size() >= 1,"The first devil spawns immediately")
	await _kill_devils(delve)
	check(delve.phase == "CLEARED","Clearing every devil opens the cache phase")
	check(not delve.world.sealed,"Clearing the wave unseals the gates")
	check(not delve.chest_ready,"The cache waits out the clear delay")
	await create_timer(2.5).timeout
	check(delve.chest_ready and is_instance_valid(delve.chest),"The cache spawns after the delay")
	check(delve.world.is_rope_lowered() and delve.world.is_hole_open(),"The rope drops and the floor opens")
	check(delve.world.get_node_or_null("Rope") != null,"The rope is a world node")
	check(delve.world.get_node_or_null("FloorHole") != null,"The floor hole is a world node")

	var credits_before: int = int(state.credits)
	var inventory_before: int = state.inventory.size()
	delve.open_chest()
	check(delve.chest_open and delve.chest.is_opened(),"Opening the cache is authoritative and visual")
	check(int(state.credits) == credits_before + 70,"Depth one pays 70 gold")
	check(state.inventory.size() == inventory_before + 1,"Depth one grants one cache item")
	delve.open_chest()
	check(int(state.credits) == credits_before + 70,"The cache cannot be looted twice")

	delve.descend_next_depth()
	check(delve.depth == 2 and delve.phase == "ALTAR","The open floor descends to depth two")
	check(not delve.chest_ready and not delve.chest_open,"Descending clears the old cache state")
	check(not delve.world.is_rope_lowered() and not delve.world.is_hole_open(),"The next depth starts sealed")
	check(delve.actors[0].global_position.y > 5.0,"The party falls into the recycled room")
	await create_timer(0.4).timeout
	delve.begin_wave()
	await create_timer(0.3).timeout
	var depth_two_total: int = delve._remaining_enemies()
	check(depth_two_total == 3,"Depth two starts with three devils")
	await _kill_devils(delve)
	check(delve.phase == "CLEARED","Depth two can also be cleared")
	await create_timer(2.5).timeout
	check(delve.chest_ready and delve.world.is_rope_lowered(),"Depth two offers its own cache and rope")

	delve.ascend_to_surface()
	await create_timer(0.6).timeout
	check(current_scene != null and current_scene.scene_file_path == "res://main.tscn","The rope returns to town")

	state.reset(false)
	_remove_test_save()
	print("DELVE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
