extends Node3D

const Archer = preload("res://scripts/archer.gd")
const World = preload("res://scripts/range_world.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Thrown = preload("res://scripts/thrown_weapon.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Hud = preload("res://scripts/hud.gd")
const Audio = preload("res://scripts/range_audio.gd")
const Combat = preload("res://scripts/combat.gd")
const DodgeRoll = preload("res://scripts/dodge_roll.gd")
const RunningSlide = preload("res://scripts/running_slide.gd")
const CoverMovement = preload("res://scripts/cover_movement.gd")
const ShoulderCamera = preload("res://scripts/shoulder_camera.gd")
const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
const ARMOR_REDUCTION := [0.0, 0.15, 0.30]

var world
var archer
var hud
var audio
var _player_state
var combat
var roll
var slide
var cover
var shoulder_camera := ShoulderCamera.new()
var _peek_requested := false
var _peek_right := Vector3.RIGHT
var _movement_direction := Vector3.ZERO
var player: CharacterBody3D
var camera: Camera3D
var enemies: Array[CharacterBody3D] = []
var arrows: Array[Node3D] = []
var thrown_weapons: Array[Node3D] = []
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
var _throw_held := false
var _cursor_free := false
var _jump_requested := false
var _interaction_id := ""
var _interaction_allowed := false
var _aim_query := PhysicsRayQueryParameters3D.new()
var _aim_exclude: Array[RID] = []
var _floor_query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_player_state = get_node_or_null("/root/PlayerState")
	_aim_query.collision_mask = 1 | 2
	_floor_query.collision_mask = 1
	world = World.new()
	world.name = "IronwoodFrontier"
	add_child(world)
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_meta("ironwood_player", true)
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
	combat.thrown.connect(_on_weapon_thrown)
	combat.actor = player
	roll = DodgeRoll.new()
	add_child(roll)
	slide = RunningSlide.new()
	add_child(slide)
	cover = CoverMovement.new()
	add_child(cover)
	cover.setup(player,collider)
	combat.cover = cover
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
	hud.shield_selected.connect(equip_shield)
	hud.view_toggled.connect(toggle_view)
	hud.camp_requested.connect(return_to_camp)
	hud.map_toggled.connect(toggle_map)
	hud.cursor_requested.connect(_set_cursor_free)
	hud.hub_requested.connect(_return_to_hub)
	if _player_state != null:
		archer.set_bow(_player_state.equipped_index("bow"))
		archer.set_sword(_player_state.equipped_index("sword"))
		archer.set_armor(_player_state.equipped_index("armor"))
		gold = int(_player_state.credits)
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
		enemy.attacked.connect(_on_enemy_attack)
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
		slide.reset()
	var running: bool = (cover.active or not cover.crouched and not cover.crouch_requested) and Input.is_physical_key_pressed(KEY_SHIFT) and not _sprint_exhausted and stamina > 1.0 and input_vector.length_squared() > 0.1
	var speed := 2.2 if not cover.active and (cover.crouched or cover.crouch_requested) else SPRINT_SPEED if running else WALK_SPEED
	var stamina_rate: float = 0.0 if combat.blocking else (-19.0 if running or slide.active else 13.0)
	stamina = clampf(stamina + delta * stamina_rate, 0.0, 100.0)
	if stamina <= 1.0:
		_sprint_exhausted = true
	elif stamina >= 25.0:
		_sprint_exhausted = false
	var camera_right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var camera_back := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
	var direction := camera_right * input_vector.x + camera_back * input_vector.y
	_movement_direction = direction
	var slide_velocity: Vector3 = slide.step(delta,player,cover,direction,roll.active)
	var acceleration := 35.0 if player.is_on_floor() else 10.0
	player.velocity.x = move_toward(player.velocity.x, direction.x * speed, acceleration * delta)
	player.velocity.z = move_toward(player.velocity.z, direction.z * speed, acceleration * delta)
	var was_in_cover: bool = cover.active
	_update_combat_cover_side()
	combat.face_block(Vector3(-sin(camera_yaw),0,-cos(camera_yaw)))
	var covered_velocity: Vector3 = cover.step(delta,direction,_peek_requested or combat.wants_cover_exposure(),combat.cover_side,running)
	if was_in_cover:
		player.velocity.x = covered_velocity.x
		player.velocity.z = covered_velocity.z
	if slide.active:
		player.velocity.x = slide_velocity.x
		player.velocity.z = slide_velocity.z
	if roll.active:
		player.velocity.x = roll.direction.x * DodgeRoll.SPEED
		player.velocity.z = roll.direction.z * DodgeRoll.SPEED
	if _jump_requested and not inspecting and not hud.map_open:
		player.velocity.y = 7.0
	elif player.is_on_floor():
		player.velocity.y = -1.0
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
	var actual_velocity := (player.global_position - previous_position) / maxf(delta, 0.0001)
	slide.after_move(player,actual_velocity)
	archer.set_cover(cover.active,cover.normal,cover.crouch_amount,cover.peeking,cover.lean)
	archer.set_slide(slide.progress if slide.active else -1.0,slide.direction)
	archer.set_roll(roll.progress if roll.active else -1.0,roll.direction)
	archer.set_locomotion(actual_velocity, player.is_on_floor() and not roll.active)
	combat.set_motion(actual_velocity, running or roll.active or slide.active, player.is_on_floor() and not roll.active)
	if _mouse_drawing or _key_drawing or _throw_held or combat.wants_cover_exposure() or archer.charge_frozen:
		update_crosshair_aim()
	combat.advance(delta)
	if player.position.y < -25.0:
		return_to_camp()

func _process(delta: float) -> void:
	shoulder_camera.update(delta)
	_update_camera(delta)
	if _mouse_drawing or _key_drawing or _throw_held or _peek_requested or combat.wants_cover_exposure() or archer.charge_frozen:
		update_crosshair_aim()
	_update_interaction()
	hud.reticle_visible = not _cursor_free and not inspecting and not hud.map_open
	hud.reticle = get_viewport().get_visible_rect().size * 0.5
	hud.update_status(health, stamina, gold, kills, archer.phase, archer.draw_amount, world.region_at(player.position), combat.get_attack_interval(), combat.attack_progress, combat.movement_mode, combat.blocking, combat.blocking and combat.block_time <= Combat.PARRY_WINDOW, archer.melee_progress_for("left"), archer.melee_progress_for("right"))
	hud.update_world_position(player.position, archer.global_rotation.y, activated)
	hud.update_cover(cover.active,cover.low,cover.peeking,shoulder_camera.side,cover.crouched,slide.active)

func _sample_floor(point: Vector3) -> float:
	_floor_query.from = point + Vector3(0, 1.15, 0)
	_floor_query.to = point - Vector3(0, 2.4, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return float(hit.position.y) if not hit.is_empty() else player.global_position.y

func _update_camera(delta: float) -> void:
	var focus_height: float = 1.05 if inspecting else cover.camera_height()
	var desired_focus := player.global_position + Vector3.UP*focus_height
	var factor := 1.0 if not _camera_ready else 1.0 - exp(-delta * 10.0)
	camera_focus = camera_focus.lerp(desired_focus, factor)
	var back := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch))
	camera.global_position = shoulder_camera.resolve(get_world_3d().direct_space_state,camera_focus,back,camera_distance,inspecting)
	if inspecting:
		if camera.global_position.distance_squared_to(camera_focus) > 0.01:
			camera.look_at(camera_focus)
	else:
		camera.look_at(camera.global_position - back)
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
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	# Clip camera-side cover at the actor, never at the animated weapon tip.
	# Using the tip feeds bow rotation back into target selection and skips close targets.
	var aim_anchor: Vector3 = player.global_position + Vector3.UP*cover.camera_height()
	var actor_depth := maxf(0.0,(aim_anchor-ray_origin).dot(ray_direction))
	_aim_query.from = ray_origin + ray_direction*actor_depth
	_aim_query.to = ray_origin + ray_direction * 300.0
	# The body you are posted against is camera-side cover, not a target.
	_aim_exclude.clear()
	var cover_rid: RID = cover.attached_surface()
	if cover_rid.is_valid():
		_aim_exclude.append(cover_rid)
	_aim_query.exclude = _aim_exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(_aim_query)
	combat.set_aim(hit.position if not hit.is_empty() else _aim_query.to)

