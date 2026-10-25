extends Node3D
## The delve sigil: a five-point star plus an inner and an outer ring drawn as
## thin additive ribbons on the floor, and the demonic ritual layer that plays
## over it - rising embers, a central column of light, five point-orbs that light
## one after another, a slowly spinning outer ring and a pulsing light.
##
## Nothing here runs per frame: the ribbons pulse on the shader's TIME, the ring
## spins and the light breathes on looping tweens, and the embers are a
## CPUParticles3D stream.

const SIGIL_SHADER: Shader = preload("res://scripts/world/shaders/delve_pentagram.gdshader")
const COLUMN_SHADER: Shader = preload("res://scripts/world/shaders/delve_beacon.gdshader")

const STAR_POINTS := 5
const STAR_LINE_RATIO := 0.09
const STAR_LINE_MIN := 0.18
const INNER_RING_RATIO := 0.42
const OUTER_RING_RATIO := 1.08
const INNER_RING_WIDTH := 0.052
const OUTER_RING_WIDTH := 0.062
const RING_WIDTH_MIN := 0.12
const RING_SEGMENTS := 64
const FLOOR_LIFT := 0.05
const FADE_TIME := 0.6
const RITUAL_FADE := 0.8
const SPIN_TIME := 12.0
const PULSE_TIME := 1.15
const COLUMN_HEIGHT := 9.0
const COLUMN_RADIUS_RATIO := 0.17
const COLUMN_ENERGY := 1.0
const LIGHT_BASE := 1.15
const LIGHT_RITUAL_BOOST := 1.3
const LIGHT_RANGE_FACTOR := 3.4
const LIGHT_RANGE_MIN := 7.0
const ORB_RADIUS := 0.16
const ORB_LIFT := 0.5
const ORB_STAGGER := 0.16
const ORB_FADE := 0.34
const EMBER_AMOUNT := 72

var _radius: float = 5.0
var _accent: Color = Color("ff8f3a")
var _floor_y: float = 0.0
var _built: bool = false
var _active: bool = false
var _intensity: float = 0.0
var _ritual: bool = false
var _progress: float = 0.0
var _energy: float = 0.0
var _ritual_energy: float = 0.0
var _column_energy_value: float = 0.0

var _sigil: MeshInstance3D
var _outer_ring: MeshInstance3D
var _column: MeshInstance3D
var _embers: CPUParticles3D
var _light: OmniLight3D
var _orbs: Array[MeshInstance3D] = []
var _orb_materials: Array[StandardMaterial3D] = []
var _orb_lit: Array[bool] = []
var _orb_tweens: Array[Tween] = []
var _sigil_material: ShaderMaterial
var _column_material: ShaderMaterial
var _state_tween: Tween
var _column_tween: Tween
var _spin_tween: Tween
var _pulse_tween: Tween
var _light_tween: Tween


func _ready() -> void:
	if not _built:
		_build()
	_apply_geometry()
	_set_energy(0.0)
	_sigil.visible = _active
	_outer_ring.visible = _active
	_apply_ritual(true)
	if _active:
		_apply_state()


## Extent of the figure in metres, the colour it burns and the world height of
## the floor slab it lies on. Safe to call before the node enters the tree.
func configure(radius: float, accent: Color, floor_y: float) -> void:
	_radius = maxf(radius, 1.0)
	_accent = accent
	_floor_y = floor_y
	if _built:
		_apply_geometry()


## Fade the sigil in and scale how hot it burns. Zero intensity hides it.
func set_state(active: bool, intensity: float = 0.0) -> void:
	var next := clampf(intensity, 0.0, 1.5)
	var changed := active != _active or not is_equal_approx(next, _intensity)
	_active = active
	_intensity = next
	if not _built or not changed:
		return
	_apply_state()


## Toggle the demonic layer. `progress` runs 0..1 and lights the five point-orbs
## in order, so the summoning visibly gathers as the ritual advances.
func set_ritual(active: bool, progress: float = 0.0) -> void:
	var next := clampf(progress, 0.0, 1.0) if active else 0.0
	var changed := active != _ritual
	_ritual = active
	_progress = next
	if not _built:
		return
	if changed:
		_apply_ritual(false)
	else:
		_update_orbs(false)


