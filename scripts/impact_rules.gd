extends RefCounted
## Pure attack-style knock direction for corpse physics.
##
## Every hit records a short horizontal force vector on the victim: a melee cut
## uses the victim's angle across the swing plus its authored style, arrows and
## thrown blades use their flight direction, and spells push away from the
## blast centre. Death reads that vector so the corpse falls along the blow
## rather than in a fixed direction.

const OVERHEAD_STRENGTH := 1.15
const DIAGONAL_STRENGTH := 1.0
const FORWARD_STRENGTH := 0.9
const PROJECTILE_STRENGTH := 0.65
const SPELL_STRENGTH := 0.9

## `origin` is the attacker, `forward`/`right` its horizontal aim frame and
## `contact` the point the blade reached. A rightward diagonal (side +1) pushes
## the victim along the blade's travel; a leftward diagonal mirrors it. Overhead
## and forward attacks push away from the attacker.
static func melee_force(origin: Vector3, forward: Vector3, right: Vector3,
		contact: Vector3, style: String, side: float) -> Vector3:
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() < 0.0001:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()
	var flat_right := Vector3(right.x, 0.0, right.z).normalized()
	if flat_right.length_squared() < 0.0001:
		flat_right = flat_forward.cross(Vector3.UP)
	var offset := Vector3(contact.x - origin.x, 0.0, contact.z - origin.z)
	if offset.length_squared() < 0.0001:
		offset = flat_forward
	var radial := offset.normalized()
	var angle := atan2(offset.dot(flat_right), offset.dot(flat_forward))
	match style:
		"diagonal_left", "diagonal_right":
			var tangent := flat_forward * sin(angle) - flat_right * cos(angle)
			var force := tangent * side + radial * 0.30
			return _finish(force, DIAGONAL_STRENGTH)
		"stab", "forward":
			return _finish(radial, FORWARD_STRENGTH)
		_:
			return _finish(radial, OVERHEAD_STRENGTH)


## A spell or radial skill: push the victim away from the blast/skill centre.
static func radial_force(origin: Vector3, target: Vector3,
		strength: float = SPELL_STRENGTH) -> Vector3:
	var offset := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	return _finish(offset, strength)


## Projectile flight direction, already horizontal.
static func projectile_force(direction: Vector3,
		strength: float = PROJECTILE_STRENGTH) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	return _finish(flat, strength)


static func _finish(force: Vector3, strength: float) -> Vector3:
	var flat := Vector3(force.x, 0.0, force.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	return flat.normalized() * maxf(strength, 0.0)
