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
##     crowded to `DEN_CROWD` bodies a post inside its own room;
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
const PrepScript = preload("res://scripts/warband/delve_prep_menu.gd")
const Layout = preload("res://scripts/warband/delve_layout.gd")

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


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame


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

func check_mouth_and_pack() -> void:
	var area = game.delve_area
	var soul = _soul()
	check(soul != null, "a body stands in the square")
	check(area.mouth != null and area.mouth.get_node_or_null("MouthName") != null,
		"the Hollow's mouth stands in the square, named")
	soul.teleport_to(area.mouth_point() + Vector3(0.0, 0.12, 2.2), 0.0)
	await _frames(2)
	check(area.at_mouth(soul), "a body by the pit is at the mouth")
	check(area.prompt_line(soul) == AreaScript.MOUTH_PROMPT,
		"the crosshair names the way down (%s)" % area.prompt_line(soul))
	game._try_interact()
	check(area.prep.is_open(), "G at the mouth opens the delve panel")
	var offered: Array[int] = area.prep.candidates()
	check(offered.size() == 5, "every standing body is offered (%d)" % offered.size())
	check(area.prep.selected().size() == offered.size(), "and every one starts chosen")
	var arrows: int = warband.stash.pooled_count("arrow")
	check(arrows > 0, "the town's quiver has shafts to pack (%d)" % arrows)
	check(area.prep.amount() == 1, "a click moves one copy until the dial says otherwise")
	area.prep.pack("arrow", true)
	check(warband.delve.inventory.pooled_count("arrow") == arrows,
		"a shift-click packs every shaft (%d)" % warband.delve.inventory.pooled_count("arrow"))
	check(warband.stash.pooled_count("arrow") == 0, "and the stash has none left")
	# The dial: one click moves as many copies as the party says, which is what a
	# quiver needs and what "click once per arrow" was paying for.
	area.prep.set_amount(6)
	check(area.prep.amount() == 6, "the dial holds the copies a click moves")
	area.prep.unpack("arrow")
	check(warband.delve.inventory.pooled_count("arrow") == arrows - 6
			and warband.stash.pooled_count("arrow") == 6,
		"one click moves the dial's six shafts back to the stash (%d / %d)" % [
			warband.delve.inventory.pooled_count("arrow"), warband.stash.pooled_count("arrow")])
	area.prep.pack("arrow")
	check(warband.delve.inventory.pooled_count("arrow") == arrows
			and warband.stash.pooled_count("arrow") == 0,
		"and one click packs them down again (%d)" % warband.delve.inventory.pooled_count("arrow"))
	# Outside the dial's range, and back to a click of one for the blade below.
	area.prep.set_amount(0)
	check(area.prep.amount() == 1, "the dial cannot go below one copy")
	area.prep.set_amount(9999)
	check(area.prep.amount() == PrepScript.MAX_AMOUNT, "nor above the panel's ceiling")
	area.prep.set_amount(1)
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
	await _frames(3)
	check(not area.prep.is_open(), "GO DOWN closes the panel")
	check(area.below() and warband.delve.active, "the party is below")
	check(warband.delve.party == _party, "the books hold the chosen party (%s)" % str(warband.delve.party))
	var cave = area.cave
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
## `DEN_CROWD` bodies for each post it was written with, each inside its own room.
func check_floor_plan() -> void:
	var cave = game.delve_area.cave
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
		if fielded.size() != (spec["members"] as Array).size() * Layout.DEN_CROWD or inside != fielded.size():
			thin.append("%s %d/%d" % [spec["id"], inside, fielded.size()])
	check(thin.is_empty(), "every den fields %d bodies a post, all in its room (%s)" % [Layout.DEN_CROWD, str(thin)])
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


