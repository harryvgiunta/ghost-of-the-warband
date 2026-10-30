extends RefCounted
## The one ground the whole world stands on: a deterministic heightfield, one
## `ArrayMesh` and one trimesh collider, and `height_at()` for everything that is
## placed on it.
##
## The campaign used to lie on a single flat box: 420 x 1480 m of y = 0. It is a
## drowned wood in hill country now - three octaves of value noise on a fixed seed,
## 190/100/58 m wavelengths and `RELIEF` metres either side of level, so the walk
## to town crosses crests and drops into hollows and the horizon is a range of
## swells rather than a line. The waves are long against their own amplitude on
## purpose: a hill here is a minute's walk up and a minute's walk down, at ten
## degrees, never a face to climb.
##
## Four rules hold it together.
##
## 1. **One surface.** The mesh, the collider and `height_at()` are the same
##    surface: `height_at` interpolates the exact triangle the collider carries, so
##    a prop placed by it sits on the ground a body walks on, not a centimetre
##    above or below it.
## 2. **Flat where flatness is the point.** The camp pocket and the town square are
##    padded to `PAD_Y` and blended into the slope over `blend` metres, so the cages
##    stand level, the square is level, and the walk between them is not.
## 3. **The wood is closed.** After the rolling floor is normalised, a mountain rim
##    is raised along the strip's four edges - a steep face inside the field's
##    boundary, 34-58 m high and noise-varied along its length - so the trail is a
##    valley with walls instead of a plank in space. The face is steeper than the
##    46-degree `floor_max_angle` every body walks with, so the trimesh *is* the
##    wall and no collision is added for it.
## 4. **No seam, no ledge, no hole.** The field is bounded like the floor it
##    replaces, the mesh covers all of it, and the world keeps a catch floor under
##    the lowest point so nothing can fall out of the map.
##
## One hollow is cut into it: a shallow swamp basin `SWAMP_FRACTION` of the way
## down the trail, on one side of the lane, with a flat water level `swamp_region()`
## publishes for the water plane and its reeds. The lane itself is never dug - the
## basin starts `SWAMP_INNER` metres off the centre line, clear of the torch posts
## - so the route stays exactly the route while the ground beside it goes wet.
##
## What feet have done to it is painted, not modelled: `build()` bakes the worn
## lines and spots it is handed - the lane, the corridor, the camp's yard, the
## ruts, the town's ring - and the swamp's mud into a half-metre ground map
## (`wear_at()`, `wet_at()`), and the terrain shader height-blends dirt into the
## grass and litter by it. No disc of dirt is ever laid on top of the ground.
##
## It is static state, because a world has exactly one ground: `build()` bakes the
## grid and every area samples it afterwards. Unbuilt (a standalone preview scene),
## `height_at()` answers 0.0 - the flat floor those previews still build.

const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## The strip the world occupies. `x` is the strip's west edge, `y` its near edge.
## It is sized off the trail the world builds: the lane runs 1,375 m south from the
## camp's mouth, the town stands 30 m past its far end, and the wood that has
## grown out to `run_forest.gd`'s `WOOD_EDGE` has to stand on ground that does not
## climb. So x reaches 268 m either side of the lane - the wood's edge, the rim's
## toe and the face climbing to the boundary - and z runs from the camp's own wood
## in the north to a town pad 62 m short of the southern rim.
const ORIGIN := Vector2(-268.0, -1695.0)
const COLS := 77
const ROWS := 277
const CELL := 7.0
## Three octaves, 190/100/58 m. The sum is normalised to `RELIEF` metres either
## side of level, so the wood rises and falls by about a house and a half over a
## couple of hundred metres - hill country, walked at ten degrees, not a mountain
## and not corrugation. The old floor was ±2 m of the same noise at a quarter the
## wavelength: relief you could see in the triangle count and never on the skyline.
## `_relief_hold()` keeps the swells off the pads, so the camp and the square stayed
## level while the ground between them became a walk over real ground.
const SEED := 51117
const OCTAVES := [{"wavelength": 190.0, "weight": 1.0}, {"wavelength": 100.0, "weight": 0.55},
	{"wavelength": 58.0, "weight": 0.3}]
