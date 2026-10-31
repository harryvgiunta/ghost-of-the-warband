extends Node3D
## One descent into the Weeping Hollow: floor I, built when a party goes down and
## freed when it comes back up.
##
## The cave is an instance. Every descent builds a fresh copy of the same authored
## floor - the rock, the light, the watchers in their dens and the demon at the
## bottom - at `DelveArea.ORIGIN`, far outside the wood's map, and the climb out
## frees all of it: nothing below outlives the party that went down. The floor is
## deterministic (fixed layout, fixed seeds, fixed names), so a co-op guest builds
## the same cave its host built and the host's mob snapshots land on bodies of the
## same name.
##
## The layout is a chain of rooms joined by tunnels, each an axis-aligned
## rectangle of floor in the cave's own frame (+Z back toward the mouth, -Z deeper).
## The rock is derived, not authored: the rooms are rasterised onto a half-metre
## grid and every cell that is not floor is rock, merged into as few boxes as the
## grid allows. A tunnel's mouth is an opening because the floor runs through it,
## and the squad's map (`squad_nav.gd`) sees the same boxes the bodies collide
## with. Each room owns its own shell mesh, which keeps the renderer's per-object
## light limit local: a room is lit by its own torches.
##
## Watchers wait in two dens and the demon in the last room. A den sleeps - its
## bodies stand their posts outside the world's hostile list, so nothing in the
## next room picks a fight through rock - until one of its own sees a body, hears
## a fight or takes a blow, or a body walks into the room. Then the whole den wakes
## at once and joins `host.guards`, where the squad, the retarget and the session
## find it like any other hostile.

## A den just woke: `label` is how the HUD names it.
signal den_woke(den_id: String, label: String)
## The floor's master died.
signal master_slain(master_name: String)

