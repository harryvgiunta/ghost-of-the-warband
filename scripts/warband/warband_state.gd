extends Node
## Autoload `Warband`: the persistent soul, the roster, the infinite stash, the
## Cruor ledger, the recruiter and the campaign ledger, in one place.
##
## Ghost of the Warband is a possession game, so the thing that survives a
## battle is not a character: it is the warband. This node owns that state and
## nothing else - no scene, no camera, no input. The camp, the trail and the town
## read it and write back through it.
##
## Gold is the existing `PlayerState` purse; this node never keeps a second one.

signal changed
## A piece just woke into its skill at the altar. Whatever dresses bodies off the
## roster listens, so every body already holding a copy carries the skill at once.
signal anointed(item_id: String, ability: String)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const CruorScript = preload("res://scripts/warband/cruor_manager.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const SoulScript = preload("res://scripts/warband/soul_router.gd")
const CruorCatalog = preload("res://scripts/warband/cruor_catalog.gd")
const State = preload("res://scripts/player_state.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const QuestScript = preload("res://scripts/warband/quest_log.gd")

## Item categories a body can wear; the same list `EquipmentRules` enforces.
const EQUIPPABLE_CATEGORIES := ["1h", "2h", "bow", "staff", "shield", "focus", "armor", "jewelry"]

## The order a fresh body is armed in: steel first, then armour, then the
## trinkets. `dress_recruit` walks this list and takes the dearest spare the
## shared stash holds for each slot.
const DRESS_SLOTS := ["main", "off", "head", "chest", "hands", "legs", "feet", "neck", "ring1", "ring2"]

## Additive save format. v3 added each mercenary's two weapon sets (`weapon_sets`
## plus `active_set` per record), the pair `TAB` brings up; v4 added the
## checkpoint bookmark (`checkpoint`), the autosave that remembers which stretch
## of the world the warband has already played; v5 added the campaign ledger
## (`quests`), the objectives the quartermaster has handed over and how far each
## one got; v6 added the altar's anointed pieces (`cruor.anointed`), the stock
## steel that has been given its skill; v7 dropped the expedition's battle ledger
## (`runs`, `run_totals`). Older files still load: a record with no sets puts the
## pair already in its hands in Set 1 and starts Set 2 empty, a file without a
## checkpoint resumes at the town as it always did, a file without quests opens
## with an empty ledger, and a file without anointings carries plain steel.
const SAVE_VERSION := 7
const DEFAULT_SAVE_PATH := "user://warband_state.json"
## The areas a checkpoint may name. A checkpoint is a *place in the campaign*,
## not a save slot: the camp is the only place a run starts, so it is never a
## checkpoint (the opening is already restartable from the title).
const CHECKPOINT_AREAS := ["trail", "town"]
## What every gear and purse verb answers while the warband is lent (see `lent`).
const LENT_MESSAGE := "This is the host's warband: only the host changes its gear and purse."

var roster: WarbandRoster = RosterScript.new()
var souls: SoulRouter = SoulScript.new()
var stash: WarbandStash = StashScript.new()
var cruor: WarbandCruor = CruorScript.new()
## The campaign ledger: which objectives the quartermaster has handed over and
## how far each has got. Pure state (no scene, no node), saved with everything
## else, so a checkpoint restores the orders as they stood.
var quests: WarbandQuests = QuestScript.new()
var deployment_cap: int = Contracts.MAX_DEPLOYMENT_CAP
var save_path := DEFAULT_SAVE_PATH
## True when a mode has already handed this warband its starting bodies, so a
## scene reload cannot seed a second copy of the same squad.
var seeded := false
## The mercenary each peer is currently inside, mirrored from the router so a
## scene hand-off can restore control without a live body.
var possession: Dictionary = {}   # peer_id -> merc_id
## Seconds into the current 5 s revive channel, keyed by peer id.
var revive_channels: Dictionary = {}  # peer_id -> {merc_id, seconds}
## The last autosave bookmark: `{id, area, position, label, at}` or `{}`. It is
## written by the world at the moments the campaign becomes a new stretch - the
## camp's six watchers down and the squad on the road, the town square entered -
## and it is what a wipe and the title's resume door read. The roster, stash and
## essence beside it are the warband as it stood then; the purse is not rolled
## back, because `PlayerState` owns it and a reload must never repay a run.
var checkpoint: Dictionary = {}
## True while this warband is a co-op host's, lent to this machine for the length
## of a session (`GameFlow.join_campaign`). A lent warband is shown and played and
## never touches this machine's files: `save_state` and `load_state` refuse, so the
## guest's own campaign is exactly as it was when the session ends. The host is
## the only place the shared warband changes - its gear, its purse, its roll - so
## every gear and purse verb below answers `LENT_MESSAGE` instead, and the host's
## own updates arrive through `lend()`. `end_loan()` gives this machine its own
## warband back.
var lent := false
## The host's purse while lent: shown, never spent on this machine.
var _lent_gold := 0

func _ready() -> void:
	set_process(false)
	if not roster.died.is_connected(_on_merc_died):
		roster.died.connect(_on_merc_died)

# --- purse -----------------------------------------------------------------

func gold() -> int:
	if lent:
		return _lent_gold
	var state := get_node_or_null("/root/PlayerState")
	return int(state.credits) if state != null else 0

## False (and nothing spent) when the purse cannot cover it.
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if lent:
		return false
	var state := get_node_or_null("/root/PlayerState")
	if state == null or int(state.credits) < amount:
		return false
	state.add_credits(-amount)
	return true

func award_gold(amount: int) -> void:
	if amount == 0 or lent:
		return
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(amount)

# --- the co-op loan ----------------------------------------------------------

## Take a co-op host's warband for the session: the roster, stash, essence,
## orders and bookmark exactly as the host holds them (its `to_dict()`), and the
## host's purse. The host sends it again whenever its warband changes, so this is
## also how the lent copy keeps up.
func lend(data: Dictionary, gold_amount: int) -> void:
	lent = true
	_lent_gold = maxi(0, gold_amount)
	from_dict(data)

## Hand the lent warband back: this machine's own save is read again, or a fresh
## warband stands in when there is none, so the title opens exactly the campaign
## it opened before the session.
func end_loan() -> void:
	if not lent:
		return
	lent = false
	_lent_gold = 0
	clear_possession()
	if not load_state():
		reset_state()

## The refusal every gear and purse verb gives while lent, in the shape that verb
## always answers with.
func _lent_refusal(fields: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "message": LENT_MESSAGE}
	out.merge(fields)
	return out

# --- the quiver ------------------------------------------------------------

## Ammunition is one pool for the whole band, exactly like the shared stash it
## lives in: every shaft a bow looses comes out of it, every bunch a keeper sells
## goes into it, and every archer's corpse gives a few back. A bow with nothing
## in the quiver cannot be drawn, which is the whole of the rule.
const ARROW_ITEM := "arrow"
## What a fresh campaign opens with. A body that has to buy its first shaft
## before it may use a bow it just looted would read the bow as broken.
const STARTING_ARROWS := 24

func arrows() -> int:
	return stash.pooled_count(ARROW_ITEM)

## False when the quiver is empty. A caller drawing a bow asks this first.
func has_arrows() -> bool:
	return arrows() > 0

## Take up to `count` shafts out of the pool and answer how many actually left
## it: a loosed arrow asks for one and gets 0 or 1, so the count can never go
## negative however many shots a frame resolves.
func take_arrows(count: int = 1) -> int:
	var taken := 0
	while taken < maxi(count, 0) and stash.remove(ARROW_ITEM, 1):
		taken += 1
	if taken > 0:
		_notify()
	return taken

## Put shafts back in the pool: a keeper's bunch, an archer's corpse, a test.
func add_arrows(count: int = 1) -> int:
	var added := maxi(count, 0)
	if added <= 0:
		return 0
	stash.add(ARROW_ITEM, added)
	_notify()
	return added

## A campaign's opening bunch. Seeding never mints: a warband that already counts
## shafts - a resumed save, a keeper's purchase - keeps exactly what it had.
func seed_quiver(count: int = STARTING_ARROWS) -> int:
	if arrows() > 0:
		return 0
	return add_arrows(count)

# --- roster ----------------------------------------------------------------

func merc_ids() -> Array[int]:
	return roster.ids()

func alive_merc_ids() -> Array[int]:
	return roster.alive_ids()

## The dead leave the warband the moment they die: a corpse is not a party member,
## it cannot be deployed or entered, and its record used to sit on the hire cap
## forever - a band that had filled its eight places could never swear another
## body because the fallen still counted. The name leaves the roster, the body
## leaves the soul router, and everything it was still wearing goes back into the
## shared stash, so dying costs the man, never the gear. Returns the fallen
## records (`[{id, name, health, max_health, items}]`); empty when nobody died.
func reap_dead() -> Array[Dictionary]:
	var fallen := roster.take_dead()
	if fallen.is_empty():
		return fallen
	for entry in fallen:
		var merc_id := int(entry.get("id", 0))
		for item_id in entry.get("items", []):
			stash.add(str(item_id), 1)
		if souls.has_body(merc_id):
			souls.unregister_body(merc_id)
		for peer_id in possession.keys():
			if int(possession[peer_id]) == merc_id:
				possession.erase(peer_id)
		for peer_id in revive_channels.keys():
			var channel: Variant = revive_channels[peer_id]
			if channel is Dictionary and int((channel as Dictionary).get("merc_id", 0)) == merc_id:
				revive_channels.erase(peer_id)
	_notify()
	return fallen

func _on_merc_died(_merc_id: int) -> void:
	reap_dead()

## Hack a body into the warband (the cage tutorial's four prisoners, the admin
## arena's eight test bodies, a soldier cut out of a cage). No gold changes hands.
func add_mercenary(merc_name: String = "", equipped: Dictionary = {}) -> int:
	var merc_id := roster.create(merc_name, equipped)
	_notify()
	return merc_id

## Hand a fresh body the best kit the warband already owns.
##
## A body that swears with empty hands is dead weight, so a hire and a rescue
## both walk the equipment slots in the order a fighter would fill them and take
## the dearest spare out of the shared stash for each one. The pool is the only
## source: nothing is minted, and anything the body was already wearing (the
## cage's rags, a looted blade) is left alone. A two-hander locks the off hand,
## exactly as `EquipmentRules` says it does.
## Returns `{ok, merc_id, fitted, message}` with the ids that walked across.
func dress_recruit(merc_id: int, slots: Array = DRESS_SLOTS) -> Dictionary:
	var fitted: Array[String] = []
	if lent:
		return _lent_refusal({"merc_id": merc_id, "fitted": fitted})
	if merc_id <= 0 or not roster.is_alive(merc_id):
		return {"ok": false, "merc_id": merc_id, "fitted": fitted, "message": ""}
	for slot_id in slots:
		var wanted_slot := str(slot_id)
		var gear := roster.equipped_of(merc_id)
		if not str(gear.get(wanted_slot, "")).is_empty():
			continue
		if wanted_slot == "off":
			var main_id := str(gear.get("main", ""))
			if Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
				continue
		var best := ""
		var best_value := -1
		for item_id in stash.pooled_ids():
			var item: Dictionary = State.ITEMS.get(str(item_id), {})
			if not EquipmentRules.allowed(item, wanted_slot):
				continue
			var value := WarbandStash.value_of(str(item_id), cruor.brand_of(str(item_id)))
			if value > best_value:
				best_value = value
				best = str(item_id)
		if best.is_empty():
			continue
		var result := equip_merc(merc_id, wanted_slot, best)
		if bool(result.get("ok", false)):
			fitted.append(best)
	if fitted.is_empty():
		return {"ok": true, "merc_id": merc_id, "fitted": fitted,
			"message": "%s takes the field with what the band had spare." % roster.name_of(merc_id)}
	_notify()
	return {"ok": true, "merc_id": merc_id, "fitted": fitted,
		"message": "%s arms from the shared stash: %s." % [roster.name_of(merc_id),
			", ".join(fitted.map(func(item_id: String): return str(
				State.ITEMS.get(item_id, {}).get("name", item_id))))]}

## Buy one catalog item into the shared stash with gold. The price is the same
## keeper price the paperdoll and the stash sort use, so nothing can disagree
## about what a piece is worth. A catalog row that carries a `bundle` (ammunition)
## hands over that many copies for the list price per copy, so one visit to the
## shelf is a quiver's worth of shafts and a sale still pays per shaft.
func buy_gear(item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"item_id": item_id, "cost": 0})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return {"ok": false, "message": "The quartermaster does not stock that.", "item_id": item_id, "cost": 0, "count": 0}
	var count := State.item_bundle(item_id)
	var cost := int(item.get("price", 0)) * count
	if int(item.get("price", 0)) <= 0:
		return {"ok": false, "message": "That piece has no price.", "item_id": item_id, "cost": 0, "count": 0}
	if not spend_gold(cost):
		return {"ok": false, "item_id": item_id, "cost": cost, "count": count,
			"message": "You need %d gold; you have %d." % [cost, gold()]}
	stash.add(item_id, count)
	_notify()
	var display := str(item.get("name", item_id))
	if count > 1:
		display = "%d × %s" % [count, display]
	return {"ok": true, "item_id": item_id, "cost": cost, "count": count,
		"message": "Bought %s for %d gold into the shared stash." % [display, cost]}

## Sell one pooled copy back to a keeper. The piece must be in the shared pool:
## a blade somebody is wearing is not the warband's to sell behind their back,
## and the pool is the only place a copy can leave without stripping a body.
##
## The keeper pays `share` of the catalogue price (60% by default), floored to a
## whole coin, so a sale always returns less than the purchase. `price` in the
## reply is what the purse was actually paid, not the catalogue figure.
func sell_gear(item_id: String, share: float = 0.6) -> Dictionary:
	if lent:
		return _lent_refusal({"price": 0, "item_id": item_id})
	var id := State.migrate_item_id(item_id)
	var item: Dictionary = State.ITEMS.get(id, {})
	if item.is_empty():
		return {"ok": false, "message": "No keeper buys that.", "price": 0, "item_id": item_id}
	var list_price := int(item.get("price", 0))
	if list_price <= 0:
		return {"ok": false, "message": "That piece has no price.", "price": 0, "item_id": id}
	var display := str(item.get("name", id))
	# The pool is the authority on whether there is a copy to sell: a worn piece
	# is on a body, not on the keeper's shelf, and a failed removal must never pay.
	if not stash.remove(id, 1):
		return {"ok": false, "price": 0, "item_id": id,
			"message": "You have no spare %s in the stash." % display}
	var payout := int(floor(float(list_price) * clampf(share, 0.0, 1.0)))
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(payout)
	_notify()
	return {"ok": true, "item_id": id, "price": payout,
		"message": "Sold %s for %d gold." % [display, payout]}

## Lay the altar's reagents on a piece the warband carries. The recipe leaves the
## shared stash, every copy of the piece wakes into its own skill, the ledger's
## APPLY orders hear about each reagent, and `anointed` tells the scene to dress
## the bodies already holding one. Returns the ledger's reply plus `completed`,
## the orders this anointing finished.
func anoint(item_id: String) -> Dictionary:
	var result := cruor.anoint(stash, roster, item_id)
	var completed: Array[String] = []
	if bool(result.get("ok", false)):
		var spent: Dictionary = result.get("spent", {})
		for reagent in spent:
			for quest_id in quests.note_applied(str(reagent), int(spent[reagent])):
				if quests.is_complete(quest_id):
					completed.append(quest_id)
		anointed.emit(item_id, str(result.get("ability", "")))
		_notify()
	result["completed"] = completed
	return result

func hire(merc_name: String = "") -> Dictionary:
	if lent:
		return _lent_refusal({"merc_id": -1, "cost": 0})
	var state := get_node_or_null("/root/PlayerState")
	var result := WarbandVendor.hire(roster, state, merc_name, deployment_cap) if state != null \
		else {"ok": false, "message": "The purse is missing.", "merc_id": -1, "cost": 0}
	if bool(result.get("ok", false)):
		# A body that swears with empty hands is dead weight: the recruiter's
		# oath includes whatever the shared stash can spare.
		var merc_id := int(result.get("merc_id", -1))
		var dressed := dress_recruit(merc_id)
		var fitted: Array = dressed.get("fitted", [])
		if not fitted.is_empty():
			result["fitted"] = fitted
			result["message"] = "%s %s" % [str(result.get("message", "")),
				str(dressed.get("message", ""))]
		_notify()
	return result

func hire_cost() -> int:
	return WarbandVendor.hire_cost(roster)

## Equip a mercenary straight from the collective stash. The piece is looked up
## by catalog id; anything displaced returns to the pool, so no item is ever
## lost by equipping.
## Equip a mercenary from the collective stash. The stash is one pool, so a
## piece another mercenary is already wearing is a *transfer*, not a refusal:
## the wearer is stripped and the piece walks across. Without that rule the only
## dagger in a fresh warband could never be handed from the rescuer to a
## prisoner, which is exactly what the first scene asks the player to do.
func equip_merc(merc_id: int, slot_id: String, item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"displaced": {}})
	if item_id.is_empty():
		return {"ok": false, "message": "Choose a piece of gear.", "displaced": {}}
	var gear := roster.equipped_of(merc_id)
	if str(gear.get(slot_id, "")) == item_id:
		return {"ok": true, "message": "%s is already worn there." % roster.name_of(merc_id),
			"displaced": {}}
	var moved_from := ""
	if stash.pooled_count(item_id) <= 0:
		var taken := _strip_worn(item_id)
		if not bool(taken.get("ok", false)):
			return {"ok": false, "message": "You do not own that piece yet.", "displaced": {}}
		moved_from = str(taken.get("from", ""))
	var result := roster.equip(merc_id, slot_id, item_id)
	if not bool(result.get("ok", false)):
		# Put the stripped piece back where it came from: a refused equip must
		# not quietly pocket somebody else's gear.
		if not moved_from.is_empty():
			stash.remove(item_id, 1)
		return result
	stash.remove(item_id, 1)
	var displaced: Dictionary = result.get("displaced", {})
	for slot in displaced:
		var old_id := str(displaced[slot])
		if not old_id.is_empty():
			stash.add(old_id, 1)
	if not moved_from.is_empty():
		result["message"] = "%s taken from %s." % [str(result.get("message", "")), moved_from]
	_notify()
	return result

