extends Node3D
## A banded wooden delve chest. Opening it is pure presentation: the lid swings
## up, a gold burst fires from the mouth and a light flash fades out. No items,
## no PlayerState writes.

signal opened

const Geo = preload("res://scripts/geo.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")

const LID_OPEN_ANGLE := -1.9
const LID_OPEN_TIME := 0.45
const FLASH_ENERGY := 4.5
const FLASH_TIME := 0.55

var is_open: bool = false
var depth: int = 0

var _lid: Node3D
var _burst: CPUParticles3D
var _flash: OmniLight3D
var _rune_light: OmniLight3D
var _rune_material: StandardMaterial3D
var _wood: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _iron: StandardMaterial3D
var _black: StandardMaterial3D


func _ready() -> void:
	_wood = TextureLibrary.building_material("wood", Color("806243"))
	_wood_dark = TextureLibrary.building_material("wood", Color("4d3a28"))
	_iron = Geo.material(Color("2b3036"), 0.72, 0.38)
	_black = Geo.material(Color("07090b"), 0.0, 0.9)
	_build_body()
	_build_lid()
	_build_hardware()
	_build_rune()
	_build_loot_burst()
	_build_flash()


## Cache which depth spawned this chest (presentation only).
func set_depth(value: int) -> void:
	depth = value


func is_opened() -> bool:
	return is_open


func open(instant: bool = false) -> void:
	if is_open:
		return
	is_open = true

	if _lid != null:
		if instant or not is_inside_tree():
			_lid.rotation.x = LID_OPEN_ANGLE
		else:
			var lid_tween := create_tween()
			lid_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			lid_tween.tween_property(_lid, "rotation:x", LID_OPEN_ANGLE, LID_OPEN_TIME)

	if _burst != null:
		_burst.restart()
		_burst.emitting = true

	if _flash != null:
		_flash.light_energy = FLASH_ENERGY
		if instant or not is_inside_tree():
			_flash.light_energy = 0.0
		else:
			var flash_tween := create_tween()
			flash_tween.tween_property(_flash, "light_energy", 0.0, FLASH_TIME)

	if _rune_material != null:
		_rune_material.emission_energy_multiplier = 0.35
	if _rune_light != null:
		_rune_light.light_energy = 0.0

	opened.emit()


func _build_body() -> void:
	var body := StaticBody3D.new()
	body.name = "ChestBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(1.38, 0.98, 0.94)
	var collider := CollisionShape3D.new()
	collider.name = "ChestCollision"
	collider.shape = shape
	collider.position = Vector3(0, 0.49, 0)
	body.add_child(collider)

	Geo.box(self, Vector3(1.3, 0.72, 0.86), Vector3(0, 0.36, 0), _wood)
	Geo.box(self, Vector3(1.22, 0.1, 0.78), Vector3(0, 0.71, 0), _wood_dark)
	Geo.box(self, Vector3(1.34, 0.1, 0.9), Vector3(0, 0.76, 0), _wood_dark)
	for side in [-1.0, 1.0]:
		Geo.box(self, Vector3(0.16, 0.12, 0.16), Vector3(side * 0.5, 0.06, 0.3), _iron)
		Geo.box(self, Vector3(0.16, 0.12, 0.16), Vector3(side * 0.5, 0.06, -0.3), _iron)
	# Iron bands wrap the base.
	for x in [-0.44, 0.0, 0.44]:
		Geo.box(self, Vector3(0.09, 0.74, 0.92), Vector3(x, 0.36, 0), _iron)
		Geo.box(self, Vector3(0.12, 0.06, 0.12), Vector3(x, 0.36, 0.46), _iron)


func _build_lid() -> void:
	_lid = Node3D.new()
	_lid.name = "LidPivot"
	_lid.position = Vector3(0, 0.72, -0.43)
	add_child(_lid)

	Geo.box(_lid, Vector3(1.34, 0.24, 0.9), Vector3(0, 0.1, 0.45), _wood)
	Geo.box(_lid, Vector3(1.26, 0.09, 0.82), Vector3(0, 0.23, 0.45), _wood_dark)
	for x in [-0.44, 0.0, 0.44]:
		Geo.box(_lid, Vector3(0.09, 0.27, 0.94), Vector3(x, 0.1, 0.45), _iron)
	# Hinge barrels at the back edge.
	for side in [-1.0, 1.0]:
		var hinge := Geo.cylinder(_lid, 0.07, 0.07, 0.3, Vector3(side * 0.46, 0.0, 0.0), _iron, 10)
		hinge.rotation.z = PI * 0.5


