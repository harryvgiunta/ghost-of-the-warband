extends SceneTree
## The altar's rack: a weld is a row with a price, and the same books always give
## the same steel. What this owns: the options a copy offers, the price each one
## asks, the refusal of a weld the piece cannot take or the purse cannot pay, and
## the certainty that pays out the same way twice.

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const CruorManager = preload("res://scripts/warband/cruor_manager.gd")

const WARBAND_SAVE := "user://weld_regression_warband.json"
const STATE_SAVE := "user://weld_regression_state.json"

var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WELD_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(WARBAND_SAVE)
	_remove(STATE_SAVE)
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = STATE_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	warband.add_mercenary("Weld", {"main": "bow_short"})
	warband.stash.add("sword_short", 1)
	warband.stash.add(CruorManager.BASIC_REAGENT, 8)
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 40)
	warband.cruor.add(Contracts.CruorTier.T2_BLACK_BILE, 20)

	var options: Array = warband.weld_options("sword_short", 0)
	check(not options.is_empty(), "the rack lists welds for a plain sword (%d)" % options.size())
	var abilities := 0
	var priced := true
	for row in options:
		if int(row["kind"]) == 0:
			abilities += 0
		check(int(row["cost_count"]) > 0, "every row names a price")
		check(str(row["cost_name"]) != "", "and the tier it is paid in (%s)" % str(row["cost_name"]))
		if int(row["cost_count"]) <= 0:
			priced = false
	check(priced, "every row is priced")
	var ability_row: Dictionary = {}
	for row in options:
		if str(row["kind_name"]) == "ABILITY":
			ability_row = row
			break
	check(not ability_row.is_empty(), "an ability weld is on the rack")
	if ability_row.is_empty():
		_finish()
		return

	# A weld the piece cannot take is refused, and costs nothing.
	var before_gold: int = warband.gold()
	var refused: Dictionary = warband.weld("ring_copper", 0, str(ability_row["entry_id"]))
	check(not bool(refused.get("ok", true)), "a piece that cannot take it says so")
	check(warband.gold() == before_gold, "and nothing is paid for a refusal")

	# The same weld, twice, gives the same steel both times: the price and the
	# row are the whole decision, and there is no die to disagree on a re-run.
	var wallet_before: int = warband.cruor.tier_count(int(ability_row["cost_tier"]))
	var vials_before: int = warband.stash.pooled_count(CruorManager.BASIC_REAGENT)
	var welded: Dictionary = warband.weld("sword_short", 0, str(ability_row["entry_id"]))
	check(bool(welded.get("ok", false)), "the weld lands (%s)" % str(welded.get("message", "")))
	var entry_id := str(ability_row["entry_id"])
	check(warband.annoints.has("sword_short", 0, entry_id), "the copy carries the weld")
	check(warband.cruor.tier_count(int(ability_row["cost_tier"])) ==
		wallet_before - int(ability_row["cost_count"]), "the cruor paid is the row's price")
	check(warband.stash.pooled_count(CruorManager.BASIC_REAGENT) == vials_before - 1,
		"and one vial went with it")

	# The same row again is refused: the piece already carries it.
	var twice: Dictionary = warband.weld("sword_short", 0, entry_id)
	check(not bool(twice.get("ok", true)), "the same weld is not laid twice")
	check(warband.annoints.count("sword_short", 0) == 1, "and the copy still carries one")

	# A second sword, and the same press on it: identical books, identical steel.
	warband.stash.add("sword_short", 1)
	warband.stash.add(CruorManager.BASIC_REAGENT, 4)
	warband.cruor.add(int(ability_row["cost_tier"]), int(ability_row["cost_count"]))
	var again: Dictionary = warband.weld("sword_short", 1, entry_id)
	check(bool(again.get("ok", false)), "another copy takes the same weld")
	check(warband.annoints.ids("sword_short", 1) == warband.annoints.ids("sword_short", 0),
		"the same rows give the same steel on a second copy (%s / %s)" % [
			str(warband.annoints.ids("sword_short", 1)), str(warband.annoints.ids("sword_short", 0))])

	# An empty pick is the one refusal the panel can make before the books do.
	var empty_pick: Dictionary = warband.weld("sword_short", 0, "")
	check(not bool(empty_pick.get("ok", true)), "no row picked is no weld")

	_finish()


func _finish() -> void:
	_remove(WARBAND_SAVE)
	_remove(STATE_SAVE)
	print("WELD_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
