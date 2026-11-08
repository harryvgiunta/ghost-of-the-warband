class_name RogueliteStage
extends Node3D
## One bounded island: the ground a run is fought on.
##
## The three biomes are the campaign's own art, recycled: the wood's trees out of
## `TreeKit` and `WorldStyle`, the cave floor's dripstone and glow out of
## `CaveKit`, the ring's dressed stone out of `RockKit` and primitives. Nothing
## here is a new asset pipeline, and nothing here touches the terrain heightfield:
## the island stands off the field at its own height (`LIFT`), exactly the way the
## arena ring and the delve already stand away from it.
##
## What makes it an island rather than a scene is the boundary: a ring of solid
## blockers just behind the fog wall, so a body that runs at the edge stops, and a
## fog sheet thick enough to read as the edge of the world without stopping a
## shaft. The wall has no gate: the run's own portals are the way out.

const Geo = preload("res://scripts/geo.gd")
const RockKit = preload("res://scripts/world/rock_kit.gd")
const CaveKit = preload("res://scripts/world/cave_kit.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const WorldScatter = preload("res://scripts/world/scatter.gd")
const RunForest = preload("res://scripts/warband/run_forest.gd")
const WorldStyleScript = preload("res://scripts/world/world_style.gd")

## Out of sight above the campaign and clear of the arena ring (260) and the
## delve (1100 in z). Each stage takes its own height so the corpse and prop of
## the last island can never be found on the next.
const LIFT := 620.0
const STAGE_SPACING := 210.0

const BIOMES := [
	{
		"id": "wilderness", "name": "THE BRIARWOOD", "subtitle": "WILDERNESS  ·  WATCHERS",
		"radius": 34.0, "wall_height": 7.0,
		"earth": Color(0.19, 0.21, 0.13), "sky": Color(0.11, 0.15, 0.17),
		"fog": Color(0.16, 0.22, 0.18, 0.30), "light": Color(0.72, 0.86, 0.72),
		"faction": "watchers",
	},
	{
		"id": "caves", "name": "THE HOLLOW BENEATH", "subtitle": "CAVES  ·  DEMONS",
		"radius": 30.0, "wall_height": 8.0,
		"earth": Color(0.17, 0.14, 0.12), "sky": Color(0.05, 0.05, 0.06),
		"fog": Color(0.22, 0.13, 0.09, 0.34), "light": Color(1.0, 0.55, 0.30),
		"faction": "demons",
	},
	{
		"id": "arena", "name": "THE BLOOD PIT", "subtitle": "ARENA  ·  BLOOD CLONES",
		"radius": 31.0, "wall_height": 7.5,
		"earth": Color(0.27, 0.22, 0.17), "sky": Color(0.14, 0.09, 0.08),
		"fog": Color(0.30, 0.12, 0.09, 0.28), "light": Color(1.0, 0.62, 0.42),
		"faction": "clones",
	},
]

var biome_id := "wilderness"
var radius := 34.0
var seed_value := 0
var stage_index := 0
var _rng := RandomNumberGenerator.new()
var _props: Node3D
var _dressing: Node3D


static func biome(biome_key: String) -> Dictionary:
	for row in BIOMES:
		if str(row.id) == biome_key:
			return row
	return BIOMES[0]


static func centre_for(index: int) -> Vector3:
	return Vector3(0.0, LIFT + float(absi(index)) * STAGE_SPACING, 0.0)


## Build (or rebuild) the island. The node is expected to have been positioned
## at `centre_for(stage_index)` by the caller before `build`.
func build(biome_key: String, run_seed: int, index: int) -> void:
	biome_id = biome_key
	stage_index = maxi(0, index)
	seed_value = run_seed
	var data := biome(biome_key)
	radius = float(data.radius)
	_rng.seed = int(run_seed) + stage_index * 7919 + str(biome_key).hash()
	_position_on_lift()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	_build_floor(data)
	_build_boundary(data)
	_build_light(data)
	match biome_key:
		"caves":
			_build_cave(data)
		"arena":
			_build_pit(data)
		_:
			_build_wood(data)
	_build_litter(data)


## A body is placed on an island by this, never by the heightfield: the island's
## own floor is the only ground under it.
func _position_on_lift() -> void:
	var wanted := centre_for(stage_index)
	if global_position.distance_squared_to(wanted) > 0.001:
		global_position = wanted


func floor_point(local: Vector2) -> Vector3:
	return global_position + Vector3(local.x, 0.05, local.y)


func random_point(rng: RandomNumberGenerator, margin: float = 4.0) -> Vector3:
	var reach := maxf(1.0, radius - margin)
	for _attempt in 24:
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * reach
		return floor_point(Vector2(cos(angle) * distance, sin(angle) * distance))
	return floor_point(Vector2.ZERO)


## Where a wave comes in: the rim, spread around the circle. The angle is jittered
## so two waves of the same count never stand in the same ring.
func spawn_points(count: int, rng: RandomNumberGenerator = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var die := rng if rng != null else _rng
	for index in count:
		var angle := TAU * (float(index) / float(maxi(1, count))) + die.randf_range(-0.18, 0.18)
		var distance := radius * die.randf_range(0.62, 0.84)
		out.append(floor_point(Vector2(cos(angle) * distance, sin(angle) * distance)))
	return out


## Where the party stands when the portal drops them on a fresh island.
func entry_posts(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index in count:
		var spread := (float(index) - float(maxi(1, count) - 1) * 0.5) * 2.0
		out.append(floor_point(Vector2(spread, radius * 0.62)))
	return out


## The island's rim, for portals, chests and the shop: evenly spaced around the
## back half so nothing lands on the party's own entry line.
func rim_point(index: int, count: int, inset: float = 3.2) -> Vector3:
	var angle := PI * (0.15 + 0.7 * (float(index) + 0.5) / float(maxi(1, count)))
	var distance := maxf(1.0, radius - inset)
	return floor_point(Vector2(cos(angle) * distance, sin(angle) * distance))


# --- ground ----------------------------------------------------------------

func _build_floor(data: Dictionary) -> void:
	var earth := Geo.material(data.earth, 0.0, 0.94)
	var floor_mesh := Geo.cylinder(self, radius, radius, 0.7, Vector3(0.0, -0.35, 0.0), earth, 48)
	floor_mesh.name = "IslandFloor"
	var solid := StaticBody3D.new()
	solid.name = "IslandGround"
	add_child(solid)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 2.0, 0.7, radius * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.35, 0.0)
	solid.add_child(shape)
	# A rim of rock under the lip so the island reads as a broken-off piece of
	# the world rather than a disc in the sky.
	var rock := RockKit.mesh("outcrop", seed_value + 31)
	if rock != null:
		var underneath := Node3D.new()
		underneath.name = "Underside"
		add_child(underneath)
		var stone := Geo.material(data.earth.darkened(0.35), 0.0, 0.98)
		for index in 9:
			var angle := TAU * float(index) / 9.0
			var mesh := MeshInstance3D.new()
			mesh.mesh = rock
			mesh.material_override = stone
			mesh.position = Vector3(cos(angle) * radius * 0.86, -1.4,
				sin(angle) * radius * 0.86)
			mesh.scale = Vector3(4.0, 3.4, 4.0)
			mesh.rotation.y = _rng.randf_range(0.0, TAU)
			underneath.add_child(mesh)


func _build_boundary(data: Dictionary) -> void:
	var solid := StaticBody3D.new()
	solid.name = "IslandWall"
	add_child(solid)
	var segments := 28
	var step := TAU / float(segments)
	var chord := 2.0 * (radius + 0.7) * sin(step * 0.5) + 0.6
	for index in segments:
		var angle := step * float(index)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(chord, float(data.wall_height), 0.6)
		shape.shape = box
		shape.position = Vector3(cos(angle) * (radius + 0.9),
			float(data.wall_height) * 0.5, sin(angle) * (radius + 0.9))
		shape.rotation.y = -angle
		solid.add_child(shape)
	# The fog sheet. One cylinder, unshaded and double-sided, so the edge reads
	# as weather rather than a wall from either side.
	var fog_mesh := CylinderMesh.new()
	fog_mesh.top_radius = radius + 1.1
	fog_mesh.bottom_radius = radius + 1.1
	fog_mesh.height = float(data.wall_height)
	fog_mesh.radial_segments = 40
	fog_mesh.rings = 2
	fog_mesh.cap_top = false
	fog_mesh.cap_bottom = false
	var fog := MeshInstance3D.new()
	fog.name = "BoundaryFog"
	fog.mesh = fog_mesh
	var fog_material := StandardMaterial3D.new()
	fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_material.albedo_color = data.fog
	fog_material.disable_receive_shadows = true
	fog.material_override = fog_material
	fog.position = Vector3(0.0, float(data.wall_height) * 0.5, 0.0)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)


func _build_light(data: Dictionary) -> void:
	var sun := OmniLight3D.new()
	sun.name = "IslandLight"
	sun.light_color = data.light
	sun.light_energy = 2.2 if biome_id == "caves" else 1.5
	sun.omni_range = radius * 2.4
	sun.position = Vector3(0.0, float(data.wall_height) - 1.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)
	if biome_id == "caves":
		# A floor glow under the island so the rim is not a black hole.
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.42, 0.18)
		glow.light_energy = 0.9
		glow.omni_range = radius * 1.4
		glow.position = Vector3(0.0, 0.6, 0.0)
		add_child(glow)




