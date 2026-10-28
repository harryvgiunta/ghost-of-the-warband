extends SceneTree
## Watcher variants regression: the camp's watchers are the wood's antlered
## wardens again - one varied creature per body, armed with real makeshift steel
## and able to sweep, lunge, block, stagger and crouch.
##
## Nothing here reads a library in isolation. Watchers are instantiated exactly
## the way the camp does it (name, mob id and health pool set before the tree,
## position after), and every claim is asked of the live body: the table signs at
## least ten distinct signatures, the mains are makeshift, `arm`/`take_weapon_item`
## round-trip through the hand bone, `gear_items()` lists the blade and the rag,
## a killed watcher reports its defeat once, the guard/stagger/crouch rules answer
## from the body's own numbers, and the sampler reports the warden's three swings
## and its block/stagger/crouch clips.
##
## The five new clips are asserted against the imported GLB itself, so a sampler
## that promises a swing the asset does not bake fails here rather than falling
## back in silence.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const Mob = preload("res://scripts/forest_mob.gd")
const Visual = preload("res://scripts/forest_mob_visual.gd")
const Catalog = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Scaler = preload("res://scripts/warband/damage_scaler.gd")

const SAMPLE := 12
const SPAWN_STEP := 4.0
## Off the ring, for the hunting checks: these bodies must not be measured
## against the camp's yard.
const FAR_SAFE := Vector3(-900.0, 0.0, -900.0)
## The pinned clip contract: the sampler table promises these names, durations
## and impact frames, and the imported GLB has to bake them.
const SWING_CLIPS := {
	"overhead": ["Warden_Attack", 1.60, 0.78],
	"slash": ["Warden_Attack_Slash", 1.35, 0.66],
	"stab": ["Warden_Attack_Stab", 1.10, 0.50],
}
const BLOCK_CLIP := "Warden_Block"
const STAGGER_CLIP := "Warden_Stagger"
const CROUCH_CLIP := "Warden_Crouch"
const NEW_CLIPS := ["Warden_Attack_Slash", "Warden_Attack_Stab", "Warden_Block",
	"Warden_Stagger", "Warden_Crouch"]

var checks := 0
var failures := 0
var _field: Node3D
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
	# A floor, so a spawned body stands instead of falling through the void while
	# the checks run.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	floor_shape.shape = box
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	_field = Node3D.new()
	_field.name = "WatcherField"
	root.add_child(_field)
	for index in SAMPLE:
		_samples.append(_spawn(_field, "Watcher%d" % index,
			Vector3(SPAWN_STEP * float(index), 0.1, 0.0), WatcherScript.HARDENED_HEALTH))
	for index in 2:
		_pairs.append(_spawn(_field, "Pair%d" % (SAMPLE + index),
			Vector3(SPAWN_STEP * float(SAMPLE + index), 0.1, 0.0),
			WatcherScript.PAIR_HEALTH))
	await physics_frame
	await physics_frame

	check_table()
	check_bodies()
	check_pairs()
	await check_weapon()
	check_arm_round_trip()
	check_gear()
	await check_swing_arc()
	check_fight()
	await check_attack()
	await check_sampler()
	check_death()

	_field.queue_free()
	floor_body.queue_free()
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
func _spawn(parent: Node3D, label: String, at: Vector3, health: float):
	var watcher = WatcherScript.new()
	watcher.name = label
	watcher.mob_id = "hollow_warden"
	watcher.health_pool = health
	watcher.position = at
	parent.add_child(watcher)
	watcher.global_position = at
	return watcher

# --- the table -------------------------------------------------------------

