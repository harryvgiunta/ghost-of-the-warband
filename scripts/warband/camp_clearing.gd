extends RefCounted
## The camp in the deep wood: a ragged pocket of trodden dirt with the cage line
## in it, and a forest running out of sight in every direction.
##
## The camp used to be a rectangular clearing with a broken stake fence round it,
## eighteen metres of trees beyond, and the trail starting at the fence's mouth.
## It is now what a holding pen in a drowned wood actually is: no fence line and no
## grass boundary at all, trees standing *inside* the camp's own footprint, a
## handful of rickety shelters and one fire ring around the cages, and a long
## stretch of ordinary wood between the gap in the trees and the trail's first
## torch. Nothing about the way out reads as a road.
##
## This module is geometry only. `cage_escape.gd` owns the lesson - the sequencer,
## the four latches, the watchers and the reinforcements - and the world owns the
## bodies, the camera and the HUD. What comes back from `build()` is what a scene
## needs to *use* this place: the cage doors it lifts, the clear ground it
## measured, the corridor it cut through the wood, the collision it planted, and the
## flame material its torches share with the trail.
##
## Three rules hold it together, the same three the dressing modules keep:
##
## 1. **The world's art.** Trees from `TreeKit` with the species table in
##    `WorldStyle`, undergrowth from `BushKit`, stone from `RockKit`, fire from
##    `FireFx` on the shared flame shader, shelters/huts/litter from `CampKit`.
##    The night and the fog are the caller's (the trail's own), so a body walking
##    out of the camp crosses no seam in the light.
## 2. **The wood is solid where it is walked, the ground is not a ledge.** The
##    trees a body can reach carry trunk colliders and the band's outer edge is
##    walled behind them; the pocket's own floor is the world's heightfield, never
##    a second slab, and every tree, shelter, prop and torch is lifted onto that
##    heightfield by `terrain.gd`. Deep in the wood the trees are batched props,
##    not thousands of colliders.
## 3. **The caller owns the layout.** The pocket's bounds, the cage posts, the
##    mouth, the distance to the trail and the spans that must stay clear are
##    handed in by the camp (which hands them on from the dressing module, so the
##    two can never drift), never invented here.

