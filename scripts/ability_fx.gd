extends RefCounted
## Procedural presentation for item skills: blade arcs, shockwaves, fire and
## bone bursts. Nothing here changes damage; scenes call it on every peer.

const BladeTrail = preload("res://scripts/blade_trail.gd")
const LungeWake = preload("res://scripts/lunge_wake.gd")

const FIRE := Color("ff8a3c")
const FIRE_CORE := Color("ffd9a0")
const BONE := Color("bfe6c8")
const BONE_CORE := Color("e8fff1")
const STEEL := Color("e9f2ff")
const DUST := Color("c9b18a")
const EMBER_RED := Color("e8503c")
const HOT_WHITE := Color("fff6e4")
## Billboards in the backstab blink cloud. Five times the original 26, so the
## burst genuinely engulfs the ranger at both ends of the blink.
const BLINK_PUFFS := 130

## Cached procedural sprites. Both are generated once from fixed seeds so every
## peer that triggers an effect gets the same image.
static var _smoke_texture: Texture2D
static var _dot_texture: Texture2D


## Deterministic yaw/pitch offset for one shot of a burst. Every peer derives
## the same pattern from the cue index, so the host's damaging arrow and the
## clients' visual arrows follow the same line.
static func shot_offsets(definition: Dictionary, shot_index: int) -> Vector2:
	var effect: Dictionary = definition.get("effect", {})
	var shots := maxi(int(effect.get("shots", 1)), 1)
	var spread := deg_to_rad(float(effect.get("spread_degrees", 0.0)))
	var vertical := deg_to_rad(float(effect.get("vertical_spread_degrees", 0.0)))
	if shots <= 1:
		return Vector2.ZERO
	var yaw := 0.0
	if shots == 3:
		yaw = [-1.0, 0.0, 1.0][clampi(shot_index, 0, 2)]
	else:
		var pattern := [-0.85, 0.95, -0.45, 0.55, -0.15, 0.25, -0.7, 0.7]
		yaw = float(pattern[shot_index % pattern.size()])
	var pitch := 0.0
	if vertical > 0.0:
		var vertical_pattern := [0.4, -0.35, 0.15, -0.1, 0.3, -0.25]
		pitch = float(vertical_pattern[shot_index % vertical_pattern.size()])
	return Vector2(yaw * spread, pitch * vertical)


static func rotate_direction(direction: Vector3, yaw: float, pitch: float) -> Vector3:
	var result := direction.rotated(Vector3.UP, yaw)
	if absf(pitch) > 0.00001:
		var right := result.cross(Vector3.UP)
		if right.length_squared() > 0.000001:
			result = result.rotated(right.normalized(), pitch)
	return result.normalized()


static func glow_material(color: Color, energy: float = 3.0, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func spark_particles(color: Color, amount: int, speed_min: float,
		speed_max: float, lifetime: float, size: float, one_shot: bool = true) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = 1.0 if one_shot else 0.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 180.0
	particles.gravity = Vector3(0.0, -7.5, 0.0)
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.damping_min = 0.4
	particles.damping_max = 1.4
	particles.scale_amount_min = 0.55
	particles.scale_amount_max = 1.35
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.24, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.99, 0.92, 1.0),
		color,
		Color(color.r * 0.75, color.g * 0.32, color.b * 0.12, 0.75),
		Color(color.r * 0.25, color.g * 0.1, color.b * 0.05, 0.0),
	])
	particles.color_ramp = gradient
	var spark := SphereMesh.new()
	spark.radius = size
	spark.height = size * 2.0
	spark.radial_segments = 6
	spark.rings = 3
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_receive_shadows = true
	spark.material = material
	particles.mesh = spark
	return particles


