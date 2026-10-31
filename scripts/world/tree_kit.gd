class_name TreeKit
extends RefCounted
## Procedural, deterministic tree meshes for the stylised woodland.
##
## Every tree is a tapered tube trunk with real branch geometry plus (for leafy
## forms) alpha-scissored leaf cards sampled from the 2x2 foliage atlases. Mesh
## origin sits at the ground, +Y is up. Leaf cards store UV2 = (wind phase,
## wind weight) and darken toward the crown interior through vertex colour.
##
## Species keys consumed here: `form`, `height`, `trunk`, `crown`, `leaves`,
## `wind`, `variants`. See WorldStyle.default_trees(). Adding a species with one
## of the four forms needs no changes in this file.
##
## Budgets (triangles, trunk + leaves): broadleaf 1400, conifer 900, birch 800,
## snag 700. The current generators sit far under them, leaving room for extra
## cards/branches when art direction asks for denser silhouettes.

const BARK_UV_METRES := 2.0
const TRUNK_SIDES := 8
const BRANCH_SIDES := 5

## The trunk's own profile, as a fraction of the species' base radius at a given
## height. Every trunk is the same six-ring tube: a flare that dies out inside the
## first metre, a nearly straight lower run, then the taper to the tip. The mesh
## and the collision are both cut from these numbers, so the bark a body meets is
## the bark that is drawn - a collider built from a species table can be neither.
const TRUNK_RINGS := 6
const TRUNK_RING_CURVE := 0.94
const TRUNK_TAPER_CURVE := 0.9
const TRUNK_TIP_TAPER := 0.22
const SNAG_TIP_TAPER := 0.34
const TRUNK_FLARE := 0.24
const TRUNK_FLARE_FALLOFF := 2.4

const BUDGETS := {
	"broadleaf": 1400,
	"conifer": 900,
	"birch": 800,
	"snag": 700,
}