## Take one worn copy of `item_id` off whichever mercenary holds it and drop it
## into the pool. Returns `{ok, from}` where `from` names the mercenary.
##
## Both weapon sets are searched, not just the hands: a piece waiting in the set
## the body is not carrying is still the warband's to hand over.
func _strip_worn(item_id: String) -> Dictionary:
	for entry in _worn_entries_all():
		if str(entry.get("item", "")) != item_id:
			continue
		var merc_id := int(entry.get("merc", 0))
		var slot_id := str(entry.get("slot", ""))
		var label := "%s (%s)" % [roster.name_of(merc_id), Contracts.slot_id_label(slot_id)]
		if roster.take_worn(merc_id, slot_id, int(entry.get("set", -1))) != item_id:
			continue
		stash.add(item_id, 1)
		return {"ok": true, "from": label}
	return {"ok": false, "from": ""}

## Every worn piece in the warband, both weapon sets included, as `{merc, slot,
## item, set}` records.
func _worn_entries_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for merc in roster.records():
		var merc_id := int(merc.get("id", 0))
		for entry in roster.worn_entries(merc_id):
			var row := entry.duplicate()
			row["merc"] = merc_id
			out.append(row)
	return out

## The piece a loot pickup should snap into the soul's hands if it can. It only
## takes a slot that is empty or holds something clearly cheaper, so a player
## never loses a good blade to a lucky drop; anything else stays in the stash.
## Returns `{ok, slot, displaced, message}`.
func auto_equip(merc_id: int, item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"slot": ""})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty() or merc_id <= 0:
		return {"ok": false, "message": "", "slot": ""}
	if not str(item.get("category", "")) in EQUIPPABLE_CATEGORIES:
		return {"ok": false, "message": "", "slot": ""}
	if not roster.is_alive(merc_id):
		return {"ok": false, "message": "", "slot": ""}
	var gear := roster.equipped_of(merc_id)
	var slot_id := EquipmentRules.auto_slot(item, gear)
	if slot_id.is_empty():
		return {"ok": false, "message": "", "slot": ""}
	var worn := str(gear.get(slot_id, ""))
	if not worn.is_empty():
		var worn_price := WarbandStash.value_of(worn, cruor.brand_of(worn))
		var new_price := WarbandStash.value_of(item_id, cruor.brand_of(item_id))
		if new_price <= worn_price:
			return {"ok": false, "message": "", "slot": slot_id}
	var result := equip_merc(merc_id, slot_id, item_id)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": str(result.get("message", "")), "slot": slot_id}
	return {"ok": true, "slot": slot_id, "message": str(result.get("message", "")),
		"displaced": result.get("displaced", {})}

