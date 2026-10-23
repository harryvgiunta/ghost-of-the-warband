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

func check_horizontal(rig: Node3D, size: int, variant: String) -> void:
	rig.set_weapon("sword")
	rig.set_sword(size)
	rig.set_locomotion(Vector3.ZERO,true)
	rig.advance_animation(0.4)
	check(rig.begin_melee("right",variant),"The %s horizontal cut starts" % variant)
	var window: Vector2 = rig._melee_window("right")
	var duration: float = Archer.SWORD_DATA[size].seconds
	var previous: Dictionary = rig.get_joint_positions()
	var entry := Vector3.ZERO
	var exit := Vector3.ZERO
	var previous_azimuth := 0.0
	var swept := 0.0
	var lowest := INF
	var highest := -INF
	var in_window := false
	for frame in int(round(duration*120.0)):
		rig.advance_animation(1.0/120.0)
		if rig._right_melee_time < 0.0:
			break
		var joints: Dictionary = rig.get_joint_positions()
		check_limbs(rig,joints)
		for side in ["left","right"]:
			check(joints[side+"_elbow"].distance_to(previous[side+"_elbow"])<0.25,
				"Horizontal %s %d elbows move continuously without an IK pole flip" % [variant,size])
		var time: float = rig._right_melee_time
		var tip: Vector3 = rig.get_blade_tip()
		lowest = minf(lowest,tip.y)
		highest = maxf(highest,tip.y)
		var azimuth := atan2(tip.x-rig.global_position.x,-(tip.z-rig.global_position.z))
		if time >= window.x and time <= window.y:
			# Both hands stay on the hilt through the whole cut, not only at the
			# instant the contact volume is sampled.
			if size == 2:
				check_two_hand_grip(rig)
			if not in_window:
				in_window = true
				entry = tip
			else:
				swept += absf(wrapf(azimuth-previous_azimuth,-PI,PI))
			exit = tip
			previous_azimuth = azimuth
		previous = joints
	check(swept > deg_to_rad(105.0),
		"Horizontal %s %d sweeps the blade through a wide arc (%.0f degrees)" % [variant,size,rad_to_deg(swept)])
	check(entry.distance_to(exit) > 1.2+0.5*size,
		"Horizontal %s %d carries the blade through a real path (%.2f m)" % [variant,size,entry.distance_to(exit)])
	check(lowest > 0.25 and highest < 2.7,
		"Horizontal %s %d stays between waist and head height (%.2f..%.2f)" % [variant,size,lowest,highest])
	check(rig.phase == "READY","The horizontal cut recovers to ready")

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
	for size in 3:
		for variant in ["horizontal_right","horizontal_left"]:
			check_horizontal(rig,size,variant)
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
