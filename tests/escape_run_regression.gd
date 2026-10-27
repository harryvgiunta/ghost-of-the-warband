extends SceneTree
## Phase 4: the escape is a run, not a teleport.
##
## The cage's regression owns the lesson up to the fight. This one owns what the
## arch does now and what happens on the other side of it:
##
##   1. **The arch opens the road.** A possessed body walks into the camp gate and
##      presses G; exactly one `scene_requested` fires and it carries the run, not
##      the town. The tutorial does not end at the camp gate any more.
##   2. **The road is a place.** The run scene builds a lane between 240 and 300 m
##      long and 9-12 m wide, with at least 24 torches, dense tree walls, hanging
##      rags and bones, gibbets and standards, fires and ground litter - all of it
##      from the world's own art kits - and a node/draw budget it has to stay in.
##   3. **It is walkable.** A body placed at the lane's start and driven down the
##      lane with real intent reaches the town arch without ever leaving the
##      walkable width and without ever getting further from the arch. That is the
##      proof the lane is a corridor and not a wall of collision, and the test
##      records how long the run took.
##   4. **It is a fight.** Eight armed `CageWatcher`s: two start behind the squad
##      on the soul's own body and a pair waits in each clearing. Each drops the
##      weapon it carried. The squad follows the soul.
##   5. **Both endings are the same door.** G at the far arch requests the town
##      once; a wipe (every body downed) requests the town once after its beat and
##      leaves the roster downed, with nothing gathered.

const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

const TEST_SAVE := "user://escape_run_state.json"
const WARBAND_SAVE := "user://escape_run_warband.json"
const CAGE := "res://scenes/cage_escape.tscn"
const RUN := "res://scenes/escape_run.tscn"
const TOWN := "res://scenes/town_hub.tscn"
## How long the walk may take before the test calls it a hang.
const WALK_LIMIT := 70.0
## The walk is played at this speed multiplier so a quarter-kilometre run fits in
## a regression; the recorded time is the game time the lane cost at 1x.
const WALK_SCALE := 3.0

var state
var warband
var cage
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
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()

	# A scene script that fails to parse leaves this coroutine parked forever; the
	# watchdog turns that hang into a failing run.
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	watchdog.wait_time = 300.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	await check_camp_arch()
	await check_run_scene()
	await check_wipe()
	_finish()


func _on_watchdog() -> void:
	check(false, "the escape run did not finish inside the watchdog")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if is_instance_valid(game):
		game.queue_free()
	if is_instance_valid(cage):
		cage.queue_free()
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
	if cage != null and cage.card != null and cage.card.is_open():
		cage.card.close()


# --- 1. the camp arch ------------------------------------------------------

## The arch is the camp's way out and nothing else: it starts the run.
func check_camp_arch() -> void:
	cage = load(CAGE).instantiate()
	root.add_child(cage)
	await create_timer(0.7).timeout
	if not cage.has_method("_try_interact"):
		check(false, "the cage escape scene loaded without its script")
		return
	cage.scene_requested.connect(_on_scene_requested)
	_dismiss_card()
	# Drive the lesson to the escape through the sequencer's own public beats; the
	# cage regression is what proves the beats themselves.
	for merc_id in cage.caged_ids:
		cage.sequencer.note_body_entered(int(merc_id))
	_dismiss_card()
	cage.sequencer.note_rescuer_arrived()
	_dismiss_card()
	cage.sequencer.note_rescuer_taken()
	for index in cage.caged_ids.size():
		cage.sequencer.note_cage_opened(index)
	_dismiss_card()
	for index in SequencerScript.GUARD_COUNT:
		cage.sequencer.note_guard_killed()
	_dismiss_card()
	check(cage.sequencer.state() == SequencerScript.State.ESCAPING,
		"the camp reaches the escape (%s)" % cage.sequencer.state_name())

	var body = cage.controller.active_body(1)
	check(body != null, "the soul has a body at the camp gate")
	body.global_position = cage.GATE_POINT
	game = cage
	await physics_frame
	cage._try_interact()
	await physics_frame
	check(requested.size() == 1, "the arch asks for exactly one scene (%d)" % requested.size())
	if not requested.is_empty():
		var path := str(requested[0])
		check(path == cage.ESCAPE_RUN, "the arch opens the road (%s)" % path)
		check(path.ends_with("escape_run.tscn"), "and the road is the escape run")
		check(path != TOWN, "the camp arch no longer hands over the town")
	check(cage.sequencer.state() == SequencerScript.State.ESCAPING,
		"the tutorial does not end at the camp gate (%s)" % cage.sequencer.state_name())
	# A second press must not queue a second door.
	cage._try_interact()
	check(requested.size() == 1, "the arch only opens once")
	# The STEP 5 card tells the player the arch opens a road, not that it is over.
	var step_body: String = str(cage.STEP_CARDS[4]["body"]).to_lower()
	check(step_body.contains("road"), "the escape card names the road")
	check(not step_body.contains("for town"), "the escape card does not promise town at the gate")

	cage.queue_free()
	game = null
	await process_frame
	await create_timer(0.2).timeout
	# The real hand-off clears the soul registry; this test drives the scenes by
	# hand, so it does the same before the next scene fields bodies.
	warband.clear_possession()
	requested.clear()