const Geo = preload("res://scripts/geo.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const CampKit = preload("res://scripts/world/camp_kit.gd")
const FireFx = preload("res://scripts/world/fire_fx.gd")
const FireFlicker = preload("res://scripts/world/fire_flicker.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const BushKit = preload("res://scripts/world/bush_kit.gd")
const RockKit = preload("res://scripts/world/rock_kit.gd")
const WorldScatter = preload("res://scripts/world/scatter.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## Deterministic: a rebuilt world is the same world.
const SEED := 4137
## How deep the wood runs outside the pocket: the sides, the back and the whole of
## the way to the trail. The camp sits in a wood, not in a clearing with a treeline
## painted behind it.
const WOOD_DEPTH := 170.0
## How far out the trees a body can reach keep trunk colliders. Past this the wood
## is batched props: a forest is not 4000 collision shapes.
const SOLID_WOOD_DEPTH := 18.0
## Square metres per tree and per bush: dense in the near ring - what a body reads
## at arm's length - and thinner in the deep wood, which only has to close the
## horizon through the fog without turning into a collider for every trunk. The
## wood is twice as thick as the treeline it grew out of: a camp lost in it, not a
## camp with a hedge round it.
const TREE_AREA := 96.0
const FAR_TREE_AREA := 430.0
const BUSH_AREA := 140.0
const FAR_BUSH_AREA := 950.0
## Trees planted inside the pocket's own footprint - the camp is *in* the wood -
## but only in a rim round its edge, so the wood intrudes on the camp without
## standing in the middle of the ground a body has to fight and walk on.
const INTERIOR_TREE_AREA := 34.0
const INTERIOR_RIM := 5.0
const INTERIOR_BUSH_RIM := 9.0
## Chunk sizes for the batched wood. Wider chunks than the lane's, because this
## wood is far bigger and the fog hides the seams.
const TREE_CHUNK := 200.0
const BUSH_CHUNK := 240.0
## The ragged boundary: what is left of the cult's staking, planted at a wandering
## radius rather than on a line, with gaps where the wood has swallowed it.
const STAKE_SPACING := 1.35
const STAKE_HEIGHT := 1.5
const WALL_HEIGHT := 3.0
## How wide the corridor cut through the wood runs, either side of its wandering
## centre. A gap between trees a body can walk abreast in - not a road, and not a
## fifteen-metre avenue.
const CORRIDOR_HALF := 4.5
## The corridor's wandering run, in gaps.
const CORRIDOR_SEGMENTS := 9
## How far past the pocket's edge the camp's grass runs, and how wide it grows
## either side of the corridor's worn line on the way out.
const GRASS_RIM := 14.0
const GRASS_VERGE := 7.0
## The walk the lesson is played on, handed to the planting as keep-out circles by
## the camp: cage to cage, then down the pocket to the mouth.
const WALK_SPINE := [
	Vector3(-5.1, 0.0, 6.0), Vector3(0.0, 0.0, 6.0), Vector3(5.1, 0.0, 6.0),
	Vector3(0.0, 0.0, 1.0), Vector3(-0.8, 0.0, -5.0), Vector3(0.8, 0.0, -11.0),
	Vector3(-0.6, 0.0, -17.0), Vector3(0.6, 0.0, -23.0), Vector3(0.0, 0.0, -29.0),
]
## The three shelters close in around the cage line, and the one fire between the
## cages and the way out. Nothing solid in the walk a body has to make.
const HUTS := [
	{"post": Vector3(-13.5, 0.0, 9.0), "yaw": 0.0, "width": 2.8, "depth": 2.2,
		"height": 1.70, "style": "lean_to", "seed": 3311},
	{"post": Vector3(14.0, 0.0, 9.5), "yaw": 0.0, "width": 2.4, "depth": 2.0,
		"height": 1.55, "style": "a_frame", "seed": 3319},
	{"post": Vector3(-12.5, 0.0, -8.5), "yaw": PI, "width": 3.0, "depth": 2.1,
		"height": 1.75, "style": "collapsed", "seed": 3329},
]
const FIRE_POST := Vector3(-6.4, 0.0, -4.0)
## The cold altar the cult works on the yard from: the dressing finds its node.
const ALTAR_POST := Vector3(0.0, 0.0, 12.5)
## The cult's own junk, stacked where it was dropped. All of it merged, none of it
## a collider.
const PROP_POSTS := [
	Vector3(-14.0, 0.0, -8.0), Vector3(-13.2, 0.0, -6.4), Vector3(13.4, 0.0, 12.0),
	Vector3(12.4, 0.9, 12.4), Vector3(13.1, 0.0, -14.5),
]
const BARREL_POSTS := [
	Vector3(-13.6, 0.0, 3.0), Vector3(14.2, 0.0, 2.0), Vector3(-8.0, 0.0, -19.0),
]

## The yard's broad wear, `[centre, radius, strength]`: the ground between the
## cages, the middle of the pocket, and the run down to the mouth.
const YARD_WEAR := [
	[Vector3(0.0, 0.0, 6.0), 10.0, 0.85],
	[Vector3(0.5, 0.0, -8.0), 9.5, 0.8],
	[Vector3(-0.5, 0.0, -21.0), 7.5, 0.75],
]


## Builds the camp under `parent` and returns what the camp needs:
## `{root, cages, doors, solids, clear, mouth, band, corridor, trees, bushes,
## grass, stakes, wall, huts}`.
## `layout` is the camp's own: `{half_width, front, back, cage_posts, mouth,
## mouth_half_width, to_road, torches, keep_clear}`.
static func build(parent: Node3D, layout: Dictionary, style: WorldStyle) -> Dictionary:
	var empty := {"root": null, "cages": [], "doors": [], "solids": null,
		"clear": Vector2.ZERO, "mouth": Vector3.ZERO, "band": Rect2(),
		"corridor": [], "trees": 0, "bushes": 0, "grass": 0, "stakes": 0, "wall": 0,
		"huts": 0}
	if parent == null or style == null:
		return empty
	var half := float(layout.get("half_width", 20.0))
	var front := float(layout.get("front", -30.0))
	var back := float(layout.get("back", 22.0))
	var mouth: Vector3 = layout.get("mouth", Vector3(0.0, 0.0, front))
	var mouth_half := float(layout.get("mouth_half_width", 6.0))
	var to_road := float(layout.get("to_road", 170.0))
	var keep_clear: Array = layout.get("keep_clear", [])
	var posts: Array = layout.get("cage_posts", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var root := Node3D.new()
	root.name = "Clearing"
	parent.add_child(root)
	var solids := StaticBody3D.new()
	solids.name = "ClearingCollision"
	solids.collision_layer = 1
	solids.collision_mask = 0
	root.add_child(solids)

	var mats: Dictionary = CampKit.materials()
	var iron := metal()
	var cages: Array = []
	var doors: Array = []
	for index in posts.size():
		var built := _build_cage(parent, index, posts[index], mats, iron)
		cages.append(built["node"])
		doors.append(built["door"])
	_build_props(parent, mats)

	# The corridor: the way out of the camp, and the long run of ordinary wood
	# between the mouth and the trail's first waypoint. It wanders, because a
	# straight cut through trees is a road and this is a gap in the wood.
	var corridor := _corridor(mouth, mouth_half, to_road)
	var pocket := Rect2(-half, front, half * 2.0, back - front)

	# Everything the geometry itself plants around must stay clear of: its own
	# shelters, its fire, its prop stacks, the altar and the corridor.
	var planted_clear: Array = keep_clear.duplicate()
	for hut in HUTS:
		planted_clear.append({"point": hut["post"], "radius": 2.6})
	planted_clear.append({"point": FIRE_POST, "radius": 2.4})
	for post in PROP_POSTS:
		planted_clear.append({"point": Vector3(post.x, 0.0, post.z), "radius": 1.6})
	for post in BARREL_POSTS:
		planted_clear.append({"point": post, "radius": 1.4})

	_build_shelters(root, solids, mats)
	_build_fire(root, mats)
	_build_junk(root, mats)
	# The pocket's trodden dirt is the ground's own surface: `trodden_ground()`
	# hands it to the world's terrain before anything here is built.
	var stakes := _build_ragged_boundary(root, mats, pocket, mouth, mouth_half, corridor)
	var band := pocket.grow(WOOD_DEPTH)
	var wood := plant_wood(root, style, pocket, WOOD_DEPTH, corridor, planted_clear, SEED,
		solids, "Wood", true)
	_build_wood_litter(root, band, pocket, corridor, planted_clear, rng)
	var grass := 0
	if TerrainScript.is_built():
		grass = _build_grass(root, style, pocket, planted_clear, mouth, to_road)
	_build_torches(root, layout.get("torches", []), mats)

	return {
		"root": root,
		"cages": cages,
		"doors": doors,
		"solids": solids,
		"clear": Vector2(pocket.size.x, pocket.size.y),
		"mouth": Vector3(mouth.x, 0.0, mouth.z),
		"band": band,
		"corridor": corridor,
		"trees": int(wood.get("trees", 0)),
		"inside_trees": int(wood.get("inside", 0)),
		"bushes": int(wood.get("bushes", 0)),
		"grass": grass,
		"stakes": stakes,
		"wall": int(wood.get("wall", 0)),
		"huts": HUTS.size(),
	}


# --- the grass -------------------------------------------------------------

## Grass, ferns and the odd flower round the camp: through the pocket and the
## near wood (`GRASS_RIM` past its edge) and along the corridor out (`GRASS_VERGE`
## either side of its worn line), trodden out wherever the ground map says the
## yard is worn and never on a spot the camp keeps clear. Only on the world's baked
## ground: a standalone preview's flat floor has no worn yard to keep bare.
## Returns the grass clumps placed.
static func _build_grass(root: Node3D, style: WorldStyle, pocket: Rect2, keep_clear: Array,
		mouth: Vector3, to_road: float) -> int:
	var rim := pocket.grow(GRASS_RIM)
	var corridor_area := to_road * GRASS_VERGE * 2.0
	var share := rim.get_area() / (rim.get_area() + corridor_area)
	var host := Node3D.new()
	host.name = "Grass"
	root.add_child(host)
	var ground := func(point: Vector2) -> Vector3:
		return Vector3(point.x, TerrainScript.height_at(point.x, point.y), point.y)
	var sampler := func(rng: RandomNumberGenerator) -> Vector2:
		if rng.randf() < share:
			return _sample(rng, rim)
		var t := rng.randf()
		return Vector2(mouth.x + _corridor_wobble(t) + rng.randf_range(-GRASS_VERGE, GRASS_VERGE),
			mouth.z - to_road * t)
	var reserved := func(point: Vector2) -> bool:
		return _blocked(point, [], keep_clear) or TerrainScript.is_trodden(point.x, point.y)
	var cover := GrassField.for_area(style, rim.get_area() + corridor_area)
	var built: Dictionary = GrassField.build(host, cover, ground, reserved, SEED + 611, sampler)
	return int(built.get("grass", 0))


# --- the wood --------------------------------------------------------------

## Plants the world's own wood in a band of `depth` metres around `clearing`,
## leaving `gaps` (rects: the mouth, a corridor, a road) and `keep_clear` circles
## (a gibbet's post, a drop) empty, and walls the band's outer edge behind the
## trunks. Shared by the camp and the town: a settlement cut into this wood looks
## like the wood, wherever it stands.
##
## `interior` also plants *inside* `clearing` - trees standing in the camp's own
## footprint, which is what makes a pocket in a wood rather than a mown field.
##
## Returns `{trees, bushes, wall}` - the counts a budget assertion reads.
static func plant_wood(parent: Node3D, style: WorldStyle, clearing: Rect2, depth: float,
		gaps: Array, keep_clear: Array, seed_value: int, solids: Node3D,
		label: String = "Wood", interior: bool = false) -> Dictionary:
	var out := {"trees": 0, "inside": 0, "bushes": 0, "wall": 0}
	if parent == null or style == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var band := clearing.grow(depth)
	var near := clearing.grow(minf(depth, SOLID_WOOD_DEPTH))
	var group := Node3D.new()
	group.name = label
	parent.add_child(group)

	var records: Array[Dictionary] = []
	for entry in [["ironoak", 2], ["briar_pine", 2], ["hollow_snag", 1]]:
		var species: Dictionary = style.species_by_id(String(entry[0]))
		if species.is_empty():
			continue
		var built: Array = TreeKit.build_variants(species, seed_value + records.size() * 37)
		for index in mini(int(entry[1]), built.size()):
			records.append({
				"variant": built[index], "species": species,
				"trunks": [] as Array[Dictionary], "leaves": [] as Array[Dictionary],
			})
	if records.is_empty():
		return out

	var points := _tree_points(rng, band, clearing, near, gaps, keep_clear, interior)
	var inside := 0
	for point in points:
		var record: Dictionary = records[rng.randi_range(0, records.size() - 1)]
		var variant: Dictionary = record["variant"]
		var species: Dictionary = record["species"]
		var scale_at := rng.randf_range(0.85, 1.45)
		var at := TerrainScript.grounded(Vector3(point.x, 0.0, point.y))
		var xform := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
			Vector3.ONE * scale_at), at)
		(record["trunks"] as Array[Dictionary]).append({
			"transform": xform,
			"color": _pick(species.get("bark_tints", []), rng, Color.WHITE),
		})
		var tints: Array = species.get("tints", [])
		if variant.get("leaves") != null and not tints.is_empty():
			(record["leaves"] as Array[Dictionary]).append({
				"transform": xform, "color": _pick(tints, rng, Color.WHITE),
			})
		# The pocket's own trees and the ring a body can walk up to are the ones a
		# body cannot pass. Deep in the wood - and past the fog - they are props.
		var solid := clearing.has_point(point) \
			or _edge_distance(point, clearing) <= minf(depth, SOLID_WOOD_DEPTH)
		if clearing.has_point(point):
			inside += 1
		if solid:
			TreeKit.add_trunk_solids(solids, at, variant, scale_at)
	out["trees"] = points.size()
	out["inside"] = inside

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

	# Undergrowth in the same band: fewer, larger batches than the trees.
	var atlases: Array = []
	for species in style.trees:
		var leaves := String(species.get("leaves", ""))
		if leaves.is_empty() or atlases.has(leaves):
			continue
		atlases.append(leaves)
	var bush_points := _bush_points(rng, band, clearing, near, gaps, keep_clear, interior)
	var placed := 0
	var atlas_index := 0
	for atlas in atlases:
		var variants := BushKit.build_variants(String(atlas), seed_value + atlas_index * 11)
		var wind := _wind_for(style, String(atlas))
		var buckets: Array = []
		for probe in variants.size():
			buckets.append([] as Array[Dictionary])
		for point in bush_points:
			var scale_at := rng.randf_range(0.75, 1.5)
			var slot := rng.randi_range(0, variants.size() - 1)
			(buckets[slot] as Array[Dictionary]).append({
				"transform": Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
					Vector3(scale_at, scale_at * rng.randf_range(0.8, 1.2), scale_at)),
					TerrainScript.grounded(Vector3(point.x, 0.0, point.y))),
				"color": Color(rng.randf_range(0.62, 0.86), rng.randf_range(0.66, 0.9),
					rng.randf_range(0.58, 0.82), 1.0),
			})
			placed += 1
		for slot in variants.size():
			WorldScatter.batch(group, "Bush_%d_%d" % [atlas_index, slot], variants[slot]["mesh"],
				TextureLibrary.foliage_material_tuned(String(atlas), wind), buckets[slot],
				BUSH_CHUNK, {"cast_shadow": true, "visible_end": 62.0})
		atlas_index += 1
	out["bushes"] = placed

	# The band's outer edge, walled behind the trunks: the wood is the wall, and a
	# body that slips between two trees stops three metres later, exactly as it
	# does on the lane.
	out["wall"] = _wall_ring(solids, band.grow(0.4), WALL_HEIGHT, gaps)
	return out


