extends SceneTree
## Boots the real warband world, closes every opening card, and writes the battle
## readout - so HUD work is judged in the game it ships in, over a real forest,
## with a real body in it.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_hud.gd --resolution 1440x900
##
## Writes media/concept/game_hud.png. Art-direction verification only.

const OUT := "res://media/concept/game_hud.png"

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/warband_world.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	_run(scene)

func _run(scene: Node) -> void:
	for _i in 40:
		await process_frame
	_dismiss(root)
	for _i in 80:
		await process_frame
	_dismiss(root)
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("HUD_CAPTURE_OK ", image.get_size())
	quit()

## Every one of the world's opening cards is a CanvasLayer of its own: hide them
## all so the frame is the readout and nothing else.
func _dismiss(node: Node) -> void:
	for child in node.get_children():
		var opened := false
		if child.has_method("is_open"):
			opened = bool(child.call("is_open"))
			if opened and child.has_method("close"):
				child.call("close")
		elif child.has_method("showing"):
			opened = bool(child.call("showing"))
			if opened and child.has_method("dismiss"):
				child.call("dismiss")
		_dismiss(child)
