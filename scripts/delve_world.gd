extends Node3D
## Two delve rooms on one footprint: the sunken sanctuary with its dais and
## altar, and the claustrophobic ossuary pit of bone and charnel. Every
## descent rebuilds the room through apply_room(), so geometry, palette and FX
## are thrown away and re-authored instead of patched. Gameplay points (altar,
## rope, hole, chest, party marks) keep identical coordinates in both rooms;
## only the art, the ceiling and the colour cycle change.

const Geo = preload("res://scripts/geo.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const Pentagram = preload("res://scripts/delve_pentagram.gd")
const Beacon = preload("res://scripts/delve_beacon.gd")

const ROOM_SANCTUARY := "sanctuary"
const ROOM_OSSUARY := "ossuary"

const LIMIT := 17.0
const CHAMBER_HALF := 18.0
const WALL_THICKNESS := 2.0
const FLOOR_THICKNESS := 1.0
const CEILING_HIGH := 15.0
const CEILING_LOW := 10.5
const DROP_HEIGHT := 8.0
const DROP_APERTURE := 2.5
const PLATFORM_TOP := 3.2
const PLATFORM_SIZE := Vector3(12.0, PLATFORM_TOP, 4.5)
const PLATFORM_CENTER_Z := 15.25
const STAIR_WIDTH := 6.0
const STAIR_STEPS := 7
const STAIR_RISE := 0.4
const STAIR_DEPTH := 0.5
const PILLAR_COUNT := 6
const PILLAR_RADIUS := 0.9
const PILLAR_RING := 9.0
# The ossuary totems sit further out than the sanctuary pillars so the arena
# and the drop-to-charnel sightline stay open.
const TOTEM_RING := 11.2
const TOTEM_SHAFT_RADIUS := 0.5
const TOTEM_COLLIDER_RADIUS := 0.72
const TOTEM_TIERS := 15
const SPAWN_INNER_RING := 5.5
const SPAWN_OUTER_RING := 11.0
const SPAWN_CLEARANCE := 0.75
const PENTAGRAM_RADIUS := 3.4
const BEACON_RADIUS := 0.85

var room_kind := ROOM_SANCTUARY
var cycle := 1
var altar_position: Vector3 = Vector3(0, 0.05, -4.0)
var rope_position: Vector3 = Vector3(5.2, 0.05, 3.0)
var hole_position: Vector3 = Vector3(-5.2, 0.05, 3.0)
var hole_radius: float = 1.05
var chest_position: Vector3 = Vector3(0, 0.06, 0)
var drop_center: Vector3 = Vector3(0, 8.0, 0)
var player_spawns: Array[Vector3] = []
var enemy_spawns: Array[Dictionary] = [
	{"position": Vector3(12.8, 0.05, 10.5), "facing": Vector3(-1, 0, 0)},
	{"position": Vector3(-12.8, 0.05, 10.5), "facing": Vector3(1, 0, 0)},
	{"position": Vector3(12.8, 0.05, -10.5), "facing": Vector3(-1, 0, 0)},
	{"position": Vector3(-12.8, 0.05, -10.5), "facing": Vector3(1, 0, 0)},
]
var spawn_points: Array[Vector3] = []
var sealed: bool = false
var rope_lowered: bool = false
var hole_open: bool = false
var generation_stats: Dictionary = {}

var _theme: Dictionary = {}
var _ceiling: float = CEILING_HIGH
var _rock: StandardMaterial3D
var _stone: StandardMaterial3D
var _dark_stone: StandardMaterial3D
var _wall: StandardMaterial3D
var _wood: StandardMaterial3D
var _iron: StandardMaterial3D
var _bone: StandardMaterial3D
var _bone_dark: StandardMaterial3D
var _gore: StandardMaterial3D
var _gore_rim: StandardMaterial3D
var _flesh: StandardMaterial3D
var _charnel_floor: StandardMaterial3D
var _portal: StandardMaterial3D
var _flame_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _seal_material: StandardMaterial3D
var _roots: Array[Node] = []
var _seal_barriers: Array[MeshInstance3D] = []
var _rope_pivot: Node3D
var _rope_tween: Tween
var _hole_plate: Node3D
var _hole_plate_base: Vector3 = Vector3.ZERO
var _hole_void: MeshInstance3D
var _hole_tween: Tween
var _pentagram
var _beacons: Dictionary = {}
var _beacon_on: Dictionary = {"altar": false, "rope": false, "hole": false}
var _pentagram_active := false
var _solids := 0
var _lights := 0
var _torches := 0
var _built := false


func _ready() -> void:
	# Geometry belongs to apply_room(); _ready only prepares the materials.
	_ensure_materials()


## False until apply_room() has authored this world's geometry. A controller
## must build the room before it draws a frame, and a client's first run state
## only has to rebuild when the host is on a different room or cycle.
func is_built() -> bool:
	return _built


## Rebuilds the whole room for `kind` at palette `room_cycle`. Idempotent: the
## previous build is freed, every reference and flag is reset, and the new
## room is authored from scratch. The room always lands in its resting state
## (unsealed, rope up, hatch closed, pentagram dark, beacons off).
func apply_room(kind: String, room_cycle: int) -> void:
	_clear_room()
	room_kind = ROOM_OSSUARY if kind == ROOM_OSSUARY else ROOM_SANCTUARY
	cycle = maxi(1, room_cycle)
	_ceiling = CEILING_LOW if room_kind == ROOM_OSSUARY else CEILING_HIGH
	_ensure_materials()
	_apply_theme(_theme_for(room_kind, cycle))
	player_spawns = _player_spawn_list()
	spawn_points = _build_spawn_points()
	_build_environment()
	if room_kind == ROOM_OSSUARY:
		_build_ossuary()
	else:
		_build_sanctuary()
	_build_pentagram()
	_build_beacons()
	_refresh_generation_stats()
	set_sealed(false)
	set_rope_lowered(false, true)
	set_hole_open(false, true)
	set_pentagram(false, 0.0)
	set_beacons(false, false, false)
	_built = true


func room_title() -> String:
	return "THE OSSUARY PIT" if room_kind == ROOM_OSSUARY else "THE SUNKEN DELVE"


func has_altar() -> bool:
	return room_kind == ROOM_SANCTUARY


func palette() -> Dictionary:
	return _theme


func set_pentagram(active: bool, intensity: float = 1.0) -> void:
	_pentagram_active = active
	if _pentagram != null and is_instance_valid(_pentagram):
		_pentagram.set_state(active, intensity)


func is_pentagram_active() -> bool:
	return _pentagram_active


func set_ritual(active: bool, progress: float = 0.0) -> void:
	if _pentagram != null and is_instance_valid(_pentagram):
		_pentagram.set_ritual(active, clampf(progress, 0.0, 1.0))


func set_beacons(altar_on: bool, rope_on: bool, hole_on: bool) -> void:
	_beacon_on = {"altar": altar_on, "rope": rope_on, "hole": hole_on}
	for kind in _beacon_on:
		if not _beacons.has(kind):
			continue
		var beacon = _beacons[kind]
		if beacon != null and is_instance_valid(beacon):
			beacon.set_active(bool(_beacon_on[kind]))


func beacon_active(kind: String) -> bool:
	return bool(_beacon_on.get(kind, false))


## Sealed only lights the emissive barrier in each of the four archway mouths:
## the room has no gate geometry and no gate colliders.
func set_sealed(value: bool) -> void:
	sealed = value
	for plane in _seal_barriers:
		if plane != null and is_instance_valid(plane):
			plane.visible = value


## The rope grows out of the ceiling over 0.7 s once the depth is cleared.
func set_rope_lowered(value: bool, instant: bool = false) -> void:
	if value == rope_lowered:
		return
	rope_lowered = value
	if _rope_pivot == null or not is_instance_valid(_rope_pivot):
		return
	_kill_rope_tween()
	if value:
		_rope_pivot.visible = true
		if instant or not is_inside_tree():
			_rope_pivot.scale = Vector3.ONE
			return
		_rope_pivot.scale = Vector3(1.0, 0.02, 1.0)
		_rope_tween = create_tween()
		_rope_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_rope_tween.tween_property(_rope_pivot, "scale", Vector3.ONE, 0.7)
	else:
		_rope_pivot.scale = Vector3(1.0, 0.02, 1.0)
		_rope_pivot.visible = false


func is_rope_lowered() -> bool:
	return rope_lowered


## Opens the floor plate onto the shaft that leads one depth down.
func set_hole_open(value: bool, instant: bool = false) -> void:
	if value == hole_open:
		return
	hole_open = value
	if _hole_plate == null or not is_instance_valid(_hole_plate):
		return
	_kill_hole_tween()
	if _hole_void != null and is_instance_valid(_hole_void):
		_hole_void.visible = value
	var target_position := _hole_plate_base + (Vector3(-2.35, 0.16, 0.0) if value else Vector3.ZERO)
	var target_angle := -1.1 if value else 0.0
	if instant or not is_inside_tree():
		_hole_plate.position = target_position
		_hole_plate.rotation.z = target_angle
		return
	_hole_tween = create_tween()
	_hole_tween.set_parallel(true)
	_hole_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hole_tween.tween_property(_hole_plate, "position", target_position, 0.4)
	_hole_tween.tween_property(_hole_plate, "rotation:z", target_angle, 0.4)


func is_hole_open() -> bool:
	return hole_open


## True while a body standing on the chamber floor is inside the open shaft.
func is_in_hole(point: Vector3) -> bool:
	if not hole_open:
		return false
	var dx := point.x - hole_position.x
	var dz := point.z - hole_position.z
	return dx * dx + dz * dz <= hole_radius * hole_radius and point.y <= 1.2


func _clear_room() -> void:
	_kill_tweens()
	for root in _roots:
		if root == null or not is_instance_valid(root):
			continue
		if root.get_parent() == self:
			remove_child(root)
		root.free()
	_roots.clear()
	_seal_barriers.clear()
	_beacons.clear()
	_rope_pivot = null
	_hole_plate = null
	_hole_void = null
	_pentagram = null
	_solids = 0
	_lights = 0
	_torches = 0
	sealed = false
	rope_lowered = false
	hole_open = false
	_pentagram_active = false
	_beacon_on = {"altar": false, "rope": false, "hole": false}
	spawn_points.clear()
	generation_stats = {}


func _kill_tweens() -> void:
	_kill_rope_tween()
	_kill_hole_tween()


func _kill_rope_tween() -> void:
	if _rope_tween != null and _rope_tween.is_valid():
		_rope_tween.kill()
	_rope_tween = null


func _kill_hole_tween() -> void:
	if _hole_tween != null and _hole_tween.is_valid():
		_hole_tween.kill()
	_hole_tween = null


func _ensure_materials() -> void:
	if _theme.is_empty():
		_theme = _theme_for(ROOM_SANCTUARY, 1)
	if _rock != null:
		return
	_rock = TextureLibrary.rock_material()
	_wood = TextureLibrary.building_material("wood", Color("6d5741"))
	_iron = Geo.material(Color("2a2f34"), 0.65, 0.42)
	_bone = Geo.material(Color("d8cbab"), 0.0, 0.58)
	_bone_dark = Geo.material(Color("54483d"), 0.0, 0.72)
	_gore = Geo.material(Color("4a0f14"), 0.0, 0.32)
	_gore_rim = Geo.material(Color("1e0709"), 0.0, 0.85)
	_flesh = Geo.material(Color("8a4640"), 0.0, 0.92)
	_portal = StandardMaterial3D.new()
	_portal.albedo_color = Color(0.012, 0.016, 0.022)
	_portal.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_portal.disable_receive_shadows = true
	_apply_palette()


func _apply_theme(theme: Dictionary) -> void:
	_theme = theme
	_apply_palette()


## Palette-driven materials. Shared textures keep their cache; every emissive
## surface is authored per build so a new cycle never tints the old room.
func _apply_palette() -> void:
	_stone = TextureLibrary.building_material("stone", _theme["stone"])
	_dark_stone = TextureLibrary.building_material("stone", _theme["dark"])
	_charnel_floor = TextureLibrary.building_material("stone", _theme["floor"])
	var wall_tint := _rock.duplicate() as StandardMaterial3D
	wall_tint.albedo_color = _theme["wall"]
	_wall = wall_tint
	var accent: Color = _theme["accent"]
	var torch: Color = _theme["torch"]
	_flame_material = StandardMaterial3D.new()
	_flame_material.albedo_color = torch.lerp(Color.WHITE, 0.35)
	_flame_material.emission_enabled = true
	_flame_material.emission = torch
	_flame_material.emission_energy_multiplier = 2.4
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.disable_receive_shadows = true
	_accent_material = _emissive(accent, 1.9)
	_seal_material = _emissive(accent, 1.5, 0.16)


func _emissive(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.disable_receive_shadows = true
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _theme_for(kind: String, theme_cycle: int) -> Dictionary:
	var themes: Array[Dictionary] = _themes(kind)
	var index := posmod(theme_cycle - 1, themes.size())
	return themes[index]


func _themes(kind: String) -> Array[Dictionary]:
	var themes: Array[Dictionary] = []
	if kind == ROOM_OSSUARY:
		themes.append({
			"name": "Flesh Charnel",
			"accent": Color("c9d67a"),
			"fog": Color("2a2a1e"),
			"stone": Color("8f8873"),
			"dark": Color("4a4738"),
			"floor": Color("4a3a33"),
			"wall": Color("b9ac93"),
			"ambient": Color("6b6a4c"),
			"torch": Color("ffbe6a"),
			"sky": Color("070705"),
			"rope": Color("ffc36b"),
			"hole": Color("ff4d5a"),
			"fog_density": 0.018,
		})
		themes.append({
			"name": "Blood Reliquary",
			"accent": Color("ff6a72"),
			"fog": Color("2c1216"),
			"stone": Color("8b6f68"),
			"dark": Color("4a2b2c"),
			"floor": Color("432523"),
			"wall": Color("b08d84"),
			"ambient": Color("7a3f43"),
			"torch": Color("ff8a45"),
			"sky": Color("0a0405"),
			"rope": Color("ffc36b"),
			"hole": Color("ff3b52"),
			"fog_density": 0.02,
		})
		return themes
	themes.append({
		"name": "Cold Reliquary",
		"accent": Color("79e3d3"),
		"fog": Color("18222c"),
		"stone": Color("69736c"),
		"dark": Color("3a423f"),
		"floor": Color("2c3230"),
		"wall": Color("55605c"),
		"ambient": Color("556273"),
		"torch": Color("ffb066"),
		"sky": Color("04060a"),
		"rope": Color("ffc36b"),
		"hole": Color("ff4d5a"),
		"fog_density": 0.008,
	})
	themes.append({
		"name": "Ember Vigil",
		"accent": Color("ff7a4d"),
		"fog": Color("2a1712"),
		"stone": Color("75655a"),
		"dark": Color("45322a"),
		"floor": Color("382a24"),
		"wall": Color("6b5a4f"),
		"ambient": Color("7a4a38"),
		"torch": Color("ff8a3d"),
		"sky": Color("090402"),
		"rope": Color("ffd27a"),
		"hole": Color("ff3f58"),
		"fog_density": 0.009,
	})
	return themes


func _refresh_generation_stats() -> void:
	generation_stats = {
		"room": room_kind,
		"cycle": cycle,
		"solids": _solids,
		"spawn_points": spawn_points.size(),
		"beacons": _beacons.size(),
		"pentagram": 1 if _pentagram != null else 0,
		"gate": false,
		"player_spawns": player_spawns.size(),
		"enemy_spawns": enemy_spawns.size(),
		"ceiling_height": _ceiling,
		"pillars": PILLAR_COUNT,
		"torches": _torches,
		"lights": _lights,
		"limit": LIMIT,
	}


func _root(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	_roots.append(root)
	return root


func _own(node: Node) -> Node:
	add_child(node)
	_roots.append(node)
	return node


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _theme["sky"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _theme["ambient"]
	environment.ambient_light_energy = 0.58
	environment.ambient_light_sky_contribution = 0.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = _theme["fog"]
	environment.fog_light_energy = 0.7
	environment.fog_density = _theme["fog_density"]
	environment.fog_sky_affect = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.25
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.05
	environment.adjustment_contrast = 1.08
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.12
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_strength = 1.0
	environment.glow_hdr_threshold = 1.1
	environment.set_glow_level(1, 0.55)
	environment.set_glow_level(3, 0.4)
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	_own(world_environment)


func _build_shell(wall_material: Material, floor_material: Material, stone_ribs: bool) -> void:
	var shell := _root("Chamber")
	var span := CHAMBER_HALF * 2.0 + WALL_THICKNESS * 2.0
	var floor_body := _solid_box(Vector3(span, FLOOR_THICKNESS, span),
		Vector3(0, -FLOOR_THICKNESS * 0.5, 0), floor_material, shell)
	floor_body.name = "Floor"
	_solid_box(Vector3(span, _ceiling, WALL_THICKNESS),
		Vector3(0, _ceiling * 0.5, CHAMBER_HALF + WALL_THICKNESS * 0.5), wall_material, shell).name = "NorthWall"
	_solid_box(Vector3(span, _ceiling, WALL_THICKNESS),
		Vector3(0, _ceiling * 0.5, -CHAMBER_HALF - WALL_THICKNESS * 0.5), wall_material, shell).name = "SouthWall"
	_solid_box(Vector3(WALL_THICKNESS, _ceiling, CHAMBER_HALF * 2.0),
		Vector3(CHAMBER_HALF + WALL_THICKNESS * 0.5, _ceiling * 0.5, 0), wall_material, shell).name = "EastWall"
	_solid_box(Vector3(WALL_THICKNESS, _ceiling, CHAMBER_HALF * 2.0),
		Vector3(-CHAMBER_HALF - WALL_THICKNESS * 0.5, _ceiling * 0.5, 0), wall_material, shell).name = "WestWall"
	if not stone_ribs:
		return
	# Stone ribs give the sanctuary walls a built, pillared rhythm.
	var ribs := _root("WallRibs")
	for index in 5:
		var z := -14.0 + float(index) * 7.0
		for side in [-1.0, 1.0]:
			Geo.box(ribs, Vector3(0.45, _ceiling, 0.7),
				Vector3(side * (CHAMBER_HALF - 0.22), _ceiling * 0.5, z), _dark_stone)
	for index in 3:
		var x := -12.0 + float(index) * 12.0
		for side in [-1.0, 1.0]:
			Geo.box(ribs, Vector3(0.7, _ceiling, 0.45),
				Vector3(x, _ceiling * 0.5, side * (CHAMBER_HALF - 0.22)), _dark_stone)


func _build_ceiling() -> void:
	var ceiling := _root("Ceiling")
	var hole := DROP_APERTURE
	var outside := CHAMBER_HALF + WALL_THICKNESS
	var band := (outside - hole) * 0.5
	var band_center := hole + band
	_solid_box(Vector3(outside * 2.0, 0.9, band * 2.0),
		Vector3(0, _ceiling + 0.45, band_center), _rock, ceiling)
	_solid_box(Vector3(outside * 2.0, 0.9, band * 2.0),
		Vector3(0, _ceiling + 0.45, -band_center), _rock, ceiling)
	_solid_box(Vector3(band * 2.0, 0.9, hole * 2.0),
		Vector3(band_center, _ceiling + 0.45, 0), _rock, ceiling)
	_solid_box(Vector3(band * 2.0, 0.9, hole * 2.0),
		Vector3(-band_center, _ceiling + 0.45, 0), _rock, ceiling)

	# Visual drop shaft above the aperture. No collision so a drop never snags.
	var shaft := Node3D.new()
	shaft.name = "DropShaft"
	ceiling.add_child(shaft)
	var lip := 3.0
	for side in [-1.0, 1.0]:
		Geo.box(shaft, Vector3(0.6, DROP_HEIGHT, lip * 2.0),
			Vector3(side * (hole + 0.3), _ceiling + DROP_HEIGHT * 0.5, 0), _rock)
		Geo.box(shaft, Vector3(lip * 2.0, DROP_HEIGHT, 0.6),
			Vector3(0, _ceiling + DROP_HEIGHT * 0.5, side * (hole + 0.3)), _rock)

	var accent: Color = _theme["accent"]
	var shaft_material := _emissive(accent, 0.2, 0.05)
	var light_shaft := MeshInstance3D.new()
	light_shaft.name = "LightShaft"
	var cone := CylinderMesh.new()
	cone.top_radius = hole * 0.9
	cone.bottom_radius = hole * 1.9
	cone.height = _ceiling
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	light_shaft.mesh = cone
	light_shaft.material_override = shaft_material
	light_shaft.position = Vector3(0, _ceiling * 0.5, 0)
	light_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.add_child(light_shaft)

	var spot := SpotLight3D.new()
	spot.name = "DropShaftLight"
	spot.position = Vector3(0, _ceiling - 0.4, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = accent.lerp(Color.WHITE, 0.55)
	spot.light_energy = 3.2
	spot.spot_range = _ceiling * 1.6
	spot.spot_angle = 40.0
	spot.shadow_enabled = true
	shaft.add_child(spot)
	_lights += 1


func _build_archways() -> void:
	var archways := _root("Archways")
	for entry in _archway_centers():
		var center: Vector3 = entry["center"]
		var inward: Vector3 = entry["inward"]
		var outward := -inward
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
		Geo.box(anchor, Vector3(0.55, 0.4, width - 0.5),
			outward * (depth * 0.5) + Vector3(0, height - 0.08, 0), _stone)

		var mouth := center + inward * 1.7
		for offset in [-1.35, 1.35]:
			_brazier(archways, Vector3(mouth.x, 0.0, mouth.z + offset), false)
		_add_omni(archways, Vector3(mouth.x, 2.5, mouth.z), _theme["torch"], 2.3, 11.0)


## Emissive barriers in the four mouths. `set_sealed` only flips their
## visibility, so sealing never adds geometry or colliders.
func _build_seals() -> void:
	var seals := _root("Seals")
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 5.1)
	for entry in _archway_centers():
		var center: Vector3 = entry["center"]
		var inward: Vector3 = entry["inward"]
		var plane := MeshInstance3D.new()
		plane.name = "Seal_%d_%d" % [int(signf(center.x)), int(signf(center.z))]
		plane.mesh = quad
		plane.material_override = _seal_material
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plane.transform = Transform3D(Basis.looking_at(-inward, Vector3.UP),
			center + inward * 0.35 + Vector3(0, 2.6, 0))
		plane.visible = false
		seals.add_child(plane)
		_seal_barriers.append(plane)


func _archway_centers() -> Array[Dictionary]:
	var centers: Array[Dictionary] = []
	for spawn in enemy_spawns:
		var position: Vector3 = spawn["position"]
		var facing: Vector3 = spawn["facing"]
		centers.append({
			"center": Vector3(signf(position.x) * 13.5, 0.0, signf(position.z) * 10.5),
			"inward": facing.normalized(),
		})
	return centers


func _player_spawn_list() -> Array[Vector3]:
	var marks: Array[Vector3] = []
	if room_kind == ROOM_OSSUARY:
		for index in 4:
			var angle := TAU * (float(index) + 0.5) / 4.0
			marks.append(Vector3(cos(angle) * 4.6, 0.05, sin(angle) * 4.6))
		return marks
	marks.append(Vector3(-4.5, 3.28, 15.2))
	marks.append(Vector3(-1.5, 3.28, 15.2))
	marks.append(Vector3(1.5, 3.28, 15.2))
	marks.append(Vector3(4.5, 3.28, 15.2))
	return marks


## Wave-spawn candidates on the chamber floor: an inner ring around the dais
## and an outer ring under the vaults, filtered clear of every solid and of the
## rope/hole/altar interaction radii. Both rooms share the same set.
func _build_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var candidates: Array[Vector3] = []
	for index in 16:
		var angle := TAU * (float(index) + 0.5) / 16.0
		candidates.append(Vector3(cos(angle) * SPAWN_INNER_RING, 0.05, sin(angle) * SPAWN_INNER_RING))
	for index in 32:
		var angle := TAU * (float(index) + 0.5) / 32.0
		candidates.append(Vector3(cos(angle) * SPAWN_OUTER_RING, 0.05, sin(angle) * SPAWN_OUTER_RING))
	for point in candidates:
		if _spawn_clear(point):
			points.append(point)
	if points.size() >= 12:
		return points
	# Safety net if the art moves: scan a grid until the minimum is met.
	var radii: Array[float] = [4.5, 6.0, 7.5, 10.0, 12.5]
	for radius in radii:
		for index in 12:
			var angle := TAU * float(index) / 12.0
			var candidate := Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
			if _spawn_clear(candidate) and not points.has(candidate):
				points.append(candidate)
	return points


func _spawn_clear(point: Vector3) -> bool:
	if absf(point.x) > 15.0 or absf(point.z) > 15.0:
		return false
	var flat := Vector2(point.x, point.z)
	# The landing platform and its stairs only exist in the sanctuary, but the
	# shared spawn ring must stay clear of both rooms' footprints.
	if Rect2(-6.0, 13.0, PLATFORM_SIZE.x, PLATFORM_SIZE.z).grow(0.9).has_point(flat):
		return false
	if Rect2(-STAIR_WIDTH * 0.5, 9.5, STAIR_WIDTH, 3.5).grow(0.9).has_point(flat):
		return false
	for rect in _cover_rects():
		if rect.grow(SPAWN_CLEARANCE).has_point(flat):
			return false
	# Sanctuary pillars or ossuary totems, whichever ring this room actually has.
	var ring_radius := TOTEM_RING if room_kind == ROOM_OSSUARY else PILLAR_RING
	var ring_solid := TOTEM_COLLIDER_RADIUS if room_kind == ROOM_OSSUARY else PILLAR_RADIUS
	for index in PILLAR_COUNT:
		var angle := TAU * float(index) / float(PILLAR_COUNT) + PI / 6.0
		if flat.distance_to(Vector2(cos(angle), sin(angle)) * ring_radius) < ring_solid + SPAWN_CLEARANCE:
			return false
	var avoid := hole_radius + SPAWN_CLEARANCE + 0.3
	if flat.distance_to(Vector2(rope_position.x, rope_position.z)) < avoid:
		return false
	if flat.distance_to(Vector2(hole_position.x, hole_position.z)) < avoid:
		return false
	if flat.distance_to(Vector2(altar_position.x, altar_position.z)) < 2.0:
		return false
	for entry in _archway_centers():
		var center: Vector3 = entry["center"]
		if flat.distance_to(Vector2(center.x, center.z)) < 2.4:
			return false
	return true


## Cover footprints, expressed in the XZ floor plane: four barriers on the axes
## and four cache stacks on the diagonals. Both rooms reuse them so their
## colliders and spawn clearance stay identical.
func _cover_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(-1.6, 4.55, 3.2, 0.7),
		Rect2(-1.6, -5.25, 3.2, 0.7),
		Rect2(4.55, -1.6, 0.7, 3.2),
		Rect2(-5.25, -1.6, 0.7, 3.2),
		Rect2(-8.575, 7.025, 1.15, 1.15),
		Rect2(7.425, 7.025, 1.15, 1.15),
		Rect2(-8.575, -8.175, 1.15, 1.15),
		Rect2(7.425, -8.175, 1.15, 1.15),
	]
	return rects


func _build_sanctuary() -> void:
	_build_shell(_stone, _rock, true)
	_build_ceiling()
	_build_landing_platform()
	_build_archways()
	_build_side_alcoves()
	_build_dais()
	_build_altar()
	_build_rope()
	_build_hole()
	_build_pillars()
	_build_cover()
	_build_torches()
	_build_fill_lighting()
	_build_seals()


func _build_landing_platform() -> void:
	var platform := _root("NorthPlatform")
	_solid_box(PLATFORM_SIZE, Vector3(0, PLATFORM_TOP * 0.5, PLATFORM_CENTER_Z), _stone, platform).name = "PlatformBlock"
	Geo.box(platform, Vector3(11.7, 0.06, 4.2), Vector3(0, 3.22, PLATFORM_CENTER_Z), _wood)
	for side in [-1.0, 1.0]:
		Geo.box(platform, Vector3(0.16, 0.9, 4.2), Vector3(side * 5.85, 3.65, PLATFORM_CENTER_Z), _wood)
		for index in 3:
			Geo.box(platform, Vector3(0.2, 1.0, 0.2),
				Vector3(side * 5.85, 3.7, 13.2 + float(index) * 1.9), _wood)
	Geo.box(platform, Vector3(11.7, 0.16, 0.16), Vector3(0, 4.1, 17.25), _wood)
	for index in 5:
		Geo.box(platform, Vector3(0.2, 1.0, 0.2),
			Vector3(-5.4 + float(index) * 2.7, 3.7, 17.25), _wood)

	# Landing runes mark the four drop points without colliding.
	for spawn in player_spawns:
		var ring := Geo.cylinder(platform, 0.55, 0.55, 0.012,
			Vector3(spawn.x, 3.256, spawn.z), _accent_material, 24)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var stairs := Node3D.new()
	stairs.name = "Stairs"
	platform.add_child(stairs)
	for index in STAIR_STEPS:
		var top := PLATFORM_TOP - STAIR_RISE * float(index + 1)
		var z := 13.0 - STAIR_DEPTH * (float(index) + 0.5)
		_solid_box(Vector3(STAIR_WIDTH, top, STAIR_DEPTH), Vector3(0, top * 0.5, z), _stone, stairs)


func _build_side_alcoves() -> void:
	var alcoves := _root("SideAlcoves")
	for side in [-1.0, 1.0]:
		var center := Vector3(side * (CHAMBER_HALF - 0.06), 0, 0)
		var frame := Node3D.new()
		frame.name = "SideAlcove_%d" % int(side)
		alcoves.add_child(frame)
		Geo.box(frame, Vector3(0.08, 3.6, 4.4), Vector3(center.x, 1.9, 0), _portal)
		Geo.box(frame, Vector3(0.55, 4.2, 0.55), Vector3(center.x - side * 0.28, 2.1, 2.5), _dark_stone)
		Geo.box(frame, Vector3(0.55, 4.2, 0.55), Vector3(center.x - side * 0.28, 2.1, -2.5), _dark_stone)
		Geo.box(frame, Vector3(0.55, 0.65, 5.6), Vector3(center.x - side * 0.28, 4.35, 0), _dark_stone)
		_brazier(alcoves, Vector3(center.x - side * 1.4, 0.0, 1.9), false)
		_add_omni(alcoves, Vector3(center.x - side * 1.0, 2.7, 0), _theme["torch"], 2.0, 10.5)


func _build_dais() -> void:
	var dais := _root("Dais")
	var disc := Geo.cylinder(dais, 3.3, 3.3, 0.12, Vector3.ZERO, _dark_stone, 48)
	disc.name = "DaisDisc"
	# A thin inlaid rune ring, not a glowing disc: the pentagram owns the glow.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 2.86
	ring_mesh.outer_radius = 2.94
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	var rune := MeshInstance3D.new()
	rune.name = "DaisRing"
	rune.mesh = ring_mesh
	rune.material_override = _accent_material
	rune.position = Vector3(0, 0.062, 0)
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dais.add_child(rune)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		Geo.box(dais, Vector3(0.55, 0.04, 0.55),
			Vector3(cos(angle) * 3.55, 0.02, sin(angle) * 3.55), _stone)


func _build_altar() -> void:
	var altar := Node3D.new()
	altar.name = "Altar"
	altar.position = altar_position
	_own(altar)
	var body := _solid_box(Vector3(1.5, 0.95, 1.0), Vector3(0, 0.475, 0), _dark_stone, altar)
	body.name = "AltarBlock"
	Geo.box(altar, Vector3(1.66, 0.14, 1.0), Vector3(0, 1.02, 0), _stone)
	Geo.box(altar, Vector3(1.34, 0.08, 0.86), Vector3(0, 1.12, 0), _dark_stone)
	for side in [-1.0, 1.0]:
		Geo.box(altar, Vector3(0.18, 0.34, 0.72), Vector3(side * 0.48, 1.28, 0), _stone)

	var rune := Geo.cylinder(altar, 0.42, 0.42, 0.02, Vector3(0, 1.17, 0), _accent_material, 24)
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rune_points: Array[Vector3] = [
		Vector3(-0.34, 0.6, 0.505), Vector3(0.0, 0.6, 0.505), Vector3(0.34, 0.6, 0.505),
	]
	for offset in rune_points:
		Geo.box(altar, Vector3(0.1, 0.5, 0.03), offset, _accent_material)
	_add_omni(altar, altar_position + Vector3(0, 1.7, 0), _theme["accent"], 1.5, 6.5)


func _build_rope() -> void:
	_rope_pivot = Node3D.new()
	_rope_pivot.name = "Rope"
	_rope_pivot.position = Vector3(rope_position.x, _ceiling - 0.2, rope_position.z)
	_own(_rope_pivot)
	var rope_material := Geo.material(Color("9a7b52"), 0.0, 0.85)
	var length := _ceiling - 1.05
	Geo.cylinder(_rope_pivot, 0.07, 0.07, length, Vector3(0, -length * 0.5, 0), rope_material, 10)
	var knots := int(length / 1.4)
	for index in knots:
		Geo.cylinder(_rope_pivot, 0.115, 0.115, 0.12,
			Vector3(0, -0.55 - float(index) * 1.4, 0), rope_material, 10)
	Geo.sphere(_rope_pivot, 0.16, Vector3(0, -length, 0), rope_material)
	_rope_pivot.scale = Vector3(1.0, 0.02, 1.0)
	_rope_pivot.visible = false


func _build_hole() -> void:
	var hole := Node3D.new()
	hole.name = "FloorHole"
	hole.position = hole_position
	_own(hole)
	var void_material := StandardMaterial3D.new()
	void_material.albedo_color = Color(0.004, 0.005, 0.007)
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	void_material.disable_receive_shadows = true
	_hole_void = Geo.cylinder(hole, hole_radius, hole_radius, 0.015,
		Vector3(0, 0.02, 0), void_material, 32)
	_hole_void.visible = false
	for index in 12:
		var angle := TAU * float(index) / 12.0
		Geo.box(hole, Vector3(0.34, 0.1, 0.3),
			Vector3(cos(angle) * (hole_radius + 0.13), 0.05, sin(angle) * (hole_radius + 0.13)), _stone)

	_hole_plate = Node3D.new()
	_hole_plate.name = "HolePlate"
	_hole_plate_base = Vector3(0, 0.09, 0)
	_hole_plate.position = _hole_plate_base
	hole.add_child(_hole_plate)
	Geo.cylinder(_hole_plate, hole_radius, hole_radius, 0.08, Vector3.ZERO, _dark_stone, 32)
	Geo.cylinder(_hole_plate, 0.34, 0.34, 0.03, Vector3(0, 0.05, 0), _iron, 16)
	var plate_rune := Geo.box(_hole_plate, Vector3(0.7, 0.02, 0.08), Vector3(0, 0.05, 0), _accent_material)
	plate_rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_pentagram() -> void:
	_pentagram = Pentagram.new()
	_pentagram.name = "Pentagram"
	_pentagram.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0))
	_own(_pentagram)
	var accent: Color = _theme["accent"]
	_pentagram.configure(PENTAGRAM_RADIUS, accent, 0.08 if room_kind == ROOM_SANCTUARY else 0.02)
	_pentagram.set_state(false, 0.0)
	_pentagram.set_ritual(false, 0.0)


func _build_beacons() -> void:
	var specs: Array[Dictionary] = [
		{"kind": "altar", "name": "BeaconAltar", "position": altar_position, "title": "ALTAR", "color": _theme["accent"]},
		{"kind": "rope", "name": "BeaconRope", "position": rope_position, "title": "ROPE OUT", "color": _theme["rope"]},
		{"kind": "hole", "name": "BeaconHole", "position": hole_position, "title": "DESCEND", "color": _theme["hole"]},
	]
	for spec in specs:
		var beacon = Beacon.new()
		beacon.name = str(spec["name"])
		var anchor: Vector3 = spec["position"]
		beacon.transform = Transform3D(Basis.IDENTITY, anchor)
		_own(beacon)
		beacon.configure(spec["color"], BEACON_RADIUS, _ceiling - 0.8, str(spec["title"]))
		beacon.set_active(false)
		_beacons[str(spec["kind"])] = beacon


func _build_pillars() -> void:
	var pillars := _root("Pillars")
	for index in PILLAR_COUNT:
		var angle := TAU * float(index) / float(PILLAR_COUNT) + PI / 6.0
		var point := Vector3(cos(angle) * PILLAR_RING, 0, sin(angle) * PILLAR_RING)
		var body := _solid_cylinder(PILLAR_RADIUS, _ceiling, point, _stone, pillars)
		body.name = "Pillar_%d" % index
		Geo.cylinder(pillars, PILLAR_RADIUS + 0.24, PILLAR_RADIUS + 0.1, 0.5,
			point + Vector3(0, 0.25, 0), _dark_stone, 16)
		Geo.cylinder(pillars, PILLAR_RADIUS + 0.1, PILLAR_RADIUS + 0.26, 0.6,
			point + Vector3(0, _ceiling - 0.3, 0), _dark_stone, 16)


func _build_cover() -> void:
	var cover := _root("Cover")
	var rects := _cover_rects()
	for index in rects.size():
		var rect := rects[index]
		var point := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
		var size := Vector3(rect.size.x, 1.15, rect.size.y)
		if index < 4:
			_solid_box(size, point + Vector3(0, size.y * 0.5, 0), _stone, cover)
			Geo.box(cover, Vector3(size.x + 0.16, 0.12, size.z + 0.16),
				point + Vector3(0, size.y + 0.02, 0), _wood)
		else:
			var crate := _solid_box(size, point + Vector3(0, size.y * 0.5, 0), _wood, cover)
			crate.name = "Crate_%d" % (index - 4)
			Geo.box(cover, Vector3(size.x + 0.06, 0.1, size.z + 0.06),
				point + Vector3(0, size.y + 0.02, 0), _iron)


func _build_torches() -> void:
	var torches := _root("Torches")
	for side in [-1.0, 1.0]:
		var north_point := Vector3(side * 4.8, 3.25, 16.9)
		_brazier(torches, north_point, true)
		_add_omni(torches, north_point + Vector3(0, 1.1, 0), _theme["torch"], 2.4, 10.5)
		var south_point := Vector3(side * 4.8, 0.0, -17.4)
		_brazier(torches, south_point, true)
		_add_omni(torches, south_point + Vector3(0, 1.1, 0), _theme["torch"].lerp(Color("ff9a5c"), 0.35), 2.3, 10.5)


## A cool fill keeps the dais readable while the archways stay warm.
func _build_fill_lighting() -> void:
	var lights := _root("Lights")
	var crown := OmniLight3D.new()
	crown.name = "CrownFill"
	crown.position = Vector3(0, _ceiling - 1.2, 0)
	crown.light_color = _theme["ambient"]
	crown.light_energy = 2.0
	crown.omni_range = 20.0
	crown.omni_attenuation = 1.1
	crown.shadow_enabled = false
	lights.add_child(crown)
	_lights += 1
	var fill_tint: Color = _theme["ambient"].lerp(_theme["accent"], 0.25)
	for index in 4:
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var fill := OmniLight3D.new()
		fill.name = "ChamberFill_%d" % index
		fill.position = Vector3(cos(angle) * 8.2, _ceiling * 0.45, sin(angle) * 8.2)
		fill.light_color = fill_tint if index % 2 == 0 else _theme["torch"]
		fill.light_energy = 1.5
		fill.omni_range = 13.5
		fill.omni_attenuation = 1.2
		fill.shadow_enabled = false
		lights.add_child(fill)
		_lights += 1


func _build_ossuary() -> void:
	_build_shell(_wall, _charnel_floor, false)
	_build_ceiling()
	_build_archways()
	_build_bone_totems()
	_build_bone_cover()
	_build_bone_arcs()
	_build_skull_niches()
	_build_femur_bundles()
	_build_floor_flesh()
	_build_floor_dressing()
	_build_chains()
	_build_charnel_slab()
	_build_sacrificial_ring()
	_build_rope()
	_build_hole()
	_build_torches_ossuary()
	_build_fill_lighting()
	_build_seals()


## Bone totems stand where the sanctuary keeps its columns: a slim dark shaft
## with a batched vertebra stack, skulls wedged between the discs and a skull
## knot at the head. The collider is a plain cylinder, so it costs nothing.
func _build_bone_totems() -> void:
	var totems := _root("BoneTotems")
	var disc_mesh := CylinderMesh.new()
	disc_mesh.bottom_radius = 1.0
	disc_mesh.top_radius = 1.0
	disc_mesh.height = 1.0
	disc_mesh.radial_segments = 10
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.2
	skull_mesh.height = 0.4
	skull_mesh.radial_segments = 8
	skull_mesh.rings = 5
	var discs: Array[Transform3D] = []
	var skulls: Array[Transform3D] = []
	for index in PILLAR_COUNT:
		var angle := TAU * float(index) / float(PILLAR_COUNT) + PI / 6.0
		var point := Vector3(cos(angle) * TOTEM_RING, 0.0, sin(angle) * TOTEM_RING)
		var body := _totem_body(point, totems)
		body.name = "BoneTotem_%d" % index
		# Vertebrae: alternating radii and thicknesses with a slow per-tier twist.
		var stride := (_ceiling - 2.1) / float(TOTEM_TIERS - 1)
		for tier in TOTEM_TIERS:
			var lift := 0.5 + float(tier) * stride
			var radius := 0.55 + 0.3 * (0.5 + 0.5 * sin(float(tier) * 2.1 + float(index) * 0.9))
			var thickness := 0.14 + 0.12 * (0.5 + 0.5 * cos(float(tier) * 1.7 + float(index) * 0.5))
			var spin := float(tier) * 0.72 + float(index) * 1.1
			var disc_basis := Basis(Vector3.UP, spin) * Basis(Vector3.RIGHT, 0.06 * sin(float(tier) * 1.3))
			discs.append(Transform3D(disc_basis.scaled(Vector3(radius, thickness, radius)),
				point + Vector3(0, lift, 0)))
		# Skulls wedged into the gaps of the stack at three heights.
		for level in 3:
			var lift := 1.3 + float(level) * 2.4
			for slot in 2:
				var spin := TAU * (float(slot) + 0.25) / 2.0 + float(level) * 0.9 + float(index) * 0.6
				var skull_basis := Basis(Vector3.UP, spin + PI * 0.5) * Basis(Vector3.RIGHT, 0.25)
				skulls.append(Transform3D(skull_basis.scaled(Vector3(1.15, 0.9, 1.0)),
					point + Vector3(cos(spin) * 0.6, lift, sin(spin) * 0.6)))
		# Crown knot: the head of the totem is a clutch of skulls.
		for slot in 6:
			var spin := TAU * float(slot) / 6.0 + float(index) * 0.4
			var crown := point + Vector3(cos(spin) * 0.4, _ceiling - 1.15 + 0.18 * float(slot % 2),
				sin(spin) * 0.4)
			skulls.append(Transform3D(Basis(Vector3.UP, spin).scaled(Vector3(1.2, 1.0, 1.05)), crown))
		skulls.append(Transform3D(Basis(Vector3.UP, float(index)).scaled(Vector3(1.3, 1.1, 1.1)),
			point + Vector3(0, _ceiling - 0.85, 0)))
		if index % 2 == 0:
			_add_omni(totems, point + Vector3(0, 2.0, 0), _theme["accent"], 0.9, 5.5)
	_multimesh(totems, "Vertebrae", disc_mesh, _bone, discs)
	_multimesh(totems, "TotemSkulls", skull_mesh, _bone, skulls)


func _totem_body(point: Vector3, parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	Geo.cylinder(body, 1.05, 0.92, 0.28, Vector3(0, 0.14, 0), _bone_dark, 12)
	Geo.cylinder(body, TOTEM_SHAFT_RADIUS, TOTEM_SHAFT_RADIUS * 1.18, _ceiling,
		Vector3(0, _ceiling * 0.5, 0), _bone_dark, 10)
	var shape := CylinderShape3D.new()
	shape.radius = TOTEM_COLLIDER_RADIUS
	shape.height = _ceiling
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, _ceiling * 0.5, 0)
	body.add_child(collider)
	_solids += 1
	return body


## Bone-pile cover in the four cover positions, plus skull heaps on the cache
## spots, so both rooms block the same floor.
func _build_bone_cover() -> void:
	var cover := _root("BoneCover")
	var lump_mesh := SphereMesh.new()
	lump_mesh.radius = 0.42
	lump_mesh.height = 0.84
	lump_mesh.radial_segments = 8
	lump_mesh.rings = 5
	var lumps: Array[Transform3D] = []
	var rects := _cover_rects()
	for index in rects.size():
		var rect := rects[index]
		var point := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
		var size := Vector3(rect.size.x, 1.1, rect.size.y)
		var pile := _solid_box(size, point + Vector3(0, size.y * 0.5, 0), _bone_dark, cover)
		if index < 4:
			pile.name = "BonePile_%d" % index
		else:
			pile.name = "SkullHeap_%d" % (index - 4)
			Geo.sphere(cover, 0.5, point + Vector3(0, size.y + 0.05, 0),
				_flesh, Vector3(0.9, 0.35, 0.9))
		# Pale bone lumps spilling over the dark mass break the slab silhouette.
		var lump_count := 6 if index < 4 else 3
		for lump in lump_count:
			var spin := TAU * float(lump) / float(lump_count) + float(index) * 0.7
			var reach := 0.42 * rect.size.x + 0.25 * rect.size.y
			var lump_basis := Basis(Vector3.UP, spin * 1.7) * Basis(Vector3.RIGHT, 0.35)
			lumps.append(Transform3D(lump_basis.scaled(Vector3(1.0, 0.7, 1.15)),
				point + Vector3(cos(spin) * reach, size.y + 0.02, sin(spin) * reach * 0.35)))
	_multimesh(cover, "BoneLumps", lump_mesh, _bone, lumps)


## Rib arcs climb the walls and meet across the vaulted ceiling.
func _build_bone_arcs() -> void:
	var arcs := _root("BoneArcs")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 1.0, 0.16)
	var placements: Array[Transform3D] = []
	for entry in _wall_faces():
		var face: Vector3 = entry["face"]
		var inward: Vector3 = entry["inward"]
		var tangent: Vector3 = entry["tangent"]
		for offset in [-10.5, -3.5, 3.5, 10.5]:
			var lower_base := face + tangent * float(offset) + Vector3(0, 0.35, 0)
			_arc(placements, lower_base, inward, 2.6, 1.95, 9, 1.0)
			var upper_base := face + tangent * float(offset) + Vector3(0, _ceiling - 3.0, 0)
			_arc(placements, upper_base, inward, 1.9, 1.6, 7, -1.0)
	for offset in [-12.0, -6.0, 6.0, 12.0]:
		placements.append(_beam_transform(Vector3(-CHAMBER_HALF, _ceiling - 0.25, offset),
			Vector3(CHAMBER_HALF, _ceiling - 0.25, offset)))
		placements.append(_beam_transform(Vector3(offset, _ceiling - 0.25, -CHAMBER_HALF),
			Vector3(offset, _ceiling - 0.25, CHAMBER_HALF)))
	_multimesh(arcs, "Ribs", mesh, _bone, placements)


