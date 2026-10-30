extends SceneTree
## The campaign's first town is a stockade settlement, not a room: a stake ring
## with one open gate on the north road, roofed halls with their backs to the
## stakes, a keeper standing behind every counter, a gold arrow over the one who
## has something to say, an ichor bench, and three archers of the watch who shoot
## what comes up the road past the gate.
##
## Every claim here is a number the scene can be asked for without a rendered
## window: the stakes the ring came out at, the roof over each hall's eave, the
## colliders the dressing may not own, the lights the town may not overspend on,
## the arrow's own target, and one real `arrow.gd` shaft taking health off a real
## wolf at the gate.

const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const TownScript = preload("res://scripts/warband/town_hub.gd")
const DressingScript = preload("res://scripts/warband/town_dressing.gd")
const FolkScript = preload("res://scripts/warband/town_folk.gd")
const GuardScript = preload("res://scripts/warband/town_guard.gd")
const GiverScript = preload("res://scripts/warband/quest_giver.gd")
const EnemyScript = preload("res://scripts/enemy.gd")

const SCENE := "res://scenes/town_hub.tscn"
const TEST_SAVE := "user://town_stockade_state.json"
const WARBAND_SAVE := "user://town_stockade_warband.json"
## A body's own girth: the clearance every service point and every muster post is
## held to.
const BODY_RADIUS := 0.45
## How far outside the gate the wolf is put: on the road the ring was cut for,
## well inside a watch archer's reach.
const WOLF_OUTSIDE := 8.0
## Seconds of frames the watch is given to notice, draw, and loose.
const WATCH_SECONDS := 3.0
## The town may own this many lamps and no more: the fire, the three stall lamps,
## the two desk lamps, the altar's, the dressing's four lanterns, the expedition
## gate's two, the two gate braziers, the bench's green one and the offering
## ground's. The town added four of them (the braziers, the bench and the
## offering); the rest were already here.
const LIGHT_BUDGET := 18

var town
var warband
var state
var checks := 0
var failures := 0
## The one stand-in body the hint and prompt lines are asked about.
var _probe: Node3D = null

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("STOCKADE_FAIL  ", message)

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
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()

	# A scene script that fails to parse would leave this coroutine parked, so a
	# hang becomes a failing run instead of a dead test.
	var watchdog := Timer.new()
	watchdog.name = "Watchdog"
	watchdog.wait_time = 110.0
	watchdog.one_shot = true
	watchdog.timeout.connect(func() -> void:
		check(false, "the stockade regression hung")
		_finish())
	root.add_child(watchdog)
	watchdog.start()

	town = load(SCENE).instantiate()
	root.add_child(town)
	await create_timer(0.9).timeout
	check(town != null and is_instance_valid(town), "the town builds in its own scene")
	if town == null or not is_instance_valid(town):
		_finish()
		return

	check_ring()
	check_buildings()
	check_dressing()
	check_keepers()
	await check_marker()
	await check_talk()
	check_services()
	await check_guard()
	check_lights()
	_finish()


func _finish() -> void:
	if town != null and is_instance_valid(town):
		town.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("TOWN_STOCKADE_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


# --- geometry helpers ------------------------------------------------------

func meshes_under(node: Node, found: Array = []) -> Array:
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		meshes_under(child, found)
	return found

func lights_under(node: Node, found: Array = []) -> Array:
	if node is Light3D:
		found.append(node)
	for child in node.get_children():
		lights_under(child, found)
	return found

func solids_under(node: Node, found: Array = []) -> Array:
	if node is CollisionObject3D or node is CollisionShape3D:
		found.append(node)
	for child in node.get_children():
		solids_under(child, found)
	return found

func world_aabb(mesh_instance: MeshInstance3D) -> AABB:
	if mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	return mesh_instance.global_transform * mesh_instance.mesh.get_aabb()

## The radius the farthest horizontal corner of a box reaches from the town's
## own centre.
func radius_of(box: AABB) -> float:
	var farthest := 0.0
	for x in [box.position.x, box.end.x]:
		for z in [box.position.z, box.end.z]:
			farthest = maxf(farthest, Vector2(x, z).length())
	return farthest

## A straight line with nothing solid on layer 1 across it.
func clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return town.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## Whether a body could stand at `at`: nothing solid inside its own girth.
func standing_clear(at: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = BODY_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 1.0, 0.0))
	return town.get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


