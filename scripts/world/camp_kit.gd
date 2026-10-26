class_name CampKit
extends RefCounted
## The Unholy Forest's own camp: shelters bent out of saplings and brush by
## people who never had a tool between them.
##
## Sizes are deliberately small - a shelter is 2-3 m wide and barely taller than
## a ranger crouched - because these are dens a child would build, not buildings.
## Nothing here is plumb: every pole is bent at a kink, every brush bundle lies at
## its own angle, and the roofs are a heap of fistfuls rather than a surface.
##
## Everything is presentation. Props merge into one multi-surface mesh per
## structure and one batch for all the small clutter, so a full camp costs a
## handful of draw calls. Colliders go on the caller's existing solid body.
## Builders are deterministic from their seed.

const Geo = preload("res://scripts/geo.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## How many hanging-charm shapes `add_hanging` can pick from.
const HANGING_VARIANTS := 11

## The two sides of anything mirrored.
const SIDES: Array[float] = [-1.0, 1.0]

static var _mats: Dictionary = {}
static var _prims: Dictionary = {}


# ---------------------------------------------------------------------------
# palette
# ---------------------------------------------------------------------------

## The camp's one material set: sun-bleached driftwood, damp twigs, dry brush,
## scraps of hide, bone, river stone and the ochre they daub on everything.
static func materials() -> Dictionary:
	if not _mats.is_empty():
		return _mats
	var m: Dictionary = {}
	m["drift"] = TextureLibrary.building_material("wood", Color("a89e8a"))
	m["drift_dark"] = TextureLibrary.building_material("wood", Color("857b68"))
	m["twig"] = TextureLibrary.building_material("timber", Color("9a8054"))
	m["twig_dark"] = TextureLibrary.building_material("timber", Color("6f5b40"))
	m["bark"] = TextureLibrary.bark_material_tinted("bark_dead", Color("6f6653"))
	m["thatch"] = TextureLibrary.building_material("thatch", Color("b59a63"))
	m["thatch_dark"] = TextureLibrary.building_material("thatch", Color("7f6b45"))
	m["hide"] = TextureLibrary.building_material("hide", Color("a8875f"))
	m["hide_dark"] = TextureLibrary.building_material("hide", Color("7c6144"))
	m["bone"] = TextureLibrary.building_material("bone", Color("b6ab8d"))
	m["stone"] = TextureLibrary.granite_material(Color("8a8070"))
	m["ash"] = Geo.material(Color("2f2925"), 0.0, 0.96)
	m["char"] = Geo.material(Color("171412"), 0.0, 0.98)
	m["clay"] = Geo.material(Color("7a5236"), 0.02, 0.95)
	m["clay_dark"] = Geo.material(Color("5c3b28"), 0.02, 0.95)
	m["rag"] = Geo.material(Color("332d26"), 0.0, 0.95)
	m["ochre"] = Geo.material(Color("59241a"), 0.02, 0.94)
	m["moss"] = Geo.material(Color("455536"), 0.0, 0.95)
	m["feather"] = Geo.material(Color("3d352c"), 0.0, 0.85)
	m["ember"] = _glow(Color("ff8a3c"), Color("ff5a12"), 1.8)
	m["fire_core"] = _glow(Color("ffd08a"), Color("ff8a2a"), 2.2)
	m["flame"] = TextureLibrary.flame_material()
	_mats = m
	return m


static func _glow(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material


# ---------------------------------------------------------------------------
# primitive cache
# ---------------------------------------------------------------------------

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	var cached: Mesh = _prims.get(key)
	if cached != null:
		return cached as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = size
	_prims[key] = mesh
	return mesh


static func _cyl_mesh(bottom: float, top: float, height: float, sides: int) -> CylinderMesh:
	var key := "c%.3f,%.3f,%.3f,%d" % [bottom, top, height, sides]
	var cached: Mesh = _prims.get(key)
	if cached != null:
		return cached as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = maxi(3, sides)
	mesh.rings = 1
	_prims[key] = mesh
	return mesh


static func _sphere_mesh(radius: float, segments: int, rings: int) -> SphereMesh:
	var key := "s%.3f,%d,%d" % [radius, segments, rings]
	var cached: Mesh = _prims.get(key)
	if cached != null:
		return cached as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = maxi(4, segments)
	mesh.rings = maxi(2, rings)
	_prims[key] = mesh
	return mesh


static func _ring_mesh(inner: float, outer: float, rings: int, segments: int) -> TorusMesh:
	var key := "t%.3f,%.3f,%d,%d" % [inner, outer, rings, segments]
	var cached: Mesh = _prims.get(key)
	if cached != null:
		return cached as TorusMesh
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = maxi(3, rings)
	mesh.ring_segments = maxi(3, segments)
	_prims[key] = mesh
	return mesh


## A card in the XY plane facing +Z: the flame billboards.
static func _quad_mesh(size: Vector2) -> PlaneMesh:
	var key := "q%.3f,%.3f" % [size.x, size.y]
	var cached: Mesh = _prims.get(key)
	if cached != null:
		return cached as PlaneMesh
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Z
	_prims[key] = mesh
	return mesh


# ---------------------------------------------------------------------------
# merged mesh builder
# ---------------------------------------------------------------------------

## One merged, multi-surface mesh. Add primitives in any `push`ed group; `commit`
## produces a single MeshInstance3D with one surface per material.
class Merged:
	var base := Transform3D.IDENTITY
	var group := Transform3D.IDENTITY
	var surfaces: Dictionary = {}

	func push(xform: Transform3D) -> Transform3D:
		var previous := group
		group = group * xform
		return previous

	func add(mesh: Mesh, local: Transform3D, material: Material) -> void:
		var st: SurfaceTool = surfaces.get(material)
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[material] = st
		st.append_from(mesh, 0, base * group * local)

	func is_empty() -> bool:
		return surfaces.is_empty()

	func commit(host: Node3D, label: String, cast_shadow: bool = true) -> MeshInstance3D:
		if surfaces.is_empty():
			return null
		var mesh := ArrayMesh.new()
		var index := 0
		for material in surfaces.keys():
			(surfaces[material] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(index, material)
			index += 1
		var node := MeshInstance3D.new()
		node.name = label
		node.mesh = mesh
		node.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		host.add_child(node)
		return node


static func _xf(at: Vector3, yaw: float = 0.0, pitch: float = 0.0, roll: float = 0.0, s: float = 1.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)).scaled(Vector3.ONE * s), at)


# --- primitive helpers -----------------------------------------------------

static func add_box(m: Merged, size: Vector3, at: Vector3, material: Material,
		yaw: float = 0.0, pitch: float = 0.0, roll: float = 0.0) -> void:
	m.add(_box_mesh(size), _xf(at, yaw, pitch, roll), material)


## A tapered rod from `a` to `b`; `tip` is the radius at `b`.
static func add_beam(m: Merged, a: Vector3, b: Vector3, radius: float, material: Material,
		sides: int = 5, tip: float = -1.0) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.0005:
		return
	var up := span / length
	var hint := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := up.cross(hint).normalized()
	var forward := side.cross(up).normalized()
	m.add(_cyl_mesh(radius, radius if tip < 0.0 else tip, length, sides),
		Transform3D(Basis(side, up, forward), (a + b) * 0.5), material)


static func add_ball(m: Merged, radius: float, at: Vector3, material: Material,
		squash: Vector3 = Vector3.ONE, segments: int = 8, rings: int = 5) -> void:
	m.add(_sphere_mesh(radius, segments, rings), _xf(at).scaled_local(squash), material)


static func add_ring(m: Merged, at: Vector3, yaw: float, inner: float, outer: float,
		material: Material, pitch: float = 0.0, rings: int = 12, segments: int = 4) -> void:
	m.add(_ring_mesh(inner, outer, rings, segments), _xf(at, yaw, pitch), material)


# --- collision helpers -----------------------------------------------------

static func add_collider(solids: StaticBody3D, base: Transform3D, size: Vector3, at: Vector3,
		yaw: float = 0.0, pitch: float = 0.0, roll: float = 0.0) -> void:
	if solids == null:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = base * _xf(at, yaw, pitch, roll)
	solids.add_child(collision)


# ---------------------------------------------------------------------------
# bent wood and brush
# ---------------------------------------------------------------------------

## A sapling bent into two kinked segments, the way a child bends one over.
static func _bent_pole(m: Merged, mats: Dictionary, foot: Vector3, top: Vector3,
		rng: RandomNumberGenerator, radius: float, material: Material) -> void:
	var mid := foot.lerp(top, rng.randf_range(0.42, 0.64))
	mid += Vector3(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.08, 0.08),
		rng.randf_range(-0.14, 0.14))
	add_beam(m, foot, mid, radius, material, 4, radius * 0.72)
	add_beam(m, mid, top, radius * 0.66, material, 4, radius * 0.20)


