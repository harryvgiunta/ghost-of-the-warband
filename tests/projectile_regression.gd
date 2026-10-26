extends SceneTree

const Arrow = preload("res://scripts/arrow.gd")
const Enemy = preload("res://scripts/enemy.gd")
var failures := 0
var defeats := 0
var arena: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func fire(damage: float) -> Node3D:
	var arrow := Arrow.new()
	arena.add_child(arrow)
	var excluded: Array[RID] = []
	arrow.launch(Vector3(0, 1, 5), Vector3.FORWARD, 32.0, damage, excluded)
	return arrow

func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	var enemy := Enemy.new()
	enemy.kind = 0
	enemy.position = Vector3(0, 0, -3)
	arena.add_child(enemy)
	enemy.defeated.connect(func(_enemy, _reward): defeats += 1)
	var original_health := enemy.health
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.3)
	var collision := CollisionShape3D.new()
	collision.position.y = 1.5
	collision.shape = shape
	wall.add_child(collision)
	arena.add_child(wall)
	await physics_frame
	await physics_frame
	var blocked := fire(20.0)
	await create_timer(0.4).timeout
	check(not blocked.flying and absf(blocked.position.z - 0.15) < 0.02, "Physical wall must stop the swept arrow at its surface")
	check(enemy.health == original_health, "An enemy behind a wall must not receive arrow damage")
	wall.queue_free()
	await physics_frame
	await physics_frame
	var direct := fire(20.0)
	await create_timer(0.4).timeout
	check(not direct.flying and enemy.health == original_health - 20.0, "Unobstructed arrow must hit the real enemy collider")
	fire(original_health)
	await create_timer(0.4).timeout
	check(not enemy.alive and defeats == 1, "Lethal arrow must defeat the enemy exactly once")
	fire(original_health)
	await create_timer(0.4).timeout
	check(defeats == 1, "Dead enemies must not yield repeated kill rewards")
	arena.queue_free()
	await process_frame
	print("PROJECTILE_REGRESSION failures=", failures)
	quit(0 if failures == 0 else 1)
