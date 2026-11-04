extends RefCounted
## The Weeping Hollow's rock as a surface: a skin over every wall a room shows, a
## lintel over every lower way out of it, and a vaulted roof.
##
## The walls and roofs are collider boxes on the half-metre raster
## (`delve_layout.gd`): what stops a body and what the squad's map sees. The floor
## is not one of them - it is a surface of its own (`delve_floor.gd`) - and this
## draws the rock those boxes stand for, hung off that floor.
## Every edge where a room's floor meets rock is followed lattice point by lattice
## point and a strip is raised on it from under the floor to over the roof, pushed
## out into the room by one field (`relief`): a talus skirt at the foot, broken
## strata that wander along the wall, deep overhangs above head height and a cove
## that curls into the roof. The skin only ever stands proud of the box face
## (`PROUD` and up), so the box behind it never shows and nothing a body walks
## through is hidden inside it.
##
## Two strips that meet - round a room's own corner, or at a jamb where a way out
## turns into the next room - share their corner vertex, pushed along the sum of
## the faces' normals there (read from the raster's four cells round the point).
## At a jamb the two rooms must agree on that vertex, so everything room-shaped in
## the field (a hall's deeper overhang, its cove) fades out over `JAMB_BLEND`
## metres toward the jamb, and what is left is a function of the point and of the
## way out itself: its mouth, where the jambs swell in toward the head of the
## opening (`ARCH_PUSH`), so a passage reads as worn through the rock from either
## side and never as a door cut in a box. A taller room shows the rock over a
## lower way out as a lintel lofted between the two pushed jambs, its soffit
## tucked back over the lower roof. Round every torch, lantern and timber set on a
## wall the rock is dressed back (`DRESSED`), so nothing mounted is buried.
##
## The roof is a sheet that sags up to `vault` metres into the room and comes back
## to the box at the walls, where the coves already hide its edge, and flattens
## round each shaft's hole.
##
## Skins are presentation and deterministic, built once per process and kept: every
## descent after the first reuses them, and a co-op guest draws what its host drew.

const Layout = preload("res://scripts/warband/delve_layout.gd")
const Floor = preload("res://scripts/warband/delve_floor.gd")

## The skin starts this far under the lowest ground a room's walls stand on and
## ends this far over its roof.
const BURY := 0.15
const OVER := 0.4
## The least the rock stands off its collider face.
const PROUD := 0.05
## How far the rock reaches out of a wall, at the most: low (where bodies walk),
## and above head height in a way and in a hall.
const FOOT_REACH := 0.2
const WAY_REACH := 0.38
const HALL_REACH := 0.78
## Over how many metres toward a jamb the room-shaped rock fades out.
const JAMB_BLEND := 2.0
## A way out's mouth: the jambs swell this far in over the top `ARCH_RISE` metres of
## the opening, spreading `ARCH_SPREAD` metres along the walls either side.
const ARCH_PUSH := 0.6
const ARCH_RISE := 1.8
const ARCH_SPREAD := 1.6
## Round a wall mount the rock is dressed back to this, inside `DRESSED_NEAR` and
## out to the natural rock by `DRESSED_FAR`.
const DRESSED := 0.07
const DRESSED_NEAR := 0.55
const DRESSED_FAR := 1.5
## The roof sheet's grid, in metres.
const ROOF_STEP := 0.8
## How far a lintel's soffit tucks back over the lower roof.
const SOFFIT := 0.35
## The roof skin hangs at least this far under the collider box's underside, so the
## two never share a plane.
const UNDER := 0.03
## Mounts are bucketed on a grid this coarse for the dressing lookup.
const BUCKET := 4.0

static var _skins: Dictionary = {}
static var _runs: Dictionary = {}
static var _mounts: Dictionary = {}
static var _field: FastNoiseLite = null
static var _mass: FastNoiseLite = null
static var _grain: FastNoiseLite = null
static var _vault: FastNoiseLite = null


# --- reading -------------------------------------------------------------------