## Strip a worn piece back into the pool.
func unequip_merc(merc_id: int, slot_id: String) -> String:
	if lent:
		return ""
	var item_id := roster.unequip(merc_id, slot_id)
	if item_id.is_empty():
		return ""
	stash.add(item_id, 1)
	_notify()
	return item_id

## `TAB` in the world: the standing body puts away the weapon set in its hands
## and takes up the other one, exactly as the frontier's own swap does. The two
## pairs live on the roster record, so the swap is warband state - it survives a
## body hop, a reload and a scene hand-off - and the scene re-dresses the rig from
## it with `refresh_gear()`.
func swap_weapon_set(merc_id: int) -> Dictionary:
	if lent:
		return _lent_refusal({"set": 0})
	var result := roster.swap_weapon_set(merc_id)
	_notify()
	return result

## What one mercenary's kit is worth. Both weapon sets count: stowing a sword in
## the set the hands are not carrying does not make it leave the warband.
func gear_value(merc_id: int) -> int:
	var total := 0
	for entry in roster.worn_entries(merc_id):
		var item_id := str(entry.get("item", ""))
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id, cruor.brand_of(item_id))
	return total

## The warband's combined worth, gear and essence, for the HUD and tests.
func total_value() -> int:
	var total := 0
	for entry in _worn_entries_all():
		var item_id := str(entry.get("item", ""))
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id, cruor.brand_of(item_id))
	var pooled := stash.pooled_map()
	for item_id in pooled:
		total += WarbandStash.value_of(str(item_id), cruor.brand_of(str(item_id))) * int(pooled[item_id])
	for tier in CruorCatalog.TIER_ORDER:
		total += cruor.tier_count(tier) * CruorCatalog.tier_value(tier)
	return total

