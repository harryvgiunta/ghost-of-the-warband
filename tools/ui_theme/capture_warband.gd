extends SceneTree
## Opens the warband ledger over the running world and writes one frame.
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_warband.gd --resolution 1440x900

const OUT := "res://media/concept/game_warband.png"
const Screen = preload("res://scripts/warband/warband_screen.gd")

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
	var screen := Screen.new()
	screen.name = "CaptureWarband"
	root.add_child(screen)
	screen.configure(null)
	screen.open()
	for _i in 10:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("WARBAND_CAPTURE_OK ", image.get_size())
	quit()
