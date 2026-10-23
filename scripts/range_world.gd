extends Node3D
## Seamless frontier: all public positions are world-space with this root at identity.

const Geo = preload("res://scripts/geo.gd")
const WORLD_LIMIT := 145.0
const GRID_STEP := 2.0
const GRID_CELLS := 145
const GRID_SIDE := GRID_CELLS + 1
const BRIDGE_HEIGHT := 3.0

var player_spawn: Vector3 = Vector3(0.0, 3.0, 35.0)
var enemy_spawns: Array[Dictionary] = []
var interactables: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var map_paths: Array[PackedVector3Array] = []
var generation_stats: Dictionary = {}

# The Y component is the designed route elevation, not a sampled terrain value.
# Shared junctions have identical grades; the steepest designed route is under 18 degrees.
var _routes: Array[PackedVector3Array] = [
	PackedVector3Array([Vector3(0, 3, 48), Vector3(0, 3, 35), Vector3(0, 3, 4), Vector3(12, 3, -10), Vector3(32, 3, -10), Vector3(55, 5, -35), Vector3(55, 7, -60)]),
	PackedVector3Array([Vector3(0, 3, 4), Vector3(-30, 3, -8), Vector3(-55, 4, -25), Vector3(-55, 7, -60), Vector3(-35, 13, -85), Vector3(-15, 18, -100)]),
	PackedVector3Array([Vector3(55, 7, -60), Vector3(55, 7, -81), Vector3(30, 11, -85), Vector3(-15, 18, -100)]),
	PackedVector3Array([Vector3(-15, 3, 37), Vector3(0, 3, 35), Vector3(15, 3, 37)]),
	PackedVector3Array([Vector3(-15, 3, 21), Vector3(0, 3, 22), Vector3(15, 3, 21)])
]
var _heights := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _solids: StaticBody3D
var _wood: StandardMaterial3D
var _timber: StandardMaterial3D
var _plaster: StandardMaterial3D
var _roof: StandardMaterial3D
var _stone: StandardMaterial3D
var _gold: StandardMaterial3D
var _cyan: StandardMaterial3D
var _activated: Dictionary = {}


func _ready() -> void:
	_rng.seed = 714209
	_wood = Geo.material(Color("836044"))
	_timber = Geo.material(Color("493e32"))
	_plaster = Geo.material(Color("ddd0a5"))
	_roof = Geo.material(Color("795045"))
	_stone = Geo.material(Color("858a7c"))
	_gold = Geo.material(Color("b99b55"), 0.3)
	_cyan = Geo.material(Color("558e92"), 0.2)
	_solids = StaticBody3D.new()
	_solids.name = "FrontierSolidObstacles"
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	add_child(_solids)
	_build_lighting()
	_build_terrain()
	_build_map_data()
	_build_village()
	_build_water_and_bridge()
	_build_fort()
	_build_shrine()
	_build_waystone("forest", "Heartwood Waystone", Vector2(-55, -25))
	_build_waystone("ruins", "Watchfall Waystone", Vector2(55, -60))
	_build_waystone("ridge", "Suncrest Waystone", Vector2(-15, -100))
	_build_enemy_spawns()
	_build_woodland()
	_build_rocks()
	_build_signposts()
	generation_stats["terrain_vertices"] = GRID_SIDE * GRID_SIDE
	generation_stats["terrain_triangles"] = GRID_CELLS * GRID_CELLS * 2
	generation_stats["nodes"] = _count_nodes(self)
	generation_stats["obstacle_shapes"] = _solids.get_child_count()
	generation_stats["paths"] = map_paths.size()
	generation_stats["enemies"] = enemy_spawns.size()


func _build_lighting() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("789fab")
	sky_material.sky_horizon_color = Color("dfdbc0")
	sky_material.ground_bottom_color = Color("637057")
	sky_material.ground_horizon_color = Color("c5cbb2")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bed1d1")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("c5d0bd")
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.0022
	environment.fog_sky_affect = 0.12
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "WarmFrontierSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("ffe2b3")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_bias = 0.04
	add_child(sun)


