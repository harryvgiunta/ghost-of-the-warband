extends RefCounted
## Boots: the sound of one walking body's footfalls.
##
## It reads the rig's own feet - the same joints `bloody_feet.gd` prints on - and
## plays a take when a foot comes back down, so the sound is tied to the step the
## player can see rather than to a timer that only happens to be near the walk
## cycle. A body that is standing still, airborne or further than `AUDIBLE` from
## the eye makes no sound at all, which is what keeps a fight's soundtrack to the
## blows instead of a wall of scuffs.
##
## Presentation only: nothing here reads or writes damage, health or authority.

const SfxScript = preload("res://scripts/audio/sfx.gd")

## A foot must fall this far below its tracked peak to count as a footfall. The
## number is `BloodyFeet.STEP_DROP` on purpose: the print and the sound are one
## event seen and heard, not two different guesses at where the boot landed.
const STEP_DROP := 0.05
## Below this ground speed a body is shuffling in place, not walking.
const MIN_SPEED := 0.45
## Seconds before the same foot may sound again. A run clip bobs a foot several
## times per stride; without this the boots machine-gun.
const MIN_GAP := 0.18
## A footfall further than this from the camera is not worth a voice. Feet are
## close-range information: past a few dozen metres the fight is what matters.
const AUDIBLE := 28.0

var _peak: Array[float] = [0.0, 0.0]
var _gap: Array[float] = [0.0, 0.0]

## Call once per physics tick, after the body has moved and the rig is posed.
##
## `body` and `rig` are duck-typed on purpose: the two things this needs from a
## body (`velocity`, `is_on_floor()`) cannot both be faked on a real
## `CharacterBody3D` - the engine's own method cannot be overridden - and a
## presentation helper that cannot be driven by a regression is a helper nobody
## can prove. The call sites pass the real body and rig.
func update(delta: float, body, rig) -> void:
	if not is_instance_valid(body) or not is_instance_valid(rig):
		return
	for side in 2:
		_gap[side] = maxf(_gap[side] - delta, 0.0)
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if not body.is_on_floor() or speed < MIN_SPEED:
		_peak[0] = 0.0
		_peak[1] = 0.0
		return
	# Both boots are still on their clock: sample nothing until one is free.
	if _gap[0] > 0.0 and _gap[1] > 0.0:
		_peak[0] = 0.0
		_peak[1] = 0.0
		return
	var camera := _camera(body)
	if camera != null and body.global_position.distance_to(camera.global_position) > AUDIBLE:
		_peak[0] = 0.0
		_peak[1] = 0.0
		return
	if not rig.has_method("get_joint_positions"):
		return
	var joints: Dictionary = rig.get_joint_positions()
	var feet := [joints.get("left_foot", body.global_position),
		joints.get("right_foot", body.global_position)]
	for side in 2:
		var foot: Vector3 = feet[side]
		var peak: float = _peak[side]
		# Track the lift; the boot lands when it comes back down.
		if foot.y > peak:
			_peak[side] = foot.y
			continue
		if peak <= 0.0 or foot.y >= peak - STEP_DROP:
			continue
		_peak[side] = 0.0
		if _gap[side] > 0.0:
			continue
		_gap[side] = MIN_GAP
		SfxScript.play("footstep", foot)


## The eye this body's boots are heard from, or null when it has none (a
## headless run, a detached stub): no eye means no distance cull, not no sound.
func _camera(body) -> Camera3D:
	if not body.is_inside_tree() or not body.has_method("get_viewport"):
		return null
	var viewport: Viewport = body.get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
