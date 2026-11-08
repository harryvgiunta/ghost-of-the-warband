extends SceneTree
## The trail through the wood, driven on the one world.
##
## The escape used to be a scene of its own: the camp's arch loaded it and its own
## gate loaded the town. Neither door exists any more, and the camp is gone with
## them. What this regression owns now is the middle of the world:
##
##   1. **The trail is a place.** A kilometre and a third long (1,250-1,500 m) and
##      9-12 m wide, at least 24 torches with a light each, dense tree walls, rags
##      and bones, gibbets and effigies, fires and ground litter - all from the
##      world's own art kits - inside a node/draw budget.
##   2. **It meets both ends.** Its first waypoint is a long run of wood past the
##      wood's own mouth and its last is the town's gate; the lane's walls stop at
##      the wood and at the settlement instead of capping the corridor.
##   3. **It is walkable.** A body placed at the lane's start and driven down it
##      with real intent covers a real stretch of it without leaving the walkable
##      width and without ever getting further from the town's gate. The run is
##      timed.
##   4. **It is a fight.** Twenty armed `CageWatcher`s in pairs down the road, each
##      leaving the body the scene registers as a corpse.
##   5. **No door, and a wipe is a defeat.** Reaching the far end changes nothing
##      and requests nothing; every body down leaves the roster exactly that way,
##      gathers nothing, and makes no transition.

const TrailScript = preload("res://scripts/warband/escape_run.gd")
const WoodScript = preload("res://scripts/warband/wood_boss.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")

const TEST_SAVE := "user://escape_run_state.json"
const WARBAND_SAVE := "user://escape_run_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## How long the walk may take before the test calls it a hang.
## A watchdog against a hang, not a performance budget: nine hundred metres of
## ground is ~170 s of game time and the headless frame rate is not the game's.
const WALK_LIMIT := 260.0
## The walk is played at this speed multiplier so a quarter-kilometre run fits in
## a regression; the recorded time is the game time the lane cost at 1x.
## The lane is a kilometre and a third now, so the walk is driven faster in real
## time to stay inside the suite's ceiling; the assertions are distances, states
## and game seconds, which are the campaign's own.
const WALK_SCALE := 4.2
## How much of the lane this test drives. The full traverse - 1,575 m, no scene
## change - is `warband_world_regression`'s claim and it makes it once; this test
## is the *area*: the lane is a corridor, the escort follows, and a stretch is
## enough to prove both without paying for the second kilometre twice.
const WALK_METRES := 420.0
## How long the escort is given to close on the soul at the far end, in scaled
## seconds: it walks the wood behind the soul rather than a lane.
const FOLLOW_S := 40.0

var state
var warband
var game
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("RUN_FAIL  ", message)


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
	var flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.world_start = "town"

	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	# The walk plays at 3x, and a Timer counts scaled time: this is ~500 s real.
	watchdog.wait_time = 1500.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	await check_the_world()
	await check_lane()
	check_art()
	check_pursuers()
	await check_chain()
	await kill_cultists()
	await check_walk()
	await check_follow()
	await check_no_door()
	await check_wipe()
	_finish()