## The points the trees stand on: a dense ring just outside the pocket (the rows
## a body can walk up to, and the only ones that carry colliders), a thinner stand
## through the deep wood, and - when the caller asks for it - a thinner one inside
## the pocket itself.
static func _tree_points(rng: RandomNumberGenerator, band: Rect2, clearing: Rect2,
		near: Rect2, gaps: Array, keep_clear: Array, interior: bool) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append_array(_ring_points(rng, near, clearing, gaps, keep_clear, TREE_AREA))
	var deep_wanted := int(maxf(1.0, (band.get_area() - near.get_area()) / FAR_TREE_AREA))
	var deep := 0
	for attempt in deep_wanted * 2:
		if deep >= deep_wanted:
			break
		var point := _sample(rng, band)
		if near.has_point(point) or _blocked(point, gaps, keep_clear):
			continue
		points.append(point)
		deep += 1
	if interior:
		points.append_array(_inside_points(rng, clearing, gaps, keep_clear,
			INTERIOR_TREE_AREA, INTERIOR_RIM))
	return points


## The points the undergrowth fills: the same shape as the trees, thinner, and
## with no colliders at all.
static func _bush_points(rng: RandomNumberGenerator, band: Rect2, clearing: Rect2,
		near: Rect2, gaps: Array, keep_clear: Array, interior: bool) -> Array[Vector2]:
	var points: Array[Vector2] = []
	points.append_array(_ring_points(rng, near, clearing, gaps, keep_clear, BUSH_AREA))
	var deep_wanted := int(maxf(1.0, (band.get_area() - near.get_area()) / FAR_BUSH_AREA))
	var deep := 0
	for attempt in deep_wanted * 2:
		if deep >= deep_wanted:
			break
		var point := _sample(rng, band)
		if near.has_point(point) or _blocked(point, gaps, keep_clear):
			continue
		points.append(point)
		deep += 1
	if interior:
		points.append_array(_inside_points(rng, clearing, gaps, keep_clear,
			INTERIOR_TREE_AREA * 1.5, INTERIOR_BUSH_RIM))
	return points