## Niche recesses stacked with skulls: one batched draw call per room.
func _build_skull_niches() -> void:
	var niches := _root("SkullNiches")
	var recess := BoxMesh.new()
	recess.size = Vector3(1.45, 1.15, 0.05)
	var recess_placements: Array[Transform3D] = []
	var skull_placements: Array[Transform3D] = []
	for entry in _wall_faces():
		var face: Vector3 = entry["face"]
		var inward: Vector3 = entry["inward"]
		var tangent: Vector3 = entry["tangent"]
		for offset in [-9.0, 0.0, 9.0]:
			var center := face + inward * 0.03 + tangent * float(offset) + Vector3(0, 1.85, 0)
			recess_placements.append(Transform3D(Basis.looking_at(-inward, Vector3.UP), center))
			for row in 2:
				for column in 3:
					var skull := face + inward * 0.2 \
						+ tangent * (float(offset) + (float(column) - 1.0) * 0.42) \
						+ Vector3(0, 1.55 + float(row) * 0.4, 0)
					var spin := Basis(Vector3.UP, float(column) * 0.7 + float(row) * 0.4) \
						* Basis(Vector3.RIGHT, 0.12 * float(row))
					skull_placements.append(Transform3D(spin.scaled(Vector3(1.0, 0.85, 0.95)), skull))
	var rects := _cover_rects()
	for index in range(4, rects.size()):
		var rect := rects[index]
		var center := Vector3(rect.get_center().x, 1.15, rect.get_center().y)
		for stack in 5:
			var angle := TAU * float(stack) / 5.0
			var skull := center + Vector3(cos(angle) * 0.34, float(stack % 2) * 0.22, sin(angle) * 0.34)
			skull_placements.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(1.0, 0.8, 0.9)), skull))
	var debris := SphereMesh.new()
	debris.radius = 0.2
	debris.height = 0.4
	debris.radial_segments = 8
	debris.rings = 5
	_multimesh(niches, "Recesses", recess, _portal, recess_placements)
	_multimesh(niches, "Skulls", debris, _bone, skull_placements)


