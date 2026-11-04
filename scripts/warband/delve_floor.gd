extends RefCounted
## The Weeping Hollow's floor as a surface: the ground the party walks on.
##
## The plan (`delve_layout.gd`) says where the floor is; this says how high it is.
## No square metre of it is level. Under everything lies the plan's fall
## (`Layout.descent`): a bowl thirteen metres deep at the rim, so the lair is a
## long walk downhill from the mouth and the far shafts stand in ground that has
## already gone down. Over the fall the floor carries what water and breakdown
## leave in a cave: broad swells and hollows at `HILL` over a twenty-metre wave
## (`_hills`), broken stone over them at `KNOB` (`_knobs`), basins (`pit`) and
## heaps of fallen rock (`hump`).
##
## Three kinds of place are read off the plan itself. A shaft's landing ring and
## its rope are dressed flat (`pad`), because a party lands there and a body
## standing on a slope is a body that thinks it is falling; every light and prop
## the plan stands on the floor is dressed flat under its own footprint, so
## nothing is half-buried; and a pool lies in a pan cut `PAN` metres under the
## ground round it, so its water sits in a hollow of the floor and not on top of
## it - water is level, and everything else follows the floor. Nothing
## else is flattened, and a den's own posts are left on the ground they were
## written on - the pits keep `KEEP_CLEAR` off them instead.
##
## One field for the whole floor, and a function of the point rather than of the
## room: two rooms that share a way out agree on the ground exactly along it, so
## a doorway has no lip and a body never steps off a cliff it did not choose. It
## is read by the drawn floor and by its collider (`mesh`, `faces`, which are the
## same vertices), by the wall skin's foot and its talus (`delve_rock.gd`), by
## the dripstone and the lights and props set on it (`delve_dressing.gd`), by
## the crowd's posts (`delve_cave.gd`), by the rats along the walls
## (`delve_fauna.gd`) and by the squad's map (`squad_nav.gd`).

const Layout = preload("res://scripts/warband/delve_layout.gd")

## The grid the floor is drawn and collided on, in metres. Every shape the field
## carries is metres across, and the ground a body is stopped by is the very
## vertices it is drawn from: what stops a foot is exactly what the eye sees.
const STEP := 1.0
## The lowest a floor point can lie: under the deepest pit on the deepest rim,
## with the whole rock box hung off it (`delve_cave.gd`).
const LOW := -18.0
## How far the ground swells and dips at a twenty-metre wave, and how far the
## broken stone over it moves at a three-metre one.
const HILL := 0.65
const KNOB := 0.11
## A basin's depth and a mound's height at most, and how much floor one of them
## takes: a broken patch per `PIT_PER` square metres, six in ten of them hollow.
const PIT_DEEP := 1.35
const HUMP_HIGH := 0.9
const PIT_PER := 46.0
## A pit in a way out is smaller and shallower than one in a hall.
const WAY_SCALE := 0.72
## How flat the ground is dressed round a landing or a piece of the plan, how far
## that dressing blends back out into the natural floor, and how far a pool's pan
## is cut under the ground round it.
const PAD_RIM := 0.55
const PAN := 0.24
## How far a pit keeps off a den's post, so no body starts in a hole, and off a
## rope, so the foot of a climb is a place a body can stand.
const KEEP_CLEAR := 2.8
## How far under the lowest ground along a room's walls its rock skin starts.
const LOW_MARGIN := 0.35
## The bucket a feature is filed under, in metres: a point reads the one bucket
## it falls in, and a feature is filed in every bucket it reaches.
const BUCKET := 8.0

## Feature fields: what it is, its centre (cave x/z), its reach, what it adds (or,
## for a pad, the height it dresses the ground to), and whether it is read as a
## disc or a square.
const KIND := 0
const PX := 1
const PZ := 2
const RX := 3
const RZ := 4
const AMOUNT := 5
const SQUARE := 6
enum { PIT, HUMP, PAD }

static var _hills: FastNoiseLite = null
static var _knobs: FastNoiseLite = null
## Bucket point -> the features a height there has to read.
static var _features: Dictionary = {}
static var _pads: Dictionary = {}
## Every pad as filed, for the clearance test the basins are cut against.
static var _pads_flat: Array = []
## Pads waiting for their ground to be read (`_file_pads`).
static var _level: Array = []
## Point kept off the pits: `[centre, reach]`, a den's own posts and the ropes.
static var _kept: Array = []
static var _grids: Dictionary = {}
static var _meshes: Dictionary = {}
static var _faces: Dictionary = {}
static var _lows: Dictionary = {}