const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const DemonScript = preload("res://scripts/warband/delve_demon.gd")
const NavScript = preload("res://scripts/warband/squad_nav.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const VillageKit = preload("res://scripts/world/village_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const CampDressing = preload("res://scripts/warband/camp_dressing.gd")

const TITLE := "THE WEEPING HOLLOW"
const FLOOR_LABEL := "FLOOR I"
## The raster the rock is derived from, and the rock's height: every wall rises
## to `TOP`, and each room's ceiling fills down from it to the room's own height.
const CELL := 0.5
const TOP := 11.0
## The rock box the rooms are cut out of, in the cave's frame (x/z): every room
## plus two metres of rock on every side.
const BOUNDS := Rect2(-50.0, -96.0, 62.0, 104.0)
## The rooms, mouth first. Edges sit on the half-metre grid, and every room shares
## an edge with the next, which is the whole of how they connect. The ways between
## the halls bend on purpose: a den's sight runs down a straight tunnel, and a den
## that could see the landing - or the next den's fight - woke the moment a party
## set foot below.
const ROOMS := [
	{"id": "mouth", "rect": Rect2(-7.0, -8.0, 14.0, 14.0), "height": 7.0},
	{"id": "first_way", "rect": Rect2(-2.5, -15.0, 5.0, 7.0), "height": 4.6, "tunnel": true},
	{"id": "first_bend", "rect": Rect2(-2.5, -20.0, 12.0, 5.0), "height": 4.6, "tunnel": true},
	{"id": "first_drop", "rect": Rect2(4.5, -24.0, 5.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "den", "rect": Rect2(-10.0, -42.0, 20.0, 18.0), "height": 8.0},
	{"id": "crawl", "rect": Rect2(-17.0, -40.0, 7.0, 4.0), "height": 4.2, "tunnel": true},
	{"id": "crawl_turn", "rect": Rect2(-21.0, -40.0, 4.0, 14.0), "height": 4.6, "tunnel": true},
	{"id": "crawl_out", "rect": Rect2(-24.0, -30.0, 3.0, 4.0), "height": 4.6, "tunnel": true},
	{"id": "ossuary", "rect": Rect2(-42.0, -48.0, 18.0, 26.0), "height": 8.5},
	{"id": "descent", "rect": Rect2(-36.0, -66.0, 6.0, 18.0), "height": 5.0, "tunnel": true},
	{"id": "lair", "rect": Rect2(-48.0, -94.0, 30.0, 28.0), "height": 10.0},
]
## The way up: a rope out of a hole in the mouth's roof.
const EXIT_POINT := Vector3(0.0, 0.0, 3.6)
const EXIT_REACH := 2.6
## Where the party lands: a ring in the mouth, facing down the first way.
const ENTRY_CENTRE := Vector3(0.0, 0.0, -1.0)
const ENTRY_RADIUS := 2.3
const ENTRY_POSTS := 8
## The same lift every body in the world is spawned clear of its ground by.
const SPAWN_LIFT := 0.12
## The two dens. Every body faces its den's own entrance (`door`), so its sight
## cone is what notices a party coming in.
const DENS := [
	{"id": "den", "label": "The watchers' den wakes.", "room": "den", "door": Vector3(7.0, 0.0, -24.0),
		"members": [
		{"species": "hollow_warden", "at": Vector3(-4.5, 0.0, -35.0)},
		{"species": "ossuary_stalker", "at": Vector3(4.0, 0.0, -37.5)},
		{"species": "hollow_warden", "at": Vector3(0.5, 0.0, -31.0)},
	]},
	{"id": "ossuary", "label": "The ossuary stirs.", "room": "ossuary", "door": Vector3(-24.0, 0.0, -28.0),
		"members": [
		{"species": "ossuary_stalker", "at": Vector3(-29.0, 0.0, -33.0)},
		{"species": "gallowsroot", "at": Vector3(-35.0, 0.0, -40.0)},
		{"species": "hollow_warden", "at": Vector3(-38.0, 0.0, -30.0)},
		{"species": "ossuary_stalker", "at": Vector3(-30.5, 0.0, -44.0)},
	]},
]
## The floor's master, at the far end of the lair, facing the way down.
const MASTER_POINT := Vector3(-33.0, 0.0, -84.0)
const MASTER_NAME := "HollowMaster"
## How often the sleepers are asked whether they have noticed anything.
const WAKE_POLL := 0.25
## A body this far inside a den's room wakes it whatever the den has seen.
const WAKE_INSET := 1.5
const PACK_RADIUS := 14.0
const SEED := 4409

## The world this instance is built into.
var host: Node3D = null
## True on a co-op guest: the bodies are the host's to drive, so they go straight
## onto the hostile list as replicas and nothing here wakes them.
var replica := false
## The squad's map of the floor (`squad_nav.gd`).
var nav = null
## The camera's environment while the eye is below.
var environment: Environment = null
## The floor's master (`delve_demon.gd`), or null once freed.
var master = null

## `{id, label, rect, mobs, awake}` per den, in `DENS` order.
var _dens: Array[Dictionary] = []
var _poll := 0.0
var _rock_material: Material
var _floor_material: Material
var _ceiling_material: Material
var _boulder_material: Material
var _glow_material: StandardMaterial3D
var _stones: Array[ArrayMesh] = []
var _spires: Array[ArrayMesh] = []
var _lights := 0


# --- reading ---------------------------------------------------------------

## Where the rope hangs, in the world.
func exit_point() -> Vector3:
	return to_global(EXIT_POINT)


## Whether a body stands close enough to the rope to climb it.
func at_exit(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	return (actor as Node3D).global_position.distance_to(exit_point()) <= EXIT_REACH


## Whether a world point is inside this instance: under its roof and over its
## floor. The eye is asked this every frame, so it is a box test.
func contains(point: Vector3) -> bool:
	var local := point - global_position
	if local.y < -6.0 or local.y > TOP + 6.0:
		return false
	return BOUNDS.has_point(Vector2(local.x, local.z))


## The ground the party lands on, in the world, one post per body.
func entry_posts(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index in maxi(1, count):
		var angle := TAU * float(index % ENTRY_POSTS) / float(ENTRY_POSTS)
		var radius := ENTRY_RADIUS + 1.2 * float(index / ENTRY_POSTS)
		out.append(to_global(ENTRY_CENTRE + Vector3(cos(angle) * radius, SPAWN_LIFT,
			sin(angle) * radius)))
	return out


## The way a landed body faces: down the first way.
func entry_yaw() -> float:
	return 0.0


## Every hostile this floor fielded, the master included.
func mobs() -> Array:
	var out: Array = []
	for den in _dens:
		out.append_array(den["mobs"])
	if master != null:
		out.append(master)
	return out


## Hostiles still standing.
func living() -> int:
	var count := 0
	for mob in mobs():
		if is_instance_valid(mob) and bool(mob.get("alive")):
			count += 1
	return count


func master_alive() -> bool:
	return master != null and is_instance_valid(master) and bool(master.get("alive"))


## Whether a den has woken (`id` from `DENS`, or "lair" for the master).
func is_awake(den_id: String) -> bool:
	for den in _dens:
		if str(den["id"]) == den_id:
			return bool(den["awake"])
	return false


func light_count() -> int:
	return _lights


# --- the build ---------------------------------------------------------------

## Build the floor into `world`. The node must already be in the tree at its own
## origin: the rock's colliders, the mobs' homes and the squad's map are all read
## in world space.
func build(world: Node3D, as_replica: bool = false) -> void:
	host = world
	replica = as_replica
	_materials()
	_build_environment()
	_build_rock()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for room in ROOMS:
		_dress_room(room, rng)
	_build_exit()
	_build_lights()
	_build_props()
	_build_mobs()
	nav = NavScript.new()
	nav.build(self, Rect2(global_position.x + BOUNDS.position.x,
		global_position.z + BOUNDS.position.y, BOUNDS.size.x, BOUNDS.size.y), [],
		global_position.y)


func _materials() -> void:
	_rock_material = TextureLibrary.granite_material(Color(0.47, 0.44, 0.41))
	_floor_material = TextureLibrary.granite_material(Color(0.34, 0.30, 0.27))
	_ceiling_material = TextureLibrary.granite_material(Color(0.30, 0.28, 0.27))
	_boulder_material = TextureLibrary.boulder_material(Color(0.62, 0.58, 0.54))
	_glow_material = StandardMaterial3D.new()
	_glow_material.albedo_color = Color(0.55, 0.95, 0.80)
	_glow_material.emission_enabled = true
	_glow_material.emission = Color(0.30, 0.95, 0.72)
	_glow_material.emission_energy_multiplier = 1.6
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for variant in 4:
		_stones.append(RockKit.mesh("outcrop" if variant % 2 == 0 else "boulder", 9100 + variant * 37))
	for variant in 3:
		_spires.append(RockKit.mesh("spire", 9300 + variant * 41))


## Underground: no sky, a dim warm ambient that keeps rock readable between the
## torches, and a close brown haze so the far end of a hall is a guess.
func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.010, 0.009)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.44, 0.40)
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.10, 0.085, 0.07)
	environment.fog_light_energy = 0.8
	environment.fog_sky_affect = 0.0
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# Godot 4.7 resets the density when the mode is written: the density goes last.
	environment.fog_density = 0.016
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.35
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.95
	environment.adjustment_contrast = 1.06
	environment.adjustment_brightness = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1


## The rock: one floor slab under everything, a box for every run of grid that is
## not floor, and a ceiling over every room. Each room's share of the rock is drawn
## by that room's own mesh.
func _build_rock() -> void:
	var solids := StaticBody3D.new()
	solids.name = "Rock"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	_box_collider(solids, Vector3(BOUNDS.size.x, 1.0, BOUNDS.size.y),
		Vector3(BOUNDS.get_center().x, -0.5, BOUNDS.get_center().y))
	var shells: Dictionary = {}
	for room in ROOMS:
		var node := Node3D.new()
		node.name = "Room_%s" % str(room["id"])
		add_child(node)
		var shell := VillageKit.Merged.new()
		var rect: Rect2 = room["rect"]
		var height := float(room["height"])
		VillageKit.add_box(shell, Vector3(rect.size.x, 0.2, rect.size.y),
			Vector3(rect.get_center().x, -0.1, rect.get_center().y), _floor_material)
		var ceiling := Vector3(rect.size.x, TOP - height, rect.size.y)
		var ceiling_at := Vector3(rect.get_center().x, (height + TOP) * 0.5, rect.get_center().y)
		VillageKit.add_box(shell, ceiling, ceiling_at, _ceiling_material)
		_box_collider(solids, ceiling, ceiling_at)
		shells[str(room["id"])] = {"node": node, "shell": shell}
	for block in rock_rects():
		var size := Vector3(block.size.x, TOP, block.size.y)
		var at := Vector3(block.get_center().x, TOP * 0.5, block.get_center().y)
		_box_collider(solids, size, at)
		var beside := _room_touching(block)
		if beside.is_empty():
			continue
		VillageKit.add_box(shells[beside]["shell"], size, at, _rock_material)
	for room_id in shells:
		shells[room_id]["shell"].commit(shells[room_id]["node"], "Shell", false)


## The rock as rectangles: every half-metre cell of `BOUNDS` whose centre is not
## on a room's floor, merged greedily into the widest, then tallest, run.
static func rock_rects() -> Array[Rect2]:
	var cols := int(ceil(BOUNDS.size.x / CELL))
	var rows := int(ceil(BOUNDS.size.y / CELL))
	var open := PackedByteArray()
	open.resize(cols * rows)
	open.fill(0)
	# Each room fills the cells it covers; its edges sit on the grid, so a cell is
	# wholly floor or wholly rock.
	for room in ROOMS:
		var rect: Rect2 = room["rect"]
		var x0 := int(round((rect.position.x - BOUNDS.position.x) / CELL))
		var z0 := int(round((rect.position.y - BOUNDS.position.y) / CELL))
		var x1 := int(round((rect.end.x - BOUNDS.position.x) / CELL))
		var z1 := int(round((rect.end.y - BOUNDS.position.y) / CELL))
		for z in range(maxi(z0, 0), mini(z1, rows)):
			for x in range(maxi(x0, 0), mini(x1, cols)):
				open[z * cols + x] = 1
	var used := PackedByteArray()
	used.resize(cols * rows)
	used.fill(0)
	var out: Array[Rect2] = []
	for z in rows:
		var x := 0
		while x < cols:
			var index := z * cols + x
			if open[index] != 0 or used[index] != 0:
				x += 1
				continue
			var width := 1
			while x + width < cols and open[index + width] == 0 and used[index + width] == 0:
				width += 1
			var depth := 1
			while z + depth < rows:
				var whole := true
				for step in width:
					var probe := (z + depth) * cols + x + step
					if open[probe] != 0 or used[probe] != 0:
						whole = false
						break
				if not whole:
					break
				depth += 1
			for dz in depth:
				for dx in width:
					used[(z + dz) * cols + x + dx] = 1
			out.append(Rect2(BOUNDS.position.x + float(x) * CELL, BOUNDS.position.y + float(z) * CELL,
				float(width) * CELL, float(depth) * CELL))
			x += width
	return out


## Whether a cave-local x/z point is on some room's floor.
static func is_floor(point: Vector2) -> bool:
	for room in ROOMS:
		if (room["rect"] as Rect2).has_point(point):
			return true
	return false


## The room a rock block borders, or "" for rock no room can see.
func _room_touching(block: Rect2) -> String:
	var grown := block.grow(0.25)
	for room in ROOMS:
		if grown.intersects(room["rect"] as Rect2):
			return str(room["id"])
	return ""


func _box_collider(solids: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position = at
	solids.add_child(holder)


## Broken stone along every wall foot, stalactites in every roof, a few
## stalagmites at the walls: what turns boxes of rock into a cave. All of it is
## presentation, batched per room, and none of it stands where a body walks.
func _dress_room(room: Dictionary, rng: RandomNumberGenerator) -> void:
	var node := get_node("Room_%s" % str(room["id"])) as Node3D
	var rect: Rect2 = room["rect"]
	var tunnel := bool(room.get("tunnel", false))
	var height := float(room["height"])
	var rocks := VillageKit.Merged.new()
	var step := 1.8 if tunnel else 2.3
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	for edge in edges:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var inward: Vector2 = edge[2]
		var along := (b - a).normalized()
		var length := a.distance_to(b)
		var t := rng.randf_range(0.2, 1.0)
		while t < length - 0.2:
			var point := a + along * t
			# A mouth into the next room is floor on the far side: no stone there.
			if not is_floor(point - inward * 0.75):
				var size := rng.randf_range(0.35, 0.6) if tunnel else rng.randf_range(0.5, 1.0)
				var at := Vector3(point.x - inward.x * size * 0.2, 0.0, point.y - inward.y * size * 0.2)
				RockKit.add_stone(rocks, _boulder_material, _stones[rng.randi() % _stones.size()],
					at, size, rng.randf_range(0.0, TAU), 0.42, rng.randf_range(-0.25, 0.25))
				if not tunnel and rng.randf() < 0.22:
					_stalagmite(rocks, at - Vector3(inward.x, 0.0, inward.y) * 0.1, rng)
			t += step * rng.randf_range(0.7, 1.3)
	var hanging := int(rect.get_area() / (26.0 if tunnel else 16.0))
	for index in hanging:
		var at := Vector2(rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0),
			rng.randf_range(rect.position.y + 1.0, rect.end.y - 1.0))
		_stalactite(rocks, Vector3(at.x, 0.0, at.y), height, rng, tunnel)
	rocks.commit(node, "Stone", false)


func _stalactite(m, at: Vector3, ceiling: float, rng: RandomNumberGenerator, short: bool) -> void:
	var mesh: ArrayMesh = _spires[rng.randi() % _spires.size()]
	var bounds := mesh.get_aabb()
	var width := rng.randf_range(0.18, 0.34) if short else rng.randf_range(0.22, 0.5)
	var stretch := rng.randf_range(0.7, 1.4)
	var basis := (Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, PI)) \
		.scaled_local(Vector3(width, width * stretch, width))
	# Upside down, the mesh's lowest point is its root: sink it into the roof.
	var root := -bounds.position.y * width * stretch
	m.add(mesh, Transform3D(basis, Vector3(at.x, ceiling + 0.15 - root, at.z)), _boulder_material)


