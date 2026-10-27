extends SceneTree
## The opening tutorial, driven on the real world.
##
## The camp used to be a scene of its own with an arch at the end of the yard that
## loaded the road. It is now the first quarter of one world, and this regression
## owns the lesson inside it: five rags prisoners spawn in the clearing, four of
## them in cages with the soul already inside one; every caged body sits clamped
## in its own cage; shifting the soul through all four in a scrambled order
## advances the sequencer exactly once; the fifth prisoner jogs in and stands
## still; the player takes his body themselves and cuts four latches one at a
## time with G; the freed squad arms itself off the ground and fights; the first
## pair falling calls six armed watchers out of the trees; eight kills open the
## way - and the way out is the trail through the wood, not a door. The last
## section actually walks the body out of the clearing through the mouth, which is
## what replaced the arch.
##
## Every out-of-order event is fired at the machine first: freeing before the
## rescuer arrives, a kill before the squad is out, loot before the fight. None of
## them may advance a state or throw.

const SequencerScript = preload("res://scripts/warband/tutorial_sequencer.gd")
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

	dismiss_card("the opening card")
	check_spawn()
	await check_clamp()
	check_refusals()
	check_see_all()
	await check_rescuer()
	await check_latches()
	await check_freed_walk()
	await check_fight_and_way_out()

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

func state_count(value: int) -> int:
	var total := 0
	for entry in state_log:
		if int(entry[0]) == value:
			total += 1
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
		var rags := true
		for slot in ["head", "chest", "hands", "legs", "feet"]:
			if not str(gear.get(slot, "")).begins_with("armor_makeshift_"):
				rags = false
		check(rags, "%s wears rags" % warband.roster.name_of(merc_id))
		if merc_id != camp.rescuer_id:
			check(str(gear.get("main", "")).is_empty(),
				"prisoner %s is unarmed" % warband.roster.name_of(merc_id))
	check(str(warband.roster.equipped_of(camp.rescuer_id).get("main", "")) == "dagger_makeshift",
		"the rescuer carries the shiv")
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
		check(is_equal_approx(float(watcher.max_health), 72.0),
			"the watcher carries 72 health, got %s" % str(watcher.max_health))
		check(str(watcher.name).begins_with("Forest_"), "the watcher is the woodland mob (%s)" % watcher.name)
	check(camp.sequencer.hint().contains("F1"), "the first beat names the body keys")
	check(camp.pickups().size() == 3, "three cultist weapons lie on the walk")
	# Nothing is under the world: the clearing is ground, not a ledge.
	for body in game.bodies:
		check(body.global_position.y > -1.0, "body %s stands on the clearing" % str(body.name))
	for watcher in camp.guards:
		check(watcher.global_position.y > -1.0, "watcher %s stands on the clearing" % str(watcher.name))
	# The way out is the mouth in the fence, and the trail starts there.
	check(is_equal_approx(camp.GATE_POINT.z, camp.YARD_FRONT),
		"the mouth is on the clearing's front line (%s)" % str(camp.GATE_POINT))
	var lane: PackedVector3Array = game.trail.forest["lane"]
	check(flat_range(lane[0], camp.GATE_POINT) < 0.01,
		"the trail's first waypoint is the clearing's mouth")

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
	check(not camp.sequencer.note_cage_opened(0), "a latch is refused before the rescuer arrives")
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
		"the rescuer's arrival hands over the shiv (%s)" % camp.sequencer.state_name())
	check(state_count(SequencerScript.State.RESCUER_ARRIVED) == 1,
		"RESCUER_ARRIVED is entered exactly once")
	check(game.controller.merc_for_peer(1) != camp.rescuer_id,
		"the soul is NOT moved into the rescuer for the player")
	check(not camp.sequencer.rescuer_taken(), "the rescuer has not been taken yet")
	check(camp.cages_open_count() == 0, "no latch is cut for free")
	var arrived_objective: String = camp.sequencer.objective()
	check(arrived_objective.contains("F5") and arrived_objective.contains("[ ]"),
		"the objective names both keys, got %s" % arrived_objective)
	check(camp.sequencer.hint().contains("F5"), "the hint names F5")
	dismiss_card("the rescuer's card")
	var take: Dictionary = game.controller.direct(1, camp.rescuer_id)
	check(bool(take.get("ok", false)), "the rescuer's body can be entered")
	check(game.controller.merc_for_peer(1) == camp.rescuer_id,
		"the soul is in Corvin's body after F5")
	check(camp.sequencer.rescuer_taken(), "the sequencer saw the player take the body")
	check(not camp.sequencer.note_rescuer_taken(), "taking the body only counts once")
	check(camp.sequencer.objective().contains("latch"),
		"the objective moves on to the latches, got %s" % camp.sequencer.objective())
	check(camp.sequencer.hint().contains("G"), "the hint names the latch key")
	var rescuer = game.controller.body_of(camp.rescuer_id)
	check(rescuer != null and flat_range(rescuer.global_position, camp.JOG_TARGET) < 4.0,
		"the rescuer is standing at the cages")
	dismiss_card("the rescuer's card")

