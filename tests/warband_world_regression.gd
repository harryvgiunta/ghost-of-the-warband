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
const DuelScript = preload("res://scripts/warband/duel_lesson.gd")
const ArenaScript = preload("res://scripts/admin_arena.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

const TEST_SAVE := "user://warband_world_state.json"
const WARBAND_SAVE := "user://warband_world_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## The rescuer's walk and his fight have to happen inside this.
const JOG_TIMEOUT := 16.0
## How long the shiv may take to put the pair down before the test calls it a hang.
const PAIR_TIMEOUT := 40.0
## How long the driven walk may take before the test calls it a hang.
const WALK_LIMIT := 200.0
## The walk is played at three times the simulation per second so a quarter of a
## kilometre fits in a regression; the recorded time is game time at 1x.
const WALK_SCALE := 3.0
## Where the campaign's walk begins: the cage line the soul wakes on.
const CAGE_LINE := Vector3(-2.6, 0.2, 6.0)

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


## The tutorial card is modal and pauses the tree. A test plays the player: if a
## card is up, it must be pausing, and closing it must resume.
func dismiss_card(label: String) -> void:
	if game == null or game.card == null or not game.card.is_open():
		return
	check(paused, "the card holds the game still (%s)" % label)
	check(not game.card.step().is_empty(), "the card names its step (%s)" % label)
	game.card.close()
	check(not paused, "closing the card resumes the game (%s)" % label)


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
	check(nodes_named("TutorialCard") == 1,
		"exactly one tutorial card exists (%d)" % nodes_named("TutorialCard"))
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
	check(game.camp.card == game.card, "the areas share the world's one tutorial card")
	check(game.camp.squad == game.squad,
		"the camp drives the world's one squad module, not a copy")
	check(game.bodies.size() == 5, "five bodies stand in the camp (%d)" % game.bodies.size())
	check(warband.roster.count() == 5, "five mercenaries are sworn (%d)" % warband.roster.count())
	var local = game.controller.active_body(1)
	check(local != null, "the local soul starts inside a body")
	check(game.camp.caged_ids.has(game.controller.merc_for_peer(1)),
		"the soul starts in one of the four prisoners")
	# The tutorial machine ends in the escape: there is no TOWN beat.
	check(SequencerScript.state_name_of(SequencerScript.State.ESCAPING) == "escaping",
		"the escape is the tutorial's last state")
	check(SequencerScript.state_name_of(SequencerScript.State.ESCAPING + 1) == "unknown",
		"the state machine stops at the escape - there is no town state")
	var final_card: String = str(game.camp.STEP_CARDS[4]["body"]).to_lower()
	check(final_card.contains("trail"), "the last card says the trail through the wood is the way out")
	check(not final_card.contains("arch"), "the last card promises no arch")
	var final_keys: String = str(game.camp.STEP_CARDS[4]["keys"]).to_lower()
	check(final_keys.contains("run") or final_keys.contains("walk"),
		"the last card tells the player to move through the wood")


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
	# field before the first latch and the road's cultists are down the lane.
	var camp_guards: int = game.camp.guards.size()
	check(camp_guards == 2, "two watchers hold the camp (%d)" % camp_guards)
	check(game.guards.size() == camp_guards + 20,
		"twenty cultists hold the trail and are on the same hostile list (%d in all)"
		% game.guards.size())
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
	# The cage line stands level: four cages on one pad, no step between them.
	var first := TerrainScript.height_at(game.camp.CAGE_POSTS[0].x, game.camp.CAGE_POSTS[0].z)
	for post in game.camp.CAGE_POSTS:
		var height := TerrainScript.height_at(post.x, post.z)
		check(absf(height - first) < 0.01,
			"the cages stand level with each other (%.3f m vs %.3f)" % [height, first])
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
	dismiss_card("the opening card")
	check(game.camp.sequencer.state() == SequencerScript.State.CAGED, "the lesson opens caged")
	check(game.camp.sequencer.seen_count() == 1, "the starting body counts as seen")
	check(game.camp.sequencer.objective().contains("1/4"), "the objective counts the seen bodies")
	check(not game.camp.cages_open(), "the cages are still shut")
	check(game.camp.pickups().size() == 4,
		"three cultist weapons and the rescuer's shiv lie on the walk (%d)"
		% game.camp.pickups().size())

	# A caged soul cannot leave its cage: possession moves the soul, not the bars.
	var merc_id: int = game.controller.merc_for_peer(1)
	var actor = game.controller.body_of(merc_id)
	var anchor: Vector3 = game.camp.cage_anchor_for(merc_id)
	actor.global_position = anchor + Vector3(6.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	check(flat_range(actor.global_position, anchor) <= 1.2,
		"a caged body is snapped back inside its cage (%.2f m)"
		% flat_range(actor.global_position, anchor))

	# Every out-of-order beat is refused. A cage that does not exist is never booked,
	# and the live lesson starts with no latch on it at all - the early-latch guard
	# itself is measured on a scratch machine in the cage regression.
	check(not game.camp.sequencer.note_cage_opened(9), "a cage that does not exist is never booked")
	check(not game.camp.sequencer.note_rescuer_arrived(), "the rescuer cannot arrive before all four seen")
	check(not game.camp.sequencer.note_guard_killed(), "a guard death before the fight is not progress")
	check(not game.camp.sequencer.note_weapon_looted(), "loot before the cages open is not progress")
	check(not game.camp.sequencer.note_body_entered(0), "a non-body never counts as a prisoner")
	check(game.camp.sequencer.cages_opened() == 0, "and no latch was booked on the live lesson")

	# All four seen, in a scrambled order: the lesson must not depend on F1..F4.
	var ids: Array = game.camp.caged_ids
	for index in ids.size():
		game.controller.direct(1, int(ids[(index + 2) % ids.size()]))
	check(game.camp.sequencer.seen_count() == 4, "all four prisoners were seen")
	check(game.camp.sequencer.state() == SequencerScript.State.ALL_SEEN,
		"the fourth possession advances to ALL_SEEN (%s)" % game.camp.sequencer.state_name())
	check(state_count(SequencerScript.State.ALL_SEEN) == 1, "ALL_SEEN is entered exactly once")
	dismiss_card("all four seen")

	# Corvin jogs in with empty hands and stops at the cage line: the pair are the
	# player's fight now, not his. The soul is NOT moved for the player - taking his
	# body is the beat.
	var arrived := await await_condition(
		func() -> bool: return game.camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		JOG_TIMEOUT, "the rescuer's walk")
	check(arrived, "the rescuer walked to the cages (%s)" % game.camp.sequencer.state_name())
	check(state_count(SequencerScript.State.RESCUER_ARRIVED) == 1,
		"RESCUER_ARRIVED is entered exactly once")
	check(game.controller.merc_for_peer(1) != game.camp.rescuer_id,
		"the soul is NOT moved into the rescuer for the player")
	check(not game.camp.sequencer.rescuer_taken(), "the rescuer has not been taken yet")
	check(game.camp.cages_open_count() == 0, "no latch is cut for free")
	check(game.camp.sequencer.objective().contains("F5"), "the objective names the key")
	var walked_in = game.controller.body_of(game.camp.rescuer_id)
	check(not game.camp.holds_blade(walked_in),
		"the rescuer walked in with nothing in his hands")
	var sleeping := 0
	for watcher in game.camp.guards:
		if is_instance_valid(watcher) and bool(watcher.hunting()):
			sleeping += 1
	check(sleeping == 0, "nothing hunts before the player is armed (%d hunting)" % sleeping)
	dismiss_card("the rescuer's card")

	# A body at the bars with bare hands is told what is missing, and opens nothing.
	var first_cage: Vector3 = game.camp.CAGE_POSTS[0]
	var prisoner = game.controller.body_of(int(ids[2]))
	prisoner.global_position = first_cage + Vector3(0.0, 0.1, 2.4)
	await physics_frame
	check(not game.camp.holds_blade(prisoner), "the prisoner has nothing in its hands")
	game._try_interact()
	check(game.camp.cages_open_count() == 0, "G with bare hands opens no cage")
	var bare_status = game.hud.get("_status_label")
	check(bare_status != null
			and str(bare_status.text).contains("Nothing to cut the latch with"),
		"the HUD says what is missing")
	check(game.camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		"and the lesson stays where it was")

	# The first fight is the player's: take the body, walk to the shiv, take it, and
	# put the pair down. This regression is about the world around that fight, so
	# the melee itself is left to `cage_escape_regression` and the pair fall through
	# the same damage path a landed swing ends in.
	var take: Dictionary = game.controller.direct(1, game.camp.rescuer_id)
	check(bool(take.get("ok", false)), "the rescuer's body can be entered")
	check(game.camp.sequencer.rescuer_taken(), "the sequencer saw the player take the body")
	check(game.camp.cages_open_count() == 0, "taking him cuts no latch by itself")
	check(game.camp.duel.step() == DuelScript.Step.MOVE,
		"taking him starts the first fight's lesson at the feet (%s)"
		% game.camp.duel.step_name())
	dismiss_card("the walking card")
	var cutter = game.controller.active_body(1)
	check(not game.camp.holds_blade(cutter), "his hands are empty until the shiv is taken")
	cutter.global_position = game.camp.SHIV_POST + Vector3(0.0, 0.35, 2.0)
	await physics_frame
	await physics_frame
	check(game.camp.duel.step() == DuelScript.Step.FETCH,
		"standing over the shiv asks for the pickup (%s)" % game.camp.duel.step_name())
	dismiss_card("the pickup card")
	game._try_loot()
	check(game.camp.holds_blade(cutter), "and the shiv is in the player's hands")
	check(game.card != null and game.card.is_open() and game.card.step() == "step_5",
		"and taking it holds the game still for the cuts card (%s)"
		% ("" if game.card == null else game.card.step()))
	dismiss_card("the cuts card")
	var pair_woke := await await_condition(
		func() -> bool:
			for watcher in game.camp.guards:
				if is_instance_valid(watcher) and bool(watcher.hunting()):
					return true
			return false, 8.0, "the pair waking")
	check(pair_woke, "the pair wake on the body that took the shiv")
	dismiss_card("the pair waking")
	for watcher in game.camp.guards.duplicate():
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(1000.0, 0)
	await physics_frame
	check(game.camp.watchers_down() == 2, "the pair are down (%d)" % game.camp.watchers_down())
	check(game.camp.sequencer.guards_down() == 2,
		"both kills count on the tally (%d)" % game.camp.sequencer.guards_down())
	check(game.camp.cages_open_count() == 0, "the pair falling cuts nothing by itself")

	# The player walks the cage line cutting one latch per press. Only the fourth
	# frees the squad.
	for index in game.camp.CAGE_POSTS.size():
		var post: Vector3 = game.camp.CAGE_POSTS[index]
		cutter.global_position = Vector3(post.x, 0.2, post.z + 2.6)
		await physics_frame
		game._try_interact()
		check(game.camp.cages_open_count() == index + 1,
			"latch %d is cut one cage at a time (%d)" % [index + 1, game.camp.cages_open_count()])
		if index < game.camp.CAGE_POSTS.size() - 1:
			check(game.camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
				"and the squad is not loose at %d of 4 (%s)"
				% [index + 1, game.camp.sequencer.state_name()])
	check(game.camp.cages_open(), "all four latches are cut")
	check(state_count(SequencerScript.State.FREED) == 1, "FREED is entered exactly once")
	check(game.camp.sequencer.state() == SequencerScript.State.FREED,
		"the fourth latch frees the squad (%s)" % game.camp.sequencer.state_name())
	for index in ids.size():
		check(not game.camp.is_cage_clamped(int(ids[index])),
			"cage %d stopped clamping its prisoner" % (index + 1))
	check(game.camp.sequencer.objective().contains("2/%d" % SequencerScript.GUARD_COUNT),
		"the tally reads true against the camp (%s)" % game.camp.sequencer.objective())
	dismiss_card("the freed card")

	# The freed squad arms itself off the ground - silently, with no loot step.
	var armed := await await_condition(
		func() -> bool: return game.camp.allies_armed() >= 1, 16.0, "the squad arming")
	check(armed, "a freed ally picks a weapon off the ground and holds it")
	# The three cultist drops are still there, plus a blade for each of the pair
	# Corvin put down: a fallen watcher's steel leaves its hand and lands on the
	# dirt beside it.
	var fallen_pair := 0
	for watcher in game.camp.guards:
		if is_instance_valid(watcher) and not bool(watcher.get("alive")):
			fallen_pair += 1
	check(game.camp.pickups().size() == 4 + fallen_pair,
		"three drops, the shiv and one blade per fallen watcher lie where they were (%d for %d fallen)"
		% [game.camp.pickups().size(), fallen_pair])


# --- 3b. the leaving is the ambush ---------------------------------------

## ESCAPING is not a body count: it is the soul walking out of the clearing. The
## ground from the cages to the mouth is walked here, timed, and the six come out
## of the trees on the frame the mouth is crossed.
func check_leaving() -> void:
	var local = game.controller.active_body(1)
	check(local != null, "the soul still has a body for the walk out")
	# The campaign's walk starts at the cage line the soul woke on. The ground
	# between there and the mouth is covered by the opening itself - Corvin's run
	# at the pair, then the walk out - so it is banked here and the lane's metres
	# are added on top: one walk from the cages to the square, not two halves.
	opening_metres = flat_range(local.global_position, CAGE_LINE)
	check(game.camp.guards.size() == 2,
		"the camp holds no more watchers than the pair (%d)" % game.camp.guards.size())
	check(game.camp.sequencer.state() == SequencerScript.State.FREED,
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
		var to: Vector3 = game.camp.GATE_POINT - local.global_position
		to.y = 0.0
		if to.length() <= 0.8:
			break
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
	# The camp's pair plus the ambush, plus the road's twenty: one list for the whole
	# wood, so a watcher in the camp and a cultist on the lane are the same system.
	var expected_hostiles: int = 2 + CampScript.AMBUSH_COUNT + 20
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
	# ambush is the opening's own fight and is cleared with it.
	for watcher in game.trail.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	for watcher in game.camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	await create_timer(0.4).timeout
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

	var waypoints: Array[Vector3] = []
	for index in range(1, lane.size()):
		waypoints.append(lane[index])
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
		check(game._panel_open(), "the %s panel is open" % service)
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
	# One world is one scene: a camp in a 170 m wood, 915 m of trail, a square and
	# twenty-eight watchers all in one tree. The caps follow what the deep wood and
	# the road actually cost - a deep band batched into multimeshes, trunk colliders
	# only in the rows a body can walk up to - and the readout below is the measured
	# number, so a regression that starts creeping can be narrowed from it.
	check(nodes <= 26000, "the world stays inside its node budget (%d)" % nodes)
	check(draws <= 800, "the world stays inside its draw budget (%d multimesh)" % draws)
	check(shapes <= 1400, "the world stays inside its collision budget (%d shapes)" % shapes)
	# The route is marked by fire now: a pair of torches every twelve metres is 152
	# lights down nine hundred metres of wood, and that is the design, not creep.
	check(lights <= 210, "the world stays inside its light budget (%d)" % lights)
	var hostiles: int = 2 + CampScript.AMBUSH_COUNT + 20
	check(int(readout["guards"]) == hostiles,
		"all %d watchers are on the list (%d)" % [hostiles, int(readout["guards"])])
	check(float(readout["lane_length"]) >= 860.0 and float(readout["lane_length"]) <= 980.0,
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
