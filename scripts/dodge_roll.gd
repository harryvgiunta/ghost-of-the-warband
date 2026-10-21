extends Node
## A second jump press within the tap window starts one directional airborne roll.
const DOUBLE_TAP_SECONDS := 0.30
const DURATION := 0.68
const SPEED := 8.5
var active := false
var direction := Vector3.FORWARD
var progress := 0.0
var takeoff_pending := false
var _tap_elapsed := INF
var _used_in_air := false

func press_jump(movement: Vector3, facing: Vector3, grounded: bool) -> bool:
	if active:
		return false
	if _tap_elapsed <= DOUBLE_TAP_SECONDS and not _used_in_air:
		direction = Vector3(movement.x,0,movement.z)
		if direction.length_squared() < 0.01:
			direction = Vector3(facing.x,0,facing.z)
		direction = direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
		active = true
		progress = 0.0
		takeoff_pending = true
		_used_in_air = true
		_tap_elapsed = INF
		return false
	_tap_elapsed = 0.0
	return grounded

func advance(delta: float, grounded: bool) -> void:
	_tap_elapsed += delta
	if active:
		progress = minf(1.0,progress+delta/DURATION)
		if progress >= 1.0:
			active = false
	elif grounded:
		_used_in_air = false

func reset() -> void:
	active = false
	progress = 0.0
	takeoff_pending = false
	_tap_elapsed = INF
	_used_in_air = false