## Billboard smoke on the cached soft sprite: wider, slower and rotated puffs
## instead of the old flat untextured quads. Callers still own the lifetime.
static func smoke_particles(color: Color, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = clampi(amount, 1, 96)
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.55
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.42
	particles.flatness = 0.35
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 62.0
	particles.gravity = Vector3(0.16, 0.34, 0.10)
	particles.initial_velocity_min = 0.35
	particles.initial_velocity_max = 1.15
	particles.damping_min = 0.35
	particles.damping_max = 0.95
	particles.scale_amount_min = 1.2
	particles.scale_amount_max = 1.7
	particles.scale_amount_curve = smoke_growth_curve()
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.angular_velocity_min = -16.0
	particles.angular_velocity_max = 16.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.62),
		Color(color.r * 0.62, color.g * 0.58, color.b * 0.55, 0.38),
		Color(color.r * 0.28, color.g * 0.26, color.b * 0.24, 0.0),
	])
	particles.color_ramp = gradient
	var quad := smoke_quad(1.0)
	(quad.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


static func flash_light(color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.15
	light.shadow_enabled = false
	return light


## A crescent of blade light in front of the body. The ribbon uses the same
## radius as the damage arc so the presentation and the hit volume agree.
static func slash_arc(parent: Node3D, origin: Vector3, forward: Vector3,
		radius: float, arc_degrees: float, color: Color = STEEL, tilt_degrees: float = 0.0) -> void:
	if not is_instance_valid(parent):
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.000001:
		return
	flat = flat.normalized()
	var root := Node3D.new()
	root.name = "AbilitySlashArc"
	parent.add_child(root)
	root.global_position = origin + Vector3.UP * 1.26
	root.global_basis = Basis.looking_at(flat, Vector3.UP) \
		* Basis(Vector3(0.0,0.0,-1.0),deg_to_rad(tilt_degrees))
	var arc := deg_to_rad(clampf(arc_degrees, 20.0, 340.0))
	var segments := clampi(int(arc * 18.0), 10, 64)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var inner := maxf(radius - 0.09, radius * 0.9)
	var outer := radius
	for index in segments + 1:
		var t := float(index) / segments
		var angle := -arc * 0.5 + arc * t
		var direction := Basis(Vector3.UP, angle) * Vector3(0.0, 0.0, -1.0)
		var fade := pow(sin(PI * t), 0.65)
		var lift := 0.18 * sin(PI * t)
		vertices.append(direction * inner + Vector3.UP * lift)
		colors.append(Color(color.r, color.g, color.b, fade * 0.10))
		vertices.append(direction * outer + Vector3.UP * lift)
		colors.append(Color(color.r*0.86, color.g*0.96, minf(color.b*1.1,1.0), fade * 0.52))
	var indices := PackedInt32Array()
	for index in segments:
		var base := index * 2
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = mesh
	ribbon.material_override = material
	root.add_child(ribbon)
	var tween := root.create_tween()
	tween.tween_property(material, "albedo_color", Color(0.0, 0.0, 0.0, 0.0), 0.26)
	tween.tween_callback(root.queue_free)


## Low, dusty ground ring for a full-turn cut. A chest-height ring is nearly
## edge-on to the shoulder camera; the read belongs at the feet.
static func spin_dust(parent: Node3D, origin: Vector3, radius: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilitySpinDust"
	parent.add_child(root)
	root.global_position = origin+Vector3.UP*0.06
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.94
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 56
	ring_mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86,0.74,0.54,0.55)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.disable_receive_shadows = true
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = material
	ring.scale = Vector3(0.35,0.22,0.35)
	root.add_child(ring)
	var dust := spark_particles(Color("c9b18a"), 44, 1.2, 4.2, 0.7, 0.045)
	dust.gravity = Vector3(0.0,-1.4,0.0)
	dust.emitting = true
	root.add_child(dust)
	var dust_ramp := Gradient.new()
	dust_ramp.offsets = PackedFloat32Array([0.0,0.35,1.0])
	dust_ramp.colors = PackedColorArray([Color(0.788,0.694,0.541,0.65),Color(0.604,0.498,0.361,0.38),Color(0.373,0.298,0.216,0.0)])
	dust.color_ramp = dust_ramp
	if dust.mesh is SphereMesh and dust.mesh.material is StandardMaterial3D:
		dust.mesh.material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring,"scale",Vector3(radius,0.1,radius),0.36).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material,"albedo_color",Color(0.85,0.73,0.57,0.0),0.5)
	tween.set_parallel(false)
	tween.tween_interval(0.35)
	tween.tween_callback(root.queue_free)

## Impact burst for a projectile hit or a ground slam.
static func burst(parent: Node3D, at: Vector3, color: Color, scale: float = 1.0) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilityBurst"
	parent.add_child(root)
	root.global_position = at
	var sparks := soft_spark_particles(color, int(24 * scale), 2.2 * scale, 6.0 * scale,
		0.45, 0.042 * scale)
	sparks.emitting = true
	root.add_child(sparks)
	var flash := flash_light(color, 2.6 * scale, 3.2 * scale)
	root.add_child(flash)
	var tween := root.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.26)
	tween.tween_interval(0.55)
	tween.tween_callback(root.queue_free)


## Expanding fireball detonation: hot core, shockwave ring, sparks, smoke and a
## short light flash. `radius` is the gameplay blast radius. The core is two
## camera-facing additive sprites rather than spheres, so the centre can only
## ever add light: no dark disc, no faceted edge, no backface artefact.
static func explosion(parent: Node3D, at: Vector3, radius: float,
		color: Color = FIRE, core: Color = FIRE_CORE) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilityExplosion"
	parent.add_child(root)
	root.global_position = at
	var hot := sprite_flash(root, Vector3.ZERO, Vector2.ONE * radius * 0.5, HOT_WHITE)
	hot.scale = Vector3.ONE * 0.45
	var body := sprite_flash(root, Vector3(0.0, 0.05, 0.0), Vector2.ONE * radius * 1.0,
		Color(core.r, core.g, core.b, 0.75))
	body.scale = Vector3.ONE * 0.4
	var wash := sprite_flash(root, Vector3(0.0, 0.15, 0.0), Vector2.ONE * radius * 1.7,
		Color(color.r, color.g, color.b, 0.45))
	wash.scale = Vector3.ONE * 0.35
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	var ring_material := glow_material(core, 2.0, 0.45)
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_material
	ring.scale = Vector3(0.15, 0.5, 0.15)
	root.add_child(ring)
	var sparks := soft_spark_particles(color, 64, 4.0, 11.0, 0.65, 0.075)
	sparks.emitting = true
	root.add_child(sparks)
	var chunks := soft_spark_particles(core, 18, 6.0, 13.0, 0.75, 0.05)
	chunks.emitting = true
	root.add_child(chunks)
	# Smoke begins after the flash and on a ring well outside the hot core, so no
	# puff can mix-darken the centre while the core sprite is alive.
	_smoke_cloud(root, at, 0.95, false, 26, 1.5, Vector3.ZERO, 0.18, 1.35)
	var light := flash_light(color, 9.0, radius * 3.0)
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(hot, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(hot), "albedo_color",
		Color(HOT_WHITE.r, HOT_WHITE.g, HOT_WHITE.b, 0.0), 0.26)
	tween.tween_property(body, "scale", Vector3.ONE, 0.26) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(body), "albedo_color",
		Color(core.r, core.g, core.b, 0.0), 0.38)
	tween.tween_property(wash, "scale", Vector3.ONE, 0.36) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(wash), "albedo_color",
		Color(color.r, color.g, color.b, 0.0), 0.44)
	tween.tween_property(ring, "scale", Vector3(radius, radius * 0.35, radius), 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_material, "albedo_color", Color(core.r, core.g, core.b, 0.0), 0.4)
	tween.tween_property(light, "light_energy", 0.0, 0.36)
	tween.set_parallel(false)
	tween.tween_interval(2.1)
	tween.tween_callback(root.queue_free)


