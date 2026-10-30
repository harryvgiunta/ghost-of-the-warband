extends SceneTree
## Watcher regression: the camp's watchers are the wood's three creatures on the
## warband's own rig.
##
## Nothing here reads a library in isolation. Watchers are instantiated exactly
## the way the camp does it (name, species and health pool set before the tree,
## position after), and every claim is asked of the live body:
##
##   * the variant table fields three species with at least ten distinct bodies,
##     and a body's species is what the scene asked for;
##   * the presentation is the ranger's rig wearing a creature skin - the skin is
##     skinned to that skeleton, the ranger's own body is off the screen, and the
##     body stands at the creature's height;
##   * the piece in the hand is a catalog model held by the rig's own weapon slot,
##     and a swing is the rig's authored cut, retimed so the blade crosses the
##     target on the frame the mob's damage resolves;
##   * `arm`/`take_weapon_item` round-trip, the guard and the crouch are the rig's
##     authored stances, a real blow breaks a swing, and a corpse is the shared
##     ragdoll.
##
## The three skins are also compared against their exported metadata, so a
## sampler that promises a height or a fit scale the asset does not carry fails
## here rather than at spawn.

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const Presenter = preload("res://scripts/warband/watcher_visual.gd")
const Mob = preload("res://scripts/forest_mob.gd")
const Catalog = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const Scaler = preload("res://scripts/warband/damage_scaler.gd")
const BloodSurface = preload("res://scripts/blood_surface.gd")
const BloodField = preload("res://scripts/blood_field.gd")

const SPECIES := ["hollow_warden", "ossuary_stalker", "gallowsroot"]
const PER_SPECIES := 4
const SPAWN_STEP := 4.5
## Off the ring, for the hunting checks: these bodies must not be measured
## against the camp's yard.
const FAR_SAFE := Vector3(-900.0, 0.0, -900.0)
## The three swings' rig clips, pinned: the presenter promises these names and the
## ranger's own AnimationPlayer has to carry them.
const SWING_CLIPS := {
	"overhead": "Sword_Overhead_OneHand",
	"slash": "Sword_Overhead",
	"stab": "Dagger_Stab",
}
const BLOCK_CLIP := "Sword_Block_Loop_OneHand"
const CROUCH_CLIP := "Crouch_Idle_Loop"
const IDLE_CLIP := "Sword_Idle_OneHand"

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
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160.0, 1.0, 160.0)
	floor_shape.shape = box
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	_field = Node3D.new()
	_field.name = "WatcherField"
	root.add_child(_field)
	var index := 0
	for species in SPECIES:
		for slot in PER_SPECIES:
			_samples.append(_spawn(_field, "Watcher%d" % index, species,
				Vector3(SPAWN_STEP * float(index), 0.1, 0.0), WatcherScript.HARDENED_HEALTH))
			index += 1
	# The lesson's pair: two thinned bodies, still two species.
	_pairs.append(_spawn(_field, "Pair%d" % index, "hollow_warden",
		Vector3(SPAWN_STEP * float(index), 0.1, 0.0), WatcherScript.PAIR_HEALTH))
	_pairs.append(_spawn(_field, "Pair%d" % (index + 1), "ossuary_stalker",
		Vector3(SPAWN_STEP * float(index + 1), 0.1, 0.0), WatcherScript.PAIR_HEALTH))
	await physics_frame
	await physics_frame

	check_assets()
	check_table()
	check_bodies()
	await check_blood()
	check_pairs()
	await check_weapon()
	check_arm_round_trip()
	check_gear()
	await check_swing()
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
func _spawn(parent: Node3D, label: String, species: String, at: Vector3, health: float):
	var watcher = WatcherScript.new()
	watcher.name = label
	watcher.mob_id = species
	watcher.health_pool = health
	watcher.position = at
	parent.add_child(watcher)
	watcher.global_position = at
	return watcher


# --- the skins -------------------------------------------------------------

