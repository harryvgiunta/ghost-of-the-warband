extends SceneTree
## The one world: the wood, the trail and the town in a single coordinate space.
##
## This regression is the campaign's spine. It proves the things the old chain of
## three scenes could not:
##
##   1. **One of everything.** The world owns exactly one `PossessionController`,
##      one camera, one `WarbandHud` and one tip channel, and its areas adopt them
##      instead of building their own.
##   2. **The wood is a place.** The pocket at the road's far end carries a deep
##      wood on every side *and* trees standing inside its own footprint, a ragged
##      stake line, shelters and a fire, not one cage - and the Hollow's own master
##      standing on his patch with his two keepers, on the world's one hostile list.
##   3. **The ground is one heightfield.** The wood's pocket and the town square are
##      padded flat into it, the walk between them rolls over real slopes, and the
##      trodden ground is the field's own map rather than geometry laid on it.
##   4. **Walking is the only travel.** A real body is driven north out of the town
##      square, up the whole road to the wood's mouth: no scene is requested, no
##      transition is made, the scene object never changes, the body never leaves
##      the walkable ground, and the walk is timed.
##   5. **The town end is the town.** The stash, the altar, the recruiter and the
##      quartermaster answer `G` from where the body stands, and nothing in the
##      square changes scene.
##   6. **The budget.** One world is one scene: nodes, multimesh draws, lights and
##      collision shapes are counted and bounded.