## Ground shockwave for the tower shield slam and heavy landings.
static func ground_shockwave(parent: Node3D, origin: Vector3, radius: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilityShockwave"
	parent.add_child(root)
	root.global_position = origin + Vector3.UP * 0.08
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 56
	ring_mesh.ring_segments = 6
	var material := glow_material(Color("ffd9a0"), 2.0, 0.9)
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = material
	ring.scale = Vector3(0.2, 0.25, 0.2)
	root.add_child(ring)
	var dust := spark_particles(Color("c9b18a"), 30, 2.0, 6.2, 0.7, 0.045)
	dust.gravity = Vector3(0.0, -2.0, 0.0)
	var dust_ramp := Gradient.new()
	dust_ramp.offsets = PackedFloat32Array([0.0,0.35,1.0])
	dust_ramp.colors = PackedColorArray([Color(0.788,0.694,0.541,0.75),Color(0.604,0.498,0.361,0.45),Color(0.373,0.298,0.216,0.0)])
	dust.color_ramp = dust_ramp
	dust.emitting = true
	root.add_child(dust)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.12, radius), 0.38).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.85, 0.63, 0.0), 0.5)
	tween.set_parallel(false)
	tween.tween_interval(0.5)
	tween.tween_callback(root.queue_free)


# --- Soft sprites -----------------------------------------------------------
# Sparks and smoke were flat-shaded primitives, which read as faceted balls and
# pixelated quads at HUD distance. Everything below is a camera-facing quad on a
# cached procedural sprite instead.

## Cached soft radial dot for sparks and flash cores. Deterministic and 1:1 safe.
static func soft_dot_texture() -> Texture2D:
	if _dot_texture != null:
		return _dot_texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var centre := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var offset := Vector2(float(x) - centre, float(y) - centre) / centre
			var radial := clampf(1.0 - offset.length(), 0.0, 1.0)
			var alpha := radial * radial * (3.0 - 2.0 * radial)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
	image.generate_mipmaps()
	_dot_texture = ImageTexture.create_from_image(image)
	return _dot_texture


## Cached soft smoke sprite: a radial falloff warped by fixed-seed noise so the
## billboards have an uneven, cloudy silhouette instead of a visible circle.
static func smoke_texture() -> Texture2D:
	if _smoke_texture != null:
		return _smoke_texture
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var noise := FastNoiseLite.new()
	noise.seed = 0x5106E
	noise.frequency = 0.055
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	var centre := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var offset := Vector2(float(x) - centre, float(y) - centre) / centre
			var radial := clampf(1.0 - offset.length(), 0.0, 1.0)
			if radial <= 0.0:
				continue
			var grain := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var edge := smoothstep(0.0, 1.0, radial)
			var alpha := clampf(edge * (0.34 + 0.96 * grain), 0.0, 1.0)
			var shade := 0.78 + 0.22 * grain
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	image.generate_mipmaps()
	_smoke_texture = ImageTexture.create_from_image(image)
	return _smoke_texture


## Sprite material for plain quads. A QuadMesh carries no COLOR attribute, so
## vertex-colour-as-albedo would tint it black; the tint is baked into
## albedo_color instead. `additive` is for light, mix for smoke and dust.
static func sprite_material(texture: Texture2D, additive: bool = true,
		tint: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	if additive:
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


## Same sprite, but for CPUParticles3D meshes where the per-particle colour ramp
## must reach the fragment stage as vertex colour.
static func particle_sprite_material(texture: Texture2D, tint: Color = Color.WHITE,
		additive: bool = true) -> StandardMaterial3D:
	var material := sprite_material(texture, additive, tint)
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return material


static func smoke_quad(scale: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * maxf(scale, 0.05)
	quad.material = sprite_material(smoke_texture(), false)
	return quad


static func smoke_growth_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 1.75))
	return curve


## Camera-facing sprite used for impact flashes and hot cores.
static func sprite_flash(parent: Node3D, offset: Vector3, size: Vector2,
		tint: Color) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = sprite_material(soft_dot_texture(), true, tint)
	var sprite := MeshInstance3D.new()
	sprite.mesh = quad
	sprite.position = offset
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sprite)
	return sprite


static func sprite_tint(sprite: MeshInstance3D) -> StandardMaterial3D:
	if not is_instance_valid(sprite) or not (sprite.mesh is QuadMesh):
		return null
	return (sprite.mesh as QuadMesh).material as StandardMaterial3D


