extends Node3D
## Host-authoritative spell projectile: the Ember Staff's fireball and the Bone
## Staff's spear. Direct hits and detonations are presentation here; the scene
## that owns authority applies the area damage from the `detonated` signal.

signal detonated(centre: Vector3, direction: Vector3)
signal impacted(enemy_hit: bool, position: Vector3)

const Geo = preload("res://scripts/geo.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")

const GRAVITY := Vector3(0.0, -1.6, 0.0)

var kind := "fireball"
var velocity := Vector3.ZERO
var flying := true
var age := 0.0
var damage := 0.0
var blast_radius := 3.0
var pierce := 0
var source_id := -1
var hit_mask := 1 | 2
var authoritative_damage := true
var source_rig
var attacker_position := Vector3.ZERO
var visual_only := false
var _query := PhysicsRayQueryParameters3D.new()
var _excluded: Array[RID] = []
var _victims: Dictionary = {}
var _visual: Node3D
var _light: OmniLight3D
var _trail: CPUParticles3D
var _sparkle: Node3D
var _spin := 0.0


func _ready() -> void:
	_build_visual()
	_query.collision_mask = hit_mask


func launch(origin: Vector3, direction: Vector3, launch_speed: float,
		launch_damage: float, exclusions: Array[RID], mask: int,
		authoritative: bool, caster_position: Vector3 = Vector3.ZERO,
		radius: float = 3.0, pierce_count: int = 0, only_visual: bool = false) -> void:
	global_position = origin
	var aim := direction.normalized()
	if aim.length_squared() < 0.5:
		aim = Vector3.FORWARD
	velocity = aim * launch_speed
	damage = launch_damage
	blast_radius = radius
	pierce = pierce_count
	hit_mask = mask
	authoritative_damage = authoritative
	visual_only = only_visual
	source_rig = null
	attacker_position = caster_position if caster_position.is_finite() else origin
	_query.collision_mask = mask
	_excluded = exclusions.duplicate()
	_query.exclude = _excluded
	look_at(global_position + aim, Vector3.UP)


func _physics_process(delta: float) -> void:
	age += delta
	if is_instance_valid(_sparkle):
		_sparkle.rotate_y(delta * 7.0)
	if not flying:
		if age > 4.0:
			queue_free()
		return
	var next := global_position + velocity * delta + GRAVITY * (0.5 * delta * delta)
	velocity += GRAVITY * delta
	_query.from = global_position
	_query.to = next
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		_handle_hit(hit, next)
		return
	global_position = next
	look_at(global_position + velocity, Vector3.UP)
	if age > 5.0 or global_position.y < -30.0:
		queue_free()


func _handle_hit(hit: Dictionary, next: Vector3) -> void:
	var collider: Object = hit.collider
	var is_shield: bool = collider.has_method("is_shield")
	var unit: Object = collider
	var is_unit := is_instance_valid(unit) and unit is Node3D \
		and (unit.has_method("take_damage") or unit.has_method("receive_melee")) \
		and not is_shield
	var enemy_hit := is_unit and collider.has_method("take_damage")
	global_position = hit.position
	if is_unit and not visual_only and not _victims.has(unit.get_instance_id()) and pierce > 0:
		_victims[unit.get_instance_id()] = true
		pierce -= 1
		if authoritative_damage:
			_apply_direct(unit, hit.position)
		impacted.emit(enemy_hit, hit.position)
		# Punch through: exclude the body and resume just past the contact.
		var rid: RID = hit.rid
		if not _excluded.has(rid):
			_excluded.append(rid)
		_query.exclude = _excluded
		global_position = hit.position + velocity.normalized() * 0.12
		return
	flying = false
	if not visual_only:
		impacted.emit(enemy_hit, hit.position)
		if kind == "fireball":
			AbilityFx.explosion(get_parent() as Node3D, global_position, blast_radius)
		else:
			AbilityFx.burst(get_parent() as Node3D, global_position, AbilityFx.BONE, 0.9)
		detonated.emit(global_position, velocity.normalized())
	queue_free()


func _apply_direct(unit: Node3D, at: Vector3) -> void:
	var direction := velocity.normalized()
	if unit.has_method("receive_melee"):
		unit.receive_melee(damage, source_id, attacker_position, false)
	else:
		unit.take_damage(damage, source_id, false)
	if is_instance_valid(source_rig):
		BloodFx.impact(source_rig, at, direction, damage, false)
	else:
		AbilityFx.burst(get_parent() as Node3D, at, AbilityFx.BONE, 0.7)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "SpellVisual"
	add_child(_visual)
	if kind == "bone_spear":
		_build_bone_spear()
	else:
		_build_fireball()


