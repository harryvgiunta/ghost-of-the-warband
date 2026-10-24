extends Node3D
## Imported humanoid animation, with skeletal aim/terrain corrections and real blade samples.

signal arrow_released(origin: Vector3, direction: Vector3, speed: float, charge: float)
signal weapon_thrown(origin: Vector3, direction: Vector3, speed: float, charge: float, weapon: String, weapon_index: int)
signal loadout_changed()
signal melee_started(hand: String)
signal melee_sweep(hand: String, previous_base: Vector3, previous_tip: Vector3, current_base: Vector3, current_tip: Vector3, radius: float)

const Geo = preload("res://scripts/geo.gd")
const Bow = preload("res://scripts/bow.gd")
const Sword = preload("res://scripts/sword.gd")
const Dagger = preload("res://scripts/dagger.gd")
const Shield = preload("res://scripts/shield.gd")
const Staff = preload("res://scripts/staff.gd")
const FocusItem = preload("res://scripts/focus_item.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const CHARACTER = preload("res://assets/characters/ironwood_ranger.glb")
const BOW_DATA = [
	{"name":"Shortbow", "subtitle":"Quick ashwood scout bow", "draw_seconds":1.0, "speed":66.0, "length":1.0},
	{"name":"Recurve", "subtitle":"Balanced horn-and-yew recurve", "draw_seconds":2.0, "speed":84.0, "length":1.4},
	{"name":"Longbow", "subtitle":"Heavy heartwood war bow", "draw_seconds":3.0, "speed":102.0, "length":1.8},
]
const SWORD_DATA = [
	{"name":"Shortsword", "seconds":1.0, "length":0.80, "reach":1.8, "damage":30.0, "throw_speed":26.0},
	{"name":"Arming sword", "seconds":2.0, "length":1.05, "reach":2.1, "damage":38.0, "throw_speed":28.0},
	{"name":"Greatsword", "seconds":3.0, "length":1.40, "reach":2.5, "damage":50.0, "throw_speed":24.0},
]
const DAGGER_DATA = {"name":"Dagger", "seconds":0.5, "length":0.34, "reach":1.2, "damage":14.0, "throw_speed":30.0}
const CONSUMABLE_DATA = {
	"bandage": {"name":"Bandage", "seconds":3.0, "heal":35.0, "heal_seconds":3.0, "clip":"Bandage_Wrap", "phase":"BANDAGE"},
	"potion": {"name":"Healing potion", "seconds":0.5, "heal":50.0, "heal_seconds":0.0, "clip":"Potion_Drink", "phase":"DRINK"},
}
## Two-handed staves reuse the greatsword combat profile; only the visible
## shaft endpoints differ, so blade sweeps follow the real staff length.
const STAFF_DATA = [
	{"name":"Ember staff", "length":1.75},
	{"name":"Bone staff", "length":1.60},
]
## Horizontal cut profiles, one row per sword size (shortsword, arming sword,
## greatsword). Angles are radians relative to the crosshair: `load` cocks the
## hands back over the striking side, `cross` carries them past the opposite
## side, and the torso winds `body_load` then follows through `body_cross`. The
## blade points out from the swing centre (plus `lag`), which is what makes the
## tip sweep a real arc instead of a narrow forward band.
const HORIZONTAL_SWING = [
	{"load":1.02, "cross":1.16, "body_load":0.30, "body_cross":0.52,
		"radius_load":0.28, "radius_cross":0.46, "lag_load":0.30, "lag_cross":-0.24,
		"height":-0.12, "bias":0.06},
	{"load":1.20, "cross":1.38, "body_load":0.38, "body_cross":0.66,
		"radius_load":0.30, "radius_cross":0.47, "lag_load":0.40, "lag_cross":-0.30,
		"height":-0.10, "bias":0.09},
	{"load":1.42, "cross":1.66, "body_load":0.46, "body_cross":0.92,
		"radius_load":0.26, "radius_cross":0.44, "lag_load":0.52, "lag_cross":-0.44,
		"height":-0.08, "bias":0.12},
]
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
var armor_pieces := {"head":0, "chest":0, "hands":0, "legs":0, "feet":0}
var weapon := "bow"
## The paperdoll main-hand category. Empty hands cannot be dual-wielded; a bow
## or dagger may still hand the session back to the selected one-handed sword.
var main_hand_kind := "sword"
var phase := "READY"
var draw_amount := 0.0
var charge_frozen := false
var bow_hand: Node3D
var string_hand: Node3D
var active_bow: Bow
var active_sword: Node3D
var active_dagger: Node3D
var active_shield
var shield_equipped := false
var shield_variant := 1
var consumable_kind := ""
var _bandage_prop: Node3D
var _potion_prop: Node3D
var active_staff: Node3D
var active_off_weapon: Node3D
var active_focus: Node3D
var staff_index := 0
var staff_active := false
## The off hand defaults to the dagger so the established dual-wield mode keeps
## its visible left-hand weapon until a loadout replaces it.
var off_weapon_kind := "dagger"
var off_weapon_index := 0
var off_weapon_active := true
var focus_kind := ""
var focus_index := 0
var focus_active := false
var skeleton: Skeleton3D
var _phase_time := 0.0
var _roll_progress := -1.0
var slide_progress := -1.0
var _slide_direction := Vector3.FORWARD
var _slide_weight := 0.0
var _velocity := Vector3.ZERO
var _grounded := true
var _cover_active := false
var _blocking := false
var _block_forward := Vector3.FORWARD
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
var last_arrow_visual_origin := Vector3.ZERO
var _model: Node3D
var _player: AnimationPlayer
var _bows: Array[Bow] = []
var _swords: Array[Node3D] = []
var _off_swords: Array[Node3D] = []
var _staffs: Array[Node3D] = []
var _focus_items: Dictionary = {}
var _armor_meshes: Dictionary = {}
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
var _sword_grip_left := Transform3D.IDENTITY
var _melee_hand := "right"
var _right_variant := "overhead"
var _left_melee_time := -1.0
var _right_melee_time := -1.0
var _left_melee_duration := float(DAGGER_DATA.seconds)
var _right_melee_duration := 1.0
var _swing_start_hand := Transform3D.IDENTITY
var _swing_start_support := Transform3D.IDENTITY
var _swing_start_hand_chest := Transform3D.IDENTITY
var _swing_start_support_chest := Transform3D.IDENTITY
var _swing_start_valid := false
var _step_progress := -1.0
var _step_direction := Vector3.RIGHT
var _step_facing_hold := 0.0
var _hit_react := 0.0
var _neutral_right_arm: Dictionary = {}
var _offhand_offset := Vector3(0.03,-0.23,0.28)
var _offhand_weapon_basis := Basis.IDENTITY
var _offhand_pole := Vector3(0.40,-0.20,0.50)
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
	_sword_grip_left = _mirror_transform(_sword_grip)
	_offhand_weapon_basis = Basis.looking_at(Vector3(0.0,-0.25,1.0).normalized(),Vector3.UP)
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
	for bone_name in ["clavicle_r","upperarm_r","lowerarm_r","hand_r"]:
		_neutral_right_arm[int(_bones[bone_name])] = skeleton.get_bone_pose(int(_bones[bone_name]))
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
	var dagger := Dagger.new()
	dagger.blade_length = float(DAGGER_DATA.length)
	add_child(dagger)
	dagger.visible = false
	var shield := Shield.new()
	shield.name = "Shield"
	add_child(shield)
	active_shield = shield
	active_bow = _bows[bow_index]
	active_sword = _swords[sword_index]
	active_dagger = dagger
	_build_weapon_visuals()
	active_off_weapon = active_dagger
	active_staff = _staffs[0]
	if off_weapon_active and off_weapon_kind != "dagger":
		active_off_weapon = _off_weapon_mesh()
	if staff_active:
		active_staff = _staffs[staff_index]
	if focus_active:
		active_focus = _focus_items.get(focus_kind,null)
	_build_equipment()
	_build_consumable_props()
	_built = true
	set_bow(bow_index)
	set_sword(sword_index)
	_apply_armor_visibility()
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

func _mirror_transform(value: Transform3D) -> Transform3D:
	# The imported skeleton's left side is the exact X mirror of its right side.
	var mirror := Basis(Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,0,1))
	return Transform3D(mirror*value.basis*mirror,mirror*value.origin)

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
	_build_armor_meshes()

