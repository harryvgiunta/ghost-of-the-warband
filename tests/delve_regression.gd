extends SceneTree
## The Sunken Delve: checkpoint data, chamber contract, full 3-wave solo flow,
## chest timing/burst, explicit revive, party wipe, resume and both entry points.

const Progress = preload("res://scripts/delve_progress.gd")
const World = preload("res://scripts/delve_world.gd")
const TEST_SAVE := "user://delve_regression_state.json"

var failures := 0
var checks := 0
var session

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DELVE_FAIL  ", message)

func _remove_test_save() -> void:
	for path in [TEST_SAVE, TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _wait_until(predicate: Callable, timeout: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

func _free_game(game) -> void:
	if game == null:
		return
	game.leave_game()
	game.queue_free()
	await process_frame

func _host_scene(save_path: String):
	var game = load("res://delve.tscn").instantiate()
	game.save_path = save_path
	session.arm_delve("delve-solo", "127.0.0.1", 7777, "Delve regression")
	root.add_child(game)
	var ready := await _wait_until(func():
		return game.network_role == "host" and game.hud != null, 6.0)
	check(ready, "The delve scene hosts a solo run")
	await process_frame
	await process_frame
	return game

func _kill_live_devils(game) -> void:
	for devil in game.devils.duplicate():
		if is_instance_valid(devil) and devil.alive:
			devil.take_damage(9999.0, -1)

func _test_plan() -> void:
	check(Progress.WAVE_COUNT == 3, "The delve is three waves long")
	for wave in [1, 2, 3]:
		check(Progress.wave_size(wave) == 2, "Wave %d seeds two devils" % wave)
		var weapons: Array = Progress.wave_weapons(wave)
		check(weapons.size() == 2, "Wave %d declares two weapons" % wave)
		for weapon in weapons:
			check(str(weapon) in ["claw", "dagger", "sword"], "Wave %d rolls a melee devil" % wave)
	_remove_test_save()
	check(Progress.load_run(TEST_SAVE).is_empty(), "A missing checkpoint loads nothing")
	Progress.save_run(2, true, 424242, TEST_SAVE)
	var loaded := Progress.load_run(TEST_SAVE)
	check(int(loaded.get("wave", 0)) == 2, "The checkpoint keeps its wave")
	check(bool(loaded.get("chest_ready", false)), "The checkpoint keeps the cache flag")
	check(int(loaded.get("seed", 0)) == 424242, "The checkpoint keeps its seed")
	var corrupt := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	corrupt.store_string("{\"version\":1,\"wave\":9}")
	corrupt.close()
	check(Progress.load_run(TEST_SAVE).is_empty(), "An invalid checkpoint is rejected")
	Progress.save_run(1, false, 7, TEST_SAVE)
	Progress.clear_run(TEST_SAVE)
	check(Progress.load_run(TEST_SAVE).is_empty(), "Clearing removes the checkpoint")

func _test_world() -> void:
	var world = World.new()
	root.add_child(world)
	await process_frame
	check(world.CEILING_HEIGHT >= 12.0, "The chamber ceiling clears the shoulder camera")
	check(world.player_spawns.size() == 4, "Four party landing spots")
	check(world.enemy_spawns.size() == 4, "Four dark archways feed the wave")
	for spawn in world.enemy_spawns:
		check(spawn.has("position") and spawn.has("facing"), "Every archway carries a spawn and a facing")
	check(world.chest_position.distance_to(Vector3(0, 0.06, 0)) < 0.01, "The cache sits on the central dais")
	check(world.drop_center.y >= 6.0, "The drop falls from the shaft")
	check(world.ascent_position.y < 1.0 and absf(world.ascent_position.z) < 13.0,
		"The ascent prompt is reachable from the chamber floor")
	check(world.descent_position.y < 1.0 and world.descent_position.z < -12.0,
		"The descent prompt sits inside the south gate")
	check(int(world.generation_stats.get("solids", 0)) > 20, "The chamber builds real collision")
	var north := world.find_child("NorthGate", true, false)
	var south := world.find_child("SouthGate", true, false)
	check(north != null and south != null, "Both portcullises exist")
	if north != null and south != null:
		world.set_sealed(true)
		check(world.sealed, "Sealing sets the world flag")
		check(not (north.find_child("GateShape", true, false) as CollisionShape3D).disabled, "Sealed north gate blocks")
		check(not (south.find_child("GateShape", true, false) as CollisionShape3D).disabled, "Sealed south gate blocks")
		check((north.find_child("GateBars", true, false) as MeshInstance3D).visible, "Sealed bars are visible")
		world.set_sealed(false)
		check((north.find_child("GateShape", true, false) as CollisionShape3D).disabled, "Open north gate clears collision")
		check(not (north.find_child("GateBars", true, false) as MeshInstance3D).visible, "Open gate hides its bars")
	world.queue_free()
	await process_frame

func _test_solo_flow() -> void:
	_remove_test_save()
	var game = await _host_scene(TEST_SAVE)
	check(game.phase == "ASSEMBLY", "A host starts on the surface landing")
	check(game.get_human_count() == 1, "The host counts as the first delver")
	check(game.actors[0].alive, "The host starts alive")
	check(game.actors[0].global_position.y > 2.0, "The party waits on the raised landing")
	check(game.world.set_sealed != null and not game.world.sealed, "The landing gates start open")
	check(game.hud.wave_label != null, "The delve HUD is built")

	game.begin_descent()
	await process_frame
	check(game.phase == "WAVE", "Beginning the descent starts wave one")
	check(game.wave == 1, "Wave one is the first fight")
	check(game.world.sealed, "The chamber seals behind the drop")
	check(game.actors[0].combat.target_mask == 2, "Player attacks can reach the devil layer")
	var drop_offset: Vector3 = game.actors[0].global_position - game.world.drop_center
	drop_offset.y = 0.0
	check(drop_offset.length() < 4.0 and game.actors[0].global_position.y > 5.0,
		"The host is dropped into the chamber")

	var spawned := await _wait_until(func(): return game.devils.size() == 2, 5.0)
	check(spawned, "Wave one trickles in two devils")
	if spawned:
		for devil in game.devils:
			check(devil.authoritative, "The host owns devil simulation")
			check(devil.alive, "A fresh devil is alive")
			check(devil.devil_weapon in ["claw", "dagger", "sword"], "The devil carries a melee role")
		# Damage comes through the host's authoritative receive path.
		var devil = game.devils[0]
		var before: float = game.actors[0].health
		game.actors[0].receive_melee(10.0, 21, devil.global_position, false)
		check(game.actors[0].health < before, "A devil strike damages a delver")
		game.actors[0].health = 100.0

		# A real bow shot must travel through the combat pipeline and damage a
		# devil, proving the delve's target layer and projectile wiring.
		var landed := await _wait_until(func(): return game.actors[0].is_on_floor(), 3.0)
		check(landed, "The dropped delver lands on the chamber floor")
		game.actors[0].respawn_at(Vector3(0, 0.1, 1.5))
		for frozen in game.devils:
			if is_instance_valid(frozen):
				frozen.authoritative = false
		game.actors[0].health = 100.0
		await _wait_until(func(): return game.actors[0].combat.stagger_time <= 0.0, 1.5)
		await physics_frame
		devil = game.devils[0]
		devil.position = Vector3(0, 0.05, -2.5)
		# Suppress the local crosshair stream so this direct aim is not
		# overwritten by the unattended camera; host simulation continues.
		var saved_slot: int = game.local_slot
		game.local_slot = -1
		game.actors[0].rig.set_weapon("bow")
		game.actors[0].combat.set_aim(devil.get_aim_position())
		game.actors[0].combat.clear_camera_ray()
		var drawing: bool = game.actors[0].combat.begin_draw()
		check(drawing, "The delver can draw a bow in the chamber")
		await create_timer(0.95).timeout
		game.actors[0].combat.release_draw()
		var shot_landed := await _wait_until(func(): return devil.health < devil.max_health or not devil.alive, 2.0)
		game.local_slot = saved_slot
		check(shot_landed, "A real arrow damages a cinder devil")
		check(game.shots_fired >= 1, "The host records the released arrow")

	_kill_live_devils(game)
	await process_frame
	await process_frame
	check(game.phase == "CLEARED", "Killing the wave breaks the seal")
	check(not game.world.sealed, "The cleared wave opens the gates")
	check(game.chest_ready == false, "The cache waits for the clear timer")
	var timed := await _wait_until(func(): return game.chest_ready and is_instance_valid(game.chest), 4.0)
	check(timed, "The cache spawns after the clear timer")
	if timed:
		check(game.chest.has_node("LootBurst"), "The cache owns the loot burst")
		var saved := Progress.load_run(TEST_SAVE)
		check(int(saved.get("wave", 0)) == 1 and bool(saved.get("chest_ready", false)),
			"Wave one asserts a chest-ready checkpoint")
		game.open_chest()
		check(game.chest_open and game.chest.is_opened(), "The cache opens once")
		check((game.chest.get_node("LootBurst") as CPUParticles3D).emitting,
			"Opening the cache fires the loot burst")
		game.open_chest()
		check(game.chest_open, "Opening an open cache is idempotent")

	# A surviving non-host ranger can take the party through a cleared gate,
	# which matters when the host's own ranger is down.
	var guest = game.actors[1]
	guest.authoritative = true
	guest.configure(2, false, "Guest", game.world.descent_position)
	guest.authoritative = true
	guest.alive = true
	guest.visible = true
	guest.global_position = game.world.descent_position
	game._host_interact(1)
	await process_frame
	check(game.phase == "WAVE" and game.wave == 2, "Descending starts wave two")
	check(game.actors[1].peer_id == 2, "The survivor's seat drove the descent")
	check(game.world.sealed, "Wave two seals the chamber again")
	check(not is_instance_valid(game.chest) or game.chest.is_queued_for_deletion(), "The old cache leaves with its wave")
	var wave2 := await _wait_until(func(): return game.devils.size() == 2, 5.0)
	check(wave2, "Wave two trickles in two devils")
	_kill_live_devils(game)
	var clear2 := await _wait_until(func(): return game.chest_ready and is_instance_valid(game.chest), 5.0)
	check(clear2, "Wave two offers its cache")
	if clear2:
		game.open_chest()
	game.descend_next_wave()
	await process_frame
	check(game.phase == "WAVE" and game.wave == 3, "Descending starts wave three")
	var wave3 := await _wait_until(func(): return game.devils.size() == 2, 5.0)
	check(wave3, "Wave three trickles in two devils")
	_kill_live_devils(game)
	var clear3 := await _wait_until(func(): return game.chest_ready and is_instance_valid(game.chest), 5.0)
	check(clear3, "Wave three offers the final cache")
	if clear3:
		var final_save := Progress.load_run(TEST_SAVE)
		check(int(final_save.get("wave", 0)) == 3 and bool(final_save.get("chest_ready", false)),
			"The final cache is checkpointed")
		game.open_chest()
		await process_frame
		check(game.phase == "COMPLETE", "Claiming the final cache completes the run")
		check(Progress.load_run(TEST_SAVE).is_empty(), "Completion clears the checkpoint")

	# Explicit revival is the only way back up: no inherited arena respawn.
	game.actors[0].take_damage(9999.0, 99)
	check(not game.actors[0].alive, "Lethal damage downs the host")
	check(game.actors[0].respawn > 100000.0, "The inherited arena respawn countdown is disabled")
	game.actors[0].respawn_at(game.world.player_spawns[0])
	check(game.actors[0].alive, "Explicit revive brings a delver back")

	await _free_game(game)

func _test_resume() -> void:
	_remove_test_save()
	Progress.save_run(2, true, 909090, TEST_SAVE)
	var game = await _host_scene(TEST_SAVE)
	check(int(game.resume_data.get("wave", 0)) == 2, "The landing reads the saved wave")
	check(int(game.run_seed) == 909090, "The landing restores the run seed")
	game.begin_descent()
	await process_frame
	check(game.phase == "CLEARED", "A saved cache resumes already cleared")
	check(game.wave == 2, "The saved wave is the one resumed")
	check(game.chest_ready and is_instance_valid(game.chest), "The saved cache is present on resume")
	check(not game.world.sealed, "A resumed cleared room is open")
	var landed := await _wait_until(func(): return game.actors[0].global_position.y < 3.0, 3.0)
	check(landed, "Resuming drops the party into the room")
	await _free_game(game)

func _test_wipe() -> void:
	_remove_test_save()
	var game = await _host_scene(TEST_SAVE)
	game.begin_descent()
	await process_frame
	Progress.save_run(1, false, 55, TEST_SAVE)
	game.actors[0].take_damage(9999.0, 99)
	var wiped := await _wait_until(func(): return game.phase == "GAME_OVER", 2.0)
	check(wiped, "A party wipe ends the run")
	check(game.hud.game_over_layer.visible, "The game-over overlay is shown")
	check(Progress.load_run(TEST_SAVE).is_empty(), "A wipe clears the checkpoint")
	await _free_game(game)

func _test_entries() -> void:
	var session_node := root.get_node_or_null("Session")
	check(session_node != null and session_node.has_method("arm_delve"), "Session exposes the delve hand-off")
	if session_node != null:
		session_node.arm_delve("delve-host", "127.0.0.1", 7901, " Delve ")
		var request: Dictionary = session_node.take()
		check(str(request.mode) == "delve-host" and int(request.port) == 7901, "The delve hand-off keeps its mode and port")
		check(str(request.name) == "Delve", "The delve hand-off trims the name")
		session_node.clear()

	var frontier = load("res://main.tscn").instantiate()
	root.add_child(frontier)
	await create_timer(0.6).timeout
	var delve_entry: Dictionary = {}
	for entry in frontier.world.interactables:
		if str(entry.get("id", "")) == "delve":
			delve_entry = entry
			break
	check(not delve_entry.is_empty(), "Hearthstead exposes the inn hatch")
	if not delve_entry.is_empty():
		frontier.player.global_position = (delve_entry.get("position", Vector3.ZERO) as Vector3) + Vector3(0, 0.25, 1.0)
		frontier._update_interaction()
		check(frontier._interaction_id == "delve", "Standing at the hatch selects the delve")
		check(frontier._interaction_allowed, "The delve entrance is usable")
		check(frontier.hud._interaction.text.contains("Sunken Delve"), "The prompt names the delve")
	frontier.queue_free()
	await process_frame

	var menu = load("res://menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	check(menu.hud.delve_button != null and menu.hud.delve_button.visible, "The Hollow offers the delve")
	check(menu.hud.delve_host_button.visible and menu.hud.delve_join_button.visible,
		"The Hollow offers delve hosting and joining")
	menu.hud.set_delve_progress(2, false)
	check(menu.hud.delve_button.text.contains("WAVE 2"), "The hub resumes a saved wave")
	menu.hud.set_delve_progress(2, true)
	check(menu.hud.delve_button.text.contains("WAVE 2 CACHE"), "The hub labels an early-wave cache")
	menu.hud.set_delve_progress(3, true)
	check(menu.hud.delve_button.text.contains("FINAL CACHE"), "The hub labels a saved final cache")
	menu.queue_free()
	await process_frame

func run() -> void:
	_remove_test_save()
	session = root.get_node_or_null("Session")
	check(session != null, "The Session autoload exists")
	_test_plan()
	await _test_world()
	await _test_solo_flow()
	await _test_resume()
	await _test_wipe()
	await _test_entries()
	_remove_test_save()
	print("DELVE_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
