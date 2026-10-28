extends RefCounted
## The way out of the camp: a barely visible path through the wood, to the town.
##
## There is no road. The lane that used to be here - eleven metres of walkable band
## between two chains of walls, ruts down its middle and torches on its verges - is
## gone, and what is left is what a wood actually has: a soft, worn line of trodden
## earth that wanders between the trunks, with trees and brush standing *in* it,
## sometimes close enough that a body has to walk round them. What marks the way is
## fire. A pair of torches stands every `TORCH_SPACING` metres along the route, and
## at any distance the lights are the only clear thing in the wood.
##
## Three rules hold it together.
##
## 1. **Every piece of art is the world's own.** Trees come from `TreeKit` with
##    the species table in `WorldStyle`; undergrowth from `BushKit`, `RockKit`,
##    `GrassField` and `WorldScatter`; the cult's furniture from `CampKit` (rag
##    trees, bone arches, charm webs, wicker effigies, skull stakes, cauldrons,
##    fires) and `VillageKit` (the town gate, gallows trees, hanging charms);
##    fire from `FireFx` on the shared `flame.gdshader`; the night and its fog
##    from `EnvironmentKit`. Nothing is authored here that the world did not
##    already have.
## 2. **The way is walkable end to end, and nothing else is guaranteed.** The
##    centre line keeps `CLEAR_HALF` metres clear on both sides - no trunk, no
##    prop, nothing solid - so a body the width of these bodies can always pass,
##    and `mob_steering.gd`'s lane probe never meets a pinch it cannot slide out
##    of. Outside that, the wood stands where it likes. The only floor is the
##    world's heightfield: every tree, torch and prop stands on `terrain.gd`'s
##    ground, not on y = 0.
## 3. **The scene owns the numbers.** `build()` returns the lane, its measured
##    length, its width, every torch, the squad's spawn posts, the arch and the
##    three clearings the cult waits in, so the scene and the regression read the
##    same geometry instead of guessing at it.

