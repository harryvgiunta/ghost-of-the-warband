extends SceneTree
## The warband in one kit: eight mercenaries wearing the same five pieces, each
## with the livery, device, finish and trophies `WarbandFlair` derives from his id.
##
##     godot --path . --script res://playtest/armor_flair_lookbook.gd
##     godot --path . --script res://playtest/armor_flair_lookbook.gd -- --set plate
##     godot --path . --script res://playtest/armor_flair_lookbook.gd -- --plain
##
## Writes `res://.runtime/probe/flair_<set>_front.png`, `_back.png`, `_close.png`
## and `_close_back.png` (three bodies near enough to read a device and a
## border) for each of the five armour sets, or only the one named by `--set`.
## `--plain` strips the flair and writes `plain_<set>_*.png`: the same eight men
## as the warband dressed them before. This is the surface the flair is judged
## on: eight men in identical drops who still read as eight.

const Archer = preload("res://scripts/archer.gd")
const Looks = preload("res://scripts/warband/warband_looks.gd")
const Flair = preload("res://scripts/warband/warband_flair.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const SETS := ["makeshift", "leather", "mail", "plate", "cloth"]
const SPACING := 0.95
const COUNT := 8

var _rigs: Array = []
var _camera: Camera3D
var _world: Node3D
var _plain := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	var at := args.find("--set")
	if at >= 0 and at + 1 < args.size():
		only = args[at + 1]
	_plain = args.has("--plain")
	_build_stage()
	for set_name in SETS:
		if not only.is_empty() and set_name != only:
			continue
		await _shoot_set(set_name)
	print("ARMOR_FLAIR_LOOKBOOK ok")
	quit()


## The light of `warband_lookbook.gd`, plus a rim from behind so the back of the
## band - where the big device is - is not a silhouette.
func _build_stage() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.72, 0.55, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.35, -2.5, 0.0)
	fill.light_energy = 0.55
	_world.add_child(fill)
	var back := DirectionalLight3D.new()
	back.rotation = Vector3(-0.5, PI + 0.4, 0.0)
	back.light_energy = 0.45
	_world.add_child(back)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.33, 0.29)
	ground.material_override = mat
	_world.add_child(ground)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 34.0
	_world.add_child(_camera)


func _shoot_set(set_name: String) -> void:
	for rig in _rigs:
		rig.queue_free()
	_rigs.clear()
	await process_frame
	var set_index := ArmorData.SET_IDS.find(set_name)
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = set_index
	for index in COUNT:
		var merc_id := index + 1
		var rig = Archer.new()
		rig.appearance = Looks.profile_for(merc_id)
		if _plain:
			rig.appearance = rig.appearance.duplicate()
			rig.appearance.erase("flair")
		_world.add_child(rig)
		rig.apply_loadout({
			"main": "", "off": "", "weapon": "none", "bow": 0, "sword": 0,
			"staff": -1, "dagger": 1, "armor": pieces,
			"shield": false, "off_weapon": {}, "focus": {},
		})
		rig.position = Vector3((index - (COUNT - 1) * 0.5) * SPACING, 0.0, 0.0)
		_rigs.append(rig)
	for frame in 12:
		await process_frame
	for rig in _rigs:
		for node in [rig.active_dagger, rig.active_sword, rig.active_staff,
				rig.active_bow, rig.active_shield, rig.active_focus, rig._quiver]:
			if node != null and is_instance_valid(node):
				node.visible = false
		if _plain:
			continue
		var flair: Dictionary = rig.appearance["flair"]
		var hung := []
		for row in rig._flair.trophies():
			if bool(row["visible"]):
				hung.append("%s:%s" % [row["anchor"], row["kind"]])
		print("FLAIR %s %d field=%s charge=%s design=%s motif=%s hem=%s thread=%s finish=%s surcoat=%s trophies=%s"
			% [set_name, int(rig.appearance["merc_id"]), flair["field"], flair["charge"],
				Flair.DESIGNS[int(flair["design"])], Flair.MOTIFS[int(flair["motif"])],
				Flair.HEMS[int(flair["hem"])], flair["thread"],
				Flair.FINISHES[int(flair["finish"])]["name"], str(flair["surcoat"]), ", ".join(hung)])
	var prefix := "plain" if _plain else "flair"
	# The rig's model is yawed 180 degrees, so the band faces -Z: the front shot
	# comes from the far side of the row.
	_camera.fov = 34.0
	_camera.position = Vector3(0.0, 1.18, -6.6)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	await _shot("%s_%s_front.png" % [prefix, set_name])
	_camera.position = Vector3(0.0, 1.24, 6.6)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	await _shot("%s_%s_back.png" % [prefix, set_name])
	_camera.fov = 30.0
	_camera.position = Vector3(-1.9, 1.30, -2.7)
	_camera.look_at(Vector3(-1.9, 1.0, 0.0))
	await _shot("%s_%s_close.png" % [prefix, set_name])
	_camera.position = Vector3(1.9, 1.32, 2.7)
	_camera.look_at(Vector3(1.9, 1.05, 0.0))
	await _shot("%s_%s_close_back.png" % [prefix, set_name])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.runtime/probe/%s" % name)