## Every skin is compared against the metadata the fit tool wrote: the fit scale
## the presenter applies and the height it produces are the asset's own numbers.
func check_assets() -> void:
	for species in SPECIES:
		var spec: Dictionary = Presenter.SPECIES.get(species, {})
		check(not spec.is_empty(), "the presenter knows the %s" % species)
		var skin := str(spec.get("skin", ""))
		var mesh_path := str(spec.get("materials", ""))
		check(ResourceLoader.exists(skin), "%s's skin is imported (%s)" % [species, skin])
		check(ResourceLoader.exists(mesh_path), "%s's materials exist (%s)" % [species, mesh_path])
		var meta_path := skin.get_basename() + ".json"
		check(FileAccess.file_exists(meta_path), "%s's skin has its metadata" % species)
		if not FileAccess.file_exists(meta_path):
			continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		check(is_equal_approx(float(meta.get("fit_scale", 0.0)), float(spec.get("fit", -1.0))),
			"%s's fit scale is the measured one (%s / %s)"
			% [species, str(spec.get("fit")), str(meta.get("fit_scale"))])
		check(int(meta.get("bone_count", 0)) == 65,
			"%s's skin is bound to the ranger's 65-bone rig (%d)" % [species, int(meta.get("bone_count", 0))])
		check(int(meta.get("embedded_images", -1)) == 0,
			"%s's skin ships no images; its materials come from the creature" % species)
		check(str(meta.get("node", "")).begins_with("Watcher_"),
			"%s's skin carries its watcher node (%s)" % [species, str(meta.get("node", ""))])

		# The runtime scene itself: one skinned mesh wearing the creature's own
		# material slots, on a real Skeleton3D.
		var packed := load(skin) as PackedScene
		check(packed != null, "%s's skin loads as a scene" % species)
		if packed == null:
			continue
		var instance := packed.instantiate()
		var skeleton := instance.find_children("*", "Skeleton3D", true, false)
		check(skeleton.size() >= 1, "%s's skin carries a skeleton" % species)
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() == 1, "%s's skin is one joined mesh (%d)" % [species, meshes.size()])
		if not meshes.is_empty():
			var mesh := meshes[0] as MeshInstance3D
			check(mesh.skin != null, "%s's skin is skinned" % species)
			check(mesh.mesh.get_surface_count() >= 4,
				"%s keeps its creature surfaces (%d)" % [species, mesh.mesh.get_surface_count()])
			for node_name in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(node_name)
				check(material != null and str(material.resource_name).begins_with("Forest_"),
					"%s's surface %d is a creature material (%s)"
					% [species, node_name, str(material.resource_name) if material else "none"])
		instance.free()


# --- the table -------------------------------------------------------------

func check_table() -> void:
	var table: Array = WatcherScript.VARIANTS
	check(table.size() >= 10, "the variant table fields at least ten bodies (%d)" % table.size())
	var signatures := {}
	var tints := {}
	var scales: Array[float] = []
	var swings := {}
	var species_seen := {}
	var crouched := 0
	var previous := ""
	for entry in table:
		var spec: Dictionary = entry
		var main_id := str(spec.get("main", ""))
		var favourite := str(spec.get("swing", ""))
		var species := str(spec.get("species", ""))
		check(WatcherScript.SPECIES_IDS.has(species),
			"every table row names a watcher species, got '%s'" % species)
		species_seen[species] = int(species_seen.get(species, 0)) + 1
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
	# Three species, and enough of each that a squad is mixed rather than one
	# creature and a token.
	for species in SPECIES:
		check(int(species_seen.get(species, 0)) >= 3,
			"%s fields at least three variants (%d)" % [species, int(species_seen.get(species, 0))])
		var rows := WatcherScript.table_for(species)
		check(not rows.is_empty(), "%s has its own rows" % species)
		for row in rows:
			check(str((row as Dictionary).get("species", "")) == species,
				"%s's table holds only its own species" % species)


# --- the bodies ------------------------------------------------------------

