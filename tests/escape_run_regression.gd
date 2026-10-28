extends SceneTree
## The trail through the wood, driven on the one world.
##
## The escape used to be a scene of its own: the camp's arch loaded it and its own
## gate loaded the town. Neither door exists any more. What this regression owns
## now is the middle of the world:
##
##   1. **The trail is a place.** 240-300 m long and 9-12 m wide, at least 24
##      torches with a light each, dense tree walls, rags and bones, gibbets and
##      effigies, fires and ground litter - all from the world's own art kits -
##      inside a node/draw budget.
##   2. **It meets both ends.** Its first waypoint is the camp's mouth and its last
##      is the town's gate; the lane's walls stop at the clearing and at the
##      settlement instead of capping the corridor.
##   3. **It is walkable.** A body placed at the lane's start and driven down it
##      with real intent reaches the town's gate without leaving the walkable
##      width and without ever getting further from it. The run is timed.
##   4. **It is a fight.** Twenty armed `CageWatcher`s in pairs down the road, each
##      leaving the body the scene registers as a corpse.
##   5. **No door, and a wipe is a defeat.** Reaching the far end changes nothing
##      and requests nothing; every body down leaves the roster exactly that way,
##      gathers nothing, and makes no transition.

const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

const TEST_SAVE := "user://escape_run_state.json"
const WARBAND_SAVE := "user://escape_run_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## How long the walk may take before the test calls it a hang.
## A watchdog against a hang, not a performance budget: nine hundred metres of
## ground is ~170 s of game time and the headless frame rate is not the game's.
const WALK_LIMIT := 260.0
## The walk is played at this speed multiplier so a quarter-kilometre run fits in
## a regression; the recorded time is the game time the lane cost at 1x.
const WALK_SCALE := 3.0
## How long the escort is given to close on the soul at the far end, in scaled
## seconds: it walks the wood behind the soul rather than a lane.
const FOLLOW_S := 40.0