func is_active() -> bool:
	return _active


func intensity() -> float:
	return _intensity


func _build() -> void:
	_built = true

	_sigil_material = ShaderMaterial.new()
	_sigil_material.shader = SIGIL_SHADER

	_sigil = MeshInstance3D.new()
	_sigil.name = "Sigil"
	_sigil.material_override = _sigil_material
	_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sigil.visible = false
	add_child(_sigil)

	_outer_ring = MeshInstance3D.new()
	_outer_ring.name = "OuterRing"
	_outer_ring.material_override = _sigil_material
	_outer_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outer_ring.visible = false
	add_child(_outer_ring)

	_column_material = ShaderMaterial.new()
	_column_material.shader = COLUMN_SHADER
	_column_material.set_shader_parameter("shape", 0.0)
	_column_material.set_shader_parameter("agitation", 1.0)
	_column_material.set_shader_parameter("energy", 0.0)
	_column = MeshInstance3D.new()
	_column.name = "RitualColumn"
	_column.material_override = _column_material
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = false
	add_child(_column)

	_build_embers()

	for index in STAR_POINTS:
		var orb := MeshInstance3D.new()
		orb.name = "Orb%d" % index
		var sphere := SphereMesh.new()
		sphere.radius = ORB_RADIUS
		sphere.height = ORB_RADIUS * 2.0
		sphere.radial_segments = 10
		sphere.rings = 5
		orb.mesh = sphere
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.visible = false
		var orb_material := StandardMaterial3D.new()
		orb_material.albedo_color = Color(_accent.r, _accent.g, _accent.b, 0.0)
		orb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		orb_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		orb_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		orb_material.disable_receive_shadows = true
		orb.material_override = orb_material
		add_child(orb)
		_orbs.append(orb)
		_orb_materials.append(orb_material)
		_orb_lit.append(false)
		_orb_tweens.append(null)

	_light = OmniLight3D.new()
	_light.name = "RitualLight"
	_light.light_color = _accent
	_light.light_energy = 0.0
	_light.omni_attenuation = 1.1
	_light.shadow_enabled = false
	add_child(_light)


func _build_embers() -> void:
	_embers = CPUParticles3D.new()
	_embers.name = "Embers"
	_embers.emitting = false
	_embers.amount = EMBER_AMOUNT
	_embers.lifetime = 3.2
	_embers.preprocess = 1.4
	_embers.randomness = 0.5
	_embers.local_coords = false
	_embers.direction = Vector3(0.0, 1.0, 0.0)
	_embers.spread = 16.0
	_embers.gravity = Vector3(0.0, 0.45, 0.0)
	_embers.initial_velocity_min = 0.5
	_embers.initial_velocity_max = 1.5
	_embers.damping_min = 0.05
	_embers.damping_max = 0.3
	_embers.scale_amount_min = 0.6
	_embers.scale_amount_max = 1.4
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_embers.emission_ring_axis = Vector3(0.0, 1.0, 0.0)
	_embers.emission_ring_height = 0.12
	_embers.emission_ring_radius = 4.5
	_embers.emission_ring_inner_radius = 1.0

	var ember := SphereMesh.new()
	ember.radius = 0.04
	ember.height = 0.08
	ember.radial_segments = 6
	ember.rings = 3
	var ember_material := StandardMaterial3D.new()
	ember_material.vertex_color_use_as_albedo = true
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_material.disable_receive_shadows = true
	ember.material = ember_material
	_embers.mesh = ember
	add_child(_embers)