const WildernessScript = preload("res://scripts/warband/wilderness.gd")
const TrailScript = preload("res://scripts/warband/escape_run.gd")
const WoodScript = preload("res://scripts/warband/wood_boss.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const ClearingScript = preload("res://scripts/warband/camp_clearing.gd")
const CagesScript = preload("res://scripts/warband/soldier_cages.gd")

const TEST_SAVE := "user://warband_world_state.json"
const WARBAND_SAVE := "user://warband_world_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## How long the driven walk may take before the test calls it a hang.
const WALK_LIMIT := 200.0
## The walk is played at five times the simulation per second so a kilometre and a
## half of road fits inside the suite's ninety-second ceiling even with the pool
## running seven other Godots; the recorded time is game time at 1x, so the distance
## and the pace asserted below are the campaign's own.
const WALK_SCALE := 5.0

var game
var flow
var warband
var state
var checks := 0
var failures := 0
## The band on the way out: the briar wolves `wilderness.gd` spawns into
## `world.guards` before anything here reads the count, so every hostile tally in
## this run is the wood's own three plus the trail's cultists plus these.
var wolves: int = WildernessScript.PACK_COUNT


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WORLD_FAIL  ", message)


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
	flow.world_start = "town"

	# A scene that fails to parse would park this coroutine forever; the watchdog
	# turns that hang into a failing run.
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	# The walk plays at five times the simulation, and a Timer counts scaled time.
	watchdog.wait_time = 1500.0
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	root.add_child(watchdog)
	watchdog.start()

	game = load(WORLD).instantiate()
	root.add_child(game)
	if not game.has_method("stats"):
		check(false, "the world scene loaded without its script")
		_finish()
		return
	current_scene = game
	await create_timer(1.0).timeout
	# From here on the flow is live: if anything in the world opened a door, the
	# transition counter would move and the walk checks would catch it.
	flow.active = true

	check_one_of_each()
	await swear_escort()
	check_wood()
	check_ground()
	check_wood_and_road()
	await check_town_end()
	await check_walk()
	await check_down_drops_steel()
	check_keys()
	check_budget()
	check_doors()

	_finish()


func check_down_drops_steel() -> void:
	var victim = null
	var merc_id := 0
	for body in game.bodies:
		if not is_instance_valid(body) or body == game.controller.active_body(1):
			continue
		if not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		victim = body
		merc_id = game.controller.merc_of(body)
		break
	check(victim != null, "a warband body is standing to drop its steel")
	if victim == null:
		return
	# A campaign's bodies are naked: the steel this check watches fall is the
	# pool's, worn through the same roster call every gear change uses - a club in
	# the main hand and a blade in the off.
	warband.stash.add("dagger_ironwood", 1)
	warband.equip_merc(merc_id, "off", "dagger_ironwood")
	game.controller.refresh_gear(merc_id)
	await physics_frame
	var gear: Dictionary = warband.roster.equipped_of(merc_id)
	var held: Array[String] = []
	for slot in ["off", "main"]:
		if not str(gear.get(slot, "")).is_empty():
			held.append(str(gear.get(slot, "")))
	var floor_before: int = game.pickups.size()
	var at: Vector3 = victim.global_position
	victim.enter_downed(0)
	check(bool(victim.downed), "the body is on the floor")
	if not held.is_empty():
		check(game.pickups.size() == floor_before + held.size(),
			"the floor gains what it was holding (%d for %d)"
			% [game.pickups.size() - floor_before, held.size()])
		var dropped: Dictionary = {}
		for index in range(floor_before, game.pickups.size()):
			var piece = game.pickups[index]
			if is_instance_valid(piece):
				dropped[str(piece.item_id)] = piece
		for item_id in held:
			check(dropped.has(item_id), "the piece it held is on the floor (%s)" % item_id)
		for item_id in dropped:
			check(victim.global_position.distance_to((dropped[item_id] as Node3D).global_position) <= 1.2,
				"and it lies beside the body (%s, %.2f m)" % [item_id,
					victim.global_position.distance_to((dropped[item_id] as Node3D).global_position)])
	var after: Dictionary = warband.roster.equipped_of(merc_id)
	check(str(after.get("main", "")).is_empty() and str(after.get("off", "")).is_empty(),
		"the roster's hands are empty after the fall")
	check(str(victim.rig.weapon) == "none" or str(victim.rig.weapon).is_empty(),
		"and the body in the world is not holding it either (%s)" % str(victim.rig.weapon))
	# A second fall (the bleed-out death) must not drop the same piece twice.
	var floor_mid: int = game.pickups.size()
	victim._die(0)
	check(game.pickups.size() == floor_mid, "the death of an already-dropped body adds no second blade")


## One key press, as the window would send it: pressed, no echo, no modifiers.
func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


## The campaign's own key map, driven through the live scene's `_unhandled_input`:
## `O` is the warband screen (TAB is not), and `TAB` is the frontier's quick weapon
## swap - the body puts away the set in its hands and takes up the other one, with
## the rig re-dressed from the roster.
func check_keys() -> void:
	var merc_id: int = game.controller.merc_for_peer(1)
	check(merc_id > 0, "the soul is in a body to swap for")
	if merc_id <= 0:
		return
	warband.stash.add("bow_twig", 1)
	warband.stash.add("club_makeshift", 1)
	check(bool(warband.equip_merc(merc_id, "main", "bow_twig").get("ok", false)),
		"the soul's body takes the twig bow")
	game.controller.refresh_gear(merc_id)
	check(str(game.controller.body_of(merc_id).rig.weapon) == "bow",
		"the bow is in its hands")
	check(not game.screen.is_open(), "the warband screen starts closed")
	game._unhandled_input(_key(KEY_O))
	check(game.screen.is_open(), "O opens the warband screen")
	game._unhandled_input(_key(KEY_O))
	check(not game.screen.is_open(), "O closes it again")
	game._unhandled_input(_key(KEY_TAB))
	check(not game.screen.is_open(), "TAB does not open the warband screen")
	var hands: Dictionary = warband.roster.equipped_of(merc_id)
	check(str(hands.get("main", "")).is_empty() and str(hands.get("off", "")).is_empty(),
		"TAB puts the bow away and the empty Set 2 is in its hands")
	check(str(game.controller.body_of(merc_id).rig.weapon) != "bow",
		"and the rig let go of it (%s)" % str(game.controller.body_of(merc_id).rig.weapon))
	check(bool(warband.equip_merc(merc_id, "main", "club_makeshift").get("ok", false)),
		"a club goes into the empty Set 2")
	game.controller.refresh_gear(merc_id)
	game._unhandled_input(_key(KEY_TAB))
	hands = warband.roster.equipped_of(merc_id)
	check(str(hands.get("main", "")) == "bow_twig", "the next TAB brings Set 1's bow back")
	check(str(game.controller.body_of(merc_id).rig.weapon) == "bow",
		"and the rig is holding it again")
	check(warband.roster.weapon_set_pair(merc_id, 1).get("main", "") == "club_makeshift",
		"Set 2 kept the club the swap put away")


func _on_watchdog() -> void:
	check(false, "the one world did not finish inside the watchdog")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	flow.active = false
	flow.world_start = "town"
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_WORLD_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func flat_range(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


## The warband teaches with tips, never with pages: a beat that offers a hint must
## leave the game running, and nothing may pause the tree over a read.
func dismiss_card(label: String) -> void:
	if game == null:
		return
	check(not paused, "the game is never held still by a read (%s)" % label)
	if game.tips != null and is_instance_valid(game.tips):
		game.tips.hide()


# --- 1. one of everything --------------------------------------------------

func nodes_named(label: String) -> int:
	var total := 0
	for node in game.find_children(label, "", true, false):
		if String(node.name) == label:
			total += 1
	return total


func check_one_of_each() -> void:
	check(game.controller != null, "the world owns a possession controller")
	check(nodes_named("Soul") == 1, "exactly one controller exists (%d)" % nodes_named("Soul"))
	check(nodes_named("WarbandHud") == 1, "exactly one warband HUD exists (%d)" % nodes_named("WarbandHud"))
	check(nodes_named("TutorialCard") == 0,
		"the world carries no tutorial card any more (%d)" % nodes_named("TutorialCard"))
	check(nodes_named("Tips") == 1,
		"exactly one tip channel exists (%d)" % nodes_named("Tips"))
	# Only the world's own view counts: the paperdoll renders its character into
	# a SubViewport, and a camera that is current inside a SubViewport is current
	# for that viewport alone.
	var cameras := 0
	for node in game.find_children("*", "Camera3D", true, false):
		if not (node as Camera3D).current:
			continue
		var inside_viewport := false
		var parent: Node = node.get_parent()
		while parent != null and parent != game:
			if parent is SubViewport:
				inside_viewport = true
				break
			parent = parent.get_parent()
		if not inside_viewport:
			cameras += 1
	check(cameras == 1, "exactly one camera is current (%d)" % cameras)
	# The areas are the same scripts their standalone previews use, and they are
	# all pointed at the world's one controller and HUD.
	check(game.wood != null and game.trail != null and game.town != null,
		"the world built its wood, its trail and its town")
	check(game.town.controller == game.controller,
		"the town adopts the world's controller instead of building one")
	check(game.town.hud == game.hud, "the town writes to the world's one HUD")
	check(game.town.warband == warband, "and to the one warband")
	check(game.squad != null and game.squad.watchers == game.guards,
		"the squad drives the world's one hostile list, not a copy")
	# A new campaign starts in the town with the band `Warband.STARTING_BAND`
	# names - one naked body - and the soul is inside it.
	check(game.start_area == "town", "a new campaign opens in the town (%s)" % game.start_area)
	check(game.bodies.size() == warband.STARTING_BAND.size(),
		"the starting band stands in the square (%d bodies for %d sworn)"
			% [game.bodies.size(), warband.STARTING_BAND.size()])
	check(warband.roster.count() == warband.STARTING_BAND.size(),
		"and that is the whole of it (%d sworn)" % warband.roster.count())
	var local = game.controller.active_body(1)
	check(local != null, "the local soul starts inside a body")
	check(local != null and game.town.in_square(local), "and the body it is inside stands in the square")


## The band a campaign opens with is one body, and this walk is an escort walk: a
## squad is the thing it proves is not lost. Two names are sworn the way the game
## swears one - the roster takes them, the shared pool dresses them through the
## roster call every gear change uses, and the world's own field sync stands their
## bodies beside the party (the field holds `MAX_DEPLOYMENT_CAP`, so both take it).
func swear_escort() -> Array:
	var ids: Array = []
	for merc_name in ["Cass", "Bram"]:
		var merc_id: int = warband.add_mercenary(merc_name)
		ids.append(merc_id)
	# Naked bodies cannot fight back, and the road refills behind the walk: the
	# pair carry the pool's spare blade and a mail set each, through the roster
	# call every gear change uses. The walk is about the ground, not about the
	# escort losing a fight to a pack that came back while it walked past.
	var kit := {"main": "club_makeshift", "chest": "armor_mail_chest",
		"head": "armor_mail_head", "hands": "armor_mail_hands",
		"legs": "armor_mail_legs", "feet": "armor_mail_feet"}
	for slot_id in kit:
		warband.stash.add(str(kit[slot_id]), ids.size())
	for merc_id in ids:
		if int(merc_id) <= 0:
			continue
		for slot_id in kit:
			warband.equip_merc(int(merc_id), str(slot_id), str(kit[slot_id]))
	var waited := 0.0
	while waited < 4.0 and game.bodies.size() < 1 + ids.size():
		await physics_frame
		waited += 0.016
	for merc_id in ids:
		if int(merc_id) > 0:
			game.controller.refresh_gear(int(merc_id))
	check(game.bodies.size() == 1 + ids.size(),
		"the field seats every name the band swears (%d bodies)" % game.bodies.size())
	check(game.squad_ids.size() == game.bodies.size(),
		"and each of them is on the squad's book (%d of %d)"
			% [game.squad_ids.size(), game.bodies.size()])
	return ids


# --- 2. the wood at the far end of the road --------------------------------

func check_wood() -> void:
	var wood: Dictionary = game.wood.clearing
	check(int(wood.get("trees", 0)) >= 150, "the wood sits inside a real wood (%d trees)"
		% int(wood.get("trees", 0)))
	check(int(wood.get("bushes", 0)) >= 200, "undergrowth fills it (%d bushes)"
		% int(wood.get("bushes", 0)))
	check(int(wood.get("stakes", 0)) >= 60,
		"the boundary is a ragged stake line, not a fence (%d)" % int(wood.get("stakes", 0)))
	check(int(wood.get("wall", 0)) >= 5, "the wood behind the trunks is solid (%d wall runs)"
		% int(wood.get("wall", 0)))
	check(int(wood.get("huts", 0)) >= 2, "shelters stand round the pocket (%d huts)"
		% int(wood.get("huts", 0)))
	# A pocket cut into the wood, not a parade ground: the walkable ground is a
	# yard, and the wood runs far past it in every direction.
	var clear: Vector2 = game.clearing_size()
	check(clear.x >= 30.0 and clear.y >= 40.0,
		"the pocket holds a fire, a squad and the demon's patch (%.0f x %.0f m)" % [clear.x, clear.y])
	check(clear.x <= 50.0 and clear.y <= 60.0,
		"and it is a pocket, not a field (%.0f x %.0f m)" % [clear.x, clear.y])
	var band: Rect2 = wood.get("band", Rect2())
	check(band.size.x >= clear.x + 300.0 and band.size.y >= clear.y + 300.0,
		"the wood runs at least 150 m out on every side (%.0f x %.0f m)"
		% [band.size.x, band.size.y])
	# Trees stand inside the pocket's own footprint, which is what stops it reading
	# as a mown field with a treeline painted behind it.
	var inside := int(wood.get("inside_trees", 0))
	check(inside >= 6, "trees stand inside the wood itself (%d trunks)" % inside)
	check(game.wood.get_node_or_null("Clearing/Wood") != null,
		"the wood's own trees are one batched group")
	# The campsite: shelters, a fire and the junk, all close in around the pocket,
	# and grass round the trodden yard.
	for label in ["Huts", "CampFire", "CampJunk", "Grass", "StakeRing", "WoodLitter"]:
		check(game.wood.get_node_or_null("Clearing/%s" % label) != null,
			"the wood builds its %s" % label)
	check(game.wood.get_node_or_null("CampDressing") != null, "and its dressing")
	print("WORLD_CLEARING size=%.0fx%.0f band=%.0fx%.0f inside=%d trees=%d bushes=%d stakes=%d wall=%d"
		% [clear.x, clear.y, band.size.x, band.size.y, inside,
			int(wood.get("trees", 0)), int(wood.get("bushes", 0)),
			int(wood.get("stakes", 0)), int(wood.get("wall", 0))])

	# The cages are gone with the opening they belonged to: not one post, not one
	# cage node, and no door for the dressing to bolt iron to.
	check((wood.get("cages", []) as Array).is_empty(),
		"the pocket is built with zero cages (%d)" % (wood.get("cages", []) as Array).size())
	check(game.wood.get_node_or_null("Cage1") == null, "and no cage node stands in it")
	var hardware = game.wood.get_node_or_null("CampDressing/CageHardware")
	check(hardware != null and hardware.get_child_count() == 0,
		"the dressing bolts no iron to a cage (%d)"
		% (0 if hardware == null else hardware.get_child_count()))
	# Torches in the pocket and along the road: one night, one fire vocabulary.
	check((game.trail.forest.get("torches", []) as Array).size() >= 40,
		"the trail carries its torch line (%d)" % (game.trail.forest.get("torches", []) as Array).size())
	# The way in is a gap in the trees, and the road is a long run of ordinary wood
	# past it - the distance is the wood's own number, so the two cannot drift.
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var road_gap := flat_range(lane[0], game.wood.GATE_POINT)
	check(road_gap >= 150.0 and road_gap <= 210.0,
		"the road stands %.0f m of wood off the wood's mouth" % road_gap)
	check(absf(road_gap - game.wood.CAMP_TO_ROAD_METRES) < 1.0,
		"which is the wood's own CAMP_TO_ROAD_METRES (%.0f)" % game.wood.CAMP_TO_ROAD_METRES)
	var corridor: Array = game.wood.clearing.get("corridor", [])
	check(corridor.size() >= 8, "the way out is a corridor cut through the trees (%d gaps)"
		% corridor.size())
	check(int(game.wood.MOUTH_HALF_WIDTH) * 2 >= 8,
		"the gap is walkable (%d m)" % (int(game.wood.MOUTH_HALF_WIDTH) * 2))
	# The warband's enemies are the wood's mobs: the master and his pair stand in
	# the pocket, the road's cultists are down the lane, the briar wolves hold the
	# way between them and the quartermaster's warcamps are in the deep wood - one
	# list for all four.
	var wood_guards: int = game.wood.guards.size()
	check(wood_guards == 1 + WoodScript.GUARD_POSTS.size(),
		"the master and his two keepers hold the wood (%d)" % wood_guards)
	var warcamps: int = game.watcher_warren.total() if game.watcher_warren != null else 0
	check(game.guards.size() == wood_guards + 20 + TrailScript.ARCHER_COUNT + wolves + warcamps,
		"twenty cultists, %d wolves and %d warcamp wardens join them on the same hostile"
			% [wolves, warcamps] + " list (%d in all)" % game.guards.size())
	for guard in game.wood.guards:
		check(game.guards.has(guard), "a wood body is on the world's hostile list")
		check(guard.global_position.y > -1.0, "and stands on the ground")


# --- 2b. the ground -------------------------------------------------------

## One heightfield under the whole strip: the wood's pocket and the town square
## padded flat into it, and the walk between them rolling over real slopes. The
## world used to lie on a single flat box; this is what replaced it.
func check_ground() -> void:
	var readout: Dictionary = game.stats()
	var low := float(readout["height_min"])
	var high := float(readout["height_max"])
	check(int(readout["terrain_tris"]) >= 20000,
		"the ground is one heightfield (%d triangles)" % int(readout["terrain_tris"]))
	check(high - low >= 2.0, "the wood rises and falls (%.1f .. %.1f m)" % [low, high])
	# The wood's own bodies stand on the ground they were posted on: a demon that
	# floats or sinks is a body in the wood, not a fight waiting for a party.
	for guard in game.wood.guards:
		if not is_instance_valid(guard):
			continue
		var ground := TerrainScript.height_at(guard.global_position.x, guard.global_position.z)
		check(absf(guard.global_position.y - ground) < 0.05,
			"the %s stands on the ground it holds (%.3f vs %.3f)"
				% [String(guard.name), guard.global_position.y, ground])
	# ... and so does the square.
	var centre: Vector3 = game.town.global_position
	var corner: Variant = null
	for offset in [Vector3(-12.0, 0.0, -9.0), Vector3(12.0, 0.0, -9.0),
			Vector3(-12.0, 0.0, 9.0), Vector3(12.0, 0.0, 9.0)]:
		var height := TerrainScript.height_at(centre.x + offset.x, centre.z + offset.z)
		if corner == null:
			corner = height
		check(absf(height - float(corner)) < 0.01,
			"the square is level (%.3f m)" % height)
	# The walk between them is not: the trail goes over the wood's own ground.
	var low_walk := INF
	var high_walk := -INF
	for point in game.trail.forest["lane"]:
		var height := TerrainScript.height_at(point.x, point.z)
		low_walk = minf(low_walk, height)
		high_walk = maxf(high_walk, height)
	# The walk between them is not: the trail is hill country, and the floor it
	# used to be - two metres of roll - is what made the wood read as a lawn.
	check(high_walk - low_walk >= 12.0,
		"the walk between them goes over real hills (%.1f m of relief)" % (high_walk - low_walk))
	print("WORLD_GROUND relief=%.1f..%.1f walk=%.1f..%.1f tris=%d"
		% [low, high, low_walk, high_walk, int(readout["terrain_tris"])])
	check_worn_ground()


## The worn ground is the ground's own map, never geometry laid on it: trodden
## earth where feet go, untouched wood off the route, and an edge softer than one of
## the heightfield's 7 m cells. The old dirt rode the mesh's vertex alpha, which
## cannot draw anything narrower than a cell - every trodden patch came out as a
## polygon of triangles - and the wood's own yard was a set of hard discs on the
## grass. (Where the grass stands is not read here: a headless run keeps no
## MultiMesh instance data.)
func check_worn_ground() -> void:
	# The demon's patch is the most walked ground in the pocket: the fight happens
	# there and the ground says so.
	for point in [game.wood.BOSS_POINT, WoodScript.GUARD_POSTS[0], WoodScript.GUARD_POSTS[1]]:
		var worn := TerrainScript.wear_at((point as Vector3).x, (point as Vector3).z)
		check(worn >= 0.6, "the ground at (%.0f, %.0f) is trodden earth (%.2f)"
			% [(point as Vector3).x, (point as Vector3).z, worn])
	var path = game.trail.forest["path"]
	var thinnest := 1.0
	var widest := 0.0
	var wild := 0.0
	# Off the swamp (0.42-0.62 of the way, where the bowl is mud beside the lane)
	# and off the wood's corridor, which meets the lane at its start.
	for fraction in [0.12, 0.2, 0.28, 0.36, 0.7, 0.78, 0.86, 0.94]:
		var frame: Dictionary = path.sample(path.total * float(fraction))
		var at: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		thinnest = minf(thinnest, TerrainScript.wear_at(at.x, at.z))
		for side: float in [-1.0, 1.0]:
			# Out across the line: where the bare core gives way, and where the
			# ground is untouched again.
			var core := -1.0
			var edge := -1.0
			for step in 64:
				var reach := 0.25 * float(step)
				var probe := at + right * side * reach
				var worn := TerrainScript.wear_at(probe.x, probe.z)
				if core < 0.0 and worn < 0.6:
					core = reach
				if worn <= 0.05:
					edge = reach
					break
			check(core >= 0.0 and edge >= 0.0,
				"the lane's worn line ends inside 16 m at %.0f%% (%.1f .. %.1f m)"
				% [float(fraction) * 100.0, core, edge])
			widest = maxf(widest, edge - core)
			var off := at + right * side * 40.0
			wild = maxf(wild, TerrainScript.wear_at(off.x, off.z))
	check(thinnest >= 0.6, "the lane's middle is trodden earth all the way (%.2f)" % thinnest)
	check(widest < TerrainScript.CELL * 0.5,
		"a worn edge is softer than a terrain cell, not a polygon of them (%.1f m)" % widest)
	check(wild <= 0.01, "the wood off the route is untouched (%.2f)" % wild)
	print("WORLD_WORN lane_core=%.2f edge=%.1fm wild=%.2f" % [thinnest, widest, wild])


# --- 3. the wood, the Horned Thing, and the road ------------------------

## What stands at the road's far end, and what the road still carries: the wood is
## built whether or not the party ever walks that far, the Hollow's master stands on
## his own patch in the open air, and the road's own caged line and warcamps - the
## quartermaster's orders' ground - are built on it.
func check_wood_and_road() -> void:
	dismiss_card("the wood")
	check(game.wood.boss_point().is_equal_approx(WoodScript.BOSS_POINT),
		"the wood names the demon's patch (%s)" % str(game.wood.boss_point()))
	var master = game.wood.master
	check(master != null and is_instance_valid(master), "the Horned Thing stands in the wood")
	if master == null or not is_instance_valid(master):
		return
	check(flat_range(master.global_position, game.wood.boss_point()) < 0.1,
		"on the patch it is named for (%.2f m)" % flat_range(master.global_position,
			game.wood.boss_point()))
	check(game.wood.master_alive(), "and he is on his feet at boot")
	check(bool(master.get("boss")), "he is the Hollow's master, not a keeper")
	check(game.guards.has(master), "he is on the world's one hostile list")
	check(float(master.max_health) > 240.0,
		"and carries more than a keeper's pool (%d)" % int(master.max_health))
	# His pair hold their own posts, one either side of him.
	var keepers := 0
	for index in WoodScript.GUARD_POSTS.size():
		var keeper = game.wood.get_node_or_null("WoodKeeper%d" % (index + 1))
		check(keeper != null, "keeper %d stands with him" % (index + 1))
		if keeper == null:
			continue
		keepers += 1
		var post: Vector3 = WoodScript.GUARD_POSTS[index]
		check(flat_range((keeper as Node3D).global_position, post) < 0.1,
			"keeper %d holds its post (%.2f m)" % [index + 1,
				flat_range((keeper as Node3D).global_position, post)])
		check(bool(keeper.get("alive")), "keeper %d is alive" % (index + 1))
	check(keepers == WoodScript.GUARD_POSTS.size(),
		"the wood fields his whole guard (%d)" % keepers)
	# Nothing points at him: he is optional, and no order, no counter and no door
	# sends a party to the pocket. The wood simply stands there.
	check(game.trail.cultists_alive() == game.trail.guards.size(),
		"the road is at its own full strength (%d)" % game.trail.cultists_alive())

	# The road's own caged line: the table's soldiers strung down the lane - one
	# of them, the second body the band can reach, which is the whole of the
	# road's recruitment.
	check(game.soldier_cages != null, "the road's caged line is built")
	if game.soldier_cages != null:
		check(game.soldier_cages.remaining() == CagesScript.CAGE_FRACTIONS.size(),
			"the table's soldiers are held down the road (%d of %d)"
			% [game.soldier_cages.remaining(), CagesScript.CAGE_FRACTIONS.size()])
		var lane: PackedVector3Array = game.trail.forest["lane"]
		var lane_start: Vector3 = lane[0]
		var lane_end: Vector3 = lane[lane.size() - 1]
		for point in game.soldier_cages.marker_points():
			check((point as Vector3).z < lane_start.z and (point as Vector3).z > lane_end.z - 40.0,
				"a cage stands on the lane (%s)" % str(point))
	# ... and the warcamps of wardens in the deep wood.
	check(game.watcher_warren != null, "the watcher warren is built")
	if game.watcher_warren != null:
		check((game.watcher_warren.camps() as Array).size() == WatcherWarren.CAMPS.size(),
			"every warcamp in the table stands off the lane (%d)"
			% (game.watcher_warren.camps() as Array).size())
		check(game.watcher_warren.total() > 0,
			"and every warden is on the list (%d)" % game.watcher_warren.total())
		check(game.watcher_warren.living() == game.watcher_warren.total(),
			"all of them alive at boot (%d)" % game.watcher_warren.living())
	print("WORLD_WOOD boss=%s health=%d keepers=%d hostiles=%d"
		% [str(master.get("display")), int(master.max_health), keepers, game.guards.size()])


# --- 4. walk the whole world ----------------------------------------------

## The proof that there is no travel scene any more: one body, driven with real
## movement, north out of the town square, up the whole road and through the gap in
## the trees to the wood's mouth - with the scene, the flow and the walkable floor
## watched the whole way. The distance the docs quote is this walk, driven end to
## end by the same body.
func check_walk() -> void:
	var lane: PackedVector3Array = game.trail.forest["lane"]
	var path = game.trail.forest["path"]
	var town_gate: Vector3 = game.trail.town_gate()
	var town_at: Vector3 = game.town.global_position
	var wood_mouth: Vector3 = game.wood.GATE_POINT
	var half := float(game.trail.forest["width"]) * 0.5
	var body = game.controller.active_body(1)
	check(body != null, "the soul still has a body for the walk")
	if body == null:
		return
	# Clear the road first: the walk proves the ground, not the fight. A live band
	# of cultists, wolves or the wood's own pair would decide the run instead of
	# measuring it.
	for watcher in game.trail.guards:
		if is_instance_valid(watcher) and bool(watcher.get("alive")):
			watcher.take_damage(4000.0, 0)
	for guard in game.wood.guards:
		if is_instance_valid(guard) and bool(guard.get("alive")):
			guard.take_damage(4000.0, 0)
	if game.wilderness != null:
		for wolf in game.wilderness.wolves():
			if is_instance_valid(wolf) and bool(wolf.get("alive")):
				wolf.take_damage(4000.0, 0)
	await create_timer(0.4).timeout
	# A one-time lesson may have opened after the field went quiet (the bandage
	# card is the usual one); a paused tree would read as a body that cannot walk.
	dismiss_card("the wound card")
	check(game.trail.cultists_alive() == 0, "the road can be cleared (%d left)"
		% game.trail.cultists_alive())
	check(game.loot.corpse_ids().size() >= game.trail.guards.size(),
		"every cultist is a lootable corpse (%d registered for %d bodies)"
		% [game.loot.corpse_ids().size(), game.trail.guards.size()])

	# No teleport: the body is where the town left it, and it walks out from there.
	check(game.town.in_square(body), "the walk begins on the square's own ground")
	game.controller.input_enabled = false
	await physics_frame

	# Follow the road itself instead of the polyline's own corners: a body steered
	# at a 45 m waypoint cuts the inside of every bend, and on a lane this long the
	# cut reaches the tree row. Sampling the path every few metres keeps the body on
	# the line the torches mark, which is the line the lateral assertion is about.
	# The walk runs the lane backwards - town first - and then up the corridor the
	# wood cut through its own trees to the mouth.
	var waypoints: Array[Vector3] = [town_gate + Vector3(0.0, 0.2, 0.0)]
	var along := float(path.total) - 6.0
	while along > 0.0:
		var sample: Dictionary = path.sample(along)
		waypoints.append((sample["position"] as Vector3) + Vector3(0.0, 0.2, 0.0))
		along -= 6.0
	var corridor: PackedVector3Array = ClearingScript.corridor_line(wood_mouth,
		game.wood.CAMP_TO_ROAD_METRES)
	for index in range(corridor.size() - 1, -1, -1):
		waypoints.append(corridor[index] + Vector3(0.0, 0.2, 0.0))
	waypoints.append(wood_mouth + Vector3(0.0, 0.2, 0.0))

	var transitions_before: int = flow.transitions
	var scene_before = current_scene
	var travelled := 0.0
	var last: Vector3 = body.global_position
	var off_ground := 0
	var worst_lateral := 0.0
	var ticks := 0
	var started := Time.get_ticks_msec()
	var index := 0
	Engine.physics_ticks_per_second = 180
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = WALK_SCALE
	var walk_stall := 0
	while index < waypoints.size() and ticks < 30000:
		var to: Vector3 = waypoints[index] - body.global_position
		to.y = 0.0
		if to.length() <= 1.6:
			index += 1
			continue
		var direction := to.normalized()
		body.accept_network_input(Vector2(direction.x, direction.z), true)
		await physics_frame
		ticks += 1
		var step := flat_range(last, body.global_position)
		travelled += step
		last = body.global_position
		if step < 0.01:
			walk_stall += 1
			if walk_stall > 300:
				print("WORLD_STALL world walk stuck at %s waypoint %d" % [
					str(body.global_position), index])
				break
		else:
			walk_stall = 0
		# Lateral drift is a claim about the lane, so it is measured on the lane:
		# the wood's corridor and the square are wide open by design.
		if body.global_position.z > lane[lane.size() - 1].z + 1.0 \
				and body.global_position.z < lane[0].z - 1.0:
			var lateral: float = path.distance_to(Vector2(body.global_position.x, body.global_position.z))
			worst_lateral = maxf(worst_lateral, lateral)
		if not _walkable(body.global_position, path, half, town_at):
			off_ground += 1
		if bool(body.get("downed")) or not bool(body.get("alive")):
			break
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.controller.input_enabled = true
	var real_seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var game_seconds := float(ticks) / 60.0

	check(flow.transitions == transitions_before,
		"walking the whole world made no transition (%d -> %d)"
		% [transitions_before, flow.transitions])
	check(current_scene == scene_before, "the scene object never changed during the walk")
	check(game.is_inside_tree(), "the world is still the scene the body walked in")
	check(off_ground == 0, "the body never left the walkable ground (%d ticks off)" % off_ground)
	check(worst_lateral <= half + 0.6,
		"the body never left the %.1f m trail (%.2f m off centre)" % [half * 2.0, worst_lateral])
	check(flat_range(body.global_position, wood_mouth) <= 3.0,
		"the body reached the wood's mouth (%.2f m from the gap)"
		% flat_range(body.global_position, wood_mouth))
	check(real_seconds < WALK_LIMIT, "the walk finished inside the watchdog (%.1f s real)" % real_seconds)
	# The squad is an escort, not a decoration: a body left wedged on a trunk
	# somewhere in a kilometre and a half of wood is a squad the player loses for
	# the rest of the run. None of the free allies may be dead, and none abandoned.
	var soul_id: int = int(game.controller.merc_for_peer(1))
	var free_allies := 0
	var alive_allies := 0
	var farthest := 0.0
	var report: Array[String] = []
	for merc_id in game.squad_ids:
		if int(merc_id) == soul_id:
			continue
		var ally = game.controller.body_of(int(merc_id))
		if ally == null or not is_instance_valid(ally):
			continue
		free_allies += 1
		if bool(ally.get("alive")):
			alive_allies += 1
		var gap: float = flat_range(ally.global_position, body.global_position)
		farthest = maxf(farthest, gap)
		report.append("%s %.0f m" % [warband.roster.name_of(int(merc_id)), gap])
	check(free_allies >= 2, "the walk had a squad to lose (%d allies)" % free_allies)
	check(alive_allies == free_allies,
		"every ally walked the road on his feet (%d of %d)" % [alive_allies, free_allies])
	# A soul that sprints the whole 1,560 m without ever stopping is faster than an
	# escort, and the squad is allowed to trail it - the trail's own regression is
	# where "they arrive and stand beside you" is proved (`escape_run_regression`
	# waits at the end of a stretch and requires three within 20 m). What this walk
	# proves is that nobody is *lost*: a body left wedged in a tree when the soul
	# reaches the wood is a body the player never gets back.
	check(farthest < 700.0, "no ally is stranded on the road (%s)" % ", ".join(report))
	# The campaign is one walk from the square to the wood, and the same body walks
	# all of it.
	check(travelled >= 1500.0, "the walk from the square to the wood is a real one (%.0f m)"
		% travelled)
	# The kill loop above emptied the wood, and every pack took its own
	# `RESPAWN_SECONDS` clock from that first death. A clock that runs out behind
	# the walker puts the same bodies back on the same posts; one held by
	# `RESPAWN_QUIET` waits, because a party body is still that near. Either way
	# the rule that survives the walk is the band's own: never more bodies than the
	# table names, and every body it puts back is a live hostile standing on the
	# world's ground - nothing comes out of the wood in front of the walker.
	if game.wilderness != null:
		check(game.wilderness.wolves().size() == WildernessScript.PACK_COUNT,
			"the band is still its %d wolves after the walk (%d)"
				% [WildernessScript.PACK_COUNT, game.wilderness.wolves().size()])
		var recovered := 0
		for wolf in game.wilderness.wolves():
			if not is_instance_valid(wolf) or not bool(wolf.get("alive")):
				continue
			recovered += 1
			check(game.guards.has(wolf), "%s is on the world's one hostile list" % wolf.name)
			var ground := TerrainScript.height_at((wolf as Node3D).global_position.x,
				(wolf as Node3D).global_position.z)
			check(absf(float((wolf as Node3D).global_position.y) - ground) < 1.0,
				"%s stands on the ground it was put back on (%.2f m off)"
					% [wolf.name, absf(float((wolf as Node3D).global_position.y) - ground)])
		print("WORLD_PACKS living=%d of %d" % [recovered, WildernessScript.PACK_COUNT])
	print("WORLD_WALK game_seconds=%.1f real_seconds=%.1f ticks=%d metres=%.0f lateral=%.2f"
		% [game_seconds, real_seconds, ticks, travelled, worst_lateral])


## Whether a point is on ground a body is meant to stand on: the wood's pocket, the
## lane's walkable band, the wood's own corridor out to the road, the approach road,
## or the square itself.
func _walkable(point: Vector3, path, half: float, town_at: Vector3) -> bool:
	if absf(point.x) <= game.wood.YARD_HALF_WIDTH + 1.0 \
			and point.z >= game.wood.YARD_FRONT - 1.5 and point.z <= game.wood.YARD_BACK + 1.0:
		return true
	# The wood's own band: pocket, corridor and the wood the layout measured. A body
	# is meant to stand in all of it - the trees near the wood are the only obstacles.
	var band: Rect2 = game.wood.clearing.get("band", Rect2())
	if band.size.x > 0.0 and point.x >= band.position.x - 1.0 \
			and point.x <= band.end.x + 1.0 and point.z >= band.position.y - 1.0 \
			and point.z <= band.end.y + 1.0:
		return true
	if path.distance_to(Vector2(point.x, point.z)) <= half + 0.55:
		return true
	if absf(point.x) <= game.town.NORTH_GATE_HALF + 2.0 \
			and point.z <= game.trail.town_gate().z + 1.0 and point.z >= town_at.z + 1.0:
		return true
	return absf(point.x) <= game.town.WALL_RADIUS + 1.0 \
		and absf(point.z - town_at.z) <= game.town.WALL_RADIUS + 1.0


# --- 5. the town end -------------------------------------------------------

func check_town_end() -> void:
	var body = game.controller.active_body(1)
	check(body != null, "the body is standing in the square")
	check(is_instance_valid(game.stash_chest), "the stash chest stands in the square")
	check(is_instance_valid(game.recruiter_desk), "the recruiter desk stands in the square")
	check(game.altar != null and game.altar.has_method("interact"), "the altar is the shared object")
	check(is_instance_valid(game.quartermaster), "the quartermaster's counter is real")

	# Each counter answers G from where the body stands - and the answer is the
	# object itself, not a message.
	for service in ["stash", "altar", "recruiter", "quartermaster"]:
		var point: Vector3 = game.service_point(service)
		body.global_position = point + Vector3(1.2, 0.1, 1.2)
		await create_timer(0.15).timeout
		check(game.service_at(body.global_position) == service,
			"the %s counter resolves from where the body stands" % service)
		var answered: String = game.interact_at(1, body.global_position)
		check(answered == service, "G at the %s opens it (got '%s')" % [service, answered])
		# A keeper with something to say says it as one line and gets out of the
		# way: the counter opens on the same press, and nothing is read on top of
		# it. There is no modal to dismiss and nothing to spam-skip.
		check(game._panel_open(), "the %s counter opens on the same press" % service)
		check(not paused, "and the game keeps running behind it (%s)" % service)
		game._hide_panels()
		await create_timer(0.1).timeout
	check(not game._panel_open(), "the panels close again")

# --- 6. the budget ---------------------------------------------------------

func check_budget() -> void:
	var readout: Dictionary = game.stats()
	var nodes := int(readout["nodes"])
	var draws := int(readout["draws"])
	var shapes := int(readout["shapes"])
	var lights := int(readout["lights"])
	# One world is one scene: a pocket in a deep wood, a kilometre and a half of
	# road, the road's caged line and the warcamps the orders point at, a square
	# and fifty-odd hostiles all in one tree. The caps follow what the deep wood and
	# the road actually cost - a deep band batched into multimeshes, trunk colliders
	# only in the rows a body can walk up to - and the readout below is the measured
	# number, so a regression that starts creeping can be narrowed from it.
	check(nodes <= 26000, "the world stays inside its node budget (%d)" % nodes)
	check(draws <= 800, "the world stays inside its draw budget (%d multimesh)" % draws)
	check(shapes <= 1400, "the world stays inside its collision budget (%d shapes)" % shapes)
	# The route is marked by fire now: a pair of torches every eighteen metres down
	# a kilometre and a third of wood, and that is the design, not creep. The
	# warcamps' braziers and the town's own lanterns share the same ceiling.
	check(lights <= 210, "the world stays inside its light budget (%d)" % lights)
	var warren: int = game.watcher_warren.total() if game.watcher_warren != null else 0
	var hostiles: int = 1 + WoodScript.GUARD_POSTS.size() + 20 \
		+ TrailScript.ARCHER_COUNT + wolves + warren
	check(int(readout["guards"]) == hostiles,
		"all %d hostiles are on the list (%d)" % [hostiles, int(readout["guards"])])
	# The wood is a kilometre and a third of lane: a band, not a number, so a
	# waypoint can be nudged without a test about the art failing.
	check(float(readout["lane_length"]) >= 1250.0 and float(readout["lane_length"]) <= 1500.0,
		"the trail is a long run (%.1f m)" % float(readout["lane_length"]))
	print("WORLD_BUDGET nodes=%d draws=%d meshes=%d lights=%d shapes=%d guards=%d"
		% [nodes, draws, int(readout["meshes"]), lights, shapes, int(readout["guards"])])


# --- 7. the one door -------------------------------------------------------

func check_doors() -> void:
	check(flow.WORLD_SCENE == WORLD, "the flow's campaign scene is the world (%s)" % flow.WORLD_SCENE)
	check(flow.TITLE_SCENE == "res://title.tscn", "and its way out is the title")
	flow.active = false
	flow.world_start = "town"