func _stalagmite(m, at: Vector3, rng: RandomNumberGenerator) -> void:
	var mesh: ArrayMesh = _spires[rng.randi() % _spires.size()]
	var bounds := mesh.get_aabb()
	var width := rng.randf_range(0.2, 0.38)
	var stretch := rng.randf_range(0.8, 1.5)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(
		Vector3(width, width * stretch, width))
	m.add(mesh, Transform3D(basis, Vector3(at.x, -0.12 - bounds.position.y * width * stretch, at.z)),
		_boulder_material)


## The way up: a knotted rope out of a hole of night in the mouth's roof, the cold
## light that falls through it, and a word on the stone so it is found.
func _build_exit() -> void:
	var node := get_node("Room_mouth") as Node3D
	var mats: Dictionary = CampKit.materials()
	var m := VillageKit.Merged.new()
	var roof := float(ROOMS[0]["height"])
	var hang := EXIT_POINT + Vector3(0.0, roof, 0.0)
	VillageKit.add_beam(m, hang, EXIT_POINT + Vector3(0.0, 0.25, 0.0), 0.045, mats["drift"], 6)
	var knots := int((roof - 0.6) / 0.9)
	for index in knots:
		VillageKit.add_ball(m, 0.075, EXIT_POINT + Vector3(0.0, 0.7 + float(index) * 0.9, 0.0),
			mats["drift"], Vector3(1.0, 0.8, 1.0), 6, 4)
	m.commit(node, "Rope", false)
	var sky := StandardMaterial3D.new()
	sky.albedo_color = Color(0.55, 0.66, 0.85)
	sky.emission_enabled = true
	sky.emission = Color(0.42, 0.52, 0.78)
	sky.emission_energy_multiplier = 1.3
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var hole := MeshInstance3D.new()
	hole.name = "SkyHole"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.04
	disc.radial_segments = 18
	hole.mesh = disc
	hole.material_override = sky
	hole.position = hang - Vector3(0.0, 0.03, 0.0)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(hole)
	var shaft := SpotLight3D.new()
	shaft.name = "NightShaft"
	shaft.position = hang - Vector3(0.0, 0.2, 0.0)
	shaft.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shaft.light_color = Color(0.62, 0.72, 0.95)
	shaft.light_energy = 3.0
	shaft.spot_range = roof + 2.0
	shaft.spot_angle = 32.0
	shaft.shadow_enabled = false
	node.add_child(shaft)
	_lights += 1
	var word := Label3D.new()
	word.name = "WayUp"
	word.text = "THE WAY UP"
	word.font_size = 56
	word.pixel_size = 0.006
	word.outline_size = 10
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.modulate = Color(0.86, 0.90, 1.0)
	word.outline_modulate = Color(0.02, 0.03, 0.06, 0.9)
	word.position = EXIT_POINT + Vector3(0.0, 2.7, 0.0)
	node.add_child(word)


