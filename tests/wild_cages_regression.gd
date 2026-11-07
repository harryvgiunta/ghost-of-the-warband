extends SceneTree
## The watch camps and the cage line: the two pieces of content the quartermaster's
## first two orders are actually played against.
##
## The module is proved against the real campaign world rather than a stub -
## `scenes/warband_world.tscn` is instantiated and the cages and camps it builds
## itself are the ones measured - because every rule here is a rule about the wood:
## the cage line's clearance from a lane a body walks, the camps' distance from the
## town's wall, the latch on the same `G` the camp uses, and a warden's death
## reaching the world's one kill handler.
##
## What is measured:
##
##   1. **The line.** One cage, `CAGE_FRACTIONS` long - the soldier the watchers
##      took, caged half way along the walk - on the ground, inside its 6-9 m band
##      and well clear of the walked line.
##   2. **The latch.** Bare hands answer the press and change nothing; a blade in
##      reach cuts the cage; a second press does nothing; the one press puts one
##      name on the roll and empties the rescue order's marker.
##   3. **The warren.** Every camp in `WatcherWarren.CAMPS`, `CAMP_SIZE`
##      `hollow_warden` bodies each, every one of them in the world's hostile
##      list, on the ground, off the lane and clear of the town's wall - one of
##      them killed through the signal path counts toward the watcher bounty, and
##      that camp alone refills its fallen on its own clock while the others are
##      left exactly as they stood.
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

## The world's own build is a heightfield and a wood; this is the ceiling for it.
const WORLD_TIMEOUT := 45.0
## The door's lift, the soldier's walk out and the fade, all started on the cut:
## 3.2 s of animation, and the rest is the marker's poll and slack.
const FREE_TIMEOUT := 12.0
## Nothing solid within 6 m of the lane's centre line. The walked band's own rule
## is `RunForestScript.CLEAR_HALF`; the cage line keeps a wider one.
const CAGE_CLEARANCE := 6.0
## A camp body's own distance from the lane, as the camps are laid. The band's
## floor is the rule that matters: a warden's sight is 60 m, so nothing may stand
## inside 70 and the road must never be able to pull a camp.
const LATERAL_MIN := 70.0
const LATERAL_MAX := 120.0
## How far a body may end up from where it was put while it stands on the road:
## a warden that converged on it would shove it twice that in a breath.
const STAND_DRIFT := 2.0
## How far a calm warden may stand from its own camp's dressing: the spawn ring
## plus the patch it roams, with room to spare. A camp that had converged on the
## road would be tens of metres out.
const RING_REACH := 14.0
## Half a second of simulation at each camp in the table: enough for the far
## band's own tick to take a sighting, if a sighting were possible.
const ROAD_FRAMES := 30
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

	var body = game.controller.active_body(1)
	check(body != null, "a body is seated in the world")
	if body == null:
		_finish()
		return
	# The world's own wiring, not a second copy: one cage line, one warren, one
	# loot hand and one map sheet are what a campaign opens with.
	check(game.soldier_cages != null, "the world fields the cage line")
	check(game.watcher_warren != null, "and the watcher warren")
	check(game.loot_hand != null, "the loot hand is built with the vacuum")
	check(game.world_map != null, "the map sheet is built with the world")
	check(game.map_markers().size()
			== CagesScript.CAGE_FRACTIONS.size() + WarrenScript.CAMPS.size(),
		"the map is told where every cage and every camp stands (%d)"
			% game.map_markers().size())
	var roster_before: int = warband.roster.count()
	# The campaign opens one naked body strong (`Warband.STARTING_BAND`): the cage
	# line is the only place the wood adds a name to that band, so every count
	# below is measured against this one.
	check(roster_before == warband.STARTING_BAND.size(),
		"the campaign opens with the starting band (%d of %d)"
			% [roster_before, warband.STARTING_BAND.size()])

	await _check_cages()
	await _check_warren(body)
	_check_latches(body)
	await _check_rescue(body, roster_before)
	_finish()


# --- 1. the cage line ------------------------------------------------------