const RELIEF := 22.0
## Where the swells are held down to nothing and how far they take to come back.
## Measured from the pad's own rectangle: inside `RELIEF_HOLD_INNER` of its edge the
## ground is the pad's smooth base, and a hill reaches full height by
## `RELIEF_HOLD_OUTER`. Without the hold the camp sat in a pit walled by its own 14 m
## blend - a flat pad against ground that had climbed 16 m under it - and the walk
## out of it was a scramble.
const RELIEF_HOLD_INNER := 40.0
const RELIEF_HOLD_OUTER := 260.0
## Where a pad is flat, and how far it takes to stop being flat.
const PAD_Y := 0.0
## The mountain rim: the steep face's heights, the band it rises over at each
## edge (from the toe inside the wood to the field's boundary), and the share of
## that band the face takes. `_rim_curve()` reaches full height by this share, so
## the face is steeper than the 46-degree floor every body walks on and the strip
## is enclosed by ground rather than by an invisible wall.
const RIM_MIN := 34.0
const RIM_MAX := 58.0
const RIM_FACE_SHARE := 0.72
## West/east toes, and the north/south toes. The field is x -268..271, z
## -1695..244, and the wood's own outer row stands at 196 m off the lane, so the
## toe is past it and the face has 50 m (or 62 m north and south) to climb in.
const RIM_TOE_X := 218.0
const RIM_TOE_Z_NORTH := 180.0
const RIM_TOE_Z_SOUTH := -1633.0
## The upper edge of the rim's forested skirt, as a share of the face height:
## below it the slope is gentle and dark enough for the wood's own rows to stand.
const RIM_SKIRT_SHARE := 0.24
## The swamp: where along the trail it begins, which side of the lane it lies on,
## how far off the line its banks run, how long it is, and how deep the bowl cuts.
## The water level is the lane's own height minus `SWAMP_WATER_DROP`, and the
## water plane's inner edge starts past the torch line (`SWAMP_INNER` > 5.4 m).
const SWAMP_FRACTION := 0.515
const SWAMP_SIDE := -1.0
const SWAMP_INNER := 6.4
const SWAMP_OUTER := 26.0
const SWAMP_HALF_LENGTH := 46.0
const SWAMP_BANK := 4.5
const SWAMP_DEPTH := 1.45
const SWAMP_WATER_DROP := 0.55
## The trail line the swamp is measured against: the longest polyline the caller
## passes as `worn` is the lane (the corridor to the camp is a fifth as long).
const SWAMP_TRAIL_MIN_LENGTH := 400.0
## The worn ground: what feet have done to the floor, as the terrain shader reads it.
## It is a baked map, not the mesh's vertex alpha - a 7 m vertex grid drew every
## trodden patch as a diamond of triangles and the camp's dirt as hard discs laid
## on top of the grass - so `MAP_TEXEL` is half a metre over the box the worn
## ground occupies (plus `MAP_MARGIN`), and the shader breaks its edge up further
## with its own noise and the layers' heights.
const MAP_TEXEL := 0.5
const MAP_MARGIN := 12.0
## A worn line's default footprint: how much dirt the walk loads into the map, and
## how patchy it is along its length. The patch noise swings the line's width from
## 0.55x to 1.3x of `half_width` and its wear by `WEAR_PATCH`; the core stays bare
## earth, because a line that faded to half-worn in its middle read as leaves.
const WEAR_STRENGTH := 0.55
const WEAR_PATCH := 0.25
## How far a worn spot's edge wanders, as a share of its radius, and the size of
## the wander: a trampled patch is never a circle.
const SPOT_WOBBLE := 0.5
const SPOT_WOBBLE_SCALE := 4.3
## Where grass starts to be trodden out of the worn ground, and where none is left.
const TRODDEN_FROM := 0.06
const TRODDEN_BARE := 0.42

static var _heights := PackedFloat32Array()
static var _built := false
static var _pads: Array = []
static var _worn: Array = []
## The baked swamp, as `height_at()`'s owner publishes it to anything that wants
## to lay water, reeds or mist: `{centre, forward, right, water_y, inner, outer,
## half_length, side}`.
static var _swamp: Dictionary = {}
## The baked field's extremes, so nothing has to fold 21,000 floats to read them.
static var _low := 0.0
static var _high := 0.0
## The ground map: two bytes a texel (R wear, G wet), `_map_width` x `_map_height`
## texels of `MAP_TEXEL` metres from `_map_origin` (world x/z), and the texture
## the terrain material samples it through.
static var _map := PackedByteArray()
static var _map_width := 0
static var _map_height := 0
static var _map_origin := Vector2.ZERO
static var _map_texture: ImageTexture = null


