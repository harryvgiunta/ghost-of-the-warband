extends SceneTree
## The warband lobby, end to end on two real ENet processes.
##
## Both machines open the real title screen, fill the real lobby panel and press
## the real buttons: HOST WARBAND on one, JOIN WARBAND on the other. `GameFlow`
## carries the intent into the arena, seats a `WarbandSession` on the scene that
## fielded the bodies, and the two souls take one body each. The guest walks and
## the host sees it, a second soul asking for the host's body is refused with the
## router's own words on the guest's strip, and a guest that leaves hands its
## body back to the scene's AI.
##
## Nothing here builds a private battlefield: the whole point of the lobby is
## that the socket outlives the menu and binds to a real scene, so the real scene
## is what gets driven.

const TITLE := "res://title.tscn"
const ARENA := "res://admin_arena.tscn"
const REPORT_NAME := "WarbandLobbyReport"
const TRACE_PATH := "user://warband_lobby_guest_trace.txt"
const SoulRouterScript = preload("res://scripts/warband/soul_router.gd")

var checks := 0
var failures := 0
var flow
var warband
var state
var arena
var reports: Dictionary = {}
var child_pid := -1
var guest_peer := 0
var guest_merc := -1
var leave_requested := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_LOBBY_FAIL  ", message)

func _trace(message: String) -> void:
	var file := FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	else:
		file.seek_end()
	if file != null:
		file.store_line(message)
		file.close()

func _read_trace() -> String:
	return FileAccess.get_file_as_string(TRACE_PATH) \
		if FileAccess.file_exists(TRACE_PATH) else ""

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _clear_trace() -> void:
	_remove(TRACE_PATH)

