extends SceneTree
## Snapshot-driven rigs: a body whose pose arrives on the wire must run its own
## clocks at frame rate. Holding the pose between 20 Hz samples is what made a
## replicated jump flip read as stop-motion.

const Archer = preload("res://scripts/archer.gd")
const DodgeRoll = preload("res://scripts/dodge_roll.gd")

const FRAME := 1.0/60.0
const SNAPSHOT_FRAMES := 3
const POSE_EPSILON := 0.0001

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("REPLICA_ANIMATION_FAIL  ",message)

func _initialize() -> void:
	call_deferred("run")

## The furthest any joint moved since the previous sample.
func _pose_distance(a: Dictionary, b: Dictionary) -> float:
	var farthest := 0.0
	for key in a:
		if key == "anchor":
			continue
		farthest = maxf(farthest,a[key].distance_to(b[key]))
	return farthest

func _build(holder: Node3D) -> Archer:
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	rig.aim_at(Vector3(0,1.2,-10))
	return rig

## Drive `source` as the authority and `replica` as a peer: a snapshot every
## third frame, one animation advance every frame.
func _test_flip(holder: Node3D) -> void:
	var source := _build(holder)
	var replica := _build(holder)
	var frames := int(ceil(DodgeRoll.DURATION/FRAME))+4
	var measured := 0
	var moved := 0
	var stalls := 0
	var rewinds := 0
	var longest_hold := 0
	var hold := 0
	var previous: Dictionary = replica.get_joint_positions()
	var previous_roll := -1.0
	for frame in frames:
		var elapsed := frame*FRAME
		if frame % SNAPSHOT_FRAMES == 0:
			var progress := elapsed/DodgeRoll.DURATION
			if progress >= 1.0:
				progress = -1.0
			source.set_roll(progress,Vector3.FORWARD)
			replica.apply_animation_state(source.get_animation_state())
		var before_roll: float = replica._roll_progress
		replica.advance_animation(FRAME)
		var joints: Dictionary = replica.get_joint_positions()
		var distance := _pose_distance(previous,joints)
		previous = joints
		var active := elapsed < DodgeRoll.DURATION*0.97
		if before_roll < previous_roll-0.0001 and before_roll >= 0.0:
			rewinds += 1
		previous_roll = before_roll
		if not active:
			continue
		measured += 1
		if distance > POSE_EPSILON:
			moved += 1
			hold = 0
		else:
			stalls += 1
			hold += 1
			longest_hold = maxi(longest_hold,hold)
	check(measured > 35,"The flip window covers the authored roll")
	check(stalls == 0,"A replicated flip moves its pose on every frame, not only on snapshot frames (%d of %d frames held)" % [stalls,measured])
	check(moved >= SNAPSHOT_FRAMES*3,"The pose advances several times between two snapshots")
	check(longest_hold <= 1,"No pose is held for a whole snapshot interval")
	check(rewinds == 0,"The flip clock never runs backwards on a snapshot")

func _test_wire_authority(holder: Node3D) -> void:
	var source := _build(holder)
	var replica := _build(holder)
	# The loops keep the wire as their authority: a sample reconstructs the
	# owner's crouched draw pose on the replica, and local frames between two
	# samples never invent a pose of their own.
	source.set_cover(true,Vector3.BACK,1.0,true,Vector3.LEFT)
	source.aim_at(Vector3(0,1.4,12))
	source.begin_draw()
	source.advance_animation(0.8)
	source._update_pose(0.0)
	replica.set_cover(true,Vector3.BACK,1.0,true,Vector3.LEFT)
	replica.apply_animation_state(source.get_animation_state())
	replica.advance_animation(0.2)
	replica.apply_animation_state(source.get_animation_state())
	check(replica._bone_world(replica._bones.Head).origin.distance_to(source._bone_world(source._bones.Head).origin) < 0.005,"A replicated draw rebuilds the owner's crouched pose exactly")
	replica.set_cover(false,Vector3.BACK,0.0,false,Vector3.ZERO)
	replica.set_locomotion(Vector3(0,0,-5.0),true)
	var strides: Array[float] = []
	for frame in 30:
		replica.advance_animation(FRAME)
		strides.append(replica._locomotion_phase)
	var stalled := 0
	for index in range(1,strides.size()):
		if absf(strides[index]-strides[index-1]) < 0.000001:
			stalled += 1
	check(stalled == 0,"A replicated stride keeps advancing between samples")

func _test_roll_takeover(holder: Node3D) -> void:
	var source := _build(holder)
	var replica := _build(holder)
	# A second flip can begin before the peer ever sampled the idle frame
	# between them; the new roll must take over instead of sticking at the end.
	source.set_roll(1.0,Vector3.FORWARD)
	replica.apply_animation_state(source.get_animation_state())
	replica.advance_animation(FRAME)
	check(replica._roll_progress >= 1.0-0.0001,"The first flip reaches its last frame")
	source.set_roll(0.0,Vector3.FORWARD)
	replica.apply_animation_state(source.get_animation_state())
	check(replica._roll_progress < 0.2,"A new flip takes the clock over from a finished one")
	# ...and a local body keeps its authoritative clock instead of doubling it.
	var local := _build(holder)
	local.set_locomotion(Vector3(0,0,-8.5),true)
	local.set_roll(0.25,Vector3.FORWARD)
	for frame in SNAPSHOT_FRAMES:
		local.advance_animation(FRAME)
	check(is_equal_approx(local._roll_progress,0.25),"A locally driven flip is not advanced twice")
	local.set_roll(-1.0,Vector3.FORWARD)
	check(local._roll_progress < 0.0,"The local roll clears on the authoritative value")

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	_test_flip(holder)
	_test_wire_authority(holder)
	_test_roll_takeover(holder)
	holder.queue_free()
	await process_frame
	print("REPLICA_ANIMATION_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
