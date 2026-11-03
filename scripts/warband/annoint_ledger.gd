extends RefCounted
## Where annointments live: one list of entry ids per **copy** of an item.
##
## A copy is addressed by `copy key` = `"<catalog id>#<ordinal>"`. Ordinals are
## minted per catalog id by whoever hands the item out (`Warband`), so two
## shortbows are two lists and an annointment welded to one is invisible to the
## other. That is the whole point of the sheet: the piece carries it, not the
## catalog row and not the body.
##
## The ledger is deliberately dumb about the world. It stores ids, validates them
## against the catalog, and answers three questions the rest of the game asks:
##
##   * what stats does this kit add?        -> `stats_for`
##   * what procs does it arm?              -> `procs_for`
##   * which skills does it wake?           -> `abilities_for`
##
## Those three answers are the contract with `Archer.apply_annointments`,
## `AnnointRuntime` and `AbilityRules`, so no consumer ever reads an entry.

const Catalog = preload("res://scripts/warband/annoint_catalog.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

## Kit-wide ceilings, counted across every worn piece, annointments only. They
## sit below the engine's own clamps (`move_scale` 2.0, `attack_rate` 3.0) so a
## player never reaches a limiter that silently does nothing.
const CEILINGS := {
	"health": 60.0,
	"stamina": 250.0,
	"stamina_regen": 0.50,
	"attack_speed": 0.25,
	"move_speed": 0.20,
	"melee_damage": 0.30,
	"ranged_damage": 0.30,
	"throw_damage": 0.30,
	"cooldown": 0.30,
	"gold_find": 0.50,
	"stagger": 0.60,
	"heal_on_kill": 25.0,
	"stamina_on_kill": 100.0,
}

## A drawback may not push a kit into the dirt.
const FLOOR := -0.25

## copy key -> Array[String] of entry ids, oldest first.
var pieces: Dictionary = {}


func clear() -> void:
	pieces = {}


static func key_of(item_id: String, ordinal: int) -> String:
	return "%s#%d" % [item_id, maxi(ordinal, 0)]


static func ref(item_id: String, ordinal: int) -> Dictionary:
	return {"item_id": item_id, "ordinal": maxi(ordinal, 0)}


# --- storage ---------------------------------------------------------------

func ids(item_id: String, ordinal: int = 0) -> Array[String]:
	var payload: Variant = pieces.get(key_of(item_id, ordinal), [])
	var out: Array[String] = []
	if payload is Array:
		for id in payload:
			out.append(str(id))
	return out


func count(item_id: String, ordinal: int = 0) -> int:
	return ids(item_id, ordinal).size()


func is_full(item_id: String, ordinal: int = 0) -> bool:
	return count(item_id, ordinal) >= Catalog.MAX_PER_PIECE


func has(item_id: String, ordinal: int, entry_id: String) -> bool:
	return ids(item_id, ordinal).has(entry_id)


## Returns false when the copy is full, already carries the entry, or the entry
## is not a thing this build can play.
func add(item_id: String, ordinal: int, entry_id: String) -> bool:
	var entry := Catalog.by_id(entry_id)
	if entry == null or not entry.wired:
		return false
	var current := ids(item_id, ordinal)
	if current.size() >= Catalog.MAX_PER_PIECE or current.has(entry_id):
		return false
	current.append(entry_id)
	pieces[key_of(item_id, ordinal)] = current
	return true


func remove_id(item_id: String, ordinal: int, entry_id: String) -> bool:
	var current := ids(item_id, ordinal)
	var index := current.find(entry_id)
	if index < 0:
		return false
	current.remove_at(index)
	_store(item_id, ordinal, current)
	return true


## The strip half of a replace: take the named one out, put the new one in, and
## keep the order stable so a card does not shuffle.
func replace(item_id: String, ordinal: int, removed_id: String, added_id: String) -> bool:
	var entry := Catalog.by_id(added_id)
	if entry == null or not entry.wired:
		return false
	var current := ids(item_id, ordinal)
	var index := current.find(removed_id)
	if index >= 0:
		current.remove_at(index)
	elif current.size() >= Catalog.MAX_PER_PIECE:
		return false
	if current.has(added_id):
		_store(item_id, ordinal, current)
		return true
	if index >= 0:
		current.insert(index, added_id)
	else:
		current.append(added_id)
	_store(item_id, ordinal, current)
	return true


func _store(item_id: String, ordinal: int, list: Array[String]) -> void:
	var key := key_of(item_id, ordinal)
	if list.is_empty():
		pieces.erase(key)
	else:
		pieces[key] = list


## Every copy ordinal that exists for this catalog id, ascending.
func ordinals_of(item_id: String) -> Array[int]:
	var out: Array[int] = []
	for key in pieces:
		var text := str(key)
		var cut := text.rfind("#")
		if cut <= 0:
			continue
		if text.substr(0, cut) != item_id:
			continue
		out.append(int(text.substr(cut + 1)))
	out.sort()
	return out


# --- reads for the rest of the game ---------------------------------------

## The live entries on a copy, unknown ids dropped (a save from an older build).
func entries_of(item_id: String, ordinal: int = 0) -> Array:
	var out: Array = []
	for id in ids(item_id, ordinal):
		var entry := Catalog.by_id(id)
		if entry != null and entry.wired:
			out.append(entry)
	return out


## The first annointed skill a copy carries, or "". Skill order is acquisition
## order, so the first ability welded on is the one that fires.
func ability_of(item_id: String, ordinal: int = 0) -> String:
	for entry in entries_of(item_id, ordinal):
		if int(entry.kind) == Catalog.Kind.ABILITY and not str(entry.ability).is_empty():
			if not AbilityRules.by_id(str(entry.ability)).is_empty():
				return str(entry.ability)
	return ""


## `refs` is an Array of `ref()` dictionaries: the worn pieces of one body.
func stats_for(refs: Array) -> Dictionary:
	var total := {}
	for payload in refs:
		if not payload is Dictionary:
			continue
		var item_id := str((payload as Dictionary).get("item_id", ""))
		var ordinal := int((payload as Dictionary).get("ordinal", 0))
		for entry in entries_of(item_id, ordinal):
			Catalog.apply_entry(total, entry)
	return _clamp(total)


func procs_for(refs: Array) -> Array:
	var out: Array = []
	for payload in refs:
		if not payload is Dictionary:
			continue
		var item_id := str((payload as Dictionary).get("item_id", ""))
		var ordinal := int((payload as Dictionary).get("ordinal", 0))
		for entry in entries_of(item_id, ordinal):
			if int(entry.kind) == Catalog.Kind.PROC:
				out.append(entry)
	return out


## Skill ids a kit wakes, in order. The caller caps them at the three slots.
func abilities_for(refs: Array, limit: int = 3) -> Array[String]:
	var out: Array[String] = []
	for payload in refs:
		if not payload is Dictionary:
			continue
		var item_id := str((payload as Dictionary).get("item_id", ""))
		var ordinal := int((payload as Dictionary).get("ordinal", 0))
		var skill := ability_of(item_id, ordinal)
		if skill.is_empty() or out.has(skill):
			continue
		out.append(skill)
		if out.size() >= limit:
			break
	return out


func _clamp(total: Dictionary) -> Dictionary:
	var out := {}
	for key in total:
		var value := float(total[key])
		var ceiling := float(CEILINGS.get(str(key), 0.0))
		if ceiling > 0.0:
			value = minf(value, ceiling)
		value = maxf(value, FLOOR)
		if not is_zero_approx(value):
			out[str(key)] = value
	return out


# --- reads for the item card ----------------------------------------------

## One label/value row per annointment, plus the header. Fed straight into
## `WarbandItemCard`'s detail rows.
func rows_for(item_id: String, ordinal: int = 0) -> Array:
	var out: Array = []
	var live := entries_of(item_id, ordinal)
	if live.is_empty():
		return out
	out.append({"label": "ANNOINTED", "value": "%d / %d" % [live.size(), Catalog.MAX_PER_PIECE]})
	for entry in live:
		out.append({"label": str(entry.name), "value": str(entry.line)})
	return out


## "3 annoints - Haste II, Leech, Whetstone Edge" for a hover line, or "".
func summary_for(item_id: String, ordinal: int = 0) -> String:
	var live := entries_of(item_id, ordinal)
	if live.is_empty():
		return ""
	var names := PackedStringArray()
	for entry in live:
		names.append(str(entry.name))
	return "%d annoints - %s" % [live.size(), ", ".join(names)]


## How much a body of this disposition wants this kit, 0..1. The arming pass and
## the squad's casting priority both read it.
func want_for(refs: Array, disposition: String) -> float:
	var total := 0.0
	var seen := 0
	for payload in refs:
		if not payload is Dictionary:
			continue
		var item_id := str((payload as Dictionary).get("item_id", ""))
		var ordinal := int((payload as Dictionary).get("ordinal", 0))
		for entry in entries_of(item_id, ordinal):
			total += float(entry.want(disposition))
			seen += 1
	return (total / float(seen)) if seen > 0 else 0.0


# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	var saved := {}
	for key in pieces:
		var list: Array = pieces[key]
		if list.is_empty():
			continue
		saved[str(key)] = list.duplicate()
	return {"pieces": saved}


func from_dict(data: Dictionary) -> void:
	clear()
	var saved: Variant = data.get("pieces", {})
	if not saved is Dictionary:
		return
	for key in saved:
		var text := str(key)
		var cut := text.rfind("#")
		if cut <= 0:
			continue
		var item_id := text.substr(0, cut)
		var ordinal := int(text.substr(cut + 1))
		var source: Variant = saved[key]
		if not source is Array:
			continue
		var kept: Array[String] = []
		for raw in source:
			var entry := Catalog.by_id(str(raw))
			if entry == null or not entry.wired:
				continue
			if kept.has(str(entry.id)) or kept.size() >= Catalog.MAX_PER_PIECE:
				continue
			kept.append(str(entry.id))
		_store(item_id, ordinal, kept)
