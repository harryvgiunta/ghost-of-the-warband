class_name RogueliteMeta
extends Node
## Autoload `Roguelite`: the meta-progression ledger of the arena campaign.
##
## The keys a band earns, the weapons those keys have opened, and the loadout a
## body carries through the Start Run Portal all live here, in one file of their
## own (`user://roguelite_meta.json`) rather than in a campaign save. A run is
## not a campaign: the arena is played over and over from the Town Hub, and a
## weapon unlocked on the third run has to be there on the fourth even if the
## warband file was started fresh.
##
## The file is versioned and read defensively: an id this build no longer has is
## dropped, a loadout slot naming a weapon that is not unlocked falls back to the
## starter, and a newer file is left alone instead of being half-read.
##
## In co-op the pool is the host's. A guest carries its own unlocks from its own
## machine, and the host lends the rest by broadcasting its share (`share_pool`);
## `is_unlocked` answers for both, so a rack row draws what the party can
## actually field.

signal meta_changed
## One line for the HUD: a key earned, a weapon opened, a slot rebound.
signal announcement(text: String)

const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://roguelite_meta.json"
const RANGED_SLOT := "ranged"
const MELEE_SLOT := "melee"
const SLOTS := [RANGED_SLOT, MELEE_SLOT]
## What a fresh body walks into Hearthstead holding. These two are never locked:
## the whole point of the arc is that a band starts with a bow and a hatchet and
## earns the rest.
const DEFAULT_RANGED := "bow_twig"
const DEFAULT_MELEE := "hatchet_makeshift"
## What the Unlock Totem costs per roll. One stage clear pays two or three, so a
## run is worth a weapon and a half on its own.
const UNLOCK_COST := 3
## Keys a fresh ledger starts with, so the totem is a thing a player can touch on
## the very first walk into the square.
const STARTING_KEYS := 3

var keys := STARTING_KEYS
var unlocked: Array[String] = []
var loadout := {RANGED_SLOT: DEFAULT_RANGED, MELEE_SLOT: DEFAULT_MELEE}
var runs := 0
var best_stage := 0
var lifetime_kills := 0
var lifetime_keys := 0
var save_path := DEFAULT_SAVE_PATH
## The host's share, lent to this machine by `share_pool`. Empty on a host and in
## a single-player session, which is what makes the two cases the same case.
var shared_pool: Array[String] = []


func _ready() -> void:
	# Script regressions must never read or overwrite a player's ledger.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = "user://roguelite_meta_test.json"
	load_meta()


# --- the ledger ------------------------------------------------------------

func reset(persist: bool = true) -> void:
	keys = STARTING_KEYS
	unlocked.clear()
	loadout = {RANGED_SLOT: DEFAULT_RANGED, MELEE_SLOT: DEFAULT_MELEE}
	runs = 0
	best_stage = 0
	lifetime_kills = 0
	lifetime_keys = 0
	shared_pool.clear()
	if persist:
		save_meta()
	meta_changed.emit()


## Every weapon id this machine can field: the two starters, whatever its own
## keys opened, and whatever the host lent.
func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for id in Weapons.default_ids():
		if not out.has(id):
			out.append(id)
	for id in unlocked:
		if Weapons.has(id) and not out.has(id):
			out.append(id)
	for id in shared_pool:
		if Weapons.has(id) and not out.has(id):
			out.append(id)
	return out


func is_unlocked(weapon_id: String) -> bool:
	if Weapons.is_default(weapon_id):
		return true
	if unlocked.has(weapon_id):
		return true
	return shared_pool.has(weapon_id)


