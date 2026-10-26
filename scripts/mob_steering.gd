extends RefCounted
## Lightweight obstacle avoidance shared by every wilderness body.
##
## A mob does not path around a building: it walks at its quarry, probes the
## lane a couple of metres ahead and, when the lane is blocked, commits to a
## side and follows the obstruction's surface until it reopens. The chosen side
## is remembered for `HOLD_SECONDS`, so a body never oscillates between two
## equally good gaps, and real movement is measured every tick: a body that
## wants to move and does not is stuck, so the side flips and the probe widens.
##
## This is steering, not navigation: no mesh, no grid, no allocation per tick.
## Senses, damage and state machines stay in the owning mob.

## How far ahead the lane is probed.
const PROBE := 2.1
## The longer lane a stuck body re-probes with.
const WIDE_PROBE := 2.9
## The fan of detour headings, in degrees off the desired one.
const FAN_DEGREES := [30.0, 60.0, 90.0, 120.0, 150.0]
## How long a chosen detour side survives before it is reconsidered.
const HOLD_SECONDS := 1.1
## A body slower than this while it wants to move is not moving.
const STUCK_SPEED := 0.30
## How long that has to last before the detour side flips.
const STUCK_SECONDS := 0.55
## The second, higher sample that catches a waist-high barrier.
const UPPER_LIFT := 0.55

## The side of the last detour: -1 left, +1 right, 0 undecided.
var side := 0.0
## The side a fresh detour starts on; the owner seeds it so a pack splits.
var bias := 1.0

var _hold := 0.0
var _stuck := 0.0
## The detour heading that worked last time, re-validated with one ray before
## the whole fan is searched again.
var _heading := Vector3.ZERO
var _last := Vector3.ZERO
var _tracked := false
var _moving := false
var _query := PhysicsRayQueryParameters3D.new()


func _init(mask: int = 1) -> void:
	_query.collision_mask = mask


func reset() -> void:
	side = 0.0
	_heading = Vector3.ZERO
	_hold = 0.0
	_stuck = 0.0
	_tracked = false
	_moving = false


## The heading to walk this tick: `desired` when its lane is clear, otherwise
## the nearest clear heading on the committed side. `probe_height` is where the
## body samples the lane (roughly its chest).
func steer(owner: Node3D, desired: Vector3, probe_height: float) -> Vector3:
	var delta := _tick_delta(owner)
	_measure_progress(owner, delta)
	var planar := Vector3(desired.x, 0.0, desired.z)
	if planar.length_squared() < 0.0001:
		_moving = false
		return Vector3.ZERO
	planar = planar.normalized()
	if _stuck >= STUCK_SECONDS:
		# Pinned against something the fan could not see: give up on this side.
		side = -side if side != 0.0 else bias
		_hold = HOLD_SECONDS
		_stuck = 0.0
	_hold = maxf(0.0, _hold - delta)
	if _hold <= 0.0:
		side = 0.0
	_moving = true
	var lane := PROBE if _stuck <= 0.0 else WIDE_PROBE
	# The straight lane first: two rays, the common case.
	if _clear(owner, planar, probe_height, lane, true):
		_heading = Vector3.ZERO
		return planar
	# Then the detour that worked on the last tick: one ray instead of a fan.
	if _heading.length_squared() > 0.0001 and _clear(owner, _heading, probe_height, lane, false):
		return _heading
	if side == 0.0:
		side = bias
		_hold = HOLD_SECONDS
	# Prefer the committed side, then the mirror, then the next wider heading.
	# Fan candidates test one band only: the chest lane already showed whether
	# a wall is there, and a low barrier is caught by the straight check above.
	for angle in FAN_DEGREES:
		for signed in [side, -side]:
			var candidate := planar.rotated(Vector3.UP, float(signed) * deg_to_rad(float(angle)))
			if _clear(owner, candidate, probe_height, lane, false):
				_heading = candidate
				_hold = HOLD_SECONDS
				return candidate
	# Nothing in the fan is clear: slide along the widest heading and let the
	# stuck detector widen the search on the next tick.
	_hold = HOLD_SECONDS
	_heading = planar.rotated(Vector3.UP, side * deg_to_rad(float(FAN_DEGREES[FAN_DEGREES.size() - 1])))
	return _heading


func _tick_delta(owner: Node3D) -> float:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return 1.0 / 60.0
	return maxf(float(owner.get_physics_process_delta_time()), 0.0001)


## Real travel since the previous tick, not intent: a body held by a wall
## reports (almost) none whatever it asked for.
func _measure_progress(owner: Node3D, delta: float) -> void:
	if not is_instance_valid(owner):
		return
	if _tracked and _moving:
		var travel := Vector2(owner.global_position.x - _last.x,
			owner.global_position.z - _last.z).length() / delta
		if travel < STUCK_SPEED:
			_stuck += delta
		else:
			_stuck = 0.0
	else:
		_stuck = 0.0
	_last = owner.global_position
	_tracked = true


## `two_bands` samples the chest lane and a higher one, so a low barrier and a
## tall wall are both seen in the one query that decides straight travel. The
## fan after it tests the chest band alone.
func _clear(owner: Node3D, direction: Vector3, probe_height: float, lane: float,
		two_bands: bool = true) -> bool:
	if not is_instance_valid(owner):
		return false
	var space := owner.get_world_3d().direct_space_state
	var base := owner.global_position + Vector3(0.0, probe_height, 0.0)
	_query.from = base
	_query.to = base + direction * lane
	if not space.intersect_ray(_query).is_empty():
		return false
	if not two_bands:
		return true
	_query.from = base + Vector3(0.0, UPPER_LIFT, 0.0)
	_query.to = _query.from + direction * lane
	return space.intersect_ray(_query).is_empty()
