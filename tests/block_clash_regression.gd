extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Combat = preload("res://scripts/combat.gd")
const STEP := 1.0 / 240.0
const SWORD_DAMAGE := 38.0
var checks := 0
var failures := 0
var attacker
var defender
var clock := 0.0
var clash_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fighter(parent: Node3D, index: int, position_at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, false, "Regression", position_at)
	actor.set_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor

func step_both(delta: float) -> void:
	clock += delta
	attacker.rig.advance_animation(delta)
	attacker.combat.advance(delta)
	defender.rig.advance_animation(delta)
	defender.combat.advance(delta)

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		step_both(delta)
		remaining -= delta

func face_each_other() -> void:
	attacker.rig.global_basis = Basis(Vector3.UP, PI)
	defender.rig.global_basis = Basis(Vector3.UP, 0.0)
	defender.combat.set_aim(attacker.global_position + Vector3(0,1.2,0))
	attacker.combat.set_aim(defender.global_position + Vector3(0,1.2,0))

func reset_pair() -> void:
	attacker.combat.stop()
	defender.combat.stop()
	attacker.combat.stagger_time = 0.0
	defender.combat.stagger_time = 0.0
	attacker.combat.clash_cooldown = 0.0
	defender.combat.clash_cooldown = 0.0
	attacker.combat.attack_progress = 1.0
	defender.combat.attack_progress = 1.0
	attacker.combat.melee_progress = 1.0
	defender.combat.melee_progress = 1.0
	attacker.rig.phase = "READY"
	defender.rig.phase = "READY"
	attacker.health = 100.0
	defender.health = 100.0
	defender.stamina = 100.0
	attacker.velocity = Vector3.ZERO
	defender.velocity = Vector3.ZERO
	face_each_other()

func count_clash(_position: Vector3) -> void:
	clash_count += 1

