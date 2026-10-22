extends Node3D

const Actor = preload("res://scripts/arena_actor.gd")
const World = preload("res://scripts/arena_world.gd")
const Hud = preload("res://scripts/arena_hud.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Combat = preload("res://scripts/combat.gd")
const ShoulderCamera = preload("res://scripts/shoulder_camera.gd")
var actors: Array = []
var local_slot := -1
var network_role := "offline"
var server_tick := 0
var last_snapshot_tick := -1
var projectiles: Array[Node3D] = []
var shots_fired := 0
var world
var hud
var audio
var camera: Camera3D
var _peer_slots: Dictionary = {}
# Per actor: newest snapshot sent by the host or applied by this client.
var _snapshot_ticks := PackedInt32Array([-1,-1,-1,-1])
var _player_name := "Ranger"
var _endpoint := ""
var _join_elapsed := 0.0
var _send_elapsed := 0.0
var _camera_yaw := 0.65
var _camera_pitch := 0.08
var _camera_distance := 4.5
var _shoulder_camera := ShoulderCamera.new()
var _cursor_free := true
var _mouse_drawing := false
var _key_drawing := false
var _peek_held := false
var _peek_right := Vector3.RIGHT
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	name = "Arena"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world = World.new()
	add_child(world)
	for index in 4:
		var actor := Actor.new()
		actor.slot = index
		actor.name = "Fighter%d" % index
		add_child(actor)
		actor.configure(0,true,"Bot %d" % (index+1),world.spawn_points[index])
		actor.fired.connect(_on_fired)
		actor.killed.connect(_on_killed)
		actor.visible = false
		actors.append(actor)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 59
	camera.near = 0.08
	camera.far = 150
	add_child(camera)
	camera.position = Vector3(23,24,25)
	camera.look_at(Vector3.ZERO)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.host_requested.connect(host_game)
	hud.join_requested.connect(join_game)
	hud.leave_requested.connect(leave_game)
	hud.frontier_requested.connect(_frontier)
	hud.bow_selected.connect(func(index: int): send_action("bow",index))
	hud.armor_selected.connect(func(index: int): send_action("armor",index))
	hud.sword_selected.connect(func(index: int): send_action("sword",index))
	hud.weapon_selected.connect(func(value: String): send_action("weapon",value))
	audio = Audio.new()
	add_child(audio)
	_query.collision_mask = 1 | 4
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _connection_ended("Could not join. Check address, UDP port and host capacity (four players)."))
	multiplayer.server_disconnected.connect(func(): _connection_ended("The host disconnected. Host a new match or join another game."))
	call_deferred("_read_arguments")

func _read_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var port := 7777
	var player_name := "Ranger"
	var address := ""
	for index in args.size():
		if args[index] == "--arena-port" and index+1 < args.size():
			port = args[index+1].to_int()
		elif args[index] == "--arena-name" and index+1 < args.size():
			player_name = args[index+1]
		elif args[index] == "--arena-join" and index+1 < args.size():
			address = args[index+1]
	if args.has("--arena-host"):
		host_game(port,player_name)
	elif not address.is_empty():
		join_game(address,port,player_name)