## Femur bundles are dragged along the wall bases, around the totems and over
## the bone piles: one batched draw call for the whole room.
func _build_femur_bundles() -> void:
	var clutter := _root("Femurs")
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 0.05
	mesh.top_radius = 0.05
	mesh.height = 1.0
	mesh.radial_segments = 6
	var placements: Array[Transform3D] = []
	for entry in _wall_faces():
		var face: Vector3 = entry["face"]
		var inward: Vector3 = entry["inward"]
		var tangent: Vector3 = entry["tangent"]
		for offset in [-13.5, -6.0, 6.0, 13.5]:
			var knuckle := face + inward * 0.18 + tangent * float(offset) + Vector3(0, 0.08, 0)
			for stick in 6:
				var spread := float(stick) - 2.5
				var tip := knuckle + inward * (-0.3 - 0.07 * float(stick % 3)) \
					+ Vector3(0, 0.7 + 0.16 * float(stick % 2), 0) + tangent * spread * 0.2
				placements.append(_beam_transform(knuckle, tip))
	for index in PILLAR_COUNT:
		var angle := TAU * float(index) / float(PILLAR_COUNT) + PI / 6.0
		var center := Vector3(cos(angle) * TOTEM_RING, 0.0, sin(angle) * TOTEM_RING)
		for stick in 6:
			var spin := TAU * float(stick) / 6.0
			var root := center + Vector3(cos(spin) * 0.98, 0.08, sin(spin) * 0.98)
			var tip := root + Vector3(cos(spin) * 0.4, 0.75 + 0.1 * float(stick % 2), sin(spin) * 0.4)
			placements.append(_beam_transform(root, tip))
	for rect in _cover_rects():
		var center := Vector3(rect.get_center().x, 0.9, rect.get_center().y)
		for stick in 6:
			var spin := TAU * float(stick) / 6.0 + 0.4
			var pile_base := center + Vector3(cos(spin) * 0.5, 0.0, sin(spin) * 0.5)
			var tip := center + Vector3(cos(spin) * 1.0, 0.35 + 0.12 * float(stick % 3), sin(spin) * 1.0)
			placements.append(_beam_transform(pile_base, tip))
	# Loose femurs dropped across the floor between the clutter.
	for index in 24:
		var spread_angle := float(index) * 2.399
		var spread_radius := 6.2 + 3.8 * (0.5 + 0.5 * sin(float(index) * 2.3))
		var lying := Vector3(cos(spread_angle) * spread_radius, 0.05, sin(spread_angle) * spread_radius)
		var heading := spread_angle + 1.2
		var length := 0.6 + 0.12 * float(index % 4)
		placements.append(_beam_transform(lying,
			lying + Vector3(cos(heading) * length, 0.07, sin(heading) * length)))
	_multimesh(clutter, "BoneClutter", mesh, _bone, placements)


