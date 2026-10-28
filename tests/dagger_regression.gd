extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const STEP := 1.0 / 240.0
var checks := 0
var failures := 0
var attacker
var victim
var clock := 0.0
var recording := false
var samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func step(delta: float) -> void:
	clock += delta
	attacker.rig.advance_animation(delta)
	attacker.combat.advance(delta)
	victim.rig.advance_animation(delta)
	victim.combat.advance(delta)

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		step(delta)
		remaining -= delta

func observe_sweep(hand: String, previous_base: Vector3, previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	check(hand == "right" and attacker.rig.phase.begins_with("MELEE"), "Only an active stab emits blade sweeps")
	if recording:
		samples.append({"time":clock, "base":current_base, "tip":current_tip, "radius":radius})

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

func place_victim(from_contact: Vector3) -> void:
	victim.position = from_contact - Vector3(0, 0.9, 0)
	victim.velocity = Vector3.ZERO
	victim.rig.global_basis = Basis(Vector3.UP, PI)
	attacker.rig.global_basis = Basis.IDENTITY
	victim.combat.set_aim(attacker.global_position + Vector3(0, 1.2, 0))
	attacker.combat.set_aim(victim.global_position + Vector3(0, 1.2, 0))

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	attacker = fighter(world, 0, Vector3.ZERO)
	victim = fighter(world, 1, Vector3(0, 0, -0.9))
	attacker.rig.melee_sweep.connect(observe_sweep)
	attacker.rig.set_weapon("dagger")
	attacker.rig.set_locomotion(Vector3.ZERO, true)
	await physics_frame
	await physics_frame

	check(attacker.rig._player.has_animation("Dagger_Stab"), "The rebuilt Ranger exports the authored dagger stab")
	var stab: Dictionary = attacker.rig._profile.clips.stab
	check(is_equal_approx(float(stab.duration), Archer.dagger_profile(0).seconds), "The stab clip duration matches dagger attack timing")
	check(is_equal_approx(float(stab.strike_start), 10.0/60.0) and is_equal_approx(float(stab.strike_end), 17.0/60.0), "The stab's authored forward window drives damage timing")
	check(float(Archer.dagger_profile(0).damage) < float(Archer.SWORD_DATA[0].damage), "The dagger deals less damage than the smallest sword")
	check(float(Archer.dagger_profile(0).seconds) < float(Archer.SWORD_DATA[0].seconds), "The dagger recovers faster than the smallest sword")
	check(float(Archer.dagger_profile(0).reach) < float(Archer.SWORD_DATA[0].reach), "The dagger is a closer-range weapon than every sword")
	check(attacker.rig.active_dagger.visible and not attacker.rig.active_sword.visible and not attacker.rig.active_bow.visible, "Dagger selection shows only the dagger model")
	check(attacker.rig.melee_radius() < 0.03, "The dagger uses a thin blade contact volume")
	# The authored thrust must actually lead with the dagger at torso height,
	# not leave the blade hanging or travel sideways.
	attacker.rig.begin_melee()
	attacker.rig.advance_animation(0.13)
	var chamber_base: Vector3 = attacker.rig.get_blade_base()
	var chamber_tip: Vector3 = attacker.rig.get_blade_tip()
	attacker.rig.advance_animation(0.13)
	var extension_base: Vector3 = attacker.rig.get_blade_base()
	var extension_tip: Vector3 = attacker.rig.get_blade_tip()
	var origin: Vector3 = attacker.rig.global_position
	var forward: Vector3 = -attacker.rig.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var extension_blade: Vector3 = extension_tip - extension_base
	extension_blade.y = 0.0
	var extension_reach: float = (extension_tip - origin).dot(forward)
	var chamber_reach: float = (chamber_tip - origin).dot(forward)
	check(extension_blade.normalized().dot(forward) > 0.90, "The stab points the dagger along the attack direction")
	check(extension_reach > 0.55, "The dagger tip reaches beyond the torso at full extension")
	check(extension_reach - chamber_reach > 0.30, "The chamber-to-extension travel is a real forward thrust")
	check(extension_base.y - origin.y > 1.0 and extension_base.y - origin.y < 1.55, "The stab lands at torso height, not at the ground or over the head")
	attacker.rig.advance_animation(0.30)
	check(attacker.rig.phase == "READY", "The authored stab completes after the geometry probe")

	# Probe the real authored hand path before placing targets.
	attacker.combat.damage_enabled = false
	recording = true
	samples.clear()
	clock = 0.0
	check(attacker.combat.begin_melee(), "A grounded ready dagger accepts a stab")
	advance(Archer.dagger_profile(0).seconds + STEP)
	recording = false
	check(not samples.is_empty(), "The authored stab emits real blade samples")
	check(attacker.rig.phase == "READY", "The dagger returns to ready after 0.5 seconds")
	check(attacker.combat.attack_progress >= 0.999999, "Dagger recovery finishes with the clip")
	if samples.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	var first_time: float = samples[0].time
	var last_time: float = samples[-1].time
	check(first_time >= 0.14 and first_time <= 0.20, "The stab's damage begins during the forward drive")
	check(last_time - first_time <= 0.13, "The dagger's active window is brief")
	var middle: Dictionary = samples[samples.size() / 2]
	var contact_time: float = float(middle.time)
	var contact: Vector3 = (middle.base as Vector3).lerp(middle.tip, 0.70)
	place_victim(contact)
	await physics_frame
	await physics_frame
	victim.health = 200.0
	attacker.combat.damage_enabled = true
	clock = 0.0
	check(attacker.combat.begin_melee(), "A second dagger stab starts after its short recovery")
	advance(Archer.dagger_profile(0).seconds + STEP)
	check(is_equal_approx(victim.health, 200.0 - float(Archer.dagger_profile(0).damage)), "A real dagger blade contact deals its small base damage once")
	check(attacker.combat.stagger_time == 0.0, "An unguarded dagger hit does not stagger the attacker")
	check(attacker.combat.begin_melee(), "The dagger can immediately start another stab")
	attacker.combat.stop()

	# A dagger guard never parries; it only softens the hit and costs more stamina.
	victim.health = 100.0
	victim.stamina = 100.0
	victim.rig.set_weapon("dagger")
	victim.combat.stop()
	victim.combat.set_motion(Vector3.ZERO, false, true)
	check(victim.combat.start_block(Vector3(0, 0, 1)), "A dagger can raise a guard")
	check(victim.rig._display_clip == "Sword_Block_Loop_OneHand", "The dagger guard reuses the authored one-hand guard loop")
	check(victim.combat.resolve_melee_defense(attacker.global_position) == Combat.DEFENSE_WEAK_BLOCK, "An instant dagger guard is still only a weak block, never a parry")
	var outcome: int = victim.receive_melee(20.0, 0, attacker.global_position, false)
	check(outcome == Combat.DEFENSE_WEAK_BLOCK, "Arena defense reports the weak block outcome")
	check(is_equal_approx(victim.health, 100.0 - 20.0 * Combat.WEAK_BLOCK_DAMAGE_SCALE), "A weak block halves incoming damage")
	check(is_equal_approx(victim.stamina, 100.0 - Combat.DAGGER_BLOCK_STAMINA), "A weak block costs the heavier dagger stamina chunk")
	check(victim.combat.blocking, "A weak block leaves the dagger guard up")

	# Sword guard timing is unchanged: the same immediate hit parries.
	victim.health = 100.0
	victim.stamina = 100.0
	victim.rig.set_weapon("sword")
	victim.combat.stop()
	victim.combat.set_motion(Vector3.ZERO, false, true)
	check(victim.combat.start_block(Vector3(0, 0, 1)), "The same fighter raises a sword guard")
	check(victim.combat.resolve_melee_defense(attacker.global_position) == Combat.DEFENSE_PARRY, "A sword guard keeps its timing-based parry")
	advance(Combat.PARRY_WINDOW + 0.05)
	check(victim.combat.resolve_melee_defense(attacker.global_position) == Combat.DEFENSE_BLOCK, "A sword guard outside the parry window remains a full block")
	victim.combat.stop()

	# A real stab into a held dagger guard: half damage and the attacker's swing continues.
	victim.health = 100.0
	victim.stamina = 100.0
	victim.rig.set_weapon("dagger")
	victim.combat.stop()
	victim.combat.set_motion(Vector3.ZERO, false, true)
	check(victim.combat.start_block(Vector3(0, 0, 1)), "The dagger guard is up for the contact run")
	advance(0.30)
	attacker.combat.damage_enabled = true
	clock = 0.0
	check(attacker.combat.begin_melee(), "The attacker starts a stab into the weak guard")
	advance(contact_time + 2.0 * STEP)
	check(is_equal_approx(victim.health, 100.0 - float(Archer.dagger_profile(0).damage) * Combat.WEAK_BLOCK_DAMAGE_SCALE), "A held dagger guard only halves a real stab hit")
	check(attacker.rig.phase == "MELEE" and attacker.combat.stagger_time == 0.0, "A weak block does not neutralize or stagger the attacker")
	advance(Archer.dagger_profile(0).seconds)
	check(attacker.rig.phase == "READY", "The attacker's stab still completes normally")

	# Switching back to a sword hides the dagger and restores full guard behavior.
	attacker.combat.stop()
	attacker.rig.set_weapon("sword")
	check(attacker.rig.active_sword.visible and not attacker.rig.active_dagger.visible, "Sword selection hides the dagger model")
	attacker.rig.set_weapon("dagger")
	check(attacker.rig.active_dagger.visible and not attacker.rig.active_sword.visible, "Dagger selection can be restored at any time")

	world.queue_free()
	await process_frame

	# Frontier receives the same weak guard through its enemy strike path.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game.health = 100.0
	game.stamina = 100.0
	game.archer.set_weapon("dagger")
	game.combat.set_motion(Vector3.ZERO, false, true)
	var enemy = game.enemies[0]
	enemy.global_position = game.player.global_position + Vector3(0, 0, -2.0)
	check(game.combat.start_block(Vector3(0, 0, -1)), "Frontier accepts a dagger guard")
	var enemy_state: String = enemy.state
	game._on_enemy_attack(enemy, 20.0)
	var body_guard: float = game.archer.damage_reduction(false)
	check(is_equal_approx(game.health, 100.0 - 20.0 * Combat.WEAK_BLOCK_DAMAGE_SCALE * (1.0 - body_guard)), "Frontier weak block only halves an enemy hit")
	check(is_equal_approx(game.stamina, 100.0 - Combat.DAGGER_BLOCK_STAMINA), "Frontier weak block spends the dagger stamina chunk")
	check(enemy.state == enemy_state, "Frontier weak block does not stagger the enemy")

	# The dagger thrust itself follows the crosshair. Aim low at the wolf and
	# the blade must angle down to that point, not run through its chest line.
	game.combat.stop()
	game.archer.cancel_draw()
	game.combat.melee_progress = 1.0
	var wolf = game.enemies[0]
	wolf.set_physics_process(false)
	wolf.global_position = game.player.global_position + Vector3(0, 0, -0.8)
	wolf.rotation.y = PI
	wolf.health = 100.0
	game.combat.set_motion(Vector3.ZERO, false, true)
	await physics_frame
	await physics_frame
	game.combat.set_aim(wolf.get_aim_position())
	check(game.combat.begin_melee(), "A crosshair-aimed dagger stab starts")
	var aim_dot := -1.0
	var signed_drop := 0.0
	var stab_time := 0.0
	while stab_time < Archer.dagger_profile(0).seconds + STEP:
		game.archer.advance_animation(STEP)
		game.combat.advance(STEP)
		stab_time += STEP
		if stab_time > 0.20 and stab_time < 0.24:
			var base: Vector3 = game.archer.get_blade_base()
			var tip: Vector3 = game.archer.get_blade_tip()
			var wanted: Vector3 = (game.combat.aim_point - base).normalized()
			aim_dot = maxf(aim_dot, (tip - base).normalized().dot(wanted))
			signed_drop = tip.y - base.y
	check(aim_dot > 0.9, "The dagger blade points at the crosshair aim point")
	check(signed_drop < -0.05, "A low crosshair aim angles the stab down")
	check(wolf.health < 100.0, "The aimed dagger blade contacts the wolf")

	# Pointing above the wolf must not secretly stab down at it.
	game.combat.stop()
	game.archer.cancel_draw()
	game.combat.melee_progress = 1.0
	wolf.health = 100.0
	game.combat.set_motion(Vector3.ZERO, false, true)
	game.combat.set_aim(game.player.global_position + Vector3(0, 1.5, -20.0))
	check(game.combat.begin_melee(), "A high-aimed dagger stab starts")
	var high_time := 0.0
	while high_time < Archer.dagger_profile(0).seconds + STEP:
		game.archer.advance_animation(STEP)
		game.combat.advance(STEP)
		high_time += STEP
	check(is_equal_approx(wolf.health, 100.0), "The stab follows the aim instead of auto-targeting the wolf")
	game.queue_free()
	await process_frame


	print("DAGGER_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
