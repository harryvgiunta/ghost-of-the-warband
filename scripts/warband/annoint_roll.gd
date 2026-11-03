extends RefCounted
## The altar's die. Pure rules, no state, no world: hand it a pool and the ids a
## piece already carries and it answers what the ichor did.
##
## Four outcomes, equal weight, and nothing is ever destroyed:
##
##   01-25  add an ability      (falls back to a passive, then to replace)
##   26-50  add a passive       (falls back to an ability, then to replace)
##   51-75  remove one, at random
##   76-00  replace one at random with one at random
##
## At the piece's cap the two add outcomes become a replace, so a full piece
## still spends every vial on something that happened.

const Catalog = preload("res://scripts/warband/annoint_catalog.gd")

enum Outcome { ADD_ABILITY, ADD_PASSIVE, REMOVE, REPLACE, NOTHING }

const BAND := 25
const CHANCES := {
	"add_ability": 0.25,
	"add_passive": 0.25,
	"remove": 0.25,
	"replace": 0.25,
}

## The outcome a `d100` of `value` lands on. Separate from `roll` so the altar can
## advertise the bands and the test can walk them without a pool.
static func outcome_of(value: int) -> int:
	var band := clampi(value, 0, 99) / BAND
	match band:
		0:
			return Outcome.ADD_ABILITY
		1:
			return Outcome.ADD_PASSIVE
		2:
			return Outcome.REMOVE
	return Outcome.REPLACE


static func label(outcome: int) -> String:
	match outcome:
		Outcome.ADD_ABILITY:
			return "ADD AN ABILITY"
		Outcome.ADD_PASSIVE:
			return "ADD A PASSIVE"
		Outcome.REMOVE:
			return "REMOVE ONE"
		Outcome.REPLACE:
			return "REPLACE ONE"
	return "NOTHING"


static func _rand(values: Array, rng: RandomNumberGenerator) -> Variant:
	if values.is_empty():
		return null
	return values[rng.randi_range(0, values.size() - 1)]


## Free entries from `pool` whose id is not already in `existing`.
static func _open(pool: Array, existing: Array[String]) -> Array:
	var out: Array = []
	for entry in pool:
		if existing.has(str(entry.id)):
			continue
		out.append(entry)
	return out


## One ritual. `pool` is `AnnointCatalog.for_item()` / `for_armour_slot()`,
## `existing` the ids on this copy, `at_cap` whether the piece is full.
##
## Returns `{outcome, converted, entry_id, removed_id, message}`; `entry_id` is
## `""` on REMOVE and `removed_id` is `""` when nothing was taken. `converted` is
## true when the cap turned an add into a replace.
static func roll(pool: Array, existing: Array[String], at_cap: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	var result := {"outcome": Outcome.NOTHING, "converted": false, "entry_id": "",
		"removed_id": "", "message": "The ichor does nothing."}
	if pool.is_empty():
		result["message"] = "There is nothing this piece can take."
		return result
	var drawn := rng.randi_range(0, 99)
	var outcome := outcome_of(drawn)
	if at_cap and (outcome == Outcome.ADD_ABILITY or outcome == Outcome.ADD_PASSIVE):
		outcome = Outcome.REPLACE
		result["converted"] = true
	match outcome:
		Outcome.ADD_ABILITY:
			return _add(pool, existing, true, result, rng)
		Outcome.ADD_PASSIVE:
			return _add(pool, existing, false, result, rng)
		Outcome.REMOVE:
			if existing.is_empty():
				result["outcome"] = Outcome.NOTHING
				result["message"] = "There is nothing on the piece to take."
				return result
			var stripped: String = _rand(existing, rng)
			result["outcome"] = Outcome.REMOVE
			result["removed_id"] = stripped
			result["message"] = "The ichor takes %s." % _name_of(pool, stripped)
			return result
		Outcome.REPLACE:
			return _replace(pool, existing, result, rng, drawn)
	return result


static func _add(pool: Array, existing: Array[String], want_ability: bool,
		result: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var kind_pool: Array = []
	for entry in pool:
		var is_ability := int(entry.kind) == Catalog.Kind.ABILITY
		if want_ability == is_ability:
			kind_pool.append(entry)
	var open := _open(kind_pool, existing)
	if open.is_empty():
		# That half of the pool is spent: the other half gets the vial.
		for entry in pool:
			var is_ability := int(entry.kind) == Catalog.Kind.ABILITY
			if want_ability != is_ability:
				open.append(entry)
		open = _open(open, existing)
	if open.is_empty():
		return _replace(pool, existing, result, rng, -1)
	var picked = _rand(open, rng)
	result["outcome"] = Outcome.ADD_ABILITY if want_ability else Outcome.ADD_PASSIVE
	result["entry_id"] = str(picked.id)
	result["message"] = "The ichor wakes %s." % str(picked.name)
	return result


static func _replace(pool: Array, existing: Array[String], result: Dictionary,
		rng: RandomNumberGenerator, drawn: int) -> Dictionary:
	var removed := ""
	if not existing.is_empty():
		removed = str(_rand(existing, rng))
	var kept: Array[String] = []
	for id in existing:
		if id != removed:
			kept.append(id)
	var open := _open(pool, kept)
	if open.is_empty():
		result["outcome"] = Outcome.NOTHING
		result["removed_id"] = ""
		result["message"] = "The ichor turns the piece over and settles again."
		return result
	var picked = _rand(open, rng)
	result["outcome"] = Outcome.REPLACE if drawn >= 0 else Outcome.REPLACE
	result["converted"] = bool(result.get("converted", false)) or drawn < 0
	result["entry_id"] = str(picked.id)
	result["removed_id"] = removed
	if removed.is_empty():
		result["message"] = "The ichor wakes %s." % str(picked.name)
	else:
		result["message"] = "%s goes, %s takes its place." % [
			_name_of(pool, removed), str(picked.name)]
	return result


## A name for an id, read off the pool first and the catalog second, so a strip
## of an entry the pool no longer offers still says what it took.
static func _name_of(pool: Array, id: String) -> String:
	for entry in pool:
		if str(entry.id) == id:
			return str(entry.name)
	var known := Catalog.by_id(id)
	return str(known.name) if known != null else id