## Torches in the walls, a fire in the den, cold fungus in the ossuary, braziers
## round the lair. Every light belongs to the room it lights.
func _build_lights() -> void:
	_sconce("mouth", Vector3(-6.95, 0.0, -2.0), Vector3(1.0, 0.0, 0.0), 11)
	_sconce("mouth", Vector3(6.95, 0.0, -4.0), Vector3(-1.0, 0.0, 0.0), 12)
	_fire("mouth", Vector3(-3.6, 0.0, 3.0), 9)
	_sconce("first_bend", Vector3(3.0, 0.0, -19.95), Vector3(0.0, 0.0, 1.0), 13)
	_sconce("den", Vector3(-9.95, 0.0, -30.0), Vector3(1.0, 0.0, 0.0), 17)
	_sconce("den", Vector3(9.95, 0.0, -39.0), Vector3(-1.0, 0.0, 0.0), 19)
	_fire("den", Vector3(1.5, 0.0, -36.0), 23)
	_sconce("crawl_turn", Vector3(-20.95, 0.0, -34.0), Vector3(1.0, 0.0, 0.0), 29)
	_sconce("ossuary", Vector3(-41.95, 0.0, -26.0), Vector3(1.0, 0.0, 0.0), 31)
	_sconce("ossuary", Vector3(-24.05, 0.0, -44.0), Vector3(-1.0, 0.0, 0.0), 37)
	_fungus("ossuary", Vector3(-40.6, 0.0, -45.8), 41)
	_fungus("ossuary", Vector3(-26.0, 0.0, -23.4), 43)
	_sconce("descent", Vector3(-35.95, 0.0, -57.0), Vector3(1.0, 0.0, 0.0), 47)
	for spot in [Vector3(-44.0, 0.0, -70.5), Vector3(-22.0, 0.0, -70.5),
			Vector3(-44.0, 0.0, -89.5), Vector3(-22.0, 0.0, -89.5)]:
		_brazier("lair", spot, 53 + int(absf(spot.x + spot.z)))