# --- the ring and its gate -------------------------------------------------

func check_ring() -> void:
	check(is_equal_approx(TownScript.WALL_RADIUS, 22.0),
		"the town is a ring of stakes %d m across (%.1f)" % [44, TownScript.WALL_RADIUS])
	check(town.palisade_stakes > 200,
		"the ring is a wall of stakes, not a fence rail (%d stakes)" % town.palisade_stakes)
	var mesh := town.get_node_or_null("Palisade/VillagePalisade") as MeshInstance3D
	check(mesh != null and mesh.mesh != null, "the palisade is one merged mesh")

	# The one gap in the ring is the road in: a body walks through the middle of
	# it, and the lane is wider than a man's shoulders.
	check(clear_line(Vector3(0.0, 1.0, 18.0), Vector3(0.0, 1.0, 26.0)),
		"the gate line is open at the centre")
	check(clear_line(Vector3(1.7, 1.0, 18.0), Vector3(1.7, 1.0, 26.0)),
		"the lane is open a stride to the east of the centre")
	check(clear_line(Vector3(-1.7, 1.0, 18.0), Vector3(-1.7, 1.0, 26.0)),
		"the lane is open a stride to the west of the centre")
	# Everywhere else the ring is a wall.
	check(not clear_line(Vector3(12.0, 1.0, 12.0), Vector3(17.0, 1.0, 17.0)),
		"the ring closes on the north-east diagonal")
	check(not clear_line(Vector3(-12.0, 1.0, -12.0), Vector3(-17.0, 1.0, -17.0)),
		"the ring closes on the south-west diagonal")
	check(not clear_line(Vector3(-17.0, 1.0, 2.0), Vector3(-22.5, 1.0, 2.0)),
		"the ring closes on the west side")

	# The gate frame stands in the gap, over the road, and it says where the road
	# goes.
	var frame := town.get_node_or_null("NorthGate/VillageGate") as MeshInstance3D
	check(frame != null and frame.mesh != null, "the antler gate stands in the gap")
	if frame != null:
		var box := world_aabb(frame)
		check(absf(box.get_center().x) < 0.5 and box.size.x > 8.0,
			"the gate spans the lane (%.1f m wide)" % box.size.x)
		check(box.end.y > 4.0, "the gate stands a lintel over a body's head (%.1f m)" % box.end.y)
	var label := town.get_node_or_null("NorthGate/GateSign") as Label3D
	check(label != null and label.text == "THE WOOD ROAD", "the gate still names the wood road")

	# Nothing stands in the road: the lane is walkable from the fire to the wall
	# and a stride outside it.
	for z in [16.0, 18.0, 20.0, 22.0, 24.0, 26.0]:
		for x in [-1.8, 0.0, 1.8]:
			check(standing_clear(Vector3(x, 0.0, z)),
				"the gate lane is walkable at (%.1f, %.1f)" % [x, z])


# --- the settlement --------------------------------------------------------

## Half the footprint of each kind of structure, in metres: the plot a body would
## find the thing in. The wall check is made on these corners and not on a mesh's
## axis-aligned box, because a hall turned to face the fire has an AABB that
## reaches past its own corners.
const FOOTPRINTS := {
	"keeper": Vector2(4.1, 3.5),
	"wattle": Vector2(2.9, 2.9),
	"frame": Vector2(2.5, 2.1),
	"totem": Vector2(1.1, 1.1),
	"woodpile": Vector2(1.3, 1.3),
	"rack": Vector2(1.3, 0.8),
	"effigy": Vector2(0.8, 0.8),
	"offering": Vector2(2.9, 2.6),
}

## The four footprint corners of a structure, in the town's own space.
func footprint_corners(node: Node3D, half: Vector2) -> Array:
	var turn := Basis(Vector3.UP, node.rotation.y)
	var out: Array = []
	for lx in [-half.x, half.x]:
		for lz in [-half.y, half.y]:
			out.append(node.position + turn * Vector3(lx, 0.0, lz))
	return out


