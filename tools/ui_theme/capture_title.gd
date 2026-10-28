extends SceneTree
## Runs the title scene and writes one frame.
const OUT := "res://media/concept/game_title.png"

func _initialize() -> void:
	var scene: Node = load("res://title.tscn").instantiate()
	root.add_child(scene)
	_run()

func _run() -> void:
	for _i in 30:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("TITLE_CAPTURE_OK ", image.get_size())
	quit()
