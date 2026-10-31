extends SceneTree

const Actor = preload("res://scripts/warband/warband_body.gd")
var failures := 0
var checks := 0
var scene: Node3D
var actor
var floor_body: StaticBody3D
var attack_shots: Array[Dictionary] = []

func record_attack(origin: Vector3, direction: Vector3, _speed: float, charge: float) -> void:
	var desired: Vector3 = (actor.combat.aim_point-origin).normalized()
	attack_shots.append({"origin":origin,"direction":direction,"charge":charge})
	check(actor.cover.peeking,"Automatic release waits for real physical exposure")
	check(direction.dot(desired)>0.999,"Emitted arrow travels toward the selected aim rather than the protected facing")
	check(actor.rig.active_bow.get_arrow_direction().dot(desired)>0.98,"The visible bow points along the emitted arrow at release")
	var horizontal := Vector3(desired.x,0,desired.z).normalized()
	check((-actor.rig.global_basis.z).dot(horizontal)>0.95,"The character faces the attack aim when the arrow leaves")

func automatic_attack_scenarios() -> void:
	actor.combat.shot.connect(record_attack)
	for side in [0,1,-1]:
		await relocate(Vector3(10,0,1.7) if side==0 else Vector3(0,0,1.1))
		actor.set_crouch(true)
		await drive(20)
		check(actor.cover.try_enter(Vector3.FORWARD),"Direct attack fixture attaches from crouch")
		await drive(20)
		if side!=0:
			await drive(120,Vector2(float(side),0))
		actor.peek_shoulder = 1 if side==0 else side
		await drive(1)
		actor.combat.cover_side = -actor.peek_shoulder
		actor.combat.set_aim(actor.position+Vector3(0,1.3,-15))
		var anchor: Vector3 = actor.position
		var count := attack_shots.size()
		check(actor.combat.begin_draw(),"Direct bow input accepts top and either crouched edge without RMB")
		await drive(24)
		check(actor.cover.active and actor.cover.peeking and actor.cover.lean.length()>0.95,"Direct held bow physically exposes top and both shoulders")
		check(actor.rig.active_bow.get_arrow_direction().dot((actor.combat.aim_point-actor.rig.get_arrow_origin()).normalized())>0.98,"Held direct bow visibly aims into the attack, not away from cover")
		if side!=0:
			check(crouched_capsule_clear() and actor.position.distance_to(anchor)>0.35 and actor.position.distance_to(anchor)<0.52,"Automatic side attack preserves crouch and modest physical travel")
		actor.combat.release_draw()
		await drive(45)
		check(attack_shots.size()==count+1 and actor.cover.active and actor.cover.lean.is_zero_approx() and crouched_capsule_clear(),"A direct shot returns to crouched sticky cover without another arrow")
		await drive(60)
		count = attack_shots.size()
		check(actor.combat.begin_draw(),"Quick direct press starts a fresh draw after recovery")
		await drive(1)
		var released_charge: float = actor.rig.draw_amount
		actor.combat.release_draw()
		check(attack_shots.size()==count,"Quick release cannot fire before the capsule reaches exposure")
		await drive(50)
		check(attack_shots.size()==count+1,"Quick press-release queues exactly one arrow")
		if attack_shots.size()>count:
			check(absf(float(attack_shots[count].charge)-released_charge)<0.001,"Waiting for exposure does not add charge after release")
		actor.combat.release_draw()
		await drive(60)
		check(attack_shots.size()==count+1 and actor.rig.phase=="READY","Repeated release cannot duplicate a deferred arrow or skip recovery")
		count = attack_shots.size()
		actor.combat.begin_draw()
		actor.combat.release_draw()
		actor.combat.stop()
		await drive(50)
		check(attack_shots.size()==count and not actor.combat.wants_cover_exposure() and actor.cover.lean.is_zero_approx(),"Canceling pending exposure leaves no latent shot or lean")
		actor.rig.set_weapon("sword")
		actor.rig.set_sword(0)
		check(actor.combat.begin_melee(),"A melee attack accepts top and either side without a peek prerequisite")
		check(not actor.cover.active and actor.rig.phase=="MELEE" and actor.position.distance_to(anchor)<0.03 and (-actor.rig.global_basis.z).dot(Vector3.FORWARD)>0.95,"Melee immediately breaks attachment and faces aim without moving to a peek destination")
		await drive(24,Vector2(0,1))
		check(not actor.cover.active and actor.rig.phase=="MELEE" and actor.position.z>anchor.z+0.4,"Movement away from the wall is free during the swing, not constrained to its tangent")
		await drive(90)
		check(not actor.cover.active and actor.cover.lean.is_zero_approx() and crouched_capsule_clear(),"Sword recovery stays detached and preserves manual crouch")
		actor.rig.set_weapon("bow")
		if side!=0:
			check(actor.cover.try_enter(Vector3.FORWARD),"Cover can be explicitly reacquired after a melee exit")
			await drive(20)
			actor.peek_shoulder = -side
			await drive(1)
			check(not actor.combat.begin_draw(),"Wrong-edge direct bow cannot pass through the wall")
			actor.rig.set_weapon("sword")
			check(actor.combat.begin_melee() and not actor.cover.active and actor.rig.phase=="MELEE","A blocked shoulder does not prevent melee from breaking attachment")
			actor.rig.set_weapon("bow")
			await drive(30)
			check(attack_shots.size()==count and not actor.cover.active and actor.cover.lean.is_zero_approx(),"A rejected bow and detached sword leave no pending exposure or arrow")
	await relocate(Vector3(10,0,1.7))
	actor.set_crouch(true)
	await drive(20)
	var ceiling := box(Vector3(6,0.2,2),Vector3(10,1.3,1.65))
	await drive(3)
	actor.cover.try_enter(Vector3.FORWARD)
	await drive(20)
	var count := attack_shots.size()
	check(not actor.combat.begin_draw(),"Headroom blocks automatic top bow exposure")
	actor.rig.set_weapon("sword")
	check(actor.combat.begin_melee() and not actor.cover.active and actor.rig.phase=="MELEE" and crouched_capsule_clear(),"Low headroom permits a crouched melee exit without expanding the capsule")
	actor.rig.set_weapon("bow")
	ceiling.queue_free()
	await drive(45)
	check(attack_shots.size()==count and crouched_capsule_clear() and not actor.cover.peeking,"Removing blocked headroom cannot resurrect rejected attacks")
	actor.combat.shot.disconnect(record_attack)

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

