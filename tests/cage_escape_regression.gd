extends SceneTree
## GHOST OF THE WARBAND: the opening, end to end, on the real world.
##
## The camp is the first quarter of one continuous world and this regression owns
## the lesson inside it. The player wakes inside the first of five prisoners, shut
## in its own cage: five bodies, five latches and no blade in anybody's hands. The
## first latch is cut bare-handed (`G`) - a nail and a padlock - which opens that
## cage and turns the sequencer to LOOSE. Stepping out past `BEARINGS_RADIUS` is
## getting your bearings, and that is where the first fight's lesson
## (`duel_lesson.gd`) starts at MOVE: walk to the ironwood shiv on the dirt at the
## altar, take it with `K` (the frame the blade enters the hand is the frame the
## cuts are named and the pair wake), and hold `RMB` on the second watcher's
## windup. The pair then fall to the player's own steel, and the four remaining
## cages are cut with `G` one at a time - each needs a blade, and bare hands are
## told so. The fifth latch puts five bodies on their feet: WARBAND, run to the
## town, over the gold arrow at the gap in the trees. Walking into that gap is the
## leaving, and the wood answers it with four armed watchers. Only the pair and
## the ambush down is the opening cleared.
##
## Nothing here is written in a paragraph any more. The whole opening is eight
## one-line tips, each one a key and a command, and every beat below asserts the
## tree is never paused and no tip is left standing where the old card would have
## been. Every out-of-order event is fired at the machine first: a latch that does
## not exist, opening the same cage twice, a cage cut with bare hands. None of
## them may advance a state or throw.

