extends SceneTree

const Actor = preload("res://scripts/arena_actor.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const STEP := 1.0 / 240.0

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fighter(parent: Node3D, slot: int, at: Vector3):
	var actor := Actor.new()
	actor.slot = slot
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(slot + 1, false, "Regression", at)
	actor.set_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor

func fire(world: Node3D, origin: Vector3, damage: float) -> Node3D:
	var arrow := Arrow.new()
	arrow.hit_mask = 1 | 4
	world.add_child(arrow)
	var excluded: Array[RID] = []
	arrow.launch(origin, Vector3.FORWARD, 40.0, damage, excluded)
	return arrow

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	await physics_frame
	await physics_frame

	# --- Arena actor: point zones, armor order, replica guard and crouch. ---
	var target = fighter(world, 0, Vector3(0, 0, 0))
	await physics_frame
	target.rig.advance_animation(STEP)
	var standing_head: Vector3 = target.head_hitbox_center()
	check(absf(standing_head.y - target.global_position.y - 1.71) < 0.06, "The head zone follows the animated Head bone")
	check(Hitbox.is_headshot(target, standing_head), "The head bone centre is inside the head zone")
	check(not Hitbox.is_headshot(target, Vector3(standing_head.x, standing_head.y - 0.6, standing_head.z)), "Chest height is body")
	check(Hitbox.is_headshot(target, Vector3(target.global_position.x, standing_head.y, target.global_position.z - 0.30)), "A capsule-surface hit at head height is a headshot")
	check(not Hitbox.is_headshot(target, target.global_position + Vector3(0, 0.9, -0.30)), "A capsule-surface hit at chest height is body")

	target.take_damage(20.0, 1, true)
	check(is_equal_approx(target.health, 60.0), "Arena head damage doubles")
	target.take_damage(20.0, 1, false)
	check(is_equal_approx(target.health, 40.0), "Arena body damage stays base")
	target.health = 100.0
	target.take_damage(20.0, 1)
	check(is_equal_approx(target.health, 80.0), "Damage without a hit zone stays body")
	target.health = 100.0
	target.rig.set_armor(1)
	target.take_damage(20.0, 1, true)
	check(is_equal_approx(target.health, 66.0), "Head multiplier applies before armor reduction")
	target.rig.set_armor(0)
	target.health = 100.0
	target.authoritative = false
	target.take_damage(20.0, 1, true)
	check(is_equal_approx(target.health, 100.0), "Replicas cannot apply headshot damage")
	target.authoritative = true

	target.rig.set_cover(false, Vector3.UP, 1.0, false, Vector3.ZERO)
	target.rig.advance_animation(STEP)
	var crouched_head: Vector3 = target.head_hitbox_center()
	check(crouched_head.y < standing_head.y - 0.4, "Crouching lowers the head zone with the skeleton")
	check(Hitbox.is_headshot(target, crouched_head), "The crouched head is still a head zone")
	check(not Hitbox.is_headshot(target, standing_head), "The standing head height is no longer the crouched head")
	target.rig.set_cover(false, Vector3.ZERO, 0.0, false, Vector3.ZERO)
	target.rig.advance_animation(STEP)

	# --- Frontier enemies: sentinel and wolf zones. ---
	var sentinel = Enemy.new()
	sentinel.kind = 1
	sentinel.position = Vector3(12, 0, 0)
	world.add_child(sentinel)
	var wolf = Enemy.new()
	wolf.kind = 0
	wolf.position = Vector3(-12, 0, 0)
	world.add_child(wolf)
	await physics_frame
	await physics_frame
	await process_frame
	var sentinel_head: Vector3 = sentinel.head_hitbox_center()
	check(sentinel_head.y > 1.7, "The sentinel head zone sits on the stone head")
	check(Hitbox.is_headshot(sentinel, sentinel_head), "The sentinel head is a head zone")
	check(not Hitbox.is_headshot(sentinel, sentinel.global_position + Vector3(0, 1.0, 0)), "The sentinel torso is body")
	sentinel.take_damage(10.0, 0, true)
	check(is_equal_approx(sentinel.health, 62.0), "Sentinel head damage doubles")
	sentinel.take_damage(10.0, 0, false)
	check(is_equal_approx(sentinel.health, 52.0), "Sentinel body damage stays base")

	var wolf_head: Vector3 = wolf.head_hitbox_center()
	check(wolf_head.y > 0.8 and wolf_head.z < wolf.global_position.z - 0.4, "The wolf head zone follows the imported head bone")
	var wolf_front := Vector3(wolf.global_position.x, 0.85, wolf.global_position.z - 0.30)
	check(Hitbox.is_headshot(wolf, wolf_front), "The wolf's reachable front neck/head is a head zone")
	check(not Hitbox.is_headshot(wolf, Vector3(wolf.global_position.x, 0.85, wolf.global_position.z + 0.30)), "The wolf's rear body stays body")
	wolf.take_damage(10.0, 0, true)
	check(is_equal_approx(wolf.health, 18.0), "Wolf head damage doubles")
	wolf.take_damage(10.0, 0, false)
	check(is_equal_approx(wolf.health, 8.0), "Wolf body damage stays base")

	# --- Real arrow path: the projectile passes the hit point. ---
	var shooter_target = fighter(world, 1, Vector3(20, 0, 0))
	shooter_target.rig.advance_animation(STEP)
	await physics_frame
	var arrow_head: Vector3 = shooter_target.head_hitbox_center()
	fire(world, Vector3(arrow_head.x, arrow_head.y, 2), 10.0)
	await create_timer(0.2).timeout
	check(is_equal_approx(shooter_target.health, 80.0), "An arrow that hits the head zone deals doubled damage")
	fire(world, Vector3(20, shooter_target.global_position.y + 0.9, 2), 10.0)
	await create_timer(0.2).timeout
	check(is_equal_approx(shooter_target.health, 70.0), "An arrow that hits the body deals base damage")

	# --- Real blade path: place the victim's head on a sampled strike point. ---
	var attacker = fighter(world, 2, Vector3(-30, 0, 0))
	var victim = fighter(world, 3, Vector3(-10, 0, 0))
	attacker.rig.set_weapon("sword")
	attacker.rig.set_sword(1)
	attacker.combat.set_aim(Vector3(-30, 1.2, -50))
	await physics_frame
	var samples: Array[Dictionary] = []
	var recorder := func(hand: String, previous_base: Vector3, previous_tip: Vector3,
			current_base: Vector3, current_tip: Vector3, radius: float) -> void:
		if hand == "right":
			samples.append({"base":current_base,"tip":current_tip})
	attacker.rig.melee_sweep.connect(recorder)
	attacker.combat.damage_enabled = false
	check(attacker.combat.begin_melee(), "The head-zone check starts a real authored swing")
	var duration := 2.0
	var remaining := duration + STEP
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		attacker.rig.advance_animation(delta)
		attacker.combat.advance(delta)
		remaining -= delta
	check(not samples.is_empty(), "The authored swing emits real blade samples")
	if not samples.is_empty():
		var sample: Dictionary = samples[samples.size() / 2]
		var contact: Vector3 = (sample.base as Vector3).lerp(sample.tip as Vector3, 0.65)
		victim.position += contact - victim.head_hitbox_center()
		victim.health = 100.0
		await physics_frame
		await physics_frame
		attacker.combat.damage_enabled = true
		check(attacker.combat.begin_melee(), "A second swing accepts the repositioned head")
		remaining = duration + STEP
		while remaining > 0.000001:
			var delta := minf(STEP, remaining)
			attacker.rig.advance_animation(delta)
			attacker.combat.advance(delta)
			remaining -= delta
		check(is_equal_approx(victim.health, 100.0 - 2.0 * 38.0), "A blade contact in the head zone doubles damage")

	world.queue_free()
	await process_frame
	print("HITBOX_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
