extends SceneTree
## Phase 3, wt-16: a battle becomes a record the warband keeps.
##
## The warband's save is the memory of the campaign, so the field has to hand it
## the truth on the way out: who fought, who is down, what was killed, looted and
## paid - and it must hand it over exactly once, whatever the file is loaded
## afterwards. This drives the real admin arena (a deployed line = an expedition)
## through a clear and a wipe, then hammers the save: reset, reload, compare every
## field of both reports, watch the purse and the essence wallet not move, load a
## v1 file that never held a report, and cap the history.
##
## Nothing here is a stand-in: the kills are real `take_damage` hits through the
## body's own funnel, the loot is the arena's own sweep, the reward is paid into
## the real wallets, and the report is filed by `Warband`, whose only hook is the
## `node_added` watcher it owns.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RunReportScript = preload("res://scripts/warband/run_report.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")
const State = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://run_persist_state.json"
const WARBAND_SAVE := "user://run_persist_warband.json"
const OLD_SAVE := "user://run_persist_v1.json"
const BOUND_SAVE := "user://run_persist_bound.json"

## Three bodies, five waves from the director: 3 + 4 + 4 + 5 + 6 cultists fall,
## each leaving a piece.
const WAVE_KILLS := 22
## The arena's own five battlefield drops plus the twenty-two the cult leaves behind.
const FIELD_DROPS := 5
const EXPECTED_ITEMS := WAVE_KILLS + FIELD_DROPS
## What the director pays on a clear: 25 gold a wave plus 50 for the Bilewarden,
## one ritual tallow a wave and one black bile at the boss.
const REWARD_GOLD := 175
const REWARD_CRUOR := 6
const TOWN_SCENE := "res://scenes/town_hub.tscn"

const LINEUP := [
	{"name": "Aldous", "main": "sword_short", "off": "shield_buckler", "armor": "leather"},
	{"name": "Brine", "main": "dagger_iron", "off": "shield_kite", "armor": "mail"},
	{"name": "Cael", "main": "bow_short", "off": "", "armor": "cloth"},
]

## A field with a wave manager and no guard nodes: what the close must read when a
## director fields bodies this module cannot classify (an escort, a boss).
class StubWaves:
	extends Node
	signal wave_started(index: int, count: int)
	signal wave_cleared(index: int)

	var cleared := 0
	var index := 0

	func total_cleared() -> int:
		return cleared

	func wave() -> int:
		return index

