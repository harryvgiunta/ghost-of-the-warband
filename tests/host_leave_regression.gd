extends SceneTree
## Two real ENet processes: a host opens the world, a guest joins and follows it
## below into the delve, then the host's session disappears. The guest must get
## its own body back standing in the world - not falling through it - and the
## quick menu must already be open so it can save or quit.

const TRACE := "user://host_leave_client.txt"
const CLIENT_READY := "in_delve"

var game
var session
var child_pid := -1
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("HOST_LEAVE_FAIL  ",message)

func _wait_until(predicate: Callable, timeout: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

func _trace_text() -> String:
	return FileAccess.get_file_as_string(TRACE) if FileAccess.file_exists(TRACE) else ""

func _clear_trace() -> void:
	if FileAccess.file_exists(TRACE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE))

func _report() -> Dictionary:
	var result := {}
	for line in _trace_text().split("\n",false):
		var split := line.split("=",true,1)
		if split.size() == 2:
			result[split[0].strip_edges()] = split[1].strip_edges()
	return result

func run() -> void:
	session = root.get_node_or_null("Session")
	if session == null:
		session = load("res://scripts/session.gd").new()
		session.name = "Session"
		root.add_child(session)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and str(args[0]) == "--host-leave-client":
		await _client_run(int(str(args[1])))
		return
	await _host_run()

func _host_run() -> void:
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK,"The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	session.arm_world("world-host","127.0.0.1",port,"Host")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var hosted := await _wait_until(func(): return game.network_role == "host",8.0)
	check(hosted,"The host opens the open world")
	if not hosted:
		await _finish()
		return
	var client_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",get_script().resource_path,"--","--host-leave-client",str(port)])
	child_pid = OS.create_process(OS.get_executable_path(),client_args)
	check(child_pid > 0,"The guest process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2,25.0)
	check(joined,"A real ENet guest joins the open world")
	if not joined:
		print("CLIENT_TRACE:\n",_trace_text())
		await _finish()
		return
	# The host's own fall opens the run inside the session; the guest follows it
	# down on the connection it already has, which is what freezes its frontier.
	game.player.global_position = Vector3(16.0,3.8,42.0)
	game.player.velocity = Vector3.ZERO
	var entered := await _wait_until(func(): return game._delve_inner != null,10.0)
	check(entered,"The host's fall opens the run inside the session")
	var guest_in := await _wait_until(func(): return _trace_text().begins_with(CLIENT_READY),35.0)
	check(guest_in,"The guest is seated below in the delve")
	if not guest_in:
		print("CLIENT_TRACE:\n",_trace_text())
		await _finish()
		return
	# The host's session goes away: the socket is closed exactly as it is when
	# the host closes the game, so every guest sees the server disappear.
	game.multiplayer.multiplayer_peer.close()
	var reported := await _wait_until(func(): return _report().has("layer"),25.0)
	check(reported,"The guest reports after the host vanished")
	var report := _report()
	if not reported:
		print("CLIENT_TRACE:\n",_trace_text())
		await _finish()
		return
	check(str(report.get("delve_inner","true")) == "false","The guest is back in the open world")
	check(str(report.get("pointer_is_anchor","false")) == "true","The guest owns its own body again")
	check(str(report.get("layer","0")) == "4","The guest body stands on the world layer")
	check(str(report.get("mask","0")) == "3","The guest body collides with the world and the mobs")
	check(str(report.get("on_floor","false")) == "true","The guest stands on the floor")
	var drop := float(report.get("y0","-999")) - float(report.get("y1","-999"))
	check(absf(drop) < 0.2 and float(report.get("y1","-999")) > 1.0,"The guest holds its height instead of falling")
	check(str(report.get("menu_open","false")) == "true","The quick menu opens by itself when the host is lost")
	check(str(report.get("menu_exit","")) == "EXIT TO TITLE","The lost-session menu offers the way out")
	await _finish()

func _finish() -> void:
	_clear_trace()
	print("HOST_LEAVE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _client_run(port: int) -> void:
	session.arm_world("world-join","127.0.0.1",port,"Guest")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var joined := await _wait_until(func(): return main.local_slot == 1,25.0)
	if not joined:
		print("HOST_LEAVE_CLIENT join timeout")
		quit(1)
		return
	var open := await _wait_until(func(): return int(session.delve_open_port) == port,30.0)
	if not open:
		print("HOST_LEAVE_CLIENT no delve port")
		quit(1)
		return
	main.player.global_position = Vector3(16.0,2.2,42.0)
	main.player.velocity = Vector3.ZERO
	var arrived := await _wait_until(func(): return main._delve_inner != null,30.0)
	if not arrived:
		print("HOST_LEAVE_CLIENT no inner delve")
		quit(1)
		return
	var seated := await _wait_until(func(): return main._delve_inner.local_slot == 1,10.0)
	if not seated:
		print("HOST_LEAVE_CLIENT not seated")
		quit(1)
		return
	var file := FileAccess.open(TRACE,FileAccess.WRITE)
	file.store_line(CLIENT_READY)
	file.close()
	var lost := await _wait_until(func(): return main.network_role == "offline",30.0)
	if not lost:
		print("HOST_LEAVE_CLIENT never lost the host")
		quit(1)
		return
	await create_timer(1.0).timeout
	var first: Vector3 = main.player.global_position
	var on_floor: bool = main.player.is_on_floor()
	await create_timer(1.0).timeout
	var second: Vector3 = main.player.global_position
	var menu = main.pause_menu
	var lines := PackedStringArray()
	lines.append("delve_inner=%s" % str(main._delve_inner != null))
	lines.append("pointer_is_anchor=%s" % str(main.player == main._anchor_player))
	lines.append("layer=%d" % main.player.collision_layer)
	lines.append("mask=%d" % main.player.collision_mask)
	lines.append("on_floor=%s" % str(on_floor and main.player.is_on_floor()))
	lines.append("y0=%.3f" % first.y)
	lines.append("y1=%.3f" % second.y)
	lines.append("menu_open=%s" % str(menu != null and menu.is_open()))
	lines.append("menu_exit=%s" % str(menu.exit_button.text if menu != null else ""))
	var out := FileAccess.open(TRACE,FileAccess.WRITE)
	out.store_string("\n".join(lines))
	out.close()
	print("HOST_LEAVE_CLIENT report\n","\n".join(lines))
	quit(0)
