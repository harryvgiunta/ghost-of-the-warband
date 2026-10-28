extends SceneTree
## Captures the frontier equipment menu's live ranger from its own SubViewport,
## so the gear concept board shows the real character preview rather than a
## drawing of one.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_preview.gd --resolution 1440x900
##
## Writes media/concept/preview_ranger.png and exits. Art-direction input only.

const OUT := "res://media/concept/preview_ranger.png"

func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	_run(scene)

func _run(scene: Node) -> void:
	for _i in 40:
		await process_frame
	var ui = scene.get("world_ui")
	if ui == null:
		print("NO_WORLD_UI")
		quit()
		return
	ui.open_equipment()
	for _i in 12:
		await process_frame
	var viewport := root.find_child("CharacterViewport", true, false) as SubViewport
	if viewport == null:
		print("NO_PREVIEW")
		quit()
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 10:
		await process_frame
	var image := viewport.get_texture().get_image()
	image.save_png(OUT)
	print("PREVIEW_OK ", image.get_size())
	quit()