func _wait_until(predicate: Callable, timeout: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

## The scene the flow actually changed to, with one more beat so its `_ready`
## (bodies, HUD, services) has run.
func _wait_scene(path: String, timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
		var scene := current_scene
		if scene != null and scene.scene_file_path == path:
			await create_timer(0.4).timeout
			scene = current_scene
			if scene != null and scene.scene_file_path == path:
				return scene
	return null

## Every save this test touches gets a path of its own, so a parallel worktree's
## test run and this one cannot read each other's roster, purse or cache.
func _prepare(role_name: String) -> bool:
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	if state == null or warband == null or flow == null:
		check(false, "The autoloads exist")
		return false
	state.save_path = "user://warband_lobby_%s_state.json" % role_name
	_remove(state.save_path)
	state.reset(false)
	warband.save_path = "user://warband_lobby_%s_warband.json" % role_name
	_remove(warband.save_path)
	warband.reset_state()
	var cache := root.get_node_or_null("NetCache")
	if cache != null:
		cache.save_path = "user://warband_lobby_%s_net_cache.json" % role_name
		_remove(cache.save_path)
		cache.reset()
	return true

func _cleanup() -> void:
	for role_name in ["host", "guest"]:
		_remove("user://warband_lobby_%s_state.json" % role_name)
		_remove("user://warband_lobby_%s_warband.json" % role_name)
		_remove("user://warband_lobby_%s_net_cache.json" % role_name)
	_clear_trace()

class Report:
	extends Node
	signal submitted(payload: Dictionary)
	signal walk_requested(frames: int)
	signal steal_requested(merc_id: int)
	signal leave_requested()

	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

	@rpc("authority", "call_remote", "reliable")
	func walk(frames: int) -> void:
		walk_requested.emit(frames)

	@rpc("authority", "call_remote", "reliable")
	func steal(merc_id: int) -> void:
		steal_requested.emit(merc_id)

	@rpc("authority", "call_remote", "reliable")
	func leave() -> void:
		leave_requested.emit()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--warband-lobby-guest"):
		await _guest_run()
	else:
		await _host_run()

## The title screen, filled in the way a player fills it: after the panel is up,
## so the values typed survive the cache read that `_ready` performs.
func _open_title(player_name: String, address: String, port: int) -> Node:
	var title = load(TITLE).instantiate()
	root.add_child(title)
	await process_frame
	if title.lobby == null:
		return title
	title.lobby.name_input.text = player_name
	title.lobby.address_input.text = address
	title.lobby.port_input.value = port
	return title

# --- host ------------------------------------------------------------------

func _host_run() -> void:
	_clear_trace()
	if not _prepare("host"):
		await _finish_host()
		return
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	var report := Report.new()
	report.name = REPORT_NAME
	report.submitted.connect(_store_report)
	root.add_child(report)

	var title = await _open_title("Host soul", "127.0.0.1", port)
	check(title.lobby != null, "The title screen carries the warband lobby")
	if title.lobby == null:
		await _finish_host()
		return
	check(title.lobby.host_button.text == "HOST WARBAND", "The lobby's first door is HOST WARBAND")
	check(title.lobby.join_button.text == "JOIN WARBAND", "The lobby's second door is JOIN WARBAND")
	check(int(title.lobby.port_input.value) == port, "The lobby takes the port it was given")
	check(title.start_button.text == "START NEW GAME" and title.join_button.text == "JOIN GAME",
		"The four existing doors are untouched beside the lobby")
	check(not title._load_button.disabled or title._load_button.text == "LOAD SAVED GAME",
		"The load door still explains itself")

	title.lobby.host_button.pressed.emit()
	arena = await _wait_scene(ARENA, 40.0)
	check(arena != null, "HOST WARBAND carries the flow into the battle scene")
	if arena == null:
		await _finish_host()
		return
	check(flow.session != null, "The lobby opened a real WarbandSession")
	check(String(flow.session.get_path()) == "/root/GameFlow/WarbandLink",
		"The socket lives under the flow, not the menu (%s)" % String(flow.session.get_path()))
	check(flow.session.role() == "host", "The host role survives the scene hand-off")
	check(flow.warband_intent.get("mode", "") == "host", "The intent names the mode")
	check(arena.bodies.size() == 8, "The arena fields the warband (%d)" % arena.bodies.size())
	arena.set_sparring(false)
	arena.set_choreography(false)

	var host_merc: int = arena.controller.merc_for_peer(1)
	check(host_merc > 0, "The host is inside a body after the hand-off")
	check(warband.souls.body_of(1) == host_merc, "The router agrees with the controller")
	check(_bodies_of(1) == 1, "The host's soul is inside exactly one body (%d)" % _bodies_of(1))
	check(flow.banner != null and String(flow.banner.state_text).contains("HOSTING UDP %d" % port),
		"The lobby strip names the port it is hosting on (%s)"
			% (String(flow.banner.state_text) if flow.banner != null else ""))

	var child_args := PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", get_script().resource_path, "--",
		"--warband-lobby-guest", str(port), str(host_merc)])
	child_pid = OS.create_process(OS.get_executable_path(), child_args)
	check(child_pid > 0, "The guest process starts")
	var joined := await _wait_until(func(): return flow.session.peer_count() == 2, 45.0)
	check(joined, "The guest's ENet peer reaches the host's session")
	if not joined:
		print("GUEST_TRACE:\n", _read_trace())
		await _finish_host()
		return
	guest_peer = _client_peer()
	check(guest_peer > 1, "The host sees the guest's peer id")
	check(String(flow.banner.state_text).contains("2 souls"),
		"The lobby strip counts the second soul (%s)" % String(flow.banner.state_text))

	var seated := await _wait_until(func(): return reports.has("seat"), 40.0)
	check(seated, "The guest reports the body it took")
	if not seated:
		print("GUEST_TRACE:\n", _read_trace())
		await _finish_host()
		return
	var seat: Dictionary = reports["seat"]
	guest_merc = int(seat.get("merc", -1))
	check(guest_merc > 0, "The guest is inside a body (%d)" % guest_merc)
	check(guest_merc != host_merc, "The two souls are inside two different bodies")
	check(int(seat.get("peer", 0)) == guest_peer, "The guest knows its own peer id")
	check(warband.souls.occupied_by(guest_merc) == guest_peer,
		"The router records the guest inside its body")
	check(arena.controller.merc_for_peer(guest_peer) == guest_merc,
		"The host's controller wires the guest's body")
	check(arena.controller.merc_for_peer(1) == host_merc, "The host keeps its own body")
	check(_bodies_of(guest_peer) == 1,
		"The guest's soul is inside exactly one body (%d)" % _bodies_of(guest_peer))
	check(bool(seat.get("predicting", false)),
		"The guest's body is a replica, not a second authority")
	check(flow.banner != null and String(flow.banner.state_text).contains("2 souls"),
		"The strip keeps counting both souls")

	# The guest's own keys, on the host's copy of the guest's body.
	var guest_body = arena.controller.body_of(guest_merc)
	check(guest_body != null, "The host holds the guest's body")
	var before: Vector3 = guest_body.global_position
	var sent := Time.get_ticks_msec()
	report.walk.rpc_id(guest_peer, 45)
	# First: motion at all. A guest whose intents never cross the wire only moves
	# on its own screen and is snapped back by every snapshot.
	var reached := await _wait_until(
		func(): return is_instance_valid(guest_body) \
			and guest_body.global_position.distance_to(before) > 0.25, 5.0)
	var reached_ms := Time.get_ticks_msec() - sent
	check(reached, "The host sees the guest's body move")
	check(reached and reached_ms <= 1500,
		"The guest's first step reaches the host within 1.5 s (%d ms)" % reached_ms)
	var motion_seen := await _wait_until(func(): return reports.has("motion"), 20.0)
	check(motion_seen, "The guest reports its own walk")
	var walk := 0.0
	if motion_seen:
		var motion: Dictionary = reports["motion"]
		check(int(motion.get("merc", -1)) == guest_merc, "The guest moved its own body")
		check(float(motion.get("predicted", 0.0)) > 0.5,
			"The guest's body walked on its own screen (%s m)" % str(motion.get("predicted")))
		check(int(motion.get("first_move", 99)) <= 2,
			"The guest's body moves on the frame its key went down")
		check(float(motion.get("worst_step", 99.0)) < 0.4,
			"The guest's prediction never jumps (%s)" % str(motion.get("worst_step")))
		walk = float(motion.get("predicted", 0.0))
	# The host's copy keeps taking frames for a beat after the key goes up, so the
	# distance is read once both machines are at rest: the number is the walk, not
	# the moment a threshold was crossed.
	var settle_deadline := Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < settle_deadline:
		await physics_frame
	var walked: float = guest_body.global_position.distance_to(before) \
		if is_instance_valid(guest_body) else 0.0
	check(walked > 1.0, "The guest's whole walk reaches the host (%s m of %s m)"
		% [walked, walk])

	# A second soul asking for an occupied body: the router's reason comes back.
	report.steal.rpc_id(guest_peer, host_merc)
	var refused := await _wait_until(func(): return reports.has("refusal"), 20.0)
	check(refused, "The guest's refused request comes back to it")
	if reports.has("refusal"):
		var refusal: Dictionary = reports["refusal"]
		var reason := str(refusal.get("reason", ""))
		check(reason == SoulRouterScript.REASON_OCCUPIED,
			"The guest hears the router's own reason (%s)" % reason)
		check(String(refusal.get("reason_line", "")).contains(SoulRouterScript.REASON_OCCUPIED),
			"The reason is on the guest's strip, not just in a log (%s)"
				% String(refusal.get("reason_line", "")))
		check(int(refusal.get("own_merc", -1)) == guest_merc,
			"The refused guest stays in its own body")
	check(arena.controller.merc_for_peer(1) == host_merc, "The refused body stays with its owner")
	check(warband.souls.occupied_by(host_merc) == 1, "The router keeps the host's body")
	check(_bodies_of(guest_peer) == 1, "The refused guest did not gain a second body")

	# A leaving peer hands its body back to the scene.
	report.leave.rpc_id(guest_peer)
	var left := await _wait_until(func(): return flow.session.peer_count() == 1, 30.0)
	check(left, "The host sees the guest leave")
	check(not flow.session.connected_peers().has(guest_peer),
		"The departed peer is gone from the session")
	check(arena.controller.body_for_peer(guest_peer) == null,
		"The departed soul has no body on the host")
	check(warband.souls.occupied_by(guest_merc) == 0, "The router frees the departed body")
	var freed = arena.controller.body_of(guest_merc)
	check(freed != null, "The departed body stays on the field")
	check(freed != null and bool(freed.is_bot), "The departed body falls back to its own AI")
	check(flow.session.role() == "host", "The host keeps hosting after the guest leaves")
	check(arena.controller.merc_for_peer(1) == host_merc, "The host keeps its own body")
	check(String(flow.banner.state_text).contains("1 soul"),
		"The strip goes back to one soul (%s)" % String(flow.banner.state_text))
	await _finish_host()

