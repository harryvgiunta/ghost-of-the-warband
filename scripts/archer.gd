extends Node3D
## Imported humanoid animation, with skeletal aim/terrain corrections and real blade samples.

signal arrow_released(origin: Vector3, direction: Vector3, speed: float, charge: float)
signal loadout_changed()
signal melee_started()
signal melee_sweep(previous_base: Vector3, previous_tip: Vector3, current_base: Vector3, current_tip: Vector3, radius: float)

const Geo = preload("res://scripts/geo.gd")
const Bow = preload("res://scripts/bow.gd")
const Sword = preload("res://scripts/sword.gd")
const CHARACTER = preload("res://assets/characters/ironwood_ranger.glb")
const BOW_DATA = [
	{"name":"Shortbow", "subtitle":"Quick ashwood scout bow", "draw_seconds":1.0, "speed":22.0, "length":1.0},
	{"name":"Recurve", "subtitle":"Balanced horn-and-yew recurve", "draw_seconds":2.0, "speed":28.0, "length":1.4},
	{"name":"Longbow", "subtitle":"Heavy heartwood war bow", "draw_seconds":3.0, "speed":34.0, "length":1.8},
]
const SWORD_DATA = [
	{"name":"Shortsword", "seconds":1.0, "length":0.80, "reach":1.8, "damage":30.0},
	{"name":"Arming sword", "seconds":2.0, "length":1.05, "reach":2.1, "damage":38.0},
	{"name":"Greatsword", "seconds":3.0, "length":1.40, "reach":2.5, "damage":50.0},
]
const ARMOR_NAMES = ["Ranger leather", "Sentinel mail", "Warden plate"]
const RAISE_SECONDS := 0.30
const RELEASE_SECONDS := 0.28
const RECOVER_SECONDS := 0.95
const MAX_ELEVATION := deg_to_rad(25.0)
const STANCE_YAW := deg_to_rad(-80.0)
const MELEE_SAMPLE_SECONDS := 1.0 / 120.0
const BLEND_SECONDS := 0.12
static var _profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/ironwood_ranger.json"))

var bow_index := 1
var sword_index := 1
var armor_index := 0
var weapon := "bow"
var phase := "READY"
var draw_amount := 0.0
var charge_frozen := false
var bow_hand: Node3D
var string_hand: Node3D
var active_bow: Bow
var active_sword: Node3D
var skeleton: Skeleton3D
var _phase_time := 0.0
var _roll_progress := -1.0
var slide_progress := -1.0
var _slide_direction := Vector3.FORWARD
var _slide_weight := 0.0
var _velocity := Vector3.ZERO
var _grounded := true
var _cover_active := false
var _cover_normal := Vector3.ZERO
var _cover_lean := Vector3.ZERO
var _crouch_amount := 0.0
var _ground_sampler := Callable()
var _aim_point := Vector3(0,1.5,-20)
var _motion_time := 0.0
var _locomotion_phase := 0.0
var _air_time := 0.0
var _landing_weight := 0.0
var _release_draw := 0.0
var _release_charge := 0.0
var _release_raise := 0.0
var _release_grip := Vector3.ZERO
var _release_contact := Vector3.ZERO
var _release_bow_rotation := Quaternion.IDENTITY
var _model: Node3D
var _player: AnimationPlayer
var _bows: Array[Bow] = []
var _swords: Array[Node3D] = []
var _armor: Array[Node3D] = []
var _chest: Node3D
var _quiver: Node3D
var _chest_rest_basis := Basis.IDENTITY
var _bones: Dictionary = {}
var _arms: Array[PackedInt32Array] = []
var _legs: Array[PackedInt32Array] = []
var _leg_lengths := Vector2.ZERO
var _leg_bones := PackedInt32Array()
var _lower_pose: Array[Transform3D] = []
var _blend_pose: Array[Transform3D] = []
var _authored_pose: Array[Transform3D] = []
var _crouch_pose: Array[Transform3D] = []
var _slide_crouch_pose: Array[Transform3D] = []
var _crouch_lowering := 0.0
var _cover_bones := PackedInt32Array()
var _cover_neutral: Array[Transform3D] = []
var _cover_turns: Array[Basis] = []
var _cover_shift := Vector3.ZERO
var _guard_bones := PackedInt32Array()
var _guard_pose: Array[Transform3D] = []
var _display_clip := ""
var _display_lower_clip := ""
var _display_weapon := ""
var _display_drawing := false
var _blend_time := BLEND_SECONDS
var _palm_left := Vector3.ZERO
var _palm_right := Vector3.ZERO
var _jaw_bone := -1
var _jaw_offset := Vector3.ZERO
var _bow_grip_basis := Basis.IDENTITY
var _string_grip_basis := Basis.IDENTITY
var _sword_grip := Transform3D.IDENTITY
var _foot_height := Vector2.ZERO
var _foot_up: Array[Vector3] = []
var _built := false

