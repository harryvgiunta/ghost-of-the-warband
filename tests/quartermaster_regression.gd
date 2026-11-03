extends SceneTree
## The quartermaster: gold into the collective stash, at the keeper price, with
## the same refusal rules the rest of the town uses.

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

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
		var merc_id: int = warband.add_mercenary("Merc %d" % index)
		# The second body is the band's bowman, so a bow bought at the desk has an
		# owner: a blade's body never takes one (`Contracts.disposition_refuses_gear`).
		if index == 1:
			warband.set_disposition(merc_id, Contracts.DISPOSITION_BOW)

	game = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	var desk: Vector3 = game.quartermaster_desk.global_position
	check(game.service_at(desk) == "quartermaster", "the desk resolves as the quartermaster")
	check(game.interact_at(1, desk) == "quartermaster", "G opens the quartermaster")
	check(game.quartermaster.is_open(), "the shop is open")
	check(game.quartermaster.stock_rows().size() == QuartermasterMenu.STOCK.size(),
		"every stocked piece is on the board (%d)" % game.quartermaster.stock_rows().size())
	for tid: String in ["dagger_ironwood", "club_makeshift", "bow_twig", "branch_heavy",
			"shield_wood", "armor_naked_chest", "armor_naked_legs"]:
		var found := false
		for row in game.quartermaster.stock_rows():
			if str(row["item_id"]) == tid:
				found = true
		check(found, "the quartermaster stocks " + tid)
	check(game.quartermaster.stock_rows().size() >= 11,
		"the original base pieces are still stocked (the torch included)")

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
	var merc_ids: Array[int] = warband.roster.alive_ids()
	check(str(warband.roster.equipped_of(merc_ids[0]).get("main", "")) == "sword_short",
		"the first bare body takes the blade as it is bought")
	check(warband.stash.pooled_count("sword_short") == 0, "and the worn copy leaves the pool")
	check(str(game.controller.seat_loadout(merc_ids[0]).get("main", "")) == "sword_short",
		"the live body is re-dressed with the blade the band armed itself with")
	check(game.quartermaster.is_open(), "buying keeps the shop open")
	check(game.quartermaster.status_text().contains("Shortsword"),
		"the keeper says what was bought")
	check(game.quartermaster.status_text().contains("takes it"),
		"and who the band armed with it")

	# The desk sells the shafts its bows spend, by the bunch: the row prices the
	# whole bunch and one purchase lands that many in the shared quiver.
	var bundle: int = State.item_bundle("arrow")
	var arrow_row: Dictionary = {}
	for row in game.quartermaster.stock_rows():
		if str(row["item_id"]) == "arrow":
			arrow_row = row
	check(not arrow_row.is_empty(), "the quartermaster stocks arrows")
	check(int(arrow_row.get("price", 0)) == int(State.ITEMS["arrow"]["price"]) * bundle,
		"the arrow row prices the whole bunch (%d)" % int(arrow_row.get("price", 0)))
	var quiver_before: int = warband.arrows()
	var purse_before := int(state.credits)
	var shafts: Dictionary = game.quartermaster.buy("arrow")
	check(bool(shafts.get("ok", false)), "a bunch of arrows is bought at the desk")
	check(warband.arrows() == quiver_before + bundle,
		"the bunch lands in the shared quiver (%d -> %d)" % [quiver_before, warband.arrows()])
	check(int(state.credits) == purse_before - int(arrow_row.get("price", 0)),
		"and costs exactly the row's price (%d)" % state.credits)

	# The whole warband can be armed from the shop, not only the ranger: each
	# purchase fills the next open slot across the band.
	var shield_bought: Dictionary = game.quartermaster.buy("shield_buckler")
	check(bool(shield_bought.get("ok", false))
		and str(warband.roster.equipped_of(merc_ids[0]).get("off", "")) == "shield_buckler",
		"a bought shield fills the next open slot")
	var bow_bought: Dictionary = game.quartermaster.buy("bow_short")
	check(bool(bow_bought.get("ok", false))
		and str(warband.roster.equipped_of(merc_ids[1]).get("main", "")) == "bow_short",
		"a bought bow arms the next body")
	var helm_bought: Dictionary = game.quartermaster.buy("armor_leather_head")
	check(bool(helm_bought.get("ok", false))
		and str(warband.roster.equipped_of(merc_ids[0]).get("head", "")) == "armor_leather_head",
		"a bought helm goes on a head")
	check(warband.stash.pooled_count("sword_short") == 0,
		"nothing the band wears is left doubled in the pool")

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