func _check_cages() -> void:
	# The world builds the cage line itself (`_build_orders`), so this adopts the
	# instance the campaign actually plays against instead of adding a second one
	# beside it: a duplicated line would double the soldiers in the wood while
	# every assertion here still passed.
	cages = game.soldier_cages
	check(cages != null and is_instance_valid(cages), "the world builds the cage line")
	if cages == null:
		return
	# The line's length is the product's own table, never a literal: one fraction
	# is one cage, one prisoner and one latch.
	var count: int = CagesScript.CAGE_FRACTIONS.size()
	check(cages.cages().size() == count,
		"the line fields one cage per fraction (%d of %d)"
			% [cages.cages().size(), count])
	check(cages.open_cages().size() == count, "and each of them has a shut latch")
	check(cages.remaining() == count, "nothing on the line is open yet (%d shut)"
		% cages.remaining())
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
	check(on_ground == count, "every cage stands on the ground (%d of %d)"
		% [on_ground, count])
	check(clear == count, "no cage comes inside %.1f m of the lane (%d of %d)"
		% [CAGE_CLEARANCE, clear, count])
	check(banded == count, "every cage stands in its own 6-9 m band (%d of %d)"
		% [banded, count])
	check(soldiers == count, "one ragged soldier waits in each cage (%d of %d)"
		% [soldiers, count])
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
	check(walled == count, "every cage has three standing walls of bars (%d of %d)"
		% [walled, count])
	check(doored == count, "and a door whose collider rises with it (%d of %d)"
		% [doored, count])

	check(cages.marker_points().size() == count,
		"every shut cage is a point on the map (%d of %d)"
			% [cages.marker_points().size(), count])

	# The arrow points at the nearest shut cage while the rescue order is on the
	# roll. The body is on the town square, at the town's end of the walk, so on a
	# line of one the last cage is the only candidate.
	await create_timer(POLL_WAIT).timeout
	var marker = cages.get_node_or_null("FreeHimMarker")
	check(marker != null, "the gold arrow exists")
	check(marker != null and marker.visible and marker.attached(),
		"the arrow marks a shut cage while the order is open")
	check(marker != null and marker.target() == cages.cages()[count - 1],
		"and it is the nearest shut cage to the body")


# --- 2. the warren ---------------------------------------------------------