func _apply_geometry() -> void:
	if not _built:
		return

	var lift := _floor_lift()
	_sigil.mesh = _sigil_mesh()
	_sigil.position = Vector3(0.0, lift, 0.0)
	_outer_ring.mesh = _outer_ring_mesh()
	_outer_ring.position = Vector3(0.0, lift, 0.0)

	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = _radius * COLUMN_RADIUS_RATIO * 1.12
	column_mesh.bottom_radius = _radius * COLUMN_RADIUS_RATIO
	column_mesh.height = COLUMN_HEIGHT
	column_mesh.radial_segments = 20
	column_mesh.rings = 1
	column_mesh.cap_top = false
	column_mesh.cap_bottom = false
	_column.mesh = column_mesh
	_column.position = Vector3(0.0, lift + COLUMN_HEIGHT * 0.5, 0.0)

	_embers.position = Vector3(0.0, lift + 0.1, 0.0)
	_embers.emission_ring_radius = _radius * 0.92
	_embers.emission_ring_inner_radius = _radius * 0.2
	_embers.color_ramp = _ember_ramp()

	for index in _orbs.size():
		_orbs[index].position = _tip(index, _radius * 0.98) + Vector3(0.0, lift + ORB_LIFT, 0.0)
		_orb_materials[index].albedo_color = Color(_accent.r, _accent.g, _accent.b, _orb_materials[index].albedo_color.a)

	_light.position = Vector3(0.0, lift + 1.1, 0.0)
	_light.omni_range = maxf(_radius * LIGHT_RANGE_FACTOR, LIGHT_RANGE_MIN)
	_light.light_color = _accent

	_sigil_material.set_shader_parameter("sigil_color", _accent)
	_column_material.set_shader_parameter("beam_color", _accent)
	_column_material.set_shader_parameter("beam_height", COLUMN_HEIGHT)


func _apply_state() -> void:
	if not _built:
		return
	var target := _intensity if _active else 0.0
	if target > 0.001:
		_sigil.visible = true
		_outer_ring.visible = true
	if _state_tween != null and _state_tween.is_valid():
		_state_tween.kill()
	_state_tween = null
	if not is_inside_tree() or is_equal_approx(_energy, target):
		_set_energy(target)
		if target <= 0.001:
			_hide_sigil()
		_refresh_light(true)
		return
	_state_tween = create_tween()
	_state_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_state_tween.tween_method(_set_energy, _energy, target, FADE_TIME)
	if target <= 0.001:
		_state_tween.tween_callback(_hide_sigil)
	_refresh_light(false)


func _apply_ritual(instant: bool) -> void:
	if not _built:
		return
	if _column_tween != null and _column_tween.is_valid():
		_column_tween.kill()
	_column_tween = null
	var animate := not instant and is_inside_tree()
	var duration := 0.0 if instant else RITUAL_FADE

	if _ritual:
		_column.visible = true
		_embers.restart()
		_embers.emitting = true
		_start_spin(instant)
		if animate:
			_column_tween = create_tween()
			_column_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_column_tween.tween_method(_set_column_energy, _column_energy(), COLUMN_ENERGY, duration)
			_column_tween.parallel().tween_method(_set_ritual_energy, _ritual_energy, 1.0, duration)
		else:
			_set_column_energy(COLUMN_ENERGY)
			_set_ritual_energy(1.0)
	else:
		_embers.emitting = false
		_stop_spin()
		if animate:
			_column_tween = create_tween()
			_column_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_column_tween.tween_method(_set_column_energy, _column_energy(), 0.0, duration)
			_column_tween.parallel().tween_method(_set_ritual_energy, _ritual_energy, 0.0, duration)
			_column_tween.tween_callback(_hide_column)
		else:
			_set_column_energy(0.0)
			_set_ritual_energy(0.0)
			_hide_column()

	_update_orbs(instant)
	_refresh_light(instant)


func _update_orbs(instant: bool) -> void:
	if not _built:
		return
	var span := 1.0 / float(STAR_POINTS)
	for index in _orbs.size():
		var wanted := _ritual and _progress >= (float(index) + 0.55) * span
		if wanted == _orb_lit[index]:
			continue
		_orb_lit[index] = wanted
		var delay := float(index) * ORB_STAGGER if wanted else 0.0
		_fade_orb(index, wanted, delay, instant)