func check_table() -> void:
	var table: Array = WatcherScript.VARIANTS
	check(table.size() >= 10, "the variant table fields at least ten bodies (%d)" % table.size())
	check(WatcherScript.PAIR_HEALTH >= 30.0
		and WatcherScript.PAIR_HEALTH < WatcherScript.HARDENED_HEALTH,
		"the pair's pool is thinner than the hardened one and still a fight")
	var signatures := {}
	var tints := {}
	var scales: Array[float] = []
	var swings := {}
	var crouched := 0
	var previous := ""
	for entry in table:
		var spec: Dictionary = entry
		var main_id := str(spec.get("main", ""))
		var favourite := str(spec.get("swing", ""))
		check(WatcherScript.MAKESHIFT_TIER.has(main_id),
			"every table main is makeshift, got %s" % main_id)
		check(SWING_CLIPS.has(favourite), "every swing is one the body authors (%s)" % favourite)
		check(str(spec.get("armor", "")) in WatcherScript.WATCHER_ARMOUR,
			"every armour set is a watcher set, got %s" % str(spec.get("armor", "")))
		check(Catalog.ITEMS.has(main_id), "the table's main is catalog gear (%s)" % main_id)
		var scale := float(spec.get("scale", 0.0))
		scales.append(scale)
		check(scale >= 0.88 and scale <= 1.30,
			"a body scale stays inside 0.88-1.30 (%f)" % scale)
		var guard := float(spec.get("guard", 1.0))
		check(guard > 0.0 and guard < 0.70, "a guard share is a share, never certain (%f)" % guard)
		if bool(spec.get("crouch", false)):
			crouched += 1
		var signature := WatcherScript.signature_of(spec)
		check(signature != previous, "no two neighbours in the table are the same body (%s)" % signature)
		previous = signature
		signatures[signature] = true
		tints[(spec.get("tint", Color.WHITE) as Color).to_html(false)] = true
		swings[favourite] = true
		var pool := WatcherScript.swing_pool_for(main_id, favourite)
		check(pool.size() >= 2, "a body has at least two swings in the pool (%s)" % str(pool))
		check(pool[0] == favourite and pool[1] == favourite,
			"the favourite is repeated, so the mix is a preference (%s)" % str(pool))
		check(pool.has("overhead"), "the plain overhead is always available for variety")
		for name in pool:
			check(SWING_CLIPS.has(str(name)), "a pool only names authored swings (%s)" % str(name))
	check(signatures.size() >= 10,
		"the table signs at least ten distinct combinations (%d)" % signatures.size())
	check(tints.size() >= 5, "the paint is more than one colour (%d hues)" % tints.size())
	check(scales.min() <= 0.92 and scales.max() >= 1.24,
		"the table spans visibly different builds (%.2f-%.2f)" % [scales.min(), scales.max()])
	check(swings.size() == 3, "the table mixes all three swings (%s)" % str(swings.keys()))
	check(crouched >= 2, "some watchers are crouch-armed (%d)" % crouched)

# --- the bodies ------------------------------------------------------------