## Points in the ring between the pocket and `near`, at `area` square metres each.
static func _ring_points(rng: RandomNumberGenerator, near: Rect2, clearing: Rect2,
		gaps: Array, keep_clear: Array, area: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var wanted := int(maxf(1.0, (near.get_area() - clearing.get_area()) / area))
	for attempt in wanted * 3:
		if points.size() >= wanted:
			break
		var point := _sample(rng, near)
		if clearing.has_point(point) or _blocked(point, gaps, keep_clear):
			continue
		points.append(point)
	return points


## Points inside the pocket itself, in a rim no deeper than `rim` metres from its
## edge and kept off everything the camp walks on.
static func _inside_points(rng: RandomNumberGenerator, clearing: Rect2, gaps: Array,
		keep_clear: Array, area: float, rim: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var inner := Rect2(clearing.position + Vector2(rim, rim),
		clearing.size - Vector2(rim, rim) * 2.0)
	var rim_area := maxf(0.0, clearing.get_area() - (inner.get_area() if inner.size.x > 0.0 else 0.0))
	var wanted := int(maxf(1.0, rim_area / area))
	for attempt in wanted * 8:
		if points.size() >= wanted:
			break
		var point := _sample(rng, clearing)
		if _edge_distance(point, clearing) > rim:
			continue
		if _blocked(point, gaps, keep_clear):
			continue
		points.append(point)
	return points


static func _sample(rng: RandomNumberGenerator, rect: Rect2) -> Vector2:
	return Vector2(rng.randf_range(rect.position.x, rect.end.x),
		rng.randf_range(rect.position.y, rect.end.y))


## One point's distance to the nearest edge of `rect` (0 inside).
static func _edge_distance(point: Vector2, rect: Rect2) -> float:
	if rect.has_point(point):
		return 0.0
	var dx := maxf(rect.position.x - point.x, point.x - rect.end.x)
	var dz := maxf(rect.position.y - point.y, point.y - rect.end.y)
	return sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dz, 0.0) * maxf(dz, 0.0))


static func _blocked(point: Vector2, gaps: Array, keep_clear: Array) -> bool:
	for gap in gaps:
		if (gap as Rect2).has_point(point):
			return true
	for entry in keep_clear:
		var at: Vector3 = entry.get("point", Vector3.ZERO)
		var radius := float(entry.get("radius", 1.5))
		if Vector2(point.x - at.x, point.y - at.z).length() <= radius:
			return true
	return false


static func _wind_for(style: WorldStyle, atlas: String) -> Vector2:
	for species in style.trees:
		if String(species.get("leaves", "")) == atlas:
			return species.get("wind", Vector2(0.08, 1.0))
	return Vector2(0.08, 1.0)


static func _pick(pool: Array, rng: RandomNumberGenerator, fallback: Color) -> Color:
	if pool.is_empty():
		return fallback
	return pool[rng.randi_range(0, pool.size() - 1)]


