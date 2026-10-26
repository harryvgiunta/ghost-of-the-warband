extends SceneTree
## Open world -> delve -> back: the delve is a disposable instance opened inside
## the running session. The host's fall keeps its ENet server and its whole
## frontier (frozen), riders stay in the walkable town until each asks for
## passage, the room waits on a gate until every connected ranger is seated, and
## the rope hands the frontier back exactly as it was — same peers, same mobs,
## same state, no reconnect and no scene replacement.

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
var child_pid_2 := -1
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

## The room's real geometry, not just the node: a client that skipped
## `apply_room` still has a world node but nothing in it.
func _mesh_count(node: Node) -> int:
	var count := 0
	var stack: Array = [node]
	while not stack.is_empty():
		var item: Node = stack.pop_back()
		for child in item.get_children():
			stack.push_back(child)
		if item is MeshInstance3D:
			count += 1
	return count

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

	var script_path: String = get_script().resource_path
	var child_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",script_path,"--","--open-world-delve-client",str(port)])
	child_pid = OS.create_process(OS.get_executable_path(),child_args)
	check(child_pid > 0,"The client process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2 and game._seats.has(1),20.0)
	check(joined,"A real ENet client joins the open world")
	if not joined:
		print("CLIENT_TRACE:\n",_read_trace())
		await _print_and_quit()
		return

	# A second rider links up too, then quits below ground without descending:
	# the gate must drop it from the count without opening on its own.
	var idle_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",script_path,"--","--open-world-delve-idle",str(port)])
	child_pid_2 = OS.create_process(OS.get_executable_path(),idle_args)
	check(child_pid_2 > 0,"The second client process starts")
	var both := await _wait_until(func(): return game.get_human_count() == 3 and game._seats.has(2),20.0)
	check(both,"A second ENet client joins the open world")

	# A rider who drops into the hatch alone must not tear the party apart while
	# the authority is still holding the town.
	var seat = game._seats[1]
	seat.global_position = Vector3(16.0,2.0,42.0)
	seat.velocity = Vector3.ZERO
	var rescued := await _wait_until(func(): return is_instance_valid(seat) and seat.global_position.z > 43.0 and seat.global_position.y > 3.0,4.0)
	check(rescued,"The host lifts a rider who fell into the hatch back out")
	check(game.network_role == "host" and game.get_human_count() == 3,"The open-world session survives the refused solo drop")
	check(_scene_path() == "res://main.tscn","The refused drop stays in the open world")

	var refused := await _wait_until(func(): return reports.has("refused") or reports.has("client_error"),10.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
		print("CLIENT_TRACE:\n",_read_trace())
	check(refused,"The client reports the refused solo drop")
	if reports.has("refused"):
		var refused_data: Dictionary = reports["refused"]
		check(bool(refused_data.get("stayed",false)),"The client stayed in the open world during the refused drop")

	# State that must come back untouched after the rope.
	var peer_instance: int = game.multiplayer.multiplayer_peer.get_instance_id()
	var probe_mob = game.enemies[0]
	var probe_layer := int(probe_mob.collision_layer)
	var outer_health: float = game.health
	var outer_gold: int = game.gold
	var outer_enemies: int = game.enemies.size()
	var outer_player: Node = game.player

	# The host's own fall opens the run inside this session; the party is not
	# dragged along and the frontier is frozen rather than replaced.
	game.player.global_position = Vector3(16.0,3.8,42.0)
	game.player.velocity = Vector3.ZERO
	var entered := await _wait_until(func(): return game._delve_inner != null,10.0)
	check(entered,"The host's fall opens the run inside the session")
	if not entered:
		print("CLIENT_TRACE:\n",_read_trace())
		await _print_and_quit()
		return
	var delve = game._delve_inner
	check(_scene_path() == "res://main.tscn" and game.is_inside_tree(),"The descent does not replace the session")
	check(String(delve.get_path()) == "/root/Ironwood/Delve","The run is an inner instance of this session")
	check(str(delve.network_role) == "host","The fall keeps the host role")
	check(delve.multiplayer.multiplayer_peer is ENetMultiplayerPeer,"The run talks on a real ENet peer")
	check(delve.multiplayer.multiplayer_peer.get_instance_id() == peer_instance,"The run keeps the open world's peer, not a new server")
	check(str(delve._endpoint).contains(str(port)),"The run keeps the open world's port")
	check(delve.local_slot == 0,"The host sits on delver slot zero")
	check(game._frontier.process_mode == Node.PROCESS_MODE_DISABLED and not game._frontier.visible,"The frontier freezes behind the run")
	check(not game._ui_layer.visible,"The frontier HUD hides behind the run")
	check(int(probe_mob.collision_layer) == 0,"Frontier bodies stop colliding inside the run")
	var frozen_at: Vector3 = probe_mob.global_position

	# Requirement: a rider who drops into a delve with a party outside waits on a
	# waiting screen until the others join, and nobody is dragged along.
	check(str(delve.phase) == "WAITING","The host opens on the waiting screen while rangers are still outside")
	check(int(delve.waiting_count()) == 2,"The waiting screen counts both rangers who stayed in town")
	check(delve.get_human_count() == 1,"The party outside was not pulled into the delve")
	check(delve.world.is_built(),"The run builds its room before the first frame")
	check(_mesh_count(delve.world) > 0,"The waiting room renders real geometry, not an empty shell")
	check(delve.devils.is_empty() and delve.wave_total == 0,"The wave is not planned before the party is assembled")
	delve.begin_wave()
	await create_timer(0.4).timeout
	check(str(delve.phase) == "WAITING","The altar stays asleep while the party is still outside")

	# The ranger chose to stay in town and can still walk: the client reports it.
	var stayed := await _wait_until(func(): return reports.has("stayed") or reports.has("client_error"),12.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
		print("CLIENT_TRACE:\n",_read_trace())
	check(stayed,"The client reports the open run without a scene change")
	if reports.has("stayed"):
		var stayed_data: Dictionary = reports["stayed"]
		check(str(stayed_data.get("scene","")) == "res://main.tscn","The host's fall leaves the rider in the open world")
		check(bool(stayed_data.get("inner",false)) == false,"The rider still owns the open world, not a run")
		check(str(stayed_data.get("role","")) == "client","The rider keeps its client role in town")
		check(int(stayed_data.get("port",0)) == port,"The rider learns the run's port on the same session")
	var walked := await _wait_until(func(): return reports.has("walk") or reports.has("client_error"),10.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
	check(walked,"The rider reports its walk in the abandoned town")
	if reports.has("walk"):
		check(float(reports["walk"].get("walked",0.0)) > 0.1,"The town stays walkable while the authority is below")

	# The gate holds through every membership change: the first rider seats while
	# the second is still outside, and only the last departure opens the room.
	var gate_held := true
	var gate_deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < gate_deadline:
		if int(delve.waiting_count()) > 0 and str(delve.phase) != "WAITING":
			gate_held = false
		if str(delve.phase) == "ALTAR":
			break
		await process_frame
	check(gate_held,"The gate stays shut while any ranger is still outside")
	check(str(delve.phase) == "ALTAR","The gate opens once nobody is left outside")
	check(int(delve.waiting_count()) == 0,"No ranger is still counted outside")
	check(delve.get_human_count() == 2,"Only the ranger who descended holds a delve seat")
	if is_instance_valid(delve.actors[1]):
		check(delve.actors[1].alive and delve.actors[1].visible,"The rider is seated as a live delver")
		check(int(delve.actors[1].peer_id) > 1,"The carried delver keeps its ENet peer id")
		check(delve.actors[1].display_name == "World client","The carried delver keeps its player name")

	var reported := await _wait_until(func(): return reports.has("delve") or reports.has("client_error"),12.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
		print("CLIENT_TRACE:\n",_read_trace())
	check(reported,"The client reports its run state")
	if reports.has("delve"):
		var data: Dictionary = reports["delve"]
		check(str(data.get("scene","")) == "res://main.tscn","The client's world scene never changed")
		check(bool(data.get("inner",false)),"The client opened its own inner instance")
		check(String(data.get("path","")) == "/root/Ironwood/Delve","The client's run sits at the same path")
		check(str(data.get("role","")) == "client","The client kept its client role")
		check(int(data.get("slot",-1)) == 1,"The client resumed its carried delver slot")
		check(bool(data.get("accepted",false)),"The host accepted the carried delver")
		check(bool(data.get("same_peer",false)),"The client kept its open-world ENet connection")
		check(bool(data.get("replicated",false)),"The client sees both delvers after the hand-off")
		check(bool(data.get("room_built",false)),"The client renders the room's real geometry")
		check(int(data.get("mesh_count",0)) > 0,"The client's room is not an empty shell")
		check(str(data.get("phase","")) == "ALTAR","The client sees the assembled phase")
		check(int(data.get("waiting",-1)) == 0,"The client's waiting screen reads zero rangers outside")

	# Freezing is real: the frontier does not advance while the run is open.
	check(int(delve.waiting_count()) == 0 and delve.get_human_count() == 2,"The run is still live before the rope")
	check(probe_mob.global_position.distance_to(frozen_at) < 0.001,"The frozen frontier does not move during the run")
	check(not probe_mob.can_process(),"Frontier nodes are halted during the run")

	# The rope: the run ends, the same session resumes with everything it had.
	delve._set_phase("CLEARED")
	delve.ascend_to_surface()
	var first_run_id: int = delve.get_instance_id()
	var left := await _wait_until(func(): return game._delve_inner == null,10.0)
	check(left,"The rope ends the run")
	check(_scene_path() == "res://main.tscn" and game.is_inside_tree(),"The rope keeps the session loaded")
	check(not is_instance_valid(delve),"The disposable run is freed")
	check(str(game.network_role) == "host","The host role survives the run")
	check(game.multiplayer.multiplayer_peer.get_instance_id() == peer_instance,"The rope keeps the open world's peer")
	check(game.get_human_count() == 2,"The party is still connected after the rope")
	check(game._frontier.visible and game._frontier.process_mode == Node.PROCESS_MODE_INHERIT,"The frontier resumes")
	check(game._ui_layer.visible,"The frontier HUD returns")
	check(game.camera.current,"The frontier camera takes the view back")
	check(int(probe_mob.collision_layer) == probe_layer and probe_mob.can_process(),"Frontier bodies collide and simulate again after the rope")
	check(game.enemies.size() == outer_enemies and game.enemies[0] == probe_mob,"The frontier keeps its own mobs, not a rebuild")
	check(is_instance_valid(outer_player) and game.player == outer_player,"The same ranger body comes back")
	check(absf(game.health - outer_health) < 0.01 and game.gold == outer_gold,"The outer ranger's state is untouched by the run")
	check(game.player.global_position.z > 43.0 and game.player.global_position.y > 3.0,"The host steps out of the hatch")
	var resumed := await _wait_until(func(): return reports.has("resumed") or reports.has("client_error"),12.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
	check(resumed,"The rider reports the resumed world")
	if reports.has("resumed"):
		var back: Dictionary = reports["resumed"]
		check(str(back.get("scene","")) == "res://main.tscn","The rider is back in the world scene")
		check(bool(back.get("inner_gone",false)),"The rider's run is gone")
		check(str(back.get("role","")) == "client","The rider is still a client")
		check(bool(back.get("same_peer",false)),"The rider never reconnected")
		check(bool(back.get("frontier_live",false)),"The rider's frontier resumed")
		check(int(back.get("open_port",-1)) == 0,"The rider knows the party is back in the world")

	# Disposable: the same hatch opens a brand-new run, and a rider can ask the
	# authority to bring the party back up.
	game.player.global_position = Vector3(16.0,3.8,42.0)
	game.player.velocity = Vector3.ZERO
	var second_open := await _wait_until(func(): return game._delve_inner != null,10.0)
	check(second_open,"A second fall opens a new run")
	if second_open:
		var second = game._delve_inner
		check(int(second.get_instance_id()) != first_run_id,"The second run is a fresh instance")
		check(str(second.phase) == "WAITING","The fresh run waits on the party again")
		check(int(second.depth) == 1 and second.devils.is_empty(),"The fresh run starts at depth one with no leftovers")
		var released := await _wait_until(func(): return reports.has("released") or reports.has("client_error"),30.0)
		if reports.has("client_error"):
			check(false,"Client reported an error: " + str(reports["client_error"]))
		check(released,"The rider asks the party out of the second run")
		check(bool(reports.get("released",{}).get("seated",false)),"The rider was seated in the second run")
		check(await _wait_until(func(): return game._delve_inner == null,12.0),"The authority ends the run for the party")
		check(game._frontier.process_mode == Node.PROCESS_MODE_INHERIT and game._frontier.visible,"The frontier resumes after a party exit")
		check(game.get_human_count() == 2 and str(game.network_role) == "host","The party stays together after the second exit")
	await _print_and_quit()

func _print_and_quit() -> void:
	for pid in [child_pid,child_pid_2]:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
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

	# A rider drop while the host holds the town is refused; the authority lifts
	# this seat back out and the client stays put.
	await create_timer(1.0).timeout
	_trace("drop window done stayed=" + str(main.is_inside_tree()))
	var stayed: bool = main.network_role == "client" and main._delve_inner == null
	report_node.submit.rpc_id(1,{"stage":"refused","stayed":stayed})

	# The host falls. This client must stay in the open world and learn the port.
	var open := await _wait_until(func(): return int(session.delve_open_port) == port,25.0)
	var still_in_town: bool = is_instance_valid(main) and main._delve_inner == null and main.network_role == "client"
	_trace("delve open=" + str(open) + " stayed=" + str(still_in_town))
	report_node.submit.rpc_id(1,{"stage":"stayed","scene":str(main.scene_file_path),
		"inner":is_instance_valid(main) and main._delve_inner != null,
		"role":str(main.network_role) if is_instance_valid(main) else "",
		"port":int(session.delve_open_port),"stayed":still_in_town})
	if not open:
		report_node.submit.rpc_id(1,{"client_error":"the host's fall never opened the delve"})
		await _finish_client(1)
		return

	# The town stays walkable with no authority behind it. W follows the camera
	# yaw, so face the walk away from the hatch and measure the local travel.
	var walked := -1.0
	if is_instance_valid(main):
		main.player.global_position = main.world.player_spawn + Vector3(0.0,0.3,0.0)
		main.player.velocity = Vector3.ZERO
		await process_frame
		await process_frame
		main.camera_yaw = PI
		var start: Vector3 = main.player.global_position
		var press_key := InputEventKey.new()
		press_key.physical_keycode = KEY_W
		press_key.pressed = true
		Input.parse_input_event(press_key)
		await create_timer(0.5).timeout
		var release_key := InputEventKey.new()
		release_key.physical_keycode = KEY_W
		release_key.pressed = false
		Input.parse_input_event(release_key)
		walked = start.distance_to(main.player.global_position)
	_trace("walked=" + str(walked))
	report_node.submit.rpc_id(1,{"stage":"walk","walked":walked})

	# Walk into the hatch on this side; the authority leads the peer down into an
	# instance of the session it already shares.
	await create_timer(2.5).timeout
	if is_instance_valid(main) and main._delve_inner == null:
		main.player.global_position = Vector3(16.0,2.2,42.0)
		main.player.velocity = Vector3.ZERO
	var arrived := await _wait_until(func(): return is_instance_valid(main) and main._delve_inner != null,20.0)
	if not arrived:
		_trace("delve instance timeout")
		report_node.submit.rpc_id(1,{"client_error":"inner instance timeout"})
		await _finish_client(1)
		return
	var delve = main._delve_inner
	var accepted := await _wait_until(func(): return delve.local_slot == 1,8.0)
	var replicated := await _wait_until(func(): return delve.actors[0].alive and delve.actors[1].alive,8.0)
	var assembled := await _wait_until(func(): return str(delve.phase) == "ALTAR",8.0)
	var payload := {
		"stage":"delve",
		"scene":str(main.scene_file_path),"inner":true,"path":str(delve.get_path()),
		"role":str(delve.network_role),"slot":int(delve.local_slot),
		"same_peer":delve.multiplayer.multiplayer_peer.get_instance_id() == peer_instance,
		"replicated":replicated,"accepted":accepted and assembled,
		"room_built":bool(delve.world.is_built()),
		"mesh_count":_mesh_count(delve),
		"phase":str(delve.phase),"waiting":int(delve.waiting_count()),
	}
	print("WORLD_DELVE_CLIENT report slot=",delve.local_slot," same_peer=",payload["same_peer"])
	report_node.submit.rpc_id(1,payload)

	# The rope takes the whole party back into the same session.
	var gone := await _wait_until(func(): return is_instance_valid(main) and main._delve_inner == null,25.0)
	await create_timer(0.4).timeout
	_trace("resumed gone=" + str(gone) + " scene=" + str(main.scene_file_path))
	report_node.submit.rpc_id(1,{"stage":"resumed","scene":str(main.scene_file_path),
		"inner_gone":is_instance_valid(main) and main._delve_inner == null,
		"role":str(main.network_role) if is_instance_valid(main) else "",
		"same_peer":is_instance_valid(main) and main.multiplayer.multiplayer_peer.get_instance_id() == peer_instance,
		"frontier_live":is_instance_valid(main) and main._frontier.visible and main._frontier.process_mode == Node.PROCESS_MODE_INHERIT,
		"open_port":int(session.delve_open_port)})

	# The host opens a second run; follow it and then ask the party out.
	await create_timer(1.0).timeout
	if is_instance_valid(main) and main._delve_inner == null:
		main.player.global_position = Vector3(16.0,2.2,42.0)
		main.player.velocity = Vector3.ZERO
	var second := await _wait_until(func(): return is_instance_valid(main) and main._delve_inner != null,25.0)
	if not second:
		report_node.submit.rpc_id(1,{"client_error":"the second run never opened"})
		await _finish_client(1)
		return
	var run = main._delve_inner
	var seated := await _wait_until(func(): return run.local_slot == 1 and str(run.phase) == "ALTAR",15.0)
	await create_timer(0.4).timeout
	run._surface_request.rpc_id(1)
	var out := await _wait_until(func(): return is_instance_valid(main) and main._delve_inner == null,20.0)
	_trace("released seated=" + str(seated) + " out=" + str(out))
	report_node.submit.rpc_id(1,{"stage":"released","seated":seated,"inner_gone":is_instance_valid(main) and main._delve_inner == null,
		"role":str(main.network_role) if is_instance_valid(main) else "",
		"same_peer":is_instance_valid(main) and main.multiplayer.multiplayer_peer.get_instance_id() == peer_instance})
	await create_timer(0.4).timeout
	await _finish_client(0)

## A second rider: links up, holds the town through the host's fall, then leaves
## before it ever descends. The gate must drop it from the count without opening
## on its own.
func _idle_run(port: int) -> void:
	session.arm_world("world-join","127.0.0.1",port,"Idle client")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var joined := await _wait_until(func(): return main.local_slot >= 1,20.0)
	print("WORLD_DELVE_IDLE joined=",joined," slot=",main.local_slot)
	if not joined:
		await _finish_client(1)
		return
	var open := await _wait_until(func(): return int(session.delve_open_port) == port,25.0)
	print("WORLD_DELVE_IDLE open=",open)
	# Hold the connection long enough for the other rider to seat below ground.
	await create_timer(10.0).timeout
	_trace("idle leaving")
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
		var role := "client" if client_mode else "idle" if args.has("--open-world-delve-idle") else "host"
		save_path = "user://open_world_delve_%s_state.json" % role
		state.save_path = save_path
		state.reset(false)
	if client_mode:
		await _client_run(int(args[args.find("--open-world-delve-client") + 1]))
	elif args.has("--open-world-delve-idle"):
		await _idle_run(int(args[args.find("--open-world-delve-idle") + 1]))
	else:
		await _host_run()
