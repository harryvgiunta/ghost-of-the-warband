extends Node3D

const Geo = preload("res://scripts/geo.gd")
# Human-scale draw shared by all bow shapes; equipment never rescales the rig.
const BRACE_DISTANCE: float = 0.18
const DRAW_DISTANCE: float = 0.825
const ARROW_SHAFT: float = 0.91
const ARROW_LENGTH: float = 0.98

var bow_kind: int = 1
var bow_length: float = 1.4
var normalized_draw: float = 0.0
var grip: Node3D
var nock: Node3D
var arrow_tip: Node3D
var nocked_arrow: Node3D
var _limbs: Array[MeshInstance3D] = []
var _strings: Array[MeshInstance3D] = []
var _tip_caps: Array[MeshInstance3D] = []
var _points: PackedVector3Array = PackedVector3Array()
var _ready_built: bool = false
var _has_pose := false
var _rest_lengths := PackedFloat32Array()
var _rest_angles := PackedFloat32Array()
var _string_half_length := 0.0
const SEGMENTS: int = 9

func _ready() -> void:
	_build()
	set_draw(normalized_draw)

func _build() -> void:
	var wood: StandardMaterial3D
	if bow_kind == 0:
		wood = Geo.material(Color("b98449"))
	elif bow_kind == 1:
		wood = Geo.material(Color("315e64"), 0.12)
	else:
		wood = Geo.material(Color("553528"))
	var edge := Geo.material(Color("d3aa63"), 0.48, 0.38)
	var leather := Geo.material(Color("30251e"))
	var cord := Geo.material(Color("e9dfbd"), 0.0, 0.95)
	grip = Node3D.new()
	grip.name = "Grip"
	add_child(grip)
	nock = Node3D.new()
	nock.name = "Nock"
	add_child(nock)
	Geo.cylinder(self, 0.032, 0.032, 0.19, Vector3.ZERO, leather, 10)
	for i in range(8):
		Geo.cylinder(self, 0.034, 0.034, 0.009, Vector3(0, -0.081 + i * 0.023, 0), edge, 10)
	Geo.box(self, Vector3(0.065, 0.016, 0.047), Vector3(0.017, -0.018, -0.025), edge)
	_points.resize((SEGMENTS + 1) * 2)
	for side in range(2):
		for j in range(SEGMENTS):
			var radius: float = lerpf(0.032, 0.013, float(j) / SEGMENTS)
			var limb := Geo.cylinder(self, radius, radius * 0.9, 1.0, Vector3.ZERO, wood, 6)
			_limbs.append(limb)
		_strings.append(Geo.cylinder(self, 0.0026, 0.0026, 1.0, Vector3.ZERO, cord, 5))
		_tip_caps.append(Geo.sphere(self, 0.021, Vector3.ZERO, edge, Vector3(0.8, 1.4, 0.8)))
		var collar_y: float = (-1.0 if side == 0 else 1.0) * 0.115
		Geo.cylinder(self, 0.039, 0.036, 0.045, Vector3(0, collar_y, 0), edge, 8)
	if bow_kind == 1:
		for side in [-1.0, 1.0]:
			Geo.box(self, Vector3(0.052, 0.16, 0.018), Vector3(0, side * 0.19, -0.027), edge)
	elif bow_kind == 2:
		for side in [-1.0, 1.0]:
			Geo.sphere(self, 0.035, Vector3(0, side * 0.13, -0.025), edge, Vector3(0.8, 1.4, 0.55))
	nocked_arrow = create_arrow_visual()
	nocked_arrow.name = "NockedArrow"
	add_child(nocked_arrow)
	arrow_tip = nocked_arrow.get_node("ArrowTip") as Node3D
	_rest_lengths.resize(SEGMENTS)
	_rest_angles.resize(SEGMENTS)
	var previous := Vector2.ZERO
	for index in SEGMENTS:
		var point := _rest_point(float(index + 1) / SEGMENTS)
		var segment := point - previous
		_rest_lengths[index] = segment.length()
		_rest_angles[index] = atan2(segment.y, segment.x)
		previous = point
	_string_half_length = previous.distance_to(Vector2(0, BRACE_DISTANCE))
	_ready_built = true