const Geo = preload("res://scripts/geo.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
## The camp's dressing module owns the handful of materials the world kits do not
## carry (iron, steel, blood, rutted earth); it is the shared source, not copied.
const CampDressing = preload("res://scripts/warband/camp_dressing.gd")

## The route's walkable band: what the scene reports as its width, and what the
## regression measures drift against. It is not a built lane - it is how wide the
## wood is kept roughly passable either side of the worn line.
const WIDTH := 11.0
const HALF_WIDTH := WIDTH * 0.5
## How far off the centre line nothing solid may stand. Two and a half metres of
## clear walking is the number `mob_steering.gd`'s probe and a two-slide elite body
## need; this leaves a margin either side of it.
const CLEAR_HALF := 1.55
## How far from the way dressing may stand outside it.
const VERGE := 24.0
const TREE_CHUNK := 96.0
## Bushes cover the verge in one pass: fewer, larger batches than the trees.
const BUSH_CHUNK := 120.0
## Torches: a pair either side every this many metres, on the verge - outside the
## walked line, because a staked post is solid and a body must never jam on one.
const TORCH_SPACING := 12.0
const TORCH_OFFSET := 4.4
## Where the cult stands in pairs. Fractions of the lane's arc length.
const CLEARING_FRACTIONS := [0.22, 0.44, 0.66, 0.88]
## Grass and ferns are confined to the route's verge: the rest of the wood is
## trunks and brambles, and grass a body never sees is a draw call for nothing.
const GRASS_BAND := 12.0
const SEED := 82117

## The lane, its own first waypoint to the town gate. It winds, but every bend
## still closes on the arch, so a body walking it always has the town ahead of it.
## Where that first waypoint lands is the caller's `offset`: in the one world it
## is a long run of wood past the camp's mouth, not the camp's mouth itself.
const LANE_POINTS := [
	Vector3(0.0, 0.0, 6.0),
	Vector3(-5.0, 0.0, -39.0),
	Vector3(4.0, 0.0, -84.0),
	Vector3(9.0, 0.0, -129.0),
	Vector3(1.0, 0.0, -174.0),
	Vector3(-8.0, 0.0, -219.0),
	Vector3(-2.0, 0.0, -264.0),
	Vector3(7.0, 0.0, -309.0),
	Vector3(11.0, 0.0, -354.0),
	Vector3(2.0, 0.0, -399.0),
	Vector3(-7.0, 0.0, -444.0),
	Vector3(-1.0, 0.0, -489.0),
	Vector3(6.0, 0.0, -534.0),
	Vector3(3.0, 0.0, -579.0),
	Vector3(-4.0, 0.0, -624.0),
	Vector3(8.0, 0.0, -669.0),
	Vector3(-9.0, 0.0, -714.0),
	Vector3(0.0, 0.0, -759.0),
	Vector3(5.0, 0.0, -804.0),
	Vector3(-3.0, 0.0, -849.0),
	Vector3(1.0, 0.0, -894.0),
]


## The lane's owner: carries the layout the scene and the regression read back.
class Root extends Node3D:
	var lane := PackedVector3Array()
	var length := 0.0
	var width := WIDTH
	var start := Vector3.ZERO
	var arch := Vector3.ZERO
	var torches: Array = []
	var spawn_posts: Array = []
	var clearings: Array = []
	var pursuer_posts: Array = []
	var clearing_posts: Array = []
	var groups: Dictionary = {}
	var stats: Dictionary = {}
	## One static body for every prop that needs a footprint.
	var solids: StaticBody3D


## The lane as a measured polyline: arc length, frames and distance queries.
class Path extends RefCounted:
	var points := PackedVector3Array()
	## Cumulative arc length at each point (index 0 is 0.0).
	var marks := PackedFloat32Array()
	var total := 0.0

	func setup(lane: PackedVector3Array) -> void:
		points = lane
		marks = PackedFloat32Array()
		total = 0.0
		for index in points.size():
			if index == 0:
				marks.append(0.0)
				continue
			total += points[index - 1].distance_to(points[index])
			marks.append(total)

	## The frame at arc distance `at`: where the lane is, which way it runs and
	## which way is its right-hand verge.
	func sample(at: float) -> Dictionary:
		var distance := clampf(at, 0.0, total)
		var index := 0
		for probe in range(points.size() - 1):
			if distance <= marks[probe + 1]:
				index = probe
				break
			index = points.size() - 2
		var from := points[index]
		var to := points[index + 1]
		var span := maxf(0.0001, marks[index + 1] - marks[index])
		var t := clampf((distance - marks[index]) / span, 0.0, 1.0)
		var forward := (to - from) / (to - from).length()
		return {
			"position": from.lerp(to, t),
			"forward": forward,
			"right": Vector3(forward.z, 0.0, -forward.x),
		}

	## A point `offset` metres to the right of the lane at arc distance `at`.
	func verge(at: float, offset: float) -> Vector3:
		var frame := sample(at)
		return (frame["position"] as Vector3) + (frame["right"] as Vector3) * offset

	## Perpendicular distance from a point to the lane, in XZ.
	func distance_to(point: Vector2) -> float:
		var best := INF
		for index in range(points.size() - 1):
			var a := points[index]
			var b := points[index + 1]
			var ax := a.x
			var az := a.z
			var bx := b.x - ax
			var bz := b.z - az
			var length_squared := bx * bx + bz * bz
			var t := 0.0
			if length_squared > 0.000001:
				t = clampf(((point.x - ax) * bx + (point.y - az) * bz) / length_squared, 0.0, 1.0)
			var cx := ax + bx * t - point.x
			var cz := az + bz * t - point.y
			best = minf(best, sqrt(cx * cx + cz * cz))
		return best


## Builds the lane under `parent` (the scene root) and returns the layout:
## `{root, lane, length, width, torches, spawn_posts, arch, clearings, start,
## path, stats}`. Nothing here is ever rebuilt.
##
## `options` is how the lane is *placed* in the one world instead of standing on
## its own:
##   * `offset` - the whole way moves as one: its first waypoint lands where the
##     caller wants it to start, and every prop, torch and collider moves with
##     it, because they are all laid out in lane space.
##   * `ground` (default true) - the lane's own floor and catch floor. The world
##     scene owns one heightfield for the whole map, so it asks for none.
##   * `arch` (default true) - the village gate and its threshold stones at the
##     far end. The world's town builds its own gate at the edge of the square,
##     so the lane ends where the settlement begins instead of doubling it.
static func build(parent: Node3D, options: Dictionary = {}) -> Dictionary:
	if parent == null:
		return {}
	var offset: Vector3 = options.get("offset", Vector3.ZERO)
	var shifted := PackedVector3Array()
	for point in LANE_POINTS:
		shifted.append(point + offset)
	var path := Path.new()
	path.setup(shifted)
	var with_ground := bool(options.get("ground", true))
	var with_arch := bool(options.get("arch", true))

	var root := Root.new()
	root.name = "RunForest"
	parent.add_child(root)
	root.lane = path.points
	root.length = path.total
	root.width = WIDTH
	root.start = path.points[0]
	root.arch = path.points[path.points.size() - 1]
	root.spawn_posts = _spawn_posts(path)
	root.clearings = _clearing_points(path)
	root.pursuer_posts = _pursuer_posts(path)
	root.clearing_posts = _clearing_posts(path)

	var style := night_style()
	var environment: Dictionary = WorldEnvironmentKit.build(root, style)
	root.stats["sun"] = environment.get("sun") != null
	root.solids = _solids(root)
	if with_ground:
		_build_ground(root, style, path)
	else:
		_build_catch_floor(root, path)
	_build_trees(root, style, path)
	_build_bushes(root, style, path)
	_build_grass(root, style, path)
	_build_rocks(root, path)
	_build_torches(root, path)
	if with_arch:
		_build_arch(root, path)
	_build_hanging(root, path)
	_build_omens(root, path)
	_build_fires(root, path)
	_build_scatter(root, path)

	root.stats["nodes"] = _count_nodes(root)
	root.stats["draws"] = _count_type(root, "MultiMeshInstance3D")
	root.stats["meshes"] = _count_type(root, "MeshInstance3D")
	root.stats["lights"] = _count_type(root, "OmniLight3D")
	print("RUN_FOREST_READY length=%.1f width=%.1f torches=%d trees=%d bushes=%d nodes=%d draws=%d"
		% [root.length, root.width, root.torches.size(), int(root.stats.get("trees", 0)),
			int(root.stats.get("bushes", 0)), int(root.stats.get("nodes", 0)),
			int(root.stats.get("draws", 0))])

	return {
		"root": root,
		"lane": root.lane,
		"length": root.length,
		"width": root.width,
		"torches": root.torches,
		"spawn_posts": root.spawn_posts,
		"arch": root.arch,
		"clearings": root.clearings,
		"pursuer_posts": root.pursuer_posts,
		"clearing_posts": root.clearing_posts,
		"start": root.start,
		"path": path,
		"groups": root.groups,
		"stats": root.stats,
	}


# --- the palette -----------------------------------------------------------

## The wood at night: the frontier's own terrain and foliage, one stop down, with
## the depth fog replaced by a thick exponential haze the torches have to cut
## through. EnvironmentKit writes the density after the fog mode, which is the
## only way a density survives in Godot 4.7.
##
## Public because the one world is *this* night, not three: the camp clearing and
## the town are built inside the same style, so a body that walks from the cages
## to the square never crosses a seam in the light or the fog.
static func night_style() -> WorldStyle:
	var style := WorldStyle.frontier()
	style.id = "escape_run"
	style.sky = {
		"texture": "sky_frontier",
		"energy": 0.10,
		"sun_rotation": Vector3(-58.0, -34.0, 0.0),
		"sun_color": Color(0.54, 0.62, 0.88),
		"sun_energy": 0.92,
		"sun_shadow_distance": 70.0,
		"ambient_color": Color(0.125, 0.15, 0.205),
		"sun_shadows": false,
		"ambient_energy": 2.2,
		"use_sky_ambient": false,
		"fog_mode": "exponential",
		"fog_color": Color(0.05, 0.065, 0.095),
		"fog_density": 0.012,
		"fog_sun_scatter": 0.0,
		"fog_sky_affect": 0.0,
		"fog_aerial_perspective": 0.0,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"exposure": 1.0,
		"saturation": 0.80,
		"contrast": 1.06,
	}
	style.ground = {
		"grass_texture": "terrain_grass",
		"dirt_texture": "terrain_dirt",
		"rock_texture": "terrain_rock",
		"macro_texture": "terrain_macro",
		"tile": 6.0,
		"dirt_tile": 5.0,
		"rock_tile": 4.0,
		"macro_tile": 24.0,
		"grass_tint": Color("333d29"),
		"dirt_tint": Color("4a3f30"),
		"rock_tint": Color("33312b"),
		"detail_strength": 0.55,
		"detail_fade": Vector2(70.0, 120.0),
	}
	style.grass = {
		"texture": "grass_meadow",
		"count": 2600,
		"range": 76.0,
		"chunk_size": 96.0,
		"radius": 150.0,
		"tints": [Color("54613c"), Color("44523a"), Color("6b7350"), Color("38452f")],
		"shade_tint": Color("20281c"),
		"wind": Vector2(0.10, 1.2),
		"density_falloff": Vector2(1.0, 0.62),
		"max_slope": 30.0,
		"height_range": Vector2(-2.0, 40.0),
		"scale": Vector2(0.80, 1.5),
		"clump_variants": 2,
	}
	style.ground_cover = {
		"flowers": {
			"texture": "flowers", "count": 340, "range": 58.0, "chunk_size": 96.0,
			"radius": 150.0, "scale": Vector2(0.6, 1.1), "wind": Vector2(0.07, 1.1),
			"max_slope": 26.0, "height_range": Vector2(-2.0, 40.0),
			"tints": [Color("8c8a6a"), Color("7a6a78"), Color("6c7a8c"), Color("8a7a5e")],
			"shade_tint": Color("30361f"),
		},
		"ferns": {
			"texture": "fern", "count": 620, "range": 64.0, "chunk_size": 96.0,
			"radius": 150.0, "scale": Vector2(0.75, 1.45), "wind": Vector2(0.06, 1.0),
			"max_slope": 34.0, "height_range": Vector2(-2.0, 40.0),
			"tints": [Color("41552f"), Color("35472a"), Color("56683c")],
			"shade_tint": Color("1e2718"),
		},
	}
	return style


# --- plumbing --------------------------------------------------------------

static func _group(root: Root, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	root.add_child(node)
	root.groups[label] = node
	return node


static func _host(parent: Node3D, at: Vector3, yaw: float) -> Node3D:
	var node := Node3D.new()
	node.position = at
	node.rotation.y = yaw
	parent.add_child(node)
	return node


## Yaw that turns a node's local +Z toward `direction`.
static func _yaw_facing(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


## Yaw that turns a node's local +X along `direction` (a gate's span).
static func _yaw_spanning(direction: Vector3) -> float:
	return atan2(-direction.z, direction.x)


static func _solids(root: Root) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "LaneCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	return body


static func _solid_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body


static func _trunk_collider(solids: StaticBody3D, at: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at + Vector3(0.0, height * 0.5, 0.0)
	solids.add_child(collision)


static func _count_nodes(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		total += 1 + _count_nodes(child)
	return total


static func _count_type(node: Node, type_name: String) -> int:
	var total := 0
	for child in node.get_children():
		if child.is_class(type_name):
			total += 1
		total += _count_type(child, type_name)
	return total


# --- layout ----------------------------------------------------------------

## Where the fielded warband stands: the mouth of the lane, inside the walkable
## band, tight enough that the squad is a squad and loose enough not to overlap.
static func _spawn_posts(path: Path) -> Array:
	var posts: Array = []
	var offsets := [
		Vector3(-2.0, 0.0, -0.8), Vector3(-0.7, 0.0, -1.6), Vector3(0.7, 0.0, -1.6),
		Vector3(2.0, 0.0, -0.8), Vector3(-2.6, 0.0, 0.6), Vector3(-0.9, 0.0, 1.0),
		Vector3(0.9, 0.0, 1.0), Vector3(2.6, 0.0, 0.6),
	]
	var frame := path.sample(0.0)
	var forward: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var origin: Vector3 = frame["position"]
	for offset in offsets:
		# Posts are laid out in lane space: forward is -Z-ish, so the offsets are
		# rotated with the lane's own frame, and lifted onto the ground.
		posts.append(TerrainScript.grounded(
			origin + right * float(offset.x) - forward * float(offset.z)))
	return posts


## The three clearings the cult waits in, at the lane's own fractions.
static func _clearing_points(path: Path) -> Array:
	var points: Array = []
	for fraction in CLEARING_FRACTIONS:
		var frame := path.sample(path.total * float(fraction))
		points.append(TerrainScript.grounded(frame["position"]))
	return points


## The two that start behind the squad, at the camp mouth: close enough to be on
## them at once, inside the lane so they are never walled off from the run.
static func _pursuer_posts(path: Path) -> Array:
	# The first ambush stands well down the road, not on the camp's doorstep. The
	# camp's own fight happens around the cages and a cultist's sight reaches 60 m,
	# so anything closer joins the tutorial. On a nine-hundred-metre road this is
	# ~90 m in; the rest of the ambushes follow every ~100 m after it.
	var at := path.total * 0.10
	var head := path.sample(at)
	var back: Vector3 = (head["position"] as Vector3) - (head["forward"] as Vector3) * 3.2
	var right: Vector3 = head["right"]
	return [TerrainScript.grounded(back + right * 1.9),
		TerrainScript.grounded(back - right * 1.9)]


## A pair in each clearing, split across the lane so the run is intercepted from
## both sides rather than by a single body in the middle.
static func _clearing_posts(path: Path) -> Array:
	var posts: Array = []
	for fraction in CLEARING_FRACTIONS:
		var frame := path.sample(path.total * float(fraction))
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		posts.append(TerrainScript.grounded(point + right * 1.7))
		posts.append(TerrainScript.grounded(point - right * 1.7))
	return posts


# --- ground ----------------------------------------------------------------

## The lane's own footprint: its centre and extent, verges included. Only the
## lane's own floor uses it now - the one world owns the heightfield, and the
## route lies on it.
static func lane_extent(path: Path) -> Dictionary:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point in path.points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.z)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.z)
	var size := Vector2(maxf(maximum.x - minimum.x, WIDTH), maxf(maximum.y - minimum.y, WIDTH))
	size += Vector2(VERGE * 2.0, VERGE * 2.0)
	return {"centre": (minimum + maximum) * 0.5, "size": size}


## The lane standing on its own: a flat floor under it. In the one world this is
## never built - the world's heightfield is the only ground.
static func _build_ground(root: Root, style: WorldStyle, path: Path) -> void:
	var ground := TextureLibrary.ground_material(style)
	var extent: Dictionary = lane_extent(path)
	var centre: Vector2 = extent["centre"]
	var size: Vector2 = extent["size"]
	# One floor under the whole lane. No ledge, no seam and no hole: the run is a
	# walk, and a walk must never fall out of the world.
	_solid_box(root, Vector3(size.x, 0.6, size.y), Vector3(centre.x, -0.3, centre.y), ground)
	var field := Geo.box(root, Vector3(size.x + 220.0, 0.3, size.y + 220.0),
		Vector3(centre.x, -0.75, centre.y), ground)
	field.name = "ForestField"
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_catch_floor(root, path)


## A last-resort floor: no fall is ever fatal or endless, whatever is pushed. The
## world scene owns the map's real ground and asks for nothing here.
static func _build_catch_floor(root: Root, path: Path) -> void:
	var extent: Dictionary = lane_extent(path)
	var centre: Vector2 = extent["centre"]
	var size: Vector2 = extent["size"]
	var catch_body := StaticBody3D.new()
	catch_body.name = "CatchFloor"
	catch_body.position = Vector3(centre.x, TerrainScript.floor_bottom() - 2.0, centre.y)
	catch_body.collision_layer = 1
	catch_body.collision_mask = 0
	root.add_child(catch_body)
	var catch_shape := CollisionShape3D.new()
	var catch_box := BoxShape3D.new()
	catch_box.size = Vector3(size.x + 260.0, 0.4, size.y + 260.0)
	catch_shape.shape = catch_box
	catch_body.add_child(catch_shape)


# --- the wood --------------------------------------------------------------

## One row of the wood: how far off the way its trees stand, how often they come,
## how far they wander about that line, and whether a body can walk into them. The
## near two rows carry the trunks a body has to get round; the rest is batched
## forest, which closes the horizon through the fog for the price of a multimesh.
## Six rows a side, twice the treeline this lane grew out of.
static func _wood_rows() -> Array:
	return [
		{"offset": 3.2, "spacing": 8.0, "jitter": 0.8, "scale": Vector2(0.85, 1.25), "solid": true},
		{"offset": 4.9, "spacing": 9.0, "jitter": 1.8, "scale": Vector2(0.9, 1.3), "solid": false},
		{"offset": 7.4, "spacing": 11.0, "jitter": 2.6, "scale": Vector2(0.95, 1.4), "solid": true},
		{"offset": 11.5, "spacing": 10.5, "jitter": 3.4, "scale": Vector2(1.0, 1.5), "solid": false},
		{"offset": 16.5, "spacing": 12.5, "jitter": 4.2, "scale": Vector2(1.05, 1.6), "solid": false},
		{"offset": 22.0, "spacing": 14.5, "jitter": 5.0, "scale": Vector2(1.1, 1.75), "solid": false},
	]


## The wood along the way, planted band by band from the worn line out to the fog.
## Trees stand *in* the walked band - that is the point of it - and the only rule
## they obey is that no trunk a body can walk into reaches inside `CLEAR_HALF` of
## the centre line.
static func _build_trees(root: Root, style: WorldStyle, path: Path) -> void:
	var group := _group(root, "Trees")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var records: Array[Dictionary] = []
	for entry in [["ironoak", 2], ["briar_pine", 2], ["hollow_snag", 1]]:
		var species: Dictionary = style.species_by_id(String(entry[0]))
		if species.is_empty():
			continue
		var built: Array = TreeKit.build_variants(species, SEED + records.size() * 31)
		for index in mini(int(entry[1]), built.size()):
			records.append({
				"variant": built[index], "species": species,
				"trunks": [] as Array[Dictionary], "leaves": [] as Array[Dictionary],
			})
	if records.is_empty():
		return
	var planted := 0
	var solid_trees := 0
	for row in _wood_rows():
		var offset := float(row["offset"])
		var spacing := float(row["spacing"])
		var jitter := float(row["jitter"])
		for side in [-1.0, 1.0]:
			var at := rng.randf_range(0.0, spacing)
			while at < path.total:
				var frame := path.sample(at)
				var right: Vector3 = frame["right"]
				var ground_point: Vector3 = (frame["position"] as Vector3) \
					+ right * side * (offset + rng.randf_range(-jitter, jitter))
				var record: Dictionary = records[rng.randi_range(0, records.size() - 1)]
				var variant: Dictionary = record["variant"]
				var species: Dictionary = record["species"]
				var scale_at := rng.randf_range(float(row["scale"].x), float(row["scale"].y))
				var tree_height := float(variant.get("height", 8.0)) * scale_at
				var trunk_spec: Vector2 = species.get("trunk", Vector2(0.04, 0.62))
				var trunk_height := maxf(1.4, tree_height * float(trunk_spec.y) * 0.95)
				var trunk_radius := maxf(0.18, tree_height * float(trunk_spec.x) * 1.04)
				at += spacing * rng.randf_range(0.82, 1.24)
				# The way stays clear: a trunk whose bark would reach inside the
				# walked line is not planted at all. That is the whole reason the
				# route is passable with the walls gone.
				if path.distance_to(Vector2(ground_point.x, ground_point.z)) - trunk_radius < CLEAR_HALF:
					continue
				var point := TerrainScript.grounded(Vector3(ground_point.x, 0.0, ground_point.z))
				var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_at)
				var xform := Transform3D(basis, point)
				var tints: Array = species.get("tints", [])
				(record["trunks"] as Array[Dictionary]).append({
					"transform": xform,
					"color": _pick(species.get("bark_tints", []), rng, Color.WHITE),
				})
				if variant.get("leaves") != null and not tints.is_empty():
					(record["leaves"] as Array[Dictionary]).append({
						"transform": xform,
						"color": _pick(tints, rng, Color.WHITE),
					})
				if bool(row["solid"]):
					_trunk_collider(root.solids, point, trunk_radius, trunk_height)
					solid_trees += 1
				planted += 1
	var batch_index := 0
	for record in records:
		var variant: Dictionary = record["variant"]
		WorldScatter.batch(group, "Trunk_%d" % batch_index, variant["trunk"],
			TextureLibrary.bark_material(String(variant["bark"])), record["trunks"],
			TREE_CHUNK, {"cast_shadow": true})
		if variant.get("leaves") != null and not (record["leaves"] as Array).is_empty():
			WorldScatter.batch(group, "Leaves_%d" % batch_index, variant["leaves"],
				TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]),
					variant.get("wind", Vector2(0.08, 1.0))),
				record["leaves"], TREE_CHUNK, {"cast_shadow": true})
		batch_index += 1
	root.stats["trees"] = planted
	root.stats["solid_trees"] = solid_trees