func _ready() -> void:
	name = "Archer"
	_model = CHARACTER.instantiate()
	add_child(_model)
	_model.basis = Basis(Vector3.UP,PI)
	skeleton = _find_node_of_type(_model, "Skeleton3D") as Skeleton3D
	_player = _find_node_of_type(_model, "AnimationPlayer") as AnimationPlayer
	assert(skeleton != null and _player != null, "The ranger asset must contain its rig and authored animation library")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for index in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(index)] = index
		_blend_pose.append(Transform3D.IDENTITY)
		_authored_pose.append(skeleton.get_bone_pose(index))
		_crouch_pose.append(Transform3D.IDENTITY)
	for side in ["l", "r"]:
		_arms.append(PackedInt32Array([_bones["upperarm_"+side],_bones["lowerarm_"+side],_bones["hand_"+side]]))
		_legs.append(PackedInt32Array([_bones["thigh_"+side],_bones["calf_"+side],_bones["foot_"+side]]))
		for prefix in ["thigh_", "calf_", "foot_", "ball_", "ball_leaf_"]:
			_leg_bones.append(_bones[prefix+side])
	_leg_bones.append(_bones.pelvis)
	_lower_pose.resize(_leg_bones.size())
	for bone_name in ["pelvis","spine_01","spine_02","spine_03","neck_01","Head"]:
		_cover_bones.append(_bones[bone_name])
	_sample_clip(str(_profile.clips.cover_top.name),0.0)
	for bone in _cover_bones:
		_cover_neutral.append(skeleton.get_bone_global_pose(bone))
		_cover_turns.append(Basis.IDENTITY)
	var standing_pelvis := skeleton.get_bone_global_pose(_bones.pelvis).origin.y
	_sample_clip(str(_profile.clips.crouch_idle.name),0.0)
	_crouch_lowering = 0.58-(standing_pelvis-skeleton.get_bone_global_pose(_bones.pelvis).origin.y)
	for bone in skeleton.get_bone_count():
		_slide_crouch_pose.append(skeleton.get_bone_pose(bone))
	_palm_left = _vector(_profile.palms.left)
	_palm_right = _vector(_profile.palms.right)
	_jaw_bone = int(_bones[_profile.bow_anchor.bone])
	_jaw_offset = _vector(_profile.bow_anchor.position)
	var rotation: Array = _profile.sword_grip.rotation
	_sword_grip = Transform3D(Basis(Quaternion(rotation[0],rotation[1],rotation[2],rotation[3]).normalized()),_vector(_profile.sword_grip.position))
	for side in 2:
		var rest := skeleton.global_transform * skeleton.get_bone_global_rest(_legs[side][2])
		_foot_height[side] = rest.origin.y - global_position.y
		var thigh := skeleton.get_bone_global_rest(_legs[side][0]).origin
		var calf := skeleton.get_bone_global_rest(_legs[side][1]).origin
		_leg_lengths[side] = thigh.distance_to(calf)+calf.distance_to(skeleton.get_bone_global_rest(_legs[side][2]).origin)
		_foot_up.append(rest.basis.inverse() * Vector3.UP)
	for bone in skeleton.get_bone_count():
		var ancestor := bone
		while ancestor >= 0:
			if ancestor == int(_bones.clavicle_l) or ancestor == int(_bones.clavicle_r):
				_guard_bones.append(bone)
				_guard_pose.append(Transform3D.IDENTITY)
				break
			ancestor = skeleton.get_bone_parent(ancestor)
	_sample_clip("Sword_Idle_OneHand",0.0)
	var carry_basis := global_basis * Basis(Vector3.RIGHT,-0.45)
	_bow_grip_basis = _bone_world(_arms[0][2]).basis.inverse() * carry_basis
	_string_grip_basis = _bone_world(_arms[1][2]).basis.inverse() * global_basis
	bow_hand = Node3D.new()
	bow_hand.name = "BowGrip"
	add_child(bow_hand)
	string_hand = Node3D.new()
	string_hand.name = "StringGrip"
	add_child(string_hand)
	for index in 3:
		var bow := Bow.new()
		bow.bow_kind = index
		bow.bow_length = float(BOW_DATA[index].length)
		add_child(bow)
		_bows.append(bow)
		var sword := Sword.new()
		sword.sword_kind = index
		sword.blade_length = float(SWORD_DATA[index].length)
		add_child(sword)
		_swords.append(sword)
	active_bow = _bows[bow_index]
	active_sword = _swords[sword_index]
	_build_equipment()
	_built = true
	set_bow(bow_index)
	set_sword(sword_index)
	set_armor(armor_index)
	_update_pose(0.0)

