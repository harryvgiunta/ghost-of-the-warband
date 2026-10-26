class_name VillageKit
extends RefCounted
## Bushcrafted village art: the huts, fetishes, witch charms and sacrifice
## furniture of Hollowharrow, the settlement the Unholy Forest's tree-horned
## wardens keep.
##
## Everything is presentation. Props are merged into as few meshes as possible -
## one per structure, one world batch for all small doodads - so a full village
## costs a handful of draw calls. Every collider is registered against the
## caller's existing solid body so gameplay collision keeps one owner.
##
## Builders are deterministic from their seed: the same seed always produces the
## same prop, so the village rebuilds identically on every launch.

const Geo = preload("res://scripts/geo.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

## How many hanging-charm shapes `add_hanging` can pick from.
const HANGING_VARIANTS := 8

## The two sides of anything mirrored: posts, arms, horns, wattles.
const SIDES: Array[float] = [-1.0, 1.0]

static var _mats: Dictionary = {}
static var _prims: Dictionary = {}


# ---------------------------------------------------------------------------
# palette
# ---------------------------------------------------------------------------

## The village's one material set: bog-dark timber, reed thatch, stretched hide,
## weathered bone, iron, clay, ash and the ochre the wardens paint their marks in.
## Cached once; `range_world` shares it across every prop.
static func materials() -> Dictionary:
	if not _mats.is_empty():
		return _mats
	var m: Dictionary = {}
	m["bark"] = TextureLibrary.bark_material_tinted("bark_dead", Color("6f6653"))
	m["log"] = TextureLibrary.building_material("wood", Color("b7a488"))
	m["log_dark"] = TextureLibrary.building_material("wood", Color("8a7a62"))
	m["timber"] = TextureLibrary.building_material("timber", Color("82735c"))
	m["wattle"] = TextureLibrary.building_material("wattle", Color("9c8b6d"))
	m["stake"] = TextureLibrary.building_material("wood", Color("6d5c46"))
	m["thatch"] = TextureLibrary.building_material("thatch", Color("c8ad78"))
	m["thatch_dark"] = TextureLibrary.building_material("thatch", Color("a08c5e"))
	m["hide"] = TextureLibrary.building_material("hide", Color("c6a884"))
	m["hide_dark"] = TextureLibrary.building_material("hide", Color("8d6f50"))
	m["hide_wall"] = TextureLibrary.building_material("hide", Color("a8875f"))
	m["bone"] = TextureLibrary.building_material("bone", Color("b6ab8d"))
	m["stone"] = TextureLibrary.granite_material(Color("8a8070"))
	m["daub"] = TextureLibrary.building_material("plaster", Color("54483a"))
	m["ash"] = Geo.material(Color("241e19"), 0.0, 1.0)
	m["char"] = Geo.material(Color("171412"), 0.0, 0.98)
	m["iron"] = Geo.material(Color("3b3937"), 0.72, 0.48)
	m["clay"] = Geo.material(Color("8d5a3b"), 0.04, 0.93)
	m["clay_dark"] = Geo.material(Color("6a4230"), 0.04, 0.94)
	m["rag"] = Geo.material(Color("332d26"), 0.0, 0.95)
	m["ochre"] = Geo.material(Color("5e2418"), 0.05, 0.9)
	m["wicker"] = TextureLibrary.building_material("timber", Color("8a7550"))
	m["moss"] = Geo.material(Color("455536"), 0.0, 0.95)
	m["feather"] = Geo.material(Color("3d352c"), 0.0, 0.85)
	m["ember"] = _glow(Color("ff8a3c"), Color("ff5a12"), 2.0)
	m["flame"] = TextureLibrary.flame_material()
	m["fire_core"] = _glow(Color("ffd08a"), Color("ff8a2a"), 2.6)
	m["rune"] = _glow(Color("6e2018"), Color("c8452a"), 0.7)
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
# primitive cache (one mesh per distinct parameter set, shared by every prop)
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

	## Enters a local frame (position + rotation + uniform scale), returning the
	## frame to restore with `group = ...`.
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
		sides: int = 6, tip: float = -1.0) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.0005:
		return
	var up := span / length
	var hint := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := up.cross(hint).normalized()
	var forward := side.cross(up).normalized()
	var basis := Basis(side, up, forward)
	m.add(_cyl_mesh(radius, radius if tip < 0.0 else tip, length, sides),
		Transform3D(basis, (a + b) * 0.5), material)


static func add_ball(m: Merged, radius: float, at: Vector3, material: Material,
		squash: Vector3 = Vector3.ONE, segments: int = 8, rings: int = 5) -> void:
	m.add(_sphere_mesh(radius, segments, rings), _xf(at, 0.0, 0.0, 0.0, 1.0).scaled_local(squash), material)


static func add_cone(m: Merged, radius: float, height: float, at: Vector3, material: Material,
		sides: int = 9, taper: float = 0.03, lean: Vector2 = Vector2.ZERO) -> void:
	m.add(_cyl_mesh(radius, radius * taper, height, sides), _xf(at, 0.0, lean.y, lean.x), material)


## `pitch` 0 lays the band flat (a rim, a binding, a painted band); PI * 0.5
## stands the hoop up in the yaw plane (a hook, a snare, a hanging ring).
static func add_ring(m: Merged, at: Vector3, yaw: float, inner: float, outer: float,
		material: Material, pitch: float = 0.0, rings: int = 14, segments: int = 5) -> void:
	m.add(_ring_mesh(inner, outer, rings, segments), _xf(at, yaw, pitch), material)


# --- collision helpers -----------------------------------------------------

## Registers one box collider on the caller's solid body. `base` is the prop's
## world transform (host.transform); `at` is local to it.
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


static func add_post_collider(solids: StaticBody3D, base: Transform3D, radius: float,
		height: float, at: Vector3) -> void:
	if solids == null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = base * _xf(at + Vector3(0.0, height * 0.5, 0.0))
	solids.add_child(collision)


# ---------------------------------------------------------------------------
# shared motifs
# ---------------------------------------------------------------------------

## An animal skull: domed cranium, brow, long tapered muzzle, sunken eye pits and
## jaw. The muzzle points down -Z before `yaw` is applied, so a skull lashed to a
## post faces out of the village.
static func add_skull(m: Merged, mats: Dictionary, at: Vector3, yaw: float = 0.0,
		s: float = 1.0, horns: bool = false) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	# cranium: widest at the back, flattened on top
	add_ball(m, 0.135, Vector3(0.0, 0.005, 0.02), mats["bone"], Vector3(0.90, 0.84, 1.00), 10, 6)
	add_box(m, Vector3(0.235, 0.105, 0.14), Vector3(0.0, -0.005, -0.025), mats["bone"])
	# brow ridge over the sockets, then the muzzle tapering forward
	add_box(m, Vector3(0.205, 0.05, 0.10), Vector3(0.0, 0.06, -0.10), mats["bone"], 0.0, 0.20)
	add_box(m, Vector3(0.115, 0.085, 0.20), Vector3(0.0, -0.045, -0.20), mats["bone"], 0.0, 0.10)
	add_box(m, Vector3(0.085, 0.065, 0.11), Vector3(0.0, -0.058, -0.335), mats["bone"], 0.0, 0.04)
	# sunken eye pits and the nasal cavity
	add_ball(m, 0.046, Vector3(0.062, 0.012, -0.118), mats["ash"], Vector3(1.0, 0.9, 0.45), 7, 4)
	add_ball(m, 0.046, Vector3(-0.062, 0.012, -0.118), mats["ash"], Vector3(1.0, 0.9, 0.45), 7, 4)
	add_box(m, Vector3(0.038, 0.05, 0.022), Vector3(0.0, -0.012, -0.30), mats["ash"])
	# jaw and teeth
	add_box(m, Vector3(0.10, 0.045, 0.23), Vector3(0.0, -0.115, -0.17), mats["bone"], 0.0, -0.05)
	for i in range(4):
		add_box(m, Vector3(0.016, 0.042, 0.016), Vector3(-0.036 + float(i) * 0.024, -0.085, -0.275),
			mats["bone"])
	if horns:
		for side in SIDES:
			var root := Vector3(side * 0.10, 0.075, 0.01)
			var mid := root + Vector3(side * 0.085, 0.13, -0.03)
			var tip := mid + Vector3(side * 0.05, 0.16, -0.07)
			add_beam(m, root, mid, 0.034, mats["bone"], 5, 0.022)
			add_beam(m, mid, tip, 0.022, mats["bone"], 5, 0.008)
	m.group = saved


## A branched antler, used on door crowns, totems and effigies.
static func add_antler(m: Merged, mats: Dictionary, at: Vector3, yaw: float, s: float = 1.0) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	add_beam(m, Vector3.ZERO, Vector3(0.10, 0.42, -0.05), 0.038, mats["bone"], 6, 0.026)
	add_beam(m, Vector3(0.10, 0.42, -0.05), Vector3(0.30, 0.74, -0.10), 0.026, mats["bone"], 5, 0.012)
	add_beam(m, Vector3(0.10, 0.42, -0.05), Vector3(0.05, 0.63, 0.06), 0.019, mats["bone"], 5, 0.008)
	add_beam(m, Vector3(0.22, 0.62, -0.08), Vector3(0.40, 0.80, 0.02), 0.015, mats["bone"], 5, 0.007)
	add_beam(m, Vector3(0.04, 0.20, 0.0), Vector3(-0.10, 0.33, 0.06), 0.019, mats["bone"], 5, 0.008)
	m.group = saved


