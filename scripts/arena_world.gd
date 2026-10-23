extends Node3D
## The duel field. Gameplay geometry (LIMIT, spawn points, cover and tree
## collisions) is unchanged; scenery comes from the shared world-art kit.

const Geo = preload("res://scripts/geo.gd")
const WorldStyleKit = preload("res://scripts/world/world_style.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const WorldScatter = preload("res://scripts/world/scatter.gd")
const GrassField = preload("res://scripts/world/grass_field.gd")
const WorldEnvironmentKit = preload("res://scripts/world/environment_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const LIMIT := 32.0
const ARENA_TREE_CHUNK := 24.0
const GRASS_SEED := 44119
const ARENA_TREE_SEED := 81043
const BACKDROP_TREES := 150
const TREE_RADIUS := 0.55
const TREE_HEIGHT := 5.5

var spawn_points: Array[Vector3] = [Vector3(-22, 0, -22), Vector3(22, 0, 22), Vector3(-22, 0, 22), Vector3(22, 0, -22)]
var generation_stats: Dictionary = {}
var style: WorldStyleKit
var _tree_locations: Array[Vector3] = []
var _cover_boxes: Array[Vector3] = []

func _ready() -> void:
	style = WorldStyleKit.arena()
	var prop_tints: Dictionary = style.props.get("tints", {})
	var wood := TextureLibrary.building_material("wood", prop_tints.get("wood", Color.WHITE))
	var stone := TextureLibrary.building_material("stone", prop_tints.get("stone", Color.WHITE))
	var ground := TextureLibrary.ground_material(style)
	var built: Dictionary = WorldEnvironmentKit.build(self, style)
	generation_stats["sun"] = built.get("sun") != null

	_solid_box(Vector3(66, 0.6, 66), Vector3(0, -0.3, 0), ground)
	# Surrounding field closes the horizon; the 66 m duel floor keeps its collider.
	var field := Geo.box(self, Vector3(180, 0.3, 180), Vector3(0, -0.65, 0), ground)
	field.name = "ArenaOuterField"
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(66, 1.4, 0.7), Vector3(0, 0.7, side * 32.5), stone)
		_solid_box(Vector3(0.7, 1.4, 64), Vector3(side * 32.5, 0.7, 0), stone)
		for index in 17:
			_solid_box(Vector3(0.32, 2.1, 0.32), Vector3(-32 + index * 4, 1.05, side * 32.5), wood)
	var colors := [Color("70c4cb"), Color("e4a75f"), Color("bfa1dc"), Color("86c48a")]
	for index in 4:
		Geo.cylinder(self, 2, 2, 0.025, spawn_points[index] + Vector3(0, 0.012, 0), Geo.material(colors[index].darkened(0.3)), 32)
		var label := Label3D.new()
		label.text = str(index + 1)
		label.position = spawn_points[index] + Vector3(0, 0.04, 0)
		label.rotation.x = -PI / 2
		label.font_size = 90
		label.pixel_size = 0.014
		add_child(label)

	_build_arena_trees()
	_build_cover(stone, wood)
	_build_grass()
	_build_backdrop()
	generation_stats["texture_count"] = TextureLibrary.texture_count()
	generation_stats["world_style"] = style.id


## The 14 real cover trees keep the exact colliders used by the arena cover and
## network regressions; only their presentation is replaced.
func _build_arena_trees() -> void:
	_tree_locations = [
		Vector3(-9,0,-7), Vector3(9,0,7), Vector3(-8,0,9), Vector3(8,0,-9), Vector3(-18,0,1), Vector3(18,0,-1),
		Vector3(-24,0,8), Vector3(24,0,-8), Vector3(-12,0,-24), Vector3(12,0,24),
		Vector3(-28,0,-4), Vector3(28,0,4), Vector3(0,0,27), Vector3(0,0,-27),
	]
	var species: Dictionary = style.species_by_id("ironoak")
	if species.is_empty():
		return
	var variants: Array = TreeKit.build_variants(species, ARENA_TREE_SEED)
	var trunk_buckets: Array = []
	var leaf_buckets: Array = []
	for index in variants.size():
		trunk_buckets.append([] as Array[Dictionary])
		leaf_buckets.append([] as Array[Dictionary])
	for index in range(_tree_locations.size()):
		var location: Vector3 = _tree_locations[index]
		var variant_index := index % variants.size()
		var variant: Dictionary = variants[variant_index]
		var scale_at := 0.92 + float(index % 5) * 0.045
		var xform := Transform3D(Basis(Vector3.UP, float(index) * 1.37).scaled(Vector3.ONE * scale_at), location)
		(trunk_buckets[variant_index] as Array[Dictionary]).append({
			"transform": xform,
			"color": species["bark_tints"][index % species["bark_tints"].size()],
		})
		(leaf_buckets[variant_index] as Array[Dictionary]).append({
			"transform": xform,
			"color": species["tints"][index % species["tints"].size()],
		})
		var trunk := StaticBody3D.new()
		trunk.position = location
		trunk.collision_layer = 1
		trunk.collision_mask = 0
		add_child(trunk)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = TREE_RADIUS
		shape.height = TREE_HEIGHT
		collision.shape = shape
		collision.position.y = TREE_HEIGHT * 0.5
		trunk.add_child(collision)
	for index in variants.size():
		var variant: Dictionary = variants[index]
		WorldScatter.batch(self, "ArenaTreeTrunk_%d" % index, variant["trunk"],
			TextureLibrary.bark_material(String(variant["bark"])), trunk_buckets[index], ARENA_TREE_CHUNK,
			{"cast_shadow": true})
		if variant.get("leaves") != null:
			WorldScatter.batch(self, "ArenaTreeLeaves_%d" % index, variant["leaves"],
				TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]), variant["wind"]),
				leaf_buckets[index], ARENA_TREE_CHUNK, {"cast_shadow": true})
	generation_stats["arena_trees"] = _tree_locations.size()