func check_bodies() -> void:
	check(_samples.size() == SPECIES.size() * PER_SPECIES,
		"the field holds %d watchers" % (SPECIES.size() * PER_SPECIES))
	var signatures := {}
	var tints := {}
	for raw in _samples:
		var watcher = raw
		check(is_instance_valid(watcher) and watcher.alive, "a watcher stands on its feet")
		check(watcher is Mob, "a watcher is a wilderness mob, not a ranger clone")
		check(WatcherScript.SPECIES_IDS.has(str(watcher.species_id())),
			"the body is one of the wood's creatures (%s)" % str(watcher.species_id()))
		check(str(watcher.species_display()) == str(watcher.profile.get("display", "")),
			"the species names its own profile (%s)" % str(watcher.species_display()))
		check(str(watcher.name).begins_with("Watcher"),
			"the scene's own name survives the mob's rename (%s)" % str(watcher.name))
		check(watcher.is_in_group("camp_watchers"), "a watcher joins the camp's pack")
		check(not watcher.is_in_group("forest_mobs"), "and is not counted as a forest spawn")
		check(watcher.collision_layer == WatcherScript.WATCHER_LAYER,
			"a watcher is on the camp's hostile layer (%d)" % watcher.collision_layer)
		check(is_equal_approx(float(watcher.max_health), WatcherScript.HARDENED_HEALTH),
			"a hardened watcher carries the camp pool (%.1f)" % float(watcher.max_health))

		# The rig: a human body wearing the creature's own skin.
		var vis = watcher._visual
		check(is_instance_valid(vis) and vis.get_script() == Presenter,
			"the body's presentation is the humanoid watcher presenter")
		var rig = vis.rig if is_instance_valid(vis) else null
		check(is_instance_valid(rig), "the watcher wears the warband's rig")
		if not is_instance_valid(rig):
			continue
		check(rig.skin_meshes().size() == 1, "exactly one creature skin is worn (%d)"
			% rig.skin_meshes().size())
		var skin: MeshInstance3D = rig.skin_meshes()[0] if rig.skin_meshes().size() == 1 else null
		check(skin != null and skin.get_node_or_null(skin.skeleton) == rig.skeleton,
			"the skin is bound to the live ranger skeleton")
		check(skin != null and skin.is_visible_in_tree(), "and it is drawn")
		# The ranger's own body is not drawn under it: a human face in a hood is
		# the failure this whole cutover exists to avoid.
		for mesh_name in ["Male_Ranger_Body", "Male_Ranger_Head_Hood",
				"Ranger_Head_SuperHero_Male", "Male_Ranger_Feet_Boots"]:
			var shipped := rig._model.find_child(mesh_name, true, false) as MeshInstance3D
			check(shipped != null and not shipped.is_visible_in_tree(),
				"the ranger's own %s is off the screen" % mesh_name)
		# Height: the species' fit scale times the variant's silhouette, and the
		# body is as tall as the creature it is.
		var fit := float((Presenter.SPECIES[watcher.species_id()] as Dictionary)["fit"])
		var expected := fit * float(watcher.variant.get("scale", 1.0))
		check(absf(float(watcher.body_scale()) - expected) < 0.02,
			"the body is built to its species' height (%.3f / %.3f)" % [watcher.body_scale(), expected])
		check(rig.body_scale() > 0.9 and rig.body_scale() < 1.8,
			"and the rig carries it (%.3f)" % rig.body_scale())
		var head: Vector3 = watcher.head_hitbox_center() - watcher.global_position
		var rest := 1.869 * float(watcher.body_scale())
		check(head.y / maxf(rest, 0.01) > 0.78,
			"the head zone rides the rig's own head (%.2f of %.2f m)" % [head.y, rest])
		check(watcher.head_hit_profile().x > 0.3, "with a head's radius (%.2f)"
			% watcher.head_hit_profile().x)
		# The pitch: the variant's paint is on the skin's own copies.
		check(watcher.paint_tint().is_equal_approx(
			watcher.variant.get("tint", Color.WHITE) as Color),
			"the paint is the variant's own colour")
		signatures[watcher.variant_signature()] = true
		tints[watcher.paint_tint().to_html(false)] = true
	check(signatures.size() >= 4, "the field fields distinct bodies (%d)" % signatures.size())
	check(tints.size() >= 2, "the field wears several colours (%d)" % tints.size())
	# The same id and ordinal sign the same body twice: a corpus that spawned the
	# camp again would look the same.
	var once := WatcherScript.variant_index_for("hollow_warden", "CampWatcher7")
	var twice := WatcherScript.variant_index_for("hollow_warden", "CampWatcher7")
	check(once == twice, "the table index is a pure function of the id and name")
	check(WatcherScript.variant_index_for("hollow_warden", "CampWatcher1")
		!= WatcherScript.variant_index_for("hollow_warden", "CampWatcher2"),
		"consecutive ordinals walk different entries")
	# A species' walk never leaves its own creature.
	for species in SPECIES:
		var rows := WatcherScript.table_for(species)
		var slot := WatcherScript.variant_index_for(species, "CampWatcher3")
		check(slot >= 0 and slot < rows.size(),
			"%s's index is inside its own table (%d)" % [species, slot])
		check(str((rows[slot] as Dictionary).get("species", "")) == species,
			"and lands on a %s" % species)