# --- one latch at a time ---------------------------------------------------

## Every cage is opened by walking to it and pressing G, and only Corvin's body
## carries the shiv: a prisoner at their own bars is refused.
func check_latches() -> void:
	var rescuer = game.controller.body_of(camp.rescuer_id)
	var first_cage: Vector3 = camp.CAGE_POSTS[0]
	game.controller.direct(1, int(camp.caged_ids[2]))
	var prisoner = game.controller.body_of(int(camp.caged_ids[2]))
	prisoner.global_position = first_cage + Vector3(0.0, 0.1, 0.3)
	await physics_frame
	game._try_interact()
	check(camp.cages_open_count() == 0, "only the rescuer's shiv opens a cage")
	check(camp.sequencer.state() == SequencerScript.State.RESCUER_ARRIVED,
		"a refused latch changes nothing")

	game.controller.direct(1, camp.rescuer_id)
	rescuer = game.controller.body_of(camp.rescuer_id)
	for index in camp.caged_ids.size():
		var cage: Vector3 = camp.CAGE_POSTS[index]
		rescuer.global_position = cage + Vector3(0.0, 0.1, 0.4)
		await physics_frame
		await physics_frame
		game._try_interact()
		dismiss_card("latch %d" % (index + 1))
		if index == 0:
			# 72 health against a 14-damage shiv: five stabs are not enough.
			var early = camp.guards[0]
			for stab in 5:
				early.take_damage(14.0, 0)
				check(bool(early.get("alive")), "stab %d of 6 leaves a watcher standing" % (stab + 1))
			early.take_damage(14.0, 0)
			check(not bool(early.get("alive")), "the sixth stab puts a watcher down")
			check(camp.sequencer.guards_down() == 0,
				"a kill before the squad is out is not progress")
		await physics_frame
		check(camp.cages_open_count() == index + 1,
			"latch %d of 4 is cut (%d)" % [index + 1, camp.cages_open_count()])
		check(not camp.is_cage_clamped(int(camp.caged_ids[index])),
			"cage %d stopped clamping its prisoner" % (index + 1))
		if index + 1 < camp.caged_ids.size():
			check(camp.is_cage_clamped(int(camp.caged_ids[index + 1])),
				"the next cage is still shut")
	check(camp.cages_open(), "all four latches are cut")
	check(camp.sequencer.state() == SequencerScript.State.FREED,
		"the fourth latch frees the squad (%s)" % camp.sequencer.state_name())
	check(camp.sequencer.cages_opened() == 4, "the sequencer counted four cages")
	check(not camp.sequencer.note_cage_opened(0), "a latch only counts once")
	check(camp.sequencer.guards_down() == 1,
		"the kill landed before the squad was out is reconciled on FREED")

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

# --- the fight and the way out --------------------------------------------

## True once the watcher is hurt or gone: the proof that a squad swing landed.
func _watcher_hurt(watcher) -> bool:
	if not is_instance_valid(watcher):
		return true
	if not bool(watcher.get("alive")):
		return true
	return float(watcher.get("health")) < float(watcher.get("max_health"))