## A heap of loose twigs thrown over the frame: nothing but thin sticks, laid in
## the general direction the builder was working. No straw surfaces, no planks.
static func _twig_pile(m: Merged, mats: Dictionary, centre: Vector3, along: Vector3,
		spread: float, count: int, rng: RandomNumberGenerator) -> void:
	var direction := along.normalized()
	# spread sideways along the surface, so every stick starts on the frame and
	# hangs down the slope instead of floating in the air beside it
	var lateral := Vector3(-direction.z, 0.0, direction.x)
	if lateral.length_squared() < 0.01:
		lateral = Vector3.RIGHT
	lateral = lateral.normalized()
	for i in range(count):
		var start := centre + lateral * rng.randf_range(-spread, spread) 			+ Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.05),
				rng.randf_range(-0.04, 0.04))
		var aim := direction.rotated(Vector3.UP, rng.randf_range(-0.12, 0.12))
		var length := rng.randf_range(0.45, 1.15)
		var end := start + aim * length + Vector3(0.0, rng.randf_range(-0.20, 0.02), 0.0)
		add_beam(m, start, end, rng.randf_range(0.015, 0.032),
			mats["twig_dark"] if i % 3 else mats["twig"], 4, 0.008)


## A clump of dry straw: three thin tufts at crossed angles, never one flat slab.
static func _straw_tuft(m: Merged, mats: Dictionary, at: Vector3, rng: RandomNumberGenerator) -> void:
	for i in range(3):
		add_box(m, Vector3(rng.randf_range(0.14, 0.24), rng.randf_range(0.03, 0.06),
			rng.randf_range(0.14, 0.26)),
			at + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, 0.05),
				rng.randf_range(-0.12, 0.12)),
			mats["thatch"] if i else mats["thatch_dark"], rng.randf_range(0.0, TAU),
			rng.randf_range(-0.30, 0.30), rng.randf_range(-0.30, 0.30))


## A loose twig lashed across two points at a random diagonal.
static func _cross_twig(m: Merged, mats: Dictionary, a: Vector3, b: Vector3,
		rng: RandomNumberGenerator) -> void:
	add_beam(m, a + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.10, 0.10),
		rng.randf_range(-0.12, 0.12)),
		b + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.10, 0.10),
			rng.randf_range(-0.12, 0.12)),
		rng.randf_range(0.012, 0.024), mats["twig_dark"], 3)


static func _rope(m: Merged, mats: Dictionary, from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> void:
	var mid := from.lerp(to, 0.5) + Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05))
	add_beam(m, from, mid, 0.013, mats["rag"], 3)
	add_beam(m, mid, to, 0.013, mats["rag"], 3)
	add_ball(m, 0.024, from, mats["rag"], Vector3.ONE, 5, 3)
	add_ball(m, 0.026, mid, mats["rag"], Vector3.ONE, 5, 3)


# ---------------------------------------------------------------------------
# shared motifs
# ---------------------------------------------------------------------------

## An animal skull: domed cranium, brow, long tapered muzzle, sunken eye pits and
## jaw. The muzzle points down -Z before `yaw` is applied.
static func add_skull(m: Merged, mats: Dictionary, at: Vector3, yaw: float = 0.0,
		s: float = 1.0, horns: bool = false) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	add_ball(m, 0.135, Vector3(0.0, 0.005, 0.02), mats["bone"], Vector3(0.90, 0.84, 1.00), 10, 6)
	add_box(m, Vector3(0.235, 0.105, 0.14), Vector3(0.0, -0.005, -0.025), mats["bone"])
	add_box(m, Vector3(0.205, 0.05, 0.10), Vector3(0.0, 0.06, -0.10), mats["bone"], 0.0, 0.20)
	add_box(m, Vector3(0.115, 0.085, 0.20), Vector3(0.0, -0.045, -0.20), mats["bone"], 0.0, 0.10)
	add_box(m, Vector3(0.085, 0.065, 0.11), Vector3(0.0, -0.058, -0.335), mats["bone"], 0.0, 0.04)
	add_ball(m, 0.046, Vector3(0.062, 0.012, -0.118), mats["ash"], Vector3(1.0, 0.9, 0.45), 7, 4)
	add_ball(m, 0.046, Vector3(-0.062, 0.012, -0.118), mats["ash"], Vector3(1.0, 0.9, 0.45), 7, 4)
	add_box(m, Vector3(0.038, 0.05, 0.022), Vector3(0.0, -0.012, -0.30), mats["ash"])
	add_box(m, Vector3(0.10, 0.045, 0.23), Vector3(0.0, -0.115, -0.17), mats["bone"], 0.0, -0.05)
	for i in range(4):
		add_box(m, Vector3(0.016, 0.042, 0.016), Vector3(-0.036 + float(i) * 0.024, -0.085, -0.275),
			mats["bone"])
	if horns:
		for side in SIDES:
			var root := Vector3(side * 0.10, 0.075, 0.01)
			var mid := root + Vector3(side * 0.085, 0.13, -0.03)
			var tip := mid + Vector3(side * 0.05, 0.16, -0.07)
			add_beam(m, root, mid, 0.034, mats["bone"], 4, 0.022)
			add_beam(m, mid, tip, 0.022, mats["bone"], 4, 0.008)
	m.group = saved


## A branched antler lashed to a shelter or a post.
static func add_antler(m: Merged, mats: Dictionary, at: Vector3, yaw: float, s: float = 1.0) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	add_beam(m, Vector3.ZERO, Vector3(0.10, 0.42, -0.05), 0.036, mats["bone"], 5, 0.024)
	add_beam(m, Vector3(0.10, 0.42, -0.05), Vector3(0.30, 0.74, -0.10), 0.024, mats["bone"], 4, 0.011)
	add_beam(m, Vector3(0.10, 0.42, -0.05), Vector3(0.05, 0.63, 0.06), 0.018, mats["bone"], 4, 0.008)
	add_beam(m, Vector3(0.22, 0.62, -0.08), Vector3(0.40, 0.80, 0.02), 0.014, mats["bone"], 4, 0.006)
	m.group = saved


