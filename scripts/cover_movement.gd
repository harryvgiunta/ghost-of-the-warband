extends Node
## Geometry-driven sticky cover. Only the owning physics controller moves the body.

const REACH := 1.35
const GAP := 0.42
const SPEED := 2.2
const FAST_SPEED := 4.2
const STANCE_SPEED := 6.0
const PROBE_HEIGHT := 0.65
const CROUCH_HEIGHT := 1.12
const STAND_HEIGHT := 1.8
const PEEK_DISTANCE := 0.45
const PEEK_EXTENTS := [PEEK_DISTANCE,0.55,0.65]
const FIRING_RADIUS := 0.05
var view_right := Vector3.RIGHT
var active := false
var normal := Vector3.ZERO
var low := false
var peeking := false
var lean := Vector3.ZERO
var crouch_requested := false
var crouched := false
var crouch_amount := 0.0
var _peek_offset := Vector3.ZERO
var _peek_side := 0
var _side_extents := Vector2(PEEK_DISTANCE,PEEK_DISTANCE)
var _side_lean := false
var _top_lean := false
var _body: CharacterBody3D
var _collider: CollisionShape3D
var _capsule: CapsuleShape3D
var _anchor := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _clearance := PhysicsShapeQueryParameters3D.new()
var _standing_shape := CapsuleShape3D.new()
var _firing_shape := SphereShape3D.new()
var _firing_query := PhysicsShapeQueryParameters3D.new()
var _capsule_query := PhysicsShapeQueryParameters3D.new()
var _walk_collision := KinematicCollision3D.new()
var _exclude: Array[RID] = []
var attached_rid := RID()

func setup(body: CharacterBody3D, collider: CollisionShape3D) -> void:
	_body = body
	_collider = collider
	_capsule = collider.shape as CapsuleShape3D
	_ray.collision_mask = 1
	_standing_shape.radius = _capsule.radius
	# Test only the added headroom, not the existing capsule against a sloping floor.
	_standing_shape.height = STAND_HEIGHT-CROUCH_HEIGHT+2.0*_capsule.radius
	_clearance.shape = _standing_shape
	_clearance.collision_mask = body.collision_mask
	_clearance.margin = 0.002
	_exclude.append(body.get_rid())
	_clearance.exclude = _exclude
	_ray.exclude = _exclude
	_firing_shape.radius = FIRING_RADIUS
	_firing_query.shape = _firing_shape
	_firing_query.collision_mask = 1
	_firing_query.margin = 0.002
	_firing_query.exclude = _exclude
	_capsule_query.shape = _capsule
	_capsule_query.collision_mask = 1
	_capsule_query.exclude = _exclude

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
	attached_rid = best.rid
	_anchor = best.position+normal*GAP-Vector3.UP*PROBE_HEIGHT
	var support := _support(_anchor)
	if support.is_empty():
		return false
	_anchor = _grounded_position(_anchor,support)
	# Entering cover follows the supported capsule path, including terrain rise.
	if not _walk_clear(_body.global_position,_anchor):
		return false
	active = true
	peeking = false
	low = _is_low_cover()
	crouched = low or crouch_requested
	return true

func exit() -> void:
	active = false
	attached_rid = RID()
	peeking = false
	lean = Vector3.ZERO
	_side_lean = false
	_top_lean = false
	low = false
	normal = Vector3.ZERO
	_peek_offset = Vector3.ZERO
	_peek_side = 0
	_side_extents = Vector2(PEEK_DISTANCE,PEEK_DISTANCE)

func prepare_jump() -> bool:
	if not _can_stand():
		return false
	reset()
	return true

func reset() -> void:
	exit()
	crouch_requested = false
	crouched = false
	crouch_amount = 0.0
	_apply_height()

## A skill that cannot be performed from a crouch stands the owner up. Clear the
## crouch intent and snap the capsule upright so the authored clip owns the whole
## body; refuse when the ceiling cannot take the standing capsule, so the caller
## can block the skill instead of playing it folded over.
func force_stand() -> bool:
	if not crouched and not crouch_requested and crouch_amount <= 0.0:
		return true
	if _body != null and not _can_stand():
		return false
	crouch_requested = false
	crouched = false
	crouch_amount = 0.0
	_apply_height()
	return true

