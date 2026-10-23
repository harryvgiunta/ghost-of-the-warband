extends SceneTree
## Horizontal sword cuts must reach the advertised shortsword distance against
## the 0.9 m cinder devils without becoming an unbounded actor-centered cone.

const Enemy = preload("res://scripts/enemy.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _spawn_devil(game, distance: float):
	var devil := Enemy.new()
	devil.kind = 2
	devil.devil_weapon = "claw"
	devil.pack_index = 0
	devil.player = game.player
	devil.safe_center = Vector3(1000,0,1000)
	devil.position = game.player.global_position+Vector3(0,0,-distance)
	game.add_child(devil)
	devil.set_physics_process(false)
	return devil

func _swing(game, devil, variant: String = "horizontal_left") -> void:
	game.camera_yaw = 0.0
	game.shoulder_camera.side = 1
	game._next_swing_side = 1
	game.combat.set_aim(devil.get_aim_position())
	game.begin_attack("right",variant)
	# begin_attack refreshes the crosshair; pin the aim back onto the short target.
	game.combat.set_aim(devil.get_aim_position())

func _spawn_devil_at(game, offset: Vector3):
	var devil := Enemy.new()
	devil.kind = 2
	devil.devil_weapon = "claw"
	devil.pack_index = 0
	devil.player = game.player
	devil.safe_center = Vector3(1000,0,1000)
	devil.position = game.player.global_position+offset
	game.add_child(devil)
	devil.set_physics_process(false)
	return devil

func _reset_swing(game) -> void:
	game.combat.stop()
	game.archer._clear_melee()
	game.archer._sync_primary_hand()
	game.combat.right_melee_progress = 1.0
	game.combat.melee_progress = 1.0
	game.combat.left_melee_progress = 1.0

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
		enemy.set_deferred("collision_layer",0)
	game._set_cursor_free(false)
	var spot: Vector3 = game.world._ground(-20,21)
	game.player.global_position = spot+Vector3(0,0.2,0)
	game.player.velocity = Vector3.ZERO
	game.archer.set_sword(0)
	game.archer.set_weapon("sword")
	await physics_frame

	var near = _spawn_devil(game,1.75)
	await physics_frame
	_swing(game,near)
	for frame in 120:
		await physics_frame
	check(not near.alive and near.health == 0.0, "A horizontal cut reaches a 0.9 m devil at 1.75 m")
	near.queue_free()
	await process_frame
	_reset_swing(game)
	await physics_frame

	var far = _spawn_devil(game,2.30)
	await physics_frame
	_swing(game,far)
	for frame in 120:
		await physics_frame
	check(far.alive and is_equal_approx(far.health,far.max_health), "The forgiveness envelope ends before an unrelated 2.3 m target")
	far.queue_free()
	await process_frame
	_reset_swing(game)
	await physics_frame

	# A horizontal cut is a swing across the front, not a narrow band down the
	# crosshair. Both flanks of the arc take damage from one right-to-left cut.
	var right_flank = _spawn_devil_at(game,Vector3(1.00,0,-0.58))
	var left_flank = _spawn_devil_at(game,Vector3(-1.00,0,-0.58))
	await physics_frame
	# Aim down the middle: the arc is centred on the crosshair, so both flanks
	# have to be inside one swing from a level forward aim.
	game.camera_yaw = 0.0
	game.shoulder_camera.side = 1
	game._next_swing_side = 1
	game.combat.set_aim(game.player.global_position+Vector3(0,0.6,-6))
	game.begin_attack("right","horizontal_right")
	game.combat.set_aim(game.player.global_position+Vector3(0,0.6,-6))
	for frame in 120:
		await physics_frame
	check(right_flank.health < right_flank.max_health,"The right-to-left cut hits a target 60 degrees to the starting side")
	check(left_flank.health < left_flank.max_health,"The same cut follows through to a target 60 degrees to the far side")
	right_flank.queue_free()
	left_flank.queue_free()
	await process_frame
	_reset_swing(game)

	game.archer.set_sword(0)
	game.archer.set_weapon("dagger")
	await physics_frame

	var dagger_near = _spawn_devil(game,1.20)
	await physics_frame
	_swing(game,dagger_near,"")
	for frame in 120:
		await physics_frame
	check(dagger_near.health < dagger_near.max_health, "A dagger thrust reaches a devil at its 1.2 m advertised reach")
	dagger_near.queue_free()
	await process_frame
	_reset_swing(game)
	await physics_frame

	var dagger_far = _spawn_devil(game,1.90)
	await physics_frame
	_swing(game,dagger_far,"")
	for frame in 120:
		await physics_frame
	check(dagger_far.alive and is_equal_approx(dagger_far.health,dagger_far.max_health), "The dagger envelope ends before an unrelated 1.9 m target")
	dagger_far.queue_free()
	game.queue_free()
	await process_frame
	print("SWING_REACH_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