## Sparks on the soft dot sprite: additive glints with a short bright head and a
## cooling tail, sized in metres rather than a tessellated ball.
static func soft_spark_particles(color: Color, amount: int, speed_min: float,
		speed_max: float, lifetime: float, size: float, one_shot: bool = true) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = clampi(amount, 1, 160)
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = 1.0 if one_shot else 0.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.damping_min = 0.5
	particles.damping_max = 1.6
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.5
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.99, 0.94, 1.0),
		Color(color.r, color.g, color.b, 0.9),
		Color(color.r * 0.88, color.g * 0.4, color.b * 0.2, 0.5),
		Color(color.r * 0.4, color.g * 0.16, color.b * 0.1, 0.0),
	])
	particles.color_ramp = gradient
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size * 2.6
	quad.material = particle_sprite_material(soft_dot_texture(), color, true)
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Flat additive ribbon in the local XZ plane opening toward -Z, unit radius and
## vertex-alpha taper. Scales into swishes and shock rings alike.
static func arc_ribbon_mesh(arc_degrees: float, segments: int = 32,
		inner_ratio: float = 0.9, taper: bool = true) -> ArrayMesh:
	var arc := deg_to_rad(clampf(arc_degrees, 15.0, 360.0))
	var steps := clampi(segments, 8, 96)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for index in steps + 1:
		var t := float(index) / steps
		var direction := Basis(Vector3.UP, -arc * 0.5 + arc * t) * Vector3(0.0, 0.0, -1.0)
		var fade := pow(sin(PI * t), 0.6) if taper else 1.0
		vertices.append(direction * inner_ratio)
		colors.append(Color(1.0, 1.0, 1.0, fade * 0.12))
		vertices.append(direction)
		colors.append(Color(1.0, 1.0, 1.0, fade))
	for index in steps:
		var base := index * 2
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func ribbon_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	return material


## Smooth smoke cloud that frees itself, built from individual billboard puffs.
## Quads instead of a particle system keep the colour explicit: albedo_color
## carries the tint and the fade, so no vertex-colour or particle-ramp path can
## tint the cloud black, and the texture is the only thing shaping the puff.
## `flow` pushes the puffs; `start_delay` holds the first puff back so smoke
## never covers a flash; `inner` spawns on a ring around the centre instead of
## on top of it.
static func _smoke_cloud(parent: Node3D, at: Vector3, scale: float, dark: bool,
		amount: int, lifetime: float, flow: Vector3 = Vector3.ZERO,
		start_delay: float = 0.0, inner: float = 0.0) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilitySmoke"
	parent.add_child(root)
	root.global_position = at
	var count := clampi(amount, 1, 48)
	var texture := smoke_texture()
	var pushed := flow.length_squared() > 0.0001
	var push := flow.normalized() if pushed else Vector3.UP
	var body := maxf(scale, 0.2)
	var motion := clampf(body, 0.35, 1.6)
	var spread := 0.42 * body
	var mode := 1 if dark else 0
	for index in count:
		var h1 := _hash_unit(index, 11)
		var h2 := _hash_unit(index, 29)
		var h3 := _hash_unit(index, 47)
		var angle := TAU * h1
		var tint := _smoke_tint(index, mode)
		var puff := MeshInstance3D.new()
		puff.name = "Puff"
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var material := sprite_material(texture, false, Color(tint.r, tint.g, tint.b, 0.0))
		quad.material = material
		puff.mesh = quad
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var radius := inner + spread * (0.35 + 0.65 * h2)
		var start := Vector3(cos(angle) * radius, (0.35 + 0.65 * h3) * spread * 0.7,
			sin(angle) * radius)
		puff.position = start
		puff.scale = Vector3.ONE * 0.9
		root.add_child(puff)
		var peak := body * (1.5 + 1.3 * h2)
		var alpha := 0.44 if dark else 0.32
		var drift := Vector3(cos(angle), 0.0, sin(angle)) * (0.22 + 0.5 * h2) * motion
		if pushed:
			drift += push * (0.35 + 0.5 * h1) * motion
		var end := start + Vector3(0.0, (0.28 + 0.5 * h2) * motion, 0.0) + drift
		var tween := puff.create_tween()
		tween.tween_interval(start_delay + 0.12 * lifetime * h3)
		tween.set_parallel(true)
		tween.tween_property(material, "albedo_color",
			Color(tint.r, tint.g, tint.b, alpha), 0.3 * lifetime)
		tween.tween_property(puff, "scale", Vector3.ONE * peak, 0.5 * lifetime)
		tween.tween_property(puff, "position", end, 0.62 * lifetime)
		tween.chain().tween_property(material, "albedo_color",
			Color(tint.r, tint.g, tint.b, 0.0), 0.42 * lifetime)
	var timer := root.create_tween()
	timer.tween_interval(maxf(lifetime, 0.2) + start_delay + 0.5)
	timer.tween_callback(root.queue_free)


## Deterministic 0..1 spread value: no RNG state, so every peer that plays the
## same cue builds the same puff layout.
static func _hash_unit(index: int, salt: int) -> float:
	var value := (index + 1) * 374761393 + salt * 668265263
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xFFFF) / 65535.0


## Warm grey ash (0) or charcoal with a violet and teal edge (1). The engulfing
## blink cloud builds its own near-black palette.
static func _smoke_tint(index: int, mode: int) -> Color:
	if mode == 1:
		match index % 3:
			0:
				return Color(0.10, 0.09, 0.12)
			1:
				return Color(0.26, 0.17, 0.34)
			_:
				return Color(0.12, 0.29, 0.31)
	return Color(0.50, 0.47, 0.43) if index % 3 == 0 else Color(0.56, 0.53, 0.49)