func _find_node_of_type(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found := _find_node_of_type(child,type_name)
		if found != null:
			return found
	return null

func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

func _build_equipment() -> void:
	_chest = Node3D.new()
	add_child(_chest)
	_chest_rest_basis = (global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(_bones.spine_03)).basis
	var leather := Geo.material(Color("543d2c"))
	var trim := Geo.material(Color("be9454"),0.5,0.45)
	_quiver = Node3D.new()
	_quiver.position = Vector3(0.13,0.05,0.19)
	_quiver.rotation.z = -0.18
	_chest.add_child(_quiver)
	Geo.cylinder(_quiver,0.075,0.09,0.46,Vector3.ZERO,leather,12)
	Geo.cylinder(_quiver,0.094,0.094,0.04,Vector3(0,0.23,0),trim,12)
	for index in 5:
		var x := cos(index*2.4)*0.04
		var z := sin(index*2.4)*0.04
		Geo.beam(_quiver,Vector3(x,0.18,z),Vector3(x,0.47,z),0.004,trim,6)
		Geo.box(_quiver,Vector3(0.035,0.07,0.004),Vector3(x,0.43,z),trim)
	for index in 3:
		var armor := Node3D.new()
		_chest.add_child(armor)
		_armor.append(armor)
		if index == 0:
			continue # The imported ranger outfit is the leather loadout.
		var metal := Geo.material(Color("65777b") if index == 1 else Color("a3b5ba"),0.65,0.46)
		var coat := Geo.cylinder(armor,0.235,0.25,0.36,Vector3(0,-0.09,0),metal,16)
		coat.scale.z = 0.65
		if index == 1:
			for row in 7:
				Geo.cylinder(armor,0.238,0.238,0.018,Vector3(0,0.06-row*0.045,0),trim,16).scale.z = 0.65
		else:
			Geo.sphere(armor,0.21,Vector3(0,0.01,-0.09),metal,Vector3(1,0.85,0.40))
			Geo.box(armor,Vector3(0.025,0.32,0.025),Vector3(0,-0.06,-0.19),trim)

func set_bow(index: int) -> void:
	bow_index = clampi(index,0,2)
	if not _built:
		return
	for i in _bows.size():
		_bows[i].visible = weapon == "bow" and i == bow_index
	active_bow = _bows[bow_index]
	_update_pose(0.0)
	loadout_changed.emit()

func set_sword(index: int) -> void:
	if phase == "MELEE":
		phase = "READY"
		_phase_time = 0.0
	sword_index = clampi(index,0,2)
	if not _built:
		return
	for i in _swords.size():
		_swords[i].visible = weapon == "sword" and i == sword_index
	active_sword = _swords[sword_index]
	_update_pose(0.0)
	loadout_changed.emit()

func set_weapon(value: String) -> void:
	if value not in ["bow","sword"] or value == weapon:
		return
	if phase not in ["RELEASE","RECOVER"]:
		phase = "READY"
		_phase_time = 0.0
		draw_amount = 0.0
	weapon = value
	set_bow(bow_index)
	set_sword(sword_index)

func set_armor(index: int) -> void:
	armor_index = clampi(index,0,2)
	if not _built:
		return
	for i in _armor.size():
		_armor[i].visible = i == armor_index
	loadout_changed.emit()

func begin_melee() -> bool:
	if weapon != "sword" or phase != "READY" or _roll_progress >= 0.0:
		return false
	phase = "MELEE"
	_phase_time = 0.0
	melee_started.emit()
	_update_pose(0.0)
	return true

func begin_draw() -> void:
	if weapon != "bow" or phase != "READY" or _roll_progress >= 0.0:
		return
	draw_amount = 0.0
	charge_frozen = false
	phase = "DRAWING"
	_phase_time = 0.0
	_update_pose(0.0)

func get_bow_recovery_progress() -> float:
	var duration := RELEASE_SECONDS + RECOVER_SECONDS
	if phase == "RELEASE":
		return clampf(_phase_time/duration,0,1)
	if phase == "RECOVER":
		return clampf((RELEASE_SECONDS+_phase_time)/duration,0,1)
	return 1.0

func release_string() -> void:
	if phase not in ["DRAWING","HOLDING"]:
		return
	charge_frozen = false
	_release_charge = clampf(draw_amount,0,1)
	_release_draw = draw_amount
	_release_raise = _archery_weight()
	_release_grip = to_local(active_bow.global_position)
	_release_contact = to_local(string_hand.global_position)
	_release_bow_rotation = (global_basis.inverse()*active_bow.global_basis).get_rotation_quaternion()
	var origin := get_arrow_origin()
	var direction := (_aim_point-origin).normalized()
	if direction.length_squared() < 0.0001:
		direction = active_bow.get_arrow_direction()
	phase = "RELEASE"
	_phase_time = 0.0
	active_bow.set_arrow_visible(false)
	arrow_released.emit(origin,direction,float(BOW_DATA[bow_index].speed)*lerpf(0.45,1.0,_release_charge),_release_charge)
	_update_pose(0.0)

func cancel_draw() -> void:
	charge_frozen = false
	if phase not in ["DRAWING","HOLDING","MELEE"]:
		return
	phase = "READY"
	draw_amount = 0.0
	_phase_time = 0.0
	_update_pose(0.0)

func aim_at(world_point: Vector3) -> void:
	_aim_point = world_point
	if _built and phase != "READY":
		_update_pose(0.0)

func set_roll(progress: float, direction: Vector3) -> void:
	_roll_progress = progress
	if progress >= 0.0:
		global_basis = Basis(Vector3.UP,atan2(-direction.x,-direction.z))
	_update_pose(0.0)

func set_slide(progress: float, direction: Vector3) -> void:
	slide_progress = clampf(progress,0.0,1.0) if progress >= 0.0 else -1.0
	if slide_progress >= 0.0:
		var planar := Vector3(direction.x,0.0,direction.z)
		if not planar.is_zero_approx():
			_slide_direction = planar.normalized()
		if phase == "READY" and _roll_progress < 0.0:
			global_basis = Basis(Vector3.UP,atan2(-_slide_direction.x,-_slide_direction.z))
	elif _crouch_amount <= 0.0 or _cover_active:
		_slide_weight = 0.0

func set_cover(active: bool, outward: Vector3, crouch_amount: float, peeking: bool, lean: Vector3) -> void:
	_cover_active = active
	_cover_normal = outward
	_cover_lean = lean if active else Vector3.ZERO
	_crouch_amount = clampf(crouch_amount,0.0,1.0)
	if active and (phase == "READY" or not peeking):
		global_basis = Basis(Vector3.UP,atan2(-outward.x,-outward.z))

func set_locomotion(world_velocity: Vector3, grounded: bool) -> void:
	if grounded and not _grounded and _velocity.y < -1.0:
		_landing_weight = 1.0
	if not grounded and _grounded:
		_air_time = 0.0
	_velocity = world_velocity
	_grounded = grounded
	if not _cover_active and phase == "READY" and _roll_progress < 0.0 and slide_progress < 0.0 and Vector2(world_velocity.x,world_velocity.z).length_squared() > 0.01:
		global_basis = Basis(Vector3.UP,atan2(-world_velocity.x,-world_velocity.z))

func set_ground_sampler(sampler: Callable) -> void:
	_ground_sampler = sampler

func get_animation_state() -> Dictionary:
	# Roll facing already travels in yaw; compact slide state also fits maximum-length names.
	return {"phase":phase,"draw":draw_amount,"charge_frozen":charge_frozen,"time":_phase_time,"aim":_aim_point,
		"release_draw":_release_draw,"release_charge":_release_charge,"release_raise":_release_raise,
		"release_grip":_release_grip,"release_contact":_release_contact,"release_rotation":_release_bow_rotation,
		"yaw":global_rotation.y,"roll":_roll_progress,
		"slide":Vector4(slide_progress,_slide_direction.x,_slide_direction.z,_slide_weight),
		"motion_time":_motion_time,"locomotion_phase":_locomotion_phase,"air_time":_air_time,"landing":_landing_weight}

func apply_animation_state(state: Dictionary) -> void:
	phase = str(state.phase)
	draw_amount = float(state.draw)
	charge_frozen = bool(state.charge_frozen)
	_phase_time = float(state.time)
	_aim_point = state.aim
	_release_draw = float(state.release_draw)
	_release_charge = float(state.release_charge)
	_release_raise = float(state.release_raise)
	_release_grip = state.release_grip
	_release_contact = state.release_contact
	_release_bow_rotation = state.release_rotation
	global_basis = Basis(Vector3.UP,float(state.yaw))
	_roll_progress = float(state.roll)
	var slide: Vector4 = state.slide
	slide_progress = slide.x
	_slide_direction = Vector3(slide.y,0.0,slide.z)
	_slide_weight = slide.w
	_motion_time = float(state.motion_time)
	_locomotion_phase = float(state.locomotion_phase)
	_air_time = float(state.air_time)
	_landing_weight = float(state.landing)
	# The owning actor applies its single authoritative cover snapshot via set_cover first.
	_update_pose(0.0)

func get_arrow_origin() -> Vector3:
	return active_bow.get_arrow_origin()

func get_stance_forward() -> Vector3:
	var pose := _bone_world(_bones.spine_03)
	return (pose.basis * skeleton.get_bone_global_rest(_bones.spine_03).basis.inverse()).z.normalized()

func get_joint_positions() -> Dictionary:
	var result: Dictionary = {}
	for side in 2:
		var prefix := "left" if side == 0 else "right"
		result[prefix+"_shoulder"] = _bone_world(_arms[side][0]).origin
		result[prefix+"_elbow"] = _bone_world(_arms[side][1]).origin
		result[prefix+"_wrist"] = _bone_world(_arms[side][2]).origin
		result[prefix+"_hip"] = _bone_world(_legs[side][0]).origin
		result[prefix+"_knee"] = _bone_world(_legs[side][1]).origin
		var foot := _bone_world(_legs[side][2])
		result[prefix+"_ankle"] = foot.origin
		result[prefix+"_foot"] = foot.origin - foot.basis*_foot_up[side]*_foot_height[side]
	result["anchor"] = _jaw_anchor()
	return result

func get_blade_base() -> Vector3:
	return active_sword.to_global(Vector3(0,0,-0.09))

func get_blade_tip() -> Vector3:
	return active_sword.to_global(Vector3(0,0,-float(SWORD_DATA[sword_index].length)-0.09))

func _physics_process(delta: float) -> void:
	advance_animation(delta)

func advance_animation(delta: float) -> void:
	if not _built:
		return
	if phase != "MELEE":
		_advance_step(delta)
		return
	# The same sampled pose drives the skinned mesh, attached sword, and damage.
	# Chronological substeps prevent a long frame from skipping the downswing.
	var remaining := maxf(delta,0.0)
	while remaining > 0.000001 and phase == "MELEE":
		var step := minf(remaining,MELEE_SAMPLE_SECONDS)
		var previous_base := get_blade_base()
		var previous_tip := get_blade_tip()
		var previous_time := _phase_time
		_advance_step(step)
		var window := _melee_window()
		if _phase_time >= window.x and previous_time <= window.y and _roll_progress < 0.0:
			melee_sweep.emit(previous_base,previous_tip,get_blade_base(),get_blade_tip(),0.035+0.011*sword_index)
		if _phase_time >= float(SWORD_DATA[sword_index].seconds)-0.000001:
			phase = "READY"
			_phase_time = 0.0
		remaining -= step
	if remaining > 0.000001:
		_advance_step(remaining)

func _advance_step(delta: float) -> void:
	_phase_time += delta
	_motion_time += delta
	var slide_target := 1.0 if slide_progress >= 0.0 else 0.0
	_slide_weight = move_toward(_slide_weight,slide_target,delta/BLEND_SECONDS) if _grounded and _roll_progress < 0.0 and not _cover_active else 0.0
	if _grounded and slide_progress < 0.0:
		var speed := Vector2(_velocity.x,_velocity.z).length()
		var clip := _locomotion_clip(speed)
		var reference_speed := 8.5 if clip == "Sprint_Loop" else (5.5 if clip == "Jog_Fwd_Loop" else 2.4)
		var stride := reference_speed*float(_profile.animations[clip])
		stride = lerpf(stride,float(_profile.clips.crouch_forward.stride),_crouch_amount)
		_locomotion_phase = fposmod(_locomotion_phase+delta*speed/stride,1.0)
	_air_time += delta if not _grounded else 0.0
	_landing_weight = move_toward(_landing_weight,0.0,delta*4.0)
	match phase:
		"DRAWING":
			if not charge_frozen:
				draw_amount = minf(1.0,draw_amount+delta/float(BOW_DATA[bow_index].draw_seconds))
			if draw_amount >= 1.0-0.000001:
				draw_amount = 1.0
				phase = "HOLDING"
				_phase_time = 0.0
		"RELEASE":
			draw_amount = _release_draw*(1.0-smoothstep(0.0,0.075,_phase_time))
			if _phase_time >= RELEASE_SECONDS:
				draw_amount = 0.0
				phase = "RECOVER"
				_phase_time -= RELEASE_SECONDS
	if phase == "RECOVER" and _phase_time >= RECOVER_SECONDS-0.000001:
		phase = "READY"
		_phase_time = 0.0
	_update_pose(delta)

func _melee_clip() -> Dictionary:
	return _profile.clips.overhead if sword_index == 2 else _profile.clips.overhead_one_hand

func _melee_window() -> Vector2:
	var duration := float(SWORD_DATA[sword_index].seconds)
	var cut_seconds := 0.22+0.04*sword_index
	var windup := (duration-cut_seconds)*0.55
	return Vector2(windup,windup+cut_seconds)

func _melee_clip_time() -> float:
	var clip := _melee_clip()
	var window := _melee_window()
	var duration := float(SWORD_DATA[sword_index].seconds)
	if _phase_time < window.x:
		return lerpf(0.0,float(clip.strike_start),clampf(_phase_time/window.x,0,1))
	if _phase_time < window.y:
		return lerpf(float(clip.strike_start),float(clip.strike_end),(_phase_time-window.x)/(window.y-window.x))
	return lerpf(float(clip.strike_end),float(clip.duration),clampf((_phase_time-window.y)/(duration-window.y),0,1))

func _archery_weight() -> float:
	if phase == "DRAWING":
		return smoothstep(0.0,RAISE_SECONDS,_phase_time)
	if phase == "HOLDING":
		return 1.0
	if phase == "RELEASE":
		return _release_raise
	if phase == "RECOVER":
		return _release_raise*(1.0-smoothstep(0.18,0.72,_phase_time))
	return 0.0

func _sample_clip(clip: String, time: float) -> void:
	skeleton.reset_bone_poses()
	if _player.current_animation != clip:
		_player.play(clip,0.0)
	_player.seek(clampf(time,0.0,_player.get_animation(clip).length),true)

func _locomotion_clip(speed: float) -> String:
	if speed > 7.0:
		return "Sprint_Loop"
	if speed > 3.0:
		return "Jog_Fwd_Loop"
	return "Walk_Loop"

func _locomotion_clip_time(clip: String) -> float:
	return _locomotion_phase*_player.get_animation(clip).length

func _update_pose(delta: float) -> void:
	if not _built:
		return
	var speed := Vector2(_velocity.x,_velocity.z).length()
	var sliding := _grounded and _roll_progress < 0.0 and not _cover_active and (slide_progress >= 0.0 or _slide_weight > 0.0)
	var moving := _grounded and speed > 0.1 and _roll_progress < 0.0 and not sliding
	var drawing := weapon == "bow" and phase in ["DRAWING","HOLDING","RELEASE","RECOVER"]
	var coupled_carry := weapon == "sword" and sword_index == 2 and phase != "MELEE"
	var guarding := coupled_carry and _grounded and _roll_progress < 0.0
	var arm_overlay := coupled_carry and not guarding
	var action := phase == "MELEE" or drawing or guarding or _cover_active
	var layer_lower_body := action and (moving or (guarding and _landing_weight > 0.0))
	var lower_clip := (_locomotion_clip(speed) if moving else "Jump_Land") if layer_lower_body else ""
	var archery := _archery_weight() if drawing else 0.0
	if _roll_progress < 0.0 and (phase != "READY" or _cover_active):
		var offset := _aim_point-global_position
		if Vector2(offset.x,offset.z).length_squared() > 0.0001:
			var yaw := atan2(-offset.x,-offset.z)
			if _cover_active:
				var tucked_yaw := atan2(-_cover_normal.x,-_cover_normal.z)
				yaw = lerp_angle(tucked_yaw,yaw,smoothstep(0.0,1.0,_cover_lean.length()))
			global_basis = Basis(Vector3.UP,yaw)
	# These nodes are rotation-only. Repeated Euler setters preserve extracted
	# scale and accumulate float drift until weapon/foot slerps cease to be rotations.
	_model.basis = Basis(Vector3.UP,PI+STANCE_YAW*archery)
	_model.position = Vector3.ZERO
	var clip := ("Sword_Idle" if sword_index == 2 else "Sword_Idle_OneHand") if weapon == "sword" else "Idle_Loop"
	var time := fposmod(_motion_time,_player.get_animation(clip).length)
	if _roll_progress >= 0.0:
		clip = "Roll"
		time = clampf(_roll_progress,0,1)*_player.get_animation(clip).length
	elif phase == "MELEE":
		clip = str(_melee_clip().name)
		time = _melee_clip_time()
	elif drawing:
		time = 0.0
	elif guarding:
		clip = "Sword_Idle"
		time = fposmod(_motion_time,_player.get_animation(clip).length)
	elif not _grounded:
		clip = "Jump_Start" if _air_time < 0.15 else "Jump_Loop"
		time = _air_time/0.15*_player.get_animation(clip).length if _air_time < 0.15 else fposmod(_air_time,_player.get_animation(clip).length)
	elif _landing_weight > 0.0 and not moving and not sliding:
		clip = "Jump_Land"
		time = (1.0-_landing_weight)*_player.get_animation(clip).length
	elif moving:
		clip = _locomotion_clip(speed)
		time = _locomotion_clip_time(clip)
	if clip != _display_clip or lower_clip != _display_lower_clip or weapon != _display_weapon or drawing != _display_drawing:
		for bone in skeleton.get_bone_count():
			_blend_pose[bone] = _authored_pose[bone]
		_blend_time = 0.0
		_display_clip = clip
		_display_lower_clip = lower_clip
		_display_weapon = weapon
		_display_drawing = drawing
	var crouching := _crouch_amount > 0.0 and _roll_progress < 0.0
	var leaning := _cover_active and not _cover_lean.is_zero_approx() and _roll_progress < 0.0
	if leaning:
		_sample_cover_lean()
	if crouching:
		var crouch_moving := moving or (sliding and slide_progress < 0.0 and speed > 0.1)
		var crouch_clip := str(_profile.clips.crouch_forward.name if crouch_moving else _profile.clips.crouch_idle.name)
		var crouch_time := _locomotion_clip_time(crouch_clip) if crouch_moving else fposmod(_motion_time,_player.get_animation(crouch_clip).length)
		_sample_clip(crouch_clip,crouch_time)
		var slide_blend := smoothstep(0.0,1.0,_slide_weight)
		for bone in skeleton.get_bone_count():
			var pose := skeleton.get_bone_pose(bone)
			_crouch_pose[bone] = pose.interpolate_with(_slide_crouch_pose[bone],slide_blend) if sliding else pose
	if arm_overlay:
		_sample_clip("Sword_Idle",fposmod(_motion_time,_player.get_animation("Sword_Idle").length))
		for index in _guard_bones.size():
			_guard_pose[index] = skeleton.get_bone_pose(_guard_bones[index])
	if layer_lower_body:
		var lower_time := _locomotion_clip_time(lower_clip) if moving else (1.0-_landing_weight)*_player.get_animation(lower_clip).length
		_sample_clip(lower_clip,lower_time)
		for index in _leg_bones.size():
			_lower_pose[index] = skeleton.get_bone_pose(_leg_bones[index])
	_sample_clip(clip,time)
	if layer_lower_body:
		for index in _leg_bones.size():
			skeleton.set_bone_pose(_leg_bones[index],_lower_pose[index])
	_blend_time = minf(BLEND_SECONDS,_blend_time+delta)
	if _blend_time < BLEND_SECONDS and _roll_progress < 0.0:
		var weight := smoothstep(0.0,BLEND_SECONDS,_blend_time)
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone,_blend_pose[bone].interpolate_with(skeleton.get_bone_pose(bone),weight))
	# Blend authored motion only. Feeding already crouched/IK-corrected bones
	# back into the next transition applies their offsets again on every switch.
	for bone in skeleton.get_bone_count():
		_authored_pose[bone] = skeleton.get_bone_pose(bone)
	if arm_overlay:
		for index in _guard_bones.size():
			skeleton.set_bone_pose(_guard_bones[index],_guard_pose[index])
	if crouching:
		_apply_cover_crouch(drawing or phase == "MELEE" or coupled_carry)
	if moving and action:
		var spine_pose := _bone_world(_bones.spine_01)
		var pelvis := _bone_world(_bones.pelvis)
		var travel := atan2(-_velocity.x,-_velocity.z)-global_rotation.y-STANCE_YAW*archery
		pelvis.basis = Basis(Vector3.UP,travel)*pelvis.basis
		_set_bone_world(_bones.pelvis,pelvis)
		var corrected_spine := _bone_world(_bones.spine_01)
		corrected_spine.basis = spine_pose.basis
		_set_bone_world(_bones.spine_01,corrected_spine)
	if leaning:
		_apply_cover_lean()
	if _grounded and _roll_progress < 0.0:
		if drawing and not moving:
			_plant_archery_feet(archery*(1.0-_slide_weight) if sliding else archery)
		if sliding:
			_apply_slide_pose(drawing or phase == "MELEE" or coupled_carry)
		_place_feet()
	if drawing:
		var head := _bone_world(_bones.Head)
		head.basis = Basis(Vector3.UP,-STANCE_YAW*archery)*head.basis
		_set_bone_world(_bones.Head,head)
	if weapon == "bow":
		_update_bow_pose(drawing)
	else:
		_update_hand_contacts()
		active_sword.global_transform = _bone_world(_arms[1][2]) * _sword_grip
	var chest_pose := global_transform.affine_inverse()*_bone_world(_bones.spine_03)
	_chest.transform = Transform3D(chest_pose.basis*_chest_rest_basis.inverse(),chest_pose.origin)

