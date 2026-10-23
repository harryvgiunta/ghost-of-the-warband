extends Node3D
## "The Sunken Delve" chamber: one sealed underground room with a north landing
## platform, a south gate, four dark archways for the cinder devils and rock
## cover around a central dais. Geometry is authored once in _ready; every
## gameplay point comes from the shared Delve contract.

const Geo = preload("res://scripts/geo.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

const LIMIT := 17.0
const CEILING_HEIGHT := 15.0
const DROP_HEIGHT := 8.0
const CHAMBER_HALF := 18.0
const WALL_THICKNESS := 2.0
const FLOOR_THICKNESS := 1.0
const PLATFORM_TOP := 3.2
const PLATFORM_SIZE := Vector3(12.0, PLATFORM_TOP, 4.5)
const GATE_WIDTH := 6.0
const GATE_HEIGHT := 4.6
const PILLAR_COUNT := 6
const PILLAR_RADIUS := 0.9
const PILLAR_HEIGHT := 12.0
const PILLAR_RING := 9.0
const STAIR_STEPS := 7
const STAIR_RISE := 0.4
const STAIR_DEPTH := 0.5

var player_spawns: Array[Vector3] = [
	Vector3(-4.5, 3.28, 15.2),
	Vector3(-1.5, 3.28, 15.2),
	Vector3(1.5, 3.28, 15.2),
	Vector3(4.5, 3.28, 15.2),
]
var enemy_spawns: Array[Dictionary] = [
	{"position": Vector3(12.8, 0.05, 10.5), "facing": Vector3(-1, 0, 0)},
	{"position": Vector3(-12.8, 0.05, 10.5), "facing": Vector3(1, 0, 0)},
	{"position": Vector3(12.8, 0.05, -10.5), "facing": Vector3(-1, 0, 0)},
	{"position": Vector3(-12.8, 0.05, -10.5), "facing": Vector3(1, 0, 0)},
]
var descent_position: Vector3 = Vector3(0, 0.05, -15.0)
var ascent_position: Vector3 = Vector3(0, 0.05, 12.2)
var chest_position: Vector3 = Vector3(0, 0.06, 0)
var drop_center: Vector3 = Vector3(0, 8.0, 0)
var sealed: bool = false
var generation_stats: Dictionary = {}

var _rock: StandardMaterial3D
var _stone: StandardMaterial3D
var _dark_stone: StandardMaterial3D
var _wood: StandardMaterial3D
var _iron: StandardMaterial3D
var _portal: StandardMaterial3D
var _solids: int = 0
var _lights: int = 0
var _gate_shapes: Array[CollisionShape3D] = []
var _gate_bars: Array[MeshInstance3D] = []


func _ready() -> void:
	_rock = TextureLibrary.rock_material()
	_stone = TextureLibrary.building_material("stone", Color("69736c"))
	_dark_stone = TextureLibrary.building_material("stone", Color("3a423f"))
	_wood = TextureLibrary.building_material("wood", Color("6d5741"))
	_iron = Geo.material(Color("2a2f34"), 0.65, 0.42)
	_portal = StandardMaterial3D.new()
	_portal.albedo_color = Color(0.012, 0.016, 0.022)
	_portal.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_portal.disable_receive_shadows = true

	_build_environment()
	_build_chamber_shell()
	_build_ceiling_and_shaft()
	_build_landing_platform()
	_build_gates()
	_build_archways()
	_build_side_alcoves()
	_build_dais()
	_build_pillars()
	_build_cover()
	_build_torches()
	_build_fill_lighting()
	set_sealed(sealed)

	generation_stats = {
		"solids": _solids,
		"player_spawns": player_spawns.size(),
		"enemy_spawns": enemy_spawns.size(),
		"ceiling_height": CEILING_HEIGHT,
		"pillars": PILLAR_COUNT,
		"torches": _lights,
		"archways": enemy_spawns.size(),
		"limit": LIMIT,
	}


## Toggles both portcullises. Sealed means blocked: the GateShape colliders are
## enabled and the GateBars are visible.
func set_sealed(value: bool) -> void:
	sealed = value
	for shape in _gate_shapes:
		shape.disabled = not value
	for bars in _gate_bars:
		bars.visible = value


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("04060a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("556273")
	environment.ambient_light_energy = 0.58
	environment.ambient_light_sky_contribution = 0.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color("18222c")
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.008
	environment.fog_sky_affect = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.25
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.05
	environment.adjustment_contrast = 1.08

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


func _build_chamber_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Chamber"
	add_child(shell)

	_solid_box(Vector3(CHAMBER_HALF * 2.0 + WALL_THICKNESS * 2.0, FLOOR_THICKNESS,
		CHAMBER_HALF * 2.0 + WALL_THICKNESS * 2.0),
		Vector3(0, -FLOOR_THICKNESS * 0.5, 0), _rock, shell).name = "Floor"

	var wall_height := CEILING_HEIGHT
	_solid_box(Vector3(CHAMBER_HALF * 2.0 + WALL_THICKNESS * 2.0, wall_height, WALL_THICKNESS),
		Vector3(0, wall_height * 0.5, CHAMBER_HALF + WALL_THICKNESS * 0.5), _stone, shell).name = "NorthWall"
	_solid_box(Vector3(CHAMBER_HALF * 2.0 + WALL_THICKNESS * 2.0, wall_height, WALL_THICKNESS),
		Vector3(0, wall_height * 0.5, -CHAMBER_HALF - WALL_THICKNESS * 0.5), _stone, shell).name = "SouthWall"
	_solid_box(Vector3(WALL_THICKNESS, wall_height, CHAMBER_HALF * 2.0),
		Vector3(CHAMBER_HALF + WALL_THICKNESS * 0.5, wall_height * 0.5, 0), _stone, shell).name = "EastWall"
	_solid_box(Vector3(WALL_THICKNESS, wall_height, CHAMBER_HALF * 2.0),
		Vector3(-CHAMBER_HALF - WALL_THICKNESS * 0.5, wall_height * 0.5, 0), _stone, shell).name = "WestWall"

	# Stone ribs give the walls a built, pillared rhythm without adding colliders.
	for index in 5:
		var z := -14.0 + index * 7.0
		for side in [-1.0, 1.0]:
			Geo.box(shell, Vector3(0.45, wall_height, 0.7),
				Vector3(side * (CHAMBER_HALF - 0.22), wall_height * 0.5, z), _dark_stone)
	for index in 3:
		var x := -12.0 + index * 12.0
		for side in [-1.0, 1.0]:
			Geo.box(shell, Vector3(0.7, wall_height, 0.45),
				Vector3(x, wall_height * 0.5, side * (CHAMBER_HALF - 0.22)), _dark_stone)


func _build_ceiling_and_shaft() -> void:
	var ceiling := Node3D.new()
	ceiling.name = "Ceiling"
	add_child(ceiling)

	var hole := 2.5
	var half := CHAMBER_HALF
	var outside := half + WALL_THICKNESS
	var band := (outside - hole) * 0.5
	var band_center := hole + band
	_solid_box(Vector3(outside * 2.0, 0.9, band * 2.0),
		Vector3(0, CEILING_HEIGHT + 0.45, band_center), _rock, ceiling)
	_solid_box(Vector3(outside * 2.0, 0.9, band * 2.0),
		Vector3(0, CEILING_HEIGHT + 0.45, -band_center), _rock, ceiling)
	_solid_box(Vector3(band * 2.0, 0.9, hole * 2.0),
		Vector3(band_center, CEILING_HEIGHT + 0.45, 0), _rock, ceiling)
	_solid_box(Vector3(band * 2.0, 0.9, hole * 2.0),
		Vector3(-band_center, CEILING_HEIGHT + 0.45, 0), _rock, ceiling)

	# Visual drop shaft above the hole. No collision so the drop never snags.
	var shaft := Node3D.new()
	shaft.name = "DropShaft"
	ceiling.add_child(shaft)
	var shaft_height := DROP_HEIGHT
	var lip := 3.0
	for side in [-1.0, 1.0]:
		Geo.box(shaft, Vector3(0.6, shaft_height, lip * 2.0),
			Vector3(side * (hole + 0.3), CEILING_HEIGHT + shaft_height * 0.5, 0), _rock)
		Geo.box(shaft, Vector3(lip * 2.0, shaft_height, 0.6),
			Vector3(0, CEILING_HEIGHT + shaft_height * 0.5, side * (hole + 0.3)), _rock)

	# Faint shaft of light falling through the opening.
	var shaft_material := StandardMaterial3D.new()
	shaft_material.albedo_color = Color(0.58, 0.7, 0.95, 0.05)
	shaft_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shaft_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shaft_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft_material.disable_receive_shadows = true
	var light_shaft := MeshInstance3D.new()
	light_shaft.name = "LightShaft"
	var cone := CylinderMesh.new()
	cone.top_radius = hole * 0.9
	cone.bottom_radius = hole * 1.9
	cone.height = CEILING_HEIGHT
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	light_shaft.mesh = cone
	light_shaft.material_override = shaft_material
	light_shaft.position = Vector3(0, CEILING_HEIGHT * 0.5, 0)
	light_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.add_child(light_shaft)

	var spot := SpotLight3D.new()
	spot.name = "DropShaftLight"
	spot.position = Vector3(0, CEILING_HEIGHT - 0.4, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = Color("b7cdf0")
	spot.light_energy = 3.4
	spot.spot_range = 24.0
	spot.spot_angle = 40.0
	spot.shadow_enabled = true
	shaft.add_child(spot)


func _build_landing_platform() -> void:
	var platform := Node3D.new()
	platform.name = "NorthPlatform"
	add_child(platform)

	_solid_box(PLATFORM_SIZE, Vector3(0, PLATFORM_TOP * 0.5, 15.25), _stone, platform).name = "PlatformBlock"
	Geo.box(platform, Vector3(11.7, 0.06, 4.2), Vector3(0, 3.22, 15.25), _wood)
	# Low rails along the three platform edges (visual only).
	for side in [-1.0, 1.0]:
		Geo.box(platform, Vector3(0.16, 0.9, 4.2), Vector3(side * 5.85, 3.65, 15.25), _wood)
		for index in 3:
			Geo.box(platform, Vector3(0.2, 1.0, 0.2),
				Vector3(side * 5.85, 3.7, 13.2 + index * 1.9), _wood)
	Geo.box(platform, Vector3(11.7, 0.16, 0.16), Vector3(0, 4.1, 17.25), _wood)
	for index in 5:
		Geo.box(platform, Vector3(0.2, 1.0, 0.2),
			Vector3(-5.4 + index * 2.7, 3.7, 17.25), _wood)

	# Landing runes mark the four drop points without colliding.
	var rune_material := Geo.material(Color("89b7c9"))
	rune_material.emission_enabled = true
	rune_material.emission = Color("3f6f82")
	rune_material.emission_energy_multiplier = 0.6
	for spawn in player_spawns:
		var ring := Geo.cylinder(platform, 0.55, 0.55, 0.012,
			Vector3(spawn.x, 3.256, spawn.z), rune_material, 24)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var stairs := Node3D.new()
	stairs.name = "Stairs"
	platform.add_child(stairs)
	for index in STAIR_STEPS:
		var top := PLATFORM_TOP - STAIR_RISE * float(index + 1)
		var z := 13.0 - STAIR_DEPTH * (float(index) + 0.5)
		_solid_box(Vector3(GATE_WIDTH, top, STAIR_DEPTH), Vector3(0, top * 0.5, z), _stone, stairs)


func _build_gates() -> void:
	# The landing gate sits on the platform lip; the south gate guards the
	# descent point and opens onto a black tunnel mouth in the south wall.
	_build_gate("NorthGate", Vector3(0, 0, 13.0), PLATFORM_TOP + GATE_HEIGHT * 0.5)
	var south := _build_gate("SouthGate", Vector3(0, 0, -17.0), GATE_HEIGHT * 0.5)
	Geo.box(south, Vector3(GATE_WIDTH, GATE_HEIGHT, 0.07),
		Vector3(0, GATE_HEIGHT * 0.5, -0.75), _portal)
	Geo.box(south, Vector3(GATE_WIDTH + 0.6, 0.4, 0.5),
		Vector3(0, 0.2, -0.9), _dark_stone)


func _build_gate(gate_name: String, point: Vector3, center_y: float) -> StaticBody3D:
	var gate := StaticBody3D.new()
	gate.name = gate_name
	gate.position = point
	gate.collision_layer = 1
	gate.collision_mask = 0
	add_child(gate)

	var shape := CollisionShape3D.new()
	shape.name = "GateShape"
	var box := BoxShape3D.new()
	box.size = Vector3(GATE_WIDTH, GATE_HEIGHT, 0.35)
	shape.shape = box
	shape.position = Vector3(0, center_y, 0)
	shape.disabled = false
	gate.add_child(shape)
	_gate_shapes.append(shape)

	var bars := _portcullis(GATE_WIDTH, GATE_HEIGHT, _iron)
	bars.position = Vector3(0, center_y + GATE_HEIGHT * 0.5, 0)
	gate.add_child(bars)
	_gate_bars.append(bars)

	# Frame: two jamb posts plus a lintel sized to the gate head.
	var top := center_y + GATE_HEIGHT * 0.5
	var post_height := top + 0.9
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(0.8, post_height, 1.2),
			point + Vector3(side * (GATE_WIDTH * 0.5 + 0.4), post_height * 0.5, 0), _dark_stone, self)
	Geo.box(gate, Vector3(GATE_WIDTH + 2.0, 0.9, 1.4), Vector3(0, top + 0.45, 0), _dark_stone)
	return gate


func _portcullis(width: float, height: float, material: Material) -> MeshInstance3D:
	var bars := MeshInstance3D.new()
	bars.name = "GateBars"
	var top_rail := BoxMesh.new()
	top_rail.size = Vector3(width, 0.24, 0.36)
	bars.mesh = top_rail
	bars.material_override = material
	Geo.box(bars, Vector3(width, 0.24, 0.36), Vector3(0, -height, 0), material)
	var count := 9
	for index in count:
		var x := -width * 0.5 + width * (float(index) + 0.5) / float(count)
		Geo.box(bars, Vector3(0.14, height - 0.28, 0.16), Vector3(x, -height * 0.5, 0), material)
	# Spiked feet make the portcullis read as ironwork, not a slab.
	for index in count:
		var x := -width * 0.5 + width * (float(index) + 0.5) / float(count)
		Geo.sphere(bars, 0.13, Vector3(x, -height - 0.05, 0), material, Vector3(1.0, 0.7, 1.0))
	return bars


func _build_archways() -> void:
	var archways := Node3D.new()
	archways.name = "Archways"
	add_child(archways)
	for spawn in enemy_spawns:
		var spawn_position: Vector3 = spawn["position"]
		var facing: Vector3 = spawn["facing"]
		var inward := facing.normalized()
		var outward := -inward
		var center := Vector3(signf(spawn_position.x) * 13.5, 0.0, signf(spawn_position.z) * 10.5)
		var side := Vector3(0, 0, 1)

		var anchor := Node3D.new()
		anchor.name = "Archway_%d_%d" % [int(signf(center.x)), int(signf(center.z))]
		anchor.position = center
		archways.add_child(anchor)

		var depth := 2.4
		var width := 3.2
		var height := 5.6
		_solid_box(Vector3(0.5, height, width + 0.4),
			center + outward * (depth * 0.5 + 0.25) + Vector3(0, height * 0.5, 0), _dark_stone, archways)
		_solid_box(Vector3(depth, height, 0.5),
			center + side * (width * 0.5 + 0.25) + Vector3(0, height * 0.5, 0), _dark_stone, archways)
		_solid_box(Vector3(depth, height, 0.5),
			center - side * (width * 0.5 + 0.25) + Vector3(0, height * 0.5, 0), _dark_stone, archways)
		_solid_box(Vector3(depth + 1.1, 0.75, width + 1.1),
			center + Vector3(0, height + 0.3, 0), _dark_stone, archways)

		Geo.box(anchor, Vector3(0.07, height - 0.4, width - 0.1),
			outward * (depth * 0.5 + 0.02) + Vector3(0, (height - 0.4) * 0.5, 0), _portal)
		# Stepped header stone for a carved arch silhouette.
		Geo.box(anchor, Vector3(0.55, 0.4, width - 0.5),
			outward * (depth * 0.5) + Vector3(0, height - 0.08, 0), _stone)

		# Pair of dead braziers flanking the mouth; only one light per archway.
		var mouth := center + inward * 1.7
		for offset in [-1.35, 1.35]:
			_brazier(Vector3(mouth.x, 0.0, mouth.z + offset), false)
		var tint: Color = Color("ffb066") if center.z > 0.0 else Color("67c9d6")
		_add_omni(Vector3(mouth.x - inward.x * 0.2, 2.5, mouth.z), tint, 2.4, 11.0)


func _build_side_alcoves() -> void:
	for side in [-1.0, 1.0]:
		var center := Vector3(side * (CHAMBER_HALF - 0.06), 0, 0)
		var frame := Node3D.new()
		frame.name = "SideAlcove_%d" % int(side)
		add_child(frame)
		Geo.box(frame, Vector3(0.08, 3.6, 4.4), Vector3(center.x, 1.9, 0), _portal)
		Geo.box(frame, Vector3(0.55, 4.2, 0.55), Vector3(center.x - side * 0.28, 2.1, 2.5), _dark_stone)
		Geo.box(frame, Vector3(0.55, 4.2, 0.55), Vector3(center.x - side * 0.28, 2.1, -2.5), _dark_stone)
		Geo.box(frame, Vector3(0.55, 0.65, 5.6), Vector3(center.x - side * 0.28, 4.35, 0), _dark_stone)
		_brazier(Vector3(center.x - side * 1.4, 0.0, 1.9), false)
		_add_omni(Vector3(center.x - side * 1.0, 2.7, 0), Color("d8b47a"), 2.1, 10.5)


func _build_dais() -> void:
	var dais := Node3D.new()
	dais.name = "Dais"
	add_child(dais)
	var dais_mesh := Geo.cylinder(dais, 3.3, 3.3, 0.12, Vector3(0, 0.0, 0), _dark_stone, 48)
	dais_mesh.name = "DaisDisc"
	var rune := Geo.cylinder(dais, 2.9, 2.9, 0.012, Vector3(0, 0.062, 0), _stone, 48)
	rune.name = "DaisRing"
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flush rune stones ring the dais edge; they add no blocking lip.
	for index in 8:
		var angle := TAU * float(index) / 8.0
		Geo.box(dais, Vector3(0.55, 0.04, 0.55),
			Vector3(cos(angle) * 3.55, 0.02, sin(angle) * 3.55), _stone)


func _build_pillars() -> void:
	var pillars := Node3D.new()
	pillars.name = "Pillars"
	add_child(pillars)
	for index in PILLAR_COUNT:
		var angle := TAU * float(index) / float(PILLAR_COUNT) + PI / 6.0
		var point := Vector3(cos(angle) * PILLAR_RING, 0, sin(angle) * PILLAR_RING)
		var body := _solid_cylinder(PILLAR_RADIUS, PILLAR_HEIGHT, point, _stone, pillars)
		body.name = "Pillar_%d" % index
		Geo.cylinder(pillars, PILLAR_RADIUS + 0.24, PILLAR_RADIUS + 0.1, 0.5,
			point + Vector3(0, 0.25, 0), _dark_stone, 16)
		Geo.cylinder(pillars, PILLAR_RADIUS + 0.1, PILLAR_RADIUS + 0.26, 0.6,
			point + Vector3(0, PILLAR_HEIGHT - 0.3, 0), _dark_stone, 16)


func _build_cover() -> void:
	var cover := Node3D.new()
	cover.name = "Cover"
	add_child(cover)
	var barrier_size := Vector3(3.2, 1.15, 0.7)
	var barrier_positions: Array[Vector3] = [
		Vector3(0, 0, 4.9), Vector3(0, 0, -4.9),
	]
	for point in barrier_positions:
		_solid_box(barrier_size, point + Vector3(0, barrier_size.y * 0.5, 0), _stone, cover)
		Geo.box(cover, Vector3(barrier_size.x + 0.16, 0.12, barrier_size.z + 0.16),
			point + Vector3(0, barrier_size.y + 0.02, 0), _wood)
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(0.7, 1.15, 3.2),
			Vector3(side * 4.9, 0.575, 0), _stone, cover)
		Geo.box(cover, Vector3(0.86, 0.12, 3.36), Vector3(side * 4.9, 1.17, 0), _wood)

	var crate_points: Array[Vector3] = [
		Vector3(-8.0, 0, 7.6), Vector3(8.0, 0, 7.6),
		Vector3(-8.0, 0, -7.6), Vector3(8.0, 0, -7.6),
	]
	for index in range(crate_points.size()):
		var size := Vector3(1.15, 1.15, 1.15)
		var point := crate_points[index] + Vector3(0, size.y * 0.5, 0)
		var crate := _solid_box(size, point, _wood, cover)
		crate.name = "Crate_%d" % index
		Geo.box(cover, Vector3(size.x + 0.06, 0.1, size.z + 0.06),
			point + Vector3(0, size.y * 0.5, 0), _iron)


## A cool central pool keeps the dais and every approaching devil readable
## while the archways and sconces stay warm and directional.
func _build_fill_lighting() -> void:
	var crown := OmniLight3D.new()
	crown.name = "DaisFill"
	crown.position = Vector3(0, 9.0, 0)
	crown.light_color = Color("c4d4e8")
	crown.light_energy = 2.1
	crown.omni_range = 20.0
	crown.omni_attenuation = 1.1
	crown.shadow_enabled = false
	add_child(crown)
	for index in 4:
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var fill := OmniLight3D.new()
		fill.name = "ChamberFill_%d" % index
		fill.position = Vector3(cos(angle) * 8.2, 5.4, sin(angle) * 8.2)
		fill.light_color = Color("b6c6dc") if index % 2 == 0 else Color("e0c7a4")
		fill.light_energy = 1.35
		fill.omni_range = 13.5
		fill.omni_attenuation = 1.2
		fill.shadow_enabled = false
		add_child(fill)
	_lights += 5


func _build_torches() -> void:
	# Gate sconces (the archway and side-alcove lights are built with their art).
	for side in [-1.0, 1.0]:
		var north_point := Vector3(side * 4.8, 3.25, 16.9)
		_brazier(north_point, true)
		_add_omni(north_point + Vector3(0, 1.1, 0), Color("ffb066"), 2.4, 10.5)
		var south_point := Vector3(side * 4.8, 0.0, -17.4)
		_brazier(south_point, true)
		_add_omni(south_point + Vector3(0, 1.1, 0), Color("ff9a5c"), 2.3, 10.5)


func _brazier(point: Vector3, with_bowl: bool) -> void:
	Geo.cylinder(self, 0.16, 0.26, 0.75, point + Vector3(0, 0.375, 0), _iron, 10)
	if with_bowl:
		Geo.cylinder(self, 0.42, 0.22, 0.24, point + Vector3(0, 0.87, 0), _iron, 12)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.17
	flame_mesh.height = 0.5
	flame_mesh.radial_segments = 8
	flame_mesh.rings = 5
	flame.mesh = flame_mesh
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color("ffd39a")
	flame_material.emission_enabled = true
	flame_material.emission = Color("ff9b45")
	flame_material.emission_energy_multiplier = 2.4
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = flame_material
	flame.position = point + Vector3(0, 0.98, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)


func _add_omni(point: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = point
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	add_child(light)
	_lights += 1
	return light


func _solid_box(dimensions: Vector3, point: Vector3, material: Material, parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	Geo.box(body, dimensions, Vector3.ZERO, material)
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_solids += 1
	return body


func _solid_cylinder(radius: float, height: float, point: Vector3, material: Material, parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	Geo.cylinder(body, radius, radius * 0.94, height, Vector3(0, height * 0.5, 0), material, 24)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, height * 0.5, 0)
	body.add_child(collider)
	_solids += 1
	return body
