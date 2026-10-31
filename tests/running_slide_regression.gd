extends SceneTree

const Actor = preload("res://scripts/warband/warband_body.gd")
const DT := 1.0/60.0
const FORWARD := Vector2(0,-1)
var failures := 0
var checks := 0
var scene: Node3D
var actor
var floor_body: StaticBody3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

func drive(frames: int, motion: Vector2 = Vector2.ZERO, fast: bool = false, held_crouch: bool = false) -> void:
	for frame in frames:
		await physics_frame
		actor.move_direction = motion
		actor.run_requested = fast
		actor.input_age = 0.0
		if held_crouch:
			actor.set_crouch(true)
		actor.step(DT,[actor])
		actor.rig.advance_animation(DT)

func relocate(point: Vector3 = Vector3(0,0,6)) -> void:
	actor.spawn_point = point
	actor.revive()
	await drive(25)
	check(actor.is_on_floor(),"Fixture settles on the isolated box floor")

func begin_slide() -> void:
	await relocate()
	await drive(24,FORWARD,true)
	check(Vector2(actor.get_real_velocity().x,actor.get_real_velocity().z).length()>6.0,"Fixture achieves real sprint velocity before crouch")
	actor.set_crouch(true)
	check(actor.slide.active,"Crouching during an achieved sprint starts a running slide")

func capsule_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.cover._capsule
	query.collision_mask = 1
	query.exclude = [actor.get_rid(),floor_body.get_rid()]
	query.transform = actor.cover._collider.global_transform
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func limb_error(rig: Node3D, joints: Dictionary) -> float:
	var largest := 0.0
	for side in ["left","right"]:
		var suffix := "l" if side == "left" else "r"
		for segment in [["shoulder","elbow","lowerarm"],["elbow","wrist","hand"],["hip","knee","calf"],["knee","ankle","foot"]]:
			var bone: int = rig.skeleton.find_bone(segment[2]+"_"+suffix)
			var rest_length: float = rig.skeleton.get_bone_rest(bone).origin.length()
			var actual_length: float = joints[side+"_"+segment[0]].distance_to(joints[side+"_"+segment[1]])
			largest = maxf(largest,absf(actual_length-rest_length))
	return largest

func check_replica_pose() -> void:
	var replica = Actor.new()
	scene.add_child(replica)
	replica.set_process(false)
	replica.rig.set_physics_process(false)
	var state: Dictionary = actor.snapshot()
	replica.apply_snapshot(state)
	# Settle the observer's initial authored-clip blend, then reapply the exact
	# authoritative animation clock. Never compare fields instead of the pose.
	replica.rig.advance_animation(0.25)
	replica.apply_snapshot(state)
	replica.collision_layer = 0
	replica.collision_mask = 0
	var source: Dictionary = actor.rig.get_joint_positions()
	var observed: Dictionary = replica.rig.get_joint_positions()
	var largest := 0.0
	for joint in source:
		var expected: Vector3 = actor.rig.to_local(source[joint])
		var actual: Vector3 = replica.rig.to_local(observed[joint])
		largest = maxf(largest,expected.distance_to(actual))
	check(largest<0.025,"Actor snapshots reconstruct the actual sliding skeleton (largest joint error %.4f m)" % largest)
	check(limb_error(replica.rig,observed)<0.003,"The replicated slide preserves connected imported limb lengths")
	replica.free()

