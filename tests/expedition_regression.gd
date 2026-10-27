extends SceneTree
## Phase Gate 2, the battle half: a deployed warband walks into the arena and
## fights cultist waves, and the survivors physically loot the field before the
## vacuum books it.
##
## The sandbox brawls are the bubble demo; an expedition is a real battle. The
## arena decides which one it is from the warband's deployment line, exactly as
## the town gate writes it.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const State = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://expedition_state.json"
const WARBAND_SAVE := "user://expedition_warband.json"
const LINEUP := [
	{"name": "Aldous", "main": "sword_short", "off": "shield_buckler", "armor": "leather"},
	{"name": "Brine", "main": "dagger_iron", "off": "shield_kite", "armor": "mail"},
	{"name": "Cael", "main": "bow_short", "off": "", "armor": "cloth"},
	{"name": "Dorn", "main": "sword_great", "off": "", "armor": "plate"},
	{"name": "Edda", "main": "sword_arming", "off": "shield_tower", "armor": "mail"},
	{"name": "Fenwick", "main": "sword_short", "off": "dagger_iron", "armor": "leather"},
]

var game
var warband
var state
var checks := 0
var failures := 0
var returns: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("EXPEDITION_FAIL  ", message)

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

	var ids: Array[int] = []
	for entry in LINEUP:
		var merc_id: int = warband.add_mercenary(str(entry["name"]))
		var main_id := str(entry["main"])
		warband.roster.equip(merc_id, "main", main_id)
		var off_id := str(entry["off"])
		if not off_id.is_empty() and not Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
			warband.roster.equip(merc_id, "off", off_id)
		for slot in ["head", "chest", "hands", "legs", "feet"]:
			var armor_id := "armor_%s_%s" % [str(entry["armor"]), slot]
			if State.ITEMS.has(armor_id):
				warband.roster.equip(merc_id, slot, armor_id)
		ids.append(merc_id)
	var fielded: Array = warband.deploy_battle(ids.slice(0, 4))
	check(fielded.size() == 4, "four mercenaries are deployed")

	game = load("res://admin_arena.tscn").instantiate()
	game.scene_requested.connect(func(path: String): returns.append(path))
	root.add_child(game)
	await create_timer(0.6).timeout

	check(game.expedition, "a deployment line makes this a real battle")
	check(game.bodies.size() == 4, "only the deployed line takes the field (%d)" % game.bodies.size())
	check(game.waves != null, "the cult walks in")
	if game.waves == null:
		_finish()
		return
	check(game.waves.living() == 3, "wave one is three cultists")
	check(game.groups.is_empty(), "the sandbox brawls are not built")

	# A cultist within reach really threatens a warband body.
	var body = game.bodies[1]
	var guard = game.waves.guards()[0] if not game.waves.guards().is_empty() else null
	if guard != null:
		guard.global_position = body.global_position + Vector3(1.4, 0, 0)
		var before: float = body.health
		await create_timer(3.5).timeout
		check(body.health < before, "a cultist guard takes health off a warband body")

	var first_cleared := await _clear_wave()
	check(first_cleared, "wave one is cleared")
	check(game.loot.pickups().size() >= 3, "the dead cultists left gear (%d)" % game.loot.pickups().size())

	check(await _wait_wave(1), "wave two arrives on its own")
	check(game.waves.living() == 4, "wave two is four cultists")
	await _clear_wave()
	check(await _wait_wave(2), "wave three arrives")
	check(game.waves.living() == 5, "wave three is five cultists")

	# Stand the survivors near the cult so the loot jog is a short one.
	for actor in game.bodies:
		if bool(actor.get("alive")) and not bool(actor.get("downed")):
			actor.global_position = Vector3(actor.global_position.x, 0.1, -10.0)
	var stash_before: int = warband.stash.pooled_total()
	await _clear_wave()
	check(game._battle_over, "clearing the last wave ends the expedition")
	check(game._loot_running, "the survivors are sent to loot the field")
	var jogged := await _wait_until(func(): return not game._loot_running, 20.0)
	check(jogged, "the loot run finishes")
	await create_timer(0.4).timeout
	check(warband.stash.pooled_total() > stash_before,
		"the field lands in the shared stash (%d -> %d)" % [stash_before, warband.stash.pooled_total()])

	game._request_return()
	check(returns.size() == 1 and returns[0] == "res://scenes/town_hub.tscn",
		"the field hands the warband back to town (%s)" % str(returns))

	_finish()

func _finish() -> void:
	if game != null:
		game.queue_free()
		await process_frame
	Damage.reset()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("EXPEDITION_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

## Kill whatever wave is standing, through the real damage funnel.
func _clear_wave() -> bool:
	if game.waves == null:
		return false
	var deadline := Time.get_ticks_msec() + 5000
	while game.waves.living() > 0 and Time.get_ticks_msec() < deadline:
		for guard in game.waves.guards():
			if is_instance_valid(guard) and bool(guard.get("alive")):
				guard.take_damage(5000.0, 1)
		await process_frame
	return game.waves.living() == 0

func _wait_wave(index: int) -> bool:
	return await _wait_until(func(): return game.waves.wave() == index, 8.0)

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await create_timer(0.1).timeout
	return bool(predicate.call())
