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

const Actor = preload("res://scripts/warband/warband_body.gd")

## The world layer `ArenaActor` bodies collide with; camera probes only this.
const WORLD_MASK := 1
## Where the eye sits on the body, in metres above its feet.
const EYE_HEIGHT := 1.65
## Default orbit: behind and above the body, close enough to read a blade.
const FOLLOW_DISTANCE := 4.4
const FOLLOW_PITCH := 0.26
## The eye rides a shoulder, not the spine: the frontier's 0.70 m, so the reticle
## and the body's own head are never the same point on screen.
const SHOULDER_OFFSET := 0.70
## How far the arc may swing. The old limit was -0.12 .. +0.95 rad, which is
## seven degrees of sky - a body could not see the canopy it was walking under,
## let alone the ground at its own feet. A free look is the whole sphere bar the
## last five degrees at each pole, where the arc has no side left to swing to.
## The signs follow `pitch`: negative lifts the eye below the horizon (looking
## up), positive puts it overhead (looking down).
const LOOK_UP := -1.4835
const LOOK_DOWN := 1.4835
## How fast the eye crosses from one shoulder to the other, per second.
const SWAP_RATE := 10.0
## The closest the camera may be pulled before it refuses to move in further.
const MIN_DISTANCE := 0.55
## Clearance kept off the geometry that pulled the camera in.
const SURFACE_MARGIN := 0.28
## The radius of the column the ridden body's own legs and chest occupy. Past
## about seventy degrees of upward look the resolved eye is directly under the
## body, which is the inside of a thigh; it slides out to this standoff instead,
## because free look must never mean "look through the man you are".
const BODY_STANDOFF := 0.62
## How fast the boom may pull in and how slowly it is allowed back out. A tree
## passing between the eye and the body makes the raw ray distance jump by metres
## from one frame to the next; snapping to it reads as the world shaking, which is
## exactly what a running body through the wood looked like. Pulling in quickly
## keeps the trunk from clipping through, easing out is what stops the jitter.
const BOOM_IN_RATE := 30.0
const BOOM_OUT_RATE := 3.5
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
## Which shoulder the eye is over: 1 the body's right, -1 its left. `X` swaps it,
## exactly as the frontier's `shoulder_camera.swap()` does.
var side := 1
## The eased lateral offset, so a swap crosses the body instead of cutting.
var _offset := SHOULDER_OFFSET

var _target: Actor
var _swooping := false
## The current smoothed boom length, -1 until the first frame resolves one.
var _boom := -1.0
## The frame delta the last `update()` was given, so `_resolved` can ease on the
## same clock the caller uses (it is also called from `follow_point()`).
var _delta := 1.0 / 60.0
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

## Cross to the other shoulder. The offset eases across in `update()`, so the view
## slides over the body's shoulder instead of snapping to the far side of it.
func swap() -> void:
	side = -side

## Move the eye around the body. Called with the mouse delta by the controller.
## Yaw wraps, so the horizontal is already free; pitch is the whole sky and the
## whole ground, short of the pole.
func rotate_view(delta_yaw: float, delta_pitch: float) -> void:
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	pitch = clampf(pitch + delta_pitch, LOOK_UP, LOOK_DOWN)

## The arc and the follow both run from here, once per controller frame.
func update(delta: float) -> void:
	_delta = clampf(delta, 0.0, 0.1)
	_ensure_camera()
	if camera == null:
		return
	if active_body() == null:
		_swooping = false
		return
	_offset = lerpf(_offset, float(side) * SHOULDER_OFFSET,
		1.0 - exp(-SWAP_RATE * clampf(delta, 0.0, 0.1)))
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

## The centre ray of the view, which is the possessed body's aim. Projected
## through the screen centre rather than read off the camera basis, so the ray and
## the drawn reticle are the same line by construction - a shoulder offset, a
## different viewport or a zoom cannot desync them.
func aim_ray() -> Dictionary:
	var cam := camera
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return {"origin": global_position, "direction": -global_basis.z}
	var centre := get_viewport().get_visible_rect().size * 0.5
	return {
		"origin": cam.project_ray_origin(centre),
		"direction": cam.project_ray_normal(centre),
	}

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