func drive(frames: int, motion: Vector2 = Vector2.ZERO, peek: bool = false, fast: bool = false) -> void:
	for frame in frames:
		await physics_frame
		actor.move_direction = motion
		actor.peek_requested = peek
		actor.run_requested = fast
		actor.input_age = 0.0
		actor.step(1.0/60.0,[actor])

func relocate(point: Vector3) -> void:
	actor.spawn_point = point
	actor.revive()
	await drive(30)

## Sticky movement is opt-in: a press on a surface that stands in front of the
## body, and only that. This is the report - "players automatically sticky wall" -
## checked from both ends: nothing near cover holds a body that never pressed F,
## and a body that leaves cover stays out until it presses F again.
func sticky_toggle_scenarios() -> void:
	await relocate(Vector3(0,0,1.1))
	check(not actor.cover.try_enter(Vector3.BACK),"A wall behind the player is not a surface F sticks to")
	check(not actor.cover.active,"and a refused press leaves sticky movement off")
	await drive(20,Vector2(0,-1))
	check(not actor.cover.active,"Walking into cover without a press never sticks to it")
	check(actor.cover.try_enter(Vector3.FORWARD),"The same wall in front of the player is cover")
	await drive(20)
	check(actor.cover.active,"and the press holds the body on it")
	# Off the surface is off the surface: input that points away peels the body
	# free, and walking back in does not re-arm it.
	await drive(20,Vector2(0,1))
	check(not actor.cover.active,"Walking off the surface releases sticky movement")
	await drive(45,Vector2(0,-1))
	check(not actor.cover.active and actor.position.z<0.8,"Walking back to the surface does not reattach the body")
	check(actor.cover.try_enter(Vector3.FORWARD),"A fresh press sticks it again")
	await drive(20)
	check(actor.cover.active,"and the body holds the wall again")
	actor.press_jump(false)
	await drive(2)
	check(not actor.cover.active,"A jump leaves sticky movement off")
	await drive(45)
	check(actor.is_on_floor() and not actor.cover.active,"Landing on the same ground does not put it back")

## A real generated trunk, not a stand-in cylinder: the mesh and the collision it
## plants are one profile, so the sticky point is the bark the player can see. This
## is the report - "some trees have sticky points out of proportion to the graphics"
## - measured end to end: the anchor stands on the trunk's own drawn footprint and
## the standing capsule is outside it.
func tree_trunk_scenarios() -> void:
	var species: Dictionary = WorldStyle.frontier().species_by_id("ironoak")
	var variants: Array = TreeKit.build_variants(species, 4242)
	check(not variants.is_empty() and float(variants[0].get("trunk_height", 0.0)) > 0.0,
		"the ironoak ships a trunk the collision can be cut from")
	if variants.is_empty():
		return
	var variant: Dictionary = variants[0]
	var scale := 1.2
	var footprint: float = TreeKit.trunk_footprint(variant, scale)
	var body := StaticBody3D.new()
	body.position = Vector3(0, 0, 20)
	body.collision_layer = 1
	body.collision_mask = 0
	scene.add_child(body)
	TreeKit.add_trunk_solids(body, Vector3.ZERO, variant, scale)
	await relocate(Vector3(0,0,20.0+footprint+1.0))
	check(actor.cover.try_enter(Vector3.FORWARD),"A generated tree trunk is cover")
	await drive(25)
	var stand: float = Vector2(actor.position.x,actor.position.z-20.0).length()
	check(actor.cover.active and absf(stand-(footprint+0.42))<0.04,
		"the anchor stands on the trunk's drawn footprint (%.2f m, footprint %.2f + 0.42)"
		% [stand, footprint])
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.cover._capsule
	query.collision_mask = 1
	query.exclude = [actor.get_rid(),floor_body.get_rid()]
	query.transform = actor.cover._collider.global_transform
	check(scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),
		"and the standing capsule is outside the bark, not buried in the flare")
	body.queue_free()
	await drive(3)

