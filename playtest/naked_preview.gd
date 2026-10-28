extends SceneTree
## The naked armour set on the live rig, from three angles.
##
##     godot --path . --script res://playtest/naked_preview.gd
##
## Writes `res://.runtime/probe/naked_front.png`, `naked_three_quarter.png` and
## `naked_back_left.png`. The rig, the camera and the ground are built here; only
## the asset is under test, so a piece that floats, twists, leaves a hole or is
## painted with the wrong atlas is visible in a two second run.

const Archer = preload("res://scripts/archer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.6, 0.0)
	sun.light_energy = 1.5
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.4, 0.0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.35, 0.30)
	ground.material_override = mat
	world.add_child(ground)
	var rig := Archer.new()
	world.add_child(rig)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 40.0
	world.add_child(camera)
	rig.apply_loadout({
		"main": "dagger_ironwood", "off": "", "weapon": "dagger", "bow": 0,
		"sword": 0, "staff": -1, "dagger": 1,
		"armor": {"head": 5, "chest": 5, "hands": 5, "legs": 5, "feet": 5},
		"shield": false, "off_weapon": {}, "focus": {},
	})
	for index in 20:
		await process_frame
	# The garment is what is under test: the quiver, the belt of weapons and the
	# held blade would sit on top of it and hide a seam or fake a hole.
	if rig._quiver != null:
		rig._quiver.visible = false
	for node in [rig.active_dagger, rig.active_sword, rig.active_staff, rig.active_bow,
			rig.active_shield, rig.active_focus]:
		if node != null and is_instance_valid(node):
			node.visible = false
	camera.position = Vector3(0.0, 1.05, 3.1)
	camera.look_at(Vector3(0.0, 0.95, 0.0))
	await _shot("naked_front.png")
	camera.position = Vector3(2.3, 1.25, 2.3)
	camera.look_at(Vector3(0.0, 0.95, 0.0))
	await _shot("naked_three_quarter.png")
	camera.position = Vector3(-2.6, 1.05, 2.0)
	camera.look_at(Vector3(0.0, 0.95, 0.0))
	await _shot("naked_back_left.png")
	print("NAKED_PREVIEW ok")
	quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.runtime/probe/%s" % name)