# --- Ability cues -----------------------------------------------------------

## Real blade ribbon for the spin, the double slash and the lunge. The trail
## follows the rig's equipped right blade for `seconds` and frees itself. It is
## presentation only: no damage, no authority, no changes to the rig.
static func blade_trail(parent: Node3D, rig, seconds: float, color: Color = STEEL) -> void:
	if not is_instance_valid(parent) or not is_instance_valid(rig):
		return
	if not rig.has_method("get_blade_base") or not rig.has_method("get_blade_tip"):
		return
	var trail = BladeTrail.new()
	parent.add_child(trail)
	trail.start(rig, seconds, color)


## Backstab blink beat. With `dark` it is the engulfing burst: a near-black cloud
## of 130 soft billboards, ~4 m wide and ~3.6 m tall, that swallows the body at
## the departure and arrival points. Otherwise it is a quick warm dust poof.
## Either way a thin vertical streak marks the displacement.
static func smoke_puff(parent: Node3D, at: Vector3, scale: float = 1.0,
		dark: bool = true) -> void:
	if not is_instance_valid(parent):
		return
	var size := maxf(scale, 0.2)
	if dark:
		_blink_burst(parent, at, size)
	else:
		_smoke_cloud(parent, at, 0.3 * size, false, 14, 0.55, Vector3.ZERO, 0.0,
			0.06 * size)
	_blink_streak(parent, at, size, dark)


## Near-black cloud that hides the ranger for a blink. Puff centres sit inside the
## body volume (a centred fill, not a ring), and `BLINK_PUFFS` heavily overlapping
## soft billboards keep the interior solid: charcoal 0.06-0.13 albedo with a faint
## violet-grey rim. Swells in 0.25 s, holds briefly and is mostly gone by 0.7 s.
## The billboards share one quad mesh and carry their own `material_override`, so
## the only per-puff resources are the tint and its fade tween.
static func _blink_burst(parent: Node3D, at: Vector3, scale: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilityBlinkBurst"
	parent.add_child(root)
	root.global_position = at
	var body := maxf(scale, 0.2)
	var texture := smoke_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for index in BLINK_PUFFS:
		var h1 := _hash_unit(index, 11)
		var h2 := _hash_unit(index, 29)
		var h3 := _hash_unit(index, 47)
		var h4 := _hash_unit(index, 71)
		var angle := TAU * h1
		var radius := (0.04 + 0.68 * h2 * h2) * body
		var lift := (0.48 + 1.60 * h3) * body
		var shade := 0.06 + 0.07 * h4
		var tint := Color(shade, shade, shade * 1.08)
		if index % 5 == 0:
			tint = Color(0.13, 0.11, 0.17)
		elif index % 7 == 0:
			tint = Color(0.09, 0.11, 0.13)
		var puff := MeshInstance3D.new()
		puff.name = "Puff"
		var material := sprite_material(texture, false, Color(tint.r, tint.g, tint.b, 0.0))
		puff.mesh = quad
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var start := Vector3(cos(angle) * radius, lift, sin(angle) * radius)
		puff.position = start
		puff.scale = Vector3.ONE * 0.5
		root.add_child(puff)
		var peak := body * (0.9 + 0.6 * h1)
		var alpha := 0.55 + 0.10 * h2
		var end := start + Vector3(cos(angle) * 0.26, 0.12 + 0.24 * h2,
			sin(angle) * 0.26)
		var tween := puff.create_tween()
		tween.tween_interval(0.06 * h4)
		tween.set_parallel(true)
		tween.tween_property(material, "albedo_color",
			Color(tint.r, tint.g, tint.b, alpha), 0.12)
		tween.tween_property(puff, "scale", Vector3.ONE * peak, 0.25)
		tween.tween_property(puff, "position", end, 0.25)
		tween.set_parallel(false)
		tween.tween_interval(0.1)
		tween.tween_property(material, "albedo_color",
			Color(tint.r, tint.g, tint.b, 0.0), 0.38)
	var timer := root.create_tween()
	timer.tween_interval(0.95)
	timer.tween_callback(root.queue_free)


## Thin vertical flash that sells the step. Additive and short, so it reads as a
## displacement line and never hides the body. Charcoal violet for the blink.
static func _blink_streak(parent: Node3D, at: Vector3, scale: float,
		dark: bool) -> void:
	var root := Node3D.new()
	root.name = "AbilityBlinkStreak"
	parent.add_child(root)
	root.global_position = at
	var tint := Color(0.42, 0.34, 0.56) if dark else Color(0.70, 0.62, 0.98)
	var streak := sprite_flash(root, Vector3(0.0, 0.75 * scale, 0.0),
		Vector2(0.16, 1.5) * scale, Color(tint.r, tint.g, tint.b, 0.0))
	var material := sprite_tint(streak)
	var tween := root.create_tween()
	tween.tween_property(material, "albedo_color", Color(tint.r, tint.g, tint.b, 0.45), 0.04)
	tween.tween_interval(0.08)
	tween.set_parallel(true)
	tween.tween_property(streak, "scale", Vector3(0.4, 1.0, 1.0), 0.3)
	tween.tween_property(material, "albedo_color", Color(tint.r, tint.g, tint.b, 0.0), 0.3)
	tween.chain().tween_callback(root.queue_free)


## Fast AOE read for the full-turn cut: a low warm dust ring in mix blend, a few
## thin radial streaks, a small spark burst and a short warm light. The blade
## ribbon is added separately by the cue.
static func spin_burst(parent: Node3D, origin: Vector3, radius: float) -> void:
	if not is_instance_valid(parent):
		return
	var reach := maxf(radius, 1.2)
	var root := Node3D.new()
	root.name = "AbilitySpinBurst"
	parent.add_child(root)
	root.global_position = origin
	var tween := root.create_tween()
	tween.set_parallel(true)
	# Ground dust: two offset, very thin warm rings rather than one painted hoop,
	# and dust puffs drawn along the rim to break the outline.
	for band in 2:
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.96
		ring_mesh.outer_radius = 1.0
		ring_mesh.rings = 64
		ring_mesh.ring_segments = 6
		var ring_material := StandardMaterial3D.new()
		ring_material.albedo_color = Color(DUST.r * 0.92, DUST.g * 0.86, DUST.b * 0.78,
			0.13 if band == 0 else 0.07)
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_material.disable_receive_shadows = true
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.material_override = ring_material
		ring.position = Vector3(0.0, 0.03 + 0.035 * float(band), 0.0)
		ring.scale = Vector3(0.5, 0.06, 0.5)
		root.add_child(ring)
		var target := reach * (0.78 - 0.14 * float(band))
		var delay := 0.05 * float(band)
		tween.tween_property(ring, "scale", Vector3(target, 0.02, target), 0.36) \
			.set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring_material, "albedo_color",
			Color(DUST.r * 0.9, DUST.g * 0.84, DUST.b * 0.76, 0.0), 0.5).set_delay(delay)
	# A few thin radial speed streaks, warm and short.
	var streak_count := 3
	for index in streak_count:
		var angle := TAU * float(index) / float(streak_count) + 0.21
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 0.05)
		var material := sprite_material(soft_dot_texture(), true, Color(1.0, 0.82, 0.56, 0.5))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		quad.material = material
		var streak := MeshInstance3D.new()
		streak.mesh = quad
		streak.basis = Basis(outward, Vector3.UP, outward.cross(Vector3.UP))
		streak.position = outward * 0.35 + Vector3.UP * (0.3 + 0.16 * sin(float(index) * 1.7))
		streak.scale = Vector3(0.15, 1.0, 1.0)
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(streak)
		var delay := 0.02 * float(index)
		tween.tween_property(streak, "scale", Vector3(clampf(reach * 0.35, 0.3, 1.1), 1.0, 1.0), 0.2) \
			.set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(material, "albedo_color", Color(1.0, 0.82, 0.56, 0.0), 0.22).set_delay(delay)
	var sparks := soft_spark_particles(Color("ffd9a0"), 14, 1.6, 3.6, 0.32, 0.038)
	sparks.emission_sphere_radius = 0.14
	sparks.gravity = Vector3(0.0, -5.5, 0.0)
	sparks.emitting = true
	root.add_child(sparks)
	var light := flash_light(Color("e8c9a0"), 1.1, reach * 1.1)
	light.position = Vector3(0.0, 0.75, 0.0)
	root.add_child(light)
	tween.tween_property(light, "light_energy", 0.0, 0.2)
	tween.set_parallel(false)
	tween.tween_interval(0.75)
	tween.tween_callback(root.queue_free)
	# Dust along the rim breaks the ring outline, and a loose cluster sits at the
	# feet so the AOE still reads as kicked-up ground.
	_smoke_cloud(parent, origin + Vector3.UP * 0.08, 0.5, false, 12, 0.9,
		Vector3.ZERO, 0.0, reach * 0.55)
	_smoke_cloud(parent, origin + Vector3.UP * 0.1, 0.4, false, 8, 0.8)