func check_buildings() -> void:
	var roofed := 0
	var stray := 0
	for row in TownScript.BUILDINGS:
		var label := str(row["name"])
		var kind := str(row["kind"])
		var node := town.get_node_or_null(label) as Node3D
		check(node != null, "%s stands in the settlement" % label)
		if node == null:
			continue
		var meshes := meshes_under(node)
		check(not meshes.is_empty(), "%s is built from the village kit" % label)
		var top := -INF
		for mesh_instance in meshes:
			top = maxf(top, world_aabb(mesh_instance).end.y)
		if kind == "keeper":
			roofed += 1
			check(top > 4.0, "%s carries its thatch roof over the eave (%.1f m)" % [label, top])
		elif kind == "wattle":
			roofed += 1
			check(top > 3.4, "%s is roofed (%.1f m)" % [label, top])
		else:
			check(top > 2.6, "%s is an open stall with an awning (%.1f m)" % [label, top])
		# Its back is to the wall: the whole plot has to be inside the ring.
		for corner in footprint_corners(node, FOOTPRINTS[kind]):
			if Vector2(corner.x, corner.z).length() > TownScript.WALL_RADIUS:
				stray += 1
	check(roofed >= 4, "at least four roofed structures stand around the square (%d)" % roofed)
	check(stray == 0, "every hall is built inside the stakes (%d corners out)" % stray)

	# None of it may stand on the square's own ground: the fire, the counters, the
	# three 3 m service rings, the muster posts or the gate lane.
	for service in ["stash", "altar", "recruiter", "quartermaster", "ichor",
			"vendor_orla", "vendor_brann", "vendor_vey", "gate"]:
		check(standing_clear(town.service_point(service)),
			"a body can stand at the %s" % service)
	for post in TownScript.SPAWN_POSTS:
		check(standing_clear(town.global_position + post),
			"the muster post at (%.1f, %.1f) is clear" % [post.x, post.z])
	for ring in [Vector3(2.2, 0.0, 0.0), Vector3(-2.2, 0.0, 0.0),
			Vector3(0.0, 0.0, 2.2), Vector3(0.0, 0.0, -2.2)]:
		check(standing_clear(town.global_position + ring),
			"the fire ring is clear at (%.1f, %.1f)" % [ring.x, ring.z])

	# The village props are here too, and they are real warden furniture.
	for row in TownScript.VILLAGE_PROPS:
		var label := str(row["name"])
		var kind := str(row["kind"])
		var node := town.get_node_or_null(label) as Node3D
		check(node != null and not meshes_under(node).is_empty(),
			"%s stands in the settlement" % label)
		if node == null:
			continue
		for corner in footprint_corners(node, FOOTPRINTS[kind]):
			if Vector2(corner.x, corner.z).length() > TownScript.WALL_RADIUS:
				stray += 1
	check(stray == 0, "no hall or prop leans out over the stakes (%d corners out)" % stray)


func check_dressing() -> void:
	var dressing: Node = town.get_node_or_null("TownDressing")
	check(dressing != null, "the square builds its dressing")
	if dressing == null:
		return
	check(is_equal_approx(DressingScript.WALL_RADIUS, TownScript.WALL_RADIUS),
		"the dressing's ring mirrors the town's own WALL_RADIUS")
	var props: Array = dressing.get("props")
	check(props.size() >= 20, "the dressing records %d props" % props.size())
	var outside := 0
	for record in props:
		var at: Vector3 = record["position"]
		if Vector2(at.x, at.z).length() > TownScript.WALL_RADIUS:
			outside += 1
	check(outside == 0, "every dressing prop stands inside the ring (%d outside)" % outside)
	var off := 0
	for mesh_instance in meshes_under(dressing):
		if radius_of(world_aabb(mesh_instance)) > TownScript.WALL_RADIUS + 0.05:
			off += 1
	check(off == 0, "every dressing mesh stays inside the ring (%d outside)" % off)
	check(solids_under(dressing).is_empty(),
		"the dressing adds no collider (%d found)" % solids_under(dressing).size())
	check(lights_under(dressing).size() == DressingScript.LANTERN_POSTS.size(),
		"the dressing owns exactly its %d lantern lights" % DressingScript.LANTERN_POSTS.size())