var game
var screen
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
		print("RUN_PERSIST_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _set_gold(amount: int) -> void:
	state.add_credits(amount - int(state.credits))

# --- the run ---------------------------------------------------------------

func run() -> void:
	for path in [TEST_SAVE, WARBAND_SAVE, OLD_SAVE, BOUND_SAVE]:
		_remove(path)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()
	_set_gold(1000)

	check(warband.run_history().is_empty(), "a fresh warband has fought nothing")
	check(warband.last_run().is_empty(), "and shows no last run")
	check(int(warband.run_record().get("runs")) == 0, "and has no record")

	await _clear_expedition()
	await _wipe_expedition()
	await _check_persistence()
	_check_screen()
	_check_old_save()
	_check_history_bound()
	_check_wave_tally()

	_finish()

## A deployed line, three waves, all twelve cultists dead, the field looted, the
## clear paid - then the survivors walk out through the town door, exactly as the
## campaign does it.
func _clear_expedition() -> void:
	_seed_lineup()
	var deployed: Array = warband.deployed_merc_ids()
	check(deployed.size() == 3, "three bodies take the field (%d)" % deployed.size())
	var holdings_before: int = _holdings()
	var stash_before: int = warband.stash.pooled_total()

	game = load("res://admin_arena.tscn").instantiate()
	game.scene_requested.connect(_on_scene_requested)
	root.add_child(game)
	await create_timer(0.5).timeout

	check(game.expedition, "a deployment line makes this a real battle")
	check(warband.run_open(), "Warband opens a record when the cult's waves appear")
	check(warband.run_history().is_empty(), "an open record is not yet history")

	# Walk whatever curve the director fields, rather than assuming its length:
	# the report must describe the battle that was really fought.
	var waves_seen := 1
	check(await _kill_wave(), "wave one falls")
	while not game._battle_over and waves_seen < 8:
		if not await _wait_wave(waves_seen):
			break
		waves_seen += 1
		check(await _kill_wave(), "wave %d falls" % waves_seen)
	check(game._battle_over, "the last wave ends the expedition")
	check(waves_seen == 5, "the director fielded five waves (%d)" % waves_seen)

	# The director paid on the clear, through the real wallets and never through
	# the report: nothing here hands the warband a second purse.

	check(await _wait_until(func(): return not game._loot_running, 25.0),
		"the survivors finish looting the field")
	await create_timer(0.3).timeout
	check(game.loot.pickups().is_empty(), "the field is bare (%d left)" % game.loot.pickups().size())

	game._request_return()
	check(returns.size() == 1 and returns[0] == TOWN_SCENE,
		"the field hands the warband back to town (%s)" % str(returns))
	await process_frame

	var report: Dictionary = warband.last_run()
	check(not report.is_empty(), "leaving the field files a report")
	check(not warband.run_open(), "the filed record is closed")
	check(warband.run_history().size() == 1, "the history holds exactly one record")
	check(str(report.get("mode")) == RunReportScript.MODE_EXPEDITION,
		"the record names the expedition (%s)" % str(report.get("mode")))
	check(str(report.get("outcome")) == RunReportScript.OUTCOME_CLEARED,
		"a battle where the warband stands is a clear (%s)" % str(report.get("outcome")))
	check(int(report.get("waves")) == 5, "five waves were fielded (%d)" % int(report.get("waves")))
	check(int(report.get("waves_cleared")) == 5,
		"five waves were broken (%d)" % int(report.get("waves_cleared")))
	check(int(report.get("kills")) == WAVE_KILLS,
		"the twenty-two cultists are counted (%d)" % int(report.get("kills")))
	check(int(report.get("items")) == EXPECTED_ITEMS,
		"five field drops and twenty-two cultist drops are booked (%d)" % int(report.get("items")))
	check(int(report.get("items")) == _holdings() - holdings_before,
		"the item count matches what the warband gained (%d vs %d)" % [
			int(report.get("items")), _holdings() - holdings_before])
	check(warband.stash.pooled_total() - stash_before <= EXPECTED_ITEMS,
		"loot that went straight onto a body is not double counted")
	check(int(report.get("gold")) == REWARD_GOLD,
		"the gold the run paid is recorded (%d)" % int(report.get("gold")))
	check(int(report.get("cruor")) == REWARD_CRUOR,
		"the cruor the run paid is recorded (%d)" % int(report.get("cruor")))
	check(int(report.get("ended_at")) >= int(report.get("started_at")),
		"the end stamp follows the start")
	check(int(report.get("seconds")) >= 0, "the battle has a duration")

	var bodies: Array = report.get("bodies", [])
	check(bodies.size() == 3, "one outcome per body that took the field (%d)" % bodies.size())
	check(_count_state(bodies, RunReportScript.STATE_ALIVE) == 3,
		"the survivors are recorded alive (%d)" % _count_state(bodies, RunReportScript.STATE_ALIVE))
	_check_bodies_match_roster(bodies, "the clear")

	var totals: Dictionary = warband.run_record()
	check(int(totals.get("runs")) == 1, "the record counts one run")
	check(int(totals.get("wins")) == 1, "and one clear")
	check(int(totals.get("wipes")) == 0, "and no wipe")
	check(int(totals.get("best_wave")) == 5, "the best wave is five (%d)" % int(totals.get("best_wave")))
	check(int(totals.get("kills")) == WAVE_KILLS, "the kills accumulate")
	check(int(totals.get("gold")) == REWARD_GOLD and int(totals.get("cruor")) == REWARD_CRUOR,
		"the lifetime rewards accumulate")

## A second battle: one cultist dies, then the whole warband goes down. Left
## through the scene's own `_exit_tree()`, which is where the save happens.
func _wipe_expedition() -> void:
	game.queue_free()
	await process_frame
	game = null
	# The first field's survivors stand back up for the second one.
	warband.roster.restore_all()
	warband.deploy_battle(warband.roster.alive_ids())
	check(warband.deployed_merc_ids().size() == 3, "three bodies deploy for the second run")

	game = load("res://admin_arena.tscn").instantiate()
	game.scene_requested.connect(_on_scene_requested)
	root.add_child(game)
	await create_timer(0.5).timeout
	check(warband.run_open(), "a second battle opens a second record")
	check(warband.run_history().size() == 1, "the first record is still there")

	var guards: Array = game.waves.guards()
	if not guards.is_empty():
		guards[0].take_damage(5000.0, 1)
	await process_frame
	for actor in game.bodies:
		if is_instance_valid(actor) and bool(actor.get("alive")):
			actor.enter_downed(99)
	# The arena mirrors the bodies into the roster every 0.4 s.
	await create_timer(0.7).timeout
	check(warband.roster.alive_count() == 0, "nobody is left standing")

	game.queue_free()
	await process_frame
	game = null

	var report: Dictionary = warband.last_run()
	check(warband.run_history().size() == 2, "the wipe is filed beside the clear")
	check(str(report.get("outcome")) == RunReportScript.OUTCOME_WIPED,
		"a field with nobody standing is a wipe (%s)" % str(report.get("outcome")))
	check(int(report.get("waves")) == 1, "the wipe happened in wave one (%d)" % int(report.get("waves")))
	check(int(report.get("waves_cleared")) == 0, "no wave was broken")
	check(int(report.get("kills")) == 1, "the one cultist that died is counted (%d)"
		% int(report.get("kills")))
	check(int(report.get("items")) == 0, "a wipe gathers nothing (%d)" % int(report.get("items")))
	check(int(report.get("gold")) == 0 and int(report.get("cruor")) == 0,
		"a wipe pays nothing")
	var bodies: Array = report.get("bodies", [])
	check(_count_state(bodies, RunReportScript.STATE_DOWNED) == 3,
		"every body is recorded downed (%s)" % str(_states(bodies)))

	var totals: Dictionary = warband.run_record()
	check(int(totals.get("runs")) == 2, "two runs are counted")
	check(int(totals.get("wins")) == 1 and int(totals.get("wipes")) == 1,
		"a wipe is tallied apart from a clear")
	check(int(totals.get("best_wave")) == 5,
		"a shorter run never lowers the best wave (%d)" % int(totals.get("best_wave")))
	check(int(totals.get("kills")) == WAVE_KILLS + 1, "kills add up across runs")

# --- the save --------------------------------------------------------------

func _check_persistence() -> void:
	var before: Array = warband.run_history()
	check(before.size() == 2, "two records are on file")
	var gold_before: int = int(state.credits)
	var cruor_before: int = warband.cruor.total()
	var totals_before: Dictionary = warband.run_record()

	warband.save_state()
	var text := FileAccess.get_file_as_string(WARBAND_SAVE)
	check(text.contains("\"runs\""), "the save carries the history")
	check(text.contains("\"run_totals\""), "the save carries the lifetime totals")
	check(text.contains("\"bodies\""), "and each report carries its bodies")

	warband.reset_state()
	check(warband.run_history().is_empty(), "reset forgets the history")
	check(warband.last_run().is_empty(), "reset forgets the last run")
	check(int(warband.run_record().get("runs")) == 0, "reset forgets the record")
	check(int(state.credits) == gold_before, "reset never touches the purse")

	check(warband.load_state(), "the warband loads")
	var after: Array = warband.run_history()
	check(after.size() == 2, "both records come back")
	_check_report_equal(before[0], after[0], "the clear")
	_check_report_equal(before[1], after[1], "the wipe")
	check(str(after[1].get("outcome")) == RunReportScript.OUTCOME_WIPED,
		"the newest record is still the wipe")
	var totals_after: Dictionary = warband.run_record()
	for key in RunReportScript.TOTAL_FIELDS:
		check(int(totals_after.get(key)) == int(totals_before.get(key)),
			"the lifetime total %s round-trips (%s vs %s)" % [
				key, str(totals_after.get(key)), str(totals_before.get(key))])

	# A reload replays the ledger; it never pays it again.
	check(int(state.credits) == gold_before,
		"reloading never pays the run's gold again (%d vs %d)" % [
			int(state.credits), gold_before])
	check(warband.cruor.total() == cruor_before,
		"reloading never pays the cruor again (%d vs %d)" % [
			warband.cruor.total(), cruor_before])
	check(int(after[0].get("gold")) == REWARD_GOLD,
		"the clear's record still shows what was earned")

	# The bodies survive the trip with their real health and state.
	var bodies: Array = after[0].get("bodies", [])
	check(bodies.size() == 3, "the clear's bodies come back")
	for entry in bodies:
		var body: Dictionary = entry
		var merc_id := _merc_named(str(body.get("name", "")))
		check(merc_id > 0, "%s is still in the roster" % str(body.get("name", "")))
		if merc_id <= 0:
			continue
		check(float(body.get("max_health")) == warband.roster.max_health_of(merc_id),
			"%s keeps its maximum health" % str(body.get("name", "")))

## An old save is a warband without a ledger: it must load, and it must not
## invent a battle.
func _check_old_save() -> void:
	warband.reset_state()
	warband.add_mercenary("Old Kestrel")
	warband.stash.add("ring_blood", 2)
	var blob: Dictionary = warband.to_dict()
	blob["version"] = 1
	blob.erase("runs")
	blob.erase("run_totals")
	var file := FileAccess.open(OLD_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(blob, "\t"))
	file.close()

	warband.save_path = OLD_SAVE
	check(warband.load_state(), "a version 1 save still loads")
	check(warband.roster.count() == 1, "and its roster is intact")
	check(warband.stash.pooled_count("ring_blood") == 2, "and its stash is intact")
	check(warband.run_history().is_empty(), "and it has no history rather than an error")
	check(warband.last_run().is_empty(), "and no last run")
	var totals: Dictionary = warband.run_record()
	check(int(totals.get("runs")) == 0 and int(totals.get("best_wave")) == 0,
		"and its record starts empty")
	check(warband.run_open() == false, "and no battle is open")
	warband.save_path = WARBAND_SAVE

## The history is bounded: a save with more than the cap keeps the newest 20.
func _check_history_bound() -> void:
	warband.reset_state()
	warband.add_mercenary("Bound")
	var blob: Dictionary = warband.to_dict()
	var entries: Array = []
	for index in 25:
		var report := RunReportScript.new()
		report.mode = RunReportScript.MODE_EXPEDITION
		report.outcome = RunReportScript.OUTCOME_CLEARED
		report.started_at = 1000 + index
		report.ended_at = 1010 + index
		report.seconds = 10
		report.waves = 1 + index
		report.waves_cleared = 1 + index
		report.kills = index
		report.bodies.append({"name": "Bound", "health": 100.0, "max_health": 100.0,
			"state": RunReportScript.STATE_ALIVE})
		entries.append(report.to_dict())
	blob["runs"] = entries
	blob["run_totals"] = {"runs": 25, "wins": 25, "best_wave": 25, "kills": 300}
	var file := FileAccess.open(BOUND_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(blob, "\t"))
	file.close()

	warband.save_path = BOUND_SAVE
	check(warband.load_state(), "a save over the history cap still loads")
	var history: Array = warband.run_history()
	check(history.size() == RunReportScript.HISTORY_LIMIT,
		"the history is capped at %d (%d)" % [RunReportScript.HISTORY_LIMIT, history.size()])
	if history.size() == RunReportScript.HISTORY_LIMIT:
		check(int(history[0].get("started_at")) == 1005,
			"the oldest five are dropped (%d)" % int(history[0].get("started_at")))
		check(int(history.back().get("started_at")) == 1024, "the newest report is kept")
	check(int(warband.run_record().get("runs")) == 25, "the lifetime totals are not trimmed")
	warband.save_path = WARBAND_SAVE

## The spawner's own tally is the fallback for kills this node never saw a signal
## for, and the wave index is the floor for the waves fielded.
func _check_wave_tally() -> void:
	warband.reset_state()
	warband.add_mercenary("Stub")
	var stub := StubWaves.new()
	root.add_child(stub)
	check(warband.begin_run("expedition", stub) != null, "a scene can open its own record")
	stub.index = 1
	stub.cleared = 5
	var filed: Dictionary = warband.finish_run(RunReportScript.OUTCOME_CLEARED)
	check(int(filed.get("kills")) == 5,
		"the spawner's tally is read when the tree saw no kills (%d)" % int(filed.get("kills")))
	check(int(filed.get("waves")) == 2,
		"the spawner's wave index gives the waves fielded (%d)" % int(filed.get("waves")))
	check(int(filed.get("waves_cleared")) == 0, "and no wave was announced as broken")
	check(not warband.run_open(), "the record is closed")
	stub.queue_free()

# --- the screen ------------------------------------------------------------

## The roster screen shows the last run and the record without owning either.
func _check_screen() -> void:
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	check(warband.load_state(), "the filed battle loads for the screen")
	screen = ScreenScript.new()
	root.add_child(screen)
	screen.configure(warband, warband.souls)
	screen.open()

	check(screen.last_run_label.text.contains("Wiped"),
		"the block names the last verdict (%s)" % screen.last_run_label.text)
	check(screen.last_run_label.text.contains("1 kills"),
		"the block counts the kills (%s)" % screen.last_run_label.text)
	check(screen.last_run_label.text.contains("0 of 1 waves cleared"),
		"the block tells waves reached from waves broken (%s)" % screen.last_run_label.text)
	check(screen.record_label.text.contains("2 run(s)"),
		"the block shows the lifetime runs (%s)" % screen.record_label.text)
	check(screen.record_label.text.contains("best wave 5"),
		"the block shows the best wave (%s)" % screen.record_label.text)
	check(screen.record_label.text.contains("1 clear(s)") and
		screen.record_label.text.contains("1 wipe(s)"),
		"the block tells clears from wipes (%s)" % screen.record_label.text)
	check(screen.run_bodies_label.text.contains("downed"),
		"the block lists the downed bodies (%s)" % screen.run_bodies_label.text)
	check(screen.run_bodies_label.text.contains("Aldous"),
		"the block lists the bodies that fought (%s)" % screen.run_bodies_label.text)

	# A warband with no history says so instead of showing an old battle.
	warband.reset_state()
	screen.refresh()
	check(screen.last_run_label.text == "No battle recorded yet.",
		"an empty ledger says so (%s)" % screen.last_run_label.text)
	check(screen.record_label.text.contains("no battles fought yet"),
		"and the record line says so too (%s)" % screen.record_label.text)
	check(screen.run_bodies_label.text.is_empty(), "and no body line is shown")
	screen.close()

# --- drivers ---------------------------------------------------------------

func _on_scene_requested(path: String) -> void:
	returns.append(path)
	# What `GameFlow.goto()` does with the warband before the scene changes.
	warband.save_state()

func _seed_lineup() -> void:
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
	warband.deploy_battle(ids)

## Kill whatever wave is standing, through the real damage funnel.
func _kill_wave() -> bool:
	if game == null or game.waves == null:
		return false
	var deadline := Time.get_ticks_msec() + 8000
	while game.waves.living() > 0 and Time.get_ticks_msec() < deadline:
		for guard in game.waves.guards():
			if is_instance_valid(guard) and bool(guard.get("alive")):
				guard.take_damage(5000.0, 1)
		await process_frame
	return game.waves.living() == 0

func _wait_wave(index: int) -> bool:
	return await _wait_until(func(): return game != null and game.waves.wave() == index, 10.0)

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await create_timer(0.1).timeout
	return bool(predicate.call())

# --- comparisons -----------------------------------------------------------

func _check_report_equal(expected: Dictionary, actual: Dictionary, label: String) -> void:
	check(expected.keys().size() == actual.keys().size(),
		"%s keeps exactly its keys (%d vs %d)" % [label, expected.keys().size(),
			actual.keys().size()])
	for field in RunReportScript.FIELDS:
		var want: Variant = expected.get(field)
		var got: Variant = actual.get(field)
		if field == "bodies":
			check(want is Array and got is Array and (want as Array).size() == (got as Array).size(),
				"%s: every body survives the save" % label)
			_check_bodies_equal(want, got, label)
			continue
		check(typeof(want) == typeof(got),
			"%s: %s keeps its type (%s vs %s)" % [label, field, type_string(typeof(want)),
				type_string(typeof(got))])
		check(want == got, "%s: %s round-trips (%s vs %s)" % [label, field, str(want), str(got)])

func _check_bodies_equal(expected: Variant, actual: Variant, label: String) -> void:
	if not expected is Array or not actual is Array:
		return
	var want: Array = expected
	var got: Array = actual
	for index in mini(want.size(), got.size()):
		var left: Dictionary = want[index]
		var right: Dictionary = got[index]
		for field in ["name", "health", "max_health", "state"]:
			check(right.has(field) and left.get(field) == right.get(field),
				"%s: body %d %s round-trips (%s vs %s)" % [label, index, field,
					str(left.get(field)), str(right.get(field))])

## The report's bodies are the roster as the arena left it: same names, same
## health, same state.
func _check_bodies_match_roster(bodies: Array, label: String) -> void:
	for entry in bodies:
		var body: Dictionary = entry
		var merc_id := _merc_named(str(body.get("name", "")))
		check(merc_id > 0, "%s: %s is in the roster" % [label, str(body.get("name", ""))])
		if merc_id <= 0:
			continue
		check(str(body.get("state")) == RunReportScript.state_key(warband.roster.state_of(merc_id)),
			"%s: %s's state is the roster's (%s vs %s)" % [label, str(body.get("name", "")),
				str(body.get("state")), RunReportScript.state_key(warband.roster.state_of(merc_id))])
		check(is_equal_approx(float(body.get("health")),
			roundf(warband.roster.health_of(merc_id) * 10.0) / 10.0),
			"%s: %s's health is the roster's (%s vs %s)" % [label, str(body.get("name", "")),
				str(body.get("health")), str(warband.roster.health_of(merc_id))])

## Everything the warband owns: the shared stash plus every worn piece. A piece
## looted straight onto a body counts once, so this is what a battle should add.
func _holdings() -> int:
	var total: int = warband.stash.pooled_total()
	for merc_id in warband.roster.ids():
		var gear: Dictionary = warband.roster.equipped_of(int(merc_id))
		for slot in gear:
			if not str(gear[slot]).is_empty():
				total += 1
	return total

func _merc_named(merc_name: String) -> int:
	for merc_id in warband.roster.ids():
		if warband.roster.name_of(int(merc_id)) == merc_name:
			return int(merc_id)
	return -1

func _count_state(bodies: Array, key: String) -> int:
	var count := 0
	for entry in bodies:
		if entry is Dictionary and str((entry as Dictionary).get("state", "")) == key:
			count += 1
	return count

func _states(bodies: Array) -> Array:
	var out: Array = []
	for entry in bodies:
		if entry is Dictionary:
			out.append(str((entry as Dictionary).get("state", "")))
	return out

func _finish() -> void:
	if screen != null:
		screen.queue_free()
	if game != null:
		game.queue_free()
	await process_frame
	Damage.reset()
	warband.reset_state()
	state.reset(false)
	for path in [TEST_SAVE, WARBAND_SAVE, OLD_SAVE, BOUND_SAVE]:
		_remove(path)
	print("RUN_PERSISTENCE_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
