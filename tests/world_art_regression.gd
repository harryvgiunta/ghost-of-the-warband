extends SceneTree
## Verifies the modular world-art pipeline in the real scenes: textured panorama
## sky, shader terrain, chunked textured trees/grass with instance tints and
## distance ranges, arena cover preservation, deterministic tree variants, and
## scenery budgets. Visual quality still requires rendered inspection.

const WorldStyle = preload("res://scripts/world/world_style.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const ArenaWorld = preload("res://scripts/arena_world.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _wait_ready(node: Node, flag: String, timeout_ms: int = 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if node.get(flag) != null:
			return true
		await process_frame
	return false

func _multimeshes(root: Node, prefix: String) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child in root.get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with(prefix):
			found.append(child)
		found.append_array(_multimeshes(child, prefix))
	return found

func _triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	return mesh.get_faces().size() / 3

func _variant_vertices(mesh: Mesh) -> PackedVector3Array:
	if mesh == null:
		return PackedVector3Array()
	var arrays: Array = mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]

func _check_sky(root: Node3D, label: String) -> void:
	var environment: Environment = null
	for child in root.get_children():
		if child is WorldEnvironment:
			environment = (child as WorldEnvironment).environment
			break
	check(environment != null, label + " must build a WorldEnvironment")
	if environment == null:
		return
	check(environment.background_mode == Environment.BG_SKY, label + " must use a sky background")
	check(environment.sky != null, label + " must own a Sky")
	if environment.sky == null:
		return
	check(environment.sky.sky_material is PanoramaSkyMaterial, label + " must use a panorama, not procedural balls")
	if environment.sky.sky_material is PanoramaSkyMaterial:
		var panorama := (environment.sky.sky_material as PanoramaSkyMaterial).panorama
		check(panorama != null, label + " panorama texture must load")
		if panorama != null:
			check(panorama.get_width() == 4096 and panorama.get_height() == 2048,
				label + " panorama must be the authored 4096x2048 equirect")
	check(environment.tonemap_mode == Environment.TONE_MAPPER_FILMIC, label + " must use the filmic grade")
	check(environment.fog_enabled or environment.fog_density <= 0.0, label + " fog configuration must be explicit")

