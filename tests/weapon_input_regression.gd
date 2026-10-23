extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func mouse(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = root.get_screen_transform()*point
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	await mouse(point,true)
	await mouse(point,false)

func look(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative * root.get_screen_transform().get_scale()
	event.position = root.get_screen_transform()*(root.get_visible_rect().size*0.5)
	event.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func equipment_checks(scene, rig, frontier: bool) -> void:
	await key(KEY_I)
	await click(scene.hud.bow_buttons[2])
	await click(scene.hud.sword_buttons[0])
	check(rig.bow_index == 2 and rig.sword_index == 0,"Mouse clicks select each weapon's size independently")
	await key(KEY_2)
	check(rig.weapon == "sword" and rig.active_sword.visible and not rig.active_bow.visible,"Key 2 equips the actual sword model")
	check(rig.bow_index == 2 and rig.sword_index == 0,"Key 2 never changes a weapon size")
	await key(KEY_2)
	check(rig.sword_index == 0,"Repeated key 2 does not cycle sword sizes")
	await key(KEY_1)
	check(rig.weapon == "bow" and rig.active_bow.visible and not rig.active_sword.visible,"Key 1 equips the actual bow model")
	await key(KEY_3)
	check(rig.weapon == "dagger" and rig.active_dagger.visible and not rig.active_sword.visible and not rig.active_bow.visible,"Key 3 equips the actual dagger model")
	check(rig.bow_index == 2 and rig.sword_index == 0,"Key 3 selects no bow or sword size")
	await key(KEY_2)
	await click(scene.hud.sword_buttons[2])
	check(rig.sword_index == 2 and rig.bow_index == 2,"Sword size remains mouse-selectable while equipped")
	await key(KEY_1)
	await click(scene.hud.bow_buttons[0])
	check(rig.bow_index == 0 and rig.sword_index == 2,"Bow size clicks do not overwrite the selected sword")
	await key(KEY_I)
	if frontier:
		check(not scene._cursor_free,"Closing equipment restores mouse-look")
	else:
		check(not scene._cursor_free,"Arena equipment toggle restores mouse-look")

func held_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func held_attack(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_screen_transform()*(root.get_visible_rect().size*0.5)
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func physics_ticks(count: int) -> void:
	for tick in count:
		await physics_frame

func input_box(scene: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

func crosshair_shoulder_checks(scene, frontier: bool) -> void:
	var actor: CharacterBody3D = scene.player if frontier else scene.actors[0]
	var rig = scene.archer if frontier else actor.rig
	var combat = scene.combat if frontier else actor.combat
	var shoulder = scene.shoulder_camera if frontier else scene._shoulder_camera
	var saved_position := actor.position
	var saved_yaw: float = scene.camera_yaw if frontier else scene._camera_yaw
	var saved_pitch: float = scene.camera_pitch if frontier else scene._camera_pitch
	var platform := input_box(scene,Vector3(0,59.5,0),Vector3(8,1,40))
	var target := input_box(scene,Vector3(0,61.5,-10),Vector3(0.4,3.0,0.02))
	actor.position = Vector3(0,60.02,7)
	actor.velocity = Vector3.ZERO
	rig.set_bow(0)
	if frontier:
		scene.camera_yaw = 0.0
		scene.camera_pitch = 0.0
		scene._camera_ready = false
	else:
		scene._camera_yaw = 0.0
		scene._camera_pitch = 0.0
	scene._set_cursor_free(false)
	await physics_ticks(90)
	for side in [1,-1]:
		if shoulder.side != side:
			await key(KEY_X)
		await physics_ticks(60)
		for distance in [0.8,2.0,15.0]:
			# A narrow real target on the camera line, not a copy of combat's aim.
			target.position = Vector3(scene.camera.global_position.x,scene.camera.global_position.y,actor.position.z-distance)
			await physics_ticks(2)
			rig.global_basis = Basis(Vector3.UP,float(side)*PI*0.5)
			held_attack(true)
			var stable := true
			for tick in 70:
				await physics_frame
				var expected := target.position+Vector3.BACK*0.01
				stable = stable and combat.aim_point.distance_to(expected)<0.01
			check(stable,"Crosshair target stays fixed through bow raising and draw from either shoulder at %.1f m"%distance)
			var arrows: Array = scene.arrows if frontier else scene.projectiles
			var previous_shot = arrows.back() if not arrows.is_empty() else null
			held_attack(false)
			var arrow = arrows.back() if not arrows.is_empty() else null
			check(arrow != null and arrow != previous_shot,"Shoulder aiming releases a new physical arrow")
			if arrow != null and arrow != previous_shot:
				var desired: Vector3 = (target.position+Vector3.BACK*0.01-arrow.global_position).normalized()
				var center := root.get_visible_rect().size*0.5
				var view_origin: Vector3 = scene.camera.project_ray_origin(center)
				var view_direction: Vector3 = scene.camera.project_ray_normal(center)
				check(arrow.velocity.normalized().dot(desired)>0.9999,"Launch follows the crosshair target instead of initial character facing")
				check((arrow.global_position-view_origin).cross(view_direction).length()<0.02,"Open-field arrow starts on the center crosshair ray")
				check(arrow.velocity.normalized().dot(view_direction)>0.9999,"Open-field arrow flies along the center crosshair ray")
				check(arrow.velocity.dot(-rig.active_bow.global_basis.z)>0.0,"A nearby crosshair target never reverses the arrow through its own bow")
				if is_equal_approx(float(distance),15.0):
					await physics_ticks(8)
					var visual_tip: Vector3 = arrow._visual.global_position-arrow._visual.global_basis.z*0.98
					check(visual_tip.distance_to(arrow.global_position)<0.05,"Rendered arrow converges onto the authoritative crosshair path")
					await physics_ticks(37)
				else:
					await physics_ticks(45)
				check(not arrow.flying and absf(arrow.global_position.z-(target.position.z+0.01))<0.01 and absf(arrow.global_position.x-target.position.x)<0.01,"Real arrow strikes the crosshair target from either shoulder, retaining gravity")
			await physics_ticks(90)
	platform.queue_free()
	target.queue_free()
	actor.position = saved_position
	actor.velocity = Vector3.ZERO
	if frontier:
		scene.camera_yaw = saved_yaw
		scene.camera_pitch = saved_pitch
		scene._camera_ready = false
	else:
		scene._camera_yaw = saved_yaw
		scene._camera_pitch = saved_pitch
	await physics_ticks(30)

func slide_distance(actor: CharacterBody3D, cover, code: Key, fast: bool) -> float:
	held_key(KEY_SHIFT,fast)
	held_key(code,true)
	await physics_ticks(6)
	var start := actor.position
	await physics_ticks(12)
	var distance := absf(actor.position.x-start.x)
	held_key(code,false)
	held_key(KEY_SHIFT,false)
	await physics_ticks(3)
	check(cover.active,"Held movement keeps the actor attached to cover")
	return distance

func automatic_input_checks(scene, frontier: bool) -> void:
	var actor = scene.player if frontier else scene.actors[0]
	var rig = scene.archer if frontier else actor.rig
	var cover = scene.cover if frontier else actor.cover
	var combat = scene.combat if frontier else actor.combat
	var center := root.get_visible_rect().size*0.5
	var emitted: Array[Dictionary] = []
	var record := func(origin: Vector3, direction: Vector3, _speed: float, charge: float):
		var desired: Vector3 = (combat.aim_point-origin).normalized()
		var horizontal := Vector3(desired.x,0,desired.z).normalized()
		check(cover.peeking and (-rig.global_basis.z).dot(horizontal)>0.95,"Direct input faces aim only after real attack exposure")
		check(rig.active_bow.get_arrow_direction().dot(desired)>0.98 and direction.dot(desired)>0.999,"Visible bow and emitted direction agree with the actual crosshair")
		var arrows: Array = scene.arrows if frontier else scene.projectiles
		check(not arrows.is_empty(),"Direct cover release creates a real projectile")
		if not arrows.is_empty():
			check(arrows.back().velocity.normalized().dot(direction)>0.999,"The spawned projectile follows the displayed bow direction")
		emitted.append({"charge":charge})
	combat.shot.connect(record)
	for keyboard in [false,true]:
		if keyboard:
			held_attack(true)
		else:
			await mouse(center,true)
		await physics_ticks(30)
		check(cover.active and cover.peeking and cover.lean.y>0.95 and rig.phase in ["DRAWING","HOLDING"],"Two independent LMB holds rise and lean without RMB in both controllers")
		if keyboard:
			held_attack(false)
		else:
			await mouse(center,false)
		await physics_ticks(100)
		check(cover.active and not cover.peeking and cover.lean.is_zero_approx() and cover._capsule.height<1.2,"A direct input shot retucks after release while staying attached")
	check(emitted.size()==2,"Each independent LMB hold releases one arrow")
	held_attack(true)
	await physics_ticks(1)
	var charge: float = rig.draw_amount
	held_attack(false)
	check(emitted.size()==2,"Quick LMB release waits for exposure rather than shooting tucked")
	await physics_ticks(100)
	check(emitted.size()==3,"Quick LMB press-release completes exactly once")
	if emitted.size()>2:
		check(absf(float(emitted[2].charge)-charge)<0.001,"A quick queued input cannot gain charge after key-up")
	held_attack(true)
	held_attack(false)
	await key(KEY_2)
	await physics_ticks(45)
	check(emitted.size()==3 and cover.lean.is_zero_approx(),"Equipment cancellation clears the queued shot and automatic exposure")
	var melee_origin: Vector3 = actor.position
	await mouse(center,true)
	check(not cover.active and rig.phase.begins_with("MELEE") and actor.position.distance_to(melee_origin)<0.03,"LMB starts melee immediately and breaks sticky cover without stepping to exposure")
	await mouse(center,false)
	held_key(KEY_S,true)
	await physics_ticks(12)
	held_key(KEY_S,false)
	check(not cover.active and rig.phase.begins_with("MELEE") and actor.position.z>melee_origin.z+0.3,"The real controller can move away from the wall during melee")
	await physics_ticks(210)
	check(not cover.active and cover.lean.is_zero_approx(),"Sword recovery does not automatically reattach to cover")
	actor.position = melee_origin+Vector3.UP*0.02
	actor.velocity = Vector3.ZERO
	await physics_ticks(20)
	await key(KEY_F)
	await physics_ticks(20)
	held_attack(true)
	check(not cover.active and rig.phase.begins_with("MELEE"),"LMB also breaks cover and starts the sword immediately")
	held_attack(false)
	await physics_ticks(210)
	await key(KEY_1)
	await key(KEY_F)
	await physics_ticks(20)
	await mouse(center,true,MOUSE_BUTTON_RIGHT)
	await physics_ticks(30)
	await mouse(center,true)
	await physics_ticks(24)
	await mouse(center,false)
	await physics_ticks(100)
	check(emitted.size()==4 and cover.peeking and cover._capsule.height>1.6,"Finishing a shot cannot steal a still-held manual RMB peek")
	await mouse(center,false,MOUSE_BUTTON_RIGHT)
	await physics_ticks(30)
	check(cover.active and cover.lean.is_zero_approx(),"The manual owner alone controls retuck after its shot")
	combat.shot.disconnect(record)

func side_attack_input_checks(scene, frontier: bool) -> void:
	var actor = scene.player if frontier else scene.actors[0]
	var rig = scene.archer if frontier else actor.rig
	var cover = scene.cover if frontier else actor.cover
	var combat = scene.combat if frontier else actor.combat
	var camera = scene.shoulder_camera if frontier else scene._shoulder_camera
	input_box(scene,Vector3(0,29.5,0),Vector3(16,1,10))
	input_box(scene,Vector3(0,31.5,-1),Vector3(6,3,0.6))
	var center := root.get_visible_rect().size*0.5
	var record := func(origin: Vector3, direction: Vector3, _speed: float, _charge: float):
		var desired: Vector3 = (combat.aim_point-origin).normalized()
		check(cover.peeking and rig.active_bow.get_arrow_direction().dot(desired)>0.98 and direction.dot(desired)>0.999,"Either edge emits its arrow along the visible bow only after physical exposure")
		var arrows: Array = scene.arrows if frontier else scene.projectiles
		check(not arrows.is_empty() and arrows.back().velocity.normalized().dot(direction)>0.999,"Both controller edge attacks spawn a projectile in the actual aimed direction")
	combat.shot.connect(record)
	for side in [1,-1]:
		if cover.active:
			await key(KEY_F)
		actor.position = Vector3(0,30.02,0.1)
		actor.velocity = Vector3.ZERO
		if frontier:
			scene.camera_yaw = 0.0
		else:
			scene._camera_yaw = 0.0
		scene._set_cursor_free(false)
		await physics_ticks(30)
		if not cover.crouch_requested:
			await key(KEY_C)
		await key(KEY_F)
		await physics_ticks(24)
		var movement := KEY_D if side==1 else KEY_A
		held_key(movement,true)
		await physics_ticks(100)
		held_key(movement,false)
		await physics_ticks(3)
		if camera.side!=side:
			await key(KEY_X)
		await key(KEY_1)
		var anchor: Vector3 = actor.position
		var count: int = scene.shots if frontier else scene.shots_fired
		if side==1:
			await mouse(center,true)
		else:
			held_attack(true)
		await physics_ticks(30)
		var desired: Vector3 = (combat.aim_point-rig.get_arrow_origin()).normalized()
		var horizontal := Vector3(desired.x,0,desired.z).normalized()
		check(cover.active and cover.peeking and cover._capsule.height<1.2 and actor.position.distance_to(anchor)>0.35 and actor.position.distance_to(anchor)<0.52,"Real LMB input exposes either edge compactly while staying crouched")
		check((-rig.global_basis.z).dot(horizontal)>0.95 and rig.active_bow.get_arrow_direction().dot(desired)>0.98,"Both real controller shoulder attacks visibly face the shot instead of the tucked direction")
		if side==1:
			await mouse(center,false)
		else:
			held_attack(false)
		await physics_ticks(100)
		check((scene.shots if frontier else scene.shots_fired)==count+1 and cover.active and actor.position.distance_to(anchor)<0.03 and cover._capsule.height<1.2,"Each edge input fires once and restores its protected crouched anchor")
	await key(KEY_F)
	await key(KEY_C)
	combat.shot.disconnect(record)

func lookout_fixture(scene: Node3D, kind: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(0,41.5,0)
	body.collision_layer = 1
	body.collision_mask = 0
	for index in (2 if kind == "compound" else 1):
		var collider := CollisionShape3D.new()
		if kind == "cylinder":
			var shape := CylinderShape3D.new()
			shape.radius = 0.55
			shape.height = 3.0
			collider.shape = shape
		else:
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.1,3.0,0.65 if kind == "compound" else 1.1)
			collider.shape = shape
			if kind == "compound":
				collider.position.z = -0.225 if index == 0 else 0.225
		body.add_child(collider)
	scene.add_child(body)
	return body

func lookout_input_checks(scene, frontier: bool) -> void:
	var actor = scene.player if frontier else scene.actors[0]
	var rig = scene.archer if frontier else actor.rig
	var cover = scene.cover if frontier else actor.cover
	var combat = scene.combat if frontier else actor.combat
	var camera = scene.shoulder_camera if frontier else scene._shoulder_camera
	var center := root.get_visible_rect().size*0.5
	input_box(scene,Vector3(0,39.5,0),Vector3(16,1,16))
	var emitted: Array[Dictionary] = []
	var record := func(origin: Vector3, direction: Vector3, _speed: float, _charge: float):
		check(rig.last_arrow_visual_origin.distance_to(rig.get_arrow_origin())<0.0001,"Shot captures the rendered arrow tip for its visual blend")
		var shot_center := root.get_visible_rect().size*0.5
		var view_origin: Vector3 = scene.camera.project_ray_origin(shot_center)
		var view_direction: Vector3 = scene.camera.project_ray_normal(shot_center)
		check((origin-view_origin).cross(view_direction).length()<0.01,"Cover shot launches on the center crosshair ray")
		check(direction.dot(view_direction)>0.9999,"Cover shot direction is the center crosshair ray")
		check(direction.dot((combat.aim_point-origin).normalized())>0.999,"Lookout projectile preserves the exact aim line")
		var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*2.0,1)
		query.hit_from_inside = true
		check(scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Lookout projectile's first two metres clear the original cover")
		var arrows: Array = scene.arrows if frontier else scene.projectiles
		check(not arrows.is_empty(),"Lookout emits a real collision-enabled arrow")
		if not arrows.is_empty():
			emitted.append({"arrow":arrows.back(),"origin":origin})
	combat.shot.connect(record)
	for kind in ["cylinder","box","compound"]:
		var obstacle := lookout_fixture(scene,kind)
		for mode in 3:
			if cover.active:
				await key(KEY_F)
			await key(KEY_1)
			actor.position = Vector3(0,40.02,1.0)
			actor.velocity = Vector3.ZERO
			if frontier:
				scene.camera_yaw = 0.0
				scene.camera_pitch = 0.0
			else:
				scene._camera_yaw = 0.0
				scene._camera_pitch = 0.0
			scene._set_cursor_free(false)
			await physics_ticks(24)
			if cover.crouch_requested != (mode == 2):
				await key(KEY_C)
			await key(KEY_F)
			await physics_ticks(24)
			check(cover.active and not cover.low,"Real controller attaches to tall "+kind)
			var initial_side := 1 if mode == 1 else -1
			if camera.side != initial_side:
				await key(KEY_X)
			var anchor: Vector3 = actor.position
			var before := emitted.size()
			if mode == 0:
				await mouse(center,true,MOUSE_BUTTON_RIGHT)
				await physics_ticks(30)
			if mode == 2:
				held_attack(true)
			else:
				await mouse(center,true)
			await physics_ticks(30)
			if mode == 1:
				await key(KEY_X)
				await physics_ticks(45)
			check(cover.peeking and cover.lean.x < -0.95 and actor.position.x < anchor.x-0.35,"X-left physically exposes "+kind+" for manual RMB and direct LMB")
			check(rig.phase in ["DRAWING","HOLDING"],"Shoulder swapping preserves the held bow draw")
			var captured: Vector3 = scene._peek_right
			if mode == 2:
				await look(Vector2(-500,0))
				await physics_ticks(8)
				check(scene._peek_right.is_equal_approx(captured) and cover.lean.x < -0.95,"Free look across the side-sign boundary cannot recapture the physical shoulder")
			if mode == 0:
				await mouse(center,false,MOUSE_BUTTON_RIGHT)
				await physics_ticks(30)
				check(not cover.peeking and rig.phase in ["DRAWING","HOLDING"],"Manual left retuck keeps its held draw without claiming automatic exposure")
			if mode == 2:
				held_attack(false)
			else:
				await mouse(center,false)
			await physics_ticks(35)
			check(scene._peek_right.is_equal_approx(captured),"Release and return preserve captured lookout context")
			check(emitted.size() == before+1,"Each clear left lookout fires exactly once from "+kind)
			if emitted.size() == before+1:
				var arrow = emitted.back().arrow
				check(is_instance_valid(arrow) and arrow.flying and arrow.position.distance_to(emitted.back().origin)>1.0,"Actual left projectile travels past cover instead of striking its source obstacle")
			await physics_ticks(80)
			check(cover.active and not cover.peeking and actor.position.distance_to(anchor)<0.03,"Left lookout returns to its protected anchor after release")
		await key(KEY_F)
		obstacle.queue_free()
		await physics_ticks(2)
	# A tiny shaft blocker does not replace the body-lane geometry fixture.
	var obstacle := lookout_fixture(scene,"cylinder")
	for at_nock in [true,false]:
		actor.position = Vector3(0,40.02,1.0)
		actor.velocity = Vector3.ZERO
		if frontier:
			scene.camera_yaw = 0.0
		else:
			scene._camera_yaw = 0.0
		await physics_ticks(24)
		await key(KEY_F)
		await physics_ticks(24)
		await mouse(center,true,MOUSE_BUTTON_RIGHT)
		await physics_ticks(30)
		held_attack(true)
		await physics_ticks(140)
		var nock: Vector3 = rig.active_bow.get_nock_position()
		var point: Vector3 = nock if at_nock else nock.lerp(rig.get_arrow_origin(),0.5)
		var blocker := input_box(scene,point,Vector3.ONE*0.06)
		# A buried nock also overlaps the capsule: release before depenetration
		# moves the actor away and makes the deliberately blocked shaft clear.
		check(not combat._cover_shaft_clear(),"Weapon clearance rejects both an initially buried nock and a blocked shaft midpoint")
		var before := emitted.size()
		held_attack(false)
		await physics_ticks(35)
		check(emitted.size()==before and not combat._release_pending and not rig.charge_frozen,"Obstructed shaft cancels safely without a shot or frozen latent release")
		await mouse(center,false,MOUSE_BUTTON_RIGHT)
		blocker.queue_free()
		await physics_ticks(90)
		check(emitted.size()==before and rig.phase=="READY","Removing an obstruction never resurrects the canceled shot")
		await key(KEY_F)
	obstacle.queue_free()
	if cover.crouch_requested:
		await key(KEY_C)
	combat.shot.disconnect(record)

func cover_input_checks(scene, frontier: bool) -> void:
	var actor: CharacterBody3D = scene.player if frontier else scene.actors[0]
	var rig = scene.archer if frontier else actor.rig
	var cover = scene.cover if frontier else actor.cover
	var roll = scene.roll if frontier else actor.roll
	# One isolated low wall supplies input context, not a second geometry suite.
	# Frontier terrain and enemies cannot interfere with this elevated platform.
	if frontier:
		input_box(scene,Vector3(0,19.5,35),Vector3(16,1,12))
		input_box(scene,Vector3(0,20.7,33),Vector3(3.2,1.4,1.5))
		actor.position = Vector3(0,20.02,34.4)
		scene.camera_yaw = 0.0
	else:
		actor.position = Vector3(0,0.02,-11.6)
		scene._camera_yaw = 0.0
	actor.velocity = Vector3.ZERO
	scene._set_cursor_free(false)
	await physics_ticks(24)
	var armor: int = rig.armor_index
	var standing_height: float = cover._capsule.height
	await key(KEY_C)
	await physics_ticks(24)
	check(cover.crouched and cover._capsule.height<standing_height-0.4,"C crouches outside cover by shrinking the real capsule")
	check(rig.armor_index==armor,"C crouch never changes equipped armor")
	await key(KEY_C)
	await physics_ticks(24)
	check(not cover.crouched and absf(cover._capsule.height-standing_height)<0.02,"Second C restores standing posture and collider")
	check(rig.armor_index==armor,"C stand never changes equipped armor")
	await key(KEY_F)
	await physics_ticks(24)
	check(cover.active and cover.low and cover._capsule.height<1.2,"F enters low cover through the real controller")
	var ordinary: float = await slide_distance(actor,cover,KEY_D,false)
	var fast: float = await slide_distance(actor,cover,KEY_A,true)
	check(ordinary>0.2 and fast>ordinary*1.5,"Shift produces faster attached movement than ordinary slide")
	var wall_face := 33.75 if frontier else -12.25
	check(absf(actor.position.x)<1.6 and actor.position.z>wall_face+0.25,"Both cover slide speeds stay along the actual wall without penetration")
	await key(KEY_1)
	var center := root.get_visible_rect().size*0.5
	await automatic_input_checks(scene,frontier)
	var initial_shots: int = scene.shots if frontier else scene.shots_fired
	await mouse(center,true,MOUSE_BUTTON_RIGHT)
	await physics_ticks(30)
	check(cover.active and cover.peeking and cover._capsule.height>1.6,"Held RMB physically exposes the attached actor")
	await mouse(center,true)
	await physics_ticks(18)
	var peek_height: float = cover._capsule.height
	await physics_ticks(24)
	check(cover.active and cover.peeking and absf(cover._capsule.height-peek_height)<0.02,"Continuously held RMB keeps a stable peek rather than toggling posture")
	var draw_before: float = rig.draw_amount
	await mouse(center,false,MOUSE_BUTTON_RIGHT)
	await physics_ticks(24)
	check(cover.active and not cover.peeking and cover._capsule.height<1.2,"Releasing RMB returns to physically low cover")
	check(rig.phase in ["DRAWING","HOLDING"] and rig.draw_amount>=draw_before,"Returning to cover preserves the held bow draw")
	check((scene.shots if frontier else scene.shots_fired)==initial_shots,"Holding through peek and return never auto-fires")
	await mouse(center,false)
	await physics_ticks(3)
	await physics_ticks(24)
	check((scene.shots if frontier else scene.shots_fired)==initial_shots+1,"Releasing a manually retucked draw re-exposes before launching one real projectile")
	await mouse(center,false)
	await physics_ticks(6)
	check((scene.shots if frontier else scene.shots_fired)==initial_shots+1,"Repeated mouse-up cannot duplicate the cover shot")
	var ground_height: float = actor.position.y
	await key(KEY_SPACE)
	await physics_ticks(5)
	check(not cover.active and not roll.active and actor.position.y>ground_height+0.15 and not actor.is_on_floor(),"Unmodified Space jumps out of low cover without rolling")
	check(not cover.crouch_requested and cover._capsule.height>=standing_height-0.02,"Cover jump immediately restores the standing collider")

func drain_audio(scene) -> void:
	for voice in scene.audio.voices:
		if voice.playing:
			await voice.finished

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.45).timeout
	await equipment_checks(game,game.archer,true)
	var yaw: float = game.camera_yaw
	await look(Vector2(45,0))
	check(absf(game.camera_yaw-yaw)>0.1,"Frontier mouse movement turns view without holding RMB")
	check(game.hud.reticle.is_equal_approx(root.get_visible_rect().size*0.5),"Frontier reticle stays at screen center")
	await crosshair_shoulder_checks(game,true)
	await cover_input_checks(game,true)
	await side_attack_input_checks(game,true)
	await lookout_input_checks(game,true)
	await drain_audio(game)
	game.queue_free()
	await process_frame
	await process_frame
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	var socket := PacketPeerUDP.new()
	check(socket.bind(0)==OK,"A free network test port is available")
	var port := socket.get_local_port()
	socket.close()
	arena.host_game(port,"Input regression")
	for actor in arena.actors:
		actor.is_bot = false
	await create_timer(0.4).timeout
	await equipment_checks(arena,arena.actors[0].rig,false)
	var rig = arena.actors[0].rig
	rig.set_bow(1)
	var center := root.get_visible_rect().size*0.5
	var victim = arena.actors[1]
	arena.actors[0].position = Vector3(0,0.02,7)
	arena._camera_yaw = 0
	arena._camera_pitch = 0.08
	await create_timer(0.2).timeout
	arena._update_game_camera()
	var ray_origin: Vector3 = arena.camera.project_ray_origin(center)
	var ray_direction: Vector3 = arena.camera.project_ray_normal(center)
	var on_ray := ray_origin + ray_direction*10.0
	victim.position = Vector3(on_ray.x,0.02,on_ray.z)
	victim.health = 100
	await physics_frame
	await physics_frame
	await mouse(center,true)
	await create_timer(0.55).timeout
	check(arena.shots_fired==0 and victim.health==100,"Mouse hold cannot fire or damage an aimed-at player")
	var start_yaw: float = arena._camera_yaw
	await look(Vector2(55,-8))
	check(absf(arena._camera_yaw-start_yaw)>0.1,"Aim remains freely mouse-controlled during draw")
	check(arena.hud.reticle.is_equal_approx(center),"Aim reticle never follows the target off center")
	await look(Vector2(-55,8))
	await create_timer(1.6).timeout
	check(rig.phase=="HOLDING" and arena.shots_fired==0,"Fully drawn bow waits for release indefinitely")
	var old_position: Vector3 = victim.position
	victim.position.x += 3
	await physics_frame
	await physics_frame
	var free_point: Vector3 = arena._crosshair_aim()
	var view_direction: Vector3 = arena.camera.project_ray_normal(center)
	check((free_point-arena.camera.project_ray_origin(center)).normalized().dot(view_direction)>0.99999,"Moving target does not pull the camera ray or create lock-on")
	victim.position = old_position
	await physics_frame
	await physics_frame
	await mouse(center,false)
	check(arena.shots_fired==1 and victim.health==100,"Release launches one projectile without applying hitscan damage")
	if arena.projectiles.is_empty():
		arena.leave_game()
		quit(1)
		return
	var arrow = arena.projectiles.back()
	check(arrow.velocity.normalized().dot((arena.actors[0].combat.aim_point-arrow.position).normalized())>0.999,"Arrow starts on the actual aim line without compensation")
	await create_timer(0.5).timeout
	check(is_equal_approx(victim.health,62.0),"Damage is applied when the full-draw arrow actually reaches the collider")
	await create_timer(0.8).timeout
	check(arena.shots_fired==1,"Releasing does not enable automatic fire")
	await crosshair_shoulder_checks(arena,false)
	await cover_input_checks(arena,false)
	await side_attack_input_checks(arena,false)
	await lookout_input_checks(arena,false)
	await drain_audio(arena)
	arena.leave_game()
	arena.queue_free()
	await process_frame
	print("WEAPON_INPUT_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