# --- reading -------------------------------------------------------------------

## The ground at a cave-local x/z point, in metres: 0 at the mouth's own floor,
## minus the plan's fall, plus whatever the floor does there. This is the one
## height everything that stands, walks or grows below asks for.
static func height(x: float, z: float) -> float:
	_build()
	var h := _base(x, z)
	var cell := Vector2i(floori(x / BUCKET), floori(z / BUCKET))
	var pits = _features.get(cell)
	if pits != null:
		for f in pits:
			var t := _reach(f, x, z)
			if t < 1.0:
				var edge := 1.0 - t * t
				var amount := edge * edge * float(f[AMOUNT])
				h += -amount if int(f[KIND]) == PIT else amount
	var pads = _pads.get(cell)
	if pads != null:
		for f in pads:
			var t := _reach(f, x, z)
			if t < 1.0:
				h = lerpf(h, float(f[AMOUNT]), 1.0 - smoothstep(PAD_RIM, 1.0, t))
	return h


## `at` with its feet set on the ground under it: a spot the plan authored at the
## floor (a fire, a coffin, a den's post) is a spot without a height, and this is
## the height it gets.
static func lift(at: Vector3) -> Vector3:
	return Vector3(at.x, at.y + height(at.x, at.z), at.z)


## The lowest ground along a room's walls, set a margin under it: the height a
## wall's rock sheet must start from, so a wall whose foot lies in a hollow still
## ends in rock and never in the air.
static func low(index: int) -> float:
	if not _lows.has(index):
		var rect: Rect2 = Layout.ROOMS[index]["rect"]
		var lowest := INF
		var x := rect.position.x
		while x <= rect.end.x + 0.001:
			lowest = minf(lowest, minf(height(x, rect.position.y), height(x, rect.end.y)))
			x += STEP
		var z := rect.position.y
		while z <= rect.end.y + 0.001:
			lowest = minf(lowest, minf(height(rect.position.x, z), height(rect.end.x, z)))
			z += STEP
		_lows[index] = lowest - LOW_MARGIN
	return float(_lows[index])


# --- the drawn and collided floor -----------------------------------------------

## A room's floor as one mesh, in the cave's frame, facing up. Built on first ask
## and kept: every descent after the first draws the same ground.
static func mesh(index: int) -> ArrayMesh:
	if _meshes.has(index):
		return _meshes[index]
	var grid := _grid(index)
	var points: PackedVector3Array = grid["points"]
	var cols := int(grid["cols"])
	var rows := int(grid["rows"])
	var normals := PackedVector3Array()
	normals.resize(points.size())
	for i in cols:
		for j in rows:
			var du := points[mini(i + 1, cols - 1) * rows + j] - points[maxi(i - 1, 0) * rows + j]
			var dv := points[i * rows + mini(j + 1, rows - 1)] - points[i * rows + maxi(j - 1, 0)]
			var normal := du.cross(dv)
			normals[i * rows + j] = normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP
	var indices := PackedInt32Array()
	indices.resize((cols - 1) * (rows - 1) * 6)
	var at := 0
	for i in cols - 1:
		for j in rows - 1:
			var a := i * rows + j
			var b := a + rows
			indices[at] = a
			indices[at + 1] = a + 1
			indices[at + 2] = b + 1
			indices[at + 3] = a
			indices[at + 4] = b + 1
			indices[at + 5] = b
			at += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[index] = made
	return made


## The same floor as the physics of the floor: one triangle per triangle of the
## drawn mesh, so a body stands on the ground it is looking at.
static func faces(index: int) -> PackedVector3Array:
	if _faces.has(index):
		return _faces[index]
	var grid := _grid(index)
	var points: PackedVector3Array = grid["points"]
	var cols := int(grid["cols"])
	var rows := int(grid["rows"])
	var out := PackedVector3Array()
	out.resize((cols - 1) * (rows - 1) * 6)
	var at := 0
	for i in cols - 1:
		for j in rows - 1:
			var a := i * rows + j
			var b := a + rows
			out[at] = points[a]
			out[at + 1] = points[a + 1]
			out[at + 2] = points[b + 1]
			out[at + 3] = points[a]
			out[at + 4] = points[b + 1]
			out[at + 5] = points[b]
			at += 6
	_faces[index] = out
	return out