# --- the three biomes ------------------------------------------------------

func _build_wood(_data: Dictionary) -> void:
	var style: WorldStyle = RunForest.night_style()
	var species_ids := ["ironoak", "briar_pine", "hollow_snag"]
	var planted := 0
	for species_id in species_ids:
		var species: Dictionary = style.species_by_id(str(species_id))
		if species.is_empty():
			continue
		var variants := TreeKit.build_variants(species, seed_value + planted * 31 + 11)
		for variant in variants:
			var trunks: Array[Dictionary] = []
			var leaves: Array[Dictionary] = []
			var copies := 3 + _rng.randi_range(0, 2)
			for _copy in copies:
				var angle := _rng.randf_range(0.0, TAU)
				var distance := sqrt(_rng.randf()) * (radius - 5.0)
				var at := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
				if absf(at.x) < 4.0 and at.z > radius * 0.35:
					continue
				var scale_at := _rng.randf_range(0.85, 1.25)
				var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) .scaled(Vector3.ONE * scale_at)
				var xform := Transform3D(basis, at)
				trunks.append({"transform": xform,
					"color": _pick(species.get("bark_tints", []), Color.WHITE, _rng)})
				if variant.get("leaves") != null:
					leaves.append({"transform": xform,
						"color": _pick(species.get("tints", []), Color.WHITE, _rng)})
				# The trunk's collider stands where the trunk stands: the tree
				# itself is a multimesh cell, its bark is this one body.
				TreeKit.add_trunk_solids(_props, at, variant, scale_at)
			WorldScatter.batch(_dressing, "Trunk_%s_%d" % [species_id, planted],
				variant["trunk"], TextureLibrary.bark_material(String(variant["bark"])),
				trunks, 24.0)
			if variant.get("leaves") != null and not leaves.is_empty():
				WorldScatter.batch(_dressing, "Leaves_%s_%d" % [species_id, planted],
					variant["leaves"],
					TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]),
						variant.get("wind", Vector2(0.08, 1.0))),
					leaves, 24.0)
			planted += 1
	_scatter_rocks("boulder", 10, 0.8, 1.7)


