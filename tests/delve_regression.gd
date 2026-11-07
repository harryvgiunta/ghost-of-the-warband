extends SceneTree
## The delve loop on the real world: make up a party and a delve inventory at the
## Weeping Hollow's mouth, go down into a fresh instance, wake a den, kill and loot
## below, lose a member and take his kit back, climb out with it, then go down
## again and fall.
##
## What it holds the loop to:
##   * packing moves free pieces from the town stash into the delve inventory and
##     back; the descent is written to the save at once;
##   * the party lands together in one of the floor's six shafts, each in its own
##     area and far from the next, and the draw spreads parties over all six;
##   * the squad's map walks every shaft to the lair and to every other shaft, no
##     sleeper can see a landing, every den's post is open ground, and every den is
##     crowded to its own `crowd` a post inside its own room;
##   * the floor is three rings - shafts, the demons' ring with one demon a chamber,
##     and the centre's squad of several demon species - and most rooms keep a bow;
##   * the floor is built `SCALE` times the authored plan - every shaft, den post,
##     light and prop still on its own room's floor, no room wider than the eye's
##     reach;
##   * only the bodies inside `BODY_HIDE_DISTANCE` of the eye are drawn, and a
##     hidden body is still a body: it keeps its brain, its clock and its place;
##   * below, the party is the only thing a soul or a paperdoll can reach, the
##     quiver is the inventory, and everything taken - by a right click, the window
##     or a squadmate - lands in the inventory and never in the stash; a right
##     click takes a whole body and the steel beside it and dresses nobody;
##   * a den sleeps until a body is in its room, then joins the hostile list whole,
##     and falls leaving a thin share of its kit; anointed steel off a body wakes
##     its skill as it is taken;
##   * a member who dies below keeps his kit on his body, booked for nobody and
##     left alone by the squad, until a right click takes it back;
##   * climbing out - at any shaft's rope - brings the party up and empties the
##     inventory into the stash, the Ritual Tallow it carried into the wallet;
##   * falling loses the inventory and everything the party wears, and wakes the
##     downed in the square;
##   * a save still holding a party below loads as a fall.

const WorldScene := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://delve_player.json"
const WARBAND_SAVE := "user://delve_warband.json"
const AreaScript = preload("res://scripts/warband/delve_area.gd")
const Layout = preload("res://scripts/warband/delve_layout.gd")
const Floor = preload("res://scripts/warband/delve_floor.gd")
const DelveMode = preload("res://scripts/warband/delve_mode.gd")
const TownHub = preload("res://scripts/warband/town_hub.gd")

var state
var warband
var flow
var game
var checks := 0
var failures := 0
## The easy floor's dials on one named body, for the hard floor to be compared
## against: the same authored post stands on both, so a hard floor must be four
## times its pool, twice its pace and half its beat.
var _probe_name := ""
var _probe_pool := 0.0
var _probe_walk := 0.0
var _probe_beat := 0.0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DELVE_FAIL  ", message)


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
	await create_timer(0.8).timeout
	if game == null or game.get("delve_area") == null:
		check(false, "the world opened with a delve")
		_finish()
		return
	await check_mouth_and_pack()
	await check_descent()
	check_floor_plan()
	check_demon_ring()
	check_difficulty()
	check_plan_geometry()
	check_floor_relief()
	check_eye_culling()
	await check_floor_map()
	await _gather_at("mouth")
	await check_den_and_loot()
	await check_fallen_member()
	await check_climb_out()
	await check_fall()
	check_load_forfeit()
	_finish()