func _route_sample(x: float, z: float) -> Vector2:
	var query := Vector2(x, z)
	var nearest: float = INF
	var grade: float = 3.0
	for route in _routes:
		for i in range(route.size() - 1):
			var a := Vector2(route[i].x, route[i].z)
			var b := Vector2(route[i + 1].x, route[i + 1].z)
			var span := b - a
			var along: float = clampf((query - a).dot(span) / span.length_squared(), 0.0, 1.0)
			var distance: float = query.distance_to(a + span * along)
			if distance < nearest:
				nearest = distance
				grade = lerpf(route[i].y, route[i + 1].y, along)
	return Vector2(nearest, grade)


func _raw_height(x: float, z: float) -> float:
	var height: float = 3.0 + sin(x * 0.037) * 2.4 + sin(z * 0.043 + x * 0.018) * 2.0
	height += 13.0 * exp(-((x + 18.0) * (x + 18.0) / 3000.0 + (z + 104.0) * (z + 104.0) / 1800.0))
	height += 5.5 * exp(-((x - 87.0) * (x - 87.0) / 1000.0 + (z + 45.0) * (z + 45.0) / 2600.0))
	var route := _route_sample(x, z)
	height = lerpf(height, route.y, 1.0 - smoothstep(3.8, 10.0, route.x))
	# Broad, flat usable clearings, rather than foundations hovering over hills.
	for clearing in [Vector4(0, 32, 3, 26), Vector4(-55, -25, 4, 11), Vector4(55, -60, 7, 20), Vector4(-15, -100, 18, 10)]:
		var distance: float = Vector2(x - clearing.x, z - clearing.y).length()
		height = lerpf(height, clearing.z, 1.0 - smoothstep(clearing.w, clearing.w + 9.0, distance))
	# A real depression under the pond and bridge. Roads stop at the bridge abutments.
	var pond_radius: float = Vector2((x - 22.0) / 10.0, (z + 10.0) / 34.0).length()
	height = lerpf(height, -1.2, 1.0 - smoothstep(0.62, 1.0, pond_radius))
	# Continuous steep foothills enclose the finite zone without floating scenery walls.
	var edge: float = maxf(absf(x), absf(z))
	height += smoothstep(114.0, 145.0, edge) * (42.0 + 5.0 * sin(x * 0.08) * cos(z * 0.065))
	return height


func _grid_height(ix: int, iz: int) -> float:
	if not _heights.is_empty():
		return _heights[iz * GRID_SIDE + ix]
	return _raw_height(-WORLD_LIMIT + float(ix) * GRID_STEP, -WORLD_LIMIT + float(iz) * GRID_STEP)


func terrain_height(x: float, z: float) -> float:
	# Barycentric interpolation uses exactly the diagonal of the rendered/collision mesh.
	var gx: float = clampf((x + WORLD_LIMIT) / GRID_STEP, 0.0, float(GRID_CELLS))
	var gz: float = clampf((z + WORLD_LIMIT) / GRID_STEP, 0.0, float(GRID_CELLS))
	var ix: int = mini(int(floor(gx)), GRID_CELLS - 1)
	var iz: int = mini(int(floor(gz)), GRID_CELLS - 1)
	var u: float = gx - float(ix)
	var v: float = gz - float(iz)
	var a: float = _grid_height(ix, iz)
	var b: float = _grid_height(ix + 1, iz)
	var c: float = _grid_height(ix, iz + 1)
	var d: float = _grid_height(ix + 1, iz + 1)
	if u + v <= 1.0:
		return a + u * (b - a) + v * (c - a)
	return d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain_height(x, z), z)


