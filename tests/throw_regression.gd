extends SceneTree

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const Thrown = preload("res://scripts/thrown_weapon.gd")
const STEP := 1.0 / 240.0
var failures := 0
var checks := 0

class Target extends StaticBody3D:
	var damage := 0.0
	var hits := 0
	var saw_headshot := false

	func take_damage(amount: float, _source: int, headshot: bool = false) -> void:
		hits += 1
		damage += amount
		saw_headshot = saw_headshot or headshot

	func head_hitbox_center() -> Vector3:
		return global_position + Vector3(0, 1.55, 0)

	func head_hit_profile() -> Vector2:
		return Vector2(0.34, 0.14)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func make_target(parent: Node3D, at: Vector3) -> Target:
	var target := Target.new()
	target.position = at
	target.collision_layer = 2
	target.collision_mask = 0
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.position.y = 0.9
	collider.shape = shape
	target.add_child(collider)
	parent.add_child(target)
	return target

func make_thrown(parent: Node3D, weapon_name: String, weapon_index: int) -> Thrown:
	var thrown := Thrown.new()
	thrown.weapon = weapon_name
	thrown.weapon_index = weapon_index
	thrown.blade_length = float(Archer.DAGGER_DATA.length) if weapon_name == "dagger" else float(Archer.SWORD_DATA[weapon_index].length)
	parent.add_child(thrown)
	return thrown

func wait_for_projectile(thrown) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(thrown) and thrown.flying and Time.get_ticks_msec() < deadline:
		await physics_frame

func advance(rig, combat, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		rig.advance_animation(delta)
		combat.advance(delta)
		remaining -= delta

func projectile_checks(world: Node3D) -> void:
	var head := make_target(world, Vector3(0, 0, -4))
	var body := make_target(world, Vector3(4, 0, -4))
	var covered := make_target(world, Vector3(8, 0, -4))
	var wall := StaticBody3D.new()
	wall.position = Vector3(8, 0, 0)
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2, 3, 0.2)
	var wall_collision := CollisionShape3D.new()
	wall_collision.position.y = 1.5
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	world.add_child(wall)
	await physics_frame
	await physics_frame

	var head_throw := make_thrown(world, "sword", 0)
	head_throw.launch(Vector3(0, 1.55, 2), Vector3.FORWARD, 26.0, 30.0, [])
	await wait_for_projectile(head_throw)
	check(head.hits == 1 and is_equal_approx(head.damage, 30.0), "A thrown weapon damages a real collider exactly once")
	check(head.saw_headshot, "A thrown weapon uses the animated head zone")
	check(not head_throw.flying and head_throw.velocity.y < 0.1, "Thrown weapons are swept under gravity instead of tracking a target")

	var body_throw := make_thrown(world, "dagger", 0)
	body_throw.launch(Vector3(4, 0.9, 2), Vector3.FORWARD, 30.0, 14.0, [])
	await wait_for_projectile(body_throw)
	check(body.hits == 1 and is_equal_approx(body.damage, 14.0), "A thrown dagger deals its own base damage")
	check(not body.saw_headshot, "A torso hit stays a body hit")

	var blocked_throw := make_thrown(world, "sword", 2)
	blocked_throw.launch(Vector3(8, 1.55, 2), Vector3.FORWARD, 24.0, 50.0, [])
	await wait_for_projectile(blocked_throw)
	check(covered.hits == 0 and not blocked_throw.flying, "World cover stops a thrown weapon before the target behind it")

	var replica_target := make_target(world, Vector3(12, 0, -4))
	var replica_throw := make_thrown(world, "sword", 1)
	replica_throw.authoritative_damage = false
	replica_throw.launch(Vector3(12, 1.0, 2), Vector3.FORWARD, 28.0, 38.0, [])
	await wait_for_projectile(replica_throw)
	check(replica_target.hits == 0 and not replica_throw.flying, "Replica throw visuals collide but never apply damage")