func _sconce(room_id: String, at: Vector3, inward: Vector3, seed_value: int) -> void:
	var node := get_node("Room_%s" % room_id) as Node3D
	var host_node := Node3D.new()
	host_node.name = "Sconce%d" % seed_value
	host_node.position = at
	host_node.rotation.y = atan2(inward.x, inward.z)
	node.add_child(host_node)
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := CampKit.Merged.new()
	CampKit.add_beam(m, Vector3(0.0, 2.05, -0.1), Vector3(0.0, 2.05, 0.30), 0.03, iron["iron"], 5)
	CampKit.add_ring(m, Vector3(0.0, 2.05, 0.34), 0.0, 0.05, 0.08, iron["iron"], 0.0, 8, 3)
	CampKit.add_beam(m, Vector3(0.0, 1.75, 0.30), Vector3(0.0, 2.36, 0.40), 0.045, mats["drift_dark"], 6, 0.035)
	CampKit.add_ball(m, 0.07, Vector3(0.0, 2.38, 0.40), mats["fire_core"], Vector3(1.0, 0.6, 1.0), 7, 4)
	var saved: Transform3D = m.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.40)))
	FireFx.flame_cards(m, mats["flame"], rng, 0.42, 2.36)
	m.group = saved
	m.commit(host_node, "Torch")
	var light := FireFlicker.new()
	light.name = "TorchLight"
	light.position = Vector3(0.0, 2.6, 0.62)
	light.light_color = Color(1.0, 0.58, 0.26)
	light.light_energy = 3.0
	light.omni_range = 13.0
	light.omni_attenuation = 1.0
	light.flicker = 0.24
	light.shadow_enabled = false
	host_node.add_child(light)
	_lights += 1