func deceleration_and_pose() -> void:
	await begin_slide()
	var start: Vector3 = actor.position
	var previous_speed := INF
	var previous_progress := -1.0
	var first_speed := 0.0
	var decelerates := true
	var progresses := true
	var drains := true
	var samples := 0
	var max_limb_error := 0.0
	var feet := {}
	var max_foot_drift := 0.0
	var replicated := false
	for frame in 70:
		var before: Vector3 = actor.position
		var stamina_before: float = actor.stamina
		await drive(1,Vector2.ZERO,false,true)
		if not actor.slide.active:
			break
		var displacement: Vector3 = actor.position-before
		var actual_speed := Vector2(displacement.x,displacement.z).length()/DT
		if samples==0:
			first_speed = actual_speed
		decelerates = decelerates and actual_speed<=previous_speed+0.03
		progresses = progresses and actor.slide.progress>previous_progress
		drains = drains and absf(stamina_before-actor.stamina-19.0*DT)<0.002
		previous_speed = actual_speed
		previous_progress = actor.slide.progress
		samples += 1
		var joints: Dictionary = actor.rig.get_joint_positions()
		max_limb_error = maxf(max_limb_error,limb_error(actor.rig,joints))
		if actor.slide.progress>0.35 and actor.slide.progress<0.65:
			for foot in ["left_foot","right_foot"]:
				var local_foot: Vector3 = actor.rig.to_local(joints[foot])
				if not feet.has(foot):
					feet[foot] = local_foot
				max_foot_drift = maxf(max_foot_drift,local_foot.distance_to(feet[foot]))
			if not replicated:
				check_replica_pose()
				replicated = true
	check(samples>15 and samples<65 and not actor.slide.active,"The slide lasts a finite interval rather than ending instantly or looping")
	check(decelerates and progresses and previous_speed<first_speed*0.65,"Actual planar slide speed meaningfully decays monotonically while progress advances")
	check(drains,"Sliding without held Shift still spends the ordinary 19 stamina per second")
	check(start.z-actor.position.z>2.0 and absf(actor.position.x-start.x)<0.05,"Released WASD retains substantial forward slide momentum without lateral drift")
	check(actor.cover.crouch_requested and actor.cover.crouched and actor.cover._capsule.height<1.2,"Natural completion retains physical crouch instead of standing")
	check(max_limb_error<0.003,"Sliding never stretches imported arms or legs (error %.4f m)" % max_limb_error)
	check(replicated and feet.size()==2 and max_foot_drift<0.10,"Mid-slide feet stay body-relative rather than cycling a running gait (drift %.4f m)" % max_foot_drift)
	var rest: Vector3 = actor.position
	await drive(20)
	check(actor.position.distance_to(rest)<0.25,"No-input momentum stops after the finite slide")
	var restarted := false
	for frame in 65:
		await drive(1,FORWARD,true,true)
		restarted = restarted or actor.slide.active
	check(not restarted and actor.cover.crouched and Vector2(actor.velocity.x,actor.velocity.z).length()<2.3,"Held crouch intent and Shift never retrigger or sprint out of the ending crouch")
	actor.set_crouch(false)
	await drive(20)
	check(not actor.cover.crouched and actor.cover._capsule.height>1.79,"A new uncrouch request restores standing when headroom is clear")

func steering() -> void:
	await begin_slide()
	var entry: Vector3 = actor.slide.direction
	var previous: Vector3 = entry
	var greatest_turn := 0.0
	var largest_step := 0.0
	for frame in 25:
		await drive(1,Vector2.RIGHT)
		if not actor.slide.active:
			break
		var direction: Vector3 = actor.slide.direction
		greatest_turn = maxf(greatest_turn,entry.angle_to(direction))
		largest_step = maxf(largest_step,previous.angle_to(direction))
		previous = direction
	check(greatest_turn>0.05 and greatest_turn<deg_to_rad(50) and largest_step<deg_to_rad(6),"Steering bends the slide gradually within a bounded forward cone")
	var before: Vector3 = actor.position
	await drive(8,Vector2(0,1))
	check((actor.position-before).dot(entry)>0.1,"Reverse WASD cannot instantly reverse retained slide momentum")

func eligibility() -> void:
	await relocate()
	actor.run_requested = true
	actor.set_crouch(true)
	await drive(2,Vector2.ZERO,true)
	check(not actor.slide.active and actor.cover.crouch_requested,"Stationary Shift+C is an ordinary crouch, not a slide")
	await relocate()
	await drive(20,FORWARD)
	actor.set_crouch(true)
	check(not actor.slide.active and actor.cover.crouch_requested,"Walking into crouch does not slide")
	await relocate()
	await drive(20,FORWARD)
	actor.run_requested = true
	actor.set_crouch(true)
	check(not actor.slide.active,"Pressing Shift and crouch before achieving sprint speed cannot manufacture momentum")
	await relocate()
	await drive(24,FORWARD,true)
	actor.stamina = 0.0
	actor._exhausted = true
	actor.set_crouch(true)
	check(not actor.slide.active,"An exhausted runner cannot start a slide from residual velocity")
	await relocate()
	await drive(24,FORWARD,true)
	actor.press_jump(false)
	await drive(3,FORWARD,true)
	check(not actor.is_on_floor(),"Airborne eligibility fixture really left the floor")
	actor.set_crouch(true)
	check(not actor.slide.active,"Airborne sprint-crouch cannot begin a slide")
	await relocate()
	await drive(24,FORWARD,true)
	actor.press_jump(true)
	check(actor.roll.active,"Rolling eligibility fixture starts a real roll")
	actor.set_crouch(true)
	check(actor.roll.active and not actor.slide.active,"Crouch cannot replace an active roll with a running slide")
	await relocate()
	var wall := box(Vector3(8,3,0.4),Vector3(0,1.5,4.9))
	await drive(3)
	actor.toggle_cover(Vector3.FORWARD)
	await drive(20)
	check(actor.cover.active,"Cover eligibility fixture attaches to real wall geometry")
	await drive(12,Vector2.RIGHT,true)
	actor.set_crouch(true)
	check(actor.cover.active and not actor.slide.active and actor.cover.crouch_requested,"Fast attached movement still crouches in cover rather than becoming a running slide")
	wall.free()

