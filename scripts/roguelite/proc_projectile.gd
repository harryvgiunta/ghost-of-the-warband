class_name ProcProjectile
extends Node3D
## A proc's own body: the spinning blade, the splinter ring, the crescent wave
## and the planted blood charge.
##
## These are deliberately not `arrow.gd`. An arrow is a player's shot with its own
## lag compensation, ammo and equipment rules; a proc is a consequence that the
## authority already decided to pay for. It flies for a short life, applies one
## damage figure it was handed, and tells its owner's runtime what it struck so
## the kill can be booked like any other.
##
## Damage from a proc never rolls procs again. That is the one rule that keeps
## Arrow Nova from eating the frame: eight splinters that each rolled a nova would
## be an unbounded fan-out, so the fan-out is exactly one deep by construction.

const Geo = preload("res://scripts/geo.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")

const GRAVITY := Vector3(0.0, -5.0, 0.0)

var kind := "dagger"
var velocity := Vector3.ZERO
var damage := 0.0
var source_id := -1
var shooter: Node3D
var hit_mask := 1 | 2
var pierce := 0
var radius := 0.0
var delay := 0.0
var life := 2.5
var crit := false
var proc := 1.0
## A guest's copy: it draws the flight and touches nothing. The host owns every
## blow, and a visual that applied damage would double it on the wire.
var visual_only := false
## Called with `(target, is_kill)` after a blow lands, so the owner's runtime can
## book a kill without this node knowing what a kill worth.
var hit_callback: Callable = Callable()
## The target a homing blade was pointed at when it was spawned.
var homing_target: Node3D
var homing_turn := 0.0

var _age := 0.0
var _struck: Dictionary = {}
var _spin := 0.0
var _visual: Node3D
var _detonated := false
var _query := PhysicsRayQueryParameters3D.new()
var _explode_at := Vector3.ZERO


func _ready() -> void:
	_query.collision_mask = hit_mask
	_build_visual()


func launch(origin: Vector3, direction: Vector3, speed: float, shot_damage: float) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	damage = shot_damage
	if is_instance_valid(shooter):
		# The body that threw it is never the body it finds: its own capsule sits
		# around the spawn point, and a ray that names it would spend the proc on
		# the thrower's shin.
		var excluded: Array[RID] = [shooter.get_rid()]
		_query.exclude = excluded
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity.normalized(), Vector3.UP)


func _physics_process(delta: float) -> void:
	_age += delta
	match kind:
		"bomb":
			_tick_bomb(delta)
		"wave", "splinter":
			_tick_sweep(delta)
		_:
			_tick_blade(delta)
	if _age > life:
		queue_free()


# --- blade and splinter flight --------------------------------------------

func _tick_blade(delta: float) -> void:
	if kind == "dagger":
		_spin += 18.0 * delta
		if _visual != null:
			_visual.rotation.z = _spin
		if is_instance_valid(homing_target) and homing_turn > 0.0:
			var wanted: Vector3 = (homing_target.global_position + Vector3.UP * 1.1) - global_position
			if wanted.length_squared() > 0.04:
				velocity = velocity.lerp(wanted.normalized() * velocity.length(),
					clampf(homing_turn * delta, 0.0, 1.0))
	var next := global_position + velocity * delta + GRAVITY * (0.5 * delta * delta)
	if kind == "dagger":
		velocity += GRAVITY * delta
	_query.from = global_position
	_query.to = next
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = next
		return
	global_position = hit.position
	_apply(hit.collider, hit.position)
	queue_free()


## The crescent and the splinters sweep an area every frame rather than a ray:
## a wave is a wall of wind, not a line. Each body is struck once.
func _tick_sweep(delta: float) -> void:
	var next := global_position + velocity * delta
	global_position = next
	var reach := maxf(radius, 0.6)
	var shape := SphereShape3D.new()
	shape.radius = reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = hit_mask
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 16)
	for entry in hits:
		var collider = entry.get("collider")
		_apply(collider, global_position)
	if kind == "wave":
		_scale_wave(delta)


func _scale_wave(delta: float) -> void:
	if _visual == null:
		return
	var grow := 1.0 + _age * 2.4
	_visual.scale = Vector3(grow, 1.0, 1.0)
	if _visual is MeshInstance3D:
		(_visual as MeshInstance3D).transparency = clampf(_age / maxf(life, 0.01), 0.0, 1.0)


# --- the charge ------------------------------------------------------------

func _tick_bomb(delta: float) -> void:
	if _detonated:
		return
	if is_instance_valid(_visual):
		var pulse := 1.0 + sin(_age * 30.0) * 0.14
		_visual.scale = Vector3.ONE * pulse
	if _age >= delay:
		_detonate()