func _apply_cover_crouch(lower_only: bool) -> void:
	# Authored crouch steps replace standing strides; aim and sword grips keep their upper-body pose.
	if lower_only:
		for bone in _leg_bones:
			skeleton.set_bone_pose(bone,skeleton.get_bone_pose(bone).interpolate_with(_crouch_pose[bone],_crouch_amount))
	else:
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone,skeleton.get_bone_pose(bone).interpolate_with(_crouch_pose[bone],_crouch_amount))
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.origin.y -= _crouch_lowering*_crouch_amount
	_set_bone_world(_bones.pelvis,pelvis)
	_solve_limb(_legs[0],left.origin,left.basis)
	_solve_limb(_legs[1],right.origin,right.basis)

func _apply_slide_pose(lower_only: bool) -> void:
	# Slide offsets are measured against the imported leg chains. Only fixed-length
	# limb rotations follow the targets; physical crouch remains owned by CoverMovement.
	var weight := smoothstep(0.0,1.0,_slide_weight)*_crouch_amount
	if weight <= 0.0:
		return
	var stance := Basis(Vector3.UP,atan2(-_slide_direction.x,-_slide_direction.z))
	var spine := _bone_world(_bones.spine_01)
	var pelvis := _bone_world(_bones.pelvis)
	var travel := atan2(-_slide_direction.x,-_slide_direction.z)-global_rotation.y-STANCE_YAW*_archery_weight()
	pelvis.basis = Basis(Vector3.UP,wrapf(travel,-PI,PI)*weight)*pelvis.basis
	var leg_length := (_leg_lengths.x+_leg_lengths.y)*0.5
	pelvis.origin += (stance.z*0.08-Vector3.UP*0.08)*leg_length*weight
	_set_bone_world(_bones.pelvis,pelvis)
	var corrected_spine := _bone_world(_bones.spine_01)
	# Keep action/guard orientation and both grips intact; ready stance leans back
	# slightly over the tucked trailing knee instead of pitching the whole mesh.
	corrected_spine.basis = spine.basis if lower_only else Basis(stance.x,0.16*weight)*spine.basis
	_set_bone_world(_bones.spine_01,corrected_spine)
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var foot := _bone_world(_legs[side][2])
		var reach := 0.70 if side == 0 else -0.22
		var target := global_position+stance*Vector3(sign_x*0.19*_leg_lengths[side],_foot_height[side],-reach*_leg_lengths[side])
		var rest_basis := stance*Basis(Vector3.UP,PI)*skeleton.get_bone_global_rest(_legs[side][2]).basis
		if side == 0:
			rest_basis = Basis(stance.x,0.14)*rest_basis
		var pole := stance*Vector3(sign_x*0.18,0.25,-1.0)
		_solve_limb(_legs[side],foot.origin.lerp(target,weight),foot.basis.slerp(rest_basis,weight),pole)

