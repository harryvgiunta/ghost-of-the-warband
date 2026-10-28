extends SceneTree
## Watcher variants regression: the camp's watchers are rigged bodies with a
## deterministic kit table, and they fight like the arena bodies they now are.
##
## Nothing here reads a library in isolation. Watchers are instantiated exactly
## the way the camp does it (name, mob id and health pool set before the tree,
## position after), and every claim is asked of the live body: the table signs the
## same string twice, the mains are makeshift, `arm`/`take_weapon_item` round-trip
## through the rig, the corpse emits one `defeated`, and the authored animation
## player really contains the block/stab/crouch clips each body claims.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const Catalog = preload("res://scripts/player_state.gd")
const Scaler = preload("res://scripts/warband/damage_scaler.gd")

const SAMPLE := 12
const SPAWN_STEP := 3.0
## Off the ring the fallback for a watcher with no safe centre: the camp's own
## yard is the ring, and these bodies must not be tested against it.
const FAR_SAFE := Vector3(-900.0, 0.0, -900.0)
const CLIP_BLOCK_ONE := "Sword_Block_Loop_OneHand"
const CLIP_BLOCK_TWO := "Sword_Block_Loop"
const CLIP_STAB := "Dagger_Stab"
const CLIP_OVERHEAD := "Sword_Overhead"
const CLIP_OVERHEAD_ONE := "Sword_Overhead_OneHand"
const CLIP_CROUCH := "Crouch_Idle_Loop"
const ALL_CLIPS := [CLIP_BLOCK_ONE, CLIP_BLOCK_TWO, CLIP_STAB, CLIP_OVERHEAD,
	CLIP_OVERHEAD_ONE, CLIP_CROUCH]

var checks := 0
var failures := 0
var _field: Node3D
var _duplicates: Node3D
var _samples: Array = []
var _pairs: Array = []
var _defeats := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WATCHER_VARIANTS_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _on_defeated(_enemy, _reward) -> void:
	_defeats += 1


func run() -> void:
	Scaler.reset()
	_field = Node3D.new()
	_field.name = "WatcherField"
	root.add_child(_field)
	for index in SAMPLE:
		_samples.append(_spawn(_field, "Watcher%d" % index, index,
			WatcherScript.HARDENED_HEALTH))
	for index in 2:
		_pairs.append(_spawn(_field, "Pair%d" % index, SAMPLE + index,
			WatcherScript.PAIR_HEALTH))
	await physics_frame
	await physics_frame

	check_table()
	check_samples()
	await check_determinism()
	check_pairs()
	check_arm_round_trip()
	check_gear()
	check_clips()
	check_behaviour()
	check_death()
	check_downed_is_fatal()

	_field.queue_free()
	if _duplicates != null:
		_duplicates.queue_free()
	await process_frame
	Scaler.reset()
	print("WATCHER_VARIANTS_REGRESSION checks=", checks, " failures=", failures)
	if failures == 0:
		print("WATCHER_VARIANTS_OK ", checks)
	else:
		print("WATCHER_VARIANTS_FAILURES ", failures)
	quit(0 if failures == 0 else 1)


## Spawn one watcher the way a scene does: every field that `_ready` reads is set
## before the body enters the tree, and the position is settled after it can be.
func _spawn(parent: Node3D, label: String, index: int, health: float):
	var watcher = WatcherScript.new()
	watcher.name = label
	watcher.mob_id = "hollow_warden"
	watcher.health_pool = health
	watcher.position = Vector3(SPAWN_STEP * float(index), 0.1, 0.0)
	parent.add_child(watcher)
	watcher.global_position = Vector3(SPAWN_STEP * float(index), 0.1, 0.0)
	return watcher

# --- the table -------------------------------------------------------------

