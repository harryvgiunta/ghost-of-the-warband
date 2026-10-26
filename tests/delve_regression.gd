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
const Devil = preload("res://scripts/delve_devil.gd")

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
	var species_health: Dictionary = {}
	var species_probe := true
	var ranger_probe := true
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
				if role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
					species_health[role] = float(devil.max_health)
					if str(devil._visual_kind) != "mob" \
							or devil.head_hit_profile().x <= 0.01 \
							or not devil.blood_strike_point().is_finite() \
							or devil.get_aim_position().y <= devil.global_position.y:
						species_probe = false
				elif role == "ranger":
					var clone_kind = devil.get("kind")
					if clone_kind == null or int(clone_kind) != 8 or not is_instance_valid(devil.rig) \
							or int(devil.collision_layer) != 2 or str(devil.held_weapon_id()).is_empty():
						ranger_probe = false
				var spawn_index := _nearest_spawn(delve.world,devil.global_position)
				if spawn_index >= 0:
					points[spawn_index] = true
			devil.take_damage(99999.0,-1)
		if delve.phase == "CLEARED":
			break
		await process_frame
	return {"cleared":delve.phase == "CLEARED", "spawned":spawned, "roles":roles,
		"points":points.size(), "sealed_seen":sealed_seen, "species_health":species_health,
		"species_probe":species_probe, "ranger_probe":ranger_probe}