# --- possession bookkeeping ------------------------------------------------

## Mirror a router decision into the persistent map.
func note_possession(peer_id: int, merc_id: int) -> void:
	if merc_id <= 0:
		possession.erase(peer_id)
	else:
		possession[peer_id] = merc_id
	_notify()

func possessed_by(peer_id: int) -> int:
	return int(possession.get(peer_id, -1))

func possessed_ids() -> Dictionary:
	return possession.duplicate()

func clear_possession() -> void:
	possession.clear()
	revive_channels.clear()
	souls.clear()
	_notify()

# --- reset -----------------------------------------------------------------

func reset_state(cap: int = Contracts.MAX_DEPLOYMENT_CAP) -> void:
	# A reset is a fresh warband of this machine's own, never a host's.
	lent = false
	_lent_gold = 0
	roster.clear()
	stash.clear()
	cruor.clear()
	souls.clear()
	quests.reset()
	deployment_cap = maxi(1, cap)
	seeded = false
	possession.clear()
	revive_channels.clear()
	checkpoint.clear()
	_notify()

func _notify() -> void:
	changed.emit()

# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"deployment_cap": deployment_cap,
		"roster": roster.to_dict(),
		"stash": stash.to_dict(),
		"cruor": cruor.to_dict(),
		"checkpoint": checkpoint.duplicate(true),
		"quests": quests.to_dict(),
	}

