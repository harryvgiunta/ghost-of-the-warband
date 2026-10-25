extends SceneTree
## Endless Sunken Delve: fall in, touch the altar, wake the pentagram, break the
## weighted wave, loot the cache, then descend through the floor into the
## ossuary and back up into a freshly coloured sanctuary.

const TEST_SAVE := "user://delve_regression_state.json"
const PORT := 7831
const SPAWN_SCALE := 8.0
const WAVE_DEADLINE := 25.0
const CACHE_DEADLINE := 6.0
const PHASE_DEADLINE := 12.0

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

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

func _host_scene() -> Node:
	session.arm_delve("delve-solo","127.0.0.1",PORT,"Tester")
	var scene = load("res://delve.tscn").instantiate()
	root.add_child(scene)
	await _wait_until(func(): return scene.network_role == "host",6.0)
	await create_timer(0.2).timeout
	return scene

## The run state is the only shared surface that carries the ritual clock, so
## read it through the public probe and fall back to the replicated copy.
func _run_state(delve) -> Dictionary:
	if delve.has_method("reach_phase"):
		var state_now = delve.reach_phase()
		if state_now is Dictionary:
			return state_now
	var remote = delve.get("_remote_state")
	if remote is Dictionary:
		return remote
	return {}

func _ritual_progress(delve) -> float:
	return maxf(0.0,float(_run_state(delve).get("ritual",0.0)))

func _nearest_spawn(world, point: Vector3) -> int:
	var best := -1
	var best_distance := 2.0
	for index in world.spawn_points.size():
		var distance: float = world.spawn_points[index].distance_to(point)
		if distance <= best_distance:
			best_distance = distance
			best = index
	return best