## A rectangle of walls around `rect`, split where a gap rect crosses the line.
## Returns how many wall segments it laid down.
static func _wall_ring(solids: Node3D, rect: Rect2, height: float, gaps: Array) -> int:
	var laid := 0
	# The two sides that run along z at x = rect's left and right edges.
	for side in [rect.position.x, rect.end.x]:
		var spans := [Vector2(rect.position.y, rect.end.y)]
		for gap in gaps:
			var cut: Rect2 = gap
			if side >= cut.position.x and side <= cut.end.x:
				spans = _carve(spans, Vector2(cut.position.y, cut.end.y))
		for span in spans:
			var length := float(span.y) - float(span.x)
			if length <= 0.4:
				continue
			_wall_segment(solids, Vector3(side, height * 0.5, (float(span.x) + float(span.y)) * 0.5),
				Vector3(0.5, height, length), 0.0)
			laid += 1
	# ...and the two that run along x at z = rect's near and far edges.
	for side in [rect.position.y, rect.end.y]:
		var spans := [Vector2(rect.position.x, rect.end.x)]
		for gap in gaps:
			var cut: Rect2 = gap
			if side >= cut.position.y and side <= cut.end.y:
				spans = _carve(spans, Vector2(cut.position.x, cut.end.x))
		for span in spans:
			var length := float(span.y) - float(span.x)
			if length <= 0.4:
				continue
			_wall_segment(solids, Vector3((float(span.x) + float(span.y)) * 0.5, height * 0.5, side),
				Vector3(length, height, 0.5), 0.0)
			laid += 1
	return laid


static func _carve(spans: Array, cut: Vector2) -> Array:
	var out: Array = []
	for span in spans:
		var a := float(span.x)
		var b := float(span.y)
		if cut.y <= a or cut.x >= b:
			out.append(Vector2(a, b))
			continue
		if cut.x > a:
			out.append(Vector2(a, cut.x))
		if cut.y < b:
			out.append(Vector2(cut.y, b))
	return out


static func _wall_segment(solids: Node3D, at: Vector3, size: Vector3, yaw: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	# The wall follows the ground: a segment laid at y = 0 on a rise would leave a
	# step a body could crawl over, and in a hollow a gap under it.
	collision.position = TerrainScript.grounded(at)
	collision.rotation.y = yaw
	solids.add_child(collision)


# --- the way out -----------------------------------------------------------

## The corridor through the trees: one throat at the mouth, a wandering run of
## gaps the length of `to_road`, and a last bite that reaches the trail's first
## waypoint. Every rect is a hole the wood is not planted in and the wall ring is
## cut for, so the only way out of the camp is a walk between trees.
static func _corridor(mouth: Vector3, mouth_half: float, to_road: float) -> Array:
	var gaps: Array = []
	# The throat: a straight run out of the camp, long enough to clear the ring of
	# trunks that carry colliders.
	var throat := Rect2(mouth.x - mouth_half - 2.5, mouth.z - 34.0,
		(mouth_half + 2.5) * 2.0, 38.0)
	gaps.append(throat)
	var step := to_road / float(CORRIDOR_SEGMENTS)
	var width := CORRIDOR_HALF * 2.0
	for index in CORRIDOR_SEGMENTS:
		var t := (float(index) + 0.5) / float(CORRIDOR_SEGMENTS)
		var z := mouth.z - step * (float(index) + 0.5)
		gaps.append(Rect2(mouth.x + _corridor_wobble(t) - width * 0.5, z - step * 0.62,
			width, step * 1.24))
	gaps.append(Rect2(mouth.x - CORRIDOR_HALF - 1.0, mouth.z - to_road - 2.0,
		width + 2.0, 5.0))
	return gaps


## The worn line down the middle of the corridor, mouth to road, in world space:
## the line `terrain.gd` wears into the ground through the gaps `_corridor()` cuts,
## so the trodden earth follows the gap in the trees instead of running into them.
static func corridor_line(mouth: Vector3, to_road: float) -> PackedVector3Array:
	var line := PackedVector3Array()
	line.append(Vector3(mouth.x, 0.0, mouth.z))
	var step := to_road / float(CORRIDOR_SEGMENTS)
	for index in CORRIDOR_SEGMENTS:
		var t := (float(index) + 0.5) / float(CORRIDOR_SEGMENTS)
		line.append(Vector3(mouth.x + _corridor_wobble(t), 0.0,
			mouth.z - step * (float(index) + 0.5)))
	line.append(Vector3(mouth.x, 0.0, mouth.z - to_road))
	return line


## How far the corridor's centre wanders off the mouth's line at `t` (0 at the
## mouth, 1 at the road). The gaps and the worn line share it.
static func _corridor_wobble(t: float) -> float:
	return sin(t * TAU * 1.5) * 3.5


# --- the ragged boundary ---------------------------------------------------

## What is left of the cult's staking: no fence line and no wall, just posts at a
## wandering radius round the pocket, snapped off, leaning and missing in places,
## with rags tied to the ones still standing. Nothing here is a collider - the
## trees are the boundary.
static func _build_ragged_boundary(root: Node3D, mats: Dictionary, pocket: Rect2,
		mouth: Vector3, mouth_half: float, corridor: Array) -> int:
	var group := Node3D.new()
	group.name = "StakeRing"
	root.add_child(group)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5
	var centre := pocket.get_center()
	var rx := pocket.size.x * 0.5 + 5.5
	var rz := pocket.size.y * 0.5 + 5.5
	var circumference := TAU * (rx + rz) * 0.5
	var count := maxi(24, int(circumference / STAKE_SPACING))
	var merged := CampKit.Merged.new()
	var wood: Material = mats["drift_dark"]
	var rag: Material = mats["rag"]
	var stakes := 0
	for index in count:
		var angle := TAU * float(index) / float(count)
		var radius := 1.0 + rng.randf_range(-0.055, 0.075)
		var foot := centre + Vector2(cos(angle) * rx * radius, sin(angle) * rz * radius)
		if _blocked(foot, corridor, []):
			continue
		if Vector2(foot.x - mouth.x, foot.y - mouth.z).length() <= mouth_half + 4.0:
			continue
		# A tenth of the run has been pushed over or taken back by the wood.
		if rng.randf() < 0.14:
			continue
		var height := rng.randf_range(STAKE_HEIGHT * 0.55, STAKE_HEIGHT * 1.3)
		if rng.randf() < 0.12:
			height *= 0.34
		var lean := Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))
		var foot_y := TerrainScript.height_at(foot.x, foot.y)
		CampKit.add_beam(merged, Vector3(foot.x, foot_y - 0.12, foot.y),
			Vector3(foot.x + lean.x, foot_y + height, foot.y + lean.z),
			rng.randf_range(0.075, 0.115), wood, 6, 0.045)
		if rng.randf() < 0.3:
			CampKit.add_hanging(merged, mats, Vector3(foot.x, foot_y + height * 0.82, foot.y),
				rng.randf_range(0.0, TAU), SEED + 900 + index, 0.62)
		elif rng.randf() < 0.25:
			CampKit.add_beam(merged, Vector3(foot.x - 0.55, foot_y + height * 0.68, foot.y),
				Vector3(foot.x + 0.5, foot_y + height * 0.72, foot.y + 0.1), 0.03, rag, 3)
		stakes += 1
	merged.commit(group, "Stakes")
	return stakes


