extends SceneTree
## Corpse looting regression for Ghost of the Warband: a fallen enemy as a
## container instead of a pile on the floor, the single booking path into the
## infinite shared stash, the squad's silent claim, a freed body that reports
## empty instead of crashing, and the corpse screen itself - open, list, take,
## strip, and refuse a piece that is already gone.

const StateScript = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const PanelScript = preload("res://scripts/warband/corpse_loot_panel.gd")
const SoldierRunScript = preload("res://scripts/warband/soldier_loot_run.gd")

const TEST_SAVE := "user://corpse_loot_state.json"

## Each scenario uses its own ids, so "the stash gained exactly one copy" never
## needs arithmetic on a shared counter.
const BLADE := "sword_makeshift"
const RAG := "armor_makeshift_chest"
const SHIV := "dagger_ironwood"
const HOOD := "armor_leather_head"
const CLUB := "club_makeshift"
const SHIELD := "shield_wood"
const BRANCH := "branch_heavy"
const SQUAD_BLADE := "focus_skull_death"
const SQUAD_RAG := "neck_ember"
const PANEL_BOW := "bow_twig"
const PANEL_HELM := "armor_cloth_head"
const PANEL_SHIRT := "armor_naked_chest"

## A body that answers `gear_items()` the way an enemy does. `reads` proves the
## corpse record takes the kit once instead of asking a stripped body again.
class DummyCorpse extends Node3D:
	var carried: Array[String] = []
	var reads := 0

	func gear_items() -> Array[String]:
		reads += 1
		return carried.duplicate()

	func get_display_name() -> String:
		return "Camp Watcher"

class DummyRig extends Node:
	var steps := 0

	func set_locomotion(_velocity: Vector3, _grounded: bool) -> void:
		steps += 1

class DummySoldier extends Node3D:
	var alive := true
	var downed := false
	var move_direction := Vector2.ZERO
	var run_requested := false
	var rig: DummyRig = null

var checks := 0
var failures := 0

var _warband = null
var _field: Node3D = null
var _loot: WarbandLoot = null
## The body `check_single_take()` and `check_claim()` share.
var _single_corpse := 0
var _single_body: DummyCorpse = null

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CORPSE_LOOT_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()
	_warband = warband

	_field = Node3D.new()
	_field.name = "Battlefield"
	root.add_child(_field)
	_loot = LootScript.new()
	_loot.name = "Loot"
	root.add_child(_loot)
	_loot.setup(warband, _field)

	check_registration()
	check_single_take()
	check_claim()
	await check_freed_body()
	await check_squad_claim()
	check_panel()

	_remove_test_save()
	print("CORPSE_LOOT_OK ", checks)
	quit(0 if failures == 0 else 1)

# --- helpers ---------------------------------------------------------------

func _body(kit: Array[String], at: Vector3, tag: String) -> DummyCorpse:
	var body := DummyCorpse.new()
	body.name = tag
	body.carried = kit
	root.add_child(body)
	body.global_position = at
	return body

func _pooled(item_id: String) -> int:
	return int(_warband.stash.pooled_count(item_id))

func _ids(items: Array) -> String:
	return str(items)

# --- registration ----------------------------------------------------------

func check_registration() -> void:
	var kit: Array[String] = [BLADE, RAG]
	var body := _body(kit, Vector3(3.0, 0.0, 2.0), "WatcherA")
	var corpse := _loot.register_corpse(body)
	check(corpse > 0, "a body carrying gear registers")
	check(body.reads == 1, "the kit is read once, got %d reads" % body.reads)
	check(_loot.has_corpse(corpse), "the corpse is there to search")
	check(_loot.corpse_items(corpse) == kit,
		"the corpse carries the body's kit, got %s" % _ids(_loot.corpse_items(corpse)))
	check(_loot.corpse_label(corpse) == "Camp Watcher",
		"the corpse names who fell, got %s" % _loot.corpse_label(corpse))
	check(_loot.corpse_position(corpse).distance_to(Vector3(3.0, 0.0, 2.0)) < 0.001,
		"the corpse reports where it lies")
	check(_loot.corpse_at(Vector3(3.4, 0.0, 2.2), 1.0) == corpse,
		"a body inside reach is found")
	check(_loot.corpse_at(Vector3(40.0, 0.0, 40.0), 2.0) == 0,
		"a body across the field is not in reach")
	check(_loot.corpse_ids().has(corpse), "the corpse is listed for the AI")
	check(_loot.corpse_value(corpse)
		== StashScript.value_of(BLADE) + StashScript.value_of(RAG),
		"the corpse is valued by the stash rule")

	check(_loot.register_corpse(body) == corpse, "registering the same body twice keeps one record")
	check(body.reads == 1, "a second registration does not re-read a stripped body")
	check(_loot.corpse_ids().size() == 1, "one body, one corpse")

	var none: Array[String] = []
	var empty := _body(none, Vector3.ZERO, "WatcherEmpty")
	check(_loot.register_corpse(empty) == 0, "a body carrying nothing gets no corpse id")
	check(_loot.corpse_ids().size() == 1, "an empty body adds no corpse")

	# The first corpse is left with its kit for the next check.
	_single_corpse = corpse
	_single_body = body