## Body blood must ride the skeleton the skin is actually rendered on. The
## fitted watcher skins keep their source armature in the scene, and the blood
## field used to measure that dead rest pose: the stains stayed behind in the
## air while the body walked and swung. One body per species is measured, and
## the stain's parent chain is the check, because that is what makes it move.
func check_blood() -> void:
	var seen := {}
	for raw in _samples:
		var watcher = raw
		var species := str(watcher.species_id())
		if seen.has(species):
			continue
		seen[species] = true
		var vis = watcher._visual
		var rig = vis.rig
		var skin_root: Node3D = vis.blood_anchor()
		var body: Dictionary = BloodSurface.body_for(skin_root)
		check(body.get("skeleton") == rig.skeleton,
			"%s's blood measures the live skeleton, not the skin's rest armature" % species)
		var field = BloodField.new()
		field.set_process(false)
		root.add_child(field)
		field.wound(skin_root, watcher.get_aim_position(), 20.0, false, false, 1.0)
		await process_frame
		var soak: MeshInstance3D = null
		for child in watcher.find_children("*", "MeshInstance3D", true, false):
			if child.has_meta("blood_stain"):
				soak = child as MeshInstance3D
				break
		check(soak != null, "%s's wound leaves body blood" % species)
		if soak != null:
			check(rig.skeleton.is_ancestor_of(soak),
				"%s's wound rides the animated skeleton" % species)
		field.clear_all()
		field.queue_free()
		await process_frame


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
		check(str(watcher.species_id()) in SPECIES, "and it is a creature like the rest")


# --- the hand --------------------------------------------------------------

## The piece is the rig's own weapon slot, not a model hung off a bone: the
## warband's club is the club a watcher swings, and its mode says so.
func check_weapon() -> void:
	for raw in _samples:
		var watcher = raw
		var item := str(watcher.weapon_item)
		var rig = watcher._visual.rig
		var kind := str((Catalog.ITEMS.get(item, {}) as Dictionary).get("kind", ""))
		check(watcher.has_weapon_visual(), "the main hand really holds %s" % item)
		check(str(watcher._visual.held_item()) == item,
			"the rig reports the catalog piece (%s)" % str(watcher._visual.held_item()))
		check(watcher.gear_items().has(item), "and the corpse lists it")
		match kind:
			"sword":
				check(rig.weapon == "sword", "a %s is carried as the rig's sword (%s)" % [item, rig.weapon])
				check(rig.sword_index == int(Catalog.ITEMS[item].index),
					"the blade is the catalog index (%d)" % rig.sword_index)
			"dagger":
				check(rig.weapon == "dagger", "a %s is carried as the rig's dagger (%s)" % [item, rig.weapon])
				check(rig.dagger_index == int(Catalog.ITEMS[item].index),
					"the shiv is the catalog index (%d)" % rig.dagger_index)
			"bow":
				check(rig.weapon == "bow", "a %s is carried as the rig's bow (%s)" % [item, rig.weapon])
		check(not rig.shield_equipped, "a watcher never carries a shield")
		check(rig.active_focus == null or not rig.active_focus.visible,
			"and never a focus")
	# A bow on the archer body: the rig's own bow, drawn and loosed, instead of a
	# prop hung off a hand bone.
	var bowman = _spawn(_field, "Bowman", "hollow_warden", Vector3(0.0, 0.1, 26.0),
		WatcherScript.HARDENED_HEALTH)
	bowman.arm("bow_twig")
	await physics_frame
	await physics_frame
	check(str(bowman._visual.held_item()) == "bow_twig", "the twig bow is in the hand")
	check(bowman._visual.rig.weapon == "bow", "and the rig is in its bow mode")
	check(bowman._visual.rig.bow_index == int(Catalog.ITEMS["bow_twig"].index),
		"with the catalog bow's own index (%d)" % bowman._visual.rig.bow_index)
	var origin: Vector3 = bowman._visual.bow_origin()
	check(origin.distance_to(bowman.global_position) > 0.3,
		"the shaft leaves from the bow, not the body's centre (%.2f m)"
		% origin.distance_to(bowman.global_position))
	bowman.queue_free()
	await physics_frame