func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	for path in [TEST_SAVE, WARBAND_SAVE]:
		_remove(path)
	print("DELVE_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _soul():
	return game.controller.active_body(1)


## A staged descent: wait until the floor is whole (and the panel that asked for
## it has closed). A ceiling in frames, so a stuck build fails the run in ~15 s
## rather than hanging it.
func _await_floor(limit: int = 900) -> void:
	var waited := 0
	while waited < limit:
		var area = game.delve_area
		var soul = game.controller.active_body(1)
		if area != null and area.below() and not area.building() and not area.prep.is_open() \
				and soul != null and is_instance_valid(soul) and area.in_cave(soul):
			return
		await process_frame
		waited += 1


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame


## Walk the soul to a spot, when the party below still has one. A body the books
## have lost fails the check that looked for it; it must not take the rest of the
## staged block down with an engine error.
func _soul_to(soul, at: Vector3, yaw: float = 0.0) -> void:
	if soul == null or not is_instance_valid(soul):
		return
	soul.teleport_to(at, yaw)


## The row's own press, handed to the panel exactly the way the button hands a
## click on. What a real mouse adds on top is Godot's own hit test, and the
## windowed captures under `tools/ui_theme` are where that is driven.
func _press_row(control: Control, shift: bool = false) -> void:
	if control == null or not is_instance_valid(control):
		check(false, "a row to press")
		return
	if shift:
		Input.parse_input_event(_key_event(KEY_SHIFT, true))
		await process_frame
	(control as BaseButton).pressed.emit()
	if shift:
		Input.parse_input_event(_key_event(KEY_SHIFT, false))
	await process_frame


func _key_event(code: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.key_label = code
	event.pressed = pressed
	return event


## Whether the warband owns a piece anywhere: the stash or any body's slots.
func _owned(item_id: String) -> bool:
	if warband.stash.pooled_count(item_id) > 0:
		return true
	for merc_id in warband.roster.ids():
		for entry in warband.roster.worn_entries(merc_id):
			if str(entry.get("item", "")) == item_id:
				return true
	return false


# --- the mouth and the pack ------------------------------------------------

var _party: Array[int] = []
var _stayer := -1

## The names this test swears to its band, and the piece each one is owed by the
## square's shelf if the shelf has none of it left.
const SWORN := [["Brine", "sword_short"], ["Cael", "club_makeshift"]]

## The band a campaign opens with is one naked body (`Warband.STARTING_BAND`), and
## a naked body alone has nobody below to lose and nothing to lose: the delve's own
## party is sworn here, at the square's fire, the way a player swears it - each name
## taken onto the roster (`Warband.add_mercenary`) and dressed out of the shared
## shelf (`Warband.dress_recruit`), with the one piece the shelf could not spare put
## back into it by hand first. The world lays a body for a place taken after it was
## seated (`WorldScene._sync_field`), so the musters stand in the square a frame or
## two before the mouth is used.
func _swear_party() -> void:
	# One naked body is what the town seeded (`TownHub.seed_warband`); the two
	# sworn here are the test's own, and the count every check below reads is this.
	var band: int = warband.STARTING_BAND.size() + SWORN.size()
	for entry in SWORN:
		var sworn: int = warband.add_mercenary(str(entry[0]))
		check(sworn > 0, "%s swears to the warband" % str(entry[0]))
		if sworn <= 0:
			continue
		# The shelf is the only armorer: a piece the first recruit took is stood
		# back on it before the second one's oath, so nobody is dressed from air.
		if warband.stash.pooled_count(str(entry[1])) <= 0:
			warband.stash.add(str(entry[1]), 1)
		var dressed: Dictionary = warband.dress_recruit(sworn)
		check(bool(dressed.get("ok", false)), "%s is armed out of the shelf (%s)"
			% [str(entry[0]), str(dressed.get("message", ""))])
		if warband.roster.worn_entries(sworn).is_empty():
			warband.equip_merc(sworn, "main", str(entry[1]))
		check(not warband.roster.worn_entries(sworn).is_empty(),
			"%s takes the field dressed" % str(entry[0]))
	# An oath is the pool's (`dress_recruit` walks every slot): the two recruits
	# took what the shared shelf could spare, so the square is stocked back to the
	# one spare of each piece it opens with (`TownHub.TOWN_SPARES`). The packing
	# checks below read that shelf, and a band that swears musters a fresh one.
	for item_id in TownHub.TOWN_SPARES:
		if warband.stash.pooled_count(str(item_id)) <= 0:
			warband.stash.add(str(item_id), 1)
	check(warband.roster.count() == band,
		"the band is one and the two sworn here (%d)" % warband.roster.count())
	check(warband.roster.field_ids().size() == band,
		"and every one of them stands on the field (%d of %d)"
		% [warband.roster.field_ids().size(), band])
	await _frames(4)
	var bodied := 0
	for merc_id in warband.roster.field_ids():
		var body = game.controller.body_of(int(merc_id))
		if body != null and is_instance_valid(body):
			bodied += 1
	check(bodied == band, "every name on the field has a body in the square (%d of %d)"
		% [bodied, band])


func check_mouth_and_pack() -> void:
	await _swear_party()
	var area = game.delve_area
	var soul = _soul()
	check(soul != null, "a body stands in the square")
	check(area.mouth != null and area.mouth.get_node_or_null("MouthName") != null,
		"the Hollow's mouth stands in the square, named")
	if soul != null:
		soul.teleport_to(area.mouth_point() + Vector3(0.0, 0.12, 2.2), 0.0)
	await _frames(2)
	check(area.at_mouth(soul), "a body by the pit is at the mouth")
	check(area.prompt_line(soul) == AreaScript.MOUTH_PROMPT,
		"the crosshair names the way down (%s)" % area.prompt_line(soul))
	# The supplies a party is never asked to pack by hand.
	warband.stash.add("bandage_linen", 4)
	var quiver: int = warband.stash.pooled_count("arrow")
	var dressings: int = warband.stash.pooled_count("bandage_linen")
	game._try_interact()
	check(area.prep.is_open(), "G at the mouth opens the delve panel")
	# The floor's difficulty: the panel opens on EASY, and the three plates are the
	# warband's own choice (`Warband.set_delve_mode`) - the floor below is built from
	# it, so the press has to land on the books and be refused where they are not
	# the player's to write.
	var modes: Dictionary = area.prep.mode_buttons()
	check(modes.size() == 3, "the mouth offers three difficulties (%d)" % modes.size())
	check(area.prep.mode() == DelveMode.DEFAULT and warband.delve.mode == DelveMode.DEFAULT,
		"a band that has never been down opens on the easy Hollow (%s)" % area.prep.mode())
	(modes["hard"] as Button).pressed.emit()
	check(area.prep.mode() == "hard" and warband.delve.mode == "hard",
		"a press on HARD puts the next descent on hard (%s)" % area.prep.mode())
	check((modes["hard"] as Button).button_pressed and not (modes["easy"] as Button).button_pressed,
		"and the plate lit is the one pressed")
	check(not bool(warband.set_delve_mode("brutal").get("ok", false))
			and warband.delve.mode == "hard",
		"a difficulty the Hollow does not have is refused")
	(modes["easy"] as Button).pressed.emit()
	check(area.prep.mode() == "easy" and (modes["easy"] as Button).button_pressed,
		"and the party is put back on the easy Hollow")
	var offered: Array[int] = area.prep.candidates()
	check(offered.size() == warband.roster.field_ids().size()
			and offered.size() == warband.STARTING_BAND.size() + SWORN.size(),
		"every standing body is offered (%d of %d on the field)"
		% [offered.size(), warband.roster.field_ids().size()])
	check(area.prep.selected().size() == offered.size(), "and every one starts chosen")
	check(quiver > 0 and dressings > 0, "the town keeps a quiver and dressings (%d / %d)" % [
		quiver, dressings])
	check(warband.delve.inventory.pooled_count("arrow") == quiver
			and warband.stash.pooled_count("arrow") == 0,
		"the quiver is packed the moment the page opens (%d)" % quiver)
	check(warband.delve.inventory.pooled_count("bandage_linen") == dressings
			and warband.stash.pooled_count("bandage_linen") == 0,
		"and so are the bandages (%d)" % dressings)
	# A click sends one copy; the prompt a shift-click opens sends as many as it is
	# told, and never fewer than one.
	area.prep.unpack("arrow")
	check(warband.stash.pooled_count("arrow") == 1
			and warband.delve.inventory.pooled_count("arrow") == quiver - 1,
		"one click sends a single shaft back to the stash (%d)" % quiver)
	area.prep.open_count("arrow", true)
	area.prep.submit_count(0)
	check(warband.stash.pooled_count("arrow") == 0
			and warband.delve.inventory.pooled_count("arrow") == quiver,
		"a typed zero still moves one copy, no more and no less")
	check(not area.prep.count_open(), "and the prompt shuts once it has moved")
	var ask := mini(6, quiver)
	area.prep.click("arrow", false, true)
	check(area.prep.count_open() and area.prep.prompt_item() == "arrow",
		"a shift-click opens the how-many prompt on that row")
	area.prep.submit_count(ask)
	check(warband.stash.pooled_count("arrow") == ask
			and warband.delve.inventory.pooled_count("arrow") == quiver - ask,
		"the typed %d shafts come back to the stash" % ask)
	area.prep.open_count("arrow", true)
	area.prep.submit_count(-1)
	check(warband.stash.pooled_count("arrow") == 0
			and warband.delve.inventory.pooled_count("arrow") == quiver,
		"and ALL packs every spare shaft down again (%d)" % quiver)
	# The rows themselves, driven the way a player drives them: a real left click
	# on a stash row sends one copy, a shift-click asks how many instead. The top
	# row is used because the list scrolls and a piece further down is out of view.
	var rows: Array[Dictionary] = area.prep.stash_rows()
	check(rows.size() > 0, "the stash has rows to click (%d)" % rows.size())
	if not rows.is_empty():
		var clicked_id := str(rows[0]["item_id"])
		var clicked_before: int = warband.stash.pooled_count(clicked_id)
		var clicked_row: Control = area.prep.stash_row_control(clicked_id)
		check(clicked_row != null and clicked_before > 0,
			"the top stash row is a piece to click (%s)" % clicked_id)
		if clicked_row != null:
			await _press_row(clicked_row)
			check(warband.stash.pooled_count(clicked_id) == clicked_before - 1
					and warband.delve.inventory.pooled_count(clicked_id) == 1,
				"a click on the row packs exactly one copy")
			var packed_row: Control = area.prep.pack_row_control(clicked_id)
			check(packed_row != null, "the inventory shows the piece that went down")
			if packed_row != null:
				await _press_row(packed_row, true)
				check(area.prep.count_open() and area.prep.prompt_item() == clicked_id,
					"and a shift-click asks how many instead of moving anything")
				check(warband.delve.inventory.pooled_count(clicked_id) == 1,
					"which moves nothing until the number is given")
				area.prep.cancel_count()
				packed_row = area.prep.pack_row_control(clicked_id)
				await _press_row(packed_row)
				check(warband.delve.inventory.pooled_count(clicked_id) == 0
						and warband.stash.pooled_count(clicked_id) == clicked_before,
					"and a click on the packed row brings that one copy back")
	# A spare is a copy nobody wears: a worn one is on a body, not on the shelf.
	if warband.stash.pooled_count("sword_arming") <= 0:
		warband.stash.add("sword_arming", 1)
	var spare_before: int = warband.stash.pooled_count("sword_arming")
	area.prep.pack("sword_arming")
	check(warband.delve.inventory.pooled_count("sword_arming") == 1, "a click packs one spare blade")
	area.prep.unpack("sword_arming")
	check(warband.stash.pooled_count("sword_arming") == spare_before, "and unpacking puts it back")
	area.prep.pack("sword_arming")
	_stayer = offered[offered.size() - 1]
	area.prep.set_member(_stayer, false)
	_party = area.prep.selected()
	check(_party.size() == offered.size() - 1 and not _party.has(_stayer),
		"one body is left home (%s)" % str(_party))


# --- going down ------------------------------------------------------------

func check_descent() -> void:
	var area = game.delve_area
	# GO DOWN draws the shaft; a fixed draw keeps the run repeatable.
	area._draw.seed = 20261031
	area.prep.descend_requested.emit(area.prep.selected())
	# A descent builds the floor across frames now (the window keeps painting
	# under GOING DOWN), so the test waits for the floor, not three frames.
	await _await_floor()
	check(not area.prep.is_open(), "GO DOWN closes the panel")
	check(area.below() and warband.delve.active, "the party is below")
	check(warband.delve.party == _party, "the books hold the chosen party (%s)" % str(warband.delve.party))
	var cave = area.cave
	check(cave != null, "the floor is built under the party that came down")
	if cave == null:
		return
	var landed: Dictionary = Layout.landing(area.landing)
	check(not landed.is_empty(), "the party came down one of the shafts (%s)" % area.landing)
	var shaft := Layout.room_index(str(landed.get("room", "")))
	for merc_id in _party:
		var body = game.controller.body_of(merc_id)
		var local: Vector3 = cave.to_local(body.global_position) if body != null else Vector3.INF
		check(body != null and shaft >= 0 and Layout.room_index_at(Vector2(local.x, local.z)) == shaft,
			"%s landed in the %s shaft" % [warband.roster.name_of(merc_id), area.landing])
	var stayer_body = game.controller.body_of(_stayer)
	check(stayer_body != null and game.town.in_square(stayer_body), "the body left home is in the square")
	check(_party.has(int(game.controller.merc_for_peer(1))), "the soul went down with the party")
	var refused: Dictionary = game.controller.direct(1, _stayer)
	check(not bool(refused.get("ok", true)), "a soul below cannot take the body left home")
	check(not game._is_free_ally(_stayer), "and the squad leaves that body standing")
	check(warband.arrows() == warband.delve.inventory.pooled_count("arrow") and warband.arrows() > 0,
		"below, the quiver is the delve inventory (%d)" % warband.arrows())
	var equip: Dictionary = warband.equip_merc(_stayer, "main", "sword_arming")
	check(not bool(equip.get("ok", true)), "a body in the town cannot be dressed from below")
	var file := FileAccess.open(WARBAND_SAVE, FileAccess.READ)
	var saved: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	check(saved is Dictionary and bool((saved as Dictionary).get("delve", {}).get("active", false)),
		"going down is written to the save at once")
	# The eye eases down after the body from wherever it was in the town; a far
	# shaft takes it a moment longer to arrive than the mouth does.
	var waited := 0.0
	while waited < 2.0 and game.camera.environment != cave.environment:
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(0.25).timeout
	check(game.camera.environment == cave.environment, "the eye below has the cave's sky (%.1f s)" % waited)
	var sun = game.find_child("WorldSun", true, false)
	check(sun == null or not sun.visible, "and the moon is out")
	check(game.squad.nav == cave.nav and cave.nav != null, "the squad walks the cave's map")
	var listed := 0
	for mob in cave.mobs():
		if game.guards.has(mob):
			listed += 1
	check(not cave.is_awake("den") and listed == 0, "every den sleeps off the hostile list (%d listed)" % listed)
	check(game.loot_feed.header_text().contains(Layout.area_name(str(landed.get("area", "")))),
		"the floor's line names the area the party landed in (%s)" % game.loot_feed.header_text())
	check(game.delve_area.prompt_line(_soul()).begins_with("SLAY GOREHORN"),
		"the crosshair names the floor's objective (%s)" % game.delve_area.prompt_line(_soul()))


# --- the floor --------------------------------------------------------------

## The floor is laid out for more than one party: six shafts, each in its own
## area and far from the next, a draw that hands parties different shafts as far
## apart as it can, ways that join every shaft to the lair and to each other on
## the squad's own map, no den that can see anybody land, and every den crowded to
## `den_crowd` bodies for each post it was written with, each inside its own room.
func check_floor_plan() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to lay out")
	if cave == null:
		return
	var areas := {}
	var closest := INF
	for first in Layout.LANDINGS.size():
		areas[str(Layout.LANDINGS[first]["area"])] = true
		for second in range(first + 1, Layout.LANDINGS.size()):
			closest = minf(closest, (Layout.LANDINGS[first]["centre"] as Vector3).distance_to(
				Layout.LANDINGS[second]["centre"]))
	check(Layout.LANDINGS.size() >= 6 and areas.size() == Layout.LANDINGS.size(),
		"six shafts or more, each in its own area (%d shafts, %d areas)" % [Layout.LANDINGS.size(), areas.size()])
	check(closest >= 50.0, "no two shafts are closer than 50 m (%.1f m)" % closest)
	var thin: Array[String] = []
	for spec in Layout.DENS:
		var fielded: Array = cave.den_mobs(str(spec["id"]))
		var room: Rect2 = Layout.room(str(spec["room"]))["rect"]
		var inside := 0
		for mob in fielded:
			var at: Vector3 = cave.to_local(mob.global_position)
			if room.has_point(Vector2(at.x, at.z)):
				inside += 1
		if fielded.size() != Layout.den_bodies(spec, warband.delve.mode) or inside != fielded.size():
			thin.append("%s %d/%d" % [spec["id"], inside, fielded.size()])
	check(thin.is_empty(), "every den fields its crowd a post, all in its own room (%s)" % str(thin))
	var misplaced: Array[String] = []
	for entry in Layout.LANDINGS:
		var shaft := Layout.room_index(str(entry["room"]))
		for post in cave.entry_posts(str(entry["id"]), cave.ENTRY_POSTS):
			var local: Vector3 = cave.to_local(post)
			var climbing := false
			for rope_entry in Layout.LANDINGS:
				if post.distance_to(cave.rope_point(str(rope_entry["id"]))) <= cave.EXIT_REACH + 0.2:
					climbing = true
			if climbing or Layout.room_index_at(Vector2(local.x, local.z)) != shaft \
					or cave.nav.free_point(post).distance_to(post) > 0.01:
				misplaced.append("%s %s" % [entry["id"], str(local)])
	check(misplaced.is_empty(),
		"every landing post is open ground in its own shaft, out of every rope's reach (%s)" % str(misplaced))
	var spread := true
	for seed_value in 8:
		var every: Array[String] = Layout.landings_for(Layout.LANDINGS.size() + 2, seed_value)
		var distinct := {}
		for landing_id in every:
			distinct[landing_id] = true
		if every.size() != Layout.LANDINGS.size() or distinct.size() != every.size():
			spread = false
		var pair: Array[String] = Layout.landings_for(2, seed_value)
		var first: Vector3 = Layout.landing(pair[0])["centre"]
		var gap := first.distance_to(Layout.landing(pair[1])["centre"])
		for entry in Layout.LANDINGS:
			if first.distance_to(entry["centre"]) > gap + 0.01:
				spread = false
	check(spread, "the draw gives every party its own shaft, the second as far from the first as there is")
	var master: Vector3 = cave.to_global(Layout.MASTER_POINT)
	var stranded: Array[String] = []
	for first in Layout.LANDINGS.size():
		var from: Vector3 = cave.to_global(Layout.LANDINGS[first]["centre"])
		var goals := {"lair": master}
		for second in range(first + 1, Layout.LANDINGS.size()):
			goals[str(Layout.LANDINGS[second]["id"])] = cave.to_global(Layout.LANDINGS[second]["centre"])
		for goal_id in goals:
			var goal: Vector3 = goals[goal_id]
			var path: PackedVector3Array = cave.nav.route(from, goal)
			if path.is_empty() or Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(
					Vector2(goal.x, goal.z)) > 1.0:
				stranded.append("%s->%s" % [Layout.LANDINGS[first]["id"], goal_id])
	check(stranded.is_empty(), "the squad's map walks every shaft to the lair and to every other shaft (%s)"
		% str(stranded))
	var space: PhysicsDirectSpaceState3D = cave.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	var seen: Array[String] = []
	var buried: Array[String] = []
	for mob in cave.mobs():
		var home: Vector3 = mob.global_position
		if cave.nav.free_point(home).distance_to(home) > 0.01:
			buried.append(str(mob.name))
		var reach := float((mob.get("profile") as Dictionary).get("sight", 34.0))
		var eye := home + Vector3(0.0, 1.8, 0.0)
		for entry in Layout.LANDINGS:
			for post in cave.entry_posts(str(entry["id"]), cave.ENTRY_POSTS):
				var chest: Vector3 = post + Vector3(0.0, 1.25, 0.0)
				if eye.distance_to(chest) > reach:
					continue
				query.from = eye
				query.to = chest
				if space.intersect_ray(query).is_empty():
					seen.append("%s->%s" % [mob.name, entry["id"]])
	check(seen.is_empty(), "no sleeper has a line of sight to a landing (%s)" % str(seen))
	check(buried.is_empty(), "every den's post is open ground on the squad's map (%s)" % str(buried))


## The floor's three rings: the six shafts on the outer rim, the demons' ring of
## four chambers round the lair - one demon and its archers a chamber - and the
## centre, which keeps a squad of several demon species and Gorehorn himself. Most
## of the floor's rooms keep a bow of their own: a watcher with a bow is not a
## curiosity below, it is what holds the far side of a room while the rest close.
func check_demon_ring() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to read its rings")
	if cave == null:
		return
	var chambers: Array[String] = []
	for spec in Layout.DENS:
		if str(Layout.room(str(spec["room"])).get("area", "")) == "ring":
			chambers.append(str(spec["id"]))
	check(chambers.size() == 4, "four chambers ring the lair (%d)" % chambers.size())
	var wrong: Array[String] = []
	for den_id in chambers:
		var demons := 0
		var bows := 0
		for mob in cave.den_mobs(den_id):
			if mob.has_method("demon"):
				demons += 1
			elif mob.has_method("begin_ambush"):
				bows += 1
		if demons != 1 or bows < 1:
			wrong.append("%s %d demon(s) %d bow(s)" % [den_id, demons, bows])
	check(wrong.is_empty(),
		"every chamber of the ring keeps one demon, and archers with it (%s)" % str(wrong))
	var squad := {}
	var guard_bows := 0
	for mob in cave.den_mobs("lair_guard"):
		if mob.has_method("demon"):
			squad[str(mob.get("mob_id"))] = true
		elif mob.has_method("begin_ambush"):
			guard_bows += 1
	check(squad.size() >= 3,
		"the centre keeps a squad of several demon species (%s)" % str(squad.keys()))
	check(guard_bows >= 1, "and its own archers hold the sides (%d)" % guard_bows)
	check(cave.master != null and bool(cave.master.get("boss")) and bool(cave.master.get("alive")),
		"Gorehorn holds the centre himself")
	var armed := 0
	for spec in Layout.DENS:
		var bows := 0
		for mob in cave.den_mobs(str(spec["id"])):
			if mob.has_method("begin_ambush"):
				bows += 1
		if bows > 0:
			armed += 1
	check(armed * 2 > Layout.DENS.size(),
		"most of the floor's rooms keep a bow (%d of %d dens)" % [armed, Layout.DENS.size()])
	# The ring is a loop and not four spokes: each corner's arc walks to both of the
	# chambers it joins, so a party can go round the ring without crossing the lair.
	var corners := {"ring_sw_jog": ["ring_s", "ring_w"], "ring_se_jog": ["ring_s", "ring_e"],
		"ring_ne_jog": ["ring_n", "ring_e"], "ring_nw_run": ["ring_w", "ring_n"]}
	var broken: Array[String] = []
	for arc_id in corners:
		var from_point: Vector3 = cave.to_global(_room_centre(arc_id))
		for room_id in corners[arc_id]:
			var goal: Vector3 = cave.to_global(_room_centre(room_id))
			var path: PackedVector3Array = cave.nav.route(from_point, goal)
			if path.is_empty() or Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(
					Vector2(goal.x, goal.z)) > 1.0:
				broken.append("%s->%s" % [arc_id, room_id])
	check(broken.is_empty(),
		"the ring's corners walk to both chambers they join (%s)" % str(broken))
	var keeper = null
	for mob in cave.den_mobs("ring_s"):
		if mob.has_method("demon"):
			keeper = mob
	# A keeper is the floor's own weight, not the wardens' - and the difficulty
	# scales every body on the floor by the same factor, so the comparison is taken
	# between two bodies standing on this floor whatever mode it was built with.
	var warden = null
	for mob in cave.den_mobs("den"):
		if not mob.has_method("demon") and not mob.has_method("begin_ambush"):
			warden = mob
			break
	check(keeper != null and warden != null
			and float(keeper.get("max_health")) >= float(warden.get("max_health")) * 2.0,
		"a chamber's keeper is a demon of the floor's own weight (%s against a warden's %s)" % [
			str(keeper.get("max_health")) if keeper != null else 0,
			str(warden.get("max_health")) if warden != null else 0])


## The difficulty a party goes down on, on the floor it actually built. EASY is the
## default, so this is the floor the first descent made: a third of every den's
## crowd a post, half the pool, and the speeds the bodies were authored with. The
## three dials are proved on real rigs - one of the floor's wardens and one of its
## archers - by scaling them the way a hard floor would and reading the numbers
## back, then putting the body back where the floor left it.
func check_difficulty() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to read its difficulty")
	if cave == null:
		return
	check(cave.mode == "easy", "the first floor is built on the easy Hollow (%s)" % cave.mode)
	var expected := 1
	for spec in Layout.DENS:
		expected += Layout.den_bodies(spec, "easy")
	check(cave.mobs().size() == expected,
		"the easy floor stands %d bodies (%d)" % [expected, cave.mobs().size()])
	var hard_total := 1
	for spec in Layout.DENS:
		hard_total += Layout.den_bodies(spec, "hard")
	check(hard_total > expected * 2,
		"and the hard Hollow stands %d over the easy one's %d" % [hard_total, expected])
	check(Layout.den_crowd(Layout.DENS[0], "easy") < Layout.den_crowd(Layout.DENS[0], "medium")
			and Layout.den_crowd(Layout.DENS[0], "medium") < Layout.den_crowd(Layout.DENS[0], "hard"),
		"the crowd a post stands climbs easy, medium, hard (%d / %d / %d)" % [
			Layout.den_crowd(Layout.DENS[0], "easy"),
			Layout.den_crowd(Layout.DENS[0], "medium"),
			Layout.den_crowd(Layout.DENS[0], "hard")])
	var watcher = null
	var archer = null
	for mob in cave.den_mobs("workings"):
		if mob.has_method("begin_ambush"):
			archer = mob
		elif watcher == null:
			watcher = mob
	check(watcher != null and archer != null, "a hall's warden and its archer stand on the floor")
	if watcher == null or archer == null:
		return
	# The body the hard floor is compared against: the same authored post, standing
	# on both floors (the authored posts are never thinned).
	_probe_name = str(watcher.name)
	_probe_pool = float(watcher.get("max_health"))
	_probe_walk = float(watcher.profile.walk_speed)
	_probe_beat = float(watcher._cooldown_seconds())
	check(is_equal_approx(_probe_pool, float(watcher.get("health"))),
		"a body scaled at spawn starts on its whole pool (%.1f)" % _probe_pool)
	# Idempotent: the same difficulty applied again is the same body.
	watcher.apply_difficulty(0.5, 1.0)
	check(is_equal_approx(float(watcher.get("max_health")), _probe_pool),
		"a difficulty applied twice is one floor, not two (%.1f)" % float(watcher.get("max_health")))
	var archer_beat := float(archer._cooldown_seconds())
	var archer_pool := float(archer.get("max_health"))
	for mob in [watcher, archer]:
		mob.apply_difficulty(2.0, 2.0)
	check(is_equal_approx(float(watcher.get("max_health")), _probe_pool * 4.0)
			and is_equal_approx(float(archer.get("max_health")), archer_pool * 4.0),
		"twice the pool where the easy floor gave half of it (%s / %s)" % [
			str(watcher.get("max_health")), str(archer.get("max_health"))])
	check(is_equal_approx(float(watcher.profile.walk_speed), _probe_walk * 2.0)
			and is_equal_approx(float(watcher.profile.run_speed),
				float(watcher._authored["run_speed"]) * 2.0),
		"twice the walk and the run (%.2f m/s)" % float(watcher.profile.walk_speed))
	check(is_equal_approx(float(watcher._cooldown_seconds()), _probe_beat / 2.0),
		"and a swing every half the beat (%.2f s of %.2f)" % [
			float(watcher._cooldown_seconds()), _probe_beat])
	check(is_equal_approx(float(archer._cooldown_seconds()), archer_beat / 2.0),
		"the archer looses on the floor's own clock too (%.2f s of %.2f)" % [
			float(archer._cooldown_seconds()), archer_beat])
	# Back to the floor under test: every later check fights the easy Hollow.
	watcher.apply_difficulty(0.5, 1.0)
	archer.apply_difficulty(0.5, 1.0)
	check(is_equal_approx(float(watcher.get("max_health")), _probe_pool)
			and is_equal_approx(float(archer.get("max_health")), archer_pool),
		"and a body put back on easy is the body it was")
	check(game.loot_feed.header_text().contains(DelveMode.label_of("easy")),
		"the floor's own line names the difficulty (%s)" % game.loot_feed.header_text())


## The middle of a room's floor, in the cave's frame (y is a metre up).
func _room_centre(room_id: String) -> Vector3:
	var rect: Rect2 = Layout.room(room_id)["rect"]
	return Vector3(rect.get_center().x, 0.5, rect.get_center().y)


## The floor's own geometry, at the size it is built: the plan is `SCALE` times the
## authored one, every room is inside the rock box, and every piece the plan places
## - a shaft's rope and the ring in front of it, a den's post, a light, a prop, the
## master's ring - is on the floor of the room it names. A piece left behind by a
## half-applied scale stands in the rock, so this is asked of the built floor.
## And no room is wider corner to corner than the eye's reach: however big the
## floor is built, a body in the room the eye stands in is drawn.
func check_plan_geometry() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to measure")
	if cave == null:
		return
	var box: Rect2 = Layout.BOUNDS
	check(box.size.is_equal_approx(Layout.AUTHORED_BOUNDS.size * Layout.SCALE),
		"the rock box is built at %s times the authored plan (%s)" % [Layout.SCALE, box.size])
	var stray: Array[String] = []
	var widest := 0.0
	var widest_room := ""
	for index in Layout.ROOMS.size():
		var room: Dictionary = Layout.ROOMS[index]
		var rect: Rect2 = room["rect"]
		if not box.encloses(rect):
			stray.append("%s in the rock" % str(room["id"]))
		if rect.size.length() > widest:
			widest = rect.size.length()
			widest_room = str(room["id"])
	check(widest <= cave.BODY_HIDE_DISTANCE,
		"no room is wider than the eye's reach (%s %.1f m, reach %.1f m)"
		% [widest_room, widest, cave.BODY_HIDE_DISTANCE])
	for entry in Layout.LANDINGS:
		for field in ["rope", "centre"]:
			var at: Vector3 = entry[field]
			if not _on_its_floor(str(entry["room"]), Vector2(at.x, at.z)):
				stray.append("%s %s" % [str(entry["id"]), field])
	for spec in Layout.DENS:
		for member in Layout.den_members(spec):
			var at: Vector3 = member["at"]
			if not _on_its_floor(str(spec["room"]), Vector2(at.x, at.z)):
				stray.append("%s post" % str(spec["id"]))
	for spec in Layout.LIGHTS + Layout.PROPS:
		var at: Vector3 = Layout.wall_point(str(spec["room"]), str(spec["wall"]), float(spec["along"]))["at"] \
			if spec.has("wall") else spec["at"]
		if not _on_its_floor(str(spec["room"]), Vector2(at.x, at.z)):
			stray.append("%s %s" % [str(spec["room"]), str(spec["kind"])])
	if not _on_its_floor(Layout.MASTER_ROOM, Vector2(Layout.MASTER_POINT.x, Layout.MASTER_POINT.z)):
		stray.append("the master's ring")
	check(stray.is_empty(), "every piece of the plan stands on its own room's floor (%s)" % str(stray))


## The floor is a surface and not a shelf. It falls away from the mouth all the
## way into the dark - the lair stands metres lower than the chamber a party lands
## in, which is what makes a descent read as one - and over that fall it pitches:
## every hall's ground rises and dips a metre or more between its high point and
## its low. What stops a body is the mesh it is looking at (`_floor_collider` is
## the drawn floor's own vertices), so a ray down from over a hall stops on the
## field's own height; and the stone grown out of the floor stands in the open
## middle of the halls, not only along their walls.
func check_floor_relief() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to feel its relief")
	if cave == null:
		return
	var mouth_rope: Vector3 = Layout.landing("mouth")["rope"]
	var mouth := Floor.height(mouth_rope.x, mouth_rope.z)
	check(absf(mouth) < 1.0,
		"the mouth's own floor is the level the rest is read from (%.2f m)" % mouth)
	var master := Floor.height(Layout.MASTER_POINT.x, Layout.MASTER_POINT.z)
	check(master <= mouth - 5.0,
		"the ground falls away from the mouth into the dark (lair %.1f m, %.1f m of fall)"
		% [master, mouth - master])
	var flat: Array[String] = []
	var steep: Array[String] = []
	var level: Array[String] = []
	for index in Layout.ROOMS.size():
		var room: Dictionary = Layout.ROOMS[index]
		if bool(room.get("tunnel", false)):
			continue
		var rect: Rect2 = room["rect"]
		if rect.get_area() < 150.0:
			continue
		var low := INF
		var high_at := -INF
		for i in 12:
			for j in 12:
				var x := rect.position.x + rect.size.x * (float(i) + 0.5) / 12.0
				var z := rect.position.y + rect.size.y * (float(j) + 0.5) / 12.0
				var ground := Floor.height(x, z)
				low = minf(low, ground)
				high_at = maxf(high_at, ground)
		if high_at - low < 0.5:
			flat.append("%s %.2f" % [str(room["id"]), high_at - low])
		# Nowhere does the ground rise more in a metre than a body can walk up.
		for step in 24:
			var x := rect.position.x + rect.size.x * (float(step) + 0.5) / 24.0
			var z := rect.position.y + rect.size.y * (float(step % 7) + 0.5) / 7.0
			var rise := absf(Floor.height(x + 1.0, z) - Floor.height(x, z))
			if rise > 0.8:
				steep.append("%s %.2f" % [str(room["id"]), rise])
		# A hall deep in the dark is lower than the mouth's own chamber.
		var centre := rect.get_center()
		if Vector2(centre.x, centre.y).distance_to(Vector2(mouth_rope.x, mouth_rope.z)) > 150.0 \
				and Floor.height(centre.x, centre.y) > -1.0:
			level.append(str(room["id"]))
	check(flat.is_empty(), "every hall's floor pitches underfoot (%s)" % str(flat))
	check(steep.is_empty(), "and never rises more in a metre than a body can climb (%s)" % str(steep))
	check(level.is_empty(), "a hall far from the mouth is lower than it (%s)" % str(level))
	# What stops a body is the drawn floor: every room's ground is one collider of
	# the floor's own vertices, and a body standing on open ground - a landing's
	# post, which the map already holds open - is standing on the field's height and
	# not on a level the cave never had.
	var missing: Array[String] = []
	for index in Layout.ROOMS.size():
		var drawn := Floor.faces(index)
		var found := false
		for child in cave._rock_solids.get_children():
			if not (child is CollisionShape3D):
				continue
			var shape = (child as CollisionShape3D).shape
			if not (shape is ConcavePolygonShape3D):
				continue
			var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
			if faces.size() == drawn.size() and faces == drawn:
				found = true
				break
		if not found:
			missing.append(str(Layout.ROOMS[index]["id"]))
	check(missing.is_empty(), "every room's ground is the floor it draws (%s)" % str(missing))
	var space: PhysicsDirectSpaceState3D = cave.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	var off: Array[String] = []
	for entry in Layout.LANDINGS:
		for post in cave.entry_posts(str(entry["id"]), cave.ENTRY_POSTS):
			var local: Vector3 = cave.to_local(post)
			var ground := Floor.height(local.x, local.z)
			query.from = cave.to_global(Vector3(local.x, ground + 2.0, local.z))
			query.to = cave.to_global(Vector3(local.x, ground - 1.0, local.z))
			var hit := space.intersect_ray(query)
			if hit.is_empty() or absf(float(hit["position"].y) - cave.to_global(
					Vector3(local.x, ground, local.z)).y) > 0.05:
				off.append("%s %.2f" % [str(entry["id"]), ground])
	check(off.is_empty(), "a body landed on open ground stands on the field's own height (%s)" % str(off))
	# Dripstone out of the open floor: a stand of stone away from every wall.
	var open_stands := 0
	var halls := 0
	for index in Layout.ROOMS.size():
		var room: Dictionary = Layout.ROOMS[index]
		if bool(room.get("tunnel", false)) or (room["rect"] as Rect2).get_area() < 150.0:
			continue
		halls += 1
		var rect: Rect2 = room["rect"]
		for child in cave._rooms[index].get_node_or_null("RockSolids").get_children():
			if not (child is CollisionShape3D) or not ((child as CollisionShape3D).shape is CylinderShape3D):
				continue
			var at: Vector3 = (child as Node3D).position
			var edge := minf(minf(at.x - rect.position.x, rect.end.x - at.x),
				minf(at.z - rect.position.y, rect.end.y - at.z))
			if edge > 3.5:
				open_stands += 1
				break
	check(open_stands * 2 > halls,
		"stone grows out of the open floor of most halls (%d of %d)" % [open_stands, halls])


## Whether a cave-frame point is on the floor of the room it names.
func _on_its_floor(room_id: String, at: Vector2) -> bool:
	var index := Layout.room_index(room_id)
	return index >= 0 and Layout.room_index_at(at) == index


## The eye's reach on the floor. The descent fields a den per room, and the frame
## pays for every one of them: a body past `BODY_HIDE_DISTANCE` is not a picture
## anyone can see (its room's lights are out and three rooms of bent tunnel stand
## between), so it stops drawing and stops posing. Hiding is not silencing - the
## body keeps its brain, its collision and its clock, and the party walks into it
## standing where it was.
func check_eye_culling() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to cull")
	if cave == null:
		return
	var mobs: Array = cave.mobs()
	check(mobs.size() > 20, "the floor fields bodies to cull (%d)" % mobs.size())
	if mobs.is_empty():
		return
	var target = mobs[0]
	var at: Vector3 = target.global_position
	var inside := 0
	for mob in mobs:
		if (mob as Node3D).global_position.distance_to(at) <= cave.BODY_HIDE_DISTANCE:
			inside += 1
	# Reveals are staged (a body is drawn for the first time on the frame it is
	# shown, and a room shown at once is a stall), so one poll hides everything
	# out of reach and puts back only its share; a few polls put the rest back.
	cave.cull_bodies(at)
	var culled := 0
	for mob in mobs:
		if bool(mob.get("culled")):
			culled += 1
	check(culled <= mobs.size() - inside + cave.REVEAL_CHUNK,
		"no more than one chunk of the eye's bodies is still hidden (%d of %d, %d inside)"
		% [culled, mobs.size(), inside])
	for _poll in 8:
		cave.cull_bodies(at)
	culled = 0
	for mob in mobs:
		if bool(mob.get("culled")):
			culled += 1
	check(culled == mobs.size() - inside,
		"every body outside the eye's reach is culled once the reveals are done (%d of %d, %d inside)"
		% [culled, mobs.size(), inside])
	check(inside < mobs.size() / 2,
		"the eye's reach is a fraction of the floor (%d of %d)" % [inside, mobs.size()])
	target.mob_wake()
	check(target.visible, "the body the eye stands on is drawn")
	cave.cull_bodies(at + Vector3(0.0, 0.0, cave.BODY_HIDE_DISTANCE * 2.0))
	check(not target.visible, "the body is hidden when the eye leaves it")
	check(not target.dormant,
		"hidden is not dormant: the body keeps its brain, its collision and its clock")
	check(target.is_physics_processing(), "and it is still being simulated")
	cave.cull_bodies(at)
	check(target.visible, "and it comes back when the eye returns")


## `M` below opens the Hollow's own plan, not the wood's sheet, and the plan is the
## floor: every room on it, every rope a mark inside it with the shortest walk up
## ringed, and the soul drawn in the room it stands in. A second `M` closes it.
func check_floor_map() -> void:
	var area = game.delve_area
	var map = area.map
	check(map != null, "the delve has a plan of its floor")
	if map == null:
		return
	_press_key(KEY_M)
	await process_frame
	await process_frame
	check(map.is_open() and not game.world_map.is_open(), "M below opens the floor's plan, not the wood's sheet")
	var drawn: Array = map.rooms()
	check(drawn.size() == Layout.ROOMS.size(), "the plan draws every room (%d)" % drawn.size())
	var ropes := 0
	var ringed := 0
	var soul_mark := {}
	for marker in map.markers():
		match str(marker["kind"]):
			"shaft":
				if not bool(marker["pinned"]):
					ropes += 1
				if bool(marker.get("nearest", false)):
					ringed += 1
			"soul":
				soul_mark = marker
	check(ropes == Layout.LANDINGS.size(), "every rope is on the plan (%d)" % ropes)
	check(ringed == 1, "one rope is ringed as the shortest walk up (%d)" % ringed)
	var soul = _soul()
	check(soul != null and area.cave != null, "a soul on a floor to be drawn on the plan")
	if soul != null and area.cave != null:
		var local: Vector3 = area.cave.to_local(soul.global_position)
		var index := Layout.room_index_at(Vector2(local.x, local.z))
		check(not soul_mark.is_empty() and index >= 0
			and (drawn[index]["rect"] as Rect2).grow(1.0).has_point(soul_mark["screen"]),
			"the soul is drawn in the room it stands in (%s)" % str(soul_mark.get("screen", "")))
	_press_key(KEY_M)
	await process_frame
	await process_frame
	check(not map.is_open(), "a second M closes the plan")


## One real key event through the input pipeline, so the binding is proved.
func _press_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)


## Walk the party over to another shaft's landing, as if it had come down there.
func _gather_at(landing_id: String) -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to gather the party on")
	if cave == null:
		return
	var posts: Array[Vector3] = cave.entry_posts(landing_id, _party.size())
	for index in _party.size():
		var body = game.controller.body_of(_party[index])
		if body != null:
			body.teleport_to(posts[index], cave.entry_yaw(landing_id))
	await _frames(3)


# --- a den, a kill, the loot -----------------------------------------------

func check_den_and_loot() -> void:
	var cave = game.delve_area.cave
	check(cave != null, "the floor is below to wake a den on")
	if cave == null:
		return
	var soul = _soul()
	check(soul != null, "the soul stands on the floor beside the den")
	# The hall the den posts in: the wake and the kit both read it, so it is read
	# once, out here, where every check below can see it.
	var room: Rect2 = Layout.room("den")["rect"]
	if soul != null:
		soul.teleport_to(cave.to_global(Vector3(0.0, 0.12, room.end.y - 3.0)), 0.0)
	await create_timer(0.45).timeout
	check(cave.is_awake("den"), "a body in the den's room wakes it")
	var den: Array = cave.den_mobs("den")
	check(not den.is_empty(), "the den fields bodies to wake")
	if den.is_empty():
		return
	var listed := 0
	for mob in den:
		if game.guards.has(mob):
			listed += 1
	check(listed == den.size(), "the whole den joins the hostile list (%d of %d)" % [listed, den.size()])
	var others_awake: Array[String] = []
	for spec in Layout.DENS:
		if str(spec["id"]) != "den" and cave.is_awake(str(spec["id"])):
			others_awake.append(str(spec["id"]))
	check(others_awake.is_empty() and not cave.is_awake("lair"), "every other den sleeps on (%s)" % str(others_awake))
	var stash_before: Dictionary = warband.stash.pooled_map()
	var inventory_before: int = warband.delve.inventory.pooled_total()
	var victim = den[0]
	# The table's rare finds, put on the first body by hand so every run has them:
	# a piece of Ritual Tallow to carry up to the wallet, and steel already
	# anointed in its hand.
	victim.carried.append("cruor_t1")
	var anointed_id := str(victim.weapon_item)
	victim.weapon_anointed = true
	var kit_before := 0
	for mob in den:
		kit_before += (mob.gear_items() as Array).size()
	for mob in den:
		mob.take_damage(9999.0, 1)
	await _frames(2)
	check(not bool(victim.get("alive")), "the den falls")
	# The Hollow pays 30% of a body's kit: thirty bodies' worth of pieces - on the
	# corpses and in the dirt of the hall - is far under half of what they carried.
	var kit_after := 0
	for left_id in game.loot.corpse_ids():
		var lies: Vector3 = cave.to_local(game.loot.corpse_position(left_id))
		if room.has_point(Vector2(lies.x, lies.z)):
			kit_after += game.loot.corpse_items(left_id).size()
	for pickup in game.loot.pickups():
		var lies: Vector3 = cave.to_local(pickup.global_position)
		if room.has_point(Vector2(lies.x, lies.z)):
			kit_after += 1
	check(kit_after > 0 and kit_after * 2 < kit_before,
		"the den leaves a thin share of its kit (%d of %d pieces)" % [kit_after, kit_before])
	var marked := false
	for pickup in game.loot.pickups():
		if bool(pickup.anointed) and str(pickup.item_id) == anointed_id:
			marked = true
	check(marked, "the anointed steel falls as an anointed drop (%s)" % anointed_id)
	check(not warband.cruor.is_anointed(anointed_id), "and nothing is awake before it is taken")
	var corpse_id: int = game.loot.corpse_at(victim.global_position, 1.0)
	check(corpse_id != 0, "a fallen watcher is a body to search")
	_soul_to(soul, victim.global_position + Vector3(1.2, 0.12, 0.0))
	await _frames(1)
	var target: Dictionary = {}
	if soul != null:
		target = game.loot_hand.target_at(soul, victim.global_position + Vector3(0.0, 0.4, 0.0))
	check(str(target.get("kind", "")) == "corpse", "a press on the body finds the corpse")
	# Below, the right click is the take itself: the whole body and the steel that
	# fell beside it, straight into the delve inventory and onto nobody.
	var soul_merc := int(game.controller.merc_for_peer(1))
	var worn_before: Array = warband.roster.worn_entries(soul_merc)
	var on_body: Array[String] = game.loot.corpse_items(corpse_id)
	var took: Array[String] = []
	if soul != null:
		took = game.loot_hand.take_now(soul, target)
	var whole := not on_body.is_empty()
	for item_id in on_body:
		if not took.has(item_id):
			whole = false
	check(whole and not game.loot.has_corpse(corpse_id),
		"a right click takes everything on the body (%s of %s)" % [str(took), str(on_body)])
	check(took.has(anointed_id), "and the steel that fell beside it")
	check(warband.roster.worn_entries(soul_merc) == worn_before, "none of it goes onto the body that took it")
	check(warband.delve.inventory.pooled_total() == inventory_before + took.size(),
		"every piece lands in the delve inventory (%d -> %d)" % [inventory_before,
			warband.delve.inventory.pooled_total()])
	check(warband.cruor.is_anointed(anointed_id),
		"taking the anointed steel wakes its skill for the warband (%s)" % anointed_id)
	check(warband.stash.pooled_map() == stash_before, "the town stash did not move while below")
	check(not game.loot_feed.lines().is_empty(), "the looted list names what came up (%s)" % str(game.loot_feed.lines()))
	check(game.loot_feed.header_text().contains("DELVE INVENTORY"), "and the delve's line heads it")
	# The loot window is the right click above; opened on a body below it lists that
	# body's container - what the dead body still wore and carried, and the steel
	# that fell out of its hand and lies beside it - and books the lot into the
	# delve inventory. A corpse holds the Hollow's own rolls (a watcher keeps 30% of
	# its kit, piece by piece), so the row count is read here and never assumed: the
	# invariant is that the window's whole list comes up, into the pack, and that the
	# window lets go of a body it has emptied.
	var second_id := 0
	var second_at := Vector3.ZERO
	for mob in den:
		var other_id: int = game.loot.corpse_at(mob.global_position, 0.6)
		if mob != victim and other_id != 0:
			second_id = other_id
			second_at = mob.global_position
			break
	_soul_to(soul, second_at + Vector3(1.2, 0.12, 0.0))
	await _frames(1)
	var window_rows: Array = []
	if soul != null and game.loot_window.open_on(soul,
			{"kind": "corpse", "corpse_id": second_id, "pickup": null}):
		window_rows = game.loot_window.rows()
	# The body's own contents are part of what the window lists, each piece on a row
	# of its own (copies of one piece share a row, with a count).
	var on_second: Array[String] = game.loot.corpse_items(second_id)
	var window_ids: Array[String] = []
	var window_pieces := 0
	for row in window_rows:
		window_ids.append(str(row.get("item_id", "")))
		window_pieces += int(row.get("count", 0))
	var holds_all := not on_second.is_empty()
	for item_id in on_second:
		if not window_ids.has(item_id):
			holds_all = false
	check(holds_all, "the window lists every piece still on the body (%s of %s)"
		% [str(window_ids), str(on_second)])
	var held_before: int = warband.delve.inventory.pooled_total()
	var stash_below: Dictionary = warband.stash.pooled_map()
	var worn_on_taker: Array = warband.roster.worn_entries(soul_merc)
	var took_all: Array[String] = game.loot_window.take_all()
	check(window_pieces > 0 and took_all.size() == window_pieces and not game.loot_window.is_open(),
		"the loot window lists a body below and takes the lot (%d rows, %d of %d pieces)"
		% [window_rows.size(), took_all.size(), window_pieces])
	check(warband.delve.inventory.pooled_total() == held_before + window_pieces,
		"and every piece lands in the delve inventory (%d -> %d)"
		% [held_before, warband.delve.inventory.pooled_total()])
	check(warband.roster.worn_entries(soul_merc) == worn_on_taker,
		"nothing of it is dressed onto the body that searched it")
	check(warband.stash.pooled_map() == stash_below, "and the town stash is untouched by it")
	# The rest of the den is the squad's: it walks the cave's map down to the soul
	# and strips the bodies and the steel on the floor into the same inventory. A
	# den is a crowd now, so the check is that the squad works it - a few bodies
	# emptied on its own - not that it has cleared the whole hall.
	var others: Array[int] = []
	for mob in den:
		if mob != victim:
			var other_id: int = game.loot.corpse_at(mob.global_position, 1.0)
			if other_id != 0 and other_id != second_id:
				others.append(other_id)
	check(not others.is_empty(), "the squad has bodies left to strip")
	var wanted := mini(others.size(), 3)
	# The squad walks there from the shaft it came down, so the allowance is the
	# authored 20 s at the plan's own scale: the floor is `SCALE` times as long and
	# the squad covers the same ground at the same speed. The loop leaves as soon as
	# the bodies are stripped, so the allowance costs nothing when the walk is quick.
	var budget := 20.0 * Layout.SCALE
	var waited := 0.0
	var emptied := 0
	while waited < budget and emptied < wanted:
		await create_timer(0.5).timeout
		waited += 0.5
		emptied = 0
		for other_id in others:
			if not game.loot.has_corpse(other_id):
				emptied += 1
	check(emptied >= wanted, "the squad strips the den's bodies on its own (%d of %d in %.1f s)"
		% [emptied, others.size(), waited])
	var by_squad := false
	for line in game.loot_feed.lines():
		if str(line).ends_with("squad"):
			by_squad = true
	check(by_squad, "and the looted list says the squad took it (%s)" % str(game.loot_feed.lines()))
	check(warband.stash.pooled_map() == stash_before, "none of it reached the town stash")
	# The master: woken, killed, and taken whole with one right click. A floor
	# that never stood him up records the failure and the paperdoll below still
	# runs, which is a better report than a coroutine killed on a nil.
	var master = cave.master
	check(master != null, "Gorehorn holds the centre of the new floor")
	if master != null:
		master.take_damage(99999.0, 1)
		await _frames(2)
		check(not cave.master_alive(), "Gorehorn dies")
		var master_corpse: int = game.loot.corpse_at(master.global_position, 1.0)
		check(master_corpse != 0 and game.loot.corpse_items(master_corpse).has("ring_blood"),
			"the master's body carries the floor's prize")
		if soul != null:
			soul.teleport_to(master.global_position + Vector3(1.0, 0.12, 0.0), 0.0)
		await _frames(1)
		if soul != null:
			var spoils: Dictionary = game.loot_hand.target_at(soul,
				master.global_position + Vector3(0.0, 0.4, 0.0))
			check(game.loot_hand.take_now(soul, spoils).has("ring_blood"),
				"a right click takes the master's body whole")
			check(warband.delve.inventory.pooled_count("ring_blood") == 1,
				"the prize is in the delve inventory")
			check(warband.stash.pooled_count("ring_blood") == 0, "and not yet in the stash")
	game.paperdoll.open(int(game.controller.merc_for_peer(1)))
	var shows_inventory := false
	for row in game.paperdoll.stash_rows:
		if str(row.get("item_id", "")) == "arrow" \
				and int(row.get("pooled", 0)) == warband.delve.inventory.pooled_count("arrow"):
			shows_inventory = true
	check(shows_inventory, "below, the paperdoll dresses from the delve inventory")
	check(not game.paperdoll.picker_buttons.has(_stayer), "and offers only the party")
	game.paperdoll.close()


# --- a member falls below ----------------------------------------------------

## A member who dies below keeps what he wore: none of it is booked for him, the
## squad's sweep leaves his body alone, and a right click on it takes it all back
## into the delve inventory.
func check_fallen_member() -> void:
	var cave = game.delve_area.cave
	var soul_merc := int(game.controller.merc_for_peer(1))
	var fallen_id := -1
	for merc_id in warband.delve.party:
		if merc_id != soul_merc and not warband.roster.worn_entries(merc_id).is_empty():
			fallen_id = merc_id
			break
	check(fallen_id > 0, "a dressed member of the party is below to fall")
	if fallen_id <= 0:
		return
	var body = game.controller.body_of(fallen_id)
	check(body != null and cave != null, "%s is below, on a floor, with a body to fall"
		% warband.roster.name_of(fallen_id))
	if body == null or cave == null:
		return
	var kit: Array[String] = []
	for entry in warband.roster.worn_entries(fallen_id):
		kit.append(str(entry.get("item", "")))
	kit.sort()
	# He falls alone at the mouth's shaft, far from the rest of the party, so nothing
	# but the rule below decides where his kit goes.
	var lone: Vector3 = cave.entry_posts("mouth", 1)[0]
	body.teleport_to(lone, 0.0)
	await _frames(2)
	var inventory_before: Dictionary = warband.delve.inventory.pooled_map()
	var stash_before: Dictionary = warband.stash.pooled_map()
	body.take_damage(9999.0, 90)
	body.take_damage(9999.0, 90)
	await create_timer(0.6).timeout
	check(not bool(body.get("alive")) and not warband.roster.has(fallen_id),
		"the member dies and leaves the books")
	var remains: int = game.loot.corpse_at(body.global_position, 1.0)
	var lying: Array[String] = game.loot.corpse_items(remains)
	for pickup in game.loot.pickups():
		if pickup.global_position.distance_to(body.global_position) <= 2.0:
			lying.append(str(pickup.item_id))
	lying.sort()
	check(remains != 0 and lying == kit, "everything he wore lies on his body or at its feet (%s of %s)"
		% [str(lying), str(kit)])
	check(warband.delve.inventory.pooled_map() == inventory_before and warband.stash.pooled_map() == stash_before,
		"and none of it is booked for him")
	check(not game.loot.corpse_ids(false).has(remains), "the squad's sweep leaves a fallen comrade alone")
	var soul = _soul()
	check(soul != null, "the soul is below to take a comrade's kit back")
	if soul != null:
		soul.teleport_to(body.global_position + Vector3(1.0, 0.12, 0.0), 0.0)
	await _frames(1)
	var target: Dictionary = {}
	if soul != null:
		target = game.loot_hand.target_at(soul, body.global_position + Vector3(0.0, 0.4, 0.0))
		check(int(target.get("corpse_id", 0)) == remains, "a press on his body finds him")
	var took: Array[String] = []
	if soul != null:
		took = game.loot_hand.take_now(soul, target)
	took.sort()
	check(took == kit and not game.loot.has_corpse(remains),
		"a right click takes all of it back (%s)" % str(took))
	var home := true
	for item_id in kit:
		if warband.delve.inventory.pooled_count(item_id) < int(inventory_before.get(item_id, 0)) + kit.count(item_id):
			home = false
	check(home, "into the delve inventory")


# --- climbing out ----------------------------------------------------------

## The climb is at a rope the party did not come down: every shaft is a way up.
func check_climb_out() -> void:
	var cave = game.delve_area.cave
	var soul = _soul()
	check(cave != null and soul != null, "a soul on the floor stands at a rope to climb out")
	if cave == null or soul == null:
		return
	var rope_id := "mere" if game.delve_area.landing != "mere" else "chapel"
	# The rope a body walks up to is reached across the ground: the plan's rope
	# points are authored at y = 0 and the floor under a deep shaft is metres
	# below that, so a body standing at the foot of the rope used to be out of its
	# own reach (`G` did nothing at the far ropes).
	var deep: Vector3 = cave.rope_point(rope_id) + Vector3(0.0, -8.0, 1.0)
	soul.teleport_to(deep, 0.0)
	await _frames(2)
	check(cave.exit_at(soul) == rope_id,
		"a body 8 m below the plan's rope point is still at the %s rope" % rope_id)
	var plan: Vector3 = cave.to_local(cave.rope_point(rope_id))
	var foot: Vector3 = cave.rope_point(rope_id)
	foot.y = cave.to_global(Vector3(plan.x, Floor.height(plan.x, plan.z), plan.z)).y
	soul.teleport_to(foot + Vector3(0.0, 0.12, 1.0), 0.0)
	await _frames(2)
	check(cave.exit_at(soul) == rope_id, "a body at the %s rope is at a way up" % rope_id)
	check(game.delve_area.prompt_line(soul).begins_with("G  -  CLIMB OUT"),
		"the crosshair names the climb (%s)" % game.delve_area.prompt_line(soul))
	var carried: Dictionary = warband.delve.inventory.pooled_map()
	var essence := int(carried.get("cruor_t1", 0))
	var tallow_tier := CruorCatalog.tier_from_id("cruor_t1")
	var tallow_before: int = warband.cruor.tier_count(tallow_tier)
	check(essence > 0, "the party carries Ritual Tallow off the Hollow's dead (%d)" % essence)
	var stash_before: Dictionary = warband.stash.pooled_map()
	var below_mobs: Array = cave.mobs()
	# A guest's `G` on a rope arrives as this intent, so the host has to judge the
	# reach itself: a body nowhere near a rope is refused, and the same call at the
	# rope is what brings the whole party up - the way out that a host whose own
	# body is dead in the dark cannot press.
	soul.teleport_to(foot + Vector3(0.0, 0.12, 40.0), 0.0)
	await _frames(2)
	check(not game._on_world_action(soul, "climb_out", null),
		"a climb-out intent from away from the rope is refused")
	soul.teleport_to(foot + Vector3(0.0, 0.12, 1.0), 0.0)
	await _frames(2)
	check(game._on_world_action(soul, "climb_out", null),
		"a climb-out intent at the rope is the guest's way out")
	await create_timer(0.2).timeout
	check(not game.delve_area.below() and not warband.delve.active, "the rope ends the descent")
	check(warband.delve.inventory.pooled_total() == 0, "the delve inventory is emptied")
	var home := true
	for item_id in carried:
		if str(item_id) == "cruor_t1":
			continue
		if warband.stash.pooled_count(str(item_id)) != int(stash_before.get(item_id, 0)) + int(carried[item_id]):
			home = false
	check(home, "every piece carried up is in the town stash")
	check(warband.cruor.tier_count(tallow_tier) == tallow_before + essence
		and warband.stash.pooled_count("cruor_t1") == 0,
		"the tallow carried up renders into the altar's wallet, not the stash (%d -> %d)"
		% [tallow_before, warband.cruor.tier_count(tallow_tier)])
	check(_owned("ring_blood"), "the prize came home with it")
	for merc_id in _party:
		var body = game.controller.body_of(merc_id)
		if body != null and bool(body.get("alive")):
			check(game.town.in_square(body), "%s is back in the square" % warband.roster.name_of(merc_id))
	var allowed: Dictionary = game.controller.direct(1, _stayer)
	check(bool(allowed.get("ok", false)), "the body left home is in reach again")
	await create_timer(0.2).timeout
	check(game.camera.environment == null, "the eye has the wood's sky back")
	var lingering := 0
	for mob in below_mobs:
		if game.guards.has(mob):
			lingering += 1
	check(lingering == 0, "nothing of the Hollow stays on the hostile list (%d)" % lingering)


# --- falling ---------------------------------------------------------------

func check_fall() -> void:
	var area = game.delve_area
	var party: Array[int] = []
	for merc_id in warband.roster.ids():
		var body = game.controller.body_of(merc_id)
		if body != null and bool(body.get("alive")) and not bool(body.get("downed")) and party.size() < 2:
			party.append(merc_id)
	var packed_before: int = warband.stash.pooled_count("arrow")
	warband.pack_for_delve("arrow", 5)
	var worn: int = 0
	for merc_id in party:
		worn += warband.roster.worn_entries(merc_id).size()
	check(worn > 0, "the second party wears something to lose (%d)" % worn)
	# The next descent is on the hard floor: the same cave, built with twice the
	# pool and twice the speed, and every den's crowd at its authored size.
	check(bool(warband.set_delve_mode("hard").get("ok", false)),
		"the mouth can put the next descent on the hard Hollow")
	var result: Dictionary = await area.descend(party)
	check(bool(result.get("ok", false)), "a second party goes down (%s)" % str(result.get("message", "")))
	var hard = area.cave
	check(hard != null, "the second floor is built below the party")
	if hard == null:
		return
	check(not hard.is_awake("den"), "into a fresh instance: the den sleeps again")
	check(hard.mode == "hard", "the second floor is built on the hard Hollow (%s)" % hard.mode)
	var hard_expected := 1
	for spec in Layout.DENS:
		hard_expected += Layout.den_bodies(spec, "hard")
	check(hard.mobs().size() == hard_expected,
		"the hard floor stands %d bodies (%d)" % [hard_expected, hard.mobs().size()])
	var probe = null
	for mob in hard.den_mobs("workings"):
		if str(mob.name) == _probe_name:
			probe = mob
	check(probe != null, "the same post stands on both floors (%s)" % _probe_name)
	if probe != null:
		check(is_equal_approx(float(probe.get("max_health")), _probe_pool * 4.0)
				and is_equal_approx(float(probe.get("health")), float(probe.get("max_health"))),
			"the hard floor gives the body four times the easy pool (%.1f of %.1f)"
			% [float(probe.get("max_health")), _probe_pool])
		check(is_equal_approx(float(probe.profile.walk_speed), _probe_walk * 2.0),
			"and twice the walk it had on easy (%.2f of %.2f)"
			% [float(probe.profile.walk_speed), _probe_walk])
		check(is_equal_approx(float(probe._cooldown_seconds()), _probe_beat / 2.0),
			"and swings on half the beat (%.2f s of %.2f)"
			% [float(probe._cooldown_seconds()), _probe_beat])
	check(not bool(warband.set_delve_mode("easy").get("ok", false)),
		"a floor somebody is below cannot be re-cut under the party")
	for merc_id in party:
		var doomed = game.controller.body_of(merc_id)
		check(doomed != null, "%s is below to fall" % warband.roster.name_of(merc_id))
		if doomed != null:
			doomed.take_damage(9999.0, 90)
	await create_timer(AreaScript.WIPE_BEAT + 0.6).timeout
	check(not area.below() and not warband.delve.active, "a party with nobody standing falls")
	var stripped := true
	for merc_id in party:
		if warband.roster.has(merc_id) and not warband.roster.worn_entries(merc_id).is_empty():
			stripped = false
	check(stripped, "everything the party wore is the Hollow's")
	check(warband.stash.pooled_count("arrow") == packed_before - 5, "and so is what it packed")
	for merc_id in party:
		var body = game.controller.body_of(merc_id)
		check(body != null and bool(body.get("alive")) and not bool(body.get("downed")) \
			and game.town.in_square(body), "%s wakes in the square" % warband.roster.name_of(merc_id))


# --- leaving the game below ------------------------------------------------

func check_load_forfeit() -> void:
	var merc_id := -1
	for candidate in warband.roster.ids():
		if warband.roster.is_alive(candidate) and not warband.roster.worn_entries(candidate).is_empty():
			merc_id = candidate
			break
	# A warband of three has already sent two parties down and lost their kits, so
	# nothing may be left on a body: the order still needs one dressed man to lose
	# his gear below, and the shared stash is where the harness dresses him.
	if merc_id <= 0:
		for candidate in warband.roster.ids():
			if not warband.roster.is_alive(candidate):
				continue
			if warband.stash.pooled_count("sword_short") <= 0:
				warband.stash.add("sword_short", 1)
			warband.equip_merc(candidate, "main", "sword_short")
			merc_id = candidate
			break
	check(merc_id > 0, "a dressed body is left to test the load with")
	if merc_id <= 0:
		return
	warband.pack_for_delve("sword_arming", 1)
	check(bool(warband.begin_delve([merc_id]).get("ok", false)), "the books take a party down")
	warband.load_state()
	check(not warband.delve.active, "a save that still holds a party below loads with nobody below")
	check(warband.delve.mode == "hard",
		"and the Hollow's difficulty comes back with the books (%s)" % warband.delve.mode)
	check(warband.roster.worn_entries(merc_id).is_empty(), "and that party's gear is lost")
	check(warband.delve.inventory.pooled_total() == 0, "with what it packed")
