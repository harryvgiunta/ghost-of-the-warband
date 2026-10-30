extends SceneTree
## Main menu: exactly four doors - NEW CAMPAIGN, RESUME CAMPAIGN, JOIN GAME,
## HOST GAME - the resume and checkpoint gates on a real warband save, the join
## form and host panel reading the network cache every time they open, and what
## each door hands to `GameFlow`.
##
## The door presses come last and nothing awaits a frame after the first one: a
## press queues the flow's scene change, and this test checks what the flow was
## told, not the world it opens.

const NetCacheScript = preload("res://scripts/net_cache.gd")
const STATE_SAVE := "user://title_menu_state.json"
const WARBAND_SAVE := "user://title_menu_warband.json"
const LEGACY_CACHE := "user://net_cache_legacy.json"
const CHECKPOINT_LABEL := "THE CAMP IS BEHIND YOU"
const DOOR_TEXTS := ["NEW CAMPAIGN", "RESUME CAMPAIGN", "JOIN GAME", "HOST GAME"]

var state
var warband
var flow
var cache
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

func _open_title():
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	return title

## A saved warband with bodies, and a trail bookmark when asked for one.
func _seed_save(with_checkpoint: bool) -> void:
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
	audio = root.get_node_or_null("Audio")
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	state.save_path = STATE_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
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
		check(doors[0] == title.new_campaign_button and doors[1] == title.resume_button
			and doors[2] == title.join_button and doors[3] == title.host_button,
			"the four door members are the four buttons in the column")
	check(title.new_campaign_button.theme_type_variation == "PrimaryButton",
		"NEW CAMPAIGN is the primary door")
	for door in doors:
		check(door.visible, "%s is visible" % door.text)

	# No save: RESUME is dead, and pressing it anyway explains itself without
	# handing the score over or moving the flow.
	check(title.resume_button.disabled, "RESUME is disabled without a warband save")
	if audio != null:
		audio.last_event = ""
	flow.world_start = "town"
	title._resume_campaign()
	check(title._status.text.contains("No campaign saved"), "a refused resume says why (%s)" % title._status.text)
	check(flow.world_start == "town", "a refused resume leaves the flow alone")
	if audio != null:
		check(audio.last_event != "menu_thud", "a refused resume does not sound as a door")

	# A save written while the title stands is seen on the next refresh, and
	# the tooltip names the bookmark the save would open on.
	_seed_save(true)
	title._refresh_resume()
	check(not title.resume_button.disabled, "RESUME is enabled once a warband save exists")
	check(title.resume_button.tooltip_text.contains(CHECKPOINT_LABEL),
		"RESUME names the saved checkpoint (%s)" % title.resume_button.tooltip_text)
	title.free()

	# A fresh title reads the save too.
	title = _open_title()
	check(not title.resume_button.disabled, "a new title enables RESUME on an existing save")
	_remove(WARBAND_SAVE)
	title._refresh_resume()
	check(title.resume_button.disabled, "RESUME goes dead again when the save is gone")
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
	check(title.host_checkpoint_button.disabled, "FROM CHECKPOINT is disabled without a warband save")
	check(title._host_checkpoint_label.text == "No campaign saved yet.",
		"the host panel says there is nothing to host from (%s)" % title._host_checkpoint_label.text)
	title._close_host()

	# A roster with no bookmark opens in Hearthstead; a bookmark is named.
	_seed_save(false)
	cache.remember_host("HostRanger", 7799)
	title._open_host()
	check(int(title._host_port_input.value) == 7799, "the host panel rereads the host port every time it opens")
	check(not title.host_checkpoint_button.disabled, "FROM CHECKPOINT is enabled on a warband save")
	check(title._host_checkpoint_label.text.contains("saved warband - opens in Hearthstead"),
		"a save without a bookmark opens in Hearthstead (%s)" % title._host_checkpoint_label.text)
	title._close_host()
	_seed_save(true)
	title._open_host()
	check(title._host_checkpoint_label.text.contains(CHECKPOINT_LABEL),
		"FROM CHECKPOINT names the bookmark (%s)" % title._host_checkpoint_label.text)
	_remove(WARBAND_SAVE)
	title._refresh_resume()
	check(title.host_checkpoint_button.disabled, "_refresh_resume regates FROM CHECKPOINT")
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

## The four doors that open a campaign, pressed back to back.
func _check_campaign_doors() -> void:
	# NEW CAMPAIGN: a fresh warband and purse in the cages, whatever was saved.
	_seed_save(true)
	warband.load_state()
	state.add_credits(700)
	flow.world_start = "town"
	var title = _open_title()
	if audio != null:
		audio.last_event = ""
	title.new_campaign_button.pressed.emit()
	if audio != null:
		check(audio.last_event == "menu_thud", "NEW CAMPAIGN sounds as a door (%s)" % audio.last_event)
		check(audio.music_track == "warband", "NEW CAMPAIGN hands the score to the campaign (%s)" % audio.music_track)
	check(flow.world_start == "camp", "NEW CAMPAIGN starts at the cages (%s)" % flow.world_start)
	check(warband.roster.count() == 0, "NEW CAMPAIGN begins a fresh warband (%d bodies)" % warband.roster.count())
	check(warband.gold() == int(state.STARTING_CREDITS),
		"NEW CAMPAIGN starts on the starting purse (%d)" % warband.gold())
	check(flow.warband_intent.is_empty(), "NEW CAMPAIGN is a campaign of this machine's own")
	title.free()

	# RESUME CAMPAIGN: the saved roster on its checkpoint.
	_seed_save(true)
	flow.world_start = "camp"
	title = _open_title()
	if audio != null:
		audio.last_event = ""
	title.resume_button.pressed.emit()
	if audio != null:
		check(audio.last_event == "menu_thud", "RESUME sounds as a door (%s)" % audio.last_event)
	check(flow.world_start == "checkpoint", "RESUME opens on the checkpoint (%s)" % flow.world_start)
	check(warband.roster.count() == 2, "RESUME loads the saved roster (%d)" % warband.roster.count())
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
	if audio != null:
		check(audio.last_event == "menu_thud", "NEW GAME sounds as a door")
	title.free()

	# HOST GAME, FROM CHECKPOINT: the saved warband on its bookmark.
	_seed_save(true)
	flow.world_start = "camp"
	title = _open_title()
	title._open_host()
	check(not title.host_checkpoint_button.disabled, "FROM CHECKPOINT is live on the saved warband")
	title.host_checkpoint_button.pressed.emit()
	check(str(flow.warband_intent.get("mode", "")) == "host", "FROM CHECKPOINT hosts")
	check(flow.world_start == "checkpoint", "FROM CHECKPOINT opens on the checkpoint (%s)" % flow.world_start)
	check(warband.roster.count() == 2, "FROM CHECKPOINT hosts the saved roster (%d)" % warband.roster.count())
	title.free()
