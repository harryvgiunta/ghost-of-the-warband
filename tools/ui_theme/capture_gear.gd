extends SceneTree
## Opens the gear page over the running world and writes one frame.
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_gear.gd --resolution 1440x900

const OUT := "res://media/concept/game_gear.png"
const Doll = preload("res://scripts/warband/warband_paperdoll.gd")

var _doll = null

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
	var first := -1
	if warband != null:
		var ids: Array = warband.roster.ids()
		if not ids.is_empty():
			first = int(ids[0])
	_doll = Doll.new()
	_doll.name = "CaptureGear"
	root.add_child(_doll)
	_doll.configure(null)
	_doll.open(first)
	for _i in 30:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("GEAR_CAPTURE_OK ", image.get_size())
	quit()
