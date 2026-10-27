extends RefCounted
## The camp clearing: the cage yard, rebuilt as a hole cut in the drowned wood.
##
## The camp used to be a room - a 60 x 68 m box of palisade with a gate at the
## far end - and the road out was a door behind that gate. It is now a clearing in
## the same wood the trail runs through: the old yard's own layout (four cages in
## a line facing the way out, the cold altar behind them, the gate watchers
## between the cages and the mouth) with a *broken* stake fence where the palisade
## stood, the treeline pressing in on every side, and one wide mouth to the south
## where the trail leaves. Nothing here is a room: the wood is the wall and the
## fence is what is left of the one the cult built.
##
## This module is geometry only. `cage_escape.gd` owns the lesson - the
## sequencer, the four latches, the watchers and the reinforcements - and the
## world owns the bodies, the camera and the HUD. What comes back from `build()`
## is what a scene needs to *use* this place: the cage doors it lifts, the clear
## ground it measured, the collision it planted, and the flame material its
## torches share with the trail.
##
## Three rules hold it together, the same three the dressing modules keep:
##
## 1. **The world's art.** Trees from `TreeKit` with the species table in
##    `WorldStyle`, undergrowth from `BushKit`, fire from `FireFx` on the shared
##    flame shader, timber/bone/hide from `CampKit`. The night and the fog are the
##    caller's (the trail's own), so a body walking out of the clearing crosses no
##    seam in the light.
## 2. **The wood is solid, the ground is not a ledge.** The treeline carries trunk
##    colliders and an invisible wall behind them, exactly as `run_forest.gd`
##    walls the lane; the fence carries its own thin colliders. Inside the fence
##    line there is not one collider but the cages' own bars.
## 3. **The caller owns the layout.** The clearing's bounds, the cage posts, the
##    mouth and the spans that must stay clear are handed in by the camp (which
##    hands them on from the dressing module, so the two can never drift), never
##    invented here.