# --- the campsite ----------------------------------------------------------

## Two lean-tos and a collapsed den close in around the cage line: what a holding
## pen in a wood is roofed with. The kit builds them (and their own foot
## colliders); nothing stands in the walk.
static func _build_shelters(root: Node3D, solids: StaticBody3D, mats: Dictionary) -> void:
	var group := Node3D.new()
	group.name = "Huts"
	root.add_child(group)
	for index in HUTS.size():
		var spec: Dictionary = HUTS[index]
		var host := Node3D.new()
		host.name = "Hut%d" % (index + 1)
		host.position = TerrainScript.grounded(spec["post"])
		host.rotation.y = float(spec["yaw"])
		group.add_child(host)
		CampKit.twig_shelter(host, mats, solids, {
			"seed": int(spec["seed"]), "name": "HutMesh",
			"width": float(spec["width"]), "depth": float(spec["depth"]),
			"height": float(spec["height"]), "style": String(spec["style"]),
		})


## The fire the guards sat round: a ring of river stones, ash, three charred
## sticks and a small flame on the world's own flame cards. No collider, because a
## body may well walk through the camp's fire on its way out.
static func _build_fire(root: Node3D, mats: Dictionary) -> void:
	var host := Node3D.new()
	host.name = "CampFire"
	host.position = TerrainScript.grounded(FIRE_POST)
	root.add_child(host)
	CampKit.fire_ring(host, mats, SEED + 17)
	# The logs somebody dragged up to sit on, and a heap of split kindling. Local
	# to the fire's own node, so the ring's furniture moves with it.
	var m := CampKit.Merged.new()
	for index in 2:
		var angle := 2.1 + float(index) * 2.4
		CampKit.add_beam(m, Vector3(cos(angle) * 1.6, 0.16, sin(angle) * 1.6),
			Vector3(cos(angle) * 1.6 - sin(angle) * 1.7, 0.16,
				sin(angle) * 1.6 + cos(angle) * 1.7),
			0.13, mats["drift_dark"], 6, 0.10)
	CampKit.add_cyl_disc(m, 0.5, 0.06, Vector3(1.5, 0.03, 1.1), mats["ash"], 10)
	m.commit(host, "FireLogs")
	var light := FireFlicker.new()
	light.name = "FireLight"
	light.position = Vector3(0.0, 0.9, 0.0)
	light.light_color = Color(1.0, 0.57, 0.24)
	light.light_energy = 2.2
	light.omni_range = 12.0
	light.omni_attenuation = 1.3
	light.flicker = 0.22
	light.shadow_enabled = false
	host.add_child(light)


## The camp's junk: pots, a bone heap, two stakes with rags on them, straw. One
## merged mesh, no colliders, all of it off the walk.
static func _build_junk(root: Node3D, mats: Dictionary) -> void:
	var group := Node3D.new()
	group.name = "CampJunk"
	root.add_child(group)
	var m := CampKit.Merged.new()
	CampKit.pot_stack(m, mats, TerrainScript.grounded(Vector3(-9.4, 0.0, 2.2)), 0.4, 61)
	CampKit.pot_stack(m, mats, TerrainScript.grounded(Vector3(9.8, 0.0, -9.5)), -1.1, 67)
	CampKit.bone_heap(m, mats, TerrainScript.grounded(Vector3(10.2, 0.0, 7.4)), 1.3, 71)
	CampKit.bone_heap(m, mats, TerrainScript.grounded(Vector3(-10.6, 0.0, -15.0)), -0.6, 73)
	CampKit.mask_stake(m, mats, TerrainScript.grounded(Vector3(9.4, 0.0, -2.4)), -0.4, 79)
	CampKit.mask_stake(m, mats, TerrainScript.grounded(Vector3(-9.2, 0.0, -12.0)), 0.9, 83)
	CampKit.add_hanging(m, mats, TerrainScript.grounded(Vector3(9.4, 1.72, -2.4)), -0.4, 87, 0.8)
	CampKit.add_hanging(m, mats, TerrainScript.grounded(Vector3(-9.2, 1.68, -12.0)), 0.9, 89, 0.7)
	m.commit(group, "Junk")


