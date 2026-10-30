extends SceneTree
## The three market keepers: each counter is a real service with its own seat in
## `PlayerState.VENDORS`, `G` at the counter opens that keeper's board, and the
## counter trades through the warband - gold out into the shared stash, spare
## copies back in at the keeper's rate, and a short purse buys nothing.

const State = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://warband_vendors_state.json"
const WARBAND_SAVE := "user://warband_vendors_warband.json"
## The service rings and the market ring the counters must stand inside.
const SERVICE_REACH := 3.0
const MARKET_RADIUS := 16.0

var game
var warband
var state
var checks := 0
var failures := 0

## service id -> the `PlayerState.VENDORS` seat it opens, in counter order.
const VENDOR_SEATS := [
	{"id": "vendor_orla", "seat": 0, "keeper": "Storekeeper Orla"},
	{"id": "vendor_brann", "seat": 1, "keeper": "Smith Brann"},
	{"id": "vendor_vey", "seat": 2, "keeper": "Quartermaster Vey"},
]

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("VENDORS_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _expected_stock(seat: int) -> Array:
	var out: Array = []
	var stock: Array = State.VENDORS[seat].get("stock", [])
	for entry in stock:
		var item_id := str(entry)
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or int(item.get("price", 0)) <= 0:
			continue
		out.append(item_id)
	out.sort()
	return out

func _row_for(rows: Array, item_id: String) -> Dictionary:
	for row in rows:
		if str(row["item_id"]) == item_id:
			return row
	return {}

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
	# A living warband keeps `seed_warband` from filling the pool with spares, so
	# every count below is this test's own purchase and sale.
	for index in 4:
		warband.add_mercenary("Merc %d" % index)
	check(warband.stash.pooled_total() == 0, "the test starts with an empty shared stash")

	game = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	# Every counter is a service with its own seat, standing inside the market.
	var points: Dictionary = {
		"stash": game.service_point("stash"),
		"altar": game.service_point("altar"),
		"recruiter": game.service_point("recruiter"),
		"quartermaster": game.service_point("quartermaster"),
		"gate": game.service_point("gate"),
	}
	for entry in VENDOR_SEATS:
		var service := str(entry["id"])
		var seat := int(entry["seat"])
		var point: Vector3 = game.service_point(service)
		check(point != Vector3.ZERO, "%s has a point in the square" % service)
		check(Vector2(point.x, point.z).length() <= MARKET_RADIUS,
			"%s stands on the market ring (%.1f m)" % [service, point.length()])
		check(game.service_at(point) == service,
			"%s ring resolves to itself" % service)
		for other in points:
			var gap: float = point.distance_to(points[other])
			check(gap > SERVICE_REACH * 2.0,
				"%s stays clear of %s (%.1f m)" % [service, other, gap])
		points[service] = point

		var opened: String = game.interact_at(1, point)
		check(opened == service, "G at %s names it (got '%s')" % [service, opened])
		check(game.vendor_menu.is_open(), "%s opens a stall" % service)
		check(game.panels_open(), "an open stall counts as an open panel")
		check(game.vendor_menu.vendor_index() == seat,
			"%s opens seat %d" % [service, seat])
		check(game.vendor_menu.keeper_name() == str(entry["keeper"]),
			"%s is %s" % [service, str(entry["keeper"])])

		var stock_ids: Array = []
		for row in game.vendor_menu.stock_rows():
			stock_ids.append(str(row["item_id"]))
			check(int(row["price"]) > 0, "%s prices %s" % [service, str(row["item_id"])])
		stock_ids.sort()
		check(stock_ids == _expected_stock(seat),
			"%s stocks exactly its vendor seat's catalogue" % service)
		check(not game.vendor_menu.keeper_tag().is_empty(),
			"%s shows a keeper tag" % service)
		check(not game.vendor_menu.keeper_line().is_empty(),
			"%s shows a keeper line" % service)

	# The old quartermaster desk still answers, and so does its menu.
	check(game.service_at(game.quartermaster_desk.global_position) == "quartermaster",
		"the quartermaster desk still resolves to the quartermaster")
	check(game.interact_at(1, game.quartermaster_desk.global_position) == "quartermaster",
		"G at the quartermaster desk still opens the old keeper")
	check(game.quartermaster.is_open(), "the quartermaster menu still opens")
	game.quartermaster.close()

	# Orla's shelf: buy the shortbow into the shared stash at its keeper price.
	var orla_point: Vector3 = game.service_point("vendor_orla")
	check(game.interact_at(1, orla_point) == "vendor_orla", "Orla's stall opens again")
	check(game.vendor_menu.stock_rows().size() == _expected_stock(0).size(),
		"Orla's board is still whole")
	var bow_row: Dictionary = _row_for(game.vendor_menu.stock_rows(), "bow_short")
	check(not bow_row.is_empty(), "Orla stocks the shortbow")
	var bow_price := int(State.ITEMS["bow_short"]["price"])
	check(int(bow_row.get("price", 0)) == bow_price,
		"the shelf charges the keeper price (%d)" % bow_price)
	check(not bool(game.vendor_menu.buy("sword_short").get("ok", true)),
		"a keeper cannot sell what another keeper stocks")

	var credits_before := int(state.credits)
	var bow_bought: Dictionary = game.vendor_menu.buy("bow_short")
	check(bool(bow_bought.get("ok", false)), "Orla sells the shortbow")
	check(int(state.credits) == credits_before - bow_price,
		"exactly the price leaves the purse (%d)" % state.credits)
	check(warband.stash.pooled_count("bow_short") == 1,
		"the shortbow lands in the shared stash")
	check(game.vendor_menu.status_text().contains("Shortbow"),
		"the keeper says what was bought")

	var pool_row: Dictionary = _row_for(game.vendor_menu.stash_rows(), "bow_short")
	check(not pool_row.is_empty() and int(pool_row.get("count", 0)) == 1,
		"the stash board shows the pooled copy with its count")

	# Selling the same copy back returns the keeper's share and empties the pool.
	var after_buy: int = int(state.credits)
	var bow_sold: Dictionary = game.vendor_menu.sell("bow_short")
	check(bool(bow_sold.get("ok", false)), "Orla buys the spare shortbow back")
	var payout := int(bow_sold.get("price", 0))
	check(payout == int(floor(float(bow_price) * 0.6)),
		"the sale pays 60%% of the price (%d)" % payout)
	check(absf(float(payout) / float(bow_price) - 0.6) < 0.02,
		"the payout is about sixty percent")
	check(int(state.credits) == after_buy + payout, "the purse is paid the sale price")
	check(warband.stash.pooled_count("bow_short") == 0,
		"the sold copy leaves the shared stash")
	check(_row_for(game.vendor_menu.stash_rows(), "bow_short").is_empty(),
		"the stash board drops the sold row")
	check(game.vendor_menu.status_text().contains("Sold"),
		"the keeper says what was sold")
	check(not bool(game.vendor_menu.sell("bow_short").get("ok", true)),
		"selling a copy the pool does not hold is refused")

	# Ammunition is the one row sold by the bunch: the board prices the whole
	# bunch, one click puts a quiver's worth of shafts in the shared pool, and a
	# shaft sells back for the keeper's share - the loop a dry bow depends on.
	var bundle: int = state.item_bundle("arrow")
	check(bundle > 1, "arrow ammunition is sold in bunches (%d)" % bundle)
	check(warband.arrows() == 0, "the test starts with a dry quiver")
	var arrow_row: Dictionary = _row_for(game.vendor_menu.stock_rows(), "arrow")
	check(not arrow_row.is_empty(), "the store stocks arrows")
	check(int(arrow_row.get("price", 0)) == int(State.ITEMS["arrow"]["price"]) * bundle,
		"the shelf prices the whole bunch (%d)" % int(arrow_row.get("price", 0)))
	check(int(arrow_row.get("bundle", 0)) == bundle, "and says how many it hands over")
	var credits_for_arrows := int(state.credits)
	var arrow_bought: Dictionary = game.vendor_menu.buy("arrow")
	check(bool(arrow_bought.get("ok", false)), "a bunch of arrows is bought")
	check(warband.arrows() == bundle, "the bunch lands in the quiver (%d)" % warband.arrows())
	check(int(state.credits) == credits_for_arrows - int(arrow_row["price"]),
		"the bunch costs one shelf price (%d)" % state.credits)
	check(warband.has_arrows(), "and the quiver answers a bow again")
	check(game.vendor_menu.status_text().contains("Arrow"), "the keeper says what was bought")
	var arrow_pool: Dictionary = _row_for(game.vendor_menu.stash_rows(), "arrow")
	check(int(arrow_pool.get("count", 0)) == bundle, "the stash board counts the bunch")
	var shaft_sale: Dictionary = game.vendor_menu.sell("arrow")
	check(bool(shaft_sale.get("ok", false)), "a keeper buys shafts back")
	check(int(shaft_sale.get("price", 0)) == int(floor(float(State.ITEMS["arrow"]["price"]) * 0.6)),
		"one shaft sells for the keeper's share (%d)" % int(shaft_sale.get("price", 0)))
	check(warband.arrows() == bundle - 1, "and one shaft leaves the quiver")
	warband.take_arrows(warband.arrows())

	# A short purse refuses before the stash is touched.
	state.credits = 5
	var refused_buy: Dictionary = game.vendor_menu.buy("bow_short")
	check(not bool(refused_buy.get("ok", true)), "a short purse buys nothing")
	check(int(state.credits) == 5, "a refused purchase spends nothing")
	check(warband.stash.pooled_count("bow_short") == 0,
		"a refused purchase adds nothing")
	check(game.vendor_menu.status_text().contains("gold"),
		"the refusal names the shortfall")

	game.vendor_menu.close()
	check(not game.vendor_menu.is_open(), "the stall closes")
	check(not game.panels_open(), "closing the stall leaves no panel open")

	game.queue_free()
	await process_frame
	state.reset(false)
	warband.reset_state()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_VENDORS_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