func check_bodies() -> void:
	check(_samples.size() == SAMPLE, "the field holds %d watchers" % SAMPLE)
	var signatures := {}
	var tints := {}
	for raw in _samples:
		var watcher = raw
		check(is_instance_valid(watcher) and watcher.alive, "a watcher stands on its feet")
		check(watcher is Mob, "a watcher is the antlered warden body, not a ranger clone")
		check(str(watcher.mob_id) == "hollow_warden", "the body is the hollow warden (%s)" % watcher.mob_id)
		check(is_instance_valid(watcher._visual), "the body carries its imported presentation")
		check(str(watcher.name).begins_with("Watcher"),
			"the scene's own name survives the mob's rename (%s)" % str(watcher.name))
		check(watcher.is_in_group("camp_watchers"), "a watcher joins the camp's pack")
		check(not watcher.is_in_group("forest_mobs"), "and is not counted as a forest spawn")
		check(watcher.collision_layer == WatcherScript.WATCHER_LAYER,
			"a watcher is on the camp's hostile layer (%d)" % watcher.collision_layer)
		check(is_equal_approx(float(watcher.max_health), WatcherScript.HARDENED_HEALTH),
			"a hardened watcher carries the camp pool (%.1f)" % float(watcher.max_health))
		var main_id := str(watcher.variant.get("main", ""))
		check(WatcherScript.MAKESHIFT_TIER.has(main_id),
			"a watcher's hand is makeshift, got %s" % main_id)
		check(str(watcher.weapon_item) == main_id,
			"the catalog string matches the table (%s / %s)" % [str(watcher.weapon_item), main_id])
		check(is_equal_approx(watcher.body_scale(), float(watcher.variant.get("scale", 1.0))),
			"the body is built to its table scale")
		check(watcher.paint_tint().is_equal_approx(
			watcher.variant.get("tint", Color.WHITE) as Color),
			"the paint is the variant's own colour")
		signatures[watcher.variant_signature()] = true
		tints[watcher.paint_tint().to_html(false)] = true
	check(signatures.size() >= 10,
		"the field fields at least ten distinct watchers (%d)" % signatures.size())
	check(tints.size() >= 4, "the field wears several colours (%d)" % tints.size())
	# The same id and ordinal sign the same body twice: a corpus that spawned the
	# camp again would look the same.
	var once := WatcherScript.variant_index_for("hollow_warden", "CampWatcher7")
	var twice := WatcherScript.variant_index_for("hollow_warden", "CampWatcher7")
	check(once == twice, "the table index is a pure function of the id and name")
	check(WatcherScript.variant_index_for("hollow_warden", "CampWatcher1")
		!= WatcherScript.variant_index_for("hollow_warden", "CampWatcher2"),
		"consecutive ordinals walk different entries")


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
		check(WatcherScript.MAKESHIFT_TIER.has(main_id), "and still makeshift steel")
		check(str(watcher.variant.get("armor", "")) in ["naked", "makeshift"],
			"the pair wears a shirt or salvage, got %s" % str(watcher.variant.get("armor", "")))
		check(watcher.guard_chance() < 0.56, "the pair still rolls its guard")
		check(watcher.has_weapon_visual(), "the pair's weapon is in its hand")

# --- the hand --------------------------------------------------------------

func check_weapon() -> void:
	for raw in _samples:
		var watcher = raw
		var item := str(watcher.weapon_item)
		check(watcher.has_weapon_visual(), "the main hand really holds %s" % item)
		check(str(watcher._visual.held_item()) == item,
			"the held model is the catalog piece (%s)" % str(watcher._visual.held_item()))
		check(watcher._visual._hold != null and is_instance_valid(watcher._visual._hold),
			"the piece hangs off a hand bone, so it follows every clip")
		var hold: BoneAttachment3D = watcher._visual._hold
		check(hold.bone_name == "hand_r",
			"the hand is the warden's right hand (%s)" % hold.bone_name)
		check(watcher.gear_items().has(item), "and the corpse lists it")
		# A BoneAttachment3D rewrites its own transform from the bone every frame,
		# so the fitted grip has to live under it: this is the structure that makes
		# the rotation stick, and the check that it is not silently discarded.
		var grip: Node3D = watcher._visual._grip
		check(grip != null and is_instance_valid(grip) and grip.get_parent() == hold,
			"the fitted grip hangs under the bone attachment, not on it")
		check(not grip.basis.is_equal_approx(Basis()),
			"the grip carries a fitted rotation (%s)" % str(grip.basis.get_euler()))
	# The aim, on a body standing in its own idle stance: the piece leaves the
	# fist forward and a third of the way down, so it is clear of the robe at rest
	# and its tip is off the floor.
	var straight = null
	for raw in _samples:
		if not bool(raw.variant.get("crouch", false)):
			straight = raw
			break
	check(straight != null, "an upright watcher fields to read the grip off")
	if straight != null:
		var piece: Node3D = straight._visual._held
		var axis: Vector3 = (piece.global_basis * Vector3(0.0, 0.0, -1.0)).normalized()
		var bone: Vector3 = (straight._visual._hold.global_basis * Vector3(0.0, 0.0, -1.0)).normalized()
		check(axis.dot(bone) < 0.95,
			"the fitted grip turns the piece off the bare hand bone (%f)" % axis.dot(bone))
		check(axis.z < -0.45, "the haft leaves the fist forward (z=%.2f)" % axis.z)
		check(axis.y < -0.15, "and angled down out of the sleeve (y=%.2f)" % axis.y)
		# The model's own end is 0.68 down its local -Z; the global transform
		# carries the grip scale, so the local end is what to ask for.
		var tip: Vector3 = piece.global_transform * Vector3(0.0, 0.0, -0.68)
		check(tip.y > 0.15, "the haft's end clears the floor (%.2f)" % tip.y)
	# The bow shares the entry, not the club's aim: its limbs are its own +Y, so
	# it gets its own grip and has to read upright and turned out, not edge-on.
	var bowman = _spawn(_field, "Bowman", Vector3(0.0, 0.1, 12.0),
		WatcherScript.HARDENED_HEALTH)
	bowman.variant["crouch"] = false
	bowman.arm("bow_twig")
	await physics_frame
	await physics_frame
	check(str(bowman._visual.held_item()) == "bow_twig", "the bow is in the hand")
	var bow: Node3D = bowman._visual._held
	if bow != null:
		var up: Vector3 = bow.global_basis.y.normalized()
		var face: Vector3 = (bow.global_basis * Vector3(0.0, 0.0, -1.0)).normalized()
		check(up.y > 0.90, "the bow stands upright (up.y=%.2f)" % up.y)
		check(absf(face.z) > 0.40 and absf(face.x) < 0.85,
			"and its face is turned out, not edge-on (%s)" % str(face))
		check(bow.global_position.z < bowman.global_position.z - 0.2,
			"the bow is presented in front of the body, clear of the robe")
	bowman.queue_free()
	await physics_frame