func from_dict(data: Dictionary) -> void:
	roster.from_dict(data.get("roster", {}))
	stash.from_dict(data.get("stash", {}))
	cruor.from_dict(data.get("cruor", {}))
	deployment_cap = clampi(int(data.get("deployment_cap", Contracts.MAX_DEPLOYMENT_CAP)),
		1, Contracts.MAX_DEPLOYMENT_CAP)
	# A v3 file has no checkpoint: it resumes at the town, which is what every
	# save written before autosave existed meant.
	checkpoint = sanitise_checkpoint(data.get("checkpoint", {}))
	# A v4 file has no ledger: it opens with no orders, which is exactly the
	# quartermaster's slate before he speaks.
	quests.from_dict(QuestScript.sanitise(data.get("quests", {})))
	# A file written before the dead left the books still carries their records.
	# They leave now, and whatever they wore joins the stash that was just read:
	# opening an old warband must free the hire cap, not inherit a graveyard.
	reap_dead()
	# Nothing is ever paid here: the purse and the essence wallet already hold
	# what a run earned, so a save/load cycle cannot pay one twice.
	seeded = roster.count() > 0
	_notify()

## `GameFlow.goto()` and every scene's `_exit_tree()` call this, so the file is
## written with the roster as the world last mirrored it.
func save_state() -> void:
	# A lent warband is the host's: writing it here would put somebody else's
	# campaign over this machine's own save.
	if lent:
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Warband: cannot write %s" % save_path)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()

