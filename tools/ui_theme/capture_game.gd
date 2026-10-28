extends SceneTree
## Boots the real warband world, lets the tutorial card open, and writes the
## frame - so UI work is judged in the game it ships in, not in a mock.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_game.gd --resolution 1440x900
##
## Writes media/concept/game_capture.png. Art-direction verification only.

const OUT := "res://media/concept/game_capture.png"

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
	for _i in 90:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("GAME_CAPTURE_OK ", image.get_size())
	quit()