## The pocket's trodden ground, as worn marks for `terrain.gd`'s ground map: the
## walk the opening is played on, the cages, the fire, the shelters, the altar
## and the heart of the yard. The terrain paints and height-blends them into the
## floor, so the camp's dirt has a soft, ragged edge and no disc sits on the
## grass. `cage_posts` and `walk` are the camp's own (`cage_escape.gd`).
static func trodden_ground(cage_posts: Array, walk: Array) -> Array:
	var marks: Array = []
	# The yard, where the cult stood about and dragged its prisoners: worn down the
	# middle of the pocket from the cage line to the mouth, ragged at its edge.
	for spot in YARD_WEAR:
		marks.append({"point": spot[0], "radius": spot[1], "strength": spot[2]})
	var route := PackedVector3Array()
	for point in walk:
		route.append(point)
	marks.append({"points": route, "half_width": 2.6, "strength": 0.95})
	for post in cage_posts:
		marks.append({"point": post, "radius": 3.4, "strength": 1.0})
	marks.append({"point": FIRE_POST, "radius": 3.8, "strength": 1.0})
	marks.append({"point": ALTAR_POST, "radius": 3.6, "strength": 0.95})
	for hut in HUTS:
		marks.append({"point": hut["post"], "radius": 3.0, "strength": 0.85})
	return marks


# --- the wood's own floor --------------------------------------------------

## Stone, deadfall, bramble and small doodads through the wood: what a forest floor
## is. Batched into a handful of merged meshes, standing off the corridor and the
## pocket's hotspots, with no colliders of their own - the trunks near the camp are
## the only wood a body has to get round.
static func _build_wood_litter(root: Node3D, band: Rect2, pocket: Rect2, gaps: Array,
		keep_clear: Array, rng: RandomNumberGenerator) -> void:
	var group := Node3D.new()
	group.name = "WoodLitter"
	root.add_child(group)
	var mats: Dictionary = CampKit.materials()
	var rock := TextureLibrary.rock_material()
	var stones: Array[ArrayMesh] = [
		RockKit.mesh("boulder", 2711), RockKit.mesh("slab", 2749),
		RockKit.mesh("boulder", 2787),
	]
	var boulders := CampKit.Merged.new()
	for index in 48:
		var point := _sample(rng, band)
		if _blocked(point, gaps, keep_clear):
			continue
		if pocket.has_point(point) and rng.randf() < 0.75:
			continue
		RockKit.add_stone(boulders, rock, stones[index % stones.size()],
			TerrainScript.grounded(Vector3(point.x, 0.0, point.y)),
			rng.randf_range(0.35, 1.5), rng.randf_range(0.0, TAU), rng.randf_range(0.34, 0.62),
			rng.randf_range(-0.22, 0.22))
	boulders.commit(group, "Outcrops")

	var deadfall := CampKit.Merged.new()
	for index in 26:
		var point := _sample(rng, band)
		if _blocked(point, gaps, keep_clear):
			continue
		var angle := rng.randf_range(0.0, TAU)
		var length := rng.randf_range(1.6, 5.4)
		var foot := TerrainScript.grounded(Vector3(point.x, rng.randf_range(0.05, 0.28), point.y))
		var tip := foot + Vector3(cos(angle) * length, rng.randf_range(-0.2, 0.3),
			sin(angle) * length)
		CampKit.add_beam(deadfall, foot, tip, rng.randf_range(0.10, 0.26),
			mats["drift_dark"] if index % 3 else mats["bark"], 6, 0.07)
	deadfall.commit(group, "Deadfall")

	var brush := CampKit.Merged.new()
	for index in 8:
		var point := _sample(rng, band.grow(-SOLID_WOOD_DEPTH * 0.5))
		if _blocked(point, gaps, keep_clear):
			continue
		CampKit.brush_screen(brush, mats, TerrainScript.grounded(Vector3(point.x, 0.0, point.y)),
			rng.randf_range(0.0, TAU), rng.randf_range(2.2, 4.4), SEED + 300 + index)
	brush.commit(group, "Brambles")

	var doodads := CampKit.Merged.new()
	for index in 8:
		var point := _sample(rng, band)
		if _blocked(point, gaps, keep_clear):
			continue
		var foot := TerrainScript.grounded(Vector3(point.x, 0.0, point.y))
		match index % 4:
			0:
				CampKit.offering_stone(doodads, mats, foot,
					rng.randf_range(0.0, TAU), SEED + 400 + index)
			1:
				CampKit.pot_stack(doodads, mats, foot,
					rng.randf_range(0.0, TAU), SEED + 420 + index)
			2:
				CampKit.bone_heap(doodads, mats, foot,
					rng.randf_range(0.0, TAU), SEED + 440 + index)
			_:
				CampKit.skull_stakes(doodads, mats, foot,
					rng.randf_range(0.0, TAU), 3, 0.7, SEED + 460 + index)
	doodads.commit(group, "Doodads")


# --- the cages -------------------------------------------------------------

## One cage: a slab floor, four corner posts, fixed bars on three sides, and a
## door of bars on the mouth side that rises when its latch is cut. The cage is
## named `Cage1`..`Cage4` on the camp node itself, because the camp's dressing
## bolts its padlocks and chains onto the cage nodes it finds there.
static func _build_cage(parent: Node3D, index: int, at: Vector3, mats: Dictionary,
		iron: Dictionary) -> Dictionary:
	var wood: Material = mats["drift_dark"]
	var cage := Node3D.new()
	cage.name = "Cage%d" % (index + 1)
	cage.position = TerrainScript.grounded(Vector3(at.x, 0.0, at.z))
	parent.add_child(cage)
	Geo.box(cage, Vector3(2.5, 0.1, 2.5), Vector3(0, -0.03, 0), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Geo.box(cage, Vector3(0.17, 2.9, 0.17), Vector3(sx * 1.15, 1.45, sz * 1.15), iron["iron"])
	for step in 5:
		var offset := -0.8 + step * 0.4
		Geo.cylinder(cage, 0.05, 0.05, 2.7, Vector3(offset, 1.4, 1.15), iron["iron"], 6)
		Geo.cylinder(cage, 0.05, 0.05, 2.7, Vector3(-1.15, 1.4, offset), iron["iron"], 6)
		Geo.cylinder(cage, 0.05, 0.05, 2.7, Vector3(1.15, 1.4, offset), iron["iron"], 6)
	Geo.box(cage, Vector3(2.5, 0.12, 0.12), Vector3(0, 2.78, -1.15), iron["iron"])
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0, 0, -1.15)
	cage.add_child(door)
	for step in 6:
		Geo.cylinder(door, 0.045, 0.045, 2.7, Vector3(-1.0 + step * 0.4, 1.4, 0), iron["iron"], 6)
	Geo.box(door, Vector3(2.4, 0.1, 0.1), Vector3(0, 1.1, 0), iron["iron"])
	# The bars are a wall, not a painting: two 2.5 m sides and the back of the
	# cage stop a body walking in, and the floor stops nothing because it is the
	# world's own heightfield. The inside stays hollow - a clamped prisoner lives
	# there - and the front belongs to the door.
	var bars := _collision_body(cage, "CageBars")
	_collision_box(bars, Vector3(0.12, 2.7, 2.5), Vector3(-1.15, 1.35, 0.0))
	_collision_box(bars, Vector3(0.12, 2.7, 2.5), Vector3(1.15, 1.35, 0.0))
	_collision_box(bars, Vector3(2.5, 2.7, 0.12), Vector3(0.0, 1.35, 1.15))
	# The door is its own body so the collider rises with the bars it is drawn on:
	# a cut latch opens the front of the cage, not just its picture.
	var door_bars := _collision_body(door, "DoorBars")
	_collision_box(door_bars, Vector3(2.4, 2.7, 0.12), Vector3(0.0, 1.35, 0.0))
	return {"node": cage, "door": door}


