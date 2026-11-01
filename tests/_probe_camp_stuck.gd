extends SceneTree
## Throwaway probe: plays the camp opening with real movement (soul driven through
## accept_network_input, latches cut where a player stands) and reports every freed
## ally that stalls - wants to move, not fighting, < 0.5 m net in a 2 s window.

const TEST_SAVE := "user://camp_probe_state.json"
const WARBAND_SAVE := "user://camp_probe_warband.json"

var game
var controller
var camp
var squad
var soul
var frame := 0
var _anchor := {}
var _intent := {}
var stall_count := {}
var variant := "front"


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func fmt(v: Vector3) -> String:
	return "(%.1f,%.1f)" % [v.x, v.z]


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("variant="):
			variant = arg.substr(8)
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "camp"
	game = load("res://scenes/warband_world.tscn").instantiate()
	root.add_child(game)
	for index in 90:
		await physics_frame
	controller = game.controller
	camp = game.camp
	squad = game.squad
	soul = controller.active_body(1)
	controller.input_enabled = false
	if variant == "dump":
		dump_obstacles()
		quit(0)
		return
	if variant == "map":
		dump_map()
		quit(0)
		return
	if variant == "bench":
		var started := Time.get_ticks_usec()
		var fresh = camp._build_nav()
		print("PROBE BENCH build=%d us" % (Time.get_ticks_usec() - started))
		var from := Vector3(-17.0, 0.0, -18.0)
		var to := Vector3(9.5, 0.0, 16.0)
		started = Time.get_ticks_usec()
		var route: PackedVector3Array
		for index in 100:
			route = fresh.route(from, to)
		print("PROBE BENCH route=%d us (%d cells)" % [(Time.get_ticks_usec() - started) / 100, route.size()])
		started = Time.get_ticks_usec()
		var clear := false
		for index in 1000:
			clear = fresh.clear_line(Vector3(-15.0, 0.0, -25.0), Vector3(15.0, 0.0, 20.0))
		print("PROBE BENCH line54m=%.1f us clear=%s" % [float(Time.get_ticks_usec() - started) / 1000.0, str(clear)])
		started = Time.get_ticks_usec()
		for index in 100:
			route = fresh.route(Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, 7.6))
		print("PROBE BENCH sealed=%d us (%d cells)" % [(Time.get_ticks_usec() - started) / 100, route.size()])
		quit(0)
		return
	if variant == "freed":
		for watcher in camp.guards:
			watcher.take_damage(4000.0, 0)
		for index in camp.CAGE_POSTS.size():
			camp.open_latch(index)
		squad.following = true
		await hold(2.0)
		print("PROBE freeing the pair's bodies")
		for watcher in camp.guards:
			if is_instance_valid(watcher):
				watcher.queue_free()
		await hold(1.0)
		print("PROBE done")
		quit(0)
		return
	if variant == "sweep" or variant == "sweep-nonav":
		if variant == "sweep-nonav":
			squad.nav = null
		await sweep()
		quit(0)
		return
	print("PROBE variant=%s soul=%s" % [variant, fmt(soul.global_position)])
	# 1. own latch, step out the front.
	camp.open_latch(0)
	await hold(1.4)
	await walk([Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 1.0)])
	print("PROBE state=%s" % camp.sequencer.state_name())
	# 2. round the west side of the own cage to the shiv.
	await walk([Vector3(-2.7, 0.0, 2.5), Vector3(-2.7, 0.0, 9.2)])
	game._try_loot()
	print("PROBE shiv taken=%s weapon=%s" % [str(camp.duel.fighting()), str(soul.rig.weapon)])
	# The pair come at the soul; the player puts them down where they arrive.
	var waited := 0
	while waited < 600:
		await tick()
		waited += 1
		var close := 0
		for watcher in camp.guards:
			if is_instance_valid(watcher) and soul.global_position.distance_to(watcher.global_position) < 3.0:
				close += 1
		if close >= 2:
			break
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	await hold(1.0)
	var order: Array = [1, 2, 3, 4]
	var stands := _stands()
	for index in order:
		var path: Array = stands[index]
		await walk(path)
		var opened: bool = camp.open_latch(index)
		print("PROBE cage %d opened=%s soul=%s state=%s" % [index, str(opened),
			fmt(soul.global_position), camp.sequencer.state_name()])
		await hold(1.4)
		await hold(4.0)
		report("after cage %d" % index)
		dump_allies("after cage %d" % index)
	# 3. the mouth.
	await walk([Vector3(6.0, 0.0, -16.0), Vector3(0.0, 0.0, -23.0), Vector3(0.0, 0.0, -29.0)])
	print("PROBE at mouth state=%s" % camp.sequencer.state_name())
	await hold(6.0)
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	await hold(3.0)
	report("ambush down")
	dump_allies("ambush down")
	# 4. down the corridor: the corridor's own gaps, centre line.
	var points: Array = []
	for gap in camp.clearing.get("corridor", []):
		var rect: Rect2 = gap
		points.append(Vector3(rect.get_center().x, 0.0, rect.get_center().y))
	points.sort_custom(func(a, b): return a.z > b.z)
	var walk_points: Array = []
	for point in points:
		if (point as Vector3).z < -30.0 and (point as Vector3).z > -95.0:
			walk_points.append(point)
	await walk(walk_points)
	await hold(8.0)
	report("corridor")
	dump_allies("corridor")
	print("PROBE stalls=%s" % str(stall_count))
	quit(0)