# --- 2. the road -----------------------------------------------------------

func check_run_scene() -> void:
	game = load(RUN).instantiate()
	root.add_child(game)
	# The pursuers exist before the first tick, and they start on the soul's body.
	var soul = game.controller.active_body(1)
	check(soul != null, "the soul is seated in a body when the road opens")
	check(game.guards.size() == 8, "eight cultists hold the road (%d)" % game.guards.size())
	for index in mini(2, game.guards.size()):
		check(game.guards[index].player == soul, "pursuer %d starts on the soul's body" % (index + 1))
	game.scene_requested.connect(_on_scene_requested)
	await create_timer(0.7).timeout

	check_lane()
	check_art()
	check_pursuers()
	check_hud()
	await kill_cultists()
	await check_walk()
	await check_follow()
	await check_arch_door()


func check_lane() -> void:
	var lane: PackedVector3Array = game.forest["lane"]
	check(lane.size() >= 8, "the lane has real waypoints (%d)" % lane.size())
	var measured := 0.0
	for index in range(lane.size() - 1):
		measured += lane[index].distance_to(lane[index + 1])
	var length := float(game.forest["length"])
	check(absf(measured - length) <= 0.01,
		"the reported length is the summed waypoints (%.2f vs %.2f)" % [length, measured])
	check(length >= 240.0 and length <= 300.0, "the lane is a long run (%.1f m)" % length)
	var width := float(game.forest["width"])
	check(width >= 9.0 and width <= 12.0, "the lane is %.1f m wide" % width)
	var torches: Array = game.forest["torches"]
	check(torches.size() >= 24, "%d torches light the lane" % torches.size())
	var arch: Vector3 = game.forest["arch"]
	check(arch.is_equal_approx(lane[lane.size() - 1]), "the arch is the far end of the lane")
	var lights := 0
	for host in (game.forest["groups"]["Torches"] as Node).get_children():
		for child in host.get_children():
			if child is OmniLight3D:
				lights += 1
	check(lights == torches.size(), "every torch carries its own light (%d/%d)" % [lights, torches.size()])
	# The spawn ring is inside the walkable band and the arch is walkable to.
	for post in game.forest["spawn_posts"] as Array:
		var point: Vector3 = post
		var off: float = game.forest["path"].distance_to(Vector2(point.x, point.z))
		check(off <= width * 0.5, "a spawn post is inside the lane (%.2f m off centre)" % off)
	print("ESCAPE_RUN_LANE length=%.1f width=%.1f torches=%d waypoints=%d"
		% [length, width, torches.size(), lane.size()])


func check_art() -> void:
	var groups: Dictionary = game.forest["groups"]
	for label in ["Trees", "Bushes", "Grass", "Hanging", "Omens", "Braziers", "Scatter",
			"Rocks", "Torches", "Arch"]:
		check(groups.has(label), "the lane has its %s group" % label)
		if groups.has(label):
			check((groups[label] as Node).get_child_count() > 0,
				"the %s group has props (%d)" % [label, (groups[label] as Node).get_child_count()])
	check((groups["Hanging"] as Node).get_child_count() >= 12,
		"the hanging art is dense (%d hosts)" % (groups["Hanging"] as Node).get_child_count())
	check((groups["Omens"] as Node).get_child_count() >= 6,
		"gibbets/effigies/stakes stand along the verge")
	check((groups["Braziers"] as Node).get_child_count() >= 8,
		"the clearings and the gate burn (%d fires)" % (groups["Braziers"] as Node).get_child_count())
	var stats: Dictionary = game.forest["stats"]
	check(int(stats.get("trees", 0)) >= 240, "the wood is dense: %d trees" % int(stats.get("trees", 0)))
	check(int(stats.get("bushes", 0)) >= 90, "undergrowth: %d bushes" % int(stats.get("bushes", 0)))
	check(int(stats.get("rocks", 0)) >= 150, "stone: %d rocks" % int(stats.get("rocks", 0)))
	check(int(stats.get("grass", 0)) >= 300, "the verge has grass: %d clumps" % int(stats.get("grass", 0)))
	# Collision outside the lane: trunks and wall boxes, all in one static body.
	var solids: StaticBody3D = game.forest["root"].solids
	check(solids.get_child_count() >= 280,
		"the wood and its walls are solid (%d shapes)" % solids.get_child_count())
	# The budget: a lane is one scene, not a draw-call catalogue. The node cap
	# leaves room for the torch line itself - 48 torches is a host, a merged post
	# and a light each, and the lights are what make 286 m of night walkable.
	var draws := int(stats.get("draws", 0))
	var nodes := int(stats.get("nodes", 0))
	check(draws <= 250, "the lane stays inside its draw budget (%d multimesh)" % draws)
	check(nodes <= 900, "the lane stays inside its node budget (%d nodes)" % nodes)
	print("ESCAPE_RUN_ART trees=%d bushes=%d rocks=%d grass=%d nodes=%d draws=%d shapes=%d"
		% [int(stats.get("trees", 0)), int(stats.get("bushes", 0)), int(stats.get("rocks", 0)),
			int(stats.get("grass", 0)), nodes, draws, solids.get_child_count()])


