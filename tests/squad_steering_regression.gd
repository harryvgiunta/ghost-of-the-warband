extends SceneTree
## A squadmate's heading is its body's facing.
##
## `Archer.set_locomotion` snaps the whole rig to the move direction, so any
## intent that flips sides between frames spins the body on the spot: four allies
## whirling in fast little circles is what the camp's fight looked like. This test
## holds the rule that stops it - the intent is *turned* towards what the brain
## wants at `SquadDrive.TURN_RATE` instead of being taken whole - and that a roll
## which used to reverse every step now never reverses at all.

const SquadScript = preload("res://scripts/warband/squad_drive.gd")

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("SQUAD_STEER_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var step := 1.0 / 60.0
	var cap := deg_to_rad(SquadScript.TURN_RATE) * step

	# One frame of turning is capped, whatever it is asked for.
	var flip := SquadScript.limited_heading(Vector3.FORWARD, Vector3.BACK, step)
	check(absf(Vector3.FORWARD.signed_angle_to(flip, Vector3.UP)) <= cap + 0.0001,
		"a 180 degree request turns by the cap and no more")
	check(flip.length() > 0.99, "and the heading stays a unit vector")

	# The same request held gives the wanted direction outright.
	var wanted := Vector3(0.6, 0.0, -0.8)
	var aligned := SquadScript.limited_heading(wanted, wanted, step)
	check(aligned.distance_to(wanted) < 0.001, "an aligned body keeps its heading")
	var settled := SquadScript.limited_heading(Vector3.ZERO, wanted, step)
	check(settled.distance_to(wanted) < 0.001, "a body with no heading takes the wanted one")

	# The bug itself: an intent that flips between two headings every few frames.
	var body := FakeBody.new()
	root.add_child(body)
	var squad = SquadScript.new()
	squad.setup(null, null, null)
	var track := {"merc_id": 1, "delta": step, "side": 0.0, "sign": 1.0, "state": 0,
		"state_left": 0.0, "step_left": 0.0, "roam_left": 0.0}
	var headings: Array[Vector3] = []
	var left := Vector3(-1.0, 0.0, 0.0)
	var right := Vector3(1.0, 0.0, 0.0)
	for index in 240:
		var want := left if (index / 3) % 2 == 0 else right
		squad._steer(body, want, track, false)
		headings.append(Vector3(body.last_intent.x, 0.0, body.last_intent.y))
	var worst_turn := 0.0
	var travelled := 0.0
	for index in range(1, headings.size()):
		var turn := absf(headings[index - 1].signed_angle_to(headings[index], Vector3.UP))
		worst_turn = maxf(worst_turn, turn)
		travelled += turn
	check(worst_turn <= cap + 0.0001,
		"a body fed a flipping intent never turns faster than the cap (%.1f deg/frame)"
		% rad_to_deg(worst_turn))
	check(worst_turn > 0.0, "and it still turns: the fix is a rate, not a freeze")
	check(travelled <= deg_to_rad(SquadScript.TURN_RATE) * 4.0 + 0.01,
		"net turning stays inside the rate over four seconds (%.0f deg)" % rad_to_deg(travelled))

	# A roll never reverses the body's own feet.
	check(is_zero_approx(SquadScript.CIRCLE_REVERSE),
		"a circle never reverses a body's direction of travel")
	check(SquadScript.CIRCLE_MIN >= 0.5 and SquadScript.STEP_MIN >= 0.35,
		"the roll windows are long enough to read as steps (%.2f s, %.2f s)"
		% [SquadScript.CIRCLE_MIN, SquadScript.STEP_MIN])

	print("SQUAD_STEERING_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## The only part of a rigged body the steering writes is the intent.
class FakeBody extends Node3D:
	var last_intent := Vector2.ZERO
	var combat := FakeCombat.new()
	var move_direction := Vector2.ZERO
	var run_requested := false

	func accept_network_input(direction: Vector2, _running: bool) -> void:
		last_intent = direction

class FakeCombat extends RefCounted:
	func stop_block() -> void:
		pass

	func stop() -> void:
		pass