func check_table() -> void:
	var table: Array = WatcherScript.VARIANTS
	check(table.size() >= 10, "the variant table fields at least ten bodies (%d)" % table.size())
	var signatures := {}
	var tints := {}
	var scales: Array[float] = []
	var swing_kinds := {}
	var crouched := 0
	var guarded := 0
	for entry in table:
		var spec: Dictionary = entry
		var main_id := str(spec.get("main", ""))
		check(WatcherScript.MAKESHIFT_MAINS.has(main_id),
			"every table main is makeshift, got %s" % main_id)
		check(str(spec.get("armor", "")) in WatcherScript.WATCHER_ARMOUR,
			"every table armour set is a watcher set, got %s" % str(spec.get("armor", "")))
		var off := str(spec.get("off", ""))
		check(off.is_empty() or off == "shield_wood" or WatcherScript.MAKESHIFT_MAINS.has(off),
			"every off hand is empty, a shield or a makeshift piece, got %s" % off)
		check(Catalog.ITEMS.has(main_id), "the table's main is catalog gear (%s)" % main_id)
		var scale := float(spec.get("scale", 0.0))
		scales.append(scale)
		check(scale >= 0.88 and scale <= 1.12, "a body scale stays inside 0.88-1.12 (%f)" % scale)
		var guard := float(spec.get("guard", 1.0))
		check(guard >= 0.45 and guard <= 0.70 and guard < 1.0,
			"a guard chance is 45-70%% and never certain (%f)" % guard)
		if guard >= 0.45 and guard < 1.0:
			guarded += 1
		if bool(spec.get("crouch", false)):
			crouched += 1
		signatures[WatcherScript.signature_of(spec)] = true
		tints[(spec.get("tint", Color.WHITE) as Color).to_html(false)] = true
		for swing in WatcherScript.swing_pool_for(main_id):
			swing_kinds[str(swing)] = true
	check(signatures.size() >= 10, "the table signs at least ten distinct combinations (%d)"
		% signatures.size())
	check(tints.size() >= 5, "the paint is more than one colour (%d hues)" % tints.size())
	check(scales.min() < 0.92 and scales.max() > 1.08,
		"the table spans visibly different builds (%.2f-%.2f)" % [scales.min(), scales.max()])
	check(swing_kinds.size() >= 3, "the table mixes at least three melee swings (%s)"
		% str(swing_kinds.keys()))
	check(crouched >= 2, "some watchers are crouch-armed (%d)" % crouched)
	check(guarded == table.size(), "every watcher has a rolled guard, never a stance")

# --- the bodies ------------------------------------------------------------

func check_samples() -> void:
	check(_samples.size() == SAMPLE, "the field holds %d watchers" % SAMPLE)
	var signatures := {}
	var tints := {}
	for raw in _samples:
		var watcher = raw
		check(is_instance_valid(watcher) and watcher.alive, "a watcher stands on its feet")
		check(watcher.authoritative, "a watcher is simulated, not a replica")
		check(watcher.is_bot, "a watcher thinks for itself")
		check(is_equal_approx(float(watcher.max_health), WatcherScript.HARDENED_HEALTH),
			"a hardened watcher carries the camp pool (%.1f)" % float(watcher.max_health))
		var main_id := str(watcher.variant.get("main", ""))
		check(WatcherScript.MAKESHIFT_MAINS.has(main_id),
			"a watcher's hand is makeshift, got %s" % main_id)
		check(str(watcher.weapon_item) == main_id,
			"the catalog string matches the table (%s / %s)" % [str(watcher.weapon_item), main_id])
		check(watcher.has_weapon_visual(), "the main hand is really in the rig (%s)" % main_id)
		var kind := str(Catalog.ITEMS.get(main_id, {}).get("kind", ""))
		match kind:
			"dagger":
				check(watcher.rig.weapon == "dagger", "a shiv is held as a dagger (%s)" % main_id)
			"sword":
				check(watcher.rig.weapon == "sword", "a club or branch is a sword (%s)" % main_id)
			"bow":
				check(watcher.rig.weapon == "bow", "a twig bow is held as a bow (%s)" % main_id)
		check(is_equal_approx(watcher.body_scale(), float(watcher.variant.get("scale", 1.0))),
			"the body is built to its table scale")
		check(watcher.paint_tint().is_equal_approx(
			watcher.variant.get("tint", Color.WHITE) as Color),
			"the paint is the variant's colour")
		signatures[watcher.variant_signature()] = true
		tints[watcher.paint_tint().to_html(false)] = true
	check(signatures.size() >= 10, "the field fields at least ten distinct watchers (%d)"
		% signatures.size())
	check(tints.size() >= 4, "the field wears several colours (%d)" % tints.size())

func check_determinism() -> void:
	_duplicates = Node3D.new()
	_duplicates.name = "WatcherDuplicates"
	root.add_child(_duplicates)
	var first = _spawn(_duplicates, "Watcher0", 20, WatcherScript.HARDENED_HEALTH)
	var second = _spawn(_duplicates, "Watcher1", 21, WatcherScript.HARDENED_HEALTH)
	await physics_frame
	check(first.variant_signature() == _samples[0].variant_signature(),
		"the same id signs the same variant (%s / %s)"
		% [first.variant_signature(), _samples[0].variant_signature()])
	check(second.variant_signature() == _samples[1].variant_signature(),
		"the second ordinal is deterministic too")
	var once := WatcherScript.variant_index_for("hollow_warden", "CampWatcher7")
	var twice := WatcherScript.variant_index_for("hollow_warden", "CampWatcher7")
	check(once == twice, "the table index is a pure function of the id")
	check(WatcherScript.variant_index_for("hollow_warden", "CampWatcher1")
		!= WatcherScript.variant_index_for("hollow_warden", "CampWatcher2"),
		"consecutive ordinals walk different entries")
	check(first.weapon_item == _samples[0].weapon_item,
		"a duplicate spawn carries the same weapon")