func _check_tree_variants() -> void:
	var style := WorldStyle.frontier()
	check(style.trees.size() >= 5, "The species library must expose at least five tree variants")
	var species: Dictionary = style.species_by_id("ironoak")
	check(not species.is_empty(), "ironoak species must exist")
	var first: Array = TreeKit.build_variants(species, 424242)
	var second: Array = TreeKit.build_variants(species, 424242)
	var different: Array = TreeKit.build_variants(species, 99001)
	check(first.size() == int(species.get("variants", 3)), "variant count comes from the species data")
	check(first.size() > 1, "broadleaf species must have multiple shapes")
	for index in first.size():
		var a: Dictionary = first[index]
		var b: Dictionary = second[index]
		check(a["trunk"] != null and a["leaves"] != null, "tree variant must contain trunk and foliage meshes")
		check(_triangle_count(a["trunk"]) + _triangle_count(a["leaves"]) <= 1400,
			"broadleaf variant %d exceeds its triangle budget" % index)
		var bounds: AABB = (a["trunk"] as Mesh).get_aabb().merge((a["leaves"] as Mesh).get_aabb())
		check(bounds.size.y > 5.0 and is_finite(bounds.size.x), "tree variant must have a sane vertical AABB")
		check((a["trunk"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != null,
			"trunk mesh must carry bark UVs")
		check((a["leaves"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] != null,
			"leaf cards must carry wind UV2")
		check(_triangle_count(a["trunk"]) == _triangle_count(b["trunk"]),
			"same seed must reproduce the same trunk")
		check(_triangle_count(a["trunk"]) == _triangle_count(different[index]["trunk"]) or
			_variant_vertices(a["trunk"]) != _variant_vertices(different[index]["trunk"]),
			"a different seed must produce a different silhouette")
		# Mesh equality is not enough; compare the actual first vertex run.
		check(_variant_vertices(a["trunk"]) == _variant_vertices(b["trunk"]),
			"same seed must reproduce identical vertex data")

func _check_texture_library() -> void:
	for id in ["terrain_grass", "terrain_litter", "terrain_dirt", "terrain_rock", "terrain_noise",
			"terrain_macro", "rock", "bark_oak", "bark_pine", "bark_birch", "bark_dead",
			"leaves_broadleaf", "leaves_amber", "leaves_birch", "needles_pine", "grass_meadow",
			"flowers", "fern", "wood_planks", "timber", "plaster", "roof_shingles", "stone_blocks",
			"sky_frontier"]:
		var texture := TextureLibrary.texture(id)
		check(texture != null and texture.get_width() > 0, "texture '%s' must load" % id)
	check(TextureLibrary.texture_count() >= 20, "the world must load the full authored texture set")
	check(TextureLibrary.texture("leaves_broadleaf").get_height() == 512, "foliage atlas must be 512x512")
	check(TextureLibrary.texture("terrain_grass").get_height() == 512, "terrain detail must be 512x512")
	var rock_material := TextureLibrary.rock_material()
	check(rock_material.uv1_triplanar and rock_material.albedo_texture != null,
		"boulders must use a triplanar textured material")
	var bark := TextureLibrary.bark_material("bark_oak")
	check(bark.albedo_texture != null and bark.vertex_color_use_as_albedo,
		"bark must be textured and instance-tintable")

func _check_frontier() -> void:
	var start := Time.get_ticks_msec()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var ready := await _wait_ready(game, "world", 3000)
	check(ready, "frontier must finish building")
	if not ready:
		game.queue_free()
		return
	var frontier = game.world
	var build_ms := Time.get_ticks_msec() - start
	print("WORLD_ART frontier_build_ms=", build_ms, " stats=", frontier.generation_stats)
	check(build_ms < 12000, "frontier generation must stay inside its load budget")
	var stats: Dictionary = frontier.generation_stats
	check(int(stats.get("trees", 0)) >= 500, "frontier needs a real forest")
	check(int(stats.get("tree_variants", 0)) >= 15, "frontier must scatter multiple shapes per species")
	check(int(stats.get("backdrop_trees", 0)) > 100, "horizon treeline must be populated")
	check(int(stats.get("grass_instances", 0)) >= 15000, "frontier grass must be dense, not token scatter")
	check(int(stats.get("flower_instances", 0)) > 300 and int(stats.get("fern_instances", 0)) > 200,
		"ground cover must include flowers and ferns")
	check(String(stats.get("world_style", "")) == "frontier", "frontier must use the frontier style")
	_check_sky(frontier, "frontier")
	# Terrain: shader material, world-space textures, dirt weights in vertex alpha.
	var terrain: MeshInstance3D = null
	for child in frontier.get_children():
		if child is MeshInstance3D and String(child.name) == "ContinuousFrontierTerrain":
			terrain = child
			break
	check(terrain != null, "the frontier terrain mesh must exist")
	if terrain != null:
		check(terrain.material_override is ShaderMaterial, "terrain must render through the splat shader")
		var arrays: Array = terrain.mesh.surface_get_arrays(0)
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var min_alpha := 1.0
		var max_alpha := 0.0
		for colour in colours:
			min_alpha = minf(min_alpha, colour.a)
			max_alpha = maxf(max_alpha, colour.a)
		check(min_alpha < 0.05 and max_alpha > 0.9, "terrain vertex alpha must encode grass and path weights")
		check(arrays[Mesh.ARRAY_INDEX].size() > 20000, "terrain must keep its continuous mesh")
	# Tree and grass chunks.
	var trunks := _multimeshes(frontier, "TreeTrunk_")
	var leaves := _multimeshes(frontier, "TreeLeaves_")
	var grass := _multimeshes(frontier, "Grass_")
	check(trunks.size() > 20, "trees must be chunked, not one world-sized MultiMesh")
	check(leaves.size() > 20, "leaf cards must be chunked alongside trunks")
	check(grass.size() > 20, "grass must be chunked")
	var trunk_instances := 0
	for node in trunks:
		trunk_instances += node.multimesh.instance_count
		check(node.multimesh.use_colors, "tree instances must carry per-tree tints")
		check(node.multimesh.custom_aabb.size.length() > 0.0, "chunk AABBs must be explicit")
		check(node.multimesh.get_instance_transform(0).origin.is_finite(), "tree transforms must be finite")
	check(absf(float(trunk_instances) - float(stats.get("trees", 0))) < 1.0,
		"every tree must be present in exactly one trunk batch")
	var grass_instances := 0
	for node in grass:
		grass_instances += node.multimesh.instance_count
		check(node.visibility_range_end > 0.0, "grass chunks need a visibility range")
		check(node.visibility_range_end <= 90.0, "grass must cull beyond the playable detail ring")
		check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"grass must not cast shadows")
		check(node.multimesh.use_colors, "grass must use instance tints")
		if node.material_override is ShaderMaterial:
			var fade: float = (node.material_override as ShaderMaterial).get_shader_parameter("fade_end")
			check(absf(fade - node.visibility_range_end) < 0.6,
				"grass shader fade must end at the chunk visibility range")
	check(absf(float(grass_instances) - float(stats.get("grass_instances", 0))) < 1.0,
		"grass batches must account for every clump")
	var flowers := _multimeshes(frontier, "Flowers")
	var ferns := _multimeshes(frontier, "Ferns")
	check(not flowers.is_empty() and not ferns.is_empty(), "flowers and ferns must be scattered")
	var pebbles := _multimeshes(frontier, "Pebbles")
	check(not pebbles.is_empty(), "pebbles must dress the paths")
	var boulders := _multimeshes(frontier, "Boulder_")
	check(not boulders.is_empty(), "boulders must use the batched textured rock")
	_check_stone(boulders, stats)
	# Gameplay data is updated for the in-game town, not removed.
	check(frontier.interactables.size() == 10, "camp, three keepers, stash, portal, delve and three waystones are interactive")
	check(frontier.enemy_spawns.size() == 36, "all enemy spawns must survive the art pass")
	check(frontier.map_paths.size() == 7 and frontier.landmarks.size() == 8,
		"map data tracks the town, the delve, the trail and the village path")
	check(frontier.player_spawn.distance_to(Vector3(0, frontier.terrain_height(0, 47), 47)) < 0.02,
		"the new journey spawns at the town gate")
	await _check_camp(frontier)
	game.queue_free()
	await process_frame

## The Unholy Forest camp: authored surfaces, a handful of child-sized stick
## shelters hidden in the trees, charms on those trees, and a fire in the middle.
## Structure only - the look needs rendered inspection.
func _check_camp(frontier) -> void:
	var stats: Dictionary = frontier.generation_stats
	# one physics step so the camp and village colliders reach the broadphase
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = frontier.get_world_3d().direct_space_state
	var probe := CapsuleShape3D.new()
	probe.radius = 0.34
	probe.height = 1.75
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 1
	query.exclude = []
	for id in ["thatch", "hide", "bone", "flame"]:
		var map := TextureLibrary.texture(id)
		check(map != null and map.get_width() > 0, "camp surface '%s' must load" % id)
	check(TextureLibrary.texture("flame").get_width() == 512
		and TextureLibrary.cell_count("flame") == 4, "the flame atlas must carry four tongues")
	for kind in ["thatch", "hide", "bone"]:
		var material := TextureLibrary.building_material(kind)
		check(material.albedo_texture != null and material.normal_texture != null,
			"camp surface '%s' must be textured with a normal map" % kind)
	check(TextureLibrary.granite_material(Color("8a8070")).uv1_world_triplanar,
		"camp stone must be world-triplanar granite")
	var flame := TextureLibrary.flame_material()
	check(flame.shader != null and flame.get_shader_parameter("albedo_texture") != null,
		"the camp fire must run the flame shader")
	# The live fire: cards with their own baked phase, embers, and a lamp that
	# wanders instead of sitting at a constant energy.
	var fire_mesh := frontier.get_node_or_null("CampFire/CampFire") as MeshInstance3D
	check(fire_mesh != null, "the camp fire must keep its merged mesh")
	var flame_surface := -1
	if fire_mesh != null and fire_mesh.mesh != null:
		for index in range(fire_mesh.mesh.get_surface_count()):
			if fire_mesh.mesh.surface_get_material(index) == flame:
				flame_surface = index
				break
	check(flame_surface >= 0, "the camp fire must author its flame cards on the flame material")
	if flame_surface >= 0:
		var flame_arrays: Array = fire_mesh.mesh.surface_get_arrays(flame_surface)
		var phases: PackedColorArray = flame_arrays[Mesh.ARRAY_COLOR]
		check(phases.size() >= 36, "the fire must build its full ring of cards (%d vertices)" % phases.size())
		var distinct := {}
		for colour in phases:
			distinct[colour.to_rgba32()] = true
		check(distinct.size() >= 5, "every flame card must carry its own phase (%d)" % distinct.size())
	check(frontier.get_node_or_null("CampFire/FireEmbers") is CPUParticles3D,
		"the camp fire must throw embers")
	check(frontier.get_node_or_null("CampFire/CampFireLight") is FireFlicker,
		"the camp fire lamp must breathe with the flame")
	# the camp exists, and it is a camp, not a settlement
	check(frontier.get_node_or_null("CampFire/CampFireLight") is OmniLight3D,
		"the camp fire must light the camp")
	for node_name in ["CampDoodads", "CampTreeCharms", "TrailDoodads", "CampBoneArch",
			"CampCharmWeb0", "CampWickerEffigy", "CampRagTree0", "TrailHeadArch",
			"TrailRagTree0"]:
		check(frontier.get_node_or_null(node_name) != null, node_name + " must exist")
	check(int(stats.get("camp_shelters", 0)) == 6, "the camp has six shelters in clusters")
	check(int(stats.get("trail_marks", 0)) == 8, "the trail carries eight marks of witch work")
	check(int(stats.get("camp_hangers", 0)) >= 180,
		"the camp must hang its charms everywhere (%d)" % int(stats.get("camp_hangers", 0)))
	check(int(stats.get("camp_charm_trees", 0)) >= 40,
		"the trees at the camp must carry charms (%d)" % int(stats.get("camp_charm_trees", 0)))
	# the camp is a trek away, not a shed behind the keepers
	var camp_point := Vector2(-100.0, -22.0)
	var from_town: float = camp_point.distance_to(Vector2(0.0, 32.0))
	check(from_town > 90.0, "the camp must sit deep in the woods (%.0f m out)" % from_town)
	check(frontier.region_at(Vector3(camp_point.x, 4.0, camp_point.y)) == "The Wardens' Camp",
		"the camp must be its own region")
	var camp_landmarks := 0
	for entry: Dictionary in frontier.landmarks:
		if String(entry.get("name", "")) == "The Wardens' Camp":
			camp_landmarks += 1
	check(camp_landmarks == 1, "the camp must appear on the map")
	# Gallowgarth: the wardens' village, out on its own footpath in the north-east
	for node_name in ["GallowgarthPalisade", "GallowgarthGate", "GallowgarthFirepit",
			"GallowgarthOffering", "GallowgarthDoodads", "GallowgarthEffigy",
			"GallowgarthFrame", "WardenHut0", "WardenHut2",
			"WattleHouse0", "WattleHouse2", "WardenTotem0", "WardenTotem2"]:
		check(frontier.get_node_or_null(node_name) != null, node_name + " must exist")
	check(int(stats.get("village_stakes", 0)) >= 120,
		"the village needs a real stake palisade (%d)" % int(stats.get("village_stakes", 0)))
	check(int(stats.get("village_huts", 0)) == 3 and int(stats.get("village_round_huts", 0)) == 3,
		"the village has three stick longhouses and three round huts")
	check(int(stats.get("village_hangers", 0)) >= 5,
		"the village hangs its charms (%d)" % int(stats.get("village_hangers", 0)))
	var village := Vector2(58.0, 22.0)
	check(village.distance_to(Vector2(0.0, 32.0)) > 40.0, "the village must sit out in the woods")
	check(frontier.region_at(Vector3(village.x, 6.6, village.y)) == "Gallowgarth",
		"the village must be its own region")
	var village_landmarks := 0
	for entry: Dictionary in frontier.landmarks:
		if String(entry.get("name", "")) == "Gallowgarth":
			village_landmarks += 1
	check(village_landmarks == 1, "the village must appear on the map")
	# its gate line and fire ground are walkable, the fence is not
	var gate_at := village + Vector2(sin(-3.0 * PI / 4.0), cos(-3.0 * PI / 4.0)) * 15.0
	query.transform = Transform3D(Basis(),
		Vector3(gate_at.x, frontier.terrain_height(gate_at.x, gate_at.y) + 1.05, gate_at.y))
	check(space.intersect_shape(query, 1).is_empty(), "the village gate line must stay walkable")
	query.transform = Transform3D(Basis(),
		Vector3(village.x, frontier.terrain_height(village.x, village.y) + 1.05, village.y))
	check(space.intersect_shape(query, 1).is_empty(), "the village fire ground must stay walkable")
	query.transform = Transform3D(Basis(),
		Vector3(village.x, frontier.terrain_height(village.x, village.y + 15.0) + 1.3, village.y + 15.0))
	check(not space.intersect_shape(query, 1).is_empty(),
		"the village palisade must block the same probe")
	# the castle and the shrine are gone, and their clearings with them
	check(frontier.get_node_or_null("WatchfallFortress") == null, "the Watchfall fortress is gone")
	check(frontier.get_node_or_null("SuncrestShrine") == null, "the Suncrest shrine is gone")
	# small enough that a child built it: no shelter reads as a building
	for i in range(6):
		var shelter: Node = frontier.get_node_or_null("TwigShelter%d" % i)
		check(shelter != null, "shelter %d must stand" % i)
		if shelter == null:
			continue
		var mesh_node: MeshInstance3D = shelter.get_node_or_null("TwigShelterMesh") as MeshInstance3D
		check(mesh_node != null and mesh_node.mesh != null, "shelter %d must keep its mesh" % i)
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var bounds: AABB = mesh_node.mesh.get_aabb()
		check(bounds.size.x <= 4.0 and bounds.size.z <= 3.4,
			"shelter %d must stay small (%.1f x %.1f)" % [i, bounds.size.x, bounds.size.z])
		check(bounds.size.y <= 2.2, "shelter %d must be lower than a doorway" % i)
	check(int(stats.get("bushes", 0)) >= 300,
		"the woods need undergrowth (%d bushes)" % int(stats.get("bushes", 0)))
	# the camp sits in the woodland: trunks stand right there with it
	var trees_at_camp := 0
	var solids: Node = frontier.get_node_or_null("FrontierSolidObstacles")
	if solids != null:
		for shape_node in solids.get_children():
			if not (shape_node is CollisionShape3D):
				continue
			var shape := (shape_node as CollisionShape3D).shape
			if not (shape is CylinderShape3D):
				continue
			var at: Vector3 = (shape_node as CollisionShape3D).position
			if Vector2(at.x, at.z).distance_to(camp_point) < 16.0:
				trees_at_camp += 1
	check(trees_at_camp >= 8, "the camp must sit amongst trees (%d trunks within 16 m)" % trees_at_camp)
	# the fire ground is walkable, and the effigy's stake is solid
	var fire_at := Vector3(camp_point.x, frontier.terrain_height(camp_point.x, camp_point.y) + 1.05,
		camp_point.y)
	query.transform = Transform3D(Basis(), fire_at)
	check(space.intersect_shape(query, 1).is_empty(), "the camp fire ground must stay walkable")
	var stake := Vector3(-104.6, frontier.terrain_height(-104.6, -23.9) + 0.7, -23.9)
	query.transform = Transform3D(Basis(), stake)
	check(not space.intersect_shape(query, 1).is_empty(),
		"the camp probe must detect the effigy's stake")


## Rock variety and bedding: authored silhouettes rather than one repeated
## polygon, each normalised to a metre of half-width, cut on a flat fracture face
## and sized on its own.
func _check_stone(boulders: Array[MultiMeshInstance3D], stats: Dictionary) -> void:
	var meshes := {}
	var total := 0
	for node in boulders:
		var mesh: Mesh = node.multimesh.mesh
		check(mesh != null, "a boulder batch must carry a mesh")
		if mesh == null:
			continue
		var rid := mesh.get_rid()
		if not meshes.has(rid):
			meshes[rid] = true
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			check(not vertices.is_empty(), "a boulder variant must have geometry")
			var half := 0.0
			var low := INF
			for vertex in vertices:
				half = maxf(half, maxf(absf(vertex.x), absf(vertex.z)))
				low = minf(low, vertex.y)
			check(absf(half - 1.0) < 0.06,
				"a boulder variant must be normalised to a 1 m half-extent (%.2f)" % half)
			# A closed, solid mass: the signed tetrahedron sum catches a shell or a
			# mesh that collapsed to plates, which is what a bad deformation does.
			var volume := 0.0
			for index in range(0, vertices.size(), 3):
				volume += vertices[index].dot(vertices[index + 1].cross(vertices[index + 2])) / 6.0
			var box := mesh.get_aabb().size
			check(absf(volume) > 0.2 * box.x * box.y * box.z,
				"a boulder variant must be a solid mass (%.3f m3 inside %.3f)" %
				[absf(volume), box.x * box.y * box.z])
		total += node.multimesh.instance_count
	check(meshes.size() >= 6, "boulders must come from at least six authored silhouettes (%d)" % meshes.size())
	check(total >= 60, "the frontier must dress itself with stone (%d boulders)" % total)
	# MultiMesh instance data lives in the renderer, so headless cannot read the
	# transforms back; the placement records the spread it actually used.
	var span: Vector2 = stats.get("rock_span", Vector2.ZERO)
	check(span.y > span.x * 3.0,
		"boulders must vary in size instead of sharing one scale (%.2f to %.2f)" % [span.x, span.y])


func _check_arena() -> void:
	var arena = ArenaWorld.new()
	root.add_child(arena)
	await process_frame
	await process_frame
	print("WORLD_ART arena_stats=", arena.generation_stats)
	check(arena.LIMIT == 32.0, "arena limit must remain 32 m")
	check(arena.spawn_points.size() == 4, "arena keeps four seats")
	check(arena.spawn_points[0] == Vector3(-22, 0, -22), "arena spawn geometry must not move")
	_check_sky(arena, "arena")
	check(int(arena.generation_stats.get("arena_trees", 0)) == 14, "all 14 real cover trees must be rebuilt")
	check(int(arena.generation_stats.get("grass_instances", 0)) > 2000, "arena floor needs textured grass")
	var tree_bodies := 0
	var cover_shapes := arena.find_children("*", "CollisionShape3D", true, false)
	check(cover_shapes.size() >= 14, "tree and cover collision shapes must remain")
	for child in arena.get_children():
		if child is StaticBody3D and child.position.distance_to(Vector3.ZERO) > 1.0:
			var shape := child.get_child(0) as CollisionShape3D
			if shape != null and shape.shape is CylinderShape3D:
				tree_bodies += 1
				check(is_equal_approx((shape.shape as CylinderShape3D).radius, 0.55), "arena tree cover radius must not change")
				check(is_equal_approx((shape.shape as CylinderShape3D).height, 5.5), "arena tree cover height must not change")
	check(tree_bodies == 14, "all arena cover trees keep their exact colliders")
	var trunks := _multimeshes(arena, "ArenaTreeTrunk_")
	var backdrop := _multimeshes(arena, "ArenaBackdropTrunk_")
	check(not trunks.is_empty(), "arena trees must be textured meshes")
	check(not backdrop.is_empty(), "arena horizon must be dressed outside the walls")
	arena.queue_free()
	await process_frame

func run() -> void:
	_check_tree_variants()
	_check_texture_library()
	await _check_frontier()
	await _check_arena()
	print("WORLD_ART_REGRESSION failures=", failures)
	quit(0 if failures == 0 else 1)