func check_arm_round_trip() -> void:
	var watcher = _samples[1]
	check(watcher != null, "one watcher takes a handed-over piece")
	var before := str(watcher.weapon_item)
	watcher.arm("branch_heavy")
	check(str(watcher.weapon_item) == "branch_heavy", "arm writes the catalog piece")
	check(watcher.has_weapon_visual(), "the branch is in the right hand")
	check(watcher._visual.rig.weapon == "sword", "and the rig swings it as a blade")
	var taken = watcher.take_weapon_item()
	check(str(taken) == "branch_heavy", "take_weapon_item hands the piece back (%s)" % str(taken))
	check(str(watcher.weapon_item).is_empty(), "the catalog string is cleared")
	check(not watcher.has_weapon_visual(), "the hand is empty after the strip")
	check(watcher._visual.rig.weapon == "none", "and the rig is empty-handed (%s)"
		% watcher._visual.rig.weapon)
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
	check(armoured != null, "one watcher walks with salvage on its corpse")
	check(bare != null, "one watcher carries nothing but the creature it is")
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
		var reagents := 0
		for item_id in gear:
			check(Catalog.ITEMS.has(str(item_id)), "corpse gear is catalog gear (%s)" % str(item_id))
			if str(item_id).begins_with("armor_%s_" % set_name):
				pieces += 1
			if str(item_id) == "bandage_linen":
				dressings += 1
			if str(item_id) == "ichor_vial":
				reagents += 1
		check(pieces >= 1, "the corpse lists the worn %s pieces (%d)" % [set_name, pieces])
		check(dressings <= 1, "a body carries at most one dressing (%d)" % dressings)
		check(reagents <= 1, "a body carries at most one vial of ichor (%d)" % reagents)
		check(gear.size() == pieces + 1 + dressings + reagents,
			"gear is the blade, the worn pieces, the dressing and the warden's vial (%d of %d)"
			% [gear.size(), pieces + 1 + dressings + reagents])
		check(ArmorData.SET_IDS.has(set_name), "the armour set is a catalog set (%s)" % set_name)
	if bare != null:
		var bare_gear: Array = bare.gear_items()
		check(bare_gear.has(str(bare.weapon_item)),
			"an unarmoured watcher drops its blade (%s)" % str(bare_gear))
		for item_id in bare_gear:
			if str(item_id) != str(bare.weapon_item):
				check(str(item_id) in ["bandage_linen", "ichor_vial"],
					"and nothing but a dressing or a vial rides beside it (%s)" % str(item_id))
	# Every watcher walks the wood with a field dressing tied at its belt: that is
	# where the squad's medicine comes from, and a corpse lists exactly one.
	check(carried_bandages == _samples.size(),
		"every body carries one dressing (%d of %d)" % [carried_bandages, _samples.size()])
	for raw in _samples + _pairs:
		var dropped_set := str(raw.variant.get("armor", "naked"))
		check(dropped_set in WatcherScript.WATCHER_ARMOUR,
			"a scenario-1 corpse carries an allowed set (%s)" % dropped_set)
		for item_id in raw.gear_items():
			if str(item_id).begins_with("armor_"):
				check(str(item_id).begins_with("armor_makeshift_"),
					"scenario-1 armour is the salvage tier (%s)" % str(item_id))


# --- the swing -------------------------------------------------------------