func check_pairs() -> void:
	check(_pairs.size() == 2, "two thinned watchers field beside the rest")
	for raw in _pairs:
		var watcher = raw
		check(watcher.alive, "a pair watcher stands on its feet")
		check(is_equal_approx(float(watcher.max_health), WatcherScript.PAIR_HEALTH),
			"the pair carries the thin pool (%s)" % str(watcher.max_health))
		var main_id := str(watcher.weapon_item)
		check(main_id in ["dagger_ironwood", "club_makeshift"],
			"the pair is a shiv or a club, got %s" % main_id)
		check(watcher.variant.get("off", "") == "", "the pair carries no off hand")
		check(str(watcher.variant.get("armor", "")) in ["naked", "makeshift"],
			"the pair wears a shirt or salvage, got %s" % str(watcher.variant.get("armor", "")))
		check(watcher.guard_chance() < 0.56, "the pair still rolls its guard")
		check(watcher.has_weapon_visual(), "the pair's weapon is in its hand")

# --- the kit round trip -----------------------------------------------------

func check_arm_round_trip() -> void:
	var watcher = null
	for raw in _samples:
		if not str(raw.variant.get("off", "")).is_empty():
			watcher = raw
			break
	check(watcher != null, "one watcher of the field carries an off hand")
	if watcher == null:
		watcher = _samples[5]
	watcher.arm("branch_heavy")
	check(str(watcher.weapon_item) == "branch_heavy", "arm writes the catalog piece")
	check(watcher.has_weapon_visual(), "the branch is in the right hand")
	check(watcher.rig.weapon == "sword" and watcher.rig.sword_index == 4,
		"the rig holds the heavy branch profile (%s / %d)" % [watcher.rig.weapon,
			int(watcher.rig.sword_index)])
	check(watcher.gear_items().has("branch_heavy"), "the branch is on the corpse list")
	check(watcher.variant.get("off", "") != "", "the table entry still owns an off hand")
	check(watcher.kit.get("off", "") == "",
		"a two-hander drops the off hand through the kit rule")
	var taken = watcher.take_weapon_item()
	check(str(taken) == "branch_heavy", "take_weapon_item hands the piece back (%s)" % str(taken))
	check(str(watcher.weapon_item).is_empty(), "the catalog string is cleared")
	check(not watcher.has_weapon_visual(), "the hand is empty after the strip")
	check(watcher.rig.weapon == "none", "the rig is unarmed after the strip (%s)" % watcher.rig.weapon)
	check(not watcher.gear_items().has("branch_heavy"), "the corpse no longer lists the branch")
	watcher.arm("dagger_ironwood")
	check(watcher.rig.weapon == "dagger" and watcher.rig.dagger_index == 1,
		"re-arming puts the ironwood shiv profile back")
	check(watcher.has_weapon_visual(), "and the shiv is visible again")

func check_gear() -> void:
	var armoured = null
	var bare = null
	for raw in _samples:
		if str(raw.variant.get("armor", "")) == "naked":
			bare = raw
		elif armoured == null:
			armoured = raw
	check(armoured != null, "one watcher wears a salvage set")
	check(bare != null, "one watcher wears nothing but a shirt")
	if armoured != null:
		var gear: Array = armoured.gear_items()
		check(gear.has(str(armoured.weapon_item)), "the corpse lists the blade")
		var set_name := str(armoured.variant.get("armor", ""))
		var pieces := 0
		for item_id in gear:
			check(Catalog.ITEMS.has(str(item_id)), "corpse gear is catalog gear (%s)" % str(item_id))
			if str(item_id).begins_with("armor_%s_" % set_name):
				pieces += 1
		check(pieces >= 1, "the corpse lists the worn %s pieces (%d)" % [set_name, pieces])
		check(gear.size() == pieces + 1, "gear is the blade plus the worn pieces (%d)" % gear.size())
	if bare != null:
		var bare_gear: Array = bare.gear_items()
		check(bare_gear.size() == 1 and bare_gear[0] == str(bare.weapon_item),
			"a naked watcher drops only its blade (%s)" % str(bare_gear))

# --- the animation claims ---------------------------------------------------