## Where a player stands to cut each latch, walking from the last one.
func _stands() -> Dictionary:
	match variant:
		"side":
			return {
				1: [Vector3(-5.0, 0.0, 9.5), Vector3(-7.5, 0.0, 12.0)],
				2: [Vector3(0.0, 0.0, 9.5), Vector3(5.0, 0.0, 10.0), Vector3(7.2, 0.0, 13.4)],
				3: [Vector3(5.0, 0.0, 4.0), Vector3(0.0, 0.0, 1.0), Vector3(-9.0, 0.0, -13.0),
					Vector3(-14.6, 0.0, -18.5)],
				4: [Vector3(-8.0, 0.0, -14.0), Vector3(0.0, 0.0, -10.0), Vector3(9.6, 0.0, -9.5)],
			}
		"back":
			return {
				1: [Vector3(-5.0, 0.0, 9.5), Vector3(-7.0, 0.0, 15.0), Vector3(-10.0, 0.0, 14.6)],
				2: [Vector3(-5.0, 0.0, 15.5), Vector3(0.0, 0.0, 15.5), Vector3(9.5, 0.0, 16.0)],
				3: [Vector3(5.0, 0.0, 9.0), Vector3(3.0, 0.0, 2.0), Vector3(-9.0, 0.0, -9.0),
					Vector3(-14.5, 0.0, -14.5), Vector3(-17.0, 0.0, -16.0)],
				4: [Vector3(-8.0, 0.0, -11.0), Vector3(0.0, 0.0, -5.0), Vector3(12.0, 0.0, -7.0)],
			}
	return {
		1: [Vector3(-5.0, 0.0, 9.5), Vector3(-10.0, 0.0, 9.4)],
		2: [Vector3(0.0, 0.0, 9.5), Vector3(5.0, 0.0, 10.0), Vector3(9.5, 0.0, 11.0)],
		3: [Vector3(5.0, 0.0, 4.0), Vector3(0.0, 0.0, 1.0), Vector3(-9.0, 0.0, -13.0),
			Vector3(-17.0, 0.0, -21.0)],
		4: [Vector3(-8.0, 0.0, -14.0), Vector3(0.0, 0.0, -12.0), Vector3(12.0, 0.0, -12.0)],
	}


func tick() -> void:
	await physics_frame
	frame += 1
	monitor()


func hold(seconds: float) -> void:
	for index in int(seconds * 60.0):
		soul.accept_network_input(Vector2.ZERO, false)
		await tick()


func walk(points: Array, running: bool = false) -> void:
	for target in points:
		var stall := 0
		var last: Vector3 = soul.global_position
		var ticks := 0
		while ticks < 60 * 30:
			var to: Vector3 = (target as Vector3) - soul.global_position
			to.y = 0.0
			if to.length() <= 0.6:
				break
			var dir := to.normalized()
			soul.accept_network_input(Vector2(dir.x, dir.z), running)
			await tick()
			ticks += 1
			if soul.global_position.distance_to(last) < 0.01:
				stall += 1
				if stall > 90:
					print("PROBE SOUL_STALL at %s toward %s" % [fmt(soul.global_position), fmt(target)])
					break
			else:
				stall = 0
			last = soul.global_position
	soul.accept_network_input(Vector2.ZERO, false)