## The contract that makes a fight read: a windup opens one of the rig's own
## authored cuts, the cut is retimed onto the mob's telegraph, and on the frame
## the mob's damage resolves the blade is crossing the target.
func check_swing() -> void:
	var watcher = _samples[0]
	watcher.set_physics_process(false)
	var vis = watcher._visual
	var rig = vis.rig
	rig.set_physics_process(false)
	vis.set_held_weapon("club_makeshift")
	vis.set_attack("overhead")
	var windup := float(watcher.profile.get("windup", 0.55))
	var strike := float(watcher.profile.get("strike", 0.20))
	var impact_time := windup + strike * Presenter.STRIKE_DAMAGE_SHARE
	vis.set_combat("WINDUP", 0.0)
	check(rig.is_melee(), "a windup opens the rig's swing")
	if not rig.is_melee():
		watcher.set_physics_process(true)
		return
	var swing := float(rig.melee_seconds("right"))
	var expected := float(vis._swing_seconds())
	check(absf(swing - expected) < 0.001,
		"the swing is the mob's telegraph long (%.3f / %.3f)" % [swing, expected])
	check(rig.melee_variant("right") == "overhead", "the plain swing is the overhead (%s)"
		% rig.melee_variant("right"))
	# The blade travels, and it comes down rather than across.
	var cocked: Vector3 = rig.get_blade_tip("right")
	var cocked_at := 0.0
	var elapsed := 0.0
	var peak := 0.0
	var lowest := 999.0
	while rig.is_melee() and elapsed < swing + 0.5:
		rig.advance_animation(1.0 / 120.0)
		elapsed += 1.0 / 120.0
		var tip: Vector3 = rig.get_blade_tip("right")
		peak = maxf(peak, tip.distance_to(cocked))
		lowest = minf(lowest, tip.y)
		if absf(elapsed - impact_time) <= 1.0 / 120.0:
			cocked_at = rig.melee_cut_progress("right")
	check(peak >= 0.9, "the piece travels on the swing (%.2f m)" % peak)
	check(lowest < cocked.y - 0.25,
		"the head comes down, not across (%.2f -> %.2f)" % [cocked.y, lowest])
	# The impact lands where the damage does: the strike window opens on the
	# mob's own frame, within one sample.
	check(absf(cocked_at - Presenter.BLADE_IMPACT_SHARE) < 0.08,
		"the strike window opens on the damage frame (%.2f vs %.2f)"
		% [cocked_at, Presenter.BLADE_IMPACT_SHARE])
	check(not rig.is_melee(), "and the swing finishes on its own clock")
	# The other two swings are the rig's other cuts.
	vis.set_attack("slash")
	vis.set_combat("CIRCLE", 0.0)
	vis.set_combat("WINDUP", 0.0)
	check(rig.is_melee() and rig.melee_variant("right") == "diagonal_right",
		"a slash is the rig's diagonal cut (%s)" % rig.melee_variant("right"))
	vis.set_attack("stab")
	rig.abort_melee("right")
	vis.set_combat("CIRCLE", 0.0)
	vis.set_combat("WINDUP", 0.0)
	check(rig.is_melee() and rig.melee_variant("right") == "stab",
		"a stab is the rig's lunge (%s)" % rig.melee_variant("right"))
	# A real blow breaks it: the flinch cancels the swing instead of finishing it.
	vis.set_combat("STAGGER", 0.0)
	check(not rig.is_melee(), "a stagger cancels the swing")
	check(rig._hit_react > 0.0, "and the body takes the recoil")
	watcher.set_physics_process(true)
	rig.set_physics_process(true)


# --- the fight -------------------------------------------------------------

func check_fight() -> void:
	var crouched := 0
	var standing := 0
	for raw in _samples:
		var watcher = raw
		check(watcher.guard_chance() > 0.0 and watcher.guard_chance() < 1.0,
			"the rolled guard is a share, not a certainty (%f)" % watcher.guard_chance())
		check(watcher.guard_chance() <= 0.9, "no watcher guards every exchange")
		if watcher.crouch_armed():
			crouched += 1
		else:
			standing += 1
		check(not watcher.hunting(), "an unpointed watcher is not hunting")
	check(crouched >= 1, "crouch-armed watchers exist (%d)" % crouched)
	check(standing >= 1, "and upright ones too (%d)" % standing)

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

	# The guard and the crouch are the rig's authored stances.
	var holder = _samples[3]
	check(not holder.guard_up(), "a watcher does not start braced")
	holder.brace(WatcherScript.GUARD_SECONDS)
	check(holder.guard_up(), "a rolled window holds the guard up")
	check(holder._present_blocking(), "and the sampler is told to play the block loop")

	# The stagger: a real blow drives the body back and cancels the guard.
	var staggered = _samples[4]
	staggered.brace(WatcherScript.GUARD_SECONDS)
	var threshold: float = staggered._stagger_threshold()
	check(threshold >= WatcherScript.STAGGER_FLOOR, "the stagger floor is a floor (%f)" % threshold)
	check(is_equal_approx(threshold, maxf(WatcherScript.STAGGER_FLOOR,
		float(staggered.max_health) * WatcherScript.STAGGER_SHARE)),
		"and ten percent of the body is the other half of the rule")
	staggered.take_damage(2.0, 90)
	check(staggered.state != "STAGGER", "a chip is traded through, not staggered on")
	staggered.take_damage(threshold * 2.0, 90)
	check(staggered.state == "STAGGER", "a real blow staggers the body (%s)" % staggered.state)
	check(not staggered.guard_up(), "and cancels the guard it was holding")
	check(staggered.alive, "the staggered body is still standing")
	# Back on its feet for the stance checks below: the stagger owns the pose.
	staggered.state = "CIRCLE"
	staggered._state_time = 0.0
	staggered.health = staggered.max_health

	for raw in _samples:
		var watcher = raw
		if watcher.crouch_armed():
			watcher.health = watcher.max_health - 1.0
			watcher._attack_cooldown = 0.8
			check(watcher._present_crouch(), "a crouch-armed watcher crouches while it waits")
		else:
			watcher.health = watcher.max_health - 1.0
			watcher._attack_cooldown = 0.8
			check(not watcher._present_crouch(), "an upright watcher never crouches")
		watcher.health = watcher.max_health

	# The mob surface: a woken, pointed watcher has a live pursuit, and a quarry
	# inside the camp's ring is never one.
	var hunter = _samples[_samples.size() - 1]
	var quarry = _samples[_samples.size() - 2]
	check(not hunter.hunting(), "the hunter starts idle")
	hunter.safe_center = FAR_SAFE
	hunter.mob_wake()
	hunter.hunt(quarry)
	check(hunter.player == quarry, "hunt commits the body to its quarry")
	check(hunter.hunting(), "a woken watcher with a quarry in sight is hunting")
	check(hunter.get_aim_position().distance_to(hunter.global_position) > 0.1,
		"the body answers where it is aimed")
	var guard = _samples[0]
	var caged = _samples[1]
	guard.mob_wake()
	guard.hunt(caged)
	check(not guard.hunting(), "a quarry in the safe ring is not a pursuit")