func check_arm_round_trip() -> void:
	var watcher = _samples[5]
	check(watcher != null, "one watcher takes a handed-over piece")
	var before := str(watcher.weapon_item)
	watcher.arm("branch_heavy")
	check(str(watcher.weapon_item) == "branch_heavy", "arm writes the catalog piece")
	check(watcher.has_weapon_visual(), "the branch is in the right hand")
	check(watcher.gear_items().has("branch_heavy"), "the branch is on the corpse list")
	var taken = watcher.take_weapon_item()
	check(str(taken) == "branch_heavy", "take_weapon_item hands the piece back (%s)" % str(taken))
	check(str(watcher.weapon_item).is_empty(), "the catalog string is cleared")
	check(not watcher.has_weapon_visual(), "the hand is empty after the strip")
	check(not is_instance_valid(watcher._visual._held), "the model left the hand")
	check(not watcher.gear_items().has("branch_heavy"), "the corpse no longer lists the branch")
	watcher.arm("dagger_ironwood")
	check(watcher.has_weapon_visual(), "re-arming puts a piece back in the hand")
	check(str(watcher._visual.held_item()) == "dagger_ironwood", "and it is the shiv")
	watcher.arm(str(before))
	check(watcher.has_weapon_visual(), "and the body goes back to its own %s" % before)


func check_gear() -> void:
	var armoured = null
	var bare = null
	for raw in _samples:
		if str(raw.variant.get("armor", "")) == "naked":
			bare = raw
		elif armoured == null:
			armoured = raw
	check(armoured != null, "one watcher wears a salvage set")
	check(bare != null, "one watcher wears nothing but the creature it is")
	# The corpse's kit is the blade, the rag it wore and whatever it carried - a
	# bandage on every second body, which is where the squad's field medicine comes
	# from. Nothing else is on a watcher.
	var carried_bandages := 0
	for raw in _samples:
		if raw.gear_items().has("bandage_linen"):
			carried_bandages += 1
	if armoured != null:
		var gear: Array = armoured.gear_items()
		check(gear.has(str(armoured.weapon_item)), "the corpse lists the blade")
		var set_name := str(armoured.variant.get("armor", ""))
		var pieces := 0
		var dressings := 0
		for item_id in gear:
			check(Catalog.ITEMS.has(str(item_id)), "corpse gear is catalog gear (%s)" % str(item_id))
			if str(item_id).begins_with("armor_%s_" % set_name):
				pieces += 1
			if str(item_id) == "bandage_linen":
				dressings += 1
		check(pieces >= 1, "the corpse lists the worn %s pieces (%d)" % [set_name, pieces])
		check(dressings <= 1, "a body carries at most one dressing (%d)" % dressings)
		check(gear.size() == pieces + 1 + dressings,
			"gear is the blade, the worn pieces and the dressing (%d of %d)"
			% [gear.size(), pieces + 1 + dressings])
		check(ArmorData.SET_IDS.has(set_name), "the armour set is a catalog set (%s)" % set_name)
	if bare != null:
		var bare_gear: Array = bare.gear_items()
		check(bare_gear.has(str(bare.weapon_item)),
			"an unarmoured watcher drops its blade (%s)" % str(bare_gear))
		for item_id in bare_gear:
			if str(item_id) != str(bare.weapon_item):
				check(str(item_id) == "bandage_linen",
					"and nothing but a dressing rides beside it (%s)" % str(item_id))
	# Half the variants walk the table with a field dressing: that is where the
	# squad's medicine comes from, so some of the sample must be carrying one.
	check(carried_bandages > 0 and carried_bandages < _samples.size(),
		"the dressings are carried by some bodies and not others (%d of %d)"
		% [carried_bandages, _samples.size()])

