extends SceneTree
## Regression for `scripts/backstab_ability.gd`.
##
## Deliberately animation-free: the arena rigs are frozen and no ability is
## activated. Only the targeting, landing spot, blink and strike rules run.
## Run manually:
##   godot --headless --path . --script tests/backstab_regression.gd

const Actor = preload("res://scripts/arena_actor.gd")
const Archer = preload("res://scripts/archer.gd")
const Backstab = preload("res://scripts/backstab_ability.gd")

## A target that keeps its own authority rules trivial: it records every hit
## and has no rig, so the module's plain-body path is exercised too.
class DummyTarget extends CharacterBody3D:
	var health := 100.0
	var alive := true
	var stagger_time := 0.0
	var hits := 0

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.8
		var collider := CollisionShape3D.new()
		collider.position.y = 0.9
		collider.shape = capsule
		add_child(collider)

	func take_damage(amount: float, _source_id: int, _headshot: bool = false) -> void:
		hits += 1
		health = maxf(0.0, health - amount)
		if health <= 0.0:
			alive = false

	func get_aim_position() -> Vector3:
		return global_position + Vector3(0.0, 1.2, 0.0)

	func stagger(seconds: float) -> void:
		stagger_time = maxf(stagger_time, seconds)

var checks := 0
var failures := 0
var mover
var victim
var dummy

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func forward_for(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func fighter(parent: Node3D, index: int, spawn: Vector3, authority: bool = true):
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = authority
	parent.add_child(actor)
	actor.configure(index + 1, false, "Regression", spawn)
	actor.set_process(false)
	actor.rig.set_process(false)
	actor.rig.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	return actor

func make_floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.4, 60.0)
	collider.shape = box
	body.add_child(collider)
	parent.add_child(body)
	body.position = Vector3(0.0, -0.2, 0.0)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	make_floor(world)
	mover = fighter(world, 0, Vector3.ZERO)
	victim = fighter(world, 1, Vector3(0.0, 0.0, -3.0))
	dummy = DummyTarget.new()
	world.add_child(dummy)
	dummy.global_position = Vector3(5.0, 0.0, -3.0)
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var mover_exclude: Array[RID] = []
	mover_exclude.append(mover.get_rid())

	# --- targeting ---------------------------------------------------------
	var found = Backstab.find_target(space, mover.global_position,
		victim.get_aim_position(), 4, 12.0, mover_exclude)
	check(found == victim, "find_target picks the aimed arena actor under the crosshair")
	check(Backstab.find_target(space, mover.global_position,
		victim.get_aim_position(), 4, 1.5, mover_exclude) == null,
		"find_target rejects an actor beyond max_range")
	check(Backstab.find_target(space, mover.global_position,
		mover.get_aim_position(), 4, 12.0, mover_exclude) == null,
		"find_target never returns the excluded actor itself")
	check(Backstab.find_target(space, mover.global_position,
		dummy.get_aim_position(), 2, 12.0, mover_exclude) == dummy,
		"find_target works with the frontier/delve target mask 2")
	check(Backstab.find_target(space, mover.global_position,
		dummy.get_aim_position(), 4, 12.0, mover_exclude) == null,
		"the arena mask 4 does not select a layer-2 body")

	# --- landing spot ------------------------------------------------------
	victim.global_basis = Basis(Vector3.UP, PI)
	victim.rig.global_basis = Basis(Vector3.UP, PI)
	var victim_forward: Vector3 = -victim.rig.global_basis.z
	victim_forward.y = 0.0
	victim_forward = victim_forward.normalized()
	var spot := Backstab.behind_spot(space, victim, 1.0)
	check(bool(spot.ok), "behind_spot finds clear ground behind the actor")
	var spot_position: Vector3 = spot.position
	var behind_offset: Vector3 = spot_position - victim.global_position
	behind_offset.y = 0.0
	check(behind_offset.dot(victim_forward) < -0.5,
		"the landing spot is behind the target, not in front")
	check(behind_offset.length() > 0.8 and behind_offset.length() < 1.6,
		"the landing spot keeps the requested distance")
	check(absf(spot_position.y - 0.08) < 0.03,
		"the landing spot is lifted onto the floor")
	var to_victim: Vector3 = victim.global_position - spot_position
	to_victim.y = 0.0
	to_victim = to_victim.normalized()
	check(forward_for(float(spot.yaw)).dot(to_victim) > 0.99,
		"the spot yaw faces the target")

	# --- blink -------------------------------------------------------------
	mover.rig.set_weapon("dagger")
	mover.combat.set_motion(Vector3.ZERO, false, true)
	check(mover.combat.start_block(forward_for(0.0)),
		"the attacker can raise a dagger guard before the blink")
	Backstab.blink(mover, spot_position, float(spot.yaw))
	check(mover.global_position.distance_to(spot_position) < 0.002,
		"blink teleports the authoritative actor onto the spot in one step")
	check(not mover.combat.blocking, "blink drops the raised guard")
	check(mover.velocity.is_equal_approx(Vector3.ZERO),
		"blink zeroes the actor's velocity")
	check(mover._states.is_empty(), "blink clears the interpolation history")
	check(mover._target_position.is_equal_approx(mover.global_position),
		"blink rebases the authoritative target position")
	var mover_facing: Vector3 = -mover.rig.global_basis.z
	mover_facing.y = 0.0
	check(mover_facing.normalized().dot(to_victim) > 0.99,
		"blink turns the rig to face the target's back")

	var ghost = fighter(world, 2, Vector3(0.0, 0.0, 6.0), false)
	await physics_frame
	var ghost_before: Vector3 = ghost.global_position
	Backstab.blink(ghost, Vector3(2.0, 0.08, 2.0), 0.4)
	check(ghost.global_position.is_equal_approx(ghost_before),
		"a non-authoritative arena actor never teleports")

	dummy.velocity = Vector3(3.0, 0.0, 4.0)
	Backstab.blink(dummy, Vector3(2.0, 0.08, -2.0), 0.75)
	check(dummy.global_position.is_equal_approx(Vector3(2.0, 0.08, -2.0)),
		"blink moves a plain CharacterBody3D")
	check(dummy.velocity.is_equal_approx(Vector3.ZERO),
		"blink zeroes a plain body's planar velocity")
	check((-dummy.global_basis.z).dot(forward_for(0.75)) > 0.999,
		"blink yaws a plain body")

	# --- strike ------------------------------------------------------------
	victim.health = 100.0
	victim.alive = true
	victim.combat.stagger_time = 0.0
	victim.rig.set_weapon("dagger")
	victim.combat.set_motion(Vector3.ZERO, false, true)
	check(victim.combat.start_block(Vector3(0.0, 0.0, 1.0)),
		"the victim holds a front guard for the backstab")
	var stab := float(Archer.DAGGER_DATA.damage) * 2.0
	check(is_equal_approx(stab, 28.0), "the backstab is twice the dagger's 14 damage")
	var applied := Backstab.strike(mover, victim, stab, 0)
	check(is_equal_approx(applied, 28.0),
		"strike returns the full 2x damage through the guard")
	check(is_equal_approx(victim.health, 72.0),
		"the guarded victim still loses 28 health")
	check(victim.combat.stagger_time >= Backstab.STAGGER_SECONDS,
		"a landed backstab staggers the victim")
	check(not victim.combat.blocking, "the victim's guard is broken by the stagger")

	victim.combat.stagger_time = 0.0
	victim.health = 0.0
	victim.alive = false
	var dead_applied := Backstab.strike(mover, victim, stab, 0)
	check(dead_applied == 0.0, "strike applies nothing to an already-dead target")
	check(victim.health == 0.0 and victim.combat.stagger_time == 0.0,
		"a dead target is not hit or staggered")

	# --- blocked rear ------------------------------------------------------
	var wall := StaticBody3D.new()
	wall.name = "RearWall"
	wall.collision_layer = 1
	var wall_collider := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(5.0, 3.0, 2.15)
	wall_collider.shape = wall_box
	wall.add_child(wall_collider)
	world.add_child(wall)
	wall.position = victim.global_position - victim_forward * 1.425
	wall.position.y = 1.5
	await physics_frame
	await physics_frame
	var blocked := Backstab.behind_spot(space, victim, 1.0)
	check(not bool(blocked.ok),
		"behind_spot refuses a rear that no standing capsule can occupy")

	world.queue_free()
	await process_frame

	print("BACKSTAB_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
