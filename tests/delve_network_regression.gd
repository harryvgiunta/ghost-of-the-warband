extends SceneTree
## Two real ENet processes: the host opens the delve, the client joins, both see
## the ritual, the weighted wave, the cache, and the descent into the ossuary.

const TEST_SAVE := "user://delve_network_regression_state.json"
const TRACE_PATH := "user://delve_net_client_trace.txt"
const SPAWN_SCALE := 8.0
const REPLICATION_GRACE_MS := 800

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
		print("DELVE_NET_FAIL  ",message)

func _remove_test_save() -> void:
	for path in [TEST_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

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

## The run state is the only surface that carries the ritual clock; reach_phase
## wraps it on both peers, so fall back to the replicated copy if it moves.
func _run_state(delve) -> Dictionary:
	if delve.has_method("reach_phase"):
		var now = delve.reach_phase()
		if now is Dictionary:
			return now
	var remote = delve.get("_remote_state")
	if remote is Dictionary:
		return remote
	return {}

## Kill every live devil once the snapshots had a chance to replicate it, so the
## client really observes the wave instead of a locally erased spawn.
func _clear_host_wave(delve, timeout: float) -> Dictionary:
	var first_seen: Dictionary = {}
	var spawned := 0
	var sealed_seen := false
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var now := Time.get_ticks_msec()
		if delve.phase == "WAVE" and bool(delve.world.sealed):
			sealed_seen = true
		for devil in delve.devils.duplicate():
			if not is_instance_valid(devil) or not devil.alive:
				continue
			var key: int = devil.get_instance_id()
			if not first_seen.has(key):
				first_seen[key] = now
				spawned += 1
			if now - int(first_seen[key]) >= REPLICATION_GRACE_MS:
				devil.take_damage(99999.0,-1)
		if delve.phase == "CLEARED":
			break
		await process_frame
	return {"cleared":delve.phase == "CLEARED","spawned":spawned,"sealed_seen":sealed_seen}

class Report:
	extends Node
	signal submitted(payload: Dictionary)
	@rpc("any_peer","call_remote","reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

func _store_report(payload: Dictionary) -> void:
	if payload.has("client_error"):
		reports["client_error"] = str(payload["client_error"])
	elif bool(payload.get("depth3",false)):
		reports["depth3"] = payload
	elif bool(payload.get("depth2",false)):
		reports["depth2"] = payload
	elif bool(payload.get("open",false)):
		reports["open"] = payload
	elif bool(payload.get("cleared",false)):
		reports["cleared"] = payload

func _host_run() -> void:
	_remove_test_save()
	_clear_trace()
	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK,"Network fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	session.arm_delve("delve-host","127.0.0.1",port,"Delve host")
	game = load("res://delve.tscn").instantiate()
	root.add_child(game)
	var report := Report.new()
	report.name = "DelveNetReport"
	report.submitted.connect(_store_report)
	root.add_child(report)
	var hosted := await _wait_until(func(): return game.network_role == "host",6.0)
	check(hosted,"The host opens a delve server")
	check(game.phase == "ALTAR" and game.depth == 1,"The host starts at the sanctuary altar")
	check(str(game.world.room_kind) == "sanctuary","The first room is the sanctuary")
	check(not game.world.is_pentagram_active(),"The pentagram sleeps before the ritual")
	check(game.world.beacon_active("altar"),"The altar beacon is lit")
	game.spawn_time_scale = SPAWN_SCALE

	var child_args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"--script",get_script().resource_path,"--","--delve-client",str(port)])
	child_pid = OS.create_process(OS.get_executable_path(),child_args)
	check(child_pid > 0,"The client process starts")
	var joined := await _wait_until(func(): return game.get_human_count() == 2,10.0)
	check(joined,"A real ENet client joins the delve")
	check(int(game.actors[1].peer_id) > 1,"The host seats the client")
	check(game.actors[1].alive and game.actors[1].visible,"The joining delver is alive and visible")

	game.begin_wave()
	var ritual := await _wait_until(func(): return game.phase == "RITUAL",5.0)
	check(ritual,"Touching the altar starts the ritual")
	check(game.world.is_pentagram_active(),"The pentagram burns for the ritual")
	check(game.wave_plan().size() == 17,"The first wave plan holds seventeen enemies")
	var wave := await _wait_until(func(): return game.phase == "WAVE" and not game.devils.is_empty(),8.0)
	check(wave,"The ritual ends into the replicated wave")
	check(game.wave_total == 17,"The first wave totals seventeen enemies")

	var observed: Dictionary = await _clear_host_wave(game,40.0)
	check(bool(observed["cleared"]),"The host breaks the wave and reaches the cache phase")
	check(bool(observed["sealed_seen"]),"The room stays sealed during the wave")
	check(not game.world.sealed,"Clearing the wave unseals the room")
	check(int(observed["spawned"]) == 17,"Every planned devil spawned on the host")
	var cached := await _wait_until(func(): return game.phase == "CLEARED" and game.chest_ready and is_instance_valid(game.chest),8.0)
	check(cached,"The host spawns the cache after the clear delay")
	check(not game.world.is_pentagram_active(),"The pentagram dims when the wave clears")
	check(game.world.beacon_active("rope") and game.world.beacon_active("hole"),"The exit beacons light with the cache")

	var client_cleared := await _wait_until(func(): return reports.has("cleared") or reports.has("client_error"),10.0)
	if reports.has("client_error"):
		check(false,"Client reported an error: " + str(reports["client_error"]))
	if not client_cleared:
		print("CLIENT_TRACE:\n",_read_trace())
	check(client_cleared,"The client observes the cleared room and its cache")
	if reports.has("cleared"):
		var cleared_report: Dictionary = reports["cleared"]
		check(int(cleared_report.get("slot",-1)) == 1,"The client joined seat one")
		check(str(cleared_report.get("room","")) == "sanctuary","The client sees the sanctuary room")
		check(bool(cleared_report.get("saw_wave",false)),"The client saw the replicated devils")
		check(int(cleared_report.get("devils",0)) >= 1,"At least one devil reached the client")
		check(float(cleared_report.get("ritual",0.0)) > 0.0,"The client saw the ritual progress")
		check(bool(cleared_report.get("pentagram",false)),"The client saw the active pentagram")
		check(str(cleared_report.get("phase","")) == "CLEARED","The client reached the cleared phase")
		check(int(cleared_report.get("depth",0)) == 1,"The client sees depth one")
		check(bool(cleared_report.get("chest",false)),"The client sees the cache")
		check(bool(cleared_report.get("rope",false)) and bool(cleared_report.get("hole",false)),"The client sees the rope and hole open")
		check(bool(cleared_report.get("host_alive",false)),"The client sees the host alive")
		var client_roles: Array = cleared_report.get("roles",[])
		check(client_roles.has("imp") and client_roles.has("devil"),"The client replicates the cycle-one imps and devils")
		for role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
			check(client_roles.has(role),"The client replicates the cycle-one %s" % role)
		check(not client_roles.has("ranger"),"The first wave replicates no crimson clone")

	game.open_chest()
	check(game.chest_open,"The host opens the cache")
	var client_open := await _wait_until(func(): return reports.has("open") or reports.has("client_error"),8.0)
	check(client_open,"The client observes the opened cache")
	if reports.has("open"):
		var open_report: Dictionary = reports["open"]
		check(bool(open_report.get("chest_open",false)),"The client chest lid opens")
		check(bool(open_report.get("burst",false)),"The client fires the shared loot burst")

	game.descend_next_depth()
	check(game.depth == 2 and str(game.world.room_kind) == "ossuary","The host drops into the depth-two ossuary")
	check(game.phase == "DROP","The ossuary waits for the party to land")
	check(not game.world.is_rope_lowered() and not game.world.is_hole_open(),"The next depth resets the rope and hole")
	var client_depth := await _wait_until(func(): return reports.has("depth2") or reports.has("client_error"),10.0)
	check(client_depth,"The client observes the descent")
	if reports.has("depth2"):
		var depth_report: Dictionary = reports["depth2"]
		check(int(depth_report.get("depth",0)) == 2,"The client sees depth two")
		check(str(depth_report.get("room","")) == "ossuary","The client sees the ossuary")
		var client_phase := str(depth_report.get("phase",""))
		check(client_phase == "DROP" or client_phase == "RITUAL" or client_phase == "WAVE","The client leaves the altar phase behind")
		check(not bool(depth_report.get("rope",true)) and not bool(depth_report.get("hole",true)),"The next round keeps the rope and hole closed")

	var ossuary_wave := await _wait_until(func(): return game.phase == "WAVE",20.0)
	check(ossuary_wave,"The ossuary starts its seventeen-enemy wave")
	var observed_two: Dictionary = await _clear_host_wave(game,45.0)
	check(bool(observed_two["cleared"]),"The host clears the ossuary")
	game.descend_next_depth()
	check(game.depth == 3 and str(game.world.room_kind) == "sanctuary","The host reaches the cycle-two sanctuary")
	game.begin_wave()
	var wave_three := await _wait_until(func(): return game.phase == "WAVE",10.0)
	check(wave_three,"The cycle-two sanctuary starts its wave")
	var client_depth3 := await _wait_until(func(): return reports.has("depth3") or reports.has("client_error"),45.0)
	check(client_depth3,"The client observes the cycle-two wave")
	if reports.has("depth3"):
		var roles_three: Array = reports["depth3"].get("roles",[])
		for role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
			check(roles_three.has(role),"The client replicates the %s in cycle two" % role)
		check(roles_three.has("ranger"),"The client replicates the crimson ranger clone")
		check(bool(reports["depth3"].get("species_visuals",false)),"The client builds the imported species rigs in cycle two")

	await _print_and_quit()

