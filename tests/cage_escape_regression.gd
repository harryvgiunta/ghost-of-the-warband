extends SceneTree
## The opening tutorial, driven on the real world.
##
## The camp used to be a scene of its own with an arch at the end of the yard that
## loaded the road. It is now the first quarter of one world, and this regression
## owns the lesson inside it: five rags prisoners spawn in the camp, four of them
## in cages with the soul already inside one; every caged body sits clamped in its
## own cage; shifting the soul through all four in a scrambled order advances the
## sequencer exactly once; the fifth prisoner jogs in with empty hands - the pair
## took his shiv and threw it in the dirt - and stops there, because the fight is
## the player's. Taking his body starts the first fight's lesson: walk to the shiv
## (the card names W A S D), take it with `K`, swing once (the card names the three
## cuts), and hold `RMB` on the second watcher's windup (the card names the guard).
## The pair then fall for real, the tally books both, and the player cuts the four
## latches one cage at a time with `G`. Bare hands at a padlock are told so. The
## fourth latch is what puts the squad on its feet. Walking the body out of the
## camp through the gap in the trees spawns the six armed watchers out of the wood
## and turns the state to ESCAPING - the leaving is the ambush, not a kill quota.
##
## Every out-of-order event is fired at the machine first: a cage opened on the
## first beat, a kill before the fight, loot before the squad is out, a guard with
## no card behind it. None of them may advance a state or throw.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
const DuelScript = preload("res://scripts/warband/duel_lesson.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

const TEST_SAVE := "user://cage_escape_state.json"
const WARBAND_SAVE := "user://cage_escape_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## How long the rescuer's walk may take before the test calls it a hang.
const JOG_TIMEOUT := 16.0

var game
var camp
var state
var warband
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
	# The last beat plays at 3x, and a Timer counts scaled time.
	watchdog.wait_time = 900.0
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
	await create_timer(0.8).timeout
	camp.sequencer.state_changed.connect(_on_state_changed)
	game.scene_requested.connect(_on_scene_requested)

	print("CAGE_PHASE built %d ms" % (Time.get_ticks_msec() - _phase_start))
	dismiss_card("the opening card")
	_phase_start = Time.get_ticks_msec()
	check_spawn()
	check_cards()
	await check_clamp()
	check_refusals()
	check_see_all()
	await check_rescuer()
	print("CAGE_PHASE rescuer %d ms" % (Time.get_ticks_msec() - _phase_start))
	_phase_start = Time.get_ticks_msec()
	await check_duel()
	print("CAGE_PHASE duel %d ms" % (Time.get_ticks_msec() - _phase_start))
	_phase_start = Time.get_ticks_msec()
	await check_latches()
	print("CAGE_PHASE latches %d ms" % (Time.get_ticks_msec() - _phase_start))
	_phase_start = Time.get_ticks_msec()
	await check_revive_lesson()
	print("CAGE_PHASE revive %d ms" % (Time.get_ticks_msec() - _phase_start))
	_phase_start = Time.get_ticks_msec()
	await check_freed_walk()
	await check_out_and_ambush()
	print("CAGE_PHASE ambush+walk %d ms" % (Time.get_ticks_msec() - _phase_start))

	check(is_instance_valid(game) and game.is_inside_tree(),
		"the player stays in the world when nothing was requested")
	check(requested_paths.is_empty(), "the camp never asks for a scene (%s)" % str(requested_paths))

	_finish()

func _on_watchdog() -> void:
	check(false, "the cage escape tutorial did not finish inside the watchdog")
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

## The tutorial card is modal and pauses the tree. A test plays the player: if a
## card is up, it must be pausing, and closing it must resume.
func dismiss_card(label: String) -> void:
	if game == null or game.card == null or not game.card.is_open():
		return
	check(paused, "the card holds the game still (%s)" % label)
	check(not game.card.step().is_empty(), "the card names its step (%s)" % label)
	game.card.close()
	check(not paused, "closing the card resumes the game (%s)" % label)

func flat_range(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()

# --- spawn -----------------------------------------------------------------

func check_spawn() -> void:
	check(warband.roster.count() == 5, "the camp seeds five mercenaries (%d)" % warband.roster.count())
	check(game.bodies.size() == 5, "five bodies spawned (%d)" % game.bodies.size())
	check(camp.caged_ids.size() == 4, "four of them are caged")
	check(game.controller == camp.controller, "the camp runs on the world's one controller")
	check(camp.rescuer_id > 0 and not camp.caged_ids.has(camp.rescuer_id),
		"the fifth prisoner is not caged")
	for merc_id in warband.roster.ids():
		var gear: Dictionary = warband.roster.equipped_of(merc_id)
		# The warband starts in the naked base set - an old shirt and tight shorts,
		# and bare head, hands and feet, all of which guard nothing. They fight in
		# what they strip off the dead or buy in town.
		for slot in ["head", "chest", "hands", "legs", "feet"]:
			check(str(gear.get(slot, "")) == "armor_naked_%s" % slot,
				"%s wears the naked %s (%s)" % [warband.roster.name_of(merc_id), slot,
					str(gear.get(slot, ""))])
		if merc_id != camp.rescuer_id:
			check(str(gear.get("main", "")).is_empty(),
				"prisoner %s is unarmed" % warband.roster.name_of(merc_id))
	check(str(warband.roster.equipped_of(camp.rescuer_id).get("main", "")).is_empty(),
		"the rescuer arrives with empty hands")
	check(str(warband.roster.equipped_of(camp.rescuer_id).get("off", "")).is_empty(),
		"and nothing in his off hand either")
	var lesson_shiv = camp.get("_shiv_pickup")
	check(lesson_shiv != null and is_instance_valid(lesson_shiv),
		"his ironwood shiv lies on the dirt for the player to take")
	check(lesson_shiv != null and str(lesson_shiv.item_id) == camp.LESSON_SHIV,
		"and it is the shiv, not a stray club (%s)"
		% ("" if lesson_shiv == null else str(lesson_shiv.item_id)))
	for merc_id in camp.caged_ids:
		check(game.controller.body_of(merc_id) != null, "caged mercenary %d has a body" % merc_id)
	var local = game.controller.active_body(1)
	check(local != null, "the local soul starts inside a body")
	check(camp.caged_ids.has(game.controller.merc_for_peer(1)),
		"the soul starts in one of the four prisoners")
	check(camp.sequencer.state() == SequencerScript.State.CAGED, "the tutorial opens caged")
	check(camp.sequencer.seen_count() == 1, "the starting body counts as seen")
	check(camp.sequencer.objective() == "Shift your soul between the four prisoners   1/4",
		"the opening objective reads as a possession instruction")
	check(not camp.cages_open(), "the cages are still shut")
	check(camp.guards.size() == 2, "two watchers hold the clearing")
	for watcher in camp.guards:
		check(bool(watcher.get("alive")), "a watcher stands on its feet")
		check(is_equal_approx(float(watcher.max_health), float(camp.PAIR_LESSON_HEALTH)),
			"the pair Corvin fights are the thinned ones, got %s" % str(watcher.max_health))
		check(float(camp.PAIR_LESSON_HEALTH) <= WatcherScript.PAIR_HEALTH,
			"and never thicker than the camp's own thinned pool")
		check(str(watcher.name).begins_with("CampWatcher"),
			"the watcher is a camp body (%s)" % watcher.name)
		check(str(watcher.get("mob_id")) == "hollow_warden",
			"the watcher is the antlered warden body, not a ranger clone")
	check(camp.sequencer.hint().contains("F1"), "the first beat names the body keys")
	check(camp.pickups().size() == 4,
		"three cultist weapons and the rescuer's shiv lie on the walk (%d)"
		% camp.pickups().size())
	# Nothing is under the world: the clearing is ground, not a ledge.
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

## The tutorial stays - cards, objectives, key lines - and says only what happens
## now. Every step names the real key for the real action: no card claims a latch
## opens itself, and no card hands the pair to somebody else, because the fight is
## the player's own now.
func check_cards() -> void:
	var cards: Dictionary = camp.STEP_CARDS
	check(cards.size() == 5, "the opening has one card per beat (%d)" % cards.size())
	for state in cards:
		var card: Dictionary = cards[state]
		var text := "%s %s %s %s" % [card["title"], card["body"], card["keys"],
			card["footnote"]]
		var lower := text.to_lower()
		check(not lower.contains("opens at once") and not lower.contains("all four latches at once")
				and not lower.contains("he cuts all four") and not lower.contains("latches fall"),
			"card %d never claims a latch opens itself (%s)" % [int(state), text])
		check(not lower.contains("puts them down himself")
				and not lower.contains("puts them down for you"),
			"card %d never promises the pair are somebody else's kill" % int(state))
		# `G` is only named where it cuts a latch.
		if int(state) < 2:
			check(not lower.contains("g at a cage") and not lower.contains("g  -"),
				"card %d never advertises an interact key it has no use for (%s)"
				% [int(state), text])
	var body_card: Dictionary = cards[2]
	var body_text := "%s %s" % [body_card["body"], body_card["keys"]]
	check(str(body_card["keys"]).contains("F5"), "the body card names the key that takes him")
	check(body_text.to_lower().contains("shiv"), "and sends the player to his shiv")
	check(body_text.to_lower().contains("cut") and body_text.to_lower().contains("g"),
		"and says the latches come after it with G (%s)" % body_text)
	var out_card := str(cards[3]["body"]).to_lower()
	check(out_card.contains("gap in the trees"), "the freed card sends the squad out between trees")
	check(out_card.contains("wood"), "and says the way on is wood, not a road")
	check(not out_card.contains("watchers wake"), "and no longer promises a fight in the camp")
	# The first fight's own four cards: the feet, the steel, the cuts, the guard.
	check(camp.DUEL_CARDS.size() == 4, "the first fight has four cards (%d)"
		% camp.DUEL_CARDS.size())
	var feet: Dictionary = camp.DUEL_CARDS[0]
	check(str(feet["keys"]).contains("W A S D"), "the first card teaches walking")
	check(str(feet["keys"]).contains("SHIFT"), "and running")
	var steel: Dictionary = camp.DUEL_CARDS[1]
	check(str(steel["keys"]).contains("K"), "the second card names the pickup key")
	var cuts: Dictionary = camp.DUEL_CARDS[2]
	for token in ["LMB", "WHEEL_UP", "WHEEL_DOWN"]:
		check(str(cuts["keys"]).contains(token), "the cuts card names %s" % token)
	var guard: Dictionary = camp.DUEL_CARDS[3]
	check(str(guard["keys"]).contains("RMB"), "the guard card names RMB")
	check(str(guard["body"]).to_lower().contains("hold"),
		"and says the guard is held, not tapped")
	check(camp.sequencer.hint().contains("F1"), "the first beat names the body keys")
	check(not camp.sequencer.hint().contains("cut a latch"),
		"and never a latch key while the latches are not the beat")


# --- the cage clamp --------------------------------------------------------

func check_clamp() -> void:
	var merc_id: int = game.controller.merc_for_peer(1)
	var actor = game.controller.body_of(merc_id)
	var anchor: Vector3 = camp.cage_anchor_for(merc_id)
	check(camp.is_cage_clamped(merc_id), "the soul's cage is clamped")
	actor.global_position = anchor + Vector3(6.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	var strayed := flat_range(actor.global_position, anchor)
	check(strayed <= 1.2, "a caged body is snapped back inside its cage (%.2f m)" % strayed)
	check(game.controller.active_body(1) == actor, "the clamped body is still the soul's body")

# --- order guards ----------------------------------------------------------

func check_refusals() -> void:
	var before: int = camp.sequencer.state()
	check(not camp.sequencer.note_cage_opened(9), "a cage that does not exist is never booked")
	check(not camp.sequencer.note_cage_opened(-1), "and neither is a negative index")
	check(not camp.sequencer.note_rescuer_arrived(), "the rescuer cannot arrive before all four seen")
	check(not camp.sequencer.note_guard_killed(), "a guard death before the fight is not progress")
	check(not camp.sequencer.note_weapon_looted(), "loot before the cages open is not progress")
	check(not camp.sequencer.note_body_entered(0), "a non-body never counts as a prisoner")
	check(not camp.sequencer.note_body_entered(-3), "a negative id never counts as a prisoner")
	check(camp.sequencer.state() == before, "refusals leave the state where it was")
	check(camp.sequencer.seen_count() == 1, "refusals do not inflate the seen count")
	camp.sequencer.note_body_entered(camp.caged_ids[0])
	check(camp.sequencer.seen_count() == 1, "re-entering a body twice counts once")
	check(camp.sequencer.state() == SequencerScript.State.CAGED, "still caged after the refusals")

	# A cage cut before the lesson reaches the latches is a fact, not a permission:
	# it is booked, and it does not skip a beat. The live camp's machine is not
	# touched here - the point is the sequencing guard, so it is driven on a scratch
	# machine through the whole opening in the wrong order.
	var scratch := SequencerScript.new()
	scratch.begin(2)
	for index in SequencerScript.PRISONER_COUNT:
		scratch.note_cage_opened(SequencerScript.PRISONER_COUNT - 1 - index)
	check(scratch.cages_opened() == SequencerScript.PRISONER_COUNT,
		"four early latches are all booked (%d)" % scratch.cages_opened())
	check(scratch.state() == SequencerScript.State.CAGED,
		"four early latches skip no beat (%s)" % scratch.state_name())
	for merc_id in [11, 12, 13, 14]:
		scratch.note_body_entered(int(merc_id))
	check(scratch.state() == SequencerScript.State.ALL_SEEN,
		"the four bodies still advance the lesson once (%s)" % scratch.state_name())
	scratch.note_rescuer_arrived()
	check(scratch.state() == SequencerScript.State.FREED,
		"and the squad is out the moment the beat that owns four latches arrives (%s)"
		% scratch.state_name())
	scratch.free()

# --- seeing all four -------------------------------------------------------

func check_see_all() -> void:
	var ids: Array = camp.caged_ids
	# Scrambled order on purpose: the lesson must not depend on F1..F4 in order.
	for index in ids.size():
		var merc_id: int = int(ids[(index + 2) % ids.size()])
		game.controller.direct(1, merc_id)
		check(game.controller.merc_for_peer(1) == merc_id, "the soul moved into mercenary %d" % merc_id)
	check(camp.sequencer.seen_count() == 4, "all four prisoners were seen")
	check(camp.sequencer.state() == SequencerScript.State.ALL_SEEN,
		"the fourth possession advances to ALL_SEEN (%s)" % camp.sequencer.state_name())
	check(state_count(SequencerScript.State.ALL_SEEN) == 1, "ALL_SEEN is entered exactly once")
	check(camp.sequencer.objective().contains("fifth prisoner"),
		"the objective sends the player to the rescuer")
	game.controller.direct(1, int(ids[1]))
	game.controller.direct(1, int(ids[3]))
	check(camp.sequencer.seen_count() == 4 and camp.sequencer.state() == SequencerScript.State.ALL_SEEN,
		"re-entering seen bodies does not advance the tutorial")
	dismiss_card("all four seen")

# --- the rescuer -----------------------------------------------------------

func check_rescuer() -> void:
	var waited := 0.0
	while camp.sequencer.state() == SequencerScript.State.ALL_SEEN and waited < JOG_TIMEOUT:
		await create_timer(0.1).timeout
		waited += 0.1
	check(waited < JOG_TIMEOUT, "the rescuer walked to the cages in %.1f s" % waited)
	check(camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		"the rescuer's arrival starts the fight (%s)" % camp.sequencer.state_name())
	check(state_count(SequencerScript.State.RESCUER_ARRIVED) == 1,
		"RESCUER_ARRIVED is entered exactly once")
	check(game.controller.merc_for_peer(1) != camp.rescuer_id,
		"the soul is NOT moved into the rescuer for the player")
	check(not camp.sequencer.rescuer_taken(), "the rescuer has not been taken yet")
	check(camp.cages_open_count() == 0, "no latch is cut for free")
	check(camp.watchers_down() == 0, "both watchers are still standing when he arrives")
	var arrived_objective: String = camp.sequencer.objective()
	check(arrived_objective.contains("F5") and arrived_objective.contains("[ ]"),
		"the objective names both keys, got %s" % arrived_objective)
	check(arrived_objective.to_lower().contains("shiv"),
		"and sends the player to his shiv, got %s" % arrived_objective)
	check(camp.sequencer.hint().contains("F5"), "the hint names F5")
	check(camp.sequencer.hint().contains("K"),
		"and names the key that takes a weapon off the ground, got %s" % camp.sequencer.hint())
	dismiss_card("the rescuer's card")

	# Bare hands cut nothing: the soul is still in a caged body with no blade, and a
	# press at the bars is answered with the one line that says why.
	var soul = game.controller.active_body(1)
	var soul_id: int = game.controller.merc_for_peer(1)
	var own_cage: int = camp.caged_ids.find(soul_id)
	check(own_cage >= 0, "the soul is still in one of the cages")
	await physics_frame
	check(camp.latch_target(soul) == own_cage, "its own latch is in reach through the bars")
	check(not camp.holds_blade(soul), "and the body has nothing to cut it with")
	check(camp.interact(soul), "the camp consumes the press at a cage")
	check(camp.cages_open_count() == 0, "G with bare hands opens no cage")
	var status = game.hud.get("_status_label")
	check(status != null and str(status.text).contains("Nothing to cut the latch with"),
		"and the HUD says what is missing (%s)" % ("" if status == null else str(status.text)))
	check(camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		"and the lesson stays where it was")

	# Taking Corvin is the beat that hands the player a body, and nothing more: his
	# hands are empty, because the pair took his shiv off him and threw it in the
	# dirt. The first fight's lesson starts on that frame and holds the game still
	# for the walk it asks for.
	var take: Dictionary = game.controller.direct(1, camp.rescuer_id)
	check(bool(take.get("ok", false)), "the rescuer's body can be entered")
	check(game.controller.merc_for_peer(1) == camp.rescuer_id,
		"the soul is in Corvin's body after F5")
	check(camp.sequencer.rescuer_taken(), "the sequencer saw the player take the body")
	check(not camp.sequencer.note_rescuer_taken(), "taking the body only counts once")
	check(camp.cages_open_count() == 0, "and taking his body cuts no latch by itself")
	check(camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		"the lesson still wants the walk (%s)" % camp.sequencer.state_name())
	var cutter = game.controller.active_body(1)
	check(not camp.holds_blade(cutter), "his hands are empty until the shiv is taken")
	check(camp.duel != null, "the first fight's lesson is built with the camp")
	check(float(camp.SHIV_CARD_RADIUS) <= float(load("res://scripts/warband/world_scene.gd").LOOT_REACH),
		"the pickup card opens no farther off than the key that takes it reaches")
	check(camp.duel.step() == DuelScript.Step.MOVE,
		"taking him starts the lesson at the feet (%s)" % camp.duel.step_name())
	check(game.card != null and game.card.is_open() and game.card.step() == "step_3",
		"the walking card is the chapter's fourth (%s)"
		% ("" if game.card == null else game.card.step()))
	check(str(camp.hint_line(cutter)).contains("W A S D"),
		"and its key line teaches walking (%s)" % str(camp.hint_line(cutter)))
	# Nothing hunts an empty-handed body: the pair wake on the shiv, not on a beat.
	for watcher in camp.guards:
		check(not bool(watcher.hunting()), "the pair do not hunt an unarmed body")
	check(camp.watchers_down() == 0, "both watchers are still standing")
	dismiss_card("the walking card")

# --- the first fight -------------------------------------------------------

## Walk onto the shiv, take it, and fight the pair with the keys the cards name.
## Every card here is raised by the fight itself - a step onto the shiv, a swing,
## the second watcher's windup - and every one of them holds the game still.
func check_duel() -> void:
	var cutter = game.controller.active_body(1)
	check(cutter != null and game.controller.merc_for_peer(1) == camp.rescuer_id,
		"the soul is still in Corvin's body for the fight")
	# 1. The walk. The card that asks for `K` opens on the approach, never on a
	#    timer, and the pair stay asleep until the player is armed.
	cutter.global_position = camp.SHIV_POST + Vector3(0.0, 0.35, 2.0)
	await physics_frame
	await physics_frame
	check(camp.duel.step() == DuelScript.Step.FETCH,
		"standing over the shiv asks for the pickup (%s)" % camp.duel.step_name())
	check(game.card != null and game.card.is_open() and game.card.step() == "step_4",
		"the pickup card is the chapter's fifth (%s)"
		% ("" if game.card == null else game.card.step()))
	check(str(camp.hint_line(cutter)).contains("K"),
		"and its key line names K (%s)" % str(camp.hint_line(cutter)))
	for watcher in camp.guards:
		check(not bool(watcher.hunting()), "nothing hunts the body on its way to the shiv")
	dismiss_card("the pickup card")
	# 2. Take it with the key the card named.
	game._try_loot()
	check(str(warband.roster.equipped_of(camp.rescuer_id).get("main", ""))
			== camp.LESSON_SHIV, "K puts the ironwood shiv in his main hand")
	check(camp.holds_blade(cutter), "and the body is holding a blade")
	check(camp.duel.step() == DuelScript.Step.FIGHT,
		"taking the shiv starts the fight (%s)" % camp.duel.step_name())
	# 3. The pair wake on that frame, and never before it.
	var woke := await await_condition(
		func() -> bool: return _hunting_watchers() > 0, 8.0, "the pair waking")
	check(woke, "the pair turn on the body holding the shiv (%d hunting)"
		% _hunting_watchers())
	# 4. The first cut is where the three cuts get named.
	await click_until_swing(cutter)
	check(camp.duel.swing_card(), "the player's first cut raises the swings card")
	check(game.card != null and game.card.is_open(),
		"and the game is held still for it")
	if game.card != null and game.card.is_open():
		check(game.card.step() == "step_5", "the cuts card is the chapter's sixth (%s)"
			% game.card.step())
	dismiss_card("the swings card")
	# 5. The second watcher's windup is where the guard is taught: stand in front
	#    of it and let it raise its club.
	var second = camp.guards[1] if camp.guards.size() > 1 else null
	check(second != null and is_instance_valid(second), "the pair has a second body")
	if second != null and is_instance_valid(second):
		cutter.global_position = (second as Node3D).global_position + Vector3(0.0, 0.1, 1.7)
	var wind := await await_condition(
		func() -> bool: return bool(camp.duel.guard_card()), 12.0, "the guard card")
	check(wind, "the second watcher's swing teaches the guard")
	if game.card != null and game.card.is_open():
		check(game.card.step() == "step_6", "the guard card is the chapter's seventh (%s)"
			% game.card.step())
		dismiss_card("the guard card")
	# 6. Hold the guard and let the club come down on it. The press is repeated
	#    because a body still landing cannot raise its blade.
	var guarded := false
	var guard_frames := 0
	while guard_frames < 300:
		if not bool(cutter.combat.blocking):
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_RIGHT
			press.pressed = true
			game.controller._mouse_press(press)
		if bool(camp.duel.guarded()):
			guarded = true
			break
		await physics_frame
		guard_frames += 1
	check(guarded, "a blow that lands on a raised blade finishes the lesson (%s)"
		% camp.duel.step_name())
	check(camp.duel.step() == DuelScript.Step.DONE,
		"and the lesson hands the keys back (%s)" % camp.duel.step_name())
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	game.controller._mouse_release(release)
	# 7. The pair fall to the player's own blade - the whole point of the lesson.
	#    Two stabs of a 21-health watcher, thrown from the real input path, with the
	#    body walked back into reach between cuts because the pair keep closing.
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
	check(str(camp.prompt_line(cutter)).contains("latch"),
		"and the HUD asks for the latches again (%s)" % str(camp.prompt_line(cutter)))
	check(camp.sequencer.rescuer_taken(), "the soul's earlier step still counts")

## How many of the camp's watchers are actually hunting.
func _hunting_watchers() -> int:
	var count := 0
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.hunting()):
			count += 1
	return count

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

# --- the latches -----------------------------------------------------------

## The walk the opening builds to: one cage, one press, one latch, one door - and
## the fourth cut is what puts the squad on its feet.
func check_latches() -> void:
	check(game.controller.merc_for_peer(1) == camp.rescuer_id,
		"the soul is in Corvin's body for the latches")
	var cutter = game.controller.active_body(1)
	check(camp.holds_blade(cutter), "and the shiv is in his hands")
	check(camp.cages_open_count() == 0,
		"the pair falling cut no latch by itself (%d)" % camp.cages_open_count())
	var doors: Array = camp.clearing.get("doors", [])
	check(doors.size() == 4, "the camp has four cage doors (%d)" % doors.size())
	# The ground in front of every cage has to be walkable: a latch is worked from
	# the dirt on its +z side, so no hut, stack, stake or trunk may stand there.
	for index in camp.CAGE_POSTS.size():
		var approach: Vector3 = camp.CAGE_POSTS[index]
		var blocked := _geometry_at(Vector3(approach.x, 0.9, approach.z + 2.6), 0.55)
		check(blocked.is_empty(), "cage %d's approach is clear ground (%s)"
			% [index + 1, str(blocked)])
	for index in camp.CAGE_POSTS.size():
		var post: Vector3 = camp.CAGE_POSTS[index]
		cutter.global_position = Vector3(post.x, 0.2, post.z + 2.6)
		await physics_frame
		var reach_gap: float = Vector2(cutter.global_position.x - post.x,
			cutter.global_position.z - post.z).length() - float(camp.CAGE_HALF)
		check(camp.latch_target(cutter) == index,
			"cage %d's latch is the one in reach (body %.1f,%.1f gap %.2f target %d)"
			% [index + 1, cutter.global_position.x, cutter.global_position.z, reach_gap,
				camp.latch_target(cutter)])
		game._try_interact()
		check(camp.cages_open_count() == index + 1,
			"cutting cage %d books %d latches (%d)" % [index + 1, index + 1, camp.cages_open_count()])
		check(camp.sequencer.cages_opened() == index + 1,
			"and the sequencer counts them one by one (%d)" % camp.sequencer.cages_opened())
		if index < camp.CAGE_POSTS.size() - 1:
			check(camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
				"%d of 4 latches does not loose the squad (%s)"
				% [index + 1, camp.sequencer.state_name()])
	# The card that opens on the fourth latch pauses the tree, so it is read before
	# the doors are timed: the lift is the door's own animation, not a cutscene.
	dismiss_card("the freed card")
	await create_timer(1.3).timeout
	check(camp.cages_open(), "the cages are open")
	check(camp.sequencer.cages_opened() == 4, "the sequencer booked four cages")
	check(not camp.sequencer.note_cage_opened(0), "a latch only counts once")
	check(state_count(SequencerScript.State.FREED) == 1, "FREED is entered exactly once")
	check(camp.sequencer.state() == SequencerScript.State.FREED,
		"the fourth latch frees the squad (%s)" % camp.sequencer.state_name())
	for index in camp.caged_ids.size():
		check(not camp.is_cage_clamped(int(camp.caged_ids[index])),
			"cage %d stopped clamping its prisoner" % (index + 1))
	# The bars lift: the camp's four doors climb out of their frames.
	var lifted := 0
	for door in doors:
		if is_instance_valid(door) and (door as Node3D).position.y >= camp.CAGE_BAR_LIFT - 0.2:
			lifted += 1
	check(lifted == 4, "every cage door rose when its latch went (%d of 4)" % lifted)
	check(SequencerScript.GUARD_COUNT == 2 + CampScript.AMBUSH_COUNT,
		"the camp's tally counts the pair and the ambush (%d)" % SequencerScript.GUARD_COUNT)
	check(camp.sequencer.objective().contains("2/%d" % SequencerScript.GUARD_COUNT),
		"the tally counts Corvin's pair against the camp (%s)" % camp.sequencer.objective())

# --- the fallen ------------------------------------------------------------

## A squadmate going down at the player's feet raises the one unnumbered card:
## `G` held for five seconds brings a body back, and that has to be taught the
## first time it can be used, wherever it happens. The body is stripped first so
## the drop it leaves behind is not mistaken for the lesson's own steel.
func check_revive_lesson() -> void:
	var ally_id: int = int(camp.caged_ids[2])
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
	check(game.card != null and game.card.is_open(),
		"a squadmate falling at the player's feet opens the revive lesson")
	check(game.card.step() == "lesson_revive",
		"it is the one unnumbered card (%s)" % ("" if game.card == null else game.card.step()))
	check(paused, "and it holds the game still, bleed clock included")
	check(camp.pickups().size() == floor_before,
		"an empty-handed body leaves nothing on the dirt (%d for %d)"
		% [camp.pickups().size(), floor_before])
	dismiss_card("the revive card")
	await physics_frame
	var prompt := str(game.get("_prompt_text"))
	check(prompt.to_upper().contains("HOLD G"),
		"the HUD then asks for the hold over the body (%s)" % prompt)
	check(prompt.contains(warband.roster.name_of(ally_id).to_upper()),
		"and names the body that needs it (%s)" % prompt)


# --- the freed squad -------------------------------------------------------

func check_freed_walk() -> void:
	var merc_id: int = int(camp.caged_ids[1])
	check(not camp.is_cage_clamped(merc_id), "the clamp is gone once the cages open")
	var actor = game.controller.body_of(merc_id)
	var anchor: Vector3 = camp.cage_anchor_for(merc_id)
	actor.global_position = anchor + Vector3(5.5, 0.0, 0.0)
	await create_timer(0.3).timeout
	var walked := flat_range(actor.global_position, anchor)
	check(walked > 4.0, "a freed body walks out of its cage (%.2f m)" % walked)

# --- the armed squad, and the leaving -------------------------------------

## True once the watcher is hurt or gone: the proof that a squad swing landed.
func _watcher_hurt(watcher) -> bool:
	if not is_instance_valid(watcher):
		return true
	if not bool(watcher.get("alive")):
		return true
	return float(watcher.get("health")) < float(watcher.get("max_health"))

## A freed prisoner - not Corvin, and not the body the soul is in - with steel in
## its hands. The squad arms itself silently; this is the only way to see it.
func _prisoner_armed() -> int:
	var count := 0
	for raw_id in camp.caged_ids:
		var actor = game.controller.body_of(int(raw_id))
		if actor == null or not is_instance_valid(actor):
			continue
		if str(actor.rig.weapon) in ["sword", "dagger", "dual", "bow"]:
			count += 1
	return count

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


func await_condition(predicate: Callable, timeout: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		dismiss_card(label)
		if bool(predicate.call()):
			return true
		await create_timer(0.05).timeout
	dismiss_card(label)
	return bool(predicate.call())

func check_out_and_ambush() -> void:
	# Nothing was looted for the player: the three cultist drops are still there,
	# plus the shiv the lesson put on the dirt, plus one blade for each of the pair
	# the player put down - a fallen watcher's steel leaves its hand and lands on
	# the dirt beside it.
	var standing_pair := 0
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			standing_pair += 1
	check(camp.pickups().size() == 4 + (2 - standing_pair),
		"three drops, the shiv and one blade per fallen watcher lie on the walk (%d)"
		% camp.pickups().size())
	var armed := await await_condition(
		func() -> bool: return _prisoner_armed() >= 1, 14.0, "the squad arming")
	check(armed, "a freed prisoner picks a weapon off the ground and holds it")
	var left := 0
	for pickup in camp.pickups():
		if is_instance_valid(pickup) and not bool(pickup.collected):
			left += 1
	check(left < camp.pickups().size(), "a drop left the floor (%d of %d left)"
		% [left, camp.pickups().size()])
	check(camp.sequencer.weapons_taken() >= 1, "the pickup was booked as steel")
	check(camp.sequencer.state() == SequencerScript.State.FREED,
		"arming itself does not start the escape (%s)" % camp.sequencer.state_name())
	check(camp.guards.size() == 2, "the camp holds no more watchers than the pair (%d)"
		% camp.guards.size())

	# Leaving is the ambush: the body walks out through the gap in the trees and the
	# wood answers.
	var local = game.controller.active_body(1)
	check(local != null, "the soul still has a body for the walk out")
	game.controller.input_enabled = false
	local.global_position = Vector3(0.0, 0.2, -12.0)
	await physics_frame
	var mouth: Vector3 = camp.GATE_POINT
	var ticks := 0
	var out_started := Time.get_ticks_msec()
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 3.0
	while ticks < 2000:
		if camp.sequencer.state() == SequencerScript.State.ESCAPING:
			break
		var to: Vector3 = Vector3(0.0, 0.2, mouth.z - 2.0) - local.global_position
		to.y = 0.0
		if to.length() <= 1.2:
			break
		var direction := to.normalized()
		local.accept_network_input(Vector2(direction.x, direction.z), false)
		await physics_frame
		ticks += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var walked_seconds := float(Time.get_ticks_msec() - out_started) / 1000.0
	# The card that opens on the leaving holds the tree still, exactly like every
	# other beat: the player reads it, then the ambush moves.
	dismiss_card("the leaving")
	check(camp.sequencer.state() == SequencerScript.State.ESCAPING,
		"walking out through the mouth is the escape (%s)" % camp.sequencer.state_name())
	check(state_count(SequencerScript.State.ESCAPING) == 1, "ESCAPING is entered exactly once")
	check(flat_range(local.global_position, mouth) <= camp.ESCAPE_RADIUS + 0.5,
		"the soul reached the mouth (%.1f m from it)" % flat_range(local.global_position, mouth))
	check(camp.sequencer.guards_down() == 2,
		"the escape is not a kill quota: only Corvin's pair are down (%d)"
		% camp.sequencer.guards_down())
	check(camp.sequencer.hint().contains("trail"), "the escape's key line names the trail")
	check(camp.sequencer.hint().contains("town"), "and names the town at the far end")
	check(not camp.sequencer.hint().to_lower().contains("arch"), "and not an arch")
	print("CAGE_AMBUSH seconds=%.1f game_seconds=%.1f metres_out=%.0f"
		% [walked_seconds, float(ticks) / 60.0,
			flat_range(Vector3(0.0, 0.0, -30.0), local.global_position)])

	# Six armed watchers come out of the trees on that frame.
	var expected_guards: int = 2 + CampScript.AMBUSH_COUNT
	check(camp.guards.size() == expected_guards,
		"the ambush comes out of the trees (%d camp watchers of %d)" % [camp.guards.size(), expected_guards])
	var armed_reinforcements := 0
	var visible_blades := 0
	for index in range(2, camp.guards.size()):
		var watcher = camp.guards[index]
		check(bool(watcher.get("alive")), "reinforcement %d is on its feet" % index)
		if str(watcher.weapon_item) in ["club_makeshift", "dagger_ironwood",
				"branch_heavy", "bow_twig"]:
			armed_reinforcements += 1
		if watcher.has_weapon_visual():
			visible_blades += 1
		check(watcher.global_position.y > -1.0,
			"reinforcement %d did not fall out of the world (y=%.2f)" % [index, watcher.global_position.y])
	check(armed_reinforcements == CampScript.AMBUSH_COUNT,
		"every reinforcement carries a weapon (%d)" % armed_reinforcements)
	check(visible_blades == CampScript.AMBUSH_COUNT,
		"and the blade is in its hand (%d)" % visible_blades)

	# A hardened watcher's pool is the camp's contract, whoever ends up putting one
	# down, so it is measured here on one of the ambushers nobody has touched yet.
	var stabbable = null
	for index in range(2, camp.guards.size()):
		var fresh = camp.guards[index]
		if is_instance_valid(fresh) and bool(fresh.get("alive")):
			stabbable = fresh
			# The squad is already fighting them, so the pool is measured on a
			# body put back on its feet rather than on one nobody has reached yet.
			stabbable.health = stabbable.max_health
			break
	check(stabbable != null, "one of the ambush is still standing to measure")
	if stabbable != null:
		# The ambush is meant to be won: sixty health is five ironwood stabs, not
		# the twelve a hardened watcher used to take.
		var stabs := 0
		while bool(stabbable.get("alive")) and stabs < 40:
			stabbable.take_damage(10.0, 0)
			stabs += 1
		check(not bool(stabbable.get("alive")),
			"an ambusher goes down after %d shiv stabs" % stabs)
		check(stabs <= 7, "and it is meant to be won (%d stabs)" % stabs)

	# They are pointed at the squad, not left standing in the dark.
	var runner = null
	for index in range(2, camp.guards.size()):
		if camp.guards[index] != stabbable and is_instance_valid(camp.guards[index]) \
				and bool(camp.guards[index].get("alive")):
			runner = camp.guards[index]
			break
	check(runner != null, "an ambusher is left standing to run")
	var prey = camp.nearest_standing_body(runner.global_position)
	check(prey != null, "there is a body for the ambush to run at")
	var gap_before: float = runner.global_position.distance_to(prey.global_position)
	await create_timer(1.1).timeout
	dismiss_card("the ambush")
	check(is_instance_valid(runner) and bool(runner.get("alive")), "the runner is still alive")
	var gap_after: float = runner.global_position.distance_to(prey.global_position)
	check(gap_after < gap_before - 2.5, "the reinforcements run straight in (%.1f m -> %.1f m)"
		% [gap_before, gap_after])

	# The freed squad fights the ambush: a reinforcement takes a blow from a
	# squadmate's blade, which is what the arming was for. The one this test put
	# down itself does not count.
	var ambush_hurt := func() -> bool:
		for index in range(2, camp.guards.size()):
			if camp.guards[index] == stabbable:
				continue
			if _watcher_hurt(camp.guards[index]):
				return true
		return false
	var hurt := await await_condition(ambush_hurt, 14.0, "the squad landing blows")
	check(hurt, "the freed squad's steel lands on the ambush")

	# A fallen body's steel lands beside it. The corpse keeps the rag and the
	# dressing it wore; the blade it was swinging is a drop on the dirt, at the
	# body's own ground, carrying the id it was holding.
	var fell_with_steel := 0
	for index in range(2, camp.guards.size()):
		var watcher = camp.guards[index]
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var held := str(watcher.weapon_item)
		var at: Vector3 = watcher.global_position
		var floor_before: int = game.pickups.size()
		watcher.take_damage(4000.0, 0)
		await create_timer(0.1).timeout
		if held.is_empty():
			continue
		check(game.pickups.size() == floor_before + 1,
			"a fallen watcher leaves one blade on the floor (%d)" % (game.pickups.size() - floor_before))
		if game.pickups.size() > floor_before:
			var drop = game.pickups[game.pickups.size() - 1]
			# The squad may have walked it away inside the same beat, which is the
			# looting working rather than a missing drop.
			if not is_instance_valid(drop):
				fell_with_steel += 1
				continue
			check(str(drop.item_id) == held, "and it is the blade it held (%s)" % str(drop.item_id))
			check(flat_range(drop.global_position, at) <= 1.2,
				"lying beside the body (%.2f m)" % flat_range(drop.global_position, at))
			check(absf(drop.global_position.y - at.y) < 0.6,
				"on the body's own ground (%.2f vs %.2f)" % [drop.global_position.y, at.y])
		fell_with_steel += 1
	check(fell_with_steel >= 1, "at least one ambusher fell holding steel (%d)" % fell_with_steel)
	await create_timer(0.2).timeout
	var corpse_ids: Array = game.loot.corpse_ids()
	var with_gear := 0
	for corpse_id in corpse_ids:
		if not game.loot.corpse_items(int(corpse_id)).is_empty():
			with_gear += 1
	# The squad strips bodies on its own once the field is quiet, so `corpse_ids()`
	# can already be empty by the time this reads it: the contract being measured
	# is that every fallen body went through the registry, and that nothing landed
	# on the floor.
	check(game.loot.registered_corpses() >= CampScript.AMBUSH_COUNT,
		"every fallen ambusher registered as a corpse (%d of %d)"
		% [game.loot.registered_corpses(), CampScript.AMBUSH_COUNT])
	# A corpse never holds a second copy of the blade that fell: the steel is on
	# the floor and the body keeps the rag it was wearing.
	for corpse_id in corpse_ids:
		for item_id in game.loot.corpse_items(int(corpse_id)):
			check(not str(item_id) in ["club_makeshift", "dagger_ironwood",
					"branch_heavy", "bow_twig"],
				"a corpse carries no blade, the steel is on the floor (%s)" % str(item_id))
	check(camp.sequencer.guards_down() == 2 + CampScript.AMBUSH_COUNT,
		"the tally reaches the whole camp (%d)" % camp.sequencer.guards_down())
	check(requested_paths.is_empty(), "walking out of the camp requests no scene (%s)"
		% str(requested_paths))

	# The way on is a long run of wood to the head of the trail, and it is walked,
	# not opened. The corridor the camp cut has to end on the lane's first waypoint,
	# or the two halves of the world do not meet: proven on the geometry first.
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var corridor: Array = camp.clearing.get("corridor", [])
	var joins := false
	for gap in corridor:
		if (gap as Rect2).has_point(Vector2(lane[0].x, lane[0].z)):
			joins = true
			break
	check(joins, "the camp's corridor reaches the lane's first waypoint (%.1f,%.1f)"
		% [lane[0].x, lane[0].z])
	# The walk proves the ground, not the fight: the ambush has already been fought,
	# so the soul steps into whichever body is still standing and runs from there -
	# the same thing a player does when the body they were in has been put down.
	var runner_id := -1
	for merc_id in game.squad_ids:
		var candidate = game.controller.body_of(int(merc_id))
		if candidate == null or not is_instance_valid(candidate):
			continue
		if bool(candidate.get("alive")) and not bool(candidate.get("downed")):
			runner_id = int(merc_id)
			break
	if runner_id <= 0:
		# Every body is down: the revive channel is what a player would use, so the
		# walk is proven on a body brought back up rather than on nobody.
		for merc_id in game.squad_ids:
			var candidate = game.controller.body_of(int(merc_id))
			if candidate != null and is_instance_valid(candidate) \
					and bool(candidate.get("downed")) and bool(candidate.get("alive")):
				candidate.revive_from_downed(1.0)
				runner_id = int(merc_id)
				break
	check(runner_id > 0, "a body can be put on its feet for the run")
	if runner_id > 0:
		game.controller.direct(1, runner_id)
	local = game.controller.active_body(1)
	# The camp's own ground - cages to the gap in the trees - was walked by the
	# escape above. What is measured here is the wood between the camp and the road:
	# from the gap to the lane's first waypoint, with nothing under it but trees.
	local.global_position = Vector3(camp.GATE_POINT.x, 0.2, camp.GATE_POINT.z + 1.0)
	await physics_frame
	# The walk proves the ground, not the trail's fight: the road's cultists are
	# taken off the board first, so nothing interrupts the run between the camp and
	# the road's first torch.
	for watcher in game.trail.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	await create_timer(0.2).timeout
	game.controller.input_enabled = false
	ticks = 0
	var corridor_stall := 0
	var corridor_gap := flat_range(local.global_position, lane[0])
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 3.0
	while ticks < 4000:
		var to: Vector3 = lane[0] - local.global_position
		to.y = 0.0
		if to.length() <= 1.6:
			break
		var direction := to.normalized()
		local.accept_network_input(Vector2(direction.x, direction.z), true)
		await physics_frame
		ticks += 1
		# A body that stops making ground is a broken corridor, not a long run.
		var gap := flat_range(local.global_position, lane[0])
		corridor_stall = corridor_stall + 1 if gap > corridor_gap - 0.02 else 0
		corridor_gap = gap
		if corridor_stall > 240:
			print("CAGE_STALL corridor stuck at %.1f,%.1f" % [local.global_position.x,
				local.global_position.z])
			break
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	print("CAGE_PHASE corridor walk %d ms ticks=%d" % [Time.get_ticks_msec() - out_started, ticks])
	var out_of_the_camp: bool = local.global_position.z < camp.YARD_FRONT - 20.0
	check(out_of_the_camp, "the body walked out of the camp and into the wood (z=%.1f)"
		% local.global_position.z)
	check(flat_range(local.global_position, lane[0]) <= 2.0,
		"and ran the whole stretch of wood to the head of the trail (%.1f m off, at %.1f,%.1f)"
		% [flat_range(local.global_position, lane[0]), local.global_position.x,
			local.global_position.z])
	check(game.trail.forest["path"].distance_to(Vector2(local.global_position.x, local.global_position.z))
		< float(game.trail.forest["width"]) * 0.5 + 0.6,
		"and it is standing on the trail, not beside it")
	check(camp.sequencer.state() == SequencerScript.State.ESCAPING,
		"the lesson ends in the escape, not in a town state (%s)" % camp.sequencer.state_name())
	check(requested_paths.is_empty(), "walking out of the camp requests no scene (%s)"
		% str(requested_paths))
	check(SequencerScript.state_name_of(SequencerScript.State.ESCAPING) == "escaping"
			and SequencerScript.state_name_of(SequencerScript.State.ESCAPING + 1) == "unknown",
		"the state machine has no town state after the escape")
