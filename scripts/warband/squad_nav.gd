extends RefCounted
## The squad's map of one area's ground: which half-metre cells a body can stand
## in, and the way round what it cannot walk through.
##
## `SquadDrive` steers in straight lines, with a sidestep and a back-out for a body
## that stops getting anywhere. That answers a post or a trunk. It cannot answer a
## *pocket*: a cage whose only opening is its door, a den open on one side, two
## trunks with a notch between them. A body inside one, pushing at a point behind
## it, slides along the bars, backs out of the opening, turns round and walks
## straight back in - a freed prisoner whose latch was cut from behind its cage did
## exactly that until the soul walked away. A map that knows the bars are there
## sends the body out of the door and round.
##
## The map is built once from the static colliders under one node (the area that
## owns them), rasterised flat: every collider that reaches into a body's height
## marks the cells within `CLEARANCE` of its footprint as solid. A node in `skip`
## (a cage door, which rises out of the way) is left off, so the map draws every
## opening as open. Bodies never collide with each other here, so nothing that
## moves is on it.

const TerrainScript = preload("res://scripts/warband/terrain.gd")

## One cell's side, in metres.
const CELL := 0.5
## How far a cell's centre stays from any solid for a body to stand in it: the
## capsule's 0.3 m radius and the margin a slide needs to get round a corner.
const CLEARANCE := 0.5
## The height band a body occupies over its own ground. A collider wholly above it
## (a door lifted out of its frame) or wholly under it does not stop a walk.
const BAND_LOW := 0.25
const BAND_HIGH := 1.85
## How far a goal that lands in a solid cell is moved to the nearest open one, in
## cells: a post drawn inside a trunk, a corpse against a cage.
const SNAP_RINGS := 8

var rect := Rect2()
var _size := Vector2i.ZERO
var _solid := PackedByteArray()
var _grid := AStarGrid2D.new()


## Map `area` (flat, x/z) from the colliders under `root`. `skip` holds nodes whose
## whole subtree stays off the map.
func build(root: Node, area: Rect2, skip: Array = []) -> void:
	rect = area
	_size = Vector2i(ceili(area.size.x / CELL), ceili(area.size.y / CELL))
	_solid = PackedByteArray()
	_solid.resize(_size.x * _size.y)
	_solid.fill(0)
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node == null or skip.has(node):
			continue
		if node is StaticBody3D and ((node as StaticBody3D).collision_layer & 1) != 0:
			for child in node.get_children():
				if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
					_stamp(child)
		for child in node.get_children():
			pending.append(child)
	_grid.region = Rect2i(Vector2i.ZERO, _size)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = area.position + Vector2(CELL, CELL) * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for z in _size.y:
		for x in _size.x:
			if _solid[z * _size.x + x] != 0:
				_grid.set_point_solid(Vector2i(x, z))


## Whether a point lies on the mapped ground.
func covers(point: Vector3) -> bool:
	return rect.has_point(Vector2(point.x, point.z))


## Whether a body can walk the straight line between two points. The cell the walk
## starts in is not asked: a body pressed against a wall stands inside the margin,
## and the question is whether the line ahead of it is clear.
func clear_line(from: Vector3, to: Vector3) -> bool:
	var a := Vector2((from.x - rect.position.x) / CELL, (from.z - rect.position.y) / CELL)
	var b := Vector2((to.x - rect.position.x) / CELL, (to.z - rect.position.y) / CELL)
	var x := floori(a.x)
	var z := floori(a.y)
	var end_x := floori(b.x)
	var end_z := floori(b.y)
	var step_x := signi(end_x - x)
	var step_z := signi(end_z - z)
	var delta := b - a
	var t_delta_x := INF if delta.x == 0.0 else absf(1.0 / delta.x)
	var t_delta_z := INF if delta.y == 0.0 else absf(1.0 / delta.y)
	var t_max_x := INF
	var t_max_z := INF
	if step_x > 0:
		t_max_x = (float(x + 1) - a.x) * t_delta_x
	elif step_x < 0:
		t_max_x = (a.x - float(x)) * t_delta_x
	if step_z > 0:
		t_max_z = (float(z + 1) - a.y) * t_delta_z
	elif step_z < 0:
		t_max_z = (a.y - float(z)) * t_delta_z
	var left := absi(end_x - x) + absi(end_z - z)
	while left > 0:
		if t_max_x < t_max_z:
			x += step_x
			t_max_x += t_delta_x
		else:
			z += step_z
			t_max_z += t_delta_z
		left -= 1
		# Off the map is solid: the map has nothing to say about it.
		if x < 0 or z < 0 or x >= _size.x or z >= _size.y or _solid[z * _size.x + x] != 0:
			return false
	return true


