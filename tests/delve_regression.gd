extends SceneTree
## The delve loop on the real world: make up a party and a delve inventory at the
## Weeping Hollow's mouth, go down into a fresh instance, wake a den, kill and loot
## below, climb out with it, then go down again and fall.
##
## What it holds the loop to:
##   * packing moves free pieces from the town stash into the delve inventory and
##     back; the descent is written to the save at once;
##   * below, the party is the only thing a soul or a paperdoll can reach, the
##     quiver is the inventory, and everything taken - by the window, the shift
##     take-all or a squadmate - lands in the inventory and never in the stash;
##   * a den sleeps until a body is in its room, then joins the hostile list whole;
##   * climbing out brings the party up and empties the inventory into the stash;
##   * falling loses the inventory and everything the party wears, and wakes the
##     downed in the square;
##   * a save still holding a party below loads as a fall.

const WorldScene := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://delve_player.json"
const WARBAND_SAVE := "user://delve_warband.json"
const AreaScript = preload("res://scripts/warband/delve_area.gd")

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
	await check_den_and_loot()
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


## Whether a piece is the party's below: in the delve inventory, or on a body of
## the party (a take by the soul's own hands puts a better piece straight on).
func _carried_below(item_id: String) -> bool:
	if warband.delve.inventory.pooled_count(item_id) > 0:
		return true
	for merc_id in warband.delve.party:
		for entry in warband.roster.worn_entries(merc_id):
			if str(entry.get("item", "")) == item_id:
				return true
	return false


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
	area.prep.pack("arrow", true)
	check(warband.delve.inventory.pooled_count("arrow") == arrows,
		"a shift-click packs every shaft (%d)" % warband.delve.inventory.pooled_count("arrow"))
	check(warband.stash.pooled_count("arrow") == 0, "and the stash has none left")
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
	area.prep.descend_requested.emit(area.prep.selected())
	await _frames(3)
	check(not area.prep.is_open(), "GO DOWN closes the panel")
	check(area.below() and warband.delve.active, "the party is below")
	check(warband.delve.party == _party, "the books hold the chosen party (%s)" % str(warband.delve.party))
	var cave = area.cave
	for merc_id in _party:
		var body = game.controller.body_of(merc_id)
		check(body != null and cave.contains(body.global_position),
			"%s landed in the cave" % warband.roster.name_of(merc_id))
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
	await create_timer(0.25).timeout
	check(game.camera.environment == cave.environment, "the eye below has the cave's sky")
	var sun = game.find_child("WorldSun", true, false)
	check(sun == null or not sun.visible, "and the moon is out")
	check(game.squad.nav == cave.nav and cave.nav != null, "the squad walks the cave's map")
	check(not cave.is_awake("den") and not game.guards.has(cave._dens[0]["mobs"][0]),
		"the den sleeps off the hostile list")
	check(game.delve_area.prompt_line(_soul()).begins_with("SLAY GOREHORN"),
		"the crosshair names the floor's objective (%s)" % game.delve_area.prompt_line(_soul()))


# --- a den, a kill, the loot -----------------------------------------------