func _fade_orb(index: int, lit: bool, delay: float, instant: bool) -> void:
	var orb := _orbs[index]
	var orb_material := _orb_materials[index]
	if _orb_tweens[index] != null and _orb_tweens[index].is_valid():
		_orb_tweens[index].kill()
	_orb_tweens[index] = null
	var target := 1.0 if lit else 0.0
	orb.visible = true

	if instant or not is_inside_tree():
		orb_material.albedo_color = Color(_accent.r, _accent.g, _accent.b, target)
		orb.visible = lit
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(orb_material, "albedo_color:a", target, ORB_FADE)
	if not lit:
		tween.tween_callback(_hide_orb.bind(index))
	_orb_tweens[index] = tween


func _refresh_light(instant: bool) -> void:
	if not _built:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()
	_light_tween = null

	var base := _light_base()
	if base <= 0.001:
		if instant or not is_inside_tree():
			_light.light_energy = 0.0
			_light.visible = false
		else:
			_light_tween = create_tween()
			_light_tween.set_trans(Tween.TRANS_SINE)
			_light_tween.tween_property(_light, "light_energy", 0.0, FADE_TIME)
			_light_tween.tween_callback(_hide_light)
		return

	_light.visible = true
	if instant or not is_inside_tree():
		_light.light_energy = base
		if _ritual and is_inside_tree():
			_start_pulse()
		return

	_light_tween = create_tween()
	_light_tween.set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(_light, "light_energy", base, RITUAL_FADE * 0.6 if _ritual else FADE_TIME)
	if _ritual:
		_light_tween.tween_callback(_start_pulse)


func _start_pulse() -> void:
	if not _built or not _ritual or not is_inside_tree():
		return
	var base := _light_base()
	if base <= 0.001:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_light, "light_energy", base * 1.5, PULSE_TIME)
	_pulse_tween.tween_property(_light, "light_energy", base * 0.62, PULSE_TIME)


func _start_spin(instant: bool) -> void:
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = null
	_outer_ring.rotation.y = 0.0
	if instant or not is_inside_tree():
		return
	_spin_tween = create_tween().set_loops()
	_spin_tween.set_trans(Tween.TRANS_LINEAR)
	_spin_tween.tween_property(_outer_ring, "rotation:y", TAU, SPIN_TIME)


func _stop_spin() -> void:
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = null


func _light_base() -> float:
	if not _active:
		return 0.0
	return _intensity * (LIGHT_BASE + LIGHT_RITUAL_BOOST * (1.0 if _ritual else 0.0))


func _set_energy(value: float) -> void:
	_energy = clampf(value, 0.0, 1.5)
	if _sigil_material != null:
		_sigil_material.set_shader_parameter("energy", _energy)


func _set_ritual_energy(value: float) -> void:
	_ritual_energy = clampf(value, 0.0, 1.0)
	if _sigil_material != null:
		_sigil_material.set_shader_parameter("ritual", _ritual_energy)


func _set_column_energy(value: float) -> void:
	_column_energy_value = value
	if _column_material != null:
		_column_material.set_shader_parameter("energy", value)


func _column_energy() -> float:
	return _column_energy_value


func _hide_sigil() -> void:
	if _energy > 0.001:
		return
	_sigil.visible = false
	_outer_ring.visible = false


func _hide_column() -> void:
	if _column_energy() > 0.001:
		return
	_column.visible = false


func _hide_light() -> void:
	if _light_base() > 0.001:
		return
	_light.light_energy = 0.0
	_light.visible = false


func _hide_orb(index: int) -> void:
	if _orb_lit[index]:
		return
	_orbs[index].visible = false


func _floor_lift() -> float:
	var lift := _floor_y
	if is_inside_tree():
		lift -= global_position.y
	return lift + FLOOR_LIFT


func _tip(index: int, reach: float) -> Vector3:
	var angle := -PI * 0.5 + TAU * float(index % STAR_POINTS) / float(STAR_POINTS)
	return Vector3(cos(angle), 0.0, sin(angle)) * reach


