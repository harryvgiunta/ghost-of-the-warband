extends SceneTree
## The one world: camp, trail and town in a single coordinate space.
##
## This regression is the campaign's spine. It proves the things the old chain of
## three scenes could not:
##
##   1. **One of everything.** The world owns exactly one `PossessionController`,
##      one camera, one `WarbandHud` and one tutorial card, and its three areas
##      adopt them instead of building their own.
##   2. **The camp is in the trees.** The clearing carries a treeline and
##      undergrowth on every side, a broken stake fence where the palisade stood,
##      the four cages with their own anchors, and 60 x 68 m of open ground - more
##      than the 45 x 40 m a six-watcher fight and a squad need.
##   3. **The lesson still works.** CAGED -> ALL_SEEN -> Corvin kills the pair ->
##      F5 -> all four latches at once -> the squad out and armed -> walking out
##      of the mouth is ESCAPING and the six come out of the trees, with every
##      out-of-order beat refused and no key opening a cage.
##   4. **Walking is the only travel.** A real body is driven out of the clearing,
##      down the 286 m trail and into the town square: no scene is requested, no
##      transition is made, the scene object never changes, the body never leaves
##      the walkable ground, and the walk is timed.
##   5. **The town end is the town.** The stash, the altar, the recruiter and the
##      quartermaster answer `G` from where the body stands, and the expedition
##      gate is the campaign's one remaining door.
##   6. **The budget.** One world is one scene: nodes, multimesh draws, lights and
##      collision shapes are counted and bounded.

