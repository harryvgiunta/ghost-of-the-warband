class_name FireFx
extends RefCounted
## The live half of a firepit: its flame cards, embers, smoke and lamp.
##
## The kits author the pit itself (stone kerb, ash bed, charred logs) into one
## merged mesh. This module adds what has to move: flame planes that each carry
## their own phase into the shader, embers rising on the heat, a thin smoke
## plume, and the light that breathes with them. Everything is built from the
## fire's own scale and a seed, so a rebuild reproduces the same camp.
##
## `flame_cards` takes either kit's `Merged` (both expose `add(mesh, transform,
## material)`) and appends straight into the mesh the pit already commits, so
## the fire stays one draw call.

## Ring layout, in fire heights: how many planes, how tall, how wide, how far
## from the axis and how far the tops splay outward. Low rings sit wider and lean
## more, which is what makes the base of a fire read as a burning bed instead of
## a column.
const RINGS := [
	{"planes": 4, "height": 1.00, "width": 0.50, "radius": 0.05, "tilt": 0.04},
	{"planes": 4, "height": 0.80, "width": 0.44, "radius": 0.11, "tilt": 0.08},
	# The apron: short, wide cards that make the burning bed continuous instead
	# of five separate columns standing on the ash.
	{"planes": 5, "height": 0.32, "width": 0.62, "radius": 0.20, "tilt": 0.14},
	{"planes": 4, "height": 0.52, "width": 0.38, "radius": 0.18, "tilt": 0.16},
	{"planes": 2, "height": 0.62, "width": 0.22, "radius": 0.03, "tilt": 0.02},
]

static var _soft: ImageTexture


## Appends the flame planes to a kit's merged mesh. `scale` is the fire's tallest
## tongue in metres and `ground` is the height of the ash bed the cards stand on.
static func flame_cards(merged, material: Material, rng: RandomNumberGenerator,
		scale: float, ground: float) -> void:
	var ring_index := 0
	for ring in RINGS:
		var planes: int = int(ring["planes"])
		var step := TAU / float(planes)
		var yaw_offset := float(ring_index) * 0.62
		for plane in range(planes):
			var angle := step * float(plane) + yaw_offset
			var height: float = scale * float(ring["height"]) * rng.randf_range(0.94, 1.06)
			var width: float = scale * float(ring["width"]) * rng.randf_range(0.94, 1.08)
			var radius: float = scale * float(ring["radius"]) * rng.randf_range(0.85, 1.2)
			var lean: float = float(ring["tilt"]) * rng.randf_range(0.6, 1.5)
			var foot := Vector3(sin(angle) * radius, ground, cos(angle) * radius)
			var card := card_mesh(Vector2(width, height), rng.randf())
			# Face outward (local +Z along the ring) and splay the top away from
			# the axis, so the fire broadens as it climbs.
			var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, lean) \
				* Basis(Vector3.BACK, rng.randf_range(-0.06, 0.06))
			merged.add(card, Transform3D(basis, foot), material)
		ring_index += 1


## One flame plane, anchored at its foot: the card grows upward from `ground` and
## carries a per-card phase in its vertex colour for the shader.
static func card_mesh(size: Vector2, seed_value: float) -> ArrayMesh:
	var half := size.x * 0.5
	var tint := Color(clampf(seed_value, 0.0, 1.0), 0.0, 0.0, 1.0)
	var corners := [
		Vector3(-half, 0.0, 0.0),
		Vector3(half, 0.0, 0.0),
		Vector3(half, size.y, 0.0),
		Vector3(-half, size.y, 0.0),
	]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 2, 0, 2, 3]:
		var point: Vector3 = corners[index]
		tool.set_color(tint)
		tool.set_normal(Vector3.BACK)
		# Image v grows downward from the cell's transparent tip to its coal bed,
		# so the card's foot must sample v = 1, not v = 0.
		tool.set_uv(Vector2((point.x + half) / maxf(size.x, 0.001),
			1.0 - point.y / maxf(size.y, 0.001)))
		tool.add_vertex(point)
	return tool.commit()


