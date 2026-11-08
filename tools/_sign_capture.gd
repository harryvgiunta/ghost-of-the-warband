extends SceneTree
## Art-direction capture for the world's signs: the real town under the world's own
## sun and sky, framed on each sign, plus the cave waymark on its own.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/_sign_capture.gd --resolution 1280x720
##
## Throwaway: writes .runtime/signs/*.png for review, then quits.

const OUT := "res://.runtime/signs/"

var town: Node3D

func _initialize() -> void:
	root.get_node("PlayerState").reset(false)
	root.get_node("Warband").reset_state()
	_build_light()
	town = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(town)
	_run()

func _build_light() -> void:
	var style = load("res://scripts/world/world_style.gd")
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load("res://assets/world/textures/sky_frontier.png")
	sky.sky_material = panorama
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)

func _run() -> void:
	for _i in 45:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _shot("gate_board", Vector3(2.7, 2.9, 12.0), Vector3(2.7, 3.7, 22.0))
	await _shot("gate_board_close", Vector3(2.7, 3.4, 19.6), Vector3(2.7, 3.7, 22.0))
	await _shot("fingerpost", Vector3(4.2, 1.7, 7.6), Vector3(7.5, 1.9, 10.5))
	await _shot("square_board", Vector3(2.0, 2.2, 4.2), Vector3(2.0, 2.4, 9.0))
	await _shot("fingerpost_back", Vector3(9.8, 1.7, 13.0), Vector3(7.5, 1.9, 10.5))
	await _shot("arena_plate", Vector3(13.5, 3.2, 0.5), Vector3(17.0, 3.9, -4.0))
	await _shot("altar_stele", Vector3(4.6, 1.5, 4.0), Vector3(8.7, 1.42, 4.0))
	await _shot("altar_stele_close", Vector3(7.0, 1.45, 4.1), Vector3(8.76, 1.42, 4.0))
	await _shot("square_wide", Vector3(-6.0, 5.0, 16.0), Vector3(4.0, 1.6, 4.0))
	await _mouth()
	await _cave_tablet()
	print("SIGN_CAPTURE_OK")
	quit()

func _shot(label: String, eye: Vector3, at: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = 62.0
	root.add_child(camera)
	camera.global_position = eye
	camera.look_at(at, Vector3.UP)
	camera.current = true
	for _i in 6:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT + label + ".png")
	camera.queue_free()

## The Weeping Hollow's mouth, built by the delve area itself.
func _mouth() -> void:
	town.visible = false
	var area = load("res://scripts/warband/delve_area.gd").new()
	root.add_child(area)
	area.host = null
	area._build_mouth()
	var mouth: Node3D = area.mouth
	var forward := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, mouth.rotation.y)
	var eye := mouth.position + forward * 5.6 + Vector3(0.0, 2.4, 0.0)
	await _shot("delve_mouth", eye, mouth.position + Vector3(0.0, 2.2, 0.0))
	var close := mouth.position + forward * 3.2 + Vector3(0.0, 2.2, 0.0)
	await _shot("delve_mouth_close", close, mouth.position + Vector3(0.0, 2.2, 0.0))
	area.queue_free()
	town.visible = true


## The cave waymark the delve sets at the foot of every rope.
func _cave_tablet() -> void:
	town.visible = false
	var cave := Node3D.new()
	root.add_child(cave)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	floor_mesh.mesh = plane
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.20, 0.19, 0.18)
	rock.roughness = 0.95
	floor_mesh.material_override = rock
	cave.add_child(floor_mesh)
	var sign_kit = load("res://scripts/world/sign_kit.gd")
	sign_kit.tablet(cave, "way_up", Vector3.ZERO, 0.0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.72, 0.80, 1.0)
	lamp.light_energy = 3.0
	lamp.omni_range = 8.0
	lamp.position = Vector3(0.6, 3.2, 2.4)
	cave.add_child(lamp)
	await _shot("cave_way_up", Vector3(0.0, 1.5, 2.9), Vector3(0.0, 0.45, 0.0))
	await _shot("cave_way_up_close", Vector3(0.0, 0.62, 1.25), Vector3(0.0, 0.45, 0.0))