func host_game(port: int, player_name: String) -> void:
	leave_game()
	if port < 1024 or port > 65535:
		hud.set_status("Choose a UDP port between 1024 and 65535.")
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port,3)
	if error != OK:
		hud.set_status("Could not host on UDP %d: %s" % [port,error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	network_role = "host"
	local_slot = 0
	_camera_yaw = atan2(world.spawn_points[0].x,world.spawn_points[0].z)
	_peer_slots[1] = 0
	_player_name = _safe_name(player_name)
	for actor in actors:
		actor.authoritative = true
		actor.visible = true
		actor.configure(1 if actor.slot == 0 else 0,actor.slot != 0,_player_name if actor.slot == 0 else "Bot %d" % actor.slot,world.spawn_points[actor.slot])
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
			addresses.append(address)
	_endpoint = "UDP %d / LAN %s / same PC 127.0.0.1" % [port,", ".join(addresses)]
	hud.show_match(_player_name,_endpoint)
	_set_cursor_free(false)
	print("ARENA_HOST_READY port=",port)

func join_game(address: String, port: int, player_name: String) -> void:
	leave_game()
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		hud.set_status("Enter a host address and a UDP port between 1024 and 65535.")
		return
	_player_name = _safe_name(player_name)
	_endpoint = "%s:%d" % [address.strip_edges(),port]
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(),port)
	if error != OK:
		hud.set_status("Could not start connection: " + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	network_role = "client"
	_join_elapsed = 0
	hud.set_status("Connecting to " + _endpoint + "...")

func leave_game() -> void:
	network_role = "offline"
	local_slot = -1
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer_slots.clear()
	last_snapshot_tick = -1
	_snapshot_ticks.fill(-1)
	server_tick = 0
	_send_elapsed = 0
	shots_fired = 0
	_mouse_drawing = false
	_key_drawing = false
	_peek_held = false
	_peek_right = Vector3.RIGHT
	_cursor_free = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	for actor in actors:
		actor.combat.stop()
		actor.reset_stance()
		actor.authoritative = false
		actor.combat.damage_enabled = false
		actor.visible = false
		actor.collision_layer = 0
		actor.collision_mask = 0
	hud.show_lobby()

func _connection_ended(message: String) -> void:
	leave_game()
	hud.set_status(message)
	print("ARENA_CONNECTION_ENDED ",message)

func _frontier() -> void:
	leave_game()
	get_tree().change_scene_to_file("res://main.tscn")

func _safe_name(value: String) -> String:
	var result := value.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	return "Ranger" if result.is_empty() else result

func get_human_count() -> int:
	var count := 0
	for actor in actors:
		if not actor.is_bot:
			count += 1
	return count if network_role != "offline" else 0

func _peer_connected(peer_id: int) -> void:
	if network_role != "host":
		return
	multiplayer.multiplayer_peer.get_peer(peer_id).set_timeout(32,2000,5000)
	for actor in actors:
		if actor.is_bot:
			_clear_slot_arrows(actor.slot)
			actor.configure(peer_id,false,"Joining ranger",world.spawn_points[actor.slot])
			_peer_slots[peer_id] = actor.slot
			_accept.rpc_id(peer_id,actor.slot)
			print("ARENA_PEER_JOINED slot=",actor.slot," humans=",get_human_count())
			return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func _peer_disconnected(peer_id: int) -> void:
	if network_role != "host" or not _peer_slots.has(peer_id):
		return
	var slot: int = _peer_slots[peer_id]
	_peer_slots.erase(peer_id)
	_clear_slot_arrows(slot)
	actors[slot].configure(0,true,"Bot %d" % slot,world.spawn_points[slot])
	print("ARENA_BOT_RESTORED slot=",slot," humans=",get_human_count())

func _clear_slot_arrows(slot: int) -> void:
	for index in range(projectiles.size()-1,-1,-1):
		var projectile = projectiles[index]
		if not is_instance_valid(projectile):
			projectiles.remove_at(index)
		elif projectile.source_id == slot:
			projectile.queue_free()
			projectiles.remove_at(index)
	_clear_remote_arrows.rpc(slot)

@rpc("authority","call_remote","reliable")
func _clear_remote_arrows(slot: int) -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile) and projectile.source_id == slot:
			projectile.queue_free()

func _connected() -> void:
	multiplayer.multiplayer_peer.get_peer(1).set_timeout(32,2000,5000)
	_register.rpc_id(1,_player_name)

@rpc("any_peer","call_remote","reliable")
func _register(player_name: String) -> void:
	if network_role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if _peer_slots.has(sender):
		actors[int(_peer_slots[sender])].display_name = _safe_name(player_name)

@rpc("authority","call_remote","reliable")
func _accept(slot: int) -> void:
	if network_role != "client" or slot < 1 or slot > 3:
		return
	local_slot = slot
	_camera_yaw = atan2(world.spawn_points[slot].x,world.spawn_points[slot].z)
	for actor in actors:
		actor.authoritative = false
		actor.visible = true
	hud.show_match(_player_name,_endpoint)
	_set_cursor_free(false)
	print("ARENA_CLIENT_READY slot=",slot)

func _physics_process(delta: float) -> void:
	if network_role == "offline":
		return
	if network_role == "client" and local_slot < 0:
		_join_elapsed += delta
		if _join_elapsed > 6.0:
			_connection_ended("Connection timed out. The host may be offline, full, or blocked by a firewall.")
		return
	_send_elapsed += delta
	if local_slot >= 0:
		var x := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		var z := float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
		var motion := Vector2(x,z).limit_length()
		if _cursor_free:
			motion = Vector2.ZERO
		var right := Vector2(cos(_camera_yaw),-sin(_camera_yaw))
		var back := Vector2(sin(_camera_yaw),cos(_camera_yaw))
		var direction := right*motion.x + back*motion.y
		var running := Input.is_physical_key_pressed(KEY_SHIFT)
		if network_role == "host":
			_set_movement(local_slot,direction,running,_crosshair_aim())
		elif _send_elapsed >= 0.05:
			_move_input.rpc_id(1,direction,running,_crosshair_aim(),_snapshot_ticks[local_slot])
	if network_role == "host":
		server_tick += 1
		for actor in actors:
			actor.step(delta,actors,server_tick)
		if _send_elapsed >= 0.05:
			# One fighter per datagram stays below ENet's MTU without fragmentation.
			for actor in actors:
				_receive_snapshot.rpc(server_tick,actor.slot,actor.snapshot())
				_snapshot_ticks[actor.slot] = server_tick
	if _send_elapsed >= 0.05:
		_send_elapsed = fmod(_send_elapsed,0.05)

func _set_movement(slot: int, direction: Vector2, running: bool, aim: Vector3, aim_tick: int = -1) -> void:
	if not direction.is_finite() or not _set_aim(slot,aim,aim_tick):
		return
	actors[slot].move_direction = direction.limit_length()
	actors[slot].run_requested = running
	actors[slot].input_age = 0

func _set_aim(slot: int, point: Vector3, aim_tick: int = -1) -> bool:
	if not point.is_finite() or point.length_squared() > 1000000.0:
		return false
	var actor = actors[slot]
	if actor.peer_id > 1:
		if aim_tick < 0 or aim_tick > _snapshot_ticks[slot]:
			return false
		# Reliable draw/release may arrive after a newer movement aim. Honor
		# the action without rewinding its aim or exposure acknowledgement.
		if aim_tick < actor.aim_snapshot_tick:
			return true
		actor.aim_snapshot_tick = aim_tick
	actor.update_cover_aim_readiness()
	actors[slot].combat.set_aim(point)
	return true

@rpc("any_peer","call_remote","unreliable_ordered")
func _move_input(direction: Vector2, running: bool, aim: Vector3, aim_tick: Variant) -> void:
	if network_role != "host" or typeof(aim_tick) != TYPE_INT:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _peer_slots.has(sender):
		_set_movement(int(_peer_slots[sender]),direction,running,aim,aim_tick)

@rpc("authority","call_remote","unreliable")
func _receive_snapshot(tick: int, slot: int, state: Dictionary) -> void:
	if network_role != "client" or slot < 0 or slot >= 4 or tick <= _snapshot_ticks[slot]:
		return
	_snapshot_ticks[slot] = tick
	last_snapshot_tick = maxi(last_snapshot_tick,tick)
	actors[slot].apply_snapshot(state)

func send_action(action: String, value: Variant = null) -> void:
	if local_slot < 0:
		return
	if action in ["bow","sword","weapon","armor"]:
		_cancel_draw_input()
	if action == "draw" and not _peek_held and actors[local_slot].rig.phase == "READY":
		_capture_peek_context()
	if action in ["draw","release"]:
		_send_peek_input()
	if network_role == "host":
		_apply_action(local_slot,action,value)
	elif network_role == "client":
		_action_input.rpc_id(1,action,value,_snapshot_ticks[local_slot])

@rpc("any_peer","call_remote","reliable")
func _action_input(action: String, value: Variant, aim_tick: Variant) -> void:
	if network_role != "host" or typeof(aim_tick) != TYPE_INT:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _peer_slots.has(sender):
		var slot := int(_peer_slots[sender])
		if aim_tick < 0 or aim_tick > _snapshot_ticks[slot]:
			return
		_apply_action(slot,action,value,aim_tick)

func _apply_action(slot: int, action: String, value: Variant, aim_tick: int = -1) -> void:
	var actor = actors[slot]
	if not actor.alive:
		return
	match action:
		"draw":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick):
				actor.update_combat_cover_side()
				if actor.rig.weapon == "sword":
					actor.combat.begin_melee()
				else:
					actor.combat.begin_draw()
		"release":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick):
				actor.update_combat_cover_side()
				actor.combat.release_draw()
		"stop": actor.combat.stop()
		"jump":
			if typeof(value) == TYPE_BOOL:
				actor.press_jump(value)
		"cover":
			if typeof(value) == TYPE_VECTOR3 and value.is_finite() and value.length_squared() > 0.01 and value.length_squared() <= 1000000.0:
				actor.toggle_cover(value.normalized())
		"crouch":
			if typeof(value) == TYPE_BOOL:
				actor.set_crouch(value)
		"peek":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("right")) != TYPE_VECTOR3 or typeof(value.get("side")) != TYPE_INT:
				return
			var right: Vector3 = value.right
			if not right.is_finite() or absf(right.y) > 0.01 or absf(right.length_squared()-1.0) > 0.01 or value.side not in [-1,1]:
				return
			actor.peek_requested = value.pressed
			actor.peek_view_right = Vector3(right.x,0,right.z).normalized()
			actor.peek_shoulder = value.side
			actor.update_combat_cover_side()
		"bow":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				actor.rig.set_bow(value)
		"sword":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				actor.rig.set_sword(value)
		"weapon":
			if typeof(value) == TYPE_STRING and value in ["bow","sword"]:
				actor.combat.stop()
				actor.rig.set_weapon(value)
		"armor":
			if typeof(value) == TYPE_INT and value >= 0 and value < 3:
				actor.rig.set_armor(value)

