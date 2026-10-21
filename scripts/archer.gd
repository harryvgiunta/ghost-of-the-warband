extends Node3D

signal arrow_released(origin: Vector3, direction: Vector3, speed: float, charge: float)
signal loadout_changed()
signal melee_strike

const Geo = preload("res://scripts/geo.gd")
const Bow = preload("res://scripts/bow.gd")
const Sword = preload("res://scripts/sword.gd")
const BOW_DATA = [
	{"name": "Shortbow", "subtitle": "Quick ashwood scout bow", "attack_interval": 1.0, "draw_seconds": 0.65, "speed": 22.0, "length": 1.0},
	{"name": "Recurve", "subtitle": "Balanced horn-and-yew recurve", "attack_interval": 2.0, "draw_seconds": 0.95, "speed": 28.0, "length": 1.4},
	{"name": "Longbow", "subtitle": "Heavy heartwood war bow", "attack_interval": 3.0, "draw_seconds": 1.25, "speed": 34.0, "length": 1.8},
]
const ARMOR_NAMES = ["Ranger leather", "Sentinel mail", "Warden plate"]
const SWORD_DATA = [
	{"name":"Shortsword", "seconds":1.0, "length":0.80, "reach":1.8, "damage":30.0},
	{"name":"Arming sword", "seconds":2.0, "length":1.05, "reach":2.1, "damage":38.0},
	{"name":"Greatsword", "seconds":3.0, "length":1.40, "reach":2.5, "damage":50.0},
]
# Segment meshes and their endpoint nodes share these exact, unscaled lengths.
const ARM_UPPER: float = 0.33
const ARM_LOWER: float = 0.30
const LEG_UPPER: float = 0.43
const LEG_LOWER: float = 0.43
const GRIP_OFFSET: float = 0.08
const FINGER_OFFSET: float = 0.075
const MAX_ELEVATION: float = 25.0 * PI / 180.0
const STANCE_YAW: float = -80.0 * PI / 180.0
const RAISE_SECONDS: float = 0.30
const RELEASE_SECONDS: float = 0.28
const RECOVER_SECONDS: float = 0.95

var bow_index: int = 1
var armor_index: int = 0
var sword_index := 1
var weapon := "bow"
var active_sword: Node3D
var _swords: Array[Node3D] = []
var _melee_struck := false
var _roll_progress := -1.0
var _roll_direction := Vector3.FORWARD
var _landing_weight := 0.0
var _takeoff_weight := 0.0
var draw_amount: float = 0.0
var phase: String = "READY"
var bow_hand: Node3D
var string_hand: Node3D
var active_bow: Bow
var _bows: Array[Bow] = []
var _armor_pieces: Array = [[], [], []]
var _torso: Node3D
var _head: Node3D
var _upper_arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _wrists: Array[Node3D] = []
var _draw_fingers: Array[Node3D] = []
var _thighs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _ankle_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_bases: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _ground_sampler: Callable = Callable()
var _velocity: Vector3 = Vector3.ZERO
var _grounded: bool = true
var _gait: float = 0.0
var _walk_blend: float = 0.0
var _release_raise: float = 1.0
var _release_plant: float = 1.0
var _elevation: float = 0.0
var _shoulders: Array[Vector3] = [Vector3(-0.235, 1.51, 0), Vector3(0.235, 1.51, 0)]
var _aim_point: Vector3 = Vector3(0, 1.45, -20)
var _time: float = 0.0
var _phase_time: float = 0.0
var _release_draw: float = 0.0
var _release_charge: float = 0.0
var _built: bool = false
var _skin: StandardMaterial3D
var _cloth: StandardMaterial3D
var _navy: StandardMaterial3D
var _leather: StandardMaterial3D
var _dark_leather: StandardMaterial3D
var _gold: StandardMaterial3D
var _steel: StandardMaterial3D
var _mail: StandardMaterial3D

func _ready() -> void:
	name = "Archer"
	_skin = Geo.material(Color("cb9672"))
	_cloth = Geo.material(Color("265a60"))
	_navy = Geo.material(Color("243844"))
	_leather = Geo.material(Color("76513a"))
	_dark_leather = Geo.material(Color("352d29"))
	_gold = Geo.material(Color("c59b5a"), 0.62, 0.38)
	_steel = Geo.material(Color("8caaaf"), 0.7, 0.4)
	_mail = Geo.material(Color("465d65"), 0.6, 0.65)
	_torso = Node3D.new()
	_torso.name = "BreathingTorso"
	_torso.rotation.y = 0.0
	add_child(_torso)
	_build_body()
	_build_head()
	_build_arms()
	_build_equipment()
	_build_armor()
	for i in range(3):
		var bow: Bow = Bow.new()
		bow.name = "Bow" + str(i)
		bow.bow_kind = i
		bow.bow_length = BOW_DATA[i].length
		add_child(bow)
		_bows.append(bow)
		var sword := Sword.new()
		sword.sword_kind = i
		sword.blade_length = SWORD_DATA[i].length
		add_child(sword)
		_swords.append(sword)
	_built = true
	set_bow(bow_index)
	set_sword(sword_index)
	set_armor(armor_index)
	_update_pose()

func _build_body() -> void:
	var hips := Geo.cylinder(_torso, 0.235, 0.22, 0.20, Vector3(0, 0.94, 0), _navy, 8)
	hips.scale.z = 0.64
	var tunic := Geo.cylinder(_torso, 0.235, 0.275, 0.43, Vector3(0, 1.245, 0), _cloth, 8)
	tunic.scale.z = 0.62
	var shoulder_chest := Geo.sphere(_torso, 0.26, Vector3(0, 1.455, 0), _cloth, Vector3(1.0, 0.4, 0.63))
	shoulder_chest.rotation.z = 0
	Geo.cylinder(_torso, 0.083, 0.075, 0.17, Vector3(0, 1.65, 0), _skin, 10)
	for side in [-1.0, 1.0]:
		var skirt := Geo.box(_torso, Vector3(0.19, 0.22, 0.045), Vector3(side * 0.105, 0.95, -0.135), _cloth)
		skirt.rotation.z = side * 0.075
		Geo.box(_torso, Vector3(0.16, 0.025, 0.049), Vector3(side * 0.105, 0.85, -0.136), _gold)
	Geo.cylinder(_torso, 0.242, 0.242, 0.072, Vector3(0, 1.065, 0), _dark_leather, 8).scale.z = 0.64
	Geo.box(_torso, Vector3(0.095, 0.067, 0.025), Vector3(0, 1.068, -0.158), _gold)
	Geo.box(_torso, Vector3(0.054, 0.035, 0.029), Vector3(0, 1.068, -0.16), _dark_leather)

