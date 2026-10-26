extends SceneTree
## Corpse regression: every mob kind keeps its corpse where it fell for the
## shared five-minute default instead of vanishing after a few seconds, keeps
## its authored death pose, stops colliding, and still dissolves and frees
## through the one shared hold path when its clock runs out.

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CORPSE_FAIL  ", message)


func pause(seconds: float) -> void:
	await create_timer(seconds).timeout


func run() -> void:
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(_on_watchdog)
	var CorpseHold = load("res://scripts/corpse_hold.gd")
	var CorpsePhysics = load("res://scripts/corpse_physics.gd")
	var Enemy = load("res://scripts/enemy.gd")
	var Mob = load("res://scripts/devil_mob.gd")
	var DelveDevil = load("res://scripts/delve_devil.gd")

	check(is_equal_approx(CorpseHold.SECONDS, 300.0),
		"A corpse lies in the world for five minutes by default")
	check(CorpseHold.DISSOLVE_SECONDS > 0.0 and CorpseHold.DISSOLVE_SECONDS < 2.0,
		"The corpse frees itself through a short dissolve, never a pop")

	var fixture := Node3D.new()
	fixture.name = "CorpseFixture"
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60.0, 1.0, 60.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	fixture.add_child(floor_body)
	await physics_frame

	var wolf = Enemy.new()
	wolf.kind = 0
	var sentinel = Enemy.new()
	sentinel.kind = 1
	var cinder = Enemy.new()
	cinder.kind = 2
	cinder.devil_weapon = "claw"
	var pack = Mob.new()
	pack.mob_id = "hell_goat"
	var delve = DelveDevil.new()
	delve.configure(1, "claw", 1)
	var delve_species = DelveDevil.new()
	delve_species.configure(2, "claw", 1, "hell_goat")
	var corpses := [
		["Briar wolf", wolf, Vector3(-6.0, 0.12, 0.0)],
		["Ruin sentinel", sentinel, Vector3(-3.0, 0.12, 0.0)],
		["Cinder devil", cinder, Vector3(0.0, 0.12, 0.0)],
		["Hellish goat man", pack, Vector3(3.0, 0.12, 0.0)],
		["Delve devil", delve, Vector3(6.0, 0.12, 0.0)],
		["Delve goat", delve_species, Vector3(9.0, 0.12, 0.0)],
	]
	for entry in corpses:
		var body = entry[1]
		body.position = entry[2]
		fixture.add_child(body)
	await physics_frame
	await physics_frame

	for entry in corpses:
		var label := str(entry[0])
		var body = entry[1]
		check(body.alive, label + " starts alive")
		body.take_damage(99999.0, 0, false)
		await physics_frame
		check(not body.alive, label + " dies")
		check(body.collision_layer == 0, label + " corpse stops colliding")
		check(body.collision_mask == 1, label + " corpse still catches the world floor")
		check((body as Node3D).scale.is_equal_approx(Vector3.ONE),
			label + " corpse root keeps its scale while it is held")
	# Rigged mobs hand their skeleton to the shared ragdoll; the procedural
	# cinder and sentinel keep their authored collapse and only fall by root.
	check(CorpsePhysics.is_limp(wolf._wolf), "The wolf corpse is a physical ragdoll")
	check(CorpsePhysics.is_limp(pack._visual), "An imported devil corpse is a physical ragdoll")
	check(CorpsePhysics.is_limp(delve_species._visual), "A delve species corpse is a physical ragdoll")
	check(not CorpsePhysics.is_limp(delve._visual), "A procedural corpse keeps its authored collapse")
	check(not CorpsePhysics.is_limp(sentinel._body), "The primitive sentinel has no skeleton to ragdoll")
	var wolf_sim := wolf._wolf.find_child("CorpseRagdoll", true, false) as PhysicalBoneSimulator3D
	var wolf_bones := wolf_sim.get_child_count() if wolf_sim != null else 0
	check(wolf_bones >= 10, "The wolf ragdoll builds its driven bone chain")
	var goat_skeleton := pack._visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var eye_bone := goat_skeleton.find_bone("neutral_bone")
	var goat_head := goat_skeleton.find_bone("Head")
	check(eye_bone >= 0 and goat_skeleton.get_bone_parent(eye_bone) == goat_head,
		"The goat's stray eye bone is adopted by the head before simulation")
	if wolf_sim != null:
		var first_bone := wolf_sim.get_child(0) as PhysicalBone3D
		check(first_bone.collision_layer == 0 and first_bone.collision_mask == 1,
			"Corpse bones stop blocking fighters while still colliding with the world")

	# The authored poses are held, not reset by a fake delete.
	check(wolf._wolf.is_dead(), "The wolf holds its authored death pose")
	check(cinder._devil.is_dead(), "The cinder devil holds its authored death pose")
	check(pack._visual.is_dead(), "An imported devil holds its authored death pose")
	check(delve._visual.is_dead(), "A delve devil holds its authored death pose")
	await pause(0.6)
	check(sentinel._body.rotation.z > 0.1, "The sentinel collapses onto its side")

	# Corpses obey gravity even when killed in the air: the primitive root and
	# the rigged limbs both reach the floor instead of hanging at the death spot.
	var falling_guard = Enemy.new()
	falling_guard.kind = 1
	falling_guard.position = Vector3(-9.0, 5.0, 0.0)
	fixture.add_child(falling_guard)
	await physics_frame
	await physics_frame
	falling_guard.take_damage(99999.0, 0, false)
	await pause(1.6)
	check(falling_guard.global_position.y < 0.6,
		"A sentinel killed in the air falls to the ground")
	check(sentinel.global_position.y < 0.6,
		"A grounded corpse settles on the floor")

	# The old four-second corpse is the exact behavior this replaces: every
	# body must still be lying there well past it.
	await pause(5.2)
	for entry in corpses:
		var label := str(entry[0])
		var body = entry[1]
		check(is_instance_valid(body) and not body.is_queued_for_deletion(),
			label + " corpse is still lying there after five seconds")
		check(is_instance_valid(body) and body.is_inside_tree(),
			label + " corpse stays in the scene instead of being unparented")
		check(is_instance_valid(body) and body.collision_layer == 0,
			label + " corpse never re-enables collision")
	# The ragdoll retires after settling and leaves its baked pose in place.
	check(not CorpsePhysics.is_limp(wolf._wolf), "The wolf ragdoll retires after settling")
	check(not CorpsePhysics.is_limp(pack._visual), "The imported devil ragdoll retires after settling")
	var baked_head := _bone_world(wolf._wolf, "head")
	var baked_pelvis := _bone_world(wolf._wolf, "pelvis")
	check(baked_head.y < 0.8 and baked_pelvis.y < 0.8,
		"The settled wolf corpse lies on the ground")
	var wolf_spread := Vector2(baked_head.x - baked_pelvis.x,
		baked_head.z - baked_pelvis.z).length()
	check(wolf_spread > 0.3,
		"The wolf torso stays extended instead of folding into a pile")
	var goat_head_world := _bone_world(pack._visual, "Head")
	var goat_pelvis_world := _bone_world(pack._visual, "pelvis")
	check(goat_head_world.y < 0.6 and goat_pelvis_world.y < 0.6,
		"The goat corpse lies on the ground")
	var goat_spread := Vector2(goat_head_world.x - goat_pelvis_world.x,
		goat_head_world.z - goat_pelvis_world.z).length()
	check(goat_spread > 0.35,
		"The goat torso topples as one body instead of melting in place")
	await pause(0.4)
	var held_head := _bone_world(wolf._wolf, "head")
	check(held_head.distance_to(baked_head) < 0.05, "The settled limp pose is held for the corpse lifetime")

	# The shared hold dissolves and frees at the end of its clock.
	var stand_in := Node3D.new()
	var shrink := Node3D.new()
	stand_in.name = "CorpseStandIn"
	stand_in.add_child(shrink)
	fixture.add_child(stand_in)
	CorpseHold.hold(stand_in, shrink, 0.15)
	await pause(1.2)
	check(not is_instance_valid(stand_in),
		"The shared corpse hold dissolves and frees the body when the clock runs out")
	check(is_instance_valid(fixture), "The fixture survives its own corpse tear-down")

	fixture.queue_free()
	await process_frame
	print("CORPSE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _bone_world(visual: Node3D, bone_name: String) -> Vector3:
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return Vector3.ZERO
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return Vector3.ZERO
	return skeleton.get_global_transform() * skeleton.get_bone_global_pose(bone).origin


func _on_watchdog() -> void:
	print("CORPSE_WATCHDOG failures=", failures, " checks=", checks)
	quit(2)