## The weapons a slot can be set to right now, in registry order.
func pool_for(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in Weapons.ids_for_slot(slot):
		if is_unlocked(id):
			out.append(id)
	return out


func loadout_for(slot: String) -> String:
	var id := str(loadout.get(slot, ""))
	if id.is_empty() or not is_unlocked(id) or Weapons.slot_of(id) != slot:
		return DEFAULT_RANGED if slot == RANGED_SLOT else DEFAULT_MELEE
	return id


## Bind a slot to an unlocked weapon. Refuses a locked piece, a piece that
## belongs in the other slot, and the same piece in both hands.
func set_loadout_slot(slot: String, weapon_id: String) -> Dictionary:
	if not SLOTS.has(slot):
		return {"ok": false, "message": "That is not a loadout slot."}
	if not Weapons.has(weapon_id):
		return {"ok": false, "message": "That weapon is not in the armory."}
	var weapon_slot := Weapons.slot_of(weapon_id)
	if weapon_slot != slot:
		return {"ok": false, "message": "%s belongs in the %s slot." % [
			Weapons.display_name(weapon_id), weapon_slot]}
	if not is_unlocked(weapon_id):
		return {"ok": false, "message": "%s is still locked. Open it at the totem." % [
			Weapons.display_name(weapon_id)]}
	var other := MELEE_SLOT if slot == RANGED_SLOT else RANGED_SLOT
	if loadout_for(other) == weapon_id:
		return {"ok": false, "message": "%s is already in the other hand." % [
			Weapons.display_name(weapon_id)]}
	loadout[slot] = weapon_id
	save_meta()
	meta_changed.emit()
	return {"ok": true, "message": "%s takes the %s slot." % [
		Weapons.display_name(weapon_id), slot]}


# --- keys and unlocks ------------------------------------------------------

func award_keys(amount: int, reason: String = "") -> int:
	var gained := maxi(0, amount)
	if gained <= 0:
		return 0
	keys += gained
	lifetime_keys += gained
	save_meta()
	meta_changed.emit()
	var line := "+%d KEY%s" % [gained, "" if gained == 1 else "S"]
	if not reason.is_empty():
		line += "  ·  %s" % reason
	announcement.emit(line)
	return gained


func spend_keys(amount: int) -> bool:
	var price := maxi(0, amount)
	if price <= 0:
		return true
	if keys < price:
		return false
	keys -= price
	save_meta()
	meta_changed.emit()
	return true


## What the Unlock Totem would open, without spending. The totem shows the roll
## it can pay for so the walk to it is never a blind bet.
func unlock_preview(rng: RandomNumberGenerator = null) -> String:
	var pool := locked_ids()
	if pool.is_empty():
		return ""
	var die := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		die.randomize()
	return str(pool[die.randi_range(0, pool.size() - 1)])


## The weapons that are still behind the totem, cheapest first. A pool that only
## ever offered the dearest piece would make the first three keys feel like a tax.
func locked_ids() -> Array[String]:
	var out: Array[String] = []
	for id in Weapons.all_ids():
		if not is_unlocked(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var cost_a := int(Weapons.get_weapon(a).get("unlock_cost", 3))
		var cost_b := int(Weapons.get_weapon(b).get("unlock_cost", 3))
		if cost_a == cost_b:
			return a < b
		return cost_a < cost_b)
	return out


## Spend the totem's price and open one random locked weapon.
func roll_unlock(rng: RandomNumberGenerator = null) -> Dictionary:
	if keys < UNLOCK_COST:
		return {"ok": false, "message": "The totem wants %d keys. You carry %d." % [
			UNLOCK_COST, keys]}
	var pool := locked_ids()
	if pool.is_empty():
		return {"ok": false, "message": "Every weapon in the armory is already open."}
	var die := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		die.randomize()
	var picked := str(pool[die.randi_range(0, pool.size() - 1)])
	spend_keys(UNLOCK_COST)
	unlocked.append(picked)
	save_meta()
	meta_changed.emit()
	var text := "%s is open. It stands on the rack." % Weapons.display_name(picked)
	announcement.emit(text)
	return {"ok": true, "id": picked, "name": Weapons.display_name(picked),
		"message": text}


func note_run(stage_reached: int, kills: int = 0) -> void:
	runs += 1
	best_stage = maxi(best_stage, stage_reached)
	lifetime_kills += maxi(0, kills)
	save_meta()
	meta_changed.emit()


# --- co-op ----------------------------------------------------------------

## The host's share of the pool. A guest calls this with what the host sent; a
## host calls it empty once the session ends, which takes the loan back out of
## its own rack.
func share_pool(ids: Array) -> void:
	shared_pool.clear()
	for raw in ids:
		var id := str(raw)
		if Weapons.has(id) and not shared_pool.has(id):
			shared_pool.append(id)
	meta_changed.emit()


## What this machine lends a guest: its own opened steel and nothing of the loan
## it was handed, so two guests cannot pass a host's pool between themselves.
func lent_pool() -> Array:
	return unlocked.duplicate()


# --- persistence -----------------------------------------------------------

func save_meta() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Roguelite: cannot write %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"keys": keys,
		"unlocked": unlocked,
		"loadout": loadout,
		"runs": runs,
		"best_stage": best_stage,
		"lifetime_kills": lifetime_kills,
		"lifetime_keys": lifetime_keys,
	}, "\t"))
	file.close()


func load_meta() -> void:
	if not FileAccess.file_exists(save_path):
		_ensure_defaults()
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		_ensure_defaults()
		return
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_ensure_defaults()
		return
	var data: Dictionary = parsed
	if int(data.get("version", 0)) > SAVE_VERSION:
		# A ledger from a newer build is left as it stands; reading half of it
		# would quietly spend a player's keys on a weapon this build cannot hold.
		_ensure_defaults()
		return
	keys = maxi(0, int(data.get("keys", 0)))
	runs = maxi(0, int(data.get("runs", 0)))
	best_stage = maxi(0, int(data.get("best_stage", 0)))
	lifetime_kills = maxi(0, int(data.get("lifetime_kills", 0)))
	lifetime_keys = maxi(0, int(data.get("lifetime_keys", 0)))
	unlocked.clear()
	var raw_unlocked: Variant = data.get("unlocked", [])
	if raw_unlocked is Array:
		for entry in raw_unlocked:
			var id := str(entry)
			if Weapons.has(id) and not Weapons.is_default(id) and not unlocked.has(id):
				unlocked.append(id)
	var raw_loadout: Variant = data.get("loadout", {})
	if raw_loadout is Dictionary:
		var saved: Dictionary = raw_loadout
		for slot in SLOTS:
			var id := str(saved.get(slot, ""))
			if not id.is_empty() and Weapons.slot_of(id) == slot and (Weapons.is_default(id) or unlocked.has(id)):
				loadout[slot] = id
	_ensure_defaults()


func _ensure_defaults() -> void:
	if not Weapons.has(DEFAULT_RANGED) or not Weapons.has(DEFAULT_MELEE):
		push_error("Roguelite: the starter weapons are missing from the registry")
		return
	if not is_unlocked(str(loadout.get(RANGED_SLOT, ""))) or Weapons.slot_of(str(loadout.get(RANGED_SLOT, ""))) != RANGED_SLOT:
		loadout[RANGED_SLOT] = DEFAULT_RANGED
	if not is_unlocked(str(loadout.get(MELEE_SLOT, ""))) or Weapons.slot_of(str(loadout.get(MELEE_SLOT, ""))) != MELEE_SLOT:
		loadout[MELEE_SLOT] = DEFAULT_MELEE


func describe() -> String:
	return "%d key%s  ·  %d/%d weapons open  ·  best stage %d" % [
		keys, "" if keys == 1 else "s", unlocked_ids().size(), Weapons.all_ids().size(),
		best_stage]
