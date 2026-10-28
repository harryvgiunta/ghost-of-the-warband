extends SceneTree
## The concept boards are composed over a real still of the warband camp, not a
## painted backdrop: contrast and legibility are judged in the game's own light.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_backdrop.gd --resolution 1440x900
##
## Writes media/concept/backdrop_camp.png and exits. Every UI layer and floating
## world label is hidden and the camera is parked on the cage yard, so the still
## contains no chrome. It is art-direction input only; nothing in the game loads
## the result.

const OUT := "res://media/concept/backdrop_camp.png"

func _initialize() -> void:
	var flow = root.get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.world_start = "camp"
		flow.active = true
	var packed: PackedScene = load("res://scenes/warband_world.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	_run(scene)

func _run(scene: Node) -> void:
	for _i in 40:
		await process_frame
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in root.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
	var cameras := root.find_children("*", "Camera3D", true, false)
	if not cameras.is_empty():
		var cam: Camera3D = cameras[0]
		cam.set_script(null)
		cam.current = true
		cam.fov = 62.0
		cam.global_position = Vector3(2.6, 2.35, 17.5)
		cam.look_at(Vector3(0.0, 1.25, -6.0), Vector3.UP)
	for _i in 10:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("BACKDROP_OK ", image.get_size())
	quit()
