extends SceneTree
## The warband lobby's mode row - the default campaign co-op and the arena bout
## it can still be switched to - and the title door that opens it.
##
## No socket and no scene hand-off: this test only reads what the panel would
## send. The lobby is instantiated beside the real `GameFlow`, the selector is
## driven the way a player drives it, and `request_payload()` is read before any
## press. A live intent is the thing the serial ENet regression already proves,
## so keeping it out of this test is what lets it finish in a second.
##
## The default is CAMPAIGN (CO-OP): the warband is the game, so a player who
## presses HOST WARBAND without touching the mode row must get the co-op run and
## the world scene in both directions. The arena bout stays the selectable first
## option, and this test switches to it explicitly to prove that switching it
## back and forth keeps naming the right scene.

const LobbyScript = preload("res://scripts/warband/warband_lobby.gd")
const TITLE_SCENE := "res://title.tscn"
const ARENA_SCENE := "res://admin_arena.tscn"
const CAMPAIGN_SCENE := "res://scenes/warband_world.tscn"

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_LOBBY_CAMPAIGN_FAIL  ", message)

func run() -> void:
	var flow := root.get_node_or_null("GameFlow")
	check(flow != null, "The real GameFlow autoload exists")
	var intent_before: Dictionary = flow.warband_intent.duplicate() if flow != null else {}
	var session_before = flow.session if flow != null else null

	var lobby = LobbyScript.new()
	root.add_child(lobby)
	await process_frame

	# --- the mode choice ---------------------------------------------------
	check(lobby.mode_select != null, "The lobby carries a mode selector")
	check(lobby.selected_mode() == "campaign", "The lobby defaults to campaign co-op (%s)"
		% lobby.selected_mode())
	check(lobby.mode_select.item_count == 2, "The selector offers two bouts (%d)"
		% lobby.mode_select.item_count)
	check(str(lobby.mode_select.get_item_metadata(0)) == "arena"
		and str(lobby.mode_select.get_item_metadata(1)) == "campaign",
		"The arena is the first option and campaign the second")
	check(lobby.mode_select.get_item_text(0).to_lower().contains("arena")
		and lobby.mode_select.get_item_text(1).to_lower().contains("campaign"),
		"Both options are named in words a player reads")
	check(lobby.mode_description != null
		and lobby.mode_description.text.to_lower().contains("arena")
		and lobby.mode_description.text.to_lower().contains("campaign"),
		"The selector describes both modes in one line each (%s)"
		% (lobby.mode_description.text if lobby.mode_description != null else ""))

	# --- what the fields say ----------------------------------------------
	lobby.name_input.text = "Campaign Soul"
	lobby.address_input.text = "10.20.30.40"
	lobby.port_input.value = 7788
	check(lobby.player_name() == "Campaign Soul", "The lobby takes the typed name")
	check(lobby.address() == "10.20.30.40", "The lobby takes the typed address")
	check(lobby.port() == 7788, "The lobby takes the typed port")

	# --- the campaign payload, host and join ------------------------------
	var host_payload: Dictionary = lobby.request_payload()
	check(host_payload.size() == 6,
		"request_payload names exactly the six intent fields (%d)" % host_payload.size())
	check(str(host_payload.get("mode", "")) == "host", "Hosting is the default action")
	check(str(host_payload.get("mode_kind", "")) == "campaign",
		"The default payload is campaign co-op (%s)" % str(host_payload.get("mode_kind", "")))
	check(str(host_payload.get("scene", "")) == CAMPAIGN_SCENE,
		"The campaign payload opens the campaign world (%s)" % str(host_payload.get("scene", "")))
	check(str(host_payload.get("address", "")) == "127.0.0.1",
		"A host payload points at itself (%s)" % str(host_payload.get("address", "")))
	check(int(host_payload.get("port", 0)) == 7788, "The host payload carries the port")
	check(str(host_payload.get("name", "")) == "Campaign Soul", "The host payload carries the name")

	var join_payload: Dictionary = lobby.request_payload("join")
	check(str(join_payload.get("mode", "")) == "join", "Asking for join builds a join payload")
	check(str(join_payload.get("mode_kind", "")) == "campaign",
		"A default join stays in the campaign")
	check(str(join_payload.get("scene", "")) == CAMPAIGN_SCENE,
		"A campaign join asks for the campaign world")
	check(str(join_payload.get("address", "")) == "10.20.30.40",
		"A join payload points at the host typed in the field (%s)"
			% str(join_payload.get("address", "")))

	# --- switching to the arena -------------------------------------------
	# The arena is still index 0 and still fully selectable; it just stopped
	# being the default, so a player who wants the bout says so.
	lobby.mode_select.select(0)
	lobby.mode_select.item_selected.emit(0)
	check(lobby.selected_mode() == "arena", "The selector switches to the arena (%s)"
		% lobby.selected_mode())

	var arena_host: Dictionary = lobby.request_payload("host")
	check(str(arena_host.get("mode_kind", "")) == "arena",
		"The arena payload names the arena (%s)" % str(arena_host.get("mode_kind", "")))
	check(str(arena_host.get("scene", "")) == ARENA_SCENE,
		"Arena hosting opens the arena scene (%s)" % str(arena_host.get("scene", "")))
	var arena_join: Dictionary = lobby.request_payload("join")
	check(str(arena_join.get("mode", "")) == "join"
		and str(arena_join.get("mode_kind", "")) == "arena",
		"Arena join is its own payload")
	check(str(arena_join.get("scene", "")) == ARENA_SCENE,
		"Both arena peers ask for the same scene (%s)" % str(arena_join.get("scene", "")))

	# --- back to the campaign ---------------------------------------------
	var campaign_index := -1
	for index in lobby.mode_select.item_count:
		if str(lobby.mode_select.get_item_metadata(index)) == "campaign":
			campaign_index = index
	check(campaign_index >= 0, "The campaign option is present")
	lobby.mode_select.select(campaign_index)
	lobby.mode_select.item_selected.emit(campaign_index)
	check(lobby.selected_mode() == "campaign", "The campaign option is still reachable (%s)"
		% lobby.selected_mode())
	check(str(lobby.request_payload("host").get("scene", "")) == CAMPAIGN_SCENE,
		"Switching back restores the campaign scene")
	check(str(lobby.request_payload("join").get("scene", "")) == CAMPAIGN_SCENE,
		"Switching back restores the campaign join scene")

	# --- requested, never sent --------------------------------------------
	check(flow != null and flow.session == session_before,
		"Reading a payload opens no socket")
	check(flow != null and str(flow.warband_intent) == str(intent_before),
		"Reading a payload leaves the flow's intent alone")

	# --- the cache still feeds the fields ---------------------------------
	var cache := root.get_node_or_null("NetCache")
	if cache != null:
		var saved_name := str(cache.player_name)
		var saved_address := str(cache.address)
		var saved_port := int(cache.port)
		cache.player_name = "Cached Soul"
		cache.address = "192.168.1.55"
		cache.port = 7791
		lobby.sync_from_cache()
		check(lobby.name_input.text == "Cached Soul", "The lobby reads the cached name")
		check(lobby.address_input.text == "192.168.1.55", "The lobby reads the cached address")
		check(int(lobby.port_input.value) == 7791, "The lobby reads the cached port")
		# Presentation only: a cache read must not move the mode the player chose.
		check(lobby.selected_mode() == "campaign", "A cache read leaves the mode alone")
		cache.player_name = saved_name
		cache.address = saved_address
		cache.port = saved_port

	# --- the title door ----------------------------------------------------
	var title = load(TITLE_SCENE).instantiate()
	root.add_child(title)
	await process_frame
	var doors := {
		"NEW CAMPAIGN": title.start_button,
		"CONTINUE": title._load_button,
		"HOST OPEN WORLD": title.host_world_button,
		"JOIN GAME": title.join_button,
		"GHOST OF THE WARBAND": title.warband_button,
		"RESUME WARBAND": title.warband_resume_button,
		"WARBAND LOBBY": title._lobby_button,
	}
	for expected in doors:
		var door = doors[expected]
		check(door != null and door.text == expected,
			"The title still carries the %s door (%s)"
				% [expected, door.text if door != null else "missing"])
	check(title._lobby_button.tooltip_text.to_lower().contains("campaign")
		and title._lobby_button.tooltip_text.to_lower().contains("arena"),
		"The lobby door names both destinations (%s)" % title._lobby_button.tooltip_text)
	check(title.lobby != null and title.lobby.mode_select != null,
		"The title's lobby is the one with the mode row")
	title._toggle_lobby()
	check(title._lobby_layer.visible, "The lobby door still opens the panel")
	check(title._status.text.to_lower().contains("campaign")
		and title._status.text.to_lower().contains("arena"),
		"Opening the panel says what its two modes are (%s)" % title._status.text)
	title._toggle_lobby()
	check(not title._lobby_layer.visible, "The lobby door still closes the panel")

	title.queue_free()
	lobby.queue_free()
	await process_frame
	print("WARBAND_LOBBY_CAMPAIGN_REGRESSION checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)
