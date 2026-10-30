extends SceneTree
## Runs the title scene and writes the four doors, then each co-op form over them.
const OUT := "res://media/concept/game_title.png"
const HOST_OUT := "res://media/concept/game_title_host.png"
const JOIN_OUT := "res://media/concept/game_title_join.png"

func _initialize() -> void:
	var scene: Node = load("res://title.tscn").instantiate()
	root.add_child(scene)
	_run(scene)

func _run(title: Node) -> void:
	await _capture(OUT, "TITLE_CAPTURE_OK", 30)
	title.call("_open_host")
	await _capture(HOST_OUT, "TITLE_HOST_OK", 8)
	title.call("_close_host")
	title.call("_open_join")
	await _capture(JOIN_OUT, "TITLE_JOIN_OK", 8)
	quit()

func _capture(path: String, marker: String, frames: int) -> void:
	for _i in frames:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(path)
	print(marker, " ", image.get_size())