func step(delta: float, desired_direction: Vector3, wants_peek: bool, shoulder: int, fast: bool = false) -> Vector3:
	if not active:
		_update_stance(delta,crouch_requested)
		return Vector3.ZERO
	if not _body.is_on_floor():
		exit()
		_update_stance(delta,crouch_requested)
		return Vector3.ZERO
	var support := _support(_anchor)
	if support.is_empty():
		exit()
		_update_stance(delta,crouch_requested)
		return Vector3.ZERO
	_anchor = _grounded_position(_anchor,support)
	var contact := _probe(_anchor,normal,PROBE_HEIGHT)
	if not _compatible_surface(contact,_anchor):
		exit()
		_update_stance(delta,crouch_requested)
		return Vector3.ZERO
	attached_rid = contact.rid
	var tangent := normal.cross(Vector3.UP)
	var travel := clampf(desired_direction.dot(tangent),-1.0,1.0)
	var speed := FAST_SPEED if fast else SPEED
	# Retucking keeps the protected anchor until the body actually returns, even
	# after release clears the requested destination. Low top peeks can still slide.
	if not _side_lean and absf(travel) > 0.01:
		var stride := tangent*travel*minf(speed*delta,0.12)
		var candidate := _anchor+stride
		var ahead := _probe(candidate+tangent*signf(travel)*0.16,normal,PROBE_HEIGHT)
		var next := _probe(candidate,normal,PROBE_HEIGHT)
		if _wall(ahead) and _flat_normal(ahead.normal).dot(normal) > 0.45 and _compatible_surface(next,candidate):
			var next_normal := _flat_normal(next.normal)
			var next_anchor: Vector3 = next.position+next_normal*GAP-Vector3.UP*PROBE_HEIGHT
			next_anchor.y = _anchor.y
			# A convex facet change can rotate the clearance normal abruptly. Follow
			# its offset surface at slide speed instead of teleporting or stopping at the seam.
			var blend := minf(1.0,stride.length()/maxf(next_anchor.distance_to(_anchor),0.000001))
			var contact_point := next_anchor-next_normal*GAP
			next_normal = normal.lerp(next_normal,blend).normalized()
			next_anchor = (_anchor-normal*GAP).lerp(contact_point,blend)+next_normal*GAP
			next_anchor = _anchor+(next_anchor-_anchor).limit_length(stride.length())
			if _walk_clear(_anchor,next_anchor):
				_anchor = next_anchor
				_peek_offset = Vector3.ZERO
				_peek_side = 0
				normal = next_normal
				tangent = normal.cross(Vector3.UP)
	low = _is_low_cover()
	# Keep the selected endpoint through holding and retuck. A same-side request
	# validates that endpoint rather than switching to a longer candidate mid-peek.
	var side_allowed := false
	if wants_peek and not low and shoulder in [-1,1]:
		if _peek_offset.is_zero_approx() or _peek_side != shoulder:
			var selected := _find_peek_offset(shoulder)
			if not selected.is_zero_approx():
				_peek_offset = selected
				_peek_side = shoulder
				_side_extents[0 if shoulder < 0 else 1] = Vector2(selected.x,selected.z).length()
				_side_lean = true
		if _peek_side == shoulder and not _peek_offset.is_zero_approx():
			side_allowed = _peek_destination_clear(_peek_offset)
			if side_allowed:
				_side_lean = true
	var wants_crouch := crouch_requested or low
	if low and wants_peek:
		wants_crouch = false
	_update_stance(delta,wants_crouch)
	if low:
		_peek_offset = Vector3.ZERO
		_peek_side = 0
		_side_lean = false
		_top_lean = _top_lean or (wants_peek and not crouched)
		lean = Vector3.UP*(1.0-crouch_amount) if _top_lean else Vector3.ZERO
		if crouch_amount >= 1.0:
			_top_lean = false
	else:
		_top_lean = false
		# Sample the moved capsule, never the requested peek destination. The
		# signed displacement also preserves the old side during a shoulder swap.
		var displacement := (_body.global_position-_anchor).dot(tangent)
		var extent := _side_extents[0 if displacement < 0.0 else 1]
		var side_fraction := clampf(displacement/extent,-1.0,1.0)
		lean = tangent*side_fraction if _side_lean else Vector3.ZERO
		if not side_allowed and absf(displacement) < 0.02:
			_side_lean = false
			lean = Vector3.ZERO
			if not wants_peek or _peek_side != shoulder:
				_peek_offset = Vector3.ZERO
				_peek_side = 0
	var offset := _anchor+(_peek_offset if side_allowed else Vector3.ZERO)-_body.global_position
	offset.y = 0.0
	var exposed := not crouched and crouch_amount < 0.05 if low else side_allowed
	var tolerance := 0.15 if low else 0.02
	peeking = wants_peek and exposed and offset.length_squared() < tolerance*tolerance
	return (offset/maxf(delta,0.0001)).limit_length(maxf(speed,3.5) if wants_peek and not low else speed)