## Boss-first impact at a shield face: white-hot flash, a forward shock ring, a
## forward cone of soft sparks and dust, and a short light. `heavy` scales the
## tower slam up without changing the shape.
static func shield_impact(parent: Node3D, at: Vector3, forward: Vector3,
		radius: float, heavy: bool = false) -> void:
	if not is_instance_valid(parent):
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	# Everything is sized to the shield, never to the body: a slam grows the
	# whole read by 30% instead of wrapping the actor in a dome.
	var weight := 1.3 if heavy else 1.0
	var ring_radius := clampf(radius, 0.35, 0.75) * 0.62 * weight
	var root := Node3D.new()
	root.name = "AbilityShieldImpact"
	parent.add_child(root)
	root.global_position = at
	root.global_basis = Basis.looking_at(flat, Vector3.UP)
	var light := flash_light(Color("ffe3bd"), 2.4 * weight, 2.2 * weight)
	light.position = Vector3(0.0, 0.0, -0.3)
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	# White-hot core on the boss with a warm falloff behind it.
	var core := sprite_flash(root, Vector3(0.0, 0.0, -0.07), Vector2.ONE * 0.42 * weight,
		HOT_WHITE)
	core.scale = Vector3.ONE * 0.35
	var halo := sprite_flash(root, Vector3(0.0, 0.0, -0.05), Vector2.ONE * 0.8 * weight,
		Color(1.0, 0.70, 0.38, 0.55))
	halo.scale = Vector3.ONE * 0.4
	tween.tween_property(core, "scale", Vector3.ONE, 0.12) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(core), "albedo_color",
		Color(HOT_WHITE.r, HOT_WHITE.g, HOT_WHITE.b, 0.0), 0.15)
	tween.tween_property(halo, "scale", Vector3.ONE * 1.2, 0.17) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(halo), "albedo_color", Color(1.0, 0.70, 0.38, 0.0), 0.2)
	# Thin shock ring in the plane of the shield face, opening away from the boss.
	var shock := MeshInstance3D.new()
	shock.name = "ShockRing"
	shock.mesh = arc_ribbon_mesh(360.0, 48, 0.84, false)
	var shock_material := ribbon_material(Color(1.0, 0.86, 0.62, 0.55))
	shock.material_override = shock_material
	shock.rotation.x = -PI * 0.5
	shock.scale = Vector3.ONE * ring_radius * 0.3
	root.add_child(shock)
	tween.tween_property(shock, "scale", Vector3.ONE * ring_radius, 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(shock_material, "albedo_color", Color(1.0, 0.86, 0.62, 0.0), 0.24)
	# Six to ten short streaks radiating in the shield plane.
	var streak_count := 8 if heavy else 6
	for index in streak_count:
		var angle := TAU * float(index) / float(streak_count) + 0.4
		var radial := Vector3(cos(angle), sin(angle), 0.0)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.26, 0.022)
		var material := sprite_material(soft_dot_texture(), true, Color(1.0, 0.88, 0.68, 0.55))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		quad.material = material
		var streak := MeshInstance3D.new()
		streak.mesh = quad
		streak.basis = Basis(Vector3(0.0, 0.0, 1.0), angle)
		streak.position = radial * 0.1 + Vector3(0.0, 0.0, -0.06)
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(streak)
		var delay := 0.015 * float(index % 4)
		tween.tween_property(streak, "position",
			radial * (0.3 * weight) + Vector3(0.0, 0.0, -0.06), 0.16).set_delay(delay)
		tween.tween_property(streak, "scale", Vector3(1.3, 1.0, 1.0), 0.16).set_delay(delay)
		tween.tween_property(material, "albedo_color",
			Color(1.0, 0.88, 0.68, 0.0), 0.18).set_delay(delay)
	# Four short forward cone lines: the bash pushes the boss, so the burst has a
	# direction instead of only a pop.
	for index in 4:
		var cone_angle := TAU * float(index) / 4.0 + 0.65
		var spread_out := Vector3(cos(cone_angle), sin(cone_angle) * 0.5, 0.0)
		var line_quad := QuadMesh.new()
		line_quad.size = Vector2(0.42, 0.03)
		var line_material := sprite_material(soft_dot_texture(), true,
			Color(1.0, 0.90, 0.72, 0.5))
		line_quad.material = line_material
		var line := MeshInstance3D.new()
		line.mesh = line_quad
		line.position = spread_out * 0.14 + Vector3(0.0, 0.0, -0.2)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(line)
		var line_delay := 0.02 * float(index)
		tween.tween_property(line, "position",
			spread_out * 0.26 + Vector3(0.0, 0.0, -0.62 * weight), 0.16).set_delay(line_delay)
		tween.tween_property(line, "scale", Vector3(1.6, 1.0, 1.0), 0.16).set_delay(line_delay)
		tween.tween_property(line_material, "albedo_color",
			Color(1.0, 0.90, 0.72, 0.0), 0.18).set_delay(line_delay)
	# Soft sparks in a forward cone, plus a tight jet along the shield normal.
	var sparks := soft_spark_particles(Color("ffd9a0"), 16 if heavy else 10,
		1.4, 3.6, 0.34, 0.04)
	sparks.direction = Vector3(0.0, 0.0, -1.0)
	sparks.spread = 48.0
	sparks.emission_sphere_radius = 0.1
	sparks.gravity = Vector3(0.0, -5.0, 0.0)
	sparks.emitting = true
	root.add_child(sparks)
	var jet := soft_spark_particles(Color("ffe9c4"), 8, 3.4, 6.2, 0.24, 0.03)
	jet.direction = Vector3(0.0, 0.0, -1.0)
	jet.spread = 14.0
	jet.emission_sphere_radius = 0.06
	jet.gravity = Vector3(0.0, -2.0, 0.0)
	jet.emitting = true
	root.add_child(jet)
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.set_parallel(false)
	tween.tween_interval(0.4)
	tween.tween_callback(root.queue_free)
	# Warm dust shoved along the shield normal, plus a little at the feet, so the
	# impact has weight without growing into a bubble.
	_smoke_cloud(parent, at, 0.34 * weight, false, 8, 0.7, flat)
	_smoke_cloud(parent, at - Vector3.UP * 0.35, 0.36 * weight, false, 4, 0.9)