func _build_head() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.rotation.y = 0.0
	_head.position = Vector3(0, 1.805, 0)
	_torso.add_child(_head)
	var hair := Geo.material(Color("33271f"))
	var hair_light := Geo.material(Color("513829"))
	var eye_white := Geo.material(Color("dcd7c4"))
	var iris := Geo.material(Color("263c38"))
	var lip := Geo.material(Color("885747"))
	Geo.sphere(_head, 0.155, Vector3(0, 0.035, 0), _skin, Vector3(0.88, 1.18, 0.88))
	Geo.box(_head, Vector3(0.187, 0.118, 0.163), Vector3(0, -0.053, -0.01), _skin)
	Geo.sphere(_head, 0.105, Vector3(0, -0.062, -0.023), _skin, Vector3(1, 0.79, 0.87))
	for side in [-1.0, 1.0]:
		Geo.sphere(_head, 0.036, Vector3(side * 0.139, 0.005, 0.007), _skin, Vector3(0.45, 1.0, 0.65))
		Geo.sphere(_head, 0.039, Vector3(side * 0.077, -0.012, -0.095), _skin, Vector3(1, 0.8, 0.65))
		Geo.box(_head, Vector3(0.047, 0.014, 0.012), Vector3(side * 0.055, 0.025, -0.126), eye_white)
		Geo.box(_head, Vector3(0.014, 0.015, 0.008), Vector3(side * 0.055, 0.025, -0.135), iris)
		var brow := Geo.box(_head, Vector3(0.059, 0.015, 0.021), Vector3(side * 0.055, 0.047, -0.123), hair)
		brow.rotation.z = side * -0.10
		Geo.box(_head, Vector3(0.026, 0.077, 0.073), Vector3(side * 0.115, -0.031, -0.008), hair)
	Geo.sphere(_head, 0.029, Vector3(0, -0.009, -0.148), _skin, Vector3(0.68, 1.3, 1.04))
	Geo.box(_head, Vector3(0.026, 0.066, 0.024), Vector3(0, 0.018, -0.132), _skin)
	Geo.sphere(_head, 0.1, Vector3(0, -0.081, -0.041), hair, Vector3(1.0, 0.66, 0.93))
	Geo.box(_head, Vector3(0.073, 0.01, 0.008), Vector3(0, -0.06, -0.137), lip)
	Geo.box(_head, Vector3(0.092, 0.016, 0.018), Vector3(0, -0.046, -0.131), hair_light)
	Geo.sphere(_head, 0.157, Vector3(0, 0.087, 0.025), hair, Vector3(0.9, 0.86, 0.9))
	for i in range(5):
		var lock := Geo.box(_head, Vector3(0.043, 0.058, 0.12), Vector3(-0.085 + i * 0.041, 0.146 + 0.01 * sin(i), -0.014), hair_light if i % 2 == 0 else hair)
		lock.rotation.z = -0.22
		lock.rotation.x = -0.24

func _build_arms() -> void:
	for side in range(2):
		var upper := Node3D.new()
		upper.name = "LeftUpperArm" if side == 0 else "RightUpperArm"
		add_child(upper)
		_upper_arms.append(upper)
		var fore := Node3D.new()
		fore.name = "LeftForearm" if side == 0 else "RightForearm"
		upper.add_child(fore)
		fore.position.y = ARM_UPPER
		_forearms.append(fore)
		Geo.cylinder(upper, 0.082, 0.064, ARM_UPPER, Vector3(0, ARM_UPPER * 0.5, 0), _cloth, 10)
		Geo.sphere(upper, 0.082, Vector3.ZERO, _cloth)
		Geo.sphere(fore, 0.063, Vector3.ZERO, _skin)
		Geo.cylinder(fore, 0.062, 0.043, ARM_LOWER, Vector3(0, ARM_LOWER * 0.5, 0), _skin, 10)
		Geo.cylinder(fore, 0.065, 0.050, 0.17, Vector3(0, 0.18, 0), _dark_leather, 10)
		for y in [0.10, 0.25]:
			Geo.cylinder(fore, 0.067 if y < 0.2 else 0.052, 0.067 if y < 0.2 else 0.052, 0.018, Vector3(0, y, 0), _gold, 10)
		var wrist := Node3D.new()
		wrist.name = "LeftWrist" if side == 0 else "RightWrist"
		fore.add_child(wrist)
		wrist.position.y = ARM_LOWER
		_wrists.append(wrist)
		Geo.sphere(wrist, 0.043, Vector3.ZERO, _skin)
		# The palm extends forward from the wrist; contact is at fingers/grip.
		Geo.box(wrist, Vector3(0.071, 0.045, 0.065), Vector3(0, -0.008, -0.035), _skin)
		Geo.box(wrist, Vector3(0.074, 0.025, 0.037), Vector3(0, -0.023, -0.025), _dark_leather)
		for finger in range(3):
			var digit := Geo.box(wrist, Vector3(0.043, 0.014, 0.024), Vector3(-0.006, -0.018 + finger * 0.018, -0.075), _skin)
			if side == 1:
				_draw_fingers.append(digit)
		Geo.sphere(wrist, 0.023, Vector3(0.035, 0.013, -0.042), _skin, Vector3(0.65, 1, 1))
		var contact := Node3D.new()
		contact.name = "BowHand" if side == 0 else "StringHand"
		contact.position.z = -GRIP_OFFSET if side == 0 else -FINGER_OFFSET
		wrist.add_child(contact)
		if side == 0:
			bow_hand = contact
		else:
			string_hand = contact
		var thigh := Node3D.new()
		thigh.name = "LeftThigh" if side == 0 else "RightThigh"
		add_child(thigh)
		_thighs.append(thigh)
		Geo.cylinder(thigh, 0.106, 0.081, LEG_UPPER, Vector3(0, LEG_UPPER * 0.5, 0), _navy, 10)
		Geo.sphere(thigh, 0.105, Vector3.ZERO, _navy)
		var shin := Node3D.new()
		thigh.add_child(shin)
		shin.position.y = LEG_UPPER
		_shins.append(shin)
		Geo.sphere(shin, 0.081, Vector3.ZERO, _navy)
		Geo.cylinder(shin, 0.080, 0.058, LEG_LOWER, Vector3(0, LEG_LOWER * 0.5, 0), _navy, 10)
		Geo.cylinder(shin, 0.083, 0.069, 0.25, Vector3(0, LEG_LOWER - 0.125, 0), _dark_leather, 10)
		Geo.cylinder(shin, 0.089, 0.089, 0.04, Vector3(0, LEG_LOWER - 0.25, 0), _leather, 10)
		var ankle := Node3D.new()
		shin.add_child(ankle)
		ankle.position.y = LEG_LOWER
		_ankles.append(ankle)
		Geo.sphere(ankle, 0.068, Vector3.ZERO, _dark_leather)
		Geo.box(ankle, Vector3(0.16, 0.105, 0.27), Vector3(0, -0.060, -0.065), _dark_leather)
		Geo.box(ankle, Vector3(0.17, 0.025, 0.28), Vector3(0, -0.1175, -0.065), _leather)
		for lace in range(3):
			Geo.box(ankle, Vector3(0.10, 0.012, 0.015), Vector3(0, -0.005, -0.04 - lace * 0.04), _leather)
		# Foot reports the sole directly beneath the ankle, not the toe tip.
		var foot := Node3D.new()
		foot.position.y = -0.13
		ankle.add_child(foot)
		_feet.append(foot)