# --- the swing -------------------------------------------------------------

## The piece in the hand has to travel. The mobset's attack clips raise the weapon
## arm and then hold it up, so the sampler lays its own arc - cock, whip, settle -
## over the clip; a strike that leaves the club where the windup put it is a statue
## with a club over its head, which is exactly what the camp used to have.
func check_swing_arc() -> void:
	var watcher = _samples[0]
	watcher.arm("club_makeshift")
	await physics_frame
	var vis = watcher._visual
	watcher.set_physics_process(false)
	vis.set_process(false)
	vis._snapshot_swing_base()
	var windup := float(watcher.profile.get("windup", 0.55))
	var strike := float(watcher.profile.get("strike", 0.20))
	vis._combat_state = "WINDUP"
	vis._combat_time = windup
	vis._apply_swing()
	await process_frame
	var cocked: Vector3 = (vis._held as Node3D).to_global(Vector3(0.0, 0.0, -1.0))
	vis._combat_state = "STRIKE"
	vis._combat_time = strike
	vis._apply_swing()
	await process_frame
	var landed: Vector3 = (vis._held as Node3D).to_global(Vector3(0.0, 0.0, -1.0))
	var travel := cocked.distance_to(landed)
	check(travel >= 1.0, "the piece travels on the swing (%.2f m)" % travel)
	check(landed.y < cocked.y - 0.5,
		"and the head comes down, not across (%.2f m -> %.2f m)" % [cocked.y, landed.y])
	check(landed.y < 1.2, "the club finishes below the shoulder (%.2f m)" % landed.y)
	watcher.set_physics_process(true)
	vis.set_process(true)
	vis._attack_playing = false
	vis._combat_state = ""


# --- the fight -------------------------------------------------------------