const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const ArenaScript = preload("res://scripts/admin_arena.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

const TEST_SAVE := "user://warband_world_state.json"
const WARBAND_SAVE := "user://warband_world_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## The rescuer's walk and his fight have to happen inside this.
const JOG_TIMEOUT := 16.0
## How long the shiv may take to put the pair down before the test calls it a hang.
const PAIR_TIMEOUT := 40.0
## How long the driven walk may take before the test calls it a hang.
const WALK_LIMIT := 90.0
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
	await check_lesson()
	await check_leaving()
	await check_walk()
	await check_town_end()
	check_budget()
	check_doors()

	_finish()


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


func state_count(value: int) -> int:
	var total := 0
	for entry in state_log:
		if int(entry[0]) == value:
			total += 1
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
	var cameras := 0
	for node in game.find_children("*", "Camera3D", true, false):
		if (node as Camera3D).current:
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
	check(final_keys.contains("walk"), "the last card tells the player to walk")


# --- 2. the camp is in the trees -------------------------------------------

func check_camp_in_the_woods() -> void:
	var wood: Dictionary = game.camp.clearing
	check(int(wood.get("trees", 0)) >= 120, "the treeline surrounds the clearing (%d trees)"
		% int(wood.get("trees", 0)))
	check(int(wood.get("bushes", 0)) >= 80, "undergrowth fills the verge (%d bushes)"
		% int(wood.get("bushes", 0)))
	check(int(wood.get("stakes", 0)) >= 150, "the broken fence is stakes, not a wall (%d)"
		% int(wood.get("stakes", 0)))
	check(int(wood.get("wall", 0)) >= 5, "the wood behind the trunks is solid (%d wall runs)"
		% int(wood.get("wall", 0)))
	# The old palisade is gone as a room: no continuous four-sided wall of timber.
	var clear: Vector2 = game.clearing_size()
	check(clear.x >= 45.0 and clear.y >= 40.0,
		"the clearing fits six watchers and a squad (%.0f x %.0f m)" % [clear.x, clear.y])
	check(clear.x <= 70.0 and clear.y <= 80.0,
		"the clearing is still a clearing, not a field (%.0f x %.0f m)" % [clear.x, clear.y])
	print("WORLD_CLEARING size=%.0fx%.0f trees=%d bushes=%d stakes=%d wall=%d"
		% [clear.x, clear.y, int(wood.get("trees", 0)), int(wood.get("bushes", 0)),
			int(wood.get("stakes", 0)), int(wood.get("wall", 0))])

	# Four cages, on their own anchors, inside the clearing.
	for index in game.camp.CAGE_POSTS.size():
		var post: Vector3 = game.camp.CAGE_POSTS[index]
		var cage := game.camp.get_node_or_null("Cage%d" % (index + 1)) as Node3D
		check(cage != null, "cage %d stands in the clearing" % (index + 1))
		if cage == null:
			continue
		check(flat_range(cage.position, post) < 0.01,
			"cage %d stands on its own anchor" % (index + 1))
		check(absf(post.x) <= clear.x * 0.5 and post.z >= -clear.y * 0.5 + game.camp.YARD_FRONT
				+ 42.0 - 0.5,
			"cage %d's anchor is inside the clearing" % (index + 1))
	check(game.camp.get_node_or_null("ColdAltar") != null, "the cold altar stands behind the cages")
	check(game.camp.get_node_or_null("CampDressing") != null, "the camp's dressing is built")
	# Torches in the clearing and along the trail: one night, one fire vocabulary.
	check((game.trail.forest.get("torches", []) as Array).size() >= 40,
		"the trail carries its torch line (%d)" % (game.trail.forest.get("torches", []) as Array).size())
	# The mouth is open: the fence stops at it and the trail's first waypoint is
	# exactly there, with no wall between the two.
	var lane: PackedVector3Array = game.trail.forest["lane"]
	check(flat_range(lane[0], game.camp.GATE_POINT) < 0.01,
		"the trail begins at the clearing's mouth (%.1f m off)" % flat_range(lane[0], game.camp.GATE_POINT))
	check(int(game.camp.MOUTH_HALF_WIDTH) * 2 >= 11,
		"the mouth is at least the lane's width (%d m)" % (int(game.camp.MOUTH_HALF_WIDTH) * 2))
	# The warband's enemies are the wood's mobs: the camp's watchers are on the
	# field before the first latch and the road's cultists are down the lane.
	var camp_guards: int = game.camp.guards.size()
	check(camp_guards == 2, "two watchers hold the clearing (%d)" % camp_guards)
	check(game.guards.size() == camp_guards + 80,
		"eighty cultists hold the trail and are on the same hostile list (%d in all)"
		% game.guards.size())
	for watcher in game.camp.guards:
		check(is_equal_approx(float(watcher.max_health), 72.0),
			"the camp watcher carries 72 health (%s)" % str(watcher.max_health))
		check(watcher.global_position.y > -1.0, "the watcher stands on the ground")


# --- 3. the lesson ---------------------------------------------------------

func check_lesson() -> void:
	dismiss_card("the opening card")
	check(game.camp.sequencer.state() == SequencerScript.State.CAGED, "the lesson opens caged")
	check(game.camp.sequencer.seen_count() == 1, "the starting body counts as seen")
	check(game.camp.sequencer.objective().contains("1/4"), "the objective counts the seen bodies")
	check(not game.camp.cages_open(), "the cages are still shut")
	check(game.camp.pickups().size() == 3, "three cultist weapons lie on the walk (%d)"
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

	# Every out-of-order beat is refused.
	check(not game.camp.sequencer.note_cage_opened(0), "a latch is refused before the rescuer arrives")
	check(not game.camp.sequencer.note_rescuer_arrived(), "the rescuer cannot arrive before all four seen")
	check(not game.camp.sequencer.note_guard_killed(), "a guard death before the fight is not progress")
	check(not game.camp.sequencer.note_weapon_looted(), "loot before the cages open is not progress")
	check(not game.camp.sequencer.note_body_entered(0), "a non-body never counts as a prisoner")

	# All four seen, in a scrambled order: the lesson must not depend on F1..F4.
	var ids: Array = game.camp.caged_ids
	for index in ids.size():
		game.controller.direct(1, int(ids[(index + 2) % ids.size()]))
	check(game.camp.sequencer.seen_count() == 4, "all four prisoners were seen")
	check(game.camp.sequencer.state() == SequencerScript.State.ALL_SEEN,
		"the fourth possession advances to ALL_SEEN (%s)" % game.camp.sequencer.state_name())
	check(state_count(SequencerScript.State.ALL_SEEN) == 1, "ALL_SEEN is entered exactly once")
	dismiss_card("all four seen")

	# Corvin jogs in, and he does not stand there: the pair are his. The soul is
	# NOT moved for the player - taking his body is the beat.
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
	dismiss_card("the rescuer's card")

	# `G` is not a latch key any more: a body at the bars opens nothing.
	var first_cage: Vector3 = game.camp.CAGE_POSTS[0]
	var prisoner = game.controller.body_of(int(ids[2]))
	prisoner.global_position = first_cage + Vector3(0.0, 0.1, 0.3)
	await physics_frame
	game._try_interact()
	check(game.camp.cages_open_count() == 0, "G does not open a cage")
	check(game.camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		"and the lesson stays where it was")

	# Corvin puts the pair down himself. The player is in a cage for all of it.
	var pair := await await_condition(
		func() -> bool: return game.camp.watchers_down() >= 2, PAIR_TIMEOUT, "the pair falling")
	check(pair, "Corvin puts both watchers down himself (%d of 2)" % game.camp.watchers_down())
	check(game.camp.ally_engaged(), "he swung: the squad's own module landed the blows")
	check(game.camp.sequencer.guards_down() == 2,
		"his two kills count on the tally (%d)" % game.camp.sequencer.guards_down())
	check(game.controller.merc_for_peer(1) != game.camp.rescuer_id,
		"the player never had to touch them")
	check(game.camp.cages_open_count() == 0, "the pair falling cuts nothing by itself")

	# The soul takes the body - F5 in the game, `direct` here - and that is the
	# latch beat: all four at once, and the squad out.
	var take: Dictionary = game.controller.direct(1, game.camp.rescuer_id)
	check(bool(take.get("ok", false)), "the rescuer's body can be entered")
	check(game.camp.sequencer.rescuer_taken(), "the sequencer saw the player take the body")
	check(game.camp.cages_open_count() == 4,
		"taking him cuts all four latches at once (%d)" % game.camp.cages_open_count())
	check(game.camp.cages_open(), "all four latches are cut")
	check(state_count(SequencerScript.State.FREED) == 1, "FREED is entered exactly once")
	check(game.camp.sequencer.state() == SequencerScript.State.FREED,
		"the fourth latch frees the squad (%s)" % game.camp.sequencer.state_name())
	for index in ids.size():
		check(not game.camp.is_cage_clamped(int(ids[index])),
			"cage %d stopped clamping its prisoner" % (index + 1))
	check(game.camp.sequencer.objective().contains("2/8"),
		"the tally reads true against the eight (%s)" % game.camp.sequencer.objective())
	dismiss_card("the freed card")

	# The freed squad arms itself off the ground - silently, with no loot step.
	var armed := await await_condition(
		func() -> bool: return game.camp.allies_armed() >= 1, 16.0, "the squad arming")
	check(armed, "a freed ally picks a weapon off the ground and holds it")
	check(game.camp.pickups().size() == 3, "the three cultist drops lie where they were (%d)"
		% game.camp.pickups().size())


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
		"the clearing holds no more watchers than the pair (%d)" % game.camp.guards.size())
	check(game.camp.sequencer.state() == SequencerScript.State.FREED,
		"the clearing is held, not escaped (%s)" % game.camp.sequencer.state_name())
	game.controller.input_enabled = false
	await physics_frame
	var ticks := 0
	var last: Vector3 = local.global_position
	var mouth_started := Time.get_ticks_msec()
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = WALK_SCALE
	while ticks < 9000:
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
		opening_metres += flat_range(last, local.global_position)
		last = local.global_position
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - mouth_started) / 1000.0
	var game_seconds := float(ticks) / 60.0
	check(game.camp.sequencer.state() == SequencerScript.State.ESCAPING,
		"walking out through the mouth is the escape (%s)" % game.camp.sequencer.state_name())
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
	check(game.camp.guards.size() == 8, "six more watchers come out of the trees (%d camp watchers)"
		% game.camp.guards.size())
	await create_timer(0.6).timeout
	dismiss_card("the ambush")
	var armed_reinforcements := 0
	var visible_blades := 0
	for index in range(2, game.camp.guards.size()):
		var watcher = game.camp.guards[index]
		check(bool(watcher.get("alive")), "reinforcement %d is on its feet" % index)
		if str(watcher.weapon_item) in ["sword_short", "dagger_iron", "sword_arming"]:
			armed_reinforcements += 1
		if watcher.has_weapon_visual():
			visible_blades += 1
		check(watcher.global_position.y > -1.0,
			"reinforcement %d did not fall out of the world (y=%.2f)"
			% [index, watcher.global_position.y])
	check(armed_reinforcements == 6, "every reinforcement carries a weapon (%d)" % armed_reinforcements)
	check(visible_blades == 6, "and the blade is in its hand (%d)" % visible_blades)
	check(game.guards.size() == 88, "the world's hostile list holds all eighty-eight (%d)" % game.guards.size())