# --- one piece at a time ---------------------------------------------------

func check_single_take() -> void:
	check(_pooled(BLADE) == 0, "the blade is not in the stash yet")
	var taken := _loot.take_from_corpse(_single_corpse, BLADE, 0)
	check(bool(taken.get("ok", false)), "a piece can be taken off a body")
	check(str(taken.get("item_id", "")) == BLADE, "the take names the piece")
	check(str(taken.get("message", "")).contains("shared stash"),
		"the take says where the piece went, got %s" % str(taken.get("message", "")))
	check(_pooled(BLADE) == 1, "the piece is a stash row at once")
	check(int(taken.get("remaining", -1)) == 1, "the take counts what is left")
	check(_loot.corpse_items(_single_corpse).size() == 1
		and _loot.corpse_items(_single_corpse)[0] == RAG,
		"the body no longer lists the piece, got %s" % _ids(_loot.corpse_items(_single_corpse)))

	var again := _loot.take_from_corpse(_single_corpse, BLADE, 0)
	check(not bool(again.get("ok", true)), "the same piece cannot be taken twice")
	check(str(again.get("message", "")).contains("not on that body"),
		"the refusal explains itself, got %s" % str(again.get("message", "")))
	check(_pooled(BLADE) == 1, "a refused take pays nothing")

	var stranger := _loot.take_from_corpse(_single_corpse, CLUB, 0)
	check(not bool(stranger.get("ok", true)), "a piece the body never carried is refused")
	check(_pooled(CLUB) == 0, "a refused stranger stays out of the stash")

# --- the squad's claim -----------------------------------------------------

func check_claim() -> void:
	var claimed := _loot.claim_corpse(_single_corpse, 0)
	check(bool(claimed.get("ok", false)), "claim_corpse strips the rest of the body")
	check(int(claimed.get("count", -1)) == 1, "the claim counts one piece")
	check((claimed.get("ids", []) as Array).has(RAG), "the claim names the piece")
	check(int(claimed.get("value", -1)) == StashScript.value_of(RAG),
		"the claim values the piece by the stash rule")
	check(_pooled(RAG) == 1, "the claimed piece is a stash row")
	check(_loot.corpse_items(_single_corpse).is_empty(), "an empty corpse reports empty")
	check(not _loot.corpse_ids().has(_single_corpse), "a stripped body drops out of the AI's list")
	check(_loot.corpse_at(_single_body.global_position, 5.0) == 0,
		"a stripped body is no longer lootable")

	var again := _loot.claim_corpse(_single_corpse, 0)
	check(not bool(again.get("ok", true)), "a second claim reports empty")
	check(int(again.get("count", -1)) == 0, "a second claim takes nothing")
	check(_pooled(RAG) == 1, "a second claim cannot duplicate a piece")
	check(not _loot.has_corpse(_single_corpse), "a stripped body is no longer offered")

	var late := _loot.take_from_corpse(_single_corpse, RAG, 0)
	check(not bool(late.get("ok", true)), "a stripped body refuses a piece")
	check(str(late.get("message", "")).contains("nothing left"),
		"the empty body says so, got %s" % str(late.get("message", "")))

	var club_kit: Array[String] = [CLUB]
	var club_body := _body(club_kit, Vector3(-4.0, 0.0, 1.0), "WatcherClub")
	var club_corpse := _loot.register_corpse(club_body)
	check(club_corpse > 0, "the club carrier registers")
	check(club_corpse != _single_corpse, "every body gets its own stable id")
	var claimed_club := _loot.claim_corpse(club_corpse, 0)
	check(int(claimed_club.get("count", -1)) == 1, "claim_corpse takes the id's kit")
	check(_pooled(CLUB) == 1, "the club reaches the stash once")
	check(int(_loot.claim_corpse(club_corpse, 0).get("count", -1)) == 0,
		"the same id cannot claim twice")
	check(_pooled(CLUB) == 1, "the club is still one copy")

	check(_loot.battlefield_value()
		== StashScript.value_of(BLADE) + StashScript.value_of(RAG)
		+ StashScript.value_of(CLUB),
		"every corpse take is in the battle ledger, got %d" % _loot.battlefield_value())