static func _build_bushes(root: Root, style: WorldStyle, path: Path) -> void:
	var group := _group(root, "Bushes")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var atlases: Array = []
	for species in style.trees:
		var leaves := String(species.get("leaves", ""))
		if leaves.is_empty() or atlases.has(leaves):
			continue
		atlases.append(leaves)
	var placed := 0
	var atlas_index := 0
	for atlas in atlases:
		var variants := BushKit.build_variants(String(atlas), SEED + atlas_index * 13)
		var wind := _wind_for(style, String(atlas))
		var buckets: Array = []
		for probe in variants.size():
			buckets.append([] as Array[Dictionary])
		var at := 0.0
		while at < path.total:
			for side in [-1.0, 1.0]:
				if rng.randf() > 0.68:
					continue
				# Brush stands in the walked band too, right up to the edge of the
				# clear line: nothing here has a collider, so it can.
				var point := path.verge(at + rng.randf_range(-1.4, 1.4),
					side * rng.randf_range(CLEAR_HALF + 0.3, VERGE))
				var scale_at := rng.randf_range(0.75, 1.55)
				var slot := rng.randi_range(0, variants.size() - 1)
				(buckets[slot] as Array[Dictionary]).append({
					"transform": Transform3D(
						Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
							Vector3(scale_at, scale_at * rng.randf_range(0.8, 1.2), scale_at)),
						TerrainScript.grounded(Vector3(point.x, 0.0, point.z))),
					"color": Color(rng.randf_range(0.62, 0.86), rng.randf_range(0.66, 0.9),
						rng.randf_range(0.58, 0.82), 1.0),
				})
				placed += 1
			at += rng.randf_range(2.8, 4.4)
		for slot in variants.size():
			WorldScatter.batch(group, "Bush_%d_%d" % [atlas_index, slot], variants[slot]["mesh"],
				TextureLibrary.foliage_material_tuned(String(atlas), wind), buckets[slot],
				BUSH_CHUNK, {"cast_shadow": true, "visible_end": 62.0})
		atlas_index += 1
	root.stats["bushes"] = placed