## Short red-and-gold plunge read for a backstab: hot core, soft streak, a spark
## scatter and a small dark smoke wisp. Presentation only.
static func backstab_flash(parent: Node3D, at: Vector3, forward: Vector3) -> void:
	if not is_instance_valid(parent):
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var root := Node3D.new()
	root.name = "AbilityBackstab"
	parent.add_child(root)
	root.global_position = at
	root.global_basis = Basis.looking_at(flat, Vector3.UP)
	var light := flash_light(EMBER_RED, 2.2, 2.4)
	light.position = Vector3(0.0, 0.2, -0.2)
	root.add_child(light)
	var halo := sprite_flash(root, Vector3(0.0, 0.06, -0.03), Vector2.ONE * 0.72,
		Color(0.92, 0.28, 0.18, 0.8))
	halo.scale = Vector3.ONE * 0.4
	var core := sprite_flash(root, Vector3(0.0, 0.06, -0.06), Vector2.ONE * 0.42,
		Color(1.0, 0.93, 0.72, 1.0))
	core.scale = Vector3.ONE * 0.32
	var streak := sprite_flash(root, Vector3(0.0, 0.07, 0.0), Vector2(0.7, 0.1),
		Color(1.0, 0.62, 0.44, 0.85))
	streak.scale = Vector3(0.4, 1.0, 1.0)
	var sparks := soft_spark_particles(Color("ffb27a"), 12, 1.2, 3.2, 0.34, 0.038)
	sparks.direction = Vector3(0.0, 0.0, -1.0)
	sparks.spread = 60.0
	sparks.emission_sphere_radius = 0.1
	sparks.gravity = Vector3(0.0, -6.0, 0.0)
	sparks.emitting = true
	root.add_child(sparks)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(core, "scale", Vector3.ONE * 1.15, 0.12) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(core), "albedo_color", Color(1.0, 0.93, 0.72, 0.0), 0.17)
	tween.tween_property(halo, "scale", Vector3.ONE * 1.2, 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_tint(halo), "albedo_color", Color(0.92, 0.28, 0.18, 0.0), 0.24)
	tween.tween_property(streak, "scale", Vector3(1.3, 1.0, 1.0), 0.2)
	tween.tween_property(sprite_tint(streak), "albedo_color", Color(1.0, 0.62, 0.44, 0.0), 0.22)
	tween.tween_property(light, "light_energy", 0.0, 0.2)
	tween.set_parallel(false)
	tween.tween_interval(0.4)
	tween.tween_callback(root.queue_free)
	_smoke_cloud(parent, at + Vector3.UP * 0.12, 0.3, true, 8, 0.85)