func load_state() -> bool:
	# Reading this machine's file into a lent warband would swap the host's
	# campaign for the guest's in the middle of a session.
	if lent:
		return false
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Warband: %s is not a saved warband" % save_path)
		return false
	if int(parsed.get("version", 0)) > SAVE_VERSION:
		push_warning("Warband: %s is from a newer build" % save_path)
		return false
	from_dict(parsed)
	return true

## What a warband file holds, read without adopting it: `{exists, roster,
## checkpoint}`. The title says what HOST GAME's checkpoint door would open with
## this, and must not load a save into the live warband just to describe one.
static func peek_save(path: String) -> Dictionary:
	var out := {"exists": false, "roster": 0, "checkpoint": {}}
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	out["exists"] = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return out
	var roster_data: Variant = (parsed as Dictionary).get("roster", {})
	if roster_data is Dictionary and (roster_data as Dictionary).get("mercenaries", []) is Array:
		out["roster"] = ((roster_data as Dictionary)["mercenaries"] as Array).size()
	out["checkpoint"] = sanitise_checkpoint((parsed as Dictionary).get("checkpoint", {}))
	return out

# --- checkpoints (the autosave bookmark) ------------------------------------
#
# A checkpoint is the campaign's own memory of "how far we got", written at the
# moments that begin a new stretch: the camp's six watchers down with the squad
# on the road (`trail_start`), and the town square entered (`town`). It rides in
# the same `warband_state.json` as everything else, so one file is one truthful
# picture - a wiped run loads the roster, stash and essence as they stood there
# and puts the warband back on that ground. A v3 file has no checkpoint and
# resumes at the town, exactly as it did before.

