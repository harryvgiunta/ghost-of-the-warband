extends SceneTree
## The one world: camp, trail and town in a single coordinate space.
##
## This regression is the campaign's spine. It proves the things the old chain of
## three scenes could not:
##
##   1. **One of everything.** The world owns exactly one `PossessionController`,
##      one camera, one `WarbandHud` and one tutorial card, and its three areas
##      adopt them instead of building their own.
##   2. **The camp is in a wood.** The pocket carries a deep wood on every side
##      *and* trees standing inside its own footprint, a ragged stake line where
##      the cult's fence used to be, shelters and a fire round the cages, the four
##      cages on their own anchors - and a long run of ordinary trees between the
##      gap in the wood and the road's first torch.
##   3. **The lesson still works.** CAGED -> ALL_SEEN -> Corvin kills the pair ->
##      F5 -> one latch per cage cut with G -> the squad out and armed -> walking
##      out through the gap is ESCAPING and the six come out of the wood, with
##      every out-of-order beat refused and nothing opening on its own.
##   4. **Walking is the only travel.** A real body is driven out of the camp,
##      down the 915 m trail and into the town square: no scene is requested, no
##      transition is made, the scene object never changes, the body never leaves
##      the walkable ground, and the walk is timed.
##   5. **The town end is the town.** The stash, the altar, the recruiter and the
##      quartermaster answer `G` from where the body stands, and the expedition
##      gate is the campaign's one remaining door.
##   6. **The budget.** One world is one scene: nodes, multimesh draws, lights and
##      collision shapes are counted and bounded.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")
const WildernessScript = preload("res://scripts/warband/wilderness.gd")
const TrailScript = preload("res://scripts/warband/escape_run.gd")
const DuelScript = preload("res://scripts/warband/duel_lesson.gd")
const ArenaScript = preload("res://scripts/admin_arena.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

const TEST_SAVE := "user://warband_world_state.json"
const WARBAND_SAVE := "user://warband_world_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## How long the first fight has to start before the test calls it a hang.
const PAIR_TIMEOUT := 40.0
## How long the driven walk may take before the test calls it a hang.
const WALK_LIMIT := 200.0
## The walk is played at five times the simulation per second so a kilometre and a
## third of trail fits inside the suite's ninety-second ceiling even with the pool
## running seven other Godots; the recorded time is game time at 1x, so the distance
## and the pace asserted below are the campaign's own.
const WALK_SCALE := 5.0
## Where the campaign's walk begins: the cage the soul wakes in (`CAGE_POSTS[0]`).
const CAGE_LINE := Vector3(0.0, 0.2, 6.0)

var game
var flow
var warband
var state
var checks := 0
var failures := 0
var state_log: Array = []
var requested: Array = []
## Ground the opening itself walks: the cages to the mouth, which the ambush
## interrupts. Counted into the campaign's 359 m below so the number the docs
## quote is the whole walk, not the half of it the walk test times.
var opening_metres := 0.0
## The band on the way out: the briar wolves `wilderness.gd` spawns into
## `world.guards` before anything here reads the count, so every hostile tally in
## this run is the camp's watchers plus the trail's cultists plus these.
var wolves: int = WildernessScript.PACK_COUNT


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WORLD_FAIL  ", message)


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
	flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()
	flow.active = false
	flow.world_start = "camp"

	# A scene that fails to parse would park this coroutine forever; the watchdog
	# turns that hang into a failing run.
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	# The walk plays at 3x, and a Timer counts scaled time: this is ~500 s real.
	watchdog.wait_time = 1500.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	game = load(WORLD).instantiate()
	root.add_child(game)
	if not game.has_method("stats"):
		check(false, "the world scene loaded without its script")
		_finish()
		return
	current_scene = game
	await create_timer(1.0).timeout
	game.camp.sequencer.state_changed.connect(_on_state_changed)
	game.scene_requested.connect(_on_scene_requested)
	# From here on the flow is live: if anything in the world opened a door, the
	# transition counter would move and the walk checks would catch it.
	flow.active = true

	check_one_of_each()
	check_camp_in_the_woods()
	check_ground()
	await check_lesson()
	await check_leaving()
	await check_walk()
	await check_town_end()
	check_down_drops_steel()
	check_keys()
	check_budget()
	check_doors()

	_finish()


## A warband body that goes down lets go of what it was holding, into the one
## floor list a soul takes back with `K`. Measured here, in the live world, because
## the wiring is the part that could silently break: `downed_started` has to reach
## the roster and the loot vacuum on the same frame the body falls.
func check_down_drops_steel() -> void:
	var victim = null
	var merc_id := 0
	for body in game.bodies:
		if not is_instance_valid(body) or body == game.controller.active_body(1):
			continue
		if not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		victim = body
		merc_id = game.controller.merc_of(body)
		break
	check(victim != null, "a warband body is standing to drop its steel")
	if victim == null:
		return
	var gear: Dictionary = warband.roster.equipped_of(merc_id)
	var held: Array[String] = []
	for slot in ["off", "main"]:
		if not str(gear.get(slot, "")).is_empty():
			held.append(str(gear.get(slot, "")))
	var floor_before: int = game.pickups.size()
	var at: Vector3 = victim.global_position
	victim.enter_downed(0)
	check(bool(victim.downed), "the body is on the floor")
	if not held.is_empty():
		check(game.pickups.size() == floor_before + held.size(),
			"the floor gains what it was holding (%d for %d)"
			% [game.pickups.size() - floor_before, held.size()])
		var dropped: Dictionary = {}
		for index in range(floor_before, game.pickups.size()):
			var piece = game.pickups[index]
			if is_instance_valid(piece):
				dropped[str(piece.item_id)] = piece
		for item_id in held:
			check(dropped.has(item_id), "the piece it held is on the floor (%s)" % item_id)
		for item_id in dropped:
			check(victim.global_position.distance_to((dropped[item_id] as Node3D).global_position) <= 1.2,
				"and it lies beside the body (%s, %.2f m)" % [item_id,
					victim.global_position.distance_to((dropped[item_id] as Node3D).global_position)])
	var after: Dictionary = warband.roster.equipped_of(merc_id)
	check(str(after.get("main", "")).is_empty() and str(after.get("off", "")).is_empty(),
		"the roster's hands are empty after the fall")
	check(str(victim.rig.weapon) == "none" or str(victim.rig.weapon).is_empty(),
		"and the body in the world is not holding it either (%s)" % str(victim.rig.weapon))
	# A second fall (the bleed-out death) must not drop the same piece twice.
	var floor_mid: int = game.pickups.size()
	victim._die(0)
	check(game.pickups.size() == floor_mid, "the death of an already-dropped body adds no second blade")


## One key press, as the window would send it: pressed, no echo, no modifiers.
func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


## The campaign's own key map, driven through the live scene's `_unhandled_input`:
## `O` is the warband screen (TAB is not), and `TAB` is the frontier's quick weapon
## swap - the body puts away the set in its hands and takes up the other one, with
## the rig re-dressed from the roster.
func check_keys() -> void:
	var merc_id: int = game.controller.merc_for_peer(1)
	check(merc_id > 0, "the soul is in a body to swap for")
	if merc_id <= 0:
		return
	warband.stash.add("bow_twig", 1)
	warband.stash.add("club_makeshift", 1)
	check(bool(warband.equip_merc(merc_id, "main", "bow_twig").get("ok", false)),
		"the soul's body takes the twig bow")
	game.controller.refresh_gear(merc_id)
	check(str(game.controller.body_of(merc_id).rig.weapon) == "bow",
		"the bow is in its hands")
	check(not game.screen.is_open(), "the warband screen starts closed")
	game._unhandled_input(_key(KEY_O))
	check(game.screen.is_open(), "O opens the warband screen")
	game._unhandled_input(_key(KEY_O))
	check(not game.screen.is_open(), "O closes it again")
	game._unhandled_input(_key(KEY_TAB))
	check(not game.screen.is_open(), "TAB does not open the warband screen")
	var hands: Dictionary = warband.roster.equipped_of(merc_id)
	check(str(hands.get("main", "")).is_empty() and str(hands.get("off", "")).is_empty(),
		"TAB puts the bow away and the empty Set 2 is in its hands")
	check(str(game.controller.body_of(merc_id).rig.weapon) != "bow",
		"and the rig let go of it (%s)" % str(game.controller.body_of(merc_id).rig.weapon))
	check(bool(warband.equip_merc(merc_id, "main", "club_makeshift").get("ok", false)),
		"a club goes into the empty Set 2")
	game.controller.refresh_gear(merc_id)
	game._unhandled_input(_key(KEY_TAB))
	hands = warband.roster.equipped_of(merc_id)
	check(str(hands.get("main", "")) == "bow_twig", "the next TAB brings Set 1's bow back")
	check(str(game.controller.body_of(merc_id).rig.weapon) == "bow",
		"and the rig is holding it again")
	check(warband.roster.weapon_set_pair(merc_id, 1).get("main", "") == "club_makeshift",
		"Set 2 kept the club the swap put away")


func _on_watchdog() -> void:
	check(false, "the one world did not finish inside the watchdog")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	flow.active = false
	flow.world_start = "camp"
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_WORLD_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _on_state_changed(new_state: int, objective: String) -> void:
	state_log.append([new_state, objective])


func _on_scene_requested(path: String) -> void:
	requested.append(path)


## How many times the machine *entered* `value`: a state is announced again on
## every counter change while it is held, and that is not a transition.
func state_count(value: int) -> int:
	var total := 0
	var previous := -1
	for entry in state_log:
		var current := int(entry[0])
		if current == value and previous != value:
			total += 1
		previous = current
	return total


func flat_range(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


## The warband teaches with tips, never with pages: a beat that offers a hint must
## leave the game running, and nothing may pause the tree over a read.
func dismiss_card(label: String) -> void:
	if game == null:
		return
	check(not paused, "the game is never held still by a read (%s)" % label)
	if game.tips != null and is_instance_valid(game.tips):
		game.tips.hide()


## Poll a condition while playing the player: any card that opens during the wait
## is read and closed, so the world keeps moving.
func await_condition(predicate: Callable, timeout: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		dismiss_card(label)
		if bool(predicate.call()):
			return true
		await create_timer(0.05).timeout
	dismiss_card(label)
	return bool(predicate.call())


# --- 1. one of everything --------------------------------------------------

func nodes_named(label: String) -> int:
	var total := 0
	for node in game.find_children(label, "", true, false):
		if String(node.name) == label:
			total += 1
	return total


func check_one_of_each() -> void:
	check(game.controller != null, "the world owns a possession controller")
	check(nodes_named("Soul") == 1, "exactly one controller exists (%d)" % nodes_named("Soul"))
	check(nodes_named("WarbandHud") == 1, "exactly one warband HUD exists (%d)" % nodes_named("WarbandHud"))
	check(nodes_named("TutorialCard") == 0,
		"the world carries no tutorial card any more (%d)" % nodes_named("TutorialCard"))
	check(nodes_named("Tips") == 1,
		"exactly one tip channel exists (%d)" % nodes_named("Tips"))
	# Only the world's own view counts: the paperdoll renders its character into
	# a SubViewport, and a camera that is current inside a SubViewport is current
	# for that viewport alone.
	var cameras := 0
	for node in game.find_children("*", "Camera3D", true, false):
		if not (node as Camera3D).current:
			continue
		var inside_viewport := false
		var parent: Node = node.get_parent()
		while parent != null and parent != game:
			if parent is SubViewport:
				inside_viewport = true
				break
			parent = parent.get_parent()
		if not inside_viewport:
			cameras += 1
	check(cameras == 1, "exactly one camera is current (%d)" % cameras)
	# The three areas are the same scripts their standalone previews use, and they
	# are all pointed at the world's one controller, HUD and card.
	check(game.camp != null and game.trail != null and game.town != null,
		"the world built its camp, its trail and its town")
	check(game.camp.controller == game.controller and game.town.controller == game.controller,
		"the areas adopt the world's controller instead of building one")
	check(game.camp.hud == game.hud and game.town.hud == game.hud,
		"the areas write to the world's one HUD")
	check(game.camp.tips == game.tips, "the areas share the world's one tip channel")
	check(game.camp.squad == game.squad,
		"the camp drives the world's one squad module, not a copy")
	check(game.bodies.size() == 5, "five bodies stand in the camp (%d)" % game.bodies.size())
	check(warband.roster.count() == 5, "five mercenaries are sworn (%d)" % warband.roster.count())
	var local = game.controller.active_body(1)
	check(local != null, "the local soul starts inside a body")
	check(game.camp.caged_ids.has(game.controller.merc_for_peer(1)),
		"the soul starts inside one of the five prisoners")
	check(game.camp.caged_ids.size() == 5, "all five of the warband are in cages (%d)"
		% game.camp.caged_ids.size())
	# The tutorial machine ends in the escape: there is no TOWN beat.
	check(SequencerScript.state_name_of(SequencerScript.State.ESCAPING) == "escaping",
		"the escape is the tutorial's last state")
	check(SequencerScript.state_name_of(SequencerScript.State.ESCAPING + 1) == "unknown",
		"the state machine stops at the escape - there is no town state")
	# The opening's whole script is a table of one-line tips: no paragraph, no
	# page, and every one of them a command.
	var tips_table: Dictionary = game.camp.OPENING_TIPS
	check(tips_table.size() == 8, "the opening has eight tips (%d)" % tips_table.size())
	for id in tips_table.keys():
		var row: Dictionary = tips_table[id]
		var text := str(row.get("text", ""))
		var keys := str(row.get("keys", ""))
		check(not text.contains("\n") and not keys.contains("\n"),
			"%s is one line" % id)
		check(text.length() <= 48, "%s is short enough to read over a fight (%d)"
			% [id, text.length()])
		check(not text.ends_with("."), "%s is a command, not a sentence" % id)
	var run_row: Dictionary = tips_table[game.camp.TIP_RUN]
	check(str(run_row["text"]).to_lower().contains("town"),
		"the last tip names the town (%s)" % str(run_row["text"]))
	check(game.camp.RUN_MARKER_LABEL == "RUN TO TOWN",
		"and the arrow over the way out says the same (%s)" % game.camp.RUN_MARKER_LABEL)


# --- 2. the camp is in a wood ----------------------------------------------

func check_camp_in_the_woods() -> void:
	var wood: Dictionary = game.camp.clearing
	check(int(wood.get("trees", 0)) >= 150, "the camp sits inside a real wood (%d trees)"
		% int(wood.get("trees", 0)))
	check(int(wood.get("bushes", 0)) >= 200, "undergrowth fills it (%d bushes)"
		% int(wood.get("bushes", 0)))
	check(int(wood.get("stakes", 0)) >= 60,
		"the boundary is a ragged stake line, not a fence (%d)" % int(wood.get("stakes", 0)))
	check(int(wood.get("wall", 0)) >= 5, "the wood behind the trunks is solid (%d wall runs)"
		% int(wood.get("wall", 0)))
	check(int(wood.get("huts", 0)) >= 2, "shelters stand round the cages (%d huts)"
		% int(wood.get("huts", 0)))
	# A camp, not a parade ground: the walkable pocket shrank, and the wood runs far
	# past it in every direction.
	var clear: Vector2 = game.clearing_size()
	check(clear.x >= 30.0 and clear.y >= 40.0,
		"the pocket still holds the cages, a fire and a squad (%.0f x %.0f m)" % [clear.x, clear.y])
	check(clear.x <= 50.0 and clear.y <= 60.0,
		"and it is a camp, not a field (%.0f x %.0f m)" % [clear.x, clear.y])
	var band: Rect2 = wood.get("band", Rect2())
	check(band.size.x >= clear.x + 300.0 and band.size.y >= clear.y + 300.0,
		"the wood runs at least 150 m out on every side (%.0f x %.0f m)"
		% [band.size.x, band.size.y])
	# Trees stand inside the pocket's own footprint, which is what stops it reading
	# as a mown field with a treeline painted behind it.
	var inside := int(wood.get("inside_trees", 0))
	check(inside >= 6, "trees stand inside the camp itself (%d trunks)" % inside)
	check(game.camp.get_node_or_null("Clearing/Wood") != null,
		"the camp's wood is one batched group")
	# The campsite: shelters, a fire and the junk, all close in around the cages.
	for label in ["Huts", "CampFire", "CampJunk", "Dirt", "StakeRing", "WoodLitter"]:
		check(game.camp.get_node_or_null("Clearing/%s" % label) != null,
			"the camp builds its %s" % label)
	print("WORLD_CLEARING size=%.0fx%.0f band=%.0fx%.0f inside=%d trees=%d bushes=%d stakes=%d wall=%d"
		% [clear.x, clear.y, band.size.x, band.size.y, inside,
			int(wood.get("trees", 0)), int(wood.get("bushes", 0)),
			int(wood.get("stakes", 0)), int(wood.get("wall", 0))])

	# Four cages, on their own anchors, inside the clearing.
	for index in game.camp.CAGE_POSTS.size():
		var post: Vector3 = game.camp.CAGE_POSTS[index]
		var cage := game.camp.get_node_or_null("Cage%d" % (index + 1)) as Node3D
		check(cage != null, "cage %d stands in the camp" % (index + 1))
		if cage == null:
			continue
		check(flat_range(cage.position, post) < 0.01,
			"cage %d stands on its own anchor" % (index + 1))
		check(absf(post.x) <= clear.x * 0.5
				and post.z >= game.camp.YARD_FRONT and post.z <= game.camp.YARD_BACK,
			"cage %d's anchor is inside the pocket" % (index + 1))
	check(game.camp.get_node_or_null("ColdAltar") != null, "the cold altar stands behind the cages")
	check(game.camp.get_node_or_null("CampDressing") != null, "the camp's dressing is built")
	# Torches in the clearing and along the trail: one night, one fire vocabulary.
	check((game.trail.forest.get("torches", []) as Array).size() >= 40,
		"the trail carries its torch line (%d)" % (game.trail.forest.get("torches", []) as Array).size())
	# The way out is a gap in the trees, and the road is a long run of ordinary wood
	# past it - the distance is the camp's own number, so the two cannot drift.
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var road_gap := flat_range(lane[0], game.camp.GATE_POINT)
	check(road_gap >= 150.0 and road_gap <= 210.0,
		"the road stands %.0f m of wood off the camp's mouth" % road_gap)
	check(absf(road_gap - game.camp.CAMP_TO_ROAD_METRES) < 1.0,
		"which is the camp's own CAMP_TO_ROAD_METRES (%.0f)" % game.camp.CAMP_TO_ROAD_METRES)
	check(road_gap >= 150.0, "nothing of the road is in sight of the cages")
	var corridor: Array = game.camp.clearing.get("corridor", [])
	check(corridor.size() >= 8, "the way out is a corridor cut through the trees (%d gaps)"
		% corridor.size())
	check(int(game.camp.MOUTH_HALF_WIDTH) * 2 >= 8,
		"the gap is walkable (%d m)" % (int(game.camp.MOUTH_HALF_WIDTH) * 2))
	# The warband's enemies are the wood's mobs: the camp's watchers are on the
	# field before the first latch, the road's cultists are down the lane, the
	# briar wolves hold the way between them and the quartermaster's warcamps are
	# in the deep wood - one list for all four.
	var camp_guards: int = game.camp.guards.size()
	check(camp_guards == 2, "two watchers hold the camp (%d)" % camp_guards)
	var warcamps: int = game.watcher_warren.total() if game.watcher_warren != null else 0
	check(game.guards.size() == camp_guards + 20 + TrailScript.ARCHER_COUNT + wolves + warcamps,
		"twenty cultists, %d wolves and %d warcamp wardens join them on the same hostile"
			% [wolves, warcamps] + " list (%d in all)" % game.guards.size())
	for watcher in game.camp.guards:
		check(is_equal_approx(float(watcher.max_health), float(game.camp.PAIR_LESSON_HEALTH)),
			"the pair Corvin fights carry the lesson's thin pool (%s)" % str(watcher.max_health))
		check(watcher.global_position.y > -1.0, "the watcher stands on the ground")


# --- 2b. the ground -------------------------------------------------------

## One heightfield under the whole strip: the camp pocket and the town square
## padded flat into it, and the walk between them rolling over real slopes. The
## world used to lie on a single flat box; this is what replaced it.
func check_ground() -> void:
	var readout: Dictionary = game.stats()
	var low := float(readout["height_min"])
	var high := float(readout["height_max"])
	check(int(readout["terrain_tris"]) >= 20000,
		"the ground is one heightfield (%d triangles)" % int(readout["terrain_tris"]))
	check(high - low >= 2.0, "the wood rises and falls (%.1f .. %.1f m)" % [low, high])
	# The cages are scattered through the pocket, so each one stands on the ground
	# at its own anchor: a cage that floats or sinks is a body in the wood, not a
	# prisoner in a cage.
	for index in game.camp.CAGE_POSTS.size():
		var post: Vector3 = game.camp.CAGE_POSTS[index]
		var cage := game.camp.get_node_or_null("Cage%d" % (index + 1)) as Node3D
		check(cage != null, "cage %d stands in the camp" % (index + 1))
		if cage == null:
			continue
		var ground := TerrainScript.height_at(post.x, post.z)
		check(absf(cage.global_position.y - ground) < 0.05,
			"cage %d sits on the ground it was planted on (%.3f vs %.3f)"
				% [index + 1, cage.global_position.y, ground])
	# ... and so does the square.
	var centre: Vector3 = game.town.global_position
	var corner: Variant = null
	for offset in [Vector3(-12.0, 0.0, -9.0), Vector3(12.0, 0.0, -9.0),
			Vector3(-12.0, 0.0, 9.0), Vector3(12.0, 0.0, 9.0)]:
		var height := TerrainScript.height_at(centre.x + offset.x, centre.z + offset.z)
		if corner == null:
			corner = height
		check(absf(height - float(corner)) < 0.01,
			"the square is level (%.3f m)" % height)
	# The walk between them is not: the trail goes over the wood's own ground.
	var low_walk := INF
	var high_walk := -INF
	for point in game.trail.forest["lane"]:
		var height := TerrainScript.height_at(point.x, point.z)
		low_walk = minf(low_walk, height)
		high_walk = maxf(high_walk, height)
	check(high_walk - low_walk >= 1.0,
		"the walk between them goes over real slopes (%.1f m of relief)" % (high_walk - low_walk))
	print("WORLD_GROUND relief=%.1f..%.1f walk=%.1f..%.1f tris=%d"
		% [low, high, low_walk, high_walk, int(readout["terrain_tris"])])


# --- 3. the lesson ---------------------------------------------------------

func check_lesson() -> void:
	dismiss_card("the opening")
	check(game.camp.sequencer.state() == SequencerScript.State.CAGED,
		"the opening wakes the player in a cage")
	check(game.camp.sequencer.objective() == "Cut your latch",
		"with one thing to do (%s)" % game.camp.sequencer.objective())
	check(game.camp.sequencer.hint().contains("G"), "and the key that does it")
	check(game.camp.cages_open_count() == 0, "the cages are all shut")
	check(game.camp.caged_ids.size() == 5, "five bodies are held (%d)" % game.camp.caged_ids.size())
	check(game.camp.pickups().size() == 3 + 1 + game.camp.STARTING_BANDAGES,
		"three cultist weapons, the camp's shiv and five dressings lie on the dirt (%d)"
		% game.camp.pickups().size())
	check(game.tips != null and game.tips.has_shown(game.camp.TIP_CAGE),
		"and the first key was named as a tip over the crosshair")

	# A caged body cannot leave its cage: the clamp is what holds it, not a script.
	var merc_id: int = game.controller.merc_for_peer(1)
	var actor = game.controller.body_of(merc_id)
	var anchor: Vector3 = game.camp.cage_anchor_for(merc_id)
	actor.global_position = anchor + Vector3(6.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	check(flat_range(actor.global_position, anchor) <= 1.2,
		"a caged body is snapped back inside its cage (%.2f m)"
		% flat_range(actor.global_position, anchor))

	# Every out-of-order beat is refused on the live opening.
	check(not game.camp.sequencer.note_cage_opened(9), "a cage that does not exist is never booked")
	check(not game.camp.sequencer.note_cage_opened(-1), "nor a negative one")
	check(not game.camp.sequencer.note_looked_around(),
		"the bearings beat cannot start before the cage is open")
	check(not game.camp.sequencer.note_guard_killed(), "a guard death before the fight is not progress")
	check(not game.camp.sequencer.note_weapon_looted(), "loot before the cage is open is not progress")
	check(not game.camp.sequencer.note_escaped(), "and the escape cannot happen from a cage")
	check(game.camp.sequencer.cages_opened() == 0, "nothing was booked on the live opening")

	# Out of the cage: the player's own latch, bare-handed, on one press.
	check(not game.camp.holds_blade(actor), "the player wakes with empty hands")
	check(game.camp.latch_target(actor) == game.camp.OWN_CAGE,
		"and its own latch is the one in reach (%d)" % game.camp.latch_target(actor))
	game._try_interact()
	check(game.camp.cages_open_count() == 1, "G opens the player's own cage (%d)"
		% game.camp.cages_open_count())
	check(game.camp.sequencer.state() == SequencerScript.State.LOOSE,
		"and the opening moves out into the camp (%s)" % game.camp.sequencer.state_name())
	check(not game.camp.is_cage_clamped(merc_id), "the clamp is gone from the player's body")
	check(game.tips.has_shown(game.camp.TIP_WALK), "the walk was named")

	# Bearings: the beat ends on the freed body stepping away from its own cage.
	actor.global_position = game.camp.CAGE_POSTS[game.camp.OWN_CAGE] + Vector3(0.0, 0.2, -7.0)
	await physics_frame
	await physics_frame
	check(game.camp.sequencer.state() == SequencerScript.State.FREEING,
		"stepping out carries it to the objective (%s)" % game.camp.sequencer.state_name())
	check(game.camp.duel.step() == DuelScript.Step.MOVE,
		"and the first fight's lesson is at the feet (%s)" % game.camp.duel.step_name())
	var opening_prompt: String = game.camp.prompt_line(actor)
	check(opening_prompt.contains("warband 1/5"),
		"the prompt carries the objective's count (%s)" % opening_prompt)

	# A body at another cage with bare hands is told what is missing, and opens
	# nothing: only the wretch's own cell gives up to a nail.
	var other_cage: Vector3 = game.camp.CAGE_POSTS[game.camp.OWN_CAGE + 1]
	actor.global_position = other_cage + Vector3(0.0, 0.2, 2.6)
	await physics_frame
	game._try_interact()
	check(game.camp.cages_open_count() == 1, "G with bare hands opens no other cage")
	var bare_status = game.hud.get("_status_label")
	check(bare_status != null
			and str(bare_status.text).contains("Nothing to cut the latch with"),
		"the HUD says what is missing")
	check(game.camp.sequencer.state() == SequencerScript.State.FREEING,
		"and the objective stays where it was")

	# The camp's only blade is on the dirt: walk onto it, take it, and the pair wake.
	actor.global_position = game.camp.SHIV_POST + Vector3(0.0, 0.35, 2.0)
	await physics_frame
	await physics_frame
	check(game.camp.duel.step() == DuelScript.Step.FETCH,
		"standing over the blade asks for the pickup (%s)" % game.camp.duel.step_name())
	check(game.tips.has_shown(game.camp.TIP_BLADE), "the pickup was named")
	game._try_loot()
	check(game.camp.holds_blade(actor), "and the ironwood shiv is in the player's hands")
	check(game.camp.duel.step() == DuelScript.Step.FIGHT,
		"the fight starts on the frame the blade is taken (%s)" % game.camp.duel.step_name())
	check(game.tips.has_shown(game.camp.TIP_SWING), "the cuts were named")
	check(not paused, "none of it held the game still")
	var pair_woke := await await_condition(
		func() -> bool:
			for watcher in game.camp.guards:
				if is_instance_valid(watcher) and bool(watcher.hunting()):
					return true
			return false, 8.0, "the pair waking")
	check(pair_woke, "the pair wake on the body that took the blade")
	dismiss_card("the pair waking")
	# This regression is about the world around the fight: the melee itself is
	# `cage_escape_regression`'s, and the pair fall through the same damage path a
	# landed swing ends in.
	for watcher in game.camp.guards.duplicate():
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(1000.0, 0)
	await physics_frame
	check(game.camp.watchers_down() == 2, "the pair are down (%d)" % game.camp.watchers_down())
	check(game.camp.sequencer.guards_down() == 2,
		"both kills count on the tally (%d)" % game.camp.sequencer.guards_down())
	check(game.camp.cages_open_count() == 1, "the pair falling cuts nothing by itself")

	# The player walks to each shut cage and cuts one latch per press. Only the
	# last one puts the warband on its feet.
	var shut: Array[int] = []
	for index in game.camp.CAGE_POSTS.size():
		if index != game.camp.OWN_CAGE:
			shut.append(index)
	for step in shut.size():
		var index: int = shut[step]
		var post: Vector3 = game.camp.CAGE_POSTS[index]
		actor.global_position = Vector3(post.x, 0.2, post.z + 2.6)
		await physics_frame
		game._try_interact()
		check(game.camp.cages_open_count() == step + 2,
			"latch %d is cut one cage at a time (%d)" % [index + 1, game.camp.cages_open_count()])
		if step < shut.size() - 1:
			check(game.camp.sequencer.state() == SequencerScript.State.FREEING,
				"and the warband is not loose at %d of 5 (%s)"
				% [step + 2, game.camp.sequencer.state_name()])
	check(game.camp.cages_open(), "every latch is cut")
	check(state_count(SequencerScript.State.WARBAND) == 1, "WARBAND is entered exactly once")
	check(game.camp.sequencer.state() == SequencerScript.State.WARBAND,
		"the last latch puts five bodies on their feet (%s)" % game.camp.sequencer.state_name())
	for index in game.camp.caged_ids.size():
		check(not game.camp.is_cage_clamped(int(game.camp.caged_ids[index])),
			"cage %d stopped clamping its prisoner" % (index + 1))
	check(game.camp.sequencer.objective() == "Run to the town",
		"the objective turns over to the road (%s)" % game.camp.sequencer.objective())
	check(game.tips.has_shown(game.camp.TIP_RUN), "and the run was named")
	check(game.camp._run_marker != null and game.camp._run_marker.visible,
		"the gold arrow stands over the gap in the trees")
	check(game.squad.following, "the freed warband follows the soul round the camp")

	# The freed squad arms itself off the ground - silently, with no loot step.
	var armed := await await_condition(
		func() -> bool: return game.camp.allies_armed() >= 1, 16.0, "the squad arming")
	check(armed, "a freed ally picks a weapon off the ground and holds it")
	var fallen_pair := 0
	for watcher in game.camp.guards:
		if is_instance_valid(watcher) and not bool(watcher.get("alive")):
			fallen_pair += 1
	check(game.camp.pickups().size() == 3 + 1 + game.camp.STARTING_BANDAGES + fallen_pair,
		"three drops, the shiv, the altar's five dressings and one blade per fallen watcher lie where they were (%d for %d fallen)"
		% [game.camp.pickups().size(), fallen_pair])


# --- 3b. the leaving is the ambush ---------------------------------------

## ESCAPING is not a body count: it is the soul walking out of the clearing. The
## ground from the cages to the mouth is walked here, timed, and the six come out
## of the trees on the frame the mouth is crossed.
func check_leaving() -> void:
	# The cage bars are solid now: give the cut latches their 1.2 s lift before
	# driving a body through a door that is still coming up.
	await create_timer(1.4).timeout
	dismiss_card("the latches")
	var local = game.controller.active_body(1)
	check(local != null, "the soul still has a body for the walk out")
	# The cage bars are solid, so the driven body has to walk round the cage line
	# instead of straight through it. A player sees the bars and steps around; the
	# test follows the clear spine through the gap beside the soul's cage.
	var side_x := -5.1 if local.global_position.x < 0.0 else 5.1
	var route: Array[Vector3] = [
		Vector3(side_x, 0.0, 9.0),
		Vector3(side_x, 0.0, 3.2),
		Vector3(0.0, 0.0, 1.0),
		game.camp.GATE_POINT,
	]
	var route_index := 0
	# The campaign's walk starts at the cage line the soul woke on. The ground
	# between there and the mouth is covered by the opening itself - Corvin's run
	# at the pair, then the walk out - so it is banked here and the lane's metres
	# are added on top: one walk from the cages to the square, not two halves.
	opening_metres = flat_range(local.global_position,
		game.camp.CAGE_POSTS[game.camp.OWN_CAGE])
	check(game.camp.guards.size() == 2,
		"the camp holds no more watchers than the pair (%d)" % game.camp.guards.size())
	check(game.camp.sequencer.state() == SequencerScript.State.WARBAND,
		"the camp is held, not escaped (%s)" % game.camp.sequencer.state_name())
	game.controller.input_enabled = false
	await physics_frame
	var ticks := 0
	var last: Vector3 = local.global_position
	var mouth_started := Time.get_ticks_msec()
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = WALK_SCALE
	var mouth_stall := 0
	while ticks < 3000:
		if game.camp.sequencer.state() == SequencerScript.State.ESCAPING:
			break
		var target: Vector3 = route[mini(route_index, route.size() - 1)]
		var to: Vector3 = target - local.global_position
		to.y = 0.0
		if to.length() <= 0.9:
			if route_index >= route.size() - 1:
				break
			route_index += 1
			continue
		var direction := to.normalized()
		local.accept_network_input(Vector2(direction.x, direction.z), true)
		await physics_frame
		ticks += 1
		var step := flat_range(last, local.global_position)
		opening_metres += step
		last = local.global_position
		# A body that cannot move is a broken world, not a long walk: fail fast.
		if step < 0.01:
			mouth_stall += 1
			if mouth_stall > 240:
				print("WORLD_STALL mouth walk stuck at %s" % str(local.global_position))
				break
		else:
			mouth_stall = 0
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - mouth_started) / 1000.0
	var game_seconds := float(ticks) / 60.0
	check(game.camp.sequencer.state() == SequencerScript.State.ESCAPING,
		"walking out through the gap in the trees is the escape (%s)" % game.camp.sequencer.state_name())
	check(state_count(SequencerScript.State.ESCAPING) == 1, "ESCAPING is entered exactly once")
	check(game.camp.sequencer.guards_down() == 2,
		"the escape is not a kill quota: only Corvin's pair are down (%d)"
		% game.camp.sequencer.guards_down())
	check(game.camp.sequencer.hint().contains("trail"),
		"the escape's key line names the trail (%s)" % game.camp.sequencer.hint())
	check(game.squad.following, "the squad turns escort the moment the trees answer")
	print("WORLD_OPENING metres=%.0f game_seconds=%.1f real_seconds=%.1f"
		% [opening_metres, game_seconds, real_seconds])

	# Six armed watchers out of the trees on that frame.
	var expected_guards: int = 2 + CampScript.AMBUSH_COUNT
	check(game.camp.guards.size() == expected_guards,
		"the ambush comes out of the trees (%d camp watchers of %d)" % [game.camp.guards.size(), expected_guards])
	await create_timer(0.6).timeout
	dismiss_card("the ambush")
	var armed_reinforcements := 0
	var visible_blades := 0
	for index in range(2, game.camp.guards.size()):
		var watcher = game.camp.guards[index]
		check(bool(watcher.get("alive")), "reinforcement %d is on its feet" % index)
		if str(watcher.weapon_item) in ["club_makeshift", "dagger_ironwood",
				"branch_heavy", "bow_twig"]:
			armed_reinforcements += 1
		if watcher.has_weapon_visual():
			visible_blades += 1
		check(watcher.global_position.y > -1.0,
			"reinforcement %d did not fall out of the world (y=%.2f)"
			% [index, watcher.global_position.y])
	check(armed_reinforcements == CampScript.AMBUSH_COUNT,
		"every reinforcement carries a weapon (%d)" % armed_reinforcements)
	check(visible_blades == CampScript.AMBUSH_COUNT,
		"and the blade is in its hand (%d)" % visible_blades)
	# The camp's pair plus the ambush, plus the road's twenty and the wolves on the
	# way out, plus the three warcamps the quartermaster's bounty points at: one
	# list for the whole wood, so a watcher in the camp, a wolf on the corridor, a
	# cultist on the lane and a warden in a warcamp are the same system.
	var warren: int = game.watcher_warren.total() if game.watcher_warren != null else 0
	var expected_hostiles: int = 2 + CampScript.AMBUSH_COUNT + 20 + TrailScript.ARCHER_COUNT + wolves + warren
	check(game.guards.size() == expected_hostiles,
		"the world's hostile list holds all %d (%d)" % [expected_hostiles, game.guards.size()])



# --- 4. walk the whole world ----------------------------------------------

## The proof that there is no travel scene any more: one body, driven with real
## movement, from where the opening leaves it - past the gap in the trees, with the
## ambush the whole opening warned about on its heels - down the
## trail and into the town square, with the scene, the flow and the walkable floor
## watched the whole way. The ground the opening itself walks is added in, so the
## distance the docs quote is the campaign's, not this half of it.
func check_walk() -> void:
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var path = game.trail.forest["path"]
	var town_gate: Vector3 = game.trail.town_gate()
	var town_at: Vector3 = game.town.global_position
	var half := float(game.trail.forest["width"]) * 0.5
	var body = game.controller.active_body(1)
	check(body != null, "the soul still has a body for the walk")
	# Clear the road first: the walk proves the ground, not the fight. The camp's
	# ambush is the opening's own fight and is cleared with it, and the band on the
	# way out is cleared with them: a live band would decide the run instead of
	# measuring it.
	for watcher in game.trail.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	for watcher in game.camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	if game.wilderness != null:
		for wolf in game.wilderness.wolves():
			if is_instance_valid(wolf) and bool(wolf.get("alive")):
				wolf.take_damage(4000.0, 0)
	await create_timer(0.4).timeout
	# A one-time lesson may have opened after the field went quiet (the bandage
	# card is the usual one); a paused tree would read as a body that cannot walk.
	dismiss_card("the wound card")
	check(game.trail.cultists_alive() == 0, "the trail can be cleared (%d left)"
		% game.trail.cultists_alive())
	check(game.loot.corpse_ids().size() >= game.trail.guards.size(),
		"every cultist is a lootable corpse (%d registered for %d bodies)"
		% [game.loot.corpse_ids().size(), game.trail.guards.size()])

	# No teleport: the body is where the ambush left it, and it walks on from there.
	check(flat_range(body.global_position, game.camp.GATE_POINT) <= game.camp.ESCAPE_RADIUS + 1.0,
		"the walk begins at the mouth the ambush opened (%.1f m)"
		% flat_range(body.global_position, game.camp.GATE_POINT))
	game.controller.input_enabled = false
	await physics_frame

	# Follow the road itself instead of the polyline's own corners: a body steered
	# at a 45 m waypoint cuts the inside of every bend, and on a lane this long the
	# cut reaches the tree row. Sampling the path every few metres keeps the body on the
	# line the torches mark, which is the line the lateral assertion is about.
	var waypoints: Array[Vector3] = []
	var along := 6.0
	while along < float(path.total):
		var sample: Dictionary = path.sample(along)
		waypoints.append((sample["position"] as Vector3) + Vector3(0.0, 0.2, 0.0))
		along += 6.0
	waypoints.append(town_gate + Vector3(0.0, 0.2, 0.0))
	waypoints.append(Vector3(town_at.x, 0.2, town_at.z))

	var transitions_before: int = flow.transitions
	var scene_before = current_scene
	var previous := flat_range(body.global_position, town_at)
	var travelled := 0.0
	var last: Vector3 = body.global_position
	var off_ground := 0
	var worst_lateral := 0.0
	var ticks := 0
	var started := Time.get_ticks_msec()
	var index := 0
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = WALK_SCALE
	var walk_stall := 0
	while index < waypoints.size() and ticks < 30000:
		var to: Vector3 = waypoints[index] - body.global_position
		to.y = 0.0
		if to.length() <= 1.6:
			index += 1
			continue
		var direction := to.normalized()
		body.accept_network_input(Vector2(direction.x, direction.z), true)
		await physics_frame
		ticks += 1
		var step := flat_range(last, body.global_position)
		travelled += step
		last = body.global_position
		if step < 0.01:
			walk_stall += 1
			if walk_stall > 300:
				print("WORLD_STALL world walk stuck at %s waypoint %d" % [
					str(body.global_position), index])
				break
		else:
			walk_stall = 0
		# Lateral drift is a claim about the lane, so it is measured on the lane:
		# the clearing and the square are wide open by design.
		if body.global_position.z < lane[0].z - 1.0 and body.global_position.z > lane[lane.size() - 1].z + 1.0:
			var lateral: float = path.distance_to(Vector2(body.global_position.x, body.global_position.z))
			worst_lateral = maxf(worst_lateral, lateral)
		if not _walkable(body.global_position, path, half, town_at):
			off_ground += 1
		if bool(body.get("downed")) or not bool(body.get("alive")):
			break
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var game_seconds := float(ticks) / 60.0

	check(flow.transitions == transitions_before,
		"walking the whole world made no transition (%d -> %d)"
		% [transitions_before, flow.transitions])
	check(current_scene == scene_before, "the scene object never changed during the walk")
	check(game.is_inside_tree(), "the world is still the scene the body walked in")
	check(requested.is_empty(), "no scene was requested by walking (%s)" % str(requested))
	check(off_ground == 0, "the body never left the walkable ground (%d ticks off)" % off_ground)
	check(worst_lateral <= half + 0.6,
		"the body never left the %.1f m trail (%.2f m off centre)" % [half * 2.0, worst_lateral])
	check(flat_range(body.global_position, town_at) <= 3.0,
		"the body reached the town square (%.2f m from the fire)"
		% flat_range(body.global_position, town_at))
	check(real_seconds < WALK_LIMIT, "the walk finished inside the watchdog (%.1f s real)" % real_seconds)
	# The squad is an escort, not a decoration: a body left wedged on a trunk
	# somewhere in a kilometre and a third of wood is a squad the player loses for
	# the rest of the run. Half of the free allies must still be walking with the
	# soul, and none may be dead.
	var soul_id: int = int(game.controller.merc_for_peer(1))
	var free_allies := 0
	var alive_allies := 0
	var farthest := 0.0
	var report: Array[String] = []
	for merc_id in game.squad_ids:
		if int(merc_id) == soul_id:
			continue
		var ally = game.controller.body_of(int(merc_id))
		if ally == null or not is_instance_valid(ally):
			continue
		free_allies += 1
		if bool(ally.get("alive")):
			alive_allies += 1
		var gap: float = flat_range(ally.global_position, body.global_position)
		farthest = maxf(farthest, gap)
		report.append("%s %.0f m" % [warband.roster.name_of(int(merc_id)), gap])
	check(free_allies >= 2, "the walk had a squad to lose (%d allies)" % free_allies)
	check(alive_allies == free_allies,
		"every ally walked out of the wood on his feet (%d of %d)" % [alive_allies, free_allies])
	# A soul that sprints the whole 1,575 m without ever stopping is faster than an
	# escort, and the squad is allowed to trail it - the trail's own regression is
	# where "they arrive and stand beside you" is proved (`escape_run_regression`
	# waits at the end of a stretch and requires three within 20 m). What this walk
	# proves is that nobody is *lost*: a body left wedged in the camp when the soul
	# reaches the gate is a body the player never gets back, and the difference
	# between "trailing" and "abandoned" is the whole point.
	check(farthest < 700.0, "no ally is stranded in the wood (%s)" % ", ".join(report))
	# The campaign's walk is the opening's ground plus the wood plus the lane's, and
	# the same body walks all of it.
	check(travelled >= 850.0, "the trail half of the walk is a real one (%.0f m of ground)"
		% travelled)
	check(opening_metres + travelled >= 900.0,
		"the campaign is one walk from the cages to the square (%.0f m)"
		% (opening_metres + travelled))
	check(game.town.in_square(body), "the body stands on the square's own ground")
	# The prompt counts the trail down on the way and names the town at the end.
	check(game.prompt_text().begins_with("REACH THE TOWN") or game.prompt_text().is_empty()
			or game.prompt_text().contains("G -"),
		"the prompt names the town, not a door (%s)" % game.prompt_text())
	print("WORLD_WALK game_seconds=%.1f real_seconds=%.1f ticks=%d metres=%.0f opening=%.0f lateral=%.2f"
		% [game_seconds, real_seconds, ticks, travelled, opening_metres, worst_lateral])


## Whether a point is on ground a body is meant to stand on: the clearing, the
## lane's walkable band, the camp's own wood (the pocket and the corridor to the
## road), the approach road, or the square itself.
func _walkable(point: Vector3, path, half: float, town_at: Vector3) -> bool:
	if absf(point.x) <= game.camp.YARD_HALF_WIDTH + 1.0 \
			and point.z >= game.camp.YARD_FRONT - 1.5 and point.z <= game.camp.YARD_BACK + 1.0:
		return true
	# The camp's wood: pocket, corridor and the band the layout measured. A body is
	# meant to stand in all of it - the trees near the camp are the only obstacles.
	var band: Rect2 = game.camp.clearing.get("band", Rect2())
	if band.size.x > 0.0 and point.x >= band.position.x - 1.0 \
			and point.x <= band.end.x + 1.0 and point.z >= band.position.y - 1.0 \
			and point.z <= band.end.y + 1.0:
		return true
	if path.distance_to(Vector2(point.x, point.z)) <= half + 0.55:
		return true
	if absf(point.x) <= game.town.NORTH_GATE_HALF + 2.0 \
			and point.z <= game.trail.town_gate().z + 1.0 and point.z >= town_at.z + 1.0:
		return true
	return absf(point.x) <= game.town.WALL_RADIUS + 1.0 \
		and absf(point.z - town_at.z) <= game.town.WALL_RADIUS + 1.0


# --- 5. the town end -------------------------------------------------------

func check_town_end() -> void:
	var body = game.controller.active_body(1)
	check(body != null, "the body is standing in the square")
	check(is_instance_valid(game.stash_chest), "the stash chest stands in the square")
	check(is_instance_valid(game.recruiter_desk), "the recruiter desk stands in the square")
	check(game.altar != null and game.altar.has_method("interact"), "the altar is the shared object")
	check(game.gate != null, "the expedition gate stands in the square")
	check(is_instance_valid(game.quartermaster), "the quartermaster's counter is real")

	# Each counter answers G from where the body stands - and the answer is the
	# object itself, not a message.
	for service in ["stash", "altar", "recruiter", "quartermaster"]:
		var point: Vector3 = game.service_point(service)
		body.global_position = point + Vector3(1.2, 0.1, 1.2)
		await create_timer(0.15).timeout
		check(game.service_at(body.global_position) == service,
			"the %s counter resolves from where the body stands" % service)
		var answered: String = game.interact_at(1, body.global_position)
		check(answered == service, "G at the %s opens it (got '%s')" % [service, answered])
		# A keeper with something to say says it as one line and gets out of the
		# way: the counter opens on the same press, and nothing is read on top of
		# it. There is no modal to dismiss and nothing to spam-skip.
		check(game._panel_open(), "the %s counter opens on the same press" % service)
		check(not paused, "and the game keeps running behind it (%s)" % service)
		game._hide_panels()
		await create_timer(0.1).timeout
	check(not game._panel_open(), "the panels close again")

	# The one door left: the expedition gate asks for the arena, exactly once.
	var paths: Array[String] = []
	game.gate.scene_requested.connect(func(path: String) -> void: paths.append(path))
	var gate_at: Vector3 = game.service_point("gate")
	body.global_position = gate_at + Vector3(0.0, 0.1, 0.0)
	await create_timer(0.2).timeout
	var standing: Dictionary = game.gate.prompt(1)
	check(bool(standing.get("ok", false)), "a body under the arch opens the gate")
	var ids: Array[int] = warband.merc_ids()
	var line: Array[int] = []
	for index in mini(3, ids.size()):
		line.append(int(ids[index]))
	flow.active = false
	var launch: Dictionary = game.gate.deploy_and_launch(line)
	check(bool(launch.get("ok", false)), "the gate launches the marked line")
	check(paths.size() == 1 and paths[0] == "res://admin_arena.tscn",
		"the gate asks for the arena and nothing else (%s)" % str(paths))
	flow.active = true


# --- 6. the budget ---------------------------------------------------------

func check_budget() -> void:
	var readout: Dictionary = game.stats()
	var nodes := int(readout["nodes"])
	var draws := int(readout["draws"])
	var shapes := int(readout["shapes"])
	var lights := int(readout["lights"])
	# One world is one scene: a camp in a 170 m wood, a kilometre and a third of
	# trail, the four cages and three warcamps the orders point at, a square and
	# fifty-odd watchers all in one tree. The caps follow what the deep wood and the
	# road actually cost - a deep band batched into multimeshes, trunk colliders only
	# in the rows a body can walk up to - and the readout below is the measured
	# number, so a regression that starts creeping can be narrowed from it.
	check(nodes <= 26000, "the world stays inside its node budget (%d)" % nodes)
	check(draws <= 800, "the world stays inside its draw budget (%d multimesh)" % draws)
	check(shapes <= 1400, "the world stays inside its collision budget (%d shapes)" % shapes)
	# The route is marked by fire now: a pair of torches every eighteen metres down
	# a kilometre and a third of wood, and that is the design, not creep. The
	# warcamps' braziers and the town's own lanterns share the same ceiling.
	check(lights <= 210, "the world stays inside its light budget (%d)" % lights)
	var warren: int = game.watcher_warren.total() if game.watcher_warren != null else 0
	var hostiles: int = 2 + CampScript.AMBUSH_COUNT + 20 + TrailScript.ARCHER_COUNT + wolves + warren
	check(int(readout["guards"]) == hostiles,
		"all %d hostiles are on the list (%d)" % [hostiles, int(readout["guards"])])
	# The wood is a kilometre and a third of lane now: a band, not a number, so a
	# waypoint can be nudged without a test about the art failing.
	check(float(readout["lane_length"]) >= 1250.0 and float(readout["lane_length"]) <= 1500.0,
		"the trail is a long run (%.1f m)" % float(readout["lane_length"]))
	print("WORLD_BUDGET nodes=%d draws=%d meshes=%d lights=%d shapes=%d guards=%d"
		% [nodes, draws, int(readout["meshes"]), lights, shapes, int(readout["guards"])])


# --- 7. the one door -------------------------------------------------------

func check_doors() -> void:
	check(flow.WORLD_SCENE == WORLD, "the flow's campaign scene is the world (%s)" % flow.WORLD_SCENE)
	# The arena was written against the old town scene and is not ours to change:
	# the flow has to map that path to the world's town end.
	check(ArenaScript.TOWN_SCENE == flow.ARENA_RETURN,
		"the field's return path is the one the flow maps (%s)" % ArenaScript.TOWN_SCENE)
	flow.active = true
	flow.world_start = "camp"
	flow._on_scene_requested(ArenaScript.TOWN_SCENE)
	check(flow.world_start == "town", "the field's return lands at the world's town end (%s)" % flow.world_start)
	flow.active = false
	flow.world_start = "camp"
