extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const NetCacheScript = preload("res://scripts/net_cache.gd")
const STEP := 1.0/120.0
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index+1,false,"Expansion",at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO,false,true)
	return actor

func advance(actor, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP,remaining)
		actor.rig.advance_animation(delta)
		actor.combat.advance(delta)
		remaining -= delta

func reset_swing(actor) -> void:
	actor.combat.stop()
	actor.combat.left_melee_progress = 1.0
	actor.combat.right_melee_progress = 1.0
	actor.combat.melee_progress = 1.0
	actor.combat.stagger_time = 0.0
	actor.rig._clear_melee()
	actor.rig._sync_primary_hand()
	actor.combat.set_motion(Vector3.ZERO,false,true)
	actor.combat.set_aim(actor.global_position+Vector3(0,1.2,-8))

func horizontal_tip(actor, variant: String) -> Dictionary:
	reset_swing(actor)
	check(actor.combat.begin_melee("right",variant),"%s starts" % variant)
	var window: Vector2 = actor.rig._melee_window("right")
	advance(actor,window.x+0.02)
	var start: Vector3 = actor.rig.get_blade_tip("right")
	advance(actor,maxf(window.y-window.x-0.03,0.01))
	var finish: Vector3 = actor.rig.get_blade_tip("right")
	return {"start":start,"end":finish,"travel":finish-start}

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var attacker = fighter(world,0,Vector3.ZERO)
	attacker.rig.set_weapon("sword")
	attacker.rig.set_sword(0)
	# Horizontal cuts use the authored overhead body timing plus an actual
	# hip-led lateral arc. Both sides must sweep across, not merely down.
	var right: Dictionary = horizontal_tip(attacker,"horizontal_right")
	var left: Dictionary = horizontal_tip(attacker,"horizontal_left")
	for pair in [["right",right],["left",left]]:
		var travel: Vector3 = pair[1].travel
		check(Vector2(travel.x,travel.z).length() > absf(travel.y)*1.5,"%s horizontal cut sweeps across the body" % pair[0])
		check(travel.length() > 1.4,"%s horizontal cut covers a real blade path, not a forward poke" % pair[0])
	check(signf(right.travel.x) != signf(left.travel.x),"Left and right horizontal cuts mirror their lateral path")
	# The greatsword sweeps further than a one-handed cut; a wide bat-like arc
	# is the point of the heavy weapon, so require it to travel much further.
	attacker.rig.set_sword(2)
	var heavy: Dictionary = horizontal_tip(attacker,"horizontal_right")
	check(heavy.travel.length() > 2.4,"The greatsword carries its blade through a full-body swing")
	attacker.rig.set_sword(0)
	# Forward stab uses the authored thrust clip, a 0.5 s window, and extends
	# the socketed blade toward the crosshair instead of reusing the overhead.
	reset_swing(attacker)
	check(attacker.combat.begin_melee("right","stab"),"A forward stab starts")
	check(attacker.rig.phase == "MELEE_ST" and is_equal_approx(attacker.rig.melee_seconds(),0.5),"The stab carries its own phase and duration")
	var stab_window: Vector2 = attacker.rig._melee_window("right")
	advance(attacker,stab_window.x+0.01)
	var chamber: Vector3 = attacker.rig.get_blade_tip("right")
	advance(attacker,maxf(stab_window.y-stab_window.x-0.02,0.01))
	var extended: Vector3 = attacker.rig.get_blade_tip("right")
	var stab_line: Vector3 = (attacker.combat.aim_point-chamber).normalized()
	check((extended-chamber).dot(stab_line) > 0.18,"The stab blade travels along the crosshair line")
	# Damage-scaled stagger: heavier hits interrupt longer but not forever.
	var victim = fighter(world,1,Vector3(20,0,0))
	victim.health = 100.0
	victim.take_damage(14.0,4,false)
	var light_stagger: float = victim.combat.stagger_time
	victim.combat.stagger_time = 0.0
	victim.health = 100.0
	victim.take_damage(50.0,4,false)
	var heavy_stagger: float = victim.combat.stagger_time
	check(light_stagger > 0.1 and heavy_stagger > light_stagger,"Taking damage staggers, and heavier damage staggers longer")
	check(heavy_stagger <= Combat.HIT_STAGGER_MAX+0.0001,"Hit stagger stays bounded")
	var react_state: Dictionary = victim.rig.get_animation_state()
	check(str(react_state.phase) == "STAGGER" and float(react_state.time) > 0.0,"A hit presents the stagger phase with its remaining time")
	var flinch_replica := Archer.new()
	world.add_child(flinch_replica)
	flinch_replica.set_physics_process(false)
	flinch_replica.set_weapon("sword")
	flinch_replica.apply_animation_state(react_state)
	check(flinch_replica._hit_react > 0.0 and flinch_replica.phase == "READY","A replica decodes the hit flinch without entering a gameplay phase")
	flinch_replica.advance_animation(1.0)
	check(flinch_replica._hit_react == 0.0,"Replica flinch expires on its animation clock")
	# Bodies are soft: overlapping fighters are separated gently instead of
	# being shoved to the old hard-capsule distance.
	var first = fighter(world,2,Vector3(0,0,0))
	var second = fighter(world,3,Vector3(0,0,0.30))
	check(first.collision_mask == 1,"Fighters no longer hard-collide with each other")
	for tick in 30:
		first.step(1.0/60.0,[first,second],tick)
		second.step(1.0/60.0,[first,second],tick)
	var overlap_distance: float = Vector2(first.position.x-second.position.x,first.position.z-second.position.z).length()
	check(overlap_distance > 0.34 and overlap_distance < 0.62,"Soft separation settles closer than a hard capsule while preventing stacking")
	# Snapshot interpolation is real buffered interpolation, not an exponential
	# chase toward the newest packet.
	var host = fighter(world,0,Vector3(40,0,0))
	var replica := Actor.new()
	replica.slot = 1
	replica.authoritative = false
	world.add_child(replica)
	replica.configure(9,false,"Replica",Vector3(40,0,0))
	replica.set_process(false)
	replica.set_physics_process(false)
	var state_a: Dictionary = host.snapshot()
	state_a.position = Vector3(0,0,0)
	state_a.velocity = Vector3(2,0,0)
	replica.apply_snapshot(state_a)
	await create_timer(0.06).timeout
	var state_b: Dictionary = host.snapshot()
	state_b.position = Vector3(2,0,0)
	state_b.velocity = Vector3(2,0,0)
	replica.apply_snapshot(state_b)
	check(replica._states.size() >= 2,"The replica buffers more than the newest snapshot")
	if replica._states.size() >= 2:
		var t0: float = float(replica._states[0].time)
		var t1: float = float(replica._states[-1].time)
		var middle: Vector3 = replica._interpolate_position((t0+t1)*0.5)
		check(middle.x > 0.6 and middle.x < 1.4,"Interpolation samples between received snapshots")
		var extrapolated: Vector3 = replica._interpolate_position(t1+0.05)
		check(extrapolated.x > 2.0 and extrapolated.x < 2.2,"Short extrapolation carries velocity without a jump")
	# Net cache round-trips the player's name and host endpoint.
	var cache = NetCacheScript.new()
	cache.save_path = "user://net_cache_regression.json"
	var cache_file := FileAccess.open(cache.save_path,FileAccess.WRITE)
	if cache_file != null:
		cache_file.close()
	cache.remember("Wayfarer","100.64.0.9",7788)
	var loaded = NetCacheScript.new()
	loaded.save_path = cache.save_path
	loaded.load_cache()
	check(loaded.player_name == "Wayfarer" and loaded.address == "100.64.0.9" and loaded.port == 7788,"Network cache preserves the last name, address and port")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache.save_path))
	cache.free()
	loaded.free()
	# Quick step is a bounded grounded burst with its own cooldown.
	var step_node = DodgeStep.new()
	check(step_node.try_step(Vector3.RIGHT,true,false) and step_node.active,"A grounded quick step starts")
	var step_velocity: Vector3 = step_node.velocity()
	check(step_velocity.x > 4.0,"The quick step has real takeoff speed")
	for tick in 20:
		step_node.advance(1.0/60.0,true)
	check(not step_node.active and step_node.cooldown_left > 0.0,"The step ends and enters cooldown")
	check(not step_node.try_step(Vector3.RIGHT,true,false),"The step cannot restart during cooldown")
	step_node.free()
	world.queue_free()

	# Frontier routing: shoulder determines the horizontal side, consecutive
	# swings rebound, wheel variants and Q/E steps are real inputs.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.45).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game.archer.set_sword(0)
	game.archer.set_weapon("sword")
	game._set_cursor_free(false)
	game.shoulder_camera.side = 1
	game._next_swing_side = 1
	game.begin_attack("right")
	check(game.archer.phase == "MELEE_HR","A right-shoulder LMB swing starts from the right")
	game.combat.stop()
	game.combat.right_melee_progress = 1.0
	game.combat.melee_progress = 1.0
	game.archer._clear_melee()
	game.archer._sync_primary_hand()
	game.begin_attack("right")
	check(game.archer.phase == "MELEE_HL","A second LMB swing rebounds from the left")
	game.combat.stop()
	game.combat.right_melee_progress = 1.0
	game.combat.melee_progress = 1.0
	game.archer._clear_melee()
	game.archer._sync_primary_hand()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_WHEEL_UP
	up.pressed = true
	game._unhandled_input(up)
	check(game.archer.phase == "MELEE_ST","Wheel up starts a forward stab")
	game.combat.stop()
	game.combat.right_melee_progress = 1.0
	game.combat.melee_progress = 1.0
	game.archer._clear_melee()
	game.archer._sync_primary_hand()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	game._unhandled_input(down)
	check(game.archer.phase == "MELEE" and game.archer._right_variant == "overhead","Wheel down starts the overhead swing")
	game.combat.stop()
	game.combat.right_melee_progress = 1.0
	game.combat.melee_progress = 1.0
	game.archer._clear_melee()
	game.archer._sync_primary_hand()
	var before_step: Vector3 = game.player.position
	var stamina_before: float = game.stamina
	var e_key := InputEventKey.new()
	e_key.keycode = KEY_E
	e_key.pressed = true
	game._unhandled_input(e_key)
	await create_timer(0.12).timeout
	check(game.step.active and game.player.position.z < before_step.z,"E quick-steps right without starting an attack")
	check(game.stamina < stamina_before,"The quick step spends stamina")
	check(game.archer.phase == "READY","Q/E no longer draw or attack")
	var q_key := InputEventKey.new()
	q_key.keycode = KEY_Q
	q_key.pressed = true
	game.archer.set_weapon("bow")
	game.step.reset()
	game._unhandled_input(q_key)
	check(game.archer.phase == "READY","Q no longer starts a bow draw")
	game.queue_free()
	await process_frame

	# The Hollow forms open with the cached name, address and port.
	var net_cache = root.get_node_or_null("NetCache")
	check(net_cache != null,"NetCache autoload is registered")
	if net_cache != null:
		net_cache.remember("CachedRanger","100.64.0.12",7999)
		var hub = load("res://menu.tscn").instantiate()
		root.add_child(hub)
		await create_timer(0.35).timeout
		hub.hud.join_button.pressed.emit()
		await process_frame
		check(hub.hud._name_input.text == "CachedRanger" and hub.hud._address_input.text == "100.64.0.12" and int(hub.hud._port_input.value) == 7999,"The join form restores the cached name, address and port")
		hub.hud.close_form()
		hub.queue_free()
		await process_frame
		net_cache.reset()

	# Arena authority routes both the explicit melee variant and the quick step.
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	await create_timer(0.3).timeout
	var socket := PacketPeerUDP.new()
	check(socket.bind(0) == OK,"Expansion regression finds a free UDP port")
	var port: int = socket.get_local_port()
	socket.close()
	arena.host_game(port,"Expansion")
	await create_timer(0.3).timeout
	arena.actors[0].is_bot = false
	var arena_actor = arena.actors[0]
	arena._apply_action(0,"weapon","sword")
	arena._apply_action(0,"melee",{"aim":Vector3(0,1.2,-8),"hand":"right","variant":"stab"})
	check(arena_actor.rig.phase == "MELEE_ST","The arena accepts an explicit forward-stab action")
	arena_actor.combat.stop()
	arena_actor.combat.right_melee_progress = 1.0
	arena_actor.combat.melee_progress = 1.0
	arena_actor.rig._clear_melee()
	arena_actor.rig._sync_primary_hand()
	arena._apply_action(0,"step",Vector3.RIGHT)
	check(arena_actor.dodge.active,"The host applies a quick step from the network action")
	arena.leave_game()
	arena.queue_free()
	await process_frame
	print("COMBAT_EXPANSION_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