func _role_counts(plan: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry in plan:
		var role := str(entry.get("role",""))
		counts[role] = int(counts.get(role,0)) + 1
	return counts

func _point_on_spawn(world, point: Variant) -> bool:
	if not (point is Vector3):
		return false
	for spawn in world.spawn_points:
		if spawn.distance_to(point) <= 0.001:
			return true
	return false

## Kill every live devil each frame until the wave breaks, recording where the
## enemies actually emerged and whether the room stayed sealed.
func _clear_wave(delve, timeout: float) -> Dictionary:
	var roles: Dictionary = {}
	var points: Dictionary = {}
	var seen: Dictionary = {}
	var spawned := 0
	var sealed_seen := false
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if delve.phase == "WAVE" and bool(delve.world.sealed):
			sealed_seen = true
		for devil in delve.devils.duplicate():
			if not is_instance_valid(devil) or not devil.alive:
				continue
			var key: int = devil.get_instance_id()
			if not seen.has(key):
				seen[key] = true
				spawned += 1
				var role := str(devil.role())
				roles[role] = int(roles.get(role,0)) + 1
				var spawn_index := _nearest_spawn(delve.world,devil.global_position)
				if spawn_index >= 0:
					points[spawn_index] = true
			devil.take_damage(99999.0,-1)
		if delve.phase == "CLEARED":
			break
		await process_frame
	return {"cleared":delve.phase == "CLEARED", "spawned":spawned, "roles":roles,
		"points":points.size(), "sealed_seen":sealed_seen}

func _check_first_plan(delve, plan: Array) -> void:
	check(plan.size() == 10,"The first wave plans ten enemies")
	var previous_at := -1.0
	var ordered := true
	var early := 0
	var opening := 0
	var kinds_ok := true
	var imps := 0
	var placed := true
	for index in plan.size():
		var entry: Dictionary = plan[index]
		var at := float(entry.get("at",0.0))
		if index > 0 and at < previous_at:
			ordered = false
		previous_at = at
		if at <= 15.0:
			early += 1
		if at <= 5.0:
			opening += 1
		var role := str(entry.get("role",""))
		if role == "imp":
			imps += 1
		elif role != "devil":
			kinds_ok = false
		if not _point_on_spawn(delve.world,entry.get("position")):
			placed = false
	check(ordered,"The wave plan is ordered by spawn time")
	check(early <= 4 and opening >= 1,"The spawn times are weighted to the back of the window")
	var last_entry: Dictionary = plan[plan.size() - 1]
	check(absf(float(last_entry.get("at",0.0)) - 30.0) <= 0.01,"The last spawn lands on the thirty second mark")
	check(kinds_ok,"The first wave only fields imps and devils")
	check(imps * 2 > plan.size(),"Imps are the strict majority of the first wave")
	check(placed,"Every planned spawn sits on a chamber spawn point")

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	session = root.get_node("Session")
	state.save_path = TEST_SAVE
	state.reset(false)

	var delve = await _host_scene()
	check(delve.network_role == "host","The delve hosts solo")
	check(delve.depth == 1 and delve.phase == "ALTAR","Entry lands at the depth-one altar")
	check(str(delve.world.room_kind) == "sanctuary","The first room is the sanctuary")
	check(delve.world.has_altar(),"The sanctuary offers an altar")
	check(not delve.world.is_pentagram_active(),"The pentagram sleeps before the ritual")
	check(delve.world.beacon_active("altar"),"The altar beacon marks the decision point")
	check(not delve.world.beacon_active("rope") and not delve.world.beacon_active("hole"),"The rope and hole beacons are dark")
	check(delve.world.find_child("NorthGate",true,false) == null and delve.world.find_child("SouthGate",true,false) == null,"The sanctuary has no portcullis gates")
	check(delve.chest == null and not delve.chest_ready,"No cache before the first wave")
	var accent_one: Color = delve.world.palette()["accent"]

	delve.spawn_time_scale = SPAWN_SCALE

	delve.actors[0].global_position = delve.world.altar_position + Vector3(0,0.1,1.2)
	delve.begin_wave()
	check(delve.phase == "RITUAL","Touching the altar wakes the ritual")
	check(delve.world.is_pentagram_active(),"The pentagram burns during the ritual")
	check(delve.world.sealed,"The ritual seals the room")
	# The controller freezes the plan when the ritual starts, before any enemy
	# reaches the floor, so this is the earliest point the plan is observable.
	check(delve.devils.is_empty(),"No devil stands on the floor when the plan is built")
	_check_first_plan(delve,delve.wave_plan())
	var ritual_seen := 0.0
	var ritual_advanced := false
	var ritual_deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < ritual_deadline and delve.phase == "RITUAL":
		var progress := _ritual_progress(delve)
		if progress > ritual_seen + 0.0001:
			ritual_advanced = true
		ritual_seen = maxf(ritual_seen,progress)
		await process_frame
	check(ritual_seen > 0.0,"The ritual progress advances")
	check(ritual_advanced,"The ritual progress keeps climbing")
	var wave_one := await _wait_until(func(): return delve.phase == "WAVE",6.0)
	check(wave_one,"The ritual ends into the first wave")
	check(delve.wave_total == 10,"The first wave holds ten enemies")
	check(_ritual_progress(delve) >= 0.99,"The ritual completes when the wave starts")

	var observed: Dictionary = await _clear_wave(delve,WAVE_DEADLINE)
	check(bool(observed["cleared"]),"Clearing every devil ends the wave")
	check(observed["sealed_seen"],"The room stays sealed for the whole wave")
	check(not delve.world.sealed,"Clearing the wave unseals the room")
	check(int(observed["spawned"]) == 10,"Every planned devil reached the floor")
	var roles_one: Dictionary = observed["roles"]
	check(int(roles_one.get("imp",0)) > 0,"Imps spawn in the first wave")
	check(int(roles_one.get("devil",0)) > 0,"Devils spawn in the first wave")
	check(int(observed["points"]) >= 5,"The wave emerged from distinct spawn points across the room")

	check(not delve.world.is_pentagram_active(),"The pentagram dims when the wave clears")
	check(_ritual_progress(delve) <= 0.01,"The ritual goes dark when the wave clears")
	check(not delve.chest_ready,"The cache waits out the clear delay")
	var cache_one := await _wait_until(func(): return delve.chest_ready and is_instance_valid(delve.chest),CACHE_DEADLINE)
	check(cache_one,"The cache arrives after the delay")
	check(delve.world.is_rope_lowered() and delve.world.is_hole_open(),"The rope lowers and the floor opens")
	check(delve.world.beacon_active("rope") and delve.world.beacon_active("hole"),"The exit beacons light with the cache")
	check(not delve.world.beacon_active("altar"),"The altar beacon sleeps once the room is won")
	check(delve.world.get_node_or_null("Rope") != null,"The rope is a world node")
	check(delve.world.get_node_or_null("FloorHole") != null,"The floor hole is a world node")

	var credits_before: int = int(state.credits)
	delve.open_chest()
	var credits_after: int = int(state.credits)
	check(delve.chest_open and delve.chest.is_opened(),"Opening the cache is authoritative and visual")
	check(credits_after > credits_before,"The depth-one cache pays out")
	delve.open_chest()
	check(int(state.credits) == credits_after,"The cache cannot be looted twice")

	delve.descend_next_depth()
	check(delve.depth == 2,"The open floor descends to depth two")
	check(str(delve.world.room_kind) == "ossuary","Depth two is the ossuary")
	check(delve.world.cycle == 1,"The ossuary opens cycle one")
	check(delve.phase == "DROP","The ossuary waits for the party to land")
	check(not delve.world.has_altar() and delve.world.get_node_or_null("Altar") == null,"The ossuary has no altar")
	check(not delve.world.beacon_active("altar"),"The ossuary has no altar beacon")
	check(not delve.world.is_rope_lowered() and not delve.world.is_hole_open(),"The next depth resets the rope and hole")
	check(not delve.chest_ready and not delve.chest_open and delve.chest == null,"Descending clears the old cache state")
	check(delve.actors[0].global_position.y > 5.0,"The party falls into the ossuary")
	delve.spawn_time_scale = SPAWN_SCALE

	var drop_ritual := await _wait_until(func(): return delve.phase == "RITUAL",PHASE_DEADLINE)
	check(drop_ritual,"Landing in the ossuary starts its ritual")
	var wave_two := await _wait_until(func(): return delve.phase == "WAVE",PHASE_DEADLINE)
	check(wave_two,"The ossuary ritual ends into its wave")
	check(delve.wave_total == 20,"The ossuary fields twenty enemies")
	var plan_two: Array = delve.wave_plan()
	check(plan_two.size() == 20,"The ossuary plan holds twenty enemies")
	var roles_two := _role_counts(plan_two)
	check(int(roles_two.get("imp",0)) == 4 and int(roles_two.get("brute",0)) == 6 and int(roles_two.get("bonefiend",0)) == 10,"The ossuary mixes imps, brutes and bonefiends")
	var last_imp := -1
	var first_elite := -1
	for index in plan_two.size():
		var entry: Dictionary = plan_two[index]
		if str(entry.get("role","")) == "imp":
			last_imp = index
		elif first_elite < 0:
			first_elite = index
	check(last_imp >= 0 and first_elite > last_imp,"The ossuary sends its elites after the imps")

	var observed_two: Dictionary = await _clear_wave(delve,WAVE_DEADLINE)
	check(bool(observed_two["cleared"]),"The ossuary can be cleared")
	check(not delve.world.sealed,"Clearing the ossuary unseals it")
	check(int(observed_two["spawned"]) == 20,"Every ossuary enemy reached the floor")
	var cache_two := await _wait_until(func(): return delve.chest_ready and is_instance_valid(delve.chest),CACHE_DEADLINE)
	check(cache_two,"The ossuary offers its own cache")

	delve.descend_next_depth()
	check(delve.depth == 3,"Dropping again reaches depth three")
	check(str(delve.world.room_kind) == "sanctuary","Odd depths return to the sanctuary")
	check(delve.world.cycle == 2,"Depth three opens cycle two")
	check(delve.phase == "ALTAR","The recycled sanctuary starts at its altar")
	check(delve.world.has_altar(),"The new sanctuary has an altar")
	check(delve.world.beacon_active("altar"),"The new sanctuary lights its altar beacon")
	check(not delve.world.is_pentagram_active(),"The new sanctuary's pentagram sleeps")
	var accent_two: Color = delve.world.palette()["accent"]
	check(accent_two != accent_one,"The next sanctuary cycle repaints the room")

	delve.spawn_time_scale = SPAWN_SCALE
	delve.begin_wave()
	var wave_three := await _wait_until(func(): return delve.phase == "WAVE",PHASE_DEADLINE)
	check(wave_three,"The recycled sanctuary runs its own ritual")
	var observed_three: Dictionary = await _clear_wave(delve,WAVE_DEADLINE)
	check(bool(observed_three["cleared"]),"The recycled sanctuary can be cleared")
	var cache_three := await _wait_until(func(): return delve.chest_ready,CACHE_DEADLINE)
	check(cache_three,"The recycled sanctuary offers a cache")

	delve.ascend_to_surface()
	var home := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://main.tscn",10.0)
	check(home,"The rope returns to town")

	state.reset(false)
	_remove_test_save()
	print("DELVE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