func _build_terrain() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	_heights.resize(GRID_SIDE * GRID_SIDE)
	vertices.resize(GRID_SIDE * GRID_SIDE)
	colors.resize(GRID_SIDE * GRID_SIDE)
	for iz in range(GRID_SIDE):
		for ix in range(GRID_SIDE):
			var x: float = -WORLD_LIMIT + float(ix) * GRID_STEP
			var z: float = -WORLD_LIMIT + float(iz) * GRID_STEP
			var height: float = _raw_height(x, z)
			var index: int = iz * GRID_SIDE + ix
			_heights[index] = height
			vertices[index] = Vector3(x, height, z)
			var shade: float = (sin(x * 0.21) * cos(z * 0.18) + 1.0) * 0.5
			var color := Color("657c4e").lerp(Color("89935e"), shade * 0.65)
			if z < -75.0:
				color = color.lerp(Color("a0a184"), clampf((-z - 75.0) / 65.0, 0.0, 0.7))
			var road_distance: float = _route_sample(x, z).x
			color = color.lerp(Color("b5a17a"), 1.0 - smoothstep(1.5, 3.2, road_distance))
			if height < 1.0:
				color = Color("857d60")
			color = color.lerp(Color("747b72"), smoothstep(120.0, 140.0, maxf(absf(x), absf(z))))
			colors[index] = color
	for iz in range(GRID_CELLS):
		for ix in range(GRID_CELLS):
			var a: int = iz * GRID_SIDE + ix
			indices.append_array(PackedInt32Array([a, a + 1, a + GRID_SIDE, a + 1, a + GRID_SIDE + 1, a + GRID_SIDE]))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		var normal: Vector3 = (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := Geo.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	Geo.mesh_node(self, mesh, material).name = "ContinuousFrontierTerrain"
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)


func _build_map_data() -> void:
	player_spawn = _ground(0, 35)
	for entry in [
		["Hearthstead", Vector2(0, 35)], ["Heartwood", Vector2(-55, -25)],
		["Watchfall Ruins", Vector2(55, -60)], ["Suncrest Ridge", Vector2(-15, -100)],
		["Willow Bridge", Vector2(22, -10)]
	]:
		var point: Vector2 = entry[1]
		var location := _ground(point.x, point.y)
		if entry[0] == "Willow Bridge":
			location.y = BRIDGE_HEIGHT
		landmarks.append({"name": String(entry[0]), "position": location})
	for route in _routes:
		var points := PackedVector3Array()
		for i in range(route.size() - 1):
			var count: int = maxi(1, int(ceil(route[i].distance_to(route[i + 1]) / 2.0)))
			for step in range(count):
				var point: Vector3 = route[i].lerp(route[i + 1], float(step) / float(count))
				point.y = terrain_height(point.x, point.z)
				if point.x >= 12.0 and point.x <= 32.0 and absf(point.z + 10.0) < 0.1:
					point.y = BRIDGE_HEIGHT
				points.append(point)
		var end: Vector3 = route[route.size() - 1]
		points.append(_ground(end.x, end.z))
		map_paths.append(points)


func region_at(world_position: Vector3) -> String:
	var p := Vector2(world_position.x, world_position.z)
	if p.distance_to(Vector2(0, 32)) < 29.0:
		return "Hearthstead · Safe Haven"
	if p.distance_to(Vector2(22, -10)) < 18.0:
		return "Willowwater Crossing"
	if p.distance_to(Vector2(55, -60)) < 26.0:
		return "Watchfall Ruins"
	if p.y < -77.0:
		return "Suncrest Ridge"
	if p.x < -25.0:
		return "Heartwood Forest"
	return "The Woodland Frontier"


