extends Node3D
## Frame driver and ground ribbon for a lunging charge's wake.
##
## It follows the rig in world space, samples the travelled path every physics
## frame into a short tapered additive ribbon on the ground (the primary read),
## and calls back on a fixed cadence so AbilityFx can add dust, skid smears,
## afterimage wisps and speed streaks. It never touches, damages or reparents the
## rig, and it frees itself shortly after the charge ends.

const RIBBON_WINDOW := 0.35
const RIBBON_MAX := 48
const RIBBON_WIDTH := 0.16
const RIBBON_HALO := 0.55
const RIBBON_TINT := Color(1.0, 0.88, 0.62)
const LIFT := 0.04

const DUST_STEP := 0.04
const SKID_STEP := 0.08
const WISP_STEP := 0.06
const EMIT_UNTIL := 0.06
const TAIL := 0.35

var _rig
var _beat: Callable
var _remaining := 0.0
var _stopped := 0.0
var _clock := 0.0
var _dust := 0.0
var _skid := 0.0
var _wisp := 0.0
var _index := 0
var _last := Vector3.ZERO
var _points := PackedVector3Array()
var _stamps := PackedFloat32Array()
var _mesh := ImmediateMesh.new()
var _view: MeshInstance3D


func _ready() -> void:
	_build_view()


## Called by AbilityFx straight after the node is parented.
func start(rig, seconds: float, beat: Callable) -> void:
	_rig = rig
	_beat = beat
	_remaining = clampf(seconds, 0.05, 1.5)
	_build_view()
	if is_instance_valid(rig) and rig is Node3D:
		var at: Vector3 = rig.global_position
		global_position = at
		_last = at
		_points.append(Vector3(at.x, at.y + LIFT, at.z))
		_stamps.append(0.0)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _remaining > 0.0:
		_remaining -= delta
		if not is_instance_valid(_rig) or not (_rig is Node3D):
			# The body left mid-charge: stop emitting and let everything fade.
			_remaining = 0.0
		else:
			_track()
			if _remaining > EMIT_UNTIL:
				_emit(delta)
	_prune()
	_rebuild()
	if _remaining <= 0.0:
		_stopped += delta
		if _stopped > RIBBON_WINDOW + 0.05:
			queue_free()


## Samples the travelled path into the ribbon.
func _track() -> void:
	var at: Vector3 = _rig.global_position
	global_position = at
	if _points.size() > 0:
		var flat := Vector2(at.x - _last.x, at.z - _last.z)
		if flat.length() < 0.03:
			return
	_last = at
	_points.append(Vector3(at.x, at.y + LIFT, at.z))
	_stamps.append(_clock)
	while _points.size() > RIBBON_MAX:
		_points.remove_at(0)
		_stamps.remove_at(0)


func _emit(delta: float) -> void:
	var at: Vector3 = _rig.global_position + Vector3.UP * LIFT
	var forward: Vector3 = -_rig.global_basis.z
	if _points.size() > 1:
		var step := _points[_points.size() - 1] - _points[_points.size() - 2]
		step.y = 0.0
		if step.length_squared() > 0.0001:
			forward = step.normalized()
	_dust -= delta
	_skid -= delta
	_wisp -= delta
	if _dust <= 0.0:
		_dust += DUST_STEP
		_index += 1
		_beat.call(0, at, forward, _index)
	if _skid <= 0.0:
		_skid += SKID_STEP
		_index += 1
		_beat.call(2, at, forward, _index)
	if _wisp <= 0.0:
		_wisp += WISP_STEP
		_index += 1
		_beat.call(1, at, forward, _index)


func _prune() -> void:
	var cut := 0
	while cut < _stamps.size() and _clock - _stamps[cut] > RIBBON_WINDOW:
		cut += 1
	if cut > 0:
		_points = _points.slice(cut)
		_stamps = _stamps.slice(cut)


func _fade(index: int) -> float:
	return clampf(1.0 - (_clock - _stamps[index]) / RIBBON_WINDOW, 0.0, 1.0)


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var count := _points.size()
	if count < 2:
		return
	_surface(count, RIBBON_WIDTH, 0.60, 1.1)
	_surface(count, RIBBON_HALO, 0.14, 1.6)


## One ribbon sheet along the sampled path, `width` metres across the travel.
func _surface(count: int, width: float, peak: float, power: float) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in count - 1:
		var a := _points[index]
		var b := _points[index + 1]
		var span := b - a
		span.y = 0.0
		if span.length_squared() < 0.000001:
			continue
		span = span.normalized()
		var perp := Vector3(-span.z, 0.0, span.x)
		var fade_a := _fade(index)
		var fade_b := _fade(index + 1)
		var half_a := width * 0.5 * (0.30 + 0.70 * fade_a)
		var half_b := width * 0.5 * (0.30 + 0.70 * fade_b)
		var color_a := Color(RIBBON_TINT.r, RIBBON_TINT.g, RIBBON_TINT.b,
			peak * pow(fade_a, power))
		var color_b := Color(RIBBON_TINT.r, RIBBON_TINT.g, RIBBON_TINT.b,
			peak * pow(fade_b, power))
		var a0 := a - perp * half_a
		var a1 := a + perp * half_a
		var b0 := b - perp * half_b
		var b1 := b + perp * half_b
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(a0)
		_mesh.surface_add_vertex(a1)
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(b0)
		_mesh.surface_add_vertex(b1)
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(a1)
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(b1)
		_mesh.surface_add_vertex(b0)
	_mesh.surface_end()


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
