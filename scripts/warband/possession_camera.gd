class_name PossessionCamera
extends Node3D
## The floating eye of the soul. It rides one body's shoulder and, when the
## soul changes bodies, arcs across the field instead of cutting, because the
## whole premise of Ghost of the Warband is that the thing moving between
## bodies is continuous.
##
## The camera owns exactly one `Camera3D` and one offset. Occlusion is resolved
## against the world layer every frame: a body backed into a rock must not put
## the camera inside the rock, and a swoop must never END inside geometry, which
## is why the resolved follow point is the swoop's last lerp target rather than
## a raw offset.
##
## Camera aim is the single source of truth for the possessed body: the
## controller asks `aim_ray()` and hands the centre ray to `Combat`.

const Actor = preload("res://scripts/arena_actor.gd")

## The world layer `ArenaActor` bodies collide with; camera probes only this.
const WORLD_MASK := 1
## Where the eye sits on the body, in metres above its feet.
const EYE_HEIGHT := 1.65
## Default orbit: behind and above the body, close enough to read a blade.
const FOLLOW_DISTANCE := 4.4
const FOLLOW_PITCH := 0.26
## The closest the camera may be pulled before it refuses to move in further.
const MIN_DISTANCE := 0.55
## Clearance kept off the geometry that pulled the camera in.
const SURFACE_MARGIN := 0.28
## A pulled-in camera never drops below this height over the body's feet.
const MIN_HEIGHT := 0.9
## Default length of the body-to-body arc.
const SWOOP_SECONDS := 0.35
## How fast the camera closes the last metres of ordinary follow.
const FOLLOW_RATE := 16.0

var camera: Camera3D
## Orbit around the body, radians. Yaw 0 puts the camera behind (+Z), positive
## pitch lifts it. The controller feeds these from the mouse.
var yaw := 0.0
var pitch := FOLLOW_PITCH

var _target: Actor
var _swooping := false
var _swoop_from := Vector3.ZERO
var _swoop_left := 0.0
var _swoop_total := 0.0
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_ensure_camera()

## Take over a scene camera (the one the mode already created and made current)
## so there is exactly one camera in the tree, not a second one watching the
## same body.
func adopt(node: Camera3D) -> void:
	if node == null or node == camera:
		return
	# The scene's own camera wins over the fallback eye this node builds for a
	# scene that has none. Leaving the fallback behind would make two cameras
	# current at once, which is a coin flip on which one the player looks through.
	if is_instance_valid(camera) and camera != node and camera.get_parent() == self:
		camera.current = false
		remove_child(camera)
		camera.queue_free()
	if node.get_parent() == self:
		camera = node
		node.current = true
		return
	if node.get_parent() != null:
		node.reparent(self, true)
	else:
		add_child(node)
	camera = node
	camera.current = true

## The body the eye is riding, or null while the soul is between bodies.
func active_body() -> Actor:
	return _target if is_instance_valid(_target) else null

func has_target() -> bool:
	return active_body() != null

## Ride `body`. `snap` is for the first body of a session and for scene
## hand-offs; every later change is an arc, which is the whole idea.
func follow(body: Actor, snap: bool = false) -> void:
	_target = body if is_instance_valid(body) else null
	_swooping = false
	_ensure_camera()
	if _target == null:
		return
	if snap:
		_place(_resolved(_shoulder()))
	else:
		swoop_to(body)

## Arc from wherever the eye is now to the new body's shoulder in `seconds`,
## eased so the move accelerates out of the old body and settles into the new.
func swoop_to(body: Actor, seconds: float = SWOOP_SECONDS) -> void:
	_ensure_camera()
	_target = body if is_instance_valid(body) else null
	if _target == null:
		_swooping = false
		return
	_swoop_from = _camera_position()
	_swoop_total = maxf(seconds, 0.001)
	_swoop_left = _swoop_total
	_swooping = true
	# A zero-length request still has to land, and land out of geometry.
	if seconds <= 0.0:
		_swooping = false
		_place(_resolved(_shoulder()))