func _build_equipment() -> void:
	var strap := Geo.beam(_torso, Vector3(-0.18, 1.49, -0.155), Vector3(0.18, 1.09, -0.164), 0.025, _leather, 4)
	strap.name = "QuiverHarness"
	Geo.box(_torso, Vector3(0.065, 0.065, 0.025), Vector3(0.02, 1.27, -0.19), _gold).rotation.z = -0.65
	var quiver := Node3D.new()
	quiver.position = Vector3(0.225, 1.29, 0.21)
	quiver.rotation.z = -0.22
	_torso.add_child(quiver)
	Geo.cylinder(quiver, 0.075, 0.093, 0.48, Vector3.ZERO, _leather, 10)
	Geo.cylinder(quiver, 0.098, 0.098, 0.045, Vector3(0, 0.23, 0), _gold, 10)
	Geo.cylinder(quiver, 0.078, 0.078, 0.025, Vector3(0, 0.254, 0), _dark_leather, 10)
	Geo.cylinder(quiver, 0.078, 0.078, 0.035, Vector3(0, -0.23, 0), _dark_leather, 10)
	for i in range(5):
		var x: float = cos(i * 2.4) * 0.045
		var z: float = sin(i * 2.4) * 0.045
		var h: float = 0.49 + (i % 3) * 0.025
		Geo.beam(quiver, Vector3(x, 0.20, z), Vector3(x, h, z), 0.004, _gold, 6)
		Geo.box(quiver, Vector3(0.035, 0.08, 0.003), Vector3(x, h - 0.04, z), _cloth)
		Geo.box(quiver, Vector3(0.003, 0.08, 0.035), Vector3(x, h - 0.04, z), _gold)
	Geo.box(_torso, Vector3(0.13, 0.15, 0.075), Vector3(-0.23, 1.035, 0.025), _leather)
	Geo.box(_torso, Vector3(0.14, 0.04, 0.085), Vector3(-0.23, 1.11, 0.025), _dark_leather)
	Geo.sphere(_torso, 0.012, Vector3(-0.23, 1.073, -0.018), _gold)
	var knife := Geo.box(_torso, Vector3(0.046, 0.25, 0.055), Vector3(0.232, 0.95, -0.005), _dark_leather)
	knife.rotation.z = -0.16
	Geo.box(_torso, Vector3(0.075, 0.022, 0.07), Vector3(0.21, 1.085, -0.005), _gold)