func rig_checks(holder: Node3D) -> void:
	var rig = Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	var combat = Combat.new()
	holder.add_child(combat)
	combat.setup(rig, Vector3(0, 1.4, -12))
	var emitted: Array[Dictionary] = []
	combat.thrown.connect(func(origin: Vector3, direction: Vector3, speed: float, charge: float, weapon_name: String, weapon_index: int):
		emitted.append({"origin":origin,"direction":direction,"speed":speed,"charge":charge,"weapon":weapon_name,"index":weapon_index}))
	combat.set_motion(Vector3.ZERO, false, true)

	rig.set_weapon("bow")
	check(not combat.begin_throw(), "A bow cannot throw a sword or dagger")
	rig.set_weapon("sword")
	rig.set_sword(0)
	check(combat.begin_throw(), "A grounded ready sword starts a throw charge")
	check(rig.phase == "T_DRAW", "Throwing uses its own charge phase")
	advance(rig, combat, 0.5)
	check(absf(rig.draw_amount - 0.5) < 0.002, "A shortsword fills 50% of its 1-second throw charge in half a second")
	combat.release_throw()
	check(emitted.size() == 1, "One release emits exactly one thrown weapon")
	check(absf(emitted[-1].charge - 0.5) < 0.002, "Thrown damage uses the actual charge fraction")
	check(is_equal_approx(Combat.throw_damage("sword", 0, 0.5), 15.0), "Thrown damage scales linearly from zero to base damage")
	check(combat.attack_progress < 0.001, "Release starts the throw recovery bar at zero")
	check(not rig.active_sword.visible, "The thrown weapon leaves the hand during release")
	check(rig.phase == "T_RELEASE", "Release plays the authored throw follow-through")
	combat.release_throw()
	check(emitted.size() == 1, "Repeated release cannot duplicate a thrown weapon")
	advance(rig, combat, 0.3)
	check(rig.phase == "T_RECOVER" and rig.active_sword.visible, "The endless supply restores the equipped weapon during recovery")
	check(not combat.can_throw(), "Recovery blocks the next throw")
	advance(rig, combat, 0.95)
	check(rig.phase == "READY" and combat.can_throw(), "Throw recovery finishes at the bow recovery boundary")
	check(rig.weapon == "sword" and rig.sword_index == 0, "Throwing never consumes or changes the equipped weapon")

	# Charge time and full damage follow each equipped weapon's own data.
	for weapon_name in ["sword", "dagger"]:
		var count := 3 if weapon_name == "sword" else 1
		for index in count:
			combat.stop()
			advance(rig, combat, 1.3)
			rig.set_weapon(weapon_name)
			if weapon_name == "sword":
				rig.set_sword(index)
			check(combat.begin_throw(), "Every equipped sword and dagger accepts a throw")
			var seconds: float = rig.charge_seconds()
			var expected_seconds: float = float(Archer.DAGGER_DATA.seconds) if weapon_name == "dagger" else float(Archer.SWORD_DATA[index].seconds)
			check(is_equal_approx(seconds, expected_seconds), "Throw charge duration follows the weapon size")
			advance(rig, combat, seconds + 0.01)
			check(rig.phase == "T_HOLD" and rig.draw_amount >= 0.999, "Holding a full charge never auto-throws")
			var before := emitted.size()
			combat.release_throw()
			check(emitted.size() == before + 1, "A full charge still requires an explicit release")
			var base: float = float(Archer.DAGGER_DATA.damage) if weapon_name == "dagger" else float(Archer.SWORD_DATA[index].damage)
			check(is_equal_approx(float(emitted[-1].charge), 1.0) and is_equal_approx(Combat.throw_damage(weapon_name, index, 1.0), base), "Full throw charge deals the weapon's base damage")
			check(String(emitted[-1].weapon) == weapon_name and int(emitted[-1].index) == (index if weapon_name == "sword" else 0), "The thrown model and size match the equipped weapon")

	# Canceling an unreleased charge spends no weapon and invents no recovery.
	combat.stop()
	advance(rig, combat, 1.3)
	var before_cancel := emitted.size()
	check(combat.begin_throw(), "A throw starts before cancellation")
	advance(rig, combat, 0.4)
	combat.stop()
	check(rig.phase == "READY" and emitted.size() == before_cancel, "Canceling a charge throws nothing")
	check(combat.begin_throw(), "Canceling an unthrown weapon does not invent a cooldown")
	combat.stop()

	# The authored melee clip must actually drive the throwing arm forward,
	# rather than holding a static weapon while the projectile spawns.
	advance(rig, combat, 1.3)
	rig.set_weapon("sword")
	rig.set_sword(0)
	combat.set_aim(Vector3(0, 1.4, -12))
	check(combat.begin_throw(), "The throw-motion probe starts")
	advance(rig, combat, 1.0)
	var chamber: Vector3 = rig.active_sword.global_position
	combat.release_throw()
	advance(rig, combat, 0.28)
	var extended: Vector3 = rig.active_sword.global_position
	var toward_aim := Vector3(0, 0, -12) - chamber
	toward_aim.y = 0.0
	toward_aim = toward_aim.normalized()
	check((extended - chamber).dot(toward_aim) > 0.20, "The release drives the throwing hand toward the aim line")
	check(extended.y < chamber.y + 0.15, "The release is a forward throw, not a static raised pose")
	advance(rig, combat, 1.3)

	# Rolling blocks a charge, and a melee swing still gates a throw until recovery.
	rig.set_roll(0.4, Vector3.FORWARD)
	check(not combat.begin_throw(), "Rolling cannot start a throw")
	rig.set_roll(-1.0, Vector3.FORWARD)
	check(combat.begin_melee(), "LMB melee remains available with the same weapon")
	advance(rig, combat, rig.melee_seconds() * 0.5)
	check(not combat.begin_throw(), "Sword recovery gates throwing until the swing finishes")
	advance(rig, combat, rig.melee_seconds())
	check(combat.begin_throw(), "A throw can start after the swing's independent recovery")

	holder.queue_free()