## The point itself when a body can stand there, else the centre of the nearest
## open cell (at the point's own height). Off the map, or with nothing open in
## reach, the point comes back unchanged.
func free_point(point: Vector3) -> Vector3:
	if not covers(point):
		return point
	var cell := _cell_of(point)
	if not _is_solid(cell):
		return point
	var open := _nearest_open(cell, Vector2(point.x, point.z))
	if open.x < 0:
		return point
	var at := _centre(open)
	return Vector3(at.x, point.y, at.y)


## The way from one point to another round everything solid: the centres of the
## cells to walk through, the first step first and the goal's cell last (at the
## goal's own height). Empty when either end is off the map or has nothing open in
## reach. A goal sealed off from the start is walked as close as the ground allows.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not covers(from) or not covers(to):
		return out
	var start := _cell_of(from)
	if _is_solid(start):
		start = _nearest_open(start, Vector2(from.x, from.z))
	var goal := _cell_of(to)
	if _is_solid(goal):
		goal = _nearest_open(goal, Vector2(to.x, to.z))
	if start.x < 0 or goal.x < 0:
		return out
	if start == goal:
		var at := _centre(goal)
		out.append(Vector3(at.x, to.y, at.y))
		return out
	var cells: Array[Vector2i] = _grid.get_id_path(start, goal, true)
	for index in range(1, cells.size()):
		var at := _centre(cells[index])
		out.append(Vector3(at.x, to.y, at.y))
	return out


# --- the raster ------------------------------------------------------------

func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori((point.x - rect.position.x) / CELL),
		floori((point.z - rect.position.y) / CELL))


func _centre(cell: Vector2i) -> Vector2:
	return rect.position + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## Off the map counts as solid: the map has nothing to say about it.
func _is_solid(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _size.x or cell.y >= _size.y:
		return true
	return _solid[cell.y * _size.x + cell.x] != 0


## The open cell closest to `near`, searched ring by ring out to `SNAP_RINGS`, or
## (-1, -1).
func _nearest_open(cell: Vector2i, near: Vector2) -> Vector2i:
	for ring in range(1, SNAP_RINGS + 1):
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dz) != ring:
					continue
				var probe := cell + Vector2i(dx, dz)
				if _is_solid(probe):
					continue
				var distance := _centre(probe).distance_squared_to(near)
				if distance < best_distance:
					best_distance = distance
					best = probe
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Mark one collider's footprint, grown by `CLEARANCE`. Boxes are tested in their
## own frame (a yawed wall stays a yawed wall), round shapes as circles; a trimesh
## or a heightfield is a floor, not a wall, and is left off.
func _stamp(holder: CollisionShape3D) -> void:
	var shape := holder.shape
	var xform := holder.global_transform
	var local := AABB()
	var radius := -1.0
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		local = AABB(-size * 0.5, size)
	elif shape is CylinderShape3D:
		radius = (shape as CylinderShape3D).radius
		var height := (shape as CylinderShape3D).height
		local = AABB(Vector3(-radius, -height * 0.5, -radius), Vector3(radius * 2.0, height, radius * 2.0))
	elif shape is CapsuleShape3D:
		radius = (shape as CapsuleShape3D).radius
		var tall := (shape as CapsuleShape3D).height
		local = AABB(Vector3(-radius, -tall * 0.5, -radius), Vector3(radius * 2.0, tall, radius * 2.0))
	elif shape is SphereShape3D:
		radius = (shape as SphereShape3D).radius
		local = AABB(-Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	else:
		return
	var bounds: AABB = xform * local
	var flat := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z) \
		.grow(CLEARANCE)
	if not flat.intersects(rect):
		return
	var ground := TerrainScript.height_at(xform.origin.x, xform.origin.z)
	if bounds.position.y > ground + BAND_HIGH or bounds.end.y < ground + BAND_LOW:
		return
	var inverse := xform.affine_inverse()
	var half := local.size * 0.5
	var low := Vector2i(maxi(floori((flat.position.x - rect.position.x) / CELL), 0),
		maxi(floori((flat.position.y - rect.position.y) / CELL), 0))
	var high := Vector2i(mini(floori((flat.end.x - rect.position.x) / CELL), _size.x - 1),
		mini(floori((flat.end.y - rect.position.y) / CELL), _size.y - 1))
	var centre := Vector2(xform.origin.x, xform.origin.z)
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var at := _centre(Vector2i(x, z))
			var inside := false
			if radius >= 0.0:
				inside = at.distance_to(centre) <= radius + CLEARANCE
			else:
				var mine: Vector3 = inverse * Vector3(at.x, xform.origin.y, at.y)
				inside = absf(mine.x) <= half.x + CLEARANCE and absf(mine.z) <= half.z + CLEARANCE
			if inside:
				_solid[z * _size.x + x] = 1
