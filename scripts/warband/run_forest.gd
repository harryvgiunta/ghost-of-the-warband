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
##
## And two things that are not the road but the place it runs through. The wood is
## **deep**: sixteen rows a side out to `WOOD_EDGE` (the near six walked past, the
## rest batched in fog-sized cells), with the mountain rim `terrain.gd` raises
## standing beyond them - the trail is a valley, not a strip of trees. One hollow
## in it is **wet**: `terrain.gd`'s swamp basin at `SWAMP_FRACTION` of the route
## gets a flat water plane on the existing water shader, reeds, snags, roots, mud
## and a low mist, all of it off the lane and past the torch line, so the route is
## unchanged and a body that steps off it is wading in the dark.

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
## The near wood's culling cells. The lane is a kilometre and a third long now, and
## a cell edge is paid for on every row the wood plants, so the near rows share a
## 128 m cell: still well inside the fog's own reach, and a fifth fewer multimeshes
## than 96 m cells over the same wood.
const TREE_CHUNK := 128.0
## The deep wood - every row past this offset - is batched in larger chunks: the
## outer rows are seen through fog at 60-plus metres, so a 512 m multimesh cell
## culls nearly as well as a 128 m one for a fraction of the nodes and draws.
const DEEP_ROW_MIN := 26.0
const DEEP_TREE_CHUNK := 512.0
## The wood's own outer edge: no trunk is planted past this. It grew with the lane
## (the wood is the trail's own depth, not a fixed skirt), so the last five rows
## are the mountain rim's forested skirt - sparse, large trees standing at the toe
## of the face, which read as a treeline climbing into the fog - and the rim
## (`terrain.gd`) closes the valley beyond them.
const WOOD_EDGE := 205.0
## Bushes cover the verge in one pass: fewer, larger batches than the trees.
const BUSH_CHUNK := 160.0
## Torches: a pair either side every this many metres, on the verge - outside the
## walked line, because a staked post is solid and a body must never jam on one.
## Eighteen metres is still an unbroken chain of fire: each torch throws sixteen, so
## the pair either side of a body standing between two posts both reach it, and the
## whole 1,375 m route costs 154 lights against the old 152.
const TORCH_SPACING := 18.0
const TORCH_OFFSET := 4.4
## Where the cult stands in pairs. Fractions of the lane's arc length.
const CLEARING_FRACTIONS := [0.22, 0.44, 0.66, 0.88]
## Grass and ferns are confined to the route's verge: the rest of the wood is
## trunks and brambles, and grass a body never sees is a draw call for nothing.
const GRASS_BAND := 12.0
## How often the floor's own litter falls: stone, trodden earth, leaf straw and the
## odd drop of blood, as one of each per this many metres of lane. The counts are
## read off the road's measured length, so a longer road gets more of the same
## litter instead of the same litter spread thinner.
const BOULDER_EVERY := 13.5
const COBBLE_EVERY := 6.1
const TRODDEN_EVERY := 11.0
const STRAW_EVERY := 27.0
const BLOOD_EVERY := 92.0
const SEED := 82117

