extends SceneTree
## Main menu: exactly four doors - NEW CAMPAIGN, CAMPAIGNS, JOIN GAME, HOST GAME -
## the campaign list reading the save-slot ledger, the host panel's checkpoint gate
## on the campaign it selects, and the join form and host panel reading the network
## cache every time they open. Every campaign this test writes is a folder of its
## own, so a door that starts one is checked against the campaign it must not
## touch.
##
## The door presses come last and nothing awaits a frame after the first one: a
## press queues the flow's scene change, and this test checks what the flow was
## told, not the world it opens.

const NetCacheScript = preload("res://scripts/net_cache.gd")
const WarbandStateScript = preload("res://scripts/warband/warband_state.gd")
const STATE_SAVE := "user://title_menu_state.json"
const WARBAND_SAVE := "user://title_menu_warband.json"
const LEGACY_CACHE := "user://net_cache_legacy.json"
## The campaigns this test makes: a scratch ledger, removed before and after.
const SLOT_ROOT := "user://title_menu_saves"
const CHECKPOINT_LABEL := "THE CAMP IS BEHIND YOU"
const DOOR_TEXTS := ["NEW CAMPAIGN", "CAMPAIGNS", "JOIN GAME", "HOST GAME"]

var state
var warband
var flow
var cache
var slots
var audio
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TITLE_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## A campaign folder holds two files, so removing one means walking it.
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

## Put the ledger back to nothing, the way a machine with no campaign looks.
func _clear_ledger() -> void:
	_remove_tree(SLOT_ROOT)
	slots.load_index()

func _open_title():
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	return title

## A campaign with bodies, and a trail bookmark when asked for one. It is a real
## ledger row and the warband is bound to it, which is exactly what a door opens.
func _seed_save(with_checkpoint: bool) -> String:
	var id := str(slots.new_slot("Test campaign"))
	slots.bind(id)
	warband.reset_state()
	warband.add_mercenary("Old Ash")
	warband.add_mercenary("Brann")
	if with_checkpoint:
		warband.save_checkpoint("trail_start", "trail", Vector3(6.0, 0.0, -90.0), CHECKPOINT_LABEL)
	else:
		warband.save_state()
	# The live warband is emptied again so a door that opens the save has to
	# read it back from disk.
	warband.reset_state()
	return id

func _free_udp_port() -> int:
	var socket := PacketPeerUDP.new()
	check(socket.bind(0) == OK, "the test finds a free UDP port")
	var port := socket.get_local_port()
	socket.close()
	return port

func _escape(title) -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	title._unhandled_input(event)

