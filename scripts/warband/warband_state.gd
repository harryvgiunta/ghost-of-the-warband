extends Node
## Autoload `Warband`: the persistent soul, the roster, the infinite stash, the
## Cruor ledger and the recruiter, in one place.
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

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://warband_state.json"

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

func _ready() -> void:
	set_process(false)

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
func equip_merc(merc_id: int, slot_id: String, item_id: String) -> Dictionary:
	if stash.pooled_count(item_id) <= 0:
		return {"ok": false, "message": "That piece is not free in the stash.", "displaced": {}}
	var result := roster.equip(merc_id, slot_id, item_id)
	if not bool(result.get("ok", false)):
		return result
	stash.remove(item_id, 1)
	var displaced: Dictionary = result.get("displaced", {})
	for slot in displaced:
		var old_id := str(displaced[slot])
		if not old_id.is_empty():
			stash.add(old_id, 1)
	_notify()
	return result

## Strip a worn piece back into the pool.
func unequip_merc(merc_id: int, slot_id: String) -> String:
	var item_id := roster.unequip(merc_id, slot_id)
	if item_id.is_empty():
		return ""
	stash.add(item_id, 1)
	_notify()
	return item_id

func set_deployed(merc_id: int, on: bool) -> Dictionary:
	var result := roster.set_deployed(merc_id, on, deployment_cap)
	_notify()
	return result

func deploy_battle(merc_ids: Array) -> Array[int]:
	var fielded := roster.deploy(merc_ids, deployment_cap)
	_notify()
	return fielded

func gear_value(merc_id: int) -> int:
	var gear := roster.equipped_of(merc_id)
	var total := 0
	for slot in gear:
		var item_id := str(gear[slot])
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id, cruor.brand_of(item_id))
	return total

## The warband's combined worth, gear and essence, for the HUD and tests.
func total_value() -> int:
	var total := 0
	for merc in roster.records():
		var gear: Variant = merc.get("equipped", {})
		if gear is Dictionary:
			for slot in gear:
				var item_id := str(gear[slot])
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
	}

func from_dict(data: Dictionary) -> void:
	roster.from_dict(data.get("roster", {}))
	stash.from_dict(data.get("stash", {}))
	cruor.from_dict(data.get("cruor", {}))
	deployment_cap = clampi(int(data.get("deployment_cap", Contracts.MAX_DEPLOYMENT_CAP)),
		1, Contracts.MAX_DEPLOYMENT_CAP)
	seeded = roster.count() > 0
	_notify()

func save_state() -> void:
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

## One line for the log card and for tests.
func describe() -> String:
	return "mercs=%d alive=%d deployed=%d cap=%d gold=%d cruor=%d brands=%d stash=%d" % [
		roster.count(), roster.alive_count(), roster.deployed_count(), deployment_cap,
		gold(), cruor.total(), cruor.brands.size(), stash.pooled_total()]