## A crude idol: a bundle of sticks stood on end, tied with cord, skull on top and
## two twig arms. No tools, no joinery - just lashed sticks.
static func add_idol(m: Merged, mats: Dictionary, at: Vector3, yaw: float, s: float = 1.0,
		seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	var height := rng.randf_range(0.75, 1.15)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + rng.randf_range(-0.3, 0.3)
		var foot := Vector3(cos(a) * 0.05, -0.05, sin(a) * 0.05)
		_bent_pole(m, mats, foot, Vector3(cos(a) * 0.05, height, sin(a) * 0.05), rng,
			rng.randf_range(0.022, 0.032), mats["twig"])
	for i in range(2):
		add_ring(m, Vector3(0.0, height * (0.35 + float(i) * 0.3), 0.0), rng.randf_range(0.0, TAU),
			0.075, 0.10, mats["rag"], 0.0, 8, 3)
	for side in SIDES:
		add_beam(m, Vector3(side * 0.03, height * 0.78, 0.0),
			Vector3(side * 0.30, height * 0.95, -0.06), 0.016, mats["twig"], 3, 0.008)
	add_skull(m, mats, Vector3(0.0, height + 0.09, 0.0), rng.randf_range(0.0, TAU), 0.45, seed % 3 == 0)
	add_box(m, Vector3(0.05, 0.09, 0.02), Vector3(0.06, height * 0.55, -0.075), mats["ochre"])
	m.group = saved


# ---------------------------------------------------------------------------
# hanging charms
# ---------------------------------------------------------------------------

## One hanging charm tied at `top` (a branch, a shelter pole, a lintel) and
## dropping down. Eight shapes: bone chime, skull string, pot string, antler
## charm, wicker cage, rag fetish, rib bundle and a carved rune board. Returns
## the drop length so the caller can hang another below it.
static func add_hanging(m: Merged, mats: Dictionary, top: Vector3, yaw: float, seed: int,
		scale_at: float = 1.0) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var variant := posmod(seed, HANGING_VARIANTS)
	var s := scale_at * rng.randf_range(0.85, 1.15)
	var saved := m.push(_xf(top, yaw, 0.0, 0.0, s))
	var rope_len := rng.randf_range(0.35, 1.10)
	var sway := rng.randf_range(-0.14, 0.14)
	var knot := Vector3(sway, -rope_len, sway * 0.7)
	_rope(m, mats, Vector3.ZERO, knot, rng)
	match variant:
		0:
			_bone_chime(m, mats, knot, rng)
		1:
			_skull_string(m, mats, knot, rng)
		2:
			_pot_string(m, mats, knot, rng)
		3:
			add_antler(m, mats, knot, rng.randf_range(0.0, TAU), 0.8)
			add_beam(m, knot, knot + Vector3(0.20, -0.26, 0.04), 0.010, mats["rag"], 3)
			for i in range(3):
				add_ball(m, 0.020, knot + Vector3(-0.10 + float(i) * 0.10, -0.18 - float(i) * 0.06, 0.0),
					mats["bone"], Vector3.ONE, 4, 3)
		4:
			_wicker_cage(m, mats, knot, rng)
		5:
			_rag_fetish(m, mats, knot, rng)
		6:
			_rib_bundle(m, mats, knot, rng)
		7:
			_rune_board(m, mats, knot, rng)
		8:
			_cloth_strips(m, mats, knot, rng)
		9:
			_bone_mobile(m, mats, knot, rng)
		_:
			_mask_chime(m, mats, knot, rng)
	m.group = saved
	return rope_len


static func _bone_chime(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	add_ring(m, knot, 0.0, 0.055, 0.08, mats["twig_dark"])
	for i in range(5):
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var at := knot + Vector3(cos(a) * 0.07, 0.0, sin(a) * 0.07)
		var drop := rng.randf_range(0.10, 0.32)
		var low := at + Vector3(0.0, -drop, 0.0)
		add_beam(m, at, low, 0.006, mats["rag"], 3)
		add_ball(m, 0.024, low, mats["bone"], Vector3.ONE, 5, 3)
		var tail := low + Vector3(rng.randf_range(-0.04, 0.04), -rng.randf_range(0.12, 0.26),
			rng.randf_range(-0.04, 0.04))
		add_beam(m, low, tail, 0.022, mats["bone"], 4, 0.014)
		add_ball(m, 0.026, tail, mats["bone"], Vector3.ONE, 5, 3)


static func _skull_string(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var at := knot
	for i in range(3):
		var size_at := 0.60 - float(i) * 0.12
		add_skull(m, mats, at, rng.randf_range(0.0, TAU), size_at, i == 0)
		var next := at + Vector3(rng.randf_range(-0.06, 0.06), -0.34, rng.randf_range(-0.06, 0.06))
		_rope(m, mats, at + Vector3(0.0, -0.09, 0.0), next, rng)
		at = next


static func _pot_string(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var at := knot
	for i in range(4):
		var r := 0.12 - float(i) * 0.013
		add_ball(m, r, at, mats["clay"], Vector3(1.0, 0.8, 1.0), 9, 5)
		add_ring(m, at + Vector3(0.0, r * 0.72, 0.0), 0.0, r * 0.5, r * 0.72, mats["clay_dark"], 0.0, 9, 3)
		add_beam(m, at + Vector3(0.0, r * 0.9, 0.0), at + Vector3(0.0, 0.14, 0.0), 0.009, mats["rag"], 3)
		at += Vector3(rng.randf_range(-0.04, 0.04), -0.36, rng.randf_range(-0.04, 0.04))
		_rope(m, mats, at + Vector3(0.0, 0.36, 0.0), at, rng)


static func _wicker_cage(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var top := knot + Vector3(0.0, -0.08, 0.0)
	var floor_at := knot + Vector3(0.0, -0.48, 0.0)
	add_ring(m, top, 0.0, 0.13, 0.17, mats["twig_dark"], 0.0, 10, 3)
	add_ring(m, floor_at, 0.0, 0.19, 0.24, mats["twig_dark"], 0.0, 12, 3)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		add_beam(m, top + Vector3(cos(a) * 0.15, 0.0, sin(a) * 0.15),
			floor_at + Vector3(cos(a) * 0.22, 0.02, sin(a) * 0.22), 0.011, mats["twig_dark"], 3)
	add_skull(m, mats, knot + Vector3(rng.randf_range(-0.02, 0.02), -0.34, 0.0),
		rng.randf_range(0.0, TAU), 0.40, false)


static func _rag_fetish(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	add_ring(m, knot, 0.0, 0.05, 0.075, mats["twig_dark"])
	for i in range(5):
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.2, 0.2)
		var at := knot + Vector3(cos(a) * 0.06, -0.02, sin(a) * 0.06)
		var length := rng.randf_range(0.18, 0.42)
		add_box(m, Vector3(0.05, length, 0.012), at + Vector3(0.0, -length * 0.5, 0.0),
			mats["rag"], a, 0.0, rng.randf_range(-0.2, 0.2))
		if i % 2 == 0:
			add_box(m, Vector3(0.04, 0.14, 0.008), at + Vector3(0.0, -length - 0.05, 0.0),
				mats["feather"], a, 0.0, rng.randf_range(-0.4, 0.4))


static func _rib_bundle(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var spine_a := knot + Vector3(0.0, -0.12, 0.0)
	var spine_b := knot + Vector3(0.05, -0.56, 0.03)
	add_beam(m, spine_a, spine_b, 0.030, mats["bone"], 5, 0.022)
	for i in range(5):
		var root := spine_a.lerp(spine_b, 0.12 + float(i) * 0.18)
		var side := -1.0 if i % 2 == 0 else 1.0
		var bend := root + Vector3(side * 0.11, -0.04, rng.randf_range(-0.05, 0.05))
		var tip := bend + Vector3(side * 0.06, -0.19, rng.randf_range(-0.04, 0.04))
		add_beam(m, root, bend, 0.014, mats["bone"], 3, 0.011)
		add_beam(m, bend, tip, 0.011, mats["bone"], 3, 0.006)
	add_box(m, Vector3(0.18, 0.26, 0.02), spine_b + Vector3(0.0, 0.08, 0.05), mats["hide_dark"], 0.2)


## A bound bundle of cloth and feathers, the wardens' ordinary charm.
static func _cloth_strips(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	add_beam(m, knot, knot + Vector3(0.0, -0.10, 0.0), 0.012, mats["rag"], 3)
	var hub := knot + Vector3(0.0, -0.12, 0.0)
	add_ball(m, 0.045, hub, mats["rag"], Vector3.ONE, 5, 3)
	for i in range(8):
		var a := TAU * float(i) / 8.0 + rng.randf_range(-0.2, 0.2)
		var length := rng.randf_range(0.20, 0.55)
		var out := Vector3(cos(a) * 0.05, 0.0, sin(a) * 0.05)
		add_box(m, Vector3(0.035, length, 0.012), hub + out + Vector3(0.0, -length * 0.5, 0.0),
			mats["rag"] if i % 2 else mats["feather"], a, 0.0, rng.randf_range(-0.25, 0.25))
		if i % 3 == 0:
			add_ball(m, 0.018, hub + out + Vector3(0.0, -length - 0.03, 0.0), mats["bone"],
				Vector3.ONE, 4, 3)


## A crossbar of bones on strings, swinging at different lengths.
static func _bone_mobile(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var bar := knot + Vector3(0.0, -0.16, 0.0)
	add_beam(m, bar + Vector3(-0.22, 0.0, 0.0), bar + Vector3(0.22, 0.0, 0.0), 0.014,
		mats["twig_dark"], 3)
	for i in range(3):
		var start := bar + Vector3(-0.18 + float(i) * 0.18, 0.0, 0.0)
		var drop := rng.randf_range(0.18, 0.42)
		var low := start + Vector3(0.0, -drop, 0.0)
		add_beam(m, start, low, 0.007, mats["rag"], 3)
		add_beam(m, low, low + Vector3(rng.randf_range(-0.04, 0.04), -0.20, rng.randf_range(-0.04, 0.04)),
			0.021, mats["bone"], 4, 0.013)
		add_ball(m, 0.026, low, mats["bone"], Vector3.ONE, 5, 3)
	add_skull(m, mats, bar + Vector3(0.26, -0.30, 0.0), rng.randf_range(0.0, TAU), 0.38, false)


## Two little masks and a bone clapper, strung together.
static func _mask_chime(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	add_beam(m, knot, knot + Vector3(0.0, -0.14, 0.0), 0.010, mats["rag"], 3)
	for i in range(2):
		var at := knot + Vector3(-0.10 + float(i) * 0.20, -0.30 - float(i) * 0.16, 0.0)
		add_box(m, Vector3(0.16, 0.20, 0.05), at, mats["drift"], rng.randf_range(-0.3, 0.3), 0.0,
			rng.randf_range(-0.15, 0.15))
		add_ball(m, 0.022, at + Vector3(0.04, 0.03, -0.04), mats["ash"], Vector3(1.0, 0.7, 0.4), 4, 3)
		add_ball(m, 0.022, at + Vector3(-0.04, 0.03, -0.04), mats["ash"], Vector3(1.0, 0.7, 0.4), 4, 3)
		add_box(m, Vector3(0.07, 0.02, 0.02), at + Vector3(0.0, -0.05, -0.04), mats["ochre"])
		add_beam(m, knot + Vector3(-0.10 + float(i) * 0.20, -0.14, 0.0), at, 0.007, mats["rag"], 3)
	add_beam(m, knot + Vector3(0.0, -0.12, 0.0), knot + Vector3(0.02, -0.52, 0.0), 0.016,
		mats["bone"], 4, 0.010)


static func _rune_board(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var board := knot + Vector3(0.0, -0.26, 0.0)
	add_box(m, Vector3(0.26, 0.36, 0.030), board, mats["drift_dark"], 0.0, 0.0, 0.08)
	for i in range(3):
		add_box(m, Vector3(0.04, 0.11, 0.010), board + Vector3(-0.06 + float(i) * 0.06, 0.02, -0.020),
			mats["ochre"], 0.0, 0.0, rng.randf_range(-0.5, 0.5))
	add_ring(m, board + Vector3(0.0, -0.24, 0.0), 0.0, 0.04, 0.06, mats["twig_dark"], PI * 0.5, 8, 3)



# ---------------------------------------------------------------------------
# witch work: the props that make the woods wrong to walk through
# ---------------------------------------------------------------------------

## A clootie tree: a dead pole with cloth strips, feathers and charms tied all the
## way up - the wardens' habit of tying their business to a branch.
static func rag_tree(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 51) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var height := rng.randf_range(3.1, 4.5)
	add_beam(m, Vector3(0.0, -0.25, 0.0), Vector3(0.08, height, 0.05), 0.095, mats["bark"], 5, 0.045)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + rng.randf_range(-0.45, 0.45)
		var y := height * (0.50 + float(i) * 0.15)
		add_beam(m, Vector3(0.03, y, 0.0),
			Vector3(cos(a) * rng.randf_range(0.40, 0.85), y + rng.randf_range(0.45, 0.95),
				sin(a) * rng.randf_range(0.40, 0.85)), 0.040, mats["bark"], 4, 0.016)
	for i in range(15):
		var y := rng.randf_range(0.45, height - 0.15)
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.06, 0.30)
		var at := Vector3(cos(a) * r, y, sin(a) * r)
		if i % 4 == 3:
			add_hanging(m, mats, at + Vector3(0.0, 0.04, 0.0), a, seed * 31 + i, 0.65)
		else:
			add_box(m, Vector3(rng.randf_range(0.05, 0.10), rng.randf_range(0.22, 0.55), 0.01),
				at + Vector3(0.0, -0.20, 0.0), mats["rag"] if i % 2 else mats["feather"], a, 0.0,
				rng.randf_range(-0.22, 0.22))
	add_skull(m, mats, Vector3(0.0, height + 0.07, 0.0), rng.randf_range(0.0, TAU), 0.55, true)
	add_collider(solids, base, Vector3(0.30, 2.6, 0.30), Vector3(0.0, 1.3, 0.0))
	m.commit(host, "RagTree")


## Two forked sticks, a lashed crossbar and bones hung under it. Marks the trail
## head and the camp's edge.
static func bone_arch(host: Node3D, mats: Dictionary, solids: StaticBody3D,
		half_width: float = 1.5, height: float = 2.3, seed: int = 53) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	for side in SIDES:
		var foot := Vector3(side * half_width, -0.20, rng.randf_range(-0.1, 0.1))
		_bent_pole(m, mats, foot, Vector3(side * (half_width + rng.randf_range(-0.1, 0.18)), height,
			rng.randf_range(-0.12, 0.12)), rng, rng.randf_range(0.055, 0.075), mats["bark"])
		add_ring(m, foot + Vector3(0.0, height * 0.55, 0.0), rng.randf_range(0.0, TAU), 0.09, 0.12,
			mats["rag"], 0.0, 8, 3)
		add_collider(solids, base, Vector3(0.22, height, 0.22), Vector3(side * half_width, height * 0.5, 0.0))
	var sag := Vector3(rng.randf_range(-0.15, 0.15), -rng.randf_range(0.10, 0.26),
		rng.randf_range(-0.08, 0.08))
	add_beam(m, Vector3(-half_width - 0.10, height - 0.08, 0.0),
		Vector3(0.0, height - 0.12, 0.0) + sag, 0.065, mats["bark"], 5, 0.05)
	add_beam(m, Vector3(0.0, height - 0.12, 0.0) + sag,
		Vector3(half_width + 0.10, height - 0.02, 0.02), 0.062, mats["bark"], 5, 0.045)
	for i in range(3):
		add_hanging(m, mats, Vector3(-half_width * 0.55 + float(i) * half_width * 0.55,
			height - 0.16, 0.02), rng.randf_range(0.0, TAU), seed * 19 + i, 0.8)
	add_skull(m, mats, Vector3(0.0, height + 0.02, 0.0), rng.randf_range(0.0, TAU), 0.72, true)
	add_antler(m, mats, Vector3(-half_width * 0.5, height + 0.04, 0.0), 0.4, 0.8)
	add_antler(m, mats, Vector3(half_width * 0.5, height + 0.04, 0.0), PI - 0.4, 0.8)
	m.commit(host, "BoneArch")


## A bound straw figure on a stake: arms out, skull head, ochre smeared on it.
static func straw_doll(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 55) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	var height := rng.randf_range(0.85, 1.25)
	add_beam(m, Vector3(0.0, -0.15, 0.0), Vector3(0.03, height + 0.35, 0.02), 0.028, mats["twig"], 4, 0.018)
	# straw body bound with cord, taller and narrower than a pot
	add_cone(mats, m, 0.20, height * 0.85, Vector3(0.0, height * 0.42, 0.0), rng)
	add_box(m, Vector3(0.26, 0.05, 0.10), Vector3(0.0, height * 0.34, -0.02), mats["drift_dark"])
	for i in range(3):
		add_ring(m, Vector3(0.0, height * (0.30 + float(i) * 0.18), 0.0), rng.randf_range(0.0, TAU),
			0.10, 0.13, mats["rag"], 0.0, 8, 3)
	for side in SIDES:
		add_beam(m, Vector3(side * 0.05, height * 0.62, 0.0),
			Vector3(side * rng.randf_range(0.32, 0.48), height * (0.72 + rng.randf_range(-0.1, 0.1)),
				rng.randf_range(-0.10, 0.06)), 0.022, mats["twig"], 3, 0.010)
	add_skull(m, mats, Vector3(0.0, height + 0.44, 0.0), rng.randf_range(0.0, TAU), 0.40, seed % 2 == 0)
	add_box(m, Vector3(0.07, 0.11, 0.02), Vector3(0.0, height * 0.55, -0.13), mats["ochre"])
	m.group = saved


## A straw cone for the dolls' bodies (the shared tapered prism helper).
static func add_cone(mats: Dictionary, m: Merged, radius: float, height: float, at: Vector3,
		rng: RandomNumberGenerator) -> void:
	m.add(_cyl_mesh(radius * rng.randf_range(0.85, 1.1), radius * 0.5, height, 6), _xf(at),
		mats["thatch_dark"] if rng.randf() < 0.4 else mats["thatch"])


## A carved mask nailed to a stake, painted and feathered.
static func mask_stake(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 57) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	var height := rng.randf_range(1.05, 1.55)
	_bent_pole(m, mats, Vector3(0.0, -0.15, 0.0), Vector3(rng.randf_range(-0.08, 0.08), height,
		rng.randf_range(-0.08, 0.08)), rng, 0.035, mats["twig"])
	var face := Vector3(0.0, height - 0.08, -0.02)
	add_box(m, Vector3(0.30, 0.38, 0.09), face, mats["drift"], rng.randf_range(-0.2, 0.2), 0.0,
		rng.randf_range(-0.12, 0.12))
	add_ball(m, 0.045, face + Vector3(0.075, 0.05, -0.06), mats["ash"], Vector3(1.0, 0.7, 0.4), 6, 4)
	add_ball(m, 0.045, face + Vector3(-0.075, 0.05, -0.06), mats["ash"], Vector3(1.0, 0.7, 0.4), 6, 4)
	add_box(m, Vector3(0.13, 0.035, 0.03), face + Vector3(0.0, -0.08, -0.06), mats["ochre"])
	add_box(m, Vector3(0.05, 0.16, 0.03), face + Vector3(0.0, 0.11, -0.06), mats["ochre"])
	for i in range(3):
		add_box(m, Vector3(0.03, 0.12, 0.02), face + Vector3(-0.12 + float(i) * 0.12, 0.22, -0.02),
			mats["feather"], 0.0, 0.0, rng.randf_range(-0.4, 0.4))
	m.group = saved


## A ring of skull-topped sticks pressed into the ground.
static func skull_ring(m: Merged, mats: Dictionary, at: Vector3, radius: float = 1.6,
		count: int = 7, seed: int = 59) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, 0.0, 0.0, 0.0, 1.0))
	for i in range(count):
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var r := radius + rng.randf_range(-0.2, 0.2)
		var foot := Vector3(cos(a) * r, -0.12, sin(a) * r)
		var height := rng.randf_range(0.55, 0.95)
		_bent_pole(m, mats, foot, foot + Vector3(rng.randf_range(-0.10, 0.10), height,
			rng.randf_range(-0.10, 0.10)), rng, rng.randf_range(0.020, 0.032), mats["twig"])
		add_skull(m, mats, foot + Vector3(0.0, height + 0.05, 0.0), -a + PI, rng.randf_range(0.42, 0.60),
			i % 3 == 0)
	# a painted arc of dashes, not a full hoop: a mark scratched in the dirt
	for i in range(5):
		var a := -0.6 + float(i) * 0.30
		var dash := Vector3(cos(a) * (radius - 0.05), 0.02, sin(a) * (radius - 0.05))
		add_box(m, Vector3(0.26, 0.02, 0.06), dash, mats["ochre"], a, 0.0, 0.0)
	m.group = saved


## A woven effigy, taller than a person: straw body, twig limbs, antlered skull,
## lashed to a stake so it keeps standing.
static func wicker_effigy(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 61) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var height := rng.randf_range(2.0, 2.5)
	add_beam(m, Vector3(0.0, -0.2, 0.0), Vector3(0.04, height, 0.02), 0.06, mats["twig"], 5, 0.04)
	add_cone(mats, m, 0.30, height * 0.55, Vector3(0.0, height * 0.45, 0.0), rng)
	for i in range(4):
		add_ring(m, Vector3(0.0, height * (0.22 + float(i) * 0.17), 0.0), rng.randf_range(0.0, TAU),
			0.22, 0.27, mats["rag"], 0.0, 10, 3)
	for side in SIDES:
		_bent_pole(m, mats, Vector3(side * 0.14, height * 0.66, 0.0),
			Vector3(side * rng.randf_range(0.7, 0.95), height * (0.86 + rng.randf_range(-0.06, 0.06)),
				rng.randf_range(-0.2, 0.1)), rng, 0.035, mats["twig"])
	add_skull(m, mats, Vector3(0.0, height + 0.12, 0.0), rng.randf_range(0.0, TAU), 0.70, true)
	add_antler(m, mats, Vector3(-0.10, height + 0.18, 0.02), 0.6, 1.0)
	add_antler(m, mats, Vector3(0.10, height + 0.18, 0.02), PI - 0.6, 1.0)
	for i in range(3):
		add_box(m, Vector3(0.06, 0.20, 0.02), Vector3(0.0, height * (0.35 + float(i) * 0.14), -0.22),
			mats["ochre"], 0.0, 0.0, rng.randf_range(-0.2, 0.2))
	add_collider(solids, base, Vector3(0.5, 1.4, 0.5), Vector3(0.0, 0.7, 0.0))
	m.commit(host, "WickerEffigy")


## A web of cords strung between two forked posts and hung with charms: the
## wardens' string-work.
static func charm_web(host: Node3D, mats: Dictionary, solids: StaticBody3D,
		span: float = 2.6, height: float = 1.9, seed: int = 63) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var posts: Array[Vector3] = []
	for side in SIDES:
		var foot := Vector3(side * span * 0.5, -0.18, rng.randf_range(-0.1, 0.1))
		var top := Vector3(side * span * rng.randf_range(0.10, 0.24), height,
			rng.randf_range(-0.12, 0.12))
		_bent_pole(m, mats, foot, top, rng, 0.045, mats["twig"])
		posts.append(top)
		add_collider(solids, base, Vector3(0.18, height, 0.18), Vector3(foot.x, height * 0.5, 0.0))
	# the cords: a loose cat's cradle between the two tops
	var cords := 5
	for i in range(cords):
		var end := posts[0].lerp(posts[1], float(i + 1) / float(cords + 1))
		end.y += rng.randf_range(-0.18, 0.10)
		add_beam(m, posts[i % 2] + Vector3(0.0, -0.06, 0.0), end, 0.010, mats["rag"], 3)
		add_beam(m, end, posts[1 - i % 2] + Vector3(0.0, -0.10, 0.02), 0.010, mats["rag"], 3)
		if i % 2 == 0:
			add_hanging(m, mats, end, rng.randf_range(0.0, TAU), seed * 13 + i, 0.75)
	m.commit(host, "CharmWeb")


## Painted marks on a standing trunk: ochre and charcoal daubs at head height.
static func trunk_marks(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 65) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	var radius := rng.randf_range(0.22, 0.34)
	for i in range(5):
		var y := rng.randf_range(0.9, 2.3)
		var a := rng.randf_range(-0.8, 0.8)
		var at_mark := Vector3(-sin(a) * radius, y, -cos(a) * radius)
		add_box(m, Vector3(rng.randf_range(0.05, 0.11), rng.randf_range(0.10, 0.26), 0.02),
			at_mark, mats["ochre"] if i % 3 else mats["char"], a, 0.0, rng.randf_range(-0.3, 0.3))
	add_box(m, Vector3(0.14, 0.03, 0.02), Vector3(0.0, rng.randf_range(1.3, 1.8), -radius),
		mats["ochre"], 0.0, 0.0, rng.randf_range(-0.4, 0.4))
	m.group = saved


# ---------------------------------------------------------------------------
# shelters
# ---------------------------------------------------------------------------

## A den of bent saplings and brush: two rows of ribs gathered to a low ridge,
## saplings cross-hatched with twigs, a heap of brush on top and a scrap of hide
## at the opening. `w` is the width, `d` the depth, `h` the ridge height - keep
## them small; this is a child's shelter, not a hut.
static func twig_shelter(host: Node3D, mats: Dictionary, solids: StaticBody3D,
		spec: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var m := Merged.new()
	var base := host.transform
	var width := float(spec.get("width", 2.6))
	var depth := float(spec.get("depth", 2.0))
	var height := float(spec.get("height", 1.55))
	var style := String(spec.get("style", "lean_to"))
	var collapsed := style == "collapsed"
	var ribs := 7 if width < 2.8 else 9
	var back_z := depth * 0.5
	var front_z := -depth * 0.5
	var front_y := height * (0.50 if style == "lean_to" else 0.80)
	var ridge_y := height

	# --- the frame: saplings planted along the back, bent over to a ridge ----
	var ridge_points: Array[Vector3] = []
	for i in range(ribs):
		var t := float(i) / float(ribs - 1)
		var x := lerpf(-width * 0.5, width * 0.5, t) + rng.randf_range(-0.12, 0.12)
		var foot := Vector3(x + rng.randf_range(-0.08, 0.08), -0.16,
			back_z + rng.randf_range(-0.12, 0.16))
		var peak := Vector3(x * 0.66 + rng.randf_range(-0.10, 0.10),
			ridge_y + rng.randf_range(-0.16, 0.10), rng.randf_range(-0.12, 0.12))
		if collapsed and i % 3 == 0:
			peak = Vector3(x * 0.9, ridge_y * 0.62, rng.randf_range(0.0, 0.3))
		_bent_pole(m, mats, foot, peak, rng, rng.randf_range(0.040, 0.058), mats["twig"])
		ridge_points.append(peak)
	# an A-frame gets a second, shorter row on the other side
	if style == "a_frame":
		for i in range(ribs):
			var t := float(i) / float(ribs - 1)
			var x := lerpf(-width * 0.5, width * 0.5, t) + rng.randf_range(-0.12, 0.12)
			var foot := Vector3(x + rng.randf_range(-0.08, 0.08), -0.16,
				front_z + rng.randf_range(-0.16, 0.12))
			var peak := Vector3(x * 0.66 + rng.randf_range(-0.10, 0.10),
				ridge_y + rng.randf_range(-0.16, 0.10), rng.randf_range(-0.12, 0.12))
			_bent_pole(m, mats, foot, peak, rng, rng.randf_range(0.036, 0.052), mats["twig"])
	# a crooked ridge pole along the crown, tied down with cord
	for i in range(ridge_points.size() - 1):
		add_beam(m, ridge_points[i], ridge_points[i + 1], rng.randf_range(0.024, 0.034),
			mats["drift"], 4, 0.020)
	if style == "lean_to":
		var eave_a := Vector3(-width * 0.55, front_y + rng.randf_range(-0.12, 0.12), front_z)
		var eave_b := Vector3(width * 0.55, front_y + rng.randf_range(-0.12, 0.12), front_z)
		add_beam(m, eave_a, eave_b, rng.randf_range(0.022, 0.032), mats["drift"], 4, 0.018)
		# front props, stuck in where the saplings end
		for side in SIDES:
			_bent_pole(m, mats, Vector3(side * width * 0.5, -0.16, front_z + 0.05),
				Vector3(side * width * 0.55, front_y, front_z), rng, 0.030, mats["twig"])
	# --- cross-hatched twigs across the ribs -------------------------------
	for i in range(ribs - 1):
		for k in range(2):
			var a := ridge_points[i].lerp(ridge_points[i + 1], rng.randf_range(0.0, 1.0))
			var b := Vector3(a.x + rng.randf_range(-0.5, 0.5), rng.randf_range(front_y * 0.3, ridge_y * 0.9),
				rng.randf_range(front_z, back_z))
			_cross_twig(m, mats, a, b, rng)
	# side walls: a few leaned twigs so the den closes at the ends
	for side in SIDES:
		for i in range(3):
			var foot := Vector3(side * (width * 0.5 + rng.randf_range(-0.1, 0.1)), -0.14,
				lerpf(back_z, front_z, float(i) / 2.0))
			_bent_pole(m, mats, foot, foot + Vector3(side * rng.randf_range(-0.1, 0.1),
				rng.randf_range(0.6, 1.2), rng.randf_range(-0.3, 0.1)), rng,
				rng.randf_range(0.018, 0.030), mats["twig_dark"])
	# --- the covering: heaps of loose sticks laid down the slope ----------
	var to_front := (Vector3(0.0, front_y, front_z) - Vector3(0.0, ridge_y, 0.0)).normalized()
	var rows := 7 if collapsed else 11
	for i in range(rows):
		var t := (float(i) + 0.5) / float(rows)
		var at := Vector3(lerpf(-width * 0.5, width * 0.5, t) + rng.randf_range(-0.10, 0.10),
			lerpf(ridge_y, front_y, 0.52) + rng.randf_range(0.00, 0.10),
			lerpf(0.0, front_z, 0.52) + rng.randf_range(-0.12, 0.12))
		_twig_pile(m, mats, at, to_front, width / float(rows) * 0.80, 12, rng)
		if i % 3 == 0:
			# a bundle thrown across the others, off the working direction
			_twig_pile(m, mats, at + Vector3(0.0, 0.06, 0.0), Vector3(1.0, 0.0, 0.0),
				width / float(rows) * 0.7, 3, rng)
	# a heap of dry stuff thrown over the crown
	for i in range(3):
		_straw_tuft(m, mats, Vector3(lerpf(-width * 0.4, width * 0.4, float(i) / 2.0) +
			rng.randf_range(-0.15, 0.15), ridge_y * rng.randf_range(0.82, 0.94),
			rng.randf_range(-0.25, 0.25)), rng)
		_straw_tuft(m, mats, Vector3(rng.randf_range(-width * 0.45, width * 0.45),
			lerpf(ridge_y, front_y, 0.45) + 0.06, lerpf(0.0, front_z, 0.45) +
			rng.randf_range(-0.2, 0.2)), rng)
	# the back is matted with upright twigs, so the den closes
	for i in range(12):
		var x := rng.randf_range(-width * 0.55, width * 0.55)
		_twig_pile(m, mats, Vector3(x, 0.05, back_z + rng.randf_range(-0.16, 0.10)),
			Vector3.UP, 0.12, 3, rng)
	# straw dragged in for bedding, clumps at the mouth
	for i in range(3):
		_straw_tuft(m, mats, Vector3(rng.randf_range(-width * 0.30, width * 0.30), 0.03,
			rng.randf_range(-0.25, 0.35)), rng)
	for i in range(2):
		_straw_tuft(m, mats, Vector3(rng.randf_range(-width * 0.5, width * 0.5), 0.02,
			front_z + rng.randf_range(-0.05, 0.30)), rng)
	# --- the opening: a hide scrap on one side, an antler on the other -----
	var flap_side := -1.0 if rng.randf() < 0.5 else 1.0
	for i in range(2):
		add_box(m, Vector3(rng.randf_range(0.26, 0.40), rng.randf_range(0.35, 0.60), 0.02),
			Vector3(flap_side * (width * 0.3 + float(i) * 0.16), front_y * rng.randf_range(0.62, 0.82),
				front_z - 0.05), mats["hide"] if i == 0 else mats["hide_dark"],
			rng.randf_range(-0.20, 0.20), 0.0, rng.randf_range(-0.14, 0.14))
	_rope(m, mats, Vector3(flap_side * width * 0.34, front_y + 0.04, front_z - 0.03),
		Vector3(flap_side * width * 0.34, front_y * 0.86, front_z - 0.05), rng)
	add_antler(m, mats, Vector3(-flap_side * width * 0.42, front_y + 0.10, front_z + 0.02),
		rng.randf_range(0.0, TAU), 0.7)
	# a couple of stones and a brush heap at the mouth
	for i in range(3):
		add_ball(m, rng.randf_range(0.09, 0.16),
			Vector3(rng.randf_range(-width * 0.6, width * 0.6), 0.05, front_z + rng.randf_range(-0.2, 0.2)),
			mats["stone"], Vector3(1.0, 0.6, 1.0), 6, 4)
	# --- collision: the back and the two ends only, the mouth stays open ---
	add_collider(solids, base, Vector3(width, height, 0.30), Vector3(0.0, height * 0.5, back_z))
	for side in SIDES:
		add_collider(solids, base, Vector3(0.26, height * 0.7, depth * 0.7),
			Vector3(side * width * 0.5, height * 0.35, 0.0))
	m.commit(host, String(spec.get("name", "TwigShelter")))


## The camp fire: a ring of river stones, a bed of ash, three charred sticks and
## a small flame. No tripod, no benches - somebody sat on the ground here.
static func fire_ring(host: Node3D, mats: Dictionary, seed: int = 3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var radius := 0.62
	add_cyl_disc(m, radius, 0.05, Vector3(0.0, 0.025, 0.0), mats["ash"], 14)
	for i in range(9):
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.14, 0.14)
		var at := radius + rng.randf_range(-0.04, 0.06)
		var size_at := rng.randf_range(0.13, 0.24)
		add_ball(m, size_at, Vector3(cos(a) * at, size_at * 0.32, sin(a) * at), mats["stone"],
			Vector3(1.0, rng.randf_range(0.5, 0.75), 1.0), 6, 4)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.6
		add_beam(m, Vector3(cos(a) * 0.08, 0.09, sin(a) * 0.08),
			Vector3(cos(a) * 0.45, 0.06, sin(a) * 0.45), 0.042, mats["char"], 4, 0.028)
	add_ball(m, 0.11, Vector3(0.0, 0.09, 0.0), mats["fire_core"], Vector3(1.0, 0.5, 1.0), 8, 4)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.35
		var card_h := rng.randf_range(0.42, 0.72)
		var card_w := rng.randf_range(0.32, 0.48)
		for k in range(2):
			m.add(_quad_mesh(Vector2(card_w, card_h)),
				_xf(Vector3(cos(a) * 0.09, 0.10 + card_h * 0.5, sin(a) * 0.09), a + float(k) * PI * 0.5),
				mats["flame"])
	m.commit(host, "CampFire")
	var light := OmniLight3D.new()
	light.name = "CampFireLight"
	light.position = Vector3(0.0, 0.55, 0.0)
	light.light_color = Color("ffb271")
	light.light_energy = 1.1
	light.omni_range = 6.5
	host.add_child(light)


static func add_cyl_disc(m: Merged, radius: float, height: float, at: Vector3,
		material: Material, sides: int = 14) -> void:
	m.add(_cyl_mesh(radius, radius, height, sides), _xf(at), material)


## A heap of driftwood and dead branches dragged in from the shore and the
## treeline, dumped where it was dropped.
static func driftwood_pile(host: Node3D, mats: Dictionary, solids: StaticBody3D,
		seed: int = 11) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	for i in range(9):
		var a := rng.randf_range(0.0, TAU)
		var start := Vector3(cos(a) * rng.randf_range(0.0, 0.35), rng.randf_range(0.05, 0.55),
			sin(a) * rng.randf_range(0.0, 0.35))
		var end := start + Vector3(cos(a) * rng.randf_range(0.7, 1.5),
			rng.randf_range(-0.35, 0.30), sin(a) * rng.randf_range(0.7, 1.5))
		add_beam(m, start, end, rng.randf_range(0.030, 0.065),
			mats["drift"] if i % 3 else mats["bark"], 4, 0.014)
	add_box(m, Vector3(0.9, 0.08, 0.9), Vector3(0.0, 0.04, 0.0), mats["ash"], 0.0, 0.0, 0.12)
	add_collider(solids, base, Vector3(1.8, 0.5, 1.8), Vector3(0.0, 0.25, 0.0))
	m.commit(host, "DriftwoodPile")


## A windbreak: a line of dead branches leaned into the wind and lashed, with
## brush jammed between them.
static func brush_screen(m: Merged, mats: Dictionary, at: Vector3, yaw: float, length: float,
		seed: int = 13) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	var posts := int(length / 0.55)
	for i in range(posts):
		var t := -length * 0.5 + (float(i) + 0.5) * (length / float(posts))
		var foot := Vector3(t, -0.12, rng.randf_range(-0.1, 0.1))
		_bent_pole(m, mats, foot, foot + Vector3(rng.randf_range(-0.2, 0.2),
			rng.randf_range(0.9, 1.5), rng.randf_range(-0.3, 0.1)), rng,
			rng.randf_range(0.025, 0.045), mats["twig"])
		_twig_pile(m, mats, foot + Vector3(0.0, rng.randf_range(0.3, 0.9), 0.0),
			Vector3.UP, 0.18, 5, rng)
	for i in range(posts - 1):
		var x0 := -length * 0.5 + float(i) * (length / float(posts))
		var x1 := x0 + length / float(posts)
		add_beam(m, Vector3(x0, rng.randf_range(0.5, 0.9), 0.0), Vector3(x1, rng.randf_range(0.5, 0.9), 0.0),
			rng.randf_range(0.014, 0.022), mats["twig_dark"], 3)
	m.group = saved


## A flat stone set on two smaller stones, smeared with ochre, a pair of skulls
## and a scatter of bones: the only ritual furniture the camp owns.
static func offering_stone(m: Merged, mats: Dictionary, at: Vector3, yaw: float,
		seed: int = 17) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	add_box(m, Vector3(0.72, 0.10, 0.52), Vector3(0.0, 0.46, 0.0), mats["stone"],
		0.0, 0.0, rng.randf_range(-0.05, 0.05))
	for side in SIDES:
		add_ball(m, 0.17, Vector3(side * 0.24, 0.16, 0.02), mats["stone"], Vector3(1.0, 0.8, 0.9), 6, 4)
	add_box(m, Vector3(0.5, 0.012, 0.10), Vector3(0.0, 0.52, -0.06), mats["ochre"], 0.0, 0.0,
		rng.randf_range(-0.2, 0.2))
	add_skull(m, mats, Vector3(-0.16, 0.56, 0.06), rng.randf_range(0.0, TAU), 0.55, true)
	add_skull(m, mats, Vector3(0.18, 0.55, -0.08), rng.randf_range(0.0, TAU), 0.5, false)
	for i in range(6):
		var a := TAU * float(i) / 6.0 + 0.3
		var r := rng.randf_range(0.75, 0.95)
		add_beam(m, Vector3(cos(a) * r, 0.04, sin(a) * r),
			Vector3(cos(a) * (r + 0.22), 0.04, sin(a) * (r + 0.22)), 0.022, mats["bone"], 3, 0.012)
	add_ring(m, Vector3(0.0, 0.03, 0.0), 0.0, 0.92, 1.02, mats["ochre"], 0.0, 18, 3)
	m.group = saved


## A run of skull-capped sticks, the camp's boundary omen. Sizes stay small.
static func skull_stakes(m: Merged, mats: Dictionary, at: Vector3, yaw: float,
		count: int = 4, spacing: float = 0.75, seed: int = 23) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	for i in range(count):
		var offset := Vector3(float(i) * spacing - float(count - 1) * spacing * 0.5,
			0.0, rng.randf_range(-0.20, 0.20))
		var height := rng.randf_range(0.85, 1.30)
		_bent_pole(m, mats, offset + Vector3(0.0, -0.12, 0.0),
			offset + Vector3(rng.randf_range(-0.12, 0.12), height, rng.randf_range(-0.12, 0.12)),
			rng, rng.randf_range(0.022, 0.036), mats["twig"])
		add_skull(m, mats, offset + Vector3(0.0, height + 0.06, 0.0), rng.randf_range(0.0, TAU),
			rng.randf_range(0.50, 0.70), i % 2 == 0)
	m.group = saved


## A pole rack with hides and meat strips hung to dry. Small: two stakes and a
## lashing, the way anyone would knock one up.
static func drying_rack(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 31) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var span := 1.65
	for side in SIDES:
		var foot := Vector3(side * span * 0.5, -0.14, 0.0)
		var top := foot + Vector3(side * rng.randf_range(-0.1, 0.1), rng.randf_range(1.55, 1.85),
			rng.randf_range(-0.1, 0.1))
		_bent_pole(m, mats, foot, top, rng, 0.032, mats["twig"])
	add_beam(m, Vector3(-span * 0.5 - 0.06, 1.48, 0.0), Vector3(span * 0.5 + 0.06, 1.52, 0.03),
		0.026, mats["drift"], 4, 0.020)
	for i in range(2):
		add_box(m, Vector3(rng.randf_range(0.22, 0.34), rng.randf_range(0.34, 0.56), 0.02),
			Vector3(-0.42 + float(i) * 0.14, rng.randf_range(1.02, 1.20), 0.0),
			mats["hide"] if i == 0 else mats["hide_dark"], rng.randf_range(-0.15, 0.15), 0.0,
			rng.randf_range(-0.12, 0.12))
		add_box(m, Vector3(rng.randf_range(0.20, 0.30), rng.randf_range(0.30, 0.48), 0.02),
			Vector3(0.24 + float(i) * 0.12, rng.randf_range(1.06, 1.22), 0.02),
			mats["hide_dark"] if i == 0 else mats["hide"], rng.randf_range(-0.15, 0.15), 0.0,
			rng.randf_range(-0.12, 0.12))
	for i in range(3):
		add_box(m, Vector3(0.07, 0.30, 0.02), Vector3(-0.02 + float(i) * 0.11, 1.24, 0.0),
			mats["ochre"], 0.0, 0.0, rng.randf_range(-0.15, 0.15))
	add_collider(solids, base, Vector3(span + 0.2, 1.4, 0.3), Vector3(0.0, 0.7, 0.0))
	m.commit(host, "DryingRack")


## A pot left on three sticks over the coals.
static func cauldron(m: Merged, mats: Dictionary, at: Vector3, yaw: float, s: float = 0.9) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	var apex := Vector3(0.0, 1.45, 0.0)
	for i in range(3):
		var a := TAU * float(i) / 3.0
		add_beam(m, Vector3(cos(a) * 0.75, 0.0, sin(a) * 0.75), apex, 0.038, mats["twig"], 4, 0.026)
	add_ball(m, 0.06, apex, mats["rag"], Vector3.ONE, 5, 3)
	add_beam(m, apex + Vector3(0.0, -0.04, 0.0), Vector3(0.0, 0.86, 0.0), 0.010, mats["rag"], 3)
	add_ball(m, 0.30, Vector3(0.0, 0.72, 0.0), mats["clay_dark"], Vector3(1.0, 0.70, 1.0), 10, 6)
	add_ring(m, Vector3(0.0, 0.86, 0.0), 0.0, 0.26, 0.30, mats["clay_dark"], 0.0, 12, 4)
	add_ball(m, 0.22, Vector3(0.0, 0.83, 0.0), mats["ash"], Vector3(1.0, 0.22, 1.0), 8, 4)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.5
		add_ball(m, 0.045, Vector3(cos(a) * 0.22, 0.08, sin(a) * 0.22), mats["ember"],
			Vector3(1.0, 0.6, 1.0), 5, 3)
	m.group = saved


## A stump used as a block, a flint flake and a stone hammer - no steel here.
static func chopping_block(m: Merged, mats: Dictionary, at: Vector3, yaw: float) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	m.add(_cyl_mesh(0.34, 0.30, 0.44, 8), _xf(Vector3(0.0, 0.22, 0.0)), mats["bark"])
	add_ring(m, Vector3(0.0, 0.44, 0.0), 0.0, 0.28, 0.34, mats["drift_dark"], 0.0, 10, 3)
	add_box(m, Vector3(0.16, 0.03, 0.10), Vector3(0.06, 0.47, -0.05), mats["char"], 0.4)
	add_ball(m, 0.09, Vector3(-0.26, 0.09, 0.16), mats["stone"], Vector3(1.0, 0.8, 1.0), 6, 4)
	add_beam(m, Vector3(-0.26, 0.10, 0.16), Vector3(-0.52, 0.20, 0.34), 0.022, mats["twig"], 3, 0.012)
	for i in range(4):
		add_ball(m, 0.032, Vector3(-0.20 + float(i) * 0.08, 0.03, 0.42 + float(i) * 0.05),
			mats["bone"], Vector3.ONE, 4, 3)
	m.group = saved


## A heap of picked bones and a cracked pot.
static func bone_heap(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 71) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	add_ball(m, 0.22, Vector3(0.0, 0.08, 0.0), mats["ash"], Vector3(1.5, 0.35, 1.2), 7, 4)
	for i in range(6):
		var a := TAU * float(i) / 6.0 + rng.randf_range(-0.3, 0.3)
		var at_local := Vector3(cos(a) * rng.randf_range(0.04, 0.30), rng.randf_range(0.10, 0.22),
			sin(a) * rng.randf_range(0.04, 0.28))
		add_beam(m, at_local, at_local + Vector3(rng.randf_range(-0.26, 0.26),
			rng.randf_range(-0.08, 0.02), rng.randf_range(-0.24, 0.24)), 0.028, mats["bone"], 3, 0.014)
	add_skull(m, mats, Vector3(-0.16, 0.18, 0.12), rng.randf_range(0.0, TAU), 0.5, true)
	add_ball(m, 0.11, Vector3(0.24, 0.08, -0.14), mats["clay_dark"], Vector3(1.0, 0.55, 1.0), 7, 4)
	m.group = saved


## A stack of clay pots and a couple of loose ones.
static func pot_stack(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 91) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	for i in range(3):
		var r := rng.randf_range(0.08, 0.15)
		var p := Vector3(rng.randf_range(-0.20, 0.20), r * 0.85, rng.randf_range(-0.16, 0.16))
		add_ball(m, r, p, mats["clay"] if i % 2 == 0 else mats["clay_dark"], Vector3(1.0, 0.85, 1.0), 8, 4)
		add_ring(m, p + Vector3(0.0, r * 0.72, 0.0), 0.0, r * 0.5, r * 0.72, mats["clay_dark"], 0.0, 8, 3)
	add_ball(m, 0.12, Vector3(-0.04, 0.34, 0.02), mats["clay"], Vector3(1.0, 0.8, 1.0), 8, 4)
	m.group = saved