func _sample_cover_lean() -> void:
	var clip: Dictionary = _profile.clips.cover_top
	if _cover_lean.y <= 0.0:
		clip = _profile.clips.cover_left if _cover_lean.dot(_cover_normal.cross(Vector3.UP)) > 0.0 else _profile.clips.cover_right
	_sample_clip(str(clip.name),clampf(_cover_lean.length(),0.0,1.0)*float(clip.duration))
	var parent_turn := Basis.IDENTITY
	for index in _cover_bones.size():
		var pose := skeleton.get_bone_global_pose(_cover_bones[index])
		var turn := pose.basis*_cover_neutral[index].basis.inverse()
		_cover_turns[index] = turn*parent_turn.inverse()
		parent_turn = turn
	_cover_shift = skeleton.get_bone_global_pose(_bones.pelvis).origin-_cover_neutral[0].origin

func _apply_cover_lean() -> void:
	# Keep the authored lean in the cover frame, even when an attack turns toward the crosshair.
	var cover_basis := Basis(Vector3.UP,atan2(-_cover_normal.x,-_cover_normal.z))
	var inverse := cover_basis.inverse()
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	for index in _cover_bones.size():
		var bone := _cover_bones[index]
		var pose := _bone_world(bone)
		pose.basis = cover_basis*_cover_turns[index]*inverse*pose.basis
		if index == 0:
			pose.origin += cover_basis*_cover_shift
		_set_bone_world(bone,pose)
	_solve_limb(_legs[0],left.origin,left.basis)
	_solve_limb(_legs[1],right.origin,right.basis)

