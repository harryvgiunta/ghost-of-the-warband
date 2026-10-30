extends SceneTree
## Phase 3, wt-15: the camp and the town have to read as places, not as a
## collection of boxes.
##
## Builds both real scenes headless and holds the dressing to the contract the
## brief sets: known groups with known child counts, kit-textured materials plus
## the flame shader exactly where fire belongs, no collider anywhere a body can
## reach, nothing standing on a spawn or a `G` point, and no prop floating
## outside the floor the scene actually built.
##
## The spawns and interaction points come from the two scene scripts' own
## constants - `CAGE_POSTS`, `CAGE_CLAMP_RADIUS`, `GATE_POINT`,
## `GATE_WATCHERS`, `REINFORCE_POSTS`, `WEAPON_DROPS`, `SPAWN_POSTS` and the four
## service points - and the dressing modules' declared bounds are compared with
## the scenes' so the two can never drift apart in silence. Every point a body
## stands in is a claim this test can make without a rendered window: the
## geometry source is the authority here, not a screenshot.

const CampDressingScript = preload("res://scripts/warband/camp_dressing.gd")
const TownDressingScript = preload("res://scripts/warband/town_dressing.gd")
const CageScript = preload("res://scripts/warband/cage_escape.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")

const TEST_SAVE := "user://warband_art_state.json"
const WARBAND_SAVE := "user://warband_art_warband.json"
const FLAME_SHADER := "res://scripts/world/shaders/flame.gdshader"
## A body's own footprint. A prop may not cover a spot a body stands in, so the
## prop's extent plus this has to fit between the prop's anchor and the point.
const BODY_RADIUS := 0.45

var camp
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

	await check_camp()
	await check_town()
	_finish()

func _on_watchdog() -> void:
	check(false, "the art regression hung")
	_finish()

func _finish() -> void:
	for scene_node in [camp, town]:
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

func particles_under(node: Node, found: Array = []) -> Array:
	if node is CPUParticles3D:
		found.append(node)
	for child in node.get_children():
		particles_under(child, found)
	return found

## Anything that could stop, block or touch a body. The dressing may never own
## one: the camp yard and the town square are the play space.
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

func is_flame(material) -> bool:
	if not (material is ShaderMaterial):
		return false
	var shader: Shader = (material as ShaderMaterial).shader
	return shader != null and String(shader.resource_path) == FLAME_SHADER

func flame_surfaces(materials: Array) -> int:
	var count := 0
	for material in materials:
		if is_flame(material):
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


## Every record has to be on the ground it claims: inside the walled yard, or
## outside the walls but still on the floor (the camp gibbets).
func assert_in_zone(props: Array, label: String, half: float, front: float, back: float,
		floor_half: float, floor_front: float, floor_back: float) -> void:
	var strays := 0
	var detail := ""
	for record in props:
		var at: Vector3 = record["position"]
		var inside_yard: bool = absf(at.x) <= half and at.z >= front and at.z <= back
		var inside_floor: bool = absf(at.x) <= floor_half and at.z >= floor_front and at.z <= floor_back
		var wanted_yard := String(record["zone"]) == "yard"
		var ok := inside_yard if wanted_yard else (inside_floor and not inside_yard)
		if not ok:
			strays += 1
			if detail.is_empty():
				detail = "%s at (%.1f, %.1f)" % [String(record["name"]), at.x, at.z]
	check(strays == 0, "%s dressing keeps every prop on its own ground (%d stray: %s)" % [label, strays, detail])


# --- the cage camp ---------------------------------------------------------

