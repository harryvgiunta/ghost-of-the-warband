extends RefCounted
## Backstab: blink behind the aimed body and drive a dagger into its back.
##
## Every entry point is scene-agnostic and duck-typed, so the same module works
## on a plain frontier mob and on an arena or delve fighter. The owning scene
## keeps the ability definition, its cues, stamina and smoke: this file only
## answers "who is under the crosshair", "where is their back", "move there"
## and "land the blow".
##
## The strike deliberately bypasses `receive_melee`: a backstab is the answer
## to a raised front guard, so the target's block, parry and clash rules are
## not consulted. Armor, damage numbers, body blood and death handling still
## live in the target's own `take_damage`.

const ImpactRules = preload("res://scripts/impact_rules.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")

## Sphere around the crosshair contact that captures the body under it.
const TARGET_SPHERE_RADIUS := 0.85
## The shooter's chest, used as the sight-ray origin.
const CHEST_HEIGHT := 1.4
## A standing body must fit at the landing spot.
const STAND_RADIUS := 0.32
const STAND_HEIGHT := 1.6
const GROUND_MASK := 1
## Floors, not walls: the downward ray must land on a walkable face.
const FLOOR_DOT := 0.7
const BEHIND_LIFT := 0.08
const MAX_LATERAL := 0.35
## Distances tried in order; the caller's preference is tried first.
const BEHIND_DISTANCES := [1.0, 1.2, 1.4, 0.85]
const BEHIND_LATERALS := [0.0, 0.18, -0.18, MAX_LATERAL, -MAX_LATERAL]
const STAGGER_SECONDS := 0.35
const AIM_HEIGHT := 1.2

static var _sphere_shape: SphereShape3D
static var _stand_shape: CapsuleShape3D
static var _shape_query: PhysicsShapeQueryParameters3D
static var _ray_query: PhysicsRayQueryParameters3D
static var _empty_exclude: Array[RID] = []

# --- targeting -------------------------------------------------------------

## The body under `aim_point`, or the first damageable body on the actor's
## crosshair ray. `exclude` must carry the actor's own RID (and anything else
## that must never be selected, such as a held target). Returns null when
## nothing valid is inside `max_range` with a clear line of sight.
static func find_target(space: PhysicsDirectSpaceState3D,
		actor_position: Vector3, aim_point: Vector3, mask: int,
		max_range: float, exclude: Array[RID]) -> Node3D:
	if space == null or mask == 0 or max_range <= 0.0:
		return null
	var query := _shape_query_for(_sphere(), aim_point, mask, exclude)
	var hits := space.intersect_shape(query, 16)
	var best: Node3D = null
	var best_distance := INF
	var seen: Array[RID] = []
	for sphere_hit in hits:
		var hit_rid: RID = sphere_hit.get("rid", RID())
		if seen.has(hit_rid):
			continue
		seen.append(hit_rid)
		var hit_unit: Node3D = sphere_hit.get("collider") as Node3D
		if not _valid_target(hit_unit, hit_rid, actor_position, max_range, exclude):
			continue
		if not _sight_clear(space, actor_position, _aim_of(hit_unit), exclude):
			continue
		var distance := actor_position.distance_to(hit_unit.global_position)
		if distance < best_distance:
			best_distance = distance
			best = hit_unit
	if best != null:
		return best
	# The sphere missed (a thin or low body under a distant crosshair point):
	# fall back to the first body the aim ray actually crosses.
	var from := actor_position + Vector3.UP * CHEST_HEIGHT
	var direction := aim_point - from
	if direction.length_squared() < 0.000001:
		return null
	direction = direction.normalized()
	var ray := _ray_for(from, aim_point + direction * 0.35, mask, exclude)
	var ray_hit := space.intersect_ray(ray)
	if ray_hit.is_empty():
		return null
	var ray_rid: RID = ray_hit.get("rid", RID())
	var ray_unit: Node3D = ray_hit.get("collider") as Node3D
	if not _valid_target(ray_unit, ray_rid, actor_position, max_range, exclude):
		return null
	if not _sight_clear(space, actor_position, _aim_of(ray_unit), exclude):
		return null
	return ray_unit

# --- landing spot ----------------------------------------------------------