func _check_warren(body) -> void:
	# The world builds the warren itself (`WorldScene._build_orders`), so this
	# adopts the instance the campaign plays against instead of adding a second
	# one beside it - two warrens would field the table's wardens twice over while
	# every assertion below still passed.
	warren = game.watcher_warren
	check(warren != null and is_instance_valid(warren), "the world builds the warren")
	if warren == null:
		return
	await create_timer(0.6).timeout

	# Every count is the camp table's own arithmetic: `CAMPS.size()` camps of
	# `CAMP_SIZE` bodies, and the module's `total()` is the table read back.
	var fielded: int = WarrenScript.CAMPS.size() * WarrenScript.CAMP_SIZE

	check(warren.total() == fielded, "the warren is %d camps of %d (%d)"
		% [WarrenScript.CAMPS.size(), WarrenScript.CAMP_SIZE, warren.total()])
	check(warren.camps().size() == WarrenScript.CAMPS.size(),
		"every camp in the table stands in the wood (%d)" % warren.camps().size())
	check(warren.mobs().size() == fielded, "%d wardens were fielded (%d)"
		% [fielded, warren.mobs().size()])
	check(warren.living() == fielded, "and all of them are on their feet (%d)"
		% warren.living())
	check(warren.camp_points().size() == WarrenScript.CAMPS.size(),
		"each camp is a place on the map")

	var town_centre: Vector3 = game.town.global_position
	var wall := TownScript.WALL_RADIUS
	var on_ground := 0
	var outside := 0
	var listed := 0
	var named := 0
	var closest := INF
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
		closest = minf(closest, path.distance_to(Vector2(at.x, at.z)))
	check(on_ground == fielded, "every warden stands on the ground (%d of %d)"
		% [on_ground, fielded])
	check(outside == fielded, "every warden keeps %.0f m off the town's wall (%d of %d)"
		% [wall + WALL_CLEARANCE, outside, fielded])
	check(listed == fielded, "every warden is on the world's one hostile list (%d of %d)"
		% [listed, fielded])
	check(named == fielded, "every warden is a hollow warden (%d of %d)"
		% [named, fielded])
	check(closest >= LATERAL_MIN,
		"no warden stands inside %.0f m of the lane (nearest is %.1f m)"
		% [LATERAL_MIN, closest])
	check(closest <= LATERAL_MAX,
		"and the nearest camp is still inside %.0f m of it (%.1f m)"
		% [LATERAL_MAX, closest])

	await _check_road_is_calm(body)

	# A kill through the mob's own signal path reaches the world's handler, pays
	# the purse and drops the steel: nothing counts it beyond that.
	var prey = warren.mobs()[0]
	var gold_before: int = warband.gold()
	prey.take_damage(4000.0, 0)
	await create_timer(0.3).timeout
	check(warband.gold() >= gold_before, "a warden's death leaves the purse no worse (%d -> %d)"
		% [gold_before, warband.gold()])
	check(warren.living() == fielded - 1, "and one body fewer stands (%d of %d)"
		% [warren.living(), fielded])

	# The wood is a place a party can farm, not a place it empties once: a camp
	# that lost a body gets *one* clock for the camp, and when it runs the fallen
	# warden comes back on his own post - asleep there like a fresh one - while the
	# camps that lost nothing are not touched at all.
	await create_timer(0.6).timeout
	var counting: float = warren.refill_in(0)
	check(counting > 0.0 and counting <= WarrenScript.RESPAWN_SECONDS,
		"the cut camp is counting down its refill (%.1f s of %.0f)"
			% [counting, WarrenScript.RESPAWN_SECONDS])
	check(warren.refill_in(1) < 0.0,
		"a camp nothing died in has no clock (%.1f)" % warren.refill_in(1))
	var before: Array = []
	for index in range(1, warren.camps().size()):
		before.append((warren.camps()[index]["mobs"] as Array).duplicate())
	var post: Vector3 = warren.camps()[0]["posts"][0]

	# The quiet hold, measured on the module's own refill seam: while a party body
	# stands inside the camp's `RESPAWN_QUIET`, the camp stays cut - a squad must
	# never have wardens appear inside its own sight. The stand is written and the
	# seam asked in the same frame, so nothing here walks or fights.
	body.global_position = post + Vector3(0.0, 0.5, 0.0)
	body.velocity = Vector3.ZERO
	check(_flat(body.global_position, post) < WarrenScript.RESPAWN_QUIET,
		"a body standing in the camp is inside the refill's quiet hold (%.1f m of %.0f)"
			% [_flat(body.global_position, post), WarrenScript.RESPAWN_QUIET])
	check(warren.refill_camp(0) == 0,
		"and the camp holds its refill while that body stands there")
	check(warren.living() == fielded - 1,
		"the fallen warden stays down until the squad leaves (%d of %d)"
			% [warren.living(), fielded])

	# Away from every camp - the town square, at the other end of the walk - the
	# same seam puts the camp back on its own posts. The hold is measured on the
	# nearest of that camp's posts, exactly as `_refill_one` measures it.
	body.global_position = game.town.global_position + Vector3(0.0, 0.5, 0.0)
	body.velocity = Vector3.ZERO
	var nearest_post := INF
	for point in warren.camps()[0]["posts"]:
		nearest_post = minf(nearest_post, _flat(body.global_position, point as Vector3))
	check(nearest_post > WarrenScript.RESPAWN_QUIET,
		"and the body stands clear of that hold before the refill is asked (%.1f m of %.0f)"
			% [nearest_post, WarrenScript.RESPAWN_QUIET])
	var back: int = warren.refill_camp(0)
	check(back == 1, "the camp refills only what it lost (%d bodies)" % back)
	check(warren.mobs().size() == fielded and warren.living() == fielded,
		"and the camp is whole again (%d bodies, %d standing of %d)"
			% [warren.mobs().size(), warren.living(), fielded])
	var camp_standing := 0
	for member in warren.camps()[0]["mobs"]:
		if is_instance_valid(member) and bool(member.get("alive")):
			camp_standing += 1
	check(camp_standing == WarrenScript.CAMP_SIZE,
		"the cut camp is back to its own %d wardens (%d standing)"
			% [WarrenScript.CAMP_SIZE, camp_standing])
	var revived = (warren.camps()[0]["mobs"] as Array)[0]
	check(is_instance_valid(revived) and bool(revived.get("alive")),
		"the warden is back on his feet")
	check(revived != null and str((revived as Node).name) == "HollowWarden1_1",
		"under the name the wire knows him by (%s)"
			% (str((revived as Node).name) if revived != null else "no body"))
	check(revived != null and game.guards.has(revived),
		"and back on the world's one hostile list")
	check(revived != null and (revived as Node).is_in_group("wild_mobs"),
		"as a wilderness body, so the culler and the packs find him")
	check(revived != null and _flat((revived as Node3D).global_position, post) < 0.6,
		"standing on his own post (%.2f m off)"
			% (_flat((revived as Node3D).global_position, post) if revived != null else -1.0))
	check(revived != null and (revived as Node3D).home.distance_to(post) < 0.01,
		"with that post as his home, so the leash holds")
	check(warren.refill_camp(0) == 0, "a second refill spawns nobody")
	check(warren.refill_in(0) < 0.0, "and the clock is spent until another body falls")
	var untouched := 0
	for index in range(1, warren.camps().size()):
		var mobs: Array = warren.camps()[index]["mobs"]
		for slot in mobs.size():
			if mobs[slot] == before[index - 1][slot]:
				untouched += 1
	# Every camp but the cut one, as the table lays them out.
	check(untouched == (WarrenScript.CAMPS.size() - 1) * WarrenScript.CAMP_SIZE,
		"the other camps are exactly the bodies they were (%d of %d)"
			% [untouched, (WarrenScript.CAMPS.size() - 1) * WarrenScript.CAMP_SIZE])
	print("WILD_CAGES_WARREN camps=%s mobs=%d" % [
		str(warren.camp_points().map(func(p: Vector3) -> String:
			return "(%.1f,%.2f,%.1f)" % [p.x, p.y, p.z])), warren.mobs().size()])