func _update_hand_contacts() -> void:
	var left := _bone_world(_arms[0][2])
	var right := _bone_world(_arms[1][2])
	bow_hand.global_transform = Transform3D(left.basis,left*_palm_left)
	string_hand.global_transform = Transform3D(right.basis,right*_palm_right)

func _update_bow_pose(drawing: bool) -> void:
	var left := _bone_world(_arms[0][2])
	var right := _bone_world(_arms[1][2])
	var carry_grip: Vector3 = left*_palm_left
	var carry_contact: Vector3 = right*_palm_right
	var bow_basis := left.basis*_bow_grip_basis
	var grip := carry_grip
	var contact := carry_contact
	var right_basis := right.basis
	if drawing:
		var shoulder := _bone_world(_arms[1][0]).origin
		var body_right := shoulder-_bone_world(_arms[0][0]).origin
		body_right.y = 0.0
		body_right = body_right.normalized()
		var body_forward := Vector3.UP.cross(body_right).normalized()
		var chest := _bone_world(_bones.spine_03).origin
		var shoulder_gate := shoulder+body_right*0.16+Vector3.UP*0.28-body_forward*0.03
		var front_gate := shoulder+body_forward*0.32+body_right*0.12+Vector3.UP*0.10
		var anchor := _jaw_anchor()
		var offset := _aim_point-anchor
		var elevation := clampf(atan2(offset.y,maxf(Vector2(offset.x,offset.z).length(),0.001)),-MAX_ELEVATION,MAX_ELEVATION)
		var aim_yaw := atan2(-offset.x,-offset.z)
		if _cover_active:
			aim_yaw = lerp_angle(atan2(-_cover_normal.x,-_cover_normal.z),aim_yaw,smoothstep(0.0,1.0,_cover_lean.length()))
		var aim_basis := Basis(Vector3.UP,aim_yaw)*Basis(Vector3.RIGHT,elevation)
		var weight := _archery_weight()
		# Push the bow out while pulling the string back; a fully extended bow
		# at zero tension puts its brace point beyond the drawing arm's reach.
		var grip_distance := lerpf(Bow.BRACE_DISTANCE+0.12,Bow.DRAW_DISTANCE,draw_amount)
		grip = carry_grip.lerp(anchor-aim_basis.z*grip_distance,weight)
		bow_basis = bow_basis.slerp(aim_basis,weight)
		if phase == "RELEASE":
			grip = to_global(_release_grip)
			bow_basis = global_basis*Basis(_release_bow_rotation)
		elif phase == "RECOVER":
			# Load in front of the centreline, within both arms' reach. A far-left
			# target straightens the right elbow and drives its forearm through the chest.
			var nocking_grip := chest+body_right*0.04+body_forward*0.46-Vector3.UP*0.05
			var nocking_basis := Basis.looking_at(body_forward,Vector3.UP)
			var lower := smoothstep(0.18,0.40,_phase_time)
			var relax := smoothstep(0.72,RECOVER_SECONDS,_phase_time)
			grip = to_global(_release_grip).lerp(nocking_grip,lower).lerp(carry_grip,relax)
			bow_basis = (global_basis*Basis(_release_bow_rotation)).slerp(nocking_basis,lower).slerp(bow_basis,relax)
		var left_basis := bow_basis*_bow_grip_basis.inverse()
		_solve_limb(_arms[0],grip-left_basis*_palm_left,left_basis,-body_right*0.60+body_forward*0.40-Vector3.UP*0.20)
		left = _bone_world(_arms[0][2])
		active_bow.global_transform = Transform3D(bow_basis,left*_palm_left)
		active_bow.set_draw(draw_amount)
		right_basis = bow_basis*_string_grip_basis.inverse()
		contact = active_bow.get_nock_position()
		var draw_reach := 1.0
		if phase == "DRAWING":
			draw_reach = smoothstep(0.03,RAISE_SECONDS,_phase_time)
			var hip_gate := chest+body_forward*0.35+body_right*0.28-Vector3.UP*0.20
			contact = _hand_arc(carry_contact,hip_gate,front_gate,contact,draw_reach)
			right_basis = right.basis.slerp(right_basis,draw_reach)
		elif phase in ["RELEASE","RECOVER"]:
			var follow := smoothstep(0.0,RELEASE_SECONDS,_phase_time) if phase == "RELEASE" else 1.0
			contact = to_global(_release_contact)+global_basis*Basis(_release_bow_rotation).z*(0.12*follow*_release_raise*_release_charge)
			if phase == "RECOVER":
				var quiver_top := _quiver.to_global(Vector3(0,0.29,0))
				if _phase_time < 0.40:
					contact = _hand_arc(contact,shoulder_gate,shoulder_gate,quiver_top,smoothstep(0.03,0.40,_phase_time))
				elif _phase_time < 0.68:
					contact = _hand_arc(quiver_top,shoulder_gate,front_gate,active_bow.get_nock_position(),smoothstep(0.40,0.68,_phase_time))
				else:
					var relax := smoothstep(0.72,RECOVER_SECONDS,_phase_time)
					var hip_gate := chest+body_forward*0.35+body_right*0.28-Vector3.UP*0.20
					contact = _hand_arc(active_bow.get_nock_position(),hip_gate,hip_gate,carry_contact,relax)
					right_basis = right_basis.slerp(right.basis,relax)
		var elbow_pole := body_right*0.65+body_forward*0.40+Vector3.UP*0.12
		if phase == "DRAWING":
			elbow_pole = (_bone_world(_arms[1][1]).origin-shoulder).lerp(elbow_pole,draw_reach)
		_solve_limb(_arms[1],contact-right_basis*_palm_right,right_basis,elbow_pole)
	else:
		active_bow.global_transform = Transform3D(bow_basis,grip)
		active_bow.set_draw(0.0)
	active_bow.set_arrow_visible(_roll_progress < 0.0 and (phase in ["READY","DRAWING","HOLDING"] or (phase == "RECOVER" and _phase_time >= 0.68)))
	_update_hand_contacts()