func _on_watchdog() -> void:
	check(false, "the trail did not finish inside the watchdog")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "town"
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("ESCAPE_RUN_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _flat(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _dismiss_card() -> void:
	# There is no card any more: the opening offers tips, and none of them pauses
	# the tree. The name stays because every beat of this test calls it.
	if game != null and game.tips != null and is_instance_valid(game.tips):
		game.tips.hide()


## The world, opened at the town, with the trail ahead of it: what this test wants
## is the trail, not a lesson. The wood, the lane and the square are one scene, and
## the party is put on the lane's own first stretch, because a squad a kilometre
## and a third behind the soul is not an escort.
func check_the_world() -> void:
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	_dismiss_card()
	check(game.wood != null and game.trail != null and game.town != null,
		"the world built all three of its areas")
	check(game.start_area == "town", "a new campaign opens in the town (%s)" % game.start_area)
	var soul = game.controller.active_body(1)
	check(soul != null, "the soul is in a body")
	check(soul != null and game.town.in_square(soul),
		"and the body it is inside stands in the square")
	# The wood at the far end of the road is the Hollow's own, and optional: a
	# party walking the other way never has to meet him.
	check(game.wood.master_alive(), "the Horned Thing stands in his wood")
	check(game.wood.guards.size() == 3,
		"with his two keepers beside him (%d)" % game.wood.guards.size())
	# Seat the party on the lane's first stretch, on the ground, in a ring.
	var start: Vector3 = game.trail.forest["start"]
	var posts: Array = game._spawn_ring(start, game.bodies.size())
	for index in game.bodies.size():
		var actor = game.bodies[index]
		if is_instance_valid(actor):
			actor.global_position = posts[mini(index, posts.size() - 1)]
	await physics_frame
	await physics_frame
	_dismiss_card()
	soul = game.controller.active_body(1)
	check(soul != null, "the soul is seated in a body when the trail opens")
	check(soul != null and _flat(soul.global_position, start) < 8.0,
		"and the party stands on the lane's first stretch (%.1f m)"
		% (_flat(soul.global_position, start) if soul != null else -1.0))
	check(game.trail.guards.size() == game.trail.cultists.size() + TrailScript.ARCHER_COUNT,
		"the blade cultists and the two archer ambushes hold the trail (%d bodies, %d of them blades)"
		% [game.trail.guards.size(), game.trail.cultists.size()])
	# Where they stand is what matters (asserted with the lane, below): a mob's
	# `player` field is its current quarry, not a spawn-time script.


func check_lane() -> void:
	var forest: Dictionary = game.trail.forest
	var lane: PackedVector3Array = forest["lane"]
	check(lane.size() >= 8, "the lane has real waypoints (%d)" % lane.size())
	var measured := 0.0
	for index in range(lane.size() - 1):
		measured += lane[index].distance_to(lane[index + 1])
	var length := float(forest["length"])
	check(absf(measured - length) <= 0.01,
		"the reported length is the summed waypoints (%.2f vs %.2f)" % [length, measured])
	check(length >= 1250.0 and length <= 1500.0, "the lane is a long run (%.1f m)" % length)
	var width := float(forest["width"])
	check(width >= 9.0 and width <= 12.0, "the lane is %.1f m wide" % width)
	var torches: Array = forest["torches"]
	check(torches.size() >= 24, "%d torches light the lane" % torches.size())
	check(lane[lane.size() - 1].is_equal_approx(forest["arch"]),
		"the reported far end is the lane's last waypoint")
	var road_gap := _flat(lane[0], WoodScript.GATE_POINT)
	check(absf(road_gap - WoodScript.CAMP_TO_ROAD_METRES) < 1.0,
		"the lane begins %.0f m of wood past the wood's mouth (%.1f m)"
		% [WoodScript.CAMP_TO_ROAD_METRES, road_gap])
	check(road_gap >= 150.0, "and no torch of it stands in sight of the wood (%.0f m)" % road_gap)
	check(_flat(forest["arch"], game.town.global_position) <= 40.0,
		"the lane ends at the town (%.1f m from the square)"
		% _flat(forest["arch"], game.town.global_position))
	var lights := 0
	for host in (forest["groups"]["Torches"] as Node).get_children():
		for child in host.get_children():
			if child is OmniLight3D:
				lights += 1
	check(lights == torches.size(), "every torch carries its own light (%d/%d)" % [lights, torches.size()])
	print("ESCAPE_RUN_LANE length=%.1f width=%.1f torches=%d waypoints=%d"
		% [length, width, torches.size(), lane.size()])
	# There is no lane any more: no wall down either verge, no corridor cut through
	# the wood. What keeps the way passable is the clear line round its centre,
	# measured where a body actually walks - a ray either side at chest and shoulder
	# height, never inside 1.25 m of the centre line, so the narrowest gap a body
	# meets is 2.5 m. An arch it walks under is not a pinch; a trunk is.
	check(forest["root"].get_node_or_null("LaneWalls") == null,
		"the lane has no wall geometry to walk between")
	check(forest["root"].get_node_or_null("ForestField") == null,
		"the lane builds no band of its own on the world's ground")
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var path = forest["path"]
	var probe := PhysicsRayQueryParameters3D.new()
	probe.collision_mask = 1
	var clearance := INF
	var tightest := Vector3.ZERO
	var samples := 480
	for index in samples:
		var frame: Dictionary = path.sample(float(length) * float(index) / float(samples))
		var base: Vector3 = TerrainScript.grounded(frame["position"])
		for height in [1.35, 1.9]:
			var from := base + Vector3(0.0, float(height), 0.0)
			for side in [-1.0, 1.0]:
				probe.from = from
				probe.to = from + (frame["right"] as Vector3) * side * 2.6
				var hit: Dictionary = space.intersect_ray(probe)
				var gap := 2.6
				if not hit.is_empty():
					gap = _flat(hit["position"] as Vector3, from)
				if gap < clearance:
					clearance = gap
					tightest = from
	check(clearance >= 1.25,
		"the centre line keeps 2.5 m clear end to end (%.2f m at %.1f,%.1f)"
		% [clearance, tightest.x, tightest.z])
	print("ESCAPE_RUN_CLEAR half_width=%.2f tightest=%s" % [clearance, str(tightest)])


func check_art() -> void:
	var forest: Dictionary = game.trail.forest
	var groups: Dictionary = forest["groups"]
	for label in ["Trees", "Bushes", "Grass", "Hanging", "Omens", "Braziers", "Scatter",
			"Rocks", "Torches"]:
		check(groups.has(label), "the lane has its %s group" % label)
		if groups.has(label):
			check((groups[label] as Node).get_child_count() > 0,
				"the %s group has props (%d)" % [label, (groups[label] as Node).get_child_count()])
	# The far gate is the town's own now: the lane ends at a settlement gate, not
	# at a gate of its own.
	check(game.town.get_node_or_null("NorthGate") != null,
		"the lane's far end is the town's gate")
	check((groups["Hanging"] as Node).get_child_count() >= 12,
		"the hanging art is dense (%d hosts)" % (groups["Hanging"] as Node).get_child_count())
	check((groups["Omens"] as Node).get_child_count() >= 6,
		"gibbets/effigies/stakes stand along the verge")
	check((groups["Braziers"] as Node).get_child_count() >= 8,
		"the clearings and the road burn (%d fires)" % (groups["Braziers"] as Node).get_child_count())
	var stats: Dictionary = forest["stats"]
	check(int(stats.get("trees", 0)) >= 240, "the wood is dense: %d trees" % int(stats.get("trees", 0)))
	check(int(stats.get("bushes", 0)) >= 90, "undergrowth: %d bushes" % int(stats.get("bushes", 0)))
	check(int(stats.get("rocks", 0)) >= 150, "stone: %d rocks" % int(stats.get("rocks", 0)))
	check(int(stats.get("grass", 0)) >= 300, "the verge has grass: %d clumps" % int(stats.get("grass", 0)))
	var solids: StaticBody3D = forest["root"].solids
	check(solids.get_child_count() >= 280,
		"the wood and its walls are solid (%d shapes)" % solids.get_child_count())
	var draws := int(stats.get("draws", 0))
	var nodes := int(stats.get("nodes", 0))
	check(draws <= 700, "the lane stays inside its draw budget (%d multimesh)" % draws)
	check(nodes <= 2600, "the lane stays inside its node budget (%d nodes)" % nodes)
	print("ESCAPE_RUN_ART trees=%d bushes=%d rocks=%d grass=%d nodes=%d draws=%d shapes=%d"
		% [int(stats.get("trees", 0)), int(stats.get("bushes", 0)), int(stats.get("rocks", 0)),
			int(stats.get("grass", 0)), nodes, draws, solids.get_child_count()])


func check_pursuers() -> void:
	var armed := 0
	var visible := 0
	var hunting := 0
	for watcher in game.trail.guards:
		check(is_instance_valid(watcher) and bool(watcher.get("alive")), "a cultist is on its feet")
		if str(watcher.get("weapon_item")) != "":
			armed += 1
		if watcher.has_weapon_visual():
			visible += 1
		if bool(watcher.hunting()) and is_instance_valid(watcher.player):
			hunting += 1
		check(is_equal_approx(float(watcher.max_health), _pool_for(watcher)),
			"a road cultist carries its species' pool (%s of %s)"
			% [str(watcher.max_health), str(_pool_for(watcher))])
		# On the ground it was posted on, wherever that is: the trail is hill
		# country, so "y above zero" was a claim about the old flat floor, and a
		# cultist standing in a hollow at -15 m is a cultist on its feet.
		var ground := TerrainScript.height_at(watcher.global_position.x,
			watcher.global_position.z)
		check(absf(watcher.global_position.y - ground) < 1.5,
			"a cultist stands on the ground it was posted on (%.1f vs %.1f)"
			% [watcher.global_position.y, ground])
		check(watcher.safe_center.is_equal_approx(game.trail.town_gate()),
			"the town's gate is the safe ring, so nobody is hunted inside it")
	check(armed == game.trail.guards.size(), "every cultist holds a weapon (%d/%d)"
		% [armed, game.trail.guards.size()])
	check(visible >= 6, "the blade is in its hand (%d visible)" % visible)
	# The trail is the same first scenario as the wood and it pays the same way: a
	# corpse carries the makeshift rag and nothing above it, on the blade cultists
	# and the hidden archers alike.
	var above_tier: Array[String] = []
	for cultist in game.trail.guards:
		for item_id in cultist.gear_items():
			if str(item_id).begins_with("armor_") and not str(item_id).begins_with("armor_makeshift_"):
				above_tier.append(str(item_id))
	check(above_tier.is_empty(),
		"no trail corpse drops armour above the salvage tier (%s)" % str(above_tier))
	# The road answers the *leaving*: when the squad steps out of the clearing a
	# third of every ring is handed the soul, and no more. A cultist with a quarry
	# from spawn walks ninety metres into the party's own fight.
	check(hunting <= int(game.trail.guards.size() / 3) + 1,
		"only the leaving hands the road a quarry (%d of %d hunting)"
		% [hunting, game.trail.guards.size()])
	# The ambush stands well inside the trail rather than on the lane's own head:
	# a cultist sees 60 m, so anything closer joins the party's first fight.
	var start: Vector3 = game.trail.forest["start"]
	var near := 0
	for watcher in game.trail.guards:
		if _flat(watcher.global_position, start) <= 60.0:
			near += 1
	check(near == 0, "nobody stands within sight of the lane's head (%d within 60 m)"
		% near)
	# **The first fight of a campaign is the smallest one.** What a party out of the
	# gate meets first is the body nearest the town's gate, and it is a single
	# hollow runt: one body, a third of a warden's pool, and no partner within a
	# warden's reach. A ring of four full wardens at the first clearing was the bug
	# this holds shut - the road's chain is `TrailScript.CHAIN_*`.
	var gate: Vector3 = game.trail.town_gate()
	var first = null
	var nearest := INF
	for cultist in game.trail.cultists:
		if not is_instance_valid(cultist) or not bool(cultist.get("alive")):
			continue
		var distance := _flat(cultist.global_position, gate)
		if distance < nearest:
			nearest = distance
			first = cultist
	check(first != null, "the town end of the road is held")
	if first != null:
		check(str(first.get("mob_id")) == WatcherScript.RUNT_ID,
			"the first cultist out of the town gate is a hollow runt (%s)"
			% str(first.get("mob_id")))
		check(is_equal_approx(float(first.max_health), WatcherScript.RUNT_HEALTH),
			"at a third of a warden's pool (%s)" % str(first.max_health))
		var companions := 0
		for cultist in game.trail.cultists:
			if cultist == first or not is_instance_valid(cultist):
				continue
			if bool(cultist.get("alive")) \
					and _flat(cultist.global_position, first.global_position) < 20.0:
				companions += 1
		check(companions == 0, "and it stands alone (%d within 20 m)" % companions)
	check(game.squad != null and game.squad.following, "the squad is an escort on the road")
	check(game.squad.watchers == game.guards,
		"the squad fights the world's one hostile list, not a copy of it")


## The pool a body of that species is owed: a runt is a third of a hard body's, and
## a warden the hard pool itself, whatever the scene spawned it with.
func _pool_for(watcher) -> float:
	return WatcherScript.RUNT_HEALTH if str(watcher.get("mob_id")) == WatcherScript.RUNT_ID \
		else WatcherScript.HARDENED_HEALTH


## **The road is a chain.** The first band stands `CHAIN_FIRST` out of the town
## gate, the second `CHAIN_SECOND_STEP` beyond it, and every gap after that is drawn
## between `CHAIN_GAP_MIN` and `CHAIN_GAP_MAX` - so the wood is held ground a squad
## meets every fifty-odd metres, not four set-pieces with three hundred empty metres
## between them. Every band is also handed a disc to wander in: a band that never
## moves is a row of posts.
func check_chain() -> void:
	var gate: Vector3 = game.trail.town_gate()
	var marks: Array[float] = []
	for cultist in game.trail.cultists:
		if is_instance_valid(cultist):
			marks.append(_flat(cultist.global_position, gate))
	marks.sort()
	var bands: Array[float] = []
	for distance in marks:
		if bands.is_empty() or distance - float(bands[bands.size() - 1]) > 5.0:
			bands.append(distance)
	check(bands.size() >= 10, "the road is a chain, not a handful of camps (%d bands)"
		% bands.size())
	check(absf(float(bands[0]) - TrailScript.CHAIN_FIRST) <= 6.0,
		"the first band stands %.0f m out of the town gate (%.1f)"
		% [TrailScript.CHAIN_FIRST, float(bands[0])])
	var worst := 0.0
	for index in range(1, bands.size()):
		worst = maxf(worst, float(bands[index]) - float(bands[index - 1]))
	check(worst <= TrailScript.CHAIN_GAP_MAX + 6.0,
		"no gap in the chain is longer than %.0f m (%.1f)"
		% [TrailScript.CHAIN_GAP_MAX, worst])
	# The pieces: the makeshift tier in the hand, a board the only off-hand, and a
	# bow only in a body fielded as an archer.
	for cultist in game.trail.cultists:
		var main := str(cultist.get("weapon_item"))
		check(WatcherScript.MAKESHIFT_TIER.has(main),
			"a chain body carries the salvage tier (%s)" % main)
		var off := str(cultist.get("off_item"))
		check(off.is_empty() or off == "shield_wood",
			"and a board is the only off hand (%s)" % off)
		# The board is on the rig, not only in the roster's idea of the body: the
		# presenter straps it to the left hand and the rig wears it.
		check(bool(cultist.has_shield_visual()) == (off == "shield_wood"),
			"the board is actually strapped on the body (%s, %s)"
				% [off, str(cultist.has_shield_visual())])
		check(float(cultist.get("patrol_radius")) > 0.0, "and it is given a disc to walk")
	# Wandering, for real. A far-away body is parked by the culler (that is the
	# world's own LOD, not the band's), so the soul is stood ninety metres off the
	# first band - outside the fifty-five the world re-targets within, inside the
	# wake ring - and the band is watched for one leg of a patrol.
	var mover = null
	for cultist in game.trail.cultists:
		if is_instance_valid(cultist):
			mover = cultist
			break
	var watched = game.controller.active_body(1)
	check(mover != null and watched != null, "there is a band to watch")
	if mover != null and watched != null:
		var from: Vector3 = (mover as Node3D).global_position
		var away: Vector3 = from + Vector3(90.0, 0.0, 0.0)
		var home: Vector3 = (watched as Node3D).global_position
		(watched as Node3D).global_position = TerrainScript.grounded(Vector3(away.x, 0.0, away.z))
		await create_timer(6.0).timeout
		# Waited for, not assumed: a body woken by the culler settles for two to
		# four seconds before its first goal, and a pool of eight Godots stretching
		# the frame is not a fault in the band. Fifteen seconds is the ceiling for
		# one leg of a patrol.
		var moved := 0.0
		for step in 60:
			await create_timer(0.25).timeout
			if not is_instance_valid(mover):
				break
			moved = (mover as Node3D).global_position.distance_to(from)
			if moved > 0.5:
				break
		check(moved > 0.5, "the band walks its patch (%s moved %.2f m)"
			% [str(mover.name), moved])
		(watched as Node3D).global_position = home


func kill_cultists() -> void:
	# Everything on the field goes down, not just the cultists: this test drives
	# the ground, not a fight, and a live wolf or warden would decide the run.
	# Every pass is one more wave (the ambush a dead ring can call up).
	for pass_index in 4:
		for watcher in game.guards.duplicate():
			if is_instance_valid(watcher) and bool(watcher.get("alive")):
				watcher.take_damage(1000.0, 0)
		await create_timer(1.6).timeout
	check(game.trail.cultists_alive() == 0, "the trail can be cleared (%d left)"
		% game.trail.cultists_alive())
	check(game.loot.corpse_ids().size() >= game.trail.guards.size(),
		"every cultist is a lootable corpse (%d registered for %d bodies)"
		% [game.loot.corpse_ids().size(), game.trail.guards.size()])


# --- the walk --------------------------------------------------------------

## The proof that the lane is a corridor: real movement from the lane's start to
## the town's gate, sampled every physics tick for lateral drift and for distance
## to the gate.
func check_walk() -> void:
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var gate: Vector3 = game.trail.town_gate()
	var path = game.trail.forest["path"]
	var half := float(game.trail.forest["width"]) * 0.5
	var body = game.controller.active_body(1)
	check(body != null, "the soul still has a body for the walk")
	if body == null or not is_instance_valid(body):
		return
	body.global_position = lane[0] + Vector3(0.0, 0.1, 0.0)
	game.controller.input_enabled = false
	await physics_frame
	var previous := _flat(body.global_position, gate)
	var started_gap := previous
	var covered := 0.0
	var worst := 0.0
	var monotonic := true
	var worst_step := 0.0
	var index := 1
	var ticks := 0
	var last_gap := 9999.0
	var stall_ticks := 0
	var started := Time.get_ticks_msec()
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = WALK_SCALE
	while index < lane.size() and ticks < 20000:
		var to: Vector3 = lane[index] - body.global_position
		to.y = 0.0
		if to.length() <= 1.4:
			index += 1
			continue
		var direction := to.normalized()
		body.accept_network_input(Vector2(direction.x, direction.z), false)
		await physics_frame
		ticks += 1
		if not is_instance_valid(body) or bool(body.get("downed")) or not bool(body.get("alive")):
			break
		var lateral: float = path.distance_to(
			Vector2(body.global_position.x, body.global_position.z))
		worst = maxf(worst, lateral)
		var gap := _flat(body.global_position, gate)
		if gap > previous + 0.05:
			monotonic = false
			worst_step = maxf(worst_step, gap - previous)
		covered = started_gap - gap
		previous = gap
		if covered >= WALK_METRES:
			break
		# A player steps around a post; a straight-line driver pushes into it and
		# stays there. Sidestep for a beat whenever the ground stops being made.
		if absf(gap - last_gap) < 0.05:
			stall_ticks += 1
		else:
			stall_ticks = 0
		last_gap = gap
		if stall_ticks > 40:
			body.accept_network_input(Vector2(-direction.z, direction.x)
				* (1.0 if int(ticks / 40) % 2 == 0 else -1.0), false)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var game_seconds := float(ticks) / 60.0
	check(monotonic, "the walk never gets further from the town (worst +%.2f m)" % worst_step)
	check(worst <= half, "the body never leaves the %.1f m lane (%.2f m off centre)" % [half * 2.0, worst])
	check(covered >= WALK_METRES - 5.0,
		"the body walked its stretch of the lane (%.0f m of %.0f m)" % [covered, WALK_METRES])
	check(ticks < 20000 and real_seconds < WALK_LIMIT,
		"the run finished inside the watchdog (%.1f s real)" % real_seconds)
	check(root.get_node("GameFlow").transitions == 0, "walking the trail requests no scene")
	print("ESCAPE_RUN_WALK game_seconds=%.1f real_seconds=%.1f ticks=%d metres=%.0f lateral=%.2f"
		% [game_seconds, real_seconds, ticks, covered, worst])


## The escort: with the road clear, the squad closes on the soul wherever it is.
func check_follow() -> void:
	var soul = game.controller.active_body(1)
	check(soul != null, "the soul has a body for the escort to close on")
	if soul == null or not is_instance_valid(soul):
		return
	# The escort is every body on the field but the soul's own: a band that opens
	# as one naked body has no escort to prove, and one is not asked for here.
	var needed := mini(3, maxi(0, game.squad_ids.size() - 1))
	var near := 0
	var waited := 0.0
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = WALK_SCALE
	# The escort walks a forest, not a lane: it cuts corners, pushes past trunks and
	# comes up the rises behind the soul, so it is allowed a longer catch-up than the
	# flat corridor it used to run down.
	while near < needed and waited < FOLLOW_S:
		# A one-time lesson (the bandage card is the likely one after a long
		# walk) pauses the tree; read it so the escort can keep moving.
		_dismiss_card()
		await create_timer(0.1).timeout
		waited += 0.1
		near = 0
		for merc_id in game.squad_ids:
			if int(merc_id) == game.controller.merc_for_peer(1):
				continue
			var actor = game.controller.body_of(int(merc_id))
			if actor == null or not bool(actor.get("alive")) or bool(actor.get("downed")):
				continue
			if _flat(actor.global_position, soul.global_position) <= 20.0:
				near += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	# A failure here has to say *why*: three allies left behind because they are
	# still fighting, and three allies on the floor, are different bugs.
	var report: Array = []
	for merc_id in game.squad_ids:
		if int(merc_id) == game.controller.merc_for_peer(1):
			continue
		var ally = game.controller.body_of(int(merc_id))
		if ally == null or not is_instance_valid(ally):
			report.append("%d:gone" % int(merc_id))
			continue
		var nearest := INF
		for hostile in game.guards:
			if is_instance_valid(hostile) and bool(hostile.get("alive")):
				nearest = minf(nearest, _flat((hostile as Node3D).global_position,
					(ally as Node3D).global_position))
		var track: Dictionary = game.squad._track.get(int(merc_id), {})
		var stuck = game.squad._nearest_pickup(ally)
		var pick_info := "none"
		if is_instance_valid(stuck):
			pick_info = "%s d=%.2f armed=%s drop=%s col=%s block=%s" % [
				str(stuck.item_id), (stuck as Node3D).global_position.distance_to((ally as Node3D).global_position),
				str(stuck.armed), str(stuck.dropper_peer), str(stuck.collected),
				str(stuck.blocked_for(0))]
		report.append("%d:%.0fm%s%s:hostile=%.0fm:move=%.1f,%.1f:at=%.1f,%.1f:free=%s:pb=%s:state=%s:band=%s:nw=%s:np=%s:nc=%s:paused=%s:pick=%s" % [int(merc_id),
			_flat(ally.global_position, soul.global_position),
			"" if bool(ally.get("alive")) else ":dead",
			":down" if bool(ally.get("downed")) else "",
			-1.0 if nearest == INF else nearest,
			float(ally.get("move_direction").x), float(ally.get("move_direction").y),
			(ally as Node3D).global_position.x, (ally as Node3D).global_position.z,
			str(game.is_free_body(int(merc_id))),
			str(game.squad.player_body == soul),
			str(track.get("state", "?")), str(track.get("bandaging", "?")),
			str(is_instance_valid(game.squad._nearest_watcher(ally))),
			str(is_instance_valid(game.squad._nearest_pickup(ally))),
			str(game.squad._nearest_corpse(ally)),
			str(game.get_tree().paused), pick_info])
	check(near >= needed,
		"the squad follows the soul down the trail (%d of %d within 20 m after %.0f s; following=%s; %s)"
		% [near, needed, waited * WALK_SCALE, str(game.squad.following), ", ".join(report)])


# --- the end of the trail --------------------------------------------------

## The far end is the town's gate, and walking through it is not a door: the
## square is simply there, and nothing is requested.
func check_no_door() -> void:
	var body = game.controller.active_body(1)
	check(body != null, "a body stands at the far end of the trail")
	if body == null or not is_instance_valid(body):
		return
	var transitions_before: int = root.get_node("GameFlow").transitions
	body.global_position = game.trail.town_gate() + Vector3(0.0, 0.2, 0.0)
	await physics_frame
	game._try_interact()
	await create_timer(0.3).timeout
	check(root.get_node("GameFlow").transitions == transitions_before,
		"and makes no transition (%d)" % root.get_node("GameFlow").transitions)
	check(game.town.in_square(body) or _flat(body.global_position, game.town.global_position) < 40.0,
		"the town is simply there, on foot")
	check(game.town.service_at(game.town.global_position) == "",
		"the square's fire is not a service, so nothing was triggered by standing there")


## A wipe: every body down. There is no door to hand the warband through any more,
## so the world stops, the roster keeps the truth and nothing is gathered.
func check_wipe() -> void:
	if is_instance_valid(game):
		game.queue_free()
		game = null
	await process_frame
	await create_timer(0.2).timeout
	warband.clear_possession()
	root.get_node("GameFlow").world_start = "town"
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout
	# The opening card pauses the tree; a paused world cannot notice a wipe.
	_dismiss_card()
	# The world fields the whole living band - every living name not waiting in the
	# reserve, one body each (`PossessionController._spawn_ids`) - and a band that
	# opens as one naked body is one living name. The count is the band's, never a
	# literal: whatever the roster carries is what the wiped world must stand up.
	var field: int = 0
	for merc_id in warband.alive_merc_ids():
		if warband.roster.is_alive(int(merc_id)) and not warband.roster.is_reserve(int(merc_id)):
			field += 1
	check(field > 0 and game.bodies.size() == field,
		"the wiped world fields the whole living band (%d of %d)"
		% [game.bodies.size(), field])
	var gathered: int = warband.stash.pooled_total()
	var transitions_before: int = root.get_node("GameFlow").transitions
	for actor in game.bodies:
		actor.enter_downed(99)
	# The soul's own body raises the downed lesson (it pauses the tree); a wipe
	# is not a moment to leave a card up, so read it and let the world run.
	_dismiss_card()
	var waited := 0.0
	while not game._wiped and waited < 8.0:
		_dismiss_card()
		await create_timer(0.1).timeout
		waited += 0.1
	check(game._wiped, "the world notices the warband is down")
	check(root.get_node("GameFlow").transitions == transitions_before, "a wipe hands the warband through no door")
	check(root.get_node("GameFlow").transitions == transitions_before,
		"and makes no transition (%d)" % root.get_node("GameFlow").transitions)
	for merc_id in game.squad_ids:
		check(warband.roster.is_downed(int(merc_id)),
			"%s is left downed on the roster" % warband.roster.name_of(int(merc_id)))
	check(warband.stash.pooled_total() == gathered,
		"a wipe gathers nothing (%d pieces in the stash)" % warband.stash.pooled_total())
	var soul = game.controller.active_body(1)
	check(soul == null or not is_instance_valid(soul) or bool(soul.get("downed")),
		"no soul is left standing in a downed body")
	print("ESCAPE_RUN_WIPE seconds=%.1f bodies=%d downed=%d"
		% [waited, game.bodies.size(), warband.roster.downed_ids().size()])
