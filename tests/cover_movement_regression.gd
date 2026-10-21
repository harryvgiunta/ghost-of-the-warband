extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const ShoulderCamera = preload("res://scripts/shoulder_camera.gd")
var failures := 0
var checks := 0
var scene: Node3D
var actor

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func box(size: Vector3, center: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

func drive(frames: int, motion: Vector2 = Vector2.ZERO, peek: bool = false) -> void:
	for frame in frames:
		await physics_frame
		actor.move_direction = motion
		actor.peek_requested = peek
		actor.input_age = 0.0
		actor.step(1.0/60.0,[actor])

func relocate(point: Vector3) -> void:
	actor.spawn_point = point
	actor.revive()
	await drive(30)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	box(Vector3(44,1,44),Vector3(0,-0.5,0))
	var wall := box(Vector3(6,3,0.6),Vector3(0,1.5,0))
	box(Vector3(4,1.4,1.5),Vector3(10,0.7,0))
	box(Vector3(4,3,0.6),Vector3(-10,1.5,0),PI/4.0)
	var tree := StaticBody3D.new()
	tree.position = Vector3(0,2.5,10)
	tree.collision_layer = 1
	tree.collision_mask = 0
	var trunk := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.55
	cylinder.height = 5
	trunk.shape = cylinder
	tree.add_child(trunk)
	scene.add_child(tree)
	actor = Actor.new()
	actor.authoritative = true
	actor.is_bot = false
	scene.add_child(actor)
	actor.configure(1,false,"Cover regression",Vector3(0,0,1.1))
	await drive(30)
	check(actor.cover.try_enter(Vector3.FORWARD),"A grounded character attaches to a nearby wall")
	await drive(30)
	check(actor.cover.active and not actor.cover.low and absf(actor.position.z-0.72)<0.02,"Cover settles at capsule-safe wall clearance")
	check(not actor.combat.begin_draw(),"Tucked cover cannot start an attack through the wall")
	var initial: Vector3 = actor.position
	await drive(30,Vector2(0,-1))
	check(actor.position.distance_to(initial)<0.02,"Pushing into cover never penetrates it")
	await drive(120,Vector2(1,0))
	check(actor.cover.active and actor.position.x>2.6 and actor.position.x<3.0,"Wall slide stops at the edge instead of walking into exposure")
	initial = actor.position
	await drive(30,Vector2.ZERO,true)
	check(actor.cover.peeking and actor.position.x>initial.x+0.55,"The selected shoulder physically steps out at a tall-cover edge")
	check(actor.combat.begin_draw(),"Exposed cover permits aiming and drawing")
	await drive(30)
	check(not actor.cover.peeking and actor.rig.phase=="READY" and actor.position.distance_to(initial)<0.03,"Releasing peek returns behind cover and cancels an unreleased draw")
	actor.peek_shoulder = -1
	await drive(20,Vector2.ZERO,true)
	check(not actor.cover.peeking,"The opposite shoulder cannot peek through the solid middle of a wall")
	actor.press_jump(true)
	check(not actor.cover.active and actor.roll.active,"Jump-roll exits cover before starting the roll")
	await relocate(Vector3(10,0,1.7))
	check(actor.cover.try_enter(Vector3.FORWARD),"Low stone debris supports cover")
	await drive(30)
	check(actor.cover.low and actor.cover._capsule.height<1.2,"Low cover reduces the real damage collider")
	var standing_head: float = actor.rig._bone_world(actor.rig._bones.Head).origin.y
	await drive(30,Vector2.ZERO,true)
	check(actor.cover.peeking and is_equal_approx(actor.cover._capsule.height,1.8),"Low-cover peek restores a standing collider")
	check(actor.rig._bone_world(actor.rig._bones.Head).origin.y>standing_head+0.4,"Low-cover peek raises the visible skeleton, not just the camera")
	await drive(20)
	actor.take_damage(1000,1)
	check(not actor.cover.active and not actor.alive,"Death clears cover and its reduced collider")
	actor.revive()
	check(not actor.cover.active and is_equal_approx(actor.cover._capsule.height,1.8),"Respawn restores ordinary standing movement")
	await relocate(Vector3(0,0,11.25))
	check(actor.cover.try_enter(Vector3.FORWARD),"Round tree trunks support cover")
	await drive(25)
	var first_normal: Vector3 = actor.cover.normal
	await drive(35,Vector2(1,0))
	var radial := Vector2(actor.position.x,actor.position.z-10).length()
	check(actor.cover.active and actor.cover.normal.dot(first_normal)<0.85 and absf(radial-0.97)<0.08,"Sliding follows a curved trunk without detaching or cutting through it")
	await relocate(Vector3(-10,0,0)+Vector3(sin(PI/4),0,cos(PI/4))*1.1)
	check(actor.cover.try_enter(Vector3(-sin(PI/4),0,-cos(PI/4))),"Rotated wall normals are detected geometrically")
	await drive(25,Vector2(cos(PI/4),-sin(PI/4)))
	check(actor.cover.active and actor.cover.normal.dot(Vector3(sin(PI/4),0,cos(PI/4)))>0.99,"Rotated cover preserves its surface normal while sliding")
	await relocate(Vector3(15,0,15))
	check(not actor.cover.try_enter(Vector3.FORWARD),"Bare ground is not cover and distant obstacles cannot attract the player")
	await relocate(Vector3(0,0,1.1))
	actor.cover.try_enter(Vector3.FORWARD)
	wall.queue_free()
	await drive(3)
	check(not actor.cover.active,"Removing the supporting obstacle releases cover")
	var camera := ShoulderCamera.new()
	var space := scene.get_world_3d().direct_space_state
	var focus := Vector3(0,1.5,-8)
	var right_position := camera.resolve(space,focus,Vector3.BACK,4.5)
	camera.swap()
	camera.update(0.05)
	var transition := camera.resolve(space,focus,Vector3.BACK,4.5)
	check(transition.x<right_position.x and transition.x>-0.70,"Shoulder switching traverses smoothly rather than teleporting")
	camera.update(1.0)
	var left_position := camera.resolve(space,focus,Vector3.BACK,4.5)
	check(left_position.x< -0.69 and right_position.x>0.69,"Both shoulder views frame opposite sides of the character")
	box(Vector3(4,4,0.2),focus+Vector3(0,0,2))
	await physics_frame
	var blocked := camera.resolve(space,focus,Vector3.BACK,4.5)
	check(blocked.z<focus.z+1.7,"Camera volume stops before a thin wall instead of clipping its near plane")
	var sphere := SphereShape3D.new()
	sphere.radius = ShoulderCamera.CAMERA_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	var recovered := camera.resolve(space,focus+Vector3(0,0,1.95),Vector3.FORWARD,3.0)
	query.transform.origin = recovered
	check(space.intersect_shape(query,1).is_empty(),"Camera recovers when its starting sphere overlaps world geometry")
	print("COVER_MOVEMENT_REGRESSION checks=",checks," failures=",failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