func _root_at(label: String, point: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.position = point
	add_child(root)
	return root


func _box_collision(parent: Node3D, size: Vector3, point: Vector3, angle: float = 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = parent.transform * Transform3D(Basis(Vector3.UP, angle), point) if parent != self else Transform3D(Basis(Vector3.UP, angle), point)
	_solids.add_child(collision)


func _solid_box(parent: Node3D, size: Vector3, point: Vector3, material: Material, angle: float = 0.0) -> MeshInstance3D:
	var visual := Geo.box(parent, size, point, material)
	visual.rotation.y = angle
	_box_collision(parent, size, point, angle)
	return visual


func _build_village() -> void:
	_build_house(Vector2(-15, 42), 0.0, "ForesterHouse")
	_build_house(Vector2(15, 42), 0.0, "WayfarerInn")
	_build_house(Vector2(-15, 16), PI, "FletcherWorkshop")
	_build_house(Vector2(15, 16), PI, "HearthsteadStore")
	var camp := _root_at("HearthsteadCampfire", _ground(4, 35))
	for i in range(9):
		var angle: float = float(i) * TAU / 9.0
		Geo.sphere(camp, 0.24, Vector3(cos(angle) * 0.85, 0.15, sin(angle) * 0.85), _stone, Vector3(1, 0.65, 1))
	for i in range(3):
		var angle: float = float(i) * PI / 3.0
		Geo.beam(camp, Vector3(cos(angle), 0.21, sin(angle)) * 0.7, Vector3(-cos(angle) * 0.7, 0.3, -sin(angle) * 0.7), 0.12, _timber)
	var flame := Geo.material(Color("ffb74c"))
	flame.emission_enabled = true
	flame.emission = Color("f88a30")
	flame.emission_energy_multiplier = 1.3
	Geo.cylinder(camp, 0.36, 0.0, 1.0, Vector3(0, 0.65, 0), flame, 7)
	Geo.cylinder(camp, 0.23, 0.0, 0.75, Vector3(0.2, 0.55, 0.1), flame, 5)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.4, 0)
	glow.light_color = Color("ffc075")
	glow.light_energy = 1.1
	glow.omni_range = 8.0
	camp.add_child(glow)
	interactables.append({"id": "camp", "name": "Hearthstead Campfire", "kind": "camp", "position": camp.position, "node": camp})
	for x in [-2.5, 2.5]:
		_solid_box(camp, Vector3(0.65, 0.55, 2.0), Vector3(x, 0.275, 0), _wood)
	# An open market canopy frames the square without blocking the northbound road.
	var market := _root_at("OpenMarket", _ground(-7, 28))
	for x in [-2.0, 2.0]:
		for z in [-1.5, 1.5]:
			_solid_box(market, Vector3(0.16, 3, 0.16), Vector3(x, 1.5, z), _timber)
	Geo.box(market, Vector3(4.5, 0.12, 3.5), Vector3(0, 3, 0), Geo.material(Color("688d83")))
	_solid_box(market, Vector3(3.6, 0.9, 0.85), Vector3(0, 0.45, -0.8), _wood)
	for i in range(5):
		Geo.sphere(market, 0.2, Vector3(-1.2 + float(i) * 0.5, 1.04, -0.8), _gold)


func _build_house(point: Vector2, angle: float, label: String) -> void:
	var house := _root_at(label, _ground(point.x, point.y))
	house.rotation.y = angle
	# An actual 1.8m doorway, open interior, and walkable terrain floor.
	_solid_box(house, Vector3(7, 3.7, 0.32), Vector3(0, 1.85, 3), _plaster)
	for x in [-3.5, 3.5]:
		_solid_box(house, Vector3(0.32, 3.7, 6), Vector3(x, 1.85, 0), _plaster)
	for x in [-2.2, 2.2]:
		_solid_box(house, Vector3(2.6, 3.7, 0.32), Vector3(x, 1.85, -3), _plaster)
	_solid_box(house, Vector3(1.8, 1.1, 0.32), Vector3(0, 3.15, -3), _plaster)
	for x in [-3.5, -0.95, 0.95, 3.5]:
		Geo.box(house, Vector3(0.18, 3.7, 0.42), Vector3(x, 1.85, -3.02), _timber)
	for y in [0.25, 2.65, 3.65]:
		Geo.box(house, Vector3(7.3, 0.18, 0.42), Vector3(0, y, 3.02), _timber)
		for x in [-3.52, 3.52]:
			Geo.box(house, Vector3(0.22, 0.18, 6.2), Vector3(x, y, 0), _timber)
		if y > 2.6:
			Geo.box(house, Vector3(7.3, 0.18, 0.42), Vector3(0, y, -3.02), _timber)
		else:
			for x in [-2.2, 2.2]:
				Geo.box(house, Vector3(2.6, 0.18, 0.42), Vector3(x, y, -3.02), _timber)
	for side in [-1.0, 1.0]:
		var roof_panel := Geo.box(house, Vector3(4.35, 0.22, 7.0), Vector3(side * 1.85, 4.5, 0), _roof)
		roof_panel.rotation.z = -side * 0.45
		var shape := BoxShape3D.new()
		shape.size = Vector3(4.35, 0.22, 7.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = house.transform * roof_panel.transform
		_solids.add_child(collision)
	_solid_box(house, Vector3(0.85, 2.0, 0.85), Vector3(2.1, 4.9, 1.1), _stone)
	for x in [-2.2, 2.2]:
		Geo.box(house, Vector3(1.1, 1.15, 0.08), Vector3(x, 2.05, -3.19), _timber)
		Geo.box(house, Vector3(0.81, 0.87, 0.09), Vector3(x, 2.05, -3.24), _gold)
		Geo.box(house, Vector3(0.06, 0.95, 0.1), Vector3(x, 2.05, -3.3), _timber)
		Geo.box(house, Vector3(0.9, 0.06, 0.1), Vector3(x, 2.05, -3.3), _timber)
	# Door swung inward, never a solid slab across the entrance.
	Geo.box(house, Vector3(0.14, 2.55, 1.7), Vector3(-0.86, 1.275, -2.1), _wood)
	Geo.box(house, Vector3(1.8, 0.035, 2.0), Vector3(0, 0.025, -4.0), _stone)


func _build_water_and_bridge() -> void:
	var water := Geo.material(Color("477f86"), 0.22, 0.26)
	# Opaque water keeps Compatibility rendering stable; its shore is inside the carved bowl.
	var pond := Geo.cylinder(self, 1, 1, 0.045, Vector3(22, 0.25, -10), water, 64)
	pond.scale = Vector3(7.75, 1, 26.35)
	var bridge := _root_at("WillowBridge", Vector3(22, BRIDGE_HEIGHT, -10))
	_solid_box(bridge, Vector3(22, 0.35, 4.8), Vector3(0, -0.175, 0), _timber)
	for i in range(44):
		Geo.box(bridge, Vector3(0.475, 0.055, 4.7), Vector3(-10.75 + float(i) * 0.5, 0.025, 0), _wood)
	for side in [-1.0, 1.0]:
		_solid_box(bridge, Vector3(21.7, 0.18, 0.18), Vector3(0, 1.05, side * 2.3), _wood)
		_solid_box(bridge, Vector3(21.7, 0.16, 0.16), Vector3(0, 0.5, side * 2.3), _wood)
		for i in range(7):
			var x: float = -10.5 + float(i) * 3.5
			_solid_box(bridge, Vector3(0.22, 3.8, 0.22), Vector3(x, -0.65, side * 2.3), _timber)
	# Low entry thresholds are flush with the y=3 route, not raised stair obstacles.
	for x in [10.5, 33.5]:
		_solid_box(self, Vector3(1.5, 0.25, 5.2), Vector3(x, BRIDGE_HEIGHT - 0.125, -10), _stone)
	for i in range(18):
		var angle: float = TAU * float(i) / 18.0
		var point := _ground(22 + cos(angle) * 9.3, -10 + sin(angle) * 31.5)
		if absf(point.z + 10.0) < 4.0:
			continue
		for stem in range(3):
			Geo.cylinder(self, 0.035, 0.02, 1.25, point + Vector3(float(stem) * 0.16, 0.6, 0), _wood, 4)


func _build_fort() -> void:
	var fort := _root_at("WatchfallFortress", _ground(55, -60))
	# South gate is an unobstructed eight-metre gap aligned with the village road.
	for x in [-10.0, 10.0]:
		_solid_box(fort, Vector3(12, 4.5, 1.6), Vector3(x, 2.25, 15), _stone)
		_solid_box(fort, Vector3(12, 3.7, 1.6), Vector3(x, 1.85, -15), _stone)
	for x in [-16.0, 16.0]:
		_solid_box(fort, Vector3(1.6, 4.2, 30), Vector3(x, 2.1, 0), _stone)
	# North gap also leads directly onto the ridge trail.
	for z in [-15.0, 15.0]:
		for x in [-16.0, 16.0]:
			_solid_box(fort, Vector3(4, 8.2, 4), Vector3(x, 4.1, z), _stone)
			for corner in [-1.25, 1.25]:
				_solid_box(fort, Vector3(1.3, 1.0, 1.3), Vector3(x + corner, 8.7, z - 1.25), _stone)
				_solid_box(fort, Vector3(1.3, 1.0, 1.3), Vector3(x + corner, 8.7, z + 1.25), _stone)
	for x in [-5.0, 5.0]:
		_solid_box(fort, Vector3(2, 6.5, 2.8), Vector3(x, 3.25, 15), _stone)
	_solid_box(fort, Vector3(12, 1.2, 2.8), Vector3(0, 6.3, 15), _stone)
	for i in range(8):
		var x: float = -13.5 + float(i) * 3.8
		if absf(x) < 4.0:
			continue
		Geo.box(fort, Vector3(1.6, 0.8, 1.8), Vector3(x, 4.9, 15), _stone)
	for x in [-9.0, 9.0]:
		for z in [-6.0, 5.0]:
			_solid_box(fort, Vector3(1.2, 3.2, 1.2), Vector3(x, 1.6, z), _stone)
	Geo.box(fort, Vector3(7, 0.08, 7), Vector3(0, 0.04, 0), Geo.material(Color("a4a58f")))


func _build_shrine() -> void:
	var shrine := _root_at("SuncrestShrine", _ground(-15, -100))
	# No raised inaccessible dais: the shrine clearing and both approaches are continuous terrain.
	Geo.cylinder(shrine, 6.5, 6.5, 0.06, Vector3(0, 0.03, 0), _stone, 16)
	for i in range(7):
		var angle: float = PI + float(i) * PI / 6.0
		var point := Vector3(cos(angle) * 7.0, 0, sin(angle) * 7.0)
		_solid_box(shrine, Vector3(1.0, 5.7, 1.0), point + Vector3(0, 2.85, 0), _stone, -angle)
		Geo.box(shrine, Vector3(1.8, 0.45, 1.8), point + Vector3(0, 5.8, 0), _gold)
	var ring := TorusMesh.new()
	ring.inner_radius = 3.1
	ring.outer_radius = 3.5
	ring.rings = 24
	ring.ring_segments = 6
	var halo := Geo.mesh_node(shrine, ring, _gold, Vector3(0, 9.0, -3.5))
	halo.rotation.x = PI * 0.5
	_solid_box(shrine, Vector3(1.3, 10, 1.3), Vector3(0, 5, -7), _stone)


func _build_waystone(id: String, label: String, point: Vector2) -> void:
	var root := _root_at(label.replace(" ", ""), _ground(point.x, point.y))
	var material := Geo.material(Color("578a8c"), 0.3)
	material.emission_enabled = true
	material.emission = Color("326365")
	material.emission_energy_multiplier = 0.25
	_solid_box(root, Vector3(1.35, 4.2, 1.35), Vector3(0, 2.1, 0), _stone, PI * 0.25)
	for side in [-1.0, 1.0]:
		Geo.box(root, Vector3(0.09, 3.5, 0.1), Vector3(side * 0.57, 2.3, 0.72), material)
	var crown := Geo.cylinder(root, 0.72, 0.0, 2.0, Vector3(0, 4.75, 0), material, 5)
	crown.name = "WaystoneCrystal"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 1.12
	ring.rings = 20
	ring.ring_segments = 6
	Geo.mesh_node(root, ring, _gold, Vector3(0, 3.3, 0))
	var beacon_material := Geo.material(Color("80f5e4"))
	beacon_material.emission_enabled = true
	beacon_material.emission = Color("60f1de")
	beacon_material.emission_energy_multiplier = 1.6
	var beacon := Geo.cylinder(root, 0.13, 0.055, 21, Vector3(0, 15.4, 0), beacon_material, 6)
	beacon.name = "AwakenedBeacon"
	beacon.visible = false
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "WaystoneLight"
	light.position = Vector3(0, 4, 0)
	light.light_color = Color("67e8d9")
	light.omni_range = 11.0
	light.light_energy = 0.15
	root.add_child(light)
	root.set_meta("crystal_material", material)
	interactables.append({"id": id, "name": label, "kind": "waystone", "position": root.position, "node": root})


func activate_interactable(id: String) -> void:
	if _activated.has(id):
		return
	for entry in interactables:
		if String(entry["id"]) != id:
			continue
		_activated[id] = true
		if String(entry["kind"]) == "camp":
			return
		var root: Node3D = entry["node"]
		var material: StandardMaterial3D = root.get_meta("crystal_material")
		material.albedo_color = Color("a0fff0")
		material.emission = Color("70ffe4")
		material.emission_energy_multiplier = 1.6
		var beacon := root.get_node("AwakenedBeacon") as MeshInstance3D
		beacon.visible = true
		var light := root.get_node("WaystoneLight") as OmniLight3D
		light.light_energy = 2.0
		return


func _build_enemy_spawns() -> void:
	# Clear ground near roads; objective defenders, wilderness hunters and devil packs.
	for entry in [
		Vector3(-49, 0, -20), Vector3(-61, 0, -30),
		Vector3(49, 1, -56), Vector3(61, 1, -65),
		Vector3(-9, 1, -96), Vector3(-21, 1, -98),
		Vector3(-27, 0, -1), Vector3(-39, 0, -16), Vector3(-62, 0, -48),
		Vector3(-48, 0, -68), Vector3(-35, 0, -82),
		Vector3(40, 0, -23), Vector3(62, 0, -33), Vector3(75, 0, -48),
		Vector3(35, 1, -80), Vector3(8, 0, -91)
	]:
		enemy_spawns.append({"position": _ground(entry.x, entry.z), "kind": int(entry.y)})
	# Cinder devil packs. The village-glade pack sits just outside the camp's
	# 19 m safe ring; the western pack joins the existing woodland hunters.
	var glade := Vector2(-20, 21)
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var point := glade + Vector2(cos(angle), sin(angle)) * 2.7
		enemy_spawns.append({"position": _ground(point.x, point.y), "kind": 2, "pack_index": index})
	var western := Vector2(-46, -30)
	for index in 3:
		var angle := TAU * float(index) / 3.0 + 0.4
		var point := western + Vector2(cos(angle), sin(angle)) * 2.4
		enemy_spawns.append({"position": _ground(point.x, point.y), "kind": 2, "pack_index": 5 + index})


func _reserved(point: Vector2, margin: float) -> bool:
	if maxf(absf(point.x), absf(point.y)) > 124.0:
		return true
	if _route_sample(point.x, point.y).x < margin:
		return true
	if point.distance_to(Vector2(0, 32)) < 29.0:
		return true
	if absf(point.x - 55.0) < 21.0 and absf(point.y + 60.0) < 21.0:
		return true
	if Vector2((point.x - 22.0) / 13.0, (point.y + 10.0) / 38.0).length() < 1.0:
		return true
	for entry in interactables:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 11.0:
			return true
	for entry in enemy_spawns:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 3.0:
			return true
	return false


func _build_woodland() -> void:
	var trunks: Array[Transform3D] = []
	var pine_dark: Array[Transform3D] = []
	var pine_light: Array[Transform3D] = []
	var oak: Array[Transform3D] = []
	var amber: Array[Transform3D] = []
	for i in range(560):
		var point := Vector2(_rng.randf_range(-126, 126), _rng.randf_range(-126, 124))
		if _reserved(point, 6.5):
			continue
		# More open meadow in the south; dense woodland on the west and northern shoulders.
		if point.y > 45.0 and i % 3 != 0:
			continue
		var base := _ground(point.x, point.y)
		var height: float = _rng.randf_range(7.0, 12.0)
		var radius: float = height * 0.045
		trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(radius, height * 0.8, radius)), base + Vector3(0, height * 0.4, 0)))
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height * 0.8
		collision.shape = shape
		collision.position = base + Vector3(0, shape.height * 0.5, 0)
		_solids.add_child(collision)
		if i % 3 != 0:
			for layer in range(3):
				var width: float = height * (0.30 - float(layer) * 0.065)
				var branch_transform := Transform3D(Basis(Vector3.UP, float(i)).scaled(Vector3(width, height * 0.49, width)), base + Vector3(0, height * (0.48 + float(layer) * 0.19), 0))
				if layer == 1:
					pine_light.append(branch_transform)
				else:
					pine_dark.append(branch_transform)
		else:
			for branch in range(3):
				var crown_transform := Transform3D(Basis(Vector3.UP, float(i)).scaled(Vector3(height * 0.25, height * 0.23, height * 0.24)), base + Vector3(float(branch - 1) * height * 0.16, height * (0.73 + float(branch % 2) * 0.12), 0))
				if i % 4 == 0:
					amber.append(crown_transform)
				else:
					oak.append(crown_transform)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.top_radius = 0.68
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 7
	_batch("BatchedTreeTrunks", trunk_mesh, _timber, trunks)
	var cone := CylinderMesh.new()
	cone.bottom_radius = 1.0
	cone.top_radius = 0.0
	cone.height = 1.0
	cone.radial_segments = 7
	_batch("BatchedPineShade", cone, Geo.material(Color("315e49")), pine_dark)
	_batch("BatchedPineLight", cone, Geo.material(Color("54805a")), pine_light)
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 7
	crown.rings = 4
	_batch("BatchedOakCrowns", crown, Geo.material(Color("78934f")), oak)
	_batch("BatchedAmberCrowns", crown, Geo.material(Color("b2a65d")), amber)
	generation_stats["trees"] = trunks.size()
	_build_grass()


