extends SceneTree

## Makeshift starter gear: the salvage armour set and the salvage blades.
##
## The five pieces ship as their own skinned GLB and are re-pointed at the live
## ranger skeleton at runtime, and the two blades reuse the short-blade combat
## profiles with a different model family. Both are easy to break silently —
## an unregistered armour piece renders as a bare ranger, and a lost skin swap
## renders the salvage blade as forged steel — so this test drives the real rig.

const ArmorData = preload("res://scripts/armor_data.gd")
const StateScript = preload("res://scripts/player_state.gd")
const Combat = preload("res://scripts/combat.gd")

const MAKESHIFT_SCENE := "res://assets/characters/armor/ironwood_makeshift.glb"
const MAKESHIFT_JSON := "res://assets/characters/armor/ironwood_makeshift.json"
const NAKED_SCENE := "res://assets/characters/armor/ironwood_naked.glb"
const NAKED_JSON := "res://assets/characters/armor/ironwood_naked.json"
const NAKED_PIECES := ["Armor_Naked_Chest", "Armor_Naked_Legs"]
const SLOT_PIECES := {
	"head": "Armor_Makeshift_Head",
	"chest": "Armor_Makeshift_Chest",
	"hands": "Armor_Makeshift_Hands",
	"legs": "Armor_Makeshift_Legs",
	"feet": "Armor_Makeshift_Feet",
}

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	_check_catalog()
	await _check_asset()
	await _check_rig()
	await _check_blades()
	print("MAKESHIFT_GEAR_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_catalog() -> void:
	var set_index := ArmorData.SET_IDS.find("makeshift")
	check(set_index >= 0, "Makeshift is a registered armour set")
	check(ArmorData.SET_ABBREVIATIONS.size() == ArmorData.SET_IDS.size(),
		"Every armour set has a HUD abbreviation")
	check(ArmorData.PIECE_MASK >= (1 << (ArmorData.SLOTS.size() * 2)) - 1,
		"The armour piece mask fits the set count")
	check(ArmorData.SHIELD_BIT > ArmorData.PIECE_MASK,
		"The shield bit sits above the packed armour field")
	for slot in ArmorData.SLOTS:
		var id := ArmorData.item_id(set_index, slot)
		var item: Dictionary = StateScript.ITEMS.get(id, {})
		check(not item.is_empty(), "Catalog carries " + id)
		check(int(item.get("set", -1)) == set_index, id + " maps to the Makeshift set")
		check(str(item.get("slot", "")) == slot, id + " occupies the " + slot + " slot")
		check(not str(item.get("detail", "")).is_empty(), id + " describes its guard")
		var pieces := {}
		for other in ArmorData.SLOTS:
			pieces[other] = set_index
		var bits := ArmorData.pack(pieces)
		var unpacked := ArmorData.unpack(bits)
		for other in ArmorData.SLOTS:
			check(int(unpacked[other]) == set_index,
				"Packing round-trips " + other + " at the Makeshift set index")
	# Two channels: the helmet alone on a head hit, the four body pieces summed
	# on every other hit. Each row is the base figure before trinket guard.
	var rows := {
		"leather":[0.20, 0.10], "mail":[0.30, 0.25], "plate":[0.50, 0.30],
		"cloth":[0.05, 0.05], "makeshift":[0.20, 0.10], "naked":[0.0, 0.0]}
	check(is_equal_approx(ArmorData.head_reduction({}), 0.0) \
			and is_equal_approx(ArmorData.body_reduction({}), 0.0),
		"An empty kit guards nothing")
	check(is_equal_approx(ArmorData.BODY_WEIGHT_TOTAL, 2.6),
		"The body split's divisor matches its weights")
	for set_name: String in rows:
		var row_index: int = ArmorData.SET_IDS.find(set_name)
		var full := {}
		for slot in ArmorData.SLOTS:
			full[slot] = row_index
		check(is_equal_approx(ArmorData.head_reduction(full), rows[set_name][0]),
			set_name + " helmets guard their head figure")
		check(is_equal_approx(ArmorData.body_reduction(full), rows[set_name][1]),
			set_name + " body pieces add up to the body figure")
		# The body split: chest and legs match, hands and feet are 30% of them.
		var chest := ArmorData.reduction_for(row_index, "chest")
		check(is_equal_approx(ArmorData.reduction_for(row_index, "legs"), chest),
			set_name + " legs match the chest figure")
		check(is_equal_approx(ArmorData.reduction_for(row_index, "hands"), chest * 0.3),
			set_name + " hands are 30% of the chest figure")
		check(is_equal_approx(ArmorData.reduction_for(row_index, "feet"), chest * 0.3),
			set_name + " feet are 30% of the chest figure")
		check(is_equal_approx(ArmorData.body_reduction({"head":row_index}), 0.0),
			set_name + " helm adds nothing to the body channel")
		var body_only := full.duplicate()
		body_only["head"] = ArmorData.NONE
		check(is_equal_approx(ArmorData.head_reduction(body_only), 0.0),
			set_name + " body pieces add nothing to the head channel")
	# An empty slot packs into the spare three-bit codes and reads back empty.
	var empty := {}
	for slot in ArmorData.SLOTS:
		empty[slot] = ArmorData.NONE
	var empty_back := ArmorData.unpack(ArmorData.pack(empty))
	for slot in ArmorData.SLOTS:
		check(int(empty_back[slot]) == ArmorData.NONE,
			"An empty " + slot + " slot survives packing")
	check(is_equal_approx(ArmorData.head_reduction(empty_back), 0.0) \
			and is_equal_approx(ArmorData.body_reduction(empty_back), 0.0),
		"Empty slots still guard nothing after the round trip")
	# The starter kit is the salvage set, and the blades are on the smith.
	var defaults: Dictionary = StateScript.DEFAULTS
	for slot in ArmorData.SLOTS:
		check(str(defaults.get(slot, "")) == ArmorData.item_id(set_index, slot),
			"The starting " + slot + " is the Makeshift piece")
	check(not StateScript.DEFAULTS.has("main") or str(StateScript.DEFAULTS.get("main", "")) != "sword_makeshift",
		"The salvage cleaver is bought, not starter luggage")
	var smith: Dictionary = StateScript.VENDORS[1]
	var tier := ["dagger_ironwood", "bow_twig", "club_makeshift", "branch_heavy", "shield_wood"]
	for item_id: String in tier:
		check(StateScript.ITEMS.has(item_id), "The makeshift tier carries " + item_id)
		check((smith.stock as Array).has(item_id), "The smith sells " + item_id)
	check(is_equal_approx(float(StateScript.ITEM_STATS["dagger_ironwood"]["damage"]), 10.0),
		"The Ironwood Shiv deals 10")
	check(is_equal_approx(float(StateScript.ITEM_STATS["bow_twig"]["damage"]), 5.0),
		"The Twig Bow deals 5")
	check(is_equal_approx(float(StateScript.ITEM_STATS["club_makeshift"]["damage"]), 6.0),
		"The Club deals 6")
	check(is_equal_approx(float(StateScript.ITEM_STATS["branch_heavy"]["damage"]), 15.0),
		"The Heavy Tree Branch deals 15")
	check(str(StateScript.ITEMS["branch_heavy"]["category"]) == "2h",
		"The Heavy Tree Branch is the tier's two-handed piece")
	check(not StateScript.ITEMS.has("dagger_makeshift"),
		"The retired shiv id is gone from the catalog")
	check(StateScript.migrate_item_id("dagger_makeshift") == "dagger_ironwood",
		"An old save's shiv migrates onto the ironwood one")
	check(float(StateScript.ITEM_STATS["club_makeshift"]["damage"])
			< float(StateScript.ITEM_STATS["sword_short"]["damage"]),
		"The club is worse than a shortsword")
	check(float(StateScript.ITEM_STATS["branch_heavy"]["damage"])
			< float(StateScript.ITEM_STATS["sword_arming"]["damage"]),
		"The branch is worse than an arming sword")
	check(float(StateScript.ITEM_STATS["bow_twig"]["damage"])
			< float(StateScript.ITEM_STATS["bow_short"]["damage"]),
		"The twig bow is worse than a shortbow")
	check(float(StateScript.ITEM_STATS["dagger_ironwood"]["damage"])
			< float(StateScript.ITEM_STATS["dagger_iron"]["damage"]),
		"The shiv is worse than an iron dagger")
	var quartermaster: Dictionary = StateScript.VENDORS[2]
	var naked := ArmorData.SET_IDS.find("naked")
	check(naked >= 0, "The naked set is registered")
	for slot in ArmorData.SLOTS:
		check((quartermaster.stock as Array).has(ArmorData.item_id(set_index, slot)),
			"The quartermaster stocks the salvage " + slot)
		check((quartermaster.stock as Array).has(ArmorData.item_id(naked, slot)),
			"The quartermaster stocks the naked " + slot)
		var piece: Dictionary = StateScript.ITEMS.get(ArmorData.item_id(naked, slot), {})
		check(not piece.is_empty(), "Catalog carries the naked " + slot)
		check(int(piece.get("set", -1)) == naked, "The naked " + slot + " maps to the naked set")
	# A salvage chest swapped for a mail one changes the body figure by exactly
	# the difference between the two chest pieces; the helm is untouched.
	var full_makeshift := {}
	for slot in ArmorData.SLOTS:
		full_makeshift[slot] = set_index
	var mixed: Dictionary = full_makeshift.duplicate()
	mixed["chest"] = ArmorData.SET_IDS.find("mail")
	check(is_equal_approx(ArmorData.body_reduction(mixed),
			ArmorData.body_reduction(full_makeshift) - ArmorData.reduction_for(set_index,"chest")
			+ ArmorData.reduction_for(1,"chest")),
		"Only the swapped chest changes the body figure")
	check(is_equal_approx(ArmorData.head_reduction(mixed), ArmorData.head_reduction(full_makeshift)),
		"A body swap leaves the helmet channel alone")


func _check_asset() -> void:
	check(ResourceLoader.exists(MAKESHIFT_SCENE), "The Makeshift armour GLB exists")
	if not ResourceLoader.exists(MAKESHIFT_SCENE):
		return
	var packed := load(MAKESHIFT_SCENE) as PackedScene
	check(packed != null, "The Makeshift armour GLB imports as a scene")
	if packed == null:
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	for slot: String in SLOT_PIECES:
		var piece := instance.find_child(str(SLOT_PIECES[slot]), true, false)
		check(piece is MeshInstance3D, "The GLB carries the " + slot + " piece")
		if piece is MeshInstance3D:
			var mesh := piece as MeshInstance3D
			check(mesh.skin != null, "The " + slot + " piece is skinned")
			var materials := 0
			for surface in mesh.mesh.get_surface_count():
				if mesh.mesh.surface_get_material(surface) != null:
					materials += 1
			check(materials > 0, "The " + slot + " piece carries its materials")
	var metadata_text := FileAccess.get_file_as_string(MAKESHIFT_JSON)
	check(not metadata_text.is_empty(), "The Makeshift armour JSON exists")
	if not metadata_text.is_empty():
		var metadata = JSON.parse_string(metadata_text)
		check(metadata is Dictionary, "The Makeshift armour JSON parses")
		if metadata is Dictionary:
			var triangles := int(metadata.get("total_triangles", 0))
			check(triangles > 0, "The armour set reports a triangle count")
			check(triangles <= int(metadata.get("triangle_budget", 22000)),
				"The armour set stays inside its triangle budget")
			check(int(metadata.get("embedded_images", 0)) > 0, "The armour set embeds its textures")
			check(str(metadata.get("set", "")) == "makeshift", "The metadata names the salvage set")
			var pieces: Dictionary = metadata.get("pieces", {})
			for slot: String in SLOT_PIECES:
				var entry: Dictionary = pieces.get(str(SLOT_PIECES[slot]), {})
				check(not entry.is_empty(), "The metadata describes the " + slot + " piece")
				check(str(entry.get("slot", "")) == slot, "The " + slot + " piece reports the " + slot + " slot")
	instance.queue_free()
	await process_frame
	await _check_naked_asset()


## The naked set ships as its own two-piece GLB and covers only the body parts
## that matter: a shirt over the torso and arms, shorts over the hips, and bare
## skin everywhere else.
func _check_naked_asset() -> void:
	check(ResourceLoader.exists(NAKED_SCENE), "The naked armour GLB exists")
	if not ResourceLoader.exists(NAKED_SCENE):
		return
	var packed := load(NAKED_SCENE) as PackedScene
	check(packed != null, "The naked armour GLB imports as a scene")
	if packed == null:
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	for piece_name: String in NAKED_PIECES:
		var piece := instance.find_child(piece_name, true, false)
		check(piece is MeshInstance3D, "The naked GLB carries " + piece_name)
		if piece is MeshInstance3D:
			check((piece as MeshInstance3D).skin != null, piece_name + " is skinned")
	var metadata_text := FileAccess.get_file_as_string(NAKED_JSON)
	check(not metadata_text.is_empty(), "The naked armour JSON exists")
	if not metadata_text.is_empty():
		var metadata = JSON.parse_string(metadata_text)
		check(metadata is Dictionary, "The naked armour JSON parses")
		if metadata is Dictionary:
			check(int(metadata.get("total_triangles", 0)) > 0, "The naked set reports triangles")
			check(str(metadata.get("set", "")) == "naked", "The metadata names the naked set")
	instance.queue_free()
	await process_frame


func _check_rig() -> void:
	var frontier = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(frontier)
	for frame in 6:
		await process_frame
	var rig = frontier.archer
	check(rig != null, "The frontier exposes the player rig")
	if rig == null:
		frontier.queue_free()
		return
	var set_index := ArmorData.SET_IDS.find("makeshift")
	check(int(rig.armor_piece("head")) == set_index, "The ranger starts in the salvage helm")
	var registered := 0
	for slot: String in SLOT_PIECES:
		var pieces: Array = rig._armor_meshes.get(slot, {}).get(set_index, [])
		check(pieces.size() == 1, "The rig registers the salvage " + slot + " mesh")
		for node in pieces:
			registered += 1
			# is_visible_in_tree, not visible: a hidden parent (the imported
			# armour skeleton) silently hides every piece beneath it.
			check(is_instance_valid(node) and (node as MeshInstance3D).is_visible_in_tree(),
				"The equipped salvage " + slot + " is visible in the scene tree")
			if (node as MeshInstance3D).skeleton:
				check((node as MeshInstance3D).get_node_or_null((node as MeshInstance3D).skeleton) == rig.skeleton,
					"The salvage " + slot + " deforms on the live ranger skeleton")
	check(registered == 5, "All five salvage pieces are registered on the rig")
	# Swapping to a forged set hides every salvage piece.
	rig.set_armor_pieces({"head": 1, "chest": 1, "hands": 1, "legs": 1, "feet": 1})
	await process_frame
	for slot: String in SLOT_PIECES:
		for node in rig._armor_meshes.get(slot, {}).get(set_index, []):
			check(not (node as MeshInstance3D).is_visible_in_tree(), "The salvage " + slot + " hides behind mail")
	rig.set_armor_pieces({"head": set_index, "chest": set_index, "hands": set_index,
		"legs": set_index, "feet": set_index})
	await process_frame
	for slot: String in SLOT_PIECES:
		for node in rig._armor_meshes.get(slot, {}).get(set_index, []):
			check((node as MeshInstance3D).is_visible_in_tree(), "The salvage " + slot + " returns when equipped")
	frontier.queue_free()
	await process_frame


func _check_blades() -> void:
	var frontier = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(frontier)
	for frame in 6:
		await process_frame
	var rig = frontier.archer
	check(rig != null, "The frontier exposes the rig for the blade check")
	if rig == null:
		frontier.queue_free()
		return
	var salvage := {"head": 4, "chest": 4, "hands": 4, "legs": 4, "feet": 4}
	var crafted := StateScript.build_loadout("sword_makeshift", "shield_buckler", salvage)
	rig.apply_loadout(crafted)
	await process_frame
	var sword: Node3D = rig._swords[0]
	check(str(sword.get("skin")) == "makeshift", "The salvage cleaver replaces the steel shortsword model")
	check(sword.get_child_count() > 0, "The salvage cleaver builds its geometry")
	check(sword.find_child("Blade", true, false) != null, "The salvage cleaver keeps the shared blade node")
	# The class profile is untouched: it is still the short sword.
	check(rig.sword_index == 0, "The salvage cleaver fights with the short-blade profile")
	var forged := StateScript.build_loadout("sword_short", "shield_buckler",
		{"head": 1, "chest": 1, "hands": 1, "legs": 1, "feet": 1})
	rig.apply_loadout(forged)
	await process_frame
	check(str(rig._swords[0].get("skin")) == "", "Forged steel restores the steel model")
	# The makeshift tier picks its own meshes from the catalog index.
	var club := StateScript.build_loadout("club_makeshift", "shield_wood", salvage)
	rig.apply_loadout(club)
	await process_frame
	check(rig.sword_index == 3, "The club selects the club profile")
	check(rig._swords[3].get_child_count() > 0, "The club builds its own geometry")
	check(rig._swords[3].find_child("Head", true, false) != null,
		"The club carries the root-ball head, not a steel blade")
	check(is_equal_approx(rig.melee_damage(), 6.0), "The club swings for six")
	check(rig.shield_equipped and rig.shield_variant == 3,
		"The wooden shield is the fourth shield variant")
	var branch := StateScript.build_loadout("branch_heavy", "", salvage)
	rig.apply_loadout(branch)
	await process_frame
	check(rig.sword_index == 4, "The heavy branch selects the branch profile")
	check(rig._swords[4].get_child_count() > 0, "The branch builds its own geometry")
	check(is_equal_approx(rig.melee_damage(), 15.0), "The branch swings for fifteen")
	check(not rig.off_weapon_active and not rig.shield_equipped,
		"The two-handed branch locks the off hand")
	var twig := StateScript.build_loadout("bow_twig", "", salvage)
	rig.apply_loadout(twig)
	await process_frame
	check(rig.weapon == "bow" and rig.bow_index == 3, "The twig bow selects the fourth bow profile")
	check(rig._bows[3].get_child_count() > 0, "The twig bow builds its own geometry")
	check(is_equal_approx(Combat.damage_for(3, 1.0), 5.0), "A full twig draw deals five")
	var shiv := StateScript.build_loadout("dagger_ironwood", "shield_wood", salvage)
	rig.apply_loadout(shiv)
	await process_frame
	check(rig.weapon == "dagger", "The ironwood shiv selects dagger mode")
	check(rig.dagger_index == 1, "The shiv selects the second dagger profile")
	check(rig.active_dagger.get_child_count() > 0, "The shiv builds its own geometry")
	check(is_equal_approx(rig.melee_damage(), 10.0), "The shiv stabs for ten")
	check(not is_equal_approx(rig.melee_seconds(), float(rig.dagger_profile(0).seconds)),
		"The shiv keeps its own, slower stab")
	frontier.queue_free()
	await process_frame