# --- the keepers -----------------------------------------------------------

func check_keepers() -> void:
	check(town.keepers.size() == FolkScript.KEEPERS.size(),
		"one keeper stands behind every counter (%d)" % town.keepers.size())
	for row in FolkScript.KEEPERS:
		var service := str(row["service"])
		var keeper := town.keepers.get(service) as Node3D
		check(keeper != null, "a keeper stands behind the %s" % service)
		if keeper == null:
			continue
		var rig = keeper.get("rig")
		check(rig != null and rig is Node3D, "the %s keeper is a body" % service)
		if rig != null:
			var worn := 0
			for slot in rig.armor_pieces:
				if int(rig.armor_pieces[slot]) != ArmorData.NONE:
					worn += 1
			check(worn == ArmorData.SLOTS.size(),
				"the %s keeper wears a whole armor set (%d of %d slots)"
					% [service, worn, ArmorData.SLOTS.size()])
			var main_id := str(row["main"])
			if main_id.is_empty():
				check(str(rig.weapon) == "none",
					"the %s keeper carries the shield and no blade (%s)" % [service, rig.weapon])
			else:
				check(str(rig.weapon) != "none",
					"the %s keeper is armed (%s)" % [service, rig.weapon])
		# A keeper is a fixture: nothing here may be possessed or fought.
		check(not (keeper is CharacterBody3D),
			"the %s keeper is not a body the soul can take" % service)
		check(not keeper.has_method("take_damage"),
			"the %s keeper cannot be hit" % service)
		check(keeper.get("combat") == null,
			"the %s keeper has no combat target mask" % service)
		# The name over the head, readable through the counter it stands behind.
		var plate := keeper.get_node_or_null("Nameplate") as Label3D
		check(plate != null and plate.text == str(row["name"]),
			"the %s keeper wears their name" % service)
		if plate != null:
			check(plate.no_depth_test and plate.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
				"the %s nameplate reads over the stall" % service)
		# Behind the counter, not in it: the 3 m ring stays a place a body stands.
		var counter: Vector3 = town.service_point(service)
		var gap := keeper.global_position.distance_to(counter)
		check(gap > 0.6 and gap < 1.8,
			"the %s keeper stands a stride behind the counter (%.2f m)" % [service, gap])
		check(keeper.global_position.distance_to(counter) > 0.0
			and standing_clear(counter), "the %s ring is still walkable" % service)


# --- the gold arrow --------------------------------------------------------

func check_marker() -> void:
	var giver = town.quest_giver
	check(giver != null, "the town has a keeper who talks")
	if giver == null:
		return
	check(town.quest_marker != null, "the town owns one gold arrow")
	if town.quest_marker == null:
		return
	check(town.quest_marker.visible, "the arrow is up for a band under the cap")
	check(town.quest_marker.label_text() == "TALK TO HIM",
		"the arrow says what to do (%s)" % town.quest_marker.label_text())
	check(giver.marker_service() == "recruiter",
		"a band short of the cap is the recruiter's business (%s)" % giver.marker_service())
	check(town.quest_marker.target() == town.keepers.get("recruiter"),
		"the arrow rides the recruiter")

	# Fill the band to the cap: the recruiter has nothing left to sell, and the
	# campaign's first order is the quartermaster's.
	while warband.roster.count() < warband.deployment_cap:
		warband.add_mercenary("Oath %d" % warband.roster.count())
	check(warband.roster.count() >= warband.deployment_cap,
		"the band is at the cap (%d)" % warband.roster.count())
	await create_timer(TownScript.MARKER_POLL * 1.6).timeout
	check(giver.marker_service() == "quartermaster",
		"at the cap the arrow is the quartermaster's business (%s)" % giver.marker_service())
	check(town.quest_marker.target() == town.keepers.get("quartermaster"),
		"and it has moved onto the quartermaster")


# --- the keepers' business -------------------------------------------------