## The lane, its own first waypoint to the town gate. It winds, but every bend
## still closes on the arch, so a body walking it always has the town ahead of it.
## Thirty straight z-steps of 45 m with the x drifting between -9 and 11: about
## 1,375 m of measured road, and the wood, the torches, the clearings and the
## ground are all derived from these points rather than from a second table.
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
	Vector3(7.0, 0.0, -939.0),
	Vector3(-2.0, 0.0, -984.0),
	Vector3(-8.0, 0.0, -1029.0),
	Vector3(3.0, 0.0, -1074.0),
	Vector3(10.0, 0.0, -1119.0),
	Vector3(-4.0, 0.0, -1164.0),
	Vector3(1.0, 0.0, -1209.0),
	Vector3(-6.0, 0.0, -1254.0),
	Vector3(9.0, 0.0, -1299.0),
	Vector3(-1.0, 0.0, -1344.0),
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
	## Every trunk a body can walk into, as `{"at": Vector2 (x/z), "radius": float}`:
	## the scene's ambushers and the wood's own placements stand clear of them.
	var trunks: Array = []
	## `terrain.gd`'s one hollow, as `swamp_region()` published it, plus the water
	## plane's own numbers. Empty in a preview with no baked ground.
	var swamp: Dictionary = {}
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
	_build_swamp(root, path)
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
		"swamp": root.swamp,
		"trunks": root.trunks,
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
		# The panorama at 0.10 filled the frame with a near-black hemisphere the
		# moment a body turned round; it is a night sky now, not a void, and the
		# sky's own ambient is what keeps the wood behind the squad readable.
		"energy": 0.55,
		"sun_rotation": Vector3(-58.0, -34.0, 0.0),
		"sun_color": Color(0.54, 0.62, 0.88),
		"sun_energy": 1.0,
		"sun_shadow_distance": 70.0,
		"ambient_color": Color(0.17, 0.20, 0.26),
		"sun_shadows": false,
		# Sky ambient at a modest fill: the panorama is brighter now, but this is
		# still a night wood, not a lit stage.
		"ambient_energy": 1.3,
		"use_sky_ambient": true,
		"fog_mode": "exponential",
		# A lighter haze that also eats the sky: the horizon closes at its own
		# distance instead of turning the background into a black wall.
		"fog_color": Color(0.075, 0.094, 0.124),
		"fog_density": 0.012,
		"fog_sun_scatter": 0.05,
		"fog_sky_affect": 0.38,
		"fog_aerial_perspective": 0.18,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"exposure": 1.0,
		"saturation": 0.84,
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


## How many of something a road of `metres` carries at one per `every`: the lane's
## own length is the only place a density is written down, so a longer road grows
## its litter instead of thinning it.
static func _per_metre(metres: float, every: float) -> int:
	return maxi(1, int(round(metres / maxf(every, 0.001))))


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
	# so anything closer joins the tutorial. On this road that is ~140 m in, past
	# the corridor and out of sight of the mouth; the rest follow every ~280 m.
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
## near two solid rows carry the trunks a body has to get round; the rest is
## batched forest, which closes the horizon through the fog for the price of a
## multimesh. Sixteen rows a side, out to `WOOD_EDGE`: the trail is a wood now,
## not a treeline, and the mountains stand beyond it.
static func _wood_rows() -> Array:
	return [
		{"offset": 3.2, "spacing": 8.0, "jitter": 0.8, "scale": Vector2(0.85, 1.25), "solid": true},
		{"offset": 4.9, "spacing": 9.0, "jitter": 1.8, "scale": Vector2(0.9, 1.3), "solid": false},
		{"offset": 7.4, "spacing": 11.0, "jitter": 2.6, "scale": Vector2(0.95, 1.4), "solid": true},
		{"offset": 11.5, "spacing": 10.5, "jitter": 3.4, "scale": Vector2(1.0, 1.5), "solid": false},
		{"offset": 16.5, "spacing": 12.5, "jitter": 4.2, "scale": Vector2(1.05, 1.6), "solid": false},
		{"offset": 22.0, "spacing": 14.5, "jitter": 5.0, "scale": Vector2(1.1, 1.75), "solid": false},
		{"offset": 28.0, "spacing": 16.0, "jitter": 5.4, "scale": Vector2(1.1, 1.8), "solid": false},
		{"offset": 35.0, "spacing": 18.0, "jitter": 6.0, "scale": Vector2(1.15, 1.9), "solid": false},
		{"offset": 43.0, "spacing": 24.0, "jitter": 6.4, "scale": Vector2(1.15, 2.0), "solid": false},
		{"offset": 52.0, "spacing": 28.0, "jitter": 6.8, "scale": Vector2(1.2, 2.1), "solid": false},
		{"offset": 62.0, "spacing": 32.0, "jitter": 7.0, "scale": Vector2(1.2, 2.2), "solid": false},
		{"offset": 73.0, "spacing": 36.0, "jitter": 7.4, "scale": Vector2(1.25, 2.3), "solid": false},
		{"offset": 85.0, "spacing": 40.0, "jitter": 7.8, "scale": Vector2(1.3, 2.4), "solid": false},
		# The rim's skirt: a sparse, oversized treeline at the toe of the mountain
		# face, which is the last thing the fog lets through. It reaches out to
		# `WOOD_EDGE` now, so the wood's depth grows with the lane's length.
		{"offset": 100.0, "spacing": 55.0, "jitter": 7.0, "scale": Vector2(1.25, 2.1), "solid": false},
		{"offset": 125.0, "spacing": 62.0, "jitter": 7.0, "scale": Vector2(1.3, 2.2), "solid": false},
		{"offset": 148.0, "spacing": 68.0, "jitter": 6.5, "scale": Vector2(1.25, 2.1), "solid": false},
		{"offset": 172.0, "spacing": 76.0, "jitter": 6.5, "scale": Vector2(1.3, 2.2), "solid": false},
		{"offset": 196.0, "spacing": 84.0, "jitter": 6.5, "scale": Vector2(1.25, 2.1), "solid": false},
	]


