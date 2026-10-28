extends RefCounted
## The one ground the whole world stands on: a deterministic heightfield, one
## `ArrayMesh` and one trimesh collider, and `height_at()` for everything that is
## placed on it.
##
## The campaign used to lie on a single flat box: 420 x 1480 m of y = 0. It is a
## drowned wood on a rolling floor now - three octaves of value noise on a fixed
## seed, 30-70 m wavelengths and a couple of metres of relief, so walking the trail
## goes over rises and through hollows and the horizon is not a line.
##
## Three rules hold it together.
##
## 1. **One surface.** The mesh, the collider and `height_at()` are the same
##    surface: `height_at` interpolates the exact triangle the collider carries, so
##    a prop placed by it sits on the ground a body walks on, not a centimetre
##    above or below it.
## 2. **Flat where flatness is the point.** The camp pocket and the town square are
##    padded to `PAD_Y` and blended into the slope over `blend` metres, so the cages
##    stand level, the square is level, and the walk between them is not.
## 3. **No seam, no ledge, no hole.** The field is bounded like the floor it
##    replaces, the mesh covers all of it, and the world keeps a catch floor under
##    the lowest point so nothing can fall out of the map.
##
## It is static state, because a world has exactly one ground: `build()` bakes the
## grid and every area samples it afterwards. Unbuilt (a standalone preview scene),
## `height_at()` answers 0.0 - the flat floor those previews still build.

const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## The strip the world occupies. `x` is the strip's west edge, `y` its near edge.
const ORIGIN := Vector2(-210.0, -1242.0)
const COLS := 60
const ROWS := 212
const CELL := 7.0
## Three octaves, 64/40/31 m. The sum is normalised to `peak` metres either side of
## the pads, so the relief is the ±2 m a forest floor rolls over, not a mountain and
## not corrugation.
const SEED := 51117
const OCTAVES := [{"wavelength": 64.0, "weight": 1.0}, {"wavelength": 40.0, "weight": 0.55},
	{"wavelength": 31.0, "weight": 0.28}]
const PEAK := 1.9
## Where a pad is flat, and how far it takes to stop being flat.
const PAD_Y := 0.0
## The worn path's footprint: how much dirt the walk loads into the terrain shader's
## vertex alpha, how wide it is at its widest, and how patchy it is along its length.
const WEAR_ALPHA := 0.55
const WEAR_PATCH := 0.55

static var _heights := PackedFloat32Array()
static var _built := false
static var _pads: Array = []
static var _worn: Array = []
## The baked field's extremes, so nothing has to fold 13,000 floats to read them.
static var _low := 0.0
static var _high := 0.0


## Bake the field under `parent` and build its mesh and collider.
##
## `pads` is the flat ground: `{rect: Rect2 (x/z), y: float, blend: float}`.
## `worn` is what feet have worn: `{points: PackedVector3Array, half_width: float}`,
## used only for the terrain shader's dirt weight - the ground stays one surface.
##
## Returns `{triangles, min, max, cell}` for the world's readout.
static func build(parent: Node3D, style: WorldStyle, pads: Array = [],
		worn: Array = []) -> Dictionary:
	_pads = pads
	_worn = worn
	_bake()
	var mesh := _mesh()
	var material: Material = TextureLibrary.terrain_material(style)
	var view := MeshInstance3D.new()
	view.name = "Terrain"
	view.mesh = mesh
	view.material_override = material
	if parent != null:
		parent.add_child(view)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	if parent != null:
		parent.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "TerrainShape"
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(_faces())
	shape.shape = concave
	body.add_child(shape)
	return {"triangles": COLS * ROWS * 2, "cell": CELL, "min": _low, "max": _high}


## The ground at a point, exactly as the collider carries it.
static func height_at(x: float, z: float) -> float:
	if not _built:
		return PAD_Y
	var u := clampf((x - ORIGIN.x) / CELL, 0.0, float(COLS) - 0.0001)
	var v := clampf((z - ORIGIN.y) / CELL, 0.0, float(ROWS) - 0.0001)
	var i := int(u)
	var j := int(v)
	var fx := u - float(i)
	var fz := v - float(j)
	var h00 := _at(i, j)
	var h10 := _at(i + 1, j)
	var h01 := _at(i, j + 1)
	var h11 := _at(i + 1, j + 1)
	# The cell is split on the (i + 1, j) -> (i, j + 1) diagonal, exactly as the
	# mesh and the collider split it.
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return (h11 - h01) * fx + (h11 - h10) * fz + (h10 + h01 - h11)