## Look along the orbit, never at the body: an eye that re-centres on the head
## cannot be aimed (the reticle would sit on the character's own skull, and the
## pitch would fight itself). The frontier looks down `-back` for the same reason.
##
## The basis is composed from `yaw` and `pitch` rather than aimed with
## `look_at(pos - back, Vector3.UP)`: `look_at` degenerates as the view nears a
## pole, where its up hint is parallel to the direction it is given, and a free
## look walks straight into those poles. Composed, the whole sphere is stable:
## `-Z` lands on `-back` exactly (yaw about world up, then pitch about the local
## right, tilting the view down as `pitch` lifts the eye), and the up vector
## follows at any angle.
func _look() -> void:
	if camera == null:
		return
	camera.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)


## The unit vector from the body's focus out to the eye's shoulder.
func _back() -> Vector3:
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()

## The point the eye should read: the body's head and shoulders, not its feet.
## A warband body carries its own height, so a short mercenary does not get an eye
## floating above his crown and a tall one does not look at his collarbone.
func _focus_point() -> Vector3:
	var body := active_body()
	if body == null:
		return global_position
	var height := EYE_HEIGHT
	if body.has_method("body_scale"):
		height *= float(body.body_scale())
	return body.global_position + Vector3.UP * height

## The eye's wanted position: the orbit distance back along `back`, then the
## shoulder offset across it, before occlusion.
func _shoulder() -> Vector3:
	var back := _back()
	var right := Vector3(back.z, 0.0, -back.x).normalized()
	return _focus_point() + back * FOLLOW_DISTANCE + right * _offset

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
	var wanted_length := anchor.distance_to(wanted)
	var free_length := wanted_length
	if not hit.is_empty():
		free_length = anchor.distance_to(hit.position) - SURFACE_MARGIN
		free_length = clampf(free_length, MIN_DISTANCE, maxf(MIN_DISTANCE, wanted_length))
	if _boom < 0.0:
		_boom = free_length
	else:
		var rate := BOOM_IN_RATE if free_length < _boom else BOOM_OUT_RATE
		_boom = move_toward(_boom, free_length, rate * _delta)
	var direction: Vector3 = (wanted - anchor).normalized() if wanted_length > 0.0001 \
		else Vector3.BACK
	var point: Vector3 = anchor + direction * _boom
	# A boom pulled flat against the ground would look through the body's knees.
	point.y = maxf(point.y, body.global_position.y + MIN_HEIGHT)
	return _off_body(body, point)


## Keep the eye out of the column the ridden body's own legs and chest occupy.
##
## Looking up to the top of the arc resolves an eye directly beneath the body -
## a metre of sky above, and the inside of a thigh in front of it. The eye slides
## out to `BODY_STANDOFF` along its own azimuth instead, keeping the height the
## boom already resolved, so the view is "up past your own shoulder" and not
## "through your own legs". The slide is probed against the world at the eye's own
## height: standing with a trunk at your back must not push the eye into it.
func _off_body(body: Actor, point: Vector3) -> Vector3:
	var feet := body.global_position
	var height := EYE_HEIGHT
	if body.has_method("body_scale"):
		height *= float(body.body_scale())
	# Above the body's own head the eye is looking at the man, not through him.
	if point.y < feet.y or point.y > feet.y + height * 1.15:
		return point
	var flat := Vector2(point.x - feet.x, point.z - feet.z)
	var reach := flat.length()
	if reach >= BODY_STANDOFF:
		return point
	var away := flat / reach if reach > 0.0001 else Vector2(sin(yaw), cos(yaw))
	if away.length() < 0.0001:
		return point
	away = away.normalized()
	var base := Vector3(feet.x, point.y, feet.z)
	var out := Vector3(away.x, 0.0, away.y)
	_query.from = base + out * 0.10
	_query.to = base + out * BODY_STANDOFF
	_query.collision_mask = WORLD_MASK
	_query.exclude = [body.get_rid()]
	var space := get_world_3d().direct_space_state
	if space == null or not space.intersect_ray(_query).is_empty():
		return point
	return _query.to