func check_fight() -> void:
	var crouched := 0
	var standing := 0
	var swings := {}
	for raw in _samples:
		var watcher = raw
		check(watcher.guard_chance() > 0.0 and watcher.guard_chance() < 1.0,
			"the rolled guard is a share, not a certainty (%f)" % watcher.guard_chance())
		check(watcher.guard_chance() <= 0.9, "no watcher guards every exchange")
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

	# The three dials the camp sets per wave.
	var dialled = _samples[2]
	var share := float(dialled.variant.get("guard", 0.5))
	dialled.guard_scale = 0.5
	check(is_equal_approx(dialled.guard_chance(), clampf(share * 0.5, 0.0, 0.9)),
		"guard_scale scales the variant's share (%f)" % dialled.guard_chance())
	dialled.blow_scale = 0.25
	check(is_equal_approx(dialled._strike_damage(),
		float(dialled.profile.get("damage", 0.0)) * 0.25),
		"blow_scale weights a landed swing (%f)" % dialled._strike_damage())
	dialled.swing_gap_scale = 2.0
	check(is_equal_approx(dialled._cooldown_seconds(),
		float(dialled.profile.get("cooldown", 0.0)) * 2.0),
		"swing_gap_scale stretches the beat between swings")
	dialled.guard_scale = 1.0
	dialled.blow_scale = 1.0
	dialled.swing_gap_scale = 1.0

	# The swings: a windup takes one of the body's pool, and the pool covers the
	# three authored attacks across the field.
	var club = null
	var shiv = null
	for raw in _samples:
		if str(raw.weapon_item) == "club_makeshift" and club == null:
			club = raw
		elif str(raw.weapon_item) == "dagger_ironwood" and shiv == null:
			shiv = raw
	check(club != null, "a club watcher fields")
	check(shiv != null, "a shiv watcher fields")
	if club != null:
		check(club.swing_pool().has("slash"),
			"a club has the sweep in its pool (%s)" % str(club.swing_pool()))
		check(str(club.swing_pool()[0]) == str(club.variant.get("swing")),
			"its favourite leads the pool (%s)" % str(club.swing_pool()))
		var seen := {}
		for draw in 40:
			club._choose_attack()
			seen[str(club._visual.current_attack())] = true
		check(seen.size() >= 2, "a club mixes its sweep with other swings (%s)" % str(seen.keys()))
		check(seen.has(str(club.variant.get("swing"))),
			"and the favourite keeps coming up (%s)" % str(seen.keys()))
	if shiv != null:
		check(shiv.swing_pool().has("stab"),
			"a shiv has the lunge in its pool (%s)" % str(shiv.swing_pool()))
		check(str(shiv.swing_pool()[0]) == str(shiv.variant.get("swing")),
			"and its own favourite leads (%s)" % str(shiv.swing_pool()))

	# The guard: a rolled window stops the swing, and it is never a stance.
	var braced = _samples[4]
	check(not braced.guard_up(), "a watcher does not start braced")
	braced.brace(WatcherScript.GUARD_SECONDS)
	check(braced.guard_up(), "a rolled window holds the guard up")
	check(braced._present_blocking(), "and the sampler is told to play the block loop")

	# The stagger: a real blow drives the body back and cancels the guard.
	var staggered = _samples[6]
	staggered.brace(WatcherScript.GUARD_SECONDS)
	var threshold: float = staggered._stagger_threshold()
	check(threshold >= WatcherScript.STAGGER_FLOOR, "the stagger floor is a floor (%f)" % threshold)
	check(is_equal_approx(threshold, maxf(WatcherScript.STAGGER_FLOOR,
		float(staggered.max_health) * WatcherScript.STAGGER_SHARE)),
		"and ten percent of the body is the other half of the rule")
	staggered.take_damage(2.0, 90)
	check(staggered.state != "STAGGER", "a chip is traded through, not staggered on")
	staggered.take_damage(threshold, 90)
	check(staggered.state == "STAGGER", "a real blow staggers the body (%s)" % staggered.state)
	check(not staggered.guard_up(), "and cancels the guard it was holding")
	check(staggered.alive, "the staggered body is still standing")

	# The crouch: crouch-armed bodies rest low while they wait or while hurt.
	for raw in _samples:
		var watcher = raw
		if watcher.crouch_armed():
			watcher.health = watcher.max_health - 1.0
			watcher._attack_cooldown = 0.8
			check(watcher._present_crouch(), "a crouch-armed warden crouches while it waits")
		else:
			watcher.health = watcher.max_health - 1.0
			watcher._attack_cooldown = 0.8
			check(not watcher._present_crouch(), "an upright warden never crouches")
		watcher.health = watcher.max_health

	# The mob surface: a woken, pointed watcher has a live pursuit, and a quarry
	# inside the camp's ring is never one.
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
	var guard = _samples[1]
	var caged = _samples[0]
	guard.mob_wake()
	guard.hunt(caged)
	check(not guard.hunting(), "a quarry in the safe ring is not a pursuit")

# --- the blow --------------------------------------------------------------

