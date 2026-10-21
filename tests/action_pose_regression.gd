extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Roll = preload("res://scripts/dodge_roll.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func check_limbs(rig: Node3D) -> void:
	var joints: Dictionary = rig.get_joint_positions()
	for side in ["left","right"]:
		check(absf(joints[side+"_shoulder"].distance_to(joints[side+"_elbow"])-Archer.ARM_UPPER)<0.0001,"Upper arms retain anatomical length in the action pose")
		check(absf(joints[side+"_elbow"].distance_to(joints[side+"_wrist"])-Archer.ARM_LOWER)<0.0001,"Forearms remain attached to wrists")
		check(absf(joints[side+"_hip"].distance_to(joints[side+"_knee"])-Archer.LEG_UPPER)<0.0001,"Thighs retain their length")
		check(absf(joints[side+"_knee"].distance_to(joints[side+"_ankle"])-Archer.LEG_LOWER)<0.0001,"Shins stay connected while tucked")

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_process(false)
	rig.set_weapon("sword")
	rig.aim_at(Vector3(0,1.2,-10))
	for size in 3:
		rig.set_sword(size)
		rig.phase = "READY"
		rig._process(0.01)
		var rest_forward: Vector3 = rig.get_stance_forward()
		rig.begin_melee()
		for sample in 12:
			rig._process(float(Archer.SWORD_DATA[size].seconds)/12.0)
			check_limbs(rig)
			var joints := rig.get_joint_positions()
			check(absf(joints.left_foot.y)<0.015 and absf(joints.right_foot.y)<0.015,"Sword weight transfer keeps both standing feet grounded")
			if size == 2:
				var grip: Vector3 = rig.active_sword.to_global(Vector3(0,0,0.16))
				check(rig.bow_hand.global_position.distance_to(grip)<0.025,"Greatsword off-hand stays on the handle throughout the cut")
			if sample == 4:
				check(rest_forward.dot(rig.get_stance_forward())<0.99,"Sword windup rotates the shoulders instead of moving only the arms")
	for weapon in ["bow","sword"]:
		rig.set_weapon(weapon)
		rig.phase = "READY"
		rig.set_locomotion(Vector3(0,0,-8.5),false)
		for progress in [0.0,0.12,0.3,0.5,0.72,0.9,1.0]:
			rig.set_roll(progress,Vector3.FORWARD)
			check_limbs(rig)
			if progress == 0.5:
				var joints := rig.get_joint_positions()
				check(joints.left_hip.distance_to(joints.left_ankle)<0.48,"Mid-roll folds the leg rather than rotating a straight body")
				check(joints.right_hip.distance_to(joints.right_ankle)<0.48,"Both legs are tucked during the roll")
		rig.set_roll(-1.0,Vector3.FORWARD)
		rig.set_locomotion(Vector3(0,-5,0),false)
		rig.set_locomotion(Vector3.ZERO,true)
		rig._process(0.01)
		check(rig._landing_weight>0.5,"A descending landing triggers weight absorption")
		rig._process(0.35)
		check(rig._landing_weight==0.0,"Landing settles back to the normal stance")
	holder.queue_free()
	await process_frame
	print("ACTION_POSE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