func swing_until_first_hit() -> float:
	clock = 0.0
	check(attacker.combat.begin_melee(), "The attacker accepts the probe swing")
	while defender.health >= 99.99 and clock < 3.0:
		step_both(STEP)
	return clock

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	attacker = fighter(world,0,Vector3.ZERO)
	defender = fighter(world,1,Vector3(0,0,-1.4))
	attacker.rig.set_weapon("sword")
	defender.rig.set_weapon("sword")
	attacker.rig.set_sword(1)
	defender.rig.set_sword(1)
	attacker.combat.clash.connect(count_clash)
	check(defender.rig._player.has_animation("Sword_Block_Loop"), "The greatsword guard clip is exported")
	check(defender.rig._player.has_animation("Sword_Block_Loop_OneHand"), "The one-hand guard clip is exported")
	face_each_other()
	await physics_frame
	await physics_frame

	# Probe the real authored blade path once so parry/block runs can begin
	# with a known contact time rather than a hard-coded animation percentage.
	var contact_time := swing_until_first_hit()
	check(defender.health < 100.0, "An unguarded authored chop lands its real blade contact")
	check(contact_time > 0.2 and contact_time < 2.5, "The probe contact occurs during the authored strike")
	advance(3.0 - clock)
	check(attacker.rig.phase == "READY", "The probe swing finishes its recovery")

	# Timed parry: block starts 0.10 s before contact, inside the 0.25 s window.
	reset_pair()
	check(attacker.combat.begin_melee(), "Parry run starts a swing")
	advance(maxf(0.0,contact_time - 0.10))
	check(defender.combat.start_block(Vector3(0,0,1)), "A grounded, ready sword user can raise a guard")
	check(defender.rig._display_clip == "Sword_Block_Loop_OneHand", "A one-hand sword plays the authored guard loop")
	advance(0.20)
	check(defender.health == 100.0, "A parry prevents all damage")
	check(attacker.combat.stagger_time > 0.5, "A parry staggers the attacker for about 0.8 seconds")
	check(attacker.rig.phase == "READY" and attacker.combat.attack_progress >= 0.999999, "A parried swing is interrupted instead of finishing")
	check(defender.combat.blocking, "The parry leaves the defender's guard up")
	var base_local: Vector3 = defender.rig._model.global_transform.affine_inverse() * defender.rig.get_blade_base()
	var tip_local: Vector3 = defender.rig._model.global_transform.affine_inverse() * defender.rig.get_blade_tip()
	check(tip_local.x > base_local.x + 0.35, "The one-hand guard blade crosses the body")
	check(tip_local.y > base_local.y + 0.25, "The one-hand guard blade is raised above the hilt")
	check(tip_local.z > base_local.z + 0.10, "The one-hand guard blade points forward")
	check(defender.combat.begin_melee(), "The defender can immediately counter during the stagger window")
	check(not attacker.combat.begin_melee(), "The staggered attacker cannot queue another swing")
	defender.combat.stop()
	advance(1.0)
	reset_pair()
	defender.rig.set_weapon("bow")
	check(not defender.combat.start_block(Vector3(0,0,1)), "A bow cannot guard")
	defender.rig.set_weapon("sword")
	reset_pair()

	# Held standard block: guard predates the hit by more than the parry window.
	check(defender.combat.start_block(Vector3(0,0,1)), "Held guard starts")
	advance(0.12)
	check(attacker.combat.begin_melee(), "Standard-block run starts a swing")
	advance(contact_time + 0.05)
	check(defender.health == 100.0, "A held block prevents melee damage")
	check(is_equal_approx(defender.stamina,100.0 - Combat.BLOCK_STAMINA), "A standard block spends one stamina chunk")
	check(not attacker.combat.blocking and attacker.combat.stagger_time == 0.0, "A standard block does not stagger the attacker")
	check(attacker.rig.phase == "READY", "A standard block knocks the attacker's swing back to neutral")
	check(attacker.combat.begin_melee(), "The blocked attacker can immediately queue another action")
	attacker.combat.stop()
	defender.rig.set_sword(2)
	check(defender.rig._display_clip == "Sword_Block_Loop", "The greatsword plays the authored two-hand guard loop")
	advance(0.20)
	var two_hand_base: Vector3 = defender.rig._model.global_transform.affine_inverse() * defender.rig.get_blade_base()
	var two_hand_tip: Vector3 = defender.rig._model.global_transform.affine_inverse() * defender.rig.get_blade_tip()
	check(two_hand_tip.x > two_hand_base.x + 0.80, "The greatsword guard blade crosses in front of the face")
	check(two_hand_tip.z > two_hand_base.z + 0.05, "The greatsword guard blade points forward")
	var left_wrist: Vector3 = defender.rig.get_joint_positions()["left_wrist"]
	check(left_wrist.distance_to(defender.rig.get_blade_base()) < 0.25, "The greatsword guard keeps the support hand at the hilt")
	defender.rig.set_sword(1)
	check(defender.rig._display_clip == "Sword_Block_Loop_OneHand", "Returning to a one-hand sword restores its guard loop")
	advance(0.20)
	check(defender.velocity.z < -1.0, "A standard block pushes the defender away from the attacker")
	var replica = fighter(world,2,Vector3(20,0,20))
	replica.authoritative = false
	replica.apply_snapshot(defender.snapshot())
	check(replica.combat.blocking and replica.rig.is_blocking(), "Arena snapshots replicate the held guard pose")
	check(replica.rig.phase == "READY", "Replicated guard keeps gameplay phase READY")
	replica.queue_free()
	advance(3.0)
	reset_pair()

	# Facing matters; turning the guard perpendicular to the attack fails it.
	check(defender.combat.start_block(Vector3(0,0,1)), "Facing-test guard starts")
	advance(0.05)
	defender.rig.global_basis = Basis(Vector3.UP,PI * 0.5)
	check(attacker.combat.begin_melee(), "Facing-test swing starts")
	advance(contact_time + 0.05)
	# The close overhead strikes the head zone, so require at least the base
	# damage instead of pinning one zone; hitbox_regression checks both values.
	check(defender.health <= 100.0 - SWORD_DAMAGE, "A guard facing away from the attack takes unblocked damage")
	check(is_equal_approx(defender.stamina,100.0), "An unblocked hit spends no guard stamina")
	advance(3.0)

	# Simultaneous active swings facing each other clash: zero damage, both reset.
	reset_pair()
	clash_count = 0
	check(attacker.combat.begin_melee(), "Clash attacker starts a swing")
	check(defender.combat.begin_melee(), "Clash defender starts a swing in the same frame")
	var swings := clock
	while clash_count == 0 and clock - swings < 3.0:
		step_both(STEP)
	check(clash_count == 1, "Simultaneous active sword swings produce one clash")
	check(defender.health == 100.0 and attacker.health == 100.0, "A clash deals zero damage in both directions")
	check(attacker.rig.phase == "READY" and defender.rig.phase == "READY", "A clash resets both swings to neutral")
	check(attacker.combat.attack_progress >= 0.999999 and defender.combat.attack_progress >= 0.999999, "A clash bypasses both recovery timers")
	check(attacker.velocity.z > 1.0 and defender.velocity.z < -1.0, "A clash bounces both fighters apart")
	check(attacker.combat.begin_melee() and defender.combat.begin_melee(), "Both fighters can immediately act again after a clash")

	# Simultaneous swings without mutual facing are not a clash.
	reset_pair()
	clash_count = 0
	defender.combat.set_aim(defender.global_position + Vector3(1,1.2,0))
	check(attacker.combat.begin_melee() and defender.combat.begin_melee(), "Non-facing simultaneous swings start")
	var no_clash_start := clock
	while defender.health >= 99.99 and clock - no_clash_start < 3.0:
		step_both(STEP)
	check(clash_count == 0, "A defender facing away from the attacker does not clash")
	check(is_equal_approx(defender.health,100.0 - SWORD_DAMAGE), "Non-facing simultaneous swings deal normal blade damage")
	advance(3.0)
	reset_pair()

	# Frontier: the wolf/sentinel strike signal resolves through the same guard.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	game.archer.set_weapon("sword")
	game.combat.set_motion(Vector3.ZERO,false,true)
	var enemy = game.enemies[0]
	var to_enemy: Vector3 = enemy.global_position - game.player.global_position
	to_enemy.y = 0.0
	if to_enemy.length_squared() > 0.000001:
		game.camera_yaw = atan2(-to_enemy.x,-to_enemy.z)
		game.archer.global_basis = Basis(Vector3.UP,game.camera_yaw)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	check(game.combat.blocking, "Frontier right-click raises a sword guard")
	game._on_enemy_attack(enemy,13.0)
	check(game.health == 100.0 and enemy.state == "STAGGER", "Frontier parry prevents damage and staggers the wolf or sentinel")
	await create_timer(0.30).timeout
	game._on_enemy_attack(enemy,13.0)
	check(game.health == 100.0, "Frontier held block prevents damage")
	check(game.stamina < 100.0, "Frontier standard block spends stamina")
	check(not game.combat.blocking or game.combat.block_time > Combat.PARRY_WINDOW, "Frontier guard timer advanced past the parry window")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	check(not game.combat.blocking, "Releasing right mouse drops the frontier guard")
	game.queue_free()
	await process_frame

	# Arena: the host accepts the same right-click guard from its local slot.
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	await create_timer(0.3).timeout
	arena.host_game(7895,"Regression")
	await create_timer(0.2).timeout
	check(arena.local_slot == 0, "Arena host owns the local slot")
	arena.send_action("weapon","sword")
	await create_timer(0.1).timeout
	var arena_press := InputEventMouseButton.new()
	arena_press.button_index = MOUSE_BUTTON_RIGHT
	arena_press.pressed = true
	Input.parse_input_event(arena_press)
	await create_timer(0.1).timeout
	check(arena.actors[0].combat.blocking, "Arena right-click raises the authoritative guard")
	var arena_release := InputEventMouseButton.new()
	arena_release.button_index = MOUSE_BUTTON_RIGHT
	arena_release.pressed = false
	Input.parse_input_event(arena_release)
	await create_timer(0.1).timeout
	check(not arena.actors[0].combat.blocking, "Arena right-click release drops the authoritative guard")
	arena.leave_game()
	arena.queue_free()
	await process_frame

	world.queue_free()
	await process_frame
	print("BLOCK_CLASH_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