## Bake the field under `parent` and build its mesh and collider.
##
## `pads` is the flat ground: `{rect: Rect2 (x/z), y: float, blend: float}`.
## `worn` is what feet have worn, painted into the ground map the terrain shader
## blends dirt and wet by - the ground stays one surface. Each entry is a line
## `{points: PackedVector3Array, half_width: float}` or a spot `{point: Vector3,
## radius: float}`; both take an optional `strength` (peak wear, default
## `WEAR_STRENGTH`) and `wet` (peak wetness, default 0).
##
## Returns `{triangles, min, max, cell, map}` for the world's readout.
static func build(parent: Node3D, style: WorldStyle, pads: Array = [],
		worn: Array = []) -> Dictionary:
	_pads = pads
	_worn = worn
	_bake()
	_bake_ground_map()
	var mesh := _mesh()
	var material := TextureLibrary.terrain_material(style).duplicate() as ShaderMaterial
	material.set_shader_parameter("ground_map", _map_texture)
	material.set_shader_parameter("ground_map_origin", _map_origin)
	material.set_shader_parameter("ground_map_size",
		Vector2(float(_map_width), float(_map_height)) * MAP_TEXEL)
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
	return {"triangles": COLS * ROWS * 2, "cell": CELL, "min": _low, "max": _high,
		"map": Vector2i(_map_width, _map_height)}


## The ground at a point, exactly as the collider carries it.
static func height_at(x: float, z: float) -> float:
	if not _built:
		return PAD_Y
	return _sampled(x, z)


## The same point lifted onto the ground: what every prop that stands on it uses.
static func grounded(at: Vector3) -> Vector3:
	return Vector3(at.x, height_at(at.x, at.z) + at.y, at.z)


## The one swamp in the wood, for the trail's water plane, reeds and mist:
## `{centre, forward, right, water_y, inner, outer, half_length, side}`, or an
## empty dictionary in a preview whose ground was never baked. `centre` is on the
## lane at `SWAMP_FRACTION`; `side` is the lane's own right-hand sign the basin
## lies on.
static func swamp_region() -> Dictionary:
	return _swamp.duplicate() if not _swamp.is_empty() else {}


## The interpolated field without the "was it baked" guard, so the bake itself
## can sample its own progress.
static func _sampled(x: float, z: float) -> float:
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


## The surface normal at a point, for anything laid flat on the ground. Unbuilt (a
## standalone preview's flat floor) it is straight up, as `height_at()` is level.
static func normal_at(x: float, z: float) -> Vector3:
	if not _built:
		return Vector3.UP
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
	# Normalised to `RELIEF`: a fixed seed gives a fixed field, and its extremes are
	# the relief the world was designed around rather than whatever the octaves
	# happened to add up to.
	var scale := RELIEF / maxf(maxf(absf(lowest), absf(highest)), 0.0001)
	var width := COLS + 1
	_heights = PackedFloat32Array()
	_heights.resize(count)
	_swamp = {}
	for j in ROWS + 1:
		for i in width:
			var index := j * width + i
			var x := ORIGIN.x + float(i) * CELL
			var z := ORIGIN.y + float(j) * CELL
			# The rolling floor - held down around the pads - then the pads, then
			# the rim that closes the strip.
			_heights[index] = _rimmed(_padded(raw[index] * scale * _relief_hold(x, z),
				x, z), x, z)
	# The swamp is cut after the rim and the pads: a hollow in the walking wood,
	# never a second surface. It also publishes the water level the trail's water
	# plane lies on, measured off the lane's own baked height.
	_settle_swamp()
	_low = INF
	_high = -INF
	for index in count:
		_low = minf(_low, _heights[index])
		_high = maxf(_high, _heights[index])
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