# --- the body that is gone -------------------------------------------------

func check_freed_body() -> void:
	var kit: Array[String] = [SHIELD, BRANCH]
	var body := _body(kit, Vector3(9.0, 0.0, 9.0), "WatcherFreed")
	var corpse := _loot.register_corpse(body)
	check(corpse > 0, "the doomed body registers")
	var taken := _loot.take_from_corpse(corpse, SHIELD, 0)
	check(bool(taken.get("ok", false)), "the shield comes off before the body goes")
	check(_pooled(SHIELD) == 1, "the shield is a stash row")

	body.queue_free()
	await process_frame
	check(_loot.corpse_items(corpse).is_empty(), "a freed body reports empty, not stale")
	check(not _loot.has_corpse(corpse), "a freed body is forgotten")
	check(not _loot.corpse_ids().has(corpse), "a freed body is not offered to the AI")
	check(_loot.corpse_position(corpse) == Vector3.ZERO, "a freed body has no position")
	check(_loot.corpse_at(Vector3(9.0, 0.0, 9.0), 5.0) == 0, "a freed body cannot be found")

	var after := _loot.take_from_corpse(corpse, BRANCH, 0)
	check(not bool(after.get("ok", true)), "taking from a freed body is refused")
	check(_pooled(BRANCH) == 0, "a freed body's piece never reaches the stash")
	check(int(_loot.claim_corpse(corpse, 0).get("count", -1)) == 0,
		"claiming a freed body reports empty instead of crashing")

# --- the squad strips bodies on its own ------------------------------------

func check_squad_claim() -> void:
	var kit: Array[String] = [SQUAD_BLADE, SQUAD_RAG]
	var body := _body(kit, Vector3(4.0, 0.0, 0.0), "WatcherSquad")
	var corpse := _loot.register_corpse(body)
	check(corpse > 0, "the squad's body registers")

	var first := DummySoldier.new()
	first.name = "SoldierA"
	first.rig = DummyRig.new()
	root.add_child(first)
	first.global_position = Vector3.ZERO
	var second := DummySoldier.new()
	second.name = "SoldierB"
	second.rig = DummyRig.new()
	root.add_child(second)
	second.global_position = Vector3(0.6, 0.0, 0.0)

	var runner = SoldierRunScript.new()
	runner.name = "CorpseRun"
	root.add_child(runner)
	runner.setup(_warband, _loot, [first, second])
	var collected := [0]
	runner.finished.connect(func(count: int) -> void: collected[0] = count)

	runner.run([])
	check(runner.running(), "the squad sets off for the body")
	await create_timer(1.3).timeout
	check(runner.done(), "the squad's run finishes")
	check(int(collected[0]) == 2, "the run reports both pieces, got %d" % int(collected[0]))
	check(_pooled(SQUAD_BLADE) == 1, "the squad books the blade into the stash")
	check(_pooled(SQUAD_RAG) == 1, "the squad books the rag into the stash")
	check(_loot.corpse_items(corpse).is_empty(), "the squad leaves an empty body")
	check(not _loot.corpse_ids().has(corpse), "the stripped body is not re-offered")
	check(first.rig.steps > 0 or second.rig.steps > 0,
		"the jog drives the rig's step cycle")

	runner.run([])
	check(int(collected[0]) == 0, "a second run finds nothing left")
	check(runner.done(), "a run with no targets finishes at once")
	check(_pooled(SQUAD_BLADE) == 1 and _pooled(SQUAD_RAG) == 1,
		"no soldier can book the same corpse piece twice")

# --- the corpse screen -----------------------------------------------------