func check_den_and_loot() -> void:
	var cave = game.delve_area.cave
	var soul = _soul()
	soul.teleport_to(cave.to_global(Vector3(0.0, 0.12, -27.0)), 0.0)
	await create_timer(0.45).timeout
	check(cave.is_awake("den"), "a body in the den's room wakes it")
	var den: Array = cave._dens[0]["mobs"]
	var listed := 0
	for mob in den:
		if game.guards.has(mob):
			listed += 1
	check(listed == den.size(), "the whole den joins the hostile list (%d of %d)" % [listed, den.size()])
	check(not cave.is_awake("ossuary"), "the next den sleeps on")
	var stash_before: Dictionary = warband.stash.pooled_map()
	var inventory_before: int = warband.delve.inventory.pooled_total()
	var victim = den[0]
	for mob in den:
		mob.take_damage(9999.0, 1)
	await _frames(2)
	check(not bool(victim.get("alive")), "the den falls")
	var corpse_id: int = game.loot.corpse_at(victim.global_position, 1.0)
	check(corpse_id != 0, "a fallen watcher is a body to search")
	soul.teleport_to(victim.global_position + Vector3(1.2, 0.12, 0.0), 0.0)
	await _frames(1)
	var target: Dictionary = game.loot_hand.target_at(soul, victim.global_position + Vector3(0.0, 0.4, 0.0))
	check(str(target.get("kind", "")) == "corpse", "a press on the body finds the corpse")
	check(game.loot_window.open_on(soul, target), "the loot window opens on it")
	var listed_rows: Array = game.loot_window.rows()
	check(not listed_rows.is_empty(), "the window lists what the body had (%d rows)" % listed_rows.size())
	var first := str(listed_rows[0]["item_id"]) if not listed_rows.is_empty() else ""
	var took: Array = game.loot_window.take(first)
	check(took.size() >= 1 and str(took[0]) == first, "a click takes that row (%s)" % str(took))
	game.loot_window.take_all()
	check(not game.loot_window.is_open(), "taking the lot empties and closes the window")
	# A piece the soul's hands take may go straight onto its body; either way it
	# is the party's below, and the inventory grew.
	check(warband.delve.inventory.pooled_total() > inventory_before,
		"the take lands in the delve inventory (%d -> %d)" % [inventory_before,
			warband.delve.inventory.pooled_total()])
	check(warband.stash.pooled_map() == stash_before, "the town stash did not move while below")
	check(not game.loot_feed.lines().is_empty(), "the looted list names what came up (%s)" % str(game.loot_feed.lines()))
	check(game.loot_feed.header_text().contains("DELVE INVENTORY"), "and the delve's line heads it")
	# The rest of the den is the squad's: it walks the cave's map down to the soul
	# and strips the bodies and the steel on the floor into the same inventory.
	var others: Array[int] = []
	for mob in den:
		if mob != victim:
			var other_id: int = game.loot.corpse_at(mob.global_position, 1.0)
			if other_id != 0:
				others.append(other_id)
	check(not others.is_empty(), "the squad has bodies left to strip")
	var waited := 0.0
	var stripped := false
	while waited < 14.0 and not stripped:
		await create_timer(0.5).timeout
		waited += 0.5
		stripped = true
		for other_id in others:
			if game.loot.has_corpse(other_id):
				stripped = false
	check(stripped, "the squad strips the den's bodies on its own (%.1f s)" % waited)
	var by_squad := false
	for line in game.loot_feed.lines():
		if str(line).ends_with("squad"):
			by_squad = true
	check(by_squad, "and the looted list says the squad took it (%s)" % str(game.loot_feed.lines()))
	check(warband.stash.pooled_map() == stash_before, "none of it reached the town stash")
	# The master: woken, killed, and stripped with the shift take-all.
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
	check(game.loot_hand.begin_on(soul, spoils), "shift-right-click starts the take-all on the master")
	game.loot_hand.tick(1.0)
	check(_carried_below("ring_blood"), "the prize is carried below")
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


# --- climbing out ----------------------------------------------------------

func check_climb_out() -> void:
	var cave = game.delve_area.cave
	var soul = _soul()
	soul.teleport_to(cave.exit_point() + Vector3(0.0, 0.12, -1.0), 0.0)
	await _frames(2)
	check(cave.at_exit(soul), "a body at the rope is at the way up")
	check(game.delve_area.prompt_line(soul).begins_with("G  -  CLIMB OUT"),
		"the crosshair names the climb (%s)" % game.delve_area.prompt_line(soul))
	var carried: Dictionary = warband.delve.inventory.pooled_map()
	var stash_before: Dictionary = warband.stash.pooled_map()
	var below_mobs: Array = cave.mobs()
	game._try_interact()
	await create_timer(0.2).timeout
	check(not game.delve_area.below() and not warband.delve.active, "G at the rope ends the descent")
	check(warband.delve.inventory.pooled_total() == 0, "the delve inventory is emptied")
	var home := true
	for item_id in carried:
		if warband.stash.pooled_count(str(item_id)) != int(stash_before.get(item_id, 0)) + int(carried[item_id]):
			home = false
	check(home, "every piece carried up is in the town stash")
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