func _build_consumable_props() -> void:
	var cloth := Geo.material(Color("ddd6c2"))
	var cloth_edge := Geo.material(Color("b7ad92"))
	_bandage_prop = Node3D.new()
	_bandage_prop.name = "BandageRoll"
	_bandage_prop.visible = false
	add_child(_bandage_prop)
	Geo.cylinder(_bandage_prop,0.036,0.036,0.105,Vector3.ZERO,cloth,12)
	Geo.cylinder(_bandage_prop,0.038,0.038,0.012,Vector3(0,0.049,0),cloth_edge,12)
	Geo.box(_bandage_prop,Vector3(0.085,0.003,0.19),Vector3(0,-0.018,0.09),cloth)
	Geo.sphere(_bandage_prop,0.038,Vector3(0,-0.052,0),cloth,Vector3(1.0,0.6,1.0))
	var glass := Geo.material(Color(0.42,0.68,0.64,0.75),0.2,0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var liquid := Geo.material(Color("b73f45"),0.1,0.45)
	var cork := Geo.material(Color("a8814f"))
	_potion_prop = Node3D.new()
	_potion_prop.name = "HealingPotion"
	_potion_prop.visible = false
	add_child(_potion_prop)
	Geo.cylinder(_potion_prop,0.033,0.033,0.085,Vector3(0,0.042,0),liquid,12)
	Geo.cylinder(_potion_prop,0.036,0.030,0.125,Vector3(0,0.062,0),glass,12)
	Geo.cylinder(_potion_prop,0.017,0.017,0.045,Vector3(0,0.145,0),glass,10)
	Geo.cylinder(_potion_prop,0.020,0.020,0.022,Vector3(0,0.176,0),cork,10)
	Geo.sphere(_potion_prop,0.018,Vector3(0,0.09,0),liquid)
	_update_consumable_props()

func begin_consumable(kind: String) -> bool:
	if not CONSUMABLE_DATA.has(kind):
		return false
	if phase != "READY" or _roll_progress >= 0.0 or is_melee():
		return false
	consumable_kind = kind
	phase = str(CONSUMABLE_DATA[kind].phase)
	_phase_time = 0.0
	draw_amount = 0.0
	charge_frozen = false
	_blocking = false
	_update_pose(0.0)
	return true

func end_consumable() -> void:
	if phase not in ["BANDAGE","DRINK"]:
		return
	phase = "READY"
	_phase_time = 0.0
	consumable_kind = ""
	_update_pose(0.0)

func cancel_consumable() -> void:
	if phase in ["BANDAGE","DRINK"]:
		end_consumable()

func is_consuming() -> bool:
	return phase in ["BANDAGE","DRINK"]

func _update_consumable_props() -> void:
	if _bandage_prop == null or _potion_prop == null:
		return
	var consuming := is_consuming()
	_bandage_prop.visible = consuming and consumable_kind == "bandage"
	_potion_prop.visible = consuming and consumable_kind == "potion"
	if not consuming:
		return
	var socket := _bone_world(_arms[1][2]) * _sword_grip
	var prop := _bandage_prop if consumable_kind == "bandage" else _potion_prop
	prop.global_transform = Transform3D(socket.basis * Basis(Vector3.RIGHT,PI*0.5),socket.origin)

func _build_weapon_visuals() -> void:
	# Off-hand 1H swords are separate meshes from the main-hand set so both
	# hands can show the same sword size at once.
	for index in 2:
		var off := Sword.new()
		off.sword_kind = index
		off.blade_length = float(SWORD_DATA[index].length)
		add_child(off)
		off.visible = false
		_off_swords.append(off)
	for index in STAFF_DATA.size():
		var staff := Staff.new()
		staff.staff_kind = index
		staff.blade_length = float(STAFF_DATA[index].length)
		add_child(staff)
		staff.visible = false
		_staffs.append(staff)
	for kind in ["tome", "skull"]:
		var focus := FocusItem.new()
		focus.focus_kind = kind
		add_child(focus)
		focus.visible = false
		_focus_items[kind] = focus

func set_bow(index: int) -> void:
	cancel_consumable()
	bow_index = clampi(index,0,2)
	if not _built:
		return
	active_bow = _bows[bow_index]
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_sword(index: int) -> void:
	cancel_consumable()
	if is_melee():
		_clear_melee()
		phase = "READY"
		_phase_time = 0.0
	# Selecting a sword is the session hand-off away from a staff. The persistent
	# loadout re-activates the staff after this call.
	staff_active = false
	sword_index = clampi(index,0,2)
	if weapon == "dual" and sword_index == 2:
		# The greatsword needs both hands; fall back to the one-handed sword mode.
		weapon = "sword"
	if shield_equipped and not can_equip_shield():
		shield_equipped = false
		_blocking = false
	if not _built:
		return
	active_sword = _swords[sword_index]
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_weapon(value: String) -> bool:
	cancel_consumable()
	if value not in ["bow","sword","dagger","dual","none"]:
		return false
	if value != "dual":
		main_hand_kind = value
	if value == "dual" and shield_equipped and off_weapon_active:
		# A raised shield is stowed when a legal off-hand weapon enters dual.
		shield_equipped = false
		_blocking = false
	if value == "dual" and not _dual_ready():
		return false
	if value == weapon:
		# Pressing the sword key while a staff supplies this same "sword" mode
		# must still hand the session back to the actual sword.
		if value == "sword" and staff_active:
			staff_active = false
			_sync_weapon_visibility()
			_update_pose(0.0)
		return true
	_clear_melee()
	if phase not in ["RELEASE","RECOVER","T_RELEASE","T_RECOVER"]:
		phase = "READY"
		_phase_time = 0.0
		draw_amount = 0.0
	_melee_hand = "right"
	_blocking = false
	weapon = value
	if shield_equipped and not can_equip_shield():
		shield_equipped = false
	set_bow(bow_index)
	set_sword(sword_index)
	_sync_weapon_visibility()
	return true

func apply_loadout(loadout: Dictionary) -> void:
	# Session hand-off from PlayerState.loadout(): armor, main mode, off item
	# and the matching pose. Pure presentation; every setter keeps its own
	# legality checks, so a malformed dict degrades instead of crashing.
	var mode := str(loadout.get("weapon",""))
	var staff_value := int(loadout.get("staff",-1))
	var bow_value := int(loadout.get("bow",0))
	var sword_value := int(loadout.get("sword",0))
	var off_id := str(loadout.get("off",""))
	var shield_on := bool(loadout.get("shield",false))
	set_armor_pieces(loadout.get("armor",{}))
	set_staff(0,false)
	set_off_focus("",0,false)
	set_off_weapon("",0,false)
	set_shield(false)
	set_bow(bow_value)
	set_sword(sword_value)
	var focus: Dictionary = loadout.get("focus",{})
	if focus.has("kind"):
		set_off_focus(str(focus.get("kind","")),int(focus.get("index",0)),true)
	var off_weapon: Dictionary = loadout.get("off_weapon",{})
	if off_weapon.has("kind"):
		set_off_weapon(str(off_weapon.get("kind","")),int(off_weapon.get("index",0)),true)
	if shield_on:
		set_shield_variant(_shield_variant_for(off_id))
	var dual_ready := sword_value <= 1 and staff_value < 0 and not focus_active \
		and off_weapon_active and off_weapon_kind in ["dagger","sword"]
	match mode:
		"bow":
			set_weapon("bow")
			set_sword(0)
		"dagger":
			set_weapon("dagger")
			set_sword(0)
		"sword":
			set_weapon("sword")
			if dual_ready:
				set_weapon("dual")
		"dual":
			set_weapon("sword")
			set_weapon("dual")
		_:
			set_weapon("none")
	if shield_on:
		set_shield(true)
	# Activate the staff after the mode selection: set_sword() intentionally
	# stows a staff, and a fresh loadout must be able to replace that session
	# hand-off with the paperdoll's main-hand staff.
	if staff_value >= 0:
		set_staff(staff_value,true)
	_update_pose(0.0)
	_sync_weapon_visibility()

func set_staff(index: int, active: bool) -> void:
	staff_index = clampi(index,0,STAFF_DATA.size()-1)
	staff_active = active
	active_staff = _staffs[staff_index] if not _staffs.is_empty() else null
	if not _built:
		return
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_off_weapon(kind: String, index: int, active: bool) -> void:
	off_weapon_kind = kind if kind in ["dagger","sword"] else ""
	off_weapon_index = clampi(index,0,1)
	off_weapon_active = active and not off_weapon_kind.is_empty()
	active_off_weapon = _off_weapon_mesh()
	if weapon == "dual" and not _dual_ready():
		_clear_melee()
		weapon = "sword"
		_sync_primary_hand()
	if not _built:
		return
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_off_focus(kind: String, index: int, active: bool) -> void:
	focus_kind = kind if kind in ["tome","skull"] else ""
	focus_index = clampi(index,0,1)
	focus_active = active and not focus_kind.is_empty()
	active_focus = _focus_items.get(focus_kind,null) if focus_active else null
	if focus_active and weapon == "dual":
		_clear_melee()
		weapon = "sword"
		_sync_primary_hand()
	if not _built:
		return
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()

func set_shield_variant(index: int) -> void:
	shield_variant = clampi(index,0,2)
	if active_shield != null and active_shield.has_method("set_variant"):
		active_shield.set_variant(shield_variant)
	if not _built:
		return
	_update_pose(0.0)

func _shield_variant_for(item_id: String) -> int:
	match item_id:
		"shield_buckler":
			return 0
		"shield_tower":
			return 2
	return 1

func _off_weapon_mesh() -> Node3D:
	if not off_weapon_active:
		return null
	if off_weapon_kind == "sword":
		return _off_swords[off_weapon_index] if _off_swords.size() > off_weapon_index else null
	if off_weapon_kind == "dagger":
		return active_dagger
	return null

func _dual_ready() -> bool:
	return main_hand_kind != "none" and sword_index <= 1 and staff_active == false \
		and not focus_active and not shield_equipped \
		and off_weapon_active and off_weapon_kind in ["dagger","sword"]

func _staff_shown() -> bool:
	return staff_active and weapon == "sword"

func _off_profile() -> Dictionary:
	if off_weapon_kind == "sword":
		return SWORD_DATA[off_weapon_index]
	return DAGGER_DATA

func _left_blade_node() -> Node3D:
	if active_off_weapon != null:
		return active_off_weapon
	return active_dagger

func _focus_supported() -> bool:
	# A held focus is a two-slot loadout: one-handed main, nothing blocking or
	# dual-wielded, and no action pose that owns the left arm.
	if weapon not in ["sword","dagger"] or sword_index > 1:
		return false
	if shield_equipped or staff_active or _roll_progress >= 0.0:
		return false
	return phase not in ["DRAWING","HOLDING","RELEASE","RECOVER"]

func _sync_weapon_visibility() -> void:
	# A thrown weapon leaves the hand for its release frame, then the endless
	# supply restores the same equipped weapon as the recovery begins.
	var hidden := phase == "T_RELEASE"
	var consuming := is_consuming()
	var staff_shown := _staff_shown()
	var left_shown := weapon == "dual" and off_weapon_active and off_weapon_kind in ["dagger","sword"]
	for i in _swords.size():
		_swords[i].visible = weapon in ["sword","dual"] and i == sword_index and not hidden and not staff_shown and not consuming
	for i in _bows.size():
		_bows[i].visible = weapon == "bow" and i == bow_index and not consuming
	for i in _staffs.size():
		_staffs[i].visible = staff_shown and i == staff_index and not hidden and not consuming
	if active_dagger != null:
		active_dagger.visible = ((weapon == "dagger" and not hidden) \
			or (left_shown and off_weapon_kind == "dagger")) and not consuming
	for i in _off_swords.size():
		_off_swords[i].visible = left_shown and off_weapon_kind == "sword" and i == off_weapon_index and not consuming
	var focus_shown := focus_active and _focus_supported() and not consuming
	for key: String in _focus_items:
		_focus_items[key].visible = focus_shown and key == focus_kind
	if active_shield != null:
		active_shield.set_active(shield_equipped and not consuming and is_visible_in_tree())

func _build_armor_meshes() -> void:
	# The imported leather outfit is split across the same five slots as the
	# generated shells.  Arrows/head/face/hair stay outside every group.
	var source_slots := {
		"Male_Ranger_Head_Hood": "head",
		"Male_Ranger_Body": "chest",
		"Male_Ranger_Body_Belt_1": "chest",
		"Male_Ranger_Body_Belt_2": "chest",
		"Male_Ranger_Acc_Pauldron": "chest",
		"Male_Ranger_Arms": "chest",
		"Male_Ranger_Arms_Bracer": "hands",
		"Male_Ranger_Legs": "legs",
		"Male_Ranger_Feet_Boots": "feet",
	}
	for slot in ArmorData.SLOTS:
		_armor_meshes[slot] = {}
		for set_index in ArmorData.SET_IDS.size():
			_armor_meshes[slot][set_index] = []
	for node in _model.find_children("*","MeshInstance3D",true,false):
		var mesh_name := str(node.name)
		var slot := str(source_slots.get(mesh_name,""))
		var set_index := 0 if not slot.is_empty() else -1
		if mesh_name.begins_with("Armor_"):
			var parts := mesh_name.split("_")
			if parts.size() >= 3:
				set_index = ArmorData.SET_IDS.find(parts[1].to_lower())
				slot = parts[2].to_lower()
		if set_index >= 0 and _armor_meshes.has(slot):
			_armor_meshes[slot][set_index].append(node)
	var generated: Dictionary = _profile.get("armor",{}).get("generated",{})
	for set_name: String in generated:
		var set_index := ArmorData.SET_IDS.find(set_name)
		if set_index < 0:
			continue
		for slot: String in generated[set_name]:
			if not _armor_meshes.has(slot):
				continue
			for mesh_name: String in generated[set_name][slot]:
				var node := _model.find_child(mesh_name,true,false)
				if node is MeshInstance3D and not _armor_meshes[slot][set_index].has(node):
					_armor_meshes[slot][set_index].append(node)

func _apply_armor_visibility() -> void:
	for slot in ArmorData.SLOTS:
		var active := int(armor_pieces.get(slot,0))
		for set_index: int in _armor_meshes.get(slot,{}):
			for node: Node3D in _armor_meshes[slot][set_index]:
				node.visible = set_index == active

func set_armor_piece(slot: String, set_index: int) -> void:
	cancel_consumable()
	if slot not in ArmorData.SLOTS:
		return
	armor_pieces[slot] = clampi(set_index,0,ArmorData.SET_IDS.size()-1)
	if _built:
		_apply_armor_visibility()
	loadout_changed.emit()

func set_armor_pieces(pieces: Dictionary) -> void:
	cancel_consumable()
	for slot in ArmorData.SLOTS:
		armor_pieces[slot] = clampi(int(pieces.get(slot,0)),0,ArmorData.SET_IDS.size()-1)
	if _built:
		_apply_armor_visibility()
	loadout_changed.emit()

func set_armor(index: int) -> void:
	cancel_consumable()
	# Convenience for tests and whole-set loadouts: every slot uses one set.
	var value := clampi(index,0,ArmorData.SET_IDS.size()-1)
	for slot in ArmorData.SLOTS:
		armor_pieces[slot] = value
	if _built:
		_apply_armor_visibility()
	loadout_changed.emit()

func set_armor_bits(bits: int) -> void:
	set_armor_pieces(ArmorData.unpack(bits & 1023))

func armor_bits() -> int:
	return ArmorData.pack(armor_pieces)

func armor_piece(slot: String) -> int:
	return int(armor_pieces.get(slot,0))

func armor_reduction() -> float:
	return ArmorData.reduction(armor_pieces)

func can_equip_shield() -> bool:
	# Any one-handed sword or the dagger can carry the shield; the 2H
	# greatsword, staff, bow and dual wield still cannot.
	return weapon == "dagger" or (weapon == "sword" and sword_index <= 1)

func set_shield(active: bool) -> bool:
	cancel_consumable()
	var allowed := active and can_equip_shield()
	if shield_equipped == allowed:
		return shield_equipped
	shield_equipped = allowed
	if not allowed:
		_blocking = false
	_sync_weapon_visibility()
	_update_pose(0.0)
	loadout_changed.emit()
	return shield_equipped

func is_melee() -> bool:
	return has_melee("left") or has_melee("right")

func has_melee(hand: String) -> bool:
	return (_left_melee_time >= 0.0) if hand == "left" else (_right_melee_time >= 0.0)

func melee_progress_for(hand: String) -> float:
	var time := _left_melee_time if hand == "left" else _right_melee_time
	if time < 0.0:
		return 1.0
	var duration := _left_melee_duration if hand == "left" else _right_melee_duration
	return clampf(time/maxf(duration,0.001),0.0,1.0)

func _right_phase() -> String:
	match _right_variant:
		"horizontal_left":
			return "MELEE_HL"
		"horizontal_right":
			return "MELEE_HR"
		"stab":
			return "MELEE_ST"
	return "MELEE"

func _sync_primary_hand() -> void:
	if _right_melee_time >= 0.0:
		phase = _right_phase()
		_melee_hand = "right"
		_phase_time = _right_melee_time
	elif _left_melee_time >= 0.0:
		phase = "MELEE_L"
		_melee_hand = "left"
		_phase_time = _left_melee_time
	else:
		phase = "READY"
		_melee_hand = "right"
		_phase_time = 0.0

func _right_duration_for(variant: String) -> float:
	if variant == "stab" or weapon == "dagger":
		return float(DAGGER_DATA.seconds)
	return float(SWORD_DATA[sword_index].seconds)

func _valid_variant(variant: String) -> bool:
	return variant in ["overhead","horizontal_left","horizontal_right","stab"]

func can_begin_melee(hand: String) -> bool:
	if _roll_progress >= 0.0 or is_consuming():
		return false
	if hand == "left":
		if weapon != "dual" or _left_melee_time >= 0.0:
			return false
		return phase == "READY" or (phase.begins_with("MELEE") and phase != "MELEE_L")
	if weapon not in ["sword","dagger","dual"] or _right_melee_time >= 0.0:
		return false
	return phase == "READY" or phase == "MELEE_L"

func begin_melee(hand: String = "right", variant: String = "overhead") -> bool:
	var key := "left" if hand == "left" else "right"
	if not can_begin_melee(key):
		return false
	if key == "left":
		_left_melee_duration = float(_off_profile().seconds)
		_left_melee_time = 0.0
	else:
		var requested := variant if _valid_variant(variant) else "overhead"
		if weapon == "dagger":
			# The dagger's only attack is already a stab; keep its established
			# MELEE presentation phase so HUD and regression contracts stay put.
			requested = "overhead"
		_right_variant = requested
		_right_melee_duration = _right_duration_for(requested)
		_right_melee_time = 0.0
		_swing_start_valid = false
	_sync_primary_hand()
	melee_started.emit(key)
	_update_pose(0.0)
	return true

func abort_melee(hand: String) -> void:
	if hand == "left":
		_left_melee_time = -1.0
	else:
		_right_melee_time = -1.0
	_sync_primary_hand()
	_update_pose(0.0)

func _clear_melee() -> void:
	_left_melee_time = -1.0
	_right_melee_time = -1.0
	_swing_start_valid = false

func melee_seconds(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return float(_off_profile().seconds)
	if weapon == "dagger":
		return float(DAGGER_DATA.seconds)
	if _right_melee_time >= 0.0:
		return _right_melee_duration
	return float(SWORD_DATA[sword_index].seconds)

func melee_damage(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return float(_off_profile().damage)
	if weapon == "dagger":
		return float(DAGGER_DATA.damage)
	return float(SWORD_DATA[sword_index].damage)

func melee_reach(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return float(_off_profile().reach)
	if weapon == "dagger":
		return float(DAGGER_DATA.reach)
	return float(SWORD_DATA[sword_index].reach)

func melee_radius(hand: String = "") -> float:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return (0.035 + 0.011 * off_weapon_index) if off_weapon_kind == "sword" else 0.022
	if weapon == "dagger":
		return 0.022
	return 0.035 + 0.011 * sword_index

func begin_draw() -> void:
	if weapon != "bow" or phase != "READY" or _roll_progress >= 0.0:
		return
	draw_amount = 0.0
	charge_frozen = false
	phase = "DRAWING"
	_phase_time = 0.0
	_update_pose(0.0)

func begin_throw() -> bool:
	if staff_active or weapon not in ["sword","dagger","dual"] or phase != "READY" or _roll_progress >= 0.0:
		return false
	draw_amount = 0.0
	charge_frozen = false
	phase = "T_DRAW"
	_phase_time = 0.0
	_update_pose(0.0)
	return true

func charge_seconds() -> float:
	if weapon == "bow":
		return float(BOW_DATA[bow_index].draw_seconds)
	if weapon == "dagger":
		return float(DAGGER_DATA.seconds)
	return float(SWORD_DATA[sword_index].seconds)

func throw_weapon_name() -> String:
	return "dagger" if weapon == "dagger" else "sword"

func throw_speed() -> float:
	return float(DAGGER_DATA.throw_speed) if weapon == "dagger" else float(SWORD_DATA[sword_index].throw_speed)

func get_throw_origin() -> Vector3:
	if weapon == "dagger":
		return active_dagger.global_position
	if _staff_shown():
		return active_staff.global_position
	return active_sword.global_position

func get_recovery_progress() -> float:
	var duration := RELEASE_SECONDS + RECOVER_SECONDS
	if phase in ["RELEASE","T_RELEASE"]:
		return clampf(_phase_time/duration,0,1)
	if phase in ["RECOVER","T_RECOVER"]:
		return clampf((RELEASE_SECONDS+_phase_time)/duration,0,1)
	return 1.0

func release_string(override_origin: Vector3 = Vector3.INF, override_direction: Vector3 = Vector3.ZERO) -> void:
	if phase not in ["DRAWING","HOLDING"]:
		return
	charge_frozen = false
	_release_charge = clampf(draw_amount,0,1)
	_release_draw = draw_amount
	_release_raise = _archery_weight()
	_release_grip = to_local(active_bow.global_position)
	_release_contact = to_local(string_hand.global_position)
	_release_bow_rotation = (global_basis.inverse()*active_bow.global_basis).get_rotation_quaternion()
	var visual_origin := get_arrow_origin()
	var origin := visual_origin
	var direction := (_aim_point-origin).normalized()
	if override_origin.is_finite() and override_direction.length_squared() > 0.5:
		origin = override_origin
		direction = override_direction.normalized()
	elif direction.length_squared() < 0.0001:
		direction = active_bow.get_arrow_direction()
	# The rendered arrow leaves from the bow; the physics arrow leaves along the
	# validated crosshair ray. Arrow blends one to the other over a few frames.
	last_arrow_visual_origin = visual_origin
	phase = "RELEASE"
	_phase_time = 0.0
	active_bow.set_arrow_visible(false)
	arrow_released.emit(origin,direction,float(BOW_DATA[bow_index].speed)*lerpf(0.45,1.0,_release_charge),_release_charge)
	_update_pose(0.0)

func release_throw() -> void:
	if phase not in ["T_DRAW","T_HOLD"] or weapon not in ["sword","dagger","dual"]:
		return
	charge_frozen = false
	_release_charge = clampf(draw_amount,0,1)
	_release_draw = draw_amount
	var origin := get_throw_origin()
	var direction := (_aim_point-origin).normalized()
	if direction.length_squared() < 0.0001:
		direction = -global_basis.z
	phase = "T_RELEASE"
	_phase_time = 0.0
	# Endless supply: the equipped weapon is never consumed, only a flying copy
	# leaves the hand. Damage scales with charge exactly like a bow draw.
	var thrown_name := throw_weapon_name()
	weapon_thrown.emit(origin,direction,throw_speed()*lerpf(0.45,1.0,_release_charge),_release_charge,thrown_name,sword_index if thrown_name == "sword" else 0)
	_update_pose(0.0)

func cancel_draw() -> void:
	charge_frozen = false
	cancel_consumable()
	if phase not in ["DRAWING","HOLDING","T_DRAW","T_HOLD"] and not phase.begins_with("MELEE"):
		return
	_clear_melee()
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

func set_hit_react(seconds: float) -> void:
	if seconds <= 0.0:
		_hit_react = 0.0
	else:
		_hit_react = maxf(_hit_react,seconds)
		cancel_consumable()
	_update_pose(0.0)

func set_step(progress: float, direction: Vector3) -> void:
	_step_progress = clampf(progress,0.0,1.0) if progress >= 0.0 else -1.0
	if _step_progress >= 0.0:
		var planar := Vector3(direction.x,0.0,direction.z)
		if not planar.is_zero_approx():
			_step_direction = planar.normalized()
		# The step's own momentum is still decaying on the next few ticks.
		# Keep the facing latched so the exit does not snap the root into the
		# step direction and undo the whole side-step silhouette.
		_step_facing_hold = 0.20
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

func set_blocking(active: bool, forward: Vector3 = Vector3.ZERO) -> void:
	_blocking = active and weapon in ["sword","dagger"]
	if _blocking:
		face_block(forward)
	_update_pose(0.0)

func face_block(forward: Vector3) -> void:
	if not _blocking:
		return
	var planar := Vector3(forward.x,0.0,forward.z)
	if planar.length_squared() > 0.000001:
		_block_forward = planar.normalized()
		global_basis = Basis(Vector3.UP,atan2(-planar.x,-planar.z))

func is_blocking() -> bool:
	return _blocking

func in_strike_window(hand: String = "") -> bool:
	if hand in ["left","right"]:
		var time := _left_melee_time if hand == "left" else _right_melee_time
		if time < 0.0:
			return false
		if hand == "left" and weapon != "dual":
			return false
		if hand == "right" and weapon not in ["sword","dagger","dual"]:
			return false
		var window := _melee_window(hand)
		return time >= window.x-0.000001 and time <= window.y+0.000001
	return (has_melee("left") and in_strike_window("left")) \
		or (has_melee("right") and in_strike_window("right"))

func set_locomotion(world_velocity: Vector3, grounded: bool) -> void:
	if grounded and not _grounded and _velocity.y < -1.0:
		_landing_weight = 1.0
	if not grounded and _grounded:
		_air_time = 0.0
	_velocity = world_velocity
	_grounded = grounded
	if not _cover_active and not _blocking and not is_consuming() and phase == "READY" and _roll_progress < 0.0 and slide_progress < 0.0 and _step_progress < 0.0 and _step_facing_hold <= 0.0 and Vector2(world_velocity.x,world_velocity.z).length_squared() > 0.01:
		# A quick step keeps the original facing; its travel is applied by the
		# hips and shoulders below instead of snapping the whole body sideways.
		global_basis = Basis(Vector3.UP,atan2(-world_velocity.x,-world_velocity.z))

func set_ground_sampler(sampler: Callable) -> void:
	_ground_sampler = sampler

func get_animation_state() -> Dictionary:
	# Roll facing already travels in yaw; compact slide state also fits maximum-length names.
	# Guard rides in the presentation phase instead of another payload field:
	# gameplay still sees READY, while replicas show the sword guard pose.
	# During melee the otherwise-idle draw field carries the other hand's elapsed
	# time, so overlapping recovery does not add a new snapshot key.
	var melee_secondary := draw_amount
	if is_melee():
		melee_secondary = _left_melee_time if _right_melee_time >= 0.0 else _right_melee_time
	var presentation := "GUARD" if _blocking else phase
	var presentation_time := _phase_time
	if _hit_react > 0.0001 and phase == "READY" and not _blocking:
		# STAGGER rides in the existing phase string; time carries the remaining
		# reaction, so the flinch costs no extra snapshot key. An attack that is
		# already active owns the pose instead.
		presentation = "STAGGER"
		presentation_time = _hit_react
	elif _step_progress >= 0.0 and phase == "READY" and not _blocking:
		# The quick step also rides in the phase string. Time carries its
		# progress, so replicas get the shoulder turn with no extra payload key.
		presentation = "STEP"
		presentation_time = _step_progress
	return {"phase":presentation,"draw":melee_secondary,"charge_frozen":charge_frozen,"time":presentation_time,"aim":_aim_point,
		"release_draw":_release_draw,"release_charge":_release_charge,"release_raise":_release_raise,
		"release_grip":_release_grip,"release_contact":_release_contact,"release_rotation":_release_bow_rotation,
		"yaw":global_rotation.y,"roll":_roll_progress,
		"slide":Vector4(slide_progress,_slide_direction.x,_slide_direction.z,_slide_weight),
		"motion_time":_motion_time,"locomotion_phase":_locomotion_phase,"air_time":_air_time,"landing":_landing_weight}

func apply_animation_state(state: Dictionary) -> void:
	var replicated_phase := str(state.phase)
	var guard_phase := replicated_phase == "GUARD"
	var step_phase := replicated_phase == "STEP"
	var consume_phase := replicated_phase in ["BANDAGE","DRINK"]
	_blocking = guard_phase and weapon in ["sword","dagger"]
	if replicated_phase.begins_with("MELEE"):
		var secondary := float(state.draw)
		_left_melee_duration = float(_off_profile().seconds)
		if replicated_phase == "MELEE_L":
			_left_melee_time = float(state.time)
			_right_melee_time = secondary
		else:
			var incoming_variant := "overhead"
			if replicated_phase == "MELEE_HL":
				incoming_variant = "horizontal_left"
			elif replicated_phase == "MELEE_HR":
				incoming_variant = "horizontal_right"
			elif replicated_phase == "MELEE_ST":
				incoming_variant = "stab"
			# A replica catches the swing from the first snapshot it sees. Keep
			# the captured carry pose for one swing only: a phase that is not a
			# running melee or a changed variant means a new strike.
			if not phase.begins_with("MELEE") or incoming_variant != _right_variant:
				_swing_start_valid = false
			_right_variant = incoming_variant
			_right_melee_duration = _right_duration_for(_right_variant)
			_right_melee_time = float(state.time)
			_left_melee_time = secondary
		_sync_primary_hand()
		draw_amount = 0.0
		_hit_react = 0.0
	elif replicated_phase == "STAGGER":
		_left_melee_time = -1.0
		_right_melee_time = -1.0
		phase = "READY"
		_melee_hand = "right"
		_phase_time = 0.0
		draw_amount = 0.0
		_hit_react = maxf(float(state.time),0.0)
	else:
		_left_melee_time = -1.0
		_right_melee_time = -1.0
		phase = "READY" if guard_phase or step_phase else replicated_phase
		_melee_hand = "right"
		_phase_time = 0.0 if guard_phase or step_phase else float(state.time)
		draw_amount = float(state.draw)
		_hit_react = 0.0
		consumable_kind = ("bandage" if replicated_phase == "BANDAGE" else "potion") if consume_phase else ""
	charge_frozen = bool(state.charge_frozen)
	_aim_point = state.aim
	_release_draw = float(state.release_draw)
	_release_charge = float(state.release_charge)
	_release_raise = float(state.release_raise)
	_release_grip = state.release_grip
	_release_contact = state.release_contact
	_release_bow_rotation = state.release_rotation
	global_basis = Basis(Vector3.UP,float(state.yaw))
	if _blocking:
		_block_forward = -global_basis.z
	if step_phase:
		_step_progress = clampf(float(state.time),0.0,1.0)
		# Replicas have no separate step payload; the snapshot velocity is the
		# same world travel the owner collided into.
		var travel := Vector3(_velocity.x,0.0,_velocity.z)
		_step_direction = travel.normalized() if travel.length_squared() > 0.0625 else global_basis.x
	else:
		_step_progress = -1.0
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

func head_hitbox_center() -> Vector3:
	if not _built:
		return global_position + Vector3(0, Hitbox.HUMAN_HEAD_OFFSET + 1.6, 0)
	return _bone_world(_bones.Head) * Vector3(0, Hitbox.HUMAN_HEAD_OFFSET, 0)

func head_hit_profile() -> Vector2:
	return Vector2(Hitbox.HUMAN_HEAD_RADIUS, Hitbox.HUMAN_HEAD_HALF_HEIGHT)

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

func get_blade_base(hand: String = "") -> Vector3:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return _left_blade_node().to_global(Vector3(0,0,-0.09))
	if weapon == "dagger":
		return active_dagger.to_global(Vector3(0,0,-0.09))
	if _staff_shown():
		return active_staff.to_global(Vector3(0,0,-0.09))
	return active_sword.to_global(Vector3(0,0,-0.09))

func get_blade_tip(hand: String = "") -> Vector3:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left":
		return _left_blade_node().to_global(Vector3(0,0,-float(_off_profile().length)-0.09))
	if weapon == "dagger":
		return active_dagger.to_global(Vector3(0,0,-float(DAGGER_DATA.length)-0.09))
	if _staff_shown():
		return active_staff.to_global(Vector3(0,0,-float(STAFF_DATA[staff_index].length)-0.09))
	return active_sword.to_global(Vector3(0,0,-float(SWORD_DATA[sword_index].length)-0.09))

func _physics_process(delta: float) -> void:
	advance_animation(delta)

func advance_animation(delta: float) -> void:
	if not _built:
		return
	_hit_react = maxf(0.0,_hit_react-delta)
	if not is_melee():
		_advance_step(delta)
		return
	# Each hand owns its elapsed time. Both weapons can damage in the same
	# frame; the right sword animation is the body clip whenever it is active.
	# Chronological substeps prevent a long frame from skipping either downswing.
	var remaining := maxf(delta,0.0)
	while remaining > 0.000001 and is_melee():
		var step := minf(remaining,MELEE_SAMPLE_SECONDS)
		var previous_left := _left_melee_time
		var previous_right := _right_melee_time
		var previous_left_base := Vector3.ZERO
		var previous_left_tip := Vector3.ZERO
		var previous_right_base := Vector3.ZERO
		var previous_right_tip := Vector3.ZERO
		if previous_left >= 0.0:
			previous_left_base = get_blade_base("left")
			previous_left_tip = get_blade_tip("left")
		if previous_right >= 0.0:
			previous_right_base = get_blade_base("right")
			previous_right_tip = get_blade_tip("right")
		_advance_melee_step(step)
		if _roll_progress < 0.0:
			if previous_left >= 0.0 and _left_melee_time >= 0.0:
				var window_left := _melee_window("left")
				if _left_melee_time >= window_left.x and previous_left <= window_left.y:
					melee_sweep.emit("left",previous_left_base,previous_left_tip,
						get_blade_base("left"),get_blade_tip("left"),melee_radius("left"))
			if previous_right >= 0.0 and _right_melee_time >= 0.0:
				var window_right := _melee_window("right")
				if _right_melee_time >= window_right.x and previous_right <= window_right.y:
					melee_sweep.emit("right",previous_right_base,previous_right_tip,
						get_blade_base("right"),get_blade_tip("right"),melee_radius("right"))
		if _left_melee_time >= _left_melee_duration-0.000001:
			_left_melee_time = -1.0
		if _right_melee_time >= _right_melee_duration-0.000001:
			_right_melee_time = -1.0
		_sync_primary_hand()
		remaining -= step
	if remaining > 0.000001:
		_advance_step(remaining)

func _advance_melee_step(delta: float) -> void:
	_advance_motion(delta)
	if _left_melee_time >= 0.0:
		_left_melee_time += delta
	if _right_melee_time >= 0.0:
		_right_melee_time += delta
	_sync_primary_hand()
	_update_pose(delta)

func _advance_motion(delta: float) -> void:
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

func _advance_step(delta: float) -> void:
	_phase_time += delta
	_advance_motion(delta)
	match phase:
		"DRAWING":
			if not charge_frozen:
				draw_amount = minf(1.0,draw_amount+delta/float(BOW_DATA[bow_index].draw_seconds))
			if draw_amount >= 1.0-0.000001:
				draw_amount = 1.0
				phase = "HOLDING"
				_phase_time = 0.0
		"T_DRAW":
			if not charge_frozen:
				draw_amount = minf(1.0,draw_amount+delta/charge_seconds())
			if draw_amount >= 1.0-0.000001:
				draw_amount = 1.0
				phase = "T_HOLD"
				_phase_time = 0.0
		"RELEASE":
			draw_amount = _release_draw*(1.0-smoothstep(0.0,0.075,_phase_time))
			if _phase_time >= RELEASE_SECONDS:
				draw_amount = 0.0
				phase = "RECOVER"
				_phase_time -= RELEASE_SECONDS
		"T_RELEASE":
			draw_amount = _release_draw*(1.0-smoothstep(0.0,0.075,_phase_time))
			if _phase_time >= RELEASE_SECONDS:
				draw_amount = 0.0
				phase = "T_RECOVER"
				_phase_time -= RELEASE_SECONDS
		"BANDAGE","DRINK":
			var consume_length := float(CONSUMABLE_DATA.get(consumable_kind, {}).get("seconds", 0.0))
			_phase_time = minf(_phase_time, consume_length)
	if phase in ["RECOVER","T_RECOVER"] and _phase_time >= RECOVER_SECONDS-0.000001:
		phase = "READY"
		_phase_time = 0.0
	_update_pose(delta)

func _melee_clip_for(hand: String, variant: String) -> Dictionary:
	var key := "left" if hand == "left" else "right"
	if key == "left" or weapon == "dagger" or variant == "stab":
		return _profile.clips.stab
	return _profile.clips.overhead if sword_index == 2 else _profile.clips.overhead_one_hand

func _melee_clip() -> Dictionary:
	return _melee_clip_for(_melee_hand,_right_variant if _melee_hand == "right" else "stab")

func _melee_window(hand: String = "") -> Vector2:
	var key := hand if hand in ["left","right"] else _melee_hand
	if key == "left" or weapon == "dagger" or (key == "right" and _right_variant == "stab"):
		var clip: Dictionary = _profile.clips.stab
		var scale := 1.0
		if key == "left":
			# The authored stab is 0.5 s; an off-hand sword keeps the same
			# proportion of its longer swing instead of hitting too early.
			scale = _left_melee_duration / maxf(float(clip.duration),0.0001)
		return Vector2(float(clip.strike_start),float(clip.strike_end)) * scale
	var duration := _right_melee_duration if _right_melee_time >= 0.0 else float(SWORD_DATA[sword_index].seconds)
	var cut_seconds := 0.22+0.04*sword_index
	var windup := (duration-cut_seconds)*0.55
	return Vector2(windup,windup+cut_seconds)

func _melee_clip_time() -> float:
	var clip := _melee_clip()
	var window := _melee_window()
	var duration := melee_seconds()
	if _phase_time < window.x:
		return lerpf(0.0,float(clip.strike_start),clampf(_phase_time/window.x,0,1))
	if _phase_time < window.y:
		return lerpf(float(clip.strike_start),float(clip.strike_end),(_phase_time-window.x)/(window.y-window.x))
	return lerpf(float(clip.strike_end),float(clip.duration),clampf((_phase_time-window.y)/(duration-window.y),0,1))

func _throw_clip_time() -> float:
	# Charge winds through the authored chamber; release snaps through the
	# authored strike, then the follow-through doubles as the resupply recovery.
	var clip := _melee_clip_for("right","overhead")
	var strike_start := float(clip.strike_start)
	var strike_end := float(clip.strike_end)
	match phase:
		"T_DRAW":
			return lerpf(0.0,strike_start,clampf(_phase_time/charge_seconds(),0,1))
		"T_HOLD":
			return strike_start
		"T_RELEASE":
			return lerpf(strike_start,strike_end,smoothstep(0.0,RELEASE_SECONDS,_phase_time))
	return lerpf(strike_end,float(clip.duration),smoothstep(0.0,RECOVER_SECONDS,_phase_time))

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
	_step_facing_hold = maxf(0.0,_step_facing_hold-delta)
	var speed := Vector2(_velocity.x,_velocity.z).length()
	var sliding := _grounded and _roll_progress < 0.0 and not _cover_active and (slide_progress >= 0.0 or _slide_weight > 0.0)
	var stepping := _grounded and _step_progress >= 0.0 and _roll_progress < 0.0 and not sliding
	# The quick step owns its own planted lunge; the forward locomotion cycle
	# would read as a sprint in the step direction instead of a side step.
	var moving := _grounded and speed > 0.1 and _roll_progress < 0.0 and not sliding and not stepping
	var consuming := is_consuming()
	var drawing := weapon == "bow" and phase in ["DRAWING","HOLDING","RELEASE","RECOVER"]
	var throwing := phase in ["T_DRAW","T_HOLD","T_RELEASE","T_RECOVER"]
	var coupled_carry := weapon == "sword" and (sword_index == 2 or _staff_shown()) and not is_melee() and not throwing and not consuming
	var guarding := (coupled_carry or _blocking) and _grounded and _roll_progress < 0.0
	var arm_overlay := coupled_carry and not guarding
	var action := is_melee() or drawing or throwing or guarding or _cover_active or consuming
	var layer_lower_body := action and (moving or (guarding and _landing_weight > 0.0))
	var lower_clip := (_locomotion_clip(speed) if moving else "Jump_Land") if layer_lower_body else ""
	var archery := _archery_weight() if drawing else 0.0
	if _roll_progress < 0.0 and not consuming and (phase != "READY" or _cover_active):
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
	var clip := ("Sword_Idle_OneHand" if weapon in ["sword","dagger"] or weapon == "dual" else "Idle_Loop")
	if weapon == "sword" and (sword_index == 2 or _staff_shown()):
		clip = "Sword_Idle"
	var time := fposmod(_motion_time,_player.get_animation(clip).length)
	if _roll_progress >= 0.0:
		clip = "Roll"
		time = clampf(_roll_progress,0,1)*_player.get_animation(clip).length
	elif is_melee():
		clip = str(_melee_clip().name)
		time = _melee_clip_time()
	elif throwing:
		clip = str(_melee_clip_for("right","overhead").name)
		time = _throw_clip_time()
	elif consuming:
		clip = str(CONSUMABLE_DATA.get(consumable_kind, {}).get("clip","Idle_Loop"))
		time = clampf(_phase_time,0.0,_player.get_animation(clip).length)
	elif drawing:
		time = 0.0
	elif guarding:
		clip = "Sword_Block_Loop" if weapon == "sword" and (sword_index == 2 or _staff_shown()) else "Sword_Block_Loop_OneHand"
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
		_apply_cover_crouch(drawing or is_melee() or throwing or coupled_carry or _blocking or weapon == "dual" or consuming)
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
	_apply_melee_swing_path()
	_apply_hit_react_pose()
	if _grounded and _roll_progress < 0.0:
		if drawing and not moving:
			_plant_archery_feet(archery*(1.0-_slide_weight) if sliding else archery)
		if sliding:
			_apply_slide_pose(drawing or is_melee() or throwing or coupled_carry or _blocking or weapon == "dual" or consuming)
		if _step_progress >= 0.0 and not is_melee() and not throwing:
			_apply_step_pose()
		_place_feet()
	if drawing:
		var head := _bone_world(_bones.Head)
		head.basis = Basis(Vector3.UP,-STANCE_YAW*archery)*head.basis
		_set_bone_world(_bones.Head,head)
	if weapon == "dual" and not consuming:
		_pose_dual_arms()
		if _right_melee_time >= 0.0 and _right_variant == "stab":
			_aim_sword_thrust()
	elif weapon == "dagger" and _right_melee_time >= 0.0:
		_aim_dagger_stab()
	elif weapon == "sword" and _right_melee_time >= 0.0 and _right_variant == "stab":
		_aim_sword_thrust()
	if _right_melee_time >= 0.0 and _right_variant in ["horizontal_left","horizontal_right"]:
		_apply_horizontal_arm_path()
	_update_shield_pose()
	if weapon == "bow":
		_update_bow_pose(drawing)
	elif weapon != "none":
		_update_hand_contacts()
		var right_hand := _bone_world(_arms[1][2])
		if weapon == "dagger":
			active_dagger.global_transform = right_hand * _sword_grip
		elif weapon == "dual":
			active_sword.global_transform = right_hand * _sword_grip
			if active_off_weapon != null:
				active_off_weapon.global_transform = _bone_world(_arms[0][2]) * _sword_grip_left
		elif _staff_shown():
			active_staff.global_transform = right_hand * _sword_grip
		else:
			active_sword.global_transform = right_hand * _sword_grip
		if active_focus != null:
			active_focus.global_transform = _bone_world(_arms[0][2]) * _sword_grip_left
	var chest_pose := global_transform.affine_inverse()*_bone_world(_bones.spine_03)
	_chest.transform = Transform3D(chest_pose.basis*_chest_rest_basis.inverse(),chest_pose.origin)
	_update_consumable_props()
	_sync_weapon_visibility()

func _pose_dual_arms() -> void:
	# The left dagger has no authored attack clip of its own. A left strike
	# starts from the low offhand guard and extends along the crosshair; every
	# other dual pose holds that guard. The right arm stays on the authored
	# sword animation whenever the right hand is attacking, and is otherwise
	# restored to neutral so a left-only strike does not drag the sword.
	# Keep the authored tucked roll arms intact.
	if _roll_progress >= 0.0:
		return
	var left_before: Array[Transform3D] = []
	for bone in _arms[0]:
		left_before.append(skeleton.get_bone_pose(bone))
	var left_melee := _left_melee_time >= 0.0
	var right_melee := _right_melee_time >= 0.0
	var restore_right := left_melee and not right_melee
	var right_bones: Array[int] = []
	var right_before: Array[Transform3D] = []
	if restore_right:
		right_bones.append(int(_bones.clavicle_r))
		for bone in _arms[1]:
			right_bones.append(bone)
		for bone in right_bones:
			right_before.append(skeleton.get_bone_pose(bone))
	if left_melee:
		var shoulder_l := _bone_world(_arms[0][0]).origin
		var shoulder_skel := skeleton.get_bone_global_pose(_arms[0][0])
		var guard := skeleton.global_transform*(shoulder_skel.origin+_offhand_offset)
		var offset := _aim_point-shoulder_l
		var direction := -global_basis.z
		if offset.length_squared() > 0.1225:
			direction = offset.normalized()
		var up := Vector3.UP
		if absf(direction.dot(up)) > 0.98:
			up = global_basis.x
		var aim_basis := Basis.looking_at(direction,up)
		var elbow := _bone_world(_arms[0][1]).origin
		var arm_reach := shoulder_l.distance_to(elbow)+elbow.distance_to(_bone_world(_arms[0][2]).origin)
		var aim_along := 0.35
		if offset.length_squared() > 0.1225:
			aim_along = maxf(0.10,offset.length()-float(_off_profile().length)-0.09)
		var extended := shoulder_l+direction*minf(aim_along,arm_reach-0.01)
		var window := _melee_window("left")
		var extend := smoothstep(window.x-0.06,window.x,_left_melee_time)
		var retract := smoothstep(window.y+0.06,maxf(window.y+0.08,_left_melee_duration-0.04),_left_melee_time)
		var strike := extend*(1.0-retract)
		var target := guard.lerp(extended,strike)
		_solve_limb(_arms[0],target,aim_basis*_sword_grip_left.basis.inverse(),skeleton.global_basis*_offhand_pole)
		if restore_right:
			for bone: int in _neutral_right_arm:
				skeleton.set_bone_pose(bone,_neutral_right_arm[bone])
	else:
		var shoulder := skeleton.get_bone_global_pose(_arms[0][0])
		var target_skel := shoulder.origin+_offhand_offset
		_solve_limb(_arms[0],skeleton.global_transform*target_skel,
			skeleton.global_basis*_offhand_weapon_basis*_sword_grip_left.basis.inverse(),
			skeleton.global_basis*_offhand_pole)
	if _blend_time < BLEND_SECONDS and _roll_progress < 0.0:
		var weight := smoothstep(0.0,BLEND_SECONDS,_blend_time)
		for index in _arms[0].size():
			var bone := _arms[0][index]
			skeleton.set_bone_pose(bone,left_before[index].interpolate_with(skeleton.get_bone_pose(bone),weight))
		if restore_right:
			for index in right_bones.size():
				var bone := right_bones[index]
				skeleton.set_bone_pose(bone,right_before[index].interpolate_with(skeleton.get_bone_pose(bone),weight))
	# Feed the visible arm pose into the next clip transition instead of the
	# unsolved authored arm, which would pop when the strike ends.
	for bone in _arms[0]:
		_authored_pose[bone] = skeleton.get_bone_pose(bone)
	if restore_right:
		for bone in right_bones:
			_authored_pose[bone] = skeleton.get_bone_pose(bone)

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

func _horizontal_swing_timeline() -> Dictionary:
	# One readable full-body cut. The hands lift out of the carry and wind back
	# over the striking shoulder while the torso coils, then the waist unwinds
	# and the hands carry the hilt across the front. The blade points out from
	# the swing centre, so its tip sweeps a wide arc instead of the narrow
	# forward band a mostly-forward blade produced. Angles are signed for the
	# requested side (+1 starts on the right).
	if _right_melee_time < 0.0 or _right_variant not in ["horizontal_left","horizontal_right"]:
		return {"weight":0.0}
	var window := _melee_window("right")
	var duration := maxf(_right_melee_duration,0.001)
	var time := _right_melee_time
	var side := 1.0 if _right_variant == "horizontal_right" else -1.0
	var spec: Dictionary = HORIZONTAL_SWING[clampi(sword_index,0,2)]
	# A right-handed blade cocks far back on its own side. The mirrored wind-up
	# carries the sword across the chest, where the sword arm cannot reach as
	# far, so that coil starts closer to the body instead of locking the arm out.
	var cross_body := _right_variant == "horizontal_left"
	var load := float(spec.load)*(0.90 if cross_body else 1.0)
	var load_radius := float(spec.radius_load)*(0.82 if cross_body else 1.0)
	var coil := smoothstep(0.0,maxf(window.x,0.02),time)
	var cut := smoothstep(window.x,maxf(window.y,window.x+0.001),time) if time > window.x else 0.0
	var settle := smoothstep(window.y,minf(duration,window.y+0.46),time) if time > window.y else 0.0
	# `raise` lifts the blade out of the carry; `release` recovers to a front
	# guard after the cut, and the authored clip only resumes once the swing
	# ends. The authored overhead wind-up therefore never drags the hands away
	# from the cut.
	var raise := smoothstep(0.0,minf(maxf(window.x*0.55,0.16),0.36),time)
	var release := smoothstep(window.y+0.08,minf(duration-0.03,window.y+0.80),time) if time > window.y else 0.0
	# Hands sweep from the cocked side, through the crosshair, past the far side.
	var azimuth := side*lerpf(lerpf(0.30,load,coil),-float(spec.cross),cut)-side*0.30*settle
	# Positive yaw turns the chest toward the actor's left, so the wind-up turns
	# the torso with the hands (a right-side coil turns right) and the cut
	# unwinds it across the body.
	var body := -side*lerpf(lerpf(0.06,float(spec.body_load),coil),-float(spec.body_cross),cut)+side*0.16*settle
	# The blade trails the hands on the wind-up and leads them after contact, so
	# the tip accelerates through the cut instead of merely circling the hands.
	var lag := side*lerpf(lerpf(0.24,float(spec.lag_load),coil),float(spec.lag_cross),cut)
	return {
		"weight":1.0, "raise":raise, "coil":coil, "cut":cut, "settle":settle, "release":release,
		"azimuth":azimuth, "body":body, "lag":lag,
		# The hands start close to the body and only extend as the torso winds:
		# a fully extended neutral pose is out of the sword arm's reach and
		# flattens the elbow against the chest.
		"radius":lerpf(lerpf(0.22,load_radius,coil),float(spec.radius_cross),cut),
		"bias":lerpf(float(spec.bias),0.28,cut),
		"height":float(spec.height),
		"lean":0.05*coil-0.12*cut,
		"pitch":0.12*settle,
	}

func _apply_melee_swing_path() -> void:
	# Horizontal cuts are driven through the waist. A rotating pelvis would drag
	# the planted feet around with it, so the twist lives in the spine and chest:
	# the stance stays fixed while the shoulders and head travel through the cut.
	var swing := _horizontal_swing_timeline()
	if float(swing.weight) <= 0.0:
		return
	var release := float(swing.release)
	var body := float(swing.body)*(1.0-release)
	var lean := float(swing.lean)*(1.0-release)
	if absf(body) <= 0.0001 and absf(lean) <= 0.0001:
		return
	var spine := _bone_world(_bones.spine_01)
	spine.basis = Basis(Vector3.UP,body*0.42)*spine.basis
	_set_bone_world(_bones.spine_01,spine)
	var middle := _bone_world(_bones.spine_02)
	middle.basis = Basis(Vector3.UP,body*0.31)*Basis(global_basis.x,lean*0.5)*middle.basis
	_set_bone_world(_bones.spine_02,middle)
	var chest := _bone_world(_bones.spine_03)
	chest.basis = Basis(Vector3.UP,body*0.27)*Basis(global_basis.x,lean*0.5)*chest.basis
	_set_bone_world(_bones.spine_03,chest)
	# Keep the gaze on the target while the body winds away from it: the
	# silhouette reads as a coil but the crosshair stays meaningful.
	var head := _bone_world(_bones.Head)
	head.basis = Basis(Vector3.UP,-body*0.55)*head.basis
	_set_bone_world(_bones.Head,head)

func _apply_horizontal_arm_path() -> void:
	var swing := _horizontal_swing_timeline()
	if float(swing.weight) <= 0.0:
		return
	var two_hand: bool = weapon == "sword" and (sword_index == 2 or _staff_shown())
	# The swing centre is the shoulder line, not the spine base: the hands orbit
	# the torso, and a pitch-forward crouch would otherwise place every target
	# below and ahead of the ribcage that actually has to clear them.
	var chest := _bone_world(_bones.spine_03).origin
	var pivot := (_bone_world(_arms[0][0]).origin+_bone_world(_arms[1][0]).origin)*0.5
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return
	forward = forward.normalized()
	var offset := _aim_point-pivot
	offset.y = 0.0
	if offset.length_squared() > 0.04:
		forward = offset.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var azimuth := float(swing.azimuth)
	var radial := forward*cos(azimuth)+right*sin(azimuth)
	var settle := float(swing.settle)
	# Aim low against short targets: a fixed chest-height cut passes over the
	# half-size devils. The cut itself stays horizontal; only its plane follows
	# the crosshair's height, and the follow-through lets the tip dip.
	var aim_height := clampf(_aim_point.y,0.35,pivot.y)
	var cut_height := lerpf(pivot.y-0.42,aim_height,0.90)-0.10*settle
	var height := lerpf(pivot.y+float(swing.height),cut_height,float(swing.cut))
	var target := pivot+radial*float(swing.radius)+forward*float(swing.bias)+Vector3.UP*(height-pivot.y)
	# The blade axis is radial from the body, so the whole 1.4 m greatsword
	# sweeps around the swing centre rather than translating forward.
	var blade_azimuth := azimuth+float(swing.lag)
	var blade_dir := forward*cos(blade_azimuth)+right*sin(blade_azimuth)
	blade_dir = (blade_dir*cos(float(swing.pitch))-Vector3.UP*sin(float(swing.pitch))).normalized()
	var hand := _bone_world(_arms[1][2])
	# The resting carry is held in root space, not chest space: the authored
	# wind-up twists the chest, and a chest-relative carry would be dragged
	# behind the back where the sword arm cannot follow it.
	var root_xf := Transform3D(global_basis,global_position)
	var chest_xf := Transform3D(_bone_world(_bones.spine_03).basis,chest)
	if not _swing_start_valid:
		_swing_start_hand = root_xf.affine_inverse()*hand
		_swing_start_support = root_xf.affine_inverse()*_bone_world(_arms[0][2])
		_swing_start_hand_chest = chest_xf.affine_inverse()*hand
		_swing_start_support_chest = chest_xf.affine_inverse()*_bone_world(_arms[0][2])
		_swing_start_valid = true
	var start := root_xf*_swing_start_hand
	# The carry is tracked in chest space as well, only so the elbow pole can
	# tell how far the hand has travelled away from a body-relative rest pose.
	var resting := chest_xf*_swing_start_hand_chest
	var raise := maxf(float(swing.raise),float(swing.coil))
	var release := float(swing.release)
	# The hand leaves the carry along an arc that bows out in front of the
	# chest, not a straight line through it: a linear blend to a cross-body
	# wind-up passed the wrist through the shoulder and the elbow flipped
	# halfway there. The control point sits in the swing frame, so the path
	# stays in front of the body while the torso winds under it.
	var via := pivot+right*0.34+forward*0.06+Vector3.UP*-0.22
	# Leave the carry outward before turning into the swing plane. A hand can
	# rest anywhere around the body after the previous action; a direct arc
	# toward the swing centre would drag the forearm through the ribs.
	var start_out := start.origin-pivot
	start_out.y = 0.0
	if start_out.length_squared() < 0.0001:
		start_out = right
	var leave := start.origin+start_out.normalized()*0.26+Vector3.UP*0.16
	var hand_path := target
	if raise < 1.0:
		hand_path = _hand_arc(start.origin,leave,via,hand_path,raise)
	var start_sword := start.basis*_sword_grip.basis
	var target_sword := Basis.looking_at(blade_dir,Vector3.UP)
	# Once the pose owns the arm, use the target orientation directly. Blending
	# two nearly opposite sword frames is only needed while handing over (and
	# back), and its intermediate roll is not wanted during the cut itself.
	var cut_sword := target_sword if raise >= 0.999 else _blend_basis(start_sword,target_sword,raise)
	# The hand comes up to the carry before the blade turns back into it, so the
	# tip does not drag through the floor while the low follow-through rotates
	# up toward the resting carry.
	var turned := smoothstep(0.30,1.0,release)
	# The cut recovers to a front guard rather than dragging the hand back to
	# the hip: a low hand beside a lunging body folds the forearm through the
	# belly. The carry is the opening pose only.
	var guard := pivot+forward*0.34+right*0.12+Vector3.UP*((cut_height-pivot.y)*0.6)
	if release > 0.0:
		hand_path = _bezier(hand_path,via,guard,release)
	# Ease out of the authored arm over the same window the rig blends clips.
	# That arm pose is valid for its body; taking the arm over in one frame
	# while the torso is still blending would fold the forearm into the ribs.
	var engage := smoothstep(0.0,BLEND_SECONDS,float(_right_melee_time))
	var hand_position := hand.origin.lerp(hand_path,engage)
	var sword_basis := cut_sword if turned <= 0.0001 else _blend_basis(cut_sword,start_sword,turned)
	if engage < 0.999:
		sword_basis = _blend_basis(hand.basis*_sword_grip.basis,sword_basis,engage)
	var hand_basis := sword_basis*_sword_grip.basis.inverse()
	# Wherever the swing starts, the first frames keep the authored elbow: a
	# hand held close to the chest needs the authored bend direction, and the
	# extended-cut pole would tuck the elbow inside the ribs. The pole hands
	# over to the swing's own direction as the hand travels away from the carry.
	var authored_pole := _bone_world(_arms[1][1]).origin-_bone_world(_arms[1][0]).origin
	var extension := smoothstep(0.16,0.45,hand_position.distance_to(resting.origin))
	# The elbow bulges away from the chest on the sword side instead of folding
	# inside it, which also keeps the forearm clear when the cut crosses the body.
	var pole := authored_pole.normalized().slerp(
		(forward*0.7+Vector3.UP*-0.6).normalized(),extension)
	_solve_limb(_arms[1],hand_position,hand_basis,pole)
	if two_hand:
		# Both palms stay on the actual hilt. The support wrist is placed so its
		# palm lands on the handle behind the sword hand; if that point is out of
		# the offhand's reach the grip slides toward the pommel instead of
		# leaving the hand hanging off the sword.
		var sword_hand := _bone_world(_arms[1][2])
		var handle := sword_hand*_sword_grip
		var left := _bone_world(_arms[0][2])
		var shoulder := _bone_world(_arms[0][0]).origin
		var elbow := _bone_world(_arms[0][1]).origin
		var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(left.origin)-0.01
		# The offhand grips the same hilt mirrored, not with the sword hand's
		# own orientation: the mirrored grip puts its wrist on the side the left
		# arm can actually reach.
		var support_target: Basis = (sword_hand*_sword_grip).basis*_sword_grip_left.basis.inverse()
		var support_basis := _blend_basis((root_xf*_swing_start_support).basis,support_target,raise)
		var support := handle*Vector3(0,0,0.20)
		for step in 5:
			var wrist := support-support_basis*_palm_left
			if shoulder.distance_to(wrist) <= arm_reach:
				break
			support = handle*Vector3(0,0,0.20+0.024*float(step+1))
		var support_start := root_xf*_swing_start_support
		var support_rest := chest_xf*_swing_start_support_chest
		var support_point := support_start.origin.lerp(support,raise)
		var authored_support_pole := _bone_world(_arms[0][1]).origin-_bone_world(_arms[0][0]).origin
		var support_pole := authored_support_pole.normalized().slerp(
			(forward*0.6+Vector3.UP*-0.6).normalized(),
			smoothstep(0.16,0.45,support.distance_to(support_start.origin)))
		var left_basis := _blend_basis(support_basis,support_rest.basis,turned)
		var wrist_target: Vector3 = (support_point-support_basis*_palm_left).lerp(guard+right*0.08,release)
		_solve_limb(_arms[0],wrist_target,left_basis,support_pole)

func _apply_hit_react_pose() -> void:
	if _hit_react <= 0.0001 or _roll_progress >= 0.0 or phase != "READY" or _blocking:
		return
	var weight := clampf(_hit_react/0.42,0.0,1.0)
	var spine := _bone_world(_bones.spine_01)
	spine.basis = Basis(global_basis.x,0.22*weight)*spine.basis
	_set_bone_world(_bones.spine_01,spine)
	var head := _bone_world(_bones.Head)
	head.basis = Basis(global_basis.x,0.14*weight)*head.basis
	_set_bone_world(_bones.Head,head)
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.origin += global_basis.z*0.035*weight
	_set_bone_world(_bones.pelvis,pelvis)

func _apply_step_pose() -> void:
	# A planted lateral lunge. The root keeps its facing while the hips open
	# toward the travel, the chest turns further and the head stays on target.
	# That is the side step; snapping the whole body to the velocity read as a
	# one-beat sideways sprint instead.
	var weight := sin(clampf(_step_progress,0.0,1.0)*PI)
	if weight <= 0.0:
		return
	var travel := Vector3(_step_direction.x,0.0,_step_direction.z)
	if travel.length_squared() < 0.0001:
		return
	travel = travel.normalized()
	var face := -global_basis.z
	var turn := clampf(atan2(face.cross(travel).y,face.dot(travel)),-PI*0.5,PI*0.5)
	var side := signf(turn)
	var pelvis := _bone_world(_bones.pelvis)
	pelvis.basis = Basis(Vector3.UP,turn*0.30*weight) \
		* Basis(face,-side*0.12*weight) \
		* Basis(global_basis.x,-0.16*weight) * pelvis.basis
	pelvis.origin += travel*(0.10*weight) - Vector3.UP*0.05*weight
	_set_bone_world(_bones.pelvis,pelvis)
	var spine := _bone_world(_bones.spine_01)
	spine.basis = Basis(Vector3.UP,turn*0.22*weight) \
		* Basis(face,side*0.05*weight) \
		* Basis(global_basis.x,-0.06*weight) * spine.basis
	_set_bone_world(_bones.spine_01,spine)
	var chest := _bone_world(_bones.spine_02)
	chest.basis = Basis(Vector3.UP,turn*0.08*weight)*chest.basis
	_set_bone_world(_bones.spine_02,chest)
	var head := _bone_world(_bones.Head)
	head.basis = Basis(Vector3.UP,-turn*0.42*weight)*head.basis
	_set_bone_world(_bones.Head,head)

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

func _aim_sword_thrust() -> void:
	var shoulder := _bone_world(_arms[1][0]).origin
	var hand := _bone_world(_arms[1][2])
	var offset := _aim_point-shoulder
	if Vector2(offset.x,offset.z).length() < 0.35 or offset.length_squared() < 0.0001:
		return
	var direction := offset.normalized()
	var along := (hand.origin-shoulder).dot(direction)
	var elbow := _bone_world(_arms[1][1]).origin
	var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(hand.origin)
	var blade_length := float(STAFF_DATA[staff_index].length) if _staff_shown() else float(SWORD_DATA[sword_index].length)
	var aim_along := offset.length()-blade_length-0.09
	var window := _melee_window("right")
	var thrust := smoothstep(window.x*0.6,window.y,_right_melee_time)
	along = lerpf(along,clampf(aim_along,along,arm_reach-0.01),thrust)
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = global_basis.x
	var aim_basis := Basis.looking_at(direction,up)
	_solve_limb(_arms[1],shoulder+direction*along,aim_basis*_sword_grip.basis.inverse())

func _aim_dagger_stab() -> void:
	var shoulder := _bone_world(_arms[1][0]).origin
	var hand := _bone_world(_arms[1][2])
	var offset := _aim_point-shoulder
	# Ignore a placeholder/self aim (the arena's initial aim is the actor's own
	# chest); the authored thrust remains for those.
	if Vector2(offset.x,offset.z).length() < 0.35 or offset.length_squared() < 0.0001:
		return
	var direction := offset.normalized()
	# Keep the authored chamber/extension travel, but put the hand on the aim
	# line: the signed distance along the aim is the authored hand's own.
	var along := (hand.origin-shoulder).dot(direction)
	# During the strike the arm extends toward the aim point. The hand cannot
	# pass the arm's length or the point itself (the blade's reach is 0.43).
	var elbow := _bone_world(_arms[1][1]).origin
	var arm_reach := shoulder.distance_to(elbow)+elbow.distance_to(hand.origin)
	var aim_along := offset.length()-float(DAGGER_DATA.length)-0.09
	var window := _melee_window()
	var thrust := smoothstep(window.x*0.6,window.y,_phase_time)
	along = lerpf(along,clampf(aim_along,along,arm_reach-0.01),thrust)
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = global_basis.x
	var aim_basis := Basis.looking_at(direction,up)
	# The socket carries its own grip rotation; cancel it so the blade axis
	# itself points at the aim rather than the hand bone.
	_solve_limb(_arms[1],shoulder+direction*along,aim_basis*_sword_grip.basis.inverse())

func _update_shield_pose() -> void:
	if active_shield == null:
		return
	if not shield_equipped:
		active_shield.set_active(false)
		return
	active_shield.set_active(true)
	var shield_radius := 0.36
	if active_shield.has_method("radius"):
		shield_radius = float(active_shield.radius())
	var size_delta := shield_radius-0.36
	if _blocking:
		var forward := _block_forward
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = -global_basis.z
		forward = forward.normalized()
		var right := global_basis.x
		var chest := _bone_world(_bones.spine_03).origin
		# Keep the shield clear of the weapon hand behind it: the one-handed
		# guard bracer reaches almost to the face, so a close carry clips it.
		# Crouching brings that hand further forward relative to the chest.
		var reach := 0.58+size_delta+0.06*_crouch_amount
		var center := chest+forward*reach+Vector3.UP*0.02-right*0.08
		var basis := Basis.looking_at(forward,Vector3.UP)
		active_shield.global_transform = Transform3D(basis,center)
		var hand := center-forward*0.12-Vector3.UP*0.03
		_solve_limb(_arms[0],hand,basis,-right*0.55-forward*0.15+Vector3.UP*0.1)
	else:
		# A carried shield hangs flat against the outside of the left forearm
		# with its boss facing out. Centering it on the wrist with the face
		# forward slices the forearm and, when crouched, the torso and legs.
		var hand := _bone_world(_arms[0][2])
		var outward := -global_basis.x
		var basis := Basis.looking_at(outward,Vector3.UP)
		var carry := 0.18+size_delta*0.5
		var center := hand.origin+outward*carry+Vector3.UP*0.02
		active_shield.global_transform = Transform3D(basis,center)

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

func _bezier(start: Vector3, control: Vector3, finish: Vector3, weight: float) -> Vector3:
	var inverse := 1.0-weight
	return start*(inverse*inverse)+control*(2.0*inverse*weight)+finish*(weight*weight)

func _arc(from: Vector3, to: Vector3) -> Quaternion:
	# A 180-degree vector pair has no unique rotation axis, and Godot's from/to
	# quaternion then flips axis between frames. Nudge the target just off the
	# antipode toward a stable side so the arc stays continuous.
	if from.dot(to) < -0.9995:
		var side := from.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = from.cross(Vector3.RIGHT)
		to = (to+side.normalized()*0.02).normalized()
	return Quaternion(from,to)

func _blend_basis(from: Basis, to: Basis, weight: float) -> Basis:
	# Interpolate orientation as two independent vector arcs instead of slerping
	# whole bases. A basis slerp between a changing authored hand pose and the
	# cut target flips its rotation axis when the pair approaches 180 degrees,
	# which snapped the sword through the body mid-swing. Direction and up are
	# stable vectors here, and the result reconstructs `from` exactly at 0.
	var dir := (Basis(Quaternion.IDENTITY.slerp(_arc(-from.z,-to.z),weight))*(-from.z)).normalized()
	var up := (Basis(Quaternion.IDENTITY.slerp(_arc(from.y,to.y),weight))*from.y).normalized()
	if absf(dir.dot(up)) > 0.985:
		up = to.y if absf(dir.dot(to.y)) < 0.985 else Vector3.UP
	return Basis.looking_at(dir,up)

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

func _step_foot_offset(side: int) -> Vector3:
	# Widen the stance toward the step: the leading foot reaches out and lifts,
	# the trailing foot braces. The pelvis shift is deliberately smaller than
	# the lead reach so the silhouette stays a step, not a slide.
	if _step_progress < 0.0:
		return Vector3.ZERO
	var travel := Vector3(_step_direction.x,0.0,_step_direction.z)
	if travel.length_squared() < 0.0001:
		return Vector3.ZERO
	travel = travel.normalized()
	var local := travel.dot(global_basis.x)
	if absf(local) < 0.1:
		return Vector3.ZERO
	var weight := sin(clampf(_step_progress,0.0,1.0)*PI)
	var lead := 0 if local < 0.0 else 1
	if side == lead:
		return travel*(0.26*weight)+Vector3.UP*(0.075*weight)
	return travel*(-0.07*weight)

func _place_feet() -> void:
	if not _ground_sampler.is_valid():
		return
	var offset_l := _step_foot_offset(0)
	var offset_r := _step_foot_offset(1)
	var left := _bone_world(_legs[0][2])
	var right := _bone_world(_legs[1][2])
	var left_floor := left.origin+Vector3(offset_l.x,0.0,offset_l.z)
	var right_floor := right.origin+Vector3(offset_r.x,0.0,offset_r.z)
	var floors := Vector2(float(_ground_sampler.call(left_floor)),float(_ground_sampler.call(right_floor)))
	var base_floor := minf(floors.x,floors.y)
	_model.position.y = clampf(base_floor-global_position.y,-0.4,0.4)
	for side in 2:
		var foot := _bone_world(_legs[side][2])
		var offset := offset_l if side == 0 else offset_r
		var ankle := foot.origin+offset+Vector3.UP*(floors[side]-base_floor)
		var toe := foot.origin-global_basis.z*0.15
		var edge := foot.origin+global_basis.x*0.08
		var forward := -global_basis.z*0.15+Vector3.UP*(float(_ground_sampler.call(toe))-floors[side])
		var across := global_basis.x*0.08+Vector3.UP*(float(_ground_sampler.call(edge))-floors[side])
		var normal := across.cross(forward).normalized()
		# Terrain adds slope; do not erase authored heel lift or toe push-off.
		var basis := Basis(Quaternion(Vector3.UP,normal))*foot.basis
		_solve_limb(_legs[side],ankle,basis)