## The same point lifted onto the ground: what every prop that stands on it uses.
static func grounded(at: Vector3) -> Vector3:
	return Vector3(at.x, height_at(at.x, at.z) + at.y, at.z)


## The surface normal at a point, for anything laid flat on the ground.
static func normal_at(x: float, z: float) -> Vector3:
	var u := clampf((x - ORIGIN.x) / CELL, 0.0, float(COLS) - 0.0001)
	var v := clampf((z - ORIGIN.y) / CELL, 0.0, float(ROWS) - 0.0001)
	var i := int(u)
	var j := int(v)
	var dx := (_at(i + 1, j) - _at(i, j)) / CELL
	var dz := (_at(i, j + 1) - _at(i, j)) / CELL
	return Vector3(-dx, 1.0, -dz).normalized()


## A basis with +Y on the ground's normal and `yaw` about it: a patch of worn
## earth lies on the slope instead of cutting into it.
static func ground_basis(x: float, z: float, yaw: float = 0.0) -> Basis:
	return Basis(Quaternion(Vector3.UP, normal_at(x, z))) * Basis(Vector3.UP, yaw)


## The lowest the ground ever gets, so the world can keep its net under it.
static func floor_bottom() -> float:
	if not _built:
		return PAD_Y
	return _low


## Whether a field has been baked at all: the standalone previews have none and
## stand on their own flat floors.
static func is_built() -> bool:
	return _built


# --- the field -------------------------------------------------------------

static func _bake() -> void:
	var count := (COLS + 1) * (ROWS + 1)
	var raw := PackedFloat32Array()
	raw.resize(count)
	var lowest := INF
	var highest := -INF
	for j in ROWS + 1:
		for i in COLS + 1:
			var x := ORIGIN.x + float(i) * CELL
			var z := ORIGIN.y + float(j) * CELL
			var value := _sum(x, z)
			raw[j * (COLS + 1) + i] = value
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	# Normalised to `PEAK`: a fixed seed gives a fixed field, and its extremes are
	# the relief the world was designed around rather than whatever the octaves
	# happened to add up to.
	var scale := PEAK / maxf(maxf(absf(lowest), absf(highest)), 0.0001)
	var width := COLS + 1
	_heights = PackedFloat32Array()
	_heights.resize(count)
	_low = INF
	_high = -INF
	for j in ROWS + 1:
		for i in width:
			var index := j * width + i
			var height := _padded(raw[index] * scale,
				ORIGIN.x + float(i) * CELL, ORIGIN.y + float(j) * CELL)
			_heights[index] = height
			_low = minf(_low, height)
			_high = maxf(_high, height)
	_built = true


static func _at(i: int, j: int) -> float:
	var width := COLS + 1
	return _heights[clampi(j, 0, ROWS) * width + clampi(i, 0, COLS)]


## The unbaked height: three octaves of value noise, weighted and summed.
static func _sum(x: float, z: float) -> float:
	var total := 0.0
	var weight := 0.0
	for octave in OCTAVES:
		var wavelength := float(octave["wavelength"])
		var octave_weight := float(octave["weight"])
		total += octave_weight * _value(x / wavelength, z / wavelength)
		weight += octave_weight
	return total / maxf(weight, 0.0001)


## Smooth value noise: a lattice of fixed hashes, smoothstep between them.
static func _value(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - float(ix)
	var fz := z - float(iz)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sz := fz * fz * (3.0 - 2.0 * fz)
	var a := _lattice(ix, iz)
	var b := _lattice(ix + 1, iz)
	var c := _lattice(ix, iz + 1)
	var d := _lattice(ix + 1, iz + 1)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sz)


## One lattice corner's value in [-1, 1). Integer arithmetic only, so the same
## seed is the same wood on every machine and every run.
static func _lattice(ix: int, iz: int) -> float:
	var h := (ix * 374761393 + iz * 668265263 + SEED * 69069) & 0x7fffffff
	h = (h ^ (h >> 13)) & 0x7fffffff
	h = (h * 1274126177) & 0x7fffffff
	h = (h ^ (h >> 16)) & 0x7fffffff
	return float(h % 2000001) / 1000000.0 - 1.0


