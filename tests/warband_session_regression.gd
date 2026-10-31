extends SceneTree
## Two real ENet processes: a host opens a warband session over eight real
## `ArenaActor` bodies, a client joins it, and possession, prediction,
## replication and the departure all have to agree on both peers.
##
## The field is built in code (flat ground, one `PossessionController`) so the
## only thing under test is `WarbandSession` and the libraries it wires.

const TRACE_PATH := "user://warband_session_client_trace.txt"
const REPORT_NAME := "WarbandSessionReport"
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const ControllerScript = preload("res://scripts/warband/possession_controller.gd")
const SessionScript = preload("res://scripts/warband/warband_session.gd")

var failures := 0
var checks := 0
var warband
var battlefield: Node3D
var controller: ControllerScript
var session: SessionScript
var bodies: Array = []
var reports: Dictionary = {}
var child_pid := -1
var refusal_reason := ""
var leave_requested := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_SESSION_FAIL  ", message)

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
	return FileAccess.get_file_as_string(TRACE_PATH) if FileAccess.file_exists(TRACE_PATH) else ""

func _clear_trace() -> void:
	if FileAccess.file_exists(TRACE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE_PATH))

func _wait_until(predicate: Callable, timeout: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

class Report:
	extends Node
	signal submitted(payload: Dictionary)
	signal walk_requested(frames: int)
	signal probe_requested(merc_id: int)
	signal leave_requested()

	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

	@rpc("authority", "call_remote", "reliable")
	func walk(frames: int) -> void:
		walk_requested.emit(frames)

	@rpc("authority", "call_remote", "reliable")
	func probe(merc_id: int) -> void:
		probe_requested.emit(merc_id)

	@rpc("authority", "call_remote", "reliable")
	func leave() -> void:
		leave_requested.emit()

# --- the field -------------------------------------------------------------

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--warband-client"):
		await _client_run()
	else:
		await _host_run()

## A flat yard and one real squad: no `ArenaWorld`, no scene file, so nothing
## but the session can put a body anywhere.
func _build_field(authoritative: bool) -> bool:
	warband = root.get_node_or_null("Warband")
	if warband == null:
		check(false, "The Warband autoload exists")
		return false
	warband.reset_state()
	_seed_warband()
	battlefield = Node3D.new()
	battlefield.name = "Battlefield"
	root.add_child(battlefield)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.6, 80.0)
	shape.shape = box
	shape.position.y = -0.3
	ground.add_child(shape)
	battlefield.add_child(ground)
	var camera := Camera3D.new()
	camera.name = "FieldCamera"
	camera.current = true
	camera.position = Vector3(0.0, 12.0, 26.0)
	battlefield.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	controller = ControllerScript.new()
	controller.name = "Soul"
	battlefield.add_child(controller)
	controller.setup(warband, camera, battlefield)
	bodies = controller.spawn_mercenaries(_posts(), authoritative)
	session = SessionScript.new()
	session.name = "WarbandSession"
	battlefield.add_child(session)
	session.setup(controller, warband)
	return true

func _seed_warband() -> void:
	var lineup := ["Aldous", "Brine", "Cael", "Dorn", "Edda", "Fenwick", "Grist", "Hale"]
	for index in lineup.size():
		var merc_id: int = warband.add_mercenary(str(lineup[index]))
		warband.roster.equip(merc_id, "main", "sword_short")
		for slot in ArmorData.SLOTS:
			var armor_id := "armor_leather_%s" % slot
			if State.ITEMS.has(armor_id):
				warband.roster.equip(merc_id, slot, armor_id)

func _posts() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for index in 8:
		points.append(Vector3(-12.0 + 8.0 * float(index % 4), 0.0, -8.0 + 16.0 * float(index / 4)))
	return points

func _merc_at(index: int) -> int:
	var ids: Array[int] = warband.roster.ids()
	return ids[index] if index < ids.size() else -1

func _client_peer() -> int:
	for peer_id in session.connected_peers():
		if peer_id != 1:
			return peer_id
	return 0