func _update_combat_cover_side() -> void:
	cover.view_right = _peek_right
	combat.cover_side = shoulder_camera.side * (1 if _peek_right.dot(cover.normal.cross(Vector3.UP)) >= 0.0 else -1)

func _capture_attack_cover_side() -> void:
	if not _peek_requested and archer.phase == "READY":
		_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	_update_combat_cover_side()

func begin_attack(hand: String = "right") -> void:
	if hud.map_open:
		return
	_capture_attack_cover_side()
	update_crosshair_aim()
	var requested := hand if archer.weapon == "dual" else "right"
	var started: bool = combat.begin_melee(requested) if archer.weapon in ["sword","dagger","dual"] else combat.begin_draw()
	if not started:
		hud.show_feedback("Finish recovery and stand on solid ground." if archer.weapon in ["sword","dagger","dual"] else "Finish recovery, stand on solid ground, and use a clear cover edge or top.")

func begin_throw_attack() -> void:
	if hud.map_open:
		return
	if archer.weapon not in ["sword","dagger","dual"]:
		hud.show_feedback("Equip a sword with 2 or the dagger with 3 to throw.")
		return
	_capture_attack_cover_side()
	update_crosshair_aim()
	if not combat.begin_throw():
		hud.show_feedback("Finish recovery and stand on solid ground to throw.")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _mouse_drawing:
			_mouse_drawing = false
			if not _key_drawing:
				_update_combat_cover_side()
				update_crosshair_aim()
				combat.release_draw()
	if event is InputEventKey and event.keycode == KEY_Q and not event.pressed:
		if _key_drawing:
			_key_drawing = false
			if not _mouse_drawing:
				_update_combat_cover_side()
				update_crosshair_aim()
				combat.release_draw()
	if event is InputEventKey and event.keycode == KEY_T and not event.pressed:
		if _throw_held:
			_throw_held = false
			_update_combat_cover_side()
			update_crosshair_aim()
			combat.release_throw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_orbiting = false
		_peek_requested = false
		combat.stop_block()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: equip_weapon("bow")
			KEY_2: equip_weapon("sword")
			KEY_3: equip_weapon("dagger")
			KEY_4: equip_shield(not archer.shield_equipped)
			KEY_5: equip_weapon("dual")
			KEY_C: toggle_crouch()
			KEY_SPACE: press_jump(event.shift_pressed)
			KEY_F: toggle_cover()
			KEY_X:
				shoulder_camera.swap()
				_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
				_update_combat_cover_side()
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
					begin_attack("left")
			KEY_T:
				if not inspecting:
					hud.close_panels()
					_set_cursor_free(false)
				if not _throw_held:
					_throw_held = true
					begin_throw_attack()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not inspecting:
				hud.close_panels()
				_set_cursor_free(false)
			_mouse_drawing = true
			if not _key_drawing:
				begin_attack("left")
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if inspecting:
				_orbiting = true
				_orbit_pointer = event.position
			elif archer.weapon == "dual":
				hud.close_panels()
				_set_cursor_free(false)
				begin_attack("right")
			else:
				hud.close_panels()
				_set_cursor_free(false)
				_peek_requested = cover.active
				_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
				if not combat.start_block(Vector3(-sin(camera_yaw),0,-cos(camera_yaw))) and not cover.active:
					hud.show_feedback("Equip a sword or dagger with 2 or 3, stand still and finish recovery to guard.")
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
	_throw_held = false
	_orbiting = false
	_peek_requested = false
	combat.stop()

