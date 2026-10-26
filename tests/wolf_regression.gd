extends SceneTree

const WOLF := preload("res://assets/characters/ironwood_wolf.glb")
const WolfVisual = preload("res://scripts/wolf_visual.gd")
const Enemy = preload("res://scripts/enemy.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# Imported asset contract: geometry, orientation, clips, texture.
	var scene := WOLF.instantiate()
	world.add_child(scene)
	await process_frame
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh := scene.find_child("WolfMesh", true, false) as MeshInstance3D
	check(player != null, "Imported wolf scene has an AnimationPlayer")
	check(skeleton != null, "Imported wolf scene has a Skeleton3D")
	check(mesh != null, "Imported wolf scene has the skinned mesh")
	if player and skeleton and mesh:
		var names := player.get_animation_list()
		for required in ["Wolf_Idle_Loop", "Wolf_Trot_Loop", "Wolf_Attack", "Wolf_Death"]:
			check(required in names, "Imported wolf has clip " + required)
		check(is_equal_approx(player.get_animation("Wolf_Idle_Loop").length, 2.4), "Idle clip is 2.4 seconds")
		check(is_equal_approx(player.get_animation("Wolf_Trot_Loop").length, 0.6), "Trot clip is 0.6 seconds")
		check(is_equal_approx(player.get_animation("Wolf_Attack").length, 1.5), "Attack clip is 1.5 seconds")
		check(is_equal_approx(player.get_animation("Wolf_Death").length, 0.45), "Death clip is 0.45 seconds")
		check(player.get_animation("Wolf_Idle_Loop").loop_mode == Animation.LOOP_LINEAR, "Idle loops")
		check(player.get_animation("Wolf_Trot_Loop").loop_mode == Animation.LOOP_LINEAR, "Trot loops")
		check(player.get_animation("Wolf_Attack").loop_mode == Animation.LOOP_NONE, "Attack does not loop")
		check(player.get_animation("Wolf_Death").loop_mode == Animation.LOOP_NONE, "Death does not loop")
		check(skeleton.get_bone_count() == 37, "Wolf skeleton has the expected 37 bones")
		for bone in ["root", "pelvis", "head", "jaw", "front_paw_l", "hind_toes_r", "tail_04"]:
			check(skeleton.find_bone(bone) >= 0, "Wolf skeleton has bone " + bone)
		var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("head")).origin
		var tail_rest := skeleton.get_bone_global_rest(skeleton.find_bone("tail_04")).origin
		check(head_rest.z < -0.5, "Wolf faces gameplay -Z")
		check(tail_rest.z > 0.5, "Wolf tail extends behind the body")
		var bounds := mesh.get_aabb()
		check(absf(bounds.position.y) < 0.03, "Wolf paws sit at the ground plane")
		check(bounds.size.y > 1.0 and bounds.size.y < 1.3, "Wolf height stays inside the captured capsule scale")
		check(bounds.size.z > 1.8 and bounds.size.z < 2.4, "Wolf body length reads as a quadruped, not a stretched sphere")
		check(bounds.size.x > 0.4 and bounds.size.x < 0.7, "Wolf torso width is plausible")
		var surface_material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		check(surface_material != null and surface_material.albedo_texture != null, "Fur surface has an embedded albedo texture")
		if surface_material and surface_material.albedo_texture:
			check(surface_material.albedo_texture.get_width() == 1024 and surface_material.albedo_texture.get_height() == 1024, "Coat texture is 1024x1024")
		# No authored root translation may leak into gameplay movement.
		var root_bone := skeleton.find_bone("root")
		for clip in ["Wolf_Idle_Loop", "Wolf_Trot_Loop", "Wolf_Attack", "Wolf_Death"]:
			var length: float = player.get_animation(clip).length
			for time in [0.0, length * 0.5, length]:
				player.play(clip)
				player.seek(time, true)
				player.pause()
				await process_frame
				skeleton.force_update_all_bone_transforms()
				check(skeleton.get_bone_global_pose(root_bone).origin.length() < 0.001, "Clip " + clip + " keeps the root bone stationary")
	scene.queue_free()
	await process_frame

	# Visual controller: bite impact and held death.
	var visual := WolfVisual.new()
	world.add_child(visual)
	await process_frame
	await process_frame
	var visual_skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	check(visual.get_clip_name() == "Wolf_Idle_Loop", "Wolf visual starts in idle")
	visual.set_combat("WINDUP", 0.0)
	await create_timer(0.12).timeout
	visual.set_combat("WINDUP", 0.55)
	await process_frame
	await process_frame
	visual_skeleton.force_update_all_bone_transforms()
	var jaw_bone := visual_skeleton.find_bone("jaw")
	var jaw_open: Quaternion = visual_skeleton.get_bone_global_pose(jaw_bone).basis.get_rotation_quaternion()
	var jaw_windup: Vector3 = visual_skeleton.get_bone_global_pose(jaw_bone).origin
	var head_windup: Vector3 = visual_skeleton.get_bone_global_pose(visual_skeleton.find_bone("head")).origin
	visual.set_combat("WINDUP", 0.65)
	await process_frame
	await process_frame
	visual_skeleton.force_update_all_bone_transforms()
	var jaw_impact: Quaternion = visual_skeleton.get_bone_global_pose(jaw_bone).basis.get_rotation_quaternion()
	var jaw_impact_origin: Vector3 = visual_skeleton.get_bone_global_pose(jaw_bone).origin
	var head_impact: Vector3 = visual_skeleton.get_bone_global_pose(visual_skeleton.find_bone("head")).origin
	check(visual.get_clip_name() == "Wolf_Attack", "Windup starts the authored attack clip")
	check(jaw_open.angle_to(jaw_impact) > 0.25, "Bite closes between windup and the 0.65 s impact")
	check(jaw_impact_origin.z < visual_skeleton.get_bone_global_rest(jaw_bone).origin.z - 0.06, "Bite drives the jaw forward at impact")
	visual_skeleton.force_update_all_bone_transforms()
	var head_bone := visual_skeleton.find_bone("head")
	var pelvis_bone := visual_skeleton.find_bone("pelvis")
	var standing_head_pelvis: float = visual_skeleton.get_bone_global_pose(head_bone).origin.distance_to(
		visual_skeleton.get_bone_global_pose(pelvis_bone).origin)
	visual.die()
	check(visual.is_dead(), "Wolf visual enters its death state")
	check(visual.get_clip_name() == "Wolf_Death", "Death clip name is kept for presentation")
	check(CorpsePhysics.is_limp(visual), "Wolf corpse hands its skeleton to the physical ragdoll")
	var simulator := visual_skeleton.get_node_or_null("CorpseRagdoll") as PhysicalBoneSimulator3D
	check(simulator != null and simulator.get_child_count() >= 10,
		"Wolf corpse builds a physical bone chain")
	var head_physical: PhysicalBone3D = null
	var pelvis_physical: PhysicalBone3D = null
	if simulator != null:
		for child in simulator.get_children():
			if not child is PhysicalBone3D:
				continue
			var physical := child as PhysicalBone3D
			if physical.get_bone_id() == head_bone:
				head_physical = physical
			elif physical.get_bone_id() == pelvis_bone:
				pelvis_physical = physical
	check(head_physical == null, "Wolf head is welded into the rigid torso and cannot spin")
	check(pelvis_physical != null, "Wolf pelvis drives the rigid torso ragdoll")
	await create_timer(1.5).timeout
	if pelvis_physical != null:
		check(pelvis_physical.global_position.y < 0.6,
			"Limp wolf falls onto the ground under gravity")
		check(pelvis_physical.collision_layer == 0 and pelvis_physical.collision_mask == 1,
			"Corpse bones stop blocking bodies while still catching the world")
	var deadline := Time.get_ticks_msec() + 8000
	while CorpsePhysics.is_limp(visual) and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	check(not CorpsePhysics.is_limp(visual), "Ragdoll settles and bakes within the corpse window")
	visual_skeleton.force_update_all_bone_transforms()
	var dead_head: Vector3 = visual_skeleton.get_bone_global_pose(head_bone).origin
	var dead_pelvis: Vector3 = visual_skeleton.get_bone_global_pose(pelvis_bone).origin
	check(dead_head.y < 0.6, "Baked limp pose keeps the body on the ground")
	check(absf(dead_head.distance_to(dead_pelvis) - standing_head_pelvis) < 0.03,
		"The head keeps its torso offset instead of spinning")
	await create_timer(0.25).timeout
	visual_skeleton.force_update_all_bone_transforms()
	var held_head: Vector3 = visual_skeleton.get_bone_global_pose(head_bone).origin
	check(held_head.distance_to(dead_head) < 0.05, "Baked corpse pose is held after the ragdoll retires")
	visual.queue_free()
	await process_frame

	# Enemy cutover: wolf presentation only, built from the imported visual.
	var dummy_player := CharacterBody3D.new()
	world.add_child(dummy_player)
	dummy_player.position = Vector3(0, 0, 0)
	var wolf_enemy := Enemy.new()
	wolf_enemy.kind = 0
	wolf_enemy.player = dummy_player
	wolf_enemy.safe_center = Vector3(1000, 0, 1000)
	wolf_enemy.position = Vector3(0, 0, -2.0)
	world.add_child(wolf_enemy)
	await physics_frame
	await physics_frame
	check(wolf_enemy._wolf != null, "Wolf enemy attaches its imported visual")
	check(wolf_enemy._body.get_child_count() == 1 and wolf_enemy._body.get_child(0) == wolf_enemy._wolf, "Wolf body contains only the imported visual")
	wolf_enemy.take_damage(999.0, 0)
	await create_timer(0.55).timeout
	check(wolf_enemy.state == "DEAD" and wolf_enemy._wolf.is_dead(), "Wolf enemy routes lethal damage through the authored death")
	check(wolf_enemy.scale == Vector3.ONE and wolf_enemy._body.scale == Vector3.ONE, "Wounded wolf keeps root and visual container scale identity during the collapse")
	wolf_enemy.queue_free()
	await process_frame

	world.queue_free()
	await process_frame
	print("WOLF_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