## How much of the rolling floor a point keeps: 0 within `RELIEF_HOLD_INNER` of a
## pad's edge, 1 from `RELIEF_HOLD_OUTER`, smoothstepped between. One rule for every
## pad handed in, so the camp pocket and the town square are held the same way and a
## world with no pads at all (a bare field, a preview) keeps all of its relief.
static func _relief_hold(x: float, z: float) -> float:
	if _pads.is_empty():
		return 1.0
	var hold := 1.0
	for pad in _pads:
		var rect: Rect2 = pad["rect"]
		var dx := maxf(rect.position.x - x, x - rect.end.x)
		var dz := maxf(rect.position.y - z, z - rect.end.y)
		var outside := sqrt(maxf(dx, 0.0) * maxf(dx, 0.0) + maxf(dz, 0.0) * maxf(dz, 0.0))
		var t := clampf((outside - RELIEF_HOLD_INNER)
			/ maxf(RELIEF_HOLD_OUTER - RELIEF_HOLD_INNER, 0.0001), 0.0, 1.0)
		hold = minf(hold, t * t * (3.0 - 2.0 * t))
	return hold


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


# --- the rim and the swamp -------------------------------------------------

## The strip's edges, raised: the field boundary pulled in to the four toes, with
## the whole face inside `RIM_FACE_SHARE` of that band. A body walks with a
## 46-degree floor, and the face is steeper than that everywhere it is climbed, so
## the trimesh closes the wood without a single extra collider. The height along
## the ridge is noise-varied, so the rim is a range of peaks.
static func _rimmed(height: float, x: float, z: float) -> float:
	var rise := _rim_rise(x, z)
	if rise <= 0.0:
		return height
	var noise := 0.5 + 0.5 * _value(x / 47.0 + 11.0, z / 47.0 - 5.0)
	return height + rise * lerpf(RIM_MIN, RIM_MAX, noise)


## 0 in the walking wood, 1 at the field's edge. The max of the four faces, so a
## corner takes the taller of its two ridges instead of adding them.
static func _rim_rise(x: float, z: float) -> float:
	# The toes are symmetric in x and hand-set in z; every denominator is the real
	# distance from its toe to the field's own boundary, so the face's gradient is
	# the same on all four sides whatever the strip is sized to.
	var east_edge := ORIGIN.x + float(COLS) * CELL
	var north_edge := ORIGIN.y + float(ROWS) * CELL
	var west := (-RIM_TOE_X - x) / maxf(absf(ORIGIN.x) - RIM_TOE_X, 1.0)
	var east := (x - RIM_TOE_X) / maxf(east_edge - RIM_TOE_X, 1.0)
	var north := (z - RIM_TOE_Z_NORTH) / maxf(north_edge - RIM_TOE_Z_NORTH, 1.0)
	var south := (RIM_TOE_Z_SOUTH - z) / maxf(RIM_TOE_Z_SOUTH - ORIGIN.y, 1.0)
	return maxf(maxf(_rim_curve(west), _rim_curve(east)),
		maxf(_rim_curve(north), _rim_curve(south)))


## The face's own profile: zero at the toe, the full peak by `RIM_FACE_SHARE`,
## and the plateau to the boundary. The mid-face gradient is `1.5 / 0.72` of the
## average, which is what puts every climb over the 46-degree floor.
static func _rim_curve(t: float) -> float:
	var share := clampf(t / RIM_FACE_SHARE, 0.0, 1.0)
	return share * share * (3.0 - 2.0 * share)