## The room's skin - its walls, the lintels over its lower ways out and its roof -
## as one mesh in the cave's frame. Built on first ask and kept.
static func skin(index: int) -> ArrayMesh:
	if _skins.has(index):
		return _skins[index]
	_noises()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rows := _rows(Floor.low(index) - BURY, ceiling(index))
	for run in wall_runs(index):
		var points: PackedVector2Array = run["points"]
		var dirs: PackedVector2Array = run["dirs"]
		var open: PackedFloat32Array = run["open"]
		var arch: PackedFloat32Array = run["arch"]
		var grid := PackedVector3Array()
		grid.resize(points.size() * rows.size())
		for i in points.size():
			for j in rows.size():
				var y := rows[j]
				var push := relief(index, points[i].x, y, points[i].y, open[i], arch[i])
				grid[i * rows.size() + j] = Vector3(points[i].x + dirs[i].x * push, y, points[i].y + dirs[i].y * push)
		_sheet(grid, points.size(), rows.size(), verts, normals, indices)
	for lintel in lintels(index):
		_lintel(index, lintel, verts, normals, indices)
	_roof(index, verts, normals, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_skins[index] = mesh
	return mesh


## The rock's height over a room, in the cave's frame: the room's authored height
## over its own floor, and that floor has fallen away from the mouth
## (`Layout.room_floor`). A hall deep in the dark is the same room moved down, so
## the rock over it is exactly as thick as the rock over the mouth and the
## clearance under it is the height it was authored with.
static func ceiling(index: int) -> float:
	return float(Layout.ROOMS[index]["height"]) + Layout.room_floor(index)


## Every wall a room shows, as runs of raster lattice points round its floor, in
## the floor's own winding. Per run: `points` (cave x/z), `dirs` (the way each is
## pushed out into the room: a straight wall's normal, both walls' at a corner),
## `along` (metres from the run's start), `open` (metres to the nearer jamb) and
## `arch` (the head height of the way out at that nearer jamb, in the cave's own
## frame - the ceiling of the lower room at that jamb). A run ends where a way out
## begins - at a jamb - and turns with the room's own corners.
static func wall_runs(index: int) -> Array:
	if _runs.has(index):
		return _runs[index]
	var height := ceiling(index)
	var stretches := _grouped(_perimeter(index))
	var out: Array = []
	for order in stretches.size():
		var run: Dictionary = stretches[order]
		if int(run["key"]) >= 0:
			continue
		# The ways out at either end of the run, and how high each one is.
		var before := int(stretches[(order - 1 + stretches.size()) % stretches.size()]["key"])
		var after := int(stretches[(order + 1) % stretches.size()]["key"])
		var arch_start := minf(height, ceiling(before)) if before >= 0 else height
		var arch_end := minf(height, ceiling(after)) if after >= 0 else height
		var segments: Array = run["segments"]
		var points := PackedVector2Array()
		var dirs := PackedVector2Array()
		var along := PackedFloat32Array()
		var lattice: Array[Vector2i] = [segments[0][0]]
		for segment in segments:
			lattice.append(segment[1])
		var metres := 0.0
		for k in lattice.size():
			var cell: Vector2i = lattice[k]
			var fallback: Vector2 = segments[mini(k, segments.size() - 1)][3]
			var point := Layout.lattice(cell.x, cell.y)
			if k > 0:
				metres += point.distance_to(points[k - 1])
			points.append(point)
			dirs.append(_push(cell.x, cell.y, fallback))
			along.append(metres)
		var open := PackedFloat32Array()
		var arch := PackedFloat32Array()
		for k in along.size():
			var from_start := along[k]
			var from_end := metres - along[k]
			open.append(minf(from_start, from_end))
			arch.append(arch_start if from_start <= from_end else arch_end)
		out.append({"points": points, "dirs": dirs, "along": along, "open": open, "arch": arch})
	_runs[index] = out
	return out


## A point `s` metres along a wall run: `{point, dir, tangent, open, arch}` - where
## on the box face it is, the way it is pushed out (diagonal at a corner), the run's
## direction there, and how far it is from the nearer way out and how high that is.
static func sample(run: Dictionary, s: float) -> Dictionary:
	var points: PackedVector2Array = run["points"]
	var dirs: PackedVector2Array = run["dirs"]
	var along: PackedFloat32Array = run["along"]
	var k := 0
	while k < along.size() - 2 and along[k + 1] < s:
		k += 1
	var span := maxf(along[k + 1] - along[k], 0.0001)
	var f := clampf((s - along[k]) / span, 0.0, 1.0)
	var total := along[along.size() - 1]
	var near := k if f < 0.5 else k + 1
	return {"point": points[k].lerp(points[k + 1], f), "dir": dirs[near],
		"tangent": (points[k + 1] - points[k]).normalized(), "open": minf(s, total - s),
		"arch": (run["arch"] as PackedFloat32Array)[near]}


## The ways out of a room into a lower one: `{points, normal, low}` per opening -
## the opening's lattice points jamb to jamb, the room's inward normal there and
## the lower roof's height in the cave's frame. The taller room owns the rock over
## the opening.
static func lintels(index: int) -> Array:
	var height := ceiling(index)
	var out: Array = []
	for run in _grouped(_perimeter(index)):
		var neighbour := int(run["key"])
		if neighbour < 0:
			continue
		var low := ceiling(neighbour)
		if low > height - 0.05:
			continue
		var segments: Array = run["segments"]
		var lattice: Array[Vector2i] = [segments[0][0]]
		for segment in segments:
			lattice.append(segment[1])
		out.append({"lattice": lattice, "normal": segments[0][3], "low": low})
	return out


## How far the rock stands out of its box face at a point of room `index`, in
## metres - always at least `PROUD`. `open` is how far along the wall the point is
## from the nearer way out, and `arch` that way's head height: the jamb two rooms
## share comes out the same from either, and the mouth swells toward the head.
## Everything the wall does relative to the floor it stands on - the talus skirt at
## its foot, where the rock starts to reach into the room over a body's head - is
## read against the ground under that point (`Floor.height`), because the floor of
## a hall is not level: a wall's foot in a deep hollow carries its skirt there.
static func relief(index: int, x: float, y: float, z: float, open: float = INF, arch: float = INF) -> float:
	_noises()
	var room: Dictionary = Layout.ROOMS[index]
	var top := ceiling(index)
	var tunnel := bool(room.get("tunnel", false))
	var rise := y - Floor.height(x, z)
	var shape := smoothstep(0.0, JAMB_BLEND, open)
	var broad := 0.5 + 0.5 * _field.get_noise_3d(x, y * 0.75, z)
	var mass := 0.5 + 0.5 * _mass.get_noise_3d(x, y * 0.6, z)
	var grain := 0.5 + 0.5 * _grain.get_noise_3d(x, y, z)
	var high := lerpf(WAY_REACH, WAY_REACH if tunnel else HALL_REACH, shape)
	var reach := lerpf(FOOT_REACH, high, smoothstep(2.0, 3.0, rise))
	var push := PROUD + reach * (0.5 * broad + 0.5 * mass) + 0.05 * grain
	# Strata: ledges every metre and a third that wander up and down the wall.
	var level := y + 0.55 * _vault.get_noise_2d(x * 1.7, z * 1.7)
	var ledge := pow(maxf(sin(level * TAU / 1.35), 0.0), 8.0)
	push += ledge * 0.09 * smoothstep(0.4, 1.0, rise)
	# The talus skirt at the foot.
	push += 0.3 * (1.0 - smoothstep(-0.1, 0.65, rise)) * (0.5 + 0.5 * broad)
	# The cove into the roof: the room's own, so it fades out at a jamb.
	var cove_height := 1.4 if tunnel else minf(2.6, float(room["height"]) * 0.35)
	var cove := smoothstep(top - cove_height, top + OVER, y)
	push += (0.35 if tunnel else 0.75) * cove * cove * shape
	# The mouth of a way out: the rock swells in toward the head of the opening.
	if arch < INF:
		var near := 1.0 - smoothstep(0.0, ARCH_SPREAD, open)
		var head := smoothstep(arch - ARCH_RISE, arch, y) * (1.0 - smoothstep(arch + 0.3, arch + 1.8, y))
		push += ARCH_PUSH * near * head * (0.75 + 0.5 * grain)
	# Dressed back round anything mounted on the wall.
	var dressed := _dressed(x, z)
	return lerpf(PROUD + DRESSED, push, dressed) if dressed < 1.0 else push


## The roof's underside over a point of a room (cave frame): just under the room's
## ceiling at its walls and round a shaft's hole, sagging into a vault toward the
## middle of a hall.
static func roof_height(index: int, x: float, z: float) -> float:
	_noises()
	var room: Dictionary = Layout.ROOMS[index]
	var rect: Rect2 = room["rect"]
	var top := ceiling(index)
	var edge := minf(minf(x - rect.position.x, rect.end.x - x), minf(z - rect.position.y, rect.end.y - z))
	var fade := smoothstep(0.0, 1.8, edge)
	for landing in Layout.LANDINGS:
		var rope: Vector3 = landing["rope"]
		fade *= smoothstep(1.0, 2.4, Vector2(x - rope.x, z - rope.z).length())
	var dome := 0.5 + 0.5 * _vault.get_noise_2d(x, z)
	var grain := 0.5 + 0.5 * _grain.get_noise_2d(x * 1.3, z * 1.3)
	return top - UNDER - vault(index) * fade * (0.25 + 0.75 * dome) - 0.12 * fade * grain


## How deep a room's roof sags at most.
static func vault(index: int) -> float:
	var room: Dictionary = Layout.ROOMS[index]
	if bool(room.get("tunnel", false)):
		return 0.45
	return clampf((float(room["height"]) - 4.0) * 0.28, 0.35, 1.6)


# --- the raster ------------------------------------------------------------------

static func _noises() -> void:
	if _field != null:
		return
	_field = _noise(4409, 0.32, 3)
	_mass = _noise(4417, 0.11, 2)
	_grain = _noise(4421, 1.35, 2)
	_vault = _noise(4433, 0.17, 3)
	_bucket_mounts()


static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


## Everything mounted on a wall, as cave x/z points in `BUCKET` cells: the wall
## lights (sconces, witch-lights, lanterns, fungus), the timber posts set against
## the workings' walls and both legs of every timber set across a way.
static func _bucket_mounts() -> void:
	var points: Array[Vector2] = []
	for spec in Layout.LIGHTS:
		if spec.has("wall"):
			var at: Vector3 = Layout.wall_point(str(spec["room"]), str(spec["wall"]), float(spec["along"]))["at"]
			points.append(Vector2(at.x, at.z))
	for spec in Layout.PROPS:
		match str(spec["kind"]):
			"post":
				var at: Vector3 = Layout.wall_point(str(spec["room"]), str(spec["wall"]), float(spec["along"]))["at"]
				points.append(Vector2(at.x, at.z))
			"frame":
				var at: Vector3 = spec["at"]
				var yaw := float(spec.get("yaw", 0.0))
				var across := Vector2(cos(yaw), -sin(yaw))
				for side in [-1.0, 1.0]:
					points.append(Vector2(at.x, at.z) + across * side * 1.82)
	for point in points:
		var key := Vector2i(floori(point.x / BUCKET), floori(point.y / BUCKET))
		if not _mounts.has(key):
			_mounts[key] = []
		(_mounts[key] as Array).append(point)


## 0 at a wall mount, rising to 1 (natural rock) by `DRESSED_FAR`.
static func _dressed(x: float, z: float) -> float:
	var cx := floori(x / BUCKET)
	var cz := floori(z / BUCKET)
	var nearest := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var list = _mounts.get(Vector2i(cx + dx, cz + dz))
			if list == null:
				continue
			for point in list:
				nearest = minf(nearest, (point as Vector2).distance_squared_to(Vector2(x, z)))
	if nearest >= DRESSED_FAR * DRESSED_FAR:
		return 1.0
	return smoothstep(DRESSED_NEAR, DRESSED_FAR, sqrt(nearest))


## A room's edge as unit segments round its floor - north edge east, east edge
## south, south edge west, west edge north - each `[from, to, outside, inward]`:
## its lattice points, the room on the other side (-1 for rock) and the room's
## inward normal.
static func _perimeter(index: int) -> Array:
	var cells := Layout.cells_of(Layout.ROOMS[index]["rect"])
	var x0 := cells.position.x
	var z0 := cells.position.y
	var x1 := cells.end.x
	var z1 := cells.end.y
	var out: Array = []
	for x in range(x0, x1):
		out.append([Vector2i(x, z0), Vector2i(x + 1, z0), Layout.cell_room(x, z0 - 1), Vector2(0.0, 1.0)])
	for z in range(z0, z1):
		out.append([Vector2i(x1, z), Vector2i(x1, z + 1), Layout.cell_room(x1, z), Vector2(-1.0, 0.0)])
	for x in range(x1 - 1, x0 - 1, -1):
		out.append([Vector2i(x + 1, z1), Vector2i(x, z1), Layout.cell_room(x, z1), Vector2(0.0, -1.0)])
	for z in range(z1 - 1, z0 - 1, -1):
		out.append([Vector2i(x0, z + 1), Vector2i(x0, z), Layout.cell_room(x0 - 1, z), Vector2(1.0, 0.0)])
	return out


## Consecutive segments with the same room outside, round the loop: `{key,
## segments}` per stretch, starting where the outside changes.
static func _grouped(segments: Array) -> Array:
	var count := segments.size()
	var start := 0
	for index in count:
		if int(segments[index][2]) != int(segments[(index - 1 + count) % count][2]):
			start = index
			break
	var out: Array = []
	var current: Array = []
	var key := -2
	for step in count:
		var segment: Array = segments[(start + step) % count]
		if not current.is_empty() and int(segment[2]) != key:
			out.append({"key": key, "segments": current})
			current = []
		key = int(segment[2])
		current.append(segment)
	if not current.is_empty():
		out.append({"key": key, "segments": current})
	return out


## The way a lattice point is pushed out of the rock: the sum of the distinct
## normals of the floor/rock edges that meet there, from the four cells round it.
static func _push(ix: int, iz: int, fallback: Vector2) -> Vector2:
	var nw := Layout.cell_room(ix - 1, iz - 1) >= 0
	var ne := Layout.cell_room(ix, iz - 1) >= 0
	var sw := Layout.cell_room(ix - 1, iz) >= 0
	var se := Layout.cell_room(ix, iz) >= 0
	var east := false
	var west := false
	var south := false
	var north := false
	if nw != ne:
		east = ne
		west = not ne
	if sw != se:
		east = east or se
		west = west or not se
	if nw != sw:
		south = sw
		north = not sw
	if ne != se:
		south = south or se
		north = north or not se
	var push := Vector2((1.0 if east else 0.0) - (1.0 if west else 0.0),
		(1.0 if south else 0.0) - (1.0 if north else 0.0))
	return push if push.length_squared() > 0.25 else fallback


## The rows of a wall sheet, bottom to top: dense from `from` (under the lowest
## ground the room's walls stand on), then a row every 0.45 m, then the rows that
## carry the cove over `top`.
static func _rows(from: float, top: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([from, from + 0.12, from + 0.3, from + 0.55, from + 0.85, from + 1.2])
	var y := from + 1.65
	while y < top - 1.4:
		out.append(y)
		y += 0.45
	for high in [top - 1.0, top - 0.65, top - 0.35, top - 0.12, top + 0.1, top + OVER]:
		if high > out[out.size() - 1] + 0.08:
			out.append(high)
	return out


# --- the meshes ----------------------------------------------------------------------

## A grid of points (`cols` columns of `rows` rows, column-major) as triangles,
## facing the side `cross(along columns, up rows)` points to. Normals by central
## differences across the grid.
static func _sheet(grid: PackedVector3Array, cols: int, rows: int, verts: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var base := verts.size()
	for i in cols:
		for j in rows:
			var du := grid[mini(i + 1, cols - 1) * rows + j] - grid[maxi(i - 1, 0) * rows + j]
			var dv := grid[i * rows + mini(j + 1, rows - 1)] - grid[i * rows + maxi(j - 1, 0)]
			var normal := du.cross(dv)
			verts.append(grid[i * rows + j])
			normals.append(normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP)
	for i in cols - 1:
		for j in rows - 1:
			var a := base + i * rows + j
			var b := a + rows
			# Godot's front faces wind clockwise as seen from the side they face.
			indices.append_array(PackedInt32Array([a, b + 1, b, a, a + 1, b + 1]))


## The rock over a lower way out, from just under the lower roof to over this
## room's own. Each row is lofted between the two jambs as the wall skins push
## them (so the lintel meets both jamb columns exactly and never folds back over
## them), pushed into the room by the same field in between, with a soffit row
## tucked back over the lower roof so the opening's head has no open edge.
static func _lintel(index: int, lintel: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array) -> void:
	var lattice: Array = lintel["lattice"]
	var inward: Vector2 = lintel["normal"]
	var low := float(lintel["low"])
	var first: Vector2i = lattice[0]
	var last: Vector2i = lattice[lattice.size() - 1]
	var a := Layout.lattice(first.x, first.y)
	var b := Layout.lattice(last.x, last.y)
	var dir_a := _push(first.x, first.y, inward)
	var dir_b := _push(last.x, last.y, inward)
	var width := a.distance_to(b)
	var axis := (b - a) / maxf(width, 0.0001)
	var keep := PackedFloat32Array([low - 0.06])
	for y in _rows(Floor.low(index) - BURY, ceiling(index)):
		if y > low - 0.02:
			keep.append(y)
	var count := keep.size() + 1
	var grid := PackedVector3Array()
	grid.resize(lattice.size() * count)
	for i in lattice.size():
		var cell: Vector2i = lattice[i]
		var point := Layout.lattice(cell.x, cell.y)
		var t := float(i) / float(lattice.size() - 1)
		var open := minf(t, 1.0 - t) * width
		for j in keep.size():
			var y := keep[j]
			var end_a := a + dir_a * relief(index, a.x, y, a.y, 0.0, low)
			var end_b := b + dir_b * relief(index, b.x, y, b.y, 0.0, low)
			var u := lerpf((end_a - a).dot(axis), width + (end_b - b).dot(axis), t)
			var v := relief(index, point.x, y, point.y, open, low)
			if i == 0:
				v = (end_a - a).dot(inward)
			elif i == lattice.size() - 1:
				v = (end_b - b).dot(inward)
			var at := a + axis * u + inward * v
			grid[i * count + j + 1] = Vector3(at.x, y, at.y)
			if j == 0:
				var tuck := a + axis * u - inward * SOFFIT
				grid[i * count] = Vector3(tuck.x, low + 0.03, tuck.y)
	_sheet(grid, lattice.size(), count, verts, normals, indices)


## The roof: a height field over the room's rectangle, facing down.
static func _roof(index: int, verts: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array) -> void:
	var rect: Rect2 = Layout.ROOMS[index]["rect"]
	var cols := maxi(2, ceili(rect.size.x / ROOF_STEP) + 1)
	var rows := maxi(2, ceili(rect.size.y / ROOF_STEP) + 1)
	var grid := PackedVector3Array()
	grid.resize(cols * rows)
	for i in cols:
		var x := rect.position.x + rect.size.x * float(i) / float(cols - 1)
		for j in rows:
			var z := rect.position.y + rect.size.y * float(j) / float(rows - 1)
			grid[i * rows + j] = Vector3(x, roof_height(index, x, z), z)
	_sheet(grid, cols, rows, verts, normals, indices)