## A static collider on the world's own layer, and blind to everything: nothing
## in the camp is pushed by these walls, they are simply there.
static func _collision_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _collision_box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	parent.add_child(shape)


## The camp's own furniture: crate stacks, barrels and the cold altar behind the
## cages. The dressing module builds the rest around the altar node it finds here.
static func _build_props(parent: Node3D, mats: Dictionary) -> void:
	var iron := metal()
	var wood: Material = mats["drift_dark"]
	var stone := Geo.material(Color(0.26, 0.25, 0.24), 0.0, 0.9)
	var group := Node3D.new()
	group.name = "CampProps"
	parent.add_child(group)
	for index in PROP_POSTS.size():
		var post: Vector3 = PROP_POSTS[index]
		var crate := Geo.box(group, Vector3(0.9, 0.9, 0.9),
			TerrainScript.grounded(post) + Vector3(0, 0.45, 0), wood)
		crate.rotation.y = 0.17 * float(index) - 0.3
	for point in BARREL_POSTS:
		var barrel: Vector3 = point
		Geo.cylinder(group, 0.36, 0.32, 0.95,
			TerrainScript.grounded(barrel) + Vector3(0, 0.48, 0), wood, 12)
	var altar := Node3D.new()
	altar.name = "ColdAltar"
	altar.position = TerrainScript.grounded(ALTAR_POST)
	parent.add_child(altar)
	Geo.box(altar, Vector3(2.6, 0.9, 1.3), Vector3(0, 0.45, 0), stone)
	Geo.box(altar, Vector3(3.0, 0.18, 1.6), Vector3(0, 0.99, 0), stone)
	Geo.cylinder(altar, 0.34, 0.5, 0.24, Vector3(0, 1.2, 0), iron["iron"], 12)
	var stain := Geo.material(Color(0.20, 0.03, 0.03), 0.0, 0.7)
	Geo.box(altar, Vector3(1.6, 0.02, 0.9), Vector3(0, 1.09, 0), stain)


# --- fire ------------------------------------------------------------------

## The camp's torches: staked posts with the world's flame cards, embers and a
## light that breathes - the same fire the trail burns, so the camp and the lane
## are lit by one thing.
static func _build_torches(root: Node3D, torches: Array, mats: Dictionary) -> void:
	var group := Node3D.new()
	group.name = "Torches"
	root.add_child(group)
	var iron := metal()
	var index := 0
	for entry in torches:
		var at: Vector3 = entry[0]
		var scale_at := float(entry[1])
		var host := Node3D.new()
		host.name = "Torch%d" % (index + 1)
		host.position = TerrainScript.grounded(Vector3(at.x, 0.0, at.z))
		group.add_child(host)
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED + 101 + index * 29
		var m := CampKit.Merged.new()
		CampKit.add_beam(m, Vector3(0.0, -0.25, 0.0),
			Vector3(0.06, 2.46 * scale_at, 0.03), 0.085, mats["drift_dark"], 6, 0.055)
		CampKit.add_ring(m, Vector3(0.05, 1.92 * scale_at, 0.02), 0.0, 0.10, 0.145,
			iron["iron"], 0.0, 8, 3)
		CampKit.add_ring(m, Vector3(0.05, 2.42 * scale_at, 0.02), 0.0, 0.17, 0.215,
			iron["iron"], 0.0, 12, 3)
		CampKit.add_ball(m, 0.09, Vector3(0.05, 2.46 * scale_at, 0.02), mats["fire_core"],
			Vector3(1.0, 0.55, 1.0), 7, 4)
		FireFx.flame_cards(m, mats["flame"], rng, 0.54 * scale_at, 2.44 * scale_at)
		m.commit(host, "TorchPost")
		if index % 2 == 0:
			FireFx.embers(host, 2.44 * scale_at, 0.26, 12)
		var light := FireFlicker.new()
		light.name = "TorchLight"
		light.position = Vector3(0.05, 2.62 * scale_at, 0.02)
		light.light_color = Color(1.0, 0.56, 0.22)
		light.light_energy = 3.4 * scale_at
		light.omni_range = 16.0
		light.omni_attenuation = 1.0
		light.flicker = 0.26
		light.shadow_enabled = false
		host.add_child(light)
		index += 1


# --- palette ---------------------------------------------------------------

## The few materials the world kits do not carry, shared with the lane so the
## camp's iron and the road's iron are the same iron.
static func metal() -> Dictionary:
	return preload("res://scripts/warband/camp_dressing.gd").metal()