# --- host ------------------------------------------------------------------

func _host_run() -> void:
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	if not _build_field(true):
		await _print_and_quit()
		return
	var report := Report.new()
	report.name = REPORT_NAME
	report.submitted.connect(_store_report)
	root.add_child(report)
	check(session.host(port, "Host soul"), "The host opens a warband session")
	check(session.role() == "host", "The host reports the host role")
	check(session.peer_count() == 1, "The host starts alone")
	var host_merc := _merc_at(0)
	var host_take := session.request_body(host_merc)
	check(bool(host_take.get("ok", false)), "The host enters its own body")
	check(controller.merc_for_peer(1) == host_merc, "The host's state shows its own body")
	check(int(session.ownership().get(1, 0)) == host_merc, "The host's map names its own body")
	var host_body = controller.body_of(host_merc)
	check(host_body != null and int(host_body.peer_id) == 1,
		"The host's body belongs to the host soul")

	var client_merc := _merc_at(1)
	var child_args := PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", get_script().resource_path, "--",
		"--warband-client", str(port), str(client_merc), str(host_merc)])
	child_pid = OS.create_process(OS.get_executable_path(), child_args)
	check(child_pid > 0, "The client process starts")
	var joined := await _wait_until(func(): return session.peer_count() == 2, 20.0)
	check(joined, "A real ENet client joins the warband session")
	if not joined:
		print("CLIENT_TRACE:\n", _read_trace())
		await _print_and_quit()
		return
	var client_peer := _client_peer()
	check(client_peer > 1, "The host sees the client's peer id")
	var seated := await _wait_until(
		func(): return int(session.ownership().get(client_peer, 0)) == client_merc, 10.0)
	check(seated, "The host's map shows the client's body owned by the client")
	if not seated:
		print("CLIENT_TRACE:\n", _read_trace())
		await _print_and_quit()
		return
	check(controller.merc_for_peer(client_peer) == client_merc,
		"The host's controller wires the client's body")
	check(warband.souls.occupied_by(client_merc) == client_peer,
		"The router records the client inside its own body")
	check(controller.merc_for_peer(1) == host_merc, "The host keeps a different body")

	var refusals: Array[String] = []
	session.transfer_refused.connect(
		func(_merc_id: int, reason: String): refusals.append(reason))
	var stolen := session.request_body(client_merc)
	check(not bool(stolen.get("ok", false)), "The host cannot take the client's body")
	check(str(stolen.get("reason", "")) != "", "The host's refusal names a reason")
	check(refusals.size() == 1, "The host's own refusal reaches its own soul")
	check(controller.merc_for_peer(1) == host_merc, "The refused host soul stays in its body")
	check(warband.souls.occupied_by(client_merc) == client_peer,
		"The refused body stays with its owner")

	var client_body = controller.body_of(client_merc)
	var before: Vector3 = client_body.global_position
	var sent := Time.get_ticks_msec()
	report.walk.rpc_id(client_peer, 45)
	var moved_ms := -1
	var walk_deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < walk_deadline:
		if is_instance_valid(client_body) and client_body.global_position.distance_to(before) > 0.5:
			moved_ms = Time.get_ticks_msec() - sent
			break
		await physics_frame
	check(moved_ms >= 0, "The host sees the client's body walk")
	check(moved_ms >= 0 and moved_ms <= 500,
		"The client's walk reaches the host within 500 ms (%d ms)" % moved_ms)
	var walked: float = client_body.global_position.distance_to(before)
	check(walked > 0.5, "The client's body really moved on the host (%s m)" % walked)

	var motion_seen := await _wait_until(
		func(): return reports.has("motion") or reports.has("error"), 15.0)
	check(motion_seen, "The client reports its predicted walk")
	if reports.has("error"):
		check(false, "Client reported an error: " + str(reports["error"]))
		print("CLIENT_TRACE:\n", _read_trace())
	# The host's copy may still be draining the frames the client already
	# simulated; compare the two poses once both bodies are actually at rest.
	var settle := Time.get_ticks_msec() + 1500
	var last: Vector3 = client_body.global_position
	var still := 0
	while Time.get_ticks_msec() < settle and still < 6:
		await physics_frame
		if client_body.global_position.distance_to(last) < 0.0025:
			still += 1
		else:
			still = 0
		last = client_body.global_position
	if reports.has("motion"):
		_check_motion(reports["motion"], client_peer, client_merc)

	var spare_merc := _merc_at(2)
	var spare = controller.body_of(spare_merc)
	spare.enter_downed(int(controller.body_of(host_merc).slot))
	report.probe.rpc_id(client_peer, spare_merc)
	var probe_seen := await _wait_until(func(): return reports.has("probe"), 10.0)
	check(probe_seen, "The client answers the downed probe")
	if reports.has("probe"):
		var probe_data: Dictionary = reports["probe"]
		check(int(probe_data.get("merc", -1)) == spare_merc, "The probed body is the downed one")
		check(bool(probe_data.get("downed", false)),
			"A body downed on the host reaches the client as downed")
		check(float(probe_data.get("health", 1.0)) <= 0.0,
			"The replicated downed body carries the host's zero health")
		check(int(probe_data.get("failures", 1)) == 0, "The client's own checks all pass")

	report.leave.rpc_id(client_peer)
	var left := await _wait_until(func(): return session.peer_count() == 1, 15.0)
	check(left, "The host sees the client leave")
	check(not session.connected_peers().has(client_peer), "The departed peer is gone from the session")
	check(controller.body_for_peer(client_peer) == null, "The departed soul has no body on the host")
	check(warband.souls.occupied_by(client_merc) == 0, "The router frees the departed body")
	var freed = controller.body_of(client_merc)
	check(freed != null, "The departed body stays on the field")
	check(session.role() == "host", "The host keeps hosting after the client leaves")
	check(controller.merc_for_peer(1) == host_merc, "The host keeps its own body")
	check(controller.body_of(host_merc) != null and controller.body_of(host_merc).alive,
		"The host keeps running")
	await _print_and_quit()