## Cut the one swamp into the baked field. The bowl is measured off the lane's
## own height at that fraction, its banks stay under 25 degrees, and the water
## level is published for the trail to lay a plane on. Everything is derived from
## the lane polyline the world hands in as `worn`, so the swamp follows the route
## instead of a guessed coordinate.
static func _settle_swamp() -> void:
	_swamp = {}
	var trail := _trail_line()
	if trail.size() < 2:
		return
	var marks := PackedFloat32Array()
	marks.resize(trail.size())
	marks[0] = 0.0
	for index in range(1, trail.size()):
		marks[index] = marks[index - 1] + trail[index - 1].distance_to(trail[index])
	var total: float = marks[marks.size() - 1]
	if total < SWAMP_TRAIL_MIN_LENGTH:
		return
	var frame := _frame_on(trail, marks, total * SWAMP_FRACTION)
	var centre: Vector3 = frame["position"]
	var forward: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var flat := Vector2(centre.x, centre.z)
	var heading := Vector2(forward.x, forward.z)
	var across := Vector2(right.x, right.z)
	var base := 0.0
	for along in [-SWAMP_HALF_LENGTH, -SWAMP_HALF_LENGTH * 0.5, 0.0,
			SWAMP_HALF_LENGTH * 0.5, SWAMP_HALF_LENGTH]:
		var sample := centre + forward * float(along)
		base += _sampled(sample.x, sample.z)
	base /= 5.0
	for j in ROWS + 1:
		for i in COLS + 1:
			var x := ORIGIN.x + float(i) * CELL
			var z := ORIGIN.y + float(j) * CELL
			var weight := _swamp_weight(x, z, flat, across, heading)
			if weight <= 0.0:
				continue
			var ripple := 0.30 * (0.5 + 0.5 * _value(x / 13.0 + 7.0, z / 13.0 - 3.0))
			var floor_y := base - SWAMP_DEPTH - ripple
			var slot := j * (COLS + 1) + i
			_heights[slot] = lerpf(_heights[slot], floor_y, weight)
	_swamp = {
		"centre": centre,
		"forward": forward,
		"right": right,
		"water_y": base - SWAMP_WATER_DROP,
		"inner": SWAMP_INNER,
		"outer": SWAMP_OUTER,
		"half_length": SWAMP_HALF_LENGTH,
		"side": SWAMP_SIDE,
	}


## How much of the swamp a point belongs to: 0 on dry ground and on the lane,
## 1 in the middle of the bowl. Shared by the bake, the mesh's wet tint and the
## trail's reeds.
static func _swamp_weight(x: float, z: float, centre: Vector2, across: Vector2,
		heading: Vector2) -> float:
	var offset := Vector2(x, z) - centre
	var along := offset.dot(heading)
	var lateral := offset.dot(across) * SWAMP_SIDE
	if lateral <= SWAMP_INNER - SWAMP_BANK or lateral >= SWAMP_OUTER + SWAMP_BANK:
		return 0.0
	if absf(along) >= SWAMP_HALF_LENGTH:
		return 0.0
	var along_window := 1.0 - smoothstep(SWAMP_HALF_LENGTH * 0.62, SWAMP_HALF_LENGTH,
		absf(along))
	var bank_in := smoothstep(SWAMP_INNER, SWAMP_INNER + SWAMP_BANK, lateral)
	var bank_out := 1.0 - smoothstep(SWAMP_OUTER - SWAMP_BANK, SWAMP_OUTER, lateral)
	return clampf(along_window * bank_in * bank_out, 0.0, 1.0)


## The swamp's weight at a world point, for anything outside the bake that wants
## to know whether it stands in the wet (the trail's darker brush, its reeds).
static func swamp_weight_at(x: float, z: float) -> float:
	if _swamp.is_empty():
		return 0.0
	var centre: Vector3 = _swamp["centre"]
	var forward: Vector3 = _swamp["forward"]
	var right: Vector3 = _swamp["right"]
	return _swamp_weight(x, z, Vector2(centre.x, centre.z),
		Vector2(right.x, right.z), Vector2(forward.x, forward.z))


## The longest polyline among the worn ones: the world's lane. The corridor to
## the camp is a hundred and seventy metres, so length is the one honest way to
## tell the route from the approach.
static func _trail_line() -> PackedVector3Array:
	var best := PackedVector3Array()
	var best_length := 0.0
	for path in _worn:
		var points: PackedVector3Array = path.get("points", PackedVector3Array())
		if points.size() < 2:
			continue
		var length := 0.0
		for index in range(points.size() - 1):
			length += points[index].distance_to(points[index + 1])
		if length > best_length:
			best_length = length
			best = points
	if best_length < SWAMP_TRAIL_MIN_LENGTH:
		return PackedVector3Array()
	return best


## The frame at an arc distance along a polyline: where it is, which way it runs
## and which way its right hand points.
static func _frame_on(trail: PackedVector3Array, marks: PackedFloat32Array,
		distance: float) -> Dictionary:
	var total: float = marks[marks.size() - 1]
	var at := clampf(distance, 0.0, total)
	var index := 0
	for probe in range(trail.size() - 1):
		if at <= marks[probe + 1]:
			index = probe
			break
		index = trail.size() - 2
	var from := trail[index]
	var to := trail[index + 1]
	var span := maxf(0.0001, marks[index + 1] - marks[index])
	var t := clampf((at - marks[index]) / span, 0.0, 1.0)
	var forward := (to - from) / (to - from).length()
	return {
		"position": from.lerp(to, t),
		"forward": forward,
		"right": Vector3(forward.z, 0.0, -forward.x),
	}


