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
	var cinder = Enemy.new()
	cinder.kind = 2
	cinder.devil_weapon = "claw"
	var pack = Mob.new()
	pack.mob_id = "hell_goat"
	var delve = DelveDevil.new()
	delve.configure(1, "claw", 1)
	var corpses := [
		["Briar wolf", wolf, Vector3(-6.0, 0.12, 0.0)],
		["Cinder devil", cinder, Vector3(0.0, 0.12, 0.0)],
		["Hellish goat man", pack, Vector3(3.0, 0.12, 0.0)],
		["Delve devil", delve, Vector3(6.0, 0.12, 0.0)],
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
		check((body as Node3D).scale.is_equal_approx(Vector3.ONE),
			label + " corpse root keeps its scale while it is held")

	# The authored poses are held, not reset by a fake delete.
	check(wolf._wolf.is_dead(), "The wolf holds its authored death pose")
	check(cinder._devil.is_dead(), "The cinder devil holds its authored death pose")
	check(pack._visual.is_dead(), "An imported devil holds its authored death pose")
	check(delve._visual.is_dead(), "A delve devil holds its authored death pose")

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


func _on_watchdog() -> void:
	print("CORPSE_WATCHDOG failures=", failures, " checks=", checks)
	quit(2)