func _build_grass() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(3):
		var angle: float = float(i) * PI / 3.0
		var side := Vector3(cos(angle), 0, sin(angle)) * 0.22
		vertices.append_array(PackedVector3Array([-side, side, Vector3(0.06, 0.6 + float(i) * 0.06, 0)]))
		normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := Geo.material(Color("879853"))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grass: Array[Transform3D] = []
	for i in range(4200):
		var point := Vector2(_rng.randf_range(-122, 122), _rng.randf_range(-122, 122))
		if _reserved(point, 3.0):
			continue
		var scale_at: float = _rng.randf_range(0.6, 1.5)
		grass.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale_at), _ground(point.x, point.y)))
	_batch("BatchedMeadowGrass", mesh, material, grass, false)
	generation_stats["grass_clumps"] = grass.size()


func _build_rocks() -> void:
	for i in range(60):
		var point := Vector2(_rng.randf_range(-124, 124), _rng.randf_range(-124, 112))
		if _reserved(point, 7.0):
			continue
		var radius: float = _rng.randf_range(0.8, 2.2)
		var base := _ground(point.x, point.y)
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 1.6
		mesh.radial_segments = 6
		mesh.rings = 3
		var visual := Geo.mesh_node(self, mesh, _stone, base + Vector3(0, radius * 0.45, 0))
		visual.rotation.y = _rng.randf_range(0, TAU)
		var collision := CollisionShape3D.new()
		collision.shape = mesh.create_convex_shape()
		collision.transform = visual.transform
		_solids.add_child(collision)


func _build_signposts() -> void:
	for entry in [
		[Vector2(3.8, 5), "HEARTWOOD  ←\nWATCHFALL  →"],
		[Vector2(-50, -57), "SUNCREST  ↑"],
		[Vector2(36, -13), "HEARTHSTEAD  ←"]
	]:
		var point: Vector2 = entry[0]
		var root := _root_at("TrailSign", _ground(point.x, point.y))
		_solid_box(root, Vector3(0.16, 2.8, 0.16), Vector3(0, 1.4, 0), _wood)
		Geo.box(root, Vector3(3.4, 1.0, 0.16), Vector3(0, 2.45, 0), _timber)
		var label := Label3D.new()
		label.text = String(entry[1])
		label.font_size = 34
		label.pixel_size = 0.0045
		label.modulate = Color("f6e4b0")
		label.position = Vector3(0, 2.45, 0.095)
		root.add_child(label)


func _batch(label: String, mesh: Mesh, material: Material, transforms: Array[Transform3D], shadows: bool = true) -> void:
	if transforms.is_empty():
		return
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for i in range(transforms.size()):
		batch.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = batch
	instance.material_override = material
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