const Geo = preload("res://scripts/geo.gd")
const CampKit = preload("res://scripts/world/camp_kit.gd")
const FireFx = preload("res://scripts/world/fire_fx.gd")
const FireFlicker = preload("res://scripts/world/fire_flicker.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const BushKit = preload("res://scripts/world/bush_kit.gd")
const WorldScatter = preload("res://scripts/world/scatter.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## Deterministic: a rebuilt world is the same world.
const SEED := 4137
## How deep the wood runs outside the fence line.
const WOOD_DEPTH := 18.0
## Square metres per tree and per bush in that band.
const TREE_AREA := 30.0
const BUSH_AREA := 38.0
const TREE_CHUNK := 64.0
const BUSH_CHUNK := 96.0
## The fence: a broken stake line, not a wall.
const FENCE_SPACING := 0.52
const FENCE_HEIGHT := 1.55
const WALL_HEIGHT := 3.0


## Builds the clearing under `parent` and returns what the camp needs:
## `{root, cages, doors, solids, clear, mouth, trees, bushes, stakes, wall}`.
## `layout` is the camp's own: `{half_width, front, back, cage_posts, mouth,
## mouth_half_width, torches, keep_clear}`.
static func build(parent: Node3D, layout: Dictionary, style: WorldStyle) -> Dictionary:
	var empty := {"root": null, "cages": [], "doors": [], "solids": null,
		"clear": Vector2.ZERO, "trees": 0, "bushes": 0, "stakes": 0}
	if parent == null or style == null:
		return empty
	var half := float(layout.get("half_width", 30.0))
	var front := float(layout.get("front", -42.0))
	var back := float(layout.get("back", 26.0))
	var mouth_half := float(layout.get("mouth_half_width", 7.0))
	var keep_clear: Array = layout.get("keep_clear", [])
	var posts: Array = layout.get("cage_posts", [])

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
	_build_props(parent)

	var fence := Rect2(-half, front, half * 2.0, back - front)
	var stakes := _build_fence(root, solids, fence, mouth_half, mats)
	# The mouth: the wood opens onto the trail, so the treeline and the wall
	# behind it are cut where the lane leaves the clearing.
	var mouth_gap := Rect2(-mouth_half - 1.5, front - WOOD_DEPTH - 6.0,
		(mouth_half + 1.5) * 2.0, WOOD_DEPTH + 12.0)
	var wood := plant_wood(root, style, fence, WOOD_DEPTH, [mouth_gap], keep_clear,
		SEED, solids, "Clearing")
	_build_torches(root, layout.get("torches", []), mats)

	return {
		"root": root,
		"cages": cages,
		"doors": doors,
		"solids": solids,
		"clear": Vector2(fence.size.x, fence.size.y),
		"mouth": Vector3(0.0, 0.0, front),
		"trees": int(wood.get("trees", 0)),
		"bushes": int(wood.get("bushes", 0)),
		"stakes": stakes,
		"wall": int(wood.get("wall", 0)),
	}


# --- the wood --------------------------------------------------------------

## Plants the world's own wood in a band of `depth` metres around `clearing`,
## leaving `gaps` (rects: the mouth, a service, a road) and `keep_clear` circles
## (a gibbet's post, a drop) empty, and walls the band's outer edge behind the
## trunks. Shared by the camp and the town: a settlement cut into this wood looks
## like the wood, wherever it stands.
##
## Returns `{trees, bushes, wall}` - the counts a budget assertion reads.
static func plant_wood(parent: Node3D, style: WorldStyle, clearing: Rect2, depth: float,
		gaps: Array, keep_clear: Array, seed_value: int, solids: Node3D,
		label: String = "Wood") -> Dictionary:
	var out := {"trees": 0, "bushes": 0, "wall": 0}
	if parent == null or style == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var band := clearing.grow(depth)
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

	var attempts := int(maxf(1.0, (band.get_area() - clearing.get_area()) / TREE_AREA))
	var planted := 0
	var colliders := 0
	for attempt in attempts * 2:
		if planted >= attempts:
			break
		var point := Vector2(rng.randf_range(band.position.x, band.end.x),
			rng.randf_range(band.position.y, band.end.y))
		if clearing.has_point(point) or _blocked(point, gaps, keep_clear):
			continue
		var record: Dictionary = records[rng.randi_range(0, records.size() - 1)]
		var variant: Dictionary = record["variant"]
		var species: Dictionary = record["species"]
		var scale_at := rng.randf_range(0.85, 1.45)
		var at := Vector3(point.x, 0.0, point.y)
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
		# The two rows that face the clearing are the ones a body can reach, so
		# they are the ones with trunks a body cannot pass.
		if _edge_distance(point, clearing) <= depth * 0.55:
			var tree_height := float(variant.get("height", 8.0)) * scale_at
			var trunk_spec: Vector2 = species.get("trunk", Vector2(0.04, 0.62))
			_trunk_collider(solids, at, maxf(0.18, tree_height * float(trunk_spec.x) * 1.04),
				maxf(1.4, tree_height * float(trunk_spec.y) * 0.95))
			colliders += 1
		planted += 1
	out["trees"] = planted

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
	var placed := 0
	var atlas_index := 0
	for atlas in atlases:
		var variants := BushKit.build_variants(String(atlas), seed_value + atlas_index * 11)
		var wind := _wind_for(style, String(atlas))
		var buckets: Array = []
		for probe in variants.size():
			buckets.append([] as Array[Dictionary])
		var bushes := int(maxf(1.0, (band.get_area() - clearing.get_area()) / BUSH_AREA))
		for attempt in bushes * 2:
			if placed >= bushes:
				break
			var point := Vector2(rng.randf_range(band.position.x, band.end.x),
				rng.randf_range(band.position.y, band.end.y))
			if clearing.has_point(point) or _blocked(point, gaps, keep_clear):
				continue
			var scale_at := rng.randf_range(0.75, 1.5)
			var slot := rng.randi_range(0, variants.size() - 1)
			(buckets[slot] as Array[Dictionary]).append({
				"transform": Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
					Vector3(scale_at, scale_at * rng.randf_range(0.8, 1.2), scale_at)),
					Vector3(point.x, 0.0, point.y)),
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


static func _trunk_collider(solids: Node3D, at: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at + Vector3(0.0, height * 0.5, 0.0)
	solids.add_child(collision)


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
	collision.position = at
	collision.rotation.y = yaw
	solids.add_child(collision)


# --- the fence -------------------------------------------------------------

## The palisade that is left: stake runs along the yard's old line, broken where
## the cult never finished it and where the wood has taken it back. Each run is
## merged into one mesh and carries one thin collider, so the standing fence is
## solid and the breaks are real holes into the trees.
static func _build_fence(root: Node3D, solids: Node3D, fence: Rect2, mouth_half: float,
		mats: Dictionary) -> int:
	var group := Node3D.new()
	group.name = "StakeFence"
	root.add_child(group)
	var half := fence.size.x * 0.5
	var front := fence.position.y
	var back := fence.end.y
	var wood: Material = mats["drift_dark"]
	var rag: Material = mats["rag"]
	var runs := [
		# long side walls, broken twice a side
		[Vector2(-half, front), Vector2(-half, -30.0)],
		[Vector2(-half, -26.0), Vector2(-half, 2.0)],
		[Vector2(-half, 6.0), Vector2(-half, back)],
		[Vector2(half, front), Vector2(half, -22.0)],
		[Vector2(half, -18.0), Vector2(half, 9.0)],
		[Vector2(half, 13.0), Vector2(half, back)],
		# the back, where the altar stands: one break for the wood
		[Vector2(-half, back), Vector2(-4.0, back)],
		[Vector2(4.0, back), Vector2(half, back)],
		# the front, and the mouth the trail leaves through
		[Vector2(-half, front), Vector2(-mouth_half, front)],
		[Vector2(mouth_half, front), Vector2(half, front)],
	]
	var merged := CampKit.Merged.new()
	var stakes := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5
	for run in runs:
		var from: Vector2 = run[0]
		var to: Vector2 = run[1]
		var span := from.distance_to(to)
		if span < 0.6:
			continue
		var along := (to - from) / span
		var count := maxi(1, int(span / FENCE_SPACING))
		for stake_index in count:
			# A stake every so often is snapped off at the knee, and a few lean.
			if rng.randf() < 0.16:
				continue
			var t := (float(stake_index) + 0.5) / float(count)
			var foot := from + along * (span * t)
			var height := rng.randf_range(FENCE_HEIGHT * 0.55, FENCE_HEIGHT * 1.35)
			if rng.randf() < 0.10:
				height *= 0.35
			var lean := Vector3(rng.randf_range(-0.16, 0.16), 0.0, rng.randf_range(-0.16, 0.16))
			var top := Vector3(foot.x, height, foot.y) + lean
			CampKit.add_beam(merged, Vector3(foot.x, -0.12, foot.y), top,
				rng.randf_range(0.075, 0.115), wood, 6, 0.045)
			stakes += 1
		# The lashings that held the run together, and the rags tied on it.
		if span >= 4.0:
			var mid := from.lerp(to, 0.5)
			CampKit.add_beam(merged, Vector3(from.x, FENCE_HEIGHT * 0.72, from.y),
				Vector3(to.x, FENCE_HEIGHT * 0.72, to.y), 0.035, rag, 3)
			for knot in 2:
				var at := from.lerp(to, 0.22 + 0.56 * float(knot))
				CampKit.add_hanging(merged, mats, Vector3(at.x, FENCE_HEIGHT * 0.9, at.y),
					rng.randf_range(0.0, TAU), SEED + _index_stub(run, knot), 0.7)
		# The run is solid: one thin box in its own direction.
		_wall_segment(solids, Vector3((from.x + to.x) * 0.5, FENCE_HEIGHT * 0.5,
			(from.y + to.y) * 0.5),
			Vector3(0.34, FENCE_HEIGHT, span), atan2(along.x, along.y))
	merged.commit(group, "Stakes")
	return stakes


static func _index_stub(run: Array, knot: int) -> int:
	var from: Vector2 = run[0]
	return int(absf(from.x) * 3.0 + absf(from.y) * 7.0) + knot * 13


# --- the cages -------------------------------------------------------------

## One cage: a slab floor, four corner posts, fixed bars on three sides, and a
## door of bars on the mouth side that rises when the rescuer works the latch.
## The cage is named `Cage1`..`Cage4` on the camp node itself, because the camp's
## dressing bolts its padlocks and chains onto the cage nodes it finds there.
static func _build_cage(parent: Node3D, index: int, at: Vector3, mats: Dictionary,
		iron: Dictionary) -> Dictionary:
	var wood: Material = mats["drift_dark"]
	var cage := Node3D.new()
	cage.name = "Cage%d" % (index + 1)
	cage.position = Vector3(at.x, 0.0, at.z)
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
	return {"node": cage, "door": door}


## The camp's own furniture: crate stacks, barrels and the cold altar behind the
## cages. The dressing module builds the rest around the altar node it finds here.
static func _build_props(parent: Node3D) -> void:
	var mats: Dictionary = CampKit.materials()
	var iron := metal()
	var wood: Material = mats["drift_dark"]
	var stone := Geo.material(Color(0.26, 0.25, 0.24), 0.0, 0.9)
	var crate_at := [Vector3(-13.0, 0, -8.0), Vector3(-12.2, 0, -6.4), Vector3(13.4, 0, 12.0),
		Vector3(12.4, 0.9, 12.4), Vector3(13.1, 0, -14.5)]
	for index in crate_at.size():
		var crate := Geo.box(parent, Vector3(0.9, 0.9, 0.9), crate_at[index] + Vector3(0, 0.45, 0), wood)
		crate.rotation.y = 0.17 * float(index) - 0.3
	for point in [Vector3(-13.6, 0, 3.0), Vector3(14.2, 0, 2.0), Vector3(-8.0, 0, -19.0)]:
		Geo.cylinder(parent, 0.36, 0.32, 0.95, point + Vector3(0, 0.48, 0), wood, 12)
	var altar := Node3D.new()
	altar.name = "ColdAltar"
	altar.position = Vector3(0, 0, 12.5)
	parent.add_child(altar)
	Geo.box(altar, Vector3(2.6, 0.9, 1.3), Vector3(0, 0.45, 0), stone)
	Geo.box(altar, Vector3(3.0, 0.18, 1.6), Vector3(0, 0.99, 0), stone)
	Geo.cylinder(altar, 0.34, 0.5, 0.24, Vector3(0, 1.2, 0), iron["iron"], 12)
	var stain := Geo.material(Color(0.20, 0.03, 0.03), 0.0, 0.7)
	Geo.box(altar, Vector3(1.6, 0.02, 0.9), Vector3(0, 1.09, 0), stain)


# --- fire ------------------------------------------------------------------

## The camp's torches: staked posts with the world's flame cards, embers and a
## light that breathes - the same fire the trail burns, so the clearing and the
## lane are lit by one thing.
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
		host.position = Vector3(at.x, 0.0, at.z)
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
