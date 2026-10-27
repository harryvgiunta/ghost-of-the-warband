extends SceneTree
## The quartermaster: gold into the collective stash, at the keeper price, with
## the same refusal rules the rest of the town uses.

const State = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://quartermaster_state.json"
const WARBAND_SAVE := "user://quartermaster_warband.json"

var game
var warband
var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("QUARTERMASTER_FAIL  ", message)

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
	state.credits = 1000
	for index in 4:
		warband.add_mercenary("Merc %d" % index)

	game = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	var desk: Vector3 = game.quartermaster_desk.global_position
	check(game.service_at(desk) == "quartermaster", "the desk resolves as the quartermaster")
	check(game.interact_at(1, desk) == "quartermaster", "G opens the quartermaster")
	check(game.quartermaster.is_open(), "the shop is open")
	check(game.quartermaster.stock_rows().size() == 10, "ten base pieces are stocked")

	var rows: Array[Dictionary] = game.quartermaster.stock_rows()
	var sword_row: Dictionary = {}
	for row in rows:
		if str(row["item_id"]) == "sword_short":
			sword_row = row
	check(not sword_row.is_empty(), "the shortsword is on the board")
	check(int(sword_row["price"]) == int(State.ITEMS["sword_short"]["price"]),
		"the shop charges the keeper price")
	check(bool(sword_row["affordable"]), "1000 gold covers a shortsword")

	var bought: Dictionary = game.quartermaster.buy("sword_short")
	check(bool(bought.get("ok", false)), "the purchase succeeds")
	check(int(state.credits) == 1000 - int(State.ITEMS["sword_short"]["price"]),
		"exactly the price is spent (%d)" % state.credits)
	check(warband.stash.pooled_count("sword_short") == 1, "the piece lands in the shared stash")
	check(game.quartermaster.is_open(), "buying keeps the shop open")
	check(game.quartermaster.status_text().contains("Shortsword"),
		"the keeper says what was bought")

	# The whole warband can be armed from the shop, not only the ranger.
	var merc_ids: Array[int] = warband.roster.alive_ids()
	var arm: Dictionary = warband.equip_merc(int(merc_ids[0]), "main", "sword_short")
	check(bool(arm.get("ok", false)), "a mercenary wears what was bought")
	check(warband.stash.pooled_count("sword_short") == 0, "wearing it takes it out of the pool")

	# An empty purse buys nothing, and nothing is lost.
	state.credits = 5
	var refused: Dictionary = game.quartermaster.buy("ring_health")
	check(refused.get("ok") == false, "a short purse is refused")
	check(int(state.credits) == 5, "a refused purchase spends nothing")
	check(warband.stash.pooled_count("ring_health") == 0, "and adds nothing")
	check(game.quartermaster.status_text().contains("gold"), "the refusal names the shortfall")
	var unaffordable := false
	for row in game.quartermaster.stock_rows():
		if not bool(row["affordable"]):
			unaffordable = true
	check(unaffordable, "the board greys out what the purse cannot cover")

	game.quartermaster.close()
	check(not game.quartermaster.is_open(), "the shop closes")

	game.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("QUARTERMASTER_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
