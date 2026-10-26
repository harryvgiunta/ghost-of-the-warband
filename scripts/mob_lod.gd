extends RefCounted
## Frame budget for the wilderness tick.
##
## Seventy-five bodies cannot each run sight, steering, the state machine and a
## swept collision move every frame: at 60 Hz that alone eats most of the
## physics budget. One rule instead - the tick rate follows the distance to the
## nearest ranger:
##
##   near  (<= 22 m)   every frame        (30 Hz once calm: a fight is the
##                                         only thing that needs 60)
##   mid   (<= 55 m)   every third        (12 Hz once calm)
##   far   (<= 95 m)   every twelfth      (5 Hz)
##   deep  (> 95 m)    every twenty-four  (2.5 Hz)
##
## A skipped frame is not lost time: the pending delta is carried into the next
## tick, so a far body covers the same ground in coarser steps. Beyond 55 m no
## profile can see past 32 m, so a low-rate body can never miss a sighting it
## could have made, and it is far enough away that 5 Hz reads as motion.
##
## Presentation follows the same distance: past `ANIMATE_DISTANCE` the body
## stops evaluating its animation tracks (the skeleton keeps its last pose,
## which at that distance is a few pixels) and resumes on the way back in.

const NEAR_DISTANCE := 22.0
const MID_DISTANCE := 55.0
const DEEP_DISTANCE := 95.0
const NEAR_FRAMES := 1
const MID_FRAMES := 3
const FAR_FRAMES := 12
const DEEP_FRAMES := 24
## Calm bodies walk: half the near rate and a fifth of the mid rate is
## invisible at 1.5 m/s.
const CALM_NEAR_FRAMES := 2
const CALM_MID_FRAMES := 5
## Past this distance animation evaluation and locomotion presentation stop.
const ANIMATE_DISTANCE := 62.0
## Past this distance a body stops casting into the four shadow splits. Every
## mob inside 110 m used to be skinned a second time for the shadow pass.
const SHADOW_DISTANCE := 30.0

var _tick := 0
var _pending := 0.0
## Granted slices since spawn: a diagnostic, and what the budget regression
## counts to prove a far body really sits frames out.
var grants := 0


## `phase` spreads the packs across frames so a whole habitat never ticks on
## the same frame.
func _init(phase: int = 0) -> void:
	_tick = absi(phase)


## The delta this body should integrate now, or 0.0 when it sits the frame out.
## `calm` is a body with nothing to fight: it walks a patch instead of playing a
## duel, so it may spend more frames per tick.
func slice(nearest: float, delta: float, calm: bool = false) -> float:
	var frames := DEEP_FRAMES
	if nearest <= NEAR_DISTANCE:
		frames = CALM_NEAR_FRAMES if calm else NEAR_FRAMES
	elif nearest <= MID_DISTANCE:
		frames = CALM_MID_FRAMES if calm else MID_FRAMES
	elif nearest <= DEEP_DISTANCE:
		frames = FAR_FRAMES
	if frames <= 1:
		_pending = 0.0
		grants += 1
		return delta
	_tick += 1
	if (_tick % frames) != 0:
		_pending += delta
		return 0.0
	var budget := _pending + delta
	_pending = 0.0
	grants += 1
	return budget


## Presentation band: 0 still casts a shadow, 1 animates without one, 2 rests.
## Bodies cache this so the render budget is applied only when it changes, never
## per frame.
static func band(nearest: float) -> int:
	if nearest <= SHADOW_DISTANCE:
		return 0
	if nearest <= ANIMATE_DISTANCE:
		return 1
	return 2


## `move_and_slide` integrates exactly one physics frame, but a budgeted tick
## has to cover several. The sweep is scaled up for this call and the body's
## velocity is restored after it, so a body on a 24-frame budget still covers
## 24 frames of ground in one cast (and one collision query). Views of `delta`
## inside the AI stay in real seconds.
static func move(body: CharacterBody3D, delta: float) -> void:
	if not is_instance_valid(body):
		return
	var engine := maxf(float(body.get_physics_process_delta_time()), 0.0001)
	var scale := clampf(delta / engine, 1.0, float(DEEP_FRAMES))
	if scale <= 1.0001:
		body.move_and_slide()
		return
	# Only the horizontal sweep is scaled. A scaled fall would drive the capsule
	# into the floor and the recovery step would eat the horizontal motion with
	# it - the body would stand still with a velocity set.
	var effective := body.velocity
	body.velocity = Vector3(effective.x * scale, effective.y, effective.z * scale)
	body.move_and_slide()
	body.velocity = Vector3(body.velocity.x / scale, body.velocity.y, body.velocity.z / scale)


## One render budget for a GLB body: animation evaluation and the shadow pass
## cost far more than the draw call at range. Called only when the band flips.
static func present(instance: Node3D, player: AnimationPlayer, distance: float) -> void:
	if is_instance_valid(player):
		player.active = distance <= ANIMATE_DISTANCE
	if not is_instance_valid(instance):
		return
	var casting := distance <= SHADOW_DISTANCE
	var setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casting \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = setting