func has_checkpoint() -> bool:
	return not checkpoint.is_empty()

func checkpoint_id() -> String:
	return str(checkpoint.get("id", ""))

## `"trail"` or `"town"`, or `""` when there is no bookmark.
func checkpoint_area() -> String:
	return str(checkpoint.get("area", ""))

func checkpoint_label() -> String:
	return str(checkpoint.get("label", ""))

## The ground the bookmark was taken on. Zero when there is none; callers that
## need a standable point snap it to the terrain.
func checkpoint_position() -> Vector3:
	return checkpoint_vector(checkpoint)

## The moment the bookmark was taken, as a unix stamp.
func checkpoint_at() -> int:
	return int(checkpoint.get("at", 0))

## Write a checkpoint and the whole warband with it. The warband is saved at the
## same time on purpose: a bookmark that points at a state the file has never
## held is a lie the reload cannot honour. Returns the stored record.
func save_checkpoint(id: String, area: String, position: Vector3, label: String = "") -> Dictionary:
	var wanted_id := id.strip_edges()
	var wanted_area := area if CHECKPOINT_AREAS.has(area) else "town"
	if wanted_id.is_empty():
		wanted_id = wanted_area
	checkpoint = {
		"id": wanted_id,
		"area": wanted_area,
		"position": [position.x, position.y, position.z],
		"label": label,
		"at": int(Time.get_unix_time_from_system()),
	}
	save_state()
	_notify()
	return checkpoint.duplicate(true)

