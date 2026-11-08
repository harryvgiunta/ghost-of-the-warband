extends SceneTree
## Boots the real warband world, stands the party on the first arena island and
## writes two frames: the Town Hub with its three new fixtures, and the island
## under a live wave. Art-direction verification only - this script changes
## nothing and the files it writes are gitignored.
##
##   .runtime/godot/Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tools/ui_theme/capture_rogue.gd --resolution 1440x900

const TOWN_OUT := "res://.runtime/capture_rogue_town.png"
const ISLAND_OUT := "res://.runtime/capture_rogue_island.png"


func _initialize() -> void:
	var flow = root.get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.world_start = "town"
		flow.active = false
	var scene: Node = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for _frame in 90:
		await process_frame
	_capture(TOWN_OUT)
	var town = scene.get("town")
	if town != null:
		town._open_forge("rack")
		for _frame in 20:
			await process_frame
		_capture("res://.runtime/capture_rogue_rack.png")
		town.forge_panel.close_panel()
	var run = scene.get("roguelite")
	if run != null:
		run.start_run()
		for _frame in 45:
			await process_frame
		run.tick(2.5)
		run.tick(2.5)
		for _frame in 90:
			await process_frame
		_capture(ISLAND_OUT)
		# The other two islands, built and stood on: the cave's dripstone and the
		# pit's colonnade are the two the first island never shows.
		var biomes := ["caves", "arena"]
		for index in biomes.size():
			run.stage_index = index + 1
			run.biome_id = str(biomes[index])
			run._build_stage()
			var body = scene.get("bodies")[0] if scene.get("bodies").size() > 0 else null
			if body != null:
				body.global_position = run.stage.entry_posts(1)[0]
			for _frame in 60:
				await process_frame
			_capture("res://.runtime/capture_rogue_%s.png" % str(biomes[index]))
		# The island's furniture and the draft window: clear the last island,
		# walk the body to the pedestal and open the board it offers.
		run._clear_stage()
		for _frame in 30:
			await process_frame
		var pedestal = null
		for prop in run._props:
			if is_instance_valid(prop) and str(prop.get_meta("roguelite_prop", "")) == "pedestal":
				pedestal = prop
				break
		if pedestal != null and scene.get("bodies").size() > 0:
			var player_body = scene.get("bodies")[0]
			player_body.global_position = pedestal.global_position + Vector3(0.0, 0.0, 2.6)
			run._open_draft(int(pedestal.get_meta("serial")), player_body)
			for _frame in 20:
				await process_frame
			_capture("res://.runtime/capture_rogue_draft.png")
	quit()


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		print("ROGUE_CAPTURE_MISS ", path)
		return
	image.save_png(path)
	print("ROGUE_CAPTURE_OK ", path, " ", image.get_size())