func _fire(room_id: String, at: Vector3, seed_value: int) -> void:
	var node := get_node("Room_%s" % room_id) as Node3D
	var host_node := Node3D.new()
	host_node.name = "Fire%d" % seed_value
	host_node.position = at
	node.add_child(host_node)
	CampKit.fire_ring(host_node, CampKit.materials(), seed_value)
	var light := host_node.get_node_or_null("CampFireLight") as OmniLight3D
	if light != null:
		light.light_energy = 2.0
		light.omni_range = 10.0
	_lights += 1


## Pale growth on the wet stone at a wall's foot, and the cold light it gives.
func _fungus(room_id: String, at: Vector3, seed_value: int) -> void:
	var node := get_node("Room_%s" % room_id) as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := VillageKit.Merged.new()
	for index in 14:
		var spot := at + Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(0.02, 0.9),
			rng.randf_range(-1.1, 1.1))
		VillageKit.add_ball(m, rng.randf_range(0.04, 0.11), spot, _glow_material,
			Vector3(1.0, 0.55, 1.0), 6, 4)
	m.commit(node, "Fungus%d" % seed_value, false)
	var light := OmniLight3D.new()
	light.name = "FungusLight%d" % seed_value
	light.position = at + Vector3(0.0, 0.8, 0.0)
	light.light_color = Color(0.40, 0.95, 0.78)
	light.light_energy = 1.1
	light.omni_range = 7.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	node.add_child(light)
	_lights += 1


func _brazier(room_id: String, at: Vector3, seed_value: int) -> void:
	var node := get_node("Room_%s" % room_id) as Node3D
	var host_node := Node3D.new()
	host_node.name = "Brazier%d" % seed_value
	host_node.position = at
	node.add_child(host_node)
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := CampKit.Merged.new()
	for index in 3:
		var angle := TAU * float(index) / 3.0
		CampKit.add_beam(m, Vector3(cos(angle) * 0.34, 0.0, sin(angle) * 0.34),
			Vector3(cos(angle) * 0.18, 0.95, sin(angle) * 0.18), 0.035, iron["iron"], 5)
	CampKit.add_ring(m, Vector3(0.0, 1.0, 0.0), 0.0, 0.28, 0.36, iron["iron"], 0.0, 12, 4)
	CampKit.add_ball(m, 0.26, Vector3(0.0, 1.04, 0.0), mats["ember"], Vector3(1.1, 0.35, 1.1), 8, 4)
	CampKit.add_ball(m, 0.12, Vector3(0.0, 1.12, 0.0), mats["fire_core"], Vector3(1.0, 0.5, 1.0), 7, 4)
	FireFx.flame_cards(m, mats["flame"], rng, 0.85, 1.1)
	m.commit(host_node, "Brazier")
	FireFx.embers(host_node, 1.14, 0.22, 14)
	var light := FireFlicker.new()
	light.name = "BrazierLight"
	light.position = Vector3(0.0, 1.9, 0.0)
	light.light_color = Color(1.0, 0.42, 0.18)
	light.light_energy = 2.6
	light.omni_range = 13.0
	light.omni_attenuation = 1.0
	light.flicker = 0.28
	light.shadow_enabled = false
	host_node.add_child(light)
	_lights += 1


