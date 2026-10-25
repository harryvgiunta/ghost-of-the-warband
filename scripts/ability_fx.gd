extends RefCounted
## Procedural presentation for item skills: blade arcs, shockwaves, fire and
## bone bursts. Nothing here changes damage; scenes call it on every peer.

const FIRE := Color("ff8a3c")
const FIRE_CORE := Color("ffd9a0")
const BONE := Color("bfe6c8")
const BONE_CORE := Color("e8fff1")
const STEEL := Color("e9f2ff")


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


static func smoke_particles(color: Color, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.35
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 70.0
	particles.gravity = Vector3(0.0, 0.55, 0.0)
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 2.2
	particles.damping_min = 0.6
	particles.damping_max = 1.8
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 2.1
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.55),
		Color(color.r * 0.5, color.g * 0.45, color.b * 0.4, 0.34),
		Color(0.12, 0.11, 0.1, 0.0),
	])
	particles.color_ramp = gradient
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.disable_receive_shadows = true
	quad.material = material
	particles.mesh = quad
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
	var sparks := spark_particles(color, int(28 * scale), 2.6 * scale, 7.5 * scale, 0.5, 0.045 * scale)
	sparks.emitting = true
	root.add_child(sparks)
	var flash := flash_light(color, 2.6 * scale, 3.2 * scale)
	root.add_child(flash)
	var tween := root.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.26)
	tween.tween_interval(0.55)
	tween.tween_callback(root.queue_free)


## Expanding fireball detonation: hot shell, shockwave ring, sparks, smoke and
## a short light flash. `radius` is the gameplay blast radius.
static func explosion(parent: Node3D, at: Vector3, radius: float,
		color: Color = FIRE, core: Color = FIRE_CORE) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "AbilityExplosion"
	parent.add_child(root)
	root.global_position = at
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 1.0
	shell_mesh.height = 2.0
	shell_mesh.radial_segments = 24
	shell_mesh.rings = 12
	var shell_material := glow_material(core, 3.6, 0.55)
	var shell := MeshInstance3D.new()
	shell.mesh = shell_mesh
	shell.material_override = shell_material
	shell.scale = Vector3.ONE * 0.12
	root.add_child(shell)
	var inner_mesh := SphereMesh.new()
	inner_mesh.radius = 1.0
	inner_mesh.height = 2.0
	inner_mesh.radial_segments = 16
	inner_mesh.rings = 8
	var inner_material := glow_material(color, 5.0, 0.9)
	var inner := MeshInstance3D.new()
	inner.mesh = inner_mesh
	inner.material_override = inner_material
	inner.scale = Vector3.ONE * 0.06
	root.add_child(inner)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	var ring_material := glow_material(core, 2.4, 0.8)
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_material
	ring.scale = Vector3(0.15, 0.5, 0.15)
	root.add_child(ring)
	var sparks := spark_particles(color, 64, 4.0, 11.0, 0.65, 0.075)
	sparks.emitting = true
	root.add_child(sparks)
	var chunks := spark_particles(core, 18, 6.0, 13.0, 0.75, 0.05)
	chunks.emitting = true
	root.add_child(chunks)
	var smoke := smoke_particles(Color(0.22, 0.19, 0.17), 22, 1.25)
	smoke.emitting = true
	root.add_child(smoke)
	var light := flash_light(color, 9.0, radius * 3.0)
	root.add_child(light)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * radius * 0.72, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(inner, "scale", Vector3.ONE * radius * 0.46, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3(radius, radius * 0.35, radius), 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell_material, "albedo_color", Color(core.r, core.g, core.b, 0.0), 0.34)
	tween.tween_property(inner_material, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.28)
	tween.tween_property(ring_material, "albedo_color", Color(core.r, core.g, core.b, 0.0), 0.4)
	tween.tween_property(light, "light_energy", 0.0, 0.36)
	tween.set_parallel(false)
	tween.tween_interval(1.0)
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
