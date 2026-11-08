extends RefCounted
## The arena's proc visuals that are not a projectile: the blood arc's lightning,
## a nova's ring, and the small flash a kill leaves.
##
## Host and guest both run these: the host draws the consequence it rolled, and a
## guest draws the same one from the event the host broadcast. They are purely
## presentational - no damage, no collision, no gameplay state - so a peer that
## misses one loses only a flash.

const Geo = preload("res://scripts/geo.gd")

const BLOOD := Color(0.95, 0.22, 0.16)
const SPARK := Color(1.0, 0.72, 0.36)


## A jagged arc between two points: the Blood Arc's zap, and the same shape a
## future chain effect can reuse.
static func lightning(parent: Node3D, from: Vector3, to: Vector3,
		colour: Color = BLOOD) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "ProcLightning"
	parent.add_child(node)
	# World-space vertices, world-space node: an island dressing node with its own
	# transform must not bend the arc into its local frame.
	node.top_level = true
	var points := _jagged(from, to, 9)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 4.0
	material.vertex_color_use_as_albedo = false
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 2.4
	light.omni_range = 5.0
	light.position = to
	node.add_child(light)
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(instance, "transparency", 1.0, 0.18)
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.chain().tween_callback(node.queue_free)


## A ring on the ground: the nova, the bomb's burst, the pedestal's halo.
static func ring(parent: Node3D, at: Vector3, colour: Color = BLOOD,
		size: float = 2.0, hold: float = 0.26) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "ProcRing"
	parent.add_child(node)
	node.top_level = true
	node.global_position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.55)
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.55, size * 0.9)
	torus.outer_radius = maxf(0.62, size)
	torus.rings = 24
	torus.ring_segments = 8
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.material_override = material
	instance.rotation.x = PI * 0.5
	instance.position = Vector3(0.0, 0.08, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(instance, "scale", Vector3.ONE * 2.6, hold)
	tween.tween_property(material, "albedo_color", Color(colour.r, colour.g, colour.b, 0.0), hold)
	tween.chain().tween_callback(node.queue_free)


## A short, bright flare at a point: a splinter's birth, an absorbed charge.
static func flare(parent: Node3D, at: Vector3, colour: Color = SPARK,
		size: float = 0.5) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var node := Node3D.new()
	node.name = "ProcFlare"
	parent.add_child(node)
	node.top_level = true
	node.global_position = at
	var material := Geo.material(colour, 0.0, 0.4)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere := Geo.sphere(node, size, Vector3.ZERO, material)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3.ONE * 0.1, 0.2)
	tween.tween_property(sphere, "transparency", 1.0, 0.2)
	tween.chain().tween_callback(node.queue_free)


static func _jagged(from: Vector3, to: Vector3, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(from.x * 17.0) + absf(to.z * 31.0) + 7.0)
	var axis := (to - from)
	var length := axis.length()
	if length <= 0.001:
		return PackedVector3Array([from, to])
	var direction := axis / length
	var side := direction.cross(Vector3.UP)
	if side.length_squared() <= 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	for index in steps + 1:
		var t := float(index) / float(steps)
		var point := from.lerp(to, t)
		if index > 0 and index < steps:
			var jitter := side * rng.randf_range(-0.22, 0.22) + Vector3.UP * rng.randf_range(-0.18, 0.18)
			point += jitter * (length * 0.12 + 0.15)
		out.append(point)
	return out