func _check_motion(data: Dictionary, client_peer: int, client_merc: int) -> void:
	check(int(data.get("peers", -1)) == session.peer_count(),
		"Both peers count the same souls (%s vs %s)" % [data.get("peers"), session.peer_count()])
	check(int(data.get("own_peer", 0)) == client_peer, "The client knows its own peer id")
	check(int(data.get("own_merc", -1)) == client_merc,
		"The client's own body is the one it asked for")
	check(int(data.get("host_view", -1)) == client_peer,
		"The client's own body is owned by the client")
	check(bool(data.get("predicting", false)), "The client predicts its body instead of waiting for it")
	check(int(data.get("first_move", 99)) <= 2,
		"The client's body moves on the frame its key went down")
	check(float(data.get("predicted", 0.0)) > 0.5, "The predicted body really walked")
	check(float(data.get("worst_step", 99.0)) < 0.4,
		"The prediction never jumps (%s)" % str(data.get("worst_step")))
	var own_pos: Vector3 = data.get("own_pos", Vector3.ZERO)
	var host_pos: Vector3 = controller.body_of(client_merc).global_position
	# `PossessionSync` carries direction, not frame numbers, so the guest's
	# prediction has no acknowledgement to reconcile against: a dropped
	# unreliable frame leaves the two copies a fraction of a stride apart. The
	# bound below is that fraction (the walk covers 4 m), while `worst_step`
	# above already proves the body never jumps between samples.
	check(own_pos.distance_to(host_pos) < 0.6,
		"The client's body agrees with the host's copy (%s vs %s)" % [own_pos, host_pos])
	check(str(data.get("refusal", "")) != "", "The client's refused request names a reason")
	check(int(data.get("failures", 1)) == 0, "The client's own checks all pass")