## A clear patch of ground directly behind `target`, lifted onto the floor and
## turned to face the back it belongs to. `ok` is false when no distance or
## lateral offset has standing clearance.
static func behind_spot(space: PhysicsDirectSpaceState3D, target: Node3D,
		preferred_distance: float = 1.0) -> Dictionary:
	if space == null or not is_instance_valid(target) or not target.is_inside_tree():
		return _no_spot()
	var forward := _facing_forward(target)
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		return _no_spot()
	right = right.normalized()
	var target_position := target.global_position
	var exclude: Array[RID] = []
	var body := target as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	var distances: Array[float] = []
	for candidate in [preferred_distance, BEHIND_DISTANCES[0], BEHIND_DISTANCES[1],
			BEHIND_DISTANCES[2], BEHIND_DISTANCES[3]]:
		var distance := clampf(float(candidate), 0.45, 2.5)
		if not distances.has(distance):
			distances.append(distance)
	for distance in distances:
		for lateral in BEHIND_LATERALS:
			var spot := target_position - forward * distance + right * float(lateral)
			var ground := _ground(space, spot)
			if ground.is_empty():
				continue
			var normal: Vector3 = ground.get("normal", Vector3.UP)
			if normal.y < FLOOR_DOT:
				continue
			var ground_position: Vector3 = ground.get("position", spot)
			var point: Vector3 = ground_position + Vector3.UP * BEHIND_LIFT
			if not _standing_clear(space, point, exclude):
				continue
			var to_target := target_position - point
			to_target.y = 0.0
			if to_target.length_squared() < 0.000001:
				continue
			to_target = to_target.normalized()
			return {"ok": true, "position": point,
				"yaw": atan2(-to_target.x, -to_target.z)}
	return _no_spot()

# --- movement --------------------------------------------------------------

## Instant, authoritative repositioning. Arena fighters own the authority check
## inside `teleport_to`; a plain CharacterBody3D is moved directly. The rig
## faces `yaw` in both cases and any raised guard or running swing is dropped.
static func blink(actor: Node3D, point: Vector3, yaw: float) -> void:
	if not is_instance_valid(actor):
		return
	_stop_combat(actor)
	if actor.has_method("teleport_to"):
		actor.teleport_to(point, yaw)
	else:
		if actor.is_inside_tree():
			actor.global_position = point
		else:
			actor.position = point
		var velocity_value: Variant = actor.get("velocity")
		if velocity_value is Vector3:
			var planar := Vector3(velocity_value)
			actor.set("velocity", Vector3(0.0, planar.y, 0.0))
		actor.global_basis = Basis(Vector3.UP, yaw)
	var rig := _rig_of(actor)
	if rig != null:
		rig.global_basis = Basis(Vector3.UP, yaw)

# --- damage ----------------------------------------------------------------

## The stab itself. Guards are ignored by construction: the target's
## `take_damage` is called directly, never `receive_melee`. Returns the health
## actually removed (armor included), or 0.0 when nothing was applied.
static func strike(actor: Node3D, target: Node3D, damage: float,
		source_id: int) -> float:
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return 0.0
	if damage <= 0.0 or not target.has_method("take_damage"):
		return 0.0
	if _is_dead(target):
		return 0.0
	var before: Variant = _health_of(target)
	if target.has_method("note_impact"):
		target.note_impact(ImpactRules.radial_force(actor.global_position, target.global_position))
	target.take_damage(damage, source_id, false)
	var applied := damage
	var after: Variant = _health_of(target)
	if before != null and after != null:
		applied = maxf(0.0, float(before) - float(after))
	if applied <= 0.0:
		return 0.0
	if target.has_method("stagger"):
		target.stagger(STAGGER_SECONDS)
	else:
		var target_combat: Variant = target.get("combat")
		if target_combat != null and is_instance_valid(target_combat) \
				and target_combat.has_method("stagger"):
			target_combat.stagger(STAGGER_SECONDS)
	var at := _aim_of(target)
	BloodFx.impact(actor, at, at - actor.global_position, applied, false)
	var rig := _rig_of(actor)
	if rig != null:
		BloodFx.stain_weapon(rig, applied)
	return applied

# --- helpers ---------------------------------------------------------------

static func _valid_target(unit: Node3D, rid: RID, actor_position: Vector3,
		max_range: float, exclude: Array[RID]) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if exclude.has(rid):
		return false
	if not unit.has_method("take_damage"):
		return false
	if unit.has_method("is_shield") and bool(unit.is_shield()):
		return false
	if _is_dead(unit):
		return false
	return actor_position.distance_to(unit.global_position) <= max_range

static func _sight_clear(space: PhysicsDirectSpaceState3D,
		actor_position: Vector3, target_position: Vector3,
		exclude: Array[RID]) -> bool:
	var from := actor_position + Vector3.UP * CHEST_HEIGHT
	var ray := _ray_for(from, target_position, GROUND_MASK, exclude)
	return space.intersect_ray(ray).is_empty()

