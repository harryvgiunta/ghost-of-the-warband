extends Node
## Geometry-driven sticky cover. Only the owning physics controller moves the body.

const REACH := 1.35
const GAP := 0.42
const SPEED := 2.2
const PROBE_HEIGHT := 0.65
const CROUCH_HEIGHT := 1.12
const STAND_HEIGHT := 1.8
const PEEK_DISTANCE := 0.72
var active := false
var normal := Vector3.ZERO
var low := false
var peeking := false
var _body: CharacterBody3D
var _collider: CollisionShape3D
var _capsule: CapsuleShape3D
var _anchor := Vector3.ZERO
var _surface := RID()
var _surface_shape := -1
var _ray := PhysicsRayQueryParameters3D.new()
var _clearance := PhysicsShapeQueryParameters3D.new()
var _standing_shape := CapsuleShape3D.new()
var _exclude: Array[RID] = []

func setup(body: CharacterBody3D, collider: CollisionShape3D) -> void:
	_body = body
	_collider = collider
	_capsule = collider.shape as CapsuleShape3D
	_ray.collision_mask = 1
	_standing_shape.radius = _capsule.radius
	_standing_shape.height = STAND_HEIGHT
	_clearance.shape = _standing_shape
	_clearance.collision_mask = body.collision_mask
	_clearance.margin = 0.002
	_exclude.append(body.get_rid())
	_clearance.exclude = _exclude

func try_enter(preferred_direction: Vector3) -> bool:
	if active or not _body.is_on_floor():
		return false
	var forward := Vector3(preferred_direction.x,0,preferred_direction.z).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var best: Dictionary = {}
	var best_score := INF
	var space := _body.get_world_3d().direct_space_state
	# Nearby sides remain usable when looking away; the view breaks distance ties.
	for index in 16:
		var direction := forward.rotated(Vector3.UP,float(index)*TAU/16.0)
		_ray.from = _body.global_position+Vector3.UP*PROBE_HEIGHT
		_ray.to = _ray.from+direction*REACH
		var hit := space.intersect_ray(_ray)
		if not _wall(hit):
			continue
		var score: float = _ray.from.distance_to(hit.position)+0.25*(1.0-direction.dot(forward))
		if score < best_score:
			best = hit
			best_score = score
	if best.is_empty():
		return false
	normal = _flat_normal(best.normal)
	_anchor = best.position+normal*GAP-Vector3.UP*PROBE_HEIGHT
	_anchor.y = _body.global_position.y
	if not _supported(_anchor):
		return false
	var approach := _anchor-_body.global_position
	# Entering cover is a swept approach, not a teleport through another obstacle.
	if _body.test_move(_body.global_transform,approach):
		return false
	_surface = best.rid
	_surface_shape = int(best.shape)
	active = true
	peeking = false
	low = _probe(_anchor,normal,1.55).is_empty()
	_set_crouched(low)
	return true

func exit() -> void:
	active = false
	peeking = false
	low = false
	normal = Vector3.ZERO
	_surface = RID()
	_surface_shape = -1
	_set_crouched(false)

func step(delta: float, desired_direction: Vector3, wants_peek: bool, shoulder: int) -> Vector3:
	if not active:
		return Vector3.ZERO
	if not _body.is_on_floor():
		exit()
		return Vector3.ZERO
	_anchor.y = _body.global_position.y
	var contact := _probe(_anchor,normal,PROBE_HEIGHT)
	if not _same_surface(contact):
		exit()
		return Vector3.ZERO
	normal = _flat_normal(contact.normal)
	var tangent := normal.cross(Vector3.UP)
	var travel := clampf(desired_direction.dot(tangent),-1.0,1.0)
	# Move the protected anchor only while tucked in; peeking never walks off an edge.
	if not wants_peek and absf(travel) > 0.01:
		var stride := tangent*travel*minf(SPEED*delta,0.12)
		var candidate := _anchor+stride
		var ahead := _probe(candidate+tangent*signf(travel)*0.16,normal,PROBE_HEIGHT)
		var next := _probe(candidate,normal,PROBE_HEIGHT)
		if _same_surface(ahead) and _same_surface(next):
			var next_normal := _flat_normal(next.normal)
			var target: Vector3 = next.position+next_normal*GAP-Vector3.UP*PROBE_HEIGHT
			target.y = _anchor.y
			var pose := _body.global_transform
			pose.origin = _anchor
			if _supported(target) and not _body.test_move(pose,target-_anchor):
				_anchor = target
				normal = next_normal
				tangent = normal.cross(Vector3.UP)
	low = _probe(_anchor,normal,1.55).is_empty()
	var target := _anchor
	var exposed := false
	if wants_peek:
		if low:
			exposed = _can_stand()
		else:
			var side := tangent*float(shoulder)
			var edge := _probe(_anchor+side*PEEK_DISTANCE,normal,PROBE_HEIGHT)
			if edge.is_empty():
				var outside := _anchor+side*PEEK_DISTANCE
				var pose := _body.global_transform
				pose.origin = _anchor
				if _supported(outside) and not _body.test_move(pose,outside-_anchor):
					target = outside
					exposed = true
	_set_crouched(low and not exposed)
	var offset := target-_body.global_position
	offset.y = 0.0
	# An attack is allowed only once the real body reaches the exposed position.
	peeking = exposed and offset.length_squared() < 0.0225
	return (offset/maxf(delta,0.0001)).limit_length(SPEED if not wants_peek else 3.5)

func camera_height() -> float:
	return 0.95 if active and low and not peeking else 1.5

func snapshot() -> Dictionary:
	return {"active":active,"normal":normal,"low":low,"peeking":peeking}

func apply_snapshot(state: Dictionary) -> void:
	active = bool(state.active)
	normal = state.normal
	low = bool(state.low)
	peeking = bool(state.peeking)
	_set_crouched(active and low and not peeking)

func _set_crouched(crouched: bool) -> void:
	var height := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	if not is_equal_approx(_capsule.height,height):
		_capsule.height = height
		_collider.position.y = height*0.5

func _can_stand() -> bool:
	_clearance.transform = Transform3D(Basis.IDENTITY,_body.global_position+Vector3.UP*(STAND_HEIGHT*0.5+0.015))
	return _body.get_world_3d().direct_space_state.intersect_shape(_clearance,1).is_empty()

func _probe(point: Vector3, outward: Vector3, height: float) -> Dictionary:
	_ray.from = point+Vector3.UP*height+outward*0.10
	_ray.to = point+Vector3.UP*height-outward*(GAP+0.3)
	return _body.get_world_3d().direct_space_state.intersect_ray(_ray)

func _supported(point: Vector3) -> bool:
	_ray.from = point+Vector3.UP*0.3
	_ray.to = point-Vector3.UP*0.65
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(_ray)
	return not hit.is_empty() and hit.normal.y > 0.65

func _wall(hit: Dictionary) -> bool:
	return not hit.is_empty() and absf(hit.normal.y) < 0.45

func _same_surface(hit: Dictionary) -> bool:
	return _wall(hit) and hit.rid == _surface and int(hit.shape) == _surface_shape \
		and _flat_normal(hit.normal).dot(normal) > 0.65

func _flat_normal(value: Vector3) -> Vector3:
	return Vector3(value.x,0,value.z).normalized()