## A baked height, pressed flat inside a pad and taken back to the slope over the
## pad's blend. The blend is a smoothstep, so the edge of a pad is a curve and not
## a step.
static func _padded(height: float, x: float, z: float) -> float:
	var point := Vector2(x, z)
	var out := height
	for pad in _pads:
		var rect: Rect2 = pad["rect"]
		var blend := float(pad.get("blend", 8.0))
		var target := float(pad.get("y", PAD_Y))
		if not rect.grow(blend).has_point(point):
			continue
		var dx := maxf(rect.position.x - x, x - rect.end.x)
		var dz := maxf(rect.position.y - z, z - rect.end.y)
		var outside := sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dz, 0.0) * maxf(dz, 0.0))
		var t := clampf(outside / maxf(blend, 0.0001), 0.0, 1.0)
		out = lerpf(target, out, t * t * (3.0 - 2.0 * t))
	return out


# --- the mesh --------------------------------------------------------------

static func _mesh() -> ArrayMesh:
	var width := COLS + 1
	var count := width * (ROWS + 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	for j in ROWS + 1:
		for i in width:
			var x := ORIGIN.x + float(i) * CELL
			var z := ORIGIN.y + float(j) * CELL
			var index := j * width + i
			vertices[index] = Vector3(x, _at(i, j), z)
			normals[index] = normal_at(x, z)
			# Vertex colour: the tint the terrain shader multiplies in, and the
			# alpha that is its dirt weight - a faint, patchy, foot-worn line
			# through the wood, not a road.
			var tint := 0.94 + 0.08 * (_value(x / 23.0, z / 23.0) * 0.5 + 0.5)
			colors[index] = Color(tint, tint, tint * 0.97, _wear(x, z))
	for j in ROWS:
		for i in COLS:
			var a := j * width + i
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
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The collider's faces: the same triangles, in the same order, unindexed.
static func _faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(COLS * ROWS * 6)
	var at := 0
	for j in ROWS:
		var z0 := ORIGIN.y + float(j) * CELL
		var z1 := z0 + CELL
		for i in COLS:
			var x0 := ORIGIN.x + float(i) * CELL
			var x1 := x0 + CELL
			var a := Vector3(x0, _at(i, j), z0)
			var b := Vector3(x1, _at(i + 1, j), z0)
			var c := Vector3(x0, _at(i, j + 1), z1)
			var d := Vector3(x1, _at(i + 1, j + 1), z1)
			faces[at] = a
			faces[at + 1] = b
			faces[at + 2] = c
			faces[at + 3] = b
			faces[at + 4] = d
			faces[at + 5] = c
			at += 6
	return faces


## What the terrain shader paints as dirt at a point: the wear of the walked
## route, ragged and patchy, plus the trodden middle of a camp.
static func _wear(x: float, z: float) -> float:
	var patch := 0.5 + 0.5 * _value(x / 11.0 + 31.0, z / 11.0 - 17.0)
	var dirt := 0.05 + 0.06 * patch
	for path in _worn:
		var points: PackedVector3Array = path["points"]
		var half := float(path.get("half_width", 3.0)) * (0.55 + 0.75 * patch)
		var distance := _distance_to(points, x, z)
		if distance >= half:
			continue
		var weight := 1.0 - smoothstep(half * 0.25, half, distance)
		dirt = maxf(dirt, weight * WEAR_ALPHA * (0.45 + WEAR_PATCH * patch))
	return clampf(dirt, 0.0, 1.0)


## XZ distance from a point to a polyline.
static func _distance_to(points: PackedVector3Array, x: float, z: float) -> float:
	var best := INF
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var bx := b.x - a.x
		var bz := b.z - a.z
		var length_squared := bx * bx + bz * bz
		var t := 0.0
		if length_squared > 0.000001:
			t = clampf(((x - a.x) * bx + (z - a.z) * bz) / length_squared, 0.0, 1.0)
		var cx := a.x + bx * t - x
		var cz := a.z + bz * t - z
		best = minf(best, sqrt(cx * cx + cz * cz))
	return best