static func _wind_for(style: WorldStyle, atlas: String) -> Vector2:
	for species in style.trees:
		if String(species.get("leaves", "")) == atlas:
			return species.get("wind", Vector2(0.08, 1.0))
	return Vector2(0.08, 1.0)


static func _pick(pool: Array, rng: RandomNumberGenerator, fallback: Color) -> Color:
	if pool.is_empty():
		return fallback
	return pool[rng.randi_range(0, pool.size() - 1)]


## The lawn and the ferns, both confined to the route's verge: two meadows, one at
## each end of the run, so the whole way has grass under it. The field is centred on
## its host and places its clumps in *local* space, so the ground callable answers
## relative to the host and at the heightfield's own height.
static func _build_grass(root: Root, style: WorldStyle, path: Path) -> void:
	var counts := {"grass": 0, "flowers": 0, "ferns": 0, "chunks": 0}
	var group := _group(root, "Grass")
	for index in 2:
		var at := path.total * (0.25 + 0.5 * float(index))
		var frame := path.sample(at)
		var centre := Vector3((frame["position"] as Vector3).x, 0.0, (frame["position"] as Vector3).z)
		var host := Node3D.new()
		host.name = "Grass%d" % (index + 1)
		host.position = centre
		group.add_child(host)
		var ground := func(point: Vector2) -> Vector3:
			return Vector3(point.x - centre.x, TerrainScript.height_at(point.x, point.y),
				point.y - centre.z)
		var reserved := func(point: Vector2) -> bool: return path.distance_to(point) > GRASS_BAND
		var built: Dictionary = GrassField.build(host, style, ground, reserved, SEED + 401 + index * 17)
		for key in counts.keys():
			counts[key] = int(counts[key]) + int(built.get(key, 0))
	root.stats["grass"] = int(counts["grass"])
	root.stats["ferns"] = int(counts["ferns"])
	root.stats["flowers"] = int(counts["flowers"])