func _armor_node(parent: Node3D, index: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Armor" + str(index)
	parent.add_child(node)
	_armor_pieces[index].append(node)
	return node

func _build_armor() -> void:
	for index in range(3):
		var chest := _armor_node(_torso, index)
		if index == 0:
			for side in [-1.0, 1.0]:
				var panel := Geo.box(chest, Vector3(0.16, 0.29, 0.043), Vector3(side * 0.12, 1.30, -0.146), _leather)
				panel.rotation.z = side * -0.08
				for j in range(4):
					Geo.sphere(chest, 0.009, Vector3(side * 0.18, 1.20 + j * 0.061, -0.175), _gold)
		elif index == 1:
			var vest := Geo.cylinder(chest, 0.249, 0.284, 0.40, Vector3(0, 1.29, 0), _mail, 10)
			vest.scale.z = 0.68
			for row in range(9):
				for column in range(9):
					var x: float = -0.185 + column * 0.046 + (0.011 if row % 2 == 1 else 0.0)
					var ring := Geo.sphere(chest, 0.016, Vector3(x, 1.12 + row * 0.039, -0.174 + absf(x) * 0.15), _steel, Vector3(1, 0.7, 0.28))
					ring.rotation.z = 0.35 if row % 2 == 0 else -0.35
			Geo.box(chest, Vector3(0.11, 0.25, 0.035), Vector3(0, 1.3, -0.197), _navy)
			Geo.box(chest, Vector3(0.055, 0.055, 0.02), Vector3(0, 1.37, -0.22), _gold).rotation.z = PI / 4.0
		else:
			var breastplate := Geo.cylinder(chest, 0.244, 0.29, 0.35, Vector3(0, 1.315, -0.008), _steel, 8)
			breastplate.scale.z = 0.72
			for side in [-1.0, 1.0]:
				var pectoral := Geo.sphere(chest, 0.135, Vector3(side * 0.12, 1.4, -0.134), _steel, Vector3(1, 0.7, 0.58))
				pectoral.rotation.z = side * 0.12
				Geo.beam(chest, Vector3(side * 0.21, 1.46, -0.175), Vector3(0, 1.25, -0.202), 0.014, _gold, 6)
				var tasset := Geo.box(chest, Vector3(0.18, 0.22, 0.045), Vector3(side * 0.115, 0.99, -0.18), _steel)
				tasset.rotation.z = side * -0.12
				Geo.box(chest, Vector3(0.16, 0.02, 0.051), Vector3(side * 0.115, 0.9, -0.181), _gold)
			for j in range(3):
				Geo.box(chest, Vector3(0.39 - j * 0.01, 0.038, 0.038), Vector3(0, 1.19 - j * 0.047, -0.17), _steel)
			Geo.sphere(chest, 0.038, Vector3(0, 1.4, -0.219), _gold, Vector3(0.72, 1.2, 0.3))
			var collar := Geo.cylinder(chest, 0.14, 0.12, 0.07, Vector3(0, 1.585, 0), _steel, 10)
			collar.scale.z = 0.8
		for side in range(2):
			var shoulder := _armor_node(_upper_arms[side], index)
			var bracer := _armor_node(_forearms[side], index)
			if index == 0:
				Geo.sphere(shoulder, 0.101, Vector3(0, 0.045, 0), _leather, Vector3(1, 1.0, 1))
				Geo.box(bracer, Vector3(0.085, 0.15, 0.026), Vector3(0, 0.17, -0.057), _leather)
			elif index == 1:
				Geo.cylinder(shoulder, 0.105, 0.083, 0.22, Vector3(0, 0.09, 0), _mail, 10)
				for j in range(4):
					Geo.cylinder(shoulder, 0.105 - j * 0.005, 0.105 - j * 0.005, 0.012, Vector3(0, j * 0.048, 0), _steel, 10)
				Geo.box(bracer, Vector3(0.08, 0.17, 0.03), Vector3(0, 0.17, -0.065), _steel)
			else:
				Geo.sphere(shoulder, 0.127, Vector3(0, 0.025, 0), _steel, Vector3(1.0, 0.9, 1.0))
				for j in range(3):
					Geo.cylinder(shoulder, 0.12 - j * 0.013, 0.105 - j * 0.013, 0.065, Vector3(0, 0.085 + j * 0.052, 0), _steel, 8)
				Geo.cylinder(shoulder, 0.124, 0.124, 0.02, Vector3(0, 0.06, 0), _gold, 8)
				Geo.cylinder(bracer, 0.078, 0.06, 0.2, Vector3(0, 0.17, 0), _steel, 8)
				Geo.box(bracer, Vector3(0.024, 0.17, 0.024), Vector3(0, 0.17, -0.072), _gold)

func set_bow(index: int) -> void:
	bow_index = clampi(index, 0, 2)
	if not _built:
		return
	for i in range(_bows.size()):
		_bows[i].visible = weapon == "bow" and i == bow_index
	active_bow = _bows[bow_index]
	active_bow.set_draw(draw_amount)
	_update_pose()
	loadout_changed.emit()

func set_sword(index: int) -> void:
	if phase == "MELEE":
		phase = "READY"
	sword_index = clampi(index,0,2)
	if not _built:
		return
	for i in _swords.size():
		_swords[i].visible = weapon == "sword" and i == sword_index
	active_sword = _swords[sword_index]
	_update_pose()
	loadout_changed.emit()

func set_weapon(value: String) -> void:
	if value not in ["bow","sword"] or value == weapon:
		return
	phase = "READY"
	draw_amount = 0.0
	weapon = value
	set_bow(bow_index)
	set_sword(sword_index)

func begin_melee() -> bool:
	if weapon != "sword" or phase != "READY" or _roll_progress >= 0:
		return false
	phase = "MELEE"
	_phase_time = 0.0
	_melee_struck = false
	_update_pose()
	return true

func set_roll(progress: float, direction: Vector3) -> void:
	_roll_progress = progress
	_roll_direction = direction
	_update_pose()

func set_armor(index: int) -> void:
	armor_index = clampi(index, 0, 2)
	if not _built:
		return
	for i in range(3):
		for piece: Node3D in _armor_pieces[i]:
			piece.visible = i == armor_index
	loadout_changed.emit()

func is_charged_action() -> bool:
	return phase == "DRAWING" or phase == "HOLDING" or phase == "RELEASE" or phase == "RECOVER"


func begin_draw() -> void:
	if weapon != "bow" or _roll_progress >= 0 or (phase != "READY" and phase != "RECOVER"):
		return
	draw_amount = 0.0
	phase = "DRAWING"
	_phase_time = 0.0
	_update_pose()

func release_string() -> void:
	if phase != "DRAWING" and phase != "HOLDING":
		return
	# Capture the actual loaded pose before the string snaps, not its relaxed nock.
	_release_charge = clampf(draw_amount, 0.0, 1.0)
	_release_draw = draw_amount
	_release_raise = smoothstep(0.07, RAISE_SECONDS, _phase_time) if phase == "DRAWING" else 1.0
	_release_plant = smoothstep(0.0, 0.18, _phase_time) if phase == "DRAWING" else 1.0
	var origin: Vector3 = get_arrow_origin()
	var direction: Vector3 = (_aim_point - origin).normalized()
	if direction.length_squared() < 0.0001:
		direction = active_bow.get_arrow_direction()
	phase = "RELEASE"
	_phase_time = 0.0
	var speed: float = float(BOW_DATA[bow_index].speed) * lerpf(0.45, 1.0, _release_charge)
	active_bow.set_arrow_visible(false)
	arrow_released.emit(origin, direction, speed, _release_charge)
	_update_pose()

func cancel_draw() -> void:
	if phase != "DRAWING" and phase != "HOLDING" and phase != "MELEE":
		return
	draw_amount = 0.0
	phase = "READY"
	_phase_time = 0.0
	if _built:
		_update_pose()

func aim_at(world_point: Vector3) -> void:
	_aim_point = world_point
	if _built and phase != "READY":
		_update_pose()

func set_locomotion(world_velocity: Vector3, grounded: bool) -> void:
	if grounded and not _grounded and _velocity.y < -1.0:
		_landing_weight = 1.0
	if not grounded and _grounded and world_velocity.y > 1.0:
		_takeoff_weight = 1.0
	_velocity = world_velocity
	_grounded = grounded
	if phase == "READY" and Vector2(world_velocity.x, world_velocity.z).length_squared() > 0.01:
		global_rotation.y = atan2(-world_velocity.x, -world_velocity.z)

func set_ground_sampler(sampler: Callable) -> void:
	_ground_sampler = sampler

func get_animation_state() -> Dictionary:
	return {"phase": phase, "draw": draw_amount, "time": _phase_time,
		"aim": _aim_point, "release_draw": _release_draw,
		"release_charge": _release_charge, "release_raise": _release_raise,
		"release_plant": _release_plant, "yaw": global_rotation.y,
		"roll":_roll_progress,"roll_direction":_roll_direction,"landing":_landing_weight,"takeoff":_takeoff_weight}

func apply_animation_state(state: Dictionary) -> void:
	phase = str(state.phase)
	draw_amount = float(state.draw)
	_phase_time = float(state.time)
	_aim_point = state.aim
	_release_draw = float(state.release_draw)
	_release_charge = float(state.release_charge)
	_release_raise = float(state.release_raise)
	_release_plant = float(state.release_plant)
	global_rotation.y = float(state.yaw)
	_roll_progress = float(state.roll)
	_roll_direction = state.roll_direction
	_landing_weight = float(state.landing)
	_takeoff_weight = float(state.takeoff)
	_update_pose()

func get_arrow_origin() -> Vector3:
	if not _built:
		return global_position + Vector3(0, 1.45, -0.8)
	return active_bow.get_arrow_origin()

func get_stance_forward() -> Vector3:
	return -_torso.global_basis.z.normalized()

func get_joint_positions() -> Dictionary:
	# All joints are actual mesh hierarchy endpoints, never cached ideal IK targets.
	# Foot is local -Y 0.13m from ankle along the terrain normal; toes extend 0.205m.
	return {
		"left_shoulder": _upper_arms[0].global_position,
		"left_elbow": _forearms[0].global_position,
		"left_wrist": _wrists[0].global_position,
		"right_shoulder": _upper_arms[1].global_position,
		"right_elbow": _forearms[1].global_position,
		"right_wrist": _wrists[1].global_position,
		"left_hip": _thighs[0].global_position,
		"left_knee": _shins[0].global_position,
		"left_ankle": _ankles[0].global_position,
		"right_hip": _thighs[1].global_position,
		"right_knee": _shins[1].global_position,
		"right_ankle": _ankles[1].global_position,
		"left_foot": _feet[0].global_position,
		"right_foot": _feet[1].global_position,
		"anchor": _head.to_global(Vector3(0.105, -0.105, -0.065)),
	}

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_landing_weight = move_toward(_landing_weight,0.0,delta*4.0)
	_takeoff_weight = move_toward(_takeoff_weight,0.0,delta*8.0)
	var previous_time: float = _phase_time
	_phase_time += delta
	var speed: float = Vector2(_velocity.x, _velocity.z).length()
	var walking: float = clampf(speed / 3.4, 0.0, 1.0) if _grounded else 0.0
	_walk_blend = move_toward(_walk_blend, walking, delta * 7.0)
	_gait += delta * lerpf(7.0, 12.0, clampf(speed / 7.0, 0.0, 1.0)) * _walk_blend
	var strike_now := false
	match phase:
		"MELEE":
			var duration: float = SWORD_DATA[sword_index].seconds
			if _phase_time >= duration * 0.58 and not _melee_struck:
				_melee_struck = true
				strike_now = true
			if _phase_time >= duration:
				phase = "READY"
				_phase_time = 0.0
		"DRAWING":
			# Plant, raise, then apply tension. Normalized draw survives equipment swaps.
			var tension_delta: float = maxf(0.0, _phase_time - RAISE_SECONDS) - maxf(0.0, previous_time - RAISE_SECONDS)
			draw_amount = minf(1.0, draw_amount + tension_delta / float(BOW_DATA[bow_index].draw_seconds))
			if draw_amount >= 1.0:
				phase = "HOLDING"
				_phase_time = 0.0
		"RELEASE":
			draw_amount = _release_draw * (1.0 - smoothstep(0.0, 0.075, _phase_time))
			if _phase_time >= RELEASE_SECONDS:
				draw_amount = 0.0
				phase = "RECOVER"
				_phase_time = 0.0
		"RECOVER":
			if _phase_time >= RECOVER_SECONDS:
				phase = "READY"
				_phase_time = 0.0
	_update_pose()
	if strike_now:
		melee_strike.emit()

func _update_pose() -> void:
	if not _built:
		return
	if weapon == "sword" and is_instance_valid(active_sword):
		_update_melee_pose()
		_apply_roll()
		return
	var raise_amount: float = 0.0
	var plant: float = 0.0
	var held_draw: float = draw_amount
	if phase == "DRAWING":
		plant = smoothstep(0.0, 0.18, _phase_time)
		raise_amount = smoothstep(0.07, RAISE_SECONDS, _phase_time)
	elif phase == "HOLDING":
		plant = 1.0
		raise_amount = 1.0
	elif phase == "RELEASE" or phase == "RECOVER":
		plant = _release_plant
		raise_amount = _release_raise
		held_draw = _release_draw
		if phase == "RECOVER":
			raise_amount *= 1.0 - smoothstep(0.18, 0.72, _phase_time)
			plant *= 1.0 - smoothstep(0.72, RECOVER_SECONDS, _phase_time)
	if phase != "READY":
		var aim_offset: Vector3 = _aim_point - (global_position + Vector3(0, 1.70, 0))
		var horizontal: float = Vector2(aim_offset.x, aim_offset.z).length()
		if horizontal > 0.001:
			global_rotation.y = atan2(-aim_offset.x, -aim_offset.z)
		_elevation = clampf(atan2(aim_offset.y, maxf(horizontal, 0.001)), -MAX_ELEVATION, MAX_ELEVATION)
	var stride: float = _walk_blend
	var bob: float = -0.035 * stride + sin(_gait * 2.0) * 0.012 * stride
	bob += sin(_time * 1.8) * 0.002 * (1.0 - stride)
	bob -= 0.10 * maxf(_landing_weight,_takeoff_weight)
	var torso_yaw: float = STANCE_YAW * plant
	# While shooting on the move, hips/feet keep a softer angle than the chest;
	# the gait travels along actual velocity, including strafing and backpedaling.
	var lower_yaw := lerpf(torso_yaw, deg_to_rad(-35.0), _walk_blend * plant)
	var stance_basis := Basis(Vector3.UP, lower_yaw)
	var pitch := Basis(Vector3.RIGHT, _elevation * raise_amount)
	var pivot := Vector3(0, 1.0, 0)
	bob = _prepare_feet(stance_basis, pitch, plant * (1.0 - stride), stride, bob)
	var pose_offset: Vector3 = pivot - pitch * pivot + Vector3(0, bob, 0)
	_torso.transform = Transform3D(pitch * Basis(Vector3.UP, torso_yaw), pose_offset)
	_head.rotation = Vector3(0, -torso_yaw, 0)
	# Bow grip is pushed toward the target as the fingers pull back to the jaw.
	# All three bows use the same human draw length, never scaled limbs.
	var carry_grip: Vector3 = stance_basis * Vector3(-0.25, 1.22, -0.24)
	var shot_grip := Vector3(0.105, 1.70, lerpf(-0.59, -0.89, held_draw))
	var grip_position: Vector3 = pitch * carry_grip.lerp(shot_grip, raise_amount) + pose_offset
	# Keep the string in front of the chest while the feet/torso turn side-on.
	var carry_basis := Basis(Vector3.RIGHT, -0.45)
	var hand_basis: Basis = pitch * carry_basis.slerp(Basis.IDENTITY, raise_amount)
	var left_shoulder: Vector3 = _torso.transform * _shoulders[0]
	var right_shoulder: Vector3 = _torso.transform * _shoulders[1]
	_solve_chain(_upper_arms[0], _forearms[0], left_shoulder, grip_position + hand_basis.z * GRIP_OFFSET, pitch * Vector3(-0.5, -0.8, 0.1), ARM_UPPER, ARM_LOWER)
	_orient_endpoint(_wrists[0], _upper_arms[0], _forearms[0], hand_basis)
	# Bow follows the real grip endpoint, including any reachable-target correction.
	active_bow.transform = Transform3D(hand_basis, to_local(bow_hand.global_position))
	active_bow.set_draw(draw_amount)
	active_bow.set_arrow_visible(phase == "READY" or phase == "DRAWING" or phase == "HOLDING" or (phase == "RECOVER" and _phase_time >= 0.68))
	var right_contact: Vector3 = to_local(active_bow.get_nock_position())
	var relaxed_wrist: Vector3 = _torso.transform * Vector3(0.29, 1.00, 0.025 + sin(_gait) * 0.16 * stride)
	var right_basis: Basis = hand_basis
	if phase == "READY":
		right_basis = Basis(Vector3.RIGHT, -1.10)
		right_contact = relaxed_wrist - right_basis.z * FINGER_OFFSET
	elif phase == "RELEASE" or phase == "RECOVER":
		# The string snaps FORWARD alone. Fingers and wrist continue BACKWARD.
		var release_pitch := Basis(Vector3.RIGHT, _elevation * _release_raise)
		var release_offset: Vector3 = pivot - release_pitch * pivot + Vector3(0, bob, 0)
		var release_stance := Basis(Vector3.UP, STANCE_YAW * _release_plant)
		var released_grip: Vector3 = release_pitch * (release_stance * Vector3(-0.25, 1.22, -0.24)).lerp(shot_grip, _release_raise) + release_offset
		var release_basis: Basis = release_pitch * Basis(Vector3.RIGHT, -0.45).slerp(Basis.IDENTITY, _release_raise)
		var follow: float = smoothstep(0.0, RELEASE_SECONDS, _phase_time) if phase == "RELEASE" else 1.0
		var follow_contact: Vector3 = released_grip + release_basis.z * (lerpf(Bow.BRACE_DISTANCE, Bow.DRAW_DISTANCE, _release_draw) + 0.14 * follow)
		right_contact = follow_contact
		right_basis = release_basis
		if phase == "RECOVER":
			var quiver_contact: Vector3 = _torso.transform * Vector3(0.22, 1.74, 0.24)
			if _phase_time < 0.40:
				right_contact = follow_contact.lerp(quiver_contact, smoothstep(0.05, 0.40, _phase_time))
			elif _phase_time < 0.68:
				right_contact = quiver_contact.lerp(to_local(active_bow.get_nock_position()), smoothstep(0.40, 0.68, _phase_time))
			else:
				right_basis = hand_basis.slerp(Basis(Vector3.RIGHT, -1.10), smoothstep(0.72, RECOVER_SECONDS, _phase_time))
				right_contact = to_local(active_bow.get_nock_position()).lerp(relaxed_wrist - right_basis.z * FINGER_OFFSET, smoothstep(0.72, RECOVER_SECONDS, _phase_time))
	var right_pole: Vector3 = pitch * Vector3(0.65, -0.15, 0.8).lerp(Vector3(0.5, -0.8, 0.1), 1.0 - raise_amount)
	_solve_chain(_upper_arms[1], _forearms[1], right_shoulder, right_contact + right_basis.z * FINGER_OFFSET, right_pole, ARM_UPPER, ARM_LOWER)
	_orient_endpoint(_wrists[1], _upper_arms[1], _forearms[1], right_basis)
	var finger_open: float = smoothstep(0.0, 0.045, _phase_time) if phase == "RELEASE" else 0.0
	if phase == "RECOVER":
		finger_open = 1.0 - smoothstep(0.15, 0.40, _phase_time)
	for finger: Node3D in _draw_fingers:
		finger.position.x = -0.006 + 0.016 * finger_open
		finger.position.z = -0.075 - 0.014 * finger_open
		finger.rotation.y = -0.7 * finger_open
	for side in range(2):
		var sign_x: float = -1.0 if side == 0 else 1.0
		var hip: Vector3 = pitch * stance_basis * Vector3(sign_x * 0.125, 0.94, 0) + pose_offset
		_solve_chain(_thighs[side], _shins[side], hip, _ankle_targets[side], stance_basis * Vector3(sign_x * 0.08, 0, -1), LEG_UPPER, LEG_LOWER)
		_orient_endpoint(_ankles[side], _thighs[side], _shins[side], _foot_bases[side])
	_apply_roll()

func _update_melee_pose() -> void:
	if phase == "MELEE":
		var toward := _aim_point - global_position
		if Vector2(toward.x,toward.z).length_squared() > 0.01:
			global_rotation.y = atan2(-toward.x,-toward.z)
	var t := clampf(_phase_time / float(SWORD_DATA[sword_index].seconds),0,1) if phase == "MELEE" else 0.0
	var windup := smoothstep(0.0,0.42,t)
	var cut := smoothstep(0.42,0.67,t)
	var recover := smoothstep(0.67,1.0,t)
	var loaded := windup * (1.0-cut)
	var delivered := cut * (1.0-recover)
	var stride := _walk_blend
	var bob := -0.035*stride + sin(_gait*2.0)*0.012*stride - 0.10*maxf(_landing_weight,_takeoff_weight) - 0.055*delivered
	bob = _prepare_feet(Basis.IDENTITY,Basis.IDENTITY,1.0-stride,stride,bob,0.18)
	var hip_basis := Basis(Vector3.UP,-0.10*loaded + 0.12*delivered)
	var shoulder_basis := Basis(Vector3.UP,-0.06 - 0.26*loaded + 0.30*delivered)
	shoulder_basis = Basis(Vector3.RIGHT,0.04*loaded - 0.14*delivered) * shoulder_basis
	var shift := Vector3(0,bob,0.025*loaded - 0.06*delivered)
	var pivot := Vector3(0,0.94,0)
	_torso.transform = Transform3D(shoulder_basis,pivot-shoulder_basis*pivot+shift)
	_head.rotation = Vector3(-0.04*delivered,0.06+0.26*loaded-0.30*delivered,0)
	for finger: Node3D in _draw_fingers:
		finger.position.x = -0.006
		finger.position.z = -0.075
		finger.rotation.y = 0.0
	var guard := Vector3(0.05 if sword_index == 2 else 0.25,1.21,-0.27)
	var high := Vector3(0.06 if sword_index == 2 else 0.16,2.00,-0.19)
	var low := Vector3(0.08 if sword_index == 2 else 0.18,1.20,-0.45)
	var contact := guard.lerp(high,windup).lerp(low,cut).lerp(guard,recover) + shift
	var angle := lerpf(lerpf(lerpf(-0.45,1.22,windup),-0.75,cut),-0.45,recover)
	var hand_basis := Basis(Vector3.RIGHT,angle)
	var shoulder: Vector3 = _torso.transform * _shoulders[1]
	_solve_chain(_upper_arms[1],_forearms[1],shoulder,contact+hand_basis.z*FINGER_OFFSET,Vector3(0.8,0.15,0.35),ARM_UPPER,ARM_LOWER)
	_orient_endpoint(_wrists[1],_upper_arms[1],_forearms[1],hand_basis)
	active_sword.transform = Transform3D(hand_basis,to_local(string_hand.global_position))
	var left_contact := Vector3(-0.32,1.15,0.02+0.14*delivered) + shift
	var left_basis := Basis(Vector3.RIGHT,-0.7)
	if sword_index == 2:
		left_contact = to_local(string_hand.global_position) + hand_basis.z*0.16
		left_basis = hand_basis
	shoulder = _torso.transform * _shoulders[0]
	_solve_chain(_upper_arms[0],_forearms[0],shoulder,left_contact+left_basis.z*GRIP_OFFSET,Vector3(-0.8,0.10,0.20),ARM_UPPER,ARM_LOWER)
	_orient_endpoint(_wrists[0],_upper_arms[0],_forearms[0],left_basis)
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var hip := hip_basis*Vector3(sign_x*0.125,0.94,0) + shift
		_solve_chain(_thighs[side],_shins[side],hip,_ankle_targets[side],Vector3(sign_x*0.08,0,-1),LEG_UPPER,LEG_LOWER)
		_orient_endpoint(_ankles[side],_thighs[side],_shins[side],_foot_bases[side])

func _apply_roll() -> void:
	if _roll_progress < 0.0:
		return
	var t := clampf(_roll_progress,0,1)
	var tuck := smoothstep(0.0,0.18,t) * (1.0-smoothstep(0.74,1.0,t))
	var base_offset := _torso.position
	var left_contact := to_local(bow_hand.global_position)
	var right_contact := to_local(string_hand.global_position)
	var left_basis := global_basis.transposed()*bow_hand.global_basis
	var right_basis := global_basis.transposed()*string_hand.global_basis
	var pelvis := Vector3(0,0.94,0)
	var curl := Basis(Vector3.RIGHT,-0.45*tuck)
	_torso.transform = Transform3D(curl*_torso.basis,pelvis+curl*(base_offset-pelvis)+Vector3(0,-0.16*tuck,0))
	_head.rotation.x = lerpf(_head.rotation.x,-0.30,tuck)
	left_contact = left_contact.lerp(Vector3(-0.28,1.12+base_offset.y,-0.34),tuck)
	left_basis = left_basis.slerp(Basis(Vector3.RIGHT,-PI/2.0),tuck)
	var protected_hand := Vector3(0.28,1.13+base_offset.y,-0.37)
	if weapon == "sword":
		protected_hand = Vector3(0.34,1.15+base_offset.y,-0.10)
		right_basis = right_basis.slerp(Basis(Vector3.UP,-PI/2.0)*Basis(Vector3.RIGHT,-0.05),tuck)
	right_contact = right_contact.lerp(protected_hand,tuck)
	_solve_chain(_upper_arms[0],_forearms[0],_torso.transform*_shoulders[0],left_contact+left_basis.z*GRIP_OFFSET,Vector3(-0.8,-0.3,0.1),ARM_UPPER,ARM_LOWER)
	_orient_endpoint(_wrists[0],_upper_arms[0],_forearms[0],left_basis)
	_solve_chain(_upper_arms[1],_forearms[1],_torso.transform*_shoulders[1],right_contact+right_basis.z*FINGER_OFFSET,Vector3(0.8,-0.3,0.1),ARM_UPPER,ARM_LOWER)
	_orient_endpoint(_wrists[1],_upper_arms[1],_forearms[1],right_basis)
	if weapon == "bow":
		active_bow.transform = Transform3D(left_basis,to_local(bow_hand.global_position))
		active_bow.set_arrow_visible(tuck < 0.1)
	else:
		active_sword.transform = Transform3D(right_basis,to_local(string_hand.global_position))
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var ankle := to_local(_ankles[side].global_position).lerp(Vector3(sign_x*0.16,0.60+base_offset.y,0.05),tuck)
		var hip: Vector3 = _torso.transform*Vector3(sign_x*0.125,0.94,0)
		var pole := Vector3(sign_x*0.08,0.8*tuck,-1)
		_solve_chain(_thighs[side],_shins[side],hip,ankle,pole,LEG_UPPER,LEG_LOWER)
		_orient_endpoint(_ankles[side],_thighs[side],_shins[side],_foot_bases[side]*Basis(Vector3.RIGHT,-0.4*tuck))
	var right := Vector3(-_roll_direction.z,0,_roll_direction.x)
	var local_axis := global_basis.transposed()*right.normalized()
	var spin := Basis(local_axis,-TAU*smoothstep(0.10,0.86,t))
	var pivot := Vector3(0,0.90,0)
	var turn := Transform3D(spin,pivot-spin*pivot)
	_torso.transform = turn*_torso.transform
	for limb in _upper_arms:
		limb.transform = turn*limb.transform
	for limb in _thighs:
		limb.transform = turn*limb.transform
	if weapon == "bow":
		active_bow.transform = turn*active_bow.transform
	else:
		active_sword.transform = turn*active_sword.transform

func _prepare_feet(stance: Basis, pitch: Basis, plant: float, stride: float, bob: float, stagger: float = 0.0) -> float:
	var lowest_floor: float = INF
	var travel := Vector3(_velocity.x, 0, _velocity.z)
	travel = global_basis.transposed() * travel.normalized() if travel.length_squared() > 0.01 else Vector3.FORWARD
	for side in range(2):
		var sign_x: float = -1.0 if side == 0 else 1.0
		var step_phase: float = _gait + (0.0 if side == 0 else PI)
		var lift: float = maxf(0.0, cos(step_phase)) * 0.14 * stride
		var sole: Vector3 = stance * Vector3(sign_x * 0.19, 0, sign_x * (stagger - 0.045) * plant)
		sole += travel * sin(step_phase) * 0.27 * stride
		var boot_basis: Basis = stance * Basis(Vector3.UP, -sign_x * 0.07)
		var floor_y: float = 0.0
		if _grounded and _ground_sampler.is_valid():
			var sample: Vector3 = to_global(sole)
			floor_y = float(_ground_sampler.call(sample)) - global_position.y
			var toe_sample: Vector3 = to_global(sole - boot_basis.z * 0.20)
			var edge_sample: Vector3 = to_global(sole + boot_basis.x * 0.08)
			var toe_y: float = float(_ground_sampler.call(toe_sample)) - global_position.y
			var edge_y: float = float(_ground_sampler.call(edge_sample)) - global_position.y
			var forward: Vector3 = (-boot_basis.z * 0.20 + Vector3.UP * (toe_y - floor_y)).normalized()
			var right: Vector3 = boot_basis.x * 0.08 + Vector3.UP * (edge_y - floor_y)
			var normal: Vector3 = right.cross(forward).normalized()
			boot_basis = Basis(forward.cross(normal).normalized(), normal, -forward)
		lowest_floor = minf(lowest_floor, floor_y)
		sole.y = floor_y + lift
		if not _grounded:
			sole.y += 0.14
			sole.z += 0.13 if side == 0 else -0.08
		_foot_bases[side] = boot_basis
		_ankle_targets[side] = sole + boot_basis.y * 0.13
	# Lower the pelvis before solving so both real ankles remain reachable on slopes.
	# Upper body, armor, shoulders, and jaw all inherit the same displacement.
	var pelvis_y: float = bob + lowest_floor
	var pivot := Vector3(0, 1.0, 0)
	for side in range(2):
		var sign_x: float = -1.0 if side == 0 else 1.0
		var hip: Vector3 = pitch * stance * Vector3(sign_x * 0.125, 0.94, 0) + pivot - pitch * pivot
		var ankle: Vector3 = _ankle_targets[side]
		var horizontal_squared: float = Vector2(hip.x - ankle.x, hip.z - ankle.z).length_squared()
		var reach: float = LEG_UPPER + LEG_LOWER - 0.005
		var vertical_reach: float = sqrt(maxf(0.0, reach * reach - horizontal_squared))
		pelvis_y = minf(pelvis_y, ankle.y + vertical_reach - hip.y)
	return pelvis_y


func _solve_chain(upper: Node3D, lower: Node3D, start: Vector3, target: Vector3, pole: Vector3, upper_length: float, lower_length: float) -> void:
	var offset: Vector3 = target - start
	var raw_distance: float = offset.length()
	var axis: Vector3 = offset / raw_distance if raw_distance > 0.00001 else Vector3.DOWN
	var distance: float = clampf(raw_distance, absf(upper_length - lower_length) + 0.0001, upper_length + lower_length - 0.0001)
	# Project the actual endpoint too; never clamp only the IK triangle distance.
	var endpoint: Vector3 = start + axis * distance
	var bend: Vector3 = pole - axis * pole.dot(axis)
	if bend.length_squared() < 0.00001:
		var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
		bend = reference - axis * reference.dot(axis)
	bend = bend.normalized()
	var along: float = (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height: float = sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var joint: Vector3 = start + axis * along + bend * height
	upper.transform = Transform3D(_segment_basis(joint - start), start)
	lower.transform = Transform3D(upper.basis.transposed() * _segment_basis(endpoint - joint), Vector3(0, upper_length, 0))

func _orient_endpoint(endpoint: Node3D, upper: Node3D, lower: Node3D, orientation: Basis) -> void:
	endpoint.basis = (upper.basis * lower.basis).transposed() * orientation

func _segment_basis(offset: Vector3) -> Basis:
	var up: Vector3 = offset.normalized()
	var reference: Vector3 = Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right: Vector3 = up.cross(reference).normalized()
	return Basis(right, up, right.cross(up).normalized())