## A carved guardian idol: stacked timber body, skull or block head, antler crown.
## `kind` 0 is a tall warden, 1 a squat skull-idol holding a bowl.
static func add_figurine(m: Merged, mats: Dictionary, at: Vector3, yaw: float,
		s: float = 1.0, kind: int = 0, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	var tall := kind == 0
	var body_h := 1.05 if tall else 0.62
	var body_r := 0.17 if tall else 0.26
	# plinth, body, shoulders
	add_box(m, Vector3(body_r * 2.6, 0.12, body_r * 2.6), Vector3(0.0, 0.06, 0.0), mats["stone"])
	add_beam(m, Vector3(0.0, 0.10, 0.0), Vector3(0.0, 0.10 + body_h, 0.0), body_r, mats["wattle"], 7, body_r * 0.62)
	add_box(m, Vector3(body_r * 2.2, 0.16, body_r * 1.5), Vector3(0.0, 0.10 + body_h, 0.0), mats["log_dark"])
	if tall:
		# bound arms lifted outward
		for side in SIDES:
			add_beam(m, Vector3(side * 0.14, body_h * 0.78, 0.0),
				Vector3(side * 0.40, body_h * 0.62 + 0.30, -0.10), 0.048, mats["wattle"], 5, 0.032)
		add_skull(m, mats, Vector3(0.0, 0.10 + body_h + 0.22, 0.0), PI, 0.86, true)
		add_antler(m, mats, Vector3(-0.05, 0.30 + body_h, 0.02), 0.4, 0.85)
	else:
		# squat idol: a carved timber head with a skull lashed to its face
		var head_at := Vector3(0.0, 0.10 + body_h + 0.20, 0.0)
		add_box(m, Vector3(0.30, 0.28, 0.27), head_at, mats["wattle"])
		add_skull(m, mats, head_at + Vector3(0.0, -0.01, -0.15), 0.0, 0.52, false)
		add_antler(m, mats, head_at + Vector3(-0.02, 0.12, 0.02), 0.45, 0.6)
		add_box(m, Vector3(0.22, 0.04, 0.02), head_at + Vector3(0.0, -0.10, -0.14), mats["ochre"])
		# offering bowl held in front
		add_ball(m, 0.13, Vector3(0.0, 0.52, -0.24), mats["clay"], Vector3(1.0, 0.5, 1.0), 9, 5)
		add_ball(m, 0.09, Vector3(0.0, 0.56, -0.24), mats["clay_dark"], Vector3(1.0, 0.35, 1.0), 8, 4)
	# painted marks and a bone necklace
	for i in range(3):
		var y := 0.30 + float(i) * (body_h * 0.42)
		add_ring(m, Vector3(0.0, y, 0.0), rng.randf_range(0.0, TAU), body_r * 0.98, body_r * 1.12, mats["ochre"], 0.0, 10, 4)
	for i in range(5):
		var a := TAU * float(i) / 5.0
		add_ball(m, 0.022, Vector3(cos(a) * body_r * 1.05, 0.10 + body_h * 0.86, sin(a) * body_r * 1.05),
			mats["bone"], Vector3.ONE, 5, 3)
	m.group = saved


# ---------------------------------------------------------------------------
# hanging charms
# ---------------------------------------------------------------------------

static func _rope(m: Merged, mats: Dictionary, from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> void:
	var mid := from.lerp(to, 0.5) + Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05))
	add_beam(m, from, mid, 0.015, mats["rag"], 4)
	add_beam(m, mid, to, 0.015, mats["rag"], 4)
	add_ball(m, 0.026, from, mats["rag"], Vector3.ONE, 5, 3)
	add_ball(m, 0.028, mid, mats["rag"], Vector3.ONE, 5, 3)


## One hanging charm tied at `top` (a branch, a lintel, a rack bar) and dropping
## down. Eight shapes: bone chime, skull string, pot string, antler charm,
## wicker cage, rag fetish, rib bundle and a carved rune board. Returns the drop.
static func add_hanging(m: Merged, mats: Dictionary, top: Vector3, yaw: float, seed: int,
		scale_at: float = 1.0) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var variant := posmod(seed, HANGING_VARIANTS)
	var s := scale_at * rng.randf_range(0.88, 1.16)
	var saved := m.push(_xf(top, yaw, 0.0, 0.0, s))
	var rope_len := rng.randf_range(0.55, 1.85)
	var sway := rng.randf_range(-0.16, 0.16)
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
			add_antler(m, mats, knot, rng.randf_range(0.0, TAU), 0.9)
			add_beam(m, knot, knot + Vector3(0.22, -0.30, 0.05), 0.012, mats["rag"], 4)
			for i in range(3):
				add_ball(m, 0.024, knot + Vector3(-0.12 + float(i) * 0.11, -0.22 - float(i) * 0.07, 0.0),
					mats["bone"], Vector3.ONE, 5, 3)
		4:
			_wicker_cage(m, mats, knot, rng)
		5:
			_rag_fetish(m, mats, knot, rng)
		6:
			_rib_bundle(m, mats, knot, rng)
		_:
			_rune_board(m, mats, knot, rng)
	m.group = saved
	return rope_len