## Stone: boulders bedded in the verge and loose cobbles trodden into the worn
## line. Both are merged into one mesh each, so the whole run's stone is two draw
## calls.
static func _build_rocks(root: Root, path: Path) -> void:
	var group := _group(root, "Rocks")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 13
	var material := TextureLibrary.rock_material()
	var meshes: Array[ArrayMesh] = [
		RockKit.mesh("boulder", 2711), RockKit.mesh("slab", 2749), RockKit.mesh("boulder", 2787),
	]
	var boulders := CampKit.Merged.new()
	for index in 68:
		var at := rng.randf_range(0.0, path.total)
		var side := -1.0 if index % 2 == 0 else 1.0
		var point := path.verge(at, side * rng.randf_range(3.2, 13.0))
		var stone: ArrayMesh = meshes[rng.randi_range(0, meshes.size() - 1)]
		RockKit.add_stone(boulders, material, stone,
			TerrainScript.grounded(Vector3(point.x, -0.05, point.z)),
			rng.randf_range(0.45, 1.35), rng.randf_range(0.0, TAU), rng.randf_range(0.38, 0.6),
			rng.randf_range(-0.2, 0.2))
	boulders.commit(group, "Boulders", false)
	var cobbles := CampKit.Merged.new()
	var cobble := RockKit.mesh("cobble", 6301)
	for index in 150:
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-4.0, 4.0))
		RockKit.add_stone(cobbles, material, cobble,
			TerrainScript.grounded(Vector3(point.x, -0.02, point.z)),
			rng.randf_range(0.10, 0.3), rng.randf_range(0.0, TAU), 0.55, rng.randf_range(-0.25, 0.25))
	cobbles.commit(group, "Cobbles", false)
	root.stats["rocks"] = 68 + 150