func wall_stop() -> void:
	await begin_slide()
	var wall_z: float = actor.position.z-1.8
	var wall := box(Vector3(6,3,0.3),Vector3(0,1.5,wall_z))
	var stayed_in_front := true
	var stopped_at := -1
	for frame in 25:
		await drive(1,FORWARD,true)
		# The physics solver permits sub-safe_margin contact penetration before recovery.
		stayed_in_front = stayed_in_front and actor.position.z>=wall_z+0.45-actor.safe_margin
		if not actor.slide.active and stopped_at<0:
			stopped_at = frame
	check(stopped_at>=0 and stopped_at<20,"Blocked forward travel terminates the slide before its normal timeout")
	check(stayed_in_front,"A fast slide stops at a thin wall within the solver's contact tolerance, without tunneling")
	check(actor.cover.crouched and not actor.slide.active,"A wall-stopped slide remains crouched")
	wall.free()

func headroom_and_cancellation() -> void:
	await begin_slide()
	await drive(13)
	var roof := box(Vector3(8,0.2,12),Vector3(actor.position.x,1.4,actor.position.z))
	await drive(1)
	actor.press_jump(false)
	await drive(2)
	check(actor.slide.active and actor.is_on_floor() and capsule_clear(),"A headroom-blocked jump leaves the ongoing slide intact instead of forcing an unsafe stand")
	actor.set_crouch(false)
	await drive(5)
	check(not actor.slide.active and actor.cover.crouched and capsule_clear(),"Uncrouching cancels slide but preserves a safe crouched capsule beneath a ceiling")
	var before: Vector3 = actor.position
	actor.press_jump(false)
	await drive(4)
	check(actor.is_on_floor() and actor.position.y-before.y<0.03 and actor.velocity.y<=0 and capsule_clear(),"A blocked crouched jump cannot expand or take off through overhead geometry")
	roof.free()
	await drive(20)
	check(not actor.cover.crouched and actor.cover._capsule.height>1.79,"The pending stand completes after overhead clearance returns")
	for roll_requested in [false,true]:
		await begin_slide()
		await drive(8)
		actor.press_jump(roll_requested)
		await drive(2)
		check(not actor.slide.active and not actor.cover.crouch_requested and not actor.is_on_floor(),"Successful %s cancels the slide and releases crouch" % ("roll" if roll_requested else "jump"))
		check(actor.roll.active==roll_requested,"Slide cancellation preserves the requested jump versus modifier-roll action")

func combat_and_lifecycle() -> void:
	await begin_slide()
	await drive(8)
	check(actor.combat.begin_draw(),"Grounded sliding still permits a bow draw")
	await drive(5)
	check(actor.slide.active and actor.rig.phase in ["DRAWING","HOLDING"],"Bow drawing coexists with continued slide motion")
	actor.combat.stop()
	actor.rig.set_weapon("sword")
	check(actor.combat.begin_melee(),"Grounded sliding still permits a sword swing")
	await drive(2)
	check(actor.slide.active and actor.rig.phase=="MELEE","Starting a grounded sword swing does not silently cancel the slide")
	actor.take_damage(1000.0,actor.slot+1)
	# A campaign body goes DOWN on a lethal blow, and going down is what clears
	# the slide; the finisher is the next blow that lands.
	check(actor.downed and actor.alive and not actor.slide.active and actor.rig.slide_progress<0.0,
		"Going down immediately clears physical and visible sliding")
	actor.take_damage(1.0,actor.slot+1)
	check(not actor.alive and not actor.slide.active and actor.rig.slide_progress<0.0,
		"A finisher leaves no slide behind either")
	actor.set_crouch(true)
	check(not actor.slide.active,"Dead crouch intent cannot restart sliding")
	actor.revive()
	check(actor.alive and not actor.slide.active and not actor.cover.crouch_requested and actor.rig.slide_progress<0.0,"Revive removes stale slide and crouch intent")
	await drive(25)
	var before: Vector3 = actor.position
	await drive(10)
	check(actor.position.distance_to(before)<0.02 and actor.cover._capsule.height>1.79,"Revived actors stand still without residual slide displacement")
	actor.rig.set_weapon("bow")
	await begin_slide()
	actor.revive()
	check(not actor.slide.active and actor.rig.slide_progress<0.0,"Direct revive of a living slider also resets its movement and pose")

func run() -> void:
	Engine.physics_ticks_per_second = 60
	scene = Node3D.new()
	root.add_child(scene)
	floor_body = box(Vector3(44,1,44),Vector3(0,-0.5,0))
	actor = Actor.new()
	actor.authoritative = true
	scene.add_child(actor)
	actor.configure(1,"Slide regression",Vector3(0,0,6))
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	await deceleration_and_pose()
	await steering()
	await eligibility()
	await wall_stop()
	await headroom_and_cancellation()
	await combat_and_lifecycle()
	print("RUNNING_SLIDE_REGRESSION checks=",checks," failures=",failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
