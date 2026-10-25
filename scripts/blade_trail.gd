extends Node3D
## Short-lived additive ribbon that follows a rig's equipped right-hand blade.
##
## `AbilityFx.blade_trail` owns the instance; the ability cues only ask for a
## duration, so the spin, the double slash and the lunge share one look. The node
## samples the rig's public blade base/tip every physics frame and keeps a short
## window of that sweep (SAMPLE_WINDOW), which is drawn as two thin strips near
## the tip: a narrow bright leading edge and a wider faint halo. Nothing spans
## base to tip, and the peak alpha is a third of white, so the result reads as a
## quick steel swish instead of a sail. It reads the rig and never damages,
## edits or reparents anything on it.

const SAMPLE_WINDOW := 0.11
const MAX_SAMPLES := 24
const LINGER := 0.18
const TELEPORT_DISTANCE := 2.5
const CORE_WIDTH := 0.055
const HALO_WIDTH := 0.17
const CORE_TINT := Color(0.60, 0.86, 1.0)
const HEAD_TINT := Color(1.0, 0.87, 0.58)

static var _dot_texture: Texture2D

var _rig
var _color := Color("e9f2ff")
var _remaining := 0.0
var _stopped := 0.0
var _clock := 0.0
var _bases := PackedVector3Array()
var _tips := PackedVector3Array()
var _ages := PackedFloat32Array()
var _mesh := ImmediateMesh.new()
var _view: MeshInstance3D
var _sparks: CPUParticles3D
var _spark_ramp := Gradient.new()


func _ready() -> void:
	_build_view()


## Called by AbilityFx right after the node is parented.
func start(rig, seconds: float, color: Color) -> void:
	_rig = rig
	_color = color
	_remaining = clampf(seconds, 0.05, 3.0)
	_build_view()
	_build_sparks()
	if _sparks != null:
		_sparks.emitting = _remaining > 0.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_rig) or not _rig.has_method("get_blade_base") \
			or not _rig.has_method("get_blade_tip"):
		queue_free()
		return
	_clock += delta
	if _remaining > 0.0:
		_remaining -= delta
		_sample()
		if _remaining <= 0.0:
			_stopped = 0.0
	elif _stopped > SAMPLE_WINDOW + LINGER:
		queue_free()
		return
	else:
		_stopped += delta
	_prune()
	_rebuild()
	_update_sparks()


## Glints only while the blade is actually travelling, so a held blade does not
## keep leaking sparks.
func _update_sparks() -> void:
	if not is_instance_valid(_sparks):
		return
	var count := _tips.size()
	if count <= 0:
		_sparks.emitting = false
		return
	_sparks.global_position = _tips[count - 1]
	var moving := count > 1 and _tips[count - 1].distance_to(_tips[count - 2]) > 0.012
	_sparks.emitting = moving and _remaining > 0.0


func _sample() -> void:
	var base: Vector3 = _rig.get_blade_base("right")
	var tip: Vector3 = _rig.get_blade_tip("right")
	if not base.is_finite() or not tip.is_finite():
		return
	if base.distance_squared_to(tip) < 0.0001:
		return
	if _bases.size() > 0 and _bases[_bases.size() - 1].distance_squared_to(base) \
			> TELEPORT_DISTANCE * TELEPORT_DISTANCE:
		_bases.clear()
		_tips.clear()
		_ages.clear()
	_bases.append(base)
	_tips.append(tip)
	_ages.append(_clock)
	while _bases.size() > MAX_SAMPLES:
		_bases.remove_at(0)
		_tips.remove_at(0)
		_ages.remove_at(0)


func _prune() -> void:
	var cut := 0
	while cut < _ages.size() and _clock - _ages[cut] > SAMPLE_WINDOW:
		cut += 1
	if cut > 0:
		_bases = _bases.slice(cut)
		_tips = _tips.slice(cut)
		_ages = _ages.slice(cut)


## 1.0 for the newest sample, 0.0 once a sample has left the window.
func _fade(index: int) -> float:
	return clampf(1.0 - (_clock - _ages[index]) / SAMPLE_WINDOW, 0.0, 1.0)


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var count := _bases.size()
	if count < 2:
		return
	_surface(count, true)
	_surface(count, false)


## One strip hugging the tip: `core` is the narrow bright edge, otherwise the
## wider faint halo. Both narrow and dim as samples age, so only a crescent
## near the current tip survives.
func _surface(count: int, core: bool) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in count - 1:
		_strip_quad(index, count, core)
	_mesh.surface_end()