# --- fire ------------------------------------------------------------------

## The way's only furniture: a pair of torches every `TORCH_SPACING` metres, set
## back from the worn line on the verge. There is no lane to light any more - the
## lights are the route, and at any distance they are the only clear thing in the
## wood. Each is a staked post, an iron cup and the world's own flame cards on the
## shared flame shader, with a light that breathes (FireFlicker) and embers off
## every other one.
static func _build_torches(root: Root, path: Path) -> void:
	var group := _group(root, "Torches")
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 3
	var at := 0.0
	var index := 0
	while at < path.total - 4.0:
		for side in [-1.0, 1.0]:
			# The pair stands opposite each other, give or take: a rhythm, not a
			# surveyed line.
			var lateral := TORCH_OFFSET + rng.randf_range(-0.9, 0.9)
			var point := path.verge(at + rng.randf_range(-1.4, 1.4), side * lateral)
			var foot := TerrainScript.grounded(Vector3(point.x, 0.0, point.z))
			_torch(group, mats, iron, foot, SEED + index * 29, index % 2 == 0)
			root.torches.append(foot)
			index += 1
		at += TORCH_SPACING
	root.stats["torches"] = root.torches.size()


static func _torch(group: Node3D, mats: Dictionary, iron: Dictionary, at: Vector3,
		seed_value: int, with_embers: bool) -> void:
	var host := _host(group, at, 0.0)
	host.name = "Torch%d" % group.get_child_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := CampKit.Merged.new()
	CampKit.add_beam(m, Vector3(0.0, -0.25, 0.0), Vector3(0.06, 2.46, 0.03), 0.085,
		mats["drift_dark"], 6, 0.055)
	CampKit.add_ring(m, Vector3(0.05, 1.92, 0.02), 0.0, 0.10, 0.145, iron["iron"], 0.0, 8, 3)
	CampKit.add_ring(m, Vector3(0.05, 2.42, 0.02), 0.0, 0.17, 0.215, iron["iron"], 0.0, 12, 3)
	CampKit.add_ball(m, 0.09, Vector3(0.05, 2.46, 0.02), mats["fire_core"],
		Vector3(1.0, 0.55, 1.0), 7, 4)
	FireFx.flame_cards(m, mats["flame"], rng, 0.54, 2.44)
	m.commit(host, "TorchPost")
	if with_embers:
		FireFx.embers(host, 2.44, 0.26, 12)
	var light := FireFlicker.new()
	light.name = "TorchLight"
	light.position = Vector3(0.05, 2.62, 0.02)
	light.light_color = Color(1.0, 0.56, 0.22)
	light.light_energy = 3.4
	light.omni_range = 16.0
	light.omni_attenuation = 1.0
	light.flicker = 0.26
	light.shadow_enabled = false
	host.add_child(light)