func run() -> void:
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://title.tscn",
		"The title screen is the game's entry scene")
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	cache = root.get_node("NetCache")
	slots = root.get_node("SaveSlots")
	audio = root.get_node_or_null("Audio")
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	# The ledger is the save gate now: this test's campaigns live in a scratch
	# root, empty before the doors are checked.
	slots.root_path = SLOT_ROOT
	_remove_tree(SLOT_ROOT)
	slots.load_index()
	state.reset(false)
	warband.reset_state()
	flow.active = false
	flow.take_notice()
	cache.reset()

	await _check_doors()
	_check_escape()
	_check_join_form()
	_check_host_panel()
	_check_notice()
	_check_cache_restart()
	_check_campaign_doors()

	flow.leave_warband()
	flow.active = false
	flow.take_notice()
	state.reset(false)
	cache.reset()
	_remove_tree(SLOT_ROOT)
	_remove(cache.save_path)
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	_remove(LEGACY_CACHE)
	print("TITLE_MENU_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

## Four doors, in order, and nothing else in the column that can be pressed.
func _check_doors() -> void:
	var title = _open_title()
	await process_frame
	var column: Node = title.get_node_or_null("Doors")
	check(column != null, "the title has its Doors column")
	var doors: Array = []
	if column != null:
		for child in column.get_children():
			if child is BaseButton:
				doors.append(child)
	check(doors.size() == 4, "the column holds exactly four doors (%d)" % doors.size())
	var texts: Array = []
	for door in doors:
		texts.append(str(door.text))
	check(texts == DOOR_TEXTS, "the doors read %s in that order (%s)" % [str(DOOR_TEXTS), str(texts)])
	if doors.size() == 4:
		check(doors[0] == title.new_campaign_button and doors[1] == title.campaigns_button
			and doors[2] == title.join_button and doors[3] == title.host_button,
			"the four door members are the four buttons in the column")
	check(title.new_campaign_button.theme_type_variation == "PrimaryButton",
		"NEW CAMPAIGN is the primary door")
	for door in doors:
		check(door.visible, "%s is visible" % door.text)

	# No campaign: the list says so, and NEW CAMPAIGN is a form that writes nothing
	# until it is confirmed - the door itself can never write over a campaign.
	check(slots.slots.is_empty(), "the ledger starts empty in this test")
	title.campaigns_button.pressed.emit()
	check(title._campaigns_layer.visible, "CAMPAIGNS opens the campaign list")
	check(title._campaigns_empty.visible, "an empty ledger says there is nothing saved")
	check(title.campaign_ids().is_empty(), "an empty ledger lists no campaigns")
	_escape(title)
	check(not title._campaigns_layer.visible, "Escape closes the campaign list")
	title.new_campaign_button.pressed.emit()
	check(title._new_layer.visible, "NEW CAMPAIGN asks for a name")
	check(title._new_name_input.text == "Ranger",
		"the form offers the name in the cache (%s)" % title._new_name_input.text)
	check(slots.slots.is_empty(), "asking for a name writes no campaign")
	_escape(title)
	check(not title._new_layer.visible, "Escape closes the new-campaign form")

	# A campaign saved while the title stands is listed the next time the list is
	# opened, on the bookmark it would open.
	var id := _seed_save(true)
	title._open_campaigns()
	check(title.campaign_ids().size() == 1 and title.campaign_ids()[0] == id,
		"the list shows the campaign that was just saved (%s)" % str(title.campaign_ids()))
	check(title._campaigns_empty.visible == false, "the empty line goes away once a campaign exists")
	if title._campaigns_list.get_child_count() == 1:
		var row: Button = title._campaigns_list.get_child(0)
		check(str(row.text).begins_with("Test campaign"),
			"the row is named after the campaign (%s)" % str(row.text))
		check(str(row.text).contains(CHECKPOINT_LABEL),
			"the row names the saved checkpoint (%s)" % str(row.text))
	title.free()

	# A fresh title reads the same ledger, and a campaign deleted under the title
	# is gone from the next list rather than showing a dead row.
	title = _open_title()
	title._open_campaigns()
	check(title.campaign_ids().size() == 1, "a new title lists the saved campaign")
	_clear_ledger()
	title._open_campaigns()
	check(title.campaign_ids().is_empty() and title._campaigns_empty.visible,
		"a ledger emptied under the title shows no campaigns")
	title.free()

## Escape closes the settings window first, then the host panel, then the join
## form, and opens the settings when nothing else is up.
func _check_escape() -> void:
	var title = _open_title()
	title._open_host()
	_escape(title)
	check(not title._host_layer.visible, "Escape closes the host panel")
	title._open_join()
	_escape(title)
	check(not title._join_layer.visible, "Escape closes the join form")
	_escape(title)
	check(title.settings.is_open(), "Escape with nothing open opens the settings")
	_escape(title)
	check(not title.settings.is_open(), "Escape closes the settings again")
	title.free()

func _check_join_form() -> void:
	cache.remember("CachedRanger", "100.64.0.12", 7999)
	var title = _open_title()
	title.join_button.pressed.emit()
	check(title._join_layer.visible, "JOIN GAME opens the join form")
	check(title._name_input.text == "CachedRanger" and title._address_input.text == "100.64.0.12"
		and int(title._port_input.value) == 7999, "the join form restores the cached name, address and port")
	check(title._name_input.max_length == 16, "a join name is at most sixteen characters")
	# The form reads the cache when it opens, not once at startup; and it reads
	# the join port, never the host's own.
	cache.remember("FreshRanger", "100.64.0.44", 8111)
	cache.remember_host("FreshRanger", 9001)
	title._close_join()
	check(not title._join_layer.visible, "the join form can be cancelled")
	title._open_join()
	check(title._name_input.text == "FreshRanger" and title._address_input.text == "100.64.0.44"
		and int(title._port_input.value) == 8111, "the join form rereads the cache every time it opens")

	# An empty address is refused on the form, and nothing is joined.
	title._address_input.text = "   "
	title._confirm_join()
	check(title._form_error.text == "Enter the host's address.",
		"an empty address is refused (%s)" % title._form_error.text)
	check(title._join_layer.visible, "a refused join keeps the form open")
	check(flow.warband_intent.is_empty() and flow.session == null, "a refused join opens no session")
	check(cache.address == "100.64.0.44", "a refused join remembers nothing")
	title.free()
	cache.reset()

func _check_host_panel() -> void:
	_clear_ledger()
	cache.remember("JoinRanger", "100.64.0.12", 8123)
	cache.remember_host("HostRanger", 7788)
	var title = _open_title()
	title.host_button.pressed.emit()
	check(title._host_layer.visible, "HOST GAME opens the host panel")
	check(title._host_name_input.text == "HostRanger", "the host panel reads the cached name")
	check(int(title._host_port_input.value) == 7788,
		"the host panel opens on the host port, never the join port (%d)" % int(title._host_port_input.value))
	check(title.host_new_button.text == "NEW GAME" and title.host_checkpoint_button.text == "FROM CHECKPOINT",
		"the host panel offers NEW GAME and FROM CHECKPOINT")
	check(title._host_campaign_box.disabled, "the campaign selector is dead without a campaign")
	check(title.host_checkpoint_button.disabled, "FROM CHECKPOINT is disabled without a campaign")
	check(title._host_checkpoint_label.text == "No campaign saved yet.",
		"the host panel says there is nothing to host from (%s)" % title._host_checkpoint_label.text)
	title._close_host()

	# Two campaigns, played in order. The newest is what FROM CHECKPOINT offers,
	# and the selector moves the door to either one.
	_seed_save(false)
	_seed_save(true)
	cache.remember_host("HostRanger", 7799)
	title._open_host()
	check(int(title._host_port_input.value) == 7799, "the host panel rereads the host port every time it opens")
	check(not title._host_campaign_box.disabled, "the selector is live on a saved campaign")
	check(title._host_campaign_box.item_count == 2,
		"the selector lists both campaigns (%d)" % title._host_campaign_box.item_count)
	check(not title.host_checkpoint_button.disabled, "FROM CHECKPOINT is enabled on a warband save")
	check(title._host_checkpoint_label.text.contains(CHECKPOINT_LABEL),
		"FROM CHECKPOINT names the newest campaign's bookmark (%s)" % title._host_checkpoint_label.text)
	title._host_campaign_box.select(1)
	title._host_campaign_box.item_selected.emit(1)
	check(title._host_checkpoint_label.text.contains("saved warband - opens in Hearthstead"),
		"the older campaign, with no bookmark, opens in Hearthstead (%s)" % title._host_checkpoint_label.text)
	title._host_campaign_box.select(0)
	title._host_campaign_box.item_selected.emit(0)
	check(title._host_checkpoint_label.text.contains(CHECKPOINT_LABEL),
		"the selector moves FROM CHECKPOINT back to the bookmark (%s)" % title._host_checkpoint_label.text)
	title._close_host()
	_clear_ledger()
	title._refresh_campaigns()
	check(title.host_checkpoint_button.disabled, "_refresh_campaigns regates FROM CHECKPOINT")
	check(title._host_campaign_box.disabled, "and the selector goes dead with the last campaign")
	title.free()
	cache.reset()

## Why a session ended reaches the title both ways: waiting for it on open, and
## live while the title stands.
func _check_notice() -> void:
	flow._post_notice("Could not reach 10.0.0.9:7777.")
	var title = _open_title()
	check(title._status.text == "Could not reach 10.0.0.9:7777.",
		"the title shows the flow's last notice on open (%s)" % title._status.text)
	check(flow.take_notice() == "", "the title takes the notice when it shows it")
	flow._post_notice("The host left.")
	check(title._status.text == "The host left.", "a notice posted while the title stands reaches the status line")
	check(flow.take_notice() == "", "a live notice is not shown twice")
	title.free()

## What the cache remembers survives a restart, and an older cache has no host
## port at all.
func _check_cache_restart() -> void:
	cache.remember("JoinRanger", "100.64.0.12", 8123)
	cache.remember_host("HostRanger", 7790)
	var reloaded = NetCacheScript.new()
	reloaded.save_path = cache.save_path
	reloaded.load_cache()
	check(reloaded.host_port == 7790 and reloaded.port == 8123 and reloaded.address == "100.64.0.12",
		"the host port survives a restart without moving the join port")
	reloaded.free()
	var legacy_file := FileAccess.open(LEGACY_CACHE, FileAccess.WRITE)
	legacy_file.store_string('{"version":1,"player_name":"Legacy","address":"100.64.0.7","port":52140,"mode":"world"}')
	legacy_file.close()
	var legacy = NetCacheScript.new()
	legacy.save_path = LEGACY_CACHE
	legacy.load_cache()
	check(legacy.port == 52140 and legacy.host_port == 7777,
		"a version-1 cache keeps its join port and defaults the host port to 7777")
	legacy.free()
	_remove(LEGACY_CACHE)
	cache.reset()

## The four doors, pressed back to back. Every door that starts a campaign makes
## a campaign of its own, and every door that opens one binds the campaign it
## opened; the seeded campaign is checked after each press, because "a new game
## never writes over a saved one" is the whole point of the ledger.
func _check_campaign_doors() -> void:
	# NEW CAMPAIGN: a name, a new folder, and a fresh warband and purse in the
	# cages, while the campaign already saved keeps its bodies.
	_clear_ledger()
	var kept := _seed_save(true)
	warband.load_state()
	state.add_credits(700)
	flow.world_start = "town"
	var title = _open_title()
	if audio != null:
		audio.last_event = ""
	title.new_campaign_button.pressed.emit()
	title._new_name_input.text = "Second"
	title._confirm_new_campaign()
	if audio != null:
		check(audio.last_event == "menu_thud", "NEW CAMPAIGN sounds as a door (%s)" % audio.last_event)
		check(audio.music_track == "warband", "NEW CAMPAIGN hands the score to the campaign (%s)" % audio.music_track)
	check(flow.world_start == "camp", "NEW CAMPAIGN starts at the cages (%s)" % flow.world_start)
	check(warband.roster.count() == 0, "NEW CAMPAIGN begins a fresh warband (%d bodies)" % warband.roster.count())
	check(warband.gold() == int(state.STARTING_CREDITS),
		"NEW CAMPAIGN starts on the starting purse (%d)" % warband.gold())
	check(flow.warband_intent.is_empty(), "NEW CAMPAIGN is a campaign of this machine's own")
	check(slots.slots.size() == 2, "NEW CAMPAIGN writes a campaign of its own (%d rows)" % slots.slots.size())
	check(str(str(slots.summaries()[0].get("name", ""))) == "Second",
		"NEW CAMPAIGN is the newest campaign (%s)" % str(str(slots.summaries()[0].get("name", ""))))
	check(int(WarbandStateScript.peek_save(str(slots.warband_path(kept))).get("roster", 0)) == 2,
		"NEW CAMPAIGN leaves the saved campaign's warband alone")
	title.free()

	# CAMPAIGNS: the list holds both campaigns, and a row opens the one it names
	# on its checkpoint.
	flow.world_start = "camp"
	title = _open_title()
	title.campaigns_button.pressed.emit()
	var ids: Array = title.campaign_ids()
	check(ids.size() == 2, "the list holds both campaigns (%d)" % ids.size())
	check(ids.has(kept), "the older campaign is still in the list")
	if ids.has(kept):
		var row: Button = title._campaigns_list.get_child(ids.find(kept))
		if audio != null:
			audio.last_event = ""
		row.pressed.emit()
		if audio != null:
			check(audio.last_event == "menu_thud", "a campaign row sounds as a door (%s)" % audio.last_event)
		check(flow.world_start == "checkpoint", "a campaign row opens its checkpoint (%s)" % flow.world_start)
		check(warband.roster.count() == 2, "a campaign row loads its roster (%d)" % warband.roster.count())
		check(str(slots.active) == kept, "a campaign row binds the campaign it opened (%s)" % str(slots.active))
	title.free()

	# HOST GAME, NEW GAME: a fresh campaign whose socket opens on the host port.
	var port := _free_udp_port()
	cache.remember("JoinRanger", "100.64.0.12", 8123)
	cache.remember_host("HostRanger", port)
	flow.world_start = "town"
	title = _open_title()
	title._open_host()
	if audio != null:
		audio.last_event = ""
	title.host_new_button.pressed.emit()
	var intent: Dictionary = flow.warband_intent
	check(str(intent.get("mode", "")) == "host", "NEW GAME hosts (%s)" % str(intent))
	check(int(intent.get("port", 0)) == port, "NEW GAME opens the host port (%s)" % str(intent))
	check(str(intent.get("name", "")) == "HostRanger", "NEW GAME seats the host's name")
	check(str(intent.get("scene", "")) == flow.WORLD_SCENE, "NEW GAME opens the campaign world")
	check(flow.session != null, "NEW GAME creates the warband session")
	check(flow.world_start == "camp", "NEW GAME starts at the cages (%s)" % flow.world_start)
	check(warband.roster.count() == 0, "NEW GAME begins a fresh warband")
	check(not title._host_layer.visible, "hosting closes the panel")
	check(cache.host_port == port, "hosting remembers its own port")
	check(cache.port == 8123 and cache.address == "100.64.0.12", "hosting leaves the join endpoint untouched")
	check(slots.slots.size() == 3, "NEW GAME hosts in a campaign of its own (%d rows)" % slots.slots.size())
	check(str(str(slots.summaries()[0].get("name", ""))) == "HostRanger",
		"the hosted campaign is named after the host (%s)" % str(str(slots.summaries()[0].get("name", ""))))
	check(int(WarbandStateScript.peek_save(str(slots.warband_path(kept))).get("roster", 0)) == 2,
		"hosting a new game leaves the saved campaign alone")
	if audio != null:
		check(audio.last_event == "menu_thud", "NEW GAME sounds as a door")
	title.free()

	# HOST GAME, FROM CHECKPOINT: the campaign the selector names, on its bookmark.
	_clear_ledger()
	var hosted := _seed_save(true)
	flow.world_start = "camp"
	title = _open_title()
	title._open_host()
	check(not title.host_checkpoint_button.disabled, "FROM CHECKPOINT is live on the saved warband")
	title.host_checkpoint_button.pressed.emit()
	check(str(flow.warband_intent.get("mode", "")) == "host", "FROM CHECKPOINT hosts")
	check(flow.world_start == "checkpoint", "FROM CHECKPOINT opens on the checkpoint (%s)" % flow.world_start)
	check(warband.roster.count() == 2, "FROM CHECKPOINT hosts the saved roster (%d)" % warband.roster.count())
	check(str(slots.active) == hosted, "FROM CHECKPOINT binds the campaign it hosts")
	title.free()