# --- the worn ground -------------------------------------------------------

## How worn the ground is at a point (0 untouched, 1 bare earth), exactly as the
## terrain shader reads it: the camp's trodden yard, the lane's line, the swamp's
## mud. Grass and litter placement read it so nothing grows where feet go.
static func wear_at(x: float, z: float) -> float:
	return _map_sample(x, z, 0)


## How wet the ground is at a point (0 dry, 1 standing mud).
static func wet_at(x: float, z: float) -> float:
	return _map_sample(x, z, 1)


## Whether a clump of grass at a point has been trodden out: always on bare earth,
## never on untouched ground, and between them by a fixed per-point hash - so the
## verge thins into the worn line the way a real path does, and a rebuilt world
## grows the same grass.
static func is_trodden(x: float, z: float) -> bool:
	var wear := wear_at(x, z)
	if wear <= TRODDEN_FROM:
		return false
	var roll := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
	return roll < smoothstep(TRODDEN_FROM, TRODDEN_BARE, wear)


## Paint every worn line and spot, then the swamp, into the ground map, and hand
## the result to the GPU as one RG8 texture with mipmaps. The map covers only the
## box the worn ground occupies: everything outside it reads as untouched.
static func _bake_ground_map() -> void:
	var box := _map_bounds()
	_map_origin = box.position
	_map_width = maxi(1, ceili(box.size.x / MAP_TEXEL))
	_map_height = maxi(1, ceili(box.size.y / MAP_TEXEL))
	_map = PackedByteArray()
	_map.resize(_map_width * _map_height * 2)
	for mark in _worn:
		var strength := float(mark.get("strength", WEAR_STRENGTH))
		var wet := float(mark.get("wet", 0.0))
		if mark.has("points"):
			_paint_line(mark["points"], float(mark.get("half_width", 3.0)), strength, wet)
		elif mark.has("point"):
			_paint_spot(mark["point"], float(mark.get("radius", 3.0)), strength, wet)
	_paint_swamp()
	var image := Image.create_from_data(_map_width, _map_height, false, Image.FORMAT_RG8, _map)
	image.generate_mipmaps()
	_map_texture = ImageTexture.create_from_image(image)


## The box the map has to cover: every worn line and spot at its widest, the
## swamp's banks, and `MAP_MARGIN` round all of it, clipped to the field. With
## nothing worn it is one texel at the origin, which reads as untouched ground.
static func _map_bounds() -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for mark in _worn:
		if mark.has("points"):
			var reach := _line_reach(float(mark.get("half_width", 3.0)))
			for point in mark["points"] as PackedVector3Array:
				low = low.min(Vector2(point.x, point.z) - Vector2.ONE * reach)
				high = high.max(Vector2(point.x, point.z) + Vector2.ONE * reach)
		elif mark.has("point"):
			var at: Vector3 = mark["point"]
			var reach := _spot_reach(float(mark.get("radius", 3.0)))
			low = low.min(Vector2(at.x, at.z) - Vector2.ONE * reach)
			high = high.max(Vector2(at.x, at.z) + Vector2.ONE * reach)
	for corner in _swamp_corners():
		low = low.min(corner)
		high = high.max(corner)
	if low.x > high.x:
		return Rect2(Vector2.ZERO, Vector2.ONE * MAP_TEXEL)
	var field := Rect2(ORIGIN, Vector2(float(COLS), float(ROWS)) * CELL)
	var box := Rect2(low, high - low).grow(MAP_MARGIN).intersection(field)
	# Snapped to the texel grid, so a rebuilt world bakes the same texels.
	var start := (box.position / MAP_TEXEL).floor() * MAP_TEXEL
	return Rect2(start, box.end - start)


## How far a worn line can reach from its centre: the patch noise swings the
## half width up to 1.3x.
static func _line_reach(half_width: float) -> float:
	return half_width * 1.3 + MAP_TEXEL


