extends Node3D

signal impacted(enemy_hit: bool, impact_position: Vector3)

const Bow = preload("res://scripts/bow.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const GRAVITY := Vector3(0.0, -4.0, 0.0)
var velocity := Vector3.ZERO
var flying := true
var age := 0.0
var damage := 0.0
var source_id := -1
var hit_mask := 1 | 2
var authoritative_damage := true
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	var visual := Bow.create_arrow_visual()
	visual.position.z = Bow.ARROW_LENGTH
	add_child(visual)
	_query.collision_mask = hit_mask

func launch(origin: Vector3, direction: Vector3, speed: float, shot_damage: float, excluded: Array[RID]) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	damage = shot_damage
	_query.collision_mask = hit_mask
	_query.exclude = excluded
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	age += delta
	if not flying:
		if age > 10.0:
			queue_free()
		return
	var next := global_position + velocity * delta + GRAVITY * (0.5 * delta * delta)
	velocity += GRAVITY * delta
	_query.from = global_position
	_query.to = next
	# Sweep the physical arrow tip against terrain, props and enemy bodies.
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		global_position = hit.position
		flying = false
		var collider: Object = hit.collider
		var is_shield := collider.has_method("is_shield")
		var hit_enemy := collider.has_method("take_damage") and not is_shield
		if hit_enemy and authoritative_damage:
			collider.take_damage(damage, source_id, Hitbox.is_headshot(collider as Node, hit.position))
		# A shield intercepts the arrow without transferring damage to its
		# owner. Players and shields keep the shaft so it visibly sticks where
		# it landed; the arrow still times out with the existing age limit.
		if (is_shield or collider.has_meta("ironwood_player")) and collider is Node3D:
			reparent(collider as Node3D, true)
			visible = true
		elif hit_enemy:
			visible = false
		impacted.emit(hit_enemy, global_position)
		return
	global_position = next
	look_at(global_position + velocity, Vector3.UP)
	if age > 8.0 or global_position.y < -30.0:
		queue_free()
