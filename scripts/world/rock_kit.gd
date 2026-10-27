class_name RockKit
extends RefCounted
## Deterministic natural stone for the wilderness.
##
## Each rock is an ellipsoid deformed by a seeded noise field, narrowed at the
## crown and chipped by a few break planes, so a scatter of boulders reads as
## granite breaking out of the ground instead of the same rounded polygon
## repeated. The silhouette, the collision hull and the surface are one mesh: what
## the ranger sees is exactly what stops an arrow.
##
## Meshes are authored once per variant and shared by the `WorldScatter` batches;
## nothing here touches the scene tree.

## Per-archetype authoring. `squash` is the ellipsoid the noise field is applied
## to, `taper` narrows the mass toward its crown (a boulder is not a ball), and
## `fractures` is how many break planes chip flat faces out of the surface. The
## underside is left rounded on purpose: a cut base becomes a wide flat rim that
## shows above the grass as a blade, while a rounded base just looks like rock
## where the terrain falls away.
const KINDS := {
	"boulder": {"segments": 18, "rings": 10, "noise": 0.30, "taper": 0.26, "fractures": 3,
		"squash": Vector3(1.0, 0.95, 0.94)},
	"slab": {"segments": 16, "rings": 9, "noise": 0.24, "taper": 0.12, "fractures": 2,
		"squash": Vector3(1.10, 0.86, 1.0)},
	"outcrop": {"segments": 18, "rings": 10, "noise": 0.28, "taper": 0.30, "fractures": 3,
		"squash": Vector3(1.12, 1.06, 1.02)},
	"spire": {"segments": 12, "rings": 10, "noise": 0.24, "taper": 0.30, "fractures": 3,
		"squash": Vector3(0.62, 1.55, 0.58)},
	"cobble": {"segments": 12, "rings": 8, "noise": 0.26, "taper": 0.24, "fractures": 2,
		"squash": Vector3(1.0, 0.85, 1.0)},
}


## Drops one authored stone into a kit's merged mesh (a fire ring, a kerb, a
## plinth): `size` is its half-width in metres, `sink` the fraction of its height
## left under the surface it sits in.
static func add_stone(merged, material: Material, stone: ArrayMesh, surface: Vector3,
		size: float, yaw: float, sink: float = 0.52, tilt: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) \
		* Basis(Vector3.BACK, tilt * 0.5)
	basis = basis.scaled_local(Vector3(size, size * 0.72, size * 0.9))
	var bounds: AABB = Transform3D(basis, Vector3.ZERO) * stone.get_aabb()
	var origin := Vector3(surface.x, surface.y - bounds.size.y * sink - bounds.position.y, surface.z)
	merged.add(stone, Transform3D(basis, origin), material)


## One faceted rock. `seed_value` selects the noise field, so the same seed always
## reproduces the same stone across runs and machines.
static func mesh(kind: String, seed_value: int) -> ArrayMesh:
	var spec: Dictionary = KINDS.get(kind, KINDS["boulder"])
	var segments: int = maxi(6, int(spec["segments"]))
	var rings: int = maxi(4, int(spec["rings"]))
	var amount: float = float(spec["noise"])
	var taper: float = float(spec["taper"])
	var squash: Vector3 = spec["squash"]
	var lons := segments
	var lats := rings + 1
	var offset := Vector3(float(seed_value % 61) * 0.37, float(seed_value % 47) * 0.23,
		float(seed_value % 89) * 0.19)
	var points := PackedVector3Array()
	points.resize(lats * lons)
	var low := INF
	var high := -INF
	for j in range(lats):
		var theta := -PI * 0.5 + PI * float(j) / float(rings)
		var ring := cos(theta)
		var y := sin(theta)
		for i in range(lons):
			var phi := TAU * float(i) / float(lons)
			var dir := Vector3(ring * sin(phi), y, ring * cos(phi))
			var sample := dir * 1.55 + offset
			# Three smooth bands: a broad lobe that decides the mass, a middle one
			# for shoulders and flanks, and a fine one for the chipped surface.
			# Everything stays continuous - quantising this field is what turns a
			# boulder into a crumpled shell.
			var broad := _fbm(sample, 2, seed_value) - 0.5
			var middle := _noise3(sample * 3.1 + Vector3(5.0, 13.0, 2.0), seed_value + 17) - 0.5
			var fine := _noise3(sample * 7.7 + Vector3(11.0, 3.0, 7.0), seed_value + 7) - 0.5
			var relief := broad * amount * 2.0 + middle * amount * 0.55 + fine * amount * 0.22
			# Narrow the crown: stone weathers rounder and thinner at the top.
			var crown := 1.0 - taper * smoothstep(-0.2, 1.0, dir.y)
			var point := dir * ((1.0 + clampf(relief, -0.55, 0.55)) * crown)
			point = Vector3(point.x * squash.x, point.y * squash.y, point.z * squash.z)
			points[j * lons + i] = point
			low = minf(low, point.y)
			high = maxf(high, point.y)
	if high <= low:
		return ArrayMesh.new()
	# Fracture planes: granite does not weather round, it breaks. Each plane
	# flattens everything beyond it into one face, which is what gives a boulder
	# its chipped sides and a slab its cleft.
	var fractures: int = int(spec["fractures"])
	var fracture_rng := RandomNumberGenerator.new()
	fracture_rng.seed = seed_value
	for _index in range(fractures):
		var normal := Vector3(fracture_rng.randf_range(-1.0, 1.0),
			fracture_rng.randf_range(-0.45, 0.55), fracture_rng.randf_range(-1.0, 1.0))
		if normal.length_squared() < 0.01:
			continue
		normal = normal.normalized()
		var reach := 0.0
		for point in points:
			reach = maxf(reach, point.dot(normal))
		var plane := reach * fracture_rng.randf_range(0.80, 0.93)
		for index in range(points.size()):
			var depth: float = points[index].dot(normal) - plane
			if depth > 0.0:
				# Shave, do not shear: a full projection from three sides leaves a
				# blade, which reads as a shard of glass rather than as stone.
				points[index] -= normal * depth * 0.85
	# Normalise the footprint to a 1 m half-extent (2 m across), so callers can
	# size a rock in metres of half-width instead of in mesh units.
	var half_x := 0.0
	var half_z := 0.0
	for index in range(points.size()):
		half_x = maxf(half_x, absf(points[index].x))
		half_z = maxf(half_z, absf(points[index].z))
	var unit := 1.0 / maxf(maxf(half_x, half_z), 1e-3)
	for index in range(points.size()):
		points[index] = points[index] * unit
	low = INF
	high = -INF
	for index in range(points.size()):
		low = minf(low, points[index].y)
		high = maxf(high, points[index].y)
	# Smooth normals, weighted by face area: the silhouette stays broken and
	# irregular while the surface reads as weathered stone rather than as a
	# polygon soup. Flat shading is what makes a rock look machine-cut.
	var normals: Array = []
	normals.resize(points.size())
	normals.fill(Vector3.ZERO)
	for j in range(lats - 1):
		for i in range(lons):
			var next := (i + 1) % lons
			var a := points[j * lons + i]
			var b := points[j * lons + next]
			var c := points[(j + 1) * lons + next]
			var d := points[(j + 1) * lons + i]
			_accumulate(normals, j * lons + i, (b - a).cross(c - a))
			_accumulate(normals, j * lons + next, (b - a).cross(c - a))
			_accumulate(normals, (j + 1) * lons + next, (b - a).cross(c - a))
			_accumulate(normals, j * lons + i, (c - a).cross(d - a))
			_accumulate(normals, (j + 1) * lons + next, (c - a).cross(d - a))
			_accumulate(normals, (j + 1) * lons + i, (c - a).cross(d - a))
	for index in range(normals.size()):
		var normal: Vector3 = normals[index]
		normals[index] = normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(lats - 1):
		for i in range(lons):
			var next := (i + 1) % lons
			_triangle(tool,
				points[j * lons + i], normals[j * lons + i],
				points[j * lons + next], normals[j * lons + next],
				points[(j + 1) * lons + next], normals[(j + 1) * lons + next])
			_triangle(tool,
				points[j * lons + i], normals[j * lons + i],
				points[(j + 1) * lons + next], normals[(j + 1) * lons + next],
				points[(j + 1) * lons + i], normals[(j + 1) * lons + i])
	return tool.commit()