static func create_arrow_visual() -> Node3D:
	var visual := Node3D.new()
	var metal := Geo.material(Color("d3aa63"), 0.48, 0.38)
	var shaft := Geo.material(Color("dfc89a"))
	var feather := Geo.material(Color("e8d5a9"))
	var feather_dark := Geo.material(Color("b85e39"))
	Geo.beam(visual, Vector3.ZERO, Vector3(0, 0, -ARROW_SHAFT), 0.005, shaft, 6)
	var point := Geo.cylinder(visual, 0.020, 0.0, 0.07, Vector3(0, 0, -0.945), metal, 4)
	point.rotation.x = -PI / 2.0
	for i in range(3):
		var vane := Node3D.new()
		vane.rotation.z = i * TAU / 3.0
		visual.add_child(vane)
		Geo.box(vane, Vector3(0.003, 0.038, 0.09), Vector3(0, 0.019, -0.075), feather if i != 1 else feather_dark)
	var tip := Node3D.new()
	tip.name = "ArrowTip"
	tip.position = Vector3(0, 0, -ARROW_LENGTH)
	visual.add_child(tip)
	return visual

func set_draw(value: float) -> void:
	var next_draw := clampf(value, 0.0, 1.0)
	if _has_pose and is_equal_approx(next_draw, normalized_draw):
		return
	normalized_draw = next_draw
	if not _ready_built:
		return
	_has_pose = true
	nock.position = Vector3(0, 0, lerpf(BRACE_DISTANCE, DRAW_DISTANCE, normalized_draw))
	nocked_arrow.position = nock.position
	# Drawing rotates fixed-length wood segments until the inextensible cord
	# reaches the fingers. Neither the wood nor the string stretches.
	var low := 0.0
	var high := 2.0
	if normalized_draw > 0.0:
		for iteration in 16:
			var candidate := (low + high) * 0.5
			if _tip_at_bend(candidate).distance_to(Vector2(0, nock.position.z)) > _string_half_length:
				low = candidate
			else:
				high = candidate
	else:
		high = 0.0
	var bend := (low + high) * 0.5
	for side in 2:
		var sign_y := -1.0 if side == 0 else 1.0
		var point := Vector2.ZERO
		var base := side * (SEGMENTS + 1)
		_points[base] = Vector3.ZERO
		for index in SEGMENTS:
			var angle := _rest_angles[index] + bend * (0.4 + 0.6 * (float(index) + 0.5) / SEGMENTS)
			point += Vector2(cos(angle), sin(angle)) * _rest_lengths[index]
			_points[base + index + 1] = Vector3(0, point.x * sign_y, point.y)
			Geo.place_beam(_limbs[side * SEGMENTS + index], _points[base + index], _points[base + index + 1])
		var tip := _points[base + SEGMENTS]
		Geo.place_beam(_strings[side], tip, nock.position)
		_tip_caps[side].position = tip

func _rest_point(t: float) -> Vector2:
	var z := 0.105 * t * t
	if bow_kind == 1:
		z = 0.13 * sin(t * PI * 0.95) - 0.095 * pow(t, 5.0)
	elif bow_kind == 2:
		z = 0.165 * t * t
	return Vector2(bow_length * 0.5 * t, z)

func _tip_at_bend(bend: float) -> Vector2:
	var point := Vector2.ZERO
	for index in SEGMENTS:
		var angle := _rest_angles[index] + bend * (0.4 + 0.6 * (float(index) + 0.5) / SEGMENTS)
		point += Vector2(cos(angle), sin(angle)) * _rest_lengths[index]
	return point

func set_arrow_visible(value: bool) -> void:
	if _ready_built:
		nocked_arrow.visible = value

func get_grip_position() -> Vector3:
	return grip.global_position

func get_nock_position() -> Vector3:
	return nock.global_position

func get_arrow_origin() -> Vector3:
	return arrow_tip.global_position

func get_arrow_direction() -> Vector3:
	return -global_basis.z.normalized()
