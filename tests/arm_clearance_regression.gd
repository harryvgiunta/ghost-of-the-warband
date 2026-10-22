extends SceneTree
## Test rendered anatomy, not a guessed torso radius or a hand-target variable.
const Archer = preload("res://scripts/archer.gd")
var rig
var body: MeshInstance3D
var vertices: PackedVector3Array
var indices: PackedInt32Array
var weights: PackedFloat32Array
var joints: PackedInt32Array
var skinned := PackedVector3Array()
var bind_bones := PackedInt32Array()
var binds: Array[Transform3D] = []
var transforms: Array[Transform3D] = []
var influences := 4
var failures := 0
var samples := 0

func _initialize() -> void:
	call_deferred("run")

func skin_body() -> void:
	for index in binds.size():
		transforms[index] = rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(bind_bones[index])*binds[index]
	for index in vertices.size():
		var point := Vector3.ZERO
		for influence in influences:
			var slot := index*influences+influence
			if weights[slot]>0.0:
				point += (transforms[joints[slot]]*vertices[index])*weights[slot]
		skinned[index] = point

func check_forearms(label: String) -> void:
	samples += 1
	skin_body()
	var pose: Dictionary = rig.get_joint_positions()
	for side in ["left","right"]:
		var start: Vector3 = pose[side+"_elbow"]
		var finish: Vector3 = pose[side+"_wrist"]
		var along := (finish-start).normalized()
		var across := along.cross(Vector3.UP).normalized()
		if across.length_squared()<0.01:
			across = along.cross(Vector3.RIGHT).normalized()
		var around := along.cross(across).normalized()
		for displacement in [Vector3.ZERO,across*0.03,-across*0.03,around*0.03,-around*0.03]:
			for triangle in range(0,indices.size(),3):
				var hit = Geometry3D.segment_intersects_triangle(start+displacement,finish+displacement,skinned[indices[triangle]],skinned[indices[triangle+1]],skinned[indices[triangle+2]])
				if hit != null:
					failures += 1
					push_error("%s %s forearm penetrates the actual skinned torso at %s (weapon %s/%d, phase %s, t %.3f; shoulder %s, elbow %s, wrist %s, nock %s)" % [label,side,str(hit),rig.weapon,rig.sword_index,rig.phase,rig._phase_time,str(pose[side+"_shoulder"]),str(start),str(finish),str(rig.active_bow.get_nock_position())])
					return

func advance(seconds: float, label: String) -> void:
	var remaining := seconds
	while remaining>0.000001:
		var step := minf(remaining,0.025)
		rig.advance_animation(step)
		check_forearms(label)
		remaining -= step
		if failures>0:
			return

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	rig = Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	body = rig.find_child("Male_Ranger_Body",true,false) as MeshInstance3D
	var arrays := body.mesh.surface_get_arrays(0)
	vertices = arrays[Mesh.ARRAY_VERTEX]
	indices = arrays[Mesh.ARRAY_INDEX]
	weights = arrays[Mesh.ARRAY_WEIGHTS]
	joints = arrays[Mesh.ARRAY_BONES]
	influences = joints.size()/vertices.size()
	skinned.resize(vertices.size())
	for index in body.skin.get_bind_count():
		bind_bones.append(rig.skeleton.find_bone(body.skin.get_bind_name(index)))
		binds.append(body.skin.get_bind_pose(index))
		transforms.append(Transform3D.IDENTITY)
	rig.aim_at(Vector3(0,1.7,-30))
	rig.set_bow(2)
	for fraction in [0.0,0.5,1.0]:
		rig.begin_draw()
		advance(3.0*fraction,"Bow draw")
		if failures>0:
			break
		rig.release_string()
		advance(1.23,"Arrow retrieval and re-nock")
		if failures>0:
			break
	if failures==0:
		rig.set_weapon("sword")
		for size in 3:
			rig.set_sword(size)
			rig.begin_melee()
			advance(float(size+1),"Sword windup/cut/recovery")
			if failures>0:
				break
			advance(0.3,"Sword guard transition")
			if failures>0:
				break
	if failures==0:
		rig.set_weapon("sword")
		for size in 3:
			rig.set_sword(size)
			rig.set_blocking(true,Vector3(0,0,-1))
			advance(2.0,"Sword guard loop")
			if failures>0:
				break
			rig.set_blocking(false)
			advance(0.3,"Sword guard transition")
			if failures>0:
				break
	if failures==0:
		rig.set_weapon("sword")
		rig.set_sword(0)
		rig.set_blocking(true,Vector3(0,0,-1))
		rig.set_cover(false,Vector3.ZERO,0.6,false,Vector3.ZERO)
		advance(0.4,"Crouched sword guard")
		rig.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
		rig.set_blocking(false)
		advance(0.3,"Crouched guard exit")
	if failures==0:
		rig.set_weapon("sword")
		rig.set_sword(1)
		rig.set_blocking(true,Vector3(0,0,-1))
		rig.set_locomotion(Vector3(0,0,-5.5),true)
		advance(0.8,"Moving sword guard")
		rig.set_locomotion(Vector3.ZERO,true)
		rig.set_blocking(false)
		advance(0.3,"Moving guard exit")
	if failures==0:
		for weapon in ["bow","sword"]:
			rig.set_weapon(weapon)
			for speed in [5.5,8.5]:
				rig.set_locomotion(Vector3(0,0,-speed),true)
				advance(0.8,"Moving weapon carry")
				if failures>0:
					break
	holder.queue_free()
	await process_frame
	print("ARM_CLEARANCE_REGRESSION samples=",samples," failures=",failures)
	quit(0 if failures==0 else 1)
