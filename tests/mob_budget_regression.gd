extends SceneTree
## The wilderness tick budget: bands, carried time, and the one rule that makes
## it safe - a body on a long budget covers exactly the same ground as one
## ticking every frame.

const MobLod = preload("res://scripts/mob_lod.gd")


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
	await _check_flat_ground()
	await _check_slope()
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
		if deep.slice(200.0, 1.0 / 60.0) > 0.0:
			deep_grants += 1
	check(deep_grants == 5, "a body at 200 m ticks every twenty-fourth frame (granted %d)" % deep_grants)
	check(deep.grants == deep_grants, "the budget counts its grants")


## A skipped frame is not lost time: the granted deltas still add up to a second.
func _check_carried_time() -> void:
	for entry in [[5.0, false], [5.0, true], [40.0, false], [70.0, false], [200.0, false]]:
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
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(".:position"))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	player.add_animation("idle", animation)
	holder.add_child(player)
	player.play("idle")
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