# --- Charge wake ------------------------------------------------------------

## Fast, low wake for the lunging thrust: ground dust under the stride, a short
## skid smear, thin horizontal speed streaks trailing the body in their own
## additive layer, and a few fading afterimage wisps at hip and chest height.
## Every piece is a camera-facing billboard, so nothing vanishes edge-on at the
## speed the dash moves. Presentation only: no damage, no authority, and the
## driver frees itself shortly after the charge.
static func lunge_wake(parent: Node3D, rig, seconds: float) -> void:
	if not is_instance_valid(parent) or not is_instance_valid(rig):
		return
	if not (rig is Node3D):
		return
	var wake = LungeWake.new()
	parent.add_child(wake)
	var target := parent
	wake.start(rig, seconds, func(kind: int, at: Vector3, forward: Vector3,
			index: int) -> void:
		_lunge_beat(target, kind, at, forward, index))


## One emission beat of the charge wake. 0 = ground dust, 1 = afterimage wisp,
## 2 = skid smear; 1 and 2 also drop a speed streak so the trailing band reads.
static func _lunge_beat(parent: Node3D, kind: int, at: Vector3, forward: Vector3,
		index: int) -> void:
	if not is_instance_valid(parent):
		return
	var behind := -forward
	if kind == 0:
		var size := 1.05 + 0.30 * _hash_unit(index, 13)
		var alpha := 0.50 + 0.08 * float(index % 2)
		_fading_sprite(parent, at + Vector3.UP * 0.1 + behind * 0.25,
			Vector2.ONE * size, Color(0.82, 0.74, 0.60), alpha, 1.2, 0.45, false)
		return
	var lift := 0.72 if index % 2 == 0 else 1.15
	if kind == 2:
		_fading_sprite(parent, at + Vector3.UP * 0.05 + behind * 0.15,
			Vector2(1.6, 0.25), Color(0.78, 0.70, 0.55), 0.55, 1.15, 0.4, false)
		lift = 0.55
	else:
		_fading_sprite(parent, at + Vector3.UP * lift + behind * 0.28,
			Vector2.ONE * 1.0, Color(0.84, 0.80, 0.70), 0.32, 1.25, 0.4, false)
	_fading_sprite(parent, at + Vector3.UP * (lift + 0.08) + behind * 0.55,
		Vector2(2.5, 0.10), Color(1.0, 0.95, 0.82), 0.5, 1.05, 0.28, true)


## Tiny grow-and-fade billboard sprite that owns its node and frees it. `size` is
## the final footprint, `grow` the scale it swells to, `life` the whole life.
static func _fading_sprite(parent: Node3D, at: Vector3, size: Vector2, tint: Color,
		peak: float, grow: float, life: float, additive: bool) -> void:
	var holder := Node3D.new()
	holder.name = "WakeSprite"
	# force_readable_name: duplicates must stay findable by name for QA probes.
	parent.add_child(holder, true)
	holder.global_position = at
	var quad := QuadMesh.new()
	quad.size = size
	var material := sprite_material(soft_dot_texture() if additive else smoke_texture(),
		additive, Color(tint.r, tint.g, tint.b, 0.0))
	quad.material = material
	var sprite := MeshInstance3D.new()
	sprite.name = "Sprite"
	sprite.mesh = quad
	sprite.scale = Vector3.ONE * 0.6
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(sprite)
	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(material, "albedo_color",
		Color(tint.r, tint.g, tint.b, peak), minf(life * 0.3, 0.08))
	tween.tween_property(sprite, "scale", Vector3.ONE * grow, life * 0.6)
	tween.set_parallel(false)
	tween.tween_property(material, "albedo_color",
		Color(tint.r, tint.g, tint.b, 0.0), life * 0.4)
	tween.tween_callback(holder.queue_free)