func _bodies_of(peer_id: int) -> int:
	var count := 0
	if arena == null:
		return count
	for body in arena.controller.bodies():
		if is_instance_valid(body) and int(body.peer_id) == peer_id:
			count += 1
	return count

func _client_peer() -> int:
	for peer_id in flow.session.connected_peers():
		if peer_id != 1:
			return peer_id
	return 0

func _store_report(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	if not kind.is_empty():
		reports[kind] = payload
	if int(payload.get("failures", 0)) > 0:
		check(false, "The guest reported its own failure: %s" % str(payload))

func _finish_host() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	if flow != null:
		flow.leave_warband()
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	_cleanup()
	print("WARBAND_LOBBY_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- guest -----------------------------------------------------------------

func _guest_run() -> void:
	_clear_trace()
	if not _prepare("guest"):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var index := args.find("--warband-lobby-guest")
	var port := int(args[index + 1])
	var host_merc := int(args[index + 2]) if index + 2 < args.size() else -1
	var report := Report.new()
	report.name = REPORT_NAME
	root.add_child(report)
	report.walk_requested.connect(_walk_and_report)
	report.steal_requested.connect(_steal_and_report)
	report.leave_requested.connect(_leave_and_report)

	var title = await _open_title("Guest soul", "127.0.0.1", port)
	check(title.lobby != null, "The guest's title screen carries the lobby")
	if title.lobby == null:
		_submit({"kind": "error", "detail": "no lobby panel"})
		await _finish(1)
		return
	_trace("title ready, joining udp %d" % port)
	title.lobby.join_button.pressed.emit()
	arena = await _wait_scene(ARENA, 40.0)
	_trace("arena=%s" % (arena != null))
	if arena == null:
		_submit({"kind": "error", "detail": "the join never reached the battle scene"})
		await _finish(1)
		return
	check(flow.session != null and flow.session.role() == "client",
		"The guest keeps the client role after the hand-off")
	check(String(flow.session.get_path()) == "/root/GameFlow/WarbandLink",
		"The guest mounts the session at the host's path")
	arena.set_sparring(false)
	arena.set_choreography(false)

	var seated := await _wait_until(func(): return _own_merc() > 0, 40.0)
	_trace("seated=%s peer=%d merc=%d" % [seated, _own_peer(), _own_merc()])
	if not seated:
		_submit({"kind": "error", "detail": "the guest never took a body"})
		await _finish(1)
		return
	var own_body = arena.controller.body_of(_own_merc())
	check(own_body != null and bool(own_body.predicting),
		"The guest predicts its own body instead of waiting for it")
	check(int(flow.banner.state_text.length()) > 0,
		"The guest's strip reports the battle (%s)" % String(flow.banner.state_text))
	_submit({"kind": "seat", "peer": _own_peer(), "merc": _own_merc(),
		"predicting": bool(own_body.predicting) if own_body != null else false,
		"banner": String(flow.banner.state_text),
		"host_merc": host_merc})

	var held := await _wait_until(func(): return leave_requested, 90.0)
	if not held:
		_submit({"kind": "error", "detail": "the host never released the guest"})
	await _finish(0 if held else 1)

func _own_peer() -> int:
	var id := root.multiplayer.get_unique_id()
	return id if id > 0 else 1

func _own_merc() -> int:
	if arena == null or arena.controller == null:
		return -1
	return int(arena.controller.merc_for_peer(_own_peer()))

func _walk_and_report(frames: int) -> void:
	var body = arena.controller.active_body()
	if body == null:
		_submit({"kind": "error", "detail": "no body to walk"})
		return
	var origin: Vector3 = body.global_position
	var previous := origin
	var first := -1
	var worst := 0.0
	_press(KEY_D, true)
	for index in frames:
		await physics_frame
		var now: Vector3 = body.global_position
		if first < 0 and now.distance_to(origin) > 0.008:
			first = index
		worst = maxf(worst, now.distance_to(previous))
		previous = now
	_press(KEY_D, false)
	var stop: Vector3 = body.global_position
	# Let the last frames round-trip so the pose reported here is one both
	# machines have settled on, not a local guess.
	var settle := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < settle:
		await process_frame
	_submit({"kind": "motion", "peer": _own_peer(), "merc": _own_merc(),
		"predicted": stop.distance_to(origin), "first_move": first,
		"worst_step": worst, "predicting": bool(body.predicting)})

func _steal_and_report(merc_id: int) -> void:
	var own_before := _own_merc()
	var asked: Dictionary = flow.warband_enter_body(merc_id)
	_trace("steal asked=%s" % [asked])
	var landed := await _wait_until(
		func(): return flow.banner != null and not String(flow.banner.reason).is_empty(), 10.0)
	_submit({"kind": "refusal", "ok": landed,
		"asked_ok": bool(asked.get("ok", false)),
		"pending": bool(asked.get("pending", false)),
		"reason": String(flow.banner.reason) if flow.banner != null else "",
		"reason_line": flow.banner.reason_line() if flow.banner != null else "",
		"own_merc": _own_merc(), "own_merc_before": own_before, "own_peer": _own_peer()})

func _leave_and_report() -> void:
	flow.leave_warband()
	_submit({"kind": "left", "peer": _own_peer()})
	leave_requested = true

func _press(keycode: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _submit(payload: Dictionary) -> void:
	var report := root.get_node_or_null(REPORT_NAME)
	if report == null:
		return
	payload["checks"] = checks
	payload["failures"] = failures
	report.submit.rpc_id(1, payload)

func _finish(code: int) -> void:
	if flow != null:
		flow.leave_warband()
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	_cleanup()
	quit(code)