func can_peek(side: int) -> bool:
	if not active or not _body.is_on_floor() or side not in [-1,1]:
		return false
	if low:
		return _can_stand()
	if _peek_side == side and not _peek_offset.is_zero_approx():
		return _peek_destination_clear(_peek_offset)
	return not _find_peek_offset(side).is_zero_approx()

func _find_peek_offset(side: int) -> Vector3:
	var tangent := normal.cross(Vector3.UP)*float(side)
	for extent in PEEK_EXTENTS:
		var offset: Vector3 = tangent*extent
		if _peek_destination_clear(offset):
			return offset
	return Vector3.ZERO

func _peek_destination_clear(offset: Vector3) -> bool:
	var outside := _anchor+offset
	var support := _support(outside)
	if support.is_empty():
		return false
	outside = _grounded_position(outside,support)
	if not _walk_clear(_anchor,outside):
		return false
	# Revalidate the actual side-swap path as well as the protected approach.
	# Ground projection removes ordinary floor-recovery depth, not obstacles.
	if not _walk_clear(_body.global_position,outside):
		return false
	var height := lerpf(1.4,0.78,crouch_amount)
	# A requested crouch must be safe at its final firing height too, before
	# its physical capsule has finished shrinking.
	if crouch_requested or crouched:
		height = 0.78
	return _firing_corridor_clear(outside,height,Vector3.UP.cross(view_right).normalized())

func _is_low_cover() -> bool:
	# Classify the obstacle itself, not whichever direction free look happens to face.
	# A short probe alone misses convex cover rising farther behind its front face.
	return _probe(_anchor,normal,1.55).is_empty() and _firing_corridor_clear(_anchor,1.55,-normal)

func _firing_corridor_clear(point: Vector3, height: float, forward: Vector3) -> bool:
	if forward.is_zero_approx():
		return false
	_firing_query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*height)
	_firing_query.motion = Vector3.ZERO
	var space := _body.get_world_3d().direct_space_state
	# cast_motion deliberately ignores initial overlaps; reject those explicitly.
	if not space.intersect_shape(_firing_query,1).is_empty():
		return false
	_firing_query.motion = forward*(REACH+GAP)
	var fractions := space.cast_motion(_firing_query)
	return fractions.size() == 2 and fractions[0] >= 1.0

func camera_height() -> float:
	return lerpf(1.5,0.95,crouch_amount)

func snapshot() -> Dictionary:
	return {"active":active,"normal":normal,"low":low,"peeking":peeking,"lean":lean,
		"crouch_requested":crouch_requested,"crouched":crouched,"crouch_amount":crouch_amount}

func apply_snapshot(state: Dictionary) -> void:
	active = bool(state.active)
	normal = state.normal
	low = bool(state.low)
	peeking = bool(state.peeking)
	lean = state.lean
	crouch_requested = bool(state.crouch_requested)
	crouched = bool(state.crouched)
	crouch_amount = float(state.crouch_amount)
	_apply_height()

func _update_stance(delta: float, wants_crouch: bool) -> void:
	crouched = wants_crouch or not _can_stand()
	crouch_amount = move_toward(crouch_amount,1.0 if crouched else 0.0,STANCE_SPEED*delta)
	_apply_height()

func _apply_height() -> void:
	var height := lerpf(STAND_HEIGHT,CROUCH_HEIGHT,crouch_amount)
	if not is_equal_approx(_capsule.height,height):
		_capsule.height = height
		_collider.position.y = height*0.5