static func _ground(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var from := point + Vector3.UP * 1.5
	var to := point - Vector3.UP * 3.5
	return space.intersect_ray(_ray_for(from, to, GROUND_MASK, _empty_exclude))

static func _standing_clear(space: PhysicsDirectSpaceState3D, point: Vector3,
		exclude: Array[RID]) -> bool:
	var query := _shape_query_for(_stand(), point + Vector3.UP * (STAND_HEIGHT * 0.5),
		GROUND_MASK, exclude)
	return space.intersect_shape(query, 1).is_empty()

## A fighter keeps its facing on the rig, not on the collision body (arena and
## delve actors never rotate their root). A plain mob rotates its own body and
## has no rig, so both duck-typed paths end at the same forward.
static func _facing_forward(target: Node3D) -> Vector3:
	var rig: Variant = target.get("rig")
	if rig is Node3D and is_instance_valid(rig):
		var rig_forward: Vector3 = -(rig as Node3D).global_basis.z
		rig_forward.y = 0.0
		if rig_forward.length_squared() > 0.000001:
			return rig_forward.normalized()
	var forward := -target.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.000001:
		return forward.normalized()
	return Vector3.FORWARD

static func _aim_of(unit: Node3D) -> Vector3:
	if unit.has_method("get_aim_position"):
		var at: Variant = unit.get_aim_position()
		if at is Vector3:
			return Vector3(at)
	return unit.global_position + Vector3.UP * AIM_HEIGHT

static func _health_of(unit: Node) -> Variant:
	var value: Variant = unit.get("health")
	if value is float or value is int:
		return float(value)
	return null

static func _is_dead(unit: Node) -> bool:
	var alive_value: Variant = unit.get("alive")
	if alive_value != null:
		return not bool(alive_value)
	var health: Variant = _health_of(unit)
	return health != null and float(health) <= 0.0

## Drops the guard and any recorded melee swing without cancelling an active
## ability pose: the backstab itself is already running on the rig.
static func _stop_combat(actor: Node) -> void:
	var combat: Variant = actor.get("combat")
	if combat == null or not is_instance_valid(combat):
		return
	if combat.has_method("stop_block"):
		combat.stop_block()
	if combat.has_method("abort_melee_to_neutral"):
		combat.abort_melee_to_neutral()
	elif combat.has_method("stop"):
		combat.stop()

static func _rig_of(actor: Node) -> Node3D:
	if not is_instance_valid(actor):
		return null
	for field_name in ["rig", "archer"]:
		var candidate: Variant = actor.get(field_name)
		if candidate is Node3D and is_instance_valid(candidate):
			return candidate as Node3D
	# A plain CharacterBody3D keeps its rig as an unnamed child.
	for child in actor.get_children():
		if child is Node3D and child.has_method("blood_weapon_anchor"):
			return child
	return null

static func _no_spot() -> Dictionary:
	return {"ok": false, "position": Vector3.ZERO, "yaw": 0.0}

static func _sphere() -> SphereShape3D:
	if _sphere_shape == null:
		_sphere_shape = SphereShape3D.new()
		_sphere_shape.radius = TARGET_SPHERE_RADIUS
	return _sphere_shape

static func _stand() -> CapsuleShape3D:
	if _stand_shape == null:
		_stand_shape = CapsuleShape3D.new()
		_stand_shape.radius = STAND_RADIUS
		_stand_shape.height = STAND_HEIGHT
	return _stand_shape

static func _shape_query_for(shape: Shape3D, at: Vector3, mask: int,
		exclude: Array[RID]) -> PhysicsShapeQueryParameters3D:
	if _shape_query == null:
		_shape_query = PhysicsShapeQueryParameters3D.new()
		_shape_query.collide_with_areas = false
		_shape_query.collide_with_bodies = true
	_shape_query.shape = shape
	_shape_query.transform = Transform3D(Basis.IDENTITY, at)
	_shape_query.motion = Vector3.ZERO
	_shape_query.collision_mask = mask
	_shape_query.exclude = exclude
	return _shape_query

static func _ray_for(from: Vector3, to: Vector3, mask: int,
		exclude: Array[RID]) -> PhysicsRayQueryParameters3D:
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters3D.new()
		_ray_query.collide_with_areas = false
		_ray_query.collide_with_bodies = true
	_ray_query.from = from
	_ray_query.to = to
	_ray_query.collision_mask = mask
	_ray_query.exclude = exclude
	return _ray_query