func _build_cave(_data: Dictionary) -> void:
	_build_shell(Color(0.16, 0.13, 0.11), 11.0, true)
	var stone := Geo.material(Color(0.20, 0.17, 0.15), 0.0, 0.9)
	var floor_mesh := Geo.cylinder(self, radius * 0.98, radius * 0.98, 0.06,
		Vector3(0.0, 0.03, 0.0), stone, 40)
	floor_mesh.name = "CaveFloor"
	var formation_material := CaveKit.formation_material("strata")
	var glow_material := CaveKit.glow_material(Color(1.0, 0.42, 0.22))
	# Floor pieces: stalagmites and columns, batched where the kit has them.
	for piece in ["StalagmiteTall", "StalagmiteSquat", "Column", "BoulderA"]:
		var mesh: Mesh = CaveKit.formation(str(piece))
		if mesh == null:
			continue
		var instances: Array[Dictionary] = []
		var copies := 5 if piece != "Column" else 3
		for _index in copies:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := _rng.randf_range(radius * 0.45, radius - 4.0)
			var scale_at := _rng.randf_range(0.8, 1.6)
			instances.append({"transform": Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) .scaled(Vector3.ONE * scale_at),
				Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))})
		WorldScatter.batch(_dressing, "Cave_%s" % piece, mesh, formation_material,
			instances, 20.0)
	# Roof pieces hang from the fog's top: the island is a room with a lid.
	for piece in ["StalactiteCarrot", "StalactiteRibbed"]:
		var mesh: Mesh = CaveKit.formation(str(piece))
		if mesh == null:
			continue
		var instances: Array[Dictionary] = []
		for _index in 7:
			var angle := _rng.randf_range(0.0, TAU)
			var distance := _rng.randf_range(radius * 0.25, radius - 3.0)
			instances.append({"transform": Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)),
				Vector3(cos(angle) * distance, 9.0, sin(angle) * distance))})
		WorldScatter.batch(_dressing, "Roof_%s" % piece, mesh, formation_material,
			instances, 20.0)
	# Glow caps: the hollow's own light, four clumps of fungus and crystal.
	for _index in 6:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(radius * 0.35, radius - 5.0)
		var cap: Mesh = CaveKit.flora("CapCluster")
		if cap == null:
			cap = CaveKit.flora("CapGiant")
		if cap == null:
			continue
		var node := MeshInstance3D.new()
		node.mesh = cap
		node.material_override = glow_material
		node.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		node.scale = Vector3.ONE * _rng.randf_range(0.7, 1.2)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dressing.add_child(node)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.45, 0.24)
		glow.light_energy = 1.4
		glow.omni_range = 7.0
		glow.position = Vector3(cos(angle) * distance, 1.1, sin(angle) * distance)
		_dressing.add_child(glow)
	_scatter_rocks("spire", 6, 1.2, 2.2)