## Adds `weight` (a face normal scaled by area) to one of the grid normals.
## `Array` is a reference type, so the accumulation survives the call.
static func _accumulate(normals: Array, index: int, weight: Vector3) -> void:
	normals[index] = (normals[index] as Vector3) + weight


## One triangle carrying its corner normals. The lat-long parameterisation is
## wound outward by construction, so no per-triangle flip is applied: flipping
## against the body centre, as a naive builder does, turns every concave fold
## inside out and lights the rock like a crumpled shell.
static func _triangle(tool: SurfaceTool, a: Vector3, na: Vector3, b: Vector3, nb: Vector3,
		c: Vector3, nc: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-12:
		return
	tool.set_normal(na)
	tool.add_vertex(a)
	tool.set_normal(nb)
	tool.add_vertex(b)
	tool.set_normal(nc)
	tool.add_vertex(c)


## Trilinear value noise in [0, 1].
static func _noise3(point: Vector3, seed_value: int) -> float:
	var ix := floori(point.x)
	var iy := floori(point.y)
	var iz := floori(point.z)
	var fx := point.x - float(ix)
	var fy := point.y - float(iy)
	var fz := point.z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var c000 := _hash(ix, iy, iz, seed_value)
	var c100 := _hash(ix + 1, iy, iz, seed_value)
	var c010 := _hash(ix, iy + 1, iz, seed_value)
	var c110 := _hash(ix + 1, iy + 1, iz, seed_value)
	var c001 := _hash(ix, iy, iz + 1, seed_value)
	var c101 := _hash(ix + 1, iy, iz + 1, seed_value)
	var c011 := _hash(ix, iy + 1, iz + 1, seed_value)
	var c111 := _hash(ix + 1, iy + 1, iz + 1, seed_value)
	var near := lerpf(lerpf(c000, c100, fx), lerpf(c010, c110, fx), fy)
	var far := lerpf(lerpf(c001, c101, fx), lerpf(c011, c111, fx), fy)
	return lerpf(near, far, fz)


## Fractal sum of `_noise3`, normalised to [0, 1].
static func _fbm(point: Vector3, octaves: int, seed_value: int) -> float:
	var total := 0.0
	var amplitude := 0.55
	var frequency := 1.0
	var normaliser := 0.0
	for octave in range(maxi(1, octaves)):
		total += _noise3(point * frequency, seed_value + octave * 43) * amplitude
		normaliser += amplitude
		amplitude *= 0.52
		frequency *= 2.17
	return total / maxf(normaliser, 1e-6)


## Integer hash to [0, 1]. Masked to 32 bits so it is identical on every
## platform Godot runs on.
static func _hash(x: int, y: int, z: int, seed_value: int) -> float:
	var value: int = (x * 374761393 + y * 668265263 + z * 1274126177 + seed_value * 2147483647) & 0xFFFFFFFF
	value = (value ^ (value >> 13)) & 0xFFFFFFFF
	value = (value * 1274126177) & 0xFFFFFFFF
	value = (value ^ (value >> 16)) & 0xFFFFFFFF
	return float(value & 0xFFFF) / 65535.0
