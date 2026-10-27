extends SceneTree
## Battlefield looting regression for Ghost of the Warband: a real drop node a
## battle can leave on the ground, the instant single-piece pick, the
## end-of-battle sweep into the infinite shared stash, and the proof that the
## shipping catalog can fill all ten worn slots and every weapon subtype.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const StateScript = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const PickupScript = preload("res://scripts/warband/warband_pickup.gd")

const TEST_SAVE := "user://stash_autoloot_state.json"

## The five drops the battle leaves behind. Values descend cleanly
## (360 / 340 / 280 / 260 / 120) so the stash order is unambiguous.
const DROP_IDS := ["bow_long", "sword_great", "shield_tower", "focus_skull_death", "neck_ember"]
const QUICK_TAKE := "neck_ember"
const DROPPER := 7

var checks := 0
var failures := 0

var _warband = null
var _field: Node3D = null
var _loot: WarbandLoot = null
## item id -> the drop node this battle left for it.
var _drops: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("STASH_AUTOLOOT_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()
	_warband = warband

	check_coverage()

	_field = Node3D.new()
	_field.name = "Battlefield"
	root.add_child(_field)
	_loot = LootScript.new()
	_loot.name = "Loot"
	root.add_child(_loot)
	_loot.setup(warband, _field)

	check_drops_and_quick_loot()
	await check_dropper_lock()
	check_no_survivors()
	await check_sweep()
	check_infinite_stash()
	check_ten_slot_kit()

	_remove_test_save()
	print("STASH_AUTOLOOT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- gear vocabulary -------------------------------------------------------

func check_coverage() -> void:
	check(Rules.SLOTS.size() == 10, "there are ten worn slots")
	var candidates := _slot_candidates()
	for slot in Rules.SLOTS:
		var ids: Array = candidates.get(slot, [])
		check(not ids.is_empty(), "the catalog can fill the %s slot" % slot)
		if not ids.is_empty():
			check(Rules.allowed(StateScript.ITEMS[ids[0]], slot),
				"%s is legal in the %s slot" % [ids[0], slot])
	var by_subtype := {}
	for item_id in StateScript.ITEMS:
		var subtype := Contracts.weapon_subtype(StateScript.ITEMS[item_id])
		if subtype != Contracts.WeaponSubType.NONE:
			by_subtype[subtype] = str(item_id)
	for subtype in Contracts.WeaponSubType.values():
		if int(subtype) == Contracts.WeaponSubType.NONE:
			continue
		check(by_subtype.has(subtype), "a %s exists: %s" % [
			str(Contracts.WEAPON_LABELS[subtype]), str(by_subtype.get(subtype, "none"))])

# --- drops and the instant pick -------------------------------------------

func check_drops_and_quick_loot() -> void:
	var index := 0
	for item_id in DROP_IDS:
		var pickup := _loot.spawn(item_id, Vector3(float(index) * 2.0, 0.0, 0.0))
		_drops[item_id] = pickup
		index += 1
		check(pickup != null and is_instance_valid(pickup), "%s drops as a real node" % item_id)
		if pickup == null:
			continue
		check(pickup.get_parent() == _field, "%s is parented into the battlefield" % item_id)
		check(pickup.is_inside_tree(), "%s lies in the world, not in a mode-local list" % item_id)
		check(pickup.item_id == item_id, "%s keeps its catalog id" % item_id)
		check(pickup.armed, "%s starts as open loot" % item_id)
		check(pickup.label_text() == str(StateScript.ITEMS[item_id]["name"]),
			"%s wears its catalog name" % item_id)
		check(_has_mesh(pickup), "%s has a visible mesh" % item_id)
		check(_has_label(pickup), "%s has a visible label" % item_id)
	check(_loot.describe().begins_with("drops=5"),
		"the vacuum sees all five drops, got %s" % _loot.describe())

	var stash: WarbandStash = _warband.stash
	var take: WarbandPickup = _drops[QUICK_TAKE]
	var taken_ids: Array[String] = []
	take.taken.connect(func(picked: WarbandPickup) -> void: taken_ids.append(picked.item_id))
	var changes := [0]
	_warband.changed.connect(func() -> void: changes[0] += 1)
	var result := _loot.quick_loot(take, 1)
	check(bool(result.get("ok", false)), "a human quick-loots the drop under the crosshair")
	check(str(result.get("item_id", "")) == QUICK_TAKE, "the pick names the piece")
	check(stash.pooled_count(QUICK_TAKE) == 1, "the piece becomes a stash row at once")
	check(stash.pooled_total() == 1, "one pick is one piece, got %d" % stash.pooled_total())
	check(take.collected, "the drop reports itself taken")
	check(take.get_parent() == null and not take.is_inside_tree(), "the drop left the world")
	check(taken_ids.size() == 1 and taken_ids[0] == QUICK_TAKE,
		"the drop announces its one take, got %s" % str(taken_ids))
	check(changes[0] == 1, "the pick notifies the warband once, got %d" % int(changes[0]))

	var again := _loot.quick_loot(take, 2)
	check(not bool(again.get("ok", true)), "a second pick of the same node is refused")
	check(str(again.get("message", "")).contains("already"),
		"the refusal explains itself, got %s" % str(again.get("message", "")))
	check(stash.pooled_count(QUICK_TAKE) == 1, "a refused pick pays nothing")
	check(taken_ids.size() == 1 and changes[0] == 1, "a refused pick announces nothing")

# --- the dropper's lock ----------------------------------------------------

func check_dropper_lock() -> void:
	var stash: WarbandStash = _warband.stash
	var locked := _loot.spawn("dagger_makeshift", Vector3(12.0, 0.0, 0.0), false, DROPPER)
	check(locked != null, "a disarmed drop still lands in the world")
	if locked == null:
		return
	check(not locked.armed, "a disarmed drop starts locked")
	check(locked.dropper_peer == DROPPER, "the lock names the dropper")
	check(locked.blocked_for(DROPPER), "the dropper is the only blocked collector")
	check(not locked.blocked_for(8), "another collector is never blocked")

	var refused := _loot.quick_loot(locked, DROPPER)
	check(not bool(refused.get("ok", true)), "the dropper cannot take back their own drop")
	check(stash.pooled_count("dagger_makeshift") == 0, "the refused pick keeps the stash clean")
	check(not locked.collected and locked.get_parent() == _field,
		"the blocked drop stays on the ground")

	var other := _loot.quick_loot(locked, 8)
	check(bool(other.get("ok", false)), "a second collector takes the locked drop at once")
	check(stash.pooled_count("dagger_makeshift") == 1, "that piece reaches the shared stash")

	var cooldown := _loot.spawn("sword_makeshift", Vector3(14.0, 0.0, 0.0), false, DROPPER)
	check(cooldown != null, "a second disarmed drop exists")
	if cooldown == null:
		return
	var early := _loot.quick_loot(cooldown, DROPPER)
	check(not bool(early.get("ok", true)), "the lock holds while it is fresh")
	await create_timer(PickupScript.ARM_DELAY + 0.4).timeout
	check(cooldown.armed, "the lock expires on its own")
	check(not cooldown.blocked_for(DROPPER), "the dropper is no longer blocked")
	var retake := _loot.quick_loot(cooldown, DROPPER)
	check(bool(retake.get("ok", false)), "the dropper may take the piece back once the lock lifts")
	check(stash.pooled_count("sword_makeshift") == 1, "the recovered piece is in the stash")

# --- no survivors ----------------------------------------------------------

func check_no_survivors() -> void:
	var stash: WarbandStash = _warband.stash
	var before := stash.pooled_total()
	var result := _loot.sweep([])
	check(not bool(result.get("ok", true)), "a battle with no survivors gathers nothing")
	check(int(result.get("collected", -1)) == 0, "the empty sweep collects nothing")
	check((result.get("item_ids", []) as Array).is_empty(), "the empty sweep names no items")
	check(int(result.get("skipped", -1)) == 4,
		"all four drops are reported left behind, got %d" % int(result.get("skipped", -1)))
	check(str(result.get("message", "")).contains("No survivors"),
		"the result says why, got %s" % str(result.get("message", "")))
	check(stash.pooled_total() == before, "the stash is untouched by an empty sweep")
	for item_id in _drops:
		if item_id == QUICK_TAKE:
			continue
		var pickup: WarbandPickup = _drops[item_id]
		check(is_instance_valid(pickup) and not pickup.collected and pickup.get_parent() == _field,
			"%s stays where it fell" % item_id)

# --- the sweep -------------------------------------------------------------

func check_sweep() -> void:
	var stash: WarbandStash = _warband.stash
	var merc_id: int = _warband.add_mercenary("Looter")
	stash.add("armor_makeshift_feet", 1)
	var worn: Dictionary = _warband.equip_merc(merc_id, "feet", "armor_makeshift_feet")
	check(bool(worn.get("ok", false)), "the looter wears a piece before the sweep")

	var survivor := Node3D.new()
	survivor.name = "Survivor"
	root.add_child(survivor)
	survivor.global_position = Vector3(6.0, 0.0, 0.0)
	var far := _loot.spawn("ring_silver", Vector3(500.0, 0.0, 0.0))
	check(far != null, "a drop far off the battlefield exists")

	var result := _loot.sweep([survivor])
	check(bool(result.get("ok", false)), "a sweep with a survivor standing succeeds")
	check(int(result.get("collected", 0)) == 4,
		"the sweep gathers the remaining four, got %d" % int(result.get("collected", 0)))
	var expected: Array[String] = []
	for item_id in DROP_IDS:
		if item_id != QUICK_TAKE:
			expected.append(item_id)
	expected.sort()
	var got: Array = result.get("item_ids", [])
	var names_ok := got.size() == expected.size()
	for item_id in expected:
		if not item_id in got:
			names_ok = false
	check(names_ok, "the sweep names exactly the four drops, got %s" % str(got))
	check(int(result.get("skipped", 0)) == 1, "the drop 500 m away is out of reach")
	check(far != null and not far.collected and far.get_parent() == _field,
		"the unreachable drop stays in the world")
	check(stash.pooled_count("ring_silver") == 0, "an unreachable drop never enters the stash")

	for item_id in DROP_IDS:
		check(stash.pooled_count(item_id) == 1, "%s reached the shared stash exactly once" % item_id)
	# neck_ember + dagger_makeshift + sword_makeshift from the manual picks, the
	# four swept pieces, and the worn boots are out of the pool.
	check(stash.pooled_total() == 7, "seven pooled pieces after the sweep, got %d" % stash.pooled_total())

	var expected_value := 0
	for item_id in ["neck_ember", "dagger_makeshift", "sword_makeshift", "bow_long",
			"sword_great", "shield_tower", "focus_skull_death"]:
		expected_value += StashScript.value_of(item_id)
	check(_loot.battlefield_value() == expected_value,
		"the battlefield report values the haul by the stash rule, got %d of %d" % [
			_loot.battlefield_value(), expected_value])
	check(_loot.describe().begins_with("drops=1"),
		"only the unreachable drop is still lying there, got %s" % _loot.describe())

	var rows := stash.rows(_warband.roster, _warband.cruor.brands)
	check(rows.size() == 8, "seven pooled ids plus the worn piece, got %d" % rows.size())
	var present := {}
	for row in rows:
		present[str(row["item_id"])] = true
	for item_id in DROP_IDS:
		check(present.has(item_id), "%s is a row after the sweep" % item_id)
	check(str(rows[0]["item_id"]) == "bow_long",
		"the most valuable piece is the first row, got %s" % str(rows[0].get("item_id", "")))
	check(int(rows[0]["value"]) == StashScript.value_of("bow_long"),
		"the first row is valued at the longbow's price")
	var descending := true
	for index in range(1, rows.size()):
		if int(rows[index - 1]["value"]) < int(rows[index]["value"]):
			descending = false
	check(descending, "swept rows come back sorted by value, highest first")
	var consistent := true
	for row in rows:
		if int(row["pooled"]) + (row["worn"] as Array).size() != int(row["total"]):
			consistent = false
	check(consistent, "pooled plus worn equals total on every row")

	var worn_row := _row_of(rows, "armor_makeshift_feet")
	check(not worn_row.is_empty(), "the worn piece keeps its row after the sweep")
	check(int(worn_row.get("pooled", -1)) == 0 and int(worn_row.get("total", -1)) == 1,
		"the worn piece is counted once, not pooled and not lost")
	var tags: Array = worn_row.get("tags", [])
	check(tags.size() == 1 and str(tags[0]) == "Looter Boots",
		"the equipped tag survives the sweep, got %s" % str(tags))

	var swept: Array = []
	for item_id in DROP_IDS:
		if item_id != QUICK_TAKE:
			swept.append(_drops[item_id])
	await process_frame
	for pickup in swept:
		check(not is_instance_valid(pickup), "the sweep freed the drop node")

	survivor.queue_free()

# --- the stash is infinite -------------------------------------------------

func check_infinite_stash() -> void:
	_warband.reset_state()
	var stash: WarbandStash = _warband.stash
	stash.add("ring_copper", 1000)
	check(stash.pooled_count("ring_copper") == 1000, "a thousand copies of one id are stored")
	var rows := stash.rows(_warband.roster, _warband.cruor.brands)
	check(rows.size() == 1, "a thousand copies are one row, got %d" % rows.size())
	if rows.size() == 1:
		check(int(rows[0]["total"]) == 1000, "that row counts all thousand, got %d" % int(rows[0]["total"]))
		check(str(rows[0]["name"]) == str(StateScript.ITEMS["ring_copper"]["name"]),
			"the row still reads its catalog name")
		check(int(rows[0]["value"]) == StashScript.value_of("ring_copper"),
			"the row still reads its value")

	var ids: Array[String] = []
	for item_id in StateScript.ITEMS:
		ids.append(str(item_id))
	ids.sort()
	var added := 0
	while added < 500:
		stash.add(ids[added % ids.size()], 1)
		added += 1
	check(stash.pooled_total() == 1500,
		"1000 + 500 pieces are stored together, got %d" % stash.pooled_total())
	check(stash.pooled_total() > int(StateScript.STASH_CAPACITY),
		"the shared stash has no capacity wall, only the legacy %d slot array had" % int(StateScript.STASH_CAPACITY))
	check(stash.pooled_ids().size() == ids.size(), "every catalog id is pooled")

	rows = stash.rows(_warband.roster, _warband.cruor.brands)
	check(rows.size() == ids.size(), "one row per distinct id, got %d of %d" % [rows.size(), ids.size()])
	var total := 0
	var readable := true
	var descending := true
	for index in range(rows.size()):
		total += int(rows[index]["total"])
		if str(rows[index]["name"]).is_empty() or str(rows[index]["category"]).is_empty():
			readable = false
		if index > 0 and int(rows[index - 1]["value"]) < int(rows[index]["value"]):
			descending = false
	check(total == 1500, "the rows account for every piece, got %d" % total)
	check(readable, "every one of the %d rows has a name and a category" % rows.size())
	check(descending, "1500 pieces come back value-sorted, highest first")
	check(int(rows[0]["value"]) == StashScript.value_of("bow_long"),
		"the longbow leads the sorted stash, got %s" % str(rows[0].get("item_id", "")))
	check(int(_row_of(rows, "ring_copper").get("total", 0)) > 1000,
		"the thousand-copy row grew with the mix instead of capping")

# --- ten pieces, ten slots -------------------------------------------------

func check_ten_slot_kit() -> void:
	_warband.reset_state()
	var stash: WarbandStash = _warband.stash
	var candidates := _slot_candidates()
	var main_id := _first_of_category(candidates.get("main", []), "1h")
	var off_id := _first_of_category(candidates.get("off", []), "shield")
	check(not main_id.is_empty() and not off_id.is_empty(),
		"a one-hander and a shield can be worn together")
	var rings: Array = candidates.get("ring2", [])
	check(rings.size() > 1, "two rings are available for the two ring slots")
	var kit := {
		"head": _first(candidates, "head"),
		"chest": _first(candidates, "chest"),
		"hands": _first(candidates, "hands"),
		"legs": _first(candidates, "legs"),
		"feet": _first(candidates, "feet"),
		"neck": _first(candidates, "neck"),
		"ring1": str(rings[0]) if rings.size() > 0 else "",
		"ring2": str(rings[1]) if rings.size() > 1 else "",
		"main": main_id,
		"off": off_id,
	}
	check(str(kit["ring1"]) != str(kit["ring2"]), "two different rings fill both ring slots")

	var merc_id: int = _warband.add_mercenary("Full Kit")
	for slot in Rules.SLOTS:
		var item_id := str(kit[slot])
		stash.add(item_id, 1)
		var result: Dictionary = _warband.equip_merc(merc_id, slot, item_id)
		check(bool(result.get("ok", false)), "%s fits the %s slot" % [item_id, slot])

	var worn: Dictionary = _warband.roster.equipped_of(merc_id)
	var filled := 0
	for slot in Rules.SLOTS:
		if not str(worn.get(slot, "")).is_empty():
			filled += 1
	check(filled == 10, "all ten slots are filled at once, got %d" % filled)
	check(str(worn.get("main", "")) == main_id and str(worn.get("off", "")) == off_id,
		"the hands hold the one-hander and the shield together")

	var rows := stash.rows(_warband.roster, _warband.cruor.brands)
	var tagged := 0
	for row in rows:
		if int(row["total"]) == 1 and (row["tags"] as Array).size() == 1:
			tagged += 1
	check(rows.size() == 10 and tagged == 10,
		"ten worn pieces are ten tagged rows, got %d rows / %d tagged" % [rows.size(), tagged])

# --- helpers ---------------------------------------------------------------

## slot -> every catalog id legal in that slot, in catalog order. The single
## source of truth for "is the gear vocabulary complete".
func _slot_candidates() -> Dictionary:
	var out := {}
	for slot in Rules.SLOTS:
		out[slot] = []
	for item_id in StateScript.ITEMS:
		var item: Dictionary = StateScript.ITEMS[item_id]
		for slot in Rules.SLOTS:
			if Rules.allowed(item, slot):
				(out[slot] as Array).append(str(item_id))
	return out

func _first(candidates: Dictionary, slot: String) -> String:
	var ids: Array = candidates.get(slot, [])
	return "" if ids.is_empty() else str(ids[0])

func _first_of_category(ids: Array, category: String) -> String:
	for item_id in ids:
		if str(StateScript.ITEMS[item_id].get("category", "")) == category:
			return str(item_id)
	return ""

func _row_of(rows: Array, item_id: String) -> Dictionary:
	for row in rows:
		if str(row["item_id"]) == item_id:
			return row
	return {}

func _has_mesh(pickup: WarbandPickup) -> bool:
	for child in pickup.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			return true
	return false

func _has_label(pickup: WarbandPickup) -> bool:
	for child in pickup.get_children():
		if child is Label3D and not (child as Label3D).text.is_empty():
			return true
	return false