func _build_hardware() -> void:
	# Lock plate and keyhole on the front face (+Z).
	Geo.box(self, Vector3(0.26, 0.3, 0.1), Vector3(0, 0.6, 0.44), _iron)
	Geo.box(self, Vector3(0.3, 0.06, 0.12), Vector3(0, 0.78, 0.44), _iron)
	Geo.box(self, Vector3(0.05, 0.11, 0.03), Vector3(0, 0.6, 0.5), _black)
	Geo.box(self, Vector3(0.09, 0.09, 0.03), Vector3(0, 0.55, 0.5), _black)


func _build_rune() -> void:
	_rune_material = StandardMaterial3D.new()
	_rune_material.albedo_color = Color("0e1417")
	_rune_material.emission_enabled = true
	_rune_material.emission = Color("79e3d3")
	_rune_material.emission_energy_multiplier = 1.2
	_rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rune_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	Geo.box(self, Vector3(0.52, 0.22, 0.035), Vector3(0, 0.28, 0.445), _rune_material)
	Geo.box(self, Vector3(0.06, 0.34, 0.03), Vector3(0.17, 0.3, 0.45), _rune_material)
	Geo.box(self, Vector3(0.06, 0.34, 0.03), Vector3(-0.17, 0.3, 0.45), _rune_material)
	Geo.box(self, Vector3(0.24, 0.05, 0.03), Vector3(0, 0.42, 0.45), _rune_material)

	_rune_light = OmniLight3D.new()
	_rune_light.name = "RuneLight"
	_rune_light.position = Vector3(0, 0.42, 0.62)
	_rune_light.light_color = Color("79e3d3")
	_rune_light.light_energy = 0.45
	_rune_light.omni_range = 2.2
	_rune_light.shadow_enabled = false
	add_child(_rune_light)


func _build_loot_burst() -> void:
	_burst = CPUParticles3D.new()
	_burst.name = "LootBurst"
	_burst.position = Vector3(0, 0.82, 0.12)
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 56
	_burst.lifetime = 1.15
	_burst.explosiveness = 1.0
	_burst.direction = Vector3(0, 1, 0.15)
	_burst.spread = 52.0
	_burst.gravity = Vector3(0, -5.4, 0)
	_burst.initial_velocity_min = 2.4
	_burst.initial_velocity_max = 5.6
	_burst.scale_amount_min = 0.05
	_burst.scale_amount_max = 0.14
	_burst.local_coords = false
	_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_burst.emission_sphere_radius = 0.26

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.68, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.99, 0.9, 1.0),
		Color(1.0, 0.86, 0.42, 1.0),
		Color(1.0, 0.68, 0.18, 0.8),
		Color(1.0, 0.55, 0.12, 0.0),
	])
	_burst.color_ramp = gradient

	var spark := SphereMesh.new()
	spark.radius = 0.055
	spark.height = 0.11
	spark.radial_segments = 6
	spark.rings = 3
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_color = Color.WHITE
	spark_material.vertex_color_use_as_albedo = true
	spark_material.emission_enabled = true
	spark_material.emission = Color("ffd68a")
	spark_material.emission_energy_multiplier = 2.2
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.disable_receive_shadows = true
	spark.material = spark_material
	_burst.mesh = spark
	add_child(_burst)


func _build_flash() -> void:
	_flash = OmniLight3D.new()
	_flash.name = "Flash"
	_flash.position = Vector3(0, 1.02, 0.18)
	_flash.light_color = Color("ffd693")
	_flash.light_energy = 0.0
	_flash.omni_range = 4.6
	_flash.omni_attenuation = 1.2
	_flash.shadow_enabled = false
	add_child(_flash)