# --- the blow --------------------------------------------------------------

## The contract the camp hangs its own fight on: a woken watcher in reach swings,
## and what leaves the body is `attacked(self, amount, victim)` - already weighted
## by its own dial, for the scene to resolve through the victim's guard.
func check_attack() -> void:
	var hunter = _spawn(_field, "Striker", "gallowsroot", Vector3(0.0, 0.1, 34.0),
		WatcherScript.HARDENED_HEALTH)
	hunter.safe_center = FAR_SAFE
	hunter.blow_scale = 0.5
	await physics_frame
	var victim := CharacterBody3D.new()
	victim.name = "Quarry"
	_field.add_child(victim)
	# Straight in front of the watcher, inside its reach.
	victim.global_position = hunter.global_position + Vector3(0.0, 0.0, -2.2)
	var blows: Array = []
	var at_blow: Array = []
	hunter.attacked.connect(func(attacker, amount, target) -> void:
		blows.append({"self": attacker == hunter, "amount": amount, "target": target})
		at_blow.append(bool(hunter._visual.rig.is_melee())))
	hunter.mob_wake()
	hunter.hunt(victim)
	for frame in 180:
		await physics_frame
		if not blows.is_empty():
			break
	check(not blows.is_empty(), "a watcher in reach lands its blow")
	if not blows.is_empty():
		var blow: Dictionary = blows[0]
		check(bool(blow.self), "the blow names the watcher as the attacker")
		check(blow.target == victim, "and the body it was fighting as the victim")
		check(is_equal_approx(float(blow.amount),
			float(hunter.profile.get("damage", 0.0)) * 0.5),
			"the blow carries the profile damage through blow_scale (%f)" % float(blow.amount))
		check(not at_blow.is_empty() and bool(at_blow[0]),
			"the rig was mid-cut when the blow landed")
	hunter.queue_free()
	victim.queue_free()
	await physics_frame


# --- the sampler -----------------------------------------------------------