# --- 4. walk the whole world ----------------------------------------------

## The proof that there is no travel scene any more: one body, driven with real
## movement, from where the opening leaves it - the wrong side of the clearing's
## mouth, with the ambush the whole opening warned about on its heels - down the
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
			watcher.take_damage(400.0, 0)
	for watcher in game.camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(400.0, 0)
	await create_timer(0.4).timeout
	check(game.trail.cultists_alive() == 0, "the trail can be cleared (%d left)"
		% game.trail.cultists_alive())
	check(game.trail.pickups_left() + game.camp.steel_taken() >= 8,
		"every cultist dropped the weapon it held (%d on the ground, %d taken)"
		% [game.trail.pickups_left(), game.camp.steel_taken()])

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
	Engine.time_scale = WALK_SCALE
	while index < waypoints.size() and ticks < 30000:
		var to: Vector3 = waypoints[index] - body.global_position
		to.y = 0.0
		if to.length() <= 1.6:
			index += 1
			continue
		var direction := to.normalized()
		body.accept_network_input(Vector2(direction.x, direction.z), false)
		await physics_frame
		ticks += 1
		travelled += flat_range(last, body.global_position)
		last = body.global_position
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
	# The campaign's walk is the opening's ground plus the lane's: the cages to the
	# mouth is the first 50 m of it, and it is walked by the same body.
	check(travelled >= 300.0, "the trail half of the walk is a real one (%.0f m of ground)"
		% travelled)
	check(opening_metres + travelled >= 350.0,
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
## lane's walkable band, the approach road, or the square itself.
func _walkable(point: Vector3, path, half: float, town_at: Vector3) -> bool:
	if absf(point.x) <= game.camp.YARD_HALF_WIDTH + 1.0 \
			and point.z >= game.camp.YARD_FRONT - 1.5 and point.z <= game.camp.YARD_BACK + 1.0:
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
	# One world is one scene: 60 x 68 m of clearing, 286 m of trail, a square and
	# eighty-eight watchers all in one tree. These are the numbers it holds itself to.
	# The node cap carries the cult: a watcher is a body and a rig, so eighty extra
	# of them cost nodes without costing draw calls - draws stay flat at 323.
	check(nodes <= 4900, "the world stays inside its node budget (%d)" % nodes)
	check(draws <= 420, "the world stays inside its draw budget (%d multimesh)" % draws)
	check(shapes <= 900, "the world stays inside its collision budget (%d shapes)" % shapes)
	check(lights <= 110, "the world stays inside its light budget (%d)" % lights)
	check(int(readout["guards"]) == 88, "all eighty-eight watchers are on the list (%d)" % int(readout["guards"]))
	check(float(readout["lane_length"]) >= 240.0 and float(readout["lane_length"]) <= 300.0,
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
