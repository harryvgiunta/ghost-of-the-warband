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
	var title = root.get_child(root.get_child_count() - 1)
	if title != null and title.has_method("_toggle_lobby"):
		title.call("_toggle_lobby")
		for _i in 8:
			await process_frame
		var lobby := root.get_texture().get_image()
		lobby.save_png("res://media/concept/game_title_lobby.png")
		print("TITLE_LOBBY_OK ", lobby.get_size())
	quit()