func _check_first_plan(delve, plan: Array) -> void:
	check(plan.size() == 10,"The first wave plans ten enemies")
	var previous_at := -1.0
	var ordered := true
	var early := 0
	var opening := 0
	var known := true
	var imps := 0
	var devils := 0
	var rangers := 0
	var species := {}
	var placed := true
	var easy_first := true
	var last_tier := -1
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
		var tier := int(Devil.ROLE_DIFFICULTY.get(role,99))
		if tier < last_tier:
			easy_first = false
		last_tier = tier
		if role == "imp":
			imps += 1
		elif role == "devil":
			devils += 1
		elif role == "ranger":
			rangers += 1
		elif role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
			species[role] = true
		else:
			known = false
		if not _point_on_spawn(delve.world,entry.get("position")):
			placed = false
	check(ordered,"The wave plan is ordered by spawn time")
	check(easy_first,"The wave is scheduled from the lightest body to the heaviest")
	check(str(plan[0].get("role","")) == "imp","The first wave opens on imps")
	check(early <= 11 and opening >= 1,"The spawn times are weighted to the back of the window")
	var last_entry: Dictionary = plan[plan.size() - 1]
	check(absf(float(last_entry.get("at",0.0)) - 30.0) <= 0.01,"The last spawn lands on the thirty second mark")
	check(known,"Cycle one fields the plain ladder and the court devils")
	check(imps == 3 and devils == 2,"The cycle-one ladder is three imps and two devils")
	check(species.size() == 5,"All five court devils join the first wave")
	check(rangers == 0,"No crimson clone appears before the third wave")
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
	check(int(observed["spawned"]) == 10,"Every planned enemy reached the floor")
	var roles_one: Dictionary = observed["roles"]
	check(int(roles_one.get("imp",0)) == 3 and int(roles_one.get("devil",0)) == 2,"The first wave spawns its three imps and two devils")
	for role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
		check(int(roles_one.get(role,0)) == 1,"The first wave spawns one %s" % role)
	check(int(roles_one.get("ranger",0)) == 0,"The first wave brings no crimson clone")
	var species_base := {"hell_goat":72.0, "succubus":46.0, "spawn":22.0, "beast":130.0, "gargoyle":110.0}
	for role in species_base.keys():
		var expected := float(species_base[role]) * 0.45
		check(absf(float(observed["species_health"].get(role,-1.0)) - expected) < 0.01,"The %s enters the delve at its court-scaled health" % role)
	check(bool(observed["species_probe"]),"Every court devil runs its imported rig, head zone and strike hand")

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
	check(delve.wave_total == 15,"The ossuary fields fifteen enemies")
	var plan_two: Array = delve.wave_plan()
	check(plan_two.size() == 15,"The ossuary plan holds fifteen enemies")
	var roles_two := _role_counts(plan_two)
	check(int(roles_two.get("imp",0)) == 6 and int(roles_two.get("devil",0)) == 4,"The ossuary cycle-one ladder is six imps and four devils")
	for role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
		check(int(roles_two.get(role,0)) == 1,"The ossuary fields one %s" % role)
	check(int(roles_two.get("ranger",0)) == 0,"The ossuary's second wave still withholds the clones")

	var observed_two: Dictionary = await _clear_wave(delve,WAVE_DEADLINE)
	check(bool(observed_two["cleared"]),"The ossuary can be cleared")
	check(not delve.world.sealed,"Clearing the ossuary unseals it")
	check(int(observed_two["spawned"]) == 15,"Every ossuary enemy reached the floor")
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
	check(delve.wave_total == 20,"Cycle two scales to twenty enemies")
	var plan_three: Array = delve.wave_plan()
	check(plan_three.size() == 20,"The cycle-two plan holds twenty enemies")
	var roles_three := _role_counts(plan_three)
	check(int(roles_three.get("ranger",0)) == 1,"The third wave opens the crimson clones with one")
	check(str(plan_three[plan_three.size() - 1].get("role","")) == "ranger","The crimson clone closes the cycle-two schedule")
	for role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
		check(int(roles_three.get(role,0)) == 1,"Cycle two fields one %s" % role)
	check(int(roles_three.get("imp",0)) == 11 and int(roles_three.get("devil",0)) == 3,"The cycle-two ladder is eleven imps and three devils")
	var observed_three: Dictionary = await _clear_wave(delve,WAVE_DEADLINE)
	check(bool(observed_three["cleared"]),"The recycled sanctuary can be cleared")
	check(int(observed_three["roles"].get("ranger",0)) == 1,"The clone reached the floor")
	check(bool(observed_three["ranger_probe"]),"Clones carry their rig, body layer and rolled weapon")
	for role in species_base.keys():
		var expected := float(species_base[role]) * 0.45 * (1.0 + 0.28 * 2.0)
		check(absf(float(observed_three["species_health"].get(role,-1.0)) - expected) < 0.01,"The %s scales with depth three" % role)
	check(bool(observed_three["species_probe"]),"The court devils keep their imported rigs at depth three")
	var cache_three := await _wait_until(func(): return delve.chest_ready,CACHE_DEADLINE)
	check(cache_three,"The recycled sanctuary offers a cache")

	# Consumables route through the delve's own key map and action handler.
	var local = delve.actors[0]
	local.respawn_at(delve.world.rope_position)
	local.health = 40.0
	await _wait_until(func(): return local.is_on_floor(),3.0)
	var bandage_key := InputEventKey.new()
	bandage_key.keycode = KEY_6
	bandage_key.physical_keycode = KEY_6
	bandage_key.pressed = true
	Input.parse_input_event(bandage_key)
	Input.flush_buffered_events()
	var bandage_started := await _wait_until(func(): return local.consume_kind == "bandage",1.5)
	check(bandage_started,"The delve accepts the bandage key")
	local._cancel_consumable()
	local.health = 40.0
	var potion_key := InputEventKey.new()
	potion_key.keycode = KEY_7
	potion_key.physical_keycode = KEY_7
	potion_key.pressed = true
	Input.parse_input_event(potion_key)
	Input.flush_buffered_events()
	var potion_started := await _wait_until(func(): return local.consume_kind == "potion",1.5)
	check(potion_started,"The delve accepts the potion key")
	check(await _wait_until(func(): return local.health > 40.5,2.0),"The delve potion heals")

	delve.ascend_to_surface()
	var home := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://main.tscn",10.0)
	check(home,"The rope returns to town")

	state.reset(false)
	_remove_test_save()
	print("DELVE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
