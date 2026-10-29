extends Node
## Autoload `Warband`: the persistent soul, the roster, the infinite stash, the
## Cruor ledger, the recruiter and the battle ledger, in one place.
##
## Ghost of the Warband is a possession game, so the thing that survives a
## battle is not a character: it is the warband. This node owns that state and
## nothing else - no scene, no camera, no input. Every mode (cage escape, town
## hub, admin arena, expedition) reads it and writes back through it.
##
## Gold is the existing `PlayerState` purse; this node never keeps a second one.

signal changed

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const CruorScript = preload("res://scripts/warband/cruor_manager.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const SoulScript = preload("res://scripts/warband/soul_router.gd")
const CruorCatalog = preload("res://scripts/warband/cruor_catalog.gd")
const State = preload("res://scripts/player_state.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
## The battle ledger record; see "run reports" in the persistence section.
const RunReportScript = preload("res://scripts/warband/run_report.gd")

## Item categories a body can wear; the same list `EquipmentRules` enforces.
const EQUIPPABLE_CATEGORIES := ["1h", "2h", "bow", "staff", "shield", "focus", "armor", "jewelry"]

## Additive save format. v2 added the run history (`runs`) and the lifetime
## totals (`run_totals`); v3 added each mercenary's two weapon sets (`weapon_sets`
## plus `active_set` per record), the pair `TAB` brings up; v4 added the
## checkpoint bookmark (`checkpoint`), the autosave that remembers which stretch
## of the world the warband has already played. Older files still load: a record
## with no sets puts the pair already in its hands in Set 1 and starts Set 2
## empty, a v1 file has no reports and zeroed totals, and a file without a
## checkpoint resumes at the town as it always did.
const SAVE_VERSION := 4
const DEFAULT_SAVE_PATH := "user://warband_state.json"
## The areas a checkpoint may name. A checkpoint is a *place in the campaign*,
## not a save slot: the camp is the only place a run starts, so it is never a
## checkpoint (the opening is already restartable from the title).
const CHECKPOINT_AREAS := ["trail", "town"]

var roster: WarbandRoster = RosterScript.new()
var souls: SoulRouter = SoulScript.new()
var stash: WarbandStash = StashScript.new()
var cruor: WarbandCruor = CruorScript.new()
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

func _ready() -> void:
	set_process(false)
	# The battle ledger is fed by watching the field, so it needs `node_added`
	# from the first frame; see "run reports" in the persistence section.
	_ensure_run_watch()

# --- purse -----------------------------------------------------------------

func gold() -> int:
	var state := get_node_or_null("/root/PlayerState")
	return int(state.credits) if state != null else 0

## False (and nothing spent) when the purse cannot cover it.
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	var state := get_node_or_null("/root/PlayerState")
	if state == null or int(state.credits) < amount:
		return false
	state.add_credits(-amount)
	return true

func award_gold(amount: int) -> void:
	if amount == 0:
		return
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(amount)

# --- roster ----------------------------------------------------------------

func merc_ids() -> Array[int]:
	return roster.ids()

func alive_merc_ids() -> Array[int]:
	return roster.alive_ids()

func deployed_merc_ids() -> Array[int]:
	return roster.deployed_ids()

## Hack a body into the warband (the cage tutorial's four prisoners, the admin
## arena's eight test bodies). No gold changes hands.
func add_mercenary(merc_name: String = "", equipped: Dictionary = {}) -> int:
	var merc_id := roster.create(merc_name, equipped)
	_notify()
	return merc_id

## Buy one catalog item into the shared stash with gold. The price is the same
## keeper price the paperdoll and the stash sort use, so nothing can disagree
## about what a piece is worth.
func buy_gear(item_id: String) -> Dictionary:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return {"ok": false, "message": "The quartermaster does not stock that.", "item_id": item_id, "cost": 0}
	var cost := int(item.get("price", 0))
	if cost <= 0:
		return {"ok": false, "message": "That piece has no price.", "item_id": item_id, "cost": 0}
	if not spend_gold(cost):
		return {"ok": false, "item_id": item_id, "cost": cost,
			"message": "You need %d gold; you have %d." % [cost, gold()]}
	stash.add(item_id, 1)
	_notify()
	return {"ok": true, "item_id": item_id, "cost": cost,
		"message": "Bought %s for %d gold into the shared stash." % [
			str(item.get("name", item_id)), cost]}

## Sell one pooled copy back to a keeper. The piece must be in the shared pool:
## a blade somebody is wearing is not the warband's to sell behind their back,
## and the pool is the only place a copy can leave without stripping a body.
##
## The keeper pays `share` of the catalogue price (60% by default), floored to a
## whole coin, so a sale always returns less than the purchase. `price` in the
## reply is what the purse was actually paid, not the catalogue figure.
func sell_gear(item_id: String, share: float = 0.6) -> Dictionary:
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

func hire(merc_name: String = "") -> Dictionary:
	var state := get_node_or_null("/root/PlayerState")
	var result := WarbandVendor.hire(roster, state, merc_name, deployment_cap) if state != null \
		else {"ok": false, "message": "The purse is missing.", "merc_id": -1, "cost": 0}
	if bool(result.get("ok", false)):
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
	var result := roster.swap_weapon_set(merc_id)
	_notify()
	return result

func set_deployed(merc_id: int, on: bool) -> Dictionary:
	var result := roster.set_deployed(merc_id, on, deployment_cap)
	_notify()
	return result

func deploy_battle(merc_ids: Array) -> Array[int]:
	var fielded := roster.deploy(merc_ids, deployment_cap)
	_notify()
	return fielded

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
	roster.clear()
	stash.clear()
	cruor.clear()
	souls.clear()
	deployment_cap = maxi(1, cap)
	seeded = false
	possession.clear()
	revive_channels.clear()
	checkpoint.clear()
	# A new campaign has no history to show (the persistence section owns it).
	_reset_run_records()
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
		"runs": _run_history.duplicate(true),
		"run_totals": RunReportScript.sanitize_totals(run_totals),
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
	# A v1 save has neither field; both readers answer "nothing fought yet".
	_load_run_history(data.get("runs", []))
	run_totals = RunReportScript.sanitize_totals(data.get("run_totals", {}))
	# No reward is ever re-applied here. The purse and the essence wallet already
	# hold what a battle paid; the history is a ledger of that, never a second
	# payment, so a save/load cycle cannot pay a run twice.
	seeded = roster.count() > 0
	_notify()

## Leaving the field is the moment a battle becomes history: `GameFlow.goto()`
## and every scene's `_exit_tree()` call this, so the report is written with the
## roster the arena mirrored at 0.4 s intervals still in place.
func save_state() -> void:
	_close_open_run()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Warband: cannot write %s" % save_path)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()

func load_state() -> bool:
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
	return "mercs=%d alive=%d deployed=%d cap=%d gold=%d cruor=%d brands=%d stash=%d checkpoint=%s" % [
		roster.count(), roster.alive_count(), roster.deployed_count(), deployment_cap,
		gold(), cruor.total(), cruor.brands.size(), stash.pooled_total(),
		checkpoint_id() if has_checkpoint() else "-"]

# --- run reports (persistence) ---------------------------------------------
#
# A battle becomes history without every scene having to remember to file it:
# `Warband` watches the tree for the two node types an expedition is built from -
# `EnemyWaves` (which paces the cult and knows every wave it fielded) and
# `CultistGuard` (whose death signal is the kill count) - so the admin arena and
# the expedition director both feed the same ledger with no wiring of their own.
# A scene may call `begin_run()`/`note_run()`/`finish_run()` itself when it wants
# to be explicit; the record is idempotent and one battle is one entry.
#
# Nothing here pays. Gold and cruor are read back out of the wallets at the end
# of the run, so a reward is paid exactly once, by whoever pays it, and a reload
# replays the ledger without touching a purse.

## The battle being recorded, or `null` between battles.
var run = null
## Lifetime counters; `RunReport.TOTAL_FIELDS` is the full list.
var run_totals: Dictionary = RunReportScript.blank_totals()
## Newest last, at most `RunReport.HISTORY_LIMIT` entries.
var _run_history: Array[Dictionary] = []
## Transient run bookkeeping. None of it is saved: a reload in the middle of a
## battle is not a battle result.
## The spawner last bound to the open record, so the close can read its own tally
## (never dereferenced without `is_instance_valid`: it dies with the scene).
var _run_waves: Node = null
var _run_wave_count := 0
var _run_cleared_waves := 0
var _run_kills := 0
var _run_notes: Dictionary = {}
var _run_body_ids: Array[int] = []
var _run_gold_start := 0
var _run_cruor_start := 0
var _run_items_start := 0

## Listen for the field. Connected once from `_ready()`; `node_added` is the only
## hook that can see a battle start in a scene this autoload does not own.
func _ensure_run_watch() -> void:
	var tree := get_tree()
	if tree == null or tree.node_added.is_connected(_on_node_added):
		return
	tree.node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node is EnemyWaves:
		_attach_waves(node)
	elif node is CultistGuard and run != null:
		_watch_guard(node)

func _attach_waves(waves: Node) -> void:
	if run == null:
		begin_run(RunReportScript.MODE_EXPEDITION, waves)
		return
	# A director that fields more than one spawner is still one battle: keep the
	# record and let the same watcher count the new node's waves and guards.
	_bind_waves(waves)

func _bind_waves(waves: Node) -> void:
	if waves == null or not is_instance_valid(waves):
		return
	_run_waves = waves
	if waves.has_signal("wave_started") \
			and not waves.is_connected("wave_started", _on_run_wave_started):
		waves.wave_started.connect(_on_run_wave_started)
	if waves.has_signal("wave_cleared") \
			and not waves.is_connected("wave_cleared", _on_run_wave_cleared):
		waves.wave_cleared.connect(_on_run_wave_cleared)
	if waves.has_method("guards"):
		for guard in waves.guards():
			_watch_guard(guard)

func _watch_guard(guard: Node) -> void:
	if guard == null or not is_instance_valid(guard):
		return
	if not guard.has_signal("killed") or guard.is_connected("killed", _on_run_guard_killed):
		return
	guard.killed.connect(_on_run_guard_killed)

func _on_run_wave_started(index: int, _count: int) -> void:
	_run_wave_count = maxi(_run_wave_count, index + 1)

func _on_run_wave_cleared(_index: int) -> void:
	_run_cleared_waves += 1

func _on_run_guard_killed(_slot: int, _source: int) -> void:
	_run_kills += 1

## Open a record for the battle about to happen. `waves` is optional: when it is
## given, this node reads the wave count and the kills off it. Returns the live
## record; calling twice answers the same one.
func begin_run(mode: String = "expedition", waves = null) -> RunReportScript:
	if run != null:
		return run
	run = RunReportScript.new()
	run.mode = mode
	run.start()
	_run_wave_count = 0
	_run_cleared_waves = 0
	_run_kills = 0
	_run_notes.clear()
	_run_gold_start = gold()
	_run_cruor_start = cruor.total()
	_run_items_start = _item_count()
	_run_body_ids = deployed_merc_ids()
	if _run_body_ids.is_empty():
		# No deployment line (a debug field): the bodies the warband owns still
		# get their outcome recorded, so a report is never empty of people.
		_run_body_ids = roster.ids()
	if waves != null and is_instance_valid(waves):
		_bind_waves(waves)
	_notify()
	return run

## Let the scene be explicit about a count this node cannot see by itself. The
## last call wins for `kills`/`items`; `waves`/`waves_cleared` keep whichever is
## larger, so a scene can only add detail, never shrink the record.
func note_run(kind: String, amount: int = 1) -> void:
	if run == null or amount == 0:
		return
	var key := str(kind)
	if not key in ["kills", "items", "waves", "waves_cleared"]:
		return
	_run_notes[key] = int(_run_notes.get(key, 0)) + amount

## Close the record and file it: outcome, stamps, the bodies' real health and the
## purse delta. Returns the filed payload. An empty `outcome` is derived from the
## record (nobody standing = a wipe; every wave broken = a clear).
func finish_run(outcome: String = "") -> Dictionary:
	if run == null:
		return {}
	var report: RunReportScript = run
	var now := int(Time.get_unix_time_from_system())
	report.ended_at = now
	report.seconds = maxi(0, now - report.started_at)
	# The spawner's own tally is the authority on its field: a director that fields
	# guest bodies this node cannot classify (an escort, a boss) still has them
	# counted, and a scene that retired a wave without a death cannot inflate it.
	var wave_kills := _run_kills
	var waves_fielded := _run_wave_count
	if _run_waves != null and is_instance_valid(_run_waves):
		if _run_waves.has_method("total_cleared"):
			wave_kills = maxi(wave_kills, int(_run_waves.total_cleared()))
		if _run_waves.has_method("wave"):
			waves_fielded = maxi(waves_fielded, int(_run_waves.wave()) + 1)
	report.waves = maxi(waves_fielded, int(_run_notes.get("waves", 0)))
	report.waves_cleared = maxi(_run_cleared_waves, int(_run_notes.get("waves_cleared", 0)))
	report.kills = int(_run_notes.get("kills", wave_kills))
	report.items = int(_run_notes.get("items", maxi(0, _item_count() - _run_items_start)))
	# The wallets are the truth of what the run paid; the ledger only records it.
	report.gold = maxi(0, gold() - _run_gold_start)
	report.cruor = maxi(0, cruor.total() - _run_cruor_start)
	report.bodies = _snapshot_bodies()
	report.outcome = outcome if str(outcome) in RunReportScript.OUTCOMES \
		else _derive_outcome(report)
	var payload: Dictionary = report.to_dict()
	_run_history.append(payload)
	_trim_run_history()
	RunReportScript.tally(run_totals, payload)
	_clear_run_state()
	_notify()
	return payload.duplicate(true)

## Drop the record without filing it (a new campaign is not a battle result).
func cancel_run() -> void:
	if run == null:
		return
	_clear_run_state()
	_notify()

func run_open() -> bool:
	return run != null

## The newest filed report, or an empty dictionary.
func last_run() -> Dictionary:
	return {} if _run_history.is_empty() else _run_history.back().duplicate(true)

## Oldest first; at most `RunReport.HISTORY_LIMIT` entries.
func run_history() -> Array[Dictionary]:
	return _run_history.duplicate(true)

## The lifetime counters (`runs`, `wins`, `wipes`, `best_wave`, and the sums).
func run_record() -> Dictionary:
	return run_totals.duplicate(true)

## What the warband holds in gear: the shared stash plus every worn piece. The
## difference across a battle is what the field yielded, without needing the loot
## vacuum - a piece taken and worn still counts exactly once.
func _item_count() -> int:
	var total := stash.pooled_total()
	for merc in roster.records():
		total += roster.worn_entries(int(merc.get("id", 0))).size()
	return total

## The bodies that took the field, as the roster holds them right now: the arena
## mirrors health and downed state into it every 0.4 s, so this is the truth at
## the moment the field is left.
func _snapshot_bodies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _run_body_ids:
		var merc_id := int(entry)
		if not roster.has(merc_id):
			continue
		out.append({
			"name": roster.name_of(merc_id),
			"health": roundf(roster.health_of(merc_id) * 10.0) / 10.0,
			"max_health": roster.max_health_of(merc_id),
			"state": RunReportScript.state_key(roster.state_of(merc_id)),
		})
	return out

func _derive_outcome(report: RunReportScript) -> String:
	var standing := 0
	for body in report.bodies:
		if str(body.get("state", "")) == RunReportScript.STATE_ALIVE:
			standing += 1
	if report.bodies.is_empty():
		return RunReportScript.OUTCOME_ABANDONED
	if standing == 0:
		# Nobody on their feet: the warband is down, whatever the field looked like.
		return RunReportScript.OUTCOME_WIPED
	if report.waves > 0 and report.waves_cleared >= report.waves:
		return RunReportScript.OUTCOME_CLEARED
	return RunReportScript.OUTCOME_ABANDONED

func _close_open_run() -> void:
	if run != null:
		finish_run()

func _clear_run_state() -> void:
	run = null
	_run_waves = null
	_run_wave_count = 0
	_run_cleared_waves = 0
	_run_kills = 0
	_run_notes.clear()
	_run_body_ids.clear()
	_run_gold_start = 0
	_run_cruor_start = 0
	_run_items_start = 0

## A brand-new campaign starts with no ledger. Called by `reset_state()`; a save
## written before the reset still holds the old history, which is what a load
## restores.
func _reset_run_records() -> void:
	_clear_run_state()
	_run_history.clear()
	run_totals = RunReportScript.blank_totals()

## Keep only the newest entries, whichever order the file was written in.
func _trim_run_history() -> void:
	while _run_history.size() > RunReportScript.HISTORY_LIMIT:
		_run_history.remove_at(0)

func _load_run_history(saved: Variant) -> void:
	_run_history.clear()
	if saved is Array:
		for entry in saved as Array:
			if entry is Dictionary:
				_run_history.append(_clean_report(entry))
	_trim_run_history()

## One saved entry read through the record's own sanitiser, so a hand-edited or
## older file is normalised (ints stay ints, states stay known) instead of
## poisoning the history with whatever JSON held.
func _clean_report(data: Dictionary) -> Dictionary:
	var report = RunReportScript.new()
	report.read_dict(data)
	return report.to_dict()