func await_condition(predicate: Callable, timeout: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		dismiss_card(label)
		if bool(predicate.call()):
			return true
		await create_timer(0.05).timeout
	dismiss_card(label)
	return bool(predicate.call())

func check_fight_and_way_out() -> void:
	check(camp.sequencer.guards_down() == 1,
		"the pre-latch kill is reconciled when the squad comes out (%d)" % camp.sequencer.guards_down())
	var local = game.controller.active_body(1)
	check(local != null, "the soul still has a body for the fight")

	var last_watcher = null
	for watcher in camp.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			last_watcher = watcher
			break
	var armed := await await_condition(
		func() -> bool: return camp.allies_armed() >= 1, 14.0, "the squad arming")
	check(armed, "a freed ally picks a weapon off the ground and holds it")
	var left := 0
	for pickup in camp.pickups():
		if is_instance_valid(pickup) and not bool(pickup.collected):
			left += 1
	check(left < 3, "the drop left the floor (%d left)" % left)
	check(camp.sequencer.weapons_taken() >= 1, "the pickup was booked as steel")

	var engaged := await await_condition(
		func() -> bool: return camp.ally_engaged(), 16.0, "the squad charging")
	check(engaged, "an armed ally closes on a watcher and swings")
	var hurt := await await_condition(
		func() -> bool: return _watcher_hurt(last_watcher), 14.0, "the squad landing blows")
	check(hurt, "an ally's swing actually wounds a watcher")

	var drops_before: int = game.pickups.size()
	var wave_two := await await_condition(
		func() -> bool: return camp.guards.size() == 8, 12.0, "the second wave")
	check(wave_two, "six more watchers come out of the trees (%d camp watchers)" % camp.guards.size())
	await create_timer(0.6).timeout
	var armed_reinforcements := 0
	var visible_blades := 0
	for index in range(2, camp.guards.size()):
		var watcher = camp.guards[index]
		check(bool(watcher.get("alive")), "reinforcement %d is on its feet" % index)
		if str(watcher.weapon_item) in ["sword_short", "dagger_iron", "sword_arming"]:
			armed_reinforcements += 1
		if watcher.has_weapon_visual():
			visible_blades += 1
		check(watcher.global_position.y > -1.0,
			"reinforcement %d did not fall out of the world (y=%.2f)" % [index, watcher.global_position.y])
	check(armed_reinforcements == 6, "every reinforcement carries a weapon (%d)" % armed_reinforcements)
	check(visible_blades == 6, "and the blade is in its hand (%d)" % visible_blades)

	var runner = null
	for index in range(2, camp.guards.size()):
		if is_instance_valid(camp.guards[index]) and bool(camp.guards[index].get("alive")):
			runner = camp.guards[index]
			break
	var prey = camp.nearest_standing_body(runner.global_position)
	var gap_before: float = runner.global_position.distance_to(prey.global_position)
	await create_timer(1.1).timeout
	check(is_instance_valid(runner) and bool(runner.get("alive")), "the runner is still alive")
	var gap_after: float = runner.global_position.distance_to(prey.global_position)
	check(gap_after < gap_before - 2.5, "the reinforcements run straight in (%.1f m -> %.1f m)"
		% [gap_before, gap_after])

	for index in range(2, camp.guards.size()):
		var watcher = camp.guards[index]
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(400.0, 0)
	var dropped := await await_condition(
		func() -> bool: return game.pickups.size() >= drops_before + 6, 6.0, "the dropped weapons")
	check(dropped, "the six weapons are on the floor (%d spawned)" % (game.pickups.size() - drops_before))

	var escaped := await await_condition(
		func() -> bool: return camp.sequencer.state() == SequencerScript.State.ESCAPING,
		14.0, "the escape opening")
	check(escaped, "the squad's fight opens the escape (%s)" % camp.sequencer.state_name())
	check(camp.sequencer.guards_down() == 8, "all eight watchers are down (%d)"
		% camp.sequencer.guards_down())
	check(camp.sequencer.hint().contains("trail"), "the escape's key line names the trail")
	check(not camp.sequencer.hint().to_lower().contains("arch"), "and not an arch")

	# The way out is a walk: the body crosses the mouth into the lane with real
	# movement, and nothing anywhere asks for a scene.
	local = game.controller.active_body(1)
	game.controller.input_enabled = false
	local.global_position = Vector3(0.0, 0.2, -30.0)
	await physics_frame
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var ticks := 0
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	while ticks < 3000:
		var to: Vector3 = lane[1] - local.global_position
		to.y = 0.0
		if to.length() <= 1.6:
			break
		var direction := to.normalized()
		local.accept_network_input(Vector2(direction.x, direction.z), false)
		await physics_frame
		ticks += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var out_of_the_clearing: bool = local.global_position.z < camp.YARD_FRONT
	check(out_of_the_clearing, "the body walked out through the mouth (z=%.1f)" % local.global_position.z)
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
