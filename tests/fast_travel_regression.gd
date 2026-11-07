extends SceneTree
## Fast travel home: the sheet's RETURN TO HEARTHSTEAD, and the three doors it must
## not open.
##
## The page offers one press that puts the whole band back about the fire, and it
## has to be the same walk the road is: the whole field, on the town's own posts,
## with the squad's memory of the lane dropped and the town bookmark written - so a
## wipe from it reloads into the square and not onto the lane.
##
## The other three answers are refusals, and refusals are lines, not silence: a
## party below in the Weeping Hollow, a ring holding a fight, and a band already
## standing in the square. Every one of them leaves every body exactly where it
## stood - a fast travel that quietly moved a body out of the ring would be a way
## to walk out of a fight - and none of them wakes a body that was on its chest.

const WorldScene := "res://scenes/warband_world.tscn"
const Travel = preload("res://scripts/warband/fast_travel.gd")
const Terrain = preload("res://scripts/warband/terrain.gd")
const TEST_SAVE := "user://fast_travel_state.json"
const WARBAND_SAVE := "user://fast_travel_warband.json"

var state
var warband
var flow
var game
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("FAST_TRAVEL_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	for path in [TEST_SAVE, WARBAND_SAVE]:
		_remove(path)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.world_start = "town"
	game = load(WorldScene).instantiate()
	root.add_child(game)
	# The world seats its band a frame or two after it opens; wait on the bodies
	# rather than on a clock, so a slow machine fails nothing but its own patience.
	var waited := 0.0
	while waited < 20.0 and (game.get("controller") == null or game.bodies.size() < 1):
		await physics_frame
		waited += 0.016
	if game == null or game.get("world_map") == null or game.get("town") == null:
		check(false, "the world opened with its square and its sheet")
		_finish()
		return
	check_no_world()
	check_guest()
	await check_home_from_the_road()
	await check_down_stays_down()
	await check_refused_in_the_ring()
	await check_refused_below()
	_finish()


func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	flow.active = false
	flow.world_start = "town"
	for path in [TEST_SAVE, WARBAND_SAVE]:
		_remove(path)
	print("FAST_TRAVEL_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


# --- the pieces the checks stand on ---------------------------------------

func _soul():
	return game.controller.focus_body()


## The whole band out on the lane, well past the gate: the ground a homecoming is
## actually for.
func _walk_out() -> void:
	var centre: Vector3 = game.town.global_position
	# The world's own answer for where the lane meets the town, not a second guess
	# at it: the band walks out along the road the map is drawn from.
	var gate: Vector3 = game.lane_end()
	var outward: Vector3 = gate - centre
	outward.y = 0.0
	if outward.length() < 1.0:
		outward = Vector3(0.0, 0.0, 1.0)
	outward = outward.normalized()
	var at: Vector3 = centre + outward * (game.town.WALL_RADIUS + 140.0)
	for index in game.bodies.size():
		var body = game.bodies[index]
		if body == null or not is_instance_valid(body):
			continue
		var spot: Vector3 = at + Vector3(float(index) * 1.8, 0.0, float(index) * 0.7)
		body.teleport_to(Terrain.grounded(Vector3(spot.x, 0.0, spot.z)) + Vector3(0.0, 0.2, 0.0), 0.0)


## Every body's ground, by instance: the answer "nobody moved" is taken in the
## same frame as the press, so a refusal has to leave these exactly as they are.
func _ground() -> Dictionary:
	var out := {}
	for body in game.bodies:
		if body != null and is_instance_valid(body):
			out[body.get_instance_id()] = body.global_position
	return out


func _unmoved(before: Dictionary, what: String) -> void:
	for body in game.bodies:
		if body == null or not is_instance_valid(body):
			continue
		var key: int = body.get_instance_id()
		if not before.has(key):
			continue
		var was: Vector3 = before[key]
		var now: Vector3 = body.global_position
		check(now.distance_to(was) < 0.001,
			"%s leaves %s where it stood" % [what, str(body.name)])


## The tile of the town that a body stands on: its own muster post, in XZ.
func _on_its_post(body, index: int) -> bool:
	var posts: Array = game.town.spawn_posts()
	var post: Vector3 = posts[index % posts.size()]
	var want: Vector3 = game.town.global_position + post
	var now: Vector3 = body.global_position
	var flat := Vector2(now.x - want.x, now.z - want.z)
	return flat.length() < 0.75


# --- the two answers that need no world -----------------------------------

func check_no_world() -> void:
	var refused: Dictionary = Travel.can_travel(null)
	check(not bool(refused.get("ok", true)), "there is no trip without a world")
	check(not str(refused.get("reason", "")).is_empty(),
		"and it says why (%s)" % str(refused.get("reason", "")))


## A guest does not own the world, and does not travel in it: the press is refused
## with a line and nothing on the field moves.
func check_guest() -> void:
	var guest := {"_client": true, "town": game.town, "controller": game.controller,
		"bodies": game.bodies, "squad": game.squad}
	var refused: Dictionary = Travel.can_travel(guest)
	check(not bool(refused.get("ok", true)), "a guest does not travel on its own")
	check(str(refused.get("reason", "")).to_lower().contains("guest"),
		"and is told whose call it is (%s)" % str(refused.get("reason", "")))
	var before := _ground()
	var result: Dictionary = Travel.travel(guest)
	check(not bool(result.get("ok", true)), "a guest's press goes nowhere")
	_unmoved(before, "a guest's press")


# --- home from the lane ---------------------------------------------------

func check_home_from_the_road() -> void:
	var field: int = game.bodies.size()
	check(field > 0, "the road has a band to bring home (%d bodies)" % field)
	if field == 0:
		return
	# A book with no bookmark reads as a band that has never stood anywhere: the
	# lane writes its own the moment the party is out on it, and the trip home has
	# to move it on to the square.
	warband.clear_checkpoint()
	_walk_out()
	await create_timer(0.2).timeout
	check(warband.checkpoint_id() == "trail_start",
		"the lane writes its own bookmark (%s)" % warband.checkpoint_id())

	game.world_map.open()
	check(game.world_map.is_open(), "the sheet is open on the press")
	var verdict: Dictionary = Travel.can_travel(game)
	check(bool(verdict.get("ok", false)),
		"the lane may travel home (%s)" % str(verdict.get("reason", "")))
	check(game.world_map.travel_line().to_upper().contains("HEARTHSTEAD"),
		"the sheet offers the way home (%s)" % game.world_map.travel_line())

	var result: Dictionary = game.world_map.travel_home()
	check(bool(result.get("ok", false)),
		"the press takes the band home (%s)" % str(result.get("reason", "")))
	check(int(result.get("moved", -1)) == field,
		"the whole field travels (%d of %d)" % [int(result.get("moved", -1)), field])
	check(bool(result.get("checkpoint", false)),
		"the trip drops a bookmark through the world's own save path")
	check(game.bodies.size() == field,
		"the trip spawns and loses no body (%d of %d)" % [game.bodies.size(), field])
	for index in game.bodies.size():
		var body = game.bodies[index]
		check(body != null and is_instance_valid(body), "body %d is still in the field" % index)
		if body == null or not is_instance_valid(body):
			continue
		check(game.town.in_square(body), "%s stands in the square" % str(body.name))
		check(_on_its_post(body, index), "%s stands on its own muster post" % str(body.name))
	var soul = _soul()
	check(soul != null and is_instance_valid(soul) and game.town.in_square(soul),
		"the soul rides a body in the square")
	check(warband.checkpoint_id() == "town",
		"the trip writes the town bookmark (%s)" % warband.checkpoint_id())
	check(warband.checkpoint_area() == "town", "and says so")
	check(warband.checkpoint_label() == "HEARTHSTEAD",
		"under the square's own label (%s)" % warband.checkpoint_label())

	# In the square the door is shut, and the sheet says which door and why.
	var again: Dictionary = game.world_map.travel_home()
	check(not bool(again.get("ok", true)), "a band in the square cannot travel home again")
	check(str(again.get("reason", "")).to_lower().contains("square"),
		"and is told it is already there (%s)" % str(again.get("reason", "")))
	check(game.world_map.travel_line().to_lower().contains("square"),
		"the sheet says so too (%s)" % game.world_map.travel_line())
	var before := _ground()
	_unmoved(before, "a second press home")


## A trip moves the bodies that can walk. A body on its chest is left where it
## fell and woken by nobody: travel is not a revive.
func check_down_stays_down() -> void:
	_walk_out()
	await create_timer(0.2).timeout
	# A campaign opens with one body, and the fall below needs a second one to
	# put on its chest. Swearing a name is how the game stands a body: the
	# roster takes it and the world's own field sync - the step that runs
	# `controller.spawn_mercenaries([muster post], true, [id])` and appends the
	# body to `bodies` - seats it beside the party, which is out on the lane by
	# now. Calling `spawn_mercenaries` here instead would stand the body up but
	# leave `game.bodies` without it, and the sync would then skip the name.
	warband.add_mercenary("Wedge")
	var seated := 0.0
	while seated < 2.0 and game.bodies.size() < 2:
		await physics_frame
		seated += 0.016
	var faller = null
	var soul = _soul()
	for body in game.bodies:
		if body == null or not is_instance_valid(body) or body == soul:
			continue
		if bool(body.get("alive")) and not bool(body.get("downed")):
			faller = body
			break
	check(faller != null, "the band has a body to put on its chest")
	if faller == null:
		return
	faller.take_damage(9999.0, 99)
	check(bool(faller.get("downed")), "the body goes down on the lane")
	var fell_at: Vector3 = (faller as Node3D).global_position
	var standing := 0
	for body in game.bodies:
		if body != null and is_instance_valid(body) and bool(body.get("alive")) \
				and not bool(body.get("downed")):
			standing += 1
	var result: Dictionary = game.world_map.travel_home()
	check(bool(result.get("ok", false)),
		"the band travels home past its fallen (%s)" % str(result.get("reason", "")))
	check(int(result.get("moved", -1)) == standing,
		"the trip moves only the bodies that can walk (%d of %d)" % [
			int(result.get("moved", -1)), standing])
	check(is_instance_valid(faller) and bool(faller.get("downed")),
		"the fallen body is still on its chest")
	check(is_instance_valid(faller)
		and (faller as Node3D).global_position.distance_to(fell_at) < 2.0,
		"and still where it fell")
	check(is_instance_valid(faller) and not game.town.in_square(faller),
		"not carried into the square")
	for body in game.bodies:
		if body == null or not is_instance_valid(body) or body == faller:
			continue
		check(game.town.in_square(body), "%s came home" % str(body.name))


# --- the two fights that hold the band ------------------------------------

## The ring is a fight the campaign does not let a body walk out of, so the trip
## is refused in the ring's own words and the field stays in it.
func check_refused_in_the_ring() -> void:
	var entered: Dictionary = game.arena.enter("easy")
	check(bool(entered.get("ok", false)),
		"the ring takes the band (%s)" % str(entered.get("message", "")))
	check(game.arena.is_open(), "and holds the fight")
	var verdict: Dictionary = Travel.can_travel(game)
	check(not bool(verdict.get("ok", true)), "the ring refuses the trip")
	check(str(verdict.get("reason", "")).to_lower().contains("ring"),
		"and names the ring (%s)" % str(verdict.get("reason", "")))
	check(game.world_map.travel_line().to_lower().contains("ring"),
		"the sheet says the same (%s)" % game.world_map.travel_line())
	var before := _ground()
	var result: Dictionary = game.world_map.travel_home()
	check(not bool(result.get("ok", true)), "the press in the ring is refused")
	_unmoved(before, "a refused trip in the ring")
	game.arena.leave()


## The Hollow is the other fight: a party below travels when it has climbed out,
## not while it is down the shaft.
func check_refused_below() -> void:
	var ids: Array = []
	for body in game.bodies:
		if body == null or not is_instance_valid(body):
			continue
		if not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		var merc_id: int = game.controller.merc_of(body)
		if merc_id > 0:
			ids.append(merc_id)
	check(not ids.is_empty(), "the party has a body to send down (%s)" % str(ids))
	var descended: Dictionary = await game.delve_area.descend(ids)
	check(bool(descended.get("ok", false)),
		"the party went down (%s)" % str(descended.get("message", "")))
	check(game.delve_area.below(), "and the Hollow holds it")
	var verdict: Dictionary = Travel.can_travel(game)
	check(not bool(verdict.get("ok", true)), "below, the trip is refused")
	check(str(verdict.get("reason", "")).to_lower().contains("hollow"),
		"and names the Hollow (%s)" % str(verdict.get("reason", "")))
	check(game.world_map.travel_line().to_lower().contains("hollow"),
		"the sheet says the same (%s)" % game.world_map.travel_line())
	var before := _ground()
	var result: Dictionary = game.world_map.travel_home()
	check(not bool(result.get("ok", true)), "the press below is refused")
	_unmoved(before, "a refused trip below")
	for body in game.bodies:
		if body == null or not is_instance_valid(body):
			continue
		check(not game.town.in_square(body), "%s is not pulled up into the square" % str(body.name))