func check_panel() -> void:
	var kit: Array[String] = [PANEL_BOW, PANEL_HELM]
	var body := _body(kit, Vector3(8.0, 0.0, 8.0), "WatcherPanel")
	var corpse := _loot.register_corpse(body)
	check(corpse > 0, "the screen's body registers")

	var panel = PanelScript.new()
	panel.name = "CorpseScreen"
	root.add_child(panel)
	panel.configure(_warband)
	check(not panel.is_open(), "the corpse screen starts closed")
	check(not panel.open_corpse(_loot, 0), "there is no body at corpse id 0")
	check(not panel.open_corpse(null, corpse), "a screen with no vacuum opens nothing")
	check(not panel.is_open(), "a refused open shows nothing")

	check(panel.open_corpse(_loot, corpse), "the screen opens on a body holding gear")
	check(panel.is_open() and panel.showing_corpse(), "the screen is open on the corpse")
	check(panel.title_label.text.begins_with("THE DEAD"),
		"the screen titles the dead, got %s" % panel.title_label.text)
	check(panel.title_label.text.contains("CAMP WATCHER"),
		"the title names the body, got %s" % panel.title_label.text)
	check(panel.corpse_rows.size() == 2,
		"the screen lists every carried piece, got %d" % panel.corpse_rows.size())
	check(str(panel.corpse_rows[0]["item_id"]) == PANEL_BOW, "the list keeps the carry order")
	check(str(panel.corpse_rows[0]["name"]) == str(StateScript.ITEMS[PANEL_BOW]["name"]),
		"a row wears the catalog name, got %s" % str(panel.corpse_rows[0]["name"]))
	check(int(panel.corpse_rows[0]["value"]) == StashScript.value_of(PANEL_BOW),
		"a row wears the stash value")
	check(panel.corpse_rows[0]["button"].text.contains(str(StateScript.ITEMS[PANEL_BOW]["name"])),
		"the row button names the piece")
	check(str(panel.slot_rows["main"]["item_id"]) == PANEL_BOW,
		"the body's paperdoll wears the bow in the main hand")
	check(str(panel.slot_rows["head"]["item_id"]) == PANEL_HELM,
		"the body's paperdoll wears the helm on the head")

	# A worn row is a take, exactly like a list row.
	panel.slot_rows["head"]["button"].pressed.emit()
	check(_pooled(PANEL_HELM) == 1, "a click on the body's helm puts it in the stash")
	check(panel.corpse_rows.size() == 1, "the taken piece leaves the list")
	check(_loot.corpse_items(corpse).size() == 1, "the taken piece leaves the body")

	var taken: Dictionary = panel.take_piece(PANEL_BOW)
	check(bool(taken.get("ok", false)), "the last piece can be taken on demand")
	check(_pooled(PANEL_BOW) == 1, "the last piece is a stash row")
	check(panel.corpse_rows.is_empty(), "a stripped body lists nothing")
	check(panel.status_text().contains("shared stash"),
		"the take is reported, got %s" % panel.status_text())
	check(str(panel.slot_rows["main"]["item_id"]).is_empty(),
		"the stripped body wears nothing")

	var stale: Dictionary = panel.take_piece(PANEL_BOW)
	check(not bool(stale.get("ok", true)), "a row whose piece is gone is refused")
	check(panel.status_text().contains("nothing left"),
		"the refusal says the body is empty, got %s" % panel.status_text())
	check(_pooled(PANEL_BOW) == 1, "a stale click cannot duplicate a piece")

	var all: Dictionary = panel.take_all()
	check(not bool(all.get("ok", true)), "TAKE ALL on an empty body reports empty")
	check(int(all.get("count", -1)) == 0, "TAKE ALL on an empty body takes nothing")
	check(_pooled(PANEL_BOW) == 1 and _pooled(PANEL_HELM) == 1,
		"the stash holds one copy of each piece")

	panel.close()
	check(not panel.is_open(), "close() closes the screen")
	check(not panel.showing_corpse(), "close() leaves the corpse")
	check(panel.title_label.text == "PAPERDOLL", "the header goes back to the paperdoll")
	check(not panel.open_corpse(_loot, corpse), "a stripped body opens no screen")

	# One screen, both jobs: the same node still dresses the warband.
	panel.open(-1)
	check(panel.is_open() and not panel.showing_corpse(),
		"the same screen opens the warband's gear")
	check(panel.status_text().contains("Click a worn slot"), "the mercenary hint is back")
	panel.close()

	var shirt_kit: Array[String] = [PANEL_SHIRT]
	var shirt_body := _body(shirt_kit, Vector3(12.0, 0.0, 0.0), "WatcherShirt")
	var shirt_corpse := _loot.register_corpse(shirt_body)
	check(panel.open_corpse(_loot, shirt_corpse), "the screen opens on a second body")
	check(panel.corpse_rows.size() == 1, "the second body lists its own kit")
	check(str(panel.corpse_rows[0]["item_id"]) == PANEL_SHIRT,
		"the second body's row is its own piece")
	panel.close()
