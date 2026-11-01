extends SceneTree
## Scratch: what strands a freed prisoner in the opening camp? Three variants,
## each measuring stalls (intent + under 0.3 m in 2 s) with the brain's own flags.

const CampScript = preload("res://scripts/warband/cage_escape.gd")

const TEST_SAVE := "user://camp_stuck_state.json"
const WARBAND_SAVE := "user://camp_stuck_warband.json"
const STEP := 1.0 / 60.0

var warband


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _boot() -> Array:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "camp"
	var game = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(game)
	for index in 90:
		await physics_frame
	return [game, game.controller, game.camp]


func run() -> void:
	print("STUCK ===== D: the soul stands by the collapsed den for 12 s")
	await _variant(Vector3(-12.5, 0.0, -8.5), 12.0, "hut")
	quit(0)


func _variant(stand: Vector3, hold_seconds: float, label: String) -> void:
	var booted: Array = await _boot()
	var game = booted[0]
	var controller = booted[1]
	var camp = booted[2]
	var soul_id: int = controller.merc_for_peer(1)
	var soul = controller.body_of(soul_id)
	for index in camp.CAGE_POSTS.size():
		camp.open_latch(index)
	game.squad.following = true
	game.squad.engage_radius = 34.0
	# Stand the soul where this variant wants it (y from the ground the body is on).
	(soul as Node3D).global_position = Vector3(stand.x,
		(soul as Node3D).global_position.y, stand.z)
	for index in int(hold_seconds / STEP):
		await physics_frame
		if index % 60 == 0:
			_live(game, controller, soul, "t=%.0fs" % (float(index) * STEP))
	await _report(game, controller, soul, label)
	# Now walk out and see who never follows.
	for index in 240:
		await physics_frame
	await _report(game, controller, soul, label + "-after-hold")
	await _walk(game, controller, soul, Vector3(0.0, 0.0, -90.0))
	await _report(game, controller, soul, label + "-walked-out")
	game.queue_free()
	await process_frame


## What each ally is actually doing this second: the pickup or corpse it has
## chosen, the fetch key it is walking to, and whether it even knows where the
## soul is.
func _live(game, controller, soul, when: String) -> void:
	var soul_at: Vector3 = (soul as Node3D).global_position
	var line := "STUCK live %s following=%s soul=(%.1f,%.1f)" % [when,
		str(game.squad.following), soul_at.x, soul_at.z]
	for raw in game.squad.squad_ids:
		var merc_id := int(raw)
		var actor = controller.body_of(merc_id)
		if actor == null or actor == soul:
			continue
		var now: Vector3 = (actor as Node3D).global_position
		var pickup = game.squad._nearest_pickup(actor)
		var steel = game.squad._nearest_weapon_pickup(actor)
		var corpse: int = game.squad._nearest_corpse(actor)
		var track: Dictionary = game.squad._track.get(merc_id, {})
		var piece := "-"
		if pickup != null:
			piece = "%s@%.1f" % [str(pickup.item_id),
				now.distance_to((pickup as Node3D).global_position)]
		var bar := "-"
		if corpse != 0:
			var where: Vector3 = game.loot.corpse_position(corpse)
			bar = "%d@%.1f" % [corpse, now.distance_to(where)]
		line += " | m%d (%.1f,%.1f) d=%.1f pick=%s steel=%s corpse=%s fetch=%s roam=%.1f" % [
			merc_id, now.x, now.z,
			Vector2(now.x - soul_at.x, now.z - soul_at.z).length(),
			piece, "yes" if steel != null else "no", bar,
			str(track.get("fetch_key", "")), float(track.get("roam_left", 0.0))]
	print(line)


## 2 s windows: an ally with intent that covers under 0.3 m is stalled. The brain's
## flags say which recovery it was in.
func _report(game, controller, soul, label: String) -> void:
	var ids: Array = game.squad.squad_ids.duplicate()
	var soul_at: Vector3 = (soul as Node3D).global_position
	var line := "STUCK %s soul=(%.1f,%.1f)" % [label, soul_at.x, soul_at.z]
	for raw in ids:
		var merc_id := int(raw)
		var actor = controller.body_of(merc_id)
		if actor == null or actor == soul:
			continue
		var now: Vector3 = (actor as Node3D).global_position
		var track: Dictionary = game.squad._track.get(merc_id, {})
		var flags: String = "e=%s s=%.2f r=%.2f k=%.2f" % [
			"1" if bool(track.get("engaged", false)) else "0",
			float(track.get("side", 0.0)), float(track.get("retreat", 0.0)),
			float(track.get("stuck", 0.0))]
		line += " | m%d (%.1f,%.1f) d=%.1f %s" % [merc_id, now.x, now.z,
			Vector2(now.x - soul_at.x, now.z - soul_at.z).length(), flags]
	print(line)


func _walk(game, controller, soul, to: Vector3) -> void:
	var from: Vector3 = (soul as Node3D).global_position
	var span := Vector2(to.x - from.x, to.z - from.z).length()
	var frames := maxi(int(ceil((span / 2.6) / STEP)), 1)
	for step in frames:
		var t := float(step) / float(frames)
		var at := from.lerp(Vector3(to.x, from.y, to.z), t)
		(soul as Node3D).global_position = at
		await physics_frame
