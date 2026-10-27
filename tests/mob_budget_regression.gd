extends SceneTree
## The wilderness tick budget: bands, carried time, and the one rule that makes
## it safe - a body on a long budget covers exactly the same ground as one
## ticking every frame. Plus the end of the budget: past the fog wall a body is
## parked outright, and the frontier test at the bottom proves a real one stops.

const MobLod = preload("res://scripts/mob_lod.gd")


## Slack inside the wake radius: bodies this close must never be parked.
const NEAR_SLACK := 8.0


## A body that walks itself one direction at a fixed speed, on a budget.
class Runner:
	extends CharacterBody3D
	var every := 1
	var speed := 1.0
	var travel := 0.0
	var frame := 0
	var grounded_ticks := 0

	func _physics_process(_delta: float) -> void:
		velocity = Vector3(speed, velocity.y, 0.0)
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= 18.0 * _delta
		frame += 1
		if frame % every != 0:
			return
		var before := global_position
		MobLod.move(self, (1.0 / 60.0) * float(every))
		# Horizontal ground covered: a settling drop is not walking.
		travel += Vector2(global_position.x - before.x, global_position.z - before.z).length()
		if is_on_floor():
			grounded_ticks += 1


var world: Node3D
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("BUDGET_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_check_bands()
	_check_carried_time()
	_check_presentation_bands()
	_check_dormancy()
	await _check_flat_ground()
	await _check_slope()
	await _check_frontier_parking()
	world.queue_free()
	await process_frame
	print("MOB_BUDGET_REGRESSION checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)


## Every band sits its frames out, and the rates are the documented ones.
func _check_bands() -> void:
	var near := MobLod.new(0)
	var near_grants := 0
	for index in 120:
		if near.slice(5.0, 1.0 / 60.0) > 0.0:
			near_grants += 1
	check(near_grants == 120, "a body inside 22 m ticks every frame (granted %d)" % near_grants)
	var calm_near := MobLod.new(0)
	var calm_grants := 0
	for index in 120:
		if calm_near.slice(5.0, 1.0 / 60.0, true) > 0.0:
			calm_grants += 1
	check(calm_grants == 60, "a calm body inside 22 m ticks every other frame (granted %d)" % calm_grants)
	var mid := MobLod.new(0)
	var mid_grants := 0
	for index in 120:
		if mid.slice(40.0, 1.0 / 60.0) > 0.0:
			mid_grants += 1
	check(mid_grants == 40, "a body at 40 m ticks every third frame (granted %d)" % mid_grants)
	var far := MobLod.new(0)
	var far_grants := 0
	for index in 120:
		if far.slice(70.0, 1.0 / 60.0) > 0.0:
			far_grants += 1
	check(far_grants == 10, "a body at 70 m ticks every twelfth frame (granted %d)" % far_grants)
	var deep := MobLod.new(0)
	var deep_grants := 0
	for index in 120:
		if deep.slice(MobLod.DORMANT_DISTANCE - 8.0, 1.0 / 60.0) > 0.0:
			deep_grants += 1
	check(deep_grants == 5, "the deepest band ticks every twenty-fourth frame (granted %d)" % deep_grants)
	check(deep.grants == deep_grants, "the budget counts its grants")


## A skipped frame is not lost time: the granted deltas still add up to a second.
func _check_carried_time() -> void:
	for entry in [[5.0, false], [5.0, true], [40.0, false], [70.0, false],
			[MobLod.DORMANT_DISTANCE - 8.0, false]]:
		var lod := MobLod.new(3)
		var total := 0.0
		for index in 240:
			total += lod.slice(float(entry[0]), 1.0 / 60.0, bool(entry[1]))
		check(absf(total - 4.0) <= 0.45,
			"a budgeted body is granted its full time at %.0f m (got %.3f s of 4 s)" %
				[float(entry[0]), total])


## Presentation rests past the documented distances.
func _check_presentation_bands() -> void:
	check(MobLod.band(10.0) == 0, "inside 30 m a body casts a shadow")
	check(MobLod.band(45.0) == 1, "past 30 m a body animates without a shadow")
	check(MobLod.band(100.0) == 2, "past 62 m a body rests")
	var holder := Node3D.new()
	world.add_child(holder)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	holder.add_child(mesh_instance)
	var player := AnimationPlayer.new()
	holder.add_child(player)
	MobLod.present(holder, player, 10.0)
	check(player.active, "a near body keeps evaluating its animation")
	check(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"a near body casts a shadow")
	MobLod.present(holder, player, 45.0)
	check(player.active, "a mid body still animates")
	check(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a mid body stops casting a shadow")
	MobLod.present(holder, player, 100.0)
	check(not player.active, "a far body stops evaluating its animation")
	check(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a far body casts no shadow")
	world.remove_child(holder)
	holder.free()


## The end of the budget: past the park radius a body is granted nothing at
## all, and a body that wakes banks none of the sleep.
func _check_dormancy() -> void:
	check(not MobLod.dormant(MobLod.DORMANT_DISTANCE - 1.0, false),
		"a body just inside the park radius keeps ticking")
	check(MobLod.dormant(MobLod.DORMANT_DISTANCE + 1.0, false),
		"a body just past the park radius parks")
	var between := (MobLod.DORMANT_DISTANCE + MobLod.WAKE_DISTANCE) * 0.5
	check(MobLod.dormant(between, true),
		"a parked body stays parked inside the wake radius (hysteresis)")
	check(not MobLod.dormant(between, false),
		"an awake body at the same distance keeps ticking")
	check(not MobLod.dormant(MobLod.WAKE_DISTANCE - 1.0, true),
		"a parked body wakes inside the wake radius")
	check(not MobLod.dormant(INF, false), "a body with no ranger in the world never parks")
	var orphan := MobLod.new(0)
	var orphan_grants := 0
	for index in 120:
		if orphan.slice(INF, 1.0 / 60.0) > 0.0:
			orphan_grants += 1
	check(orphan_grants == 5,
		"a scene with no ranger still ticks its bodies on the deepest band (%d)" % orphan_grants)
	var parked := MobLod.new(0)
	var parked_grants := 0
	for index in 300:
		if parked.slice(200.0, 1.0 / 60.0) > 0.0:
			parked_grants += 1
	check(parked_grants == 0, "a parked body is granted nothing at all (%d grants)" % parked_grants)
	check(parked.grants == 0, "and counts no tick")
	var deep := MobLod.new(0)
	var deep_grants := 0
	for index in 120:
		if deep.slice(MobLod.DORMANT_DISTANCE - 8.0, 1.0 / 60.0) > 0.0:
			deep_grants += 1
	check(deep_grants == 5, "just inside the park radius a body still ticks at 2.5 Hz (%d)" % deep_grants)
	# The sleep is not banked: the first frame back is one frame.
	var slept := MobLod.new(0)
	for index in 3600:
		slept.slice(200.0, 1.0 / 60.0)
	slept.resume()
	var first := slept.slice(MobLod.DORMANT_DISTANCE - 8.0, 1.0 / 60.0)
	check(absf(first - 1.0 / 60.0) < 0.0005,
		"a body that slept a minute wakes on one normal frame (%.4f s)" % first)
	check(slept.grants == 1, "and is granted its first tick back")
	var near := MobLod.new(0)
	near.resume()
	var near_first := near.slice(5.0, 1.0 / 60.0)
	check(absf(near_first - 1.0 / 60.0) < 0.0005,
		"a near body that wakes integrates one frame too (%.4f s)" % near_first)


func _plate(at: Vector3, tilt_degrees: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	body.rotation.x = deg_to_rad(tilt_degrees)
	world.add_child(body)
	return body


func _runner(at: Vector3, every: int) -> Runner:
	var runner := Runner.new()
	runner.collision_layer = 2
	runner.collision_mask = 1
	runner.max_slides = 2
	runner.floor_stop_on_slope = false
	runner.floor_snap_length = 0.6
	runner.every = every
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 2.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 1.0
	runner.add_child(collider)
	runner.position = at
	world.add_child(runner)
	return runner


## A body on a twenty-four-frame budget must cover the same ground per second
## as one ticking every frame: that is the whole contract of the carried delta.
func _check_flat_ground() -> void:
	_plate(Vector3(0.0, -0.5, 0.0), 0.0)
	await physics_frame
	var fast := _runner(Vector3(0.0, 3.0, 0.0), 1)
	var slow := _runner(Vector3(20.0, 3.0, 0.0), 24)
	await create_timer(1.5).timeout
	fast.travel = 0.0
	slow.travel = 0.0
	fast.grounded_ticks = 0
	slow.grounded_ticks = 0
	await create_timer(3.0).timeout
	check(fast.travel > 2.0, "a per-frame body walks (%.2f m)" % fast.travel)
	var ratio := slow.travel / maxf(fast.travel, 0.001)
	check(absf(ratio - 1.0) < 0.12,
		"a budgeted body covers the same ground (%.2f m vs %.2f m, ratio %.2f)" %
			[slow.travel, fast.travel, ratio])
	check(slow.grounded_ticks > 0, "a budgeted body still reports the floor")
	check(absf(slow.global_position.y - fast.global_position.y) < 0.35,
		"a budgeted body keeps its feet on the same ground (%.2f vs %.2f)" %
			[slow.global_position.y, fast.global_position.y])
	fast.queue_free()
	slow.queue_free()
	await process_frame


## Slopes must not eat the sweep: the tilt used to cancel horizontal motion.
func _check_slope() -> void:
	_plate(Vector3(-80.0, 9.5, 0.0), 18.0)
	_plate(Vector3(80.0, -0.5, 0.0), 0.0)
	await physics_frame
	var sloped := _runner(Vector3(-80.0, 15.0, 0.0), 24)
	var flat := _runner(Vector3(80.0, 3.0, 0.0), 24)
	await create_timer(1.5).timeout
	flat.travel = 0.0
	sloped.travel = 0.0
	flat.grounded_ticks = 0
	sloped.grounded_ticks = 0
	await create_timer(3.0).timeout
	check(flat.travel > 1.0 and sloped.travel > 0.7 * flat.travel,
		"a sloped body keeps moving (flat %.2f m, sloped %.2f m)" % [flat.travel, sloped.travel])
	check(sloped.grounded_ticks > 0, "the sloped body stays on its ramp")
	flat.queue_free()
	sloped.queue_free()
	await process_frame


## The frontier itself: the fog closes the view before the park radius, the
## camera stops with the fog, and a real mob past the wall stops running.
func _check_frontier_parking() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	check(packed_scene != null, "main.tscn loads")
	if packed_scene == null:
		return
	var state = root.get_node_or_null("PlayerState")
	if state != null:
		state.reset(false)
	var frontier := packed_scene.instantiate()
	root.add_child(frontier)
	await process_frame
	await process_frame
	var environment: Environment = null
	if is_instance_valid(frontier._frontier_environment):
		environment = frontier._frontier_environment.environment
	check(environment != null, "the frontier builds its environment")
	if environment != null:
		check(environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH,
			"the frontier fades with depth fog, not a flat haze")
		check(environment.fog_depth_end > environment.fog_depth_begin,
			"the fog ramps outward (%.0f m to %.0f m)" % [environment.fog_depth_begin, environment.fog_depth_end])
		check(environment.fog_depth_end < MobLod.DORMANT_DISTANCE,
			"the haze is fully opaque before the park radius (%.0f m vs %.0f m)" %
				[environment.fog_depth_end, MobLod.DORMANT_DISTANCE])
		check(environment.fog_depth_begin >= 50.0,
			"and the near field stays clear (%.0f m)" % environment.fog_depth_begin)
	check(is_equal_approx(frontier.camera.far, 175.0),
		"the camera stops with the fog (%.0f m)" % frontier.camera.far)
	var culler := frontier.get_node_or_null("Frontier/MobCuller")
	check(culler != null, "the frontier owns the sweep node")
	# At the town spawn every authored body is inside the fog wall, so nothing
	# may be parked near the ranger: that is the guard on the sweep itself.
	await create_timer(1.2).timeout
	var wrongly_parked := 0
	var near_mob = null
	for enemy in frontier.enemies:
		if not is_instance_valid(enemy) or not bool(enemy.get("alive")):
			continue
		var nearest: float = enemy._nearest_ranger()
		if nearest >= MobLod.WAKE_DISTANCE - NEAR_SLACK:
			continue
		if bool(enemy.get("dormant")):
			wrongly_parked += 1
		elif bool(enemy.is_on_floor()) and not enemy._senses.aggressive():
			near_mob = enemy
	check(wrongly_parked == 0, "no body inside the wake radius is parked (%d)" % wrongly_parked)
	check(near_mob != null, "the town spawn keeps a body beside the ranger")
	if near_mob == null:
		frontier.queue_free()
		await process_frame
		return
	# Carry one body to the far corner. A ranger 200 m away has no reason to
	# simulate it, and it must stop dead - not tick at 2.5 Hz.
	var spot = _ground_point(Vector3(125.0, 0.0, -125.0))
	check(spot != null, "the far corner has ground")
	if spot != null:
		var traveller = near_mob
		traveller.global_position = (spot as Vector3) + Vector3(0.0, 0.3, 0.0)
		check(await _await_floor(traveller, 4.0), "the body lands on the far ground")
		check(traveller._nearest_ranger() >= MobLod.DORMANT_DISTANCE,
			"and stands past the park radius (%.0f m)" % traveller._nearest_ranger())
		await create_timer(1.0).timeout
		check(bool(traveller.get("dormant")), "a body past the fog wall is parked")
		check(not traveller.is_physics_processing(), "a parked body runs no physics process")
		check(not traveller.visible, "a parked body draws nothing")
		var frozen: Vector3 = traveller.global_position
		var grants_before: int = traveller._lod.grants
		await create_timer(1.0).timeout
		check(int(traveller._lod.grants) == grants_before,
			"a parked body is granted no ticks (%d then %d)" %
				[grants_before, int(traveller._lod.grants)])
		check(traveller.global_position.distance_to(frozen) < 0.001,
			"and it does not move while parked")
		# Walk the ranger back in: the same body comes back and runs.
		traveller.global_position = frontier.player.global_position + Vector3(12.0, 0.6, 0.0)
		await create_timer(1.0).timeout
		check(not bool(traveller.get("dormant")), "a body inside the wake radius comes back")
		check(traveller.is_physics_processing(), "and runs its physics again")
		check(traveller.visible, "and draws again")
		var grants_after: int = traveller._lod.grants
		await create_timer(0.6).timeout
		check(int(traveller._lod.grants) > grants_after,
			"and is granted ticks again (%d then %d)" %
				[grants_after, int(traveller._lod.grants)])
	frontier.queue_free()
	await process_frame


## Ground hit for a ray straight down, so a body can be stood somewhere real.
func _ground_point(at: Vector3):
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, 120.0, at.z), Vector3(at.x, -60.0, at.z), 1)
	var hit := root.world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.get("position")


## Waits (up to `seconds`) for a body to report a floor: a coarse tick still
## lands it, so this is a wait rather than an assumption.
func _await_floor(body: Node, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if body.is_on_floor():
			return true
		await physics_frame
	return body.is_on_floor()
