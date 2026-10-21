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

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
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
	check(rig.bow_index == 2 and rig.sword_index == 0 and rig.weapon == "bow","Key 3 cannot select or cycle a size")
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
	await drain_audio(arena)
	arena.leave_game()
	arena.queue_free()
	await process_frame
	print("WEAPON_INPUT_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