func _sigil_mesh() -> ArrayMesh:
	# Stepping two points at a time on the pentagon traces the five-point star.
	var star := PackedVector3Array()
	for step in STAR_POINTS:
		star.append(_tip((step * 2) % STAR_POINTS, _radius))
	var surfaces: Array[Dictionary] = [
		{"points": star, "width": maxf(_radius * STAR_LINE_RATIO, STAR_LINE_MIN)},
		{
			"points": _circle(_radius * INNER_RING_RATIO, RING_SEGMENTS),
			"width": maxf(_radius * INNER_RING_WIDTH, RING_WIDTH_MIN),
		},
	]
	return _ribbon_mesh(surfaces)


## The outer ring carries five radial ticks at the star angles, so the tween that
## spins it during the ritual is unmistakable on screen.
func _outer_ring_mesh() -> ArrayMesh:
	var radius := _radius * OUTER_RING_RATIO
	var width := maxf(_radius * OUTER_RING_WIDTH, RING_WIDTH_MIN)
	var tick_width := maxf(width * 0.55, 0.1)
	var surfaces: Array[Dictionary] = [{"points": _circle(radius, RING_SEGMENTS * 2), "width": width}]
	for index in STAR_POINTS:
		var tick := PackedVector3Array([_tip(index, radius * 0.92), _tip(index, radius * 1.2)])
		surfaces.append({"points": tick, "width": tick_width, "closed": false})
	return _ribbon_mesh(surfaces)


func _circle(radius: float, segments: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in segments:
		var angle := TAU * float(index) / float(segments)
		points.append(Vector3(cos(angle), 0.0, sin(angle)) * radius)
	return points


## Lays flat quads along polyline loops. UV.x carries the distance walked
## along the ribbon in metres so the shader's pulse keeps an even wavelength, and
## UV.y runs across the stroke for the soft edge. Straight runs (the outer ring's
## ticks) pass `"closed": false`.
func _ribbon_mesh(surfaces: Array[Dictionary]) -> ArrayMesh:
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walked := 0.0
	for surface in surfaces:
		var points: PackedVector3Array = surface["points"]
		if points.size() < 2:
			continue
		var width: float = maxf(float(surface["width"]), 0.02)
		var closed := bool(surface.get("closed", true))
		var segments := points.size() if closed else points.size() - 1
		for index in segments:
			walked = _add_ribbon_quad(ribbon, points[index], points[(index + 1) % points.size()], width, walked)
	return ribbon.commit()


func _add_ribbon_quad(ribbon: SurfaceTool, a: Vector3, b: Vector3, width: float, walked: float) -> float:
	var span := b - a
	var length := span.length()
	if length < 0.0001:
		return walked
	var side := Vector3.UP.cross(span).normalized() * (width * 0.5)
	var start := walked
	var end := walked + length

	ribbon.set_normal(Vector3.UP)
	ribbon.set_uv(Vector2(start, 0.0))
	ribbon.add_vertex(a - side)
	ribbon.set_uv(Vector2(end, 0.0))
	ribbon.add_vertex(b - side)
	ribbon.set_uv(Vector2(end, 1.0))
	ribbon.add_vertex(b + side)

	ribbon.set_uv(Vector2(start, 0.0))
	ribbon.add_vertex(a - side)
	ribbon.set_uv(Vector2(end, 1.0))
	ribbon.add_vertex(b + side)
	ribbon.set_uv(Vector2(start, 1.0))
	ribbon.add_vertex(a + side)
	return end


func _ember_ramp() -> Gradient:
	var hot := _accent.lerp(Color.WHITE, 0.55)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.62, 1.0])
	ramp.colors = PackedColorArray([
		Color(hot.r, hot.g, hot.b, 0.0),
		Color(hot.r, hot.g, hot.b, 1.0),
		Color(_accent.r, _accent.g, _accent.b, 0.8),
		Color(_accent.r, _accent.g, _accent.b, 0.0),
	])
	return ramp