func crouched_capsule_clear() -> bool:
	var collider: CollisionShape3D = actor.cover._collider
	var capsule: CapsuleShape3D = collider.shape
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid(),floor_body.get_rid()]
	query.transform = collider.global_transform
	return capsule.height <= 1.121 and absf(collider.position.y-capsule.height*0.5)<0.001 \
		and scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func crouched_cover_scenarios() -> void:
	for side in [1,-1]:
		await relocate(Vector3(0,0,1.1))
		actor.set_crouch(true)
		await drive(20)
		check(actor.cover.try_enter(Vector3.FORWARD),"A manually crouched capsule acquires tall cover")
		await drive(20)
		check(crouched_capsule_clear() and absf(actor.position.z-0.72)<0.02,"Crouched entry reaches the protected anchor without penetration")
		actor.set_crouch(false)
		await drive(20)
		check(actor.cover.active and is_equal_approx(actor.cover._capsule.height,1.8),"Crouch can be toggled off while attached to tall cover")
		actor.set_crouch(true)
		await drive(20)
		var roof := box(Vector3(9,0.2,2),Vector3(0,1.3,1))
		await drive(3)
		actor.set_crouch(false)
		await drive(20)
		check(actor.cover.active and crouched_capsule_clear(),"Standing requests stay capsule-safe beneath an attached headroom obstruction")
		actor.set_crouch(true)
		var start: Vector3 = actor.position
		var clear_slide := true
		for frame in 20:
			await drive(1,Vector2.RIGHT)
			clear_slide = clear_slide and crouched_capsule_clear()
		var slow_distance: float = actor.position.x-start.x
		start = actor.position
		for frame in 20:
			await drive(1,Vector2.LEFT,false,true)
			clear_slide = clear_slide and crouched_capsule_clear()
		var fast_distance: float = start.x-actor.position.x
		check(actor.cover.active and clear_slide and absf(slow_distance-2.2/3.0)<0.06 and absf(fast_distance-4.2/3.0)<0.06,"Both crouched slide speeds move the real capsule beneath standing-height obstructions")
		await drive(120,Vector2(float(side),0))
		var anchor: Vector3 = actor.position
		check(actor.cover.active and absf(anchor.x)>2.6 and absf(anchor.x)<3.0 and crouched_capsule_clear(),"Crouched sliding stops safely at either tall-wall edge")
		actor.peek_shoulder = side
		var obstacle := box(Vector3(0.25,0.8,0.5),anchor+Vector3(float(side)*0.58,0.4,0))
		await drive(15,Vector2.ZERO,true)
		check(not actor.cover.peeking and actor.cover.lean.is_zero_approx() and actor.position.distance_to(anchor)<0.02,"A capsule-height obstruction blocks side exposure without inventing lean")
		obstacle.queue_free()
		await drive(3)
		var clear_peek := true
		var physical_lean := true
		var partial_lean := false
		for frame in 30:
			var before: Vector3 = actor.position
			await drive(1,Vector2.ZERO,true)
			var expected := Vector3.RIGHT*clampf((before.x-anchor.x)/actor.cover.PEEK_DISTANCE,-1.0,1.0)
			physical_lean = physical_lean and actor.cover.lean.distance_to(expected)<0.025
			partial_lean = partial_lean or actor.cover.lean.length()>0.1 and actor.cover.lean.length()<0.9
			clear_peek = clear_peek and crouched_capsule_clear()
		var travel: float = (actor.position.x-anchor.x)*float(side)
		check(actor.cover.peeking and clear_peek and physical_lean and partial_lean and travel>0.35 and travel<0.52,"Both shoulders expose smoothly with bounded crouched capsule displacement")
		var replica = Actor.new()
		scene.add_child(replica)
		replica.apply_snapshot(actor.snapshot())
		replica.collision_layer = 0
		var replicated_offset: float = (replica.position.x-anchor.x)/actor.cover.PEEK_DISTANCE
		check(replica.cover.lean.distance_to(Vector3.RIGHT*replicated_offset)<0.025 and is_equal_approx(replica.cover._capsule.height,1.12),"A side-peek snapshot recreates lean from observed displacement and a genuinely crouched replica collider")
		replica.free()
		check(actor.combat.begin_draw(),"A crouched exposed character can hold a bow draw")
		await drive(1,Vector2(float(side),0))
		check(not actor.cover.peeking and actor.cover.lean.length()>0.8,"Release closes the attack exposure gate while physical side lean remains during return")
		var last_lean: float = actor.cover.lean.length()
		var smooth_return := true
		for frame in 30:
			await drive(1,Vector2(float(side),0))
			smooth_return = smooth_return and actor.cover.lean.length()<=last_lean+0.001 and crouched_capsule_clear()
			last_lean = actor.cover.lean.length()
		check(smooth_return and actor.position.distance_to(anchor)<0.03 and actor.cover.lean.is_zero_approx() and actor.rig.phase in ["DRAWING","HOLDING"],"Movement held during retuck cannot drag the anchor, stand the capsule or cancel the draw")
		await drive(15,Vector2(-float(side),0))
		check(actor.cover.active and actor.cover.lean.is_zero_approx() and actor.rig.phase in ["DRAWING","HOLDING"] and crouched_capsule_clear(),"A manually exposed-start draw survives retuck and crouched sliding away from the edge")
		actor.combat.release_draw()
		await drive(30)
		check(actor.rig.phase=="READY" and not actor.combat.wants_cover_exposure() and actor.cover.lean.is_zero_approx(),"Releasing that draw at blocked wall geometry cancels safely instead of firing through cover")
		actor.toggle_cover(Vector3.FORWARD)
		await drive(20)
		check(not actor.cover.active and actor.cover.lean.is_zero_approx() and crouched_capsule_clear(),"F exit after a side peek preserves manual crouch and clears lean")
		roof.queue_free()
		await drive(20)
		check(crouched_capsule_clear(),"Manual crouch survives F exit even after the headroom obstruction disappears")
	await relocate(Vector3(0,0,11.25))
	actor.set_crouch(true)
	await drive(20)
	check(actor.cover.try_enter(Vector3.FORWARD),"A crouched character acquires curved cover")
	await drive(25)
	var first_normal: Vector3 = actor.cover.normal
	var clear_curve := true
	for frame in 35:
		await drive(1,Vector2.RIGHT)
		var radial := Vector2(actor.position.x,actor.position.z-10).length()
		clear_curve = clear_curve and crouched_capsule_clear() and absf(radial-0.97)<0.08
	check(actor.cover.active and clear_curve and actor.cover.normal.dot(first_normal)<0.85,"Crouched curved-wall movement follows the surface without standing or cutting through it")
	await relocate(Vector3(10,0,1.7))
	actor.set_crouch(true)
	await drive(20)
	var ceiling := box(Vector3(6,0.2,2),Vector3(10,1.3,1.65))
	await drive(3)
	check(actor.cover.try_enter(Vector3.FORWARD),"A crouched character acquires low cover beneath limited headroom")
	await drive(20)
	var low_anchor: Vector3 = actor.position
	await drive(30,Vector2.ZERO,true)
	check(actor.cover.low and not actor.cover.peeking and actor.cover.lean.is_zero_approx() and crouched_capsule_clear() and actor.position.distance_to(low_anchor)<0.02,"Blocked low-top requests neither expand the capsule nor animate a false lean")
	var low_slide_start: float = actor.position.x
	await drive(15,Vector2.RIGHT,true,true)
	check(actor.cover.active and actor.position.x-low_slide_start>0.9 and crouched_capsule_clear() and actor.cover.lean.is_zero_approx(),"A headroom-blocked low peek still permits fast crouched sliding")
	actor.toggle_cover(Vector3.FORWARD)
	await drive(20)
	check(not actor.cover.active and crouched_capsule_clear(),"Leaving low cover preserves manually requested crouch")
	ceiling.queue_free()
	await drive(3)
	check(actor.cover.try_enter(Vector3.FORWARD),"Low cover can be reacquired after its ceiling is removed")
	await drive(20)
	var physical_top := true
	var partial_top := false
	for frame in 20:
		await drive(1,Vector2.ZERO,true)
		var fraction: float = (actor.cover._capsule.height-1.12)/(1.8-1.12)
		physical_top = physical_top and actor.cover.lean.distance_to(Vector3.UP*fraction)<0.001
		partial_top = partial_top or fraction>0.1 and fraction<0.9
		if frame == 4:
			var replica = Actor.new()
			scene.add_child(replica)
			replica.apply_snapshot(actor.snapshot())
			replica.collision_layer = 0
			var replica_fraction: float = (replica.cover._capsule.height-1.12)/(1.8-1.12)
			check(replica_fraction>0.1 and replica_fraction<0.9 and replica.cover.lean.distance_to(Vector3.UP*replica_fraction)<0.001,"A transition snapshot recreates partial top lean and its corresponding physical capsule height")
			replica.free()
	check(actor.cover.peeking and physical_top and partial_top,"Low-top lean follows the actual expanding capsule rather than raw peek intent")
	await drive(1)
	check(not actor.cover.peeking and actor.cover.lean.y>0.5,"Low-top retuck keeps its physical lean while exposure permission closes immediately")
	await drive(20)
	check(crouched_capsule_clear() and actor.cover.lean.is_zero_approx(),"Releasing a low-top peek restores the tucked crouched collider and zero lean")
	actor.toggle_cover(Vector3.FORWARD)
	await drive(20)
	check(crouched_capsule_clear(),"An unobstructed low-cover exit retains manual crouch after a top peek")