## A room's floor vertices on the floor's grid, `cols` columns of `rows` rows,
## column-major. z runs *down* the rows: `dv` is -z, so `du.cross(dv)` turns up
## and the faces are wound the way `_sheet` winds them in `delve_rock.gd` - the
## floor is looked at from above, the roof from below.
static func _grid(index: int) -> Dictionary:
	if _grids.has(index):
		return _grids[index]
	var rect: Rect2 = Layout.ROOMS[index]["rect"]
	var xs := _axis(rect.position.x, rect.end.x)
	var zs := _axis(rect.position.y, rect.end.y)
	zs.reverse()
	var cols := xs.size()
	var rows := zs.size()
	var points := PackedVector3Array()
	points.resize(cols * rows)
	for i in cols:
		for j in rows:
			points[i * rows + j] = Vector3(xs[i], height(xs[i], zs[j]), zs[j])
	var grid := {"points": points, "cols": cols, "rows": rows}
	_grids[index] = grid
	return grid


## The columns of a room's floor: its own two edges exactly, and the floor's grid
## between them. Two rooms that share an edge therefore share the line exactly -
## the same points, the same heights - so a way out has neither a crack nor a lip.
static func _axis(from: float, to: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([from])
	var at := from + STEP
	while at < to - 0.001:
		out.append(at)
		at += STEP
	if to > from + 0.001:
		out.append(to)
	return out


# --- the field -------------------------------------------------------------------

## The ground before anything stands on it: the plan's fall, the broad swells and
## the broken stone. What the pads dress and the pits and mounds add is not in it.
static func _base(x: float, z: float) -> float:
	return Layout.descent(x, z) + HILL * _hills.get_noise_2d(x, z) + KNOB * _knobs.get_noise_2d(x, z)


## How far out from a feature a point is, in its own reach: 1 at its rim, 0 at its
## middle.
static func _reach(f: Array, x: float, z: float) -> float:
	var dx := (x - float(f[PX])) / float(f[RX])
	var dz := (z - float(f[PZ])) / float(f[RZ])
	if int(f[SQUARE]) != 0:
		return maxf(absf(dx), absf(dz))
	return sqrt(dx * dx + dz * dz)


static func _build() -> void:
	if _hills != null:
		return
	_hills = _noise(9109, 0.055, 2)
	_knobs = _noise(9133, 0.31, 2)
	_features.clear()
	_pads.clear()
	_pads_flat.clear()
	_level.clear()
	_kept.clear()
	_place_pads()
	_place_kept()
	# A pad dresses its ground to the height under its own middle, read before
	# anything is dressed; and it is filed before the basins are cut, so no pit
	# opens under a landing, a light, a prop or a pool.
	_file_pads()
	for index in Layout.ROOMS.size():
		_scatter(index)


## Everything the plan stands on the floor is dressed flat: a shaft's ring and its
## rope, every light and prop with a footprint, and a pool's pan.
static func _place_pads() -> void:
	for entry in Layout.LANDINGS:
		var centre: Vector3 = entry["centre"]
		_pad(Vector2(centre.x, centre.z), Vector2(4.2, 4.2), 0.0, false)
		var rope: Vector3 = entry["rope"]
		_pad(Vector2(rope.x, rope.z), Vector2(2.2, 2.2), 0.0, false)
	# The landing ring is dressed flat only as far as the posts reach: a body lands
	# on the level it walked into, and the hall beyond it keeps its own pitch.
	for spec in Layout.LIGHTS:
		if spec.has("wall"):
			continue
		var at := _spot(spec)
		_pad(Vector2(at.x, at.z), Vector2(1.5, 1.5), 0.0, false)
	for spec in Layout.PROPS:
		var kind := str(spec["kind"])
		if OVERHEAD.has(kind):
			continue
		var at := _spot(spec)
		var size: Vector2 = spec.get("size", Vector2.ZERO)
		var square := bool(spec.get("square", false))
		match kind:
			"pool":
				_pad(Vector2(at.x, at.z), size * 1.16, PAN, square)
			_:
				var reach: float = maxf(1.4, maxf(float(spec.get("radius", 0.0)) + 0.9, size.length() * 0.35))
				_pad(Vector2(at.x, at.z), Vector2(reach, reach), 0.0, false)


## What no basin may swallow: the posts a den's bodies stand on, and the ropes.
static func _place_kept() -> void:
	for den in Layout.DENS:
		for post in Layout.den_members(den):
			var at: Vector3 = post["at"]
			_kept.append([Vector2(at.x, at.z), KEEP_CLEAR])
	for entry in Layout.LANDINGS:
		var rope: Vector3 = entry["rope"]
		_kept.append([Vector2(rope.x, rope.z), KEEP_CLEAR])


## The basins and the mounds over one room's floor: half of them hollow, none of
## them under a den's post, a rope, a landing, a light or a prop.
static func _scatter(index: int) -> void:
	var room: Dictionary = Layout.ROOMS[index]
	var rect: Rect2 = room["rect"]
	var inner := rect.grow(-1.7)
	if inner.size.x < 2.0 or inner.size.y < 2.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 6163 + index * 131
	var narrow := minf(inner.size.x, inner.size.y)
	var way := bool(room.get("tunnel", false))
	for patch in int(rect.get_area() / PIT_PER):
		var p := Vector2(rng.randf_range(inner.position.x, inner.end.x),
			rng.randf_range(inner.position.y, inner.end.y))
		var reach: float = minf(rng.randf_range(1.9, 4.4), narrow * 0.34)
		var deep: float = minf(rng.randf_range(0.45, PIT_DEEP), reach * 0.45)
		if way:
			reach *= WAY_SCALE
			deep = minf(deep * WAY_SCALE, 0.6)
		if reach < 1.1 or not _open_for(p, reach):
			continue
		var hollow := rng.randf() < 0.62
		_add(_features, [PIT if hollow else HUMP, p.x, p.y, reach, reach,
			deep if hollow else minf(deep * 0.66, HUMP_HIGH), 0])


## Whether a patch of this reach may be cut at a point: clear of everything the
## floor is dressed for, of every post a body starts on and of the ropes.
static func _open_for(p: Vector2, reach: float) -> bool:
	for f in _pads_flat:
		if p.distance_to(Vector2(f[PX], f[PZ])) < reach + maxf(float(f[RX]), float(f[RZ])) + 0.8:
			return false
	for entry in _kept:
		if p.distance_to(entry[0]) < reach + float(entry[1]):
			return false
	return true


## A pad the floor is to be dressed with, filed once the ground it dresses to is
## known (`_file_pads`).
static func _pad(p: Vector2, reach: Vector2, drop: float, square: bool) -> void:
	_level.append([p, Vector2(maxf(reach.x, 0.6), maxf(reach.y, 0.6)), drop, square])


## File every pad at the height of the ground under its own middle, `drop` under
## it: a pool's pan is cut below the floor round it, everything else is dressed to
## the floor itself.
static func _file_pads() -> void:
	for entry in _level:
		var p: Vector2 = entry[0]
		var reach: Vector2 = entry[1]
		var f := [PAD, p.x, p.y, reach.x, reach.y, _base(p.x, p.y) - float(entry[2]),
			1 if bool(entry[3]) else 0]
		_add(_pads, f)
		_pads_flat.append(f)
	_level.clear()


static func _add(source: Dictionary, f: Array) -> void:
	var reach := maxf(float(f[RX]), float(f[RZ]))
	var from := Vector2i(floori((float(f[PX]) - reach) / BUCKET), floori((float(f[PZ]) - reach) / BUCKET))
	var to := Vector2i(floori((float(f[PX]) + reach) / BUCKET), floori((float(f[PZ]) + reach) / BUCKET))
	for z in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var key := Vector2i(x, z)
			if not source.has(key):
				source[key] = []
			(source[key] as Array).append(f)


## Props whose feet are not on the floor at all: they hang from the roof.
const OVERHEAD := ["roots"]


static func _spot(spec: Dictionary) -> Vector3:
	if spec.has("wall"):
		return Layout.wall_point(str(spec["room"]), str(spec["wall"]), float(spec["along"]))["at"]
	return spec.get("at", Vector3.ZERO)


static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise
