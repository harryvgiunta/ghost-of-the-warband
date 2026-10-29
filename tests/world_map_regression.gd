extends SceneTree
## The wood grew, and the campaign grew a map to read it by.
##
## Two claims are tested here, both of them headless and both of them geometry
## rather than pixels:
##
##   1. **The lane is a big wood.** `run_forest.build()` stands a road 1,250-1,500 m
##      long on the ground, with a chain of fire along it and nothing solid inside
##      the clear walking band, and the heightfield under it covers the whole of it,
##      the camp's pocket and the town's pad without a single sample falling off the
##      field or up the mountain rim.
##   2. **The map is the ground.** `world_map.configure()` against a stub host that
##      carries the real lane: the projection is uniform and monotonically
##      north-up, every mark it would draw lands on the sheet, the possessor's dot
##      faces the way its body faces, and the scale it quotes is the scale its own
##      bounds and panel imply.
##
## The numbers are read back out of the lane (`stats`, `torches`, `trunks`) rather
## than assumed, so a lane that grows again moves this test with it instead of
## failing it for being longer.

const RunForest = preload("res://scripts/warband/run_forest.gd")
const TerrainScript = preload("res://scripts/warband/terrain.gd")
const MapScript = preload("res://scripts/warband/world_map.gd")
const CampScript = preload("res://scripts/warband/cage_escape.gd")

## The grown road, as a band rather than a number: 1,375 m is the design, and a
## point either way of it - or a hundred - is still the same wood.
const LANE_MIN := 1250.0
const LANE_MAX := 1500.0
## The world's own light ceiling. The torches are the route, so this is the one
## art budget that scales with the road at all.
const LIGHT_CAP := 210
## The world's draw ceiling, and the forest's share of it: the camp and the town
## take the rest of the 800 the world regression enforces.
const DRAW_CAP := 650
## A lane step: 45 m of z plus the drift, and a bend may not be a jump.
const STEP_MAX := 60.0
## How far past the lane's far end the town's square stands - `world_scene.gd`'s
## own number, repeated here because this test builds the ground and the page
## without the scene.
const TOWN_BEHIND := 30.0
const TOWN_PAD := 23.0
const STATE_SAVE := "user://world_map_state.json"
const WARBAND_SAVE := "user://world_map_warband.json"

var checks := 0
var failures := 0


## The town as the map reads it: a node with the square's own wall radius.
class StubTown extends Node3D:
	const WALL_RADIUS := 18.0


## A warband body: a node, the local flag the controller sets on the possessor, and
## the rig its yaw lives on.
class StubBody extends Node3D:
	var is_local := false
	var rig: Node3D = null


## A hostile: a node that can be dead.
class StubGuard extends Node3D:
	var alive := true


## The trail as the map reads it: the forest dictionary `run_forest.build()`
## returns, exactly as `escape_run.gd` holds it.
class StubTrail extends Node3D:
	var forest: Dictionary = {}


## The world as the map reads it: the lane's end, the town, the bodies, the
## hostiles and whatever the campaign wants marked.
class StubWorld extends Node3D:
	var trail = null
	var town = null
	var bodies: Array = []
	var guards: Array = []
	var lane_end_at := Vector3.ZERO
	var marks: Array = []

	func lane_end() -> Vector3:
		return lane_end_at

	func map_markers() -> Array:
		return marks


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("MAP_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _count_type(node: Node, type_name: String) -> int:
	var total := 0
	for child in node.get_children():
		if child.is_class(type_name):
			total += 1
		total += _count_type(child, type_name)
	return total


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func run() -> void:
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node_or_null("PlayerState")
	var warband = root.get_node_or_null("Warband")
	if state != null:
		state.save_path = STATE_SAVE
	if warband != null:
		warband.save_path = WARBAND_SAVE

	var started := Time.get_ticks_msec()
	# --- where the lane will stand in the one world ------------------------
	# The lane's own first point lands a long run of wood past the camp's mouth,
	# and the town stands `TOWN_BEHIND` beyond its far end. Both are derived the
	# way `world_scene.gd` derives them, so the ground this test bakes is the
	# ground the campaign walks.
	var offset := Vector3(CampScript.GATE_POINT.x, 0.0,
		CampScript.GATE_POINT.z - CampScript.CAMP_TO_ROAD_METRES) - RunForest.LANE_POINTS[0]
	var lane_end := (RunForest.LANE_POINTS[RunForest.LANE_POINTS.size() - 1] as Vector3) + offset
	var town_at := lane_end + Vector3(0.0, 0.0, -TOWN_BEHIND)
	var line := PackedVector3Array()
	for point in RunForest.LANE_POINTS:
		line.append((point as Vector3) + offset)

	# --- 1. the ground ----------------------------------------------------
	var ground_host := Node3D.new()
	ground_host.name = "Ground"
	root.add_child(ground_host)
	var pads := [
		{"rect": Rect2(-CampScript.YARD_HALF_WIDTH, CampScript.YARD_FRONT,
			CampScript.YARD_HALF_WIDTH * 2.0, CampScript.YARD_BACK - CampScript.YARD_FRONT),
			"y": TerrainScript.PAD_Y, "blend": 14.0},
		{"rect": Rect2(town_at.x - TOWN_PAD, town_at.z - TOWN_PAD, TOWN_PAD * 2.0,
			TOWN_PAD * 2.0), "y": TerrainScript.PAD_Y, "blend": 16.0},
	]
	var field: Dictionary = TerrainScript.build(ground_host, RunForest.night_style(), pads,
		[{"points": line, "half_width": 3.2}])
	check(TerrainScript.is_built(), "the ground is baked")
	var west := TerrainScript.ORIGIN.x
	var east := TerrainScript.ORIGIN.x + float(TerrainScript.COLS) * TerrainScript.CELL
	var south := TerrainScript.ORIGIN.y
	var north := TerrainScript.ORIGIN.y + float(TerrainScript.ROWS) * TerrainScript.CELL
	check(int(field.get("triangles", 0)) >= 20000,
		"one heightfield covers the longer wood (%d triangles)" % int(field.get("triangles", 0)))
	check(float(field.get("max", 0.0)) - float(field.get("min", 0.0)) >= 2.0,
		"the field rises and falls (%.1f .. %.1f m)"
		% [float(field.get("min", 0.0)), float(field.get("max", 0.0))])

	# Every waypoint of the lane stands inside the field, with the town's pad and
	# its blend still on the field's side of the mountain.
	var inside := true
	var off := Vector3.ZERO
	for point in line:
		if point.x < west or point.x > east or point.z < south or point.z > north:
			inside = false
			off = point
	check(inside, "the whole lane stands on the field (off at %s)" % str(off))
	check(town_at.x - TOWN_PAD - 16.0 >= west and town_at.x + TOWN_PAD + 16.0 <= east
			and town_at.z - TOWN_PAD - 16.0 >= south and town_at.z + TOWN_PAD + 16.0 <= north,
		"the town's pad and its blend are inside the field (%s)" % str(town_at))

	# The camp's pocket is flat, cages and yard floor alike, and so is the square.
	# The check stands a stride inside each pad: a pad blends into the slopes it was
	# cut into over 14-16 m, and the mesh interpolates across the cell that straddles
	# its edge, so its last grid cell is a ramp by design and not a fault.
	var camp_first := TerrainScript.height_at(CampScript.CAGE_POSTS[0].x,
		CampScript.CAGE_POSTS[0].z)
	var camp_flat := true
	for post in CampScript.CAGE_POSTS:
		if absf(TerrainScript.height_at(post.x, post.z) - camp_first) >= 0.01:
			camp_flat = false
	for probe in [Vector2(-CampScript.YARD_HALF_WIDTH + 6.0, 0.0),
			Vector2(CampScript.YARD_HALF_WIDTH - 6.0, 0.0),
			Vector2(0.0, CampScript.YARD_FRONT + 6.0),
			Vector2(0.0, CampScript.YARD_BACK - 6.0)]:
		if absf(TerrainScript.height_at(probe.x, probe.y) - camp_first) >= 0.01:
			camp_flat = false
	check(camp_flat, "the camp's pad is flat (%.4f m)" % camp_first)
	var town_first := TerrainScript.height_at(town_at.x, town_at.z)
	var town_flat := true
	for step in [Vector2(-12.0, -10.0), Vector2(12.0, -10.0), Vector2(-12.0, 10.0),
			Vector2(12.0, 10.0)]:
		if absf(TerrainScript.height_at(town_at.x + step.x, town_at.z + step.y)
				- town_first) >= 0.01:
			town_flat = false
	check(town_flat, "the town's square is flat (%.4f m)" % town_first)

	# `grounded()` answers everywhere along the lane, on the walkable floor and
	# never up on the rim: the route is the route.
	var grounded_ok := true
	var walk_low := INF
	var walk_high := -INF
	for point in line:
		var lifted: Vector3 = TerrainScript.grounded(Vector3(point.x, 0.0, point.z))
		var height: float = TerrainScript.height_at(point.x, point.z)
		if absf(lifted.y - height) >= 0.0001:
			grounded_ok = false
		walk_low = minf(walk_low, height)
		walk_high = maxf(walk_high, height)
	check(grounded_ok, "the ground answers all the way down the lane")
	check(walk_high < 5.0 and walk_low > -5.0,
		"the road stays on the valley floor (%.2f .. %.2f m)" % [walk_low, walk_high])
	check(walk_high - walk_low >= 1.0,
		"the walk goes over real ground (%.2f m of relief)" % (walk_high - walk_low))

	# The mountain rim closes the strip on all four edges.
	var mid_x := (west + east) * 0.5
	var mid_z := (south + north) * 0.5
	var edges := {
		"west": Vector2(west + 0.5, mid_z), "east": Vector2(east - 0.5, mid_z),
		"north": Vector2(mid_x, north - 0.5), "south": Vector2(mid_x, south + 0.5),
	}
	for side in edges:
		var probe: Vector2 = edges[side]
		check(TerrainScript.height_at(probe.x, probe.y) > 20.0,
			"the mountain rim closes the %s edge (%.1f m)"
			% [side, TerrainScript.height_at(probe.x, probe.y)])

	# --- 2. the wood ------------------------------------------------------
	var wood_host := Node3D.new()
	wood_host.name = "Wood"
	root.add_child(wood_host)
	var forest: Dictionary = RunForest.build(wood_host, {"ground": true})
	var length := float(forest.get("length", 0.0))
	var lane: PackedVector3Array = forest.get("lane", PackedVector3Array())
	var path = forest.get("path")
	var torches: Array = forest.get("torches", [])
	var stats: Dictionary = forest.get("stats", {})
	check(length > LANE_MIN and length < LANE_MAX,
		"the trail is a long run now (%.1f m)" % length)
	check(lane.size() >= 30, "the lane is built from its own points (%d)" % lane.size())
	check(path != null and absf(float(path.total) - length) < 0.01,
		"the measured path and the reported length agree")
	check(torches.size() > 100, "the way is a chain of fire (%d torches)" % torches.size())
	check(_count_type(wood_host, "OmniLight3D") <= LIGHT_CAP,
		"the wood stays inside the world's light budget (%d)"
		% _count_type(wood_host, "OmniLight3D"))
	check(int(stats.get("draws", 0)) <= DRAW_CAP,
		"the longer wood stays inside its share of the draw budget (%d multimesh)"
		% int(stats.get("draws", 0)))
	check(int(stats.get("nodes", 0)) < 4000,
		"the longer wood is still batched, not a node per tree (%d nodes)"
		% int(stats.get("nodes", 0)))
	check(int(stats.get("trees", 0)) > 1000 and int(stats.get("bushes", 0)) > 1500,
		"the wood scales with the lane (%d trees, %d bushes)"
		% [int(stats.get("trees", 0)), int(stats.get("bushes", 0))])

	# The lane is one continuous walk: no step is a teleport, and the road's own
	# clearance rule holds for every trunk a body can walk into.
	var longest := 0.0
	for index in range(lane.size() - 1):
		longest = maxf(longest, lane[index].distance_to(lane[index + 1]))
	check(longest <= STEP_MAX, "the lane never jumps (longest step %.1f m)" % longest)
	var trunks: Array = forest.get("trunks", [])
	check(trunks.size() > 100, "the wood publishes the trunks a body can hit (%d)"
		% trunks.size())
	var worst_edge := INF
	var worst_at := Vector3.ZERO
	for trunk in trunks:
		var flat: Vector2 = trunk["at"]
		var radius := float(trunk["radius"])
		var lateral: float = path.distance_to(flat)
		if lateral - radius < worst_edge:
			worst_edge = lateral - radius
			worst_at = Vector3(flat.x, 0.0, flat.y)
	check(worst_edge >= RunForest.CLEAR_HALF,
		"nothing solid stands inside the clear line (%.2f m, at %s)"
		% [worst_edge, str(worst_at)])
	# ... and no lane point is off the walkable floor the field bakes under it.
	var on_ground := true
	for point in lane:
		if absf(TerrainScript.height_at(point.x, point.z)) > 2.2:
			on_ground = false
	check(on_ground, "every lane point stands on the walkable floor")

	# --- 3. the map -------------------------------------------------------
	var host := StubWorld.new()
	host.name = "StubWorld"
	root.add_child(host)
	var trail := StubTrail.new()
	trail.name = "Trail"
	trail.forest = forest
	host.add_child(trail)
	host.trail = trail
	var town := StubTown.new()
	town.name = "Town"
	town.position = town_at
	host.add_child(town)
	host.town = town
	host.lane_end_at = lane_end
	for index in 3:
		var body := StubBody.new()
		body.name = "Body%d" % index
		body.rig = Node3D.new()
		body.add_child(body.rig)
		host.add_child(body)
		body.global_position = lane[index * 10]
		body.is_local = index == 0
		body.rig.rotation.y = 0.6
		host.bodies.append(body)
	for index in 2:
		var guard := StubGuard.new()
		guard.name = "Guard%d" % index
		host.add_child(guard)
		guard.global_position = path.verge(length * (0.3 + 0.3 * float(index)), 1.4)
		guard.alive = index == 0
		host.guards.append(guard)
	host.marks = [
		{"position": path.verge(length * 0.5, 0.0), "label": "THE RECRUITER",
			"kind": "recruiter"},
		{"position": Vector3(420.0, 0.0, -980.0), "label": "FAR CONTRACT",
			"kind": "quartermaster"},
	]
	var map = MapScript.new()
	map.name = "Map"
	root.add_child(map)
	map.configure(host)

	var page: Rect2 = map.page_rect()
	var panel: Rect2 = map.panel_rect()
	var bounds: Rect2 = map.map_bounds()
	var scale := map.scale_metres_per_pixel()
	check(page.size.x >= 200.0 and page.size.y >= 300.0,
		"the sheet is a page sized to the window (%.0f x %.0f)"
		% [page.size.x, page.size.y])
	check(panel.size.x > 8.0 and panel.size.y > 100.0,
		"the road band is a band, not a line (%.1f x %.1f)"
		% [panel.size.x, panel.size.y])
	check(bounds.encloses(Rect2(Vector2(west, south), Vector2(east - west, north - south)))
			== false, "the sheet covers the lane's own strip, not the whole field")
	check(bounds.has_point(Vector2.ZERO) and bounds.has_point(Vector2(town_at.x, town_at.z)),
		"the page holds the camp and the town (%s)" % str(bounds))
	check(absf(scale * panel.size.x - bounds.size.x) <= 0.01
			and absf(scale * panel.size.y - bounds.size.y) <= 0.01,
		"the scale is the bounds and the panel agreeing (%.4f m/px)" % scale)

	# The road: one continuous line from the camp's end of the page to the town's,
	# monotonically north-up, every point on the band.
	var drawn: PackedVector2Array = map.road()
	check(drawn.size() >= 100, "the road is sampled along the lane (%d points)" % drawn.size())
	var monotonic := true
	var on_band := true
	var wobble := 0.0
	var middle := panel.get_center().x
	for index in drawn.size():
		var point := drawn[index]
		if not panel.grow(0.5).has_point(point):
			on_band = false
		wobble = maxf(wobble, absf(point.x - middle))
		if index > 0 and point.y > drawn[index - 1].y + 0.001:
			monotonic = false
	check(monotonic, "the road reads north-up, one way up the page")
	check(on_band, "the road never leaves its band")
	check(wobble > 1.0 and wobble < panel.size.x * 0.5,
		"the road wanders inside its band (%.1f px off the middle)" % wobble)
	var camp_screen: Vector2 = map.project(Vector3.ZERO)
	var town_screen: Vector2 = map.project(town_at)
	check(camp_screen.y > town_screen.y,
		"the camp is at the bottom of the page and the town at the top (%.0f vs %.0f)"
		% [camp_screen.y, town_screen.y])
	check(drawn[0].distance_to(map.project(lane[0])) < 0.01
			and drawn[drawn.size() - 1].distance_to(map.project(lane[lane.size() - 1])) < 0.01,
		"the drawn road starts and ends on the lane's own ends")

	# The marks: one of each kind the page claims to draw, every one of them on the
	# sheet, the possessor's facing carried through, and a mark that is off the page
	# pinned to its edge rather than drawn somewhere it is not.
	var marks: Array[Dictionary] = map.markers()
	var kinds := {}
	var off_page := 0
	var pinned := 0
	var soul_yaw := INF
	for mark in marks:
		kinds[str(mark["kind"])] = int(kinds.get(str(mark["kind"]), 0)) + 1
		var screen: Vector2 = mark["screen"]
		if not panel.grow(0.5).has_point(screen):
			off_page += 1
		if bool(mark.get("pinned", false)):
			pinned += 1
		if str(mark["kind"]) == "soul":
			soul_yaw = float(mark["yaw"])
	for kind in ["camp", "town", "clearing", "quest", "hostile", "body", "soul"]:
		check(int(kinds.get(kind, 0)) >= 1, "the sheet marks the %s" % kind)
	check(int(kinds.get("clearing", 0)) == 4,
		"every clearing of the lane is on the page (%d)" % int(kinds.get("clearing", 0)))
	check(int(kinds.get("hostile", 0)) == 1,
		"only the living are marked as hostiles (%d marks)" % int(kinds.get("hostile", 0)))
	check(int(kinds.get("quest", 0)) == 2, "both of the campaign's marks are on the page")
	check(off_page == 0, "every mark lands on the sheet (%d off)" % off_page)
	check(pinned == 1, "only the mark that stands off the wood is pinned (%d)" % pinned)
	check(absf(soul_yaw - 0.6) < 0.001,
		"the possessor's mark carries its body's facing (%.2f)" % soul_yaw)
	var labels := {}
	for mark in marks:
		labels[str(mark["label"])] = true
	check(labels.has("THE CAMP") and labels.has("THE TOWN"),
		"the camp and the town are named on the page")
	check(labels.has("CLEARING 1") and labels.has("CLEARING 4"),
		"the clearings are named on the page")
	check(labels.has("THE RECRUITER") and labels.has("FAR CONTRACT"),
		"the campaign's own marks keep their names")
	check(map.title() == "THE WOOD", "the page carries its one-line title (%s)" % map.title())
	var town_radius := 0.0
	for mark in marks:
		if str(mark["kind"]) == "town":
			town_radius = float(mark.get("radius", 0.0))
	check(is_equal_approx(town_radius, StubTown.WALL_RADIUS),
		"the town is drawn at its own wall radius (%.1f m)" % town_radius)

	var legend: Array[String] = map.legend()
	check(legend.size() >= 4, "the sheet carries a legend (%d lines)" % legend.size())
	var legend_has_text := true
	for entry in legend:
		if entry.strip_edges().is_empty():
			legend_has_text = false
	check(legend_has_text, "no line of the legend is empty")

	# Opening and closing: the pointer comes back for the page and is captured
	# again after it, and the tree is never stopped for either.
	check(not map.is_open(), "the map starts shut")
	map.open()
	check(map.is_open() and map.visible, "M opens the page")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the pointer comes back for the page")
	var paused_before: bool = paused
	map.close()
	check(not map.is_open() and not map.visible, "closing the page puts it away")
	# The headless display server has no pointer to capture, so the capture is only
	# asserted where there is one; the visible half above holds in both.
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the pointer is captured again")
	check(paused == paused_before, "the map never stops the wood")
	map.toggle()
	check(map.is_open(), "the toggle opens it")
	map.toggle()
	check(not map.is_open(), "the toggle closes it")
	map.open()
	# Two frames so the board actually paints what the assertions just described.
	await process_frame
	await process_frame
	map.close()

	print("WORLD_MAP lane=%.1f torches=%d trees=%d bushes=%d trunks=%d nodes=%d draws=%d lights=%d"
		% [length, torches.size(), int(stats.get("trees", 0)), int(stats.get("bushes", 0)),
			trunks.size(), int(stats.get("nodes", 0)), int(stats.get("draws", 0)),
			_count_type(wood_host, "OmniLight3D")])
	print("WORLD_MAP sheet bounds=%.0fx%.0fm panel=%.0fx%.0fpx scale=%.3f m/px marks=%d"
		% [bounds.size.x, bounds.size.y, panel.size.x, panel.size.y, scale, marks.size()])
	print("WORLD_MAP_REGRESSION checks=%d failures=%d seconds=%.1f"
		% [checks, failures, float(Time.get_ticks_msec() - started) / 1000.0])
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	quit(1 if failures > 0 else 0)