func _jaw_anchor() -> Vector3:
	return _bone_world(_jaw_bone)*_jaw_offset

func _hand_arc(start: Vector3, control_a: Vector3, control_b: Vector3, finish: Vector3, t: float) -> Vector3:
	var u := 1.0-t
	return start*(u*u*u)+control_a*(3.0*u*u*t)+control_b*(3.0*u*t*t)+finish*(t*t*t)

func _bone_world(index: int) -> Transform3D:
	return skeleton.global_transform*skeleton.get_bone_global_pose(index)

func _set_bone_world(index: int, pose: Transform3D) -> void:
	skeleton.set_bone_global_pose(index,skeleton.global_transform.affine_inverse()*pose)

func _solve_limb(chain: PackedInt32Array, target: Vector3, endpoint_basis: Basis, pole: Vector3 = Vector3.ZERO) -> void:
	var upper := _bone_world(chain[0])
	var lower := _bone_world(chain[1])
	var end := _bone_world(chain[2])
	var upper_length := upper.origin.distance_to(lower.origin)
	var lower_length := lower.origin.distance_to(end.origin)
	var offset := target-upper.origin
	var axis := offset.normalized() if offset.length_squared() > 0.000001 else Vector3.DOWN
	var distance := clampf(offset.length(),absf(upper_length-lower_length)+0.001,upper_length+lower_length-0.001)
	var bend := lower.origin-upper.origin if pole.is_zero_approx() else pole
	bend -= axis*bend.dot(axis)
	if bend.length_squared() < 0.000001:
		bend = upper.basis.z-axis*upper.basis.z.dot(axis)
	bend = bend.normalized()
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2.0*distance)
	var elbow := upper.origin+axis*along+bend*sqrt(maxf(0.0,upper_length*upper_length-along*along))
	var wrist := upper.origin+axis*distance
	# Rotate the authored bone frames; never invent a replacement twist basis or scale a bone.
	var upper_turn := Basis(Quaternion((lower.origin-upper.origin).normalized(),(elbow-upper.origin).normalized()))
	var lower_turn := Basis(Quaternion((end.origin-lower.origin).normalized(),(wrist-elbow).normalized()))
	_set_bone_world(chain[0],Transform3D(upper_turn*upper.basis,upper.origin))
	_set_bone_world(chain[1],Transform3D(lower_turn*lower.basis,elbow))
	_set_bone_world(chain[2],Transform3D(endpoint_basis,wrist))