func _strip_quad(index: int, count: int, core: bool) -> void:
	var fade_a := _fade(index)
	var fade_b := _fade(index + 1)
	var inner_a := _inner_point(index, core, fade_a)
	var outer_a := _outer_point(index, core)
	var inner_b := _inner_point(index + 1, core, fade_b)
	var outer_b := _outer_point(index + 1, core)
	var color_inner_a := _strip_color(fade_a, core, false, index, count)
	var color_outer_a := _strip_color(fade_a, core, true, index, count)
	var color_inner_b := _strip_color(fade_b, core, false, index + 1, count)
	var color_outer_b := _strip_color(fade_b, core, true, index + 1, count)
	_mesh.surface_set_color(color_inner_a)
	_mesh.surface_add_vertex(inner_a)
	_mesh.surface_set_color(color_outer_a)
	_mesh.surface_add_vertex(outer_a)
	_mesh.surface_set_color(color_inner_b)
	_mesh.surface_add_vertex(inner_b)
	_mesh.surface_set_color(color_outer_b)
	_mesh.surface_add_vertex(outer_b)
	_mesh.surface_set_color(color_outer_a)
	_mesh.surface_add_vertex(outer_a)
	_mesh.surface_set_color(color_outer_b)
	_mesh.surface_add_vertex(outer_b)
	_mesh.surface_set_color(color_inner_b)
	_mesh.surface_add_vertex(inner_b)


## Inner (hilt-side) edge of the strip: pulled in toward the tip as it ages.
func _inner_point(index: int, core: bool, fade: float) -> Vector3:
	var base := _bases[index]
	var tip := _tips[index]
	var axis := tip - base
	if axis.length_squared() < 0.000001:
		return tip
	var width := (CORE_WIDTH if core else HALO_WIDTH) * (0.30 + 0.70 * fade)
	return tip - axis.normalized() * width


func _outer_point(index: int, core: bool) -> Vector3:
	var base := _bases[index]
	var tip := _tips[index]
	var axis := tip - base
	if axis.length_squared() < 0.000001:
		return tip
	return tip + axis.normalized() * (0.01 if core else 0.03)


## Steel-cyan body with a faint gold leading edge on the newest samples. Peak
## alpha stays well under half so additive stacking never blows out to white.
func _strip_color(fade: float, core: bool, leading: bool, index: int, count: int) -> Color:
	var head := clampf(1.0 - float(count - 1 - index) / 3.0, 0.0, 1.0)
	var tint := CORE_TINT.lerp(HEAD_TINT, 0.42 * head * fade)
	tint = tint.lerp(_color, 0.25)
	if core:
		tint.a = (0.34 if leading else 0.10) * pow(fade, 1.5)
	else:
		tint.a = (0.075 if leading else 0.02) * pow(fade, 2.2)
	return tint


func _build_view() -> void:
	if _view != null:
		return
	top_level = true
	global_transform = Transform3D.IDENTITY
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	_view = MeshInstance3D.new()
	_view.name = "Ribbon"
	_view.mesh = _mesh
	_view.material_override = material
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_view)


## Small, sparse steel glints flung off the tip while the blade is moving.
func _build_sparks() -> void:
	if _sparks != null:
		return
	_spark_ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	_spark_ramp.colors = PackedColorArray([
		Color(1.0, 0.99, 0.95, 0.9),
		Color(_color.r, _color.g, _color.b, 0.45),
		Color(_color.r * 0.7, _color.g * 0.8, _color.b, 0.0),
	])
	_sparks = CPUParticles3D.new()
	_sparks.name = "TipSparks"
	_sparks.amount = 10
	_sparks.lifetime = 0.22
	_sparks.one_shot = false
	_sparks.explosiveness = 0.0
	_sparks.local_coords = false
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.02
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.gravity = Vector3(0.0, -3.4, 0.0)
	_sparks.initial_velocity_min = 0.25
	_sparks.initial_velocity_max = 1.1
	_sparks.damping_min = 0.8
	_sparks.damping_max = 1.8
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	_sparks.color_ramp = _spark_ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _soft_dot()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	quad.material = material
	_sparks.mesh = quad
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.emitting = false
	add_child(_sparks)


## Cached radial dot so the glints read as light instead of faceted splinters.
static func _soft_dot() -> Texture2D:
	if _dot_texture != null:
		return _dot_texture
	var size := 48
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var centre := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var offset := Vector2(float(x) - centre, float(y) - centre) / centre
			var radial := clampf(1.0 - offset.length(), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, radial * radial * (3.0 - 2.0 * radial)))
	image.generate_mipmaps()
	_dot_texture = ImageTexture.create_from_image(image)
	return _dot_texture