func frontier_checks() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout
	for enemy in game.enemies:
		enemy.set_physics_process(false)
	game.archer.set_weapon("sword")
	game.archer.set_sword(0)
	game.camera_yaw = 0.0
	game.camera_pitch = 0.0
	game._camera_ready = false
	await physics_frame
	await physics_frame
	game.archer.set_locomotion(Vector3.ZERO, true)
	game.combat.set_motion(Vector3.ZERO, false, true)
	var before: int = game.thrown_weapons.size()
	var press := InputEventKey.new()
	press.keycode = KEY_T
	press.physical_keycode = KEY_T
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	for tick in 20:
		await physics_frame
	check(game.archer.phase in ["T_DRAW", "T_HOLD"], "The frontier T key charges a throw")
	var held_charge: float = game.archer.draw_amount
	check(held_charge > 0.0, "Holding T accumulates throw charge")
	var release := InputEventKey.new()
	release.keycode = KEY_T
	release.physical_keycode = KEY_T
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame
	check(game.thrown_weapons.size() == before + 1, "The frontier controller launches one thrown weapon")
	if game.thrown_weapons.size() > before:
		var thrown = game.thrown_weapons.back()
		check(thrown is Thrown, "The frontier spawns the thrown-weapon projectile type")
		check(absf(thrown.damage - Combat.throw_damage("sword", 0, held_charge)) < 0.01, "The frontier projectile carries the charged damage")
	check(game.archer.phase == "T_RELEASE", "The frontier enters the throw release phase")
	# Endless supply: after recovery the same weapon is still equipped and ready.
	for tick in 90:
		await physics_frame
	check(game.archer.weapon == "sword" and game.archer.sword_index == 0 and game.archer.active_sword.visible, "The frontier keeps the equipped weapon after an endless-supply throw")
	check(game.combat.can_throw(), "The frontier becomes ready to throw again after recovery")
	# LMB still starts melee; T never replaces the normal melee input.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = root.get_visible_rect().size * 0.5
	click.pressed = true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	check(game.archer.phase.begins_with("MELEE"), "LMB still performs the normal melee attack after a throw")
	var click_up := InputEventMouseButton.new()
	click_up.button_index = MOUSE_BUTTON_LEFT
	click_up.position = click.position
	click_up.pressed = false
	Input.parse_input_event(click_up)
	Input.flush_buffered_events()
	await process_frame
	for voice in game.audio.voices:
		if voice.playing:
			await voice.finished
	game.queue_free()
	await process_frame

func arena_checks() -> void:
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	await create_timer(0.3).timeout
	arena.host_game(7899, "Throw Regression")
	await create_timer(0.2).timeout
	arena.send_action("weapon", "sword")
	await create_timer(0.1).timeout
	check(arena.actors[0].rig.weapon == "sword", "Arena equips the sword for a throw")
	arena.send_action("throw", Vector3(0, 1.2, -8))
	await create_timer(0.1).timeout
	check(arena.actors[0].rig.phase == "T_DRAW", "Arena accepts the throw charge action")
	arena.send_action("throw_release", Vector3(0, 1.2, -8))
	await create_timer(0.1).timeout
	check(arena.throws_fired == 1, "The arena host spawns exactly one authoritative throw")
	var thrown = null
	for projectile in arena.projectiles:
		if is_instance_valid(projectile) and projectile is Thrown and projectile.source_id == 0:
			thrown = projectile
	check(thrown != null, "The arena keeps the thrown weapon in its projectile list")
	if thrown != null:
		check(thrown.authoritative_damage, "The host owns thrown-weapon damage")
		check(thrown.damage > 0.0, "The host applies the charged throw damage")
	var before_replica: int = arena.projectiles.size()
	arena.network_role = "client"
	arena.local_slot = 1
	arena._throw_event(0, Vector3(0, 1.2, -2), Vector3.FORWARD, 20.0, "dagger", 0)
	var replica = arena.projectiles.back() if not arena.projectiles.is_empty() else null
	check(arena.projectiles.size() == before_replica + 1, "A client throw event spawns the remote projectile")
	check(replica is Thrown and replica != null and not replica.authoritative_damage, "Replica throws are visual-only")
	arena.network_role = "host"
	arena.local_slot = 0
	arena.leave_game()
	for voice in arena.audio.voices:
		if voice.playing:
			await voice.finished
	arena.queue_free()
	await process_frame

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	await physics_frame
	await physics_frame
	await projectile_checks(world)
	world.queue_free()
	await process_frame

	var holder := Node3D.new()
	root.add_child(holder)
	rig_checks(holder)
	await process_frame

	await frontier_checks()
	await arena_checks()
	print("THROW_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
