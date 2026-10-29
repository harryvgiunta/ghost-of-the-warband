extends SceneTree
## The warband as a line-up: eight mercenaries in one row, each with the look
## `WarbandLooks` derives from their id.
##
##     godot --path . --script res://playtest/warband_lookbook.gd
##
## Writes `res://.runtime/probe/warband_lineup.png` (front), `_back.png` and
## `_faces.png` (heads only). This is the surface the look is judged on: a band
## that reads as eight different men from the distance a player actually sees
## them, with feet on the ground at every height.

const Archer = preload("res://scripts/archer.gd")
const Looks = preload("res://scripts/warband/warband_looks.gd")
const NAKED_SET := 5
const SPACING := 0.95

var _rigs: Array = []
var _camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.72, 0.55, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.35, -2.5, 0.0)
	fill.light_energy = 0.55
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.33, 0.29)
	ground.material_override = mat
	world.add_child(ground)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 34.0
	world.add_child(_camera)

	var count := 8
	for index in count:
		var merc_id := index + 1
		var rig := Archer.new()
		rig.appearance = Looks.profile_for(merc_id)
		world.add_child(rig)
		rig.apply_loadout({
			"main": "", "off": "", "weapon": "dagger", "bow": 0, "sword": 0,
			"staff": -1, "dagger": 1,
			"armor": {"head": NAKED_SET, "chest": NAKED_SET, "hands": NAKED_SET,
				"legs": NAKED_SET, "feet": NAKED_SET},
			"shield": false, "off_weapon": {}, "focus": {},
		})
		rig.position = Vector3((index - (count - 1) * 0.5) * SPACING, 0.0, 0.0)
		rig.rotation.y = 0.0
		_rigs.append(rig)
		for frame in 12:
			await process_frame
		# A look is judged on what the body shows: the quiver and the held props
		# would sit on top of the shirt and hide a seam.
		for node in [rig.active_dagger, rig.active_sword, rig.active_staff,
				rig.active_bow, rig.active_shield, rig.active_focus, rig._quiver]:
			if node != null and is_instance_valid(node):
				node.visible = false
		print("LOOK %d %s height=%.2f face=%s hair=%s beard=%s skin=%s shirt=%s shorts=%s hair_tone=%s eye=%d"
			% [merc_id, Looks.data().get("asset", "looks"), float(rig.appearance["height"]),
				str(rig.appearance["face_name"]), str(rig.appearance["hair_name"]),
				str(rig.appearance["beard_name"]), str(rig.appearance["skin"]),
				str(rig.appearance["shirt"]), str(rig.appearance["shorts"]),
				str(rig.appearance["hair_tone"]), int(rig.appearance["eye"])])

	# The rig's own model is yawed 180 degrees, so the band faces -Z: the front
	# shot comes from the far side of the row.
	_camera.position = Vector3(0.0, 1.18, -6.6)
	_camera.look_at(Vector3(0.0, 1.00, 0.0))
	await _shot("warband_lineup.png")
	_camera.position = Vector3(0.0, 1.24, 6.6)
	_camera.look_at(Vector3(0.0, 1.00, 0.0))
	await _shot("warband_lineup_back.png")
	# Portraits: four heads at a time, big enough to judge a face, a cut and a
	# beard on, taken from just under the eye so the stance's head pitch does not
	# hide the forehead.
	var front := DirectionalLight3D.new()
	front.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
	front.light_energy = 1.2
	front.light_color = Color(0.96, 0.93, 0.87)
	world.add_child(front)
	for group in 2:
		for index in _rigs.size():
			var rig: Node3D = _rigs[index]
			var height := float(rig.appearance["height"])
			var in_group := index / 4 == group
			rig.visible = in_group
			rig.position.x = (index % 4 - 1.5) * 0.235
			rig.position.z = 0.0
			rig.position.y = 1.787 * (1.0 - height)
		_camera.fov = 30.0
		_camera.position = Vector3(0.0, 1.670, -1.05)
		_camera.look_at(Vector3(0.0, 1.672, 0.0))
		await _shot("warband_heads_%s.png" % ("a" if group == 0 else "b"))

	print("WARBAND_LOOKBOOK ok")
	quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.runtime/probe/%s" % name)
