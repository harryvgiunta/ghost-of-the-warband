extends Node3D
## Host-authoritative controller for "The Sunken Delve".
##
## One sealed chamber, three waves of cinder devils trickling out of four dark
## archways, a cache when a wave breaks, and a checkpointed run that can be
## resumed or wiped. Networking follows the arena: the host simulates every
## body, clients send input and action intents, and snapshots drive the
## replicas. Everything the host decides about the run itself travels as a
## reliable run state so the HUD and caches cannot drift apart.

const Actor = preload("res://scripts/delve_actor.gd")
const Devil = preload("res://scripts/delve_devil.gd")
const Chest = preload("res://scripts/delve_chest.gd")
const World = preload("res://scripts/delve_world.gd")
const Hud = preload("res://scripts/delve_hud.gd")
const Progress = preload("res://scripts/delve_progress.gd")
const Archer = preload("res://scripts/archer.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Thrown = preload("res://scripts/thrown_weapon.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Combat = preload("res://scripts/combat.gd")
const ShoulderCamera = preload("res://scripts/shoulder_camera.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const LootPickup = preload("res://scripts/loot_pickup.gd")
const FieldInventoryScript = preload("res://scripts/field_inventory.gd")

const INTERACT_RANGE := 4.0
const PICKUP_RADIUS := 1.6
const DROP_FULL_INTERVAL := 2.5
const CHEST_RANGE := 3.5
const DEVIL_TRICKLE := 1.4
const CLEAR_DELAY := 2.2
const SNAPSHOT_INTERVAL := 0.05
const RUN_STATE_INTERVAL := 0.2
const MAX_SHOTS := 128
const AUTO_BEGIN_DELAY := 2.0
const HOOK_KILL_DELAY := 2.0

var world
var hud
var audio
var camera: Camera3D
var actors: Array = []
var devils: Array = []
var chest
var local_slot := -1
var network_role := "offline"
var phase := "ASSEMBLY"
var wave := 1
var chest_ready := false
var chest_open := false
var run_seed := 0
var save_path: String = Progress.SAVE_PATH
var resume_data: Dictionary = {}
var server_tick := 0
var last_snapshot_tick := -1
var projectiles: Array[Node3D] = []
var shots_fired := 0
var throws_fired := 0

var _peer_slots: Dictionary = {}
var _snapshot_ticks := PackedInt32Array([-1,-1,-1,-1])
var _player_name := "Ranger"
var _endpoint := ""
var _remote_state: Dictionary = {}
var _join_elapsed := 0.0
var _send_elapsed := 0.0
var _run_send_elapsed := 0.0
var _elapsed := 0.0
var _mode_elapsed := 0.0
var _wave_elapsed := 0.0
var _clear_timer := 0.0
var _spawn_timer := 0.0
var _spawn_queue: Array = []
var _next_devil_id := 1
var _devil_nodes: Dictionary = {}
var _devil_dead_ids: Dictionary = {}
var _last_devil_tick := -1
var _auto_start := false
var _kill_wave_hook := false
var _exit_after := 0.0
var _auto_fired := false
var _kill_fired := false
var _camera_yaw := 0.65
var _camera_pitch := 0.08
var _camera_distance := 4.5
var _shoulder_camera := ShoulderCamera.new()
var _cursor_free := true
var _mouse_drawing := false
var _throw_held := false
var _next_swing_side := 0
var _peek_held := false
var _peek_right := Vector3.RIGHT
var _query := PhysicsRayQueryParameters3D.new()
var _aim_origin := Vector3.ZERO
var _aim_origin_valid := false
var loot_pickups: Array = []
var _field_inventory
var _player_state
var _drop_query := PhysicsRayQueryParameters3D.new()
var _loot_message_cooldown := 0.0

func _ready() -> void:
	name = "Delve"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world = World.new()
	add_child(world)
	world.set_sealed(false)
	for index in 4:
		var actor := Actor.new()
		actor.slot = index
		actor.name = "Delver%d" % index
		add_child(actor)
		actor.bounds = float(World.LIMIT) - 0.4
		actor.interp_delay = 0.12
		actor.authoritative = false
		actor.visible = false
		actor.alive = false
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.combat.target_mask = 2
		actor.combat.damage_enabled = false
		actor.fired.connect(_on_fired)
		actor.thrown_weapon.connect(_on_thrown_weapon)
		actor.fell.connect(_on_actor_fell)
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
	hud.hub_requested.connect(_hub)
	hud.surface_requested.connect(_on_surface_requested)
	_player_state = get_node_or_null("/root/PlayerState")
	if _player_state != null:
		_field_inventory = FieldInventoryScript.new()
		_field_inventory.name = "FieldInventory"
		_field_inventory.layer = layer.layer + 1
		add_child(_field_inventory)
		_field_inventory.opened.connect(_on_field_opened)
		_field_inventory.closed.connect(_on_field_closed)
		_field_inventory.loadout_changed.connect(_on_field_loadout_changed)
		_field_inventory.configure(_player_state,get_node_or_null("/root/Session"),null,Callable(self,"_drop_field_item"))
	audio = Audio.new()
	add_child(audio)
	_query.collision_mask = 1 | 2
	_drop_query.collision_mask = 1
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _connection_ended("Could not join. Check the address, UDP port and host capacity (four delvers)."))
	multiplayer.server_disconnected.connect(func(): _connection_ended("The host disconnected. Host a new delve or join another party."))
	resume_data = Progress.load_run(save_path)
	if not resume_data.is_empty():
		run_seed = int(resume_data.get("seed", 0))
	call_deferred("_read_arguments")

func _read_arguments() -> void:
	var pending: Dictionary = {}
	var session_node := get_node_or_null("/root/Session")
	if session_node != null:
		pending = session_node.take()
	var args := OS.get_cmdline_user_args()
	var port := 7777
	var port_set := false
	var player_name := "Ranger"
	var name_set := false
	var address := ""
	var host := false
	var solo := false
	for index in args.size():
		var argument := args[index]
		if argument == "--delve-port" and index+1 < args.size():
			port = args[index+1].to_int()
			port_set = true
		elif argument == "--delve-name" and index+1 < args.size():
			player_name = args[index+1]
			name_set = true
		elif argument == "--delve-join" and index+1 < args.size():
			address = args[index+1]
		elif argument == "--delve-exit-after" and index+1 < args.size():
			_exit_after = args[index+1].to_float()
		elif argument == "--delve-host":
			host = true
		elif argument == "--delve-solo":
			solo = true
		elif argument == "--delve-auto":
			_auto_start = true
		elif argument == "--delve-kill-wave":
			_kill_wave_hook = true
	var session_port := int(pending.get("port", port))
	var session_name := str(pending.get("name", player_name))
	var final_port := port if port_set else session_port
	var final_name := player_name if name_set else session_name
	if final_name.strip_edges().is_empty():
		final_name = "Ranger"
	# Explicit command-line intent stays authoritative; the hub request fills the gap.
	if host:
		host_game(final_port,final_name,false)
	elif solo:
		host_game(final_port,final_name,true)
	elif not address.is_empty():
		join_game(address,final_port,final_name)
	else:
		match str(pending.get("mode", "")):
			"delve-solo":
				host_game(final_port,final_name,true)
			"delve-host":
				host_game(final_port,final_name,false)
			"delve-join", "delve-client":
				join_game(str(pending.get("address", address)),final_port,final_name)

func host_game(port: int, player_name: String, find_open_port: bool = false) -> void:
	leave_game()
	if port < 1024 or port > 65535:
		hud.set_status("Choose a UDP port between 1024 and 65535.")
		return
	if find_open_port:
		var open_port := _find_open_port(port)
		if open_port <= 0:
			hud.set_status("No free UDP port near %d. Close another host and try again." % port)
			return
		port = open_port
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port,3)
	if error != OK and find_open_port:
		# A solo run must not lose to an existing host on the default port.
		for offset in range(1,16):
			var candidate := port + offset
			if candidate > 65535:
				break
			var retry := ENetMultiplayerPeer.new()
			var retry_error := retry.create_server(candidate,3)
			if retry_error == OK:
				peer = retry
				port = candidate
				error = OK
				break
	if error != OK:
		hud.set_status("Could not host on UDP %d: %s" % [port,error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	network_role = "host"
	local_slot = 0
	_peer_slots.clear()
	_peer_slots[1] = 0
	_player_name = _safe_name(player_name)
	resume_data = Progress.load_run(save_path)
	if resume_data.is_empty():
		run_seed = randi()
	else:
		run_seed = int(resume_data.get("seed", randi()))
	_on_devils_reset_local()
	for actor in actors:
		actor.authoritative = true
		actor.is_local = false
		actor.visible = false
		actor.alive = false
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.combat.target_mask = 2
		actor.combat.damage_enabled = false
	var local = actors[0]
	local.configure(1,false,_player_name,_assembly_spawn(0))
	local.visible = true
	local.is_local = true
	local.collision_layer = 4
	local.collision_mask = 1
	local.combat.target_mask = 2
	local.combat.damage_enabled = true
	_camera_yaw = atan2(local.global_position.x,local.global_position.z)
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
			addresses.append(address)
	_endpoint = "UDP %d / LAN %s / same PC 127.0.0.1" % [port,", ".join(addresses)]
	hud.configure(_endpoint)
	hud.set_status("Descend when the party is ready.",2.5)
	_set_cursor_free(false)
	_remember_network(_player_name,"",port)
	_apply_loadout(0,_local_loadout())
	_bind_field_rig()
	_mode_elapsed = 0.0
	_auto_fired = false
	_set_phase("ASSEMBLY")
	print("DELVE_HOST_READY port=%d" % port)

func join_game(address: String, port: int, player_name: String) -> void:
	leave_game()
	if address.strip_edges().is_empty() or port < 1024 or port > 65535:
		hud.set_status("Enter a host address and a UDP port between 1024 and 65535.")
		return
	_player_name = _safe_name(player_name)
	_endpoint = "%s:%d" % [address.strip_edges(),port]
	_remember_network(_player_name,address.strip_edges(),port)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(),port)
	if error != OK:
		hud.set_status("Could not start connection: " + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	network_role = "client"
	_join_elapsed = 0.0
	hud.configure(_endpoint)
	hud.set_status("Connecting to " + _endpoint + "...")

func leave_game() -> void:
	# A server-disconnected signal can arrive while the scene is being freed;
	# there is no MultiplayerAPI left to close at that point.
	if not is_inside_tree() or multiplayer == null:
		return
	network_role = "offline"
	local_slot = -1
	if _field_inventory != null:
		if _field_inventory.is_open():
			_field_inventory.close()
		_field_inventory.rebind(null)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer_slots.clear()
	_remote_state.clear()
	_snapshot_ticks.fill(-1)
	last_snapshot_tick = -1
	_last_devil_tick = -1
	server_tick = 0
	_send_elapsed = 0.0
	_run_send_elapsed = 0.0
	_join_elapsed = 0.0
	_mode_elapsed = 0.0
	_elapsed = 0.0
	_wave_elapsed = 0.0
	_clear_timer = 0.0
	_spawn_timer = 0.0
	_spawn_queue.clear()
	_auto_fired = false
	_kill_fired = false
	_next_devil_id = 1
	shots_fired = 0
	throws_fired = 0
	_mouse_drawing = false
	_throw_held = false
	_peek_held = false
	_next_swing_side = 0
	_peek_right = Vector3.RIGHT
	_cursor_free = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phase = "ASSEMBLY"
	wave = 1
	chest_ready = false
	chest_open = false
	_clear_devils()
	_remove_chest()
	_on_devils_reset_local()
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	for entry in loot_pickups:
		var pickup = entry.get("node")
		if is_instance_valid(pickup):
			pickup.queue_free()
	loot_pickups.clear()
	for actor in actors:
		actor.combat.stop()
		actor.reset_stance()
		actor.authoritative = false
		actor.is_local = false
		actor.combat.damage_enabled = false
		actor.visible = false
		actor.alive = false
		actor.collision_layer = 0
		actor.collision_mask = 0
	if world != null:
		world.set_sealed(false)

func _connection_ended(message: String) -> void:
	if not is_inside_tree():
		return
	leave_game()
	hud.show_connection_lost(message)
	print("DELVE_CONNECTION_ENDED %s" % message)

func _hub() -> void:
	leave_game()
	get_tree().change_scene_to_file("res://menu.tscn")

func _on_surface_requested() -> void:
	if network_role == "host" and (phase == "CLEARED" or phase == "COMPLETE"):
		ascend_to_surface()
		return
	leave_game()
	get_tree().change_scene_to_file("res://main.tscn")

func _find_open_port(start: int) -> int:
	var last := mini(start+15,65535)
	for candidate in range(start,last+1):
		var probe := PacketPeerUDP.new()
		var error := probe.bind(candidate)
		probe.close()
		if error == OK:
			return candidate
	return 0

func _safe_name(value: String) -> String:
	var result := value.strip_edges().replace("\n"," ").replace("\r"," ").replace("\t"," ").left(16)
	return "Ranger" if result.is_empty() else result

func _remember_network(player_name: String, address: String, port: int) -> void:
	var cache := get_node_or_null("/root/NetCache")
	if cache != null:
		cache.remember(player_name,address,port)

func _local_loadout() -> Dictionary:
	var node: Variant = get_node_or_null("/root/PlayerState")
	if node == null:
		return {}
	return {
		"main":str(node.main_item()),
		"off":str(node.off_item()),
		"bow":int(node.equipped_index("bow")),
		"sword":int(node.equipped_index("sword")),
		"armor":ArmorData.pack(node.equipped_pieces()),
	}

func _catalog_hand(value: Variant, slot: String) -> String:
	# Seat loadouts come off the wire: only real gear legal for that hand.
	if typeof(value) != TYPE_STRING:
		return ""
	var id := str(value)
	var item: Dictionary = State.ITEMS.get(id,{})
	if item.is_empty() or not Rules.allowed(item,slot):
		return ""
	return id

func _apply_loadout(slot: int, loadout: Dictionary) -> void:
	if slot < 0 or slot >= actors.size() or loadout.is_empty():
		return
	var actor = actors[slot]
	var bow: Variant = loadout.get("bow")
	var sword: Variant = loadout.get("sword")
	var armor: Variant = loadout.get("armor")
	var bow_ok := typeof(bow) == TYPE_INT and int(bow) >= 0 and int(bow) <= 2
	var sword_ok := typeof(sword) == TYPE_INT and int(sword) >= 0 and int(sword) <= 2
	var armor_ok := typeof(armor) == TYPE_INT and int(armor) >= 0 and int(armor) <= 1023
	var main_raw: Variant = loadout.get("main")
	var off_raw: Variant = loadout.get("off")
	var main := _catalog_hand(main_raw,"main")
	var off := _catalog_hand(off_raw,"off")
	var hands_present := loadout.has("main") or loadout.has("off")
	var main_ok := not loadout.has("main") or (typeof(main_raw) == TYPE_STRING and (str(main_raw).is_empty() or not main.is_empty()))
	var off_ok := not loadout.has("off") or (typeof(off_raw) == TYPE_STRING and (str(off_raw).is_empty() or not off.is_empty()))
	if hands_present and main_ok and off_ok:
		# Hub kits carry the whole paperdoll; the state script derives the
		# weapon mode, staff, focus, shield and off-hand from the validated ids.
		# Explicitly empty hands are deliberate (unarmed); a malformed non-empty
		# hand falls through instead of wiping a valid seat.
		var pieces: Dictionary = ArmorData.unpack(int(armor) & 1023) if armor_ok else actor.rig.armor_pieces.duplicate()
		actor.rig.apply_loadout(State.build_loadout(main,off,pieces))
		return
	if bow_ok:
		actor.rig.set_bow(int(bow))
	if sword_ok:
		actor.rig.set_sword(int(sword))
	if armor_ok:
		actor.rig.set_armor_bits(int(armor))

func get_human_count() -> int:
	if network_role == "offline":
		return 0
	var count := 0
	for actor in actors:
		if actor.peer_id > 0:
			count += 1
	return count

func _peer_connected(peer_id: int) -> void:
	if network_role != "host":
		return
	multiplayer.multiplayer_peer.get_peer(peer_id).set_timeout(32,2000,5000)
	var slot := _lowest_free_slot()
	if slot < 0:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_peer_slots[peer_id] = slot
	var actor = actors[slot]
	actor.authoritative = true
	actor.configure(peer_id,false,"Ranger",_join_spawn(slot))
	actor.visible = true
	actor.is_local = false
	actor.collision_layer = 4
	actor.collision_mask = 1
	actor.combat.target_mask = 2
	actor.combat.damage_enabled = true
	_accept.rpc_id(peer_id,slot)
	_run_state.rpc_id(peer_id,_run_state_dict())
	print("DELVE_PEER_JOINED slot=%d humans=%d" % [slot,get_human_count()])

func _peer_disconnected(peer_id: int) -> void:
	if network_role != "host" or not _peer_slots.has(peer_id):
		return
	var slot: int = _peer_slots[peer_id]
	_peer_slots.erase(peer_id)
	_deactivate_slot(slot)
	_slot_cleared.rpc(slot)
	print("DELVE_PEER_LEFT slot=%d humans=%d" % [slot,get_human_count()])
	_check_party_wipe()

func _lowest_free_slot() -> int:
	for slot in range(1,actors.size()):
		if not _peer_slots.values().has(slot):
			return slot
	return -1

func _assembly_spawn(slot: int) -> Vector3:
	var spawns: Array = world.player_spawns
	if spawns.is_empty():
		return Vector3(0,3.3,15.2)
	return spawns[clampi(slot,0,spawns.size()-1)]

func _join_spawn(slot: int) -> Vector3:
	match phase:
		"WAVE":
			var angle := TAU * float(slot) / 4.0
			return world.drop_center + Vector3(cos(angle)*1.8,0.0,sin(angle)*1.8)
		"CLEARED", "COMPLETE":
			return world.chest_position + Vector3(2.0 + float(slot)*0.6,0.0,2.0)
		_:
			return _assembly_spawn(slot)

func _deactivate_slot(slot: int) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var actor = actors[slot]
	_clear_slot_arrows(slot)
	actor.combat.stop()
	actor.authoritative = false
	actor.is_local = false
	actor.visible = false
	actor.alive = false
	actor.peer_id = 0
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.combat.damage_enabled = false

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

@rpc("authority","call_remote","reliable")
func _slot_cleared(slot: int) -> void:
	if network_role != "client" or slot < 0 or slot >= actors.size():
		return
	actors[slot].visible = false
	actors[slot].alive = false
	actors[slot].collision_layer = 0
	actors[slot].collision_mask = 0

func _connected() -> void:
	if network_role != "client":
		return
	multiplayer.multiplayer_peer.get_peer(1).set_timeout(32,2000,5000)
	_register.rpc_id(1,_player_name,_local_loadout())

@rpc("any_peer","call_remote","reliable")
func _register(player_name: String, loadout: Dictionary) -> void:
	if network_role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if _peer_slots.has(sender):
		var slot := int(_peer_slots[sender])
		actors[slot].display_name = _safe_name(player_name)
		_apply_loadout(slot,loadout)

@rpc("authority","call_remote","reliable")
func _accept(slot: int) -> void:
	if network_role != "client" or slot < 1 or slot > 3:
		return
	local_slot = slot
	_next_swing_side = 0
	_camera_yaw = atan2(_assembly_spawn(slot).x,_assembly_spawn(slot).z)
	for actor in actors:
		actor.authoritative = false
		actor.is_local = actor.slot == slot
		actor.combat.damage_enabled = false
		actor.combat.target_mask = 2
		if actor.slot != slot:
			actor.visible = false
	actors[slot].visible = true
	actors[slot].interp_delay = 0.05
	hud.configure(_endpoint)
	_bind_field_rig()
	_set_cursor_free(false)
	print("DELVE_CLIENT_READY slot=%d" % slot)

func _physics_process(delta: float) -> void:
	if network_role == "offline":
		return
	if network_role == "client" and local_slot < 0:
		_join_elapsed += delta
		if _join_elapsed > 6.0:
			_connection_ended("Connection timed out. The host may be offline, full, or blocked by a firewall.")
		return
	_collect_loot(delta)
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
		var aim := _crosshair_aim()
		var aim_origin: Variant = _aim_origin if _aim_origin_valid else null
		if network_role == "host":
			_set_movement(local_slot,direction,running,aim,-1,aim_origin)
		elif _send_elapsed >= SNAPSHOT_INTERVAL:
			_move_input.rpc_id(1,direction,running,aim,_snapshot_ticks[local_slot],aim_origin)
	if network_role == "host":
		server_tick += 1
		for actor in actors:
			if actor.peer_id > 0:
				actor.step(delta,actors,server_tick)
		if phase == "WAVE":
			var live := _live_devils()
			for devil in devils.duplicate():
				if is_instance_valid(devil) and devil.alive:
					devil.step(delta,actors,live)
		_advance_host_state(delta)
		_check_party_wipe()
		if _send_elapsed >= SNAPSHOT_INTERVAL:
			for actor in actors:
				if actor.peer_id > 0:
					_receive_snapshot.rpc(server_tick,actor.slot,actor.snapshot())
					_snapshot_ticks[actor.slot] = server_tick
			var states: Array = []
			for devil in devils:
				if is_instance_valid(devil):
					states.append(devil.snapshot())
			if not states.is_empty():
				_devil_snapshots.rpc(server_tick,states)
		_run_send_elapsed += delta
		if _run_send_elapsed >= RUN_STATE_INTERVAL:
			_run_send_elapsed = fmod(_run_send_elapsed,RUN_STATE_INTERVAL)
			_sync_run_state()
	if _send_elapsed >= SNAPSHOT_INTERVAL:
		_send_elapsed = fmod(_send_elapsed,SNAPSHOT_INTERVAL)

func _set_movement(slot: int, direction: Vector2, running: bool, aim: Vector3, aim_tick: int = -1, aim_origin: Variant = null) -> void:
	if slot < 0 or slot >= actors.size():
		return
	if not direction.is_finite() or not _set_aim(slot,aim,aim_tick,aim_origin):
		return
	actors[slot].move_direction = direction.limit_length()
	actors[slot].run_requested = running
	actors[slot].input_age = 0

func _set_aim(slot: int, point: Vector3, aim_tick: int = -1, aim_origin: Variant = null) -> bool:
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
	actor.combat.set_aim(point)
	if typeof(aim_origin) == TYPE_VECTOR3:
		var origin: Vector3 = aim_origin
		var ray: Vector3 = point-origin
		if origin.is_finite() and origin.distance_squared_to(actor.global_position) <= 144.0 \
				and ray.is_finite() and ray.length_squared() > 0.01:
			actor.combat.set_camera_ray(origin,ray)
		else:
			actor.combat.clear_camera_ray()
	else:
		actor.combat.clear_camera_ray()
	if actor.combat.blocking:
		var facing: Vector3 = point - actor.global_position
		facing.y = 0.0
		if facing.length_squared() > 0.000001:
			actor.combat.face_block(facing)
	return true

@rpc("any_peer","call_remote","unreliable_ordered")
func _move_input(direction: Vector2, running: bool, aim: Vector3, aim_tick: Variant, aim_origin: Variant = null) -> void:
	if network_role != "host" or typeof(aim_tick) != TYPE_INT:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _peer_slots.has(sender):
		_set_movement(int(_peer_slots[sender]),direction,running,aim,aim_tick,aim_origin)

@rpc("authority","call_remote","unreliable")
func _receive_snapshot(tick: int, slot: int, state: Dictionary) -> void:
	if network_role != "client" or slot < 0 or slot >= actors.size() or tick <= _snapshot_ticks[slot]:
		return
	_snapshot_ticks[slot] = tick
	last_snapshot_tick = maxi(last_snapshot_tick,tick)
	actors[slot].apply_snapshot(state)

func send_action(action: String, value: Variant = null) -> void:
	if local_slot < 0:
		return
	if action == "interact":
		if network_role == "host":
			_host_interact(local_slot)
		elif network_role == "client":
			_action_input.rpc_id(1,action,null,_snapshot_ticks[local_slot],null)
		return
	if action in ["bow","sword","weapon","armor","shield","loadout"]:
		_cancel_draw_input()
	if action in ["draw","throw"] and not _peek_held and actors[local_slot].rig.phase == "READY":
		_capture_peek_context()
	if action in ["draw","release","throw","throw_release"]:
		_send_peek_input()
	var aim_origin: Variant = _aim_origin if _aim_origin_valid and action in ["draw","release","throw","throw_release","attack_right","melee"] else null
	if network_role == "host":
		_apply_action(local_slot,action,value,-1,aim_origin)
	elif network_role == "client":
		_action_input.rpc_id(1,action,value,_snapshot_ticks[local_slot],aim_origin)

@rpc("any_peer","call_remote","reliable")
func _action_input(action: String, value: Variant, aim_tick: Variant, aim_origin: Variant = null) -> void:
	if network_role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_slots.has(sender):
		return
	var slot := int(_peer_slots[sender])
	if action == "interact":
		# Interaction is a world-position check; it needs no aim rewind.
		_apply_action(slot,action,null)
		return
	if action == "loadout":
		# Kit changes are seat state, not aim; no snapshot rewind needed.
		if typeof(value) == TYPE_DICTIONARY:
			_apply_loadout(slot,value)
		return
	if typeof(aim_tick) != TYPE_INT:
		return
	if aim_tick < 0 or aim_tick > _snapshot_ticks[slot]:
		return
	_apply_action(slot,action,value,aim_tick,aim_origin)

func _apply_action(slot: int, action: String, value: Variant, aim_tick: int = -1, aim_origin: Variant = null) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var actor = actors[slot]
	if action == "loadout":
		# Same validated seat loader as the join handshake; unknown fields die here.
		if typeof(value) == TYPE_DICTIONARY:
			_apply_loadout(slot,value)
		return
	if not actor.alive:
		return
	match action:
		"draw":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				if actor.rig.weapon == "dual":
					actor.combat.begin_melee("left")
				elif actor.rig.weapon in ["sword","dagger"]:
					actor.combat.begin_melee()
				else:
					actor.combat.begin_draw()
		"attack_right":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.begin_melee("right","overhead")
		"melee":
			if typeof(value) != TYPE_DICTIONARY:
				return
			var aim = value.get("aim")
			var hand := str(value.get("hand","right"))
			var variant := str(value.get("variant","overhead"))
			if typeof(aim) != TYPE_VECTOR3 or hand not in ["left","right"] \
					or variant not in ["overhead","horizontal_left","horizontal_right","stab"]:
				return
			if _set_aim(slot,aim,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.begin_melee(hand,variant)
		"step":
			if typeof(value) != TYPE_VECTOR3:
				return
			var direction: Vector3 = value
			if not direction.is_finite() or absf(direction.y) > 0.01:
				return
			var flat := Vector3(direction.x,0,direction.z)
			if absf(flat.length()-1.0) > 0.1:
				return
			actor.try_step(flat)
		"release":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.release_draw()
		"throw":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.begin_throw()
		"throw_release":
			if typeof(value) == TYPE_VECTOR3 and _set_aim(slot,value,aim_tick,aim_origin):
				actor.update_combat_cover_side()
				actor.combat.release_throw()
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
		"block":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("pressed")) != TYPE_BOOL or typeof(value.get("forward")) != TYPE_VECTOR3:
				return
			var forward: Vector3 = value.forward
			if not forward.is_finite() or (value.pressed and forward.length_squared() < 0.25):
				return
			actor.set_block(value.pressed,Vector3(forward.x,0,forward.z))
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
			if typeof(value) == TYPE_STRING and value in ["bow","sword","dagger","dual"]:
				var requested := str(value)
				if requested == "dual":
					if actor.rig.weapon == "dual":
						requested = "sword"
					elif actor.rig.sword_index == 2:
						return
				actor.combat.stop()
				actor.rig.set_weapon(requested)
		"shield":
			if typeof(value) == TYPE_BOOL:
				actor.combat.stop()
				actor.rig.set_shield(value)
		"armor":
			if typeof(value) != TYPE_DICTIONARY:
				return
			if typeof(value.get("slot")) != TYPE_STRING or typeof(value.get("set")) != TYPE_INT:
				return
			var armor_slot := str(value.slot)
			var armor_set := int(value.set)
			if armor_slot in ArmorData.SLOTS and armor_set >= 0 and armor_set < ArmorData.SET_IDS.size():
				actor.rig.set_armor_piece(armor_slot,armor_set)
		"interact":
			_host_interact(slot)

func _on_fired(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	if network_role != "host":
		return
	var damage := Combat.damage_for(actors[slot].rig.bow_index,charge)
	var visual_origin: Vector3 = actors[slot].rig.last_arrow_visual_origin
	_spawn_arrow(slot,origin,direction,speed,damage,true,visual_origin)
	_arrow_event.rpc(slot,origin,direction,speed,visual_origin)
	shots_fired += 1

func _spawn_arrow(slot: int, origin: Vector3, direction: Vector3, speed: float, damage: float, authoritative: bool, visual_origin: Vector3 = Vector3.INF) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var arrow := Arrow.new()
	arrow.source_id = slot
	arrow.hit_mask = 1 | 2
	arrow.authoritative_damage = authoritative
	add_child(arrow)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	if is_instance_valid(actors[slot].rig.active_shield):
		excluded.append(actors[slot].rig.active_shield.get_rid())
	arrow.launch(origin,direction,speed,damage,excluded,visual_origin)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(arrow)
	if projectiles.size() > MAX_SHOTS:
		var oldest = projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	if slot == local_slot:
		audio.play_sound("release")

@rpc("authority","call_remote","reliable")
func _arrow_event(slot: int, origin: Vector3, direction: Vector3, speed: float, visual_origin: Variant = null) -> void:
	if network_role == "client" and slot >= 0 and slot < actors.size():
		var start: Vector3 = visual_origin if typeof(visual_origin) == TYPE_VECTOR3 else Vector3.INF
		_spawn_arrow(slot,origin,direction,speed,0.0,false,start)
		shots_fired += 1

func _on_thrown_weapon(slot: int, origin: Vector3, direction: Vector3, speed: float, charge: float, weapon_name: String, weapon_index: int) -> void:
	if network_role != "host":
		return
	var damage := Combat.throw_damage(weapon_name,weapon_index,charge)
	_spawn_thrown(slot,origin,direction,speed,weapon_name,weapon_index,damage,true)
	_throw_event.rpc(slot,origin,direction,speed,weapon_name,weapon_index)
	throws_fired += 1

func _spawn_thrown(slot: int, origin: Vector3, direction: Vector3, speed: float, weapon_name: String, weapon_index: int, damage: float, authoritative: bool) -> void:
	if slot < 0 or slot >= actors.size():
		return
	var thrown := Thrown.new()
	thrown.source_id = slot
	thrown.weapon = weapon_name
	thrown.weapon_index = weapon_index
	thrown.blade_length = float(Archer.DAGGER_DATA.length) if weapon_name == "dagger" else float(Archer.SWORD_DATA[clampi(weapon_index,0,2)].length)
	thrown.hit_mask = 1 | 2
	thrown.authoritative_damage = authoritative
	add_child(thrown)
	var excluded: Array[RID] = [actors[slot].get_rid()]
	thrown.launch(origin,direction,speed,damage,excluded)
	for index in range(projectiles.size()-1,-1,-1):
		if not is_instance_valid(projectiles[index]):
			projectiles.remove_at(index)
	projectiles.append(thrown)
	if projectiles.size() > MAX_SHOTS:
		var oldest = projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	if slot == local_slot:
		audio.play_sound("release")

@rpc("authority","call_remote","reliable")
func _throw_event(slot: int, origin: Vector3, direction: Vector3, speed: float, weapon_name: String, weapon_index: int) -> void:
	if network_role == "client" and slot >= 0 and slot < actors.size():
		_spawn_thrown(slot,origin,direction,speed,weapon_name,weapon_index,0.0,false)

func _on_actor_fell(_slot: int, _source_id: int) -> void:
	if network_role != "host":
		return
	_check_party_wipe()

func _on_devil_died(_devil) -> void:
	if network_role != "host":
		return
	_check_wave_cleared()

func _on_devil_struck(_target, _amount, position: Vector3, outcome) -> void:
	if network_role != "host":
		return
	var kind := "hit"
	if typeof(outcome) == TYPE_INT:
		var code := int(outcome)
		if code == Combat.DEFENSE_PARRY:
			kind = "parry"
		elif code == Combat.DEFENSE_BLOCK or code == Combat.DEFENSE_WEAK_BLOCK:
			kind = "block"
	elif typeof(outcome) == TYPE_STRING:
		var text := str(outcome)
		if text in ["parry","block","hit"]:
			kind = text
	elif typeof(outcome) == TYPE_BOOL and bool(outcome):
		kind = "parry"
	Combat.spawn_impact(self,position,kind)
	audio.play_sound("clang" if kind == "parry" else "block" if kind == "block" else "hit")
	_impact_event.rpc(position,kind)

@rpc("authority","call_remote","unreliable")
func _impact_event(position: Vector3, kind: String) -> void:
	if network_role != "client":
		return
	Combat.spawn_impact(self,position,kind)
	audio.play_sound("clang" if kind == "parry" else "block" if kind == "block" else "hit")

func _process(delta: float) -> void:
	_elapsed += delta
	if network_role == "host":
		_process_hooks(delta)
	if local_slot < 0:
		hud.reticle_visible = false
		return
	var actor = actors[local_slot]
	if not actor.alive and (_peek_held or _mouse_drawing or _throw_held):
		_peek_held = false
		_cancel_draw_input()
	_shoulder_camera.update(delta)
	_update_game_camera()
	var state: Dictionary = _run_state_dict() if network_role == "host" else _remote_state
	if state.is_empty():
		state = _run_state_dict()
	hud.update_run(state)
	hud.update_local(_local_state(actor))
	hud.set_prompt(_prompt_text())
	hud.reticle_visible = actor.alive and not _cursor_free
	hud.reticle = get_viewport().get_visible_rect().size * 0.5

func _process_hooks(delta: float) -> void:
	_mode_elapsed += delta
	if _auto_start and not _auto_fired and phase == "ASSEMBLY" and _mode_elapsed >= AUTO_BEGIN_DELAY:
		_auto_fired = true
		begin_descent()
	if _kill_wave_hook and not _kill_fired and phase == "WAVE" and _wave_elapsed >= HOOK_KILL_DELAY:
		_kill_fired = true
		for devil in devils.duplicate():
			if is_instance_valid(devil) and devil.alive:
				devil.take_damage(99999.0,-1)
	if _exit_after > 0.0 and _elapsed >= _exit_after:
		_exit_after = 0.0
		get_tree().quit(0)

func _local_state(actor) -> Dictionary:
	return {
		"slot":actor.slot, "health":actor.health, "stamina":actor.stamina, "alive":actor.alive,
		"weapon":actor.rig.weapon, "bow":actor.rig.bow_index, "sword":actor.rig.sword_index,
		"armor":actor.rig.armor_bits(), "phase":actor.rig.phase, "draw":actor.rig.draw_amount,
		"shield":actor.rig.shield_equipped, "blocking":actor.combat.blocking,
		"movement":actor.combat.movement_mode, "attack_progress":actor.combat.attack_progress,
		"attack_interval":actor.combat.get_attack_interval(),
		"parry":actor.authoritative and actor.combat.blocking and not actor.rig.shield_equipped and actor.combat.block_time <= Combat.PARRY_WINDOW,
		"left":actor.rig.melee_progress_for("left"), "right":actor.rig.melee_progress_for("right"),
		"downed":not actor.alive, "sealed":bool(world.sealed), "run_phase":phase,
	}

func _prompt_text() -> String:
	if local_slot < 0 or local_slot >= actors.size():
		return ""
	var actor = actors[local_slot]
	var pos: Vector3 = actor.global_position
	match phase:
		"ASSEMBLY":
			if network_role == "host":
				var shaft: Vector3 = world.player_spawns[1] if world.player_spawns.size() > 1 else world.player_spawns[0]
				if pos.distance_to(shaft) <= INTERACT_RANGE:
					return "G  BEGIN THE DESCENT"
				return "Walk to the shaft to begin"
			return "Waiting for the host to begin the descent"
		"WAVE":
			var remaining := _remaining_enemies()
			if network_role == "client":
				remaining = int(_remote_state.get("remaining",remaining))
			return "Sealed in - %d cinder devils remain" % remaining
		"CLEARED":
			if chest_ready and not chest_open and is_instance_valid(chest) and pos.distance_to(world.chest_position) <= CHEST_RANGE:
				return "G  OPEN THE CACHE"
			if wave < Progress.WAVE_COUNT and pos.distance_to(world.descent_position) <= INTERACT_RANGE:
				return "G  DESCEND TO WAVE %d" % (wave + 1)
			if pos.distance_to(world.ascent_position) <= INTERACT_RANGE:
				return "G  ASCEND TO THE SURFACE"
			return "The wave is broken; descend or ascend."
		"COMPLETE":
			if pos.distance_to(world.ascent_position) <= INTERACT_RANGE:
				return "G  ASCEND TO THE SURFACE"
			return "The cache is yours"
		_:
			return ""

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

func _field_inventory_open() -> bool:
	return _field_inventory != null and _field_inventory.is_open()

func _on_field_opened() -> void:
	# A menu opens with the pointer free and any held draw or throw cancelled.
	_set_cursor_free(true)

func _on_field_closed() -> void:
	# Closing must not recapture the pointer in the lobby, a dead run or after
	# the connection dropped; the scene owns that decision.
	if network_role == "offline" or local_slot < 0 or phase == "GAME_OVER":
		return
	_set_cursor_free(false)

func _bind_field_rig() -> void:
	if _field_inventory == null:
		return
	var rig: Variant = null
	if local_slot >= 0 and local_slot < actors.size():
		rig = actors[local_slot].rig
	_field_inventory.rebind(rig)

func _on_field_loadout_changed() -> void:
	if local_slot < 0 or local_slot >= actors.size():
		return
	_bind_field_rig()
	_apply_loadout(local_slot,_local_loadout())
	hud.update_local(_local_state(actors[local_slot]))
	if network_role == "client":
		# The host rebuilds the seat from the same validated catalog ids and
		# its snapshots stay the presentation authority for everyone else.
		send_action("loadout",_local_loadout())

func _drop_field_item(item_id: String) -> void:
	if _player_state == null or local_slot < 0 or local_slot >= actors.size():
		return
	var id := str(item_id)
	if id.is_empty() or not State.ITEMS.has(id):
		return
	var facing := Vector3(-sin(_camera_yaw),0.0,-cos(_camera_yaw))
	var pickup := LootPickup.new()
	pickup.name = "FieldDrop_" + id
	pickup.setup(id,_field_display_name(id))
	pickup.position = _drop_floor(actors[local_slot].global_position + facing*0.8)
	add_child(pickup)
	# A dropped piece arms only after the dropper steps clear, so it cannot be
	# swallowed again from the same spot.
	loot_pickups.append({"node":pickup, "item_id":id, "armed":false})

func _collect_loot(delta: float) -> void:
	_loot_message_cooldown = maxf(0.0,_loot_message_cooldown - delta)
	if _player_state == null or local_slot < 0 or local_slot >= actors.size():
		return
	var actor = actors[local_slot]
	if not actor.alive:
		return
	for index in range(loot_pickups.size()-1,-1,-1):
		var entry: Dictionary = loot_pickups[index]
		var pickup = entry.get("node")
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			loot_pickups.remove_at(index)
			continue
		var offset: Vector3 = pickup.global_position - actor.global_position
		var in_reach: bool = Vector2(offset.x,offset.z).length() <= PICKUP_RADIUS and absf(offset.y) <= 2.4
		if not in_reach:
			if not bool(entry.get("armed",true)):
				entry["armed"] = true
			continue
		if not bool(entry.get("armed",true)):
			continue
		var result: Dictionary = _player_state.try_pickup(str(entry.get("item_id","")))
		if bool(result.get("ok",false)):
			var picked := str(pickup.get("display_name"))
			loot_pickups.remove_at(index)
			pickup.queue_free()
			hud.set_status(str(result.get("message","Picked up %s." % picked)),2.5)
			_refresh_field_hud()
		elif _loot_message_cooldown <= 0.0:
			_loot_message_cooldown = DROP_FULL_INTERVAL
			hud.set_status(str(result.get("message","Backpack full.")),2.5)

func _field_display_name(item_id: String) -> String:
	if _player_state != null and _player_state.has_method("item_name"):
		var named := str(_player_state.item_name(item_id))
		if not named.is_empty() and named != item_id:
			return named
	return item_id.capitalize()

func _drop_floor(at: Vector3) -> Vector3:
	_drop_query.from = at + Vector3(0,2.0,0)
	_drop_query.to = at - Vector3(0,3.0,0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_drop_query)
	return (hit.position + Vector3(0,0.05,0)) if not hit.is_empty() else at

func _refresh_field_hud() -> void:
	if _field_inventory != null and _field_inventory.hud != null:
		_field_inventory.hud.refresh()

func _crosshair_aim() -> Vector3:
	_update_game_camera()
	var center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	_aim_origin = ray_origin
	_aim_origin_valid = true
	# Match the frontier: shoulder and bow poses must not move the start past a target.
	var actor = actors[local_slot]
	var aim_anchor: Vector3 = actor.global_position + Vector3.UP*actor.cover.camera_height()
	var actor_depth := maxf(0.0,(aim_anchor-ray_origin).dot(ray_direction))
	_query.from = ray_origin + ray_direction*actor_depth
	_query.to = ray_origin + ray_direction*120.0
	# Skip only the cover this delver is posted against, on host and replica.
	var excluded: Array[RID] = [actor.get_rid()]
	var cover_rid: RID = actor.cover.attached_surface()
	if cover_rid.is_valid():
		excluded.append(cover_rid)
	_query.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	return hit.position if not hit.is_empty() else _query.to

func _input(event: InputEvent) -> void:
	if local_slot < 0:
		return
	if _field_inventory_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_peek_held = false
		if actors[local_slot].rig.weapon != "dual":
			send_action("block",{"pressed":false,"forward":Vector3.ZERO})
		_send_peek_input()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _mouse_drawing:
			_mouse_drawing = false
			send_action("release",_crosshair_aim())
	if event is InputEventKey and event.keycode == KEY_T and not event.pressed:
		if _throw_held:
			_throw_held = false
			send_action("throw_release",_crosshair_aim())

func _cancel_draw_input() -> void:
	_mouse_drawing = false
	_throw_held = false
	send_action("stop")

func _capture_peek_context() -> void:
	_peek_right = Vector3(cos(_camera_yaw),0,-sin(_camera_yaw))

func _send_peek_input() -> void:
	send_action("peek",{"pressed":_peek_held,"right":_peek_right,"side":_shoulder_camera.side})

func _horizontal_variant() -> String:
	var side := _next_swing_side
	if side == 0:
		side = 1 if _shoulder_camera.side > 0 else -1
	_next_swing_side = -side
	return "horizontal_right" if side > 0 else "horizontal_left"

func _send_melee(hand: String, variant: String) -> void:
	var aim := _crosshair_aim()
	send_action("melee",{"aim":aim,"hand":hand,"variant":variant})

func _send_step(side: int) -> void:
	if local_slot < 0 or _cursor_free or side == 0:
		return
	var right := Vector3(cos(_camera_yaw),0,-sin(_camera_yaw))
	send_action("step",right*signf(float(side)))

func _unhandled_input(event: InputEvent) -> void:
	if local_slot < 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _field_inventory_open():
			# The paperdoll/backpack owns the keyboard while it is up.
			match event.keycode:
				KEY_ESCAPE, KEY_I:
					_field_inventory.close()
			return
		match event.keycode:
			KEY_1: send_action("weapon","bow")
			KEY_2: send_action("weapon","sword")
			KEY_3: send_action("weapon","dagger")
			KEY_4: send_action("shield",not actors[local_slot].rig.shield_equipped)
			KEY_5: send_action("weapon","dual")
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
				_next_swing_side = _shoulder_camera.side
				_capture_peek_context()
				_send_peek_input()
			KEY_Q: _send_step(-1)
			KEY_E: _send_step(1)
			KEY_G:
				if not _cursor_free:
					send_action("interact")
			KEY_R:
				if network_role == "host" and phase == "ASSEMBLY":
					Progress.clear_run(save_path)
					resume_data.clear()
					run_seed = randi()
					begin_descent()
			KEY_ESCAPE:
				if _field_inventory_open():
					_field_inventory.close()
				else:
					_set_cursor_free(not _cursor_free)
			KEY_I:
				if _field_inventory != null:
					_field_inventory.toggle()
				else:
					_set_cursor_free(not _cursor_free)
			KEY_T:
				_set_cursor_free(false)
				_throw_held = true
				send_action("throw",_crosshair_aim())
	if _field_inventory_open():
		return
	if event is InputEventMouseButton and event.pressed:
		var weapon: String = actors[local_slot].rig.weapon
		if event.button_index == MOUSE_BUTTON_LEFT:
			_set_cursor_free(false)
			if weapon == "bow":
				_mouse_drawing = true
				send_action("draw",_crosshair_aim())
			elif weapon == "dual":
				_send_melee("left","stab")
			elif weapon == "dagger":
				_send_melee("right","stab")
			else:
				_send_melee("right",_horizontal_variant())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_cursor_free(false)
			if weapon == "dual":
				send_action("attack_right",_crosshair_aim())
			else:
				_peek_held = true
				_capture_peek_context()
				_send_peek_input()
				send_action("block",{"pressed":true,"forward":Vector3(-sin(_camera_yaw),0,-cos(_camera_yaw))})
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _cursor_free:
				return
			if event.ctrl_pressed:
				_camera_distance = maxf(3,_camera_distance-0.5)
			elif weapon in ["sword","dagger","dual"]:
				_send_melee("right","stab")
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _cursor_free:
				return
			if event.ctrl_pressed:
				_camera_distance = minf(17,_camera_distance+0.5)
			elif weapon in ["sword","dagger","dual"]:
				_send_melee("right","overhead")
	if event is InputEventMouseMotion and not _cursor_free:
		_camera_yaw -= event.relative.x*0.004
		_camera_pitch = clampf(_camera_pitch+event.relative.y*0.004,-0.7,0.7)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and local_slot >= 0:
		_set_cursor_free(true)

func _exit_tree() -> void:
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# --------------------------------------------------------------------------
# Run flow
# --------------------------------------------------------------------------

func begin_descent() -> void:
	if network_role != "host" or phase != "ASSEMBLY":
		return
	var start_wave := 1
	var start_cleared := false
	if not resume_data.is_empty():
		start_wave = clampi(int(resume_data.get("wave",1)),1,Progress.WAVE_COUNT)
		start_cleared = bool(resume_data.get("chest_ready",false))
		var saved_seed := int(resume_data.get("seed",run_seed))
		if saved_seed != 0:
			run_seed = saved_seed
	resume_data.clear()
	wave = start_wave
	_drop_party()
	if start_cleared:
		_clear_devils()
		world.set_sealed(false)
		chest_ready = true
		chest_open = false
		_clear_timer = 0.0
		_spawn_chest()
		_set_phase("CLEARED")
		hud.show_wave_banner("WAVE %d CLEARED" % wave,2.0)
		_sync_run_state()
	else:
		_start_wave()

func descend_next_wave() -> void:
	if network_role != "host" or phase != "CLEARED":
		return
	if wave >= Progress.WAVE_COUNT:
		return
	wave += 1
	_start_wave()

func ascend_to_surface() -> void:
	if network_role != "host":
		return
	if phase != "CLEARED" and phase != "COMPLETE":
		return
	_ascend_event.rpc()
	print("DELVE_RETURN_SURFACE")
	# Give ENet a couple of polls to flush the reliable departure before this
	# controller closes its peer on the way out.
	get_tree().create_timer(0.25).timeout.connect(_change_scene_to_surface,CONNECT_ONE_SHOT)

@rpc("authority","call_remote","reliable")
func _ascend_event() -> void:
	print("DELVE_RETURN_SURFACE")
	_change_scene_to_surface()

func _change_scene_to_surface() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func open_chest() -> void:
	if network_role != "host" or phase != "CLEARED":
		return
	if not chest_ready or chest_open:
		return
	if not is_instance_valid(chest):
		_spawn_chest()
	if not is_instance_valid(chest):
		return
	chest.open(false)
	_on_chest_opened()

func reach_phase() -> Dictionary:
	var state := _run_state_dict()
	state["local_slot"] = local_slot
	state["humans"] = get_human_count()
	state["devils_alive"] = _live_devil_count()
	return state

func _start_wave() -> void:
	_clear_devils()
	_remove_chest()
	chest_ready = false
	chest_open = false
	world.set_sealed(true)
	_clear_timer = 0.0
	_wave_elapsed = 0.0
	_kill_fired = false
	_spawn_timer = 0.0
	_spawn_queue.clear()
	var count: int = maxi(1,Progress.wave_size(wave))
	var weapons: Array = Progress.wave_weapons(wave)
	var spawn_count: int = maxi(1,world.enemy_spawns.size())
	var arch_offset: int = (absi(run_seed) + wave) % spawn_count
	var arch_stride: int = maxi(1, spawn_count / count)
	for index in count:
		var weapon := "claw"
		if not weapons.is_empty():
			weapon = str(weapons[index % weapons.size()])
		_spawn_queue.append({"weapon":weapon, "spawn":(arch_offset + index * arch_stride) % spawn_count})
	_set_phase("WAVE")
	hud.show_wave_banner("WAVE %d" % wave,2.0)
	print("DELVE_WAVE_START wave=%d mobs=%d" % [wave,count])
	if wave > 1:
		_save_checkpoint(false)
	_sync_run_state()

func _advance_host_state(delta: float) -> void:
	match phase:
		"WAVE":
			_wave_elapsed += delta
			_spawn_timer -= delta
			while not _spawn_queue.is_empty() and _spawn_timer <= 0.0:
				var entry: Dictionary = _spawn_queue.pop_front()
				_spawn_devil(str(entry.get("weapon","claw")),int(entry.get("spawn",0)))
				_spawn_timer += DEVIL_TRICKLE
		"CLEARED":
			if chest_ready:
				return
			_clear_timer = maxf(0.0,_clear_timer-delta)
			if _clear_timer <= 0.0:
				_clear_timer = 0.0
				chest_ready = true
				_spawn_chest()
				_save_checkpoint(true)
				_sync_run_state()
		_:
			pass

func _spawn_devil(weapon: String, spawn_index: int) -> void:
	if world.enemy_spawns.is_empty():
		return
	var entry: Dictionary = world.enemy_spawns[clampi(spawn_index,0,world.enemy_spawns.size()-1)]
	var spawn_point: Vector3 = entry.get("position",Vector3.ZERO)
	var facing: Vector3 = entry.get("facing",Vector3.FORWARD)
	var devil = Devil.new()
	devil.name = "Devil%d" % _next_devil_id
	add_child(devil)
	devil.configure(_next_devil_id,weapon,wave)
	devil.authoritative = true
	devil.global_position = spawn_point
	var flat := Vector3(facing.x,0.0,facing.z)
	if flat.length_squared() > 0.0001:
		devil.look_at(devil.global_position + flat.normalized(),Vector3.UP)
	devil.died.connect(_on_devil_died)
	devil.struck.connect(_on_devil_struck)
	devils.append(devil)
	_next_devil_id += 1

func _wave_cleared() -> void:
	if phase != "WAVE":
		return
	_set_phase("CLEARED")
	world.set_sealed(false)
	_clear_timer = CLEAR_DELAY
	print("DELVE_WAVE_CLEAR wave=%d" % wave)
	hud.show_wave_banner("WAVE %d CLEARED" % wave,2.0)
	_sync_run_state()

func _check_wave_cleared() -> void:
	if phase != "WAVE":
		return
	if not _spawn_queue.is_empty():
		return
	for devil in devils:
		if is_instance_valid(devil) and devil.alive:
			return
	_wave_cleared()

func _remaining_enemies() -> int:
	if phase != "WAVE":
		return 0
	return _spawn_queue.size() + _live_devil_count()

func _live_devil_count() -> int:
	var count := 0
	for devil in devils:
		if is_instance_valid(devil) and devil.alive:
			count += 1
	return count

func _live_devils() -> Array:
	var live: Array = []
	for devil in devils:
		if is_instance_valid(devil) and devil.alive:
			live.append(devil)
	return live

func _clear_devils() -> void:
	for devil in devils:
		if is_instance_valid(devil):
			devil.queue_free()
	devils.clear()
	if network_role == "host":
		_devils_reset.rpc()

@rpc("authority","call_remote","reliable")
func _devils_reset() -> void:
	if network_role != "client":
		return
	_on_devils_reset_local()

func _on_devils_reset_local() -> void:
	for key in _devil_nodes.keys():
		var node = _devil_nodes[key]
		if is_instance_valid(node):
			node.queue_free()
	_devil_nodes.clear()
	_devil_dead_ids.clear()
	_last_devil_tick = -1

@rpc("authority","call_remote","unreliable")
func _devil_snapshots(tick: int, states: Array) -> void:
	if network_role != "client" or tick <= _last_devil_tick:
		return
	_last_devil_tick = tick
	for state in states:
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var id := int(state.get("id",0))
		var state_alive := bool(state.get("alive",true))
		if not state_alive:
			_devil_dead_ids[id] = true
		var node = _devil_nodes.get(id)
		if node == null or not is_instance_valid(node):
			# The corpse already finished; never respawn a replica just to die.
			if not state_alive:
				continue
			var created = Devil.new()
			add_child(created)
			created.configure(id,str(state.get("weapon","claw")),int(state.get("wave",wave)))
			created.authoritative = false
			_devil_nodes[id] = created
			node = created
		node.apply_snapshot(state)

func _spawn_chest() -> void:
	if is_instance_valid(chest):
		return
	chest = Chest.new()
	add_child(chest)
	chest.position = world.chest_position
	if not chest.opened.is_connected(_on_chest_opened):
		chest.opened.connect(_on_chest_opened)
	chest.set_wave(wave)

func _remove_chest() -> void:
	if is_instance_valid(chest):
		chest.queue_free()
	chest = null

func _on_chest_opened() -> void:
	if network_role != "host" or chest_open:
		return
	chest_open = true
	_chest_event.rpc()
	print("DELVE_CHEST_OPEN")
	if wave >= Progress.WAVE_COUNT:
		Progress.clear_run(save_path)
		_set_phase("COMPLETE")
		hud.show_wave_banner("THE CACHE IS YOURS",3.0)
	else:
		hud.set_status("The cache is open. Descend when the party is ready.",2.5)
	_sync_run_state()

@rpc("authority","call_remote","reliable")
func _chest_event() -> void:
	if network_role != "client":
		return
	chest_open = true
	if not is_instance_valid(chest) and chest_ready:
		_spawn_chest()
	if is_instance_valid(chest) and not chest.is_opened():
		chest.open(false)

func _sync_client_chest() -> void:
	if network_role != "client":
		return
	if chest_ready:
		if not is_instance_valid(chest):
			_spawn_chest()
		if chest_open and is_instance_valid(chest) and not chest.is_opened():
			chest.open(false)
	elif is_instance_valid(chest):
		_remove_chest()

@rpc("authority","call_remote","reliable")
func _run_state(state: Dictionary) -> void:
	if network_role != "client":
		return
	_apply_run_state(state)

func _apply_run_state(state: Dictionary) -> void:
	var previous_phase := phase
	var previous_wave := wave
	phase = str(state.get("phase",phase))
	wave = int(state.get("wave",wave))
	chest_ready = bool(state.get("chest_ready",chest_ready))
	chest_open = bool(state.get("chest_open",chest_open))
	_clear_timer = float(state.get("timer",0.0))
	_remote_state = state.duplicate(true)
	# The host's slot index is not this client's; the party panel marks the
	# local row from this field, so keep it local.
	_remote_state["local_slot"] = local_slot
	if state.has("endpoint"):
		_endpoint = str(state.get("endpoint",_endpoint))
	world.set_sealed(bool(state.get("sealed",false)))
	var party: Variant = state.get("party",[])
	var active_slots: Dictionary = {}
	if party is Array:
		for row in party:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var slot := int(row.get("slot",-1))
			if slot < 0 or slot >= actors.size():
				continue
			active_slots[slot] = true
			var actor = actors[slot]
			actor.display_name = str(row.get("name",actor.display_name))
			if actor.slot != local_slot:
				actor.visible = true
	for actor in actors:
		if not active_slots.has(actor.slot) and actor.slot != local_slot:
			actor.visible = false
			actor.alive = false
			actor.collision_layer = 0
			actor.collision_mask = 0
	_sync_client_chest()
	if phase == "GAME_OVER":
		if _field_inventory_open():
			_field_inventory.close()
		_set_cursor_free(true)
	if phase != previous_phase:
		match phase:
			"WAVE":
				hud.show_wave_banner("WAVE %d" % wave,2.0)
			"CLEARED":
				hud.show_wave_banner("WAVE %d CLEARED" % wave,2.0)
			"GAME_OVER":
				hud.show_game_over("The delve has claimed the party.")
			"COMPLETE":
				hud.show_wave_banner("THE CACHE IS YOURS",3.0)
	elif wave != previous_wave:
		hud.show_wave_banner("WAVE %d" % wave,2.0)

func _run_state_dict() -> Dictionary:
	var party: Array = []
	for actor in actors:
		if actor.peer_id <= 0:
			continue
		party.append({"slot":actor.slot, "name":actor.display_name, "health":actor.health,
			"alive":actor.alive, "peer":actor.peer_id, "downed":not actor.alive})
	return {
		"phase":phase, "wave":wave, "waves":Progress.WAVE_COUNT,
		"remaining":_remaining_enemies(),
		"timer":maxf(0.0,_clear_timer) if phase == "CLEARED" else 0.0,
		"sealed":bool(world.sealed), "chest_ready":chest_ready, "chest_open":chest_open,
		"party":party, "role":network_role, "endpoint":_endpoint, "local_slot":local_slot,
	}

func _sync_run_state() -> void:
	if network_role != "host":
		return
	_run_state.rpc(_run_state_dict())

func _set_phase(value: String) -> void:
	phase = value
	print("DELVE_PHASE phase=%s wave=%d" % [phase,wave])
	if phase == "GAME_OVER":
		if _field_inventory_open():
			_field_inventory.close()
		_set_cursor_free(true)
		hud.show_game_over("The delve has claimed the party.")

func _check_party_wipe() -> void:
	if network_role != "host":
		return
	if phase != "WAVE" and phase != "CLEARED":
		return
	var active := 0
	var standing := 0
	for actor in actors:
		if actor.peer_id <= 0:
			continue
		active += 1
		if actor.alive:
			standing += 1
	if active > 0 and standing == 0:
		_game_over()

func _game_over() -> void:
	if phase == "GAME_OVER":
		return
	_set_phase("GAME_OVER")
	Progress.clear_run(save_path)
	resume_data.clear()
	for actor in actors:
		actor.combat.stop()
	print("DELVE_GAME_OVER")
	_sync_run_state()

func _save_checkpoint(open_ready: bool) -> void:
	Progress.save_run(wave,open_ready,run_seed,save_path)

func _drop_party() -> void:
	var index := 0
	for actor in actors:
		if actor.peer_id <= 0:
			continue
		var angle := TAU * float(index) / 4.0
		var point: Vector3 = world.drop_center + Vector3(cos(angle)*2.4,0.0,sin(angle)*2.4)
		actor.respawn_at(point)
		actor.combat.damage_enabled = true
		index += 1

func _host_interact(slot: int) -> void:
	if network_role != "host" or slot < 0 or slot >= actors.size():
		return
	var actor = actors[slot]
	if not actor.alive:
		return
	var pos: Vector3 = actor.global_position
	match phase:
		"ASSEMBLY":
			if slot != 0:
				return
			var shaft: Vector3 = world.player_spawns[1] if world.player_spawns.size() > 1 else world.player_spawns[0]
			if pos.distance_to(shaft) <= INTERACT_RANGE:
				begin_descent()
		"CLEARED":
			if chest_ready and not chest_open and is_instance_valid(chest) \
					and pos.distance_to(world.chest_position) <= CHEST_RANGE:
				open_chest()
				return
			# Any survivor can take the party through a cleared gate. This keeps
			# the run moving when the host's own ranger is down but the party lives.
			if pos.distance_to(world.descent_position) <= INTERACT_RANGE:
				descend_next_wave()
			elif pos.distance_to(world.ascent_position) <= INTERACT_RANGE:
				ascend_to_surface()
		"COMPLETE":
			if pos.distance_to(world.ascent_position) <= INTERACT_RANGE:
				ascend_to_surface()
		_:
			pass