## The contract the camp hangs its own fight on: a woken watcher in reach swings,
## and what leaves the body is `attacked(self, amount, victim)` - already weighted
## by its own dial, for the scene to resolve through the victim's guard.
func check_attack() -> void:
	var hunter = _spawn(_field, "Striker", Vector3(0.0, 0.1, 20.0),
		WatcherScript.HARDENED_HEALTH)
	hunter.safe_center = FAR_SAFE
	hunter.blow_scale = 0.5
	await physics_frame
	var victim := CharacterBody3D.new()
	victim.name = "Quarry"
	_field.add_child(victim)
	# Straight in front of the watcher, inside the warden's reach.
	victim.global_position = hunter.global_position + Vector3(0.0, 0.0, -2.0)
	var blows: Array = []
	hunter.attacked.connect(func(attacker, amount, target) -> void:
		blows.append({"self": attacker == hunter, "amount": amount, "target": target}))
	hunter.mob_wake()
	hunter.hunt(victim)
	for frame in 180:
		await physics_frame
		if not blows.is_empty():
			break
	check(not blows.is_empty(), "a warden in reach lands its blow")
	if not blows.is_empty():
		var blow: Dictionary = blows[0]
		check(bool(blow.self), "the blow names the watcher as the attacker")
		check(blow.target == victim, "and the body it was fighting as the victim")
		check(is_equal_approx(float(blow.amount),
			float(hunter.profile.get("damage", 0.0)) * 0.5),
			"the blow carries the profile damage through blow_scale (%f)" % float(blow.amount))
	hunter.queue_free()
	victim.queue_free()
	await physics_frame

# --- the sampler -----------------------------------------------------------