func _plant_archery_feet(weight: float) -> void:
	var stance := global_basis*Basis(Vector3.UP,STANCE_YAW*weight)
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var foot := _bone_world(_legs[side][2])
		var planted := global_position+stance*Vector3(sign_x*0.18,_foot_height[side],0.0)
		var basis := skeleton.global_basis*skeleton.get_bone_global_rest(_legs[side][2]).basis
		_solve_limb(_legs[side],foot.origin.lerp(planted,weight),foot.basis.slerp(basis,weight),stance*Vector3(sign_x*0.08,0,-1))

func _place_feet() -> void:
	if not _ground_sampler.is_valid():
		return
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	var floors := Vector2(float(_ground_sampler.call(left.origin)),float(_ground_sampler.call(right.origin)))
	var base_floor := minf(floors.x,floors.y)
	_model.position.y = clampf(base_floor-global_position.y,-0.4,0.4)
	for side in 2:
		var foot := _bone_world(_legs[side][2])
		var ankle := foot.origin+Vector3.UP*(floors[side]-base_floor)
		var toe := foot.origin-global_basis.z*0.15
		var edge := foot.origin+global_basis.x*0.08
		var forward := -global_basis.z*0.15+Vector3.UP*(float(_ground_sampler.call(toe))-floors[side])
		var across := global_basis.x*0.08+Vector3.UP*(float(_ground_sampler.call(edge))-floors[side])
		var normal := across.cross(forward).normalized()
		# Terrain adds slope; do not erase authored heel lift or toe push-off.
		var basis := Basis(Quaternion(Vector3.UP,normal))*foot.basis
		_solve_limb(_legs[side],ankle,basis)