## A body standing on the lane at each camp's own fraction must leave the camps
## where they are. This is the road's rule and the reason the band starts at 70 m:
## a warden's sight is 60 m, and a camp that came off its patch every time the
## squad walked past would be a fight the warband never chose - and, at the old
## 18-40 m, seven bodies a camp standing in the lane the campaign has to walk.
func _check_road_is_calm(body) -> void:
	var path = game.trail.forest.get("path")
	# A warband body clamps itself to a square around the world origin
	# (`arena_actor.gd::bounds`), so a lane point outside it is not somewhere a
	# body can stand: the nearest the road lets it get is the bound. The stand is
	# clamped here for exactly the reason the body clamps itself.
	var reach := float(body.get("bounds"))
	var nearest := INF
	var drifted := 0.0
	for spec in WarrenScript.CAMPS:
		var frame: Dictionary = path.sample(path.total * float(spec["fraction"]))
		var lane: Vector3 = frame["position"]
		var land := Vector3(clampf(lane.x, -reach, reach), 0.0,
			clampf(lane.z, -reach, reach))
		var stood := Vector3(land.x, TerrainScript.height_at(land.x, land.z) + 0.25, land.z)
		body.global_position = stood
		body.velocity = Vector3.ZERO
		for tick in ROAD_FRAMES:
			await physics_frame
		drifted = maxf(drifted, _flat(body.global_position, stood))
		for mob in warren.mobs():
			if not is_instance_valid(mob) or not bool(mob.get("alive")):
				continue
			nearest = minf(nearest, _flat(mob.global_position, body.global_position))
	check(nearest >= 60.0,
		"a body on the lane is outside a warden's sight of every camp (%.1f m)" % nearest)
	check(drifted <= STAND_DRIFT,
		"and nothing shoves it while it stands there (%.2f m off the mark)" % drifted)

	# Every warden is still standing its own patch: a camp that had converged on
	# the road would be tens of metres from its own dressing.
	var walked_off := 0
	for camp in warren.camps():
		var centre: Vector3 = camp["centre"]
		for mob in camp["mobs"]:
			if not is_instance_valid(mob) or not bool(mob.get("alive")):
				continue
			if _flat(mob.global_position, centre) > RING_REACH:
				walked_off += 1
	check(walked_off == 0,
		"the road does not pull a camp off its patch (%d walked off)" % walked_off)


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
	check(cages.remaining() == CagesScript.CAGE_FRACTIONS.size(),
		"and the line has not moved (%d shut)" % cages.remaining())

	# A makeshift blade in the hand: one press, one cage.
	body.rig.apply_loadout(State.build_loadout("dagger_ironwood", "", {}))
	check(cages.holds_blade(body), "a dagger in the hand is a blade")


