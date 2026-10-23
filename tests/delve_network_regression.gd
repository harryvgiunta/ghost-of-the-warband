extends SceneTree
## Two real ENet processes: a host opens the delve, a client joins the landing,
## both see the wave spawn, the host breaks it, and both see the cache open.

const Progress = preload("res://scripts/delve_progress.gd")
const TEST_SAVE := "user://delve_network_regression_state.json"
const TRACE_PATH := "user://delve_net_client_trace.txt"

var failures := 0
var checks := 0
var session
var game
var reports: Dictionary = {}
var child_pid := -1

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DELVE_NET_FAIL  ", message)

func _remove_test_save() -> void:
	for path in [TEST_SAVE, TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

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
	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

func _store_report(payload: Dictionary) -> void:
	if payload.has("client_error"):
		reports["client_error"] = str(payload["client_error"])
	elif bool(payload.get("cleared", false)):
		reports["cleared"] = payload
	elif bool(payload.get("open", false)):
		reports["open"] = payload

func _host_run() -> void:
	_remove_test_save()
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "Network fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	session.arm_delve("delve-host", "127.0.0.1", port, "Delve host")
	game = load("res://delve.tscn").instantiate()
	game.save_path = TEST_SAVE
	root.add_child(game)
	var report := Report.new()
	report.name = "DelveNetReport"
	report.submitted.connect(_store_report)
	root.add_child(report)
	var hosted := await _wait_until(func(): return game.network_role == "host", 6.0)
	check(hosted, "The host opens a delve server")
	var child_args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", get_script().resource_path, "--", "--delve-client", str(port)])
	child_pid = OS.create_process(OS.get_executable_path(), child_args)
	check(child_pid > 0, "The client process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2, 10.0)
	check(joined, "A real ENet client joins the delve")
	check(int(game.actors[1].peer_id) > 1, "The host seats the client")
	check(game.actors[1].alive and game.actors[1].visible, "The joining delver is live on the landing")

	game.begin_descent()
	var wave := await _wait_until(func(): return game.phase == "WAVE" and game.devils.size() == 2, 6.0)
	check(wave, "The host starts the wave with two devils")
	check(game.world.sealed, "The room is sealed for the network wave")
	for devil in game.devils:
		check(devil.authoritative and devil.alive, "Host owns every replicated devil")
	# Let a couple of 20 Hz snapshots reach the replica before ending the wave.
	await create_timer(0.8).timeout
	for devil in game.devils.duplicate():
		if is_instance_valid(devil) and devil.alive:
			devil.take_damage(9999.0, -1)
	var cleared := await _wait_until(func(): return game.phase == "CLEARED" and game.chest_ready and is_instance_valid(game.chest), 6.0)
	check(cleared, "The host breaks the wave and spawns the cache")
	var client_cleared := await _wait_until(func(): return reports.has("cleared") or reports.has("client_error"), 8.0)
	if reports.has("client_error"):
		check(false, "Client reported an error: " + str(reports["client_error"]))
	if not client_cleared:
		print("CLIENT_TRACE:\n", _read_trace())
	check(client_cleared, "The client observes the cleared room and its cache")
	if reports.has("cleared"):
		var cleared_report: Dictionary = reports["cleared"]
		check(int(cleared_report.get("slot", -1)) == 1, "The client joined seat one")
		check(bool(cleared_report.get("saw_wave", false)), "The client saw the replicated devils")
		check(int(cleared_report.get("devils", 0)) >= 1, "At least one devil reached the client")
		check(str(cleared_report.get("phase", "")) == "CLEARED", "The client reached the cleared phase")
		check(bool(cleared_report.get("chest", false)), "The client sees the cache")
		check(bool(cleared_report.get("host_alive", false)), "The client sees the host alive")
		check(bool(cleared_report.get("sealed_open", false)), "The client sees the opened seal")
		check(bool(cleared_report.get("role_ok", false)), "The client HUD labels its link as CLIENT")

	game.open_chest()
	check(game.chest_open, "The host opens the cache")
	var client_open := await _wait_until(func(): return reports.has("open") or reports.has("client_error"), 8.0)
	check(client_open, "The client observes the opened cache")
	if reports.has("open"):
		var open_report: Dictionary = reports["open"]
		check(bool(open_report.get("chest_open", false)), "The client chest lid opens")
		check(bool(open_report.get("burst", false)), "The client fires the shared loot burst")

	await _print_and_quit()

func _print_and_quit() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	game.leave_game()
	game.queue_free()
	await process_frame
	_remove_test_save()
	print("DELVE_NETWORK_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _client_run(port: int) -> void:
	session.arm_delve("delve-join", "127.0.0.1", port, "Delve client")
	game = load("res://delve.tscn").instantiate()
	root.add_child(game)
	var report := Report.new()
	report.name = "DelveNetReport"
	root.add_child(report)
	_trace("client scene added")
	var joined := await _wait_until(func(): return game.local_slot == 1, 10.0)
	_trace("joined=" + str(joined) + " slot=" + str(game.local_slot))
	if not joined:
		report.submit.rpc_id(1, {"client_error": "join timeout"})
		await _finish_client(1)
		return
	print("DELVE_NET_CLIENT joined slot=", game.local_slot)
	var saw_wave := false
	var devils_seen := 0
	var cleared_sent := false
	var open_sent := false
	var last_phase := ""
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if game.phase != last_phase:
			last_phase = game.phase
			var replica_count := 0
			for devil in game._devil_nodes.values():
				if is_instance_valid(devil) and devil.alive:
					replica_count += 1
			_trace("phase=" + last_phase + " devils=" + str(replica_count) + " chest=" + str(is_instance_valid(game.chest)) + " chest_ready=" + str(game.chest_ready))
			print("DELVE_NET_CLIENT phase=", last_phase, " devils=", replica_count)
		if game.phase == "GAME_OVER":
			break
		if game.phase == "WAVE":
			var replicas := 0
			for devil in game._devil_nodes.values():
				if is_instance_valid(devil) and devil.alive:
					replicas += 1
			if replicas > 0:
				saw_wave = true
				devils_seen = maxi(devils_seen, replicas)
		if game.phase == "CLEARED" and is_instance_valid(game.chest) and not cleared_sent:
			cleared_sent = true
			_trace("sending cleared report")
			report.submit.rpc_id(1, {"cleared": true, "slot": game.local_slot,
				"saw_wave": saw_wave, "devils": devils_seen, "phase": game.phase,
				"chest": is_instance_valid(game.chest), "host_alive": game.actors[0].alive,
				"sealed_open": not game.world.sealed,
				"role_ok": game.hud.endpoint_label.text.begins_with("CLIENT")})
		if cleared_sent and is_instance_valid(game.chest) and game.chest.is_opened() and not open_sent:
			open_sent = true
			_trace("sending open report")
			var burst := game.chest.get_node_or_null("LootBurst") as CPUParticles3D
			report.submit.rpc_id(1, {"open": true, "chest_open": game.chest_open,
				"burst": burst != null and burst.emitting})
			# Reliable RPC still needs an ENet poll before this peer closes.
			await create_timer(0.6).timeout
			break
		await process_frame
	if not cleared_sent:
		_trace("failed to reach cleared; phase=" + str(game.phase))
		report.submit.rpc_id(1, {"client_error": "never reached cleared; phase=" + str(game.phase)})
	await _finish_client(0 if cleared_sent else 1)

func _finish_client(code: int) -> void:
	game.leave_game()
	game.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	session = root.get_node_or_null("Session")
	check(session != null, "The Session autoload exists")
	var args := OS.get_cmdline_user_args()
	if args.has("--delve-client"):
		await _client_run(int(args[args.find("--delve-client") + 1]))
	else:
		await _host_run()
