extends SceneTree
## Opens the sacrificial altar over the running world and writes one frame of
## the ANOINT page: the rack of individual copies on the left with their own
## welded annointments, and the bench on the right - the picked copy in the
## square, its reagent and the one brass ANOINT under them.
const OUT := "res://media/concept/game_altar.png"
const Altar = preload("res://scripts/warband/altar_menu.gd")
const CAPTURE_SAVE := "user://altar_capture_state.json"
## The copies of the greatsword that come out of the capture already worked, so
## the rack reads as ten swords with ten different sets rather than ten blanks.
const WORKED := [0, 1, 2, 4, 5, 7, 9]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var warband = root.get_node_or_null("Warband")
	if warband != null:
		# The capture runs on its own warband: a loadout to lay on the bench,
		# never the player's save.
		warband.save_path = CAPTURE_SAVE
		warband.reset_state()
		warband.add_mercenary("Wick", {"main": "bow_short"})
		for entry in [["sword_arming", 1], ["sword_great", 10], ["shield_buckler", 1],
				["dagger_ironwood", 1], ["ichor_vial", 80]]:
			warband.stash.add(str(entry[0]), int(entry[1]))
		# Weld a different set on each copy the picture shows, through the real
		# rite with a forced die so the frame is the same one every capture.
		for ordinal in WORKED:
			for step in 2:
				var rng := RandomNumberGenerator.new()
				rng.seed = 101 + int(ordinal) * 17 + step * 7919
				warband.anoint("sword_great", int(ordinal), rng)
	var flow = root.get_node_or_null("GameFlow")
	if flow != null:
		flow.world_start = "camp"
		flow.active = true
	var scene: Node = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(scene)
	for _i in 60:
		await process_frame
	var card = root.find_child("TutorialCard", true, false)
	if card != null and card.has_method("close"):
		card.close()
	var altar := Altar.new()
	altar.name = "CaptureAltar"
	root.add_child(altar)
	altar.configure(warband)
	altar.open()
	altar.show_page(Altar.PAGE_ANOINT)
	altar.select_anoint_item("sword_great", 4)
	for _i in 10:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("ALTAR_CAPTURE_OK ", image.get_size(), " socket=", altar.selected_anoint_item(),
		"#" , altar.selected_anoint_ordinal(), " rows=", altar.anoint_rows().size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAPTURE_SAVE))
	quit()
