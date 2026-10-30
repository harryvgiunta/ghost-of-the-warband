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

	check_fetch_give_up(step)

	print("SQUAD_STEERING_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## A walk to a piece of loot is a walk, not an order. The camp showed what the
## missing rule cost: a freed squad that could not cross a cage wall to the shiv
## stood shouldering that wall for the rest of the session, so the run never began.
## A body that has not earned `FETCH_PROGRESS` metres of headway in
## `FETCH_GIVE_UP` seconds abandons that piece - and the whole squad is on to the
## next errand, because the abandoned key leaves every selector at once.
func check_fetch_give_up(step: float) -> void:
	# --- a body that cannot close the gap -------------------------------
	var blocked := FakeBody.new()
	root.add_child(blocked)
	var shiv := FakePickup.new()
	shiv.item_id = "dagger_ironwood"
	root.add_child(shiv)
	shiv.global_position = Vector3(0.0, 0.0, 12.0)
	var squad = SquadScript.new()
	squad.setup(null, null, null)
	squad.pickups = [shiv]
	check(squad._nearest_weapon_pickup(blocked) == shiv,
		"an unarmed ally finds the steel on the ground")

	var key: String = squad._pickup_key(shiv)
	var fetch := {"merc_id": 1, "delta": step, "side": 0.0, "sign": 1.0}
	var walked := 0
	var early := 0.0
	for index in 600:
		if not squad._walk_to_loot(blocked, shiv.global_position, key, fetch):
			break
		walked += 1
		if index == 60:
			early = blocked.last_intent.length()
	check(walked > 0 and walked < 600, "a blocked walk ends on its own (%d frames)" % walked)
	check(early > 0.9, "and until then it was really walking there (%.2f)" % early)
	var seconds := float(walked) * step
	check(absf(seconds - SquadScript.FETCH_GIVE_UP) <= step * 2.0,
		"after its own give-up window (%.2f s)" % seconds)
	check(squad._nearest_weapon_pickup(blocked) == null,
		"the piece the squad cannot reach is not offered again")
	check(not squad._walk_to_loot(blocked, shiv.global_position, key, fetch),
		"and the walk is not restarted by the next call")

	# --- a body that is closing on it keeps the trip --------------------
	var walker := FakeBody.new()
	root.add_child(walker)
	var sword := FakePickup.new()
	sword.item_id = "sword_short"
	root.add_child(sword)
	sword.global_position = Vector3(0.0, 0.0, 12.0)
	squad.pickups = [sword]
	var trip := {"merc_id": 2, "delta": step, "side": 0.0, "sign": 1.0}
	var held := 0
	for index in 900:
		walker.global_position += Vector3(0.0, 0.0, 0.01)
		if squad._walk_to_loot(walker, sword.global_position, squad._pickup_key(sword), trip):
			held += 1
	check(held == 900, "a body closing on the drop keeps its walk (%d of 900)" % held)
	check(squad._nearest_weapon_pickup(walker) == sword, "and the drop is still on offer")

	# --- the next reachable drop is still the squad's business ----------
	var beside := FakePickup.new()
	beside.item_id = "sword_short"
	root.add_child(beside)
	beside.global_position = Vector3(1.0, 0.0, 1.0)
	squad.pickups = [shiv, beside]
	check(squad._nearest_weapon_pickup(blocked) == beside,
		"an abandoned drop does not blind the squad to the next one")
	check(squad._in_loot_reach(blocked, beside.global_position),
		"and the one at its feet counts as reached (%.1f m)"
		% blocked.global_position.distance_to(beside.global_position))

	# --- the whole loop -------------------------------------------------
	# Through `drive()`: an ally that cannot reach the only blade stops walking at
	# it and spends its frame on something else. The magnitude is the tell - a walk
	# to loot asks for its whole walk speed (1.0) and the idle drift asks for
	# `ROAM_INTENT`.
	var frame := FakeBody.new()
	root.add_child(frame)
	var only := FakePickup.new()
	only.item_id = "dagger_ironwood"
	root.add_child(only)
	only.global_position = Vector3(0.0, 0.0, 20.0)
	var driver = SquadScript.new()
	var controller := FakeController.new()
	controller.bodies = {1: frame}
	driver.setup(FakeWarband.new(), controller, null)
	var solo: Array[int] = [1]
	driver.squad_ids = solo
	driver.pickups = [only]
	var walking := 0.0
	var afterwards := 0.0
	for index in 420:
		driver.drive(step)
		if index == 60:
			walking = frame.last_intent.length()
		afterwards = frame.last_intent.length()
	check(walking > 0.9, "the ally walks at the drop (%.2f)" % walking)
	check(afterwards < 0.5, "and gives the wall up (%.2f)" % afterwards)
	check(driver._nearest_weapon_pickup(frame) == null, "the drop is off the board")


## The only part of a rigged body the steering writes is the intent, plus the two
## facts `drive()` reads off a body before it decides anything.
class FakeBody extends Node3D:
	var last_intent := Vector2.ZERO
	var combat := FakeCombat.new()
	var move_direction := Vector2.ZERO
	var run_requested := false
	var alive := true
	var downed := false
	var health := 100.0
	var max_health := 100.0

	func accept_network_input(direction: Vector2, _running: bool) -> void:
		last_intent = direction

class FakeCombat extends RefCounted:
	var damage_enabled := true

	func stop_block() -> void:
		pass

	func stop() -> void:
		pass


## One piece on the floor: a position, an id and the flag every loot path reads.
class FakePickup extends Node3D:
	var item_id := ""
	var collected := false


## A warband with nothing in it: no roster kit (every ally is unarmed, which is
## the state the fetch rule is asked about) and no stash (so no dressing path is
## open on a body with no wound).
class FakeWarband extends RefCounted:
	var roster := FakeRoster.new()
	var stash = null


class FakeRoster extends RefCounted:
	func equipped_of(_merc_id: int) -> Dictionary:
		return {}


class FakeController extends RefCounted:
	var bodies: Dictionary = {}

	func body_of(merc_id: int):
		return bodies.get(merc_id, null)

	func focus_body():
		return null

	func merc_of(_body) -> int:
		return -1

	func refresh_gear(_merc_id: int) -> void:
		pass