func _build_floor_flesh() -> void:
	var flesh := _root("FloorFlesh")
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 0.8
	mesh.top_radius = 0.62
	mesh.height = 0.06
	mesh.radial_segments = 10
	var placements: Array[Transform3D] = []
	for index in 16:
		var angle := TAU * (float(index) + 0.35) / 16.0
		var radius := 13.2 if index % 2 == 0 else 12.1
		var point := Vector3(cos(angle) * radius, 0.02, sin(angle) * radius)
		placements.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(1.25, 1.0, 0.85)), point))
	# Keep the inner patches off the pentagram so the sigil stays readable.
	for index in 4:
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var point := Vector3(cos(angle) * 5.0, 0.02, sin(angle) * 5.0)
		placements.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(0.9, 1.0, 0.9)), point))
	_multimesh(flesh, "FleshPatches", mesh, _flesh, placements)


## Charnel floor dressing: pale bone dust drifting against the walls and dark
## gore pools with a dry rim. Purely visual, a couple of centimetres high, so
## the floor stays flat and every collider is untouched.
func _build_floor_dressing() -> void:
	var dressing := _root("FloorDressing")
	var dust_mesh := CylinderMesh.new()
	dust_mesh.bottom_radius = 1.0
	dust_mesh.top_radius = 0.82
	dust_mesh.height = 0.02
	dust_mesh.radial_segments = 12
	var radii: Array[float] = [12.0, 13.4, 14.8]
	var dust: Array[Transform3D] = []
	for index in 22:
		var angle := TAU * (float(index) + 0.3) / 22.0
		var radius: float = radii[index % radii.size()]
		var point := Vector3(cos(angle) * radius, 0.01, sin(angle) * radius)
		var span := 1.0 + 0.6 * (0.5 + 0.5 * sin(float(index) * 1.9))
		dust.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(span, 1.0, span * 0.8)), point))
	_multimesh(dressing, "BoneDust", dust_mesh, _bone, dust)

	var rim_mesh := CylinderMesh.new()
	rim_mesh.bottom_radius = 1.0
	rim_mesh.top_radius = 0.98
	rim_mesh.height = 0.016
	rim_mesh.radial_segments = 14
	var pool_mesh := CylinderMesh.new()
	pool_mesh.bottom_radius = 0.86
	pool_mesh.top_radius = 0.9
	pool_mesh.height = 0.03
	pool_mesh.radial_segments = 14
	var rims: Array[Transform3D] = []
	var pools: Array[Transform3D] = []
	for index in 7:
		var angle := TAU * (float(index) + 0.5) / 7.0 + 0.25
		var radius := 7.4 + 1.1 * float(index % 3)
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var span := 0.75 + 0.35 * float(index % 3)
		var basis := Basis(Vector3.UP, float(index) * 0.9).scaled(Vector3(span, 1.0, span * 0.88))
		rims.append(Transform3D(basis, point + Vector3(0, 0.008, 0)))
		pools.append(Transform3D(basis, point + Vector3(0, 0.02, 0)))
	_multimesh(dressing, "GoreRim", rim_mesh, _gore_rim, rims)
	_multimesh(dressing, "GorePool", pool_mesh, _gore, pools)