## The wood along the way, planted band by band from the worn line out to the fog.
## Trees stand *in* the walked band - that is the point of it - and the only rule
## they obey is that no trunk a body can walk into reaches inside `CLEAR_HALF` of
## the centre line.
##
## The near rows and the deep rows are batched separately: everything past
## `DEEP_ROW_MIN` is fogged out long before its cell edge, so it pays for a 192 m
## multimesh instead of the near wood's 96 m one.
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
				"deep_trunks": [] as Array[Dictionary],
				"deep_leaves": [] as Array[Dictionary],
			})
	if records.is_empty():
		return
	var planted := 0
	var solid_trees := 0
	var deep_trees := 0
	for row in _wood_rows():
		var offset := float(row["offset"])
		var spacing := float(row["spacing"])
		var jitter := float(row["jitter"])
		var deep := offset >= DEEP_ROW_MIN
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
				# The bark is what a body meets. The species table names the trunk's
				# taper, but an ironoak's base flares well past it - and a collider
				# narrower than the drawn bark is an invisible wall with a tree painted
				# a metre behind it, which is exactly what "I stop two metres short and
				# the camera goes inside the wood" was. The mesh's own footprint is the
				# floor of the number, for the planting rule and the collider alike.
				var trunk_mesh: Mesh = variant.get("trunk")
				if trunk_mesh != null:
					var box := trunk_mesh.get_aabb()
					var bark := maxf(absf(box.position.x), absf(box.end.x)) * scale_at
					trunk_radius = maxf(trunk_radius, bark)
				at += spacing * rng.randf_range(0.82, 1.24)
				# The way stays clear, and the wood stops at its own edge: a trunk
				# whose bark would reach inside the walked line is not planted at
				# all, and nothing stands out in the rim's open ground.
				var lateral := path.distance_to(Vector2(ground_point.x, ground_point.z))
				if lateral > WOOD_EDGE or lateral - trunk_radius < CLEAR_HALF:
					continue
				var point := TerrainScript.grounded(Vector3(ground_point.x, 0.0, ground_point.z))
				var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_at)
				var xform := Transform3D(basis, point)
				var tints: Array = species.get("tints", [])
				var trunk_bucket: Array = record["deep_trunks"] if deep else record["trunks"]
				var leaf_bucket: Array = record["deep_leaves"] if deep else record["leaves"]
				(trunk_bucket as Array[Dictionary]).append({
					"transform": xform,
					"color": _pick(species.get("bark_tints", []), rng, Color.WHITE),
				})
				if variant.get("leaves") != null and not tints.is_empty():
					(leaf_bucket as Array[Dictionary]).append({
						"transform": xform,
						"color": _pick(tints, rng, Color.WHITE),
					})
				if bool(row["solid"]):
					_trunk_collider(root.solids, point, trunk_radius, trunk_height)
					root.trunks.append({"at": Vector2(point.x, point.z), "radius": trunk_radius})
					solid_trees += 1
				if deep:
					deep_trees += 1
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
		WorldScatter.batch(group, "DeepTrunk_%d" % batch_index, variant["trunk"],
			TextureLibrary.bark_material(String(variant["bark"])), record["deep_trunks"],
			DEEP_TREE_CHUNK, {"cast_shadow": true})
		if variant.get("leaves") != null and not (record["deep_leaves"] as Array).is_empty():
			WorldScatter.batch(group, "DeepLeaves_%d" % batch_index, variant["leaves"],
				TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]),
					variant.get("wind", Vector2(0.08, 1.0))),
				record["deep_leaves"], DEEP_TREE_CHUNK, {"cast_shadow": true})
		batch_index += 1
	root.stats["trees"] = planted
	root.stats["deep_trees"] = deep_trees
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
				if rng.randf() > 0.88:
					continue
				# Brush stands in the walked band too, right up to the edge of the
				# clear line: nothing here has a collider, so it can.
				var point := path.verge(at + rng.randf_range(-1.4, 1.4),
					side * rng.randf_range(CLEAR_HALF + 0.3, VERGE))
				var scale_at := rng.randf_range(0.75, 1.55)
				var slot := rng.randi_range(0, variants.size() - 1)
				# The swamp's brush is thicker and near-black: standing water and
				# silt, not the wood's dry verge.
				var wet := TerrainScript.swamp_weight_at(point.x, point.z)
				var shade := 1.0 - 0.45 * wet
				(buckets[slot] as Array[Dictionary]).append({
					"transform": Transform3D(
						Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
							Vector3(scale_at, scale_at * rng.randf_range(0.8, 1.2), scale_at)),
						TerrainScript.grounded(Vector3(point.x, 0.0, point.z))),
					"color": Color(rng.randf_range(0.62, 0.86) * shade,
						rng.randf_range(0.66, 0.9) * shade,
						rng.randf_range(0.58, 0.82) * shade, 1.0),
				})
				placed += 1
				if wet > 0.12 and rng.randf() < 0.8:
					# A second clump in the same bucket: the hollow is choked with
					# growth, for no extra batch.
					var moss := rng.randf_range(0.42, 0.62) * shade
					(buckets[slot] as Array[Dictionary]).append({
						"transform": Transform3D(
							Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
								Vector3(scale_at * 0.8, scale_at * rng.randf_range(1.0, 1.5),
									scale_at * 0.8)),
							TerrainScript.grounded(Vector3(point.x, 0.0, point.z))),
						"color": Color(moss, moss * 1.18, moss * 0.9, 1.0),
					})
					placed += 1
			at += rng.randf_range(2.2, 3.6)
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
		# The verge has grass; the wet hollow does not - its own reeds are built
		# with the swamp, and lawn clumps standing in water read wrong.
		var reserved := func(point: Vector2) -> bool:
			return path.distance_to(point) > GRASS_BAND or TerrainScript.swamp_weight_at(
				point.x, point.y) > 0.30
		var built: Dictionary = GrassField.build(host, style, ground, reserved, SEED + 401 + index * 17)
		for key in counts.keys():
			counts[key] = int(counts[key]) + int(built.get(key, 0))
	root.stats["grass"] = int(counts["grass"])
	root.stats["ferns"] = int(counts["ferns"])
	root.stats["flowers"] = int(counts["flowers"])