func check_pursuers() -> void:
	var armed := 0
	var visible := 0
	var hunting := 0
	for watcher in game.guards:
		check(is_instance_valid(watcher) and bool(watcher.get("alive")),
			"a cultist is on its feet")
		if str(watcher.get("weapon_item")) != "":
			armed += 1
		if watcher.has_weapon_visual():
			visible += 1
		if bool(watcher.hunting()) and is_instance_valid(watcher.player):
			hunting += 1
		check(is_equal_approx(float(watcher.max_health), 72.0),
			"a road cultist carries 72 health, got %s" % str(watcher.max_health))
		check(watcher.global_position.y > -1.0, "a cultist stands on the lane")
	check(armed == game.guards.size(), "every cultist holds a weapon (%d/%d)"
		% [armed, game.guards.size()])
	check(visible >= 6, "the blade is in its hand (%d visible)" % visible)
	check(hunting >= 2, "the cult is hunting the warband (%d hunting)" % hunting)
	# The pair behind the squad is close enough to be on them at once.
	var start: Vector3 = game.forest["start"]
	for index in mini(2, game.guards.size()):
		var watcher = game.guards[index]
		check(_flat(watcher.global_position, start) <= 8.0,
			"pursuer %d starts at the camp mouth (%.1f m)" % [index + 1,
				_flat(watcher.global_position, start)])
	# The squad is every other body the run fielded.
	check(game.squad_ids.size() == game.bodies.size(), "every body is on the squad list")
	check(game.squad != null and game.squad.following, "the squad is an escort")


func check_hud() -> void:
	check(game.objective_text() == "REACH THE TOWN ROAD",
		"the objective names the escape (%s)" % game.objective_text())
	var prompt: String = game.prompt_text()
	check(prompt.begins_with("REACH THE TOWN ROAD"), "the prompt carries the objective (%s)" % prompt)
	check(prompt.contains(" m"), "the prompt carries the metres to the arch (%s)" % prompt)
	check(not prompt.to_lower().contains("loot"), "the run does not advertise loot (%s)" % prompt)


func kill_cultists() -> void:
	for watcher in game.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(1000.0, 0)
	await create_timer(0.6).timeout
	check(game.cultists_alive() == 0, "the road can be cleared (%d left)" % game.cultists_alive())
	# A dropped weapon can already be in a squadmate's hands: what matters is that
	# every cultist left the piece it carried somewhere on the field.
	check(game.pickups_left() + game.steel_taken >= game.guards.size(),
		"every cultist dropped the weapon it held (%d on the ground, %d taken)"
		% [game.pickups_left(), game.steel_taken])


# --- 3. the walk -----------------------------------------------------------

