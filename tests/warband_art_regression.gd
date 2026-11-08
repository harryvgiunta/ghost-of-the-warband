extends SceneTree
## Phase 3, wt-15: the wood and the town have to read as places, not as a
## collection of boxes.
##
## Builds the town's real scene and the wood's own builder headless and holds the
## dressing to the contract the brief sets: known groups with known child counts,
## kit-textured materials plus the flame shader exactly where fire belongs, no
## collider anywhere a body can reach, nothing standing on a spawn or a `G` point,
## and no prop floating outside the floor the scene actually built.
##
## The spawns and interaction points come from the scene scripts' own constants -
## `SPAWN_POSTS` and the four service points in the town, `BOSS_POINT` in the wood
## - and the dressing module's declared bounds are compared with the pocket's so
## the two can never drift apart in silence. Every point a body stands in is a
## claim this test can make without a rendered window: the geometry source is the
## authority here, not a screenshot. The cages are gone with the opening, so the
## camp section is gone with them: what is left of it is the wood.

const CampDressingScript = preload("res://scripts/warband/camp_dressing.gd")
const TownDressingScript = preload("res://scripts/warband/town_dressing.gd")
const WoodScript = preload("res://scripts/warband/wood_boss.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")
const SignKit = preload("res://scripts/world/sign_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

const TEST_SAVE := "user://warband_art_state.json"
const WARBAND_SAVE := "user://warband_art_warband.json"
## A body's own footprint. A prop may not cover a spot a body stands in, so the
## prop's extent plus this has to fit between the prop's anchor and the point.
const BODY_RADIUS := 0.45

var wood
var town
var state
var warband
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ART_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()

	# A scene script that fails to parse would leave this coroutine parked; the
	# watchdog turns that hang into a failing run instead of a dead test.
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	watchdog.wait_time = 180.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	check_signs()
	await check_wood()
	await check_town()
	_finish()

func _on_watchdog() -> void:
	check(false, "the art regression hung")
	_finish()

func _finish() -> void:
	for scene_node in [wood, town]:
		if scene_node != null and is_instance_valid(scene_node):
			scene_node.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_ART_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


# --- geometry helpers ------------------------------------------------------

func meshes_under(node: Node, found: Array = []) -> Array:
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		meshes_under(child, found)
	return found

func lights_under(node: Node, found: Array = []) -> Array:
	if node is Light3D:
		found.append(node)
	for child in node.get_children():
		lights_under(child, found)
	return found

## Anything that could stop, block or touch a body. The dressing may never own
## one: the wood's pocket and the town square are the play space.
func solids_under(node: Node, found: Array = []) -> Array:
	if node is CollisionObject3D or node is CollisionShape3D:
		found.append(node)
	for child in node.get_children():
		solids_under(child, found)
	return found

func surfaces_of(mesh_instance) -> int:
	if mesh_instance == null or not (mesh_instance is MeshInstance3D):
		return 0
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return 0
	return mesh.get_surface_count()

## Every label under `node`: a sign is paint on a board, so a sign prop that still
## carries one is a sign that never got made.
func labels_under(node: Node, found: Array = []) -> Array:
	if node is Label3D:
		found.append(node)
	for child in node.get_children():
		labels_under(child, found)
	return found


## The material wearing `sign_id`'s baked face, wherever the prop merged it. Null
## when the prop carries no such face - which is what a board built before the
## switch, or one pointed at the wrong sign, looks like.
func face_of(mesh_instance: Node, sign_id: String) -> Material:
	if not (mesh_instance is MeshInstance3D):
		return null
	var instance := mesh_instance as MeshInstance3D
	var wanted := "sign_%s.png" % sign_id
	var override: Material = instance.material_override
	if override is StandardMaterial3D and _wears(override as StandardMaterial3D, wanted):
		return override
	if instance.mesh == null:
		return null
	for surface in instance.mesh.get_surface_count():
		var material: Material = instance.mesh.surface_get_material(surface)
		if material is StandardMaterial3D and _wears(material as StandardMaterial3D, wanted):
			return material
	return null


func _wears(material: StandardMaterial3D, wanted: String) -> bool:
	return material.albedo_texture != null \
		and material.albedo_texture.resource_path.ends_with(wanted)


## Every sign in `SignKit.SIGNS` has a face on disk of the board's own aspect, at
## the one scale the tool bakes (320 px per metre). This is the check that stops a
## resized board from becoming stretched paint.
func check_signs() -> void:
	var png := 0
	for id in SignKit.SIGNS:
		var spec: Dictionary = SignKit.spec_of(id)
		var size: Vector2 = spec["size"]
		var path := "res://assets/world/textures/sign_%s.png" % id
		var normal_path := "res://assets/world/textures/sign_%s_n.png" % id
		check(not String(spec["text"]).strip_edges().is_empty(),
			"sign %s carries words" % id)
		check(ResourceLoader.exists(path) and ResourceLoader.exists(normal_path),
			"sign %s is baked (%s)" % [id, path.get_file()])
		if not ResourceLoader.exists(path):
			continue
		png += 1
		var texture := load(path) as Texture2D
		check(texture != null and texture.get_width() > 0, "sign %s loads" % id)
		if texture == null:
			continue
		var expected := Vector2(size.x * SignKit.PIXELS_PER_METRE,
			size.y * SignKit.PIXELS_PER_METRE)
		check(absf(float(texture.get_width()) - expected.x) <= 1.0
			and absf(float(texture.get_height()) - expected.y) <= 1.0,
			"sign %s is baked at its board's size (%dx%d for %.2f x %.2f m)"
				% [id, texture.get_width(), texture.get_height(), size.x, size.y])
		var material := TextureLibrary.sign_material(id)
		check(material.albedo_texture == texture,
			"sign %s wears its own face" % id)
		check(material.normal_enabled, "sign %s carries the paint's relief" % id)
		var face := SignKit.face_mesh(id)
		check(is_equal_approx(face.size.x, size.x) and is_equal_approx(face.size.y, size.y),
			"sign %s's quad is the board's face, not a guess" % id)
	check(png == SignKit.SIGNS.size(), "every sign in the table is baked")


func materials_of(meshes: Array) -> Array:
	var found: Array = []
	for mesh_instance in meshes:
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh: Mesh = mesh_instance.mesh
		for surface in mesh.get_surface_count():
			found.append(mesh.surface_get_material(surface))
	return found

func textured_surfaces(materials: Array) -> int:
	var count := 0
	for material in materials:
		if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null:
			count += 1
	return count

func world_aabb(mesh_instance: MeshInstance3D) -> AABB:
	if mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	return mesh_instance.global_transform * mesh_instance.mesh.get_aabb()

func props_of(dressing: Node) -> Array:
	var records = dressing.get("props")
	return records if records is Array else []


# --- the two positional contracts -----------------------------------------

## One check per protected point, naming the closest prop that has a footprint.
## Flat litter (`blocks = false`) is exempt: it may lie under a spawn ring.
func assert_clear(props: Array, points: Array, label: String) -> void:
	for entry in points:
		var point: Vector3 = entry["point"]
		var reach := float(entry["reach"])
		var closest := "no prop at all"
		var margin := INF
		for record in props:
			if not bool(record["blocks"]):
				continue
			var at: Vector3 = record["position"]
			var distance := Vector2(at.x, at.z).distance_to(Vector2(point.x, point.z))
			var gap := distance - (float(record["radius"]) + reach + BODY_RADIUS)
			if gap < margin:
				margin = gap
				closest = "%s (%.2f m spare)" % [String(record["name"]), gap]
		check(margin > 0.0, "%s dressing stands off %s: %s" % [label, String(entry["what"]), closest])


# --- the wood at the far end of the road -----------------------------------

## The wood is the camp's own builders with the cages taken out: the same pocket,
## the same ragged stake line, the same shelters, fire and dressing. What is
## asserted here is what the deletion changed - the clearing is built with no cage
## at all, the master's patch is clear of everything a body can hit, and he stands
## on it.
func check_wood() -> void:
	wood = Node3D.new()
	wood.name = "Wood"
	wood.set_script(WoodScript)
	root.add_child(wood)
	await create_timer(0.9).timeout
	var clearing: Dictionary = wood.clearing
	check(not clearing.is_empty(), "the wood built its clearing")
	var dressing = wood.get_node_or_null("CampDressing")
	check(dressing != null and dressing is Node3D, "the wood builds its dressing")
	if clearing.is_empty() or dressing == null:
		return

	# The cages are gone at the source, not merely hidden.
	check((clearing.get("cages", []) as Array).is_empty(),
		"the clearing is built with zero cages (%d)" % (clearing.get("cages", []) as Array).size())
	check((clearing.get("doors", []) as Array).is_empty(), "and no doors to open")
	var standing := 0
	for index in 4:
		if wood.get_node_or_null("Cage%d" % (index + 1)) != null:
			standing += 1
	check(standing == 0, "not one cage node stands in the wood (%d)" % standing)
	var hardware = dressing.get_node_or_null("CageHardware")
	check(hardware != null and hardware.get_child_count() == 0,
		"and the dressing bolts no iron to a cage (%d)"
		% (0 if hardware == null else hardware.get_child_count()))
	for label in ["Banners", "Gibbets", "AltarDressing", "Braziers", "GroundScatter"]:
		var group = dressing.get_node_or_null(label)
		check(group != null and group.get_child_count() > 0,
			"the wood still carries its %s" % label)

	# The master stands on his own patch, in the open air, with his pair beside
	# him - the one thing in the wood that fights back properly.
	check(wood.boss_point().is_equal_approx(WoodScript.BOSS_POINT),
		"the wood names the demon's patch (%s)" % str(wood.boss_point()))
	check(wood.master != null and is_instance_valid(wood.master),
		"the Horned Thing stands in the wood")
	if wood.master != null and is_instance_valid(wood.master):
		# Flat only: this build has no baked ground under it, so the body's own
		# height here is where gravity left it. The patch it stands on is the claim.
		var at: Vector3 = (wood.master as Node3D).position
		check(Vector2(at.x - WoodScript.BOSS_POINT.x,
			at.z - WoodScript.BOSS_POINT.z).length() < 0.01,
			"on the patch it is named for (%.1f, %.1f)" % [at.x, at.z])
		check(wood.master_alive(), "and he is on his feet at the build")
	check(wood.guards.size() == 1 + WoodScript.GUARD_POSTS.size(),
		"the master and his keepers are the wood's own list (%d)" % wood.guards.size())
	check(wood.guards.has(wood.master), "the master is on it")
	for index in WoodScript.GUARD_POSTS.size():
		var post: Vector3 = WoodScript.GUARD_POSTS[index]
		var keeper = wood.get_node_or_null("WoodKeeper%d" % (index + 1))
		check(keeper != null, "keeper %d stands with him" % (index + 1))
		if keeper != null:
			check(Vector2(keeper.position.x - post.x, keeper.position.z - post.z).length() < 0.01,
				"keeper %d holds its own post" % (index + 1))

	# Clearance: nothing solid stands inside the patch, and no dressing prop's
	# footprint reaches a body standing on it.
	var solids = clearing.get("solids")
	var nearest := INF
	var nearest_name := "nothing"
	if solids != null:
		for child in (solids as Node).get_children():
			if not (child is CollisionShape3D):
				continue
			var at: Vector3 = (child as Node3D).global_position
			var gap := Vector2(at.x - WoodScript.BOSS_POINT.x, at.z - WoodScript.BOSS_POINT.z).length()
			if gap < nearest:
				nearest = gap
				nearest_name = "a trunk at (%.1f, %.1f)" % [at.x, at.z]
	check(nearest >= 7.0, "no trunk stands inside the fight's patch (nearest %s, %.1f m)"
		% [nearest_name, nearest])
	var props := props_of(dressing)
	check(props.size() >= 20, "the wood dressing records %d props for the clearance check" % props.size())
	assert_clear(props, [{"what": "the master's patch", "point": WoodScript.BOSS_POINT,
		"reach": 0.0}], "wood")

	# The dressing's declared yard is the pocket's, so the two cannot drift.
	check(is_equal_approx(CampDressingScript.YARD_HALF_WIDTH, WoodScript.YARD_HALF_WIDTH)
		and is_equal_approx(CampDressingScript.YARD_FRONT, WoodScript.YARD_FRONT)
		and is_equal_approx(CampDressingScript.YARD_BACK, WoodScript.YARD_BACK),
		"the dressing's yard mirrors wood_boss.gd's YARD_*")
	check(CampDressingScript.FLOOR_HALF_WIDTH > WoodScript.YARD_HALF_WIDTH
		and CampDressingScript.FLOOR_FRONT < WoodScript.YARD_FRONT
		and CampDressingScript.FLOOR_BACK > WoodScript.YARD_BACK,
		"the declared floor is bigger than the pocket, always")
	check(int(clearing.get("trees", 0)) >= 150,
		"the pocket still sits inside a real wood (%d trees)" % int(clearing.get("trees", 0)))
	check(int(clearing.get("stakes", 0)) >= 60,
		"its boundary is still a ragged stake line (%d)" % int(clearing.get("stakes", 0)))

	print("WARBAND_ART_WOOD groups=%d trees=%d stakes=%d props=%d nearest_solid=%.1f" % [
		dressing.get_child_count(), int(clearing.get("trees", 0)),
		int(clearing.get("stakes", 0)), props.size(), nearest])

	wood.queue_free()
	await process_frame


# --- the town square -------------------------------------------------------

func check_town() -> void:
	town = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(town)
	await create_timer(0.7).timeout
	var dressing = town.get_node_or_null("TownDressing")
	check(dressing != null and dressing is Node3D, "the town square builds its dressing")
	if dressing == null:
		return

	var groups := ["Counters", "StashAwning", "Signpost", "FireRing", "LanternPools"]
	check(dressing.get_child_count() == groups.size(),
		"the town dressing is %d prop groups (%d)" % [groups.size(), dressing.get_child_count()])
	for label in groups:
		check(dressing.get_node_or_null(label) != null, "the town dressing has a %s group" % label)

	# The two booths, built around the desks the scene placed.
	var counters = dressing.get_node_or_null("Counters")
	check(counters != null and counters.get_child_count() == 2,
		"both counters are dressed (%d)" % (0 if counters == null else counters.get_child_count()))
	if counters != null:
		for label in ["RecruiterCounter", "QuartermasterCounter"]:
			var booth := counters.get_node_or_null(label) as MeshInstance3D
			check(booth != null, "%s is built" % label)
			if booth == null:
				continue
			check(surfaces_of(booth) >= 4,
				"%s merges posts, awning and hanging goods (%d surfaces)" % [label, surfaces_of(booth)])
			var box := world_aabb(booth)
			check(box.size.x > 2.4 and box.size.z > 1.6,
				"%s frames its desk (%.1f x %.1f m)" % [label, box.size.x, box.size.z])
			check(box.end.y > 2.2, "%s is a booth, not a table (%.1f m tall)" % [label, box.end.y])
			check(textured_surfaces(materials_of([booth])) >= 2,
				"%s is timber and hide from the village kit" % label)

	# The stash under its roof.
	var stash = dressing.get_node_or_null("StashAwning")
	var roof: MeshInstance3D = null
	if stash != null:
		roof = stash.get_node_or_null("StashRoof") as MeshInstance3D
	check(roof != null, "the stash has a roof")
	if roof != null:
		var box := world_aabb(roof)
		check(box.size.x > 3.0 and box.size.z > 2.0,
			"the stash roof covers the chest (%.1f x %.1f m)" % [box.size.x, box.size.z])
		check(box.end.y > 2.2, "the stash roof clears a body's head (%.1f m)" % box.end.y)
		check(surfaces_of(roof) >= 4, "the stash roof merges posts, hide and stock (%d surfaces)" % surfaces_of(roof))

	# The fingerpost: real text, and each board really points at what it names.
	var signpost = dressing.get_node_or_null("Signpost")
	check(labels_under(signpost).is_empty() if signpost != null else false,
		"the fingerpost's words are painted on its boards, not floated over them")
	var lettered := 0
	for board_index in TownDressingScript.SIGN_BOARDS.size():
		if signpost == null:
			break
		var row: Dictionary = TownDressingScript.SIGN_BOARDS[board_index]
		var board := signpost.get_node_or_null("Board%d" % (board_index + 1)) as Node3D
		check(board != null, "finger board %d exists" % (board_index + 1))
		if board == null:
			continue
		var sign_id := String(row["sign"])
		var board_mesh := board.get_node_or_null("Board") as MeshInstance3D
		check(face_of(board_mesh, sign_id) != null,
			"finger board %d is painted with %s's words" % [board_index + 1, sign_id])
		check(SignKit.text_of(sign_id) == String(row["text"]),
			"finger board %d's paint says \"%s\"" % [board_index + 1, SignKit.text_of(sign_id)])
		check(labels_under(board).is_empty(),
			"finger board %d carries no floating text" % (board_index + 1))
		if face_of(board_mesh, sign_id) != null:
			lettered += 1
		# The board's own +X has to point at its destination.
		var target: Vector3 = TownDressingScript.SIGN_BOARDS[board_index]["target"]
		var post_at: Vector3 = TownDressingScript.SIGN_POST
		var heading := (board.global_transform.basis * Vector3.RIGHT).normalized()
		var wanted := target - post_at
		wanted.y = 0.0
		wanted = wanted.normalized()
		check(heading.dot(wanted) > 0.999,
			"finger board %d points at what it names (%.3f)" % [board_index + 1, heading.dot(wanted)])
	check(lettered == TownDressingScript.SIGN_BOARDS.size(),
		"every lettered board is direction-correct")

	# The square's own board, and the arena's name and the altar's cut into stone:
	# words in the surface of the prop, never a label floating over it.
	var square = town.get_node_or_null("Signpost/SquareBoard") as Node3D
	check(square != null, "the square's board is nailed to the signpost")
	if square != null:
		check(face_of(square.get_node_or_null("Board"), "square") != null,
			"the square's board is painted with its own words")
		check(labels_under(square).is_empty(),
			"the square's board carries no floating text")
		check(square.position.z > 0.13,
			"the board stands proud of its post (%.2f m)" % square.position.z)
	var arena_plate = town.get_node_or_null("ArenaGate/ArenaNameplate")
	check(arena_plate != null, "the arena's name stands on its gate")
	if arena_plate != null:
		check(face_of(arena_plate.get_node_or_null("Plate"), "arena") != null,
			"the arena's name is cut into the lintel's stone")
		check(labels_under(arena_plate).is_empty(), "nothing floats over the arena gate")
	var altar_node = town.get_node_or_null("SacrificialAltar")
	check(altar_node != null, "the altar stands in the square")
	if altar_node != null:
		var altar_plate = altar_node.get_node_or_null("AltarNameplate")
		check(altar_plate != null and face_of(altar_plate.get_node_or_null("Plate"), "altar") != null,
			"the altar's name is cut into its stele")
		check(labels_under(altar_node).is_empty(), "the altar says its name in stone")

	# The ring around the fire: centred on the scene's own pit, wider than it,
	# with the woodpile as its own merge beside the seats.
	var ring_group = dressing.get_node_or_null("FireRing")
	var ring_meshes := meshes_under(ring_group)
	check(ring_meshes.size() == 2, "the fire ring is the ring and the woodpile (%d meshes)" % ring_meshes.size())
	check(ring_group != null and ring_group.get_node_or_null("Firewood") != null,
		"the woodpile stands beside the ring")
	var ring: MeshInstance3D = null
	if ring_group != null:
		ring = ring_group.get_node_or_null("FireRing") as MeshInstance3D
	check(ring != null, "the fire ring itself is one merged mesh")
	if ring != null:
		var box := world_aabb(ring)
		var centre := box.get_center()
		check(Vector2(centre.x, centre.z).length() < 0.6,
			"the fire ring is centred on the campfire (%.2f m off)" % Vector2(centre.x, centre.z).length())
		check(box.size.x > 4.4 and box.size.z > 4.4,
			"the ring reaches past the pit (%.1f x %.1f m)" % [box.size.x, box.size.z])
		check(surfaces_of(ring) >= 3,
			"the ring merges kerb, benches and rags (%d surfaces)" % surfaces_of(ring))
	check(town.flame is MeshInstance3D and town.flame.mesh != null,
		"the scene's own flame is still in the pit")
	check(town.fire_light is OmniLight3D and town.fire_light.light_energy > 0.0,
		"the scene's own fire light still burns")

	# The lantern pools.
	var lanterns = dressing.get_node_or_null("LanternPools")
	check(lanterns != null and lanterns.get_child_count() == TownDressingScript.LANTERN_POSTS.size(),
		"four lanterns pool light on the corners")
	if lanterns != null:
		for lantern_index in lanterns.get_child_count():
			var lantern := lanterns.get_child(lantern_index) as Node3D
			var lantern_lights := lights_under(lantern)
			check(lantern_lights.size() == 1, "lantern %d carries one light" % (lantern_index + 1))
			if lantern_lights.size() == 1:
				var lamp := lantern_lights[0] as Light3D
				check(lamp.light_energy > 1.0 and lamp.omni_range >= 6.0,
					"lantern %d actually pools (%.1f energy, %.1f m)" % [lantern_index + 1, lamp.light_energy, lamp.omni_range])
			check(meshes_under(lantern).size() == 1, "lantern %d is one merged post and lamp" % (lantern_index + 1))
			var heading := (lantern.global_transform.basis * Vector3.BACK).normalized()
			var wanted := -Vector3(lantern.position.x, 0.0, lantern.position.z).normalized()
			check(heading.dot(wanted) > 0.999,
				"lantern %d reaches in over the square" % (lantern_index + 1))

	# Materials, and no collider.
	var town_meshes := meshes_under(dressing)
	var town_materials := materials_of(town_meshes)
	var unset := 0
	for material in town_materials:
		if material == null:
			unset += 1
	check(unset == 0, "every town surface carries a material (%d unset)" % unset)
	check(textured_surfaces(town_materials) >= 6,
		"the town dressing is textured from the village kit (%d textured surfaces)" % textured_surfaces(town_materials))
	check(lights_under(dressing).size() == TownDressingScript.LANTERN_POSTS.size(),
		"the town dressing owns exactly its lantern lights (%d)" % lights_under(dressing).size())
	var solids := solids_under(dressing)
	check(solids.is_empty(), "the town dressing adds no collider (%d found)" % solids.size())

	# Bounds: the declared square is the scene's square, and nothing stands
	# outside the walls.
	check(is_equal_approx(TownDressingScript.WALL_RADIUS, TownScript.WALL_RADIUS),
		"the dressing's square mirrors town_hub.gd's WALL_RADIUS")
	var props := props_of(dressing)
	check(props.size() >= 20, "the town dressing records %d props for the clearance check" % props.size())
	var outside_wall := 0
	for record in props:
		var at: Vector3 = record["position"]
		if absf(at.x) > TownScript.WALL_RADIUS or absf(at.z) > TownScript.WALL_RADIUS:
			outside_wall += 1
	check(outside_wall == 0, "every town prop stands inside the walls (%d outside)" % outside_wall)
	var off_square := 0
	for mesh_instance in town_meshes:
		var box := world_aabb(mesh_instance)
		if absf(box.position.x) > TownScript.WALL_RADIUS + 0.05 \
				or absf(box.position.z) > TownScript.WALL_RADIUS + 0.05 \
				or absf(box.end.x) > TownScript.WALL_RADIUS + 0.05 \
				or absf(box.end.z) > TownScript.WALL_RADIUS + 0.05:
			off_square += 1
	check(off_square == 0, "every town prop's geometry stays inside the walls (%d outside)" % off_square)

	# Nobody's spawn, and no service or the gate, has a prop on it.
	var points: Array = []
	for post in TownScript.SPAWN_POSTS:
		points.append({"what": "a muster post", "point": post, "reach": 0.0})
	points.append({"what": "the stash", "point": TownScript.STASH_POINT, "reach": 0.0})
	points.append({"what": "the altar", "point": TownScript.ALTAR_POINT, "reach": 0.0})
	points.append({"what": "the recruiter", "point": TownScript.RECRUITER_POINT, "reach": 0.0})
	points.append({"what": "the quartermaster", "point": TownScript.QUARTERMASTER_POINT, "reach": 0.0})
	points.append({"what": "the signpost", "point": TownScript.SIGN_POINT, "reach": 0.0})
	assert_clear(props, points, "town")

	print("WARBAND_ART_TOWN groups=%d meshes=%d props=%d materials=%d" % [
		dressing.get_child_count(), town_meshes.size(), props.size(), town_materials.size()])

	town.queue_free()
	await process_frame