func _print_and_quit() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	game.leave_game()
	game.queue_free()
	await process_frame
	_remove_test_save()
	print("DELVE_NETWORK_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _client_run(port: int) -> void:
	session.arm_delve("delve-join","127.0.0.1",port,"Delve client")
	game = load("res://delve.tscn").instantiate()
	root.add_child(game)
	var report := Report.new()
	report.name = "DelveNetReport"
	root.add_child(report)
	_trace("client scene added")
	var joined := await _wait_until(func(): return game.local_slot == 1,10.0)
	_trace("joined=" + str(joined) + " slot=" + str(game.local_slot))
	if not joined:
		report.submit.rpc_id(1,{"client_error":"join timeout"})
		await _finish_client(1)
		return
	print("DELVE_NET_CLIENT joined slot=",game.local_slot)
	var saw_wave := false
	var devils_seen := 0
	var roles_seen := {}
	var species_visuals := true
	var ritual_seen := 0.0
	var pentagram_seen := false
	var cleared_sent := false
	var open_sent := false
	var depth_sent := false
	var depth3_sent := false
	var last_phase := ""
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		if game.world != null:
			ritual_seen = maxf(ritual_seen,float(_run_state(game).get("ritual",0.0)))
			pentagram_seen = pentagram_seen or bool(game.world.is_pentagram_active())
		if game.phase != last_phase:
			last_phase = game.phase
			var replica_count := 0
			for devil in game._devil_nodes.values():
				if is_instance_valid(devil) and devil.alive:
					replica_count += 1
			_trace("phase=" + last_phase + " depth=" + str(game.depth) + " devils=" + str(replica_count) + " chest=" + str(is_instance_valid(game.chest)))
			print("DELVE_NET_CLIENT phase=",last_phase," depth=",game.depth)
		if game.phase == "GAME_OVER":
			break
		if game.phase == "WAVE":
			var replicas := 0
			for devil in game._devil_nodes.values():
				if is_instance_valid(devil) and devil.alive:
					replicas += 1
					var role := str(devil.role())
					roles_seen[role] = true
					if role in ["hell_goat","succubus","spawn","beast","gargoyle"] and str(devil._visual_kind) != "mob":
						species_visuals = false
			if replicas > 0:
				saw_wave = true
				devils_seen = maxi(devils_seen,replicas)
		if game.phase == "CLEARED" and game.chest_ready and is_instance_valid(game.chest) and not cleared_sent:
			cleared_sent = true
			_trace("sending cleared report")
			report.submit.rpc_id(1,{"cleared":true,"slot":game.local_slot,
				"saw_wave":saw_wave,"devils":devils_seen,"phase":game.phase,"depth":game.depth,
				"chest":is_instance_valid(game.chest),"host_alive":game.actors[0].alive,
				"room":str(game.world.room_kind),"ritual":ritual_seen,"pentagram":pentagram_seen,
				"rope":game.world.is_rope_lowered(),"hole":game.world.is_hole_open(),
				"roles":roles_seen.keys(),"species_visuals":species_visuals})
		if cleared_sent and is_instance_valid(game.chest) and game.chest.is_opened() and not open_sent:
			open_sent = true
			_trace("sending open report")
			var burst := game.chest.get_node_or_null("LootBurst") as CPUParticles3D
			report.submit.rpc_id(1,{"open":true,"chest_open":game.chest_open,
				"burst":burst != null and burst.emitting})
		if open_sent and game.depth == 2 and game.phase in ["DROP","RITUAL","WAVE"] and not depth_sent:
			depth_sent = true
			_trace("sending depth report")
			report.submit.rpc_id(1,{"depth2":true,"depth":game.depth,"phase":game.phase,
				"room":str(game.world.room_kind),
				"rope":game.world.is_rope_lowered(),"hole":game.world.is_hole_open()})
			await create_timer(0.6).timeout
		if depth_sent and game.depth == 3 and game.phase == "WAVE" and not depth3_sent:
			var species_count := 0
			for role in ["hell_goat","succubus","spawn","beast","gargoyle"]:
				if roles_seen.has(role):
					species_count += 1
			if species_count >= 5 and roles_seen.has("ranger"):
				depth3_sent = true
				_trace("sending depth3 report")
				report.submit.rpc_id(1,{"depth3":true,"roles":roles_seen.keys(),
					"species_visuals":species_visuals})
				await create_timer(0.6).timeout
				break
		await process_frame
	if not cleared_sent:
		_trace("failed to reach cleared; phase=" + str(game.phase))
		report.submit.rpc_id(1,{"client_error":"never reached cleared; phase=" + str(game.phase)})
	await _finish_client(0 if cleared_sent else 1)

func _finish_client(code: int) -> void:
	game.leave_game()
	game.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	session = root.get_node_or_null("Session")
	check(session != null,"The Session autoload exists")
	var args := OS.get_cmdline_user_args()
	if args.has("--delve-client"):
		await _client_run(int(args[args.find("--delve-client") + 1]))
	else:
		await _host_run()
