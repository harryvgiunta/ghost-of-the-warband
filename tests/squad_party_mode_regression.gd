extends SceneTree
## The party's mode on the real world: how the squad picks its fights. The mode is
## the warband's (`Warband.set_party_mode`, set from the warband menu), and the world
## hands it to its one squad every frame.
##
##   1. OFFENSIVE goes looking: an ally goes in on a hostile that has done nothing.
##   2. DEFENSIVE answers: a hostile that has done nothing is left alone, and so is
##      one a third party wounded; a blow it lands on the ally through the world's
##      own handler is a fight, and so is a hostile the soul cut first.
##   3. PASSIVE fights nothing: a hostile that struck the ally and that the soul cut
##      is left alone while the ally keeps to the soul - and put back on DEFENSIVE,
##      the band goes in on it at once, because the book is kept in every mode.
##
## Every hostile here stands frozen (no tick of its own), so nothing it does by
## itself can be why the squad went in or stayed out; the town's watch is stood
## down for the same reason, and its arrow is asked for once, by hand.
##
## A campaign opens with one naked body (`Warband.STARTING_BAND`) - the soul's -
## so this harness swears the second body the AI drives and arms it out of the
## shared stash itself: a band of one has nobody else to measure.

const WORLD := "res://scenes/warband_world.tscn"
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

const TEST_SAVE := "user://squad_party_mode_state.json"
const WARBAND_SAVE := "user://squad_party_mode_warband.json"
## How far from the ally a hostile stands: well inside the squad's engage radius.
const NEAR := 6.0
## Frames a squad gets to go in on something it may fight, and frames a squad that
## must not is watched for.
const GO_IN_FRAMES := 240
const HOLD_FRAMES := 90
## The source an arrow from the town's watch books its wound under (`arrow.gd`'s
## default): nobody in the band.
const WATCH_SOURCE := -1
## An escort further than this from the soul is walking the soul's footprints to
## catch up rather than holding its post (`SquadDrive.ESCORT_RALLY`).
const WITH_THE_SOUL := 9.0

