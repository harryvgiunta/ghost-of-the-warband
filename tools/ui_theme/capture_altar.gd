extends SceneTree
## Opens the sacrificial altar over the running world and writes one frame.
const OUT := "res://media/concept/game_altar.png"
const Altar = preload("res://scripts/warband/altar_menu.gd")

func _initialize() -> void:
	var flow = root.get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.world_start = "camp"
		flow.active = true
	var scene: Node = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(scene)
	_run()

func _run() -> void:
	for _i in 60:
		await process_frame
	var card = root.find_child("TutorialCard", true, false)
	if card != null and card.has_method("close"):
		card.close()
	var warband = root.get_node_or_null("/root/Warband")
	var altar := Altar.new()
	altar.name = "CaptureAltar"
	root.add_child(altar)
	altar.configure(warband)
	altar.open()
	for _i in 10:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("ALTAR_CAPTURE_OK ", image.get_size())
	quit()