static func _bone_chime(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	add_ring(m, knot, 0.0, 0.07, 0.10, mats["iron"])
	for i in range(5):
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var at := knot + Vector3(cos(a) * 0.09, 0.0, sin(a) * 0.09)
		var drop := rng.randf_range(0.14, 0.42)
		var low := at + Vector3(0.0, -drop, 0.0)
		add_beam(m, at, low, 0.007, mats["rag"], 4)
		add_ball(m, 0.028, low, mats["bone"], Vector3.ONE, 6, 4)
		var tail := low + Vector3(rng.randf_range(-0.04, 0.04), -rng.randf_range(0.16, 0.30), rng.randf_range(-0.04, 0.04))
		add_beam(m, low, tail, 0.026, mats["bone"], 5, 0.018)
		add_ball(m, 0.03, tail, mats["bone"], Vector3.ONE, 6, 4)


static func _skull_string(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var at := knot
	for i in range(3):
		var size_at := 0.72 - float(i) * 0.14
		add_skull(m, mats, at, rng.randf_range(0.0, TAU), size_at, i == 0)
		var next := at + Vector3(rng.randf_range(-0.07, 0.07), -0.40, rng.randf_range(-0.07, 0.07))
		_rope(m, mats, at + Vector3(0.0, -0.10, 0.0), next, rng)
		at = next


static func _pot_string(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var at := knot
	for i in range(4):
		var r := 0.15 - float(i) * 0.016
		add_ball(m, r, at, mats["clay"], Vector3(1.0, 0.8, 1.0), 10, 6)
		add_ring(m, at + Vector3(0.0, r * 0.72, 0.0), 0.0, r * 0.5, r * 0.72, mats["clay_dark"], 0.0, 10, 4)
		add_beam(m, at + Vector3(0.0, r * 0.9, 0.0), at + Vector3(0.0, 0.16, 0.0), 0.010, mats["rag"], 4)
		at += Vector3(rng.randf_range(-0.05, 0.05), -0.44, rng.randf_range(-0.05, 0.05))
		_rope(m, mats, at + Vector3(0.0, 0.44, 0.0), at, rng)


static func _wicker_cage(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var top := knot + Vector3(0.0, -0.10, 0.0)
	var floor_at := knot + Vector3(0.0, -0.62, 0.0)
	add_ring(m, top, 0.0, 0.16, 0.21, mats["wicker"], 0.0, 12, 4)
	add_ring(m, floor_at, 0.0, 0.24, 0.30, mats["wicker"], 0.0, 14, 4)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		add_beam(m, top + Vector3(cos(a) * 0.18, 0.0, sin(a) * 0.18),
			floor_at + Vector3(cos(a) * 0.27, 0.02, sin(a) * 0.27), 0.014, mats["wicker"], 4)
	add_ring(m, knot + Vector3(0.0, -0.36, 0.0), 0.0, 0.20, 0.24, mats["wicker"], 0.0, 12, 4)
	add_skull(m, mats, knot + Vector3(rng.randf_range(-0.03, 0.03), -0.44, 0.0), rng.randf_range(0.0, TAU), 0.5, false)


static func _rag_fetish(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	add_ring(m, knot, 0.0, 0.06, 0.09, mats["iron"])
	for i in range(5):
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.2, 0.2)
		var at := knot + Vector3(cos(a) * 0.07, -0.02, sin(a) * 0.07)
		var length := rng.randf_range(0.24, 0.52)
		add_box(m, Vector3(0.06, length, 0.012), at + Vector3(0.0, -length * 0.5, 0.0),
			mats["rag"], a, 0.0, rng.randf_range(-0.2, 0.2))
		if i % 2 == 0:
			add_box(m, Vector3(0.045, 0.16, 0.008), at + Vector3(0.0, -length - 0.06, 0.0),
				mats["feather"], a, 0.0, rng.randf_range(-0.4, 0.4))
	add_beam(m, knot + Vector3(0.0, -0.06, 0.0), knot + Vector3(0.04, -0.34, 0.02), 0.022, mats["bone"], 5, 0.014)


static func _rib_bundle(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var spine_a := knot + Vector3(0.0, -0.14, 0.0)
	var spine_b := knot + Vector3(0.06, -0.70, 0.04)
	add_beam(m, spine_a, spine_b, 0.036, mats["bone"], 6, 0.026)
	for i in range(6):
		var t := 0.12 + float(i) * 0.15
		var root := spine_a.lerp(spine_b, t)
		var side := -1.0 if i % 2 == 0 else 1.0
		var bend := root + Vector3(side * 0.14, -0.05, rng.randf_range(-0.06, 0.06))
		var tip := bend + Vector3(side * 0.08, -0.24, rng.randf_range(-0.05, 0.05))
		add_beam(m, root, bend, 0.017, mats["bone"], 4, 0.014)
		add_beam(m, bend, tip, 0.014, mats["bone"], 4, 0.008)
	add_box(m, Vector3(0.22, 0.34, 0.02), spine_b + Vector3(0.0, 0.10, 0.06), mats["hide_dark"], 0.2)


static func _rune_board(m: Merged, mats: Dictionary, knot: Vector3, rng: RandomNumberGenerator) -> void:
	var board := knot + Vector3(0.0, -0.34, 0.0)
	add_box(m, Vector3(0.34, 0.46, 0.035), board, mats["log_dark"], 0.0, 0.0, 0.08)
	for i in range(3):
		add_box(m, Vector3(0.05, 0.14, 0.012), board + Vector3(-0.08 + float(i) * 0.08, 0.03, -0.024),
			mats["rune"], 0.0, 0.0, rng.randf_range(-0.5, 0.5))
	add_box(m, Vector3(0.16, 0.03, 0.012), board + Vector3(0.0, -0.14, -0.024), mats["ochre"])
	add_ring(m, board + Vector3(0.0, -0.30, 0.0), 0.0, 0.05, 0.07, mats["iron"], PI * 0.5, 10, 4)


# ---------------------------------------------------------------------------
# great firepit
# ---------------------------------------------------------------------------

## The village's hearth: a ringed ash pit with charred logs, a burning centre,
## a cauldron tripod, bone stakes and log benches. Returns the firepit root.
static func great_pit(host: Node3D, mats: Dictionary, solids: StaticBody3D,
		radius: float = 3.3, seed: int = 11) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	# ash bed, burnt-out hollow and the mound the fire sits on
	add_cyl_disc(m, radius * 0.98, 0.22, Vector3(0.0, 0.09, 0.0), mats["ash"], 28)
	add_cyl_disc(m, radius * 0.62, 0.26, Vector3(0.0, 0.11, 0.0), mats["char"], 24)
	add_ball(m, radius * 0.34, Vector3(0.0, 0.16, 0.0), mats["ash"], Vector3(1.0, 0.30, 1.0), 14, 6)
	# burnt lumps and bone chips across the bed
	for i in range(16):
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.3, radius * 0.80)
		var lump := rng.randf_range(0.10, 0.26)
		add_ball(m, lump, Vector3(cos(a) * r, 0.10 + rng.randf_range(0.0, 0.08), sin(a) * r),
			mats["char"] if i % 3 else mats["ash"],
			Vector3(1.0, rng.randf_range(0.4, 0.7), 1.0), 6, 4)
	for i in range(7):
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.5, radius * 0.85)
		add_beam(m, Vector3(cos(a) * r, 0.12, sin(a) * r),
			Vector3(cos(a) * r + rng.randf_range(-0.3, 0.3), 0.12,
				sin(a) * r + rng.randf_range(-0.3, 0.3)), 0.028, mats["bone"], 3, 0.014)
	# a continuous kerb of rounded fire stones, not scattered blocks
	for i in range(40):
		var a := TAU * float(i) / 40.0 + rng.randf_range(-0.04, 0.04)
		var ring_r := radius - 0.02 + rng.randf_range(-0.05, 0.05)
		var width := rng.randf_range(0.30, 0.46)
		var tall := rng.randf_range(0.16, 0.26)
		var depth := rng.randf_range(0.30, 0.46)
		add_ball(m, width, Vector3(cos(a) * ring_r, tall * 0.34, sin(a) * ring_r), mats["stone"],
			Vector3(1.0, tall / width, depth / width), 8, 5)
	# charred logs in the fireplace
	for i in range(5):
		var a := TAU * float(i) / 5.0 + 0.4
		var inner := Vector3(cos(a) * 0.30, 0.24, sin(a) * 0.30)
		var outer := Vector3(cos(a) * (radius - 0.95), 0.18, sin(a) * (radius - 0.95))
		add_beam(m, inner, outer, rng.randf_range(0.10, 0.15), mats["char"], 6, 0.07)
		add_ball(m, 0.13, outer, mats["ash"], Vector3(1.0, 0.7, 1.0), 6, 4)
	# fire: a hot core under crossed cards of the authored flame tongues
	add_ball(m, 0.36, Vector3(0.0, 0.26, 0.0), mats["fire_core"], Vector3(1.0, 0.42, 1.0), 10, 5)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.35
		var card_h := rng.randf_range(1.55, 2.30)
		var card_w := rng.randf_range(0.95, 1.30)
		var at := Vector3(cos(a) * 0.22, 0.16 + card_h * 0.5, sin(a) * 0.22)
		for k in range(2):
			m.add(_quad_mesh(Vector2(card_w, card_h)), _xf(at, a + float(k) * PI * 0.5), mats["flame"])
	for i in range(2):
		var a := TAU * float(i) / 2.0 + 1.2
		var card_h := rng.randf_range(0.80, 1.20)
		var card_w := rng.randf_range(0.60, 0.85)
		m.add(_quad_mesh(Vector2(card_w, card_h)),
			_xf(Vector3(cos(a) * 0.44, 0.18 + card_h * 0.5, sin(a) * 0.44), a + 0.4), mats["flame"])
	for i in range(7):
		var a := TAU * float(i) / 7.0
		add_ball(m, rng.randf_range(0.035, 0.07), Vector3(cos(a) * rng.randf_range(0.6, 2.2), 0.16,
			sin(a) * rng.randf_range(0.6, 2.2)), mats["ember"], Vector3(1.0, 0.6, 1.0), 6, 4)
	# cauldron tripod over the fire
	var apex := Vector3(0.0, 2.95, 0.0)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.6
		add_beam(m, Vector3(cos(a) * 2.55, 0.0, sin(a) * 2.55), apex, 0.075, mats["log_dark"], 6, 0.05)
	add_ball(m, 0.10, apex, mats["rag"], Vector3.ONE, 6, 4)
	add_ring(m, apex + Vector3(0.0, -0.06, 0.0), 0.0, 0.07, 0.10, mats["iron"], 0.0, 10, 4)
	add_beam(m, apex + Vector3(0.0, -0.10, 0.0), Vector3(0.0, 1.62, 0.0), 0.016, mats["iron"], 4)
	add_ball(m, 0.34, Vector3(0.0, 1.42, 0.0), mats["iron"], Vector3(1.0, 0.82, 1.0), 12, 7)
	add_ring(m, Vector3(0.0, 1.60, 0.0), 0.0, 0.30, 0.34, mats["iron"], 0.0, 14, 5)
	add_ball(m, 0.26, Vector3(0.0, 1.56, 0.0), mats["char"], Vector3(1.0, 0.25, 1.0), 10, 5)
	# bone stakes at the four quarters of the rim
	for i in range(4):
		var a := TAU * float(i) / 4.0 + 0.35
		var foot := Vector3(cos(a) * (radius + 0.55), 0.0, sin(a) * (radius + 0.55))
		var top := foot + Vector3(cos(a) * 0.10, 2.35, sin(a) * 0.10)
		add_beam(m, foot, top, 0.055, mats["log_dark"], 6, 0.042)
		add_skull(m, mats, top + Vector3(0.0, 0.10, 0.0), atan2(-cos(a), -sin(a)), 0.8, i % 2 == 0)
		add_ring(m, foot + Vector3(0.0, 1.35, 0.0), a, 0.06, 0.08, mats["ochre"], 0.0, 10, 4)
		add_ring(m, foot + Vector3(0.0, 1.62, 0.0), a, 0.06, 0.08, mats["ochre"], 0.0, 10, 4)
	# two half-log benches on the approach side
	for side in SIDES:
		var a := PI * 0.5 + side * 0.85
		var at := Vector3(cos(a) * (radius + 1.65), 0.26, sin(a) * (radius + 1.65))
		add_beam(m, at + Vector3(-1.15, 0.0, 0.22), at + Vector3(1.15, 0.0, 0.22), 0.22, mats["bark"], 7, 0.20)
		add_beam(m, at + Vector3(-1.15, 0.0, -0.20), at + Vector3(1.15, 0.0, -0.20), 0.20, mats["bark"], 7, 0.18)
	m.commit(host, "GreatFirepitPit")
	var light := OmniLight3D.new()
	light.name = "FirepitLight"
	light.position = Vector3(0.0, 1.5, 0.0)
	light.light_color = Color("ffb271")
	light.light_energy = 2.4
	light.omni_range = 17.0
	host.add_child(light)
	# the benches are the only solid part: the pit itself is walked around
	for side in SIDES:
		var a := PI * 0.5 + side * 0.85
		var at := Vector3(cos(a) * (radius + 1.65), 0.26, sin(a) * (radius + 1.65))
		add_collider(solids, host.transform, Vector3(2.4, 0.55, 0.55), at)


static func add_cyl_disc(m: Merged, radius: float, height: float, at: Vector3, material: Material, sides: int = 16) -> void:
	m.add(_cyl_mesh(radius, radius, height, sides), _xf(at), material)


# ---------------------------------------------------------------------------
# keeper hut (bushcrafted longhouse)
# ---------------------------------------------------------------------------

## Rebuilds one keeper building the way the wardens built it: crooked sticks
## planted shoulder to shoulder, lashed at random heights, patched with hide and
## daub, and pegged under a ragged reed roof. No plumb lines, no sawn boards, no
## coursing. Only the collider contract is exact: the 7 x 6 m footprint, the
## 1.8 m back doorway at local z = -3 and an open, walkable interior. Returns the
## charm count so the scene can report it.
static func keeper_hut(host: Node3D, mats: Dictionary, solids: StaticBody3D, spec: Dictionary) -> int:
	var seed_value := int(spec.get("seed", 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := Merged.new()
	var base := host.transform
	var pitch := float(spec.get("pitch", 0.52))
	var eave := 3.36 + rng.randf_range(-0.08, 0.20)
	var ridge := eave + tan(pitch) * 3.95 + rng.randf_range(-0.10, 0.16)
	var charm_count := 0

	# --- shell colliders (the interior contract from the original house) -----
	add_collider(solids, base, Vector3(7.0, 3.7, 0.32), Vector3(0.0, 1.85, 3.0))
	for x in [-3.5, 3.5]:
		add_collider(solids, base, Vector3(0.32, 3.7, 6.0), Vector3(x, 1.85, 0.0))
	for x in [-2.2, 2.2]:
		add_collider(solids, base, Vector3(2.6, 3.7, 0.32), Vector3(x, 1.85, -3.0))
	add_collider(solids, base, Vector3(1.8, 1.1, 0.32), Vector3(0.0, 3.15, -3.0))

	# --- four walls of planted sticks, hide and daub ----------------------
	_stick_wall(m, mats, rng, Vector3(0.0, 0.0, 3.12), Vector3.RIGHT, Vector3.BACK, 7.0, eave)
	_stick_wall(m, mats, rng, Vector3(0.0, 0.0, -3.12), Vector3.LEFT, Vector3.FORWARD, 7.0, eave,
		-0.98, 0.98)
	for side in SIDES:
		_stick_wall(m, mats, rng, Vector3(side * 3.62, 0.0, 0.0), Vector3.BACK,
			Vector3(side, 0.0, 0.0), 6.0, eave)
	_wall_patches(m, mats, rng, Vector3(0.0, 0.0, 3.10), Vector3.RIGHT, Vector3.BACK, 6.8, 0.35, eave - 0.55)
	_wall_patches(m, mats, rng, Vector3(0.0, 0.0, -3.10), Vector3.LEFT, Vector3.FORWARD, 6.8, 0.35,
		eave - 0.55, 1.40)
	for side in SIDES:
		_wall_patches(m, mats, rng, Vector3(side * 3.60, 0.0, 0.0), Vector3.BACK,
			Vector3(side, 0.0, 0.0), 5.8, 0.35, eave - 0.55)
	# stones and moss piled against the foot of the sticks
	for i in range(9):
		var a := rng.randf_range(0.0, TAU)
		add_ball(m, rng.randf_range(0.13, 0.25),
			Vector3(cos(a) * rng.randf_range(3.6, 4.2), 0.08, sin(a) * rng.randf_range(3.1, 3.6)),
			mats["stone"], Vector3(1.0, 0.65, 1.0), 7, 4)
	for i in range(6):
		add_ball(m, rng.randf_range(0.14, 0.26), Vector3(rng.randf_range(-3.4, 3.4), 0.22,
			rng.randf_range(-3.3, 3.3)), mats["moss"], Vector3(1.0, 0.45, 1.0), 6, 4)

	# --- roof: ragged reed mats over crooked rafters, lashed at the ridge --
	_thatch_roof(m, mats, solids, base, rng, eave, ridge)
	for side_z in SIDES:
		_gable_fill(m, mats, rng, eave, ridge, side_z * 3.02)
	# the back gable keeps a smoking hole, half covered by a loose hide
	add_box(m, Vector3(0.78, 0.62, 0.05), Vector3(0.0, ridge - 1.45, -3.12), mats["char"])
	add_box(m, Vector3(1.05, 0.85, 0.03), Vector3(0.0, ridge - 0.92, -3.18), mats["hide_dark"],
		0.0, 0.0, 0.22)

	# --- the doorway: a bundle lintel, a hide roll, the antler crown --------
	for i in range(3):
		var lintel_y := 2.58 + float(i) * 0.13 + rng.randf_range(-0.04, 0.04)
		add_beam(m, Vector3(-1.26, lintel_y, -3.14 + rng.randf_range(-0.04, 0.04)),
			Vector3(1.26, lintel_y + rng.randf_range(-0.08, 0.08), -3.14 + rng.randf_range(-0.04, 0.04)),
			0.062, mats["stake"], 5, 0.05)
	# a hide sheet laced over the gap above the lintel bundle
	add_box(m, Vector3(2.00, 1.05, 0.025), Vector3(0.0, 3.22, -3.10), mats["hide_dark"], 0.0, 0.0, 0.06)
	# rolled hide slung on a crooked stick across the opening
	add_beam(m, Vector3(-1.16, 2.44, -3.24), Vector3(1.16, 2.50, -3.24), 0.045, mats["log_dark"], 5, 0.035)
	add_beam(m, Vector3(-0.98, 2.40, -3.28), Vector3(0.98, 2.40, -3.28), 0.17, mats["hide"], 8, 0.17)
	for x in [-0.70, 0.70]:
		add_box(m, Vector3(0.05, 0.30, 0.04), Vector3(x, 2.30, -3.26), mats["rag"])
	# leaning braces and threshold stones
	for side in SIDES:
		add_beam(m, Vector3(side * 1.60, -0.05, -3.16), Vector3(side * 0.98, 2.10, -3.20), 0.055,
			mats["stake"], 5, 0.04)
	for i in range(3):
		add_ball(m, rng.randf_range(0.16, 0.26), Vector3(-0.75 + float(i) * 0.75, 0.06, -3.30),
			mats["stone"], Vector3(1.0, 0.6, 1.2), 7, 4)
	add_antler(m, mats, Vector3(-0.55, 2.92, -3.12), 0.4, 1.15)
	add_antler(m, mats, Vector3(0.55, 2.92, -3.12), PI - 0.4, 1.15)
	for side in SIDES:
		add_hanging(m, mats, Vector3(side * 1.46, 2.40, -3.20), rng.randf_range(0.0, TAU),
			seed_value * 31 + int(side) + 7, 0.62)
		charm_count += 1
	# ochre handprints smeared on the sticks either side of the door
	for side in SIDES:
		for i in range(3):
			add_box(m, Vector3(0.10, 0.045, 0.03),
				Vector3(side * (1.18 + float(i) * 0.11), 1.05 + float(i) * 0.27, -3.18),
				mats["ochre"], rng.randf_range(-0.4, 0.4))
	# --- hide shutters lashed over the walls -------------------------------
	for x in [-2.30, 2.30]:
		add_box(m, Vector3(0.92, 0.98, 0.03), Vector3(x, 1.98 + rng.randf_range(-0.12, 0.12), 3.16),
			mats["hide_dark"] if rng.randf() < 0.5 else mats["hide"],
			rng.randf_range(-0.10, 0.10), 0.0, rng.randf_range(-0.10, 0.10))
		add_beam(m, Vector3(x - 0.42, 1.48, 3.20), Vector3(x + 0.42, 2.42, 3.20), 0.028,
			mats["log_dark"], 4)
	for side in SIDES:
		add_box(m, Vector3(0.03, 0.90, 0.85), Vector3(side * 3.66, 1.90 + rng.randf_range(-0.1, 0.1),
			rng.randf_range(-1.2, 1.2)), mats["hide_dark"], 0.0, 0.0, rng.randf_range(-0.12, 0.12))

	# --- side clutter, chosen per hut so the four read differently ---------
	match posmod(seed_value, 3):
		0:
			# lean-to store against the east wall, thatch falling away from the hut
			for z in [-1.7, 0.0, 1.7]:
				add_beam(m, Vector3(3.58, 2.60, z), Vector3(5.15, 1.85, z), 0.07, mats["log_dark"], 6, 0.05)
				add_post_collider(solids, base, 0.12, 1.85, Vector3(5.10, 0.0, z))
			for k in range(3):
				var z := -1.20 + float(k) * 1.20
				add_box(m, Vector3(1.70, 0.05, 1.30), Vector3(4.35, 2.30, z), mats["thatch"],
					0.0, 0.0, 0.36 + rng.randf_range(-0.05, 0.05))
				add_box(m, Vector3(0.20, 0.22, 1.30), Vector3(5.18, 1.92, z), mats["thatch_dark"], 0.0, 0.0, 0.36)
			add_box(m, Vector3(1.10, 1.25, 0.04), Vector3(5.10, 1.10, 0.9), mats["hide_dark"], 0.0, 0.0, 0.08)
			add_box(m, Vector3(1.30, 0.62, 0.70), Vector3(4.20, 0.31, -0.80), mats["log_dark"])
			add_collider(solids, base, Vector3(1.30, 0.62, 0.70), Vector3(4.20, 0.31, -0.80))
		1:
			# split firewood stacked under the west eave
			for i in range(7):
				var y := 0.14 + float(i % 3) * 0.23
				var z := -1.15 + float(i) * 0.38
				add_beam(m, Vector3(-4.30, y, z), Vector3(-3.72, y, z + 0.10), 0.10, mats["log"], 6, 0.09)
			add_box(m, Vector3(0.70, 0.08, 3.00), Vector3(-4.05, 0.05, 0.0), mats["log_dark"])
		_:
			# antler and skull rack on the west wall
			add_box(m, Vector3(0.10, 0.12, 2.40), Vector3(-3.70, 2.55, 0.4), mats["timber"])
			for i in range(3):
				add_antler(m, mats, Vector3(-3.72, 2.42, -0.50 + float(i) * 0.82), PI * 0.5 + 0.2, 0.95)
			for i in range(2):
				add_skull(m, mats, Vector3(-3.72, 2.02, 0.10 + float(i) * 0.70), -PI * 0.5, 0.72, i == 1)
	# pots by the door, a stool and a lantern bundle inside
	add_ball(m, 0.17, Vector3(-2.55, 0.19, -2.60), mats["clay"], Vector3(1.0, 0.9, 1.0), 9, 5)
	add_ball(m, 0.13, Vector3(-2.22, 0.15, -2.30), mats["clay_dark"], Vector3(1.0, 0.85, 1.0), 9, 5)
	add_ball(m, 0.10, Vector3(-2.72, 0.12, -2.28), mats["clay"], Vector3(1.0, 0.8, 1.0), 8, 4)
	add_beam(m, Vector3(2.55, 0.0, -2.20), Vector3(2.62, 0.42, -2.24), 0.21, mats["log"], 9, 0.21)
	add_hanging(m, mats, Vector3(0.0, 3.34, 0.6), 0.0, seed_value * 17 + 3, 0.55)
	for i in range(2):
		add_skull_line(m, mats, Vector3(2.9, 2.9, 2.4), i, rng)
	charm_count += 1

	m.commit(host, String(spec.get("name", "BushHut")))
	return charm_count


## Plants crooked poles shoulder to shoulder along one wall and lashes every
## third one. `gap_from`/`gap_to` are wall-local `along` coordinates; a doorway
## passes its own span so no pole blocks the opening.
static func _stick_wall(m: Merged, mats: Dictionary, rng: RandomNumberGenerator,
		centre: Vector3, along: Vector3, outward: Vector3, length: float, eave: float,
		gap_from: float = 1.0e9, gap_to: float = 1.0e9) -> void:
	var count := int(length / 0.155)
	for i in range(count):
		var t := -length * 0.5 + (float(i) + 0.5) * (length / float(count)) + rng.randf_range(-0.07, 0.07)
		if t > gap_from and t < gap_to:
			continue
		if rng.randf() < 0.05:
			continue
		var base := centre + along * t + outward * rng.randf_range(-0.05, 0.05)
		base.y = rng.randf_range(-0.18, -0.06)
		var height := eave + rng.randf_range(-0.10, 0.34)
		var lean := Vector3(rng.randf_range(-0.07, 0.07), 0.0, rng.randf_range(-0.07, 0.07))
		var knee := base + Vector3(lean.x * 0.45, height * rng.randf_range(0.42, 0.62), lean.z * 0.45)
		var top := knee + Vector3(lean.x * 0.65 + rng.randf_range(-0.04, 0.04), height * 0.48,
			lean.z * 0.65 + rng.randf_range(-0.04, 0.04))
		var pole: Material = mats["bark"] if i % 5 == 0 else (mats["stake"] if i % 3 == 0
			else mats["log_dark"])
		add_beam(m, base, knee, rng.randf_range(0.060, 0.140), pole, 5, rng.randf_range(0.050, 0.110))
		add_beam(m, knee, top, rng.randf_range(0.040, 0.100), pole, 5, rng.randf_range(0.020, 0.060))
		if i % 3 == 0:
			add_ring(m, base + Vector3(0.0, height * rng.randf_range(0.30, 0.78), 0.0),
				rng.randf_range(0.0, TAU), 0.105, 0.140, mats["wicker"], 0.0, 8, 3)
	# withies woven through the uprights, at whatever height the hand landed
	for row in range(4):
		var y := 0.55 + float(row) * 0.72 + rng.randf_range(-0.12, 0.12)
		var segments := 3
		for s in range(segments):
			var t0 := -length * 0.5 + float(s) * length / float(segments) + rng.randf_range(0.0, 0.25)
			var t1 := t0 + length / float(segments) + rng.randf_range(-0.1, 0.3)
			if gap_to < 1.0e8 and t1 > gap_from and t0 < gap_to:
				continue
			var p0 := centre + along * t0 + outward * rng.randf_range(0.02, 0.07)
			var p1 := centre + along * t1 + outward * rng.randf_range(0.02, 0.07)
			add_beam(m, p0 + Vector3(0.0, y, 0.0), p1 + Vector3(0.0, y + rng.randf_range(-0.08, 0.08), 0.0),
				rng.randf_range(0.020, 0.030), mats["wicker"], 4)


## Jammed patches: stitched hides pinned between the sticks, and daub smeared
## into the gaps. Deliberately irregular, the work of people without carpentry.
static func _wall_patches(m: Merged, mats: Dictionary, rng: RandomNumberGenerator,
		centre: Vector3, along: Vector3, outward: Vector3, length: float,
		low: float, high: float, gap_from: float = 1.0e9, gap_to: float = 1.0e9) -> void:
	var yaw := atan2(-along.z, along.x)
	var tries := int(length / 0.72)
	for i in range(tries):
		var t := rng.randf_range(-length * 0.5 + 0.4, length * 0.5 - 0.4)
		if t > gap_from and t < gap_to:
			continue
		if rng.randf() < 0.16:
			continue
		var at := centre + along * t + outward * rng.randf_range(0.0, 0.07) \
			+ Vector3(0.0, rng.randf_range(low, high), 0.0)
		if rng.randf() < 0.45:
			add_box(m, Vector3(rng.randf_range(0.7, 1.6), rng.randf_range(0.5, 1.3), 0.025), at,
				mats["hide_dark"] if rng.randf() < 0.7 else mats["hide_wall"],
				yaw + rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.18, 0.18))
			# one stick pins the sheet to the wall
			add_beam(m, at - along * rng.randf_range(0.0, 0.32) - outward * 0.03,
				at + along * rng.randf_range(0.0, 0.32) + Vector3(0.0, 0.16, 0.0) - outward * 0.03,
				0.022, mats["log_dark"], 4)
		else:
			# a broad smear of daub pressed through the weave
			add_box(m, Vector3(rng.randf_range(0.8, 2.1), rng.randf_range(0.5, 1.4), 0.12), at,
				mats["daub"], yaw + rng.randf_range(-0.16, 0.16), 0.0, rng.randf_range(-0.18, 0.18))


## The roof: overlapping reed mats at slightly different pitches, ragged hems,
## crooked rafters poking out and a three-pole ridge lashed down with cords.
static func _thatch_roof(m: Merged, mats: Dictionary, solids: StaticBody3D, base: Transform3D,
		rng: RandomNumberGenerator, eave: float, ridge: float) -> void:
	var half := 3.95
	var pitch := atan2(ridge - eave, half)
	var slope := sqrt(half * half + (ridge - eave) * (ridge - eave))
	for side in SIDES:
		var mat_rows := 4
		for k in range(mat_rows):
			var z := -3.55 + (float(k) + 0.5) * (7.10 / float(mat_rows))
			var span := 7.10 / float(mat_rows) + rng.randf_range(0.10, 0.40)
			var roll := -side * (pitch + rng.randf_range(-0.055, 0.055))
			var at := Vector3(side * half * 0.5 + rng.randf_range(-0.06, 0.06),
				(eave + ridge) * 0.5 + rng.randf_range(-0.06, 0.06), z)
			add_box(m, Vector3(slope + rng.randf_range(0.05, 0.32), rng.randf_range(0.24, 0.34), span),
				at, mats["thatch"], 0.0, 0.0, roll)
			# ragged hem hanging off the eave
			add_box(m, Vector3(rng.randf_range(0.16, 0.34), rng.randf_range(0.16, 0.30), span + 0.04),
				Vector3(side * (half + rng.randf_range(0.02, 0.20)), eave - rng.randf_range(0.02, 0.16), z),
				mats["thatch_dark"], 0.0, 0.0, roll)
			# a crooked rafter poking out from under the hem
			add_beam(m, Vector3(side * 0.45, ridge - 0.10, z),
				Vector3(side * (half + rng.randf_range(0.18, 0.55)), eave - rng.randf_range(0.10, 0.30), z),
				0.05, mats["log_dark"], 5, 0.028)
		# cords pegged across the mats
		for k in range(4):
			var z := -3.0 + float(k) * 2.0
			add_beam(m, Vector3(side * 0.55, ridge - 0.30, z),
				Vector3(side * (half - 0.15), eave + 0.22, z), 0.028, mats["rag"], 4)
		add_collider(solids, base, Vector3(4.3, 0.30, 7.6),
			Vector3(side * half * 0.5, (eave + ridge) * 0.5, 0.0), 0.0, 0.0, -side * pitch)
	# ridge: three crooked poles lashed down, overhanging both gables
	for i in range(3):
		var off := Vector3(rng.randf_range(-0.09, 0.09), rng.randf_range(-0.05, 0.05), 0.0)
		add_beam(m, Vector3(0.0, ridge + 0.06, -4.55) + off, Vector3(0.0, ridge + 0.06, 4.55) + off,
			0.07, mats["log_dark"], 6, 0.055)
	for z in [-3.4, -1.7, 0.0, 1.7, 3.4]:
		add_ring(m, Vector3(0.0, ridge + 0.07, z), 0.0, 0.125, 0.165, mats["rag"], 0.0, 10, 3)


## Closes a gable end with leaned sticks and a sheet of hide, so the triangle
## reads patched rather than boarded.
static func _gable_fill(m: Merged, mats: Dictionary, rng: RandomNumberGenerator,
		eave: float, ridge: float, z: float) -> void:
	for i in range(10):
		var x := -3.15 + float(i) * 0.70 + rng.randf_range(-0.14, 0.14)
		var top_y := ridge - absf(x) * (ridge - eave) / 3.5
		add_beam(m, Vector3(x, eave - 0.30, z + rng.randf_range(-0.05, 0.05)),
			Vector3(x + rng.randf_range(-0.20, 0.20), top_y + rng.randf_range(-0.10, 0.12),
				z + rng.randf_range(-0.05, 0.05)),
			rng.randf_range(0.05, 0.09), mats["stake"] if i % 2 == 0 else mats["bark"], 5, 0.02)
	add_box(m, Vector3(rng.randf_range(1.8, 2.8), rng.randf_range(0.70, 1.20), 0.025),
		Vector3(0.0, (eave + ridge) * 0.52, z + signf(z) * 0.06), mats["hide_dark"],
		0.0, 0.0, rng.randf_range(-0.12, 0.12))


## A line of two small skulls hung on a thong inside a hut.
static func add_skull_line(m: Merged, mats: Dictionary, at: Vector3, index: int,
		rng: RandomNumberGenerator) -> void:
	var top := at + Vector3(0.0, 0.0, float(index) * 0.55)
	_rope(m, mats, top, top + Vector3(0.0, -0.42, 0.0), rng)
	add_skull(m, mats, top + Vector3(0.0, -0.56, 0.0), PI * 0.5, 0.42, false)


# ---------------------------------------------------------------------------
# round wattle dwelling
# ---------------------------------------------------------------------------

## The village's smaller dwellings: a ring of posts and wattle infill under a
## faceted reed cone, door gap on the local +Z face, charms under the eave.
static func wattle_hut(host: Node3D, mats: Dictionary, solids: StaticBody3D,
		radius: float = 2.2, wall_height: float = 2.35, seed: int = 3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var segments := 12
	var door_half := 0.18
	for i in range(segments):
		var a := TAU * float(i) / segments
		var gap := absf(angle_difference(a, 0.0))
		var at := Vector3(sin(a) * radius, 0.0, cos(a) * radius)
		# crooked posts; wattle infill and collision except at the door gap
		var tall := wall_height + rng.randf_range(-0.18, 0.26)
		var lean := Vector3(rng.randf_range(-0.10, 0.10), 0.0, rng.randf_range(-0.10, 0.10))
		var knee := at + Vector3(lean.x * 0.5, tall * 0.55, lean.z * 0.5)
		add_beam(m, at + Vector3(0.0, -0.12, 0.0), knee, rng.randf_range(0.075, 0.115),
			mats["log_dark"] if i % 2 == 0 else mats["stake"], 5, rng.randf_range(0.06, 0.085))
		add_beam(m, knee, knee + Vector3(lean.x * 0.6, tall * 0.45, lean.z * 0.6),
			rng.randf_range(0.055, 0.08), mats["log_dark"], 5, rng.randf_range(0.02, 0.045))
		if gap > door_half:
			# a box's local X runs tangent to the ring, so its yaw is the segment angle
			var panel_at := Vector3(sin(a) * (radius - 0.05), wall_height * 0.5, cos(a) * (radius - 0.05))
			add_box(m, Vector3(radius * TAU / segments * 1.02, wall_height * rng.randf_range(0.80, 0.92), 0.13),
				panel_at, mats["wattle"], a, 0.0, rng.randf_range(-0.05, 0.05))
			# lashings and a hide patch over every other bay
			add_ring(m, panel_at + Vector3(0.0, rng.randf_range(-0.4, 0.5), 0.0), a,
				0.10, 0.14, mats["wicker"], PI * 0.5, 8, 3)
			if i % 3 == 0:
				add_box(m, Vector3(radius * TAU / segments * 0.8, rng.randf_range(0.5, 0.9), 0.02),
					panel_at + Vector3(0.0, 0.2, 0.0), mats["hide_dark"], a, 0.0,
					rng.randf_range(-0.15, 0.15))
			add_collider(solids, base, Vector3(radius * TAU / segments * 1.02, wall_height, 0.28),
				panel_at, a)
	# stones tumbled round the foot
	for i in range(segments):
		var a := TAU * float(i) / segments + 0.26
		add_ball(m, rng.randf_range(0.14, 0.28), Vector3(sin(a) * (radius + 0.16), 0.10,
			cos(a) * (radius + 0.16)), mats["stone"], Vector3(1.0, 0.6, 1.0), 7, 4)
	# reed roof: three overlapping mats of different slope, pegged at the apex
	var cone_base := wall_height + 0.04
	var cone_h := radius * 1.95
	add_cone(m, radius + 0.20, cone_h, Vector3(0.0, cone_base + cone_h * 0.5, 0.0), mats["thatch"], 12, 0.02)
	add_cone(m, radius + 0.02, cone_h * 0.42, Vector3(0.0, cone_base + cone_h * 0.62, 0.0),
		mats["thatch_dark"], 11, 0.02)
	for i in range(3):
		var y := cone_base + cone_h * (0.22 + float(i) * 0.24)
		var r := (radius + 0.20) * (1.0 - (0.22 + float(i) * 0.24))
		add_ring(m, Vector3(0.0, y, 0.0), 0.0, r - 0.03, r + 0.03, mats["rag"], 0.0, 14, 3)
	# crooked posts poking out of the roof
	for i in range(5):
		var a := TAU * float(i) / 5.0 + 0.4
		var foot := Vector3(sin(a) * (radius + 0.1), cone_base + cone_h * 0.55, cos(a) * (radius + 0.1))
		add_beam(m, foot, foot + Vector3(sin(a) * 0.22, rng.randf_range(0.45, 0.85), cos(a) * 0.22),
			0.045, mats["log_dark"], 4, 0.015)
	add_beam(m, Vector3(0.0, cone_base + cone_h - 0.24, 0.0),
		Vector3(rng.randf_range(-0.12, 0.12), cone_base + cone_h + 0.62, rng.randf_range(-0.12, 0.12)),
		0.055, mats["log_dark"], 5, 0.02)
	add_skull(m, mats, Vector3(0.0, cone_base + cone_h * 0.92, 0.0), rng.randf_range(0.0, TAU), 0.5, true)
	# door flap and charms
	add_box(m, Vector3(1.05, 1.65, 0.04), Vector3(0.0, 0.86, radius + 0.02), mats["hide_dark"], 0.22, 0.0, 0.05)
	add_box(m, Vector3(0.10, 1.95, 0.14), Vector3(-0.62, 0.98, radius + 0.06), mats["timber"], 0.0, 0.0, 0.08)
	add_box(m, Vector3(0.10, 1.95, 0.14), Vector3(0.62, 0.98, radius + 0.06), mats["timber"], 0.0, 0.0, -0.08)
	add_hanging(m, mats, Vector3(-0.72, wall_height + 0.30, radius + 0.10), 0.4, seed * 13 + 1, 0.6)
	add_hanging(m, mats, Vector3(0.78, wall_height + 0.26, radius + 0.08), 2.1, seed * 13 + 2, 0.6)
	# a woodpile and a drying hide around the outside
	for i in range(4):
		var a := 2.3 + float(i) * 0.16
		add_beam(m, Vector3(sin(a) * (radius + 0.75), 0.12 + float(i) * 0.19, cos(a) * (radius + 0.75)),
			Vector3(sin(a) * (radius + 0.75) - 0.85, 0.12 + float(i) * 0.19, cos(a) * (radius + 0.75)),
			0.09, mats["log"], 6, 0.08)
	add_box(m, Vector3(1.10, 1.15, 0.03), Vector3(sin(1.2) * (radius + 0.42), 1.35, cos(1.2) * (radius + 0.42)),
		mats["hide"], 1.2, 0.0, 0.06)
	m.commit(host, "WattleDwelling")


# ---------------------------------------------------------------------------
# palisade, gate and totems
# ---------------------------------------------------------------------------

## A leaning stake wall around the village with gaps cut for the road gates.
## `sample` maps a world XZ point to its terrain height. Returns the stake count.
static func palisade(host: Node3D, mats: Dictionary, solids: StaticBody3D, centre: Vector2,
		radius: float, gaps: Array, sample: Callable, seed: int = 5) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var circumference := TAU * radius
	var count := int(circumference / 0.45)
	var stakes := 0
	var base := host.transform
	for i in range(count):
		var a := TAU * float(i) / float(count)
		if _gap_blocked(a, gaps):
			continue
		var point := centre + Vector2(sin(a), cos(a)) * radius
		var ground: Vector3 = sample.call(point.x, point.y)
		var height := rng.randf_range(2.15, 3.35)
		var lean := rng.randf_range(0.05, 0.13)
		var outward := Vector3(sin(a), 0.0, cos(a))
		var foot := ground + Vector3(rng.randf_range(-0.08, 0.08), -0.16, rng.randf_range(-0.08, 0.08))
		var top := foot + Vector3(0.0, height, 0.0) + outward * (lean * height)
		var split: Material = mats["log"] if i % 6 == 0 else mats["stake"]
		add_beam(m, foot, top, rng.randf_range(0.16, 0.23), split, 6, rng.randf_range(0.015, 0.045))
		var ring_at := foot + Vector3(0.0, height * rng.randf_range(0.55, 0.72), 0.0) + outward * lean
		add_ring(m, ring_at, a, 0.10, 0.14, mats["wicker"], 0.0, 8, 3)
		# every twenty-third stake wears a skull, facing out of the village
		if i % 23 == 0:
			add_skull(m, mats, top, a + PI, rng.randf_range(0.66, 0.86), i % 46 == 0)
		stakes += 1
	# two bound rails hold the wall together every few metres
	for i in range(0, count, 5):
		var a0 := TAU * float(i) / float(count)
		var a1 := TAU * float(i + 5) / float(count)
		var p0 := centre + Vector2(sin(a0), cos(a0)) * radius
		var p1 := centre + Vector2(sin(a1), cos(a1)) * radius
		if _gap_blocked(a0, gaps) or _gap_blocked(a1, gaps):
			continue
		var g0: Vector3 = sample.call(p0.x, p0.y)
		var g1: Vector3 = sample.call(p1.x, p1.y)
		for rail_y in [1.05, 1.95]:
			add_beam(m, g0 + Vector3(0.0, rail_y, 0.0), g1 + Vector3(0.0, rail_y, 0.0), 0.05,
				mats["wicker"], 5)
	m.commit(host, "VillagePalisade")
	# one collider per ~2.25 m of intact wall, aligned tangentially
	var step := maxi(1, int(2.25 / 0.45))
	for i in range(0, count, step):
		var a := TAU * float(i + step / 2) / float(count)
		if _gap_blocked(a, gaps):
			continue
		var point := centre + Vector2(sin(a), cos(a)) * radius
		var ground: Vector3 = sample.call(point.x, point.y)
		# a box's local X runs tangent to the ring, so its yaw is the ring angle
		add_collider(solids, base, Vector3(2.75, 2.85, 0.60),
			base.affine_inverse() * (ground + Vector3(0.0, 1.32, 0.0)), a)
	return stakes


static func _gap_blocked(angle_at: float, gaps: Array) -> bool:
	for gap_angle in gaps:
		if absf(angle_difference(angle_at, float(gap_angle))) < PI * 0.055:
			return true
	return false


## The village gate: two lashed posts with a bone lintel, an antler crown, a
## hanging hide banner and charms. The lane underneath stays open.
static func gate(host: Node3D, mats: Dictionary, solids: StaticBody3D, half_width: float = 3.8,
		height: float = 4.6, seed: int = 9) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	for side in SIDES:
		var foot := Vector3(side * half_width, 0.0, 0.0)
		var top := Vector3(side * (half_width + 0.20), height, 0.06)
		add_beam(m, foot, top, 0.26, mats["bark"], 8, 0.19)
		add_post_collider(solids, base, 0.32, height, foot)
		for i in range(2):
			add_ring(m, foot + Vector3(side * 0.16, 1.1 + float(i) * 1.5, 0.0), 0.0, 0.20, 0.26,
				mats["wicker"], 0.0, 12, 4)
		add_skull(m, mats, foot + Vector3(side * 0.16, 3.05, -0.22), side * 1.2, 0.95, true)
		add_hanging(m, mats, foot + Vector3(-side * 0.05, 3.62, -0.30), side * 0.5, seed * 7 + int(side), 0.75)
	add_beam(m, Vector3(-half_width - 0.26, height - 0.16, 0.02),
		Vector3(half_width + 0.26, height - 0.16, 0.02), 0.17, mats["bark"], 8, 0.15)
	add_beam(m, Vector3(-half_width + 1.1, height + 0.22, 0.0), Vector3(half_width - 1.1, height + 0.24, 0.02),
		0.09, mats["bark"], 6, 0.07)
	for x in [-2.2, -0.75, 0.75, 2.2]:
		add_antler(m, mats, Vector3(x, height + 0.14, 0.02), 0.2 + x * 0.12, 1.05)
	# a torn hide banner on a rope, painted with the wardens' mark
	add_beam(m, Vector3(-1.30, height - 0.30, 0.14), Vector3(1.30, height - 0.30, 0.14), 0.02, mats["rag"], 4)
	for strip in [
		{"x": -1.16, "w": 0.40, "h": 0.66, "roll": 0.05},
		{"x": -0.62, "w": 0.48, "h": 0.92, "roll": -0.03},
		{"x": 0.06, "w": 0.56, "h": 1.05, "roll": 0.02},
		{"x": 0.74, "w": 0.42, "h": 0.78, "roll": -0.05},
		{"x": 1.18, "w": 0.34, "h": 1.02, "roll": 0.06},
	]:
		var w: float = strip["w"]
		var strip_h: float = strip["h"]
		add_box(m, Vector3(w, strip_h, 0.022),
			Vector3(float(strip["x"]), height - 0.32 - strip_h * 0.5, 0.145),
			mats["hide_dark"], 0.0, 0.0, float(strip["roll"]))
		# a torn tail, so the sheet never reads as a sawn board
		add_box(m, Vector3(w * 0.55, strip_h * 0.30, 0.020),
			Vector3(float(strip["x"]) + w * 0.12,
				height - 0.32 - strip_h - strip_h * 0.13, 0.146),
			mats["hide_dark"], 0.0, 0.0, float(strip["roll"]) + 0.12)
	add_ring(m, Vector3(0.06, height - 0.92, 0.13), 0.0, 0.15, 0.21, mats["ochre"], PI * 0.5, 12, 4)
	add_box(m, Vector3(0.44, 0.05, 0.02), Vector3(0.06, height - 1.32, 0.13), mats["ochre"])
	add_box(m, Vector3(0.05, 0.34, 0.02), Vector3(0.06, height - 1.47, 0.13), mats["ochre"])
	for i in range(3):
		add_ball(m, 0.035, Vector3(-0.85 + float(i) * 0.18, height - 0.42, 0.14), mats["bone"],
			Vector3.ONE, 5, 3)
	# hanging bone charms across the lane, high enough to walk under
	for i in range(3):
		var x := -1.6 + float(i) * 1.6
		add_hanging(m, mats, Vector3(x, height - 0.12, 0.10), rng.randf_range(0.0, TAU),
			seed * 11 + i, 0.7)
	m.commit(host, "VillageGate")
	return 8


## A carved totem: stacked log sections with faces, paint bands, outflung arms
## carrying charms and an antler crown. `height` is total.
static func totem(host: Node3D, mats: Dictionary, solids: StaticBody3D, height: float = 4.6,
		seed: int = 4) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var sections := maxi(3, int(height / 1.05))
	var y := 0.0
	for i in range(sections):
		var r := 0.36 - float(i) * 0.045
		var h := height / float(sections)
		var yaw := rng.randf_range(-0.25, 0.25)
		add_cyl_section(m, r, h, Vector3(0.0, y + h * 0.5, 0.0), mats["log_dark"], yaw, 0.88)
		# painted tally dashes instead of a hoop, so it reads carved, not coopered
		for k in range(3):
			add_box(m, Vector3(0.05, 0.15, 0.03),
				Vector3(-0.10 + float(k) * 0.10, y + h * 0.86, -r * 0.94), mats["ochre"], yaw)
		# a carved warden face on both sides of every section
		for facing in SIDES:
			_totem_face(m, mats, y, h, r, facing)
		if i == sections / 2:
			for side in SIDES:
				add_antler(m, mats, Vector3(side * 0.26, y + h * 0.86, 0.02), side * 0.9, 0.8)
		y += h
	# arms and their charms
	for side in SIDES:
		var at := Vector3(side * 0.30, height * 0.62, 0.0)
		var tip := at + Vector3(side * 0.95, 0.34, -0.12)
		add_beam(m, at, tip, 0.075, mats["log_dark"], 6, 0.05)
		add_hanging(m, mats, tip + Vector3(0.0, -0.06, 0.0), 0.0, seed * 5 + int(side) + 2, 0.7)
	add_skull(m, mats, Vector3(0.0, height + 0.16, -0.10), PI, 1.05, true)
	add_antler(m, mats, Vector3(-0.12, height + 0.24, 0.04), 0.5, 1.1)
	add_antler(m, mats, Vector3(0.12, height + 0.24, 0.04), PI - 0.5, 1.1)
	for i in range(5):
		var a := TAU * float(i) / 5.0
		add_ball(m, 0.032, Vector3(cos(a) * 0.30, height * 0.34, sin(a) * 0.30), mats["bone"],
			Vector3.ONE, 5, 3)
	add_post_collider(solids, base, 0.44, height, Vector3.ZERO)
	m.commit(host, "VillageTotem")


static func add_cyl_section(m: Merged, radius: float, height: float, at: Vector3,
		material: Material, yaw: float, top_ratio: float = 0.96) -> void:
	m.add(_cyl_mesh(radius, radius * top_ratio, height, 9), _xf(at, yaw), material)


## One carved warden face on a totem section. `facing` is -1 for the front (-Z)
## and +1 for the back, so a totem reads from every side of the square.
static func _totem_face(m: Merged, mats: Dictionary, y: float, h: float, r: float,
		facing: float) -> void:
	var fz := -r * 0.90 * facing
	add_box(m, Vector3(r * 1.5, 0.09, 0.06), Vector3(0.0, y + h * 0.80, fz), mats["char"])
	add_ball(m, 0.085, Vector3(0.15, y + h * 0.66, fz), mats["ash"], Vector3(1.0, 0.8, 0.55), 7, 4)
	add_ball(m, 0.085, Vector3(-0.15, y + h * 0.66, fz), mats["ash"], Vector3(1.0, 0.8, 0.55), 7, 4)
	add_box(m, Vector3(0.10, 0.28, 0.10), Vector3(0.0, y + h * 0.50, fz + 0.03 * facing), mats["wattle"])
	add_box(m, Vector3(0.28, 0.11, 0.05), Vector3(0.0, y + h * 0.30, fz), mats["char"])
	for t in range(3):
		add_box(m, Vector3(0.026, 0.05, 0.026), Vector3(-0.07 + float(t) * 0.07, y + h * 0.24, fz),
			mats["bone"])
	add_box(m, Vector3(0.17, 0.05, 0.04), Vector3(0.0, y + h * 0.14, fz), mats["ochre"])


# ---------------------------------------------------------------------------
# sacrifice furniture, racks and effigies
# ---------------------------------------------------------------------------

## The wardens' offering ground: a blood-grooved slab, three leaning mark-stones,
## a gibbet with hooks and a bone ring on the ground.
static func sacrifice_ground(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 21) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	# slab on two stone legs
	add_box(m, Vector3(1.95, 0.22, 0.95), Vector3(0.0, 0.92, 0.0), mats["stone"])
	for x in [-0.72, 0.72]:
		add_box(m, Vector3(0.34, 0.82, 0.72), Vector3(x, 0.41, 0.0), mats["stone"])
	add_collider(solids, base, Vector3(1.95, 1.14, 0.95), Vector3(0.0, 0.57, 0.0))
	# carved grooves and the stain they drain
	for i in range(3):
		add_box(m, Vector3(1.55, 0.02, 0.07), Vector3(0.0, 1.04, -0.22 + float(i) * 0.22), mats["ochre"])
	add_box(m, Vector3(0.07, 0.02, 0.78), Vector3(0.55, 1.04, 0.0), mats["ochre"])
	add_ball(m, 0.13, Vector3(0.55, 1.00, 0.0), mats["ochre"], Vector3(1.0, 0.2, 1.0), 8, 4)
	# blade, bowl, skulls and ember candles on the slab
	add_box(m, Vector3(0.42, 0.02, 0.075), Vector3(-0.34, 1.06, 0.12), mats["iron"], 0.35)
	add_box(m, Vector3(0.13, 0.045, 0.055), Vector3(-0.10, 1.07, 0.20), mats["log_dark"], 0.35)
	add_ball(m, 0.15, Vector3(0.30, 1.10, -0.18), mats["clay"], Vector3(1.0, 0.55, 1.0), 10, 5)
	add_ball(m, 0.11, Vector3(0.30, 1.15, -0.18), mats["ochre"], Vector3(1.0, 0.3, 1.0), 8, 4)
	add_skull(m, mats, Vector3(-0.62, 1.14, -0.24), 0.6, 0.62, true)
	add_skull(m, mats, Vector3(0.66, 1.12, 0.26), -1.1, 0.56, false)
	for x in [-0.9, 0.9]:
		add_cyl_section(m, 0.055, 0.20, Vector3(x, 1.13, 0.30), mats["clay_dark"], 0.0)
		add_ball(m, 0.045, Vector3(x, 1.25, 0.30), mats["ember"], Vector3(1.0, 1.4, 1.0), 5, 4)
	# three leaning mark-stones, painted with ochre bands
	for i in range(3):
		var a := -1.9 + float(i) * 1.35
		var lean := Vector2(sin(a), cos(a)) * 0.30
		var foot := Vector3(sin(a) * 2.35, 0.0, cos(a) * 2.35 - 0.4)
		var tall := 1.95 + float(i) * 0.28
		add_box(m, Vector3(0.58, tall * 0.55, 0.40), foot + Vector3(lean.x * 0.6, tall * 0.28, lean.y * 0.6),
			mats["stone"], a, 0.0, -0.07 + float(i) * 0.05)
		add_box(m, Vector3(0.42, tall * 0.55, 0.30), foot + Vector3(lean.x * 1.2, tall * 0.75, lean.y * 1.2),
			mats["stone"], a, 0.0, -0.07 + float(i) * 0.05)
		for j in range(2):
			add_box(m, Vector3(0.60, 0.085, 0.40), foot + Vector3(lean.x * 1.3, 0.85 + float(j) * 0.62,
				lean.y * 1.3), mats["ochre"], a, 0.0, -0.07 + float(i) * 0.05)
		add_collider(solids, base, Vector3(0.58, tall, 0.4), foot + Vector3(0.0, tall * 0.5, 0.0), a)
	# gibbet frame with hooks
	var gib_a := Vector3(-2.5, 0.0, 1.5)
	var gib_b := Vector3(2.5, 0.0, 1.5)
	add_beam(m, gib_a, gib_a + Vector3(0.06, 3.05, 0.0), 0.12, mats["log_dark"], 6, 0.09)
	add_beam(m, gib_b, gib_b + Vector3(-0.04, 3.05, 0.0), 0.12, mats["log_dark"], 6, 0.09)
	add_beam(m, gib_a + Vector3(0.0, 2.95, 0.0), gib_b + Vector3(0.0, 2.98, 0.0), 0.10, mats["log_dark"], 6, 0.09)
	for x in [-1.5, 0.0, 1.5]:
		var hook := Vector3(x, 2.90, 1.5)
		add_ring(m, hook, 0.0, 0.07, 0.10, mats["iron"], PI * 0.5, 8, 3)
		add_beam(m, hook, hook + Vector3(0.0, -0.35, 0.0), 0.02, mats["iron"], 4)
		if x != 0.0:
			_rib_bundle(m, mats, hook + Vector3(0.0, -0.35, 0.0), rng)
		else:
			add_box(m, Vector3(0.26, 0.85, 0.03), hook + Vector3(0.0, -0.80, 0.0), mats["hide_dark"], 0.0, 0.0, 0.12)
	add_collider(solids, base, Vector3(5.3, 3.1, 0.5), Vector3(0.0, 1.55, 1.5))
	# bone ring pressed into the ground
	add_ring(m, Vector3(0.0, 0.06, -1.5), 0.0, 1.55, 1.68, mats["bone"], 0.0, 20, 5)
	for i in range(9):
		var a := TAU * float(i) / 9.0
		var at := Vector3(cos(a) * 1.85, 0.06, sin(a) * 1.85 - 1.5)
		add_beam(m, at, at + Vector3(cos(a) * 0.34, 0.0, sin(a) * 0.34), 0.035, mats["bone"], 5, 0.02)
	# a low ember glow so the slab reads at night
	var light := OmniLight3D.new()
	light.name = "OfferingGlow"
	light.position = Vector3(0.0, 1.3, 0.0)
	light.light_color = Color("ff9a5c")
	light.light_energy = 0.7
	light.omni_range = 6.0
	host.add_child(light)
	m.commit(host, "SacrificeGround")


## A drying rack: two posts, a lashed rail, hanging hides and meat strips.
static func drying_rack(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 31) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	var span := 2.15
	for side in SIDES:
		var foot := Vector3(side * span * 0.5, 0.0, 0.0)
		add_beam(m, foot, foot + Vector3(side * 0.10, 2.28, 0.04), 0.075, mats["log_dark"], 6, 0.05)
		add_post_collider(solids, base, 0.14, 2.2, foot)
	add_beam(m, Vector3(-span * 0.5 - 0.05, 2.18, 0.0), Vector3(span * 0.5 + 0.05, 2.20, 0.04),
		0.06, mats["log_dark"], 6, 0.055)
	# stretching frames: hides, then strips of meat and a pair of snare loops
	add_box(m, Vector3(0.72, 0.92, 0.025), Vector3(-0.62, 1.70, 0.02), mats["hide"], 0.0, 0.0, 0.04)
	add_box(m, Vector3(0.28, 0.34, 0.02), Vector3(-0.62, 1.86, -0.05), mats["hide_dark"], 0.0, 0.0, 0.2)
	add_box(m, Vector3(0.62, 0.82, 0.025), Vector3(0.66, 1.74, 0.04), mats["hide_dark"], 0.0, 0.0, -0.05)
	for i in range(4):
		add_box(m, Vector3(0.10, 0.44, 0.02), Vector3(-0.12 + float(i) * 0.16, 1.90, 0.02),
			mats["ochre"], 0.0, 0.0, rng.randf_range(-0.15, 0.15))
	add_ring(m, Vector3(0.20, 2.02, 0.06), 0.0, 0.05, 0.075, mats["rag"], PI * 0.5, 8, 3)
	add_ring(m, Vector3(0.34, 1.98, 0.06), 0.0, 0.05, 0.075, mats["rag"], PI * 0.5, 8, 3)
	m.commit(host, "DryingRack")


## A bound wicker effigy on a stake: straw body, outflung arms, horned skull.
static func effigy(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 41) -> void:
	var m := Merged.new()
	var base := host.transform
	add_beam(m, Vector3(0.0, 0.0, 0.0), Vector3(0.04, 2.85, 0.02), 0.075, mats["log_dark"], 6, 0.055)
	add_post_collider(solids, base, 0.20, 2.6, Vector3.ZERO)
	add_cone(m, 0.34, 1.15, Vector3(0.0, 1.30, 0.0), mats["wicker"], 9, 0.62)
	add_ball(m, 0.26, Vector3(0.0, 2.02, 0.0), mats["wicker"], Vector3(1.0, 0.86, 1.0), 9, 5)
	for side in SIDES:
		add_beam(m, Vector3(side * 0.18, 1.86, 0.0), Vector3(side * 0.78, 2.26, -0.10),
			0.075, mats["wicker"], 5, 0.05)
		add_box(m, Vector3(0.16, 0.30, 0.14), Vector3(side * 0.82, 2.14, -0.12), mats["wicker"], 0.0, 0.0, side * 0.2)
	for i in range(3):
		add_ring(m, Vector3(0.0, 0.95 + float(i) * 0.42, 0.0), 0.0, 0.30 - float(i) * 0.03,
			0.35 - float(i) * 0.03, mats["rag"], 0.0, 12, 4)
	add_skull(m, mats, Vector3(0.0, 2.42, -0.02), PI, 0.9, true)
	add_antler(m, mats, Vector3(-0.10, 2.50, 0.02), 0.6, 0.85)
	add_antler(m, mats, Vector3(0.10, 2.50, 0.02), PI - 0.6, 0.85)
	for i in range(4):
		var a := TAU * float(i) / 4.0 + 0.4
		add_ball(m, 0.09, Vector3(cos(a) * 0.42, 0.08, sin(a) * 0.42), mats["stone"], Vector3(1.0, 0.7, 1.0), 6, 4)
	m.commit(host, "BoundEffigy")


## A dead, crooked tree left standing for the charms: bare bark, split leaning
## trunk, splayed roots and charms hung from every branch tip. Returns how many
## charms it carries.
static func gallows_tree(m: Merged, mats: Dictionary, solids: StaticBody3D, at: Vector3,
		yaw: float, seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	var height := rng.randf_range(5.2, 7.0)
	var knee := Vector3(rng.randf_range(-0.26, 0.26), height * 0.42, rng.randf_range(-0.24, 0.24))
	var crown := knee + Vector3(rng.randf_range(-0.42, 0.42), height * 0.58, rng.randf_range(-0.36, 0.36))
	add_beam(m, Vector3.ZERO, knee, 0.42, mats["bark"], 9, 0.30)
	add_beam(m, knee, crown, 0.30, mats["bark"], 8, 0.09)
	# splayed roots and a few snapped stubs up the trunk
	for i in range(5):
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var tip := Vector3(cos(a) * rng.randf_range(0.70, 1.15), rng.randf_range(0.02, 0.18),
			sin(a) * rng.randf_range(0.70, 1.15))
		add_beam(m, Vector3(0.0, 0.20, 0.0), tip, 0.16, mats["bark"], 5, 0.03)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.5
		var root := knee.lerp(crown, 0.15 + float(i) * 0.28)
		add_beam(m, root, root + Vector3(cos(a) * 0.34, 0.18, sin(a) * 0.34), 0.10, mats["bark"], 5, 0.04)
	var tips: Array[Vector3] = []
	var branch_count := rng.randi_range(4, 5)
	for i in range(branch_count):
		var along := 0.16 + float(i) / float(branch_count) * 0.78
		var root := knee.lerp(crown, along)
		var a := TAU * float(i) / float(branch_count) + rng.randf_range(-0.5, 0.5)
		var length := rng.randf_range(1.3, 2.6)
		var mid := root + Vector3(cos(a) * length * 0.55, rng.randf_range(0.10, 0.45),
			sin(a) * length * 0.55)
		var tip := mid + Vector3(cos(a) * length * 0.55, rng.randf_range(-0.45, 0.08),
			sin(a) * length * 0.55)
		add_beam(m, root, mid, 0.15, mats["bark"], 6, 0.09)
		add_beam(m, mid, tip, 0.09, mats["bark"], 5, 0.028)
		# one fork per branch, so the silhouette is a dead crown, not a pole
		add_beam(m, mid.lerp(tip, 0.45), mid.lerp(tip, 0.45) + Vector3(cos(a + 0.9) * 0.55,
			0.22, sin(a + 0.9) * 0.55), 0.06, mats["bark"], 4, 0.02)
		tips.append(tip)
	var charms := 0
	for i in range(tips.size()):
		add_hanging(m, mats, tips[i] + Vector3(0.0, -0.06, 0.0), rng.randf_range(0.0, TAU),
			seed * 37 + i, rng.randf_range(0.85, 1.15))
		charms += 1
	if rng.randf() < 0.6:
		add_hanging(m, mats, crown + Vector3(0.0, 0.05, 0.0), rng.randf_range(0.0, TAU),
			seed * 53 + 1, 0.95)
		charms += 1
	m.group = saved
	add_post_collider(solids, _xf(at, yaw), 0.46, 3.0, Vector3.ZERO)
	return charms


## A run of skull-capped stakes, the village's boundary omen.
static func skull_stakes(m: Merged, mats: Dictionary, at: Vector3, yaw: float,
		count: int = 5, spacing: float = 0.95, seed: int = 51) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	for i in range(count):
		var offset := Vector3(float(i) * spacing - float(count - 1) * spacing * 0.5,
			0.0, rng.randf_range(-0.16, 0.16))
		var height := rng.randf_range(1.35, 1.95)
		add_beam(m, offset, offset + Vector3(rng.randf_range(-0.08, 0.08), height, rng.randf_range(-0.08, 0.08)),
			0.055, mats["log_dark"], 5, 0.04)
		add_skull(m, mats, offset + Vector3(0.0, height + 0.10, 0.0), rng.randf_range(0.0, TAU),
				rng.randf_range(0.62, 0.85), i % 2 == 0)
		add_ring(m, offset + Vector3(0.0, height * 0.55, 0.0), 0.0, 0.06, 0.085, mats["ochre"],
			0.0, 8, 3)
	m.group = saved


## A trader's frame where the market awning stood: two posts, a hide awning and
## the charms hanging from its edge.
static func trader_frame(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 61) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	for x in [-2.0, 2.0]:
		for z in [-1.5, 1.5]:
			add_beam(m, Vector3(x, 0.0, z), Vector3(x * 0.96, 2.95, z * 0.96), 0.09, mats["log_dark"], 6, 0.07)
			add_post_collider(solids, base, 0.16, 2.8, Vector3(x, 0.0, z))
	for z in [-1.5, 1.5]:
		add_beam(m, Vector3(-2.0, 2.86, z), Vector3(2.0, 2.90, z), 0.07, mats["log_dark"], 5)
	for x in [-2.0, 2.0]:
		add_beam(m, Vector3(x, 2.86, -1.5), Vector3(x, 2.90, 1.5), 0.07, mats["log_dark"], 5)
	add_box(m, Vector3(4.6, 0.07, 3.6), Vector3(0.0, 3.02, 0.0), mats["hide_dark"], 0.0, 0.0, 0.06)
	for i in range(6):
		add_box(m, Vector3(rng.randf_range(0.22, 0.42), rng.randf_range(0.26, 0.50), 0.02),
			Vector3(-2.0 + float(i) * 0.8, 2.80, 1.74), mats["hide_dark"], 0.0, 0.0,
			rng.randf_range(-0.16, 0.16))
	# the stall's goods: pots, bundled roots, a hide roll, a bone tally
	for i in range(4):
		add_ball(m, 0.15 - float(i) * 0.015, Vector3(-1.3 + float(i) * 0.34, 0.98, -0.9),
			mats["clay"] if i % 2 == 0 else mats["clay_dark"], Vector3(1.0, 0.85, 1.0), 9, 5)
	add_box(m, Vector3(0.9, 0.5, 0.6), Vector3(1.25, 0.25, -0.9), mats["log_dark"])
	add_box(m, Vector3(0.34, 0.26, 0.44), Vector3(1.15, 0.62, -0.90), mats["wicker"], 0.3)
	add_beam(m, Vector3(0.4, 0.9, 0.9), Vector3(1.8, 1.02, 0.6), 0.13, mats["hide_dark"], 7, 0.11)
	for i in range(5):
		var x := -1.8 + float(i) * 0.9
		add_hanging(m, mats, Vector3(x, 2.90, 1.66), rng.randf_range(0.0, TAU), seed * 3 + i, 0.5)
	add_skull(m, mats, Vector3(1.35, 1.14, -0.35), 2.4, 0.6, false)
	m.commit(host, "TraderFrame")


# ---------------------------------------------------------------------------
# small dressing props
# ---------------------------------------------------------------------------

## A chopping block with the axe left in it and a scatter of bone chips.
static func chopping_block(m: Merged, mats: Dictionary, at: Vector3, yaw: float) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	m.add(_cyl_mesh(0.42, 0.38, 0.58, 10), _xf(Vector3(0.0, 0.29, 0.0)), mats["log"])
	add_ring(m, Vector3(0.0, 0.55, 0.0), 0.0, 0.36, 0.42, mats["log_dark"], 0.0, 12, 4)
	add_beam(m, Vector3(0.02, 0.55, 0.0), Vector3(0.24, 1.05, -0.14), 0.035, mats["log_dark"], 5, 0.03)
	add_box(m, Vector3(0.30, 0.22, 0.035), Vector3(0.14, 0.62, -0.02), mats["iron"], 0.5, 0.0, 0.2)
	for i in range(6):
		var a := TAU * float(i) / 6.0 + 0.3
		add_box(m, Vector3(0.07, 0.03, 0.05), Vector3(cos(a) * 0.72, 0.03, sin(a) * 0.66), mats["bone"], a)
	m.group = saved


## A witch's cauldron on a tripod, with the fire still burning under it.
static func cauldron(m: Merged, mats: Dictionary, at: Vector3, yaw: float, s: float = 1.0) -> void:
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, s))
	var apex := Vector3(0.0, 2.05, 0.0)
	for i in range(3):
		var a := TAU * float(i) / 3.0
		add_beam(m, Vector3(cos(a) * 0.95, 0.0, sin(a) * 0.95), apex, 0.05, mats["log_dark"], 5, 0.035)
	add_ball(m, 0.075, apex, mats["rag"], Vector3.ONE, 5, 4)
	add_beam(m, apex + Vector3(0.0, -0.04, 0.0), Vector3(0.0, 1.18, 0.0), 0.014, mats["iron"], 4)
	add_ball(m, 0.40, Vector3(0.0, 0.98, 0.0), mats["iron"], Vector3(1.0, 0.72, 1.0), 12, 7)
	add_ring(m, Vector3(0.0, 1.14, 0.0), 0.0, 0.36, 0.40, mats["iron"], 0.0, 14, 5)
	add_ball(m, 0.30, Vector3(0.0, 1.10, 0.0), mats["char"], Vector3(1.0, 0.22, 1.0), 10, 5)
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.5
		add_ball(m, 0.055, Vector3(cos(a) * 0.30, 0.10, sin(a) * 0.30), mats["ember"],
			Vector3(1.0, 0.6, 1.0), 5, 4)
	m.group = saved


## A heap of picked bones and a couple of cracked pots.
static func bone_heap(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 71) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	add_ball(m, 0.24, Vector3(0.0, 0.10, 0.0), mats["ash"], Vector3(1.5, 0.4, 1.2), 8, 4)
	for i in range(7):
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		var at_local := Vector3(cos(a) * rng.randf_range(0.05, 0.34), rng.randf_range(0.12, 0.26),
			sin(a) * rng.randf_range(0.05, 0.30))
		var tip := at_local + Vector3(rng.randf_range(-0.30, 0.30), rng.randf_range(-0.10, 0.02),
			rng.randf_range(-0.28, 0.28))
		add_beam(m, at_local, tip, 0.035, mats["bone"], 5, 0.022)
	add_skull(m, mats, Vector3(-0.20, 0.20, 0.14), rng.randf_range(0.0, TAU), 0.62, true)
	add_ball(m, 0.13, Vector3(0.28, 0.10, -0.16), mats["clay_dark"], Vector3(1.0, 0.55, 1.0), 8, 4)
	m.group = saved


## A stack of firewood under a lean-to rail.
static func woodpile(host: Node3D, mats: Dictionary, solids: StaticBody3D, seed: int = 81) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := Merged.new()
	var base := host.transform
	for row in range(3):
		for i in range(5):
			var y := 0.12 + float(row) * 0.21
			var x := -0.75 + float(i) * 0.37 + float(row % 2) * 0.16
			add_beam(m, Vector3(x, y, -1.05), Vector3(x, y, 1.05), 0.095, mats["log"], 6, 0.088)
	add_beam(m, Vector3(-1.05, 0.0, -1.0), Vector3(-1.05, 1.65, -1.0), 0.07, mats["log_dark"], 5, 0.05)
	add_beam(m, Vector3(1.05, 0.0, 1.0), Vector3(1.05, 1.65, 1.0), 0.07, mats["log_dark"], 5, 0.05)
	add_box(m, Vector3(2.3, 0.07, 2.2), Vector3(0.0, 1.68, 0.0), mats["hide_dark"], 0.0, 0.0, 0.05)
	add_collider(solids, base, Vector3(2.2, 0.9, 2.2), Vector3(0.0, 0.45, 0.0))
	m.commit(host, "Woodpile")


## A scatter of stakes, racks and pot stacks that keeps the village lived-in.
static func pot_stack(m: Merged, mats: Dictionary, at: Vector3, yaw: float, seed: int = 91) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var saved := m.push(_xf(at, yaw, 0.0, 0.0, 1.0))
	for i in range(4):
		var r := rng.randf_range(0.10, 0.19)
		var p := Vector3(rng.randf_range(-0.28, 0.28), r * 0.85, rng.randf_range(-0.22, 0.22))
		add_ball(m, r, p, mats["clay"] if i % 2 == 0 else mats["clay_dark"], Vector3(1.0, 0.85, 1.0), 9, 5)
		add_ring(m, p + Vector3(0.0, r * 0.72, 0.0), 0.0, r * 0.52, r * 0.74,
			mats["clay_dark"], 0.0, 10, 4)
	add_ball(m, 0.15, Vector3(-0.05, 0.42, 0.02), mats["clay"], Vector3(1.0, 0.8, 1.0), 9, 5)
	m.group = saved