func _detonate() -> void:
	_detonated = true
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius, 1.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = hit_mask
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 24)
	for entry in hits:
		_apply(entry.get("collider"), global_position)
	_detonated_visual()
	# The flash is a tween on this node, so the charge stays long enough for it
	# to play out; `_physics_process` frees it on the extended clock.
	life = _age + 0.4


func _detonated_visual() -> void:
	var flash := Geo.sphere(self, maxf(radius, 1.0) * 0.5, Vector3.ZERO,
		Geo.material(Color(0.9, 0.18, 0.12), 0.0, 0.4))
	flash.name = "BombFlash"
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.22, 0.12)
	light.light_energy = 4.0
	light.omni_range = maxf(radius, 1.0) * 3.0
	add_child(light)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.4, 0.22)
	tween.tween_property(light, "light_energy", 0.0, 0.26)


# --- the blow --------------------------------------------------------------

func _apply(collider: Object, at: Vector3) -> void:
	if visual_only:
		return
	if collider == null or not (collider is Node):
		return
	var unit := collider as Node
	if not unit.has_method("take_damage"):
		return
	if unit == shooter:
		return
	var id := unit.get_instance_id()
	if _struck.has(id):
		return
	_struck[id] = true
	var applied := damage * (Hitbox.damage_multiplier(true) if crit else 1.0)
	if unit.has_method("note_attacker") and is_instance_valid(shooter):
		unit.note_attacker(shooter)
	if unit.has_method("note_impact"):
		unit.note_impact(velocity.normalized() * maxf(velocity.length(), 1.0) * 0.33)
	unit.take_damage(applied, source_id, false)
	BloodFx.impact(self, at, velocity.normalized(), applied, false)
	var died: bool = unit.get("alive") == false
	if hit_callback.is_valid():
		hit_callback.call(unit, died)
	if kind == "dagger":
		return
	if pierce > 0:
		pierce -= 1
		return
	if kind == "splinter":
		queue_free()


# --- looks -----------------------------------------------------------------

func _build_visual() -> void:
	match kind:
		"dagger":
			_visual = _make_dagger()
		"splinter":
			_visual = _make_splinter()
		"wave":
			_visual = _make_wave()
		"bomb":
			_visual = _make_bomb()
		_:
			_visual = _make_splinter()
	if _visual != null:
		add_child(_visual)


func _make_dagger() -> Node3D:
	var root := Node3D.new()
	root.name = "ProcDagger"
	var iron := Geo.material(Color(0.62, 0.65, 0.67), 0.55, 0.36)
	var hide := Geo.material(Color(0.26, 0.18, 0.12), 0.0, 0.9)
	var blade := Geo.box(root, Vector3(0.06, 0.012, 0.34), Vector3(0.0, 0.0, -0.17), iron)
	blade.name = "Blade"
	Geo.box(root, Vector3(0.05, 0.03, 0.12), Vector3(0.0, 0.0, 0.06), hide)
	var glow := Geo.sphere(root, 0.055, Vector3(0.0, 0.0, -0.33),
		Geo.material(Color(0.95, 0.36, 0.24), 0.0, 0.3))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _make_splinter() -> Node3D:
	var root := Node3D.new()
	root.name = "ProcSplinter"
	var bone := Geo.material(Color(0.86, 0.78, 0.64), 0.0, 0.55)
	var shaft := Geo.box(root, Vector3(0.028, 0.028, 0.42), Vector3(0.0, 0.0, -0.21), bone)
	return root


func _make_wave() -> Node3D:
	var root := Node3D.new()
	root.name = "ProcWave"
	var blood := Geo.material(Color(0.62, 0.10, 0.09), 0.0, 0.42)
	blood.emission_enabled = true
	blood.emission = Color(0.55, 0.06, 0.05)
	blood.emission_energy_multiplier = 1.4
	# A crescent built from three overlapping blades of wind: wide in the middle,
	# thinning to points at either end.
	var middle := Geo.box(root, Vector3(2.1, 0.16, 0.10), Vector3(0.0, 0.0, 0.0), blood)
	middle.name = "Wave"
	middle.rotation.x = 0.0
	for side in [-1.0, 1.0]:
		var tip := Geo.box(root, Vector3(0.9, 0.10, 0.08),
			Vector3(float(side) * 1.35, 0.0, 0.25), blood)
		tip.rotation.y = float(side) * 0.42
	return root


func _make_bomb() -> Node3D:
	var root := Node3D.new()
	root.name = "ProcBomb"
	var meat := Geo.material(Color(0.42, 0.06, 0.06), 0.0, 0.5)
	meat.emission_enabled = true
	meat.emission = Color(0.75, 0.10, 0.06)
	meat.emission_energy_multiplier = 2.2
	Geo.sphere(root, 0.20, Vector3.ZERO, meat)
	for index in 4:
		var spike := Geo.sphere(root, 0.07,
			Vector3(cos(TAU * index / 4.0) * 0.24, 0.06, sin(TAU * index / 4.0) * 0.24),
			meat)
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root