func equip_bow(index: int) -> void:
	cancel_input()
	archer.set_bow(index)
	audio.play_sound("equip")

func equip_sword(index: int) -> void:
	cancel_input()
	archer.set_sword(index)
	audio.play_sound("equip")

func equip_weapon(value: String) -> void:
	if value == "dual":
		if archer.weapon == "dual":
			value = "sword"
		elif archer.sword_index == 2:
			hud.show_feedback("Dual wield needs a one-handed sword. Select the small or medium sword.")
			return
	cancel_input()
	if not archer.set_weapon(value):
		hud.show_feedback("Dual wield needs a one-handed sword. Select the small or medium sword.")
		return
	audio.play_sound("equip")

func equip_shield(value: bool) -> void:
	if value and not archer.can_equip_shield():
		hud.show_feedback("Shield fits the dagger or the medium arming sword.")
		return
	cancel_input()
	archer.set_shield(value)
	audio.play_sound("equip")

func toggle_cover() -> void:
	if inspecting or hud.map_open or _cursor_free:
		return
	cancel_input()
	_peek_right = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	_update_combat_cover_side()
	if cover.active:
		cover.exit()
	elif not roll.active and cover.try_enter(Vector3(-sin(camera_yaw),0,-cos(camera_yaw))):
		slide.reset()
		hud.show_feedback("In cover  /  LMB or Q attacks out; RMB guards and peeks; F leaves")
	else:
		hud.show_feedback("Move closer to a tree, wall or solid debris and stand on the ground.")

func toggle_crouch() -> void:
	if inspecting or hud.map_open or _cursor_free or not player.is_on_floor() or roll.active:
		return
	var requested: bool = not cover.crouch_requested
	if requested:
		var sprinting := Input.is_physical_key_pressed(KEY_SHIFT) and not _sprint_exhausted and stamina > 1.0 and _movement_direction.length_squared() > 0.1
		slide.try_start(player,cover,sprinting,roll.active)
	else:
		slide.reset()
	cover.crouch_requested = requested

