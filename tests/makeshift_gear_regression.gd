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

const MAKESHIFT_SCENE := "res://assets/characters/armor/ironwood_makeshift.glb"
const MAKESHIFT_JSON := "res://assets/characters/armor/ironwood_makeshift.json"
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
	check(is_equal_approx(ArmorData.reduction({}), 0.0), "No armour guards nothing")
	var full_makeshift := {}
	for slot in ArmorData.SLOTS:
		full_makeshift[slot] = set_index
	check(is_equal_approx(ArmorData.reduction(full_makeshift), 0.0),
		"The salvage skin is the tier-0 starter set: it guards nothing")
	# The starter kit is the salvage set, and the blades are on the smith.
	var defaults: Dictionary = StateScript.DEFAULTS
	for slot in ArmorData.SLOTS:
		check(str(defaults.get(slot, "")) == ArmorData.item_id(set_index, slot),
			"The starting " + slot + " is the Makeshift piece")
	check(not StateScript.STARTING_INVENTORY.has("sword_makeshift"),
		"The salvage cleaver is bought, not starter luggage")
	check(StateScript.ITEMS.has("sword_makeshift") and StateScript.ITEMS.has("dagger_makeshift"),
		"Both salvage blades are in the catalog")
	var smith: Dictionary = StateScript.VENDORS[1]
	check((smith.stock as Array).has("sword_makeshift"), "The smith sells the salvage cleaver")
	check((smith.stock as Array).has("dagger_makeshift"), "The smith sells the salvage shiv")
	var quartermaster: Dictionary = StateScript.VENDORS[2]
	for slot in ArmorData.SLOTS:
		check((quartermaster.stock as Array).has(ArmorData.item_id(set_index, slot)),
			"The quartermaster stocks the salvage " + slot)
	# A salvage chest swapped for a mail one changes guard by exactly the mail row.
	var mixed := full_makeshift.duplicate()
	mixed["chest"] = ArmorData.SET_IDS.find("mail")
	check(is_equal_approx(ArmorData.reduction(mixed), ArmorData.reduction_for(1, "chest")),
		"Guard comes only from the forged piece")


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


func _check_rig() -> void:
	var frontier = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(frontier)
	for frame in 6:
		await process_frame
	var rig = frontier.player
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
	var rig = frontier.player
	check(rig != null, "The frontier exposes the rig for the blade check")
	if rig == null:
		frontier.queue_free()
		return
	var crafted := StateScript.build_loadout("sword_makeshift", "shield_buckler",
		{"head": 4, "chest": 4, "hands": 4, "legs": 4, "feet": 4})
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
	var shiv := StateScript.build_loadout("dagger_makeshift", "shield_buckler",
		{"head": 4, "chest": 4, "hands": 4, "legs": 4, "feet": 4})
	rig.apply_loadout(shiv)
	await process_frame
	check(str(rig.active_dagger.get("skin")) == "makeshift", "The salvage shiv replaces the iron dagger model")
	check(rig.weapon == "dagger", "The salvage shiv selects dagger mode")
	frontier.queue_free()
	await process_frame
