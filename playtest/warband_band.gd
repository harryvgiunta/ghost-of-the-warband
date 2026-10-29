extends SceneTree
## The warband in the real arena: the same eight bodies the sandbox fields, with
## the look each man was given, lit by the scene rather than by a probe rig.
##
##     godot --path . --script res://playtest/warband_band.gd
##
## Writes `res://.runtime/probe/warband_band.png` (the two soul bodies waiting at
## the posts), `warband_band_squad.png` (the far brawl's three, close) and
## `warband_band_field.png` (the wide arena). The brains and the fights are off
## so nothing moves between the frames.

const SQUAD_A := Vector3(-24.0, 0.0, -10.0)

var game
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var warband = root.get_node("Warband")
	warband.save_path = "user://warband_band_warband.json"
	warband.reset_state()
	warband.reset_state()
	for index in 8:
		warband.add_mercenary("Mercenary %d" % (index + 1))
	game = load("res://admin_arena.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	game.set_sparring(false)
	game.set_choreography(false)
	await create_timer(0.4).timeout
	# The possession camera drives the scene camera every frame; the picture needs
	# its own eye, so the rig is parked and a fresh camera is made current.
	if game.controller != null and game.controller.camera_rig != null:
		game.controller.camera_rig.set_process(false)
		game.controller.camera_rig.set_physics_process(false)
	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	game.add_child(camera)
	camera.current = true
	for index in game.bodies.size():
		var actor = game.bodies[index]
		if not is_instance_valid(actor):
			continue
		print("BODY %d %s at %s height=%.2f face=%s hair=%s beard=%s skin=%s shirt=%s shorts=%s"
			% [index, actor.display_name, str(actor.global_position),
				float(actor.appearance.get("height", 1.0)),
				str(actor.appearance.get("face_name", "")),
				str(actor.appearance.get("hair_name", "-")),
				str(actor.appearance.get("beard_name", "-")),
				str(actor.appearance.get("skin", "")), str(actor.appearance.get("shirt", "")),
				str(actor.appearance.get("shorts", ""))])
	# The two bodies waiting for a soul.
	var waiting: Vector3 = game.bodies[6].global_position.lerp(game.bodies[7].global_position, 0.5)
	camera.position = waiting + Vector3(0.0, 1.75, 3.4)
	camera.look_at(waiting + Vector3(0.0, 1.05, 0.0))
	camera.fov = 40.0
	await _shot("warband_band.png")
	# The first brawl, close enough to read a face, a sleeve and a shin.
	var ring: Vector3 = Vector3.ZERO
	for index in 3:
		ring += game.bodies[index].global_position
	ring /= 3.0
	camera.position = ring + Vector3(2.2, 1.70, 3.0)
	camera.look_at(ring + Vector3(0.0, 1.02, 0.0))
	camera.fov = 40.0
	await _shot("warband_band_squad.png")
	# The far ring, where the fourth mercenary stands: the one with a whole head
	# of hair rather than a cut.
	var afro: Vector3 = game.bodies[3].global_position
	camera.position = afro + Vector3(1.5, 1.72, 2.4)
	camera.look_at(afro + Vector3(0.0, 1.10, 0.0))
	camera.fov = 40.0
	await _shot("warband_band_far.png")
	# The whole field, the way the sandbox is first seen.
	camera.position = Vector3(0.0, 14.0, 30.0)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	camera.fov = 59.0
	await _shot("warband_band_field.png")
	print("WARBAND_BAND ok")
	quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.runtime/probe/%s" % name)