## The eye's reach on the floor. The descent fields a den per room, and the frame
## pays for every one of them: a body past `BODY_HIDE_DISTANCE` is not a picture
## anyone can see (its room's lights are out and three rooms of bent tunnel stand
## between), so it stops drawing and stops posing. Hiding is not silencing - the
## body keeps its brain, its collision and its clock, and the party walks into it
## standing where it was.
func check_eye_culling() -> void:
	var cave = game.delve_area.cave
	var mobs: Array = cave.mobs()
	check(mobs.size() > 20, "the floor fields bodies to cull (%d)" % mobs.size())
	var target = mobs[0]
	var at: Vector3 = target.global_position
	var inside := 0
	for mob in mobs:
		if (mob as Node3D).global_position.distance_to(at) <= cave.BODY_HIDE_DISTANCE:
			inside += 1
	cave.cull_bodies(at)
	var culled := 0
	for mob in mobs:
		if bool(mob.get("culled")):
			culled += 1
	check(culled == mobs.size() - inside,
		"exactly the bodies outside the eye's reach are culled (%d of %d, %d inside)"
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
	var local: Vector3 = area.cave.to_local(_soul().global_position)
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
	var posts: Array[Vector3] = cave.entry_posts(landing_id, _party.size())
	for index in _party.size():
		var body = game.controller.body_of(_party[index])
		if body != null:
			body.teleport_to(posts[index], cave.entry_yaw(landing_id))
	await _frames(3)


# --- a den, a kill, the loot -----------------------------------------------

func check_den_and_loot() -> void:
	var cave = game.delve_area.cave
	var soul = _soul()
	var room: Rect2 = Layout.room("den")["rect"]
	soul.teleport_to(cave.to_global(Vector3(0.0, 0.12, room.end.y - 3.0)), 0.0)
	await create_timer(0.45).timeout
	check(cave.is_awake("den"), "a body in the den's room wakes it")
	var den: Array = cave.den_mobs("den")
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
	soul.teleport_to(victim.global_position + Vector3(1.2, 0.12, 0.0), 0.0)
	await _frames(1)
	var target: Dictionary = game.loot_hand.target_at(soul, victim.global_position + Vector3(0.0, 0.4, 0.0))
	check(str(target.get("kind", "")) == "corpse", "a press on the body finds the corpse")
	# Below, the right click is the take itself: the whole body and the steel that
	# fell beside it, straight into the delve inventory and onto nobody.
	var soul_merc := int(game.controller.merc_for_peer(1))
	var worn_before: Array = warband.roster.worn_entries(soul_merc)
	var on_body: Array[String] = game.loot.corpse_items(corpse_id)
	var took: Array[String] = game.loot_hand.take_now(soul, target)
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
	# The loot window is the right click above; opened on a body below it still
	# books into the delve inventory.
	var second_id := 0
	var second_at := Vector3.ZERO
	for mob in den:
		var other_id: int = game.loot.corpse_at(mob.global_position, 0.6)
		if mob != victim and other_id != 0:
			second_id = other_id
			second_at = mob.global_position
			break
	soul.teleport_to(second_at + Vector3(1.2, 0.12, 0.0), 0.0)
	await _frames(1)
	var window_rows := 0
	if game.loot_window.open_on(soul, {"kind": "corpse", "corpse_id": second_id, "pickup": null}):
		window_rows = game.loot_window.rows().size()
	var held_before: int = warband.delve.inventory.pooled_total()
	game.loot_window.take_all()
	check(window_rows > 0 and not game.loot_window.is_open() and warband.delve.inventory.pooled_total() > held_before,
		"the loot window lists a body below and takes the lot into the inventory (%d rows)" % window_rows)
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
	var waited := 0.0
	var emptied := 0
	while waited < 14.0 and emptied < wanted:
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
	# The master: woken, killed, and taken whole with one right click.
	var master = cave.master
	master.take_damage(99999.0, 1)
	await _frames(2)
	check(not cave.master_alive(), "Gorehorn dies")
	var master_corpse: int = game.loot.corpse_at(master.global_position, 1.0)
	check(master_corpse != 0 and game.loot.corpse_items(master_corpse).has("ring_blood"),
		"the master's body carries the floor's prize")
	soul.teleport_to(master.global_position + Vector3(1.0, 0.12, 0.0), 0.0)
	await _frames(1)
	var spoils: Dictionary = game.loot_hand.target_at(soul, master.global_position + Vector3(0.0, 0.4, 0.0))
	check(game.loot_hand.take_now(soul, spoils).has("ring_blood"), "a right click takes the master's body whole")
	check(warband.delve.inventory.pooled_count("ring_blood") == 1, "the prize is in the delve inventory")
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
	soul.teleport_to(body.global_position + Vector3(1.0, 0.12, 0.0), 0.0)
	await _frames(1)
	var target: Dictionary = game.loot_hand.target_at(soul, body.global_position + Vector3(0.0, 0.4, 0.0))
	check(int(target.get("corpse_id", 0)) == remains, "a press on his body finds him")
	var took: Array[String] = game.loot_hand.take_now(soul, target)
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
	var rope_id := "mere" if game.delve_area.landing != "mere" else "chapel"
	soul.teleport_to(cave.rope_point(rope_id) + Vector3(0.0, 0.12, 1.0), 0.0)
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
	game._try_interact()
	await create_timer(0.2).timeout
	check(not game.delve_area.below() and not warband.delve.active, "G at the rope ends the descent")
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
	var result: Dictionary = area.descend(party)
	check(bool(result.get("ok", false)), "a second party goes down (%s)" % str(result.get("message", "")))
	check(not area.cave.is_awake("den"), "into a fresh instance: the den sleeps again")
	for merc_id in party:
		game.controller.body_of(merc_id).take_damage(9999.0, 90)
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
	check(merc_id > 0, "a dressed body is left to test the load with")
	if merc_id <= 0:
		return
	warband.pack_for_delve("sword_arming", 1)
	check(bool(warband.begin_delve([merc_id]).get("ok", false)), "the books take a party down")
	warband.load_state()
	check(not warband.delve.active, "a save that still holds a party below loads with nobody below")
	check(warband.roster.worn_entries(merc_id).is_empty(), "and that party's gear is lost")
	check(warband.delve.inventory.pooled_total() == 0, "with what it packed")