func _check_rescue(body, roster_before: int) -> void:
	# One press per cage, and the line's length is the product's own table.
	var line: int = cages.cages().size()
	var room_at_start: int = warband.field_room()
	var reserves_before: int = warband.roster.reserve_ids().size()
	for index in line:
		var node: Node3D = cages.cages()[index]
		_stand_at(body, node)
		var shut_before: int = cages.remaining()
		var room_before: int = warband.field_room()
		check(cages.latch_target(body) == index,
			"cage %d's latch is in reach from where the body stands" % (index + 1))
		check(cages.interact(body), "cage %d's press is consumed" % (index + 1))
		check(cages.remaining() == shut_before - 1,
			"exactly one cage opened (%d shut, was %d)" % [cages.remaining(), shut_before])
		check(cages.open_cages()[index], "cage %d stands open" % (index + 1))
		check(not cages.interact(body), "a second press on an open cage does nothing")
		check(not cages.open_latch(index), "and open_latch refuses the same cage twice")
		# The door lifts, the soldier walks out, and only then does the roll hear
		# about him: one press is one record and one mark, never the whole line at
		# once.
		var out := await _await(func() -> bool: return cages.freed() == index + 1,
			FREE_TIMEOUT)
		check(out, "cage %d's soldier walked out (%d freed)" % [index + 1, cages.freed()])
		check(warband.roster.count() == roster_before + index + 1,
			"one press puts one body on the roll (%d -> %d)"
			% [roster_before, warband.roster.count()])
		# With a place on the field he takes it where he stands, out at the cage;
		# past a full field he waits in the town's reserve and nothing stands up.
		var rescued_ids: Array[int] = warband.roster.ids()
		var rescued: int = rescued_ids[rescued_ids.size() - 1]
		await physics_frame
		await physics_frame
		var rescued_body = game.controller.body_of(rescued)
		if room_before > 0:
			check(not warband.roster.is_reserve(rescued), "cage %d's soldier takes a place on the field"
				% (index + 1))
			check(rescued_body != null and is_instance_valid(rescued_body)
				and _flat(rescued_body.global_position, node.global_position) < 4.0,
				"and stands up as a body at his cage (%s)" % (
					str(rescued_body.global_position) if rescued_body != null else "no body"))
		else:
			check(warband.roster.is_reserve(rescued),
				"cage %d's soldier, past a full field, waits in the reserve" % (index + 1))
			check(rescued_body == null, "and no body stands up for him out in the wood")
	check(warband.roster.reserve_ids().size()
			== reserves_before + maxi(0, line - room_at_start),
		"the field took %d of the line's %d and the rest wait in the reserve (%d waiting)"
		% [mini(line, room_at_start), line, warband.roster.reserve_ids().size()])

	check(cages.remaining() == 0, "the line is open (%d shut)" % cages.remaining())
	check(cages.marker_points().is_empty(), "an open line has nothing left to mark")
	var lifted := 0
	for cage in cages.cages():
		var door = (cage as Node3D).get_node_or_null("Door")
		if door != null \
				and absf((door as Node3D).position.y - CagesScript.CAGE_BAR_LIFT) <= 0.02:
			lifted += 1
	check(lifted == line, "every door stands %.1f m clear of its cage (%d of %d)"
		% [CagesScript.CAGE_BAR_LIFT, lifted, line])

	# One roster record per cage, and no more: the world's one rescue call is what
	# puts a name on the roll.
	check(warband.roster.count() == roster_before + line,
		"the line put %d bodies on the roll (%d -> %d)"
		% [line, roster_before, warband.roster.count()])
	var names: Array[String] = []
	for merc in warband.roster.records():
		names.append(str(merc.get("name", "")))
	var on_roll := 0
	for soldier in CagesScript.SOLDIER_NAMES:
		var found := names.count(str(soldier))
		if found == 1:
			on_roll += 1
		check(found == 1, "%s is on the roll exactly once (%d)" % [soldier, found])
	check(on_roll == CagesScript.SOLDIER_NAMES.size(),
		"every freed soldier is a name on the roll (%d of %d)"
			% [on_roll, CagesScript.SOLDIER_NAMES.size()])

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
