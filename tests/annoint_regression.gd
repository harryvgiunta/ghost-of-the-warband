extends SceneTree
## The annointment pool, its roll and its ledger - including the altar stress:
## 99,999 rituals in a row, every invariant checked, the distribution printed.
##
## What this owns:
##   * the catalog's invariants (unique ids, real stat keys, wired abilities)
##   * applicability (a bow never rolls a melee entry, a shield never a two-hand)
##   * the die's four bands, the cap conversion, determinism under a seed
##   * the ledger: per-copy independence, cap, duplicates, ceilings, round trip
##   * 99,999 rituals with no piece over six, no duplicate, no dead entry
##
## Run: godot --headless --path . --script res://tests/annoint_regression.gd

const Catalog = preload("res://scripts/warband/annoint_catalog.gd")
const Roll = preload("res://scripts/warband/annoint_roll.gd")
const Ledger = preload("res://scripts/warband/annoint_ledger.gd")
const Stats = preload("res://scripts/trinket_stats.gd")
const Rules = preload("res://scripts/ability_rules.gd")
const State = preload("res://scripts/player_state.gd")
const Runtime = preload("res://scripts/warband/annoint_runtime.gd")
const Marks = preload("res://scripts/annoint_marks.gd")
const SwordScript = preload("res://scripts/sword.gd")
const DaggerScript = preload("res://scripts/dagger.gd")
const StaffScript = preload("res://scripts/staff.gd")
const ShieldScript = preload("res://scripts/shield.gd")
const BowScript = preload("res://scripts/bow.gd")
const FocusScript = preload("res://scripts/focus_item.gd")

const RITUALS := 99999

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("ANNOINT_FAIL  ", message)
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func _on_watchdog() -> void:
	print("ANNOINT_REGRESSION checks=", checks, " failures=", failures, " (watchdog)")
	quit(1)


## The items the stress walks: every weapon family plus one armour family.
const SAMPLE_ITEMS := [
	"sword_short", "sword_arming", "sword_great", "dagger_iron", "dagger_ironwood",
	"bow_short", "bow_recurve", "bow_long", "staff_fire", "staff_bone",
	"shield_buckler", "shield_kite", "shield_tower", "focus_tome", "focus_skull",
]

const SAMPLE_ARMOUR := ["head", "chest", "hands", "legs", "feet"]