var state
var warband
var game
var checks := 0
var failures := 0
var requested: Array = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("RUN_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	var flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()
	flow.active = false
	flow.world_start = "camp"

	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	# The walk plays at 3x, and a Timer counts scaled time: this is ~500 s real.
	watchdog.wait_time = 1500.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	await check_the_world()
	await check_lane()
	check_art()
	check_pursuers()
	await check_hud()
	await kill_cultists()
	await check_walk()
	await check_follow()
	await check_no_door()
	await check_wipe()
	_finish()


func _on_watchdog() -> void:
	check(false, "the trail did not finish inside the watchdog")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "camp"
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("ESCAPE_RUN_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _on_scene_requested(path: String) -> void:
	requested.append(path)


func _flat(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _dismiss_card() -> void:
	if game != null and game.card != null and game.card.is_open():
		game.card.close()


## The world, opened at the camp, with the lesson driven through its own public
## beats to the escape: what this test wants is the trail, not the cages.
func check_the_world() -> void:
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	game.scene_requested.connect(_on_scene_requested)
	_dismiss_card()
	check(game.camp != null and game.trail != null and game.town != null,
		"the world built all three of its areas")
	for merc_id in game.camp.caged_ids:
		game.camp.sequencer.note_body_entered(int(merc_id))
	_dismiss_card()
	game.camp.sequencer.note_rescuer_arrived()
	_dismiss_card()
	# The pair standing over the cages fall, then the soul itself steps into Corvin
	# for the shiv and walks the cage line cutting one latch per cage - the only
	# way a cage opens now.
	for watcher in game.camp.guards.duplicate():
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	game.controller.direct(1, game.camp.rescuer_id)
	_dismiss_card()
	check(not game.camp.cages_open(), "taking Corvin cuts nothing by itself")
	var cutter = game.controller.active_body(1)
	for index in game.camp.CAGE_POSTS.size():
		var post: Vector3 = game.camp.CAGE_POSTS[index]
		cutter.global_position = Vector3(post.x, 0.2, post.z + 2.6)
		await physics_frame
		game._try_interact()
		_dismiss_card()
		check(game.camp.cages_open_count() == index + 1,
			"latch %d was cut one cage at a time (%d)" % [index + 1, game.camp.cages_open_count()])
	check(game.camp.cages_open(), "all four latches are cut (%d of %d)"
		% [game.camp.cages_open_count(), game.camp.caged_ids.size()])
	# The escape is the walk out: the soul crosses the mouth and the wood answers.
	var soul = game.controller.active_body(1)
	soul.global_position = game.camp.GATE_POINT + Vector3(0.0, 0.2, 0.0)
	await physics_frame
	await physics_frame
	_dismiss_card()
	check(game.camp.sequencer.state() == SequencerScript.State.ESCAPING,
		"the camp reaches the escape (%s)" % game.camp.sequencer.state_name())
	soul = game.controller.active_body(1)
	check(soul != null, "the soul is seated in a body when the trail opens")
	check(soul != null and game.trail.guards.size() == 20,
		"twenty cultists hold the trail (%d)" % game.trail.guards.size())
	# Where they stand is what matters (asserted with the lane, below): a mob's
	# `player` field is its current quarry, not a spawn-time script.


func check_lane() -> void:
	var forest: Dictionary = game.trail.forest
	var lane: PackedVector3Array = forest["lane"]
	check(lane.size() >= 8, "the lane has real waypoints (%d)" % lane.size())
	var measured := 0.0
	for index in range(lane.size() - 1):
		measured += lane[index].distance_to(lane[index + 1])
	var length := float(forest["length"])
	check(absf(measured - length) <= 0.01,
		"the reported length is the summed waypoints (%.2f vs %.2f)" % [length, measured])
	check(length >= 860.0 and length <= 980.0, "the lane is a long run (%.1f m)" % length)
	var width := float(forest["width"])
	check(width >= 9.0 and width <= 12.0, "the lane is %.1f m wide" % width)
	var torches: Array = forest["torches"]
	check(torches.size() >= 24, "%d torches light the lane" % torches.size())
	check(lane[lane.size() - 1].is_equal_approx(forest["arch"]),
		"the reported far end is the lane's last waypoint")
	var road_gap := _flat(lane[0], game.camp.GATE_POINT)
	check(absf(road_gap - game.camp.CAMP_TO_ROAD_METRES) < 1.0,
		"the lane begins %.0f m of wood past the camp's mouth (%.1f m)"
		% [game.camp.CAMP_TO_ROAD_METRES, road_gap])
	check(road_gap >= 150.0, "and no torch of it stands in sight of the cages (%.0f m)" % road_gap)
	check(_flat(forest["arch"], game.town.global_position) <= 40.0,
		"the lane ends at the town (%.1f m from the square)"
		% _flat(forest["arch"], game.town.global_position))
	var lights := 0
	for host in (forest["groups"]["Torches"] as Node).get_children():
		for child in host.get_children():
			if child is OmniLight3D:
				lights += 1
	check(lights == torches.size(), "every torch carries its own light (%d/%d)" % [lights, torches.size()])
	print("ESCAPE_RUN_LANE length=%.1f width=%.1f torches=%d waypoints=%d"
		% [length, width, torches.size(), lane.size()])
	# There is no lane any more: no wall down either verge, no corridor cut through
	# the wood. What keeps the way passable is the clear line round its centre,
	# measured where a body actually walks - a ray either side at chest and shoulder
	# height, never inside 1.25 m of the centre line, so the narrowest gap a body
	# meets is 2.5 m. An arch it walks under is not a pinch; a trunk is.
	check(forest["root"].get_node_or_null("LaneWalls") == null,
		"the lane has no wall geometry to walk between")
	check(forest["root"].get_node_or_null("ForestField") == null,
		"the lane builds no band of its own on the world's ground")
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var path = forest["path"]
	var probe := PhysicsRayQueryParameters3D.new()
	probe.collision_mask = 1
	var clearance := INF
	var tightest := Vector3.ZERO
	var samples := 480
	for index in samples:
		var frame: Dictionary = path.sample(float(length) * float(index) / float(samples))
		var base: Vector3 = TerrainScript.grounded(frame["position"])
		for height in [1.35, 1.9]:
			var from := base + Vector3(0.0, float(height), 0.0)
			for side in [-1.0, 1.0]:
				probe.from = from
				probe.to = from + (frame["right"] as Vector3) * side * 2.6
				var hit: Dictionary = space.intersect_ray(probe)
				var gap := 2.6
				if not hit.is_empty():
					gap = _flat(hit["position"] as Vector3, from)
				if gap < clearance:
					clearance = gap
					tightest = from
	check(clearance >= 1.25,
		"the centre line keeps 2.5 m clear end to end (%.2f m at %.1f,%.1f)"
		% [clearance, tightest.x, tightest.z])
	print("ESCAPE_RUN_CLEAR half_width=%.2f tightest=%s" % [clearance, str(tightest)])


func check_art() -> void:
	var forest: Dictionary = game.trail.forest
	var groups: Dictionary = forest["groups"]
	for label in ["Trees", "Bushes", "Grass", "Hanging", "Omens", "Braziers", "Scatter",
			"Rocks", "Torches"]:
		check(groups.has(label), "the lane has its %s group" % label)
		if groups.has(label):
			check((groups[label] as Node).get_child_count() > 0,
				"the %s group has props (%d)" % [label, (groups[label] as Node).get_child_count()])
	# The far gate is the town's own now: the lane ends at a settlement gate, not
	# at a gate of its own.
	check(game.town.get_node_or_null("NorthGate") != null,
		"the lane's far end is the town's gate")
	check((groups["Hanging"] as Node).get_child_count() >= 12,
		"the hanging art is dense (%d hosts)" % (groups["Hanging"] as Node).get_child_count())
	check((groups["Omens"] as Node).get_child_count() >= 6,
		"gibbets/effigies/stakes stand along the verge")
	check((groups["Braziers"] as Node).get_child_count() >= 8,
		"the clearings and the road burn (%d fires)" % (groups["Braziers"] as Node).get_child_count())
	var stats: Dictionary = forest["stats"]
	check(int(stats.get("trees", 0)) >= 240, "the wood is dense: %d trees" % int(stats.get("trees", 0)))
	check(int(stats.get("bushes", 0)) >= 90, "undergrowth: %d bushes" % int(stats.get("bushes", 0)))
	check(int(stats.get("rocks", 0)) >= 150, "stone: %d rocks" % int(stats.get("rocks", 0)))
	check(int(stats.get("grass", 0)) >= 300, "the verge has grass: %d clumps" % int(stats.get("grass", 0)))
	var solids: StaticBody3D = forest["root"].solids
	check(solids.get_child_count() >= 280,
		"the wood and its walls are solid (%d shapes)" % solids.get_child_count())
	var draws := int(stats.get("draws", 0))
	var nodes := int(stats.get("nodes", 0))
	check(draws <= 700, "the lane stays inside its draw budget (%d multimesh)" % draws)
	check(nodes <= 2600, "the lane stays inside its node budget (%d nodes)" % nodes)
	print("ESCAPE_RUN_ART trees=%d bushes=%d rocks=%d grass=%d nodes=%d draws=%d shapes=%d"
		% [int(stats.get("trees", 0)), int(stats.get("bushes", 0)), int(stats.get("rocks", 0)),
			int(stats.get("grass", 0)), nodes, draws, solids.get_child_count()])


func check_pursuers() -> void:
	var armed := 0
	var visible := 0
	var hunting := 0
	for watcher in game.trail.guards:
		check(is_instance_valid(watcher) and bool(watcher.get("alive")), "a cultist is on its feet")
		if str(watcher.get("weapon_item")) != "":
			armed += 1
		if watcher.has_weapon_visual():
			visible += 1
		if bool(watcher.hunting()) and is_instance_valid(watcher.player):
			hunting += 1
		check(is_equal_approx(float(watcher.max_health), 144.0),
			"a road cultist carries twice the old pool, got %s" % str(watcher.max_health))
		check(watcher.global_position.y > -1.0, "a cultist stands on the lane")
		check(watcher.safe_center.is_equal_approx(game.trail.town_gate()),
			"the town's gate is the safe ring, so nobody is hunted inside it")
	check(armed == game.trail.guards.size(), "every cultist holds a weapon (%d/%d)"
		% [armed, game.trail.guards.size()])
	check(visible >= 6, "the blade is in its hand (%d visible)" % visible)
	# The road answers the *leaving*: when the squad steps out of the clearing a
	# third of every ring is handed the soul, and no more. A cultist with a quarry
	# from spawn walks ninety metres into the camp's own fight.
	check(hunting <= int(game.trail.guards.size() / 3) + 1,
		"only the leaving hands the road a quarry (%d of %d hunting)"
		% [hunting, game.trail.guards.size()])
	# The ambush stands well inside the trail rather than on the camp's doorstep:
	# a cultist sees 60 m, so anything closer joins the tutorial's own fight.
	var start: Vector3 = game.trail.forest["start"]
	var near := 0
	var far := 0
	for watcher in game.trail.guards:
		var distance := _flat(watcher.global_position, start)
		if distance <= 60.0:
			near += 1
		if distance < 250.0:
			far += 1
	check(near == 0, "nobody stands within sight of the camp's mouth (%d within 60 m)"
		% near)
	check(far >= 6, "the cult is still on the road (%d within 250 m)" % far)
	check(game.squad != null and game.squad.following, "the squad is an escort once the camp is clear")
	check(game.squad.watchers == game.guards,
		"the squad fights the world's one hostile list, not a copy of it")


func check_hud() -> void:
	var soul = game.controller.active_body(1)
	soul.global_position = game.trail.forest["start"] + Vector3(0.0, 0.2, -6.0)
	await create_timer(0.2).timeout
	check(game.objective_text() == "REACH THE TOWN",
		"the objective names the town (%s)" % game.objective_text())
	var prompt: String = game.prompt_text()
	check(prompt.begins_with("REACH THE TOWN"), "the prompt carries the objective (%s)" % prompt)
	check(prompt.contains(" m"), "the prompt carries the metres to the town (%s)" % prompt)
	check(not prompt.to_lower().contains("loot"), "the trail does not advertise loot (%s)" % prompt)
	check(not prompt.to_lower().contains("press g"), "and no door (%s)" % prompt)


func kill_cultists() -> void:
	# The camp's watchers go too, and their second wave with them: this test drove
	# the sequencer to the escape without fighting them, so they are the test's own
	# artefacts rather than the trail's business. Every pass is one more wave.
	for pass_index in 4:
		for watcher in game.guards.duplicate():
			if is_instance_valid(watcher) and bool(watcher.get("alive")):
				watcher.take_damage(1000.0, 0)
		await create_timer(1.6).timeout
	check(game.trail.cultists_alive() == 0, "the trail can be cleared (%d left)"
		% game.trail.cultists_alive())
	check(game.loot.corpse_ids().size() >= game.trail.guards.size(),
		"every cultist is a lootable corpse (%d registered for %d bodies)"
		% [game.loot.corpse_ids().size(), game.trail.guards.size()])


# --- the walk --------------------------------------------------------------

## The proof that the lane is a corridor: real movement from the lane's start to
## the town's gate, sampled every physics tick for lateral drift and for distance
## to the gate.
func check_walk() -> void:
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var gate: Vector3 = game.trail.town_gate()
	var path = game.trail.forest["path"]
	var half := float(game.trail.forest["width"]) * 0.5
	var body = game.controller.active_body(1)
	check(body != null, "the soul still has a body for the walk")
	body.global_position = lane[0] + Vector3(0.0, 0.1, 0.0)
	game.controller.input_enabled = false
	await physics_frame
	var previous := _flat(body.global_position, gate)
	var worst := 0.0
	var monotonic := true
	var worst_step := 0.0
	var index := 1
	var ticks := 0
	var last_gap := 9999.0
	var stall_ticks := 0
	var started := Time.get_ticks_msec()
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = WALK_SCALE
	while index < lane.size() and ticks < 20000:
		var to: Vector3 = lane[index] - body.global_position
		to.y = 0.0
		if to.length() <= 1.4:
			index += 1
			continue
		var direction := to.normalized()
		body.accept_network_input(Vector2(direction.x, direction.z), false)
		await physics_frame
		ticks += 1
		if not is_instance_valid(body) or bool(body.get("downed")) or not bool(body.get("alive")):
			break
		var lateral: float = path.distance_to(
			Vector2(body.global_position.x, body.global_position.z))
		worst = maxf(worst, lateral)
		var gap := _flat(body.global_position, gate)
		if gap > previous + 0.05:
			monotonic = false
			worst_step = maxf(worst_step, gap - previous)
		previous = gap
		if gap <= 3.0:
			break
		# A player steps around a post; a straight-line driver pushes into it and
		# stays there. Sidestep for a beat whenever the ground stops being made.
		if absf(gap - last_gap) < 0.05:
			stall_ticks += 1
		else:
			stall_ticks = 0
		last_gap = gap
		if stall_ticks > 40:
			body.accept_network_input(Vector2(-direction.z, direction.x)
				* (1.0 if int(ticks / 40) % 2 == 0 else -1.0), false)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var game_seconds := float(ticks) / 60.0
	check(monotonic, "the walk never gets further from the town (worst +%.2f m)" % worst_step)
	check(worst <= half, "the body never leaves the %.1f m lane (%.2f m off centre)" % [half * 2.0, worst])
	check(previous <= 4.0, "the body reached the town's gate (%.2f m)" % previous)
	check(ticks < 20000 and real_seconds < WALK_LIMIT,
		"the run finished inside the watchdog (%.1f s real)" % real_seconds)
	check(requested.is_empty(), "walking the trail requests no scene (%s)" % str(requested))
	print("ESCAPE_RUN_WALK game_seconds=%.1f real_seconds=%.1f ticks=%d lateral=%.2f"
		% [game_seconds, real_seconds, ticks, worst])


## The escort: with the road clear, the squad closes on the soul wherever it is.
func check_follow() -> void:
	var soul = game.controller.active_body(1)
	var needed := mini(3, game.squad_ids.size() - 1)
	var near := 0
	var waited := 0.0
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = WALK_SCALE
	# The escort walks a forest, not a lane: it cuts corners, pushes past trunks and
	# comes up the rises behind the soul, so it is allowed a longer catch-up than the
	# flat corridor it used to run down.
	while near < needed and waited < FOLLOW_S:
		await create_timer(0.1).timeout
		waited += 0.1
		near = 0
		for merc_id in game.squad_ids:
			if int(merc_id) == game.controller.merc_for_peer(1):
				continue
			var actor = game.controller.body_of(int(merc_id))
			if actor == null or not bool(actor.get("alive")) or bool(actor.get("downed")):
				continue
			if _flat(actor.global_position, soul.global_position) <= 20.0:
				near += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	check(near >= needed,
		"the squad follows the soul down the trail (%d of %d within 20 m after %.0f s)"
		% [near, needed, waited * WALK_SCALE])


# --- the end of the trail --------------------------------------------------

## The far end is the town's gate, and walking through it is not a door: the
## square is simply there, and nothing is requested.
func check_no_door() -> void:
	var body = game.controller.active_body(1)
	var transitions_before: int = root.get_node("GameFlow").transitions
	body.global_position = game.trail.town_gate() + Vector3(0.0, 0.2, 0.0)
	await physics_frame
	game._try_interact()
	await create_timer(0.3).timeout
	check(requested.is_empty(), "the end of the trail asks for no scene (%s)" % str(requested))
	check(root.get_node("GameFlow").transitions == transitions_before,
		"and makes no transition (%d)" % root.get_node("GameFlow").transitions)
	check(game.town.in_square(body) or _flat(body.global_position, game.town.global_position) < 40.0,
		"the town is simply there, on foot")
	check(game.town.service_at(game.town.global_position) == "",
		"the square's fire is not a service, so nothing was triggered by standing there")


## A wipe: every body down. There is no door to hand the warband through any more,
## so the world stops, the roster keeps the truth and nothing is gathered.
func check_wipe() -> void:
	if is_instance_valid(game):
		game.queue_free()
		game = null
	await process_frame
	await create_timer(0.2).timeout
	warband.clear_possession()
	requested.clear()
	root.get_node("GameFlow").world_start = "camp"
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout
	game.scene_requested.connect(_on_scene_requested)
	# The opening card pauses the tree; a paused world cannot notice a wipe.
	_dismiss_card()
	check(game.bodies.size() >= 4, "the wiped world still fields the warband (%d)" % game.bodies.size())
	var transitions_before: int = root.get_node("GameFlow").transitions
	for actor in game.bodies:
		actor.enter_downed(99)
	var waited := 0.0
	while not game._wiped and waited < 8.0:
		await create_timer(0.1).timeout
		waited += 0.1
	check(game._wiped, "the world notices the warband is down")
	check(requested.is_empty(), "a wipe hands the warband through no door (%s)" % str(requested))
	check(root.get_node("GameFlow").transitions == transitions_before,
		"and makes no transition (%d)" % root.get_node("GameFlow").transitions)
	for merc_id in game.squad_ids:
		check(warband.roster.is_downed(int(merc_id)),
			"%s is left downed on the roster" % warband.roster.name_of(int(merc_id)))
	check(game.camp.steel_taken() == 0, "a wipe gathers nothing (%d pieces)" % game.camp.steel_taken())
	var soul = game.controller.active_body(1)
	check(soul == null or not is_instance_valid(soul) or bool(soul.get("downed")),
		"no soul is left standing in a downed body")
	print("ESCAPE_RUN_WIPE seconds=%.1f bodies=%d downed=%d"
		% [waited, game.bodies.size(), warband.roster.downed_ids().size()])
