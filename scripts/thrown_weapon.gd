extends Node3D
## A thrown sword or dagger. Flight and damage follow the arrow projectile:
## swept ray collision, gravity after launch, head-zone multiplier, and no
## damage from an authority-disabled replica.

signal impacted(enemy_hit: bool, impact_position: Vector3)

const Sword = preload("res://scripts/sword.gd")
const Dagger = preload("res://scripts/dagger.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const ImpactRules = preload("res://scripts/impact_rules.gd")
const GRAVITY := Vector3(0.0, -4.0, 0.0)
const SPIN_SPEED := 11.0
var weapon := "sword"
var weapon_index := 0
var blade_length := 1.0
var velocity := Vector3.ZERO
var flying := true
var age := 0.0
var damage := 0.0
var source_id := -1
## The body that threw this weapon; mobs read it through `note_attacker`.
var shooter: Node3D
var hit_mask := 1 | 2
var authoritative_damage := true
var _visual: Node3D
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_query.collision_mask = hit_mask
	if weapon == "dagger":
		var dagger := Dagger.new()
		dagger.blade_length = blade_length
		_visual = dagger
	else:
		var sword := Sword.new()
		sword.sword_kind = weapon_index
		sword.blade_length = blade_length
		_visual = sword
	add_child(_visual)

func launch(origin: Vector3, direction: Vector3, speed: float, shot_damage: float, excluded: Array[RID]) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	damage = shot_damage
	_query.exclude = excluded
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	age += delta
	if not flying:
		if age > 10.0:
			queue_free()
		return
	if is_instance_valid(_visual):
		_visual.rotation.x = fposmod(_visual.rotation.x + SPIN_SPEED * delta, TAU)
	var next := global_position + velocity * delta + GRAVITY * (0.5 * delta * delta)
	velocity += GRAVITY * delta
	_query.from = global_position
	_query.to = next
	# Sweep the tumbling weapon against terrain, props and enemy bodies.
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		global_position = hit.position
		flying = false
		var collider: Object = hit.collider
		var hit_enemy := collider.has_method("take_damage")
		if hit_enemy:
			if authoritative_damage:
				var headshot := Hitbox.is_headshot(collider as Node, hit.position)
				if is_instance_valid(shooter) and collider.has_method("note_attacker"):
					collider.note_attacker(shooter)
				if collider.has_method("note_impact"):
					collider.note_impact(ImpactRules.projectile_force(velocity))
				collider.take_damage(damage, source_id, headshot)
				BloodFx.impact(self, hit.position, velocity, damage, headshot)
			visible = false
		impacted.emit(hit_enemy, global_position)
		return
	global_position = next
	look_at(global_position + velocity, Vector3.UP)
	if age > 8.0 or global_position.y < -30.0:
		queue_free()
