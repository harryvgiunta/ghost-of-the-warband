extends SceneTree
## Cinder devil packs must circle and flank rather than charge in a line, mix
## leaps, slides and shared quick steps, and commit at most three attackers.
## The presentation is the imported GLB: seven authored clips, a 2.1 m frame
## and a skinned body the blood field can measure.

const Enemy = preload("res://scripts/enemy.gd")
const DevilVisual = preload("res://scripts/cinder_devil_visual.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")

const CLIP_KEYS := ["idle", "walk", "run", "attack", "shoot", "hit", "death"]

var failures := 0
var checks := 0
var reward_received := -1

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
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(60,1,60)
	var floor_collision := CollisionShape3D.new()
	floor_collision.position = Vector3(0,-0.5,0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	var dummy := CharacterBody3D.new()
	dummy.collision_layer = 4
	dummy.collision_mask = 0
	dummy.position = Vector3(0,0.05,0)
	world.add_child(dummy)

	# --- the asset ---------------------------------------------------------
	var visual := DevilVisual.new()
	world.add_child(visual)
	await process_frame
	check(visual._skeleton != null and visual._player != null,
		"The cinder devil loads the imported skeleton and its AnimationPlayer")
	var player: AnimationPlayer = visual._player
	for key in CLIP_KEYS:
		check(player.has_animation(str(DevilVisual.CLIPS[key])),
			"The imported cinder devil carries the %s clip" % key)
	for key in ["idle", "walk", "run"]:
		check(player.get_animation(str(DevilVisual.CLIPS[key])).loop_mode == Animation.LOOP_LINEAR,
			"%s loops" % key)
	for key in ["attack", "shoot", "hit", "death"]:
		check(player.get_animation(str(DevilVisual.CLIPS[key])).loop_mode == Animation.LOOP_NONE,
			"%s is a one-shot clip" % key)
	check(is_equal_approx(player.get_animation("Cinder_Attack").length, 0.80),
		"The attack clip is the authored 0.80 s")
	check(is_equal_approx(player.get_animation("Cinder_Shoot").length, 0.55),
		"The draw clip is the authored 0.55 s")

	var mesh_bounds := AABB()
	var first_mesh := true
	var surface_count := 0
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		var node := mesh as MeshInstance3D
		surface_count += node.mesh.get_surface_count()
		var box: AABB = node.global_transform*node.get_aabb()
		if first_mesh:
			mesh_bounds = box
			first_mesh = false
		else:
			mesh_bounds = mesh_bounds.merge(box)
	check(mesh_bounds.size.y > 2.0 and mesh_bounds.size.y < 2.8,
		"The authored frame stands over two metres tall")
	check(mesh_bounds.position.y > -0.03 and mesh_bounds.position.y < 0.05,
		"The devil's soles rest on the ground plane")
	check(surface_count == 8, "The mesh carries one surface per authored material")

	# The blood field measures a real skinned body, not a triangle soup.
	check(visual.blood_anchor() != visual and visual.blood_anchor().find_child("Skeleton3D", true, false) != null,
		"Blood stains ride the imported skeleton")

	# --- the pack AI -------------------------------------------------------
	var devils: Array = []
	var start: Array[Vector3] = []
	for index in 5:
		var devil := Enemy.new()
		devil.kind = 2
		devil.pack_index = index
		devil.player = dummy
		devil.safe_center = Vector3(1000,0,1000)
		var angle := TAU*float(index)/5.0
		devil.position = Vector3(cos(angle)*5.0,0.12,sin(angle)*5.0)
		world.add_child(devil)
		devils.append(devil)
	await physics_frame
	await physics_frame

	var first = devils[0]
	var capsule := first.get_child(0) as CollisionShape3D
	check(first.get_display_name() == "Cinder devil", "The pack enemy is named Cinder devil")
	check(is_equal_approx(first.max_health,24.0), "Cinder devils are fragile at 24 health")
	check(capsule != null and is_equal_approx(capsule.shape.radius,0.34) and is_equal_approx(capsule.shape.height,2.15),
		"Cinder devils use the authored 2.15 m capsule")
	check(first._devil != null and first._body.get_child_count() == 1,
		"Cinder devils attach the imported visual")
	check(first.head_hit_profile() == Vector2(0.26,0.16), "The horned head keeps its authored hit profile")
	var head_height: float = first.head_hitbox_center().y-first.global_position.y
	check(head_height > 1.55 and head_height < 2.15, "The head zone sits on the animated skull")
	check(is_equal_approx(first.get_aim_position().y-first.global_position.y,1.25),
		"Aim resolves at the chest of the taller frame")
	check(first._dodge != null, "Cinder devils own a shared quick-step controller")
	check(is_equal_approx(first._dodge.travel,DodgeStep.TRAVEL*0.5), "Devil side steps cover half the player distance")
	check(is_equal_approx(first._dodge.duration,0.22), "Devil side steps use the quicker 0.22 s timing")

	var hits: Array[float] = []
	for devil in devils:
		devil.attacked.connect(func(_attacker, amount, _victim): hits.append(amount))
		start.append(devil.global_position)
	var seen := {}
	var step_frames := 0
	var jump_frames := 0
	var slide_frames := 0
	var max_attackers := 0
	var paths: Array[float] = [0.0,0.0,0.0,0.0,0.0]
	var previous: Array[Vector3] = [start[0],start[1],start[2],start[3],start[4]]
	for frame in 600:
		await physics_frame
		var attackers := 0
		for index in devils.size():
			var devil = devils[index]
			seen[devil.state] = true
			if devil._dodge.active:
				step_frames += 1
			if not devil.is_on_floor():
				jump_frames += 1
			if devil.state == "SLIDE":
				slide_frames += 1
			if devil.state in ["WINDUP","STRIKE","DIVE"]:
				attackers += 1
			var move: Vector3 = devil.global_position-previous[index]
			paths[index] += Vector2(move.x,move.z).length()
			previous[index] = devil.global_position
		max_attackers = maxi(max_attackers,attackers)
	for state in ["CIRCLE","STEP","LEAP","SLIDE","DIVE","WINDUP","STRIKE","RECOVER"]:
		check(seen.has(state), "Cinder devil pack uses the " + state + " state")
	check(step_frames > 0, "Cinder devils use quick side steps around the player")
	check(jump_frames > 0, "Cinder devils leap during the fight")
	check(slide_frames > 0, "Cinder devils slide through the flank")
	check(hits.size() > 0, "The pack commits and lands claw attacks")
	var valid_hit := true
	for amount in hits:
		if not (is_equal_approx(amount,8.0) or is_equal_approx(amount,10.0)):
			valid_hit = false
	check(valid_hit, "Claw and landing-pounce damage stay at 8 and 10")
	check(max_attackers <= Enemy.DEVIL_MAX_ATTACKERS, "No more than three pack members commit to an attack at once")
	for index in devils.size():
		var straight := Vector2(devils[index].global_position.x-start[index].x,devils[index].global_position.z-start[index].z).length()
		check(paths[index] > 6.0 and paths[index] > straight*1.5, "Devil %d circles instead of charging in a straight line" % index)

	var staggered = devils[0]
	staggered.stagger(0.8)
	check(staggered.state == "STAGGER" and not staggered._warning.visible, "A parry cancels the devil's attack telegraph")
	check(not staggered._dodge.active, "A parry also cancels an in-flight quick step")
	await create_timer(0.9).timeout
	check(staggered.state != "STAGGER", "The devil recovers from parry stagger and rejoins the pack")

	for devil in devils:
		devil.queue_free()
	await process_frame

	# --- weapon roles ------------------------------------------------------
	var dagger_devil := Enemy.new()
	dagger_devil.kind = 2
	dagger_devil.devil_weapon = "dagger"
	dagger_devil.pack_index = 20
	dagger_devil.player = dummy
	dagger_devil.safe_center = Vector3(1000,0,1000)
	dagger_devil.position = Vector3(15,0.12,15)
	world.add_child(dagger_devil)
	dagger_devil.set_physics_process(false)
	await process_frame
	check(dagger_devil._devil._weapon == "dagger" and dagger_devil._devil._melee != null, "Dagger devils hold a dagger mesh")
	check(dagger_devil.held_weapon_id() == "dagger_iron", "Dagger devils drop the iron dagger")
	check(is_equal_approx(dagger_devil._attack_damage,6.0) and is_equal_approx(dagger_devil._attack_reach,1.6), "Daggers use the short 6-damage reach profile")
	var sword_devil := Enemy.new()
	sword_devil.kind = 2
	sword_devil.devil_weapon = "sword"
	sword_devil.pack_index = 21
	sword_devil.player = dummy
	sword_devil.safe_center = Vector3(1000,0,1000)
	sword_devil.position = Vector3(18,0.12,18)
	world.add_child(sword_devil)
	sword_devil.set_physics_process(false)
	await process_frame
	check(sword_devil._devil._weapon == "sword" and sword_devil._devil._melee != null, "Sword devils hold a short sword mesh")
	check(sword_devil.held_weapon_id() == "sword_short", "Sword devils drop the shortsword")
	check(is_equal_approx(sword_devil._attack_damage,11.0) and is_equal_approx(sword_devil._attack_reach,2.0), "Short swords use the longer 11-damage reach profile")
	var bow_devil := Enemy.new()
	bow_devil.kind = 2
	bow_devil.devil_weapon = "bow"
	bow_devil.pack_index = 22
	bow_devil.player = dummy
	bow_devil.safe_center = Vector3(1000,0,1000)
	bow_devil.position = Vector3(9,0.12,9)
	world.add_child(bow_devil)
	await physics_frame
	check(bow_devil._devil._weapon == "bow" and bow_devil._devil._bow != null, "Bow devils hold a bow mesh")
	check(bow_devil.held_weapon_id() == "bow_recurve", "Bow devils drop the recurve bow")
	check(is_equal_approx(bow_devil._attack_damage,7.0) and is_equal_approx(bow_devil._attack_reach,0.0), "Bow devils use the 7-damage ranged profile")
	var saw_shoot := false
	for frame in 360:
		await physics_frame
		if bow_devil.state == "SHOOT":
			saw_shoot = true
	check(saw_shoot, "Bow devils enter the ranged shoot state")
	check(bow_devil.shots_fired > 0, "Bow devils release real arrow projectiles")
	dagger_devil.queue_free()
	sword_devil.queue_free()
	bow_devil.queue_free()
	await process_frame

	# --- death -------------------------------------------------------------
	var doomed := Enemy.new()
	doomed.kind = 2
	doomed.pack_index = 5
	doomed.player = dummy
	doomed.safe_center = Vector3(1000,0,1000)
	doomed.position = Vector3(8,0.12,8)
	doomed.defeated.connect(func(_enemy, amount): reward_received = amount)
	world.add_child(doomed)
	await physics_frame
	doomed.take_damage(999.0,0)
	check(not doomed.alive and doomed.state == "DEAD", "Lethal damage puts a devil into its death state")
	check(doomed._devil.is_dead(), "The devil visual routes death through its authored clip")
	check(reward_received == 6, "A Cinder devil awards six gold")
	check(doomed.held_weapon_id().is_empty(), "A claw devil drops no weapon")
	await create_timer(0.6).timeout
	check(doomed._devil._death_time > 0.4, "The devil death clip advances even while the corpse is held")

	# --- clip selection and posture ---------------------------------------
	visual.set_action("WINDUP",0.15)
	visual._process(0.016)
	check(visual.get_clip_name() == "Cinder_Attack", "Windup plays the authored attack clip")
	var windup_at: float = visual._player.current_animation_position
	check(windup_at > 0.10 and windup_at < 0.32, "Windup seeks into the authored rear-back, ahead of the impact")
	visual.set_action("STRIKE",0.08)
	visual._process(0.016)
	check(visual._player.current_animation_position >= 0.38, "The strike frame reaches the authored impact at 0.38 s")
	visual.set_action("SHOOT",0.30)
	visual._process(0.016)
	check(visual.get_clip_name() == "Cinder_Shoot", "The bow state plays the draw clip")
	check(visual._player.current_animation_position >= 0.28, "The draw clip reaches its release frame")
	visual.set_action("STAGGER",0.10)
	visual._process(0.016)
	check(visual.get_clip_name() == "Cinder_Hit", "A stagger plays the authored hit flinch")
	visual.set_action("CIRCLE",0.0)
	visual.set_step(0.5,Vector3.RIGHT)
	visual._process(0.016)
	check(absf(visual._instance.rotation.z) > 0.02, "A quick step leans the body onto the lead foot")
	visual.set_step(-1,Vector3.RIGHT)
	visual.set_slide(1.0)
	for frame in 12:
		visual._process(0.016)
	check(visual._instance.position.y < -0.12 and visual._instance.rotation.x > 0.25, "The slide drops and pitches the body")
	visual.set_slide(-1)
	var standing_head: float = visual.head_hitbox_center().y
	visual.die()
	for frame in 80:
		visual._process(0.016)
	check(visual.get_clip_name() == "Cinder_Death", "Death plays the authored collapse")
	check(visual._death_held, "The death clip holds its final pose")
	check(standing_head - visual.head_hitbox_center().y > 0.6,
		"The head drops over half a metre as the corpse goes down")

	world.queue_free()
	await process_frame
	print("DEVIL_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
