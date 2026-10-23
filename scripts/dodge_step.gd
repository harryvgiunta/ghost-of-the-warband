extends Node
## Fast grounded side-step shared by the frontier and arena controllers.
## Short travel, short recovery, and no invulnerability: unlike the roll this
## is a positioning move that can be chained after a brief cooldown.

const DURATION := 0.30
const TRAVEL := 2.95
const COOLDOWN := 0.55
const STAMINA_COST := 7.0

var active := false
var direction := Vector3.RIGHT
var progress := 0.0
var cooldown_left := 0.0

func can_step(grounded: bool, rolling: bool) -> bool:
	return grounded and not rolling and not active and cooldown_left <= 0.0

func try_step(planar: Vector3, grounded: bool, rolling: bool) -> bool:
	if not can_step(grounded,rolling):
		return false
	var flat := Vector3(planar.x,0.0,planar.z)
	if flat.length_squared() < 0.0001:
		return false
	direction = flat.normalized()
	active = true
	progress = 0.0
	cooldown_left = COOLDOWN + DURATION
	return true

func advance(delta: float, grounded: bool) -> void:
	cooldown_left = maxf(0.0,cooldown_left-delta)
	if not active:
		return
	if not grounded:
		# A step is a planted move. Leaving the floor ends it without carrying
		# a hidden sideways velocity into the jump.
		reset()
		return
	progress = minf(1.0,progress+delta/DURATION)
	if progress >= 1.0:
		active = false

func velocity() -> Vector3:
	if not active:
		return Vector3.ZERO
	# Ease-out calibrated at the 60 Hz physics rate: the sampled travel over
	# DURATION is TRAVEL, so the HUD, docs and the real move agree.
	var weight := 1.0-progress
	return direction * (TRAVEL/DURATION) * (1.46*weight+0.31)

func reset() -> void:
	active = false
	progress = 0.0
	cooldown_left = 0.0