func _build_fireball() -> void:
	var core := SphereMesh.new()
	core.radius = 0.145
	core.height = 0.29
	core.radial_segments = 18
	core.rings = 9
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color("fff2cf")
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.emission_enabled = true
	core_material.emission = Color("ffd9a0")
	core_material.emission_energy_multiplier = 5.0
	core_material.disable_receive_shadows = true
	var core_node := MeshInstance3D.new()
	core_node.mesh = core
	core_node.material_override = core_material
	_visual.add_child(core_node)

	var shell := SphereMesh.new()
	shell.radius = 0.28
	shell.height = 0.56
	shell.radial_segments = 20
	shell.rings = 10
	var shell_material := AbilityFx.glow_material(AbilityFx.FIRE, 3.2, 0.42)
	var shell_node := MeshInstance3D.new()
	shell_node.mesh = shell
	shell_node.material_override = shell_material
	_visual.add_child(shell_node)

	_sparkle = Node3D.new()
	_sparkle.name = "Embers"
	_visual.add_child(_sparkle)
	for index in 5:
		var ember := SphereMesh.new()
		ember.radius = 0.035 + 0.012 * index
		ember.height = ember.radius * 2.0
		var ember_node := MeshInstance3D.new()
		ember_node.mesh = ember
		ember_node.material_override = AbilityFx.glow_material(AbilityFx.FIRE_CORE, 4.0, 0.9)
		var angle := TAU * float(index) / 5.0
		ember_node.position = Vector3(cos(angle) * 0.3, sin(angle * 2.0) * 0.1, sin(angle) * 0.3)
		_sparkle.add_child(ember_node)

	_light = AbilityFx.flash_light(AbilityFx.FIRE, 3.2, 5.5)
	_light.light_energy = 2.4
	add_child(_light)

	_trail = AbilityFx.spark_particles(AbilityFx.FIRE, 44, 0.4, 1.8, 0.38, 0.05, false)
	_trail.emitting = true
	_trail.emission_sphere_radius = 0.1
	add_child(_trail)


func _build_bone_spear() -> void:
	var length := 1.25
	var bone := Geo.material(Color("d9cfb0"), 0.05, 0.55)
	var sinew := Geo.material(Color("6f5b45"), 0.0, 0.8)
	var shaft := Geo.cylinder(_visual, 0.022, 0.026, length, Vector3.ZERO, bone, 8)
	shaft.rotation.x = PI * 0.5
	shaft.position = Vector3(0.0, 0.0, length * 0.5)
	var tip := Geo.cylinder(_visual, 0.05, 0.0, 0.3, Vector3.ZERO, bone, 8)
	tip.rotation.x = -PI * 0.5
	tip.position = Vector3(0.0, 0.0, -0.12)
	var wrap := Geo.cylinder(_visual, 0.032, 0.032, 0.16, Vector3(0.0, 0.0, 0.34), sinew, 8)
	wrap.rotation.x = PI * 0.5
	for index in 3:
		var angle := TAU * float(index) / 3.0 + 0.4
		var barb := Geo.cylinder(_visual, 0.012, 0.0, 0.16, Vector3(cos(angle) * 0.07, sin(angle) * 0.07, 0.02), bone, 6)
		barb.rotation = Vector3(angle * 0.7, 0.0, -0.7)
	var ghost := SphereMesh.new()
	ghost.radius = 0.16
	ghost.height = 0.32
	var ghost_node := MeshInstance3D.new()
	ghost_node.mesh = ghost
	ghost_node.material_override = AbilityFx.glow_material(AbilityFx.BONE, 2.6, 0.28)
	ghost_node.position = Vector3(0.0, 0.0, -0.02)
	_visual.add_child(ghost_node)
	_light = AbilityFx.flash_light(AbilityFx.BONE, 1.6, 3.5)
	add_child(_light)
	_trail = AbilityFx.spark_particles(AbilityFx.BONE, 40, 0.3, 1.4, 0.42, 0.045, false)
	_trail.emitting = true
	_trail.emission_sphere_radius = 0.08
	add_child(_trail)