func _build_pit(_data: Dictionary) -> void:
	# A low stone rim before the fog: the pit's horizon is a wall of dressed
	# stone, not open sky. The colonnade stands inside it.
	_build_shell(Color(0.20, 0.18, 0.16), 4.2, false)
	var sand := Geo.material(Color(0.34, 0.27, 0.19), 0.0, 0.95)
	var floor_mesh := Geo.cylinder(self, radius * 0.99, radius * 0.99, 0.08,
		Vector3(0.0, 0.04, 0.0), sand, 44)
	floor_mesh.name = "PitSand"
	var stone := Geo.material(Color(0.33, 0.31, 0.28), 0.0, 0.9)
	var iron := Geo.material(Color(0.22, 0.21, 0.20), 0.55, 0.5)
	# The ring of dressed stone the pit is fought in: a colonnade, then braziers
	# between the columns. This is the arena's own architecture, recycled.
	var solid := StaticBody3D.new()
	solid.name = "PitPillars"
	add_child(solid)
	var columns := 16
	for index in columns:
		var angle := TAU * float(index) / float(columns)
		var at := Vector3(cos(angle) * (radius - 3.0), 0.0, sin(angle) * (radius - 3.0))
		Geo.cylinder(_props, 0.62, 0.48, 4.6, at + Vector3(0.0, 2.3, 0.0), stone, 10)
		Geo.box(_props, Vector3(1.5, 0.42, 1.5), at + Vector3(0.0, 4.75, 0.0), stone)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 4.8, 1.2)
		shape.shape = box
		shape.position = at + Vector3(0.0, 2.4, 0.0)
		solid.add_child(shape)
		if index % 4 == 0:
			var brazier := Node3D.new()
			brazier.position = Vector3(cos(angle + 0.14) * (radius - 5.4), 0.0,
				sin(angle + 0.14) * (radius - 5.4))
			_props.add_child(brazier)
			Geo.cylinder(brazier, 0.34, 0.26, 1.5, Vector3(0.0, 0.75, 0.0), iron, 8)
			var flame := Geo.sphere(brazier, 0.34, Vector3(0.0, 1.72, 0.0), iron,
				Vector3(1.0, 1.5, 1.0))
			flame.material_override = CaveKit.glow_material(Color(1.0, 0.55, 0.2))
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.58, 0.24)
			light.light_energy = 2.0
			light.omni_range = 12.0
			light.position = Vector3(0.0, 1.9, 0.0)
			brazier.add_child(light)
	# Broken stones scattered across the floor: cover, not decoration.
	_scatter_rocks("cobble", 9, 0.7, 1.4)