func check_clips() -> void:
	var claimed_stab := false
	var claimed_overhead := false
	var claimed_one_hand := false
	var claimed_crouch := false
	var claimed_block := false
	for raw in _samples:
		var watcher = raw
		if str(Catalog.ITEMS.get(str(watcher.weapon_item), {}).get("kind", "")) == "bow":
			continue
		var claims: Array = watcher.claimed_clips()
		check(not claims.is_empty(), "a melee watcher claims its clips")
		for clip in claims:
			var clip_name := str(clip)
			check(watcher.rig_plays(clip_name), "the rig really carries %s" % clip_name)
			if clip_name == CLIP_STAB:
				claimed_stab = true
			elif clip_name == CLIP_OVERHEAD:
				claimed_overhead = true
			elif clip_name == CLIP_OVERHEAD_ONE:
				claimed_one_hand = true
			elif clip_name == CLIP_CROUCH:
				claimed_crouch = true
			elif clip_name == CLIP_BLOCK_ONE or clip_name == CLIP_BLOCK_TWO:
				claimed_block = true
		if watcher.swing_pool().has("stab"):
			check(claims.has(CLIP_STAB), "a shiv body claims the authored thrust")
	check(claimed_stab, "some watcher fights with the authored stab")
	check(claimed_overhead, "some watcher fights with the two-hand overhead")
	check(claimed_one_hand, "some watcher fights with the one-hand overhead")
	check(claimed_crouch, "some watcher claims the crouch idle")
	check(claimed_block, "some watcher claims an authored block loop")
	for clip in ALL_CLIPS:
		check(_samples[0].rig_plays(str(clip)),
			"the ranger rig carries the authored clip %s" % str(clip))

# --- behaviour --------------------------------------------------------------

func check_behaviour() -> void:
	var crouched := 0
	var standing := 0
	var swings := {}
	for raw in _samples:
		var watcher = raw
		check(watcher.guard_chance() >= 0.45 and watcher.guard_chance() <= 0.70,
			"the rolled guard is a share, not a certainty (%f)" % watcher.guard_chance())
		check(watcher.guard_chance() < 1.0, "no watcher guards every exchange")
		if watcher.crouch_armed():
			crouched += 1
		else:
			standing += 1
		for swing in watcher.swing_pool():
			swings[str(swing)] = true
		check(not watcher.hunting(), "an unpointed watcher is not hunting")
	check(crouched >= 2, "crouch-armed watchers exist (%d)" % crouched)
	check(standing >= 1, "and upright ones too (%d)" % standing)
	check(swings.size() >= 3, "the field mixes at least three swings (%s)" % str(swings.keys()))

	# The mob surface: a woken, pointed watcher has a live pursuit.
	var hunter = _samples[SAMPLE - 1]
	var quarry = _samples[SAMPLE - 2]
	check(not hunter.hunting(), "the hunter starts idle")
	hunter.safe_center = FAR_SAFE
	hunter.mob_wake()
	hunter.hunt(quarry)
	check(hunter.player == quarry, "hunt commits the body to its quarry")
	check(hunter.hunting(), "a woken watcher with a quarry in sight is hunting")
	check(hunter.get_aim_position().distance_to(hunter.global_position) > 0.1,
		"the body answers where it is aimed")

	# A body inside the camp's ring is never hunted: the yard is the safe centre.
	var guard = _samples[1]
	var caged = _samples[0]
	guard.hunt(caged)
	check(not guard.hunting(), "a quarry in the safe ring is not a pursuit")

# --- death ------------------------------------------------------------------

func check_death() -> void:
	var watcher = _samples[8]
	_defeats = 0
	watcher.defeated.connect(_on_defeated)
	watcher.take_damage(1000.0, 90)
	check(_defeats == 1, "a killed watcher reports its defeat exactly once (%d)" % _defeats)
	check(not watcher.alive, "the body is dead")
	check(not watcher.hunting(), "a corpse is not hunting")
	watcher.take_damage(1000.0, 90)
	check(_defeats == 1, "a blow on the corpse is not a second kill (%d)" % _defeats)
	check(is_instance_valid(watcher.rig) and watcher.rig.visible,
		"the body stays in the mud instead of vanishing")
	check(watcher.rig.is_downed_pose(), "the rig holds the prone pose")

func check_downed_is_fatal() -> void:
	# A watcher is a mob: the contract's downed state must not open a bleed clock
	# the camp never reads. The blow that would knock it down kills it instead.
	var watcher = _samples[9]
	_defeats = 0
	watcher.defeated.connect(_on_defeated)
	watcher.enter_downed(-1)
	check(_defeats == 1, "a knocked-down watcher dies once (%d)" % _defeats)
	check(not watcher.alive and not watcher.downed,
		"the body is dead, not waiting to be revived")
