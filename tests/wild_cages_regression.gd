extends SceneTree
## The watch camps and the cage line: the two pieces of content the quartermaster's
## first two orders are actually played against.
##
## The module is proved against the real campaign world rather than a stub -
## `scenes/warband_world.tscn` is instantiated, seated and then handed the two
## nodes exactly as the world will hand them - because every rule here is a rule
## about the wood: the cage line's clearance from a lane a body walks, the camps'
## distance from the town's wall, the latch on the same `G` the camp uses, and a
## warden's death reaching the world's one kill handler.
##
## What is measured:
##
##   1. **The line.** Four cages, four ragged prisoners, four latches - each cage
##      on the ground, inside its 6-9 m band and well clear of the walked line.
##   2. **The latch.** Bare hands answer the press and change nothing; a blade in
##      reach cuts exactly one cage; a second press does nothing; four presses put
##      four names on the roll and four marks on the rescue order.
##   3. **The warren.** Three camps, twenty-one `hollow_warden` bodies, every one
##      of them in the world's hostile list, on the ground, off the lane and clear
##      of the town's wall - and one of them killed through the signal path counts
##      toward the watcher bounty.
##
## Bodies are moved by setting `global_position`; nothing here walks the 900 m of
## wood, so the whole run is a few seconds of simulation on top of the world's
## own build.