func monitor() -> void:
	var soul_at: Vector3 = soul.global_position
	for raw in squad.squad_ids:
		var merc_id := int(raw)
		var actor = controller.body_of(merc_id)
		if actor == null or actor == soul or not squad._is_free(merc_id):
			continue
		var track: Dictionary = squad._track.get(merc_id, {})
		if Vector2(actor.move_direction).length_squared() > 0.01:
			_intent[merc_id] = int(_intent.get(merc_id, 0)) + 1
		if not _anchor.has(merc_id):
			_anchor[merc_id] = actor.global_position
			continue
		if frame % 120 != 0:
			continue
		var net: float = (actor.global_position - (_anchor[merc_id] as Vector3)).length()
		var intent := int(_intent.get(merc_id, 0))
		_anchor[merc_id] = actor.global_position
		_intent[merc_id] = 0
		if net < 0.5 and intent > 60 and not bool(track.get("engaged", false)):
			stall_count[merc_id] = int(stall_count.get(merc_id, 0)) + 1
			var post: Vector3 = squad._escort_post(actor, track) if is_instance_valid(squad.player_body) else Vector3.ZERO
			print("PROBE STALL t=%.1f m%d at %s soul=%s d=%.1f fetch=%s to_post=%s post=%s r=%.2f s=%.2f net=%.2f intent=%d" % [
				float(frame) / 60.0, merc_id, fmt(actor.global_position), fmt(soul_at),
				Vector2(actor.global_position.x - soul_at.x, actor.global_position.z - soul_at.z).length(),
				str(track.get("fetch_key", "")), str(track.get("to_post", false)), fmt(post),
				float(track.get("retreat", 0.0)), float(track.get("side", 0.0)), net, intent])


func report(label: String) -> void:
	var soul_at: Vector3 = soul.global_position
	var line := "PROBE %s t=%.1f soul=%s" % [label, float(frame) / 60.0, fmt(soul_at)]
	for raw in squad.squad_ids:
		var merc_id := int(raw)
		var actor = controller.body_of(merc_id)
		if actor == null or actor == soul:
			continue
		var free: bool = squad._is_free(merc_id)
		line += " | m%d%s %s d=%.1f %s" % [merc_id, "" if free else "(caged)",
			fmt(actor.global_position),
			Vector2(actor.global_position.x - soul_at.x, actor.global_position.z - soul_at.z).length(),
			str(actor.rig.weapon)]
	print(line)


func dump_allies(label: String) -> void:
	var soul_at: Vector3 = soul.global_position
	print("PROBE DUMP %s rescuer=%d trail=%d" % [label, int(squad._rescuer_merc), squad._trail.size()])
	for raw in squad.squad_ids:
		var merc_id := int(raw)
		var actor = controller.body_of(merc_id)
		if actor == null or actor == soul:
			continue
		var track: Dictionary = squad._track.get(merc_id, {})
		var crumb = squad._crumb_for(actor, track.duplicate())
		var watcher = squad._nearest_watcher(actor)
		print("PROBE   m%d at %s d=%.1f free=%s alive=%s downed=%s hp=%.0f/%.0f move=%s eng=%s band=%s fetch=%s to_post=%s r=%.2f s=%.2f crumb=%s watcher=%s" % [
			merc_id, fmt(actor.global_position),
			Vector2(actor.global_position.x - soul_at.x, actor.global_position.z - soul_at.z).length(),
			str(squad._is_free(merc_id)), str(actor.get("alive")), str(actor.get("downed")),
			float(actor.get("health")), float(actor.get("max_health")), str(actor.move_direction),
			str(track.get("engaged", false)), str(track.get("bandaging", false)),
			str(track.get("fetch_key", "")), str(track.get("to_post", false)),
			float(track.get("retreat", 0.0)), float(track.get("side", 0.0)),
			fmt(crumb) if crumb != null else "none",
			(str(watcher.name) + fmt(watcher.global_position)) if watcher != null else "none"])