## The town's gate at the end of the lane, wide enough to frame the whole
## corridor, with two braziers and the name of the place over it.
static func _build_arch(root: Root, path: Path) -> void:
	var group := _group(root, "Arch")
	var frame := path.sample(path.total)
	var tail: Vector3 = TerrainScript.grounded(frame["position"])
	var yaw := _yaw_spanning(frame["forward"])
	var host := _host(group, tail, yaw)
	host.name = "Gate"
	var mats: Dictionary = VillageKit.materials()
	VillageKit.gate(host, mats, root.solids, HALF_WIDTH + 0.45, 5.2, 9)
	var label := Label3D.new()
	label.text = "TOWN"
	label.position = Vector3(0.0, 5.9, 0.0)
	label.font_size = 96
	label.pixel_size = 0.013
	label.modulate = Color(1.0, 0.78, 0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	host.add_child(label)
	# The gate's own threshold stones read the lane closed at the far end.
	var stone := Geo.material(Color(0.20, 0.19, 0.17))
	for side in [-1.0, 1.0]:
		Geo.box(host, Vector3(1.4, 0.22, 1.0), Vector3(side * (HALF_WIDTH - 1.0), 0.11, 0.4), stone)


# --- the cult's furniture --------------------------------------------------

## Trees with rags tied on, gallows trees, ropes of charms strung across the
## lane, charm webs and bone arches: the "stuff hanging" the wood is read from.
static func _build_hanging(root: Root, path: Path) -> void:
	var group := _group(root, "Hanging")
	var mats: Dictionary = CampKit.materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 23
	# Seven rag trees, alternating sides.
	for index in 7:
		var at := path.total * (0.06 + 0.135 * float(index))
		var side := -1.0 if index % 2 == 0 else 1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 1.4)))
		var frame := path.sample(at)
		var yaw := _yaw_facing(-(frame["right"] as Vector3) * side)
		var host := _host(group, point, yaw)
		host.name = "RagTree%d" % (index + 1)
		CampKit.rag_tree(host, mats, root.solids, SEED + 7 + index * 11)
	# Three gallows trees, the village's own dead crown, one merged mesh.
	var gallows := VillageKit.Merged.new()
	for index in 3:
		var at := path.total * (0.22 + 0.25 * float(index))
		var side := 1.0 if index % 2 == 0 else -1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 2.6)))
		VillageKit.gallows_tree(gallows, VillageKit.materials(), root.solids,
			point, rng.randf_range(0.0, TAU), SEED + 31 + index * 7)
	gallows.commit(group, "GallowsTrees")
	# Ropes of charms strung from tree to tree across the path, high enough that
	# a body runs under them.
	var ropes := CampKit.Merged.new()
	for index in 4:
		var at := path.total * (0.14 + 0.22 * float(index))
		var left := path.verge(at, -(HALF_WIDTH + 1.1))
		var right := path.verge(at, HALF_WIDTH + 1.1)
		left.y = TerrainScript.height_at(left.x, left.z) + rng.randf_range(3.1, 3.5)
		right.y = TerrainScript.height_at(right.x, right.z) + rng.randf_range(3.1, 3.5)
		var mid := left.lerp(right, 0.5)
		mid.y -= rng.randf_range(0.25, 0.45)
		CampKit.add_beam(ropes, left, mid, 0.016, mats["rag"], 3)
		CampKit.add_beam(ropes, mid, right, 0.016, mats["rag"], 3)
		for drop in 3:
			var knot := mid.lerp(left if drop == 0 else right, float(drop) / 3.0)
			CampKit.add_hanging(ropes, mats, knot, rng.randf_range(0.0, TAU), SEED + drop * 13 + index, 0.75)
	ropes.commit(group, "CharmRopes")
	# Two charm webs and two bone arches: the wardens' string-work over the road.
	for index in 2:
		var at := path.total * (0.35 + 0.4 * float(index))
		var side := -1.0 if index == 0 else 1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 2.4)))
		var host := _host(group, point, _yaw_facing(
			-(path.sample(at)["right"] as Vector3) * side))
		host.name = "CharmWeb%d" % (index + 1)
		CampKit.charm_web(host, mats, root.solids, 2.6, 1.9, SEED + 43 + index * 5)
	for index in 2:
		var at := path.total * (0.42 + 0.3 * float(index))
		var frame := path.sample(at)
		var host := _host(group, TerrainScript.grounded(frame["position"]),
			_yaw_spanning(frame["forward"]))
		host.name = "BoneArch%d" % (index + 1)
		CampKit.bone_arch(host, mats, root.solids, HALF_WIDTH + 1.6, 3.2, SEED + 61 + index * 3)
	root.stats["hanging"] = 7 + 3 + 4 + 2 + 2


## The omens along the verge: wicker effigies, skull-stake runs, a drying rack and
## a cauldron. All outside the walkable band.
static func _build_omens(root: Root, path: Path) -> void:
	var group := _group(root, "Omens")
	var mats: Dictionary = CampKit.materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 37
	for index in 2:
		var at := path.total * (0.17 + 0.55 * float(index))
		var side := 1.0 if index == 0 else -1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 2.0)))
		var host := _host(group, point, _yaw_facing(
			-(path.sample(at)["right"] as Vector3) * side))
		host.name = "Effigy%d" % (index + 1)
		CampKit.wicker_effigy(host, mats, root.solids, SEED + 71 + index * 9)
	var stakes := CampKit.Merged.new()
	for index in 3:
		var at := path.total * (0.28 + 0.22 * float(index))
		var side := -1.0 if index % 2 == 0 else 1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 1.6)))
		var frame := path.sample(at)
		var yaw := _yaw_facing(frame["forward"])
		CampKit.skull_stakes(stakes, mats, point, yaw, 4, 0.8,
			SEED + 83 + index * 5)
	for index in 2:
		var at := path.total * (0.47 + 0.3 * float(index))
		var side := 1.0 if index == 0 else -1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 2.2)))
		var host := _host(group, point, rng.randf_range(0.0, TAU))
		host.name = "Rack%d" % (index + 1)
		CampKit.drying_rack(host, mats, root.solids, SEED + 97 + index * 11)
	stakes.commit(group, "SkullStakes")
	var cauldron := CampKit.Merged.new()
	for index in 2:
		var at := path.total * (0.33 + 0.4 * float(index))
		var side := -1.0 if index == 0 else 1.0
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 1.8)))
		CampKit.cauldron(cauldron, mats, point, rng.randf_range(0.0, TAU), 1.0)
	cauldron.commit(group, "Cauldrons")
	root.stats["omens"] = 2 + 3 + 2 + 2


## Fires: the cult's camp fires in the three clearings and iron braziers at the
## town gate and along the worst of the dark.
static func _build_fires(root: Root, path: Path) -> void:
	var group := _group(root, "Braziers")
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var index := 0
	for clearing in root.clearings:
		var at := path.total * float(CLEARING_FRACTIONS[index])
		var side := -1.0 if index % 2 == 0 else 1.0
		# On the verge, never in the walkable band: a fire ring is solid, and a body
		# hugging the inside of a bend must not jam on one.
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 1.1)))
		var host := _host(group, point, 0.0)
		host.name = "CampFire%d" % (index + 1)
		CampKit.fire_ring(host, mats, SEED + 5 + index * 3)
		index += 1
	for entry in [
		{"at": 0.10, "side": -1.0}, {"at": 0.52, "side": 1.0},
		{"at": 0.78, "side": -1.0}, {"at": 0.94, "side": -1.0}, {"at": 0.97, "side": 1.0},
	]:
		var at: float = path.total * float(entry["at"])
		var side: float = float(entry["side"])
		var point := TerrainScript.grounded(path.verge(at, side * (HALF_WIDTH + 1.2)))
		_brazier(group, mats, iron, point, SEED + 101 + index * 7)
		index += 1
	root.stats["fires"] = index


