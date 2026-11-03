extends SceneTree
## Save slots: one folder per campaign under `user://saves`.
##
## The invariant this test exists for is the one a single shared file could not
## keep: starting a campaign (NEW CAMPAIGN, or HOST GAME's NEW GAME) writes its own
## folder and leaves every other campaign on the machine exactly as it was - its
## roster, its stash, its bookmark and its purse. The rest is the ledger itself:
## a repeated name is numbered, `active` survives a restart, and the single save a
## build before this node wrote is adopted instead of abandoned.

const WarbandStateScript = preload("res://scripts/warband/warband_state.gd")
const SaveSlotsScript = preload("res://scripts/warband/save_slots.gd")

const ROOT := "user://saves_regression"
const LEGACY_WARBAND := "user://saves_regression_legacy_warband.json"
const LEGACY_PURSE := "user://saves_regression_legacy_purse.json"

var slots
var warband
var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("SAVE_SLOTS_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(child)):
			_remove_tree(child)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _purse(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return -1
	return int((parsed as Dictionary).get("credits", -1))


func run() -> void:
	slots = root.get_node_or_null("SaveSlots")
	warband = root.get_node("Warband")
	state = root.get_node("PlayerState")
	check(slots != null, "the SaveSlots autoload exists")
	if slots == null:
		_finish()
		return
	check(str(slots.root_path) == SaveSlotsScript.TEST_ROOT,
		"a script-mode run keeps its own ledger (%s)" % str(slots.root_path))
	# A scratch ledger: nothing here can touch a real campaign.
	slots.root_path = ROOT
	_remove_tree(ROOT)
	slots.load_index()
	check(slots.slots.is_empty() and str(slots.active).is_empty(),
		"a ledger with no file is empty (%s)" % slots.describe())

	# --- campaign one: a warband and a purse of its own ----------------------
	var first := str(slots.new_slot("Alex"))
	check(first == "c1", "the first campaign is c1 (%s)" % first)
	check(str(slots.name_of(first)) == "Alex", "the typed name is kept (%s)" % str(slots.name_of(first)))
	check(bool(slots.bind(first)), "binding the first campaign works")
	check(str(warband.save_path) == str(slots.warband_path(first)),
		"the warband writes the bound campaign (%s)" % str(warband.save_path))
	check(str(state.save_path) == str(slots.purse_path(first)),
		"the purse writes the bound campaign (%s)" % str(state.save_path))
	warband.reset_state()
	warband.add_mercenary("Ash")
	warband.add_mercenary("Bram")
	warband.save_state()
	state.credits = 4321
	state.save_state()
	var first_warband := str(slots.warband_path(first))
	var first_purse := str(slots.purse_path(first))
	check(FileAccess.file_exists(first_warband), "the first campaign's warband is on disk")
	check(_purse(first_purse) == 4321, "the first campaign's purse is on disk")

	# --- campaign two: a new game, and the first one untouched --------------
	var second := str(slots.new_slot("Alex"))
	check(second != first, "a second campaign is a second folder (%s)" % second)
	check(str(slots.name_of(second)) == "Alex 2",
		"a repeated name takes a number (%s)" % str(slots.name_of(second)))
	check(bool(slots.bind(second)), "binding the second campaign works")
	check(int(state.credits) == int(state.STARTING_CREDITS),
		"a campaign with no purse of its own starts on the starting purse (%d)" % int(state.credits))
	state.reset(true)
	warband.reset_state()
	warband.add_mercenary("Corvin")
	warband.save_state()
	check(_purse(first_purse) == 4321,
		"the first campaign keeps its purse after a new game (%d)" % _purse(first_purse))
	var first_peek: Dictionary = WarbandStateScript.peek_save(first_warband)
	check(int(first_peek.get("roster", 0)) == 2,
		"the first campaign keeps its roster after a new game (%d)" % int(first_peek.get("roster", 0)))
	check(FileAccess.file_exists(first_warband), "the first campaign's file is still there")
	var second_peek: Dictionary = WarbandStateScript.peek_save(str(slots.warband_path(second)))
	check(int(second_peek.get("roster", 0)) == 1,
		"the new campaign holds only its own roster (%d)" % int(second_peek.get("roster", 0)))

	# --- the ledger's own bookkeeping ---------------------------------------
	var rows: Array = slots.summaries()
	check(rows.size() == 2, "the ledger lists both campaigns (%d)" % rows.size())
	if rows.size() == 2:
		check(str(rows[0]["id"]) == second, "the newest campaign is first (%s)" % str(rows[0]["id"]))
		check(bool(rows[0]["active"]) and not bool(rows[1]["active"]),
			"only the bound campaign is active")
		check(str(rows[0]["name"]) == "Alex 2" and str(rows[1]["name"]) == "Alex",
			"the names are in the list as they were typed (%s / %s)" % [str(rows[0]["name"]), str(rows[1]["name"])])
		check(int(rows[0]["roster"]) == 1 and int(rows[1]["roster"]) == 2,
			"each row says how much warband it holds (%d / %d)" % [int(rows[0]["roster"]), int(rows[1]["roster"])])

	# The in-world SAVE line names the campaign: every campaign's warband file is
	# called the same thing now, so the file name alone would say nothing.
	var menu = load("res://scripts/warband/warband_menu.gd").new()
	root.add_child(menu)
	check(menu.save_game(), "the in-world save writes the bound campaign")
	check(menu.status_text().contains("Alex 2"),
		"the save line names the campaign (%s)" % menu.status_text())
	menu.queue_free()

	# Binding an earlier campaign reads its purse back: two campaigns, two walls.
	check(bool(slots.bind(first)), "binding an earlier campaign works")
	check(int(state.credits) == 4321,
		"binding an earlier campaign reads its purse back (%d)" % int(state.credits))

	# A restart reads the same ledger: the ids, the names and the active campaign.
	var reloaded = SaveSlotsScript.new()
	reloaded.root_path = ROOT
	reloaded.load_index()
	check(reloaded.slots.size() == 2, "the ledger survives a restart (%d rows)" % reloaded.slots.size())
	check(str(reloaded.active) == first, "the last bound campaign survives a restart (%s)" % str(reloaded.active))
	check(str(reloaded.name_of(second)) == "Alex 2", "the names survive a restart")
	reloaded.free()

	# --- the single save a build before the ledger wrote is adopted ---------
	_remove_tree(ROOT)
	slots.load_index()
	check(slots.slots.is_empty(), "the scratch ledger is empty again")
	var legacy_warband := FileAccess.open(LEGACY_WARBAND, FileAccess.WRITE)
	legacy_warband.store_string('{"version":12,"roster":{"mercenaries":[],"next_id":1,"version":1},"stash":{"pooled":{"arrow":24}}}')
	legacy_warband.close()
	var legacy_purse := FileAccess.open(LEGACY_PURSE, FileAccess.WRITE)
	legacy_purse.store_string('{"credits":87669}')
	legacy_purse.close()
	var adopted := str(slots.migrate_legacy(LEGACY_WARBAND, LEGACY_PURSE))
	check(adopted == "c1", "the old save is adopted as the first campaign (%s)" % adopted)
	check(str(slots.name_of(adopted)) == SaveSlotsScript.MIGRATED_NAME,
		"the adopted campaign is named (%s)" % str(slots.name_of(adopted)))
	check(FileAccess.file_exists(str(slots.warband_path(adopted))),
		"the warband moved into the campaign folder")
	check(_purse(str(slots.purse_path(adopted))) == 87669,
		"the purse moved with it (%d)" % _purse(str(slots.purse_path(adopted))))
	check(not FileAccess.file_exists(LEGACY_WARBAND) and not FileAccess.file_exists(LEGACY_PURSE),
		"the old files are gone, so one campaign is not two copies")
	check(str(slots.active) == adopted, "the adopted campaign is the one the next launch opens")
	var stray := FileAccess.open(LEGACY_WARBAND, FileAccess.WRITE)
	stray.store_string('{"version":12}')
	stray.close()
	check(str(slots.migrate_legacy(LEGACY_WARBAND, LEGACY_PURSE)).is_empty(),
		"a ledger with a campaign in it adopts nothing")
	check(FileAccess.file_exists(LEGACY_WARBAND), "and leaves the stray file where it is")

	_finish()


func _finish() -> void:
	_remove_tree(ROOT)
	_remove(LEGACY_WARBAND)
	_remove(LEGACY_PURSE)
	if slots != null:
		slots.root_path = SaveSlotsScript.TEST_ROOT
	print("SAVE_SLOTS_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
