extends Node
## A grounded sprint-crouch burst. The owning controller still resolves all collisions.
const DURATION := 0.75
const START_SPEED := 10.5
const END_SPEED := 2.2
const MIN_START_SPEED := 6.0
const STEER_ANGLE := PI / 5.0
const STEER_RATE := 1.5
var active := false
var direction := Vector3.FORWARD
var progress := 0.0
var speed := 0.0
var _start_direction := Vector3.FORWARD

func try_start(body: CharacterBody3D, stance: Node, sprinting: bool, rolling: bool) -> bool:
	if active or not sprinting or rolling or not body.is_on_floor() \
		or stance.active or stance.crouched or stance.crouch_requested:
		return false
	# Achieved movement, not requested velocity: sprinting into a wall cannot launch a slide.
	var travel := body.get_real_velocity()
	travel.y = 0.0
	if travel.length_squared() < MIN_START_SPEED * MIN_START_SPEED:
		return false
	direction = travel.normalized()
	_start_direction = direction
	progress = 0.0
	speed = START_SPEED
	active = true
	stance.crouch_requested = true
	return true

func step(delta: float, body: CharacterBody3D, stance: Node, desired_direction: Vector3, rolling: bool) -> Vector3:
	if not active:
		return Vector3.ZERO
	if not body.is_on_floor() or not stance.crouch_requested or stance.active or rolling:
		reset()
		return Vector3.ZERO
	progress = minf(1.0,progress + delta / DURATION)
	if progress >= 1.0:
		reset()
		return Vector3.ZERO
	var desired := Vector3(desired_direction.x,0,desired_direction.z)
	if desired.length_squared() > 0.01 and desired.dot(_start_direction) >= -0.01:
		var angle := clampf(_start_direction.signed_angle_to(desired.normalized(),Vector3.UP),-STEER_ANGLE,STEER_ANGLE)
		var target := _start_direction.rotated(Vector3.UP,angle)
		var turn := clampf(direction.signed_angle_to(target,Vector3.UP),-STEER_RATE*delta,STEER_RATE*delta)
		direction = direction.rotated(Vector3.UP,turn).normalized()
	speed = lerpf(START_SPEED,END_SPEED,progress)
	return direction * speed

func after_move(body: CharacterBody3D, actual_velocity: Vector3) -> void:
	if active and (not body.is_on_floor() or actual_velocity.dot(direction) < maxf(1.0,speed*0.35)):
		reset()

func reset() -> void:
	active = false
	progress = 0.0
	speed = 0.0
	direction = Vector3.FORWARD
	_start_direction = Vector3.FORWARD
