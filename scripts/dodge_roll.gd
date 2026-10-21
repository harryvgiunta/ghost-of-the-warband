extends Node
## Shift+Space requests one directional roll per airborne cycle; Space only jumps.
const DURATION := 0.68
const SPEED := 8.5
var active := false
var direction := Vector3.FORWARD
var progress := 0.0
var takeoff_pending := false
var _used_in_air := false

func press_jump(movement: Vector3, facing: Vector3, grounded: bool, roll_requested: bool) -> bool:
	if active:
		return false
	if roll_requested and not _used_in_air:
		direction = Vector3(movement.x,0,movement.z)
		if direction.length_squared() < 0.01:
			direction = Vector3(facing.x,0,facing.z)
		direction = direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD
		active = true
		progress = 0.0
		takeoff_pending = true
		_used_in_air = true
		return false
	return grounded and not roll_requested

func advance(delta: float, grounded: bool) -> void:
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
	_used_in_air = false
