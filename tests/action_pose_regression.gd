extends SceneTree

const Archer = preload("res://scripts/archer.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func check_limbs(rig: Node3D, joints: Dictionary) -> void:
	for side in ["left","right"]:
		var suffix := "l" if side == "left" else "r"
		for segment in [["shoulder","elbow","lowerarm"],["elbow","wrist","hand"],["hip","knee","calf"],["knee","ankle","foot"]]:
			var bone: int = rig.skeleton.find_bone(segment[2]+"_"+suffix)
			var rest_length: float = rig.skeleton.get_bone_rest(bone).origin.length()
			check(absf(joints[side+"_"+segment[0]].distance_to(joints[side+"_"+segment[1]])-rest_length)<0.002,"Animation preserves the imported bone lengths and connected joints")

## Chest centre between the shoulder joints, used for the torso lean measure.
func _test_chest(joints: Dictionary, _rig: Node3D) -> Vector3:
	return (joints.left_shoulder+joints.right_shoulder)*0.5

func check_two_hand_grip(rig: Node3D) -> void:
	var handle_start: Vector3 = rig.active_sword.global_position
	var handle_end: Vector3 = rig.active_sword.to_global(Vector3(0,0,0.31))
	var nearest := Geometry3D.get_closest_point_to_segment(rig.bow_hand.global_position,handle_start,handle_end)
	check(nearest.distance_to(rig.bow_hand.global_position)<0.035,"Greatsword support palm stays on the actual handle, not an unattached pose target")

func check_overhead(rig: Node3D, size: int) -> void:
	rig.set_weapon("sword")
	rig.set_sword(size)
	rig.set_locomotion(Vector3.ZERO,true)
	rig.advance_animation(0.3)
	check(rig.begin_melee(),"Selected sword starts its authored overhead attack")
	var previous: Dictionary = rig.get_joint_positions()
	var highest_hand := -INF
	var lowest_tip_after_load := INF
	var highest_tip := -INF
	var lowest_pelvis := INF
	var highest_pelvis := -INF
	var loaded := false
	var duration: float = Archer.SWORD_DATA[size].seconds
	for frame in int(round(duration*120.0)):
		rig.advance_animation(1.0/120.0)
		var joints: Dictionary = rig.get_joint_positions()
		check_limbs(rig,joints)
		for side in ["left","right"]:
			check(joints[side+"_elbow"].distance_to(previous[side+"_elbow"])<0.18,"Authored elbows move continuously without an IK pole flip")
		var palm_y: float = rig.string_hand.global_position.y
		highest_hand = maxf(highest_hand,palm_y-joints.anchor.y)
		loaded = loaded or palm_y>joints.anchor.y+0.06
		highest_tip = maxf(highest_tip,rig.get_blade_tip().y)
		if loaded:
			lowest_tip_after_load = minf(lowest_tip_after_load,rig.get_blade_tip().y)
		var pelvis: float = (joints.left_hip.y+joints.right_hip.y)*0.5
		lowest_pelvis = minf(lowest_pelvis,pelvis)
		highest_pelvis = maxf(highest_pelvis,pelvis)
		if size == 2:
			check_two_hand_grip(rig)
		previous = joints
	check(highest_hand>0.06,"Sword loads overhead above the head before chopping")
	check(highest_tip-lowest_tip_after_load>0.8,"The loaded blade travels down through a substantial chopping arc")
	check(highest_pelvis-lowest_pelvis>0.015,"Heavy attack transfers body weight instead of moving only the hands")
	check(rig.phase=="READY","The complete authored windup, strike and recovery return to ready")

func check_diagonal(rig: Node3D, size: int, variant: String, hand: String = "right", dagger: bool = false) -> float:
	rig.set_weapon("sword")
	rig.set_sword(size)
	if hand == "left":
		rig.set_off_weapon("dagger" if dagger else "sword",size,true)
		rig.set_weapon("dual")
	elif dagger:
		rig.set_weapon("dagger")
	rig.set_locomotion(Vector3.ZERO,true)
	rig.advance_animation(0.4)
	check(rig.begin_melee(hand,variant),"The %s %s diagonal cut starts" % [hand,variant])
	var stance_left: Vector3 = rig.get_joint_positions().left_foot
	var stance_right: Vector3 = rig.get_joint_positions().right_foot
	var foot_drift := 0.0
	var lean_low := INF
	var lean_high := -INF
	var carry_forward: Vector3 = -rig.global_basis.z
	carry_forward.y = 0.0
	carry_forward = carry_forward.normalized()
	var carry_shoulder: Vector3 = rig.get_joint_positions()[hand+"_shoulder"]
	var carry_tip: float = (rig.get_blade_tip(hand)-carry_shoulder).dot(carry_forward)
	var windup_tip := -INF
	var window: Vector2 = rig._melee_window(hand)
	var duration: float = rig.melee_seconds(hand)
	var arm_side := "right" if hand == "right" else "left"
	var previous: Dictionary = rig.get_joint_positions()
	var entry := Vector3.ZERO
	var exit := Vector3.ZERO
	var previous_azimuth := 0.0
	var swept := 0.0
	var lowest := INF
	var highest := -INF
	var pelvis_low := INF
	var pelvis_high := -INF
	var loaded_hips := Vector3.ZERO
	var driven_hips := Vector3.ZERO
	var bent_knees := false
	var finish_stance := 0.0
	var in_window := false
	var load_tip_forward := INF
	var load_wrist_up := -INF
	var load_wrist_forward := INF
	var entry_forward := 0.0
	var exit_forward := 0.0
	var chain: Array[Dictionary] = []
	var head_gaze := INF
	for frame in int(ceil(duration*120.0))+1:
		rig.advance_animation(1.0/120.0)
		var joints: Dictionary = rig.get_joint_positions()
		check_limbs(rig,joints)
		for side in ["left","right"]:
			check(joints[side+"_elbow"].distance_to(previous[side+"_elbow"])<0.25,
				"Diagonal %s %d elbows remain continuous through recovery" % [variant,size])
		previous = joints
		if not rig.has_melee(hand):
			break
		var time: float = rig._left_melee_time if hand == "left" else rig._right_melee_time
		var tip: Vector3 = rig.get_blade_tip(hand)
		var blade: Vector3 = tip-rig.get_blade_base(hand)
		var azimuth := atan2(blade.x,-blade.z)
		var pelvis: float = (joints.left_hip.y+joints.right_hip.y)*0.5
		pelvis_low = minf(pelvis_low,pelvis)
		pelvis_high = maxf(pelvis_high,pelvis)
		var hips: Vector3 = (joints.left_hip+joints.right_hip)*0.5
		var swing_forward: Vector3 = -rig.global_basis.z
		swing_forward.y = 0.0
		swing_forward = swing_forward.normalized()
		if time < window.x:
			# The last windup frame is the cocked pose: wrist above the
			# shoulder, hand held back, blade loaded behind the shoulder plane.
			var load_shoulder: Vector3 = joints[arm_side+"_shoulder"]
			var load_wrist: Vector3 = joints[arm_side+"_wrist"]
			load_tip_forward = (rig.get_blade_tip(hand)-rig.global_position).dot(swing_forward)
			windup_tip = maxf(windup_tip,(rig.get_blade_tip(hand)-load_shoulder).dot(swing_forward))
			load_wrist_up = load_wrist.y-load_shoulder.y
			load_wrist_forward = (load_wrist-load_shoulder).dot(swing_forward)
		if time >= window.x and time <= window.y:
			lowest = minf(lowest,tip.y-rig.global_position.y)
			highest = maxf(highest,tip.y-rig.global_position.y)
			var left_bend: float = (joints.left_hip-joints.left_knee).angle_to(joints.left_ankle-joints.left_knee)
			var right_bend: float = (joints.right_hip-joints.right_knee).angle_to(joints.right_ankle-joints.right_knee)
			bent_knees = bent_knees or (left_bend+right_bend)*0.5 < deg_to_rad(125.0)
			driven_hips = hips
			finish_stance = absf((joints.left_foot-joints.right_foot).dot(-rig.global_basis.z))
			if size == 2 and hand == "right" and not dagger:
				check_two_hand_grip(rig)
			var left_drift: Vector3 = joints.left_foot-stance_left
			left_drift.y = 0.0
			var right_drift: Vector3 = joints.right_foot-stance_right
			right_drift.y = 0.0
			foot_drift = maxf(foot_drift,maxf(left_drift.length(),right_drift.length()))
			var torso_lean := atan2((_test_chest(joints,rig)-hips).dot(swing_forward),(_test_chest(joints,rig)-hips).y)
			lean_low = minf(lean_low,torso_lean)
			lean_high = maxf(lean_high,torso_lean)
			if not in_window:
				in_window = true
				entry = tip
				entry_forward = (tip-rig.global_position).dot(swing_forward)
				loaded_hips = hips
			else:
				swept += wrapf(azimuth-previous_azimuth,-PI,PI)
			exit = tip
			exit_forward = (tip-rig.global_position).dot(swing_forward)
			previous_azimuth = azimuth
			# Kinetic chain telemetry: hip line, hilt direction and blade
			# azimuth in the swing frame, plus the head's own gaze.
			var swing_right: Vector3 = swing_forward.cross(Vector3.UP)
			var hip_dir: Vector3 = joints.right_hip-joints.left_hip
			hip_dir.y = 0.0
			var hand_dir: Vector3 = joints[arm_side+"_wrist"]-rig.global_position
			hand_dir.y = 0.0
			var hip_turn := atan2(hip_dir.dot(swing_forward),hip_dir.dot(swing_right))
			var chest_dir: Vector3 = joints.right_shoulder-joints.left_shoulder
			chest_dir.y = 0.0
			var head_forward: Vector3 = rig._bone_world(rig._bones.Head).basis.z
			head_gaze = minf(head_gaze,head_forward.dot(swing_forward))
			chain.append({
				"pelvis":hip_turn,
				"chest":atan2(chest_dir.dot(swing_forward),chest_dir.dot(swing_right)),
				"hand":atan2(hand_dir.dot(swing_right),hand_dir.dot(swing_forward)),
				"tip":azimuth,
				"hilt":(joints[arm_side+"_wrist"]-rig.global_position).dot(swing_right),
			})
	check(load_wrist_up>0.18,"The diagonal cocks the wrist above the shoulder before cutting (up %.3f, size %d %s %s)" % [load_wrist_up,size,hand,variant])
	check(load_tip_forward<0.05,"The diagonal backswing loads the blade behind the body plane (tip %.3f, wrist up %.3f, size %d %s %s)" % [load_tip_forward,load_wrist_up,size,hand,variant])
	var two_hand_load := size == 2 and hand == "right" and not dagger
	check(load_wrist_forward<(0.40 if two_hand_load else 0.18),"The diagonal draws the hand back instead of extending it forward (f %.3f, size %d %s %s)" % [load_wrist_forward,size,hand,variant])
	# The wind-up leaves the weapon where the carry holds it: it lifts and pulls
	# back into the cock. A tip that leads forward first reads as presenting the
	# sword before the swing.
	check(windup_tip-carry_tip<0.15,"The wind-up lifts the weapon out of its carry instead of pushing it forward past the shoulder (%.3f m, size %d %s %s)" % [windup_tip-carry_tip,size,hand,variant])
	check(exit_forward-entry_forward>0.30,"The backswing releases forward through the active cut")
	check(absf(swept)>deg_to_rad(105.0),"Diagonal blade traverses a broad frontal arc")
	check(swept < 0.0 if variant == "diagonal_right" else swept > 0.0,"Opposite diagonal variants mirror the cut direction")
	check(entry.y-exit.y > 0.35,"The active stroke descends instead of sweeping a level plane")
	check(entry.distance_to(exit) > (0.7 if dagger else 1.2+0.5*size),"The blade follows a size-scaled cross-front path")
	check(lowest > 0.25 and highest < 2.7,"The diagonal stays above the actor-relative floor and below an implausible high load")
	# The kinetic chain: hips, then chest, then hand, then the blade tip. At the
	# frame where the hand is halfway across the body the hips must already be
	# through their unwind, and the tip must still be catching up.
	var tip_span := wrapf(float(chain[-1].tip)-float(chain[0].tip),-PI,PI)
	var hand_span := wrapf(float(chain[-1].hand)-float(chain[0].hand),-PI,PI)
	var half_tip := INF
	for sample in chain:
		var hand_fraction: float = clampf(wrapf(float(sample.hand)-float(chain[0].hand),-PI,PI)/hand_span,0.0,1.0)
		if hand_fraction < 0.5:
			continue
		half_tip = clampf(wrapf(float(sample.tip)-float(chain[0].tip),-PI,PI)/tip_span,0.0,1.0)
		break
	check(half_tip <= 0.5,"The blade tip lags the hilt so it arrives at the end of the arc (tip %.2f, size %d %s %s)" % [half_tip,size,hand,variant])
	# The body drives the cut: the hips and chest carry a real share of the
	# turn instead of the arm orbiting a dead torso.
	var hip_turn := 0.0
	var chest_turn := 0.0
	for index in range(1,chain.size()):
		hip_turn += wrapf(float(chain[index].pelvis)-float(chain[index-1].pelvis),-PI,PI)
		chest_turn += wrapf(float(chain[index].chest)-float(chain[index-1].chest),-PI,PI)
	check(absf(hip_turn)>deg_to_rad(20.0),"The pelvis turns through the strike instead of holding still (%.0f deg, size %d %s %s)" % [rad_to_deg(absf(hip_turn)),size,hand,variant])
	check(absf(chest_turn)>deg_to_rad(35.0),"The chest unwinds past the target with the cut (%.0f deg, size %d %s %s)" % [rad_to_deg(absf(chest_turn)),size,hand,variant])
	check(signf(chest_turn)==signf(hip_turn),"The chest follows the hips in the same direction (%.0f/%.0f deg, size %d %s %s)" % [rad_to_deg(chest_turn),rad_to_deg(hip_turn),size,hand,variant])
	var hilt_travel := absf(float(chain[-1].hilt)-float(chain[0].hilt))
	check(hilt_travel>0.20,"The hilt travels across the body instead of orbiting one hip (%.2f m, size %d %s %s)" % [hilt_travel,size,hand,variant])
	check(head_gaze>0.62,"The head keeps the target in view instead of dropping through the strike (gaze %.2f, size %d %s %s)" % [head_gaze,size,hand,variant])
	check(pelvis_high-pelvis_low>0.10,"Diagonal body motion lowers and raises the hips, rather than making an idle-sized bob")
	check(bent_knees,"The active stroke is driven through flexed knees, not locked upright legs")
	check(foot_drift<0.06,"The feet stay planted in the stance they started in instead of stepping through the cut (%.2f m, size %d %s %s)" % [foot_drift,size,hand,variant])
	check(lean_low>-0.06,"The strike never leans the torso backwards (low %.0f deg, size %d %s %s)" % [rad_to_deg(lean_low),size,hand,variant])
	check(lean_high>deg_to_rad(4.0),"The strike drives the chest forward over the stance (high %.0f deg, size %d %s %s)" % [rad_to_deg(lean_high),size,hand,variant])
	check((driven_hips-loaded_hips).dot(-rig.global_basis.z)>0.02,"The hips shift weight forward from the loaded leg through the cut")
	check(finish_stance>0.25,"The stance stays staggered through the cut instead of squaring up")
	check(rig.phase == "READY","The diagonal cut and both hands recover to ready")
	return entry.distance_to(exit)

func check_staff_diagonal(rig: Node3D) -> void:
	rig.set_weapon("sword")
	rig.set_staff(0,true)
	rig.set_locomotion(Vector3.ZERO,true)
	rig.advance_animation(0.5)
	var idle_base: Vector3 = rig.get_blade_base("right")
	var idle_tip: Vector3 = rig.get_blade_tip("right")
	var idle_center := (idle_base+idle_tip)*0.5
	var idle_right: Vector3 = rig.get_joint_positions().right_wrist
	check(idle_right.distance_to(idle_center)<0.35,"The staff grip sits around the shaft middle, not at one end")
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for variant in ["diagonal_right","diagonal_left"]:
		rig.set_staff(0,true)
		check(rig.begin_melee("right",variant),"The staff starts its %s cut" % variant)
		var window: Vector2 = rig._melee_window("right")
		var max_center := 0.0
		var max_axis := 0.0
		var min_separation := INF
		var max_separation := 0.0
		var both_ends := false
		var elapsed := 0.0
		var lead_end := Vector3.ZERO
		var butt_end := Vector3.ZERO
		var grip_end := Vector3.ZERO
		while elapsed < rig.melee_seconds("right")+0.05:
			rig.advance_animation(1.0/120.0)
			elapsed += 1.0/120.0
			if not rig.has_melee("right"):
				break
			var joints: Dictionary = rig.get_joint_positions()
			var base: Vector3 = rig.get_blade_base("right")
			var tip: Vector3 = rig.get_blade_tip("right")
			var axis := (tip-base).normalized()
			var right: Vector3 = joints.right_wrist
			var left: Vector3 = joints.left_wrist
			max_center = maxf(max_center,right.distance_to((base+tip)*0.5))
			if elapsed >= window.x:
				both_ends = both_ends or (base-right).dot(axis)*(tip-right).dot(axis)<0.0
			if elapsed >= window.x and elapsed <= window.y:
				max_axis = maxf(max_axis,(left-base).cross(axis).length())
				var separation := left.distance_to(right)
				min_separation = minf(min_separation,separation)
				max_separation = maxf(max_separation,separation)
				lead_end = tip
				butt_end = base
				grip_end = right
		check(max_center<0.35,"The %s staff swing keeps the right hand at the shaft middle" % variant)
		check(max_axis<0.12,"The %s staff swing keeps the support hand on the shaft (%.3f)" % [variant,max_axis])
		check(min_separation>0.20 and max_separation<0.45,"The %s staff hands stay spaced around the middle" % variant)
		check(both_ends,"The %s staff extends on both sides of the grip" % variant)
		# A middle-gripped staff counterweights: the leading end finishes ahead
		# and low while the rear end swings up and behind the hands. A hilt at
		# one end of the weapon cannot produce that shape.
		check((lead_end-grip_end).dot(forward)>0.20,"The %s staff leads the strike with its far end (%.2f)" % [variant,(lead_end-grip_end).dot(forward)])
		check((butt_end-grip_end).dot(forward)<0.05,"The %s staff rear end counterweights behind the hands (%.2f)" % [variant,(butt_end-grip_end).dot(forward)])
		check(butt_end.y>grip_end.y,"The %s staff rear end rides above the grip at the follow-through (%.2f/%.2f)" % [variant,butt_end.y,grip_end.y])
		check(rig.phase=="READY","The %s staff cut recovers to ready" % variant)
	rig.set_staff(0,false)

func check_staff_precision(rig: Node3D) -> void:
	rig.set_weapon("sword")
	rig.set_staff(0,true)
	rig.set_locomotion(Vector3.ZERO,true)
	for variant in ["overhead","stab"]:
		rig.advance_animation(2.4)
		rig.set_staff(0,true)
		check(rig.begin_melee("right",variant),"The staff starts its %s precision attack" % variant)
		var lowest := INF
		var duration: float = rig.melee_seconds("right")
		var elapsed := 0.0
		while elapsed < duration:
			rig.advance_animation(1.0/120.0)
			elapsed += 1.0/120.0
			var base: Vector3 = rig.get_blade_base("right")
			var tip: Vector3 = rig.get_blade_tip("right")
			lowest = minf(lowest,minf(base.y,tip.y))
		check(lowest>(0.0 if variant=="overhead" else 0.5),"The staff %s keeps both shaft ends clear of the floor (lowest %.3f)" % [variant,lowest])
		check(rig.phase=="READY","The staff %s recovers to ready" % variant)

func check_running(rig: Node3D, weapon: String, size: int) -> void:
	rig.set_weapon(weapon)
	rig.set_sword(size)
	rig.set_locomotion(Vector3(0,0,-8.5),true)
	rig.advance_animation(0.4)
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	var flight := 0
	for frame in 120:
		rig.advance_animation(1.0/120.0)
		var joints: Dictionary = rig.get_joint_positions()
		check_limbs(rig,joints)
		for side in 2:
			var prefix := "left" if side == 0 else "right"
			var hand_z: float = joints[prefix+"_wrist"].z-joints[prefix+"_shoulder"].z
			low[side] = minf(low[side],hand_z)
			high[side] = maxf(high[side],hand_z)
		if joints.left_foot.y>0.02 and joints.right_foot.y>0.02:
			flight += 1
		if weapon=="sword" and size==2:
			check_two_hand_grip(rig)
	if weapon=="bow" or size!=2:
		check(high.x-low.x>0.25 and high.y-low.y>0.25,"The authored sprint drives both arms, including the weapon arm")
	check(flight>0,"The sprint has genuine flight rather than accelerated walking")

func check_cover_poses(holder: Node3D) -> void:
	for action in ["peek","draw","release"]:
		var rig := Archer.new()
		holder.add_child(rig)
		rig.set_physics_process(false)
		rig.set_ground_sampler(func(_point: Vector3) -> float: return 0.0)
		rig.set_cover(true,Vector3.BACK,0.0,true,Vector3.ZERO)
		rig.aim_at(Vector3(0,1.4,12))
		if action in ["draw","release"]:
			rig.begin_draw()
			rig.advance_animation(0.8)
			if action == "release":
				rig.release_string()
				rig.advance_animation(0.08)
		else:
			rig.advance_animation(0.2)
		for crouch in [0.0,1.0]:
			for lean in [Vector3.UP,Vector3.LEFT,Vector3.RIGHT]:
				rig.set_cover(true,Vector3.BACK,crouch,true,Vector3.ZERO)
				rig._update_pose(0.0)
				var neutral_head: Vector3 = rig._bone_world(rig._bones.Head).origin
				var neutral_chest: Vector3 = (rig._bone_world(rig._arms[0][0]).origin+rig._bone_world(rig._arms[1][0]).origin)*0.5
				var neutral_basis: Basis = rig._bone_world(rig._bones.spine_03).basis
				var neutral_joints := rig.get_joint_positions()
				rig.set_cover(true,Vector3.BACK,crouch,true,lean)
				rig._update_pose(0.0)
				var direction: Vector3 = Vector3.FORWARD if lean == Vector3.UP else lean
				var head_motion: Vector3 = rig._bone_world(rig._bones.Head).origin-neutral_head
				var chest_motion: Vector3 = (rig._bone_world(rig._arms[0][0]).origin+rig._bone_world(rig._arms[1][0]).origin)*0.5-neutral_chest
				var torso_turn: Basis = rig._bone_world(rig._bones.spine_03).basis*neutral_basis.inverse()
				var articulation: float = torso_turn.get_rotation_quaternion().get_angle()
				var max_articulation := 0.31 if lean==Vector3.UP else 0.40
				check(head_motion.dot(direction)>0.0 and chest_motion.dot(direction)>0.0 and articulation>0.12 and articulation<max_articulation,"Cover %s visibly articulates toward %s without excessive torso tilt, including crouch %.0f" % [action,lean,crouch])
				var joints := rig.get_joint_positions()
				check_limbs(rig,joints)
				check(joints.left_foot.distance_to(neutral_joints.left_foot)<0.02 and joints.right_foot.distance_to(neutral_joints.right_foot)<0.02,"Lean weight transfer keeps both feet planted")
				rig.set_cover(true,Vector3.BACK,crouch,false,Vector3.ZERO)
				rig._update_pose(0.0)
				check(rig._bone_world(rig._bones.Head).origin.distance_to(neutral_head)<0.002,"Removing the lean restores the action pose without accumulated offsets")
		var observer := Archer.new()
		holder.add_child(observer)
		observer.set_physics_process(false)
		observer.set_cover(true,Vector3.BACK,1.0,true,Vector3.LEFT)
		rig.set_cover(true,Vector3.BACK,1.0,true,Vector3.LEFT)
		rig._update_pose(0.0)
		observer.apply_animation_state(rig.get_animation_state())
		observer.advance_animation(0.2)
		observer.apply_animation_state(rig.get_animation_state())
		check(observer._bone_world(observer._bones.Head).origin.distance_to(rig._bone_world(rig._bones.Head).origin)<0.005,"Replicated %s reconstructs the crouched lean on the real skeleton" % action)
		observer.queue_free()
		if action == "peek":
			rig.aim_at(Vector3(0,1.4,-12))
			rig.set_cover(true,Vector3.BACK,0.0,false,Vector3.UP*0.5)
			rig._update_pose(0.0)
			check(absf(rig.global_basis.z.z)<0.1,"A partial peek turns through an intermediate facing instead of snapping")
			rig.set_cover(true,Vector3.BACK,0.0,true,Vector3.UP)
			rig._update_pose(0.0)
			check((-rig.global_basis.z).dot(Vector3.FORWARD)>0.99,"An idle top peek faces over the obstacle toward the aim point")
			rig.set_cover(true,Vector3.BACK,1.0,false,Vector3.ZERO)
			rig._update_pose(0.0)
			check((-rig.global_basis.z).dot(Vector3.BACK)>0.99,"Retucking restores the protected outward facing")
		rig.queue_free()

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	rig.aim_at(Vector3(0,1.2,-10))
	for size in 3:
		check_overhead(rig,size)
	for variant in ["diagonal_right","diagonal_left"]:
		var previous_span := 0.0
		for size in 3:
			var span := check_diagonal(rig,size,variant)
			check(span > previous_span+0.25,"Each larger sword visibly broadens the cut")
			previous_span = span
		check_diagonal(rig,0,variant,"right",true)
		check_diagonal(rig,0,variant,"left",true)
		for size in 2:
			check_diagonal(rig,size,variant,"left")
	# Elevated actors use the same body-relative path, not an absolute floor clamp.
	rig.position.y = 7.0
	rig.aim_at(Vector3(0,8.2,-10))
	check_diagonal(rig,1,"diagonal_right")
	rig.position.y = 0.0
	rig.aim_at(Vector3(0,1.2,-10))
	check_staff_diagonal(rig)
	check_staff_precision(rig)
	for weapon in ["bow","sword"]:
		rig.set_weapon(weapon)
		rig.set_locomotion(Vector3(0,0,-8.5),false)
		var shortest_fold := INF
		for progress in [0.0,0.15,0.3,0.45,0.6,0.75,0.9,1.0]:
			rig.set_roll(progress,Vector3.FORWARD)
			var joints := rig.get_joint_positions()
			check_limbs(rig,joints)
			shortest_fold = minf(shortest_fold,joints.left_hip.distance_to(joints.left_ankle))
		check(shortest_fold<0.55,"Authored roll folds the knees rather than rotating a straight mannequin")
		rig.set_roll(-1.0,Vector3.FORWARD)
	check_running(rig,"bow",1)
	check_running(rig,"sword",1)
	check_running(rig,"sword",2)
	check_cover_poses(holder)
	holder.queue_free()
	await process_frame
	print("ACTION_POSE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