func check_sampler() -> void:
	# The table's promise, independent of the asset: three swings with their own
	# durations and impact frames, a guard loop, a stagger and a crouch.
	var table: Dictionary = Visual.FOREST_DATA["hollow_warden"]
	var attacks: Dictionary = table.get("attacks", {})
	check(attacks.size() == SWING_CLIPS.size(),
		"the warden authors three swings (%d)" % attacks.size())
	for name in SWING_CLIPS:
		var pinned: Array = SWING_CLIPS[name]
		var entry: Dictionary = attacks.get(name, {})
		check(str(entry.get("clip", "")) == str(pinned[0]),
			"%s plays %s" % [name, str(pinned[0])])
		check(absf(float(entry.get("duration", 0.0)) - float(pinned[1])) < 0.001,
			"%s runs %0.2f s (%s)" % [name, float(pinned[1]), str(entry.get("duration"))])
		check(absf(float(entry.get("impact", -1.0)) - float(pinned[2])) < 0.001,
			"%s lands on its own impact frame (%s)" % [name, str(entry.get("impact"))])
	check(str(table.get("block", "")) == BLOCK_CLIP, "the guard loop is %s" % BLOCK_CLIP)
	check(str(table.get("stagger", "")) == STAGGER_CLIP, "the recoil is %s" % STAGGER_CLIP)
	check(str(table.get("crouch", "")) == CROUCH_CLIP, "the stance is %s" % CROUCH_CLIP)

	var claims: Array = _samples[0].claimed_clips()
	for name in SWING_CLIPS:
		check(claims.has(str((SWING_CLIPS[name] as Array)[0])),
			"a watcher claims the %s clip (%s)" % [name, str((SWING_CLIPS[name] as Array)[0])])
	for clip in [BLOCK_CLIP, STAGGER_CLIP, CROUCH_CLIP]:
		check(claims.has(clip), "a watcher claims %s" % clip)
	for clip in claims:
		check(_samples[0].body_plays(str(clip)),
			"the body really carries the clip it claims (%s)" % str(clip))

	# What the imported body actually carries.
	var probe = Visual.new()
	probe.mob_id = "hollow_warden"
	probe.profile = Mob.FOREST_PROFILES["hollow_warden"]
	root.add_child(probe)
	await process_frame
	check(probe.attack_names() == ["overhead", "slash", "stab"],
		"the sampler reports the three swings (%s)" % str(probe.attack_names()))
	check(probe.attack_clip("slash") == "Warden_Attack_Slash", "the sweep is the slash clip")
	check(probe.attack_clip("stab") == "Warden_Attack_Stab", "the lunge is the stab clip")
	check(probe.block_clip() == BLOCK_CLIP, "the sampler reports the block loop")
	check(probe.stagger_clip() == STAGGER_CLIP, "the sampler reports the stagger")
	check(probe.crouch_clip() == CROUCH_CLIP, "the sampler reports the crouch")
	var missing: Array[String] = []
	for clip in NEW_CLIPS:
		if not probe.has_clip(str(clip)):
			missing.append(str(clip))
	check(missing.is_empty(), "the imported warden carries every authored clip (missing %s)" % str(missing))

	# The playback itself: each state selects its own authored clip.
	probe.set_attack("slash")
	probe.set_combat("WINDUP", 0.0)
	check(probe.get_clip_name() == "Warden_Attack_Slash",
		"a slash windup plays the sweep (%s)" % probe.get_clip_name())
	probe.set_attack("stab")
	probe.set_combat("CIRCLE", 0.0)
	probe.set_combat("WINDUP", 0.0)
	check(probe.get_clip_name() == "Warden_Attack_Stab",
		"a stab windup plays the lunge (%s)" % probe.get_clip_name())
	probe.set_attack("overhead")
	probe.set_combat("CIRCLE", 0.0)
	probe.set_combat("WINDUP", 0.0)
	check(probe.get_clip_name() == "Warden_Attack",
		"an overhead windup plays the base attack (%s)" % probe.get_clip_name())
	probe.set_attack("")
	probe.set_combat("CIRCLE", 0.0)
	check(probe.get_clip_name() == "Warden_Idle", "with no named swing the body idles")
	probe.set_poise(true, false)
	check(probe.get_clip_name() == BLOCK_CLIP,
		"a held guard plays the block loop (%s)" % probe.get_clip_name())
	probe.set_poise(false, true)
	probe.set_motion(Vector3.ZERO, true)
	check(probe.get_clip_name() == CROUCH_CLIP,
		"a crouched rest plays the crouch loop (%s)" % probe.get_clip_name())
	probe.set_motion(Vector3(1.2, 0.0, 0.0), true)
	await process_frame
	check(probe.get_clip_name() == "Warden_Walk",
		"a crouched body still walks on its feet (%s)" % probe.get_clip_name())
	probe.set_poise(false, false)
	probe.set_motion(Vector3.ZERO, true)
	await process_frame
	check(probe.get_clip_name() == "Warden_Idle", "dropping the stance returns to idle")
	probe.set_combat("STAGGER", 0.0)
	check(probe.get_clip_name() == STAGGER_CLIP,
		"a stagger plays the recoil (%s)" % probe.get_clip_name())
	# The loop semantics are the controller's, as for the other five clips.
	check(probe._player.get_animation(BLOCK_CLIP).loop_mode == Animation.LOOP_LINEAR,
		"the guard loop loops")
	check(probe._player.get_animation(CROUCH_CLIP).loop_mode == Animation.LOOP_LINEAR,
		"the crouch loop loops")
	check(probe._player.get_animation(STAGGER_CLIP).loop_mode == Animation.LOOP_NONE,
		"the stagger is a one-shot")
	for name in SWING_CLIPS:
		var clip := str((SWING_CLIPS[name] as Array)[0])
		check(probe._player.get_animation(clip).loop_mode == Animation.LOOP_NONE,
			"%s is a one-shot" % clip)
	probe.queue_free()
	await process_frame

# --- death -----------------------------------------------------------------

func check_death() -> void:
	var watcher = _samples[8]
	_defeats = 0
	watcher.defeated.connect(_on_defeated)
	watcher.take_damage(4000.0, 90)
	check(_defeats == 1, "a killed watcher reports its defeat exactly once (%d)" % _defeats)
	check(not watcher.alive, "the body is dead")
	check(not watcher.hunting(), "a corpse is not hunting")
	check(watcher._visual.is_dead(), "the corpse holds its own death")
	watcher.take_damage(4000.0, 90)
	check(_defeats == 1, "a blow on the corpse is not a second kill (%d)" % _defeats)
	check(watcher.gear_items().size() >= 1, "the corpse still lists its kit")