func check_talk() -> void:
	var giver = town.quest_giver
	if giver == null:
		return
	var tips = giver.tips
	check(tips != null, "the town has a tip channel to name its lessons on")
	if tips == null:
		return

	# The recruiter: the line once, then the board it teaches.
	var desk: Vector3 = town.service_point("recruiter")
	check(town.interact_at(1, desk) == "recruiter", "G at the desk names the recruiter")
	check(tips.has_shown(GiverScript.HIRE_LESSON), "the first G offers the hire tip")
	check(town.screen.is_open(), "the hire board opens straight away")
	tips.hide()
	await create_timer(0.15).timeout
	check(town.interact_at(1, desk) == "recruiter", "G at the desk names it again")
	check(town.screen.is_open(), "from then on G is the recruiter board itself")
	town.screen.close()

	# The quartermaster: the campaign's first order, handed over at the cap.
	var quartermaster: Vector3 = town.service_point("quartermaster")
	check(town.interact_at(1, quartermaster) == "quartermaster",
		"G at the desk names the quartermaster")
	check(warband.quests.is_active("free_the_soldiers"),
		"the quartermaster's talk accepts the rescue order")
	check(tips.has_shown("offer_free_the_soldiers"), "the order is one tip")
	check(town.quartermaster.is_open(), "his counter opens instead of a page")
	tips.hide()
	await create_timer(0.15).timeout


func check_services() -> void:
	# Every service the loop owns still resolves from its own point, the bench
	# included.
	for service in ["stash", "altar", "recruiter", "quartermaster", "ichor",
			"vendor_orla", "vendor_brann", "vendor_vey", "gate"]:
		var point: Vector3 = town.service_point(service)
		check(point != Vector3.ZERO, "%s has a point in the settlement" % service)
		check(town.service_at(point) == service,
			"the %s ring resolves to itself (got '%s')" % [service, town.service_at(point)])
	check(town.service_at(town.global_position) == "", "the fire is still not a service")

	# The ichor bench: a service, a panel, and a word in the key line.
	var bench: Vector3 = town.service_point("ichor")
	check(town.ichor_bench != null and town.ichor_bench.name == "IchorBench",
		"the ichor bench stands at the quartermaster's side")
	check(town.interact_at(1, bench) == "ichor", "G at the bench names it")
	check(town.bench_panel.is_open(), "the bench panel opens")
	check(town.panels_open(), "an open bench counts as an open panel")
	check(town.hint_line(_at(bench)).contains("ichor bench"),
		"the key line names the bench: %s" % town.hint_line(_at(bench)))
	check(town.prompt_line(_at(bench)).contains("ichor"),
		"the crosshair prompt names the bench")
	town.close_panels()
	check(not town.bench_panel.is_open(), "the bench closes with the rest")

	# While the ichor order is on the ledger the bench is named wherever a body
	# stands, because a reagent in the stash is useless until a player finds it.
	check(warband.quests.offer("bind_the_ichor") or warband.quests.is_active("bind_the_ichor"),
		"the ichor order can be offered")
	if not warband.quests.is_active("bind_the_ichor"):
		warband.quests.accept("bind_the_ichor")
	check(warband.quests.is_active("bind_the_ichor"), "the ichor order is on the ledger")
	var away := _at(Vector3(-2.0, 0.0, 2.0))
	check(town.hint_line(away).contains("ichor bench"),
		"the hint names the bench while the order runs: %s" % town.hint_line(away))

	# The vendors are still three stalls with a keeper each.
	for index in TownScript.VENDOR_SERVICES.size():
		var service := str(TownScript.VENDOR_SERVICES[index])
		check(town.interact_at(1, town.service_point(service)) == service,
			"G at %s opens that stall" % service)
		check(town.vendor_menu.is_open() and town.vendor_menu.vendor_index() == index,
			"%s opens the %d. keeper's stock" % [service, index])
		check(town.vendor_menu.keeper_name() == str(State.VENDORS[index].get("name", "")),
			"%s opens its own keeper" % service)
		town.close_panels()


## A stand-in actor: a point in the square the hint and prompt lines can be
## asked about without moving a real body.
class Probe extends Node3D:
	pass

func _at(point: Vector3) -> Node3D:
	if _probe == null or not is_instance_valid(_probe):
		_probe = Probe.new()
		town.add_child(_probe)
	_probe.global_position = point
	return _probe


# --- the watch -------------------------------------------------------------