func check_camp() -> void:
	camp = load("res://scenes/cage_escape.tscn").instantiate()
	root.add_child(camp)
	await create_timer(0.9).timeout
	var dressing = camp.get_node_or_null("CampDressing")
	check(dressing != null and dressing is Node3D, "the cage camp builds its dressing")
	if dressing == null:
		return

	var groups := ["CageHardware", "Banners", "Gibbets", "AltarDressing", "Braziers", "GroundScatter"]
	check(dressing.get_child_count() == groups.size(),
		"the camp dressing is %d prop groups (%d)" % [groups.size(), dressing.get_child_count()])
	for label in groups:
		check(dressing.get_node_or_null(label) != null, "the camp dressing has a %s group" % label)

	# Every cage carries its own hardware, bolted to the cage node the scene built.
	var hardware = dressing.get_node_or_null("CageHardware")
	check(hardware != null and hardware.get_child_count() == CageScript.CAGE_POSTS.size(),
		"every cage carries hardware (%d)" % (0 if hardware == null else hardware.get_child_count()))
	if hardware != null:
		for index in CageScript.CAGE_POSTS.size():
			var cage_mesh := hardware.get_node_or_null("Cage%dHardware" % (index + 1)) as MeshInstance3D
			var post: Vector3 = CageScript.CAGE_POSTS[index]
			var cage_node := camp.get_node_or_null("Cage%d" % (index + 1)) as Node3D
			check(cage_mesh != null and cage_node != null, "cage %d has its merged hardware" % (index + 1))
			if cage_mesh == null or cage_node == null:
				continue
			# The hardware is built in the cage's own frame and then placed on it,
			# so it moves with the cage the scene placed.
			check(cage_mesh.position.distance_to(cage_node.position) < 0.01,
				"cage %d hardware sits on its own cage" % (index + 1))
			check(Vector2(cage_node.position.x, cage_node.position.z).distance_to(
				Vector2(post.x, post.z)) < 0.01, "cage %d stands on its own post" % (index + 1))
			check(surfaces_of(cage_mesh) >= 5,
				"cage %d hardware merges iron, straw and bone (%d surfaces)" % [index + 1, surfaces_of(cage_mesh)])

	# The cult's banners.
	var banners = dressing.get_node_or_null("Banners")
	check(banners != null and banners.get_child_count() == CampDressingScript.BANNER_POSTS.size(),
		"the palisade carries %d banners" % CampDressingScript.BANNER_POSTS.size())
	if banners != null:
		for index in banners.get_child_count():
			var banner := banners.get_child(index) as MeshInstance3D
			check(banner != null and surfaces_of(banner) >= 3,
				"banner %d is cloth, sigil and skull in one merge" % (index + 1))
			var box := world_aabb(banner)
			check(box.size.y > 3.0, "banner %d hangs the height of the palisade (%.1f m)" % [index + 1, box.size.y])

	# The gibbets on the road in.
	var gibbets = dressing.get_node_or_null("Gibbets")
	check(gibbets != null and gibbets.get_child_count() == CampDressingScript.GIBBET_POSTS.size(),
		"two gibbets frame the gate road")
	if gibbets != null:
		for index in gibbets.get_child_count():
			var gibbet := gibbets.get_child(index) as MeshInstance3D
			check(gibbet != null and surfaces_of(gibbet) >= 3,
				"gibbet %d is a frame, a hanging cage and its bones" % (index + 1))
			var box := world_aabb(gibbet)
			check(box.size.y > 3.0 and box.size.x > 2.0,
				"gibbet %d is a gallows, not a stick (%.1f x %.1f m)" % [index + 1, box.size.x, box.size.y])

	# The cold altar: the only place in the camp that burns cold.
	var altar_group = dressing.get_node_or_null("AltarDressing")
	var altar_meshes := meshes_under(altar_group)
	check(altar_meshes.size() == 1, "the altar dressing is one merged mesh (%d)" % altar_meshes.size())
	var altar_materials := materials_of(altar_meshes)
	check(textured_surfaces(altar_materials) >= 2,
		"the altar dressing uses the kit's stone, bone and twig (%d textured)" % textured_surfaces(altar_materials))
	var cold_flames := 0
	for material in altar_materials:
		if not is_flame(material):
			continue
		cold_flames += 1
		var hot = (material as ShaderMaterial).get_shader_parameter("hot_color")
		var cool = (material as ShaderMaterial).get_shader_parameter("cool_color")
		check(hot is Color and (hot as Color).b > (hot as Color).r,
			"the altar's flame cards ask the flame shader for a cold palette")
		check(cool is Color and (cool as Color).b > (cool as Color).r,
			"the altar's flame tips are blue, not orange")
	check(cold_flames == 1, "the altar owns its own cold flame material, not the fire's (%d)" % cold_flames)
	check(lights_under(altar_group).size() == 1, "the cold altar casts one light")

	# Four ember braziers: flame cards, embers and a light each.
	var braziers = dressing.get_node_or_null("Braziers")
	check(braziers != null and braziers.get_child_count() == CampDressingScript.BRAZIER_POSTS.size(),
		"the yard has %d braziers" % CampDressingScript.BRAZIER_POSTS.size())
	if braziers != null:
		for index in braziers.get_child_count():
			var brazier := braziers.get_child(index) as Node3D
			var brazier_meshes := meshes_under(brazier)
			check(brazier_meshes.size() == 1, "brazier %d is one merged iron-and-coals mesh" % (index + 1))
			check(flame_surfaces(materials_of(brazier_meshes)) >= 1,
				"brazier %d burns on the flame shader" % (index + 1))
			check(particles_under(brazier).size() >= 1, "brazier %d throws embers" % (index + 1))
			var brazier_lights := lights_under(brazier)
			check(brazier_lights.size() == 1 and (brazier_lights[0] as Light3D).light_energy > 1.0,
				"brazier %d lights the yard" % (index + 1))
			check(brazier_lights.size() == 1 and brazier_lights[0] is FireFlicker,
				"brazier %d breathes instead of glowing flat" % (index + 1))

	# The litter.
	var scatter = dressing.get_node_or_null("GroundScatter")
	check(scatter != null and scatter.get_child_count() == 3,
		"the ground carries straw, blood and cart ruts (%d)" % (0 if scatter == null else scatter.get_child_count()))
	if scatter != null:
		for label in ["StrawScatter", "BloodStains", "CartRuts"]:
			var flat := scatter.get_node_or_null(label) as MeshInstance3D
			check(flat != null and surfaces_of(flat) >= 1, "%s is merged into one mesh" % label)
			if flat == null:
				continue
			check(flat.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s is ground litter, so it casts no shadow" % label)
			check(world_aabb(flat).size.y < 0.6, "%s lies flat on the yard (%.2f m)" % [label, world_aabb(flat).size.y])
		var stains := scatter.get_node_or_null("BloodStains") as MeshInstance3D
		if stains != null and stains.mesh != null:
			var blood := stains.mesh.surface_get_material(0)
			check(blood is StandardMaterial3D, "the stains are a plain surface material")
			if blood is StandardMaterial3D:
				var colour: Color = (blood as StandardMaterial3D).albedo_color
				check(colour.r > colour.g * 2.0 and colour.r > colour.b * 2.0,
					"the stains are blood and not paint (%s)" % colour.to_html(false))

	# Materials: every surface has one, the kits' textures are in use, and the
	# flame shader appears exactly where something burns.
	var camp_meshes := meshes_under(dressing)
	var camp_materials := materials_of(camp_meshes)
	var unset := 0
	for material in camp_materials:
		if material == null:
			unset += 1
	check(unset == 0, "every merged surface carries a material (%d unset)" % unset)
	check(textured_surfaces(camp_materials) >= 6,
		"the camp dressing is textured from the world kits (%d textured surfaces)" % textured_surfaces(camp_materials))
	check(flame_surfaces(camp_materials) >= 5,
		"four braziers and the altar share the flame shader (%d flame surfaces)" % flame_surfaces(camp_materials))

	# No collider. Not one, anywhere in the dressing.
	var solids := solids_under(dressing)
	check(solids.is_empty(), "the camp dressing adds no collider (%d found)" % solids.size())

	# Bounds: the dressing's declared yard is the scene's yard, the declared floor
	# is bigger than the walls (rule 12), and no prop orbits off the ground.
	check(is_equal_approx(CampDressingScript.YARD_HALF_WIDTH, CageScript.YARD_HALF_WIDTH)
		and is_equal_approx(CampDressingScript.YARD_FRONT, CageScript.YARD_FRONT)
		and is_equal_approx(CampDressingScript.YARD_BACK, CageScript.YARD_BACK),
		"the dressing's yard mirrors cage_escape.gd's YARD_*")
	check(CampDressingScript.FLOOR_HALF_WIDTH > CageScript.YARD_HALF_WIDTH
		and CampDressingScript.FLOOR_FRONT < CageScript.YARD_FRONT
		and CampDressingScript.FLOOR_BACK > CageScript.YARD_BACK,
		"the declared floor is bigger than the walls, always")

	var props := props_of(dressing)
	check(props.size() >= 30, "the camp dressing records %d props for the clearance check" % props.size())
	assert_in_zone(props, "camp", CageScript.YARD_HALF_WIDTH, CageScript.YARD_FRONT,
		CageScript.YARD_BACK, CampDressingScript.FLOOR_HALF_WIDTH,
		CampDressingScript.FLOOR_FRONT, CampDressingScript.FLOOR_BACK)

	# Real geometry, not just records: every merged mesh of every yard group has
	# to sit inside the walled yard, and the gibbets outside it.
	var inside_groups := ["CageHardware", "Banners", "AltarDressing", "Braziers", "GroundScatter"]
	var outside_yard := 0
	var half := float(CageScript.YARD_HALF_WIDTH)
	var front := float(CageScript.YARD_FRONT)
	var back := float(CageScript.YARD_BACK)
	for label in inside_groups:
		for mesh_instance in meshes_under(dressing.get_node_or_null(label)):
			var box := world_aabb(mesh_instance)
			var inside: bool = box.position.x >= -half - 0.05 and box.end.x <= half + 0.05
			inside = inside and box.position.z >= front - 0.05 and box.end.z <= back + 0.05
			if not inside:
				outside_yard += 1
	check(outside_yard == 0, "every yard prop's geometry is inside the palisade (%d outside)" % outside_yard)
	var off_floor := 0
	for mesh_instance in meshes_under(dressing.get_node_or_null("Gibbets")):
		var box := world_aabb(mesh_instance)
		var on_floor: bool = box.end.z < front and box.position.z > CampDressingScript.FLOOR_FRONT
		on_floor = on_floor and absf(box.position.x) < CampDressingScript.FLOOR_HALF_WIDTH
		if not on_floor:
			off_floor += 1
	check(off_floor == 0, "the gibbets stand outside the walls but on the floor (%d off)" % off_floor)

	# Nobody's spawn, no `G` point, no drop is under a prop.
	var points: Array = []
	for post in CageScript.CAGE_POSTS:
		points.append({"what": "a cage", "point": post, "reach": float(CageScript.CAGE_CLAMP_RADIUS)})
	points.append({"what": "the gate", "point": CageScript.GATE_POINT, "reach": float(CageScript.GATE_RADIUS)})
	for entry in CageScript.GATE_WATCHERS:
		points.append({"what": "a gate watcher's post", "point": entry["post"], "reach": 0.5})
	for post in CageScript.REINFORCE_POSTS:
		points.append({"what": "a reinforcement post", "point": post, "reach": 0.0})
	for drop in CageScript.WEAPON_DROPS:
		points.append({"what": "a weapon drop", "point": drop[1], "reach": 0.4})
	assert_clear(props, points, "camp")

	print("WARBAND_ART_CAMP groups=%d meshes=%d props=%d materials=%d" % [
		dressing.get_child_count(), camp_meshes.size(), props.size(), camp_materials.size()])

	camp.queue_free()
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
	var labels: Array = []
	if signpost != null:
		for child in signpost.get_children():
			for label_node in child.get_children():
				if label_node is Label3D:
					labels.append(label_node)
	check(labels.size() == TownDressingScript.SIGN_BOARDS.size(),
		"the fingerpost carries %d lettered boards" % labels.size())
	var lettered := 0
	for board_index in TownDressingScript.SIGN_BOARDS.size():
		if signpost == null:
			break
		var board := signpost.get_node_or_null("Board%d" % (board_index + 1)) as Node3D
		check(board != null, "finger board %d exists" % (board_index + 1))
		if board == null:
			continue
		var board_label := board.get_node_or_null("BoardText") as Label3D
		check(board_label != null and not board_label.text.is_empty(),
			"finger board %d carries real text" % (board_index + 1))
		if board_label != null:
			check(board_label.text == String(TownDressingScript.SIGN_BOARDS[board_index]["text"]),
				"finger board %d reads \"%s\"" % [board_index + 1, board_label.text])
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
	check(lettered == labels.size(), "every lettered board is direction-correct")

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
	points.append({"what": "the expedition gate", "point": TownScript.GATE_POINT,
		"reach": float(town.gate.open_radius)})
	assert_clear(props, points, "town")

	print("WARBAND_ART_TOWN groups=%d meshes=%d props=%d materials=%d" % [
		dressing.get_child_count(), town_meshes.size(), props.size(), town_materials.size()])

	town.queue_free()
	await process_frame