## Hanging chains and iron hooks brush the top of the frame.
func _build_chains() -> void:
	var chains := _root("Chains")
	var link := CylinderMesh.new()
	link.bottom_radius = 0.035
	link.top_radius = 0.035
	link.height = 1.0
	link.radial_segments = 6
	var hook := TorusMesh.new()
	hook.outer_radius = 0.19
	hook.inner_radius = 0.1
	hook.rings = 8
	hook.ring_segments = 6
	var chain_placements: Array[Transform3D] = []
	var hook_placements: Array[Transform3D] = []
	for index in 10:
		var angle := TAU * (float(index) + 0.5) / 10.0
		var radius := 7.4 if index % 2 == 0 else 12.6
		var top := Vector3(cos(angle) * radius, _ceiling - 0.2, sin(angle) * radius)
		var bottom := top - Vector3(0, 2.5 + 0.35 * float(index % 3), 0)
		chain_placements.append(_beam_transform(top, bottom))
		var hook_basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, PI * 0.5)
		hook_placements.append(Transform3D(hook_basis, bottom))
	_multimesh(chains, "ChainLinks", link, _iron, chain_placements)
	_multimesh(chains, "Hooks", hook, _iron, hook_placements)


## The charnel slab stands where the sanctuary altar stands, but it is bone,
## not stone, and it is not an altar the party can use.
func _build_charnel_slab() -> void:
	var slab := Node3D.new()
	slab.name = "CharnelSlab"
	slab.position = altar_position
	_own(slab)
	var body := _solid_box(Vector3(1.9, 0.85, 1.2), Vector3(0, 0.425, 0), _bone, slab)
	body.name = "SlabBlock"
	Geo.box(slab, Vector3(2.05, 0.12, 1.32), Vector3(0, 0.9, 0), _dark_stone)
	Geo.box(slab, Vector3(1.7, 0.06, 1.02), Vector3(0, 0.97, 0), _flesh)
	var bowl := Geo.cylinder(slab, 0.32, 0.26, 0.16, Vector3(0, 1.02, 0), _iron, 16)
	bowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geo.box(slab, Vector3(1.2, 0.02, 0.1), Vector3(0, 0.99, 0), _accent_material)
	for side in [-1.0, 1.0]:
		Geo.sphere(slab, 0.19, Vector3(side * 0.88, 1.02, 0.5), _bone, Vector3(1.0, 0.85, 0.95))
		Geo.sphere(slab, 0.19, Vector3(side * 0.88, 1.02, -0.5), _bone, Vector3(1.0, 0.85, 0.95))
	for side in [-1.0, 1.0]:
		Geo.beam(slab, Vector3(side * 0.75, 0.16, 0.72), Vector3(side * 0.55, 0.9, 0.44), 0.075, _bone, 6)
		Geo.beam(slab, Vector3(side * 0.75, 0.16, -0.72), Vector3(side * 0.55, 0.9, -0.44), 0.075, _bone, 6)
	_add_omni(slab, altar_position + Vector3(0, 1.6, 0), _theme["accent"], 1.4, 6.0)


