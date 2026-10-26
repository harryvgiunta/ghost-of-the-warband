extends SceneTree
## Town exits: falling through the inn hatch enters the delve, the arena portal
## hosts a match, and the delve rope returns to town.

const TEST_SAVE := "user://delve_entry_state.json"

var state
var session
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ENTRY_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _entry(world, id: String) -> Dictionary:
	for item in world.interactables:
		if str(item.id) == id:
			return item
	return {}

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_SAVE
	state.reset(false)

	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	game.set_physics_process(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	check(game.world.player_spawn.distance_to(Vector3(0,3,47)) < 0.05,"A new journey starts at the town gate")
	var hatch := _entry(game.world,"delve")
	check(not hatch.is_empty(),"The delve hatch remains a map marker")
	var inn = game.world.get_node_or_null("WayfarerInn")
	check(inn != null and inn.get_node_or_null("SunkenDelveHatch") != null,"The hatch is built inside the Wayfarer Inn")
	var hatch_node = inn.get_node("SunkenDelveHatch") if inn != null else null
	if hatch_node != null:
		check(absf(hatch_node.global_position.x - 16.0) < 0.05 and absf(hatch_node.global_position.z - 42.0) < 0.05,"The hatch sits over the open floor cell")
	check(game.world.is_over_delve_hatch(Vector3(16,2.2,42)),"The hatch footprint is open at the floor")
	check(not game.world.is_over_delve_hatch(Vector3(12,2.2,42)),"The hatch does not trigger outside the opening")

	var portal := _entry(game.world,"arena_portal")
	check(not portal.is_empty() and str(portal.kind) == "portal","The arena portal is interactive")
	check(game.world.get_node_or_null("ArenaPortal") != null,"The portal has a placeholder world node")
	var stash := _entry(game.world,"stash")
	check(not stash.is_empty() and game.world.get_node_or_null("TownStash") != null,"The stash chest is in town")

	# A real fall through the hatch opens the delve inside the running session:
	# the frontier is frozen, not destroyed, so the rope hands it back untouched.
	var probe_mob = game.enemies[0]
	var probe_layer := int(probe_mob.collision_layer)
	var probe_at: Vector3 = probe_mob.global_position
	var outer_health: float = game.health
	var outer_gold: int = game.gold
	game.set_physics_process(true)
	game.player.global_position = Vector3(16,3.8,42)
	game.player.velocity = Vector3.ZERO
	await create_timer(0.9).timeout
	var delve = game._delve_inner
	check(current_scene == null and game.is_inside_tree(),"The fall does not load another scene")
	check(delve != null and is_instance_valid(delve),"The fall opens an inner delve instance")
	if is_instance_valid(delve):
		check(String(delve.get_path()) == "/root/Ironwood/Delve","The run is instanced under the session root")
		check(str(delve.phase) == "ALTAR","The fall lands at the altar phase")
		check(str(delve.network_role) == "host","The hatch opens a solo host")
		check(delve.world.is_built(),"The inner run builds its own room")
		check(game._frontier.process_mode == Node.PROCESS_MODE_DISABLED and not game._frontier.visible,"The frontier freezes behind the run")
		check(not game._ui_layer.visible,"The frontier HUD hides behind the run")
		check(int(probe_mob.collision_layer) == 0,"Frontier bodies stop colliding inside the run")
		delve._set_phase("CLEARED")
		delve.ascend_to_surface()
		await create_timer(0.7).timeout
		check(game._delve_inner == null,"The rope ends the inner run")
		check(not is_instance_valid(delve),"The disposable run is freed")
		check(game.is_inside_tree() and str(game.network_role) == "offline","The session survives the run")
		check(game.multiplayer.multiplayer_peer is OfflineMultiplayerPeer,"The solo run closes the server it opened and hands the world back")
		check(game._frontier.visible and game._frontier.process_mode == Node.PROCESS_MODE_INHERIT,"The frontier resumes")
		check(game._ui_layer.visible,"The frontier HUD returns")
		check(game.camera.current,"The frontier camera takes the view back")
		check(int(probe_mob.collision_layer) == probe_layer,"Frontier bodies collide again after the rope")
		check(probe_mob.global_position.distance_to(probe_at) < 0.01,"The frozen mobs did not move during the run")
		check(is_instance_valid(game.enemies[0]) and game.enemies[0] == probe_mob,"The same mobs come back, not a rebuild")
		check(absf(game.health - outer_health) < 0.01 and game.gold == outer_gold,"The outer ranger's state is untouched by the run")
		check(game.player.global_position.z > 43.0 and game.player.global_position.y > 3.0,"The ranger steps out of the hatch")

	# The arena is still its own scene; the open world is freed before that trip.
	game.queue_free()
	await process_frame

	# The arena portal hosts a practice match and returns to town.
	var trip = load("res://main.tscn").instantiate()
	root.add_child(trip)
	await create_timer(0.4).timeout
	trip.set_physics_process(false)
	trip._enter_arena()
	await create_timer(0.7).timeout
	check(current_scene != null and current_scene.scene_file_path == "res://arena.tscn","The portal loads the arena")
	if current_scene != null and current_scene.get("network_role") != null:
		check(str(current_scene.network_role) == "host","The portal hosts a local match")
		current_scene._hub()
		await create_timer(0.5).timeout
		check(current_scene != null and current_scene.scene_file_path == "res://main.tscn","The arena returns to town")

	state.reset(false)
	_remove_test_save()
	print("DELVE_ENTRY_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