func press_jump(roll_requested: bool) -> void:
	if inspecting or hud.map_open or _cursor_free:
		return
	var grounded := player.is_on_floor()
	_peek_requested = false
	if not cover.prepare_jump():
		return
	slide.reset()
	archer.set_slide(-1.0,Vector3.FORWARD)
	cancel_input()
	_jump_requested = roll.press_jump(_movement_direction,-archer.global_basis.z,grounded,roll_requested) or _jump_requested
	if roll.active:
		_jump_requested = false
		cancel_input()

func equip_armor(index: int) -> void:
	cancel_input()
	archer.set_armor(index)
	audio.play_sound("equip")

func _update_loadout() -> void:
	hud.update_loadout(archer.bow_index, archer.armor_index, Archer.BOW_DATA[archer.bow_index], Archer.ARMOR_NAMES[archer.armor_index], archer.sword_index, archer.weapon, Archer.SWORD_DATA[archer.sword_index], Archer.DAGGER_DATA, archer.shield_equipped)

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
	_award_gold(25)
	audio.play_sound("bullseye")
	hud.show_feedback("Waystone restored  /  +25 gold")
	if activated.size() == 3:
		_award_gold(100)
		hud.show_feedback("FRONTIER RESTORED  /  All three waystones lit  /  +100 gold", 6.0)

func _on_enemy_attack(attacker, amount: float) -> void:
	if not is_instance_valid(attacker) or not attacker.alive:
		return
	var outcome: int = combat.resolve_melee_defense(attacker.global_position)
	if outcome == Combat.DEFENSE_PARRY:
		attacker.stagger(Combat.PARRY_STAGGER)
		Combat.spawn_impact(self,player.global_position + Vector3(0,1.15,0),"parry")
		audio.play_sound("parry")
		hud.show_feedback("PARRY  /  counter now",1.2)
		return
	if outcome == Combat.DEFENSE_BLOCK or outcome == Combat.DEFENSE_WEAK_BLOCK:
		var cost: float = combat.block_stamina_cost()
		stamina = maxf(0.0,stamina-cost)
		var push: Vector3 = player.global_position - attacker.global_position
		push.y = 0.0
		if push.length_squared() > 0.000001:
			push = push.normalized() * Combat.BLOCK_PUSH_SPEED
			player.velocity.x = push.x
			player.velocity.z = push.z
		Combat.spawn_impact(self,player.global_position + Vector3(0,1.15,0),"block")
		audio.play_sound("block")
		if outcome == Combat.DEFENSE_WEAK_BLOCK:
			take_damage(amount * Combat.WEAK_BLOCK_DAMAGE_SCALE)
			if health > 0.0:
				hud.show_feedback("WEAK BLOCK  /  -%d stamina  /  dagger only softens the hit" % int(cost),1.2)
		else:
			hud.show_feedback("BLOCKED  /  -%d stamina" % int(cost),1.0)
		return
	take_damage(amount)

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
	cover.reset()
	slide.reset()
	_jump_requested = false
	_movement_direction = Vector3.ZERO
	archer.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	archer.set_slide(-1.0,Vector3.FORWARD)
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
	arrow.hit_mask = 1 | 2 | 8
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

func _on_weapon_thrown(origin: Vector3, direction: Vector3, speed: float, charge: float, weapon_name: String, weapon_index: int) -> void:
	var thrown := Thrown.new()
	thrown.weapon = weapon_name
	thrown.weapon_index = weapon_index
	thrown.blade_length = float(Archer.DAGGER_DATA.length) if weapon_name == "dagger" else float(Archer.SWORD_DATA[clampi(weapon_index,0,2)].length)
	add_child(thrown)
	var shot_damage := Combat.throw_damage(weapon_name,weapon_index,charge)
	var excluded: Array[RID] = [player.get_rid()]
	thrown.launch(origin, direction, speed, shot_damage, excluded)
	thrown.impacted.connect(_on_arrow_impact)
	for index in range(thrown_weapons.size() - 1, -1, -1):
		if not is_instance_valid(thrown_weapons[index]):
			thrown_weapons.remove_at(index)
	thrown_weapons.append(thrown)
	if thrown_weapons.size() > 32:
		thrown_weapons.pop_front().queue_free()
	audio.play_sound("release")

func _on_enemy_defeated(enemy: Node3D, reward: int) -> void:
	_award_gold(reward)
	kills += 1
	enemies.erase(enemy)
	hud.show_feedback("%s defeated  /  +%d gold" % [enemy.get_display_name(), reward])

func _award_gold(amount: int) -> void:
	gold += amount
	if _player_state != null:
		_player_state.add_credits(amount)

func _return_to_hub() -> void:
	cancel_input()
	if _player_state != null:
		_player_state.save_state()
	get_tree().change_scene_to_file("res://menu.tscn")