## Stone: boulders bedded in the verge and loose cobbles trodden into the worn
## line. Both are merged into one mesh each, so the whole run's stone is two draw
## calls however long the run is.
static func _build_rocks(root: Root, path: Path) -> void:
	var group := _group(root, "Rocks")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 13
	var material := TextureLibrary.rock_material()
	var meshes: Array[ArrayMesh] = [
		RockKit.mesh("boulder", 2711), RockKit.mesh("slab", 2749), RockKit.mesh("boulder", 2787),
	]
	var boulder_count := _per_metre(path.total, BOULDER_EVERY)
	var cobble_count := _per_metre(path.total, COBBLE_EVERY)
	var boulders := CampKit.Merged.new()
	for index in boulder_count:
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
	for index in cobble_count:
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-4.0, 4.0))
		RockKit.add_stone(cobbles, material, cobble,
			TerrainScript.grounded(Vector3(point.x, -0.02, point.z)),
			rng.randf_range(0.10, 0.3), rng.randf_range(0.0, TAU), 0.55, rng.randf_range(-0.25, 0.25))
	cobbles.commit(group, "Cobbles", false)
	root.stats["rocks"] = boulder_count + cobble_count


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


# --- the swamp -------------------------------------------------------------

## The one wet hollow in the wood, laid on `terrain.gd`'s basin: a flat water
## plane on the muddy floor, reeds and dead snags at the waterline, roots running
## out of the bank, and a low mist that drifts over it. The water starts past the
## torch line (`SWAMP_INNER` > 5.4 m), so the route's fire is never standing in
## it, and its shader copy is darker than the world's ponds - this is the one part
## of the trail a body wants a hand torch for.
static func _build_swamp(root: Root, path: Path) -> void:
	var region := TerrainScript.swamp_region()
	if region.is_empty():
		return
	var group := _group(root, "Swamp")
	root.swamp = region.duplicate()
	var centre: Vector3 = region["centre"]
	var water_y := float(region["water_y"])
	var inner := float(region["inner"])
	var outer := float(region["outer"])
	var half := float(region["half_length"])
	var side := float(region.get("side", -1.0))
	var arc := _nearest_arc(path, centre)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 61
	var mats: Dictionary = CampKit.materials()
	# --- the water
	var water := _swamp_water_mesh(path, arc, water_y, inner + 0.7, outer - 0.9, half, side)
	var plane := MeshInstance3D.new()
	plane.name = "Water"
	plane.mesh = water
	var material := TextureLibrary.water_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("shallow_color", Color(0.12, 0.17, 0.14))
	material.set_shader_parameter("deep_color", Color(0.035, 0.065, 0.055))
	material.set_shader_parameter("sky_tint", Color(0.26, 0.32, 0.34))
	material.set_shader_parameter("ripple_strength", 0.20)
	material.set_shader_parameter("base_alpha", 0.92)
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(plane)
	# --- reeds and sedge at the waterline
	var reeds := CampKit.Merged.new()
	var sedge := CampKit.Merged.new()
	var reed_count := 0
	for index in 170:
		var along := rng.randf_range(-half * 0.9, half * 0.9)
		var lateral := inner + rng.randf_range(-0.4, 5.6)
		var frame := path.sample(clampf(arc + along, 0.0, path.total))
		var point := (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * side * lateral
		var wet := TerrainScript.swamp_weight_at(point.x, point.z)
		if wet < 0.05:
			continue
		var foot := TerrainScript.grounded(Vector3(point.x, -0.05, point.z))
		var height := rng.randf_range(0.55, 1.55)
		var lean := Vector3(rng.randf_range(-0.16, 0.16), height,
			rng.randf_range(-0.16, 0.16))
		CampKit.add_beam(reeds if index % 3 != 0 else sedge, foot, foot + lean,
			rng.randf_range(0.010, 0.024), mats["moss"] if index % 4 != 0 else mats["thatch_dark"],
			3, 0.004)
		reed_count += 1
	reeds.commit(group, "Reeds")
	sedge.commit(group, "Sedge")
	# --- dead snags standing in the water
	var snags := CampKit.Merged.new()
	for index in 5:
		var along := rng.randf_range(-half * 0.7, half * 0.7)
		var lateral := inner + rng.randf_range(2.4, 9.0)
		var frame := path.sample(clampf(arc + along, 0.0, path.total))
		var point := (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * side * lateral
		var foot := TerrainScript.grounded(Vector3(point.x, -0.2, point.z))
		var top := foot + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(3.2, 6.4),
			rng.randf_range(-0.8, 0.8))
		CampKit.add_beam(snags, foot, top, rng.randf_range(0.16, 0.30), mats["bark"], 6, 0.05)
		for stub in 2:
			var at := foot.lerp(top, rng.randf_range(0.45, 0.85))
			var out := Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(0.2, 1.1),
				rng.randf_range(-1.3, 1.3))
			CampKit.add_beam(snags, at, at + out, rng.randf_range(0.05, 0.12), mats["bark"], 4, 0.02)
	snags.commit(group, "Snags")
	# --- roots crawling out of the bank, and mud where the water has drawn back
	var roots := CampKit.Merged.new()
	for index in 22:
		var along := rng.randf_range(-half * 0.95, half * 0.95)
		var lateral := inner + rng.randf_range(-1.2, 2.8)
		var frame := path.sample(clampf(arc + along, 0.0, path.total))
		var point := (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * side * lateral
		var foot := TerrainScript.grounded(Vector3(point.x, -0.12, point.z))
		var bend := foot + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.05, 0.4),
			rng.randf_range(-0.7, 0.7))
		CampKit.add_beam(roots, foot, bend, rng.randf_range(0.05, 0.10), mats["bark"], 4, 0.02)
		var tip := bend + Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.25, 0.05),
			rng.randf_range(-1.6, 1.6))
		CampKit.add_beam(roots, bend, tip, rng.randf_range(0.025, 0.05), mats["bark"], 3, 0.01)
	roots.commit(group, "Roots")
	var mud := CampKit.Merged.new()
	var mud_material := Geo.material(Color(0.10, 0.095, 0.075), 0.0, 0.98)
	for index in 40:
		var along := rng.randf_range(-half * 0.95, half * 0.95)
		var lateral := inner + rng.randf_range(-1.4, 4.4)
		var frame := path.sample(clampf(arc + along, 0.0, path.total))
		var point := (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * side * lateral
		var at := TerrainScript.grounded(Vector3(point.x, 0.03, point.z))
		var saved := mud.push(Transform3D(
			TerrainScript.ground_basis(point.x, point.z, rng.randf_range(0.0, TAU)).scaled(
				Vector3(rng.randf_range(0.6, 2.0), 1.0, rng.randf_range(0.9, 2.6))), at))
		CampKit.add_ball(mud, 1.0, Vector3.ZERO, mud_material, Vector3(1.0, 0.02, 1.0), 9, 3)
		mud.group = saved
	mud.commit(group, "Mud", false)
	# --- mist
	_swamp_mist(group, path, arc, water_y, inner, outer, half, side)
	root.stats["swamp"] = 1
	root.stats["swamp_reeds"] = reed_count


## The water's surface: a strip following the lane's own bend, from the torch
## line out to the far bank, at one flat level. The shader is world-space, so no
## UVs are needed; the mesh is two long ribbons rather than a box so it follows
## the route instead of one tangent.
static func _swamp_water_mesh(path: Path, arc: float, level: float, inner: float,
		outer: float, half: float, side: float) -> ArrayMesh:
	var rows := 16
	var columns := [inner, (inner + outer) * 0.5, outer]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in rows + 1:
		var along := lerpf(-half * 0.94, half * 0.94, float(row) / float(rows))
		var frame := path.sample(clampf(arc + along, 0.0, path.total))
		for lateral in columns:
			var point: Vector3 = (frame["position"] as Vector3) \
				+ (frame["right"] as Vector3) * side * float(lateral)
			vertices.append(Vector3(point.x, level, point.z))
	var width := columns.size()
	for row in rows:
		for column in width - 1:
			var a := row * width + column
			var b := a + 1
			var c := a + width
			var d := c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A handful of soft billboards over the water, drifting on their own clock. Low
## and thin, so the far bank still closes and the body walking it keeps a horizon.
static func _swamp_mist(group: Node3D, path: Path, arc: float, level: float, inner: float,
		outer: float, half: float, side: float) -> void:
	var mist := SwampMist.new()
	mist.name = "Mist"
	group.add_child(mist)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.52, 0.58, 0.60, 0.16)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(11.0, 2.6)
	for index in 7:
		var along := lerpf(-half * 0.8, half * 0.8, float(index) / 6.0)
		var lateral := inner + 3.0 + float(index % 3) * 4.2
		var frame := path.sample(clampf(arc + along, 0.0, path.total))
		var point: Vector3 = (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * side * lateral
		var card := MeshInstance3D.new()
		card.name = "Mist%d" % index
		card.mesh = quad
		card.material_override = material
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.position = Vector3(point.x, level + 0.85, point.z)
		mist.add_child(card)
		mist.bases.append(card.position)
	mist.speed = 0.37


## One low bank of mist: every card drifts a little about its own anchor and
## breathes in height, which is enough for a hollow that never had wind in it.
class SwampMist extends Node3D:
	var bases: Array[Vector3] = []
	var speed := 0.35
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		var count := mini(bases.size(), get_child_count())
		for index in count:
			var card := get_child(index) as Node3D
			if card == null:
				continue
			var base: Vector3 = bases[index]
			card.position = base + Vector3(
				sin(_time * speed * 0.6 + float(index) * 1.3) * 0.9,
				sin(_time * speed + float(index) * 0.7) * 0.10,
				cos(_time * speed * 0.45 + float(index) * 0.9) * 0.5)


## The lane's arc distance closest to a world point, so the swamp's props follow
## the route's own curve rather than the region's single tangent.
static func _nearest_arc(path: Path, point: Vector3) -> float:
	var best := 0.0
	var best_distance := INF
	for index in 120:
		var mark := path.total * float(index) / 119.0
		var at := path.sample(mark)
		var position: Vector3 = at["position"]
		var distance := Vector2(position.x - point.x, position.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = mark
	return best


## The town's gate at the end of the lane, wide enough to frame the whole
## corridor, with two braziers and the name of the place over it.
static func _build_arch(root: Root, path: Path) -> void:
	var group := _group(root, "Arch")
	var frame := path.sample(path.total)
	var tail: Vector3 = TerrainScript.grounded(frame["position"])
	# A gate frames the road: its span runs ACROSS the lane, so the body that walks
	# through it walks between the posts. Facing the frame down the lane instead
	# stands both posts on the centre line, fourteen metres apart and right in the
	# walk - which is what the arch did until the walk drove through it.
	var yaw := _yaw_facing(frame["forward"])
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
			_yaw_facing(frame["forward"]))
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
	for index in _per_metre(path.total, TRODDEN_EVERY):
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-4.2, 4.2))
		_ground_patch(worn, iron["rut"], point, rng.randf_range(0.45, 1.8),
			rng.randf_range(0.55, 1.15))
	worn.commit(group, "Trodden", false)
	var straw := CampKit.Merged.new()
	for index in _per_metre(path.total, STRAW_EVERY):
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-4.6, 4.6))
		_straw(straw, mats, TerrainScript.grounded(Vector3(point.x, 0.0, point.z)), rng, 0.6, 9)
	straw.commit(group, "LeafLitter", false)
	var blood := CampKit.Merged.new()
	for index in _per_metre(path.total, BLOOD_EVERY):
		var at := rng.randf_range(0.0, path.total)
		var point := path.verge(at, rng.randf_range(-3.6, 3.6))
		_ground_patch(blood, iron["blood"], point, rng.randf_range(0.35, 0.7),
			rng.randf_range(0.7, 1.0))
	blood.commit(group, "Blood", false)
	root.stats["scatter"] = _per_metre(path.total, TRODDEN_EVERY) \
		+ _per_metre(path.total, STRAW_EVERY) + _per_metre(path.total, BLOOD_EVERY)


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