func _can_stand() -> bool:
	_clearance.transform = Transform3D(Basis.IDENTITY,_body.global_position+Vector3.UP*((STAND_HEIGHT+CROUCH_HEIGHT)*0.5-_capsule.radius))
	return _body.get_world_3d().direct_space_state.intersect_shape(_clearance,1).is_empty()

# The surface the body is attached to, including on replicated actors whose
# collision-driven steps run on the host. Aim queries skip only this body,
# never whatever the weapon pose happens to project past.
func attached_surface() -> RID:
	if not active:
		return RID()
	if attached_rid.is_valid():
		return attached_rid
	var from := _body.global_position-normal*(GAP*0.5)+Vector3.UP*PROBE_HEIGHT
	_ray.from = from
	_ray.to = from-normal*(REACH+GAP)
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(_ray)
	return hit.rid if not hit.is_empty() else RID()

func _probe(point: Vector3, outward: Vector3, height: float) -> Dictionary:
	_ray.from = point+Vector3.UP*height+outward*0.10
	_ray.to = point+Vector3.UP*height-outward*(GAP+0.3)
	return _body.get_world_3d().direct_space_state.intersect_ray(_ray)

func _supported(point: Vector3) -> bool:
	return not _support(point).is_empty()

func _support(point: Vector3) -> Dictionary:
	_ray.from = point+Vector3.UP*0.3
	_ray.to = point-Vector3.UP*0.65
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty() or hit.normal.y < cos(_body.floor_max_angle):
		return {}
	return hit

func _grounded_position(point: Vector3, support: Dictionary) -> Vector3:
	# The bottom hemisphere's center must be radius/normal.y above a slope.
	# A root placed directly on the ray hit embeds the capsule into uphill ground.
	point.y = support.position.y+_capsule.radius*(1.0/support.normal.y-1.0)+2.0*_body.safe_margin
	return point

func _capsule_clear_at(pose: Transform3D) -> bool:
	_capsule_query.transform = pose*_collider.transform
	return _body.get_world_3d().direct_space_state.intersect_shape(_capsule_query,1).is_empty()

func _walk_clear(start: Vector3, destination: Vector3) -> bool:
	var start_support := _support(start)
	var end_support := _support(destination)
	if start_support.is_empty() or end_support.is_empty():
		return false
	var pose := _body.global_transform
	pose.origin = _grounded_position(start,start_support)
	destination = _grounded_position(destination,end_support)
	if not _capsule_clear_at(pose):
		return false
	var end_pose := pose
	end_pose.origin = destination
	if not _capsule_clear_at(end_pose):
		return false
	var motion := destination-pose.origin
	# Match walkable-floor sliding instead of rejecting any terrain contact.
	# Every continued segment still sweeps the entire capsule against the world;
	# walls, steps above the floor angle, roofs and neighboring cover block it.
	for iteration in 4:
		if motion.length_squared() < 0.000001:
			return true
		if not _body.test_move(pose,motion,_walk_collision,_body.safe_margin,true,4):
			return true
		pose.origin += _walk_collision.get_travel()
		motion = _walk_collision.get_remainder()
		for index in _walk_collision.get_collision_count():
			var floor_normal := _walk_collision.get_normal(index)
			if floor_normal.y < cos(_body.floor_max_angle):
				return false
			motion = motion.slide(floor_normal)
	return Vector2(pose.origin.x-destination.x,pose.origin.z-destination.z).length_squared() < 0.0004

func _wall(hit: Dictionary) -> bool:
	return not hit.is_empty() and absf(hit.normal.y) < 0.45

func _compatible_surface(hit: Dictionary, point: Vector3) -> bool:
	if not _wall(hit) or _flat_normal(hit.normal).dot(normal) <= 0.45:
		return false
	# Follow contiguous faces, even when a batched/compound collider changes
	# shape or RID. Bound the gap as well as the normal; a nearby disconnected
	# surface cannot pull the anchor across free space.
	var gap: float = (point+Vector3.UP*PROBE_HEIGHT-hit.position).dot(normal)
	return absf(gap-GAP) <= 0.18

func _flat_normal(value: Vector3) -> Vector3:
	return Vector3(value.x,0,value.z).normalized()