## How far a worn spot can reach: the wobble pushes its edge out by half again.
static func _spot_reach(radius: float) -> float:
	return radius * (1.0 + SPOT_WOBBLE * 0.5) + MAP_TEXEL


## A worn line: soft in its middle, ragged at its edges, and patchy along its
## length - the same footprint the vertex alpha used to carry, at half a metre.
static func _paint_line(points: PackedVector3Array, half_width: float, strength: float,
		wet: float) -> void:
	var reach := _line_reach(half_width)
	for index in range(points.size() - 1):
		var a := Vector2(points[index].x, points[index].z)
		var b := Vector2(points[index + 1].x, points[index + 1].z)
		var ab := b - a
		var length_squared := ab.length_squared()
		var texels := _texel_box(a.min(b) - Vector2.ONE * reach, a.max(b) + Vector2.ONE * reach)
		for j in range(texels.position.y, texels.end.y):
			var z := _map_origin.y + (float(j) + 0.5) * MAP_TEXEL
			for i in range(texels.position.x, texels.end.x):
				var x := _map_origin.x + (float(i) + 0.5) * MAP_TEXEL
				var t := 0.0
				if length_squared > 0.000001:
					t = clampf(((x - a.x) * ab.x + (z - a.y) * ab.y) / length_squared, 0.0, 1.0)
				var dx := a.x + ab.x * t - x
				var dz := a.y + ab.y * t - z
				var distance_squared := dx * dx + dz * dz
				if distance_squared >= reach * reach:
					continue
				var patch := 0.5 + 0.5 * _value(x / 11.0 + 31.0, z / 11.0 - 17.0)
				var half := half_width * (0.55 + 0.75 * patch)
				var distance := sqrt(distance_squared)
				if distance >= half:
					continue
				var weight := 1.0 - smoothstep(half * 0.25, half, distance)
				_stamp(i, j, weight * strength * (1.0 - WEAR_PATCH + WEAR_PATCH * patch),
					weight * wet)


## A worn spot: the ground round a cage, a fire, a doorway. Its edge wanders with
## the ground's own noise, so a trampled patch is never a disc.
static func _paint_spot(at: Vector3, radius: float, strength: float, wet: float) -> void:
	var centre := Vector2(at.x, at.z)
	var reach := _spot_reach(radius)
	var texels := _texel_box(centre - Vector2.ONE * reach, centre + Vector2.ONE * reach)
	for j in range(texels.position.y, texels.end.y):
		var z := _map_origin.y + (float(j) + 0.5) * MAP_TEXEL
		for i in range(texels.position.x, texels.end.x):
			var x := _map_origin.x + (float(i) + 0.5) * MAP_TEXEL
			var distance := Vector2(x, z).distance_to(centre)
			if distance >= reach:
				continue
			var wobble := _value(x / SPOT_WOBBLE_SCALE + 5.0, z / SPOT_WOBBLE_SCALE + 9.0)
			var edge := radius * (1.0 + SPOT_WOBBLE * 0.5 * wobble)
			if distance >= edge:
				continue
			var patch := 0.5 + 0.5 * _value(x / 11.0 + 31.0, z / 11.0 - 17.0)
			var weight := 1.0 - smoothstep(edge * 0.3, edge, distance)
			_stamp(i, j, weight * strength * (0.7 + 0.3 * patch), weight * wet)


## The swamp's bowl is mud and standing wet: nothing grows where the water sits,
## and its shore is the darkest, wettest ground in the wood.
static func _paint_swamp() -> void:
	if _swamp.is_empty():
		return
	var corners := _swamp_corners()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in corners:
		low = low.min(corner)
		high = high.max(corner)
	var centre: Vector3 = _swamp["centre"]
	var forward: Vector3 = _swamp["forward"]
	var right: Vector3 = _swamp["right"]
	var flat := Vector2(centre.x, centre.z)
	var heading := Vector2(forward.x, forward.z)
	var across := Vector2(right.x, right.z)
	var texels := _texel_box(low, high)
	for j in range(texels.position.y, texels.end.y):
		var z := _map_origin.y + (float(j) + 0.5) * MAP_TEXEL
		for i in range(texels.position.x, texels.end.x):
			var x := _map_origin.x + (float(i) + 0.5) * MAP_TEXEL
			var weight := _swamp_weight(x, z, flat, across, heading)
			if weight <= 0.0:
				continue
			_stamp(i, j, 0.9 * smoothstep(0.0, 0.35, weight), smoothstep(0.0, 0.6, weight))