func _on_fired(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	if network_role != "host":
		return
	var damage := Combat.damage_for(actors[slot].rig.bow_index,charge)
	_spawn_arrow(slot,origin,direction,speed,damage,true)
	_arrow_event.rpc(slot,origin,direction,speed)
	shots_fired += 1

func _spawn_arrow(slot: int, origin: Vector3, direction: Vector3, speed: float, damage: float, authoritative: bool) -> void:
	var arrow := Arrow.new()
	arrow.source_id = slot
	arrow.hit_mask = 1 | 4
	arrow.authoritative_damage = authoritative
	add_child(arrow)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	arrow.launch(origin,direction,speed,damage,excluded)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(arrow)
	if projectiles.size() > 128:
		projectiles.pop_front().queue_free()
	if slot == local_slot:
		audio.play_sound("release")

@rpc("authority","call_remote","reliable")
func _arrow_event(slot: int, origin: Vector3, direction: Vector3, speed: float) -> void:
	if network_role == "client" and slot >= 0 and slot < 4:
		_spawn_arrow(slot,origin,direction,speed,0.0,false)
		shots_fired += 1

func _on_killed(slot: int, source: int) -> void:
	if network_role == "host" and source >= 0 and source < 4 and source != slot:
		actors[source].kills += 1
		print("ARENA_KILL source=",source," victim=",slot)

func _process(delta: float) -> void:
	if local_slot < 0:
		return
	var actor = actors[local_slot]
	if not actor.alive and (_peek_held or _mouse_drawing or _key_drawing):
		_peek_held = false
		_cancel_draw_input()
	_shoulder_camera.update(delta)
	_update_game_camera()
	var rows: Array[Dictionary] = []
	for fighter in actors:
		rows.append({"slot":fighter.slot,"name":fighter.display_name,"bot":fighter.is_bot,"health":fighter.health,"kills":fighter.kills,"deaths":fighter.deaths})
	hud.update_match({"players":rows,"local_slot":local_slot,"health":actor.health,"movement":actor.combat.movement_mode,
		"attack_interval":actor.combat.get_attack_interval(),"attack_progress":actor.combat.attack_progress,
		"phase":actor.rig.phase,"draw":actor.rig.draw_amount,"bow":actor.rig.bow_index,"armor":actor.rig.armor_index,"sword":actor.rig.sword_index,"weapon":actor.rig.weapon,"respawn":actor.respawn})
	hud.update_cover(actor.cover.active,actor.cover.low,actor.cover.peeking,_shoulder_camera.side,actor.cover.crouched,actor.rig.slide_progress >= 0.0)
	hud.reticle_visible = actor.alive and not _cursor_free
	hud.reticle = get_viewport().get_visible_rect().size * 0.5

func _update_game_camera() -> void:
	var actor = actors[local_slot]
	var height: float = actor.cover.camera_height()
	var focus: Vector3 = actor.position + Vector3(0,height,0)
	var back := Vector3(sin(_camera_yaw)*cos(_camera_pitch),sin(_camera_pitch),cos(_camera_yaw)*cos(_camera_pitch))
	camera.position = _shoulder_camera.resolve(get_world_3d().direct_space_state,focus,back,_camera_distance)
	camera.look_at(camera.position-back)

func _set_cursor_free(value: bool) -> void:
	_cursor_free = value
	if value:
		_cancel_draw_input()
		_peek_held = false
		_send_peek_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _crosshair_aim() -> Vector3:
	_update_game_camera()
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	# Match frontier: shoulder and bow poses must not move the start past a target.
	var actor = actors[local_slot]
	var aim_anchor: Vector3 = actor.global_position + Vector3.UP*actor.cover.camera_height()
	var actor_depth := maxf(0.0,(aim_anchor-ray_origin).dot(ray_direction))
	_query.from = ray_origin + ray_direction*actor_depth
	_query.to = ray_origin + ray_direction*120.0
	_query.exclude = [actors[local_slot].get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	return hit.position if not hit.is_empty() else _query.to

func _input(event: InputEvent) -> void:
	if local_slot < 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_peek_held = false
		_send_peek_input()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _mouse_drawing:
			_mouse_drawing = false
			if not _key_drawing:
				send_action("release",_crosshair_aim())
	if event is InputEventKey and event.keycode == KEY_Q and not event.pressed:
		if _key_drawing:
			_key_drawing = false
			if not _mouse_drawing:
				send_action("release",_crosshair_aim())

func _cancel_draw_input() -> void:
	_mouse_drawing = false
	_key_drawing = false
	send_action("stop")

func _capture_peek_context() -> void:
	_peek_right = Vector3(cos(_camera_yaw),0,-sin(_camera_yaw))

func _send_peek_input() -> void:
	send_action("peek",{"pressed":_peek_held,"right":_peek_right,"side":_shoulder_camera.side})

func _unhandled_input(event: InputEvent) -> void:
	if local_slot < 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: send_action("weapon","bow")
			KEY_2: send_action("weapon","sword")
			KEY_C:
				if not _cursor_free:
					send_action("crouch",not actors[local_slot].cover.crouch_requested)
			KEY_SPACE:
				if not _cursor_free:
					_peek_held = false
					_send_peek_input()
					send_action("jump",event.shift_pressed)
			KEY_F:
				if not _cursor_free:
					_cancel_draw_input()
					_peek_held = false
					_capture_peek_context()
					_send_peek_input()
					send_action("cover",Vector3(-sin(_camera_yaw),0,-cos(_camera_yaw)))
			KEY_X:
				_shoulder_camera.swap()
				_capture_peek_context()
				_send_peek_input()
			KEY_ESCAPE, KEY_I: _set_cursor_free(not _cursor_free)
			KEY_Q:
				_set_cursor_free(false)
				_key_drawing = true
				if not _mouse_drawing:
					send_action("draw",_crosshair_aim())
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_set_cursor_free(false)
			_mouse_drawing = true
			if not _key_drawing:
				send_action("draw",_crosshair_aim())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_cursor_free(false)
			_peek_held = true
			_capture_peek_context()
			_send_peek_input()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(3,_camera_distance-0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(17,_camera_distance+0.5)
	if event is InputEventMouseMotion and not _cursor_free:
		_camera_yaw -= event.relative.x*0.004
		_camera_pitch = clampf(_camera_pitch+event.relative.y*0.004,-0.7,0.7)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and local_slot >= 0:
		_set_cursor_free(true)

func _exit_tree() -> void:
	multiplayer.multiplayer_peer.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