const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const DuelScript = preload("res://scripts/warband/duel_lesson.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

const TEST_SAVE := "user://cage_escape_state.json"
const WARBAND_SAVE := "user://cage_escape_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## The naked base set every prisoner in this camp is dressed in.
const NAKED_SLOTS := ["head", "chest", "hands", "legs", "feet"]
## The makeshift tier, and the only steel in this wood.
const MAKESHIFT := ["club_makeshift", "dagger_ironwood", "branch_heavy", "bow_twig"]

var game
var camp
var warband
var state
var checks := 0
var failures := 0
var state_log: Array = []
var _phase_start := 0
var requested_paths: Array = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CAGE_FAIL  ", message)

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
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "camp"

	# A scene script that fails to parse would otherwise leave this coroutine
	# parked forever; the watchdog turns that hang into a failing run.
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	# The gate walk plays at 3x, and a Timer counts scaled time.
	watchdog.wait_time = 240.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	_phase_start = Time.get_ticks_msec()
	game = load(WORLD).instantiate()
	root.add_child(game)
	if not game.has_method("stats"):
		check(false, "the world scene loaded without its script")
		_finish()
		return
	camp = game.camp
	var built := await _wait_until(
		func() -> bool: return camp != null and camp.sequencer != null, 30.0)
	if not built:
		check(false, "the camp's opening never started on a new campaign")
		_finish()
		return
	camp.sequencer.state_changed.connect(_on_state_changed)
	game.scene_requested.connect(_on_scene_requested)
	print("CAGE_PHASE built %d ms" % (Time.get_ticks_msec() - _phase_start))

	_phase_start = Time.get_ticks_msec()
	check_spawn()
	check_tips_copy()
	await check_clamp()
	await check_own_latch()
	await check_refusals()
	await check_bearings()
	print("CAGE_PHASE caged %d ms" % (Time.get_ticks_msec() - _phase_start))

	_phase_start = Time.get_ticks_msec()
	await check_blade()
	await check_guard()
	print("CAGE_PHASE first fight %d ms" % (Time.get_ticks_msec() - _phase_start))

	_phase_start = Time.get_ticks_msec()
	await check_latches()
	await check_walk_out()
	print("CAGE_PHASE latches %d ms" % (Time.get_ticks_msec() - _phase_start))

	_phase_start = Time.get_ticks_msec()
	await check_revive_lesson()
	await check_escape()
	print("CAGE_PHASE leaving %d ms" % (Time.get_ticks_msec() - _phase_start))

	check(is_instance_valid(game) and game.is_inside_tree(),
		"the player stays in the world when nothing was requested")
	check(requested_paths.is_empty(), "the camp never asks for a scene (%s)" % str(requested_paths))
	_finish()

func _on_watchdog() -> void:
	check(false, "the opening did not finish inside the watchdog")
	_finish()

func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	Damage.reset()
	var flow = root.get_node("GameFlow")
	flow.world_start = "camp"
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("CAGE_ESCAPE_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _on_state_changed(new_state: int, objective: String) -> void:
	state_log.append([new_state, objective])

func _on_scene_requested(path: String) -> void:
	requested_paths.append(path)

## How many times the machine *entered* `value`. A state is announced again
## whenever a counter changes while it is held (a latch, a corpse, a pickup), so a
## bare tally would count bookkeeping as transitions.
func state_count(value: int) -> int:
	var total := 0
	var previous := -1
	for entry in state_log:
		var current := int(entry[0])
		if current == value and previous != value:
			total += 1
		previous = current
	return total

## The opening never holds the game still and never leaves a line standing: a tip
## fades on its own after `WarbandTips.HOLD`. Where the old lesson would have put
## a card up, this is what is asserted instead - call `clear_tips()` first when the
## beat's own tip is legitimately still inside its hold.
func check_no_prose(label: String) -> void:
	check(not paused, "the game is never held still (%s)" % label)
	check(not game.tips.showing(), "and no tip is left standing (%s)" % label)

## Put the hint line down so the next frames are clean. A tip is a fading line,
## not a modal: dropping it early only skips the rest of its hold.
func clear_tips() -> void:
	if game != null and game.tips != null:
		game.tips.visible = false

## Deterministic wait: a frame budget at the fixed 60 Hz the test runs at, never a
## wall clock. Returns whether the predicate came true.
func _wait_until(predicate: Callable, timeout: float = 2.0) -> bool:
	var frames := int(maxf(1.0, timeout) * 60.0)
	while frames > 0:
		if bool(predicate.call()):
			return true
		await physics_frame
		frames -= 1
	return bool(predicate.call())

func flat_range(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()

## Whether any node in the tree under `node` carries `wanted` as its name.
func _has_node_named(node: Node, wanted: String) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if str(node.name) == wanted:
		return true
	for child in node.get_children():
		if _has_node_named(child, wanted):
			return true
	return false

# --- spawn -----------------------------------------------------------------

func check_spawn() -> void:
	check(not paused, "the opening starts unpaused")
	check(warband.roster.count() == 5, "the camp seeds five mercenaries (%d)" % warband.roster.count())
	check(game.bodies.size() == 5, "five bodies spawned (%d)" % game.bodies.size())
	check(camp.caged_ids.size() == 5, "all five prisoners are held (%d)" % camp.caged_ids.size())
	check(camp.caged_ids.size() == camp.CAGE_COUNT,
		"one body per cage (%d ids, %d cages)" % [camp.caged_ids.size(), camp.CAGE_COUNT])
	check(game.controller == camp.controller, "the camp runs on the world's one controller")
	var soul_id: int = int(game.controller.merc_for_peer(1))
	check(soul_id == int(camp.caged_ids[camp.OWN_CAGE]),
		"the soul wakes inside the first of the five (%d vs %d)"
		% [soul_id, int(camp.caged_ids[camp.OWN_CAGE])])
	check(game.controller.active_body(1) != null, "the local soul starts inside a body")
	check(camp.is_cage_clamped(soul_id), "and its own cage is holding it")
	# The warband starts in the naked base set - an old shirt and tight shorts,
	# and bare head, hands and feet, all of which guard nothing - and nobody holds
	# a weapon: the camp's only blade is on the dirt.
	for merc_id in warband.roster.ids():
		var gear: Dictionary = warband.roster.equipped_of(merc_id)
		for slot in NAKED_SLOTS:
			check(str(gear.get(slot, "")) == "armor_naked_%s" % slot,
				"%s wears the naked %s (%s)" % [warband.roster.name_of(merc_id), slot,
					str(gear.get(slot, ""))])
		check(str(gear.get("main", "")).is_empty(),
			"prisoner %s is unarmed" % warband.roster.name_of(merc_id))
		check(str(gear.get("off", "")).is_empty(),
			"and has nothing in his off hand either (%s)" % warband.roster.name_of(merc_id))
	var shiv = camp.get("_shiv_pickup")
	check(shiv != null and is_instance_valid(shiv), "the ironwood shiv lies on the dirt")
	check(shiv != null and str(shiv.item_id) == camp.LESSON_SHIV,
		"and it is the shiv, not a stray club (%s)"
		% ("" if shiv == null else str(shiv.item_id)))
	if shiv != null and is_instance_valid(shiv):
		check(flat_range((shiv as Node3D).global_position, camp.SHIV_POST) <= 0.5,
			"at the foot of the cold altar (%.2f m off)"
			% flat_range((shiv as Node3D).global_position, camp.SHIV_POST))
	check(camp.sequencer.state() == SequencerScript.State.CAGED,
		"the opening starts caged (%s)" % camp.sequencer.state_name())
	check(camp.sequencer.objective() == "Cut your latch",
		"the objective is the latch and nothing else (%s)" % camp.sequencer.objective())
	check(camp.sequencer.hint().contains("G"),
		"the key line names G (%s)" % camp.sequencer.hint())
	check(camp.cages_open_count() == 0,
		"no latch is open at the start (%d)" % camp.cages_open_count())
	check(camp.guards.size() == 2, "two watchers hold the clearing (%d)" % camp.guards.size())
	for watcher in camp.guards:
		check(bool(watcher.get("alive")), "a watcher stands on its feet")
		check(is_equal_approx(float(watcher.max_health), float(camp.PAIR_LESSON_HEALTH)),
			"the first fight is the thinned pair, got %s" % str(watcher.max_health))
		check(float(camp.PAIR_LESSON_HEALTH) <= WatcherScript.PAIR_HEALTH,
			"and never thicker than the camp's own thinned pool")
		check(str(watcher.name).begins_with("CampWatcher"),
			"the watcher is a camp body (%s)" % watcher.name)
		check(str(watcher.get("mob_id")) == "hollow_warden",
			"the watcher is the antlered warden body, not a ranger clone")
		check(not bool(watcher.hunting()), "and sleeps while the soul is still caged")
	check(camp.pickups().size() == 3 + 1 + camp.STARTING_BANDAGES,
		"three makeshift pieces, the shiv and five dressings lie on the walk (%d)"
			% camp.pickups().size())
	check(camp.START_BANDAGE_POSTS.size() == camp.STARTING_BANDAGES,
		"and the altar carries exactly five of them (%d)" % camp.START_BANDAGE_POSTS.size())
	check(camp.tips != null and camp.tips.has_shown(camp.TIP_CAGE),
		"the first beat's tip is the latch, offered once")
	check(not _has_node_named(game, "TutorialCard"),
		"the opening has no tutorial card node anywhere in the scene")
	for body in game.bodies:
		check(body.global_position.y > -1.0, "body %s stands on the clearing" % str(body.name))
	for watcher in camp.guards:
		check(watcher.global_position.y > -1.0, "watcher %s stands on the clearing" % str(watcher.name))
	# The way out is a gap in the trees on the camp's front line, and the road is a
	# long run of ordinary wood past it - not the other side of a hedge.
	check(is_equal_approx(camp.GATE_POINT.z, camp.YARD_FRONT),
		"the way out is on the camp's front line (%s)" % str(camp.GATE_POINT))
	check(camp.CAMP_TO_ROAD_METRES >= 150.0 and camp.CAMP_TO_ROAD_METRES <= 210.0,
		"the road stands %d m of wood off the camp" % int(camp.CAMP_TO_ROAD_METRES))
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var road_gap := flat_range(lane[0], camp.GATE_POINT)
	check(absf(road_gap - camp.CAMP_TO_ROAD_METRES) < 1.0,
		"the trail's first waypoint is that far off, and not the mouth (%.1f m)" % road_gap)
	check(road_gap >= 150.0, "no torch of the road is in sight of the cages (%.0f m)" % road_gap)

## The opening is commands, not prose. Every tip is one key line and one command
## on one line, short enough to read from the corner of the screen, and none of
## them ends a sentence: there is no sentence to end.
func check_tips_copy() -> void:
	var rows: Dictionary = camp.OPENING_TIPS
	check(rows.size() == 8, "the opening's whole script is eight tips (%d)" % rows.size())
	for id in rows:
		var row: Dictionary = rows[id]
		var keys := str(row["keys"])
		var text := str(row["text"])
		check(not keys.contains("\n") and not text.contains("\n"),
			"tip %s is one line (%s / %s)" % [str(id), keys, text])
		check(text.length() <= 48,
			"tip %s's command is short enough to read (%d chars: %s)"
			% [str(id), text.length(), text])
		check(not keys.ends_with(".") and not text.ends_with("."),
			"tip %s is a command, not a sentence (%s / %s)" % [str(id), keys, text])
		check(not keys.strip_edges().is_empty(),
			"tip %s names a key (%s)" % [str(id), keys])
	check(not _has_node_named(game, "TutorialCard"),
		"no node named TutorialCard exists under the world")

# --- the cage clamp --------------------------------------------------------

func check_clamp() -> void:
	var merc_id: int = int(camp.caged_ids[camp.OWN_CAGE])
	var actor = game.controller.body_of(merc_id)
	var anchor: Vector3 = camp.cage_anchor_for(merc_id)
	check(camp.is_cage_clamped(merc_id), "the soul's cage is clamped")
	check(flat_range(anchor, camp.CAGE_POSTS[camp.OWN_CAGE]) < 0.01,
		"and the clamp holds it at its own cage centre")
	actor.global_position = anchor + Vector3(6.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	var strayed := flat_range(actor.global_position, anchor)
	check(strayed <= float(camp.CAGE_CLAMP_RADIUS) + 0.25,
		"a caged body is snapped back inside its cage (%.2f m)" % strayed)
	check(game.controller.active_body(1) == actor, "the clamped body is still the soul's body")

# --- the player's own latch, cut bare-handed -------------------------------

func check_own_latch() -> void:
	var soul_id: int = int(game.controller.merc_for_peer(1))
	var soul = game.controller.active_body(1)
	await physics_frame
	check(camp.latch_target(soul) == camp.OWN_CAGE,
		"its own latch is in reach through the bars (%d)" % camp.latch_target(soul))
	check(not camp.holds_blade(soul), "and the body has nothing to cut it with")
	check(camp.interact(soul), "the camp consumes the press at its own cage")
	check(camp.cages_open_count() == 1,
		"the own latch is cut bare-handed (%d)" % camp.cages_open_count())
	check(camp.sequencer.is_cage_opened(camp.OWN_CAGE), "and the machine booked cage 0")
	check(not camp.is_cage_clamped(soul_id), "the own cage stops holding the soul")
	check(camp.sequencer.state() == SequencerScript.State.LOOSE,
		"opening your own cage is the first beat's end (%s)" % camp.sequencer.state_name())
	check(state_count(SequencerScript.State.LOOSE) == 1, "LOOSE is entered exactly once")
	check(camp.sequencer.objective() == "Get your bearings",
		"the objective turns over (%s)" % camp.sequencer.objective())
	check(camp.sequencer.hint().contains("W A S D"),
		"and the key line teaches walking (%s)" % camp.sequencer.hint())
	check(camp.tips.has_shown(camp.TIP_WALK), "the walk's tip is offered on that beat")

# --- order guards, and a cage that needs steel -----------------------------

## The latches that are not the player's own are cuts, and a cut needs a knife.
## The machine is asked first, while the soul is still standing in its own cage:
## a latch out of range, a negative latch, and the own cage a second time.
func check_refusals() -> void:
	var before: int = camp.sequencer.state()
	check(not camp.sequencer.note_cage_opened(9), "a cage that does not exist is never booked")
	check(not camp.sequencer.note_cage_opened(-1), "and neither is a negative index")
	check(not camp.sequencer.note_cage_opened(camp.OWN_CAGE),
		"the own latch only ever counts once")
	check(not camp.open_latch(camp.OWN_CAGE), "and re-opening cage 0 is refused outright")
	check(camp.cages_open_count() == 1, "the refusals open nothing")
	check(camp.sequencer.cages_opened() == 1, "and book nothing")
	check(camp.sequencer.state() == before, "refusals leave the state where it was")

	# A different cage, with bare hands. The nearest other cage stands 11.7 m off,
	# so this walk is also the bearings beat: one step, one press, two facts.
	var soul = game.controller.active_body(1)
	var other: int = camp.OWN_CAGE + 1
	var post: Vector3 = camp.CAGE_POSTS[other]
	soul.global_position = Vector3(post.x, 0.2, post.z + 2.6)
	var frames := 0
	while camp.sequencer.state() == SequencerScript.State.LOOSE and frames < 60:
		await process_frame
		frames += 1
	check(camp.sequencer.state() == SequencerScript.State.FREEING,
		"stepping off the cage walks the opening on (%s)" % camp.sequencer.state_name())
	check(frames <= 3, "and it does so on the frame the radius is crossed (%d)" % frames)
	check(camp.latch_target(soul) == other,
		"cage %d's latch is the one in reach (%d)" % [other + 1, camp.latch_target(soul)])
	check(not camp.holds_blade(soul), "the body still has nothing to cut with")
	check(camp.interact(soul), "the camp consumes the press at a cage it cannot cut")
	check(camp.cages_open_count() == 1, "G with bare hands opens no cage")
	var status = game.hud.get("_status_label")
	check(status != null and str(status.text).contains("Nothing to cut the latch with"),
		"and the HUD says what is missing (%s)" % ("" if status == null else str(status.text)))

## The bearings beat ends on a fact and not a timer, and the objective that
## arrives with it is the warband's - carried on the same HUD line as the first
## fight's command, because one line can hold two short facts.
func check_bearings() -> void:
	var soul = game.controller.active_body(1)
	var anchor: Vector3 = camp.CAGE_POSTS[camp.OWN_CAGE]
	check(flat_range(soul.global_position, anchor) > float(camp.BEARINGS_RADIUS),
		"the body is out past the bearings radius (%.1f m)"
		% flat_range(soul.global_position, anchor))
	check(camp.sequencer.state() == SequencerScript.State.FREEING,
		"the walk is what ends the getting-your-bearings beat (%s)"
		% camp.sequencer.state_name())
	check(state_count(SequencerScript.State.FREEING) == 1, "FREEING is entered exactly once")
	check(camp.sequencer.objective().contains("1/5"),
		"the objective counts the warband (%s)" % camp.sequencer.objective())
	check(not camp.sequencer.note_looked_around(), "and it only ever fires once")
	check(camp.duel != null, "the first fight's lesson is built with the camp")
	check(camp.duel.step() == DuelScript.Step.MOVE,
		"and starts at the feet (%s)" % camp.duel.step_name())
	var prompt := str(camp.prompt_line(soul))
	check(prompt.contains("warband 1/5"),
		"the prompt carries the warband count under the fight's command (%s)" % prompt)
	check(prompt.contains("shiv"),
		"and the command sends the player to the blade (%s)" % prompt)
	check(str(camp.hint_line(soul)).contains("W A S D"),
		"the key line teaches walking (%s)" % str(camp.hint_line(soul)))
	clear_tips()
	check_no_prose("the bearings beat")

# --- the blade, and the pair waking ----------------------------------------

## Walk onto the shiv, take it with `K`, and watch the pair wake on the blade.
## Every tip here is raised by the fight itself - a step onto the shiv, the frame
## the blade enters the hand - and none of them holds the game still.
func check_blade() -> void:
	var soul_id: int = int(game.controller.merc_for_peer(1))
	var cutter = game.controller.active_body(1)
	check(cutter != null, "the soul still has its body for the walk")
	cutter.global_position = camp.SHIV_POST + Vector3(0.0, 0.35, -1.8)
	var near := await _wait_until(
		func() -> bool: return camp.duel.step() == DuelScript.Step.FETCH, 2.0)
	check(near, "standing over the shiv asks for the pickup (%s)" % camp.duel.step_name())
	check(camp.tips.has_shown(camp.TIP_BLADE), "and names K on that beat")
	check(str(camp.duel.hint()).contains("K"),
		"the lesson's key line is the pickup (%s)" % camp.duel.hint())
	check(not bool(camp.get("_watchers_awake")),
		"the camp has not turned the pair loose on an empty-handed body")
	check(_watchers_at_posts(), "and both are still standing on their posts")
	check(not paused, "the pickup beat never pauses the tree")
	game._try_loot()
	check(str(warband.roster.equipped_of(soul_id).get("main", "")) == camp.LESSON_SHIV,
		"K puts the ironwood shiv in the main hand (%s)"
		% str(warband.roster.equipped_of(soul_id).get("main", "")))
	check(camp.holds_blade(cutter), "and the body is holding a blade")
	check(camp.duel.step() == DuelScript.Step.FIGHT,
		"taking the shiv starts the fight (%s)" % camp.duel.step_name())
	check(camp.tips.has_shown(camp.TIP_SWING), "the cuts are named on the frame of the pickup")
	check(bool(camp.duel.cuts_tip()), "and the lesson has raised them")
	var woke := await _wait_until(
		func() -> bool: return _pursuing_watchers() == camp.guards.size(), 4.0)
	check(woke, "the pair wake on the blade (%d of %d pursuing)"
		% [_pursuing_watchers(), camp.guards.size()])
	for watcher in camp.guards:
		check(watcher.get("player") == cutter,
			"and both are pointed at the body that took it (%s)" % str(watcher.name))
	clear_tips()
	check_no_prose("the cuts")

# --- the guard, taught on a raised club ------------------------------------

## The guard is taught by the fight, not by the enemy: the second of the pair to
## raise its club names `RMB`, and holding it into the blow finishes the lesson.
## Then the pair fall to the player's own clicks - the whole point of it.
func check_guard() -> void:
	var cutter = game.controller.active_body(1)
	check(cutter != null and bool(cutter.get("alive")),
		"the body the fight is taught on is standing")
	# Into the pair's own ground: they close and swing from there.
	cutter.global_position = Vector3(0.0, 0.3, -18.0)
	var up := await _wait_until(func() -> bool: return bool(camp.duel.guard_tip()), 25.0)
	check(up, "a watcher's windup teaches the guard (%s, %d hunting)"
		% [camp.duel.step_name(), _pursuing_watchers()])
	check(camp.tips.has_shown(camp.TIP_GUARD), "and the guard tip is the one it raises")
	check(camp.duel.step() == DuelScript.Step.FIGHT,
		"the guard is a tip inside the fight, not a step of its own (%s)"
		% camp.duel.step_name())
	check(not paused, "the guard beat never pauses the tree")
	for watcher in camp.guards:
		watcher.attacked.connect(_probe_attack)
	# Hold the guard and let the club come down on it. Three things a player's own
	# hands do every frame have to be done here for the guard to be a guard:
	#
	#   * a frame of input, because a body left without one holds itself still and
	#     drops its blade after 0.65 s (`ArenaActor.step`);
	#   * the press itself, repeated, because a body still taking a hit cannot
	#     raise its blade and the guard has to go back up after every stagger;
	#   * the turn onto the raised club. A guard only answers a blow it faces, and
	#     the mouse is what a player turns it with: `face_block()` is the rig's own
	#     turn, the same one `set_blocking()` makes on the press.
	var guarded := false
	var guard_frames := 0
	while guard_frames < 900:
		cutter.accept_network_input(Vector2.ZERO, false)
		if not bool(cutter.combat.blocking):
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_RIGHT
			press.pressed = true
			game.controller._mouse_press(press)
		if bool(cutter.combat.blocking):
			var club = _winding_watcher(cutter)
			if club != null:
				var to: Vector3 = (club as Node3D).global_position - (cutter as Node3D).global_position
				to.y = 0.0
				cutter.rig.face_block(to)
				# A warden winds up from the edge of its own reach and does not walk
				# the gap during it: a player answers a blow by standing in it, so the
				# body is walked onto the club's own arc here.
				var reach := float((club.get("profile") as Dictionary).get("reach", 0.0))
				if reach > 0.0 and to.length() > reach * 0.7:
					cutter.global_position = (club as Node3D).global_position \
						+ to.normalized() * reach * 0.7
		if bool(camp.duel.guarded()):
			guarded = true
			break
		var watch = _winding_watcher(cutter)
		var pre_yaw := rad_to_deg(cutter.rig.global_rotation.y)
		await physics_frame
		guard_frames += 1
		if watch != null and is_instance_valid(watch):
			print("CAGE_DBG f=%d pre_yaw=%.1f post_yaw=%.1f club=%.1f %s d=%.2f block=%s" % [
				guard_frames, pre_yaw, rad_to_deg(cutter.rig.global_rotation.y),
				rad_to_deg(atan2(-((watch as Node3D).global_position.x
					- (cutter as Node3D).global_position.x),
					-((watch as Node3D).global_position.z
					- (cutter as Node3D).global_position.z))) * -1.0,
				str(watch.get("state")),
				(watch as Node3D).global_position.distance_to((cutter as Node3D).global_position),
				str(cutter.combat.blocking)])
	check(guarded, "a blow that lands on a raised blade finishes the lesson (%s)"
		% camp.duel.step_name())
	check(camp.duel.step() == DuelScript.Step.DONE,
		"and the lesson hands the keys back (%s)" % camp.duel.step_name())
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	game.controller._mouse_release(release)
	# The pair fall to the player's own blade, thrown from the real input path,
	# with the body walked back into reach between cuts because they keep closing.
	var kills := 0
	for watcher in camp.guards.duplicate():
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		for attempt in 8:
			if not bool(watcher.get("alive")):
				break
			(cutter as Node3D).global_position = (watcher as Node3D).global_position \
				+ Vector3(0.0, 0.1, 1.0)
			await physics_frame
			await click_until_swing(cutter)
			await create_timer(0.5).timeout
		check(not bool(watcher.get("alive")),
			"the pair fall to the player's blade (%s at %.0f health)"
			% [str(watcher.name), float(watcher.get("health"))])
		kills += 1
	await physics_frame
	check(kills == 2, "both watchers were fought by the player (%d)" % kills)
	check(bool(cutter.get("alive")) and not bool(cutter.get("downed")),
		"and the player's body is still standing (%.0f health)" % float(cutter.get("health")))
	check(camp.watchers_down() == 2, "exactly the pair falls (%d)" % camp.watchers_down())
	check(camp.sequencer.guards_down() == 2,
		"both kills count on the tally (%d)" % camp.sequencer.guards_down())
	check(camp.duel.step() == DuelScript.Step.DONE,
		"the lesson is over when the pair are down (%s)" % camp.duel.step_name())
	check(camp.cages_open_count() == 1,
		"and the fight cut no latch by itself (%d)" % camp.cages_open_count())
	clear_tips()
	check_no_prose("the pair down")

func _probe_attack(attacker, amount: float, victim) -> void:
	var soul = game.controller.active_body(1)
	if victim != soul:
		return
	var to: Vector3 = (attacker as Node3D).global_position - (victim as Node3D).global_position
	to.y = 0.0
	var fwd: Vector3 = -(victim.rig.global_basis.z)
	fwd.y = 0.0
	print("CAGE_DBG hit %s amount=%.1f block=%s hp=%.0f guarded=%s def=%d melee=%s d=%.2f dot=%.2f roll=%.2f age=%.2f" % [
		str(attacker.name), amount, str(victim.combat.blocking), float(victim.get("health")),
		str(camp.duel.guarded()),
		int(victim.combat.resolve_melee_defense((attacker as Node3D).global_position)),
		str(victim.rig.is_melee()), to.length(), fwd.normalized().dot(to.normalized()),
		float(victim.rig.get("_roll_progress")), float(victim.get("input_age"))])

## The watcher that is about to land a blow: the nearest of the pair with its club
## up or coming down. This is what a player turns the guard onto.
func _winding_watcher(cutter):
	var best = null
	var best_gap := INF
	if cutter == null or not is_instance_valid(cutter):
		return null
	for watcher in camp.guards:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		if not str(watcher.get("state")) in ["WINDUP", "STRIKE"]:
			continue
		var gap: float = (watcher as Node3D).global_position.distance_to(
			(cutter as Node3D).global_position)
		if gap < best_gap:
			best_gap = gap
			best = watcher
	return best

## How many of the camp's watchers are actually pursuing: the mob's own alarm
## clocks, which only `hunt()` starts. `hunting()` is not that signal - a watcher
## the culler woke on distance answers it for standing inside sight of the body,
## without ever having been turned loose.
func _pursuing_watchers() -> int:
	var count := 0
	for watcher in camp.guards:
		if not is_instance_valid(watcher):
			continue
		var senses = watcher.get("_senses")
		if senses != null and bool(senses.aggressive()):
			count += 1
	return count

## Whether both of the pair are still standing where the camp posted them.
func _watchers_at_posts() -> bool:
	for watcher in camp.guards:
		if not is_instance_valid(watcher):
			return false
		var at: float = INF
		for spec in camp.GATE_WATCHERS:
			at = minf(at, flat_range((watcher as Node3D).global_position, spec["post"]))
		if at > 2.0:
			return false
	return true

## One left click through the real input path, retried until the body actually
## swings: a click while the body is still landing, or mid-cut, is refused by the
## combat layer and is not a failure of the lesson.
func click_until_swing(cutter) -> void:
	var budget := 240
	while budget > 0:
		if bool(cutter.combat.grounded) and bool(cutter.rig.can_begin_melee("right")):
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			game.controller._mouse_press(press)
			if bool(cutter.rig.is_melee()):
				return
		await physics_frame
		budget -= 1
	check(false, "the player's click started a cut")

# --- the four remaining latches --------------------------------------------

## One cage, one press, one latch, one door - and the fifth cut is what puts the
## squad on its feet. The first two carve the hints the rest lean on: the second
## latch names the body keys, the fifth turns the objective over to the run.
func check_latches() -> void:
	var cutter = game.controller.active_body(1)
	check(camp.holds_blade(cutter), "the shiv is in the player's hands for the latches")
	check(camp.cages_open_count() == 1,
		"only the own cage is open when the fight ends (%d)" % camp.cages_open_count())
	var audio = root.get_node_or_null("Audio")
	var doors: Array = camp.clearing.get("doors", [])
	check(doors.size() == camp.CAGE_COUNT,
		"the camp has one door per cage (%d of %d)" % [doors.size(), camp.CAGE_COUNT])
	# The ground in front of every cage has to be walkable: a latch is worked from
	# the dirt on its +z side, so no hut, stack, stake or trunk may stand there.
	for index in camp.CAGE_POSTS.size():
		var approach: Vector3 = camp.CAGE_POSTS[index]
		var blocked := _geometry_at(Vector3(approach.x, 0.9, approach.z + 2.6), 0.55)
		check(blocked.is_empty(), "cage %d's approach is clear ground (%s)"
			% [index + 1, str(blocked)])
	for index in range(camp.OWN_CAGE + 1, camp.CAGE_POSTS.size()):
		var post: Vector3 = camp.CAGE_POSTS[index]
		cutter.global_position = Vector3(post.x, 0.2, post.z + 2.6)
		await physics_frame
		check(camp.latch_target(cutter) == index,
			"cage %d's latch is the one in reach (target %d)"
			% [index + 1, camp.latch_target(cutter)])
		game._try_interact()
		check(camp.cages_open_count() == index + 1,
			"cutting cage %d books %d latches (%d)"
			% [index + 1, index + 1, camp.cages_open_count()])
		check(camp.sequencer.cages_opened() == index + 1,
			"and the sequencer counts them one by one (%d)" % camp.sequencer.cages_opened())
		check(audio == null or str(audio.last_event) == "cage_latch",
			"cutting cage %d's latch plays the lock (%s)"
			% [index + 1, "" if audio == null else str(audio.last_event)])
		var door = doors[index] if index < doors.size() else null
		var lifted := await _wait_until(
			func() -> bool: return door != null and is_instance_valid(door) \
				and float((door as Node3D).position.y) >= float(camp.CAGE_BAR_LIFT) - 0.2, 3.0)
		check(lifted, "and its door climbs out of the frame (%.2f of %.2f)"
			% [0.0 if door == null else float((door as Node3D).position.y),
				float(camp.CAGE_BAR_LIFT)])
		if camp.cages_open_count() == 2:
			check(camp.tips.has_shown(camp.TIP_BODIES),
				"the second latch is where the body keys are named")
		if camp.cages_open_count() < camp.CAGE_COUNT:
			check(camp.sequencer.state() == SequencerScript.State.FREEING,
				"%d of %d latches does not loose the squad (%s)"
				% [camp.cages_open_count(), camp.CAGE_COUNT, camp.sequencer.state_name()])
	clear_tips()
	check_no_prose("the last latch")
	check(camp.cages_open(), "every cage is open (%d)" % camp.cages_open_count())
	check(camp.sequencer.warband_free(), "and the machine says the warband is free")
	check(camp.sequencer.cages_opened() == camp.CAGE_COUNT,
		"the sequencer booked all five (%d)" % camp.sequencer.cages_opened())
	check(camp.sequencer.state() == SequencerScript.State.WARBAND,
		"the fifth latch turns the objective over (%s)" % camp.sequencer.state_name())
	check(state_count(SequencerScript.State.WARBAND) == 1, "WARBAND is entered exactly once")
	check(camp.sequencer.objective() == "Run to the town",
		"and it says where to go (%s)" % camp.sequencer.objective())
	var hint := str(camp.sequencer.hint())
	check(hint.contains("run"), "the key line names the run (%s)" % hint)
	check(hint.contains("arrow"), "and the gold arrow the player is to follow (%s)" % hint)
	var marker = camp.get("_run_marker")
	check(marker != null and is_instance_valid(marker) and bool(marker.get("visible")),
		"the arrow stands over the gap in the trees")
	if marker != null and is_instance_valid(marker):
		check(flat_range((marker as Node3D).global_position, camp.GATE_POINT) <= 0.6,
			"over the mouth itself (%.2f m off)"
			% flat_range((marker as Node3D).global_position, camp.GATE_POINT))
		check(str(marker.get_script().resource_path).ends_with("lesson_arrow.gd"),
			"and it is the lesson's arrow (%s)" % str(marker.get_script().resource_path))
	check(game.squad != null and bool(game.squad.following),
		"the freed squad escorts the soul from the first open cage, not from the leaving")
	check(camp.tips.has_shown(camp.TIP_RUN), "and the run's tip is offered on that beat")
	check(SequencerScript.GUARD_COUNT == 2 + CampScript.AMBUSH_COUNT,
		"the camp's tally counts the pair and the ambush (%d)" % SequencerScript.GUARD_COUNT)

# --- the walk out ----------------------------------------------------------

## Every latch above was cut from the +z side, behind the bars, where the latch
## arrow hangs - and a cage's only way out is its door on the -z side. A prisoner
## let out from behind its bars has its post behind them too: steering straight at
## it, it shouldered the back bars, backed out of the door, turned round and walked
## back in for as long as the soul stood there. With the soul holding still where it
## cut the last latch, every freed body has to leave through its own door and come
## to it.
func check_walk_out() -> void:
	var soul = game.controller.active_body(1)
	var last: int = camp.CAGE_POSTS.size() - 1
	var post: Vector3 = camp.CAGE_POSTS[last]
	check(soul != null and soul.global_position.z > post.z + camp.CAGE_HALF,
		"the soul stands behind the last cage it opened (%.1f m past its bars)"
		% (0.0 if soul == null else soul.global_position.z - post.z - camp.CAGE_HALF))
	var penned = game.controller.body_of(int(camp.caged_ids[last]))
	Engine.time_scale = 3.0
	var gathered := await _wait_until(func() -> bool: return _farthest_ally(soul) <= 7.0, 30.0)
	Engine.time_scale = 1.0
	check(penned != null and flat_range(penned.global_position, post) > camp.CAGE_HALF + 0.3,
		"the prisoner let out from behind its bars has left its cage (%.1f m from the centre)"
		% (0.0 if penned == null else flat_range(penned.global_position, post)))
	check(gathered, "every freed prisoner walks out of its cage to the soul (farthest %.1f m: %s)"
		% [_farthest_ally(soul), _ally_spots(soul)])


## The flat distance from the soul to the free squadmate standing farthest from it.
func _farthest_ally(soul) -> float:
	var farthest := 0.0
	for merc_id in game.squad_ids:
		var ally = game.controller.body_of(int(merc_id))
		if ally == null or ally == soul or not camp.is_free(int(merc_id)):
			continue
		farthest = maxf(farthest, flat_range(ally.global_position, soul.global_position))
	return farthest


func _ally_spots(soul) -> String:
	var spots: Array[String] = []
	for merc_id in game.squad_ids:
		var ally = game.controller.body_of(int(merc_id))
		if ally == null or ally == soul:
			continue
		spots.append("%s (%.1f, %.1f)" % [warband.roster.name_of(int(merc_id)),
			ally.global_position.x, ally.global_position.z])
	return ", ".join(spots)

# --- the fallen ------------------------------------------------------------

## A squadmate going down at the player's feet raises the one unnumbered tip:
## `HOLD G` brings a body back. This regression is the only place the prompt is
## read, and it must name both the hold and the body. The ally is stripped first
## so the drop it leaves behind is not mistaken for the lesson's own steel.
func check_revive_lesson() -> void:
	var ally_id: int = int(camp.caged_ids[2])
	check(ally_id != int(game.controller.merc_for_peer(1)),
		"the body that falls is not the body the soul is in")
	warband.roster.unequip(ally_id, "main")
	warband.roster.unequip(ally_id, "off")
	game.controller.refresh_gear(ally_id)
	var ally = game.controller.body_of(ally_id)
	var soul = game.controller.active_body(1)
	check(ally != null and soul != null, "there is a body to fall and a body to fall next to")
	ally.global_position = soul.global_position + Vector3(1.4, 0.0, 0.0)
	await physics_frame
	var floor_before: int = camp.pickups().size()
	ally.enter_downed(0)
	await physics_frame
	await physics_frame
	check(game.tips.has_shown("lesson_revive"),
		"a squadmate falling at the player's feet offers the revive lesson")
	check(camp.pickups().size() == floor_before,
		"an empty-handed body leaves nothing on the dirt (%d for %d)"
		% [camp.pickups().size(), floor_before])
	var prompt := str(game.get("_prompt_text"))
	check(prompt.to_upper().contains("HOLD G"),
		"the HUD asks for the hold over the body (%s)" % prompt)
	check(prompt.contains(warband.roster.name_of(ally_id).to_upper()),
		"and names the body that needs it (%s)" % prompt)
	check(not paused, "the revive lesson never pauses the tree")
	clear_tips()
	check_no_prose("the revive lesson")

# --- the leaving, and the ambush it calls ----------------------------------

## The mouth is not a door: walking into it is the escape, and the wood answers
## with four armed watchers. Only all six of the opening's watchers down is the
## opening cleared - the leaving itself is not a kill quota.
func check_escape() -> void:
	var soul = game.controller.active_body(1)
	check(soul != null and bool(soul.get("alive")),
		"the soul still has a standing body for the walk out")
	game.controller.input_enabled = false
	soul.global_position = Vector3(camp.GATE_POINT.x, 0.2,
		float(camp.GATE_POINT.z) + float(camp.ESCAPE_RADIUS) + 3.0)
	await physics_frame
	check(camp.sequencer.state() == SequencerScript.State.WARBAND,
		"standing short of the mouth is not the leaving (%s)" % camp.sequencer.state_name())
	# The walk, on the body's own feet: the trigger is proximity, not a teleport.
	var ticks := 0
	Engine.time_scale = 3.0
	while ticks < 600 and not camp.escaping():
		var to: Vector3 = Vector3(camp.GATE_POINT.x, 0.2, float(camp.GATE_POINT.z) - 1.0) \
			- soul.global_position
		to.y = 0.0
		if to.length() <= 1.0:
			break
		var direction := to.normalized()
		soul.accept_network_input(Vector2(direction.x, direction.z), true)
		await physics_frame
		ticks += 1
	Engine.time_scale = 1.0
	game.controller.input_enabled = true
	check(camp.escaping(), "walking into the gap in the trees is the escape (%s)"
		% camp.sequencer.state_name())
	check(state_count(SequencerScript.State.ESCAPING) == 1, "ESCAPING is entered exactly once")
	check(flat_range(soul.global_position, camp.GATE_POINT) <= float(camp.ESCAPE_RADIUS) + 0.5,
		"the soul reached the mouth (%.1f m from it)"
		% flat_range(soul.global_position, camp.GATE_POINT))
	var hint := str(camp.sequencer.hint())
	check(hint.contains("trail"), "the escape's key line names the trail (%s)" % hint)
	check(hint.contains("town"), "and names the town at the far end (%s)" % hint)
	check(camp.sequencer.objective().is_empty(),
		"past the mouth the world's own line takes over (%s)" % camp.sequencer.objective())
	check(not camp.tutorial_cleared(),
		"the leaving alone does not clear the opening (guards down %d of %d)"
		% [camp.sequencer.guards_down(), SequencerScript.GUARD_COUNT])
	check(camp.sequencer.guards_down() == 2,
		"the escape is not a kill quota: only the pair are down (%d)"
		% camp.sequencer.guards_down())

	# Four of them, out of the trees, on the makeshift tier and on their feet.
	var expected: int = 2 + int(CampScript.AMBUSH_COUNT)
	check(camp.guards.size() == expected,
		"the ambush comes out of the trees (%d watchers of %d)"
		% [camp.guards.size(), expected])
	var armed := 0
	for index in range(2, camp.guards.size()):
		var watcher = camp.guards[index]
		check(bool(watcher.get("alive")), "reinforcement %d is on its feet" % index)
		check(str(watcher.weapon_item) in MAKESHIFT,
			"reinforcement %d carries makeshift steel (%s)" % [index, str(watcher.weapon_item)])
		if str(watcher.weapon_item) in MAKESHIFT:
			armed += 1
		check(bool(watcher.has_weapon_visual()),
			"and the blade is in its hand (%s)" % str(watcher.name))
		check(watcher.global_position.y > -1.0,
			"reinforcement %d did not fall out of the world (y=%.2f)"
			% [index, watcher.global_position.y])
	check(armed == int(CampScript.AMBUSH_COUNT),
		"every reinforcement is armed (%d of %d)" % [armed, int(CampScript.AMBUSH_COUNT)])

	# The camp's ground out to the road: the corridor the geometry cut has to end
	# on the lane's first waypoint, or the two halves of the world do not meet.
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var corridor: Array = camp.clearing.get("corridor", [])
	var joins := false
	for gap in corridor:
		if (gap as Rect2).has_point(Vector2(lane[0].x, lane[0].z)):
			joins = true
			break
	check(joins, "the camp's corridor reaches the lane's first waypoint (%.1f,%.1f)"
		% [lane[0].x, lane[0].z])
	check(absf(flat_range(lane[0], camp.GATE_POINT) - float(camp.CAMP_TO_ROAD_METRES)) < 1.0,
		"and the lane starts exactly the camp's own metres out (%.1f)"
		% flat_range(lane[0], camp.GATE_POINT))

	# Cleared is all six down, and not one fewer: the last body standing is what
	# the checkpoint waits for.
	var standing: Array = []
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			standing.append(watcher)
	check(standing.size() >= 1, "an ambusher is still standing to be put down (%d)" % standing.size())
	for index in standing.size() - 1:
		if is_instance_valid(standing[index]) and bool(standing[index].get("alive")):
			standing[index].take_damage(4000.0, 0)
	check(not camp.tutorial_cleared(),
		"one watcher standing is an opening that is not cleared")
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	var cleared := await _wait_until(func() -> bool: return camp.tutorial_cleared(), 5.0)
	check(cleared, "the opening is cleared once the last watcher falls")
	check(camp.watchers_down() == expected,
		"every camp watcher is down (%d of %d)" % [camp.watchers_down(), expected])
	check(camp.sequencer.guards_down() == int(SequencerScript.GUARD_COUNT),
		"and the tally reached the whole camp (%d of %d)"
		% [camp.sequencer.guards_down(), int(SequencerScript.GUARD_COUNT)])
	check(requested_paths.is_empty(), "walking out of the camp requests no scene (%s)"
		% str(requested_paths))
	check(SequencerScript.state_name_of(SequencerScript.State.ESCAPING) == "escaping"
			and SequencerScript.state_name_of(SequencerScript.State.ESCAPING + 1) == "unknown",
		"the state machine has no town state after the escape")
	clear_tips()
	check_no_prose("the ambush")

## Static geometry inside a sphere at `point`. Collision layer 1 is the world, so
## this asks what the camp built, not who happens to be standing there.
func _geometry_at(point: Vector3, radius: float) -> Array:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	var hits := space.intersect_shape(query, 8)
	var names: Array = []
	for hit in hits:
		var body = hit.get("collider")
		if body is Node:
			names.append(str((body as Node).name))
	return names