## Embers: grit thrown off the burning wood that cools as it climbs and drifts on
## the heat. Local to the fire, so a rebuilt world drops the same sparks.
static func embers(host: Node3D, ground: float, spread: float, amount: int) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "FireEmbers"
	particles.position = Vector3(0.0, ground + 0.12, 0.0)
	particles.amount = maxi(4, amount)
	particles.lifetime = 2.3
	particles.lifetime_randomness = 0.45
	particles.preprocess = 1.2
	particles.randomness = 0.45
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = spread
	particles.direction = Vector3.UP
	particles.spread = 24.0
	particles.initial_velocity_min = 0.45
	particles.initial_velocity_max = 1.5
	# Heat carries them up: gravity points along the plume, not down.
	particles.gravity = Vector3(0.05, 0.5, 0.08)
	particles.damping_min = 0.1
	particles.damping_max = 0.45
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.5
	var cooling := Gradient.new()
	cooling.set_color(0, Color(1.0, 0.80, 0.38, 1.0))
	cooling.set_color(1, Color(0.36, 0.05, 0.01, 0.0))
	cooling.add_point(0.5, Color(1.0, 0.42, 0.09, 0.85))
	particles.color_ramp = cooling
	var spark := SphereMesh.new()
	spark.radius = spread * 0.034
	spark.height = spread * 0.075
	spark.radial_segments = 6
	spark.rings = 3
	particles.mesh = spark
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = Color(1.0, 0.42, 0.1)
	material.emission_energy_multiplier = 1.15
	material.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	material.disable_receive_shadows = true
	particles.material_override = material
	particles.emitting = true
	host.add_child(particles)
	return particles


## A thin smoke plume above the flame: the daylight tell that something is
## actually burning rather than a stack of glowing cards.
static func smoke(host: Node3D, from: Vector3, spread: float, amount: int) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "FireSmoke"
	particles.position = from
	particles.amount = maxi(3, amount)
	particles.lifetime = 4.6
	particles.lifetime_randomness = 0.35
	particles.preprocess = 1.6
	particles.randomness = 0.5
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = spread
	particles.direction = Vector3.UP
	particles.spread = 9.0
	particles.initial_velocity_min = 0.35
	particles.initial_velocity_max = 0.8
	particles.gravity = Vector3(0.16, 0.06, 0.05)
	particles.damping_min = 0.02
	particles.damping_max = 0.1
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 0.95
	var billow := Curve.new()
	billow.add_point(Vector2(0.0, 0.6))
	billow.add_point(Vector2(0.45, 1.6))
	billow.add_point(Vector2(1.0, 3.1))
	particles.scale_amount_curve = billow
	var fading := Gradient.new()
	# One faint grey puff per particle; the alpha lives in the material and the
	# puff grows over its life, so nothing pops as it appears.
	var puff := QuadMesh.new()
	puff.size = Vector2(1.5, 1.5)
	particles.mesh = puff
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = soft_texture()
	material.albedo_color = Color(0.78, 0.77, 0.74, 0.085)
	material.roughness = 1.0
	material.disable_receive_shadows = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	particles.material_override = material
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = true
	host.add_child(particles)
	return particles


## A soft round falloff, generated once: no smoke texture ships with the world,
## and a procedural puff keeps the palette authored rather than sampled.
static func soft_texture() -> ImageTexture:
	if _soft != null:
		return _soft
	var size := 64
	var half := float(size) * 0.5
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var offset := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half) / half
			var falloff: float = clampf(1.0 - offset.length(), 0.0, 1.0)
			falloff = falloff * falloff * (3.0 - 2.0 * falloff)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff * falloff))
	_soft = ImageTexture.create_from_image(image)
	return _soft