func check_guard() -> void:
	check(town.guards.size() == 3, "three archers hold the gate (%d)" % town.guards.size())
	for guard in town.guards:
		check(guard is GuardScript, "a watch archer is a TownGuard")
		var rig = guard.get("rig")
		check(rig != null, "the watch archer has a body")
		if rig != null:
			check(str(rig.weapon) == "bow", "the watch archer holds a bow (%s)" % rig.weapon)
			var worn := 0
			for slot in rig.armor_pieces:
				if int(rig.armor_pieces[slot]) != ArmorData.NONE:
					worn += 1
			check(worn == ArmorData.SLOTS.size(), "the watch is armoured (%d pieces)" % worn)

	# The watch does not stand in the road it watches.
	for z in [18.0, 20.0, 22.0, 24.0]:
		for x in [-1.8, 0.0, 1.8]:
			check(standing_clear(Vector3(x, 0.0, z)),
				"the watch leaves the lane open at (%.1f, %.1f)" % [x, z])

	# A wolf eight metres outside the gate: the watch should notice, draw, and
	# put a real shaft in it.
	var wolf = EnemyScript.new()
	wolf.kind = 0
	wolf.position = town.global_position + Vector3(0.0, 0.05,
		TownScript.WALL_RADIUS + WOLF_OUTSIDE)
	root.add_child(wolf)
	await create_timer(0.25).timeout
	var health: float = float(wolf.health)
	await create_timer(WATCH_SECONDS).timeout
	var shots := 0
	for guard in town.guards:
		shots += int(guard.get("shots"))
	var arrows := arrows_under(town).size()
	print("STOCKADE_WATCH posts=%d shots=%d arrows=%d wolf=%.1f->%.1f" % [
		town.guards.size(), shots, arrows, health, float(wolf.health)])
	check(shots >= 1, "a watch archer drew and let go (%d shots)" % shots)
	check(arrows >= 1, "a real arrow shaft exists in the town (%d)" % arrows)
	check(float(wolf.health) < health,
		"the shaft took health off the wolf (%.1f -> %.1f)" % [health, float(wolf.health)])
	if is_instance_valid(wolf):
		wolf.queue_free()
	await process_frame


## Every `arrow.gd` shaft in the tree: the shout is the same node the world's own
## archers fire, so this is the real thing and not a guard-local effect.
func arrows_under(node: Node, found: Array = []) -> Array:
	var script: Variant = node.get_script() if node is Node else null
	if script is Script and String((script as Script).resource_path).ends_with("arrow.gd"):
		found.append(node)
	for child in node.get_children():
		arrows_under(child, found)
	return found


# --- the town's light ------------------------------------------------------

## Every omni light the town owns, in the town's own space. The paperdoll's
## character stage lights its own preview inside a SubViewport and is not a lamp
## in the settlement, so it is not counted here.
func town_lights(node: Node = null, found: Array = []) -> Array:
	if node == null:
		node = town
	if node is OmniLight3D:
		var inside_stage := false
		var parent := node.get_parent()
		while parent != null:
			if parent is SubViewport:
				inside_stage = true
				break
			parent = parent.get_parent()
		if not inside_stage:
			found.append(node)
	for child in node.get_children():
		town_lights(child, found)
	return found


func check_lights() -> void:
	var lights := town_lights()
	check(lights.size() <= LIGHT_BUDGET,
		"the town stays inside its light budget (%d of %d)" % [lights.size(), LIGHT_BUDGET])
	var hot := 0
	var shadowed := 0
	for light in lights:
		# A lantern flickers around its own figure, so the ceiling is the figure
		# plus a tenth rather than the figure itself.
		if light.light_energy > 3.4:
			hot += 1
		if (light as OmniLight3D).shadow_enabled:
			shadowed += 1
	check(hot == 0, "no town lamp burns hotter than 3.2 plus its flicker (%d)" % hot)
	check(shadowed == 0, "no town lamp casts a shadow (%d)" % shadowed)
	check(town.fire_light != null and town.fire_light.light_energy > 0.0,
		"the fire still burns in the middle of it")
	check(town.flame is MeshInstance3D and town.flame.mesh != null,
		"and the flame is still there to see")
