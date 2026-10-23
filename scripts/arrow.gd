extends Node3D

signal impacted(enemy_hit: bool, impact_position: Vector3)

const Bow = preload("res://scripts/bow.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const GRAVITY := Vector3(0.0, -4.0, 0.0)
const VISUAL_BLEND_SECONDS := 0.12
var velocity := Vector3.ZERO
var flying := true
var age := 0.0
var damage := 0.0
var source_id := -1
var hit_mask := 1 | 2
var authoritative_damage := true
var _query := PhysicsRayQueryParameters3D.new()
var _visual: Node3D
var _visual_start := Vector3.ZERO
var _spawn_position := Vector3.ZERO
var _visual_elapsed := VISUAL_BLEND_SECONDS
var _has_visual_start := false

func _ready() -> void:
	_visual = Bow.create_arrow_visual()
	_visual.position.z = Bow.ARROW_LENGTH
	add_child(_visual)
	_query.collision_mask = hit_mask

func launch(origin: Vector3, direction: Vector3, speed: float, shot_damage: float, excluded: Array[RID], visual_start: Vector3 = Vector3.INF) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	damage = shot_damage
	_query.collision_mask = hit_mask
	_query.exclude = excluded
	look_at(global_position + direction, Vector3.UP)
	_spawn_position = origin
	_visual_start = visual_start
	_has_visual_start = visual_start.is_finite()
	_visual_elapsed = 0.0
	_place_visual()

func _physics_process(delta: float) -> void:
	age += delta
	_visual_elapsed = minf(_visual_elapsed + delta,VISUAL_BLEND_SECONDS)
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
		var damage_target: Object = collider.get_meta("ironwood_damage_target") if collider.has_meta("ironwood_damage_target") else null
		var hit_player := damage_target != null and is_instance_valid(damage_target) and damage_target.has_method("take_damage")
		var hit_enemy := collider.has_method("take_damage") and not is_shield
		if authoritative_damage:
			if hit_player:
				# The frontier controller owns the player's two-argument
				# take_damage; the bare CharacterBody has no damage method.
				damage_target.take_damage(damage)
			elif hit_enemy:
				collider.take_damage(damage, source_id, Hitbox.is_headshot(collider as Node, hit.position))
		# A shield intercepts the arrow without transferring damage to its
		# owner. Players and shields keep the shaft so it visibly sticks where
		# it landed; the arrow still times out with the existing age limit.
		if (is_shield or collider.has_meta("ironwood_player")) and collider is Node3D:
			reparent(collider as Node3D, true)
			visible = true
		elif hit_enemy:
			visible = false
		_visual_elapsed = VISUAL_BLEND_SECONDS
		_place_visual()
		impacted.emit(hit_enemy, global_position)
		return
	global_position = next
	look_at(global_position + velocity, Vector3.UP)
	_place_visual()
	if age > 8.0 or global_position.y < -30.0:
		queue_free()

func _place_visual() -> void:
	if not is_instance_valid(_visual):
		return
	var tip := global_position
	if _has_visual_start and _visual_elapsed < VISUAL_BLEND_SECONDS:
		var blend := smoothstep(0.0,1.0,_visual_elapsed / VISUAL_BLEND_SECONDS)
		tip += (_visual_start - _spawn_position) * (1.0 - blend)
	# The visual mesh's own tip sits ARROW_LENGTH behind its origin, so place
	# its origin that far ahead along the actual flight axis.
	_visual.global_transform = Transform3D(global_basis,tip + global_basis.z * Bow.ARROW_LENGTH)