func _store_report(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	if not kind.is_empty():
		reports[kind] = payload

func _print_and_quit() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	if session != null:
		session.leave()
	if battlefield != null:
		battlefield.queue_free()
	await process_frame
	_clear_trace()
	print("WARBAND_SESSION_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- client ----------------------------------------------------------------

func _client_run() -> void:
	_clear_trace()
	var args := OS.get_cmdline_user_args()
	var index := args.find("--warband-client")
	var server_port := int(args[index + 1])
	var client_merc := int(args[index + 2])
	var host_merc := int(args[index + 3])
	if not _build_field(false):
		quit(1)
		return
	var report := Report.new()
	report.name = REPORT_NAME
	root.add_child(report)
	report.walk_requested.connect(_walk_and_report)
	report.probe_requested.connect(_probe_downed)
	report.leave_requested.connect(func(): leave_requested = true)
	_trace("field built")
	check(session.join("127.0.0.1", server_port, "Client soul"),
		"The client joins the warband session")
	var connected := await _wait_until(func(): return session.peer_count() == 2, 20.0)
	_trace("connected=%s peers=%s" % [connected, session.connected_peers()])
	if not connected:
		_submit({"kind": "error", "detail": "join timeout"})
		await _finish_client(1)
		return
	var asked := session.request_body(client_merc)
	_trace("asked=%s" % [asked])
	var possessed := await _wait_until(
		func(): return controller.merc_for_peer(controller.local_peer_id) == client_merc, 10.0)
	_trace("possessed=%s merc=%s local=%s" % [possessed,
		controller.merc_for_peer(controller.local_peer_id), controller.local_peer_id])
	if not possessed:
		_submit({"kind": "error", "detail": "possession timeout"})
		await _finish_client(1)
		return
	session.transfer_refused.connect(
		func(_merc_id: int, reason: String): refusal_reason = reason)
	var steal := session.request_body(host_merc)
	check(bool(steal.get("pending", false)),
		"The client asks the host instead of entering the body itself")
	var refused := await _wait_until(func(): return refusal_reason != "", 6.0)
	_trace("refused=%s reason=%s" % [refused, refusal_reason])
	if not refused:
		_submit({"kind": "error", "detail": "host body refusal never arrived"})
		await _finish_client(1)
		return
	check(controller.merc_for_peer(controller.local_peer_id) == client_merc,
		"The refused client soul stays in the body it asked for")
	var held := await _wait_until(func(): return leave_requested, 45.0)
	if not held:
		_submit({"kind": "error", "detail": "the host never released the client"})
	await _finish_client(0 if held else 1)

func _walk_and_report(frames: int) -> void:
	var body = controller.active_body()
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
	# Let the last frames round-trip, so the pose this report carries is the one
	# both machines settled on rather than a local guess.
	var settle := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < settle:
		await process_frame
	var merc_id := controller.merc_for_peer(controller.local_peer_id)
	_submit({"kind": "motion",
		"own_peer": root.multiplayer.get_unique_id(),
		"peers": session.peer_count(),
		"own_merc": merc_id,
		"host_view": warband.souls.occupied_by(merc_id),
		"predicting": bool(body.predicting),
		"first_move": first,
		"predicted": stop.distance_to(origin),
		"worst_step": worst,
		"own_pos": body.global_position,
		"refusal": refusal_reason})

func _probe_downed(merc_id: int) -> void:
	var body = controller.body_of(merc_id)
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if body != null and bool(body.downed) and float(body.health) <= 0.0:
			_submit({"kind": "probe", "merc": merc_id, "downed": true,
				"health": float(body.health), "alive": bool(body.alive)})
			return
		await process_frame
	_submit({"kind": "probe", "merc": merc_id, "downed": false,
		"health": float(body.health) if body != null else -1.0,
		"alive": bool(body.alive) if body != null else false})

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

func _finish_client(code: int) -> void:
	if session != null:
		session.leave()
	if battlefield != null:
		battlefield.queue_free()
	await process_frame
	quit(code)