func _scatter_rocks(kind: String, copies: int, min_scale: float, max_scale: float) -> void:
	var mesh := RockKit.mesh(kind, seed_value + kind.hash())
	if mesh == null:
		return
	var stone := Geo.material(Color(0.24, 0.23, 0.21), 0.0, 0.95)
	var instances: Array[Dictionary] = []
	for _index in copies:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(radius * 0.35, radius - 4.0)
		var scale_at := _rng.randf_range(min_scale, max_scale)
		instances.append({"transform": Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) .scaled(Vector3(scale_at, scale_at * 0.7, scale_at)),
			Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))})
	WorldScatter.batch(_dressing, "Rocks_%s" % kind, mesh, stone, instances, 20.0)


## The chamber's shell: a wall just behind the fog sheet and, for a cave, a roof
## that closes the sky. An island is a piece of the world, not a slice of it, and
## a demon floor under an open blue sky read as a stage set.
func _build_shell(colour: Color, height: float, roofed: bool) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.96
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = radius + 1.5
	wall_mesh.bottom_radius = radius + 1.5
	wall_mesh.height = maxf(2.0, height)
	wall_mesh.radial_segments = 56
	wall_mesh.rings = 3
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	var wall := MeshInstance3D.new()
	wall.name = "ChamberWall"
	wall.mesh = wall_mesh
	wall.material_override = material
	wall.position = Vector3(0.0, wall_mesh.height * 0.5, 0.0)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	if not roofed:
		return
	var roof_mesh := CylinderMesh.new()
	roof_mesh.top_radius = radius + 1.5
	roof_mesh.bottom_radius = radius + 1.5
	roof_mesh.height = 1.2
	roof_mesh.radial_segments = 56
	roof_mesh.rings = 2
	var roof := MeshInstance3D.new()
	roof.name = "ChamberRoof"
	roof.mesh = roof_mesh
	roof.material_override = material
	roof.position = Vector3(0.0, wall_mesh.height + 0.6, 0.0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(roof)


func _build_litter(_data: Dictionary) -> void:
	# Enough small stones and bones to keep the floor from reading as graph paper,
	# at one draw call each.
	var bone := Geo.material(Color(0.72, 0.66, 0.53), 0.0, 0.75)
	# A pebble, not a hole: the second litter tone is mid-stone, never near-black,
	# because a flat dark decal on a lit floor reads as a gap in it.
	var stone := Geo.material(Color(0.34, 0.31, 0.26), 0.0, 0.95)
	for index in 20:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * (radius - 3.0)
		var at := Vector3(cos(angle) * distance, 0.02, sin(angle) * distance)
		var piece := Geo.box(_dressing, Vector3(_rng.randf_range(0.16, 0.4), 0.05,
			_rng.randf_range(0.1, 0.24)), at,
			bone if index % 3 == 0 else stone)
		piece.rotation.y = _rng.randf_range(0.0, TAU)
		piece.rotation.z = _rng.randf_range(-0.1, 0.1)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _pick(values: Array, fallback: Color,
		rng: RandomNumberGenerator) -> Color:
	if values.is_empty():
		return fallback
	var value: Variant = values[rng.randi_range(0, values.size() - 1)]
	if value is Color:
		return value
	return fallback