## What the watchers live among, and the lair's altar of the dead.
func _build_props() -> void:
	var mats: Dictionary = VillageKit.materials()
	var den := get_node("Room_den") as Node3D
	var den_solids := _solids(den, "DenSolids")
	var pole := Node3D.new()
	pole.name = "DenTotem"
	pole.position = Vector3(-6.5, 0.0, -40.0)
	den.add_child(pole)
	VillageKit.totem(pole, mats, den_solids, 3.8, 6611)
	var clutter := VillageKit.Merged.new()
	VillageKit.skull_stakes(clutter, mats, Vector3(-6.5, 0.0, -26.5), 0.4, 4, 0.85, 6613)
	VillageKit.bone_heap(clutter, mats, Vector3(-8.0, 0.0, -33.0), 0.8, 6617)
	VillageKit.bone_heap(clutter, mats, Vector3(7.0, 0.0, -40.5), 2.1, 6619)
	clutter.commit(den, "DenClutter")
	var ossuary := get_node("Room_ossuary") as Node3D
	var bones := VillageKit.Merged.new()
	for spot in [Vector3(-40.0, 0.0, -24.5), Vector3(-26.5, 0.0, -36.0), Vector3(-40.5, 0.0, -38.0),
			Vector3(-33.0, 0.0, -46.5), Vector3(-27.0, 0.0, -24.0)]:
		VillageKit.bone_heap(bones, mats, spot, spot.x * 0.3, 6700 + int(absf(spot.z)))
	VillageKit.skull_stakes(bones, mats, Vector3(-36.0, 0.0, -23.0), 0.0, 5, 0.9, 6721)
	bones.commit(ossuary, "OssuaryBones")
	var lair := get_node("Room_lair") as Node3D
	var lair_solids := _solids(lair, "LairSolids")
	var altar := Node3D.new()
	altar.name = "LairAltar"
	altar.position = MASTER_POINT + Vector3(0.0, 0.0, -6.0)
	lair.add_child(altar)
	VillageKit.sacrifice_ground(altar, mats, lair_solids, 6801)
	var lair_clutter := VillageKit.Merged.new()
	VillageKit.skull_stakes(lair_clutter, mats, Vector3(-40.0, 0.0, -78.0), 1.1, 5, 0.95, 6811)
	VillageKit.skull_stakes(lair_clutter, mats, Vector3(-26.0, 0.0, -78.0), -1.1, 5, 0.95, 6813)
	for spot in [Vector3(-45.5, 0.0, -80.0), Vector3(-20.5, 0.0, -84.0), Vector3(-41.0, 0.0, -92.0),
			Vector3(-24.0, 0.0, -68.5)]:
		VillageKit.bone_heap(lair_clutter, mats, spot, spot.z * 0.2, 6820 + int(absf(spot.x)))
	# A ring of old blood the master stands in.
	var stain := StandardMaterial3D.new()
	stain.albedo_color = Color(0.20, 0.03, 0.03)
	stain.roughness = 0.35
	VillageKit.add_cyl_disc(lair_clutter, 3.2, 0.02, MASTER_POINT + Vector3(0.0, 0.01, 0.0), stain, 28)
	VillageKit.add_ring(lair_clutter, MASTER_POINT + Vector3(0.0, 0.03, 0.0), 0.0, 3.3, 3.45,
		mats["bone"], 0.0, 28, 4)
	lair_clutter.commit(lair, "LairClutter")


func _solids(parent: Node3D, label: String) -> StaticBody3D:
	var solids := StaticBody3D.new()
	solids.name = label
	solids.collision_layer = 1
	solids.collision_mask = 0
	parent.add_child(solids)
	return solids


# --- the hostiles ------------------------------------------------------------

func _build_mobs() -> void:
	var mobs_root := Node3D.new()
	mobs_root.name = "Mobs"
	add_child(mobs_root)
	for spec in DENS:
		var room: Dictionary = _room(str(spec["room"]))
		var members: Array = []
		var index := 0
		for row in spec["members"]:
			index += 1
			var at: Vector3 = row["at"]
			var door: Vector3 = spec["door"]
			members.append(_spawn_watcher(mobs_root, "Hollow%s%d" % [str(spec["id"]).capitalize(), index],
				str(row["species"]), at, atan2(-(door.x - at.x), -(door.z - at.z))))
		MobWander.assign_all(members, PACK_RADIUS)
		_dens.append({"id": str(spec["id"]), "label": str(spec["label"]),
			"rect": room["rect"], "mobs": members, "awake": false})
	master = DemonScript.new()
	master.name = MASTER_NAME
	master.position = MASTER_POINT + Vector3(0.0, SPAWN_LIFT, 0.0)
	master.rotation.y = PI
	mobs_root.add_child(master)
	master.home = master.global_position
	master.safe_center = _safe_center()
	_wire(master)
	master.defeated.connect(_on_master_defeated)
	_dens.append({"id": "lair", "label": "Gorehorn rises from the blood.",
		"rect": _room("lair")["rect"], "mobs": [master], "awake": false})
	if replica:
		# The host drives every body: a guest's copies are replicas from their
		# first frame and are on the hostile list so the snapshots find them.
		for mob in mobs():
			_enlist(mob)