const WORLD := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://wild_cages_player.json"
const WARBAND_SAVE := "user://wild_cages_warband.json"
const CagesScript = preload("res://scripts/warband/soldier_cages.gd")
const WarrenScript = preload("res://scripts/warband/watcher_warren.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const RunForestScript = preload("res://scripts/warband/run_forest.gd")
const State = preload("res://scripts/player_state.gd")
const Damage = preload("res://scripts/warband/damage_scaler.gd")

## The world's own build is a heightfield and a wood; this is the ceiling for it.
const WORLD_TIMEOUT := 45.0
## Four doors, four walks and four fades, all started within a second of one
## another: 4 s of animation, and the rest is slack.
const FREE_TIMEOUT := 12.0
## Nothing solid within 6 m of the lane's centre line. The walked band's own rule
## is `RunForestScript.CLEAR_HALF`; the cage line keeps a wider one.
const CAGE_CLEARANCE := 6.0
## A body's own footprints off the lane, as the camps are laid.
const LATERAL_MIN := 18.0
const LATERAL_MAX := 40.0
## The same clearance the watchers must keep off the town's wall.
const WALL_CLEARANCE := 14.0
## A settled mob stands this close to the analytic ground.
const GROUND_TOLERANCE := 0.6
## One poll of the cage marker plus a frame.
const POLL_WAIT := 0.5

var game
var warband
var state
var flow
var cages
var warren
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WILD_CAGES_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	Damage.reset()
	flow.active = false
	# A campaign that is already in the world: the square is the seat, so no
	# opening card is raised over a test that never plays the lesson.
	flow.world_start = "town"

	game = load(WORLD).instantiate()
	root.add_child(game)
	current_scene = game
	var ready := await _await(func() -> bool: return _world_ready(), WORLD_TIMEOUT)
	if not ready:
		check(false, "the world built inside %.0f s" % WORLD_TIMEOUT)
		_finish()
		return
	check(true, "the campaign world built")

	var quests = warband.quests
	check(quests.offer("free_the_soldiers"), "the quartermaster offers the cage line")
	check(bool(quests.accept("free_the_soldiers").get("ok", false)),
		"and the rescue order is taken")
	check(quests.offer("cull_the_watchers"), "he offers the watcher bounty")
	check(bool(quests.accept("cull_the_watchers").get("ok", false)),
		"and the kill order is taken")

	var body = game.controller.active_body(1)
	check(body != null, "a body is seated in the world")
	if body == null:
		_finish()
		return
	var roster_before: int = warband.roster.count()

	await _check_cages()
	await _check_warren(quests)
	_check_latches(body)
	await _check_rescue(body, quests, roster_before)
	_finish()


# --- 1. the cage line ------------------------------------------------------

func _check_cages() -> void:
	cages = CagesScript.new()
	cages.name = "SoldierCages"
	game.add_child(cages)
	cages.setup(game)
	check(cages.cages().size() == 4, "four cages stand on the way to town")
	check(cages.open_cages().size() == 4, "and each of them has a shut latch")
	check(cages.remaining() == 4, "nothing on the line is open yet")
	check(cages.freed() == 0, "and nobody has been freed")

	var path = game.trail.forest.get("path")
	check(path != null, "the world published the lane's own path")
	var on_ground := 0
	var clear := 0
	var banded := 0
	var soldiers := 0
	var offsets: Array[float] = []
	for index in cages.cages().size():
		var cage: Node3D = cages.cages()[index]
		var at: Vector3 = cage.global_position
		var floor: float = TerrainScript.height_at(at.x, at.z)
		if absf(at.y - floor) <= 0.02:
			on_ground += 1
		var lateral: float = path.distance_to(Vector2(at.x, at.z))
		offsets.append(lateral)
		# The cage's own footprint reaches 1.25 m back toward the road, and it is
		# that edge - not the centre - that must keep out of the walked band.
		if lateral - CagesScript.CAGE_HALF >= CAGE_CLEARANCE:
			clear += 1
		if lateral >= CagesScript.CAGE_LATERAL_MIN - 0.01 \
				and lateral <= CagesScript.CAGE_LATERAL_MAX + 0.01:
			banded += 1
		var soldier = cage.get_node_or_null("CagedSoldier")
		if soldier != null and is_instance_valid(soldier) and soldier.has_method("apply_loadout"):
			soldiers += 1
		check(lateral - CagesScript.CAGE_HALF >= RunForestScript.CLEAR_HALF,
			"cage %d keeps the walked band clear of its bars (%.2f m from the line)"
			% [index + 1, lateral])
	check(on_ground == 4, "every cage stands on the ground (%d of 4)" % on_ground)
	check(clear == 4, "no cage comes inside %.1f m of the lane (%d of 4)"
		% [CAGE_CLEARANCE, clear])
	check(banded == 4, "every cage stands in its own 6-9 m band (%d of 4)" % banded)
	check(soldiers == 4, "one ragged soldier waits in each cage (%d of 4)" % soldiers)
	print("WILD_CAGES_CAGES offsets=%s metres=%s" % [
		str(offsets.map(func(v: float) -> String: return "%.2f" % v)),
		str(cages.cages().map(func(c: Node3D) -> String:
			return "(%.1f,%.1f)" % [c.global_position.x, c.global_position.z]))])

	# Real furniture, not a picture: three walls of bars and a door that carries
	# its own collider so the opening lifts with it.
	var walled := 0
	var doored := 0
	for cage in cages.cages():
		var bars = (cage as Node3D).get_node_or_null("CageBars")
		if bars != null and bars.get_child_count() == 3 \
				and bars.collision_layer == 1 and bars.collision_mask == 0:
			walled += 1
		var door = (cage as Node3D).get_node_or_null("Door")
		var door_bars = door.get_node_or_null("DoorBars") if door != null else null
		if door_bars != null and door_bars.get_child_count() == 1 \
				and door_bars.collision_layer == 1:
			doored += 1
	check(walled == 4, "every cage has three standing walls of bars (%d of 4)" % walled)
	check(doored == 4, "and a door whose collider rises with it (%d of 4)" % doored)

	check(cages.marker_points().size() == 4, "every shut cage is a point on the map")

	# The arrow points at the nearest shut cage while the rescue order is on the
	# roll. The body is on the town square, so that is the last cage on the line.
	await create_timer(POLL_WAIT).timeout
	var marker = cages.get_node_or_null("FreeHimMarker")
	check(marker != null, "the gold arrow exists")
	check(marker != null and marker.visible and marker.attached(),
		"the arrow marks a shut cage while the order is open")
	check(marker != null and marker.target() == cages.cages()[3],
		"and it is the nearest shut cage to the body")


# --- 2. the warren ---------------------------------------------------------

func _check_warren(quests) -> void:
	warren = WarrenScript.new()
	warren.name = "WatcherWarren"
	game.add_child(warren)
	warren.setup(game)
	await create_timer(0.6).timeout

	check(warren.total() == 21, "the warren is three camps of seven (%d)" % warren.total())
	check(warren.camps().size() == 3, "three camps stand in the wood near the town")
	check(warren.mobs().size() == 21, "twenty-one wardens were fielded (%d)"
		% warren.mobs().size())
	check(warren.living() == 21, "and all of them are on their feet (%d)" % warren.living())
	check(warren.camp_points().size() == 3, "each camp is a place on the map")

	var town_centre: Vector3 = game.town.global_position
	var wall := TownScript.WALL_RADIUS
	var on_ground := 0
	var outside := 0
	var listed := 0
	var named := 0
	var banded := 0
	var path = game.trail.forest.get("path")
	for mob in warren.mobs():
		var at: Vector3 = mob.global_position
		if absf(at.y - TerrainScript.height_at(at.x, at.z)) <= GROUND_TOLERANCE:
			on_ground += 1
		if _flat(at, town_centre) >= wall + WALL_CLEARANCE:
			outside += 1
		if game.guards.has(mob):
			listed += 1
		if str(mob.mob_id) == "hollow_warden":
			named += 1
		var lateral: float = path.distance_to(Vector2(at.x, at.z))
		if lateral >= LATERAL_MIN and lateral <= LATERAL_MAX:
			banded += 1
	check(on_ground == 21, "every warden stands on the ground (%d of 21)" % on_ground)
	check(outside == 21, "every warden keeps %.0f m off the town's wall (%d of 21)"
		% [wall + WALL_CLEARANCE, outside])
	check(listed == 21, "every warden is on the world's one hostile list (%d of 21)" % listed)
	check(named == 21, "every warden is a hollow warden (%d of 21)" % named)
	check(banded == 21, "every warden stands 18-40 m off the lane (%d of 21)" % banded)

	# A kill through the mob's own signal path reaches the world's handler and the
	# ledger: this is the bounty's whole chain.
	var prey = warren.mobs()[0]
	var before: int = quests.progress_of("cull_the_watchers")
	prey.take_damage(4000.0, 0)
	await create_timer(0.3).timeout
	check(quests.progress_of("cull_the_watchers") == before + 1,
		"a warden's death counts toward the bounty (%d -> %d)"
		% [before, quests.progress_of("cull_the_watchers")])
	check(warren.living() == 20, "and one body fewer stands (%d)" % warren.living())
	print("WILD_CAGES_WARREN camps=%s mobs=%d" % [
		str(warren.camp_points().map(func(p: Vector3) -> String:
			return "(%.1f,%.1f)" % [p.x, p.z])), warren.mobs().size()])


# --- 3. the latch ----------------------------------------------------------

func _check_latches(body) -> void:
	# Bare hands: the press is answered - the cage line owns the key it was meant
	# for - and nothing opens.
	body.rig.apply_loadout(State.build_loadout("", "", {}))
	check(not cages.holds_blade(body), "a body with empty hands holds no blade")
	var first: Node3D = cages.cages()[0]
	_stand_at(body, first)
	check(cages.latch_target(body) == 0, "the first latch is in reach from the bars")
	check(cages.interact(body), "the press at the bars is answered")
	check(not cages.open_cages()[0], "bare hands leave the cage shut")
	check(cages.remaining() == 4, "and the line has not moved (%d shut)" % cages.remaining())

	# A makeshift blade in the hand: one press, one cage.
	body.rig.apply_loadout(State.build_loadout("dagger_ironwood", "", {}))
	check(cages.holds_blade(body), "a dagger in the hand is a blade")


func _check_rescue(body, quests, roster_before: int) -> void:
	for index in 4:
		var node: Node3D = cages.cages()[index]
		_stand_at(body, node)
		var shut_before: int = cages.remaining()
		check(cages.latch_target(body) == index,
			"cage %d's latch is in reach from where the body stands" % (index + 1))
		check(cages.interact(body), "cage %d's press is consumed" % (index + 1))
		check(cages.remaining() == shut_before - 1,
			"exactly one cage opened (%d shut, was %d)" % [cages.remaining(), shut_before])
		check(cages.open_cages()[index], "cage %d stands open" % (index + 1))
		check(not cages.interact(body), "a second press on an open cage does nothing")
		check(not cages.open_latch(index), "and open_latch refuses the same cage twice")

	var done := await _await(func() -> bool: return cages.freed() == 4, FREE_TIMEOUT)
	check(done, "four doors lifted, four soldiers walked out (%d freed)" % cages.freed())
	check(cages.remaining() == 0, "the line is open (%d shut)" % cages.remaining())
	check(cages.marker_points().is_empty(), "an open line has nothing left to mark")
	var lifted := 0
	for cage in cages.cages():
		var door = (cage as Node3D).get_node_or_null("Door")
		if door != null \
				and absf((door as Node3D).position.y - CagesScript.CAGE_BAR_LIFT) <= 0.02:
			lifted += 1
	check(lifted == 4, "every door stands %.1f m clear of its cage (%d of 4)"
		% [CagesScript.CAGE_BAR_LIFT, lifted])

	# One roster record per cage, and no more: the world's one rescue call is what
	# puts a name on the roll.
	check(warband.roster.count() == roster_before + 4,
		"four cages put four bodies on the roll (%d -> %d)"
		% [roster_before, warband.roster.count()])
	var names: Array[String] = []
	for merc in warband.roster.records():
		names.append(str(merc.get("name", "")))
	var on_roll := 0
	for soldier in CagesScript.SOLDIER_NAMES:
		var count := names.count(str(soldier))
		if count == 1:
			on_roll += 1
		check(count == 1, "%s is on the roll exactly once (%d)" % [soldier, count])
	check(on_roll == 4, "every freed soldier is a name on the roll (%d of 4)" % on_roll)
	check(quests.progress_of("free_the_soldiers") == 4,
		"the rescue order counted all four (%d of %d)"
		% [quests.progress_of("free_the_soldiers"),
			quests.goal_count("free_the_soldiers")])

	# The cages stay open and empty, and the arrow is gone with the order's work.
	# The figures dissolve after the name is booked, so this waits for the fade.
	var emptied_of := func() -> bool:
		for cage in cages.cages():
			if (cage as Node3D).get_node_or_null("CagedSoldier") != null:
				return false
		return true
	var emptied := await _await(emptied_of, 4.0)
	check(emptied, "every cage stands open and empty")
	await create_timer(POLL_WAIT).timeout
	var marker = cages.get_node_or_null("FreeHimMarker")
	check(marker != null and not marker.visible and not marker.attached(),
		"the arrow is hidden once every latch is cut")


# --- helpers ---------------------------------------------------------------

func _world_ready() -> bool:
	if game == null or not game.has_method("stats"):
		return false
	var trail = game.get("trail")
	if trail == null:
		return false
	var forest = trail.get("forest")
	if not (forest is Dictionary) or (forest as Dictionary).get("path") == null:
		return false
	var controller = game.get("controller")
	if controller == null:
		return false
	return controller.active_body(1) != null


## Stand a body at a cage's door: outside the bars, on the ground, at the latch.
func _stand_at(body, cage: Node3D) -> void:
	var toward: Vector3 = cage.global_basis * Vector3(0.0, 0.0, -1.0)
	toward.y = 0.0
	toward = toward.normalized()
	var at: Vector3 = cage.global_position + toward * (CagesScript.CAGE_HALF + 1.0)
	body.global_position = Vector3(at.x, TerrainScript.height_at(at.x, at.z) + 0.25, at.z)
	body.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Wait on a condition without spinning the frame: the world's own clocks have to
## run for a door to lift and a soldier to walk.
func _await(condition: Callable, seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	var budget := int(seconds * 1000.0)
	while Time.get_ticks_msec() - started < budget:
		if bool(condition.call()):
			return true
		await create_timer(0.1).timeout
	return bool(condition.call())


func _finish() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WILD_CAGES_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