## The cache sits in the middle of a sacrificial bone ring.
func _build_sacrificial_ring() -> void:
	var ring := Node3D.new()
	ring.name = "SacrificialRing"
	ring.position = Vector3(chest_position.x, 0.0, chest_position.z)
	_own(ring)
	Geo.cylinder(ring, 1.4, 1.4, 0.04, Vector3(0, 0.02, 0), _dark_stone, 32)
	Geo.cylinder(ring, 0.92, 0.86, 0.02, Vector3(0, 0.04, 0), _flesh, 20)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var base := Vector3(cos(angle) * 1.32, 0.03, sin(angle) * 1.32)
		Geo.beam(ring, base, base + Vector3(cos(angle) * 0.16, 0.42, sin(angle) * 0.16), 0.055, _bone, 6)
		Geo.sphere(ring, 0.1, base + Vector3(cos(angle) * 0.16, 0.46, sin(angle) * 0.16), _bone)
	var groove := Geo.box(ring, Vector3(0.05, 0.01, 2.4), Vector3(0, 0.045, 0), _accent_material)
	groove.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_torches_ossuary() -> void:
	var torches := _root("Torches")
	for point in [Vector3(14.4, 0.0, 0.0), Vector3(-14.4, 0.0, 0.0), Vector3(0.0, 0.0, 14.4), Vector3(0.0, 0.0, -14.4)]:
		_brazier(torches, point, false)
		_add_omni(torches, point + Vector3(0, 1.1, 0), _theme["torch"], 2.2, 9.5)