var game
var warband
var soul
var ally
var ally_id := 0
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("SQUAD_PARTY_MODE_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	# The campaign opens with one naked body (`Warband.STARTING_BAND`): the soul's.
	# This test needs a second body for the AI to drive, so one is sworn here and
	# armed out of the pool by hand - the square stocks the stash, never a body.
	warband.seed_starting_band()
	var sworn: int = warband.add_mercenary("Brine")
	warband.stash.add("sword_short", 1)
	check(bool(warband.dress_recruit(sworn).get("ok", false)),
		"a second body is sworn and armed for the AI to drive")
	var flow = root.get_node("GameFlow")
	flow.active = false
	# The town start, both bodies standing, and no lesson.
	flow.world_start = "town"
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	if _find_bodies():
		if game.town != null:
			for guard in game.town.guards:
				(guard as Node).process_mode = Node.PROCESS_MODE_DISABLED
		check(warband.party_mode == Contracts.DEFAULT_PARTY_MODE
				and warband.party_mode == Contracts.PARTY_DEFENSIVE,
			"a fresh band answers rather than hunts (%s)" % str(warband.party_mode))
		await check_offensive()
		await check_defensive()
		await check_passive()
	print("SQUAD_PARTY_MODE_REGRESSION checks=", checks, " failures=", failures)
	game.queue_free()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	quit(0 if failures == 0 else 1)


func _find_bodies() -> bool:
	var controller = game.controller
	soul = controller.body_of(controller.merc_for_peer(1))
	check(soul != null, "the soul starts in a body")
	for raw_id in game.squad.squad_ids:
		var body = controller.body_of(int(raw_id))
		if body == null or not is_instance_valid(body) or body == soul:
			continue
		if not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		ally = body
		ally_id = int(raw_id)
		break
	check(ally != null, "the band has a body the AI drives")
	return soul != null and ally != null


# --- 1. offensive ------------------------------------------------------------

func check_offensive() -> void:
	var result: Dictionary = warband.set_party_mode(Contracts.PARTY_OFFENSIVE)
	check(bool(result.get("ok", false)),
		"the band takes OFFENSIVE (%s)" % str(result.get("message", "")))
	var hostile = spawn_hostile("Idle")
	check(await goes_in(), "OFFENSIVE: an ally goes in on a hostile that has done nothing")
	await remove_hostile(hostile)


# --- 2. defensive ------------------------------------------------------------

func check_defensive() -> void:
	var result: Dictionary = warband.set_party_mode(Contracts.PARTY_DEFENSIVE)
	check(bool(result.get("ok", false)), "the band takes DEFENSIVE (%s)" % str(result.get("message", "")))
	var striker = spawn_hostile("Striker")
	check(await stays_out(), "DEFENSIVE: a hostile that has done nothing is left alone")
	striker.take_damage(1.0, WATCH_SOURCE)
	check(await stays_out(), "and so is one a third party wounded")
	# Its blow on the ally, through the world's own handler, as every area's mob lands one.
	striker.attacked.emit(striker, 1.0, ally)
	check(await goes_in(), "a hostile that struck one of the band is a fight")
	await remove_hostile(striker)

	var cut = spawn_hostile("Cut")
	check(await stays_out(), "a fresh hostile beside the ally is left alone")
	# The soul's own blade: the mob's damage path books the soul body's slot.
	cut.take_damage(1.0, int(soul.slot))
	check(await goes_in(), "a hostile the soul cut first is a fight (soul slot %d)" % int(soul.slot))
	await remove_hostile(cut)


# --- 3. passive --------------------------------------------------------------

func check_passive() -> void:
	warband.set_party_mode(Contracts.PARTY_PASSIVE)
	var chaser = spawn_hostile("Chaser")
	chaser.attacked.emit(chaser, 1.0, ally)
	chaser.take_damage(1.0, int(soul.slot))
	check(await stays_out(),
		"PASSIVE: a hostile that struck the ally and that the soul cut is left alone")
	var gap: float = (ally as Node3D).global_position.distance_to((soul as Node3D).global_position)
	check(gap <= WITH_THE_SOUL, "and the ally keeps to the soul (%.1f m)" % gap)
	warband.set_party_mode(Contracts.PARTY_DEFENSIVE)
	check(await goes_in(), "put back on DEFENSIVE, the band answers what struck it while passive")
	await remove_hostile(chaser)
	warband.set_party_mode(Contracts.PARTY_OFFENSIVE)


# --- the hostile and the reading -------------------------------------------

## A hostile beside the ally that does nothing of its own: frozen, on the world's
## hostile list, and wired to the world's blow handler the way every area wires
## its mobs.
func spawn_hostile(label: String):
	var hostile = WatcherScript.new()
	hostile.name = label
	hostile.mob_id = "hollow_warden"
	hostile.health_pool = 400.0
	hostile.process_mode = Node.PROCESS_MODE_DISABLED
	game.add_child(hostile)
	hostile.global_position = (ally as Node3D).global_position + Vector3(NEAR, 0.0, 0.0)
	hostile.attacked.connect(Callable(game, "_on_enemy_attack"))
	game.guards.append(hostile)
	return hostile


func remove_hostile(hostile) -> void:
	game.guards.erase(hostile)
	hostile.queue_free()
	for index in HOLD_FRAMES:
		await physics_frame
		if not engaged():
			return
	check(false, "the ally is out of the fight once its hostile is gone")


## Whether the ally is in a fight, as the band's notifier reads it.
func engaged() -> bool:
	for row in game.squad.engaged_allies():
		if int(row["merc_id"]) == ally_id:
			return true
	return false


func goes_in() -> bool:
	for index in GO_IN_FRAMES:
		await physics_frame
		if engaged():
			return true
	return false


func stays_out() -> bool:
	for index in HOLD_FRAMES:
		await physics_frame
		if engaged():
			return false
	return true