func _spawn_watcher(parent: Node3D, label: String, species: String, at: Vector3, yaw: float):
	var watcher = WatcherScript.new()
	watcher.name = label
	watcher.mob_id = species
	watcher.position = at + Vector3(0.0, SPAWN_LIFT, 0.0)
	watcher.rotation.y = yaw
	parent.add_child(watcher)
	watcher.home = watcher.global_position
	watcher.safe_center = _safe_center()
	_wire(watcher)
	return watcher


func _wire(mob) -> void:
	if replica or host == null:
		return
	if host.has_method("_on_enemy_defeated"):
		mob.defeated.connect(Callable(host, "_on_enemy_defeated"))
	if host.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(host, "_on_enemy_attack"))


## The town's ring is the one ground nobody hunts on; the cave is nowhere near it.
func _safe_center() -> Vector3:
	var town = host.get("town") if host != null else null
	if town != null and is_instance_valid(town):
		return (town as Node3D).global_position
	return Vector3(0.0, 0.0, 1.0e6)


func _room(room_id: String) -> Dictionary:
	for room in ROOMS:
		if str(room["id"]) == room_id:
			return room
	return {}


func _enlist(mob) -> void:
	if host == null or not is_instance_valid(mob):
		return
	var guards = host.get("guards")
	if guards is Array and not (guards as Array).has(mob):
		(guards as Array).append(mob)


## The host's clock: wake any den that has noticed the party. `party` is every
## standing body of the party below.
func tick(delta: float, party: Array) -> void:
	if replica:
		return
	_poll += delta
	if _poll < WAKE_POLL:
		return
	_poll = 0.0
	var standing: Array[CharacterBody3D] = []
	for body in party:
		if body is CharacterBody3D and is_instance_valid(body) and bool(body.get("alive")) \
				and not bool(body.get("downed")):
			standing.append(body)
	for den in _dens:
		if bool(den["awake"]):
			continue
		if _den_noticed(den, standing):
			_wake(den, standing)
			continue
		# Asleep, but with its eyes open: every sleeper watches the nearest body,
		# so what wakes it is its own sight cone and the rock between - never
		# distance through a wall.
		for mob in den["mobs"]:
			if is_instance_valid(mob) and bool(mob.get("alive")):
				mob.player = _nearest(mob.global_position, standing)


func _den_noticed(den: Dictionary, standing: Array[CharacterBody3D]) -> bool:
	for mob in den["mobs"]:
		if not is_instance_valid(mob):
			continue
		if not bool(mob.get("alive")) or float(mob.get("health")) < float(mob.get("max_health")) - 0.01:
			return true
		if mob.alerted():
			return true
	var inner := (den["rect"] as Rect2).grow(-WAKE_INSET)
	for body in standing:
		var local := to_local(body.global_position)
		if inner.has_point(Vector2(local.x, local.z)):
			return true
	return false


## The whole den at once: onto the hostile list, each body on the nearest of the
## party, and one line for the HUD.
func _wake(den: Dictionary, standing: Array[CharacterBody3D]) -> void:
	den["awake"] = true
	for mob in den["mobs"]:
		if not is_instance_valid(mob) or not bool(mob.get("alive")):
			continue
		_enlist(mob)
		var prey = _nearest(mob.global_position, standing)
		if prey != null:
			mob.targets = standing
			mob.hunt(prey)
	den_woke.emit(str(den["id"]), str(den["label"]))


func _nearest(point: Vector3, standing: Array[CharacterBody3D]):
	var best = null
	var best_distance := INF
	for body in standing:
		var distance := point.distance_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func _on_master_defeated(_enemy, _reward: int) -> void:
	master_slain.emit(str(master.get_display_name()) if is_instance_valid(master) else "Gorehorn")


# --- leaving ---------------------------------------------------------------

## Take this floor out of the world: its bodies off the hostile list, and every
## drop and missile still lying inside it freed with it. The cave's own nodes -
## rock, light, corpses, ragdolls - go with the node.
func teardown() -> void:
	if host != null and is_instance_valid(host):
		var guards = host.get("guards")
		if guards is Array:
			for mob in mobs():
				(guards as Array).erase(mob)
		for list_name in ["pickups", "projectiles"]:
			var list = host.get(list_name)
			if not (list is Array):
				continue
			for index in range((list as Array).size() - 1, -1, -1):
				var node = (list as Array)[index]
				if not is_instance_valid(node):
					(list as Array).remove_at(index)
					continue
				if node is Node3D and contains((node as Node3D).global_position):
					(list as Array).remove_at(index)
					(node as Node).queue_free()
		var loot = host.get("loot")
		if loot != null and is_instance_valid(loot) and loot.has_method("pickups"):
			for pickup in loot.pickups():
				if is_instance_valid(pickup) and contains(pickup.global_position):
					pickup.queue_free()
	_dens.clear()
	master = null
	queue_free()
