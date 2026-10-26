extends SceneTree
## Open world -> delve hand-off: the host keeps its ENet server and port, a
## rider who drops into the hatch alone is lifted back out, and the connected
## party follows the host into a hosted delve without reconnecting.

const TRACE_PATH := "user://world_delve_client_trace.txt"
const REPORT_NAME := "WorldDelveReport"

var failures := 0
var checks := 0
var session
var state
var game
var report_node
var reports: Dictionary = {}
var child_pid := -1
var save_path := ""

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if not save_path.is_empty() and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WORLD_DELVE_FAIL  ",message)

func _trace(message: String) -> void:
	var file := FileAccess.open(TRACE_PATH,FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(TRACE_PATH,FileAccess.WRITE)
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
	@rpc("any_peer","call_remote","reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

func _store_report(payload: Dictionary) -> void:
	if payload.has("client_error"):
		reports["client_error"] = str(payload["client_error"])
		return
	reports[str(payload.get("stage","delve"))] = payload

func _scene_path() -> String:
	return current_scene.scene_file_path if current_scene != null else ""

func _host_run() -> void:
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK,"The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	session.arm_world("world-host","127.0.0.1",port,"World host")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	report_node = Report.new()
	report_node.name = REPORT_NAME
	report_node.submitted.connect(_store_report)
	root.add_child(report_node)
	var hosted := await _wait_until(func(): return game.network_role == "host",8.0)
	check(hosted,"The host opens the open world")
	if not hosted:
		await _print_and_quit()
		return

	var child_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",get_script().resource_path,"--","--open-world-delve-client",str(port)])
	child_pid = OS.create_process(OS.get_executable_path(),child_args)
	check(child_pid > 0,"The client process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2 and game._seats.has(1),20.0)
	check(joined,"A real ENet client joins the open world")
	if not joined:
		print("CLIENT_TRACE:\n",_read_trace())
		await _print_and_quit()
		return

	# A rider who drops into the hatch alone must not tear the party apart.
	var seat = game._seats[1]
	seat.global_position = Vector3(16.0,2.0,42.0)
	seat.velocity = Vector3.ZERO
	var rescued := await _wait_until(func(): return is_instance_valid(seat) and seat.global_position.z > 43.0 and seat.global_position.y > 3.0,4.0)
	check(rescued,"The host lifts a rider who fell into the hatch back out")
	check(game.network_role == "host" and game.get_human_count() == 2,"The open-world session survives the refused solo drop")
	check(_scene_path() == "res://main.tscn","The refused drop stays in the open world")

	# Let the rider observe the refused drop before the host leads the descent.
	var refused := await _wait_until(func(): return reports.has("refused") or reports.has("client_error"),10.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
		print("CLIENT_TRACE:\n",_read_trace())
	check(refused,"The client reports the refused solo drop")
	if reports.has("refused"):
		var refused_data: Dictionary = reports["refused"]
		check(bool(refused_data.get("stayed",false)),"The client stayed in the open world during the refused drop")

	# The host's own fall hands the live peer and the whole party to the delve.
	var peer_instance: int = game.multiplayer.multiplayer_peer.get_instance_id()
	game.player.global_position = Vector3(16.0,3.8,42.0)
	game.player.velocity = Vector3.ZERO
	var entered := await _wait_until(func(): return _scene_path() == "res://delve.tscn",10.0)
	check(entered,"The host's fall loads the delve")
	if not entered:
		print("CLIENT_TRACE:\n",_read_trace())
		await _print_and_quit()
		return
	var delve = current_scene
	check(delve.network_role == "host","The fall keeps the host role instead of dropping to solo")
	check(delve.multiplayer.multiplayer_peer is ENetMultiplayerPeer,"The delve adopts a real ENet peer")
	check(delve.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,"The carried peer is still connected")
	check(delve.multiplayer.multiplayer_peer.get_instance_id() == peer_instance,"The delve keeps the open world's peer, not a new server")
	check(str(delve._endpoint).contains(str(port)),"The delve keeps the open world's port")
	check(delve.local_slot == 0,"The host sits on delver slot zero")

	var followed := await _wait_until(func(): return delve.get_human_count() == 2,10.0)
	check(followed,"The connected client follows the host into the delve")
	if followed:
		check(is_instance_valid(delve.actors[1]) and delve.actors[1].alive and delve.actors[1].visible,"The carried client is seated as a live delver")
		check(int(delve.actors[1].peer_id) > 1,"The carried delver keeps its ENet peer id")
		check(delve.actors[1].display_name == "World client","The carried delver keeps its player name")

	var reported := await _wait_until(func(): return reports.has("delve") or reports.has("client_error"),12.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
		print("CLIENT_TRACE:\n",_read_trace())
	check(reported,"The client reports its carried state")
	if reports.has("delve"):
		var data: Dictionary = reports["delve"]
		check(str(data.get("scene","")) == "res://delve.tscn","The client followed the host into the delve scene")
		check(str(data.get("role","")) == "client","The client kept its client role")
		check(int(data.get("slot",-1)) == 1,"The client resumed its carried delver slot")
		check(bool(data.get("accepted",false)),"The host accepted the carried delver")
		check(bool(data.get("same_peer",false)),"The client kept its open-world ENet connection")
		check(bool(data.get("replicated",false)),"The client sees both delvers after the hand-off")
		check(str(data.get("endpoint","")).contains(str(port)),"The client still addresses the host's open-world port")
	await _print_and_quit()

func _print_and_quit() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	if is_instance_valid(current_scene):
		var scene = current_scene
		if scene.has_method("leave_game"):
			scene.leave_game()
		scene.queue_free()
	if report_node != null and is_instance_valid(report_node):
		report_node.queue_free()
	await process_frame
	_clear_trace()
	_remove_test_save()
	print("OPEN_WORLD_DELVE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _client_run(port: int) -> void:
	session.arm_world("world-join","127.0.0.1",port,"World client")
	report_node = Report.new()
	report_node.name = REPORT_NAME
	root.add_child(report_node)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_trace("client scene added")
	var joined := await _wait_until(func(): return main.local_slot == 1,15.0)
	_trace("joined=" + str(joined) + " slot=" + str(main.local_slot))
	if not joined:
		report_node.submit.rpc_id(1,{"client_error":"join timeout"})
		await _finish_client(1)
		return
	print("WORLD_DELVE_CLIENT joined slot=",main.local_slot)
	var peer_instance: int = main.multiplayer.multiplayer_peer.get_instance_id()

	# The host drops this seat into the hatch alone; the authority lifts it out.
	await create_timer(1.0).timeout
	_trace("drop window done stayed=" + str(_scene_path() == "res://main.tscn"))
	var stayed: bool = _scene_path() == "res://main.tscn" and main.network_role == "client"
	report_node.submit.rpc_id(1,{"stage":"refused","stayed":stayed})
	var arrived := await _wait_until(func(): return _scene_path() == "res://delve.tscn",20.0)
	if not arrived:
		_trace("delve arrival timeout scene=" + _scene_path())
		report_node.submit.rpc_id(1,{"client_error":"delve arrival timeout"})
		await _finish_client(1)
		return
	var delve = current_scene
	var accepted := await _wait_until(func(): return delve.local_slot == 1,8.0)
	var replicated := await _wait_until(func(): return delve.actors[0].alive and delve.actors[1].alive,8.0)
	var payload := {
		"stage":"delve",
		"scene":_scene_path(),"stayed":stayed,
		"role":str(delve.network_role),"slot":int(delve.local_slot),
		"same_peer":delve.multiplayer.multiplayer_peer.get_instance_id() == peer_instance,
		"replicated":replicated,"accepted":accepted,
		"endpoint":str(delve._endpoint),
	}
	print("WORLD_DELVE_CLIENT report role=",delve.network_role," slot=",delve.local_slot," same_peer=",payload["same_peer"])
	report_node.submit.rpc_id(1,payload)
	await create_timer(0.3).timeout
	await _finish_client(0)

func _finish_client(code: int) -> void:
	if is_instance_valid(current_scene):
		var scene = current_scene
		if scene.has_method("leave_game"):
			scene.leave_game()
		scene.queue_free()
	await process_frame
	_remove_test_save()
	quit(code)

func run() -> void:
	session = root.get_node_or_null("Session")
	check(session != null,"The Session autoload exists")
	var args := OS.get_cmdline_user_args()
	var client_mode := args.has("--open-world-delve-client")
	state = root.get_node_or_null("PlayerState")
	if state != null:
		save_path = "user://open_world_delve_%s_state.json" % ("client" if client_mode else "host")
		state.save_path = save_path
		state.reset(false)
	if client_mode:
		await _client_run(int(args[args.find("--open-world-delve-client") + 1]))
	else:
		await _host_run()