func clear_checkpoint() -> void:
	if checkpoint.is_empty():
		return
	checkpoint.clear()
	_notify()

## How many bodies the bookmark can put on the field. A checkpoint whose whole
## squad is dead is not a checkpoint: the wipe path must not loop on it.
func checkpoint_standing() -> int:
	var count := 0
	for merc_id in roster.ids():
		if roster.state_of(merc_id) != Contracts.HealthState.DEAD:
			count += 1
	return count

## The same check a reader gets out of the file: malformed data is dropped, never
## half-read. Static because a save's checkpoint is untrusted input.
static func sanitise_checkpoint(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var record: Dictionary = data
	var id := str(record.get("id", "")).strip_edges()
	var area := str(record.get("area", ""))
	if id.is_empty() or not CHECKPOINT_AREAS.has(area):
		return {}
	if not is_standable(record.get("position", null)):
		return {}
	var point := checkpoint_vector(record)
	return {
		"id": id,
		"area": area,
		"position": [point.x, point.y, point.z],
		"label": str(record.get("label", "")),
		"at": int(record.get("at", 0)),
	}

## A checkpoint's position, read from a record or from the live field.
static func checkpoint_vector(record: Dictionary) -> Vector3:
	var value: Variant = record.get("position", [])
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.ZERO
	var values: Array = value
	for index in 3:
		if typeof(values[index]) not in [TYPE_INT, TYPE_FLOAT]:
			return Vector3.ZERO
	var point := Vector3(float(values[0]), float(values[1]), float(values[2]))
	return point if point.is_finite() else Vector3.ZERO

static func is_standable(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for entry in value as Array:
		if typeof(entry) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(entry)):
			return false
	return true

## One line for the log card and for tests.
func describe() -> String:
	return "mercs=%d alive=%d cap=%d gold=%d cruor=%d brands=%d stash=%d checkpoint=%s" % [
		roster.count(), roster.alive_count(), deployment_cap,
		gold(), cruor.total(), cruor.brands.size(), stash.pooled_total(),
		checkpoint_id() if has_checkpoint() else "-"]