## The swamp's footprint as four world x/z corners (empty when there is none).
static func _swamp_corners() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _swamp.is_empty():
		return out
	var centre: Vector3 = _swamp["centre"]
	var forward: Vector3 = _swamp["forward"]
	var right: Vector3 = _swamp["right"]
	var flat := Vector2(centre.x, centre.z)
	var heading := Vector2(forward.x, forward.z)
	var across := Vector2(right.x, right.z) * SWAMP_SIDE
	for along in [-SWAMP_HALF_LENGTH, SWAMP_HALF_LENGTH]:
		for lateral in [SWAMP_INNER - SWAMP_BANK, SWAMP_OUTER + SWAMP_BANK]:
			out.append(flat + heading * float(along) + across * float(lateral))
	return out


## The texels whose centres can fall inside a world x/z box, clipped to the map:
## `position` is the first texel, `end` one past the last.
static func _texel_box(low: Vector2, high: Vector2) -> Rect2i:
	var i0 := clampi(floori((low.x - _map_origin.x) / MAP_TEXEL), 0, _map_width)
	var j0 := clampi(floori((low.y - _map_origin.y) / MAP_TEXEL), 0, _map_height)
	var i1 := clampi(ceili((high.x - _map_origin.x) / MAP_TEXEL), 0, _map_width)
	var j1 := clampi(ceili((high.y - _map_origin.y) / MAP_TEXEL), 0, _map_height)
	return Rect2i(i0, j0, maxi(0, i1 - i0), maxi(0, j1 - j0))


## Paint one texel: wear and wet only ever grow, so overlapping marks keep the
## most worn reading instead of the last one written.
static func _stamp(i: int, j: int, wear: float, wet: float) -> void:
	var at := (j * _map_width + i) * 2
	_map[at] = maxi(_map[at], clampi(roundi(wear * 255.0), 0, 255))
	if wet > 0.0:
		_map[at + 1] = maxi(_map[at + 1], clampi(roundi(wet * 255.0), 0, 255))


## Bilinear read of one channel of the map, at texel centres like the GPU's.
static func _map_sample(x: float, z: float, channel: int) -> float:
	if _map_width <= 0 or _map.is_empty():
		return 0.0
	var u := (x - _map_origin.x) / MAP_TEXEL - 0.5
	var v := (z - _map_origin.y) / MAP_TEXEL - 0.5
	var i := floori(u)
	var j := floori(v)
	var fx := u - float(i)
	var fz := v - float(j)
	var top := lerpf(_texel(i, j, channel), _texel(i + 1, j, channel), fx)
	var bottom := lerpf(_texel(i, j + 1, channel), _texel(i + 1, j + 1, channel), fx)
	return lerpf(top, bottom, fz)


static func _texel(i: int, j: int, channel: int) -> float:
	if i < 0 or j < 0 or i >= _map_width or j >= _map_height:
		return 0.0
	return float(_map[(j * _map_width + i) * 2 + channel]) / 255.0


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
			# Vertex colour: a broad value tint the terrain shader multiplies in.
			# Its alpha stays 0 - the worn ground lives in the half-metre ground
			# map, and the swamp's silt and shade in that map's wet channel.
			var tint := 0.94 + 0.08 * (_value(x / 23.0, z / 23.0) * 0.5 + 0.5)
			var color := Color(tint, tint, tint * 0.97, 0.0)
			# The rim's skirt is forest-dark where the wood's last rows climb it;
			# the face above turns to cold stone.
			var rise := _rim_rise(x, z)
			if rise > 0.0:
				var rock := smoothstep(RIM_SKIRT_SHARE, 0.82, rise)
				var skirt := Color(color.r * 0.66, color.g * 0.84, color.b * 0.62)
				var stone := Color(color.r * 0.94, color.g * 0.98, color.b * 1.06)
				color = Color(lerpf(skirt.r, stone.r, rock),
					lerpf(skirt.g, stone.g, rock), lerpf(skirt.b, stone.b, rock),
					color.a)
			colors[index] = color
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