## Stop riding anything: the soul is between bodies (spectating, dead, no body
## left). The camera holds its last frame so the world does not jump.
func clear() -> void:
	_target = null
	_swooping = false

## Drop the body when it is freed under us without an explicit release.
func forget(body: Actor) -> void:
	if body == _target:
		clear()

## Move the eye around the body. Called with the mouse delta by the controller.
func rotate_view(delta_yaw: float, delta_pitch: float) -> void:
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	pitch = clampf(pitch + delta_pitch, -0.12, 0.95)

## The arc and the follow both run from here, once per controller frame.
func update(delta: float) -> void:
	_ensure_camera()
	if camera == null:
		return
	if active_body() == null:
		_swooping = false
		return
	if _swooping:
		_swoop_left = maxf(0.0, _swoop_left - delta)
		var travelled := 1.0 - (_swoop_left / _swoop_total)
		var eased := travelled * travelled * (3.0 - 2.0 * travelled)
		var point := _resolved(_swoop_from.lerp(follow_point(), eased))
		# Same frame the arc lands, it is already the settled shoulder.
		if _swoop_left <= 0.0:
			_swooping = false
			point = _resolved(_shoulder())
		_place(point)
	else:
		var point := _resolved(_shoulder())
		_place(_camera_position().lerp(point, 1.0 - exp(-FOLLOW_RATE * delta)))
	_look()

## Where the eye settles for the body it rides right now, after occlusion.
func follow_point() -> Vector3:
	return _resolved(_shoulder())

## The centre ray of the view, which is the possessed body's aim.
func aim_ray() -> Dictionary:
	var cam := camera
	if cam == null or not is_instance_valid(cam):
		return {"origin": global_position, "direction": -global_basis.z}
	return {"origin": cam.global_position, "direction": -cam.global_basis.z.normalized()}

# --- internals --------------------------------------------------------------

func _ensure_camera() -> void:
	if camera != null and is_instance_valid(camera):
		return
	camera = Camera3D.new()
	camera.name = "SoulCamera"
	camera.fov = 59.0
	camera.near = 0.08
	camera.far = 150.0
	camera.current = true
	add_child(camera)

func _camera_position() -> Vector3:
	return camera.global_position if camera != null else global_position

func _place(point: Vector3) -> void:
	if camera != null:
		camera.global_position = point

func _look() -> void:
	if camera != null:
		camera.look_at(_focus_point(), Vector3.UP)

## The point the eye should read: the body's head and shoulders, not its feet.
func _focus_point() -> Vector3:
	var body := active_body()
	if body == null:
		return global_position
	return body.global_position + Vector3.UP * EYE_HEIGHT

## Shoulder offset for the body's centre, before occlusion.
func _shoulder() -> Vector3:
	var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return _focus_point() + back.normalized() * FOLLOW_DISTANCE

## Pull a wanted eye position out of geometry. The ray runs from the focus to
## the wanted point so a wall between the two shortens the boom instead of
## letting the camera see through it.
func _resolved(wanted: Vector3) -> Vector3:
	var body := active_body()
	if body == null or not is_inside_tree():
		return wanted
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var anchor := _focus_point()
	_query.from = anchor
	_query.to = wanted
	_query.collision_mask = WORLD_MASK
	var excluded: Array[RID] = [body.get_rid()]
	_query.exclude = excluded
	var hit := space.intersect_ray(_query)
	var point := wanted
	if not hit.is_empty():
		var direction: Vector3 = (wanted - anchor).normalized()
		var reach := maxf(0.0, anchor.distance_to(hit.position) - SURFACE_MARGIN)
		reach = clampf(reach, MIN_DISTANCE, maxf(MIN_DISTANCE, anchor.distance_to(wanted)))
		point = anchor + direction * reach
	# A boom pulled flat against the ground would look through the body's knees.
	point.y = maxf(point.y, body.global_position.y + MIN_HEIGHT)
	return point
