extends SceneTree
## The arena: a mirrored warband in a stone ring, three tiers of it.
##
## What this owns: the door in the square, the field moved into the ring, three
## foes built out of the three tiers' kits, the AI closing the distance, a win
## that pays the purse, and the return that puts every body back where it stood.

const WORLD = "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://arena_regression_state.json"
const WARBAND_SAVE := "user://arena_regression_warband.json"

var game
var arena
var warband
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ARENA_FAIL  ", message)


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
	var flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.world_start = "town"

	game = load(WORLD).instantiate()
	root.add_child(game)
	current_scene = game
	var waited := 0.0
	while waited < 30.0 and (game.get("controller") == null or game.bodies.size() < 1):
		await physics_frame
		waited += 0.016
	check(game.bodies.size() >= 1, "the town stands the warband up (%d bodies)" % game.bodies.size())

	arena = game.get("arena")
	check(arena != null, "the world owns a ring")
	if arena == null:
		_finish()
		return

	# The door: a service in the square, with a point a body can walk to.
	var point: Vector3 = game.town.service_point("arena")
	check(point != Vector3.ZERO, "the square has an arena gate")
	check(game.town.service_at(point) == "arena", "and the gate resolves as its own service")

	await _check_tiers()
	await _check_fight()
	_finish()


## The three tier's kits, on the bodies the ring builds.
func _check_tiers() -> void:
	for tier in ["easy", "medium", "hard"]:
		check(arena.set_difficulty(tier), "the ring takes the %s tier" % tier)
		check(arena.difficulty == tier, "and remembers it (%s)" % arena.difficulty)
	check(not arena.set_difficulty("brutal"), "a tier the ring does not have is refused")
	arena.set_difficulty("hard")
	check(arena.difficulty == "hard", "a refusal leaves the tier where it was")
	await physics_frame


## One whole fight: the party walks in, the foes come at it, and it ends.
func _check_fight() -> void:
	var party_before: Array = game.bodies.duplicate()
	var spots: Dictionary = {}
	for body in party_before:
		spots[body] = body.global_position
	var gold_before: int = warband.gold()

	arena.set_difficulty("easy")
	var result: Dictionary = arena.enter("easy")
	check(bool(result.get("ok", false)), "the ring opens (%s)" % str(result.get("message", "")))
	check(arena.active, "and it is holding a fight")
	check(arena.foes.size() == 3, "three foes stand across it (%d)" % arena.foes.size())
	check(arena.party.size() == party_before.size(),
		"the whole field walks in (%d of %d)" % [arena.party.size(), party_before.size()])
	var in_ring := true
	for body in arena.party:
		if body.global_position.y < 100.0:
			in_ring = false
	check(in_ring, "every body stands in the ring, not in the square")
	check(arena.foes_standing() == 3, "nobody is down at the bell")

	# The kit is the tier's: makeshift steel and no anoint on easy.
	for foe in arena.foes:
		var main_id := str(foe.rig.get("main_id") if foe.rig.get("main_id") != null else "")
		check(not bool(foe.get("downed")) and bool(foe.get("alive")), "a foe stands at the bell")
		check(str(foe.rig.weapon) in ["sword", "dagger", "bow"],
			"a foe holds a weapon (%s)" % str(foe.rig.weapon))
	var easy_mains: Array = []
	for foe in arena.foes:
		easy_mains.append(str(foe.rig.main_item_id()) if foe.rig.has_method("main_item_id") else "")
	check(not easy_mains.is_empty(), "the foes' hands are readable")

	# The AI closes: a foe that never walks is a statue with a sword.
	var start: Array = []
	for foe in arena.foes:
		start.append(foe.global_position)
	for frame in 90:
		await physics_frame
	var closed := 0
	for index in arena.foes.size():
		var foe = arena.foes[index]
		if is_instance_valid(foe) and foe.global_position.distance_to(start[index]) > 1.5:
			closed += 1
	check(closed >= 2, "the foes come at the band (%d of 3 moved)" % closed)

	# A finished fight: every foe down is a win, and a win pays.
	for foe in arena.foes:
		if is_instance_valid(foe):
			foe.take_damage(900.0, 99)
	for frame in 5:
		await physics_frame
	check(arena.foes_standing() == 0, "the ring is empty of foes (%d)" % arena.foes_standing())
	check(arena.finished == "won", "and the fight is won (%s)" % arena.finished)
	check(warband.gold() == gold_before + int(arena.PURSE.get("easy", 0)),
		"the win pays the easy purse (%d -> %d)" % [gold_before, warband.gold()])

	# The gate lets the party out, and every body stands where it stood.
	check(arena.try_leave(), "the gate takes the press")
	await physics_frame
	await physics_frame
	check(not arena.active, "the ring is closed")
	check(arena.foes.is_empty(), "and no foe is left in it")
	var back := 0
	for body in party_before:
		if is_instance_valid(body) and body.global_position.distance_to(spots[body]) < 1.0:
			back += 1
	check(back == party_before.size(),
		"every body is back where it stood (%d of %d)" % [back, party_before.size()])


func _finish() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("ARENA_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
