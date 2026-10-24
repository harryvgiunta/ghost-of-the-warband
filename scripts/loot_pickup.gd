extends Node3D
## Presentation-only world drop. main.gd grants the item to PlayerState when the
## ranger walks close; this node owns the category-shaped mesh and the name plate.

const PIVOT_HEIGHT := 0.36
const BOB_HEIGHT := 0.055
const BOB_SPEED := 2.1
const SPIN_SPEED := 0.85

var item_id := ""
var display_name := ""
# A world drop the player just threw down stays inert until they step away, so
# the person who dropped it cannot scoop it straight back up.
var armed := true
var _pivot: Node3D
var _label: Label3D
var _time := 0.0
var _built := false

func setup(id: String, name: String) -> void:
	item_id = id
	display_name = name if not name.is_empty() else id
	if is_inside_tree():
		_ensure_built()

func set_armed(value: bool) -> void:
	armed = value

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build()

func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Drop"
	_pivot.position.y = PIVOT_HEIGHT
	add_child(_pivot)
	_build_shape(_category())
	_label = Label3D.new()
	_label.text = display_name
	_label.position = Vector3(0, PIVOT_HEIGHT + 0.82, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.0038
	_label.outline_size = 9
	_label.modulate = Color("f3ecd8")
	_label.outline_modulate = Color(0.02, 0.05, 0.06, 0.92)
	add_child(_label)

func _process(delta: float) -> void:
	_time += delta
	if _pivot != null:
		_pivot.position.y = PIVOT_HEIGHT + sin(_time * BOB_SPEED) * BOB_HEIGHT
		_pivot.rotation.y = wrapf(_pivot.rotation.y + delta * SPIN_SPEED, 0.0, TAU)
	if _label != null:
		_label.position.y = PIVOT_HEIGHT + 0.82 + sin(_time * BOB_SPEED) * BOB_HEIGHT * 0.5

func _category() -> String:
	var state := get_node_or_null("/root/PlayerState")
	if state != null and state.has_method("item_category"):
		var reported := str(state.item_category(item_id))
		if not reported.is_empty():
			return reported
	if item_id.begins_with("shield_"):
		return "shield"
	if item_id.begins_with("staff_"):
		return "staff"
	if item_id.begins_with("focus_"):
		return "focus"
	if item_id.begins_with("ring_") or item_id.begins_with("neck_"):
		return "jewelry"
	if item_id.begins_with("armor_"):
		return "armor"
	if item_id.begins_with("bow_"):
		return "bow"
	if item_id.begins_with("sword_") or item_id.begins_with("dagger_") or item_id.begins_with("axe_") or item_id.begins_with("mace_"):
		return "weapon"
	return "misc"

func _build_shape(category: String) -> void:
	match category:
		"shield":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.34
			disc.bottom_radius = 0.34
			disc.height = 0.055
			disc.radial_segments = 28
			disc.rings = 1
			var face := _part(disc, _material(Color("71888f"), 0.65), Vector3.ZERO)
			face.rotation_degrees = Vector3(75, 0, 0)
			var boss := SphereMesh.new()
			boss.radius = 0.075
			boss.height = 0.14
			boss.radial_segments = 12
			boss.rings = 6
			_part(boss, _material(Color("c9a55c"), 0.85), Vector3(0, 0.09, 0))
		"staff":
			var shaft := CylinderMesh.new()
			shaft.top_radius = 0.028
			shaft.bottom_radius = 0.032
			shaft.height = 1.0
			shaft.radial_segments = 8
			var pole := _part(shaft, _material(Color("7c5a35"), 0.05), Vector3(0, 0.12, 0))
			pole.rotation_degrees = Vector3(0, 0, 16)
			var orb := SphereMesh.new()
			orb.radius = 0.085
			orb.height = 0.17
			orb.radial_segments = 14
			orb.rings = 8
			_part(orb, _material(Color("e08a3c"), 0.2), Vector3(-0.15, 0.64, 0))
		"focus":
			var block := BoxMesh.new()
			block.size = Vector3(0.20, 0.055, 0.28)
			var book := _part(block, _material(Color("7c4130"), 0.05), Vector3(0, -0.30, 0))
			book.rotation_degrees = Vector3(0, 18, 10)
			var clasp := BoxMesh.new()
			clasp.size = Vector3(0.035, 0.075, 0.10)
			_part(clasp, _material(Color("c9a55c"), 0.8), Vector3(0.10, -0.29, 0))
		"jewelry":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.055
			ring.outer_radius = 0.095
			ring.rings = 22
			ring.ring_segments = 10
			var band := _part(ring, _material(Color("d9b664"), 0.9), Vector3(0, -0.26, 0))
			band.rotation_degrees = Vector3(90, 0, 0)
		"armor", "armor_bundle":
			var shell := BoxMesh.new()
			shell.size = Vector3(0.32, 0.26, 0.24)
			var piece := _part(shell, _material(Color("8d6c48"), 0.15), Vector3(0, -0.20, 0))
			piece.rotation_degrees = Vector3(0, 24, 0)
		"bow", "weapon", "1h", "2h":
			var blade := BoxMesh.new()
			blade.size = Vector3(0.045, 0.78, 0.012)
			var beam := _part(blade, _material(Color("b8c3c4"), 0.8), Vector3(0, 0.15, 0))
			beam.rotation_degrees = Vector3(0, 0, 22)
			var guard := BoxMesh.new()
			guard.size = Vector3(0.24, 0.035, 0.045)
			_part(guard, _material(Color("c9a55c"), 0.75), Vector3(-0.14, -0.12, 0))
			var grip := CylinderMesh.new()
			grip.top_radius = 0.022
			grip.bottom_radius = 0.022
			grip.height = 0.16
			var hilt := _part(grip, _material(Color("5b3b26"), 0.05), Vector3(-0.14, -0.23, 0))
			hilt.rotation_degrees = Vector3(0, 0, 22)
		_:
			var cube := BoxMesh.new()
			cube.size = Vector3(0.22, 0.22, 0.22)
			var lump := _part(cube, _material(Color("a8a08c"), 0.2), Vector3(0, -0.25, 0))
			lump.rotation_degrees = Vector3(0, 35, 12)

func _part(mesh: Mesh, material: Material, offset: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(instance)
	return instance

func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.42
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	return material