## The proof that the lane is a corridor: real movement from the lane start to
## the town arch, sampled every physics tick for lateral drift and for distance
## to the arch.
func check_walk() -> void:
	var lane: PackedVector3Array = game.forest["lane"]
	var arch: Vector3 = game.forest["arch"]
	var path = game.forest["path"]
	var half := float(game.forest["width"]) * 0.5
	var body = game.controller.active_body(1)
	check(body != null, "the soul still has a body for the walk")
	body.global_position = lane[0] + Vector3(0.0, 0.1, 0.0)
	# The keyboard intent is the scene's; for the walk the test is the only hand
	# on the stick, so the controller's own key reading steps aside.
	game.controller.input_enabled = false
	await physics_frame
	var previous := _flat(body.global_position, arch)
	var worst := 0.0
	var monotonic := true
	var worst_step := 0.0
	var index := 1
	var ticks := 0
	var started := Time.get_ticks_msec()
	# Three times the simulation per second of wall clock, at the shipped physics
	# step: a tick is still 1/60 s of game time, so the walk is measured under the
	# physics a player actually gets.
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
		var lateral: float = path.distance_to(
			Vector2(body.global_position.x, body.global_position.z))
		worst = maxf(worst, lateral)
		var gap := _flat(body.global_position, arch)
		if gap > previous + 0.05:
			monotonic = false
			worst_step = maxf(worst_step, gap - previous)
		previous = gap
		if gap <= game.ARCH_RADIUS:
			break
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var game_seconds := float(ticks) / 60.0
	check(monotonic, "the walk never gets further from the town arch (worst +%.2f m)" % worst_step)
	check(worst <= half, "the body never leaves the %.1f m lane (%.2f m off centre)" % [half * 2.0, worst])
	check(previous <= game.ARCH_RADIUS + 0.5,
		"the body reached the town arch (%.2f m)" % previous)
	check(ticks < 20000 and real_seconds < WALK_LIMIT,
		"the run finished inside the watchdog (%.1f s real)" % real_seconds)
	print("ESCAPE_RUN_WALK game_seconds=%.1f real_seconds=%.1f ticks=%d lateral=%.2f"
		% [game_seconds, real_seconds, ticks, worst])


# --- 4. the squad ----------------------------------------------------------

## The escort: with the road clear, the squad closes on the soul wherever it is.
func check_follow() -> void:
	var soul = game.controller.active_body(1)
	var needed := mini(3, game.squad_ids.size() - 1)
	var near := 0
	var waited := 0.0
	# The escort has to walk the lane the squad just ran: play it at three times
	# the simulation per second so sixty seconds of catching up fit in the test.
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = WALK_SCALE
	while near < needed and waited < 22.0:
		await create_timer(0.1).timeout
		waited += 0.1
		near = 0
		for merc_id in game.squad_ids:
			if int(merc_id) == game.controller.merc_for_peer(1):
				continue
			var actor = game.controller.body_of(int(merc_id))
			if actor == null or not bool(actor.get("alive")) or bool(actor.get("downed")):
				continue
			if _flat(actor.global_position, soul.global_position) <= 15.0:
				near += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	check(near >= needed,
		"the squad follows the soul down the lane (%d of %d within 15 m after %.0f s)"
		% [near, needed, waited * WALK_SCALE])


# --- 5. the two doors ------------------------------------------------------

func check_arch_door() -> void:
	requested.clear()
	game._try_take_town_road()
	check(requested.size() == 1, "G at the town arch asks for one scene (%d)" % requested.size())
	if not requested.is_empty():
		check(str(requested[0]) == TOWN, "the arch asks for the town (%s)" % str(requested[0]))
	check(game.door_taken(), "the run knows it is over")
	game._try_take_town_road()
	check(requested.size() == 1, "the arch only opens once")


## A wipe: every body down, the run ends by itself, the roster stays downed and
## nothing is gathered on the way out.
func check_wipe() -> void:
	if is_instance_valid(game):
		game.queue_free()
		game = null
	await process_frame
	await create_timer(0.2).timeout
	warband.clear_possession()
	requested.clear()
	game = load(RUN).instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	game.scene_requested.connect(_on_scene_requested)
	check(game.bodies.size() >= 4, "the wiped run still fields the warband (%d)" % game.bodies.size())
	for actor in game.bodies:
		actor.enter_downed(99)
	var waited := 0.0
	while requested.is_empty() and waited < 8.0:
		await create_timer(0.1).timeout
		waited += 0.1
	check(requested.size() == 1, "a wipe hands the warband over exactly once (%d)" % requested.size())
	if not requested.is_empty():
		check(str(requested[0]) == TOWN, "the wiped run ends at the town (%s)" % str(requested[0]))
	for merc_id in game.squad_ids:
		check(warband.roster.is_downed(int(merc_id)),
			"%s is left downed on the roster" % warband.roster.name_of(int(merc_id)))
	check(game.steel_taken == 0, "a wipe gathers nothing (%d pieces)" % game.steel_taken)
	check(game.pickups_left() == 0, "a wipe leaves no drops behind (%d)" % game.pickups_left())
	print("ESCAPE_RUN_WIPE seconds=%.1f bodies=%d downed=%d"
		% [waited, game.bodies.size(), warband.roster.downed_ids().size()])