## An iron tripod and a bowl of coals, burning on the world's flame cards with
## embers off it and a light that breathes - the camp dressing's brazier, rebuilt
## from the same kit primitives because the lane needs one of its own.
static func _brazier(group: Node3D, mats: Dictionary, iron: Dictionary, at: Vector3,
		seed_value: int) -> void:
	var host := _host(group, at, 0.0)
	host.name = "Brazier%d" % group.get_child_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := CampKit.Merged.new()
	for leg in 3:
		var angle := TAU * float(leg) / 3.0 + 0.3
		CampKit.add_beam(m, Vector3(cos(angle) * 0.52, 0.0, sin(angle) * 0.52),
			Vector3(cos(angle) * 0.10, 0.92, sin(angle) * 0.10), 0.045, iron["iron"], 5, 0.032)
	CampKit.add_ring(m, Vector3(0.0, 0.42, 0.0), 0.0, 0.30, 0.34, iron["iron"], 0.0, 10, 4)
	var bowl := CylinderMesh.new()
	bowl.bottom_radius = 0.26
	bowl.top_radius = 0.46
	bowl.height = 0.26
	bowl.radial_segments = 12
	bowl.rings = 1
	m.add(bowl, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.04, 0.0)), iron["iron"])
	CampKit.add_ring(m, Vector3(0.0, 1.17, 0.0), 0.0, 0.44, 0.49, iron["steel"], 0.0, 12, 4)
	for coal in 4:
		var angle := TAU * float(coal) / 4.0 + 0.7
		CampKit.add_ball(m, 0.075, Vector3(cos(angle) * 0.16, 1.15, sin(angle) * 0.16),
			mats["ember"], Vector3(1.1, 0.55, 1.1), 6, 4)
	CampKit.add_ball(m, 0.14, Vector3(0.0, 1.16, 0.0), mats["fire_core"],
		Vector3(1.0, 0.40, 1.0), 7, 4)
	FireFx.flame_cards(m, mats["flame"], rng, 0.95, 1.14)
	m.commit(host, "BrazierBowl")
	FireFx.embers(host, 1.18, 0.24, 14)
	var light := FireFlicker.new()
	light.name = "BrazierLight"
	light.position = Vector3(0.0, 1.62, 0.0)
	light.light_color = Color(1.0, 0.58, 0.24)
	light.light_energy = 1.9
	light.omni_range = 11.0
	light.omni_attenuation = 1.35
	light.flicker = 0.30
	light.shadow_enabled = false
	host.add_child(light)


# --- the ground's own litter -----------------------------------------------

## What the wood's floor carries where feet and hooves have passed: patchy trodden
## earth, leaf litter and a few drops of blood, none of it on a line and none of it
## on the centre of the way. There are no cart ruts here any more - this was never
## a road. All of it is flat and lies on the slope it is laid on, so none of it is a
## collider.
static func _build_scatter(root: Root, path: Path) -> void:
	var group := _group(root, "Scatter")
	var mats: Dictionary = CampKit.materials()
	var iron: Dictionary = CampDressing.metal()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 53
	var worn := CampKit.Merged.new()
	for index in 84:
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-4.2, 4.2))
		_ground_patch(worn, iron["rut"], point, rng.randf_range(0.45, 1.8),
			rng.randf_range(0.55, 1.15))
	worn.commit(group, "Trodden", false)
	var straw := CampKit.Merged.new()
	for index in 34:
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-4.6, 4.6))
		_straw(straw, mats, TerrainScript.grounded(Vector3(point.x, 0.0, point.z)), rng, 0.6, 9)
	straw.commit(group, "LeafLitter", false)
	var blood := CampKit.Merged.new()
	for index in 10:
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-3.6, 3.6))
		_ground_patch(blood, iron["blood"], point, rng.randf_range(0.35, 0.7),
			rng.randf_range(0.7, 1.0))
	blood.commit(group, "Blood", false)
	root.stats["scatter"] = 84 + 34 + 10


## A flat stain of worn earth, laid on the ground's own normal so it follows the
## slope instead of cutting into it or floating over it.
static func _ground_patch(m, material: Material, point: Vector3, radius: float,
		stretch: float) -> void:
	var basis := TerrainScript.ground_basis(point.x, point.z, 0.0)
	basis = basis.scaled(Vector3(radius, 1.0, radius * stretch))
	var saved: Transform3D = m.push(Transform3D(basis,
		TerrainScript.grounded(Vector3(point.x, 0.03, point.z))))
	CampKit.add_ball(m, 1.0, Vector3.ZERO, material, Vector3(1.0, 0.03, 1.0), 10, 3)
	m.group = saved


## A handful of broken straw: thin tapered straws leaning out of a heap.
static func _straw(m, mats: Dictionary, at: Vector3, rng: RandomNumberGenerator,
		spread: float, amount: int) -> void:
	for strand in amount:
		var angle := rng.randf_range(0.0, TAU)
		var foot := TerrainScript.grounded(at + Vector3(
			cos(angle) * rng.randf_range(0.0, spread), 0.0,
			sin(angle) * rng.randf_range(0.0, spread)))
		var tip := foot + Vector3(cos(angle) * rng.randf_range(0.12, 0.36),
			rng.randf_range(0.05, 0.24), sin(angle) * rng.randf_range(0.12, 0.34))
		CampKit.add_beam(m, foot, tip, rng.randf_range(0.009, 0.019),
			mats["thatch"] if strand % 2 == 0 else mats["thatch_dark"], 3, 0.004)
