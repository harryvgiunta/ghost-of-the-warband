class_name BrandedFx
extends RefCounted
## Presentation for the six branded abilities: a ground ring, a cone of force and
## a flash.
##
## Each primitive is a plain `MeshInstance3D` wearing an unshaded additive
## `StandardMaterial3D`, tweened open and freed by its own tween, so a fight that
## fires every sigil leaves nothing behind and nothing has to be tracked or
## cleaned up by the scene. There are no particles and no threads: a torus, a
## cylinder and a sphere read the shape of the blow from the shoulder camera.
##
## Headless builds draw nothing. The ability code runs identically, the
## regression just does not allocate meshes no frame will ever show.

## Default life of a ring, in seconds.
const FADE := 0.45
## A ring starts smaller than its true radius and opens onto it, which reads as
## the shockwave arriving rather than as a decal appearing.
const RING_OPEN := 0.86

static func live() -> bool:
	return DisplayServer.get_name() != "headless"

static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	return material

## Adds one primitive at `at` and hands its fade-and-free to its own tween.
## `grow` is the scale it opens to; the alpha always reaches zero at `seconds`.
static func _mount(parent: Node3D, mesh: Mesh, colour: Color, at: Vector3,
		basis: Basis, seconds: float, grow: float) -> MeshInstance3D:
	if not live() or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(colour)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_transform = Transform3D(basis, at)
	if not is_equal_approx(grow, 1.0):
		var tween := node.create_tween()
		tween.set_parallel(true)
		tween.tween_property(node, "scale", basis.get_scale() * grow, seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(node.material_override, "albedo_color:a", 0.0, seconds) \
			.set_delay(seconds * 0.3)
		tween.chain().tween_callback(node.queue_free)
	else:
		var fade := node.create_tween()
		fade.tween_property(node.material_override, "albedo_color:a", 0.0, seconds) \
			.set_delay(seconds * 0.3)
		fade.tween_callback(node.queue_free)
	return node

## A flat ring on the floor: the shockwave, the closing wound, the ward circle.
static func ring(parent: Node3D, centre: Vector3, radius: float,
		colour: Color, seconds: float = FADE) -> MeshInstance3D:
	if radius <= 0.0:
		return null
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.9
	mesh.outer_radius = radius
	mesh.rings = 28
	mesh.ring_segments = 6
	# TorusMesh already lies in the XZ plane, so the ring needs no rotation.
	return _mount(parent, mesh, colour, centre + Vector3.UP * 0.05,
			Basis.IDENTITY.scaled(Vector3.ONE * RING_OPEN), seconds, 1.0 / RING_OPEN)

## A short bright sphere: the muzzle, the staff's star, the impact.
static func flash(parent: Node3D, centre: Vector3, radius: float,
		colour: Color, seconds: float = 0.22) -> MeshInstance3D:
	if radius <= 0.0:
		return null
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _mount(parent, mesh, colour, centre, Basis.IDENTITY, seconds, 1.7)

## A tapering cylinder laid along `forward`: the hellfire cone, and any other
## wedge-shaped burst. The base sits on `origin`, the point reaches `radius`.
static func cone(parent: Node3D, origin: Vector3, forward: Vector3, radius: float,
		degrees: float, colour: Color, seconds: float = FADE) -> MeshInstance3D:
	if radius <= 0.0 or forward.length_squared() < 0.000001:
		return null
	var axis := forward.normalized()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = radius * tan(deg_to_rad(clampf(degrees, 5.0, 170.0)) * 0.5)
	mesh.height = radius
	mesh.radial_segments = 18
	# A cylinder runs along its +Y; looking_at points -Z down the axis, so tip Y
	# onto -Z afterwards. A vertical cone has no usable up vector, so fall back
	# to the forward axis as the roll reference.
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var basis := Basis.looking_at(axis, up) * Basis(Vector3.RIGHT, -PI * 0.5)
	return _mount(parent, mesh, colour, origin + axis * (radius * 0.5), basis, seconds, 1.0)