func check_sampler() -> void:
	for raw in _samples:
		var vis = raw._visual
		check(vis.attack_names() == ["overhead", "slash", "stab"],
			"the body offers the three swings (%s)" % str(vis.attack_names()))
		for name in SWING_CLIPS:
			check(vis.has_clip(str(vis.attack_clip(name))),
				"%s names a clip the rig carries (%s)" % [name, str(vis.attack_clip(name))])
		check(str(vis.block_clip()) == BLOCK_CLIP, "the guard loop is %s" % BLOCK_CLIP)
		check(str(vis.crouch_clip()) == CROUCH_CLIP, "the stance is %s" % CROUCH_CLIP)
		check(str(vis.stagger_clip()).is_empty(), "the recoil is a pose, not a clip")
		var claims: Array = raw.claimed_clips()
		for clip in claims:
			check(raw.body_plays(str(clip)),
				"the body really carries the clip it claims (%s)" % str(clip))
		check(vis.has_clip(IDLE_CLIP), "and the rig's own idle (%s)" % IDLE_CLIP)

	# The catalog piece decides which authored cut plays: a club's overhead is the
	# one-hand chop, its sweep is the authored heavy clip, and every lunge is the
	# dagger's stab - which is also the whole vocabulary of a shiv.
	var pinned := {
		"club_makeshift": {"overhead": "Sword_Overhead_OneHand",
			"slash": "Sword_Overhead", "stab": "Dagger_Stab"},
		"branch_heavy": {"overhead": "Sword_Overhead_OneHand",
			"slash": "Sword_Overhead", "stab": "Dagger_Stab"},
		"dagger_ironwood": {"overhead": "Dagger_Stab",
			"slash": "Sword_Overhead", "stab": "Dagger_Stab"},
	}
	for item_id: String in pinned:
		var probe = Presenter.new()
		probe.mob_id = "hollow_warden"
		probe.profile = WatcherScript.WATCHER_PROFILES["hollow_warden"]
		root.add_child(probe)
		await process_frame
		probe.set_held_weapon(item_id)
		var table: Dictionary = pinned[item_id]
		for swing: String in table:
			check(str(probe.attack_clip(swing)) == str(table[swing]),
				"%s's %s plays %s (%s)" % [item_id, swing, str(table[swing]),
					str(probe.attack_clip(swing))])
			check(probe.has_clip(str(table[swing])),
				"and the rig carries %s" % str(table[swing]))
		probe.queue_free()
		await process_frame

	# The playback itself, on a fresh presenter: the stance, the crouch and the
	# gait are the rig's, and dropping the stance returns to the idle.
	var walker = Presenter.new()
	walker.mob_id = "ossuary_stalker"
	walker.profile = WatcherScript.WATCHER_PROFILES["ossuary_stalker"]
	root.add_child(walker)
	await physics_frame
	await physics_frame
	walker.set_held_weapon("club_makeshift")
	walker.set_motion(Vector3.ZERO, true)
	await physics_frame
	check(walker.get_clip_name() == IDLE_CLIP,
		"an armed body rests in the rig's combat idle (%s)" % walker.get_clip_name())
	var standing_head: float = walker.head_hitbox_center().y
	walker.set_poise(true, false)
	await physics_frame
	check(walker.get_clip_name() == BLOCK_CLIP,
		"a held guard plays the block loop (%s)" % walker.get_clip_name())
	walker.set_poise(false, true)
	await physics_frame
	await physics_frame
	check(walker.rig._crouch_amount > 0.0,
		"a crouch folds the rig (%f)" % walker.rig._crouch_amount)
	check(walker.head_hitbox_center().y < standing_head - 0.2,
		"and the body comes down with it (%.2f -> %.2f)"
		% [standing_head, walker.head_hitbox_center().y])
	walker.set_poise(false, false)
	for frame in 4:
		walker.set_motion(Vector3(2.0, 0.0, 0.0), true)
		await physics_frame
	var walking := walker.get_clip_name()
	check(walking == "Walk_Loop" or walking == "Jog_Fwd_Loop",
		"and a moving body walks on the rig's own cycle (%s)" % walking)
	walker.queue_free()
	await process_frame


# --- death -----------------------------------------------------------------

func check_death() -> void:
	var watcher = _samples[_samples.size() - 1]
	var rig = watcher._visual.rig
	_defeats = 0
	watcher.defeated.connect(_on_defeated)
	watcher.take_damage(4000.0, 90)
	check(_defeats == 1, "a killed watcher reports its defeat exactly once (%d)" % _defeats)
	check(not watcher.alive, "the body is dead")
	check(not watcher.hunting(), "a corpse is not hunting")
	check(watcher._visual.is_dead(), "the corpse holds its own death")
	check(CorpsePhysics.is_limp(rig), "and the skeleton is the shared ragdoll")
	check(not rig.is_physics_processing(), "the authored clock is stopped")
	watcher.take_damage(4000.0, 90)
	check(_defeats == 1, "a blow on the corpse is not a second kill (%d)" % _defeats)
	check(watcher.gear_items().size() >= 1, "the corpse still lists its kit")
