extends Node3D

const Archer = preload("res://scripts/archer.gd")
const World = preload("res://scripts/range_world.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Hud = preload("res://scripts/hud.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Combat = preload("res://scripts/combat.gd")
const DodgeRoll = preload("res://scripts/dodge_roll.gd")
const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
const ARMOR_REDUCTION := [0.0, 0.15, 0.30]

var world
var archer
var hud
var audio
var combat
var roll
var _movement_direction := Vector3.ZERO
var player: CharacterBody3D
var camera: Camera3D
var enemies: Array[CharacterBody3D] = []
var arrows: Array[Node3D] = []
var health := 100.0
var stamina := 100.0
var _sprint_exhausted := false
var gold := 0
var kills := 0
var shots := 0
var respawns := 0
var activated: Dictionary = {}
var inspecting := false
var camera_yaw := 0.22
var camera_pitch := 0.08
var camera_distance := 4.5
var camera_focus := Vector3.ZERO
var _camera_ready := false
var _orbiting := false
var _orbit_pointer := Vector2.ZERO
var _key_drawing := false
var _mouse_drawing := false
var _cursor_free := false
var _jump_requested := false
var _interaction_id := ""
var _interaction_allowed := false
var _camera_query := PhysicsRayQueryParameters3D.new()
var _aim_query := PhysicsRayQueryParameters3D.new()
var _floor_query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_camera_query.collision_mask = 1
	_aim_query.collision_mask = 1 | 2
	_floor_query.collision_mask = 1
	world = World.new()
	world.name = "IronwoodFrontier"
	add_child(world)
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = 4
	player.collision_mask = 1 | 2
	player.floor_snap_length = 0.6
	player.floor_max_angle = deg_to_rad(46.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.80
	var collider := CollisionShape3D.new()
	collider.position.y = 0.90
	collider.shape = capsule
	player.add_child(collider)
	add_child(player)
	player.global_position = world.player_spawn + Vector3(0, 0.15, 0)
	archer = Archer.new()
	player.add_child(archer)
	archer.set_ground_sampler(_sample_floor)
	combat = Combat.new()
	add_child(combat)
	combat.setup(archer, player.position + Vector3(0, 1.4, -24))
	combat.shot.connect(_on_arrow_released)
	combat.actor = player
	roll = DodgeRoll.new()
	add_child(roll)
	camera = Camera3D.new()
	camera.name = "AdventureCamera"
	camera.fov = 59.0
	camera.near = 0.08
	camera.far = 450.0
	camera.current = true
	add_child(camera)
	audio = Audio.new()
	add_child(audio)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.bow_selected.connect(equip_bow)
	hud.armor_selected.connect(equip_armor)
	hud.sword_selected.connect(equip_sword)
	hud.weapon_selected.connect(equip_weapon)
	hud.view_toggled.connect(toggle_view)
	hud.camp_requested.connect(return_to_camp)
	hud.map_toggled.connect(toggle_map)
	hud.cursor_requested.connect(_set_cursor_free)
	hud.arena_requested.connect(func(): cancel_input(); get_tree().change_scene_to_file("res://arena.tscn"))
	archer.loadout_changed.connect(_update_loadout)
	hud.configure_map(world.landmarks, world.map_paths, world.interactables, world.WORLD_LIMIT)
	_update_loadout()
	for record: Dictionary in world.enemy_spawns:
		var enemy := Enemy.new()
		enemy.kind = int(record.kind)
		enemy.position = record.position + Vector3(0, 0.12, 0)
		enemy.player = player
		enemy.safe_center = world.player_spawn
		add_child(enemy)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.damaged_player.connect(take_damage)
		enemies.append(enemy)
	_update_camera(1.0)
	hud.show_feedback("The old waystones have gone dark. Follow the trails north.")
	print("IRONWOOD_WORLD_READY enemies=%d waystones=3 terrain=290m" % enemies.size())
	_set_cursor_free(false)

func _physics_process(delta: float) -> void:
	roll.advance(delta,player.is_on_floor())
	var input_vector := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	if inspecting or hud.map_open or _cursor_free:
		input_vector = Vector2.ZERO
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and not _sprint_exhausted and stamina > 1.0 and input_vector.length_squared() > 0.1
	var speed := SPRINT_SPEED if running else WALK_SPEED
	stamina = clampf(stamina + delta * (-19.0 if running else 13.0), 0.0, 100.0)
	if stamina <= 1.0:
		_sprint_exhausted = true
	elif stamina >= 25.0:
		_sprint_exhausted = false
	var camera_right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var camera_back := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
	var direction := camera_right * input_vector.x + camera_back * input_vector.y
	_movement_direction = direction
	var acceleration := 35.0 if player.is_on_floor() else 10.0
	player.velocity.x = move_toward(player.velocity.x, direction.x * speed, acceleration * delta)
	player.velocity.z = move_toward(player.velocity.z, direction.z * speed, acceleration * delta)
	if roll.active:
		player.velocity.x = roll.direction.x * DodgeRoll.SPEED
		player.velocity.z = roll.direction.z * DodgeRoll.SPEED
	if player.is_on_floor():
		player.velocity.y = -1.0
		if _jump_requested and not inspecting and not hud.map_open:
			player.velocity.y = 7.0
	else:
		player.velocity.y -= 20.0 * delta
	if roll.takeoff_pending:
		player.velocity.y = maxf(player.velocity.y,6.0)
		roll.takeoff_pending = false
	_jump_requested = false
	var previous_position := player.global_position
	player.move_and_slide()
	var limit: float = world.WORLD_LIMIT - 2.0
	player.position.x = clampf(player.position.x, -limit, limit)
	player.position.z = clampf(player.position.z, -limit, limit)
	archer.set_locomotion(player.velocity, player.is_on_floor() and not roll.active)
	archer.set_roll(roll.progress if roll.active else -1.0,roll.direction)
	var actual_velocity := (player.global_position - previous_position) / maxf(delta, 0.0001)
	combat.set_motion(actual_velocity, running or roll.active, player.is_on_floor() and not roll.active)
	combat.advance(delta)
	if player.position.y < -25.0:
		return_to_camp()

func _process(delta: float) -> void:
	_update_camera(delta)
	if _mouse_drawing or _key_drawing:
		update_crosshair_aim()
	_update_interaction()
	hud.reticle_visible = not _cursor_free and not inspecting and not hud.map_open
	hud.reticle = get_viewport().get_visible_rect().size * 0.5
	hud.update_status(health, stamina, gold, kills, archer.phase, archer.draw_amount, world.region_at(player.position), combat.get_attack_interval(), combat.attack_progress, combat.movement_mode)
	hud.update_world_position(player.position, archer.global_rotation.y, activated)

func _sample_floor(point: Vector3) -> float:
	_floor_query.from = point + Vector3(0, 1.15, 0)
	_floor_query.to = point - Vector3(0, 2.4, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return float(hit.position.y) if not hit.is_empty() else player.global_position.y

func _update_camera(delta: float) -> void:
	var desired_focus := player.global_position + Vector3(0, 1.5 if not inspecting else 1.05, 0)
	var factor := 1.0 if not _camera_ready else 1.0 - exp(-delta * 10.0)
	camera_focus = camera_focus.lerp(desired_focus, factor)
	var offset := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	var right := Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	var desired_position := camera_focus + offset + (Vector3.ZERO if inspecting else right * 0.70)
	_camera_query.from = camera_focus
	_camera_query.to = desired_position
	var hit := get_world_3d().direct_space_state.intersect_ray(_camera_query)
	if not hit.is_empty():
		desired_position = hit.position + hit.normal * 0.25
	camera.global_position = desired_position
	if inspecting:
		if camera.global_position.distance_squared_to(camera_focus) > 0.01:
			camera.look_at(camera_focus)
	else:
		camera.look_at(camera.global_position - offset.normalized())
	_camera_ready = true



func _set_cursor_free(value: bool) -> void:
	_cursor_free = value
	if value:
		cancel_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func update_crosshair_aim() -> void:
	_update_camera(0.0)
	if inspecting:
		combat.set_aim(player.global_position + Vector3(0,1.7,0) - archer.global_basis.z * 30.0)
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	_aim_query.from = camera.project_ray_origin(center)
	_aim_query.to = _aim_query.from + camera.project_ray_normal(center) * 300.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_aim_query)
	combat.set_aim(hit.position if not hit.is_empty() else _aim_query.to)

func begin_attack() -> void:
	if hud.map_open:
		return
	update_crosshair_aim()
	var started: bool = combat.begin_melee() if archer.weapon == "sword" else combat.begin_draw()
	if not started:
		hud.show_feedback("Wait for the weapon cooldown and stand on solid ground.")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _mouse_drawing:
			_mouse_drawing = false
			if not _key_drawing:
				update_crosshair_aim()
				combat.release_draw()
	if event is InputEventKey and event.keycode == KEY_Q and not event.pressed:
		if _key_drawing:
			_key_drawing = false
			if not _mouse_drawing:
				update_crosshair_aim()
				combat.release_draw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_orbiting = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: equip_weapon("bow")
			KEY_2: equip_weapon("sword")
			KEY_C: equip_armor((archer.armor_index + 1) % 3)
			KEY_SPACE: press_jump()
			KEY_E: interact()
			KEY_I: hud.toggle_equipment()
			KEY_M: toggle_map()
			KEY_V: toggle_view()
			KEY_R: return_to_camp()
			KEY_N:
				audio.muted = not audio.muted
				hud.show_feedback("Sound off" if audio.muted else "Sound on")
			KEY_ESCAPE:
				cancel_input()
				if inspecting:
					toggle_view()
				hud.close_panels()
				_set_cursor_free(true)
			KEY_Q:
				if not inspecting:
					hud.close_panels()
					_set_cursor_free(false)
				_key_drawing = true
				if not _mouse_drawing:
					begin_attack()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not inspecting:
				hud.close_panels()
				_set_cursor_free(false)
			_mouse_drawing = true
			if not _key_drawing:
				begin_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if inspecting:
				_orbiting = true
				_orbit_pointer = event.position
			else:
				hud.close_panels()
				_set_cursor_free(false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = maxf(camera_distance - 0.45, 2.7)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = minf(camera_distance + 0.45, 17.0)
	if event is InputEventMouseMotion:
		if not _cursor_free and not inspecting:
			camera_yaw -= event.relative.x * 0.004
			camera_pitch = clampf(camera_pitch + event.relative.y * 0.004, -0.7, 0.7)
		elif _orbiting and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			var change: Vector2 = event.position - _orbit_pointer
			_orbit_pointer = event.position
			camera_yaw -= change.x * 0.006
			camera_pitch = clampf(camera_pitch + change.y * 0.004, -0.10, 1.05)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(archer):
		_set_cursor_free(true)

func cancel_input() -> void:
	_key_drawing = false
	_mouse_drawing = false
	_orbiting = false
	combat.stop()

func equip_bow(index: int) -> void:
	archer.set_bow(index)
	audio.play_sound("equip")

func equip_sword(index: int) -> void:
	archer.set_sword(index)
	audio.play_sound("equip")

func equip_weapon(value: String) -> void:
	cancel_input()
	archer.set_weapon(value)
	audio.play_sound("equip")

func press_jump() -> void:
	if inspecting or hud.map_open:
		return
	_jump_requested = roll.press_jump(_movement_direction,-archer.global_basis.z,player.is_on_floor()) or _jump_requested
	if roll.active:
		cancel_input()

func equip_armor(index: int) -> void:
	archer.set_armor(index)
	audio.play_sound("equip")

func _update_loadout() -> void:
	hud.update_loadout(archer.bow_index, archer.armor_index, Archer.BOW_DATA[archer.bow_index], Archer.ARMOR_NAMES[archer.armor_index], archer.sword_index, archer.weapon, Archer.SWORD_DATA[archer.sword_index])

func toggle_view() -> void:
	inspecting = not inspecting
	camera_yaw = archer.global_rotation.y + (2.0 if inspecting else 0.2)
	camera_pitch = 0.12 if inspecting else 0.08
	camera_distance = 4.0 if inspecting else 4.5
	hud.set_inspecting(inspecting)
	_set_cursor_free(inspecting)

func toggle_map() -> void:
	cancel_input()
	hud.toggle_map()

func _update_interaction() -> void:
	_interaction_id = ""
	_interaction_allowed = false
	var prompt := ""
	for item: Dictionary in world.interactables:
		if player.position.distance_to(item.position) > 3.8:
			continue
		_interaction_id = item.id
		if item.kind == "camp":
			prompt = "E  /  Rest at the campfire"
			_interaction_allowed = true
		elif activated.has(item.id):
			prompt = item.name + "  /  Restored"
		else:
			var guarded := false
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy.alive and enemy.position.distance_to(item.position) < 12.0:
					guarded = true
					break
			prompt = "Defeat the nearby guardians to restore this waystone" if guarded else "E  /  Restore " + item.name
			_interaction_allowed = not guarded
		break
	hud.set_interaction(prompt)

func interact() -> void:
	_update_interaction()
	if not _interaction_allowed:
		return
	if _interaction_id == "camp":
		health = 100.0
		stamina = 100.0
		hud.show_feedback("Rested. The frontier is waiting.")
		return
	activated[_interaction_id] = true
	world.activate_interactable(_interaction_id)
	gold += 25
	audio.play_sound("bullseye")
	hud.show_feedback("Waystone restored  /  +25 gold")
	if activated.size() == 3:
		gold += 100
		hud.show_feedback("FRONTIER RESTORED  /  All three waystones lit  /  +100 gold", 6.0)

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount * (1.0 - float(ARMOR_REDUCTION[archer.armor_index])))
	audio.play_sound("hit")
	hud.flash_damage()
	if health <= 0.0:
		respawns += 1
		return_to_camp()
		hud.show_feedback("You fell. Recovered at the village campfire.", 4.0)

func return_to_camp() -> void:
	cancel_input()
	roll.reset()
	archer.set_roll(-1.0,Vector3.FORWARD)
	player.global_position = world.player_spawn + Vector3(0, 0.25, 0)
	player.velocity = Vector3.ZERO
	health = 100.0
	stamina = 100.0
	_sprint_exhausted = false
	inspecting = false
	hud.set_inspecting(false)
	camera_yaw = 0.22
	camera_pitch = 0.08
	camera_distance = 4.5
	_camera_ready = false
	hud.show_feedback("Ironwood village  /  Safe haven")
	_set_cursor_free(false)

func _on_arrow_released(origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	var arrow := Arrow.new()
	add_child(arrow)
	var shot_damage := Combat.damage_for(archer.bow_index, charge)
	var excluded: Array[RID] = [player.get_rid()]
	arrow.launch(origin, direction, speed, shot_damage, excluded)
	arrow.impacted.connect(_on_arrow_impact)
	for index in range(arrows.size() - 1, -1, -1):
		if not is_instance_valid(arrows[index]):
			arrows.remove_at(index)
	arrows.append(arrow)
	if arrows.size() > 32:
		arrows.pop_front().queue_free()
	shots += 1
	audio.play_sound("release")

func _on_arrow_impact(enemy_hit: bool, _position: Vector3) -> void:
	if enemy_hit:
		audio.play_sound("hit")

func _on_enemy_defeated(enemy: Node3D, reward: int) -> void:
	gold += reward
	kills += 1
	enemies.erase(enemy)
	hud.show_feedback("%s defeated  /  +%d gold" % [enemy.get_display_name(), reward])
