extends RefCounted
## Frame budget for the wilderness brain.
##
## Seventy-five bodies cannot each run sight, steering and the state machine
## every frame: at 60 Hz that alone eats most of the physics budget. One rule
## instead - the *decision rate* follows the distance to the nearest ranger:
##
##   near  (<= 22 m)   every frame        (30 Hz once calm: a fight is the
##                                         only thing that needs 60)
##   mid   (<= 55 m)   every third        (12 Hz once calm)
##   far   (<= 95 m)   every twelfth      (5 Hz)
##   deep  (> 95 m)    every twenty-four  (2.5 Hz)
##   parked (> 150 m)  never              (no tick, no draw, no state change)
##
## `MobLod` decides how often a body may *tick*; a family may spread its brain
## further inside those ticks. `enemy.gd` thinks on the budget itself (60/20/5/2.5
## Hz by band); `devil_mob` re-spreads its brain over every fifth tick
## (`THINK_FRAMES`), so a near body decides 12 times a second, mid 4, far 1 and
## deep 0.5 - the further away a body is, the less it is asked to notice, and a
## hall of two hundred of them is not two hundred brains at 60 Hz.
##
## The budget buys **decisions, not motion**. A body's feet move on every frame
## it is awake, on the motion its last decided tick set (`MobLod.move`), so a
## body on the far budget walks as smoothly as a near one. A skipped frame is
## not lost time either: the pending delta is carried into the next decision, so
## a far body decides over the same wall clock in coarser steps. Beyond 55 m no
## profile can see past 32 m, so a low-rate body can never miss a sighting it
## could have made.
##
## Past `DORMANT_DISTANCE` a low rate is still a wasted frame: nothing that far
## away can be seen at all - the frontier's fog is opaque well before it - so a
## body there is parked outright. It keeps its position, health, pack and
## corpse; it stops running sight, steering, its state machine and its swept
## move, and it stops drawing. `MobCuller` sweeps the group a few times a second
## and the body itself decides when it may be parked (calm and standing) and
## when a ranger has come back inside `WAKE_DISTANCE`.
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
## Past this distance the body is parked: no tick of any kind, and hidden. The
## frontier's fog is fully opaque at 145 m (`WorldStyle.frontier`), so a body
## leaving or entering this range is invisible either way.
const DORMANT_DISTANCE := 150.0
## Hysteresis: a parked body only comes back inside this, so a ranger standing
## on the boundary cannot flip it on every sweep.
const WAKE_DISTANCE := 128.0
## Past this distance animation evaluation and locomotion presentation stop.
const ANIMATE_DISTANCE := 62.0
## Past this distance a rig poses every other frame instead of every frame. A
## two-metre creature at ten metres is a couple of hundred pixels of silhouette
## and the authored cycle is a clock - a coarser solve samples the phase the body
## would have been at anyway. Inside it the body is close enough that a swing has
## to read frame for frame.
const POSE_NEAR := 10.0
## Past this distance a body stops casting into the four shadow splits. Every
## mob inside 110 m used to be skinned a second time for the shadow pass.
const SHADOW_DISTANCE := 30.0

var _tick := 0
var _pending := 0.0
## Set when the body comes back from dormancy: the first `slice` after it is
## granted whatever its band says, instead of waiting out the rest of it.
var _fresh := false
## Granted slices since spawn: a diagnostic, and what the budget regression
## counts to prove a far body really sits frames out.
var grants := 0


## `phase` spreads the packs across frames so a whole habitat never ticks on
## the same frame.
func _init(phase: int = 0) -> void:
	_tick = absi(phase)


## Dormancy, in one place: a parked body stays parked until it is back inside
## `WAKE_DISTANCE`, an awake one parks at `DORMANT_DISTANCE`.
static func dormant(nearest: float, sleeping: bool) -> bool:
	if not is_finite(nearest):
		return false
	return nearest >= (WAKE_DISTANCE if sleeping else DORMANT_DISTANCE)


## The delta this body should integrate now, or 0.0 when it sits the frame out.
## `calm` is a body with nothing to fight: it walks a patch instead of playing a
## duel, so it may spend more frames per tick.
func slice(nearest: float, delta: float, calm: bool = false) -> float:
	if is_finite(nearest) and nearest >= DORMANT_DISTANCE:
		# Parked. Bank nothing: a body must not hand the whole minute it slept
		# to its first tick back. No ranger at all is not "far away" - a scene
		# without a player still runs its bodies on the deepest band.
		_pending = 0.0
		return 0.0
	var frames := DEEP_FRAMES
	if nearest <= NEAR_DISTANCE:
		frames = CALM_NEAR_FRAMES if calm else NEAR_FRAMES
	elif nearest <= MID_DISTANCE:
		frames = CALM_MID_FRAMES if calm else MID_FRAMES
	elif nearest <= DEEP_DISTANCE:
		frames = FAR_FRAMES
	if _fresh:
		_fresh = false
		_tick = frames - 1
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


## A body that was parked starts again on its first frame, and banks nothing
## from the sleep.
func resume() -> void:
	_pending = 0.0
	_fresh = true


## Presentation band: 0 still casts a shadow, 1 animates without one, 2 rests.
## Bodies cache this so the render budget is applied only when it changes, never
## per frame.
static func band(nearest: float) -> int:
	if nearest <= SHADOW_DISTANCE:
		return 0
	if nearest <= ANIMATE_DISTANCE:
		return 1
	return 2


## Below this horizontal speed a body with its feet down has nowhere to go.
const STILL_SPEED := 0.02

## The body's own step: exactly one physics frame, every frame it is awake.
## Every mob family steps its feet here and puts only its *decisions* on the
## budget, so a body on the far budget covers the same ground in the same shape
## as one in a fight. (This used to scale the sweep by the banked budget, which
## is why a body at sixty metres crossed the ground in metre-long steps five
## times a second.)
##
## **A standing body does not sweep.** `move_and_slide` is the most expensive
## thing a mob does in a frame - a capsule cast at the terrain, 2.6 us on this
## project's world - and for a body with its feet down and no motion it resolves
## to standing still. Half of a stand-off is spent standing or circling on the
## spot: two hundred bodies holding a hall was two hundred casts a frame, 0.5 ms,
## for nothing.
static func move(body: CharacterBody3D) -> void:
	if is_instance_valid(body) and moving(body):
		body.move_and_slide()


## Whether this body has anywhere to go this frame: it is off its feet, or it is
## moving. The one rule `move` applies and the one a regression can read - a body
## with its feet down and no motion asks the world nothing at all.
static func moving(body: CharacterBody3D) -> bool:
	if not is_instance_valid(body):
		return false
	if not body.is_on_floor():
		return true
	return Vector2(body.velocity.x, body.velocity.z).length() >= STILL_SPEED


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
