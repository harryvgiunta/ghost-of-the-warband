extends RefCounted

const SHOULDER_OFFSET := 0.70
const SWAP_SPEED := 10.0
# Encloses the near-plane corners of both gameplay cameras (59 degrees, near 0.08).
const CAMERA_RADIUS := 0.22
const COLLISION_MARGIN := 0.01
const SEPARATION := 0.005
const RECOVERY_STEPS := 16

var side: int = 1
var _offset := SHOULDER_OFFSET
var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	_shape.radius = CAMERA_RADIUS
	_query.shape = _shape
	_query.collision_mask = 1
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	_query.margin = COLLISION_MARGIN

func swap() -> void:
	side = -side

func update(delta: float) -> void:
	# Keep the current offset when reversing an unfinished shoulder transition.
	_offset = lerpf(_offset, float(side) * SHOULDER_OFFSET, 1.0 - exp(-SWAP_SPEED * maxf(delta, 0.0)))

func resolve(space: PhysicsDirectSpaceState3D, focus: Vector3, back: Vector3, distance: float, centered: bool = false) -> Vector3:
	var rear := back.normalized()
	var right := Vector3(rear.z, 0.0, -rear.x).normalized()
	var destination := focus + rear * maxf(distance, 0.0)
	if not centered:
		destination += right * _offset
	# cast_motion ignores initial intersections. Recover the whole sphere first,
	# including when the focus is next to a wall or inside a low ceiling.
	var origin := _recover_overlap(space, focus)
	var motion := destination - origin
	if motion.is_zero_approx():
		return origin
	_query.transform = Transform3D(Basis.IDENTITY, origin)
	_query.motion = motion
	# Sweep the full diagonal, not just the rear boom after an unchecked offset.
	var fractions := space.cast_motion(_query)
	var fraction := fractions[0]
	if fraction < 1.0:
		fraction = maxf(0.0, fraction - SEPARATION / motion.length())
	return _recover_overlap(space, origin + motion * fraction)

func _recover_overlap(space: PhysicsDirectSpaceState3D, position_at: Vector3) -> Vector3:
	_query.motion = Vector3.ZERO
	for iteration in RECOVERY_STEPS:
		_query.transform = Transform3D(Basis.IDENTITY, position_at)
		var contacts := space.collide_shape(_query, 16)
		if contacts.is_empty():
			break
		var correction := Vector3.ZERO
		for index in range(0, contacts.size(), 2):
			# Pairs are query-surface then world-surface: their difference is
			# the minimum outward translation for this penetrating contact.
			var separation: Vector3 = contacts[index + 1] - contacts[index]
			var depth := separation.length()
			if depth <= 0.000001:
				continue
			var normal := separation / depth
			var remaining := depth + SEPARATION - correction.dot(normal)
			if remaining > 0.0:
				correction += normal * remaining
		if correction.is_zero_approx():
			break
		position_at += correction
	return position_at