func _wall_faces() -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	for side in [-1.0, 1.0]:
		faces.append({
			"face": Vector3(0.0, 0.0, side * CHAMBER_HALF),
			"inward": Vector3(0.0, 0.0, -side),
			"tangent": Vector3(1.0, 0.0, 0.0),
		})
		faces.append({
			"face": Vector3(side * CHAMBER_HALF, 0.0, 0.0),
			"inward": Vector3(-side, 0.0, 0.0),
			"tangent": Vector3(0.0, 0.0, 1.0),
		})
	return faces


func _arc(placements: Array[Transform3D], base: Vector3, inward: Vector3, radius: float, end_angle: float, segments: int, vertical: float) -> void:
	var previous := _arc_point(base, inward, radius, 0.0, vertical)
	for index in segments:
		var next := _arc_point(base, inward, radius, end_angle * float(index + 1) / float(segments), vertical)
		placements.append(_beam_transform(previous, next))
		previous = next


func _arc_point(base: Vector3, inward: Vector3, radius: float, angle: float, vertical: float) -> Vector3:
	return base + Vector3(0, radius * sin(angle) * vertical, 0) + inward * (radius * (1.0 - cos(angle)))


func _brazier(parent: Node3D, point: Vector3, with_bowl: bool) -> void:
	Geo.cylinder(parent, 0.16, 0.26, 0.75, point + Vector3(0, 0.375, 0), _iron, 10)
	if with_bowl:
		Geo.cylinder(parent, 0.42, 0.22, 0.24, point + Vector3(0, 0.87, 0), _iron, 12)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.17
	flame_mesh.height = 0.5
	flame_mesh.radial_segments = 8
	flame_mesh.rings = 5
	flame.mesh = flame_mesh
	flame.material_override = _flame_material
	flame.position = point + Vector3(0, 0.98, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flame)
	_torches += 1


func _add_omni(parent: Node3D, point: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = point
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	parent.add_child(light)
	_lights += 1
	return light


func _multimesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material, placements: Array[Transform3D]) -> MultiMeshInstance3D:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = placements.size()
	for index in placements.size():
		batch.set_instance_transform(index, placements[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = batch
	instance.material_override = material
	parent.add_child(instance)
	return instance


## Basis that stretches a unit-height mesh between two points.
func _beam_transform(a: Vector3, b: Vector3) -> Transform3D:
	var delta := b - a
	var length := maxf(delta.length(), 0.0001)
	var up := delta / length
	var side := Vector3.RIGHT
	if absf(up.dot(side)) > 0.95:
		side = Vector3.FORWARD
	var right := side.cross(up).normalized()
	var back := right.cross(up).normalized()
	return Transform3D(Basis(right, up * length, back), (a + b) * 0.5)


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