func run() -> void:
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(_on_watchdog)
	print("ANNOINT_REGRESSION start")

	_check_catalog()
	_check_applicability()
	_check_die()
	_check_ledger()
	_check_marks()
	_check_runtime()
	_check_stress()

	print("ANNOINT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


# --- the pool --------------------------------------------------------------

func _check_catalog() -> void:
	var seen := {}
	var wired := 0
	var abilities := 0
	for entry in Catalog.all():
		check(not str(entry.id).is_empty(), "entry with no id")
		check(not seen.has(entry.id), "duplicate entry id %s" % entry.id)
		seen[entry.id] = true
		check(not str(entry.name).is_empty(), "entry %s has no name" % entry.id)
		check(not str(entry.line).is_empty(), "entry %s has no card line" % entry.id)
		check(not entry.groups.is_empty(), "entry %s names no gear group" % entry.id)
		check(not entry.slots.is_empty(), "entry %s names no slot" % entry.id)
		check(not entry.tags.is_empty(), "entry %s is unclassed for AI" % entry.id)
		for tag in entry.tags:
			check(tag in ["offence", "defence", "utility", "sustain", "control", "tempo",
				"melee", "ranged", "mobility", "ability"], "unknown tag %s on %s" % [tag, entry.id])
		for disposition in ["tank", "melee", "bow"]:
			var want := float(entry.want(disposition))
			check(want >= 0.0 and want <= 1.0, "%s want(%s) out of range" % [entry.id, disposition])
		if not entry.wired:
			continue
		wired += 1
		# Every stat key must be one the shared aggregation already sums, or the
		# entry would write into a dictionary nothing reads.
		for key in entry.stats:
			check(Stats.DEFAULT.has(str(key)), "%s writes unknown stat %s" % [entry.id, key])
		for key in entry.drawback:
			check(Stats.DEFAULT.has(str(key)), "%s drawback uses unknown stat %s" % [entry.id, key])
		match int(entry.kind):
			Catalog.Kind.STAT:
				check(not entry.stats.is_empty(), "%s is a STAT with no stats" % entry.id)
			Catalog.Kind.PROC:
				check(int(entry.trigger) >= 0 and int(entry.trigger) <= Catalog.Trigger.KILL,
					"%s has no trigger" % entry.id)
				check(int(entry.proc) >= 0 and int(entry.proc) <= Catalog.Proc.BLEED,
					"%s has no proc verb" % entry.id)
				check(entry.chance > 0.0 and entry.chance <= 1.0,
					"%s chance out of range" % entry.id)
				check(not is_zero_approx(entry.magnitude + entry.scale)
					or entry.proc in [Catalog.Proc.LETHAL_SAVE, Catalog.Proc.GUARD_BREAK],
					"%s has no magnitude" % entry.id)
			Catalog.Kind.ABILITY:
				abilities += 1
				check(not entry.ability.is_empty(), "%s is an ABILITY with no id" % entry.id)
				check(not Rules.by_id(entry.ability).is_empty(),
					"%s wakes unknown ability %s" % [entry.id, entry.ability])
	var total := Catalog.all().size()
	print("  pool: %d entries (%d wired, %d abilities)" % [total, wired, abilities])
	check(total > 100, "the pool should be more than a hundred entries")
	check(wired > 60, "too few wired entries: %d" % wired)


func _check_applicability() -> void:
	var sword := Catalog.for_item(State.ITEMS["sword_short"])
	var dagger := Catalog.for_item(State.ITEMS["dagger_iron"])
	var greatsword := Catalog.for_item(State.ITEMS["sword_great"])
	var bow := Catalog.for_item(State.ITEMS["bow_short"])
	var shield := Catalog.for_item(State.ITEMS["shield_kite"])
	var staff := Catalog.for_item(State.ITEMS["staff_fire"])
	var tome := Catalog.for_item(State.ITEMS["focus_tome"])
	# A pool may hold a shared entry (a bow entry that also fits a sword), so the
	# rule is about the entry's *only* home: a bow must never roll something that
	# is melee-only, and no pool may offer an off-hand-only entry to a main hand.
	for entry in bow:
		check(not _only(entry.groups, Catalog.GROUP_MELEE), "bow rolled melee-only %s" % entry.id)
		check(not _only(entry.groups, Catalog.GROUP_TWO_HAND), "bow rolled 2H-only %s" % entry.id)
		check(not entry.groups.has(Catalog.GROUP_ARMOUR), "bow rolled armour entry %s" % entry.id)
		check(not _only(entry.slots, Catalog.SLOT_OFF), "bow rolled an off-hand-only entry %s" % entry.id)
	for entry in dagger:
		check(not _only(entry.groups, Catalog.GROUP_TWO_HAND), "dagger rolled 2H-only %s" % entry.id)
		check(not _only(entry.groups, Catalog.GROUP_BOW), "dagger rolled bow-only %s" % entry.id)
	for entry in greatsword:
		check(not _only(entry.slots, Catalog.SLOT_OFF), "2H rolled an off-hand-only entry %s" % entry.id)
		check(not _only(entry.groups, Catalog.GROUP_BOW), "2H rolled a bow-only entry %s" % entry.id)
	for entry in shield:
		check(entry.slots.has(Catalog.SLOT_OFF), "shield entry %s not off-hand" % entry.id)
		check(not _only(entry.slots, Catalog.SLOT_MAIN), "shield rolled a main-hand-only entry %s" % entry.id)
		check(not entry.groups.has(Catalog.GROUP_ARMOUR), "shield rolled armour entry %s" % entry.id)
	check(not shield.is_empty(), "the shield pool is empty")
	check(not tome.is_empty(), "the focus pool is empty")
	for entry in tome:
		check(entry.groups.has(Catalog.GROUP_FOCUS) or _only(entry.groups, Catalog.GROUP_ANY_WEAPON),
			"tome rolled %s" % entry.id)
		check(not _only(entry.slots, Catalog.SLOT_MAIN), "tome rolled a main-hand-only entry %s" % entry.id)
	# Armour: every pool is armour-grouped and names its own slot.
	for slot in SAMPLE_ARMOUR:
		var pool := Catalog.for_armour_slot(slot)
		check(not pool.is_empty(), "empty armour pool for %s" % slot)
		for entry in pool:
			check(entry.groups.has(Catalog.GROUP_ARMOUR), "%s welded to %s" % [entry.id, slot])
			check(entry.slots.has(slot), "%s does not fit %s" % [entry.id, slot])
	# A one-hander fits either hand; a staff never fits the off hand.
	check(Catalog.slots_of(State.ITEMS["dagger_iron"]).size() == 2, "dagger should fit both hands")
	check(not Catalog.slots_of(State.ITEMS["staff_fire"]).has(Catalog.SLOT_OFF), "staff took the off hand")
	check(sword.size() > 10, "sword pool too thin: %d" % sword.size())
	check(staff.size() > 5, "staff pool too thin: %d" % staff.size())
	print("  pools: sword %d, dagger %d, 2h %d, bow %d, staff %d, shield %d, tome %d" % [
		sword.size(), dagger.size(), greatsword.size(), bow.size(), staff.size(),
		shield.size(), tome.size()])


# --- the die ---------------------------------------------------------------

func _check_die() -> void:
	check(Roll.outcome_of(0) == Roll.Outcome.ADD_ABILITY, "band 0")
	check(Roll.outcome_of(24) == Roll.Outcome.ADD_ABILITY, "band 24")
	check(Roll.outcome_of(25) == Roll.Outcome.ADD_PASSIVE, "band 25")
	check(Roll.outcome_of(49) == Roll.Outcome.ADD_PASSIVE, "band 49")
	check(Roll.outcome_of(50) == Roll.Outcome.REMOVE, "band 50")
	check(Roll.outcome_of(74) == Roll.Outcome.REMOVE, "band 74")
	check(Roll.outcome_of(75) == Roll.Outcome.REPLACE, "band 75")
	check(Roll.outcome_of(99) == Roll.Outcome.REPLACE, "band 99")
	var pool := Catalog.for_item(State.ITEMS["sword_short"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# Determinism: the same seed walks the same path.
	var first: Array[String] = []
	for i in 40:
		first.append(str(Roll.roll(pool, [], false, rng)["entry_id"]))
	rng.seed = 4242
	for i in 40:
		var again := str(Roll.roll(pool, [], false, rng)["entry_id"])
		check(again == first[i], "roll is not deterministic at step %d" % i)
	# An empty piece cannot be stripped.
	var empty_strip := Roll.roll(pool, [], false, _seed_with_known_rng(50))
	check(int(empty_strip["outcome"]) == Roll.Outcome.NOTHING, "empty piece was stripped")
	# A full piece converts an add into a replace and never grows past the cap.
	var full: Array[String] = []
	for i in Catalog.MAX_PER_PIECE:
		full.append(str(pool[i].id))
	var at_cap := Roll.roll(pool, full, true, _seed_with_known_rng(0))
	check(int(at_cap["outcome"]) == Roll.Outcome.REPLACE, "cap did not convert the add")
	check(bool(at_cap["converted"]), "cap conversion not reported")
	check(not str(at_cap["removed_id"]).is_empty(), "a replace must remove one")
	check(not str(at_cap["entry_id"]).is_empty(), "a replace must add one")


## True when `list` holds exactly one value and it is `value`.
func _only(list: Array, value: String) -> bool:
	return list.size() == 1 and str(list[0]) == value


## An RNG whose first draw is exactly `value`, so a band can be forced.
func _seed_with_known_rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed := 1
	while true:
		rng.seed = seed
		if rng.randi_range(0, 99) == value:
			break
		seed += 1
		if seed > 100000:
			push_error("could not find a seed for %d" % value)
			break
	rng.seed = seed
	return rng


# --- the ledger ------------------------------------------------------------

func _check_ledger() -> void:
	var ledger := Ledger.new()
	check(ledger.add("bow_short", 0, "f_weapon_attack_speed_2"), "first annointment refused")
	check(not ledger.has("bow_short", 1, "f_weapon_attack_speed_2"), "copies leaked")
	check(ledger.count("bow_short", 1) == 0, "second copy should be bare")
	check(not ledger.add("bow_short", 0, "f_weapon_attack_speed_2"), "duplicate accepted")
	check(not ledger.add("bow_short", 0, "made_up_entry"), "unknown entry accepted")
	check(not ledger.add("bow_short", 0, "x_ground_breaker"), "unwired entry accepted")
	# Cap.
	var head := Catalog.for_armour_slot("head")
	for i in 20:
		ledger.add("head_mail", 0, str(head[i].id))
	check(ledger.count("head_mail", 0) == Catalog.MAX_PER_PIECE,
		"cap not enforced: %d" % ledger.count("head_mail", 0))
	check(ledger.is_full("head_mail", 0), "is_full disagrees with count")
	# Replace keeps the count and swaps the entry.
	var before := ledger.ids("head_mail", 0)
	var incoming := ""
	for entry in head:
		if not before.has(str(entry.id)):
			incoming = str(entry.id)
			break
	check(not incoming.is_empty(), "the head pool is smaller than the cap")
	var ok := ledger.replace("head_mail", 0, before[0], incoming)
	check(ok, "replace refused")
	check(not ledger.has("head_mail", 0, before[0]), "replace kept the old entry")
	check(ledger.has("head_mail", 0, incoming), "replace dropped the new entry")
	check(ledger.count("head_mail", 0) == before.size(), "replace changed the count")
	# Stats: two refs, same key, sums then clamps at the ceiling.
	var refs := [Ledger.ref("head_mail", 0), Ledger.ref("chest_plate", 1)]
	ledger.add("chest_plate", 1, "f_weapon_attack_speed_5")
	if ledger.has("head_mail", 0, "f_weapon_attack_speed_1"):
		ledger.remove_id("head_mail", 0, "f_weapon_attack_speed_1")
	ledger.add("chest_plate", 1, "f_weapon_attack_speed_5")
	var stats := ledger.stats_for(refs)
	check(float(stats.get("attack_speed", 0.0)) <= float(Ledger.CEILINGS["attack_speed"]) + 0.0001,
		"attack speed ceiling breached: %s" % stats)
	# A drawback can go negative but never past the floor.
	var negative := {"melee_damage": 5.0 * -0.30}
	var clamped := ledger._clamp(negative)
	check(float(clamped.get("melee_damage", 0.0)) >= Ledger.FLOOR, "floor breached")
	# Ability selection: the first welded skill is the one that fires.
	var sword_pool := Catalog.abilities_of(Catalog.for_item(State.ITEMS["sword_great"]))
	if not sword_pool.is_empty():
		ledger.add("sword_great", 3, str(sword_pool[0].id))
		check(ledger.ability_of("sword_great", 3) == str(sword_pool[0].ability),
			"ability_of lost the skill")
	# Round trip.
	var saved := ledger.to_dict()
	var restored := Ledger.new()
	restored.from_dict(saved)
	check(restored.ids("head_mail", 0) == ledger.ids("head_mail", 0), "round trip changed a piece")
	# A corrupt save cannot smuggle a dead entry or an overflow past the loader.
	var corrupt := {"pieces": {"bow_short#0": ["f_weapon_attack_speed_1", "ghost_entry", "f_weapon_attack_speed_1",
		"f_weapon_attack_speed_2", "f_weapon_attack_speed_3", "f_weapon_attack_speed_4", "f_weapon_attack_speed_5", "f_weapon_cooldown_1"]}}
	var clean := Ledger.new()
	clean.from_dict(corrupt)
	check(clean.count("bow_short", 0) == Catalog.MAX_PER_PIECE,
		"loader let %d entries through" % clean.count("bow_short", 0))
	check(not clean.has("bow_short", 0, "ghost_entry"), "loader kept a dead entry")
	# The card reads.
	check(not ledger.rows_for("head_mail", 0).is_empty(), "card rows empty")
	check(not ledger.summary_for("head_mail", 0).is_empty(), "summary empty")
	check(ledger.want_for(refs, "tank") <= 1.0, "want_for out of range")


# --- the visible mark ------------------------------------------------------

## What a player actually sees: every weapon family draws one inlaid mark per
## annointment and glows a step brighter with each, a plain piece draws nothing
## at all, and re-stating the same count is free.
func _check_marks() -> void:
	check(Marks.tier_of(-3) == 0 and Marks.tier_of(99) == Marks.TIERS,
		"the altar's count is clamped to the six a piece can carry")
	check(Marks.material_for(0) == null,"a plain piece draws no inlaid material")
	var previous_energy := -1.0
	var previous_glyphs := -1
	for tier in range(0,Marks.TIERS + 1):
		check(Marks.energy_for(tier) > previous_energy,"the glow climbs with every rung (%d)" % tier)
		check(Marks.glyph_count(tier) > previous_glyphs,"every rung adds a mark (%d)" % tier)
		previous_energy = Marks.energy_for(tier)
		previous_glyphs = Marks.glyph_count(tier)
	check(Marks.color_for(1) != Marks.color_for(Marks.TIERS),
		"a full piece burns a different colour to a single annointment")

	var holder := Node3D.new()
	root.add_child(holder)
	var pieces: Array = []
	for index in 5:
		var sword := SwordScript.new()
		sword.sword_kind = index
		sword.blade_length = float([0.50,0.80,1.40,0.68,1.16][index])
		pieces.append(["sword_%d" % index,sword])
	for index in 2:
		var dagger := DaggerScript.new()
		dagger.dagger_kind = index
		dagger.blade_length = float([0.34,0.30][index])
		pieces.append(["dagger_%d" % index,dagger])
	for index in 2:
		var staff := StaffScript.new()
		staff.staff_kind = index
		staff.blade_length = float([1.60,1.50][index])
		pieces.append(["staff_%d" % index,staff])
	pieces.append(["shield",ShieldScript.new()])
	for index in 3:
		var bow := BowScript.new()
		bow.bow_kind = index
		bow.bow_length = float([1.30,1.40,1.55][index])
		pieces.append(["bow_%d" % index,bow])
	for kind in ["tome","skull","skull_life"]:
		var focus := FocusScript.new()
		focus.focus_kind = kind
		pieces.append(["focus_%s" % kind,focus])
	for entry in pieces:
		var label := str(entry[0])
		var piece: Node3D = entry[1]
		piece.set_annoint_marks(0)
		holder.add_child(piece)
		check(int(piece.annoint_glyphs()) == 0,"%s is plain" % label)
		var plain_surfaces := _emissive_surfaces(piece)
		piece.set_annoint_marks(1)
		var single := int(piece.annoint_glyphs())
		check(single > 0,"%s draws its mark for one annointment, got %d" % [label,single])
		piece.set_annoint_marks(Marks.TIERS)
		var full := int(piece.annoint_glyphs())
		check(full > single,"%s draws more marks at six than at one (%d > %d)" % [label,full,single])
		check(_emissive_surfaces(piece) > plain_surfaces,
			"%s adds a glowing surface once it is worked" % label)
		# Re-stating the same rung on every dress must not rebuild the piece.
		var first_child: Node = piece.get_child(0)
		piece.set_annoint_marks(Marks.TIERS)
		check(piece.get_child_count() > 0 and piece.get_child(0) == first_child,
			"%s is not rebuilt when the count has not moved" % label)
		piece.queue_free()
	holder.queue_free()


## How many surfaces of a piece carry an emission: the inlaid marks, once worked.
func _emissive_surfaces(piece: Node3D) -> int:
	var total := 0
	for node in piece.find_children("*","MeshInstance3D",true,false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		var override := mesh_instance.material_override
		if override is StandardMaterial3D and (override as StandardMaterial3D).emission_enabled:
			total += 1
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material: Material = mesh_instance.mesh.surface_get_material(surface)
				if material is StandardMaterial3D and (material as StandardMaterial3D).emission_enabled:
					total += 1
	return total


# --- the procs -------------------------------------------------------------

## A body-shaped stub: the runtime duck-types health, stamina and take_damage.
class Punchbag extends Node:
	var health := 100.0
	var max_health := 100.0
	var stamina := 1000.0
	var max_stamina := 1000.0
	var slot := 3
	var taken := 0.0

	func take_damage(amount: float, source_id: int, headshot: bool = false) -> void:
		taken += amount


func _check_runtime() -> void:
	var bag := Punchbag.new()
	root.add_child(bag)
	var playback = Runtime.new()
	playback.bind(bag)

	# An absorb takes its share off the incoming figure, then waits out the cd.
	playback.arm([Catalog.by_id("a_snap_stitching")])
	var absorbed := playback.on_incoming(100.0, 9)
	check(absorbed < 100.0 and absorbed > 79.0, "absorb did not bite: %.2f" % absorbed)
	check(is_equal_approx(playback.on_incoming(100.0, 9), 100.0), "absorb ignored its cooldown")
	playback.tick(10.5)
	check(playback.on_incoming(100.0, 9) < 100.0, "absorb never came off cooldown")

	# A lethal save leaves one health instead of a corpse, once per minute.
	playback.arm([Catalog.by_id("a_second_heart")])
	bag.health = 20.0
	var saved := playback.on_incoming(50.0, 9)
	check(saved <= 19.0, "the save did not clamp the blow: %.2f" % saved)
	check(playback.on_incoming(50.0, 9) >= 50.0, "the save fired twice in a row")

	# Heal and stamina pay the bearer, capped by the maxima.
	bag.health = 90.0
	bag.stamina = 990.0
	playback.arm([Catalog.by_id("w_thirst_hit"), Catalog.by_id("a_bone_rivets")])
	for i in 400:
		playback.after_damage(10.0, 9)
	check(bag.health <= bag.max_health + 0.001, "heal overshot the pool: %.2f" % bag.health)
	check(bag.health > 90.0, "heal never fired")
	check(bag.stamina <= bag.max_stamina + 0.001, "stamina overshot the pool")

	# A bleed walks the attacker's own take_damage, one point at a time.
	var attacker := Punchbag.new()
	root.add_child(attacker)
	playback.arm([Catalog.by_id("w_bleed_edge")])
	for i in 300:
		playback.note_attacker(attacker)
		playback.after_damage(10.0, attacker.slot)
	playback.tick(3.2)
	check(attacker.taken >= 5.0, "the bleed dealt %.1f in 3 s" % attacker.taken)

	# The attacker memory expires: a stale striker is never blamed.
	playback.arm([Catalog.by_id("w_bleed_edge")])
	playback.note_attacker(attacker)
	playback.tick(2.0)
	var before := attacker.taken
	playback.after_damage(10.0, attacker.slot)
	playback.tick(3.2)
	check(is_equal_approx(attacker.taken, before), "a stale attacker was still bled")
	bag.queue_free()
	attacker.queue_free()
	print("  procs: absorb, lethal save, heal, stamina, bleed, expiry all played")


# --- 99,999 rituals --------------------------------------------------------

func _check_stress() -> void:
	var started := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261103
	var ledger := Ledger.new()
	# Pools cached: building a pool per ritual would measure the catalog, not the die.
	var pools := {}
	for catalog_id in SAMPLE_ITEMS:
		pools[catalog_id] = {"item": State.ITEMS[catalog_id], "pool": Catalog.for_item(State.ITEMS[catalog_id])}
	for slot in SAMPLE_ARMOUR:
		pools[slot] = {"item": {"category": "armor", "slot": slot},
			"pool": Catalog.for_armour_slot(slot)}
	var keys: Array = pools.keys()
	var outcomes := {Roll.Outcome.ADD_ABILITY: 0, Roll.Outcome.ADD_PASSIVE: 0,
		Roll.Outcome.REMOVE: 0, Roll.Outcome.REPLACE: 0, Roll.Outcome.NOTHING: 0}
	# The die can only be measured on pieces with room: at the cap, half the
	# table is converted to a replace by design.
	var open_outcomes := {Roll.Outcome.ADD_ABILITY: 0, Roll.Outcome.ADD_PASSIVE: 0,
		Roll.Outcome.REMOVE: 0, Roll.Outcome.REPLACE: 0}
	var open_rolls := 0
	var capped_rolls := 0
	var converted := 0
	var seen_entries := {}
	var applied := 0
	var worst := 0
	var item_id := ""
	var ordinal := 0
	for i in RITUALS:
		var key: String = keys[i % keys.size()]
		var row: Dictionary = pools[key]
		var pool: Array = row["pool"]
		# Eight copies per key, walked round robin so caps are hit and replaced.
		ordinal = (i / keys.size()) % 8
		item_id = str(key)
		if item_id in SAMPLE_ARMOUR:
			item_id = "armour_" + key
		var existing := ledger.ids(item_id, ordinal)
		var at_cap := existing.size() >= Catalog.MAX_PER_PIECE
		var result := Roll.roll(pool, existing, at_cap, rng)
		var outcome := int(result["outcome"])
		outcomes[outcome] = int(outcomes[outcome]) + 1
		if at_cap:
			capped_rolls += 1
			if bool(result["converted"]):
				converted += 1
			check(outcome != Roll.Outcome.ADD_ABILITY and outcome != Roll.Outcome.ADD_PASSIVE,
				"a capped piece took an add")
		elif outcomes.has(outcome):
			open_outcomes[outcome] = int(open_outcomes.get(outcome, 0)) + 1
			open_rolls += 1
		if outcome == Roll.Outcome.ADD_ABILITY or outcome == Roll.Outcome.ADD_PASSIVE:
			if ledger.add(item_id, ordinal, str(result["entry_id"])):
				applied += 1
				seen_entries[str(result["entry_id"])] = true
		elif outcome == Roll.Outcome.REMOVE:
			ledger.remove_id(item_id, ordinal, str(result["removed_id"]))
		elif outcome == Roll.Outcome.REPLACE:
			if ledger.replace(item_id, ordinal, str(result["removed_id"]), str(result["entry_id"])):
				applied += 1
				seen_entries[str(result["entry_id"])] = true
		# Invariants, every ritual.
		var now: Array = ledger.ids(item_id, ordinal)
		worst = maxi(worst, now.size())
		if now.size() > Catalog.MAX_PER_PIECE:
			check(false, "ritual %d overflowed to %d" % [i, now.size()])
			break
		if i % 5000 == 0:
			_check_copy(item_id, ordinal, ledger, row["item"])
	_check_copy(item_id, ordinal, ledger, {})
	for catalog_id in SAMPLE_ITEMS:
		for copy in 8:
			_check_copy(catalog_id, copy, ledger, State.ITEMS[catalog_id])
	for slot in SAMPLE_ARMOUR:
		for copy in 8:
			_check_copy("armour_" + slot, copy, ledger, {"category": "armor", "slot": slot})

	var total := float(RITUALS)
	print("  rituals: %d in %d ms, %d annointments landed, %d converted at cap" % [
		RITUALS, Time.get_ticks_msec() - started, applied, converted])
	print("  distribution:", {
		"add_ability": int(outcomes[Roll.Outcome.ADD_ABILITY]),
		"add_passive": int(outcomes[Roll.Outcome.ADD_PASSIVE]),
		"remove": int(outcomes[Roll.Outcome.REMOVE]),
		"replace": int(outcomes[Roll.Outcome.REPLACE]),
		"nothing": int(outcomes[Roll.Outcome.NOTHING]),
	})
	for outcome in [Roll.Outcome.ADD_ABILITY, Roll.Outcome.ADD_PASSIVE,
			Roll.Outcome.REMOVE, Roll.Outcome.REPLACE]:
		var share := float(open_outcomes.get(outcome, 0)) / maxf(float(open_rolls), 1.0)
		check(absf(share - 0.25) < 0.02, "band %d landed at %.3f" % [outcome, share])
	print("  open pieces: %d rolls, capped pieces: %d rolls, %d adds converted at cap" % [
		open_rolls, capped_rolls, converted])
	print("  coverage: %d distinct annointments welded, deepest piece %d" % [
		seen_entries.size(), worst])
	check(seen_entries.size() > 40, "the stress barely touched the pool: %d" % seen_entries.size())
	check(worst <= Catalog.MAX_PER_PIECE, "a piece exceeded the cap")
	# At least some pieces must actually be full: otherwise the cap path is untested.
	var full_pieces := 0
	for catalog_id in SAMPLE_ITEMS:
		for copy in 8:
			if ledger.is_full(catalog_id, copy):
				full_pieces += 1
	print("  full pieces: %d" % full_pieces)
	check(full_pieces > 0, "no piece ever filled, so the cap path is untested")


## Every id on a copy must be a wired, applicable entry for that item.
func _check_copy(item_id: String, ordinal: int, ledger, item: Dictionary) -> void:
	var live: Array = ledger.ids(item_id, ordinal)
	check(live.size() <= Catalog.MAX_PER_PIECE, "%s#%d over the cap" % [item_id, ordinal])
	var seen := {}
	var applicable := {}
	if not item.is_empty():
		for entry in Catalog.for_item(item):
			applicable[str(entry.id)] = true
	for id in live:
		check(not seen.has(id), "%s#%d repeats %s" % [item_id, ordinal, id])
		seen[id] = true
		var entry := Catalog.by_id(id)
		check(entry != null, "%s#%d carries unknown %s" % [item_id, ordinal, id])
		if entry != null:
			check(entry.wired, "%s#%d carries unwired %s" % [item_id, ordinal, id])
		if not applicable.is_empty():
			check(applicable.has(id), "%s#%d carries %s, which is not in its pool" % [item_id, ordinal, id])
