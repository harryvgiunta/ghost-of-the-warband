extends Node3D
## A shimmering decision beacon: an additive column of light with a soft pool on
## the floor, an OmniLight3D and a billboard title. The world places one over
## every choice the party has - altar, rope, floor hatch - so each option reads
## instantly from across the chamber.
##
## Every bit of motion lives in the shader (delve_beacon.gdshader drives the
## climbing bands with TIME) or in a tween, so this node never runs _process.

const BEACON_SHADER: Shader = preload("res://scripts/world/shaders/delve_beacon.gdshader")

const DEFAULT_RADIUS := 0.95
const DEFAULT_HEIGHT := 7.0
const FADE_TIME := 0.4
const LIGHT_ENERGY := 0.55
const LIGHT_RANGE_FACTOR := 3.2
const LIGHT_RANGE_MIN := 3.0
const RING_SPAN := 5.2
const RING_INNER_RATIO := 0.55
const RING_OUTER_RATIO := 1.5
const RING_LIFT := 0.04
const LABEL_HEIGHT_RATIO := 0.72
const LABEL_PIXEL := 0.012

var _beam_color: Color = Color("ffce74")
var _radius: float = DEFAULT_RADIUS
var _height: float = DEFAULT_HEIGHT
var _title: String = ""
var _active: bool = false
var _built: bool = false
var _glow: float = 0.0

var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _label: Label3D
var _beam_material: ShaderMaterial
var _ring_material: ShaderMaterial
var _fx_materials: Array[ShaderMaterial] = []
var _label_tint: Color = Color.WHITE
var _fade_tween: Tween


func _ready() -> void:
	if not _built:
		_build()
	_apply_look()
	_set_glow(0.0)
	if _active:
		_set_shown(true)
		_fade(1.0, false, FADE_TIME)
	else:
		_set_shown(false)


## Colour, thickness, height and the title that floats over the column. Safe to
## call before the node enters the tree or again to repaint an existing beacon.
func configure(beam_color: Color, radius: float, height: float, title: String) -> void:
	_beam_color = beam_color
	_radius = maxf(radius, 0.2)
	_height = maxf(height, 1.0)
	_title = title
	if _built:
		_apply_look()


func set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	if not _built:
		return
	if value:
		_set_shown(true)
		_fade(1.0, false, FADE_TIME)
	else:
		_fade(0.0, true, FADE_TIME)


func is_active() -> bool:
	return _active


func _build() -> void:
	_built = true

	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEACON_SHADER
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)

	_ring_material = ShaderMaterial.new()
	_ring_material.shader = BEACON_SHADER
	_ring_material.set_shader_parameter("shape", 1.0)
	_ring = MeshInstance3D.new()
	_ring.name = "GroundRing"
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	_fx_materials.append(_beam_material)
	_fx_materials.append(_ring_material)

	_light = OmniLight3D.new()
	_light.name = "BeaconLight"
	_light.light_energy = 0.0
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	add_child(_light)

	_label = Label3D.new()
	_label.name = "Title"
	_label.font_size = 44
	_label.pixel_size = LABEL_PIXEL
	_label.outline_size = 12
	_label.outline_modulate = Color(0.04, 0.025, 0.012, 0.9)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visible = false
	add_child(_label)


func _apply_look() -> void:
	if not _built:
		return

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = _radius * 1.06
	beam_mesh.bottom_radius = _radius
	beam_mesh.height = _height
	beam_mesh.radial_segments = 24
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_beam.mesh = beam_mesh
	_beam.position = Vector3(0.0, _height * 0.5, 0.0)

	var half_span := _radius * RING_SPAN * 0.5
	var ground := PlaneMesh.new()
	ground.size = Vector2(half_span * 2.0, half_span * 2.0)
	_ring.mesh = ground
	_ring.position = Vector3(0.0, RING_LIFT, 0.0)
	_ring_material.set_shader_parameter("ring_inner", _radius * RING_INNER_RATIO / half_span)
	_ring_material.set_shader_parameter("ring_outer", _radius * RING_OUTER_RATIO / half_span)

	for fx_material in _fx_materials:
		fx_material.set_shader_parameter("beam_color", _beam_color)
		fx_material.set_shader_parameter("beam_height", _height)

	_light.light_color = _beam_color
	_light.position = Vector3(0.0, clampf(_height * 0.3, 1.4, 2.6), 0.0)
	_light.omni_range = maxf(_radius * LIGHT_RANGE_FACTOR, LIGHT_RANGE_MIN)

	_label_tint = _beam_color.lerp(Color.WHITE, 0.5)
	_label.text = _title
	_label.position = Vector3(0.0, _height * LABEL_HEIGHT_RATIO, 0.0)

	_set_glow(_glow)


func _fade(target: float, hide: bool, duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if not is_inside_tree() or duration <= 0.0:
		_set_glow(target)
		if hide:
			_set_shown(false)
		return
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_method(_set_glow, _glow, target, duration)
	if hide:
		_fade_tween.tween_callback(_set_shown.bind(false))


func _set_glow(value: float) -> void:
	_glow = clampf(value, 0.0, 1.0)
	if not _built:
		return
	for fx_material in _fx_materials:
		fx_material.set_shader_parameter("energy", _glow)
	_light.light_energy = LIGHT_ENERGY * _glow
	_label.modulate = Color(_label_tint.r, _label_tint.g, _label_tint.b, _glow)


func _set_shown(shown: bool) -> void:
	if not _built:
		return
	_beam.visible = shown
	_ring.visible = shown
	_label.visible = shown
	# A dark light still occupies a light slot in the compatibility renderer.
	_light.visible = shown
