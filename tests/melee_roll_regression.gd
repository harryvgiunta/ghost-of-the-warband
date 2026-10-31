extends SceneTree

const Actor = preload("res://scripts/warband/warband_body.gd")
const Roll = preload("res://scripts/dodge_roll.gd")
const STEP := 1.0 / 240.0
var checks := 0
var failures := 0
var attacker
var victim
var clock := 0.0
var sweep_count := 0
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

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		step(delta)
		remaining -= delta

func observe_sweep(hand: String, previous_base: Vector3, previous_tip: Vector3,
		current_base: Vector3, current_tip: Vector3, radius: float) -> void:
	sweep_count += 1
	check(hand == "right" and attacker.rig.phase == "MELEE", "Only an active melee animation emits blade sweeps")
	if recording:
		samples.append({"time":clock, "base":current_base, "tip":current_tip,
			"previous_base":previous_base, "previous_tip":previous_tip, "radius":radius})

func fighter(parent: Node3D, index: int, position_at: Vector3):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, "Regression", position_at)
	actor.set_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor

func start_swing() -> bool:
	clock = 0.0
	sweep_count = 0
	return attacker.combat.begin_melee()

func settle_bodies() -> void:
	await physics_frame
	await physics_frame

func run() -> void:
	# Real arena actors and physics shapes, without unrelated arena scenery.
	# Place targets from the imported animation's measured blade trajectory;
	# this tests contact independently of an asset's particular strike timing.
	var world := Node3D.new()
	root.add_child(world)
	attacker = fighter(world, 0, Vector3.ZERO)
	victim = fighter(world, 1, Vector3(20, 0, 0))
	var off_blade = fighter(world, 2, Vector3(-20, 0, 0))
	attacker.rig.melee_sweep.connect(observe_sweep)
	attacker.rig.set_weapon("sword")
	attacker.combat.set_aim(Vector3(0, 1.2, -20))
	await settle_bodies()
	var first_contact_time := 0.0
	var contact_position := Vector3.ZERO
	for size in 3:
		attacker.rig.set_sword(size)
		var duration: float = [1.0, 2.0, 3.0][size]
		attacker.combat.damage_enabled = false
		samples.clear()
		recording = true
		check(start_swing(), "Every sword accepts an uncharged authored swing")
		advance(duration + STEP)
		recording = false
		check(not samples.is_empty(), "Authored downswing supplies real blade samples")
		if samples.is_empty():
			continue
		first_contact_time = float(samples[0].time)
		var last_contact_time: float = samples[-1].time
		var middle: Dictionary = samples[samples.size() / 2]
		var blade_base: Vector3 = middle.base
		var blade_tip: Vector3 = middle.tip
		var contact := blade_base.lerp(blade_tip, 0.65)
		# ArenaActor's real capsule has its center 0.9 m above its origin.
		contact_position = contact - Vector3(0, 0.9, 0)
		victim.position = contact_position
		# The greatsword's vertical cut crosses the head zone; the one-handed
		# cuts contact the chest. Use enough health for either multiplier.
		var headshot_multiplier := 2.0 if size == 2 else 1.0
		var start_health := 200.0
		victim.health = start_health
		var rightmost := -INF
		var blade_radius := 0.0
		for sample in samples:
			rightmost = maxf(rightmost, maxf(maxf(sample.base.x, sample.tip.x),
				maxf(sample.previous_base.x, sample.previous_tip.x)))
			blade_radius = maxf(blade_radius, sample.radius)
		# This capsule is close to the measured swept envelope, but its entire
		# 0.3 m radius stays outside it. No actor-centered cone may hit it.
		off_blade.position = Vector3(rightmost + blade_radius + 0.45, contact_position.y, contact_position.z)
		off_blade.health = 100.0
		await settle_bodies()
		attacker.combat.damage_enabled = true
		check(start_swing(), "Equipped sword starts after its previous recovery")
		check(attacker.rig.draw_amount == 0.0, "Melee never pulls a bowstring")
		advance(maxf(0.0, first_contact_time - 2.0 * STEP))
		check(sweep_count == 0 and victim.health == start_health, "Windup cannot damage a target on the future blade path")
		check(not attacker.combat.begin_melee(), "Click spam cannot restart a sword swing")
		advance(last_contact_time + STEP - clock)
		check(is_equal_approx(victim.health, start_health - [30.0, 38.0, 50.0][size] * headshot_multiplier), "Actual blade contact damages an opposing collider exactly once per swing")
		check(off_blade.health == 100.0, "A nearby actor entirely off the blade path is not damaged")
		var active_samples := sweep_count
		victim.health = start_health
		advance(maxf(0.0, duration - STEP - clock))
		check(attacker.rig.phase == "MELEE", "The selected sword retains its full 1/2/3-second animation")
		check(victim.health == start_health and sweep_count == active_samples, "Recovery has no active sweeps or damage")
		advance(2.0 * STEP)
		check(attacker.rig.phase == "READY" and attacker.combat.attack_progress >= 0.999999, "Sword duration and independent recovery finish together")
		check(start_swing(), "A new swing can target the same victim again")
		# One deliberately coarse animation step crosses windup, strike, and
		# recovery; the real rig must emit every chronological contact sample.
		step(duration + STEP)
		check(is_equal_approx(victim.health, start_health - [30.0, 38.0, 50.0][size] * headshot_multiplier), "A coarse animation step cannot skip blade contact or retain last swing's victim exclusion")
		check(off_blade.health == 100.0, "Coarse stepping does not invent off-blade hits")
	if not samples.is_empty():
		# A thin world-layer sheet bisects the source-to-contact path. Its
		# width/height deliberately cover the full blade, not just actor centers.
		var source: Vector3 = attacker.global_position + Vector3(0, 1.1, 0)
		var contact := contact_position + Vector3(0, 0.9, 0)
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(8.0, 8.0, 0.01)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		wall.add_child(collision)
		world.add_child(wall)
		wall.global_position = source.lerp(contact, 0.5)
		wall.look_at(contact, Vector3.RIGHT if absf((contact - source).normalized().y) > 0.9 else Vector3.UP)
		await settle_bodies()
		victim.health = 100.0
		check(start_swing(), "A covered target does not prevent initiating a swing")
		step(3.0 + STEP)
		check(victim.health == 100.0, "Thin world cover blocks contact even when a coarse step crosses the entire strike")
		wall.queue_free()
		await settle_bodies()
		check(start_swing(), "A swing starts before cancellation")
		advance(first_contact_time * 0.5)
		attacker.combat.stop()
		var cancelled_samples := sweep_count
		advance(3.0)
		check(victim.health == 100.0 and sweep_count == cancelled_samples, "Explicit cancellation stops all later blade damage and samples")
		check(start_swing(), "A swing starts before a weapon swap")
		advance(first_contact_time * 0.5)
		attacker.rig.set_weapon("bow")
		check(attacker.combat.can_draw(), "Unfinished sword recovery never creates a bow cooldown")
		attacker.rig.set_weapon("sword")
		check(not attacker.combat.begin_melee(), "A weapon swap cannot bypass independent sword recovery")
		attacker.rig.set_weapon("bow")
		cancelled_samples = sweep_count
		advance(3.0)
		check(victim.health == 100.0 and sweep_count == cancelled_samples, "Weapon switching cancels all later blade damage and samples")
		check(attacker.rig.active_bow.visible and not attacker.rig.active_sword.visible, "Bow selection hides the sword")
		attacker.rig.set_weapon("sword")
		check(attacker.rig.active_sword.visible and not attacker.rig.active_bow.visible, "Sword selection hides the bow")
		check(attacker.rig.sword_index == 2, "Weapon switching remembers selected sword size")
		attacker.combat.damage_enabled = false
		check(start_swing(), "A non-damaging replica can animate a swing")
		step(3.0 + STEP)
		check(sweep_count > 0 and victim.health == 100.0, "Replica blade motion cannot cause authoritative damage")
		attacker.combat.damage_enabled = true
		check(start_swing(), "A swing starts before a roll")
		advance(first_contact_time * 0.5)
		attacker.combat.stop()
		attacker.rig.set_roll(0.2, Vector3.RIGHT)
		cancelled_samples = sweep_count
		advance(3.0)
		check(victim.health == 100.0 and sweep_count == cancelled_samples, "Rolling cancels the swing and cannot emit damaging blade samples")
		attacker.rig.set_roll(-1.0, Vector3.RIGHT)
	var roll := Roll.new()
	world.add_child(roll)
	check(roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,true,false),"Space performs a normal grounded jump")
	roll.advance(0.15,false)
	check(not roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,false,false) and not roll.active,"Quick second Space cannot trigger a roll or an airborne jump")
	roll.advance(1.0,false)
	check(not roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,false,false) and not roll.active,"Repeated Space never triggers a roll")
	check(not roll.press_jump(Vector3.RIGHT,Vector3.FORWARD,false,true) and roll.active,"Shift+Space rolls while airborne without a second-tap timing window")
	check(roll.takeoff_pending,"An airborne roll requests its takeoff impulse")
	check(roll.direction.is_equal_approx(Vector3.RIGHT),"Strafing direction overrides facing for the roll")
	roll.advance(Roll.DURATION*0.5,false)
	var progress := roll.progress
	roll.press_jump(Vector3.LEFT,Vector3.FORWARD,false,true)
	check(is_equal_approx(roll.progress,progress) and roll.direction.is_equal_approx(Vector3.RIGHT),"An active roll cannot restart or change direction")
	roll.advance(Roll.DURATION,false)
	check(not roll.active,"Roll ends after its finite duration")
	roll.press_jump(Vector3.FORWARD,Vector3.FORWARD,false,true)
	roll.press_jump(Vector3.FORWARD,Vector3.FORWARD,false,true)
	check(not roll.active,"Repeated airborne Shift+Space cannot chain rolls")
	roll.advance(0.01,true)
	check(not roll.press_jump(Vector3.ZERO,Vector3.BACK,true,true) and roll.active and roll.takeoff_pending,"Landing permits an immediate grounded Shift+Space roll without a preliminary jump")
	check(roll.direction.is_equal_approx(Vector3.BACK),"Standing roll uses the facing direction")
	roll.reset()
	roll.press_jump(Vector3.ZERO,Vector3.ZERO,true,true)
	check(roll.active and roll.direction.is_equal_approx(Vector3.FORWARD),"A roll without movement or facing uses the forward fallback")
	world.queue_free()
	await process_frame
	print("MELEE_ROLL_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