func trunk_fixture(center: Vector3, radius: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center+Vector3.UP*2.5
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 5.0
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

func lookout_capsule_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.cover._capsule
	query.transform = actor.cover._collider.global_transform
	query.collision_mask = 1
	query.exclude = [actor.get_rid(),floor_body.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func lookout_lane_clear(right: Vector3, crouch: bool) -> bool:
	# Independently query the world at the observed body position, not the
	# solver's requested offset or an echoed can_peek result.
	var shape := SphereShape3D.new()
	shape.radius = 0.05
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = actor.position+Vector3.UP*(0.78 if crouch else 1.4)
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	var space := scene.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():
		return false
	query.motion = Vector3.UP.cross(right)*1.77
	return space.cast_motion(query)[0] >= 1.0

func lookout_geometry_scenarios() -> void:
	var narrow_tree := trunk_fixture(Vector3(6,0,10),0.32)
	var rock := StaticBody3D.new()
	rock.position = Vector3(12,0,10)
	rock.collision_layer = 1
	rock.collision_mask = 0
	var rock_collider := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	var vertices := PackedVector3Array()
	for height in [0.0,3.0]:
		for corner in [Vector2(-0.3,0.4),Vector2(0.3,0.4),Vector2(0.55,0.1),Vector2(0.4,-0.5),Vector2(-0.45,-0.45),Vector2(-0.55,0.05)]:
			vertices.append(Vector3(corner.x,height,corner.y))
	convex.points = vertices
	rock_collider.shape = convex
	rock.add_child(rock_collider)
	scene.add_child(rock)
	var rising_rock := StaticBody3D.new()
	rising_rock.position = Vector3(6,0,-6)
	rising_rock.collision_layer = 1
	rising_rock.collision_mask = 0
	var rising_collider := CollisionShape3D.new()
	var rising_shape := ConvexPolygonShape3D.new()
	var rising_vertices := PackedVector3Array()
	for x in [-0.3,0.3]:
		for corner in [Vector2(0.3,0),Vector2(0.3,1.1),Vector2(-0.45,1.9),Vector2(-0.8,1.9),Vector2(-0.8,0)]:
			rising_vertices.append(Vector3(x,corner.y,corner.x))
	rising_shape.points = rising_vertices
	rising_collider.shape = rising_shape
	rising_rock.add_child(rising_collider)
	scene.add_child(rising_rock)
	var compound := box(Vector3(2,3,0.6),Vector3(-1,1.5,-10))
	var second_shape := CollisionShape3D.new()
	var second_box := BoxShape3D.new()
	second_box.size = Vector3(2,3,0.6)
	second_shape.shape = second_box
	second_shape.position.x = 2.0
	compound.add_child(second_shape)
	var adjoining := box(Vector3(2,3,0.6),Vector3(3,1.5,-10))
	await drive(3)
	var rotated_right := Vector3.RIGHT.rotated(Vector3.UP,PI/4.0)
	var fixtures := [
		{"name":"narrow trunk","center":Vector3(6,0,10),"right":Vector3.RIGHT,"depth":0.32,"edge":0.0,"extent":0.45},
		{"name":"wide trunk","center":Vector3(0,0,10),"right":Vector3.RIGHT,"depth":0.55,"edge":0.0,"extent":0.65},
		{"name":"rotated box","center":Vector3(-10,0,0),"right":rotated_right,"depth":0.3,"edge":1.82,"extent":0.45},
		{"name":"convex rock","center":Vector3(12,0,10),"right":Vector3.RIGHT,"depth":0.4,"edge":0.0,"extent":0.65},
		{"name":"inward-rising rock","center":Vector3(6,0,-6),"right":Vector3.RIGHT,"depth":0.3,"edge":0.0,"extent":0.45},
		{"name":"compound edge","center":Vector3(1,0,-10),"right":Vector3.RIGHT,"depth":0.3,"edge":2.82,"extent":0.45}
	]
	for fixture in fixtures:
		var right: Vector3 = fixture.right
		var outward := right.cross(Vector3.UP)
		for crouch in [false,true]:
			for shoulder in [-1,1]:
				var label := "%s crouch=%s side=%s" % [fixture.name,crouch,shoulder]
				var start: Vector3 = fixture.center+right*float(shoulder)*float(fixture.edge)+outward*(float(fixture.depth)+0.7)
				await relocate(start)
				actor.set_crouch(crouch)
				actor.peek_view_right = right
				actor.peek_shoulder = shoulder
				await drive(20)
				check(actor.cover.try_enter(-outward),label+": acquires physical cover")
				await drive(20)
				var anchor: Vector3 = actor.position
				check(not actor.cover.low,label+": solid forward top geometry selects a side lookout")
				check(actor.cover.can_peek(-shoulder),label+": selected lookout is reachable")
				await drive(30,Vector2.ZERO,true)
				var endpoint: Vector3 = actor.position
				var distance: float = (endpoint-anchor).dot(right)*float(shoulder)
				# The asymmetric rock can select either .55 or .65 according to
				# its actual sloped face, rather than requiring a shape-name rule.
				var compact := absf(distance-float(fixture.extent))<0.025 if fixture.name!="convex rock" else distance>=0.44 and distance<=0.675
				check(actor.cover.peeking and compact and lookout_capsule_clear() and lookout_lane_clear(right,crouch),label+": manual peek moves a clear capsule to the shortest compact firing lane")
				var stable := true
				for frame in 35:
					await drive(1,Vector2.ZERO,true)
					stable = stable and actor.cover.peeking and actor.position.distance_to(endpoint)<0.002 and lookout_capsule_clear() and lookout_lane_clear(right,crouch)
				check(stable,label+": held endpoint and real clearance remain stable")
				if float(fixture.edge)==0.0:
					actor.peek_shoulder = -shoulder
					var swap_safe := true
					for frame in 35:
						var before: Vector3 = actor.position
						await drive(1,Vector2.ZERO,true)
						swap_safe = swap_safe and before.distance_to(actor.position)<0.061 and lookout_capsule_clear()
					check(swap_safe and actor.cover.peeking and (actor.position-anchor).dot(right)*float(shoulder)<-0.4 and lookout_lane_clear(right,crouch),label+": side swap travels continuously across the protected anchor")
				var last_lean: float = actor.cover.lean.length()
				var smooth_return := true
				for frame in 30:
					await drive(1,Vector2(right.x,right.z)*float(shoulder))
					smooth_return = smooth_return and not actor.cover.peeking and actor.cover.lean.length()<=last_lean+0.002 and lookout_capsule_clear()
					last_lean = actor.cover.lean.length()
					if actor.cover.lean.is_zero_approx():
						break
				check(smooth_return and actor.position.distance_to(anchor)<0.025,label+": retuck is physical and movement cannot drag its anchor")
				actor.peek_shoulder = shoulder
				await drive(1)
				actor.combat.set_aim(actor.position-outward*15.0+Vector3.UP*(0.78 if crouch else 1.4))
				check(actor.combat.begin_draw(),label+": bow requests the same lookout without RMB")
				await drive(30)
				check(actor.cover.peeking and (actor.position-anchor).dot(right)*float(shoulder)>0.4 and lookout_capsule_clear() and lookout_lane_clear(right,crouch),label+": automatic exposure uses the same clear physical destination")
				actor.combat.stop()
				await drive(30)
				check(actor.cover.active and actor.position.distance_to(anchor)<0.025 and actor.cover.lean.is_zero_approx(),label+": canceling automatic exposure retucks without detachment")
	# Walk across both a shape-index seam and a separate body's contiguous face.
	for crouch in [false,true]:
		await relocate(Vector3(-0.5,0,-8.9))
		actor.set_crouch(crouch)
		await drive(20)
		check(actor.cover.try_enter(Vector3.FORWARD),"Compound seam fixture attaches")
		await drive(20)
		var contiguous := true
		for frame in 90:
			var before: Vector3 = actor.position
			await drive(1,Vector2.RIGHT)
			contiguous = contiguous and actor.cover.active and actor.position.distance_to(before)<0.045 and absf(actor.position.z+9.28)<0.025 and lookout_capsule_clear()
		check(contiguous and actor.position.x>2.7,"Contiguous compound shapes and adjoining bodies slide without detaching or teleporting")
	await relocate(Vector3(3.8,0,-8.9))
	actor.cover.try_enter(Vector3.FORWARD)
	await drive(25)
	actor.peek_shoulder = 1
	await drive(25,Vector2.ZERO,true)
	check(actor.cover.peeking,"A compound edge supplies the initial right lookout")
	actor.peek_shoulder = -1
	await drive(30,Vector2.ZERO,true)
	check(not actor.cover.peeking and actor.cover.lean.is_zero_approx(),"An obstructed opposite-side request returns behind cover")
	await drive(160,Vector2.LEFT,true)
	check(actor.cover.active and actor.cover.peeking and actor.position.x< -2.0 and lookout_capsule_clear(),"Holding an initially blocked left lookout still allows sliding to the left edge")
	# A new lane obstruction invalidates the latched endpoint, not just its
	# attack gate; holding cannot pick a longer destination and jitter outward.
	await relocate(Vector3(6,0,11.02))
	actor.set_crouch(true)
	await drive(20)
	actor.cover.try_enter(Vector3.FORWARD)
	await drive(20)
	var protected: Vector3 = actor.position
	actor.peek_shoulder = 1
	await drive(25,Vector2.ZERO,true)
	var lane_blocker := box(Vector3(0.08,0.12,0.12),actor.position+Vector3(0,0.78,-0.6))
	await drive(35,Vector2.ZERO,true)
	check(not actor.cover.peeking and actor.position.distance_to(protected)<0.025 and actor.cover.lean.is_zero_approx(),"A blocked held lane retucks instead of migrating to another candidate or keeping stale exposure")
	check(not actor.cover.can_peek(-1),"Eligibility revalidates the blocked held endpoint even when a longer candidate is clear")
	lane_blocker.queue_free()
	await drive(25,Vector2.ZERO,true)
	check(actor.cover.peeking and absf(actor.position.x-protected.x-0.45)<0.025,"Removing a transient lane blocker restores the same held endpoint")
	await drive(25)
	# Unsupported destinations are rejected even when their firing lanes clear.
	var ledge_tree := trunk_fixture(Vector3(19,5,0),0.32)
	var ledge := box(Vector3(0.7,1,2),Vector3(19,4.5,1))
	await relocate(Vector3(19,5,1.02))
	check(actor.cover.try_enter(Vector3.FORWARD),"Narrow ledge has a supported protected anchor")
	await drive(25)
	var ledge_anchor: Vector3 = actor.position
	for shoulder in [-1,1]:
		actor.peek_shoulder = shoulder
		await drive(25,Vector2.ZERO,true)
		check(actor.cover.active and not actor.cover.peeking and actor.position.distance_to(ledge_anchor)<0.025,"Neither shoulder steps into an unsupported lookout beyond a ledge")
	var rock_floor := box(Vector3(4,1,4),Vector3(7,4.5,0))
	var faceted_rock := StaticBody3D.new()
	faceted_rock.position = Vector3(7,5.8,0)
	faceted_rock.collision_layer = 1
	faceted_rock.collision_mask = 0
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.7
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	var faceted_collider := CollisionShape3D.new()
	faceted_collider.shape = rock_mesh.create_convex_shape()
	faceted_rock.add_child(faceted_collider)
	scene.add_child(faceted_rock)
	for crouch in [false,true]:
		await relocate(Vector3(7,5.05,1.5))
		actor.set_crouch(crouch)
		await drive(20)
		var approach_start: Vector3 = actor.position
		check(actor.cover.try_enter(Vector3.FORWARD),"Both physical stances acquire the native-style low-poly convex sphere")
		await drive(25)
		check(actor.cover.active and actor.is_on_floor() and actor.position.distance_to(approach_start)>0.35 and actor.position.distance_to(approach_start)<0.8,"Convex acquisition performs the supported capsule approach instead of rejecting standing floor recovery")
	for shoulder in [-1,1]:
		await relocate(Vector3(7.0-float(shoulder)*0.02,5.05,1.5))
		actor.peek_shoulder = shoulder
		await drive(20)
		check(actor.cover.try_enter(Vector3.FORWARD),"An oblique rock facet can be acquired before choosing the opposite lookout")
		await drive(25)
		var facet_start: Vector3 = actor.position
		var continuous := true
		for frame in 12:
			var before: Vector3 = actor.position
			await drive(1,Vector2(float(shoulder),0))
			continuous = continuous and actor.cover.active and actor.position.distance_to(before)<0.045
		check(continuous and (actor.position.x-facet_start.x)*float(shoulder)>0.08,"Sliding toward a convex lookout follows the changing offset normal without a facet teleport or dead stop")
		await drive(30,Vector2.ZERO,true)
		check(actor.cover.peeking and lookout_capsule_clear() and lookout_lane_clear(Vector3.RIGHT,false),"Moving to either convex flank makes its selected lookout physically clear")
	# Both uphill and downhill lookouts must sweep along supported terrain,
	# not mistake a horizontal cast's floor contact for a wall or copy the
	# exposed body's height back into the protected anchor.
	var hillside := box(Vector3(6,1,6),Vector3(17,4.5,-5))
	hillside.rotation.z = 0.12
	var hillside_tree := trunk_fixture(Vector3(17,4.8,-5),0.55)
	for crouch in [false,true]:
		for shoulder in [-1,1]:
			await relocate(Vector3(17,5.3,-3.75))
			actor.set_crouch(crouch)
			actor.peek_shoulder = shoulder
			await drive(20)
			check(actor.cover.try_enter(Vector3.FORWARD),"Sloped native-style ground permits attaching beside a tree")
			await drive(20)
			var slope_anchor: Vector3 = actor.position
			await drive(35,Vector2.ZERO,true)
			var slope_endpoint: Vector3 = actor.position
			var actual_rise: float = slope_endpoint.y-slope_anchor.y
			var expected_rise: float = (slope_endpoint.x-slope_anchor.x)*tan(0.12)
			check(actor.cover.peeking and actor.is_on_floor() and absf((slope_endpoint.x-slope_anchor.x)*float(shoulder)-0.65)<0.025 and absf(actual_rise-expected_rise)<0.025 and lookout_lane_clear(Vector3.RIGHT,crouch),"Both side lookouts move the real capsule uphill/downhill to a supported clear firing lane")
			var slope_stable := true
			for frame in 35:
				await drive(1,Vector2.ZERO,true)
				slope_stable = slope_stable and actor.cover.peeking and actor.is_on_floor() and actor.position.distance_to(slope_endpoint)<0.005
			check(slope_stable,"Slope exposure keeps its endpoint and does not drag the protected anchor vertically")
			await drive(35)
			check(actor.cover.active and actor.position.distance_to(slope_anchor)<0.025,"Slope retuck returns to the original supported anchor")
			actor.combat.set_aim(actor.position+Vector3(0,1.4,-15))
			check(actor.combat.begin_draw(),"Automatic slope draw accepts the grounded lookout")
			await drive(12)
			# A real observed CharacterBody recovery dip must not abort a draw
			# merely because a floor intersects the uncorrected horizontal cast.
			actor.position.y -= 0.01657
			check(actor.cover.can_peek(-shoulder),"Ordinary floor-recovery depth cannot invalidate a clear destination")
			await drive(30)
			check(actor.cover.peeking and actor.rig.phase in ["DRAWING","HOLDING"] and actor.is_on_floor(),"Automatic exposure survives floor recovery and reaches the same physical slope endpoint")
			actor.combat.stop()
			await drive(35)
			var tucked: Vector3 = actor.position
			await drive(12,Vector2.RIGHT)
			check(actor.cover.active and actor.is_on_floor() and actor.position.distance_to(tucked)>0.15,"Ground recovery tolerance releases the return latch so sticky sliding resumes after retuck")
	await relocate(Vector3(15,0,15))
	for fixture_body in [narrow_tree,rock,rising_rock,compound,adjoining,ledge_tree,ledge,rock_floor,faceted_rock,hillside,hillside_tree]:
		fixture_body.queue_free()
	await drive(3)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	floor_body = box(Vector3(44,1,44),Vector3(0,-0.5,0))
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
	scene.add_child(actor)
	actor.configure(1,"Cover regression",Vector3(0,0,1.1))
	await drive(30)
	check(actor.cover.try_enter(Vector3.FORWARD),"A grounded character attaches to a nearby wall")
	await drive(30)
	check(actor.cover.active and not actor.cover.low and absf(actor.position.z-0.72)<0.02,"Cover settles at capsule-safe wall clearance")
	await sticky_toggle_scenarios()
	check(actor.cover.try_enter(Vector3.FORWARD),"A fresh press takes the wall again after the toggle checks")
	await drive(30)
	check(actor.cover.active and absf(actor.position.z-0.72)<0.02,"Re-entry settles back on the protected anchor")
	check(not actor.combat.begin_draw(),"A direct draw at the solid middle of tall cover cannot expose or shoot through the wall")
	await drive(20)
	check(actor.cover.active and actor.rig.phase=="READY","Blocked direct attacks leave the actor safely tucked")
	actor.rig.set_weapon("sword")
	actor.rig.set_sword(2)
	actor.combat.melee_progress = 0.5
	check(not actor.combat.begin_melee() and actor.cover.active,"A cooldown-rejected melee input does not break cover")
	actor.combat.melee_progress = 1.0
	actor.combat.grounded = false
	check(not actor.combat.begin_melee() and actor.cover.active,"An airborne-rejected melee input does not break cover")
	actor.combat.grounded = true
	actor.combat.set_aim(actor.position+Vector3(0,1.2,-12))
	check(actor.combat.begin_melee() and not actor.cover.active and actor.rig.phase=="MELEE","Even the solid middle of a tall wall permits an immediate melee exit")
	await drive(3)
	check(actor.rig.phase=="MELEE" and (-actor.rig.global_basis.z).dot(Vector3.FORWARD)>0.95,"The first attack pose and following physics ticks remain free of the cover-facing constraint")
	actor.rig.set_weapon("bow")
	actor.toggle_cover(Vector3.FORWARD)
	await drive(30)
	actor.combat.stop()
	var initial: Vector3 = actor.position
	await drive(30,Vector2(0,-1))
	check(actor.position.distance_to(initial)<0.02,"Pushing into cover never penetrates it")
	await drive(120,Vector2(1,0))
	check(actor.cover.active and actor.position.x>2.6 and actor.position.x<3.0,"Wall slide stops at the edge instead of walking into exposure")
	initial = actor.position
	await drive(30,Vector2.ZERO,true)
	check(actor.cover.peeking and actor.position.x>initial.x+0.35 and actor.position.x<initial.x+0.52,"The selected shoulder physically steps out only a bounded distance at a tall-cover edge")
	var peek_position: Vector3 = actor.position
	var stable_peek := true
	for frame in 120:
		await drive(1,Vector2.ZERO,true)
		stable_peek = stable_peek and actor.cover.peeking and actor.position.distance_to(peek_position)<0.025
	check(stable_peek,"Holding a tall peek preserves one anchored destination without jitter")
	check(actor.combat.begin_draw(),"Exposed cover permits aiming and drawing")
	await drive(30)
	check(not actor.cover.peeking and actor.rig.phase in ["DRAWING","HOLDING"] and actor.position.distance_to(initial)<0.03,"Releasing peek returns behind cover without canceling the held draw")
	actor.peek_shoulder = -1
	await drive(20,Vector2.ZERO,true)
	check(not actor.cover.peeking,"The opposite shoulder cannot peek through the solid middle of a wall")
	actor.press_jump(true)
	check(not actor.cover.active and actor.roll.active,"Jump-roll exits cover before starting the roll")
	await relocate(Vector3(10,0,1.7))
	check(actor.cover.try_enter(Vector3.FORWARD),"Low stone debris supports cover")
	await drive(1)
	check(actor.cover.lean.is_zero_approx(),"Acquiring low cover while standing does not invent a top peek during the initial crouch")
	await drive(30)
	check(actor.cover.low and actor.cover._capsule.height<1.2,"Low cover reduces the real damage collider")
	var standing_head: float = actor.rig._bone_world(actor.rig._bones.Head).origin.y
	await drive(30,Vector2.ZERO,true)
	check(actor.cover.peeking and is_equal_approx(actor.cover._capsule.height,1.8),"Low-cover peek restores a standing collider")
	check(actor.rig._bone_world(actor.rig._bones.Head).origin.y>standing_head+0.4,"Low-cover peek raises the visible skeleton, not just the camera")
	await drive(20)
	actor.press_jump(false)
	await drive(5)
	check(not actor.cover.active and not actor.roll.active and actor.velocity.y>0 and not actor.is_on_floor(),"Unmodified Space launches out of low cover instead of reattaching")
	actor.take_damage(1000,1)
	check(actor.downed and not actor.cover.active,
		"Going down clears cover and restores the standing collider")
	actor.take_damage(1.0,1)
	check(not actor.alive,"and the finisher takes the body")
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
	actor.set_crouch(true)
	await drive(20)
	check(actor.cover.crouched and actor.cover._capsule.height<1.2,"Manual crouch works without cover")
	var ceiling := box(Vector3(2,0.2,2),Vector3(15,1.45,15))
	await drive(3)
	actor.set_crouch(false)
	await drive(20)
	check(actor.cover.crouched and actor.cover._capsule.height<1.2,"Blocked headroom keeps the actor crouched instead of intersecting a ceiling")
	actor.press_jump(false)
	await drive(3)
	check(actor.is_on_floor() and actor.velocity.y<=0.0,"A crouched jump cannot expand through blocked headroom")
	ceiling.queue_free()
	await drive(20)
	check(not actor.cover.crouched and is_equal_approx(actor.cover._capsule.height,1.8),"Standing resumes when headroom becomes clear")
	await relocate(Vector3(0,0,1.1))
	actor.cover.try_enter(Vector3.FORWARD)
	await drive(20)
	var slide_start: float = actor.position.x
	await drive(20,Vector2.RIGHT)
	var slow_distance: float = actor.position.x-slide_start
	slide_start = actor.position.x
	await drive(20,Vector2.LEFT,false,true)
	var fast_distance: float = slide_start-actor.position.x
	check(actor.cover.active and fast_distance>slow_distance*1.6,"Shift increases attached slide speed without dropping cover")
	var slope := box(Vector3(6,0.4,5),Vector3(-8,2,12))
	slope.rotation.z = 0.18
	box(Vector3(3.2,1.4,1.5),Vector3(-8,2.9,10.5))
	await relocate(Vector3(-8,2.4,11.8))
	check(actor.cover.try_enter(Vector3.FORWARD),"Low cover can be acquired on a slope")
	await drive(25,Vector2.ZERO,true)
	var slope_y: float = actor.position.y
	var slope_stable := true
	for frame in 120:
		await drive(1,Vector2.ZERO,true)
		slope_stable = slope_stable and actor.cover.peeking and absf(actor.position.y-slope_y)<0.025
	check(slope_stable,"Standing peek headroom does not oscillate against a sloping floor")
	await crouched_cover_scenarios()
	await automatic_attack_scenarios()
	await lookout_geometry_scenarios()
	await tree_trunk_scenarios()
	await relocate(Vector3(0,0,1.1))
	actor.cover.try_enter(Vector3.FORWARD)
	wall.queue_free()
	await drive(3)
	check(not actor.cover.active,"Removing the supporting obstacle releases cover")
	# The eye a possessed body is seen through rides its shoulder; read the eye
	# itself, relative to the point it frames.
	await relocate(Vector3(0,0,-8))
	var camera := PossessionCamera.new()
	scene.add_child(camera)
	camera.follow(actor,true)
	var focus: Vector3 = camera._focus_point()
	var right_position: Vector3 = camera.camera.global_position-focus
	camera.swap()
	camera.update(0.05)
	var transition: Vector3 = camera.camera.global_position-focus
	check(transition.x<right_position.x and transition.x>-0.70,"Shoulder switching traverses smoothly rather than teleporting")
	for frame in 60:
		camera.update(1.0/30.0)
	var left_position: Vector3 = camera.camera.global_position-focus
	check(left_position.x< -0.69 and right_position.x>0.69,"Both shoulder views frame opposite sides of the character")
	box(Vector3(4,4,0.2),focus+Vector3(0,0,2))
	await physics_frame
	for frame in 30:
		camera.update(1.0/60.0)
	var blocked: Vector3 = camera.camera.global_position
	check(blocked.z<focus.z+1.7,"Camera boom stops before a thin wall instead of clipping its near plane")
	var rig = load("res://scripts/archer.gd").new()
	scene.add_child(rig)
	rig.set_physics_process(false)
	rig.advance_animation(0.2)
	var lowest_pelvis := INF
	var lowest_head := INF
	for frame in 180:
		rig.set_cover(true,Vector3.BACK,1.0,false,Vector3.ZERO)
		rig.set_locomotion(Vector3.RIGHT*2.2 if frame%2==0 else Vector3.ZERO,true)
		rig.set_roll(-1,Vector3.FORWARD)
		rig.advance_animation(1.0/60.0)
		lowest_pelvis = minf(lowest_pelvis,rig._bone_world(rig._bones.pelvis).origin.y)
		lowest_head = minf(lowest_head,rig._bone_world(rig._bones.Head).origin.y)
	check(lowest_pelvis>0.05 and lowest_head>0.65,"Rapid sticky movement transitions never accumulate crouch offsets into the skeleton")
	rig.set_cover(true,Vector3.BACK,0.0,true,Vector3.UP)
	rig.begin_draw()
	var largest_scale_error := 0.0
	for frame in 600:
		var yaw := 0.17+float(frame)*0.013
		rig.aim_at(Vector3(sin(yaw)*20,1.4,cos(yaw)*20))
		rig.set_roll(-1,Vector3.FORWARD)
		rig.advance_animation(1.0/60.0)
		largest_scale_error = maxf(largest_scale_error,absf(rig.global_basis.determinant()-1.0))
		largest_scale_error = maxf(largest_scale_error,absf(rig._model.basis.determinant()-1.0))
	check(largest_scale_error<0.000002,"Sustained cover aiming keeps character and weapon rotations at unit scale")
	print("COVER_MOVEMENT_REGRESSION checks=",checks," failures=",failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