func _build_cover(stone: Material, wood: Material) -> void:
	_cover_boxes = [
		Vector3(-11,0,2), Vector3(11,0,-2), Vector3(0,0,-13), Vector3(0,0,13),
		Vector3(-20,0,-6), Vector3(20,0,6), Vector3(-6,0,20), Vector3(6,0,-20),
		Vector3(-26,0,18), Vector3(26,0,-18),
	]
	for location: Vector3 in _cover_boxes:
		_solid_box(Vector3(3.2, 1.4, 1.5), location + Vector3(0,0.7,0), stone)
		Geo.box(self, Vector3(3.35,0.12,1.65), location + Vector3(0,1.42,0), wood)


func _build_grass() -> void:
	var counts: Dictionary = GrassField.build(self, style, _arena_ground, _grass_reserved, GRASS_SEED)
	generation_stats["grass_instances"] = int(counts.get("grass", 0))
	generation_stats["ground_cover_chunks"] = int(counts.get("chunks", 0))


func _build_backdrop() -> void:
	# Trees beyond the walls close the sightline without adding colliders.
	var species: Dictionary = style.species_by_id("briar_pine")
	if species.is_empty():
		return
	var variants: Array = TreeKit.build_variants(species, ARENA_TREE_SEED + 17)
	var rng := RandomNumberGenerator.new()
	rng.seed = ARENA_TREE_SEED + 91
	var buckets: Array = []
	for index in variants.size():
		buckets.append([] as Array[Dictionary])
	for index in range(BACKDROP_TREES):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(35.0, 62.0)
		var point := Vector3(cos(angle) * distance, -0.5, sin(angle) * distance)
		var variant_index := rng.randi_range(0, variants.size() - 1)
		var scale_at := rng.randf_range(1.0, 1.45)
		(buckets[variant_index] as Array[Dictionary]).append({
			"transform": Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_at), point),
			"color": species["tints"][rng.randi_range(0, species["tints"].size() - 1)],
		})
	for index in variants.size():
		var variant: Dictionary = variants[index]
		WorldScatter.batch(self, "ArenaBackdropTrunk_%d" % index, variant["trunk"],
			TextureLibrary.bark_material(String(variant["bark"])), buckets[index], 32.0,
			{"cast_shadow": false})
		if variant.get("leaves") != null:
			WorldScatter.batch(self, "ArenaBackdropLeaves_%d" % index, variant["leaves"],
				TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]), variant["wind"]),
				buckets[index], 32.0, {"cast_shadow": false})
	generation_stats["backdrop_trees"] = BACKDROP_TREES


func _arena_ground(point: Vector2) -> Vector3:
	var inside := absf(point.x) <= 33.0 and absf(point.y) <= 33.0
	return Vector3(point.x, 0.0 if inside else -0.5, point.y)


func _grass_reserved(point: Vector2) -> bool:
	if absf(point.x) > 30.5 or absf(point.y) > 30.5:
		return true
	for spawn in spawn_points:
		if point.distance_to(Vector2(spawn.x, spawn.z)) < 2.2:
			return true
	for location in _tree_locations:
		if point.distance_to(Vector2(location.x, location.z)) < 0.95:
			return true
	for location in _cover_boxes:
		if point.distance_to(Vector2(location.x, location.z)) < 2.2:
			return true
	return false


func _solid_box(dimensions: Vector3, point: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	Geo.box(body, dimensions, Vector3.ZERO, material)
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