## Builds `species.variants` distinct meshes. Same species + seed always yields
## identical vertex data (RandomNumberGenerator, seeded per variant).
static func build_variants(species: Dictionary, seed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var variant_count := maxi(1, int(species.get("variants", 3)))
	for index in range(variant_count):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + index * 104729
		result.append(_build_one(species, rng))
	return result


static func _build_one(species: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var form := String(species.get("form", "broadleaf"))
	var dims := _dimensions(species, rng, form)
	var trunk_data := _build_trunk(species, rng, dims, form)
	var trunk_mesh: ArrayMesh = trunk_data["mesh"]
	var tips: Array[Vector3] = trunk_data["tips"]
	var leaves_mesh: ArrayMesh = null
	match form:
		"conifer":
			leaves_mesh = _conifer_leaves(species, rng, dims)
		"birch":
			leaves_mesh = _birch_leaves(species, rng, dims, tips)
		"snag":
			# Dead trees stay bare: the texture contract has no snag foliage, and
			# the bare branch silhouette is the point of the form.
			leaves_mesh = null
		_:
			leaves_mesh = _broadleaf_leaves(species, rng, dims, tips)

	var box: AABB = trunk_mesh.get_aabb()
	if leaves_mesh != null:
		box = box.merge(leaves_mesh.get_aabb())
	var height := maxf(box.end.y, 0.1)
	var radius := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
	return {
		"trunk": trunk_mesh,
		"leaves": leaves_mesh,
		"height": height,
		"radius": maxf(radius, 0.1),
		# The tube's own numbers, kept beside the mesh: `radius` above is the whole
		# trunk mesh's box, which carries the branch tips out to the crown and says
		# nothing about where the bark is. Trunk collision and its planting rule
		# read these instead.
		"base_radius": float(dims["base_radius"]),
		"trunk_height": float(dims["trunk_height"]),
		"form": form,
		"bark": String(species.get("bark", "bark_oak")),
		"leaves_texture": String(species.get("leaves", "")),
		"wind": species.get("wind", Vector2(0.15, 1.0)),
	}


## The flare the trunk's first rings are built with: widest at the ground, gone
## inside the first metre.
static func _ring_flare(y: float) -> float:
	return 1.0 + TRUNK_FLARE * exp(-y * TRUNK_FLARE_FALLOFF)


## How far the trunk has closed in at ring `t` (0 at the ground, 1 at the tip).
static func _ring_taper(t: float, form: String) -> float:
	return lerpf(1.0, SNAG_TIP_TAPER if form == "snag" else TRUNK_TIP_TAPER,
		pow(t, TRUNK_TAPER_CURVE))


## Where ring `index`'s vertices sit above the tree's own origin.
static func _ring_height(index: int, trunk_height: float) -> float:
	if index <= 0:
		return 0.0
	return trunk_height * pow(float(index) / float(TRUNK_RINGS - 1), TRUNK_RING_CURVE)


## The radius of the drawn trunk at local height `y`, in the mesh's own units.
##
## The tube is a straight run between its ring vertices, so this is the surface the
## bark shows. It is what a collider and a planting rule have to ask, because the
## species table's `trunk` is the taper before the flare, and a trunk mesh's own
## box is the branch tips.
static func trunk_radius_at(variant: Dictionary, y: float) -> float:
	var trunk_height := float(variant.get("trunk_height", 0.0))
	var base_radius := float(variant.get("base_radius", 0.0))
	if trunk_height <= 0.0 or base_radius <= 0.0:
		return 0.0
	var form := String(variant.get("form", "broadleaf"))
	y = clampf(y, 0.0, trunk_height)
	var low_y := 0.0
	var low_radius := base_radius * _ring_taper(0.0, form) * _ring_flare(0.0)
	for index in range(1, TRUNK_RINGS):
		var high_y := _ring_height(index, trunk_height)
		var high_radius := base_radius * _ring_taper(float(index) / float(TRUNK_RINGS - 1), form) \
			* _ring_flare(high_y)
		if y <= high_y:
			return lerpf(low_radius, high_radius, (y - low_y) / maxf(high_y - low_y, 0.000001))
		low_y = high_y
		low_radius = high_radius
	return low_radius


## The bark's footprint on the ground, scaled: the number a planting rule keeps off
## the walked line and a path steers around.
static func trunk_footprint(variant: Dictionary, scale: float) -> float:
	return trunk_radius_at(variant, 0.0) * scale


## The bark a body meets, as collision: one cylinder on the trunk's own footprint.
##
## The species table's taper is the tube *before* its flare, and a trunk mesh's own
## box is the branch tips out at the crown - a collider cut from either is not the
## tree. The nominal radius let a body's boots stand inside the flare (an ironoak's
## bark is a fifth wider at the ground than its taper says) and on the lane the box
## made every ironoak a two-metre invisible pillar with a tree painted in the middle
## of it. The cover anchor is measured off this surface at knee height, which is why
## the report was that the sticky points were out of proportion to the trees that
## were rendered: the cover anchor now stands on the bark's widest drawn ring, out
## at the one radius a standing capsule can lean on.
static func add_trunk_solids(parent: Node3D, at: Vector3, variant: Dictionary, scale: float) -> void:
	var top := float(variant.get("trunk_height", 0.0)) * scale
	if parent == null or top <= 0.0:
		return
	_trunk_solid(parent, at + Vector3(0.0, top * 0.5, 0.0), trunk_footprint(variant, scale), top)


static func _trunk_solid(parent: Node3D, centre: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.02)
	shape.height = maxf(height, 0.05)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = centre
	parent.add_child(collision)


static func _dimensions(species: Dictionary, rng: RandomNumberGenerator, form: String) -> Dictionary:
	var height_range: Vector2 = species.get("height", Vector2(8.0, 12.0))
	var height := rng.randf_range(height_range.x, height_range.y)
	var trunk_spec: Vector2 = species.get("trunk", Vector2(0.04, 0.62))
	var crown_spec: Vector2 = species.get("crown", Vector2(0.28, 0.5))
	var base_radius := maxf(0.09, height * trunk_spec.x)
	var trunk_height := height * clampf(trunk_spec.y, 0.25, 1.0)
	var crown_radius := maxf(0.5, height * crown_spec.x)
	var crown_height := height * clampf(crown_spec.y, 0.12, 0.95)
	# Slight lean keeps a forest from looking extruded; the top displaces by at
	# most ~2% of the tree height.
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * height * 0.018
	return {
		"height": height,
		"trunk_height": trunk_height,
		"base_radius": base_radius,
		"crown_radius": crown_radius,
		"crown_height": crown_height,
		"crown_base": height - crown_height,
		"lean": lean,
	}


static func _build_trunk(species: Dictionary, rng: RandomNumberGenerator, dims: Dictionary, form: String) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height: float = dims["height"]
	var trunk_height: float = dims["trunk_height"]
	var base_radius: float = dims["base_radius"]
	var crown_radius: float = dims["crown_radius"]
	var crown_height: float = dims["crown_height"]
	var crown_base: float = dims["crown_base"]

	# Six rings: a flared root ring, a nearly straight lower trunk, then a taper.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for ring_index in range(TRUNK_RINGS):
		var t := float(ring_index) / float(TRUNK_RINGS - 1)
		var y := _ring_height(ring_index, trunk_height)
		path.append(_spine_at(y, dims))
		radii.append(base_radius * _ring_taper(t, form) * _ring_flare(y))
	_add_tube(st, path, radii, TRUNK_SIDES, true, BARK_UV_METRES, Color.WHITE)

	var branch_count := 3
	match form:
		"broadleaf":
			branch_count = rng.randi_range(3, 5)
		"conifer":
			branch_count = 3
		"birch":
			branch_count = rng.randi_range(2, 3)
		"snag":
			branch_count = rng.randi_range(4, 6)

	var tips: Array[Vector3] = []
	for branch_index in range(branch_count):
		var angle := TAU * float(branch_index) / float(branch_count) + rng.randf_range(-0.5, 0.5)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var start_t: float
		var end := Vector3.ZERO
		var branch_radius := base_radius * 0.3
		var branch_y := 0.0
		var branch_reach := 0.0
		var branch_length := 0.0
		match form:
			"conifer":
				start_t = rng.randf_range(0.42, 0.7)
				branch_y = lerpf(crown_base + crown_height * 0.12, height * 0.8, rng.randf())
				branch_reach = crown_radius * rng.randf_range(0.3, 0.55)
				end = Vector3(outward.x * branch_reach, branch_y, outward.z * branch_reach)
				branch_radius = base_radius * 0.15
			"snag":
				start_t = rng.randf_range(0.25, 0.82)
				branch_length = height * rng.randf_range(0.16, 0.34)
				branch_y = clampf(trunk_height * start_t + rng.randf_range(-0.8, 1.2), 0.6, height * 0.97)
				end = Vector3(outward.x * branch_length, branch_y, outward.z * branch_length)
				branch_radius = base_radius * rng.randf_range(0.24, 0.4)
			"birch":
				start_t = rng.randf_range(0.5, 0.86)
				branch_y = clampf(crown_base + crown_height * rng.randf_range(0.2, 0.8), 0.8, height * 0.95)
				branch_reach = crown_radius * rng.randf_range(0.4, 0.85)
				end = Vector3(outward.x * branch_reach, branch_y, outward.z * branch_reach)
				branch_radius = base_radius * rng.randf_range(0.24, 0.36)
			_:
				start_t = rng.randf_range(0.45, 0.78)
				branch_y = clampf(crown_base + crown_height * rng.randf_range(0.1, 0.7), 0.8, height * 0.94)
				branch_reach = crown_radius * rng.randf_range(0.38, 0.78)
				end = Vector3(outward.x * branch_reach, branch_y, outward.z * branch_reach)
				branch_radius = base_radius * rng.randf_range(0.26, 0.4)
		var start := _spine_at(trunk_height * start_t, dims)
		var mid := start.lerp(end, 0.5) + Vector3(0.0, rng.randf_range(0.06, 0.35), 0.0)
		var branch_path := PackedVector3Array([start, mid, end])
		var branch_radii := PackedFloat32Array([branch_radius, branch_radius * 0.55, maxf(0.012, branch_radius * 0.07)])
		_add_tube(st, branch_path, branch_radii, BRANCH_SIDES, true, BARK_UV_METRES, Color.WHITE)
		tips.append(end)

		# Snags fork: a second gnarly branch from the middle reads as weathered.
		if form == "snag" and rng.randf() < 0.65:
			var fork_angle := angle + rng.randf_range(-1.1, 1.1)
			var fork_out := Vector3(cos(fork_angle), 0.0, sin(fork_angle))
			var fork_start := mid
			var fork_end := fork_start + fork_out * (height * rng.randf_range(0.1, 0.2)) + Vector3(0.0, rng.randf_range(-0.4, 0.7), 0.0)
			fork_end.y = clampf(fork_end.y, 0.5, height * 0.98)
			var fork_radii := PackedFloat32Array([branch_radius * 0.55, maxf(0.01, branch_radius * 0.12)])
			var fork_path := PackedVector3Array([fork_start, fork_end])
			_add_tube(st, fork_path, fork_radii, BRANCH_SIDES, true, BARK_UV_METRES, Color.WHITE)
			tips.append(fork_end)

	# Bark uses a normal map, so trunks/branches need tangents. UVs are already
	# present on every vertex; generate_tangents() keeps them untouched.
	st.generate_tangents()
	return {"mesh": st.commit(), "tips": tips}


static func _broadleaf_leaves(species: Dictionary, rng: RandomNumberGenerator, dims: Dictionary, tips: Array[Vector3]) -> ArrayMesh:
	var leaves_id := String(species.get("leaves", ""))
	if leaves_id.is_empty():
		return null
	var height: float = dims["height"]
	var crown_radius: float = dims["crown_radius"]
	var crown_height: float = dims["crown_height"]
	var crown_base: float = dims["crown_base"]
	var cells := TextureLibrary.cell_count(leaves_id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# One central top cluster keeps the crown from opening at the apex; the rest
	# follow the branch tips so the canopy reads as grown rather than sprayed.
	var cluster_count := clampi(tips.size() + 1, 3, 5)
	var centers: Array[Vector3] = []
	for index in range(cluster_count):
		var center: Vector3
		if index == 0:
			center = Vector3(0.0, height * 0.86, 0.0)
		elif index - 1 < tips.size():
			center = tips[index - 1]
		else:
			center = Vector3(0.0, height * 0.78, 0.0)
		center += Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.1, 0.2), rng.randf_range(-0.18, 0.18)) * crown_radius
		center.y = clampf(center.y, crown_base + crown_height * 0.15, height * 0.97)
		centers.append(center)

	var total_cards := rng.randi_range(18, 32)
	var per_cluster := int(float(total_cards) / float(cluster_count))
	var cards_left := total_cards - per_cluster * cluster_count
	for cluster_index in range(cluster_count):
		var center := centers[cluster_index]
		var card_count := per_cluster + (1 if cluster_index < cards_left else 0)
		for card_index in range(card_count):
			var direction := _random_unit(rng)
			var offset := Vector3(direction.x, direction.y * 0.75, direction.z) * crown_radius * rng.randf_range(0.15, 0.5)
			var position := center + offset
			position.y = clampf(position.y, crown_base + crown_height * 0.08, height * 0.985)
			var normal := (position - center)
			if normal.length_squared() < 0.0001:
				normal = direction
			normal = _safe_normal(normal.normalized() + Vector3.UP * 0.45, Vector3.UP)
			var basis := _card_basis(normal, rng.randf_range(0.0, TAU))
			var size := crown_radius * rng.randf_range(0.38, 0.62)
			var half_w := size * 0.5
			var half_h := size * rng.randf_range(0.34, 0.5)
			var cell := TextureLibrary.atlas_cell(leaves_id, rng.randi_range(0, cells - 1))
			var interior := 1.0 - clampf(Vector2(position.x, position.z).length() / maxf(crown_radius, 0.001), 0.0, 1.0)
			var vertical := clampf((position.y - crown_base) / maxf(crown_height, 0.001), 0.0, 1.0)
			var shade := lerpf(1.0, 0.6, interior * interior) * lerpf(0.86, 1.0, vertical)
			var top_colour := Color(shade, shade, shade, 1.0)
			var bottom_colour := Color(shade * 0.92, shade * 0.92, shade * 0.92, 1.0)
			var phase := rng.randf()
			var wind_uv := Vector2(phase, clampf(0.25 + 0.75 * vertical, 0.0, 1.0))
			_add_card(st, position, basis[0], basis[1], half_w, half_h, cell,
				top_colour, bottom_colour, wind_uv)
	return st.commit()


static func _birch_leaves(species: Dictionary, rng: RandomNumberGenerator, dims: Dictionary, tips: Array[Vector3]) -> ArrayMesh:
	var leaves_id := String(species.get("leaves", ""))
	if leaves_id.is_empty():
		return null
	var height: float = dims["height"]
	var crown_radius: float = dims["crown_radius"]
	var crown_height: float = dims["crown_height"]
	var crown_base: float = dims["crown_base"]
	var cells := TextureLibrary.cell_count(leaves_id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cluster_count := clampi(maxi(tips.size(), 2), 2, 3)
	var centers: Array[Vector3] = []
	for index in range(cluster_count):
		var center: Vector3
		if index < tips.size():
			center = tips[index]
		else:
			center = Vector3(0.0, height * 0.86, 0.0)
		center.y = clampf(center.y, crown_base + crown_height * 0.2, height * 0.97)
		centers.append(center)

	var total_cards := rng.randi_range(10, 18)
	var per_cluster := int(float(total_cards) / float(cluster_count))
	var cards_left := total_cards - per_cluster * cluster_count
	for cluster_index in range(cluster_count):
		var center := centers[cluster_index]
		var card_count := per_cluster + (1 if cluster_index < cards_left else 0)
		for card_index in range(card_count):
			var direction := _random_unit(rng)
			var offset := Vector3(direction.x, direction.y * 0.8, direction.z) * crown_radius * rng.randf_range(0.18, 0.45)
			var position := center + offset
			position.y = clampf(position.y, crown_base + crown_height * 0.1, height * 0.985)
			var normal := (position - center)
			if normal.length_squared() < 0.0001:
				normal = direction
			normal = _safe_normal(normal.normalized() + Vector3.UP * 0.6, Vector3.UP)
			var basis := _card_basis(normal, rng.randf_range(0.0, TAU))
			var size := crown_radius * rng.randf_range(0.34, 0.55)
			var half_w := size * 0.5
			var half_h := size * rng.randf_range(0.34, 0.52)
			var cell := TextureLibrary.atlas_cell(leaves_id, rng.randi_range(0, cells - 1))
			var vertical := clampf((position.y - crown_base) / maxf(crown_height, 0.001), 0.0, 1.0)
			var shade := lerpf(0.94, 1.0, vertical)
			var top_colour := Color(shade, shade, shade, 1.0)
			var bottom_colour := Color(shade * 0.92, shade * 0.92, shade * 0.92, 1.0)
			var wind_uv := Vector2(rng.randf(), clampf(0.35 + 0.65 * vertical, 0.0, 1.0))
			_add_card(st, position, basis[0], basis[1], half_w, half_h, cell,
				top_colour, bottom_colour, wind_uv)
	return st.commit()


static func _conifer_leaves(species: Dictionary, rng: RandomNumberGenerator, dims: Dictionary) -> ArrayMesh:
	var leaves_id := String(species.get("leaves", ""))
	if leaves_id.is_empty():
		return null
	var height: float = dims["height"]
	var crown_radius: float = dims["crown_radius"]
	var crown_height: float = dims["crown_height"]
	var crown_base: float = dims["crown_base"]
	var cells := TextureLibrary.cell_count(leaves_id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var layer_count := rng.randi_range(5, 7)
	var layer_phase := rng.randf_range(0.0, TAU)
	for layer_index in range(layer_count):
		var t := float(layer_index) / float(maxi(1, layer_count - 1))
		var y := lerpf(crown_base + crown_height * 0.06, height * 0.9, t)
		var layer_radius := crown_radius * (pow(1.0 - t, 0.75) * 0.94 + 0.06)
		var cards := rng.randi_range(6, 8)
		var card_width := TAU * maxf(layer_radius, 0.35) / float(cards) * 1.12
		var card_height := (crown_height / float(layer_count)) * rng.randf_range(1.35, 1.75)
		for card_index in range(cards):
			var angle := layer_phase + TAU * float(card_index) / float(cards) + rng.randf_range(-0.16, 0.16)
			var outward := Vector3(cos(angle), 0.0, sin(angle))
			var position := _spine_at(y, dims) + outward * layer_radius * rng.randf_range(0.72, 0.95)
			position.y += rng.randf_range(-0.12, 0.12)
			var normal := _safe_normal(outward * 0.85 + Vector3.UP * 0.4, outward)
			var card_up := _safe_normal(Vector3.UP * 0.8 - outward * 0.5, Vector3.UP)
			var right := _safe_normal(card_up.cross(normal), outward.cross(Vector3.UP))
			# Droop the bough: rotate the card plane about its outward normal a little.
			var roll := rng.randf_range(-0.35, 0.35)
			right = right.rotated(normal, roll)
			card_up = normal.cross(right)
			var cell := TextureLibrary.atlas_cell(leaves_id, rng.randi_range(0, cells - 1))
			var shade := lerpf(0.72, 1.0, t) * rng.randf_range(0.94, 1.06)
			shade = clampf(shade, 0.55, 1.0)
			var top_colour := Color(shade, shade, shade, 1.0)
			var bottom_colour := Color(shade * 0.86, shade * 0.86, shade * 0.86, 1.0)
			var wind_uv := Vector2(rng.randf(), clampf(0.12 + 0.3 * t, 0.0, 1.0))
			_add_card(st, position, right, card_up, card_width * 0.5, card_height * 0.5, cell,
				top_colour, bottom_colour, wind_uv)

	# Top spire: narrow crossed cards keep the conifer tip from looking cut off.
	var spire_height := maxf(0.7, height * 0.11)
	var spire_width := maxf(0.22, crown_radius * 0.22)
	for spire_index in range(3):
		var angle := TAU * float(spire_index) / 3.0 + layer_phase
		var normal := Vector3(cos(angle), 0.0, sin(angle))
		var basis := _card_basis(normal, 0.0)
		var position := _spine_at(height - spire_height * 0.5, dims)
		var cell := TextureLibrary.atlas_cell(leaves_id, rng.randi_range(0, cells - 1))
		var colour := Color(0.92, 0.92, 0.92, 1.0)
		_add_card(st, position, basis[0], basis[1], spire_width * 0.5, spire_height * 0.5, cell,
			colour, colour * Color(0.9, 0.9, 0.9, 1.0), Vector2(rng.randf(), 0.1))
	return st.commit()


static func _add_card(st: SurfaceTool, center: Vector3, right: Vector3, up: Vector3,
		half_width: float, half_height: float, cell: Rect2,
		top_colour: Color, bottom_colour: Color, wind_uv: Vector2) -> void:
	var normal := right.cross(up)
	if normal.length_squared() < 1e-10:
		return
	normal = normal.normalized()
	var p0 := center - right * half_width - up * half_height
	var p1 := center + right * half_width - up * half_height
	var p2 := center + right * half_width + up * half_height
	var p3 := center - right * half_width + up * half_height
	var u0 := cell.position.x
	var u1 := cell.end.x
	var v0 := cell.position.y
	var v1 := cell.end.y
	# UV v grows downward in the atlas; bottom corners use v1.
	_add_triangle(st, p0, p1, p2, normal, normal, normal,
		Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0),
		wind_uv, wind_uv, wind_uv, bottom_colour, bottom_colour, top_colour)
	_add_triangle(st, p0, p2, p3, normal, normal, normal,
		Vector2(u0, v1), Vector2(u1, v0), Vector2(u0, v0),
		wind_uv, wind_uv, wind_uv, bottom_colour, top_colour, top_colour)


## Emits a triangle with Godot's clockwise front-face convention: the emitted
## winding is chosen so the face is visible from the side its hand-authored
## normal points toward. Degenerate triangles are dropped.
static func _add_triangle(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3,
		n0: Vector3, n1: Vector3, n2: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2,
		w0: Vector2, w1: Vector2, w2: Vector2,
		c0: Color, c1: Color, c2: Color) -> void:
	var face := (p1 - p0).cross(p2 - p0)
	if face.length_squared() < 1e-12:
		return
	if face.dot(n0) > 0.0:
		var tp := p1
		p1 = p2
		p2 = tp
		var tn := n1
		n1 = n2
		n2 = tn
		var tuv := uv1
		uv1 = uv2
		uv2 = tuv
		var tw := w1
		w1 = w2
		w2 = tw
		var tc := c1
		c1 = c2
		c2 = tc
	_vertex(st, p0, n0, uv0, w0, c0)
	_vertex(st, p1, n1, uv1, w1, c1)
	_vertex(st, p2, n2, uv2, w2, c2)


static func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, wind_uv: Vector2, colour: Color) -> void:
	st.set_normal(normal if normal.length_squared() > 1e-12 else Vector3.UP)
	st.set_uv(uv)
	st.set_uv2(wind_uv)
	st.set_color(colour)
	st.add_vertex(point)


## Tapered tube through `path`. Rings are built on stable tangent frames, UVs run
## once around and every 2 m along the tube, normals are radial. `cap_end` fans
## the tip closed so bark never shows a see-through hole.
static func _add_tube(st: SurfaceTool, path: PackedVector3Array, radii: PackedFloat32Array,
		sides: int, cap_end: bool, uv_metres: float, colour: Color) -> void:
	var ring_count := path.size()
	if ring_count < 2 or radii.size() != ring_count or sides < 3:
		return
	var distance := PackedFloat32Array()
	distance.resize(ring_count)
	distance[0] = 0.0
	for index in range(1, ring_count):
		distance[index] = distance[index - 1] + path[index].distance_to(path[index - 1])

	var rings: Array = []
	var ring_normals: Array = []
	var ring_uvs: Array = []
	var tangents: Array[Vector3] = []
	for index in range(ring_count):
		var tangent: Vector3
		if index == 0:
			tangent = path[1] - path[0]
		elif index == ring_count - 1:
			tangent = path[index] - path[index - 1]
		else:
			tangent = path[index + 1] - path[index - 1]
		tangent = _safe_normal(tangent, Vector3.UP)
		tangents.append(tangent)
		var reference := Vector3.UP
		if absf(tangent.dot(reference)) > 0.95:
			reference = Vector3.RIGHT
		var right := _safe_normal(tangent.cross(reference), Vector3.RIGHT)
		var up := _safe_normal(right.cross(tangent), Vector3.UP)
		var ring := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for side in range(sides + 1):
			var angle := TAU * float(side) / float(sides)
			var radial := right * cos(angle) + up * sin(angle)
			ring.append(path[index] + radial * radii[index])
			normals.append(radial.normalized())
			uvs.append(Vector2(float(side) / float(sides), distance[index] / uv_metres))
		rings.append(ring)
		ring_normals.append(normals)
		ring_uvs.append(uvs)

	var zero_wind := Vector2.ZERO
	for index in range(ring_count - 1):
		var ring_a: PackedVector3Array = rings[index]
		var ring_b: PackedVector3Array = rings[index + 1]
		var normals_a: PackedVector3Array = ring_normals[index]
		var normals_b: PackedVector3Array = ring_normals[index + 1]
		var uvs_a: PackedVector2Array = ring_uvs[index]
		var uvs_b: PackedVector2Array = ring_uvs[index + 1]
		for side in range(sides):
			var next := side + 1
			var a0 := ring_a[side]
			var a1 := ring_a[next]
			var b0 := ring_b[side]
			var b1 := ring_b[next]
			_add_triangle(st, a0, a1, b0, normals_a[side], normals_a[next], normals_b[side],
				uvs_a[side], uvs_a[next], uvs_b[side],
				zero_wind, zero_wind, zero_wind, colour, colour, colour)
			_add_triangle(st, a1, b1, b0, normals_a[next], normals_b[next], normals_b[side],
				uvs_a[next], uvs_b[next], uvs_b[side],
				zero_wind, zero_wind, zero_wind, colour, colour, colour)

	if cap_end:
		var last_ring: PackedVector3Array = rings[ring_count - 1]
		var last_uvs: PackedVector2Array = ring_uvs[ring_count - 1]
		var center := path[ring_count - 1]
		var tangent := tangents[ring_count - 1]
		var center_uv := Vector2(0.5, distance[ring_count - 1] / uv_metres)
		for side in range(sides):
			var next := side + 1
			_add_triangle(st, center, last_ring[side], last_ring[next],
				tangent, tangent, tangent,
				center_uv, last_uvs[side], last_uvs[next],
				zero_wind, zero_wind, zero_wind, colour, colour, colour)


static func _card_basis(normal: Vector3, roll: float) -> Array[Vector3]:
	var n := _safe_normal(normal, Vector3.UP)
	var reference := Vector3.UP
	if absf(n.dot(reference)) > 0.96:
		reference = Vector3.FORWARD
	var right := _safe_normal(reference.cross(n), Vector3.RIGHT)
	right = right.rotated(n, roll)
	var up := _safe_normal(n.cross(right), Vector3.UP)
	return [right, up]


static func _spine_at(y: float, dims: Dictionary) -> Vector3:
	var height: float = dims["height"]
	var lean: Vector2 = dims["lean"]
	var t := clampf(y / maxf(height, 0.001), 0.0, 1.0)
	var curve := pow(t, 1.6)
	return Vector3(lean.x * curve, y, lean.y * curve)


static func _random_unit(rng: RandomNumberGenerator) -> Vector3:
	for _attempt in range(4):
		var value := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if value.length_squared() > 0.001:
			return value.normalized()
	return Vector3.UP


static func _safe_normal(value: Vector3, fallback: Vector3) -> Vector3:
	if value.length_squared() < 1e-12:
		return fallback
	return value.normalized()