func dump_obstacles() -> void:
	var solids: Node = camp.clearing.get("solids")
	var trunks: Array[String] = []
	for child in solids.get_children():
		if not (child is CollisionShape3D):
			continue
		var at: Vector3 = (child as CollisionShape3D).global_position
		if absf(at.x) > 30.0 or at.z < -70.0 or at.z > 32.0:
			continue
		var shape = (child as CollisionShape3D).shape
		if shape is CylinderShape3D:
			trunks.append("T(%.1f,%.1f,r%.2f)" % [at.x, at.z, (shape as CylinderShape3D).radius])
		elif shape is BoxShape3D:
			trunks.append("B(%.1f,%.1f,%s)" % [at.x, at.z, str((shape as BoxShape3D).size)])
	print("PROBE OBSTACLES %d: %s" % [trunks.size(), " ".join(trunks)])


func dump_map() -> void:
	var nav = squad.nav
	print("PROBE MAP rect=%s" % str(nav.rect))
	var z := 32.0
	while z >= -66.0:
		var row := ""
		var x := -30.0
		while x <= 30.0:
			var at := Vector3(x + 0.25, 0.0, z + 0.25)
			var open: bool = nav.free_point(at) == at
			var mark := "." if open else "#"
			for index in camp.CAGE_POSTS.size():
				var post: Vector3 = camp.CAGE_POSTS[index]
				if absf(post.x - x) < 0.3 and absf(post.z - z) < 0.3:
					mark = str(index)
			row += mark
			x += 0.5
		print("PROBE %6.1f %s" % [z, row])
		z -= 0.5


## Every cage open, the pair down, the field looted; then the soul stands on the
## camp's worst ground one spot after another and the squad has to reach it.
func sweep() -> void:
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	for index in camp.CAGE_POSTS.size():
		camp.open_latch(index)
	# Opening all five at once skips FREEING, the beat that turns the escort on.
	squad.following = true
	squad.engage_radius = 34.0
	# The soul out of its own cage and to the side, then let the squad arm itself.
	soul.global_position = Vector3(3.0, soul.global_position.y, 2.0)
	await hold(25.0)
	report("looted")
	var spots := [
		["behind cage1", Vector3(-10.0, 0.0, 14.7)],
		["den mouth", Vector3(-12.5, 0.0, -8.0)],
		["behind cage2", Vector3(9.5, 0.0, 16.1)],
		["lean-to mouth", Vector3(-13.5, 0.0, 8.4)],
		["behind cage4", Vector3(12.0, 0.0, -6.8)],
		["behind den", Vector3(-12.5, 0.0, -10.9)],
		["a-frame mouth", Vector3(14.0, 0.0, 8.8)],
		["behind cage3", Vector3(-17.0, 0.0, -15.8)],
		["behind lean-to", Vector3(-13.5, 0.0, 11.0)],
		["behind cage0", Vector3(0.0, 0.0, 8.7)],
		["tree pair W", Vector3(-7.9, 0.0, 5.6)],
		["behind a-frame", Vector3(14.0, 0.0, 11.4)],
		["corner SW", Vector3(-18.0, 0.0, -28.0)],
		["tree pair E", Vector3(16.1, 0.0, 11.4)],
		["corner NW", Vector3(-18.0, 0.0, 20.0)],
		["corner SE", Vector3(18.0, 0.0, -28.0)],
		["corner NE", Vector3(18.0, 0.0, 20.0)],
		["throat", Vector3(0.0, 0.0, -50.0)],
		["altar", Vector3(0.0, 0.0, 14.5)],
	]
	var failed := 0
	for spot in spots:
		var at: Vector3 = spot[1]
		soul.global_position = Vector3(at.x, soul.global_position.y, at.z)
		var frames := 0
		var gathered := false
		while frames < 60 * 15:
			await hold(0.25)
			frames += 15
			if _all_within(7.0):
				gathered = true
				break
		if gathered:
			print("PROBE SWEEP %-15s gathered in %.2f s" % [spot[0], float(frames) / 60.0])
		else:
			failed += 1
			print("PROBE SWEEP %-15s FAILED" % spot[0])
			report("  " + str(spot[0]))
			dump_allies(str(spot[0]))
	print("PROBE SWEEP failed=%d of %d stalls=%s" % [failed, spots.size(), str(stall_count)])


func _all_within(metres: float) -> bool:
	var soul_at: Vector3 = soul.global_position
	for raw in squad.squad_ids:
		var actor = controller.body_of(int(raw))
		if actor == null or actor == soul or not squad._is_free(int(raw)):
			continue
		if not bool(actor.get("alive")) or bool(actor.get("downed")):
			continue
		if Vector2(actor.global_position.x - soul_at.x, actor.global_position.z - soul_at.z).length() > metres:
			return false
	return true
